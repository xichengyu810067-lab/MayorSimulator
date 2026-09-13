extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const SimulationClockScript := preload("res://scripts/core/simulation_clock.gd")
const VerticalSliceCoordinatorScript := preload("res://scripts/app/vertical_slice_coordinator.gd")
const TEST_SAVE_PATH := "user://mayor_simulator/tests/continuous_clock_modal_suppression.json"
const TEST_BATCH_SAVE_PATH := "user://mayor_simulator/tests/continuous_clock_modal_suppression_batch.json"
const TEST_STEPPED_SAVE_PATH := "user://mayor_simulator/tests/continuous_clock_modal_suppression_stepped.json"

const SUPPRESS_CONTEXT := {"suppress_new_resident_feedback": true}

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("CONTINUOUS_CLOCK_PHASE=clock")
	_test_clock_boundaries_and_roundtrip()
	print("CONTINUOUS_CLOCK_PHASE=authority")
	_test_authority_suppression()
	print("CONTINUOUS_CLOCK_PHASE=main")
	var main = await _create_started_main(TEST_SAVE_PATH)
	var batched_main = await _create_started_main(TEST_BATCH_SAVE_PATH)
	var stepped_main = await _create_started_main(TEST_STEPPED_SAVE_PATH)
	if main != null:
		_test_main_time_and_context(main, batched_main, stepped_main)
	var cleanup_nodes: Array = []
	for instance in [main, batched_main, stepped_main]:
		if instance != null:
			cleanup_nodes.append(instance)
	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Continuous clock and modal suppression test passed.")
	await TestCleanup.finish(self, cleanup_nodes, exit_code)


func _test_clock_boundaries_and_roundtrip() -> void:
	var clock = SimulationClockScript.new(120.0)
	_check(_clock_minutes(clock) == 0, "00:00 begins at minute zero")
	_check(clock.consume_frame(10.0) == 0, "ten real seconds remain in the same day")
	_check(_clock_minutes(clock) == 60, "ten real seconds render as 01:00 without a float-boundary minute")
	clock.reset()
	_check(clock.consume_frame(119.9) == 0, "119.9 seconds remain before the day boundary")
	_check(_clock_minutes(clock) == 719, "119.9 seconds clamp to 11:59 rather than 12:00")
	_check(clock.consume_frame(0.1) == 1 and _clock_minutes(clock) == 0, "120 seconds wrap to the next day at 00:00")
	clock.reset()
	_check(clock.consume_frame(240.0) == 2, "one open but throttled frame preserves two elapsed days")
	clock.accumulator_seconds = 37.5
	var snapshot: Dictionary = clock.to_dict()
	_check(snapshot.keys().size() == 3 and not snapshot.has("last_os_timestamp"), "clock save shape is unchanged and has no offline timestamp")
	var restored = SimulationClockScript.new()
	restored.restore(snapshot)
	_check(is_equal_approx(restored.accumulator_seconds, 37.5) and _clock_minutes(restored) == 225, "intra-day time restores without a schema field")


