extends SceneTree

const CoordinatorScript = preload("res://scripts/app/vertical_slice_coordinator.gd")
const CityTerrainMapScript = preload("res://scripts/world/city_terrain_map.gd")
const TransportPlanningSessionScript = preload("res://scripts/systems/city/transport_planning_session.gd")

const SAVE_PATH := "user://b13_transport_route_package_round_trip.json"

var _failed := false
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	_test_atomic_package_and_automatic_route()
	_test_insufficient_funds_is_zero_write()
	_cleanup()
	if not _failed:
		print("Transport route package atomicity test passed. Checks=%d" % _checks)
	quit(1 if _failed else 0)


func _test_atomic_package_and_automatic_route() -> void:
	var coordinator = CoordinatorScript.new(20_260_903, 3_000_000)
	coordinator.terrain_map = CityTerrainMapScript.new()
	var grid := _empty_grid()
	var station_a := _tile(coordinator, 2, 3)
	var station_b := _tile(coordinator, 6, 3)
	var route_tiles := _horizontal_tiles(coordinator, 2, 6, 4)
	var begun: Dictionary = coordinator.begin_transport_planning_session("公車站", TransportPlanningSessionScript.WORKFLOW_ROUTE_PACKAGE_V1)
	_check(bool(begun.get("ok", false)), "package session begins")
	_check(str(begun.get("session", {}).get("workflow", "")) == "route_package_v1", "new public-transport sessions use the versioned package workflow")
	var treasury_before := coordinator.treasury_balance()
	var core_jobs_before: Dictionary = coordinator.session.state.construction_jobs.duplicate(true)
	var transport_before: Dictionary = coordinator.transport.to_dict()
	_check(bool(coordinator.draft_transport_session_station(station_a, 5).get("ok", false)), "first station is drafted")
	_check(bool(coordinator.draft_transport_session_station(station_b, 5).get("ok", false)), "second station is drafted")
	_check(coordinator.treasury_balance() == treasury_before, "station drafts do not charge treasury")
	_check(coordinator.construction.jobs.is_empty(), "station drafts do not create construction jobs")
	_check(coordinator.session.state.construction_jobs == core_jobs_before, "station drafts do not touch core construction authority")
	_check(coordinator.transport.to_dict() == transport_before, "station drafts do not touch transport authority")
	_check(bool(coordinator.begin_transport_session_network_placement("road", {}).get("ok", false)), "session advances to route drawing")
	_check(bool(coordinator.draft_transport_session_network("road", route_tiles, 5).get("ok", false)), "continuous guideway is drafted")
	_check(bool(coordinator.begin_transport_session_route_edit({"fleet_size": 2, "headway_minutes": 8, "fare": 25}).get("ok", false)), "package advances to one confirmation screen")
	var quote: Dictionary = coordinator.transport_session_package_quote(grid)
	_check(bool(quote.get("ok", false)), "complete package quotes successfully")
	_check(int(quote.get("route_tile_count", -1)) == 5, "L counts the unique contiguous guideway cells")
	_check(int(quote.get("route_construction_cost", -1)) == 5_000, "five-cell route construction uses the package formula")
	_check(int(quote.get("route_monthly_maintenance", -1)) == 1_500, "five-cell route maintenance uses the package formula")
	_check(int(quote.get("total_cost", -1)) == int(quote.get("station_building_cost", 0)) + 5_000 + int(quote.get("support_facility_cost", 0)) + int(quote.get("level_crossing_cost", 0)), "total is station buildings plus route and explicit support/crossing fees")
	_check(int(quote.get("support_facility_cost", 0)) == 3_600, "missing connected bus depot is included explicitly")
	var negative_entries_before := _negative_ledger_count(coordinator)
	var started: Dictionary = coordinator.start_transport_session_package(grid)
	_check(bool(started.get("ok", false)), "package starts after full candidate preflight: %s" % [started])
	if not bool(started.get("ok", false)):
		return
	_check(coordinator.treasury_balance() == treasury_before - int(quote.get("total_cost", 0)), "package deducts the quoted total exactly once")
	_check(_negative_ledger_count(coordinator) == negative_entries_before + 1, "package writes one negative ledger entry")
	_check(str(coordinator.transport_planning_session_snapshot().get("state", "")) == "waiting_construction", "package waits in the same session")
	var persisted_quote: Dictionary = coordinator.transport_planning_session_snapshot().get("route_draft", {}).get("package_quote", {})
	_check(not persisted_quote.has("station_placements") and not persisted_quote.has("support_plans"), "session persists price provenance without duplicating executable blueprints or project plans")
	_check(coordinator.transport.routes.is_empty(), "route is not activated before construction completes")
	var max_days := _maximum_active_days(coordinator)
	coordinator.advance_days(max_days, {}, false)
	var completed_session := coordinator.transport_planning_session_snapshot()
	_check(str(completed_session.get("state", "")) == "materialized", "all jobs automatically materialize the route")
	_check(coordinator.transport.routes.size() == 1, "one route is created automatically without reopening the UI")
	var route: Dictionary = coordinator.transport.routes.values()[0]
	_check(str(route.get("status", "")) == "operational", "automatic route passes topology and activates")
	_check(str(route.get("price_model", "")) == "route_package_v1", "route retains its versioned price provenance")
	_check(int(route.get("route_monthly_maintenance", -1)) == 1_500, "route retains the quoted monthly formula result")
	_check(coordinator.transport_incremental_monthly_maintenance() == 1_500 + 120 + 2 * 42, "incremental maintenance replaces segment rate, excludes station duplicate, and retains depot/fleet detail")
	_check(coordinator.save_game(SAVE_PATH) == OK, "materialized package saves")
	var restored = CoordinatorScript.new(1, 1)
	_check(restored.load_game(SAVE_PATH), "materialized package reloads")
	_check(restored.transport.to_dict() == coordinator.transport.to_dict(), "price provenance, network and route round-trip without recomputation")
	_check(restored.transport_incremental_monthly_maintenance() == coordinator.transport_incremental_monthly_maintenance(), "monthly package maintenance is stable after reload")


