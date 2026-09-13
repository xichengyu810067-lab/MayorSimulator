extends SceneTree

const IntroCinematicScript := preload("res://ui/tutorial/intro_cinematic.gd")
const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const TEST_SAVE_PATH := "user://mayor_simulator/tests/guided_onboarding_entry.json"

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_save()
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	_check(str(ProjectSettings.get_setting("application/run/main_scene", "")) == "res://scenes/Main.tscn", "project.godot enters the canonical Main scene")

	var first = _new_main()
	await _settle(3)
	_check(str(first.get_script().resource_path) == "res://scripts/app/main.gd", "Main.tscn uses the canonical main.gd")
	first.start_save_path = TEST_SAVE_PATH
	first.start_screen.animation_duration = 0.04
	first.start_screen.new_game_button.emit_signal("pressed")
	await _wait_for_loading(first)
	await _settle(3)
	_check(first.tutorial_overlay != null and first.tutorial_overlay.get_script() == IntroCinematicScript, "formal new-game entry owns IntroCinematic rather than TutorialStoryOverlay")
	_check(first.tutorial_overlay.name == "IntroCinematic" and first.tutorial_overlay.is_open(), "first entry visibly opens the fixed CG sequence")
	_check(first.tutorial_overlay.current_index == 0 and first.tutorial_overlay.PAGES.size() == 8, "first entry starts on shot one of eight")
	_check(first.tutorial_overlay.skip_button != null and first.tutorial_overlay.skip_button.visible, "the previously supported skip action remains available")
	_check(first.onboarding_progress.is_story_pending() and first.onboarding_progress.receipts().is_empty(), "CG presentation cannot create an authoritative receipt")
	_check(not first.onboarding_guide.is_open() and first.vertical_slice.is_time_paused(), "CG blocks the guide and pauses simulation until completion")
	_assert_cinematic_modal_order(first, "initial CG")
	root.content_scale_size = Vector2i(1440, 900)
	root.size = Vector2i(1440, 900)
	await _settle(3)
	_assert_cinematic_modal_order(first, "resized initial CG")
	var cg_authority_before := _presentation_authority_snapshot(first)
	await _click_at(first.municipal_button.get_global_rect().get_center())
	_check(first.municipal_overlay == null, "CG consumes the pointer before the underlying Municipal button can open its lazy overlay")
	_check(_presentation_authority_snapshot(first) == cg_authority_before, "CG pointer handling cannot change date, funds, report history, or guide receipts")

	first.tutorial_overlay.skip_button.emit_signal("pressed")
	await _settle(5)
	_check(not first.tutorial_overlay.is_open(), "skip closes the CG")
	_check(first.onboarding_progress.is_active() and first.onboarding_progress.current_target() == "build", "skip begins the same ordered nine-step guide at build")
	_check(first.onboarding_progress.receipts().is_empty(), "skip grants no build or later receipt")
	_check(first.onboarding_guide.is_open() and first.onboarding_guide.is_product_mode(), "build target receives the arrow and mask guide")
	_check(first.onboarding_guide.target_control() != null, "build guide binds a real visible product control")
	_check(not first.vertical_slice.is_time_paused(), "product guide does not freeze the game clock")
	_check(first.vertical_slice.has_save_game(TEST_SAVE_PATH), "story-to-guide transition is persisted for continue")
	_assert_guide_presentation(first, first.municipal_button, "bottom-edge Municipal target")
	var guide_authority_before := _presentation_authority_snapshot(first)
	await _click_at(first.municipal_button.get_global_rect().get_center())
	await _settle(4)
	_check(first.municipal_overlay != null and first.municipal_overlay.is_open(), "guided Municipal target opens the real lazy modal")
	var buildings_target := first.onboarding_guide.target_control() as Control
	_check(buildings_target != null and buildings_target.name == "BuildingsButton", "guide rebinds to the real Buildings destination inside the Municipal modal")
	_assert_guide_presentation(first, buildings_target, "Municipal modal target")
	_check(_presentation_authority_snapshot(first) == guide_authority_before, "opening the guided Municipal modal cannot change date, funds, report history, or guide receipts")
	first.settings_overlay.open()
	await _settle(2)
	_check(_draws_after(first.settings_overlay, first.onboarding_guide), "Settings opened after the guide retains modal priority")
	first.settings_overlay.close()
	first.exit_confirmation.open()
	await _settle(2)
	_check(_draws_after(first.exit_confirmation, first.onboarding_guide), "Exit confirmation opened after the guide retains terminal modal priority")
	first.exit_confirmation.close()
	await _click_at(buildings_target.get_global_rect().get_center())
	await _settle(3)
	var residence_target := first.onboarding_guide.target_control() as Control
	if residence_target != null and residence_target.name == "BuildingGroup_housing":
		await _click_at(residence_target.get_global_rect().get_center())
		await _settle(3)
		residence_target = first.onboarding_guide.target_control() as Control
	_check(residence_target != null and residence_target.name == "BuildingCard_住宅", "guided housing group click advances through the real Residence card")
	await _click_at(residence_target.get_global_rect().get_center())
	await _settle(4)
	var blueprint_target := first.onboarding_guide.target_control() as Control
	var blueprint_scroll := _scroll_ancestor(blueprint_target)
	var blueprint_viewport := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var target_rect := blueprint_target.get_global_rect() if blueprint_target != null else Rect2()
	var effective_rect := target_rect.intersection(blueprint_viewport)
	if blueprint_scroll != null:
		effective_rect = effective_rect.intersection(blueprint_scroll.get_global_rect())
	_check(blueprint_target != null and blueprint_target.name == "SubmitBlueprintButton", "Residence selection binds the guide to the real SubmitBlueprintButton")
	_check(blueprint_scroll != null and blueprint_scroll.scroll_vertical > 0, "product guide scrolls the blueprint ScrollContainer to reveal SubmitBlueprintButton")
	_check(effective_rect.has_area() and effective_rect.encloses(target_rect), "SubmitBlueprintButton has a complete clickable rect inside its clip viewport")
	var blueprint_authority_before := _presentation_authority_snapshot(first)
	await _click_at(blueprint_target.get_global_rect().get_center())
	await _settle(4)
	_check(first.placement_mode_active, "real SubmitBlueprintButton click enters placement mode")
	_check(first.onboarding_progress.receipts().is_empty(), "entering placement from SubmitBlueprintButton creates no build receipt")
	_check(_presentation_authority_snapshot(first) == blueprint_authority_before, "SubmitBlueprintButton click changes neither date, funds, report history, nor authoritative receipts")
	var placement_target := first.onboarding_guide.target_control() as Button
	var placement_index: int = first.grid_buttons.find(placement_target)
	var placement_workers: int = int(first.vertical_slice_panel.selected_worker_count()) if first.vertical_slice_panel != null else 5
	var placement_quote: Dictionary = first.vertical_slice.placement_footprint_quote(first.placement_building_name, placement_index, placement_workers)
	var placement_viewport := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var placement_target_rect := placement_target.get_global_rect() if placement_target != null else Rect2()
	var placement_effective_rect := placement_target_rect.intersection(placement_viewport)
	var placement_scroll := _scroll_ancestor(placement_target)
	if placement_scroll != null:
		placement_effective_rect = placement_effective_rect.intersection(placement_scroll.get_global_rect())
	var placement_banner_rect: Rect2 = first.placement_banner.get_global_rect() if first.placement_banner != null else Rect2()
	_check(placement_target != null and placement_index >= 0, "build guide binds a real dynamic grid tile")
	_check(bool(placement_quote.get("ok", false)) and str(placement_quote.get("status", "")) == "approved" and bool(placement_quote.get("can_afford", false)), "build guide tile has an approved affordable authoritative placement quote")
	_check(placement_effective_rect.encloses(placement_target_rect) and placement_effective_rect.has_point(placement_target_rect.get_center()), "build guide tile center is fully visible through viewport and clipping ancestors")
	_check(first.placement_banner != null and first.placement_banner.is_visible_in_tree() and not placement_target_rect.intersects(placement_banner_rect), "build guide tile has a full clickable rect outside the visible placement banner")
	var occupied_tile_ids: Array = placement_quote.get("occupied_tile_ids", [])
	_check(not occupied_tile_ids.is_empty(), "build guide quote exposes its complete dynamic footprint")
	for occupied_tile_variant: Variant in occupied_tile_ids:
		_check(first._is_tile_inside_hud_safe_area(int(occupied_tile_variant)), "build guide quote keeps every occupied footprint tile outside the HUD safe area")
	var placement_authority_before := _presentation_authority_snapshot(first)
	var construction_jobs_before: int = first.vertical_slice.session.state.construction_jobs.size()
	var treasury_before_construction: int = first.vertical_slice.treasury_balance()
	var placement_cost := int(placement_quote.get("total_cost", placement_quote.get("cost", 0)))
	await _click_at(placement_target_rect.get_center())
	await _settle(4)
	_check(first._pending_construction_tile == placement_index, "real guided grid click selects the dynamic quoted anchor tile")
	_check(first.construction_confirmation != null and first.construction_confirmation.is_open(), "real guided grid click opens construction confirmation")
	var confirmation_target := first.onboarding_guide.target_control() as Control
	_check(confirmation_target != null and confirmation_target.name == "ConfirmConstructionButton", "guide rebinds to the real construction confirmation action")
	_check(_presentation_authority_snapshot(first) == placement_authority_before, "construction confirmation opens before changing date, funds, jobs, report history, or receipts")
	await _click_at(confirmation_target.get_global_rect().get_center())
	await _settle(4)
	_check(first.vertical_slice.session.state.construction_jobs.size() == construction_jobs_before + 1, "real confirmation creates exactly one authoritative construction job")
	_check(first.vertical_slice.treasury_balance() == treasury_before_construction - placement_cost, "real confirmation deducts the approved quoted construction cost from the authoritative treasury")
	_check(first.onboarding_progress.current_target() == "blueprint" and first.onboarding_progress.receipts().size() == 1, "real construction confirmation advances the guide once to blueprint")
	await _advance_to_onboarding_due(first, "blueprint")
	var blueprint_municipal_target := first.onboarding_guide.target_control() as Control
	_check(blueprint_municipal_target == first.municipal_button, "blueprint step returns to the real Municipal entry after construction")
	if blueprint_municipal_target == null:
		_cleanup_save()
		await TestCleanup.finish(self, [first], 1)
		return
	await _click_at(blueprint_municipal_target.get_global_rect().get_center())
	await _settle(3)
	var park_buildings_target := first.onboarding_guide.target_control() as Control
	_check(park_buildings_target != null and park_buildings_target.name == "BuildingsButton", "blueprint guide enters Buildings through the real Municipal modal")
	await _click_at(park_buildings_target.get_global_rect().get_center())
	await _settle(3)
	var public_services_tabs := first.onboarding_guide.target_control() as TabBar
	_check(public_services_tabs != null and public_services_tabs == first.building_family_tabs.get_tab_bar(), "blueprint guide points to the Public Services tab")
	await _click_at(public_services_tabs.get_global_position() + public_services_tabs.get_tab_rect(1).get_center())
	await _settle(3)
	var park_group_target: Control = first.onboarding_guide.target_control() as Control
	_check(park_group_target != null and (park_group_target.name == "BuildingGroup_community" || park_group_target.name == "BuildingCard_公園"), "Public Services tab advances to the Park service group or directly to Park card")
	if park_group_target != null and park_group_target.name == "BuildingGroup_community":
		await _click_at(park_group_target.get_global_rect().get_center())
		await _settle(3)
	var park_target: Control = first.onboarding_guide.target_control() as Control
	_check(park_target != null and park_target.name == "BuildingCard_公園", "Park service group advances the guide to the real Park card")
	await _click_at(park_target.get_global_rect().get_center())
	await _settle(3)
	var material_target: Control = first.onboarding_guide.target_control() as Control
	_check(material_target != null and material_target.name == "BlueprintMaterial", "Park blueprint card opens the real BlueprintMaterial control")
	var material_before := str(material_target.call("selected_choice_id")) if material_target != null else ""
	var material_after := "brick" if material_before != "brick" else "steel"
	_check(_select_progressive_choice(material_target, material_after), "semantic Park material picker signal changes one design field")
	await _settle(3)
	var park_submit_target := first.onboarding_guide.target_control() as Button
	var submit_primary_mode: String = str(first.vertical_slice_panel._primary_action_mode) if first.vertical_slice_panel != null else ""
	var submit_blueprint_button: Button = first.find_child("SubmitBlueprintButton", true, false) as Button
	_check(park_submit_target != null and park_submit_target.is_visible_in_tree() and not park_submit_target.disabled, "changed Park draft binds guide to the real primary submit control and it is currently actionable")
	_check(park_submit_target == first.vertical_slice_panel._submit_button or park_submit_target == submit_blueprint_button, "changed Park draft guide remains aligned with panel primary submit target")
	_check(submit_primary_mode == "submit", "changed Park draft sets primary action mode to submit")
	await _click_at(park_submit_target.get_global_rect().get_center())
	await _settle(3)
	_check(first.onboarding_progress.current_target() == "route" and first.onboarding_progress.receipts().size() == 2, "real Park blueprint submit advances once to the route step")
	_check(first.municipal_overlay != null and first.municipal_overlay.is_open() and first.municipal_overlay.current_page() == "blueprint", "successful Park blueprint leaves the real Municipal blueprint page open")
	_check(first.onboarding_guide.is_waiting_mode() and not first.onboarding_guide.is_open(), "new route segment waits without inserting an actionable target into the still-open real modal")
	var route_foreground_back := first.call("_visible_municipal_back_target") as Control
	_check(route_foreground_back != null and route_foreground_back.name == "BackButton", "the still-open blueprint page keeps its real foreground Back control while the next segment waits")
	_assert_wrong_page_resolvers_use_foreground_back(first, route_foreground_back)

	await TestCleanup.release_fixtures(self, [first])
	var resumed = _new_main()
	await _settle(3)
	resumed.start_save_path = TEST_SAVE_PATH
	resumed.start_screen.set_continue_available(true)
	resumed.start_screen.animation_duration = 0.04
	resumed.start_screen.continue_game_button.emit_signal("pressed")
	await _wait_for_loading(resumed)
	await _settle(5)
	_check(resumed.onboarding_progress.is_active() and resumed.onboarding_progress.current_target() == "route", "continue restores the exact route target after completed build and blueprint steps")
	_check(resumed.onboarding_progress.receipts().size() == 2, "continue restores the two authoritative completed-step receipts without synthesizing more")
	_check(not resumed.tutorial_overlay.is_open(), "continue does not replay an already-seen CG")
	_check(resumed.onboarding_guide.is_waiting_mode() and not resumed.onboarding_guide.is_open(), "continue restores the exact route schedule without an early target")

	var replay_authority_before := _presentation_authority_snapshot(resumed)
	resumed.call("_replay_tutorial")
	await _settle(3)
	_check(resumed.tutorial_overlay.is_open() and resumed.tutorial_overlay.current_index == 0, "settings replay reopens the CG from shot one")
	_assert_cinematic_modal_order(resumed, "settings replay CG")
	_check(_presentation_authority_snapshot(resumed) == replay_authority_before, "replaying the CG cannot change date, funds, report history, or guide receipts")
	resumed.tutorial_overlay.skip_button.emit_signal("pressed")
	await _settle(3)
	_check(resumed.onboarding_progress.current_target() == "route" and resumed.onboarding_progress.receipts().size() == 2, "replay completion cannot reset, complete, or skip the authoritative route guide")
	_check(resumed.onboarding_guide.is_waiting_mode(), "replay completion preserves the route waiting schedule")
	await _advance_to_onboarding_due(resumed, "route")

	var route_entry_target := resumed.onboarding_guide.target_control() as Control
	for expected_name: String in ["MunicipalButton", "BuildingsButton", "BuildingGroup_mobility", "BuildingCard_公車站"]:
		if route_entry_target == null or route_entry_target.name != expected_name:
			continue
		await _click_at(route_entry_target.get_global_rect().get_center())
		await _settle(4)
		route_entry_target = resumed.onboarding_guide.target_control() as Control
	_check(route_entry_target != null and route_entry_target.name == "SubmitBlueprintButton", "restored route guide reaches the real Bus Stop continuous-planning action through product controls")
	if route_entry_target == null:
		_fail("restored route guide has no actionable Bus Stop submit target")
		_cleanup_save()
		await TestCleanup.finish(self, [resumed], 1)
		return
	await _click_at(route_entry_target.get_global_rect().get_center())
	await _settle(5)
	var route_session: Dictionary = resumed.vertical_slice.transport_planning_session_snapshot()
	_check(str(route_session.get("workflow", "")) == "route_package_v1" and str(route_session.get("state", "")) == "station_placement", "real guided Bus Stop action begins the authoritative route package")
	_check(resumed.placement_mode_active and resumed.placement_building_name == "公車站", "route package begins real continuous station placement")

	var station_resolution_before := _route_guide_authority_snapshot(resumed)
	var first_station_target := resumed.onboarding_guide.target_control() as Button
	var repeated_first_station_target := resumed._resolve_route_onboarding_target() as Button
	var illegal_generic_station_target := _find_illegal_station_grid_target(resumed, route_session)
	_check(first_station_target != null and repeated_first_station_target == first_station_target, "repeated first-station resolution is deterministic")
	_check(_route_guide_authority_snapshot(resumed) == station_resolution_before, "repeated first-station resolution mutates terrain, drafts, jobs, ledger, network, population, grid, or receipts")
	_check(illegal_generic_station_target != null and first_station_target != illegal_generic_station_target, "route package rejects the first generic illegal or obscured grid tile")
	if first_station_target == null:
		await TestCleanup.finish(self, [resumed], 1)
		return
	var first_station_index : int = resumed.grid_buttons.find(first_station_target)
	var station_workers := int(resumed.vertical_slice_panel.selected_worker_count()) if resumed.vertical_slice_panel != null else 5
	var first_station_quote: Dictionary = resumed.vertical_slice.placement_footprint_quote("公車站", first_station_index, station_workers)
	_check(_approved_station_target(resumed, first_station_target, first_station_quote), "first guided station is visible, enabled, affordable, legal, and full-footprint HUD/banner safe")
	await _click_at(first_station_target.get_global_rect().get_center())
	await _settle(5)
	route_session = resumed.vertical_slice.transport_planning_session_snapshot()
	var first_placements: Array = Dictionary(route_session.get("route_draft", {})).get("station_placements", [])
	_check(first_placements.size() == 1 and int(Dictionary(first_placements[0]).get("anchor_tile_id", -1)) == first_station_index, "first real guided click retains exactly one station draft")
	if first_placements.size() != 1 or not first_placements[0] is Dictionary:
		await TestCleanup.finish(self, [resumed], 1)
		return

	var stale_session := route_session.duplicate(true)
	var stale_placement: Dictionary = stale_session["route_draft"]["station_placements"][0]
	stale_placement["footprint_id"] = "stale_guide_fixture"
	stale_session["route_draft"]["station_placements"][0] = stale_placement
	var stale_resolution_before := _route_guide_authority_snapshot(resumed)
	_check(resumed._route_package_station_onboarding_target(stale_session) == null, "stale selected station fails closed instead of guiding a second placement")
	_check(_route_guide_authority_snapshot(resumed) == stale_resolution_before, "stale station resolution mutates authoritative state")

	var second_station_target := resumed.onboarding_guide.target_control() as Button
	var repeated_second_station_target := resumed._resolve_route_onboarding_target() as Button
	if second_station_target == null:
		_fail("second station guide did not bind a real grid target")
		await TestCleanup.finish(self, [resumed], 1)
		return
	var second_station_index : int = resumed.grid_buttons.find(second_station_target)
	var second_station_quote: Dictionary = resumed.vertical_slice.placement_footprint_quote("公車站", second_station_index, station_workers)
	_check(second_station_target != null and repeated_second_station_target == second_station_target and second_station_index != first_station_index, "second station guide is stable and chooses a distinct anchor")
	_check(_approved_station_target(resumed, second_station_target, second_station_quote), "second guided station is visible, enabled, affordable, legal, and full-footprint HUD/banner safe")
	_check(_tile_arrays_do_not_overlap(first_station_quote.get("occupied_tile_ids", []), second_station_quote.get("occupied_tile_ids", [])), "guided station footprints do not overlap")
	await _click_at(second_station_target.get_global_rect().get_center())
	await _settle(5)
	route_session = resumed.vertical_slice.transport_planning_session_snapshot()
	var station_placements: Array = Dictionary(route_session.get("route_draft", {})).get("station_placements", [])
	_check(station_placements.size() == 2 and _station_placements_are_distinct(station_placements), "second real guided click preserves both distinct nonoverlapping drafts")
	_check(resumed.onboarding_guide.target_control() == resumed.placement_confirm_button and not resumed.placement_confirm_button.disabled, "two valid station drafts guide to the real station-phase confirmation")
	print("ROUTE_GUIDE_STATIONS first=%d second=%d drafts=%d" % [first_station_index, second_station_index, station_placements.size()])
	if station_placements.size() != 2 or resumed.onboarding_guide.target_control() != resumed.placement_confirm_button:
		await TestCleanup.finish(self, [resumed], 1)
		return
	await _click_at(resumed.placement_confirm_button.get_global_rect().get_center())
	await _settle(6)
	route_session = resumed.vertical_slice.transport_planning_session_snapshot()
	var road_action_target := resumed.onboarding_guide.target_control() as Button
	_check(str(route_session.get("state", "")) == "network_placement", "station confirmation advances the same package to network placement")
	_check(road_action_target != null and road_action_target.name == "InfrastructureAdd_road" and not road_action_target.disabled, "bus package guide chooses the real road action")
	if road_action_target == null:
		await TestCleanup.finish(self, [resumed], 1)
		return
	await _click_at(road_action_target.get_global_rect().get_center())
	await _settle(4)
	_check(resumed.map_action_mode == "transport_infrastructure" and resumed.transport_plan_kind == "road", "real road action enters guided corridor placement")

	route_session = resumed.vertical_slice.transport_planning_session_snapshot()
	var resolved_stations: Array[Dictionary] = resumed._route_package_current_station_candidates(route_session)
	var planned_corridor: Array[int] = resumed._route_package_corridor_completion(route_session, resolved_stations, [])
	_check(planned_corridor.size() > 1, "dynamic guided fixture exposes a multi-cell corridor for incomplete-corridor coverage")
	if resolved_stations.size() < 2 or planned_corridor.size() <= 1:
		await TestCleanup.finish(self, [resumed], 1)
		return
	var illegal_first_tile := _find_illegal_route_first_tile(resumed, resolved_stations)
	var corridor_resolution_before := _route_guide_authority_snapshot(resumed)
	resumed.transport_plan_tiles.clear()
	resumed.transport_plan_tiles.append(illegal_first_tile)
	_check(illegal_first_tile >= 0 and resumed._resolve_route_onboarding_target() == null, "illegal first corridor tile cannot become valid guidance or premature Confirm")
	resumed.transport_plan_tiles.clear()
	_check(_route_guide_authority_snapshot(resumed) == corridor_resolution_before, "illegal corridor resolution mutates authoritative state")
	var incomplete_prefix: Array[int] = [planned_corridor[0]]
	resumed.transport_plan_tiles = incomplete_prefix.duplicate()
	var incomplete_target := resumed._resolve_route_onboarding_target() as Control
	_check(incomplete_target != null and incomplete_target != resumed.placement_confirm_button, "incomplete legal corridor resolves to the next adjacent cell instead of Confirm")
	resumed.transport_plan_tiles.clear()

	var corridor_steps := 0
	while corridor_steps <= resumed.grid_buttons.size():
		var corridor_target := resumed.onboarding_guide.target_control() as Control
		if corridor_target == resumed.placement_confirm_button:
			break
		var corridor_index : int = resumed.grid_buttons.find(corridor_target)
		_check(corridor_target != null and corridor_index >= 0, "corridor guide always binds a real grid button before completion")
		if corridor_target == null or corridor_index < 0:
			break
		if not resumed.transport_plan_tiles.is_empty():
			_check(not resumed._transport_direction_pair(resumed.transport_plan_tiles.back(), corridor_index).is_empty(), "corridor guide selects the next cardinally adjacent cell")
		var candidate_path: Array[int] = resumed.transport_plan_tiles.duplicate()
		candidate_path.append(corridor_index)
		var corridor_quote: Dictionary = resumed.vertical_slice.transport_project_quote("road", "build", candidate_path, station_workers, resumed.city_grid)
		_check(bool(corridor_quote.get("ok", false)) and bool(corridor_quote.get("can_afford", false)), "every guided corridor prefix has an approved affordable pure project quote")
		await _click_at(corridor_target.get_global_rect().get_center())
		await _settle(4)
		corridor_steps += 1
	_check(resumed.onboarding_guide.target_control() == resumed.placement_confirm_button and not resumed.placement_confirm_button.disabled, "only a complete valid affordable station-connecting corridor guides to Confirm")
	var completed_corridor: Array[int] = resumed.transport_plan_tiles.duplicate()
	var corridor_model_quote: Dictionary = resumed.vertical_slice.transport.quote_completed_corridor(
		"bus",
		completed_corridor,
		resumed.vertical_slice.terrain_map,
		_station_footprint_tiles(station_placements),
		[]
	)
	_check(bool(corridor_model_quote.get("ok", false)), "completed guided corridor passes the pure topology quote")
	await _click_at(resumed.placement_confirm_button.get_global_rect().get_center())
	await _settle(7)
	route_session = resumed.vertical_slice.transport_planning_session_snapshot()
	var package_wait_target := resumed.onboarding_guide.target_control() as Button
	var package_continue_control := resumed.find_child("TransportPlanningSessionContinue", true, false) as Button
	var route_draft: Dictionary = route_session.get("route_draft", {})
	_check(str(route_session.get("state", "")) == "route_edit" and not Array(route_draft.get("station_placements", [])).is_empty() and not Array(route_session.get("network_draft", {}).get("tile_ids", [])).is_empty(), "corridor confirmation reaches route_edit with station placements and network draft")
	var wait_reserved_tiles: Array[int] = _station_footprint_tiles(station_placements)
	for corridor_tile: int in completed_corridor:
		if not wait_reserved_tiles.has(corridor_tile):
			wait_reserved_tiles.append(corridor_tile)
	var blocker_start: Dictionary = _start_route_wait_blocker(resumed, wait_reserved_tiles)
	_check(bool(blocker_start.get("ok", false)), "guided route wait starts one real independent terrain job after the staged days")
	resumed.call("_consume_vertical_events", resumed.vertical_slice.drain_ui_events())
	resumed.call("_sync_vertical_state")
	resumed.call("_update_ui")
	resumed.call("_refresh_transport_planning_panel")
	resumed.call("_refresh_onboarding_guide")
	await _settle(4)
	package_wait_target = resumed.onboarding_guide.target_control() as Button
	var plan_route_bus := resumed.find_child("PlanRoute_bus", true, false) as Button
	var package_quote: Dictionary = resumed.vertical_slice.transport_session_package_quote(resumed.city_grid)
	var package_active_jobs: Array = resumed.vertical_slice.construction.active_jobs()
	var package_available_workers: int = int(resumed.vertical_slice.construction.available_workers())
	var package_requested_workers: int = int(package_quote.get("requested_workers", -1))
	route_session = resumed.vertical_slice.transport_planning_session_snapshot()
	_check(bool(package_quote.get("ok", false)) and bool(package_quote.get("can_afford", false)) and not bool(package_quote.get("can_start", true)), "route-edit package waits when the otherwise valid affordable quote lacks workers")
	_check(package_available_workers < package_requested_workers and package_active_jobs.size() == 1 and int(Dictionary(package_active_jobs[0]).get("worker_count", 0)) == 20, "natural-wait fixture has one short real blocker and the exact package worker shortage")
	_check(package_continue_control != null and package_continue_control.is_visible_in_tree() and package_continue_control.disabled, "worker shortage keeps the actual package Continue visible and disabled")
	var package_wait_message := (resumed.onboarding_guide.get_node("OnboardingMessage") as Label).text
	var package_modal_close := resumed.find_child("CloseButton", true, false) as Button
	_check(package_wait_target == null and resumed.onboarding_guide.is_waiting_mode(), "disabled package Continue immediately uses the non-modal waiting presentation")
	_check("人力不足" in package_wait_message and "可先處理城市與工程" in package_wait_message, "open route modal explains the real worker shortage and leaves the defer action available")
	_check(package_modal_close != null and package_modal_close.is_visible_in_tree() and not package_modal_close.disabled, "the real municipal Close remains available beside non-modal guidance")
	_check(package_wait_target != plan_route_bus, "route package wait guide does not target PlanRoute_bus or require legacy station_tile_ids")
	if package_modal_close == null or package_active_jobs.size() != 1:
		await TestCleanup.finish(self, [resumed], 1)
		return

	var blocking_job: Dictionary = Dictionary(package_active_jobs[0]).duplicate(true)
	var blocking_job_id := str(blocking_job.get("id", ""))
	var blocking_remaining_days := int(blocking_job.get("projected_remaining_days", 0))
	var wait_session_before: Dictionary = route_session.duplicate(true)
	var wait_transport_before: Dictionary = resumed.vertical_slice.transport.to_dict()
	var wait_job_count_before: int = resumed.vertical_slice.construction.jobs.size()
	var wait_receipt_count_before: int = resumed.onboarding_progress.receipts().size()
	var wait_package_ledger_before := _ledger_reason_count(resumed, "construction.transport_package_total")
	await _click_at(package_modal_close.get_global_rect().get_center())
	await _settle(4)
	_check(not resumed.municipal_overlay.is_open() and not resumed.vertical_slice.is_time_paused(), "actual Close hides the municipal modal and resumes the city clock")
	var worker_wait_message := (resumed.onboarding_guide.get_node("OnboardingMessage") as Label).text
	_check(resumed.onboarding_guide.is_waiting_mode() and resumed.onboarding_guide.target_control() == null and resumed._resolve_route_onboarding_target() == null, "closed route package suppresses the Municipal re-entry loop with a non-modal waiting card while authority is not ready")
	_check("人力不足" in worker_wait_message and "可先處理城市與工程" in worker_wait_message, "worker wait card explains the real shortage and leaves the defer action available")
	_check(resumed.vertical_slice.transport_planning_session_snapshot() == wait_session_before, "closing the modal preserves the complete route-package draft")
	if blocking_job_id.is_empty() or blocking_remaining_days <= 0:
		await TestCleanup.finish(self, [resumed], 1)
		return

	var clock_seconds_per_day := float(resumed.vertical_slice.session.clock.day_length_seconds)
	var wait_tick_limit: int = int(ceil(clock_seconds_per_day)) * (blocking_remaining_days + 1)
	var wait_tick_count := 0
	while wait_tick_count < wait_tick_limit and str(Dictionary(resumed.vertical_slice.construction.jobs.get(blocking_job_id, {})).get("status", "")) == "active":
		resumed._process(1.0)
		wait_tick_count += 1
	var completed_blocking_job: Dictionary = Dictionary(resumed.vertical_slice.construction.jobs.get(blocking_job_id, {}))
	_check(wait_tick_count > 0 and wait_tick_count <= wait_tick_limit and str(completed_blocking_job.get("status", "")) == "completed", "bounded Main process-frame time naturally completes the original blocking Residence job")
	_check(resumed.vertical_slice.transport_planning_session_snapshot() == wait_session_before, "natural construction completion preserves the uncommitted route-package session and drafts")
	_check(resumed.vertical_slice.transport.to_dict() == wait_transport_before and resumed.vertical_slice.construction.jobs.size() == wait_job_count_before, "natural wait creates no route, transport project, station, or package construction job")
	_check(resumed.onboarding_progress.receipts().size() == wait_receipt_count_before and _ledger_reason_count(resumed, "construction.transport_package_total") == wait_package_ledger_before, "natural wait produces no route receipt or package ledger transaction")
	var municipal_wait_target := resumed.onboarding_guide.target_control() as Button
	_check(municipal_wait_target != null and municipal_wait_target.name == "MunicipalButton" and municipal_wait_target.is_visible_in_tree() and not resumed.vertical_slice.is_time_paused(), "natural completion restores the Municipal guide only after authority becomes ready")
	print("ROUTE_GUIDE_R8_NATURAL_WAIT_JSON=" + JSON.stringify({
		"blocking_job_id": blocking_job_id,
		"blocking_remaining_days": blocking_remaining_days,
		"clock_seconds_per_day": clock_seconds_per_day,
		"wait_tick_count": wait_tick_count,
		"available_workers_before": package_available_workers,
		"requested_workers": package_requested_workers,
		"available_workers_after": resumed.vertical_slice.construction.available_workers(),
	}))

	if municipal_wait_target == null:
		_cleanup_save()
		await TestCleanup.finish(self, [resumed], 1)
		return
	await _click_at(municipal_wait_target.get_global_rect().get_center())
	await _settle(6)
	package_quote = resumed.vertical_slice.transport_session_package_quote(resumed.city_grid)
	var package_continue_target := resumed.onboarding_guide.target_control() as Button
	_check(resumed.municipal_overlay.current_page() == "transport_planning" and resumed.vertical_slice.is_time_paused(), "actual Municipal input re-enters the active route package directly and pauses the modal")
	_check(bool(package_quote.get("ok", false)) and bool(package_quote.get("can_start", false)), "natural worker release makes the same package quote startable")
	_check(package_continue_target != null and package_continue_target == package_continue_control and package_continue_target.name == "TransportPlanningSessionContinue" and not package_continue_target.disabled, "re-entered route_edit automatically guides the visible enabled Continue for the actual package commit")
	if package_continue_target == null or not bool(package_quote.get("can_start", false)):
		await TestCleanup.finish(self, [resumed], 1)
		return
	var package_treasury_before := int(resumed.vertical_slice.treasury_balance())
	var package_jobs_before : int = resumed.vertical_slice.construction.jobs.size()
	var package_negative_ledger_before := _negative_ledger_count(resumed)
	var package_receipts_before : int = resumed.onboarding_progress.receipts().size()
	await _click_at(package_continue_target.get_global_rect().get_center())
	await _settle(7)
	var committed_session: Dictionary = resumed.vertical_slice.transport_planning_session_snapshot()
	var expected_new_jobs := Array(package_quote.get("station_placements", [])).size() + Array(package_quote.get("support_plans", [])).size()
	if not Array(Dictionary(package_quote.get("route_project_plan", {})).get("segments", [])).is_empty():
		expected_new_jobs += 1
	_check(str(committed_session.get("state", "")) == "waiting_construction" and str(committed_session.get("resume_state", "")) == "route_edit", "actual Continue commits one package into the expected waiting session")
	_check(Array(committed_session.get("station_refs", [])).size() == 2 and not Array(committed_session.get("network_refs", [])).is_empty(), "committed package owns station and network job references")
	_check(resumed.vertical_slice.construction.jobs.size() == package_jobs_before + expected_new_jobs, "actual package commit creates exactly the quoted station, corridor, and support jobs")
	_check(package_treasury_before - int(resumed.vertical_slice.treasury_balance()) == int(package_quote.get("total_cost", -1)), "actual package commit posts the exact quoted debit")
	_check(_negative_ledger_count(resumed) == package_negative_ledger_before + 1, "actual package commit posts exactly one negative ledger entry")
	_check(resumed.onboarding_progress.current_target() == "fiscal" and resumed.onboarding_progress.receipts().size() == package_receipts_before + 1, "one successful package produces exactly one route receipt and advances to fiscal")
	_check(resumed.onboarding_guide.is_waiting_mode() and resumed.onboarding_guide.target_control() == null, "post-package fiscal segment waits instead of inserting guidance into the foreground modal")
	await _advance_to_onboarding_due(resumed, "fiscal")
	var fiscal_municipal_target := resumed.onboarding_guide.target_control() as Control
	_check(fiscal_municipal_target != null and fiscal_municipal_target.name == "MunicipalButton" and fiscal_municipal_target.is_visible_in_tree(), "due fiscal segment resumes at the real Municipal entry")
	if fiscal_municipal_target == null:
		await TestCleanup.finish(self, [resumed], 1)
		return
	await _click_at(fiscal_municipal_target.get_global_rect().get_center())
	await _settle(4)
	var finance_target := resumed.onboarding_guide.target_control() as Control
	_check(finance_target != null and finance_target.name == "FinanceButton" and finance_target.is_visible_in_tree(), "Municipal opens the due fiscal guide at Finance")
	if finance_target == null:
		await TestCleanup.finish(self, [resumed], 1)
		return
	await _click_at(finance_target.get_global_rect().get_center())
	await _settle(4)
	_check(resumed.municipal_overlay.current_page() == "finance", "guided Finance remains reachable after the real route package commit")

	_cleanup_save()
	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Guided onboarding formal entry test passed.")
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


