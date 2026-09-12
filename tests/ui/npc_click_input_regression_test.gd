extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const TEST_SAVE_PATH := "res://tests/.npc_click_input_regression.json"

var _failed := false
var _grid_press_count := 0
var _npc_press_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_save()
	root.content_scale_size = Vector2i(1920, 1080)
	root.size = Vector2i(1920, 1080)
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
	_check(main._game_started and not main.start_screen.visible, "new game did not reach the clickable map")
	main.tutorial_overlay.close_as_completed(false)
	await process_frame
	# This test owns raw map pointer routing, not the mandatory onboarding layer.
	# Put that independent product flow into its validated legacy-complete state so
	# its arrow surface cannot intercept the synthetic viewport events below.
	main.onboarding_progress.restore_from_shell_state({"schema_version": 8, "tutorial_completed": true})
	main.call("_refresh_onboarding_guide")
	main.call("_sync_map_interaction_for_ui")
	await process_frame

	var npc_index := -1
	for index: int in range(main.get_visible_npc_count()):
		if str(main.get_visible_npc_snapshot(index).get("type", "")) == "商人":
			npc_index = index
			break
	_check(npc_index >= 0, "no merchant NPC was available for the click regression")
	if npc_index < 0:
		await _finish(main)
		return

	var actor := main.get_visible_npc_actor(npc_index) as Button
	actor.pressed.connect(Callable(self, "_on_npc_pressed_observed"))
	for tile_variant in main.grid_buttons:
		var tile := tile_variant as Button
		if tile != null:
			tile.pressed.connect(Callable(self, "_on_grid_pressed_observed"))
	main.dismiss_npc_dialogue()
	_check(not bool(main.get_npc_dialogue_snapshot().get("visible", false)), "dialogue fixture must begin hidden")

	var actor_center := actor.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = actor_center
	motion.global_position = actor_center
	motion.relative = Vector2.ZERO
	root.push_input(motion, true)
	await process_frame
	await process_frame
	_check(actor.is_hovered(), "viewport-routed mouse motion did not hover the merchant actor")
	var logical_position_before: Vector2 = main.get_visible_npc_snapshot(npc_index).get("pos", Vector2.ZERO)
	await process_frame
	await process_frame
	var logical_position_after: Vector2 = main.get_visible_npc_snapshot(npc_index).get("pos", Vector2.ZERO)
	_check(logical_position_before.distance_to(logical_position_after) < 0.01, "hovered merchant kept moving between pointer down and up")

	actor_center = actor.get_global_rect().get_center()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.pressed = true
	down.position = actor_center
	down.global_position = actor_center
	root.push_input(down, true)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.button_mask = 0
	up.pressed = false
	up.position = actor_center
	up.global_position = actor_center
	root.push_input(up, true)
	await process_frame
	await process_frame

	_check(_npc_press_count == 1, "viewport-routed merchant click did not emit exactly one Button press")
	_check(_grid_press_count == 0, "merchant click passed through to an isometric tile button")
	var dialogue_snapshot: Dictionary = main.get_npc_dialogue_snapshot()
	_check(bool(dialogue_snapshot.get("visible", false)), "merchant click did not reveal npc dialogue")
	_check(not str(dialogue_snapshot.get("body_text", "")).strip_edges().is_empty(), "merchant dialogue is visible but empty")
	_check(str(main.vertical_slice.selected_npc_id) == str(main.get_visible_npc_snapshot(npc_index).get("record_id", "")), "merchant click did not select the canonical NPC record")
	_check(float(dialogue_snapshot.get("remaining_seconds", 0.0)) > 0.0, "merchant click did not start the dialogue visibility timer")
	_check(float(actor.call("interaction_amount")) > 0.0, "merchant click did not start the actor's visual response")
	_check(str(actor.call("visual_expression")) == "happy", "merchant click did not produce a temporary happy expression")
	main.dismiss_npc_dialogue()
	await process_frame
	await _verify_transport_planning_input_isolation(main, npc_index)
	await _finish(main)


