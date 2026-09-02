extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const VerticalSliceCoordinatorScript := preload("res://scripts/app/vertical_slice_coordinator.gd")

const CITY_CONTEXT := {
	"population": 300,
	"security": 70,
	"environment": 70,
	"traffic": 70,
	"education": 70,
	"healthcare": 70,
}

var _failed := false
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1440, 900)
	root.size = Vector2i(1440, 900)
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	_test_capture_argument_contract()
	_test_cross_catalog_canonical_order()
	_test_preview_groups(main)
	_test_completed_visuals_selection_and_navigation(main)
	_test_large_construction_completion_load_and_demolition(main)
	var capture_seconds := _capture_seconds_from_cli()
	var capture_path := _capture_path_from_cli()
	if capture_seconds > 0:
		if _failed:
			await TestCleanup.finish(self, [main], 1)
			return
		_prepare_capture_buildings(main)
		if _failed:
			await TestCleanup.finish(self, [main], 1)
			return
		var capture_run := _find_available_flat_run_for_main(main, 3, 7)
		if capture_run.is_empty():
			_check(false, "finite capture fixture has a legal large preview run")
			await TestCleanup.finish(self, [main], 1)
			return
		main.placement_mode_active = true
		main.placement_building_name = "體育館"
		main.call("_refresh_placement_preview", int(capture_run["anchor"]))
		_prepare_capture_surface(main)
		await process_frame
		await process_frame
		print("FOOTPRINT_CAPTURE_READY completed_medium_large=true placement_large=true seconds=%d" % capture_seconds)
		await process_frame
		await process_frame
		if not capture_path.is_empty():
			_save_capture_png(capture_path)
			if _failed:
				await TestCleanup.finish(self, [main], 1)
				return
			print("FOOTPRINT_CAPTURE_SAVED path=%s" % capture_path)
		await create_timer(float(capture_seconds)).timeout
		print("FOOTPRINT_CAPTURE_FINISHED")
		print("Building footprint visual/navigation test passed. Checks=%d" % _checks)
		await TestCleanup.finish(self, [main], 0)
		return

	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Building footprint visual/navigation test passed. Checks=%d" % _checks)
	await TestCleanup.finish(self, [main], exit_code)


func _test_capture_argument_contract() -> void:
	var no_path := _capture_path_from_arguments(PackedStringArray(), false)
	_check(no_path.is_empty(), "capture path remains disabled when the CLI option is absent")
	var expected_path := "C:/tmp/mayor-footprint-capture.png"
	var parsed_path := _capture_path_from_arguments(
		PackedStringArray(["--footprint-capture-path=%s" % expected_path]),
		false
	)
	_check(parsed_path == expected_path, "capture path parser preserves an absolute PNG path")
	var relative_path := _capture_path_from_arguments(
		PackedStringArray(["--footprint-capture-path=relative/capture.png"]),
		false
	)
	_check(relative_path.is_empty(), "capture path parser rejects relative paths")


func _prepare_capture_surface(main) -> void:
	# The test exercises Main beneath its start shell. Capture mode explicitly
	# exposes that already-populated map without starting a new game, which would
	# erase the medium/large fixture assembled above.
	main._game_started = true
	if main.start_screen != null:
		main.start_screen.hide()
	if main.tutorial_overlay != null:
		main.tutorial_overlay.hide()
	main.vertical_slice.set_time_paused(true)
	main.call("_sync_map_interaction_for_ui")
	main.call("_update_ui")


func _prepare_capture_buildings(main) -> void:
	for case: Dictionary in [
		{"name": "學校", "size": "medium", "count": 2, "minimum_row": 4},
		{"name": "體育館", "size": "large", "count": 3, "minimum_row": 6},
	]:
		var run := _find_available_flat_run_for_main(
			main,
			int(case["count"]),
			int(case["minimum_row"])
		)
		if run.is_empty():
			_check(false, "capture fixture has a visible %s run" % str(case["size"]))
			return
		var record: Dictionary = main.vertical_slice.register_existing_building(
			int(run["anchor"]),
			str(case["name"]),
			{},
			str(case["size"])
		)
		if record.is_empty():
			_check(false, "capture fixture registers visible %s building" % str(case["size"]))
			return
	main.call("_rebuild_city_from_core")
	main.call("_update_ui")
	main.debug_sync_npc_navigation_obstacles()


