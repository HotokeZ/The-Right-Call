extends Node2D

signal response_arrived(vehicle_id: String, world_position: Vector2)
signal response_position_updated(vehicle_id: String, world_position: Vector2)

@export var route_file_path: String = "res://data/routes/citywide_patrol_route.json"
@export var bounds_file_path: String = "res://assets/maps/map.bounds.json"
@export var station_file_path: String = "res://data/gameplay/service_stations.json"
@export var image_width: int = 1024
@export var image_height: int = 1024
@export var max_cars: int = 5
@export var default_speed_kph: float = 125.0
@export var disappear_km: float = 100.0
@export var respawn_delay_min: float = 5.0
@export var respawn_delay_max: float = 10.0
@export var dispatch_from_station_only: bool = true
@export var professional_response_speed_kph: float = 120.0
@export var route_graph_link_radius_px: float = 48.0
@export var route_graph_max_shortcuts_per_node: int = 4
@export var route_graph_cell_size_px: float = 64.0
@export var route_graph_max_nearest_rings: int = 3

var route_points: Array = []
var regions = {
	"north": [],
	"east": [],
	"south": []
}
var _rng = RandomNumberGenerator.new()
var active_cars: Array = []
var _map_bounds: Dictionary = {}
var _service_stations: Array = []
var _route_px_points: Array = []
var _route_astar: AStar2D = AStar2D.new()
var _route_spatial_cells: Dictionary = {}
var _route_graph_ready: bool = false

var vehicle_types = ["police", "fire_truck", "ambulance"]
var vehicle_colors = {
	"police": Color8(10, 80, 255),
	"fire_truck": Color8(200, 20, 20),
	"ambulance": Color8(10, 200, 40)
}

# Approximate real facilities converted from web mercator bounds.
# BFP candidate was outside map east bound, so we clamp to map edge.
var _service_bases_norm = {
	"ambulance": Vector2(0.732, 0.545), # Laguna Medical Center area
	"police": Vector2(0.539, 0.518), # Camp Paciano Rizal / police area
	"fire_truck": Vector2(0.5463, 0.4813) # BFP Santa Cruz Fire Station (maps link)
}

func _ready() -> void:
	_rng.randomize()
	# Keep startup cheap on web/mobile-class devices.
	if OS.has_feature("web"):
		max_cars = min(max_cars, 3)
		route_graph_max_shortcuts_per_node = min(route_graph_max_shortcuts_per_node, 2)
		route_graph_link_radius_px = min(route_graph_link_radius_px, 40.0)
		route_graph_max_nearest_rings = min(route_graph_max_nearest_rings, 2)
	load_route()
	_build_route_graph()
	_load_service_stations()
	_snap_service_stations_to_route_points()
	_apply_service_station_bases()
	_load_bounds()
	_partition_regions()
	# stagger initial spawns with slight randomness
	for i in range(max_cars):
		var seeded_type = vehicle_types[i % max(1, vehicle_types.size())]
		_spawn_with_delay(i * 0.8 + _rng.randf_range(0.0, 0.5), seeded_type)

func _load_service_stations() -> void:
	_service_stations.clear()
	if not FileAccess.file_exists(station_file_path):
		return
	var f = FileAccess.open(station_file_path, FileAccess.READ)
	if not f:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	var root = parsed
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("stations"):
		root = parsed.get("stations")
	if typeof(root) != TYPE_ARRAY:
		return

	for row_any in root:
		if typeof(row_any) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_any
		var vtype = String(row.get("type", "")).strip_edges().to_lower()
		if not vehicle_types.has(vtype):
			continue
		var nx = clamp(float(row.get("x", 0.5)), 0.0, 1.0)
		var ny = clamp(float(row.get("y", 0.5)), 0.0, 1.0)
		var station = {
			"type": vtype,
			"name": String(row.get("name", _vehicle_name(vtype) + " Station")),
			"x": nx,
			"y": ny
		}
		_service_stations.append(station)


