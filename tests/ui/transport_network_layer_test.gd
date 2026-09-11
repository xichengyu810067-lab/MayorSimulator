extends SceneTree

const NetworkLayerScript = preload("res://scripts/world/transport_network_layer.gd")
const VehicleControllerScript = preload("res://scripts/world/transport_vehicle_controller.gd")
const SquareGridLayoutScript = preload("res://scripts/world/square_grid_layout.gd")

var _failed := false
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Control.new()
	stage.name = "MapStageFixture"
	stage.size = Vector2(600, 300)
	root.add_child(stage)
	var ground = NetworkLayerScript.new()
	stage.add_child(ground)
	var vehicles = VehicleControllerScript.new()
	stage.add_child(vehicles)
	await process_frame
	var marker_center := Vector2(180, 120)
	var marker_points := NetworkLayerScript.construction_marker_points(marker_center)
	_check(marker_points.size() == 5 and marker_points[0] == marker_points[4], "construction marker is not a closed four-corner shape")
	_check(is_equal_approx(marker_points[0].y, marker_points[1].y) and is_equal_approx(marker_points[1].x, marker_points[2].x), "construction marker still uses diamond edges")
	var marker_width := marker_points[0].distance_to(marker_points[1])
	var marker_height := marker_points[1].distance_to(marker_points[2])
	_check(is_equal_approx(marker_width, marker_height), "construction marker is not square")
	_check(is_equal_approx(marker_width, SquareGridLayoutScript.CELL_SIZE.x - 12.0), "construction marker is not constrained by canonical cell size")

	var centers := {
		"0": Vector2(80, 120),
		"1": Vector2(180, 120),
		"2": Vector2(280, 120),
		"3": Vector2(380, 120),
	}
	var isolated_snapshot := {
		"tile_states": {
			"0": {
				"segments": ["metro_track"],
				"facilities": [],
				"connections": {"metro_track": []},
				"neighbours": {},
				"crossing": "",
			}
		},
		"operational_lines": [],
		"private_road_paths": [],
		"crossings": {},
		"station_access_edges": [{
			"station_id": "bus_stop_fixture",
			"station_tile_id": 1,
			"network_tile_id": 0,
			"kind": "road",
		}],
	}
	ground.set_network_snapshot(isolated_snapshot, centers)
	vehicles.set_runtime_snapshot(isolated_snapshot, centers)
	_check(vehicles.active_vehicle_count() == 0, "an isolated track tile must not autonomously spawn a train")
	var ground_debug: Dictionary = ground.debug_snapshot()
	_check(not bool(ground_debug.get("autonomous_vehicle_generation", true)), "ground layer must never own vehicle generation")
	_check(bool(ground_debug.get("shares_map_stage_transform", false)), "network layer must inherit the map-stage transform")
	_check(int(ground_debug.get("station_access_edge_count", 0)) == 1, "network layer dropped the derived station access edge")
	var access_segments: Array = ground_debug.get("station_access_segments", [])
	_check(access_segments.size() == 1, "network layer did not project the station access edge")
	if access_segments.size() == 1:
		var access_segment: Dictionary = access_segments[0]
		_check(Vector2(access_segment.get("from", Vector2.INF)).is_equal_approx(centers["0"]), "station connector did not start at the authoritative road center")
		_check(Vector2(access_segment.get("to", Vector2.INF)).is_equal_approx(centers["1"]), "station connector did not end at the authoritative station center")

	var turn_center := Vector2(180, 120)
	var turn_contract: Dictionary = NetworkLayerScript.connected_junction_contract(turn_center, "road", ["w", "s"])
	_check(bool(turn_contract.get("filled_center", false)), "a square-grid L-turn does not render a filled center junction")
	_check(bool(turn_contract.get("has_perpendicular_turn", false)), "the renderer does not classify perpendicular road strokes as one continuous turn")
	_check(Vector2(turn_contract.get("center", Vector2.INF)).is_equal_approx(turn_center), "the L-turn junction moved away from the authoritative tile center")
	_check(Array(turn_contract.get("directions", [])) == ["s", "w"], "the render-only junction changed or invented connection directions")
	_check(NetworkLayerScript.connected_junction_contract(turn_center, "road", ["w"]).is_empty(), "a terminal cap was misreported as a multi-edge junction")
	var turn_snapshot := {
		"tile_states": {
			"0": {"segments": ["road"], "facilities": [], "connections": {"road": ["e"]}, "neighbours": {"e": 1}, "crossing": ""},
			"1": {"segments": ["road"], "facilities": [], "connections": {"road": ["w", "s"]}, "neighbours": {"w": 0, "s": 2}, "crossing": ""},
			"2": {"segments": ["road"], "facilities": [], "connections": {"road": ["n"]}, "neighbours": {"n": 1}, "crossing": ""},
		},
		"operational_lines": [],
		"private_road_paths": [],
		"crossings": {},
		"station_access_edges": [],
	}
	var turn_topology_before: Dictionary = turn_snapshot.duplicate(true)
	ground.set_network_snapshot(turn_snapshot, {
		"0": Vector2(80, 120),
		"1": turn_center,
		"2": Vector2(180, 220),
	})
	var turn_debug: Dictionary = ground.debug_snapshot()
	_check(turn_snapshot == turn_topology_before, "L-turn rendering mutated its caller-owned topology snapshot")
	_check(int(turn_debug.get("tile_state_count", 0)) == 3, "L-turn rendering changed the number of authoritative topology tiles")
	var connected_junctions: Array = turn_debug.get("connected_junctions", [])
	_check(connected_junctions.size() == 1, "L-turn fixture did not project exactly one render-only junction")
	if connected_junctions.size() == 1:
		var projected_turn: Dictionary = connected_junctions[0]
		_check(int(projected_turn.get("tile_id", -1)) == 1 and bool(projected_turn.get("has_perpendicular_turn", false)), "render-only junction was not attached to the authoritative L-turn tile")

	var operational_snapshot := isolated_snapshot.duplicate(true)
	operational_snapshot["tile_states"] = {
		"0": {"segments": ["rail_track"], "facilities": [], "connections": {"rail_track": ["e"]}, "neighbours": {"e": 1}, "crossing": ""},
		"1": {"segments": ["road", "rail_track"], "facilities": ["rail_signal"], "connections": {"rail_track": ["w", "e"], "road": ["n", "s"]}, "neighbours": {"w": 0, "e": 2}, "crossing": "road_rail_level_crossing"},
		"2": {"segments": ["rail_track"], "facilities": [], "connections": {"rail_track": ["w"]}, "neighbours": {"w": 1}, "crossing": ""},
	}
	operational_snapshot["crossings"] = {"1": {"tile_id": 1, "kind": "road_rail_level_crossing"}}
	operational_snapshot["operational_lines"] = [{
		"id": "line_train_000001",
		"mode": "train",
		"status": "operational",
		"vehicle_kind": "train",
		"path_tile_ids": [0, 1, 2],
		"station_tile_ids": [0, 2],
		"fleet_size": 1,
		"headway_minutes": 8,
		"fare": 45,
		"loop_seconds": 10.0,
	}]
	ground.set_network_snapshot(operational_snapshot, centers)
	vehicles.set_runtime_snapshot(operational_snapshot, centers)
	_check(vehicles.active_vehicle_count() == 1, "an operational train line must own exactly its configured fleet")
	vehicles.debug_set_simulation_time(0.0)
	var before: Dictionary = vehicles.debug_route_snapshot()
	vehicles.debug_set_simulation_time(1.25)
	var after: Dictionary = vehicles.debug_route_snapshot()
	var before_pos: Vector2 = before.get("vehicles", [])[0].get("position", Vector2.INF)
	var after_pos: Vector2 = after.get("vehicles", [])[0].get("position", Vector2.INF)
	_check(before_pos != after_pos, "the same train must advance along its authoritative cross-tile path")
	_check(absf(after_pos.y - 120.0) <= 6.0 and after_pos.x >= 74.0 and after_pos.x <= 286.0, "train position left the authoritative offset rail curve")
	_check(bool(after.get("vehicles", [])[0].get("on_authoritative_path", false)), "vehicle debug contract must identify the authoritative route source")
	vehicles.debug_set_simulation_time(2.5)
	var crossing_debug: Dictionary = vehicles.debug_route_snapshot().get("crossing_states", {})
	_check(bool(Dictionary(crossing_debug.get("1", {})).get("closed", false)), "level-crossing barriers must close while a train is approaching")
	_validate_crossing_vehicle_interlock(vehicles, operational_snapshot, centers)

	operational_snapshot["operational_lines"][0]["fleet_size"] = 40
	vehicles.set_runtime_snapshot(operational_snapshot, centers)
	_check(vehicles.active_vehicle_count() == 40, "the renderer must represent the complete player-configured fleet up to the UI maximum")

	operational_snapshot["operational_lines"][0]["status"] = "suspended"
	vehicles.set_runtime_snapshot(operational_snapshot, centers)
	_check(vehicles.active_vehicle_count() == 0, "a suspended line must immediately withdraw its vehicle actors")

	var private_snapshot := isolated_snapshot.duplicate(true)
	private_snapshot["private_road_paths"] = [{"path_tile_ids": [0, 1, 2], "operational": true}]
	vehicles.set_runtime_snapshot(private_snapshot, centers)
	_check(vehicles.active_vehicle_count() == 2, "a validated road access path may create deterministic car and motorcycle traffic")
	var private_debug: Dictionary = vehicles.debug_route_snapshot()
	_check(int(private_debug.get("autonomous_tile_vehicle_count", -1)) == 0, "private traffic must still come from the network controller, never a tile")

	stage.queue_free()
	await process_frame
	await process_frame
	if _failed:
		quit(1)
	else:
		print("Transport network layer test passed. Checks=%d" % _checks)
		quit(0)


