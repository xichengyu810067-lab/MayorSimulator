class_name TransportPlanningPanel
extends ScrollContainer

const ProgressiveChoicePagerScript = preload("res://ui/components/progressive_choice_pager.gd")
const TransportPlanningSessionScript = preload("res://scripts/systems/city/transport_planning_session.gd")

signal infrastructure_requested(kind: String, operation: String)
signal route_planning_requested(mode: String, fleet_size: int, headway_minutes: int, fare: int)
signal route_toggle_requested(route_id: String, enabled: bool)
signal route_delete_requested(route_id: String)
signal session_continue_requested
signal session_close_requested

const BODY_FONT_SIZE := 18
const SECTION_FONT_SIZE := 22
const TITLE_FONT_SIZE := 28
const CONTROL_FONT_SIZE := 18
const CONTROL_HEIGHT := 52.0
const PAGER_MINIMUM_CHOICE_WIDTH := 310.0
const THREE_COLUMN_PAGER_MINIMUM_WIDTH := PAGER_MINIMUM_CHOICE_WIDTH * 3.0 + 20.0

const INFRASTRUCTURE_CHOICES: Array[Dictionary] = [
	{"id": "road", "label": "道路", "hint": "汽車、摩托車與公車共用的連續路網。", "add": "build", "remove": "demolish", "add_label": "興建", "remove_label": "拆除"},
	{"id": "metro_track", "label": "捷運軌道", "hint": "連接捷運站與捷運機廠。", "add": "build", "remove": "demolish", "add_label": "鋪設", "remove_label": "拆除"},
	{"id": "heavy_rail", "label": "重型鐵路", "hint": "連接火車站、鐵路機廠與號誌。", "add": "build", "remove": "demolish", "add_label": "鋪設", "remove_label": "拆除"},
	{"id": "runway", "label": "跑道", "hint": "供飛機起飛與降落；必須接入機場滑行道。", "add": "build", "remove": "demolish", "add_label": "興建", "remove_label": "拆除"},
	{"id": "taxiway", "label": "滑行道", "hint": "連接航廈、機坪與跑道。", "add": "build", "remove": "demolish", "add_label": "興建", "remove_label": "拆除"},
	{"id": "bus_depot", "label": "公車車庫", "hint": "提供公車車隊；未設置時公車路線不能營運。", "add": "place", "remove": "remove", "add_label": "設置", "remove_label": "移除"},
	{"id": "metro_depot", "label": "捷運機廠", "hint": "提供捷運列車停放與維修。", "add": "place", "remove": "remove", "add_label": "設置", "remove_label": "移除"},
	{"id": "rail_depot", "label": "鐵路機廠", "hint": "提供火車停放與維修。", "add": "place", "remove": "remove", "add_label": "設置", "remove_label": "移除"},
	{"id": "rail_signal", "label": "鐵路號誌", "hint": "控制列車區間與平交道通行。", "add": "place", "remove": "remove", "add_label": "設置", "remove_label": "移除"},
]

const ROUTE_MODES: Array[Dictionary] = [
	{"id": "bus", "label": "公車路線", "hint": "依序選擇站點，路徑必須位於已完工道路。"},
	{"id": "metro", "label": "捷運路線", "hint": "至少兩座捷運站，且全線軌道、機廠與號誌完整。"},
	{"id": "train", "label": "火車路線", "hint": "至少兩座火車站，且重型鐵路全線連通。"},
	{"id": "air", "label": "航空路線", "hint": "機場、跑道與滑行道均完成後才能派遣飛機。"},
]

var _dark_mode := false
var _planning_unlocked := true
var _view_model: Dictionary = {}
var _labels: Array[Label] = []
var _cards: Array[PanelContainer] = []
var _buttons: Array[Button] = []
var _spin_boxes: Array[SpinBox] = []
var _new_plan_buttons: Array[Button] = []
var _pagers: Array[Control] = []
var _route_models: Dictionary = {}
var _infrastructure_choice_cards: Dictionary = {}
var _route_mode_cards: Dictionary = {}
var _planning_session: Dictionary = {"state": "inactive"}
var _package_quote: Dictionary = {}
var _choice_stash: Control

var _content: VBoxContainer
var _unlock_label: Label
var _live_summary: Label
var _network_summary: Label
var _fleet_input: SpinBox
var _headway_input: SpinBox
var _fare_input: SpinBox
var _infrastructure_pager: Control
var _route_mode_pager: Control
var _route_pager: Control
var _route_empty_label: Label
var _session_card: PanelContainer
var _session_status_label: Label
var _session_detail_label: Label
var _session_continue_button: Button
var _session_close_button: Button
var _infrastructure_section_card: Control
var _operations_section_card: Control
var _route_list_section_card: Control


func _init() -> void:
	name = "交通規劃"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_build_content()


func _ready() -> void:
	resized.connect(_on_layout_resized)
	var viewport := get_viewport()
	if viewport != null:
		viewport.size_changed.connect(_on_layout_resized)
	_refresh_pager_columns()


func _exit_tree() -> void:
	if resized.is_connected(_on_layout_resized):
		resized.disconnect(_on_layout_resized)
	var viewport := get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_on_layout_resized):
		viewport.size_changed.disconnect(_on_layout_resized)


