"""Tagalog / Taglish text utilities for the NLP pipeline.

Provides normalisation helpers so the classifier can understand
Filipino-language emergency advice (pure Tagalog or code-switched Taglish).
"""

import re
from typing import Dict, Tuple

# ── Tagalog → English phrase map ────────────────────────────────────────
# Maps common Tagalog / Taglish emergency-related words or phrases
# to their English equivalents for phrase-matching in the NLP classifier.
TAGALOG_PHRASE_MAP: Dict[str, str] = {
    # Fire-related
    "sunog": "fire",
    "apoy": "fire",
    "bumbero": "firefighter",
    "kawali": "pan",
    "kalan": "stove",
    "mantika": "grease",
    "tubig": "water",
    "buhusan ng tubig": "pour water",
    "itapon ang tubig": "throw water",
    "wisikan ng tubig": "spray water",
    "takpan": "cover with a lid",
    "takpan mo": "cover with a lid",
    "takpan ng takip": "cover with a lid",
    "lagyan ng takip": "cover with a lid",
    "patay": "turn off",
    "patayin": "turn off",
    "patayin ang kalan": "turn off the stove",
    "patayin ang apoy": "put out fire",
    "fire extinguisher": "use fire extinguisher",
    "pamatay apoy": "use fire extinguisher",
    "baking soda": "baking soda",
    "dalhin sa labas": "move outside",
    "ilabas": "move outside",
    "buhat": "carry",

    # Electrical
    "kuryente": "electricity",
    "wire": "wire",
    "outlet": "outlet",
    "hawakan ang wire": "touch wire",
    "i-plug out": "unplug",
    "tanggalin sa saksakan": "unplug",
    "patayin ang kuryente": "turn off power",
    "patayin ang switch": "turn off",

    # Gas
    "gas": "gas",
    "amoy ng gas": "gas leak",
    "posporo": "match",
    "magsindi": "light a match",
    "sindi": "light a match",
    "spark": "spark",
    "buksan ang bintana": "open windows",
    "buksan bintana": "open windows",

    # Medical
    "dugo": "blood",
    "sugat": "wound",
    "nahiwa": "cut",
    "iditin": "apply pressure",
    "diin": "pressure",
    "tela": "cloth",
    "bendahe": "bandage",
    "ambulansya": "ambulance",
    "ospital": "hospital",
    "gamot": "medicine",
    "alkohol": "alcohol",
    "bumagsak": "collapsed",
    "walang malay": "unconscious",
    "hindi humihinga": "not breathing",
    "nabulunan": "choking",
    "heimlich": "heimlich",
    "paghinga": "breathing",
    "CPR": "cpr",

    # Criminal
    "pulis": "police",
    "holdap": "robbery",
    "holdaper": "robber",
    "armas": "weapon",
    "nakatago": "hiding",
    "tago": "hide",
    "tumawag ng pulis": "call police",

    # Natural disaster
    "lindol": "earthquake",
    "baha": "flood",
    "bagyo": "typhoon",
    "lumikas": "evacuate",
    "ilikas": "evacuate",
    "likas": "evacuate",
    "mataas na lugar": "higher ground",
    "tulong": "help",
    "rescue": "rescue",

    # General emergency
    "tawag 911": "dispatch help",
    "tumawag ng 911": "dispatch help",
    "i-call ang 911": "dispatch help",
    "tumawag sa hotline": "call hotline",
    "emergency": "emergency",
    "lumikas": "evacuate",
    "ligtas": "safe",
    "panganib": "danger",
    "delikado": "dangerous",
}

# ── Tagalog negation words ──────────────────────────────────────────────
TAGALOG_NEGATIONS = {
    "huwag",
    "wag",
    "hindi",
    "di",
    "bawal",
    "iwasan",
    "wag mo",
    "huwag mo",
    "hindi dapat",
    "ayaw",
}

# ── Tagalog word set for language detection ─────────────────────────────
_TAGALOG_COMMON_WORDS = {
    "ang", "ng", "sa", "na", "at", "mo", "ko", "ka", "ba", "po",
    "opo", "naman", "din", "rin", "yung", "yun", "yon", "siya",
    "sila", "kami", "tayo", "nila", "niya", "namin", "natin",
    "dito", "doon", "diyan", "paano", "bakit", "ano", "sino",
    "kailan", "saan", "may", "mga", "lang", "lamang", "pa",
    "pala", "kasi", "dahil", "para", "ito", "iyon", "iyan",
    "ganito", "ganyan", "ganoon", "meron", "wala", "oo", "hindi",
    "huwag", "wag",
}


def normalize_taglish(text: str) -> str:
    """Normalise mixed Filipino / English text for NLP processing.

    Steps:
      1. Lowercase
      2. Strip non-word characters (keep apostrophes)
      3. Collapse whitespace
      4. Replace known Tagalog/Taglish phrases with English equivalents
         (longest-match-first to handle multi-word entries)
    """
    t = text.lower()
    t = re.sub(r"[^\w\s']", " ", t)
    t = re.sub(r"\s+", " ", t).strip()

    # Sort by phrase length descending so multi-word phrases match first
    sorted_phrases = sorted(TAGALOG_PHRASE_MAP.keys(), key=len, reverse=True)
    for phrase in sorted_phrases:
        pattern = r"\b" + re.escape(phrase) + r"\b"
        replacement = TAGALOG_PHRASE_MAP[phrase]
        t = re.sub(pattern, replacement, t)

    # Collapse whitespace again after replacements
    t = re.sub(r"\s+", " ", t).strip()
    return t


def detect_language(text: str) -> str:
    """Heuristic language detection for emergency-context text.

    Returns:
      ``"tl"`` – mostly Tagalog words detected
      ``"taglish"`` – mix of Tagalog and English words
      ``"en"`` – default (mostly English)
    """
    words = re.findall(r"[a-z]+", text.lower())
    if not words:
        return "en"

    tl_count = sum(1 for w in words if w in _TAGALOG_COMMON_WORDS)
    ratio = tl_count / len(words)

    if ratio >= 0.40:
        return "tl"
    if ratio >= 0.15:
        return "taglish"
    return "en"


def get_tagalog_negations() -> set:
    """Return the set of Tagalog negation tokens for the classifier."""
    return TAGALOG_NEGATIONS
