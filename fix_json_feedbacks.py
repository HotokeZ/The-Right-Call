import json
import os
import urllib.request
import time
import re

API_KEY = "YOUR_API_KEY_HERE"

files_to_process = [
    'data/gameplay/curated_scenarios_ph_v2_en.json',
    'data/gameplay/curated_scenarios_ph_v2_taglish.json',
    'data/gameplay/curated_scenarios_ph_v2_tl.json',
    'data/gameplay/curated_scenarios_ph_v2.json',
    'data/gameplay/raw_scenarios.json'
]

vague_patterns = [
    r'(?i)highly dangerous action',
    r'(?i)puts the caller in danger',
    r'(?i)bad advice for waiting'
]

def is_vague(text):
    if not text: return False
    for p in vague_patterns:
        if re.search(p, text): return True
    return False

def generate_detailed_feedback(scenario_title, option_text, lang):
    prompt = f"""You are a professional 911 dispatch instructor. 
A player chose the following incorrect dialogue option during a 911 call simulation for the emergency scenario "{scenario_title}".
The option they chose was: "{option_text}"

Explain concisely and professionally WHY this is a highly dangerous or incorrect thing for a dispatcher to say or instruct. Keep it educational. Maximum 2 sentences.
Do NOT use the generic phrases "highly dangerous action" or "puts the caller in danger".
Provide the explanation in {lang} language."""

    payload = {
        "model": "llama-3.3-70b-versatile",
        "messages": [
            {"role": "system", "content": "You are a professional 911 dispatch instructor. Output ONLY the raw explanation text, no quotes or additional formatting."},
            {"role": "user", "content": prompt}
        ],
        "temperature": 0.3
    }

    req = urllib.request.Request(
        "https://api.groq.com/openai/v1/chat/completions",
        data=json.dumps(payload).encode(),
        headers={
            "Authorization": f"Bearer {API_KEY}", 
            "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0"
        }
    )

    max_retries = 5
    base_delay = 5
    for attempt in range(max_retries):
        try:
            resp = urllib.request.urlopen(req)
            response_data = json.loads(resp.read().decode())
            content = response_data['choices'][0]['message']['content'].strip()
            return content
        except urllib.error.HTTPError as e:
            if e.code == 429:
                delay = base_delay * (2 ** attempt)
                print(f"Rate limited (429). Waiting {delay} seconds before retry {attempt + 1}/{max_retries}...")
                time.sleep(delay)
            else:
                print(f"HTTP Error: {e.code} - {e.reason}")
                return None
        except Exception as e:
            print(f"Error calling Groq: {e}")
            return None
    
    print(f"Failed to generate feedback for '{option_text}' after {max_retries} attempts.")
    return None

count_modified = 0

for file_path in files_to_process:
    if not os.path.exists(file_path):
        continue
    
    with open(file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
        
    if 'scenarios' not in data:
        continue
        
    lang = 'English'
    if 'taglish' in file_path: lang = 'Taglish (mix of English and Tagalog)'
    elif '_tl' in file_path or file_path.endswith('ph_v2.json'): lang = 'Tagalog'

    file_modified = 0
    print(f"Processing {file_path} in {lang}...")
    
    # Optional: cache identical queries to save API calls
    cache = {}

    for scenario in data['scenarios']:
        title = scenario.get('title', 'Emergency')
        
        # Check options directly in scenario
        if 'options' in scenario:
            for opt in scenario['options']:
                explanation = opt.get('explanation', '')
                feedback = opt.get('feedback', '')
                
                needs_update = is_vague(explanation) or is_vague(feedback)
                if needs_update:
                    opt_text = opt.get('text', '')
                    cache_key = f"{title}_{opt_text}_{lang}"
                    
                    if cache_key in cache:
                        new_feedback = cache[cache_key]
                    else:
                        new_feedback = generate_detailed_feedback(title, opt_text, lang)
                        if new_feedback:
                            cache[cache_key] = new_feedback
                            # Rate limiting to avoid 429
                            time.sleep(0.5)
                            
                    if new_feedback:
                        if is_vague(explanation): opt['explanation'] = new_feedback
                        if is_vague(feedback): opt['feedback'] = new_feedback
                        file_modified += 1
                        count_modified += 1
                        print(f"  Fixed: {opt_text} -> {new_feedback}")

        # Check options in transcript
        if 'transcript' in scenario:
            for line in scenario['transcript']:
                if 'options' in line:
                    for opt in line['options']:
                        explanation = opt.get('explanation', '')
                        feedback = opt.get('feedback', '')
                        
                        needs_update = is_vague(explanation) or is_vague(feedback)
                        if needs_update:
                            opt_text = opt.get('text', '')
                            cache_key = f"{title}_{opt_text}_{lang}"
                            
                            if cache_key in cache:
                                new_feedback = cache[cache_key]
                            else:
                                new_feedback = generate_detailed_feedback(title, opt_text, lang)
                                if new_feedback:
                                    cache[cache_key] = new_feedback
                                    time.sleep(0.5)
                                    
                            if new_feedback:
                                if is_vague(explanation): opt['explanation'] = new_feedback
                                if is_vague(feedback): opt['feedback'] = new_feedback
                                file_modified += 1
                                count_modified += 1
                                print(f"  Fixed: {opt_text} -> {new_feedback}")

    if file_modified > 0:
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        print(f"Modified {file_modified} options in {file_path}")

print(f"Total modified options: {count_modified}")
