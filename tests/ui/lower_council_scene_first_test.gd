extends SceneTree

const STAGE_PATH := "res://ui/governance/lower_council_stage.gd"

var _failed := false


func _initialize() -> void:
	var script := ResourceLoader.load(STAGE_PATH, "Script", ResourceLoader.CACHE_MODE_IGNORE) as Script
	_check(script != null and script.can_instantiate(), "lower-council stage compiles")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	var stage = script.new()
	root.add_child(stage)
	await process_frame
	var idle: Dictionary = stage.debug_signature()
	_check(bool(idle.get("visible", false)), "legislative chamber remains visible while idle")
	_check(str(idle.get("stage_state", "")) == "idle", "idle chamber exposes its scene-first state")
	_check(bool(idle.get("background_loaded", false)), "idle chamber loads its legislative background")
	_check(int(idle.get("portrait_count", 0)) == 30 and int(idle.get("visible_portrait_count", 0)) == 30, "all 30 councilor portraits are loaded and visible")
	_check(float(idle.get("seat_surface_max_alpha", 1.0)) <= 0.23, "seat surfaces stay translucent instead of washing out the chamber")
	_check(bool(idle.get("animation_running", false)), "idle chamber has observable ambient Tween animation")
	stage.set_catalog_focus("policy_selected", "公共建設政策")
	_check(str(stage.debug_signature().get("stage_state", "")) == "policy_selected", "policy selection keeps the chamber active")
	stage.set_catalog_focus("bill_selected", "交通建設法案")
	_check(str(stage.debug_signature().get("stage_state", "")) == "bill_selected", "bill selection keeps the chamber active")
	stage.set_catalog_focus("bill_review", "交通建設法案")
	_check(str(stage.debug_signature().get("stage_state", "")) == "bill_review", "bill review keeps the chamber active")
	stage.set_dark_mode(true)
	var dark: Dictionary = stage.debug_signature()
	_check(bool(dark.get("dark_mode", false)), "lower-council stage applies true dark mode")
	_check(int(dark.get("visible_portrait_count", 0)) == 30 and float(dark.get("seat_surface_max_alpha", 1.0)) <= 0.23, "dark mode keeps all portraits visible over translucent seats")
	if _failed:
		quit(1)
	else:
		print("Lower council scene-first test passed. States=idle,policy_selected,bill_selected,bill_review")
		quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Lower council scene-first test failed: %s" % message)
