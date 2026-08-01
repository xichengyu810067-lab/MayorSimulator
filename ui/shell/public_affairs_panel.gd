extends ScrollContainer

const ProgressiveChoicePagerScript = preload("res://ui/components/progressive_choice_pager.gd")
const UiIconCatalog = preload("res://ui/theme/ui_icon_catalog.gd")
const NpcActorScript = preload("res://scripts/world/npc_actor.gd")

signal accept_request_requested(request_id: String)
signal reject_request_requested(request_id: String)

const BODY_SIZE := 18
const TITLE_SIZE := 24
const ICONS := {
	"hero": "public_affairs",
}

var _dark_mode := false
var _labels: Array[Label] = []
var _cards: Array[PanelContainer] = []
var _summary_label: Label
var _empty_label: Label
var _requests_box: VBoxContainer
var _requests_pager: Control
var _request_buttons: Dictionary = {}
var _reject_buttons: Dictionary = {}
var _request_models: Dictionary = {}


func _init() -> void:
	name = "民情中心"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_build_content()


func set_dark_mode(enabled: bool) -> void:
	_dark_mode = enabled
	for label: Label in _labels:
		if is_instance_valid(label):
			label.add_theme_color_override("font_color", _text_color())
	for card: PanelContainer in _cards:
		if is_instance_valid(card):
			_style_card(card)
	for button_variant in _request_buttons.values():
		_style_button(button_variant as Button)
	for button_variant in _reject_buttons.values():
		_style_button(button_variant as Button)
	for model_variant in _request_models.values():
		var model := model_variant as Button
		if not is_instance_valid(model):
			continue
		model.call("set_actor", str(model.get_meta("npc_archetype", "一般居民")), _dark_mode, int(model.get_meta("npc_model_seed", 0)))
		model.call("set_expression", str(model.get_meta("npc_expression", "calm")))


func set_view_model(view_model: Dictionary) -> void:
	var requests: Array = view_model.get("citizen_requests", [])
	_summary_label.text = L10n.text("%d 件陳情紀錄｜狀態隨決策更新") % requests.size()
	_rebuild_request_cards(requests)


func _build_content() -> void:
	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(900, 0)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	add_child(content)

	var hero := _card()
	hero.name = "PublicAffairsHero"
	var hero_row := HBoxContainer.new()
	hero_row.add_theme_constant_override("separation", 20)
	hero.add_child(hero_row)
	hero_row.add_child(_icon("hero", Vector2(150, 126)))
	var hero_copy := VBoxContainer.new()
	hero_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_copy.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_copy.add_theme_constant_override("separation", 8)
	hero_row.add_child(hero_copy)
	hero_copy.add_child(_label("民情中心", TITLE_SIZE))
	var introduction := _label("所有居民陳情會自動列在下方，不必先到地圖逐一點人。", BODY_SIZE)
	introduction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hero_copy.add_child(introduction)
	_summary_label = _label("0 件陳情紀錄｜狀態隨決策更新", BODY_SIZE)
	_summary_label.name = "PublicAffairsSummary"
	hero_copy.add_child(_summary_label)
	content.add_child(hero)

	_requests_box = VBoxContainer.new()
	_requests_box.name = "PublicAffairsRequestList"
	_requests_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_requests_box.add_theme_constant_override("separation", 10)
	content.add_child(_requests_box)
	_requests_pager = ProgressiveChoicePagerScript.new(1, 3)
	_requests_pager.name = "CitizenRequestPager"
	_requests_box.add_child(_requests_pager)
	_empty_label = _label("目前沒有陳情紀錄。城市狀況改變後，新的陳情會自動出現。", BODY_SIZE)
	_empty_label.name = "PublicAffairsEmpty"
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.custom_minimum_size = Vector2(0, 100)
	_requests_box.add_child(_empty_label)

	set_dark_mode(_dark_mode)
	set_view_model({})


func _rebuild_request_cards(requests: Array) -> void:
	_requests_pager.call("clear_choices", true)
	_request_buttons.clear()
	_reject_buttons.clear()
	_request_models.clear()
	_empty_label.visible = requests.is_empty()
	for request_variant in requests:
		var request: Dictionary = request_variant
		_requests_pager.call("add_choice", _request_card(request))


