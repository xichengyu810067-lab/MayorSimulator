class_name CourtroomStage
extends Control

const SceneWorkflowShellScript = preload("res://ui/governance/scene_workflow_shell.gd")

const BACKGROUND_PATH := "res://assets/images/ui/courtroom_v1/courtroom_interior.png"
const JUDICIAL_PANEL_PATH := "res://assets/images/ui/courtroom_v1/judicial_panel.png"
const DEFENSE_TABLE_PATH := "res://assets/images/ui/courtroom_v1/defense_table.png"
const COURT_CLERK_PATH := "res://assets/images/ui/courtroom_v1/court_clerk.png"

const STAGE_LABELS := {
	"filed": "立案",
	"preparation": "書狀與證據準備",
	"hearing": "開庭陳述",
	"deliberation": "合議評議",
	"judgment": "宣判",
}
const STAGE_CUES := {
	"filed": "書記官完成收案，合議庭已排定程序。",
	"preparation": "雙方整理書狀、事實與證據，等待開庭。",
	"hearing": "合議庭聽取陳述並核對證據。",
	"deliberation": "法官進入合議，當事人等待裁判。",
	"judgment": "合議庭宣示裁判結果與法律效果。",
}

var _background: TextureRect
var _judges: TextureRect
var _defense: TextureRect
var _clerk: TextureRect
var _scrim: ColorRect
var _stage_badge: Label
var _cue_label: Label
var _last_case_id := ""
var _last_stage := ""
var _active_tween: Tween
var _shell


func _init() -> void:
	name = "CourtroomStage"
	custom_minimum_size = Vector2(720, 420)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true
	_build_scene()
	resized.connect(_layout_layers)
	call_deferred("_layout_layers")


func top_content() -> HBoxContainer:
	return _shell.top_content


func tray_content() -> VBoxContainer:
	return _shell.tray_content


func set_dark_mode(enabled: bool) -> void:
	_shell.set_dark_mode(enabled)


func debug_signature() -> Dictionary:
	var shell_signature: Dictionary = _shell.debug_signature()
	return {
		"background_path": BACKGROUND_PATH,
		"background_loaded": _shell.is_background_loaded(),
		"root_is_scroll_container": false,
		"top_rect": shell_signature.get("top_rect", Rect2()),
		"tray_rect": shell_signature.get("tray_rect", Rect2()),
		"stage_rect": get_rect(),
		"actor_layer_count": 3,
		"stage": _last_stage,
	}


func set_case(court_case: Dictionary) -> void:
	var case_id := str(court_case.get("id", ""))
	var stage := str(court_case.get("procedural_stage", "filed"))
	if not STAGE_LABELS.has(stage):
		stage = "filed"
	_stage_badge.text = L10n.text("法院程序｜%s") % L10n.text(str(STAGE_LABELS[stage]))
	_cue_label.text = L10n.text(str(STAGE_CUES[stage]))
	# Refresh proportional positions before recording Tween targets. The panel
	# may receive its first case in the same frame that its container is sized.
	_layout_layers()
	_apply_stage_visibility(stage)
	var changed := case_id != _last_case_id or stage != _last_stage
	_last_case_id = case_id
	_last_stage = stage
	if changed and not case_id.is_empty():
		_play_stage_transition(stage)


func show_empty() -> void:
	_stage_badge.text = L10n.text("法院程序｜目前無案件")
	_cue_label.text = L10n.text("法院已準備就緒；違法強制施政後會在此顯示案件。")
	for actor in [_judges, _defense, _clerk]:
		(actor as TextureRect).modulate = Color(1, 1, 1, 0.18)
	_last_case_id = ""
	_last_stage = ""


func _build_scene() -> void:
	_shell = SceneWorkflowShellScript.new(BACKGROUND_PATH)
	_shell.name = "CourtroomWorkflowShell"
	# The judicial tray also contains the five-stage timeline and three defense
	# choices. Reserve enough height for the complete interaction row at native
	# fullscreen scale instead of clipping its lower edge.
	_shell.set_tray_height(350.0)
	add_child(_shell)
	_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background = _shell.background
	_scrim = _shell.scrim
	_judges = _texture_layer(JUDICIAL_PANEL_PATH)
	_clerk = _texture_layer(COURT_CLERK_PATH)
	_defense = _texture_layer(DEFENSE_TABLE_PATH)
	_shell.scene_host.add_child(_judges)
	_shell.scene_host.add_child(_clerk)
	_shell.scene_host.add_child(_defense)

	_stage_badge = Label.new()
	_stage_badge.name = "CourtroomStageBadge"
	_stage_badge.add_theme_font_size_override("font_size", 18)
	_stage_badge.add_theme_color_override("font_color", Color(1.0, 0.96, 0.84))
	_stage_badge.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_stage_badge.add_theme_constant_override("shadow_offset_x", 2)
	_stage_badge.add_theme_constant_override("shadow_offset_y", 2)
	_stage_badge.custom_minimum_size = Vector2(180, 44)
	_stage_badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stage_badge.clip_text = true
	_stage_badge.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_stage_badge.set_meta("l10n_skip", true)
	_shell.top_content.add_child(_stage_badge)

	_cue_label = Label.new()
	_cue_label.name = "CourtroomStageCue"
	_cue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cue_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cue_label.add_theme_font_size_override("font_size", 17)
	_cue_label.add_theme_color_override("font_color", Color.WHITE)
	_cue_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_cue_label.add_theme_constant_override("shadow_offset_x", 2)
	_cue_label.add_theme_constant_override("shadow_offset_y", 2)
	_cue_label.custom_minimum_size = Vector2(0, 34)
	_cue_label.set_meta("l10n_skip", true)
	_shell.tray_content.add_child(_cue_label)


func _texture_layer(path: String) -> TextureRect:
	var layer := TextureRect.new()
	var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
	if texture != null:
		layer.texture = texture
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return layer


func _layout_layers() -> void:
	var bounds := size
	_judges.position = Vector2(bounds.x * 0.22, bounds.y * 0.14)
	_judges.size = Vector2(bounds.x * 0.56, bounds.y * 0.46)
	_clerk.position = Vector2(bounds.x * 0.55, bounds.y * 0.41)
	_clerk.size = Vector2(bounds.x * 0.23, bounds.y * 0.34)
	_defense.position = Vector2(bounds.x * 0.02, bounds.y * 0.50)
	_defense.size = Vector2(bounds.x * 0.52, bounds.y * 0.46)


func _apply_stage_visibility(stage: String) -> void:
	var judge_alpha := 1.0
	var defense_alpha := 1.0
	var clerk_alpha := 1.0
	match stage:
		"filed":
			judge_alpha = 0.0
			defense_alpha = 0.0
		"preparation":
			judge_alpha = 0.0
		"deliberation":
			defense_alpha = 0.0
			clerk_alpha = 0.0
	_judges.modulate = Color(1, 1, 1, judge_alpha)
	_defense.modulate = Color(1, 1, 1, defense_alpha)
	_clerk.modulate = Color(1, 1, 1, clerk_alpha)


func _play_stage_transition(stage: String) -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	var actor := _judges
	if stage in ["filed", "preparation"]:
		actor = _clerk
	elif stage == "hearing":
		actor = _defense
	var target_modulate := actor.modulate
	actor.modulate.a = 0.0
	_active_tween = create_tween()
	_active_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(actor, "modulate", target_modulate, 0.28)
