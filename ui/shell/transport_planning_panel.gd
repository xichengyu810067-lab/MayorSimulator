class_name TransportPlanningPanel
extends ScrollContainer

const ProgressiveChoicePagerScript = preload("res://ui/components/progressive_choice_pager.gd")

signal infrastructure_requested(kind: String, operation: String)
signal station_requested(building_name: String)
signal route_planning_requested(mode: String, fleet_size: int, headway_minutes: int, fare: int)
signal route_toggle_requested(route_id: String, enabled: bool)
signal route_delete_requested(route_id: String)

const BODY_FONT_SIZE := 18
const SECTION_FONT_SIZE := 22
const TITLE_FONT_SIZE := 28
const CONTROL_FONT_SIZE := 18
const CONTROL_HEIGHT := 52.0
const CONTENT_MINIMUM_WIDTH := 900.0

const STATION_CHOICES: Array[Dictionary] = [
	{"id": "bus_station", "building_name": "公車站", "hint": "作為公車路線端點或轉運站，仍須接入完整道路。"},
	{"id": "metro_station", "building_name": "捷運站", "hint": "選址後必須以連續捷運軌道連接至少兩站。"},
	{"id": "rail_station", "building_name": "火車站", "hint": "選址後必須連接重型鐵路、機廠與號誌。"},
	{"id": "airport", "building_name": "機場", "hint": "航廈必須連接跑道與滑行道，完成後才能安排航線。"},
]

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

var _content: VBoxContainer
var _unlock_label: Label
var _live_summary: Label
var _network_summary: Label
var _fleet_input: SpinBox
var _headway_input: SpinBox
var _fare_input: SpinBox
var _station_pager: Control
var _infrastructure_pager: Control
var _route_mode_pager: Control
var _route_pager: Control
var _route_empty_label: Label


func _init() -> void:
	name = "交通規劃"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_build_content()


func set_view_model(snapshot: Dictionary) -> void:
	_view_model = snapshot.duplicate(true)
	_planning_unlocked = bool(snapshot.get("planning_unlocked", snapshot.get("unlocked", true)))
	_unlock_label.text = (
		L10n.text("交通規劃已解鎖｜可進行站點、路網與營運決策。")
		if _planning_unlocked
		else L10n.text("交通規劃尚未解鎖｜請先完成對應的城市交通決策。")
	)
	for button: Button in _new_plan_buttons:
		if is_instance_valid(button):
			button.disabled = not _planning_unlocked

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


func set_dark_mode(enabled: bool) -> void:
	_dark_mode = enabled
	_refresh_palette()


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
		"station_choices": STATION_CHOICES.duplicate(true),
		"infrastructure_choices": INFRASTRUCTURE_CHOICES.duplicate(true),
		"route_modes": ROUTE_MODES.duplicate(true),
	}


