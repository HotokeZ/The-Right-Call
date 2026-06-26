import json
import re

filepath = r'G:\Code\BFP - Copy (11) - Copy\new-game-project\data\gameplay\scenario_bank_en.json'
new_scenarios_path = r'C:\Users\rekai\.gemini\antigravity\brain\7af99a7a-9bad-410a-af4f-bc4090148799\scenarios_batch_3.md'

with open(new_scenarios_path, 'r', encoding='utf-8') as f:
    content = f.read()

json_match = re.search(r'`json\s*(\[\s*\{.*\}\s*\])\s*`', content, re.DOTALL)
if json_match:
    new_scenarios_json = json_match.group(1)
    new_scenarios = json.loads(new_scenarios_json)
    
    with open(filepath, 'r', encoding='utf-8') as f:
        data = json.load(f)
        
    data['scenarios'].extend(new_scenarios)
    
    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=4)
        
    print(f'Successfully added {len(new_scenarios)} scenarios. Total scenarios now: {len(data["scenarios"])}')
else:
    print('Failed to find JSON block in the markdown file.')
