extends SceneTree

const WeatherVisualLayerScript = preload("res://ui/effects/weather_visual_layer.gd")

const FULLSCREEN_SETTLE_LIMIT := 120
const EXPECTED_PHYSICAL_SIZE := Vector2i(2880, 1800)
const LOGICAL_SIZE := Vector2i(1280, 800)
const OUTPUT_DIR := "res://artifacts/screenshots/weather-tests"
const CAPTURE_SPECS := [
	{"id": "sunny-full", "weather": "sunny", "quality": "full", "wet_seconds": 0.0},
	{"id": "cloudy-full", "weather": "cloudy", "quality": "full", "wet_seconds": 0.0},
	{"id": "rain-full", "weather": "rain", "quality": "full", "wet_seconds": 10.0},
	{"id": "rain-reduced", "weather": "rain", "quality": "reduced", "wet_seconds": 10.0},
]

var _stage: Control
var _weather
var _badge: Label


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	if DisplayServer.get_name().to_lower() == "headless":
		push_error("Weather visual matrix requires a visible display driver.")
		quit(1)
		return
	if not await _enter_stable_fullscreen():
		quit(1)
		return

	root.content_scale_size = LOGICAL_SIZE
	_build_stage()
	await process_frame
	_weather.set_process(false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	var captures: Array[Image] = []
	for spec_variant in CAPTURE_SPECS:
		var spec: Dictionary = spec_variant
		if not await _prepare_state(spec):
			quit(1)
			return
		var image := await _capture_frame()
		if image == null:
			quit(1)
			return
		var output_path := "%s/weather-%s-2880x1800.png" % [OUTPUT_DIR, str(spec["id"])]
		var error := image.save_png(ProjectSettings.globalize_path(output_path))
		if error != OK:
			push_error("Could not save weather capture %s: %d" % [output_path, error])
			quit(1)
			return
		captures.append(image.duplicate())
		print("Saved %s at physical=%s logical=%s." % [output_path, image.get_size(), root.get_visible_rect().size])

	var matrix_path := "%s/weather-visual-matrix-2880x1800.png" % OUTPUT_DIR
	if not _save_matrix(captures, matrix_path):
		quit(1)
		return
	print("Weather visual matrix saved: %s" % matrix_path)
	quit(0)


func _build_stage() -> void:
	_stage = Control.new()
	_stage.name = "WeatherVisualMatrixStage"
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_stage)

	var background := TextureRect.new()
	background.name = "StorybookCityBackground"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.texture = load("res://assets/images/world/backgrounds/city-map-background.png") as Texture2D
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(background)

	_weather = WeatherVisualLayerScript.new()
	_stage.add_child(_weather)

	var badge_panel := PanelContainer.new()
	badge_panel.name = "WeatherAcceptanceBadge"
	badge_panel.z_index = 3000
	badge_panel.anchor_left = 0.0
	badge_panel.anchor_top = 1.0
	badge_panel.anchor_right = 0.0
	badge_panel.anchor_bottom = 1.0
	badge_panel.offset_left = 24.0
	badge_panel.offset_top = -86.0
	badge_panel.offset_right = 545.0
	badge_panel.offset_bottom = -24.0
	badge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(0.025, 0.075, 0.10, 0.92)
	badge_style.border_color = Color(0.77, 0.88, 0.90, 0.90)
	badge_style.set_border_width_all(2)
	badge_style.set_corner_radius_all(14)
	badge_style.content_margin_left = 16
	badge_style.content_margin_right = 16
	badge_style.content_margin_top = 10
	badge_style.content_margin_bottom = 10
	badge_panel.add_theme_stylebox_override("panel", badge_style)
	_stage.add_child(badge_panel)

	_badge = Label.new()
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.add_theme_font_size_override("font_size", 22)
	_badge.add_theme_color_override("font_color", Color(0.96, 0.98, 0.95))
	_badge.add_theme_color_override("font_outline_color", Color(0.01, 0.03, 0.04, 0.96))
	_badge.add_theme_constant_override("outline_size", 3)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_panel.add_child(_badge)


