class_name StartScreen
extends Control

const ProgressiveOptionButtonScript = preload("res://ui/components/progressive_option_button.gd")
const UiIconCatalog = preload("res://ui/theme/ui_icon_catalog.gd")

signal game_requested(mode: String)
signal load_action_requested(mode: String)
signal loading_finished(mode: String)

const BACKGROUND_PATH := "res://assets/images/world/backgrounds/city-map-background.png"
const ICONS := {
	"new": "city_hall",
	"continue": "time",
}
const SAVE_AVAILABLE_COLOR := Color(0.05, 0.38, 0.20)
const SAVE_MISSING_COLOR := Color(0.42, 0.24, 0.04)
const SAVE_FAILURE_COLOR := Color(0.62, 0.14, 0.08)

var animation_duration := 1.15
var new_game_button: Button
var continue_game_button: Button
var progress_bar: ProgressBar
var progress_label: Label
var loading_label: Label
var save_status_label: Label
var background_picture: TextureRect
var language_selector: OptionButton

var _button_row: HBoxContainer
var _loading_box: VBoxContainer
var _loading_tween: Tween
var _is_loading := false


func _init() -> void:
	name = "StartScreen"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_as_relative = false
	z_index = 4000
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_content()


func set_continue_available(available: bool) -> void:
	if save_status_label == null:
		return
	save_status_label.text = "找到既有城市存檔" if available else "尚未找到存檔；點擊後會再次檢查"
	save_status_label.add_theme_color_override(
		"font_color",
		SAVE_AVAILABLE_COLOR if available else SAVE_MISSING_COLOR
	)
	L10n.localize_tree(self)


