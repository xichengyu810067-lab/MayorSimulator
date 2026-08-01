class_name TransportVehicleController
extends Control

## Cross-tile vehicle runtime.  This is the sole owner of moving transport
## vehicles; CityTileButton intentionally has no authority to spawn them.

signal crossing_states_changed(states: Dictionary)

const MAX_FRAME_DELTA := 0.10
const PRIVATE_VEHICLE_LIMIT := 2

class VehicleActor:
	extends Control

	var vehicle_key := ""
	var vehicle_kind := "car"
	var route_id := ""
	var route_mode := ""
	var actor_color := Color.WHITE

	func _init(key: String, kind: String, line_id: String, mode: String, color: Color) -> void:
		vehicle_key = key
		vehicle_kind = kind
		route_id = line_id
		route_mode = mode
		actor_color = color
		custom_minimum_size = Vector2(42, 42)
		size = Vector2(42, 42)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		pivot_offset = size * 0.5

	func _draw() -> void:
		var center := size * 0.5
		match vehicle_kind:
			"bus":
				draw_rect(Rect2(center + Vector2(-15, -7), Vector2(30, 14)), actor_color, true)
				draw_rect(Rect2(center + Vector2(-10, -5), Vector2(15, 5)), Color(0.75, 0.92, 1.0), true)
				draw_circle(center + Vector2(-9, 8), 3.2, Color(0.07, 0.08, 0.09))
				draw_circle(center + Vector2(9, 8), 3.2, Color(0.07, 0.08, 0.09))
			"metro_train", "train":
				var body_color := Color(0.08, 0.56, 0.82) if vehicle_kind == "metro_train" else actor_color
				draw_colored_polygon(PackedVector2Array([
					center + Vector2(-16, -7), center + Vector2(12, -7),
					center + Vector2(17, 0), center + Vector2(12, 7), center + Vector2(-16, 7),
				]), body_color)
				draw_line(center + Vector2(-9, -4), center + Vector2(9, -4), Color(0.78, 0.93, 1.0), 3.0, true)
				draw_circle(center + Vector2(-10, 8), 2.8, Color(0.06, 0.07, 0.08))
				draw_circle(center + Vector2(10, 8), 2.8, Color(0.06, 0.07, 0.08))
			"plane":
				draw_colored_polygon(PackedVector2Array([
					center + Vector2(18, 0), center + Vector2(-5, -4),
					center + Vector2(-15, -15), center + Vector2(-10, -2),
					center + Vector2(-18, 0), center + Vector2(-10, 2),
					center + Vector2(-15, 15), center + Vector2(-5, 4),
				]), Color(0.92, 0.96, 1.0))
				draw_line(center + Vector2(-3, 0), center + Vector2(14, 0), actor_color, 2.0, true)
			"motorcycle":
				draw_circle(center + Vector2(-7, 5), 4.0, Color(0.05, 0.06, 0.07))
				draw_circle(center + Vector2(7, 5), 4.0, Color(0.05, 0.06, 0.07))
				draw_line(center + Vector2(-6, 1), center + Vector2(6, 1), actor_color, 3.0, true)
				draw_line(center + Vector2(4, 1), center + Vector2(8, -5), actor_color, 2.0, true)
			_:
				draw_rect(Rect2(center + Vector2(-11, -6), Vector2(22, 12)), actor_color, true)
				draw_rect(Rect2(center + Vector2(-5, -5), Vector2(10, 5)), Color(0.75, 0.92, 1.0), true)
				draw_circle(center + Vector2(-7, 7), 3.0, Color(0.05, 0.06, 0.07))
				draw_circle(center + Vector2(7, 7), 3.0, Color(0.05, 0.06, 0.07))


var _runtime_snapshot: Dictionary = {}
var _tile_centers: Dictionary = {}
var _actors: Dictionary = {}
var _actor_specs: Dictionary = {}
var _simulation_time := 0.0
var _crossing_states: Dictionary = {}
var _interaction_enabled := true


func _ready() -> void:
	name = "TransportVehicleController"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(true)


func set_runtime_snapshot(snapshot: Dictionary, tile_centers: Dictionary) -> void:
	_runtime_snapshot = snapshot.duplicate(true)
	_tile_centers = tile_centers.duplicate(true)
	_rebuild_actor_specs()
	_sync_actors()
	_update_actors()


func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled


func debug_set_simulation_time(seconds: float) -> void:
	_simulation_time = maxf(0.0, seconds)
	_update_actors()


func debug_advance_simulation(delta: float) -> void:
	_simulation_time = maxf(0.0, _simulation_time + maxf(0.0, delta))
	_update_actors()


