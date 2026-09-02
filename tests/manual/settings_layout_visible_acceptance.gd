extends SceneTree

const OUTPUT_PREFIX := "--settings-layout-output-dir="
const RESULT_FILENAME := "settings-layout-result.json"
const CAPTURE_FILENAME := "settings-layout-actual-main-native.png"
const SAVE_PATH := "user://mayor_simulator/tests/settings_layout_visible_acceptance.json"
const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")

var output_dir := ""
var failed := false
var main


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(OUTPUT_PREFIX):
			output_dir = argument.trim_prefix(OUTPUT_PREFIX)
	if output_dir.is_empty() or not DirAccess.dir_exists_absolute(output_dir):
		_fail("missing existing output directory")
		return
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name().to_lower() == "headless":
		_fail("native acceptance requires a Windows display driver")
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
	if not main._game_started or main.start_screen.visible:
		_fail("new game did not reach the actual Main map")
		return
	if main.tutorial_overlay != null and main.tutorial_overlay.is_open():
		main.tutorial_overlay.skip_button.emit_signal("pressed")
		await _settle(6)

	main.settings_button.emit_signal("pressed")
	await _settle(12)
	if not main.settings_overlay.is_open():
		_fail("actual ActionDock settings button did not open settings")
		return
	var layout := _validate_layout()
	if layout.is_empty():
		return
	main._set_hint("驗收：設定頁採緊湊對齊列；配樂與音效的開關、滑桿及百分比均共用基準線。", false)
	await _settle(8)
	var capture := _capture_native()
	if capture.is_empty():
		return
	var result := {
		"schema_version": 1,
		"suite": "mayor-simulator-settings-layout-actual-main-native-visible-acceptance",
		"status": "PASS",
		"contract_validated": true,
		"actual_main": true,
		"scene": "res://scenes/Main.tscn",
		"capture_surface_kind": "native_fullscreen_root",
		"source": {
			"worktree": OS.get_environment("MAYOR_ACCEPTANCE_WORKTREE"),
			"branch": OS.get_environment("MAYOR_ACCEPTANCE_BRANCH"),
			"head": OS.get_environment("MAYOR_ACCEPTANCE_HEAD"),
			"tree": OS.get_environment("MAYOR_ACCEPTANCE_TREE"),
			"dirty": OS.get_environment("MAYOR_ACCEPTANCE_DIRTY") == "true",
			"status_sha256": OS.get_environment("MAYOR_ACCEPTANCE_STATUS_SHA256"),
			"fingerprint": OS.get_environment("MAYOR_ACCEPTANCE_SOURCE_FINGERPRINT"),
		},
		"settings": layout,
		"captures": [capture],
	}
	var result_file := FileAccess.open(output_dir.path_join(RESULT_FILENAME), FileAccess.WRITE)
	if result_file == null:
		_fail("failed to open result file")
		return
	result_file.store_string(JSON.stringify(result, "\t"))
	result_file.close()
	print("SETTINGS_LAYOUT_NATIVE_VISIBLE_ACCEPTANCE_PASSED captures=1 compact=true aligned=true actual_main=true")
	await TestCleanup.finish(self, [main], 0)


func _validate_layout() -> Dictionary:
	var overlay = main.settings_overlay
	var panel := overlay.find_child("SettingsPanel", true, false) as PanelContainer
	var content := overlay.find_child("SettingsContent", true, false) as VBoxContainer
	var tutorial_row := overlay.find_child("TutorialSettingsRow", true, false) as HBoxContainer
	var music_row := overlay.find_child("MusicVolumeRow", true, false) as HBoxContainer
	var sfx_row := overlay.find_child("SfxVolumeRow", true, false) as HBoxContainer
	if panel == null or content == null or tutorial_row == null or music_row == null or sfx_row == null:
		_fail("actual settings compact rows are incomplete")
		return {}
	var panel_rect := panel.get_global_rect()
	var viewport_rect := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var music_slider_rect: Rect2 = overlay.music_volume_slider.get_global_rect()
	var sfx_slider_rect: Rect2 = overlay.sfx_volume_slider.get_global_rect()
	var music_percent_rect: Rect2 = overlay.music_volume_label.get_global_rect()
	var sfx_percent_rect: Rect2 = overlay.sfx_volume_label.get_global_rect()
	var aligned := (
		is_equal_approx(music_slider_rect.position.x, sfx_slider_rect.position.x)
		and is_equal_approx(music_slider_rect.end.x, sfx_slider_rect.end.x)
		and is_equal_approx(music_percent_rect.position.x, sfx_percent_rect.position.x)
		and is_equal_approx(music_percent_rect.end.x, sfx_percent_rect.end.x)
	)
	if (
		not viewport_rect.encloses(panel_rect)
		or panel.custom_minimum_size != Vector2(680, 432)
		or panel_rect.size.y < 420.0 or panel_rect.size.y > 460.0
		or panel_rect.end.y - tutorial_row.get_global_rect().end.y > 24.0
		or not aligned
		or overlay.language_selector.choice_count() != 5
	):
		_fail("actual settings layout contract failed")
		return {}
	return {
		"panel_minimum_size": [680, 432],
		"panel_rect": str(panel_rect),
		"content_separation": content.get_theme_constant("separation"),
		"volume_axes_aligned": aligned,
		"language_choice_count": overlay.language_selector.choice_count(),
		"bottom_blank_extent": panel_rect.end.y - tutorial_row.get_global_rect().end.y,
	}


func _capture_native() -> Dictionary:
	var image := root.get_texture().get_image()
	if image.is_empty():
		_fail("native root capture is empty")
		return {}
	var path := output_dir.path_join(CAPTURE_FILENAME)
	if image.save_png(path) != OK:
		_fail("failed to save settings layout capture")
		return {}
	var size := image.get_size()
	return {
		"filename": CAPTURE_FILENAME,
		"surface_kind": "native_fullscreen_root",
		"width": size.x,
		"height": size.y,
		"bytes": FileAccess.get_file_as_bytes(path).size(),
		"sha256": FileAccess.get_sha256(path).to_lower(),
	}


func _settle(frames: int) -> void:
	for _frame in frames:
		await process_frame


func _fail(message: String) -> void:
	if failed:
		return
	failed = true
	push_error("Settings layout actual-Main acceptance failed: %s" % message)
	quit(1)
