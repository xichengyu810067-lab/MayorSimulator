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
	main.tutorial_overlay._transition.custom_step(1.0)
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
	await _finish(main)


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
