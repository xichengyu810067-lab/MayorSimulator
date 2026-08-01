class_name WeatherVisualLayer
extends Control

const WEATHER_STATES := ["sunny", "cloudy", "rain"]
const MOTION_QUALITIES := ["full", "reduced", "still"]
const TRANSITION_SECONDS := 2.6
const DRAW_INTERVAL_SECONDS := 1.0 / 30.0
const FAR_RAIN_FULL := 72
const NEAR_RAIN_FULL := 30
const ATMOSPHERE_SHADER := """
shader_type canvas_item;

uniform float elapsed = 0.0;
uniform float from_mode = 0.0;
uniform float to_mode = 0.0;
uniform float transition_blend = 1.0;
uniform float wetness = 0.0;
uniform float variant_seed = 0.0;

vec4 profile(float mode, vec2 uv) {
	// Broad diagonal veils avoid the conspicuous axis-aligned cells produced by
	// low-frequency value noise at large resolutions.  Local cloud detail is
	// drawn below as softly overlapping world-space shapes, so this full-screen
	// pass only needs a cheap, seamless atmospheric drift.
	float phase = (uv.x * 1.28 + uv.y * 0.37 + elapsed * 0.006 + variant_seed) * 6.2831853;
	float veil = 0.5 + 0.5 * sin(phase);
	float horizon = 1.0 - smoothstep(0.0, 1.0, uv.y);
	if (mode < 0.5) {
		float warmth = 0.012 + sin(elapsed * 0.38 + variant_seed * 6.28) * 0.003;
		return vec4(vec3(1.0, 0.83, 0.48), warmth + horizon * 0.004);
	}
	if (mode < 1.5) {
		return vec4(vec3(0.075, 0.14, 0.20), 0.060 + veil * 0.018 + horizon * 0.008);
	}
	return vec4(vec3(0.045, 0.12, 0.19), 0.096 + veil * 0.022 + horizon * 0.010);
}

void fragment() {
	float blend = smoothstep(0.0, 1.0, transition_blend);
	vec4 atmosphere = mix(profile(from_mode, UV), profile(to_mode, UV), blend);
	float ground = smoothstep(0.36, 1.0, UV.y) * wetness;
	atmosphere.rgb = mix(atmosphere.rgb, vec3(0.045, 0.105, 0.14), ground * 0.32);
	atmosphere.a += ground * 0.040;
	COLOR = atmosphere;
}
"""

var current_weather := "sunny"
var previous_weather := "sunny"
var motion_quality := "full"
var _elapsed_seconds := 0.0
var _draw_accumulator := 0.0
var _transition_progress := 1.0
var _wetness := 0.0
var _game_day := -1
var _variant_seed := 0.0
var _preview_weather := ""
var _atmosphere_material: ShaderMaterial


func _init() -> void:
	name = "WeatherVisualLayer"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	# Weather belongs to the world. Keeping it below the NPC dialogue (z=2000)
	# prevents rain and atmosphere tint from reducing dialogue readability.
	z_index = 1900


func _ready() -> void:
	var atmosphere := ColorRect.new()
	atmosphere.name = "AtmosphereCrossfade"
	atmosphere.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	atmosphere.mouse_filter = Control.MOUSE_FILTER_IGNORE
	atmosphere.show_behind_parent = true
	var shader := Shader.new()
	shader.code = ATMOSPHERE_SHADER
	_atmosphere_material = ShaderMaterial.new()
	_atmosphere_material.shader = shader
	atmosphere.material = _atmosphere_material
	add_child(atmosphere)
	_update_atmosphere_material()
	queue_redraw()


func _process(delta: float) -> void:
	var safe_delta := minf(maxf(delta, 0.0), 0.1)
	if motion_quality != "still":
		_elapsed_seconds += safe_delta
	if _transition_progress < 1.0:
		_transition_progress = minf(1.0, _transition_progress + safe_delta / TRANSITION_SECONDS)
	var wetness_target := 1.0 if current_weather == "rain" else 0.0
	var wetness_seconds := 10.0 if wetness_target > _wetness else 26.0
	_wetness = move_toward(_wetness, wetness_target, safe_delta / wetness_seconds)
	_draw_accumulator += safe_delta
	var needs_motion_frame := motion_quality != "still" and _draw_accumulator >= DRAW_INTERVAL_SECONDS
	var needs_transition_frame := _transition_progress < 1.0 or not is_equal_approx(_wetness, wetness_target)
	if not needs_motion_frame and not needs_transition_frame:
		return
	_draw_accumulator = 0.0
	_update_atmosphere_material()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func set_game_day(game_day: int) -> void:
	if not _preview_weather.is_empty() or game_day == _game_day:
		return
	_game_day = game_day
	_variant_seed = float(posmod(maxi(0, game_day) * 37 + 11, 997)) / 997.0
	set_weather(weather_for_day(game_day))


