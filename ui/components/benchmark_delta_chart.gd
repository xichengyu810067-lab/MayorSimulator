class_name BenchmarkDeltaChart
extends VBoxContainer

const DEFAULT_MINIMUM_SIZE := Vector2(0, 124)

var current_label: Label
var difference_label: Label
var safety_warning_label: Label
var minimum_label: Label
var baseline_label: Label
var maximum_label: Label
var plot_area: Control

var _minimum_value := 0.0
var _maximum_value := 100.0
var _baseline_value := 60.0
var _safety_value := 60.0
var _target_value := 60.0
var _display_value := 60.0
var _good_above := true
var _safety_enabled := true
var _dark_mode := false
var _animation_duration := 0.82
var _animation: Tween
var _pulse_phase := 0.0


func _init() -> void:
	name = "BenchmarkDeltaChart"
	custom_minimum_size = DEFAULT_MINIMUM_SIZE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 3)
	_build_content()
	# The custom canvas is owned by this parent but its geometry comes from the
	# child plot control. Hidden TabContainer pages can finish layout only after
	# becoming visible, so both visibility and either resize must invalidate the
	# parent's draw list.
	resized.connect(_request_redraw_after_layout_change)
	visibility_changed.connect(_request_redraw_after_layout_change)
	plot_area.resized.connect(_request_redraw_after_layout_change)
	set_process(false)


## Display-ready strings are supplied by the owner so this component can be
## reused by every locale without owning localization state.
func set_chart(data: Dictionary, animate: bool = true) -> void:
	_minimum_value = float(data.get("minimum", 0.0))
	_maximum_value = float(data.get("maximum", 100.0))
	if _maximum_value <= _minimum_value:
		_maximum_value = _minimum_value + 1.0
	_baseline_value = clampf(float(data.get("baseline", 60.0)), _minimum_value, _maximum_value)
	_safety_value = clampf(float(data.get("safety", _baseline_value)), _minimum_value, _maximum_value)
	_target_value = clampf(float(data.get("current", _baseline_value)), _minimum_value, _maximum_value)
	_good_above = bool(data.get("good_above", true))
	_safety_enabled = bool(data.get("safety_enabled", true))
	_animation_duration = maxf(0.1, float(data.get("duration", 0.82)))
	current_label.text = str(data.get("current_text", _formatted_number(_target_value)))
	difference_label.text = str(data.get("difference_text", _fallback_difference_text()))
	if difference_label.text.strip_edges().is_empty():
		difference_label.text = _fallback_difference_text()
	difference_label.tooltip_text = difference_label.text
	var safety_warning_text := str(data.get("safety_warning_text", ""))
	safety_warning_label.text = safety_warning_text
	safety_warning_label.visible = _safety_enabled and not _is_safe(_target_value) and not safety_warning_text.is_empty()
	safety_warning_label.tooltip_text = safety_warning_text
	minimum_label.text = str(data.get("minimum_text", _formatted_number(_minimum_value)))
	baseline_label.text = str(data.get("baseline_text", "安全線 %s" % _formatted_number(_baseline_value)))
	maximum_label.text = str(data.get("maximum_text", _formatted_number(_maximum_value)))
	tooltip_text = str(data.get("tooltip", "%s｜%s" % [current_label.text, difference_label.text]))
	set_meta("minimum_value", _minimum_value)
	set_meta("maximum_value", _maximum_value)
	set_meta("baseline_value", _baseline_value)
	set_meta("safety_value", _safety_value)
	set_meta("target_value", _target_value)
	set_meta("difference", _target_value - _baseline_value)
	set_meta("good_above", _good_above)
	set_meta("safety_warning_active", _safety_enabled and not _is_safe(_target_value))
	_apply_palette()
	if animate and is_inside_tree():
		restart_animation()
	else:
		_stop_animation()
		_display_value = _target_value
		queue_redraw()


