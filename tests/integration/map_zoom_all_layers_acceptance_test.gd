extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const TEST_SAVE_PATH := "user://mayor_simulator/tests/map_zoom_all_layers_acceptance.json"
const TRANSFORM_EPSILON := 0.75
const ROUND_TRIP_EPSILON := 0.02

var _failed := false
var _checks := 0
var _tile_press_count := 0
var _last_tile_pressed := -1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_save()
	root.content_scale_size = Vector2i(1920, 1080)
	root.size = Vector2i(1920, 1080)
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_check(packed != null, "Main scene can be loaded")
	if packed == null:
		await _finish([])
		return

	var main = packed.instantiate()
	root.add_child(main)
	await _settle(3)
	main.start_save_path = TEST_SAVE_PATH
	main.start_screen.set_continue_available(false)
	main.start_screen.animation_duration = 0.04
	main.start_screen.new_game_button.emit_signal("pressed")
	await _wait_for_loading(main)
	_check(main._game_started and not main.start_screen.visible, "New reaches the interactive Main map")
	if main.tutorial_overlay != null and main.tutorial_overlay.is_open():
		main.tutorial_overlay.close_as_completed(false)
		main.tutorial_overlay._transition.custom_step(1.0)
	await _settle(2)
	main.call("_sync_map_interaction_for_ui")
	main.call("_layout_map_stage")

	var terrain = main.vertical_slice.terrain_map
	var west_tile := int(terrain.tile_id_for_coordinate(Vector2i(3, 4)))
	var target_tile := int(terrain.tile_id_for_coordinate(Vector2i(4, 4)))
	var east_tile := int(terrain.tile_id_for_coordinate(Vector2i(5, 4)))
	var building_tile := int(terrain.tile_id_for_coordinate(Vector2i(5, 5)))
	for tile_id: int in [west_tile, target_tile, east_tile, building_tile]:
		_check(tile_id >= 0 and tile_id < main.CELL_COUNT, "central acceptance fixture resolves tile %d" % tile_id)
	if west_tile < 0 or target_tile < 0 or east_tile < 0 or building_tile < 0:
		await _finish([main])
		return

	main.city_grid[building_tile] = "住宅"
	main.building_customizations[building_tile] = {"variant": 1, "roof": 2, "wall": 3}
	var building_record: Dictionary = main.vertical_slice.register_existing_building(
		building_tile,
		"住宅",
		main.building_customizations[building_tile]
	)
	main.call("_update_tile_visual", building_tile, "住宅")
	main.refresh_visible_npc_proxies()
	main.debug_sync_npc_navigation_obstacles()
	await _settle(2)
	_check(not building_record.is_empty() and main.city_grid[building_tile] == "住宅", "Main contains a real registered building")
	_check(not main.vertical_slice.get_building_by_tile(building_tile).is_empty(), "the building also exists in the authoritative city state")

	var centers: Dictionary = main.call("_transport_tile_centers")
	var transport_snapshot := _transport_fixture(west_tile, target_tile, east_tile)
	main.transport_network_layer.set_network_snapshot(transport_snapshot, centers)
	main.transport_vehicle_controller.set_runtime_snapshot(transport_snapshot, centers)
	await _settle(2)
	_check(int(main.transport_network_layer.debug_snapshot().get("tile_state_count", 0)) == 3, "Main contains a three-tile transport network layer")
	_check(main.transport_vehicle_controller.active_vehicle_count() == 1, "Main contains the configured operational train vehicle")

	var npc_actors: Array[Button] = main.get_visible_npc_actors()
	_check(not npc_actors.is_empty(), "Main contains at least one authoritative NPC actor")
	var representative_npc: Button = npc_actors[0] if not npc_actors.is_empty() else null
	for actor: Button in npc_actors:
		actor.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for index: int in range(main.grid_buttons.size()):
		var button := main.grid_buttons[index] as Button
		if button != null:
			button.pressed.connect(Callable(self, "_on_tile_pressed").bind(index))
	var target_button := main.grid_buttons[target_tile] as Button
	var building_button := main.grid_buttons[building_tile] as Button
	_check(target_button != null and building_button != null, "target and building tile controls are mounted")
	_check(target_tile != building_tile and main.city_grid[target_tile] == "", "the click target is an empty tile distinct from the building")

	await _validate_zoom_snapshot(main, target_button, building_button, representative_npc, centers, transport_snapshot, target_tile, 1.00, "100%")
	await _drive_zoom(main, main.MAP_ZOOM_MAX, MOUSE_BUTTON_WHEEL_UP, "wheel up to 175%")
	await _validate_zoom_snapshot(main, target_button, building_button, representative_npc, centers, transport_snapshot, target_tile, 1.75, "175%")
	await _drive_zoom(main, main.MAP_ZOOM_MIN, MOUSE_BUTTON_WHEEL_DOWN, "wheel down to 65%")
	await _validate_zoom_snapshot(main, target_button, building_button, representative_npc, centers, transport_snapshot, target_tile, 0.65, "65%")
	await _verify_left_drag_and_reset_contract(main, target_button, target_tile)

	await _finish([main])


