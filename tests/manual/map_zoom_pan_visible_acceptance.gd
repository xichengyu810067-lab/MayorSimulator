extends SceneTree

const OUTPUT_ARGUMENT_PREFIX := "--map-zoom-pan-output-dir="
const RESULT_FILENAME := "map-zoom-pan-result.json"
const OUTPUTS := {
	"before": "native-map-before.png",
	"zoomed": "native-map-zoomed.png",
	"panned": "native-map-panned.png",
}

var _output_directory := ""
var _records: Array[Dictionary] = []
var _hashes: Dictionary = {}
var _failed := false
var _tile_press_count := 0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(OUTPUT_ARGUMENT_PREFIX):
			_output_directory = argument.trim_prefix(OUTPUT_ARGUMENT_PREFIX)
	if _output_directory.is_empty() or not DirAccess.dir_exists_absolute(_output_directory):
		push_error("Map zoom/pan acceptance needs an existing output directory argument.")
		quit(1)
		return
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name().to_lower() == "headless":
		_fail("Native map zoom/pan acceptance cannot run with the headless display driver.")
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	await _settle(18)
	var mode := DisplayServer.window_get_mode()
	if mode != DisplayServer.WINDOW_MODE_FULLSCREEN and mode != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		_fail("Native window did not enter fullscreen mode.")
		return
	if root.get_texture().get_width() <= 0 or root.get_texture().get_height() <= 0:
		_fail("Native root window has no capture texture.")
		return
	var packed := load("res://scenes/Main.tscn") as PackedScene
	if packed == null:
		_fail("Main.tscn could not be loaded.")
		return
	var main = packed.instantiate()
	main.start_save_path = "user://mayor_simulator/tests/native_map_zoom_pan_visible_acceptance.json"
	root.add_child(main)
	await _settle(18)
	if main.get_parent() != root:
		_fail("Main scene is not attached directly to the native root Window.")
		return
	main.start_screen.animation_duration = 0.04
	main.start_screen.new_game_button.emit_signal("pressed")
	for _frame in range(180):
		if main._game_started and not main.start_screen.visible:
			break
		await process_frame
	if not main._game_started or main.start_screen.visible:
		_fail("New game did not reach the native map.")
		return
	if main.tutorial_overlay != null and main.tutorial_overlay.is_open():
		main.tutorial_overlay.skip_button.emit_signal("pressed")
		await _settle(18)
	if main.map_viewport == null or main.map_stage == null:
		_fail("Native map viewport or stage is unavailable.")
		return
	main._layout_map_stage()
	await _settle(3)
	var target_button := _first_visible_tile_button(main)
	if target_button == null:
		_fail("No visible map tile was available for native short-click and left-drag acceptance.")
		return
	target_button.pressed.connect(_on_target_tile_pressed)

	var hud_before := _rect_record(main.status_hud)
	var zoom_before := float(main.map_zoom)
	var pan_before: Vector2 = main.map_pan_offset
	if not _capture("before", main):
		_fail("Could not capture native map-before state.")
		return

	var cursor: Vector2 = main.map_viewport.get_global_rect().get_center()
	for _step in range(20):
		if is_equal_approx(main.map_zoom, main.MAP_ZOOM_MAX):
			break
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		wheel.position = cursor
		wheel.global_position = cursor
		main._input(wheel)
		await process_frame
	if main.map_zoom <= zoom_before:
		_fail("Wheel InputEvent did not increase map zoom.")
		return
	if not _capture("zoomed", main):
		_fail("Could not capture native map-zoomed state.")
		return

	# At enlarged scale, a normal left click on a tile must stay a tile click.
	var click_position := target_button.get_global_rect().get_center()
	if not main.map_viewport.get_global_rect().has_point(click_position):
		_fail("The native short-click target moved outside the map viewport.")
		return
	root.push_input(_mouse_motion(click_position, Vector2.ZERO, 0), true)
	root.push_input(_mouse_button(MOUSE_BUTTON_LEFT, true, click_position, MOUSE_BUTTON_MASK_LEFT), true)
	await process_frame
	root.push_input(_mouse_button(MOUSE_BUTTON_LEFT, false, click_position, 0), true)
	await _settle(3)
	if _tile_press_count != 1:
		_fail("A native short left click did not preserve exactly one tile click.")
		return

	# The same pointer begins a pan only after it deliberately exceeds the
	# map's drag threshold; the captured gesture must not click through.
	_tile_press_count = 0
	var pan_start: Vector2 = target_button.get_global_rect().get_center()
	root.push_input(_mouse_motion(pan_start, Vector2.ZERO, 0), true)
	root.push_input(_mouse_button(MOUSE_BUTTON_LEFT, true, pan_start, MOUSE_BUTTON_MASK_LEFT), true)
	await process_frame
	var short_motion_position := pan_start + Vector2(3, 2)
	root.push_input(_mouse_motion(short_motion_position, Vector2(3, 2), MOUSE_BUTTON_MASK_LEFT), true)
	await process_frame
	if not main.map_pan_offset.is_equal_approx(pan_before):
		_fail("A native left move below the drag threshold changed map pan.")
		return
	var drag_position := pan_start + Vector2(160, -96)
	root.push_input(_mouse_motion(drag_position, drag_position - short_motion_position, MOUSE_BUTTON_MASK_LEFT), true)
	await _settle(3)
	var pan_after: Vector2 = main.map_pan_offset
	if pan_after.is_equal_approx(pan_before):
		_fail("Native enlarged left-drag did not change map pan offset.")
		return
	root.push_input(_mouse_button(MOUSE_BUTTON_LEFT, false, drag_position, 0), true)
	await _settle(3)
	if main._map_pan_drag_active:
		_fail("Native left-drag release left map dragging active.")
		return
	if _tile_press_count != 0:
		_fail("Native captured left-drag clicked through to its source tile.")
		return
	if not _capture("panned", main):
		_fail("Could not capture native map-panned state.")
		return
	# Right click is a direct exact reset when the camera differs from its
	# original view. It is delivered through the root so GUI dispatch is covered.
	root.push_input(_mouse_button(MOUSE_BUTTON_RIGHT, true, main.map_viewport.get_global_rect().get_center(), MOUSE_BUTTON_MASK_RIGHT), true)
	await _settle(3)
	if not is_equal_approx(main.map_zoom, 1.0) or not main.map_pan_offset.is_equal_approx(Vector2.ZERO):
		_fail("Native right click did not restore exact 100% zoom and original pan.")
		return
	var hud_after := _rect_record(main.status_hud)
	if not _rect_matches(hud_before, hud_after):
		_fail("HUD moved with map_stage during zoom/pan.")
		return
	if _records.size() != OUTPUTS.size() or _hashes.size() != OUTPUTS.size():
		_fail("Native map states are missing or visually identical by SHA-256.")
		return

	var result := {
		"schema_version": 1,
		"suite": "mayor-simulator-native-map-zoom-pan-visible-acceptance",
		"status": "PASS",
		"capture_surface_kind": "native_fullscreen_root",
		"scene_parent": "root_window",
		"scripted_input": "InputEventMouseButton wheel + root-dispatched MOUSE_BUTTON_LEFT short-click/threshold drag/release + MOUSE_BUTTON_RIGHT exact reset; not physical mouse hardware",
		"window_size": _vector2i_record(DisplayServer.window_get_size()),
		"root_texture_size": _vector2i_record(Vector2i(root.get_texture().get_width(), root.get_texture().get_height())),
		"logical_size": _vector2_record(root.get_visible_rect().size),
		"zoom": {"before": zoom_before, "zoomed": main.MAP_ZOOM_MAX, "after_right_reset": float(main.map_zoom)},
		"pan_offset": {"before": _vector2_record(pan_before), "after_left_drag": _vector2_record(pan_after), "after_right_reset": _vector2_record(main.map_pan_offset)},
		"short_click_tile_presses": 1,
		"drag_source_tile_presses": _tile_press_count,
		"dragging_after_release": main._map_pan_drag_active,
		"hud": {"before": hud_before, "after": hud_after, "unchanged": true},
		"map_stage": _transform_record(main.map_stage),
		"layers": _layer_records(main),
		"captures": _records,
	}
	var result_path := _output_directory.path_join(RESULT_FILENAME)
	var result_file := FileAccess.open(result_path, FileAccess.WRITE)
	if result_file == null:
		_fail("Could not write native map zoom/pan result.")
		return
	result_file.store_string(JSON.stringify(result, "\t"))
	result_file.close()
	print("NATIVE_MAP_ZOOM_PAN_VISIBLE_ACCEPTANCE_PASSED states=3 zoom=%.2f->%.2f pan=%s->%s" % [zoom_before, main.map_zoom, pan_before, pan_after])
	main.queue_free()
	await process_frame
	quit(0)