func _test_cross_catalog_canonical_order() -> void:
	# The --script runner installs project autoloads after compiling this test.
	# Load the tile class at runtime so its L10n global resolves exactly as it
	# does when Main builds the map.
	var city_tile_button_script = load("res://scripts/world/city_tile_button.gd")
	var cases := [
		{"name": "學校", "size": "medium", "expected": [80, 24]},
		{"name": "體育館", "size": "large", "expected": [80, 24, 25]},
	]
	for case: Dictionary in cases:
		var coordinator = VerticalSliceCoordinatorScript.new(20_260_920, 50_000_000)
		var anchor_tile_id := int(coordinator.terrain_map.tile_id_for_coordinate(Vector2i(0, 4)))
		_check(anchor_tile_id == 80, "outer-to-legacy fixture anchor keeps stable tile id 80")
		var record: Dictionary = coordinator.register_existing_building(
			anchor_tile_id,
			str(case["name"]),
			{},
			str(case["size"])
		)
		var expected: Array = case["expected"]
		_check(Array(record.get("occupied_tile_ids", [])) == expected, "%s persists canonical west-to-east ids across catalog boundary" % str(case["size"]))
		for expected_index: int in range(expected.size()):
			var tile_id := int(expected[expected_index])
			var view: Dictionary = coordinator.footprint_cell_view(tile_id)
			_check(int(view.get("footprint_index", -1)) == expected_index, "canonical view keeps west-to-east footprint index")
			_check(str(view.get("role", "")) == ("anchor" if expected_index == 0 else "secondary"), "canonical view assigns anchor/secondary without tile-id sorting")
			var cell = city_tile_button_script.new()
			cell.size = Vector2(96, 96)
			cell.set_tile({
				"index": tile_id,
				"building_name": str(case["name"]),
				"footprint_role": str(view.get("role", "")),
				"footprint_index": int(view.get("footprint_index", -1)),
				"footprint_count": int(view.get("footprint_count", 0)),
				"footprint_id": str(view.get("footprint_id", "")),
				"owner_anchor_tile_id": int(view.get("owner_anchor_tile_id", -1)),
			})
			var visual: Dictionary = cell.get_footprint_visual_snapshot()
			_check(bool(visual.get("connects_west", false)) == (expected_index > 0), "canonical visual west connector follows offset order")
			_check(bool(visual.get("connects_east", false)) == (expected_index < expected.size() - 1), "canonical visual east connector follows offset order")
			if expected.size() > 1:
				_check(cell.tooltip_text.contains("占地 %d/%d" % [expected_index + 1, expected.size()]), "canonical tooltip exposes west-to-east footprint order")
			cell.free()


func _test_preview_groups(main) -> void:
	var size_cases := {
		"公園": 1,
		"學校": 2,
		"體育館": 3,
	}
	for building_name: String in size_cases:
		var expected_count: int = int(size_cases[building_name])
		var run := _find_available_flat_run_for_main(main, expected_count)
		_check(not run.is_empty(), "%s preview fixture has a legal run" % building_name)
		if run.is_empty():
			continue
		main.placement_mode_active = true
		main.placement_building_name = building_name
		main.call("_refresh_placement_preview", int(run["anchor"]))
		var preview: Dictionary = main.get_placement_preview_snapshot()
		_check(int(preview.get("footprint_count", 0)) == expected_count, "%s preview spans exactly %d cells" % [building_name, expected_count])
		_check(bool(preview.get("can_place", false)), "%s legal preview is whole-group green" % building_name)
		var anchor_cell = main.grid_buttons[int(run["anchor"])]
		var visual_snapshot: Dictionary = anchor_cell.get_footprint_visual_snapshot()
		_check(int(visual_snapshot.get("placement_preview_count", 0)) == expected_count, "%s anchor renders the whole preview group" % building_name)
		_check(bool(visual_snapshot.get("placement_preview_valid", false)), "%s rendered preview is marked valid" % building_name)

	var terrain = main.vertical_slice.terrain_map
	var east_anchor := int(terrain.tile_id_for_coordinate(Vector2i(9, 4)))
	main.placement_mode_active = true
	main.placement_building_name = "體育館"
	main.call("_refresh_placement_preview", east_anchor)
	var edge_preview: Dictionary = main.get_placement_preview_snapshot()
	_check(int(edge_preview.get("footprint_count", 0)) == 3, "large east-edge preview retains the complete three-cell shape")
	_check(not bool(edge_preview.get("can_place", true)), "large east-edge preview is whole-group red")
	_check(str(edge_preview.get("error", "")) == "footprint_out_of_bounds", "large east-edge preview explains its invalid footprint")
	main.call("_cancel_building_placement", false)