func _apply_service_station_bases() -> void:
	# If a station exists for a responder type, use the first one as its dispatch base.
	for vtype in vehicle_types:
		for st_any in _service_stations:
			var st: Dictionary = st_any
			if String(st.get("type", "")) == vtype:
				_service_bases_norm[vtype] = Vector2(float(st.get("x", 0.5)), float(st.get("y", 0.5)))
				break

func _closest_route_px_point(px_point: Vector2) -> Vector2:
	if _route_px_points.is_empty():
		return px_point
	var best_idx = 0
	var best_dist = INF
	for i in range(_route_px_points.size()):
		var d = (_route_px_points[i] as Vector2).distance_squared_to(px_point)
		if d < best_dist:
			best_dist = d
			best_idx = i
	return _route_px_points[best_idx]

func _snap_service_stations_to_route_points() -> void:
	if _service_stations.is_empty() or _route_px_points.is_empty():
		return
	for i in range(_service_stations.size()):
		var st: Dictionary = _service_stations[i]
		var nx = clamp(float(st.get("x", 0.5)), 0.0, 1.0)
		var ny = clamp(float(st.get("y", 0.5)), 0.0, 1.0)
		var raw_px = Vector2(nx * float(image_width), ny * float(image_height))
		var snapped_px = _closest_route_px_point(raw_px)
		st["x"] = clamp(snapped_px.x / float(max(1, image_width)), 0.0, 1.0)
		st["y"] = clamp(snapped_px.y / float(max(1, image_height)), 0.0, 1.0)
		_service_stations[i] = st

func load_route() -> void:
	if not FileAccess.file_exists(route_file_path):
		push_error("Route file not found: %s" % route_file_path)
		return
	var f = FileAccess.open(route_file_path, FileAccess.READ)
	if not f:
		push_error("Failed to open route file: %s" % route_file_path)
		return
	var txt = f.get_as_text()
	var parsed = JSON.parse_string(txt)
	var root = parsed
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("error"):
		# handle wrapper
		if parsed.get("error") != OK:
			push_error("Failed to parse route JSON: %s" % route_file_path)
			return
		root = parsed.get("result")

	if typeof(root) == TYPE_DICTIONARY and root.has("points"):
		route_points = root.get("points")
	elif typeof(root) == TYPE_ARRAY:
		route_points = root
	else:
		push_error("Route data does not contain points")
		return
	_route_astar.clear()
	_route_spatial_cells.clear()
	_route_graph_ready = false

func _load_bounds() -> void:
	if FileAccess.file_exists(bounds_file_path):
		var bf = FileAccess.open(bounds_file_path, FileAccess.READ)
		if bf:
			var bj = JSON.parse_string(bf.get_as_text())
			if typeof(bj) == TYPE_DICTIONARY:
				_map_bounds = bj
			else:
				_map_bounds = {}
	else:
		_map_bounds = {}

func _partition_regions() -> void:
	# Partition route points into three geographic bands (north, east, south)
	if route_points.size() == 0:
		return
	var xs: Array = []
	var ys: Array = []
	for p in route_points:
		var x = 0.0
		var y = 0.0
		if typeof(p) == TYPE_DICTIONARY:
			x = float(p.get("x", 0.0))
			y = float(p.get("y", 0.0))
		elif typeof(p) == TYPE_ARRAY and p.size() >= 2:
			x = float(p[0])
			y = float(p[1])
		xs.append(x)
		ys.append(y)

	var xmin = xs.min()
	var xmax = xs.max()
	var ymin = ys.min()
	var ymax = ys.max()
	var xspan = xmax - xmin
	var yspan = ymax - ymin
	if xspan <= 0 or yspan <= 0:
		return

	var top_th = ymin + yspan / 3.0
	var bottom_th = ymin + 2.0 * yspan / 3.0
	var right_th = xmin + 2.0 * xspan / 3.0

	# Build contiguous segments for named regions using a top-level helper
	regions["north"] = _build_segments_for_label("north", top_th, bottom_th, right_th)
	regions["east"] = _build_segments_for_label("east", top_th, bottom_th, right_th)
	regions["south"] = _build_segments_for_label("south", top_th, bottom_th, right_th)

	# If any region is empty, fallback to picking larger slices
	for k in ["north", "east", "south"]:
		if regions[k].size() == 0:
			# fallback: pick contiguous slices from route
			var fallback: Array = []
			var idx = int((_rng.randf() * max(0, route_points.size() - 200)))
			for j in range(idx, min(idx + 300, route_points.size())):
				fallback.append(route_points[j])
			regions[k] = [fallback]