func _validate_zoom_snapshot(
	main,
	target_button: Button,
	building_button: Button,
	npc_actor: Button,
	centers: Dictionary,
	transport_snapshot: Dictionary,
	target_tile: int,
	expected_zoom: float,
	phase: String
) -> void:
	# Main intentionally refreshes visual layers from the authoritative network
	# after UI input. Reinstall this controlled visual-only fixture at each zoom
	# checkpoint so the test measures shared transforms, not route ownership.
	main.transport_network_layer.set_network_snapshot(transport_snapshot, centers)
	main.transport_vehicle_controller.set_runtime_snapshot(transport_snapshot, centers)
	_check(is_equal_approx(main.map_zoom, expected_zoom), "%s reaches the exact map zoom contract" % phase)
	var expected_stage_scale := float(main.call("_base_map_scale")) * expected_zoom
	_check(is_equal_approx(main.map_stage.scale.x, expected_stage_scale), "%s map_stage applies base scale times map zoom" % phase)
	_check(is_equal_approx(main.map_stage.scale.x, main.map_stage.scale.y), "%s map_stage scale remains uniform" % phase)

	var local_probe := Vector2(centers.get(str(target_tile), Vector2.INF))
	_check(local_probe != Vector2.INF, "%s has a canonical transport/tile point" % phase)
	var stage_transform: Transform2D = main.map_stage.get_global_transform_with_canvas()
	var layers: Dictionary = {
		"backdrop": main.city_backdrop,
		"transport network": main.transport_network_layer,
		"building/tile": main.tile_layer,
		"vehicle controller": main.transport_vehicle_controller,
		"NPC": main.npc_layer,
	}
	for layer_name: String in layers.keys():
		var layer := layers[layer_name] as Control
		_check(layer != null, "%s %s layer exists" % [phase, layer_name])
		if layer == null:
			continue
		_check(layer.get_parent() == main.map_stage, "%s %s layer is a direct map_stage child" % [phase, layer_name])
		_check(layer.position.distance_to(Vector2.ZERO) <= ROUND_TRIP_EPSILON, "%s %s layer has no independent pan offset" % [phase, layer_name])
		_check(layer.scale.distance_to(Vector2.ONE) <= ROUND_TRIP_EPSILON, "%s %s layer has no independent zoom" % [phase, layer_name])
		var layer_transform: Transform2D = layer.get_global_transform_with_canvas()
		for point: Vector2 in [Vector2.ZERO, local_probe, main.MAP_STAGE_SIZE]:
			var stage_global := stage_transform * point
			var layer_global := layer_transform * point
			_check(layer_global.distance_to(stage_global) <= TRANSFORM_EPSILON, "%s %s uses the common map_stage transform at %s" % [phase, layer_name, point])
			var round_trip := layer_transform.affine_inverse() * layer_global
			_check(round_trip.distance_to(point) <= ROUND_TRIP_EPSILON, "%s %s global/local point conversion round-trips" % [phase, layer_name])

	_check(main.city_backdrop.size.distance_to(main.MAP_STAGE_SIZE) <= ROUND_TRIP_EPSILON, "%s backdrop still covers map_stage local space" % phase)
	_check(building_button != null and building_button.get_parent() == main.tile_layer, "%s building remains on the tile layer" % phase)
	if building_button != null:
		var building_local_center := building_button.position + building_button.size * 0.5
		var expected_building_global: Vector2 = main.tile_layer.get_global_transform_with_canvas() * building_local_center
		var actual_building_global := building_button.get_global_rect().get_center()
		_check(actual_building_global.distance_to(expected_building_global) <= TRANSFORM_EPSILON, "%s building visual has no transform drift" % phase)
		_check(absf(building_button.get_global_rect().size.x - building_button.size.x * expected_stage_scale) <= TRANSFORM_EPSILON, "%s building visual width follows map_stage scale" % phase)

	_check(target_button != null and target_button.get_parent() == main.tile_layer, "%s click target remains on the tile layer" % phase)
	if target_button != null:
		var target_local_center := target_button.position + target_button.size * 0.5
		_check(target_local_center.distance_to(local_probe) <= ROUND_TRIP_EPSILON, "%s tile control and transport endpoint share the square-cell center" % phase)
		_check(main.npc_map_controller.tile_at_feet(local_probe) == target_tile, "%s NPC tile lookup resolves the same square-cell center" % phase)
		var expected_target_global: Vector2 = main.tile_layer.get_global_transform_with_canvas() * target_local_center
		_check(target_button.get_global_rect().get_center().distance_to(expected_target_global) <= TRANSFORM_EPSILON, "%s click target rect follows the shared transform" % phase)

	_check(npc_actor != null, "%s retains a representative NPC actor" % phase)
	if npc_actor != null:
		_check(npc_actor.get_parent() == main.npc_layer, "%s NPC actor remains on npc_layer" % phase)
		var npc_local_center := npc_actor.position + npc_actor.size * 0.5
		var expected_npc_global: Vector2 = main.npc_layer.get_global_transform_with_canvas() * npc_local_center
		_check(npc_actor.get_global_rect().get_center().distance_to(expected_npc_global) <= TRANSFORM_EPSILON, "%s NPC actor has no transform drift" % phase)
		_check(absf(npc_actor.get_global_rect().size.x - npc_actor.size.x * expected_stage_scale) <= TRANSFORM_EPSILON, "%s NPC actor width follows map_stage scale" % phase)

	var network_global: Vector2 = main.transport_network_layer.get_global_transform_with_canvas() * local_probe
	var vehicle_layer_global: Vector2 = main.transport_vehicle_controller.get_global_transform_with_canvas() * local_probe
	_check(network_global.distance_to(vehicle_layer_global) <= TRANSFORM_EPSILON, "%s transport ground and vehicles agree on the canonical tile point" % phase)
	var route_debug: Dictionary = main.transport_vehicle_controller.debug_route_snapshot()
	var vehicles: Array = route_debug.get("vehicles", [])
	_check(vehicles.size() == 1, "%s retains exactly one operational vehicle record" % phase)
	var vehicle_actor := _first_control_child(main.transport_vehicle_controller)
	_check(vehicle_actor != null, "%s retains a concrete vehicle actor" % phase)
	if vehicle_actor != null:
		_check(vehicle_actor.get_parent() == main.transport_vehicle_controller, "%s vehicle actor remains on the controller layer" % phase)
		var vehicle_center_global: Vector2 = vehicle_actor.get_global_transform_with_canvas() * (vehicle_actor.size * 0.5)
		var vehicle_local_position: Vector2 = Vector2(Dictionary(vehicles[0]).get("position", Vector2.INF)) if not vehicles.is_empty() else Vector2.INF
		var expected_vehicle_global: Vector2 = main.transport_vehicle_controller.get_global_transform_with_canvas() * vehicle_local_position
		_check(vehicle_center_global.distance_to(expected_vehicle_global) <= TRANSFORM_EPSILON, "%s vehicle actor has no transform drift" % phase)
		_check(absf(vehicle_actor.get_global_transform_with_canvas().x.length() - expected_stage_scale) <= ROUND_TRIP_EPSILON, "%s vehicle transform follows map_stage scale" % phase)

	if target_button != null:
		await _click_target(main, target_button, target_tile, phase)


