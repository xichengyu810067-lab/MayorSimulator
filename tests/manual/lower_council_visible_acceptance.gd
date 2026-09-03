extends SceneTree

const OUTPUT_PREFIX := "--lower-council-output-dir="
const RESULT_FILENAME := "lower-council-result.json"
const HEARING_CAPTURE_FILENAME := "lower-council-hearing-native.png"
const FINAL_CAPTURE_FILENAME := "lower-council-final-vote-native.png"
const SAVE_PATH := "user://mayor_simulator/tests/lower_council_visible_acceptance.json"
const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")

var output_dir := ""
var failed := false
var main


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(OUTPUT_PREFIX):
			output_dir = argument.trim_prefix(OUTPUT_PREFIX)
	if output_dir.is_empty() or not DirAccess.dir_exists_absolute(output_dir):
		_fail("missing existing --lower-council-output-dir")
		return
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name().to_lower() == "headless":
		_fail("native acceptance requires a visible display driver")
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	await _settle(12)
	var window_mode := DisplayServer.window_get_mode()
	if window_mode not in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]:
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

	var vote_history_before: int = main.vertical_slice.governance.lower_council_database.vote_history.size()
	main._submit_bill("環境保護法案")
	var pending: Dictionary = main.vertical_slice.governance.pending_bill
	var decision_day := int(pending.get("decision_day", -1))
	if decision_day < main.vertical_slice.game_day():
		_fail("bill submission did not create a valid decision day")
		return
	var hearing_events: Array[Dictionary] = main.vertical_slice.advance_days(
		decision_day - main.vertical_slice.game_day(),
		_supportive_context(),
		false
	)
	main._consume_vertical_events(hearing_events)
	main._update_ui()
	main.municipal_overlay.open_page("governance")
	await _settle(12)
	var stage = main.lower_council_stage
	if stage == null:
		_fail("actual Main did not create LowerCouncilStage")
		return
	stage.select_response_for_test(0)
	await _settle(8)
	var hearing_signature: Dictionary = stage.debug_signature()
	if not _validate_hearing(hearing_signature):
		return
	if main.vertical_slice.governance.lower_council_database.vote_history.size() != vote_history_before:
		_fail("read-only hearing preview mutated authoritative vote history")
		return
	var autosaves_before_confirmation: int = main._autosave_count
	var hearing_capture := _capture_native(HEARING_CAPTURE_FILENAME, "hearing_preview")
	if hearing_capture.is_empty():
		return

	stage.confirm_response_for_test()
	var final_signature: Dictionary = {}
	for _frame in range(240):
		await process_frame
		final_signature = stage.debug_signature()
		if (
			main.vertical_slice.governance.pending_bill.is_empty()
			and int(final_signature.get("vote_reveal_step_count", 0)) == 30
			and int(final_signature.get("revealed_seat_count", 0)) == 30
			and not bool(final_signature.get("animation_running", true))
		):
			break
	if not _validate_final(final_signature, autosaves_before_confirmation, vote_history_before):
		return
	await _settle(6)
	var final_capture := _capture_native(FINAL_CAPTURE_FILENAME, "final_vote")
	if final_capture.is_empty():
		return
	if str(hearing_capture.get("sha256", "")) == str(final_capture.get("sha256", "")):
		_fail("hearing and final-vote captures are visually identical")
		return

	var result := {
		"schema_version": 1,
		"suite": "mayor-simulator-lower-council-actual-main-native-visible-acceptance",
		"status": "PASS",
		"actual_main": true,
		"scene": "res://scenes/Main.tscn",
		"scene_parent": "root_window",
		"capture_surface_kind": "native_fullscreen_root",
		"source": _source_identity(),
		"display_server": DisplayServer.get_name(),
		"window_mode": DisplayServer.window_get_mode(),
		"window_size": _v2i(DisplayServer.window_get_size()),
		"hearing": {
			"seat_count": int(hearing_signature.get("seat_count", 0)),
			"majority_threshold": int(hearing_signature.get("majority_threshold", 0)),
			"authority_contract_valid": bool(hearing_signature.get("authority_contract_valid", false)),
			"response_option_count": int(hearing_signature.get("response_option_count", 0)),
			"selected_response_id": str(hearing_signature.get("selected_response_id", "")),
			"readonly_preview": bool(hearing_signature.get("readonly_preview", false)),
			"preview_votes_for": int(hearing_signature.get("preview_votes_for", 0)),
			"preview_votes_against": int(hearing_signature.get("preview_votes_against", 0)),
			"columns": int(hearing_signature.get("columns", 0)),
		},
		"formal_vote": {
			"autosave_delta": main._autosave_count - autosaves_before_confirmation,
			"autosave_reason": str(main._last_autosave_reason),
			"vote_history_delta": main.vertical_slice.governance.lower_council_database.vote_history.size() - vote_history_before,
			"animation_generation": int(final_signature.get("animation_generation", 0)),
			"animation_steps": int(final_signature.get("vote_reveal_step_count", 0)),
			"revealed_seat_count": int(final_signature.get("revealed_seat_count", 0)),
			"animation_running": bool(final_signature.get("animation_running", true)),
			"decision_signature": str(final_signature.get("decision_signature", "")),
		},
		"captures": [hearing_capture, final_capture],
	}
	var result_file := FileAccess.open(output_dir.path_join(RESULT_FILENAME), FileAccess.WRITE)
	if result_file == null:
		_fail("failed to open lower-council result file")
		return
	result_file.store_string(JSON.stringify(result, "\t"))
	result_file.close()
	print("LOWER_COUNCIL_NATIVE_VISIBLE_ACCEPTANCE_PASSED captures=2 seats=30 threshold=16 autosave_delta=1 vote_history_delta=30 actual_main=true")
	await TestCleanup.finish(self, [main], 0)