func _spawn_with_delay(delay: float, preferred_type: String = "") -> void:
	# Use await to wait for the timer then spawn
	await get_tree().create_timer(delay).timeout
	_spawn_car(preferred_type)

func _spawn_car(preferred_type: String = "") -> void:
	# Keep at most max_cars active
	if active_cars.size() >= max_cars:
		# schedule another try
		_spawn_with_delay(_rng.randf_range(respawn_delay_min, respawn_delay_max))
		return

	# Choose vehicle type (duplicates allowed)
	var vtype = preferred_type
	if not vehicle_types.has(vtype):
		vtype = vehicle_types[_rng.randi_range(0, vehicle_types.size() - 1)]
	var vcolor = vehicle_colors.get(vtype, Color8(255, 255, 255))

	# Spawn patrol from its designated station and move out along a random direction.
	var seg: Array = _route_slice_from_station(vtype)
	if seg.size() < 8:
		seg = _random_route_slice()
	if seg.size() < 8:
		return

	# instantiate PatrolCar
	var script = load("res://scripts/vehicles/patrol_car.gd")
	var car = script.new()
	car.vehicle_type = vtype
	car.color = vcolor
	# set up the car
	var start_frac = 0.0
	car.setup(seg, _map_bounds, image_width, image_height, vcolor, default_speed_kph, disappear_km, start_frac)
	car.connect("finished", Callable(self, "_on_car_finished"))
	add_child(car)
	active_cars.append(car)

	# Spawn next car later if we still have capacity
	if active_cars.size() < max_cars:
		_spawn_with_delay(_rng.randf_range(respawn_delay_min, respawn_delay_max))

func _route_slice_from_station(vtype: String, min_len: int = 240, max_len: int = 420) -> Array:
	if route_points.is_empty():
		return []
	var n = route_points.size()
	var base_px = _norm_to_px(_base_norm_for_type(vtype))
	var base_idx = _closest_route_index_to_point(base_px)
	var dir = 1
	if _rng.randf() < 0.5:
		dir = -1
	var slice_len = _rng.randi_range(min_len, max_len)
	var seg: Array = []
	for step in range(slice_len):
		var idx = (base_idx + dir * step) % n
		if idx < 0:
			idx += n
		seg.append(route_points[idx])
	return seg

func _norm_to_px(norm_pos: Vector2) -> Vector2:
	var nx = clamp(norm_pos.x, 0.0, 1.0)
	var ny = clamp(norm_pos.y, 0.0, 1.0)
	return Vector2(nx * float(image_width), ny * float(image_height))

func _base_norm_for_type(vtype: String) -> Vector2:
	var base = _service_bases_norm.get(vtype, Vector2(0.5, 0.5))
	if base is Vector2:
		return base
	return Vector2(0.5, 0.5)

func _closest_route_index_to_point(px_point: Vector2) -> int:
	if _route_graph_ready:
		return _closest_route_index_for_px(px_point)
	if route_points.is_empty():
		return 0
	var best_idx = 0
	var best_dist = INF
	for i in range(route_points.size()):
		var p = route_points[i]
		var nx = 0.0
		var ny = 0.0
		if typeof(p) == TYPE_DICTIONARY:
			nx = float(p.get("x", 0.0))
			ny = float(p.get("y", 0.0))
		elif typeof(p) == TYPE_ARRAY and p.size() >= 2:
			nx = float(p[0])
			ny = float(p[1])
		var px = Vector2(nx * float(image_width), ny * float(image_height))
		var d = px.distance_squared_to(px_point)
		if d < best_dist:
			best_dist = d
			best_idx = i
	return best_idx