func _drive_zoom(main, target_zoom: float, wheel_button: int, phase: String) -> void:
	for _step in range(20):
		if is_equal_approx(main.map_zoom, target_zoom):
			break
		await _wheel_once(main, wheel_button, phase)
	_check(is_equal_approx(main.map_zoom, target_zoom), "%s reaches its clamped endpoint" % phase)


func _wheel_once(main, wheel_button: int, phase: String) -> void:
	var cursor: Vector2 = main.map_viewport.get_global_rect().get_center()
	var before_transform: Transform2D = main.map_stage.get_global_transform_with_canvas()
	var anchor_local: Vector2 = before_transform.affine_inverse() * cursor
	var wheel := InputEventMouseButton.new()
	wheel.button_index = wheel_button
	wheel.pressed = true
	wheel.position = cursor
	wheel.global_position = cursor
	main._input(wheel)
	await process_frame
	var anchored_global: Vector2 = main.map_stage.get_global_transform_with_canvas() * anchor_local
	_check(anchored_global.distance_to(cursor) <= TRANSFORM_EPSILON, "%s keeps the stage point under the wheel cursor" % phase)


func _verify_left_drag_and_reset_contract(main, target_button: Button, target_tile: int) -> void:
	var cursor: Vector2 = main.map_viewport.get_global_rect().get_center()
	# Establish an arbitrary, non-default wheel state before testing a direct
	# right-click reset. This is intentionally independent from the min/max test.
	await _drive_zoom(main, 1.15, MOUSE_BUTTON_WHEEL_UP, "wheel from minimum into enlarged left-drag contract")
	_check(main.map_zoom > 1.0, "left-drag contract starts from an enlarged map")

	var pan_before_click: Vector2 = main.map_pan_offset
	_tile_press_count = 0
	_last_tile_pressed = -1
	var drag_start := target_button.get_global_rect().get_center()
	_check(main.map_viewport.get_global_rect().has_point(drag_start), "left-drag source tile remains inside the map viewport")
	var hover_motion := InputEventMouseMotion.new()
	hover_motion.position = drag_start
	hover_motion.global_position = drag_start
	root.push_input(hover_motion, true)
	await process_frame
	var left_down := InputEventMouseButton.new()
	left_down.button_index = MOUSE_BUTTON_LEFT
	left_down.button_mask = MOUSE_BUTTON_MASK_LEFT
	left_down.pressed = true
	left_down.position = drag_start
	left_down.global_position = drag_start
	root.push_input(left_down, true)
	await process_frame
	var short_motion := InputEventMouseMotion.new()
	short_motion.position = drag_start + Vector2(3.0, 2.0)
	short_motion.global_position = short_motion.position
	short_motion.relative = Vector2(3.0, 2.0)
	short_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(short_motion, true)
	await process_frame
	_check(main.map_pan_offset.is_equal_approx(pan_before_click), "short left movement below the drag threshold does not pan")

	var drag_motion := InputEventMouseMotion.new()
	drag_motion.position = drag_start + Vector2(84.0, -52.0)
	drag_motion.global_position = drag_motion.position
	drag_motion.relative = Vector2(81.0, -54.0)
	drag_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(drag_motion, true)
	await process_frame
	_check(not main.map_pan_offset.is_equal_approx(pan_before_click), "left drag pans an enlarged map after its threshold")
	var left_up := InputEventMouseButton.new()
	left_up.button_index = MOUSE_BUTTON_LEFT
	left_up.pressed = false
	left_up.position = drag_motion.position
	left_up.global_position = drag_motion.position
	root.push_input(left_up, true)
	await _settle(2)
	_check(not main._map_pan_drag_active, "left drag releases its map capture")
	_check(_tile_press_count == 0, "a captured map drag cannot click through to its source tile")

	# A normal GUI tile click remains a click at the same enlarged transform.
	await _click_target(main, target_button, target_tile, "left-drag contract ordinary tile click")

	var right_reset := InputEventMouseButton.new()
	right_reset.button_index = MOUSE_BUTTON_RIGHT
	right_reset.pressed = true
	right_reset.position = cursor
	right_reset.global_position = cursor
	main._input(right_reset)
	_check(is_equal_approx(main.map_zoom, 1.0), "right click resets arbitrary wheel zoom exactly to 100%")
	_check(main.map_pan_offset.is_equal_approx(Vector2.ZERO), "right click restores original pan exactly")
	var expected_position: Vector2 = (main.map_viewport.size - main.MAP_STAGE_SIZE * float(main.call("_base_map_scale"))) * 0.5
	_check(main.map_stage.position.distance_to(expected_position) <= ROUND_TRIP_EPSILON, "right click restores the original centered stage anchor")

	# While a camera reset is possible, it wins without destroying an active map
	# action. Once already reset, right-click retains its established cancel role.
	main.placement_mode_active = true
	main.placement_building_name = "住宅"
	await _wheel_once(main, MOUSE_BUTTON_WHEEL_UP, "wheel up before active-placement right reset")
	main._input(right_reset)
	_check(main.placement_mode_active, "right reset preserves active placement instead of cancelling it")
	_check(is_equal_approx(main.map_zoom, 1.0) and main.map_pan_offset.is_equal_approx(Vector2.ZERO), "active-placement right reset restores the exact original camera")
	main._input(right_reset)
	_check(not main.placement_mode_active, "right click at the original camera retains the explicit placement cancel affordance")

	main.map_action_mode = "transport_infrastructure"
	await _wheel_once(main, MOUSE_BUTTON_WHEEL_UP, "wheel up before active-transport right reset")
	main._input(right_reset)
	_check(main.map_action_mode == "transport_infrastructure", "right reset preserves an active transport map action instead of cancelling it")
	_check(is_equal_approx(main.map_zoom, 1.0) and main.map_pan_offset.is_equal_approx(Vector2.ZERO), "active-transport right reset restores the exact original camera")
	main.map_action_mode = ""

	# Modal surfaces remain input boundaries: a right click cannot pan/reset a map
	# behind a visible modal or click through to the active map state.
	await _wheel_once(main, MOUSE_BUTTON_WHEEL_UP, "wheel up before modal right-click guard")
	var zoom_before_modal_right_click: float = main.map_zoom
	main.settings_overlay.show()
	main._input(right_reset)
	_check(is_equal_approx(main.map_zoom, zoom_before_modal_right_click), "right click behind a visible modal does not reset the map")
	main.settings_overlay.hide()


