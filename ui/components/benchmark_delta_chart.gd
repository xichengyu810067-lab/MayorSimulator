class_name BenchmarkDeltaChart
extends VBoxContainer

const DEFAULT_MINIMUM_SIZE := Vector2(0, 138)

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
var _animation_elapsed := 0.0
var _pulse_phase := 0.0
var _warning_severity := ""


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
	_warning_severity = str(data.get("safety_warning_severity", "caution" if not _is_safe(_target_value) else ""))
	if _warning_severity not in ["caution", "critical"]:
		_warning_severity = ""
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
	set_meta("safety_warning_severity", _warning_severity)
	set_meta("chart_render_mode", "donut")
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
	_animation_elapsed = 0.0
	set_meta("animation_active", true)
	queue_redraw()
	if not is_inside_tree():
		_display_value = _target_value
		set_meta("animation_active", false)
		queue_redraw()
		return
	set_process(true)


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
	safety_warning_label.custom_minimum_size = Vector2(0, 18)
	safety_warning_label.add_theme_font_size_override("font_size", 14)
	safety_warning_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	safety_warning_label.visible = false
	summary.add_child(safety_warning_label)

	plot_area = Control.new()
	plot_area.name = "BenchmarkPlot"
	plot_area.custom_minimum_size = Vector2(0, 62)
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
	var plot_rect := Rect2(plot_area.position + Vector2(3, 2), Vector2(maxf(1.0, plot_area.size.x - 6.0), maxf(1.0, plot_area.size.y - 4.0)))
	var center := plot_rect.get_center()
	var radius := maxf(10.0, minf(plot_rect.size.x, plot_rect.size.y) * 0.5 - 13.0)
	var start_angle := -PI * 0.5
	var baseline_angle := _value_angle(_baseline_value, start_angle)
	var safety_angle := _value_angle(_safety_value, start_angle)
	var current_angle := _value_angle(_display_value, start_angle)
	var track_color := Color("2b3e49") if _dark_mode else Color("d8e1e5")
	var baseline_color := Color("ffd166") if _dark_mode else Color("9a6500")
	var safety_color := Color("ff8f7b") if _dark_mode else Color("b83228")
	draw_arc(center, radius, start_angle, start_angle + TAU, 56, track_color, 10.0, true)
	var result_color := Color("4fd1a1") if _dark_mode else Color("087f5b")
	if not _is_safe(_display_value):
		result_color = Color("ff8f7b") if _dark_mode else Color("c83f2b")
	draw_arc(center, radius, start_angle, current_angle, 56, result_color, 10.0, true)
	# The outer gold arc/marker is the comparison baseline; the red tick remains
	# an independent safety guide even when both values happen to coincide.
	draw_arc(center, radius + 8.0, start_angle, baseline_angle, 56, baseline_color, 2.0, true)
	draw_line(_polar_point(center, radius - 7.0, baseline_angle), _polar_point(center, radius + 10.0, baseline_angle), baseline_color, 3.0, true)
	if _safety_enabled:
		draw_arc(center, radius + 14.0, safety_angle - 0.06, safety_angle + 0.06, 8, safety_color, 3.0, true)
		draw_line(_polar_point(center, radius + 10.0, safety_angle), _polar_point(center, radius + 18.0, safety_angle), safety_color, 2.0, true)
	var pulse := 1.0 + (sin(_pulse_phase) + 1.0) * 1.5 if not _is_safe(_display_value) else 1.0
	var current_marker := _polar_point(center, radius, current_angle)
	draw_circle(current_marker, 7.0 + pulse, Color(result_color, 0.18))
	draw_circle(current_marker, 5.0, result_color)
	draw_arc(current_marker, 5.0, 0.0, TAU, 16, Color.WHITE, 1.5, true)


func _process(delta: float) -> void:
	if bool(get_meta("animation_active", false)):
		_animation_elapsed = minf(_animation_elapsed + delta, _animation_duration)
		var progress := clampf(_animation_elapsed / _animation_duration, 0.0, 1.0)
		var eased_progress := 1.0 - pow(1.0 - progress, 3.0)
		_set_display_value(lerpf(_baseline_value, _target_value, eased_progress))
		if is_equal_approx(progress, 1.0):
			_set_display_value(_target_value)
			set_meta("animation_active", false)
			set_process(not _is_safe(_target_value))
	_pulse_phase = fmod(_pulse_phase + delta * 4.0, TAU)
	queue_redraw()


func _value_angle(value: float, start_angle: float) -> float:
	return start_angle + TAU * inverse_lerp(_minimum_value, _maximum_value, clampf(value, _minimum_value, _maximum_value))


func _polar_point(center: Vector2, radius: float, angle: float) -> Vector2:
	return center + Vector2(cos(angle), sin(angle)) * radius


func _is_safe(value: float) -> bool:
	if not _safety_enabled:
		return true
	return value >= _safety_value if _good_above else value <= _safety_value


func _set_display_value(value: float) -> void:
	_display_value = value
	queue_redraw()


func _stop_animation() -> void:
	_animation_elapsed = 0.0
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
	var warning_color := Color("ffd166") if _dark_mode else Color("9a6500")
	if _warning_severity == "critical":
		warning_color = Color("ff8f7b") if _dark_mode else Color("a52d20")
	safety_warning_label.add_theme_color_override("font_color", warning_color)
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
