extends SceneTree

const CoordinatorScript = preload("res://scripts/app/vertical_slice_coordinator.gd")
const CitySimulationServiceScript = preload("res://scripts/app/city_simulation_service.gd")
const CityTerrainMapScript = preload("res://scripts/world/city_terrain_map.gd")
const TransportModesScript = preload("res://data/catalogs/transport_modes.gd")
const VehicleControllerScript = preload("res://scripts/world/transport_vehicle_controller.gd")
const NetworkLayerScript = preload("res://scripts/world/transport_network_layer.gd")
const BuildingsScript = preload("res://data/catalogs/buildings.gd")

const SAVE_PATH := "user://transport_network_integration/round_trip.json"
const TEST_SEED := 20_260_801
const TEST_FUNDS := 3_000_000
const METRO_SERVICE_FIXTURE := {
	"metro": {
		"building": "捷運站",
		"base_uses": 24,
		"reasonable": 30,
	},
}
const RELOAD_SERVICE_DEFINITION := {
	"base_uses": 24,
	"reasonable": 30,
	"reference_headway_minutes": 10,
}

var _failed := false
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_test_save()
	_exercise_player_authored_metro_lifecycle()
	_remove_test_save()
	_exercise_fresh_mixed_runtime_reload()
	_remove_test_save()
	if _failed:
		quit(1)
	else:
		print("Transport network integration test passed. Checks=%d" % _checks)
		quit(0)


