extends SceneTree

const OUTPUT_PREFIX := "--transport-terrain-output-dir="
const HEADLESS_SMOKE_ARGUMENT := "--transport-terrain-headless-smoke"
const RESULT_FILENAME := "transport-terrain-result.json"
const CAPTURE_FILENAME := "transport-terrain-actual-main-native.png"
const SAVE_PATH := "user://mayor_simulator/tests/transport_terrain_visible_acceptance.json"
const CITY_TILE_BUTTON_PATH := "res://scripts/world/city_tile_button.gd"
const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")

var output_dir := ""
var headless_smoke := false
var failed := false
var main


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(OUTPUT_PREFIX):
			output_dir = argument.trim_prefix(OUTPUT_PREFIX)
		elif argument == HEADLESS_SMOKE_ARGUMENT:
			headless_smoke = true
	if output_dir.is_empty() or not DirAccess.dir_exists_absolute(output_dir):
		_fail("missing existing output directory")
		return
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name().to_lower() == "headless" and not headless_smoke:
		_fail("native acceptance requires a Windows display driver")
		return
	if not headless_smoke:
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
	if main.get_parent() != root:
		_fail("Main scene is not attached directly to the root Window")
		return
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
	main.vertical_slice.set_time_paused(true)
	main._layout_map_stage()

	var prepared := _prepare_authoritative_map()
	if prepared.is_empty():
		return
	await _settle(10)
	if not _validate_actual_main(prepared):
		return
	if headless_smoke:
		print("TRANSPORT_TERRAIN_ACTUAL_MAIN_HEADLESS_SMOKE_PASSED")
		await TestCleanup.finish(self, [main], 0)
		return

	main._set_hint("驗收：湖泊不可鋪路；其中一座公車站已接道路，另一座未接道路且無假接線。", false)
	await _settle(12)
	var capture := _capture_native()
	if capture.is_empty():
		return
	var result := _result(prepared, capture)
	var result_file := FileAccess.open(output_dir.path_join(RESULT_FILENAME), FileAccess.WRITE)
	if result_file == null:
		_fail("failed to open result file")
		return
	result_file.store_string(JSON.stringify(result, "\t"))
	result_file.close()
	print("TRANSPORT_TERRAIN_NATIVE_VISIBLE_ACCEPTANCE_PASSED captures=1 access_edges=1 actual_main=true")
	await TestCleanup.finish(self, [main], 0)