func weather_for_day(game_day: int) -> String:
	# Multiplication by 73 permutes 0..99, retaining an exact 60/20/20 split
	# over 100 days without the old visibly repeating ten-day cycle.
	var roll := posmod(maxi(0, game_day) * 73, 100)
	if roll < 60:
		return "sunny"
	if roll < 80:
		return "cloudy"
	return "rain"


func set_weather(weather: String, immediate: bool = false) -> bool:
	if weather not in WEATHER_STATES:
		return false
	if weather == current_weather:
		if immediate:
			previous_weather = weather
			_transition_progress = 1.0
			_update_atmosphere_material()
			queue_redraw()
		return true
	previous_weather = current_weather
	current_weather = weather
	_transition_progress = 1.0 if immediate else 0.0
	_update_atmosphere_material()
	queue_redraw()
	return true


func set_preview_weather(weather: String) -> bool:
	if weather not in WEATHER_STATES:
		return false
	_preview_weather = weather
	_variant_seed = float(WEATHER_STATES.find(weather) + 1) * 0.217
	return set_weather(weather, true)


func clear_preview_weather() -> void:
	_preview_weather = ""
	_game_day = -1


func set_motion_quality(quality: String) -> bool:
	if quality not in MOTION_QUALITIES:
		return false
	motion_quality = quality
	_update_atmosphere_material()
	queue_redraw()
	return true


func visual_debug_state() -> Dictionary:
	return {
		"current": current_weather,
		"previous": previous_weather,
		"transition": _transition_progress,
		"wetness": _wetness,
		"variant_seed": _variant_seed,
		"motion_quality": motion_quality,
		"far_rain_count": _far_rain_count(),
		"near_rain_count": _near_rain_count(),
		"z_index": z_index,
	}


func _draw() -> void:
	var blend := smoothstep(0.0, 1.0, _transition_progress)
	_draw_ground_reactions(_wetness)
	if previous_weather != current_weather and blend < 1.0:
		_draw_weather_profile(previous_weather, 1.0 - blend)
	_draw_weather_profile(current_weather, blend if previous_weather != current_weather else 1.0)


func _draw_weather_profile(weather: String, strength: float) -> void:
	if strength <= 0.002:
		return
	match weather:
		"sunny":
			_draw_sunbeams(strength)
			_draw_cloud_shadows(0.28 * strength)
			_draw_wind_accents(10, Color(1.0, 0.88, 0.50, 0.34 * strength), 22.0)
		"cloudy":
			_draw_cloud_shadows(0.82 * strength)
			_draw_wind_accents(14, Color(0.79, 0.89, 0.78, 0.28 * strength), 34.0)
		"rain":
			_draw_cloud_shadows(strength)
			_draw_rain_layer(_far_rain_count(), false, strength)
			_draw_wind_accents(8, Color(0.67, 0.82, 0.78, 0.20 * strength), 42.0)
			_draw_rain_layer(_near_rain_count(), true, strength)


func _draw_sunbeams(strength: float) -> void:
	if motion_quality == "still":
		return
	var sway := sin(_elapsed_seconds * 0.08 + _variant_seed * TAU) * size.x * 0.035
	for index in 2:
		var origin_x := size.x * (0.12 + float(index) * 0.46) + sway
		var width := size.x * (0.18 + float(index) * 0.035)
		var points := PackedVector2Array([
			Vector2(origin_x, -24.0),
			Vector2(origin_x + width * 0.34, -24.0),
			Vector2(origin_x + width, size.y),
			Vector2(origin_x - width * 0.28, size.y),
		])
		draw_colored_polygon(points, Color(1.0, 0.88, 0.55, (0.010 + float(index) * 0.004) * strength))


func _draw_cloud_shadows(strength: float) -> void:
	var cloud_count := 4 if motion_quality == "full" else 2
	if motion_quality == "still":
		cloud_count = 2
	for index in cloud_count:
		var speed := 7.0 + _hash01(index, 3.0) * 6.0
		var motion := 0.0 if motion_quality == "still" else _elapsed_seconds * speed
		var x := fposmod(_hash01(index, 7.0) * size.x + motion, size.x + 420.0) - 210.0
		var y := size.y * (0.15 + _hash01(index, 11.0) * 0.56)
		var radius := 90.0 + _hash01(index, 17.0) * 72.0
		var alpha := (0.020 + _hash01(index, 23.0) * 0.018) * strength
		var cloud_color := Color(0.08, 0.15, 0.18, alpha)
		for blob in 3:
			var offset := Vector2((float(blob) - 1.0) * radius * 0.78, sin(float(blob) * 2.1 + float(index)) * radius * 0.18)
			draw_circle(Vector2(x, y) + offset, radius * (0.72 + float(blob % 2) * 0.20), cloud_color)