func _validate_crossing_vehicle_interlock(vehicles, base_snapshot: Dictionary, centers: Dictionary) -> void:
	var snapshot := base_snapshot.duplicate(true)
	snapshot["private_road_paths"] = [{"path_tile_ids": [0, 1, 2], "operational": true}]
	var lines: Array = Array(snapshot.get("operational_lines", [])).duplicate(true)
	lines.append({
		"id": "line_bus_crossing",
		"mode": "bus",
		"status": "operational",
		"vehicle_kind": "bus",
		"path_tile_ids": [0, 1, 2],
		"station_tile_ids": [0, 2],
		"fleet_size": 1,
		"headway_minutes": 8,
		"fare": 25,
		"loop_seconds": 6.0,
	})
	snapshot["operational_lines"] = lines
	vehicles.set_runtime_snapshot(snapshot, centers)
	vehicles.debug_set_simulation_time(0.0)
	_check(vehicles.active_vehicle_count() == 4, "crossing interlock fixture must contain train, bus, car, and motorcycle")

	var tracked_kinds := ["bus", "car", "motorcycle"]
	var previous_positions: Dictionary = {}
	var previous_route_times: Dictionary = {}
	var closed_side_by_kind: Dictionary = {}
	var stop_anchors: Dictionary = {}
	var waiting_frames: Dictionary = {}
	var resumed: Dictionary = {}
	var crossing_center: Vector2 = centers["1"]
	var closure_count := 0
	var was_closed := false
	var reopened_after_first_closure := false
	var saw_first_closure := false
	var step_violation := ""
	var closed_zone_violation := ""
	var side_violation := ""
	var stop_anchor_violation := ""
	for frame in 720:
		vehicles.debug_advance_simulation(1.0 / 60.0)
		var debug: Dictionary = vehicles.debug_route_snapshot()
		var state: Dictionary = Dictionary(Dictionary(debug.get("crossing_states", {})).get("1", {}))
		var closed := bool(state.get("closed", false))
		if closed and not was_closed:
			closure_count += 1
			if closure_count == 1:
				saw_first_closure = true
		if not closed and was_closed and closure_count == 1:
			reopened_after_first_closure = true

		for vehicle_variant: Variant in debug.get("vehicles", []):
			var vehicle: Dictionary = vehicle_variant
			var kind := str(vehicle.get("vehicle_kind", ""))
			if kind not in tracked_kinds:
				continue
			var position := Vector2(vehicle.get("position", Vector2.INF))
			var route_time := float(vehicle.get("route_time", -1.0))
			if (
				previous_positions.has(kind)
				and position.distance_to(Vector2(previous_positions[kind])) > 2.0
				and step_violation.is_empty()
			):
				step_violation = "%s jumped at frame %d" % [kind, frame]
			if closed and closure_count == 1:
				var crossing_distance := position.distance_to(crossing_center)
				if crossing_distance < 30.0 and closed_zone_violation.is_empty():
					closed_zone_violation = "%s entered the closed crossing at frame %d" % [kind, frame]
				var side := signf(position.x - crossing_center.x)
				if not closed_side_by_kind.has(kind) and not is_zero_approx(side):
					closed_side_by_kind[kind] = side
				elif (
					closed_side_by_kind.has(kind)
					and not is_zero_approx(side)
					and side * float(closed_side_by_kind[kind]) < 0.0
					and side_violation.is_empty()
				):
					side_violation = "%s crossed to the far side while the gate was closed at frame %d" % [kind, frame]
				var route_time_frozen := (
					previous_route_times.has(kind)
					and is_equal_approx(route_time, float(previous_route_times[kind]))
				)
				if crossing_distance <= 34.0 and route_time_frozen:
					if not stop_anchors.has(kind):
						stop_anchors[kind] = position
						waiting_frames[kind] = 1
					elif position.distance_to(Vector2(stop_anchors[kind])) <= 0.05:
						waiting_frames[kind] = int(waiting_frames.get(kind, 0)) + 1
					elif stop_anchor_violation.is_empty():
						stop_anchor_violation = "%s moved after its route-time froze at frame %d" % [kind, frame]
			elif reopened_after_first_closure and stop_anchors.has(kind):
				if position.distance_to(Vector2(stop_anchors[kind])) > 3.0:
					resumed[kind] = true
			previous_positions[kind] = position
			previous_route_times[kind] = route_time
		was_closed = closed
		if reopened_after_first_closure and resumed.size() == tracked_kinds.size():
			break

	_check(saw_first_closure, "crossing interlock fixture never reached a closed gate")
	_check(reopened_after_first_closure, "crossing interlock fixture never reopened after the train cleared")
	_check(step_violation.is_empty(), "road vehicle continuity failed: %s" % step_violation)
	_check(closed_zone_violation.is_empty(), "closed crossing exclusion failed: %s" % closed_zone_violation)
	_check(side_violation.is_empty(), "closed crossing side interlock failed: %s" % side_violation)
	_check(stop_anchor_violation.is_empty(), "closed crossing stop anchor failed: %s" % stop_anchor_violation)
	for kind: String in tracked_kinds:
		_check(stop_anchors.has(kind), "%s never reached its closed-gate stop line" % kind)
		_check(int(waiting_frames.get(kind, 0)) >= 10, "%s did not remain stopped while the gate was closed" % kind)
		_check(bool(resumed.get(kind, false)), "%s did not resume continuously after the gate reopened" % kind)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Transport network layer test failed: %s" % message)
