import sys

with open('scripts/maps/route_scene.gd', 'r', encoding='utf-8') as f:
    content = f.read()

old_func = """func _build_station_building_badge(parent: Node2D, vtype: String) -> void:
	var sprite := Sprite2D.new()
	var texture_path := ""
	match vtype:
		"fire_truck":
			texture_path = "res://assets/The Right Call Sprites/bfp building.png"
			sprite.flip_h = true
			sprite.z_index = 3
			sprite.offset = Vector2(0, -112)
		"ambulance":
			texture_path = "res://assets/The Right Call Sprites/Lagunadocs.png"
			sprite.z_index = 2
			sprite.offset = Vector2(0, -112)
		_:
			texture_path = "res://assets/The Right Call Sprites/Policestation.png"
			sprite.flip_h = true
			sprite.z_index = 4
			sprite.offset = Vector2(0, -112)

	var tex = load(texture_path)
	if tex:
		sprite.texture = tex
		# scale down if large
		if tex.get_width() > 300:
			sprite.scale = Vector2(0.5, 0.5)
	parent.add_child(sprite)"""

old_func2 = old_func.replace('bfp building.png', 'BFPstation.png').replace('Lagunadocs.png', 'hospitalsss.png')

new_func = """func _build_station_building_badge(parent: Node2D, vtype: String) -> void:
	var pin = Polygon2D.new()
	# Triangle pointing down to the origin
	pin.polygon = PackedVector2Array([
		Vector2(-40, -80),
		Vector2(40, -80),
		Vector2(0, 0)
	])
	pin.color = Color(1.0, 0.9, 0.1, 1.0) # Yellow
	pin.z_index = 10
	
	var outline = Line2D.new()
	outline.points = PackedVector2Array([
		Vector2(-40, -80),
		Vector2(40, -80),
		Vector2(0, 0),
		Vector2(-40, -80)
	])
	outline.width = 4.0
	outline.default_color = Color(0, 0, 0, 1)
	outline.z_index = 11
	
	parent.add_child(pin)
	parent.add_child(outline)"""

if old_func in content:
    content = content.replace(old_func, new_func)
    print('Replaced exact match 1')
elif old_func2 in content:
    content = content.replace(old_func2, new_func)
    print('Replaced exact match 2')
else:
    print('Could not find exact function match!')

with open('scripts/maps/route_scene.gd', 'w', encoding='utf-8') as f:
    f.write(content)
