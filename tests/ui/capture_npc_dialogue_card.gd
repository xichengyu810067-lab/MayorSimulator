extends SceneTree

const OUTPUT_PATH := "res://artifacts/screenshots/ui-tests/npc-dialogue-card-gallery.png"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1120, 640))
	root.content_scale_size = Vector2i(1120, 640)

	var stage := Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(stage)

	var light_background := ColorRect.new()
	light_background.color = Color(0.80, 0.89, 0.74)
	light_background.position = Vector2.ZERO
	light_background.size = Vector2(560, 640)
	light_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(light_background)

	var dark_background := ColorRect.new()
	dark_background.color = Color(0.08, 0.15, 0.20)
	dark_background.position = Vector2(560, 0)
	dark_background.size = Vector2(560, 640)
	dark_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(dark_background)

	var card_script = load("res://ui/components/npc_dialogue_card.gd")
	if card_script == null:
		push_error("NPC dialogue card script could not be loaded")
		quit(1)
		return
	var portrait := load("res://assets/images/characters/npc/npc-merchant.png") as Texture2D

	for column in range(2):
		var heading := Label.new()
		heading.text = "DAY · parchment" if column == 0 else "NIGHT · moonlit teal"
		heading.position = Vector2(45 + column * 560, 44)
		heading.size = Vector2(470, 34)
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heading.add_theme_font_size_override("font_size", 18)
		heading.add_theme_color_override("font_color", Color(0.23, 0.24, 0.17) if column == 0 else Color(0.83, 0.92, 0.90))
		heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(heading)

		var card: PanelContainer = card_script.new()
		card.position = Vector2(46 + column * 560, 126)
		card.call("set_content", "黃建宏", "商人", "市場最近很熱鬧，但攤位旁的路燈需要修理。", "待回應", portrait, "查看陳情")
		card.call("set_dark_mode", column == 1)
		stage.add_child(card)

	for _frame in range(8):
		await process_frame
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("NPC dialogue card capture requires a rendering display driver")
		quit(1)
		return
	var absolute_path := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var error := image.save_png(absolute_path)
	if error != OK:
		push_error("Failed to save NPC dialogue card gallery: %s" % error_string(error))
		quit(1)
		return
	print("NPC dialogue card gallery saved to %s" % OUTPUT_PATH)
	quit(0)
