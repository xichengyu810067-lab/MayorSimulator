class_name ProgressiveChoicePager
extends VBoxContainer

signal page_changed(page_index: int)

const DEFAULT_PAGE_SIZE := 3
const MAX_PAGE_SIZE := 6

var page_size := DEFAULT_PAGE_SIZE
var columns := 3
var minimum_choice_width := 0.0
var _page_index := 0
var _choices: Array[Control] = []
var _grid: GridContainer
var _balanced_rows_host: VBoxContainer
var _navigation: HBoxContainer
var _previous_button: Button
var _page_label: Label
var _next_button: Button
var _balanced_page_layout := false


func _init(p_columns: int = 3, p_page_size: int = DEFAULT_PAGE_SIZE) -> void:
	columns = maxi(1, p_columns)
	page_size = clampi(p_page_size, 1, MAX_PAGE_SIZE)
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

	_balanced_rows_host = VBoxContainer.new()
	_balanced_rows_host.name = "BalancedChoiceRows"
	_balanced_rows_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_balanced_rows_host.add_theme_constant_override("separation", 10)
	_balanced_rows_host.visible = false
	add_child(_balanced_rows_host)

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
	resized.connect(_refresh_columns_for_width)


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
	if is_instance_valid(control) and control.get_parent() != null:
		control.get_parent().remove_child(control)
	_refresh()


func choice_grid() -> GridContainer:
	return _grid


func clear_choices(queue_nodes: bool = false) -> void:
	for choice in _choices:
		if not is_instance_valid(choice):
			continue
		if choice.get_parent() != null:
			choice.get_parent().remove_child(choice)
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


func set_minimum_choice_width(value: float) -> void:
	minimum_choice_width = maxf(0.0, value)
	_refresh_columns_for_width()


func set_balanced_page_layout(enabled: bool) -> void:
	_balanced_page_layout = enabled
	set_meta("balanced_building_pager", enabled)
	_refresh()


func balanced_rows_for_count(visible_count: int) -> Array[int]:
	match clampi(visible_count, 0, page_size):
		0: return []
		1: return [1]
		2: return [2]
		3: return [3]
		4: return [2, 2]
		5: return [3, 2]
		_: return [3, 3]


func debug_layout_state() -> Dictionary:
	var row_counts: Array[int] = []
	var row_rects: Array[Rect2] = []
	if _balanced_page_layout:
		for row_variant in _balanced_rows_host.get_children():
			var row := row_variant as HBoxContainer
			if row == null:
				continue
			var card_count := 0
			for child_variant in row.get_children():
				if child_variant is Control and bool((child_variant as Control).get_meta("progressive_choice", false)):
					card_count += 1
			row_counts.append(card_count)
			row_rects.append(row.get_rect())
	return {
		"balanced": _balanced_page_layout,
		"page_size": page_size,
		"page_index": _page_index,
		"page_count": page_count(),
		"choice_count": choice_count(),
		"visible_count": visible_choice_count(),
		"row_counts": row_counts,
		"row_rects": row_rects,
		"last_row_centered": _balanced_last_row_centered(visible_choice_count()),
		"navigation_visible": _navigation.visible,
		"minimum_choice_width": minimum_choice_width,
	}


func _refresh_columns_for_width() -> void:
	if _balanced_page_layout or minimum_choice_width <= 0.0 or size.x <= 0.0:
		return
	var gutter := float(_grid.get_theme_constant("h_separation"))
	var fit_columns := maxi(1, floori((size.x + gutter) / (minimum_choice_width + gutter)))
	_grid.columns = clampi(fit_columns, 1, columns)


func _refresh() -> void:
	_page_index = clampi(_page_index, 0, maxi(0, page_count() - 1))
	var start := _page_index * page_size
	var finish := start + page_size
	for index in _choices.size():
		var choice := _choices[index]
		if is_instance_valid(choice):
			choice.visible = index >= start and index < finish
	if _balanced_page_layout:
		_rebuild_balanced_rows(start, mini(finish, _choices.size()))
	else:
		_restore_standard_grid()
	var has_pages := _choices.size() > page_size
	_navigation.visible = has_pages
	_previous_button.disabled = _page_index <= 0
	_next_button.disabled = _page_index >= page_count() - 1
	_page_label.text = L10n.text("第 %d / %d 頁") % [_page_index + 1, page_count()]


func _rebuild_balanced_rows(start: int, finish: int) -> void:
	_restore_choices_to_grid()
	_clear_balanced_rows()
	_grid.visible = false
	_balanced_rows_host.visible = true
	var visible_count := maxi(0, finish - start)
	var row_counts := balanced_rows_for_count(visible_count)
	var cursor := start
	for row_index in row_counts.size():
		var card_count := row_counts[row_index]
		var row := HBoxContainer.new()
		row.name = "BalancedChoiceRow_%d" % row_index
		row.custom_minimum_size = Vector2(0, 120)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 10)
		_balanced_rows_host.add_child(row)
		var center_single := visible_count == 1 and card_count == 1
		var center_two := visible_count == 5 and row_index == row_counts.size() - 1 and card_count == 2
		if center_single:
			_add_balanced_spacer(row, 1.0)
		elif center_two:
			_add_balanced_spacer(row, 0.5)
		for _slot in card_count:
			var choice := _choices[cursor]
			cursor += 1
			if choice.get_parent() != null:
				choice.get_parent().remove_child(choice)
			choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			choice.size_flags_stretch_ratio = 1.0
			row.add_child(choice)
		if center_single:
			_add_balanced_spacer(row, 1.0)
		elif center_two:
			_add_balanced_spacer(row, 0.5)


func _restore_standard_grid() -> void:
	_restore_choices_to_grid()
	_clear_balanced_rows()
	_balanced_rows_host.visible = false
	_grid.visible = true
	_refresh_columns_for_width()


func _restore_choices_to_grid() -> void:
	for choice in _choices:
		if not is_instance_valid(choice) or choice.get_parent() == _grid:
			continue
		if choice.get_parent() != null:
			choice.get_parent().remove_child(choice)
		_grid.add_child(choice)


func _clear_balanced_rows() -> void:
	for row_variant in _balanced_rows_host.get_children():
		_balanced_rows_host.remove_child(row_variant)
		row_variant.free()


func _add_balanced_spacer(row: HBoxContainer, ratio: float) -> void:
	var spacer := Control.new()
	spacer.set_meta("balanced_spacer", true)
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.size_flags_stretch_ratio = ratio
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)


func _balanced_last_row_centered(visible_count: int) -> bool:
	return visible_count == 1 or visible_count == 5


func _navigation_button(node_name: String, label_text: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = label_text
	button.custom_minimum_size = Vector2(132, 44)
	button.add_theme_font_size_override("font_size", 17)
	button.set_meta("progressive_navigation", true)
	return button
