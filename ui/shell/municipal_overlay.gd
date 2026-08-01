class_name MunicipalOverlay
extends Control

const UiIconCatalog = preload("res://ui/theme/ui_icon_catalog.gd")

signal page_opened(page_id: String)
signal overlay_closed

const HUB_PAGE_ID := "hub"
const MENU_FONT_SIZE := 22
const HEADER_FONT_SIZE := 28
const ACTION_FONT_SIZE := 20
const MENU_BUTTON_HEIGHT := 200
const ACTION_BUTTON_HEIGHT := 50
const COMPANION_SAFE_RIGHT_MARGIN := 150.0
const MIN_MUNICIPAL_WINDOW_WIDTH := 960.0

const HUB_ENTRIES: Array[Dictionary] = [
	{
		"id": "buildings",
		"title": "選擇建築",
		"hint": "規劃 · 放置",
		"description": "挑選住宅、公共服務與產業建築，並進入地圖放置流程。"
	},
	{
		"id": "governance",
		"title": "政策與法案",
		"hint": "政策 · 議會",
		"description": "檢視政策、提出法案並處理議會審議與市政治理。"
	},
	{
		"id": "judicial",
		"title": "法院審判",
		"hint": "審判 · 辯護",
		"description": "玩家涉及違法行政行為時，在法院接受審判並提出辯護。"
	},
	{
		"id": "oversight",
		"title": "監察質詢",
		"hint": "質詢 · 彈劾辯護",
		"description": "玩家接受監察委員質詢，並在彈劾程序中提出答辯。"
	},
	{
		"id": "blueprint",
		"title": "設計藍圖",
		"hint": "設計 · 送審",
		"description": "調整建材、規模、樓層與裝飾，再將藍圖送交審核。"
	},
	{
		"id": "finance",
		"title": "稅率與公共事業費",
		"hint": "稅率 · 公共費",
		"description": "設定稅率與公共服務費用，掌握城市收入與居民負擔。"
	},
	{
		"id": "public_affairs",
		"title": "民情中心",
		"hint": "陳情 · 回應",
		"description": "接收居民陳情、查看待辦佇列並決定是否納入市政處理。"
	},
	{
		"id": "city_data",
		"title": "城市數據",
		"hint": "數據",
		"description": "查看完整城市數據"
	},
	{
		"id": "report",
		"title": "月度報告",
		"hint": "月報",
		"description": "查看月度報告"
	}
]
const HUB_GROUPS: Array[Dictionary] = [
	{
		"id": "development",
		"title": "建設與發展",
		"hint": "建築 · 藍圖 · 財政",
		"description": "從城市建設、設計審核與財政配置開始。",
		"icon": "buildings",
		"entries": ["buildings", "blueprint", "finance"],
	},
	{
		"id": "governance",
		"title": "治理與法務",
		"hint": "政策 · 法院 · 監察",
		"description": "處理政策法案、司法案件與監察程序。",
		"icon": "governance",
		"entries": ["governance", "judicial", "oversight"],
	},
	{
		"id": "community",
		"title": "居民與資訊",
		"hint": "民情 · 數據 · 月報",
		"description": "查看居民需求、城市指標與月度結果。",
		"icon": "public_affairs",
		"entries": ["public_affairs", "city_data", "report"],
	},
]
var _dark_mode := false
var _current_page_id := ""
var _pages: Dictionary = {}
var _page_titles: Dictionary = {}
var _hub_children: Dictionary = {}
var _menu_buttons: Dictionary = {}
var _hub_group_pages: Dictionary = {}
var _page_groups: Dictionary = {}
var _current_hub_group := ""

var _backdrop: ColorRect
var _panel: PanelContainer
var _header_panel: PanelContainer
var _header_title: Label
var _back_button: Button
var _close_button: Button
var _content_panel: PanelContainer
var _page_host: Control
var _hub_page: Control
var _hub_root: Control


func _init() -> void:
	name = "MunicipalOverlay"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Map residents use depth-sorted z values up to roughly 2,000. Keep every
	# municipal surface above the playfield so animated NPCs never bleed through
	# modal buttons or text.
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	_build_shell()
	_apply_palette()
	resized.connect(_layout_companion_safe_area)
	call_deferred("_layout_companion_safe_area")
	hide()


