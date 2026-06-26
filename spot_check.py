import json, random
with open('data/gameplay/curated_scenarios_ph_v2_en.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

# Sample 20 random options from across scenarios
all_opts = []
for s in data['scenarios']:
    for t in s.get('transcript', []):
        for opt in t.get('options', []):
            all_opts.append((s['title'], opt.get('text', '')))
    for opt in s.get('options', []):
        all_opts.append((s['title'], opt.get('text', '')))

random.seed(42)
sample = random.sample(all_opts, 20)
for title, text in sample:
    print(f'[{title[:30]}] {text[:80]}')
