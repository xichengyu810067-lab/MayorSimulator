extends SceneTree

const FiscalScrollContract := preload("res://tests/helpers/fiscal_scroll_contract.gd")
const FULLSCREEN_SETTLE_LIMIT := 120
const TEST_SAVE_PATH := "user://mayor_simulator/tests/ui_readability_autosave.json"
const NATIVE_TEST_SAVE_PATH := "user://mayor_simulator/tests/native_ui_readability_autosave.json"
const OUTPUT_ARGUMENT_PREFIX := "--ui-capture-output-dir="
const NATIVE_OUTPUT_ARGUMENT_PREFIX := "--ui-native-output-dir="
const REQUIRED_PHYSICAL_SIZE := Vector2i(2880, 1800)
const REQUIRED_FALLBACK_LOGICAL_SIZE := Vector2i(1280, 800)
const MINIMUM_NATIVE_PHYSICAL_SIZE := Vector2i(1280, 720)
const CAPTURE_SANITY_SAMPLE_COLUMNS := 32
const CAPTURE_SANITY_SAMPLE_ROWS := 20
const CAPTURE_MIN_OPAQUE_RATIO := 0.99
const CAPTURE_MIN_LUMINANCE_SD := 8.0
const CAPTURE_MIN_LUMINANCE_RANGE := 40.0
const RESULT_FILENAME := "capture-result.json"
const NATIVE_RESULT_FILENAME := "native-result.json"
const NATIVE_OUTPUTS := {
	"start": "native-start-screen.png",
	"main": "native-main.png",
	"settings": "native-settings.png",
	"municipal_overlay": "native-municipal-overlay.png",
}
const NATIVE_LANDMARKS := {
	"start": "start_actions",
	"main": "status_hud",
	"settings": "settings_panel",
	"municipal_overlay": "municipal_overlay",
}
const OUTPUTS := {
	"start": "fullscreen-start-screen.png",
	"start_loading": "fullscreen-start-loading.png",
	"tutorial_intro": "fullscreen-tutorial-intro.png",
	"tutorial_buildings": "fullscreen-tutorial-buildings.png",
	"tutorial_governance": "fullscreen-tutorial-governance.png",
	"tutorial_replay": "fullscreen-tutorial-replay.png",
	"main": "fullscreen-main.png",
	"weather_cloudy": "fullscreen-weather-cloudy.png",
	"weather_rain": "fullscreen-weather-rain.png",
	"settings": "fullscreen-settings.png",
	"settings_dark_en": "fullscreen-settings-dark-en.png",
	"building_context": "fullscreen-building-context.png",
	"hub": "fullscreen-municipal-hub.png",
	"hub_development": "fullscreen-municipal-development.png",
	"buildings": "fullscreen-buildings.png",
	"governance": "fullscreen-governance.png",
	"governance_review": "fullscreen-governance-review.png",
	"governance_implemented": "fullscreen-governance-implemented.png",
	"judicial": "fullscreen-judicial.png",
	"oversight": "fullscreen-oversight.png",
	"blueprint": "fullscreen-blueprint.png",
	"blueprint_review": "fullscreen-blueprint-review.png",
	"finance": "fullscreen-finance.png",
	"public_affairs": "fullscreen-public-affairs.png",
	"city_data": "fullscreen-city-data.png",
	"city_data_residents": "fullscreen-city-data-residents.png",
	"city_data_finance": "fullscreen-city-data-finance.png",
	"city_data_previous_month": "fullscreen-city-data-previous-month.png",
	"city_data_previous_month_warning": "fullscreen-city-data-previous-month-warning.png",
	"report": "fullscreen-report.png",
	"report_version_updates": "fullscreen-report-version-updates.png",
	"dark_blueprint": "fullscreen-dark-blueprint.png",
	"exit_confirm": "fullscreen-exit-confirm.png"
}

var _output_directory := ""
var _native_output_directory := ""
var _capture_records: Array[Dictionary] = []
var _captured_states: Dictionary = {}
var _native_capture_records: Array[Dictionary] = []
var _native_captured_states: Dictionary = {}
var _native_captured_hashes: Dictionary = {}
var _started_at_utc := ""
var _native_started_at_utc := ""
var _expected_fiscal_slider_names: Array[String] = []
var _capture_viewport: Viewport = null
var _capture_surface_kind := ""
var _capture_surface_mirrored := false
var _native_physical_size := Vector2i.ZERO
var _native_window_size := Vector2i.ZERO
var _native_backing_size := Vector2i.ZERO
var _native_logical_size := Vector2i.ZERO
var _native_screen_index := -1
var _native_screen_dpi := 0
var _native_screen_scale := 0.0
var _native_screen_size := Vector2i.ZERO
var _offscreen_notice: Label = null


func _initialize() -> void:
	if not _prepare_output_directories():
		quit(1)
		return
	call_deferred("_capture_states")


func _utc_now() -> String:
	return Time.get_datetime_string_from_system(true, true).replace(" ", "T") + "Z"


