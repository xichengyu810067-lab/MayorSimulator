class_name OnboardingGuide
extends Control

signal advanced(target_id: String, receipt: Dictionary)
signal target_input_observed(target_id: String, input_kind: String)
signal defer_requested
signal result_review_confirmed

const INPUT_MOUSE_LEFT := "mouse_left"
const INPUT_KEY := "key"
const HOLE_PADDING := 8.0
const FAIRY_ATLAS_PATH := "res://assets/images/tutorial/cg_v1/xiaoli_expressions_atlas.png"
const FAIRY_ATLAS_COUNT := 4
const FAIRY_SIZE := Vector2(96.0, 96.0)

var _progress
var _target: Control
var _input_kind := ""
var _expected_keycode := KEY_NONE
var _receipt: Dictionary = {}
var _bound_target_id := ""
var _product_mode := false
var _waiting_mode := false
var _result_review_mode := false
var _target_input_callable := Callable()
var _target_exit_callable := Callable()
var _generation := 0
var _masks: Array[ColorRect] = []
var _card: PanelContainer
var _arrow: Label
var _guide: Label
var _fairy: TextureRect
var _defer_button: Button
var _result_review_button: Button


func _init() -> void:
	name = "OnboardingGuide"
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_as_relative = false
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX
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
	return _open_target(progress, target, input_kind, expected_keycode, authority_id, entity_id, game_day, message, false)


func open_product_target(
	progress,
	target: Control,
	input_kind: String,
	expected_keycode: Key = KEY_NONE,
	message: String = ""
) -> bool:
	return _open_target(progress, target, input_kind, expected_keycode, "", "", 0, message, true)


func show_waiting(progress, message: String) -> bool:
	if progress == null or not progress.has_method("is_active") or not bool(progress.call("is_active")):
		invalidate_target()
		return false
	if not _ensure_fairy_texture():
		invalidate_target()
		return false
	var target_id := str(progress.call("current_target"))
	if target_id.is_empty():
		invalidate_target()
		return false
	if is_waiting_mode() and _progress == progress and _bound_target_id == target_id:
		_guide.text = message
		_layout_waiting()
		return true
	invalidate_target()
	_progress = progress
	_bound_target_id = target_id
	_waiting_mode = true
	_guide.text = message
	_set_waiting_presentation()
	show()
	move_to_front()
	_layout_waiting()
	return true


func show_result_review(progress, message: String) -> bool:
	if progress == null or not progress.has_method("is_active") or not bool(progress.call("is_active")):
		invalidate_target()
		return false
	if not _ensure_fairy_texture():
		invalidate_target()
		return false
	var target_id := str(progress.call("current_target"))
	if target_id not in ["judicial", "oversight"]:
		invalidate_target()
		return false
	if is_result_review_mode() and _progress == progress and _bound_target_id == target_id:
		_guide.text = message
		_layout_waiting()
		return true
	invalidate_target()
	_progress = progress
	_bound_target_id = target_id
	_result_review_mode = true
	_guide.text = message
	_set_result_review_presentation()
	show()
	move_to_front()
	_layout_waiting()
	return true