func _capture(state: String, main) -> bool:
	var filename := str(OUTPUTS.get(state, ""))
	if filename.is_empty() or _hashes.has(state):
		return false
	var image := root.get_texture().get_image()
	var image_size := image.get_size()
	if image_size.x <= 0 or image_size.y <= 0:
		return false
	var path := _output_directory.path_join(filename)
	if image.save_png(path) != OK:
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var bytes := file.get_length()
	file.close()
	var sha256 := FileAccess.get_sha256(path).to_lower()
	if bytes <= 0 or sha256.length() != 64 or _hashes.has(sha256):
		return false
	_hashes[sha256] = state
	_records.append({
		"state": state,
		"filename": filename,
		"width": image_size.x,
		"height": image_size.y,
		"bytes": bytes,
		"sha256": sha256,
		"map_stage": _transform_record(main.map_stage),
	})
	return true


func _first_visible_tile_button(main) -> Button:
	var viewport_rect: Rect2 = main.map_viewport.get_global_rect()
	for candidate in main.grid_buttons:
		var button := candidate as Button
		if button != null and button.visible and viewport_rect.has_point(button.get_global_rect().get_center()):
			return button
	return null


func _mouse_button(button_index: int, pressed: bool, position: Vector2, button_mask: int) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.button_mask = button_mask
	event.pressed = pressed
	event.position = position
	event.global_position = position
	return event