func register_page(page_id: String, title: String, control: Control, hub_child: bool = true) -> void:
	var normalized_id := page_id.strip_edges()
	if normalized_id.is_empty() or normalized_id == HUB_PAGE_ID:
		push_error("MunicipalOverlay.register_page requires a non-empty, non-reserved page id.")
		return
	if not is_instance_valid(control):
		push_error("MunicipalOverlay.register_page received an invalid control for '%s'." % normalized_id)
		return

	if _pages.has(normalized_id):
		var previous := _pages[normalized_id] as Control
		if is_instance_valid(previous) and previous != control and previous.get_parent() == _page_host:
			_page_host.remove_child(previous)

	var old_parent := control.get_parent()
	if old_parent != null and old_parent != _page_host:
		old_parent.remove_child(control)
	if control.get_parent() == null:
		_page_host.add_child(control)

	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	control.visible = false
	_pages[normalized_id] = control
	_page_titles[normalized_id] = title
	_hub_children[normalized_id] = hub_child
	_page_groups[normalized_id] = _hub_group_for_page(normalized_id)

	if control.has_method("set_dark_mode"):
		control.call("set_dark_mode", _dark_mode)
	if _menu_buttons.has(normalized_id):
		var menu_button := _menu_buttons[normalized_id] as Button
		menu_button.disabled = false


func open_hub() -> void:
	_show_only(_hub_page)
	_show_hub_child(_hub_root)
	_current_page_id = HUB_PAGE_ID
	_current_hub_group = ""
	_header_title.text = "市政服務中心"
	_back_button.visible = false
	L10n.localize_tree(self)
	show()
	_close_button.grab_focus()
	page_opened.emit(HUB_PAGE_ID)


func open_page(page_id: String) -> void:
	var normalized_id := page_id.strip_edges()
	if not _pages.has(normalized_id):
		push_warning("MunicipalOverlay has no registered page named '%s'." % normalized_id)
		return
	var page := _pages[normalized_id] as Control
	if not is_instance_valid(page):
		push_warning("MunicipalOverlay page '%s' is no longer valid." % normalized_id)
		return

	_show_only(page)
	_current_page_id = normalized_id
	_current_hub_group = str(_page_groups.get(normalized_id, ""))
	_header_title.text = str(_page_titles.get(normalized_id, normalized_id))
	_back_button.visible = bool(_hub_children.get(normalized_id, true))
	L10n.localize_tree(self)
	show()
	if _back_button.visible:
		_back_button.grab_focus()
	else:
		_close_button.grab_focus()
	page_opened.emit(normalized_id)


func close_overlay() -> void:
	if not visible:
		return
	hide()
	_current_page_id = ""
	_set_all_pages_hidden()
	overlay_closed.emit()


func is_open() -> bool:
	return visible


func current_page() -> String:
	return _current_page_id


func set_dark_mode(enabled: bool) -> void:
	_dark_mode = enabled
	_apply_palette()
	for page_variant in _pages.values():
		var page := page_variant as Control
		if is_instance_valid(page) and page.has_method("set_dark_mode"):
			page.call("set_dark_mode", enabled)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	if _current_page_id.begins_with("hub:"):
		open_hub()
	elif _current_page_id != HUB_PAGE_ID and bool(_hub_children.get(_current_page_id, false)):
		if not _current_hub_group.is_empty():
			_open_hub_group(_current_hub_group)
		else:
			open_hub()
	else:
		close_overlay()
	get_viewport().set_input_as_handled()