func set_view_model(snapshot: Dictionary) -> void:
	_view_model = snapshot.duplicate(true)
	var session_value: Variant = snapshot.get("planning_session", {"state": "inactive"})
	_planning_session = Dictionary(session_value).duplicate(true) if session_value is Dictionary else {"state": "inactive"}
	_package_quote = Dictionary(snapshot.get("package_quote", {})).duplicate(true) if snapshot.get("package_quote", {}) is Dictionary else {}
	_planning_unlocked = bool(snapshot.get("planning_unlocked", snapshot.get("unlocked", true)))
	if is_inside_tree():
		_refresh_pager_columns()
	_refresh_session_scoped_choices()
	_unlock_label.text = (
		L10n.text("交通規劃已解鎖｜可繼續既有站點規劃、路網與營運決策。")
		if _planning_unlocked
		else L10n.text("交通規劃尚未解鎖｜請先完成對應的城市交通決策。")
	)
	_render_planning_session()
	_refresh_new_plan_button_states()

	if snapshot.has("fleet_size"):
		_fleet_input.set_value_no_signal(clampf(float(snapshot["fleet_size"]), _fleet_input.min_value, _fleet_input.max_value))
	if snapshot.has("headway_minutes"):
		_headway_input.set_value_no_signal(clampf(float(snapshot["headway_minutes"]), _headway_input.min_value, _headway_input.max_value))
	if snapshot.has("fare"):
		_fare_input.set_value_no_signal(clampf(float(snapshot["fare"]), _fare_input.min_value, _fare_input.max_value))

	var routes_variant: Variant = snapshot.get("routes", snapshot.get("transport_routes", []))
	var routes: Array = routes_variant if routes_variant is Array else []
	_rebuild_route_cards(routes)
	var operational_count := 0
	for route_variant: Variant in routes:
		if route_variant is Dictionary and str((route_variant as Dictionary).get("status", "")) == "operational":
			operational_count += 1
	_network_summary.text = L10n.text("路線總覽｜%d 條規劃｜%d 條營運中") % [routes.size(), operational_count]
	_refresh_live_summary()


func _refresh_pager_columns() -> void:
	if is_queued_for_deletion():
		return
	var viewport_width := get_viewport_rect().size.x
	var available_width := size.x
	var has_three_column_width := available_width <= 0.0 or available_width >= THREE_COLUMN_PAGER_MINIMUM_WIDTH
	var target_columns := 3 if viewport_width >= 1400.0 and has_three_column_width else 2
	for pager in [_infrastructure_pager, _route_mode_pager]:
		if pager != null:
			pager.call("set_forced_columns", target_columns)


func _on_layout_resized() -> void:
	_refresh_pager_columns()


func set_dark_mode(enabled: bool) -> void:
	_dark_mode = enabled
	_refresh_palette()


func refresh_localization() -> void:
	L10n.localize_tree(self)
	set_view_model(_view_model)


func debug_snapshot() -> Dictionary:
	var progressive_groups: Dictionary = {}
	for pager: Control in _pagers:
		if not is_instance_valid(pager):
			continue
		progressive_groups[pager.name] = {
			"choice_count": int(pager.call("choice_count")),
			"visible_choice_count": int(pager.call("visible_choice_count")),
			"page_count": int(pager.call("page_count")),
		}
	return {
		"dark_mode": _dark_mode,
		"planning_unlocked": _planning_unlocked,
		"fleet_size": int(_fleet_input.value),
		"headway_minutes": int(_headway_input.value),
		"fare": int(_fare_input.value),
		"live_summary": _live_summary.text,
		"network_summary": _network_summary.text,
		"route_count": _route_models.size(),
		"routes": _route_models.duplicate(true),
		"progressive_groups": progressive_groups,
		"infrastructure_choices": INFRASTRUCTURE_CHOICES.duplicate(true),
		"route_modes": ROUTE_MODES.duplicate(true),
		"scoped_infrastructure_choice_ids": _scoped_infrastructure_choice_ids(),
		"scoped_route_mode_ids": _scoped_route_mode_ids(),
		"planning_session": _planning_session.duplicate(true),
		"package_quote": _package_quote.duplicate(true),
		"session_visible": _session_card.visible if _session_card != null else false,
		"session_status": _session_status_label.text if _session_status_label != null else "",
		"session_detail": _session_detail_label.text if _session_detail_label != null else "",
		"session_continue_enabled": not _session_continue_button.disabled if _session_continue_button != null else false,
	}