func _advance_to_onboarding_due(main, expected_target: String) -> void:
	var current_day: int = main.vertical_slice.game_day()
	var due_day: int = main.onboarding_progress.due_game_day()
	_check(main.onboarding_progress.current_target() == expected_target, "%s is the scheduled next guided segment" % expected_target)
	_check(due_day == current_day + 3 and main.onboarding_progress.is_waiting(current_day), "%s waits three full game days" % expected_target)
	if main.municipal_overlay != null and main.municipal_overlay.is_open():
		main.municipal_overlay.close_overlay()
	await _settle(2)
	main.call("_sync_time_pause_for_ui")
	_check(not main.vertical_slice.is_time_paused(), "%s schedule releases tutorial time pause" % expected_target)
	var events: Array[Dictionary] = main.vertical_slice.advance_days(
		due_day - current_day,
		main.call("_vertical_city_context"),
		false
	)
	main.call("_consume_vertical_events", events)
	main.call("_sync_vertical_state")
	main.call("_update_ui")
	main.call("_refresh_onboarding_guide")
	await _settle(3)
	_check(main.vertical_slice.game_day() == due_day and main.onboarding_progress.is_current_target_available(due_day), "%s opens on its exact due day" % expected_target)


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame


func _click_at(position: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.pressed = true
	down.position = position
	down.global_position = position
	root.push_input(down, true)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = position
	up.global_position = position
	root.push_input(up, true)
	await _settle(2)


func _select_progressive_choice(control, choice_id: String) -> bool:
	if control == null:
		return false
	for index in control.item_count:
		if str(control.get_item_metadata(index)) == choice_id:
			control.item_selected.emit(index)
			return true
	return false


func _assert_wrong_page_resolvers_use_foreground_back(main, expected_back: Control) -> void:
	for resolver_call in [
		["_resolve_fiscal_onboarding_target"],
		["_resolve_city_data_onboarding_target"],
		["_resolve_public_affairs_onboarding_target"],
		["_resolve_governance_onboarding_target"],
		["_resolve_justice_onboarding_target", "judicial"],
		["_resolve_justice_onboarding_target", "oversight"],
	]:
		var method_name := str(resolver_call[0])
		var target_variant: Variant = main.call(method_name, resolver_call[1]) if resolver_call.size() > 1 else main.call(method_name)
		var target := target_variant as Control
		_check(target == expected_back and target != main.municipal_button, "%s keeps the visible Municipal BackButton in the foreground on an unrelated open page" % method_name)


func _assert_cinematic_modal_order(main, phase: String) -> void:
	var cinematic := main.tutorial_overlay as Control
	var viewport_rect := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	_check(cinematic != null and not cinematic.z_as_relative and cinematic.z_index == RenderingServer.CANVAS_ITEM_Z_MAX, "%s owns an absolute top-level canvas order" % phase)
	_check(cinematic != null and viewport_rect.encloses(cinematic.get_global_rect()), "%s covers the resized viewport" % phase)
	_check(_draws_after(cinematic, main.status_hud) and _draws_after(cinematic, main.action_dock), "%s draws above every persistent HUD surface" % phase)
	for actor: Button in main.get_visible_npc_actors():
		_check(cinematic.z_index > actor.z_index, "%s draws above each depth-sorted NPC actor" % phase)
	_check(cinematic.get_parent() == main and cinematic.get_index() == main.get_child_count() - 1, "%s moves to the front of the real Main sibling stack" % phase)


func _assert_guide_presentation(main, expected_target: Control, phase: String) -> void:
	var guide := main.onboarding_guide as Control
	var viewport_rect := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	_check(guide != null and guide.target_control() == expected_target, "%s keeps the authoritative product target" % phase)
	_check(guide != null and not guide.z_as_relative and guide.z_index == RenderingServer.CANVAS_ITEM_Z_MAX, "%s owns absolute modal presentation order" % phase)
	if main.municipal_overlay != null and main.municipal_overlay.is_open():
		_check(_draws_after(guide, main.municipal_overlay), "%s remains visible above the Municipal modal containing its target" % phase)
	var target_rect := expected_target.get_global_rect() if expected_target != null else Rect2()
	for node_name in ["OnboardingFairy", "OnboardingMessage", "OnboardingArrow"]:
		var companion := guide.get_node_or_null(node_name) as Control
		_check(companion != null and companion.is_visible_in_tree(), "%s keeps %s visible" % [phase, node_name])
		if companion != null:
			_check(viewport_rect.encloses(companion.get_global_rect()), "%s keeps %s inside the viewport" % [phase, node_name])
	var fairy := guide.get_node_or_null("OnboardingFairy") as Control
	var message := guide.get_node_or_null("OnboardingMessage") as Control
	_check(fairy != null and not fairy.get_global_rect().intersects(target_rect), "%s keeps the fairy outside the target hit area" % phase)
	_check(message != null and not message.get_global_rect().intersects(target_rect), "%s keeps the readable message outside the target hit area" % phase)
	var target_center := target_rect.get_center()
	for index in 4:
		_check(not (guide.get_child(index) as Control).get_global_rect().has_point(target_center), "%s keeps mask %d outside the target hole" % [phase, index])


func _draws_after(front: Control, back: Control) -> bool:
	if front == null or back == null:
		return false
	if front.z_index != back.z_index:
		return front.z_index > back.z_index
	return front.get_parent() == back.get_parent() and front.get_index() > back.get_index()


func _presentation_authority_snapshot(main) -> Dictionary:
	return {
		"game_day": main.vertical_slice.game_day(),
		"treasury": main.vertical_slice.treasury_balance(),
		"construction_jobs": main.vertical_slice.session.state.construction_jobs.duplicate(true),
		"report_history": main.city_report_history_service.snapshot(),
		"receipts": main.onboarding_progress.receipts(),
	}


func _route_guide_authority_snapshot(main) -> Dictionary:
	return {
		"terrain": main.vertical_slice.terrain_map.to_dict(),
		"planning_session": main.vertical_slice.transport_planning_session_snapshot(),
		"construction": main.vertical_slice.construction.to_dict(),
		"ledger": main.vertical_slice.session.state.ledger.get_entries(),
		"treasury": main.vertical_slice.treasury_balance(),
		"transport": main.vertical_slice.transport.to_dict(),
		"population": main.vertical_slice.population.to_dict(),
		"city_grid": main.city_grid.duplicate(),
		"receipts": main.onboarding_progress.receipts(),
	}


func _approved_station_target(main, target: Button, quote: Dictionary) -> bool:
	if target == null or target.disabled or not target.is_visible_in_tree():
		return false
	if not bool(quote.get("ok", false)) or str(quote.get("status", "")) != "approved" or not bool(quote.get("can_afford", false)):
		return false
	var footprint: Array[int] = _int_array(quote.get("occupied_tile_ids", []))
	if footprint.is_empty():
		return false
	for tile_id: int in footprint:
		if not main._route_onboarding_grid_button_is_safe(tile_id):
			return false
	return true


func _find_illegal_station_grid_target(main, session: Dictionary) -> Button:
	var workers := int(main.vertical_slice_panel.selected_worker_count()) if main.vertical_slice_panel != null else 5
	for tile_id in main.grid_buttons.size():
		var button := main.grid_buttons[tile_id] as Button
		if button == null or button.disabled or not button.is_visible_in_tree():
			continue
		var quote: Dictionary = main.vertical_slice.placement_footprint_quote(str(session.get("station_blueprint_name", "")), tile_id, workers)
		if (
			not bool(quote.get("ok", false))
			or str(quote.get("status", "")) != "approved"
			or not bool(quote.get("can_afford", false))
			or not main._route_onboarding_grid_footprint_is_safe(_int_array(quote.get("occupied_tile_ids", [])))
		):
			return button
	return null


func _find_illegal_route_first_tile(main, stations: Array[Dictionary]) -> int:
	var reserved := _station_candidate_footprint_tiles(stations)
	var first_access: Array[int] = main._route_package_corridor_access_tiles(int(stations[0].get("anchor_tile_id", -1)), reserved)
	var second_access: Array[int] = main._route_package_corridor_access_tiles(int(stations[1].get("anchor_tile_id", -1)), reserved)
	for tile_id in main.grid_buttons.size():
		if tile_id not in first_access and tile_id not in second_access and main._route_package_corridor_tile_is_available(tile_id, reserved):
			return tile_id
	return -1


func _start_route_wait_blocker(main, reserved_tiles: Array[int]) -> Dictionary:
	for tile_id in main.grid_buttons.size():
		if reserved_tiles.has(tile_id):
			continue
		var quote: Dictionary = main.vertical_slice.terrain_flatten_quote(tile_id, 20)
		if bool(quote.get("ok", false)) and bool(quote.get("can_start", false)) and int(quote.get("duration_days", 0)) > 1:
			return main.vertical_slice.flatten_terrain(tile_id, 20)
	return {}


func _station_placements_are_distinct(placements: Array) -> bool:
	if placements.size() != 2 or not placements[0] is Dictionary or not placements[1] is Dictionary:
		return false
	var first: Dictionary = placements[0]
	var second: Dictionary = placements[1]
	return (
		int(first.get("anchor_tile_id", -1)) != int(second.get("anchor_tile_id", -1))
		and _tile_arrays_do_not_overlap(first.get("occupied_tile_ids", []), second.get("occupied_tile_ids", []))
	)


func _tile_arrays_do_not_overlap(first: Variant, second: Variant) -> bool:
	var first_tiles := _int_array(first)
	for tile_id: int in _int_array(second):
		if first_tiles.has(tile_id):
			return false
	return true


func _station_candidate_footprint_tiles(stations: Array[Dictionary]) -> Array[int]:
	var result: Array[int] = []
	for station: Dictionary in stations:
		for tile_id: int in _int_array(station.get("occupied_tile_ids", [])):
			if not result.has(tile_id):
				result.append(tile_id)
	return result


func _station_footprint_tiles(placements: Array) -> Array[int]:
	var result: Array[int] = []
	for placement_value: Variant in placements:
		if not placement_value is Dictionary:
			continue
		for tile_id: int in _int_array(Dictionary(placement_value).get("occupied_tile_ids", [])):
			if not result.has(tile_id):
				result.append(tile_id)
	return result


func _int_array(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if not value is Array and not value is PackedInt32Array and not value is PackedInt64Array:
		return result
	for item: Variant in value:
		var number := int(item)
		if not result.has(number):
			result.append(number)
	return result


func _negative_ledger_count(main) -> int:
	var result := 0
	for entry: Dictionary in main.vertical_slice.session.state.ledger.get_entries():
		if int(entry.get("amount", 0)) < 0:
			result += 1
	return result


func _ledger_reason_count(main, reason_tag: String) -> int:
	var result := 0
	for entry: Dictionary in main.vertical_slice.session.state.ledger.get_entries():
		if str(entry.get("reason_tag", "")) == reason_tag:
			result += 1
	return result


func _scroll_ancestor(control: Control) -> ScrollContainer:
	var ancestor := control.get_parent() if control != null else null
	while ancestor != null:
		if ancestor is ScrollContainer:
			return ancestor as ScrollContainer
		ancestor = ancestor.get_parent()
	return null


func _cleanup_save() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	for candidate in [absolute_path, absolute_path + ".tmp", absolute_path + ".bak"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _fail(message: String) -> void:
	_failed = true
	push_error("Guided onboarding entry check failed: %s" % message)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)
