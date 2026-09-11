extends SceneTree

const GeometryScript = preload("res://scripts/world/transport_route_geometry.gd")
const NetworkLayerScript = preload("res://scripts/world/transport_network_layer.gd")
const VehicleControllerScript = preload("res://scripts/world/transport_vehicle_controller.gd")
const TransportModesScript = preload("res://data/catalogs/transport_modes.gd")

const ENDPOINT_EPSILON := 0.01

var _failed := false
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var centers := _centers()
	_validate_continuous_turn_and_bidirectional_lanes(centers)
	_validate_corridor_shapes_and_completed_only(centers)
	await _validate_shared_renderer_vehicle_geometry_and_lifecycle(centers)
	if _failed:
		quit(1)
	else:
		print("Transport continuous geometry test passed. Checks=%d Modes=%d" % [_checks, TransportModesScript.route_modes().size()])
		quit(0)


func _validate_continuous_turn_and_bidirectional_lanes(centers: Dictionary) -> void:
	var turn := GeometryScript.build_centerline([0, 1, 4], centers)
	_check(bool(turn.get("valid", false)), "L-turn centerline must bake")
	var baked: PackedVector2Array = turn.get("baked_points", PackedVector2Array())
	_check(baked.size() > 3, "L-turn must contain baked curve samples")
	_check(baked[0].distance_to(centers["0"]) <= ENDPOINT_EPSILON, "L-turn start endpoint drifted from authoritative center")
	_check(baked[-1].distance_to(centers["4"]) <= ENDPOINT_EPSILON, "L-turn end endpoint drifted from authoritative center")
	var maximum_gap := 0.0
	for index in range(baked.size() - 1):
		maximum_gap = maxf(maximum_gap, baked[index].distance_to(baked[index + 1]))
	_check(maximum_gap <= GeometryScript.DEFAULT_BAKE_INTERVAL * 1.6, "baked turn contains a visible continuity gap")
	var corners: Array = turn.get("corner_contracts", [])
	_check(corners.size() == 1, "L-turn must have exactly one rounded corner")
	if corners.size() == 1:
		var corner: Dictionary = corners[0]
		_check(Vector2(corner["incoming_tangent"]).dot(Vector2(corner["entry_tangent"])) > 0.999, "turn entry tangent is discontinuous")
		_check(Vector2(corner["exit_tangent"]).dot(Vector2(corner["outgoing_tangent"])) > 0.999, "turn exit tangent is discontinuous")
		_check(Vector2(corner["entry"]).distance_to(Vector2(corner["exit"])) > 1.0, "turn collapsed to a hard corner")

	var bidirectional := GeometryScript.build_bidirectional_route([0, 1, 4], centers, 6.0)
	_check(bool(bidirectional.get("valid", false)), "bidirectional route geometry must bake")
	_check(bool(bidirectional.get("bidirectional", false)), "route geometry lost its bidirectional contract")
	var loop: PackedVector2Array = bidirectional.get("baked_points", PackedVector2Array())
	_check(loop[0].distance_to(loop[-1]) <= ENDPOINT_EPSILON, "bidirectional route loop does not close continuously")
	_check(int(bidirectional.get("terminal_caps", 0)) == 2, "bidirectional route must have a bounded turnback at both terminals")
	var forward: PackedVector2Array = bidirectional.get("forward_points", PackedVector2Array())
	var reverse: PackedVector2Array = bidirectional.get("reverse_points", PackedVector2Array())
	var forward_mid := forward[int(forward.size() / 2)]
	var reverse_mid := reverse[int(reverse.size() / 2)]
	_check(forward_mid.distance_to(reverse_mid) >= 10.0, "opposing lanes overlap instead of retaining their offset")
	var forward_tangent := (forward[mini(forward.size() - 1, int(forward.size() / 2) + 1)] - forward[maxi(0, int(forward.size() / 2) - 1)]).normalized()
	var reverse_tangent := (reverse[mini(reverse.size() - 1, int(reverse.size() / 2) + 1)] - reverse[maxi(0, int(reverse.size() / 2) - 1)]).normalized()
	_check(forward_tangent.dot(reverse_tangent) < -0.98, "opposing lanes do not carry opposing directions")

	var previous := GeometryScript.sample_geometry(bidirectional, 0.0)
	var sample_count := 400
	var expected_step := float(bidirectional.get("length", 0.0)) / float(sample_count)
	for sample_index in range(1, sample_count + 1):
		var sample := GeometryScript.sample_geometry(
			bidirectional,
			float(bidirectional.get("length", 0.0)) * float(sample_index) / float(sample_count)
		)
		_check(bool(sample.get("valid", false)), "distance sampler left the shared curve")
		if bool(sample.get("valid", false)):
			_check(Vector2(sample["position"]).distance_to(Vector2(previous["position"])) <= expected_step * 1.8, "distance sampler jumped between curve segments")
			previous = sample