func _prepare_authoritative_map() -> Dictionary:
	var coordinator = main.vertical_slice
	if coordinator == null or coordinator.transport == null or coordinator.terrain_map == null:
		_fail("Main transport authority is unavailable")
		return {}
	var terrain = coordinator.terrain_map
	var layout := _find_layout(terrain)
	if layout.is_empty():
		_fail("default terrain does not provide the required legal layout")
		return {}
	var lake_tile := int(layout["lake_tile_id"])
	var road_tile := int(layout["road_tile_id"])
	var connected_station_tile := int(layout["connected_station_tile_id"])
	var orphan_station_tile := int(layout["orphan_station_tile_id"])

	var lake_quote: Dictionary = coordinator.transport_project_quote(
		"road", "build", [lake_tile], 5, main.city_grid
	)
	if bool(lake_quote.get("ok", false)) or not _issues_have(lake_quote, "terrain_not_flat"):
		_fail("unflattened lake did not reject the authoritative road quote")
		return {}

	var station_quotes: Array[Dictionary] = []
	for station_tile: int in [connected_station_tile, orphan_station_tile]:
		var quote: Dictionary = coordinator.placement_footprint_quote("公車站", station_tile, 5)
		if not bool(quote.get("ok", false)) or not bool(quote.get("can_start", true)):
			_fail("bus-stop authority quote failed for tile %d: %s" % [station_tile, quote])
			return {}
		station_quotes.append(quote.duplicate(true))
		var started: Dictionary = coordinator.start_approved_building("公車站", station_tile, 5)
		if not bool(started.get("ok", false)):
			_fail("bus-stop authority start failed for tile %d: %s" % [station_tile, started])
			return {}
		var events: Array[Dictionary] = coordinator.advance_days(
			int(started.get("job", {}).get("projected_remaining_days", 0)), {}, false
		)
		main._consume_vertical_events(events)
		main._update_tile_visual(station_tile, main.city_grid[station_tile])
		if main.city_grid[station_tile] != "公車站":
			_fail("completed bus stop did not materialize in Main city_grid at tile %d" % station_tile)
			return {}

	var road_quote: Dictionary = coordinator.transport_project_quote(
		"road", "build", [road_tile], 5, main.city_grid
	)
	if not bool(road_quote.get("ok", false)) or not bool(road_quote.get("can_start", false)):
		_fail("road authority quote failed: %s" % road_quote)
		return {}
	var road_started: Dictionary = coordinator.start_transport_project(
		"road", "build", [road_tile], 5, main.city_grid
	)
	if not bool(road_started.get("ok", false)):
		_fail("road authority start failed: %s" % road_started)
		return {}
	var road_events: Array[Dictionary] = coordinator.advance_days(
		int(road_started.get("job", {}).get("projected_remaining_days", 0)), {}, false
	)
	main._consume_vertical_events(road_events)
	main._update_transport_runtime()
	main._update_ui()
	main._layout_map_stage()

	var runtime: Dictionary = coordinator.transport_visual_snapshot(main.city_grid)
	return {
		"lake_tile_id": lake_tile,
		"road_tile_id": road_tile,
		"connected_station_tile_id": connected_station_tile,
		"orphan_station_tile_id": orphan_station_tile,
		"lake_quote": lake_quote.duplicate(true),
		"station_quotes": station_quotes,
		"road_quote": road_quote.duplicate(true),
		"runtime": runtime,
	}


func _validate_actual_main(prepared: Dictionary) -> bool:
	var coordinator = main.vertical_slice
	var lake_tile := int(prepared["lake_tile_id"])
	var road_tile := int(prepared["road_tile_id"])
	var connected_station_tile := int(prepared["connected_station_tile_id"])
	var orphan_station_tile := int(prepared["orphan_station_tile_id"])
	var runtime: Dictionary = prepared["runtime"]
	var access_edges: Array = runtime.get("station_access_edges", [])
	if access_edges.size() != 1:
		_fail("actual Main runtime did not derive exactly one station access edge")
		return false
	var edge: Dictionary = access_edges[0]
	if (
		int(edge.get("station_tile_id", -1)) != connected_station_tile
		or int(edge.get("network_tile_id", -1)) != road_tile
		or str(edge.get("kind", "")) != "road"
	):
		_fail("actual station access edge does not connect the completed road and bus stop")
		return false
	for edge_variant: Variant in access_edges:
		if int(Dictionary(edge_variant).get("station_tile_id", -1)) == orphan_station_tile:
			_fail("orphan bus stop received a fabricated station access edge")
			return false
	var lake_state: Dictionary = runtime.get("tile_states", {}).get(str(lake_tile), {})
	if Array(lake_state.get("segments", [])).has("road"):
		_fail("actual Main runtime drew a road on the authoritative lake tile")
		return false
	var layer_debug: Dictionary = main.transport_network_layer.debug_snapshot()
	if int(layer_debug.get("station_access_edge_count", 0)) != 1:
		_fail("actual Main layer did not receive the authority edge")
		return false
	if Array(layer_debug.get("station_access_segments", [])).size() != 1:
		_fail("actual Main layer fabricated or lost an access segment")
		return false
	var projection: Dictionary = main.city_backdrop.debug_terrain_projection()
	var visual_policy: Dictionary = projection.get("visual_policy", {})
	var render_order: Dictionary = main.city_backdrop.debug_render_order() if main.city_backdrop.has_method("debug_render_order") else {}
	if (
		int(projection.get("tile_count", 0)) != 100
		or str(Dictionary(projection.get("tiles", {})).get(str(lake_tile), {}).get("terrain_kind", "")) != "river_lake"
		or not bool(visual_policy.get("background_primary", false))
		or not is_zero_approx(float(visual_policy.get("flat_grass_fill_alpha", -1.0)))
		or not is_zero_approx(float(visual_policy.get("non_flat_fill_max_alpha", -1.0)))
		or bool(visual_policy.get("persistent_terrain_overlay", true))
		or str(visual_policy.get("interactive_grid_owner", "")) != "CityTileButton"
		or int(render_order.get("background_texture_z_index", -1)) != 0
		or not bool(render_order.get("background_texture_visible_in_tree", false))
		or main.city_backdrop.get_parent() != main.map_stage
		or int(render_order.get("backdrop_sibling_index", -1)) != 0
		or not bool(render_order.get("precedes_all_later_canvas_siblings", false))
	):
		_fail("actual Main backdrop does not retain the natural map as the only persistent terrain art")
		return false
	for station_tile: int in [connected_station_tile, orphan_station_tile]:
		var tile_button = main.grid_buttons[station_tile]
		var tile_script: Script = tile_button.get_script()
		if tile_script == null or tile_script.resource_path != CITY_TILE_BUTTON_PATH:
			_fail("station tile is not rendered by the actual CityTileButton")
			return false
		var visual: Dictionary = tile_button.get_visual_animation_debug_snapshot()
		if str(visual.get("building_name", "")) != "公車站":
			_fail("actual CityTileButton does not render the completed bus stop")
			return false
	if coordinator.terrain_map.is_buildable(lake_tile):
		_fail("lake unexpectedly became buildable during acceptance")
		return false
	return true


