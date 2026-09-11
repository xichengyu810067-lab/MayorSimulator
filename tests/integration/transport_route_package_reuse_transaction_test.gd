extends SceneTree

const CoordinatorScript = preload("res://scripts/app/vertical_slice_coordinator.gd")
const CityTerrainMapScript = preload("res://scripts/world/city_terrain_map.gd")
const TransportPlanningSessionScript = preload("res://scripts/systems/city/transport_planning_session.gd")
const TransportModesScript = preload("res://data/catalogs/transport_modes.gd")

const SAVE_PATH := "user://r5c_transport_reuse_transaction.json"

var _failed := false
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	_test_all_reuse_commits_without_duplicate_work()
	_test_mixed_commits_only_new_runs_and_round_trips()
	_test_stale_tampered_changed_and_future_quotes_are_zero_write()
	_test_candidate_failure_and_cancel_rollback_are_atomic()
	_cleanup()
	if not _failed:
		print("Transport route package reuse transaction test passed. Checks=%d" % _checks)
	quit(1 if _failed else 0)


func _test_all_reuse_commits_without_duplicate_work() -> void:
	var fixture := _prepared_fixture(true)
	var coordinator = fixture["coordinator"]
	var grid: Array = fixture["grid"]
	var route_tiles: Array = fixture["route_tiles"]
	var existing_segment: Dictionary = fixture["existing_segment"].duplicate(true)
	var before_projects: int = int(coordinator.transport.projects.size())
	var before_jobs: int = int(coordinator.construction.jobs.size())
	var before_segments: int = int(coordinator.transport.segments.size())
	var before_balance: int = int(coordinator.treasury_balance())
	var quote: Dictionary = coordinator.transport_session_package_quote(grid)
	_check(bool(quote.get("ok", false)), "all-reuse quote succeeds: %s" % [quote])
	_check(str(quote.get("price_model", "")) == TransportModesScript.ROUTE_PACKAGE_REUSE_PRICE_MODEL, "all-reuse quote uses v3")
	_check(str(Dictionary(quote.get("corridor_contract", {})).get("classification", "")) == "all_reuse", "all-reuse corridor is classified exactly")
	_check(int(quote.get("route_construction_cost", -1)) == 0 and int(quote.get("route_monthly_maintenance", -1)) == 0, "all-reuse corridor charges no duplicate construction or segment maintenance")
	_check(Array(Dictionary(quote.get("route_project_plan", {})).get("segments", [])).is_empty(), "all-reuse corridor schedules no new run")
	var started: Dictionary = coordinator.start_transport_session_package(grid)
	_check(bool(started.get("ok", false)), "all-reuse package commits: %s" % [started])
	_check(not Dictionary(started.get("route", {})).is_empty(), "all-reuse package materializes immediately")
	_check(coordinator.transport.projects.size() == before_projects and coordinator.construction.jobs.size() == before_jobs, "all-reuse package creates no duplicate project or job")
	_check(coordinator.transport.segments.size() == before_segments and coordinator.transport.segments.get(existing_segment.get("id", ""), {}) == existing_segment, "all-reuse package preserves the exact completed segment")
	_check(coordinator.treasury_balance() == before_balance, "all-reuse package does not debit treasury")
	var route: Dictionary = coordinator.transport.routes.values()[0]
	_check(Array(route.get("reused_segment_refs", [])) == Array(Dictionary(quote.get("corridor_contract", {})).get("reused_segment_refs", [])), "all-reuse route persists exact ordered reused refs")
	_check(Array(route.get("new_segment_refs", [])).is_empty() and Array(route.get("new_project_ids", [])).is_empty() and Array(route.get("new_job_ids", [])).is_empty(), "all-reuse route persists empty new-work manifests")
	_check(not Dictionary(Dictionary(route.get("corridor_quote", {})).get("corridor", {})).is_empty(), "all-reuse route persists its checksummed corridor quote")
	_check(Array(Dictionary(quote.get("corridor_contract", {})).get("route_tile_ids", [])) == route_tiles, "all-reuse quote retains the ordered route tiles")
	_validate_current(coordinator, "all-reuse materialized")
	_check(coordinator.save_game(SAVE_PATH) == OK, "all-reuse route saves")
	_validate_saved_transport(SAVE_PATH, "all-reuse serialized")
	var restored = CoordinatorScript.new(1, 1)
	_check(restored.load_game(SAVE_PATH), "all-reuse route reloads: %s" % restored.session.save_service.last_error_message)
	_check(restored.transport.to_dict() == coordinator.transport.to_dict(), "all-reuse transport round-trips exactly: %s" % _first_difference(coordinator.transport.to_dict(), restored.transport.to_dict()))
	_check(restored.transport_planning_session.to_dict() == coordinator.transport_planning_session.to_dict(), "all-reuse session round-trips exactly: %s" % _first_difference(coordinator.transport_planning_session.to_dict(), restored.transport_planning_session.to_dict()))


