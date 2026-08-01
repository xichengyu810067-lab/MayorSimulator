extends SceneTree

const SOURCE_DIR := "res://assets/images/characters/npc/source"
const OUTPUT_DIR := "res://assets/images/characters/npc"
const CANVAS_SIZE := Vector2i(384, 512)
const TARGET_SIZE := Vector2i(348, 476)
const CLEAR_DISTANCE := 0.055
const FEATHER_DISTANCE := 0.34
const ALPHA_THRESHOLD := 0.018
const SOURCE_PADDING := 8
const FEET_MARGIN := 12

const PACKS := [
	{
		"source": "npc-pack-community-raw.png",
		"roles": ["resident", "student", "merchant", "elderly"]
	},
	{
		"source": "npc-pack-civic-raw.png",
		"roles": ["worker", "civil-servant", "council-member", "resident-florist"]
	}
]


func _initialize() -> void:
	call_deferred("_process_packs")


func _process_packs() -> void:
	var output_absolute := ProjectSettings.globalize_path(OUTPUT_DIR)
	var error := DirAccess.make_dir_recursive_absolute(output_absolute)
	if error != OK:
		push_error("Could not create NPC output directory: %s" % error_string(error))
		quit(1)
		return

	var report: Dictionary = {
		"canvas_size": [CANVAS_SIZE.x, CANVAS_SIZE.y],
		"target_size": [TARGET_SIZE.x, TARGET_SIZE.y],
		"anchor": "feet",
		"background_key": "#FF00FF",
		"processor": "Godot 4 deterministic chroma-key fallback",
		"assets": []
	}
	for pack in PACKS:
		if not _process_pack(pack, report):
			quit(1)
			return

	var report_path := output_absolute.path_join("pipeline-meta.json")
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	if report_file == null:
		push_error("Could not write NPC pipeline report: %s" % report_path)
		quit(1)
		return
	report_file.store_string(JSON.stringify(report, "\t") + "\n")
	report_file.close()
	print("NPC sprite processing complete: %d assets" % report["assets"].size())
	quit(0)


func _process_pack(pack: Dictionary, report: Dictionary) -> bool:
	var source_path := ProjectSettings.globalize_path(SOURCE_DIR.path_join(str(pack["source"])))
	var source := Image.load_from_file(source_path)
	if source == null or source.is_empty():
		push_error("Could not load NPC source pack: %s" % source_path)
		return false
	source.convert(Image.FORMAT_RGBA8)
	var cell_size := Vector2i(source.get_width() / 2, source.get_height() / 2)
	var roles: Array = pack["roles"]
	for index in roles.size():
		var cell_position := Vector2i(index % 2, index / 2) * cell_size
		var cell := source.get_region(Rect2i(cell_position, cell_size))
		_remove_magenta(cell, cell.get_pixel(0, 0))
		var bounds := _opaque_bounds(cell)
		if bounds.size.x <= 0 or bounds.size.y <= 0:
			push_error("NPC cell is empty after chroma key: %s[%d]" % [pack["source"], index])
			return false
		bounds = bounds.grow(SOURCE_PADDING).intersection(Rect2i(Vector2i.ZERO, cell_size))
		var cropped := cell.get_region(bounds)
		var scale_factor := minf(
			float(TARGET_SIZE.x) / float(cropped.get_width()),
			float(TARGET_SIZE.y) / float(cropped.get_height())
		)
		var rendered_size := Vector2i(
			maxi(1, roundi(float(cropped.get_width()) * scale_factor)),
			maxi(1, roundi(float(cropped.get_height()) * scale_factor))
		)
		cropped.resize(rendered_size.x, rendered_size.y, Image.INTERPOLATE_LANCZOS)
		var canvas := Image.create(CANVAS_SIZE.x, CANVAS_SIZE.y, false, Image.FORMAT_RGBA8)
		canvas.fill(Color(0, 0, 0, 0))
		var destination := Vector2i(
			(CANVAS_SIZE.x - rendered_size.x) / 2,
			CANVAS_SIZE.y - FEET_MARGIN - rendered_size.y
		)
		canvas.blend_rect(cropped, Rect2i(Vector2i.ZERO, rendered_size), destination)
		var output_name := "npc-%s.png" % str(roles[index])
		var output_path := ProjectSettings.globalize_path(OUTPUT_DIR.path_join(output_name))
		var save_error := canvas.save_png(output_path)
		if save_error != OK:
			push_error("Could not save NPC sprite %s: %s" % [output_name, error_string(save_error)])
			return false

		var edge_touch := _touches_canvas_edge(canvas)
		report["assets"].append({
			"role": str(roles[index]),
			"source": str(pack["source"]),
			"cell": index,
			"source_bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
			"rendered_size": [rendered_size.x, rendered_size.y],
			"destination": [destination.x, destination.y],
			"edge_touch": edge_touch,
			"output": output_name
		})
		if edge_touch:
			push_error("NPC sprite touched delivery canvas edge: %s" % output_name)
			return false
		print("Processed %s: source=%s rendered=%s anchor_y=%d" % [output_name, bounds, rendered_size, destination.y + rendered_size.y])
	return true


