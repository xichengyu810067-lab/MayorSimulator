extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const TEST_SAVE_PATH := "res://tests/.start_screen_roundtrip.json"
const BACKGROUND_PATH := "res://assets/images/world/backgrounds/city-map-background.png"

var _failed := false
var _load_action_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_save()
	root.content_scale_size = Vector2i(1920, 1080)
	root.size = Vector2i(1920, 1080)

	var first = _new_main()
	await _settle(3)
	_check(first.start_screen != null and first.start_screen.visible, "game opens on the start screen")
	_check(first.vertical_slice.is_time_paused(), "simulation is paused before choosing a game mode")
	_check(first.start_screen.new_game_button != null and first.start_screen.continue_game_button != null, "start screen exposes new and continue buttons")
	_check(first.start_screen.save_status_label.get_theme_font_size("font_size") >= 18, "start-screen save status uses at least 18px text")
	_check(first.start_screen.background_picture.texture.resource_path == BACKGROUND_PATH, "start screen reuses the game background image")
	first.start_save_path = TEST_SAVE_PATH
	_check(first.vertical_slice.save_path == TEST_SAVE_PATH, "all subsystem autosaves follow the active game save path")
	first.start_screen.set_continue_available(false)
	first.start_screen.animation_duration = 0.04
	first.start_screen.load_action_requested.connect(_on_load_action)
	first.start_screen.continue_game_button.emit_signal("pressed")
	await _wait_for_loading(first)
	_check(first.start_screen.visible, "failed continue remains on the start screen")
	_check(not first.start_screen.save_status_label.text.strip_edges().is_empty(), "missing save produces a visible localized explanation")
	_check(is_equal_approx(first.start_screen.progress_bar.value, 100.0), "continue attempt still completes the loading progress animation")

	first.start_screen.new_game_button.emit_signal("pressed")
	await _wait_for_loading(first)
	_check(not first.start_screen.visible and first._game_started, "new game enters the city after loading")
	_check(first.tutorial_overlay != null and first.tutorial_overlay.is_open(), "new game starts with the story tutorial")
	_check(first.onboarding_progress.is_story_pending(), "new game begins at the story phase before any city interaction")
	_check(first.onboarding_guide != null and not first.onboarding_guide.is_open(), "story-pending onboarding does not open the product guide before the story completes")
	_check(first.vertical_slice.is_time_paused(), "story tutorial pauses game time")
	first.tutorial_overlay.close_as_completed(false)
	await _settle(30)
	_check(first.tutorial_completed and first.onboarding_progress.is_active(), "story completion preserves the legacy story-seen flag without claiming onboarding completion")
	_check(first.onboarding_progress.current_target() == "build", "story completion prepares the first canonical target")
	_check(first.onboarding_guide.is_open() and first.onboarding_guide.is_product_mode(), "story completion opens the product guide for the build target")
	_check(not first.vertical_slice.is_time_paused(), "new game resumes simulation time after loading")
	_check(_load_action_count == 2, "both continue and new game execute the shared loading midpoint")
	_check(first.city_grid.count("") == first.CELL_COUNT, "new game starts with a completely empty map")
	_check(first.vertical_slice.session.state.buildings.is_empty(), "new game has no saved buildings")
	_check(first.vertical_slice.construction.jobs.is_empty() and first.vertical_slice.construction.reviews.is_empty(), "new game has no construction or blueprint history")
	_check(first.vertical_slice.session.state.event_book.is_empty(), "new game has no prior event history")
	var opening_entries: Array[Dictionary] = first.vertical_slice.session.state.ledger.get_entries()
	_check(opening_entries.size() == 1 and str(opening_entries[0].get("reason_tag", "")) == "opening_balance", "new game only records starting capital, not historical income")
	_check(first.vertical_slice.has_save_game(TEST_SAVE_PATH), "new game immediately creates a continue save")
	_check(first._autosave_count >= 2 and first._last_autosave_reason == "onboarding:story_completed", "new game creation and story progress are both autosaved")

	first.city_grid[18] = "住宅"
	first.building_customizations[18] = {"variant": 2, "roof": 3, "wall": 4}
	var residence_record: Dictionary = first.vertical_slice.register_existing_building(18, "住宅", first.building_customizations[18])
	first.call("_sync_vertical_state")
	_check(PackedStringArray(residence_record.get("resident_ids", [])).size() == 28, "seeded residence stores its exact resident IDs")
	_check(first.population == 328, "seeded residence updates main population from the canonical system")
	_check(first.vertical_slice.session.state.npcs.size() == 328 and int(first.vertical_slice.session.state.metrics.get("population", -1)) == 328, "seeded residence keeps core population mirrors consistent")
	var action_save_count: int = first._autosave_count
	first.call("_on_tax_changed", 17.0, "income")
	_check(int(first.tax_rates["income"]) != 17, "a tax slider change remains a draft before preview")
	_check(first._autosave_count == action_save_count, "an unapplied tax draft does not autosave")
	first.call("_show_fiscal_preview")
	_check(int(first.tax_rates["income"]) != 17, "preview keeps the tax draft separate from authoritative settings")
	_check(first._autosave_count == action_save_count, "preview does not autosave or commit the fiscal draft")
	first.call("_apply_fiscal_draft")
	_check(int(first.tax_rates["income"]) == 17, "execute commits the previewed tax draft before saving")
	_check(first._autosave_count == action_save_count + 1 and first._last_autosave_reason == "action:fiscal_draft_applied", "execute autosaves the complete fiscal draft exactly once")
	_check(FileAccess.file_exists(ProjectSettings.globalize_path(TEST_SAVE_PATH) + ".bak"), "autosave retains the immediately previous valid snapshot")
	first.call("_toggle_policy", true, "環保政策")
	for _day in range(3):
		first.call("_next_day")
	var saved_day: int = int(first.vertical_slice.game_day())
	var event_save_count: int = first._autosave_count
	first.call("_next_day")
	_check(first._autosave_count > event_save_count and first._last_autosave_reason.begins_with("event:"), "a game-day event autosaves")
	saved_day = int(first.vertical_slice.game_day())
	var interval_save_count: int = first._autosave_count
	first._autosave_elapsed_seconds = first.AUTOSAVE_INTERVAL_SECONDS - 0.1
	first.call("_update_autosave_timer", 0.2)
	_check(first._autosave_count > interval_save_count and first._last_autosave_reason == "interval:10_real_minutes", "ten active real minutes autosaves")
	var saved_city_metrics := {
		"satisfaction": 48,
		"security": 43,
		"environment": 44,
		"traffic": 45,
		"education": 46,
		"healthcare": 47,
	}
	_check(first.vertical_slice.session.state.set_metric_values(saved_city_metrics), "authoritative city metrics accept a pre-save regression fixture")
	_check(first.call("_autosave", "test:city_metric_authority_roundtrip") == OK, "authoritative city metric fixture is saved")
	await TestCleanup.release_fixtures(self, [first])

	var resumed = _new_main()
	await _settle(3)
	resumed.start_save_path = TEST_SAVE_PATH
	resumed.start_screen.set_continue_available(true)
	var available_status_color: Color = resumed.start_screen.save_status_label.get_theme_color("font_color")
	_check(available_status_color == resumed.start_screen.SAVE_AVAILABLE_COLOR, "available-save status uses the dedicated success color")
	_check(available_status_color.get_luminance() < 0.40, "available-save status stays dark enough to read on the cream card")
	resumed.start_screen.animation_duration = 0.04
	resumed.start_screen.continue_game_button.emit_signal("pressed")
	await _wait_for_loading(resumed)
	_check(not resumed.start_screen.visible and resumed._game_started, "continue enters the saved city after loading")
	_check(resumed.tutorial_completed and resumed.onboarding_progress.current_target() == "build", "continue restores the legacy story-seen flag and exact schema-9 onboarding progress")
	_check(not resumed.tutorial_overlay.is_open(), "continue does not replay the completed story overlay")
	_check(resumed.onboarding_guide.is_open() and resumed.onboarding_guide.is_product_mode(), "continue restores the visible product guide for the build target")
	_check(int(resumed.vertical_slice.game_day()) == saved_day, "continue restores the saved game day")
	_check(not resumed.vertical_slice.is_time_paused(), "continued game resumes time only after loading finishes")
	_check(not resumed.city_grid.is_empty() and resumed.city_grid[18] == "住宅", "continue rebuilds saved buildings on the map")
	var resumed_residence: Dictionary = resumed.vertical_slice.get_building_by_tile(18)
	_check(PackedStringArray(resumed_residence.get("resident_ids", [])).size() == 28, "continue restores exact residence ownership IDs")
	_check(resumed.population == 328 and resumed.vertical_slice.population.population_count() == 328, "continue restores authoritative residence population")
	_check(resumed.vertical_slice.session.state.npcs.size() == 328 and int(resumed.vertical_slice.session.state.metrics.get("population", -1)) == 328, "continue restores consistent core population mirrors")
	_check(int(resumed.tax_rates["income"]) == 17, "continue restores tax settings")
	_check(bool(resumed.active_policies["環保政策"]), "continue restores policy state")
	_check(int(resumed.building_customizations[18]["variant"]) == 2 and int(resumed.building_customizations[18]["roof"]) == 3, "continue restores building appearance")
	for metric_name: String in saved_city_metrics.keys():
		_check(
			int(resumed.vertical_slice.session.state.metric_value(metric_name, -1)) == int(saved_city_metrics[metric_name]),
			"continue preserves authoritative %s instead of re-deriving it while rebuilding the map" % metric_name
		)
	_check(resumed.security == 43 and resumed.environment == 44 and resumed.traffic == 45, "main compatibility getters expose the restored CityState metrics")

	_cleanup_save()
	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Start screen new/continue loading test passed.")
	await TestCleanup.finish(self, [resumed], exit_code)


func _new_main():
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main := packed.instantiate()
	root.add_child(main)
	return main


func _wait_for_loading(main) -> void:
	for _frame in range(120):
		await process_frame
		if not main.start_screen.is_loading():
			return
	_fail("loading animation did not finish within 120 frames")


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame


func _on_load_action(_mode: String) -> void:
	_load_action_count += 1


func _cleanup_save() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	for candidate in [absolute_path, absolute_path + ".tmp", absolute_path + ".bak"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _fail(message: String) -> void:
	_failed = true
	push_error("Start screen check failed: %s" % message)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)
