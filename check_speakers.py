import json
with open('data/gameplay/raw_scenarios.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

for s in data['scenarios'][:3]:
    print("Scenario ID:", s.get('title'))
    for t in s.get('transcript_en', []):
        if 'options' in t:
            print("  [OPTIONS for", t.get('speaker'), "]:", len(t['options']), "options")
        else:
            print("  ", t.get('speaker'), ":", t.get('text'))
