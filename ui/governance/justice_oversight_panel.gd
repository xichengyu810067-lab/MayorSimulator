extends ScrollContainer

const UiIconCatalog = preload("res://ui/theme/ui_icon_catalog.gd")

signal defense_submitted(mode: String, case_id: String, defense_id: String, result: Dictionary)

const BODY_SIZE := 18
const TITLE_SIZE := 25
const MODE_JUDICIAL := "judicial"
const MODE_OVERSIGHT := "oversight"
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
var _open_case_ids: Array[String] = []
var _selected_case_id: String = ""


func _init(p_mode: String = MODE_JUDICIAL) -> void:
	mode = p_mode if MODE_CONFIG.has(p_mode) else MODE_JUDICIAL
	name = str(_config()["page_name"])
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_build_content()


func set_dark_mode(enabled: bool) -> void:
	_dark_mode = enabled
	var text_color := Color(0.92, 0.96, 0.98) if enabled else Color(0.07, 0.12, 0.18)
	for label: Label in _labels:
		label.add_theme_color_override("font_color", text_color)
	_apply_case_style()
	for button_variant in _defense_buttons.values():
		_style_defense_button(button_variant as Button, text_color)
	for button in [_previous_case_button, _next_case_button]:
		if is_instance_valid(button):
			_style_defense_button(button as Button, text_color)


func refresh(system) -> void:
	_system = system
	if _system == null:
		return
	var summary: Dictionary = _system.committee_summary()
	var open_key := "judicial_open_cases" if mode == MODE_JUDICIAL else "oversight_open_cases"
	var open_cases := int(summary.get(open_key, 0))
	_summary_label.text = L10n.text("第 %d 年　｜　%d 件待處理") % [
		int(summary.get("current_year", 1)), open_cases,
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
	defense_submitted.emit(mode, case_id, template_id, result)
	return result


func _build_content() -> void:
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	add_child(content)

	var hero := HBoxContainer.new()
	hero.add_theme_constant_override("separation", 24)
	content.add_child(hero)
	var picture := TextureRect.new()
	picture.name = "FunctionIllustration"
	picture.texture = UiIconCatalog.texture(str(_config()["icon"]))
	picture.custom_minimum_size = Vector2(220, 220)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.tooltip_text = str(_config()["purpose"])
	hero.add_child(picture)

	var hero_text := VBoxContainer.new()
	hero_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_text.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_text.add_theme_constant_override("separation", 10)
	hero.add_child(hero_text)
	hero_text.add_child(_title(str(_config()["page_name"])))
	var purpose := _body(str(_config()["purpose"]))
	purpose.add_theme_font_size_override("font_size", 21)
	hero_text.add_child(purpose)
	_summary_label = _body("載入案件資料中……")
	hero_text.add_child(_summary_label)

	_case_panel = PanelContainer.new()
	_case_panel.name = "DefenseCasePanel"
	content.add_child(_case_panel)
	var case_margin := MarginContainer.new()
	case_margin.add_theme_constant_override("margin_left", 20)
	case_margin.add_theme_constant_override("margin_top", 16)
	case_margin.add_theme_constant_override("margin_right", 20)
	case_margin.add_theme_constant_override("margin_bottom", 18)
	_case_panel.add_child(case_margin)
	var case_stack := VBoxContainer.new()
	case_stack.add_theme_constant_override("separation", 9)
	case_margin.add_child(case_stack)
	var case_navigation := HBoxContainer.new()
	case_navigation.name = "CaseNavigation"
	case_navigation.add_theme_constant_override("separation", 10)
	case_stack.add_child(case_navigation)
	_previous_case_button = Button.new()
	_previous_case_button.name = "CasePreviousButton"
	_previous_case_button.text = "← 上一頁"
	_previous_case_button.custom_minimum_size = Vector2(122, 44)
	_previous_case_button.disabled = true
	_previous_case_button.pressed.connect(_select_previous_case)
	case_navigation.add_child(_previous_case_button)
	_case_selector = OptionButton.new()
	_case_selector.name = "CaseSelector"
	_case_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_case_selector.custom_minimum_size = Vector2(260, 44)
	_case_selector.disabled = true
	_case_selector.item_selected.connect(_on_case_selected)
	case_navigation.add_child(_case_selector)
	_case_page_label = _body("")
	_case_page_label.name = "CasePagerLabel"
	_case_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_case_page_label.custom_minimum_size = Vector2(120, 44)
	case_navigation.add_child(_case_page_label)
	_next_case_button = Button.new()
	_next_case_button.name = "CaseNextButton"
	_next_case_button.text = "下一頁 →"
	_next_case_button.custom_minimum_size = Vector2(122, 44)
	_next_case_button.disabled = true
	_next_case_button.pressed.connect(_select_next_case)
	case_navigation.add_child(_next_case_button)
	_case_title = _title("目前無待處理案件")
	_case_title.set_meta("l10n_skip", true)
	case_stack.add_child(_case_title)
	_case_detail = _body(str(_config()["empty_hint"]))
	_case_detail.set_meta("l10n_skip", true)
	case_stack.add_child(_case_detail)
	_defense_status = _body("案件成立後即可選擇辯護策略。")
	_defense_status.set_meta("l10n_skip", true)
	case_stack.add_child(_defense_status)
	var defense_row := HBoxContainer.new()
	defense_row.name = "DefenseActions"
	defense_row.add_theme_constant_override("separation", 12)
	case_stack.add_child(defense_row)
	for option_variant in _config()["defenses"]:
		var option: Dictionary = option_variant
		var button := Button.new()
		var option_id := str(option["id"])
		button.name = "%sDefenseButton" % option_id.to_pascal_case()
		button.text = str(option["label"])
		button.tooltip_text = str(option["detail"])
		button.set_meta("semantic_label", str(option["label"]))
		button.custom_minimum_size = Vector2(150, 50)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 18)
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
		_case_page_label.text = L10n.text("第 %d / %d 頁") % [0, 0]
		_previous_case_button.text = L10n.text("← 上一頁")
		_next_case_button.text = L10n.text("下一頁 →")
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
	_previous_case_button.text = L10n.text("← 上一頁")
	_next_case_button.text = L10n.text("下一頁 →")
	_case_page_label.text = L10n.text("第 %d / %d 頁") % [index + 1, _open_case_ids.size()]