func _test_mixed_commits_only_new_runs_and_round_trips() -> void:
	var fixture := _prepared_fixture(false)
	var coordinator = fixture["coordinator"]
	var grid: Array = fixture["grid"]
	var existing_segment: Dictionary = fixture["existing_segment"].duplicate(true)
	var before_project_ids: Array = coordinator.transport.projects.keys().duplicate()
	var before_job_ids: Array = coordinator.construction.jobs.keys().duplicate()
	var before_segment_ids: Array = coordinator.transport.segments.keys().duplicate()
	var quote: Dictionary = coordinator.transport_session_package_quote(grid)
	_check(bool(quote.get("ok", false)), "mixed quote succeeds: %s" % [quote])
	var contract: Dictionary = quote.get("corridor_contract", {})
	_check(str(contract.get("classification", "")) == "mixed", "mixed corridor is classified exactly")
	_check(Array(contract.get("reused_segment_refs", [])).size() == 1 and Array(contract.get("new_runs", [])).size() == 2, "mixed corridor contains one reused ref and two ordered new runs")
	_check(int(quote.get("route_construction_cost", -1)) == 2_080 and int(quote.get("route_monthly_maintenance", -1)) == 72, "mixed quote accounts only for four new road cells")
	var started: Dictionary = coordinator.start_transport_session_package(grid)
	_check(bool(started.get("ok", false)), "mixed package commits: %s" % [started])
	if not bool(started.get("ok", false)):
		return
	var package_quote: Dictionary = coordinator.transport_planning_session_snapshot().get("route_draft", {}).get("package_quote", {})
	_check(Array(package_quote.get("reused_segment_refs", [])) == Array(contract.get("reused_segment_refs", [])), "mixed session persists exact ordered reused refs")
	_check(Array(package_quote.get("new_segment_refs", [])).size() == 2, "mixed session persists the two new segment refs")
	_check(Array(package_quote.get("new_project_ids", [])).size() == 1 and Array(package_quote.get("new_job_ids", [])).size() == 1, "mixed session creates one corridor project and job")
	_check(coordinator.transport.projects.size() == before_project_ids.size() + 1 and coordinator.construction.jobs.size() == before_job_ids.size() + 1, "mixed start creates only its new-run project and job")
	_check(coordinator.transport.segments.keys() == before_segment_ids and coordinator.transport.segments.get(existing_segment.get("id", ""), {}) == existing_segment, "mixed start does not rewrite completed topology")
	coordinator.advance_days(_maximum_active_days(coordinator), {}, false)
	_check(coordinator.transport.routes.size() == 1, "mixed completion materializes one route")
	_check(coordinator.transport.segments.size() == before_segment_ids.size() + 2, "mixed completion materializes only the two new runs")
	_check(coordinator.transport.segments.get(existing_segment.get("id", ""), {}) == existing_segment, "mixed completion preserves the reused segment byte-for-byte")
	var route: Dictionary = coordinator.transport.routes.values()[0]
	_check(Array(route.get("reused_segment_refs", [])) == Array(contract.get("reused_segment_refs", [])), "mixed route persists exact reused refs")
	_check(Array(route.get("new_segment_refs", [])).size() == 2 and Array(route.get("new_project_ids", [])).size() == 1 and Array(route.get("new_job_ids", [])).size() == 1, "mixed route persists exact new-work manifests")
	_check(Dictionary(route.get("price_breakdown", {})) == Dictionary(quote.get("corridor_quote", {}).get("price_breakdown", {})) and Dictionary(route.get("maintenance_breakdown", {})) == Dictionary(quote.get("corridor_quote", {}).get("maintenance_breakdown", {})), "mixed route persists pricing breakdowns without recomputation")
	_validate_current(coordinator, "mixed materialized")
	_check(coordinator.save_game(SAVE_PATH) == OK, "mixed route saves")
	_validate_saved_transport(SAVE_PATH, "mixed serialized")
	var restored = CoordinatorScript.new(1, 1)
	_check(restored.load_game(SAVE_PATH), "mixed route reloads: %s" % restored.session.save_service.last_error_message)
	_check(restored.transport.to_dict() == coordinator.transport.to_dict(), "mixed transport round-trips exactly: %s" % _first_difference(coordinator.transport.to_dict(), restored.transport.to_dict()))
	_check(restored.transport_planning_session.to_dict() == coordinator.transport_planning_session.to_dict(), "mixed session round-trips exactly: %s" % _first_difference(coordinator.transport_planning_session.to_dict(), restored.transport_planning_session.to_dict()))


