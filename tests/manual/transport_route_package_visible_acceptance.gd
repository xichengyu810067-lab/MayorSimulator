extends SceneTree

const OUTPUT_PREFIX := "--transport-route-package-output-dir="
const RESULT_FILENAME := "transport-route-package-result.json"
const SAVE_PATH := "user://mayor_simulator/tests/transport_route_package_visible_acceptance.json"
const MODE_SCOPE_CAPTURE := "transport-route-package-bus-only-native.png"
const ROUTE_MAP_CAPTURE := "transport-route-package-route-map-native.png"
const DRAFT_CAPTURE := "transport-route-package-draft-native.png"
const CONSTRUCTION_CAPTURE := "transport-route-package-construction-native.png"
const OPERATIONAL_CAPTURE := "transport-route-package-operational-native.png"
const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")

var output_dir := ""
var failed := false
var main


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(OUTPUT_PREFIX):
			output_dir = argument.trim_prefix(OUTPUT_PREFIX)
	if output_dir.is_empty() or not DirAccess.dir_exists_absolute(output_dir):
		_fail("missing existing --transport-route-package-output-dir")
		return
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name().to_lower() == "headless":
		_fail("native acceptance requires a Windows display driver")
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	await _settle(12)
	if DisplayServer.window_get_mode() not in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]:
		_fail("native window did not enter fullscreen mode")
		return
	var packed := load("res://scenes/Main.tscn") as PackedScene
	if packed == null:
		_fail("Main.tscn could not be loaded")
		return
	main = packed.instantiate()
	main.start_save_path = SAVE_PATH
	root.add_child(main)
	await _settle(12)
	if main.get_parent() != root:
		_fail("actual Main is not attached directly to the native root Window")
		return
	main.start_screen.animation_duration = 0.04
	main.start_screen.new_game_button.emit_signal("pressed")
	for _frame in range(180):
		if main._game_started and not main.start_screen.visible:
			break
		await process_frame
	if not main._game_started or main.start_screen.visible:
		_fail("new game did not reach the actual Main map")
		return
	if main.tutorial_overlay != null and main.tutorial_overlay.is_open():
		main.tutorial_overlay.skip_button.emit_signal("pressed")
		await _settle(6)
	main.vertical_slice.set_time_paused(true)

	main.municipal_overlay.open_page("buildings")
	main._select_building_group("mobility")
	await _settle(6)
	var station_card := main.municipal_overlay.find_child("BuildingCard_公車站", true, false) as Button
	if station_card == null or not station_card.is_visible_in_tree():
		_fail("actual Main mobility page does not expose the bus-station card")
		return
	station_card.pressed.emit()
	await _settle(6)
	var station_action := main.vertical_slice_panel.find_child("SubmitBlueprintButton", true, false) as Button
	if station_action == null or station_action.disabled or not station_action.text.contains("連續站點"):
		_fail("actual Main approved bus-station blueprint lacks continuous planning")
		return
	var fixture := _find_eleven_tile_fixture()
	if fixture.is_empty():
		_fail("could not find a visible buildable 11-tile L-turn bus package fixture")
		return
	var existing_building_tile := _find_existing_building_tile(fixture)
	if existing_building_tile < 0:
		_fail("could not find an independent existing-building visibility fixture")
		return
	main.city_grid[existing_building_tile] = "住宅"
	main.building_customizations[existing_building_tile] = {"variant": 1, "roof": 2, "wall": 3}
	var building_record: Dictionary = main.vertical_slice.register_existing_building(
		existing_building_tile,
		"住宅",
		main.building_customizations[existing_building_tile]
	)
	main._update_tile_visual(existing_building_tile, "住宅")
	await _settle(3)
	if building_record.is_empty():
		_fail("actual Main could not register the existing-building visibility fixture")
		return

	var funds_before := int(main.vertical_slice.treasury_balance())
	var jobs_before: Dictionary = main.vertical_slice.construction.to_dict()
	var network_before: Dictionary = main.vertical_slice.transport.to_dict()
	var city_grid_before: Array = main.city_grid.duplicate()
	var negative_ledger_before := _negative_ledger_count()
	station_action.pressed.emit()
	await _settle(4)
	var session: Dictionary = main.vertical_slice.transport_planning_session_snapshot()
	if str(session.get("workflow", "")) != "route_package_v1" or str(session.get("state", "")) != "station_placement":
		_fail("actual Main did not start route_package_v1 station placement")
		return
	for station_tile: int in [int(fixture["station_a"]), int(fixture["station_b"])]:
		main._on_grid_pressed(station_tile)
		await _settle(2)
	session = main.vertical_slice.transport_planning_session_snapshot()
	if Array(Dictionary(session.get("route_draft", {})).get("station_placements", [])).size() != 2:
		_fail("actual Main did not retain both station drafts")
		return
	if main.placement_confirm_button == null or main.placement_confirm_button.disabled:
		_fail("station draft phase cannot advance to network planning")
		return
	main.placement_confirm_button.pressed.emit()
	await _settle(6)
	var captures: Array[Dictionary] = []
	var scoped_snapshot: Dictionary = main.transport_planning_panel.debug_snapshot()
	if (
		Array(scoped_snapshot.get("scoped_infrastructure_choice_ids", [])) != ["road", "bus_depot"]
		or Array(scoped_snapshot.get("scoped_route_mode_ids", [])) != ["bus"]
		or main.transport_planning_panel.find_child("InfrastructureAdd_metro_track", true, false) != null
		or main.transport_planning_panel.find_child("PlanRoute_train", true, false) != null
	):
		_fail("active bus session still exposes foreign infrastructure or route cards: %s" % scoped_snapshot)
		return
	var mode_scope_capture := _capture_native(MODE_SCOPE_CAPTURE, "bus_only_choices")
	if mode_scope_capture.is_empty():
		return
	captures.append(mode_scope_capture)
	var road_button := main.transport_planning_panel.find_child("InfrastructureAdd_road", true, false) as Button
	if road_button == null or road_button.disabled:
		_fail("network phase does not expose road planning")
		return
	road_button.pressed.emit()
	await _settle(2)
	for route_tile_value: Variant in fixture["route_tiles"]:
		main._on_grid_pressed(int(route_tile_value))
		await process_frame
	if main.transport_plan_tiles.size() != 11 or main.placement_confirm_button.disabled:
		_fail("actual Main did not retain an enabled 11-tile contiguous route draft: %s" % main.hint_label.text)
		return
	var existing_building_button := main.grid_buttons[existing_building_tile] as Button
	var building_visual: Dictionary = existing_building_button.call("get_visual_animation_debug_snapshot") if existing_building_button != null else {}
	var network_debug: Dictionary = main.transport_network_layer.debug_snapshot()
	var station_draft_ghost_count := 0
	for station_tile: int in [int(fixture["station_a"]), int(fixture["station_b"])]:
		var station_button := main.grid_buttons[station_tile] as Button
		var station_overlay: Dictionary = station_button.call("get_transport_planning_overlay_snapshot") if station_button != null else {}
		if (
			station_button != null
			and station_button.is_visible_in_tree()
			and str(station_overlay.get("kind", "")) == "station_draft"
			and bool(station_overlay.get("non_authoritative", false))
			and main.city_grid[station_tile] == ""
			and main.vertical_slice.get_building_by_tile(station_tile).is_empty()
		):
			station_draft_ghost_count += 1
	var has_l_turn_junction := false
	for junction_variant: Variant in network_debug.get("connected_junctions", []):
		if junction_variant is Dictionary and bool((junction_variant as Dictionary).get("has_perpendicular_turn", false)):
			has_l_turn_junction = true
			break
	if (
		existing_building_button == null
		or not existing_building_button.is_visible_in_tree()
		or str(building_visual.get("building_name", "")) != "住宅"
		or existing_building_button.get_parent() != main.tile_layer
		or main.tile_layer.get_index() <= main.transport_network_layer.get_index()
		or main.npc_layer.get_index() <= main.tile_layer.get_index()
		or station_draft_ghost_count != 2
		or not has_l_turn_junction
	):
		_fail("route map does not preserve the existing building, both non-authoritative station ghosts, layer order, or a continuous L-turn")
		return
	var route_map_capture := _capture_native(ROUTE_MAP_CAPTURE, "building_visible_continuous_l_turn")
	if route_map_capture.is_empty():
		return
	captures.append(route_map_capture)
	main.placement_confirm_button.pressed.emit()
	await _settle(8)
	session = main.vertical_slice.transport_planning_session_snapshot()
	if str(session.get("state", "")) != "route_edit":
		_fail("route draft did not reach the one-screen package confirmation")
		return
	var quote: Dictionary = main.vertical_slice.transport_session_package_quote(main.city_grid)
	if not _validate_draft_quote(quote, funds_before, jobs_before, network_before, city_grid_before, negative_ledger_before):
		return
	var detail := main.transport_planning_panel.find_child("TransportPlanningSessionDetail", true, false) as Label
	var expected_tokens := [
		"站點 $%d" % int(quote.get("station_building_cost", -1)),
		"路線 11 格 $11020",
		"總工程費 $%d" % int(quote.get("total_cost", -1)),
		"路線月維護 $3306",
	]
	if detail == null or not detail.is_visible_in_tree():
		_fail("package confirmation detail is not visible")
		return
	for token: String in expected_tokens:
		if not detail.text.contains(token):
			_fail("package confirmation detail is missing '%s': %s" % [token, detail.text])
			return
	var draft_capture := _capture_native(DRAFT_CAPTURE, "unconfirmed_draft")
	if draft_capture.is_empty():
		return
	captures.append(draft_capture)

	var continue_button := main.transport_planning_panel.find_child("TransportPlanningSessionContinue", true, false) as Button
	if continue_button == null or continue_button.disabled or not continue_button.text.contains("確認總包"):
		_fail("package confirmation button is not enabled")
		return
	continue_button.pressed.emit()
	await _settle(8)
	var construction_session: Dictionary = main.vertical_slice.transport_planning_session_snapshot()
	var relevant_jobs := _new_active_jobs(jobs_before)
	var job_durations := _job_duration_records(relevant_jobs)
	if (
		str(construction_session.get("state", "")) != "waiting_construction"
		or _negative_ledger_count() - negative_ledger_before != 1
		or funds_before - int(main.vertical_slice.treasury_balance()) != int(quote.get("total_cost", -1))
		or relevant_jobs.is_empty()
		or job_durations.size() != relevant_jobs.size()
		or not main.vertical_slice.transport.active_lines().is_empty()
	):
		_fail("single-confirm construction contract failed: session=%s jobs=%s quote=%s" % [construction_session, relevant_jobs, quote])
		return
	var funds_debit_after_confirmation := funds_before - int(main.vertical_slice.treasury_balance())
	var ledger_delta_after_confirmation := _negative_ledger_count() - negative_ledger_before
	main._open_transport_planning()
	main._refresh_transport_planning_panel()
	await _settle(8)
	var construction_capture := _capture_native(CONSTRUCTION_CAPTURE, "construction_started")
	if construction_capture.is_empty():
		return
	captures.append(construction_capture)

	var maximum_days := 0
	for job_value: Variant in relevant_jobs:
		if job_value is Dictionary:
			maximum_days = maxi(maximum_days, int((job_value as Dictionary).get("projected_remaining_days", 0)))
	if maximum_days <= 0:
		_fail("package jobs do not expose positive ConstructionSystem durations")
		return
	var completion_events: Array[Dictionary] = main.vertical_slice.advance_days(maximum_days, {}, false)
	main._consume_vertical_events(completion_events)
	main._sync_vertical_state()
	main._update_ui()
	main._open_transport_planning()
	main._refresh_transport_planning_panel()
	await _settle(12)
	var final_session: Dictionary = main.vertical_slice.transport_planning_session_snapshot()
	var route_refs: Array = final_session.get("route_refs", [])
	if str(final_session.get("state", "")) != "materialized" or route_refs.size() != 1:
		_fail("package did not automatically materialize after its existing jobs completed: %s" % final_session)
		return
	var route_id := str(route_refs[0])
	var route: Dictionary = main.vertical_slice.transport.routes.get(route_id, {})
	if str(route.get("status", "")) != "operational" or main.vertical_slice.transport.active_lines().size() != 1:
		_fail("automatically materialized route is not operational: %s" % route)
		return
	if _negative_ledger_count() - negative_ledger_before != 1:
		_fail("completion introduced a second package ledger debit")
		return
	var operational_capture := _capture_native(OPERATIONAL_CAPTURE, "automatically_operational")
	if operational_capture.is_empty():
		return
	captures.append(operational_capture)
	var capture_hashes: Dictionary = {}
	for capture: Dictionary in captures:
		capture_hashes[str(capture.get("sha256", ""))] = true
	if captures.size() != 5 or capture_hashes.size() != 5:
		_fail("the five route-package captures are not distinct")
		return

	var result := {
		"schema_version": 1,
		"suite": "mayor-simulator-transport-route-package-actual-main-native-visible-acceptance",
		"status": "PASS",
		"actual_main": true,
		"scene": "res://scenes/Main.tscn",
		"scene_parent": "root_window",
		"capture_surface_kind": "native_fullscreen_root",
		"source": _source_identity(),
		"display": {
			"server": DisplayServer.get_name(),
			"window_mode": DisplayServer.window_get_mode(),
			"window_size": _v2i(DisplayServer.window_get_size()),
		},
		"pricing": {
			"price_model": str(quote.get("price_model", "")),
			"route_tile_count": int(quote.get("route_tile_count", 0)),
			"long_distance_exponent": 1,
			"route_construction_cost": int(quote.get("route_construction_cost", 0)),
			"route_monthly_maintenance": int(quote.get("route_monthly_maintenance", 0)),
		},
		"quote": {
			"station_building_cost": int(quote.get("station_building_cost", 0)),
			"route_construction_cost": int(quote.get("route_construction_cost", 0)),
			"support_facility_cost": int(quote.get("support_facility_cost", 0)),
			"level_crossing_cost": int(quote.get("level_crossing_cost", 0)),
			"total_cost": int(quote.get("total_cost", 0)),
			"route_monthly_maintenance": int(quote.get("route_monthly_maintenance", 0)),
			"support_monthly_maintenance": int(quote.get("support_monthly_maintenance", 0)),
			"level_crossing_monthly_maintenance": int(quote.get("level_crossing_monthly_maintenance", 0)),
			"total_monthly_maintenance": int(quote.get("total_monthly_maintenance", 0)),
		},
		"draft": {
			"workflow": str(session.get("workflow", "")),
			"station_count": 2,
			"route_tile_ids": Array(fixture["route_tiles"]).duplicate(),
			"funds_delta": 0,
			"construction_unchanged": true,
			"network_unchanged": true,
			"city_grid_unchanged": true,
		},
		"ux_regressions": {
			"session_mode": "bus",
			"visible_infrastructure_choice_ids": scoped_snapshot.get("scoped_infrastructure_choice_ids", []),
			"visible_route_mode_ids": scoped_snapshot.get("scoped_route_mode_ids", []),
			"foreign_mode_cards_absent": true,
			"existing_building_tile_id": existing_building_tile,
			"existing_building_visible_during_route_placement": true,
			"station_draft_ghost_count": station_draft_ghost_count,
			"station_drafts_remain_outside_live_authority": true,
			"building_layer_above_route_preview": true,
			"npc_layer_order_preserved": true,
			"l_turn_route": true,
			"filled_l_turn_junction": has_l_turn_junction,
		},
		"construction": {
			"ledger_negative_entry_delta": ledger_delta_after_confirmation,
			"funds_debit": funds_debit_after_confirmation,
			"quoted_total": int(quote.get("total_cost", 0)),
			"job_count": relevant_jobs.size(),
			"job_durations": job_durations,
			"operational_routes_before_completion": 0,
		},
		"materialized_route": {
			"automatic": true,
			"returned_to_entry": false,
			"route_id": route_id,
			"status": str(route.get("status", "")),
			"price_model": str(route.get("price_model", "")),
			"route_tile_count": int(route.get("route_tile_count", 0)),
		},
		"captures": captures,
	}
	var result_file := FileAccess.open(output_dir.path_join(RESULT_FILENAME), FileAccess.WRITE)
	if result_file == null:
		_fail("failed to open route-package result file")
		return
	result_file.store_string(JSON.stringify(result, "\t"))
	result_file.close()
	print("TRANSPORT_ROUTE_PACKAGE_NATIVE_VISIBLE_ACCEPTANCE_PASSED captures=5 L=11 construction=11020 maintenance=3306 ledger_delta=1 route_status=operational bus_only=true building_visible=true l_turn=true actual_main=true")
	await TestCleanup.finish(self, [main], 0)


