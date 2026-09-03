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

	var infrastructure_events: Array[Dictionary] = []
	var route_events: Array[Dictionary] = []
	var toggle_events: Array[Dictionary] = []
	var delete_events: Array[String] = []
	var session_continue_events: Array[String] = []
	var session_close_events: Array[String] = []
	_check(not panel.has_signal("station_requested"), "transport panel still exposes a second new-station session signal")
	_check(panel.find_child("TransportStationPager", true, false) == null, "transport panel still exposes a station pager")
	_check(panel.find_child("TransportStationSection", true, false) == null, "transport panel still exposes a station creation section")
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
	panel.session_continue_requested.connect(func() -> void: session_continue_events.append("continue"))
	panel.session_close_requested.connect(func() -> void: session_close_events.append("close"))

	_check_infrastructure_controls(panel)
	_check_route_mode_controls(panel)
	_check_readability(panel)

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
				"status": "disabled",
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
	_check(rail_status != null and rail_status.text == "已停駛", "player-disabled route status is not rendered")
	for status_label: Label in [metro_status, rail_status]:
		_check(
			status_label != null
			and status_label.autowrap_mode == TextServer.AUTOWRAP_OFF
			and status_label.custom_minimum_size.x >= 96.0,
			"route status can collapse into an unreadable vertical label"
		)
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
	_check(not snapshot.has("station_choices"), "transport panel debug surface still exposes new-station choices")
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

	panel.set_view_model({
		"planning_unlocked": true,
		"planning_session": {
			"id": "transport_plan_ui_1",
			"state": "network_placement",
			"mode": "train",
			"station_blueprint_name": "火車站",
			"station_refs": [
				{"job_id": "station_1", "status": "completed"},
				{"job_id": "station_2", "status": "active"},
			],
			"network_refs": [{"job_id": "track_1", "status": "active"}],
			"route_refs": [],
		},
		"routes": [],
	})
	await process_frame
	var session_card := panel.find_child("TransportPlanningSessionCard", true, false) as PanelContainer
	var session_status := panel.find_child("TransportPlanningSessionStatus", true, false) as Label
	var session_detail := panel.find_child("TransportPlanningSessionDetail", true, false) as Label
	var session_continue := panel.find_child("TransportPlanningSessionContinue", true, false) as Button
	var session_close := panel.find_child("TransportPlanningSessionClose", true, false) as Button
	var infrastructure_section := panel.find_child("TransportInfrastructureSection", true, false) as PanelContainer
	var operations_section := panel.find_child("TransportOperationsSection", true, false) as PanelContainer
	var route_list_section := panel.find_child("TransportRouteListSection", true, false) as PanelContainer
	var sections_ready := infrastructure_section != null and operations_section != null and route_list_section != null
	_check(sections_ready, "transport planning sections are missing")
	_check(session_card != null and session_card.visible, "active planning session summary is not visible")
	_check(session_status != null and session_status.text.contains("火車站") and session_status.text.contains("2/3"), "session summary omits its player-facing station or phase")
	_check(session_status != null and not session_status.text.contains("transport_plan_ui_1"), "session summary exposes an internal planning identity to the player")
	_check(session_detail != null and _contains_all(session_detail.text, ["火車站", "站點 2", "完工 1", "路網工程 1"]), "session summary omits authoritative reference counts")
	_check(session_continue != null and not session_continue.disabled and session_continue.text.contains("規劃路線"), "network session does not expose the explicit route-step CTA")
	_check(session_close != null and not session_close.disabled, "active session does not expose explicit close")
	_check(infrastructure_section != null and infrastructure_section.visible, "network phase hides its required infrastructure controls")
	_check(operations_section != null and not operations_section.visible, "network phase still exposes the unrelated route step")
	_check(route_list_section != null and not route_list_section.visible, "active network phase is diluted by the historical route list")
	_press(panel, "TransportPlanningSessionContinue")
	_press(panel, "TransportPlanningSessionClose")
	_check(session_continue_events == ["continue"] and session_close_events == ["close"], "session CTAs did not emit their explicit commands")
	var heavy_rail_add := panel.find_child("InfrastructureAdd_heavy_rail", true, false) as Button
	var rail_signal_add := panel.find_child("InfrastructureAdd_rail_signal", true, false) as Button
	var metro_add := panel.find_child("InfrastructureAdd_metro_track", true, false) as Button
	_check(heavy_rail_add != null and not heavy_rail_add.disabled, "train session cannot add its guideway")
	_check(rail_signal_add != null and not rail_signal_add.disabled, "train session cannot add mode-compatible rail signals")
	_check(metro_add == null, "train session still renders cross-mode metro infrastructure")
	_check(panel.find_child("PlanRoute_train", true, false) is Button, "train session hides its matching route card")
	_check(panel.find_child("PlanRoute_bus", true, false) == null, "train session still renders a foreign bus route card")
	panel.set_view_model({
		"planning_unlocked": true,
		"planning_session": {
			"id": "transport_plan_air_1",
			"state": "network_placement",
			"mode": "air",
			"station_blueprint_name": "機場",
			"station_refs": [{"job_id": "airport_1", "status": "completed"}],
			"network_refs": [],
			"route_refs": [],
		},
		"routes": [],
	})
	await process_frame
	var runway_add := panel.find_child("InfrastructureAdd_runway", true, false) as Button
	var taxiway_add := panel.find_child("InfrastructureAdd_taxiway", true, false) as Button
	var road_add := panel.find_child("InfrastructureAdd_road", true, false) as Button
	_check(runway_add != null and not runway_add.disabled, "air session cannot add its runway guideway")
	_check(taxiway_add != null and not taxiway_add.disabled, "air session cannot add taxiway in the same network phase")
	_check(road_add == null, "air session still renders a cross-mode road project")
	_check(panel.find_child("PlanRoute_air", true, false) is Button, "air session hides its matching route card")
	_check(panel.find_child("PlanRoute_train", true, false) == null, "air session still renders a foreign train route card")
	_check_mode_scoped_catalogs(panel)

	panel.set_view_model({
		"planning_unlocked": true,
		"planning_session": {
			"id": "transport_plan_ui_1",
			"state": "waiting_construction",
			"mode": "train",
			"station_blueprint_name": "火車站",
			"station_refs": [{"job_id": "station_1", "status": "active"}],
			"network_refs": [],
			"route_refs": [],
		},
		"routes": [],
	})
	await process_frame
	_check(session_continue.disabled and session_continue.text.contains("等待施工"), "waiting session exposes a premature continue command")
	_check(sections_ready and not infrastructure_section.visible and not operations_section.visible and not route_list_section.visible, "waiting phase exposes controls the player cannot use")

	panel.set_view_model({"planning_unlocked": false, "routes": []})
	await process_frame
	var plan_action := panel.find_child("PlanRoute_bus", true, false) as Button
	var empty_label := panel.find_child("TransportRouteEmpty", true, false) as Label
	_check(panel.find_child("StationAction_bus_station", true, false) == null, "locked planning resurrected a station creation action")
	_check(plan_action != null and plan_action.disabled, "locked planning still allows route creation")
	_check(empty_label != null and empty_label.visible, "empty route state is not rendered")
	_check(sections_ready and infrastructure_section.visible and operations_section.visible and route_list_section.visible, "inactive planning does not restore the network and route surfaces")
	_check(int(panel.debug_snapshot().get("route_count", -1)) == 0, "route cards were not cleared with an empty snapshot")
	_check(panel.find_child("InfrastructureAdd_road", true, false) is Button and panel.find_child("InfrastructureAdd_runway", true, false) is Button, "inactive management surface does not restore all infrastructure modes")
	_check(panel.find_child("PlanRoute_bus", true, false) is Button and panel.find_child("PlanRoute_air", true, false) is Button, "inactive management surface does not restore all route modes")

	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Transport planning panel test passed. Checks=%d" % _checks)
	await TestCleanup.finish(self, [panel], exit_code)


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


