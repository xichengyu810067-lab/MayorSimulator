extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const BACKGROUND_PATH := "res://assets/images/world/backgrounds/city-map-background.png"
const TEST_SAVE_PATH := "user://mayor_simulator/tests/main_integration_autosave.json"

var _failed := false
var _quit_signal_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Profiling instrumentation is inert in a normal integration run. The
	# performance runner has to opt in before it can emit markers or hold frames.
	var performance_profile_only := "--performance-profile-lazy-overlay" in OS.get_cmdline_user_args()
	var performance_profile_hold_ms := _performance_profile_hold_ms(performance_profile_only)
	# Headless tests need a deterministic desktop-sized layout reference. This is
	# deliberately not the visual acceptance test; the capture suite validates the
	# real fullscreen window separately.
	root.content_scale_size = Vector2i(1920, 1080)
	root.size = Vector2i(1920, 1080)
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await process_frame
	var l10n = root.get_node_or_null("L10n")
	_check(main.start_screen != null and main.start_screen.visible, "game boots into the new/continue start screen")
	_check(main.vertical_slice.is_time_paused(), "simulation is paused while the start screen is open")
	_check(
		main.get_visible_npc_actors().all(func(button: Button) -> bool: return button.tooltip_text.is_empty() and button.mouse_filter == Control.MOUSE_FILTER_IGNORE),
		"start screen disables resident hover tooltips and pointer input"
	)
	_check(
		main.grid_buttons.all(func(button: Button) -> bool: return button.tooltip_text.is_empty() and button.mouse_filter == Control.MOUSE_FILTER_IGNORE),
		"start screen disables tile hover tooltips and pointer input"
	)
	main.start_save_path = TEST_SAVE_PATH
	main.start_screen.animation_duration = 0.04
	main.start_screen.new_game_button.emit_signal("pressed")
	for _frame in range(120):
		await process_frame
		if not main.start_screen.is_loading():
			break
	_check(not main.start_screen.visible and main._game_started, "new-game loading enters the playable map")
	_check(main.tutorial_overlay != null and main.tutorial_overlay.is_open(), "new game opens the animated story tutorial")
	_check(not main.vertical_slice.is_time_paused(), "story tutorial keeps active-city time running")
	main.tutorial_overlay.close_as_completed(false)
	for _frame in range(30):
		await process_frame
		if not main.tutorial_overlay.is_open():
			break
	_check(main.tutorial_completed and not main.tutorial_overlay.is_open(), "finishing the tutorial records completion")
	_check(
		main.get_visible_npc_actors().all(func(button: Button) -> bool: return not button.tooltip_text.is_empty() and button.mouse_filter == Control.MOUSE_FILTER_STOP),
		"closing the tutorial restores resident hover tooltips and pointer input"
	)
	_check(
		main.grid_buttons.all(func(button: Button) -> bool: return not button.tooltip_text.is_empty() and button.mouse_filter == Control.MOUSE_FILTER_STOP),
		"closing the tutorial restores tile hover tooltips and pointer input"
	)
	var viewport_size := root.get_visible_rect().size

	_check(main.vertical_slice != null, "vertical slice coordinator is attached")
	_check(main.buildings.has("法院") and main.buildings.has("監察所"), "court and oversight office are registered buildings")
	_check(main.BUILDING_VISUALS.has("法院") and main.BUILDING_VISUALS.has("監察所"), "court and oversight office have map visuals")
	var committee_summary: Dictionary = main.vertical_slice.governance.committee_summary()
	_check(int(committee_summary.get("judicial_active", 0)) == 15, "15 judicial committee members are active")
	_check(int(committee_summary.get("oversight_active", 0)) == 10, "10 oversight committee members are active")
	_check(main.vertical_slice.population.population_count() == 300, "300 persistent NPC records are initialized")
	_check(main.get_visible_npc_count() == 24, "render layer pools 24 NPC proxies")
	_check(main.building_context_panel != null and not main.building_context_panel.visible, "building actions start hidden until a building is clicked")
	_check(main.city_backdrop != null and main.city_backdrop.bg_texture_rect != null, "city backdrop texture node exists")
	if main.city_backdrop != null and main.city_backdrop.bg_texture_rect != null:
		_check(main.city_backdrop.bg_texture_rect.texture.resource_path == BACKGROUND_PATH, "provided fantasy map is the active backdrop")
		var terrain_projection: Dictionary = main.city_backdrop.debug_terrain_projection()
		var backdrop_policy: Dictionary = terrain_projection.get("visual_policy", {})
		_check(int(terrain_projection.get("tile_count", 0)) == 100, "city backdrop debug projection retains all 100 authoritative terrain cells")
		_check(is_zero_approx(float(backdrop_policy.get("flat_grass_fill_alpha", -1.0))), "city backdrop adds a persistent flat-grass fill")
		_check(is_zero_approx(float(backdrop_policy.get("non_flat_fill_max_alpha", -1.0))), "city backdrop adds a persistent non-flat terrain fill")
		_check(not bool(backdrop_policy.get("persistent_terrain_overlay", true)), "city backdrop adds persistent per-cell terrain decoration")
		_check(str(backdrop_policy.get("interactive_grid_owner", "")) == "CityTileButton", "city backdrop does not delegate interactive grid drawing to CityTileButton")
		_check(main.city_backdrop.has_method("debug_render_order"), "city backdrop exposes no render-order debug contract")
		if main.city_backdrop.has_method("debug_render_order"):
			var render_order: Dictionary = main.city_backdrop.debug_render_order()
			_check(main.city_backdrop.get_parent() == main.map_stage, "city backdrop is not attached to the actual map stage")
			_check(int(render_order.get("backdrop_sibling_index", -1)) == 0, "city backdrop is not the first map-stage visual layer")
			_check(int(render_order.get("background_texture_z_index", -1)) == 0, "city backdrop texture falls behind the root background")
			_check(bool(render_order.get("background_texture_visible_in_tree", false)), "city backdrop texture is hidden in the actual Main tree")
			_check(Rect2(render_order.get("background_texture_rect", Rect2())).size.is_equal_approx(main.city_backdrop.size), "city backdrop texture does not cover the actual map stage")
			_check(bool(render_order.get("precedes_all_later_canvas_siblings", false)), "city backdrop does not render before transport, tiles, vehicles, and NPCs")

	# The map-first shell must not instantiate the old permanent tab/sidebar or
	# fixed top-bar UI. Only floating HUD surfaces may sit above the map.
	var tab_containers := main.find_children("*", "TabContainer", true, false)
	var visible_persistent_tabs: Array[Node] = []
	for tab in tab_containers:
		if tab.is_visible_in_tree():
			visible_persistent_tabs.append(tab)
	_check(visible_persistent_tabs.is_empty(), "no persistent TabContainer navigation is visible over the map")
	_check(main.find_child("FiscalCategoryTabs", true, false) == null, "finance removes the legacy nested fiscal TabContainer")
	_check(main.municipal_overlay == null, "finance controls are deferred with the municipal overlay")
	_check(main.find_child("RightPanel", true, false) == null, "legacy fixed side rail does not exist")
	_check(main.find_child("ReportPanel", true, false) == null, "legacy fixed report rail does not exist")
	_check(main.find_child("TopBar", true, false) == null, "legacy fixed TopBar is not instantiated")
	_check(main.status_hud != null, "compact status HUD remains present")
	_check(main.find_child("MapMetaHud", true, false) == null, "redundant top-right map capacity strip is removed")
	_check(main.find_child("MapInfoHud", true, false) == null, "obstructive lower-left information field is removed")
	_check(main.feedback_toast != null and main.feedback_toast.visible and main.hint_label.text.contains("教學完成"), "tutorial completion produces a visible transient handoff")
	main.feedback_toast.hide()
	_check(main.weather_visual_layer != null, "weather is rendered by a dedicated visual layer")
	if main.weather_visual_layer != null:
		_check(main.weather_visual_layer.mouse_filter == Control.MOUSE_FILTER_IGNORE, "weather animation never intercepts map input")
		_check(main.weather_visual_layer.z_index < main.status_hud.z_index, "weather animation stays below readable HUD controls")
		_check(
			main.get_npc_dialogue_card_control() != null and main.weather_visual_layer.z_index < main.get_npc_dialogue_card_control().z_index,
			"weather animation stays below NPC dialogue text"
		)
		_check(main.weather_visual_layer.current_weather == "sunny", "a new city begins with a deterministic sunny visual state")
		_check(main.weather_visual_layer.set_preview_weather("rain"), "rain can be rendered for visual acceptance")
		_check(main.weather_visual_layer.current_weather == "rain", "weather preview switches the rendered state without text")
		main.weather_visual_layer.clear_preview_weather()

	# The map itself fills the screen; controls are a compact lower-right dock
	# instead of reserving permanent layout space.
	_check(main.labels["month"].get_theme_font_size("font_size") >= 19, "compact status text uses the readable font baseline")
	_check(main.labels["population"].text.contains(str(main.population)), "population HUD combines its metric name with the value")
	_check(main.labels["grievance"].text.contains(str(main.vertical_slice.governance.grievance)), "grievance HUD combines its metric name with the value")
	_check(is_equal_approx(main.header_bars["grievance"].value, float(main.vertical_slice.governance.grievance)), "grievance micro bar uses the same raw direction as its visible number")
	_check(main.labels["grievance"].get_theme_color("font_color").is_equal_approx(Color("35291f")), "healthy grievance text remains legible on the light parchment HUD")
	_check(main.labels["trust"].get_theme_color("font_color").is_equal_approx(Color("35291f")), "healthy trust text remains legible on the light parchment HUD")
	_check(
		main.map_viewport.size.x >= viewport_size.x * 0.94 and main.map_viewport.size.y >= viewport_size.y * 0.94,
		"map fills at least 94%% of both viewport dimensions (map=%s, viewport=%s)" % [main.map_viewport.size, viewport_size]
	)
	_check(main.action_dock != null and main.action_dock.name == "ActionDock", "compact ActionDock is instantiated")
	if main.action_dock != null:
		var dock_rect: Rect2 = main.action_dock.get_global_rect()
		var dock_right_gap := viewport_size.x - dock_rect.end.x
		var dock_bottom_gap := viewport_size.y - dock_rect.end.y
		_check(dock_right_gap >= -1.0 and dock_right_gap <= 16.0, "ActionDock stays within 16px of the right edge")
		_check(dock_bottom_gap >= -1.0 and dock_bottom_gap <= 16.0, "ActionDock stays within 16px of the bottom edge")

	var compact_actions: Array = [
		main.municipal_button,
		main.settings_button,
		main.exit_button,
	]
	_check(compact_actions.size() == 3, "ActionDock keeps only municipal, settings, and exit actions")
	var previous_action_rect := Rect2()
	for action_button in compact_actions:
		_check(action_button != null, "every main/context/exit action has a compact button")
		if action_button == null:
			continue
		var action_name := str(action_button.get_meta("semantic_label", action_button.text))
		_check(action_button.custom_minimum_size == Vector2(72.0, 72.0), "'%s' declares a readable 72x72 click target" % action_name)
		_check(absf(action_button.size.x - action_button.size.y) <= 2.0, "'%s' renders as a square button" % action_name)
		var action_rect: Rect2 = (action_button as Button).get_global_rect()
		if previous_action_rect.size != Vector2.ZERO:
			_check(absf(action_rect.position.y - previous_action_rect.position.y) <= 1.0, "compact actions share one aligned top edge")
			_check(absf(action_rect.size.y - previous_action_rect.size.y) <= 1.0, "compact actions share one aligned height")
			_check(absf(action_rect.position.x - previous_action_rect.end.x - 12.0) <= 1.0, "compact actions use one consistent 12px gutter")
		previous_action_rect = action_rect
		_check(_rect_inside_viewport(action_button.get_global_rect(), viewport_size), "compact action '%s' stays inside the viewport" % action_name)
		var captions: Array[Node] = action_button.find_children("*", "Label", true, false)
		_check(captions.size() == 1, "compact action '%s' has one caption" % action_name)
		if captions.size() == 1:
			var caption := captions[0] as Label
			_check(caption.get_theme_font_size("font_size") >= 18, "compact action '%s' caption remains readable" % action_name)
			_check(caption.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "compact action '%s' caption wraps instead of clipping" % action_name)
	var date_hud := main.labels["month"] as Label
	_check(not main.vertical_slice.is_time_paused() and date_hud.text.begins_with("1/1．") and date_hud.text.contains(":"), "live map shows the continuous 12-hour game clock")
	_check(date_hud.tooltip_text == "遊戲時間每 120 秒自動推進一天，日期區不需點擊。", "running date HUD explains the automatic clock and that it is not a button")
	var day_before_date_hud_input := int(main.vertical_slice.game_day())
	var date_hud_click := InputEventMouseButton.new()
	date_hud_click.button_index = MOUSE_BUTTON_LEFT
	date_hud_click.pressed = true
	date_hud.emit_signal("gui_input", date_hud_click)
	var date_hud_accept := InputEventAction.new()
	date_hud_accept.action = "ui_accept"
	date_hud_accept.pressed = true
	date_hud.emit_signal("gui_input", date_hud_accept)
	await process_frame
	_check(int(main.vertical_slice.game_day()) == day_before_date_hud_input, "clicking or accepting the non-interactive date HUD does not advance time")
	_check(date_hud.focus_mode == Control.FOCUS_NONE, "date HUD cannot receive keyboard focus or impersonate a button")

	_check(main.settings_overlay != null and not main.settings_overlay.is_open(), "settings overlay starts closed")
	main.settings_button.emit_signal("pressed")
	await process_frame
	await process_frame
	_check(main.settings_overlay.is_open(), "settings button opens the unified settings overlay")
	_check(not main.vertical_slice.is_time_paused() and main.labels["month"].text.contains("．"), "settings keeps continuous simulation and the in-day clock visible")
	_check(main.labels["month"].tooltip_text == "遊戲時間每 120 秒自動推進一天，日期區不需點擊。", "settings keeps the continuous-time explanation visible")
	_check(main.settings_overlay.language_selector.choice_count() == 5, "settings preserves all five language choices")
	_check(main.settings_overlay.language_selector.visible_popup_item_count() == 5, "settings exposes all five language choices on one popup page")
	_check(main.settings_overlay.language_selector.shows_all_choices(), "settings language selector disables More paging")
	_check(main.settings_overlay.light_button != null and main.settings_overlay.dark_button != null, "settings contains light and dark appearance controls")
	_check(main.find_child("GameLanguageSelector", true, false) == null, "language selector is no longer exposed as a separate HUD control")
	main.settings_overlay.close()
	await process_frame
	_check(not main.vertical_slice.is_time_paused() and main.labels["month"].text.contains("．"), "closing settings preserves the automatic clock")

	# Bounds checks use the live viewport instead of assuming a fixed capture size.
	for key in ["month", "funds", "population", "satisfaction", "grievance", "trust", "score", "rating"]:
		var status_rect: Rect2 = main.labels[key].get_global_rect()
		_check(_rect_inside_viewport(status_rect, viewport_size), "top status '%s' stays inside the viewport" % key)
	# Modal navigation defers the municipal control trees until the player asks
	# for them. Opening the hub must not run the global UI sync path, because a
	# pending governance failure would otherwise append a durable report event.
	var original_grievance: int = main.vertical_slice.governance.grievance
	main.vertical_slice.governance.grievance = 81
	_check(main.vertical_slice.governance.failure_reason() == "grievance_above_80", "municipal lazy-open fixture exposes the governance-failure sync hazard")
	var city_state_before_municipal_open: Dictionary = main.vertical_slice.session.state.to_dict()
	var report_history_before_municipal_open: Dictionary = main.city_report_history_service.snapshot()
	_check(main.municipal_overlay == null, "municipal overlay is not instantiated during startup")
	_check(main.grid_buttons.all(func(button: Button) -> bool: return button.focus_mode == Control.FOCUS_ALL), "every map tile is keyboard focusable")
	_check(main.get_visible_npc_actors().all(func(button: Button) -> bool: return button.focus_mode == Control.FOCUS_ALL), "every visible resident is keyboard focusable")
	if performance_profile_only:
		_emit_performance_profile_phase("startup_ready")
		_performance_profile_hold(performance_profile_hold_ms)
	main.municipal_button.emit_signal("pressed")
	if performance_profile_only:
		_emit_performance_profile_phase("first_open_completed")
		_performance_profile_hold(performance_profile_hold_ms)
	_check(main.municipal_overlay.is_open() and main.municipal_overlay.current_page() == "hub", "municipal button opens the hub")
	var fiscal_state: Dictionary = main.call("debug_fiscal_draft_state")
	var fiscal_ui: Dictionary = fiscal_state.get("ui", {})
	_check(Array(fiscal_ui.get("category_ids", [])).size() == 6, "finance exposes six focused category choices")
	_check(Array(fiscal_ui.get("plan_ids", [])).size() == 3, "each fiscal category exposes three plan choices")
	for category_id in ["resident_tax", "industry_tax", "utilities", "environment_energy", "city_services", "education_leisure"]:
		var fiscal_card := main.find_child("FiscalCategoryCard_%s" % category_id, true, false) as Button
		_check(fiscal_card != null and fiscal_card.custom_minimum_size.y >= 44.0, "fiscal category '%s' remains a reachable 44px card" % category_id)
	var city_state_after_municipal_open: Dictionary = main.vertical_slice.session.state.to_dict()
	var report_history_after_municipal_open: Dictionary = main.city_report_history_service.snapshot()
	_check(city_state_after_municipal_open == city_state_before_municipal_open, "first municipal open does not mutate CityState")
	_check(report_history_after_municipal_open == report_history_before_municipal_open, "first municipal open does not append a governance event")
	main.vertical_slice.governance.grievance = original_grievance
	if performance_profile_only:
		# The profile ends after the state-preservation assertions. Write its
		# completion evidence synchronously, then use the same leak-clean teardown
		# as the full integration path before the SceneTree exits.
		_emit_performance_profile_phase("validation_completed")
		_performance_profile_hold(performance_profile_hold_ms)
		await TestCleanup.finish(self, [main], 1 if _failed else 0)
		return
	await process_frame
	await process_frame
	await process_frame
	_check(main.municipal_overlay.is_open() and main.municipal_overlay.current_page() == "hub", "lazy municipal hub remains live across three frames after first open")
	_check(not main.vertical_slice.is_time_paused() and main.labels["month"].text.contains("．"), "municipal management keeps simulation and the in-day clock running")
	_check(main.get_visible_npc_actors().all(func(button: Button) -> bool: return button.tooltip_text.is_empty() and button.mouse_filter == Control.MOUSE_FILTER_IGNORE), "modal opening disables resident hover tooltips and pointer input")
	_check(main.grid_buttons.all(func(button: Button) -> bool: return button.tooltip_text.is_empty() and button.mouse_filter == Control.MOUSE_FILTER_IGNORE), "modal opening disables tile hover tooltips and pointer input")
	var municipal_root := main.municipal_overlay.find_child("MunicipalHubRoot", true, false) as Control
	var municipal_menu := municipal_root.find_child("MunicipalDirectDestinations", true, false) as Control if municipal_root != null else null
	var hub_window := main.municipal_overlay.find_child("MunicipalWindow", true, false) as Control
	var hub_debug: Dictionary = main.municipal_overlay.debug_hub_layout_state()
	_check(municipal_menu != null, "municipal hub exposes a direct destination surface")
	_check(int(hub_debug.get("direct_card_count", 0)) == 7 and int(hub_debug.get("unique_destination_count", 0)) == 7, "municipal hub exposes seven unique direct destinations")
	_check(int(hub_debug.get("filler_count", -1)) == 0 and int(hub_debug.get("intermediate_page_count", -1)) == 0, "municipal hub uses neither filler cards nor category pages")
	_check(int(hub_debug.get("secondary_columns", 0)) == 2 and int(hub_debug.get("secondary_rows", 0)) == 3, "municipal hub balances six secondary destinations as 2x3")
	if municipal_menu != null:
		_check(municipal_menu.get_child_count() == 7, "municipal hub keeps all seven destinations visible")
		for menu_child in municipal_menu.get_children():
			_check(_rect_inside_viewport((menu_child as Control).get_global_rect(), viewport_size), "municipal hub destination remains inside the viewport")
			_check(hub_window != null and hub_window.get_global_rect().encloses((menu_child as Control).get_global_rect()), "municipal hub destination stays inside the modal window")
			for menu_label_variant in (menu_child as Control).find_children("*", "Label", true, false):
				_check((menu_label_variant as Label).get_theme_font_size("font_size") >= 18, "municipal hub card text stays at or above 18px")
	var highest_npc_z := -4096
	for npc_button in main.get_visible_npc_actors():
		highest_npc_z = maxi(highest_npc_z, npc_button.z_index)
	_check(main.municipal_overlay.z_index > highest_npc_z, "municipal overlay renders above every map resident")
	var direct_hub_pages := ["buildings", "governance", "judicial", "oversight", "finance", "public_affairs", "city_data"]
	for page_id in ["buildings", "governance", "judicial", "oversight", "blueprint", "finance", "public_affairs", "city_data", "report"]:
		var hub_button := main.municipal_overlay.find_child("%sButton" % page_id.capitalize(), true, false) as Button
		if page_id in direct_hub_pages:
			_check(hub_button != null and not hub_button.disabled, "direct hub preserves enabled '%s' destination" % page_id)
		else:
			_check(hub_button == null, "contextual page '%s' does not consume a direct hub card" % page_id)
		if page_id in direct_hub_pages or page_id in ["blueprint", "report"]:
			main.municipal_overlay.open_page(page_id)
			await process_frame
			await process_frame
			_check(main.municipal_overlay.current_page() == page_id, "hub button reaches '%s' page" % page_id)
			if page_id == "blueprint":
				_check(main.vertical_slice_panel._submit_button.size.y >= 50.0, "blueprint submission keeps a 50px click target")
			if page_id == "governance":
				_check(main.governance_status_tabs != null and main.governance_status_tabs.get_tab_count() == 3, "governance page exposes three status tabs")
				_check(main.governance_policy_cards.size() == 4 and main.governance_bill_cards.size() == 8, "governance page categorizes all policies and bills")
				_check(main.find_child("SeparationOfPowersDashboard", true, false) == null, "governance policy and bill page excludes the separation-of-powers dashboard")
				_check(l10n != null and main.governance_status_tabs.get_tab_title(0).begins_with(l10n.text("已實施")), "implemented policies and bills are the first status category")
				for pager_variant in main.governance_status_pagers.values():
					_check(pager_variant.choice_count() == 0 or pager_variant.visible_choice_count() <= 3, "governance lists reveal no more than three cards")
			if page_id == "judicial":
				_check(main.judicial_panel != null, "independent judicial page is instantiated")
				_check(main.judicial_panel._defense_buttons.size() == 3, "judicial page exposes three defense strategies")
			if page_id == "oversight":
				_check(main.oversight_panel != null, "independent oversight page is instantiated")
				_check(main.oversight_panel._defense_buttons.size() == 3, "oversight page exposes three impeachment-defense strategies")
			if page_id == "public_affairs":
				_check(main.public_affairs_panel != null, "independent public-affairs page is instantiated")
				_check(main.public_affairs_panel._request_buttons.size() == main.vertical_slice.population.active_requests().size(), "public-affairs automatically lists every active NPC request")
				_check(main.public_affairs_panel._request_models.size() == main.vertical_slice.population.active_requests().size(), "each public-affairs request owns the requesting NPC model")
				for npc_id_variant in main.public_affairs_panel._request_models.keys():
					var npc_id := str(npc_id_variant)
					var npc_model := main.public_affairs_panel._request_models[npc_id] as Button
					var npc_proxy: Dictionary = main.vertical_slice.population.materialize_proxy(npc_id)
					_check(str(npc_model.get_meta("model_source", "")) == "authoritative_npc_record", "public-affairs portrait identifies its authoritative NPC record source")
					_check(bool(npc_model.get_meta("portrait_mode", false)), "public-affairs NPC model runs in non-interactive portrait mode")
					_check(str(npc_model.get("npc_type")) == str(npc_proxy.get("archetype", "一般居民")), "public-affairs model matches the requesting NPC archetype")
				for request_button in main.public_affairs_panel._request_buttons.values():
					_check((request_button as Button).size.y >= 50.0, "each public-affairs request action keeps a 50px click target")
					_check((request_button as Button).get_theme_font_size("font_size") >= 18, "each public-affairs request action uses at least 18px text")
				_check(main.public_affairs_panel.find_children("*", "ProgressBar", true, false).is_empty(), "public-affairs does not duplicate HUD grievance/trust bars")
				_check(main.public_affairs_panel._requests_pager.visible_choice_count() <= 3, "public-affairs reveals at most three requests")
			if page_id == "city_data":
				var data_tabs := main.municipal_overlay.find_child("城市數據", true, false) as TabContainer
				_check(data_tabs != null and data_tabs.get_tab_count() == 3, "city data separates the monthly overview, resident detail, and finance detail into three tabs")
				_check(data_tabs != null and data_tabs.has_theme_stylebox_override("tab_selected"), "city data tabs use an explicit storybook selected state")
				var monthly_data_grid := main.municipal_overlay.find_child("MonthlyDataChartGrid", true, false) as GridContainer
				_check(monthly_data_grid != null and monthly_data_grid.get_child_count() == 9, "city data consolidates all four KPI and five service charts in one monthly overview")
				_check(main.monthly_data_kpi_charts.size() == 4, "city data owns four animated monthly KPI charts")
				_check(main.monthly_data_service_charts.size() == 5, "city data owns five animated monthly service charts")
				_check(main.city_data_dashboard != null, "city data is hosted by its dedicated dashboard component")
				_check(main.monthly_data_kpi_charts["net"] == main.city_data_dashboard.monthly_data_kpi_charts["net"], "Main KPI facade points to the dashboard-owned chart")
				_check(main.monthly_data_service_charts["security"] == main.city_data_dashboard.monthly_data_service_charts["security"], "Main service facade points to the dashboard-owned chart")
				_check(main.group_bars["一般居民"] == main.city_data_dashboard.group_bars["一般居民"], "Main resident facade points to the dashboard-owned chart")
				_check(main.labels["group_一般居民"] == main.city_data_dashboard.labels["group_一般居民"], "Main label alias points to the dashboard-owned node")
				_check(main.finance_bars["right_net_income"] == main.city_data_dashboard.finance_bars["right_net_income"], "Main finance alias points to the dashboard-owned bar")
				_check(is_equal_approx(main.monthly_data_kpi_charts["net"].baseline_value(), 100.0), "first-month finance chart compares against the 100%% safety line")
				_check(is_equal_approx(main.monthly_data_kpi_charts["net"].safety_value(), 100.0), "monthly finance chart retains the 100%% safety line")
				_check(main.monthly_data_kpi_charts["satisfaction"].difference_label.text.contains("百分點"), "monthly satisfaction chart communicates the safety gap in percentage points")
				_check(main.group_bars.size() == 4, "all four resident groups own an animated benchmark chart")
				_check(main.benchmark_charts.has("finance_coverage"), "city finance owns an income-to-expense safety chart")
				var original_security: int = int(main.security)
				var previous_snapshot: Dictionary = main._make_monthly_report_snapshot(1000, 800, 1.5)
				previous_snapshot["coverage_rate"] = 125.0
				previous_snapshot["security"] = 72
				main.monthly_report_history.append(previous_snapshot)
				var current_snapshot: Dictionary = main._make_monthly_report_snapshot(900, 800, 1.0)
				current_snapshot["security"] = 45
				main.monthly_report_history.append(current_snapshot)
				main.security = 45
				main._update_ui()
				_check(is_equal_approx(main.monthly_data_kpi_charts["net"].baseline_value(), 125.0), "second-month finance chart compares against last month")
				_check(is_equal_approx(main.monthly_data_service_charts["security"].baseline_value(), 72.0), "second-month service chart compares against last month")
				_check(is_equal_approx(main.monthly_data_service_charts["security"].safety_value(), 60.0), "second-month service chart keeps its independent safety line")
				_check(main.monthly_data_service_charts["security"].has_safety_warning(), "second-month comparison still raises a below-safety warning")
				_check(main.monthly_data_service_charts["security"].difference_label.text.contains("上月"), "second-month chart states its prior-month comparison")
				_check(str(main.monthly_data_service_charts["security"].get_meta("chart_render_mode", "")) == "donut", "Main city data renders its monthly comparisons as donut charts")
				main.monthly_report_history.clear()
				for _month in 3:
					var unsafe_snapshot: Dictionary = main._make_monthly_report_snapshot(1000, 800, 1.5)
					unsafe_snapshot["security"] = 45
					main.monthly_report_history.append(unsafe_snapshot)
				main._update_ui()
				_check(str(main.monthly_data_service_charts["security"].get_meta("safety_warning_severity", "")) == "critical", "Main forwards existing monthly history so the third unsafe month turns critical")
				main.monthly_report_history.clear()
				main.security = original_security
				main._update_ui()
			if page_id == "report":
				var report_summary := main.municipal_overlay.find_child("MonthlySummary", true, false) as PanelContainer
				var version_announcements := main.municipal_overlay.find_child("VersionUpdateAnnouncements", true, false) as PanelContainer
				_check(report_summary != null and version_announcements != null, "monthly report exposes only the major-event summary and version-update sections")
				_check(main.municipal_overlay.find_child("MonthlySummaryChartGrid", true, false) == null, "monthly report contains no routine metric charts")
				_check(main.municipal_overlay.find_child("MonthlyReportDetails", true, false) == null, "monthly report removes the separate details section")
				_check(main.municipal_overlay.find_child("MonthlyServiceSnapshot", true, false) == null, "monthly report removes the separate service section")
				_check(main.version_updates.size() >= 1, "version announcements load from the durable update log")
				_check(main.announcement_label.text.contains("城市數據與月報重新分工"), "version announcement renders the recorded update title")
				main._record_major_event("building_completed", "市民會館", "", "integration:building_completed", main.vertical_slice.game_day())
				main._update_ui()
				_check(main.report_label.text.contains("建築完工") and main.report_label.text.contains("市民會館"), "monthly summary records a major building completion without routine finance data")
				var saved_shell: Dictionary = main._capture_player_shell_state()
				_check((saved_shell.get("major_event_history", []) as Array).size() >= 1, "major-event summary is included in the player save shell")
			if page_id == "buildings":
				_check(main.find_child("DemolishSelectedBuildingButton", true, false) == null, "demolition has one contextual map owner")
				_check(main.building_family_tabs != null and main.building_family_tabs.get_tab_count() == 3, "building selector exposes three broad families")
				for group_button_variant in main.building_group_buttons.values():
					_check((group_button_variant as Button).get_theme_font_size("font_size") >= 18, "building group actions use at least 18px text")
				for family_page_variant in main.building_family_tabs.get_children():
					var visible_filters := 0
					for family_button_variant in (family_page_variant as Control).find_children("*", "Button", true, false):
						if (family_button_variant as Button).visible:
							visible_filters += 1
					_check(visible_filters <= 2, "each building family keeps its subgroup list below three choices")
				for pager_variant in main.building_card_pagers.values():
					_check(pager_variant.page_size == 6 and pager_variant.visible_choice_count() <= 6, "building catalogs expose up to six balanced cards per page")
					_check(bool(pager_variant.get_meta("balanced_building_pager", false)), "building catalogs opt into the count-balanced layout")
					_check(pager_variant.has_method("debug_layout_state"), "building catalogs expose inspectable balanced geometry")
					if pager_variant.has_method("debug_layout_state"):
						var building_layout: Dictionary = pager_variant.debug_layout_state()
						_check(Array(building_layout.get("row_counts", [])) == _expected_building_rows(pager_variant.visible_choice_count()), "building catalog row geometry follows its visible card count")
				for building_button_variant in main.building_buttons.values():
					_check((building_button_variant as Button).get_theme_font_size("font_size") >= 18, "building cards use at least 18px text")
			main.municipal_overlay.open_hub()
			await process_frame
	var municipal_back := main.municipal_overlay.find_child("BackButton", true, false) as Button
	_check(municipal_back != null and municipal_back.tooltip_text == "返回上一頁（Esc）", "municipal BackButton describes its immediate previous-page behavior")
	# Navigation is a real visit history, not a static child-to-parent lookup.
	# Exercise the player-visible sequences first, then a direct-page transition
	# whose return target cannot be expressed by the legacy static map.
	for route in [["buildings", "blueprint", "buildings"], ["buildings", "transport_planning", "buildings"], ["city_data", "report", "city_data"]]:
		main.municipal_overlay.open_hub()
		await process_frame
		main.municipal_overlay.open_page(str(route[0]))
		await process_frame
		main.municipal_overlay.open_page(str(route[1]))
		await process_frame
		_check(municipal_back != null and municipal_back.visible, "contextual page '%s' exposes back navigation" % route[1])
		if municipal_back != null:
			municipal_back.emit_signal("pressed")
			await process_frame
			_check(main.municipal_overlay.current_page() == str(route[2]), "contextual page '%s' returns to immediate '%s'" % [route[1], route[2]])
			municipal_back.emit_signal("pressed")
			await process_frame
			_check(main.municipal_overlay.current_page() == "hub", "parent page '%s' returns to the hub" % route[2])
	for page_id in direct_hub_pages:
		main.municipal_overlay.open_hub()
		await process_frame
		main.municipal_overlay.open_page(str(page_id))
		await process_frame
		_check(municipal_back != null and municipal_back.visible, "direct page '%s' exposes back navigation" % page_id)
		if municipal_back != null:
			municipal_back.emit_signal("pressed")
			await process_frame
			_check(main.municipal_overlay.current_page() == "hub", "direct page '%s' returns to the hub" % page_id)
	main.municipal_overlay.open_hub()
	await process_frame
	main.municipal_overlay.open_page("governance")
	await process_frame
	main.municipal_overlay.open_page("finance")
	await process_frame
	if municipal_back != null:
		municipal_back.emit_signal("pressed")
		await process_frame
		_check(main.municipal_overlay.current_page() == "governance", "cross-page visit returns to the actual previous page instead of the hub")
		municipal_back.emit_signal("pressed")
		await process_frame
		_check(main.municipal_overlay.current_page() == "hub", "cross-page history eventually returns to the hub")
	main.municipal_overlay.open_page("buildings")
	await process_frame
	main.municipal_overlay.open_page("buildings")
	await process_frame
	if municipal_back != null:
		municipal_back.emit_signal("pressed")
		await process_frame
		_check(main.municipal_overlay.current_page() == "hub", "opening the same page repeatedly does not create a back-loop")
	main.municipal_overlay.open_hub()
	await process_frame
	for navigation_index in 24:
		main.municipal_overlay.open_page("governance" if navigation_index % 2 == 0 else "finance")
		await process_frame
	var capped_back_steps := 0
	if municipal_back != null:
		municipal_back.emit_signal("pressed")
		await process_frame
		capped_back_steps += 1
		_check(main.municipal_overlay.current_page() == "governance", "capped history still returns to the most recently visited prior page")
		while main.municipal_overlay.current_page() != "hub" and capped_back_steps < 32:
			municipal_back.emit_signal("pressed")
			await process_frame
			capped_back_steps += 1
		_check(main.municipal_overlay.current_page() == "hub", "capped municipal history still ends at the hub")
		_check(capped_back_steps <= 16, "repeated municipal page visits retain only the bounded recent navigation path")
	main.municipal_overlay.open_hub()
	await process_frame
	main.municipal_overlay.open_page("buildings")
	await process_frame
	main.municipal_overlay.open_page("blueprint")
	await process_frame
	var child_escape := InputEventAction.new()
	child_escape.action = "ui_cancel"
	child_escape.pressed = true
	main.municipal_overlay._unhandled_key_input(child_escape)
	_check(main.get_viewport().is_input_handled(), "Escape from a municipal child page marks its input event handled")
	await process_frame
	_check(main.municipal_overlay.current_page() == "buildings", "Escape from a municipal child page returns to its immediate previous page")
	if municipal_back != null:
		municipal_back.emit_signal("pressed")
		await process_frame
	_check(main.municipal_overlay.current_page() == "hub", "Back returns the child-Escape route to the hub before hub Escape is tested")
	var hub_escape := InputEventAction.new()
	hub_escape.action = "ui_cancel"
	hub_escape.pressed = true
	main.municipal_overlay._unhandled_key_input(hub_escape)
	_check(main.get_viewport().is_input_handled(), "Escape from the municipal hub marks its input event handled")
	await process_frame
	_check(not main.municipal_overlay.is_open(), "Escape from the municipal hub closes the overlay")
	main.municipal_button.emit_signal("pressed")
	await process_frame
	_check(main.municipal_overlay.is_open() and main.municipal_overlay.current_page() == "hub", "municipal control reopens the overlay after Escape closes it")
	main.municipal_overlay.open_page("buildings")
	await process_frame
	main.municipal_overlay.open_page("unknown_municipal_page")
	await process_frame
	_check(main.municipal_overlay.current_page() == "buildings", "unknown municipal page fails safe without replacing the current page")
	if municipal_back != null:
		municipal_back.emit_signal("pressed")
		await process_frame
		_check(main.municipal_overlay.current_page() == "hub", "unknown municipal page does not corrupt the previous-page route")
	var released_page := Control.new()
	main.municipal_overlay.register_page("released_navigation_test", "Released navigation test", released_page, false)
	main.municipal_overlay.open_page("buildings")
	await process_frame
	main.municipal_overlay.open_page("released_navigation_test")
	await process_frame
	released_page.queue_free()
	await process_frame
	main.municipal_overlay.open_page("released_navigation_test")
	await process_frame
	_check(main.municipal_overlay.current_page() == "released_navigation_test", "opening a freed registered page fails safe without changing the current route")
	main.municipal_overlay.set_dark_mode(true)
	main.municipal_overlay.set_dark_mode(false)
	main.municipal_overlay.open_page("blueprint")
	await process_frame
	if municipal_back != null:
		municipal_back.emit_signal("pressed")
		await process_frame
		_check(main.municipal_overlay.current_page() == "buildings", "released history page is skipped safely while navigating back")
	main.municipal_overlay.close_overlay()
	await process_frame
	main.municipal_overlay.open_hub()
	await process_frame
	_check(main.municipal_overlay.current_page() == "hub", "close and reopen clears stale municipal navigation history")
	main.municipal_overlay.open_page("buildings")
	await process_frame
	if municipal_back != null:
		municipal_back.emit_signal("pressed")
		await process_frame
		_check(main.municipal_overlay.current_page() == "hub", "reopened municipal overlay starts a fresh navigation route")
	main.municipal_overlay.open_hub()
	await process_frame

	var overlay_close_button := main.municipal_overlay.find_child("CloseButton", true, false) as Button
	_check(overlay_close_button != null, "municipal overlay exposes a mouse-clickable close button")
	if overlay_close_button != null:
		overlay_close_button.emit_signal("pressed")
	await process_frame
	_check(not main.municipal_overlay.is_open(), "clicking the municipal close button restores the map")
	_check(not main.vertical_slice.is_time_paused() and main.labels["month"].text.contains("．"), "closing municipal management preserves the automatic clock")
	_check(main.get_visible_npc_actors().all(func(button: Button) -> bool: return not button.tooltip_text.is_empty() and button.mouse_filter == Control.MOUSE_FILTER_STOP), "closing the modal restores resident interaction")
	_check(main.grid_buttons.all(func(button: Button) -> bool: return not button.tooltip_text.is_empty() and button.mouse_filter == Control.MOUSE_FILTER_STOP), "closing the modal restores tile interaction")

	var dock_labels := {}
	for dock_button_variant in main.action_dock.find_children("*", "Button", true, false):
		var dock_button := dock_button_variant as Button
		dock_labels[str(dock_button.get_meta("semantic_label", dock_button.text))] = true
	_check(not dock_labels.has("數據") and not dock_labels.has("月報"), "city data and monthly report are no longer duplicate persistent HUD actions")
	_check(not main.municipal_overlay.is_open(), "closing a destination restores the unobstructed map")
	_check(main.map_viewport.visible and main.map_viewport.size.x >= viewport_size.x * 0.94, "full-screen map remains available after closing modal navigation")

	var justice_system = main.vertical_slice.governance.justice_system
	var judicial_opened: Dictionary = justice_system.open_judicial_case(
		"defense_sync_test",
		main.vertical_slice.game_day(),
		52,
		"Defense mirror test"
	)
	_check(bool(judicial_opened.get("ok", false)), "judicial defense mirror fixture opens")
	var judicial_case_id := str(judicial_opened.get("case", {}).get("id", ""))
	main.judicial_panel.refresh(justice_system)
	var judicial_autosaves_before: int = main._autosave_count
	var judicial_defense: Dictionary = main.judicial_panel.submit_current_defense("public_interest")
	_check(bool(judicial_defense.get("ok", false)), "judicial defense submission succeeds through the panel")
	_check(main._autosave_count > judicial_autosaves_before and main._last_autosave_reason == "action:judicial_defense_submitted", "judicial defense syncs before autosave")
	var mirrored_judicial: Dictionary = _governance_mirror_case(main.vertical_slice.session.state.governance.get("judicial_cases", []), judicial_case_id)
	_check(str(mirrored_judicial.get("defense_template_id", "")) == "public_interest", "judicial defense reaches the core governance mirror")

	var oversight_opened: Dictionary = justice_system.open_oversight_case(
		"official_mayor",
		["Defense mirror test"],
		78,
		main.vertical_slice.game_day()
	)
	_check(bool(oversight_opened.get("ok", false)), "oversight defense mirror fixture opens")
	var oversight_case_id := str(oversight_opened.get("case", {}).get("id", ""))
	main.oversight_panel.refresh(justice_system)
	var oversight_autosaves_before: int = main._autosave_count
	var oversight_defense: Dictionary = main.oversight_panel.submit_current_defense("full_disclosure")
	_check(bool(oversight_defense.get("ok", false)), "oversight defense submission succeeds through the panel")
	_check(main._autosave_count > oversight_autosaves_before and main._last_autosave_reason == "action:oversight_defense_submitted", "oversight defense syncs before autosave")
	var mirrored_oversight: Dictionary = _governance_mirror_case(main.vertical_slice.session.state.governance.get("oversight_cases", []), oversight_case_id)
	_check(str(mirrored_oversight.get("defense_template_id", "")) == "full_disclosure", "oversight defense reaches the core governance mirror")

	var defense_coordinator_script: Script = load("res://scripts/app/vertical_slice_coordinator.gd") as Script
	var defense_restored = defense_coordinator_script.new(2, 2)
	defense_restored.set_save_path(TEST_SAVE_PATH)
	_check(defense_restored.load_game(TEST_SAVE_PATH), "defense autosave can be loaded")
	_check(str(defense_restored.governance.judiciary_cases.get(judicial_case_id, {}).get("defense_template_id", "")) == "public_interest", "judicial defense survives save and load")
	_check(str(_governance_mirror_case(defense_restored.session.state.governance.get("judicial_cases", []), judicial_case_id).get("defense_template_id", "")) == "public_interest", "loaded judicial core mirror matches GovernanceSystem")
	_check(str(defense_restored.governance.oversight_cases.get(oversight_case_id, {}).get("defense_template_id", "")) == "full_disclosure", "oversight defense survives save and load")
	_check(str(_governance_mirror_case(defense_restored.session.state.governance.get("oversight_cases", []), oversight_case_id).get("defense_template_id", "")) == "full_disclosure", "loaded oversight core mirror matches GovernanceSystem")

	# Fullscreen users can exit entirely by mouse. Confirm is observable without
	# terminating this test process when the explicit test switch is disabled.
	main.quit_application_on_confirm = false
	main.application_quit_requested.connect(Callable(self, "_on_application_quit_requested"))
	main.exit_button.emit_signal("pressed")
	await process_frame
	_check(main.exit_confirmation.visible, "exit button opens the quit confirmation overlay")
	_check(main.exit_confirmation.cancel_button != null and main.exit_confirmation.confirm_button != null, "quit confirmation provides mouse-clickable cancel and confirm buttons")
	main.exit_confirmation.cancel_button.emit_signal("pressed")
	await process_frame
	_check(not main.exit_confirmation.visible, "cancel button closes quit confirmation")
	main.exit_button.emit_signal("pressed")
	await process_frame
	_check(main.exit_confirmation.visible, "quit confirmation can be reopened")
	main.exit_confirmation.confirm_button.emit_signal("pressed")
	await process_frame
	_check(not main.exit_confirmation.visible, "confirm button closes quit confirmation")
	_check(_quit_signal_count == 1, "confirm emits application_quit_requested without terminating tests")
	_check(main.vertical_slice.is_time_paused(), "confirmed exit pauses simulation time")

	# A failed exit autosave must never close the game implicitly. The same
	# overlay provides a retry path and an explicit discard path.
	var valid_exit_save_path: String = main.start_save_path
	main.start_save_path = "res://project.godot/blocked-exit-save.json"
	main.exit_button.emit_signal("pressed")
	await process_frame
	main.exit_confirmation.confirm_button.emit_signal("pressed")
	await process_frame
	_check(main.exit_confirmation.visible, "failed exit autosave keeps the confirmation overlay open")
	_check(main.exit_confirmation.discard_button.visible, "failed exit autosave exposes an explicit exit-without-saving action")
	_check(_quit_signal_count == 1, "failed exit autosave does not emit an application quit request")
	_check(not main.vertical_slice.is_time_paused(), "failed exit autosave returns the still-open city to continuous simulation")
	main.start_save_path = valid_exit_save_path
	main.exit_confirmation.confirm_button.emit_signal("pressed")
	await process_frame
	_check(not main.exit_confirmation.visible and _quit_signal_count == 2, "retry closes only after autosave succeeds")

	main.start_save_path = "res://project.godot/blocked-exit-save.json"
	main.exit_button.emit_signal("pressed")
	await process_frame
	main.exit_confirmation.confirm_button.emit_signal("pressed")
	await process_frame
	_check(main.exit_confirmation.visible and main.exit_confirmation.discard_button.visible, "discard appears only after a real save failure occurs")
	main.exit_confirmation.discard_button.emit_signal("pressed")
	await process_frame
	_check(not main.exit_confirmation.visible and _quit_signal_count == 3, "explicit discard is the only failed-save path that emits quit")
	main.start_save_path = valid_exit_save_path

	var tile_index := 18
	var environment_before_park: int = int(main.environment)
	var park_record: Dictionary = main.vertical_slice.register_existing_building(tile_index, "公園")
	_check(not park_record.is_empty(), "metric reconciliation fixture registers an authoritative park")
	main.call("_reconcile_building_metric_effects")
	_check(main.environment == environment_before_park + 8, "active park applies its declared environment effect once")
	var park_satisfaction_target := _calculated_satisfaction_target(main)
	main.call("_recalculate_satisfaction")
	_check(main.total_satisfaction == park_satisfaction_target, "satisfaction recalculation writes its visible target without adding the active park twice")
	var repeated_park_satisfaction_target := _calculated_satisfaction_target(main)
	main.call("_recalculate_satisfaction")
	_check(main.total_satisfaction == repeated_park_satisfaction_target, "repeated satisfaction recalculation does not accumulate the active park contribution")
	main.call("_reconcile_building_metric_effects")
	_check(main.environment == environment_before_park + 8, "repeated reconciliation does not accumulate the park effect")
	var park_demolition: Dictionary = main.vertical_slice.start_demolition(tile_index, 20)
	_check(bool(park_demolition.get("ok", false)), "metric reconciliation fixture park can be demolished")
	if bool(park_demolition.get("ok", false)):
		main.vertical_slice.advance_days(int(park_demolition.get("job", {}).get("projected_remaining_days", 0)), {}, false)
	main.call("_reconcile_building_metric_effects")
	_check(main.environment == environment_before_park, "demolition removes the park effect once")
	var post_demolition_satisfaction_target := _calculated_satisfaction_target(main)
	main.call("_recalculate_satisfaction")
	_check(main.total_satisfaction == post_demolition_satisfaction_target, "satisfaction recalculation remains exact after the positive-effect park is demolished")
	var saturation_population_before: int = int(main.population)
	var saturation_employed_before := int(main.vertical_slice.building_capacity_snapshot().get("employed", -1))
	main.environment = 65
	main.total_satisfaction = 65
	var saturation_building_ids: Array[String] = []
	for candidate_tile in range(30, main.city_grid.size()):
		if saturation_building_ids.size() >= 11:
			break
		if not main.vertical_slice.get_building_by_tile(candidate_tile).is_empty():
			continue
		var saturation_record: Dictionary = main.vertical_slice.register_existing_building(candidate_tile, "公園")
		if not saturation_record.is_empty():
			saturation_building_ids.append(str(saturation_record.get("building_id", "")))
	_check(saturation_building_ids.size() == 11, "saturation fixture registers eleven authoritative park records")
	main.call("_reconcile_building_metric_effects")
	_check(int(Dictionary(main.get("_applied_building_metric_effects")).get("environment", 0)) == 88, "eleven park records contribute 88 environment points exactly once each")
	_check(main.environment == 100, "65-point environment plus 88 building points saturates at 100")
	_check(int(Dictionary(main.get("_applied_building_metric_effects")).get("satisfaction", 0)) == 44 and main.total_satisfaction == 100, "65-point satisfaction plus 44 building points saturates at 100")
	var saturated_satisfaction_target := _calculated_satisfaction_target(main)
	main.call("_recalculate_satisfaction")
	_check(main.total_satisfaction == saturated_satisfaction_target, "saturated satisfaction recalculation writes the service target without double-counting 44 building points")
	var repeated_saturated_satisfaction_target := _calculated_satisfaction_target(main)
	main.call("_recalculate_satisfaction")
	_check(main.total_satisfaction == repeated_saturated_satisfaction_target, "repeated saturated satisfaction recalculation remains tied to the service target")
	var saturated_shell: Dictionary = main._capture_player_shell_state()
	_check(int(saturated_shell.get("schema_version", 0)) == 10, "saturated shell uses schema 10")
	_check(int(Dictionary(saturated_shell.get("building_metric_baselines", {})).get("environment", -1)) == 65, "schema 10 preserves the pre-saturation 65-point non-building baseline")
	main.call("_apply_city_metric_delta", {"environment": -3})
	_check(main.environment == 100 and int(Dictionary(main.get("_building_metric_baselines")).get("environment", -1)) == 62, "non-building monthly delta remains recorded while the visible metric is saturated")
	for building_id: String in saturation_building_ids:
		var saturation_record: Dictionary = main.vertical_slice.session.state.buildings.get(building_id, {})
		saturation_record["status"] = "scrapped"
		main.vertical_slice.session.state.buildings[building_id] = saturation_record
	main.call("_reconcile_building_metric_effects")
	_check(main.environment == 62, "removing all 88 building points restores the exact adjusted baseline instead of 12")
	var post_scrap_satisfaction_target := _calculated_satisfaction_target(main)
	main.call("_recalculate_satisfaction")
	_check(main.total_satisfaction == post_scrap_satisfaction_target, "satisfaction recalculation remains exact after all 44 active building points are scrapped")
	main.call("_reconcile_building_metric_effects")
	_check(main.environment == 62, "repeated post-scrap reconciliation is idempotent")
	_check(main.population == saturation_population_before and int(main.vertical_slice.building_capacity_snapshot().get("employed", -1)) == saturation_employed_before, "building metric saturation and removal preserve population and employment")
	main.environment = environment_before_park
	main.city_grid[tile_index] = "住宅"
	main.building_customizations[tile_index] = {"variant": 0, "roof": 0, "wall": 0}
	var residence_record: Dictionary = main.vertical_slice.register_existing_building(tile_index, "住宅", main.building_customizations[tile_index])
	main.call("_sync_vertical_state")
	_check(PackedStringArray(residence_record.get("resident_ids", [])).is_empty(), "residence creates no resident ownership IDs")
	_check(main.population == 300, "residence leaves canonical population unchanged")
	_check(main.vertical_slice.session.state.npcs.size() == 300, "residence leaves core NPC records unchanged")
	_check(int(main.vertical_slice.session.state.metrics.get("population", -1)) == 300, "residence leaves the core population metric unchanged")
	_check(int(main.vertical_slice.building_capacity_snapshot().get("housing_capacity", -1)) == 28, "residence contributes 28 housing capacity")
	main.call("_apply_building_effect", main.buildings["住宅"])
	_check(main.population == 300, "presentation-side building effects never add population")
	_check(main.city_grid[tile_index] == "住宅", "test fixture building exists before demolition")
	main._select_built_cell(tile_index)
	_check(main.building_context_panel.visible, "clicking a building opens the contextual action panel")
	_check(main.building_context_panel._action_buttons.size() == 5, "building context preserves all five actions")
	_check(main.building_context_panel._root_actions.visible and main.building_context_panel._root_actions.get_child_count() == 3, "building context initially reveals exactly three actions")
	_check(main.building_context_panel._status.get_theme_font_size("font_size") >= 18, "building context status uses at least 18px text")
	for action_id in ["style", "roof", "exterior", "maintenance", "demolish"]:
		_check(main.building_context_panel._action_buttons.has(action_id), "building context contains '%s'" % action_id)
		var context_labels := (main.building_context_panel._action_buttons[action_id] as Button).find_children("*", "Label", true, false)
		_check(context_labels.size() == 1 and (context_labels[0] as Label).get_theme_font_size("font_size") >= 18, "building context action '%s' uses at least 18px text" % action_id)
	main.building_context_panel._appearance_button.emit_signal("pressed")
	await process_frame
	_check(main.building_context_panel._customize_actions.visible and main.building_context_panel._customize_actions.get_child_count() == 3, "appearance submenu reveals exactly three focused actions")
	var building_cancel_event := InputEventAction.new()
	building_cancel_event.action = "ui_cancel"
	building_cancel_event.pressed = true
	main.building_context_panel._unhandled_key_input(building_cancel_event)
	_check(main.building_context_panel.visible and main.building_context_panel._root_actions.visible, "Esc returns from building appearance choices to the root actions")
	main.building_context_panel._unhandled_key_input(building_cancel_event)
	_check(not main.building_context_panel.visible, "Esc closes the root building context panel")
	main._select_built_cell(tile_index)
	_check(main.building_context_panel.visible, "building context can be reopened after keyboard close")
	main._start_selected_demolition()
	_check(main.city_grid[tile_index] == "住宅", "building remains while demolition is in progress")
	_check(str(main.vertical_slice.get_building_by_tile(tile_index).get("status", "")) == "demolition", "core marks demolition in progress")
	for _day in range(10):
		if main.city_grid[tile_index] == "":
			break
		main._next_day()
	_check(main.city_grid[tile_index] == "", "demolition completion clears the map tile")
	_check(main.vertical_slice.get_building_by_tile(tile_index).is_empty(), "demolished building is removed from core state")
	_check(main.vertical_slice.construction.available_workers() == 20, "demolition returns workers to the shared team")
	_check(main.population == 300, "demolition retains every existing resident")
	_check(main.vertical_slice.population.population_count() == 300, "demolition leaves canonical population unchanged")
	_check(main.vertical_slice.session.state.npcs.size() == 300, "demolition leaves core NPC records unchanged")
	_check(int(main.vertical_slice.session.state.metrics.get("population", -1)) == 300, "demolition leaves the core population metric unchanged")
	_check(int(main.vertical_slice.building_capacity_snapshot().get("housing_capacity", -1)) == 0, "demolition removes housing capacity")
	var tax_probe_npc_id: String = main.vertical_slice.population.sorted_npc_ids()[0]
	var tax_probe_record = main.vertical_slice.population.get_record(tax_probe_npc_id)
	var original_npc_income: int = tax_probe_record.income
	var original_income_tax: int = int(main._tax_revenues().get("income", 0))
	tax_probe_record.income = original_npc_income + 100_000
	_check(int(main._tax_revenues().get("income", 0)) > original_income_tax, "resident income-tax revenue consumes authoritative NPC income")
	tax_probe_record.income = original_npc_income

	var employment_tile := 19
	main.city_grid[employment_tile] = "大型商場"
	main.building_customizations[employment_tile] = {"variant": 0, "roof": 0, "wall": 0}
	main.vertical_slice.register_existing_building(employment_tile, "大型商場", main.building_customizations[employment_tile])
	var building_job_matches: Array[Dictionary] = main._match_available_jobs()
	_check(building_job_matches.size() == int(main.buildings["大型商場"].get("job_attraction", 0)), "building job_attraction creates exactly its declared employment capacity")
	_check(main._match_available_jobs().is_empty(), "occupied building jobs are not duplicated by repeated matching")
	for match_result: Dictionary in building_job_matches:
		var matched_record = main.vertical_slice.population.get_record(str(match_result.get("npc_id", "")))
		_check(matched_record != null and matched_record.salary == null, "building employment does not fabricate salary data")

	main.city_grid[tile_index] = "住宅"
	main.vertical_slice.register_existing_building(tile_index, "住宅")
	var over_capacity_before_law: Dictionary = main.vertical_slice.building_capacity_snapshot()
	_check(int(over_capacity_before_law.get("housing_available", -1)) == 0 and int(over_capacity_before_law.get("housing_over_capacity", -1)) == 272, "legacy population above capacity is reported without deleting residents")
	var population_ids_before_law: Array[String] = main.vertical_slice.population.sorted_npc_ids()
	main.vertical_slice.governance.active_laws["population_test"] = {
		"bill_id": "population_test",
		"name": "Population test",
		"effects": {"population": 20, "monthly_expense": 0},
		"status": "active",
	}
	var monthly_autosaves_before: int = main._autosave_count
	main.call("_settle_month")
	_check(main._autosave_count == monthly_autosaves_before + 1, "monthly settlement performs exactly one final-state autosave")
	_check(main._last_autosave_reason == "event:month_started", "monthly settlement records the expected autosave reason")
	_check(main.population == 300, "monthly active-law growth is blocked when housing is over capacity")
	_check(main.vertical_slice.population.population_count() == 300, "capacity-blocked law leaves canonical population unchanged")
	_check(main.vertical_slice.session.state.npcs.size() == 300, "capacity-blocked law leaves core NPC records unchanged")
	_check(int(main.vertical_slice.session.state.metrics.get("population", -1)) == 300, "capacity-blocked law leaves the core population metric unchanged")
	var law_addresses_valid := true
	for npc_id: String in main.vertical_slice.population.sorted_npc_ids():
		if not population_ids_before_law.has(npc_id) and not str(main.vertical_slice.population.get_record(npc_id).address_id).begins_with("home_"):
			law_addresses_valid = false
	_check(law_addresses_valid, "active-law residents receive normal home addresses instead of a policy source label")
	main.call("_sync_vertical_state")
	_check(main.population == 300, "vertical-state synchronization preserves capacity-blocked population")
	var authoritative_metrics: Dictionary = main.vertical_slice.session.state.metrics
	_check(int(authoritative_metrics.get("satisfaction", -1)) == main.total_satisfaction, "CityState owns the synchronized satisfaction metric")
	_check(int(authoritative_metrics.get("security", -1)) == main.security, "CityState owns the synchronized security metric")
	_check(int(authoritative_metrics.get("environment", -1)) == main.environment, "CityState owns the synchronized environment metric")
	_check(int(authoritative_metrics.get("traffic", -1)) == main.traffic, "CityState owns the synchronized traffic metric")
	_check(int(authoritative_metrics.get("education", -1)) == main.education and int(authoritative_metrics.get("healthcare", -1)) == main.healthcare, "CityState owns the synchronized service metrics")
	var captured_shell: Dictionary = main._capture_player_shell_state()
	_check(int(captured_shell.get("schema_version", 0)) == 10 and captured_shell.get("onboarding") is Dictionary, "player shell schema includes authoritative onboarding state alongside metric authority, healthcare-service latch, audio, and map zoom persistence")
	_check(captured_shell.get("building_metric_baselines") is Dictionary and Dictionary(captured_shell.get("building_metric_baselines", {})).size() == 6, "player shell schema 10 persists exactly six non-building metric baselines")
	_check(main.last_report.contains("人口 300（+0）"), "concise monthly report records capacity-blocked population change")
	_check(bool(main.last_month_summary.get("available", false)), "monthly settlement records a structured summary")
	_check(int(main.last_month_summary.get("population_change", -1)) == 0, "structured monthly summary preserves the zero capacity-blocked population delta")
	for delta_key in ["security_change", "environment_change", "traffic_change", "education_change", "healthcare_change"]:
		_check(main.last_month_summary.has(delta_key), "structured monthly summary records %s" % delta_key)
	for metric_card_variant in main.city_metric_cards.values():
		_check(metric_card_variant.has_authoritative_delta(), "settled city metric cards expose measured monthly deltas")
	var coordinator_script: Script = load("res://scripts/app/vertical_slice_coordinator.gd") as Script
	var restored = coordinator_script.new(1, 1)
	restored.set_save_path(TEST_SAVE_PATH)
	_check(restored.load_game(TEST_SAVE_PATH), "active-law monthly snapshot can be loaded")
	_check(restored.session.save_service.last_load_source == "primary", "active-law monthly snapshot loads from the primary rather than silently falling back")
	_check(restored.governance.active_laws.has("population_test"), "active-law monthly snapshot preserves the enacted law")
	_check(restored.population.population_count() == 300, "capacity-blocked active-law population survives save and load")
	_check(restored.session.state.npcs.size() == 300 and int(restored.session.state.metrics.get("population", -1)) == 300, "loaded capacity-blocked population keeps all three authorities consistent")
	var restored_shell: Dictionary = restored.get_player_shell_state()
	_check(int(restored_shell.get("schema_version", 0)) == 10 and _metric_baselines_equal(restored_shell.get("building_metric_baselines", {}), captured_shell.get("building_metric_baselines", {})), "schema 10 building metric baselines survive current-version save and load exactly")
	_check(int(restored.building_capacity_snapshot().get("employed", -1)) == int(main.vertical_slice.building_capacity_snapshot().get("employed", -2)), "current-version save and load preserves employment assignments")
	var restored_main = (load("res://scripts/app/main.gd") as Script).new()
	restored_main.vertical_slice = restored
	restored_main._rebuild_city_from_core()
	_check(restored_main._restore_player_shell_state(restored_shell), "schema 10 player shell restores into the application metric authority")
	_check(restored_main._capture_player_shell_state().get("building_metric_baselines", {}) == captured_shell.get("building_metric_baselines", {}), "schema 10 application round-trip preserves metric baselines exactly")
	var restored_satisfaction_baseline := int(Dictionary(restored_shell.get("building_metric_baselines", {})).get("satisfaction", -1))
	var restored_satisfaction_contribution := int(Dictionary(restored_main.get("_applied_building_metric_effects")).get("satisfaction", 0))
	_check(restored_main.total_satisfaction == clampi(restored_satisfaction_baseline + restored_satisfaction_contribution, 0, 100), "schema 10 save and load preserves satisfaction as baseline plus each active building contribution exactly once")
	var inconsistent_schema10 := restored_shell.duplicate(true)
	var inconsistent_baselines: Dictionary = inconsistent_schema10["building_metric_baselines"]
	var saved_security_baseline := int(inconsistent_baselines.get("security", 70))
	inconsistent_baselines["security"] = saved_security_baseline - 1 if saved_security_baseline > 0 else 1
	var inconsistent_main = (load("res://scripts/app/main.gd") as Script).new()
	inconsistent_main.vertical_slice = restored
	inconsistent_main._rebuild_city_from_core()
	_check(not inconsistent_main._restore_player_shell_state(inconsistent_schema10), "schema 10 rejects a well-typed baseline that disagrees with authoritative metrics")
	var schema9_shell := restored_shell.duplicate(true)
	schema9_shell["schema_version"] = 9
	schema9_shell.erase("building_metric_baselines")
	var schema9_main = (load("res://scripts/app/main.gd") as Script).new()
	schema9_main.vertical_slice = restored
	schema9_main._rebuild_city_from_core()
	var population_before_schema9: int = int(restored.population.population_count())
	var employed_before_schema9 := int(restored.building_capacity_snapshot().get("employed", -1))
	_check(schema9_main._restore_player_shell_state(schema9_shell), "schema 9 player shell migrates without inventing unavailable saturation history")
	_check(restored.population.population_count() == population_before_schema9 and int(restored.building_capacity_snapshot().get("employed", -1)) == employed_before_schema9, "schema 9 migration preserves existing population and employment values")
	var migrated_schema10_shell: Dictionary = schema9_main._capture_player_shell_state()
	_check(int(migrated_schema10_shell.get("schema_version", 0)) == 10 and Dictionary(migrated_schema10_shell.get("building_metric_baselines", {})).size() == 6, "schema 9 migration writes a complete schema 10 baseline on the next save")
	restored_main.free()
	inconsistent_main.free()
	schema9_main.free()
	_check(str(restored.get_player_shell_state().get("last_report", "")).contains("人口 300（+0）"), "loaded concise shell report matches capacity-blocked population change")
	var restored_month_summary: Dictionary = restored.get_player_shell_state().get("last_month_summary", {})
	_check(bool(restored_month_summary.get("available", false)) and int(restored_month_summary.get("population_change", -1)) == 0, "capacity-blocked monthly summary survives save and load")
	var restored_report_history: Array = restored.get_player_shell_state().get("monthly_report_history", [])
	_check(restored_report_history.size() == 1, "authoritative prior-month comparison snapshot survives save and load")
	if not restored_report_history.is_empty():
		var restored_report_snapshot: Dictionary = restored_report_history[0]
		_check(int(restored_report_snapshot.get("population", 0)) == 300, "saved monthly comparison snapshot preserves authoritative population")
		_check(restored_report_snapshot.has("coverage_rate") and restored_report_snapshot.has("security"), "saved monthly comparison snapshot preserves finance and safety metrics")
	_check(int(restored.get_player_shell_state().get("month_start_population", 0)) == 300, "current-month population baseline survives save and load")
	for delta_key in ["security_change", "environment_change", "traffic_change", "education_change", "healthcare_change"]:
		_check(restored_month_summary.has(delta_key), "service metric delta survives save and load: %s" % delta_key)
	_test_main_level_crossing_navigation_policy(main)
	_test_whole_segment_transport_demolition_preview(main)

	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Mayor Simulator main integration test passed.")
	await TestCleanup.finish(self, [main], exit_code)


