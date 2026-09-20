class_name TutorialStoryOverlay
extends Control

const BACKGROUND = preload("res://assets/images/tutorial/story-intro-background.png")
const UiIconCatalog = preload("res://ui/theme/ui_icon_catalog.gd")
const ContentRegistry = preload("res://data/catalogs/content_registry.gd")

signal completed(skipped: bool)
signal audio_cue(cue: String)

const PAGES := [
	{
		"kicker": "序章｜黎明中的新城市",
		"title": "一座城市，把選擇交到你手上",
		"body": "河谷剛迎來清晨。居民需要住處、工作、公共服務，也需要一套不讓任何權力失控的制度。你的任務不是把數字堆高，而是讓城市能長久運作。",
		"bullets": ["遊戲時間每 120 秒自動推進一天，日期區不需點擊。", "所有重要操作都會提供即時回饋與自動存檔"],
		"icon": "city_hall",
	},
	{
		"kicker": "第一步｜興建",
		"title": "先從官方入門藍圖開始",
		"body": "選擇建築後，遊戲已替 %d 種建築準備核准的入門藍圖。你不必先理解材質、樓層與工期，就能直接回到地圖選空地施工。",
		"bullets": ["建築卡使用逐棟專屬圖像，圖像與名稱一致", "綠色加號表示可施工；紅色叉號表示地塊受阻"],
		"icon": "buildings",
	},
	{
		"kicker": "第二步｜藍圖庫",
		"title": "核准一次，永久反覆套用",
		"body": "想微調材質、規模或裝飾時，可以送審自訂版。通過後它會另存進永久藍圖庫，不會因開工而消失，也不會覆蓋官方入門版。",
		"bullets": ["藍圖庫會保存於遊戲存檔", "可在官方版與所有自訂核准版之間切換"],
		"icon": "blueprint",
	},
	{
		"kicker": "第三步｜讀懂城市",
		"title": "先看需要決策的資料",
		"body": "九項月度數據全部集中在城市數據：第一個月與安全線比較，第二個月起與上月比較，安全線警告永遠保留。月報只記錄重大事件與版本更新，不再重複常態數據。",
		"bullets": ["金色直線是安全基準，圓點會動畫移到目前值", "紅綠區域與百分點差距可以直接判斷風險"],
		"icon": "city_data",
	},
	{
		"kicker": "第四步｜三權分治",
		"title": "行政提出，立法表決，司法制衡",
		"body": "法案會交由 30 名下議員逐人表決，再進入上議院區域審查。若行政權強制施行被否決的法案，系統會自動開啟獨立司法審查與監察調查。",
		"bullets": ["法院停令會實際停止該法的每月效果", "治理頁會留下行政 → 立法 → 司法的制衡軌跡"],
		"icon": "governance",
	},
	{
		"kicker": "準備完成",
		"title": "從一棟住宅開始，讓制度跟著城市成長",
		"body": "建議先選住宅或公園，使用官方入門藍圖完成第一項工程；再打開城市數據查看下一個最需要改善的項目。",
		"bullets": ["右下角市政按鈕可開啟所有管理頁面", "設定頁可隨時重播這段故事教學"],
		"icon": "score",
	},
]

var current_page := 0
var background_picture: TextureRect
var atmosphere: ColorRect
var story_panel: PanelContainer
var kicker_label: Label
var title_label: Label
var body_label: Label
var bullets_box: VBoxContainer
var page_icon: TextureRect
var progress_box: HBoxContainer
var back_button: Button
var next_button: Button
var skip_button: Button
var _ambient_time := 0.0
var _transition: Tween
var _closing := false


func _init() -> void:
	name = "TutorialStoryOverlay"
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_as_relative = false
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX - 2
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _process(delta: float) -> void:
	if not visible:
		return
	_ambient_time += delta
	var drift_x := sin(_ambient_time * 0.11) * 12.0
	var drift_y := cos(_ambient_time * 0.08) * 7.0
	background_picture.offset_left = -34.0 + drift_x
	background_picture.offset_top = -28.0 + drift_y
	background_picture.offset_right = 34.0 + drift_x
	background_picture.offset_bottom = 28.0 + drift_y
	atmosphere.modulate.a = 0.34 + sin(_ambient_time * 0.65) * 0.06


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_instance_valid(story_panel):
		_layout_dialogue_strip()


