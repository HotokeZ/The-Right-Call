"""CLI bridge for the NLP backend — used by Godot via ``OS.execute()``.

Subcommands
-----------
generate   Generate a randomised scenario (JSON to stdout).
classify   Classify player text against a scenario (JSON to stdout).
evaluate   Evaluate a multiple-choice selection (JSON to stdout).
hints      Return hints for a scenario's options (JSON to stdout).

Examples
--------
::

    python backend/cli.py generate --category fire --locale tl
    python backend/cli.py classify --scenario grease_fire "cover with a lid"
    python backend/cli.py classify --scenario grease_fire --locale tl "takpan mo ng lid"
    python backend/cli.py evaluate --scenario-id grease_fire --choice 1 --locale en
    python backend/cli.py hints --scenario-id grease_fire --locale en

Legacy mode (backwards-compatible with the old CLI):

    python backend/cli.py --scenario grease_fire "your advice text here"
"""
import argparse
import json
import sys
import os

# Ensure the project root is importable regardless of how the script is invoked.
script_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.dirname(script_dir)
if project_root not in sys.path:
    sys.path.insert(0, project_root)

from backend.nlp_classifier import NLPClassifier
from backend.scenario_generator import ScenarioGenerator
from backend.feedback_engine import FeedbackEngine


def _json_out(data):
    """Print a JSON object to stdout and exit cleanly."""
    print(json.dumps(data, ensure_ascii=False))


# ── Subcommand handlers ─────────────────────────────────────────────

def cmd_generate(args):
    gen = ScenarioGenerator()
    scenario = gen.generate(
        category=args.category,
        difficulty=args.difficulty,
        locale=args.locale,
    )
    _json_out(scenario)


def cmd_classify(args):
    clf = NLPClassifier()
    text = " ".join(args.text)
    result = clf.classify(text, args.scenario)
    _json_out(result)


def cmd_evaluate(args):
    gen = ScenarioGenerator()
    engine = FeedbackEngine()

    # Get the scenario template
    template = gen.get_scenario_by_id(args.scenario_id)
    if template is None:
        _json_out({"error": f"Scenario '{args.scenario_id}' not found."})
        sys.exit(1)

    # Build a full scenario from the template
    scenario = gen._assemble(
        template,
        location="(evaluation)",
        difficulty="easy",
        locale=args.locale,
    )

    result = engine.evaluate_choice(scenario, args.choice, locale=args.locale)
    _json_out(result)


def cmd_hints(args):
    gen = ScenarioGenerator()
    engine = FeedbackEngine()

    template = gen.get_scenario_by_id(args.scenario_id)
    if template is None:
        _json_out({"error": f"Scenario '{args.scenario_id}' not found."})
        sys.exit(1)

    scenario = gen._assemble(
        template,
        location="(hints)",
        difficulty="easy",
        locale=args.locale,
    )

    hints = engine.get_hints(scenario, locale=args.locale)
    combined = engine.get_combined_hint(scenario, locale=args.locale)
    _json_out({"hints": hints, "combined_hint": combined})


def cmd_legacy(args):
    """Backwards-compatible: single classification like the old CLI."""
    clf = NLPClassifier()
    text = " ".join(args.text)
    result = clf.classify(text, args.scenario)
    _json_out(result)


# ── Main ─────────────────────────────────────────────────────────────

def main():
    # If the first non-flag argument is a known subcommand, use subparser routing.
    # Otherwise fall back to legacy single-classification mode.
    known_commands = {"generate", "classify", "evaluate", "hints"}

    # Detect legacy mode: no subcommand at all (e.g. ``cli.py --scenario x "text"``)
    first_positional = None
    for a in sys.argv[1:]:
        if not a.startswith("-"):
            first_positional = a
            break

    if first_positional not in known_commands:
        # Legacy mode
        legacy_parser = argparse.ArgumentParser(description="(legacy) NLP classifier")
        legacy_parser.add_argument("--scenario", default="grease_fire")
        legacy_parser.add_argument("text", nargs="+", help="Text of player's advice")
        args = legacy_parser.parse_args()
        cmd_legacy(args)
        return

    parser = argparse.ArgumentParser(
        description="NLP backend CLI for Emergency Dispatch game."
    )
    subparsers = parser.add_subparsers(dest="command")

    # -- generate --
    p_gen = subparsers.add_parser("generate", help="Generate a random scenario")
    p_gen.add_argument("--category", default=None, help="fire|medical|criminal|natural_disaster")
    p_gen.add_argument("--difficulty", default="easy", help="easy|certified")
    p_gen.add_argument("--locale", default="en", help="en|tl|taglish")
    p_gen.set_defaults(func=cmd_generate)

    # -- classify --
    p_cls = subparsers.add_parser("classify", help="Classify player text")
    p_cls.add_argument("--scenario", default="grease_fire", help="Scenario key for classification")
    p_cls.add_argument("--locale", default="en", help="en|tl|taglish")
    p_cls.add_argument("text", nargs="+", help="Player's advice text")
    p_cls.set_defaults(func=cmd_classify)

    # -- evaluate --
    p_eval = subparsers.add_parser("evaluate", help="Evaluate a multiple-choice selection")
    p_eval.add_argument("--scenario-id", required=True, help="Scenario template ID")
    p_eval.add_argument("--choice", type=int, required=True, help="Option index (0-based)")
    p_eval.add_argument("--locale", default="en", help="en|tl|taglish")
    p_eval.set_defaults(func=cmd_evaluate)

    # -- hints --
    p_hints = subparsers.add_parser("hints", help="Get hints for scenario options")
    p_hints.add_argument("--scenario-id", required=True, help="Scenario template ID")
    p_hints.add_argument("--locale", default="en", help="en|tl|taglish")
    p_hints.set_defaults(func=cmd_hints)

    args = parser.parse_args()

    if hasattr(args, "func"):
        args.func(args)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
