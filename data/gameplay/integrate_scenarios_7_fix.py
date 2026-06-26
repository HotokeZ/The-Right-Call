import json

new_scenarios_path = r'C:\Users\rekai\.gemini\antigravity\brain\7af99a7a-9bad-410a-af4f-bc4090148799\scenarios_batch_7.md'

with open(new_scenarios_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace the freezing river scenario with a jellyfish sting
content = content.replace('"title": "Severe Cold Exposure (Hypothermia)"', '"title": "Severe Jellyfish Sting"')
content = content.replace('My friend fell into a freezing river at {location}! We got him out but he is shivering violently and his lips are blue!', 'My sister got stung by a large jellyfish at the beach near {location}! She is in extreme pain and her breathing is getting shallow!')
content = content.replace('Get his wet clothes off immediately and cover him with dry blankets.', 'Get her out of the water immediately and keep her completely still.')
content = content.replace('Wet clothes draw heat away from the body 25 times faster than dry air.', 'Staying still prevents the venom from pumping through her body faster.')
content = content.replace('Move him into a warm shelter or a heated car right away.', 'Rinse the sting with vinegar if you have it, not fresh water.')
content = content.replace('Getting out of the wind and cold is essential to stop temperature loss.', 'Vinegar deactivates the stinging cells. Fresh water causes them to fire more venom.')
content = content.replace('Put him in a steaming hot shower.', 'Pee on the sting.')
content = content.replace('Sudden extreme temperature changes can cause fatal cardiac arrhythmias in hypothermic patients.', 'This is a dangerous myth. Urine can cause the stingers to release more venom.')
content = content.replace('Give him alcohol to warm him up.', 'Rinse it with fresh bottled water.')
content = content.replace('Alcohol dilates blood vessels, sending cold blood to the core and dropping body temperature faster.', 'Fresh water triggers the stingers to fire more venom into the skin.')
content = content.replace('Tell him to run around to warm up.', 'Rub the sting with a towel to get the tentacles off.')
content = content.replace('Physical exertion can push cold blood from the limbs into the heart, causing a heart attack.', 'Rubbing forces the stingers deeper into the skin and releases massive amounts of venom.')
content = content.replace('Rub his arms and legs vigorously.', 'Tell her to run back to the car.')
content = content.replace('Rubbing cold skin can cause severe tissue damage and forces cold blood to the heart.', 'Running pumps the venom straight to the heart and lungs.')

content = content.replace('He is in the car with the heater on. He stopped shivering but he seems very sleepy and confused.', 'She is sitting still. Her leg is covered in red welts and she says her chest feels tight.')
content = content.replace('Do not let him fall asleep! Stopping shivering is a sign his hypothermia is becoming critical.', 'Monitor her breathing closely. Severe jellyfish stings can cause anaphylactic shock.')
content = content.replace('When the body is too cold to shiver, organ failure is imminent.', 'A tight chest is a sign that her airway may be swelling shut.')
content = content.replace('Keep him awake and place warm (not hot) water bottles near his chest and armpits.', 'Keep her seated. MDRRMO is rushing to your location with oxygen and medication.')
content = content.replace('Warming the core slowly is the only safe way to treat severe hypothermia.', 'Professional medical treatment is required immediately for severe marine stings.')
content = content.replace('Let him sleep, rest is good for him.', 'Try to scrape the tentacles off with your bare hands.')
content = content.replace('If he sleeps, he may slip into a coma and die.', 'You will get stung yourself and become a second victim.')
content = content.replace('Give him a cup of hot coffee.', 'Give her an allergy pill to swallow.')
content = content.replace('Confused patients cannot swallow properly and will choke on liquids.', 'If her chest is tight, her throat is swelling. Pills are a severe choking hazard.')
content = content.replace('Take the blankets off to see if his color is returning.', 'Tell her to lie flat on her back.')
content = content.replace('Removing blankets exposes him to cold air again.', 'Lying flat makes it much harder to breathe if her airway is swelling.')
content = content.replace('Turn the car heater to the absolute maximum heat setting blowing directly in his face.', 'Pour hot coffee on the sting to kill the venom.')
content = content.replace('Intense direct heat can burn cold, numb skin.', 'Coffee does not neutralize venom and will cause severe burns.')

with open(new_scenarios_path, 'w', encoding='utf-8') as f:
    f.write(content)

print('Updated markdown file.')