func open(reset_to_start: bool = true) -> void:
	_closing = false
	if reset_to_start:
		current_page = 0
	_refresh_page(false)
	_layout_dialogue_strip()
	modulate.a = 0.0
	show()
	move_to_front()
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_SINE)
	next_button.grab_focus()


func close_as_completed(skipped: bool = false) -> void:
	if _closing:
		return
	_closing = true
	if _transition != null and _transition.is_valid():
		_transition.kill()
	_transition = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_transition.tween_property(self, "modulate:a", 0.0, 0.24).set_trans(Tween.TRANS_SINE)
	_transition.tween_callback(func() -> void:
		hide()
		_closing = false
		completed.emit(skipped)
	)


func is_open() -> bool:
	return visible


func _build() -> void:
	background_picture = TextureRect.new()
	background_picture.name = "TutorialStoryBackground"
	background_picture.texture = BACKGROUND
	background_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background_picture)

	var shade := ColorRect.new()
	shade.name = "TutorialStoryShade"
	shade.color = Color(0.06, 0.08, 0.07, 0.12)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	atmosphere = ColorRect.new()
	atmosphere.name = "TutorialDawnPulse"
	atmosphere.color = Color(1.0, 0.78, 0.38, 0.10)
	atmosphere.mouse_filter = Control.MOUSE_FILTER_IGNORE
	atmosphere.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(atmosphere)

	story_panel = PanelContainer.new()
	story_panel.name = "TutorialStoryPanel"
	story_panel.anchor_left = 0.0
	story_panel.anchor_top = 1.0
	story_panel.anchor_right = 1.0
	story_panel.anchor_bottom = 1.0
	story_panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(story_panel)
	_layout_dialogue_strip()

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 14)
	story_panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	margin.add_child(content)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 14)
	content.add_child(top_row)
	var portrait_badge := PanelContainer.new()
	portrait_badge.name = "TutorialSpeakerBadge"
	portrait_badge.custom_minimum_size = Vector2(88, 88)
	portrait_badge.add_theme_stylebox_override("panel", _speaker_badge_style())
	top_row.add_child(portrait_badge)
	page_icon = TextureRect.new()
	page_icon.custom_minimum_size = Vector2(78, 78)
	page_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	page_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	page_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_badge.add_child(page_icon)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 2)
	top_row.add_child(heading)
	kicker_label = _label("", 16, Color(0.10, 0.43, 0.42))
	kicker_label.name = "TutorialKicker"
	heading.add_child(kicker_label)
	title_label = _label("", 28, Color(0.25, 0.19, 0.13))
	title_label.name = "TutorialTitle"
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.custom_minimum_size = Vector2(0, 38)
	heading.add_child(title_label)
	body_label = _label("", 18, Color(0.24, 0.29, 0.29))
	body_label.name = "TutorialBody"
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	heading.add_child(body_label)
	bullets_box = VBoxContainer.new()
	bullets_box.name = "TutorialBullets"
	bullets_box.add_theme_constant_override("separation", 2)
	content.add_child(bullets_box)
	var footer := HBoxContainer.new()
	footer.name = "TutorialDialogueFooter"
	footer.add_theme_constant_override("separation", 8)
	content.add_child(footer)
	progress_box = HBoxContainer.new()
	progress_box.name = "TutorialProgress"
	progress_box.alignment = BoxContainer.ALIGNMENT_CENTER
	progress_box.add_theme_constant_override("separation", 6)
	footer.add_child(progress_box)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var actions := HBoxContainer.new()
	actions.name = "TutorialDialogueActions"
	actions.add_theme_constant_override("separation", 8)
	footer.add_child(actions)
	skip_button = _button("TutorialSkipButton", "跳過教學", false)
	skip_button.tooltip_text = "略過後仍可從設定頁重播。"
	skip_button.pressed.connect(func() -> void:
		audio_cue.emit("click")
		close_as_completed(true)
	)
	actions.add_child(skip_button)
	back_button = _button("TutorialBackButton", "上一步", false)
	back_button.pressed.connect(_go_back)
	actions.add_child(back_button)
	next_button = _button("TutorialNextButton", "下一步", true)
	next_button.pressed.connect(_go_next)
	actions.add_child(next_button)


