import json, re

def fix_tell_caller_to(text):
    # "Tell caller to [verb]..." -> "[Verb]..."
    m = re.match(r'^Tell caller to (.+)', text, re.IGNORECASE)
    if m:
        rest = m.group(1).strip()
        rest = rest[0].upper() + rest[1:]
        if rest[-1] not in '.!?':
            rest += '.'
        return rest
    return text

def process_options(opts):
    changed = 0
    for opt in opts:
        if isinstance(opt, dict):
            text = opt.get('text', '')
            new_text = fix_tell_caller_to(text)
            if new_text != text:
                opt['text'] = new_text
                changed += 1
    return changed

files = [
    'data/gameplay/curated_scenarios_ph_v2_en.json',
    'data/gameplay/curated_scenarios_ph_v2_taglish.json',
    'data/gameplay/curated_scenarios_ph_v2_tl.json',
]

total = 0
for file_path in files:
    with open(file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    file_count = 0
    for s in data['scenarios']:
        for t in s.get('transcript', []):
            if isinstance(t, dict) and 'options' in t:
                file_count += process_options(t['options'])
        if 'options' in s:
            file_count += process_options(s['options'])
    
    with open(file_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print(f'{file_path}: fixed {file_count}')
    total += file_count

print(f'Total: {total}')
