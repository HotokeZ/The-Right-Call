import json

file_path = 'data/gameplay/curated_scenarios_ph_v2_en.json'
with open(file_path, 'r', encoding='utf-8') as f:
    data = json.load(f)

for s in data['scenarios']:
    if s['id'] == 'gen_fire_001':
        opts = s.get('options', [])
        # Append an empty 911 speaker with these options to transcript
        s['transcript'].append({
            "speaker": "911",
            "options": opts
        })
        break

with open(file_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
