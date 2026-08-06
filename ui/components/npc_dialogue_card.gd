class_name NpcDialogueCard
extends PanelContainer

signal primary_action_requested
signal dismiss_requested

const UiIconCatalog = preload("res://ui/theme/ui_icon_catalog.gd")

const CARD_WIDTH := 468.0
const PORTRAIT_SIZE := Vector2(88, 116)

var message_label: Label
var name_label: Label
var role_label: Label
var petition_status_label: Label
var portrait_rect: TextureRect
var primary_action_button: Button
var close_button: Button

var _dark_mode := false
var _portrait_frame: PanelContainer
var _message_frame: PanelContainer
var _role_chip: PanelContainer
var _status_chip: PanelContainer
var _status_dot: Label


func _init() -> void:
	name = "NpcDialogueCard"
	custom_minimum_size = Vector2(CARD_WIDTH, 0)
	size = Vector2(CARD_WIDTH, 194)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	clip_contents = false
	z_as_relative = false
	z_index = 2000
	_build_content()
	_apply_theme()


# The caller supplies authoritative presentation data.  This component does
# not invent relationship points, infer petition state, or mutate NPC records.
func set_content(
	display_name: String,
	role_text: String,
	message: String,
	petition_status: String = "",
	portrait_texture: Texture2D = null,
	primary_action_text: String = ""
) -> void:
	name_label.text = display_name
	role_label.text = role_text
	message_label.text = message
	petition_status_label.text = petition_status
	_status_chip.visible = not petition_status.strip_edges().is_empty()
	portrait_rect.texture = portrait_texture if portrait_texture != null else UiIconCatalog.texture("population")
	primary_action_button.text = primary_action_text
	primary_action_button.visible = not primary_action_text.strip_edges().is_empty()
	queue_sort()


func set_dark_mode(enabled: bool) -> void:
	if _dark_mode == enabled:
		return
	_dark_mode = enabled
	_apply_theme()


func is_dark_mode() -> bool:
	return _dark_mode


func _build_content() -> void:
	var layout := HBoxContainer.new()
	layout.name = "DialogueLayout"
	layout.add_theme_constant_override("separation", 15)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layout)

	_portrait_frame = PanelContainer.new()
	_portrait_frame.name = "PortraitFrame"
	_portrait_frame.custom_minimum_size = PORTRAIT_SIZE
	_portrait_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(_portrait_frame)

	portrait_rect = TextureRect.new()
	portrait_rect.name = "Portrait"
	portrait_rect.custom_minimum_size = Vector2(76, 102)
	portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_rect.texture = UiIconCatalog.texture("population")
	_portrait_frame.add_child(portrait_rect)

	var text_stack := VBoxContainer.new()
	text_stack.name = "DialogueTextStack"
	text_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_stack.add_theme_constant_override("separation", 8)
	text_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(text_stack)

	var heading := HBoxContainer.new()
	heading.name = "Heading"
	heading.add_theme_constant_override("separation", 8)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_stack.add_child(heading)

	var identity := VBoxContainer.new()
	identity.name = "Identity"
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", 4)
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(identity)

	name_label = Label.new()
	name_label.name = "NpcName"
	name_label.text = "—"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(name_label)

	_role_chip = PanelContainer.new()
	_role_chip.name = "RoleChip"
	_role_chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_role_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(_role_chip)

	role_label = Label.new()
	role_label.name = "NpcRole"
	role_label.text = "—"
	role_label.add_theme_font_size_override("font_size", 14)
	role_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_role_chip.add_child(role_label)

	close_button = Button.new()
	close_button.name = "DismissButton"
	close_button.text = "×"
	close_button.custom_minimum_size = Vector2(44, 44)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_button.focus_mode = Control.FOCUS_ALL
	close_button.mouse_filter = Control.MOUSE_FILTER_STOP
	close_button.add_theme_font_size_override("font_size", 22)
	close_button.pressed.connect(_on_dismiss_pressed)
	heading.add_child(close_button)

	_message_frame = PanelContainer.new()
	_message_frame.name = "MessageFrame"
	_message_frame.custom_minimum_size = Vector2(0, 62)
	_message_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_stack.add_child(_message_frame)

	message_label = Label.new()
	message_label.name = "MessageLabel"
	message_label.text = ""
	message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 17)
	message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message_label.set_meta("l10n_skip", true)
	_message_frame.add_child(message_label)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 8)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_stack.add_child(footer)

	_status_chip = PanelContainer.new()
	_status_chip.name = "PetitionStatusChip"
	_status_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_chip.clip_contents = true
	_status_chip.hide()
	footer.add_child(_status_chip)

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 5)
	status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_chip.add_child(status_row)

	_status_dot = Label.new()
	_status_dot.name = "StatusDot"
	_status_dot.text = "●"
	_status_dot.add_theme_font_size_override("font_size", 10)
	_status_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_row.add_child(_status_dot)

	petition_status_label = Label.new()
	petition_status_label.name = "PetitionStatus"
	petition_status_label.custom_minimum_size = Vector2(0, 20)
	petition_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	petition_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	petition_status_label.clip_text = true
	petition_status_label.add_theme_font_size_override("font_size", 14)
	petition_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_row.add_child(petition_status_label)

	primary_action_button = Button.new()
	primary_action_button.name = "PrimaryActionButton"
	primary_action_button.custom_minimum_size = Vector2(124, 44)
	primary_action_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	primary_action_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	primary_action_button.focus_mode = Control.FOCUS_ALL
	primary_action_button.mouse_filter = Control.MOUSE_FILTER_STOP
	primary_action_button.add_theme_font_size_override("font_size", 16)
	primary_action_button.pressed.connect(_on_primary_action_pressed)
	primary_action_button.hide()
	footer.add_child(primary_action_button)


