class_name SettingsOverlay
extends Control

const ProgressiveOptionButtonScript = preload("res://ui/components/progressive_option_button.gd")
const ModalPointerGuardScript = preload("res://ui/components/modal_pointer_guard.gd")
const UiIconCatalog = preload("res://ui/theme/ui_icon_catalog.gd")

signal theme_selected(dark_mode: bool)
signal music_selected(enabled: bool)
signal sfx_selected(enabled: bool)
signal music_volume_selected(value: float)
signal sfx_volume_selected(value: float)
signal tutorial_requested

var language_selector: OptionButton
var light_button: Button
var dark_button: Button
var music_button: Button
var sfx_button: Button
var music_volume_slider: HSlider
var sfx_volume_slider: HSlider
var music_volume_label: Label
var sfx_volume_label: Label
var tutorial_button: Button
var close_button: Button

var _dark_mode := false
var _music_enabled := true
var _sfx_enabled := true
var _music_volume := 1.0
var _sfx_volume := 1.0
var _is_built := false
var _panel: PanelContainer
var _title: Label
var _section_labels: Array[Label] = []


func _init() -> void:
	name = "SettingsOverlay"
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_as_relative = false
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_ensure_built()


func set_dark_mode(value: bool) -> void:
	_dark_mode = value
	if _is_built:
		_apply_palette()
		_refresh_theme_buttons()


func set_audio_enabled(
	music_enabled: bool,
	sfx_enabled: bool,
	music_volume: float = -1.0,
	sfx_volume: float = -1.0
) -> void:
	_music_enabled = music_enabled
	_sfx_enabled = sfx_enabled
	if music_volume >= 0.0:
		_music_volume = clampf(music_volume, 0.0, 1.0)
	if sfx_volume >= 0.0:
		_sfx_volume = clampf(sfx_volume, 0.0, 1.0)
	if _is_built:
		music_button.set_pressed_no_signal(_music_enabled)
		sfx_button.set_pressed_no_signal(_sfx_enabled)
		music_volume_slider.set_value_no_signal(_music_volume * 100.0)
		sfx_volume_slider.set_value_no_signal(_sfx_volume * 100.0)
		_refresh_volume_labels()
		_refresh_audio_buttons()


func open() -> void:
	_ensure_built()
	_sync_language_selector()
	_refresh_theme_buttons()
	var localization = _localization_service()
	if localization != null:
		localization.localize_tree(self)
	show()
	move_to_front()
	close_button.grab_focus()


func close() -> void:
	hide()


func is_open() -> bool:
	return visible


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		accept_event()
		get_viewport().set_input_as_handled()