func _capture_states() -> void:
	if not await _capture_native_gui_phase():
		quit(1)
		return
	_started_at_utc = _utc_now()
	if not await _prepare_capture_surface():
		quit(1)
		return

	var packed_scene: PackedScene = load("res://scenes/Main.tscn")
	var scene := packed_scene.instantiate()
	_active_capture_viewport().add_child(scene)
	await _settle()
	_expected_fiscal_slider_names = FiscalScrollContract.expected_slider_names(scene)
	scene.start_save_path = TEST_SAVE_PATH
	if not _validate_start_screen(scene.get("start_screen")) or not _save_capture(OUTPUTS["start"]):
		quit(1)
		return
	var start_screen = scene.get("start_screen")
	start_screen.animation_duration = 0.90
	start_screen.new_game_button.emit_signal("pressed")
	var loading_capture_saved := false
	for _frame in range(120):
		await process_frame
		if not loading_capture_saved and start_screen.progress_bar.value >= 28.0 and start_screen.progress_bar.value < 90.0:
			if not _validate_start_loading(start_screen) or not _save_capture(OUTPUTS["start_loading"]):
				quit(1)
				return
			loading_capture_saved = true
		if not start_screen.is_loading():
			break
	if not loading_capture_saved:
		push_error("Loading animation never exposed a capturable intermediate progress state.")
		quit(1)
		return
	if start_screen.visible:
		push_error("New-game loading did not close the start screen.")
		quit(1)
		return
	var tutorial = scene.get("tutorial_overlay")
	if tutorial == null or not tutorial.is_open() or tutorial.current_page != 0:
		push_error("New game did not open the first story tutorial page.")
		quit(1)
		return
	await _settle_frames(24)
	if not _save_capture(OUTPUTS["tutorial_intro"]):
		quit(1)
		return
	tutorial.next_button.emit_signal("pressed")
	await _settle_frames(18)
	if tutorial.current_page != 1 or not _save_capture(OUTPUTS["tutorial_buildings"]):
		push_error("Tutorial did not advance to the building guidance page.")
		quit(1)
		return
	while tutorial.current_page < 4:
		tutorial.next_button.emit_signal("pressed")
		await _settle_frames(18)
	if not _save_capture(OUTPUTS["tutorial_governance"]):
		quit(1)
		return
	while tutorial.current_page < tutorial.PAGES.size() - 1:
		tutorial.next_button.emit_signal("pressed")
		await _settle_frames(18)
	tutorial.next_button.emit_signal("pressed")
	await _settle_frames(24)
	if tutorial.is_open() or not bool(scene.get("tutorial_completed")):
		push_error("Tutorial did not close and persist completion after the final button.")
		quit(1)
		return
	if not _validate_main_hud(scene) or not _save_capture(OUTPUTS["main"]):
		quit(1)
		return
	var weather_layer = scene.get("weather_visual_layer")
	if weather_layer == null or not weather_layer.set_preview_weather("cloudy"):
		push_error("Weather visual layer could not enter the cloudy preview state.")
		quit(1)
		return
	await _settle()
	if not _save_capture(OUTPUTS["weather_cloudy"]):
		quit(1)
		return
	if not weather_layer.set_preview_weather("rain"):
		push_error("Weather visual layer could not enter the rain preview state.")
		quit(1)
		return
	await _settle()
	if not _save_capture(OUTPUTS["weather_rain"]):
		quit(1)
		return
	weather_layer.clear_preview_weather()
	await _settle()

	var original_locale := str(root.get_node("L10n").current_locale)
	var original_dark := bool(scene.get("is_dark_mode"))
	var settings_button = scene.get("settings_button") as Button
	settings_button.emit_signal("pressed")
	await _settle()
	var settings = scene.get("settings_overlay")
	if not _validate_settings(settings) or not _save_capture(OUTPUTS["settings"]):
		quit(1)
		return
	settings.tutorial_button.emit_signal("pressed")
	await _settle_frames(18)
	tutorial = scene.get("tutorial_overlay")
	if tutorial == null or not tutorial.is_open() or not _save_capture(OUTPUTS["tutorial_replay"]):
		push_error("Settings tutorial replay action did not reopen the story.")
		quit(1)
		return
	tutorial.skip_button.emit_signal("pressed")
	await _settle_frames(24)
	settings_button.emit_signal("pressed")
	await _settle()
	settings = scene.get("settings_overlay")
	settings.language_selector.select_choice("en")
	settings.language_selector.emit_signal("choice_selected", "en")
	await _settle()
	settings = scene.get("settings_overlay")
	settings.dark_button.emit_signal("pressed")
	await _settle()
	settings = scene.get("settings_overlay")
	if str(root.get_node("L10n").current_locale) != "en" or not bool(scene.get("is_dark_mode")):
		push_error("Settings did not apply the selected language and dark appearance.")
		quit(1)
		return
	if not _validate_settings(settings) or not _save_capture(OUTPUTS["settings_dark_en"]):
		quit(1)
		return
	var restore_theme_button: Button = settings.dark_button if original_dark else settings.light_button
	restore_theme_button.emit_signal("pressed")
	await _settle()
	settings = scene.get("settings_overlay")
	settings.language_selector.select_choice(original_locale)
	settings.language_selector.emit_signal("choice_selected", original_locale)
	await _settle()
	if str(root.get_node("L10n").current_locale) != original_locale:
		push_error("Settings did not restore the original locale after the multilingual capture.")
		quit(1)
		return
	settings = scene.get("settings_overlay")
	settings.close()
	await _settle()

	scene.city_grid[18] = "住宅"
	scene.building_customizations[18] = {"variant": 0, "roof": 0, "wall": 0}
	scene.vertical_slice.register_existing_building(18, "住宅", scene.building_customizations[18])
	scene.call("_apply_building_effect", scene.buildings["住宅"])
	scene.call("_update_ui")
	scene.call("_select_built_cell", 18)
	await _settle()
	var building_context = scene.get("building_context_panel")
	if not _validate_building_context(building_context) or not _save_capture(OUTPUTS["building_context"]):
		quit(1)
		return
	building_context.call("close_panel")

	scene.call("_open_municipal_center")
	await _settle()
	var overlay = scene.get("municipal_overlay")
	if not _validate_overlay(overlay, "hub") or not _save_capture(OUTPUTS["hub"]):
		quit(1)
		return
	var development_button := overlay.find_child("MunicipalCategory_development", true, false) as Button
	development_button.emit_signal("pressed")
	await _settle()
	if not _validate_hub_group(overlay, "development") or not _save_capture(OUTPUTS["hub_development"]):
		quit(1)
		return
	overlay.call("open_hub")
	await _settle()

	# Seed representative player-facing cases so the judicial and oversight
	# captures exercise the actual defense states instead of only empty screens.
	var justice_system = scene.get("vertical_slice").governance.justice_system
	var opened_judicial: Dictionary = justice_system.open_judicial_case("public_safety_act", 1, 64, "公共安全法案違法施行案")
	var visual_court_case: Dictionary = opened_judicial.get("case", {})
	justice_system.advance_judicial_procedures(int(visual_court_case.get("hearing_day", 1)))
	justice_system.open_oversight_case(
		"official_mayor",
		["違法強制施行法案", "未遵守議會否決決議"],
		71,
		1
	)
	scene.get("judicial_panel").refresh(justice_system)
	scene.get("oversight_panel").refresh(justice_system)
	if not bool(scene.get("judicial_panel").submit_current_defense("safety_emergency").get("ok", false)):
		push_error("Judicial defense action could not be submitted from the UI panel.")
		quit(1)
		return
	if not bool(scene.get("oversight_panel").submit_current_defense("full_disclosure").get("ok", false)):
		push_error("Oversight impeachment defense could not be submitted from the UI panel.")
		quit(1)
		return

	for page_id in ["buildings", "governance", "judicial", "oversight", "blueprint", "finance", "public_affairs"]:
		overlay.call("open_page", page_id)
		await _settle()
		if page_id == "finance":
			var fiscal_tabs := overlay.find_child("FiscalCategoryTabs", true, false) as TabContainer
			var fiscal_scroll_contract: Dictionary = await FiscalScrollContract.validate(
				self,
				overlay,
				fiscal_tabs,
				_expected_fiscal_slider_names
			)
			if not bool(fiscal_scroll_contract.get("ok", false)):
				push_error("Finance responsive scroll contract failed: %s" % "; ".join(fiscal_scroll_contract.get("errors", [])))
				quit(1)
				return
			print("FINANCE_RESPONSIVE_SCROLL_CONTRACT %s" % JSON.stringify(fiscal_scroll_contract))
		if not _validate_overlay(overlay, page_id) or not _save_capture(OUTPUTS[page_id]):
			quit(1)
			return

	overlay.call("open_page", "blueprint")
	var blueprint_submit := overlay.find_child("SubmitCustomBlueprintButton", true, false) as Button
	if blueprint_submit == null or not blueprint_submit.is_visible_in_tree():
		push_error("Approved starter blueprint did not expose the custom-version review action.")
		quit(1)
		return
	blueprint_submit.emit_signal("pressed")
	await _settle()
	if not _validate_blueprint_review(overlay) or not _save_capture(OUTPUTS["blueprint_review"]):
		quit(1)
		return

	overlay.call("open_page", "governance")
	scene.call("_toggle_policy", true, "環保政策")
	scene.call("_submit_bill", "交通建設法案")
	await _settle()
	if str((scene.get("governance_bill_cards") as Dictionary)["交通建設法案"].get_parent().name) != "review_bill_Grid":
		push_error("Governance review capture could not move the submitted bill to review.")
		quit(1)
		return
	if not _validate_overlay(overlay, "governance") or not _save_capture(OUTPUTS["governance_review"]):
		quit(1)
		return

	var governance = scene.get("vertical_slice").governance
	governance.pending_bill.clear()
	governance.active_laws["transit_act"] = {
		"bill_id": "transit_act",
		"name": "交通建設法案",
		"status": "active",
		"effects": {},
	}
	scene.call("_update_ui")
	scene.call("_select_governance_status", "implemented")
	await _settle()
	if str((scene.get("governance_bill_cards") as Dictionary)["交通建設法案"].get_parent().name) != "implemented_bill_Grid":
		push_error("Governance implemented capture could not move the active bill to implemented.")
		quit(1)
		return
	if not _validate_overlay(overlay, "governance") or not _save_capture(OUTPUTS["governance_implemented"]):
		quit(1)
		return

	overlay.call("close_overlay")
	scene.call("_open_city_data")
	await _settle()
	overlay = scene.get("municipal_overlay")
	var animated_city_chart = (scene.get("monthly_data_service_charts") as Dictionary).values()[0]
	if not bool(animated_city_chart.get_meta("animation_active", false)) or is_equal_approx(animated_city_chart.displayed_value(), animated_city_chart.target_value()):
		push_error("City-data benchmark chart did not expose a visible in-progress animation.")
		quit(1)
		return
	if not _validate_monthly_data_mode(scene, false):
		quit(1)
		return
	if not await _validate_city_data_tabs(overlay):
		quit(1)
		return
	await _settle_frames(48)
	if not is_equal_approx(animated_city_chart.displayed_value(), animated_city_chart.target_value()):
		push_error("City-data benchmark chart did not settle on its authoritative target.")
		quit(1)
		return
	if not _validate_overlay(overlay, "city_data") or not _save_capture(OUTPUTS["city_data"]):
		quit(1)
		return
	var city_tabs_for_capture := overlay.find_child("城市數據", true, false) as TabContainer
	city_tabs_for_capture.current_tab = 1
	await _settle_frames(12)
	if not _save_capture(OUTPUTS["city_data_residents"]):
		quit(1)
		return
	city_tabs_for_capture.current_tab = 2
	await _settle_frames(12)
	if not _save_capture(OUTPUTS["city_data_finance"]):
		quit(1)
		return
	city_tabs_for_capture.current_tab = 0
	await _settle()
	overlay.call("close_overlay")
	scene.call("_next_month")
	scene.set("security", 45)
	scene.call("_update_ui")
	scene.call("_open_city_data")
	await _settle()
	overlay = scene.get("municipal_overlay")
	if not _validate_monthly_data_mode(scene, true):
		quit(1)
		return
	if not _validate_overlay(overlay, "city_data") or not _save_capture(OUTPUTS["city_data_previous_month"]):
		quit(1)
		return
	var city_data_tabs := overlay.find_child("城市數據", true, false) as TabContainer
	var overview_scroll := city_data_tabs.get_child(0) as ScrollContainer if city_data_tabs != null else null
	if overview_scroll != null:
		overview_scroll.scroll_vertical = 650
		await _settle()
	var visible_safety_warning := false
	if overview_scroll != null:
		for warning_variant in overlay.find_children("BenchmarkSafetyWarning", "Label", true, false):
			var warning_label := warning_variant as Label
			if warning_label.visible and overview_scroll.get_global_rect().intersects(warning_label.get_global_rect()):
				visible_safety_warning = true
				break
	if overview_scroll == null or not visible_safety_warning or not _save_capture(OUTPUTS["city_data_previous_month_warning"]):
		push_error("Second-month city data could not expose its safety-warning area.")
		quit(1)
		return

	overlay.call("close_overlay")
	scene.call("_record_major_event", "building_completed", "市民會館", "", "capture:building_completed", scene.get("vertical_slice").game_day())
	var capture_npc_ids: PackedStringArray = scene.get("vertical_slice").population.sorted_npc_ids()
	var capture_actor_id := capture_npc_ids[0] if not capture_npc_ids.is_empty() else ""
	scene.call("_record_major_event", "petition_accepted", "改善校園周邊交通", "希望增加公車班次並改善通學安全。", "capture:petition", scene.get("vertical_slice").game_day(), capture_actor_id)
	scene.call("_update_ui")
	scene.call("_open_monthly_report")
	await _settle()
	overlay = scene.get("municipal_overlay")
	if not _validate_monthly_report_scope(scene):
		quit(1)
		return
	if not _validate_overlay(overlay, "report") or not _save_capture(OUTPUTS["report"]):
		quit(1)
		return
	var report_scroll := overlay.find_child("月度報告", true, false) as ScrollContainer
	if report_scroll != null:
		report_scroll.scroll_vertical = 10000
		await _settle()
	if not _save_capture(OUTPUTS["report_version_updates"]):
		push_error("Monthly report could not expose its version-update area.")
		quit(1)
		return

	overlay.call("close_overlay")
	scene.call("_toggle_theme")
	await _settle()
	scene.call("_open_municipal_center")
	overlay = scene.get("municipal_overlay")
	overlay.call("open_page", "blueprint")
	await _settle()
	if not _validate_overlay(overlay, "blueprint") or not _save_capture(OUTPUTS["dark_blueprint"]):
		quit(1)
		return

	overlay.call("close_overlay")
	var exit_button = scene.get("exit_button")
	if exit_button == null or not is_instance_valid(exit_button):
		push_error("Readability capture could not find the main exit button.")
		quit(1)
		return
	exit_button.emit_signal("pressed")
	await _settle()
	var exit_confirmation = scene.get("exit_confirmation")
	if not _validate_exit_confirmation(exit_confirmation) or not _save_capture(OUTPUTS["exit_confirm"]):
		quit(1)
		return
	var cancel_button := exit_confirmation.get("cancel_button") as Button
	cancel_button.emit_signal("pressed")
	await _settle()
	if exit_confirmation.visible:
		push_error("Exit confirmation remained visible after pressing cancel.")
		quit(1)
		return

	if not _publish_capture_result():
		quit(1)
		return
	print(
		"Offscreen UI evidence captures saved with surface=%s logical=%s." % [
			_capture_surface_kind,
			_capture_logical_size(),
		]
	)
	print(
		"UI_CAPTURE_CANONICAL_ACCEPTANCE_PASSED native_gui=PASS native_captures=%d offscreen_evidence=PASS offscreen_captures=%d physical=%dx%d logical=%dx%d" % [
			NATIVE_OUTPUTS.size(),
			OUTPUTS.size(),
			REQUIRED_PHYSICAL_SIZE.x,
			REQUIRED_PHYSICAL_SIZE.y,
			REQUIRED_FALLBACK_LOGICAL_SIZE.x,
			REQUIRED_FALLBACK_LOGICAL_SIZE.y,
		]
	)
	quit(0)