func play_loading(mode: String) -> void:
	if _is_loading or mode not in ["new", "continue"]:
		return
	_is_loading = true
	new_game_button.disabled = true
	continue_game_button.disabled = true
	_button_row.visible = false
	_loading_box.visible = true
	progress_bar.value = 0.0
	progress_label.text = "0%"
	loading_label.text = "建立新的城市資料…" if mode == "new" else "讀取城市存檔…"
	L10n.localize_tree(self)
	if _loading_tween != null and _loading_tween.is_valid():
		_loading_tween.kill()
	var duration := maxf(0.03, animation_duration)
	_loading_tween = create_tween()
	_loading_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_loading_tween.tween_property(progress_bar, "value", 38.0, duration * 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_loading_tween.tween_callback(func() -> void:
		loading_label.text = "整理城市資料…"
		L10n.localize_tree(self)
		load_action_requested.emit(mode)
	)
	_loading_tween.tween_property(progress_bar, "value", 82.0, duration * 0.38).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_loading_tween.tween_callback(func() -> void:
		loading_label.text = "準備進入城市…"
		L10n.localize_tree(self)
	)
	_loading_tween.tween_property(progress_bar, "value", 100.0, duration * 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_loading_tween.tween_callback(func() -> void: loading_finished.emit(mode))


func complete_success() -> void:
	_is_loading = false
	hide()


func show_failure(message: String) -> void:
	_is_loading = false
	_loading_box.visible = false
	_button_row.visible = true
	new_game_button.disabled = false
	continue_game_button.disabled = false
	save_status_label.text = message
	save_status_label.add_theme_color_override("font_color", SAVE_FAILURE_COLOR)
	continue_game_button.grab_focus()
	L10n.localize_tree(self)


func is_loading() -> bool:
	return _is_loading


func _build_content() -> void:
	background_picture = TextureRect.new()
	background_picture.name = "StartBackground"
	background_picture.texture = load(BACKGROUND_PATH) as Texture2D
	background_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background_picture)

	var dimmer := ColorRect.new()
	dimmer.color = Color(0.02, 0.07, 0.10, 0.48)
	dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dimmer)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card := PanelContainer.new()
	card.name = "StartMenuCard"
	card.custom_minimum_size = Vector2(620, 560)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(1.0, 0.96, 0.84, 0.96)
	card_style.border_color = Color(0.48, 0.30, 0.12)
	card_style.set_border_width_all(4)
	card_style.set_corner_radius_all(20)
	card_style.content_margin_left = 34
	card_style.content_margin_top = 26
	card_style.content_margin_right = 34
	card_style.content_margin_bottom = 28
	card_style.shadow_color = Color(0, 0, 0, 0.35)
	card_style.shadow_size = 10
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)

	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 14)
	card.add_child(stack)

	var emblem := TextureRect.new()
	emblem.texture = UiIconCatalog.texture(str(ICONS["new"]))
	emblem.custom_minimum_size = Vector2(0, 150)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(emblem)

	var title := Label.new()
	title.text = "Mayor Simulator"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color(0.08, 0.15, 0.20))
	stack.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "童話城市・市政治理模擬"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.max_lines_visible = 2
	subtitle.custom_minimum_size = Vector2(0, 52)
	subtitle.add_theme_font_size_override("font_size", 21)
	subtitle.add_theme_color_override("font_color", Color(0.32, 0.36, 0.38))
	stack.add_child(subtitle)

	var language_row := HBoxContainer.new()
	language_row.alignment = BoxContainer.ALIGNMENT_CENTER
	language_row.add_theme_constant_override("separation", 10)
	stack.add_child(language_row)
	var language_label := Label.new()
	language_label.text = "語言"
	language_label.add_theme_font_size_override("font_size", 18)
	language_label.add_theme_color_override("font_color", Color(0.18, 0.25, 0.28))
	language_row.add_child(language_label)
	language_selector = ProgressiveOptionButtonScript.new()
	language_selector.name = "StartLanguageSelector"
	language_selector.custom_minimum_size = Vector2(190, 42)
	language_selector.add_theme_font_size_override("font_size", 18)
	language_selector.set_meta("l10n_skip", true)
	language_selector.call("set_show_all_choices", true)
	language_selector.call("set_choices", L10n.locale_options(), L10n.current_locale)
	language_selector.connect("choice_selected", func(locale_id: String) -> void: L10n.set_locale(locale_id))
	language_row.add_child(language_selector)

	_button_row = HBoxContainer.new()
	_button_row.name = "StartActions"
	_button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_button_row.add_theme_constant_override("separation", 18)
	stack.add_child(_button_row)
	new_game_button = _menu_button("NewGameButton", "新遊戲", "new", true)
	continue_game_button = _menu_button("ContinueGameButton", "繼續遊戲", "continue", false)
	_button_row.add_child(new_game_button)
	_button_row.add_child(continue_game_button)

	save_status_label = Label.new()
	save_status_label.name = "SaveStatus"
	save_status_label.text = "正在檢查存檔…"
	save_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	save_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	save_status_label.max_lines_visible = 2
	save_status_label.custom_minimum_size = Vector2(0, 44)
	save_status_label.add_theme_font_size_override("font_size", 18)
	stack.add_child(save_status_label)

	_loading_box = VBoxContainer.new()
	_loading_box.name = "LoadingState"
	_loading_box.visible = false
	_loading_box.add_theme_constant_override("separation", 8)
	stack.add_child(_loading_box)
	loading_label = Label.new()
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	loading_label.max_lines_visible = 2
	loading_label.custom_minimum_size = Vector2(0, 52)
	loading_label.add_theme_font_size_override("font_size", 21)
	loading_label.add_theme_color_override("font_color", Color(0.08, 0.15, 0.20))
	_loading_box.add_child(loading_label)
	progress_bar = ProgressBar.new()
	progress_bar.name = "LoadingProgress"
	progress_bar.custom_minimum_size = Vector2(0, 30)
	progress_bar.min_value = 0
	progress_bar.max_value = 100
	progress_bar.show_percentage = false
	var progress_bg := StyleBoxFlat.new()
	progress_bg.bg_color = Color(0.77, 0.79, 0.75)
	progress_bg.set_corner_radius_all(12)
	progress_bar.add_theme_stylebox_override("background", progress_bg)
	var progress_fill := StyleBoxFlat.new()
	progress_fill.bg_color = Color(0.05, 0.52, 0.32)
	progress_fill.set_corner_radius_all(12)
	progress_bar.add_theme_stylebox_override("fill", progress_fill)
	progress_bar.value_changed.connect(func(value: float) -> void: progress_label.text = "%d%%" % roundi(value))
	_loading_box.add_child(progress_bar)
	progress_label = Label.new()
	progress_label.text = "0%"
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_label.add_theme_font_size_override("font_size", 18)
	progress_label.add_theme_color_override("font_color", Color(0.18, 0.25, 0.28))
	_loading_box.add_child(progress_label)

	new_game_button.pressed.connect(func() -> void: game_requested.emit("new"))
	continue_game_button.pressed.connect(func() -> void: game_requested.emit("continue"))
	L10n.localize_tree(self)


func _menu_button(node_name: String, label_text: String, icon_key: String, primary: bool) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = ""
	button.set_meta("semantic_label", label_text)
	button.custom_minimum_size = Vector2(250, 104)
	var button_stack := VBoxContainer.new()
	button_stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button_stack.offset_left = 8
	button_stack.offset_top = 6
	button_stack.offset_right = -8
	button_stack.offset_bottom = -6
	button_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	button_stack.add_theme_constant_override("separation", 2)
	button_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(button_stack)
	var icon := TextureRect.new()
	icon.texture = UiIconCatalog.texture(str(ICONS[icon_key]))
	icon.custom_minimum_size = Vector2(0, 58)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button_stack.add_child(icon)
	var caption := Label.new()
	caption.text = label_text
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.max_lines_visible = 2
	caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_color_override("font_color", Color.WHITE if primary else Color(0.08, 0.12, 0.16))
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button_stack.add_child(caption)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.05, 0.43, 0.70) if primary else Color(0.96, 0.89, 0.72)
	normal.border_color = Color(0.03, 0.31, 0.52) if primary else Color(0.60, 0.42, 0.20)
	normal.set_border_width_all(3)
	normal.set_corner_radius_all(12)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.08, 0.52, 0.82) if primary else Color(1.0, 0.95, 0.82)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.03, 0.31, 0.52) if primary else Color(0.86, 0.75, 0.56)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", Color.WHITE if primary else Color(0.08, 0.12, 0.16))
	button.add_theme_color_override("font_hover_color", Color.WHITE if primary else Color(0.08, 0.12, 0.16))
	return button
