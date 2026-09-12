extends SceneTree

const OUTPUT_PREFIX := "--building-catalog-balance-output-dir="
const RESULT_FILENAME := "building-catalog-balance-result.json"
const CAPTURE_FILENAME := "building-catalog-balance-actual-main-native.png"
const SAVE_PATH := "user://mayor_simulator/tests/building_catalog_balance_visible_acceptance.json"
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
	await _settle(4)
	var buildings_button := main.municipal_overlay.find_child("BuildingsButton", true, false) as Button
	if buildings_button == null:
		_fail("actual municipal hub has no buildings destination")
		return
	buildings_button.emit_signal("pressed")
	await _settle(8)
	if main.municipal_overlay.current_page() != "buildings":
		_fail("actual municipal buildings card did not open the catalog")
		return

	main._select_building_group("utilities")
	await _settle(8)
	var five_layout := _pager_layout("utilities")
	if not _validate_five_card_layout(five_layout):
		return
	var paging_proof := _validate_eight_card_paging()
	if paging_proof.is_empty():
		return
	main._select_building_group("utilities")
	await _settle(8)
	main._set_hint("驗收：建築圖卡依數量平衡排列；此頁五張採 3＋2，第二列置中，超過六張才翻頁。", false)
	await _settle(8)
	var capture := _capture_native()
	if capture.is_empty():
		return
	var result := {
		"schema_version": 1,
		"suite": "mayor-simulator-building-catalog-balance-actual-main-native-visible-acceptance",
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
		"catalog": {
			"page_size": 6,
			"five_card_layout": five_layout,
			"eight_card_paging": paging_proof,
			"distribution_contract": {"1": [1], "2": [2], "3": [3], "4": [2, 2], "5": [3, 2], "6": [3, 3]},
		},
		"captures": [capture],
	}
	var result_file := FileAccess.open(output_dir.path_join(RESULT_FILENAME), FileAccess.WRITE)
	if result_file == null:
		_fail("failed to open result file")
		return
	result_file.store_string(JSON.stringify(result, "\t"))
	result_file.close()
	print("BUILDING_CATALOG_BALANCE_NATIVE_VISIBLE_ACCEPTANCE_PASSED captures=1 five_cards=3+2 page_size=6 actual_main=true")
	await TestCleanup.finish(self, [main], 0)


func _pager_layout(group_id: String) -> Dictionary:
	var pager = main.building_card_pagers.get(group_id)
	return pager.debug_layout_state() if pager != null and pager.has_method("debug_layout_state") else {}


func _validate_five_card_layout(layout: Dictionary) -> bool:
	if (
		int(layout.get("choice_count", 0)) != 5
		or int(layout.get("visible_count", 0)) != 5
		or int(layout.get("page_size", 0)) != 6
		or Array(layout.get("row_counts", [])) != [3, 2]
		or not bool(layout.get("last_row_centered", false))
		or bool(layout.get("navigation_visible", true))
	):
		_fail("five-card catalog is not a centered 3+2 layout: %s" % layout)
		return false
	return true


func _validate_eight_card_paging() -> Dictionary:
	main._select_building_group("mobility")
	var pager = main.building_card_pagers.get("mobility")
	if pager == null:
		_fail("mobility building pager is unavailable")
		return {}
	pager.set_page(0)
	var first_page: Dictionary = pager.debug_layout_state()
	pager.set_page(1)
	var second_page: Dictionary = pager.debug_layout_state()
	if (
		int(first_page.get("choice_count", 0)) != 8
		or Array(first_page.get("row_counts", [])) != [3, 3]
		or not bool(first_page.get("navigation_visible", false))
		or Array(second_page.get("row_counts", [])) != [2]
		or bool(second_page.get("last_row_centered", true))
	):
		_fail("eight-card catalog does not page as 6 then 2")
		return {}
	pager.set_page(0)
	return {"choice_count": 8, "first_page_rows": [3, 3], "second_page_rows": [2], "navigation_visible": true}


func _capture_native() -> Dictionary:
	var image := root.get_texture().get_image()
	if image.is_empty():
		_fail("native root capture is empty")
		return {}
	var path := output_dir.path_join(CAPTURE_FILENAME)
	if image.save_png(path) != OK:
		_fail("failed to save building catalog capture")
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
	push_error("Building-catalog balance actual-Main acceptance failed: %s" % message)
	quit(1)
