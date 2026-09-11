extends Control

const CourtroomStageScript = preload("res://ui/governance/courtroom_stage.gd")
const OversightHearingStageScript = preload("res://ui/governance/oversight_hearing_stage.gd")
const SemanticPalette = preload("res://ui/theme/semantic_palette.gd")

signal defense_submitted(mode: String, case_id: String, defense_id: String, result: Dictionary)

const BODY_SIZE := 18
const TITLE_SIZE := 25
const MODE_JUDICIAL := "judicial"
const MODE_OVERSIGHT := "oversight"
const DAYS_PER_MONTH := 30
const MONTHS_PER_YEAR := 12
const JUDICIAL_STAGES := ["filed", "preparation", "hearing", "deliberation", "judgment"]
const JUDICIAL_STAGE_LABELS := {
	"filed": "立案",
	"preparation": "書狀準備",
	"hearing": "開庭陳述",
	"deliberation": "合議評議",
	"judgment": "宣判",
}
const FAILURE_REASON_LABELS := {
	"imprisonment_judgment": "監禁判決",
	"grievance_above_80": "民怨超過 80",
	"municipal_trust_below_40": "市政信任低於 40",
}
const MODE_CONFIG := {
	MODE_JUDICIAL: {
		"page_name": "法院審判",
		"icon": "justice",
		"accent": Color(0.35, 0.34, 0.72),
		"purpose": "違法案件審判｜玩家提出辯護",
		"empty_hint": "玩家違法強制施政後，案件會在此開庭並等待辯護。",
		"defenses": [
			{"id": "public_interest", "label": "公共利益", "detail": "主張措施是為避免公共利益遭受立即損害。"},
			{"id": "fiscal_emergency", "label": "財政緊急", "detail": "說明措施是為避免市政財務立即失靈。"},
			{"id": "safety_emergency", "label": "公共安全", "detail": "提出居民生命安全面臨即時風險的證據。"},
		],
	},
	MODE_OVERSIGHT: {
		"page_name": "監察質詢",
		"icon": "oversight",
		"accent": Color(0.05, 0.48, 0.58),
		"purpose": "行政質詢｜彈劾程序辯護",
		"empty_hint": "玩家遭監察調查或面臨彈劾時，會在此接受質詢並答辯。",
		"defenses": [
			{"id": "full_disclosure", "label": "完整揭露", "detail": "公開決策紀錄與證據，降低資訊不透明疑慮。"},
			{"id": "due_process", "label": "程序答辯", "detail": "說明行政程序、權限依據與議會互動紀錄。"},
			{"id": "corrective_action", "label": "主動改正", "detail": "提出停止爭議措施與補救居民損害的方案。"},
		],
	},
}

var mode := MODE_JUDICIAL
var _system
var _dark_mode := false
var _labels: Array[Label] = []
var _defense_buttons: Dictionary = {}
var _summary_label: Label
var _case_title: Label
var _case_detail: Label
var _defense_status: Label
var _case_panel: PanelContainer
var _case_selector: OptionButton
var _case_page_label: Label
var _previous_case_button: Button
var _next_case_button: Button
var _courtroom_stage
var _oversight_hearing_stage
var _procedure_labels: Dictionary = {}
var _next_step_label: Label
var _bench_label: Label
var _open_case_ids: Array[String] = []
var _selected_case_id: String = ""


func _init(p_mode: String = MODE_JUDICIAL) -> void:
	mode = p_mode if MODE_CONFIG.has(p_mode) else MODE_JUDICIAL
	name = str(_config()["page_name"])
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(720, 420)
	clip_contents = true
	_build_content()


func set_dark_mode(enabled: bool) -> void:
	_dark_mode = enabled
	var text_color := SemanticPalette.color_for(enabled, "text_primary")
	for label: Label in _labels:
		label.add_theme_color_override("font_color", text_color)
	if mode == MODE_JUDICIAL and _courtroom_stage != null:
		_courtroom_stage.set_dark_mode(enabled)
	elif mode == MODE_OVERSIGHT and _oversight_hearing_stage != null:
		_oversight_hearing_stage.set_dark_mode(enabled)
	_apply_case_style()
	for button_variant in _defense_buttons.values():
		_style_defense_button(button_variant as Button, text_color)
	for button in [_previous_case_button, _next_case_button]:
		if is_instance_valid(button):
			_style_defense_button(button as Button, text_color)
	# Timeline colors are assigned per procedural state, so they must be
	# recomputed when the player changes theme while this page is open.
	if not _procedure_labels.is_empty():
		_refresh_procedure_timeline(_active_case() if _system != null else {})


