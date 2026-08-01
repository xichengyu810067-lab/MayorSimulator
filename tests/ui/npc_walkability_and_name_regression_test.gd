extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const TEST_SAVE_PATH := "res://tests/.npc_walkability_and_name_regression.json"
const ACTOR_SIZE := Vector2(52, 68)
const MINIMUM_FEET_SEPARATION := 26.0

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_save()
	root.content_scale_size = Vector2i(1440, 900)
	root.size = Vector2i(1440, 900)
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.start_save_path = TEST_SAVE_PATH
	main.start_screen.animation_duration = 0.04
	main.start_screen.new_game_button.emit_signal("pressed")
	for _frame in range(120):
		await process_frame
		if not main.start_screen.is_loading():
			break

	_check(main._game_started and not main.start_screen.visible, "new game did not reach the map")
	_check(main.vertical_slice.population.population_count() == 300, "the authoritative population changed")
	_check(main.get_visible_npc_count() == 24 and main.get_visible_npc_actors().size() == 24, "the 24 visible proxies were not preserved")
	_validate_route_design(main)
	_validate_visible_npcs(main, "initial")

	var initial_positions: Array[Vector2] = []
	var maximum_travel: Array[float] = []
	for npc: Dictionary in main.get_visible_npc_snapshots():
		initial_positions.append(Vector2(npc.get("pos", Vector2.ZERO)))
		maximum_travel.append(0.0)
	for frame in range(720):
		main.ambient_time += 1.0 / 30.0
		main.debug_step_npc_simulation(1.0 / 30.0)
		for index in main.get_visible_npc_count():
			var current_position := Vector2(main.get_visible_npc_snapshot(index).get("pos", Vector2.ZERO))
			maximum_travel[index] = maxf(maximum_travel[index], initial_positions[index].distance_to(current_position))
		if frame % 12 == 0:
			_validate_visible_npcs(main, "movement frame %d" % frame)
	var residents_with_visible_travel := 0
	for travel: float in maximum_travel:
		if travel >= 12.0:
			residents_with_visible_travel += 1
	_check(residents_with_visible_travel >= 16, "too few residents traversed their routes: %d" % residents_with_visible_travel)

	# A completed building must invalidate the active path and trigger a visible
	# walk-out/replan.  Residents must never teleport away or disappear.
	var obstacle_npc_index := -1
	var obstacle_tile := -1
	for index in main.get_visible_npc_count():
		var candidate_tile := int(main.get_visible_npc_snapshot(index).get("tile", -1))
		if candidate_tile >= 0:
			obstacle_npc_index = index
			obstacle_tile = candidate_tile
			break
	_check(obstacle_npc_index >= 0, "no route slot mapped to a buildable tile")
	if obstacle_npc_index >= 0:
		var original_id := str(main.get_visible_npc_snapshot(obstacle_npc_index).get("record_id", ""))
		main.city_grid[obstacle_tile] = "住宅"
		main.debug_sync_npc_navigation_obstacles()
		main.call("debug_force_npc_repath", obstacle_npc_index, true)
		for _frame in range(240):
			main.debug_step_npc_simulation(1.0 / 30.0)
		_check(main.get_visible_npc_actor(obstacle_npc_index).visible, "a resident disappeared even though reserve walking slots exist")
		_check(str(main.get_visible_npc_snapshot(obstacle_npc_index).get("record_id", "")) == original_id, "building avoidance replaced the authoritative NPC record")
		var safe_foot := Vector2(main.get_visible_npc_snapshot(obstacle_npc_index).get("foot_position", Vector2.ZERO))
		_check(main.get_npc_navigation_grid().is_position_walkable(safe_foot), "a resident did not walk out of the newly blocked tile")
		_validate_visible_npcs(main, "building obstacle relocation")
		main.city_grid[obstacle_tile] = ""
		main.debug_sync_npc_navigation_obstacles()
		main.call("debug_force_npc_repath", obstacle_npc_index, true)

	# The first Traditional-Chinese presentation must converge to a compact card;
	# a hidden status chip must not retain the NPC layer's full height.
	main.debug_show_npc_dialogue(0)
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	var dialogue_card = main.get_npc_dialogue_card_control()
	_check(dialogue_card.size.y <= 280.0, "Traditional-Chinese NPC dialogue did not converge to a compact height: %s" % dialogue_card.size)
	_check(dialogue_card.petition_status_label.size.x >= 120.0, "NPC petition status did not receive readable horizontal space: %s" % dialogue_card.petition_status_label.size)
	_check(not dialogue_card.petition_status_label.text.strip_edges().is_empty(), "NPC petition status text is empty")
	main.dismiss_npc_dialogue()

	var l10n = root.get_node_or_null("L10n")
	_check(l10n != null, "localization service is unavailable")
	if l10n != null:
		var original_locale := str(l10n.current_locale)
		l10n.set_locale("en", false)
		var huang_jianhong: String = str(main.format_npc_display_name({
			"display_name": "黃建宏",
			"family_name": "黃",
			"given_name": "建宏",
			"latin_display_name": "Huang Jianhong",
		}))
		var huang_yijun: String = str(main.format_npc_display_name({
			"display_name": "黃怡君",
			"family_name": "黃",
			"given_name": "怡君",
			"latin_display_name": "Huang Yijun",
		}))
		_check(huang_jianhong == "Huang Jianhong", "English name lost or mistranslated its family/given boundary: %s" % huang_jianhong)
		_check(huang_yijun == "Huang Yijun", "second English name lost its family/given boundary: %s" % huang_yijun)
		var formatted_resident_count := 0
		for resident_id: String in main.vertical_slice.population.sorted_npc_ids():
			var proxy: Dictionary = main.vertical_slice.population.materialize_proxy(resident_id)
			var localized_name: String = str(l10n.person_name(
				str(proxy.get("family_name", "")),
				str(proxy.get("given_name", "")),
				str(proxy.get("display_name", resident_id)),
				str(proxy.get("latin_display_name", ""))
			))
			_check(localized_name.contains(" "), "English resident name has no family/given boundary: %s" % localized_name)
			_check(not localized_name.begins_with("Yellow "), "surname 黃 was translated as a color: %s" % localized_name)
			formatted_resident_count += 1
		_check(formatted_resident_count == 300, "not all authoritative resident names were formatted")
		var view_model: Dictionary = main.vertical_slice.get_view_model(main.selected_cell_index)
		for request_variant: Variant in view_model.get("citizen_requests", []):
			var request: Dictionary = request_variant
			var request_name := str(request.get("npc_name", ""))
			_check(request_name.contains(" "), "citizen request name has no English family/given boundary: %s" % request_name)
			_check(not request_name.begins_with("Yellow "), "citizen request surname was translated as a color: %s" % request_name)

		var dialogue_fixture: Dictionary = main.get_visible_npc_snapshot(0)
		dialogue_fixture["display_name"] = "黃建宏"
		dialogue_fixture["family_name"] = "黃"
		dialogue_fixture["given_name"] = "建宏"
		dialogue_fixture["latin_display_name"] = "Huang Jianhong"
		_check(main.debug_override_visible_npc_proxy(0, dialogue_fixture), "dialogue fixture could not replace visible proxy through debug facade")
		main.debug_show_npc_dialogue(0)
		await process_frame
		await process_frame
		dialogue_card = main.get_npc_dialogue_card_control()
		_check(dialogue_card != null and dialogue_card.visible, "structured NPC dialogue card is not visible")
		_check(dialogue_card.name_label.text == "Huang Jianhong", "dialogue identity field does not preserve the localized speaker name: %s" % dialogue_card.name_label.text)
		_check(not str(main.get_npc_dialogue_snapshot().get("body_text", "")).strip_edges().is_empty(), "structured dialogue body is empty")
		var dialogue_rect: Rect2 = dialogue_card.get_global_rect()
		var status_rect: Rect2 = main.status_hud.get_global_rect()
		var map_rect: Rect2 = main.map_viewport.get_global_rect()
		_check(dialogue_rect.position.y >= status_rect.end.y + 8.0, "NPC dialogue is clipped behind the status HUD: dialogue=%s status=%s" % [dialogue_rect, status_rect])
		_check(dialogue_rect.position.x >= map_rect.position.x - 1.0, "NPC dialogue exceeds the visible map on the left: dialogue=%s map=%s" % [dialogue_rect, map_rect])
		_check(dialogue_rect.end.x <= map_rect.end.x + 1.0, "NPC dialogue exceeds the visible map on the right: dialogue=%s map=%s" % [dialogue_rect, map_rect])
		_check(dialogue_rect.end.y <= map_rect.end.y + 1.0, "NPC dialogue exceeds the visible map on the bottom: dialogue=%s map=%s" % [dialogue_rect, map_rect])
		var name_before_tree_pass: String = str(dialogue_card.name_label.text)
		var dialogue_before_tree_pass: String = str(main.get_npc_dialogue_snapshot().get("body_text", ""))
		l10n.localize_tree(main)
		_check(dialogue_card.name_label.text == name_before_tree_pass, "static localization reprocessed and corrupted the dynamic speaker name")
		_check(str(main.get_npc_dialogue_snapshot().get("body_text", "")) == dialogue_before_tree_pass, "static localization reprocessed and corrupted the dynamic dialogue")
		l10n.set_locale(original_locale, false)

	var exit_code := 1 if _failed else 0
	if not _failed:
		print(
			"NPC walkability/name regression passed. Visible=%d Population=%d Frames=720 Routes=%d Travelled12px=%d"
			% [
				main.get_visible_npc_count(),
				main.vertical_slice.population.population_count(),
				main.get_npc_route_slots_snapshot().size(),
				residents_with_visible_travel,
			]
		)
	_cleanup_save()
	await TestCleanup.finish(self, [main], exit_code)


