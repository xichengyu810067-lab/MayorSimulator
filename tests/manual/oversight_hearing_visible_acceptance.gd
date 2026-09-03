extends SceneTree

const OUTPUT_PREFIX := "--oversight-hearing-output-dir="
const RESULT_FILENAME := "oversight-hearing-result.json"
const EMPTY_CAPTURE := "oversight-empty-native.png"
const QUESTION_CAPTURE := "oversight-questioning-native.png"
const DEFENSE_CAPTURE := "oversight-defense-native.png"
const SAVE_PATH := "user://mayor_simulator/tests/oversight_hearing_visible_acceptance.json"
const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")

var output_dir := ""
var failed := false
var main


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(OUTPUT_PREFIX):
			output_dir = argument.trim_prefix(OUTPUT_PREFIX)
	if output_dir.is_empty() or not DirAccess.dir_exists_absolute(output_dir):
		_fail("missing existing --oversight-hearing-output-dir")
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
	main.municipal_overlay.open_page("oversight")
	await _settle(10)
	var stage = main.oversight_panel._oversight_hearing_stage
	if stage == null:
		_fail("actual Main did not create OversightHearingStage")
		return
	if not _check_state(stage.debug_signature(), "empty", ""):
		return
	var empty_capture := _capture(EMPTY_CAPTURE)
	if empty_capture.is_empty():
		return
	var justice = main.vertical_slice.governance.justice_system
	var opened: Dictionary = justice.open_oversight_case("official_mayor", ["行政失職"], 65, main.vertical_slice.game_day() + 3)
	if not bool(opened.get("ok", false)):
		_fail("could not seed oversight case")
		return
	var case_id := str(opened.get("case", {}).get("id", ""))
	main.oversight_panel.refresh(justice)
	await _settle(10)
	if not _check_state(stage.debug_signature(), "questioning", case_id):
		return
	var question_capture := _capture(QUESTION_CAPTURE)
	if question_capture.is_empty():
		return
	var defense: Dictionary = main.oversight_panel.submit_current_defense("full_disclosure")
	if not bool(defense.get("ok", false)):
		_fail("oversight defense did not submit")
		return
	await _settle(10)
	if not _check_state(stage.debug_signature(), "defense_submitted", case_id):
		return
	var defense_capture := _capture(DEFENSE_CAPTURE)
	if defense_capture.is_empty():
		return
	if str(empty_capture.get("sha256", "")) == str(question_capture.get("sha256", "")) or str(question_capture.get("sha256", "")) == str(defense_capture.get("sha256", "")):
		_fail("oversight state captures are visually identical")
		return
	var file := FileAccess.open(output_dir.path_join(RESULT_FILENAME), FileAccess.WRITE)
	if file == null:
		_fail("could not write evidence result")
		return
	file.store_string(JSON.stringify({"status": "PASS", "actual_main": true, "scene": "res://scenes/Main.tscn", "case_id": case_id, "captures": [empty_capture, question_capture, defense_capture], "source": _source_identity()}, "\t"))
	file.close()
	print("OVERSIGHT_HEARING_NATIVE_VISIBLE_ACCEPTANCE_PASSED captures=3 actual_main=true")
	await TestCleanup.finish(self, [main], 0)


func _check_state(signature: Dictionary, expected_state: String, case_id: String) -> bool:
	if not bool(signature.get("visible", false)) or not bool(signature.get("background_loaded", false)) or str(signature.get("state", "")) != expected_state or (not case_id.is_empty() and str(signature.get("case_id", "")) != case_id):
		_fail("invalid stage state: %s" % signature)
		return false
	return true


func _capture(filename: String) -> Dictionary:
	var image := root.get_texture().get_image()
	var path := output_dir.path_join(filename)
	if image.is_empty() or image.save_png(path) != OK:
		_fail("failed to save %s" % filename)
		return {}
	return {"filename": filename, "sha256": FileAccess.get_sha256(path).to_lower(), "bytes": FileAccess.get_file_as_bytes(path).size()}


func _source_identity() -> Dictionary:
	return {"worktree": OS.get_environment("MAYOR_ACCEPTANCE_WORKTREE"), "branch": OS.get_environment("MAYOR_ACCEPTANCE_BRANCH"), "head": OS.get_environment("MAYOR_ACCEPTANCE_HEAD"), "tree": OS.get_environment("MAYOR_ACCEPTANCE_TREE")}


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame


func _fail(message: String) -> void:
	if failed:
		return
	failed = true
	push_error("Oversight hearing actual-Main native visible acceptance failed: %s" % message)
	quit(1)