func _build_shell() -> void:
	_backdrop = ColorRect.new()
	_backdrop.name = "DimBackdrop"
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.name = "MunicipalWindow"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.anchor_left = 0.05
	_panel.anchor_top = 0.05
	_panel.anchor_right = 0.95
	_panel.anchor_bottom = 0.95
	_panel.custom_minimum_size = Vector2(MIN_MUNICIPAL_WINDOW_WIDTH, 600)
	add_child(_panel)

	var shell := VBoxContainer.new()
	shell.name = "Shell"
	shell.add_theme_constant_override("separation", 0)
	_panel.add_child(shell)

	_header_panel = PanelContainer.new()
	_header_panel.name = "Header"
	_header_panel.custom_minimum_size = Vector2(0, 72)
	shell.add_child(_header_panel)

	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 22)
	header_margin.add_theme_constant_override("margin_top", 10)
	header_margin.add_theme_constant_override("margin_right", 16)
	header_margin.add_theme_constant_override("margin_bottom", 10)
	_header_panel.add_child(header_margin)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header_margin.add_child(header)

	_back_button = _header_button("← 返回")
	_back_button.name = "BackButton"
	_back_button.tooltip_text = "返回市政服務中心（Esc）"
	_back_button.pressed.connect(_handle_back)
	header.add_child(_back_button)

	_header_title = Label.new()
	_header_title.name = "HeaderTitle"
	_header_title.text = "市政服務中心"
	_header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_header_title.clip_text = true
	_header_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_header_title.add_theme_font_size_override("font_size", HEADER_FONT_SIZE)
	header.add_child(_header_title)

	_close_button = _header_button("關閉 ×")
	_close_button.name = "CloseButton"
	_close_button.tooltip_text = "關閉市政畫面（Esc）"
	_close_button.pressed.connect(close_overlay)
	header.add_child(_close_button)

	_content_panel = PanelContainer.new()
	_content_panel.name = "Content"
	_content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(_content_panel)

	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 24)
	content_margin.add_theme_constant_override("margin_top", 20)
	content_margin.add_theme_constant_override("margin_right", 24)
	content_margin.add_theme_constant_override("margin_bottom", 24)
	_content_panel.add_child(content_margin)

	_page_host = Control.new()
	_page_host.name = "PageHost"
	_page_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_margin.add_child(_page_host)

	_hub_page = _build_hub_page()
	_hub_page.name = "MunicipalHub"
	_page_host.add_child(_hub_page)
	_hub_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build_hub_page() -> Control:
	var hub := Control.new()
	hub.set_meta("progressive_menu", true)
	_hub_root = _hub_menu_page("請先選擇工作類別；每一層最多顯示 3 個選項。")
	_hub_root.name = "MunicipalHubRoot"
	var category_grid := _hub_root.find_child("MenuChoices", true, false) as GridContainer
	for group in HUB_GROUPS:
		var group_id := str(group["id"])
		var button := _menu_card_button(
			"MunicipalCategory_%s" % group_id,
			str(group["title"]),
			str(group["hint"]),
			str(group["description"]),
			str(group["icon"])
		)
		button.pressed.connect(_open_hub_group.bind(group_id))
		_bind_safe_tooltip(button, _hub_root, "%s：%s" % [str(group["title"]), str(group["description"])])
		_menu_buttons["category:%s" % group_id] = button
		category_grid.add_child(button)
	hub.add_child(_hub_root)
	_hub_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	for group in HUB_GROUPS:
		var group_id := str(group["id"])
		var page := _hub_menu_page("%s｜選擇一項工作" % str(group["title"]))
		page.name = "MunicipalHubGroup_%s" % group_id
		page.visible = false
		var menu_grid := page.find_child("MenuChoices", true, false) as GridContainer
		for page_id_variant in group["entries"]:
			var page_id := str(page_id_variant)
			var entry := _hub_entry(page_id)
			if entry.is_empty():
				continue
			var button := _menu_card_button(
				"%sButton" % page_id.capitalize(),
				str(entry["title"]),
				str(entry["hint"]),
				str(entry["description"]),
				page_id
			)
			button.disabled = true
			button.pressed.connect(open_page.bind(page_id))
			_bind_safe_tooltip(button, page, "%s：%s" % [str(entry["title"]), str(entry["description"])])
			_menu_buttons[page_id] = button
			menu_grid.add_child(button)
		_hub_group_pages[group_id] = page
		hub.add_child(page)
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return hub


func _hub_menu_page(introduction_text: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 18)
	var introduction := Label.new()
	introduction.name = "HubSafeTooltip"
	introduction.text = introduction_text
	introduction.set_meta("default_source", introduction_text)
	introduction.custom_minimum_size = Vector2(0, 58)
	introduction.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	introduction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	introduction.max_lines_visible = 2
	introduction.add_theme_font_size_override("font_size", 22)
	page.add_child(introduction)
	var grid := GridContainer.new()
	grid.name = "MenuChoices"
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.set_meta("progressive_choice_group", true)
	page.add_child(grid)
	return page