func _build_content() -> void:
	_content = VBoxContainer.new()
	_content.name = "TransportPlanningContent"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 14)
	add_child(_content)

	var hero := _card("TransportPlanningHero")
	var hero_stack := VBoxContainer.new()
	hero_stack.add_theme_constant_override("separation", 8)
	hero.add_child(hero_stack)
	hero_stack.add_child(_label("城市交通規劃", TITLE_FONT_SIZE))
	var introduction := _label(
		"玩家決定站點、道路、軌道、平交道、車庫、號誌與營運設定；系統不會在未連通的格子上自行生成交通工具。",
		BODY_FONT_SIZE
	)
	introduction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hero_stack.add_child(introduction)
	_unlock_label = _label("交通規劃已解鎖｜可繼續既有站點規劃、路網與營運決策。", BODY_FONT_SIZE)
	_unlock_label.name = "TransportPlanningUnlockStatus"
	hero_stack.add_child(_unlock_label)
	_content.add_child(hero)

	_session_card = _card("TransportPlanningSessionCard")
	_session_card.visible = false
	var session_stack := VBoxContainer.new()
	session_stack.add_theme_constant_override("separation", 8)
	_session_card.add_child(session_stack)
	_session_status_label = _label("目前沒有進行中的交通規劃。", SECTION_FONT_SIZE)
	_session_status_label.name = "TransportPlanningSessionStatus"
	session_stack.add_child(_session_status_label)
	_session_detail_label = _label("", BODY_FONT_SIZE)
	_session_detail_label.name = "TransportPlanningSessionDetail"
	session_stack.add_child(_session_detail_label)
	var session_actions := HBoxContainer.new()
	session_actions.add_theme_constant_override("separation", 10)
	session_stack.add_child(session_actions)
	_session_continue_button = _button("TransportPlanningSessionContinue", "繼續規劃", "primary")
	_session_continue_button.pressed.connect(func() -> void: session_continue_requested.emit())
	session_actions.add_child(_session_continue_button)
	_session_close_button = _button("TransportPlanningSessionClose", "結束規劃", "danger")
	_session_close_button.pressed.connect(func() -> void: session_close_requested.emit())
	session_actions.add_child(_session_close_button)
	_content.add_child(_session_card)

	var infrastructure_section := _section_card(
		"TransportInfrastructureSection",
		"1. 路網與設施",
		"鋪設或拆除道路、捷運軌道、重型鐵路、跑道、滑行道；另可設置車庫、機廠與鐵路號誌。"
	)
	_infrastructure_section_card = infrastructure_section.get_parent() as Control
	_infrastructure_pager = ProgressiveChoicePagerScript.new(2, 3)
	_infrastructure_pager.name = "TransportInfrastructurePager"
	_infrastructure_pager.call("set_minimum_choice_width", PAGER_MINIMUM_CHOICE_WIDTH)
	_register_pager(_infrastructure_pager)
	infrastructure_section.add_child(_infrastructure_pager)
	for choice: Dictionary in INFRASTRUCTURE_CHOICES:
		var choice_id := str(choice.get("id", ""))
		var choice_card := _infrastructure_choice(choice)
		_infrastructure_choice_cards[choice_id] = choice_card
		_infrastructure_pager.call("add_choice", choice_card)

	var operations_section := _section_card(
		"TransportOperationsSection",
		"2. 路線與營運決策",
		"設定車隊規模、班距與票價，再選擇要規劃的交通模式。"
	)
	_operations_section_card = operations_section.get_parent() as Control
	var settings := GridContainer.new()
	settings.name = "TransportRouteSettings"
	settings.columns = 3
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.add_theme_constant_override("h_separation", 12)
	settings.add_theme_constant_override("v_separation", 10)
	settings.set_meta("progressive_choice_group", true)
	_fleet_input = _number_setting(settings, "車隊規模", "TransportFleetSize", 1, 40, 2, "輛")
	_headway_input = _number_setting(settings, "班距", "TransportHeadwayMinutes", 1, 60, 10, "分鐘")
	_fare_input = _number_setting(settings, "票價", "TransportRouteFare", 0, 500, 30, "元")
	for input: SpinBox in [_fleet_input, _headway_input, _fare_input]:
		input.value_changed.connect(func(_value: float) -> void: _refresh_live_summary())
	operations_section.add_child(settings)
	_live_summary = _label("", BODY_FONT_SIZE)
	_live_summary.name = "TransportLiveSummary"
	_live_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	operations_section.add_child(_live_summary)
	_route_mode_pager = ProgressiveChoicePagerScript.new(2, 3)
	_route_mode_pager.name = "TransportRouteModePager"
	_route_mode_pager.call("set_minimum_choice_width", PAGER_MINIMUM_CHOICE_WIDTH)
	_register_pager(_route_mode_pager)
	operations_section.add_child(_route_mode_pager)
	for mode: Dictionary in ROUTE_MODES:
		var mode_id := str(mode.get("id", ""))
		var mode_card := _route_mode_choice(mode)
		_route_mode_cards[mode_id] = mode_card
		_route_mode_pager.call("add_choice", mode_card)

	var route_section := _section_card(
		"TransportRouteListSection",
		"3. 已規劃路線",
		"檢視路線狀態、站點、路徑長度與營運設定；可啟停或刪除路線。"
	)
	_route_list_section_card = route_section.get_parent() as Control
	_network_summary = _label("路線總覽｜0 條規劃｜0 條營運中", BODY_FONT_SIZE)
	_network_summary.name = "TransportNetworkSummary"
	route_section.add_child(_network_summary)
	_route_pager = ProgressiveChoicePagerScript.new(1, 3)
	_route_pager.name = "TransportRoutePager"
	_register_pager(_route_pager)
	route_section.add_child(_route_pager)
	_choice_stash = _choice_stash_container()
	_content.add_child(_choice_stash)
	_route_empty_label = _label("目前沒有路線。請先從建設與藍圖核准交通站點，再完成基礎路網規劃。", BODY_FONT_SIZE)
	_route_empty_label.name = "TransportRouteEmpty"
	_route_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_route_empty_label.custom_minimum_size = Vector2(0, 88)
	route_section.add_child(_route_empty_label)

	_refresh_live_summary()
	_refresh_palette()