func _open_target(
	progress,
	target: Control,
	input_kind: String,
	expected_keycode: Key,
	authority_id: String,
	entity_id: String,
	game_day: int,
	message: String,
	product_mode: bool
) -> bool:
	invalidate_target()
	if progress == null or not progress.has_method("is_active") or not bool(progress.call("is_active")):
		return false
	if target == null or not is_instance_valid(target) or not target.is_inside_tree() or not target.is_visible_in_tree():
		return false
	if target is BaseButton and (target as BaseButton).disabled:
		return false
	if input_kind not in [INPUT_MOUSE_LEFT, INPUT_KEY]:
		return false
	if input_kind == INPUT_KEY and expected_keycode == KEY_NONE:
		return false
	if not _ensure_fairy_texture():
		return false
	_progress = progress
	_target = target
	_input_kind = input_kind
	_expected_keycode = expected_keycode
	_bound_target_id = str(progress.call("current_target"))
	_product_mode = product_mode
	_waiting_mode = false
	_result_review_mode = false
	if not _product_mode:
		_receipt = {
			"kind": _bound_target_id,
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
	_set_target_presentation()
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
	_bound_target_id = ""
	_product_mode = false
	_waiting_mode = false
	_result_review_mode = false
	_receipt.clear()
	_target_input_callable = Callable()
	_target_exit_callable = Callable()
	_card.hide()
	_defer_button.hide()
	_result_review_button.hide()
	hide()


func is_open() -> bool:
	return (
		visible
		and is_instance_valid(_target)
		and _progress != null
		and str(_progress.call("current_target")) == _bound_target_id
	)


func is_product_mode() -> bool:
	return is_open() and _product_mode


func is_waiting_mode() -> bool:
	return (
		visible
		and _waiting_mode
		and _progress != null
		and bool(_progress.call("is_active"))
		and str(_progress.call("current_target")) == _bound_target_id
	)


func is_result_review_mode() -> bool:
	return (
		visible
		and _result_review_mode
		and _progress != null
		and bool(_progress.call("is_active"))
		and str(_progress.call("current_target")) == _bound_target_id
	)


func target_control() -> Control:
	return _target if is_instance_valid(_target) else null


func set_dark_mode(enabled: bool) -> void:
	var mask_color := Color(0.005, 0.01, 0.02, 0.80) if enabled else Color(0.02, 0.04, 0.06, 0.68)
	for mask in _masks:
		mask.color = mask_color
	_guide.add_theme_color_override("font_color", Color.WHITE)
	_arrow.add_theme_color_override("font_color", Color(1.0, 0.76, 0.18))
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.035, 0.09, 0.15, 0.96) if enabled else Color(0.055, 0.16, 0.25, 0.96)
	card_style.border_color = Color(0.20, 0.66, 0.90, 0.95)
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(10)
	_card.add_theme_stylebox_override("panel", card_style)
	var defer_style := StyleBoxFlat.new()
	defer_style.bg_color = Color(0.08, 0.43, 0.68)
	defer_style.border_color = Color(0.68, 0.90, 1.0)
	defer_style.set_border_width_all(2)
	defer_style.set_corner_radius_all(7)
	_defer_button.add_theme_stylebox_override("normal", defer_style)
	_defer_button.add_theme_color_override("font_color", Color.WHITE)
	_defer_button.add_theme_color_override("font_hover_color", Color.WHITE)


func refresh_localization() -> void:
	# Text is supplied by the future domain adapter. Refreshing presentation must
	# never replace or retain a different target control.
	_layout_hole()


func _process(_delta: float) -> void:
	if is_waiting_mode() or is_result_review_mode():
		_layout_waiting()
	elif visible:
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
		if _product_mode:
			target_input_observed.emit(_bound_target_id, _input_kind)
			return
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
	if _product_mode:
		target_input_observed.emit(_bound_target_id, _input_kind)
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


func _on_defer_pressed() -> void:
	if not is_open() and not is_waiting_mode() and not is_result_review_mode():
		return
	defer_requested.emit()


func _on_result_review_pressed() -> void:
	if not is_result_review_mode():
		return
	result_review_confirmed.emit()


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
	_card = PanelContainer.new()
	_card.name = "OnboardingGuideCard"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)
	_fairy = TextureRect.new()
	_fairy.name = "OnboardingFairy"
	_fairy.custom_minimum_size = FAIRY_SIZE
	_fairy.size = FAIRY_SIZE
	_fairy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fairy.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_fairy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fairy)
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
	_defer_button = Button.new()
	_defer_button.name = "OnboardingDeferButton"
	_defer_button.text = "延後教學"
	_defer_button.tooltip_text = "將目前教學延後 3 個遊戲天"
	_defer_button.custom_minimum_size = Vector2(132, 44)
	_defer_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_defer_button.pressed.connect(_on_defer_pressed)
	add_child(_defer_button)
	_defer_button.hide()
	_result_review_button = Button.new()
	_result_review_button.name = "OnboardingResultReviewButton"
	_result_review_button.text = "已閱讀結果，繼續"
	_result_review_button.tooltip_text = "確認已閱讀真實案件結果並繼續教學"
	_result_review_button.custom_minimum_size = Vector2(180, 44)
	_result_review_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_review_button.pressed.connect(_on_result_review_pressed)
	add_child(_result_review_button)
	_result_review_button.hide()
	set_dark_mode(false)