func _validate_draft_quote(
	quote: Dictionary,
	funds_before: int,
	jobs_before: Dictionary,
	network_before: Dictionary,
	city_grid_before: Array,
	negative_ledger_before: int
) -> bool:
	if (
		not bool(quote.get("ok", false))
		or str(quote.get("price_model", "")) != "route_package_v1"
		or int(quote.get("route_tile_count", -1)) != 11
		or int(quote.get("route_construction_cost", -1)) != 11_020
		or int(quote.get("route_monthly_maintenance", -1)) != 3_306
		or int(quote.get("total_cost", -1)) != int(quote.get("station_building_cost", 0)) + 11_020 + int(quote.get("support_facility_cost", 0)) + int(quote.get("level_crossing_cost", 0))
		or int(main.vertical_slice.treasury_balance()) != funds_before
		or main.vertical_slice.construction.to_dict() != jobs_before
		or main.vertical_slice.transport.to_dict() != network_before
		or main.city_grid != city_grid_before
		or _negative_ledger_count() != negative_ledger_before
	):
		_fail("unconfirmed draft pricing/zero-write contract failed: %s" % quote)
		return false
	return true


func _find_eleven_tile_fixture() -> Dictionary:
	var terrain = main.vertical_slice.terrain_map
	var size: Vector2i = terrain.grid_size()
	for start_y in range(size.y):
		for start_x in range(size.x):
			for first_direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
				var perpendicular_directions: Array[Vector2i] = [
					Vector2i(-first_direction.y, first_direction.x),
					Vector2i(first_direction.y, -first_direction.x),
				]
				for second_direction: Vector2i in perpendicular_directions:
					var path: Array[int] = []
					for first_step in range(6):
						var first_coordinate := Vector2i(start_x, start_y) + first_direction * first_step
						var first_tile := int(terrain.tile_id_for_coordinate(first_coordinate))
						if first_tile < 0 or not _route_tile_available(first_tile):
							path.clear()
							break
						path.append(first_tile)
					if path.size() != 6:
						continue
					var turn_coordinate := Vector2i(start_x, start_y) + first_direction * 5
					for second_step in range(1, 6):
						var second_coordinate := turn_coordinate + second_direction * second_step
						var second_tile := int(terrain.tile_id_for_coordinate(second_coordinate))
						if second_tile < 0 or not _route_tile_available(second_tile):
							path.clear()
							break
						path.append(second_tile)
					if path.size() != 11:
						continue
					var first_candidates := _station_candidates_adjacent_to(path[0], path, [])
					var last_candidates := _station_candidates_adjacent_to(path.back(), path, first_candidates)
					if first_candidates.is_empty() or last_candidates.is_empty():
						continue
					var station_a := int(first_candidates[0])
					var station_b := int(last_candidates[0])
					if station_a == station_b:
						continue
					var reserved: Array[int] = path.duplicate()
					reserved.append(station_a)
					reserved.append(station_b)
					var support_candidates: Array[int] = []
					for route_tile: int in path:
						for neighbour: int in _cardinal_neighbours(route_tile):
							if not reserved.has(neighbour) and _route_tile_available(neighbour):
								support_candidates.append(neighbour)
					if support_candidates.is_empty():
						continue
					return {"route_tiles": path, "station_a": station_a, "station_b": station_b, "turn_tile": path[5]}
	return {}