func _section_card(node_name: String, title_text: String, description_text: String) -> VBoxContainer:
	var card := _card(node_name)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 9)
	card.add_child(stack)
	stack.add_child(_label(title_text, SECTION_FONT_SIZE))
	var description := _label(description_text, BODY_FONT_SIZE)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(description)
	_content.add_child(card)
	return stack


func _infrastructure_choice(choice: Dictionary) -> PanelContainer:
	var kind := str(choice.get("id", "infrastructure"))
	var card := _card("TransportInfrastructureChoice_%s" % kind, true)
	card.set_meta("transport_infrastructure_kind", "rail_track" if kind == "heavy_rail" else kind)
	card.custom_minimum_size = Vector2(0, 172)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	card.add_child(stack)
	stack.add_child(_label(str(choice.get("label", kind)), SECTION_FONT_SIZE))
	var hint := _label(str(choice.get("hint", "")), BODY_FONT_SIZE)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(hint)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	stack.add_child(actions)
	var add_button := _button(
		"InfrastructureAdd_%s" % kind,
		str(choice.get("add_label", "興建")),
		"primary"
	)
	add_button.pressed.connect(_on_infrastructure_pressed.bind(kind, str(choice.get("add", "build"))))
	add_button.set_meta("transport_action", "infrastructure_add")
	add_button.set_meta("transport_kind", "rail_track" if kind == "heavy_rail" else kind)
	_new_plan_buttons.append(add_button)
	actions.add_child(add_button)
	var remove_button := _button(
		"InfrastructureRemove_%s" % kind,
		str(choice.get("remove_label", "拆除")),
		"danger"
	)
	remove_button.pressed.connect(_on_infrastructure_pressed.bind(kind, str(choice.get("remove", "demolish"))))
	remove_button.set_meta("transport_action", "infrastructure_remove")
	remove_button.set_meta("transport_kind", "rail_track" if kind == "heavy_rail" else kind)
	_new_plan_buttons.append(remove_button)
	actions.add_child(remove_button)
	return card


func _route_mode_choice(mode: Dictionary) -> PanelContainer:
	var mode_id := str(mode.get("id", "route"))
	var card := _card("TransportRouteMode_%s" % mode_id, true)
	card.set_meta("transport_route_mode", mode_id)
	card.custom_minimum_size = Vector2(0, 152)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	card.add_child(stack)
	stack.add_child(_label(str(mode.get("label", mode_id)), SECTION_FONT_SIZE))
	var hint := _label(str(mode.get("hint", "")), BODY_FONT_SIZE)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(hint)
	var button := _button("PlanRoute_%s" % mode_id, "開始規劃", "primary")
	button.set_meta("transport_action", "route")
	button.set_meta("transport_mode", mode_id)
	button.pressed.connect(_on_route_planning_pressed.bind(mode_id))
	_new_plan_buttons.append(button)
	stack.add_child(button)
	return card


func _number_setting(
	parent: GridContainer,
	label_text: String,
	node_name: String,
	minimum: int,
	maximum: int,
	default_value: int,
	suffix: String
) -> SpinBox:
	var card := _card("%sCard" % node_name, true)
	card.custom_minimum_size = Vector2(0, 116)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	card.add_child(stack)
	stack.add_child(_label(label_text, BODY_FONT_SIZE))
	var input := SpinBox.new()
	input.name = node_name
	input.min_value = minimum
	input.max_value = maximum
	input.step = 1
	input.value = default_value
	input.suffix = suffix
	input.custom_minimum_size = Vector2(190, CONTROL_HEIGHT)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.add_theme_font_size_override("font_size", CONTROL_FONT_SIZE)
	input.get_line_edit().add_theme_font_size_override("font_size", CONTROL_FONT_SIZE)
	input.tooltip_text = "%s｜%d–%d %s" % [label_text, minimum, maximum, suffix]
	_spin_boxes.append(input)
	stack.add_child(input)
	parent.add_child(card)
	return input


func _rebuild_route_cards(routes: Array) -> void:
	_route_pager.call("clear_choices", true)
	_route_models.clear()
	_route_empty_label.visible = routes.is_empty()
	for route_variant: Variant in routes:
		if not route_variant is Dictionary:
			continue
		var route: Dictionary = (route_variant as Dictionary).duplicate(true)
		var route_id := str(route.get("route_id", route.get("id", "")))
		if route_id.is_empty():
			continue
		_route_models[route_id] = route
		_route_pager.call("add_choice", _route_card(route_id, route))
	_refresh_palette()


