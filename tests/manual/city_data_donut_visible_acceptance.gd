extends SceneTree

const OUTPUT_PREFIX := "--city-data-donut-output-dir="
const RESULT_FILENAME := "city-data-donut-result.json"
const CAPTURE_FILENAME := "city-data-donut-actual-main-native.png"
const SAVE_PATH := "user://mayor_simulator/tests/city_data_donut_visible_acceptance.json"
const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")

var output_dir := ""
var failed := false
var main


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(OUTPUT_PREFIX):
			output_dir = argument.trim_prefix(OUTPUT_PREFIX)
	if output_dir.is_empty() or not DirAccess.dir_exists_absolute(output_dir):
		_fail("missing existing output directory")
		return
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name().to_lower() == "headless":
		_fail("native acceptance requires a Windows display driver")
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	await _settle(12)
	var packed := load("res://scenes/Main.tscn") as PackedScene
	if packed == null:
		_fail("Main.tscn could not be loaded")
		return
	main = packed.instantiate()
	main.start_save_path = SAVE_PATH
	root.add_child(main)
	await _settle(12)
	main.start_screen.animation_duration = 0.04
	main.start_screen.new_game_button.emit_signal("pressed")
	for _frame in range(180):
		if main._game_started and not main.start_screen.visible:
			break
		await process_frame
	if not main._game_started or main.start_screen.visible:
		_fail("new game did not reach the actual Main map")
		return
	if main.tutorial_overlay != null and main.tutorial_overlay.is_open():
		main.tutorial_overlay.skip_button.emit_signal("pressed")
		await _settle(6)

	main.monthly_report_history.clear()
	for _month in 2:
		var unsafe_snapshot: Dictionary = main._make_monthly_report_snapshot(1000, 800, 1.5)
		unsafe_snapshot["security"] = 45
		main.monthly_report_history.append(unsafe_snapshot)
	main.security = 45
	main._update_ui()
	main.municipal_button.emit_signal("pressed")
	await _settle(4)
	main.municipal_overlay.open_page("city_data")
	await _settle(12)
	if not main.municipal_overlay.is_open() or main.municipal_overlay.current_page() != "city_data":
		_fail("actual municipal flow did not open city data")
		return
	if not _validate_dashboard():
		return

	main.city_data_dashboard.restart_animations()
	await _settle(5)
	var animated_mid_count := _animated_mid_count()
	if animated_mid_count < 1:
		_fail("actual donut charts did not expose a visible baseline-to-target intermediate value")
		return
	await _settle(70)
	main._set_hint("驗收：城市數據使用動態圓環；金色為比較基準、紅色為安全線，連續三月低標會升級警示。", false)
	await _settle(8)
	var capture := _capture_native()
	if capture.is_empty():
		return
	var result := {
		"schema_version": 1,
		"suite": "mayor-simulator-city-data-donut-actual-main-native-visible-acceptance",
		"status": "PASS",
		"contract_validated": true,
		"actual_main": true,
		"scene": "res://scenes/Main.tscn",
		"capture_surface_kind": "native_fullscreen_root",
		"source": {
			"worktree": OS.get_environment("MAYOR_ACCEPTANCE_WORKTREE"),
			"branch": OS.get_environment("MAYOR_ACCEPTANCE_BRANCH"),
			"head": OS.get_environment("MAYOR_ACCEPTANCE_HEAD"),
			"tree": OS.get_environment("MAYOR_ACCEPTANCE_TREE"),
			"dirty": OS.get_environment("MAYOR_ACCEPTANCE_DIRTY") == "true",
			"status_sha256": OS.get_environment("MAYOR_ACCEPTANCE_STATUS_SHA256"),
			"fingerprint": OS.get_environment("MAYOR_ACCEPTANCE_SOURCE_FINGERPRINT"),
		},
		"dashboard": {
			"monthly_chart_count": main.monthly_data_kpi_charts.size() + main.monthly_data_service_charts.size(),
			"resident_and_finance_chart_count": main.benchmark_charts.size(),
			"monthly_progress_bar_count": _monthly_progress_bar_count(),
			"render_mode": "donut",
			"animated_mid_count": animated_mid_count,
			"security_warning_severity": str(main.monthly_data_service_charts["security"].get_meta("safety_warning_severity", "")),
			"history_source": "monthly_report_history",
		},
		"captures": [capture],
	}
	var result_file := FileAccess.open(output_dir.path_join(RESULT_FILENAME), FileAccess.WRITE)
	if result_file == null:
		_fail("failed to open result file")
		return
	result_file.store_string(JSON.stringify(result, "\t"))
	result_file.close()
	print("CITY_DATA_DONUT_NATIVE_VISIBLE_ACCEPTANCE_PASSED captures=1 monthly_charts=9 benchmark_charts=5 actual_main=true")
	await TestCleanup.finish(self, [main], 0)


func _validate_dashboard() -> bool:
	if main.monthly_data_kpi_charts.size() != 4 or main.monthly_data_service_charts.size() != 5:
		_fail("actual dashboard does not own the expected nine monthly charts")
		return false
	if main.benchmark_charts.size() != 5:
		_fail("actual dashboard does not own the four resident and one finance chart")
		return false
	for registry in [main.monthly_data_kpi_charts, main.monthly_data_service_charts, main.benchmark_charts]:
		for chart_variant in registry.values():
			if str(chart_variant.get_meta("chart_render_mode", "")) != "donut":
				_fail("an actual city-data chart did not render as a donut")
				return false
	if _monthly_progress_bar_count() != 0:
		_fail("monthly overview still contains legacy ProgressBar nodes")
		return false
	if str(main.monthly_data_service_charts["security"].get_meta("safety_warning_severity", "")) != "critical":
		_fail("third consecutive unsafe month did not become critical")
		return false
	return true


func _monthly_progress_bar_count() -> int:
	var grid: Node = main.city_data_dashboard.find_child("MonthlyDataChartGrid", true, false)
	return 0 if grid == null else grid.find_children("*", "ProgressBar", true, false).size()


func _animated_mid_count() -> int:
	var count := 0
	for registry in [main.monthly_data_kpi_charts, main.monthly_data_service_charts, main.benchmark_charts]:
		for chart_variant in registry.values():
			var displayed := float(chart_variant.displayed_value())
			var baseline := float(chart_variant.baseline_value())
			var target := float(chart_variant.target_value())
			if not is_equal_approx(displayed, baseline) and not is_equal_approx(displayed, target):
				count += 1
	return count


func _capture_native() -> Dictionary:
	var image := root.get_texture().get_image()
	if image.is_empty():
		_fail("native root capture is empty")
		return {}
	var path := output_dir.path_join(CAPTURE_FILENAME)
	if image.save_png(path) != OK:
		_fail("failed to save city-data donut capture")
		return {}
	var size := image.get_size()
	return {
		"filename": CAPTURE_FILENAME,
		"surface_kind": "native_fullscreen_root",
		"width": size.x,
		"height": size.y,
		"bytes": FileAccess.get_file_as_bytes(path).size(),
		"sha256": FileAccess.get_sha256(path).to_lower(),
	}


func _settle(frames: int) -> void:
	for _frame in frames:
		await process_frame


func _fail(message: String) -> void:
	if failed:
		return
	failed = true
	push_error("City-data donut actual-Main acceptance failed: %s" % message)
	quit(1)
