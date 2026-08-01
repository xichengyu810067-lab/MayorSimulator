extends SceneTree

var _failed := false
var _emitted_ids: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ProgressiveOptionButtonScript: Script = load("res://ui/components/progressive_option_button.gd") as Script
	var picker = ProgressiveOptionButtonScript.new()
	root.add_child(picker)
	picker.choice_selected.connect(func(choice_id: String) -> void: _emitted_ids.append(choice_id))
	picker.set_choices([
		{"id": "a", "name": "Alpha"},
		{"id": "b", "name": "Beta"},
		{"id": "c", "name": "Gamma"},
		{"id": "d", "name": "Delta"},
		{"id": "e", "name": "Epsilon"},
	], "a")
	await process_frame
	_check(picker.item_count == 3, "first page contains two choices and More")
	_check(picker.visible_popup_item_count() == picker.item_count, "visible count reports the real popup rows")
	_check(picker.selected_choice_id() == "a" and picker.text == "Alpha", "initial choice is selected and displayed")

	var seen_ids: Dictionary = {}
	_collect_visible_choice_ids(picker, seen_ids)
	_activate_more(picker)
	await process_frame
	_collect_visible_choice_ids(picker, seen_ids)
	_check(picker.item_count == 3, "second page still exposes at most three rows")
	_check(picker.selected_choice_id() == "a", "paging does not change the selected choice")
	_check(picker.selected == -1 and picker.text == "Alpha", "off-page choice remains the button caption without a popup row")

	var delta_index := _choice_item_index(picker, "d")
	_check(delta_index >= 0, "second page exposes Delta")
	if delta_index >= 0:
		picker.select(delta_index)
		picker.item_selected.emit(delta_index)
	await process_frame
	_check(picker.selected_choice_id() == "d" and picker.text == "Delta", "selecting a paged choice updates the caption")
	_check(_emitted_ids == ["d"], "selecting a real choice emits exactly one semantic ID")

	_activate_more(picker)
	await process_frame
	_collect_visible_choice_ids(picker, seen_ids)
	_check(picker.selected_choice_id() == "d" and picker.text == "Delta", "third page preserves the current choice")
	_activate_more(picker)
	await process_frame
	_collect_visible_choice_ids(picker, seen_ids)
	_activate_more(picker)
	await process_frame
	_collect_visible_choice_ids(picker, seen_ids)
	for choice_id: String in ["a", "b", "c", "d", "e"]:
		_check(seen_ids.has(choice_id), "choice '%s' is reachable through More paging" % choice_id)
	_check(picker.item_count <= picker.MAX_VISIBLE_OPTIONS, "no page exceeds the three-row disclosure limit")

	picker.set_show_all_choices(true)
	await process_frame
	_check(picker.shows_all_choices(), "all-choice mode is enabled")
	_check(picker.item_count == 5, "all-choice mode exposes all five choices on one popup page")
	_check(not _has_more_item(picker), "all-choice mode removes the More navigation row")
	_check(picker.selected_choice_id() == "d" and picker.text == "Delta", "all-choice mode preserves the current selection")
	for choice_id: String in ["a", "b", "c", "d", "e"]:
		_check(_choice_item_index(picker, choice_id) >= 0, "all-choice mode exposes '%s' directly" % choice_id)

	var epsilon_index := _choice_item_index(picker, "e")
	if epsilon_index >= 0:
		picker.select(epsilon_index)
		picker.item_selected.emit(epsilon_index)
	await process_frame
	_check(picker.selected_choice_id() == "e" and picker.text == "Epsilon", "single-page selection updates the caption")
	_check(_emitted_ids == ["d", "e"], "single-page selection emits exactly one additional semantic ID")

	picker.queue_free()
	if _failed:
		quit(1)
	else:
		print("Progressive option button regression test passed. Choices=5")
		quit(0)


func _activate_more(picker) -> void:
	var more_index := -1
	for index in picker.item_count:
		var metadata: Variant = picker.get_item_metadata(index)
		if metadata is Dictionary and str(metadata.get("kind", "")) == "more":
			more_index = index
			break
	_check(more_index >= 0, "current page exposes More")
	if more_index >= 0:
		picker.select(more_index)
		picker.item_selected.emit(more_index)


func _choice_item_index(picker, choice_id: String) -> int:
	for index in picker.item_count:
		var metadata: Variant = picker.get_item_metadata(index)
		if metadata is String and str(metadata) == choice_id:
			return index
	return -1


func _has_more_item(picker) -> bool:
	for index in picker.item_count:
		var metadata: Variant = picker.get_item_metadata(index)
		if metadata is Dictionary and str(metadata.get("kind", "")) == "more":
			return true
	return false


func _collect_visible_choice_ids(picker, output: Dictionary) -> void:
	for index in picker.item_count:
		var metadata: Variant = picker.get_item_metadata(index)
		if metadata is String:
			output[str(metadata)] = true


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Progressive option regression failed: %s" % message)
