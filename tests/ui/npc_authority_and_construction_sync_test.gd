extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1440, 900)
	root.size = Vector2i(1440, 900)
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	_check(main.vertical_slice.population.population_count() == 300, "authoritative population did not start at 300")
	_check(main.get_visible_npc_count() == 24 and main.get_visible_npc_actors().size() == 24, "initial visible proxy architecture is not 24 actors")
	await _test_authoritative_proxy_refresh(main)
	_test_immediate_construction_obstacle(main)

	var exit_code := 1 if _failed else 0
	if not _failed:
		print("NPC authority/construction sync passed. Population=300 Visible=24 ImmediateObstacle=true CollisionLifecycle=true")
	await TestCleanup.finish(self, [main], exit_code)


func _test_immediate_construction_obstacle(main) -> void:
	var submitted: Dictionary = main.vertical_slice.submit_blueprint({
		"building_name": "公園",
		"material_id": "wood",
		"floors": 1,
		"size_tier": "small",
		"roof_color": "green",
		"wall_color": "cream",
		"decor_id": "flowers",
		"workers": 20,
	})
	_check(bool(submitted.get("ok", false)), "park blueprint submission failed")
	if not bool(submitted.get("ok", false)):
		return
	var review: Dictionary = submitted.get("review", {})
	var review_events: Array[Dictionary] = main.vertical_slice.advance_days(
		int(review.get("review_days", 0)),
		main.call("_vertical_city_context"),
		false
	)
	main.call("_consume_vertical_events", review_events)
	_check(str(main.vertical_slice.blueprint_review_status("公園").get("status", "")) == "approved", "park blueprint was not approved")

	var tile_index := 12
	var before_replans: Array[int] = []
	for npc_index in main.get_visible_npc_count():
		before_replans.append(int(main.get_npc_acceptance_snapshot(npc_index).get("replan_count", 0)))
	main.placement_mode_active = true
	main.placement_building_name = "公園"
	main._pending_construction_tile = tile_index
	main._pending_construction_workers = 20
	main.call("_confirm_pending_construction", tile_index)

	_check(not main.vertical_slice.active_construction_for_tile(tile_index).is_empty(), "construction did not start")
	var navigation = main.get_npc_navigation_grid()
	var tile_center: Vector2 = main.call("_iso_tile_center", tile_index)
	var construction_blocker: Dictionary = _blocker_by_id(navigation, "construction:%d" % tile_index)
	_check(not construction_blocker.is_empty(), "construction blocker was not synchronized in the confirmation frame")
	_check(
		Vector2(construction_blocker.get("half_extents", Vector2.ZERO)).x > 0.0
		and Vector2(construction_blocker.get("half_extents", Vector2.ZERO)).y > 0.0,
		"construction collision footprint has no area"
	)
	_check(not navigation.is_position_walkable(tile_center), "construction collision footprint remained walkable")
	var all_replanned := true
	for npc_index in main.get_visible_npc_count():
		var after_count := int(main.get_npc_acceptance_snapshot(npc_index).get("replan_count", 0))
		if after_count <= before_replans[npc_index]:
			all_replanned = false
			break
	_check(all_replanned, "not every visible resident replanned after immediate construction sync")
	_check(main.vertical_slice.drain_ui_events().is_empty(), "construction_started remained queued until the next game day")

	# The same occupied footprint must transition from a construction collider to
	# a building collider, survive the real save-loaded rebuild hook, remain while
	# demolition is in progress, and disappear only after demolition completes.
	for _day in range(10):
		if main.city_grid[tile_index] == "公園":
			break
		main.call("_next_day")
	_check(main.city_grid[tile_index] == "公園", "park did not complete within the lifecycle fixture")
	_check(_blocker_by_id(navigation, "construction:%d" % tile_index).is_empty(), "completed building retained its construction collider")
	var building_blocker: Dictionary = _blocker_by_id(navigation, "building:%d" % tile_index)
	_check(not building_blocker.is_empty(), "completed building did not install a building collider")
	_check(str(building_blocker.get("source", "")) == "building", "completed collider lost its building source")
	_check(not navigation.is_position_walkable(tile_center), "completed building center became walkable")

	navigation.clear_dynamic_blockers()
	_check(navigation.is_position_walkable(tile_center), "collision lifecycle fixture could not clear the building collider")
	var load_events: Array[Dictionary] = [{"type": "save_loaded", "payload": {}}]
	main.call("_consume_vertical_events", load_events)
	_check(not _blocker_by_id(navigation, "building:%d" % tile_index).is_empty(), "save-loaded rebuild did not restore the building collider")
	_check(not navigation.is_position_walkable(tile_center), "save-loaded building center remained walkable")

	main.selected_cell_index = tile_index
	main.call("_start_selected_demolition")
	_check(str(main.vertical_slice.get_building_by_tile(tile_index).get("status", "")) == "demolition", "demolition lifecycle did not start")
	_check(not _blocker_by_id(navigation, "building:%d" % tile_index).is_empty(), "building collider disappeared before demolition completed")
	for _day in range(10):
		if main.city_grid[tile_index] == "":
			break
		main.call("_next_day")
	_check(main.city_grid[tile_index] == "", "demolition lifecycle did not release the tile")
	_check(_blocker_by_id(navigation, "building:%d" % tile_index).is_empty(), "demolished building retained a stale collider")
	_check(navigation.is_position_walkable(tile_center), "demolished building footprint did not restore walkability")


