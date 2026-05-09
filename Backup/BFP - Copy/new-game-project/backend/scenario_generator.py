"""NLP-powered scenario generator.

Loads scenario templates from ``scenarios_bank.json`` and assembles
randomised, locale-aware emergency scenarios for the Godot frontend.
"""

import json
import os
import random
from typing import Any, Dict, List, Optional

DEFAULT_BANK = os.path.join(os.path.dirname(__file__), "scenarios_bank.json")


class ScenarioGenerator:
    """Generate randomised emergency scenarios from the template bank.

    Parameters
    ----------
    bank_path : str, optional
        Path to the ``scenarios_bank.json`` file.
    """

    def __init__(self, bank_path: Optional[str] = None) -> None:
        self.bank_path = bank_path or DEFAULT_BANK
        self._bank: Dict[str, Any] = {}
        self._load_bank()

    # ── Loading ──────────────────────────────────────────────────────
    def _load_bank(self) -> None:
        try:
            with open(self.bank_path, "r", encoding="utf-8") as f:
                self._bank = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError) as e:
            print(f"[ScenarioGenerator] Failed to load bank: {e}")
            self._bank = {"scenarios": [], "locations_ph": []}

    @property
    def scenarios(self) -> List[Dict]:
        return self._bank.get("scenarios", [])

    @property
    def locations(self) -> List[str]:
        return self._bank.get("locations_ph", [])

    # ── Category helpers ─────────────────────────────────────────────
    def get_categories(self) -> List[str]:
        """Return the distinct category values available."""
        return sorted({s["category"] for s in self.scenarios})

    def get_scenario_ids(self, category: Optional[str] = None) -> List[str]:
        pool = self.scenarios
        if category:
            pool = [s for s in pool if s["category"] == category]
        return [s["id"] for s in pool]

    def get_scenario_by_id(self, scenario_id: str) -> Optional[Dict]:
        for s in self.scenarios:
            if s["id"] == scenario_id:
                return s
        return None

    # ── Generation ───────────────────────────────────────────────────
    def generate(
        self,
        category: Optional[str] = None,
        difficulty: str = "easy",
        locale: str = "en",
    ) -> Dict[str, Any]:
        """Generate a complete scenario ready for the Godot front-end.

        Parameters
        ----------
        category : str or None
            Filter by category (``"fire"``, ``"medical"``, ``"criminal"``,
            ``"natural_disaster"``).  ``None`` picks randomly.
        difficulty : str
            ``"easy"`` → includes 3 multiple-choice options with hints.
            ``"certified"`` → typed-response mode (no options).
        locale : str
            ``"en"`` for English, ``"tl"`` for Tagalog, ``"taglish"`` for mixed.
        """
        pool = self.scenarios
        if category:
            pool = [s for s in pool if s["category"] == category]

        if not pool:
            return self._fallback(locale)

        template = random.choice(pool)
        location = random.choice(self.locations) if self.locations else "Unknown location"

        return self._assemble(template, location, difficulty, locale)

    # ── Assembly ─────────────────────────────────────────────────────
    def _assemble(
        self,
        template: Dict,
        location: str,
        difficulty: str,
        locale: str,
    ) -> Dict[str, Any]:
        """Build a scenario dict from a template + location."""

        # Pick text field suffix based on locale
        tl = locale in ("tl", "taglish")
        text_key = "text_tl" if tl else "text"
        title_key = "title_tl" if tl else "title"
        hint_key = "hint_tl" if tl else "hint"
        explanation_key = "explanation_tl" if tl else "explanation"

        # Build transcript
        transcript = []
        if "transcript_templates" in template:
            for line in template.get("transcript_templates", []):
                raw = line.get(text_key, line.get("text", ""))
                transcript.append({
                    "speaker": line["speaker"],
                    "text": raw.replace("{location}", location),
                })
        else:
            transcript = list(template.get("transcript", []))

        # Build options (Easy mode only)
        options = []
        if difficulty != "certified":
            raw_options = list(template.get("options", []))
            random.shuffle(raw_options)
            for opt in raw_options:
                options.append({
                    "text": opt.get(text_key, opt.get("text", "")),
                    "label": opt["label"],
                    "hint": opt.get(hint_key, opt.get("hint", "")),
                    "explanation": opt.get(explanation_key, opt.get("explanation", "")),
                })

        # Determine recommended vehicle
        category = template.get("category", "fire")
        vehicle_map = {
            "fire": "fire_truck",
            "medical": "ambulance",
            "criminal": "police",
            "natural_disaster": "rescue",
        }

        scenario = {
            "id": f"{template.get('id', 'gen')}_{random.randint(1000, 9999)}",
            "template_id": template.get("id", "fallback"),
            "mode": "easy_multiple_choice" if difficulty != "certified" else "certified_nlp_dispatch",
            "type": category,
            "severity": template.get("severity", random.choice(["low", "medium", "high"])),
            "title": template.get("title", template.get(title_key, "Emergency")),
            "location": template.get("location", location),
            "recommended_vehicle": template.get("recommended_vehicle", vehicle_map.get(category, "ambulance")),
            "transcript": transcript,
            "options": options,
            "safe_keywords": template.get("safe_keywords", []),
            "unsafe_keywords": template.get("unsafe_keywords", []),
            "locale": locale,
        }
        return scenario

    # ── Fallback ─────────────────────────────────────────────────────
    def _fallback(self, locale: str) -> Dict[str, Any]:
        """Minimal fallback scenario when no templates are available."""
        return {
            "id": f"fallback_{random.randint(1000, 9999)}",
            "template_id": "fallback",
            "mode": "easy_multiple_choice",
            "type": "fire",
            "severity": "medium",
            "title": "Emergency Drill" if locale == "en" else "Emergency Drill (Practice)",
            "location": "Training Center",
            "recommended_vehicle": "fire_truck",
            "transcript": [
                {"speaker": "911", "text": "911, what is your emergency?"},
                {"speaker": "Caller", "text": "This is a practice drill."},
            ],
            "options": [
                {
                    "text": "Stay calm and follow instructions.",
                    "label": "safe",
                    "hint": "Staying calm is always the best first step!",
                    "explanation": "Keeping a clear head helps you make better decisions in an emergency.",
                }
            ],
            "safe_keywords": ["calm", "follow"],
            "unsafe_keywords": [],
            "locale": locale,
        }


if __name__ == "__main__":
    gen = ScenarioGenerator()
    print("Available categories:", gen.get_categories())
    print("Generating a random scenario...\n")
    s = gen.generate()
    print(json.dumps(s, indent=2, ensure_ascii=False))
