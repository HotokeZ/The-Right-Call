with open('scripts/maps/route_scene.gd', 'r', encoding='utf-8') as f:
    lines = f.readlines()

new_lines = []
skip = False
for line in lines:
    if line.startswith("func _get_scenario_options() -> Array:"):
        skip = True
        continue
    
    # We want to skip the body of _get_scenario_options
    if skip:
        if line.startswith("\t"):
            continue
        elif line.strip() == "":
            continue
        else:
            skip = False
            
    if not skip:
        new_lines.append(line)

with open('scripts/maps/route_scene.gd', 'w', encoding='utf-8') as f:
    f.writelines(new_lines)
