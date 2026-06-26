import json
filepath = r'G:\Code\BFP - Copy (11) - Copy\new-game-project\data\gameplay\scenario_bank_en.json'
with open(filepath, 'r', encoding='utf-8') as f:
    data = json.load(f)

data['scenarios'] = data['scenarios'][:-10]

with open(filepath, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=4)
print(f'Removed duplicates. Total scenarios: {len(data["scenarios"])}')