func _route_card(route_id: String, route: Dictionary) -> PanelContainer:
	var card := _card("TransportRouteCard_%s" % _safe_node_part(route_id), true)
	card.custom_minimum_size = Vector2(0, 170)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 7)
	card.add_child(stack)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	stack.add_child(header)
	var route_title := str(route.get("name", route.get("title", route_id)))
	header.add_child(_label("%s｜%s" % [route_title, _mode_label(str(route.get("mode", "")))], SECTION_FONT_SIZE))
	var status := str(route.get("status", "draft"))
	var status_label := _label(_status_label(status), BODY_FONT_SIZE)
	status_label.name = "TransportRouteStatus_%s" % _safe_node_part(route_id)
	status_label.set_meta("transport_status", status)
	status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	status_label.custom_minimum_size = Vector2(96, 0)
	status_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(status_label)

	var stop_count := int(route.get("stop_count", _array_size(route.get("stop_ids", route.get("stops", [])))))
	var path_length := float(route.get("path_length", route.get("path_tile_count", 0)))
	var fleet_size := int(route.get("fleet_size", 0))
	var headway := int(route.get("headway_minutes", route.get("headway", 0)))
	var fare := int(route.get("fare", 0))
	var details := _label(
		"站點 %d｜路徑 %s 格｜車隊 %d 輛｜班距 %d 分鐘｜票價 $%d" % [
			stop_count,
			_format_length(path_length),
			fleet_size,
			headway,
			fare,
		],
		BODY_FONT_SIZE
	)
	details.name = "TransportRouteDetails_%s" % _safe_node_part(route_id)
	stack.add_child(details)
	var reason := str(route.get("status_detail", route.get("reason", "")))
	if not reason.is_empty():
		var reason_label := _label(reason, BODY_FONT_SIZE)
		reason_label.name = "TransportRouteReason_%s" % _safe_node_part(route_id)
		stack.add_child(reason_label)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 8)
	stack.add_child(actions)
	var enabled := bool(route.get("enabled", status == "operational"))
	var toggle := _button(
		"TransportRouteToggle_%s" % _safe_node_part(route_id),
		"停駛" if enabled else "啟用",
		"secondary"
	)
	toggle.disabled = not bool(route.get("can_toggle", true))
	toggle.pressed.connect(_on_route_toggle_pressed.bind(route_id, not enabled))
	actions.add_child(toggle)
	var remove := _button(
		"TransportRouteDelete_%s" % _safe_node_part(route_id),
		"刪除路線",
		"danger"
	)
	remove.disabled = not bool(route.get("can_delete", true))
	remove.pressed.connect(_on_route_delete_pressed.bind(route_id))
	actions.add_child(remove)
	return card


func _card(node_name: String, nested: bool = false) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = node_name
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.set_meta("transport_nested_card", nested)
	_cards.append(card)
	_style_card(card)
	return card


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = L10n.text(text)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", _text_color())
	_labels.append(label)
	return label


