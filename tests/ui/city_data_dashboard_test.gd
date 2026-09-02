extends SceneTree

const METRIC_SPECS: Array[Dictionary] = [
	{"id": "security", "label": "治安", "icon_key": "security"},
	{"id": "environment", "label": "環境", "icon_key": "environment"},
	{"id": "traffic", "label": "交通", "icon_key": "traffic"},
	{"id": "education", "label": "教育", "icon_key": "education"},
	{"id": "healthcare", "label": "醫療", "icon_key": "healthcare"},
]
const RESIDENT_GROUPS: Array[String] = ["一般居民", "學生家庭", "商人", "老年居民"]

var _failed := false
var _dashboard_script: Script


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var component_resource := load("res://ui/shell/city_data_dashboard.gd") as Script
	_check(component_resource != null and component_resource.can_instantiate(), "dashboard script compiles and can instantiate")
	if _failed:
		quit(1)
		return
	_dashboard_script = component_resource

	var light_1799 = await _build_dashboard(1799.0, false)
	_validate_structure(light_1799, 2)
	await _validate_refresh_contract(light_1799)
	await _validate_hidden_tab_chart_redraw(light_1799)
	var light_panel := light_1799.get_theme_stylebox("panel") as StyleBoxFlat
	var light_background := light_panel.bg_color if light_panel != null else Color.TRANSPARENT
	light_1799.queue_free()
	await _settle()

	var dark_1800 = await _build_dashboard(1800.0, true)
	_validate_structure(dark_1800, 3)
	var dark_panel := dark_1800.get_theme_stylebox("panel") as StyleBoxFlat
	_check(dark_panel != null and dark_panel.bg_color != light_background, "light and dark palettes build distinct dashboard surfaces")
	dark_1800.queue_free()
	await _settle()

	if _failed:
		quit(1)
	else:
		print("City data dashboard test passed. Tabs=3 Charts=9,4,1 Layout=1799:2,1800:3 Snapshot=immutable Baselines=first-and-previous-month")
		quit(0)


func _build_dashboard(viewport_width: float, dark_mode: bool):
	var dashboard = _dashboard_script.new()
	dashboard.configure({
		"dark_mode": dark_mode,
		"viewport_width": viewport_width,
		"metric_specs": METRIC_SPECS,
		"resident_group_names": RESIDENT_GROUPS,
	})
	dashboard.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dashboard)
	await _settle()
	return dashboard


func _validate_structure(dashboard, expected_columns: int) -> void:
	_check(dashboard.name == "城市數據", "dashboard keeps the municipal page node name")
	_check(dashboard.get_tab_count() == 3, "dashboard keeps exactly three tabs")
	var expected_tab_nodes := ["月度總覽", "居民滿意", "即時財政"]
	for index in expected_tab_nodes.size():
		_check(dashboard.get_child(index).name == expected_tab_nodes[index], "tab %d keeps its node name" % index)
	var grid := dashboard.find_child("MonthlyDataChartGrid", true, false) as GridContainer
	_check(grid != null and grid.columns == expected_columns, "viewport threshold selects %d columns" % expected_columns)
	_check(grid != null and grid.get_child_count() == 9, "monthly overview keeps four KPI and five service charts")
	_check(dashboard.find_child("CityFinanceCoverageChart", true, false) != null, "finance coverage chart keeps its node name")
	_check(dashboard.monthly_data_kpi_charts.size() == 4, "KPI registry owns four charts")
	_check(dashboard.monthly_data_service_charts.size() == 5, "service registry owns five charts")
	_check(dashboard.group_bars.size() == 4, "resident registry owns four charts")
	_check(dashboard.benchmark_charts.size() == 5, "benchmark registry owns four resident charts and finance coverage")
	_check(dashboard.finance_bars.size() == 6, "dashboard owns only its six right-side finance bars")