func _remove_magenta(image: Image, key_color: Color) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			var distance := Vector3(color.r - key_color.r, color.g - key_color.g, color.b - key_color.b).length()
			var magenta_strength := minf(color.r, color.b)
			var magenta_dominance := magenta_strength - color.g
			if distance <= CLEAR_DISTANCE or (magenta_strength >= 0.45 and magenta_dominance >= 0.56):
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var is_magenta_edge := magenta_strength >= 0.45 and magenta_dominance > 0.18
			if distance >= FEATHER_DISTANCE and not is_magenta_edge:
				color.a = 1.0
				image.set_pixel(x, y, color)
				continue
			var distance_alpha := clampf((distance - CLEAR_DISTANCE) / (FEATHER_DISTANCE - CLEAR_DISTANCE), 0.0, 1.0)
			var dominance_alpha := clampf((0.56 - magenta_dominance) / (0.56 - 0.18), 0.0, 1.0)
			var alpha := minf(distance_alpha, dominance_alpha) if is_magenta_edge else distance_alpha
			alpha = alpha * alpha * (3.0 - 2.0 * alpha)
			if alpha <= 0.002:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var inverse_alpha := 1.0 - alpha
			var recovered := Color(
				clampf((color.r - inverse_alpha * key_color.r) / alpha, 0.0, 1.0),
				clampf((color.g - inverse_alpha * key_color.g) / alpha, 0.0, 1.0),
				clampf((color.b - inverse_alpha * key_color.b) / alpha, 0.0, 1.0),
				alpha
			)
			image.set_pixel(x, y, recovered)
	_despill_outline(image, key_color)


func _despill_outline(image: Image, key_color: Color) -> void:
	var snapshot: Image = image.duplicate()
	for y in image.get_height():
		for x in image.get_width():
			var color: Color = snapshot.get_pixel(x, y)
			if color.a <= ALPHA_THRESHOLD or not _has_transparent_neighbor(snapshot, x, y, 2):
				continue
			var distance := Vector3(color.r - key_color.r, color.g - key_color.g, color.b - key_color.b).length()
			var magenta_dominance: float = minf(color.r, color.b) - color.g
			if distance >= 0.82 or magenta_dominance <= 0.12:
				continue
			var edge_alpha := clampf((0.54 - magenta_dominance) / (0.54 - 0.12), 0.0, 1.0)
			edge_alpha = edge_alpha * edge_alpha * (3.0 - 2.0 * edge_alpha)
			var target_alpha := minf(color.a, edge_alpha)
			if target_alpha <= 0.01:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var removed_alpha := 1.0 - (target_alpha / maxf(color.a, 0.001))
			image.set_pixel(x, y, Color(
				clampf((color.r - removed_alpha * key_color.r) / maxf(1.0 - removed_alpha, 0.001), 0.0, 1.0),
				clampf((color.g - removed_alpha * key_color.g) / maxf(1.0 - removed_alpha, 0.001), 0.0, 1.0),
				clampf((color.b - removed_alpha * key_color.b) / maxf(1.0 - removed_alpha, 0.001), 0.0, 1.0),
				target_alpha
			))


func _has_transparent_neighbor(image: Image, center_x: int, center_y: int, radius: int) -> bool:
	for offset_y in range(-radius, radius + 1):
		for offset_x in range(-radius, radius + 1):
			var sample_x := center_x + offset_x
			var sample_y := center_y + offset_y
			if sample_x < 0 or sample_y < 0 or sample_x >= image.get_width() or sample_y >= image.get_height():
				return true
			if image.get_pixel(sample_x, sample_y).a <= ALPHA_THRESHOLD:
				return true
	return false


func _opaque_bounds(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a <= ALPHA_THRESHOLD:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _touches_canvas_edge(image: Image) -> bool:
	for x in image.get_width():
		if image.get_pixel(x, 0).a > ALPHA_THRESHOLD or image.get_pixel(x, image.get_height() - 1).a > ALPHA_THRESHOLD:
			return true
	for y in image.get_height():
		if image.get_pixel(0, y).a > ALPHA_THRESHOLD or image.get_pixel(image.get_width() - 1, y).a > ALPHA_THRESHOLD:
			return true
	return false
