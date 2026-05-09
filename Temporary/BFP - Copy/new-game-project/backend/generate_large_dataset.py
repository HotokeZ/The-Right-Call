import json
import random
import os

OUTPUT_FILE = os.path.join(os.path.dirname(__file__), "scenarios_bank.json")

# Core Data Vault - Combinations drive the dataset volume
LOCATIONS = [
    "P. Burgos Street, Sta. Cruz", "Rizal Avenue, Sta. Cruz", "Quezon Avenue, Sta. Cruz", "Laguna Provincial Capitol",
    "Santa Cruz Public Market", "Barangay Poblacion, Sta. Cruz", "Sunstar Mall, Sta. Cruz", "Liceo de Los Banos branch, Sta. Cruz",
    "Laguna Medical Center", "Santa Cruz Church (Immaculate Conception)", "Ocampo Street, Sta. Cruz", "Barangay Santisima Cruz",
    "National Highway Intersection, Sta. Cruz", "Barangay Pagsawitan", "Barangay Bubukal", "Barangay Labuin",
    "Tricycle Terminal near Plaza", "Santa Cruz Town Plaza", "Pedro Guevara Memorial National High School", 
    "Barangay Bagumbayan, Sta. Cruz", "Barangay Calios", "San Pablo Sur, Sta. Cruz", "Magdalena Boundary Road"
]

CALLER_PERSONAS = [
    "Panicked Citizen", "Calm Bystander", "Terrified Employee",
    "Angry Shop Owner", "Crying Child", "Elderly Witness",
    "Security Guard", "Exhausted Teacher", "Out-of-breath Runner"
]

# Variations of Dispatcher initial prompt
DISPATCHER_PROMPTS = [
    "911, what is the address of your emergency?",
    "Emergency dispatch, where are you located?",
    "911 emergency, can you tell me your location?",
    "This is 911 dispatch, what is happening and where are you?"
]

def create_fire_scenario(id_num):
    location = random.choice(LOCATIONS)
    caller = random.choice(CALLER_PERSONAS)
    
    # Fire Variations
    fire_types = [
        {"desc": "flames from a pan in the kitchen", "type": "grease_fire"},
        {"desc": "a massive grease fire on the stove", "type": "grease_fire"},
        {"desc": "sparks flying from the electrical breaker panel", "type": "electrical_fire"},
        {"desc": "a burning smell and smoke coming from the wall outlets", "type": "electrical_fire"},
        {"desc": "a large structure fire engulfing the roof", "type": "structure_fire"},
        {"desc": "thick black smoke pouring out of the apartment window", "type": "structure_fire"}
    ]
    
    fire_event = random.choice(fire_types)
    is_grease = fire_event["type"] == "grease_fire"
    is_electrical = fire_event["type"] == "electrical_fire"
    
    transcript = [
        {"speaker": "911", "text": random.choice(DISPATCHER_PROMPTS)},
        {"speaker": "Caller", "text": f"[{caller}] Quickly! We have {fire_event['desc']} at {location}!"},
        {"speaker": "911", "text": "Is everyone safely evacuated from the immediate area?"},
        {"speaker": "Caller", "text": "Some people are out, but the fire is getting bigger. We are scared."},
        {"speaker": "911", "text": "Stay on the line. I need to give you instructions."},
        {"speaker": "Caller", "text": "Okay, please tell me what we should do!"}
    ]
    
    if is_grease:
        safe_keywords = ["turn off", "cover", "lid", "smother", "baking soda", "extinguisher", "evacuate", "dispatch", "fire truck"]
        unsafe_keywords = ["water", "hose", "carry", "outside", "sink"]
        options = [
            {"text": "Throw water on it immediately.", "label": "unsafe", "explanation": "Water on a grease fire causes a massive explosion of boiling oil. Never use water!"},
            {"text": "Turn off heat and smother it with a metal lid.", "label": "safe", "explanation": "Smothering cuts off oxygen, which is the safest way to kill a grease fire."},
            {"text": "Try to carry the burning pan outside.", "label": "unsafe", "explanation": "Carrying it will spill burning oil on yourself and the floor, spreading the fire."}
        ]
    elif is_electrical:
        safe_keywords = ["turn off", "power", "breaker", "unplug", "extinguisher", "evacuate", "dispatch", "fire truck"]
        unsafe_keywords = ["water", "hose", "touch", "wire", "pull"]
        options = [
            {"text": "Turn off the main breaker and evacuate.", "label": "safe", "explanation": "Cutting power stops the source of ignition safely."},
            {"text": "Grab a bucket of water and douse it.", "label": "unsafe", "explanation": "Water conducts electricity. You will be electrocuted!"},
            {"text": "Try to pull the burning wires out.", "label": "unsafe", "explanation": "Touching burning, live wires is extremely dangerous and lethal."}
        ]
    else: # structure fire
        safe_keywords = ["evacuate", "leave", "stay outside", "get out", "crawl", "smoke", "dispatch", "fire truck"]
        unsafe_keywords = ["go back", "inside", "belongings", "pets", "hide"]
        options = [
            {"text": "Evacuate immediately and stay low under the smoke.", "label": "safe", "explanation": "Smoke inhalation is the deadliest part of a fire. Staying low and getting out saves lives."},
            {"text": "Go back inside to save your valuables.", "label": "unsafe", "explanation": "Never re-enter a burning building for property. Buildings burn extremely fast."},
            {"text": "Hide in a closet to avoid the flames.", "label": "unsafe", "explanation": "Hiding traps you and smoke will still reach you. You must evacuate."}
        ]

    return {
        "id": f"fire_gen_{id_num:03d}",
        "category": "fire",
        "type": fire_event["type"],
        "title": fire_event["desc"].capitalize(),
        "location": location,
        "severity": random.choice(["medium", "high"]),
        "recommended_vehicle": "fire_truck",
        "transcript": transcript,
        "options": options,
        "safe_keywords": safe_keywords,
        "unsafe_keywords": unsafe_keywords
    }

