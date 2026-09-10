extends SceneTree

const CoordinatorScript = preload("res://scripts/app/vertical_slice_coordinator.gd")
const CityTerrainMapScript = preload("res://scripts/world/city_terrain_map.gd")
const TransportPlanningSessionScript = preload("res://scripts/systems/city/transport_planning_session.gd")
const TransportModesScript = preload("res://data/catalogs/transport_modes.gd")

const SAVE_PATH := "user://b13_transport_route_package_round_trip.json"
const LEGACY_SAVE_PATH := "user://b13_transport_route_package_v1_round_trip.json"
const LEGACY_FIXTURE_PATH := "res://tests/fixtures/save_schema/route_package_v1_transport.json"

var _failed := false
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	_test_atomic_package_and_automatic_route()
	_test_insufficient_funds_is_zero_write()
	_test_legacy_v1_costs_are_not_recomputed()
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
	var standalone_route_quote: Dictionary = coordinator.transport.quote_project("build", {
		"segments": [{"kind": "road", "tile_path": route_tiles}],
		"facilities": [],
		"stations": [],
	}, coordinator.terrain_map, [], [])
	_check(bool(standalone_route_quote.get("ok", false)), "same-topology standalone route quotes successfully")
	_check(int(quote.get("route_construction_cost", -1)) == int(standalone_route_quote.get("total_cost", -2)), "package route construction equals same-topology standalone quote_project")
	_check(int(quote.get("route_monthly_maintenance", -1)) == int(standalone_route_quote.get("monthly_maintenance", -2)), "package route maintenance equals same-topology standalone quote_project")
	_check(int(quote.get("route_construction_cost", -1)) == 2_600, "five-cell v2 road construction uses the authoritative road rate")
	_check(int(quote.get("route_monthly_maintenance", -1)) == 90, "five-cell v2 road maintenance uses the authoritative road rate")
	_check(str(quote.get("price_model", "")) == "route_package_v2", "new package quote uses v2 pricing")
	_check(str(quote.get("price_provenance", "")) == TransportModesScript.ROUTE_PACKAGE_PRICE_PROVENANCE, "new package quote names quote_project provenance")
	_check(int(quote.get("total_cost", -1)) == int(quote.get("station_building_cost", 0)) + 2_600 + int(quote.get("support_facility_cost", 0)) + int(quote.get("level_crossing_cost", 0)), "total is station buildings plus parity route and explicit support/crossing fees")
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
	_check(str(persisted_quote.get("price_model", "")) == "route_package_v2" and str(persisted_quote.get("price_provenance", "")) == TransportModesScript.ROUTE_PACKAGE_PRICE_PROVENANCE, "session persists v2 model and provenance")
	var waiting_transport_snapshot: Dictionary = coordinator.transport.to_dict()
	_check(bool(coordinator.transport.validate_snapshot(waiting_transport_snapshot).get("valid", false)), "waiting v2 project snapshot validates")
	var corrupted_waiting_snapshot := waiting_transport_snapshot.duplicate(true)
	var corrupted_project_id := _first_v2_project_id(corrupted_waiting_snapshot)
	_check(not corrupted_project_id.is_empty(), "waiting snapshot contains the v2 route project")
	if not corrupted_project_id.is_empty():
		corrupted_waiting_snapshot["projects"][corrupted_project_id]["plan"]["segments"][0]["route_monthly_maintenance"] += 1
		corrupted_waiting_snapshot["projects"][corrupted_project_id]["quote"]["plan"] = corrupted_waiting_snapshot["projects"][corrupted_project_id]["plan"].duplicate(true)
		var corrupted_waiting_validation: Dictionary = coordinator.transport.validate_snapshot(corrupted_waiting_snapshot)
		_check(not bool(corrupted_waiting_validation.get("valid", true)) and _issues_have(corrupted_waiting_validation, "invalid_build_segment_v2_price_parity"), "tampered waiting v2 project pricing fails closed")
	_check(coordinator.transport.routes.is_empty(), "route is not activated before construction completes")
	var max_days := _maximum_active_days(coordinator)
	coordinator.advance_days(max_days, {}, false)
	var completed_session := coordinator.transport_planning_session_snapshot()
	_check(str(completed_session.get("state", "")) == "materialized", "all jobs automatically materialize the route")
	_check(coordinator.transport.routes.size() == 1, "one route is created automatically without reopening the UI")
	var route: Dictionary = coordinator.transport.routes.values()[0]
	_check(str(route.get("status", "")) == "operational", "automatic route passes topology and activates")
	_check(str(route.get("price_model", "")) == "route_package_v2", "route retains its v2 price model")
	_check(str(route.get("price_provenance", "")) == TransportModesScript.ROUTE_PACKAGE_PRICE_PROVENANCE, "route retains its quote_project provenance")
	_check(int(route.get("route_monthly_maintenance", -1)) == 90, "route retains the quoted monthly result")
	var corrupted_route_snapshot: Dictionary = coordinator.transport.to_dict().duplicate(true)
	var route_id := str(coordinator.transport.routes.keys()[0])
	corrupted_route_snapshot["routes"][route_id]["route_construction_cost"] += 1
	var corrupted_route_validation: Dictionary = coordinator.transport.validate_snapshot(corrupted_route_snapshot)
	_check(not bool(corrupted_route_validation.get("valid", true)) and _issues_have(corrupted_route_validation, "invalid_route_v2_price_parity"), "tampered materialized v2 route pricing fails closed")
	_check(coordinator.transport_incremental_monthly_maintenance() == 90 + 120 + 2 * 42, "incremental maintenance replaces segment rate, excludes station duplicate, and retains depot/fleet detail")
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