func _draw_wind_accents(count: int, color: Color, speed: float) -> void:
	if motion_quality == "still":
		return
	var actual_count := count if motion_quality == "full" else maxi(3, count / 2)
	var gust := sin(_elapsed_seconds * 0.21 + _variant_seed * TAU) * 18.0
	for index in actual_count:
		var x := fposmod(_hash01(index, 29.0) * size.x + _elapsed_seconds * (speed + gust + float(index % 3) * 3.0), size.x + 80.0) - 40.0
		var y := fposmod(_hash01(index, 31.0) * size.y + sin(_elapsed_seconds * 0.7 + float(index)) * 16.0, maxf(size.y, 1.0))
		var length := 3.0 + _hash01(index, 37.0) * 5.0
		draw_line(Vector2(x - length, y), Vector2(x + length, y + length * 0.35), color, 1.4, true)


func _draw_rain_layer(count: int, near_layer: bool, strength: float) -> void:
	if motion_quality == "still":
		return
	var gust := sin(_elapsed_seconds * 0.18 + _variant_seed * TAU) * 34.0
	for index in count:
		var speed_y := (430.0 if near_layer else 255.0) + _hash01(index, 41.0 if near_layer else 43.0) * (150.0 if near_layer else 90.0)
		var speed_x := 88.0 + gust + _hash01(index, 47.0) * 40.0
		var x := fposmod(_hash01(index, 53.0 if near_layer else 59.0) * size.x + _elapsed_seconds * speed_x, size.x + 120.0) - 60.0
		var y := fposmod(_hash01(index, 61.0 if near_layer else 67.0) * size.y + _elapsed_seconds * speed_y, size.y + 150.0) - 75.0
		var length := (19.0 if near_layer else 10.0) + _hash01(index, 71.0) * (15.0 if near_layer else 7.0)
		var alpha := (0.46 if near_layer else 0.20) * strength * (0.72 + _hash01(index, 73.0) * 0.28)
		var width := 1.55 if near_layer else 0.85
		draw_line(Vector2(x, y), Vector2(x - length * 0.36, y + length), Color(0.66, 0.83, 0.94, alpha), width, true)


func _draw_ground_reactions(strength: float) -> void:
	if strength <= 0.02:
		return
	var ripple_count := 16 if motion_quality == "full" else 8
	if motion_quality == "still":
		ripple_count = 7
	for index in ripple_count:
		var phase_source := float(index) * 0.29 + _variant_seed * 3.7
		var phase := fposmod((0.0 if motion_quality == "still" else _elapsed_seconds * 1.35) + phase_source, 1.0)
		var center := Vector2(
			_hash01(index, 79.0) * size.x,
			size.y * (0.50 + _hash01(index, 83.0) * 0.45)
		)
		draw_arc(center, 3.0 + phase * 18.0, 0.10, PI - 0.10, 18, Color(0.70, 0.86, 0.94, (1.0 - phase) * 0.26 * strength), 1.15, true)


func _far_rain_count() -> int:
	if motion_quality == "still":
		return 0
	return FAR_RAIN_FULL if motion_quality == "full" else FAR_RAIN_FULL / 2


func _near_rain_count() -> int:
	if motion_quality == "still":
		return 0
	return NEAR_RAIN_FULL if motion_quality == "full" else NEAR_RAIN_FULL / 2


func _hash01(index: int, salt: float) -> float:
	return fposmod(sin(float(index + 1) * 12.9898 + salt * 7.233 + _variant_seed * 91.7) * 43758.5453, 1.0)


func _update_atmosphere_material() -> void:
	if _atmosphere_material == null:
		return
	_atmosphere_material.set_shader_parameter("elapsed", _elapsed_seconds)
	_atmosphere_material.set_shader_parameter("from_mode", float(WEATHER_STATES.find(previous_weather)))
	_atmosphere_material.set_shader_parameter("to_mode", float(WEATHER_STATES.find(current_weather)))
	_atmosphere_material.set_shader_parameter("transition_blend", _transition_progress)
	_atmosphere_material.set_shader_parameter("wetness", _wetness)
	_atmosphere_material.set_shader_parameter("variant_seed", _variant_seed)
