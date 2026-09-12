class_name LowerCouncilStage
extends Control

const SceneWorkflowShellScript = preload("res://ui/governance/scene_workflow_shell.gd")
const SemanticPalette = preload("res://ui/theme/semantic_palette.gd")

signal response_selected(response_id: String)
signal response_confirmed(response_id: String)

const BACKGROUND_PATH := "res://assets/images/ui/legislative_chamber_v1/legislative_chamber.png"
const MEMBER_PATH := "res://assets/images/characters/npc/npc-council-member.png"
const SEAT_COUNT := 30
const MAJORITY_THRESHOLD := 16
const HEARING_TRAY_HEIGHT := 240.0
const CATALOG_TRAY_HEIGHT := 300.0
const FINAL_TRAY_HEIGHT := 190.0

var response_buttons: Array[Button] = []
var confirm_button: Button

var _shell
var _scene: Control
var _seat_grid: GridContainer
var _seats: Array[PanelContainer] = []
var _seat_portraits: Array[TextureRect] = []
var _status_label: Label
var _question_label: Label
var _preview_label: Label
var _response_row: HBoxContainer
var _catalog_host: VBoxContainer
var _catalog_header_host: HBoxContainer
var _hearing_host: VBoxContainer
var _selected_response_id := ""
var _response_signature := ""
var _latest_preview: Dictionary = {}
var _latest_decision_signature := ""
var _active_tween: Tween
var _animation_generation := 0
var _vote_reveal_step_count := 0
var _revealed_seat_count := 0
var _background_loaded := false
var _authority_seat_count := SEAT_COUNT
var _authority_majority_threshold := MAJORITY_THRESHOLD
var _authority_contract_valid := true
var _layout_columns := 10
var _stage_state := "idle"
var _dark_mode := false


func _init() -> void:
	name = "LowerCouncilStage"
	custom_minimum_size = Vector2(720, 420)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_stage()
	_show_idle()


func catalog_host() -> VBoxContainer:
	return _catalog_host


func catalog_header_host() -> HBoxContainer:
	return _catalog_header_host


func set_dark_mode(enabled: bool) -> void:
	_dark_mode = enabled
	_shell.set_dark_mode(enabled)
	var primary := SemanticPalette.color_for(enabled, "text_primary")
	var secondary := SemanticPalette.color_for(enabled, "text_secondary")
	_status_label.add_theme_color_override("font_color", primary)
	_question_label.add_theme_color_override("font_color", primary)
	_preview_label.add_theme_color_override("font_color", secondary)
	_style_action_button(confirm_button, true)
	for button in response_buttons:
		_style_action_button(button, false)
	for seat: PanelContainer in _seats:
		_style_vote_seat(seat, str(seat.get_meta("vote_choice", "abstain")), float(seat.get_meta("vote_intensity", 0.24)))


func refresh(pending_bill: Dictionary, bill_definition: Dictionary, latest_decision: Dictionary = {}) -> void:
	if str(pending_bill.get("status", "")) == "awaiting_mayor_response":
		_show_hearing(pending_bill, bill_definition)
		return
	if not latest_decision.is_empty():
		_show_final_decision(latest_decision)
		return
	_show_idle()


func set_catalog_focus(focus_state: String, focus_text: String) -> void:
	if focus_state not in ["policy_selected", "bill_selected", "bill_review"]:
		return
	_stage_state = focus_state
	_set_workflow_mode(false)
	_status_label.text = L10n.text("下議院議事廳｜%s") % L10n.text(focus_text)
	_apply_vote_snapshot([], true)
	_play_ambient_motion()


