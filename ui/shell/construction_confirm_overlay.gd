extends Control

signal confirmed(tile_index: int)
signal cancelled

var _is_built := false
var _dark_mode := false
var _tile_index := -1
var _panel: PanelContainer
var _title_label: Label
var _summary_label: Label
var _cost_label: Label
var _funds_label: Label
var _cancel_button: Button
var _confirm_button: Button
var _close_button: Button


func _init() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_as_relative = false
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_ensure_built()


func set_dark_mode(enabled: bool) -> void:
	_dark_mode = enabled
	_apply_palette()


func open(building_name: String, tile_index: int, quote: Dictionary, treasury: int) -> void:
	_ensure_built()
	_tile_index = tile_index
	L10n.localize_tree(self)
	_title_label.text = L10n.text("確認開工：%s") % L10n.text(building_name)
	_summary_label.text = L10n.text("地格 %d｜工程隊 %d 人｜預計 %d 個遊戲日") % [
		tile_index + 1,
		int(quote.get("worker_count", 0)),
		int(quote.get("duration_days", 0))
	]
	_cost_label.text = L10n.text("基礎造價 $%s　＋　預付人工 $%s　＝　總造價 $%s") % [
		_format_money(int(quote.get("base_cost", 0))),
		_format_money(int(quote.get("labor_cost", quote.get("total_labor_cost", 0)))),
		_format_money(int(quote.get("total_cost", 0)))
	]
	var total_cost := int(quote.get("total_cost", 0))
	var remaining := treasury - total_cost
	_funds_label.text = L10n.text("目前公庫 $%s｜確認後餘額 $%s") % [
		_format_money(treasury),
		_format_money(remaining)
	]
	_funds_label.add_theme_color_override(
		"font_color",
		_color_success() if remaining >= 0 else _color_danger()
	)
	_confirm_button.disabled = remaining < 0
	_confirm_button.tooltip_text = L10n.text("確認後才會扣除總造價並開始施工。")
	show()
	move_to_front()
	_cancel_button.grab_focus()


func close() -> void:
	hide()
	_tile_index = -1


