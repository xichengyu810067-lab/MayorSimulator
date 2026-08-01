extends SceneTree

const EXPECTED_ROWS := 4
const EXPECTED_COLUMNS := 4
const EXPECTED_CELL_SIZE := 192
const EXPECTED_FRAMES_PER_ATLAS := 16
const EXPECTED_ATLAS_COUNT := 8
const EXPECTED_TOTAL_SOURCE_FRAMES := 128
const ALPHA_THRESHOLD := 0.02
const MAX_FEET_ANCHOR_DRIFT_PX := 1.0

const ATLAS_SPECS := [
	{"role": "一般居民", "variant": 0, "slug": "resident"},
	{"role": "學生", "variant": 0, "slug": "student"},
	{"role": "商人", "variant": 0, "slug": "merchant"},
	{"role": "老年居民", "variant": 0, "slug": "elderly"},
	{"role": "工人", "variant": 0, "slug": "worker"},
	{"role": "公務人員", "variant": 0, "slug": "civil-servant"},
	{"role": "議員", "variant": 0, "slug": "council-member"},
	{"role": "一般居民", "variant": 1, "slug": "resident-florist"},
]
const DIRECTION_ORDER := ["down", "left", "right", "up"]
const DIRECTION_VECTORS := {
	"down": Vector2.DOWN,
	"left": Vector2.LEFT,
	"right": Vector2.RIGHT,
	"up": Vector2.UP,
}

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var atlas_paths := _validate_delivered_atlases()
	var actor_script = load("res://scripts/world/npc_actor.gd")
	_check(actor_script != null, "NPC actor script could not be loaded")
	if actor_script == null:
		_finish()
		return

	var actor: Button = actor_script.new()
	actor.size = Vector2(96, 128)
	root.add_child(actor)
	await process_frame
	_validate_runtime_contract(actor, atlas_paths)
	actor.queue_free()
	_finish()


func _validate_delivered_atlases() -> PackedStringArray:
	_check(ATLAS_SPECS.size() == EXPECTED_ATLAS_COUNT, "acceptance fixture does not enumerate exactly eight NPC atlases")
	var atlas_paths := PackedStringArray()
	var total_source_frames := 0
	for spec_variant: Variant in ATLAS_SPECS:
		var spec: Dictionary = spec_variant
		var slug := str(spec["slug"])
		var directory := "res://assets/images/characters/npc/walk/%s" % slug
		var atlas_path := directory.path_join("sheet-transparent.png")
		var metadata_path := directory.path_join("pipeline-meta.json")
		atlas_paths.append(atlas_path)

		_check(FileAccess.file_exists(metadata_path), "%s metadata is missing" % slug)
		_check(FileAccess.file_exists(atlas_path), "%s transparent atlas is missing" % slug)
		if not FileAccess.file_exists(metadata_path) or not FileAccess.file_exists(atlas_path):
			continue

		var metadata_variant: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
		_check(metadata_variant is Dictionary, "%s metadata is not valid JSON" % slug)
		if not metadata_variant is Dictionary:
			continue
		var metadata: Dictionary = metadata_variant
		_check(int(metadata.get("rows", -1)) == EXPECTED_ROWS, "%s atlas does not declare four direction rows" % slug)
		_check(int(metadata.get("cols", -1)) == EXPECTED_COLUMNS, "%s atlas does not declare four walk columns" % slug)
		_check(int(metadata.get("cell_size", -1)) == EXPECTED_CELL_SIZE, "%s atlas cells are not 192x192" % slug)
		var edge_touch_frames: Array = metadata.get("edge_touch_frames", [])
		_check(edge_touch_frames.is_empty(), "%s metadata reports edge-touch frames: %s" % [slug, edge_touch_frames])

		var metadata_frames: Array = metadata.get("frames", metadata.get("frame_sources", []))
		_check(metadata_frames.size() == EXPECTED_FRAMES_PER_ATLAS, "%s metadata does not describe 16 source frames" % slug)
		total_source_frames += metadata_frames.size()

		var atlas := _load_image(atlas_path)
		if atlas == null:
			continue
		_check(
			atlas.get_size() == Vector2i(EXPECTED_CELL_SIZE * EXPECTED_COLUMNS, EXPECTED_CELL_SIZE * EXPECTED_ROWS),
			"%s atlas is not 768x768: %s" % [slug, atlas.get_size()]
		)

		var frame_images: Array[Image] = []
		var feet_bottoms: Array[int] = []
		for frame_index in EXPECTED_FRAMES_PER_ATLAS:
			var frame_path := directory.path_join("npc_walk-%d.png" % (frame_index + 1))
			_check(FileAccess.file_exists(frame_path), "%s source frame %d is missing" % [slug, frame_index])
			var frame := _load_image(frame_path)
			if frame == null:
				continue
			frame_images.append(frame)
			_check(frame.get_size() == Vector2i(EXPECTED_CELL_SIZE, EXPECTED_CELL_SIZE), "%s frame %d is not 192x192" % [slug, frame_index])
			_check(not _image_touches_edge(frame), "%s frame %d has opaque pixels touching its cell edge" % [slug, frame_index])
			var opaque_bottom := _opaque_bottom(frame)
			_check(opaque_bottom >= 0, "%s frame %d is empty" % [slug, frame_index])
			feet_bottoms.append(opaque_bottom)

		if feet_bottoms.size() == EXPECTED_FRAMES_PER_ATLAS:
			var minimum_bottom: int = int(feet_bottoms.min())
			var maximum_bottom: int = int(feet_bottoms.max())
			_check(maximum_bottom - minimum_bottom <= int(MAX_FEET_ANCHOR_DRIFT_PX), "%s feet anchors drift by %d px across source frames" % [slug, maximum_bottom - minimum_bottom])

		if frame_images.size() == EXPECTED_FRAMES_PER_ATLAS:
			_validate_direction_rows(slug, frame_images)

	_check(total_source_frames == EXPECTED_TOTAL_SOURCE_FRAMES, "eight 4x4 atlases must deliver 128 source frames, got %d" % total_source_frames)
	return atlas_paths


