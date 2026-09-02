class_name CityDataDashboard
extends TabContainer

const BenchmarkDeltaChartScript = preload("res://ui/components/benchmark_delta_chart.gd")
const UiIconCatalog = preload("res://ui/theme/ui_icon_catalog.gd")

const COLOR_TEXT := Color(0.07, 0.12, 0.18)
const COLOR_MUTED := Color(0.24, 0.31, 0.38)
const COLOR_ACCENT := Color(0.05, 0.43, 0.70)
const COLOR_ACCENT_DARK := Color(0.03, 0.31, 0.52)
const COLOR_SUCCESS := Color(0.05, 0.42, 0.23)
const COLOR_WARNING := Color(0.77, 0.18, 0.08)
const COLOR_CAUTION := Color(0.82, 0.55, 0.05)
const COLOR_INFO := Color(0.05, 0.43, 0.70)
const COLOR_GOLD := Color(0.95, 0.72, 0.16)
const UI_MIN_FONT_SIZE := 19
const UI_CONTROL_FONT_SIZE := 21

var labels: Dictionary = {}
var finance_bars: Dictionary = {}
var group_bars: Dictionary = {}
var benchmark_charts: Dictionary = {}
var monthly_data_kpi_charts: Dictionary = {}
var monthly_data_service_charts: Dictionary = {}

var _dark_mode := false
var _viewport_width := 1920.0
var _metric_specs: Array[Dictionary] = []
var _resident_group_names: Array[String] = []


func configure(config: Dictionary) -> void:
	_dark_mode = bool(config.get("dark_mode", false))
	_viewport_width = maxf(1.0, float(config.get("viewport_width", 1920.0)))
	_metric_specs.clear()
	var metric_specs_variant: Variant = config.get("metric_specs", [])
	if metric_specs_variant is Array:
		for spec_variant in metric_specs_variant:
			if spec_variant is Dictionary:
				_metric_specs.append((spec_variant as Dictionary).duplicate(true))
	_resident_group_names.clear()
	var group_names_variant: Variant = config.get("resident_group_names", [])
	if group_names_variant is Array:
		for group_name_variant in group_names_variant:
			_resident_group_names.append(str(group_name_variant))
	_build_dashboard()


func refresh(snapshot: Dictionary) -> void:
	# Treat caller-owned authority data as immutable. All presentation work uses a
	# deep copy, so nested history, metrics, groups, and finance data stay intact.
	var data: Dictionary = snapshot.duplicate(true)
	var monthly_history := _monthly_history_value(data)
	var history_includes_current := bool(data.get("history_includes_current", false))
	var current_period_index := _resolved_current_period_index(data, monthly_history, history_includes_current)
	var comparison_history := _history_before_current_period(
		monthly_history,
		history_includes_current,
		current_period_index
	)
	var history_previous_month := _previous_history_snapshot(comparison_history, current_period_index)
	var previous_month: Dictionary = history_previous_month
	if previous_month.is_empty() and not history_includes_current:
		previous_month = _dictionary_value(data, "previous_month")
	var metrics: Dictionary = _dictionary_value(data, "metrics")
	var resident_groups: Dictionary = _dictionary_value(data, "resident_groups")
	var finance: Dictionary = _dictionary_value(data, "finance")
	var has_previous_month := not history_previous_month.is_empty() or bool(data.get("has_previous_month", false))
	if history_includes_current:
		has_previous_month = not history_previous_month.is_empty()

	_update_monthly_data_charts(data, previous_month, metrics, finance, comparison_history, has_previous_month, current_period_index)
	for group_name in _resident_group_names:
		_update_group_visual(group_name, int(resident_groups.get(group_name, 0)))
	_update_finance_rows(finance)


func restart_animations() -> void:
	for registry in [benchmark_charts, monthly_data_kpi_charts, monthly_data_service_charts]:
		for chart_variant in registry.values():
			if is_instance_valid(chart_variant) and chart_variant.has_method("restart_animation"):
				chart_variant.restart_animation()