func _refresh_page(animated: bool = true) -> void:
	current_page = clampi(current_page, 0, PAGES.size() - 1)
	if animated:
		if _transition != null and _transition.is_valid():
			_transition.kill()
		_transition = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_transition.tween_property(story_panel, "modulate:a", 0.0, 0.10)
		_transition.tween_callback(_apply_page_content)
		_transition.tween_property(story_panel, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE)
		return
	_apply_page_content()
	story_panel.modulate.a = 1.0


func _apply_page_content() -> void:
	var page: Dictionary = PAGES[current_page]
	kicker_label.text = _l10n_text(str(page["kicker"]))
	title_label.text = _l10n_text(str(page["title"]))
	var localized_body := _l10n_text(str(page["body"]))
	if localized_body.contains("%d"):
		localized_body = localized_body % ContentRegistry.BUILDING_IDS.size()
	body_label.text = localized_body
	page_icon.texture = UiIconCatalog.texture(str(page["icon"]))
	for child in bullets_box.get_children():
		bullets_box.remove_child(child)
		child.queue_free()
	for bullet in page["bullets"]:
		var label := _label("◆  %s" % _l10n_text(str(bullet)), 16, Color(0.27, 0.37, 0.36))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bullets_box.add_child(label)
	for child in progress_box.get_children():
		progress_box.remove_child(child)
		child.queue_free()
	for index in PAGES.size():
		var dot := Label.new()
		dot.text = "●" if index == current_page else "○"
		dot.add_theme_font_size_override("font_size", 16)
		dot.add_theme_color_override("font_color", Color(0.93, 0.57, 0.18) if index == current_page else Color(0.55, 0.64, 0.62))
		progress_box.add_child(dot)
	back_button.disabled = current_page == 0
	next_button.text = _l10n_text("進入城市") if current_page == PAGES.size() - 1 else _l10n_text("下一步")


func _l10n_text(source: String) -> String:
	if is_inside_tree():
		var localization = get_node_or_null("/root/L10n")
		if localization != null:
			return str(localization.call("text", source))
	return source


func _go_next() -> void:
	if current_page >= PAGES.size() - 1:
		audio_cue.emit("success")
		close_as_completed(false)
		return
	current_page += 1
	audio_cue.emit("page_turn")
	_refresh_page()


func _go_back() -> void:
	if current_page <= 0:
		return
	current_page -= 1
	audio_cue.emit("page_turn")
	_refresh_page()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	# The focused Button owns ui_accept. Handling it here as well advances once
	# from this callback and once from BaseButton's keyboard activation.
	if event.is_action_pressed("ui_right"):
		_go_next()
		accept_event()
	elif event.is_action_pressed("ui_left"):
		_go_back()
		accept_event()
	elif event.is_action_pressed("ui_cancel"):
		close_as_completed(true)
		accept_event()


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(node_name: String, text: String, primary: bool) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(128, 48)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.08, 0.54, 0.66) if primary else Color(0.39, 0.48, 0.46, 0.96)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.12, 0.66, 0.76) if primary else Color(0.48, 0.57, 0.54, 0.98)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.05, 0.39, 0.50)))
	button.add_theme_stylebox_override("disabled", _button_style(Color(0.65, 0.67, 0.62, 0.90)))
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.86, 0.86, 0.81))
	return button


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.98, 0.95, 0.85, 0.97)
	style.border_color = Color(0.93, 0.60, 0.24, 0.96)
	style.set_border_width_all(2)
	style.set_corner_radius_all(22)
	style.shadow_color = Color(0.12, 0.09, 0.05, 0.34)
	style.shadow_size = 14
	return style


func _speaker_badge_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.82, 0.45, 0.72)
	style.border_color = Color(0.92, 0.55, 0.18, 0.88)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.content_margin_left = 5
	style.content_margin_top = 5
	style.content_margin_right = 5
	style.content_margin_bottom = 5
	return style


func _layout_dialogue_strip() -> void:
	if not is_instance_valid(story_panel):
		return
	var bounds := size
	if bounds.x <= 0.0 or bounds.y <= 0.0:
		return
	var horizontal_margin := clampf(bounds.x * 0.045, 24.0, 88.0)
	var bottom_margin := clampf(bounds.y * 0.035, 20.0, 56.0)
	var panel_height := clampf(bounds.y * 0.31, 240.0, 330.0)
	story_panel.offset_left = horizontal_margin
	story_panel.offset_top = -bottom_margin - panel_height
	story_panel.offset_right = -horizontal_margin
	story_panel.offset_bottom = -bottom_margin


func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = color.lightened(0.14)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style