func _capture_native_gui_phase() -> bool:
	var packed_scene: PackedScene = load("res://scenes/Main.tscn")
	if packed_scene == null:
		push_error("Native GUI acceptance could not load Main.tscn.")
		return false
	var scene := packed_scene.instantiate()
	scene.start_save_path = NATIVE_TEST_SAVE_PATH
	root.add_child(scene)
	if scene.get_parent() != root:
		push_error("Native GUI acceptance requires Main.tscn to be attached directly to the root Window viewport.")
		if scene.get_parent() != null:
			scene.get_parent().remove_child(scene)
		scene.free()
		return false
	_native_started_at_utc = _utc_now()
	# Attach the production scene before changing display mode.  This makes the
	# native phase a real visible playtest instead of an empty bootstrap window.
	if not await _prepare_native_fullscreen_surface():
		await _release_native_scene(scene)
		return false
	await _settle_frames(24)
	var phase_ok := await _capture_native_gui_states(scene)
	if phase_ok:
		phase_ok = _publish_native_capture_result()
	var release_ok := await _release_native_scene(scene)
	_capture_viewport = null
	_capture_surface_kind = ""
	return phase_ok and release_ok


func _prepare_native_fullscreen_surface() -> bool:
	if DisplayServer.get_name().to_lower() == "headless":
		push_error("Native fullscreen GUI acceptance cannot run with the headless display driver.")
		return false

	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	var previous_size := Vector2i.ZERO
	var previous_texture_size := Vector2i.ZERO
	var previous_logical_size := Vector2i.ZERO
	var stable_frames := 0
	var last_window_size := Vector2i.ZERO
	var last_texture_size := Vector2i.ZERO
	var last_logical_size := Vector2i.ZERO
	var last_mode := DisplayServer.WINDOW_MODE_WINDOWED
	for _frame in range(FULLSCREEN_SETTLE_LIMIT):
		await process_frame
		var current_size := DisplayServer.window_get_size()
		var mode := DisplayServer.window_get_mode()
		var is_fullscreen := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		var texture := root.get_texture()
		var texture_size := Vector2i(texture.get_width(), texture.get_height())
		var logical_size_value := root.get_visible_rect().size
		var logical_size := Vector2i(roundi(logical_size_value.x), roundi(logical_size_value.y))
		var screen_index := DisplayServer.window_get_current_screen()
		var screen_size := DisplayServer.screen_get_size(screen_index)
		var window_scale_x := float(current_size.x) / float(maxi(logical_size.x, 1))
		var window_scale_y := float(current_size.y) / float(maxi(logical_size.y, 1))
		var backing_scale_x := float(texture_size.x) / float(maxi(logical_size.x, 1))
		var backing_scale_y := float(texture_size.y) / float(maxi(logical_size.y, 1))
		last_window_size = current_size
		last_texture_size = texture_size
		last_logical_size = logical_size
		last_mode = mode
		var valid_native_surface: bool = (
			is_fullscreen
			and current_size.x >= MINIMUM_NATIVE_PHYSICAL_SIZE.x
			and current_size.y >= MINIMUM_NATIVE_PHYSICAL_SIZE.y
			and current_size == screen_size
			and texture_size.x >= MINIMUM_NATIVE_PHYSICAL_SIZE.x
			and texture_size.y >= MINIMUM_NATIVE_PHYSICAL_SIZE.y
			and logical_size.x >= 1280
			and logical_size.y >= 720
			and absf(window_scale_x - window_scale_y) <= 0.01
			and absf(backing_scale_x - backing_scale_y) <= 0.01
		)
		if (
			valid_native_surface
			and current_size == previous_size
			and texture_size == previous_texture_size
			and logical_size == previous_logical_size
		):
			stable_frames += 1
		else:
			stable_frames = 0
		previous_size = current_size
		previous_texture_size = texture_size
		previous_logical_size = logical_size
		if stable_frames >= 3:
			_capture_viewport = root
			_capture_surface_kind = "native_fullscreen_root"
			_native_physical_size = current_size
			_native_window_size = current_size
			_native_backing_size = texture_size
			_native_logical_size = logical_size
			_native_screen_index = screen_index
			_native_screen_dpi = DisplayServer.screen_get_dpi(_native_screen_index)
			_native_screen_scale = DisplayServer.screen_get_scale(_native_screen_index)
			_native_screen_size = DisplayServer.screen_get_size(_native_screen_index)
			if _native_screen_dpi <= 0 or _native_screen_scale <= 0.0 or _native_screen_size.x <= 0 or _native_screen_size.y <= 0:
				push_error(
					"Native display metrics are invalid: screen=%d dpi=%d scale=%.3f size=%s." % [
						_native_screen_index,
						_native_screen_dpi,
						_native_screen_scale,
						_native_screen_size,
					]
				)
				return false
			print(
				"Native fullscreen root stabilized at capture=%s backing=%s window=%s logical=%s screen=%d dpi=%d scale=%.3f." % [
					_native_physical_size,
					_native_backing_size,
					_native_window_size,
					_native_logical_size,
					_native_screen_index,
					_native_screen_dpi,
					_native_screen_scale,
				]
			)
			return true

	push_error(
		"Native fullscreen root did not stabilize with a fullscreen, screen-sized, uniformly scaled surface at >=%s within %d frames; last mode=%d window=%s root_texture=%s logical=%s." % [
			MINIMUM_NATIVE_PHYSICAL_SIZE,
			FULLSCREEN_SETTLE_LIMIT,
			last_mode,
			last_window_size,
			last_texture_size,
			last_logical_size,
		]
	)
	return false


func _capture_native_gui_states(scene) -> bool:
	var start_screen = scene.get("start_screen")
	if not _validate_start_screen(start_screen):
		return false
	if not _save_native_capture(NATIVE_OUTPUTS["start"], start_screen.new_game_button as Control):
		return false

	start_screen.animation_duration = 0.35
	start_screen.new_game_button.emit_signal("pressed")
	for _frame in range(240):
		await process_frame
		if not start_screen.is_loading():
			break
	if start_screen.is_loading() or start_screen.visible:
		push_error("Native GUI new-game loading did not reach the playable scene.")
		return false
	var tutorial = scene.get("tutorial_overlay")
	if tutorial == null or not tutorial.is_open():
		push_error("Native GUI new game did not expose the story tutorial.")
		return false
	tutorial.skip_button.emit_signal("pressed")
	await _settle_frames(24)
	if tutorial.is_open() or not _validate_main_hud(scene):
		push_error("Native GUI could not reach a validated main HUD after skipping the tutorial.")
		return false
	var status_hud := scene.find_child("StatusHud", true, false) as Control
	if status_hud == null or not _save_native_capture(NATIVE_OUTPUTS["main"], status_hud):
		return false

	var settings_button = scene.get("settings_button") as Button
	settings_button.emit_signal("pressed")
	await _settle_frames(18)
	var settings = scene.get("settings_overlay")
	if not _validate_settings(settings):
		return false
	var settings_panel := settings.find_child("SettingsPanel", true, false) as Control
	if settings_panel == null or not _save_native_capture(NATIVE_OUTPUTS["settings"], settings_panel):
		return false
	settings.close()
	await _settle()

	scene.call("_open_municipal_center")
	await _settle_frames(18)
	var overlay = scene.get("municipal_overlay")
	if not _validate_overlay(overlay, "hub"):
		return false
	if not _save_native_capture(NATIVE_OUTPUTS["municipal_overlay"], overlay as Control):
		return false
	overlay.call("close_overlay")
	await _settle()
	return true


func _release_native_scene(scene: Node) -> bool:
	if scene != null and is_instance_valid(scene):
		if scene.get_parent() != null:
			scene.get_parent().remove_child(scene)
		scene.free()
	await _settle_frames(4)
	if is_instance_valid(scene):
		push_error("Native GUI scene remained alive before offscreen evidence capture.")
		return false
	print("Native GUI scene fully released before offscreen evidence capture.")
	return true


func _prepare_capture_surface() -> bool:
	if DisplayServer.get_name().to_lower() == "headless":
		push_error("Offscreen UI evidence capture requires a non-headless display driver.")
		return false

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	await process_frame
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_size(Vector2i(960, 600))
	DisplayServer.window_set_position(Vector2i(32, 32))
	DisplayServer.window_set_title("Mayor Simulator - Automated Offscreen Evidence (Native GUI phase complete)")
	_show_offscreen_notice()
	var offscreen := SubViewport.new()
	offscreen.name = "UICaptureViewport"
	offscreen.size = REQUIRED_PHYSICAL_SIZE
	offscreen.size_2d_override = REQUIRED_FALLBACK_LOGICAL_SIZE
	offscreen.size_2d_override_stretch = true
	offscreen.transparent_bg = false
	offscreen.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(offscreen)
	_capture_viewport = offscreen
	_capture_surface_kind = "offscreen_subviewport"
	var exact_frames := 0
	for _frame in range(FULLSCREEN_SETTLE_LIMIT):
		await process_frame
		var texture := offscreen.get_texture()
		var texture_size := Vector2i(texture.get_width(), texture.get_height())
		var logical_size_value := offscreen.get_visible_rect().size
		var logical_size := Vector2i(roundi(logical_size_value.x), roundi(logical_size_value.y))
		if texture_size == REQUIRED_PHYSICAL_SIZE and logical_size == REQUIRED_FALLBACK_LOGICAL_SIZE:
			exact_frames += 1
		else:
			exact_frames = 0
		if exact_frames >= 3:
			print(
				"Offscreen capture surface stabilized at physical=%s logical=%s." % [
					texture_size,
					logical_size,
				]
			)
			return true

	push_error(
		"Offscreen evidence surface failed to produce physical=%s logical=%s within %d frames." % [
			REQUIRED_PHYSICAL_SIZE,
			REQUIRED_FALLBACK_LOGICAL_SIZE,
			FULLSCREEN_SETTLE_LIMIT,
		]
	)
	return false


func _show_offscreen_notice() -> void:
	if _offscreen_notice != null and is_instance_valid(_offscreen_notice):
		return
	var notice := Label.new()
	notice.name = "OffscreenEvidenceNotice"
	notice.position = Vector2(80, 80)
	notice.size = Vector2(1120, 640)
	notice.text = "Automated 2880×1800 offscreen evidence capture\nNative GUI acceptance phase is complete\nThis preview window is not the game UI"
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.add_theme_font_size_override("font_size", 30)
	notice.add_theme_color_override("font_color", Color("f3f6fa"))
	root.add_child(notice)
	_offscreen_notice = notice


