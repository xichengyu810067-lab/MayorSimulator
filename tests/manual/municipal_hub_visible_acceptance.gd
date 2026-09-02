extends SceneTree

const OUTPUT_PREFIX := "--municipal-hub-output-dir="
const RESULT_FILENAME := "municipal-hub-result.json"
const CAPTURE_FILENAME := "municipal-hub-actual-main-native.png"
const SAVE_PATH := "user://mayor_simulator/tests/municipal_hub_visible_acceptance.json"
const EXPECTED_DESTINATIONS := [
	"buildings", "governance", "judicial", "oversight",
	"finance", "public_affairs", "city_data",
]
const EXPECTED_DOCK_LABELS := ["市政", "設定", "離開"]
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

	main.municipal_button.emit_signal("pressed")
	await _settle(12)
	if not main.municipal_overlay.is_open() or main.municipal_overlay.current_page() != "hub":
		_fail("the actual municipal ActionDock button did not open the hub")
		return
	var dock_labels := _dock_labels()
	if dock_labels != EXPECTED_DOCK_LABELS:
		_fail("ActionDock labels are not exactly 市政、設定、離開: %s" % dock_labels)
		return
	var layout: Dictionary = main.municipal_overlay.debug_hub_layout_state()
	if not _validate_layout(layout):
		return

	main._set_hint("驗收：右下角維持市政、設定、離開三鍵；市政中心七項服務皆可直接進入。", false)
	await _settle(12)
	var capture := _capture_native()
	if capture.is_empty():
		return
	var result := {
		"schema_version": 1,
		"suite": "mayor-simulator-municipal-hub-actual-main-native-visible-acceptance",
		"status": "PASS",
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
		"display_server": DisplayServer.get_name(),
		"window_mode": DisplayServer.window_get_mode(),
		"window_size": _v2i(DisplayServer.window_get_size()),
		"action_dock": {"button_count": dock_labels.size(), "labels": dock_labels},
		"municipal_hub": layout.duplicate(true),
		"captures": [capture],
	}
	var result_file := FileAccess.open(output_dir.path_join(RESULT_FILENAME), FileAccess.WRITE)
	if result_file == null:
		_fail("failed to open result file")
		return
	result_file.store_string(JSON.stringify(result, "\t"))
	result_file.close()
	print("MUNICIPAL_HUB_NATIVE_VISIBLE_ACCEPTANCE_PASSED captures=1 dock_buttons=3 direct_cards=7 actual_main=true")
	await TestCleanup.finish(self, [main], 0)


func _dock_labels() -> Array[String]:
	var labels: Array[String] = []
	var grid: Node = main.action_dock.find_child("ActionButtonRow", true, false)
	if grid == null:
		return labels
	for child in grid.get_children():
		if child is Button:
			labels.append(str(child.get_meta("semantic_label", "")))
	return labels


func _validate_layout(layout: Dictionary) -> bool:
	if int(layout.get("direct_card_count", 0)) != 7:
		_fail("municipal hub does not expose exactly seven direct cards")
		return false
	if Array(layout.get("destinations", [])) != EXPECTED_DESTINATIONS:
		_fail("municipal hub direct destinations changed: %s" % layout.get("destinations", []))
		return false
	if (
		int(layout.get("unique_destination_count", 0)) != 7
		or int(layout.get("filler_count", -1)) != 0
		or int(layout.get("intermediate_page_count", -1)) != 0
		or str(layout.get("featured_destination", "")) != "buildings"
		or int(layout.get("secondary_columns", 0)) != 2
		or int(layout.get("secondary_rows", 0)) != 3
		or not bool(layout.get("secondary_equal_heights", false))
		or float(layout.get("minimum_target_extent", 0.0)) < 72.0
	):
		_fail("municipal hub layout contract failed: %s" % layout)
		return false
	if str(layout.get("layout_mode", "")) == "wide":
		var width_ratio := float(layout.get("featured_width_ratio", 0.0))
		if width_ratio < 0.31 or width_ratio > 0.37 or not bool(layout.get("featured_spans_full_height", false)):
			_fail("wide municipal hub does not use the 1/3 featured + 2x3 layout")
			return false
	return true


func _capture_native() -> Dictionary:
	var image := root.get_texture().get_image()
	if image.is_empty():
		_fail("native root capture is empty")
		return {}
	var path := output_dir.path_join(CAPTURE_FILENAME)
	if image.save_png(path) != OK:
		_fail("failed to save municipal hub capture")
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


func _v2i(value: Variant) -> Array:
	return [int(value.x), int(value.y)]


func _settle(frames: int) -> void:
	for _index in range(frames):
		await process_frame


func _fail(message: String) -> void:
	if failed:
		return
	failed = true
	push_error("Municipal hub actual-Main acceptance failed: %s" % message)
	quit(1)