func _test_authority_suppression() -> void:
	var coordinator = VerticalSliceCoordinatorScript.new(20260913, 250000, 300)
	coordinator.governance.adjust_civic_metrics(7, 0)
	var grievance_before: int = int(coordinator.governance.grievance)
	var trust_before: int = int(coordinator.governance.municipal_trust)
	var events_before: int = coordinator.session.state.event_book.size()
	var suppressed_events: Array[Dictionary] = coordinator.advance_days(3, SUPPRESS_CONTEXT, false)
	_check(coordinator.population.active_requests().is_empty(), "three suppressed days create no authoritative NPC request")
	_check(coordinator.session.state.event_book.size() == events_before, "suppressed days emit no hidden request facts")
	_check(suppressed_events.all(func(event: Dictionary) -> bool: return str(event.get("type", "")) != "npc_request_created"), "suppressed days queue no request-created UI event")
	_check(not coordinator.last_city_context.has("suppress_new_resident_feedback"), "transient modal suppression is excluded from persisted city context")
	var npc_id := str(coordinator.population.records.keys()[0])
	coordinator.select_npc(npc_id, SUPPRESS_CONTEXT)
	_check(coordinator.population.active_requests().is_empty(), "NPC selection cannot bypass modal request suppression")
	var result: Dictionary = coordinator.settle_month({}, {"unfunded": 999999}, 999999, SUPPRESS_CONTEXT, false)
	_check(bool(result.get("ok", false)), "suppressed monthly settlement still completes")
	_check(int(coordinator.governance.grievance) == grievance_before, "monthly shortfalls preserve the existing grievance value while suppressed")
	_check(int(coordinator.governance.municipal_trust) == trust_before - 2, "monthly shortfalls retain both trust penalties while grievance is suppressed")
	var created: Array[Dictionary] = coordinator.refresh_requests({})
	_check(not created.is_empty() and created.size() <= 4 and coordinator.population.active_requests().size() == created.size(), "leaving all operation windows resumes the existing request generator once")
	var request_types: Dictionary = {}
	for request: Dictionary in coordinator.population.active_requests():
		request_types[str(request.get("request_type", ""))] = true
	_check(request_types.size() == coordinator.population.active_requests().size(), "resumed requests retain existing per-type deduplication without backfill")
	var accepted_request: Dictionary = created[0]
	coordinator.select_npc(str(accepted_request.get("npc_id", "")), SUPPRESS_CONTEXT)
	_check(coordinator.accept_selected_request(false), "an existing request remains actionable during an operation window")
	var completed: Array[String] = coordinator.complete_requests({
		"park_count": 99,
		"hospital_count": 99,
		"school_count": 99,
		"utility_fee": 0,
		"suppress_new_resident_feedback": true,
	})
	_check(completed.has(str(accepted_request.get("request_id", ""))), "an accepted request can complete while new requests remain suppressed")
	var normal_month = VerticalSliceCoordinatorScript.new(20260913, 250000, 300)
	normal_month.governance.adjust_civic_metrics(7, 0)
	var normal_trust_before := int(normal_month.governance.municipal_trust)
	normal_month.settle_month({}, {"unfunded": 999999}, 999999, {}, false)
	_check(int(normal_month.governance.grievance) == 11, "normal monthly generation resumes with exactly the current month's grievance increments")
	_check(int(normal_month.governance.municipal_trust) == normal_trust_before - 2, "normal monthly generation keeps the same trust penalties")


func _create_started_main(save_path: String):
	_cleanup_save(save_path)
	root.content_scale_size = Vector2i(1920, 1080)
	root.size = Vector2i(1920, 1080)
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await process_frame
	main.start_save_path = save_path
	main.start_screen.animation_duration = 0.04
	main.start_screen.new_game_button.emit_signal("pressed")
	for _frame in range(120):
		await process_frame
		if not main.start_screen.is_loading():
			break
	main.set_process(false)
	_check(main._game_started, "focused fixture enters an active city")
	return main


