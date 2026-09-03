class_name SceneWorkflowShell
extends Control

signal layout_updated

const SemanticPalette = preload("res://ui/theme/semantic_palette.gd")

const EDGE_INSET := 12.0
const DEFAULT_TOP_HEIGHT := 68.0
const DEFAULT_TRAY_HEIGHT := 268.0

var background: TextureRect
var scrim: ColorRect
var scene_host: Control
var top_panel: PanelContainer
var tray_panel: PanelContainer
var top_content: HBoxContainer
var tray_content: VBoxContainer

var _background_path := ""
var _background_loaded := false
var _dark_mode := false
var _top_height := DEFAULT_TOP_HEIGHT
var _tray_height := DEFAULT_TRAY_HEIGHT


func _init(background_path: String = "") -> void:
	_background_path = background_path
	name = "SceneWorkflowShell"
	custom_minimum_size = Vector2(720, 420)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true
	_build_shell()
	resized.connect(_layout_shell)
	call_deferred("_layout_shell")


func set_dark_mode(enabled: bool) -> void:
	_dark_mode = enabled
	_apply_palette()


func set_top_height(height: float) -> void:
	_top_height = maxf(44.0, height)
	_layout_shell()
	call_deferred("_layout_shell")


func set_tray_height(height: float) -> void:
	_tray_height = maxf(120.0, height)
	_layout_shell()
	call_deferred("_layout_shell")


func is_background_loaded() -> bool:
	return _background_loaded


func relayout() -> void:
	_layout_shell()


func debug_signature() -> Dictionary:
	return {
		"background_path": _background_path,
		"background_loaded": _background_loaded,
		"top_rect": top_panel.get_rect(),
		"tray_rect": tray_panel.get_rect(),
		"scene_rect": scene_host.get_rect(),
		"shell_size": size,
		"top_minimum_size": top_panel.get_combined_minimum_size(),
		"tray_minimum_size": tray_panel.get_combined_minimum_size(),
		"top_height": _top_height,
		"tray_height": _tray_height,
		"dark_mode": _dark_mode,
	}


func _build_shell() -> void:
	background = TextureRect.new()
	background.name = "SceneBackground"
	background.texture = ResourceLoader.load(_background_path, "Texture2D") as Texture2D
	_background_loaded = background.texture != null
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	scrim = ColorRect.new()
	scrim.name = "SceneScrim"
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	scene_host = Control.new()
	scene_host.name = "SceneLayerHost"
	scene_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scene_host)
	scene_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	top_panel = PanelContainer.new()
	top_panel.name = "SceneTopBar"
	add_child(top_panel)
	top_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var top_margin := MarginContainer.new()
	top_margin.add_theme_constant_override("margin_left", 16)
	top_margin.add_theme_constant_override("margin_top", 8)
	top_margin.add_theme_constant_override("margin_right", 16)
	top_margin.add_theme_constant_override("margin_bottom", 8)
	top_panel.add_child(top_margin)
	top_content = HBoxContainer.new()
	top_content.name = "SceneTopBarContent"
	top_content.add_theme_constant_override("separation", 12)
	top_margin.add_child(top_content)

	tray_panel = PanelContainer.new()
	tray_panel.name = "SceneActionTray"
	add_child(tray_panel)
	tray_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var tray_margin := MarginContainer.new()
	tray_margin.add_theme_constant_override("margin_left", 16)
	tray_margin.add_theme_constant_override("margin_top", 10)
	tray_margin.add_theme_constant_override("margin_right", 16)
	tray_margin.add_theme_constant_override("margin_bottom", 10)
	tray_panel.add_child(tray_margin)
	tray_content = VBoxContainer.new()
	tray_content.name = "SceneActionTrayContent"
	tray_content.add_theme_constant_override("separation", 6)
	tray_margin.add_child(tray_content)

	_apply_palette()


func _layout_shell() -> void:
	if not is_instance_valid(top_panel) or size.x <= 0.0 or size.y <= 0.0:
		return
	var usable_height := maxf(0.0, size.y - EDGE_INSET * 3.0)
	var top_height := minf(_top_height, usable_height * 0.24)
	# Containers refuse to shrink below their content minimum. Include that
	# minimum before calculating tray_top so a tall workflow tray moves upward
	# instead of silently extending beyond the clipped scene root.
	var requested_tray_height := minf(_tray_height, usable_height * 0.62)
	var tray_height := maxf(requested_tray_height, tray_panel.get_combined_minimum_size().y)
	tray_height = minf(tray_height, maxf(0.0, size.y - EDGE_INSET * 2.0))
	for panel: PanelContainer in [top_panel, tray_panel]:
		panel.set_anchor(SIDE_LEFT, 0.0, false)
		panel.set_anchor(SIDE_TOP, 0.0, false)
		panel.set_anchor(SIDE_RIGHT, 0.0, false)
		panel.set_anchor(SIDE_BOTTOM, 0.0, false)
	top_panel.set_offset(SIDE_LEFT, EDGE_INSET)
	top_panel.set_offset(SIDE_TOP, EDGE_INSET)
	top_panel.set_offset(SIDE_RIGHT, maxf(EDGE_INSET, size.x - EDGE_INSET))
	top_panel.set_offset(SIDE_BOTTOM, EDGE_INSET + top_height)
	var tray_top := maxf(EDGE_INSET + top_height, size.y - tray_height - EDGE_INSET)
	tray_panel.set_offset(SIDE_LEFT, EDGE_INSET)
	tray_panel.set_offset(SIDE_TOP, tray_top)
	tray_panel.set_offset(SIDE_RIGHT, maxf(EDGE_INSET, size.x - EDGE_INSET))
	tray_panel.set_offset(SIDE_BOTTOM, tray_top + tray_height)
	layout_updated.emit()


func _apply_palette() -> void:
	if not is_instance_valid(scrim):
		return
	var scrim_color := SemanticPalette.color_for(_dark_mode, "scrim")
	scrim_color.a = 0.34 if _dark_mode else 0.20
	scrim.color = scrim_color
	var surface := SemanticPalette.color_for(_dark_mode, "surface_raised")
	surface.a = 0.94 if _dark_mode else 0.90
	var border := SemanticPalette.color_for(_dark_mode, "border_default")
	top_panel.add_theme_stylebox_override("panel", _panel_style(surface, border, 12))
	tray_panel.add_theme_stylebox_override("panel", _panel_style(surface, border, 14))


func _panel_style(background_color: Color, border_color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	return style