func refresh(system) -> void:
	_system = system
	if _system == null:
		return
	var summary: Dictionary = _system.committee_summary()
	var open_key := "judicial_open_cases" if mode == MODE_JUDICIAL else "oversight_open_cases"
	var active_key := "judicial_active" if mode == MODE_JUDICIAL else "oversight_active"
	var capacity_key := "judicial_capacity" if mode == MODE_JUDICIAL else "oversight_capacity"
	var open_cases := int(summary.get(open_key, 0))
	var game_day := int(summary.get("current_day", 0))
	_summary_label.text = L10n.text("%s｜委員 %d / %d｜待處理 %d 件") % [
		_format_game_date(game_day),
		int(summary.get(active_key, 0)),
		int(summary.get(capacity_key, 0)),
		open_cases,
	]
	_refresh_case_navigation()


func submit_current_defense(template_id: String) -> Dictionary:
	if _system == null:
		return {"ok": false, "error": "system_not_ready"}
	var active_case := _active_case()
	if active_case.is_empty():
		return {"ok": false, "error": "no_active_case"}
	var case_id := str(active_case.get("id", ""))
	var result: Dictionary
	if mode == MODE_JUDICIAL:
		result = _system.submit_defense(case_id, template_id)
	else:
		result = _system.submit_oversight_defense(case_id, template_id)
	if bool(result.get("ok", false)):
		refresh(_system)
		if mode == MODE_OVERSIGHT and _oversight_hearing_stage != null:
			_oversight_hearing_stage.play_defense(template_id)
	defense_submitted.emit(mode, case_id, template_id, result)
	return result