func _exercise_player_authored_metro_lifecycle() -> void:
	var coordinator = CoordinatorScript.new(TEST_SEED, TEST_FUNDS)
	var city_grid: Array[String] = []
	city_grid.resize(CityTerrainMapScript.CELL_COUNT)
	city_grid.fill("")

	_check(coordinator.transport != null, "new game must create the authoritative transport model")
	_check(coordinator.transport.segments.is_empty(), "new game must not seed transport segments")
	_check(coordinator.transport.facilities.is_empty(), "new game must not seed transport facilities")
	_check(coordinator.transport.routes.is_empty(), "new game must not seed routes")
	_check(coordinator.transport.active_lines().is_empty(), "new game must have zero operational lines")
	_check(Array(coordinator.transport_visual_snapshot(city_grid).get("operational_lines", [])).is_empty(), "new-game runtime must not publish vehicle-producing lines")
	_check(is_zero_approx(coordinator.transport_service_operational_factor("metro")), "new game must have zero metro service factor")
	# Isolate topology behavior from the decorative/default terrain fixture.  The
	# assertions above already prove that a real new game starts with no authored
	# transport overlay; the remainder needs a deterministic all-flat build site.
	coordinator.terrain_map = CityTerrainMapScript.new()

	var track_tiles := _horizontal_tiles(coordinator.terrain_map, 1, 2, 5)
	var depot_tile := _tile(coordinator.terrain_map, 1, 3)
	var station_a_tile := _tile(coordinator.terrain_map, 2, 3)
	var station_b_tile := _tile(coordinator.terrain_map, 4, 3)
	var station_a: Dictionary = coordinator.register_existing_building(station_a_tile, "捷運站")
	var station_b: Dictionary = coordinator.register_existing_building(station_b_tile, "捷運站")
	city_grid[station_a_tile] = "捷運站"
	city_grid[station_b_tile] = "捷運站"
	_check(not station_a.is_empty() and not station_b.is_empty(), "completed compatible metro stations must register")
	_check(coordinator.transport.stations.size() == 2, "both completed stations must enter the transport topology")

	var controller = VehicleControllerScript.new()
	controller.size = Vector2(1280, 720)
	var centers := _tile_centers(coordinator.terrain_map)
	controller.set_runtime_snapshot(coordinator.transport_visual_snapshot(city_grid), centers)
	_check(controller.active_vehicle_count() == 0, "stations alone must not create vehicles")
	_check(_metro_service_income(coordinator, city_grid) == 0, "stations without an operational route must earn zero metro revenue")

	var disconnected: Dictionary = coordinator.create_transport_route(
		"metro", [station_a_tile, station_b_tile], 2, 6, 30, city_grid
	)
	_check(not bool(disconnected.get("ok", false)), "disconnected stations must reject route creation")
	_check(str(disconnected.get("error", "")) == "transport_route_invalid", "disconnected route rejection must be explicit")
	_check(_validation_has_prefix(disconnected, "station_not_connected"), "disconnected route must report missing track topology")
	_check(coordinator.transport.routes.is_empty(), "a rejected route must not become authoritative")

	var track_quote: Dictionary = coordinator.transport_project_quote(
		"metro_track", "build", track_tiles, 20, city_grid
	)
	_check(bool(track_quote.get("ok", false)), "player-selected continuous metro track must produce a quote")
	_check(Array(track_quote.get("tile_indices", [])).size() == track_tiles.size(), "track quote must retain the complete selected path")
	_check(bool(track_quote.get("can_start", false)), "funded track quote must be startable")
	var track_start: Dictionary = coordinator.start_transport_project(
		"metro_track", "build", track_tiles, 20, city_grid
	)
	_check(bool(track_start.get("ok", false)), "quoted metro track project must start")
	if not bool(track_start.get("ok", false)):
		controller.free()
		return
	_check(coordinator.transport.segments.is_empty(), "under-construction track must not be committed early")
	for tile_id: int in track_tiles:
		_check(not coordinator.active_construction_for_tile(tile_id).is_empty(), "every selected track tile must belong to the construction job")
	var track_job_id := str(track_start.get("job", {}).get("id", ""))
	var initial_track_job: Dictionary = coordinator.construction.jobs.get(track_job_id, {})
	var initial_total_days := int(initial_track_job.get("projected_total_days", 0))
	var initial_labor_cost := int(initial_track_job.get("projected_labor_cost", 0))
	var initial_requested_workers := int(initial_track_job.get("blueprint", {}).get("requested_workers", 0))
	var reassigned: Dictionary = coordinator.construction.reassign_workers(
		track_job_id, 5, coordinator.game_day()
	)
	_check(bool(reassigned.get("ok", false)), "active transport scheduler job must support worker reassignment")
	if bool(reassigned.get("ok", false)):
		var reassigned_job: Dictionary = reassigned.get("job", {})
		coordinator._upsert_construction(reassigned_job)
		_check(int(reassigned_job.get("worker_count", 0)) == 5, "transport reassignment updates only the current worker allocation")
		_check(int(reassigned_job.get("blueprint", {}).get("requested_workers", 0)) == initial_requested_workers, "transport reassignment retains canonical initial requested workers")
		_check(int(reassigned_job.get("projected_total_days", 0)) == initial_total_days, "transport reassignment retains its initial total-day projection")
		_check(int(reassigned_job.get("projected_labor_cost", 0)) == initial_labor_cost, "transport reassignment retains its initial labor projection")
		_check(coordinator.save_game(SAVE_PATH) == OK, "reassigned active transport job must save")
		var reassigned_restored = CoordinatorScript.new(1, 1)
		var reassigned_loaded := reassigned_restored.load_game(SAVE_PATH)
		_check(reassigned_loaded, "reassigned active transport job must restore")
		if reassigned_loaded:
			coordinator = reassigned_restored
			var loaded_job: Dictionary = coordinator.construction.jobs.get(track_job_id, {})
			_check(int(loaded_job.get("worker_count", 0)) == 5, "restored transport job retains its current reassigned workers")
			_check(int(loaded_job.get("blueprint", {}).get("requested_workers", 0)) == initial_requested_workers, "restored transport job retains canonical initial requested workers")
			_check(int(loaded_job.get("projected_total_days", 0)) == initial_total_days, "restored transport job retains its initial total-day projection")
			_check(int(loaded_job.get("projected_labor_cost", 0)) == initial_labor_cost, "restored transport job retains its initial labor projection")
	var track_days := int(coordinator.construction.jobs.get(track_job_id, {}).get("projected_remaining_days", 0))
	_check(track_days > 0, "metro track project must take positive game time")
	coordinator.advance_days(track_days, {}, false)
	_check(coordinator.transport.segments.size() == 1, "advancing through construction must commit the track")
	_check(Array(coordinator.transport.segments.values()[0].get("tile_path", [])) == track_tiles, "completed track must preserve the player's contiguous path")

	var missing_depot: Dictionary = coordinator.create_transport_route(
		"metro", [station_a_tile, station_b_tile], 2, 6, 30, city_grid
	)
	_check(not bool(missing_depot.get("ok", false)), "track and stations without a depot must reject route activation")
	_check(_validation_has_prefix(missing_depot, "connected_depot_required"), "missing-depot rejection must identify the lifecycle dependency")
	_check(coordinator.transport.routes.is_empty(), "route must remain absent until every required facility is complete")

	var depot_quote: Dictionary = coordinator.transport_project_quote(
		"metro_depot", "build", [depot_tile], 20, city_grid
	)
	_check(bool(depot_quote.get("ok", false)), "player-selected connected metro depot must produce a quote")
	var depot_start: Dictionary = coordinator.start_transport_project(
		"metro_depot", "build", [depot_tile], 20, city_grid
	)
	_check(bool(depot_start.get("ok", false)), "quoted metro depot project must start")
	if not bool(depot_start.get("ok", false)):
		controller.free()
		return
	_check(coordinator.transport.facilities.is_empty(), "under-construction depot must not be committed early")
	var depot_days := int(depot_start.get("job", {}).get("projected_remaining_days", 0))
	_check(depot_days > 0, "metro depot project must take positive game time")
	coordinator.advance_days(depot_days, {}, false)
	_check(coordinator.transport.facilities.size() == 1, "advancing through construction must commit the depot")

	var route_result: Dictionary = coordinator.create_transport_route(
		"metro", [station_a_tile, station_b_tile], 2, 6, 30, city_grid
	)
	_check(bool(route_result.get("ok", false)), "completed stations, depot, and continuous track must create a route")
	if not bool(route_result.get("ok", false)):
		controller.free()
		return
	var route: Dictionary = route_result.get("route", {})
	var route_id := str(route.get("id", ""))
	_check(str(route.get("status", "")) == "operational", "complete enabled metro route must be operational")
	_check(Array(route.get("path_tile_ids", [])).size() >= 2, "operational route must expose its authoritative connected path")
	_check(coordinator.transport.active_lines().size() == 1, "only the completed route may become an active line")
	_check(is_equal_approx(coordinator.transport_service_operational_factor("metro"), 1.0), "operational metro must expose a positive service factor")

	var expected_network_maintenance := (
		track_tiles.size() * int(TransportModesScript.segment_spec("metro_track").get("monthly_maintenance_per_tile", 0))
		+ int(TransportModesScript.facility_spec("metro_depot").get("monthly_maintenance", 0))
		+ 2 * int(TransportModesScript.station_spec("捷運站").get("monthly_maintenance", 0))
		+ int(route.get("fleet_size", 0)) * int(TransportModesScript.route_spec("metro").get("fleet_monthly_maintenance", 0))
	)
	_check(coordinator.transport_monthly_maintenance() == expected_network_maintenance, "transport maintenance must include track, depot, stations, and active fleet")
	var expected_incremental_maintenance := (
		track_tiles.size() * int(TransportModesScript.segment_spec("metro_track").get("monthly_maintenance_per_tile", 0))
		+ int(TransportModesScript.facility_spec("metro_depot").get("monthly_maintenance", 0))
		+ int(route.get("fleet_size", 0)) * int(TransportModesScript.route_spec("metro").get("fleet_monthly_maintenance", 0))
	)
	_check(coordinator.transport_incremental_monthly_maintenance() == expected_incremental_maintenance, "incremental transport maintenance must exclude external station buildings already charged by the city grid")
	var base_building_maintenance := CitySimulationServiceScript.maintenance_cost(city_grid, BuildingsScript.all())
	_check(base_building_maintenance + coordinator.transport_incremental_monthly_maintenance() > base_building_maintenance, "municipal maintenance composition must add only non-duplicated transport maintenance")
	var revenue_with_route := _metro_service_income(coordinator, city_grid)
	_check(revenue_with_route > 0, "an operational metro route must earn service revenue")

	var blocker_ids: PackedInt32Array = coordinator.transport_navigation_blocked_tile_ids()
	for tile_id: int in track_tiles:
		_check(blocker_ids.has(tile_id), "completed track tile must block NPC navigation: %d" % tile_id)
	_check(blocker_ids.has(depot_tile), "completed depot must block NPC navigation")
	_check(blocker_ids.has(station_a_tile) and blocker_ids.has(station_b_tile), "completed stations must block NPC navigation")

	var runtime: Dictionary = coordinator.transport_visual_snapshot(city_grid)
	_check(Array(runtime.get("operational_lines", [])).size() == 1, "runtime snapshot must publish exactly the operational route")
	controller.set_runtime_snapshot(runtime, centers)
	_check(controller.active_vehicle_count() == int(route.get("fleet_size", 0)), "VehicleController must create only the operational route's fleet")
	var vehicle_debug: Dictionary = controller.debug_route_snapshot()
	_check(int(vehicle_debug.get("autonomous_tile_vehicle_count", -1)) == 0, "VehicleController must never create autonomous per-tile vehicles")
	for vehicle_variant: Variant in vehicle_debug.get("vehicles", []):
		var vehicle: Dictionary = vehicle_variant
		_check(str(vehicle.get("route_id", "")) == route_id, "every vehicle must be owned by the operational route")
		_check(bool(vehicle.get("on_authoritative_path", false)), "every vehicle must sample the authoritative route path")

	_check(coordinator.save_game(SAVE_PATH) == OK, "transport save must succeed")
	var restored = CoordinatorScript.new(1, 1)
	_check(restored.load_game(SAVE_PATH), "transport save must load")
	_check(restored.transport.segments == coordinator.transport.segments, "track topology must survive save/load")
	_check(restored.transport.facilities == coordinator.transport.facilities, "depot topology must survive save/load")
	_check(restored.transport.stations == coordinator.transport.stations, "station topology must survive save/load")
	_check(restored.transport.routes.has(route_id), "route must survive save/load")
	_check(str(restored.transport.routes.get(route_id, {}).get("status", "")) == "operational", "loaded valid route must remain operational")
	_check(Array(restored.transport_visual_snapshot(city_grid).get("operational_lines", [])).size() == 1, "loaded runtime must still expose the route")
	_check(_metro_service_income(restored, city_grid) == revenue_with_route, "loaded route must preserve service revenue semantics")

	var demolition_quote: Dictionary = restored.transport_project_quote(
		"metro_track", "demolish", [track_tiles[2]], 20, city_grid
	)
	_check(bool(demolition_quote.get("ok", false)), "selecting one tile of the authored track must quote whole-segment demolition")
	_check(Array(demolition_quote.get("tile_indices", [])).size() == track_tiles.size(), "demolition quote must resolve the complete connected segment")
	var demolition_start: Dictionary = restored.start_transport_project(
		"metro_track", "demolish", [track_tiles[2]], 20, city_grid
	)
	_check(bool(demolition_start.get("ok", false)), "quoted track demolition must start")
	var balance_after_first_demolition := restored.treasury_balance()
	var duplicate_demolition: Dictionary = restored.start_transport_project(
		"metro_track", "demolish", [track_tiles[2]], 20, city_grid
	)
	_check(not bool(duplicate_demolition.get("ok", false)), "an active whole-segment demolition must reject a second overlapping project")
	_check(restored.treasury_balance() == balance_after_first_demolition, "rejected duplicate demolition must not deduct treasury funds")
	if bool(demolition_start.get("ok", false)):
		var demolition_days := int(demolition_start.get("job", {}).get("projected_remaining_days", 0))
		_check(demolition_days > 0, "track demolition must take positive game time")
		restored.advance_days(demolition_days, {}, false)
	_check(restored.transport.segments.is_empty(), "completed demolition must remove the authoritative track")
	_check(str(restored.transport.routes.get(route_id, {}).get("status", "")) == "suspended", "breaking route topology must suspend the enabled route")
	_check(restored.transport.active_lines().is_empty(), "suspended route must disappear from active lines")
	_check(is_zero_approx(restored.transport_service_operational_factor("metro")), "suspended route must provide zero service factor")
	var broken_runtime: Dictionary = restored.transport_visual_snapshot(city_grid)
	_check(Array(broken_runtime.get("operational_lines", [])).is_empty(), "broken runtime must publish no vehicle-producing route")
	controller.set_runtime_snapshot(broken_runtime, centers)
	_check(controller.active_vehicle_count() == 0, "VehicleController must remove vehicles after route suspension")
	_check(_metro_service_income(restored, city_grid) == 0, "broken route must earn zero metro revenue")

	controller.free()


