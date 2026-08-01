extends SceneTree

const TestCleanup = preload("res://tests/helpers/scene_tree_test_cleanup.gd")

var _failed := false
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var PanelScript = load("res://ui/shell/transport_planning_panel.gd")
	if PanelScript == null:
		push_error("Transport planning panel script could not be loaded.")
		quit(1)
		return

	var panel = PanelScript.new()
	panel.size = Vector2(1180, 680)
	root.add_child(panel)
	await process_frame

	var station_events: Array[String] = []
	var infrastructure_events: Array[Dictionary] = []
	var route_events: Array[Dictionary] = []
	var toggle_events: Array[Dictionary] = []
	var delete_events: Array[String] = []
	panel.station_requested.connect(
		func(building_name: String) -> void: station_events.append(building_name)
	)
	panel.infrastructure_requested.connect(
		func(kind: String, operation: String) -> void:
			infrastructure_events.append({"kind": kind, "operation": operation})
	)
	panel.route_planning_requested.connect(
		func(mode: String, fleet_size: int, headway_minutes: int, fare: int) -> void:
			route_events.append({
				"mode": mode,
				"fleet_size": fleet_size,
				"headway_minutes": headway_minutes,
				"fare": fare,
			})
	)
	panel.route_toggle_requested.connect(
		func(route_id: String, enabled: bool) -> void:
			toggle_events.append({"route_id": route_id, "enabled": enabled})
	)
	panel.route_delete_requested.connect(
		func(route_id: String) -> void: delete_events.append(route_id)
	)

	_check_station_controls(panel)
	_check_infrastructure_controls(panel)
	_check_route_mode_controls(panel)
	_check_readability(panel)

	_press(panel, "StationAction_bus_station")
	_press(panel, "StationAction_airport")
	_check(station_events == ["公車站", "機場"], "station actions emitted incorrect building names")

	_press(panel, "InfrastructureAdd_road")
	_press(panel, "InfrastructureRemove_metro_track")
	_press(panel, "InfrastructureAdd_bus_depot")
	_press(panel, "InfrastructureRemove_rail_signal")
	_check(infrastructure_events == [
		{"kind": "road", "operation": "build"},
		{"kind": "metro_track", "operation": "demolish"},
		{"kind": "bus_depot", "operation": "place"},
		{"kind": "rail_signal", "operation": "remove"},
	], "infrastructure actions emitted incorrect kind or operation")

	var fleet := panel.find_child("TransportFleetSize", true, false) as SpinBox
	var headway := panel.find_child("TransportHeadwayMinutes", true, false) as SpinBox
	var fare := panel.find_child("TransportRouteFare", true, false) as SpinBox
	_check(fleet != null and headway != null and fare != null, "route operation SpinBoxes are missing")
	if fleet != null and headway != null and fare != null:
		fleet.value = 5
		headway.value = 8
		fare.value = 45
	_press(panel, "PlanRoute_bus")
	_check(route_events == [{
		"mode": "bus",
		"fleet_size": 5,
		"headway_minutes": 8,
		"fare": 45,
	}], "route planning did not emit the selected operating settings")

	panel.set_view_model({
		"planning_unlocked": true,
		"fleet_size": 7,
		"headway_minutes": 9,
		"fare": 40,
		"routes": [
			{
				"route_id": "metro_blue",
				"name": "藍線",
				"mode": "metro",
				"status": "operational",
				"enabled": true,
				"stop_count": 4,
				"path_length": 18,
				"fleet_size": 3,
				"headway_minutes": 6,
				"fare": 35,
			},
			{
				"route_id": "rail_west",
				"name": "西部幹線",
				"mode": "train",
				"status": "suspended",
				"enabled": false,
				"stop_ids": ["west", "central"],
				"path_tile_count": 24,
				"fleet_size": 2,
				"headway": 12,
				"fare": 80,
				"status_detail": "待修復號誌與平交道",
			},
		],
	})
	await process_frame

	_check(int(fleet.value) == 7 and int(headway.value) == 9 and int(fare.value) == 40, "view model did not restore route settings")
	var network_summary := panel.find_child("TransportNetworkSummary", true, false) as Label
	_check(network_summary != null and network_summary.text.contains("2 條規劃") and network_summary.text.contains("1 條營運中"), "network summary is incomplete")
	var metro_status := panel.find_child("TransportRouteStatus_metro_blue", true, false) as Label
	var rail_status := panel.find_child("TransportRouteStatus_rail_west", true, false) as Label
	_check(metro_status != null and metro_status.text == "營運中", "operational route status is not rendered")
	_check(rail_status != null and rail_status.text == "已停駛", "suspended route status is not rendered")
	var metro_details := panel.find_child("TransportRouteDetails_metro_blue", true, false) as Label
	var rail_details := panel.find_child("TransportRouteDetails_rail_west", true, false) as Label
	_check(metro_details != null and _contains_all(metro_details.text, ["站點 4", "路徑 18 格", "車隊 3 輛", "班距 6 分鐘", "票價 $35"]), "metro route card omits required operating facts")
	_check(rail_details != null and _contains_all(rail_details.text, ["站點 2", "路徑 24 格", "車隊 2 輛", "班距 12 分鐘", "票價 $80"]), "rail route card omits required operating facts")
	var rail_reason := panel.find_child("TransportRouteReason_rail_west", true, false) as Label
	_check(rail_reason != null and rail_reason.text.contains("號誌") and rail_reason.text.contains("平交道"), "route blocker reason is not visible")

	_press(panel, "TransportRouteToggle_metro_blue")
	_press(panel, "TransportRouteToggle_rail_west")
	_press(panel, "TransportRouteDelete_rail_west")
	_check(toggle_events == [
		{"route_id": "metro_blue", "enabled": false},
		{"route_id": "rail_west", "enabled": true},
	], "route toggle actions emitted incorrect target states")
	_check(delete_events == ["rail_west"], "route delete action emitted an incorrect route id")

	var snapshot: Dictionary = panel.debug_snapshot()
	_check(snapshot.get("route_count", 0) == 2, "debug snapshot route count is incorrect")
	_check(str(snapshot.get("live_summary", "")).contains("車輛只會") and str(snapshot.get("live_summary", "")).contains("任一條件未完成"), "live summary does not explain the no-random-vehicles rule")
	_check(str(snapshot.get("live_summary", "")).contains("平交道或號誌") and str(snapshot.get("live_summary", "")).contains("車庫"), "live summary omits infrastructure prerequisites")
	_check_progressive_groups(snapshot)

	var hero := panel.find_child("TransportPlanningHero", true, false) as PanelContainer
	var light_style := hero.get_theme_stylebox("panel") as StyleBoxFlat if hero != null else null
	var light_background := light_style.bg_color if light_style != null else Color.TRANSPARENT
	var light_text := metro_details.get_theme_color("font_color") if metro_details != null else Color.TRANSPARENT
	var light_input_style := fleet.get_line_edit().get_theme_stylebox("normal") as StyleBoxFlat if fleet != null else null
	var light_input_background := light_input_style.bg_color if light_input_style != null else Color.TRANSPARENT
	panel.set_dark_mode(true)
	var dark_style := hero.get_theme_stylebox("panel") as StyleBoxFlat if hero != null else null
	var dark_input_style := fleet.get_line_edit().get_theme_stylebox("normal") as StyleBoxFlat if fleet != null else null
	_check(dark_style != null and dark_style.bg_color != light_background, "panel cards did not refresh for dark mode")
	_check(metro_details != null and metro_details.get_theme_color("font_color") != light_text, "panel text did not refresh for dark mode")
	_check(dark_input_style != null and dark_input_style.bg_color != light_input_background, "route inputs did not refresh for dark mode")
	_check(bool(panel.debug_snapshot().get("dark_mode", false)), "debug snapshot does not expose dark mode")

	panel.set_view_model({"planning_unlocked": false, "routes": []})
	await process_frame
	var station_action := panel.find_child("StationAction_bus_station", true, false) as Button
	var plan_action := panel.find_child("PlanRoute_bus", true, false) as Button
	var empty_label := panel.find_child("TransportRouteEmpty", true, false) as Label
	_check(station_action != null and station_action.disabled, "locked planning still allows station siting")
	_check(plan_action != null and plan_action.disabled, "locked planning still allows route creation")
	_check(empty_label != null and empty_label.visible, "empty route state is not rendered")
	_check(int(panel.debug_snapshot().get("route_count", -1)) == 0, "route cards were not cleared with an empty snapshot")

	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Transport planning panel test passed. Checks=%d" % _checks)
	await TestCleanup.finish(self, [panel], exit_code)


