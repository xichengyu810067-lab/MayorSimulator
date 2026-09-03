extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")

var _failed := false
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1440, 900)
	root.size = Vector2i(1440, 900)
	var capture_dir := _capture_directory_from_cli()
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await process_frame
	main._game_started = true
	main.start_screen.hide()
	if main.tutorial_overlay != null and main.tutorial_overlay.is_open():
		main.tutorial_overlay.close_as_completed(false)
	main._set_map_interaction_enabled(true)

	main.municipal_overlay.open_page("buildings")
	main._select_building_group("economy")
	await process_frame
	var regular_building_card := main.municipal_overlay.find_child("BuildingCard_商店", true, false) as Button
	_check(regular_building_card != null and regular_building_card.is_visible_in_tree(), "building page does not expose the regular shop card")
	if regular_building_card != null:
		regular_building_card.pressed.emit()
	await process_frame
	_check(main.municipal_overlay.current_page() == "blueprint" and main.selected_building == "商店", "regular building card did not open its blueprint directly")
	main.municipal_overlay.open_page("buildings")
	main._select_building_group("mobility")
	await process_frame
	_check(main.municipal_overlay.find_child("OpenBlueprintButton", true, false) == null, "building page still exposes the duplicate blueprint shortcut")
	_check(main.municipal_overlay.find_child("OpenTransportPlanningButton", true, false) == null, "building page still exposes the duplicate transport shortcut")
	var station_card := main.municipal_overlay.find_child("BuildingCard_公車站", true, false) as Button
	_check(station_card != null and station_card.is_visible_in_tree(), "building page does not expose the bus-station card")
	if station_card != null:
		station_card.pressed.emit()
	await process_frame
	_check(main.municipal_overlay.current_page() == "blueprint" and main.selected_building == "公車站", "station building card did not open its blueprint directly")
	var station_button := main.vertical_slice_panel.find_child("SubmitBlueprintButton", true, false) as Button
	_check(station_button != null and not station_button.disabled and station_button.text.contains("連續站點"), "approved station blueprint does not expose the continuous-planning entry")
	var funds_before_session := int(main.vertical_slice.treasury_balance())
	var jobs_before_session := int(main.vertical_slice.construction.jobs.size())
	if station_button != null:
		station_button.pressed.emit()
	await process_frame
	var session: Dictionary = main.vertical_slice.transport_planning_session_snapshot()
	var session_id := str(session.get("id", ""))
	_check(not session_id.is_empty() and str(session.get("state", "")) == "station_placement", "station-blueprint action did not begin one authoritative session")
	_check(main.placement_mode_active and main.placement_building_name == "公車站", "station-blueprint action did not enter map placement")
	_check(int(main.vertical_slice.treasury_balance()) == funds_before_session and main.vertical_slice.construction.jobs.size() == jobs_before_session, "starting a station session charged funds or created construction before confirmation")

	main._cancel_building_placement(true)
	session = main.vertical_slice.transport_planning_session_snapshot()
	_check(str(session.get("state", "")) == "paused" and not main.placement_mode_active, "Esc/right-click semantics close map action without pausing the session")
	main._open_transport_planning()
	await process_frame
	_check(not main.transport_planning_panel.has_signal("station_requested"), "transport page still exposes a second new-station session signal")
	_check(main.transport_planning_panel.find_child("TransportStationPager", true, false) == null, "transport page still exposes a second station entry pager")
	var continue_button := main.transport_planning_panel.find_child("TransportPlanningSessionContinue", true, false) as Button
	_check(continue_button != null and not continue_button.disabled, "paused session is not recoverable from the transport page")
	if continue_button != null:
		continue_button.pressed.emit()
	await process_frame
	session = main.vertical_slice.transport_planning_session_snapshot()
	_check(main.placement_mode_active and str(session.get("state", "")) == "station_placement", "continue did not restore station placement")
	_check(str(session.get("id", "")) == session_id, "continue recreated the authoritative planning session")
	_check(int(main.vertical_slice.treasury_balance()) == funds_before_session and main.vertical_slice.construction.jobs.size() == jobs_before_session, "continue charged funds or created construction before confirmation")

	var fixture := _find_bus_fixture(main)
	_check(not fixture.is_empty(), "layout 3 has no flat connected bus-session fixture outside the HUD safe area")
	if fixture.is_empty():
		await TestCleanup.finish(self, [main], 1)
		return
	var first_tile := int(fixture["first_station"])
	var second_tile := int(fixture["second_station"])
	var funds_before: int = int(main.vertical_slice.treasury_balance())
	var negative_ledger_before := _negative_ledger_count(main)
	_place_station(main, first_tile)
	session = main.vertical_slice.transport_planning_session_snapshot()
	_check(main.placement_mode_active and main.placement_building_name == "公車站", "first station incorrectly ends continuous placement")
	_check(str(session.get("id", "")) == session_id and _station_draft_count(session) == 1, "first station changed session identity or did not retain its draft")
	_check(main.placement_banner.is_visible_in_tree() and main.placement_label.text.contains("1/3"), "first-station checkpoint lacks its visible placement banner")
	_check(main.placement_label.text.contains("公車路線") and main.placement_label.text.contains("公車站") and not main.placement_label.text.contains("transport_planning_"), "station checkpoint exposes its internal session id or lacks a player-facing route/station name")
	await _capture_checkpoint("station-placement", "01-station-placement.png", capture_dir)
	_place_station(main, second_tile)
	session = main.vertical_slice.transport_planning_session_snapshot()
	_check(main.placement_mode_active and str(session.get("id", "")) == session_id, "second station recreated or closed the session")
	_check(_station_draft_count(session) == 2 and Array(session.get("station_refs", [])).is_empty(), "same session does not retain both station drafts before package confirmation")
	_check(int(main.vertical_slice.treasury_balance()) == funds_before, "station drafts charged construction funding before package confirmation")
	_check(main.vertical_slice.construction.jobs.size() == jobs_before_session, "station drafts created construction jobs before package confirmation")

	_press_map_confirm(main, "station next-step")
	await process_frame
	session = main.vertical_slice.transport_planning_session_snapshot()
	_check(str(session.get("state", "")) == "network_placement", "station next-step did not advance the same draft to network placement")
	_check(main.municipal_overlay.is_open() and main.municipal_overlay.current_page() == "transport_planning", "station next-step did not return to the same transport page")
	_check(int(main.vertical_slice.treasury_balance()) == funds_before and main.vertical_slice.construction.jobs.size() == jobs_before_session, "advancing to the network draft changed authoritative construction state")

	var road_button := main.transport_planning_panel.find_child("InfrastructureAdd_road", true, false) as Button
	_check(road_button != null and not road_button.disabled, "network phase does not expose the same-mode guideway")
	if road_button != null:
		road_button.pressed.emit()
	_check(main.map_action_mode == "transport_infrastructure" and main.transport_plan_kind == "road", "road action did not enter the real infrastructure map mode")
	var road_tiles: Array = fixture["road_tiles"]
	for road_index in range(road_tiles.size()):
		main._on_grid_pressed(int(road_tiles[road_index]))
		_check(main.transport_plan_tiles.size() == road_index + 1, "road map input did not append the next adjacent tile")
		_check(main.transport_plan_tiles[road_index] == int(road_tiles[road_index]), "road map input changed the player-selected path order")
	_check(main.placement_confirm_button.visible and not main.placement_confirm_button.disabled, "road quote did not enable the visible confirmation control")
	_check(main.placement_confirm_button.text.contains("確認總包"), "road draft does not identify the package-confirmation handoff")
	_press_map_confirm(main, "road draft")
	await process_frame
	session = main.vertical_slice.transport_planning_session_snapshot()
	_check(str(session.get("state", "")) == "route_edit" and Array(session.get("network_refs", [])).is_empty(), "route draft did not advance to one package confirmation without authoritative projects")
	_check(main.municipal_overlay.is_open() and main.municipal_overlay.current_page() == "transport_planning", "route draft did not return to the same planning page")
	_check(main.map_action_mode == "inspect" and main.transport_plan_tiles.is_empty(), "road confirmation did not clear the completed map draft")
	_check(int(main.vertical_slice.treasury_balance()) == funds_before and main.vertical_slice.construction.jobs.size() == jobs_before_session, "route draft changed authoritative construction state before package confirmation")
	continue_button = main.transport_planning_panel.find_child("TransportPlanningSessionContinue", true, false) as Button
	_check(continue_button != null and continue_button.text.contains("確認總包") and not continue_button.disabled, "route-edit phase lacks an enabled one-step package confirmation")
	var package_detail := main.transport_planning_panel.find_child("TransportPlanningSessionDetail", true, false) as Label
	_check(package_detail != null and package_detail.text.contains("總工程費") and package_detail.text.contains("路線 5 格") and package_detail.text.contains("月維護"), "package confirmation does not expose its route-length cost breakdown")
	var route_button := main.transport_planning_panel.find_child("PlanRoute_bus", true, false) as Button
	_check(route_button == null or route_button.disabled, "package workflow still requires a second route-stop planning pass")
	await _capture_checkpoint("package-confirmation", "02-package-confirmation.png", capture_dir)
	if continue_button != null:
		continue_button.pressed.emit()
	await process_frame
	session = main.vertical_slice.transport_planning_session_snapshot()
	_check(str(session.get("state", "")) == "waiting_construction" and str(session.get("resume_state", "")) == "route_edit", "package confirmation did not start its construction jobs in the same session")
	_check(str(session.get("id", "")) == session_id and Array(session.get("station_refs", [])).size() == 2, "package confirmation lost its session or authoritative station job references")
	_check(Array(session.get("network_refs", [])).size() >= 2, "package confirmation did not retain route and required support project references")
	_check(main.vertical_slice.construction.jobs.size() == jobs_before_session + 4, "package confirmation did not create exactly two station, route and support jobs")
	_check(int(main.vertical_slice.treasury_balance()) < funds_before and _negative_ledger_count(main) == negative_ledger_before + 1, "package confirmation did not apply one authoritative debit")
	_check(main.vertical_slice.transport.routes.is_empty(), "route activated before package construction completed")
	var waiting_session_card := main.transport_planning_panel.find_child("TransportPlanningSessionCard", true, false) as Control
	_check(waiting_session_card != null and waiting_session_card.is_visible_in_tree(), "waiting package lacks its visible session card")
	await _capture_checkpoint("waiting-construction", "03-waiting-construction.png", capture_dir)
	_advance_all_active_jobs(main)
	session = main.vertical_slice.transport_planning_session_snapshot()
	_check(str(session.get("state", "")) == "materialized" and str(session.get("id", "")) == session_id, "construction completion did not automatically materialize the same package session")
	_check(Array(session.get("route_refs", [])).size() == 1, "materialized session does not retain one authoritative route identity")
	_check(main.vertical_slice.transport.routes.size() == 1, "construction completion created duplicate or missing route identities")
	_check(main.vertical_slice.transport.segments.size() == 1 and main.vertical_slice.transport.facilities.size() == 1, "completed package materialized duplicate or missing topology")
	var route: Dictionary = main.vertical_slice.transport.routes.values()[0]
	_check(str(route.get("status", "")) == "operational" and str(route.get("price_model", "")) == "route_package_v1", "automatically materialized route is not operational with versioned pricing")
	_check(_negative_ledger_count(main) == negative_ledger_before + 1, "construction completion introduced another package debit")
	_check(main.map_action_mode == "inspect" and main.transport_route_station_tiles.is_empty(), "automatic route activation left a stale route-selection action")

	var close_button := main.transport_planning_panel.find_child("TransportPlanningSessionClose", true, false) as Button
	_check(close_button != null and close_button.visible, "materialized summary lacks an explicit close command")
	if close_button != null:
		close_button.pressed.emit()
	await process_frame
	session = main.vertical_slice.transport_planning_session_snapshot()
	_check(str(session.get("state", "")) == "closed", "explicit close did not close the authoritative session")
	main._on_transport_infrastructure_requested("road", "demolish")
	_check(main.map_action_mode == "transport_infrastructure" and main.transport_plan_operation == "demolish", "closed session broke the legacy non-session transport flow")

	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Transport planning UI session flow test passed. Checks=%d" % _checks)
	await TestCleanup.finish(self, [main], exit_code)


