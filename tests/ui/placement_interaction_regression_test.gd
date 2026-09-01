extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var TileScript = load("res://scripts/world/city_tile_button.gd")
	var ConfirmScript = load("res://ui/shell/construction_confirm_overlay.gd")
	_check(TileScript != null, "city tile script could not be loaded")
	_check(ConfirmScript != null, "construction confirmation script could not be loaded")
	if _failed:
		await TestCleanup.finish(self, [], 1)
		return

	var tile = TileScript.new()
	tile.size = Vector2(120, 80)
	root.add_child(tile)
	_check(bool(tile.call("_has_point", Vector2(60, 40))), "square center is not clickable")
	_check(bool(tile.call("_has_point", Vector2(0, 40))), "square edge is not clickable")
	_check(bool(tile.call("_has_point", Vector2(5, 5))), "square top-left corner is not clickable")
	_check(bool(tile.call("_has_point", Vector2(115, 75))), "square bottom-right corner is not clickable")
	_check(not bool(tile.call("_has_point", Vector2(-1, 40))), "point left of the square is clickable")
	_check(not bool(tile.call("_has_point", Vector2(120, 40))), "point right of the square is clickable")

	var confirm = ConfirmScript.new()
	root.add_child(confirm)
	await process_frame
	var cancellations: Array[int] = []
	var confirmations: Array[int] = []
	confirm.cancelled.connect(func() -> void: cancellations.append(1))
	confirm.confirmed.connect(func(index: int) -> void: confirmations.append(index))
	var quote := {
		"worker_count": 5,
		"duration_days": 5,
		"base_cost": 1000,
		"total_labor_cost": 50000,
		"total_cost": 51000
	}
	confirm.open("商店", 12, quote, 80000)
	var cost_label := confirm.find_child("ConstructionCostBreakdown", true, false) as Label
	var confirm_button := confirm.find_child("ConfirmConstructionButton", true, false) as Button
	var cancel_button := confirm.find_child("CancelConstructionButton", true, false) as Button
	_check(confirm.visible, "construction confirmation did not open")
	_check(cost_label != null and cost_label.text.contains("1,000") and cost_label.text.contains("50,000") and cost_label.text.contains("51,000"), "construction quote is incomplete")
	_check(confirm_button != null and not confirm_button.disabled, "affordable construction cannot be confirmed")
	cancel_button.pressed.emit()
	_check(not confirm.visible and cancellations.size() == 1 and confirmations.is_empty(), "cancelling the quote emitted the wrong result")

	confirm.open("商店", 12, quote, 50000)
	_check(confirm_button.disabled, "unaffordable construction confirmation is enabled")
	confirm.close()
	confirm.open("商店", 12, quote, 80000)
	confirm_button.pressed.emit()
	_check(not confirm.visible and confirmations == [12], "confirming the quote did not emit the selected tile")

	var packed_main: PackedScene = load("res://scenes/Main.tscn")
	_check(packed_main != null, "main scene could not be loaded for placement input checks")
	var main: Node = null
	if packed_main != null:
		main = packed_main.instantiate()
		root.add_child(main)
		await process_frame
		await process_frame
		if main.start_screen != null:
			main.start_screen.hide()

		var empty_tile := main.grid_buttons[0] as Button
		_check(empty_tile != null, "empty map tile button is unavailable for placement input checks")
		if empty_tile != null:
			_activate_placement(main)
			empty_tile.focus_mode = Control.FOCUS_ALL
			empty_tile.grab_focus()
			var escape := InputEventKey.new()
			escape.keycode = KEY_ESCAPE
			escape.pressed = true
			root.push_input(escape, true)
			await process_frame
			_check(not bool(main.placement_mode_active), "Escape did not cancel placement while a map tile button had focus")

			_activate_placement(main)
			var tile_center := empty_tile.get_global_rect().get_center()
			var right_click := InputEventMouseButton.new()
			right_click.button_index = MOUSE_BUTTON_RIGHT
			right_click.pressed = true
			right_click.position = tile_center
			right_click.global_position = tile_center
			root.push_input(right_click, true)
			await process_frame
			_check(not bool(main.placement_mode_active), "right click on an empty map tile button did not cancel placement")

			_activate_placement(main)
			var left_click := InputEventMouseButton.new()
			left_click.button_index = MOUSE_BUTTON_LEFT
			left_click.pressed = true
			left_click.position = tile_center
			left_click.global_position = tile_center
			main.call("_input", left_click)
			_check(bool(main.placement_mode_active), "placement input handler intercepted the left click used to open construction confirmation")

			main.construction_confirmation.open("商店", 0, quote, 80000)
			var overlay_escape := InputEventKey.new()
			overlay_escape.keycode = KEY_ESCAPE
			overlay_escape.pressed = true
			root.push_input(overlay_escape, true)
			await process_frame
			_check(not main.construction_confirmation.is_open(), "Escape no longer closes the construction confirmation overlay")
			_check(bool(main.placement_mode_active), "construction confirmation Escape incorrectly cancelled placement mode")
			main.call("_cancel_building_placement", false)

	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Placement interaction regression test passed.")
	await TestCleanup.finish(self, [tile, confirm, main], exit_code)


func _activate_placement(main) -> void:
	main.placement_mode_active = true
	main.placement_building_name = "商店"
	main.call("_sync_placement_banner")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
