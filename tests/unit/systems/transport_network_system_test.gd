extends SceneTree

const TransportModesScript = preload("res://data/catalogs/transport_modes.gd")
const TransportNetworkSystemScript = preload("res://scripts/systems/city/transport_network_system.gd")
const CityTerrainMapScript = preload("res://scripts/world/city_terrain_map.gd")

var failed := false
var checks := 0
var terrain


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	terrain = CityTerrainMapScript.new()
	_validate_catalog_and_planning_rules()
	_validate_disconnected_station_never_spawns_vehicle()
	_validate_complete_networks_and_persistence()
	if failed:
		quit(1)
	else:
		print("Transport network system test passed. Modes=4 Overlay=true Checks=%d" % checks)
		quit(0)


func _validate_catalog_and_planning_rules() -> void:
	var catalog := TransportModesScript.validation_snapshot()
	_check(bool(catalog.get("valid", false)), "transport mode catalog must be internally valid")
	_check(str(catalog.get("infrastructure_layer", "")) == "transport_overlay", "infrastructure must be separate from terrain")
	_check(Array(catalog.get("segment_kinds", [])).size() == 5, "all five infrastructure segment kinds must be cataloged")

	var planner = TransportNetworkSystemScript.new()
	var tree_tile := _tile(0, 0)
	terrain.configure_tile(tree_tile, "trees")
	var terrain_rejected: Dictionary = planner.quote_project("build", {
		"segments": [{"kind": "road", "tile_path": [tree_tile]}],
	}, terrain)
	_check(not bool(terrain_rejected.get("ok", false)) and _issues_have(terrain_rejected, "terrain_not_flat"), "non-flat terrain must reject infrastructure")
	terrain.configure_tile(tree_tile, "flat_grass")

	var non_cardinal: Dictionary = planner.quote_project("build", {
		"segments": [{"kind": "road", "tile_path": [_tile(0, 0), _tile(1, 1)]}],
	}, terrain)
	_check(not bool(non_cardinal.get("ok", false)) and _issues_have(non_cardinal, "non_cardinal_segment_path"), "diagonal tile paths must be rejected")

	var occupied: Dictionary = planner.quote_project("build", {
		"segments": [{"kind": "road", "tile_path": [_tile(0, 0)]}],
	}, terrain, [_tile(0, 0)])
	_check(not bool(occupied.get("ok", false)) and _issues_have(occupied, "tile_occupied"), "occupied tiles must reject infrastructure")

	var construction: Dictionary = planner.quote_project("build", {
		"segments": [{"kind": "road", "tile_path": [_tile(0, 0)]}],
	}, terrain, [], [_tile(0, 0)])
	_check(not bool(construction.get("ok", false)) and _issues_have(construction, "tile_under_construction"), "active construction tiles must reject infrastructure")


func _validate_disconnected_station_never_spawns_vehicle() -> void:
	var network = TransportNetworkSystemScript.new()
	_check(bool(network.register_station("orphan_metro_a", "捷運站", _tile(1, 1)).get("ok", false)), "first orphan metro station registration failed")
	_check(bool(network.register_station("orphan_metro_b", "捷運站", _tile(4, 1)).get("ok", false)), "second orphan metro station registration failed")
	var created: Dictionary = network.create_route({
		"id": "orphan_metro_line",
		"name": "未連通捷運",
		"mode": "metro",
		"stop_ids": ["orphan_metro_a", "orphan_metro_b"],
		"fleet_size": 2,
		"headway_minutes": 6,
		"fare": 30,
		"enabled": true,
	})
	_check(bool(created.get("ok", false)) and not bool(created.get("valid", true)), "disconnected route should be retained as invalid player intent")
	_check(str(created.get("route", {}).get("status", "")) == "suspended", "enabled disconnected route must be suspended")
	_check(network.active_lines().is_empty(), "disconnected stations must never expose an active line")
	var runtime: Dictionary = network.visual_runtime_snapshot([], terrain)
	_check(Array(runtime.get("operational_lines", [])).is_empty(), "disconnected station runtime must contain no vehicle-producing line")
	_check(is_equal_approx(network.service_operational_factor("metro"), 0.0), "disconnected metro must produce no service factor")