func selected_case_id() -> String:
	return _selected_case_id


func select_case_by_id(case_id: String) -> bool:
	var index := _open_case_ids.find(case_id)
	if index < 0:
		return false
	_case_selector.select(index)
	_on_case_selected(index)
	return true


func _refresh_case() -> void:
	if _case_title == null:
		return
	var active_case := _active_case()
	if active_case.is_empty():
		_case_title.text = L10n.text("目前無待處理案件")
		_case_detail.text = L10n.text(str(_config()["empty_hint"]))
		_defense_status.text = L10n.text("案件成立後即可選擇辯護策略。")
		for button_variant in _defense_buttons.values():
			(button_variant as Button).disabled = true
			(button_variant as Button).text = L10n.text(str((button_variant as Button).get_meta("semantic_label", "辯護")))
		return

	var selected_id := str(active_case.get("defense_template_id", ""))
	if mode == MODE_JUDICIAL:
		_case_title.text = _localized_judicial_case_name(str(active_case.get("name", "行政違法審判")))
		_case_detail.text = L10n.text("第 %d 日裁決　｜　案件嚴重度 %d / 100") % [
			int(active_case.get("decision_day", 0)), int(active_case.get("base_severity", 0)),
		]
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
	if _system.has_method("is_terminal_locked") and bool(_system.is_terminal_locked()):
		var failure_reason := str(_system.terminal_failure_reason())
		_defense_status.text = L10n.text("遊戲失敗：%s") % L10n.text(str(FAILURE_REASON_LABELS.get(failure_reason, "狀態未知")))
		for button_variant in _defense_buttons.values():
			(button_variant as Button).disabled = true
		return
	_defense_status.text = L10n.text("尚未提出辯護") if selected_id.is_empty() else (L10n.text("已提出：%s") % L10n.text(_defense_label(selected_id)))
	for option_id: String in _defense_buttons:
		var button := _defense_buttons[option_id] as Button
		button.disabled = false
		var label := str(button.get_meta("semantic_label", option_id))
		var localized_label := L10n.text(label)
		button.text = "✓ %s" % localized_label if option_id == selected_id else localized_label


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
	style.bg_color = Color(0.08, 0.13, 0.17) if _dark_mode else Color(0.965, 0.91, 0.78)
	style.border_color = _config()["accent"] as Color
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	_case_panel.add_theme_stylebox_override("panel", style)


func _style_defense_button(button: Button, text_color: Color) -> void:
	if not is_instance_valid(button):
		return
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.22, 0.28) if _dark_mode else Color(1.0, 0.96, 0.86)
	normal.border_color = _config()["accent"] as Color
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(9)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.18, 0.33, 0.40) if _dark_mode else Color(1.0, 0.99, 0.93)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.07, 0.15, 0.19) if _dark_mode else Color(0.88, 0.80, 0.64)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.14, 0.18, 0.21) if _dark_mode else Color(0.78, 0.77, 0.71)
	disabled.border_color = Color(0.31, 0.39, 0.44) if _dark_mode else Color(0.55, 0.54, 0.49)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	button.add_theme_color_override("font_focus_color", text_color)
	button.add_theme_color_override("font_disabled_color", Color(0.67, 0.74, 0.78) if _dark_mode else Color(0.18, 0.22, 0.25))