func _start_fraction_for_vehicle_type(vtype: String) -> float:
	if route_points.is_empty():
		return _rng.randf()
	var base_norm = _base_norm_for_type(vtype)
	var base_px = _norm_to_px(base_norm)
	var idx = _closest_route_index_to_point(base_px)
	if route_points.size() <= 1:
		return 0.0
	return clamp(float(idx) / float(route_points.size() - 1), 0.0, 1.0)

func _vehicle_icon_path(vtype: String) -> String:
	match vtype:
		"fire_truck":
			return "res://assets/ui/icons/fire_truck.svg"
		"ambulance":
			return "res://assets/ui/icons/ambulance.svg"
		_:
			return "res://assets/ui/icons/police.svg"

func _vehicle_name(vtype: String) -> String:
	match vtype:
		"fire_truck":
			return "Fire Truck"
		"ambulance":
			return "Ambulance"
		_:
			return "Police"

func get_service_station_markers() -> Array:
	var out: Array = []
	if _service_stations.is_empty():
		for k in _service_bases_norm.keys():
			var norm: Vector2 = _service_bases_norm[k]
			out.append({
				"type": String(k),
				"name": _vehicle_name(String(k)) + " Station",
				"position": _norm_to_px(norm)
			})
		return out

	for st_any in _service_stations:
		var st: Dictionary = st_any
		var norm = Vector2(float(st.get("x", 0.5)), float(st.get("y", 0.5)))
		out.append({
			"type": String(st.get("type", "police")),
			"name": String(st.get("name", "Station")),
			"position": _norm_to_px(norm)
		})
	return out

func _closest_active_car_of_type(vtype: String, target_world: Vector2) -> Node:
	var best_car: Node = null
	var best_dist = INF
	var target_local = _as_manager_local_point(target_world)
	for car in active_cars:
		if car == null or not car.is_inside_tree():
			continue
		if not car.has_method("get_vehicle_position"):
			continue
		if String(car.get("vehicle_type")) != vtype:
			continue
		var car_pos = car.call("get_vehicle_position")
		if car_pos is Vector2:
			var local_car = _as_manager_local_point(car_pos)
			var d = local_car.distance_squared_to(target_local)
			if d < best_dist:
				best_dist = d
				best_car = car
	return best_car

func _closest_active_car(target_world: Vector2) -> Node:
	var best_car: Node = null
	var best_dist = INF
	var target_local = _as_manager_local_point(target_world)
	for car in active_cars:
		if car == null or not car.is_inside_tree():
			continue
		if not car.has_method("get_vehicle_position"):
			continue
		var car_pos = car.call("get_vehicle_position")
		if car_pos is Vector2:
			var local_car = _as_manager_local_point(car_pos)
			var d = local_car.distance_squared_to(target_local)
			if d < best_dist:
				best_dist = d
				best_car = car
	return best_car

func _as_manager_local_point(point: Vector2) -> Vector2:
	var p = point
	var bounds = Rect2(Vector2.ZERO, Vector2(float(image_width), float(image_height)))
	if not bounds.has_point(p):
		p = to_local(point)
	p.x = clamp(p.x, 0.0, float(image_width))
	p.y = clamp(p.y, 0.0, float(image_height))
	return p

