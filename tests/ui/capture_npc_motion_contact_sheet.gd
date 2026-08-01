extends SceneTree

const OUTPUT_PATH := "res://artifacts/screenshots/ui-tests/npc-motion-contact-sheet-2880x1800.png"
const CANVAS_SIZE := Vector2i(2880, 1800)
const DIRECTIONS := ["down", "left", "right", "up"]
const DIRECTION_VECTORS := {
	"down": Vector2.DOWN,
	"left": Vector2.LEFT,
	"right": Vector2.RIGHT,
	"up": Vector2.UP,
}
const ROLE_SPECS := [
	{"label": "一般居民", "role": "一般居民", "variant": 0},
	{"label": "學生", "role": "學生", "variant": 0},
	{"label": "商人", "role": "商人", "variant": 0},
	{"label": "老年居民", "role": "老年居民", "variant": 0},
	{"label": "工人", "role": "工人", "variant": 0},
	{"label": "公務人員", "role": "公務人員", "variant": 0},
	{"label": "議員", "role": "議員", "variant": 0},
	{"label": "花藝居民", "role": "一般居民", "variant": 1},
]


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(CANVAS_SIZE)
	root.content_scale_size = CANVAS_SIZE
	root.size = CANVAS_SIZE

	var actor_script = load("res://scripts/world/npc_actor.gd")
	if actor_script == null:
		push_error("NPC motion contact sheet could not load npc_actor.gd")
		quit(1)
		return
	var probe: Button = actor_script.new()
	root.add_child(probe)
	await process_frame
	for method_name: String in ["set_locomotion", "get_animation_contract", "get_locomotion_debug_snapshot"]:
		if not probe.has_method(method_name):
			push_error("NPC motion contact sheet is waiting for `%s`" % method_name)
			probe.queue_free()
			quit(1)
			return
	var contract: Dictionary = probe.call("get_animation_contract")
	var frame_distance := float(contract.get("walk_frame_distance", 5.5))
	probe.queue_free()

	var canvas := Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(canvas)
	var background := ColorRect.new()
	background.color = Color("#e8efe1")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(background)

	var title := Label.new()
	title.text = "NPC LOCOMOTION · 8 atlases · 4 directions × 4 distance-driven frames"
	title.position = Vector2(28, 14)
	title.size = Vector2(2100, 42)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("#263a36"))
	canvas.add_child(title)
	var note := Label.new()
	note.text = "Every actor uses an independent directional row. Gold lines mark the shared feet baseline."
	note.position = Vector2(1650, 20)
	note.size = Vector2(1190, 32)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	note.add_theme_font_size_override("font_size", 17)
	note.add_theme_color_override("font_color", Color("#52625c"))
	canvas.add_child(note)

	const LEFT_LABEL_WIDTH := 178.0
	const TOP := 92.0
	const CELL_WIDTH := 168.0
	const ROW_HEIGHT := 207.0
	const ACTOR_SIZE := Vector2(112, 116)
	var row_colors := [Color("#f8f2d4"), Color("#e8f0d7"), Color("#e1edf2"), Color("#efe2ee")]

	for direction_index in DIRECTIONS.size():
		var direction: String = str(DIRECTIONS[direction_index])
		for frame_index in 4:
			var column := direction_index * 4 + frame_index
			var header := Label.new()
			header.text = "%s · %d" % [direction.to_upper(), frame_index]
			header.position = Vector2(LEFT_LABEL_WIDTH + float(column) * CELL_WIDTH, 58)
			header.size = Vector2(CELL_WIDTH, 30)
			header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			header.add_theme_font_size_override("font_size", 15)
			header.add_theme_color_override("font_color", Color("#31463f"))
			canvas.add_child(header)

	for role_index in ROLE_SPECS.size():
		var role_spec: Dictionary = ROLE_SPECS[role_index]
		var row_top := TOP + float(role_index) * ROW_HEIGHT
		var role_label := Label.new()
		role_label.text = str(role_spec["label"])
		role_label.position = Vector2(12, row_top + 72)
		role_label.size = Vector2(LEFT_LABEL_WIDTH - 20, 40)
		role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		role_label.add_theme_font_size_override("font_size", 20)
		role_label.add_theme_color_override("font_color", Color("#263a36"))
		canvas.add_child(role_label)

		for direction_index in DIRECTIONS.size():
			var direction: String = str(DIRECTIONS[direction_index])
			for frame_index in 4:
				var column := direction_index * 4 + frame_index
				var cell := ColorRect.new()
				cell.color = row_colors[direction_index]
				cell.position = Vector2(LEFT_LABEL_WIDTH + float(column) * CELL_WIDTH + 3, row_top + 3)
				cell.size = Vector2(CELL_WIDTH - 6, ROW_HEIGHT - 8)
				cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
				canvas.add_child(cell)

				var baseline := ColorRect.new()
				baseline.color = Color(0.77, 0.58, 0.18, 0.72)
				baseline.position = Vector2(cell.position.x + 24, row_top + 156)
				baseline.size = Vector2(CELL_WIDTH - 48, 2)
				baseline.mouse_filter = Control.MOUSE_FILTER_IGNORE
				canvas.add_child(baseline)

				var actor: Button = actor_script.new()
				actor.position = Vector2(
					cell.position.x + (cell.size.x - ACTOR_SIZE.x) * 0.5,
					row_top + 42
				)
				actor.size = ACTOR_SIZE
				actor.call("set_actor", str(role_spec["role"]), false, int(role_spec["variant"]))
				var moved_distance := 0.25 + float(frame_index) * frame_distance
				actor.call("set_locomotion", DIRECTION_VECTORS[direction] * 40.0, moved_distance, 0.20)
				actor.tooltip_text = ""
				actor.mouse_filter = Control.MOUSE_FILTER_IGNORE
				canvas.add_child(actor)

				var snapshot: Dictionary = actor.call("get_locomotion_debug_snapshot")
				var details := Label.new()
				details.text = "atlas %02d · phase %.2f" % [
					int(snapshot.get("atlas_frame_index", -1)),
					float(snapshot.get("cycle_phase", 0.0)),
				]
				details.position = Vector2(cell.position.x, row_top + 168)
				details.size = Vector2(cell.size.x, 26)
				details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				details.add_theme_font_size_override("font_size", 12)
				details.add_theme_color_override("font_color", Color("#53625c"))
				canvas.add_child(details)

	# Let direction blends settle; no travelled distance is added while the
	# actors wait, so their selected distance-driven frames remain unchanged.
	for _frame in 18:
		await process_frame
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("NPC motion contact sheet requires a visible rendering driver")
		quit(1)
		return
	var absolute_path := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var save_error := image.save_png(absolute_path)
	if save_error != OK:
		push_error("Could not save NPC motion contact sheet: %s" % error_string(save_error))
		quit(1)
		return
	print("NPC motion contact sheet saved. Roles=8 PosesPerRole=16 Cells=128 Path=%s" % OUTPUT_PATH)
	quit(0)
