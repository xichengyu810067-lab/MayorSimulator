class_name MunicipalOverlay
extends Control

const UiIconCatalog = preload("res://ui/theme/ui_icon_catalog.gd")
const SemanticPalette = preload("res://ui/theme/semantic_palette.gd")

signal page_opened(page_id: String)
signal overlay_closed

const HUB_PAGE_ID := "hub"
const MAX_NAVIGATION_HISTORY_ENTRIES := 16
const MENU_FONT_SIZE := 22
const HEADER_FONT_SIZE := 28
const ACTION_FONT_SIZE := 20
const ACTION_BUTTON_HEIGHT := 50
const COMPANION_SAFE_RIGHT_MARGIN := 150.0
const MIN_MUNICIPAL_WINDOW_WIDTH := 960.0
const HUB_NARROW_VIEWPORT_WIDTH := 1400.0
const HUB_GAP := 14.0
const HUB_TOOLTIP_HEIGHT := 58.0
const HUB_MIN_TARGET_EXTENT := 44.0
const HUB_DIRECT_DESTINATIONS: Array[String] = [
	"buildings",
	"governance",
	"judicial",
	"oversight",
	"finance",
	"public_affairs",
	"city_data",
]
const HUB_CONTEXT_PARENTS := {
	"blueprint": "buildings",
	"transport_planning": "buildings",
	"report": "city_data",
}

const HUB_ENTRIES: Array[Dictionary] = [
	{
		"id": "buildings",
		"title": "建設與藍圖",
		"hint": "建築 · 藍圖",
		"description": "挑選建築並進入藍圖、交通規劃與地圖放置流程。"
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
	}
]
var _dark_mode := false
var _current_page_id := ""
var _page_history: Array[String] = []
var _pages: Dictionary = {}
var _page_titles: Dictionary = {}
var _hub_children: Dictionary = {}
var _menu_buttons: Dictionary = {}

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
var _hub_cards_host: Control
var _hub_safe_tooltip: Label
var _hub_featured_button: Button
var _hub_secondary_buttons: Array[Button] = []
var _hub_layout_mode := ""


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
	resized.connect(_layout_hub)
	call_deferred("_layout_companion_safe_area")
	call_deferred("_layout_hub")
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
		var previous := _page_control(normalized_id)
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

	if control.has_method("set_dark_mode"):
		control.call("set_dark_mode", _dark_mode)
	if _menu_buttons.has(normalized_id):
		var menu_button := _menu_buttons[normalized_id] as Button
		menu_button.disabled = false


func open_hub() -> void:
	_page_history.clear()
	_show_hub()


func _show_hub() -> void:
	_show_only(_hub_page)
	_current_page_id = HUB_PAGE_ID
	_header_title.text = "市政服務中心"
	_back_button.visible = false
	_layout_hub()
	L10n.localize_tree(self)
	show()
	_close_button.grab_focus()
	page_opened.emit(HUB_PAGE_ID)


func open_page(page_id: String) -> void:
	var normalized_id := page_id.strip_edges()
	if not _pages.has(normalized_id):
		push_warning("MunicipalOverlay has no registered page named '%s'." % normalized_id)
		return
	var page := _page_control(normalized_id)
	if not is_instance_valid(page):
		push_warning("MunicipalOverlay page '%s' is no longer valid." % normalized_id)
		return

	if not visible or _current_page_id.is_empty():
		_page_history = _initial_history_for(normalized_id)
	elif _current_page_id != normalized_id:
		_remember_current_page()
	_show_page(normalized_id, page)


func _show_page(page_id: String, page: Control) -> void:
	_current_page_id = page_id
	_show_only(page)
	_header_title.text = str(_page_titles.get(page_id, page_id))
	_back_button.visible = not _page_history.is_empty()
	L10n.localize_tree(self)
	show()
	if _back_button.visible:
		_back_button.grab_focus()
	else:
		_close_button.grab_focus()
	page_opened.emit(page_id)


func close_overlay() -> void:
	if not visible:
		return
	hide()
	_current_page_id = ""
	_page_history.clear()
	_set_all_pages_hidden()
	overlay_closed.emit()


func is_open() -> bool:
	return visible


func current_page() -> String:
	return _current_page_id


func _page_control(page_id: String) -> Control:
	var page_variant: Variant = _pages.get(page_id)
	# A dictionary keeps an Object reference after queue_free(). Casting that
	# stale Variant raises before is_instance_valid() can run, so validity must
	# be checked while the value is still untyped.
	if not is_instance_valid(page_variant):
		return null
	return page_variant as Control


