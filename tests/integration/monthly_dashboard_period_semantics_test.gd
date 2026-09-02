extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const SUCCESS_MARKER := "MONTHLY_DASHBOARD_PERIOD_SEMANTICS_TEST_PASSED"

var _failed := false
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var packed := load("res://scenes/Main.tscn") as PackedScene
	var main = packed.instantiate() if packed != null else null
	_check(main != null, "Main scene is available")
	if main == null:
		await TestCleanup.finish(self, [], 1)
		return
	root.add_child(main)
	await _settle(3)

	for expected_period in range(1, 4):
		main.security = 45
		main.call("_settle_month", false)
		await _settle(2)
		_check(main.monthly_report_history.size() == expected_period, "settlement records period %d exactly once" % expected_period)
		var latest: Dictionary = main.monthly_report_history[main.monthly_report_history.size() - 1]
		_check(int(latest.get("period_index", 0)) == expected_period, "settlement period index remains monotonic at %d" % expected_period)
		var chart = main.monthly_data_service_charts.get("security")
		_check(chart != null, "period %d keeps the security donut available" % expected_period)
		if chart == null:
			continue
		_check(
			chart.safety_warning_label.text.contains("連續 %d 月" % expected_period),
			"period %d counts the current unsafe month once" % expected_period
		)
		var expected_severity := "critical" if expected_period >= 3 else "caution"
		_check(
			str(chart.get_meta("safety_warning_severity", "")) == expected_severity,
			"period %d uses %s severity" % [expected_period, expected_severity]
		)
		if expected_period == 1:
			_check(is_equal_approx(chart.baseline_value(), 60.0), "first settled period uses the safety-line value as its baseline")
			_check(not chart.difference_label.text.contains("上月"), "first settled period compares against the safety line")
			_check(chart.difference_label.text.contains("低於安全線"), "first settled period reports its actual safety gap")
		else:
			var previous: Dictionary = main.monthly_report_history[expected_period - 2]
			_check(is_equal_approx(chart.baseline_value(), float(previous.get("security", 60))), "period %d compares against period %d" % [expected_period, expected_period - 1])
			_check(chart.difference_label.text.contains("上月"), "period %d explicitly names the prior-month comparison" % expected_period)

	var exit_code := 1 if _failed else 0
	if not _failed:
		print("%s Checks=%d" % [SUCCESS_MARKER, _checks])
	await TestCleanup.finish(self, [main], exit_code)


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Monthly dashboard period-semantics check failed: %s" % message)