func _build_dashboard() -> void:
	name = "城市數據"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_alignment = TabBar.ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 18)
	_style_tabs()

	var overview_scroll := ScrollContainer.new()
	overview_scroll.name = "月度總覽"
	overview_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	overview_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	overview_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(overview_scroll)
	var overview_page := MarginContainer.new()
	overview_page.name = "MonthlyDataOverviewMargin"
	overview_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview_page.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	overview_scroll.add_child(overview_page)
	var overview_stack := VBoxContainer.new()
	overview_stack.name = "MonthlyDataOverviewStack"
	overview_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview_stack.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	overview_stack.add_theme_constant_override("separation", 12)
	overview_page.add_child(overview_stack)
	var overview_panel := _panel(_theme_panel_alt(), 10, 16)
	var overview_header := VBoxContainer.new()
	overview_header.add_theme_constant_override("separation", 7)
	overview_panel.add_child(overview_header)
	overview_header.add_child(_illustrated_section_title("city_data", "九項月度數據"))
	var overview_intro := _label(
		"第一個月與安全線比較；第二個月起與上月比較。紅色安全線警告永遠保留。",
		16,
		_theme_muted()
	)
	overview_intro.name = "MonthlyDataComparisonRule"
	overview_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overview_intro.custom_minimum_size = Vector2(0, 36)
	overview_header.add_child(overview_intro)
	overview_stack.add_child(overview_panel)
	var overview_grid := GridContainer.new()
	overview_grid.name = "MonthlyDataChartGrid"
	overview_grid.columns = 3 if _viewport_width >= 1800.0 else 2
	overview_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview_grid.add_theme_constant_override("h_separation", 10)
	overview_grid.add_theme_constant_override("v_separation", 10)
	overview_grid.add_child(_monthly_data_kpi_card("net", "treasury", "收支覆蓋率"))
	overview_grid.add_child(_monthly_data_kpi_card("population", "population", "人口月增率"))
	overview_grid.add_child(_monthly_data_kpi_card("satisfaction", "wellbeing", "居民滿意"))
	overview_grid.add_child(_monthly_data_kpi_card("score", "score", "評分"))
	for metric_spec in _metric_specs:
		overview_grid.add_child(_monthly_data_service_card(metric_spec))
	overview_stack.add_child(overview_grid)

	var satisfaction_scroll := ScrollContainer.new()
	satisfaction_scroll.name = "居民滿意"
	satisfaction_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	satisfaction_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	satisfaction_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	satisfaction_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(satisfaction_scroll)
	var satisfaction_page := MarginContainer.new()
	satisfaction_page.name = "ResidentSatisfactionMargin"
	satisfaction_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	satisfaction_page.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	satisfaction_scroll.add_child(satisfaction_page)
	var satisfaction_panel := _panel(_theme_panel_alt(), 10, 18)
	satisfaction_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	satisfaction_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var satisfaction_box := VBoxContainer.new()
	satisfaction_box.add_theme_constant_override("separation", 14)
	satisfaction_panel.add_child(satisfaction_box)
	satisfaction_box.add_child(_illustrated_section_title("population", "居民滿意"))
	for group_name in _resident_group_names:
		satisfaction_box.add_child(_group_score_row(group_name))
	satisfaction_page.add_child(satisfaction_panel)

	var finance_scroll := ScrollContainer.new()
	finance_scroll.name = "即時財政"
	finance_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	finance_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	finance_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	finance_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(finance_scroll)
	var finance_page := MarginContainer.new()
	finance_page.name = "CityFinanceMargin"
	finance_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	finance_page.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	finance_scroll.add_child(finance_page)
	var finance_panel := _panel(_theme_panel_alt(), 10, 18)
	finance_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	finance_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var finance_box := VBoxContainer.new()
	finance_box.add_theme_constant_override("separation", 14)
	finance_panel.add_child(finance_box)
	finance_box.add_child(_illustrated_section_title("funds", "即時財政"))
	var finance_intro := _label("先看收入能覆蓋多少支出；金額明細放在下方供需要時查閱。", 15, _theme_muted())
	finance_intro.name = "CityFinanceIntro"
	_set_localized_tooltip(finance_intro, "圖上的金色直線是 100% 收支安全線。")
	finance_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	finance_intro.custom_minimum_size = Vector2(0, 34)
	finance_box.add_child(finance_intro)
	var finance_coverage_chart = BenchmarkDeltaChartScript.new()
	finance_coverage_chart.name = "CityFinanceCoverageChart"
	finance_coverage_chart.custom_minimum_size = Vector2(0, 118)
	finance_coverage_chart.set_dark_mode(_dark_mode)
	benchmark_charts["finance_coverage"] = finance_coverage_chart
	finance_box.add_child(finance_coverage_chart)
	finance_box.add_child(_finance_visual_row("right_tax_income", "總稅收"))
	finance_box.add_child(_finance_visual_row("right_business_income", "商業設施"))
	finance_box.add_child(_finance_visual_row("right_industrial_income", "工業設施"))
	finance_box.add_child(_finance_visual_row("right_utility_income", "公共事業"))
	finance_box.add_child(_finance_visual_row("right_service_income", "交通與服務"))
	finance_box.add_child(_finance_visual_row("right_net_income", "預估淨收支"))
	var note := _label("調整稅費：市政 → 稅率與公共事業費", 15, COLOR_WARNING)
	note.name = "CityFinanceNavigationNote"
	_set_localized_tooltip(note, "關閉此頁後，進入市政中心的稅率與公共事業費頁。")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(0, 40)
	finance_box.add_child(note)
	finance_page.add_child(finance_panel)

	refresh_localization()


