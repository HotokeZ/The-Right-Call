import json
with open('data/gameplay/curated_scenarios_ph_v2_en.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

for s in data['scenarios']:
    if s.get('title') == 'Mall Food Court Blaze':
        for t in s.get('transcript', []):
            if 'options' in t:
                print("  [OPTIONS for", t.get('speaker'), "]:", len(t['options']), "options")
            else:
                print("  ", t.get('speaker'), ":", t.get('text'))
        break
