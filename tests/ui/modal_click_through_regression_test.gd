extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")

var _failed := false
var _grid_press_count := 0
var _cancel_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1440, 900)
	root.size = Vector2i(1440, 900)
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(3)
	main.start_screen.hide()
	main.set("_game_started", true)
	main.call("_sync_map_interaction_for_ui")
	for tile_variant in main.grid_buttons:
		var tile := tile_variant as Button
		if tile != null:
			tile.pressed.connect(_on_grid_pressed)

	main.settings_overlay.open()
	await _settle(2)
	await _click(main.settings_overlay.close_button)
	_check(not main.settings_overlay.is_open(), "settings X did not close the overlay")
	var settings_guard := main.get_node_or_null("ModalPointerGuard") as Control
	_check(settings_guard != null, "settings X did not leave a pointer guard over the map")
	_check(_grid_press_count == 0, "settings X click reached an underlying map tile")
	_check(_hovered_grid_count(main) == 0, "settings X exposed a white hover marker before pointer movement")
	await _release_guard(settings_guard)

	main.exit_confirmation.cancelled.connect(_on_exit_cancelled)
	main.exit_confirmation.open()
	await _settle(2)
	await _click(main.exit_confirmation.cancel_button)
	_check(not main.exit_confirmation.visible, "exit Cancel did not close the overlay")
	var exit_guard := main.get_node_or_null("ModalPointerGuard") as Control
	_check(exit_guard != null, "exit Cancel did not leave a pointer guard over the map")
	_check(_cancel_count == 1, "exit Cancel did not emit exactly one cancellation")
	_check(_grid_press_count == 0, "exit Cancel click reached an underlying map tile")
	_check(_hovered_grid_count(main) == 0, "exit Cancel exposed a white hover marker before pointer movement")
	await _release_guard(exit_guard)

	main.exit_confirmation.open()
	await _settle(2)
	await _click(main.exit_confirmation.close_button)
	_check(not main.exit_confirmation.visible, "exit X did not close the overlay")
	var exit_close_guard := main.get_node_or_null("ModalPointerGuard") as Control
	_check(exit_close_guard != null, "exit X did not leave a pointer guard over the map")
	_check(_cancel_count == 2, "exit X did not emit the second cancellation")
	_check(_grid_press_count == 0, "exit X click reached an underlying map tile")
	_check(_hovered_grid_count(main) == 0, "exit X exposed a white hover marker before pointer movement")
	await _release_guard(exit_close_guard)

	await _verify_npc_dialogue_planning_barrier(main, false)
	await _verify_npc_dialogue_planning_barrier(main, true)
	await _verify_npc_dialogue_keyboard_dismiss_keeps_building_placement(main)

	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Modal click-through regression passed. GridPresses=%d Cancels=%d" % [_grid_press_count, _cancel_count])
	await TestCleanup.finish(self, [main], exit_code)


func _click(button: Button) -> void:
	await _click_without_post_settle(button)
	await _settle(2)


func _click_without_post_settle(button: Button) -> void:
	var center := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	motion.relative = Vector2.ZERO
	root.push_input(motion, true)
	await process_frame

	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.pressed = true
	down.position = center
	down.global_position = center
	root.push_input(down, true)
	await process_frame

	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.button_mask = 0
	up.pressed = false
	up.position = center
	up.global_position = center
	root.push_input(up, true)


func _release_guard(guard: Control) -> void:
	if guard == null:
		return
	var release_position := guard.get_viewport().get_mouse_position() + Vector2(12, 0)
	var motion := InputEventMouseMotion.new()
	motion.position = release_position
	motion.global_position = release_position
	motion.relative = Vector2(12, 0)
	root.push_input(motion, true)
	await _settle(2)
	_check(not is_instance_valid(guard), "pointer guard did not release after real pointer movement")


