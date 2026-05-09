extends Node2D

signal finished(car: Node)

@export var vehicle_type: String = "police"
@export var color: Color = Color8(0, 0, 255)
@export var speed_kph: float = 50.0
@export var disappear_km: float = 100.0

var _points: Array = []
var _image_width: int = 0
var _image_height: int = 0
var _map_width_m: float = 1.0
var _map_height_m: float = 1.0
var _total_length_m: float = 1.0
var _total_length_px: float = 1.0
var _traveled_m: float = 0.0
var _pf: PathFollow2D = null
var _rng = RandomNumberGenerator.new()
var _current_speed_kph: float = 0.0
var _target_speed_kph: float = 0.0
var _speed_change_timer: float = 0.0

func _init():
	_rng.randomize()

func setup(points: Array, map_bounds: Dictionary, image_w: int, image_h: int, vehicle_color: Color, speed_kph_in: float, _disappear_km_in: float, start_fraction: float = -1.0) -> void:
	# points: array of {"x":..., "y":...} (normalized 0..1) OR arrays [x,y]
	_points = points.duplicate(true)
	_image_width = int(image_w)
	_image_height = int(image_h)
	var minx = float(map_bounds.get("minx", 0.0))
	var miny = float(map_bounds.get("miny", 0.0))
	var maxx = float(map_bounds.get("maxx", 1.0))
	var maxy = float(map_bounds.get("maxy", 1.0))
	# avoid Python-style inline ternary; use explicit if/else for GDScript
	if (maxx - minx) != 0.0:
		_map_width_m = maxx - minx
	else:
		_map_width_m = 1.0

	if (maxy - miny) != 0.0:
		_map_height_m = maxy - miny
	else:
		_map_height_m = 1.0
	
	speed_kph = float(speed_kph_in)
	# pick a random disappear distance between 100 km and 500 km
	disappear_km = _rng.randf_range(100.0, 500.0)
	_current_speed_kph = clamp(speed_kph, 30.0, 80.0)
	_target_speed_kph = _current_speed_kph
	_speed_change_timer = _rng.randf_range(1.5, 4.0)
	
	# Build Path2D
	var route_path = Path2D.new()
	var curve = Curve2D.new()
	for p in _points:
		var nx: float = 0.0
		var ny: float = 0.0
		if typeof(p) == TYPE_DICTIONARY:
			nx = float(p.get("x", 0.0))
			ny = float(p.get("y", 0.0))
		elif typeof(p) == TYPE_ARRAY and p.size() >= 2:
			nx = float(p[0])
			ny = float(p[1])
		else:
			continue
		var px = nx * float(_image_width)
		var py = ny * float(_image_height)
		curve.add_point(Vector2(px, py))
	route_path.curve = curve
	add_child(route_path)

	# PathFollow2D (we'll set initial progress after computing total lengths)
	_pf = PathFollow2D.new()
	_pf.loop = true
	_pf.rotates = false
	route_path.add_child(_pf)

	# Visual marker: use vehicle icon SVG if available, otherwise fall back to polygon.
	var icon_path := "res://assets/ui/icons/police.svg"
	match vehicle_type:
		"fire_truck":
			icon_path = "res://assets/ui/icons/fire_truck.svg"
		"ambulance":
			icon_path = "res://assets/ui/icons/ambulance.svg"
		"police":
			icon_path = "res://assets/ui/icons/police.svg"

	if ResourceLoader.exists(icon_path):
		var tex = load(icon_path)
		if tex is Texture2D:
			var sprite = Sprite2D.new()
			sprite.texture = tex
			sprite.scale = Vector2(0.58, 0.58)
			# Keep original icon colors (no overlay tint).
			sprite.modulate = Color.WHITE
			_pf.add_child(sprite)
		else:
			var poly = Polygon2D.new()
			poly.polygon = PackedVector2Array([Vector2(0, -10), Vector2(8, 10), Vector2(-8, 10)])
			poly.color = Color.WHITE
			_pf.add_child(poly)
	else:
		var poly = Polygon2D.new()
		poly.polygon = PackedVector2Array([Vector2(0, -10), Vector2(8, 10), Vector2(-8, 10)])
		poly.color = Color.WHITE
		_pf.add_child(poly)

	# Compute total real-world length (meters) and pixel length from curve points
	_total_length_m = 0.0
	_total_length_px = 0.0
	for i in range(curve.get_point_count() - 1):
		var p1 = curve.get_point_position(i)
		var p2 = curve.get_point_position(i + 1)
		# pixel distance
		_total_length_px += p1.distance_to(p2)
		# convert pixel deltas to normalized deltas then to meters for real-world length
		var dx_norm = (p2.x - p1.x) / float(_image_width)
		var dy_norm = (p2.y - p1.y) / float(_image_height)
		var dx_m = dx_norm * _map_width_m
		var dy_m = dy_norm * _map_height_m
		_total_length_m += sqrt(dx_m * dx_m + dy_m * dy_m)

	if _total_length_m <= 0.0:
		_total_length_m = 1.0

	if _total_length_px <= 0.0:
		_total_length_px = 1.0

	# pick a starting progress along the path (in pixels)
	if start_fraction >= 0.0:
		_pf.progress = clamp(start_fraction, 0.0, 1.0) * _total_length_px
	else:
		_pf.progress = _rng.randf() * _total_length_px

	_traveled_m = 0.0
	set_process(true)

func _process(delta: float) -> void:
	if _pf == null:
		return

	var remaining_m = max(0.0, disappear_km * 1000.0 - _traveled_m)
	var slowdown_window_m = 5000.0
	var max_allowed_speed = 80.0
	if remaining_m <= slowdown_window_m:
		max_allowed_speed = max(0.0, 80.0 * (remaining_m / slowdown_window_m))
	if remaining_m <= 50.0:
		max_allowed_speed = 0.0

	_speed_change_timer -= delta
	if _speed_change_timer <= 0.0:
		_target_speed_kph = _rng.randf_range(30.0, 80.0)
		_speed_change_timer = _rng.randf_range(1.5, 4.0)

	_target_speed_kph = min(_target_speed_kph, max_allowed_speed)
	var accel_rate = 25.0 # km/h per second for gradual changes
	var diff = _target_speed_kph - _current_speed_kph
	var step = clamp(diff, -accel_rate * delta, accel_rate * delta)
	_current_speed_kph = clamp(_current_speed_kph + step, 0.0, max_allowed_speed)

	var speed_mps = _current_speed_kph / 3.6
	var pixels_per_meter = _total_length_px / _total_length_m
	var speed_px_per_s = speed_mps * pixels_per_meter
	var inc_px = speed_px_per_s * delta
	var new_progress = _pf.progress + inc_px
	if _total_length_px > 0 and new_progress >= _total_length_px:
		new_progress -= floor(new_progress / _total_length_px) * _total_length_px
	_pf.progress = new_progress

	_traveled_m += speed_mps * delta
	if _traveled_m >= disappear_km * 1000.0 or max_allowed_speed <= 0.0:
		# notify manager so it can spawn a replacement
		emit_signal("finished", self)
		queue_free()

func stop_and_remove() -> void:
	set_process(false)
	queue_free()

func get_vehicle_position() -> Vector2:
	if _pf:
		return _pf.position
	return global_position