func set_preview(preview: Dictionary) -> void:
	if not bool(preview.get("ok", false)) or not bool(preview.get("readonly", false)):
		_latest_preview.clear()
		_preview_label.text = L10n.text("尚未選擇答詢方案；預覽不會寫入正式票史。")
		confirm_button.disabled = true
		return
	var preview_votes: Array = preview.get("votes", [])
	_update_authority_values(preview_votes.size(), int(preview.get("majority_threshold", 0)))
	_latest_preview = preview.duplicate(true)
	_selected_response_id = str(preview.get("response_id", ""))
	_preview_label.text = L10n.text("唯讀表決預覽｜贊成 %d｜反對 %d｜棄權 %d｜缺席 %d｜門檻 %d") % [
		int(preview.get("votes_for", 0)),
		int(preview.get("votes_against", 0)),
		int(preview.get("abstentions", 0)),
		int(preview.get("absences", 0)),
		_authority_majority_threshold,
	]
	confirm_button.disabled = _selected_response_id.is_empty() or not _authority_contract_valid


func select_response_for_test(index: int) -> void:
	if index < 0 or index >= response_buttons.size():
		return
	var button := response_buttons[index]
	button.set_pressed_no_signal(true)
	_on_response_pressed(str(button.get_meta("response_id", "")))


func confirm_response_for_test() -> void:
	if not confirm_button.disabled:
		confirm_button.emit_signal("pressed")


func debug_signature() -> Dictionary:
	var shell_signature: Dictionary = _shell.debug_signature()
	return {
		"visible": visible,
		"background_path": BACKGROUND_PATH,
		"background_loaded": _background_loaded,
		"member_asset_path": MEMBER_PATH,
		"seat_count": _authority_seat_count,
		"rendered_seat_count": _seats.size(),
		"majority_threshold": _authority_majority_threshold,
		"authority_contract_valid": _authority_contract_valid,
		"columns": _layout_columns,
		"primary_question": _question_label.text,
		"response_option_count": response_buttons.size(),
		"response_row_visible": _response_row.visible,
		"confirm_visible": confirm_button.visible,
		"confirm_disabled": confirm_button.disabled,
		"selected_response_id": _selected_response_id,
		"readonly_preview": not _latest_preview.is_empty() and bool(_latest_preview.get("readonly", false)),
		"preview_votes_for": int(_latest_preview.get("votes_for", 0)),
		"preview_votes_against": int(_latest_preview.get("votes_against", 0)),
		"vote_reveal_step_count": _vote_reveal_step_count,
		"revealed_seat_count": _revealed_seat_count,
		"animation_generation": _animation_generation,
		"animation_running": _active_tween != null and _active_tween.is_valid(),
		"stage_state": _stage_state,
		"decision_signature": _latest_decision_signature,
		"catalog_visible": _catalog_host.visible,
		"catalog_header_visible": _catalog_header_host.visible,
		"hearing_controls_visible": _hearing_host.visible,
		"portrait_count": _seat_portraits.size(),
		"visible_portrait_count": _visible_portrait_count(),
		"seat_surface_max_alpha": _seat_surface_max_alpha(),
		"vote_color_group_count": _vote_color_group_count(),
		"dark_mode": _dark_mode,
		"root_is_scroll_container": false,
		"top_rect": shell_signature.get("top_rect", Rect2()),
		"tray_rect": shell_signature.get("tray_rect", Rect2()),
		"top_minimum_size": shell_signature.get("top_minimum_size", Vector2.ZERO),
		"tray_minimum_size": shell_signature.get("tray_minimum_size", Vector2.ZERO),
		"seat_grid_rect": _seat_grid.get_rect(),
		"first_seat_rect": _seats[0].get_rect() if not _seats.is_empty() else Rect2(),
		"stage_rect": get_rect(),
	}