func _test_legacy_v1_costs_are_not_recomputed() -> void:
	var fixture_variant: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEGACY_FIXTURE_PATH))
	_check(fixture_variant is Dictionary, "tracked legacy v1 fixture parses as a dictionary")
	if not fixture_variant is Dictionary:
		return
	var fixture: Dictionary = fixture_variant
	var raw_transport: Dictionary = fixture.get("state", {}).get("metadata", {}).get("vertical_slice", {}).get("transport", {})
	var raw_project: Dictionary = raw_transport.get("projects", {}).get("transport_project_000001", {})
	var raw_quote: Dictionary = raw_project.get("quote", {})
	_check(not raw_quote.has("maintenance_breakdown"), "pre-v2 fixture does not contain the v2 maintenance breakdown")
	_check(not raw_quote.has("monthly_maintenance"), "pre-v2 fixture does not contain the v2 aggregate quote maintenance")
	var coordinator = CoordinatorScript.new(20_260_905, 50_000)
	_check(coordinator.load_game(LEGACY_FIXTURE_PATH), "tracked legacy v1 save fixture loads")
	if coordinator.transport.segments.is_empty():
		_check(false, "tracked legacy v1 save fixture contains no transport segment")
		return
	var segment_id := str(coordinator.transport.segments.keys()[0])
	var legacy_segment: Dictionary = coordinator.transport.segments[segment_id]
	_check(str(legacy_segment.get("price_model", "")) == "route_package_v1", "tracked fixture is a historical v1 segment")
	_check(int(legacy_segment.get("route_construction_cost", -1)) == 12_345, "tracked fixture exposes its historical construction cost")
	_check(int(legacy_segment.get("route_monthly_maintenance", -1)) == 777, "tracked fixture exposes its historical maintenance")
	_check(coordinator.transport.monthly_maintenance() == 777, "loaded v1 segment keeps its historical maintenance rather than recomputing")
	var first_loaded_transport: Dictionary = coordinator.transport.to_dict()
	_check(_same_shape(raw_transport, first_loaded_transport), "first load preserves the pre-v2 transport key shape")
	var first_loaded_quote: Dictionary = first_loaded_transport.get("projects", {}).get("transport_project_000001", {}).get("quote", {})
	_check(not first_loaded_quote.has("maintenance_breakdown") and not first_loaded_quote.has("monthly_maintenance"), "first load does not silently inject v2 quote fields")
	_check(coordinator.save_game(LEGACY_SAVE_PATH) == OK, "loaded legacy v1 fixture saves without migration")
	var restored = CoordinatorScript.new(1, 1)
	_check(restored.load_game(LEGACY_SAVE_PATH), "legacy v1 fixture reloads after save")
	var restored_segment: Dictionary = restored.transport.segments.get(segment_id, {})
	_check(str(restored_segment.get("price_model", "")) == "route_package_v1", "legacy v1 price model survives save/load")
	_check(int(restored_segment.get("route_construction_cost", -1)) == 12_345, "legacy v1 construction cost survives save/load without rewriting")
	_check(int(restored_segment.get("route_monthly_maintenance", -1)) == 777, "legacy v1 maintenance survives save/load without rewriting")
	_check(restored.transport.monthly_maintenance() == 777, "legacy v1 loaded authority still uses its stored maintenance")
	_check(restored.transport.to_dict() == coordinator.transport.to_dict(), "legacy v1 transport authority round-trips without shape drift")


func _same_shape(left: Variant, right: Variant) -> bool:
	if left is Dictionary:
		if not right is Dictionary or (left as Dictionary).size() != (right as Dictionary).size():
			return false
		for key: Variant in (left as Dictionary).keys():
			if not (right as Dictionary).has(key) or not _same_shape((left as Dictionary)[key], (right as Dictionary)[key]):
				return false
		return true
	if left is Array:
		if not right is Array or (left as Array).size() != (right as Array).size():
			return false
		for index: int in (left as Array).size():
			if not _same_shape((left as Array)[index], (right as Array)[index]):
				return false
		return true
	return true


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


func _first_v2_project_id(snapshot: Dictionary) -> String:
	for project_id_variant: Variant in Dictionary(snapshot.get("projects", {})).keys():
		var project: Dictionary = snapshot["projects"][project_id_variant]
		for segment_value: Variant in Dictionary(project.get("plan", {})).get("segments", []):
			if segment_value is Dictionary and str((segment_value as Dictionary).get("price_model", "")) == "route_package_v2":
				return str(project_id_variant)
	return ""


func _issues_have(result: Dictionary, token: String) -> bool:
	for issue_variant: Variant in result.get("issues", []):
		if str(issue_variant).contains(token):
			return true
	return false


func _negative_ledger_count(coordinator) -> int:
	var result := 0
	for entry: Dictionary in coordinator.session.state.ledger.get_entries():
		if int(entry.get("amount", 0)) < 0:
			result += 1
	return result


func _cleanup() -> void:
	for path: String in [SAVE_PATH, "%s.bak" % SAVE_PATH, "%s.tmp" % SAVE_PATH, LEGACY_SAVE_PATH, "%s.bak" % LEGACY_SAVE_PATH, "%s.tmp" % LEGACY_SAVE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Transport route package atomicity test failed: %s" % label)
