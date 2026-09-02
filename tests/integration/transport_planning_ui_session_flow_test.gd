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

	main._select_building("公車站")
	main.municipal_overlay.open_page("blueprint")
	await process_frame
	var station_button := main.vertical_slice_panel.find_child("SubmitBlueprintButton", true, false) as Button
	_check(station_button != null and not station_button.disabled and station_button.text.contains("連續站點"), "approved station blueprint does not expose the continuous-planning entry")
	if station_button != null:
		station_button.pressed.emit()
	await process_frame
	var session: Dictionary = main.vertical_slice.transport_planning_session_snapshot()
	var session_id := str(session.get("id", ""))
	_check(not session_id.is_empty() and str(session.get("state", "")) == "station_placement", "station-blueprint action did not begin one authoritative session")
	_check(main.placement_mode_active and main.placement_building_name == "公車站", "station-blueprint action did not enter map placement")

	main._cancel_building_placement(true)
	session = main.vertical_slice.transport_planning_session_snapshot()
	_check(str(session.get("state", "")) == "paused" and not main.placement_mode_active, "Esc/right-click semantics close map action without pausing the session")
	main._open_transport_planning()
	await process_frame
	var continue_button := main.transport_planning_panel.find_child("TransportPlanningSessionContinue", true, false) as Button
	_check(continue_button != null and not continue_button.disabled, "paused session is not recoverable from the transport page")
	if continue_button != null:
		continue_button.pressed.emit()
	await process_frame
	_check(main.placement_mode_active and str(main.vertical_slice.transport_planning_session_snapshot().get("state", "")) == "station_placement", "continue did not restore station placement")

	var fixture := _find_bus_fixture(main)
	_check(not fixture.is_empty(), "layout 3 has no flat connected bus-session fixture outside the HUD safe area")
	if fixture.is_empty():
		await TestCleanup.finish(self, [main], 1)
		return
	var first_tile := int(fixture["first_station"])
	var second_tile := int(fixture["second_station"])
	var funds_before: int = int(main.vertical_slice.treasury_balance())
	_place_station(main, first_tile)
	session = main.vertical_slice.transport_planning_session_snapshot()
	_check(main.placement_mode_active and main.placement_building_name == "公車站", "first station incorrectly ends continuous placement")
	_check(str(session.get("id", "")) == session_id and Array(session.get("station_refs", [])).size() == 1, "first station changed session identity or did not register")
	_check(main.placement_banner.is_visible_in_tree() and main.placement_label.text.contains("1/3"), "first-station checkpoint lacks its visible placement banner")
	_check(main.placement_label.text.contains("公車站") and not main.placement_label.text.contains("transport_planning_"), "station checkpoint exposes its internal session id instead of a player-facing plan name")
	await _capture_checkpoint("station-placement", "01-station-placement.png", capture_dir)
	_place_station(main, second_tile)
	session = main.vertical_slice.transport_planning_session_snapshot()
	_check(main.placement_mode_active and str(session.get("id", "")) == session_id, "second station recreated or closed the session")
	_check(Array(session.get("station_refs", [])).size() == 2, "same session does not retain both station jobs")
	_check(main.vertical_slice.treasury_balance() < funds_before, "station confirmations did not use authoritative construction funding")
	_check(main.vertical_slice.construction.jobs.size() == 2, "two station confirmations created duplicate or missing construction jobs")

	_press_map_confirm(main, "station next-step")
	await process_frame
	session = main.vertical_slice.transport_planning_session_snapshot()
	_check(str(session.get("state", "")) == "waiting_construction" and str(session.get("resume_state", "")) == "network_placement", "station next-step did not wait for construction and retain network resume")
	_check(main.municipal_overlay.is_open() and main.municipal_overlay.current_page() == "transport_planning", "station next-step did not return to the same transport page")
	var waiting_session_card := main.transport_planning_panel.find_child("TransportPlanningSessionCard", true, false) as Control
	_check(waiting_session_card != null and waiting_session_card.is_visible_in_tree(), "waiting checkpoint lacks its visible session card")
	await _capture_checkpoint("waiting-construction", "02-waiting-construction.png", capture_dir)
	_advance_all_active_jobs(main)
	session = main.vertical_slice.transport_planning_session_snapshot()
	_check(str(session.get("state", "")) == "network_placement" and str(session.get("id", "")) == session_id, "station completion did not automatically resume the same session at network placement")
	_check(main.municipal_overlay.is_open() and main.municipal_overlay.current_page() == "transport_planning", "station completion did not keep the transport page open for its automatic network handoff")

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
	var jobs_before_road: int = int(main.vertical_slice.construction.jobs.size())
	var funds_before_road := int(main.vertical_slice.treasury_balance())
	_press_map_confirm(main, "road project")
	await process_frame
	session = main.vertical_slice.transport_planning_session_snapshot()
	_check(str(session.get("state", "")) == "network_placement" and Array(session.get("network_refs", [])).size() == 1, "first network project incorrectly advances or leaves the session")
	_check(main.municipal_overlay.is_open() and main.municipal_overlay.current_page() == "transport_planning", "network project did not return to the same planning page")
	_check(main.map_action_mode == "inspect" and main.transport_plan_tiles.is_empty(), "road confirmation did not clear the completed map draft")
	_check(main.vertical_slice.construction.jobs.size() == jobs_before_road + 1, "road confirmation created duplicate or missing construction jobs")
	_check(int(main.vertical_slice.treasury_balance()) < funds_before_road, "road confirmation did not apply exactly one funded project")

	var depot_button := main.transport_planning_panel.find_child("InfrastructureAdd_bus_depot", true, false) as Button
	_check(depot_button != null and not depot_button.disabled, "network phase cannot add its required facility after guideway confirmation")
	if depot_button != null:
		depot_button.pressed.emit()
	_check(main.map_action_mode == "transport_infrastructure" and main.transport_plan_kind == "bus_depot", "depot action did not enter the real infrastructure map mode")
	main._on_grid_pressed(int(fixture["depot_tile"]))
	_check(main.transport_plan_tiles == [int(fixture["depot_tile"])], "depot map input did not select exactly its clicked tile")
	_check(main.placement_confirm_button.visible and not main.placement_confirm_button.disabled, "depot quote did not enable the visible confirmation control")
	var jobs_before_depot: int = int(main.vertical_slice.construction.jobs.size())
	var funds_before_depot := int(main.vertical_slice.treasury_balance())
	_press_map_confirm(main, "depot project")
	await process_frame
	session = main.vertical_slice.transport_planning_session_snapshot()
	_check(str(session.get("state", "")) == "network_placement" and Array(session.get("network_refs", [])).size() == 2, "second network project did not remain in the same planning phase")
	_check(str(session.get("id", "")) == session_id, "multiple network projects recreated the planning session")
	_check(main.map_action_mode == "inspect" and main.transport_plan_tiles.is_empty(), "depot confirmation did not clear the completed map draft")
	_check(main.vertical_slice.construction.jobs.size() == jobs_before_depot + 1, "depot confirmation created duplicate or missing construction jobs")
	_check(int(main.vertical_slice.treasury_balance()) < funds_before_depot, "depot confirmation did not apply exactly one funded project")

	continue_button = main.transport_planning_panel.find_child("TransportPlanningSessionContinue", true, false) as Button
	_check(continue_button != null and continue_button.text.contains("規劃路線"), "network phase lacks the explicit route-step command")
	if continue_button != null:
		continue_button.pressed.emit()
	await process_frame
	session = main.vertical_slice.transport_planning_session_snapshot()
	_check(str(session.get("state", "")) == "waiting_construction" and str(session.get("resume_state", "")) == "route_edit", "explicit route step did not wait for active network projects")
	_advance_all_active_jobs(main)
	session = main.vertical_slice.transport_planning_session_snapshot()
	_check(str(session.get("state", "")) == "route_edit" and str(session.get("id", "")) == session_id, "network completion did not automatically resume route edit")
	_check(main.municipal_overlay.is_open() and main.municipal_overlay.current_page() == "transport_planning", "network completion did not keep the transport page open for its automatic route handoff")
	_check(main.vertical_slice.transport.segments.size() == 1 and main.vertical_slice.transport.facilities.size() == 1, "completed network projects materialized duplicate or missing topology")

	var route_button := main.transport_planning_panel.find_child("PlanRoute_bus", true, false) as Button
	_check(route_button != null and route_button.is_visible_in_tree() and not route_button.disabled, "route-edit phase does not expose its matching visible route command")
	await _capture_checkpoint("route-edit", "03-route-edit.png", capture_dir)
	if route_button != null:
		route_button.pressed.emit()
	_check(main.map_action_mode == "transport_route_stops" and main.transport_route_mode == "bus", "route action did not enter the real station-selection map mode")
	main._on_grid_pressed(first_tile)
	_check(main.transport_route_station_tiles == [first_tile], "first station click did not establish route order")
	main._on_grid_pressed(second_tile)
	_check(main.transport_route_station_tiles == [first_tile, second_tile], "second station click did not append route order")
	_check(main.placement_confirm_button.visible and not main.placement_confirm_button.disabled, "valid station order did not enable the visible route confirmation")
	var funds_before_route := int(main.vertical_slice.treasury_balance())
	var jobs_before_route: int = int(main.vertical_slice.construction.jobs.size())
	var routes_before: int = int(main.vertical_slice.transport.routes.size())
	_press_map_confirm(main, "route materialization")
	await process_frame
	session = main.vertical_slice.transport_planning_session_snapshot()
	_check(str(session.get("state", "")) == "materialized" and str(session.get("id", "")) == session_id, "route did not materialize through the same session")
	_check(Array(session.get("route_refs", [])).size() == 1, "materialized session does not retain one authoritative route identity")
	_check(main.map_action_mode == "inspect" and main.transport_route_station_tiles.is_empty(), "route confirmation did not clear the completed station draft")
	_check(main.vertical_slice.transport.routes.size() == routes_before + 1, "route confirmation created duplicate or missing topology identities")
	_check(main.vertical_slice.construction.jobs.size() == jobs_before_route, "route confirmation unexpectedly created another construction job")
	_check(int(main.vertical_slice.treasury_balance()) == funds_before_route, "route confirmation unexpectedly charged construction funds")

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
	main._on_grid_pressed(tile_id)
	_check(
		main._pending_construction_tile == tile_id,
		"station placement did not produce a direct quote for tile %d: %s" % [tile_id, main.hint_label.text]
	)
	if main._pending_construction_tile != tile_id:
		return
	_check(main.construction_confirmation.is_open(), "station quote did not open the player-facing confirmation overlay")
	var confirm_button := main.construction_confirmation.find_child("ConfirmConstructionButton", true, false) as Button
	_check(confirm_button != null and not confirm_button.disabled, "station quote did not expose an enabled construction confirmation")
	if confirm_button != null:
		confirm_button.pressed.emit()
	_check(not main.construction_confirmation.is_open(), "station confirmation overlay did not close after the player command")


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