func dispatch_response_unit(vtype: String, target_world: Vector2, travel_s: float = 2.0) -> void:
	var source = _norm_to_px(_base_norm_for_type(vtype))
	target_world = _as_manager_local_point(target_world)
	if not dispatch_from_station_only:
		var car = _closest_active_car_of_type(vtype, target_world)
		if car == null:
			car = _closest_active_car(target_world)
		if car:
			var car_pos = car.call("get_vehicle_position")
			if car_pos is Vector2:
				source = _as_manager_local_point(car_pos)
		else:
			# Ensure at least one matching patrol appears in circulation.
			_spawn_car(vtype)

	source = _as_manager_local_point(source)
	if travel_s <= 0.0:
		travel_s = _travel_time_from_source_to_target_s(source, target_world)
	travel_s = max(1.0, travel_s)

	var responder = Node2D.new()
	responder.position = source
	add_child(responder)

	var icon_path = _vehicle_icon_path(vtype)
	if ResourceLoader.exists(icon_path):
		var tex = load(icon_path)
		if tex is Texture2D:
			var sprite = Sprite2D.new()
			sprite.texture = tex
			sprite.scale = Vector2(0.62, 0.62)
			responder.add_child(sprite)

	# Find a path using route waypoints instead of direct line
	var path = _find_path_through_route(source, target_world)
	if path.size() < 2:
		path = [source, target_world]
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.set_ease(Tween.EASE_IN_OUT)
	emit_signal("response_position_updated", vtype, responder.position)
	
	# Animate along the path waypoints
	var total_dist = 0.0
	for i in range(1, path.size()):
		total_dist += (path[i - 1] as Vector2).distance_to(path[i] as Vector2)
	total_dist = max(total_dist, 1.0)
	for i in range(1, path.size()):
		var a: Vector2 = path[i - 1]
		var b: Vector2 = path[i]
		var segment_dist = a.distance_to(b)
		# Keep animation duration aligned with gameplay ETA.
		var segment_time = max(0.08, (segment_dist / total_dist) * max(0.25, travel_s))
		tween.tween_method(Callable(self, "_set_responder_position").bind(responder, vtype), a, b, segment_time)

	# Emit arrival exactly when responder reaches destination, before fade-out.
	tween.tween_callback(Callable(self, "_emit_response_arrived").bind(vtype, target_world))
	tween.tween_property(responder, "modulate:a", 0.0, 0.25)
	tween.finished.connect(responder.queue_free)

func _travel_time_from_source_to_target_s(source: Vector2, target_world: Vector2) -> float:
	if _map_bounds.is_empty():
		# Fallback to map pixels if we don't have georeferenced bounds.
		var pixel_distance_m = source.distance_to(target_world) * 6.5
		return pixel_distance_m / max(1.0, (professional_response_speed_kph * 1000.0) / 3600.0)
	var src_m = _px_to_mercator(source)
	var dst_m = _px_to_mercator(target_world)
	var distance_m = src_m.distance_to(dst_m)
	return distance_m / max(1.0, (professional_response_speed_kph * 1000.0) / 3600.0)

func _px_to_mercator(px: Vector2) -> Vector2:
	var minx = float(_map_bounds.get("minx", 0.0))
	var miny = float(_map_bounds.get("miny", 0.0))
	var maxx = float(_map_bounds.get("maxx", 1.0))
	var maxy = float(_map_bounds.get("maxy", 1.0))
	var tx = clamp(px.x / float(max(1, image_width)), 0.0, 1.0)
	var ty = clamp(px.y / float(max(1, image_height)), 0.0, 1.0)
	return Vector2(lerp(minx, maxx, tx), lerp(miny, maxy, ty))

func _emit_response_arrived(vehicle_id: String, world_position: Vector2) -> void:
	emit_signal("response_arrived", vehicle_id, world_position)

func _set_responder_position(pos: Vector2, responder: Node2D, vehicle_id: String) -> void:
	if responder == null or not is_instance_valid(responder):
		return
	responder.position = pos
	emit_signal("response_position_updated", vehicle_id, pos)

func _route_point_to_px(pt) -> Vector2:
	var nx = 0.0
	var ny = 0.0
	if typeof(pt) == TYPE_DICTIONARY:
		nx = float(pt.get("x", 0.0))
		ny = float(pt.get("y", 0.0))
	elif typeof(pt) == TYPE_ARRAY and pt.size() >= 2:
		nx = float(pt[0])
		ny = float(pt[1])
	return Vector2(nx * float(image_width), ny * float(image_height))