func _validate_complete_networks_and_persistence() -> void:
	var network = TransportNetworkSystemScript.new()

	var bus_plan := {
		"title": "玩家公車路網",
		"segments": [{"id": "road_main", "kind": "road", "tile_path": _horizontal_path(1, 1, 5)}],
		"facilities": [{"id": "bus_depot_main", "kind": "bus_depot", "tile_id": _tile(1, 2)}],
		"stations": [
			{"id": "bus_stop_a", "building_name": "公車站", "tile_id": _tile(2, 2)},
			{"id": "bus_stop_b", "building_name": "公車站", "tile_id": _tile(4, 2)},
		],
	}
	var bus_quote: Dictionary = network.quote_project("build", bus_plan, terrain)
	_check(bool(bus_quote.get("ok", false)) and int(bus_quote.get("total_cost", 0)) == 9_400, "bus network quote must include road, depot, and both stops")
	_check(_build_and_complete(network, bus_plan), "bus transport project did not complete")
	var bus_route := network.create_route({
		"id": "bus_line_1", "name": "市區公車", "mode": "bus",
		"stop_ids": ["bus_stop_a", "bus_stop_b"], "fleet_size": 2,
		"headway_minutes": 8, "fare": 15, "enabled": true,
	})
	_check(_route_is_operational(bus_route), "complete bus road, stops, depot, and fleet must activate")

	var metro_plan := {
		"title": "玩家捷運路網",
		"segments": [{"id": "metro_main", "kind": "metro_track", "tile_path": _horizontal_path(3, 1, 5)}],
		"facilities": [{"id": "metro_depot_main", "kind": "metro_depot", "tile_id": _tile(1, 4)}],
		"stations": [
			{"id": "metro_station_a", "building_name": "捷運站", "tile_id": _tile(2, 4)},
			{"id": "metro_station_b", "building_name": "捷運站", "tile_id": _tile(4, 4)},
		],
	}
	var metro_quote: Dictionary = network.quote_project("build", metro_plan, terrain)
	_check(bool(metro_quote.get("ok", false)) and int(metro_quote.get("total_cost", 0)) == 23_400, "metro quote must include track, depot, and stations")
	_check(_build_and_complete(network, metro_plan), "metro transport project did not complete")
	var metro_route := network.create_route({
		"id": "metro_line_1", "name": "藍線", "mode": "metro",
		"stop_ids": ["metro_station_a", "metro_station_b"], "fleet_size": 2,
		"headway_minutes": 5, "fare": 30, "enabled": true,
	})
	_check(_route_is_operational(metro_route), "complete metro stations, tracks, depot, and fleet must activate")

	var train_plan := {
		"title": "玩家火車路網",
		"segments": [{"id": "rail_main", "kind": "rail_track", "tile_path": _horizontal_path(6, 1, 5)}],
		"facilities": [
			{"id": "rail_depot_main", "kind": "rail_depot", "tile_id": _tile(1, 7)},
			{"id": "rail_signal_main", "kind": "rail_signal", "tile_id": _tile(5, 7)},
		],
		"stations": [
			{"id": "train_station_a", "building_name": "火車站", "tile_id": _tile(2, 7)},
			{"id": "train_station_b", "building_name": "火車站", "tile_id": _tile(4, 7)},
		],
	}
	var train_quote: Dictionary = network.quote_project("build", train_plan, terrain)
	_check(bool(train_quote.get("ok", false)) and int(train_quote.get("total_cost", 0)) == 25_150, "train quote must include track, depot, signal, and stations")
	_check(_build_and_complete(network, train_plan), "train transport project did not complete")
	var train_route := network.create_route({
		"id": "train_line_1", "name": "城際線", "mode": "train",
		"stop_ids": ["train_station_a", "train_station_b"], "fleet_size": 1,
		"headway_minutes": 15, "fare": 60, "enabled": true,
	})
	_check(_route_is_operational(train_route), "complete heavy rail network must activate")

	var air_plan := {
		"title": "玩家機場路網",
		"segments": [
			{"id": "airport_road", "kind": "road", "tile_path": [_tile(7, 5)]},
			{"id": "airport_taxiway", "kind": "taxiway", "tile_path": [_tile(8, 6), _tile(8, 7), _tile(8, 8), _tile(7, 8), _tile(6, 8)]},
			{"id": "airport_runway", "kind": "runway", "tile_path": _horizontal_path(9, 4, 7)},
		],
		"stations": [{"id": "airport_terminal", "building_name": "機場", "tile_id": _tile(8, 5)}],
	}
	var air_quote: Dictionary = network.quote_project("build", air_plan, terrain)
	_check(bool(air_quote.get("ok", false)) and int(air_quote.get("total_cost", 0)) == 26_620, "airport quote must include road access, taxiway, runway, and terminal")
	_check(_build_and_complete(network, air_plan), "airport transport project did not complete")
	var air_route := network.create_route({
		"id": "air_line_1", "name": "區域航線", "mode": "air",
		"stop_ids": ["airport_terminal"], "fleet_size": 1,
		"headway_minutes": 30, "fare": 120, "enabled": true,
	})
	_check(_route_is_operational(air_route), "airport needs one terminal, a three-plus runway, taxiway, road access, and fleet")
	_check(network.active_lines().size() == 4, "all four complete transport modes must be operational")
	for line: Dictionary in network.active_lines():
		_check(not Array(line.get("path_tile_ids", [])).is_empty(), "operational route must publish its authoritative tile path")
		_check(not Array(line.get("station_tile_ids", [])).is_empty(), "operational route must publish station tile ids")
		_check(not str(line.get("vehicle_kind", "")).is_empty() and float(line.get("loop_seconds", 0.0)) > 0.0, "operational route must publish vehicle runtime semantics")

	var crossing_plan := {
		"title": "道路跨越捷運軌道",
		"segments": [{"id": "crossing_road", "kind": "road", "tile_path": [_tile(5, 2), _tile(5, 3), _tile(5, 4)]}],
	}
	var crossing_quote: Dictionary = network.quote_project("build", crossing_plan, terrain)
	_check(bool(crossing_quote.get("ok", false)), "road-track crossing plan should be valid")
	_check(Array(crossing_quote.get("crossing_tile_ids", [])).has(_tile(5, 3)), "road and metro overlap must automatically quote a level crossing")
	_check(int(crossing_quote.get("total_cost", 0)) == 2_460, "level crossing build charge must be included exactly once")
	_check(_build_and_complete(network, crossing_plan), "crossing road project did not complete")
	var crossing_id := "level_crossing_%03d" % _tile(5, 3)
	_check(network.crossings.has(crossing_id), "completed overlap must create an authoritative crossing record")
	var crossing_visual: Dictionary = network.tile_visual_state(_tile(5, 3), terrain)
	_check(Array(crossing_visual.get("segments", [])).has("road") and Array(crossing_visual.get("segments", [])).has("metro_track"), "crossing tile must retain both infrastructure layers")
	_check(str(crossing_visual.get("crossing", "")) == "level_crossing", "crossing visual state must expose the crossing kind")
	_check(str(crossing_visual.get("project_status", "")) == "completed", "completed infrastructure must retain project provenance")

	var empty_city: Array[String] = []
	for _index in range(CityTerrainMapScript.CELL_COUNT):
		empty_city.append("")
	_check(not network.has_private_road_traffic(empty_city, terrain), "roads without two built-building access points must not generate private traffic")
	var connected_city := empty_city.duplicate()
	connected_city[_tile(2, 2)] = "住宅"
	connected_city[_tile(4, 2)] = "商店"
	_check(network.has_private_road_traffic(connected_city, terrain), "connected road component with two building accesses may generate private traffic")
	var private_paths := network.private_road_paths(connected_city, terrain)
	_check(private_paths.size() >= 1 and int(private_paths[0].get("access_count", 0)) >= 2, "private road runtime must expose auditable building access points")

	var blocker_ids := network.navigation_blocker_ids()
	_check(blocker_ids.has(_tile(5, 3)) and blocker_ids.has(_tile(8, 5)), "roads, tracks, facilities, and stations must feed navigation blockers")
	_check(network.monthly_maintenance() == 4_434, "monthly maintenance must include infrastructure, facilities, stations, crossing, and active fleets")
	_check(is_equal_approx(network.service_operational_factor("bus"), 1.0) and is_equal_approx(network.service_operational_factor("metro"), 1.0), "valid enabled services must expose their operational factor")

	var runtime := network.visual_runtime_snapshot(connected_city, terrain)
	_check(Array(runtime.get("operational_lines", [])).size() == 4, "runtime snapshot must contain only the four operational lines")
	_check(Dictionary(runtime.get("tile_states", {})).has(str(_tile(5, 3))), "runtime snapshot must expose crossing tile state")
	_check(Dictionary(runtime.get("crossings", {})).has(crossing_id), "runtime snapshot must expose authoritative crossing records")

	var removal_quote := network.quote_project("demolish", {"segment_ids": ["metro_main"]}, terrain)
	_check(bool(removal_quote.get("ok", false)) and int(removal_quote.get("total_cost", 0)) == 1_150, "track demolition must have a deterministic per-tile quote")
	var removal_started := network.start_project("demolish", {"segment_ids": ["metro_main"]}, terrain)
	_check(bool(removal_started.get("ok", false)), "metro track demolition failed to start")
	var removal_project_id := str(removal_started.get("project", {}).get("id", ""))
	_check(bool(network.complete_project(removal_project_id).get("ok", false)), "metro track demolition failed to complete")
	_check(str(network.routes.get("metro_line_1", {}).get("status", "")) == "suspended", "removing a required segment must immediately suspend its enabled route")
	_check(network.active_lines().size() == 3 and is_equal_approx(network.service_operational_factor("metro"), 0.0), "suspended metro must produce no active line, vehicle, or service factor")
	_check(not network.crossings.has(crossing_id), "orphan level crossing must disappear after its track is removed")

	var snapshot := network.to_dict()
	var validation := TransportNetworkSystemScript.validate_snapshot(snapshot)
	_check(bool(validation.get("valid", false)), "authoritative transport snapshot must validate before persistence")
	var encoded := JSON.stringify(snapshot)
	var decoded: Variant = JSON.parse_string(encoded)
	_check(decoded is Dictionary, "transport snapshot must be JSON-safe")
	var restored = TransportNetworkSystemScript.create_from_dict(decoded)
	var restored_snapshot: Dictionary = restored.to_dict()
	_check(restored_snapshot == snapshot, "transport network must survive a deterministic JSON round trip")
	_check(restored.active_lines().size() == 3 and str(restored.routes.get("metro_line_1", {}).get("status", "")) == "suspended", "route operational and suspension states must survive loading")
	_check(restored.navigation_blocker_ids() == network.navigation_blocker_ids(), "navigation blockers must survive loading")