func restart_animation() -> void:
	_stop_animation()
	_display_value = _baseline_value
	set_meta("animation_active", true)
	queue_redraw()
	if not is_inside_tree():
		_display_value = _target_value
		set_meta("animation_active", false)
		queue_redraw()
		return
	_animation = create_tween()
	_animation.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_animation.tween_method(_set_display_value, _baseline_value, _target_value, _animation_duration)
	_animation.finished.connect(func() -> void:
		set_meta("animation_active", false)
		set_process(not _is_safe(_target_value))
	)


func set_dark_mode(enabled: bool) -> void:
	_dark_mode = enabled
	_apply_palette()
	queue_redraw()


func target_value() -> float:
	return _target_value


func displayed_value() -> float:
	return _display_value


func baseline_value() -> float:
	return _baseline_value


func difference_value() -> float:
	return _target_value - _baseline_value


func safety_value() -> float:
	return _safety_value


func has_safety_warning() -> bool:
	return _safety_enabled and not _is_safe(_target_value)


func _build_content() -> void:
	var summary := VBoxContainer.new()
	summary.name = "BenchmarkSummary"
	summary.add_theme_constant_override("separation", 8)
	add_child(summary)

	current_label = Label.new()
	current_label.name = "BenchmarkCurrent"
	current_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	current_label.add_theme_font_size_override("font_size", 18)
	current_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	summary.add_child(current_label)

	difference_label = Label.new()
	difference_label.name = "BenchmarkDifference"
	difference_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	difference_label.add_theme_font_size_override("font_size", 16)
	difference_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	difference_label.tooltip_text = difference_label.text
	summary.add_child(difference_label)

	safety_warning_label = Label.new()
	safety_warning_label.name = "BenchmarkSafetyWarning"
	safety_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	safety_warning_label.add_theme_font_size_override("font_size", 14)
	safety_warning_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	safety_warning_label.visible = false
	summary.add_child(safety_warning_label)

	plot_area = Control.new()
	plot_area.name = "BenchmarkPlot"
	plot_area.custom_minimum_size = Vector2(0, 50)
	plot_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plot_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plot_area)

	var legend := HBoxContainer.new()
	legend.name = "BenchmarkLegend"
	legend.add_theme_constant_override("separation", 8)
	add_child(legend)
	minimum_label = _legend_label("BenchmarkMinimum", HORIZONTAL_ALIGNMENT_LEFT)
	baseline_label = _legend_label("BenchmarkBaseline", HORIZONTAL_ALIGNMENT_CENTER)
	baseline_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	maximum_label = _legend_label("BenchmarkMaximum", HORIZONTAL_ALIGNMENT_RIGHT)
	legend.add_child(minimum_label)
	legend.add_child(baseline_label)
	legend.add_child(maximum_label)


func _request_redraw_after_layout_change() -> void:
	queue_redraw()