func _test_stale_tampered_changed_and_future_quotes_are_zero_write() -> void:
	var fixture := _prepared_fixture(false)
	var coordinator = fixture["coordinator"]
	var grid: Array = fixture["grid"]
	coordinator.transport_session_package_quote(grid)
	coordinator.transport.next_route_sequence += 1
	_assert_rejected_start_is_zero_write(coordinator, grid, "transport_package_quote_stale", "network revision changed after quote")

	fixture = _prepared_fixture(false)
	coordinator = fixture["coordinator"]
	grid = fixture["grid"]
	coordinator.transport_session_package_quote(grid)
	coordinator.transport_planning_session.session["route_draft"]["corridor_quote"]["total_cost"] += 1
	_assert_rejected_start_is_zero_write(coordinator, grid, "transport_package_cached_quote_invalid", "tampered quote checksum")

	fixture = _prepared_fixture(false)
	coordinator = fixture["coordinator"]
	grid = fixture["grid"]
	coordinator.transport_session_package_quote(grid)
	var segment_id := str(fixture["existing_segment"].get("id", ""))
	coordinator.transport.segments[segment_id]["status"] = "removed"
	_assert_rejected_start_is_zero_write(coordinator, grid, "invalid_transport_network_snapshot", "reused segment status changed")

	fixture = _prepared_fixture(false)
	coordinator = fixture["coordinator"]
	grid = fixture["grid"]
	coordinator.transport_session_package_quote(grid)
	segment_id = str(fixture["existing_segment"].get("id", ""))
	coordinator.transport.segments.erase(segment_id)
	_assert_rejected_start_is_zero_write(coordinator, grid, "invalid_transport_network_snapshot", "reused segment missing")

	fixture = _prepared_fixture(false)
	coordinator = fixture["coordinator"]
	grid = fixture["grid"]
	coordinator.transport_session_package_quote(grid)
	segment_id = str(fixture["existing_segment"].get("id", ""))
	coordinator.transport.segments[segment_id]["tile_path"] = [fixture["route_tiles"][1]]
	_assert_rejected_start_is_zero_write(coordinator, grid, "invalid_transport_network_snapshot", "reused segment path changed")

	fixture = _prepared_fixture(false)
	coordinator = fixture["coordinator"]
	grid = fixture["grid"]
	coordinator.transport_session_package_quote(grid)
	coordinator.transport_planning_session.session["route_draft"]["corridor_quote"]["quote_schema_version"] = 999
	_assert_rejected_start_is_zero_write(coordinator, grid, "transport_package_cached_quote_invalid", "future quote schema")


