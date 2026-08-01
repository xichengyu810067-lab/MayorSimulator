class_name ProgressiveChoicePager
extends VBoxContainer

signal page_changed(page_index: int)

const DEFAULT_PAGE_SIZE := 3

var page_size := DEFAULT_PAGE_SIZE
var columns := 3
var _page_index := 0
var _choices: Array[Control] = []
var _grid: GridContainer
var _navigation: HBoxContainer
var _previous_button: Button
var _page_label: Label
var _next_button: Button


func _init(p_columns: int = 3, p_page_size: int = DEFAULT_PAGE_SIZE) -> void:
	columns = maxi(1, p_columns)
	page_size = clampi(p_page_size, 1, DEFAULT_PAGE_SIZE)
	name = "ProgressiveChoicePager"
	set_meta("progressive_choice_group", true)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)

	_grid = GridContainer.new()
	_grid.name = "VisibleChoices"
	_grid.columns = columns
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	add_child(_grid)

	_navigation = HBoxContainer.new()
	_navigation.name = "ChoicePagination"
	_navigation.alignment = BoxContainer.ALIGNMENT_CENTER
	_navigation.add_theme_constant_override("separation", 12)
	_navigation.set_meta("progressive_navigation", true)
	add_child(_navigation)

	_previous_button = _navigation_button("ChoicePrevious", "← 上一頁")
	_previous_button.pressed.connect(func() -> void: set_page(_page_index - 1))
	_navigation.add_child(_previous_button)
	_page_label = Label.new()
	_page_label.name = "ChoicePageLabel"
	_page_label.custom_minimum_size = Vector2(110, 42)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_page_label.add_theme_font_size_override("font_size", 17)
	# A dark glyph with a light outline stays legible on both supported palettes.
	_page_label.add_theme_color_override("font_color", Color(0.08, 0.12, 0.16))
	_page_label.add_theme_color_override("font_outline_color", Color(0.98, 0.98, 0.96))
	_page_label.add_theme_constant_override("outline_size", 4)
	_navigation.add_child(_page_label)
	_next_button = _navigation_button("ChoiceNext", "下一頁 →")
	_next_button.pressed.connect(func() -> void: set_page(_page_index + 1))
	_navigation.add_child(_next_button)
	_refresh()


func add_choice(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	if _choices.has(control):
		_refresh()
		return
	var old_parent := control.get_parent()
	if old_parent != null:
		old_parent.remove_child(control)
	control.set_meta("progressive_choice", true)
	_choices.append(control)
	_grid.add_child(control)
	_refresh()


func remove_choice(control: Control) -> void:
	var index := _choices.find(control)
	if index < 0:
		return
	_choices.remove_at(index)
	if is_instance_valid(control) and control.get_parent() == _grid:
		_grid.remove_child(control)
	_refresh()


func choice_grid() -> GridContainer:
	return _grid


func clear_choices(queue_nodes: bool = false) -> void:
	for choice in _choices:
		if not is_instance_valid(choice):
			continue
		if choice.get_parent() == _grid:
			_grid.remove_child(choice)
		if queue_nodes:
			choice.queue_free()
	_choices.clear()
	_page_index = 0
	_refresh()


func set_page(value: int) -> void:
	var target := clampi(value, 0, maxi(0, page_count() - 1))
	if target == _page_index:
		_refresh()
		return
	_page_index = target
	_refresh()
	page_changed.emit(_page_index)


func show_choice(control: Control) -> void:
	var index := _choices.find(control)
	if index >= 0:
		set_page(index / page_size)


func page_count() -> int:
	return maxi(1, ceili(float(_choices.size()) / float(page_size)))


func choice_count() -> int:
	return _choices.size()


func visible_choice_count() -> int:
	var count := 0
	for choice in _choices:
		if is_instance_valid(choice) and choice.visible:
			count += 1
	return count


func choices() -> Array[Control]:
	return _choices.duplicate()


func _refresh() -> void:
	_page_index = clampi(_page_index, 0, maxi(0, page_count() - 1))
	var start := _page_index * page_size
	var finish := start + page_size
	for index in _choices.size():
		var choice := _choices[index]
		if is_instance_valid(choice):
			choice.visible = index >= start and index < finish
	var has_pages := _choices.size() > page_size
	_navigation.visible = has_pages
	_previous_button.disabled = _page_index <= 0
	_next_button.disabled = _page_index >= page_count() - 1
	_page_label.text = L10n.text("第 %d / %d 頁") % [_page_index + 1, page_count()]


func _navigation_button(node_name: String, label_text: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = label_text
	button.custom_minimum_size = Vector2(132, 44)
	button.add_theme_font_size_override("font_size", 17)
	button.set_meta("progressive_navigation", true)
	return button
