extends SceneTree

const SettingsOverlayScript = preload("res://ui/shell/settings_overlay.gd")

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var l10n = root.get_node_or_null("L10n")
	_check(l10n != null, "localization service is available")
	var original_locale: String = str(l10n.current_locale)
	var overlay = SettingsOverlayScript.new()
	root.add_child(overlay)
	await process_frame
	var settings_panel := overlay.find_child("SettingsPanel", true, false) as PanelContainer
	_check(settings_panel != null and settings_panel.custom_minimum_size == Vector2(680.0, 432.0), "settings panel uses the compact aligned layout contract")
	var theme_icon := overlay.find_child("ThemeModeIcon", true, false) as TextureRect
	_check(theme_icon != null, "theme mode row exposes the illustrated theme icon")
	if theme_icon != null:
		_check(theme_icon.texture != null, "theme mode icon texture is loaded")
		if theme_icon.texture != null:
			_check(
				str(theme_icon.texture.resource_path).contains("/storybook_v2/theme.png"),
				"theme mode row uses the active Storybook V2 asset"
			)
	_check(overlay.music_volume_slider != null, "settings exposes a music volume slider")
	_check(overlay.sfx_volume_slider != null, "settings exposes a sound-effect volume slider")
	var audio_toggle_row := overlay.find_child("AudioToggleRow", true, false) as HBoxContainer
	var music_volume_row := overlay.find_child("MusicVolumeRow", true, false) as HBoxContainer
	var sfx_volume_row := overlay.find_child("SfxVolumeRow", true, false) as HBoxContainer
	_check(audio_toggle_row != null and music_volume_row != null and sfx_volume_row != null, "audio controls expose named aligned rows")
	if audio_toggle_row != null and music_volume_row != null and sfx_volume_row != null:
		_check(audio_toggle_row.get_theme_constant("separation") == 12 and music_volume_row.get_theme_constant("separation") == 12 and sfx_volume_row.get_theme_constant("separation") == 12, "audio controls use the shared 12px horizontal rhythm")
		_check(overlay.music_button.custom_minimum_size == Vector2(150.0, 44.0) and overlay.sfx_button.custom_minimum_size == Vector2(150.0, 44.0), "audio toggles share 44px targets and a common baseline")
		_check((music_volume_row.get_child(0) as Label).custom_minimum_size == Vector2(196.0, 44.0) and (sfx_volume_row.get_child(0) as Label).custom_minimum_size == Vector2(196.0, 44.0), "English volume captions keep one complete aligned column")
		_check(overlay.music_volume_label.custom_minimum_size == Vector2(72.0, 44.0) and overlay.sfx_volume_label.custom_minimum_size == Vector2(72.0, 44.0), "volume percentages use one fixed right column")
	overlay.open()
	await process_frame
	_validate_compact_layout(overlay, settings_panel, audio_toggle_row, music_volume_row, sfx_volume_row)
	if overlay.music_volume_slider != null and overlay.sfx_volume_slider != null:
		_check(overlay.music_volume_slider.min_value == 0.0 and overlay.music_volume_slider.max_value == 100.0, "music volume range is 0-100")
		_check(overlay.sfx_volume_slider.min_value == 0.0 and overlay.sfx_volume_slider.max_value == 100.0, "SFX volume range is 0-100")
		_check(overlay.music_volume_slider.custom_minimum_size.x >= 44.0 and overlay.music_volume_slider.custom_minimum_size.y >= 44.0, "music slider minimum target is at least 44x44")
		_check(overlay.sfx_volume_slider.custom_minimum_size.x >= 44.0 and overlay.sfx_volume_slider.custom_minimum_size.y >= 44.0, "SFX slider minimum target is at least 44x44")
		var emitted_music_values: Array[float] = []
		overlay.music_volume_selected.connect(func(value: float) -> void: emitted_music_values.append(value))
		overlay.set_audio_enabled(true, true, 0.42, 0.73)
		_check(emitted_music_values.is_empty(), "programmatic audio synchronization emits no player change signal")
		_check(is_equal_approx(overlay.music_volume_slider.value, 42.0), "music slider reflects the synchronized value")
		_check(is_equal_approx(overlay.sfx_volume_slider.value, 73.0), "SFX slider reflects the synchronized value")
		_check(overlay.music_volume_label.text == "42%" and overlay.sfx_volume_label.text == "73%", "volume percentages remain visible")
		overlay.music_volume_slider.value = 18.0
		_check(emitted_music_values.size() == 1 and is_equal_approx(emitted_music_values[0], 0.18), "player slider movement emits normalized music volume")

	for dark_mode in [false, true]:
		overlay.set_dark_mode(dark_mode)
		await process_frame
		_validate_close_button(overlay.close_button, "dark" if dark_mode else "light")
		_validate_mode_buttons(overlay, dark_mode, "before locale switch")

	var switched_locale := "en" if original_locale != "en" else "ja"
	_check(l10n.set_locale(switched_locale, false), "test locale can be selected")
	overlay.open()
	await process_frame
	_validate_mode_buttons(overlay, true, "after locale switch")
	_validate_compact_layout(overlay, settings_panel, audio_toggle_row, music_volume_row, sfx_volume_row)
	_check(
		overlay.language_selector.selected_choice_id() == switched_locale,
		"language selector reflects the switched locale"
	)
	_check(overlay.language_selector.choice_count() == 5, "all language choices remain available")
	_check(overlay.language_selector.visible_popup_item_count() == 5, "all five language choices are exposed on one popup page")
	_check(overlay.language_selector.shows_all_choices(), "settings language selector has no More paging")
	l10n.set_locale(original_locale, false)

	if _failed:
		quit(1)
	else:
		print("Settings overlay state style test passed.")
		quit(0)


