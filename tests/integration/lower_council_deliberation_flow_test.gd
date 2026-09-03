extends SceneTree

const GovernanceSystem := preload("res://scripts/systems/governance/governance_system.gd")
const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const TEST_SAVE_PATH := "user://mayor_simulator/tests/lower_council_deliberation_flow.json"

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_authoritative_hearing_lifecycle()
	await _test_main_stage_and_single_autosave()
	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Lower council deliberation flow test passed.")
	await TestCleanup.finish(self, [], exit_code)


func _test_authoritative_hearing_lifecycle() -> void:
	var governance = GovernanceSystem.new(20_260_903)
	var submitted: Dictionary = governance.submit_bill("environment_act", 0)
	_check(bool(submitted.get("ok", false)), "bill submission enters authoritative review")
	var decision_day := int(submitted.get("pending_bill", {}).get("decision_day", -1))
	var history_before: int = governance.lower_council_database.vote_history.size()
	var events: Array[Dictionary] = governance.advance_day(decision_day, _supportive_context())
	_check(events.size() == 1 and str(events[0].get("type", "")) == "lower_house_hearing_ready", "decision day opens a hearing instead of resolving the bill")
	_check(str(governance.pending_bill.get("status", "")) == "awaiting_mayor_response", "pending bill waits for one mayor response")
	_check(governance.legislative_history.is_empty() and governance.active_laws.is_empty() and governance.rejected_bills.is_empty(), "hearing does not create a terminal legislative result")
	_check(governance.lower_council_database.vote_history.size() == history_before, "initial vote preview does not mutate vote history")
	var hearing: Dictionary = governance.pending_bill.get("lower_house_hearing", {})
	var initial_vote: Dictionary = hearing.get("initial_vote", {})
	var options: Array = hearing.get("response_options", [])
	_check(int(hearing.get("seat_count", 0)) == 30 and int(hearing.get("majority_threshold", 0)) == 16, "hearing exposes 30 seats and a 16-vote majority")
	_check((initial_vote.get("votes", []) as Array).size() == 30, "initial preview exposes every lower-house seat")
	_check(not str(hearing.get("primary_question", "")).is_empty(), "hearing exposes the primary council question")
	_check(options.size() == 3, "hearing exposes exactly three evidence-based mayor responses")
	var option_signatures := {}
	for option_variant: Variant in options:
		var option: Dictionary = option_variant
		var response_id := str(option.get("id", ""))
		var preview: Dictionary = governance.preview_lower_house_response(response_id)
		_check(bool(preview.get("ok", false)) and bool(preview.get("readonly", false)), "response '%s' has a read-only final-vote preview" % response_id)
		_check((preview.get("votes", []) as Array).size() == 30 and int(preview.get("majority_threshold", 0)) == 16, "response '%s' preview reconciles the chamber" % response_id)
		_check(governance.lower_council_database.vote_history.size() == history_before, "response '%s' preview does not mutate vote history" % response_id)
		option_signatures[str(preview.get("model_input_signature", ""))] = true
	_check(option_signatures.size() == 3, "each mayor response supplies distinct debate evidence to the vote model")

	var selected_response := str((options[0] as Dictionary).get("id", ""))
	var resolved: Dictionary = governance.answer_lower_house_hearing(selected_response, decision_day)
	_check(bool(resolved.get("ok", false)), "one mayor response conducts the formal final vote")
	_check(governance.pending_bill.is_empty() and governance.legislative_history.size() == 1, "formal response closes pending review into existing legislative history")
	_check(governance.lower_council_database.vote_history.size() == history_before + 30, "formal final vote persists exactly 30 member votes")
	var decision: Dictionary = governance.legislative_history[0]
	_check(str(decision.get("mayor_response", {}).get("id", "")) == selected_response, "terminal decision records the selected evidence response")
	_check((decision.get("final_vote", {}).get("votes", []) as Array).size() == 30, "terminal decision uses the existing 30-member model")
	var duplicate: Dictionary = governance.answer_lower_house_hearing(selected_response, decision_day)
	_check(not bool(duplicate.get("ok", true)) and governance.lower_council_database.vote_history.size() == history_before + 30, "mayor response cannot be applied twice")

	var reload_source = GovernanceSystem.new(20_260_904)
	var reload_submit: Dictionary = reload_source.submit_bill("transit_act", 3)
	var reload_day := int(reload_submit.get("pending_bill", {}).get("decision_day", -1))
	reload_source.advance_day(reload_day, _supportive_context())
	var restored = GovernanceSystem.create_from_dict(JSON.parse_string(JSON.stringify(reload_source.to_dict())))
	_check(int(restored.to_dict().get("schema_version", 0)) == 3, "optional hearing state keeps Governance schema 3")
	_check(str(restored.pending_bill.get("status", "")) == "awaiting_mayor_response", "awaiting hearing survives existing serialization")
	var restored_history_before: int = restored.lower_council_database.vote_history.size()
	var restored_options: Array = restored.pending_bill.get("lower_house_hearing", {}).get("response_options", [])
	var restored_preview: Dictionary = restored.preview_lower_house_response(str((restored_options[1] as Dictionary).get("id", "")))
	_check(bool(restored_preview.get("ok", false)) and restored.lower_council_database.vote_history.size() == restored_history_before, "reloaded preview remains read-only")


