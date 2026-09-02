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
	main.tutorial_overlay._transition.custom_step(1.0)
	await process_frame

	# Start from non-recommended authoritative values so the category plan cards
	# have an observable draft-only effect.
	main.tax_rates["income"] = int(main.TAX_DEFS["income"]["reasonable"]) + 3
	main.utility_fees["water"] = int(main.UTILITY_DEFS["water"]["reasonable"]) + 7
	var original_tax: Dictionary = main.tax_rates.duplicate(true)
	var original_utility: Dictionary = main.utility_fees.duplicate(true)
	var original_service: Dictionary = main.service_fees.duplicate(true)
	main.municipal_overlay.open_page("finance")
	await process_frame
	var initial: Dictionary = main.call("debug_fiscal_draft_state")
	_check(int(initial.get("dirty_count", -1)) == 0, "opening finance starts with a clean draft")
	_check(main.find_child("FiscalCategoryTabs", true, false) == null, "finance removes the old nested fiscal TabContainer")
	var expected_categories := ["resident_tax", "industry_tax", "utilities", "environment_energy", "city_services", "education_leisure"]
	var category_cards: Array[Node] = main.find_children("FiscalCategoryCard_*", "Button", true, false)
	_check(category_cards.size() == 6, "finance exposes exactly six fiscal category cards")
	for category_id: String in expected_categories:
		var card := main.find_child("FiscalCategoryCard_%s" % category_id, true, false) as Button
		_check(card != null, "finance exposes category card %s" % category_id)
		if card != null:
			_check(card.custom_minimum_size.y >= 44.0, "category card %s preserves a 44px target" % category_id)
	var preview_panel := main.find_child("FiscalDraftPreview", true, false) as PanelContainer
	_check(preview_panel != null and preview_panel.is_visible_in_tree(), "whole-draft preview is persistently visible")
	var scroll_contract: Dictionary = await FiscalScrollContract.validate(
		self,
		main.municipal_overlay,
		null,
		FiscalScrollContract.expected_slider_names(main)
	)
	_check(bool(scroll_contract.get("ok", false)), "six-category card traversal keeps every custom control reachable: %s" % str(scroll_contract.get("errors", [])))
	var fiscal_scroll := main.find_child("稅率與公共事業費", true, false) as ScrollContainer
	if fiscal_scroll != null:
		fiscal_scroll.size = Vector2(900, fiscal_scroll.size.y)
		main.call("_layout_fiscal_surface", fiscal_scroll)
		var narrow_ui: Dictionary = Dictionary(main.call("debug_fiscal_draft_state")).get("ui", {})
		_check(int(narrow_ui.get("responsive_columns", 0)) == 1 and str(narrow_ui.get("preview_placement", "")) == "below", "narrow finance places the preview below the plan cards")
		_check(fiscal_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO, "narrow finance keeps the whole draft scrollable")
		fiscal_scroll.size = Vector2(1200, fiscal_scroll.size.y)
		main.call("_layout_fiscal_surface", fiscal_scroll)
		var wide_ui: Dictionary = Dictionary(main.call("debug_fiscal_draft_state")).get("ui", {})
		_check(int(wide_ui.get("responsive_columns", 0)) == 2 and str(wide_ui.get("preview_placement", "")) == "right", "wide finance keeps the preview in the right column")
	var initial_autosaves := int(main._autosave_count)
	var resident_card := main.find_child("FiscalCategoryCard_resident_tax", true, false) as Button
	if resident_card != null:
		resident_card.pressed.emit()
	await process_frame
	var plan_cards: Array[Node] = main.find_children("FiscalPlanCard_*", "Button", true, false)
	_check(plan_cards.size() == 3, "selected category exposes exactly three plan cards")
	for plan_id: String in ["current", "reasonable", "custom"]:
		var plan_card := main.find_child("FiscalPlanCard_%s" % plan_id, true, false) as Button
		_check(plan_card != null, "selected category exposes %s plan card" % plan_id)
		if plan_card != null:
			_check(plan_card.custom_minimum_size.y >= 44.0, "plan card %s preserves a 44px target" % plan_id)
	var reasonable_card := main.find_child("FiscalPlanCard_reasonable", true, false) as Button
	if reasonable_card != null:
		reasonable_card.pressed.emit()
	await process_frame
	var resident_recommended: Dictionary = main.call("debug_fiscal_draft_state")
	_check(int(resident_recommended.get("tax", {}).get("income", -1)) == int(main.TAX_DEFS["income"]["reasonable"]), "reasonable plan uses the existing income-tax definition")
	_check(main.tax_rates == original_tax, "reasonable plan selection does not mutate tax authority")
	_check(int(main._autosave_count) == initial_autosaves, "category and plan selection do not autosave")

	var utility_card := main.find_child("FiscalCategoryCard_utilities", true, false) as Button
	if utility_card != null:
		utility_card.pressed.emit()
	await process_frame
	if reasonable_card != null:
		reasonable_card.pressed.emit()
	await process_frame
	var cross_category: Dictionary = main.call("debug_fiscal_draft_state")
	_check(int(cross_category.get("tax", {}).get("income", -1)) == int(main.TAX_DEFS["income"]["reasonable"]), "switching categories preserves earlier draft choices")
	_check(int(cross_category.get("utility", {}).get("water", -1)) == int(main.UTILITY_DEFS["water"]["reasonable"]), "second category reasonable plan joins the same draft")
	var current_card := main.find_child("FiscalPlanCard_current", true, false) as Button
	if current_card != null:
		current_card.pressed.emit()
	await process_frame
	var category_reset: Dictionary = main.call("debug_fiscal_draft_state")
	_check(int(category_reset.get("utility", {}).get("water", -1)) == int(original_utility["water"]), "current plan restores only the selected category base")
	_check(int(category_reset.get("tax", {}).get("income", -1)) == int(main.TAX_DEFS["income"]["reasonable"]), "current plan does not discard another category draft")
	var custom_card := main.find_child("FiscalPlanCard_custom", true, false) as Button
	if custom_card != null:
		custom_card.pressed.emit()
	await process_frame
	var custom_editor := main.find_child("FiscalCustomEditor", true, false) as Control
	_check(custom_editor != null and custom_editor.is_visible_in_tree(), "custom plan reveals the existing slider and number-input editor")
	var visible_custom_sliders := 0
	if custom_editor != null:
		for slider_variant in custom_editor.find_children("FiscalSlider_*", "HSlider", true, false):
			var slider := slider_variant as HSlider
			if slider != null and slider.is_visible_in_tree():
				visible_custom_sliders += 1
	_check(visible_custom_sliders == 2, "custom editor exposes only the selected category's two controls")
	var preview_changes := main.find_child("FiscalDraftChangeList", true, false) as Label
	var preview_risk := main.find_child("FiscalDraftRisk", true, false) as Label
	_check(preview_changes != null and preview_changes.text.contains("→"), "fixed preview shows formal-to-draft values")
	_check(preview_risk != null and not preview_risk.text.is_empty(), "fixed preview shows burden or public-opinion risk")

	main.call("_on_tax_changed", float(int(original_tax["income"]) + 4), "income")
	main.call("_on_utility_fee_changed", float(int(original_utility["water"]) + 7), "water")
	main.call("_on_service_fee_changed", float(int(original_service["stadium"]) + 9), "stadium")
	var edited: Dictionary = main.call("debug_fiscal_draft_state")
	_check(main.tax_rates == original_tax, "tax slider edits do not mutate authoritative values")
	_check(main.utility_fees == original_utility, "utility slider edits do not mutate authoritative values")
	_check(main.service_fees == original_service, "service slider edits do not mutate authoritative values")
	_check(int(edited.get("dirty_count", -1)) == 3, "three changed controls produce one three-item draft")
	_check(int(edited.get("projected_net", 0)) != int(edited.get("authoritative_net", 0)), "forecast follows the whole draft before apply")

	var apply_button := main.find_child("FiscalApplyAllButton", true, false) as Button
	var discard_button := main.find_child("FiscalDiscardButton", true, false) as Button
	_check(apply_button != null and discard_button != null, "finance exposes one apply-all and one discard action")
	var autosaves_before := int(main._autosave_count)
	if apply_button != null:
		apply_button.pressed.emit()
	await process_frame
	var applied: Dictionary = main.call("debug_fiscal_draft_state")
	_check(int(main.tax_rates["income"]) == int(original_tax["income"]) + 4, "apply-all commits the tax draft")
	_check(int(main.utility_fees["water"]) == int(original_utility["water"]) + 7, "apply-all commits the utility draft")
	_check(int(main.service_fees["stadium"]) == int(original_service["stadium"]) + 9, "apply-all commits the service draft")
	_check(int(main._autosave_count) == autosaves_before + 1, "apply-all performs exactly one autosave")
	_check(int(applied.get("dirty_count", -1)) == 0, "apply-all resets the draft")

	main.call("_on_tax_changed", float(int(main.tax_rates["income"]) + 2), "income")
	if discard_button != null:
		discard_button.pressed.emit()
	await process_frame
	var discarded: Dictionary = main.call("debug_fiscal_draft_state")
	_check(int(discarded.get("dirty_count", -1)) == 0, "discard clears pending changes")
	_check(int(discarded.get("tax", {}).get("income", -1)) == int(main.tax_rates["income"]), "discard restores the authoritative value")

	main.call("_on_service_fee_changed", float(int(main.service_fees["stadium"]) + 4), "stadium")
	main.municipal_overlay.open_hub()
	await process_frame
	var left_page: Dictionary = main.call("debug_fiscal_draft_state")
	_check(int(left_page.get("dirty_count", -1)) == 0, "leaving finance discards an unapplied draft")
	var shell_state: Dictionary = main.call("_capture_player_shell_state")
	_check(not shell_state.has("fiscal_draft"), "fiscal draft is not added to the save schema")

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