func _test_insufficient_funds_is_zero_write() -> void:
	var coordinator = CoordinatorScript.new(20_260_904, 1)
	coordinator.terrain_map = CityTerrainMapScript.new()
	var grid := _empty_grid()
	var station_a := _tile(coordinator, 2, 3)
	var station_b := _tile(coordinator, 6, 3)
	var route_tiles := _horizontal_tiles(coordinator, 2, 6, 4)
	coordinator.begin_transport_planning_session("公車站", TransportPlanningSessionScript.WORKFLOW_ROUTE_PACKAGE_V1)
	coordinator.draft_transport_session_station(station_a, 5)
	coordinator.draft_transport_session_station(station_b, 5)
	coordinator.begin_transport_session_network_placement("road", {})
	coordinator.draft_transport_session_network("road", route_tiles, 5)
	coordinator.begin_transport_session_route_edit({"fleet_size": 2, "headway_minutes": 8, "fare": 25})
	var core_before: Dictionary = coordinator.session.make_envelope().to_dict()
	var construction_before: Dictionary = coordinator.construction.to_dict()
	var transport_before: Dictionary = coordinator.transport.to_dict()
	var planning_before: Dictionary = coordinator.transport_planning_session.to_dict()
	var blueprint_before: Dictionary = coordinator.blueprint_library_service.snapshot()
	var result: Dictionary = coordinator.start_transport_session_package(grid)
	_check(str(result.get("error", "")) == "insufficient_treasury", "insufficient treasury rejects the whole package")
	_check(coordinator.session.make_envelope().to_dict() == core_before, "rejected package leaves treasury and core state unchanged")
	_check(coordinator.construction.to_dict() == construction_before, "rejected package leaves construction unchanged")
	_check(coordinator.transport.to_dict() == transport_before, "rejected package leaves transport unchanged")
	_check(coordinator.transport_planning_session.to_dict() == planning_before, "rejected package retains the editable session without authoritative refs")
	_check(coordinator.blueprint_library_service.snapshot() == blueprint_before, "rejected package does not increment blueprint usage")


func _empty_grid() -> Array[String]:
	var result: Array[String] = []
	result.resize(CityTerrainMapScript.CELL_COUNT)
	result.fill("")
	return result


func _tile(coordinator, column: int, row: int) -> int:
	return int(coordinator.terrain_map.tile_id_for_coordinate(Vector2i(column, row)))


func _horizontal_tiles(coordinator, first_column: int, last_column: int, row: int) -> Array[int]:
	var result: Array[int] = []
	for column in range(first_column, last_column + 1):
		result.append(_tile(coordinator, column, row))
	return result


func _maximum_active_days(coordinator) -> int:
	var result := 0
	for job_value: Variant in coordinator.construction.active_jobs():
		if job_value is Dictionary:
			result = maxi(result, int((job_value as Dictionary).get("projected_remaining_days", 0)))
	return maxi(1, result)


func _negative_ledger_count(coordinator) -> int:
	var result := 0
	for entry: Dictionary in coordinator.session.state.ledger.get_entries():
		if int(entry.get("amount", 0)) < 0:
			result += 1
	return result


func _cleanup() -> void:
	for path: String in [SAVE_PATH, "%s.bak" % SAVE_PATH, "%s.tmp" % SAVE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Transport route package atomicity test failed: %s" % label)