func _button(node_name: String, text: String, variant: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = L10n.text(text)
	button.custom_minimum_size = Vector2(136, CONTROL_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", CONTROL_FONT_SIZE)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.clip_text = true
	button.set_meta("transport_button_variant", variant)
	_buttons.append(button)
	_style_button(button)
	return button


func _register_pager(pager: Control) -> void:
	_pagers.append(pager)
	_refresh_pager_palette(pager)


func _refresh_live_summary() -> void:
	if _live_summary == null:
		return
	_live_summary.text = L10n.text(
		"目前方案：車隊 %d 輛｜班距 %d 分鐘｜票價 $%d。車輛只會在站點選址、全線路徑、平交道或號誌、車庫與路線啟用等條件全部完成後出現；任一條件未完成都不會生成行駛中的車輛。"
	) % [int(_fleet_input.value), int(_headway_input.value), int(_fare_input.value)]


func _render_planning_session() -> void:
	if _session_card == null:
		return
	var state := str(_planning_session.get("state", "inactive"))
	var visible := state not in ["inactive", "closed"]
	_session_card.visible = visible
	_apply_session_focus_layout(state, visible)
	if not visible:
		return
	var station_name := str(_planning_session.get("station_blueprint_name", "交通站點"))
	var is_package := str(_planning_session.get("workflow", "")) == TransportPlanningSessionScript.WORKFLOW_ROUTE_PACKAGE_V1
	var station_placements: Array = Dictionary(_planning_session.get("route_draft", {})).get("station_placements", [])
	var station_count := (
		station_placements.size()
		if is_package
		else _non_cancelled_reference_count(_planning_session.get("station_refs", []))
	)
	var completed_station_count := _completed_reference_count(_planning_session.get("station_refs", []))
	var reused_station_count := _reused_station_placement_count(station_placements) if is_package else 0
	if is_package and _array_size(_planning_session.get("station_refs", [])) == 0:
		completed_station_count = reused_station_count
	var network_count := _non_cancelled_reference_count(_planning_session.get("network_refs", []))
	if is_package and network_count == 0 and not Array(Dictionary(_planning_session.get("network_draft", {})).get("tile_ids", [])).is_empty():
		network_count = 1
	var route_count := _array_size(_planning_session.get("route_refs", []))
	_session_status_label.text = L10n.text("進行中規劃｜%s｜%s") % [L10n.text(station_name), _session_state_label(state)]
	if is_package and state == "route_edit" and bool(_package_quote.get("ok", false)):
		_session_detail_label.text = L10n.text("總包估價｜站點 $%d＋路線 %d 格 $%d＋支援 $%d＋平交道 $%d＝總工程費 $%d｜路線月維護 $%d") % [
			int(_package_quote.get("station_building_cost", 0)), int(_package_quote.get("route_tile_count", 0)),
			int(_package_quote.get("route_construction_cost", 0)), int(_package_quote.get("support_facility_cost", 0)),
			int(_package_quote.get("level_crossing_cost", 0)), int(_package_quote.get("total_cost", 0)),
			int(_package_quote.get("route_monthly_maintenance", 0)),
		]
	else:
		var completion_text := L10n.text("完工 %d") % completed_station_count
		if reused_station_count > 0:
			completion_text += L10n.text("；沿用完成 %d") % reused_station_count
		_session_detail_label.text = L10n.text("%s｜站點 %d（%s）｜路網工程 %d｜路線 %d") % [
			L10n.text(station_name), station_count, completion_text, network_count, route_count,
		]
	_session_continue_button.visible = state != "materialized"
	_session_continue_button.disabled = state == "waiting_construction" or (
		is_package and state == "route_edit" and not bool(_package_quote.get("can_start", false))
	)
	_session_continue_button.text = L10n.text(_session_continue_label(state))
	_session_close_button.text = L10n.text("結束規劃")


func _apply_session_focus_layout(state: String, session_visible: bool) -> void:
	for section in [_infrastructure_section_card, _operations_section_card, _route_list_section_card]:
		if section != null:
			section.visible = not session_visible
	if not session_visible:
		return
	var focused_state := state
	if state == "paused":
		focused_state = str(_planning_session.get("resume_state", "station_placement"))
	match focused_state:
		"network_placement":
			if _infrastructure_section_card != null:
				_infrastructure_section_card.visible = true
		"route_edit":
			if _operations_section_card != null:
				_operations_section_card.visible = true
		"materialized":
			if _route_list_section_card != null:
				_route_list_section_card.visible = true


func _refresh_session_scoped_choices() -> void:
	if _choice_stash == null:
		_choice_stash = _choice_stash_container()
		_content.add_child(_choice_stash)
	if _infrastructure_pager == null or _route_mode_pager == null:
		return
	_infrastructure_pager.call("clear_choices", false)
	_route_mode_pager.call("clear_choices", false)
	_stash_scoped_cards(_infrastructure_choice_cards)
	_stash_scoped_cards(_route_mode_cards)
	var state := str(_planning_session.get("state", "inactive"))
	var session_active := state not in ["inactive", "closed"]
	var session_mode := str(_planning_session.get("mode", ""))
	for choice: Dictionary in INFRASTRUCTURE_CHOICES:
		var choice_id := str(choice.get("id", ""))
		var normalized_kind := "rail_track" if choice_id == "heavy_rail" else choice_id
		if session_active and not TransportPlanningSessionScript.network_kind_matches_mode(session_mode, normalized_kind):
			continue
		var card := _infrastructure_choice_cards.get(choice_id) as Control
		if card != null and is_instance_valid(card):
			card.visible = true
			_infrastructure_pager.call("add_choice", card)
	for mode: Dictionary in ROUTE_MODES:
		var mode_id := str(mode.get("id", ""))
		if session_active and mode_id != session_mode:
			continue
		var card := _route_mode_cards.get(mode_id) as Control
		if card != null and is_instance_valid(card):
			card.visible = true
			_route_mode_pager.call("add_choice", card)


func _stash_scoped_cards(cards: Dictionary) -> void:
	for choice in cards.values():
		var card := choice as Control
		if card == null or not is_instance_valid(card):
			continue
		if card.get_parent() != null and card.get_parent() != _choice_stash:
			card.get_parent().remove_child(card)
		if card.get_parent() == null:
			_choice_stash.add_child(card)


func _choice_stash_container() -> Control:
	var stash := Control.new()
	stash.name = "TransportChoiceStash"
	stash.visible = false
	stash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return stash


func _scoped_infrastructure_choice_ids() -> Array[String]:
	var result: Array[String] = []
	if _infrastructure_pager == null:
		return result
	for card_variant: Variant in _infrastructure_pager.call("choices"):
		var card := card_variant as Control
		if card != null:
			result.append(str(card.get_meta("transport_infrastructure_kind", "")))
	return result


func _scoped_route_mode_ids() -> Array[String]:
	var result: Array[String] = []
	if _route_mode_pager == null:
		return result
	for card_variant: Variant in _route_mode_pager.call("choices"):
		var card := card_variant as Control
		if card != null:
			result.append(str(card.get_meta("transport_route_mode", "")))
	return result


func _refresh_new_plan_button_states() -> void:
	var state := str(_planning_session.get("state", "inactive"))
	var session_active := state not in ["inactive", "closed"]
	var session_mode := str(_planning_session.get("mode", ""))
	var is_package := str(_planning_session.get("workflow", "")) == TransportPlanningSessionScript.WORKFLOW_ROUTE_PACKAGE_V1
	for button: Button in _new_plan_buttons:
		if not is_instance_valid(button):
			continue
		var disabled := not _planning_unlocked
		if session_active and not disabled:
			match str(button.get_meta("transport_action", "")):
				"infrastructure_add":
					disabled = state != "network_placement" or not TransportPlanningSessionScript.network_kind_matches_mode(
						session_mode, str(button.get_meta("transport_kind", ""))
					)
				"infrastructure_remove":
					disabled = true
				"route":
					disabled = is_package or state != "route_edit" or str(button.get_meta("transport_mode", "")) != session_mode
		button.disabled = disabled


func _session_state_label(state: String) -> String:
	return {
		"station_placement": "步驟 1/3：站點選址",
		"network_placement": "步驟 2/3：規劃路網",
		"route_edit": "步驟 3/3：路線設定",
		"waiting_construction": "等待施工完成",
		"paused": "已暫停",
		"materialized": "規劃已完成",
	}.get(state, "交通規劃")


func _session_continue_label(state: String) -> String:
	if (
		str(_planning_session.get("workflow", "")) == TransportPlanningSessionScript.WORKFLOW_ROUTE_PACKAGE_V1
		and state == "route_edit"
	):
		return "確認總包並開工"
	return {
		"station_placement": "繼續放置站點",
		"network_placement": "下一步：規劃路線",
		"route_edit": "繼續設定路線",
		"waiting_construction": "等待施工完成",
		"paused": "繼續規劃",
	}.get(state, "繼續規劃")


func _non_cancelled_reference_count(value: Variant) -> int:
	if not value is Array:
		return 0
	var result := 0
	for ref_value: Variant in value:
		if ref_value is Dictionary and str((ref_value as Dictionary).get("status", "")) != "cancelled":
			result += 1
	return result


func _completed_reference_count(value: Variant) -> int:
	if not value is Array:
		return 0
	var result := 0
	for ref_value: Variant in value:
		if ref_value is Dictionary and str((ref_value as Dictionary).get("status", "")) == "completed":
			result += 1
	return result


func _reused_station_placement_count(value: Variant) -> int:
	if not value is Array:
		return 0
	var result := 0
	for placement_value: Variant in value:
		if (
			placement_value is Dictionary
			and bool((placement_value as Dictionary).get("reuse_existing_station", false))
			and not str((placement_value as Dictionary).get("existing_station_id", "")).is_empty()
		):
			result += 1
	return result


func _on_infrastructure_pressed(kind: String, operation: String) -> void:
	infrastructure_requested.emit(kind, operation)


func _on_route_planning_pressed(mode: String) -> void:
	route_planning_requested.emit(
		mode,
		int(_fleet_input.value),
		int(_headway_input.value),
		int(_fare_input.value)
	)


func _on_route_toggle_pressed(route_id: String, enabled: bool) -> void:
	route_toggle_requested.emit(route_id, enabled)


func _on_route_delete_pressed(route_id: String) -> void:
	route_delete_requested.emit(route_id)


func _refresh_palette() -> void:
	_cleanup_styled_nodes()
	for label: Label in _labels:
		if not is_instance_valid(label):
			continue
		var status := str(label.get_meta("transport_status", ""))
		label.add_theme_color_override("font_color", _status_color(status) if not status.is_empty() else _text_color())
	for card: PanelContainer in _cards:
		if is_instance_valid(card):
			_style_card(card)
	for button: Button in _buttons:
		if is_instance_valid(button):
			_style_button(button)
	for input: SpinBox in _spin_boxes:
		if is_instance_valid(input):
			_style_spin_box(input)
	for pager: Control in _pagers:
		if is_instance_valid(pager):
			_refresh_pager_palette(pager)


func _style_card(card: PanelContainer) -> void:
	var nested := bool(card.get_meta("transport_nested_card", false))
	var style := StyleBoxFlat.new()
	style.bg_color = (
		Color(0.12, 0.19, 0.25) if nested else Color(0.08, 0.15, 0.21)
	) if _dark_mode else (
		Color(0.98, 0.96, 0.90) if nested else Color(0.94, 0.91, 0.82)
	)
	style.border_color = Color(0.36, 0.61, 0.76) if _dark_mode else Color(0.59, 0.43, 0.23)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14
	style.content_margin_top = 12
	style.content_margin_right = 14
	style.content_margin_bottom = 12
	style.shadow_color = Color(0, 0, 0, 0.16)
	style.shadow_size = 3
	card.add_theme_stylebox_override("panel", style)


func _style_button(button: Button) -> void:
	var variant := str(button.get_meta("transport_button_variant", "secondary"))
	var base := Color(0.05, 0.43, 0.70)
	if variant == "danger":
		base = Color(0.72, 0.20, 0.14)
	elif variant == "secondary":
		base = Color(0.24, 0.38, 0.48) if _dark_mode else Color(0.46, 0.55, 0.57)
	var normal := _button_style(base)
	var hover := _button_style(base.lightened(0.10))
	var pressed := _button_style(base.darkened(0.12))
	var disabled := _button_style(Color(0.27, 0.32, 0.36) if _dark_mode else Color(0.76, 0.79, 0.79))
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color(0.65, 0.86, 1.0) if _dark_mode else Color(0.35, 0.24, 0.10)
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(9)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover_pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.70, 0.76, 0.80) if _dark_mode else Color(0.36, 0.40, 0.42))