func _build_stage() -> void:
	_shell = SceneWorkflowShellScript.new(BACKGROUND_PATH)
	_shell.name = "LowerCouncilWorkflowShell"
	_shell.set_tray_height(CATALOG_TRAY_HEIGHT)
	add_child(_shell)
	_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shell.layout_updated.connect(_queue_scene_layout)
	_background_loaded = _shell.is_background_loaded()
	_scene = _shell.scene_host
	_scene.name = "LowerCouncilChamberVisual"

	_seat_grid = GridContainer.new()
	_seat_grid.name = "LowerCouncilSeatGrid"
	_seat_grid.columns = 10
	_seat_grid.add_theme_constant_override("h_separation", 6)
	_seat_grid.add_theme_constant_override("v_separation", 5)
	_scene.add_child(_seat_grid)
	var member_texture := ResourceLoader.load(MEMBER_PATH, "Texture2D") as Texture2D
	for index in SEAT_COUNT:
		var seat := PanelContainer.new()
		seat.name = "LowerCouncilSeat_%02d" % (index + 1)
		seat.tooltip_text = L10n.text("下議院第 %d 席") % (index + 1)
		seat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seat.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var portrait := TextureRect.new()
		portrait.texture = member_texture
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.custom_minimum_size = Vector2(38, 44)
		seat.add_child(portrait)
		_seat_grid.add_child(seat)
		_seats.append(seat)
		_seat_portraits.append(portrait)
		_style_vote_seat(seat, "abstain", 0.24)

	_status_label = Label.new()
	_status_label.name = "LowerCouncilStatus"
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 20)
	_status_label.set_meta("l10n_skip", true)
	_shell.top_content.add_child(_status_label)
	_catalog_header_host = HBoxContainer.new()
	_catalog_header_host.name = "LowerCouncilCatalogHeaderHost"
	_catalog_header_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalog_header_host.add_theme_constant_override("separation", 8)
	_shell.top_content.add_child(_catalog_header_host)

	_catalog_host = VBoxContainer.new()
	_catalog_host.name = "LowerCouncilCatalogHost"
	_catalog_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalog_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_catalog_host.add_theme_constant_override("separation", 4)
	_shell.tray_content.add_child(_catalog_host)

	_hearing_host = VBoxContainer.new()
	_hearing_host.name = "LowerCouncilHearingControls"
	_hearing_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hearing_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hearing_host.add_theme_constant_override("separation", 6)
	_shell.tray_content.add_child(_hearing_host)

	_question_label = Label.new()
	_question_label.name = "LowerCouncilPrimaryQuestion"
	_question_label.add_theme_font_size_override("font_size", 18)
	_question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_question_label.max_lines_visible = 2
	_question_label.custom_minimum_size = Vector2(0, 42)
	_question_label.set_meta("l10n_skip", true)
	_hearing_host.add_child(_question_label)

	_response_row = HBoxContainer.new()
	_response_row.name = "LowerCouncilResponseOptions"
	_response_row.add_theme_constant_override("separation", 10)
	_response_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hearing_host.add_child(_response_row)

	var action_row := HBoxContainer.new()
	action_row.name = "LowerCouncilConfirmationRow"
	action_row.add_theme_constant_override("separation", 12)
	_hearing_host.add_child(action_row)
	_preview_label = Label.new()
	_preview_label.name = "LowerCouncilReadonlyPreview"
	_preview_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_label.max_lines_visible = 2
	_preview_label.custom_minimum_size = Vector2(0, 48)
	_preview_label.add_theme_font_size_override("font_size", 16)
	_preview_label.set_meta("l10n_skip", true)
	action_row.add_child(_preview_label)
	confirm_button = Button.new()
	confirm_button.name = "LowerCouncilConfirmResponse"
	confirm_button.text = L10n.text("確認答詢並進行正式表決")
	confirm_button.set_meta("semantic_label", "確認答詢並進行正式表決")
	confirm_button.custom_minimum_size = Vector2(258, 48)
	confirm_button.add_theme_font_size_override("font_size", 18)
	confirm_button.disabled = true
	confirm_button.pressed.connect(_on_confirm_pressed)
	action_row.add_child(confirm_button)

	resized.connect(_relayout_stage)
	set_dark_mode(false)
	call_deferred("_relayout_stage")


