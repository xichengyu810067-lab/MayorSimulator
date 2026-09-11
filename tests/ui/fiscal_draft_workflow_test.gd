extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const FiscalScrollContract := preload("res://tests/helpers/fiscal_scroll_contract.gd")
const TEST_SAVE_PATH := "user://mayor_simulator/tests/fiscal_draft_workflow.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1440, 900)
	var main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.start_save_path = TEST_SAVE_PATH
	main.start_screen.animation_duration = 0.01
	main.start_screen.new_game_button.pressed.emit()
	for _frame in range(120):
		await process_frame
		if not main.start_screen.is_loading():
			break
	main.tutorial_overlay.close_as_completed(false)
	await process_frame

	main.tax_rates["income"] = int(main.TAX_DEFS["income"]["reasonable"]) + 3
	main.utility_fees["water"] = int(main.UTILITY_DEFS["water"]["reasonable"]) + 7
	var original_tax: Dictionary = main.tax_rates.duplicate(true)
	var original_utility: Dictionary = main.utility_fees.duplicate(true)
	var original_service: Dictionary = main.service_fees.duplicate(true)
	var main_source := FileAccess.get_file_as_string("res://scripts/app/main.gd")
	_check(not main_source.contains("tax_rates = _fiscal_draft_tax_rates"), "draft projection never replaces authoritative tax values, even temporarily")
	_check(not main_source.contains("utility_fees = _fiscal_draft_utility_fees"), "draft projection never replaces authoritative utility values, even temporarily")
	_check(not main_source.contains("service_fees = _fiscal_draft_service_fees"), "draft projection never replaces authoritative service values, even temporarily")
	var municipal_overlay = main.call("_ensure_municipal_overlay")
	municipal_overlay.open_page("finance")
	await process_frame

	var initial: Dictionary = main.call("debug_fiscal_draft_state")
	_check(str(initial.get("flow_step", "")) == "edit", "finance opens in EDIT")
	_check(int(initial.get("dirty_count", -1)) == 0, "opening finance starts with a clean draft")
	_check(main.find_child("FiscalCategoryTabs", true, false) == null, "finance excludes legacy nested tabs")
	_check(main.find_children("FiscalCategoryCard_*", "Button", true, false).size() == 6, "EDIT exposes exactly six fiscal categories")
	var initial_preview := main.find_child("FiscalDraftPreview", true, false) as Control
	_check(initial_preview != null and not initial_preview.is_visible_in_tree(), "EDIT hides the complete preview surface")
	var preview_button := main.find_child("FiscalPreviewButton", true, false) as Button
	_check(preview_button != null and preview_button.disabled, "EDIT has one disabled preview action before a change")
	var category_grid := main.find_child("FiscalCategoryCardGrid", true, false) as GridContainer
	_check(preview_button != null and category_grid != null and preview_button.get_index() < category_grid.get_index(), "EDIT presents the primary preview action before the six category cards")
	var scroll_contract: Dictionary = await FiscalScrollContract.validate(self, main.municipal_overlay, null, FiscalScrollContract.expected_slider_names(main))
	_check(bool(scroll_contract.get("ok", false)), "EDIT keeps every custom fiscal control reachable: %s" % str(scroll_contract.get("errors", [])))

	var resident_card := main.find_child("FiscalCategoryCard_resident_tax", true, false) as Button
	if resident_card != null:
		resident_card.pressed.emit()
	await process_frame
	var reasonable_card := main.find_child("FiscalPlanCard_reasonable", true, false) as Button
	if reasonable_card != null:
		reasonable_card.pressed.emit()
	await process_frame
	var utility_card := main.find_child("FiscalCategoryCard_utilities", true, false) as Button
	if utility_card != null:
		utility_card.pressed.emit()
	await process_frame
	if reasonable_card != null:
		reasonable_card.pressed.emit()
	await process_frame
	var income_slider := main.tax_sliders["income"] as HSlider
	income_slider.value = float(int(original_tax["income"]) + 4)
	main.call("_on_utility_fee_changed", float(int(original_utility["water"]) + 7), "water")
	main.call("_on_service_fee_changed", float(int(original_service["stadium"]) + 9), "stadium")
	var edited: Dictionary = main.call("debug_fiscal_draft_state")
	_check(main.tax_rates == original_tax and main.utility_fees == original_utility and main.service_fees == original_service, "EDIT mutations leave all three authority dictionaries unchanged")
	_check(int(edited.get("dirty_count", -1)) == 3, "three edits become one cross-category draft")
	_check(int(edited.get("projected_net", 0)) != int(edited.get("authoritative_net", 0)), "EDIT forecast uses the whole draft")
	_check(preview_button != null and not preview_button.disabled and preview_button.text.contains("3"), "EDIT exposes its sole primary preview action with the change count")
	_check(str(main.labels["tax_value_income"].text).contains("%d%% → %d%%" % [int(original_tax["income"]), int(original_tax["income"]) + 4]), "slider change updates the visible tax value from authority to draft")
	_check(str(main.labels["utility_water"].text).contains("%d" % (int(original_utility["water"]) + 7)), "utility header shows its draft value")
	_check(str(main.labels["service_stadium"].text).contains("%d" % (int(original_service["stadium"]) + 9)), "service header shows its draft value")

	var autosaves_before_preview := int(main._autosave_count)
	if preview_button != null:
		preview_button.pressed.emit()
	await process_frame
	var previewed: Dictionary = main.call("debug_fiscal_draft_state")
	var preview_ui: Dictionary = previewed.get("ui", {})
	_check(str(previewed.get("flow_step", "")) == "preview", "preview action enters PREVIEW")
	_check(int(main._autosave_count) == autosaves_before_preview, "EDIT to PREVIEW does not autosave")
	_check(main.tax_rates == original_tax and main.utility_fees == original_utility and main.service_fees == original_service, "PREVIEW keeps authority unchanged")
	_check(bool(preview_ui.get("preview_visible", false)) and not bool(preview_ui.get("edit_visible", true)), "PREVIEW and EDIT surfaces are mutually exclusive")
	_check(str(preview_ui.get("preview_changes", "")).contains("→") and not str(preview_ui.get("risk_text", "")).is_empty(), "PREVIEW shows old to new values and risk")
	var back_to_edit := main.find_child("FiscalBackToEditButton", true, false) as Button
	var execute := main.find_child("FiscalApplyAllButton", true, false) as Button
	_check(back_to_edit != null and execute != null and not execute.disabled and execute.text.contains("3"), "PREVIEW exposes return, discard, and execute actions")
	if back_to_edit != null:
		back_to_edit.pressed.emit()
	await process_frame
	var returned: Dictionary = main.call("debug_fiscal_draft_state")
	_check(str(returned.get("flow_step", "")) == "edit" and int(returned.get("dirty_count", -1)) == 3, "PREVIEW to EDIT retains the cross-category draft")
	_check(int(returned.get("tax", {}).get("income", -1)) == int(original_tax["income"]) + 4, "returning to EDIT retains the tax change")

	if preview_button != null:
		preview_button.pressed.emit()
	await process_frame
	var income_input := main.tax_inputs["income"] as LineEdit
	income_input.text_submitted.emit(str(int(original_tax["income"]) + 5))
	await process_frame
	_check(str(main.labels["tax_value_income"].text).contains("%d%% → %d%%" % [int(original_tax["income"]), int(original_tax["income"]) + 5]), "number input submission updates the visible tax draft value")
	_check(main.tax_rates == original_tax, "number input submission still leaves tax authority unchanged before execute")
	var stale_autosaves := int(main._autosave_count)
	if execute != null:
		execute.pressed.emit()
	await process_frame
	_check(main.tax_rates == original_tax and int(main._autosave_count) == stale_autosaves, "stale PREVIEW execute fails closed without authority or autosave changes")
	_check(str(Dictionary(main.call("debug_fiscal_draft_state")).get("flow_step", "")) == "preview", "stale execute remains in PREVIEW for an explicit return")
	if back_to_edit != null:
		back_to_edit.pressed.emit()
	await process_frame
	if preview_button != null:
		preview_button.pressed.emit()
	await process_frame
	var autosaves_before_execute := int(main._autosave_count)
	if execute != null:
		execute.pressed.emit()
	await process_frame
	var applied: Dictionary = main.call("debug_fiscal_draft_state")
	_check(int(main.tax_rates["income"]) == int(original_tax["income"]) + 5, "execute commits the tax snapshot")
	_check(int(main.utility_fees["water"]) == int(original_utility["water"]) + 7, "execute commits the utility snapshot")
	_check(int(main.service_fees["stadium"]) == int(original_service["stadium"]) + 9, "execute commits the service snapshot")
	_check(int(main._autosave_count) == autosaves_before_execute + 1, "execute performs exactly one autosave")
	_check(int(applied.get("dirty_count", -1)) == 0 and str(applied.get("flow_step", "")) == "edit", "successful execute returns to clean EDIT")
	_check(str(main.labels["tax_value_income"].text).contains("%d%%" % (int(original_tax["income"]) + 5)) and not str(main.labels["tax_value_income"].text).contains("→"), "execute collapses the visible tax value to the new authority")
	var autosaves_after_execute := int(main._autosave_count)
	if execute != null:
		execute.pressed.emit()
	await process_frame
	_check(int(main._autosave_count) == autosaves_after_execute, "repeated execute fails closed")

	main.call("_on_service_fee_changed", float(int(main.service_fees["stadium"]) + 4), "stadium")
	municipal_overlay.open_hub()
	await process_frame
	var left_page: Dictionary = main.call("debug_fiscal_draft_state")
	_check(int(left_page.get("dirty_count", -1)) == 0, "leaving finance discards an unapplied draft")
	_check(not main.call("_capture_player_shell_state").has("fiscal_draft"), "fiscal transient state is excluded from saves")

	if failures.is_empty():
		print("Fiscal draft workflow test passed.")
		await TestCleanup.finish(self, [main], 0)
	else:
		for failure in failures:
			push_error(failure)
		await TestCleanup.finish(self, [main], 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