func _rect_inside_viewport(rect: Rect2, viewport_size: Vector2) -> bool:
	const TOLERANCE := 1.0
	return (
		rect.position.x >= -TOLERANCE
		and rect.position.y >= -TOLERANCE
		and rect.end.x <= viewport_size.x + TOLERANCE
		and rect.end.y <= viewport_size.y + TOLERANCE
	)


func _on_application_quit_requested() -> void:
	_quit_signal_count += 1


func _test_whole_segment_transport_demolition_preview(main) -> void:
	var segment_id := "main_integration_preview_road"
	var segment_tiles: Array[int] = [91, 92, 93]
	var clicked_tile := segment_tiles[1]
	var non_target_tile := 94
	main.vertical_slice.transport.segments[segment_id] = {
		"id": segment_id,
		"kind": "road",
		"tile_path": segment_tiles.duplicate(),
		"status": "completed",
		"project_id": "main_integration_fixture",
	}
	main.call("_update_transport_runtime")
	main.call("_on_transport_infrastructure_requested", "road", "demolish")
	main.call("_on_grid_pressed", clicked_tile)

	_check(
		main.transport_plan_tiles == segment_tiles,
		"clicking the middle of a transport segment selects its complete three-tile demolition target"
	)
	var layer_snapshot: Dictionary = main.transport_network_layer.get("_network_snapshot")
	var tile_states: Dictionary = layer_snapshot.get("tile_states", {})
	for tile_id: int in segment_tiles:
		var state: Dictionary = tile_states.get(str(tile_id), {})
		_check(
			str(state.get("project_status", "")) == "demolishing",
			"whole-segment demolition preview marks target tile %d" % tile_id
		)
	var non_target_state: Dictionary = tile_states.get(str(non_target_tile), {})
	_check(
		str(non_target_state.get("project_status", "")) != "demolishing",
		"whole-segment demolition preview does not mark a neighboring non-target tile"
	)

	main.call("_confirm_transport_infrastructure_plan")
	var job: Dictionary = main.vertical_slice.active_construction_for_tile(clicked_tile)
	var metadata_tiles: Array = job.get("metadata", {}).get("tile_indices", [])
	var normalized_metadata_tiles: Array[int] = []
	for tile_variant: Variant in metadata_tiles:
		normalized_metadata_tiles.append(int(tile_variant))
	normalized_metadata_tiles.sort()
	_check(not job.is_empty(), "confirming whole-segment demolition creates an active transport job")
	_check(
		normalized_metadata_tiles == segment_tiles,
		"confirmed transport demolition metadata preserves all three segment tiles"
	)
	for tile_id: int in segment_tiles:
		_check(
			main.vertical_slice.active_construction_for_tile(tile_id).get("id", "") == job.get("id", ""),
			"every segment tile resolves to the same confirmed demolition job"
		)