func _show_hearing(pending_bill: Dictionary, bill_definition: Dictionary) -> void:
	_stage_state = "hearing"
	_set_workflow_mode(true, false)
	var hearing: Dictionary = pending_bill.get("lower_house_hearing", {})
	_update_authority_values(int(hearing.get("seat_count", 0)), int(hearing.get("majority_threshold", 0)))
	var bill_name := L10n.text(str(bill_definition.get("name", pending_bill.get("bill_id", "法案"))))
	_status_label.text = L10n.text("《%s》下議院答詢｜%d 席｜通過門檻 %d") % [bill_name, _authority_seat_count, _authority_majority_threshold]
	_question_label.text = L10n.text(str(hearing.get("primary_question", "下議院正在等待市長答詢。")))
	var options: Array = hearing.get("response_options", [])
	var new_signature := JSON.stringify(options).sha256_text()
	if new_signature != _response_signature:
		_response_signature = new_signature
		_rebuild_response_buttons(options)
	_reset_hearing_interaction()
	_apply_vote_snapshot(hearing.get("initial_vote", {}).get("votes", []), false)


func _show_final_decision(decision: Dictionary) -> void:
	_stage_state = "final_vote"
	_set_workflow_mode(true, true)
	_selected_response_id = ""
	_latest_preview.clear()
	var final_vote: Dictionary = decision.get("final_vote", {})
	var final_votes: Array = final_vote.get("votes", [])
	_update_authority_values(final_votes.size(), int(final_vote.get("majority_threshold", 0)))
	var bill_name := L10n.text(str(decision.get("name", decision.get("bill_id", "法案"))))
	_status_label.text = L10n.text("《%s》下議院正式表決｜贊成 %d｜門檻 %d") % [bill_name, int(final_vote.get("votes_for", 0)), _authority_majority_threshold]
	_question_label.text = L10n.text("正式表決已完成，結果已接續送交上議院與既有法案紀錄。")
	_preview_label.text = L10n.text("正式結果｜贊成 %d｜反對 %d｜棄權 %d｜缺席 %d") % [
		int(final_vote.get("votes_for", 0)),
		int(final_vote.get("votes_against", 0)),
		int(final_vote.get("abstentions", 0)),
		int(final_vote.get("absences", 0)),
	]
	_response_row.hide()
	confirm_button.hide()
	var decision_signature := JSON.stringify(final_vote.get("votes", [])).sha256_text()
	if decision_signature != _latest_decision_signature:
		_latest_decision_signature = decision_signature
		_play_vote_reveal(final_vote.get("votes", []))


func _show_idle() -> void:
	_stage_state = "idle"
	_set_workflow_mode(false)
	_status_label.text = L10n.text("下議院議事廳｜議程待命")
	_apply_vote_snapshot([], true)
	_play_ambient_motion()


func _set_workflow_mode(workflow_active: bool, final_vote: bool = false) -> void:
	_catalog_host.visible = not workflow_active
	_catalog_header_host.visible = not workflow_active
	_hearing_host.visible = workflow_active
	_shell.set_tray_height(CATALOG_TRAY_HEIGHT if not workflow_active else (FINAL_TRAY_HEIGHT if final_vote else HEARING_TRAY_HEIGHT))
	call_deferred("_relayout_stage")


func _rebuild_response_buttons(options: Array) -> void:
	for child in _response_row.get_children():
		_response_row.remove_child(child)
		child.queue_free()
	response_buttons.clear()
	_response_row.show()
	confirm_button.show()
	var group := ButtonGroup.new()
	for option_variant: Variant in options:
		if not option_variant is Dictionary:
			continue
		var option: Dictionary = option_variant
		var response_id := str(option.get("id", ""))
		var button := Button.new()
		button.name = "LowerCouncilResponse_%s" % response_id
		button.text = "%s\n%s" % [L10n.text(str(option.get("label", response_id))), L10n.text(str(option.get("description", "")))]
		button.set_meta("semantic_label", str(option.get("label", response_id)))
		button.set_meta("response_id", response_id)
		button.toggle_mode = true
		button.button_group = group
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(210, 68)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(_on_response_pressed.bind(response_id))
		_response_row.add_child(button)
		response_buttons.append(button)
		_style_action_button(button, false)