func is_open() -> bool:
	return visible


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
	dimmer.name = "ConstructionConfirmDimmer"
	dimmer.color = Color(0.015, 0.03, 0.045, 0.76)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dimmer)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "ConstructionConfirmPanel"
	_panel.custom_minimum_size = Vector2(680, 340)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	margin.add_child(content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	content.add_child(header)

	_title_label = Label.new()
	_title_label.text = "確認開工"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.add_theme_font_size_override("font_size", 28)
	header.add_child(_title_label)

	_close_button = Button.new()
	_close_button.name = "CloseConstructionConfirmButton"
	_close_button.text = "×"
	_close_button.tooltip_text = "返回選擇地格"
	_close_button.custom_minimum_size = Vector2(48, 48)
	_close_button.add_theme_font_size_override("font_size", 28)
	_close_button.pressed.connect(_cancel)
	header.add_child(_close_button)

	_summary_label = Label.new()
	_summary_label.name = "ConstructionConfirmSummary"
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_label.add_theme_font_size_override("font_size", 20)
	content.add_child(_summary_label)

	var cost_card := PanelContainer.new()
	cost_card.name = "ConstructionCostCard"
	cost_card.add_theme_stylebox_override("panel", _cost_card_style())
	content.add_child(cost_card)
	var cost_margin := MarginContainer.new()
	cost_margin.add_theme_constant_override("margin_left", 18)
	cost_margin.add_theme_constant_override("margin_top", 14)
	cost_margin.add_theme_constant_override("margin_right", 18)
	cost_margin.add_theme_constant_override("margin_bottom", 14)
	cost_card.add_child(cost_margin)
	_cost_label = Label.new()
	_cost_label.name = "ConstructionCostBreakdown"
	_cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cost_label.add_theme_font_size_override("font_size", 22)
	cost_margin.add_child(_cost_label)

	_funds_label = Label.new()
	_funds_label.name = "ConstructionFundsAfterConfirm"
	_funds_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_funds_label.add_theme_font_size_override("font_size", 19)
	content.add_child(_funds_label)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	content.add_child(actions)

	_cancel_button = Button.new()
	_cancel_button.name = "CancelConstructionButton"
	_cancel_button.text = "返回選地"
	_cancel_button.custom_minimum_size = Vector2(148, 52)
	_cancel_button.add_theme_font_size_override("font_size", 20)
	_cancel_button.pressed.connect(_cancel)
	actions.add_child(_cancel_button)

	_confirm_button = Button.new()
	_confirm_button.name = "ConfirmConstructionButton"
	_confirm_button.text = "確認開工"
	_confirm_button.custom_minimum_size = Vector2(176, 52)
	_confirm_button.add_theme_font_size_override("font_size", 20)
	_confirm_button.pressed.connect(_confirm)
	actions.add_child(_confirm_button)

	_apply_palette()


func _cancel() -> void:
	close()
	cancelled.emit()


func _confirm() -> void:
	if _tile_index < 0 or _confirm_button.disabled:
		return
	var confirmed_tile := _tile_index
	close()
	confirmed.emit(confirmed_tile)


func _apply_palette() -> void:
	if not _is_built or _panel == null:
		return
	var text_color := Color(0.91, 0.95, 0.98) if _dark_mode else Color(0.07, 0.12, 0.18)
	var secondary := Color(0.68, 0.76, 0.82) if _dark_mode else Color(0.24, 0.31, 0.38)
	_panel.add_theme_stylebox_override("panel", _panel_style())
	_title_label.add_theme_color_override("font_color", text_color)
	_summary_label.add_theme_color_override("font_color", secondary)
	_cost_label.add_theme_color_override("font_color", text_color)
	_style_button(_close_button, Color(0.15, 0.23, 0.30) if _dark_mode else Color(0.86, 0.89, 0.88), false)
	_style_button(_cancel_button, Color(0.18, 0.29, 0.38) if _dark_mode else Color(0.80, 0.84, 0.83), false)
	_style_button(_confirm_button, Color(0.05, 0.43, 0.70), true)


func _style_button(button: Button, base: Color, primary: bool) -> void:
	if button == null:
		return
	var font := Color.WHITE if primary or _dark_mode else Color(0.07, 0.12, 0.18)
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		button.add_theme_color_override(state, font)
	button.add_theme_color_override("font_disabled_color", Color(font, 0.48))
	button.add_theme_stylebox_override("normal", _button_style(base))
	button.add_theme_stylebox_override("hover", _button_style(base.lightened(0.10)))
	button.add_theme_stylebox_override("focus", _button_style(base.lightened(0.14)))
	button.add_theme_stylebox_override("pressed", _button_style(base.darkened(0.12)))
	button.add_theme_stylebox_override("disabled", _button_style(base.darkened(0.08)))


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.12, 0.18, 0.99) if _dark_mode else Color(0.97, 0.95, 0.88, 0.99)
	style.border_color = Color(0.35, 0.63, 0.82) if _dark_mode else Color(0.52, 0.36, 0.17)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0, 0, 0, 0.46)
	style.shadow_size = 18
	return style


func _cost_card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.18, 0.25, 0.96) if _dark_mode else Color(0.91, 0.89, 0.80, 1.0)
	style.border_color = Color(0.25, 0.55, 0.74) if _dark_mode else Color(0.66, 0.48, 0.24)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	return style


func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = color.lightened(0.14)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style


func _color_success() -> Color:
	return Color(0.35, 0.86, 0.57) if _dark_mode else Color(0.05, 0.42, 0.23)


func _color_danger() -> Color:
	return Color(1.0, 0.48, 0.42) if _dark_mode else Color(0.77, 0.18, 0.08)


func _format_money(amount: int) -> String:
	var digits := str(absi(amount))
	var insert_at := digits.length() - 3
	while insert_at > 0:
		digits = digits.insert(insert_at, ",")
		insert_at -= 3
	return ("-" if amount < 0 else "") + digits