func _test_candidate_failure_and_cancel_rollback_are_atomic() -> void:
	var fixture := _prepared_fixture(false)
	var coordinator = fixture["coordinator"]
	var grid: Array = fixture["grid"]
	coordinator.transport_session_package_quote(grid)
	var before: Dictionary = _authority_snapshot(coordinator)
	var injected: Dictionary = coordinator.start_transport_session_package(grid, "after_first_candidate_project")
	_check(str(injected.get("error", "")) == "transport_package_injected_candidate_failure", "candidate mid-failure is injected after new work begins")
	_check(_authority_snapshot(coordinator) == before, "candidate mid-failure leaves every live authority unchanged")

	fixture = _prepared_fixture(false)
	coordinator = fixture["coordinator"]
	grid = fixture["grid"]
	var existing_segment: Dictionary = fixture["existing_segment"].duplicate(true)
	var original: Dictionary = _authority_snapshot(coordinator)
	var quote: Dictionary = coordinator.transport_session_package_quote(grid)
	var started: Dictionary = coordinator.start_transport_session_package(grid)
	_check(bool(started.get("ok", false)), "rollback fixture starts")
	var cancelled: Dictionary = coordinator.cancel_transport_planning_session()
	_check(bool(cancelled.get("ok", false)), "active mixed package rolls back atomically: %s" % [cancelled])
	_check(int(cancelled.get("refunded_cost", -1)) == int(quote.get("total_cost", -2)), "rollback refunds exactly the committed package cost")
	_check(coordinator.treasury_balance() == int(original.get("balance", -1)), "rollback restores treasury")
	_check(coordinator.construction.jobs == Dictionary(original.get("construction", {})).get("jobs", {}), "rollback removes only current package jobs")
	var original_transport: Dictionary = original.get("transport", {})
	_check(
		coordinator.transport.projects == Dictionary(original_transport.get("projects", {}))
		and coordinator.transport.segments == Dictionary(original_transport.get("segments", {}))
		and coordinator.transport.facilities == Dictionary(original_transport.get("facilities", {}))
		and coordinator.transport.routes == Dictionary(original_transport.get("routes", {})),
		"rollback removes only current package projects and leaves topology exact"
	)
	_check(coordinator.transport.segments.get(existing_segment.get("id", ""), {}) == existing_segment, "rollback never edits the reused segment")
	_check(str(coordinator.transport_planning_session_snapshot().get("state", "")) == "closed", "rollback closes the package session")
	_validate_current(coordinator, "rolled back")
	_check(coordinator.save_game(SAVE_PATH) == OK, "rolled-back package saves")
	_validate_saved_transport(SAVE_PATH, "rollback serialized")
	var restored = CoordinatorScript.new(1, 1)
	_check(restored.load_game(SAVE_PATH), "rolled-back package reloads: %s" % restored.session.save_service.last_error_message)
	_check(restored.transport.to_dict() == coordinator.transport.to_dict() and restored.construction.to_dict() == coordinator.construction.to_dict(), "rolled-back authorities survive save/load")

	fixture = _prepared_all_new_fixture()
	coordinator = fixture["coordinator"]
	grid = fixture["grid"]
	quote = coordinator.transport_session_package_quote(grid)
	original = _authority_snapshot(coordinator)
	started = coordinator.start_transport_session_package(grid)
	_check(bool(started.get("ok", false)) and Array(started.get("jobs", [])).size() == 4, "all-new rollback fixture commits two stations, one corridor and one depot job")
	cancelled = coordinator.cancel_transport_planning_session()
	_check(bool(cancelled.get("ok", false)) and Array(cancelled.get("rolled_back_job_ids", [])).size() == 4, "all-new rollback removes every current package job")
	_check(coordinator.treasury_balance() == int(original.get("balance", -1)), "all-new rollback restores treasury")
	_check(coordinator.construction.jobs == Dictionary(original.get("construction", {})).get("jobs", {}), "all-new rollback leaves no package construction job")
	_check(coordinator.transport.projects == Dictionary(original.get("transport", {})).get("projects", {}) and coordinator.transport.segments == Dictionary(original.get("transport", {})).get("segments", {}) and coordinator.transport.facilities == Dictionary(original.get("transport", {})).get("facilities", {}), "all-new rollback leaves no package transport project or entity")
	_check(coordinator.blueprint_library_service.snapshot() == original.get("blueprints", {}), "all-new rollback restores blueprint usage counters")

	fixture = _prepared_all_new_fixture()
	coordinator = fixture["coordinator"]
	grid = fixture["grid"]
	coordinator.transport_session_package_quote(grid)
	original = _authority_snapshot(coordinator)
	started = coordinator.start_transport_session_package(grid)
	var first_station_job_id := str(coordinator.transport_planning_session_snapshot().get("station_refs", [])[0].get("job_id", ""))
	_check(bool(started.get("ok", false)) and not first_station_job_id.is_empty(), "partial-completion rollback fixture starts")
	if not first_station_job_id.is_empty():
		coordinator.construction.jobs[first_station_job_id]["remaining_work"] = 0.0
		coordinator.advance_days(1, {}, false)
		_check(str(coordinator.transport_planning_session_snapshot().get("station_refs", [])[0].get("status", "")) == "completed", "one current-package station completes before cancellation")
		cancelled = coordinator.cancel_transport_planning_session()
		_check(bool(cancelled.get("ok", false)), "partial-completion cancellation rolls back completed and active package work: %s" % [cancelled])
		_check(coordinator.session.state.buildings == Dictionary(original.get("core", {})).get("state", {}).get("buildings", {}), "partial-completion rollback removes only the newly completed station building")
		_check(coordinator.construction.jobs == Dictionary(original.get("construction", {})).get("jobs", {}), "partial-completion rollback removes remaining and completed package jobs")
		_check(coordinator.transport.projects == Dictionary(original.get("transport", {})).get("projects", {}) and coordinator.transport.segments == Dictionary(original.get("transport", {})).get("segments", {}) and coordinator.transport.facilities == Dictionary(original.get("transport", {})).get("facilities", {}) and coordinator.transport.stations == Dictionary(original.get("transport", {})).get("stations", {}), "partial-completion rollback removes only current package transport entities")