func _build_content() -> void:
	_content = VBoxContainer.new()
	_content.name = "TransportPlanningContent"
	_content.custom_minimum_size = Vector2(CONTENT_MINIMUM_WIDTH, 0)
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
	_unlock_label = _label("交通規劃已解鎖｜可進行站點、路網與營運決策。", BODY_FONT_SIZE)
	_unlock_label.name = "TransportPlanningUnlockStatus"
	hero_stack.add_child(_unlock_label)
	_content.add_child(hero)

	var station_section := _section_card(
		"TransportStationSection",
		"1. 站點選址",
		"先選擇公車站、捷運站、火車站或機場；站點完成後再建立連接路網。"
	)
	_station_pager = ProgressiveChoicePagerScript.new(3, 3)
	_station_pager.name = "TransportStationPager"
	_register_pager(_station_pager)
	station_section.add_child(_station_pager)
	for choice: Dictionary in STATION_CHOICES:
		_station_pager.call("add_choice", _station_choice(choice))

	var infrastructure_section := _section_card(
		"TransportInfrastructureSection",
		"2. 路網與設施",
		"鋪設或拆除道路、捷運軌道、重型鐵路、跑道、滑行道；另可設置車庫、機廠與鐵路號誌。"
	)
	_infrastructure_pager = ProgressiveChoicePagerScript.new(3, 3)
	_infrastructure_pager.name = "TransportInfrastructurePager"
	_register_pager(_infrastructure_pager)
	infrastructure_section.add_child(_infrastructure_pager)
	for choice: Dictionary in INFRASTRUCTURE_CHOICES:
		_infrastructure_pager.call("add_choice", _infrastructure_choice(choice))

	var operations_section := _section_card(
		"TransportOperationsSection",
		"3. 路線與營運決策",
		"設定車隊規模、班距與票價，再選擇要規劃的交通模式。"
	)
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
	_route_mode_pager = ProgressiveChoicePagerScript.new(3, 3)
	_route_mode_pager.name = "TransportRouteModePager"
	_register_pager(_route_mode_pager)
	operations_section.add_child(_route_mode_pager)
	for mode: Dictionary in ROUTE_MODES:
		_route_mode_pager.call("add_choice", _route_mode_choice(mode))

	var route_section := _section_card(
		"TransportRouteListSection",
		"4. 已規劃路線",
		"檢視路線狀態、站點、路徑長度與營運設定；可啟停或刪除路線。"
	)
	_network_summary = _label("路線總覽｜0 條規劃｜0 條營運中", BODY_FONT_SIZE)
	_network_summary.name = "TransportNetworkSummary"
	route_section.add_child(_network_summary)
	_route_pager = ProgressiveChoicePagerScript.new(1, 3)
	_route_pager.name = "TransportRoutePager"
	_register_pager(_route_pager)
	route_section.add_child(_route_pager)
	_route_empty_label = _label("目前沒有路線。請先完成站點選址與基礎路網規劃。", BODY_FONT_SIZE)
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


func _station_choice(choice: Dictionary) -> PanelContainer:
	var choice_id := str(choice.get("id", "station"))
	var building_name := str(choice.get("building_name", "站點"))
	var card := _card("TransportStationChoice_%s" % choice_id, true)
	card.custom_minimum_size = Vector2(0, 154)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	card.add_child(stack)
	stack.add_child(_label(building_name, SECTION_FONT_SIZE))
	var hint := _label(str(choice.get("hint", "")), BODY_FONT_SIZE)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(hint)
	var button := _button("StationAction_%s" % choice_id, "選址 %s" % building_name, "primary")
	button.pressed.connect(_on_station_pressed.bind(building_name))
	_new_plan_buttons.append(button)
	stack.add_child(button)
	return card


func _infrastructure_choice(choice: Dictionary) -> PanelContainer:
	var kind := str(choice.get("id", "infrastructure"))
	var card := _card("TransportInfrastructureChoice_%s" % kind, true)
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
	_new_plan_buttons.append(add_button)
	actions.add_child(add_button)
	var remove_button := _button(
		"InfrastructureRemove_%s" % kind,
		str(choice.get("remove_label", "拆除")),
		"danger"
	)
	remove_button.pressed.connect(_on_infrastructure_pressed.bind(kind, str(choice.get("remove", "demolish"))))
	_new_plan_buttons.append(remove_button)
	actions.add_child(remove_button)
	return card


func _route_mode_choice(mode: Dictionary) -> PanelContainer:
	var mode_id := str(mode.get("id", "route"))
	var card := _card("TransportRouteMode_%s" % mode_id, true)
	card.custom_minimum_size = Vector2(0, 152)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	card.add_child(stack)
	stack.add_child(_label(str(mode.get("label", mode_id)), SECTION_FONT_SIZE))
	var hint := _label(str(mode.get("hint", "")), BODY_FONT_SIZE)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(hint)
	var button := _button("PlanRoute_%s" % mode_id, "開始規劃", "primary")
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


func _on_station_pressed(building_name: String) -> void:
	station_requested.emit(building_name)


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
