class_name CityMetricCard
extends PanelContainer

const UiIconCatalog = preload("res://ui/theme/ui_icon_catalog.gd")
const BenchmarkDeltaChartScript = preload("res://ui/components/benchmark_delta_chart.gd")

const STATUS_GOOD := "good"
const STATUS_ATTENTION := "attention"
const STATUS_CRITICAL := "critical"
const STATUS_NEUTRAL := "neutral"
const VALID_STATUSES := [STATUS_GOOD, STATUS_ATTENTION, STATUS_CRITICAL, STATUS_NEUTRAL]

const MINIMUM_CARD_SIZE := Vector2(300, 270)
const ICON_SIZE := Vector2(42, 42)

var icon_view: TextureRect
var metric_name_label: Label
var value_label: Label
var unit_label: Label
var delta_label: Label
var status_label: Label
var interpretation_label: Label
var action_hint_label: Label
var benchmark_chart

var _content_margin: MarginContainer
var _status_chip: PanelContainer
var _action_panel: PanelContainer
var _dark_mode := false
var _model: Dictionary = {}


func _init() -> void:
	name = "CityMetricCard"
	custom_minimum_size = MINIMUM_CARD_SIZE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_content()
	set_metric({})
	set_dark_mode(false)


## All strings are display-ready so the owner can inject its already-localized
## view model without this reusable component owning localization state.
##
## Supported keys:
## id, icon_key, label, value/value_text, unit, status, status_label,
## period_label, delta_available, delta/delta_text, delta_unit,
## interpretation/reason, action_hint, unavailable_text,
## delta_unavailable_text (an exact display-ready empty-history sentence).
func set_metric(data: Dictionary) -> void:
	_model = data.duplicate(true)
	var metric_id := str(_model.get("id", ""))
	set_meta("metric_id", metric_id)

	var icon_key := str(_model.get("icon_key", "city_data"))
	icon_view.texture = UiIconCatalog.texture(icon_key)
	icon_view.tooltip_text = str(_model.get("label", "城市指標"))

	metric_name_label.text = str(_model.get("label", "城市指標"))
	value_label.text = _value_text(_model)
	unit_label.text = str(_model.get("unit", ""))
	value_label.visible = false
	unit_label.visible = false

	var status := _normalized_status(str(_model.get("status", STATUS_NEUTRAL)))
	var status_visual := _status_visual(status)
	var custom_status_label := str(_model.get("status_label", "")).strip_edges()
	var shown_status_label := custom_status_label if not custom_status_label.is_empty() else str(status_visual["label"])
	status_label.text = "%s %s" % [status_visual["symbol"], shown_status_label]
	status_label.set_meta("status", status)

	var delta_result := _delta_text(_model)
	delta_label.text = str(delta_result["text"])
	delta_label.set_meta("delta_available", bool(delta_result["available"]))
	delta_label.tooltip_text = delta_label.text

	var numeric_value := float(_model.get("value", 0.0)) if _is_numeric(_model.get("value", 0.0)) else 0.0
	var chart_current_text := str(_model.get("chart_current_text", "%s %s" % [value_label.text, unit_label.text])).strip_edges()
	benchmark_chart.set_chart({
		"minimum": float(_model.get("chart_minimum", 0.0)),
		"maximum": float(_model.get("chart_maximum", 100.0)),
		"baseline": float(_model.get("baseline", 60.0)),
		"current": numeric_value,
		"good_above": bool(_model.get("good_above", true)),
		"current_text": chart_current_text,
		"difference_text": str(_model.get("comparison_text", "")),
		"minimum_text": str(_model.get("chart_minimum_text", "0")),
		"baseline_text": str(_model.get("baseline_text", "安全線 60")),
		"maximum_text": str(_model.get("chart_maximum_text", "100")),
		"tooltip": str(_model.get("chart_tooltip", chart_current_text)),
	}, bool(_model.get("animate_chart", true)))

	var supplied_interpretation_text := str(_model.get("interpretation_text", "")).strip_edges()
	var interpretation := str(_model.get("interpretation", _model.get("reason", ""))).strip_edges()
	if interpretation.is_empty():
		interpretation = "尚無可用的原因說明。"
	interpretation_label.text = supplied_interpretation_text if not supplied_interpretation_text.is_empty() else "解讀：%s" % interpretation
	interpretation_label.tooltip_text = interpretation_label.text

	var supplied_action_text := str(_model.get("action_text", "")).strip_edges()
	var action_hint := str(_model.get("action_hint", "")).strip_edges()
	if action_hint.is_empty():
		action_hint = "目前無改善建議。"
	action_hint_label.text = supplied_action_text if not supplied_action_text.is_empty() else "建議：%s" % action_hint
	action_hint_label.tooltip_text = action_hint_label.text

	tooltip_text = "%s｜%s%s｜%s｜%s" % [
		metric_name_label.text,
		value_label.text,
		(" " + unit_label.text) if unit_label.visible else "",
		delta_label.text,
		status_label.text,
	]
	_apply_palette()