func _build_content() -> void:
	if mode == MODE_JUDICIAL:
		_courtroom_stage = CourtroomStageScript.new()
		add_child(_courtroom_stage)
		_courtroom_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		_oversight_hearing_stage = OversightHearingStageScript.new()
		add_child(_oversight_hearing_stage)
		_oversight_hearing_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var stage = _courtroom_stage if mode == MODE_JUDICIAL else _oversight_hearing_stage
	var top_host := stage.top_content() as HBoxContainer
	var tray_host := stage.tray_content() as VBoxContainer

	_summary_label = _body("載入案件資料中……")
	_summary_label.name = "JusticeOversightSummary"
	_summary_label.custom_minimum_size = Vector2(172, 44)
	_summary_label.max_lines_visible = 2
	_summary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_summary_label.add_theme_font_size_override("font_size", 15)
	top_host.add_child(_summary_label)

	_case_panel = PanelContainer.new()
	_case_panel.name = "DefenseCasePanel"
	_case_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_case_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tray_host.add_child(_case_panel)
	var case_margin := MarginContainer.new()
	case_margin.add_theme_constant_override("margin_left", 12)
	case_margin.add_theme_constant_override("margin_top", 7)
	case_margin.add_theme_constant_override("margin_right", 12)
	case_margin.add_theme_constant_override("margin_bottom", 7)
	_case_panel.add_child(case_margin)
	var case_stack := VBoxContainer.new()
	case_stack.add_theme_constant_override("separation", 4)
	case_margin.add_child(case_stack)
	var case_navigation := HBoxContainer.new()
	case_navigation.name = "CaseNavigation"
	case_navigation.add_theme_constant_override("separation", 6)
	case_navigation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_host.add_child(case_navigation)
	_previous_case_button = Button.new()
	_previous_case_button.name = "CasePreviousButton"
	_previous_case_button.text = "←"
	_previous_case_button.tooltip_text = "← 上一案"
	_previous_case_button.set_meta("semantic_label", "← 上一案")
	_previous_case_button.custom_minimum_size = Vector2(48, 44)
	_previous_case_button.disabled = true
	_previous_case_button.pressed.connect(_select_previous_case)
	case_navigation.add_child(_previous_case_button)
	_case_selector = OptionButton.new()
	_case_selector.name = "CaseSelector"
	_case_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_case_selector.custom_minimum_size = Vector2(210, 44)
	_case_selector.fit_to_longest_item = false
	_case_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_case_selector.disabled = true
	_case_selector.item_selected.connect(_on_case_selected)
	case_navigation.add_child(_case_selector)
	_case_page_label = _body("")
	_case_page_label.name = "CasePagerLabel"
	_case_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_case_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_case_page_label.custom_minimum_size = Vector2(80, 44)
	_case_page_label.add_theme_font_size_override("font_size", 14)
	case_navigation.add_child(_case_page_label)
	_next_case_button = Button.new()
	_next_case_button.name = "CaseNextButton"
	_next_case_button.text = "→"
	_next_case_button.tooltip_text = "下一案 →"
	_next_case_button.set_meta("semantic_label", "下一案 →")
	_next_case_button.custom_minimum_size = Vector2(48, 44)
	_next_case_button.disabled = true
	_next_case_button.pressed.connect(_select_next_case)
	case_navigation.add_child(_next_case_button)
	_case_title = _title("目前無待處理案件")
	_case_title.add_theme_font_size_override("font_size", 20)
	_case_title.custom_minimum_size = Vector2(0, 28)
	_case_title.max_lines_visible = 1
	_case_title.set_meta("l10n_skip", true)
	case_stack.add_child(_case_title)
	_case_detail = _body(str(_config()["empty_hint"]))
	_case_detail.add_theme_font_size_override("font_size", 15)
	_case_detail.custom_minimum_size = Vector2(0, 36)
	_case_detail.max_lines_visible = 2
	_case_detail.set_meta("l10n_skip", true)
	case_stack.add_child(_case_detail)
	if mode == MODE_JUDICIAL:
		_build_procedure_timeline(case_stack)
	_defense_status = _body("案件成立後即可選擇辯護策略。")
	_defense_status.add_theme_font_size_override("font_size", 15)
	_defense_status.custom_minimum_size = Vector2(0, 24)
	_defense_status.max_lines_visible = 1
	_defense_status.set_meta("l10n_skip", true)
	case_stack.add_child(_defense_status)
	var defense_row := HBoxContainer.new()
	defense_row.name = "DefenseActions"
	defense_row.add_theme_constant_override("separation", 8)
	case_stack.add_child(defense_row)
	for option_variant in _config()["defenses"]:
		var option: Dictionary = option_variant
		var button := Button.new()
		var option_id := str(option["id"])
		button.name = "%sDefenseButton" % option_id.to_pascal_case()
		button.text = "%s\n%s" % [str(option["label"]), str(option["detail"])]
		button.tooltip_text = str(option["detail"])
		button.set_meta("semantic_label", str(option["label"]))
		button.set_meta("semantic_detail", str(option["detail"]))
		button.custom_minimum_size = Vector2(150, 100)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 15)
		button.disabled = true
		button.pressed.connect(func() -> void: submit_current_defense(option_id))
		_defense_buttons[option_id] = button
		defense_row.add_child(button)

	set_dark_mode(_dark_mode)


func _refresh_case_navigation() -> void:
	var open_cases := _open_cases()
	_open_case_ids.clear()
	_case_selector.clear()
	for case_data: Dictionary in open_cases:
		var case_id := str(case_data.get("id", ""))
		_open_case_ids.append(case_id)
		_case_selector.add_item(_case_selector_label(case_data))
		_case_selector.set_item_metadata(_case_selector.item_count - 1, case_id)
	if _open_case_ids.is_empty():
		_selected_case_id = ""
		_case_selector.disabled = true
		_previous_case_button.disabled = true
		_next_case_button.disabled = true
		_case_page_label.text = L10n.text("第 %d / %d 案") % [0, 0]
		_previous_case_button.text = "←"
		_next_case_button.text = "→"
		_previous_case_button.tooltip_text = L10n.text("← 上一案")
		_next_case_button.tooltip_text = L10n.text("下一案 →")
		_refresh_case()
		return
	var selected_index := _open_case_ids.find(_selected_case_id)
	if selected_index < 0:
		selected_index = _open_case_ids.size() - 1
		_selected_case_id = _open_case_ids[selected_index]
	_case_selector.disabled = false
	_case_selector.select(selected_index)
	_update_case_navigation_state(selected_index)
	_refresh_case()