func _on_response_pressed(response_id: String) -> void:
	_selected_response_id = response_id
	confirm_button.disabled = true
	response_selected.emit(response_id)


func _on_confirm_pressed() -> void:
	if _selected_response_id.is_empty() or _latest_preview.is_empty():
		return
	confirm_button.disabled = true
	response_confirmed.emit(_selected_response_id)


func _layout_scene() -> void:
	if not is_instance_valid(_seat_grid) or not is_instance_valid(_shell):
		return
	var shell_signature: Dictionary = _shell.debug_signature()
	var tray_rect := shell_signature.get("tray_rect", Rect2()) as Rect2
	var available_top := SceneWorkflowShellScript.EDGE_INSET + SceneWorkflowShellScript.DEFAULT_TOP_HEIGHT + 8.0
	var available_bottom := tray_rect.position.y - 8.0
	var available_height := maxf(36.0, available_bottom - available_top)
	_layout_columns = 6 if _scene.size.x < 800.0 else 10
	_seat_grid.columns = _layout_columns
	var row_count := ceili(float(_seats.size()) / float(_layout_columns))
	var seat_height := clampf((available_height - float(row_count - 1) * 5.0) / float(row_count), 20.0, 48.0)
	var grid_width := _scene.size.x * 0.78
	var seat_width := clampf((grid_width - float(_layout_columns - 1) * 6.0) / float(_layout_columns), 26.0, 54.0)
	for seat: PanelContainer in _seats:
		seat.custom_minimum_size = Vector2(seat_width, seat_height)
	var grid_left := (_scene.size.x - grid_width) * 0.5
	_seat_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_seat_grid.offset_left = grid_left
	_seat_grid.offset_top = available_top
	_seat_grid.offset_right = -(grid_left)
	_seat_grid.offset_bottom = -(maxf(0.0, _scene.size.y - available_bottom))


func _relayout_stage() -> void:
	if not is_instance_valid(_shell):
		return
	_shell.relayout()
	_layout_scene()


func _queue_scene_layout() -> void:
	call_deferred("_layout_scene")


func _apply_vote_snapshot(votes_variant: Variant, dimmed: bool) -> void:
	var votes: Array = votes_variant if votes_variant is Array else []
	for index in _seats.size():
		var choice := str((votes[index] as Dictionary).get("choice", "abstain")) if index < votes.size() and votes[index] is Dictionary else "abstain"
		_style_vote_seat(_seats[index], choice, 0.24 if dimmed else 0.72)


func _play_vote_reveal(votes_variant: Variant) -> void:
	var votes: Array = votes_variant if votes_variant is Array else []
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	for seat in _seats:
		_style_vote_seat(seat, "absent", 0.24)
	_vote_reveal_step_count = mini(_seats.size(), votes.size())
	_revealed_seat_count = 0
	_animation_generation += 1
	_active_tween = create_tween()
	for index in _vote_reveal_step_count:
		var vote: Dictionary = votes[index]
		_active_tween.tween_interval(0.035)
		_active_tween.tween_callback(_reveal_seat.bind(index, str(vote.get("choice", "abstain"))))


func _play_ambient_motion() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_animation_generation += 1
	_active_tween = create_tween().set_loops()
	_active_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_active_tween.tween_property(_seat_grid, "modulate:a", 0.90, 0.68)
	_active_tween.tween_property(_seat_grid, "modulate:a", 1.0, 0.68)