func _test_main_level_crossing_navigation_policy(main) -> void:
	var crossing_tile := -1
	var navigation = main.npc_map_controller.get("_navigation")
	for candidate in main.city_grid.size():
		if candidate in [91, 92, 93, 94]:
			continue
		var candidate_center: Vector2 = main.call("_iso_tile_center", candidate)
		if (
			main.city_grid[candidate] == ""
			and main.vertical_slice.terrain_map.is_walkable(candidate)
			and main.vertical_slice.active_construction_for_tile(candidate).is_empty()
			and navigation != null
			and navigation.is_position_walkable(candidate_center)
		):
			crossing_tile = candidate
			break
	_check(crossing_tile >= 0, "main crossing fixture found a walkable, empty, construction-free tile")
	if crossing_tile < 0:
		return

	var road_id := "main_integration_crossing_road"
	var rail_id := "main_integration_crossing_rail"
	var crossing_id := "main_integration_level_crossing"
	main.vertical_slice.transport.segments[road_id] = {
		"id": road_id,
		"kind": "road",
		"tile_path": [crossing_tile],
		"status": "completed",
		"project_id": "main_integration_crossing_fixture",
	}
	main.vertical_slice.transport.segments[rail_id] = {
		"id": rail_id,
		"kind": "rail_track",
		"tile_path": [crossing_tile],
		"status": "completed",
		"project_id": "main_integration_crossing_fixture",
	}
	main.vertical_slice.transport.crossings[crossing_id] = {
		"id": crossing_id,
		"kind": "level_crossing",
		"tile_id": crossing_tile,
		"track_kinds": ["rail_track"],
		"status": "completed",
		"build_cost": 900,
		"monthly_maintenance": 40,
	}
	main.call("_update_transport_runtime")
	main.debug_sync_npc_navigation_obstacles()
	var crossing_center: Vector2 = main.call("_iso_tile_center", crossing_tile)
	_check(not main.npc_map_controller.is_tile_blocked(crossing_tile), "main opens a completed level crossing for NPC navigation")
	_check(navigation.is_position_walkable(crossing_center), "main crossing aperture reaches the live navigation grid")

	main.npc_map_controller.set_crossing_states({str(crossing_tile): {"closed": true, "flash": false}})
	_check(main.npc_map_controller.is_tile_blocked(crossing_tile), "closed main crossing blocks the NPC tile")
	_check(not navigation.is_position_walkable(crossing_center), "closed main crossing seals the live navigation aperture")
	main.npc_map_controller.set_crossing_states({str(crossing_tile): {"closed": false, "flash": false}})
	_check(not main.npc_map_controller.is_tile_blocked(crossing_tile), "reopened main crossing restores NPC passage")

	main.vertical_slice.transport.crossings.erase(crossing_id)
	main.vertical_slice.transport.segments.erase(road_id)
	main.vertical_slice.transport.segments.erase(rail_id)
	main.call("_update_transport_runtime")
	main.debug_sync_npc_navigation_obstacles()


