extends SceneTree

const SemanticPalette = preload("res://ui/theme/semantic_palette.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for dark_mode in [false, true]:
		_validate_palette_roles(dark_mode)
	_validate_palette_wiring()
	if _failed:
		quit(1)
		return
	print("Semantic theme contrast test passed. Themes=light,dark Components=municipal_overlay,progressive_choice_pager")
	quit(0)


func _validate_palette_roles(dark_mode: bool) -> void:
	var palette := SemanticPalette.roles(dark_mode)
	for role in [
		"surface_base", "surface_raised", "surface_muted",
		"text_primary", "text_secondary", "text_on_accent", "text_disabled",
		"border_default", "border_focus", "border_disabled",
		"action_primary", "action_primary_disabled", "success", "caution", "danger", "scrim",
	]:
		_check(palette.has(role) and palette[role] is Color, "%s exposes %s" % [_mode_name(dark_mode), role])
	_check_ratio(palette["text_primary"], palette["surface_base"], 4.5, "%s primary text on base" % _mode_name(dark_mode))
	_check_ratio(palette["text_secondary"], palette["surface_base"], 4.5, "%s secondary text on base" % _mode_name(dark_mode))
	_check_ratio(palette["text_on_accent"], palette["action_primary"], 4.5, "%s accent text" % _mode_name(dark_mode))
	_check_ratio(palette["text_on_accent"], palette["danger"], 4.5, "%s danger text" % _mode_name(dark_mode))
	_check_ratio(palette["text_disabled"], palette["action_primary_disabled"], 3.0, "%s disabled button text" % _mode_name(dark_mode))
	_check_ratio(palette["border_default"], palette["surface_base"], 3.0, "%s default border" % _mode_name(dark_mode))
	_check_ratio(palette["border_focus"], palette["surface_base"], 3.0, "%s focus border" % _mode_name(dark_mode))
	_check_ratio(palette["border_disabled"], palette["surface_muted"], 3.0, "%s disabled border" % _mode_name(dark_mode))
	_check_ratio(palette["success"], palette["surface_base"], 3.0, "%s success feedback" % _mode_name(dark_mode))
	_check_ratio(palette["caution"], palette["surface_base"], 3.0, "%s caution feedback" % _mode_name(dark_mode))
	_check_ratio(palette["danger"], palette["surface_base"], 3.0, "%s danger feedback" % _mode_name(dark_mode))
	_check(palette["action_primary_disabled"] != palette["action_primary"], "%s disabled action differs from enabled action" % _mode_name(dark_mode))


func _validate_palette_wiring() -> void:
	var overlay_source := FileAccess.get_file_as_string("res://ui/shell/municipal_overlay.gd")
	var pager_source := FileAccess.get_file_as_string("res://ui/components/progressive_choice_pager.gd")
	var main_source := FileAccess.get_file_as_string("res://scripts/app/main.gd")
	_check(overlay_source.contains("SemanticPalette") and overlay_source.contains("\"scrim\""), "municipal overlay consumes the semantic palette and scrim")
	_check(overlay_source.contains("\"border_focus\"") and overlay_source.contains("\"action_primary_disabled\""), "municipal overlay wires focus and disabled states")
	_check(pager_source.contains("func set_dark_mode") and pager_source.contains("\"border_focus\""), "progressive pager accepts theme mode and uses visible focus")
	_check(pager_source.contains("\"action_primary_disabled\"") and pager_source.contains("\"text_disabled\""), "progressive pager distinguishes disabled navigation")
	_check(main_source.contains("const SemanticPalette") and main_source.contains("pager.set_dark_mode(is_dark_mode)"), "Main wires the shared palette to governance pagers")
	_check(main_source.contains("func _apply_button_style") and main_source.contains("\"border_focus\""), "Main shared buttons expose semantic focus contrast")


func _check_ratio(first: Color, second: Color, minimum: float, label: String) -> void:
	_check(SemanticPalette.contrast_ratio(first, second) >= minimum, "%s reaches %.1f:1 contrast" % [label, minimum])


func _mode_name(dark_mode: bool) -> String:
	return "dark" if dark_mode else "light"


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Semantic theme contrast check failed: %s" % message)
