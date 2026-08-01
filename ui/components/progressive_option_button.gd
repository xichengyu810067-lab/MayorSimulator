class_name ProgressiveOptionButton
extends OptionButton

signal choice_selected(choice_id: String)

const MAX_VISIBLE_OPTIONS := 3
const PAGE_CHOICE_COUNT := 2

var _choices: Array[Dictionary] = []
var _page_index := 0
var _selected_id := ""
var _rebuilding := false
var _show_all_choices := false


func _init() -> void:
	set_meta("progressive_option_menu", true)
	item_selected.connect(_on_item_selected)


func set_choices(options: Array, selected_id: String = "") -> void:
	_choices.clear()
	for option_variant in options:
		if option_variant is Dictionary:
			_choices.append((option_variant as Dictionary).duplicate(true))
	_selected_id = selected_id
	if _selected_id.is_empty() and not _choices.is_empty():
		_selected_id = str(_choices[0].get("id", ""))
	_page_index = _page_for_choice(_selected_id)
	_rebuild_items()


func set_show_all_choices(value: bool) -> void:
	if _show_all_choices == value:
		return
	_show_all_choices = value
	_page_index = 0
	if not _choices.is_empty():
		_rebuild_items()


func shows_all_choices() -> bool:
	return _show_all_choices


func select_choice(choice_id: String) -> bool:
	if _index_for_choice(choice_id) < 0:
		return false
	_selected_id = choice_id
	_page_index = _page_for_choice(choice_id)
	_rebuild_items()
	return true


func selected_choice_id() -> String:
	return _selected_id


func choice_count() -> int:
	return _choices.size()


func visible_popup_item_count() -> int:
	return item_count


func _rebuild_items() -> void:
	_rebuilding = true
	clear()
	if _choices.is_empty():
		_rebuilding = false
		return
	if _show_all_choices or _choices.size() <= MAX_VISIBLE_OPTIONS:
		for choice in _choices:
			_add_choice_item(choice)
		_select_visible_choice()
		_rebuilding = false
		return

	var page_count := ceili(float(_choices.size()) / float(PAGE_CHOICE_COUNT))
	_page_index = clampi(_page_index, 0, maxi(0, page_count - 1))
	var start := _page_index * PAGE_CHOICE_COUNT
	var end := mini(_choices.size(), start + PAGE_CHOICE_COUNT)
	for index in range(start, end):
		_add_choice_item(_choices[index])
	add_item(_localized_text("更多…"))
	set_item_metadata(item_count - 1, {"kind": "more"})
	_select_visible_choice()
	_rebuilding = false


func _add_choice_item(choice: Dictionary) -> void:
	add_item(_localized_text(str(choice.get("name", choice.get("id", "")))))
	set_item_metadata(item_count - 1, str(choice.get("id", "")))
	var tooltip := str(choice.get("tooltip", ""))
	if not tooltip.is_empty():
		get_popup().set_item_tooltip(item_count - 1, _localized_text(tooltip))


func _select_visible_choice() -> void:
	for index in item_count:
		var metadata = get_item_metadata(index)
		if metadata is String and str(metadata) == _selected_id:
			select(index)
			return
	# Godot 4.7's PopupMenu has no hidden-item API. Keep the current choice as
	# the button caption while another page is visible by temporarily leaving
	# the OptionButton without a selected popup row.
	var selected_choice := _choice_for_id(_selected_id)
	select(-1)
	text = _localized_text(str(selected_choice.get("name", _selected_id)))


func _on_item_selected(index: int) -> void:
	if _rebuilding or index < 0 or index >= item_count:
		return
	var metadata = get_item_metadata(index)
	if metadata is Dictionary and str(metadata.get("kind", "")) == "more":
		var page_count := ceili(float(_choices.size()) / float(PAGE_CHOICE_COUNT))
		_page_index = (_page_index + 1) % maxi(1, page_count)
		_rebuild_items()
		return
	if not metadata is String:
		return
	_selected_id = str(metadata)
	choice_selected.emit(_selected_id)


func _page_for_choice(choice_id: String) -> int:
	if _show_all_choices:
		return 0
	var index := _index_for_choice(choice_id)
	return maxi(0, index / PAGE_CHOICE_COUNT)


func _index_for_choice(choice_id: String) -> int:
	for index in _choices.size():
		if str(_choices[index].get("id", "")) == choice_id:
			return index
	return -1


func _choice_for_id(choice_id: String) -> Dictionary:
	var index := _index_for_choice(choice_id)
	return _choices[index] if index >= 0 else {}


func _localized_text(source: String) -> String:
	var scene_tree := Engine.get_main_loop() as SceneTree
	if scene_tree == null:
		return source
	var localization = scene_tree.root.get_node_or_null("L10n")
	return str(localization.text(source)) if localization != null else source