func _governance_mirror_case(raw_cases: Variant, case_id: String) -> Dictionary:
	if raw_cases is Array:
		for case_variant: Variant in raw_cases:
			if case_variant is Dictionary and str(case_variant.get("id", "")) == case_id:
				return (case_variant as Dictionary).duplicate(true)
	return {}


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Main integration check failed: %s" % message)


func _metric_baselines_equal(left_value: Variant, right_value: Variant) -> bool:
	if not left_value is Dictionary or not right_value is Dictionary:
		return false
	var left: Dictionary = left_value
	var right: Dictionary = right_value
	if left.size() != right.size():
		return false
	for metric_name: String in ["security", "environment", "traffic", "education", "healthcare", "satisfaction"]:
		if not left.has(metric_name) or not right.has(metric_name):
			return false
		if int(left[metric_name]) != int(right[metric_name]):
			return false
	return true


func _calculated_satisfaction_target(main) -> int:
	var result: Dictionary = main.CitySimulationServiceScript.satisfaction_result(
		main.call("_city_metrics_snapshot"),
		main.tax_rates,
		main.TAX_DEFS,
		main.utility_fees,
		main.UTILITY_DEFS,
		main.service_fees,
		main.SERVICE_DEFS,
		main.call("_authoritative_building_records"),
		main.policies,
		main.active_policies,
		main.call("_active_law_value", "utility_relief")
	)
	return int(result.get("satisfaction", main.total_satisfaction))


