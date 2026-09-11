class_name TransportVehicleController
extends Control

const TransportRouteGeometryScript = preload("res://scripts/world/transport_route_geometry.gd")

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
var _actor_route_times: Dictionary = {}
var _actor_positions_initialized: Dictionary = {}
var _actor_samples: Dictionary = {}
var _route_geometries: Dictionary = {}
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
	_route_geometries = TransportRouteGeometryScript.build_operational_route_geometries(
		_runtime_snapshot,
		_tile_centers
	)
	_rebuild_actor_specs()
	_sync_actors()
	_update_actors(0.0)


func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled


func debug_set_simulation_time(seconds: float) -> void:
	var next_time := maxf(0.0, seconds)
	var moved_backwards := next_time < _simulation_time
	var elapsed := maxf(0.0, next_time - _simulation_time)
	_simulation_time = next_time
	if moved_backwards:
		_reset_actor_route_times(next_time)
	_update_actors(elapsed)


func debug_advance_simulation(delta: float) -> void:
	var elapsed := maxf(0.0, delta)
	_simulation_time = maxf(0.0, _simulation_time + elapsed)
	_update_actors(elapsed)


func debug_route_snapshot() -> Dictionary:
	var vehicles: Array[Dictionary] = []
	var keys: Array[String] = []
	for key_variant: Variant in _actors.keys():
		keys.append(str(key_variant))
	keys.sort()
	for key: String in keys:
		var actor := _actors[key] as VehicleActor
		var spec: Dictionary = _actor_specs.get(key, {})
		var sample: Dictionary = _actor_samples.get(key, {})
		vehicles.append({
			"vehicle_key": key,
			"vehicle_kind": actor.vehicle_kind,
			"route_id": actor.route_id,
			"route_mode": actor.route_mode,
			"position": actor.position + actor.size * 0.5,
			"path_tile_ids": Array(spec.get("path_tile_ids", [])).duplicate(),
			"operational_source": true,
			"on_authoritative_path": bool(spec.get("sample_valid", false)),
			"route_time": float(_actor_route_times.get(key, _simulation_time)),
			"curve_distance": float(sample.get("distance", 0.0)),
			"curve_length": float(sample.get("curve_length", 0.0)),
			"lane_direction": int(sample.get("lane_direction", 0)),
			"lane_offset": float(sample.get("lane_offset", 0.0)),
			"geometry_fingerprint": str(sample.get("geometry_fingerprint", "")),
		})
	return {
		"simulation_time": _simulation_time,
		"vehicle_count": vehicles.size(),
		"vehicles": vehicles,
		"crossing_states": _crossing_states.duplicate(true),
		"autonomous_tile_vehicle_count": 0,
		"network_vehicle_layer_owner": "transport_network_controller",
		"geometry_count": _route_geometries.size(),
	}


func active_vehicle_count() -> int:
	return _actors.size()


func _reset_actor_route_times(seconds: float) -> void:
	for key_variant: Variant in _actors.keys():
		_actor_route_times[str(key_variant)] = seconds


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var elapsed := minf(maxf(delta, 0.0), MAX_FRAME_DELTA)
	_simulation_time = fposmod(_simulation_time + elapsed, 86_400.0)
	_update_actors(elapsed)


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
		if route_id.is_empty() or path.size() < 2 or not _route_geometries.has(route_id):
			continue
		var fleet_size := clampi(int(line.get("fleet_size", 1)), 1, 40)
		for fleet_index in fleet_size:
			var key := "%s:%02d" % [route_id, fleet_index]
			var spec := line.duplicate(true)
			spec["route_id"] = route_id
			spec["actor_index"] = fleet_index
			spec["actor_count"] = fleet_size
			spec["geometry_key"] = route_id
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
			var geometry_key := "private_road_%02d" % path_index
			if not _route_geometries.has(geometry_key):
				var private_geometry := TransportRouteGeometryScript.build_bidirectional_route(
					tiles,
					_tile_centers,
					TransportRouteGeometryScript.DEFAULT_LANE_OFFSET
				)
				if bool(private_geometry.get("valid", false)):
					private_geometry["route_id"] = geometry_key
					private_geometry["mode"] = "road"
					_route_geometries[geometry_key] = private_geometry
			if not _route_geometries.has(geometry_key):
				continue
			_actor_specs[key] = {
				"route_id": geometry_key,
				"mode": "road",
				"vehicle_kind": "car" if vehicle_index == 0 else "motorcycle",
				"path_tile_ids": tiles.duplicate(),
				"loop_seconds": maxf(6.0, float(tiles.size()) * 1.6),
				"actor_index": vehicle_index,
				"actor_count": 2,
				"geometry_key": geometry_key,
				"status": "operational",
			}


func _sync_actors() -> void:
	for key_variant: Variant in _actors.keys().duplicate():
		var key := str(key_variant)
		if _actor_specs.has(key):
			continue
		var old_actor := _actors[key] as VehicleActor
		_actors.erase(key)
		_actor_route_times.erase(key)
		_actor_positions_initialized.erase(key)
		_actor_samples.erase(key)
		if is_instance_valid(old_actor):
			remove_child(old_actor)
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
		_actor_route_times[key] = _simulation_time
		_actor_positions_initialized[key] = false
		_actor_samples[key] = {}
	for key_variant: Variant in _actors.keys():
		var key := str(key_variant)
		if not _actor_route_times.has(key):
			_actor_route_times[key] = _simulation_time
		if not _actor_positions_initialized.has(key):
			_actor_positions_initialized[key] = false
		if not _actor_samples.has(key):
			_actor_samples[key] = {}