def create_medical_scenario(id_num):
    location = random.choice(LOCATIONS)
    caller = random.choice(CALLER_PERSONAS)
    
    med_types = [
        {"desc": "someone bleeding heavily from a deep cut", "type": "heavy_bleeding"},
        {"desc": "a pedestrian struck by a vehicle with severe lacerations", "type": "heavy_bleeding"},
        {"desc": "an elderly person collapsing and unresponsive", "type": "unconscious_person"},
        {"desc": "someone fell from a ladder and isn't waking up", "type": "unconscious_person"},
        {"desc": "a victim trapped under heavy debris needing extrication", "type": "trapped_victim"},
        {"desc": "a vehicle crash with a passenger caught inside the crushed metal", "type": "trapped_victim"}
    ]
    
    med_event = random.choice(med_types)
    is_bleeding = med_event["type"] == "heavy_bleeding"
    is_unconscious = med_event["type"] == "unconscious_person"
    
    transcript = [
        {"speaker": "911", "text": random.choice(DISPATCHER_PROMPTS)},
        {"speaker": "Caller", "text": f"[{caller}] Help! We are at {location} and there is {med_event['desc']}!"},
        {"speaker": "911", "text": "Are you with the patient right now?"},
        {"speaker": "Caller", "text": "Yes, I am right next to them. It looks bad."},
        {"speaker": "911", "text": "Stay with them. I need you to help them."},
        {"speaker": "Caller", "text": "What do I do while waiting?"}
    ]
    
    if is_bleeding:
        safe_keywords = ["pressure", "clean cloth", "press", "direct pressure", "tourniquet", "elevate", "dispatch", "ambulance"]
        unsafe_keywords = ["remove", "alcohol", "ignore", "wash", "leave"]
        options = [
            {"text": "Remove the bandage to check the wound.", "label": "unsafe", "explanation": "Removing bandages rips off blood clots and causes them to bleed out faster. Add layers, don't remove."},
            {"text": "Apply firm, direct pressure with a clean cloth.", "label": "safe", "explanation": "Direct pressure is the most effective immediate way to stop severe bleeding."},
            {"text": "Wash it with running water.", "label": "unsafe", "explanation": "For heavy bleeding, washing it wastes time and washes away clotting. Apply pressure!"}
        ]
    elif is_unconscious:
        safe_keywords = ["cpr", "compressions", "breathe", "chest", "clear airway", "dispatch", "ambulance"]
        unsafe_keywords = ["shake", "medicine", "water", "food", "slap"]
        options = [
            {"text": "Force them to drink water.", "label": "unsafe", "explanation": "Giving water to an unconscious person will cause them to choke and drown."},
            {"text": "Check their breathing and begin chest compressions if there is no pulse.", "label": "safe", "explanation": "CPR keeps blood flowing to the brain until medics arrive."},
            {"text": "Shake them violently to wake them up.", "label": "unsafe", "explanation": "Shaking can cause severe spinal damage if they fell or collapsed."}
        ]
    else: # trapped victim
        safe_keywords = ["calm", "wait", "do not move", "ambulance", "extricate", "dispatch"]
        unsafe_keywords = ["pull", "yank", "force", "drag"]
        options = [
            {"text": "Try to pull them out with all your strength.", "label": "unsafe", "explanation": "Pulling someone pinned by heavy objects can crush limbs or aggravate spine injuries."},
            {"text": "Keep them calm, warm, and instruct them not to move until the Fire Truck arrives with heavy rescue tools.", "label": "safe", "explanation": "Waiting for trained fire fighters with extrication tools prevents further injury."},
            {"text": "Leave them and look for help.", "label": "unsafe", "explanation": "Leaving a trapped victim alone increases panic and risk of shock."}
        ]

    # A trapped victim is fundamentally an extrication operation requiring a Fire Truck
    vehicle = "fire_truck" if (not is_bleeding and not is_unconscious) else "ambulance"

    return {
        "id": f"med_gen_{id_num:03d}",
        "category": "medical" if vehicle == "ambulance" else "fire",
        "type": med_event["type"],
        "title": med_event["desc"].capitalize(),
        "location": location,
        "severity": random.choice(["medium", "high"]),
        "recommended_vehicle": vehicle,
        "transcript": transcript,
        "options": options,
        "safe_keywords": safe_keywords,
        "unsafe_keywords": unsafe_keywords
    }