func _verify_transport_planning_input_isolation(main, npc_index: int) -> void:
	var selected_npc_before := str(main.vertical_slice.selected_npc_id)
	var authority_before := _authority_snapshot(main)
	var save_before := _save_bytes()
	main.call("_on_transport_infrastructure_requested", "road", "build")
	await _settle(2)
	_check(main.map_action_mode == "transport_infrastructure", "road planning did not enter map mode")
	var actor := main.get_visible_npc_actor(npc_index) as Button
	_check(actor != null, "merchant actor disappeared when transport planning began")
	if actor == null:
		return
	_check(actor.mouse_filter == Control.MOUSE_FILTER_IGNORE, "transport planning did not release NPC pointer capture")
	_check(actor.tooltip_text.is_empty(), "transport planning left an NPC tooltip enabled")

	var npc_presses_before := _npc_press_count
	var actor_center := actor.get_global_rect().get_center()
	_push_mouse_motion(actor_center)
	await _settle(2)
	_check(not actor.is_hovered(), "transport planning still allowed NPC hover")
	await _click_at(actor_center)
	_check(_npc_press_count == npc_presses_before, "transport planning allowed an NPC press")
	_check(not bool(main.get_npc_dialogue_snapshot().get("visible", false)), "transport planning opened NPC dialogue")
	_check(str(main.vertical_slice.selected_npc_id) == selected_npc_before, "transport planning changed the selected NPC")
	_check(main.municipal_overlay == null or not main.municipal_overlay.is_open(), "NPC click opened a municipal route during transport planning")
	main.call("_open_selected_npc_request")
	_check(main.municipal_overlay == null or not main.municipal_overlay.is_open(), "stale NPC action reached public affairs during transport planning")

	var target_tile_index := _first_quoteable_road_tile(main)
	_check(target_tile_index >= 0, "no quoteable road tile was available during NPC isolation")
	if target_tile_index >= 0:
		var target_tile := main.grid_buttons[target_tile_index] as Button
		_check(target_tile.mouse_filter == Control.MOUSE_FILTER_STOP, "transport planning disabled tile interaction with NPC input")
		var grid_presses_before := _grid_press_count
		await _click_at(target_tile.get_global_rect().get_center())
		_check(_grid_press_count > grid_presses_before, "transport planning tile did not receive a viewport click")
		_check(not main.transport_plan_tiles.is_empty(), "transport planning tile click did not create a local route intent")

	main.refresh_visible_npc_proxies()
	await _settle(2)
	actor = main.get_visible_npc_actor(npc_index) as Button
	_check(actor.mouse_filter == Control.MOUSE_FILTER_IGNORE and actor.tooltip_text.is_empty(), "NPC roster refresh broke planning input isolation")

	main.call("_rebuild_ui")
	await _settle(5)
	actor = main.get_visible_npc_actor(npc_index) as Button
	_check(actor != null and actor.mouse_filter == Control.MOUSE_FILTER_IGNORE, "UI rebuild restored NPC clicks during planning")
	_check(actor != null and actor.tooltip_text.is_empty(), "UI rebuild restored NPC tooltip during planning")
	_check((main.grid_buttons[target_tile_index] as Button).mouse_filter == Control.MOUSE_FILTER_STOP, "UI rebuild disabled planning tiles")

	main.settings_overlay.open()
	await _settle(2)
	_check(actor.mouse_filter == Control.MOUSE_FILTER_IGNORE, "settings modal restored NPC input during planning")
	_check((main.grid_buttons[target_tile_index] as Button).mouse_filter == Control.MOUSE_FILTER_IGNORE, "settings modal did not block planning tiles")
	main.settings_overlay.close()
	await _settle(2)
	_check(actor.mouse_filter == Control.MOUSE_FILTER_IGNORE, "closing settings restored NPC input during planning")
	_check((main.grid_buttons[target_tile_index] as Button).mouse_filter == Control.MOUSE_FILTER_STOP, "closing settings did not restore planning tiles")

	main.call("_cancel_transport_map_action", false)
	await _settle(2)
	_check(main.map_action_mode == "inspect" and main.transport_plan_tiles.is_empty(), "cancelling planning did not clear its local input intent")
	_check(actor.mouse_filter == Control.MOUSE_FILTER_STOP, "cancelling planning did not restore NPC clicks")
	_check(not actor.tooltip_text.is_empty(), "cancelling planning did not restore NPC tooltip")
	_check(_authority_snapshot(main) == authority_before, "planning input isolation changed authoritative economy, construction, transport, session, autosave, or shell state")
	_check(_save_bytes() == save_before, "planning input isolation modified the save file")

	actor.pressed.connect(Callable(self, "_on_npc_pressed_observed"))
	npc_presses_before = _npc_press_count
	await _click_at(actor.get_global_rect().get_center())
	_check(_npc_press_count == npc_presses_before + 1, "NPC click did not recover after planning cancellation")
	_check(bool(main.get_npc_dialogue_snapshot().get("visible", false)), "NPC dialogue did not recover after planning cancellation")


func _authority_snapshot(main) -> Dictionary:
	return {
		"funds": int(main.funds),
		"construction": main.vertical_slice.construction.to_dict(),
		"transport": main.vertical_slice.transport.to_dict(),
		"planning_session": main.call("_transport_session_snapshot"),
		"autosave_count": int(main._autosave_count),
		"last_autosave_reason": str(main._last_autosave_reason),
		"player_shell_state": main.vertical_slice.get_player_shell_state(),
	}


func _save_bytes() -> PackedByteArray:
	var absolute_path := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	return FileAccess.get_file_as_bytes(absolute_path) if FileAccess.file_exists(absolute_path) else PackedByteArray()


func _first_quoteable_road_tile(main) -> int:
	for tile_index in main.grid_buttons.size():
		if not bool(main.call("_is_tile_inside_hud_safe_area", tile_index)):
			continue
		var quote: Dictionary = main.vertical_slice.transport_project_quote(
			"road", "build", [tile_index], 5, main.city_grid
		)
		if bool(quote.get("ok", false)):
			return tile_index
	return -1


func _push_mouse_motion(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	motion.relative = Vector2.ZERO
	root.push_input(motion, true)


func _click_at(position: Vector2) -> void:
	_push_mouse_motion(position)
	await process_frame
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
	up.button_mask = 0
	up.pressed = false
	up.position = position
	up.global_position = position
	root.push_input(up, true)
	await _settle(2)


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame


func _on_grid_pressed_observed() -> void:
	_grid_press_count += 1


func _on_npc_pressed_observed() -> void:
	_npc_press_count += 1


func _finish(main) -> void:
	_cleanup_save()
	var exit_code := 1 if _failed else 0
	if not _failed:
		print("NPC viewport InputEvent click regression passed. NPCPresses=%d TilePresses=%d" % [_npc_press_count, _grid_press_count])
	await TestCleanup.finish(self, [main], exit_code)


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
	push_error("NPC click regression failed: %s" % message)
