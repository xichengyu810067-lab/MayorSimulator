extends SceneTree

const WeatherVisualLayerScript = preload("res://ui/effects/weather_visual_layer.gd")

const STEP_SECONDS := 0.1

var _failed := false
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var layer = WeatherVisualLayerScript.new()
	root.add_child(layer)
	await process_frame
	# Keep all time-sensitive assertions deterministic. The test advances the
	# visual state explicitly instead of depending on the runner's frame rate.
	layer.set_process(false)

	_validate_weather_schedule(layer)
	_validate_input_contract(layer)
	_validate_layering_contract(layer)
	_validate_true_crossfade(layer)
	_validate_wetness_ramp(layer)
	_validate_motion_quality_counts(layer)

	layer.queue_free()
	if _failed:
		quit(1)
	else:
		print("Weather visual layer test passed. Checks=%d Distribution=60/20/20 RainCounts=72+30/36+15/0+0" % _checks)
		quit(0)


func _validate_weather_schedule(layer) -> void:
	var counts := {"sunny": 0, "cloudy": 0, "rain": 0}
	for day in range(100):
		var weather := str(layer.weather_for_day(day))
		_check(counts.has(weather), "day %d returned an unknown weather state: %s" % [day, weather])
		if counts.has(weather):
			counts[weather] = int(counts[weather]) + 1
	_check(int(counts["sunny"]) == 60, "100-day schedule must contain exactly 60 sunny days: %s" % counts)
	_check(int(counts["cloudy"]) == 20, "100-day schedule must contain exactly 20 cloudy days: %s" % counts)
	_check(int(counts["rain"]) == 20, "100-day schedule must contain exactly 20 rain days: %s" % counts)

	var first_ten: Array[String] = []
	var second_ten: Array[String] = []
	for day in range(10):
		first_ten.append(str(layer.weather_for_day(day)))
		second_ten.append(str(layer.weather_for_day(day + 10)))
	_check(first_ten != second_ten, "weather still repeats the complete legacy ten-day sequence: %s" % [first_ten])


func _validate_input_contract(layer) -> void:
	var original_weather := str(layer.current_weather)
	_check(not layer.set_weather("hail"), "set_weather accepted an unsupported state")
	_check(str(layer.current_weather) == original_weather, "invalid weather changed the active state")
	_check(not layer.set_preview_weather("fog"), "set_preview_weather accepted an unsupported state")
	_check(str(layer.current_weather) == original_weather, "invalid preview changed the active state")
	_check(not layer.set_motion_quality("cinematic"), "set_motion_quality accepted an unsupported quality")
	_check(str(layer.motion_quality) == "full", "invalid quality changed the active quality")


func _validate_layering_contract(layer) -> void:
	_check(layer.mouse_filter == Control.MOUSE_FILTER_IGNORE, "weather layer intercepts pointer input")
	_check(layer.focus_mode == Control.FOCUS_NONE, "weather layer can steal keyboard focus")
	_check(layer.z_index < 2000, "weather layer is not below the NPC dialogue plane: z=%d" % layer.z_index)


func _validate_true_crossfade(layer) -> void:
	_check(layer.set_weather("sunny", true), "could not reset crossfade source to sunny")
	_check(layer.set_weather("cloudy", false), "could not begin sunny-to-cloudy crossfade")
	var initial: Dictionary = layer.visual_debug_state()
	_check(str(initial["previous"]) == "sunny", "crossfade did not retain the source weather")
	_check(str(initial["current"]) == "cloudy", "crossfade did not retain the destination weather")
	_check(is_zero_approx(float(initial["transition"])), "crossfade did not start at zero")

	_advance(layer, 13)
	var midpoint: Dictionary = layer.visual_debug_state()
	var midpoint_progress := float(midpoint["transition"])
	_check(midpoint_progress > 0.45 and midpoint_progress < 0.55, "crossfade midpoint is not gradual: %.4f" % midpoint_progress)
	var material := layer.get("_atmosphere_material") as ShaderMaterial
	_check(material != null, "crossfade atmosphere material is missing")
	if material != null:
		_check(is_equal_approx(float(material.get_shader_parameter("from_mode")), 0.0), "shader does not retain the sunny source profile")
		_check(is_equal_approx(float(material.get_shader_parameter("to_mode")), 1.0), "shader does not retain the cloudy destination profile")
		var shader_blend := float(material.get_shader_parameter("transition_blend"))
		_check(shader_blend > 0.45 and shader_blend < 0.55, "shader crossfade blend is not at the tested midpoint: %.4f" % shader_blend)

	_advance(layer, 13)
	var complete: Dictionary = layer.visual_debug_state()
	_check(is_equal_approx(float(complete["transition"]), 1.0), "crossfade did not reach completion after 2.6 seconds")


func _validate_wetness_ramp(layer) -> void:
	_check(layer.set_weather("rain", true), "could not enter rain for wetness validation")
	_advance(layer, 50)
	var half_wet := float(layer.visual_debug_state()["wetness"])
	_check(half_wet > 0.45 and half_wet < 0.55, "rain wetness did not rise gradually over five seconds: %.4f" % half_wet)
	_advance(layer, 50)
	var fully_wet := float(layer.visual_debug_state()["wetness"])
	_check(is_equal_approx(fully_wet, 1.0), "rain wetness did not reach one after ten seconds: %.4f" % fully_wet)

	_check(layer.set_weather("sunny", true), "could not leave rain for drying validation")
	_advance(layer, 130)
	var half_dry := float(layer.visual_debug_state()["wetness"])
	_check(half_dry > 0.45 and half_dry < 0.55, "ground did not dry gradually over thirteen seconds: %.4f" % half_dry)
	_advance(layer, 130)
	var dry := float(layer.visual_debug_state()["wetness"])
	_check(is_zero_approx(dry), "ground wetness did not return to zero after twenty-six seconds: %.4f" % dry)


func _validate_motion_quality_counts(layer) -> void:
	_check(layer.set_weather("rain", true), "could not enter rain for density validation")
	_check(layer.set_motion_quality("full"), "full motion quality was rejected")
	var full: Dictionary = layer.visual_debug_state()
	_check(int(full["far_rain_count"]) == 72 and int(full["near_rain_count"]) == 30, "full rain density is not 72 far + 30 near: %s" % full)

	_check(layer.set_motion_quality("reduced"), "reduced motion quality was rejected")
	var reduced: Dictionary = layer.visual_debug_state()
	_check(int(reduced["far_rain_count"]) == 36 and int(reduced["near_rain_count"]) == 15, "reduced rain density is not half of full: %s" % reduced)

	_check(layer.set_motion_quality("still"), "still motion quality was rejected")
	var still: Dictionary = layer.visual_debug_state()
	_check(int(still["far_rain_count"]) == 0 and int(still["near_rain_count"]) == 0, "still mode did not remove animated rain streaks: %s" % still)


func _advance(layer, steps: int) -> void:
	for _step in range(steps):
		layer.call("_process", STEP_SECONDS)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error(message)
