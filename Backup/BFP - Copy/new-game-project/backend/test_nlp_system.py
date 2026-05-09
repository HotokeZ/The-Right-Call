"""Tests for the scenario generator, feedback engine, and Tagalog NLP support."""

import json
import os
import sys

# Ensure project root is importable
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from backend.scenario_generator import ScenarioGenerator
from backend.feedback_engine import FeedbackEngine
from backend.tagalog_utils import normalize_taglish, detect_language, get_tagalog_negations
from backend.nlp_classifier import NLPClassifier


def test_scenario_generator():
    print("=" * 60)
    print("TEST: Scenario Generator")
    print("=" * 60)

    gen = ScenarioGenerator()

    # Test categories
    cats = gen.get_categories()
    print(f"  Categories: {cats}")
    assert len(cats) >= 3, f"Expected >=3 categories, got {len(cats)}"

    # Test generation for each category
    for cat in cats:
        s = gen.generate(category=cat, locale="en")
        assert s.get("id"), f"Missing ID for category {cat}"
        assert s.get("type") == cat, f"Expected type={cat}, got {s.get('type')}"
        assert len(s.get("options", [])) >= 1, f"No options for {cat}"
        print(f"  ✓ Generated {cat}: {s['title']} ({len(s['options'])} options)")

    # Test Tagalog locale
    s_tl = gen.generate(category="fire", locale="tl")
    assert s_tl.get("locale") == "tl"
    print(f"  ✓ Tagalog scenario: {s_tl['title']}")

    # Test certified mode (no options)
    s_cert = gen.generate(difficulty="certified")
    assert len(s_cert.get("options", [])) == 0, "Certified mode should have no options"
    print(f"  ✓ Certified mode: no options")

    print("  ALL SCENARIO GENERATOR TESTS PASSED ✓\n")


def test_feedback_engine():
    print("=" * 60)
    print("TEST: Feedback Engine")
    print("=" * 60)

    gen = ScenarioGenerator()
    engine = FeedbackEngine()

    scenario = gen.generate(category="fire", locale="en")
    print(f"  Testing with scenario: {scenario['title']}")

    # Test hints
    hints = engine.get_hints(scenario)
    assert len(hints) > 0, "Should have hints"
    for h in hints:
        assert h.get("hint"), f"Missing hint text for option {h.get('option_index')}"
    print(f"  ✓ Got {len(hints)} hints")

    # Test combined hint
    combined = engine.get_combined_hint(scenario)
    assert len(combined) > 20, "Combined hint should be substantial"
    print(f"  ✓ Combined hint: {combined[:80]}...")

    # Test evaluate_choice
    for i, opt in enumerate(scenario.get("options", [])):
        result = engine.evaluate_choice(scenario, i)
        assert result.get("label") in ("safe", "unsafe", "unknown"), f"Bad label: {result}"
        assert result.get("explanation"), "Missing explanation"
        assert result.get("encouragement"), "Missing encouragement"
        label_emoji = "✅" if result["label"] == "safe" else "❌"
        print(f"  {label_emoji} Option {i}: {result['label']}")

    # Test evaluate_typed (English)
    typed_result = engine.evaluate_typed(scenario, "cover with a lid and call 911")
    assert typed_result.get("label") in ("safe", "unsafe", "unknown")
    print(f"  ✓ Typed evaluation: {typed_result['label']} (score={typed_result.get('score')})")

    print("  ALL FEEDBACK ENGINE TESTS PASSED ✓\n")


