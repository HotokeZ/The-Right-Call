import json

filepath = r'G:\Code\BFP - Copy (11) - Copy\new-game-project\data\gameplay\scenario_bank_en.json'

with open(filepath, 'r', encoding='utf-8') as f:
    data = json.load(f)

for scenario in data['scenarios']:
    if scenario['id'] == 'sb_medical_024':
        scenario['title'] = 'Tricycle Accident Head Injury'
        scenario['transcript'] = [
            {
                "speaker": "Caller",
                "text": "MDRRMO! A tricycle just flipped over on the national highway at {location}! The passenger was thrown out and hit their head hard on the pavement!"
            },
            {
                "speaker": "911",
                "options": [
                    {
                        "text": "Do not move the passenger! Keep them completely still and wait for the ambulance.",
                        "label": "safe",
                        "explanation": "Moving someone with a potential spinal or severe head injury can cause permanent paralysis or death."
                    },
                    {
                        "text": "Tell arriving cars to slow down and direct traffic safely around the accident.",
                        "label": "safe",
                        "explanation": "Securing the scene prevents secondary accidents from running over the victim."
                    },
                    {
                        "text": "Pick them up and try to carry them to the side of the road.",
                        "label": "unsafe",
                        "explanation": "Unless the victim is in a burning vehicle, dragging them causes catastrophic spinal damage."
                    },
                    {
                        "text": "Take off their helmet if they are wearing one.",
                        "label": "unsafe",
                        "explanation": "Removing a helmet without proper medical training can snap a broken neck."
                    },
                    {
                        "text": "Try to sit them up to give them water.",
                        "label": "unsafe",
                        "explanation": "Sitting them up drops blood pressure to the brain, and water is a choking hazard."
                    },
                    {
                        "text": "Shake them by the shoulders to try to wake them up.",
                        "label": "unsafe",
                        "explanation": "Violent shaking worsens traumatic brain injuries and neck fractures."
                    }
                ]
            },
            {
                "speaker": "Caller",
                "text": "I am standing next to them directing traffic away. They are breathing but totally unconscious."
            },
            {
                "speaker": "911",
                "options": [
                    {
                        "text": "Kneel beside them and monitor their breathing continuously until MDRRMO arrives.",
                        "label": "safe",
                        "explanation": "If they stop breathing, you will need to start chest compressions immediately."
                    },
                    {
                        "text": "If they start to vomit, roll their entire body to the side at the same time to keep the airway clear.",
                        "label": "safe",
                        "explanation": "This is called a log-roll. It keeps the spine straight while preventing them from choking on vomit."
                    },
                    {
                        "text": "Turn their head to the side so they are more comfortable.",
                        "label": "unsafe",
                        "explanation": "Twisting the neck alone can sever the spinal cord."
                    },
                    {
                        "text": "Try to force their eyes open to check their pupils.",
                        "label": "unsafe",
                        "explanation": "Leave medical diagnostics to the professionals. You could damage their eyes."
                    },
                    {
                        "text": "Slap their cheeks gently to bring them back to consciousness.",
                        "label": "unsafe",
                        "explanation": "Physical stimulus won't wake up a severe concussion and only causes harm."
                    },
                    {
                        "text": "Leave them there and try to flip the tricycle back over.",
                        "label": "unsafe",
                        "explanation": "The patient is your priority. Flipping the trike could spill gasoline or cause a fire."
                    }
                ]
            }
        ]
        break

with open(filepath, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=4)

print('Successfully replaced scenario sb_medical_024.')