func _find_existing_building_tile(fixture: Dictionary) -> int:
	var reserved: Array[int] = Array(fixture.get("route_tiles", [])).duplicate()
	reserved.append(int(fixture.get("station_a", -1)))
	reserved.append(int(fixture.get("station_b", -1)))
	for tile_id in range(main.city_grid.size()):
		if tile_id not in reserved and _route_tile_available(tile_id):
			return tile_id
	return -1


func _station_candidates_adjacent_to(tile_id: int, route_tiles: Array[int], excluded: Array[int]) -> Array[int]:
	var result: Array[int] = []
	for neighbour: int in _cardinal_neighbours(tile_id):
		if route_tiles.has(neighbour) or excluded.has(neighbour) or not _route_tile_available(neighbour):
			continue
		var quote: Dictionary = main.vertical_slice.placement_footprint_quote("公車站", neighbour, 5)
		if bool(quote.get("ok", false)) and str(quote.get("status", "")) == "approved":
			result.append(neighbour)
	return result


func _route_tile_available(tile_id: int) -> bool:
	return (
		main.vertical_slice.terrain_map.is_buildable(tile_id)
		and bool(main._is_tile_inside_hud_safe_area(tile_id))
		and main.vertical_slice.get_building_by_tile(tile_id).is_empty()
		and main.vertical_slice.active_construction_for_tile(tile_id).is_empty()
	)


