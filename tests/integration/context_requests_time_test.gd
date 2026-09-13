extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const SimulationClockScript = preload("res://scripts/core/simulation_clock.gd")
const TEST_SAVE_PATH := "user://mayor_simulator/tests/context_requests_autosave.json"

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1920, 1080)
	root.size = Vector2i(1920, 1080)
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await process_frame
	main.start_save_path = TEST_SAVE_PATH
	main.start_screen.animation_duration = 0.04
	main.start_screen.new_game_button.emit_signal("pressed")
	for _frame in range(120):
		await process_frame
		if not main.start_screen.is_loading():
			break
	_check(main.tutorial_overlay != null and main.tutorial_overlay.is_open(), "new game opens the story tutorial")
	main.tutorial_overlay.close_as_completed(false)
	await process_frame

	_test_two_minute_clock()
	_check(is_equal_approx(main.vertical_slice.session.clock.day_length_seconds, 120.0), "live session uses 120 real seconds per game day")

	var requests: Array = main.vertical_slice.get_view_model().get("citizen_requests", [])
	_check(requests.size() >= 2, "population system produces enough NPC requests to exercise both decisions")
	main.call("_open_municipal_center")
	main.municipal_overlay.call("open_page", "public_affairs")
	await process_frame
	await process_frame
	_check(main.public_affairs_panel._request_buttons.size() == requests.size(), "public-affairs page lists every request without selecting an NPC")
	if requests.size() >= 2:
		var accepted_id := str((requests[0] as Dictionary).get("request_id", ""))
		var rejected_id := str((requests[1] as Dictionary).get("request_id", ""))
		var initial_accept_button := main.public_affairs_panel._request_buttons.get(accepted_id) as Button
		var initial_reject_button := main.public_affairs_panel._reject_buttons.get(rejected_id) as Button
		_check(initial_accept_button != null and initial_reject_button != null, "pending cards expose both accept and reject actions")
		if initial_accept_button != null:
			initial_accept_button.emit_signal("pressed")
		await process_frame
		await process_frame
		var accepted_record: Dictionary = main.vertical_slice.population.requests[accepted_id].to_dict()
		_check(str(accepted_record.get("status", "")) == "accepted", "accept action updates the authoritative request")
		var accepted_button := main.public_affairs_panel._request_buttons.get(accepted_id) as Button
		_check(accepted_button != null and accepted_button.disabled and accepted_button.text == _localized("已受理"), "accepted request remains visible with exact accepted status")

		var reject_button := main.public_affairs_panel._reject_buttons.get(rejected_id) as Button
		if reject_button != null:
			reject_button.emit_signal("pressed")
		await process_frame
		await process_frame
		var rejected_record: Dictionary = main.vertical_slice.population.requests[rejected_id].to_dict()
		_check(str(rejected_record.get("status", "")) == "rejected", "reject action updates the authoritative request")
		_check(int(rejected_record.get("rejected_day", -1)) == main.vertical_slice.game_day(), "reject action records its game day")
		var rejected_status_button := main.public_affairs_panel._request_buttons.get(rejected_id) as Button
		_check(rejected_status_button != null and rejected_status_button.disabled and rejected_status_button.text == _localized("已拒絕"), "rejected request remains visible with exact rejected status")
		_check(str(main._last_autosave_reason) == "event:npc_request_rejected", "reject decision triggers the event autosave path")

		var completed_ids: Array[String] = main.vertical_slice.complete_requests({
			"park_count": 99,
			"hospital_count": 99,
			"school_count": 99,
			"utility_fee": 0,
		})
		_check(completed_ids.has(accepted_id), "accepted request completes when its condition becomes true")
		main.call("_consume_vertical_events", main.vertical_slice.drain_ui_events())
		await process_frame
		await process_frame
		var completed_record: Dictionary = main.vertical_slice.population.requests[accepted_id].to_dict()
		_check(str(completed_record.get("status", "")) == "completed", "completion updates the authoritative request")
		var completed_button := main.public_affairs_panel._request_buttons.get(accepted_id) as Button
		_check(completed_button != null and completed_button.disabled and completed_button.text == _localized("已完成"), "completed request remains visible with exact completed status")
		_check(main.public_affairs_panel._request_buttons.size() == requests.size(), "terminal request cards remain in public-affairs history")

	main.municipal_overlay.call("close_overlay")
	main.city_grid[18] = "住宅"
	main.building_customizations[18] = {"variant": 0, "roof": 0, "wall": 0}
	main.vertical_slice.register_existing_building(18, "住宅", main.building_customizations[18])
	main.call("_apply_building_effect", main.buildings["住宅"])
	main.call("_select_built_cell", 18)
	await process_frame
	var context = main.building_context_panel
	_check(context.visible, "clicking a building opens its local controls")
	_check(context._action_buttons.size() == 5, "local controls contain exactly five building actions")
	var before_variant := int((main.building_customizations[18] as Dictionary).get("variant", 0))
	(context._action_buttons["style"] as Button).emit_signal("pressed")
	await process_frame
	var after_variant := int((main.building_customizations[18] as Dictionary).get("variant", 0))
	_check(after_variant != before_variant, "style action changes the selected building rather than a global setting")

	main.vertical_slice.set_time_paused(true)
	var paused_day: int = int(main.vertical_slice.game_day())
	for _second in range(120):
		main.vertical_slice.process_frame(1.0)
	_check(main.vertical_slice.game_day() == paused_day, "an explicit terminal/start pause ignores wall-clock input")
	main.vertical_slice.set_time_paused(false)
	for _second in range(120):
		main.vertical_slice.process_frame(1.0)
	_check(main.vertical_slice.game_day() == paused_day + 1, "active simulation advances exactly one day after 120 seconds")
	main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not main.vertical_slice.is_time_paused(), "losing application focus keeps active-city time running")
	main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(not main.vertical_slice.is_time_paused(), "returning to the application preserves continuous time")

	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Building context, NPC requests, and automatic time test passed.")
	await TestCleanup.finish(self, [main], exit_code)


func _test_two_minute_clock() -> void:
	var clock = SimulationClockScript.new()
	for _second in range(119):
		_check(clock.consume_frame(1.0) == 0, "clock does not advance early")
	_check(clock.consume_frame(1.0) == 1, "clock advances on the 120th second")
	clock.paused = true
	for _second in range(120):
		_check(clock.consume_frame(1.0) == 0, "paused wall-clock input is ignored")
	_check(not clock.to_dict().has("last_os_timestamp"), "save data contains no offline catch-up timestamp")


func _localized(source: String) -> String:
	var l10n = root.get_node_or_null("L10n")
	return str(l10n.call("text", source)) if l10n != null else source


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Context/request/time check failed: %s" % message)