func _validate_direction_rows(slug: String, frames: Array[Image]) -> void:
	var row_first_hashes := {}
	for row in EXPECTED_ROWS:
		var row_hashes := {}
		for column in EXPECTED_COLUMNS:
			var image: Image = frames[row * EXPECTED_COLUMNS + column]
			row_hashes[hash(image.get_data())] = true
		_check(row_hashes.size() >= 2, "%s %s row does not switch animation frames" % [slug, DIRECTION_ORDER[row]])
		row_first_hashes[hash(frames[row * EXPECTED_COLUMNS].get_data())] = true
	_check(row_first_hashes.size() == EXPECTED_ROWS, "%s does not provide four visually distinct direction rows" % slug)

	# A genuine right-facing row must not be produced by flipping the left row at
	# runtime.  Compare the delivered pixels after horizontally flipping right
	# back toward left; an exact mirrored delivery would have near-zero residual.
	var mirror_residual := 0.0
	for column in EXPECTED_COLUMNS:
		var left_frame: Image = frames[EXPECTED_COLUMNS + column]
		var right_frame: Image = frames[EXPECTED_COLUMNS * 2 + column]
		mirror_residual += _mean_rgba_difference(left_frame, right_frame, true)
	mirror_residual /= float(EXPECTED_COLUMNS)
	_check(mirror_residual > 0.002, "%s left/right rows are only horizontal mirrors (residual %.6f)" % [slug, mirror_residual])