func _validate_route_design(main) -> void:
	var routes: Array = main.get_npc_route_slots_snapshot()
	_check(routes.size() > main.get_visible_npc_count(), "no reserve NPC route remains available")
	var route_lengths := {}
	var has_horizontal := false
	var has_diagonal := false
	for route_variant: Variant in routes:
		var route: Dictionary = route_variant
		var start := Vector2(route.get("start", Vector2.ZERO))
		var finish := Vector2(route.get("end", Vector2.ZERO))
		var direction := finish - start
		route_lengths[roundi(direction.length())] = true
		has_horizontal = has_horizontal or absf(direction.y) < 0.1
		has_diagonal = has_diagonal or absf(direction.x) >= 0.1 and absf(direction.y) >= 0.1
		_check(direction.length() >= 36.0, "route remains too short for visible walking: %s" % direction.length())
	_check(route_lengths.size() >= 3, "routes do not provide at least three travel lengths")
	_check(has_horizontal and has_diagonal, "routes do not mix horizontal and diagonal travel")

	var spawn_x_values := {}
	var spawn_y_values := {}
	var speeds := {}
	var waits := {}
	var target_endpoints := {}
	for npc: Dictionary in main.get_visible_npc_snapshots():
		var position := Vector2(npc.get("pos", Vector2.ZERO))
		spawn_x_values[roundi(position.x)] = true
		spawn_y_values[roundi(position.y)] = true
		speeds[snappedf(float(npc.get("speed", 0.0)), 0.01)] = true
		waits[snappedf(float(npc.get("wait", 0.0)), 0.01)] = true
		target_endpoints[int(npc.get("target_endpoint", -1))] = true
	_check(spawn_x_values.size() >= 12 and spawn_y_values.size() >= 12, "NPCs still resemble a rigid row/column formation")
	_check(speeds.size() >= 3, "initial walking speeds are not staggered")
	_check(waits.size() >= 3, "initial wait timing is not staggered")
	_check(target_endpoints.has(0) and target_endpoints.has(1), "initial route endpoints are not staggered")