func _active_capture_viewport() -> Viewport:
	if _capture_viewport != null and is_instance_valid(_capture_viewport):
		return _capture_viewport
	return root


func _capture_logical_size() -> Vector2:
	return _active_capture_viewport().get_visible_rect().size


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw


func _settle_frames(frame_count: int) -> void:
	for _frame in range(frame_count):
		await process_frame
	await RenderingServer.frame_post_draw


func _validate_overlay(overlay, expected_page: String) -> bool:
	if overlay == null or not is_instance_valid(overlay):
		push_error("Readability capture could not find the municipal overlay.")
		return false
	if not bool(overlay.call("is_open")):
		push_error("Municipal overlay is not open for '%s'." % expected_page)
		return false
	var current_page := str(overlay.call("current_page"))
	if current_page != expected_page:
		push_error("Expected municipal page '%s', got '%s'." % [expected_page, current_page])
		return false
	if not _validate_visual_data(overlay, expected_page):
		return false
	return true


func _validate_city_data_tabs(overlay) -> bool:
	if overlay == null or not is_instance_valid(overlay):
		push_error("City-data tab validation could not find the municipal overlay.")
		return false
	var tabs := overlay.find_child("城市數據", true, false) as TabContainer
	if tabs == null or tabs.get_tab_count() != 3:
		push_error("City data page must expose exactly three task-focused tabs.")
		return false
	if tabs.get_theme_font_size("font_size") < 18:
		push_error("City data tabs must preserve an 18px-or-larger label size.")
		return false
	var expected_titles := ["月度總覽", "居民滿意", "即時財政"]
	var expected_bars := [0, 0, 6]
	var expected_benchmark_charts := [9, 4, 1]
	var expected_metric_cards := [9, 0, 0]
	var l10n = root.get_node_or_null("L10n")
	var comparison_rule := tabs.find_child("MonthlyDataComparisonRule", true, false) as Label
	var finance_intro := tabs.find_child("CityFinanceIntro", true, false) as Label
	if (
		l10n == null
		or comparison_rule == null
		or comparison_rule.text != str(l10n.text("第一個月與安全線比較；第二個月起與上月比較。紅色安全線警告永遠保留。"))
		or finance_intro == null
		or finance_intro.text != str(l10n.text("先看收入能覆蓋多少支出；金額明細放在下方供需要時查閱。"))
	):
		push_error("City data static guidance did not return to the active locale after language switching.")
		return false
	var logical_rect := Rect2(Vector2.ZERO, _capture_logical_size())
	if not logical_rect.encloses(tabs.get_global_rect()):
		push_error("City data tab container extends outside the logical viewport: %s." % tabs.get_global_rect())
		return false
	for index in tabs.get_tab_count():
		var expected_title: String = str(l10n.text(expected_titles[index]) if l10n != null else expected_titles[index])
		if tabs.get_tab_title(index) != expected_title:
			push_error("City data tab %d must be titled '%s'." % [index, expected_title])
			return false
		tabs.current_tab = index
		await _settle()
		var active_page := tabs.get_child(index) as Control
		if active_page == null or not active_page.is_visible_in_tree():
			push_error("City data tab '%s' did not reveal its page." % expected_title)
			return false
		if not logical_rect.encloses(active_page.get_global_rect()):
			push_error("City data tab '%s' extends outside the logical viewport: %s." % [expected_title, active_page.get_global_rect()])
			return false
		var visible_metric_cards := 0
		for card_variant in active_page.find_children("MonthlyData*", "PanelContainer", true, false):
			var card := card_variant as Control
			if card.is_visible_in_tree():
				visible_metric_cards += 1
				var benchmark_chart = null
				for chart_variant in card.find_children("*", "Control", true, false):
					if chart_variant.has_method("baseline_value"):
						benchmark_chart = chart_variant
						break
				if benchmark_chart == null or benchmark_chart.current_label.text.strip_edges().is_empty() or benchmark_chart.difference_label.text.strip_edges().is_empty():
					push_error("Monthly data card '%s' has a missing chart value or comparison explanation." % card.name)
					return false
		if visible_metric_cards != expected_metric_cards[index]:
			push_error("City data tab '%s' must expose %d metric cards; found %d." % [expected_title, expected_metric_cards[index], visible_metric_cards])
			return false
		var visible_bars := 0
		for bar_variant in active_page.find_children("*", "ProgressBar", true, false):
			var bar := bar_variant as ProgressBar
			if bar.is_visible_in_tree():
				visible_bars += 1
				if logical_rect.intersects(bar.get_global_rect()) and (bar.size.x <= 0.0 or bar.size.y < 10.0):
					push_error("City data tab '%s' contains a clipped or unreadable visual bar: %s." % [expected_title, bar.get_global_rect()])
					return false
		if visible_bars != expected_bars[index]:
			push_error("City data tab '%s' must expose %d visual bars; found %d." % [expected_title, expected_bars[index], visible_bars])
			return false
		var visible_benchmark_charts := 0
		for chart_variant in active_page.find_children("*", "Control", true, false):
			if chart_variant.has_method("baseline_value") and chart_variant.is_visible_in_tree():
				visible_benchmark_charts += 1
		if visible_benchmark_charts != expected_benchmark_charts[index]:
			push_error("City data tab '%s' must expose %d benchmark charts; found %d." % [expected_title, expected_benchmark_charts[index], visible_benchmark_charts])
			return false
		var visible_labels: Array = []
		for label_variant in active_page.find_children("*", "Label", true, false):
			var label := label_variant as Label
			if not label.is_visible_in_tree():
				continue
			if not logical_rect.intersects(label.get_global_rect()):
				continue
			visible_labels.append(label)
			if label.get_theme_font_size("font_size") < 15:
				push_error("City data tab '%s' contains text smaller than 15px: %s." % [expected_title, label.name])
				return false
			if label.size.x <= 0.0 or label.size.y <= 0.0:
				push_error("City data tab '%s' contains clipped text '%s': %s." % [expected_title, label.text, label.get_global_rect()])
				return false
		var visible_buttons: Array = []
		for button_variant in active_page.find_children("*", "Button", true, false):
			if button_variant.is_visible_in_tree():
				visible_buttons.append(button_variant)
		if not _validate_page_scope("city_data", visible_labels, visible_buttons):
			return false
		print("City data tab validation '%s': cards=%d bars=%d labels=%d." % [expected_title, visible_metric_cards, visible_bars, visible_labels.size()])
	tabs.current_tab = 0
	await _settle()
	return true


func _validate_hub_group(overlay, group_id: String) -> bool:
	if str(overlay.call("current_page")) != "hub:%s" % group_id:
		push_error("Municipal category '%s' did not open." % group_id)
		return false
	var page := overlay.find_child("MunicipalHubGroup_%s" % group_id, true, false) as Control
	var choices := page.find_child("MenuChoices", true, false) as GridContainer if page != null else null
	if choices == null or choices.get_child_count() != 3:
		push_error("Municipal category '%s' must expose exactly three destinations." % group_id)
		return false
	var visible_pictures := 0
	for picture_variant in page.find_children("*", "TextureRect", true, false):
		if (picture_variant as TextureRect).is_visible_in_tree():
			visible_pictures += 1
	if visible_pictures != 3:
		push_error("Municipal category '%s' must expose three illustrated destinations; found %d." % [group_id, visible_pictures])
		return false
	return true


func _validate_start_screen(screen) -> bool:
	if screen == null or not is_instance_valid(screen) or not screen.is_visible_in_tree():
		push_error("Game did not boot into a visible start screen.")
		return false
	if screen.new_game_button == null or screen.continue_game_button == null:
		push_error("Start screen is missing new or continue game actions.")
		return false
	if screen.background_picture == null or screen.background_picture.texture.resource_path != "res://assets/images/world/backgrounds/city-map-background.png":
		push_error("Start screen does not reuse the city background image.")
		return false
	var logical_rect := Rect2(Vector2.ZERO, _capture_logical_size())
	for button in [screen.new_game_button, screen.continue_game_button]:
		if not logical_rect.encloses((button as Button).get_global_rect()):
			push_error("Start action is outside the logical viewport: %s." % (button as Button).get_global_rect())
			return false
	print("Start screen validation passed at logical=%s." % _capture_logical_size())
	return true


func _validate_start_loading(screen) -> bool:
	if screen == null or not screen.is_visible_in_tree() or not screen.is_loading():
		push_error("Start loading state is not visible during progress animation.")
		return false
	var progress := float(screen.progress_bar.value)
	if progress <= 0.0 or progress >= 100.0:
		push_error("Start loading capture is not an intermediate progress state: %.1f." % progress)
		return false
	if not screen.loading_label.is_visible_in_tree() or not screen.progress_label.text.contains("%"):
		push_error("Loading state omits its status or percentage label.")
		return false
	print("Start loading validation passed at %.1f%%." % progress)
	return true