func _check_station_controls(panel: Control) -> void:
	for choice: Dictionary in [
		{"id": "bus_station", "label": "公車站"},
		{"id": "metro_station", "label": "捷運站"},
		{"id": "rail_station", "label": "火車站"},
		{"id": "airport", "label": "機場"},
	]:
		var button := panel.find_child("StationAction_%s" % choice["id"], true, false) as Button
		_check(button != null and button.text.contains(str(choice["label"])), "missing semantic station action: %s" % choice["label"])


func _check_infrastructure_controls(panel: Control) -> void:
	for definition: Dictionary in [
		{"id": "road", "label": "道路"},
		{"id": "metro_track", "label": "捷運軌道"},
		{"id": "heavy_rail", "label": "重型鐵路"},
		{"id": "runway", "label": "跑道"},
		{"id": "taxiway", "label": "滑行道"},
		{"id": "bus_depot", "label": "公車車庫"},
		{"id": "metro_depot", "label": "捷運機廠"},
		{"id": "rail_depot", "label": "鐵路機廠"},
		{"id": "rail_signal", "label": "鐵路號誌"},
	]:
		var add_button := panel.find_child("InfrastructureAdd_%s" % definition["id"], true, false) as Button
		var remove_button := panel.find_child("InfrastructureRemove_%s" % definition["id"], true, false) as Button
		var card := panel.find_child("TransportInfrastructureChoice_%s" % definition["id"], true, false) as PanelContainer
		_check(add_button != null and remove_button != null and card != null, "missing build/remove controls for %s" % definition["label"])