func _menu_card_button(node_name: String, title: String, hint: String, description: String, icon_key: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = ""
	button.set_meta("semantic_label", title)
	button.set_meta("semantic_description", "%s：%s" % [title, description])
	button.set_meta("progressive_choice", true)
	# A cursor-following engine tooltip covered the neighbouring card captions.
	# The same description is exposed in the page's fixed safe hint row instead.
	button.tooltip_text = ""
	button.custom_minimum_size = Vector2(250, MENU_BUTTON_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.add_theme_constant_override("outline_size", 1)
	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 18
	content.offset_top = 12
	content.offset_right = -18
	content.offset_bottom = -12
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 5)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)
	var picture := TextureRect.new()
	picture.texture = UiIconCatalog.texture(icon_key)
	picture.custom_minimum_size = Vector2(82, 82)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(picture)
	var title_label := Label.new()
	title_label.text = title
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.max_lines_visible = 2
	title_label.custom_minimum_size = Vector2(0, 52)
	title_label.add_theme_font_size_override("font_size", MENU_FONT_SIZE)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(title_label)
	var hint_label := Label.new()
	hint_label.text = hint
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.max_lines_visible = 2
	hint_label.custom_minimum_size = Vector2(0, 36)
	hint_label.add_theme_font_size_override("font_size", 18)
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(hint_label)
	return button


func _bind_safe_tooltip(button: Button, page: Control, description_source: String) -> void:
	var safe_label := page.find_child("HubSafeTooltip", true, false) as Label
	if safe_label == null:
		return
	button.mouse_entered.connect(_show_safe_tooltip.bind(safe_label, description_source))
	button.focus_entered.connect(_show_safe_tooltip.bind(safe_label, description_source))
	button.mouse_exited.connect(_restore_safe_tooltip.bind(safe_label))
	button.focus_exited.connect(_restore_safe_tooltip.bind(safe_label))


func _show_safe_tooltip(label: Label, description_source: String) -> void:
	if is_instance_valid(label):
		label.text = L10n.text(description_source)


func _restore_safe_tooltip(label: Label) -> void:
	if is_instance_valid(label):
		label.text = L10n.text(str(label.get_meta("default_source", "")))


func _layout_companion_safe_area() -> void:
	if not is_instance_valid(_panel) or size.x <= 0.0:
		return
	# Keep the existing 5% shell margin, then reserve only the extra space the
	# current viewport can afford without making the municipal window narrower
	# than its established 960 px minimum.
	var affordable_margin := maxf(0.0, size.x * 0.90 - MIN_MUNICIPAL_WINDOW_WIDTH)
	_panel.offset_right = -minf(COMPANION_SAFE_RIGHT_MARGIN, affordable_margin)


func _hub_entry(page_id: String) -> Dictionary:
	for entry in HUB_ENTRIES:
		if str(entry["id"]) == page_id:
			return entry
	return {}


func _hub_group_for_page(page_id: String) -> String:
	for group in HUB_GROUPS:
		if page_id in group["entries"]:
			return str(group["id"])
	return ""


func _open_hub_group(group_id: String) -> void:
	if not _hub_group_pages.has(group_id):
		open_hub()
		return
	_show_only(_hub_page)
	_show_hub_child(_hub_group_pages[group_id] as Control)
	_current_hub_group = group_id
	_current_page_id = "hub:%s" % group_id
	for group in HUB_GROUPS:
		if str(group["id"]) == group_id:
			_header_title.text = str(group["title"])
			break
	_back_button.visible = true
	L10n.localize_tree(self)
	show()
	_back_button.grab_focus()
	page_opened.emit(_current_page_id)


func _show_hub_child(active_control: Control) -> void:
	if is_instance_valid(_hub_root):
		_hub_root.visible = _hub_root == active_control
	for page_variant in _hub_group_pages.values():
		var page := page_variant as Control
		if is_instance_valid(page):
			page.visible = page == active_control


func _handle_back() -> void:
	if _current_page_id.begins_with("hub:"):
		open_hub()
	elif not _current_hub_group.is_empty():
		_open_hub_group(_current_hub_group)
	else:
		open_hub()