func _result(prepared: Dictionary, capture: Dictionary) -> Dictionary:
	var terrain = main.vertical_slice.terrain_map
	return {
		"schema_version": 2,
		"suite": "mayor-simulator-transport-terrain-actual-main-native-visible-acceptance",
		"status": "PASS",
		"actual_main": true,
		"scene": "res://scenes/Main.tscn",
		"scene_parent": "root_window",
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
		"display_server": DisplayServer.get_name(),
		"window_mode": DisplayServer.window_get_mode(),
		"window_size": _v2i(DisplayServer.window_get_size()),
		"authority_flow": {
			"bus_station": "placement_footprint_quote -> start_approved_building -> advance_days -> building_completed",
			"road": "transport_project_quote -> start_transport_project -> advance_days -> transport_project_completed",
			"direct_topology_writes": false,
			"custom_station_panels": false,
		},
		"terrain": {
			"projection": "SquareGridLayout",
			"tile_count": 100,
			"lake_tile_id": int(prepared["lake_tile_id"]),
			"lake_coordinate": _v2i(terrain.coordinate_for_tile_id(int(prepared["lake_tile_id"]))),
			"lake_buildable": terrain.is_buildable(int(prepared["lake_tile_id"])),
			"lake_road_quote_issue": "terrain_not_flat",
			"background_primary": true,
			"flat_grass_fill_alpha": 0.0,
			"non_flat_fill_max_alpha": 0.0,
			"persistent_terrain_overlay": false,
			"interactive_grid_owner": "CityTileButton",
		},
		"transport": {
			"road_tile_id": int(prepared["road_tile_id"]),
			"connected_station_tile_id": int(prepared["connected_station_tile_id"]),
			"orphan_station_tile_id": int(prepared["orphan_station_tile_id"]),
			"station_access_edges": Array(Dictionary(prepared["runtime"]).get("station_access_edges", [])).duplicate(true),
			"orphan_access_edge_count": 0,
		},
		"visuals": {
			"station_renderer": "CityTileButton",
			"network_renderer": "TransportNetworkLayer",
			"backdrop_renderer": "CityBackdrop",
			"backdrop_render_order": main.city_backdrop.debug_render_order(),
		},
		"captures": [capture],
	}


