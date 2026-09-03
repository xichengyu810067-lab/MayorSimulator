extends SceneTree

const JusticeScript := preload("res://systems/governance/justice-oversight/justice_oversight_system.gd")
const PANEL_PATH := "res://ui/governance/justice_oversight_panel.gd"

var _failed := false


func _initialize() -> void:
	var panel_script := ResourceLoader.load(PANEL_PATH, "Script", ResourceLoader.CACHE_MODE_IGNORE) as Script
	_check(panel_script != null and panel_script.can_instantiate(), "oversight panel compiles")
	if panel_script == null or not panel_script.can_instantiate():
		quit(1)
		return
	var system = JusticeScript.new(20_260_903)
	_check(bool(system.initialize().get("ok", false)), "justice system initializes")
	_check(bool(system.register_administrative_official("official_mayor", "現任市長", "mayor", "市長").get("ok", false)), "mayor registers")
	var panel = panel_script.new("oversight")
	root.add_child(panel)
	panel.refresh(system)
	var stage = panel._oversight_hearing_stage
	_check(stage != null, "oversight panel creates the dedicated hearing stage")
	var empty: Dictionary = stage.debug_signature()
	_check(bool(empty.get("background_loaded", false)), "oversight background loads")
	_check(str(empty.get("state", "")) == "empty", "empty oversight state is explicit")
	_check(bool(empty.get("animation_running", false)), "empty oversight state has ambient animation")
	var opened: Dictionary = system.open_oversight_case("official_mayor", ["行政失職"], 65, 3)
	_check(bool(opened.get("ok", false)), "oversight case opens")
	var case_data: Dictionary = opened.get("case", {})
	var case_id := str(case_data.get("id", ""))
	panel.refresh(system)
	await process_frame
	var questioning: Dictionary = stage.debug_signature()
	_check(str(questioning.get("state", "")) == "questioning", "active case enters questioning animation")
	_check(str(questioning.get("case_id", "")) == case_id, "stage binds the selected oversight case")
	_check(bool(questioning.get("question_visible", false)), "questioning cue is visible")
	var before_defense := int(questioning.get("animation_generation", 0))
	var defense: Dictionary = panel.submit_current_defense("full_disclosure")
	_check(bool(defense.get("ok", false)), "successful defense is submitted through authority")
	_check(str(stage.debug_signature().get("state", "")) == "defense_submitted", "only successful defense triggers the visual success feedback")
	_check(int(stage.debug_signature().get("animation_generation", 0)) > before_defense, "successful defense starts a new feedback animation")
	var submitted_generation := int(stage.debug_signature().get("animation_generation", 0))
	panel.refresh(system)
	_check(str(stage.debug_signature().get("state", "")) == "defense_submitted", "repeated refresh projects the authority submitted-defense state")
	_check(int(stage.debug_signature().get("animation_generation", 0)) == submitted_generation, "repeated refresh does not replay submitted-defense feedback")
	if _failed:
		quit(1)
	else:
		print("Oversight hearing visual acceptance passed. States=empty,questioning,defense_submitted")
		quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Oversight hearing visual acceptance failed: %s" % message)