func _ensure_built() -> void:
	if _is_built:
		return
	_is_built = true

	var dimmer := ColorRect.new()
	dimmer.name = "SettingsDimmer"
	dimmer.color = Color(0.015, 0.03, 0.045, 0.66)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dimmer)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "SettingsPanel"
	# Six compact settings rows plus the header fit this bounded sheet without
	# leaving a billboard-sized blank field below the tutorial action.
	_panel.custom_minimum_size = Vector2(680, 432)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_bottom", 22)
	_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.name = "SettingsContent"
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	content.add_child(header)

	_title = Label.new()
	_title.text = "設定"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 30)
	header.add_child(_title)

	close_button = Button.new()
	close_button.name = "CloseSettingsButton"
	close_button.text = "×"
	close_button.tooltip_text = "關閉設定"
	close_button.custom_minimum_size = Vector2(48, 48)
	close_button.add_theme_font_size_override("font_size", 28)
	close_button.pressed.connect(_close_from_pointer)
	header.add_child(close_button)

	var language_row := _setting_row("介面語言")
	language_row.name = "LanguageSettingsRow"
	content.add_child(language_row)
	language_selector = ProgressiveOptionButtonScript.new()
	language_selector.name = "SettingsLanguageSelector"
	language_selector.custom_minimum_size = Vector2(240, 50)
	language_selector.add_theme_font_size_override("font_size", 18)
	language_selector.set_meta("l10n_skip", true)
	language_selector.call("set_show_all_choices", true)
	var localization = _localization_service()
	if localization != null:
		language_selector.call("set_choices", localization.locale_options(), localization.current_locale)
	language_selector.connect("choice_selected", func(locale_id: String) -> void:
		var current_localization = _localization_service()
		if current_localization != null:
			current_localization.set_locale(locale_id)
	)
	language_row.add_child(language_selector)

	var appearance_row := _setting_row("顯示模式")
	appearance_row.name = "AppearanceSettingsRow"
	content.add_child(appearance_row)
	var theme_picture := TextureRect.new()
	theme_picture.name = "ThemeModeIcon"
	theme_picture.texture = UiIconCatalog.texture("theme")
	theme_picture.custom_minimum_size = Vector2(44, 44)
	theme_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	theme_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	theme_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	appearance_row.add_child(theme_picture)
	var appearance_actions := HBoxContainer.new()
	appearance_actions.add_theme_constant_override("separation", 12)
	appearance_row.add_child(appearance_actions)
	light_button = _mode_button("LightThemeButton", "淺色")
	dark_button = _mode_button("DarkThemeButton", "深色")
	light_button.pressed.connect(func() -> void: theme_selected.emit(false))
	dark_button.pressed.connect(func() -> void: theme_selected.emit(true))
	appearance_actions.add_child(light_button)
	appearance_actions.add_child(dark_button)

	var audio_toggles := _setting_row("聲音")
	audio_toggles.name = "AudioToggleRow"
	content.add_child(audio_toggles)
	var audio_picture := TextureRect.new()
	audio_picture.name = "AudioSettingsIcon"
	audio_picture.texture = UiIconCatalog.texture("settings")
	audio_picture.custom_minimum_size = Vector2(44, 44)
	audio_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	audio_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	audio_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	audio_toggles.add_child(audio_picture)
	music_button = _mode_button("MusicToggleButton", "配樂")
	music_button.toggle_mode = true
	music_button.set_pressed_no_signal(_music_enabled)
	music_button.toggled.connect(func(enabled: bool) -> void:
		_music_enabled = enabled
		_refresh_audio_buttons()
		music_selected.emit(enabled)
	)
	sfx_button = _mode_button("SfxToggleButton", "音效")
	sfx_button.toggle_mode = true
	sfx_button.set_pressed_no_signal(_sfx_enabled)
	sfx_button.toggled.connect(func(enabled: bool) -> void:
		_sfx_enabled = enabled
		_refresh_audio_buttons()
		sfx_selected.emit(enabled)
	)
	audio_toggles.add_child(music_button)
	audio_toggles.add_child(sfx_button)

	var music_volume_controls := _volume_row("配樂音量", "MusicVolumeSlider", _music_volume)
	(music_volume_controls["row"] as HBoxContainer).name = "MusicVolumeRow"
	music_volume_slider = music_volume_controls["slider"]
	music_volume_label = music_volume_controls["value_label"]
	music_volume_slider.value_changed.connect(func(value: float) -> void:
		_music_volume = clampf(value / 100.0, 0.0, 1.0)
		_refresh_volume_labels()
		music_volume_selected.emit(_music_volume)
	)
	content.add_child(music_volume_controls["row"])

	var sfx_volume_controls := _volume_row("音效音量", "SfxVolumeSlider", _sfx_volume)
	(sfx_volume_controls["row"] as HBoxContainer).name = "SfxVolumeRow"
	sfx_volume_slider = sfx_volume_controls["slider"]
	sfx_volume_label = sfx_volume_controls["value_label"]
	sfx_volume_slider.value_changed.connect(func(value: float) -> void:
		_sfx_volume = clampf(value / 100.0, 0.0, 1.0)
		_refresh_volume_labels()
		sfx_volume_selected.emit(_sfx_volume)
	)
	content.add_child(sfx_volume_controls["row"])

	var tutorial_row := _setting_row("新手引導")
	tutorial_row.name = "TutorialSettingsRow"
	content.add_child(tutorial_row)
	var tutorial_picture := TextureRect.new()
	tutorial_picture.name = "TutorialSettingsIcon"
	tutorial_picture.texture = UiIconCatalog.texture("blueprint")
	tutorial_picture.custom_minimum_size = Vector2(44, 44)
	tutorial_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tutorial_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tutorial_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_row.add_child(tutorial_picture)
	tutorial_button = _mode_button("ReplayTutorialButton", "重播故事教學")
	tutorial_button.custom_minimum_size.x = 234
	tutorial_button.pressed.connect(func() -> void:
		close()
		tutorial_requested.emit()
	)
	tutorial_row.add_child(tutorial_button)

	_apply_palette()
	_sync_language_selector()
	_refresh_theme_buttons()
	_refresh_audio_buttons()
	_refresh_volume_labels()