func _validate_main_hud(scene) -> bool:
	var logical_size := _capture_logical_size()
	var map_viewport = scene.get("map_viewport")
	if map_viewport == null or not is_instance_valid(map_viewport):
		push_error("Readability capture could not find the main map viewport.")
		return false
	if map_viewport.size.x < logical_size.x * 0.94 or map_viewport.size.y < logical_size.y * 0.94:
		push_error("Map viewport does not cover at least 94%% of the fullscreen logical area: map=%s logical=%s." % [map_viewport.size, logical_size])
		return false
	if scene.find_child("MapInfoHud", true, false) != null:
		push_error("Obstructive lower-left MapInfoHud is still present.")
		return false
	if scene.find_child("MapMetaHud", true, false) != null:
		push_error("Redundant top-right MapMetaHud is still present.")
		return false

	var action_dock := scene.find_child("ActionDock", true, false) as Control
	if action_dock == null or not is_instance_valid(action_dock) or not action_dock.is_visible_in_tree():
		push_error("Readability capture could not find the visible ActionDock.")
		return false
	var dock_rect := action_dock.get_global_rect()
	var dock_center := dock_rect.get_center()
	if dock_center.x <= logical_size.x * 0.5 or dock_center.y <= logical_size.y * 0.5:
		push_error("ActionDock is not positioned in the lower-right quadrant: rect=%s logical=%s." % [dock_rect, logical_size])
		return false
	if dock_rect.end.x > logical_size.x + 1.0 or dock_rect.end.y > logical_size.y + 1.0:
		push_error("ActionDock extends outside the logical viewport: rect=%s logical=%s." % [dock_rect, logical_size])
		return false
	if logical_size.x - dock_rect.end.x > 32.0 or logical_size.y - dock_rect.end.y > 32.0:
		push_error("ActionDock is not anchored close enough to the lower-right corner: rect=%s logical=%s." % [dock_rect, logical_size])
		return false

	var hud_buttons := action_dock.find_children("*", "Button", true, false)
	if hud_buttons.size() != 3:
		push_error("ActionDock must contain exactly 3 global HUD buttons; found %d." % hud_buttons.size())
		return false
	for button_variant in hud_buttons:
		var button := button_variant as Button
		var button_name := str(button.get_meta("semantic_label", button.text))
		if button.custom_minimum_size.x < 58.0 or button.custom_minimum_size.y < 58.0:
			push_error("HUD button '%s' has an undersized minimum: %s." % [button_name, button.custom_minimum_size])
			return false
		if button.size.x < 58.0 or button.size.y < 58.0:
			push_error("HUD button '%s' rendered smaller than 58×58: %s." % [button_name, button.size])
			return false
		var short_side := minf(button.size.x, button.size.y)
		var long_side := maxf(button.size.x, button.size.y)
		if short_side <= 0.0 or long_side / short_side > 1.15:
			push_error("HUD button '%s' is not visually close to square: %s." % [button_name, button.size])
			return false
		var captions := button.find_children("*", "Label", true, false)
		if captions.size() != 1 or (captions[0] as Label).get_theme_font_size("font_size") < 18:
			push_error("HUD button '%s' caption is smaller than 18px." % button_name)
			return false
	var action_pictures := action_dock.find_children("*", "TextureRect", true, false)
	if action_pictures.size() != 3:
		push_error("Picture-first ActionDock must contain 3 global illustrations; found %d." % action_pictures.size())
		return false
	var status_hud: Node = scene.find_child("StatusHud", true, false)
	var header_bars: Array[Node] = []
	if status_hud != null:
		header_bars = status_hud.find_children("*", "ProgressBar", true, false)
	if header_bars.size() != 8:
		push_error("Visual status HUD must contain 8 micro bars; found %d." % header_bars.size())
		return false
	var header_pictures: Array[Node] = []
	if status_hud != null:
		header_pictures = status_hud.find_children("*", "TextureRect", true, false)
	if header_pictures.size() != 8:
		push_error("Picture-first status HUD must contain 8 illustrations; found %d." % header_pictures.size())
		return false
	print("Main HUD validation: map=%s dock=%s buttons=%d logical=%s." % [map_viewport.size, dock_rect, hud_buttons.size(), logical_size])
	return true


func _validate_settings(settings) -> bool:
	if settings == null or not is_instance_valid(settings) or not settings.is_open():
		push_error("Unified settings overlay is not visible.")
		return false
	if settings.language_selector == null or settings.language_selector.choice_count() != 5:
		push_error("Settings overlay does not expose all five languages.")
		return false
	if settings.language_selector.visible_popup_item_count() != 5:
		push_error("Settings overlay must expose all five language choices on one popup page.")
		return false
	if not settings.language_selector.shows_all_choices():
		push_error("Settings overlay still enables More paging for languages.")
		return false
	if settings.light_button == null or settings.dark_button == null:
		push_error("Settings overlay is missing appearance controls.")
		return false
	var panel := settings.find_child("SettingsPanel", true, false) as Control
	if panel == null or not Rect2(Vector2.ZERO, _capture_logical_size()).encloses(panel.get_global_rect()):
		push_error("Settings panel is outside the logical viewport.")
		return false
	return true


func _validate_building_context(panel) -> bool:
	if panel == null or not is_instance_valid(panel) or not panel.is_visible_in_tree():
		push_error("Clicking a building did not expose the contextual action panel.")
		return false
	var logical_rect := Rect2(Vector2.ZERO, _capture_logical_size())
	if not logical_rect.encloses(panel.get_global_rect()):
		push_error("Building context extends outside the logical viewport: %s." % panel.get_global_rect())
		return false
	var actions: Dictionary = panel.get("_action_buttons")
	if actions.size() != 5:
		push_error("Building context must preserve all five actions; found %d." % actions.size())
		return false
	var root_actions := panel.get("_root_actions") as HBoxContainer
	if root_actions == null or not root_actions.visible or root_actions.get_child_count() != 3:
		push_error("Building context must initially reveal exactly three actions.")
		return false
	for action_id in ["style", "roof", "exterior", "maintenance", "demolish"]:
		if not actions.has(action_id):
			push_error("Building context is missing '%s'." % action_id)
			return false
		var button := actions[action_id] as Button
		if button.custom_minimum_size.x < 100.0 or button.custom_minimum_size.y < 58.0:
			push_error("Building action '%s' has an undersized click target: %s." % [action_id, button.custom_minimum_size])
			return false
	var pictures: Array[Node] = panel.find_children("*", "TextureRect", true, false)
	if pictures.size() != 6:
		push_error("Picture-first building context must preserve five actions plus its appearance gateway; found %d illustrations." % pictures.size())
		return false
	var visible_pictures := 0
	for picture_variant in pictures:
		if (picture_variant as TextureRect).is_visible_in_tree():
			visible_pictures += 1
	if visible_pictures != 3:
		push_error("Building context must reveal exactly three illustrated choices; found %d." % visible_pictures)
		return false
	print("Building context validation passed: rect=%s actions=%d." % [panel.get_global_rect(), actions.size()])
	return true


func _validate_blueprint_review(overlay) -> bool:
	var status := overlay.find_child("BlueprintReviewStatus", true, false) as Label
	var submit := overlay.find_child("SubmitBlueprintButton", true, false) as Button
	var l10n = root.get_node_or_null("L10n")
	var receipt_source := "✓ 已收件｜審核中｜剩餘 %d 個遊戲日"
	var reviewing_source := "審核中｜剩餘 %d 日"
	var receipt_template := str(l10n.text(receipt_source) if l10n != null else receipt_source)
	var reviewing_template := str(l10n.text(reviewing_source) if l10n != null else reviewing_source)
	var receipt_prefix := receipt_template.get_slice("%d", 0).strip_edges()
	var reviewing_prefix := reviewing_template.get_slice("%d", 0).strip_edges()
	if status == null or not status.is_visible_in_tree() or not status.text.begins_with(receipt_prefix):
		push_error("Blueprint review does not show an immediate in-page receipt.")
		return false
	var number_pattern := RegEx.new()
	number_pattern.compile("[0-9]+")
	if number_pattern.search_all(status.text).size() != 1 or status.text.contains("分鐘") or status.text.to_lower().contains("minute"):
		push_error("Blueprint review receipt must show only its remaining game days: %s." % status.text)
		return false
	if submit == null or not submit.disabled or not submit.text.begins_with(reviewing_prefix):
		push_error("Blueprint submit action does not visibly lock during review.")
		return false
	print("Blueprint review feedback validation passed: %s." % status.text)
	return true