func _legend_label(label_name: String, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.name = label_name
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", 16)
	return label


func _draw() -> void:
	if plot_area == null or plot_area.size.x <= 1.0:
		return
	var plot_rect := Rect2(plot_area.position + Vector2(3, 10), Vector2(maxf(1.0, plot_area.size.x - 6.0), 28))
	var baseline_x := _value_x(_baseline_value, plot_rect)
	var safety_x := _value_x(_safety_value, plot_rect)
	var current_x := _value_x(_display_value, plot_rect)
	var unsafe_color := Color("71342e") if _dark_mode else Color("f5c9c0")
	var safe_color := Color("205a4b") if _dark_mode else Color("bce6d4")
	var track_color := Color("2b3e49") if _dark_mode else Color("d8e1e5")
	var baseline_color := Color("ffd166") if _dark_mode else Color("9a6500")
	var safety_color := Color("ff8f7b") if _dark_mode else Color("b83228")
	var safe_side := Rect2(Vector2(safety_x, plot_rect.position.y), Vector2(plot_rect.end.x - safety_x, plot_rect.size.y))
	var unsafe_side := Rect2(plot_rect.position, Vector2(safety_x - plot_rect.position.x, plot_rect.size.y))
	if not _good_above:
		var swapped := safe_side
		safe_side = unsafe_side
		unsafe_side = swapped
	draw_rect(plot_rect, track_color, true)
	draw_rect(unsafe_side, unsafe_color, true)
	draw_rect(safe_side, safe_color, true)
	for fraction in [0.25, 0.5, 0.75]:
		var tick_x := plot_rect.position.x + plot_rect.size.x * float(fraction)
		draw_line(Vector2(tick_x, plot_rect.position.y + 3), Vector2(tick_x, plot_rect.end.y - 3), Color(1, 1, 1, 0.28), 1.0)
	if _safety_enabled:
		draw_line(Vector2(safety_x, plot_rect.position.y - 5), Vector2(safety_x, plot_rect.end.y + 5), safety_color, 2.0)
	draw_line(Vector2(baseline_x, plot_rect.position.y - 7), Vector2(baseline_x, plot_rect.end.y + 7), baseline_color, 3.0)
	var result_color := Color("4fd1a1") if _dark_mode else Color("087f5b")
	if not _is_safe(_display_value):
		result_color = Color("ff8f7b") if _dark_mode else Color("c83f2b")
	var segment_start := minf(baseline_x, current_x)
	var segment_width := maxf(3.0, absf(current_x - baseline_x))
	var segment_rect := Rect2(Vector2(segment_start, plot_rect.position.y + 8), Vector2(segment_width, 12))
	draw_rect(segment_rect, result_color, true)
	var pulse := 1.0 + (sin(_pulse_phase) + 1.0) * 1.5 if not _is_safe(_display_value) else 1.0
	draw_circle(Vector2(current_x, plot_rect.get_center().y), 9.0 + pulse, Color(result_color, 0.18))
	draw_circle(Vector2(current_x, plot_rect.get_center().y), 7.0, result_color)
	draw_arc(Vector2(current_x, plot_rect.get_center().y), 7.0, 0.0, TAU, 24, Color.WHITE, 2.0)


func _process(delta: float) -> void:
	_pulse_phase = fmod(_pulse_phase + delta * 4.0, TAU)
	queue_redraw()


func _value_x(value: float, rect: Rect2) -> float:
	return rect.position.x + inverse_lerp(_minimum_value, _maximum_value, clampf(value, _minimum_value, _maximum_value)) * rect.size.x


func _is_safe(value: float) -> bool:
	if not _safety_enabled:
		return true
	return value >= _safety_value if _good_above else value <= _safety_value


func _set_display_value(value: float) -> void:
	_display_value = value
	queue_redraw()


func _stop_animation() -> void:
	if _animation != null and _animation.is_valid():
		_animation.kill()
	_animation = null
	set_meta("animation_active", false)
	set_process(false)


func _apply_palette() -> void:
	if current_label == null:
		return
	var text_color := Color("f2f5f7") if _dark_mode else Color("14202a")
	var muted_color := Color("b7c7d0") if _dark_mode else Color("53616a")
	var difference_color := Color("8be0be") if _dark_mode else Color("0b6b4e")
	if not _is_safe(_target_value):
		difference_color = Color("ffad9f") if _dark_mode else Color("a52d20")
	current_label.add_theme_color_override("font_color", text_color)
	difference_label.add_theme_color_override("font_color", difference_color)
	safety_warning_label.add_theme_color_override("font_color", Color("ffad9f") if _dark_mode else Color("a52d20"))
	minimum_label.add_theme_color_override("font_color", muted_color)
	maximum_label.add_theme_color_override("font_color", muted_color)
	baseline_label.add_theme_color_override("font_color", Color("ffd166") if _dark_mode else Color("805300"))


func _formatted_number(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value


func _fallback_difference_text() -> String:
	var difference := _target_value - _baseline_value
	if is_zero_approx(difference):
		return "與比較基準相同"
	return "較比較基準 %+.1f 個百分點" % difference
