"""Non-interactive demo to exercise the NLP classifier.

This file is runnable directly (python backend/demo.py) and as a module
(python -m backend.demo). When run directly we ensure the project root is on
`sys.path` so the `backend` package can be imported.
"""
import os
import sys

# If this file is executed directly, the script's directory becomes sys.path[0].
# That means the parent (project root) isn't on sys.path, so `import backend...`
# will fail. Add the project root to sys.path when needed.
if __name__ == "__main__" and __package__ is None:
    current_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(current_dir)
    if project_root not in sys.path:
        sys.path.insert(0, project_root)

from backend.nlp_classifier import NLPClassifier
import sys as _sys


def run_demo():
    clf = NLPClassifier()
    scenario = "grease_fire"
    print("NPC: The pan is on fire!")

    samples = [
        "Quick, throw some water on it!",
        "Turn off the stove and cover with a lid.",
        "Use a fire extinguisher and dispatch emergency services.",
        "Smother the flames with a towel and baking soda.",
        "Spray water until it stops.",
    ]

    for s in samples:
        result = clf.classify(s, scenario)
        print("Player:", s)
        print("->", result["label"], "-", result["reason"])
        print()


def run_interactive():
    clf = NLPClassifier()
    scenario = "grease_fire"
    print("NPC: The pan is on fire!")
    print("Type advice (or '/quit' to exit). Use '/scenario NAME' to change scenario.")

    while True:
        try:
            text = input("You: ")
        except EOFError:
            print()
            break
        if not text:
            continue
        t = text.strip()
        if t.lower() in ("/quit", "quit", "exit"):
            break
        if t.startswith("/scenario ") or t.startswith("/s "):
            parts = t.split(maxsplit=1)
            if len(parts) == 2:
                scenario = parts[1].strip()
                print(f"Scenario set to '{scenario}'")
            else:
                print("Usage: /scenario <scenario_name>")
            continue
        if t.startswith("/learn "):
            # /learn safe <text> or /learn unsafe <text>
            rest = t[len("/learn "):].strip()
            if not rest:
                print("Usage: /learn <safe|unsafe> <text>")
                continue
            try:
                label, sample = rest.split(None, 1)
            except ValueError:
                print("Usage: /learn <safe|unsafe> <text>")
                continue
            label = label.lower()
            if label not in ("safe", "unsafe"):
                print("Label must be 'safe' or 'unsafe'.")
                continue
            clf.learn(sample, label)
            print("Saved example.")
            continue

        result = clf.classify(t, scenario)
        print("->", result["label"], "-", result["reason"])
        # If the classifier returned a matches breakdown, print points
        if isinstance(result, dict) and "matches" in result:
            matches = result.get("matches", [])
            if matches:
                print("Points:")
                for i, m in enumerate(matches, start=1):
                    neg = " (negated)" if m.get("negated") else ""
                    print(f"  {i}. {m['phrase']} — {m['type']}{neg}")
            counts = result.get("counts")
            if counts:
                print(
                    f"Counts: safe_unneg={counts['safe_unneg']}, safe_neg={counts['safe_neg']}, unsafe_unneg={counts['unsafe_unneg']}, unsafe_neg={counts['unsafe_neg']}"
                )
            if "score" in result:
                print(f"Score: {result['score']}")


if __name__ == "__main__":
    # If stdin is a TTY, run interactive; otherwise run the demo samples.
    if _sys.stdin is not None and _sys.stdin.isatty():
        run_interactive()
    else:
        run_demo()
