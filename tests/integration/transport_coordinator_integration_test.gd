extends SceneTree

const CoordinatorScript = preload("res://scripts/app/vertical_slice_coordinator.gd")
const CityTerrainMapScript = preload("res://scripts/world/city_terrain_map.gd")

const CURRENT_SAVE_PATH := "user://goal_2026_08_01/transport_coordinator_round_trip.json"
const LEGACY_SAVE_PATH := "user://goal_2026_08_01/transport_coordinator_schema5.json"
const INVALID_SAVE_PATH := "user://goal_2026_08_01/transport_coordinator_invalid_schema6.json"

var failed := false
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_project_route_and_current_round_trip()
	_validate_schema_five_station_migration()
	_validate_schema_six_rejects_malformed_transport()
	if failed:
		quit(1)
	else:
		print("Transport coordinator integration test passed. Checks=%d Schema=6" % checks)
		quit(0)


func _validate_project_route_and_current_round_trip() -> void:
	var coordinator = CoordinatorScript.new(20_260_801, 2_000_000)
	coordinator.terrain_map = CityTerrainMapScript.new()
	_check(coordinator.transport != null, "new_game must create the transport system")
	_check(coordinator.transport.routes.is_empty(), "new transport system must start without generated routes")

	var road_tiles := _horizontal_tiles(coordinator.terrain_map, 1, 2, 5)
	var depot_tile := _tile(coordinator.terrain_map, 1, 3)
	var stop_a_tile := _tile(coordinator.terrain_map, 2, 3)
	var stop_b_tile := _tile(coordinator.terrain_map, 4, 3)
	var city_grid: Array = []
	city_grid.resize(coordinator.terrain_map.cell_count())
	city_grid.fill("")
	var stop_a: Dictionary = coordinator.register_existing_building(stop_a_tile, "公車站")
	var stop_b: Dictionary = coordinator.register_existing_building(stop_b_tile, "公車站")
	city_grid[stop_a_tile] = "公車站"
	city_grid[stop_b_tile] = "公車站"
	_check(not stop_a.is_empty() and not stop_b.is_empty(), "completed bus-stop buildings must register")
	_check(coordinator.transport.stations.has(str(stop_a.get("building_id", ""))), "first completed stop must be registered in transport topology")
	_check(coordinator.transport.stations.has(str(stop_b.get("building_id", ""))), "second completed stop must be registered in transport topology")

	var road_quote: Dictionary = coordinator.transport_project_quote("road", "build", road_tiles, 20, city_grid)
	_check(bool(road_quote.get("ok", false)), "road corridor quote must succeed")
	_check(int(road_quote.get("tile_indices", []).size()) == road_tiles.size(), "quote must retain every selected road tile")
	var road_start: Dictionary = coordinator.start_transport_project("road", "build", road_tiles, 20, city_grid)
	_check(bool(road_start.get("ok", false)), "road corridor must start as one construction project")
	if not bool(road_start.get("ok", false)):
		return
	var road_job: Dictionary = road_start.get("job", {})
	_check(Array(road_job.get("metadata", {}).get("tile_indices", [])).size() == road_tiles.size(), "construction metadata must persist all project tiles")
	for tile_id: int in road_tiles:
		_check(not coordinator.active_construction_for_tile(tile_id).is_empty(), "every corridor tile must resolve to the active multi-tile job")
	_check(coordinator.transport.segments.is_empty(), "planned infrastructure must not become authoritative before construction completes")
	coordinator.advance_days(int(road_job.get("projected_remaining_days", 0)), {}, false)
	_check(coordinator.transport.segments.size() == 1, "construction completion must commit the road segment")
	_check(coordinator.active_construction_for_tile(road_tiles[0]).is_empty(), "completed multi-tile job must leave active construction")

	var depot_start: Dictionary = coordinator.start_transport_project("bus_depot", "build", [depot_tile], 20, city_grid)
	_check(bool(depot_start.get("ok", false)), "bus depot project must start")
	if not bool(depot_start.get("ok", false)):
		return
	coordinator.advance_days(int(depot_start.get("job", {}).get("projected_remaining_days", 0)), {}, false)
	_check(coordinator.transport.facilities.size() == 1, "depot must enter topology only after job completion")

	var route_result: Dictionary = coordinator.create_transport_route("bus", [stop_a_tile, stop_b_tile], 3, 8, 25, city_grid)
	_check(bool(route_result.get("ok", false)), "connected stops, road and depot must create a valid route")
	var route: Dictionary = route_result.get("route", {})
	var route_id := str(route.get("id", ""))
	_check(str(route.get("status", "")) == "operational", "valid enabled route must be operational")
	_check(coordinator.transport_service_operational_factor("bus") == 1.0, "operational bus route must expose service factor")
	_check(coordinator.transport_has_private_road_traffic(city_grid), "authored road with two building accesses must enable private traffic")
	_check(coordinator.transport_monthly_maintenance() > 0, "completed network and fleet must contribute maintenance")
	_check(coordinator.transport_navigation_blocked_tile_ids().has(road_tiles[0]), "completed road must be included in NPC navigation blockers")
	var runtime: Dictionary = coordinator.transport_visual_snapshot(city_grid)
	_check(Array(runtime.get("operational_lines", [])).size() == 1, "visual runtime may expose vehicles only for the operational route")

	var disabled: Dictionary = coordinator.set_transport_route_enabled(route_id, false, city_grid)
	_check(bool(disabled.get("ok", false)) and not bool(disabled.get("route", {}).get("enabled", true)) and str(disabled.get("route", {}).get("status", "")) != "operational", "player must be able to suspend a route")
	_check(coordinator.transport_service_operational_factor("bus") == 0.0, "disabled route must not contribute service")
	var enabled: Dictionary = coordinator.set_transport_route_enabled(route_id, true, city_grid)
	_check(bool(enabled.get("ok", false)) and str(enabled.get("route", {}).get("status", "")) == "operational", "valid route must resume operation")

	var save_error: Error = coordinator.save_game(CURRENT_SAVE_PATH)
	_check(save_error == OK, "schema 11 transport save must succeed: %s" % coordinator.session.save_service.last_error_message)
	_check(int(coordinator.session.state.metadata.get("vertical_slice", {}).get("schema_version", 0)) == 11, "current save must use vertical-slice schema 11")
	var restored = CoordinatorScript.new(1, 1)
	_check(restored.load_game(CURRENT_SAVE_PATH), "schema 11 transport save must load")
	_check(restored.transport.segments.size() == 1 and restored.transport.facilities.size() == 1, "transport infrastructure must survive save/load")
	_check(restored.transport.routes.has(route_id), "route must survive save/load")
	_check(str(restored.transport.routes.get(route_id, {}).get("status", "")) == "operational", "valid enabled route must remain operational after load")

	var demolition: Dictionary = restored.start_demolition(stop_a_tile, 20)
	_check(bool(demolition.get("ok", false)), "completed station building must support demolition")
	if bool(demolition.get("ok", false)):
		restored.advance_days(int(demolition.get("job", {}).get("projected_remaining_days", 0)), {}, false)
	_check(not restored.transport.stations.has(str(stop_a.get("building_id", ""))), "station demolition completion must unregister its topology node")
	_check(str(restored.transport.routes.get(route_id, {}).get("status", "")) == "suspended", "station removal must revalidate and suspend the broken route")
	_check(restored.transport_service_operational_factor("bus") == 0.0, "broken route must never remain operational")
	var deleted: Dictionary = restored.delete_transport_route(route_id)
	_check(bool(deleted.get("ok", false)) and not restored.transport.routes.has(route_id), "route deletion wrapper must use the transport system API")


