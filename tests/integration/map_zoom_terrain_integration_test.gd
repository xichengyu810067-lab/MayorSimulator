extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const CoordinatorScript := preload("res://scripts/app/vertical_slice_coordinator.gd")
const BuildingTerrainLabelsScript := preload("res://data/catalogs/building_terrain_labels.gd")

var _failed := false
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var packed_main: PackedScene = load("res://scenes/Main.tscn")
	_check(packed_main != null, "Main scene could not be loaded")
	if packed_main == null:
		await TestCleanup.finish(self, [], 1)
		return

	var main = packed_main.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	if main.start_screen != null:
		main.start_screen.hide()
	if main.tutorial_overlay != null:
		main.tutorial_overlay.hide()
	main._game_started = true
	main._layout_map_stage()

	_check(int(main.GRID_SIZE) == 10, "map grid is not 10x10")
	_check(int(main.CELL_COUNT) == 100, "map does not expose 100 logical tiles")
	_check(main.grid_buttons.size() == 100 and main.city_grid.size() == 100, "visual and city grids are not both 100 cells")
	_check(main.GRID_CELL_SIZE.x == main.GRID_CELL_SIZE.y, "visible map cells are not square")
	_check(main.GRID_CELL_SIZE == Vector2(70, 70), "visible map does not use the canonical square cell size")
	_check(main.vertical_slice.terrain_map.coordinate_for_tile_id(0) == Vector2i(1, 1), "legacy tile 0 did not keep its stable central coordinate")
	_check(main.vertical_slice.terrain_map.coordinate_for_tile_id(64) == Vector2i(0, 0), "new outer-ring tile 64 is not mapped to the expanded edge")
	_check(main.vertical_slice.terrain_map.coordinate_for_tile_id(12) == Vector2i(5, 2), "stable tile 12 coordinate changed")
	_check(main.vertical_slice.terrain_map.base_kind(12) == "river_lake", "new city tile 12 did not use square backdrop classification")
	_check(not main.vertical_slice.terrain_map.is_buildable(12) and not main.vertical_slice.terrain_map.is_walkable(12), "new city tile 12 is not blocked")
	_check(str(main.vertical_slice.terrain_snapshot().get("classification_provenance", "")) == "backdrop_square_layout_4", "new city terrain lacks square-layout provenance")
	for kind: String in ["trees", "hill_cliff", "river_lake"]:
		var found := false
		for state_variant: Variant in main.vertical_slice.terrain_map.all_tile_states():
			var state: Dictionary = state_variant
			if str(state.get("effective_kind", "")) == kind:
				found = true
				break
		_check(found, "default city terrain omits %s" % kind)
	for legacy_transport_kind: String in ["road_path", "rail_track"]:
		var found_legacy_transport := false
		for state_variant: Variant in main.vertical_slice.terrain_map.all_tile_states():
			if str(Dictionary(state_variant).get("effective_kind", "")) == legacy_transport_kind:
				found_legacy_transport = true
				break
		_check(not found_legacy_transport, "new games must not pre-seed an arbitrary %s network" % legacy_transport_kind)

	var previous_zoom: float = main.map_zoom
	var previous_stage_scale: float = main.map_stage.scale.x
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = main.map_viewport.get_global_rect().get_center()
	wheel.global_position = wheel.position
	main._input(wheel)
	await process_frame
	_check(main.map_zoom > previous_zoom, "mouse wheel did not increase map zoom")
	_check(main.map_stage.scale.x > previous_stage_scale, "map stage scale did not follow wheel zoom")
	var tile_scale: Vector2 = main.tile_layer.get_global_transform_with_canvas().get_scale()
	var npc_scale: Vector2 = main.npc_layer.get_global_transform_with_canvas().get_scale()
	_check(tile_scale.is_equal_approx(npc_scale), "buildings and NPC layers do not share the same zoom transform")
	_check(main.grid_buttons[0].get_parent() == main.tile_layer and main.npc_map_controller.get_parent() == main.npc_layer, "map actors are not parented under the synchronously scaled stage")
	var pan_start: Vector2 = main.map_pan_offset
	var pan_press := InputEventMouseButton.new()
	pan_press.button_index = MOUSE_BUTTON_MIDDLE
	pan_press.pressed = true
	pan_press.position = main.map_viewport.get_global_rect().get_center()
	pan_press.global_position = pan_press.position
	main._input(pan_press)
	var pan_motion := InputEventMouseMotion.new()
	pan_motion.position = pan_press.position + Vector2(42.0, -28.0)
	pan_motion.global_position = pan_motion.position
	pan_motion.relative = Vector2(42.0, -28.0)
	main._input(pan_motion)
	await process_frame
	_check(not main.map_pan_offset.is_equal_approx(pan_start), "middle-button drag did not pan the city-builder map")
	var pan_release := InputEventMouseButton.new()
	pan_release.button_index = MOUSE_BUTTON_MIDDLE
	pan_release.pressed = false
	pan_release.position = pan_motion.position
	pan_release.global_position = pan_release.position
	main._input(pan_release)
	_check(not main._map_pan_drag_active, "middle-button map drag did not end on release")

	var terrain_tile := -1
	var building_quote_before: Dictionary = {}
	var road_quote_before: Dictionary = {}
	for state_variant: Variant in main.vertical_slice.terrain_map.all_tile_states():
		var candidate: Dictionary = state_variant
		var candidate_id := int(candidate.get("tile_id", -1))
		if (
			BuildingTerrainLabelsScript.is_buildable(candidate_id)
			and not bool(candidate.get("walkable", true))
			and bool(candidate.get("flattenable", false))
			and main.city_grid[candidate_id] == ""
			and main._is_tile_inside_hud_safe_area(candidate_id)
		):
			var building_candidate: Dictionary = main.vertical_slice.placement_footprint_quote("住宅", candidate_id, 5)
			var road_candidate: Dictionary = main.vertical_slice.transport_project_quote("road", "build", [candidate_id], 5, main.city_grid)
			var flatten_candidate: Dictionary = main.vertical_slice.terrain_flatten_quote(candidate_id)
			if bool(building_candidate.get("ok", false)) and bool(building_candidate.get("can_afford", false)) and bool(flatten_candidate.get("can_start", false)) and not bool(road_candidate.get("ok", false)) and main._transport_quote_error(road_candidate) == "terrain_not_flat":
				terrain_tile = candidate_id
				building_quote_before = building_candidate
				road_quote_before = road_candidate
				break
	_check(terrain_tile >= 0, "no empty HUD-safe reviewed-building candidate has a natural blocker, affordable full residence footprint, startable flatten quote, and road terrain_not_flat quote")
	if terrain_tile < 0:
		await TestCleanup.finish(self, [main], 1)
		return
	var terrain_before: Dictionary = main.vertical_slice.terrain_state_for_tile(terrain_tile)
	print("TERRAIN_FIXTURE_PRIMARY tile_id=%d reviewed_buildable=%s natural_kind=%s natural_walkable=%s building_quote=%s road_quote=%s" % [
		terrain_tile, str(BuildingTerrainLabelsScript.is_buildable(terrain_tile)), str(terrain_before.get("effective_kind", "")),
		str(terrain_before.get("walkable", true)), JSON.stringify(building_quote_before), JSON.stringify(road_quote_before),
	])
	_check(bool(building_quote_before.get("ok", false)) and Array(building_quote_before.get("occupied_tile_ids", [])).has(terrain_tile), "reviewed full residence footprint was not accepted before natural terrain earthworks")
	var other_non_flat_tile := -1
	for other_state_variant: Variant in main.vertical_slice.terrain_map.all_tile_states():
		var other_state: Dictionary = other_state_variant
		var other_tile_id := int(other_state.get("tile_id", -1))
		if other_tile_id != terrain_tile and not bool(other_state.get("walkable", true)):
			other_non_flat_tile = other_tile_id
			break
	_check(other_non_flat_tile >= 0, "square terrain fixture lacks an independent non-flat control tile")
	var human_walkable_blocker := -1
	var human_blocked_quote: Dictionary = {}
	for control_id in BuildingTerrainLabelsScript.CELL_COUNT:
		if BuildingTerrainLabelsScript.is_blocked(control_id) and main.vertical_slice.terrain_map.is_walkable(control_id) and main.city_grid[control_id] == "":
			var candidate_quote: Dictionary = main.vertical_slice.placement_footprint_quote("公園", control_id, 5)
			if not bool(candidate_quote.get("ok", false)) and int(candidate_quote.get("blocked_tile_id", -1)) == control_id:
				human_walkable_blocker = control_id
				human_blocked_quote = candidate_quote
				break
	_check(human_walkable_blocker >= 0, "no naturally walkable, empty, human-reviewed blocked control tile rejected a full footprint quote")
	if human_walkable_blocker < 0:
		await TestCleanup.finish(self, [main], 1)
		return
	print("TERRAIN_FIXTURE_HUMAN_BLOCKED tile_id=%d reviewed_blocked=%s natural_walkable=%s quote=%s" % [
		human_walkable_blocker, str(BuildingTerrainLabelsScript.is_blocked(human_walkable_blocker)),
		str(main.vertical_slice.terrain_map.is_walkable(human_walkable_blocker)), JSON.stringify(human_blocked_quote),
	])
	var human_blocked_start: Dictionary = main.vertical_slice.start_approved_building("公園", human_walkable_blocker, 5)
	print("TERRAIN_HUMAN_BLOCKED_START tile_id=%d result=%s" % [human_walkable_blocker, JSON.stringify(human_blocked_start)])
	_check(not bool(human_blocked_start.get("ok", false)) and int(human_blocked_start.get("blocked_tile_id", -1)) == human_walkable_blocker, "human-reviewed blocker with naturally walkable backdrop accepted a building start")

	var station_tile := -1
	var station_quote: Dictionary = {}
	for station_state_variant: Variant in main.vertical_slice.terrain_map.all_tile_states():
		var station_state: Dictionary = station_state_variant
		var station_id := int(station_state.get("tile_id", -1))
		if BuildingTerrainLabelsScript.is_buildable(station_id) and not bool(station_state.get("buildable", true)) and main.city_grid[station_id] == "" and main._is_tile_inside_hud_safe_area(station_id):
			var candidate_station_quote: Dictionary = main.vertical_slice.placement_footprint_quote("公車站", station_id, 5)
			if bool(candidate_station_quote.get("ok", false)) and str(candidate_station_quote.get("status", "")) == "approved":
				station_tile = station_id
				station_quote = candidate_station_quote
				break
	_check(station_tile >= 0, "no human-reviewed station footprint over a non-flat backdrop is valid outside the HUD safe area")
	if station_tile < 0:
		await TestCleanup.finish(self, [main], 1)
		return
	print("TERRAIN_FIXTURE_STATION tile_id=%d reviewed_buildable=%s natural_buildable=%s full_quote=%s" % [
		station_tile, str(BuildingTerrainLabelsScript.is_buildable(station_tile)),
		str(main.vertical_slice.terrain_map.is_buildable(station_tile)), JSON.stringify(station_quote),
	])
	var station_funds_before := int(main.vertical_slice.treasury_balance())
	var station_jobs_before := int(main.vertical_slice.construction.jobs.size())
	main._on_transport_station_requested("公車站")
	_check(main._is_transport_station_session_placement(), "approved station entry did not enter the real station placement session")
	main._update_tile_visual(station_tile, "")
	var station_button = main.grid_buttons[station_tile]
	_check(bool(station_button.get("placement_allowed")) and bool(station_button.get("terrain_buildable")), "station UI still uses stale natural terrain buildability instead of reviewed placement")
	_check(not station_button.tooltip_text.contains("先整平"), "station UI still tells players to flatten a reviewed-buildable full footprint")
	main._on_grid_pressed(station_tile)
	var station_session: Dictionary = main.vertical_slice.transport_planning_session_snapshot()
	_check(main._pending_terrain_tile == -1 and not main.placement_level_button.visible, "valid station footprint opened a terrain flatten action")
	_check(Array(Dictionary(station_session.get("route_draft", {})).get("station_placements", [])).size() == 1, "valid station footprint did not enter the existing draft flow")
	_check(main.vertical_slice.treasury_balance() == station_funds_before and main.vertical_slice.construction.jobs.size() == station_jobs_before, "station draft charged funds or created construction")
	main._cancel_building_placement(false)
	var station_closed: Dictionary = main.vertical_slice.cancel_transport_planning_session()
	_check(bool(station_closed.get("ok", false)), "isolated station draft could not be closed before road terrain fixture")
	var no_reserved_tiles: Array[int] = []
	main._set_onboarding_npc_reservation(no_reserved_tiles)
	main.debug_sync_npc_navigation_obstacles()
	var terrain_center: Vector2 = main._iso_tile_center(terrain_tile)
	var other_terrain_center: Vector2 = main._iso_tile_center(other_non_flat_tile)
	var npc_navigation = main.get_npc_navigation_grid()
	_check(not npc_navigation.is_position_walkable(terrain_center), "non-flat square center is walkable before earthworks")
	_check(not npc_navigation.is_position_walkable(other_terrain_center), "independent non-flat square center is unexpectedly walkable")
	_check(main.is_npc_tile_blocked(human_walkable_blocker), "human-reviewed blocked tile with walkable natural terrain was opened to NPCs")
	_check(
		str(terrain_before.get("source_asset", "")).ends_with("city-map-background.png")
		and not Array(terrain_before.get("backdrop_feature_ids", [])).is_empty(),
		"terrain fixture is not derived from the original backdrop"
	)
	var terrain_visual_contract: Dictionary = main.grid_buttons[terrain_tile].get_visual_animation_contract()
	var terrain_visual_debug: Dictionary = main.grid_buttons[terrain_tile].get_visual_animation_debug_snapshot()
	_check(not bool(terrain_visual_contract.get("decorative_natural_terrain_tiles", true)), "natural backdrop terrain is still drawn as a decorative tile")
	_check(str(terrain_visual_contract.get("natural_terrain_visual_source", "")) == "city-map-background.png", "tile renderer does not preserve the original background as its terrain visual")
	_check(not bool(terrain_visual_debug.get("animation_active", true)), "background trees/water still run obsolete tile-local terrain animation")
	_check(bool(building_quote_before.get("ok", false)) and BuildingTerrainLabelsScript.is_buildable(terrain_tile), "natural backdrop scenery incorrectly overrode human-reviewed building placement")
	main._on_transport_infrastructure_requested("road", "build")
	_check(main.map_action_mode == "transport_infrastructure" and main.transport_plan_kind == "road", "real road map action did not enter terrain fixture")
	main._on_grid_pressed(terrain_tile)
	_check(main._pending_terrain_tile == terrain_tile and main.transport_plan_tiles.is_empty(), "road quote terrain_not_flat did not select the terrain tile without adding a route segment")
	_check(main.placement_level_button.visible and not main.placement_level_button.disabled, "real road terrain flatten action is not exposed for affordable non-flat terrain")
	_check(main.placement_level_button.tooltip_text.contains("不能解除人審禁建"), "terrain button still promises to lift human-reviewed building restrictions")
	var funds_before: int = int(main.vertical_slice.treasury_balance())
	var quote: Dictionary = main.vertical_slice.terrain_flatten_quote(terrain_tile)
	var workers_before: int = int(main.vertical_slice.construction.available_workers())
	_check(int(quote.get("duration_days", 0)) > 0, "terrain quote omitted its construction duration")
	_check(int(quote.get("total_cost", 0)) == int(quote.get("fixed_cost", 0)) + int(quote.get("labor_cost", 0)), "terrain quote total is not fixed plus labor cost")
	_check(bool(quote.get("can_start", false)), "affordable terrain quote cannot start")
	main._flatten_pending_terrain()
	await process_frame
	var flatten_job: Dictionary = main.vertical_slice.active_construction_for_tile(terrain_tile)
	_check(not flatten_job.is_empty(), "flatten action did not start a construction job")
	_check(not main.vertical_slice.terrain_map.is_buildable(terrain_tile), "natural terrain flattened immediately instead of waiting for completion")
	_check(not main.vertical_slice.terrain_map.is_walkable(terrain_tile), "terrain became walkable before earthworks completed")
	_check(main.vertical_slice.construction.available_workers() == workers_before - int(quote.get("worker_count", 0)), "terrain job did not reserve its quoted workers")
	_check(main.vertical_slice.treasury_balance() == funds_before - int(quote.get("total_cost", 0)), "terrain start did not deduct exactly the prepaid quote")
	_check(main.labels["funds"].text == main._format_currency(main.vertical_slice.treasury_balance()), "terrain start did not refresh the visible treasury balance in the same frame")
	main.debug_sync_npc_navigation_obstacles()
	_check(main.npc_map_controller._blocked_tiles.has(terrain_tile), "active terrain worksite stopped blocking the live NPC controller")
	var blocked_during_flatten: Dictionary = main.vertical_slice.start_approved_building("住宅", terrain_tile, 5)
	print("TERRAIN_BUILD_DURING_EARTHWORKS tile_id=%d result=%s" % [terrain_tile, JSON.stringify(blocked_during_flatten)])
	_check(not bool(blocked_during_flatten.get("ok", false)), "building construction started on active terrain earthworks")
	var transport_during_flatten: Dictionary = main.vertical_slice.transport_project_quote("road", "build", [terrain_tile], 5, main.city_grid)
	_check(not bool(transport_during_flatten.get("ok", false)), "transport construction started on active terrain earthworks")
	var remaining_days := int(flatten_job.get("projected_remaining_days", 0))
	if remaining_days > 1:
		var precompletion_events: Array[Dictionary] = main.vertical_slice.advance_days(remaining_days - 1, {}, false)
		main._consume_vertical_events(precompletion_events)
		_check(not main.vertical_slice.terrain_map.is_flattened(terrain_tile), "terrain flattened before the final construction day")
	var completion_events: Array[Dictionary] = main.vertical_slice.advance_days(1, {}, false)
	main._consume_vertical_events(completion_events)
	_check(main.vertical_slice.terrain_map.is_buildable(terrain_tile), "final construction day did not make natural terrain buildable for road work")
	_check(main.vertical_slice.terrain_map.is_walkable(terrain_tile), "final construction day did not make terrain walkable")
	_check(main.vertical_slice.construction.available_workers() == workers_before, "completed terrain job did not release its workers")
	_check(main.vertical_slice.treasury_balance() == funds_before - int(quote.get("total_cost", 0)), "terrain progression charged the prepaid quote more than once")
	main.debug_sync_npc_navigation_obstacles()
	_check(not main.npc_map_controller._blocked_tiles.has(terrain_tile), "completed terrain remained blocked in the live NPC controller")
	_check(npc_navigation.is_position_walkable(terrain_center), "flattened square center remains unwalkable after live synchronization")
	_check(not npc_navigation.is_position_walkable(other_terrain_center), "flattening one square center opened another non-flat tile")
	_check(main.is_npc_tile_blocked(human_walkable_blocker), "road earthworks released an independent human-reviewed NPC blocker")
	var post_flat_quote: Dictionary = main.vertical_slice.placement_footprint_quote("住宅", terrain_tile, 5)
	print("TERRAIN_BUILD_AFTER_FLATTEN tile_id=%d quote=%s" % [terrain_tile, JSON.stringify(post_flat_quote)])
	_check(bool(post_flat_quote.get("ok", false)) and Array(post_flat_quote.get("occupied_tile_ids", [])).has(terrain_tile), "flattening changed the reviewed full building footprint authority")
	var post_flat_start: Dictionary = main.vertical_slice.start_approved_building("住宅", terrain_tile, 5)
	print("TERRAIN_BUILD_START_AFTER_FLATTEN tile_id=%d result=%s" % [terrain_tile, JSON.stringify(post_flat_start)])
	_check(bool(post_flat_start.get("ok", false)), "reviewed building placement did not enter its existing construction pipeline after road earthworks")
	main.debug_sync_npc_navigation_obstacles()
	_check(main.is_npc_tile_blocked(terrain_tile), "active building construction stopped blocking NPCs after terrain earthworks")

	var save_path := "user://goal_2026_08_01/terrain_round_trip.json"
	main.vertical_slice.set_player_shell_state(main._capture_player_shell_state())
	_check(main.vertical_slice.save_game(save_path) == OK, "terrain integration save failed")
	var restored = CoordinatorScript.new(99, 10)
	_check(restored.load_game(save_path), "terrain integration save could not be loaded")
	_check(restored.terrain_map.is_flattened(terrain_tile) and restored.terrain_map.is_buildable(terrain_tile), "flattened terrain did not survive save/load")
	_check(not restored.active_construction_for_tile(terrain_tile).is_empty(), "post-flatten reviewed building construction did not survive save/load")
	var restored_human_quote: Dictionary = restored.placement_footprint_quote("公園", human_walkable_blocker, 5)
	_check(not bool(restored_human_quote.get("ok", false)) and int(restored_human_quote.get("blocked_tile_id", -1)) == human_walkable_blocker, "save/load reopened an independent human-reviewed blocked tile")

	var isolated = CoordinatorScript.new(8_020_703, 500_000)
	var blocked_nonflat_tile := -1
	var blocked_nonflat_quote: Dictionary = {}
	for blocked_id in BuildingTerrainLabelsScript.CELL_COUNT:
		if BuildingTerrainLabelsScript.is_blocked(blocked_id) and not isolated.terrain_map.is_walkable(blocked_id) and isolated.terrain_map.is_flattenable(blocked_id):
			var blocked_control_quote: Dictionary = isolated.placement_footprint_quote("公園", blocked_id, 5)
			var flatten_control_quote: Dictionary = isolated.terrain_flatten_quote(blocked_id)
			if not bool(blocked_control_quote.get("ok", false)) and int(blocked_control_quote.get("blocked_tile_id", -1)) == blocked_id and bool(flatten_control_quote.get("can_start", false)):
				blocked_nonflat_tile = blocked_id
				blocked_nonflat_quote = flatten_control_quote
				break
	_check(blocked_nonflat_tile >= 0, "no human-reviewed blocked natural non-flat tile permits isolated earthworks")
	if blocked_nonflat_tile >= 0:
		var blocked_preimage: Dictionary = isolated.terrain_state_for_tile(blocked_nonflat_tile)
		print("TERRAIN_FIXTURE_BLOCKED_FLATTEN tile_id=%d reviewed_blocked=%s natural_kind=%s quote=%s" % [
			blocked_nonflat_tile, str(BuildingTerrainLabelsScript.is_blocked(blocked_nonflat_tile)),
			str(blocked_preimage.get("effective_kind", "")), JSON.stringify(blocked_nonflat_quote),
		])
		var control_funds_before := int(isolated.treasury_balance())
		var isolated_started: Dictionary = isolated.flatten_terrain(blocked_nonflat_tile)
		_check(bool(isolated_started.get("ok", false)), "isolated natural terrain earthworks did not start on a human-reviewed blocked tile")
		if bool(isolated_started.get("ok", false)):
			var control_job: Dictionary = isolated_started.get("job", {})
			var control_days := int(control_job.get("projected_total_days", 0))
			_check(control_days > 0 and isolated.treasury_balance() == control_funds_before - int(blocked_nonflat_quote.get("total_cost", 0)), "isolated blocked-tile earthworks did not use its existing prepaid quote")
			var during_quote: Dictionary = isolated.placement_footprint_quote("公園", blocked_nonflat_tile, 5)
			_check(not bool(during_quote.get("ok", false)) and int(during_quote.get("blocked_tile_id", -1)) == blocked_nonflat_tile, "earthworks temporarily removed a human-reviewed building blocker")
			isolated.advance_days(control_days, {}, false)
			var after_quote: Dictionary = isolated.placement_footprint_quote("公園", blocked_nonflat_tile, 5)
			var after_start: Dictionary = isolated.start_approved_building("公園", blocked_nonflat_tile, 5)
			print("TERRAIN_BLOCKED_AFTER_FLATTEN tile_id=%d natural_walkable=%s quote=%s start=%s" % [
				blocked_nonflat_tile, str(isolated.terrain_map.is_walkable(blocked_nonflat_tile)),
				JSON.stringify(after_quote), JSON.stringify(after_start),
			])
			_check(isolated.terrain_map.is_flattened(blocked_nonflat_tile) and isolated.terrain_map.is_walkable(blocked_nonflat_tile), "isolated natural flatten job did not complete")
			_check(not bool(after_quote.get("ok", false)) and int(after_quote.get("blocked_tile_id", -1)) == blocked_nonflat_tile, "flatten completion removed a human-reviewed full-footprint blocker")
			_check(not bool(after_start.get("ok", false)) and int(after_start.get("blocked_tile_id", -1)) == blocked_nonflat_tile, "flatten completion allowed a start on human-reviewed blocked terrain")
			_check(isolated.treasury_balance() == control_funds_before - int(blocked_nonflat_quote.get("total_cost", 0)), "isolated flatten completion charged the prepaid quote again")

	if _failed:
		await TestCleanup.finish(self, [main], 1)
	else:
		print("Map zoom and terrain integration test passed. Checks=%d Cells=100" % _checks)
		await TestCleanup.finish(self, [main], 0)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Map zoom/terrain integration failed: %s" % message)