func _open_cases() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _system == null:
		return result
	var cases: Dictionary = _system.judicial_cases if mode == MODE_JUDICIAL else _system.oversight_cases
	for value_variant in cases.values():
		var case_data: Dictionary = value_variant
		if str(case_data.get("status", "")) == "investigating":
			result.append(case_data)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_sequence := int(a.get("sequence", 0))
		var b_sequence := int(b.get("sequence", 0))
		if a_sequence == b_sequence:
			return str(a.get("id", "")) < str(b.get("id", ""))
		return a_sequence < b_sequence
	)
	return result


func _case_selector_label(case_data: Dictionary) -> String:
	var sequence := int(case_data.get("sequence", 0))
	if mode == MODE_JUDICIAL:
		return "%d｜%s" % [sequence, _localized_judicial_case_name(str(case_data.get("name", "行政違法審判")))]
	return "%d｜%s" % [sequence, L10n.text("%s｜彈劾質詢") % L10n.text(str(case_data.get("target_name", "市長")))]


func _on_case_selected(index: int) -> void:
	if index < 0 or index >= _open_case_ids.size():
		return
	_selected_case_id = _open_case_ids[index]
	_update_case_navigation_state(index)
	_refresh_case()


func _select_previous_case() -> void:
	var index := _open_case_ids.find(_selected_case_id)
	if index > 0:
		_on_case_selected(index - 1)
		_case_selector.select(index - 1)


func _select_next_case() -> void:
	var index := _open_case_ids.find(_selected_case_id)
	if index >= 0 and index + 1 < _open_case_ids.size():
		_on_case_selected(index + 1)
		_case_selector.select(index + 1)


func _update_case_navigation_state(index: int) -> void:
	_previous_case_button.disabled = index <= 0
	_next_case_button.disabled = index < 0 or index >= _open_case_ids.size() - 1
	_previous_case_button.text = "←"
	_next_case_button.text = "→"
	_previous_case_button.tooltip_text = L10n.text("← 上一案")
	_next_case_button.tooltip_text = L10n.text("下一案 →")
	_case_page_label.text = L10n.text("第 %d / %d 案") % [index + 1, _open_case_ids.size()]


func selected_case_id() -> String:
	return _selected_case_id


func select_case_by_id(case_id: String) -> bool:
	var index := _open_case_ids.find(case_id)
	if index < 0:
		return false
	_case_selector.select(index)
	_on_case_selected(index)
	return true


func debug_layout_signature() -> Dictionary:
	var scroll_count := 0
	var positive_vertical_scroll_count := 0
	for node_variant in find_children("*", "ScrollContainer", true, false):
		var scroll := node_variant as ScrollContainer
		if scroll == null or not scroll.is_visible_in_tree():
			continue
		scroll_count += 1
		var bar := scroll.get_v_scroll_bar()
		if bar != null and bar.max_value - bar.page > 0.5:
			positive_vertical_scroll_count += 1
	var stage = _courtroom_stage if mode == MODE_JUDICIAL else _oversight_hearing_stage
	var stage_signature: Dictionary = stage.debug_signature()
	var minimum_target := INF
	for button_variant in [_previous_case_button, _next_case_button]:
		var button := button_variant as Button
		if is_instance_valid(button):
			minimum_target = minf(minimum_target, minf(button.size.x, button.size.y))
	for button_variant in _defense_buttons.values():
		var button := button_variant as Button
		if is_instance_valid(button):
			minimum_target = minf(minimum_target, minf(button.size.x, button.size.y))
	var defense_actions := find_child("DefenseActions", true, false) as HBoxContainer
	var defense_actions_rect := Rect2()
	var defense_actions_fully_visible := false
	if is_instance_valid(defense_actions) and defense_actions.is_visible_in_tree():
		defense_actions_rect = defense_actions.get_global_rect()
		defense_actions_fully_visible = get_global_rect().encloses(defense_actions_rect)
		if is_instance_valid(_case_panel):
			defense_actions_fully_visible = defense_actions_fully_visible and _case_panel.get_global_rect().encloses(defense_actions_rect)
		for button_variant in _defense_buttons.values():
			var defense_button := button_variant as Button
			if is_instance_valid(defense_button) and not defense_actions_rect.encloses(defense_button.get_global_rect()):
				defense_actions_fully_visible = false
	return {
		"mode": mode,
		"root_is_scroll_container": false,
		"scroll_container_count": scroll_count,
		"positive_vertical_scroll_count": positive_vertical_scroll_count,
		"minimum_interactive_extent": 0.0 if minimum_target == INF else minimum_target,
		"defense_actions_rect": defense_actions_rect,
		"defense_actions_fully_visible": defense_actions_fully_visible,
		"panel_rect": get_rect(),
		"top_rect": stage_signature.get("top_rect", Rect2()),
		"tray_rect": stage_signature.get("tray_rect", Rect2()),
		"actor_layer_count": int(stage_signature.get("actor_layer_count", 0)),
	}


