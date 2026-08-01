extends SceneTree

const OUTPUT_PATH := "res://artifacts/screenshots/ui-tests/fullscreen-main.png"
const FULLSCREEN_SETTLE_LIMIT := 120
const TEST_SAVE_PATH := "user://mayor_simulator/tests/main_capture_autosave.json"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	if not await _enter_stable_fullscreen():
		quit(1)
		return
	var packed_scene: PackedScene = load("res://scenes/Main.tscn")
	var scene := packed_scene.instantiate()
	root.add_child(scene)
	await _settle()
	scene.start_save_path = TEST_SAVE_PATH
	scene.start_screen.animation_duration = 0.04
	scene.start_screen.new_game_button.emit_signal("pressed")
	for _frame in range(120):
		await process_frame
		if not scene.start_screen.is_loading():
			break
	var image := root.get_texture().get_image()
	if not _validate_capture(image):
		quit(1)
		return
	var error := image.save_png(OUTPUT_PATH)
	if error == OK:
		print("Fullscreen main UI capture saved: %s (%s)" % [OUTPUT_PATH, image.get_size()])
		quit(0)
	else:
		push_error("Failed to save UI capture: %d" % error)
		quit(1)


func _enter_stable_fullscreen() -> bool:
	if DisplayServer.get_name().to_lower() == "headless":
		push_error("Fullscreen visual capture cannot run with the headless display driver.")
		return false

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	var previous_size := Vector2i.ZERO
	var stable_frames := 0
	for _frame in range(FULLSCREEN_SETTLE_LIMIT):
		await process_frame
		var current_size := DisplayServer.window_get_size()
		var mode := DisplayServer.window_get_mode()
		var is_fullscreen := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if is_fullscreen and current_size == previous_size and current_size.x > 0 and current_size.y > 0:
			stable_frames += 1
		else:
			stable_frames = 0
		previous_size = current_size
		if stable_frames >= 3:
			print("Fullscreen stabilized at %s." % current_size)
			return true

	push_error("Fullscreen did not stabilize within %d frames." % FULLSCREEN_SETTLE_LIMIT)
	return false


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame


func _validate_capture(image: Image) -> bool:
	var image_size := image.get_size()
	var window_size := DisplayServer.window_get_size()
	var logical_size_value := root.get_visible_rect().size
	var logical_size := Vector2i(roundi(logical_size_value.x), roundi(logical_size_value.y))
	if abs(image_size.x - window_size.x) > 1 or abs(image_size.y - window_size.y) > 1:
		push_error("Capture size %s does not match fullscreen window backing size %s." % [image_size, window_size])
		return false
	if logical_size.x < 1280 or logical_size.y < 720:
		push_error("Fullscreen logical UI area is too small for visual acceptance: %s." % logical_size)
		return false
	print("Fullscreen validation: physical=%s logical=%s." % [image_size, logical_size])
	return true
