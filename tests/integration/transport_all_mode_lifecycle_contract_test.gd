extends SceneTree

const TransportModesScript = preload("res://data/catalogs/transport_modes.gd")
const TransportNetworkSystemScript = preload("res://scripts/systems/city/transport_network_system.gd")
const CityTerrainMapScript = preload("res://scripts/world/city_terrain_map.gd")
const VehicleControllerScript = preload("res://scripts/world/transport_vehicle_controller.gd")

const POPULATION := 300
const SERVICE_DEFINITION := {
	"base_uses": 24,
	"reasonable": 30,
	"reference_headway_minutes": 10,
}

var _failed := false
var _checks := 0
var _terrain


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_terrain = CityTerrainMapScript.new()
	var fixtures := _route_mode_fixtures()
	_assert_catalog_coverage(fixtures)
	for mode: String in TransportModesScript.route_modes():
		if not fixtures.has(mode):
			_fail("supported route mode has no lifecycle fixture and must not be skipped: %s" % mode)
			continue
		_exercise_route_mode(mode, Dictionary(fixtures[mode]))
	_exercise_private_road_modes()
	if _failed:
		quit(1)
	else:
		print("Transport all-mode lifecycle contract passed. RouteModes=%d PrivateKinds=2 Checks=%d" % [fixtures.size(), _checks])
		quit(0)


func _assert_catalog_coverage(fixtures: Dictionary) -> void:
	var supported := TransportModesScript.route_modes()
	var fixture_modes: Array[String] = []
	for mode_variant: Variant in fixtures.keys():
		fixture_modes.append(str(mode_variant))
	fixture_modes.sort()
	_check(fixture_modes == supported, "fixtures must exactly cover every public route mode; fixtures=%s supported=%s" % [fixture_modes, supported])
	for mode: String in supported:
		var spec := TransportModesScript.route_spec(mode)
		_check(not spec.is_empty(), "%s must expose a public route specification" % mode)
		_check(not str(spec.get("vehicle_kind", "")).is_empty(), "%s must publish a vehicle kind" % mode)


func _exercise_route_mode(mode: String, fixture: Dictionary) -> void:
	var network = TransportNetworkSystemScript.new()
	_check(_build_and_complete(network, {"stations": Array(fixture.get("stations", [])).duplicate(true)}), "%s station-only fixture must complete before infrastructure" % mode)
	var disconnected_result: Dictionary = network.create_route(_route_plan(mode, fixture))
	_check(bool(disconnected_result.get("ok", false)), "%s must retain disconnected player route intent for audit" % mode)
	_check(not bool(disconnected_result.get("valid", true)), "%s must not validate without its required network" % mode)
	_check(str(disconnected_result.get("route", {}).get("status", "")) == "suspended", "%s disconnected route must be suspended" % mode)
	var route_id := str(disconnected_result.get("route", {}).get("id", ""))
	_check(route_id == "%s_lifecycle_route" % mode, "%s suspended route must retain the requested route id" % mode)
	_assert_zero_service(network, mode, "disconnected")

	_check(_build_and_complete(network, Dictionary(fixture.get("infrastructure_plan", {}))), "%s infrastructure fixture must complete through public project APIs" % mode)
	_check(network.routes.has(route_id), "%s complete_project revalidation must retain the same route record" % mode)
	var route: Dictionary = network.routes.get(route_id, {})
	_check(str(route.get("status", "")) == "operational", "%s complete network must become operational" % mode)
	_check(Array(route.get("validation_errors", [])).is_empty(), "%s complete_project must clear the suspended route's validation errors" % mode)
	_check(str(route.get("id", "")) == route_id, "%s revalidation must not replace the route id" % mode)
	_check(network.active_lines().size() == 1, "%s complete network must publish exactly one active line" % mode)
	_check(network.service_operational_factor(mode) > 0.0, "%s operational route must publish a positive service factor" % mode)
	_check(network.service_revenue(mode, POPULATION, SERVICE_DEFINITION) > 0, "%s operational route must earn positive service revenue" % mode)

	var controller = _controller_for(network, _empty_city_grid())
	var expected_fleet := int(route.get("fleet_size", 0))
	_check(controller.active_vehicle_count() == expected_fleet, "%s operational route must create exactly its declared fleet" % mode)
	var expected_kind := str(TransportModesScript.route_spec(mode).get("vehicle_kind", ""))
	for vehicle_variant: Variant in controller.debug_route_snapshot().get("vehicles", []):
		var vehicle: Dictionary = vehicle_variant
		_check(str(vehicle.get("route_id", "")) == str(route.get("id", "")), "%s vehicle must be owned by the operational route id" % mode)
		_check(str(vehicle.get("route_mode", "")) == mode, "%s vehicle must retain its owning route mode" % mode)
		_check(str(vehicle.get("vehicle_kind", "")) == expected_kind, "%s vehicle kind must match the public mode catalog" % mode)
		_check(Array(vehicle.get("path_tile_ids", [])) == Array(route.get("path_tile_ids", [])), "%s vehicle path must exactly equal the route's authoritative path" % mode)
		_check(bool(vehicle.get("on_authoritative_path", false)), "%s vehicle must remain on its authoritative path" % mode)

	var demolition: Dictionary = network.start_project("demolish", {"segment_ids": [str(fixture.get("break_segment_id", ""))]}, _terrain)
	_check(bool(demolition.get("ok", false)), "%s critical segment demolition must start through the public API" % mode)
	if bool(demolition.get("ok", false)):
		var project_id := str(demolition.get("project", {}).get("id", ""))
		var completed: Dictionary = network.complete_project(project_id)
		_check(bool(completed.get("ok", false)), "%s critical segment demolition must complete through the public API" % mode)
	_check(str(network.routes.get(str(route.get("id", "")), {}).get("status", "")) == "suspended", "%s route must suspend after its critical segment is demolished" % mode)
	_assert_zero_service(network, mode, "demolished")
	controller.set_runtime_snapshot(network.visual_runtime_snapshot(_empty_city_grid(), _terrain), _tile_centers())
	_check(controller.active_vehicle_count() == 0, "%s must remove every vehicle after network demolition" % mode)
	controller.free()