func _click_target(main, button: Button, target_tile: int, phase: String) -> void:
	_tile_press_count = 0
	_last_tile_pressed = -1
	var center := button.get_global_rect().get_center()
	_check(main.map_viewport.get_global_rect().has_point(center), "%s click target remains inside the map viewport" % phase)

	var motion := InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	motion.relative = Vector2.ZERO
	root.push_input(motion, true)
	await _settle(2)

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
	await _settle(2)
	_check(_tile_press_count == 1, "%s GUI click emits exactly one tile press" % phase)
	_check(_last_tile_pressed == target_tile, "%s GUI click reaches the intended tile without layer drift" % phase)


func _transport_fixture(west_tile: int, middle_tile: int, east_tile: int) -> Dictionary:
	return {
		"tile_states": {
			str(west_tile): {
				"segments": ["rail_track"],
				"facilities": [],
				"connections": {"rail_track": ["e"]},
				"neighbours": {"e": middle_tile},
				"crossing": "",
			},
			str(middle_tile): {
				"segments": ["road", "rail_track"],
				"facilities": ["rail_signal"],
				"connections": {"rail_track": ["w", "e"], "road": ["w", "e"]},
				"neighbours": {"w": west_tile, "e": east_tile},
				"crossing": "road_rail_level_crossing",
			},
			str(east_tile): {
				"segments": ["rail_track"],
				"facilities": [],
				"connections": {"rail_track": ["w"]},
				"neighbours": {"w": middle_tile},
				"crossing": "",
			},
		},
		"crossings": {
			str(middle_tile): {"tile_id": middle_tile, "kind": "road_rail_level_crossing"},
		},
		"operational_lines": [{
			"id": "acceptance_train_line",
			"mode": "train",
			"status": "operational",
			"vehicle_kind": "train",
			"path_tile_ids": [west_tile, middle_tile, east_tile],
			"station_tile_ids": [west_tile, east_tile],
			"fleet_size": 1,
			"headway_minutes": 8,
			"fare": 45,
			"loop_seconds": 10.0,
		}],
		"private_road_paths": [],
	}


func _first_control_child(parent: Node) -> Control:
	for child_variant: Variant in parent.get_children():
		var child := child_variant as Control
		if child != null:
			return child
	return null


func _on_tile_pressed(tile_index: int) -> void:
	_tile_press_count += 1
	_last_tile_pressed = tile_index


func _wait_for_loading(main) -> void:
	for _frame in range(180):
		await process_frame
		if not main.start_screen.is_loading():
			return
	_fail("New loading did not finish within 180 frames")


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame


func _cleanup_save() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	for suffix: String in ["", ".tmp", ".bak"]:
		var candidate := absolute_path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _finish(fixtures: Array) -> void:
	_cleanup_save()
	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Map zoom all-layers acceptance test passed. Checks=%d Zooms=100/175/65" % _checks)
	await TestCleanup.finish(self, fixtures, exit_code)


func _fail(message: String) -> void:
	_failed = true
	push_error("Map zoom all-layers acceptance failed: %s" % message)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_fail(message)