func _capture_native() -> Dictionary:
	var image := root.get_texture().get_image()
	if image.is_empty():
		_fail("native root capture is empty")
		return {}
	var path := output_dir.path_join(CAPTURE_FILENAME)
	if image.save_png(path) != OK:
		_fail("failed to save native actual-Main capture")
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


func _find_layout(terrain) -> Dictionary:
	var lake_tile := _first_tile_of_kind(terrain, "river_lake")
	if lake_tile < 0:
		return {}
	# Prefer the middle of the live map so the real station sprites and their
	# access edge remain visible below the HUD in the native acceptance image.
	var preferred_coordinates := [
		Vector2i(5, 5), Vector2i(4, 5), Vector2i(5, 4), Vector2i(4, 4),
		Vector2i(6, 5), Vector2i(5, 6), Vector2i(3, 5), Vector2i(6, 4),
	]
	var candidate_tiles: Array[int] = []
	for coordinate: Vector2i in preferred_coordinates:
		var preferred_tile := int(terrain.tile_id_for_coordinate(coordinate))
		if preferred_tile >= 0 and not candidate_tiles.has(preferred_tile):
			candidate_tiles.append(preferred_tile)
	for tile_id in terrain.cell_count():
		if not candidate_tiles.has(tile_id):
			candidate_tiles.append(tile_id)
	for road_tile: int in candidate_tiles:
		if not terrain.is_buildable(road_tile):
			continue
		var road_coordinate: Vector2i = terrain.coordinate_for_tile_id(road_tile)
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var station_tile := int(terrain.tile_id_for_coordinate(road_coordinate + offset))
			if station_tile < 0 or not terrain.is_buildable(station_tile):
				continue
			var orphan_tile := _orphan_buildable_tile(terrain, road_tile, station_tile)
			if orphan_tile >= 0:
				return {
					"lake_tile_id": lake_tile,
					"road_tile_id": road_tile,
					"connected_station_tile_id": station_tile,
					"orphan_station_tile_id": orphan_tile,
				}
	return {}


func _orphan_buildable_tile(terrain, road_tile: int, station_tile: int) -> int:
	var road_coordinate: Vector2i = terrain.coordinate_for_tile_id(road_tile)
	var preferred_coordinates := [
		Vector2i(3, 5), Vector2i(3, 4), Vector2i(7, 3), Vector2i(3, 6),
		Vector2i(7, 7), Vector2i(2, 5), Vector2i(6, 2),
	]
	var candidate_tiles: Array[int] = []
	for coordinate: Vector2i in preferred_coordinates:
		var preferred_tile := int(terrain.tile_id_for_coordinate(coordinate))
		if preferred_tile >= 0 and not candidate_tiles.has(preferred_tile):
			candidate_tiles.append(preferred_tile)
	for tile_id in terrain.cell_count():
		if not candidate_tiles.has(tile_id):
			candidate_tiles.append(tile_id)
	for tile_id: int in candidate_tiles:
		if tile_id == station_tile or not terrain.is_buildable(tile_id):
			continue
		var coordinate: Vector2i = terrain.coordinate_for_tile_id(tile_id)
		if abs(coordinate.x - road_coordinate.x) + abs(coordinate.y - road_coordinate.y) > 2:
			return tile_id
	return -1


func _first_tile_of_kind(terrain, kind: String) -> int:
	for tile_id in terrain.cell_count():
		if terrain.effective_kind(tile_id) == kind:
			return tile_id
	return -1


func _issues_have(result: Dictionary, expected_prefix: String) -> bool:
	for issue_variant: Variant in result.get("issues", []):
		if str(issue_variant).begins_with(expected_prefix):
			return true
	return false


func _v2i(value: Variant) -> Array:
	return [int(value.x), int(value.y)]


func _settle(frames: int) -> void:
	for _index in range(frames):
		await process_frame


func _fail(message: String) -> void:
	if failed:
		return
	failed = true
	push_error("Transport terrain actual-Main acceptance failed: %s" % message)
	quit(1)
