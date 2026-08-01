extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const TEST_SAVE_PATH := "user://mayor_simulator/tests/fiscal_slider_pointer.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1440, 900)
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.start_save_path = TEST_SAVE_PATH
	main.start_screen.animation_duration = 0.01
	main.start_screen.new_game_button.pressed.emit()
	for _frame in range(120):
		await process_frame
		if not main.start_screen.is_loading():
			break
	main.tutorial_overlay.close_as_completed(false)
	main.tutorial_overlay._transition.custom_step(1.0)
	await process_frame
	main.municipal_overlay.open_page("finance")
	var tabs := main.find_child("FiscalCategoryTabs", true, false) as TabContainer
	tabs.current_tab = 2
	var service_tabs := tabs.get_child(2) as TabContainer
	service_tabs.current_tab = 1
	await process_frame
	await process_frame

	var slider := main.find_child("FiscalSlider_service_stadium", true, false) as HSlider
	if slider == null or not slider.is_visible_in_tree():
		push_error("stadium slider is missing or hidden")
		await TestCleanup.finish(self, [main], 1)
		return
	var rect := slider.get_global_rect()
	var start := rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.5)
	var finish := Vector2(rect.end.x - 6.0, start.y)
	print("STADIUM_SLIDER_RECT %s start=%s finish=%s" % [rect, start, finish])
	var blockers: Array[String] = []
	for node in main.find_children("*", "Control", true, false):
		var control := node as Control
		if control != slider and control.is_visible_in_tree() and control.mouse_filter != Control.MOUSE_FILTER_IGNORE and control.get_global_rect().has_point(start):
			blockers.append("%s:%s rect=%s z=%d" % [control.name, control.get_class(), control.get_global_rect(), control.z_index])
	print("STADIUM_POINTER_CANDIDATES %s" % str(blockers))

	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = start
	down.global_position = start
	root.push_input(down, true)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = finish
	motion.global_position = finish
	motion.relative = finish - start
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = finish
	up.global_position = finish
	root.push_input(up, true)
	await process_frame
	if int(main.service_fees["stadium"]) <= 80:
		push_error("stadium slider did not respond to a viewport-routed pointer drag; value=%d" % int(main.service_fees["stadium"]))
		await TestCleanup.finish(self, [main], 1)
		return
	print("Fiscal stadium pointer test passed. value=%d" % int(main.service_fees["stadium"]))
	await TestCleanup.finish(self, [main], 0)
