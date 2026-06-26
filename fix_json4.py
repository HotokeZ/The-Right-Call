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
    
    # Catch any generic dispatch options in English
    text = re.sub(r'(?i)^dispatch\s+(pnp\s*police|bfp\s*fire_truck|mdrrmo\s*ambulance|ems)\s*(immediately|silently|only|code\s*\d)?\s*\.?$', 'I am sending help. ', text)
    text = re.sub(r'(?i)^dispatch\s+(the\s+)?(pnp|bfp|mdrrmo|police|ambulance|fire\s*truck)s?\s*(immediately|silently|only)?\s*\.?$', 'I am sending help. ', text)
    
    # Catch generic dispatch options in Tagalog
    text = re.sub(r'(?i)^ipadala\s+(agad\s+)?(lamang\s+)?(ang\s+)?(mga\s+)?(trak\s+ng\s+bumbero|pulis|ambulansya)\s*(ng\s+)?(bfp|pnp|mdrrmo)?\s*(agad|lamang|nang\s+walang\s+sirena|para\s+sa\s+[^\.]+)?\.?$', 'Padating na po ang tulong. ', text)
    text = re.sub(r'(?i)^magpadala\s+(agad\s+)?(lamang\s+)?(ng\s+)?(mga\s+)?(trak\s+ng\s+bumbero|pulis|ambulansya)\s*(ng\s+)?(bfp|pnp|mdrrmo)?\s*(agad|lamang|nang\s+walang\s+sirena|para\s+sa\s+[^\.]+)?\.?$', 'Padating na po ang tulong. ', text)
    text = re.sub(r'(?i)^mag-dispatch\s+(agad\s+)?(lamang\s+)?(ng\s+)?(mga\s+)?(trak\s+ng\s+bumbero|pulis|ambulansya)\s*(ng\s+)?(bfp|pnp|mdrrmo)?\s*(agad|lamang|nang\s+walang\s+sirena|para\s+sa\s+[^\.]+)?\.?$', 'Padating na po ang tulong. ', text)

    # Clean up
    text = re.sub(r'\s+', ' ', text).strip()
    
    # Also handle the trailing dots
    if "Padating na po ang tulong. ." in text:
        text = text.replace("Padating na po ang tulong. .", "Padating na po ang tulong.")
    if "I am sending help. ." in text:
        text = text.replace("I am sending help. .", "I am sending help.")

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