func _check_mode_scoped_catalogs(panel: Control) -> void:
	var expected_infrastructure := {
		"bus": ["road", "bus_depot"],
		"metro": ["metro_track", "metro_depot"],
		"train": ["rail_track", "rail_depot", "rail_signal"],
		"air": ["runway", "taxiway"],
	}
	for mode: String in ["bus", "metro", "train", "air"]:
		panel.set_view_model({
			"planning_unlocked": true,
			"planning_session": {
				"id": "transport_mode_scope_%s" % mode,
				"workflow": "route_package_v1" if mode != "air" else "",
				"state": "network_placement",
				"mode": mode,
				"station_blueprint_name": {"bus": "公車站", "metro": "捷運站", "train": "火車站", "air": "機場"}[mode],
				"station_refs": [],
				"network_refs": [],
				"route_refs": [],
			},
			"routes": [],
		})
		var snapshot: Dictionary = panel.debug_snapshot()
		var actual_infrastructure: Array = snapshot.get("scoped_infrastructure_choice_ids", [])
		var actual_routes: Array = snapshot.get("scoped_route_mode_ids", [])
		_check(actual_infrastructure == expected_infrastructure[mode], "%s session infrastructure catalog leaked another mode: %s" % [mode, actual_infrastructure])
		_check(actual_routes == [mode], "%s session route catalog leaked another mode: %s" % [mode, actual_routes])
		for foreign_mode: String in ["bus", "metro", "train", "air"]:
			var route_button := panel.find_child("PlanRoute_%s" % foreign_mode, true, false) as Button
			_check((route_button != null) == (foreign_mode == mode), "%s session rendered the wrong route card: %s" % [mode, foreign_mode])


func _check_progressive_groups(snapshot: Dictionary) -> void:
	var groups_variant: Variant = snapshot.get("progressive_groups", {})
	_check(groups_variant is Dictionary, "debug snapshot does not expose progressive groups")
	if not groups_variant is Dictionary:
		return
	var groups := groups_variant as Dictionary
	for expected_name: String in ["TransportInfrastructurePager", "TransportRouteModePager", "TransportRoutePager"]:
		_check(groups.has(expected_name), "missing progressive group: %s" % expected_name)
	_check(not groups.has("TransportStationPager"), "progressive groups still expose a station pager")
	for group_name: Variant in groups:
		var group_variant: Variant = groups[group_name]
		if not group_variant is Dictionary:
			_check(false, "invalid progressive group snapshot: %s" % group_name)
			continue
		var group := group_variant as Dictionary
		_check(int(group.get("visible_choice_count", 0)) <= 3, "progressive group displays more than three choices: %s" % group_name)
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