func _validate_visual_data(overlay, expected_page: String) -> bool:
	if expected_page == "hub":
		var hub_pictures: Array = []
		for node in overlay.find_children("*", "TextureRect", true, false):
			if node.is_visible_in_tree():
				hub_pictures.append(node)
		if hub_pictures.size() != 3:
			push_error("Picture-first municipal hub must expose 3 broad illustrated choices; found %d." % hub_pictures.size())
			return false
		return true
	var visible_bars: Array = []
	for node in overlay.find_children("*", "ProgressBar", true, false):
		if node.is_visible_in_tree():
			visible_bars.append(node)
	var visible_buttons: Array = []
	for node in overlay.find_children("*", "Button", true, false):
		if node.is_visible_in_tree():
			visible_buttons.append(node)
	var visible_labels: Array = []
	for node in overlay.find_children("*", "Label", true, false):
		if node.is_visible_in_tree():
			visible_labels.append(node)
	if not _validate_page_scope(expected_page, visible_labels, visible_buttons):
		return false
	if expected_page == "city_data":
		var all_metric_cards: Array[Node] = overlay.find_children("MonthlyData*", "PanelContainer", true, false)
		var visible_metric_cards := 0
		for node in all_metric_cards:
			if node.is_visible_in_tree():
				visible_metric_cards += 1
		if all_metric_cards.size() != 9 or visible_metric_cards != 9:
			push_error("City data page must retain and display all nine monthly data cards; total=%d visible=%d." % [all_metric_cards.size(), visible_metric_cards])
			return false
		if visible_bars.size() != 0:
			push_error("City service overview uses structured cards instead of repeating current-value bars; found %d bars." % visible_bars.size())
			return false
		if _visible_benchmark_chart_count(overlay) != 9:
			push_error("City monthly overview must own all nine animated comparison charts.")
			return false
	if expected_page == "report" and visible_bars.size() != 0:
		push_error("Monthly report must not duplicate current HUD KPI bars; found %d." % visible_bars.size())
		return false
	if expected_page == "report" and _visible_benchmark_chart_count(overlay) != 0:
		push_error("Monthly report must not contain routine data charts.")
		return false
	if expected_page == "blueprint" and visible_bars.size() != 1:
		push_error("Blueprint page must expose only its workforce bar; found %d." % visible_bars.size())
		return false
	if expected_page == "blueprint":
		var visual_controls: Array = []
		for node in overlay.find_children("*", "TextureRect", true, false):
			if node.is_visible_in_tree():
				visual_controls.append(node)
		if visual_controls.size() < 4:
			push_error("Picture-first blueprint must expose its hero and current parameter illustrations; found %d." % visual_controls.size())
			return false
		var parameter_cards: Array[Node] = overlay.find_children("BlueprintCard_*", "PanelContainer", true, false)
		if parameter_cards.size() != 5:
			push_error("Blueprint must expose exactly five illustrated parameter cards; found %d." % parameter_cards.size())
			return false
	if expected_page == "buildings":
		if overlay.find_child("DemolishSelectedBuildingButton", true, false) != null:
			push_error("Building page duplicates the map's contextual demolition action.")
			return false
		var group_filters: Array[Node] = overlay.find_children("BuildingGroup_*", "Button", true, false)
		if group_filters.size() != 6:
			push_error("Picture-first building selector must preserve six category filters; found %d." % group_filters.size())
			return false
		var visible_group_filters := 0
		for filter in group_filters:
			if (filter as Button).icon == null:
				push_error("Building category filter '%s' has no illustration." % filter.name)
				return false
			if (filter as Button).is_visible_in_tree():
				visible_group_filters += 1
		if visible_group_filters > 2:
			push_error("Building selector reveals too many subgroup filters: %d." % visible_group_filters)
			return false
		var visible_building_cards := 0
		for node in overlay.find_children("BuildingCard_*", "Button", true, false):
			var card := node as Button
			if card.is_visible_in_tree():
				visible_building_cards += 1
				if card.icon == null:
					push_error("Visible building card '%s' has no illustration." % card.name)
					return false
		if visible_building_cards < 1 or visible_building_cards > 3:
			push_error("Building selector should show one concise category page; visible cards=%d." % visible_building_cards)
			return false
	if expected_page == "governance":
		var governance_tabs := overlay.find_child("GovernanceStatusTabs", true, false) as TabContainer
		if governance_tabs == null or governance_tabs.get_tab_count() != 3:
			push_error("Governance page must expose exactly three status tabs.")
			return false
		var expected_titles := ["已實施", "審核中", "未實施"]
		var l10n = root.get_node_or_null("L10n")
		for index in expected_titles.size():
			var expected_title: String = str(l10n.text(expected_titles[index]) if l10n != null else expected_titles[index])
			if not governance_tabs.get_tab_title(index).begins_with(expected_title):
				push_error("Governance tab %d must begin with '%s'." % [index, expected_title])
				return false
		var governance_cards: Array[Node] = overlay.find_children("GovernanceCard_*", "PanelContainer", true, false)
		if governance_cards.size() != 12:
			push_error("Governance page must retain 4 policy and 8 bill cards; found %d." % governance_cards.size())
			return false
		if overlay.find_children("GovernanceKindTag_Policy_*", "Label", true, false).size() != 4:
			push_error("Every policy must expose a policy tag.")
			return false
		if overlay.find_children("GovernanceKindTag_Bill_*", "Label", true, false).size() != 8:
			push_error("Every bill must expose a bill tag.")
			return false
		if overlay.find_child("SeparationOfPowersDashboard", true, false) != null or overlay.find_child("GovernmentBranchGrid", true, false) != null:
			push_error("Governance policy and bill page must not include the separation-of-powers dashboard.")
			return false
	if expected_page == "finance":
		var has_status_chip := false
		for label in visible_labels:
			if str(label.text).contains("●"):
				has_status_chip = true
				break
		if not has_status_chip:
			push_error("Finance page has no visual low/recommended/high status chip.")
			return false
		var fiscal_tabs := overlay.find_child("FiscalCategoryTabs", true, false) as TabContainer
		if fiscal_tabs == null or fiscal_tabs.get_tab_count() != 3:
			push_error("Finance page must expose three broad categories.")
			return false
		for fiscal_category_variant in fiscal_tabs.get_children():
			var subcategories := fiscal_category_variant as TabContainer
			if subcategories == null or subcategories.get_tab_count() != 2:
				push_error("Each finance category must reveal two subcategories.")
				return false
		var fiscal_scroll := overlay.find_child("稅率與公共事業費", true, false) as ScrollContainer
		if fiscal_scroll == null:
			push_error("Finance page must expose its responsive ScrollContainer.")
			return false
		var fiscal_sliders: Array[Node] = overlay.find_children("FiscalSlider_*", "HSlider", true, false)
		if _expected_fiscal_slider_names.is_empty():
			push_error("Finance page could not derive its slider count from the authoritative fiscal dictionaries.")
			return false
		var fiscal_slider_names: Array[String] = []
		for slider_variant in fiscal_sliders:
			fiscal_slider_names.append(str(slider_variant.name))
		fiscal_slider_names.sort()
		if fiscal_slider_names != _expected_fiscal_slider_names:
			push_error(
				"Finance page slider names must match the authoritative tax and fee dictionaries: actual=%s expected=%s." % [
					fiscal_slider_names,
					_expected_fiscal_slider_names,
				]
			)
			return false
	if expected_page == "public_affairs":
		var affairs_pictures: Array = []
		for node in overlay.find_children("*", "TextureRect", true, false):
			if node.is_visible_in_tree():
				affairs_pictures.append(node)
		var request_cards: Array[Node] = overlay.find_children("CitizenRequest_*", "PanelContainer", true, false)
		if request_cards.is_empty():
			push_error("Public-affairs page must automatically list active NPC requests.")
			return false
		var visible_request_cards := 0
		for request_card_variant in request_cards:
			if (request_card_variant as Control).is_visible_in_tree():
				visible_request_cards += 1
		if visible_request_cards > 3:
			push_error("Public-affairs reveals more than three requests: %d." % visible_request_cards)
			return false
		var npc_models: Array[Node] = overlay.find_children("CitizenNpcModel_*", "Button", true, false)
		var visible_npc_models := 0
		for npc_model_variant in npc_models:
			var npc_model := npc_model_variant as Button
			if npc_model.is_visible_in_tree():
				visible_npc_models += 1
				if str(npc_model.get_meta("model_source", "")) != "authoritative_npc_record":
					push_error("Public-affairs NPC model is not linked to an authoritative NPC record.")
					return false
		if affairs_pictures.size() != 1 or visible_npc_models != visible_request_cards:
			push_error("Public-affairs must expose one hero illustration plus one real NPC model per visible request; pictures=%d models=%d visible=%d." % [affairs_pictures.size(), visible_npc_models, visible_request_cards])
			return false
		if visible_bars.size() != 0:
			push_error("Public-affairs page must not duplicate HUD grievance/trust bars; found %d." % visible_bars.size())
			return false
		var request_buttons: Array[Node] = overlay.find_children("AcceptRequest_*", "Button", true, false)
		if request_buttons.size() != request_cards.size():
			push_error("Every NPC request must expose one processing action.")
			return false
	if expected_page in ["judicial", "oversight"]:
		if expected_page == "judicial":
			var courtroom_scenes: Array = []
			for node in overlay.find_children("CourtroomStage", "Control", true, false):
				if node.is_visible_in_tree():
					courtroom_scenes.append(node)
			if courtroom_scenes.size() != 1:
				push_error("Judicial page must expose one layered courtroom scene; found %d." % courtroom_scenes.size())
				return false
		else:
			var function_pictures: Array = []
			for node in overlay.find_children("FunctionIllustration", "TextureRect", true, false):
				if node.is_visible_in_tree():
					function_pictures.append(node)
			if function_pictures.size() != 1:
				push_error("Page '%s' must expose one dominant function illustration; found %d." % [expected_page, function_pictures.size()])
				return false
		var defense_actions: Node = null
		for node in overlay.find_children("DefenseActions", "HBoxContainer", true, false):
			if node.is_visible_in_tree():
				defense_actions = node
				break
		if defense_actions == null or defense_actions.get_child_count() != 3:
			push_error("Page '%s' must expose three defense actions." % expected_page)
			return false
		var enabled_defenses := 0
		var selected_defenses := 0
		for child in defense_actions.find_children("*DefenseButton", "Button", true, false):
			if not (child as Button).disabled:
				enabled_defenses += 1
				if (child as Button).text.begins_with("✓"):
					selected_defenses += 1
		if enabled_defenses != 3:
			push_error("Page '%s' must enable all three defense actions for an active case; found %d." % [expected_page, enabled_defenses])
			return false
		if selected_defenses != 1:
			push_error("Page '%s' must show exactly one submitted defense; found %d." % [expected_page, selected_defenses])
			return false
	if expected_page in ["buildings", "governance"]:
		var has_directional_effect := false
		for button in visible_buttons:
			var text := str(button.text)
			if text.contains("▲") or text.contains("▼"):
				has_directional_effect = true
				break
		if not has_directional_effect:
			push_error("Page '%s' has no directional visual effect tokens." % expected_page)
			return false
	print("Visual data validation '%s': bars=%d buttons=%d labels=%d." % [expected_page, visible_bars.size(), visible_buttons.size(), visible_labels.size()])
	return true


func _visible_benchmark_chart_count(root_node: Node) -> int:
	var count := 0
	for chart_variant in root_node.find_children("*", "Control", true, false):
		if chart_variant.has_method("baseline_value") and chart_variant.is_visible_in_tree():
			count += 1
	return count


func _validate_monthly_data_mode(scene, uses_previous_month: bool) -> bool:
	var data_grid := scene.get("municipal_overlay").find_child("MonthlyDataChartGrid", true, false) as GridContainer
	if data_grid == null or data_grid.get_child_count() != 9:
		push_error("City data must consolidate all nine charts in the monthly overview.")
		return false
	var net_chart = (scene.get("monthly_data_kpi_charts") as Dictionary).get("net")
	var security_chart = (scene.get("monthly_data_service_charts") as Dictionary).get("security")
	if net_chart == null or security_chart == null:
		push_error("City-data comparison validation could not find required charts.")
		return false
	if uses_previous_month:
		if (scene.get("monthly_report_history") as Array).is_empty():
			push_error("Second-month city data has no authoritative prior-month snapshot.")
			return false
		if not str(security_chart.difference_label.text).contains("上月"):
			push_error("Second-month city data does not state its prior-month comparison.")
			return false
		if not is_equal_approx(security_chart.safety_value(), 60.0) or not security_chart.has_safety_warning():
			push_error("Second-month city data lost the independent 60%% safety warning.")
			return false
	else:
		if not (scene.get("monthly_report_history") as Array).is_empty():
			push_error("First-month city data unexpectedly has prior-month history.")
			return false
		if not is_equal_approx(net_chart.baseline_value(), net_chart.safety_value()):
			push_error("First-month city data must compare finance directly with its safety line.")
			return false
	return true


func _validate_monthly_report_scope(scene) -> bool:
	var overlay = scene.get("municipal_overlay")
	var summary := overlay.find_child("MonthlySummary", true, false) as PanelContainer
	var updates := overlay.find_child("VersionUpdateAnnouncements", true, false) as PanelContainer
	if summary == null or updates == null:
		push_error("Monthly report must expose the major-event summary and version-update sections.")
		return false
	if overlay.find_child("MonthlyDataChartGrid", true, false) != null and overlay.find_child("MonthlyDataChartGrid", true, false).is_visible_in_tree():
		push_error("Monthly report must not display routine monthly data charts.")
		return false
	var report_label := scene.get("report_label") as Label
	var update_label := scene.get("announcement_label") as Label
	if report_label == null or not report_label.text.contains("建築完工") or not report_label.text.contains("陳情受理"):
		push_error("Monthly report does not show the prepared major events.")
		return false
	if update_label == null or not update_label.text.contains("城市數據與月報重新分工"):
		push_error("Monthly report does not render the version-update log.")
		return false
	return true


