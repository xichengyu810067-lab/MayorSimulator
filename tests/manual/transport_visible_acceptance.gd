extends SceneTree

## Visible-only transport acceptance fixture.
##
## This prepares completed stations, a contiguous metro guideway, and its depot
## but deliberately leaves route creation, suspension, demolition, and reload
## to real player interactions in the normal Main scene.

const SAVE_PATH := "user://mayor_simulator/tests/transport_visible_acceptance.json"
const LOG_PREFIX := "TRANSPORT_VISIBLE_ACCEPTANCE"
const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")

var _main
var _prepared := false
var _last_state_fingerprint := ""


func _initialize() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	call_deferred("_boot")


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	_main.start_save_path = SAVE_PATH
	_main.start_screen.set_continue_available(_main.call("_has_start_save"))
	print("%s_READY save=%s" % [LOG_PREFIX, SAVE_PATH])
	if DisplayServer.get_name() == "headless":
		call_deferred("_finish_headless_smoke")


func _finish_headless_smoke() -> void:
	for _frame in range(3):
		await process_frame
	print("%s_HEADLESS_SMOKE_PASSED" % LOG_PREFIX)
	await TestCleanup.finish(self, [_main], 0)


func _process(_delta: float) -> bool:
	if _main == null or not is_instance_valid(_main):
		return false
	if _prepared:
		_log_transport_state_if_changed()
		return false
	if not bool(_main.get("_game_started")):
		return false
	_prepared = true
	call_deferred("_prepare_if_needed")
	return false


func _prepare_if_needed() -> void:
	var coordinator = _main.vertical_slice
	if coordinator == null or coordinator.transport == null:
		push_error("%s_FAILED coordinator unavailable" % LOG_PREFIX)
		return
	if not coordinator.transport.segments.is_empty():
		print("%s_LOADED existing transport retained" % LOG_PREFIX)
		_main.call("_update_transport_runtime")
		_main.call("_refresh_transport_planning_panel")
		return

	var terrain = coordinator.terrain_map
	var track_tiles := _horizontal_tiles(terrain, 1, 2, 5)
	var depot_tile := _tile(terrain, 1, 3)
	var station_a_tile := _tile(terrain, 2, 3)
	var station_b_tile := _tile(terrain, 4, 3)
	for tile_id: int in track_tiles + [depot_tile, station_a_tile, station_b_tile]:
		if not terrain.is_buildable(tile_id):
			terrain.flatten_tile(tile_id)

	_register_station(coordinator, station_a_tile)
	_register_station(coordinator, station_b_tile)
	var track_start: Dictionary = coordinator.start_transport_project(
		"metro_track", "build", track_tiles, 20, _main.city_grid
	)
	if not bool(track_start.get("ok", false)):
		push_error("%s_FAILED track=%s" % [LOG_PREFIX, track_start])
		return
	coordinator.advance_days(int(track_start.get("job", {}).get("projected_remaining_days", 0)), {}, false)
	var depot_start: Dictionary = coordinator.start_transport_project(
		"metro_depot", "build", [depot_tile], 20, _main.city_grid
	)
	if not bool(depot_start.get("ok", false)):
		push_error("%s_FAILED depot=%s" % [LOG_PREFIX, depot_start])
		return
	coordinator.advance_days(int(depot_start.get("job", {}).get("projected_remaining_days", 0)), {}, false)
	_main.call("_consume_vertical_events", coordinator.drain_ui_events())
	_main.call("_update_transport_runtime")
	_main.call("_refresh_transport_planning_panel")
	_main.call("_update_ui")
	_main.call("_autosave", "qa:transport_visible_fixture")
	print(
		"%s_PREPARED station_tiles=%s track_tiles=%s depot_tile=%d routes=%d" % [
			LOG_PREFIX,
			[station_a_tile, station_b_tile],
			track_tiles,
			depot_tile,
			coordinator.transport.routes.size(),
		]
	)
	_log_transport_state_if_changed()


func _log_transport_state_if_changed() -> void:
	var coordinator = _main.vertical_slice
	if coordinator == null or coordinator.transport == null:
		return
	var route_states: Array[String] = []
	for route_id_variant: Variant in coordinator.transport.routes.keys():
		var route_id := str(route_id_variant)
		var route: Dictionary = coordinator.transport.routes[route_id]
		route_states.append("%s:%s:%s" % [route_id, str(route.get("status", "")), str(route.get("enabled", false))])
	route_states.sort()
	var state := {
		"route_states": route_states,
		"segments": coordinator.transport.segments.size(),
		"active_lines": coordinator.transport.active_lines().size(),
		"visible_vehicles": _main.transport_vehicle_controller.active_vehicle_count(),
		"metro_revenue": coordinator.transport_service_revenue(
			"metro", _main.population, {"base_uses": 24, "reasonable": 30, "reference_headway_minutes": 10}
		),
		"maintenance_full": coordinator.transport_monthly_maintenance(),
		"maintenance_incremental": coordinator.transport_incremental_monthly_maintenance(),
		"treasury": coordinator.treasury_balance(),
	}
	var fingerprint := JSON.stringify(state)
	if fingerprint == _last_state_fingerprint:
		return
	_last_state_fingerprint = fingerprint
	print("%s_STATE %s" % [LOG_PREFIX, fingerprint])


func _register_station(coordinator, tile_id: int) -> void:
	var record: Dictionary = coordinator.register_existing_building(tile_id, "捷運站")
	if record.is_empty():
		push_error("%s_FAILED station tile=%d" % [LOG_PREFIX, tile_id])
		return
	_main.city_grid[tile_id] = "捷運站"
	_main.call("_update_tile_visual", tile_id, "捷運站")


func _horizontal_tiles(terrain, first_x: int, y: int, last_x: int) -> Array[int]:
	var result: Array[int] = []
	for x in range(first_x, last_x + 1):
		result.append(_tile(terrain, x, y))
	return result


func _tile(terrain, x: int, y: int) -> int:
	return int(terrain.tile_id_for_coordinate(Vector2i(x, y)))