func _style_spin_box(input: SpinBox) -> void:
	var background := Color(0.10, 0.17, 0.23) if _dark_mode else Color(1.0, 0.98, 0.92)
	var border := Color(0.39, 0.62, 0.76) if _dark_mode else Color(0.58, 0.42, 0.22)
	var line_edit := input.get_line_edit()
	line_edit.add_theme_color_override("font_color", _text_color())
	line_edit.add_theme_color_override("caret_color", _text_color())
	line_edit.add_theme_stylebox_override("normal", _form_style(background, border))
	line_edit.add_theme_stylebox_override("focus", _form_style(background.lightened(0.03), border.lightened(0.15), 3))
	line_edit.add_theme_stylebox_override("read_only", _form_style(background.darkened(0.04), border))
	for state: String in ["up_background", "up_background_hovered", "up_background_pressed", "up_background_disabled", "down_background", "down_background_hovered", "down_background_pressed", "down_background_disabled"]:
		input.add_theme_stylebox_override(state, _form_style(background, border, 1))
	for color_name: String in ["up_icon_modulate", "up_hover_icon_modulate", "up_pressed_icon_modulate", "down_icon_modulate", "down_hover_icon_modulate", "down_pressed_icon_modulate"]:
		input.add_theme_color_override(color_name, _text_color())


