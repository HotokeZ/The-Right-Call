"""Convert road GeoJSON (projected) to normalized point lists for Godot.

Input: data/santacruz_roads.geojson (produced by osm_extract_santacruz.py, in EPSG:3857)
Output: data/santacruz_roads_points.json with structure:
  {
    "bounds": [minx, miny, maxx, maxy],
    "points": [[x_norm, y_norm], ...]
  }

The normalized coordinates are in [0,1] relative to the bounding box. In Godot,
map normalized->pixels via x = x_norm * image_width; y = (1 - y_norm) * image_height
if the image origin is top-left.

Requires: geopandas, shapely
"""
from pathlib import Path
import json

try:
    import geopandas as gpd
    from shapely.geometry import LineString, Point
except Exception:
    raise RuntimeError("Please install geopandas and shapely to run this converter.")


def sample_linestring(ls: LineString, dist_step: float = 50.0):
    """Sample points along a linestring every `dist_step` units (meters in projected CRS)."""
    if ls.length == 0:
        return []
    pts = []
    d = 0.0
    while d <= ls.length:
        p = ls.interpolate(d)
        pts.append((p.x, p.y))
        d += dist_step
    # ensure last point
    p = ls.interpolate(ls.length)
    pts.append((p.x, p.y))
    return pts


def main():
    base = Path(__file__).resolve().parent.parent
    roads_path = base / "data" / "santacruz_roads.geojson"
    out_path = base / "data" / "santacruz_roads_points.json"
    if not roads_path.exists():
        raise FileNotFoundError(f"{roads_path} not found. Run tools/osm_extract_santacruz.py first.")

    gdf = gpd.read_file(roads_path)
    # ensure geometry is Linestring or multilinestring
    all_pts = []
    for geom in gdf.geometry:
        if geom is None:
            continue
        if geom.geom_type == 'LineString':
            all_pts.extend(sample_linestring(geom))
        elif geom.geom_type == 'MultiLineString':
            for ls in geom.geoms:
                all_pts.extend(sample_linestring(ls))

    if not all_pts:
        raise RuntimeError("No points sampled from roads; check the input GeoJSON.")

    xs = [p[0] for p in all_pts]
    ys = [p[1] for p in all_pts]
    minx, maxx = min(xs), max(xs)
    miny, maxy = min(ys), max(ys)

    width = maxx - minx
    height = maxy - miny
    pts_norm = []
    for x, y in all_pts:
        nx = (x - minx) / width if width != 0 else 0.0
        ny = (y - miny) / height if height != 0 else 0.0
        pts_norm.append([nx, ny])

    payload = {"bounds": [minx, miny, maxx, maxy], "points": pts_norm}
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)
    print(f"Wrote normalized points to {out_path} (total points: {len(pts_norm)})")


if __name__ == "__main__":
    main()