func _validate_visible_npcs(main, phase: String) -> void:
	for index in main.get_visible_npc_count():
		if not main.get_visible_npc_actor(index).visible:
			continue
		var npc: Dictionary = main.get_visible_npc_snapshot(index)
		var logical_position: Vector2 = npc.get("pos", Vector2.ZERO)
		_check(main.is_npc_position_scenery_safe(logical_position), "%s resident %d left the open-meadow route" % [phase, index])
		var tile_index := int(npc.get("tile", -1))
		_check(not main.is_npc_tile_blocked(tile_index), "%s resident %d entered an occupied building tile" % [phase, index])
		var feet_position := Vector2(npc.get("foot_position", logical_position + Vector2(ACTOR_SIZE.x * 0.5, ACTOR_SIZE.y - 3.0)))
		for other_index in range(index + 1, main.get_visible_npc_count()):
			if not main.get_visible_npc_actor(other_index).visible:
				continue
			var other_npc: Dictionary = main.get_visible_npc_snapshot(other_index)
			var other_position := Vector2(other_npc.get("pos", Vector2.ZERO))
			var other_feet := Vector2(other_npc.get("foot_position", other_position + Vector2(ACTOR_SIZE.x * 0.5, ACTOR_SIZE.y - 3.0)))
			_check(feet_position.distance_to(other_feet) >= MINIMUM_FEET_SEPARATION, "%s residents %d and %d violate personal space" % [phase, index, other_index])


func _cleanup_save() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	for suffix: String in ["", ".tmp", ".bak"]:
		var candidate := absolute_path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("NPC walkability/name regression failed: %s" % message)
