extends Control

const ModalPointerGuardScript = preload("res://ui/components/modal_pointer_guard.gd")

signal confirmed
signal cancelled
signal discard_confirmed

var cancel_button: Button
var confirm_button: Button
var discard_button: Button
var close_button: Button
var description_label: Label

var _is_built := false


func _init() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_as_relative = false
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_ensure_built()


func open() -> void:
	_ensure_built()
	_reset_prompt()
	L10n.localize_tree(self)
	show()
	move_to_front()
	if is_instance_valid(cancel_button):
		cancel_button.grab_focus()


func close() -> void:
	hide()


func show_save_error(error_code: int) -> void:
	_ensure_built()
	description_label.text = "%s\n%s" % [
		L10n.text("儲存失敗（錯誤 %d）") % error_code,
		L10n.text("遊戲仍保持開啟。請重試，或明確選擇不儲存離開。"),
	]
	confirm_button.text = L10n.text("重試儲存並離開")
	discard_button.text = L10n.text("不儲存並離開")
	discard_button.show()
	show()
	move_to_front()
	confirm_button.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_cancel()
		accept_event()
		get_viewport().set_input_as_handled()


func _ensure_built() -> void:
	if _is_built:
		return
	_is_built = true

	var dimmer := ColorRect.new()
	dimmer.color = Color(0.015, 0.03, 0.045, 0.78)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dimmer)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520.0, 260.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	content.add_child(header)

	var title := Label.new()
	title.text = "要離開 Mayor Simulator 嗎？"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("f7fbff"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	header.add_child(title)

	close_button = Button.new()
	close_button.text = "×"
	close_button.tooltip_text = "關閉確認視窗"
	close_button.custom_minimum_size = Vector2(44.0, 44.0)
	close_button.focus_mode = Control.FOCUS_ALL
	close_button.add_theme_font_size_override("font_size", 26)
	close_button.add_theme_color_override("font_color", Color("f7fbff"))
	close_button.add_theme_stylebox_override("normal", _button_style(Color(0.16, 0.24, 0.31, 0.92)))
	close_button.add_theme_stylebox_override("hover", _button_style(Color(0.24, 0.35, 0.44, 1.0)))
	close_button.add_theme_stylebox_override("pressed", _button_style(Color(0.10, 0.17, 0.23, 1.0)))
	close_button.pressed.connect(_cancel_from_pointer)
	header.add_child(close_button)

	description_label = Label.new()
	description_label.text = "尚未完成的進度可能會遺失。\n確定要關閉遊戲嗎？"
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.add_theme_font_size_override("font_size", 20)
	description_label.add_theme_color_override("font_color", Color("d9e7f2"))
	description_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(description_label)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	content.add_child(actions)

	cancel_button = Button.new()
	cancel_button.text = "取消"
	cancel_button.custom_minimum_size = Vector2(128.0, 50.0)
	cancel_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cancel_button.focus_mode = Control.FOCUS_ALL
	cancel_button.add_theme_font_size_override("font_size", 20)
	cancel_button.add_theme_color_override("font_color", Color("f7fbff"))
	cancel_button.add_theme_stylebox_override("normal", _button_style(Color(0.18, 0.29, 0.38, 1.0)))
	cancel_button.add_theme_stylebox_override("hover", _button_style(Color(0.24, 0.40, 0.52, 1.0)))
	cancel_button.add_theme_stylebox_override("pressed", _button_style(Color(0.11, 0.21, 0.29, 1.0)))
	cancel_button.pressed.connect(_cancel_from_pointer)
	actions.add_child(cancel_button)

	discard_button = Button.new()
	discard_button.text = "不儲存並離開"
	discard_button.custom_minimum_size = Vector2(160.0, 50.0)
	discard_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	discard_button.focus_mode = Control.FOCUS_ALL
	discard_button.add_theme_font_size_override("font_size", 18)
	discard_button.add_theme_color_override("font_color", Color("ffffff"))
	discard_button.add_theme_stylebox_override("normal", _button_style(Color(0.48, 0.20, 0.12, 1.0)))
	discard_button.add_theme_stylebox_override("hover", _button_style(Color(0.64, 0.28, 0.15, 1.0)))
	discard_button.add_theme_stylebox_override("pressed", _button_style(Color(0.36, 0.13, 0.08, 1.0)))
	discard_button.pressed.connect(_discard)
	discard_button.hide()
	actions.add_child(discard_button)

	confirm_button = Button.new()
	confirm_button.text = "離開遊戲"
	confirm_button.custom_minimum_size = Vector2(160.0, 50.0)
	confirm_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_button.focus_mode = Control.FOCUS_ALL
	confirm_button.add_theme_font_size_override("font_size", 20)
	confirm_button.add_theme_color_override("font_color", Color("ffffff"))
	confirm_button.add_theme_stylebox_override("normal", _button_style(Color(0.74, 0.16, 0.17, 1.0)))
	confirm_button.add_theme_stylebox_override("hover", _button_style(Color(0.90, 0.24, 0.23, 1.0)))
	confirm_button.add_theme_stylebox_override("pressed", _button_style(Color(0.55, 0.09, 0.11, 1.0)))
	confirm_button.pressed.connect(_confirm)
	actions.add_child(confirm_button)


func _cancel() -> void:
	close()
	cancelled.emit()


func _cancel_from_pointer() -> void:
	get_viewport().set_input_as_handled()
	_arm_pointer_guard()
	_cancel()


func _arm_pointer_guard() -> void:
	var parent_node := get_parent()
	if parent_node == null:
		return
	var guard := parent_node.get_node_or_null(ModalPointerGuardScript.GUARD_NODE_NAME)
	if guard == null:
		guard = ModalPointerGuardScript.new()
		parent_node.add_child(guard)
	guard.call("arm", get_viewport().get_mouse_position())


func _confirm() -> void:
	confirmed.emit()


func _discard() -> void:
	close()
	discard_confirmed.emit()


func _reset_prompt() -> void:
	if not is_instance_valid(description_label):
		return
	description_label.text = "尚未完成的進度可能會遺失。\n確定要關閉遊戲嗎？"
	confirm_button.text = "離開遊戲"
	discard_button.hide()


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.12, 0.18, 0.99)
	style.border_color = Color(0.35, 0.63, 0.82, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.48)
	style.shadow_size = 16
	return style


func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = color.lightened(0.13)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style