func _validate_refresh_contract(dashboard) -> void:
	var first_month := _snapshot(false)
	var before_refresh := first_month.duplicate(true)
	dashboard.refresh(first_month)
	_check(first_month == before_refresh, "refresh does not mutate any caller-owned snapshot data")
	_check(is_equal_approx(dashboard.monthly_data_kpi_charts["net"].baseline_value(), 100.0), "first month compares finance against the 100 percent safety line")
	_check(is_equal_approx(dashboard.monthly_data_kpi_charts["net"].safety_value(), 100.0), "first month retains the independent finance safety line")
	_check(dashboard.monthly_data_kpi_charts["satisfaction"].difference_label.text.contains("百分點"), "first-month satisfaction explains its safety gap")

	var second_month := _snapshot(true)
	var second_before := second_month.duplicate(true)
	dashboard.refresh(second_month)
	_check(second_month == second_before, "previous-month refresh leaves nested input dictionaries unchanged")
	_check(is_equal_approx(dashboard.monthly_data_kpi_charts["net"].baseline_value(), 125.0), "second month uses prior finance coverage")
	_check(is_equal_approx(dashboard.monthly_data_service_charts["security"].baseline_value(), 72.0), "second month uses prior security")
	_check(is_equal_approx(dashboard.monthly_data_service_charts["security"].safety_value(), 60.0), "second month keeps an independent service safety line")
	_check(dashboard.monthly_data_service_charts["security"].has_safety_warning(), "security 45 still raises a safety warning")
	_check(dashboard.monthly_data_service_charts["security"].difference_label.text.contains("上月"), "security comparison explicitly names the previous month")
	_check(str(dashboard.monthly_data_service_charts["security"].get_meta("chart_render_mode", "")) == "donut", "monthly charts render as donut charts while preserving their public API")
	await _validate_baseline_to_target_animation(dashboard.monthly_data_service_charts["security"])
	_validate_safety_warning_streaks(dashboard)
	_validate_current_period_history_semantics(dashboard)

	dashboard.restart_animations()
	var restarted_count := 0
	for registry in [dashboard.benchmark_charts, dashboard.monthly_data_kpi_charts, dashboard.monthly_data_service_charts]:
		for chart_variant in registry.values():
			if bool(chart_variant.get_meta("animation_active", false)):
				restarted_count += 1
	_check(restarted_count == 14, "restart covers all fourteen unique dashboard charts")
	await _settle()


func _validate_baseline_to_target_animation(chart) -> void:
	chart.set_chart({
		"minimum": 0.0,
		"maximum": 100.0,
		"baseline": 20.0,
		"safety": 60.0,
		"current": 80.0,
		"duration": 0.80,
		"current_text": "測試 80%",
		"difference_text": "測試動畫",
	}, true)
	_check(is_equal_approx(chart.displayed_value(), 20.0), "donut animation starts at the comparison baseline")
	await create_timer(0.12).timeout
	var mid_value: float = float(chart.displayed_value())
	_check(mid_value > 20.0 and mid_value < 80.0, "donut animation visibly interpolates between baseline and target")
	await create_timer(0.80).timeout
	_check(is_equal_approx(chart.displayed_value(), 80.0), "donut animation reaches the current target value")


func _validate_safety_warning_streaks(dashboard) -> void:
	var first_warning = _refresh_security_warning(dashboard, [], 45)
	_check(str(first_warning.get_meta("safety_warning_severity", "")) == "caution", "first unsafe month uses a caution warning")
	var third_warning = _refresh_security_warning(dashboard, [_security_history_snapshot(45), _security_history_snapshot(45)], 45)
	_check(str(third_warning.get_meta("safety_warning_severity", "")) == "critical", "third consecutive unsafe month escalates to a critical warning")
	var reset_warning = _refresh_security_warning(dashboard, [_security_history_snapshot(45), _security_history_snapshot(70)], 45)
	_check(str(reset_warning.get_meta("safety_warning_severity", "")) == "caution", "a safe intervening month resets the warning streak")


func _validate_current_period_history_semantics(dashboard) -> void:
	var snapshot := _snapshot(false)
	snapshot["metrics"]["security"] = 45
	snapshot["monthly_report_history"] = [
		_security_history_snapshot(72, 1),
		_security_history_snapshot(45, 2),
	]
	snapshot["history_includes_current"] = true
	snapshot["current_period_index"] = 2
	snapshot["has_previous_month"] = true
	snapshot["previous_month"] = _security_history_snapshot(45, 2)
	dashboard.refresh(snapshot)
	var chart = dashboard.monthly_data_service_charts["security"]
	_check(is_equal_approx(chart.baseline_value(), 72.0), "a history tail marked current compares against the true prior period")
	_check(chart.safety_warning_label.text.contains("連續 1 月"), "the current unsafe period is counted exactly once")

	var gap_snapshot := _snapshot(false)
	gap_snapshot["metrics"]["security"] = 45
	gap_snapshot["monthly_report_history"] = [
		_security_history_snapshot(45, 1),
		_security_history_snapshot(45, 3),
	]
	gap_snapshot["history_includes_current"] = true
	gap_snapshot["current_period_index"] = 3
	dashboard.refresh(gap_snapshot)
	chart = dashboard.monthly_data_service_charts["security"]
	_check(is_equal_approx(chart.baseline_value(), 60.0), "a missing prior period falls back to the safety-line baseline")
	_check(chart.safety_warning_label.text.contains("連續 1 月"), "a period gap interrupts the unsafe warning streak")