func _request_card(request: Dictionary) -> PanelContainer:
	var card := _card()
	card.name = "CitizenRequest_%s" % str(request.get("request_id", "unknown"))
	card.custom_minimum_size = Vector2(0, 142)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)
	row.add_child(_npc_model(request))
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 4)
	row.add_child(copy)
	var npc_name := str(request.get("npc_name", request.get("npc_id", "居民")))
	var status := str(request.get("status", "pending"))
	copy.add_child(_label("%s｜%s" % [npc_name, L10n.text(_status_text(status))], 17))
	copy.add_child(_label(L10n.text(str(request.get("title", "居民陳情"))), TITLE_SIZE))
	var description := _label(L10n.text(str(request.get("description", ""))), BODY_SIZE)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(description)
	var actions := HBoxContainer.new()
	actions.name = "RequestActions_%s" % str(request.get("request_id", "unknown"))
	actions.add_theme_constant_override("separation", 8)
	row.add_child(actions)
	var accept := Button.new()
	accept.name = "AcceptRequest_%s" % str(request.get("request_id", "unknown"))
	accept.text = L10n.text("受理") if status == "pending" else L10n.text(_status_text(status))
	accept.custom_minimum_size = Vector2(126, 70)
	accept.add_theme_font_size_override("font_size", 18)
	accept.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	accept.clip_text = true
	accept.disabled = status != "pending"
	accept.pressed.connect(func() -> void: accept_request_requested.emit(str(request.get("request_id", ""))))
	_style_button(accept)
	_request_buttons[str(request.get("request_id", ""))] = accept
	actions.add_child(accept)
	var reject := Button.new()
	reject.name = "RejectRequest_%s" % str(request.get("request_id", "unknown"))
	reject.text = L10n.text("拒絕")
	reject.custom_minimum_size = Vector2(126, 70)
	reject.add_theme_font_size_override("font_size", 18)
	reject.visible = status == "pending"
	reject.disabled = status != "pending"
	reject.pressed.connect(func() -> void: reject_request_requested.emit(str(request.get("request_id", ""))))
	_style_button(reject)
	_reject_buttons[str(request.get("request_id", ""))] = reject
	actions.add_child(reject)
	return card


func _npc_model(request: Dictionary) -> Control:
	var npc_id := str(request.get("npc_id", "unknown"))
	var archetype := str(request.get("npc_archetype", "一般居民"))
	var model_seed := int(request.get("npc_model_seed", absi(hash(npc_id))))
	var status := str(request.get("status", "pending"))
	var expression := "concerned" if status in ["pending", "rejected"] else "proud"
	var model: Button = NpcActorScript.new()
	model.name = "CitizenNpcModel_%s" % npc_id
	model.custom_minimum_size = Vector2(112, 104)
	model.size = Vector2(112, 104)
	model.call("set_portrait_mode", true)
	model.call("set_actor", archetype, _dark_mode, model_seed)
	model.call("set_expression", expression)
	model.tooltip_text = L10n.text("%s 的人物模型") % str(request.get("npc_name", npc_id))
	model.set_meta("npc_id", npc_id)
	model.set_meta("npc_archetype", archetype)
	model.set_meta("npc_model_seed", model_seed)
	model.set_meta("npc_expression", expression)
	model.set_meta("model_source", "authoritative_npc_record")
	_request_models[npc_id] = model
	return model


func _status_text(status: String) -> String:
	match status:
		"accepted": return "已受理"
		"rejected": return "已拒絕"
		"completed": return "已完成"
		_: return "待回應"


func _card() -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_constant_override("margin_left", 16)
	card.add_theme_constant_override("margin_top", 12)
	card.add_theme_constant_override("margin_right", 16)
	card.add_theme_constant_override("margin_bottom", 12)
	_cards.append(card)
	_style_card(card)
	return card


func _style_card(card: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.22, 0.29) if _dark_mode else Color(0.97, 0.94, 0.85)
	style.border_color = Color(0.36, 0.47, 0.56) if _dark_mode else Color(0.69, 0.54, 0.31)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.shadow_color = Color(0, 0, 0, 0.14)
	style.shadow_size = 3
	card.add_theme_stylebox_override("panel", style)


func _icon(icon_key: String, minimum: Vector2) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = UiIconCatalog.texture(str(ICONS[icon_key]))
	picture.custom_minimum_size = minimum
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", _text_color())
	_labels.append(label)
	return label


func _style_button(button: Button) -> void:
	if not is_instance_valid(button):
		return
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.05, 0.43, 0.70)
	normal.border_color = Color(0.03, 0.31, 0.52)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.08, 0.52, 0.82)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.30, 0.36, 0.42) if _dark_mode else Color(0.78, 0.82, 0.85)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.68, 0.76, 0.82) if _dark_mode else Color(0.24, 0.31, 0.38))


func _text_color() -> Color:
	return Color(0.90, 0.94, 0.97) if _dark_mode else Color(0.07, 0.12, 0.18)