func _validate_hearing(signature: Dictionary) -> bool:
	if (
		not bool(signature.get("visible", false))
		or str(signature.get("stage_state", "")) != "hearing"
		or not bool(signature.get("background_loaded", false))
		or int(signature.get("seat_count", 0)) != 30
		or int(signature.get("rendered_seat_count", 0)) != 30
		or int(signature.get("majority_threshold", 0)) != 16
		or not bool(signature.get("authority_contract_valid", false))
		or int(signature.get("response_option_count", 0)) != 3
		or str(signature.get("selected_response_id", "")).is_empty()
		or not bool(signature.get("readonly_preview", false))
		or bool(signature.get("confirm_disabled", true))
		or main.governance_catalog_title.visible
		or main.governance_status_tabs.visible
	):
		_fail("authoritative hearing/preview contract failed: %s" % signature)
		return false
	return true


func _validate_final(signature: Dictionary, autosaves_before: int, vote_history_before: int) -> bool:
	var autosave_delta: int = main._autosave_count - autosaves_before
	var vote_history_delta: int = main.vertical_slice.governance.lower_council_database.vote_history.size() - vote_history_before
	if (
		not main.vertical_slice.governance.pending_bill.is_empty()
		or autosave_delta != 1
		or not str(main._last_autosave_reason).begins_with("event:bill_")
		or vote_history_delta != 30
		or int(signature.get("seat_count", 0)) != 30
		or str(signature.get("stage_state", "")) != "final_vote"
		or int(signature.get("majority_threshold", 0)) != 16
		or not bool(signature.get("authority_contract_valid", false))
		or int(signature.get("vote_reveal_step_count", 0)) != 30
		or int(signature.get("revealed_seat_count", 0)) != 30
		or int(signature.get("animation_generation", 0)) < 1
		or bool(signature.get("animation_running", true))
		or str(signature.get("decision_signature", "")).is_empty()
	):
		_fail("formal vote/autosave/animation contract failed: signature=%s autosave_delta=%d vote_history_delta=%d" % [signature, autosave_delta, vote_history_delta])
		return false
	return true


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


func _supportive_context() -> Dictionary:
	return {
		"public_support": 72,
		"economic_health": 64,
		"budget_health": 61,
		"environment_health": 43,
		"feasibility": 58,
		"regional_support": {"north": 70, "east": 66, "south": 74, "west": 68},
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
	push_error("Lower council actual-Main native visible acceptance failed: %s" % message)
	quit(1)
