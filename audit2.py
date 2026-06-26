import json, re

# Find the remaining 3rd-person options that the regex missed
files = ['data/gameplay/curated_scenarios_ph_v2_en.json']

patterns_missed = [
    r'^Tell caller to',
]
for file_path in files:
    with open(file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    for s in data['scenarios']:
        for t in s.get('transcript', []):
            for opt in t.get('options', []):
                text = opt.get('text', '')
                for pat in patterns_missed:
                    if re.match(pat, text, re.IGNORECASE):
                        print(repr(text[:100]))
        for opt in s.get('options', []):
            text = opt.get('text', '')
            for pat in patterns_missed:
                if re.match(pat, text, re.IGNORECASE):
                    print(repr(text[:100]))