func _ensure_fairy_texture() -> bool:
	if _fairy.texture is AtlasTexture:
		return true
	if not ResourceLoader.exists(FAIRY_ATLAS_PATH):
		return false
	var resource := load(FAIRY_ATLAS_PATH)
	if not resource is Texture2D:
		return false
	var atlas := resource as Texture2D
	if atlas.get_width() <= 0 or atlas.get_height() <= 0 or atlas.get_width() % FAIRY_ATLAS_COUNT != 0:
		return false
	var portrait := AtlasTexture.new()
	portrait.atlas = atlas
	portrait.region = Rect2(
		float(atlas.get_width()) / float(FAIRY_ATLAS_COUNT),
		0.0,
		float(atlas.get_width()) / float(FAIRY_ATLAS_COUNT),
		float(atlas.get_height())
	)
	_fairy.texture = portrait
	return true


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
	var edge_margin := 8.0
	var companion_gap := 12.0
	var arrow_size := _arrow.get_combined_minimum_size()
	_arrow.position = Vector2(
		clampf(hole.position.x - arrow_size.x - companion_gap, edge_margin, maxf(edge_margin, size.x - arrow_size.x - edge_margin)),
		clampf(hole.position.y + hole.size.y * 0.5 - arrow_size.y * 0.5, edge_margin, maxf(edge_margin, size.y - arrow_size.y - edge_margin))
	)
	var guide_size := _guide.get_combined_minimum_size()
	_guide.size = guide_size
	var defer_size := _defer_button.get_combined_minimum_size()
	_defer_button.size = defer_size
	_fairy.size = FAIRY_SIZE
	var companion_height := maxf(guide_size.y + 8.0 + defer_size.y, FAIRY_SIZE.y)
	var below_y := hole.end.y + companion_gap
	var above_y := hole.position.y - companion_gap - companion_height
	var companion_y := below_y if below_y + companion_height <= size.y - edge_margin else above_y
	companion_y = clampf(companion_y, edge_margin, maxf(edge_margin, size.y - companion_height - edge_margin))
	var guide_x := clampf(
		hole.position.x,
		edge_margin + FAIRY_SIZE.x + companion_gap,
		maxf(edge_margin + FAIRY_SIZE.x + companion_gap, size.x - guide_size.x - edge_margin)
	)
	_guide.position = Vector2(guide_x, companion_y + maxf(0.0, (companion_height - guide_size.y) * 0.5))
	_fairy.position = Vector2(guide_x - FAIRY_SIZE.x - companion_gap, companion_y)
	_defer_button.position = Vector2(
		guide_x,
		minf(size.y - defer_size.y - edge_margin, _guide.position.y + guide_size.y + 8.0)
	)
	_layout_card(false)


func _layout_waiting() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var edge_margin := 12.0
	var companion_gap := 12.0
	var guide_size := _guide.get_combined_minimum_size()
	var defer_size := _defer_button.get_combined_minimum_size()
	var review_size := _result_review_button.get_combined_minimum_size()
	_guide.size = guide_size
	_defer_button.size = defer_size
	_result_review_button.size = review_size
	_fairy.size = FAIRY_SIZE
	var actions_width := defer_size.x
	if is_result_review_mode():
		actions_width += 8.0 + review_size.x
	var total_width := FAIRY_SIZE.x + companion_gap + maxf(guide_size.x, actions_width)
	var total_height := maxf(FAIRY_SIZE.y, guide_size.y + 8.0 + maxf(defer_size.y, review_size.y))
	var left := maxf(edge_margin, size.x - total_width - edge_margin)
	var top := clampf(96.0, edge_margin, maxf(edge_margin, size.y - total_height - edge_margin))
	_fairy.position = Vector2(left, top)
	_guide.position = Vector2(left + FAIRY_SIZE.x + companion_gap, top)
	_defer_button.position = Vector2(_guide.position.x, _guide.position.y + guide_size.y + 8.0)
	_result_review_button.position = Vector2(
		_defer_button.position.x + defer_size.x + 8.0,
		_defer_button.position.y
	)
	_layout_card(is_result_review_mode())


func _set_target_presentation() -> void:
	for mask in _masks:
		mask.show()
	_arrow.show()
	_card.show()
	_defer_button.show()
	_result_review_button.hide()


func _set_waiting_presentation() -> void:
	for mask in _masks:
		mask.hide()
	_arrow.hide()
	_card.show()
	_defer_button.show()
	_result_review_button.hide()


func _set_result_review_presentation() -> void:
	for mask in _masks:
		mask.hide()
	_arrow.hide()
	_card.show()
	_defer_button.show()
	_result_review_button.show()


func _layout_card(include_review: bool) -> void:
	var bounds := Rect2(_guide.position, _guide.size)
	bounds = bounds.merge(Rect2(_defer_button.position, _defer_button.size))
	if include_review:
		bounds = bounds.merge(Rect2(_result_review_button.position, _result_review_button.size))
	var padding := Vector2(12.0, 10.0)
	_card.position = bounds.position - padding
	_card.size = bounds.size + padding * 2.0


func _set_rect(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = Vector2(maxf(0.0, rect.size.x), maxf(0.0, rect.size.y))