func _check_route_mode_controls(panel: Control) -> void:
	for mode: String in ["bus", "metro", "train", "air"]:
		_check(panel.find_child("PlanRoute_%s" % mode, true, false) is Button, "missing route planning action: %s" % mode)


func _check_readability(panel: Control) -> void:
	var content := panel.find_child("TransportPlanningContent", true, false) as VBoxContainer
	_check(content != null and content.custom_minimum_size.x <= 1180.0, "panel content is wider than the 1280x720 viewport budget")
	for node_variant: Variant in panel.find_children("*", "Button", true, false):
		var button := node_variant as Button
		if button == null or bool(button.get_meta("progressive_navigation", false)):
			continue
		_check(button.get_theme_font_size("font_size") >= 18, "transport action text is smaller than 18px: %s" % button.name)
		_check(button.custom_minimum_size.y >= 50.0, "transport action target is shorter than 50px: %s" % button.name)
	for input_name: String in ["TransportFleetSize", "TransportHeadwayMinutes", "TransportRouteFare"]:
		var input := panel.find_child(input_name, true, false) as SpinBox
		_check(input != null and input.get_line_edit().get_theme_font_size("font_size") >= 18, "route input is not readable: %s" % input_name)


func _check_progressive_groups(snapshot: Dictionary) -> void:
	var groups_variant: Variant = snapshot.get("progressive_groups", {})
	_check(groups_variant is Dictionary, "debug snapshot does not expose progressive groups")
	if not groups_variant is Dictionary:
		return
	var groups := groups_variant as Dictionary
	for expected_name: String in ["TransportStationPager", "TransportInfrastructurePager", "TransportRouteModePager", "TransportRoutePager"]:
		_check(groups.has(expected_name), "missing progressive group: %s" % expected_name)
	for group_name: Variant in groups:
		var group_variant: Variant = groups[group_name]
		if not group_variant is Dictionary:
			_check(false, "invalid progressive group snapshot: %s" % group_name)
			continue
		var group := group_variant as Dictionary
		_check(int(group.get("visible_choice_count", 0)) <= 3, "progressive group displays more than three choices: %s" % group_name)
	_check(int((groups.get("TransportStationPager", {}) as Dictionary).get("choice_count", 0)) == 4, "station pager does not contain all four station choices")
	_check(int((groups.get("TransportInfrastructurePager", {}) as Dictionary).get("choice_count", 0)) == 9, "infrastructure pager does not contain all nine choices")
	_check(int((groups.get("TransportRouteModePager", {}) as Dictionary).get("choice_count", 0)) == 4, "route mode pager does not contain all four modes")
	_check(int((groups.get("TransportRoutePager", {}) as Dictionary).get("choice_count", 0)) == 2, "route pager does not contain the supplied routes")


func _press(panel: Control, node_name: String) -> void:
	var button := panel.find_child(node_name, true, false) as Button
	_check(button != null, "missing button: %s" % node_name)
	if button != null:
		button.pressed.emit()


func _contains_all(text: String, fragments: Array[String]) -> bool:
	for fragment: String in fragments:
		if not text.contains(fragment):
			return false
	return true


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error(message)
