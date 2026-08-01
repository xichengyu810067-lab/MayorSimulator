class_name BuildingContextPanel
extends PanelContainer

const UiIconCatalog = preload("res://ui/theme/ui_icon_catalog.gd")

signal action_requested(action_id: String)

const PANEL_SIZE := Vector2(650, 156)
const ICONS := {
	"appearance_menu": "customize",
	"style": "customize",
	"roof": "building_housing",
	"exterior": "buildings",
	"maintenance": "building_utilities",
	"demolish": "demolish",
}
const ACTIONS := [
	{"id": "style", "label": "樣式", "tip": "切換建築造型"},
	{"id": "roof", "label": "屋頂", "tip": "切換屋頂顏色"},
	{"id": "exterior", "label": "外觀", "tip": "切換外牆顏色"},
	{"id": "maintenance", "label": "維護", "tip": "將建築維修至 100 耐久"},
	{"id": "demolish", "label": "拆除", "tip": "排入共用工程隊拆除"},
]

var _dark_mode := false
var _title: Label
var _status: Label
var _action_buttons: Dictionary = {}
var _close_button: Button
var _appearance_button: Button
var _root_actions: HBoxContainer
var _customize_actions: HBoxContainer


func _init() -> void:
	name = "BuildingContextPanel"
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	z_index = 3500
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_content()
	_apply_palette()
	hide()


func set_dark_mode(enabled: bool) -> void:
	_dark_mode = enabled
	_apply_palette()


func open_for(state: Dictionary, anchor_position: Vector2, viewport_size: Vector2) -> void:
	_show_root_actions()
	_title.text = L10n.text(str(state.get("building_name", "建築")))
	_status.text = L10n.text("耐久 %d｜%s") % [
		int(state.get("durability", 100)),
		L10n.text(str(state.get("appearance", "不可客製"))),
	]
	var can_customize := bool(state.get("can_customize", false))
	_appearance_button.disabled = not can_customize
	for action_id in ["style", "roof", "exterior"]:
		(_action_buttons[action_id] as Button).disabled = not can_customize
	(_action_buttons["maintenance"] as Button).disabled = not bool(state.get("can_repair", false))
	(_action_buttons["demolish"] as Button).disabled = not bool(state.get("can_demolish", false))

	var target := Vector2(anchor_position.x - PANEL_SIZE.x * 0.5, anchor_position.y + 18.0)
	if target.y + PANEL_SIZE.y > viewport_size.y - 12.0:
		target.y = anchor_position.y - PANEL_SIZE.y - 18.0
	target.x = clampf(target.x, 12.0, maxf(12.0, viewport_size.x - PANEL_SIZE.x - 12.0))
	target.y = clampf(target.y, 82.0, maxf(82.0, viewport_size.y - PANEL_SIZE.y - 12.0))
	position = target
	show()
	_close_button.grab_focus()


func close_panel() -> void:
	hide()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	_close_or_back()
	accept_event()
	get_viewport().set_input_as_handled()


func _build_content() -> void:
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 6)
	add_child(shell)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	shell.add_child(header)
	_title = Label.new()
	_title.text = "建築"
	_title.add_theme_font_size_override("font_size", 20)
	header.add_child(_title)
	_status = Label.new()
	_status.text = "耐久 100"
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.add_theme_font_size_override("font_size", 18)
	header.add_child(_status)
	_close_button = Button.new()
	_close_button.name = "CloseBuildingContextButton"
	_close_button.text = "×"
	_close_button.tooltip_text = "關閉建築功能"
	_close_button.custom_minimum_size = Vector2(42, 36)
	_close_button.add_theme_font_size_override("font_size", 20)
	_close_button.pressed.connect(_close_or_back)
	header.add_child(_close_button)

	_root_actions = HBoxContainer.new()
	_root_actions.name = "BuildingContextActions"
	_root_actions.add_theme_constant_override("separation", 8)
	_root_actions.set_meta("progressive_choice_group", true)
	shell.add_child(_root_actions)
	_appearance_button = _action_button("appearance_menu", "外觀調整", "開啟樣式、屋頂與外牆選項")
	_appearance_button.pressed.connect(_open_customize_actions)
	_root_actions.add_child(_appearance_button)
	for action: Dictionary in ACTIONS:
		var button := _action_button(str(action["id"]), str(action["label"]), str(action["tip"]))
		_action_buttons[str(action["id"])] = button
		if str(action["id"]) in ["maintenance", "demolish"]:
			_root_actions.add_child(button)
	_customize_actions = HBoxContainer.new()
	_customize_actions.name = "BuildingAppearanceActions"
	_customize_actions.visible = false
	_customize_actions.add_theme_constant_override("separation", 8)
	_customize_actions.set_meta("progressive_choice_group", true)
	shell.add_child(_customize_actions)
	for action_id in ["style", "roof", "exterior"]:
		_customize_actions.add_child(_action_buttons[action_id])