func _setting_row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 44)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(148, 44)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 21)
	_section_labels.append(label)
	row.add_child(label)
	return row


func _mode_button(node_name: String, label_text: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = label_text
	button.tooltip_text = label_text
	button.custom_minimum_size = Vector2(150, 44)
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.add_theme_font_size_override("font_size", 18)
	return button


func _volume_row(label_text: String, node_name: String, value: float) -> Dictionary:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 44)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = label_text
	# Keep both rails on one fixed axis in every locale. Without clipping, a
	# longer translation expands one label's intrinsic minimum and shifts only
	# that slider to the right.
	# Volume captions need a wider shared column than the short section labels;
	# 196px keeps the complete English "Sound effects volume" visible while the
	# slider still has ample room inside the compact 680px sheet.
	label.custom_minimum_size = Vector2(196, 44)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.tooltip_text = label_text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	_section_labels.append(label)
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = node_name
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = clampf(value, 0.0, 1.0) * 100.0
	slider.custom_minimum_size = Vector2(220, 44)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_ALL
	slider.tooltip_text = "%s（0–100%%）" % label_text
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(72, 44)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 18)
	_section_labels.append(value_label)
	row.add_child(value_label)
	return {"row": row, "slider": slider, "value_label": value_label}


func _sync_language_selector() -> void:
	if language_selector == null:
		return
	var localization = _localization_service()
	if localization != null:
		language_selector.call("select_choice", localization.current_locale)


func _localization_service():
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/L10n")


func _close_from_pointer() -> void:
	get_viewport().set_input_as_handled()
	_arm_pointer_guard()
	close()


func _arm_pointer_guard() -> void:
	var parent_node := get_parent()
	if parent_node == null:
		return
	var guard := parent_node.get_node_or_null(ModalPointerGuardScript.GUARD_NODE_NAME)
	if guard == null:
		guard = ModalPointerGuardScript.new()
		parent_node.add_child(guard)
	guard.call("arm", get_viewport().get_mouse_position())


func _refresh_theme_buttons() -> void:
	if light_button == null or dark_button == null:
		return
	_style_mode_button(light_button, not _dark_mode)
	_style_mode_button(dark_button, _dark_mode)


func _refresh_audio_buttons() -> void:
	if music_button == null or sfx_button == null:
		return
	_style_mode_button(music_button, _music_enabled)
	_style_mode_button(sfx_button, _sfx_enabled)
	if tutorial_button != null:
		_style_mode_button(tutorial_button, false)


func _refresh_volume_labels() -> void:
	if music_volume_label != null:
		music_volume_label.text = "%d%%" % int(round(_music_volume * 100.0))
	if sfx_volume_label != null:
		sfx_volume_label.text = "%d%%" % int(round(_sfx_volume * 100.0))