func _header_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(130, ACTION_BUTTON_HEIGHT)
	button.add_theme_font_size_override("font_size", 18)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return button


func _show_only(active_control: Control) -> void:
	_set_all_pages_hidden()
	if is_instance_valid(active_control):
		active_control.visible = true


func _set_all_pages_hidden() -> void:
	if is_instance_valid(_hub_page):
		_hub_page.visible = false
	for page_variant in _pages.values():
		var page := page_variant as Control
		if is_instance_valid(page):
			page.visible = false


func _apply_palette() -> void:
	if not is_instance_valid(_backdrop):
		return

	_backdrop.color = Color(0.01, 0.02, 0.035, 0.80) if _dark_mode else Color(0.04, 0.05, 0.06, 0.67)
	_panel.add_theme_stylebox_override("panel", _panel_style(
		Color(0.075, 0.105, 0.135) if _dark_mode else Color(0.985, 0.965, 0.91),
		Color(0.28, 0.50, 0.64) if _dark_mode else Color(0.48, 0.34, 0.18),
		14,
		3
	))
	_header_panel.add_theme_stylebox_override("panel", _panel_style(
		Color(0.10, 0.16, 0.21) if _dark_mode else Color(0.91, 0.82, 0.64),
		Color(0.28, 0.50, 0.64) if _dark_mode else Color(0.48, 0.34, 0.18),
		10,
		0
	))
	_content_panel.add_theme_stylebox_override("panel", _panel_style(
		Color(0.055, 0.078, 0.10) if _dark_mode else Color(1.0, 0.985, 0.95),
		Color.TRANSPARENT,
		0,
		0
	))

	var text_color := Color(0.92, 0.96, 0.98) if _dark_mode else Color(0.08, 0.10, 0.12)
	_header_title.add_theme_color_override("font_color", text_color)
	if is_instance_valid(_hub_page):
		for label_variant in _hub_page.find_children("*", "Label", true, false):
			(label_variant as Label).add_theme_color_override("font_color", text_color)

	_style_header_action(_back_button, text_color)
	_style_header_action(_close_button, text_color)
	for button_variant in _menu_buttons.values():
		var button := button_variant as Button
		if is_instance_valid(button):
			_style_menu_button(button, text_color)


func _style_header_action(button: Button, text_color: Color) -> void:
	if not is_instance_valid(button):
		return
	var normal := _button_style(
		Color(0.13, 0.22, 0.29) if _dark_mode else Color(0.98, 0.93, 0.82),
		Color(0.33, 0.56, 0.69) if _dark_mode else Color(0.55, 0.39, 0.20),
		8
	)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.18, 0.32, 0.42) if _dark_mode else Color(1.0, 0.97, 0.88)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.07, 0.15, 0.21) if _dark_mode else Color(0.82, 0.72, 0.54)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	button.add_theme_color_override("font_focus_color", text_color)


func _style_menu_button(button: Button, text_color: Color) -> void:
	var normal := _button_style(
		Color(0.105, 0.16, 0.205) if _dark_mode else Color(0.96, 0.90, 0.76),
		Color(0.27, 0.53, 0.69) if _dark_mode else Color(0.58, 0.41, 0.20),
		12
	)
	normal.content_margin_left = 24
	normal.content_margin_right = 24
	normal.content_margin_top = 18
	normal.content_margin_bottom = 18
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.15, 0.27, 0.35) if _dark_mode else Color(1.0, 0.95, 0.82)
	hover.border_color = Color(0.38, 0.68, 0.84) if _dark_mode else Color(0.72, 0.48, 0.18)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.065, 0.13, 0.18) if _dark_mode else Color(0.86, 0.77, 0.59)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.11, 0.13, 0.15) if _dark_mode else Color(0.84, 0.84, 0.80)
	disabled.border_color = Color(0.28, 0.32, 0.35) if _dark_mode else Color(0.62, 0.62, 0.57)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	button.add_theme_color_override("font_focus_color", text_color)
	button.add_theme_color_override("font_disabled_color", Color(0.54, 0.59, 0.62) if _dark_mode else Color(0.40, 0.42, 0.43))
	for node in button.find_children("*", "Label", true, false):
		(node as Label).add_theme_color_override("font_color", text_color)


func _panel_style(background: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style


func _button_style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	return style