func _place_station(main, tile_id: int) -> void:
	var funds_before := int(main.vertical_slice.treasury_balance())
	var jobs_before := int(main.vertical_slice.construction.jobs.size())
	main._on_grid_pressed(tile_id)
	_check(main._pending_construction_tile < 0 and not main.construction_confirmation.is_open(), "station draft opened the legacy per-building confirmation")
	_check(int(main.vertical_slice.treasury_balance()) == funds_before and main.vertical_slice.construction.jobs.size() == jobs_before, "station draft mutated authoritative construction state")
	_check(main.hint_label.text.contains("草案") and main.hint_label.text.contains("不扣款"), "station draft lacks explicit zero-charge feedback: %s" % main.hint_label.text)


func _station_draft_count(session: Dictionary) -> int:
	return Array(Dictionary(session.get("route_draft", {})).get("station_placements", [])).size()


func _negative_ledger_count(main) -> int:
	var result := 0
	for entry: Dictionary in main.vertical_slice.session.state.ledger.get_entries():
		if int(entry.get("amount", 0)) < 0:
			result += 1
	return result


func _press_map_confirm(main, phase: String) -> void:
	var confirm_button := main.placement_confirm_button as Button
	_check(confirm_button != null and confirm_button.visible and not confirm_button.disabled, "%s lacks an enabled visible confirmation" % phase)
	if confirm_button != null and confirm_button.visible and not confirm_button.disabled:
		confirm_button.pressed.emit()


