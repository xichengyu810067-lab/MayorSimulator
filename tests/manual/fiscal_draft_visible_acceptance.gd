extends SceneTree

const OUTPUT_PREFIX := "--fiscal-draft-output-dir="
const DARK_MODE_ARG := "--dark-mode=true"
const RESULT_FILENAME := "fiscal-draft-result.json"
const SAVE_PATH := "user://mayor_simulator/tests/fiscal_draft_visible_acceptance.json"
const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const SemanticPalette = preload("res://ui/theme/semantic_palette.gd")

var output_dir := ""
var failed := false
var main
var captures: Array[Dictionary] = []
var dark_mode_requested := false


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(OUTPUT_PREFIX):
			output_dir = argument.trim_prefix(OUTPUT_PREFIX)
		elif argument == DARK_MODE_ARG:
			dark_mode_requested = true
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
	main.start_screen.new_game_button.pressed.emit()
	for _frame in range(180):
		if main._game_started and not main.start_screen.visible:
			break
		await process_frame
	if not main._game_started or main.start_screen.visible:
		_fail("new game did not reach the actual Main map")
		return
	if main.tutorial_overlay != null and main.tutorial_overlay.is_open():
		main.tutorial_overlay.skip_button.pressed.emit()
		await _settle(6)
	if dark_mode_requested:
		main._set_theme(true, false)
		await _settle(12)
		if not main.is_dark_mode or not _validate_dark_contrast():
			_fail("actual Main did not enter a readable true dark mode")
			return
	main.municipal_button.pressed.emit()
	await _settle(4)
	var finance_button := main.municipal_overlay.find_child("FinanceButton", true, false) as Button
	if finance_button == null:
		_fail("actual municipal hub has no finance destination")
		return
	finance_button.pressed.emit()
	await _settle(8)
	if main.municipal_overlay.current_page() != "finance":
		_fail("actual municipal finance card did not open finance")
		return

	var categories_state := _validate_categories()
	if categories_state.is_empty():
		return
	if not await _capture_native("fiscal-categories-native.png"):
		return

	var authority_tax := int(main.tax_rates["income"])
	var authority_water := int(main.utility_fees["water"])
	var authority_stadium := int(main.service_fees["stadium"])
	if not await _open_custom("resident_tax"):
		return
	var income_slider := main.find_child("FiscalSlider_tax_income", true, false) as HSlider
	if income_slider == null:
		_fail("resident custom plan has no income slider")
		return
	income_slider.value = authority_tax + 3
	await _settle(5)
	if not await _capture_native("fiscal-custom-plan-native.png"):
		return
	if not await _open_custom("utilities"):
		return
	var water_slider := main.find_child("FiscalSlider_utility_water", true, false) as HSlider
	if water_slider == null:
		_fail("utility custom plan has no water slider")
		return
	water_slider.value = authority_water + 7
	await _settle(4)
	if not await _open_custom("education_leisure"):
		return
	var stadium_slider := main.find_child("FiscalSlider_service_stadium", true, false) as HSlider
	if stadium_slider == null:
		_fail("education custom plan has no stadium slider")
		return
	stadium_slider.value = authority_stadium + 9
	await _settle(8)
	var draft_state := _validate_draft(authority_tax, authority_water, authority_stadium)
	if draft_state.is_empty():
		return
	var preview_button := main.find_child("FiscalPreviewButton", true, false) as Button
	if preview_button == null:
		_fail("EDIT does not expose the preview action")
		return
	preview_button.pressed.emit()
	await _settle(5)
	if not _validate_preview():
		return
	if not await _capture_native("fiscal-draft-preview-native.png"):
		return

	var autosaves_before := int(main._autosave_count)
	main.fiscal_apply_button.pressed.emit()
	await _settle(8)
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
	if not await _capture_native("fiscal-applied-native.png"):
		return
	var dark_governance := {}
	if dark_mode_requested:
		dark_governance = await _capture_dark_governance()
		if dark_governance.is_empty():
			return

	var result := {
		"schema_version": 2,
		"suite": "mayor-simulator-fiscal-card-draft-actual-main-native-visible-acceptance",
		"status": "PASS",
		"actual_main": true,
		"scene": "res://scenes/Main.tscn",
		"capture_surface_kind": "native_fullscreen_root",
		"dark_mode": bool(main.is_dark_mode),
		"dark_contrast": _dark_contrast_signature() if dark_mode_requested else {},
		"source": {
			"worktree": OS.get_environment("MAYOR_ACCEPTANCE_WORKTREE"),
			"branch": OS.get_environment("MAYOR_ACCEPTANCE_BRANCH"),
			"head": OS.get_environment("MAYOR_ACCEPTANCE_HEAD"),
			"tree": OS.get_environment("MAYOR_ACCEPTANCE_TREE"),
			"dirty": OS.get_environment("MAYOR_ACCEPTANCE_DIRTY") == "true",
			"status_sha256": OS.get_environment("MAYOR_ACCEPTANCE_STATUS_SHA256"),
			"fingerprint": OS.get_environment("MAYOR_ACCEPTANCE_SOURCE_FINGERPRINT"),
		},
		"category_surface": categories_state,
		"draft_preview": draft_state,
		"apply_all": {"committed_count": 3, "autosave_delta": 1, "dirty_after_apply": 0},
		"dark_governance": dark_governance,
		"captures": captures,
	}
	var result_file := FileAccess.open(output_dir.path_join(RESULT_FILENAME), FileAccess.WRITE)
	if result_file == null:
		_fail("failed to open result file")
		return
	result_file.store_string(JSON.stringify(result, "\t"))
	result_file.close()
	print("FISCAL_DRAFT_NATIVE_VISIBLE_ACCEPTANCE_PASSED captures=%d categories=6 plans=3 draft=3 apply_once=true actual_main=true dark_mode=%s governance_capture=%d" % [captures.size(), str(main.is_dark_mode).to_lower(), 1 if dark_mode_requested else 0])
	await TestCleanup.finish(self, [main], 0)