func _refresh_case() -> void:
	if _case_title == null:
		return
	var active_case := _active_case()
	if active_case.is_empty():
		_case_title.text = L10n.text("目前無待處理案件")
		_case_detail.text = L10n.text(str(_config()["empty_hint"]))
		_defense_status.text = L10n.text("案件成立後即可選擇辯護策略。")
		if mode == MODE_JUDICIAL:
			_courtroom_stage.show_empty()
			_refresh_procedure_timeline({})
		elif mode == MODE_OVERSIGHT and _oversight_hearing_stage != null:
			_oversight_hearing_stage.show_empty()
		for button_variant in _defense_buttons.values():
			var empty_button := button_variant as Button
			empty_button.disabled = true
			empty_button.text = "%s\n%s" % [
				L10n.text(str(empty_button.get_meta("semantic_label", "辯護"))),
				L10n.text(str(empty_button.get_meta("semantic_detail", ""))),
			]
		return

	var selected_id := str(active_case.get("defense_template_id", ""))
	if mode == MODE_JUDICIAL:
		_case_title.text = _localized_judicial_case_name(str(active_case.get("name", "行政違法審判")))
		_case_detail.text = L10n.text("案號 %s　｜　預定 %s 宣判　｜　案件嚴重度 %d / 100") % [
			str(active_case.get("id", "")),
			_format_game_date(int(active_case.get("decision_day", 0))),
			int(active_case.get("base_severity", 0)),
		]
		_courtroom_stage.set_case(active_case)
		_refresh_procedure_timeline(active_case)
	else:
		_case_title.text = L10n.text("%s｜彈劾質詢") % L10n.text(str(active_case.get("target_name", "市長")))
		var allegations_raw: Array = active_case.get("allegations", [])
		var localized_allegations: Array[String] = []
		for item in allegations_raw:
			localized_allegations.append(L10n.text(str(item)))
		_case_detail.text = L10n.text("第 %d 日表決　｜　證據強度 %d / 100　｜　%s") % [
			int(active_case.get("decision_day", 0)),
			int(active_case.get("evidence_strength", 0)),
			"、".join(localized_allegations),
		]
		if _oversight_hearing_stage != null:
			_oversight_hearing_stage.set_case(active_case)
	if _system.has_method("is_terminal_locked") and bool(_system.is_terminal_locked()):
		var failure_reason := str(_system.terminal_failure_reason())
		_defense_status.text = L10n.text("遊戲失敗：%s") % L10n.text(str(FAILURE_REASON_LABELS.get(failure_reason, "狀態未知")))
		for button_variant in _defense_buttons.values():
			(button_variant as Button).disabled = true
		return
	var submission_closed := mode == MODE_JUDICIAL and str(active_case.get("procedural_stage", "filed")) in ["deliberation", "judgment"]
	if submission_closed:
		_defense_status.text = L10n.text("書狀提出期間已結束；合議庭正在評議。")
	else:
		_defense_status.text = L10n.text("尚未提出辯護；可在合議前補充或更換策略。") if selected_id.is_empty() else (L10n.text("已提出：%s（合議前仍可更換）") % L10n.text(_defense_label(selected_id)))
	for option_id: String in _defense_buttons:
		var button := _defense_buttons[option_id] as Button
		button.disabled = submission_closed
		var label := str(button.get_meta("semantic_label", option_id))
		var localized_label := L10n.text(label)
		var detail := L10n.text(str(button.get_meta("semantic_detail", "")))
		button.text = "%s%s\n%s" % ["✓ " if option_id == selected_id else "", localized_label, detail]