func _mouse_motion(position: Vector2, relative: Vector2, button_mask: int) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = relative
	event.button_mask = button_mask
	return event


func _on_target_tile_pressed() -> void:
	_tile_press_count += 1


func _layer_records(main) -> Dictionary:
	var result := {}
	for layer_name in ["city_backdrop", "tile_layer", "transport_network_layer", "transport_vehicle_controller", "npc_layer"]:
		var layer = main.get(layer_name) as Control
		result[layer_name] = {"availability": "available", "transform": _transform_record(layer)} if layer != null else {"availability": "unavailable"}
	result["building_actor"] = _first_control_child_record(main.tile_layer as Control)
	result["vehicle_actor"] = _first_control_child_record(main.transport_vehicle_controller as Control)
	result["npc_actor"] = _first_control_child_record(main.npc_layer as Control)
	return result


func _first_control_child_record(parent: Control) -> Dictionary:
	if parent == null:
		return {"availability": "unavailable"}
	for child in parent.get_children():
		var control := child as Control
		if control != null:
			return {"availability": "available", "transform": _transform_record(control)}
	return {"availability": "unavailable"}


func _transform_record(control: Control) -> Dictionary:
	var global_transform := control.get_global_transform_with_canvas()
	var stage := control.get_parent() as Control
	var relative_transform := stage.get_global_transform_with_canvas().affine_inverse() * global_transform if stage != null else Transform2D.IDENTITY
	return {
		"global": _transform_values(global_transform),
		"relative_to_parent": _transform_values(relative_transform),
		"global_rect": _rect_record(control),
	}


func _transform_values(transform: Transform2D) -> Array:
	return [transform.x.x, transform.x.y, transform.y.x, transform.y.y, transform.origin.x, transform.origin.y]


func _vector2_record(value: Vector2) -> Array:
	return [value.x, value.y]


func _vector2i_record(value: Vector2i) -> Array:
	return [value.x, value.y]


func _rect_record(control: Control) -> Array:
	var rect := control.get_global_rect()
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _rect_matches(first: Array, second: Array) -> bool:
	if first.size() != 4 or second.size() != 4:
		return false
	for index in range(4):
		if absf(float(first[index]) - float(second[index])) > 0.75:
			return false
	return true


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame


func _fail(message: String) -> void:
	if not _failed:
		_failed = true
		push_error("Native map zoom/pan visible acceptance failed: %s" % message)
	quit(1)
