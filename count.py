import json

with open('data/gameplay/curated_scenarios_ph_v2_en.json', encoding='utf-8') as f:
    data = json.load(f)
    categories = [s['category'] for s in data['scenarios']]
    print(f"Fire: {categories.count('fire')}, Police: {categories.count('criminal')}, Medical: {categories.count('medical')}, Total: {len(categories)}")