## Convenience API for the current main view model. A summary is authoritative
## only when its explicit `available` flag is true and the requested key exists.
## This prevents default zeroes from being presented as measured history.
func set_metric_from_month_summary(
		config: Dictionary,
		current_value: Variant,
		last_month_summary: Dictionary,
		delta_key: String
) -> void:
	var data := config.duplicate(true)
	data["value"] = current_value
	var has_authoritative_delta := (
		bool(last_month_summary.get("available", false))
		and not delta_key.is_empty()
		and last_month_summary.has(delta_key)
		and _is_numeric(last_month_summary[delta_key])
	)
	data["delta_available"] = has_authoritative_delta
	if has_authoritative_delta:
		data["delta"] = last_month_summary[delta_key]
	else:
		data.erase("delta")
		data.erase("delta_text")
	set_metric(data)


func set_dark_mode(enabled: bool) -> void:
	_dark_mode = enabled
	set_meta("dark_mode", _dark_mode)
	_apply_palette()


func is_dark_mode() -> bool:
	return _dark_mode


func metric_data() -> Dictionary:
	return _model.duplicate(true)


func has_authoritative_delta() -> bool:
	return bool(delta_label.get_meta("delta_available", false))


func _build_content() -> void:
	_content_margin = MarginContainer.new()
	_content_margin.name = "ContentMargin"
	_content_margin.add_theme_constant_override("margin_left", 14)
	_content_margin.add_theme_constant_override("margin_top", 12)
	_content_margin.add_theme_constant_override("margin_right", 14)
	_content_margin.add_theme_constant_override("margin_bottom", 12)
	add_child(_content_margin)

	var copy := VBoxContainer.new()
	copy.name = "MetricContent"
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 4)
	_content_margin.add_child(copy)

	var heading := HBoxContainer.new()
	heading.name = "MetricHeading"
	heading.add_theme_constant_override("separation", 7)
	copy.add_child(heading)

	icon_view = TextureRect.new()
	icon_view.name = "MetricIcon"
	icon_view.custom_minimum_size = ICON_SIZE
	icon_view.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(icon_view)

	metric_name_label = Label.new()
	metric_name_label.name = "MetricName"
	metric_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metric_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	metric_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	metric_name_label.max_lines_visible = 2
	metric_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	metric_name_label.add_theme_font_size_override("font_size", 19)
	heading.add_child(metric_name_label)

	_status_chip = PanelContainer.new()
	_status_chip.name = "StatusChip"
	_status_chip.custom_minimum_size = Vector2(76, 30)
	_status_chip.size_flags_horizontal = Control.SIZE_SHRINK_END
	heading.add_child(_status_chip)

	status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 16)
	_status_chip.add_child(status_label)

	# These labels remain part of the component API and accessibility tooltip,
	# but the primary number is rendered inside the chart so the card does not
	# repeat the same cold value twice.
	value_label = Label.new()
	value_label.name = "CurrentValue"
	value_label.custom_minimum_size = Vector2(64, 34)
	value_label.add_theme_font_size_override("font_size", 27)
	value_label.visible = false
	copy.add_child(value_label)

	unit_label = Label.new()
	unit_label.name = "ValueUnit"
	unit_label.add_theme_font_size_override("font_size", 17)
	unit_label.visible = false
	copy.add_child(unit_label)

	benchmark_chart = BenchmarkDeltaChartScript.new()
	benchmark_chart.name = "SafetyBenchmarkChart"
	benchmark_chart.custom_minimum_size = Vector2(0, 124)
	copy.add_child(benchmark_chart)

	delta_label = Label.new()
	delta_label.name = "MonthDelta"
	delta_label.custom_minimum_size = Vector2(0, 26)
	delta_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	delta_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	delta_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	delta_label.add_theme_font_size_override("font_size", 16)
	copy.add_child(delta_label)

	interpretation_label = Label.new()
	interpretation_label.name = "Interpretation"
	interpretation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	interpretation_label.max_lines_visible = 2
	interpretation_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	interpretation_label.add_theme_font_size_override("font_size", 16)
	interpretation_label.visible = false
	copy.add_child(interpretation_label)

	_action_panel = PanelContainer.new()
	_action_panel.name = "ActionHintPanel"
	_action_panel.custom_minimum_size = Vector2(0, 36)
	copy.add_child(_action_panel)

	action_hint_label = Label.new()
	action_hint_label.name = "ActionHint"
	action_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_hint_label.max_lines_visible = 1
	action_hint_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	action_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	action_hint_label.add_theme_font_size_override("font_size", 16)
	_action_panel.add_child(action_hint_label)


