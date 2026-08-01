extends SceneTree

const OUTPUT_PATH := "res://artifacts/screenshots/ui-tests/npc-live-navigation-2880x1800.png"
const TEST_SAVE_PATH := "user://mayor_simulator/tests/npc_live_navigation_capture.json"
const FULLSCREEN_SETTLE_LIMIT := 120
const LIVE_MOTION_FRAMES := 360


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	if not await _enter_stable_fullscreen():
		quit(1)
		return
	var scene := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.start_save_path = TEST_SAVE_PATH
	scene.start_screen.animation_duration = 0.04
	scene.start_screen.new_game_button.emit_signal("pressed")
	for _frame in range(180):
		await process_frame
		if not scene.start_screen.is_loading():
			break
	if scene.start_screen.visible:
		push_error("NPC live capture could not enter the map")
		quit(1)
		return

	for _frame in LIVE_MOTION_FRAMES:
		await process_frame

	if scene.get_visible_npc_count() != 24 or scene.get_visible_npc_actors().size() != 24:
		push_error("NPC live capture must preserve all 24 visible proxies")
		quit(1)
		return
	var navigation = scene.get_npc_navigation_grid()
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for npc_index in scene.get_visible_npc_count():
		var snapshot: Dictionary = scene.get_npc_acceptance_snapshot(npc_index)
		if not bool(snapshot.get("visible", false)):
			push_error("NPC %d disappeared before live capture" % npc_index)
			quit(1)
			return
		var feet := Vector2(snapshot.get("feet_position", Vector2.ZERO))
		if navigation == null or not navigation.is_position_walkable(feet):
			push_error("NPC %d entered blocked terrain before live capture: %s" % [npc_index, feet])
			quit(1)
			return
		minimum.x = minf(minimum.x, feet.x)
		minimum.y = minf(minimum.y, feet.y)
		maximum.x = maxf(maximum.x, feet.x)
		maximum.y = maxf(maximum.y, feet.y)
	var spread := maximum - minimum
	if spread.x < 760.0 or spread.y < 300.0:
		push_error("NPC local life circles collapsed into a crowd: spread=%s" % spread)
		quit(1)
		return

	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != DisplayServer.window_get_size():
		push_error("NPC live capture has no valid fullscreen image")
		quit(1)
		return
	var absolute_path := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var save_error := image.save_png(absolute_path)
	if save_error != OK:
		push_error("NPC live capture save failed: %s" % error_string(save_error))
		quit(1)
		return
	print("NPC live navigation capture saved. Proxies=24 Frames=%d Spread=%s Path=%s" % [
		LIVE_MOTION_FRAMES,
		spread,
		OUTPUT_PATH,
	])
	quit(0)


func _enter_stable_fullscreen() -> bool:
	if DisplayServer.get_name().to_lower() == "headless":
		push_error("NPC live navigation capture requires a visible display driver")
		return false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	var previous_size := Vector2i.ZERO
	var stable_frames := 0
	for _frame in FULLSCREEN_SETTLE_LIMIT:
		await process_frame
		var current_size := DisplayServer.window_get_size()
		var mode := DisplayServer.window_get_mode()
		var fullscreen := mode in [
			DisplayServer.WINDOW_MODE_FULLSCREEN,
			DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
		]
		if fullscreen and current_size == previous_size and current_size.x > 0 and current_size.y > 0:
			stable_frames += 1
		else:
			stable_frames = 0
		previous_size = current_size
		if stable_frames >= 3:
			return true
	return false