func _apply_palette() -> void:
	if _panel == null:
		return
	var text_color := Color(0.91, 0.95, 0.98) if _dark_mode else Color(0.07, 0.12, 0.18)
	_panel.add_theme_stylebox_override("panel", _panel_style())
	_title.add_theme_color_override("font_color", text_color)
	for label in _section_labels:
		label.add_theme_color_override("font_color", text_color)
	_style_close_button()
	_refresh_theme_buttons()
	_refresh_audio_buttons()


func _style_close_button() -> void:
	if close_button == null:
		return
	var normal_background := Color(0.15, 0.23, 0.30) if _dark_mode else Color(0.88, 0.91, 0.91)
	var hover_background := Color(0.05, 0.43, 0.70) if _dark_mode else Color(0.47, 0.32, 0.15)
	var pressed_background := Color(0.03, 0.31, 0.52) if _dark_mode else Color(0.35, 0.23, 0.10)
	var disabled_background := Color(0.11, 0.16, 0.20) if _dark_mode else Color(0.90, 0.90, 0.86)
	var normal_text := Color(0.93, 0.96, 0.98) if _dark_mode else Color(0.07, 0.12, 0.18)
	var disabled_text := Color(0.63, 0.69, 0.74) if _dark_mode else Color(0.42, 0.45, 0.45)

	close_button.add_theme_stylebox_override("normal", _button_style(normal_background))
	close_button.add_theme_stylebox_override("hover", _button_style(hover_background))
	close_button.add_theme_stylebox_override("pressed", _button_style(pressed_background))
	close_button.add_theme_stylebox_override("focus", _focus_ring_style())
	close_button.add_theme_stylebox_override("disabled", _button_style(disabled_background))
	close_button.add_theme_color_override("font_color", normal_text)
	close_button.add_theme_color_override("font_hover_color", Color.WHITE)
	close_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	close_button.add_theme_color_override("font_focus_color", normal_text)
	close_button.add_theme_color_override("font_disabled_color", disabled_text)


func _style_mode_button(button: Button, selected: bool) -> void:
	var selected_color := Color(0.05, 0.43, 0.70)
	var idle_color := Color(0.16, 0.24, 0.31) if _dark_mode else Color(0.86, 0.89, 0.88)
	var normal_color := selected_color if selected else idle_color
	var hover_color := Color(0.08, 0.52, 0.82) if selected else (Color(0.22, 0.32, 0.40) if _dark_mode else Color(0.92, 0.93, 0.90))
	var pressed_color := Color(0.03, 0.31, 0.52) if selected else (Color(0.12, 0.19, 0.25) if _dark_mode else Color(0.77, 0.81, 0.80))
	var text_color := Color.WHITE if selected or _dark_mode else Color(0.08, 0.13, 0.17)
	button.add_theme_stylebox_override("normal", _button_style(normal_color))
	button.add_theme_stylebox_override("hover", _button_style(hover_color))
	button.add_theme_stylebox_override("pressed", _button_style(pressed_color))
	button.add_theme_stylebox_override("hover_pressed", _button_style(pressed_color))
	button.add_theme_stylebox_override("focus", _focus_ring_style())
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", Color.WHITE if selected or _dark_mode else Color(0.05, 0.10, 0.13))
	button.add_theme_color_override("font_pressed_color", Color.WHITE if selected or _dark_mode else Color(0.05, 0.10, 0.13))
	button.add_theme_color_override("font_hover_pressed_color", Color.WHITE if selected or _dark_mode else Color(0.05, 0.10, 0.13))
	button.add_theme_color_override("font_focus_color", text_color)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.12, 0.18, 0.99) if _dark_mode else Color(0.97, 0.95, 0.88, 0.99)
	style.border_color = Color(0.35, 0.63, 0.82) if _dark_mode else Color(0.52, 0.36, 0.17)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0, 0, 0, 0.46)
	style.shadow_size = 18
	return style


func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = color.lightened(0.14)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _focus_ring_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color(0.45, 0.76, 0.96) if _dark_mode else Color(0.52, 0.36, 0.17)
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	return style