func _exercise_fresh_mixed_runtime_reload() -> void:
	var source = CoordinatorScript.new(TEST_SEED + 1, TEST_FUNDS)
	source.terrain_map = CityTerrainMapScript.new()
	var terrain = source.terrain_map

	# These completed buildings are persisted by CityState, then reconstructed
	# into the city grid after load.  Their road adjacency is the authoritative
	# source for private car and motorcycle traffic.
	var residence_a: Dictionary = source.register_existing_building(_tile(terrain, 2, 0), "住宅")
	var residence_b: Dictionary = source.register_existing_building(_tile(terrain, 6, 0), "住宅")
	_check(not residence_a.is_empty() and not residence_b.is_empty(), "private-road access buildings must register before the mixed save")

	var crossing_tile := _tile(terrain, 7, 5)
	var crossing_id := "level_crossing_%03d" % crossing_tile
	var build_plan := {
		"title": "Fresh reload mixed transport fixture",
		"segments": [
			{"id": "reload_bus_road", "kind": "road", "tile_path": _horizontal_tiles(terrain, 1, 1, 7)},
			{"id": "reload_metro_track", "kind": "metro_track", "tile_path": _horizontal_tiles(terrain, 1, 3, 7)},
			{"id": "reload_rail_track", "kind": "rail_track", "tile_path": _horizontal_tiles(terrain, 1, 5, 7)},
			{"id": "reload_airport_road", "kind": "road", "tile_path": [crossing_tile]},
			{
				"id": "reload_airport_taxiway",
				"kind": "taxiway",
				"tile_path": [
					_tile(terrain, 8, 6),
					_tile(terrain, 8, 7),
					_tile(terrain, 8, 8),
					_tile(terrain, 7, 8),
					_tile(terrain, 6, 8),
				],
			},
			{"id": "reload_airport_runway", "kind": "runway", "tile_path": _horizontal_tiles(terrain, 4, 9, 7)},
		],
		"facilities": [
			{"id": "reload_bus_depot", "kind": "bus_depot", "tile_id": _tile(terrain, 1, 2)},
			{"id": "reload_metro_depot", "kind": "metro_depot", "tile_id": _tile(terrain, 1, 4)},
			{"id": "reload_rail_depot", "kind": "rail_depot", "tile_id": _tile(terrain, 1, 6)},
			{"id": "reload_rail_signal", "kind": "rail_signal", "tile_id": _tile(terrain, 7, 6)},
		],
		"stations": [
			{"id": "reload_bus_stop_a", "building_name": "公車站", "tile_id": _tile(terrain, 2, 2)},
			{"id": "reload_bus_stop_b", "building_name": "公車站", "tile_id": _tile(terrain, 6, 2)},
			{"id": "reload_metro_station_a", "building_name": "捷運站", "tile_id": _tile(terrain, 2, 4)},
			{"id": "reload_metro_station_b", "building_name": "捷運站", "tile_id": _tile(terrain, 6, 4)},
			{"id": "reload_train_station_a", "building_name": "火車站", "tile_id": _tile(terrain, 2, 6)},
			{"id": "reload_train_station_b", "building_name": "火車站", "tile_id": _tile(terrain, 6, 6)},
			{"id": "reload_airport", "building_name": "機場", "tile_id": _tile(terrain, 8, 5)},
		],
	}
	var started: Dictionary = source.transport.start_project("build", build_plan, terrain)
	_check(bool(started.get("ok", false)), "mixed all-mode infrastructure must start before the reload save: %s" % started)
	if not bool(started.get("ok", false)):
		return
	var completed: Dictionary = source.transport.complete_project(str(started.get("project", {}).get("id", "")))
	_check(bool(completed.get("ok", false)), "mixed all-mode infrastructure must complete before the reload save: %s" % completed)
	if not bool(completed.get("ok", false)):
		return
	_check(source.transport.segments.size() == 6, "mixed fixture must commit every road, guideway, taxiway, and runway segment")
	_check(source.transport.facilities.size() == 4, "mixed fixture must commit every required depot and rail signal")
	_check(source.transport.stations.size() == 7, "mixed fixture must commit every public transport station")
	_check(source.transport.crossings.has(crossing_id), "road and rail overlap must author a level crossing before save")

	var route_stop_ids := {
		"bus": ["reload_bus_stop_a", "reload_bus_stop_b"],
		"metro": ["reload_metro_station_a", "reload_metro_station_b"],
		"train": ["reload_train_station_a", "reload_train_station_b"],
		"air": ["reload_airport"],
	}
	var expected_routes: Dictionary = {}
	for mode: String in ["bus", "metro", "train", "air"]:
		var route_id := "reload_%s_route" % mode
		var route_result: Dictionary = source.transport.create_route({
			"id": route_id,
			"name": "Reload %s route" % mode,
			"mode": mode,
			"stop_ids": Array(route_stop_ids[mode]).duplicate(),
			"fleet_size": 2,
			"headway_minutes": 8,
			"fare": 30,
			"enabled": true,
		})
		_check(bool(route_result.get("ok", false)) and bool(route_result.get("valid", false)), "%s route must validate in the mixed topology: %s" % [mode, route_result])
		if not bool(route_result.get("ok", false)) or not bool(route_result.get("valid", false)):
			return
		var route: Dictionary = route_result.get("route", {})
		_check(str(route.get("status", "")) == "operational", "%s route must be operational before save" % mode)
		_check(Array(route.get("path_tile_ids", [])).size() >= 2, "%s route must expose an authoritative runtime path" % mode)
		expected_routes[route_id] = route.duplicate(true)
	_check(source.transport.active_lines().size() == 4, "mixed fixture must publish all four public transport modes")

	var population: int = int(source.population.population_count())
	var bus_revenue_without_suspended: int = int(
		source.transport.service_revenue("bus", population, RELOAD_SERVICE_DEFINITION)
	)
	_check(bus_revenue_without_suspended > 0, "operational bus route must earn revenue before the suspended control route is added")
	var suspended_route_id := "reload_suspended_bus_route"
	var suspended_result: Dictionary = source.transport.create_route({
		"id": suspended_route_id,
		"name": "Reload suspended bus control",
		"mode": "bus",
		"stop_ids": ["missing_bus_stop_a", "missing_bus_stop_b"],
		"fleet_size": 2,
		"headway_minutes": 8,
		"fare": 30,
		"enabled": true,
	})
	_check(bool(suspended_result.get("ok", false)) and not bool(suspended_result.get("valid", true)), "invalid enabled bus intent must persist as a suspended route")
	_check(str(suspended_result.get("route", {}).get("status", "")) == "suspended", "invalid enabled bus intent must be explicitly suspended")
	_check(source.transport.active_lines().size() == 4, "suspended route must not enter active lines")
	_check(source.transport.service_revenue("bus", population, RELOAD_SERVICE_DEFINITION) == bus_revenue_without_suspended, "suspended route must add zero bus revenue before save")

	var expected_transport: Dictionary = source.transport.to_dict()
	var save_error := source.save_game(SAVE_PATH)
	_check(save_error == OK, "mixed transport reload save must succeed")
	if save_error != OK:
		return
	var restored = CoordinatorScript.new(1, 1)
	var loaded := restored.load_game(SAVE_PATH)
	_check(loaded, "mixed transport reload save must load into a new coordinator")
	if not loaded:
		return
	_check(restored.transport.to_dict() == expected_transport, "complete mixed transport topology must survive a deterministic save/load round trip")
	_check(restored.transport.segments.size() == 6, "loaded topology must retain every segment")
	_check(restored.transport.facilities.size() == 4, "loaded topology must retain every facility")
	_check(restored.transport.stations.size() == 7, "loaded topology must retain every station")
	_check(restored.transport.crossings.has(crossing_id), "loaded topology must retain its level crossing")
	for route_id_variant: Variant in expected_routes.keys():
		var route_id := str(route_id_variant)
		var restored_route: Dictionary = restored.transport.routes.get(route_id, {})
		_check(str(restored_route.get("status", "")) == "operational", "loaded route must remain operational: %s" % route_id)
		_check(Array(restored_route.get("path_tile_ids", [])) == Array(expected_routes[route_id].get("path_tile_ids", [])), "loaded route must retain its authoritative path: %s" % route_id)
	_check(str(restored.transport.routes.get(suspended_route_id, {}).get("status", "")) == "suspended", "loaded invalid route must remain suspended")
	_check(restored.transport.active_lines().size() == 4, "loaded model must publish only the four operational routes")
	_check(restored.transport.service_revenue("bus", restored.population.population_count(), RELOAD_SERVICE_DEFINITION) == bus_revenue_without_suspended, "loaded suspended route must still add zero revenue")

	var restored_city_grid := _city_grid_from_coordinator(restored)
	var runtime: Dictionary = restored.transport_visual_snapshot(restored_city_grid)
	var operational_lines: Array = runtime.get("operational_lines", [])
	var private_paths: Array = runtime.get("private_road_paths", [])
	_check(operational_lines.size() == 4, "fresh loaded runtime must publish four operational public lines")
	_check(private_paths.size() == 1, "fresh loaded runtime must reconstruct exactly one private road component from persisted buildings")
	_check(Dictionary(runtime.get("crossings", {})).has(crossing_id), "fresh loaded runtime must publish the persisted level crossing")
	var crossing_visual: Dictionary = Dictionary(runtime.get("tile_states", {})).get(str(crossing_tile), {})
	_check(not str(crossing_visual.get("crossing", "")).is_empty(), "loaded crossing tile must expose crossing topology to the network layer")

	# No controller or network layer exists before load in this scenario.  These
	# nodes are intentionally fresh consumers of the restored authoritative data.
	var stage := Control.new()
	stage.name = "FreshReloadMapStage"
	stage.size = Vector2(1280, 720)
	root.add_child(stage)
	var network_layer = NetworkLayerScript.new()
	stage.add_child(network_layer)
	var controller = VehicleControllerScript.new()
	stage.add_child(controller)
	var centers := _tile_centers(restored.terrain_map)
	network_layer.set_network_snapshot(runtime, centers)
	controller.set_runtime_snapshot(runtime, centers)
	var vehicle_debug: Dictionary = controller.debug_route_snapshot()
	var crossing_states: Dictionary = vehicle_debug.get("crossing_states", {})
	network_layer.set_crossing_states(crossing_states)

	var expected_public_vehicle_count := 0
	for line_variant: Variant in operational_lines:
		expected_public_vehicle_count += int(Dictionary(line_variant).get("fleet_size", 0))
	var expected_private_vehicle_count := mini(private_paths.size(), 2) * 2
	_check(expected_public_vehicle_count == 8, "four loaded public routes must retain their complete two-vehicle fleets")
	_check(controller.active_vehicle_count() == expected_public_vehicle_count + expected_private_vehicle_count, "fresh controller actor count must derive only from loaded operational lines and private road paths")
	var public_actor_counts: Dictionary = {}
	var private_kinds: Array[String] = []
	var suspended_actor_count := 0
	for vehicle_variant: Variant in vehicle_debug.get("vehicles", []):
		var vehicle: Dictionary = vehicle_variant
		var actor_route_id := str(vehicle.get("route_id", ""))
		_check(bool(vehicle.get("on_authoritative_path", false)), "every freshly reconstructed vehicle must sample an authoritative loaded path")
		if actor_route_id.begins_with("private_road_"):
			private_kinds.append(str(vehicle.get("vehicle_kind", "")))
			var private_path := Array(vehicle.get("path_tile_ids", []))
			var path_was_published := false
			for path_variant: Variant in private_paths:
				if private_path == Array(Dictionary(path_variant).get("path_tile_ids", [])):
					path_was_published = true
					break
			_check(path_was_published, "private vehicle must use a path published by the loaded road topology")
		elif actor_route_id == suspended_route_id:
			suspended_actor_count += 1
		elif expected_routes.has(actor_route_id):
			public_actor_counts[actor_route_id] = int(public_actor_counts.get(actor_route_id, 0)) + 1
			var expected_route: Dictionary = expected_routes[actor_route_id]
			_check(str(vehicle.get("route_mode", "")) == str(expected_route.get("mode", "")), "fresh public actor must retain loaded route mode: %s" % actor_route_id)
			_check(str(vehicle.get("vehicle_kind", "")) == str(expected_route.get("vehicle_kind", "")), "fresh public actor must retain loaded vehicle kind: %s" % actor_route_id)
			_check(Array(vehicle.get("path_tile_ids", [])) == Array(expected_route.get("path_tile_ids", [])), "fresh public actor must retain loaded authoritative path: %s" % actor_route_id)
		else:
			_check(false, "fresh controller created an actor from an unknown route: %s" % actor_route_id)
	private_kinds.sort()
	_check(private_kinds == ["car", "motorcycle"], "fresh loaded road runtime must create one car and one motorcycle")
	for route_id_variant: Variant in expected_routes.keys():
		var route_id := str(route_id_variant)
		_check(int(public_actor_counts.get(route_id, 0)) == 2, "fresh controller must recreate the full loaded fleet for %s" % route_id)
	_check(suspended_actor_count == 0, "fresh controller must create zero actors for the loaded suspended route")
	_check(not crossing_states.is_empty(), "fresh controller must derive runtime state for the loaded crossing")
	_check(crossing_states.has(str(crossing_tile)), "fresh controller crossing state must use the loaded crossing tile")

	var layer_debug: Dictionary = network_layer.debug_snapshot()
	_check(bool(layer_debug.get("owned_by_player_network", false)), "fresh network layer must remain owned by the loaded player-authored network")
	_check(not bool(layer_debug.get("autonomous_vehicle_generation", true)), "fresh network layer must never generate autonomous vehicles")
	_check(bool(layer_debug.get("shares_map_stage_transform", false)), "fresh network layer must inherit the loaded map stage transform")
	_check(int(layer_debug.get("operational_line_count", -1)) == 4, "fresh network layer must receive all loaded operational routes")
	_check(int(layer_debug.get("tile_state_count", 0)) > 0, "fresh network layer must receive loaded topology tiles")
	_check(Dictionary(layer_debug.get("crossing_states", {})).has(str(crossing_tile)), "fresh network layer must receive loaded crossing state from the fresh controller")
	stage.free()