func _capture_directory_from_cli() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--transport-session-capture-dir="):
			continue
		var requested_dir := argument.trim_prefix("--transport-session-capture-dir=").strip_edges()
		if requested_dir.is_empty() or not requested_dir.is_absolute_path():
			_check(false, "transport session capture directory must be an absolute path")
			return ""
		var capture_dir := requested_dir.simplify_path()
		if FileAccess.file_exists(capture_dir):
			_check(false, "transport session capture directory points to a file: %s" % capture_dir)
			return ""
		if not DirAccess.dir_exists_absolute(capture_dir):
			var create_error := DirAccess.make_dir_recursive_absolute(capture_dir)
			if create_error != OK:
				_check(false, "could not create transport session capture directory: %s (%s)" % [capture_dir, error_string(create_error)])
				return ""
		return capture_dir
	return ""


func _capture_checkpoint(stage: String, file_name: String, capture_dir: String) -> void:
	if capture_dir.is_empty():
		return
	await process_frame
	await process_frame
	var viewport_texture := root.get_texture()
	if viewport_texture == null:
		_check(false, "capture viewport texture is unavailable at stage %s" % stage)
		return
	var capture_image := viewport_texture.get_image()
	if capture_image == null or capture_image.is_empty():
		_check(false, "capture viewport image is empty at stage %s" % stage)
		return
	var capture_path := capture_dir.path_join(file_name)
	var save_error := capture_image.save_png(capture_path)
	if save_error != OK:
		_check(false, "could not save capture at stage %s: %s (%s)" % [stage, capture_path, error_string(save_error)])
		return
	print("TRANSPORT_SESSION_CAPTURE_SAVED stage=%s path=%s" % [stage, capture_path])


