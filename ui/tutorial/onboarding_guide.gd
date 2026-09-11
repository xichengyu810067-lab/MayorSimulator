class_name OnboardingGuide
extends Control

signal advanced(target_id: String, receipt: Dictionary)

const INPUT_MOUSE_LEFT := "mouse_left"
const INPUT_KEY := "key"
const HOLE_PADDING := 8.0

var _progress
var _target: Control
var _input_kind := ""
var _expected_keycode := KEY_NONE
var _receipt: Dictionary = {}
var _target_input_callable := Callable()
var _target_exit_callable := Callable()
var _generation := 0
var _masks: Array[ColorRect] = []
var _arrow: Label
var _guide: Label


func _init() -> void:
	name = "OnboardingGuide"
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_as_relative = false
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX - 1
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	set_process_input(true)


func open_for_target(
	progress,
	target: Control,
	input_kind: String,
	expected_keycode: Key,
	authority_id: String,
	entity_id: String,
	game_day: int,
	message: String = ""
) -> bool:
	invalidate_target()
	if progress == null or not progress.has_method("is_active") or not bool(progress.call("is_active")):
		return false
	if target == null or not is_instance_valid(target) or not target.is_inside_tree() or not target.visible:
		return false
	if input_kind not in [INPUT_MOUSE_LEFT, INPUT_KEY]:
		return false
	if input_kind == INPUT_KEY and expected_keycode == KEY_NONE:
		return false
	_progress = progress
	_target = target
	_input_kind = input_kind
	_expected_keycode = expected_keycode
	_receipt = {
		"kind": str(progress.call("current_target")),
		"authority_id": authority_id,
		"entity_id": entity_id,
		"game_day": game_day,
	}
	_generation += 1
	var binding_generation := _generation
	_target_input_callable = Callable(self, "_on_target_gui_input").bind(binding_generation)
	_target_exit_callable = Callable(self, "_on_target_tree_exiting").bind(binding_generation)
	_target.gui_input.connect(_target_input_callable)
	_target.tree_exiting.connect(_target_exit_callable, CONNECT_ONE_SHOT)
	_guide.text = message
	show()
	move_to_front()
	_layout_hole()
	return true


func invalidate_target() -> void:
	_generation += 1
	if is_instance_valid(_target):
		if _target_input_callable.is_valid() and _target.gui_input.is_connected(_target_input_callable):
			_target.gui_input.disconnect(_target_input_callable)
		if _target_exit_callable.is_valid() and _target.tree_exiting.is_connected(_target_exit_callable):
			_target.tree_exiting.disconnect(_target_exit_callable)
	_target = null
	_progress = null
	_input_kind = ""
	_expected_keycode = KEY_NONE
	_receipt.clear()
	_target_input_callable = Callable()
	_target_exit_callable = Callable()
	hide()


func is_open() -> bool:
	return visible and is_instance_valid(_target) and _progress != null


func target_control() -> Control:
	return _target if is_instance_valid(_target) else null


func set_dark_mode(enabled: bool) -> void:
	var mask_color := Color(0.005, 0.01, 0.02, 0.80) if enabled else Color(0.02, 0.04, 0.06, 0.68)
	for mask in _masks:
		mask.color = mask_color
	_guide.add_theme_color_override("font_color", Color.WHITE)
	_arrow.add_theme_color_override("font_color", Color(1.0, 0.76, 0.18))


func refresh_localization() -> void:
	# Text is supplied by the future domain adapter. Refreshing presentation must
	# never replace or retain a different target control.
	_layout_hole()


func _process(_delta: float) -> void:
	if visible:
		if not is_instance_valid(_target) or not _target.is_inside_tree():
			invalidate_target()
			return
		_layout_hole()


func _input(event: InputEvent) -> void:
	if not is_open() or not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if _input_kind == INPUT_KEY and focus_owner == _target and key_event.keycode == _expected_keycode:
		_advance_once()
	accept_event()
	get_viewport().set_input_as_handled()


func _on_target_gui_input(event: InputEvent, binding_generation: int) -> void:
	if binding_generation != _generation or not is_open() or _input_kind != INPUT_MOUSE_LEFT:
		return
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	_advance_once()
	accept_event()
	get_viewport().set_input_as_handled()


func _advance_once() -> void:
	if not is_open():
		return
	var progress = _progress
	var target_id := str(progress.call("current_target"))
	var receipt := _receipt.duplicate(true)
	if not bool(progress.call("record_current_target", target_id, receipt)):
		return
	invalidate_target()
	advanced.emit(target_id, receipt)


func _on_target_tree_exiting(binding_generation: int) -> void:
	if binding_generation == _generation:
		invalidate_target()


func _consume_mask_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		accept_event()
		get_viewport().set_input_as_handled()


func _build() -> void:
	for index in 4:
		var mask := ColorRect.new()
		mask.name = "OnboardingMask%d" % index
		mask.mouse_filter = Control.MOUSE_FILTER_STOP
		mask.gui_input.connect(_consume_mask_input)
		add_child(mask)
		_masks.append(mask)
	_arrow = Label.new()
	_arrow.name = "OnboardingArrow"
	_arrow.text = "➜"
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.add_theme_font_size_override("font_size", 42)
	add_child(_arrow)
	_guide = Label.new()
	_guide.name = "OnboardingMessage"
	_guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guide.add_theme_font_size_override("font_size", 20)
	_guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_guide.custom_minimum_size = Vector2(320, 64)
	add_child(_guide)
	set_dark_mode(false)


func _layout_hole() -> void:
	if not is_instance_valid(_target) or size.x <= 0.0 or size.y <= 0.0:
		return
	var target_rect := _target.get_global_rect().grow(HOLE_PADDING)
	var inverse := get_global_transform_with_canvas().affine_inverse()
	var hole := Rect2(inverse * target_rect.position, target_rect.size)
	hole = hole.intersection(Rect2(Vector2.ZERO, size))
	if hole.size.x <= 0.0 or hole.size.y <= 0.0:
		for mask in _masks:
			_set_rect(mask, Rect2(Vector2.ZERO, size))
		return
	_set_rect(_masks[0], Rect2(0.0, 0.0, size.x, hole.position.y))
	_set_rect(_masks[1], Rect2(0.0, hole.end.y, size.x, maxf(0.0, size.y - hole.end.y)))
	_set_rect(_masks[2], Rect2(0.0, hole.position.y, hole.position.x, hole.size.y))
	_set_rect(_masks[3], Rect2(hole.end.x, hole.position.y, maxf(0.0, size.x - hole.end.x), hole.size.y))
	_arrow.position = Vector2(maxf(8.0, hole.position.x - 52.0), hole.position.y + hole.size.y * 0.5 - 24.0)
	_guide.position = Vector2(clampf(hole.position.x, 12.0, maxf(12.0, size.x - 340.0)), minf(size.y - 76.0, hole.end.y + 10.0))


func _set_rect(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = Vector2(maxf(0.0, rect.size.x), maxf(0.0, rect.size.y))