func _validate_compact_layout(overlay, panel: Control, audio_toggle_row: HBoxContainer, music_row: HBoxContainer, sfx_row: HBoxContainer) -> void:
	_check(panel != null and Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(panel.get_global_rect()), "laid-out settings panel stays inside 1280x720")
	if panel == null:
		return
	var panel_rect := panel.get_global_rect()
	_check(panel_rect.size.x >= 640.0 and panel_rect.size.x <= 700.0 and panel_rect.size.y >= 420.0 and panel_rect.size.y <= 460.0, "laid-out settings panel keeps a bounded compact footprint")
	var content := overlay.find_child("SettingsContent", true, false) as Control
	var tutorial_row := overlay.find_child("TutorialSettingsRow", true, false) as Control
	_check(content != null and tutorial_row != null, "settings compact grid exposes its content and final row")
	if content != null and tutorial_row != null:
		_check(panel_rect.end.y - tutorial_row.get_global_rect().end.y <= 24.0, "settings layout avoids a large lower blank field")
	if audio_toggle_row == null or music_row == null or sfx_row == null:
		return
	var music_slider_rect: Rect2 = overlay.music_volume_slider.get_global_rect()
	var sfx_slider_rect: Rect2 = overlay.sfx_volume_slider.get_global_rect()
	var music_percent_rect: Rect2 = overlay.music_volume_label.get_global_rect()
	var sfx_percent_rect: Rect2 = overlay.sfx_volume_label.get_global_rect()
	_check(is_equal_approx(music_slider_rect.position.x, sfx_slider_rect.position.x) and is_equal_approx(music_slider_rect.end.x, sfx_slider_rect.end.x), "laid-out music and SFX rails share exact x axes")
	_check(is_equal_approx(music_percent_rect.position.x, sfx_percent_rect.position.x) and is_equal_approx(music_percent_rect.end.x, sfx_percent_rect.end.x), "laid-out music and SFX percentages share exact x axes")
	_check(is_equal_approx(overlay.music_button.get_global_rect().position.y, overlay.sfx_button.get_global_rect().position.y) and is_equal_approx(overlay.music_button.get_global_rect().size.x, overlay.sfx_button.get_global_rect().size.x), "laid-out audio toggles share their baseline and width")


func _validate_mode_buttons(overlay, dark_mode: bool, phase: String) -> void:
	var selected_button: Button = overlay.dark_button if dark_mode else overlay.light_button
	var idle_button: Button = overlay.light_button if dark_mode else overlay.dark_button
	for button in [selected_button, idle_button, overlay.music_button, overlay.sfx_button]:
		_check(
			button.tooltip_text == button.text and not button.tooltip_text.is_empty(),
			"%s clipped mode labels preserve their complete localized tooltip" % phase
		)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		_check(selected_button.has_theme_stylebox_override(state), "%s selected mode defines %s background" % [phase, state])
		_check(idle_button.has_theme_stylebox_override(state), "%s idle mode defines %s background" % [phase, state])
		var selected_style := selected_button.get_theme_stylebox(state) as StyleBoxFlat
		var idle_style := idle_button.get_theme_stylebox(state) as StyleBoxFlat
		_check(
			_color_distance(selected_style.bg_color, idle_style.bg_color) >= 0.15,
			"%s selected mode remains visibly distinct in %s state" % [phase, state]
		)
		_check(
			selected_style.bg_color.b > selected_style.bg_color.r + 0.20,
			"%s selected mode keeps its blue highlight in %s state" % [phase, state]
		)


func _color_distance(first: Color, second: Color) -> float:
	return sqrt(
		pow(first.r - second.r, 2.0)
		+ pow(first.g - second.g, 2.0)
		+ pow(first.b - second.b, 2.0)
	)


func _validate_close_button(button: Button, palette_name: String) -> void:
	_check(button != null, "%s palette creates the close button" % palette_name)
	if button == null:
		return
	var font_names := {
		"normal": "font_color",
		"hover": "font_hover_color",
		"pressed": "font_pressed_color",
		"focus": "font_focus_color",
		"disabled": "font_disabled_color",
	}
	for state in font_names:
		_check(button.has_theme_stylebox_override(state), "%s palette defines %s background" % [palette_name, state])
		_check(button.has_theme_color_override(font_names[state]), "%s palette defines %s text" % [palette_name, state])
		var background_state: String = "normal" if state == "focus" else str(state)
		var background := button.get_theme_stylebox(background_state) as StyleBoxFlat
		var foreground := button.get_theme_color(font_names[state])
		var minimum_ratio := 3.0 if state == "disabled" else 4.5
		_check(
			_contrast_ratio(foreground, background.bg_color) >= minimum_ratio,
			"%s palette keeps %s text contrast at or above %.1f:1" % [palette_name, state, minimum_ratio]
		)
	var focus_style := button.get_theme_stylebox("focus") as StyleBoxFlat
	_check(is_zero_approx(focus_style.bg_color.a), "%s focus state uses a transparent ring" % palette_name)
	_check(focus_style.border_width_left >= 3, "%s focus ring remains keyboard-visible" % palette_name)


func _contrast_ratio(first: Color, second: Color) -> float:
	var first_luminance := _relative_luminance(first)
	var second_luminance := _relative_luminance(second)
	return (maxf(first_luminance, second_luminance) + 0.05) / (minf(first_luminance, second_luminance) + 0.05)


func _relative_luminance(color: Color) -> float:
	return (
		0.2126 * _linear_channel(color.r)
		+ 0.7152 * _linear_channel(color.g)
		+ 0.0722 * _linear_channel(color.b)
	)


func _linear_channel(value: float) -> float:
	if value <= 0.04045:
		return value / 12.92
	return pow((value + 0.055) / 1.055, 2.4)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Settings overlay style check failed: %s" % message)
