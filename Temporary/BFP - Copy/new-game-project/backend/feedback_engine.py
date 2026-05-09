"""Kid-friendly educational feedback engine.

Given a scenario and the player's choice (or typed answer), this module
produces age-appropriate hints, explanations, and encouragement messages.
"""

import os
import sys
from typing import Any, Dict, List, Optional

# Ensure project root is importable
_script_dir = os.path.dirname(os.path.abspath(__file__))
_project_root = os.path.dirname(_script_dir)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from backend.nlp_classifier import NLPClassifier
from backend.tagalog_utils import detect_language


class FeedbackEngine:
    """Produce kid-friendly feedback for emergency scenario responses.

    Works in two modes:

    1. **Multiple-choice** — uses the pre-authored hints / explanations
       stored in the scenario options.
    2. **Typed response** — delegates to :class:`NLPClassifier` and wraps
       the result with age-appropriate messaging.
    """

    # ── Encouragement pools ──────────────────────────────────────────
    _ENCOURAGEMENT = {
        "safe": {
            "en": [
                "Awesome job! You really know your emergency safety! 🌟",
                "That's the right call! You'd make a great dispatcher! 🎉",
                "Perfect! You kept everyone safe! Safety champion! 🏆",
                "Great thinking! You really know what to do in an emergency! 💪",
                "Exactly right! You're learning to save lives! ⭐",
            ],
            "tl": [
                "Ang galing mo! Alam mo talaga ang tamang gawin sa emergency! 🌟",
                "Tama yan! Magiging magaling kang dispatcher! 🎉",
                "Perpekto! Naprotektahan mo ang lahat! Safety champion! 🏆",
                "Mahusay ang pag-iisip mo! Alam mo ang gagawin sa emergency! 💪",
                "Eksakto! Natututo kang mag-save ng buhay! ⭐",
            ],
        },
        "unsafe": {
            "en": [
                "Good try, but that could be dangerous! Let's learn why. 💡",
                "Almost! That one is tricky. Here's what the experts say. 📖",
                "Nice effort! But there's a safer way to handle this. Let me explain! 🧠",
                "Don't worry — even adults get this wrong sometimes! Here's the safe answer. 🤗",
                "Keep learning! Every emergency expert started where you are now! 📚",
            ],
            "tl": [
                "Magandang tangka, pero baka delikado yan! Alamin natin kung bakit. 💡",
                "Malapit na! Medyo mahirap yan. Ito ang sabi ng mga eksperto. 📖",
                "Magaling ang effort! Pero may mas ligtas na paraan. Ipapaliwanag ko! 🧠",
                "Huwag mag-alala — kahit mga matatanda ay nagkakamali dito! Ito ang tamang sagot. 🤗",
                "Patuloy na matuto! Lahat ng emergency expert ay nagsimula sa kung nasaan ka ngayon! 📚",
            ],
        },
        "unknown": {
            "en": [
                "Hmm, I'm not sure about that one. Let's review the safe options together! 🤔",
                "Interesting answer! Let me share what emergency experts recommend. 📋",
            ],
            "tl": [
                "Hmm, hindi ako sigurado dyan. Pagusapan natin ang mga ligtas na opsyon! 🤔",
                "Kawili-wiling sagot! Ibabahagi ko kung ano ang inirerekomenda ng mga eksperto. 📋",
            ],
        },
    }

    def __init__(self) -> None:
        self._classifier = NLPClassifier()

    # ── Locale helpers ───────────────────────────────────────────────
    @staticmethod
    def _pick_locale_key(locale: str) -> str:
        return "tl" if locale in ("tl", "taglish") else "en"

    def _random_encouragement(self, label: str, locale: str) -> str:
        import random
        key = self._pick_locale_key(locale)
        label_key = label if label in self._ENCOURAGEMENT else "unknown"
        pool = self._ENCOURAGEMENT[label_key].get(key, self._ENCOURAGEMENT[label_key]["en"])
        return random.choice(pool)

    # ── Hints (before the player selects) ────────────────────────────
    def get_hints(
        self,
        scenario: Dict[str, Any],
        locale: str = "en",
    ) -> List[Dict[str, str]]:
        """Return a combined hint for the scenario (not per-option).

        The hint discusses the wrong options to guide the player toward
        the correct answer without revealing it directly.

        Returns a list of dicts: ``[{option_index, hint}]``
        """
        options = scenario.get("options", [])
        hints = []
        for i, opt in enumerate(options):
            hint_text = opt.get("hint", "")
            hints.append({
                "option_index": i,
                "option_text": opt.get("text", ""),
                "hint": hint_text,
            })
        return hints

    def get_combined_hint(
        self,
        scenario: Dict[str, Any],
        locale: str = "en",
    ) -> str:
        """Return a single combined guidance hint that nudges toward the right
        answer by explaining why the *wrong* options are problematic.

        This is the grease-fire-style hint the user described.
        """
        options = scenario.get("options", [])
        unsafe_hints = []
        safe_hint = ""

        for opt in options:
            if opt.get("label") == "unsafe":
                hint = opt.get("hint", "")
                if hint:
                    unsafe_hints.append(hint)
            elif opt.get("label") == "safe":
                safe_hint = opt.get("hint", "")

        parts = []
        for h in unsafe_hints:
            parts.append(h)

        if safe_hint:
            parts.append(safe_hint)

        if not parts:
            lk = self._pick_locale_key(locale)
            if lk == "tl":
                return "Isipin mabuti ang bawat opsyon bago pumili. Ligtas muna lagi! 🤔"
            return "Think carefully about each option before you choose. Safety first! 🤔"

        return "\n\n".join(parts)

    # ── Evaluate multiple-choice ─────────────────────────────────────
    def evaluate_choice(
        self,
        scenario: Dict[str, Any],
        chosen_index: int,
        locale: str = "en",
    ) -> Dict[str, str]:
        """Evaluate a multiple-choice selection and return feedback.

        Returns
        -------
        dict
            ``{label, explanation, encouragement}``
        """
        options = scenario.get("options", [])
        if chosen_index < 0 or chosen_index >= len(options):
            return {
                "label": "unknown",
                "explanation": "Invalid option selected.",
                "encouragement": self._random_encouragement("unknown", locale),
            }

        opt = options[chosen_index]
        label = opt.get("label", "unknown")
        explanation = opt.get("explanation", "No explanation available.")

        return {
            "label": label,
            "explanation": explanation,
            "encouragement": self._random_encouragement(label, locale),
        }

    # ── Evaluate typed response (NLP) ────────────────────────────────
    def evaluate_typed(
        self,
        scenario: Dict[str, Any],
        answer_text: str,
        locale: str = "en",
    ) -> Dict[str, Any]:
        """Classify a free-text response and wrap with kid-friendly feedback.

        Delegates to :class:`NLPClassifier` for the heavy lifting, then
        adds encouragement and age-appropriate explanation.
        """
        # Determine the NLP scenario key
        scenario_key = scenario.get("template_id", scenario.get("id", "grease_fire"))

        # Auto-detect locale from the answer text if ``taglish``
        if locale == "taglish":
            detected = detect_language(answer_text)
            if detected == "tl":
                locale = "tl"

        result = self._classifier.classify(answer_text, scenario_key)
        label = result.get("label", "unknown")

        # Build kid-friendly wrapper
        message = result.get("message", "")
        encouragement = self._random_encouragement(label, locale)

        # Find the correct option's explanation for additional context
        correct_explanation = ""
        for opt in scenario.get("options", []):
            if opt.get("label") == "safe":
                correct_explanation = opt.get("explanation", "")
                break

        feedback = {
            "label": label,
            "nlp_reason": result.get("reason", ""),
            "message": message,
            "encouragement": encouragement,
            "score": result.get("score", 0),
        }

        # If the answer was unsafe, also include what the right action is
        if label == "unsafe" and correct_explanation:
            lk = self._pick_locale_key(locale)
            if lk == "tl":
                feedback["correct_action"] = f"💡 Ang tamang gawin: {correct_explanation}"
            else:
                feedback["correct_action"] = f"💡 The right thing to do: {correct_explanation}"

        return feedback


if __name__ == "__main__":
    import json
    from backend.scenario_generator import ScenarioGenerator

    gen = ScenarioGenerator()
    engine = FeedbackEngine()

    # Generate a scenario and show hints + evaluation
    scenario = gen.generate(category="fire", locale="en")
    print("=== Scenario:", scenario["title"], "===")
    print()

    print("--- Combined Hint ---")
    print(engine.get_combined_hint(scenario))
    print()

    for i, opt in enumerate(scenario.get("options", [])):
        result = engine.evaluate_choice(scenario, i)
        print(f"Option {i}: {opt['text']}")
        print(f"  → {result['label']}: {result['explanation']}")
        print(f"  → {result['encouragement']}")
        print()