func _action_button(action_id: String, label_text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.name = "BuildingAction_%s" % action_id
	button.text = ""
	button.tooltip_text = tooltip
	button.set_meta("semantic_label", label_text)
	button.custom_minimum_size = Vector2(196, 82)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.offset_left = 5
	stack.offset_top = 3
	stack.offset_right = -5
	stack.offset_bottom = -3
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(stack)
	var picture := TextureRect.new()
	var icon_key := str(ICONS.get(action_id, action_id))
	picture.texture = UiIconCatalog.texture(icon_key)
	picture.custom_minimum_size = Vector2(0, 50)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(picture)
	var caption := Label.new()
	caption.text = label_text
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 18)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(caption)
	if action_id != "appearance_menu":
		button.pressed.connect(func() -> void: action_requested.emit(action_id))
	return button


func _open_customize_actions() -> void:
	_root_actions.visible = false
	_customize_actions.visible = true
	_close_button.text = "←"
	_close_button.tooltip_text = "返回建築功能"
	(_action_buttons["style"] as Button).grab_focus()


func _show_root_actions() -> void:
	if _root_actions == null or _customize_actions == null:
		return
	_root_actions.visible = true
	_customize_actions.visible = false
	_close_button.text = "×"
	_close_button.tooltip_text = "關閉建築功能"


func _close_or_back() -> void:
	if _customize_actions != null and _customize_actions.visible:
		_show_root_actions()
		_appearance_button.grab_focus()
	else:
		close_panel()


func _apply_palette() -> void:
	if not is_instance_valid(_title):
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.13, 0.18, 0.97) if _dark_mode else Color(1.0, 0.96, 0.84, 0.98)
	style.border_color = Color(0.33, 0.58, 0.72) if _dark_mode else Color(0.54, 0.36, 0.16)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.content_margin_left = 12
	style.content_margin_top = 8
	style.content_margin_right = 12
	style.content_margin_bottom = 10
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = 5
	add_theme_stylebox_override("panel", style)
	var text_color := Color(0.93, 0.97, 1.0) if _dark_mode else Color(0.08, 0.10, 0.12)
	_title.add_theme_color_override("font_color", text_color)
	_status.add_theme_color_override("font_color", Color(0.72, 0.80, 0.86) if _dark_mode else Color(0.28, 0.31, 0.34))
	var styled_buttons: Array = _action_buttons.values()
	styled_buttons.append(_appearance_button)
	for button_variant in styled_buttons:
		var button := button_variant as Button
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0.13, 0.22, 0.29) if _dark_mode else Color(0.96, 0.89, 0.72)
		normal.border_color = Color(0.32, 0.52, 0.64) if _dark_mode else Color(0.60, 0.42, 0.20)
		normal.set_border_width_all(2)
		normal.set_corner_radius_all(9)
		var hover := normal.duplicate() as StyleBoxFlat
		hover.bg_color = Color(0.18, 0.32, 0.42) if _dark_mode else Color(1.0, 0.95, 0.82)
		var disabled := normal.duplicate() as StyleBoxFlat
		disabled.bg_color = Color(0.18, 0.21, 0.24) if _dark_mode else Color(0.80, 0.80, 0.76)
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("focus", hover)
		button.add_theme_stylebox_override("disabled", disabled)
		for label_variant in button.find_children("*", "Label", true, false):
			(label_variant as Label).add_theme_color_override("font_color", text_color)