func _prepared_fixture(all_reuse: bool) -> Dictionary:
	var coordinator = CoordinatorScript.new(20_260_911 + _checks, 3_000_000)
	coordinator.terrain_map = CityTerrainMapScript.new()
	var grid := _empty_grid()
	var station_a_tile := _tile(coordinator, 2, 3)
	var station_b_tile := _tile(coordinator, 6, 3)
	var route_tiles := _horizontal_tiles(coordinator, 2, 6, 4)
	var reused_tiles: Array = route_tiles if all_reuse else [route_tiles[2]]
	var road_project := _complete_transport_project(coordinator, "road", {
		"segments": [{"kind": "road", "tile_path": reused_tiles}],
		"facilities": [],
		"stations": [],
	})
	_check(bool(road_project.get("ok", false)), "fixture completes reusable road")
	var depot_tile := _tile(coordinator, 4, 5)
	var depot_project := _complete_transport_project(coordinator, "bus_depot", {
		"segments": [],
		"facilities": [{"kind": "bus_depot", "tile_id": depot_tile}],
		"stations": [],
	})
	_check(bool(depot_project.get("ok", false)), "fixture completes connected bus depot")
	var station_a: Dictionary = coordinator.register_existing_building(station_a_tile, "公車站")
	var station_b: Dictionary = coordinator.register_existing_building(station_b_tile, "公車站")
	_check(not station_a.is_empty() and not station_b.is_empty(), "fixture registers completed stations")
	coordinator.begin_transport_planning_session("公車站", TransportPlanningSessionScript.WORKFLOW_ROUTE_PACKAGE_V1)
	coordinator.reuse_transport_session_station(station_a_tile)
	coordinator.reuse_transport_session_station(station_b_tile)
	coordinator.begin_transport_session_network_placement("road", {})
	coordinator.draft_transport_session_network("road", route_tiles, 5)
	coordinator.begin_transport_session_route_edit({"fleet_size": 2, "headway_minutes": 8, "fare": 25})
	var existing_segment: Dictionary = coordinator.transport.segments.values()[0]
	return {
		"coordinator": coordinator,
		"grid": grid,
		"route_tiles": route_tiles,
		"existing_segment": existing_segment,
	}


func _prepared_all_new_fixture() -> Dictionary:
	var coordinator = CoordinatorScript.new(20_261_911 + _checks, 3_000_000)
	coordinator.terrain_map = CityTerrainMapScript.new()
	var grid := _empty_grid()
	var station_a_tile := _tile(coordinator, 2, 3)
	var station_b_tile := _tile(coordinator, 6, 3)
	var route_tiles := _horizontal_tiles(coordinator, 2, 6, 4)
	coordinator.begin_transport_planning_session("公車站", TransportPlanningSessionScript.WORKFLOW_ROUTE_PACKAGE_V1)
	coordinator.draft_transport_session_station(station_a_tile, 5)
	coordinator.draft_transport_session_station(station_b_tile, 5)
	coordinator.begin_transport_session_network_placement("road", {})
	coordinator.draft_transport_session_network("road", route_tiles, 5)
	coordinator.begin_transport_session_route_edit({"fleet_size": 2, "headway_minutes": 8, "fare": 25})
	return {"coordinator": coordinator, "grid": grid}


func _complete_transport_project(coordinator, kind: String, plan: Dictionary) -> Dictionary:
	var planned: Dictionary = coordinator.transport.plan_project("build", plan, coordinator.terrain_map, [], [])
	if not bool(planned.get("ok", false)):
		return planned
	var project_id := str(planned.get("project", {}).get("id", ""))
	var started: Dictionary = coordinator.transport.start_project(project_id)
	if not bool(started.get("ok", false)):
		return started
	return coordinator.transport.complete_project(project_id)