func _test_main_time_and_context(main, batched_main, stepped_main) -> void:
	main.call("_sync_time_pause_for_ui")
	_check(not main.vertical_slice.is_time_paused(), "story tutorial leaves active-city time running")
	main.vertical_slice.session.clock.accumulator_seconds = 10.0
	main.call("_refresh_time_hud")
	_check(main.labels["month"].text == "1/1．01:00", "date HUD uses fullwidth period and exact 12-hour clock")
	_check(main.labels["month"].tooltip_text.contains("每 120 秒"), "date tooltip describes continuous automatic time")
	main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not main.vertical_slice.is_time_paused(), "focus loss does not pause an active city")
	main.vertical_slice.session.clock.accumulator_seconds = 0.0
	var focus_day: int = int(main.vertical_slice.game_day())
	main.vertical_slice.process_frame(120.0, main.call("_vertical_city_context"), false)
	_check(main.vertical_slice.game_day() == focus_day + 1, "focus-out/minimized-sized delta advances the open city")
	main.call("_sync_vertical_state")
	main.call("_refresh_time_hud")
	_check(main.labels["month"].text == "1/2．00:00", "day rollover renders the next date at 00:00 rather than 12:00")

	main.tutorial_overlay.close_as_completed(false)
	main.call("_open_municipal_center")
	main.municipal_overlay.call("open_page", "blueprint")
	main.settings_overlay.open()
	main.call("_sync_time_pause_for_ui")
	var nested_context: Dictionary = main.call("_vertical_city_context")
	_check(not main.vertical_slice.is_time_paused(), "nested municipal/settings windows do not pause time")
	_check(bool(nested_context.get("suppress_new_resident_feedback", false)), "nested operation windows expose transient authority suppression")
	main.settings_overlay.close()
	var one_layer_context: Dictionary = main.call("_vertical_city_context")
	_check(bool(one_layer_context.get("suppress_new_resident_feedback", false)), "closing one nested layer keeps suppression while municipal remains")
	var request_ids_before: Array = main.vertical_slice.population.requests.keys()
	request_ids_before.sort()
	_check(not request_ids_before.is_empty(), "active city keeps its existing requests visible before the suppressed month")
	var page_before: String = str(main.municipal_overlay.current_page())
	var design_before: Dictionary = main.vertical_slice_panel.current_design_payload()
	var workers_before := int(main.vertical_slice_panel.selected_worker_count())
	var current_day: int = int(main.vertical_slice.game_day())
	var to_next_month: int = 30 - int(main.vertical_slice.current_date().get("day", 1)) + 1
	var events: Array[Dictionary] = main.vertical_slice.advance_days(to_next_month, one_layer_context, false)
	main.call("_consume_vertical_events", events, false)
	main.call("_sync_vertical_state")
	main.call("_update_ui")
	_check(main.vertical_slice.game_day() == current_day + to_next_month, "date and monthly rules advance while municipal work remains open")
	_check(main.municipal_overlay.is_open() and main.municipal_overlay.current_page() == page_before, "daily/monthly refresh preserves the selected municipal page")
	_check(main.vertical_slice_panel.current_design_payload() == design_before and int(main.vertical_slice_panel.selected_worker_count()) == workers_before, "daily/monthly refresh preserves the current building design and worker choice")
	var request_ids_after: Array = main.vertical_slice.population.requests.keys()
	request_ids_after.sort()
	_check(request_ids_after == request_ids_before, "suppressed daily and monthly refresh preserve every existing request without creating another")
	main.municipal_overlay.close_overlay()
	main.tutorial_overlay.hide()
	main.onboarding_guide.hide()
	_check(not bool(main.call("_vertical_city_context").get("suppress_new_resident_feedback", true)), "leaving every operation window restores normal feedback generation")
	_test_throttled_month_boundaries(batched_main, stepped_main)


