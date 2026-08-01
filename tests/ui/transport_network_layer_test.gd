extends SceneTree

const NetworkLayerScript = preload("res://scripts/world/transport_network_layer.gd")
const VehicleControllerScript = preload("res://scripts/world/transport_vehicle_controller.gd")

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
	}
	ground.set_network_snapshot(isolated_snapshot, centers)
	vehicles.set_runtime_snapshot(isolated_snapshot, centers)
	_check(vehicles.active_vehicle_count() == 0, "an isolated track tile must not autonomously spawn a train")
	var ground_debug: Dictionary = ground.debug_snapshot()
	_check(not bool(ground_debug.get("autonomous_vehicle_generation", true)), "ground layer must never own vehicle generation")
	_check(bool(ground_debug.get("shares_map_stage_transform", false)), "network layer must inherit the map-stage transform")

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
	_check(is_equal_approx(after_pos.y, 120.0) and after_pos.x >= 80.0 and after_pos.x <= 280.0, "train position left the authoritative rail polyline")
	_check(bool(after.get("vehicles", [])[0].get("on_authoritative_path", false)), "vehicle debug contract must identify the authoritative route source")
	vehicles.debug_set_simulation_time(2.5)
	var crossing_debug: Dictionary = vehicles.debug_route_snapshot().get("crossing_states", {})
	_check(bool(Dictionary(crossing_debug.get("1", {})).get("closed", false)), "level-crossing barriers must close while a train is approaching")

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


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Transport network layer test failed: %s" % message)