func _build_route_graph() -> void:
	_route_px_points.clear()
	_route_astar.clear()
	_route_spatial_cells.clear()
	if route_points.is_empty():
		_route_graph_ready = false
		return

	for pt in route_points:
		_route_px_points.append(_route_point_to_px(pt))

	var total_points = _route_px_points.size()
	if total_points == 0:
		_route_graph_ready = false
		return

	# Add all route points as graph nodes and index into spatial hash.
	for i in range(total_points):
		var p = _route_px_points[i] as Vector2
		_route_astar.add_point(i, p)
		_add_point_to_spatial_index(i, p)

	# Always keep route continuity with sequential links.
	for i in range(total_points - 1):
		if not _route_astar.are_points_connected(i, i + 1):
			_route_astar.connect_points(i, i + 1, true)

	# Add limited local shortcuts using a spatial hash to avoid O(n^2) neighbor checks.
	var radius = max(8.0, route_graph_link_radius_px)
	var radius_sq = radius * radius
	var max_shortcuts = max(0, route_graph_max_shortcuts_per_node)
	for i in range(total_points):
		var pi = _route_px_points[i] as Vector2
		var candidates = _collect_candidates_in_radius(pi, radius)
		var nearby: Array = []
		for c_any in candidates:
			var j = int(c_any)
			if j == i:
				continue
			if abs(j - i) <= 1:
				continue
			var pj = _route_px_points[j] as Vector2
			var dsq = pi.distance_squared_to(pj)
			if dsq <= radius_sq:
				nearby.append({"idx": j, "dist": dsq})

		nearby.sort_custom(func(a, b): return float(a["dist"]) < float(b["dist"]))
		var added = 0
		for item in nearby:
			if added >= max_shortcuts:
				break
			var j = int(item["idx"])
			if not _route_astar.are_points_connected(i, j):
				_route_astar.connect_points(i, j, true)
				added += 1

	_route_graph_ready = true

func _spatial_key(cx: int, cy: int) -> String:
	return str(cx) + ":" + str(cy)

func _cell_coords_for_point(px: Vector2) -> Vector2i:
	var cell = max(4.0, route_graph_cell_size_px)
	return Vector2i(int(floor(px.x / cell)), int(floor(px.y / cell)))

func _add_point_to_spatial_index(node_id: int, px: Vector2) -> void:
	var c = _cell_coords_for_point(px)
	var key = _spatial_key(c.x, c.y)
	if not _route_spatial_cells.has(key):
		_route_spatial_cells[key] = []
	(_route_spatial_cells[key] as Array).append(node_id)

func _collect_candidates_in_radius(px: Vector2, radius: float) -> Array:
	var out: Array = []
	if _route_spatial_cells.is_empty():
		return out
	var c = _cell_coords_for_point(px)
	var cell = max(4.0, route_graph_cell_size_px)
	var ring = int(ceil(radius / cell))
	for dx in range(-ring, ring + 1):
		for dy in range(-ring, ring + 1):
			var key = _spatial_key(c.x + dx, c.y + dy)
			if _route_spatial_cells.has(key):
				out.append_array(_route_spatial_cells[key] as Array)
	return out

func _closest_route_index_for_px(px: Vector2) -> int:
	if not _route_graph_ready or _route_px_points.is_empty():
		return 0

	var center = _cell_coords_for_point(px)
	var max_rings = max(1, route_graph_max_nearest_rings)
	var best_idx = 0
	var best_dist = INF
	var found_any = false

	for ring in range(max_rings + 1):
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if ring > 0 and abs(dx) < ring and abs(dy) < ring:
					continue
				var key = _spatial_key(center.x + dx, center.y + dy)
				if not _route_spatial_cells.has(key):
					continue
				for idx_any in (_route_spatial_cells[key] as Array):
					var idx = int(idx_any)
					var d = (_route_px_points[idx] as Vector2).distance_squared_to(px)
					if d < best_dist:
						best_dist = d
						best_idx = idx
						found_any = true
		if found_any and ring >= 1:
			break

	if not found_any:
		for i in range(_route_px_points.size()):
			var d = (_route_px_points[i] as Vector2).distance_squared_to(px)
			if d < best_dist:
				best_dist = d
				best_idx = i
	return best_idx