func _validate_corridor_shapes_and_completed_only(centers: Dictionary) -> void:
	var shape_states := {
		"0": _state("road", ["e"], {"e": 1}),
		"1": _state("road", ["w", "s"], {"w": 0, "s": 4}),
		"4": _state("road", ["n"], {"n": 1}),
		"2": _state("metro_track", [], {}),
		"5": _state("rail_track", ["e", "s"], {"e": 6, "s": 8}),
		"6": _state("rail_track", ["w", "s"], {"w": 5, "s": 9}),
		"8": _state("rail_track", ["n", "e"], {"n": 5, "e": 9}),
		"9": _state("rail_track", ["n", "w"], {"n": 6, "w": 8}),
		"3": _state("runway", ["e", "s", "w"], {"e": 7, "s": 10, "w": 11}),
		"7": _state("runway", ["w"], {"w": 3}),
		"10": _state("runway", ["n"], {"n": 3}),
		"11": _state("runway", ["e"], {"e": 3}),
		"13": _state("taxiway", ["e"], {"e": 14}),
		"14": _state("taxiway", ["w", "e"], {"w": 13, "e": 15}),
		"15": _state("taxiway", ["w"], {"w": 14}),
		"16": _state("metro_track", ["e"], {"e": 17}),
		"17": _state("metro_track", ["w"], {"w": 16}),
	}
	var geometries := GeometryScript.build_corridor_geometries(shape_states, centers)
	var classes: Array[String] = []
	for geometry: Dictionary in geometries:
		var classification := str(geometry.get("classification", ""))
		if classification not in classes:
			classes.append(classification)
	_check("turn" in classes, "corridor generator omitted turn geometry")
	_check("short_segment" in classes, "corridor generator omitted terminal short-segment geometry")
	_check("terminal" in classes, "corridor generator omitted terminal geometry")
	_check("straight" in classes, "corridor generator omitted straight-run geometry")
	_check("loop" in classes, "corridor generator omitted closed-loop geometry")
	_check("crossing_branch" in classes, "corridor generator omitted crossing/junction branches")

	var stage := Control.new()
	root.add_child(stage)
	var layer = NetworkLayerScript.new()
	stage.add_child(layer)
	var completed_states := {
		"0": _state("road", ["e", "n"], {"e": 1, "n": 12}),
		"1": _state("road", ["w", "s"], {"w": 0, "s": 4}),
		"4": _state("road", ["n"], {"n": 1}),
	}
	var visible_states := completed_states.duplicate(true)
	visible_states["12"] = _state("road", [], {})
	visible_states["12"]["project_status"] = "under_construction"
	var snapshot := {
		"tile_states": visible_states,
		"completed_tile_states": completed_states,
		"operational_lines": [],
		"private_road_paths": [],
		"crossings": {},
		"station_access_edges": [],
	}
	var before := snapshot.duplicate(true)
	layer.set_network_snapshot(snapshot, centers)
	var debug: Dictionary = layer.debug_snapshot()
	_check(snapshot == before, "renderer geometry generation mutated its authority snapshot")
	_check(int(debug.get("completed_tile_state_count", 0)) == 3, "completed-only renderer accepted an under-construction tile")
	for geometry_variant: Variant in debug.get("corridor_geometries", []):
		_check(not Array(Dictionary(geometry_variant).get("path_tile_ids", [])).has(12), "under-construction tile leaked into operational corridor geometry")
	stage.queue_free()