func _assert_rejected_start_is_zero_write(coordinator, grid: Array, expected_error: String, label: String) -> void:
	var before: Dictionary = _authority_snapshot(coordinator)
	var result: Dictionary = coordinator.start_transport_session_package(grid)
	_check(str(result.get("error", "")) == expected_error, "%s fails closed with %s: %s" % [label, expected_error, result])
	_check(_authority_snapshot(coordinator) == before, "%s applies zero additional state" % label)


func _authority_snapshot(coordinator) -> Dictionary:
	return {
		"balance": coordinator.treasury_balance(),
		"core": coordinator.session.make_envelope().to_dict(),
		"construction": coordinator.construction.to_dict(),
		"transport": coordinator.transport.to_dict(),
		"planning": coordinator.transport_planning_session.to_dict(),
		"blueprints": coordinator.blueprint_library_service.snapshot(),
		"operation_sequence": coordinator.next_operation_sequence,
	}


func _validate_current(coordinator, label: String) -> void:
	var transport_validation: Dictionary = coordinator.transport.validate_snapshot(coordinator.transport.to_dict())
	_check(bool(transport_validation.get("valid", false)), "%s transport snapshot validates: %s" % [label, transport_validation])
	var planning_validation: Dictionary = TransportPlanningSessionScript.validate_snapshot(coordinator.transport_planning_session.to_dict())
	_check(bool(planning_validation.get("valid", false)), "%s planning snapshot validates: %s" % [label, planning_validation])
	var reference_validation: Dictionary = TransportPlanningSessionScript.validate_references(
		coordinator.transport_planning_session.to_dict(),
		coordinator.construction.to_dict(),
		coordinator.transport.to_dict(),
		coordinator.session.state.buildings
	)
	_check(bool(reference_validation.get("valid", false)), "%s references validate: %s" % [label, reference_validation])


func _validate_saved_transport(path: String, label: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(parsed is Dictionary, "%s save parses" % label)
	if not parsed is Dictionary:
		return
	var state: Dictionary = parsed.get("state", {})
	var vertical: Dictionary = state.get("metadata", {}).get("vertical_slice", {})
	var transport_snapshot: Dictionary = vertical.get("transport", {})
	var planning_snapshot: Dictionary = vertical.get("transport_planning_session", {})
	var transport_validation: Dictionary = coordinator_transport_validation(transport_snapshot)
	_check(bool(transport_validation.get("valid", false)), "%s transport validates: %s" % [label, transport_validation])
	var planning_validation: Dictionary = TransportPlanningSessionScript.validate_snapshot(planning_snapshot)
	_check(bool(planning_validation.get("valid", false)), "%s planning validates: %s" % [label, planning_validation])
	var reference_validation: Dictionary = TransportPlanningSessionScript.validate_references(
		planning_snapshot,
		vertical.get("construction", {}),
		transport_snapshot,
		state.get("buildings", {})
	)
	_check(bool(reference_validation.get("valid", false)), "%s references validate: %s" % [label, reference_validation])


func coordinator_transport_validation(snapshot: Dictionary) -> Dictionary:
	return CoordinatorScript.new(1, 1).transport.validate_snapshot(snapshot)


func _first_difference(left: Variant, right: Variant, path: String = "root") -> String:
	if typeof(left) != typeof(right):
		return "%s type %d != %d (%s != %s)" % [path, typeof(left), typeof(right), left, right]
	if left is Dictionary:
		if (left as Dictionary).keys() != (right as Dictionary).keys():
			return "%s keys %s != %s" % [path, (left as Dictionary).keys(), (right as Dictionary).keys()]
		for key: Variant in (left as Dictionary).keys():
			var nested := _first_difference((left as Dictionary)[key], (right as Dictionary)[key], "%s.%s" % [path, key])
			if not nested.is_empty():
				return nested
		return ""
	if left is Array:
		if (left as Array).size() != (right as Array).size():
			return "%s size %d != %d" % [path, (left as Array).size(), (right as Array).size()]
		for index: int in range((left as Array).size()):
			var nested := _first_difference((left as Array)[index], (right as Array)[index], "%s[%d]" % [path, index])
			if not nested.is_empty():
				return nested
		return ""
	return "" if left == right else "%s %s != %s" % [path, left, right]


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


func _cleanup() -> void:
	for path: String in [SAVE_PATH, "%s.bak" % SAVE_PATH, "%s.tmp" % SAVE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Transport route package reuse transaction test failed: %s" % label)