func _city_grid_from_coordinator(coordinator) -> Array[String]:
	var result: Array[String] = []
	result.resize(CityTerrainMapScript.CELL_COUNT)
	result.fill("")
	for building_variant: Variant in coordinator.session.state.buildings.values():
		if not building_variant is Dictionary:
			continue
		var building: Dictionary = building_variant
		var tile_id := int(building.get("tile_index", -1))
		if tile_id >= 0 and tile_id < result.size() and str(building.get("status", "active")) != "scrapped":
			result[tile_id] = str(building.get("building_name", ""))
	return result


func _horizontal_tiles(terrain, first_x: int, y: int, last_x: int) -> Array[int]:
	var result: Array[int] = []
	for x in range(first_x, last_x + 1):
		result.append(_tile(terrain, x, y))
	return result


func _tile(terrain, x: int, y: int) -> int:
	return int(terrain.tile_id_for_coordinate(Vector2i(x, y)))


func _tile_centers(terrain) -> Dictionary:
	var result: Dictionary = {}
	for tile_id in terrain.cell_count():
		var coordinate: Vector2i = terrain.coordinate_for_tile_id(tile_id)
		result[str(tile_id)] = Vector2(64.0 + coordinate.x * 72.0, 64.0 + coordinate.y * 52.0)
	return result


func _validation_has_prefix(result: Dictionary, prefix: String) -> bool:
	for error_variant: Variant in result.get("validation_errors", []):
		if str(error_variant).begins_with(prefix):
			return true
	return false


func _metro_service_income(coordinator, city_grid: Array[String]) -> int:
	if city_grid.is_empty():
		return 0
	return coordinator.transport_service_revenue(
		"metro",
		coordinator.population.population_count(),
		Dictionary(METRO_SERVICE_FIXTURE.get("metro", {})).duplicate(true)
	)


func _remove_test_save() -> void:
	var absolute_path := ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(absolute_path)
	var directory := absolute_path.get_base_dir()
	if DirAccess.dir_exists_absolute(directory):
		DirAccess.remove_absolute(directory)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Transport network integration test failed: %s" % message)