func _verify_npc_dialogue_planning_barrier(main, inject_on_next_frame: bool) -> void:
	main.call("_on_transport_infrastructure_requested", "road", "build")
	await _settle(2)
	_check(main.map_action_mode == "transport_infrastructure", "road planning did not enter map mode")
	_check(main.transport_plan_tiles.is_empty(), "road planning did not start with an empty tile intent")

	var target_tile_index := _first_quoteable_road_tile(main)
	_check(target_tile_index >= 0, "could not find a quoteable road tile under the map")
	if target_tile_index < 0:
		return
	main.debug_show_npc_dialogue(0)
	await _settle(3)
	var card := main.get_npc_dialogue_card_control() as Control
	_check(card != null and card.visible, "NPC dialogue did not open above planning mode")
	if card == null or not card.visible:
		return
	var close_button := card.find_child("DismissButton", true, false) as Button
	var target_tile := main.grid_buttons[target_tile_index] as Button
	_check(close_button != null and target_tile != null, "NPC close button or target tile is unavailable")
	if close_button == null or target_tile == null:
		return
	var treasury_before := int(main.funds)
	var construction_before: Dictionary = main.vertical_slice.construction.to_dict()
	var transport_before: Dictionary = main.vertical_slice.transport.to_dict()
	var banner_before: String = str(main.placement_label.text)

	await _click_without_post_settle(close_button)
	_check(not card.visible, "NPC dialogue close action did not hide the card")
	if inject_on_next_frame:
		await process_frame
	main.call("_on_grid_pressed", target_tile_index)
	if inject_on_next_frame:
		await process_frame

	var timing := "next frame" if inject_on_next_frame else "dismiss frame"
	_check(main.transport_plan_tiles.is_empty(), "NPC close leaked a tile intent on the %s" % timing)
	_check(main.placement_label.text == banner_before, "NPC close changed the planning quote banner on the %s" % timing)
	_check(int(main.funds) == treasury_before, "NPC close deducted treasury funds on the %s" % timing)
	_check(main.vertical_slice.construction.to_dict() == construction_before, "NPC close started construction on the %s" % timing)
	_check(main.vertical_slice.transport.to_dict() == transport_before, "NPC close changed authoritative transport state on the %s" % timing)
	var guard := main.get_node_or_null("ModalPointerGuard") as Control
	_check(guard != null, "NPC close did not leave the shared pointer guard on the %s" % timing)
	await _release_guard(guard)
	main.call("_clear_transport_map_action")
	await _settle(2)