func set_dark_mode(enabled: bool) -> void:
	_dark_mode = enabled
	_apply_palette()
	for page_id_variant in _pages.keys():
		var page := _page_control(str(page_id_variant))
		if is_instance_valid(page) and page.has_method("set_dark_mode"):
			page.call("set_dark_mode", enabled)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	if _current_page_id != HUB_PAGE_ID and not _page_history.is_empty():
		_handle_back()
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
	_back_button.tooltip_text = "返回上一頁（Esc）"
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
	hub.set_meta("municipal_direct_hub", true)
	_hub_root = Control.new()
	_hub_root.name = "MunicipalHubRoot"
	hub.add_child(_hub_root)
	_hub_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_hub_safe_tooltip = Label.new()
	_hub_safe_tooltip.name = "HubSafeTooltip"
	_hub_safe_tooltip.text = "選擇市政工作；七項服務皆可直接開啟。"
	_hub_safe_tooltip.set_meta("default_source", _hub_safe_tooltip.text)
	_hub_safe_tooltip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hub_safe_tooltip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hub_safe_tooltip.max_lines_visible = 2
	_hub_safe_tooltip.add_theme_font_size_override("font_size", 20)
	_hub_root.add_child(_hub_safe_tooltip)

	_hub_cards_host = Control.new()
	_hub_cards_host.name = "MunicipalDirectDestinations"
	_hub_root.add_child(_hub_cards_host)
	for page_id in HUB_DIRECT_DESTINATIONS:
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
		button.set_meta("destination_id", page_id)
		button.set_meta("filler", false)
		button.set_meta("featured", page_id == "buildings")
		button.pressed.connect(open_page.bind(page_id))
		_bind_safe_tooltip(button, _hub_root, "%s：%s" % [str(entry["title"]), str(entry["description"])])
		_menu_buttons[page_id] = button
		_hub_cards_host.add_child(button)
		if page_id == "buildings":
			_hub_featured_button = button
		else:
			_hub_secondary_buttons.append(button)
	_hub_root.resized.connect(_layout_hub)
	return hub


