import json
import threading
import time
from contextlib import contextmanager
from typing import Dict

import psycopg2
from psycopg2.extras import RealDictCursor, Json
from psycopg2.pool import ThreadedConnectionPool

from core.config import DATABASE_URL

JOB_RETENTION_HOURS = 24
JOB_CLEANUP_INTERVAL_SECONDS = 3600

# Connection pool: min 2, max 10 connections
_pool = None
_pool_lock = threading.Lock()


def _get_pool():
    """Lazy-initialize the connection pool (thread-safe)."""
    global _pool
    if _pool is None:
        with _pool_lock:
            if _pool is None:
                _pool = ThreadedConnectionPool(minconn=2, maxconn=10, dsn=DATABASE_URL)
    return _pool


@contextmanager
def get_db_connection():
    """Context manager that gets a connection from the pool and returns it on exit."""
    pool = _get_pool()
    conn = pool.getconn()
    try:
        yield conn
    finally:
        pool.putconn(conn)


def init_db():
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT EXISTS (
                    SELECT FROM information_schema.tables 
                    WHERE table_name = 'simulation_jobs'
                );
                """
            )
            exists = cursor.fetchone()[0]
            if exists:
                print("[DB] simulation_jobs table verified in PostgreSQL")
            else:
                print("[DB] simulation_jobs table not found, creating fallback...")
                cursor.execute(
                    """
                    CREATE TABLE IF NOT EXISTS simulation_jobs (
                        id TEXT PRIMARY KEY,
                        status TEXT NOT NULL DEFAULT 'queued',
                        result TEXT,
                        error TEXT,
                        config TEXT,
                        "userId" INT,
                        "createdAt" TIMESTAMP NOT NULL DEFAULT NOW(),
                        "updatedAt" TIMESTAMP NOT NULL DEFAULT NOW()
                    )
                    """
                )
                conn.commit()
                print("[DB] simulation_jobs fallback table created")
    except Exception as exc:
        print(f"[ERROR] Database connection failed: {exc}")
        print("[HINT] Ensure PostgreSQL is running and DATABASE_URL is correct")


def update_job_status(job_id: str, status: str, result: Dict = None, error: str = None):
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            # Use psycopg2 Json adapter for jsonb columns
            result_value = Json(result) if result is not None else None
            cursor.execute(
                """
                INSERT INTO simulation_jobs (id, status, result, error, "createdAt", "updatedAt")
                VALUES (%s, %s, %s, %s, NOW(), NOW())
                ON CONFLICT (id) DO UPDATE SET
                    status = EXCLUDED.status,
                    result = EXCLUDED.result,
                    error = EXCLUDED.error,
                    "updatedAt" = NOW()
                """,
                (job_id, status, result_value, error),
            )
            conn.commit()
    except Exception as exc:
        print(f"[DB ERROR] Failed to update job {job_id}: {exc}", flush=True)
        try:
            with get_db_connection() as conn:
                cursor = conn.cursor()
                result_value = Json(result) if result is not None else None
                cursor.execute(
                    """
                    INSERT INTO simulation_jobs (id, status, result, error, "createdAt", "updatedAt")
                    VALUES (%s, %s, %s, %s, NOW(), NOW())
                    ON CONFLICT (id) DO UPDATE SET
                        status = EXCLUDED.status,
                        result = EXCLUDED.result,
                        error = EXCLUDED.error,
                        "updatedAt" = NOW()
                    """,
                    (job_id, status, result_value, error),
                )
                conn.commit()
        except Exception as exc2:
            print(f"[DB ERROR] Retry also failed: {exc2}", flush=True)


def get_job_status(job_id: str) -> Dict:
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor(cursor_factory=RealDictCursor)
            cursor.execute(
                """
                SELECT status, result, error 
                FROM simulation_jobs 
                WHERE id = %s
                """,
                (job_id,),
            )
            row = cursor.fetchone()

            if not row:
                return {"status": "not_found", "result": None, "error": "Job not found"}

            # psycopg2 auto-deserializes jsonb columns to Python dicts
            # so no json.loads() needed
            result_data = row["result"]
            if isinstance(result_data, str):
                # Fallback: if somehow stored as text, parse it
                result_data = json.loads(result_data)

            return {
                "status": row["status"],
                "result": result_data,
                "error": row["error"],
            }
    except Exception as exc:
        print(f"[DB ERROR] Failed to get job {job_id}: {exc}", flush=True)
        return {"status": "error", "result": None, "error": f"Database error: {exc}"}


def cleanup_old_jobs():
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                DELETE FROM simulation_jobs 
                WHERE "createdAt" < NOW() - INTERVAL '%s hours'
                AND status IN ('complete', 'failed')
                """,
                (JOB_RETENTION_HOURS,),
            )
            deleted = cursor.rowcount
            conn.commit()
            if deleted > 0:
                print(f"[CLEANUP] Deleted {deleted} old simulation jobs", flush=True)
    except Exception as exc:
        print(f"[CLEANUP ERROR] Failed to cleanup jobs: {exc}", flush=True)


def _job_cleanup_loop():
    time.sleep(60)
    while True:
        cleanup_old_jobs()
        time.sleep(JOB_CLEANUP_INTERVAL_SECONDS)


def start_cleanup_thread():
    cleanup_thread = threading.Thread(target=_job_cleanup_loop, daemon=True)
    cleanup_thread.start()
    print("[CLEANUP] Background job cleanup thread started (runs every hour)")