def test_tagalog_support():
    print("=" * 60)
    print("TEST: Tagalog / Taglish Support")
    print("=" * 60)

    # Test normalization
    assert "water" in normalize_taglish("buhusan ng tubig")
    assert "cover with a lid" in normalize_taglish("takpan mo ng lid")
    assert "call 911" in normalize_taglish("tumawag ng 911")
    assert "evacuate" in normalize_taglish("lumikas")
    print("  ✓ Tagalog phrase normalization works")

    # Test language detection
    assert detect_language("Put water on the fire") == "en"
    assert detect_language("Buhusan ng tubig ang apoy sa kusina namin") == "tl"
    assert detect_language("I-cover mo na lang ang pan para patay ang fire") in ("taglish", "tl")
    print("  ✓ Language detection works")

    # Test negations
    negs = get_tagalog_negations()
    assert "huwag" in negs
    assert "wag" in negs
    assert "hindi" in negs
    assert "bawal" in negs
    print("  ✓ Tagalog negation words loaded")

    # Test classifier with Tagalog input
    clf = NLPClassifier()

    result1 = clf.classify("buhusan ng tubig ang kawali", "grease_fire")
    print(f"  'buhusan ng tubig...' → {result1['label']} (expected: unsafe)")
    assert result1["label"] == "unsafe", f"Expected unsafe, got {result1['label']}"

    result2 = clf.classify("takpan mo ng lid ang kawali", "grease_fire")
    print(f"  'takpan mo ng lid...' → {result2['label']} (expected: safe)")
    assert result2["label"] == "safe", f"Expected safe, got {result2['label']}"

    result3 = clf.classify("huwag tubig, takpan mo", "grease_fire")
    print(f"  'huwag tubig, takpan mo' → {result3['label']} (expected: safe)")
    assert result3["label"] == "safe", f"Expected safe, got {result3['label']}"

    result4 = clf.classify("tumawag ng 911 at lumikas", "gas_leak")
    print(f"  'tumawag ng 911 at lumikas' → {result4['label']} (expected: safe)")
    assert result4["label"] == "safe", f"Expected safe, got {result4['label']}"

    print("  ALL TAGALOG TESTS PASSED ✓\n")


def test_cli_subcommands():
    print("=" * 60)
    print("TEST: CLI Subcommands (import-level)")
    print("=" * 60)

    # We can't easily test OS-level CLI here, but we can test the functions
    from backend.cli import cmd_generate, cmd_classify
    print("  ✓ CLI module imports successfully")
    print("  (Full CLI tests require running with subprocess — see manual steps)")

    print("  CLI IMPORT TEST PASSED ✓\n")


def test_existing_classifier():
    print("=" * 60)
    print("TEST: Existing Classifier (backwards compatibility)")
    print("=" * 60)

    clf = NLPClassifier()

    # Original English test cases should still work
    r1 = clf.classify("put water on it", "grease_fire")
    assert r1["label"] == "unsafe"
    print(f"  ✓ 'put water on it' → {r1['label']}")

    r2 = clf.classify("cover with a lid", "grease_fire")
    assert r2["label"] == "safe"
    print(f"  ✓ 'cover with a lid' → {r2['label']}")

    r3 = clf.classify("don't use water; smother instead", "grease_fire")
    assert r3["label"] == "safe"
    print(f"  ✓ 'don't use water; smother instead' → {r3['label']}")

    r4 = clf.classify("smother it but don't use water", "grease_fire")
    assert r4["label"] == "safe"
    print(f"  ✓ 'smother it but don\\'t use water' → {r4['label']}")

    # New scenario types
    r5 = clf.classify("drop and cover under the desk", "earthquake")
    assert r5["label"] == "safe"
    print(f"  ✓ 'drop and cover under the desk' → {r5['label']} (earthquake)")

    r6 = clf.classify("go to higher ground", "flood")
    assert r6["label"] == "safe"
    print(f"  ✓ 'go to higher ground' → {r6['label']} (flood)")

    r7 = clf.classify("apply pressure with a clean cloth", "heavy_bleeding")
    assert r7["label"] == "safe"
    print(f"  ✓ 'apply pressure with clean cloth' → {r7['label']} (bleeding)")

    print("  ALL BACKWARDS COMPATIBILITY TESTS PASSED ✓\n")


if __name__ == "__main__":
    test_scenario_generator()
    test_feedback_engine()
    test_tagalog_support()
    test_cli_subcommands()
    test_existing_classifier()

    print("=" * 60)
    print("🎉 ALL TESTS PASSED!")
    print("=" * 60)