func _test_throttled_month_boundaries(batched_main, stepped_main) -> void:
	if batched_main == null or stepped_main == null:
		_check(false, "month-boundary fixtures start before comparing throttled time")
		return
	var batched_autosave_guard_before := bool(batched_main._autosave_in_progress)
	var stepped_autosave_guard_before := bool(stepped_main._autosave_in_progress)
	for fixture in [batched_main, stepped_main]:
		fixture.tutorial_overlay.close_as_completed(false)
		fixture.tutorial_overlay.hide()
		fixture.onboarding_guide.hide()
		fixture.call("_sync_time_pause_for_ui")
		fixture.vertical_slice.session.submit_command("ledger_post", {
			"amount": 5_000_000,
			"reason_tag": "test.continuous_clock_funding",
			"source_id": "test",
			"metadata": {},
			"allow_overdraft": true,
		}, "test.continuous_clock_funding")
		# This focused case drives 65 individual boundaries per fixture. It covers
		# time and settlement ordering, while save I/O has its own dedicated gates.
		fixture._autosave_in_progress = true
		_check(not fixture.vertical_slice.is_time_paused(), "funded month-boundary fixture keeps the active city clock running")
		_check(fixture.funds >= 5_000_000, "funded month-boundary fixture cannot reach an unrelated fiscal terminal state")

	# One 65-day throttled frame crosses two monthly boundaries; the 15-second
	# remainder must survive after the final boundary rather than being capped.
	batched_main.call("_process", 65.0 * 120.0 + 15.0)
	for _day in range(65):
		stepped_main.call("_process", 120.0)
	stepped_main.call("_process", 15.0)
	batched_main._autosave_in_progress = batched_autosave_guard_before
	stepped_main._autosave_in_progress = stepped_autosave_guard_before

	var expected_settlements: Array[Dictionary] = [
		{"game_time": 30, "balance_after": _monthly_ledger_balance_at(batched_main, 30)},
		{"game_time": 60, "balance_after": _monthly_ledger_balance_at(batched_main, 60)},
	]
	var batched_settlements := _monthly_ledger_settlements(batched_main)
	var stepped_settlements := _monthly_ledger_settlements(stepped_main)
	_check(batched_main.vertical_slice.game_day() == 65 and batched_main.vertical_slice.current_date().get("month") == 3 and batched_main.vertical_slice.current_date().get("day") == 6, "a single delta of at least 31 days reaches the exact final calendar date")
	_check(is_equal_approx(batched_main.vertical_slice.session.clock.accumulator_seconds, 15.0), "throttled multi-month processing retains the 15-second intra-day remainder")
	_check(batched_main.labels["month"].text == "3/6．01:30", "throttled multi-month processing refreshes the final intra-day HUD time in the same frame")
	_check(batched_settlements == expected_settlements, "throttled multi-month settlement dates and intermediate balances remain ordered at days 30 then 60")
	_check(batched_settlements == stepped_settlements, "one throttled multi-month delta matches day-by-day settlement count, order, and intermediate finances")
	_check(batched_main.monthly_report_history.size() == 2 and stepped_main.monthly_report_history.size() == 2, "each crossed month creates exactly one report settlement")
	_check(not batched_main.call("_vertical_slice_has_terminal_failure"), "funded throttled fixture remains non-terminal after both monthly settlements")


func _monthly_ledger_settlements(main) -> Array[Dictionary]:
	var settlements_by_game_time: Dictionary = {}
	for entry: Dictionary in main.vertical_slice.session.state.ledger.get_entries():
		if str(entry.get("source_id", "")) == "city_monthly":
			settlements_by_game_time[int(entry.get("game_time", -1))] = int(entry.get("balance_after", 0))
	var game_times: Array = settlements_by_game_time.keys()
	game_times.sort()
	var settlements: Array[Dictionary] = []
	for game_time_variant in game_times:
		var game_time := int(game_time_variant)
		settlements.append({"game_time": game_time, "balance_after": int(settlements_by_game_time[game_time])})
	return settlements


func _monthly_ledger_balance_at(main, game_time: int) -> int:
	for settlement: Dictionary in _monthly_ledger_settlements(main):
		if int(settlement.get("game_time", -1)) == game_time:
			return int(settlement.get("balance_after", 0))
	return -1


func _clock_minutes(clock) -> int:
	if not clock.has_method("game_minutes_into_day"):
		_check(false, "clock exposes stable in-game minute projection")
		return -1
	return int(clock.call("game_minutes_into_day"))


func _cleanup_save(save_path: String) -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var absolute := ProjectSettings.globalize_path(save_path + suffix)
		if FileAccess.file_exists(absolute):
			DirAccess.remove_absolute(absolute)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Continuous clock check failed: %s" % message)