func debug_route_snapshot() -> Dictionary:
	var vehicles: Array[Dictionary] = []
	var keys: Array[String] = []
	for key_variant: Variant in _actors.keys():
		keys.append(str(key_variant))
	keys.sort()
	for key: String in keys:
		var actor := _actors[key] as VehicleActor
		var spec: Dictionary = _actor_specs.get(key, {})
		vehicles.append({
			"vehicle_key": key,
			"vehicle_kind": actor.vehicle_kind,
			"route_id": actor.route_id,
			"route_mode": actor.route_mode,
			"position": actor.position + actor.size * 0.5,
			"path_tile_ids": Array(spec.get("path_tile_ids", [])).duplicate(),
			"operational_source": true,
			"on_authoritative_path": bool(spec.get("sample_valid", false)),
		})
	return {
		"simulation_time": _simulation_time,
		"vehicle_count": vehicles.size(),
		"vehicles": vehicles,
		"crossing_states": _crossing_states.duplicate(true),
		"autonomous_tile_vehicle_count": 0,
		"network_vehicle_layer_owner": "transport_network_controller",
	}


func active_vehicle_count() -> int:
	return _actors.size()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_simulation_time = fposmod(_simulation_time + minf(maxf(delta, 0.0), MAX_FRAME_DELTA), 86_400.0)
	_update_actors()


func _rebuild_actor_specs() -> void:
	_actor_specs.clear()
	for line_variant: Variant in _runtime_snapshot.get("operational_lines", []):
		if not line_variant is Dictionary:
			continue
		var line: Dictionary = line_variant
		if str(line.get("status", "")) != "operational":
			continue
		var route_id := str(line.get("id", line.get("route_id", "")))
		var path: Array = line.get("path_tile_ids", [])
		if route_id.is_empty() or path.size() < 2:
			continue
		var fleet_size := clampi(int(line.get("fleet_size", 1)), 1, 12)
		for fleet_index in fleet_size:
			var key := "%s:%02d" % [route_id, fleet_index]
			var spec := line.duplicate(true)
			spec["route_id"] = route_id
			spec["actor_index"] = fleet_index
			spec["actor_count"] = fleet_size
			_actor_specs[key] = spec

	var private_paths: Array = _runtime_snapshot.get("private_road_paths", [])
	for path_index in mini(private_paths.size(), PRIVATE_VEHICLE_LIMIT):
		var private_variant: Variant = private_paths[path_index]
		if not private_variant is Dictionary:
			continue
		var private_path: Dictionary = private_variant
		var tiles: Array = private_path.get("path_tile_ids", [])
		if tiles.size() < 2 or not bool(private_path.get("operational", true)):
			continue
		for vehicle_index in 2:
			var key := "private:%02d:%02d" % [path_index, vehicle_index]
			_actor_specs[key] = {
				"route_id": "private_road_%02d" % path_index,
				"mode": "road",
				"vehicle_kind": "car" if vehicle_index == 0 else "motorcycle",
				"path_tile_ids": tiles.duplicate(),
				"loop_seconds": maxf(6.0, float(tiles.size()) * 1.6),
				"actor_index": vehicle_index,
				"actor_count": 2,
				"status": "operational",
			}


func _sync_actors() -> void:
	for key_variant: Variant in _actors.keys().duplicate():
		var key := str(key_variant)
		if _actor_specs.has(key):
			continue
		var old_actor := _actors[key] as VehicleActor
		_actors.erase(key)
		if is_instance_valid(old_actor):
			old_actor.queue_free()
	for key_variant: Variant in _actor_specs.keys():
		var key := str(key_variant)
		if _actors.has(key):
			continue
		var spec: Dictionary = _actor_specs[key]
		var kind := str(spec.get("vehicle_kind", _vehicle_kind_for_mode(str(spec.get("mode", "")))))
		var mode := str(spec.get("mode", "road"))
		var route_id := str(spec.get("route_id", ""))
		var actor := VehicleActor.new(key, kind, route_id, mode, _vehicle_color(route_id, kind))
		add_child(actor)
		_actors[key] = actor


func _update_actors() -> void:
	var proposed: Dictionary = {}
	for key_variant: Variant in _actors.keys():
		var key := str(key_variant)
		var actor := _actors[key] as VehicleActor
		var spec: Dictionary = _actor_specs.get(key, {})
		var sample := _sample_spec(spec)
		spec["sample_valid"] = bool(sample.get("valid", false))
		_actor_specs[key] = spec
		if not bool(sample.get("valid", false)):
			actor.hide()
			continue
		proposed[key] = sample

	var next_crossing_states := _crossing_proximity_states(proposed)
	if next_crossing_states != _crossing_states:
		_crossing_states = next_crossing_states
		crossing_states_changed.emit(_crossing_states.duplicate(true))

	for key_variant: Variant in proposed.keys():
		var key := str(key_variant)
		var actor := _actors[key] as VehicleActor
		var sample: Dictionary = proposed[key]
		var next_position: Vector2 = sample["position"]
		if actor.vehicle_kind in ["car", "motorcycle", "bus"] and _must_stop_for_crossing(next_position):
			next_position = actor.position + actor.size * 0.5 if actor.visible else next_position
		actor.position = next_position - actor.size * 0.5
		actor.rotation = float(sample.get("angle", 0.0))
		actor.z_index = int(round(next_position.y)) + 2
		actor.visible = _interaction_enabled or true