func _apply_theme() -> void:
	add_theme_stylebox_override("panel", _card_style())
	_portrait_frame.add_theme_stylebox_override("panel", _portrait_style())
	_message_frame.add_theme_stylebox_override("panel", _message_style())
	_role_chip.add_theme_stylebox_override("panel", _role_style())
	_status_chip.add_theme_stylebox_override("panel", _status_style())

	var main_text := Color(0.92, 0.96, 0.94) if _dark_mode else Color(0.19, 0.14, 0.10)
	var quiet_text := Color(0.70, 0.82, 0.80) if _dark_mode else Color(0.34, 0.38, 0.29)
	var message_text := Color(0.88, 0.94, 0.93) if _dark_mode else Color(0.22, 0.20, 0.16)
	name_label.add_theme_color_override("font_color", main_text)
	role_label.add_theme_color_override("font_color", quiet_text)
	message_label.add_theme_color_override("font_color", message_text)
	petition_status_label.add_theme_color_override("font_color", main_text)
	_status_dot.add_theme_color_override("font_color", Color(0.94, 0.69, 0.24) if _dark_mode else Color(0.78, 0.43, 0.18))
	_style_close_button()
	_style_primary_button()


func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.12, 0.16, 0.985) if _dark_mode else Color(0.985, 0.955, 0.86, 0.99)
	style.border_color = Color(0.30, 0.68, 0.65) if _dark_mode else Color(0.48, 0.31, 0.16)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.content_margin_left = 17
	style.content_margin_right = 17
	style.content_margin_top = 15
	style.content_margin_bottom = 15
	style.shadow_color = Color(0.01, 0.03, 0.04, 0.46) if _dark_mode else Color(0.12, 0.08, 0.04, 0.24)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 5)
	return style


func _portrait_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.23, 0.27, 0.94) if _dark_mode else Color(0.82, 0.91, 0.75, 0.98)
	style.border_color = Color(0.37, 0.70, 0.67) if _dark_mode else Color(0.63, 0.45, 0.23)
	style.set_border_width_all(2)
	style.set_corner_radius_all(13)
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style


func _message_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.18, 0.21, 0.94) if _dark_mode else Color(1.0, 0.985, 0.92, 0.92)
	style.border_color = Color(0.20, 0.43, 0.43, 0.75) if _dark_mode else Color(0.72, 0.58, 0.35, 0.62)
	style.set_border_width_all(1)
	style.set_corner_radius_all(11)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style


func _role_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.30, 0.31, 0.88) if _dark_mode else Color(0.85, 0.91, 0.76, 0.94)
	style.set_corner_radius_all(9)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style


func _status_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.23, 0.26, 0.21, 0.94) if _dark_mode else Color(0.96, 0.88, 0.66, 0.96)
	style.border_color = Color(0.77, 0.55, 0.18, 0.80) if _dark_mode else Color(0.73, 0.45, 0.15, 0.66)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style


func _style_close_button() -> void:
	var normal := _button_style(
		Color(0.12, 0.25, 0.27, 0.94) if _dark_mode else Color(0.94, 0.86, 0.69, 0.96),
		Color(0.30, 0.56, 0.55, 0.82) if _dark_mode else Color(0.65, 0.45, 0.25, 0.70),
		11
	)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.20, 0.39, 0.39, 0.98) if _dark_mode else Color(0.98, 0.79, 0.55, 0.98)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.08, 0.18, 0.20, 0.98) if _dark_mode else Color(0.86, 0.70, 0.48, 0.98)
	close_button.add_theme_stylebox_override("normal", normal)
	close_button.add_theme_stylebox_override("hover", hover)
	close_button.add_theme_stylebox_override("pressed", pressed)
	close_button.add_theme_stylebox_override("focus", _focus_style(11))
	var ink := Color(0.92, 0.96, 0.94) if _dark_mode else Color(0.30, 0.20, 0.13)
	close_button.add_theme_color_override("font_color", ink)
	close_button.add_theme_color_override("font_hover_color", ink)
	close_button.add_theme_color_override("font_pressed_color", ink)
	close_button.add_theme_color_override("font_focus_color", ink)


func _style_primary_button() -> void:
	var normal := _button_style(
		Color(0.16, 0.48, 0.45),
		Color(0.33, 0.71, 0.64),
		11
	)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.20, 0.59, 0.54)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.11, 0.37, 0.36)
	primary_action_button.add_theme_stylebox_override("normal", normal)
	primary_action_button.add_theme_stylebox_override("hover", hover)
	primary_action_button.add_theme_stylebox_override("pressed", pressed)
	primary_action_button.add_theme_stylebox_override("focus", _focus_style(11))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		primary_action_button.add_theme_color_override(state, Color(0.97, 1.0, 0.96))


func _button_style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style


func _focus_style(radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color(0.96, 0.76, 0.33) if _dark_mode else Color(0.18, 0.48, 0.45)
	style.set_border_width_all(3)
	style.set_corner_radius_all(radius)
	return style


func _on_primary_action_pressed() -> void:
	primary_action_requested.emit()


func _on_dismiss_pressed() -> void:
	dismiss_requested.emit()