func _validate_shared_renderer_vehicle_geometry_and_lifecycle(centers: Dictionary) -> void:
	var lines: Array[Dictionary] = []
	var modes := TransportModesScript.route_modes()
	for mode_index in modes.size():
		var mode := modes[mode_index]
		lines.append({
			"id": "route_%s" % mode,
			"mode": mode,
			"status": "operational",
			"vehicle_kind": str(TransportModesScript.route_spec(mode).get("vehicle_kind", "")),
			"path_tile_ids": [0, 1, 4],
			"fleet_size": 2,
			"loop_seconds": 8.0 + float(mode_index),
		})
	var snapshot := {
		"tile_states": {},
		"completed_tile_states": {},
		"operational_lines": lines,
		"private_road_paths": [],
		"crossings": {},
		"station_access_edges": [],
	}
	var stage := Control.new()
	root.add_child(stage)
	var layer = NetworkLayerScript.new()
	stage.add_child(layer)
	var controller = VehicleControllerScript.new()
	stage.add_child(controller)
	await process_frame
	layer.set_network_snapshot(snapshot, centers)
	controller.set_runtime_snapshot(snapshot, centers)
	_check(controller.active_vehicle_count() == modes.size() * 2, "all existing transport modes must retain their declared two-vehicle fleets")
	var layer_routes: Dictionary = layer.debug_snapshot().get("route_geometries", {})
	var controller_debug: Dictionary = controller.debug_route_snapshot()
	_check(int(controller_debug.get("geometry_count", 0)) == modes.size(), "vehicle controller did not bound geometry resources to one per route")
	var directions_by_route: Dictionary = {}
	for vehicle_variant: Variant in controller_debug.get("vehicles", []):
		var vehicle: Dictionary = vehicle_variant
		var route_id := str(vehicle.get("route_id", ""))
		var lane_directions: Array = directions_by_route.get(route_id, [])
		var lane_direction := int(vehicle.get("lane_direction", 0))
		if lane_direction not in lane_directions:
			lane_directions.append(lane_direction)
		directions_by_route[route_id] = lane_directions
		_check(bool(vehicle.get("on_authoritative_path", false)), "%s vehicle left the shared operational curve" % route_id)
		_check(str(vehicle.get("geometry_fingerprint", "")) == str(Dictionary(layer_routes.get(route_id, {})).get("fingerprint", "")), "%s renderer and vehicle geometry fingerprints drifted" % route_id)
	for mode: String in modes:
		var route_id := "route_%s" % mode
		_check(directions_by_route.has(route_id), "%s did not create operational vehicle samples" % mode)
		_check(1 in Array(directions_by_route.get(route_id, [])) and -1 in Array(directions_by_route.get(route_id, [])), "%s two-vehicle fleet did not occupy opposing directions" % mode)

	var expected_children := modes.size() * 2
	for _refresh in 8:
		controller.set_runtime_snapshot(snapshot, centers)
		_check(controller.active_vehicle_count() == expected_children, "route refresh accumulated actor authority entries")
		_check(controller.get_child_count() == expected_children, "route refresh accumulated vehicle nodes")
	var updated := snapshot.duplicate(true)
	updated["operational_lines"][0]["path_tile_ids"] = [0, 1, 4, 8]
	controller.set_runtime_snapshot(updated, centers)
	_check(controller.active_vehicle_count() == expected_children and controller.get_child_count() == expected_children, "route update duplicated vehicle nodes")
	var empty := snapshot.duplicate(true)
	empty["operational_lines"] = []
	controller.set_runtime_snapshot(empty, centers)
	_check(controller.active_vehicle_count() == 0, "route deletion retained actor authority entries")
	_check(controller.get_child_count() == 0, "route deletion retained vehicle nodes")
	_check(int(controller.debug_route_snapshot().get("geometry_count", -1)) == 0, "route deletion retained curve resources")
	controller.set_runtime_snapshot(snapshot, centers)
	_check(controller.active_vehicle_count() == expected_children and controller.get_child_count() == expected_children, "route reload did not rebuild one bounded actor set")
	stage.queue_free()
	await process_frame
	await process_frame


func _state(kind: String, directions: Array, neighbours: Dictionary) -> Dictionary:
	var connections: Dictionary = {}
	connections[kind] = directions.duplicate()
	return {
		"segments": [kind],
		"facilities": [],
		"connections": connections,
		"neighbours": neighbours.duplicate(),
		"crossing": "",
		"project_status": "",
	}


func _centers() -> Dictionary:
	return {
		"0": Vector2(80, 80), "1": Vector2(150, 80), "2": Vector2(220, 80), "3": Vector2(290, 80),
		"4": Vector2(150, 150), "5": Vector2(360, 80), "6": Vector2(430, 80), "7": Vector2(360, 150),
		"8": Vector2(360, 150), "9": Vector2(430, 150), "10": Vector2(290, 150), "11": Vector2(220, 80),
		"12": Vector2(220, 150), "13": Vector2(80, 240), "14": Vector2(150, 240), "15": Vector2(220, 240),
		"16": Vector2(290, 240), "17": Vector2(360, 240),
	}


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Transport continuous geometry test failed: %s" % message)