def create_criminal_scenario(id_num):
    location = random.choice(LOCATIONS)
    caller = random.choice(CALLER_PERSONAS)
    
    crime_types = [
        {"desc": "an armed robbery in progress at the store", "type": "robbery_in_progress"},
        {"desc": "a violent brawl happening outside", "type": "violent_brawl"},
        {"desc": "someone breaking into a neighbors house", "type": "burglary_in_progress"}
    ]
    
    crime_event = random.choice(crime_types)
    
    transcript = [
        {"speaker": "911", "text": random.choice(DISPATCHER_PROMPTS)},
        {"speaker": "Caller", "text": f"[{caller}] Send police! There is {crime_event['desc']} at {location}!"},
        {"speaker": "911", "text": "Are they armed? Can you get to a safe place?"},
        {"speaker": "Caller", "text": "I think they have weapons. I'm taking cover nearby."},
        {"speaker": "911", "text": "Do not confront them. I need you to stay safe right now."},
        {"speaker": "Caller", "text": "Should I try to stop them or take a video?"}
    ]
    
    safe_keywords = ["hide", "safe", "lock", "stay away", "quiet", "do not confront", "dispatch", "police"]
    unsafe_keywords = ["fight", "attack", "confront", "video", "yell", "stop them"]
    
    options = [
        {"text": "Hide, stay quiet, and do not draw attention to yourself.", "label": "safe", "explanation": "Your life is more important than property. Covering and staying hidden ensures survival."},
        {"text": "Run out and try to film their faces closely.", "label": "unsafe", "explanation": "Filming armed criminals makes you a target and puts your life in extreme danger."},
        {"text": "Yell at them to stop.", "label": "unsafe", "explanation": "Yelling escalates the situation and exposes your location."}
    ]

    return {
        "id": f"crime_gen_{id_num:03d}",
        "category": "criminal",
        "type": crime_event["type"],
        "title": crime_event["desc"].capitalize(),
        "location": location,
        "severity": random.choice(["medium", "high"]),
        "recommended_vehicle": "police",
        "transcript": transcript,
        "options": options,
        "safe_keywords": safe_keywords,
        "unsafe_keywords": unsafe_keywords
    }

def main():
    print("Generating massive scenario dataset...")
    scenarios = []
    
    # Generate 200 of each
    for i in range(200):
        scenarios.append(create_fire_scenario(i))
        scenarios.append(create_medical_scenario(i))
        scenarios.append(create_criminal_scenario(i))
        
    bank = {
        "scenarios": scenarios,
        "locations_ph": LOCATIONS
    }
    
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(bank, f, indent=4)
        
    print(f"Dataset generated! Cleaned and created {len(scenarios)} unique emergency variations.")
    print(f"Saved to: {OUTPUT_FILE}")

if __name__ == "__main__":
    main()