func _build_procedure_timeline(parent: VBoxContainer) -> void:
	var timeline := HBoxContainer.new()
	timeline.name = "JudicialProcedureTimeline"
	timeline.add_theme_constant_override("separation", 7)
	parent.add_child(timeline)
	for stage_id: String in JUDICIAL_STAGES:
		var stage_label := Label.new()
		stage_label.text = L10n.text(str(JUDICIAL_STAGE_LABELS[stage_id]))
		stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stage_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		stage_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stage_label.custom_minimum_size = Vector2(88, 40)
		stage_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stage_label.add_theme_font_size_override("font_size", 14)
		stage_label.set_meta("l10n_skip", true)
		timeline.add_child(stage_label)
		_procedure_labels[stage_id] = stage_label
	_next_step_label = _body("")
	_next_step_label.name = "JudicialNextStep"
	_next_step_label.set_meta("l10n_skip", true)
	_next_step_label.add_theme_font_size_override("font_size", 14)
	_next_step_label.custom_minimum_size = Vector2(0, 22)
	_next_step_label.max_lines_visible = 1
	parent.add_child(_next_step_label)
	_bench_label = _body("")
	_bench_label.name = "JudicialBenchLabel"
	_bench_label.set_meta("l10n_skip", true)
	_bench_label.add_theme_font_size_override("font_size", 14)
	_bench_label.custom_minimum_size = Vector2(0, 22)
	_bench_label.max_lines_visible = 1
	parent.add_child(_bench_label)


func _refresh_procedure_timeline(court_case: Dictionary) -> void:
	if _procedure_labels.is_empty():
		return
	var current_stage := str(court_case.get("procedural_stage", ""))
	var current_index := JUDICIAL_STAGES.find(current_stage)
	for index: int in JUDICIAL_STAGES.size():
		var stage_id: String = JUDICIAL_STAGES[index]
		var label := _procedure_labels[stage_id] as Label
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(8)
		style.set_border_width_all(2)
		if current_index < 0:
			style.bg_color = Color(0.2, 0.23, 0.25, 0.35)
			style.border_color = Color(0.42, 0.45, 0.48, 0.5)
			label.add_theme_color_override("font_color", Color(0.88, 0.92, 0.94) if _dark_mode else Color(0.12, 0.15, 0.18))
			label.text = L10n.text(str(JUDICIAL_STAGE_LABELS[stage_id]))
		elif index < current_index:
			style.bg_color = Color(0.18, 0.48, 0.38, 0.88)
			style.border_color = Color(0.42, 0.76, 0.60)
			label.add_theme_color_override("font_color", Color.WHITE)
			label.text = "✓ %s" % L10n.text(str(JUDICIAL_STAGE_LABELS[stage_id]))
		elif index == current_index:
			style.bg_color = Color(0.35, 0.34, 0.72, 0.96)
			style.border_color = Color(0.76, 0.71, 1.0)
			label.add_theme_color_override("font_color", Color.WHITE)
			label.text = "● %s" % L10n.text(str(JUDICIAL_STAGE_LABELS[stage_id]))
		else:
			style.bg_color = Color(0.17, 0.20, 0.23, 0.46) if _dark_mode else Color(0.88, 0.84, 0.75)
			style.border_color = Color(0.38, 0.40, 0.43, 0.72)
			label.add_theme_color_override("font_color", Color(0.92, 0.95, 0.97) if _dark_mode else Color(0.10, 0.13, 0.16))
			label.text = L10n.text(str(JUDICIAL_STAGE_LABELS[stage_id]))
		label.add_theme_stylebox_override("normal", style)
	if court_case.is_empty():
		_next_step_label.text = L10n.text("目前沒有進行中的法院案件。")
		_bench_label.text = ""
		return
	var schedule := {
		"filed": int(court_case.get("opened_day", 0)),
		"preparation": int(court_case.get("preparation_day", 0)),
		"hearing": int(court_case.get("hearing_day", 0)),
		"deliberation": int(court_case.get("deliberation_day", 0)),
		"judgment": int(court_case.get("decision_day", 0)),
	}
	var next_index := mini(current_index + 1, JUDICIAL_STAGES.size() - 1)
	var next_stage: String = JUDICIAL_STAGES[next_index]
	_next_step_label.text = L10n.text("目前：%s　｜　下一步：%s（%s）") % [
		L10n.text(str(JUDICIAL_STAGE_LABELS.get(current_stage, "程序待確認"))),
		L10n.text(str(JUDICIAL_STAGE_LABELS[next_stage])),
		_format_game_date(int(schedule[next_stage])),
	]
	var names: Array[String] = []
	for member_id: Variant in court_case.get("presiding_member_ids", []):
		var member: Dictionary = _system.get_member(str(member_id)) if _system != null else {}
		names.append(L10n.text(str(member.get("name", member_id))))
	_bench_label.text = L10n.text("本案主審合議庭：%s　｜　最終裁判仍由全體 15 名司法委員記名評議") % ("、".join(names) if not names.is_empty() else L10n.text("待排定"))