func _verify_npc_dialogue_keyboard_dismiss_keeps_building_placement(main) -> void:
	const BUILDING_NAME := "加油站"
	main.call("_enter_building_placement", BUILDING_NAME)
	await _settle(2)
	_check(main.placement_mode_active, "gas-station building placement did not start")
	_check(main.placement_banner.visible, "gas-station building placement banner did not open")
	var target_tile_index := _first_placeable_building_tile(main, BUILDING_NAME)
	_check(target_tile_index >= 0, "could not find a placeable gas-station tile for keyboard dismissal")
	if target_tile_index < 0:
		return
	var target_tile := main.grid_buttons[target_tile_index] as Button
	_check(target_tile != null, "keyboard dismissal target tile is unavailable")
	if target_tile == null:
		return
	main.debug_show_npc_dialogue(0)
	await _settle(3)
	var card := main.get_npc_dialogue_card_control() as Control
	_check(card != null and card.visible, "NPC dialogue did not open for keyboard dismissal")
	if card == null or not card.visible:
		return

	var click_position := target_tile.get_global_rect().get_center()
	_push_mouse_motion(click_position)
	await process_frame
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	_check(not card.visible, "Escape did not close the NPC dialogue")
	_check(main.get_node_or_null("ModalPointerGuard") == null, "Escape incorrectly armed a pointer guard")
	await _settle(4)
	# One physical key lifecycle must be idempotent if the same pressed event is
	# delivered again before its release reaches Main.
	root.push_input(escape, true)
	await _settle(4)
	_check(main.placement_mode_active, "Escape dismissal cancelled building placement on a later process frame")
	_check(main.placement_banner.visible, "Escape dismissal hid the building placement banner on a later process frame")
	var grid_presses_before := _grid_press_count
	await _click_at_without_motion(click_position)
	_check(_grid_press_count == grid_presses_before + 1, "Escape swallowed the unmoved pointer's next tile click")
	_check(int(main.get("_pending_construction_tile")) == target_tile_index, "the tile click after Escape did not select the real building site")
	_check(main.construction_confirmation.is_open(), "the tile click after Escape did not open the building confirmation")

	var escape_release := InputEventKey.new()
	escape_release.keycode = KEY_ESCAPE
	escape_release.pressed = false
	root.push_input(escape_release, true)
	main.call("_cancel_building_placement", false)
	await _settle(2)

	main.call("_enter_building_placement", BUILDING_NAME)
	await _settle(2)
	_check(main.placement_mode_active, "building placement did not restart after normal Escape key-up")
	var fresh_escape_after_release := InputEventKey.new()
	fresh_escape_after_release.keycode = KEY_ESCAPE
	fresh_escape_after_release.pressed = true
	root.push_input(fresh_escape_after_release, true)
	await _settle(2)
	_check(not main.placement_mode_active, "normal key-up left the next fresh Escape blocked")
	var fresh_escape_release := InputEventKey.new()
	fresh_escape_release.keycode = KEY_ESCAPE
	fresh_escape_release.pressed = false
	root.push_input(fresh_escape_release, true)

	main.call("_enter_building_placement", BUILDING_NAME)
	await _settle(2)
	main.debug_show_npc_dialogue(0)
	await _settle(3)
	card = main.get_npc_dialogue_card_control() as Control
	_check(card != null and card.visible, "NPC dialogue did not reopen for focus-loss dismissal")
	if card == null or not card.visible:
		return
	var focus_escape := InputEventKey.new()
	focus_escape.keycode = KEY_ESCAPE
	focus_escape.pressed = true
	root.push_input(focus_escape, true)
	_check(not card.visible, "Escape did not close the NPC dialogue before focus loss")
	main.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _settle(2)
	main.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await _settle(2)
	# The old key-up is intentionally absent: focus loss is the lifecycle boundary.
	var fresh_escape_after_focus := InputEventKey.new()
	fresh_escape_after_focus.keycode = KEY_ESCAPE
	fresh_escape_after_focus.pressed = true
	root.push_input(fresh_escape_after_focus, true)
	await _settle(2)
	_check(not main.placement_mode_active, "focus loss without the old key-up left the next fresh Escape blocked")
	var focus_escape_release := InputEventKey.new()
	focus_escape_release.keycode = KEY_ESCAPE
	focus_escape_release.pressed = false
	root.push_input(focus_escape_release, true)
	await _settle(2)


func _click_at_without_motion(position: Vector2) -> void:
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


func _first_placeable_building_tile(main, building_name: String) -> int:
	var workers := 5
	if main.vertical_slice_panel != null:
		workers = int(main.vertical_slice_panel.selected_worker_count())
	for tile_index in main.grid_buttons.size():
		if not bool(main.call("_is_tile_inside_hud_safe_area", tile_index)):
			continue
		var quote: Dictionary = main.vertical_slice.placement_footprint_quote(building_name, tile_index, workers)
		if bool(quote.get("ok", false)) and bool(quote.get("can_afford", false)):
			return tile_index
	return -1


func _push_mouse_motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = Vector2.ZERO
	root.push_input(event, true)


func _hovered_grid_count(main) -> int:
	var count := 0
	for tile_variant in main.grid_buttons:
		var tile := tile_variant as Button
		if tile != null and tile.is_hovered():
			count += 1
	return count


func _on_grid_pressed() -> void:
	_grid_press_count += 1


func _on_exit_cancelled() -> void:
	_cancel_count += 1


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Modal click-through regression failed: %s" % message)
