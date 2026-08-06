extends SceneTree

const JusticeScript := preload("res://systems/governance/justice-oversight/justice_oversight_system.gd")
const PANEL_PATH := "res://ui/governance/justice_oversight_panel.gd"
const CAPTURE_ARGUMENT_PREFIX := "--courtroom-capture="

var _failed := false


func _initialize() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 800)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.98, 0.96, 0.90)
	backdrop.position = Vector2.ZERO
	backdrop.size = Vector2(1280, 800)
	viewport.add_child(backdrop)

	var panel_script := ResourceLoader.load(PANEL_PATH, "Script", ResourceLoader.CACHE_MODE_IGNORE) as Script
	_check(panel_script != null and panel_script.can_instantiate(), "justice panel compiles")
	if panel_script == null or not panel_script.can_instantiate():
		quit(1)
		return
	var panel = panel_script.new("judicial")
	panel.set_dark_mode(false)
	panel.position = Vector2(24, 18)
	panel.size = Vector2(1232, 764)
	backdrop.add_child(panel)

	var system = JusticeScript.new(20_260_803)
	_check(bool(system.initialize().get("ok", false)), "justice system initializes")
	var opened: Dictionary = system.open_judicial_case("public_safety_act", 1, 64, "公共安全法案違法施行案")
	var court_case: Dictionary = opened.get("case", {})
	var case_id := str(court_case.get("id", ""))
	system.advance_judicial_procedures(int(court_case.get("hearing_day", 1)))
	_check(bool(system.submit_defense(case_id, "safety_emergency").get("ok", false)), "hearing accepts the prepared defense")
	panel.refresh(system)

	var stage = panel._courtroom_stage
	if DisplayServer.get_name().to_lower() == "headless":
		# Dummy rendering does not emit frame_post_draw or advance visual tweens.
		stage._apply_stage_visibility("hearing")
	else:
		await create_timer(0.45).timeout
		await RenderingServer.frame_post_draw
	_check(stage != null and stage.visible and not stage.is_queued_for_deletion(), "layered courtroom is present and enabled")
	_check(str(system.judicial_cases[case_id].get("procedural_stage", "")) == "hearing", "case is captured during the hearing")
	_check(stage._judges.modulate.a > 0.95, "judicial panel is seated during the hearing")
	_check(stage._clerk.modulate.a > 0.95, "court clerk is present during the hearing")
	_check(stage._defense.modulate.a > 0.95, "mayor and defense counsel are present during the hearing")
	_check(stage._defense.position.y >= stage.size.y * 0.45, "the defense table remains on the courtroom floor instead of floating above the bench")
	_check(panel._procedure_labels.size() == 5, "all five procedure stages are visible")
	var future_stage_label := panel._procedure_labels["judgment"] as Label
	_check(future_stage_label.get_theme_color("font_color").get_luminance() < 0.25, "future stages keep dark readable text on the light timeline")
	panel.set_dark_mode(true)
	_check(future_stage_label.get_theme_color("font_color").get_luminance() > 0.75, "future stages become light when dark mode is enabled while the court is open")
	panel.set_dark_mode(false)
	_check(future_stage_label.get_theme_color("font_color").get_luminance() < 0.25, "future stages return to dark text when light mode is restored")
	_check(panel._next_step_label.text.contains("合議評議"), "the next procedural step is explained")
	_check(panel._case_detail.text.contains("年") and panel._case_detail.text.contains("月"), "the judgment date uses the fixed game calendar")

	var capture_path := _capture_path()
	if not capture_path.is_empty():
		_check(DisplayServer.get_name().to_lower() != "headless", "evidence capture requires a graphics display server")
		var image := viewport.get_texture().get_image()
		var error := image.save_png(capture_path) if image != null and not image.is_empty() else ERR_CANT_CREATE
		_check(error == OK, "courtroom evidence screenshot is saved")
		if error == OK:
			print("Courtroom visual evidence saved: %s" % capture_path)

	if _failed:
		quit(1)
	else:
		print("Courtroom visual acceptance passed. Stage=hearing Calendar=30x12 Layers=3")
		quit(0)


func _capture_path() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(CAPTURE_ARGUMENT_PREFIX):
			return argument.trim_prefix(CAPTURE_ARGUMENT_PREFIX)
	return ""


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Courtroom visual acceptance failed: %s" % message)
