extends Node2D

@export var route_file_path: String = "res://data/routes/citywide_patrol_route.json"
@export var image_width: int = 1024
@export var image_height: int = 1024
@export var duration: float = 60.0
@export var loop_patrol: bool = true
@export var patrol_speed: float = 1.0
@export var spawn_pin: bool = true

var _progress: float = 0.0
var _pf: PathFollow2D = null

func _ready():
	call_deferred("_deferred_load")


func _deferred_load() -> void:
	if FileAccess.file_exists(route_file_path):
		_load_and_play(route_file_path)
	else:
		print("Route file not found:", route_file_path)


func _load_and_play(path: String) -> void:
	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		push_error("Failed to open route file: %s" % path)
		return
	var txt = f.get_as_text()
	var parsed = JSON.parse_string(txt)
	# JSON.parse_string may return either a wrapper with keys {"error","result"}
	# or may directly return the parsed Dictionary/Array depending on Godot version.
	var root: Variant
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("error"):
		var err = parsed.get("error")
		if err != OK:
			push_error("Failed to parse JSON: error %d" % err)
			return
		root = parsed.get("result")
	else:
		root = parsed

	var pts: Array = []
	if typeof(root) == TYPE_DICTIONARY and root.has("points"):
		pts = root.get("points")
	elif typeof(root) == TYPE_ARRAY:
		# allow raw array of points as fallback
		pts = root
	else:
		push_error("Route file has no 'points' array")
		return

	# If this instance should not spawn the visual pin (multi-car manager handles visuals), stop here
	if not spawn_pin:
		return

	# Build Path2D with Curve2D
	var route_path = Path2D.new()
	var curve = Curve2D.new()
	for p in pts:
		# Handle both Dictionary format {"x": ..., "y": ...} and Array format [x, y]
		var nx: float
		var ny: float
		
		if typeof(p) == TYPE_DICTIONARY:
			# New format: {"x": 0.5, "y": 0.3}
			nx = float(p.get("x", 0.0))
			ny = float(p.get("y", 0.0))
		elif typeof(p) == TYPE_ARRAY and p.size() >= 2:
			# Old format: [0.5, 0.3]
			nx = float(p[0])
			ny = float(p[1])
		else:
			push_error("Invalid point format in route data")
			continue
			
		var px = nx * float(image_width)
		var py = ny * float(image_height)
		curve.add_point(Vector2(px, py))
	route_path.curve = curve
	add_child(route_path)

	var pf = PathFollow2D.new()
	route_path.add_child(pf)
	_pf = pf

	# Create a simple triangular pin if no texture exists
	var pin_texture: Texture2D = null
	if ResourceLoader.exists("res://pin.png"):
		pin_texture = load("res://pin.png")
	if pin_texture:
		var sprite = Sprite2D.new()
		sprite.texture = pin_texture
		pf.add_child(sprite)
	else:
		var poly = Polygon2D.new()
		var polygon = PackedVector2Array([Vector2(0, -8), Vector2(6, 8), Vector2(-6, 8)])
		poly.polygon = polygon
		poly.color = Color8(255, 80, 0)
		pf.add_child(poly)

	# compute total length from the points we added and animate the PathFollow2D `offset`
	var positions: Array = []
	for i in range(curve.get_point_count()):
		positions.append(curve.get_point_position(i))

	var total_length: float = 0.0
	for i in range(positions.size() - 1):
		total_length += positions[i].distance_to(positions[i + 1])

	pf.progress = 0.0

	# tween a local float `_progress` and update pf.progress each frame
	_progress = 0.0
	var tw = get_tree().create_tween()
	
	# Check if this is a patrol loop
	var is_patrol_loop = false
	if typeof(root) == TYPE_DICTIONARY and root.has("is_loop"):
		is_patrol_loop = root.get("is_loop", false) and loop_patrol
	
	if is_patrol_loop:
		# Infinite continuous patrol loop
		tw.set_loops()
		tw.tween_property(self, "_progress", total_length, duration / patrol_speed).set_trans(Tween.TRANS_LINEAR)
	else:
		# One-time route
		tw.tween_property(self, "_progress", total_length, duration / patrol_speed).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)

func _process(_delta: float) -> void:
	if _pf:
		_pf.progress = _progress

#End Patch