func _sample_spec(spec: Dictionary) -> Dictionary:
	var points := PackedVector2Array()
	for tile_variant: Variant in spec.get("path_tile_ids", []):
		var center := _center_for(int(tile_variant))
		if center != Vector2.INF:
			points.append(center)
	if points.size() < 2:
		return {"valid": false}
	var travel := PackedVector2Array(points)
	for index in range(points.size() - 2, 0, -1):
		travel.append(points[index])
	travel.append(points[0])
	var total_length := 0.0
	var segment_lengths := PackedFloat32Array()
	for index in travel.size() - 1:
		var segment_length := travel[index].distance_to(travel[index + 1])
		segment_lengths.append(segment_length)
		total_length += segment_length
	if total_length <= 0.01:
		return {"valid": false}
	var loop_seconds := maxf(1.0, float(spec.get("loop_seconds", maxf(5.0, total_length / 42.0))))
	var actor_index := int(spec.get("actor_index", 0))
	var actor_count := maxi(1, int(spec.get("actor_count", 1)))
	var phase := fposmod(_simulation_time / loop_seconds + float(actor_index) / float(actor_count), 1.0)
	var target_distance := phase * total_length
	var consumed := 0.0
	for index in segment_lengths.size():
		var length := float(segment_lengths[index])
		if target_distance > consumed + length and index < segment_lengths.size() - 1:
			consumed += length
			continue
		var local := clampf((target_distance - consumed) / maxf(length, 0.001), 0.0, 1.0)
		var from := travel[index]
		var to := travel[index + 1]
		return {
			"valid": true,
			"position": from.lerp(to, local),
			"angle": (to - from).angle(),
			"segment_index": index,
		}
	return {"valid": true, "position": travel[-1], "angle": 0.0, "segment_index": travel.size() - 2}


func _crossing_proximity_states(samples: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var crossings: Dictionary = _runtime_snapshot.get("crossings", {})
	for crossing_key_variant: Variant in crossings.keys():
		var crossing: Dictionary = crossings[crossing_key_variant]
		var tile_id := int(crossing.get("tile_id", str(crossing_key_variant)))
		var center := _center_for(tile_id)
		var closed := false
		if center != Vector2.INF:
			for key_variant: Variant in samples.keys():
				var key := str(key_variant)
				var actor := _actors.get(key) as VehicleActor
				if actor == null or actor.vehicle_kind not in ["train", "metro_train"]:
					continue
				var sample: Dictionary = samples[key]
				if (sample["position"] as Vector2).distance_to(center) <= 70.0:
					closed = true
					break
		result[str(tile_id)] = {
			"closed": closed,
			"flash": closed and int(floor(_simulation_time * 5.0)) % 2 == 0,
		}
	return result


func _must_stop_for_crossing(position: Vector2) -> bool:
	for tile_key_variant: Variant in _crossing_states.keys():
		var state: Dictionary = _crossing_states[tile_key_variant]
		if not bool(state.get("closed", false)):
			continue
		var center := _center_for(int(str(tile_key_variant)))
		if center != Vector2.INF and position.distance_to(center) <= 31.0:
			return true
	return false


func _center_for(tile_id: int) -> Vector2:
	var value: Variant = _tile_centers.get(str(tile_id), _tile_centers.get(tile_id, null))
	return value if value is Vector2 else Vector2.INF


func _vehicle_kind_for_mode(mode: String) -> String:
	return {
		"bus": "bus",
		"metro": "metro_train",
		"train": "train",
		"air": "plane",
	}.get(mode, "car")


func _vehicle_color(route_id: String, kind: String) -> Color:
	var palette := [
		Color(0.10, 0.64, 0.54), Color(0.94, 0.42, 0.18),
		Color(0.22, 0.48, 0.86), Color(0.72, 0.31, 0.76),
	]
	var stable := 0
	for index in route_id.length():
		stable = (stable * 31 + route_id.unicode_at(index)) % 997
	if kind == "plane":
		return Color(0.16, 0.48, 0.78)
	return palette[stable % palette.size()]