func _format_game_date(game_day: int) -> String:
	var safe_day := maxi(0, game_day)
	var days_per_year := DAYS_PER_MONTH * MONTHS_PER_YEAR
	var year := int(safe_day / days_per_year) + 1
	var year_day := safe_day % days_per_year
	var month := int(year_day / DAYS_PER_MONTH) + 1
	var day := year_day % DAYS_PER_MONTH + 1
	return L10n.text("第 %d 年 %d 月 %d 日") % [year, month, day]


func _localized_judicial_case_name(source: String) -> String:
	# Runtime names combine a bill title with a case suffix. Translating that
	# already-formatted string can leave untranslated fragments on screen.
	for suffix in ["違法施行案", "強制施行案", "強制執行案", "強制施行審查"]:
		if source.ends_with(suffix):
			var subject := source.trim_suffix(suffix).strip_edges()
			return L10n.text("違法施行案件：%s") % L10n.text(subject)
	return L10n.text(source)


func _active_case() -> Dictionary:
	if _system == null:
		return {}
	var cases: Dictionary = _system.judicial_cases if mode == MODE_JUDICIAL else _system.oversight_cases
	if not _selected_case_id.is_empty() and cases.has(_selected_case_id):
		var selected: Dictionary = cases[_selected_case_id]
		if str(selected.get("status", "")) == "investigating":
			return selected
	var open_cases := _open_cases()
	if open_cases.is_empty():
		return {}
	var fallback: Dictionary = open_cases.back()
	_selected_case_id = str(fallback.get("id", ""))
	return fallback


func _defense_label(template_id: String) -> String:
	for option_variant in _config()["defenses"]:
		var option: Dictionary = option_variant
		if str(option["id"]) == template_id:
			return str(option["label"])
	return template_id


func _config() -> Dictionary:
	return MODE_CONFIG[mode]


func _title(text: String) -> Label:
	var label := _body(text)
	label.add_theme_font_size_override("font_size", TITLE_SIZE)
	return label


func _body(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", BODY_SIZE)
	_labels.append(label)
	return label


func _apply_case_style() -> void:
	if not is_instance_valid(_case_panel):
		return
	var style := StyleBoxFlat.new()
	style.bg_color = SemanticPalette.color_for(_dark_mode, "surface_raised")
	style.bg_color.a = 0.82
	style.border_color = SemanticPalette.color_for(_dark_mode, "border_default")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	_case_panel.add_theme_stylebox_override("panel", style)


func _style_defense_button(button: Button, text_color: Color) -> void:
	if not is_instance_valid(button):
		return
	var normal := StyleBoxFlat.new()
	normal.bg_color = SemanticPalette.color_for(_dark_mode, "surface_muted")
	normal.border_color = SemanticPalette.color_for(_dark_mode, "border_default")
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(9)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = SemanticPalette.color_for(_dark_mode, "surface_raised")
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