func _menu_card_button(node_name: String, title: String, hint: String, description: String, icon_key: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = ""
	button.set_meta("semantic_label", title)
	button.set_meta("semantic_description", "%s：%s" % [title, description])
	# A cursor-following engine tooltip covered the neighbouring card captions.
	# The same description is exposed in the page's fixed safe hint row instead.
	button.tooltip_text = ""
	button.custom_minimum_size = Vector2(HUB_MIN_TARGET_EXTENT, HUB_MIN_TARGET_EXTENT)
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
	picture.name = "CardIcon"
	picture.texture = UiIconCatalog.texture(icon_key)
	picture.custom_minimum_size = Vector2(82, 82)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(picture)
	var title_label := Label.new()
	title_label.name = "CardTitle"
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
	hint_label.name = "CardHint"
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
	call_deferred("_layout_hub")


func _layout_hub() -> void:
	if not is_instance_valid(_hub_root) or not is_instance_valid(_hub_cards_host):
		return
	var root_size := _hub_root.size
	if root_size.x <= 0.0 or root_size.y <= 0.0:
		return
	_hub_safe_tooltip.position = Vector2.ZERO
	_hub_safe_tooltip.size = Vector2(root_size.x, HUB_TOOLTIP_HEIGHT)
	_hub_cards_host.position = Vector2(0.0, HUB_TOOLTIP_HEIGHT + HUB_GAP)
	_hub_cards_host.size = Vector2(root_size.x, maxf(0.0, root_size.y - HUB_TOOLTIP_HEIGHT - HUB_GAP))
	var host_size := _hub_cards_host.size
	if host_size.x <= 0.0 or host_size.y <= 0.0:
		return

	_hub_layout_mode = "narrow" if size.x < HUB_NARROW_VIEWPORT_WIDTH else "wide"
	if _hub_layout_mode == "wide":
		var featured_width := floorf((host_size.x - HUB_GAP) * 0.34)
		_hub_featured_button.position = Vector2.ZERO
		_hub_featured_button.size = Vector2(featured_width, host_size.y)
		var grid_origin := Vector2(featured_width + HUB_GAP, 0.0)
		var grid_size := Vector2(host_size.x - grid_origin.x, host_size.y)
		_layout_secondary_grid(grid_origin, grid_size)
	else:
		var minimum_secondary_height := HUB_MIN_TARGET_EXTENT * 3.0 + HUB_GAP * 2.0
		var maximum_featured_height := maxf(HUB_MIN_TARGET_EXTENT, host_size.y - minimum_secondary_height - HUB_GAP)
		var featured_height := minf(maxf(HUB_MIN_TARGET_EXTENT, floorf(host_size.y * 0.26)), maximum_featured_height)
		_hub_featured_button.position = Vector2.ZERO
		_hub_featured_button.size = Vector2(host_size.x, featured_height)
		var grid_origin := Vector2(0.0, featured_height + HUB_GAP)
		var grid_size := Vector2(host_size.x, maxf(0.0, host_size.y - grid_origin.y))
		_layout_secondary_grid(grid_origin, grid_size)

	_set_card_density(_hub_featured_button, true, _hub_layout_mode == "narrow")
	for secondary_button in _hub_secondary_buttons:
		_set_card_density(secondary_button, false, _hub_layout_mode == "narrow")


func _layout_secondary_grid(origin: Vector2, grid_size: Vector2) -> void:
	var card_width := maxf(0.0, (grid_size.x - HUB_GAP) / 2.0)
	var card_height := maxf(0.0, (grid_size.y - HUB_GAP * 2.0) / 3.0)
	for index in _hub_secondary_buttons.size():
		var button := _hub_secondary_buttons[index]
		var column := index % 2
		var row := int(index / 2.0)
		button.position = origin + Vector2(column * (card_width + HUB_GAP), row * (card_height + HUB_GAP))
		button.size = Vector2(card_width, card_height)


func _set_card_density(button: Button, featured: bool, narrow: bool) -> void:
	if not is_instance_valid(button):
		return
	var content := button.get_child(0) as VBoxContainer
	var picture := button.find_child("CardIcon", true, false) as TextureRect
	var title_label := button.find_child("CardTitle", true, false) as Label
	var hint_label := button.find_child("CardHint", true, false) as Label
	if content != null:
		content.offset_left = 10.0
		content.offset_top = 6.0
		content.offset_right = -10.0
		content.offset_bottom = -6.0
		content.add_theme_constant_override("separation", 2 if narrow else 4)
	if picture != null:
		var icon_extent := 54.0 if featured and narrow else (92.0 if featured else (34.0 if narrow else 48.0))
		picture.custom_minimum_size = Vector2(icon_extent, icon_extent)
	if title_label != null:
		title_label.custom_minimum_size = Vector2(0.0, 34.0 if narrow else 42.0)
		title_label.add_theme_font_size_override("font_size", 22 if featured else (18 if narrow else 20))
	if hint_label != null:
		hint_label.visible = featured or not narrow
		hint_label.custom_minimum_size = Vector2(0.0, 28.0)
		hint_label.add_theme_font_size_override("font_size", 18)


func _hub_entry(page_id: String) -> Dictionary:
	for entry in HUB_ENTRIES:
		if str(entry["id"]) == page_id:
			return entry
	return {}


func _handle_back() -> void:
	while not _page_history.is_empty():
		var previous_page_id: String = _page_history.pop_back()
		if previous_page_id == HUB_PAGE_ID:
			_show_hub()
			return
		var previous_page := _page_control(previous_page_id)
		if is_instance_valid(previous_page):
			_show_page(previous_page_id, previous_page)
			return
		push_warning("MunicipalOverlay skipped an unavailable history page named '%s'." % previous_page_id)
	open_hub()


func _remember_current_page() -> void:
	_page_history.append(_current_page_id)
	while _page_history.size() > MAX_NAVIGATION_HISTORY_ENTRIES:
		var discard_index := 1 if _page_history[0] == HUB_PAGE_ID else 0
		_page_history.remove_at(discard_index)


func _initial_history_for(page_id: String) -> Array[String]:
	var history: Array[String] = [HUB_PAGE_ID]
	var visited := {page_id: true}
	var contextual_parent := str(HUB_CONTEXT_PARENTS.get(page_id, ""))
	while not contextual_parent.is_empty() and contextual_parent != HUB_PAGE_ID and not visited.has(contextual_parent):
		visited[contextual_parent] = true
		var parent_page := _page_control(contextual_parent)
		if not is_instance_valid(parent_page):
			break
		history.append(contextual_parent)
		contextual_parent = str(HUB_CONTEXT_PARENTS.get(contextual_parent, ""))
	return history


func debug_hub_layout_state() -> Dictionary:
	_layout_hub()
	var destinations: Array[String] = []
	var unique_destinations := {}
	var filler_count := 0
	var minimum_target_extent := INF
	var featured_rect := Rect2()
	var secondary_rects: Array[Rect2] = []
	for page_id in HUB_DIRECT_DESTINATIONS:
		var button := _menu_buttons.get(page_id) as Button
		if not is_instance_valid(button):
			continue
		var destination := str(button.get_meta("destination_id", ""))
		destinations.append(destination)
		unique_destinations[destination] = true
		if bool(button.get_meta("filler", false)):
			filler_count += 1
		minimum_target_extent = minf(minimum_target_extent, minf(button.size.x, button.size.y))
		if bool(button.get_meta("featured", false)):
			featured_rect = button.get_rect()
		else:
			secondary_rects.append(button.get_rect())
	var host_rect := _hub_cards_host.get_rect() if is_instance_valid(_hub_cards_host) else Rect2()
	var first_secondary_y := INF
	var equal_secondary_heights := true
	var reference_height := secondary_rects[0].size.y if not secondary_rects.is_empty() else 0.0
	for secondary_rect in secondary_rects:
		first_secondary_y = minf(first_secondary_y, secondary_rect.position.y)
		if absf(secondary_rect.size.y - reference_height) > 1.0:
			equal_secondary_heights = false
	if minimum_target_extent == INF:
		minimum_target_extent = 0.0
	return {
		"direct_card_count": destinations.size(),
		"destinations": destinations,
		"unique_destination_count": unique_destinations.size(),
		"filler_count": filler_count,
		"intermediate_page_count": 0,
		"layout_mode": _hub_layout_mode,
		"host_rect": host_rect,
		"featured_rect": featured_rect,
		"featured_destination": "buildings",
		"featured_width_ratio": featured_rect.size.x / host_rect.size.x if host_rect.size.x > 0.0 else 0.0,
		"featured_spans_full_height": absf(featured_rect.size.y - host_rect.size.y) <= 1.0,
		"featured_precedes_secondary": featured_rect.end.y <= first_secondary_y + 1.0,
		"secondary_rects": secondary_rects,
		"secondary_columns": 2,
		"secondary_rows": 3,
		"secondary_equal_heights": equal_secondary_heights,
		"minimum_target_extent": minimum_target_extent,
		"contextual_parents": HUB_CONTEXT_PARENTS.duplicate(true),
	}


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
	for page_id_variant in _pages.keys():
		var page := _page_control(str(page_id_variant))
		if is_instance_valid(page):
			page.visible = false


func _apply_palette() -> void:
	if not is_instance_valid(_backdrop):
		return

	_backdrop.color = SemanticPalette.color_for(_dark_mode, "scrim")
	_panel.add_theme_stylebox_override("panel", _panel_style(
		SemanticPalette.color_for(_dark_mode, "surface_raised"),
		SemanticPalette.color_for(_dark_mode, "border_default"),
		14,
		3
	))
	_header_panel.add_theme_stylebox_override("panel", _panel_style(
		SemanticPalette.color_for(_dark_mode, "surface_muted"),
		SemanticPalette.color_for(_dark_mode, "border_default"),
		10,
		0
	))
	_content_panel.add_theme_stylebox_override("panel", _panel_style(
		SemanticPalette.color_for(_dark_mode, "surface_base"),
		Color.TRANSPARENT,
		0,
		0
	))

	var text_color := SemanticPalette.color_for(_dark_mode, "text_primary")
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
		SemanticPalette.color_for(_dark_mode, "surface_raised"),
		SemanticPalette.color_for(_dark_mode, "border_default"),
		8
	)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = SemanticPalette.color_for(_dark_mode, "surface_muted")
	hover.border_color = SemanticPalette.color_for(_dark_mode, "border_focus")
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = SemanticPalette.color_for(_dark_mode, "surface_base")
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
		SemanticPalette.color_for(_dark_mode, "surface_raised"),
		SemanticPalette.color_for(_dark_mode, "border_default"),
		12
	)
	normal.content_margin_left = 24
	normal.content_margin_right = 24
	normal.content_margin_top = 18
	normal.content_margin_bottom = 18
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = SemanticPalette.color_for(_dark_mode, "surface_muted")
	hover.border_color = SemanticPalette.color_for(_dark_mode, "border_focus")
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = SemanticPalette.color_for(_dark_mode, "surface_base")
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = SemanticPalette.color_for(_dark_mode, "action_primary_disabled")
	disabled.border_color = SemanticPalette.color_for(_dark_mode, "border_disabled")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	button.add_theme_color_override("font_focus_color", text_color)
	button.add_theme_color_override("font_disabled_color", SemanticPalette.color_for(_dark_mode, "text_disabled"))
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