func refresh_localization() -> void:
	if get_tab_count() < 3:
		return
	var sources := ["月度總覽", "居民滿意", "即時財政"]
	var translations: Array[String] = []
	for index in sources.size():
		var translated := L10n.text(sources[index])
		set_tab_title(index, translated)
		translations.append(translated)
	set_meta("l10n_tab_sources", sources)
	set_meta("l10n_tab_last", translations)


func _monthly_data_kpi_card(card_key: String, icon_key: String, title_text: String) -> PanelContainer:
	var card := _panel(_theme_panel_alt(), 10, 14)
	card.name = "MonthlyDataKpi_%s" % card_key
	card.custom_minimum_size = Vector2(0, 252)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	card.add_child(stack)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.add_child(_icon_texture_rect(icon_key, Vector2(42, 42)))
	var title := _label(title_text, 15, _theme_muted())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(title)
	stack.add_child(header)
	var value := _label("—", 23, _theme_text())
	value.name = "MonthlyDataKpiValue_%s" % card_key
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	value.clip_text = true
	labels["monthly_data_kpi_%s_value" % card_key] = value
	value.visible = false
	stack.add_child(value)
	var detail := _label("", 13, _theme_muted())
	detail.name = "MonthlyDataKpiDetail_%s" % card_key
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail.clip_text = true
	labels["monthly_data_kpi_%s_detail" % card_key] = detail
	stack.add_child(detail)
	var chart = BenchmarkDeltaChartScript.new()
	chart.name = "MonthlyDataKpiChart_%s" % card_key
	chart.set_dark_mode(_dark_mode)
	monthly_data_kpi_charts[card_key] = chart
	stack.add_child(chart)
	return card


func _monthly_data_service_card(spec: Dictionary) -> PanelContainer:
	var metric_id := str(spec["id"])
	var card := _panel(_theme_panel(), 9, 10)
	card.name = "MonthlyDataService_%s" % metric_id
	card.custom_minimum_size = Vector2(0, 220)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 3)
	card.add_child(stack)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 5)
	heading.add_child(_icon_texture_rect(str(spec["icon_key"]), Vector2(30, 30)))
	var title := _label(str(spec["label"]), 14, _theme_muted())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	stack.add_child(heading)
	var value := _label("—", 18, _theme_text())
	value.name = "MonthlyDataServiceValue_%s" % metric_id
	labels["monthly_data_service_%s_value" % metric_id] = value
	value.visible = false
	stack.add_child(value)
	var delta := _label("Δ —", 12, _theme_muted())
	delta.name = "MonthlyDataServiceDelta_%s" % metric_id
	labels["monthly_data_service_%s_delta" % metric_id] = delta
	delta.visible = false
	stack.add_child(delta)
	var chart = BenchmarkDeltaChartScript.new()
	chart.name = "MonthlyDataServiceChart_%s" % metric_id
	chart.set_dark_mode(_dark_mode)
	monthly_data_service_charts[metric_id] = chart
	stack.add_child(chart)
	return card


