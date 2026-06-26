import json, re

def rewrite_to_first_person(text):
    original = text
    
    action_verbs = [
        'Tell', 'Advise', 'Instruct', 'Direct', 'Guide', 'Warn',
        'Remind', 'Reassure', 'Encourage', 'Order', 'Inform', 'Notify'
    ]
    ask_verbs = ['Ask']
    
    subject_pat = r'(?:the caller|them|him|her|the victim|the patient|the resident|the person|the individual|the bystander|the witness)'
    subject_with_that = r'(?:the caller|them|him|her|the victim|the patient|the resident|the person)'
    
    for verb in action_verbs:
        # Pattern: "Tell [subject] that [rest]" -> "Please note that [rest]"
        m = re.match(rf'^{verb}\s+{subject_with_that}\s+that\s+(.+)', text, re.IGNORECASE)
        if m:
            rest = m.group(1).strip()
            rest = rest[0].upper() + rest[1:]
            if rest[-1] not in '.!?':
                rest += '.'
            return 'Please note: ' + rest
        
        # Pattern: "Tell [subject] to [rest]" -> "[Rest]"
        m = re.match(rf'^{verb}\s+{subject_pat}\s+to\s+(.+)', text, re.IGNORECASE)
        if m:
            rest = m.group(1).strip()
            rest = rest[0].upper() + rest[1:]
            if rest[-1] not in '.!?':
                rest += '.'
            return rest
        
        # Pattern: "Tell [subject] [rest]" (without 'to') -> "[Rest]"
        m = re.match(rf'^{verb}\s+{subject_pat}\s+(.+)', text, re.IGNORECASE)
        if m:
            rest = m.group(1).strip()
            rest = rest[0].upper() + rest[1:]
            if rest[-1] not in '.!?':
                rest += '.'
            return rest
    
    for verb in ask_verbs:
        # "Ask [subject] to [verb]..." -> "Can you [verb]?"
        m = re.match(rf'^{verb}\s+{subject_pat}\s+to\s+(.+)', text, re.IGNORECASE)
        if m:
            rest = m.group(1).strip()
            if rest[-1] in '.!?':
                rest = rest[:-1]
            return 'Can you ' + rest[0].lower() + rest[1:] + '?'
        
        # "Ask [subject] [rest]" -> "[Rest]?"
        m = re.match(rf'^{verb}\s+{subject_pat}\s+(.+)', text, re.IGNORECASE)
        if m:
            rest = m.group(1).strip()
            rest = rest[0].upper() + rest[1:]
            if rest[-1] not in '.!?':
                rest += '?'
            return rest
    
    # ---- Tagalog/Taglish patterns ----
    tl_patterns = [
        r'^Sabihin\s+sa\s+(?:kanila|kanya|tumatawag|kaugnayan)\s+na\s+(.+)',
        r'^Sabihin\s+sa\s+(?:kanila|kanya|tumatawag|kaugnayan)\s+(.+)',
        r'^Ipaalam\s+sa\s+(?:kanila|kanya|tumatawag)\s+na\s+(.+)',
        r'^Payuhan\s+(?:sila|ang tumatawag|siya|nila)\s+na\s+(.+)',
        r'^Turuan\s+(?:sila|ang tumatawag|siya|nila)\s+na\s+(.+)',
        r'^Ipaalala\s+sa\s+(?:kanila|kanya|tumatawag)\s+na\s+(.+)',
        r'^Tanungin\s+(?:sila|ang tumatawag|siya)\s+kung\s+(.+)',
        r'^Hilingin\s+sa\s+(?:kanila|kanya|tumatawag)\s+na\s+(.+)',
    ]
    for pat in tl_patterns:
        m = re.match(pat, text, re.IGNORECASE)
        if m:
            rest = m.group(1).strip()
            rest = rest[0].upper() + rest[1:]
            if rest[-1] not in '.!?':
                rest += '.'
            return rest
    
    return original


def process_options_in_list(opts):
    changed = 0
    for opt in opts:
        if isinstance(opt, dict):
            text = opt.get('text', '')
            new_text = rewrite_to_first_person(text)
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
        # Fix options in transcript entries
        for t in s.get('transcript', []):
            if isinstance(t, dict) and 'options' in t:
                file_count += process_options_in_list(t['options'])
        # Fix root-level options
        if 'options' in s:
            file_count += process_options_in_list(s['options'])
    
    with open(file_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    
    print(f'{file_path}: fixed {file_count} options')
    total += file_count

print(f'\\nTotal fixed: {total}')
