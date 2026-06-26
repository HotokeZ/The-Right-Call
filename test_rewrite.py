import json, re

def rewrite_to_first_person(text):
    original = text
    
    # ---- English patterns ----
    # "Tell them/the caller/him/her to [verb]..." -> "[Verb]..."
    # "Advise/Instruct/Direct/Guide/Warn/Remind/Reassure the caller to [verb]..." -> "[Verb]..."
    # "Ask them/the caller to [verb]..." -> "Can you [verb]?" or "[Verb]?"
    
    action_verbs = [
        'Tell', 'Advise', 'Instruct', 'Direct', 'Guide', 'Warn',
        'Remind', 'Reassure', 'Encourage', 'Order', 'Inform', 'Notify'
    ]
    ask_verbs = ['Ask']
    
    subject_pat = r'(the caller|them|him|her|the victim|the patient|the resident|the person|the individual|the bystander|the witness|the operator|her that|him that|them that|the caller that)'
    
    # Pattern: "Tell [subject] to [rest]"
    for verb in action_verbs:
        m = re.match(rf'^{verb}\s+{subject_pat}\s+to\s+(.+)', text, re.IGNORECASE)
        if m:
            rest = m.group(2).strip()
            # Capitalize first letter
            rest = rest[0].upper() + rest[1:]
            # Make sure it ends with punctuation
            if not rest[-1] in '.!?':
                rest += '.'
            return rest
        
        # Pattern: "Tell [subject] that [rest]" -> keep as soft reminder: "Please note that [rest]"
        m2 = re.match(rf'^{verb}\s+{subject_pat}\s+(that\s+.+)', text, re.IGNORECASE)
        if m2:
            rest = m2.group(2).strip()
            rest = rest[0].upper() + rest[1:]
            if not rest[-1] in '.!?':
                rest += '.'
            return 'Please note: ' + rest
        
        # Pattern: "Tell/Advise [subject] [verb phrase without 'to']"
        m3 = re.match(rf'^{verb}\s+{subject_pat}\s+(.+)', text, re.IGNORECASE)
        if m3:
            rest = m3.group(2).strip()
            rest = rest[0].upper() + rest[1:]
            if not rest[-1] in '.!?':
                rest += '.'
            return rest
    
    # Pattern: "Ask [subject] to [verb]..." -> "Can you [verb]?" 
    for verb in ask_verbs:
        m = re.match(rf'^{verb}\s+{subject_pat}\s+to\s+(.+)', text, re.IGNORECASE)
        if m:
            rest = m.group(2).strip()
            rest = rest[0].lower() + rest[1:]
            if rest.endswith('.') or rest.endswith('!') or rest.endswith('?'):
                rest = rest[:-1]
            return 'Can you ' + rest + '?'
        
        m2 = re.match(rf'^{verb}\s+{subject_pat}\s+(.+)', text, re.IGNORECASE)
        if m2:
            rest = m2.group(2).strip()
            rest = rest[0].upper() + rest[1:]
            if not rest[-1] in '.!?':
                rest += '.'
            return rest
    
    # ---- Tagalog/Taglish patterns ----
    # "Sabihin sa kanila/sa tumatawag na [verb]" -> "[Verb]"
    tl_patterns = [
        (r'^Sabihin\s+sa\s+(kanila|kanya|sa tumatawag|sa tawag|tumatawag)\s+na\s+(.+)', 2),
        (r'^Sabihin\s+sa\s+(kanila|kanya|sa tumatawag|sa tawag|tumatawag)\s+(.+)', 2),
        (r'^Ipaalam\s+sa\s+(kanila|kanya|tumatawag)\s+na\s+(.+)', 2),
        (r'^Payuhan\s+(sila|ang tumatawag|siya)\s+na\s+(.+)', 2),
        (r'^Turuan\s+(sila|ang tumatawag|siya)\s+na\s+(.+)', 2),
        (r'^Ipaalala\s+sa\s+(kanila|kanya|tumatawag)\s+na\s+(.+)', 2),
    ]
    for pat, group in tl_patterns:
        m = re.match(pat, text, re.IGNORECASE)
        if m:
            rest = m.group(group).strip()
            rest = rest[0].upper() + rest[1:]
            if not rest[-1] in '.!?':
                rest += '.'
            return rest
    
    return original


# Test a few
tests = [
    "Tell them to drive to the ER.",
    "Tell the caller to ask the construction site manager for more details.",
    "Advise the caller to hold their breath and retrieve pets.",
    "Tell her to hold her breath to stop the wheezing.",
    "Advise the caller to quickly drive her to the pharmacy.",
    "Instruct them to brew strong black coffee.",
    "Tell them to wait and call back if her lips turn blue.",
    "Ask the caller to stay on the line.",
    "Reassure them that help is coming.",
    "Tell them to leave it alone.",
    "Tell them to call an electrician in the morning.",
    "What is your exact location?",  # should NOT be changed
    "Stay calm and do not touch the outlet.",  # should NOT be changed
]

for t in tests:
    result = rewrite_to_first_person(t)
    if result != t:
        print(f'  CHANGED: {repr(t[:60])}')
        print(f'       TO: {repr(result[:60])}')
    else:
        print(f'  KEPT: {repr(t[:60])}')