func _validate_page_scope(page_id: String, visible_labels: Array, visible_buttons: Array) -> bool:
	var visible_text := ""
	for label_variant in visible_labels:
		visible_text += "\n%s" % str((label_variant as Label).text)
	for button_variant in visible_buttons:
		visible_text += "\n%s" % str((button_variant as Button).text)
	var forbidden_by_page := {
		"buildings": ["居民請求", "民怨", "市政信任", "法院審判", "監察質詢", "委員名單", "強制執行", "儲存", "讀取"],
		"governance": ["三權分治", "行政權", "立法權", "司法權", "制衡軌跡", "居民請求", "民怨", "市政信任", "委員名單", "委員席次", "司法調查", "監察調查", "設計藍圖", "維修至", "拆除選取", "儲存", "讀取"],
		"blueprint": ["民怨", "滿意", "信任", "居民請求", "維護", "耐久", "司法", "監察", "委員", "強制執行", "儲存", "讀取"],
		# The courtroom may name the three judges assigned to the visible bench.
		# It must still avoid leaking the full committee roster or internal records.
		"judicial": ["委員名單", "委員席次", "任期", " personality_tags", "資料庫"],
		"oversight": ["委員名單", "委員席次", "任期", "沈知衡", "任書妍", " personality_tags", "資料庫"],
		"finance": ["居民請求", "委員名單", "法院審判", "監察質詢", "設計藍圖", "維修至", "拆除選取", "強制執行", "儲存", "讀取"],
		"public_affairs": ["民怨", "市政信任", "設計藍圖", "送審藍圖", "稅率", "公共事業費", "法院審判", "彈劾辯護", "維修至", "拆除選取", "強制執行"],
	}
	for term_variant in forbidden_by_page.get(page_id, []):
		var term := str(term_variant)
		if visible_text.contains(term):
			push_error("Municipal page '%s' leaks unrelated content '%s'." % [page_id, term])
			return false
	return true


func _validate_exit_confirmation(exit_confirmation) -> bool:
	if exit_confirmation == null or not is_instance_valid(exit_confirmation):
		push_error("Readability capture could not find the exit confirmation overlay.")
		return false
	if not exit_confirmation.is_visible_in_tree():
		push_error("Exit confirmation did not become visible after pressing the exit button.")
		return false
	var logical_size := _capture_logical_size()
	var logical_rect := Rect2(Vector2.ZERO, logical_size)
	for property_name in ["cancel_button", "confirm_button", "close_button"]:
		var button := exit_confirmation.get(property_name) as Button
		if button == null or not is_instance_valid(button) or not button.is_visible_in_tree():
			push_error("Exit confirmation control '%s' is missing or not visible." % property_name)
			return false
		var button_rect: Rect2 = button.get_global_rect()
		if not logical_rect.encloses(button_rect):
			push_error("Exit confirmation control '%s' is outside the logical viewport: rect=%s logical=%s." % [property_name, button_rect, logical_rect])
			return false
	print("Exit confirmation validation passed at logical=%s." % logical_size)
	return true


func _prepare_output_directories() -> bool:
	var output_arguments: PackedStringArray = []
	var native_output_arguments: PackedStringArray = []
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(OUTPUT_ARGUMENT_PREFIX):
			output_arguments.append(argument.substr(OUTPUT_ARGUMENT_PREFIX.length()))
		if argument.begins_with(NATIVE_OUTPUT_ARGUMENT_PREFIX):
			native_output_arguments.append(argument.substr(NATIVE_OUTPUT_ARGUMENT_PREFIX.length()))
	if output_arguments.size() != 1:
		push_error("UI capture requires exactly one %s<absolute-directory> user argument." % OUTPUT_ARGUMENT_PREFIX)
		return false
	if native_output_arguments.size() != 1:
		push_error("UI capture requires exactly one %s<absolute-directory> user argument." % NATIVE_OUTPUT_ARGUMENT_PREFIX)
		return false

	var candidate := str(output_arguments[0]).strip_edges().simplify_path()
	var native_candidate := str(native_output_arguments[0]).strip_edges().simplify_path()
	if candidate.is_empty() or not candidate.is_absolute_path() or native_candidate.is_empty() or not native_candidate.is_absolute_path():
		push_error("UI capture output directories must be absolute: offscreen=%s native=%s" % [candidate, native_candidate])
		return false
	if candidate == native_candidate:
		push_error("Native and offscreen evidence directories must be distinct.")
		return false
	for directory in [native_candidate, candidate]:
		if DirAccess.dir_exists_absolute(directory) or FileAccess.file_exists(directory):
			push_error("UI capture output directory already exists; evidence is append-only: %s" % directory)
			return false
		# The wrapper creates the parent OutputRoot first. A single-directory create
		# preserves the append-only race contract: ERR_ALREADY_EXISTS is a failure.
		var create_error := DirAccess.make_dir_absolute(directory)
		if create_error != OK:
			push_error("Could not create UI capture output directory %s: %d" % [directory, create_error])
			return false

	_output_directory = candidate
	_native_output_directory = native_candidate
	for filename_variant in OUTPUTS.values():
		var filename := str(filename_variant)
		var target := _output_directory.path_join(filename)
		if FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(target):
			push_error("UI capture target already exists: %s" % target)
			return false
	for filename_variant in NATIVE_OUTPUTS.values():
		var filename := str(filename_variant)
		var target := _native_output_directory.path_join(filename)
		if FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(target):
			push_error("Native UI capture target already exists: %s" % target)
			return false
	return true


func _state_for_filename(filename: String) -> String:
	for state_variant in OUTPUTS.keys():
		var state := str(state_variant)
		if str(OUTPUTS[state]) == filename:
			return state
	return ""


func _validate_capture_content(image: Image, state: String) -> bool:
	var image_size := image.get_size()
	var sample_count := CAPTURE_SANITY_SAMPLE_COLUMNS * CAPTURE_SANITY_SAMPLE_ROWS
	var opaque_count := 0
	var luminance_sum := 0.0
	var luminance_square_sum := 0.0
	var luminance_min := 255.0
	var luminance_max := 0.0
	for sample_y in range(CAPTURE_SANITY_SAMPLE_ROWS):
		var pixel_y := clampi(
			floori((float(sample_y) + 0.5) * float(image_size.y) / float(CAPTURE_SANITY_SAMPLE_ROWS)),
			0,
			image_size.y - 1
		)
		for sample_x in range(CAPTURE_SANITY_SAMPLE_COLUMNS):
			var pixel_x := clampi(
				floori((float(sample_x) + 0.5) * float(image_size.x) / float(CAPTURE_SANITY_SAMPLE_COLUMNS)),
				0,
				image_size.x - 1
			)
			var pixel := image.get_pixel(pixel_x, pixel_y)
			if pixel.a >= 0.99:
				opaque_count += 1
			var luminance := (0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b) * 255.0
			luminance_sum += luminance
			luminance_square_sum += luminance * luminance
			luminance_min = minf(luminance_min, luminance)
			luminance_max = maxf(luminance_max, luminance)

	var opaque_ratio := float(opaque_count) / float(sample_count)
	var luminance_mean := luminance_sum / float(sample_count)
	var luminance_variance := maxf(
		0.0,
		luminance_square_sum / float(sample_count) - luminance_mean * luminance_mean
	)
	var luminance_sd := sqrt(luminance_variance)
	var luminance_range := luminance_max - luminance_min
	if (
		opaque_ratio < CAPTURE_MIN_OPAQUE_RATIO
		or luminance_sd < CAPTURE_MIN_LUMINANCE_SD
		or luminance_range < CAPTURE_MIN_LUMINANCE_RANGE
	):
		push_error(
			"Capture %s failed content sanity: opaque_ratio=%.4f luminance_sd=%.3f luminance_range=%.3f." % [
				state,
				opaque_ratio,
				luminance_sd,
				luminance_range,
			]
		)
		return false
	print(
		"Capture %s content sanity passed: opaque_ratio=%.4f luminance_sd=%.3f luminance_range=%.3f." % [
			state,
			opaque_ratio,
			luminance_sd,
			luminance_range,
		]
	)
	return true


func _native_state_for_filename(filename: String) -> String:
	for state_variant in NATIVE_OUTPUTS.keys():
		var state := str(state_variant)
		if str(NATIVE_OUTPUTS[state]) == filename:
			return state
	return ""


func _save_native_capture(filename: String, landmark: Control) -> bool:
	var state := _native_state_for_filename(filename)
	if state.is_empty():
		push_error("Native UI capture filename is not part of the four-state contract: %s" % filename)
		return false
	if _native_captured_states.has(state):
		push_error("Native UI capture state was written more than once: %s" % state)
		return false
	if _capture_viewport != root or _capture_surface_kind != "native_fullscreen_root":
		push_error("Native UI capture is not attached directly to the root viewport for %s." % state)
		return false
	if landmark == null or not is_instance_valid(landmark) or not landmark.is_visible_in_tree():
		push_error("Native UI landmark is missing or hidden for %s." % state)
		return false

	var path := _native_output_directory.path_join(filename)
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
		push_error("Native UI capture target already exists; refusing overwrite: %s" % path)
		return false
	var image := root.get_texture().get_image()
	var image_size := image.get_size()
	var window_size := DisplayServer.window_get_size()
	var root_texture := root.get_texture()
	var root_texture_size := Vector2i(root_texture.get_width(), root_texture.get_height())
	var logical_size_value := root.get_visible_rect().size
	var logical_size := Vector2i(roundi(logical_size_value.x), roundi(logical_size_value.y))
	var mode := DisplayServer.window_get_mode()
	var is_fullscreen := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if (
		not is_fullscreen
		or image_size != _native_physical_size
		or image_size != window_size
		or window_size != _native_window_size
		or root_texture_size != _native_backing_size
		or logical_size != _native_logical_size
		or image_size.x < MINIMUM_NATIVE_PHYSICAL_SIZE.x
		or image_size.y < MINIMUM_NATIVE_PHYSICAL_SIZE.y
	):
		push_error(
			"Native UI surface drifted for %s: image=%s window=%s root_texture=%s logical=%s expected_capture=%s expected_backing=%s expected_window=%s expected_logical=%s." % [
				state,
				image_size,
				window_size,
				root_texture_size,
				logical_size,
				_native_physical_size,
				_native_backing_size,
				_native_window_size,
				_native_logical_size,
			]
		)
		return false
	var logical_rect := Rect2(Vector2.ZERO, Vector2(_native_logical_size))
	var landmark_rect := landmark.get_global_rect()
	if landmark_rect.size.x <= 0.0 or landmark_rect.size.y <= 0.0 or not logical_rect.encloses(landmark_rect):
		push_error("Native UI landmark is clipped for %s: rect=%s logical=%s." % [state, landmark_rect, logical_rect])
		return false
	if not _validate_capture_content(image, "native:%s" % state):
		return false

	var error := image.save_png(path)
	if error != OK:
		push_error("Failed to save native UI capture %s: %d" % [path, error])
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not reopen native UI capture for evidence: %s" % path)
		return false
	var byte_count := file.get_length()
	file.close()
	var sha256 := FileAccess.get_sha256(path).to_lower()
	if byte_count <= 0 or sha256.length() != 64 or _native_captured_hashes.has(sha256):
		push_error("Native UI capture evidence is incomplete or duplicated for %s: bytes=%d sha256=%s" % [path, byte_count, sha256])
		return false
	_native_capture_records.append({
		"state": state,
		"filename": filename,
		"width": image_size.x,
		"height": image_size.y,
		"bytes": byte_count,
		"sha256": sha256,
		"landmark": str(NATIVE_LANDMARKS[state]),
		"landmark_rect": [landmark_rect.position.x, landmark_rect.position.y, landmark_rect.size.x, landmark_rect.size.y],
	})
	_native_captured_states[state] = true
	_native_captured_hashes[sha256] = state
	print("Saved native root UI %s at physical=%s logical=%s sha256=%s." % [path, image_size, logical_size, sha256])
	return true