func _simplify_polyline(points: Array) -> Array:
	if points.size() <= 2:
		return points
	var simplified: Array = [points[0]]
	for i in range(1, points.size() - 1):
		var a = simplified[simplified.size() - 1] as Vector2
		var b = points[i] as Vector2
		var c = points[i + 1] as Vector2
		var ab = b - a
		var bc = c - b
		if ab.length_squared() < 9.0:
			continue
		if bc.length_squared() < 9.0:
			continue
		var turn_cos = ab.normalized().dot(bc.normalized())
		# Skip tiny direction changes to reduce jitter in tweened movement.
		if turn_cos > 0.995:
			continue
		simplified.append(b)
	simplified.append(points[points.size() - 1])
	return simplified

func _find_path_through_route(from: Vector2, to: Vector2) -> Array:
	if route_points.is_empty():
		return [from, to]
	if not _route_graph_ready:
		_build_route_graph()
	if not _route_graph_ready or _route_px_points.is_empty():
		return [from, to]

	var start_idx = _closest_route_index_for_px(from)
	var end_idx = _closest_route_index_for_px(to)
	if start_idx == end_idx:
		return [from, _route_px_points[start_idx], to]

	var id_path = _route_astar.get_id_path(start_idx, end_idx)
	if id_path.is_empty():
		return [from, to]

	var path: Array = [from]
	for id_any in id_path:
		var idx = int(id_any)
		path.append(_route_px_points[idx])
	path.append(to)

	return _simplify_polyline(path)

func _region_load_cmp(a, b) -> int:
	# Compare how many active cars are in the region by testing their centroid
	var a_count = 0
	var b_count = 0
	for car in active_cars:
		if car and car.is_inside_tree():
			var cx = 0.0
			var cy = 0.0
			# guess region by car position normalized
			if car.has_method("get_global_position"):
				cx = car.global_position.x / float(image_width)
				cy = car.global_position.y / float(image_height)
				if a == "north" and cy < 0.33:
					a_count += 1
				if a == "east" and cx > 0.66:
					a_count += 1
				if a == "south" and cy > 0.66:
					a_count += 1
				if b == "north" and cy < 0.33:
					b_count += 1
				if b == "east" and cx > 0.66:
					b_count += 1
				if b == "south" and cy > 0.66:
					b_count += 1
	# prefer region with smaller count (ascending)
	return a_count - b_count

func _on_car_finished(car: Node) -> void:
	# remove from active list if present
	if car in active_cars:
		active_cars.erase(car)
	# schedule a replacement spawn
	_spawn_with_delay(_rng.randf_range(respawn_delay_min, respawn_delay_max))

func stop_all() -> void:
	for car in active_cars:
		if car and car.is_inside_tree():
			car.stop_and_remove()
	active_cars.clear()


func _random_route_slice(min_len: int = 200, max_len: int = 400) -> Array:
	if route_points.size() == 0:
		return []
	var slice_len = _rng.randi_range(min_len, max_len)
	var start = _rng.randi_range(0, max(0, route_points.size() - slice_len))
	var seg: Array = []
	for i in range(start, min(start + slice_len, route_points.size())):
		seg.append(route_points[i])
	return seg


func _build_segments_for_label(label: String, top_th: float, bottom_th: float, right_th: float) -> Array:
	var segs: Array = []
	var cur: Array = []
	for p in route_points:
		var x = 0.0
		var y = 0.0
		if typeof(p) == TYPE_DICTIONARY:
			x = float(p.get("x", 0.0))
			y = float(p.get("y", 0.0))
		elif typeof(p) == TYPE_ARRAY and p.size() >= 2:
			x = float(p[0])
			y = float(p[1])

		var ok: bool = false
		if label == "north":
			ok = y < top_th
		elif label == "east":
			ok = x > right_th
		elif label == "south":
			ok = y > bottom_th

		if ok:
			cur.append(p)
		else:
			if cur.size() > 8:
				segs.append(cur.duplicate(true))
			cur.clear()

	if cur.size() > 8:
		segs.append(cur.duplicate(true))

	return segs
