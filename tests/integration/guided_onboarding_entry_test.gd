extends SceneTree

const IntroCinematicScript := preload("res://ui/tutorial/intro_cinematic.gd")
const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const TEST_SAVE_PATH := "user://mayor_simulator/tests/guided_onboarding_entry.json"

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_save()
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	_check(str(ProjectSettings.get_setting("application/run/main_scene", "")) == "res://scenes/Main.tscn", "project.godot enters the canonical Main scene")

	var first = _new_main()
	await _settle(3)
	_check(str(first.get_script().resource_path) == "res://scripts/app/main.gd", "Main.tscn uses the canonical main.gd")
	first.start_save_path = TEST_SAVE_PATH
	first.start_screen.animation_duration = 0.04
	first.start_screen.new_game_button.emit_signal("pressed")
	await _wait_for_loading(first)
	await _settle(3)
	_check(first.tutorial_overlay != null and first.tutorial_overlay.get_script() == IntroCinematicScript, "formal new-game entry owns IntroCinematic rather than TutorialStoryOverlay")
	_check(first.tutorial_overlay.name == "IntroCinematic" and first.tutorial_overlay.is_open(), "first entry visibly opens the fixed CG sequence")
	_check(first.tutorial_overlay.current_index == 0 and first.tutorial_overlay.PAGES.size() == 8, "first entry starts on shot one of eight")
	_check(first.tutorial_overlay.skip_button != null and first.tutorial_overlay.skip_button.visible, "the previously supported skip action remains available")
	_check(first.onboarding_progress.is_story_pending() and first.onboarding_progress.receipts().is_empty(), "CG presentation cannot create an authoritative receipt")
	_check(not first.onboarding_guide.is_open() and first.vertical_slice.is_time_paused(), "CG blocks the guide and pauses simulation until completion")

	first.tutorial_overlay.skip_button.emit_signal("pressed")
	await _settle(5)
	_check(not first.tutorial_overlay.is_open(), "skip closes the CG")
	_check(first.onboarding_progress.is_active() and first.onboarding_progress.current_target() == "build", "skip begins the same ordered nine-step guide at build")
	_check(first.onboarding_progress.receipts().is_empty(), "skip grants no build or later receipt")
	_check(first.onboarding_guide.is_open() and first.onboarding_guide.is_product_mode(), "build target receives the arrow and mask guide")
	_check(first.onboarding_guide.target_control() != null, "build guide binds a real visible product control")
	_check(not first.vertical_slice.is_time_paused(), "product guide does not freeze the game clock")
	_check(first.vertical_slice.has_save_game(TEST_SAVE_PATH), "story-to-guide transition is persisted for continue")

	await TestCleanup.release_fixtures(self, [first])
	var resumed = _new_main()
	await _settle(3)
	resumed.start_save_path = TEST_SAVE_PATH
	resumed.start_screen.set_continue_available(true)
	resumed.start_screen.animation_duration = 0.04
	resumed.start_screen.continue_game_button.emit_signal("pressed")
	await _wait_for_loading(resumed)
	await _settle(5)
	_check(resumed.onboarding_progress.is_active() and resumed.onboarding_progress.current_target() == "build", "continue restores the exact first actionable target")
	_check(resumed.onboarding_progress.receipts().is_empty(), "continue cannot synthesize receipts")
	_check(not resumed.tutorial_overlay.is_open(), "continue does not replay an already-seen CG")
	_check(resumed.onboarding_guide.is_open() and resumed.onboarding_guide.is_product_mode(), "continue restores the real target guide")

	resumed.call("_replay_tutorial")
	await _settle(3)
	_check(resumed.tutorial_overlay.is_open() and resumed.tutorial_overlay.current_index == 0, "settings replay reopens the CG from shot one")
	resumed.tutorial_overlay.skip_button.emit_signal("pressed")
	await _settle(3)
	_check(resumed.onboarding_progress.current_target() == "build" and resumed.onboarding_progress.receipts().is_empty(), "replay completion cannot reset, complete, or skip the authoritative guide")

	_cleanup_save()
	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Guided onboarding formal entry test passed.")
	await TestCleanup.finish(self, [resumed], exit_code)


func _new_main():
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main := packed.instantiate()
	root.add_child(main)
	return main


func _wait_for_loading(main) -> void:
	for _frame in range(120):
		await process_frame
		if not main.start_screen.is_loading():
			return
	_fail("loading animation did not finish within 120 frames")


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame


func _cleanup_save() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	for candidate in [absolute_path, absolute_path + ".tmp", absolute_path + ".bak"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _fail(message: String) -> void:
	_failed = true
	push_error("Guided onboarding entry check failed: %s" % message)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)
