class_name IntroCinematic
extends Control

const StorySequence = preload("res://data/tutorial/story_sequence.gd")

signal completed
signal load_failed(message: String)

var current_index := 0
var current_texture: Texture2D
var next_texture: Texture2D
var _completed_emitted := false
var _closing := false
var _transition: Tween
var _ambient_tween: Tween
var current_layer: TextureRect
var next_layer: TextureRect
var parallax_tint: ColorRect
var title_label: Label
var subtitle_label: Label
var error_label: Label
var next_button: Button
var animation_player: AnimationPlayer


func _init() -> void:
	name = "IntroCinematic"
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func open() -> bool:
	if not StorySequence.is_valid():
		_fail_closed("開場動畫資料無效，無法安全播放。")
		return false
	_completed_emitted = false
	_closing = false
	current_index = 0
	if not _set_initial_shot():
		return false
	show()
	modulate.a = 0.0
	var fade := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade.tween_property(self, "modulate:a", 1.0, 0.28)
	next_button.grab_focus()
	return true


func advance() -> void:
	if not visible or _closing:
		return
	if current_index >= StorySequence.SHOTS.size() - 1:
		_finish()
		return
	current_index += 1
	if next_texture == null:
		_fail_closed("下一個開場鏡頭遺失，動畫已安全停止。")
		return
	if _transition != null and _transition.is_valid():
		_transition.kill()
	next_layer.modulate.a = 0.0
	next_layer.show()
	_transition = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_transition.set_parallel(true)
	_transition.tween_property(current_layer, "modulate:a", 0.0, 0.34)
	_transition.tween_property(next_layer, "modulate:a", 1.0, 0.34)
	_transition.set_parallel(false)
	_transition.tween_callback(_commit_advanced_shot)


func close() -> void:
	if _closing:
		return
	_closing = true
	_release_textures()
	hide()


func resident_texture_count() -> int:
	var count := 0
	if current_texture != null:
		count += 1
	if next_texture != null:
		count += 1
	return count


func _exit_tree() -> void:
	_release_textures()


func _set_initial_shot() -> bool:
	_release_textures()
	current_texture = _load_fixed_shot(current_index)
	if current_texture == null:
		return false
	next_texture = _load_fixed_shot(current_index + 1)
	if next_texture == null:
		return false
	current_layer.texture = current_texture
	current_layer.modulate.a = 1.0
	next_layer.texture = next_texture
	next_layer.modulate.a = 0.0
	_apply_text()
	_start_parallax()
	return true


func _commit_advanced_shot() -> void:
	current_texture = next_texture
	current_layer.texture = current_texture
	current_layer.modulate.a = 1.0
	next_layer.hide()
	next_layer.texture = null
	next_texture = _load_fixed_shot(current_index + 1) if current_index + 1 < StorySequence.SHOTS.size() else null
	if current_index + 1 < StorySequence.SHOTS.size() and next_texture == null:
		return
	next_layer.texture = next_texture
	_apply_text()
	_start_parallax()


func _load_fixed_shot(index: int) -> Texture2D:
	if index < 0 or index >= StorySequence.SHOTS.size():
		return null
	var path := str(StorySequence.SHOTS[index]["asset"])
	if not path.begins_with("res://assets/images/tutorial/cg_v1/shot_") or not ResourceLoader.exists(path):
		_fail_closed("開場 CG 素材遺失：%s" % path)
		return null
	var resource := load(path)
	if not resource is Texture2D:
		_fail_closed("開場 CG 素材格式無效：%s" % path)
		return null
	return resource as Texture2D


func _apply_text() -> void:
	var shot: Dictionary = StorySequence.SHOTS[current_index]
	title_label.text = _l10n(str(shot["title"]))
	subtitle_label.text = _l10n(str(shot["subtitle"]))
	next_button.text = _l10n("進入城市") if current_index == StorySequence.SHOTS.size() - 1 else _l10n("下一步")


func _start_parallax() -> void:
	if _ambient_tween != null and _ambient_tween.is_valid():
		_ambient_tween.kill()
	current_layer.scale = Vector2(1.0, 1.0)
	current_layer.position = Vector2.ZERO
	parallax_tint.modulate.a = 0.18
	animation_player.play("shot_ambient")
	_ambient_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	_ambient_tween.tween_property(current_layer, "scale", Vector2(1.06, 1.06), 5.0)
	_ambient_tween.tween_property(current_layer, "position", Vector2(-28, -16), 5.0)
	_ambient_tween.tween_property(parallax_tint, "modulate:a", 0.30, 2.5).set_trans(Tween.TRANS_SINE)


func _finish() -> void:
	if _completed_emitted:
		return
	_completed_emitted = true
	close()
	completed.emit()


func _fail_closed(message: String) -> void:
	if _closing:
		return
	_closing = true
	_release_textures()
	current_layer.hide()
	next_layer.hide()
	error_label.text = message
	error_label.show()
	show()
	load_failed.emit(message)


func _release_textures() -> void:
	current_texture = null
	next_texture = null
	if is_instance_valid(current_layer):
		current_layer.texture = null
	if is_instance_valid(next_layer):
		next_layer.texture = null


func _l10n(source: String) -> String:
	var localization := get_node_or_null("/root/L10n")
	return str(localization.call("text", source)) if localization != null else source


func _build() -> void:
	for node_name in ["CurrentLayer", "NextLayer"]:
		var layer := TextureRect.new()
		layer.name = node_name
		layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(layer)
		if node_name == "CurrentLayer":
			current_layer = layer
		else:
			next_layer = layer
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.06, 0.28)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	parallax_tint = ColorRect.new()
	parallax_tint.color = Color(1.0, 0.68, 0.28, 0.20)
	parallax_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parallax_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(parallax_tint)
	var text_box := VBoxContainer.new()
	text_box.name = "CinematicSubtitles"
	text_box.anchor_left = 0.08
	text_box.anchor_top = 0.73
	text_box.anchor_right = 0.92
	text_box.anchor_bottom = 0.94
	text_box.add_theme_constant_override("separation", 8)
	add_child(text_box)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 34)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.91, 0.70))
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(title_label)
	subtitle_label = Label.new()
	subtitle_label.add_theme_font_size_override("font_size", 21)
	subtitle_label.add_theme_color_override("font_color", Color.WHITE)
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(subtitle_label)
	next_button = Button.new()
	next_button.name = "CinematicNextButton"
	next_button.custom_minimum_size = Vector2(144, 48)
	next_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	next_button.pressed.connect(advance)
	text_box.add_child(next_button)
	error_label = Label.new()
	error_label.name = "CinematicError"
	error_label.add_theme_font_size_override("font_size", 24)
	error_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.68))
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	error_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	error_label.hide()
	add_child(error_label)
	animation_player = AnimationPlayer.new()
	animation_player.name = "CinematicAnimationPlayer"
	add_child(animation_player)
	var library := AnimationLibrary.new()
	var animation := Animation.new()
	animation.length = 5.0
	library.add_animation("shot_ambient", animation)
	animation_player.add_animation_library("", library)