func _value_text(data: Dictionary) -> String:
	if data.has("value_text"):
		var supplied := str(data["value_text"]).strip_edges()
		return supplied if not supplied.is_empty() else "—"
	if not data.has("value") or data["value"] == null:
		return "—"
	return str(data["value"])


func _delta_text(data: Dictionary) -> Dictionary:
	var period_label := str(data.get("period_label", "較上月")).strip_edges()
	if period_label.is_empty():
		period_label = "較上月"
	var unavailable_text := str(data.get("unavailable_text", "資料不足")).strip_edges()
	if unavailable_text.is_empty():
		unavailable_text = "資料不足"

	if not bool(data.get("delta_available", false)):
		var exact_unavailable := str(data.get("delta_unavailable_text", "")).strip_edges()
		if not exact_unavailable.is_empty():
			return {"available": false, "text": exact_unavailable}
		return {"available": false, "text": "%s：◇ %s" % [period_label, unavailable_text]}

	var supplied_delta_text := str(data.get("delta_text", "")).strip_edges()
	if not supplied_delta_text.is_empty():
		return {"available": true, "text": "%s：%s" % [period_label, supplied_delta_text]}
	if not data.has("delta") or not _is_numeric(data["delta"]):
		return {"available": false, "text": "%s：◇ %s" % [period_label, unavailable_text]}

	var delta := float(data["delta"])
	var decimals := clampi(int(data.get("delta_decimals", 0)), 0, 3)
	var magnitude := ("%.*f" % [decimals, absf(delta)]) if decimals > 0 else str(absi(roundi(delta)))
	var direction := "—"
	var sign := ""
	if delta > 0.0:
		direction = "▲"
		sign = "+"
	elif delta < 0.0:
		direction = "▼"
		sign = "−"
	var delta_unit := str(data.get("delta_unit", data.get("unit", ""))).strip_edges()
	var unit_suffix := (" " + delta_unit) if not delta_unit.is_empty() else ""
	return {
		"available": true,
		"text": "%s：%s %s%s%s" % [period_label, direction, sign, magnitude, unit_suffix],
	}