func _emit_performance_profile_phase(phase: String) -> void:
	var monotonic_usec := Time.get_ticks_usec()
	print("PERFORMANCE_PROFILE_LAZY_OVERLAY_PHASE phase=%s monotonic_usec=%d" % [phase, monotonic_usec])
	var marker_path := "user://mayor_simulator/tests/performance_profile_lazy_overlay_phases.jsonl"
	var marker := FileAccess.open(
		marker_path,
		FileAccess.READ_WRITE if FileAccess.file_exists(marker_path) else FileAccess.WRITE_READ
	)
	if marker == null:
		push_error("Unable to write lazy-overlay performance profile phase marker: %s" % phase)
		return
	marker.seek_end()
	marker.store_line(JSON.stringify({
		"schema_version": 1,
		"phase": phase,
		"monotonic_usec": monotonic_usec,
	}))
	marker.flush()
	marker.close()


func _performance_profile_hold_ms(profile_enabled: bool) -> int:
	if not profile_enabled:
		return 0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--performance-profile-hold-ms="):
			var raw_value := argument.trim_prefix("--performance-profile-hold-ms=")
			if raw_value.is_valid_int():
				return clampi(raw_value.to_int(), 50, 2_000)
	return 500


func _performance_profile_hold(hold_ms: int) -> void:
	if hold_ms > 0:
		OS.delay_msec(hold_ms)


func _expected_building_rows(visible_count: int) -> Array:
	match visible_count:
		0: return []
		1: return [1]
		2: return [2]
		3: return [3]
		4: return [2, 2]
		5: return [3, 2]
		_: return [3, 3]