func _capture_dark_governance() -> Dictionary:
	main._submit_bill("環境保護法案")
	var pending: Dictionary = main.vertical_slice.governance.pending_bill
	var decision_day := int(pending.get("decision_day", -1))
	if decision_day < main.vertical_slice.game_day():
		_fail("dark-mode governance setup did not create a valid decision day")
		return {}
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
		_fail("dark-mode Actual Main did not create the governance stage")
		return {}
	stage.select_response_for_test(0)
	await _settle(8)
	var signature: Dictionary = stage.debug_signature()
	if (
		not main.is_dark_mode
		or not bool(signature.get("dark_mode", false))
		or str(signature.get("stage_state", "")) != "hearing"
		or int(signature.get("visible_portrait_count", 0)) != 30
		or float(signature.get("seat_surface_max_alpha", 1.0)) > 0.23
		or bool(signature.get("catalog_visible", true))
		or bool(signature.get("catalog_header_visible", true))
	):
		_fail("dark-mode governance stage is not visibly exclusive/readable: %s" % signature)
		return {}
	if not await _capture_native("lower-council-dark-hearing-native.png"):
		return {}
	return {
		"stage_state": signature.get("stage_state", ""),
		"dark_mode": signature.get("dark_mode", false),
		"visible_portrait_count": signature.get("visible_portrait_count", 0),
		"seat_surface_max_alpha": signature.get("seat_surface_max_alpha", 1.0),
		"catalog_visible": signature.get("catalog_visible", true),
		"catalog_header_visible": signature.get("catalog_header_visible", true),
	}


func _validate_dark_contrast() -> bool:
	var signature := _dark_contrast_signature()
	return float(signature.get("primary_text_ratio", 0.0)) >= 4.5 and float(signature.get("primary_action_ratio", 0.0)) >= 4.5


