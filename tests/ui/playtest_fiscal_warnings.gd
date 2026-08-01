extends SceneTree

const FiscalScrollContract := preload("res://tests/helpers/fiscal_scroll_contract.gd")
const LOW_CAPTURE := "res://artifacts/screenshots/ui-tests/fullscreen-finance-low-warning.png"
const NORMAL_CAPTURE := "res://artifacts/screenshots/ui-tests/fullscreen-finance-normal.png"
const HIGH_CAPTURE := "res://artifacts/screenshots/ui-tests/fullscreen-finance-high-warning.png"
const RESULT_JSON := "res://artifacts/playtests/fiscal-warning-flow.json"
const TEST_SAVE_PATH := "user://mayor_simulator/tests/fiscal_playtest_autosave.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name().to_lower() == "headless":
		_fail("Fiscal warning playtest requires a visible display driver.")
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	await _settle(5)
	var scene := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _settle(5)
	scene.start_save_path = TEST_SAVE_PATH
	scene.start_screen.animation_duration = 0.04
	scene.start_screen.new_game_button.emit_signal("pressed")
	for _frame in range(120):
		await process_frame
		if not scene.start_screen.is_loading():
			break

	var municipal_button := scene.get("municipal_button") as Button
	municipal_button.emit_signal("pressed")
	await _settle()
	var overlay = scene.get("municipal_overlay")
	var finance_button := overlay.find_child("FinanceButton", true, false) as Button
	if finance_button == null or finance_button.disabled:
		_fail("Finance hub card is missing or disabled.")
		return
	finance_button.emit_signal("pressed")
	await _settle()

	var tabs := overlay.find_child("FiscalCategoryTabs", true, false) as TabContainer
	if tabs == null or tabs.get_tab_count() != 3:
		_fail("Expected three focused fiscal categories.")
		return
	var fiscal_scroll := overlay.find_child("稅率與公共事業費", true, false) as ScrollContainer
	if fiscal_scroll == null:
		_fail("Fiscal page is missing its responsive ScrollContainer.")
		return
	var fiscal_scroll_contract: Dictionary = await FiscalScrollContract.validate(self, overlay, tabs)
	if not bool(fiscal_scroll_contract.get("ok", false)):
		_fail("Fiscal responsive scroll contract failed: %s" % "; ".join(fiscal_scroll_contract.get("errors", [])))
		return
	var max_visible_rows := 0
	var leaf_category_count := 0
	for tab_index in range(tabs.get_tab_count()):
		tabs.current_tab = tab_index
		var subcategories := tabs.get_child(tab_index) as TabContainer
		if subcategories == null or subcategories.get_tab_count() != 2:
			_fail("Fiscal category %d must contain two subcategories." % tab_index)
			return
		for sub_index in range(subcategories.get_tab_count()):
			subcategories.current_tab = sub_index
			leaf_category_count += 1
			await _settle()
			var visible_rows := 0
			for node in tabs.find_children("FiscalRow_*", "VBoxContainer", true, false):
				if node.is_visible_in_tree():
					visible_rows += 1
			max_visible_rows = maxi(max_visible_rows, visible_rows)
			if visible_rows < 2 or visible_rows > 3:
				_fail("Fiscal category %d:%d exposes %d rows; expected 2–3." % [tab_index, sub_index, visible_rows])
				return

	var tax_sliders: Dictionary = scene.get("tax_sliders")
	var utility_sliders: Dictionary = scene.get("utility_sliders")
	var service_sliders: Dictionary = scene.get("service_sliders")
	_set_all_sliders(tax_sliders, 0)
	_set_all_sliders(utility_sliders, 0)
	_set_all_sliders(service_sliders, 0)
	tabs.current_tab = 1
	(tabs.get_child(1) as TabContainer).current_tab = 0
	await _settle(5)
	var low_counts := _state_counts([tax_sliders, utility_sliders, service_sliders])
	if int(low_counts.get("low", 0)) < 1:
		_fail("Zero-rate scenario did not produce a yellow funding warning.")
		return
	if not _save_capture(LOW_CAPTURE):
		return
	var low_net := int(scene.call("_projected_net_income"))
	var low_buffer := int(scene.call("_fiscal_safety_buffer"))

	_set_recommended_values(scene, tax_sliders, utility_sliders, service_sliders)
	tabs.current_tab = 0
	(tabs.get_child(0) as TabContainer).current_tab = 0
	await _settle(5)
	var normal_counts := _state_counts([tax_sliders, utility_sliders, service_sliders])
	if int(normal_counts.get("low", 0)) != 0 or int(normal_counts.get("high", 0)) != 0:
		_fail("Recommended values did not restore all sliders to normal.")
		return
	if not _save_capture(NORMAL_CAPTURE):
		return

	_set_all_sliders_to_max(tax_sliders)
	_set_all_sliders_to_max(utility_sliders)
	_set_all_sliders_to_max(service_sliders)
	tabs.current_tab = 0
	(tabs.get_child(0) as TabContainer).current_tab = 0
	await _settle(5)
	var high_counts := _state_counts([tax_sliders, utility_sliders, service_sliders])
	if int(high_counts.get("high", 0)) != 14:
		_fail("Maximum-rate scenario should mark all 14 sliders red; found %d." % int(high_counts.get("high", 0)))
		return
	if not _save_capture(HIGH_CAPTURE):
		return

	var result := {
		"result": "passed",
		"root_category_count": tabs.get_tab_count(),
		"leaf_category_count": leaf_category_count,
		"max_visible_rows": max_visible_rows,
		"responsive_scroll_contract": fiscal_scroll_contract,
		"low_state_counts": low_counts,
		"low_projected_net": low_net,
		"low_safety_buffer": low_buffer,
		"normal_state_counts": normal_counts,
		"high_state_counts": high_counts
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/playtests"))
	var file := FileAccess.open(RESULT_JSON, FileAccess.WRITE)
	if file == null:
		_fail("Could not write fiscal playtest JSON.")
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("FISCAL_WARNING_PLAYTEST %s" % JSON.stringify(result))
	quit(0)


func _set_all_sliders(sliders: Dictionary, value: int) -> void:
	for slider in sliders.values():
		(slider as HSlider).value = value


func _set_all_sliders_to_max(sliders: Dictionary) -> void:
	for slider in sliders.values():
		var control := slider as HSlider
		control.value = control.max_value


func _set_recommended_values(scene, tax_sliders: Dictionary, utility_sliders: Dictionary, service_sliders: Dictionary) -> void:
	for key in tax_sliders.keys():
		var tax_definition: Dictionary = scene.call("_fiscal_definition", "tax", str(key))
		(tax_sliders[key] as HSlider).value = int(tax_definition["reasonable"])
	for key in utility_sliders.keys():
		var utility_definition: Dictionary = scene.call("_fiscal_definition", "utility", str(key))
		(utility_sliders[key] as HSlider).value = int(utility_definition["reasonable"])
	for key in service_sliders.keys():
		var service_definition: Dictionary = scene.call("_fiscal_definition", "service", str(key))
		(service_sliders[key] as HSlider).value = int(service_definition["reasonable"])


func _state_counts(groups: Array) -> Dictionary:
	var counts := {"normal": 0, "low": 0, "high": 0}
	for group: Dictionary in groups:
		for slider in group.values():
			var state := str((slider as HSlider).get_meta("warning_state", "normal"))
			counts[state] = int(counts.get(state, 0)) + 1
	return counts


func _save_capture(path: String) -> bool:
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		_fail("Could not save %s: %d" % [path, error])
		return false
	return true


func _settle(frames: int = 3) -> void:
	for _frame in range(frames):
		await process_frame


func _fail(message: String) -> void:
	push_error("Fiscal warning playtest failed: %s" % message)
	quit(1)