func _test_completed_visuals_selection_and_navigation(main) -> void:
	var cases := [
		{"name": "公園", "size": "small", "count": 1},
		{"name": "學校", "size": "medium", "count": 2},
		{"name": "體育館", "size": "large", "count": 3},
	]
	var registered: Array[Dictionary] = []
	for case: Dictionary in cases:
		var run := _find_available_flat_run(main.vertical_slice, int(case["count"]))
		_check(not run.is_empty(), "%s completed fixture has a legal run" % str(case["name"]))
		if run.is_empty():
			continue
		var record: Dictionary = main.vertical_slice.register_existing_building(
			int(run["anchor"]),
			str(case["name"]),
			{},
			str(case["size"])
		)
		_check(not record.is_empty(), "%s completed fixture registers" % str(case["name"]))
		if not record.is_empty():
			registered.append(record)

	main.call("_rebuild_city_from_core")
	main.call("_update_ui")
	main.debug_sync_npc_navigation_obstacles()
	for record: Dictionary in registered:
		var occupied: Array = record.get("occupied_tile_ids", [])
		var anchor := int(record.get("anchor_tile_id", -1))
		var expected_count := int({"small": 1, "medium": 2, "large": 3}.get(str(record.get("blueprint", {}).get("size_tier", "")), 0))
		_check(occupied.size() == expected_count, "completed record keeps its exact occupied list")
		for occupied_index: int in range(occupied.size()):
			var tile_id := int(occupied[occupied_index])
			var view: Dictionary = main.vertical_slice.footprint_cell_view(tile_id)
			var visual: Dictionary = main.grid_buttons[tile_id].get_footprint_visual_snapshot()
			_check(int(view.get("owner_anchor_tile_id", -1)) == anchor, "completed occupied cell shares its owner anchor")
			_check(int(visual.get("footprint_count", 0)) == occupied.size(), "completed visual exposes the full footprint count")
			_check(str(visual.get("role", "")) == ("anchor" if occupied_index == 0 else "secondary"), "completed visual assigns an explicit footprint role")
			_check(bool(visual.get("draws_primary_body", false)) == (occupied_index == 0), "completed footprint draws one anchor body")
			_check(not main.get_npc_navigation_grid().is_position_walkable(main.call("_iso_tile_center", tile_id)), "every completed occupied center blocks NPC navigation")
		if occupied.size() > 1:
			_check(main.city_grid[int(occupied[0])] != "", "multi-cell economic identity remains on the anchor")
			for secondary_variant: Variant in occupied.slice(1):
				_check(main.city_grid[int(secondary_variant)] == "", "secondary visual does not duplicate city_grid economic identity")

	var large_record: Dictionary = registered.back()
	var large_tiles: Array = large_record.get("occupied_tile_ids", [])
	var jobs_before_preview: int = main.vertical_slice.construction.active_jobs().size()
	var funds_before_preview: int = main.vertical_slice.treasury_balance()
	main.placement_mode_active = true
	main.placement_building_name = "體育館"
	main.call("_refresh_placement_preview", int(large_tiles[0]))
	var collision_preview: Dictionary = main.get_placement_preview_snapshot()
	_check(int(collision_preview.get("footprint_count", 0)) == 3, "building conflict keeps the complete large preview shape")
	_check(not bool(collision_preview.get("can_place", true)), "one occupied cell makes the whole preview red")
	_check(main.vertical_slice.construction.active_jobs().size() == jobs_before_preview, "invalid preview creates no partial job")
	_check(main.vertical_slice.treasury_balance() == funds_before_preview, "invalid preview deducts no funds")
	main.call("_cancel_building_placement", false)
	main.call("_on_grid_pressed", int(large_tiles[2]))
	_check(main.selected_cell_index == int(large_record.get("anchor_tile_id", -1)), "clicking a completed secondary cell normalizes selection to the anchor")
	_check(main.building_context_panel != null and main.building_context_panel.visible, "secondary click opens the anchor building context")

	# The real save-loaded event hook must rebuild anchor-only identity while the
	# footprint view immediately restores every secondary visual and blocker.
	for cell in main.grid_buttons:
		cell.set_tile({"index": int(cell.tile_index)})
	main.get_npc_navigation_grid().clear_dynamic_blockers()
	var load_events: Array[Dictionary] = [{"type": "save_loaded", "payload": {}}]
	main.call("_consume_vertical_events", load_events)
	main.call("_update_ui")
	for tile_variant: Variant in large_tiles:
		var tile_id := int(tile_variant)
		_check(int(main.grid_buttons[tile_id].get_footprint_visual_snapshot().get("owner_anchor_tile_id", -1)) == int(large_tiles[0]), "save-loaded hook restores secondary visual ownership")
		_check(not main.get_npc_navigation_grid().is_position_walkable(main.call("_iso_tile_center", tile_id)), "save-loaded hook restores every footprint blocker")