func _refresh_security_warning(dashboard, history: Array, current_security: int):
	var snapshot := _snapshot(false)
	snapshot["metrics"]["security"] = current_security
	snapshot["monthly_report_history"] = history.duplicate(true)
	snapshot["has_previous_month"] = not history.is_empty()
	snapshot["previous_month"] = history[history.size() - 1].duplicate(true) if not history.is_empty() else {}
	var before := snapshot.duplicate(true)
	dashboard.refresh(snapshot)
	_check(snapshot == before, "warning streak refresh preserves caller-owned monthly history")
	return dashboard.monthly_data_service_charts["security"]


func _security_history_snapshot(value: int, period_index: int = 0) -> Dictionary:
	var snapshot := {
		"security": value,
		"coverage_rate": 100.0,
		"population_rate": 0.0,
		"satisfaction": 70,
		"score": 70,
		"environment": 70,
		"traffic": 70,
		"education": 70,
		"healthcare": 70,
	}
	if period_index > 0:
		snapshot["period_index"] = period_index
	return snapshot


func _validate_hidden_tab_chart_redraw(dashboard) -> void:
	dashboard.current_tab = 0
	await _settle()
	var resident_chart = dashboard.group_bars["一般居民"]
	var redraw_callable := Callable(resident_chart, "_request_redraw_after_layout_change")
	_check(resident_chart.plot_area.resized.is_connected(redraw_callable), "plot geometry changes invalidate the chart canvas")
	_check(resident_chart.visibility_changed.is_connected(redraw_callable), "newly visible charts invalidate their previously hidden canvas")
	resident_chart.set_meta("test_draw_count", 0)
	resident_chart.set_meta("test_last_draw_plot_width", 0.0)
	resident_chart.draw.connect(func() -> void:
		resident_chart.set_meta("test_draw_count", int(resident_chart.get_meta("test_draw_count", 0)) + 1)
		resident_chart.set_meta("test_last_draw_plot_width", resident_chart.plot_area.size.x)
	)
	dashboard.current_tab = 1
	await _settle(4)
	_check(int(resident_chart.get_meta("test_draw_count", 0)) > 0, "newly visible resident tab redraws its charts")
	_check(float(resident_chart.get_meta("test_last_draw_plot_width", 0.0)) > 100.0, "resident chart redraw happens after its plot receives a usable width")


func _snapshot(has_previous_month: bool) -> Dictionary:
	var previous_month := {
		"coverage_rate": 125.0,
		"population_rate": 1.5,
		"satisfaction": 68,
		"score": 66,
		"security": 72,
		"environment": 69,
		"traffic": 67,
		"education": 71,
		"healthcare": 70,
	}
	return {
		"has_previous_month": has_previous_month,
		"previous_month": previous_month.duplicate(true) if has_previous_month else {},
		"monthly_report_history": [previous_month.duplicate(true)] if has_previous_month else [],
		"population": 315,
		"month_start_population": 300,
		"satisfaction": 70,
		"score": 68,
		"rating": "B 級城市",
		"metrics": {
			"security": 45 if has_previous_month else 70,
			"environment": 73,
			"traffic": 67,
			"education": 71,
			"healthcare": 69,
		},
		"resident_groups": {
			"一般居民": 71,
			"學生家庭": 68,
			"商人": 73,
			"老年居民": 66,
		},
		"finance": {
			"tax_income": 600,
			"business_income": 160,
			"industrial_income": 120,
			"utility_income": 70,
			"service_income": 50,
			"total_income": 1000,
			"total_expense": 800,
			"net_income": 200,
		},
	}


func _settle(frames: int = 2) -> void:
	for _frame in frames:
		await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("City data dashboard check failed: %s" % message)