func _exercise_private_road_modes() -> void:
	var network = TransportNetworkSystemScript.new()
	var road_path := _horizontal_path(2, 2, 6)
	var city_grid := _empty_city_grid()
	city_grid[_tile(1, 2)] = "住宅"
	city_grid[_tile(7, 2)] = "商店"

	var controller = _controller_for(network, city_grid)
	_check(controller.active_vehicle_count() == 0, "car and motorcycle must not exist without a connected authored road")

	_check(_build_and_complete(network, {
		"segments": [{"id": "private_road_main", "kind": "road", "tile_path": road_path}],
	}), "private road fixture must build through public project APIs")
	_check(network.has_private_road_traffic(city_grid, _terrain), "a road with two building access points must become valid for private traffic")
	var authoritative_paths := _published_private_paths(network, city_grid)
	_check(not authoritative_paths.is_empty(), "valid private road must publish at least one authoritative path")
	controller.set_runtime_snapshot(network.visual_runtime_snapshot(city_grid, _terrain), _tile_centers())
	var kinds := _vehicle_kinds(controller)
	_check(controller.active_vehicle_count() == 2, "valid private road must create exactly the controller's car and motorcycle pair")
	_check(kinds == ["car", "motorcycle"], "valid private road must create both supported private vehicle kinds: %s" % [kinds])
	for vehicle_variant: Variant in controller.debug_route_snapshot().get("vehicles", []):
		var vehicle: Dictionary = vehicle_variant
		_check(authoritative_paths.has(Array(vehicle.get("path_tile_ids", []))), "private vehicle path must equal a path published by network.private_road_paths")
		_check(bool(vehicle.get("on_authoritative_path", false)), "private vehicle sampler must remain on the published road path")

	var demolition: Dictionary = network.start_project("demolish", {"segment_ids": ["private_road_main"]}, _terrain)
	_check(bool(demolition.get("ok", false)), "private road demolition must start")
	if bool(demolition.get("ok", false)):
		_check(bool(network.complete_project(str(demolition.get("project", {}).get("id", ""))).get("ok", false)), "private road demolition must complete")
	_check(not network.has_private_road_traffic(city_grid, _terrain), "demolished road must invalidate private traffic")
	controller.set_runtime_snapshot(network.visual_runtime_snapshot(city_grid, _terrain), _tile_centers())
	_check(controller.active_vehicle_count() == 0, "car and motorcycle must both disappear after road demolition")
	controller.free()


func _assert_zero_service(network, mode: String, phase: String) -> void:
	_check(network.active_lines().is_empty(), "%s %s network must expose zero active lines" % [mode, phase])
	_check(is_zero_approx(network.service_operational_factor(mode)), "%s %s network must expose zero service factor" % [mode, phase])
	_check(network.service_revenue(mode, POPULATION, SERVICE_DEFINITION) == 0, "%s %s network must earn zero revenue" % [mode, phase])
	var controller = _controller_for(network, _empty_city_grid())
	_check(controller.active_vehicle_count() == 0, "%s %s network must produce zero vehicles" % [mode, phase])
	controller.free()


func _build_and_complete(network, plan: Dictionary) -> bool:
	var started: Dictionary = network.start_project("build", plan, _terrain)
	if not bool(started.get("ok", false)):
		push_error("All-mode lifecycle fixture failed to start: %s" % started)
		return false
	var project_id := str(started.get("project", {}).get("id", ""))
	var completed: Dictionary = network.complete_project(project_id)
	return bool(completed.get("ok", false)) and str(completed.get("project", {}).get("status", "")) == "completed"


func _controller_for(network, city_grid: Array[String]):
	var controller = VehicleControllerScript.new()
	controller.size = Vector2(1280, 720)
	controller.set_runtime_snapshot(network.visual_runtime_snapshot(city_grid, _terrain), _tile_centers())
	return controller