func _cardinal_neighbours(tile_id: int) -> Array[int]:
	var result: Array[int] = []
	var terrain = main.vertical_slice.terrain_map
	var coordinate: Vector2i = terrain.coordinate_for_tile_id(tile_id)
	for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var neighbour := int(terrain.tile_id_for_coordinate(coordinate + direction))
		if neighbour >= 0:
			result.append(neighbour)
	return result


func _new_active_jobs(jobs_before: Dictionary) -> Array[Dictionary]:
	var old_ids: Dictionary = {}
	var old_jobs: Dictionary = jobs_before.get("jobs", {})
	for job_id_value: Variant in old_jobs.keys():
		old_ids[str(job_id_value)] = true
	var result: Array[Dictionary] = []
	for job_value: Variant in main.vertical_slice.construction.active_jobs():
		if job_value is Dictionary and not old_ids.has(str((job_value as Dictionary).get("id", ""))):
			result.append((job_value as Dictionary).duplicate(true))
	return result


func _job_duration_records(jobs: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for job: Dictionary in jobs:
		var remaining := int(job.get("projected_remaining_days", 0))
		var workers := int(job.get("worker_count", 0))
		var workload := float(job.get("remaining_work", job.get("workload", 0.0)))
		if remaining <= 0 or workers <= 0 or workload <= 0.0:
			return []
		result.append({
			"job_id": str(job.get("id", "")),
			"projected_remaining_days": remaining,
			"worker_count": workers,
			"workload": float(job.get("workload", 0.0)),
			"remaining_work": workload,
			"projected_total_days": int(job.get("projected_total_days", 0)),
			"start_day": int(job.get("start_day", -1)),
		})
	return result


func _negative_ledger_count() -> int:
	var result := 0
	for entry: Dictionary in main.vertical_slice.session.state.ledger.get_entries():
		if int(entry.get("amount", 0)) < 0:
			result += 1
	return result


func _capture_native(filename: String, state: String) -> Dictionary:
	var image := root.get_texture().get_image()
	if image.is_empty():
		_fail("native root capture is empty for %s" % state)
		return {}
	var path := output_dir.path_join(filename)
	if image.save_png(path) != OK:
		_fail("failed to save %s capture" % state)
		return {}
	var size := image.get_size()
	var bytes := FileAccess.get_file_as_bytes(path).size()
	var sha256 := FileAccess.get_sha256(path).to_lower()
	if size.x <= 0 or size.y <= 0 or bytes <= 0 or sha256.length() != 64:
		_fail("invalid PNG evidence for %s" % state)
		return {}
	return {
		"state": state,
		"filename": filename,
		"surface_kind": "native_fullscreen_root",
		"width": size.x,
		"height": size.y,
		"bytes": bytes,
		"sha256": sha256,
	}


func _source_identity() -> Dictionary:
	return {
		"worktree": OS.get_environment("MAYOR_ACCEPTANCE_WORKTREE"),
		"branch": OS.get_environment("MAYOR_ACCEPTANCE_BRANCH"),
		"head": OS.get_environment("MAYOR_ACCEPTANCE_HEAD"),
		"tree": OS.get_environment("MAYOR_ACCEPTANCE_TREE"),
		"dirty": OS.get_environment("MAYOR_ACCEPTANCE_DIRTY") == "true",
		"status_sha256": OS.get_environment("MAYOR_ACCEPTANCE_STATUS_SHA256"),
		"fingerprint": OS.get_environment("MAYOR_ACCEPTANCE_SOURCE_FINGERPRINT"),
	}


func _v2i(value: Variant) -> Array:
	return [int(value.x), int(value.y)]


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame


func _fail(message: String) -> void:
	if failed:
		return
	failed = true
	push_error("Transport route package actual-Main native visible acceptance failed: %s" % message)
	quit(1)
