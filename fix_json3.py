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
    # English replacements
    text = re.sub(r'(?i)^dispatch\s+((multiple\s+)?(bfp|pnp|mdrrmo)?\s*\(?((fire_truck|ambulance|police)s?)\)?\s*(code\s*\d)?\s*(immediately|silently|only)?\s*,?\s*(to\s+the\s+[^,]+,?)?)', 'I am sending help right away. ', text)
    text = re.sub(r'(?i)^dispatch\s+a\s+single\s+(bfp|pnp|mdrrmo)?\s*\(?(fire_truck|ambulance|police)\)?', 'I am sending help. ', text)
    text = re.sub(r'(?i)^dispatch\s+(bfp|pnp|mdrrmo)', 'I am sending help. ', text)
    text = re.sub(r'(?i)^send\s+a\s+(non-emergency\s+)?unit', 'I will send someone. ', text)
    text = re.sub(r'(?i)^send\s+(bfp|pnp|mdrrmo)', 'I am sending help. ', text)
    text = re.sub(r'(?i)^dispatch\s+ems\s+only', 'I am sending an ambulance. ', text)
    
    # Tagalog/Taglish replacements
    text = re.sub(r'(?i)^mag-dispatch\s+ng\s+(mga\s+)?(bfp|pnp|mdrrmo)?\s*\(?((fire_truck|ambulance|police)s?)\)?', 'Padating na po ang tulong. ', text)
    text = re.sub(r'(?i)^magpadala\s+ng\s+(mga\s+)?(bfp|pnp|mdrrmo)?\s*\(?((fire_truck|ambulance|police)s?)\)?', 'Padating na po ang tulong. ', text)
    text = re.sub(r'(?i)^ipadala\s+ang\s+(mga\s+)?(bfp|pnp|mdrrmo)?\s*\(?((fire_truck|ambulance|police)s?)\)?(\s*ng\s+(bfp|pnp|mdrrmo))?', 'Padating na po ang tulong. ', text)
    text = re.sub(r'(?i)^ipadala\s+ang\s+(iisang\s+)?yunit\s+ng\s+(bfp|pnp|mdrrmo)', 'Padating na po ang tulong. ', text)

    # Cleanup leftover grammar
    text = re.sub(r'I am sending help right away\.\s+(and\s+)?', 'I am sending help right away. ', text)
    text = re.sub(r'I am sending help\.\s+(and\s+)?', 'I am sending help. ', text)
    text = re.sub(r'Padating na po ang tulong\.\s+(at\s+)?', 'Padating na po ang tulong. ', text)
    text = re.sub(r'Padating na po ang tulong\.,?\s+', 'Padating na po ang tulong. ', text)

    # Capitalize the next letter
    match = re.search(r'(I am sending help[^\.]*\.\s+)([a-z])', text)
    if match:
        text = text[:match.start(2)] + match.group(2).upper() + text[match.end(2):]

    match = re.search(r'(Padating na po ang tulong\.\s+)([a-z])', text)
    if match:
        text = text[:match.start(2)] + match.group(2).upper() + text[match.end(2):]

    if text != original:
        return text.strip()
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
                        if lang == 'en':
                            new_text = new_text.replace(' report ', ' I will note the ')
                            new_text = new_text.replace(' initiate ', ' Please initiate ')
                            new_text = new_text.replace(' instruct ', ' Please ')
                            new_text = new_text.replace(' advise ', ' I advise you to ')
                            new_text = new_text.replace(' inform ', ' I will inform them ')
                        elif lang == 'tl' or lang == 'taglish':
                            new_text = new_text.replace(' ipaalam ', ' ipapaalam ko ')
                            new_text = new_text.replace(' magbigay-alam ', ' magbibigay-alam ako ')
                            new_text = new_text.replace(' iulat ', ' iuulat ko ')
                            new_text = new_text.replace(' payuhan ', ' pinapayuhan ko kayong ')
                            new_text = new_text.replace(' turuan ', ' tuturuan ko kayong ')
                            
                        opt['text'] = new_text
                        file_modified += 1
                        count_modified += 1

    if file_modified > 0:
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        print(f"Modified {file_modified} options in {file_path}")

print(f"Total modified options: {count_modified}")