func _vehicle_kinds(controller) -> Array[String]:
	var result: Array[String] = []
	for vehicle_variant: Variant in controller.debug_route_snapshot().get("vehicles", []):
		result.append(str(Dictionary(vehicle_variant).get("vehicle_kind", "")))
	result.sort()
	return result


func _published_private_paths(network, city_grid: Array[String]) -> Array:
	var result: Array = []
	for path_variant: Variant in network.private_road_paths(city_grid, _terrain):
		var path: Array = Array(Dictionary(path_variant).get("path_tile_ids", [])).duplicate()
		if not path.is_empty():
			result.append(path)
	return result


func _route_plan(mode: String, fixture: Dictionary) -> Dictionary:
	var stop_ids: Array[String] = []
	for station_variant: Variant in fixture.get("stations", []):
		stop_ids.append(str(Dictionary(station_variant).get("id", "")))
	return {
		"id": "%s_lifecycle_route" % mode,
		"name": "%s lifecycle" % mode,
		"mode": mode,
		"stop_ids": stop_ids,
		"fleet_size": 2,
		"headway_minutes": 8,
		"fare": 30,
		"enabled": true,
	}


func _route_mode_fixtures() -> Dictionary:
	var bus_stations := [
		{"id": "bus_stop_a", "building_name": "公車站", "tile_id": _tile(2, 2)},
		{"id": "bus_stop_b", "building_name": "公車站", "tile_id": _tile(6, 2)},
	]
	var metro_stations := [
		{"id": "metro_station_a", "building_name": "捷運站", "tile_id": _tile(2, 4)},
		{"id": "metro_station_b", "building_name": "捷運站", "tile_id": _tile(6, 4)},
	]
	var train_stations := [
		{"id": "train_station_a", "building_name": "火車站", "tile_id": _tile(2, 6)},
		{"id": "train_station_b", "building_name": "火車站", "tile_id": _tile(6, 6)},
	]
	var air_stations := [
		{"id": "airport_terminal", "building_name": "機場", "tile_id": _tile(8, 5)},
	]
	return {
		"bus": {
			"stations": bus_stations,
			"break_segment_id": "bus_road",
			"infrastructure_plan": {
				"segments": [{"id": "bus_road", "kind": "road", "tile_path": _horizontal_path(1, 1, 7)}],
				"facilities": [{"id": "bus_depot", "kind": "bus_depot", "tile_id": _tile(1, 2)}],
			},
		},
		"metro": {
			"stations": metro_stations,
			"break_segment_id": "metro_track",
			"infrastructure_plan": {
				"segments": [{"id": "metro_track", "kind": "metro_track", "tile_path": _horizontal_path(3, 1, 7)}],
				"facilities": [{"id": "metro_depot", "kind": "metro_depot", "tile_id": _tile(1, 4)}],
			},
		},
		"train": {
			"stations": train_stations,
			"break_segment_id": "rail_track",
			"infrastructure_plan": {
				"segments": [{"id": "rail_track", "kind": "rail_track", "tile_path": _horizontal_path(5, 1, 7)}],
				"facilities": [
					{"id": "rail_depot", "kind": "rail_depot", "tile_id": _tile(1, 6)},
					{"id": "rail_signal", "kind": "rail_signal", "tile_id": _tile(7, 6)},
				],
			},
		},
		"air": {
			"stations": air_stations,
			"break_segment_id": "airport_runway",
			"infrastructure_plan": {
				"segments": [
					{"id": "airport_road", "kind": "road", "tile_path": [_tile(7, 5)]},
					{"id": "airport_taxiway", "kind": "taxiway", "tile_path": [_tile(8, 6), _tile(8, 7), _tile(8, 8), _tile(7, 8), _tile(6, 8)]},
					{"id": "airport_runway", "kind": "runway", "tile_path": _horizontal_path(9, 4, 7)},
				],
			},
		},
	}


func _empty_city_grid() -> Array[String]:
	var result: Array[String] = []
	result.resize(CityTerrainMapScript.CELL_COUNT)
	result.fill("")
	return result


func _horizontal_path(row: int, first_column: int, last_column: int) -> Array[int]:
	var result: Array[int] = []
	for column in range(first_column, last_column + 1):
		result.append(_tile(column, row))
	return result


func _tile(column: int, row: int) -> int:
	return int(_terrain.tile_id_for_coordinate(Vector2i(column, row)))


func _tile_centers() -> Dictionary:
	var result: Dictionary = {}
	for tile_id in _terrain.cell_count():
		var coordinate: Vector2i = _terrain.coordinate_for_tile_id(tile_id)
		result[str(tile_id)] = Vector2(64.0 + coordinate.x * 72.0, 64.0 + coordinate.y * 52.0)
	return result


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_fail(message)


func _fail(message: String) -> void:
	_failed = true
	push_error("Transport all-mode lifecycle contract failed: %s" % message)
