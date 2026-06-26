import json, re

files = [
    'data/gameplay/curated_scenarios_ph_v2_en.json',
    'data/gameplay/curated_scenarios_ph_v2_taglish.json',
    'data/gameplay/curated_scenarios_ph_v2_tl.json',
]

# Patterns that indicate 3rd-person/stage-direction phrasing (English)
third_person_patterns = [
    r'^Tell (them|the caller|him|her|the victim|the patient|the resident|the person|the individual)',
    r'^Advise (the caller|them|him|her)',
    r'^Instruct (the caller|them|him|her)',
    r'^Ask (the caller|them|him|her)',
    r'^Inform (the caller|them|him|her)',
    r'^Direct (the caller|them|him|her)',
    r'^Guide (the caller|them|him|her)',
    r'^Warn (the caller|them|him|her)',
    r'^Remind (the caller|them|him|her)',
    r'^Reassure (the caller|them|him|her)',
    r'^Encourage (the caller|them|him|her)',
    r'^Order (the caller|them|him|her)',
]

count = 0
for file_path in files:
    with open(file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    for s in data['scenarios']:
        for t in s.get('transcript', []):
            for opt in t.get('options', []):
                text = opt.get('text', '')
                for pat in third_person_patterns:
                    if re.match(pat, text, re.IGNORECASE):
                        count += 1
                        print(repr(text[:100]))
                        break
        for opt in s.get('options', []):
            text = opt.get('text', '')
            for pat in third_person_patterns:
                if re.match(pat, text, re.IGNORECASE):
                    count += 1
                    print(repr(text[:100]))
                    break

print(f'\\nTotal 3rd-person options found: {count}')