func _update_actors(elapsed: float) -> void:
	var safe_elapsed := maxf(0.0, elapsed)
	var proposed: Dictionary = {}
	for key_variant: Variant in _actors.keys():
		var key := str(key_variant)
		var actor := _actors[key] as VehicleActor
		var spec: Dictionary = _actor_specs.get(key, {})
		var route_time := float(_actor_route_times.get(key, _simulation_time))
		var candidate_route_time := route_time + safe_elapsed
		var sample := _sample_spec(spec, candidate_route_time)
		spec["sample_valid"] = bool(sample.get("valid", false))
		_actor_specs[key] = spec
		if not bool(sample.get("valid", false)):
			actor.hide()
			_actor_positions_initialized[key] = false
			_actor_samples[key] = {}
			continue
		sample["route_time"] = candidate_route_time
		proposed[key] = sample

	var next_crossing_states := _crossing_proximity_states(proposed)
	if next_crossing_states != _crossing_states:
		_crossing_states = next_crossing_states
		crossing_states_changed.emit(_crossing_states.duplicate(true))

	for key_variant: Variant in proposed.keys():
		var key := str(key_variant)
		var actor := _actors[key] as VehicleActor
		var spec: Dictionary = _actor_specs.get(key, {})
		var sample: Dictionary = proposed[key]
		var next_position: Vector2 = sample["position"]
		var next_angle := float(sample.get("angle", 0.0))
		var initialized := bool(_actor_positions_initialized.get(key, false))
		var current_position := actor.position + actor.size * 0.5 if initialized else next_position
		var stopped_for_crossing := (
			actor.vehicle_kind in ["car", "motorcycle", "bus"]
			and _must_stop_for_crossing(current_position, next_position)
		)
		if stopped_for_crossing:
			if initialized:
				next_position = current_position
			else:
				var stop_sample := _sample_before_closed_crossing(
					spec, float(sample.get("route_time", _simulation_time))
				)
				if stop_sample.is_empty():
					actor.hide()
					continue
				next_position = Vector2(stop_sample.get("position", next_position))
				next_angle = float(stop_sample.get("angle", next_angle))
				_actor_route_times[key] = float(stop_sample.get("route_time", _simulation_time))
		else:
			_actor_route_times[key] = float(sample.get("route_time", _simulation_time))
		actor.position = next_position - actor.size * 0.5
		actor.rotation = next_angle
		actor.z_index = int(round(next_position.y)) + 2
		actor.visible = _interaction_enabled or true
		_actor_positions_initialized[key] = true
		sample["position"] = next_position
		sample["angle"] = next_angle
		_actor_samples[key] = sample


func _sample_spec(spec: Dictionary, sample_time: float) -> Dictionary:
	var geometry_key := str(spec.get("geometry_key", spec.get("route_id", "")))
	if not _route_geometries.has(geometry_key):
		return {"valid": false}
	var geometry: Dictionary = _route_geometries[geometry_key]
	var total_length := float(geometry.get("length", 0.0))
	if total_length <= 0.01:
		return {"valid": false}
	var loop_seconds := maxf(1.0, float(spec.get("loop_seconds", maxf(5.0, total_length / 42.0))))
	var actor_index := int(spec.get("actor_index", 0))
	var actor_count := maxi(1, int(spec.get("actor_count", 1)))
	var phase := fposmod(sample_time / loop_seconds + float(actor_index) / float(actor_count), 1.0)
	var sample := TransportRouteGeometryScript.sample_geometry(geometry, phase * total_length)
	if not bool(sample.get("valid", false)):
		return sample
	sample["curve_length"] = total_length
	sample["lane_offset"] = float(geometry.get("lane_offset", 0.0))
	sample["geometry_fingerprint"] = str(geometry.get("fingerprint", ""))
	return sample


func _sample_before_closed_crossing(spec: Dictionary, candidate_route_time: float) -> Dictionary:
	var loop_seconds := maxf(1.0, float(spec.get("loop_seconds", 12.0)))
	# Search one full loop backwards.  This is used only when a vehicle actor is
	# first materialized while its next authoritative sample is already inside a
	# closed crossing, so placing it at the nearest preceding stop point is both
	# deterministic and bounded.
	for step_index in range(1, 257):
		var sample_time := candidate_route_time - loop_seconds * float(step_index) / 256.0
		var sample := _sample_spec(spec, sample_time)
		if not bool(sample.get("valid", false)):
			continue
		var position := Vector2(sample.get("position", Vector2.INF))
		if position != Vector2.INF and not _must_stop_for_crossing(position, position):
			sample["route_time"] = sample_time
			return sample
	return {}


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


func _must_stop_for_crossing(from_position: Vector2, to_position: Vector2) -> bool:
	for tile_key_variant: Variant in _crossing_states.keys():
		var state: Dictionary = _crossing_states[tile_key_variant]
		if not bool(state.get("closed", false)):
			continue
		var center := _center_for(int(str(tile_key_variant)))
		if center == Vector2.INF:
			continue
		if from_position.distance_to(center) <= 31.0 or to_position.distance_to(center) <= 31.0:
			return true
		var closest := Geometry2D.get_closest_point_to_segment(center, from_position, to_position)
		if closest.distance_to(center) <= 31.0:
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