func _group_score_row(group_name: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "ResidentBenchmark_%s" % group_name
	box.add_theme_constant_override("separation", 3)
	var row := HBoxContainer.new()
	var title := _label(group_name, 16, _theme_text())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var value := _label("", 17, _theme_accent_text())
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.custom_minimum_size = Vector2(124, 0)
	labels["group_%s" % group_name] = value
	row.add_child(value)
	box.add_child(row)
	var chart = BenchmarkDeltaChartScript.new()
	chart.name = "ResidentSafetyChart_%s" % group_name
	chart.custom_minimum_size = Vector2(0, 104)
	chart.set_dark_mode(_dark_mode)
	group_bars[group_name] = chart
	benchmark_charts["resident_%s" % group_name] = chart
	box.add_child(chart)
	return box


func _finance_visual_row(label_key: String, title_text: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new()
	var name_label := _label(title_text, 16, _theme_text())
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.max_lines_visible = 2
	row.add_child(name_label)
	var value := _label("", 18, _theme_accent_text())
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.custom_minimum_size = Vector2(108, 0)
	value.clip_text = true
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	labels[label_key] = value
	row.add_child(value)
	box.add_child(row)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	_style_progress_bar(bar)
	finance_bars[label_key] = bar
	box.add_child(bar)
	return box


func _update_monthly_data_charts(
		data: Dictionary,
		previous_month: Dictionary,
		metrics: Dictionary,
		finance: Dictionary,
		monthly_history: Array,
		has_previous_month: bool,
		current_period_index: int
) -> void:
	var total_income := int(finance.get("total_income", 0))
	var total_expense := int(finance.get("total_expense", 0))
	var net_income := int(finance.get("net_income", total_income - total_expense))
	var coverage_rate := _coverage_rate(total_income, total_expense)
	var coverage_baseline := float(previous_month.get("coverage_rate", 100.0))
	var coverage_max := maxf(150.0, ceil(coverage_rate / 25.0) * 25.0)
	coverage_max = maxf(coverage_max, ceil(coverage_baseline / 25.0) * 25.0)
	_set_monthly_data_kpi(
		"net",
		"%.0f%%" % coverage_rate,
		"↑ %s  ·  ↓ %s" % [_format_currency(total_income), _format_currency(total_expense)],
		COLOR_SUCCESS if net_income >= 0 else COLOR_WARNING
	)
	var coverage_warning := _monthly_warning_state(coverage_rate, 100.0, "coverage_rate", monthly_history, current_period_index)
	_set_monthly_data_chart(
		"net", coverage_rate, coverage_baseline, 100.0, 0.0, coverage_max,
		L10n.text("收入覆蓋支出 %.0f%%") % coverage_rate,
		_report_baseline_text(coverage_baseline, 100.0, "收支安全線", 0, has_previous_month),
		_report_comparison_text(coverage_rate, coverage_baseline, "收支安全線", 0, has_previous_month),
		str(coverage_warning["text"]), str(coverage_warning["severity"]),
		"0%", "%.0f%%" % coverage_max
	)

	var population := int(data.get("population", 1))
	var month_start_population := maxi(1, int(data.get("month_start_population", population)))
	var population_delta := population - month_start_population
	var population_rate := float(population_delta) / float(month_start_population) * 100.0
	var population_baseline := float(previous_month.get("population_rate", 0.0))
	var population_range := maxf(5.0, ceil(maxf(absf(population_rate), absf(population_baseline)) / 5.0) * 5.0)
	_set_monthly_data_kpi(
		"population",
		"%+.1f%%" % population_rate,
		L10n.text("目前人口 %s 人") % _format_grouped_int(population),
		COLOR_INFO if population_rate >= 0.0 else COLOR_WARNING
	)
	var population_warning := _monthly_warning_state(population_rate, 0.0, "population_rate", monthly_history, current_period_index)
	_set_monthly_data_chart(
		"population", population_rate, population_baseline, 0.0, -population_range, population_range,
		L10n.text("本月人口 %+.1f%%") % population_rate,
		_report_baseline_text(population_baseline, 0.0, "零成長線", 1, has_previous_month),
		_report_comparison_text(population_rate, population_baseline, "零成長線", 1, has_previous_month),
		str(population_warning["text"]), str(population_warning["severity"]),
		"−%.0f%%" % population_range, "+%.0f%%" % population_range
	)

	var satisfaction := clampi(int(data.get("satisfaction", 0)), 0, 100)
	var satisfaction_baseline := float(previous_month.get("satisfaction", 60.0))
	_set_monthly_data_kpi(
		"satisfaction", "%d%%" % satisfaction, L10n.text(_score_state(satisfaction)), _score_color(satisfaction)
	)
	var satisfaction_warning := _monthly_warning_state(float(satisfaction), 60.0, "satisfaction", monthly_history, current_period_index)
	_set_monthly_data_chart(
		"satisfaction", float(satisfaction), satisfaction_baseline, 60.0, 0.0, 100.0,
		L10n.text("居民滿意 %d%%") % satisfaction,
		_report_baseline_text(satisfaction_baseline, 60.0, "安全線", 0, has_previous_month),
		_report_comparison_text(float(satisfaction), satisfaction_baseline, "安全線", 0, has_previous_month),
		str(satisfaction_warning["text"]), str(satisfaction_warning["severity"]),
		"0%", "100%"
	)

	var score := clampi(int(data.get("score", 0)), 0, 100)
	var score_baseline := float(previous_month.get("score", 60.0))
	_set_monthly_data_kpi("score", "%d%%" % score, L10n.text(str(data.get("rating", ""))), COLOR_GOLD)
	var score_warning := _monthly_warning_state(float(score), 60.0, "score", monthly_history, current_period_index)
	_set_monthly_data_chart(
		"score", float(score), score_baseline, 60.0, 0.0, 100.0,
		L10n.text("城市評分 %d%%") % score,
		_report_baseline_text(score_baseline, 60.0, "安全線", 0, has_previous_month),
		_report_comparison_text(float(score), score_baseline, "安全線", 0, has_previous_month),
		str(score_warning["text"]), str(score_warning["severity"]),
		"0%", "100%"
	)

	_update_monthly_data_service_charts(metrics, previous_month, monthly_history, has_previous_month, current_period_index)
	_update_finance_coverage_chart(total_income, total_expense)


func _update_monthly_data_service_charts(
		metrics: Dictionary,
		previous_month: Dictionary,
		monthly_history: Array,
		has_previous_month: bool,
		current_period_index: int
) -> void:
	for spec in _metric_specs:
		var metric_id := str(spec["id"])
		var value := clampi(int(metrics.get(metric_id, 0)), 0, 100)
		var value_key := "monthly_data_service_%s_value" % metric_id
		var delta_label_key := "monthly_data_service_%s_delta" % metric_id
		if labels.has(value_key):
			labels[value_key].text = "%d%%" % value
			labels[value_key].add_theme_color_override("font_color", _score_color(value))
		var baseline := float(previous_month.get(metric_id, 60.0))
		var warning := _monthly_warning_state(float(value), 60.0, metric_id, monthly_history, current_period_index)
		var delta_text := _report_comparison_text(float(value), baseline, "安全線", 0, has_previous_month)
		if labels.has(delta_label_key):
			labels[delta_label_key].text = delta_text
			labels[delta_label_key].tooltip_text = labels[delta_label_key].text
		if monthly_data_service_charts.has(metric_id):
			monthly_data_service_charts[metric_id].set_chart({
				"current": float(value),
				"baseline": baseline,
				"safety": 60.0,
				"minimum": 0.0,
				"maximum": 100.0,
				"current_text": "%s %d%%" % [L10n.text(str(spec["label"])), value],
				"difference_text": delta_text,
				"safety_warning_text": str(warning["text"]),
				"safety_warning_severity": str(warning["severity"]),
				"minimum_text": "0%",
				"baseline_text": _report_baseline_text(baseline, 60.0, "安全線", 0, has_previous_month),
				"maximum_text": "100%",
				"tooltip": delta_text,
			}, true)


func _set_monthly_data_kpi(card_key: String, value_text: String, detail_text: String, color: Color) -> void:
	var value_key := "monthly_data_kpi_%s_value" % card_key
	var detail_key := "monthly_data_kpi_%s_detail" % card_key
	if labels.has(value_key):
		labels[value_key].text = value_text
		labels[value_key].tooltip_text = "%s · %s" % [value_text, detail_text]
		labels[value_key].add_theme_color_override("font_color", color)
	if labels.has(detail_key):
		labels[detail_key].text = detail_text
		labels[detail_key].tooltip_text = detail_text


func _set_monthly_data_chart(
		card_key: String,
		current: float,
		baseline: float,
		safety: float,
		minimum: float,
		maximum: float,
		current_text: String,
		baseline_text: String,
		difference_text: String,
		safety_warning_text: String,
		safety_warning_severity: String,
		minimum_text: String,
		maximum_text: String
) -> void:
	if not monthly_data_kpi_charts.has(card_key):
		return
	monthly_data_kpi_charts[card_key].set_chart({
		"current": current,
		"baseline": baseline,
		"safety": safety,
		"minimum": minimum,
		"maximum": maximum,
		"current_text": current_text,
		"baseline_text": baseline_text,
		"difference_text": difference_text,
		"safety_warning_text": safety_warning_text,
		"safety_warning_severity": safety_warning_severity,
		"minimum_text": minimum_text,
		"maximum_text": maximum_text,
		"tooltip": "%s｜%s" % [current_text, difference_text],
	}, true)


func _update_group_visual(group_name: String, value: int) -> void:
	var color := _score_color(value)
	var label_key := "group_%s" % group_name
	if labels.has(label_key):
		labels[label_key].text = "● %s" % L10n.text(_score_state(value))
		labels[label_key].add_theme_color_override("font_color", color)
	if group_bars.has(group_name):
		var gap_text := _benchmark_gap_text(float(value), 60.0)
		group_bars[group_name].set_chart({
			"current": float(value),
			"baseline": 60.0,
			"minimum": 0.0,
			"maximum": 100.0,
			"current_text": L10n.text("目前 %d%%") % value,
			"difference_text": gap_text,
			"minimum_text": "0%",
			"baseline_text": L10n.text("安全線 60%"),
			"maximum_text": "100%",
			"tooltip": gap_text,
		}, true)


func _update_finance_rows(finance: Dictionary) -> void:
	var total_income := int(finance.get("total_income", 0))
	var total_expense := int(finance.get("total_expense", 0))
	var net_income := int(finance.get("net_income", total_income - total_expense))
	var income_scale := maxi(1, total_income)
	_update_finance_visual("right_tax_income", int(finance.get("tax_income", 0)), income_scale, COLOR_SUCCESS)
	_update_finance_visual("right_business_income", int(finance.get("business_income", 0)), income_scale, Color(0.10, 0.55, 0.72))
	_update_finance_visual("right_industrial_income", int(finance.get("industrial_income", 0)), income_scale, Color(0.45, 0.42, 0.72))
	_update_finance_visual("right_utility_income", int(finance.get("utility_income", 0)), income_scale, Color(0.14, 0.60, 0.52))
	_update_finance_visual("right_service_income", int(finance.get("service_income", 0)), income_scale, Color(0.25, 0.60, 0.76))
	_update_finance_visual("right_net_income", net_income, income_scale, COLOR_SUCCESS if net_income >= 0 else COLOR_WARNING, true)


func _update_finance_visual(label_key: String, amount: int, scale: int, color: Color, signed_value: bool = false) -> void:
	if labels.has(label_key):
		labels[label_key].text = "%s$%d" % ["+" if amount >= 0 else "-", absi(amount)] if signed_value else "$%d" % amount
		labels[label_key].add_theme_color_override("font_color", color)
	if finance_bars.has(label_key):
		var ratio := absf(float(amount)) / maxf(1.0, float(scale)) * 100.0
		_set_bar_visual(finance_bars[label_key], ratio, color)


func _update_finance_coverage_chart(total_income: int, total_expense: int) -> void:
	if not benchmark_charts.has("finance_coverage"):
		return
	var coverage_rate := _coverage_rate(total_income, total_expense)
	var maximum := maxf(150.0, ceil(coverage_rate / 25.0) * 25.0)
	var gap_text := _benchmark_gap_text(coverage_rate, 100.0, "收支安全線", 0)
	benchmark_charts["finance_coverage"].set_chart({
		"current": coverage_rate,
		"baseline": 100.0,
		"minimum": 0.0,
		"maximum": maximum,
		"current_text": L10n.text("收入覆蓋支出 %.0f%%") % coverage_rate,
		"difference_text": gap_text,
		"minimum_text": "0%",
		"baseline_text": L10n.text("收支安全線 100%"),
		"maximum_text": "%.0f%%" % maximum,
		"tooltip": "%s｜%s" % [gap_text, L10n.text("收入 %s、支出 %s") % [_format_currency(total_income), _format_currency(total_expense)]],
	}, true)


func _coverage_rate(total_income: int, total_expense: int) -> float:
	if total_expense > 0:
		return float(total_income) / float(total_expense) * 100.0
	return 100.0 if total_income > 0 else 0.0


func _report_percentage_number(value: float, decimals: int) -> String:
	return ("%.*f" % [decimals, value]) if decimals > 0 else str(roundi(value))


func _report_baseline_text(
		previous_value: float,
		safety_value: float,
		safety_name: String,
		decimals: int,
		has_previous_month: bool
) -> String:
	if has_previous_month:
		return L10n.text("上月 %s%%") % _report_percentage_number(previous_value, decimals)
	return L10n.text("%s %s%%") % [L10n.text(safety_name), _report_percentage_number(safety_value, decimals)]


func _report_comparison_text(
		current: float,
		baseline: float,
		safety_name: String,
		decimals: int,
		has_previous_month: bool
) -> String:
	if not has_previous_month:
		return _benchmark_gap_text(current, baseline, safety_name, decimals)
	var difference := current - baseline
	if absf(difference) < pow(10.0, -float(decimals)) * 0.5:
		return L10n.text("與上月相同")
	var magnitude := _report_percentage_number(absf(difference), decimals)
	if difference > 0.0:
		return L10n.text("較上月高 +%s 個百分點") % magnitude
	return L10n.text("較上月低 −%s 個百分點") % magnitude


func _report_safety_warning_text(current: float, safety: float, safety_name: String, decimals: int) -> String:
	if current >= safety:
		return ""
	var magnitude := _report_percentage_number(absf(current - safety), decimals)
	return L10n.text("⚠ 安全線警告：低於%s −%s 個百分點") % [L10n.text(safety_name), magnitude]


func _monthly_history_value(data: Dictionary) -> Array:
	var history_variant: Variant = data.get("monthly_report_history", [])
	return history_variant.duplicate(true) if history_variant is Array else []


func _latest_history_snapshot(monthly_history: Array) -> Dictionary:
	if monthly_history.is_empty():
		return {}
	var candidate: Variant = monthly_history[monthly_history.size() - 1]
	return candidate.duplicate(true) if candidate is Dictionary else {}


func _resolved_current_period_index(data: Dictionary, monthly_history: Array, history_includes_current: bool) -> int:
	var explicit_period := int(data.get("current_period_index", 0))
	if explicit_period > 0:
		return explicit_period
	var latest := _latest_history_snapshot(monthly_history)
	var latest_period := int(latest.get("period_index", 0))
	if latest_period <= 0:
		return 0
	return latest_period if history_includes_current else latest_period + 1


func _history_before_current_period(monthly_history: Array, history_includes_current: bool, current_period_index: int) -> Array:
	var comparison_history: Array = []
	for index in monthly_history.size():
		var snapshot_variant: Variant = monthly_history[index]
		if not snapshot_variant is Dictionary:
			continue
		var snapshot: Dictionary = (snapshot_variant as Dictionary).duplicate(true)
		var period_index := int(snapshot.get("period_index", 0))
		var is_current := false
		if history_includes_current:
			is_current = (
				period_index >= current_period_index
				if current_period_index > 0 and period_index > 0
				else index == monthly_history.size() - 1
			)
		if not is_current:
			comparison_history.append(snapshot)
	return comparison_history


func _previous_history_snapshot(comparison_history: Array, current_period_index: int) -> Dictionary:
	var previous := _latest_history_snapshot(comparison_history)
	if previous.is_empty() or current_period_index <= 0:
		return previous
	var previous_period := int(previous.get("period_index", 0))
	if previous_period > 0 and previous_period != current_period_index - 1:
		return {}
	return previous


func _monthly_warning_state(current: float, safety: float, metric_key: String, monthly_history: Array, current_period_index: int = 0) -> Dictionary:
	if current >= safety:
		return {"text": "", "severity": "", "streak": 0}
	var streak := 1
	var expected_period := current_period_index - 1 if current_period_index > 0 else 0
	for index in range(monthly_history.size() - 1, -1, -1):
		var snapshot_variant: Variant = monthly_history[index]
		if not snapshot_variant is Dictionary:
			break
		var snapshot := snapshot_variant as Dictionary
		var snapshot_period := int(snapshot.get("period_index", 0))
		if expected_period > 0 and snapshot_period > 0 and snapshot_period != expected_period:
			break
		if float(snapshot.get(metric_key, safety)) >= safety:
			break
		streak += 1
		if expected_period > 0:
			expected_period = snapshot_period - 1 if snapshot_period > 0 else expected_period - 1
	var severity := "critical" if streak >= 3 else "caution"
	return {
		"text": "%s（連續 %d 月）" % [_report_safety_warning_text(current, safety, "安全線", 0), streak],
		"severity": severity,
		"streak": streak,
	}


func _benchmark_gap_text(current: float, baseline: float, baseline_name: String = "安全線", decimals: int = 0) -> String:
	var difference := current - baseline
	var localized_baseline := L10n.text(baseline_name)
	if absf(difference) < pow(10.0, -float(decimals)) * 0.5:
		return L10n.text("恰好位於%s") % localized_baseline
	var magnitude := ("%.*f" % [decimals, absf(difference)]) if decimals > 0 else str(roundi(absf(difference)))
	if difference > 0.0:
		return L10n.text("高於%s +%s 個百分點") % [localized_baseline, magnitude]
	return L10n.text("低於%s −%s 個百分點") % [localized_baseline, magnitude]


func _score_state(value: int) -> String:
	if value >= 75:
		return "良好"
	if value >= 50:
		return "留意"
	return "危險"


func _score_color(value: int) -> Color:
	if value >= 75:
		return COLOR_SUCCESS
	if value >= 50:
		return COLOR_CAUTION
	return COLOR_WARNING


func _dictionary_value(source: Dictionary, key: String) -> Dictionary:
	var value: Variant = source.get(key, {})
	return value if value is Dictionary else {}


func _format_grouped_int(value: int) -> String:
	var digits := str(absi(value))
	var grouped := ""
	while digits.length() > 3:
		var split_at := digits.length() - 3
		grouped = ",%s%s" % [digits.substr(split_at, 3), grouped]
		digits = digits.substr(0, split_at)
	return "%s%s%s" % ["-" if value < 0 else "", digits, grouped]


func _format_currency(value: int) -> String:
	return "$%s" % _format_grouped_int(value)


func _panel(color: Color, radius: int, padding: int = 14) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(2)
	style.border_color = _theme_border()
	style.shadow_color = Color(0, 0, 0, 0.16)
	style.shadow_size = 3
	panel.add_theme_stylebox_override("panel", style)
	panel.add_theme_constant_override("margin_left", padding)
	panel.add_theme_constant_override("margin_top", padding)
	panel.add_theme_constant_override("margin_right", padding)
	panel.add_theme_constant_override("margin_bottom", padding)
	return panel


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	var translated := L10n.text(text)
	label.text = translated
	label.set_meta("l10n_source_text", text)
	label.set_meta("l10n_last_text", translated)
	label.add_theme_font_size_override("font_size", _readable_font_size(size))
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _set_localized_tooltip(control: Control, source: String) -> void:
	var translated := L10n.text(source)
	control.tooltip_text = translated
	control.set_meta("l10n_source_tooltip_text", source)
	control.set_meta("l10n_last_tooltip_text", translated)


func _illustrated_section_title(icon_key: String, title_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	row.add_child(_icon_texture_rect(icon_key, Vector2(44, 44)))
	var title := _section_title(title_text)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	return row


func _section_title(text: String) -> Label:
	var title := _label(text, 21, _theme_text())
	title.custom_minimum_size = Vector2(0, 38)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	return title


func _icon_texture_rect(icon_key: String, minimum_size: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = UiIconCatalog.texture(icon_key)
	icon.custom_minimum_size = minimum_size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _style_progress_bar(bar: ProgressBar) -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.79, 0.86, 0.90)
	background.set_corner_radius_all(6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = COLOR_ACCENT
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)


func _set_bar_visual(bar: ProgressBar, value: float, color: Color) -> void:
	if bar == null:
		return
	bar.value = clampf(value, bar.min_value, bar.max_value)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("fill", fill)


func _style_tabs() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = _theme_panel()
	panel_style.border_color = _theme_border()
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", panel_style)

	var unselected_style := StyleBoxFlat.new()
	unselected_style.bg_color = _theme_panel_alt()
	unselected_style.border_color = _theme_border()
	unselected_style.set_border_width_all(2)
	unselected_style.set_corner_radius_all(8)
	unselected_style.content_margin_left = 12
	unselected_style.content_margin_right = 12
	unselected_style.content_margin_top = 6
	unselected_style.content_margin_bottom = 6
	var selected_style := unselected_style.duplicate() as StyleBoxFlat
	selected_style.bg_color = Color("28414a") if _dark_mode else Color("fff4cf")
	selected_style.border_color = Color("d3aa58") if _dark_mode else Color("d59a38")
	selected_style.shadow_color = Color(0, 0, 0, 0.16)
	selected_style.shadow_size = 2
	var hovered_style := unselected_style.duplicate() as StyleBoxFlat
	hovered_style.bg_color = Color("23414a") if _dark_mode else Color("eaf7f4")
	hovered_style.border_color = Color("63a69b")
	add_theme_stylebox_override("tab_selected", selected_style)
	add_theme_stylebox_override("tab_unselected", unselected_style)
	add_theme_stylebox_override("tab_hovered", hovered_style)
	add_theme_stylebox_override("tab_focus", selected_style)
	add_theme_color_override("font_selected_color", _theme_text())
	add_theme_color_override("font_unselected_color", _theme_muted())
	add_theme_color_override("font_hovered_color", _theme_text())
	add_theme_color_override("font_focus_color", _theme_text())
	add_theme_font_size_override("font_size", UI_CONTROL_FONT_SIZE)
	add_theme_constant_override("side_margin", 8)


func _readable_font_size(requested_size: int) -> int:
	if requested_size >= 24:
		return requested_size + 1
	return maxi(UI_MIN_FONT_SIZE, requested_size + 3)


func _theme_panel() -> Color:
	return Color(0.13, 0.18, 0.24) if _dark_mode else Color.WHITE


func _theme_panel_alt() -> Color:
	return Color(0.11, 0.16, 0.21) if _dark_mode else Color(0.98, 1.0, 0.99)


func _theme_text() -> Color:
	return Color(0.93, 0.96, 0.98) if _dark_mode else COLOR_TEXT


func _theme_muted() -> Color:
	return Color(0.70, 0.76, 0.82) if _dark_mode else COLOR_MUTED


func _theme_border() -> Color:
	return Color(0.31, 0.42, 0.52) if _dark_mode else Color(0.72, 0.80, 0.86)


func _theme_accent_text() -> Color:
	return Color(0.55, 0.78, 1.0) if _dark_mode else COLOR_ACCENT_DARK