func _test_large_construction_completion_load_and_demolition(main) -> void:
	var run := _find_available_flat_run(main.vertical_slice, 3)
	_check(not run.is_empty(), "large construction fixture has a legal run")
	if run.is_empty():
		return
	var start: Dictionary = main.vertical_slice.start_approved_building("體育館", int(run["anchor"]), 20)
	_check(bool(start.get("ok", false)), "large construction starts")
	if not bool(start.get("ok", false)):
		return
	var occupied: Array = start.get("occupied_tile_ids", [])
	main.call("_consume_vertical_events", main.vertical_slice.drain_ui_events())
	main.call("_update_ui")
	main.debug_sync_npc_navigation_obstacles()
	main.call("_close_building_context")
	main.grid_buttons[int(occupied[2])].emit_signal("pressed")
	_check(main.selected_cell_index == int(occupied[0]), "active building job secondary press normalizes selection to its anchor")
	_check(not main.building_context_panel.visible, "active building job press does not open a completed-building context")
	var owner_id := ""
	for occupied_index: int in range(occupied.size()):
		var tile_id := int(occupied[occupied_index])
		var view: Dictionary = main.vertical_slice.footprint_cell_view(tile_id)
		var visual: Dictionary = main.grid_buttons[tile_id].get_footprint_visual_snapshot()
		if owner_id.is_empty():
			owner_id = str(view.get("owner_id", ""))
		_check(str(view.get("kind", "")) == "construction", "active footprint cell resolves to construction authority")
		_check(str(view.get("owner_id", "")) == owner_id, "all active footprint cells share one progress identity")
		_check(bool(visual.get("draws_primary_body", false)) == (occupied_index == 0), "active footprint draws one construction body/progress")
		_check(not main.get_npc_navigation_grid().is_position_walkable(main.call("_iso_tile_center", tile_id)), "active footprint blocks every NPC center")

	var days := int(start.get("job", {}).get("projected_remaining_days", 0))
	var events: Array[Dictionary] = main.vertical_slice.advance_days(days, CITY_CONTEXT, false)
	main.call("_consume_vertical_events", events)
	main.call("_update_ui")
	for tile_variant: Variant in occupied:
		var tile_id := int(tile_variant)
		_check(str(main.vertical_slice.footprint_cell_view(tile_id).get("kind", "")) == "building", "completion fans out the building view to every occupied cell")
		_check(main.grid_buttons[tile_id].construction_job.is_empty(), "completion clears every construction visual")

	main.call("_on_grid_pressed", int(occupied[2]))
	_check(main.selected_cell_index == int(occupied[0]), "large secondary demolition target normalizes to anchor")
	_check(main.building_context_panel.visible, "completed active-job secondary opens the anchor context")
	var completed_record: Dictionary = main.vertical_slice.get_building_by_tile(int(occupied[2]))
	var completed_building_id := str(completed_record.get("building_id", ""))
	var damage: Dictionary = main.vertical_slice.durability.apply_damage(
		completed_building_id,
		20,
		"test.w3_secondary_repair",
		main.vertical_slice.game_day()
	)
	_check(bool(damage.get("ok", false)), "completed active-job fixture accepts repairable damage")
	if bool(damage.get("ok", false)):
		main.vertical_slice.call("_handle_durability_fact", damage["event"])
	main.call("_repair_selected_building")
	_check(main.selected_cell_index == int(occupied[0]), "secondary repair keeps the normalized anchor selection")
	_check(int(main.vertical_slice.get_building_by_tile(int(occupied[2])).get("durability", 0)) == 100, "secondary repair resolves the completed anchor identity")
	main.call("_start_selected_demolition")
	var demolition_job: Dictionary = main.vertical_slice.active_construction_for_tile(int(occupied[0]))
	_check(not demolition_job.is_empty(), "large demolition starts from normalized anchor")
	var demolition_days := int(demolition_job.get("projected_remaining_days", 0))
	var demolition_events: Array[Dictionary] = main.vertical_slice.advance_days(demolition_days, CITY_CONTEXT, false)
	main.call("_consume_vertical_events", demolition_events)
	main.call("_update_ui")
	main.debug_sync_npc_navigation_obstacles()
	for tile_variant: Variant in occupied:
		var tile_id := int(tile_variant)
		var visual: Dictionary = main.grid_buttons[tile_id].get_footprint_visual_snapshot()
		_check(main.vertical_slice.footprint_cell_view(tile_id).is_empty(), "demolition clears every occupied footprint lookup")
		_check(str(visual.get("role", "none")) == "none", "demolition clears every secondary visual role")
		_check(main.get_npc_navigation_grid().is_position_walkable(main.call("_iso_tile_center", tile_id)), "demolition releases every occupied NPC blocker")


