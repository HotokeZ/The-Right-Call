import json
import os

files_to_process = [
    'data/gameplay/curated_scenarios_ph_v2_en.json',
    'data/gameplay/curated_scenarios_ph_v2_taglish.json',
    'data/gameplay/curated_scenarios_ph_v2_tl.json',
    'data/gameplay/raw_scenarios.json'
]

for file_path in files_to_process:
    if not os.path.exists(file_path):
        continue
    with open(file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    root_options = 0
    transcript_options = 0
    for scenario in data.get('scenarios', []):
        if 'options' in scenario:
            root_options += 1
        has_transcript_options = False
        if 'transcript' in scenario:
            for t in scenario['transcript']:
                if 'options' in t:
                    has_transcript_options = True
        if 'transcript_en' in scenario:
            for t in scenario['transcript_en']:
                if 'options' in t:
                    has_transcript_options = True
        if has_transcript_options:
            transcript_options += 1

    print(f"{file_path}: root_options={root_options}, transcript_options={transcript_options}")