func _build_and_complete(network, plan: Dictionary) -> bool:
	var started: Dictionary = network.start_project("build", plan, terrain)
	if not bool(started.get("ok", false)):
		push_error("Transport test project failed to start: %s" % started)
		return false
	var project: Dictionary = started.get("project", {})
	if str(project.get("status", "")) != "under_construction":
		return false
	var completed: Dictionary = network.complete_project(str(project.get("id", "")))
	return bool(completed.get("ok", false)) and str(completed.get("project", {}).get("status", "")) == "completed"


func _route_is_operational(result: Dictionary) -> bool:
	return (
		bool(result.get("ok", false))
		and bool(result.get("valid", false))
		and str(result.get("route", {}).get("status", "")) == "operational"
	)


func _horizontal_path(row: int, first_column: int, last_column: int) -> Array[int]:
	var result: Array[int] = []
	for column in range(first_column, last_column + 1):
		result.append(_tile(column, row))
	return result


func _tile(column: int, row: int) -> int:
	return int(terrain.tile_id_for_coordinate(Vector2i(column, row)))


func _issues_have(result: Dictionary, prefix: String) -> bool:
	for issue_variant: Variant in result.get("issues", []):
		if str(issue_variant).begins_with(prefix):
			return true
	return false


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		return
	failed = true
	push_error("Transport network system test failed: %s" % label)