func _normalized_status(status: String) -> String:
	return status if status in VALID_STATUSES else STATUS_NEUTRAL


func _status_visual(status: String) -> Dictionary:
	match status:
		STATUS_GOOD:
			return {"symbol": "✓", "label": "良好"}
		STATUS_ATTENTION:
			return {"symbol": "!", "label": "留意"}
		STATUS_CRITICAL:
			return {"symbol": "×", "label": "危急"}
		_:
			return {"symbol": "•", "label": "一般"}


func _status_palette(status: String) -> Dictionary:
	if _dark_mode:
		match status:
			STATUS_GOOD:
				return {"foreground": Color("8be0be"), "background": Color("174638"), "border": Color("4fae88")}
			STATUS_ATTENTION:
				return {"foreground": Color("ffd27a"), "background": Color("4a3815"), "border": Color("b88624")}
			STATUS_CRITICAL:
				return {"foreground": Color("ffad9f"), "background": Color("522820"), "border": Color("c65b49")}
			_:
				return {"foreground": Color("bbd4e5"), "background": Color("233845"), "border": Color("66879a")}
	match status:
		STATUS_GOOD:
			return {"foreground": Color("0b5d46"), "background": Color("d9f2e7"), "border": Color("4c987d")}
		STATUS_ATTENTION:
			return {"foreground": Color("704800"), "background": Color("fff0c7"), "border": Color("bd8a20")}
		STATUS_CRITICAL:
			return {"foreground": Color("8c2419"), "background": Color("ffe2dc"), "border": Color("c85d4d")}
		_:
			return {"foreground": Color("284b63"), "background": Color("e1edf4"), "border": Color("6b8798")}


func _apply_palette() -> void:
	if not is_instance_valid(status_label):
		return
	var status := str(status_label.get_meta("status", STATUS_NEUTRAL))
	var status_colors := _status_palette(status)

	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color("172732") if _dark_mode else Color("fff9ea")
	card_style.border_color = Color("658296") if _dark_mode else Color("9b754a")
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(14)
	card_style.shadow_color = Color(0, 0, 0, 0.24 if _dark_mode else 0.14)
	card_style.shadow_size = 4
	add_theme_stylebox_override("panel", card_style)

	var text_color := Color("f2f5f7") if _dark_mode else Color("14202a")
	var muted_color := Color("c1ccd4") if _dark_mode else Color("45535e")
	metric_name_label.add_theme_color_override("font_color", text_color)
	value_label.add_theme_color_override("font_color", text_color)
	unit_label.add_theme_color_override("font_color", muted_color)
	delta_label.add_theme_color_override("font_color", muted_color)
	interpretation_label.add_theme_color_override("font_color", text_color)
	action_hint_label.add_theme_color_override("font_color", text_color)
	benchmark_chart.set_dark_mode(_dark_mode)

	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = status_colors["background"]
	chip_style.border_color = status_colors["border"]
	chip_style.set_border_width_all(1)
	chip_style.set_corner_radius_all(17)
	chip_style.content_margin_left = 12
	chip_style.content_margin_right = 12
	_status_chip.add_theme_stylebox_override("panel", chip_style)
	status_label.add_theme_color_override("font_color", status_colors["foreground"])

	var action_style := StyleBoxFlat.new()
	action_style.bg_color = Color("20352f") if _dark_mode else Color("edf4ee")
	action_style.border_color = Color("6f9b87") if _dark_mode else Color("79a58c")
	action_style.set_border_width_all(0)
	action_style.border_width_left = 4
	action_style.set_corner_radius_all(8)
	action_style.content_margin_left = 10
	action_style.content_margin_top = 6
	action_style.content_margin_right = 10
	action_style.content_margin_bottom = 6
	_action_panel.add_theme_stylebox_override("panel", action_style)


func _is_numeric(value: Variant) -> bool:
	return value is int or value is float