func _validate_schema_five_station_migration() -> void:
	var legacy = CoordinatorScript.new(20_260_802, 500_000)
	legacy.terrain_map = CityTerrainMapScript.new()
	var station_tile := _tile(legacy.terrain_map, 7, 7)
	var building: Dictionary = legacy.register_existing_building(station_tile, "捷運站")
	_check(not building.is_empty(), "legacy fixture station must register")
	legacy.transport.segments["injected_schema6_segment"] = {
		"id": "injected_schema6_segment",
		"kind": "metro_track",
		"tile_path": [_tile(legacy.terrain_map, 6, 7), station_tile],
		"status": "completed",
		"project_id": "injected",
	}
	legacy.call("_stash_subsystems")
	var vertical: Dictionary = legacy.session.state.metadata.get("vertical_slice", {}).duplicate(true)
	vertical["schema_version"] = 5
	legacy.session.state.metadata["vertical_slice"] = vertical
	_check(legacy.session.save_now(LEGACY_SAVE_PATH) == OK, "schema 5 save with an untrusted future transport field must remain loadable as legacy data")
	var migrated = CoordinatorScript.new(2, 2)
	_check(migrated.load_game(LEGACY_SAVE_PATH), "schema 5 save must load through backward-compatible migration")
	_check(migrated.transport != null and migrated.transport.segments.is_empty(), "legacy load must initialize an empty transport network")
	_check(migrated.transport.stations.has(str(building.get("building_id", ""))), "legacy completed station building must reconcile into the new topology")


func _validate_schema_six_rejects_malformed_transport() -> void:
	var coordinator = CoordinatorScript.new(20_260_803, 500_000)
	coordinator.call("_stash_subsystems")
	var vertical: Dictionary = coordinator.session.state.metadata.get("vertical_slice", {}).duplicate(true)
	var malformed: Dictionary = Dictionary(vertical.get("transport", {})).duplicate(true)
	malformed["segments"] = []
	vertical["transport"] = malformed
	vertical["schema_version"] = 6
	coordinator.session.state.metadata["vertical_slice"] = vertical
	_check(
		coordinator.session.save_now(INVALID_SAVE_PATH) == ERR_INVALID_DATA,
		"schema 6 must refuse malformed transport collections instead of silently saving data loss"
	)


func _horizontal_tiles(terrain, start_x: int, y: int, end_x: int) -> Array[int]:
	var result: Array[int] = []
	for x in range(start_x, end_x + 1):
		result.append(_tile(terrain, x, y))
	return result


func _tile(terrain, x: int, y: int) -> int:
	return int(terrain.tile_id_for_coordinate(Vector2i(x, y)))


func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		return
	failed = true
	push_error("Transport coordinator integration test failed: %s" % message)