func _validate_runtime_contract(actor: Button, delivered_atlas_paths: PackedStringArray) -> void:
	var required_methods := [
		"get_animation_contract",
		"get_locomotion_debug_snapshot",
		"debug_sample_locomotion",
		"set_locomotion",
	]
	for method_name: String in required_methods:
		_check(actor.has_method(method_name), "NPC rig integration is waiting for public/debug API `%s`" % method_name)
	if required_methods.any(func(method_name: String) -> bool: return not actor.has_method(method_name)):
		return

	var contract_variant: Variant = actor.call("get_animation_contract")
	_check(contract_variant is Dictionary, "get_animation_contract() did not return a Dictionary")
	if not contract_variant is Dictionary:
		return
	var contract: Dictionary = contract_variant
	var directions: Array = contract.get("directions", contract.get("direction_order", []))
	_check(directions == DIRECTION_ORDER, "runtime direction order must be down/left/right/up, got %s" % [directions])
	_check(int(contract.get("frames_per_direction", -1)) == EXPECTED_COLUMNS, "runtime does not expose four walk frames per direction")
	_check(_cell_size_from_variant(contract.get("cell_size", 0)) == Vector2i(EXPECTED_CELL_SIZE, EXPECTED_CELL_SIZE), "runtime atlas cell size is not 192x192")
	var uses_horizontal_mirroring := bool(contract.get("uses_horizontal_mirroring", contract.get("uses_horizontal_mirror", true)))
	_check(not uses_horizontal_mirroring, "runtime still declares horizontal mirroring instead of independent left/right rows")
	_check(int(contract.get("opaque_body_draws_per_frame", -1)) == 1, "direction transition can render more than one opaque body")
	_check(str(contract.get("turn_transition_mode", "")) == "single_body_temporal_lock", "direction transition is not the single-body temporal mode")
	var neutral_frames: Array = contract.get("neutral_frames", [])
	_check(neutral_frames == [0, 2], "runtime does not identify the two neutral standing frames: %s" % [neutral_frames])
	var stop_settle_seconds := float(contract.get("stop_settle_seconds", 0.0))
	_check(stop_settle_seconds >= 0.08 and stop_settle_seconds <= 0.20, "stop settle is not a short grounded transition: %.3f" % stop_settle_seconds)
	_check(float(contract.get("direction_axis_hysteresis", 0.0)) >= 0.10, "direction selection has no meaningful 45-degree hysteresis")
	_check(float(contract.get("direction_lock_seconds", 0.0)) >= 0.08, "direction row has no short anti-jitter lock")

	var runtime_paths := _string_values(contract.get("atlas_paths", contract.get("atlases", {})))
	_check(runtime_paths.size() == EXPECTED_ATLAS_COUNT, "runtime contract does not map all eight atlases: %s" % [runtime_paths])
	for expected_path: String in delivered_atlas_paths:
		_check(expected_path in runtime_paths, "runtime contract omits delivered atlas %s" % expected_path)

	var stride_distance := maxf(8.0, float(contract.get("stride_distance", contract.get("walk_cycle_distance", 32.0))))
	var reference_anchor: Variant = null
	var direction_source_rects := {}
	for direction: String in DIRECTION_ORDER:
		var seen_frames := {}
		var seen_source_rects := {}
		for sample_index in 129:
			var distance := stride_distance * 2.0 * float(sample_index) / 128.0
			var sample_variant: Variant = actor.call("debug_sample_locomotion", direction, distance, 40.0)
			_check(sample_variant is Dictionary, "debug_sample_locomotion(%s) did not return a Dictionary" % direction)
			if not sample_variant is Dictionary:
				break
			var sample: Dictionary = sample_variant
			_check(str(sample.get("direction", "")) == direction, "runtime direction does not follow %s velocity" % direction)
			_check(bool(sample.get("is_walking", false)), "%s positive-speed sample is not in walk state" % direction)
			var frame_index := int(sample.get("frame_index", -1))
			_check(frame_index >= 0 and frame_index < EXPECTED_COLUMNS, "%s sample frame index is outside 0..3: %d" % [direction, frame_index])
			seen_frames[frame_index] = true
			seen_source_rects[str(sample.get("source_rect", ""))] = true
			var anchor: Variant = _vector2_from_variant(sample.get("feet_anchor", null))
			_check(anchor != null, "%s locomotion sample omits feet_anchor" % direction)
			if anchor != null:
				if reference_anchor == null:
					reference_anchor = anchor
				else:
					_check((anchor as Vector2).distance_to(reference_anchor as Vector2) <= MAX_FEET_ANCHOR_DRIFT_PX, "%s runtime feet anchor drifts across frames" % direction)
		_check(seen_frames.size() == EXPECTED_COLUMNS, "%s distance-driven walk did not visit all four frames: %s" % [direction, seen_frames.keys()])
		_check(seen_source_rects.size() == EXPECTED_COLUMNS, "%s walk samples do not switch among four atlas cells" % direction)
		var representative: Dictionary = actor.call("debug_sample_locomotion", direction, 0.0, 40.0)
		direction_source_rects[str(representative.get("source_rect", ""))] = true
	_check(direction_source_rects.size() == EXPECTED_ROWS, "four directions do not select four independent atlas rows")

	var speed_independent_a: Dictionary = actor.call("debug_sample_locomotion", "right", stride_distance * 0.73, 20.0)
	var speed_independent_b: Dictionary = actor.call("debug_sample_locomotion", "right", stride_distance * 0.73, 80.0)
	_check(int(speed_independent_a.get("frame_index", -1)) == int(speed_independent_b.get("frame_index", -2)), "walk frame is driven by speed/time instead of travelled distance")
	_check(_circular_distance(float(speed_independent_a.get("cycle_phase", 0.0)), float(speed_independent_b.get("cycle_phase", 0.5))) <= 0.001, "cycle phase changes with speed at an identical travelled distance")

	var stopped_a: Dictionary = actor.call("debug_sample_locomotion", "down", 0.0, 0.0)
	var stopped_b: Dictionary = actor.call("debug_sample_locomotion", "down", stride_distance * 3.0, 0.0)
	_check(not bool(stopped_a.get("is_walking", true)) and not bool(stopped_b.get("is_walking", true)), "zero-speed NPC remains in walking state")
	_check(int(stopped_a.get("frame_index", -1)) == int(stopped_b.get("frame_index", -2)), "stationary NPC air-walks when travelled_distance input changes")

	# Exercise the actual public driver as well as the pure sampler.  A long delta
	# deliberately allows the short start/stop blend to settle deterministically.
	actor.call("set_locomotion", Vector2.RIGHT * 40.0, 0.0, 0.30)
	actor.call("set_locomotion", Vector2.RIGHT * 40.0, stride_distance * 0.75, 0.30)
	var driven_walk: Dictionary = actor.call("get_locomotion_debug_snapshot")
	_check(str(driven_walk.get("direction", "")) == "right", "set_locomotion does not select the velocity direction")
	_check(bool(driven_walk.get("is_walking", false)), "set_locomotion did not enter walking state")
	actor.call("set_locomotion", Vector2.ZERO, 0.0, 0.30)
	var driven_stop: Dictionary = actor.call("get_locomotion_debug_snapshot")
	_check(not bool(driven_stop.get("is_walking", true)), "set_locomotion did not leave walking state after stopping")

	# Stop from contact frame 1.  The actor must hold that contact momentarily,
	# settle to the nearest neutral frame 2, then remain there without cycling.
	actor.call("set_actor", "一般居民", false, 101)
	var frame_distance := float(contract.get("frame_distance", 5.5))
	actor.call("set_locomotion", Vector2.RIGHT * 40.0, frame_distance * 1.10, 0.10)
	var contact_walk: Dictionary = actor.call("get_locomotion_debug_snapshot")
	_check(int(contact_walk.get("frame_index", -1)) == 1, "stop-settle fixture did not begin on contact frame 1")
	actor.call("set_locomotion", Vector2.ZERO, 0.0, 1.0 / 60.0)
	var stop_contact: Dictionary = actor.call("get_locomotion_debug_snapshot")
	_check(not bool(stop_contact.get("is_walking", true)), "contact stop remains in walking state")
	_check(int(stop_contact.get("frame_index", -1)) == 1, "stop hard-cut away from its contact frame")
	_check(int(stop_contact.get("stop_target_frame", -1)) == 2, "contact frame 1 does not settle toward nearest neutral frame 2")
	actor.call("set_locomotion", Vector2.ZERO, 0.0, stop_settle_seconds * 0.60)
	var settled_stop: Dictionary = actor.call("get_locomotion_debug_snapshot")
	_check(int(settled_stop.get("frame_index", -1)) == 2, "short stop transition did not reach neutral frame 2")
	var settled_anchor: Vector2 = settled_stop.get("feet_anchor", Vector2.ZERO)
	for _repeat in 8:
		actor.call("set_locomotion", Vector2.ZERO, 0.0, 1.0 / 60.0)
	var held_stop: Dictionary = actor.call("get_locomotion_debug_snapshot")
	_check(int(held_stop.get("frame_index", -1)) == 2, "stationary actor continued cycling after settling")
	_check(Vector2(held_stop.get("feet_anchor", Vector2.ZERO)).distance_to(settled_anchor) <= MAX_FEET_ANCHOR_DRIFT_PX, "feet anchor moved during stop settle")

	# Alternate noisy vectors around 45 degrees.  Once the actor has selected the
	# horizontal row, small separation perturbations must not flip it vertically.
	actor.call("set_actor", "一般居民", false, 202)
	actor.call("set_locomotion", Vector2.RIGHT * 40.0, 1.0, 1.0 / 60.0)
	actor.call("set_locomotion", Vector2.RIGHT * 40.0, 0.5, 0.20)
	for sample_index in 12:
		var noisy_velocity := Vector2(10.0, 10.8) if sample_index % 2 == 0 else Vector2(10.8, 10.0)
		actor.call("set_locomotion", noisy_velocity, 0.5, 1.0 / 60.0)
	var hysteresis_hold: Dictionary = actor.call("get_locomotion_debug_snapshot")
	_check(str(hysteresis_hold.get("direction", "")) == "right", "45-degree separation noise changed the horizontal direction row")
	actor.call("set_locomotion", Vector2(4.0, 20.0), 0.5, 1.0 / 60.0)
	var decisive_turn: Dictionary = actor.call("get_locomotion_debug_snapshot")
	_check(str(decisive_turn.get("direction", "")) == "down", "decisive vertical velocity did not clear direction hysteresis")
	actor.call("set_locomotion", Vector2(20.0, 4.0), 0.5, 1.0 / 60.0)
	var locked_turn: Dictionary = actor.call("get_locomotion_debug_snapshot")
	_check(str(locked_turn.get("direction", "")) == "down", "direction row ignored its short anti-jitter lock")
	actor.call("set_locomotion", Vector2(20.0, 4.0), 0.5, float(contract.get("direction_lock_seconds", 0.12)) + 0.01)
	var unlocked_turn: Dictionary = actor.call("get_locomotion_debug_snapshot")
	_check(str(unlocked_turn.get("direction", "")) == "right", "direction row remained locked after the anti-jitter interval")
	_check(int(unlocked_turn.get("opaque_body_draws", -1)) == 1, "locomotion snapshot does not guarantee one opaque body")


