class_name OversightHearingStage
extends Control

const BACKGROUND_PATH := "res://assets/images/ui/oversight_chamber_v1/oversight_chamber.png"

var _background: TextureRect
var _scrim: ColorRect
var _committee: PanelContainer
var _mayor_desk: PanelContainer
var _question_marker: Label
var _cue_label: Label
var _active_tween: Tween
var _case_id := ""
var _state := "empty"
var _animation_generation := 0
var _background_loaded := false


func _init() -> void:
	name = "OversightHearingStage"
	custom_minimum_size = Vector2(720, 390)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip_contents = true
	_build_scene()
	resized.connect(_layout_layers)
	show_empty()


func show_empty() -> void:
	_case_id = ""
	_state = "empty"
	_committee.modulate = Color(1, 1, 1, 0.38)
	_mayor_desk.modulate = Color(1, 1, 1, 0.22)
	_question_marker.hide()
	_cue_label.text = L10n.text("監察院已備妥質詢席；案件成立後將在此進行行政答辯。")
	_play_idle_motion()


func set_case(oversight_case: Dictionary) -> void:
	var next_case_id := str(oversight_case.get("id", ""))
	if next_case_id.is_empty():
		show_empty()
		return
	var changed := _case_id != next_case_id or _state != "questioning"
	_case_id = next_case_id
	_state = "questioning"
	_committee.modulate = Color.WHITE
	_mayor_desk.modulate = Color.WHITE
	_question_marker.show()
	var target_name := L10n.text(str(oversight_case.get("target_name", "市長")))
	var allegations: Array = oversight_case.get("allegations", [])
	var allegation_text := L10n.text(str(allegations.front())) if not allegations.is_empty() else L10n.text("行政調查")
	(_mayor_desk.get_node("DeskLabel") as Label).text = L10n.text("%s答辯席") % target_name
	_cue_label.text = L10n.text("監察委員質詢：%s｜請於表決日前提出答辯。") % allegation_text
	if changed:
		_play_question_animation()


func play_defense(defense_id: String) -> void:
	if _case_id.is_empty() or defense_id.is_empty():
		return
	_state = "defense_submitted"
	_cue_label.text = L10n.text("答辯資料已遞交監察委員會，案件將依原定日期進入表決。")
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_animation_generation += 1
	_mayor_desk.modulate = Color(0.75, 1.0, 0.82, 0.35)
	_active_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(_mayor_desk, "modulate", Color.WHITE, 0.42)
	_active_tween.parallel().tween_property(_question_marker, "modulate:a", 0.25, 0.2)
	_active_tween.tween_property(_question_marker, "modulate:a", 1.0, 0.2)


func debug_signature() -> Dictionary:
	return {
		"visible": visible,
		"background_path": BACKGROUND_PATH,
		"background_loaded": _background_loaded,
		"state": _state,
		"case_id": _case_id,
		"question_visible": _question_marker.visible,
		"committee_visible": _committee.visible,
		"mayor_desk_visible": _mayor_desk.visible,
		"animation_generation": _animation_generation,
		"animation_running": _active_tween != null and _active_tween.is_valid(),
	}


func _build_scene() -> void:
	_background = TextureRect.new()
	_background.name = "OversightChamberBackground"
	_background.texture = ResourceLoader.load(BACKGROUND_PATH, "Texture2D") as Texture2D
	_background_loaded = _background.texture != null
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)
	_scrim = ColorRect.new()
	_scrim.name = "OversightChamberScrim"
	_scrim.color = Color(0.015, 0.08, 0.09, 0.22)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scrim)
	_committee = _desk("OversightCommitteeDais", "監察委員會｜行政質詢", Color(0.05, 0.34, 0.36, 0.94))
	add_child(_committee)
	_mayor_desk = _desk("OversightMayorDesk", "市長答辯席", Color(0.45, 0.23, 0.10, 0.94))
	add_child(_mayor_desk)
	_question_marker = Label.new()
	_question_marker.name = "OversightQuestionMarker"
	_question_marker.text = L10n.text("質詢中")
	_question_marker.add_theme_font_size_override("font_size", 20)
	_question_marker.add_theme_color_override("font_color", Color(1.0, 0.92, 0.62))
	_question_marker.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.92))
	_question_marker.add_theme_constant_override("shadow_offset_x", 2)
	_question_marker.add_theme_constant_override("shadow_offset_y", 2)
	_question_marker.set_meta("l10n_skip", true)
	add_child(_question_marker)
	_cue_label = Label.new()
	_cue_label.name = "OversightHearingCue"
	_cue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cue_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cue_label.add_theme_font_size_override("font_size", 17)
	_cue_label.add_theme_color_override("font_color", Color.WHITE)
	_cue_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_cue_label.add_theme_constant_override("shadow_offset_x", 2)
	_cue_label.add_theme_constant_override("shadow_offset_y", 2)
	_cue_label.set_meta("l10n_skip", true)
	add_child(_cue_label)
	call_deferred("_layout_layers")


func _desk(node_name: String, text: String, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.95, 0.76, 0.36, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.name = "DeskLabel"
	label.text = L10n.text(text)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.set_meta("l10n_skip", true)
	panel.add_child(label)
	return panel


func _layout_layers() -> void:
	var bounds := size
	_background.position = Vector2.ZERO
	_background.size = bounds
	_scrim.position = Vector2.ZERO
	_scrim.size = bounds
	_committee.position = Vector2(bounds.x * 0.28, bounds.y * 0.12)
	_committee.size = Vector2(bounds.x * 0.44, bounds.y * 0.14)
	_mayor_desk.position = Vector2(bounds.x * 0.30, bounds.y * 0.60)
	_mayor_desk.size = Vector2(bounds.x * 0.40, bounds.y * 0.15)
	_question_marker.position = Vector2(bounds.x * 0.09, bounds.y * 0.31)
	_question_marker.size = Vector2(bounds.x * 0.22, 34)
	_cue_label.position = Vector2(bounds.x * 0.12, bounds.y - 54)
	_cue_label.size = Vector2(bounds.x * 0.76, 40)


func _play_idle_motion() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_animation_generation += 1
	_active_tween = create_tween().set_loops()
	_active_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_active_tween.tween_property(_committee, "modulate:a", 0.58, 0.72)
	_active_tween.parallel().tween_property(_mayor_desk, "modulate:a", 0.32, 0.72)
	_active_tween.tween_property(_committee, "modulate:a", 0.38, 0.72)
	_active_tween.parallel().tween_property(_mayor_desk, "modulate:a", 0.22, 0.72)


func _play_question_animation() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_animation_generation += 1
	_question_marker.modulate = Color(1.0, 0.92, 0.62, 0.0)
	_mayor_desk.modulate = Color(1, 1, 1, 0.35)
	_active_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(_question_marker, "modulate:a", 1.0, 0.24)
	_active_tween.parallel().tween_property(_mayor_desk, "modulate:a", 1.0, 0.24)