func _find_available_flat_run(coordinator, length: int) -> Dictionary:
	var transport_tiles: PackedInt32Array = coordinator.transport_navigation_blocked_tile_ids()
	for row: int in range(coordinator.terrain_map.grid_size().y):
		for column: int in range(coordinator.terrain_map.grid_size().x - length + 1):
			var tiles: Array[int] = []
			var available := true
			for offset: int in range(length):
				var tile_id := int(coordinator.terrain_map.tile_id_for_coordinate(Vector2i(column + offset, row)))
				if (
					not coordinator.terrain_map.is_buildable(tile_id)
					or not coordinator.get_building_by_tile(tile_id).is_empty()
					or not coordinator.active_construction_for_tile(tile_id).is_empty()
					or transport_tiles.has(tile_id)
				):
					available = false
					break
				tiles.append(tile_id)
			if available:
				return {"anchor": tiles[0], "tiles": tiles}
	return {}


func _find_available_flat_run_for_main(main, length: int, minimum_row: int = 0) -> Dictionary:
	var coordinator = main.vertical_slice
	var transport_tiles: PackedInt32Array = coordinator.transport_navigation_blocked_tile_ids()
	for row: int in range(clampi(minimum_row, 0, coordinator.terrain_map.grid_size().y), coordinator.terrain_map.grid_size().y):
		for column: int in range(coordinator.terrain_map.grid_size().x - length + 1):
			var tiles: Array[int] = []
			var available := true
			for offset: int in range(length):
				var tile_id := int(coordinator.terrain_map.tile_id_for_coordinate(Vector2i(column + offset, row)))
				if (
					not coordinator.terrain_map.is_buildable(tile_id)
					or not coordinator.get_building_by_tile(tile_id).is_empty()
					or not coordinator.active_construction_for_tile(tile_id).is_empty()
					or transport_tiles.has(tile_id)
					or not bool(main.call("_is_tile_inside_hud_safe_area", tile_id))
				):
					available = false
					break
				tiles.append(tile_id)
			if available:
				return {"anchor": tiles[0], "tiles": tiles}
	return {}


func _capture_seconds_from_cli() -> int:
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--footprint-capture-seconds="):
			continue
		var raw_seconds := argument.trim_prefix("--footprint-capture-seconds=")
		if not raw_seconds.is_valid_int():
			_check(false, "capture seconds must be an integer")
			return -1
		return clampi(int(raw_seconds), 1, 30)
	return 0


func _capture_path_from_cli() -> String:
	return _capture_path_from_arguments(OS.get_cmdline_user_args(), true)


func _capture_path_from_arguments(arguments: PackedStringArray, report_error: bool) -> String:
	for argument: String in arguments:
		if not argument.begins_with("--footprint-capture-path="):
			continue
		var capture_path := argument.trim_prefix("--footprint-capture-path=").strip_edges()
		var valid := capture_path.is_absolute_path() and capture_path.to_lower().ends_with(".png")
		if not valid:
			if report_error:
				_check(false, "capture path must be an absolute PNG path")
			return ""
		return capture_path.simplify_path()
	return ""


func _save_capture_png(capture_path: String) -> void:
	var directory_path := capture_path.get_base_dir()
	var directory_error := DirAccess.make_dir_recursive_absolute(directory_path)
	if directory_error != OK:
		_check(false, "capture directory could not be created: %s" % error_string(directory_error))
		return
	var capture_image := root.get_texture().get_image()
	if capture_image == null or capture_image.is_empty():
		_check(false, "root viewport returned no rendered capture image")
		return
	var save_error := capture_image.save_png(capture_path)
	if save_error != OK:
		_check(false, "capture PNG could not be saved: %s" % error_string(save_error))


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Building footprint visual/navigation failed: %s" % message)
