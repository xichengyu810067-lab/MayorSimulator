extends SceneTree

const OUTPUT_PREFIX := "--courtroom-output-dir="
const RESULT_FILENAME := "courtroom-result.json"
const EMPTY_CAPTURE := "courtroom-empty-native.png"
const HEARING_CAPTURE := "courtroom-hearing-native.png"
const DEFENSE_CAPTURE := "courtroom-defense-native.png"
const SAVE_PATH := "user://mayor_simulator/tests/courtroom_visible_acceptance.json"
const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")

var output_dir := ""
var failed := false
var main


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(OUTPUT_PREFIX):
			output_dir = argument.trim_prefix(OUTPUT_PREFIX)
	if output_dir.is_empty() or not DirAccess.dir_exists_absolute(output_dir):
		_fail("missing existing --courtroom-output-dir")
		return
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name().to_lower() == "headless":
		_fail("native acceptance requires a visible display driver")
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	await _settle(12)
	var packed := load("res://scenes/Main.tscn") as PackedScene
	if packed == null:
		_fail("Main.tscn could not be loaded")
		return
	main = packed.instantiate()
	main.start_save_path = SAVE_PATH
	root.add_child(main)
	await _settle(12)
	main.start_screen.animation_duration = 0.04
	main.start_screen.new_game_button.emit_signal("pressed")
	for _frame in range(180):
		if main._game_started and not main.start_screen.visible:
			break
		await process_frame
	if not main._game_started:
		_fail("new game did not reach Main")
		return
	if main.tutorial_overlay != null and main.tutorial_overlay.is_open():
		main.tutorial_overlay.skip_button.emit_signal("pressed")
		await _settle(6)
	main.vertical_slice.set_time_paused(true)
	main.municipal_overlay.open_page("judicial")
	await _settle(10)
	var panel = main.judicial_panel
	var stage = panel._courtroom_stage
	if stage == null or not _check_layout(panel, stage):
		return
	stage.show_empty()
	var empty_capture := _capture(EMPTY_CAPTURE)
	if empty_capture.is_empty():
		return

	var justice = main.vertical_slice.governance.justice_system
	var opened: Dictionary = justice.open_judicial_case(
		"public_safety_act",
		main.vertical_slice.game_day(),
		64,
		"公共安全法案違法施行案"
	)
	if not bool(opened.get("ok", false)):
		_fail("could not seed judicial case")
		return
	var court_case: Dictionary = opened.get("case", {})
	var case_id := str(court_case.get("id", ""))
	justice.advance_judicial_procedures(int(court_case.get("hearing_day", 0)))
	panel.refresh(justice)
	await _settle(24)
	if str(justice.judicial_cases[case_id].get("procedural_stage", "")) != "hearing":
		_fail("judicial case did not reach hearing")
		return
	if stage._judges.modulate.a < 0.95 or stage._clerk.modulate.a < 0.95 or stage._defense.modulate.a < 0.95:
		_fail("courtroom hearing did not display all three actor layers")
		return
	var hearing_capture := _capture(HEARING_CAPTURE)
	if hearing_capture.is_empty():
		return

	var autosaves_before: int = main._autosave_count
	var defense: Dictionary = panel.submit_current_defense("safety_emergency")
	if not bool(defense.get("ok", false)):
		_fail("judicial defense did not submit")
		return
	await _settle(10)
	var autosave_delta: int = main._autosave_count - autosaves_before
	if autosave_delta != 1 or main._last_autosave_reason != "action:judicial_defense_submitted":
		_fail("judicial defense must autosave exactly once: delta=%d reason=%s" % [autosave_delta, main._last_autosave_reason])
		return
	if str(justice.judicial_cases[case_id].get("defense_template_id", "")) != "safety_emergency":
		_fail("accepted defense was not projected from judicial authority")
		return
	var defense_capture := _capture(DEFENSE_CAPTURE)
	if defense_capture.is_empty():
		return
	if str(empty_capture.get("sha256", "")) == str(hearing_capture.get("sha256", "")) or str(hearing_capture.get("sha256", "")) == str(defense_capture.get("sha256", "")):
		_fail("courtroom state captures are visually identical")
		return

	var result := {
		"status": "PASS",
		"actual_main": true,
		"scene": "res://scenes/Main.tscn",
		"case_id": case_id,
		"procedural_stage": "hearing",
		"procedure_stage_count": panel._procedure_labels.size(),
		"actor_layer_count": 3,
		"committee_capacity": 15,
		"root_vertical_scroll_count": 0,
		"autosave_delta": autosave_delta,
		"autosave_reason": main._last_autosave_reason,
		"captures": [empty_capture, hearing_capture, defense_capture],
		"source": _source_identity(),
	}
	var file := FileAccess.open(output_dir.path_join(RESULT_FILENAME), FileAccess.WRITE)
	if file == null:
		_fail("could not write courtroom evidence result")
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("COURTROOM_NATIVE_VISIBLE_ACCEPTANCE_PASSED captures=3 stages=5 actors=3 committee=15 autosave_delta=1 root_scroll=0 actual_main=true")
	await TestCleanup.finish(self, [main], 0)


func _check_layout(panel, stage) -> bool:
	var layout: Dictionary = panel.debug_layout_signature()
	if bool(layout.get("root_is_scroll_container", true)) or int(layout.get("positive_vertical_scroll_count", -1)) != 0:
		_fail("courtroom root still exposes positive vertical scrolling: %s" % layout)
		return false
	if float(layout.get("minimum_interactive_extent", 0.0)) < 44.0:
		_fail("courtroom has an interaction target below 44px: %s" % layout)
		return false
	if panel._procedure_labels.size() != 5 or not panel._summary_label.text.contains("15"):
		_fail("courtroom five-stage/15-member authority projection failed")
		return false
	var stage_signature: Dictionary = stage.debug_signature()
	if not bool(stage_signature.get("background_loaded", false)) or int(stage_signature.get("actor_layer_count", 0)) != 3:
		_fail("courtroom background/actor scene contract failed: %s" % stage_signature)
		return false
	return true


func _capture(filename: String) -> Dictionary:
	var image := root.get_texture().get_image()
	var path := output_dir.path_join(filename)
	if image.is_empty() or image.save_png(path) != OK:
		_fail("failed to save %s" % filename)
		return {}
	return {
		"filename": filename,
		"width": image.get_width(),
		"height": image.get_height(),
		"sha256": FileAccess.get_sha256(path).to_lower(),
		"bytes": FileAccess.get_file_as_bytes(path).size(),
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


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame


func _fail(message: String) -> void:
	if failed:
		return
	failed = true
	push_error("Courtroom actual-Main native visible acceptance failed: %s" % message)
	quit(1)