func _test_authoritative_proxy_refresh(main) -> void:
	var positions_by_id := {}
	var old_ids := PackedStringArray()
	for npc: Dictionary in main.get_visible_npc_snapshots():
		var record_id := str(npc.get("record_id", ""))
		old_ids.append(record_id)
		positions_by_id[record_id] = Vector2(npc.get("foot_position", Vector2.ZERO))

	main.vertical_slice.refresh_requests(main.call("_vertical_city_context"))
	var desired: Array[Dictionary] = main.vertical_slice.visible_npc_proxies(24)
	var desired_ids := PackedStringArray()
	for proxy: Dictionary in desired:
		desired_ids.append(str(proxy.get("npc_id", "")))
	var request_changed_membership := false
	for record_id: String in desired_ids:
		request_changed_membership = request_changed_membership or not old_ids.has(record_id)
	_check(request_changed_membership, "request fixture did not exercise a proxy membership change")
	# Exercise the real post-load hook: save_loaded rebuilds city state, then the
	# event consumer refreshes proxies after _sync_vertical_state().
	var load_events: Array[Dictionary] = [{"type": "save_loaded", "payload": {}}]
	main.call("_consume_vertical_events", load_events)
	var refreshed_ids := _visible_ids(main)
	_check(_same_id_set(refreshed_ids, desired_ids), "visible actors did not match authoritative/request-prioritized proxies")
	for npc: Dictionary in main.get_visible_npc_snapshots():
		var record_id := str(npc.get("record_id", ""))
		if positions_by_id.has(record_id):
			_check(
				Vector2(npc.get("foot_position", Vector2.ZERO)).is_equal_approx(Vector2(positions_by_id[record_id])),
				"retained authoritative resident teleported during roster refresh: %s" % record_id
			)

	# Existing buttons retain their bound slot after identity rebinding.
	if main.get_visible_npc_count() > 0:
		var expected_id := str(main.get_visible_npc_snapshot(0).get("record_id", ""))
		main.get_visible_npc_actor(0).emit_signal("pressed")
		await process_frame
		_check(int(main.get_npc_dialogue_snapshot().get("active_index", -1)) == 0, "refreshed actor button lost its slot binding")
		_check(str(main.vertical_slice.selected_npc_id) == expected_id, "refreshed actor selected a stale resident id")
		main.dismiss_npc_dialogue()

	var population_before_zero: int = int(main.vertical_slice.population.population_count())
	main.vertical_slice.adjust_population(-population_before_zero, "test.zero_population")
	main.refresh_visible_npc_proxies()
	_check(main.vertical_slice.population.population_count() == 0, "test could not reach zero population")
	_check(main.get_visible_npc_count() == 0 and main.get_visible_npc_actors().is_empty(), "zero population still rendered legacy/fake residents")

	main.vertical_slice.adjust_population(300, "test.restore_population")
	main.refresh_visible_npc_proxies()
	_check(main.vertical_slice.population.population_count() == 300, "authoritative population was not restored to 300")
	_check(main.get_visible_npc_count() == 24 and main.get_visible_npc_actors().size() == 24, "24 visible proxies were not restored")
	for npc: Dictionary in main.get_visible_npc_snapshots():
		var record_id := str(npc.get("record_id", ""))
		_check(not record_id.begins_with("legacy_"), "restored roster contains a legacy fake resident")
		_check(main.vertical_slice.population.get_record(record_id) != null, "visible actor id is absent from authoritative population: %s" % record_id)


func _visible_ids(main) -> PackedStringArray:
	var ids := PackedStringArray()
	for npc: Dictionary in main.get_visible_npc_snapshots():
		ids.append(str(npc.get("record_id", "")))
	return ids


func _same_id_set(left: PackedStringArray, right: PackedStringArray) -> bool:
	if left.size() != right.size():
		return false
	var left_sorted := Array(left)
	var right_sorted := Array(right)
	left_sorted.sort()
	right_sorted.sort()
	return left_sorted == right_sorted


func _blocker_by_id(navigation, blocker_id: String) -> Dictionary:
	for blocker_variant: Variant in navigation.get_debug_dynamic_polygons():
		var blocker: Dictionary = blocker_variant
		if str(blocker.get("id", "")) == blocker_id:
			return blocker
	return {}


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("NPC authority/construction sync failed: %s" % message)
