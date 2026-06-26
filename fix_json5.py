import json
import re
import os

files_to_process = [
    'data/gameplay/curated_scenarios_ph_v2_en.json',
    'data/gameplay/curated_scenarios_ph_v2_taglish.json',
    'data/gameplay/curated_scenarios_ph_v2_tl.json',
    'data/gameplay/curated_scenarios_ph_v2.json',
    'data/gameplay/raw_scenarios.json'
]

def transform_text(text, lang='en'):
    original = text
    
    text = re.sub(r'(?i)^(Ipadala|Magpadala)\s+(ng\s+)?(isang\s+)?(yunit\s+ng\s+)?(trak\s+ng\s+bumbero|pulis|ambulansya|BFP\s*fire_truck|pulis\s*ng\s*PNP|EMS|non-emergency\s*unit|helicopter|medical\s*unit)\s*(agad\s+)?(na\s*may\s*sirena|lamang)?', 'Padating na po ang tulong. ', text)
    text = re.sub(r'(?i)^(Ipadala|Magpadala)\s+lamang\s+ang\s+EMS', 'Padating na po ang tulong. ', text)
    text = re.sub(r'(?i)^(Ipadala|Magpadala)\s+muna\s+ng\s+(patrol\s+ng\s+pulisya|medical\s+unit)', 'Padating na po ang tulong. ', text)
    text = re.sub(r'(?i)^(Ipadala|Magpadala)\s+ang\s+maraming\s+BFP\s*fire_truck', 'Padating na po ang tulong. ', text)

    text = re.sub(r'\s+', ' ', text).strip()
    
    if "Padating na po ang tulong. ." in text:
        text = text.replace("Padating na po ang tulong. .", "Padating na po ang tulong.")

    if text != original:
        return text
    return original

count_modified = 0

for file_path in files_to_process:
    if not os.path.exists(file_path):
        continue
    
    with open(file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
        
    if 'scenarios' not in data:
        continue
        
    lang = 'en'
    if 'taglish' in file_path: lang = 'taglish'
    elif '_tl' in file_path: lang = 'tl'

    file_modified = 0
    for scenario in data['scenarios']:
        if 'options' in scenario:
            for opt in scenario['options']:
                if 'text' in opt:
                    new_text = transform_text(opt['text'], lang)
                    if new_text != opt['text']:
                        opt['text'] = new_text
                        file_modified += 1
                        count_modified += 1

    if file_modified > 0:
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        print(f"Modified {file_modified} options in {file_path}")

print(f"Total modified options: {count_modified}")