func _load_image(resource_path: String) -> Image:
	var image := Image.load_from_file(ProjectSettings.globalize_path(resource_path))
	_check(image != null and not image.is_empty(), "could not inspect PNG %s" % resource_path)
	if image == null or image.is_empty():
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


func _opaque_bottom(image: Image) -> int:
	for y in range(image.get_height() - 1, -1, -1):
		for x in image.get_width():
			if image.get_pixel(x, y).a > ALPHA_THRESHOLD:
				return y
	return -1


func _image_touches_edge(image: Image) -> bool:
	for x in image.get_width():
		if image.get_pixel(x, 0).a > ALPHA_THRESHOLD or image.get_pixel(x, image.get_height() - 1).a > ALPHA_THRESHOLD:
			return true
	for y in image.get_height():
		if image.get_pixel(0, y).a > ALPHA_THRESHOLD or image.get_pixel(image.get_width() - 1, y).a > ALPHA_THRESHOLD:
			return true
	return false


func _mean_rgba_difference(first: Image, second: Image, flip_second_x: bool) -> float:
	if first.get_size() != second.get_size() or first.is_empty():
		return 1.0
	var total := 0.0
	var width := first.get_width()
	var height := first.get_height()
	for y in height:
		for x in width:
			var other_x := width - 1 - x if flip_second_x else x
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(other_x, y)
			total += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) + absf(a.a - b.a)
	return total / float(width * height * 4)


func _string_values(value: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if value is Dictionary:
		for item: Variant in (value as Dictionary).values():
			result.append(str(item))
	elif value is Array or value is PackedStringArray:
		for item: Variant in value:
			result.append(str(item))
	return result


func _cell_size_from_variant(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(roundi(value.x), roundi(value.y))
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	if value is int or value is float:
		return Vector2i(int(value), int(value))
	return Vector2i.ZERO


func _vector2_from_variant(value: Variant) -> Variant:
	if value is Vector2:
		return value
	if value is Vector2i:
		return Vector2(value)
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is Dictionary and value.has("x") and value.has("y"):
		return Vector2(float(value["x"]), float(value["y"]))
	return null


func _circular_distance(first: float, second: float) -> float:
	var difference := absf(fposmod(first, 1.0) - fposmod(second, 1.0))
	return minf(difference, 1.0 - difference)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("NPC rig contract failed: %s" % message)


func _finish() -> void:
	if _failed:
		quit(1)
	else:
		print("NPC rig contract passed. Atlases=8 Grid=4x4 Cell=192 Frames=128 Directions=4")
		quit(0)