func _advance_all_active_jobs(main) -> void:
	var days := 1
	for job_value: Variant in main.vertical_slice.construction.active_jobs():
		if job_value is Dictionary:
			days = maxi(days, int((job_value as Dictionary).get("projected_remaining_days", 0)))
	var events: Array[Dictionary] = main.vertical_slice.advance_days(days, {}, false)
	main._consume_vertical_events(events)
	main._sync_vertical_state()
	main._update_ui()


func _find_bus_fixture(main) -> Dictionary:
	var terrain = main.vertical_slice.terrain_map
	var size: Vector2i = terrain.grid_size()
	for road_y in range(size.y - 1):
		var station_y := road_y + 1
		for start_x in range(size.x - 4):
			var road_tiles: Array[int] = []
			var usable := true
			for x in range(start_x, start_x + 5):
				var road_tile := _tile(main, x, road_y)
				if (
					not terrain.is_buildable(road_tile)
					or not main.vertical_slice.get_building_by_tile(road_tile).is_empty()
					or not bool(main._is_tile_inside_hud_safe_area(road_tile))
				):
					usable = false
					break
				road_tiles.append(road_tile)
			if not usable:
				continue
			var depot_tile := _tile(main, start_x, station_y)
			var first_station := _tile(main, start_x + 1, station_y)
			var second_station := _tile(main, start_x + 3, station_y)
			for candidate: int in [depot_tile, first_station, second_station]:
				if (
					not terrain.is_buildable(candidate)
					or not main.vertical_slice.get_building_by_tile(candidate).is_empty()
					or not bool(main._is_tile_inside_hud_safe_area(candidate))
				):
					usable = false
					break
			if usable:
				return {
					"road_tiles": road_tiles,
					"depot_tile": depot_tile,
					"first_station": first_station,
					"second_station": second_station,
				}
	return {}


func _tile(main, x: int, y: int) -> int:
	return int(main.vertical_slice.terrain_map.tile_id_for_coordinate(Vector2i(x, y)))


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Transport planning UI session flow test failed: %s" % message)
