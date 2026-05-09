from backend.nlp_classifier import NLPClassifier
import re

clf = NLPClassifier()
samples = [
    "put water on it",
]

for s in samples:
    t = clf._normalize(s)
    print('INPUT:', s)
    print('NORMALIZED:', repr(t))
    for phrase in ['water', 'pour water', 'throw water']:
        pat = r"\b" + re.escape(phrase) + r"\b"
        m = list(re.finditer(pat, t))
        print(f"phrase={phrase!r}, matches={len(m)}", [ (mm.start(), mm.group(0)) for mm in m ])
    print()
