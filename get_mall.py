import json
with open('data/gameplay/curated_scenarios_ph_v2_en.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

for s in data['scenarios']:
    if s.get('title') == 'Mall Food Court Blaze':
        print(json.dumps(s['transcript'], indent=2))
        break