func _publish_native_capture_result() -> bool:
	if _native_capture_records.size() != NATIVE_OUTPUTS.size() or _native_captured_states.size() != NATIVE_OUTPUTS.size():
		push_error(
			"Native UI capture result is incomplete: records=%d states=%d required=%d" % [
				_native_capture_records.size(),
				_native_captured_states.size(),
				NATIVE_OUTPUTS.size(),
			]
		)
		return false
	for state_variant in NATIVE_OUTPUTS.keys():
		if not _native_captured_states.has(str(state_variant)):
			push_error("Native UI capture result is missing state: %s" % state_variant)
			return false
	var window_size := DisplayServer.window_get_size()
	var root_texture := root.get_texture()
	var root_texture_size := Vector2i(root_texture.get_width(), root_texture.get_height())
	var logical_size_value := root.get_visible_rect().size
	var measured_logical_size := Vector2i(roundi(logical_size_value.x), roundi(logical_size_value.y))
	var mode := DisplayServer.window_get_mode()
	var mode_name := "exclusive_fullscreen" if mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN else "fullscreen"
	if (
		(mode != DisplayServer.WINDOW_MODE_FULLSCREEN and mode != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		or window_size != _native_window_size
		or window_size != _native_physical_size
		or root_texture_size != _native_backing_size
		or measured_logical_size != _native_logical_size
		or DisplayServer.window_get_current_screen() != _native_screen_index
	):
		push_error("Native GUI result cannot be published after display-surface drift.")
		return false

	var result_path := _native_output_directory.path_join(NATIVE_RESULT_FILENAME)
	var partial_path := result_path + ".partial"
	if FileAccess.file_exists(result_path) or DirAccess.dir_exists_absolute(result_path) or FileAccess.file_exists(partial_path) or DirAccess.dir_exists_absolute(partial_path):
		push_error("Native UI capture result target already exists; refusing overwrite: %s" % result_path)
		return false
	var result := {
		"schema_version": 1,
		"suite": "mayor-simulator-native-window-ui-acceptance",
		"status": "PASS",
		"native_gui_status": "PASS",
		"capture_role": "native_gui",
		"started_at_utc": _native_started_at_utc,
		"finished_at_utc": _utc_now(),
		"output_directory": _native_output_directory,
		"capture_surface_kind": "native_fullscreen_root",
		"scene_parent": "root_window",
		"uses_subviewport": false,
		"capture_surface_mirrored": false,
		"window_mode": mode_name,
		"physical_size": [_native_physical_size.x, _native_physical_size.y],
		"physical_size_role": "native_root_capture_and_os_window_pixels",
		"logical_size": [_native_logical_size.x, _native_logical_size.y],
		"window_size": [window_size.x, window_size.y],
		"window_size_role": "os_fullscreen_window",
		"root_texture_size": [root_texture_size.x, root_texture_size.y],
		"display_server": DisplayServer.get_name(),
		"current_screen_index": _native_screen_index,
		"current_screen_dpi": _native_screen_dpi,
		"current_screen_scale": _native_screen_scale,
		"current_screen_size": [_native_screen_size.x, _native_screen_size.y],
		"required_capture_count": NATIVE_OUTPUTS.size(),
		"capture_count": _native_capture_records.size(),
		"captures": _native_capture_records,
	}
	var result_file := FileAccess.open(partial_path, FileAccess.WRITE)
	if result_file == null:
		push_error("Could not open native UI capture result for writing: %s" % partial_path)
		return false
	result_file.store_string(JSON.stringify(result, "\t"))
	result_file.flush()
	result_file.close()
	var publish_error := DirAccess.rename_absolute(partial_path, result_path)
	if publish_error != OK:
		push_error("Could not atomically publish native UI capture result %s: %d" % [result_path, publish_error])
		return false
	print("Native GUI acceptance result published with four direct-root states.")
	return true


func _save_capture(filename: String) -> bool:
	var state := _state_for_filename(filename)
	if state.is_empty():
		push_error("UI capture filename is not part of the 33-state contract: %s" % filename)
		return false
	if _captured_states.has(state):
		push_error("UI capture state was written more than once: %s" % state)
		return false
	if _capture_surface_kind != "offscreen_subviewport" or _active_capture_viewport() == root:
		push_error("The 33-state evidence contract must be captured only from the isolated offscreen SubViewport.")
		return false
	var path := _output_directory.path_join(filename)
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
		push_error("UI capture target already exists; refusing overwrite: %s" % path)
		return false

	var image := _active_capture_viewport().get_texture().get_image()
	var image_size := image.get_size()
	var window_size := DisplayServer.window_get_size()
	var logical_size_value := _capture_logical_size()
	var logical_size := Vector2i(roundi(logical_size_value.x), roundi(logical_size_value.y))
	if image_size != REQUIRED_PHYSICAL_SIZE:
		push_error("Capture %s must be exactly %s; actual=%s." % [state, REQUIRED_PHYSICAL_SIZE, image_size])
		return false
	if (
		_capture_surface_kind != "offscreen_subviewport"
		and (abs(image_size.x - window_size.x) > 1 or abs(image_size.y - window_size.y) > 1)
	):
		push_error("Capture size %s does not match fullscreen window backing size %s for %s." % [image_size, window_size, path])
		return false
	if _capture_surface_kind == "offscreen_subviewport" and logical_size != REQUIRED_FALLBACK_LOGICAL_SIZE:
		push_error("Offscreen capture %s must preserve the exact logical UI area %s; actual=%s." % [path, REQUIRED_FALLBACK_LOGICAL_SIZE, logical_size])
		return false
	if logical_size.x < 1280 or logical_size.y < 720:
		push_error("Capture %s has insufficient logical UI area for fullscreen readability acceptance: %s." % [path, logical_size])
		return false
	if not _validate_capture_content(image, state):
		return false

	var error := image.save_png(path)
	if error != OK:
		push_error("Failed to save UI capture %s: %d" % [path, error])
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not reopen UI capture for evidence: %s" % path)
		return false
	var byte_count := file.get_length()
	file.close()
	var sha256 := FileAccess.get_sha256(path).to_lower()
	if byte_count <= 0 or sha256.length() != 64:
		push_error("UI capture evidence is incomplete for %s: bytes=%d sha256=%s" % [path, byte_count, sha256])
		return false
	_capture_records.append({
		"state": state,
		"filename": filename,
		"width": image_size.x,
		"height": image_size.y,
		"bytes": byte_count,
		"sha256": sha256,
	})
	_captured_states[state] = true
	print("Saved %s at physical=%s logical=%s sha256=%s." % [path, image_size, logical_size, sha256])
	return true


func _publish_capture_result() -> bool:
	if _capture_records.size() != OUTPUTS.size() or _captured_states.size() != OUTPUTS.size():
		push_error("UI capture result is incomplete: records=%d states=%d required=%d" % [_capture_records.size(), _captured_states.size(), OUTPUTS.size()])
		return false
	for state_variant in OUTPUTS.keys():
		if not _captured_states.has(str(state_variant)):
			push_error("UI capture result is missing state: %s" % state_variant)
			return false
	var logical_size_value := _capture_logical_size()
	var measured_logical_size := Vector2i(roundi(logical_size_value.x), roundi(logical_size_value.y))
	if _capture_surface_kind != "offscreen_subviewport" or measured_logical_size != REQUIRED_FALLBACK_LOGICAL_SIZE:
		push_error(
			"Offscreen evidence result requires surface=offscreen_subviewport and measured logical=%s; actual surface=%s logical=%s." % [
				REQUIRED_FALLBACK_LOGICAL_SIZE,
				_capture_surface_kind,
				measured_logical_size,
			]
		)
		return false

	var result_path := _output_directory.path_join(RESULT_FILENAME)
	var partial_path := result_path + ".partial"
	if FileAccess.file_exists(result_path) or DirAccess.dir_exists_absolute(result_path) or FileAccess.file_exists(partial_path) or DirAccess.dir_exists_absolute(partial_path):
		push_error("UI capture result target already exists; refusing overwrite: %s" % result_path)
		return false
	var result := {
		"schema_version": 1,
		"suite": "mayor-simulator-ui-capture-acceptance",
		"status": "PASS",
		"offscreen_evidence_status": "PASS",
		"capture_role": "offscreen_evidence_only",
		"started_at_utc": _started_at_utc,
		"finished_at_utc": _utc_now(),
		"output_directory": _output_directory,
		"capture_surface_kind": _capture_surface_kind,
		"capture_surface_mirrored": _capture_surface_mirrored,
		"native_window_size": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"required_capture_count": OUTPUTS.size(),
		"capture_count": _capture_records.size(),
		"physical_size": [REQUIRED_PHYSICAL_SIZE.x, REQUIRED_PHYSICAL_SIZE.y],
		"logical_size": [measured_logical_size.x, measured_logical_size.y],
		"captures": _capture_records,
	}
	var result_file := FileAccess.open(partial_path, FileAccess.WRITE)
	if result_file == null:
		push_error("Could not open UI capture result for writing: %s" % partial_path)
		return false
	result_file.store_string(JSON.stringify(result, "\t"))
	result_file.flush()
	result_file.close()
	var publish_error := DirAccess.rename_absolute(partial_path, result_path)
	if publish_error != OK:
		push_error("Could not atomically publish UI capture result %s: %d" % [result_path, publish_error])
		return false
	return true
