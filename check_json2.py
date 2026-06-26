import json
with open('data/gameplay/curated_scenarios_ph_v2_en.json', 'r', encoding='utf-8') as f:
    data = json.load(f)
for s in data['scenarios']:
    has_t = False
    for t in s.get('transcript', []):
        if 'options' in t: has_t = True
    if not has_t:
        print("Missing transcript options in:", s['id'])