func _prepare_state(spec: Dictionary) -> bool:
	var weather := str(spec["weather"])
	var quality := str(spec["quality"])
	if not _weather.set_motion_quality(quality):
		push_error("Weather capture rejected quality '%s'." % quality)
		return false
	_weather.set("_wetness", 0.0)
	_weather.set("_elapsed_seconds", 0.0)
	if not _weather.set_preview_weather(weather):
		push_error("Weather capture rejected state '%s'." % weather)
		return false
	var wet_seconds := float(spec["wet_seconds"])
	for _step in range(roundi(wet_seconds / 0.1)):
		_weather.call("_process", 0.1)
	_weather.call("_update_atmosphere_material")
	_weather.queue_redraw()
	var state: Dictionary = _weather.visual_debug_state()
	var displayed_far_rain := int(state["far_rain_count"]) if weather == "rain" else 0
	var displayed_near_rain := int(state["near_rain_count"]) if weather == "rain" else 0
	_badge.text = "%s  •  %s  •  wetness %.2f  •  rain %d+%d" % [
		weather.to_upper(),
		quality.to_upper(),
		float(state["wetness"]),
		displayed_far_rain,
		displayed_near_rain,
	]
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return true


func _capture_frame() -> Image:
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Weather capture returned an empty viewport image.")
		return null
	if image.get_size() != EXPECTED_PHYSICAL_SIZE:
		push_error("Weather capture must be exactly %s, got %s." % [EXPECTED_PHYSICAL_SIZE, image.get_size()])
		return null
	return image


func _save_matrix(captures: Array[Image], output_path: String) -> bool:
	if captures.size() != 4:
		push_error("Weather matrix expected four quadrants, got %d." % captures.size())
		return false
	var matrix := Image.create(EXPECTED_PHYSICAL_SIZE.x, EXPECTED_PHYSICAL_SIZE.y, false, Image.FORMAT_RGBA8)
	matrix.fill(Color(0.025, 0.055, 0.07, 1.0))
	var quadrant_size := Vector2i(EXPECTED_PHYSICAL_SIZE.x / 2, EXPECTED_PHYSICAL_SIZE.y / 2)
	var positions := [Vector2i(0, 0), Vector2i(quadrant_size.x, 0), Vector2i(0, quadrant_size.y), quadrant_size]
	for index in captures.size():
		var quadrant := captures[index].duplicate()
		quadrant.convert(Image.FORMAT_RGBA8)
		quadrant.resize(quadrant_size.x, quadrant_size.y, Image.INTERPOLATE_LANCZOS)
		matrix.blit_rect(quadrant, Rect2i(Vector2i.ZERO, quadrant_size), positions[index])
	var divider := Color(0.92, 0.84, 0.60, 1.0)
	matrix.fill_rect(Rect2i(quadrant_size.x - 3, 0, 6, EXPECTED_PHYSICAL_SIZE.y), divider)
	matrix.fill_rect(Rect2i(0, quadrant_size.y - 3, EXPECTED_PHYSICAL_SIZE.x, 6), divider)
	var error := matrix.save_png(ProjectSettings.globalize_path(output_path))
	if error != OK:
		push_error("Could not save weather matrix %s: %d" % [output_path, error])
		return false
	return true


func _enter_stable_fullscreen() -> bool:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	var previous_size := Vector2i.ZERO
	var stable_frames := 0
	for _frame in range(FULLSCREEN_SETTLE_LIMIT):
		await process_frame
		var current_size := DisplayServer.window_get_size()
		var mode := DisplayServer.window_get_mode()
		var fullscreen := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if fullscreen and current_size == previous_size and current_size == EXPECTED_PHYSICAL_SIZE:
			stable_frames += 1
		else:
			stable_frames = 0
		previous_size = current_size
		if stable_frames >= 3:
			print("Weather capture fullscreen stabilized at %s." % current_size)
			return true
	push_error("Fullscreen did not stabilize at %s within %d frames; last=%s." % [EXPECTED_PHYSICAL_SIZE, FULLSCREEN_SETTLE_LIMIT, previous_size])
	return false
