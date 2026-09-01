extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const CoordinatorScript := preload("res://scripts/app/vertical_slice_coordinator.gd")

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
	for state_variant: Variant in main.vertical_slice.terrain_map.all_tile_states():
		var candidate: Dictionary = state_variant
		var candidate_id := int(candidate.get("tile_id", -1))
		if (
			str(candidate.get("effective_kind", "")) in ["trees", "hill_cliff", "river_lake"]
			and main.city_grid[candidate_id] == ""
			and main._is_tile_inside_hud_safe_area(candidate_id)
		):
			terrain_tile = candidate_id
			break
	_check(terrain_tile >= 0, "no buildable-grid plot overlaps modeled backdrop scenery")
	var terrain_before: Dictionary = main.vertical_slice.terrain_state_for_tile(terrain_tile)
	var other_non_flat_tile := -1
	for other_state_variant: Variant in main.vertical_slice.terrain_map.all_tile_states():
		var other_state: Dictionary = other_state_variant
		var other_tile_id := int(other_state.get("tile_id", -1))
		if other_tile_id != terrain_tile and not bool(other_state.get("walkable", true)):
			other_non_flat_tile = other_tile_id
			break
	_check(other_non_flat_tile >= 0, "square terrain fixture lacks an independent non-flat control tile")
	main.debug_sync_npc_navigation_obstacles()
	var terrain_center: Vector2 = main._iso_tile_center(terrain_tile)
	var other_terrain_center: Vector2 = main._iso_tile_center(other_non_flat_tile)
	var npc_navigation = main.get_npc_navigation_grid()
	_check(not npc_navigation.is_position_walkable(terrain_center), "non-flat square center is walkable before earthworks")
	_check(not npc_navigation.is_position_walkable(other_terrain_center), "independent non-flat square center is unexpectedly walkable")
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
	var blocked_start: Dictionary = main.vertical_slice.start_approved_building("住宅", terrain_tile, 5)
	_check(str(blocked_start.get("error", "")) == "terrain_not_flat", "core construction accepted non-flat terrain")
	main.placement_mode_active = true
	main.placement_building_name = "住宅"
	main._on_grid_pressed(terrain_tile)
	_check(main._pending_terrain_tile == terrain_tile, "placement flow did not select the blocked terrain tile")
	_check(main.placement_level_button.visible and not main.placement_level_button.disabled, "flatten action is not exposed for affordable non-flat terrain")
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
	_check(not main.vertical_slice.terrain_map.is_buildable(terrain_tile), "terrain flattened immediately instead of waiting for completion")
	_check(not main.vertical_slice.terrain_map.is_walkable(terrain_tile), "terrain became walkable before earthworks completed")
	_check(main.vertical_slice.construction.available_workers() == workers_before - int(quote.get("worker_count", 0)), "terrain job did not reserve its quoted workers")
	_check(main.vertical_slice.treasury_balance() == funds_before - int(quote.get("total_cost", 0)), "terrain start did not deduct exactly the prepaid quote")
	_check(main.labels["funds"].text == main._format_currency(main.vertical_slice.treasury_balance()), "terrain start did not refresh the visible treasury balance in the same frame")
	main.debug_sync_npc_navigation_obstacles()
	_check(main.npc_map_controller._blocked_tiles.has(terrain_tile), "active terrain worksite stopped blocking the live NPC controller")
	var blocked_during_flatten: Dictionary = main.vertical_slice.start_approved_building("住宅", terrain_tile, 5)
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
	_check(main.vertical_slice.terrain_map.is_buildable(terrain_tile), "final construction day did not make terrain buildable")
	_check(main.vertical_slice.terrain_map.is_walkable(terrain_tile), "final construction day did not make terrain walkable")
	_check(main.vertical_slice.construction.available_workers() == workers_before, "completed terrain job did not release its workers")
	_check(main.vertical_slice.treasury_balance() == funds_before - int(quote.get("total_cost", 0)), "terrain progression charged the prepaid quote more than once")
	main.debug_sync_npc_navigation_obstacles()
	_check(not main.npc_map_controller._blocked_tiles.has(terrain_tile), "completed terrain remained blocked in the live NPC controller")
	_check(npc_navigation.is_position_walkable(terrain_center), "flattened square center remains unwalkable after live synchronization")
	_check(not npc_navigation.is_position_walkable(other_terrain_center), "flattening one square center opened another non-flat tile")
	var post_flat_start: Dictionary = main.vertical_slice.start_approved_building("住宅", terrain_tile, 5)
	_check(bool(post_flat_start.get("ok", false)) or str(post_flat_start.get("error", "")) != "terrain_not_flat", "flattened tile did not advance to the normal blueprint/construction pipeline")

	var save_path := "user://goal_2026_08_01/terrain_round_trip.json"
	main.vertical_slice.set_player_shell_state(main._capture_player_shell_state())
	_check(main.vertical_slice.save_game(save_path) == OK, "terrain integration save failed")
	var restored = CoordinatorScript.new(99, 10)
	_check(restored.load_game(save_path), "terrain integration save could not be loaded")
	_check(restored.terrain_map.is_flattened(terrain_tile) and restored.terrain_map.is_buildable(terrain_tile), "flattened terrain did not survive save/load")

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
