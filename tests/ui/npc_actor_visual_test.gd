extends SceneTree

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var actor_script = load("res://scripts/world/npc_actor.gd")
	_check(actor_script != null, "NPC actor script could not be loaded")
	if actor_script == null:
		quit(1)
		return
	var actor: Button = actor_script.new()
	actor.size = Vector2(38, 46)
	root.add_child(actor)
	await process_frame

	_check(actor.custom_minimum_size.x >= 52.0 and actor.custom_minimum_size.y >= 68.0, "NPC hit target is smaller than the proportional 52x68 actor")
	_check(actor.size.x >= 52.0 and actor.size.y >= 68.0, "NPC runtime rect did not grow to the proportional actor size")
	_check(actor.mouse_filter == Control.MOUSE_FILTER_STOP, "NPC does not capture pointer input")
	_check(actor.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND, "NPC lacks clickable cursor feedback")
	_check(actor.text.is_empty(), "NPC button leaked label text into the map")

	var role_colors: Dictionary = {}
	var unique_colors: Dictionary = {}
	var unique_sprites: Dictionary = {}
	for role in ["一般居民", "學生", "商人", "老年居民", "工人", "公務人員", "議員"]:
		actor.call("set_actor", role, false)
		role_colors[role] = actor.call("_outfit_color")
		unique_colors[str(role_colors[role])] = true
		var sprite_path := str(actor.call("sprite_path_for_type", role))
		unique_sprites[sprite_path] = true
		_check(ResourceLoader.exists(sprite_path), "NPC sprite is missing for role %s" % role)
		var role_texture := load(sprite_path) as Texture2D
		_check(role_texture != null, "NPC sprite could not be loaded for role %s" % role)
		if role_texture != null:
			_check(role_texture.get_width() == 384 and role_texture.get_height() == 512, "NPC sprite delivery size is not 384x512 for role %s" % role)
		var source_image := Image.load_from_file(ProjectSettings.globalize_path(sprite_path))
		_check(source_image != null and not source_image.is_empty(), "NPC source PNG could not be inspected for role %s" % role)
		if source_image != null and not source_image.is_empty():
			_check(not _image_touches_edge(source_image), "NPC opaque pixels touch a delivery edge for role %s" % role)
			_check(source_image.get_pixel(0, 0).a <= 0.01, "NPC transparent background is not clean for role %s" % role)
		_check(actor.tooltip_text == role, "NPC tooltip did not track role %s" % role)
	_check(unique_colors.size() == 7, "NPC role palette is incomplete")
	_check(unique_sprites.size() == 7, "NPC role sprite catalog is incomplete")
	actor.call("set_actor", "一般居民", false, 1)
	var resident_variant_path := str((actor.get("actor_texture") as Texture2D).resource_path)
	_check(resident_variant_path.ends_with("npc-resident-florist.png"), "General-resident appearance variant was not selected")
	_check(ResourceLoader.exists(resident_variant_path), "General-resident appearance variant is missing")

	actor.call("set_motion", true, 1.25, -1.0)
	_check(bool(actor.get("is_walking")), "NPC walking state was not preserved")
	_check(is_equal_approx(float(actor.get("motion_phase")), 1.25), "NPC animation phase was not preserved")
	_check(is_equal_approx(float(actor.get("facing_sign")), -1.0), "NPC horizontal facing was not preserved")
	_check(float(actor.get("turn_reaction_remaining")) > 0.0, "NPC direction change has no short turn reaction")

	actor.call("set_expression", "proud", 0.65)
	_check(str(actor.get("expression_state")) == "proud", "NPC proud expression was not preserved")
	_check(is_equal_approx(float(actor.get("expression_intensity")), 0.65), "NPC expression intensity was not preserved")
	actor.call("set_expression", "not-a-real-expression", 1.8)
	_check(str(actor.get("expression_state")) == "calm", "unknown NPC expression did not fall back to calm")
	_check(is_equal_approx(float(actor.get("expression_intensity")), 1.0), "NPC expression intensity was not clamped")

	actor.call("set_actor", "一般居民", false, 0)
	actor.call("set_motion", false, 0.6, 1.0)
	_check(float(actor.call("blink_amount")) > 0.95, "NPC blink curve has no visible closed-eye peak")
	actor.call("set_motion", false, 3.0, 1.0)
	_check(is_zero_approx(float(actor.call("blink_amount"))), "NPC blink remains permanently closed outside its blink window")
	actor.call("play_interaction_reaction")
	_check(str(actor.call("visual_expression")) == "happy", "NPC click reaction does not temporarily select a happy expression")
	_check(float(actor.call("interaction_amount")) > 0.95, "NPC click reaction did not start at full strength")
	actor.call("_process", 0.25)
	_check(float(actor.call("interaction_amount")) < 0.95 and float(actor.call("interaction_amount")) > 0.0, "NPC click reaction does not decay smoothly")

	actor.queue_free()
	if _failed:
		quit(1)
	else:
		print("NPC actor visual-state test passed.")
		quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)


func _image_touches_edge(image: Image) -> bool:
	for x in image.get_width():
		if image.get_pixel(x, 0).a > 0.02 or image.get_pixel(x, image.get_height() - 1).a > 0.02:
			return true
	for y in image.get_height():
		if image.get_pixel(0, y).a > 0.02 or image.get_pixel(image.get_width() - 1, y).a > 0.02:
			return true
	return false
