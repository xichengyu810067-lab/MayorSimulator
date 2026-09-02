extends SceneTree

const OUTPUT_PREFIX := "--fiscal-draft-output-dir="
const RESULT_FILENAME := "fiscal-draft-result.json"
const CAPTURE_FILENAME := "fiscal-draft-actual-main-native.png"
const SAVE_PATH := "user://mayor_simulator/tests/fiscal_draft_visible_acceptance.json"
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
	var finance_button := main.municipal_overlay.find_child("FinanceButton", true, false) as Button
	if finance_button == null:
		_fail("actual municipal hub has no finance destination")
		return
	finance_button.emit_signal("pressed")
	await _settle(8)
	if main.municipal_overlay.current_page() != "finance":
		_fail("actual municipal finance card did not open finance")
		return

	var authority_tax := int(main.tax_rates["income"])
	var authority_water := int(main.utility_fees["water"])
	var authority_stadium := int(main.service_fees["stadium"])
	main.call("_on_tax_changed", float(authority_tax + 3), "income")
	main.call("_on_utility_fee_changed", float(authority_water + 7), "water")
	main.call("_on_service_fee_changed", float(authority_stadium + 9), "stadium")
	await _settle(10)
	var state: Dictionary = main.call("debug_fiscal_draft_state")
	var layout := _validate_draft_layout(state, authority_tax, authority_water, authority_stadium)
	if layout.is_empty():
		return
	main._set_hint("驗收：可連續調整多項、即時比較整組預估，再選擇一次套用或全部放棄。", false)
	await _settle(8)
	var capture := _capture_native()
	if capture.is_empty():
		return

	var autosaves_before := int(main._autosave_count)
	main.fiscal_apply_button.emit_signal("pressed")
	await _settle(6)
	var applied: Dictionary = main.call("debug_fiscal_draft_state")
	if (
		int(main.tax_rates["income"]) != authority_tax + 3
		or int(main.utility_fees["water"]) != authority_water + 7
		or int(main.service_fees["stadium"]) != authority_stadium + 9
		or int(main._autosave_count) != autosaves_before + 1
		or int(applied.get("dirty_count", -1)) != 0
	):
		_fail("apply-all did not atomically commit the visible draft exactly once")
		return

	var result := {
		"schema_version": 1,
		"suite": "mayor-simulator-fiscal-draft-actual-main-native-visible-acceptance",
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
		"fiscal_draft": layout,
		"apply_all": {"committed_count": 3, "autosave_count": 1, "dirty_after_apply": 0},
		"captures": [capture],
	}
	var result_file := FileAccess.open(output_dir.path_join(RESULT_FILENAME), FileAccess.WRITE)
	if result_file == null:
		_fail("failed to open result file")
		return
	result_file.store_string(JSON.stringify(result, "\t"))
	result_file.close()
	print("FISCAL_DRAFT_NATIVE_VISIBLE_ACCEPTANCE_PASSED captures=1 draft=3 apply_once=true actual_main=true")
	await TestCleanup.finish(self, [main], 0)


func _validate_draft_layout(state: Dictionary, authority_tax: int, authority_water: int, authority_stadium: int) -> Dictionary:
	var apply_button := main.find_child("FiscalApplyAllButton", true, false) as Button
	var discard_button := main.find_child("FiscalDiscardButton", true, false) as Button
	var status := main.find_child("FiscalDraftStatus", true, false) as Label
	var forecast_panel := main.find_child("FiscalForecastPanel", true, false) as PanelContainer
	var overlay_rect: Rect2 = main.municipal_overlay.get_global_rect()
	if apply_button == null or discard_button == null or status == null or forecast_panel == null:
		_fail("finance draft controls are incomplete")
		return {}
	var controls_visible := apply_button.is_visible_in_tree() and discard_button.is_visible_in_tree() and status.is_visible_in_tree()
	var controls_inside := overlay_rect.encloses(apply_button.get_global_rect()) and overlay_rect.encloses(discard_button.get_global_rect())
	if (
		int(state.get("dirty_count", -1)) != 3
		or int(main.tax_rates["income"]) != authority_tax
		or int(main.utility_fees["water"]) != authority_water
		or int(main.service_fees["stadium"]) != authority_stadium
		or not status.text.contains("3")
		or not apply_button.text.contains("3")
		or apply_button.disabled
		or discard_button.disabled
		or not controls_visible
		or not controls_inside
		or int(state.get("projected_net", 0)) == int(state.get("authoritative_net", 0))
	):
		_fail("visible finance draft contract failed")
		return {}
	return {
		"dirty_count": 3,
		"authority_unchanged_before_apply": true,
		"whole_draft_forecast_changed": true,
		"status_text": status.text,
		"apply_text": apply_button.text,
		"actions_visible": controls_visible,
		"actions_inside_overlay": controls_inside,
		"forecast_panel_rect": str(forecast_panel.get_global_rect()),
	}


func _capture_native() -> Dictionary:
	var image := root.get_texture().get_image()
	if image.is_empty():
		_fail("native root capture is empty")
		return {}
	var path := output_dir.path_join(CAPTURE_FILENAME)
	if image.save_png(path) != OK:
		_fail("failed to save fiscal draft capture")
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
	push_error("Fiscal draft actual-Main acceptance failed: %s" % message)
	quit(1)