func _dark_contrast_signature() -> Dictionary:
	return {
		"primary_text_ratio": SemanticPalette.contrast_ratio(SemanticPalette.color_for(true, "text_primary"), SemanticPalette.color_for(true, "surface_base")),
		"primary_action_ratio": SemanticPalette.contrast_ratio(SemanticPalette.color_for(true, "text_on_accent"), SemanticPalette.color_for(true, "action_primary")),
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


func _validate_categories() -> Dictionary:
	var state: Dictionary = main.call("debug_fiscal_draft_state")
	var ui: Dictionary = state.get("ui", {})
	var cards: Array[Node] = main.find_children("FiscalCategoryCard_*", "Button", true, false)
	var preview := main.find_child("FiscalDraftPreview", true, false) as PanelContainer
	if cards.size() != 6 or int(ui.get("category_count", 0)) != 6 or not bool(ui.get("category_surface_visible", false)):
		_fail("finance does not show the six-card category surface")
		return {}
	if preview == null or preview.is_visible_in_tree() or main.find_child("FiscalCategoryTabs", true, false) != null:
		_fail("EDIT must hide the whole-draft preview and exclude legacy nested tabs")
		return {}
	if str(state.get("flow_step", "")) != "edit" or not bool(ui.get("edit_visible", false)):
		_fail("finance must open in the EDIT surface")
		return {}
	if str(ui.get("preview_placement", "")) != "exclusive":
		_fail("finance must use an exclusive preview surface")
		return {}
	return {"category_count": 6, "ids": ui.get("category_ids", []), "preview_visible": false, "legacy_tabs_absent": true, "flow_step": state.get("flow_step", "")}


func _open_custom(category_id: String) -> bool:
	var back := main.find_child("FiscalBackToCategories", true, false) as Button
	var current_ui: Dictionary = Dictionary(main.call("debug_fiscal_draft_state")).get("ui", {})
	if bool(current_ui.get("plan_surface_visible", false)) and back != null:
		back.pressed.emit()
		await _settle(3)
	var category := main.find_child("FiscalCategoryCard_%s" % category_id, true, false) as Button
	var custom := main.find_child("FiscalPlanCard_custom", true, false) as Button
	if category == null or custom == null:
		_fail("missing category or custom plan card for %s" % category_id)
		return false
	category.pressed.emit()
	await _settle(3)
	custom.pressed.emit()
	await _settle(4)
	var state: Dictionary = main.call("debug_fiscal_draft_state")
	var ui: Dictionary = state.get("ui", {})
	if str(ui.get("selected_category", "")) != category_id or str(ui.get("selected_plan", "")) != "custom" or not bool(ui.get("custom_editor_visible", false)):
		_fail("custom plan did not become visible for %s" % category_id)
		return false
	return true


func _validate_draft(authority_tax: int, authority_water: int, authority_stadium: int) -> Dictionary:
	var state: Dictionary = main.call("debug_fiscal_draft_state")
	var ui: Dictionary = state.get("ui", {})
	var changes := main.find_child("FiscalDraftChangeList", true, false) as Label
	var risk := main.find_child("FiscalDraftRisk", true, false) as Label
	var preview_button := main.find_child("FiscalPreviewButton", true, false) as Button
	if (
		int(state.get("dirty_count", -1)) != 3
		or int(main.tax_rates["income"]) != authority_tax
		or int(main.utility_fees["water"]) != authority_water
		or int(main.service_fees["stadium"]) != authority_stadium
		or changes == null or not changes.text.contains("→")
		or risk == null or risk.text.is_empty()
		or preview_button == null or preview_button.disabled or not preview_button.text.contains("3")
		or int(state.get("projected_net", 0)) == int(state.get("authoritative_net", 0))
	):
		_fail("visible whole-draft preview contract failed")
		return {}
	return {
		"dirty_count": 3,
		"authority_unchanged_before_apply": true,
		"formal_to_draft_visible": true,
		"risk_visible": true,
		"income": state.get("projected_income", 0),
		"expense": state.get("projected_expense", 0),
		"net": state.get("projected_net", 0),
		"safety_buffer": state.get("projected_safety_buffer", 0),
		"preview_placement": ui.get("preview_placement", ""),
	}


func _validate_preview() -> bool:
	var state: Dictionary = main.call("debug_fiscal_draft_state")
	var ui: Dictionary = state.get("ui", {})
	var preview := main.find_child("FiscalDraftPreview", true, false) as PanelContainer
	var execute := main.find_child("FiscalApplyAllButton", true, false) as Button
	var return_to_edit := main.find_child("FiscalBackToEditButton", true, false) as Button
	if (
		str(state.get("flow_step", "")) != "preview"
		or preview == null or not preview.is_visible_in_tree()
		or bool(ui.get("edit_visible", true))
		or execute == null or execute.disabled or not execute.text.contains("3")
		or return_to_edit == null
	):
		_fail("PREVIEW must exclusively show complete impact and execution actions")
		return false
	return true


func _capture_native(filename: String) -> bool:
	await _settle(3)
	var image := root.get_texture().get_image()
	if image.is_empty():
		_fail("native root capture is empty")
		return false
	var path := output_dir.path_join(filename)
	if image.save_png(path) != OK:
		_fail("failed to save %s" % filename)
		return false
	var size := image.get_size()
	captures.append({"filename": filename, "surface_kind": "native_fullscreen_root", "width": size.x, "height": size.y, "bytes": FileAccess.get_file_as_bytes(path).size(), "sha256": FileAccess.get_sha256(path).to_lower()})
	return true


func _settle(frames: int) -> void:
	for _frame in frames:
		await process_frame


func _fail(message: String) -> void:
	if failed:
		return
	failed = true
	push_error("Fiscal draft actual-Main acceptance failed: %s" % message)
	quit(1)
