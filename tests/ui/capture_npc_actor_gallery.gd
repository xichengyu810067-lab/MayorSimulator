extends SceneTree

const OUTPUT_PATH := "res://artifacts/screenshots/ui-tests/npc-actor-gallery.png"
const ROLES := ["一般居民", "學生", "商人", "老年居民", "工人", "公務人員", "議員"]
const EXPRESSIONS := ["calm", "curious", "happy", "concerned", "proud", "calm", "curious"]
const ROW_TITLES := [
	"IDLE · breathing, blink & expressions",
	"WALK · stride rhythm, facing & dust",
	"INTERACT · dark-mode rim, heart & ripple",
]


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1540, 1080))
	root.content_scale_size = Vector2i(1540, 1080)
	var actor_script = load("res://scripts/world/npc_actor.gd")
	if actor_script == null:
		push_error("NPC actor script could not be loaded.")
		quit(1)
		return

	var canvas := Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(canvas)
	var row_colors := [Color(0.84, 0.91, 0.77), Color(0.94, 0.86, 0.70), Color(0.10, 0.17, 0.23)]
	for row in range(3):
		var background := ColorRect.new()
		background.color = row_colors[row]
		background.position = Vector2(0, row * 360)
		background.size = Vector2(1540, 360)
		canvas.add_child(background)
		var title := Label.new()
		title.text = ROW_TITLES[row]
		title.position = Vector2(22, row * 360 + 8)
		title.size = Vector2(680, 30)
		title.add_theme_font_size_override("font_size", 18)
		title.add_theme_color_override("font_color", Color(0.18, 0.23, 0.20, 0.84) if row < 2 else Color(0.88, 0.94, 0.97, 0.86))
		canvas.add_child(title)

	for row in range(3):
		for index in range(ROLES.size()):
			var actor: Button = actor_script.new()
			actor.position = Vector2(35 + index * 215, 42 + row * 360)
			actor.size = Vector2(150, 205)
			actor.call("set_actor", ROLES[index], row == 2, index)
			# The gallery documents visual states, not tooltip layout.  Suppressing
			# tooltip text keeps an incidental host-pointer position from covering a
			# role while still allowing one hovered actor to demonstrate its ring.
			actor.tooltip_text = ""
			if row == 0:
				actor.call("set_expression", EXPRESSIONS[index])
				actor.call("set_motion", false, 3.0 + float(index) * 3.7, 1.0)
			elif row == 1:
				actor.call("set_motion", true, 0.75 + float(index) * 0.73, 1.0 if index % 2 == 0 else -1.0)
			else:
				actor.call("set_motion", false, 3.0 + float(index) * 2.1, -1.0 if index % 2 == 0 else 1.0)
			canvas.add_child(actor)
			if row == 2:
				actor.call("play_interaction_reaction")
			var label := Label.new()
			label.text = ROLES[index]
			label.position = Vector2(15 + index * 215, 250 + row * 360)
			label.size = Vector2(190, 44)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 20)
			label.add_theme_color_override("font_color", Color(0.10, 0.14, 0.16) if row < 2 else Color(0.90, 0.94, 0.96))
			canvas.add_child(label)

	for _frame in range(6):
		await process_frame
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("NPC gallery capture requires a rendering display driver; the headless dummy driver cannot produce a viewport texture.")
		quit(1)
		return
	var absolute_path := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var error := image.save_png(absolute_path)
	if error != OK:
		push_error("Failed to save NPC actor gallery: %s" % error_string(error))
		quit(1)
		return
	print("NPC actor gallery saved to %s" % OUTPUT_PATH)
	quit(0)