func _refresh_pager_palette(pager: Control) -> void:
	for child_variant: Variant in pager.find_children("*", "Button", true, false):
		var button := child_variant as Button
		if button == null:
			continue
		if not button.has_meta("transport_button_variant"):
			button.set_meta("transport_button_variant", "secondary")
		_style_button(button)
	for child_variant: Variant in pager.find_children("*", "Label", true, false):
		var label := child_variant as Label
		if label != null:
			label.add_theme_color_override("font_color", _text_color())
			label.add_theme_color_override("font_outline_color", Color.TRANSPARENT)
			label.add_theme_constant_override("outline_size", 0)


func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = color.lightened(0.13)
	style.set_border_width_all(2)
	style.set_corner_radius_all(9)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style


func _form_style(background: Color, border: Color, width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style


func _text_color() -> Color:
	return Color(0.91, 0.95, 0.98) if _dark_mode else Color(0.07, 0.12, 0.18)


func _status_color(status: String) -> Color:
	if status == "operational":
		return Color(0.42, 0.93, 0.62) if _dark_mode else Color(0.03, 0.43, 0.20)
	if status in ["building", "planned", "draft"]:
		return Color(1.0, 0.80, 0.30) if _dark_mode else Color(0.68, 0.42, 0.02)
	if status in ["disabled", "suspended", "invalid", "blocked"]:
		return Color(1.0, 0.52, 0.42) if _dark_mode else Color(0.70, 0.12, 0.08)
	return _text_color()


func _status_label(status: String) -> String:
	match status:
		"draft": return L10n.text("草案")
		"planned": return L10n.text("已規劃")
		"building": return L10n.text("施工中")
		"operational": return L10n.text("營運中")
		"disabled": return L10n.text("已停駛")
		"suspended": return L10n.text("已停駛")
		"invalid": return L10n.text("路網不完整")
		"blocked": return L10n.text("待排除衝突")
		_: return L10n.text(status if not status.is_empty() else "未知狀態")


func _mode_label(mode: String) -> String:
	for definition: Dictionary in ROUTE_MODES:
		if str(definition.get("id", "")) == mode:
			return L10n.text(str(definition.get("label", mode)))
	return L10n.text(mode if not mode.is_empty() else "未指定模式")


func _format_length(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value


func _array_size(value: Variant) -> int:
	return (value as Array).size() if value is Array else 0


func _safe_node_part(value: String) -> String:
	var safe := value.strip_edges()
	for character: String in ["/", "\\", ":", ".", " "]:
		safe = safe.replace(character, "_")
	return safe if not safe.is_empty() else "unknown"


func _cleanup_styled_nodes() -> void:
	_labels = _valid_labels(_labels)
	_cards = _valid_cards(_cards)
	_buttons = _valid_buttons(_buttons)
	_spin_boxes = _valid_spin_boxes(_spin_boxes)
	_new_plan_buttons = _valid_buttons(_new_plan_buttons)


func _valid_labels(source: Array[Label]) -> Array[Label]:
	var result: Array[Label] = []
	for item: Label in source:
		if is_instance_valid(item):
			result.append(item)
	return result


func _valid_cards(source: Array[PanelContainer]) -> Array[PanelContainer]:
	var result: Array[PanelContainer] = []
	for item: PanelContainer in source:
		if is_instance_valid(item):
			result.append(item)
	return result


func _valid_buttons(source: Array[Button]) -> Array[Button]:
	var result: Array[Button] = []
	for item: Button in source:
		if is_instance_valid(item):
			result.append(item)
	return result


func _valid_spin_boxes(source: Array[SpinBox]) -> Array[SpinBox]:
	var result: Array[SpinBox] = []
	for item: SpinBox in source:
		if is_instance_valid(item):
			result.append(item)
	return result