func _reveal_seat(index: int, choice: String) -> void:
	if index >= 0 and index < _seats.size():
		_style_vote_seat(_seats[index], choice, 1.0)
		_revealed_seat_count += 1


func _reset_hearing_interaction() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = null
	_latest_decision_signature = ""
	_vote_reveal_step_count = 0
	_revealed_seat_count = 0
	_selected_response_id = ""
	_latest_preview.clear()
	_response_row.show()
	confirm_button.show()
	confirm_button.disabled = true
	_preview_label.text = L10n.text("尚未選擇答詢方案；預覽不會寫入正式票史。")
	for button: Button in response_buttons:
		button.set_pressed_no_signal(false)


func _update_authority_values(seat_count: int, majority_threshold: int) -> void:
	_authority_seat_count = seat_count
	_authority_majority_threshold = majority_threshold
	_authority_contract_valid = _authority_seat_count == SEAT_COUNT and _authority_majority_threshold == MAJORITY_THRESHOLD


func _style_action_button(button: Button, primary: bool) -> void:
	if not is_instance_valid(button):
		return
	var background_role := "action_primary" if primary else "surface_muted"
	var text_role := "text_on_accent" if primary else "text_primary"
	var normal := StyleBoxFlat.new()
	normal.bg_color = SemanticPalette.color_for(_dark_mode, background_role)
	normal.border_color = SemanticPalette.color_for(_dark_mode, "border_default")
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(9)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = SemanticPalette.color_for(_dark_mode, "border_focus")
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = SemanticPalette.color_for(_dark_mode, "action_primary_hover" if primary else "surface_base")
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = SemanticPalette.color_for(_dark_mode, "action_primary_disabled")
	disabled.border_color = SemanticPalette.color_for(_dark_mode, "border_disabled")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	var text_color := SemanticPalette.color_for(_dark_mode, text_role)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_focus_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	button.add_theme_color_override("font_disabled_color", SemanticPalette.color_for(_dark_mode, "text_disabled"))


func _style_vote_seat(seat: PanelContainer, choice: String, intensity: float) -> void:
	var accent := _vote_color(choice, 1.0)
	var strength := clampf(intensity, 0.0, 1.0)
	seat.set_meta("vote_choice", choice)
	seat.set_meta("vote_intensity", strength)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent.r, accent.g, accent.b, lerpf(0.06, 0.22, strength))
	style.border_color = Color(accent.r, accent.g, accent.b, lerpf(0.46, 1.0, strength))
	style.set_border_width_all(2)
	style.set_corner_radius_all(7)
	seat.add_theme_stylebox_override("panel", style)
	seat.modulate = Color.WHITE


func _visible_portrait_count() -> int:
	var count := 0
	for portrait: TextureRect in _seat_portraits:
		if portrait.texture != null and portrait.is_visible_in_tree() and portrait.modulate.a >= 0.99:
			count += 1
	return count


func _seat_surface_max_alpha() -> float:
	var maximum := 0.0
	for seat: PanelContainer in _seats:
		var style := seat.get_theme_stylebox("panel") as StyleBoxFlat
		if style != null:
			maximum = maxf(maximum, style.bg_color.a)
	return maximum


func _vote_color_group_count() -> int:
	var colors := {}
	for seat: PanelContainer in _seats:
		var style := seat.get_theme_stylebox("panel") as StyleBoxFlat
		if style != null:
			colors[style.border_color.to_html(false)] = true
	return colors.size()


func _vote_color(choice: String, alpha: float) -> Color:
	var color: Color
	match choice:
		"for":
			color = SemanticPalette.color_for(_dark_mode, "success")
		"against":
			color = SemanticPalette.color_for(_dark_mode, "danger")
		"absent":
			color = SemanticPalette.color_for(_dark_mode, "text_secondary")
		_:
			color = SemanticPalette.color_for(_dark_mode, "caution")
	color.a = alpha
	return color
