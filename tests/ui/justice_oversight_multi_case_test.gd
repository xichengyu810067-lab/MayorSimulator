extends SceneTree

const JusticeScript := preload("res://systems/governance/justice-oversight/justice_oversight_system.gd")
const PANEL_PATH := "res://ui/governance/justice_oversight_panel.gd"

var _failed := false


func _initialize() -> void:
	var panel_script := ResourceLoader.load(PANEL_PATH, "Script", ResourceLoader.CACHE_MODE_IGNORE) as Script
	_check(panel_script != null and panel_script.can_instantiate(), "justice/oversight panel compiles")
	if panel_script == null or not panel_script.can_instantiate():
		quit(1)
		return
	var system = JusticeScript.new(20_260_731)
	_check(bool(system.initialize().get("ok", false)), "justice system initializes")
	_check(bool(system.register_administrative_official("official_mayor", "現任市長", "mayor", "市長").get("ok", false)), "mayor registers")

	var first_judicial: Dictionary = system.open_judicial_case("environment_act", 1, 45, "環境保護法案強制施行審查")
	var second_judicial: Dictionary = system.open_judicial_case("transit_act", 2, 55, "交通建設法案強制施行審查")
	_check(bool(first_judicial.get("ok", false)) and bool(second_judicial.get("ok", false)), "two judicial cases can coexist")
	var first_judicial_id := str(first_judicial.get("case", {}).get("id", ""))
	var second_judicial_id := str(second_judicial.get("case", {}).get("id", ""))
	var judicial_panel = panel_script.new("judicial")
	root.add_child(judicial_panel)
	judicial_panel.refresh(system)
	_check(judicial_panel._case_selector.item_count == 2, "judicial selector lists every investigating case")
	_check(judicial_panel._courtroom_stage != null, "judicial panel includes the layered courtroom scene")
	_check(judicial_panel._procedure_labels.size() == 5, "judicial panel exposes all five procedure stages")
	_check(judicial_panel._case_detail.text.contains("年") and judicial_panel._case_detail.text.contains("月"), "judicial decision date uses the 30-day, 12-month game calendar")
	_check(judicial_panel.selected_case_id() == second_judicial_id, "latest judicial case remains the default selection")
	_check(judicial_panel.select_case_by_id(first_judicial_id), "player can select the earlier judicial case")
	_check(judicial_panel._previous_case_button.disabled, "first judicial case is at the previous boundary")
	_check(not judicial_panel._next_case_button.disabled, "first judicial case can navigate forward")
	var first_defense: Dictionary = judicial_panel.submit_current_defense("public_interest")
	_check(bool(first_defense.get("ok", false)), "selected judicial case accepts a defense")
	_check(str(system.judicial_cases[first_judicial_id].get("defense_template_id", "")) == "public_interest", "defense is written to the selected judicial case")
	_check(str(system.judicial_cases[second_judicial_id].get("defense_template_id", "")).is_empty(), "unselected judicial case is unchanged")
	judicial_panel._select_next_case()
	_check(judicial_panel.selected_case_id() == second_judicial_id, "next judicial navigation selects the following case")
	judicial_panel._select_previous_case()
	_check(judicial_panel.selected_case_id() == first_judicial_id, "previous judicial navigation returns to the earlier case")

	var first_oversight: Dictionary = system.open_oversight_case("official_mayor", ["行政失職"], 65, 3)
	var second_oversight: Dictionary = system.open_oversight_case("official_mayor", ["違法執行"], 75, 4)
	_check(bool(first_oversight.get("ok", false)) and bool(second_oversight.get("ok", false)), "two oversight cases can coexist")
	var first_oversight_id := str(first_oversight.get("case", {}).get("id", ""))
	var second_oversight_id := str(second_oversight.get("case", {}).get("id", ""))
	var oversight_panel = panel_script.new("oversight")
	root.add_child(oversight_panel)
	oversight_panel.refresh(system)
	_check(oversight_panel._oversight_hearing_stage != null, "oversight panel includes the layered hearing scene")
	_check(str(oversight_panel._oversight_hearing_stage.debug_signature().get("case_id", "")) == second_oversight_id, "oversight scene follows the latest selected case")
	_check(oversight_panel._case_selector.item_count == 2, "oversight selector lists every investigating case")
	_check(oversight_panel.selected_case_id() == second_oversight_id, "latest oversight case remains the default selection")
	_check(oversight_panel.select_case_by_id(first_oversight_id), "player can select the earlier oversight case")
	_check(str(oversight_panel._oversight_hearing_stage.debug_signature().get("case_id", "")) == first_oversight_id, "oversight scene follows case navigation")
	var oversight_defense: Dictionary = oversight_panel.submit_current_defense("due_process")
	_check(bool(oversight_defense.get("ok", false)), "selected oversight case accepts a defense")
	_check(str(system.oversight_cases[first_oversight_id].get("defense_template_id", "")) == "due_process", "defense is written to the selected oversight case")
	_check(str(oversight_panel._oversight_hearing_stage.debug_signature().get("state", "")) == "defense_submitted", "success feedback follows only the accepted oversight defense")
	_check(str(system.oversight_cases[second_oversight_id].get("defense_template_id", "")).is_empty(), "unselected oversight case is unchanged")

	system.set_terminal_failure("municipal_trust_below_40")
	judicial_panel.refresh(system)
	oversight_panel.refresh(system)
	_check(str(oversight_panel._oversight_hearing_stage.debug_signature().get("state", "")) == "questioning", "terminal state keeps the selected case visible without playing success feedback")
	for button_variant in judicial_panel._defense_buttons.values():
		_check((button_variant as Button).disabled, "terminal state disables every judicial defense command")
	_check(not bool(judicial_panel.submit_current_defense("safety_emergency").get("ok", false)), "terminal justice mutation is rejected")

	if _failed:
		quit(1)
	else:
		print("Justice/oversight multi-case test passed. Judicial=2 Oversight=2")
		quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Justice/oversight multi-case test failed: %s" % message)
