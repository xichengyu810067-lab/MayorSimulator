extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
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

	var original_tax: Dictionary = main.tax_rates.duplicate(true)
	var original_utility: Dictionary = main.utility_fees.duplicate(true)
	var original_service: Dictionary = main.service_fees.duplicate(true)
	main.municipal_overlay.open_page("finance")
	await process_frame
	var initial: Dictionary = main.call("debug_fiscal_draft_state")
	_check(int(initial.get("dirty_count", -1)) == 0, "opening finance starts with a clean draft")

	main.call("_on_tax_changed", float(int(original_tax["income"]) + 3), "income")
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
	_check(int(main.tax_rates["income"]) == int(original_tax["income"]) + 3, "apply-all commits the tax draft")
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