func _test_main_stage_and_single_autosave() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(3)
	main.start_save_path = TEST_SAVE_PATH
	main.start_screen.animation_duration = 0.01
	main.start_screen.new_game_button.emit_signal("pressed")
	for _frame in range(120):
		await process_frame
		if not main.start_screen.is_loading():
			break
	_check(main._game_started, "actual Main enters a playable city")
	main._submit_bill("環境保護法案")
	var decision_day := int(main.vertical_slice.governance.pending_bill.get("decision_day", -1))
	var days_due: int = decision_day - main.vertical_slice.game_day()
	var events: Array[Dictionary] = main.vertical_slice.advance_days(days_due, _supportive_context(), false)
	main._consume_vertical_events(events)
	main._update_ui()
	main.municipal_overlay.open_page("governance")
	await _settle(3)
	var stage = main.lower_council_stage
	var signature: Dictionary = stage.debug_signature()
	_check(bool(signature.get("visible", false)), "governance page shows the actual lower-council stage while awaiting response")
	_check(not main.governance_catalog_title.visible and not main.governance_status_tabs.visible, "active hearing replaces the legacy policy catalog in the first viewport")
	_check(bool(signature.get("background_loaded", false)), "stage loads the chamber background directly without importer metadata")
	_check(int(signature.get("seat_count", 0)) == 30 and int(signature.get("majority_threshold", 0)) == 16, "stage displays authoritative 30 seats and threshold 16")
	_check(int(signature.get("rendered_seat_count", 0)) == 30 and bool(signature.get("authority_contract_valid", false)), "stage validates authority values against its 30-seat visual contract")
	_check(int(signature.get("visible_portrait_count", 0)) == 30 and float(signature.get("seat_surface_max_alpha", 1.0)) <= 0.23, "stage keeps 30 portraits visible without an opaque seat wash")
	_check(_seat_grid_is_bounded(stage, signature), "hearing seat grid stays between the top bar and action tray inside the stage: %s" % signature)
	_check(int(signature.get("response_option_count", 0)) == 3 and not bool(signature.get("readonly_preview", true)), "stage exposes three responses before any read-only preview is selected")
	_check(not bool(signature.get("root_is_scroll_container", true)), "1280x720 governance root is not a vertical ScrollContainer")
	_check(stage.find_children("*", "ScrollContainer", true, false).is_empty(), "1280x720 hearing has no nested vertical scroller")
	var page_host := main.municipal_overlay.find_child("PageHost", true, false) as Control
	_check(page_host != null and page_host.get_global_rect().encloses(stage.get_global_rect()), "1280x720 hearing stage stays inside the actual Municipal PageHost")
	if page_host != null:
		for response_button: Button in stage.response_buttons:
			var target_rect := response_button.get_global_rect().intersection(page_host.get_global_rect())
			_check(target_rect.size.x >= 44.0 and target_rect.size.y >= 44.0, "1280x720 hearing response exposes a 44x44 target")
		var confirm_rect: Rect2 = stage.confirm_button.get_global_rect().intersection(page_host.get_global_rect())
		_check(confirm_rect.size.x >= 44.0 and confirm_rect.size.y >= 44.0, "1280x720 formal confirmation exposes a 44x44 target")
	var original_scene_size: Vector2 = stage._scene.size
	stage._scene.size = Vector2(720, 350)
	stage._layout_scene()
	_check(int(stage.debug_signature().get("columns", 0)) == 6, "narrow lower-council stage uses six seat columns")
	stage._scene.size = Vector2(1000, 350)
	stage._layout_scene()
	_check(int(stage.debug_signature().get("columns", 0)) == 10, "wide lower-council stage uses ten seat columns")
	stage._scene.size = original_scene_size
	stage._layout_scene()
	var first_hearing_pending: Dictionary = main.vertical_slice.governance.pending_bill.duplicate(true)
	var first_bill_id := str(first_hearing_pending.get("bill_id", ""))
	var first_bill_definition: Dictionary = main.vertical_slice.governance.bill_definitions.get(first_bill_id, {}).duplicate(true)
	var authority_history_before: int = main.vertical_slice.governance.lower_council_database.vote_history.size()
	stage.select_response_for_test(0)
	await _settle(2)
	var preview_signature: Dictionary = stage.debug_signature()
	var first_preview: Dictionary = stage._latest_preview.duplicate(true)
	_check(bool(preview_signature.get("readonly_preview", false)), "selecting a response exposes a read-only final-vote preview")
	_check(main.vertical_slice.governance.lower_council_database.vote_history.size() == authority_history_before, "UI response selection only previews and does not persist votes")
	var autosaves_before: int = main._autosave_count
	stage.confirm_response_for_test()
	await _settle(4)
	_check(main._autosave_count == autosaves_before + 1, "successful response uses the existing Main autosave exactly once")
	_check(str(main._last_autosave_reason).begins_with("event:bill_"), "successful response uses the existing legislative event autosave path")
	_check(main.vertical_slice.governance.pending_bill.is_empty(), "UI confirmation formally resolves the authoritative pending bill")
	var final_signature: Dictionary = stage.debug_signature()
	_check(int(final_signature.get("vote_reveal_step_count", 0)) == 30 and int(final_signature.get("animation_generation", 0)) >= 1, "stage schedules an observable 30-seat vote reveal tween")
	_check(not bool(final_signature.get("catalog_visible", true)) and not bool(final_signature.get("catalog_header_visible", true)), "final vote excludes catalog content from the chamber")
	_check(int(final_signature.get("vote_color_group_count", 0)) >= 2, "formal vote exposes distinguishable result color groups")
	_check(_seat_grid_is_bounded(stage, final_signature), "formal vote seat grid stays between the top bar and result tray inside the stage: %s" % final_signature)
	stage.refresh(first_hearing_pending, first_bill_definition, {})
	var second_hearing_reset: Dictionary = stage.debug_signature()
	_check(bool(second_hearing_reset.get("response_row_visible", false)) and bool(second_hearing_reset.get("confirm_visible", false)), "same-option second hearing restores the response row and confirm button after a final result")
	_check(str(second_hearing_reset.get("selected_response_id", "")).is_empty() and not bool(second_hearing_reset.get("readonly_preview", true)), "same-option second hearing clears the previous selection and preview")
	_check(bool(second_hearing_reset.get("confirm_disabled", false)), "same-option second hearing requires a fresh response")
	stage.set_preview(first_preview)
	var second_hearing_answerable: Dictionary = stage.debug_signature()
	_check(bool(second_hearing_answerable.get("readonly_preview", false)) and not bool(second_hearing_answerable.get("confirm_disabled", true)), "same-option second hearing can accept a fresh preview and enable confirmation")
	main.queue_free()
	await process_frame


func _supportive_context() -> Dictionary:
	return {
		"public_support": 72,
		"economic_health": 64,
		"budget_health": 61,
		"environment_health": 43,
		"feasibility": 58,
		"regional_support": {"north": 70, "east": 66, "south": 74, "west": 68},
	}


func _settle(frames: int = 2) -> void:
	for _index in range(frames):
		await process_frame


func _seat_grid_is_bounded(stage, signature: Dictionary) -> bool:
	var top_rect := signature.get("top_rect", Rect2()) as Rect2
	var tray_rect := signature.get("tray_rect", Rect2()) as Rect2
	var seat_grid_rect := signature.get("seat_grid_rect", Rect2()) as Rect2
	return (
		seat_grid_rect.position.y >= top_rect.end.y + 7.0
		and seat_grid_rect.end.y <= tray_rect.position.y - 7.0
		and Rect2(Vector2.ZERO, stage.size).encloses(seat_grid_rect)
	)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Lower council deliberation flow check failed: %s" % message)
