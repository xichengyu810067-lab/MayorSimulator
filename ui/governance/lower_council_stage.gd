class_name LowerCouncilStage
extends VBoxContainer

signal response_selected(response_id: String)
signal response_confirmed(response_id: String)

const BACKGROUND_PATH := "res://assets/images/ui/legislative_chamber_v1/legislative_chamber.png"
const MEMBER_PATH := "res://assets/images/characters/npc/npc-council-member.png"
const SEAT_COUNT := 30
const MAJORITY_THRESHOLD := 16
const TEXT_COLOR := Color("172033")
const MUTED_TEXT_COLOR := Color("334155")

var response_buttons: Array[Button] = []
var confirm_button: Button

var _scene: Control
var _seat_grid: GridContainer
var _seats: Array[PanelContainer] = []
var _status_label: Label
var _question_label: Label
var _preview_label: Label
var _response_row: HBoxContainer
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


func _init() -> void:
	name = "LowerCouncilStage"
	custom_minimum_size = Vector2(0, 580)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	_build_stage()
	hide()


func refresh(pending_bill: Dictionary, bill_definition: Dictionary, latest_decision: Dictionary = {}) -> void:
	if str(pending_bill.get("status", "")) == "awaiting_mayor_response":
		_show_hearing(pending_bill, bill_definition)
		return
	if not latest_decision.is_empty():
		_show_final_decision(latest_decision)
		return
	hide()


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
		"decision_signature": _latest_decision_signature,
	}


func _build_stage() -> void:
	_status_label = Label.new()
	_status_label.name = "LowerCouncilStatus"
	_status_label.add_theme_font_size_override("font_size", 20)
	_status_label.add_theme_color_override("font_color", TEXT_COLOR)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(0, 34)
	add_child(_status_label)

	_scene = Control.new()
	_scene.name = "LowerCouncilChamberVisual"
	_scene.custom_minimum_size = Vector2(720, 300)
	_scene.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scene.clip_contents = true
	add_child(_scene)
	var background := TextureRect.new()
	background.name = "LegislativeChamberBackground"
	var background_image := Image.load_from_file(ProjectSettings.globalize_path(BACKGROUND_PATH))
	if background_image != null and not background_image.is_empty():
		background.texture = ImageTexture.create_from_image(background_image)
		_background_loaded = background.texture != null
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene.add_child(background)
	var scrim := ColorRect.new()
	scrim.name = "LegislativeChamberScrim"
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.02, 0.04, 0.07, 0.28)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene.add_child(scrim)
	_seat_grid = GridContainer.new()
	_seat_grid.name = "LowerCouncilSeatGrid"
	_seat_grid.columns = 10
	_seat_grid.add_theme_constant_override("h_separation", 6)
	_seat_grid.add_theme_constant_override("v_separation", 6)
	_scene.add_child(_seat_grid)
	for index in SEAT_COUNT:
		var seat := PanelContainer.new()
		seat.name = "LowerCouncilSeat_%02d" % (index + 1)
		seat.custom_minimum_size = Vector2(46, 52)
		seat.tooltip_text = L10n.text("下議院第 %d 席") % (index + 1)
		var portrait := TextureRect.new()
		portrait.texture = ResourceLoader.load(MEMBER_PATH, "Texture2D") as Texture2D
		portrait.custom_minimum_size = Vector2(38, 44)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		seat.add_child(portrait)
		_seat_grid.add_child(seat)
		_seats.append(seat)
	_scene.resized.connect(_layout_scene)
	call_deferred("_layout_scene")

	_question_label = Label.new()
	_question_label.name = "LowerCouncilPrimaryQuestion"
	_question_label.add_theme_font_size_override("font_size", 20)
	_question_label.add_theme_color_override("font_color", TEXT_COLOR)
	_question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_question_label.custom_minimum_size = Vector2(0, 42)
	add_child(_question_label)

	_response_row = HBoxContainer.new()
	_response_row.name = "LowerCouncilResponseOptions"
	_response_row.add_theme_constant_override("separation", 10)
	add_child(_response_row)

	_preview_label = Label.new()
	_preview_label.name = "LowerCouncilReadonlyPreview"
	_preview_label.add_theme_font_size_override("font_size", 18)
	_preview_label.add_theme_color_override("font_color", MUTED_TEXT_COLOR)
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_label.custom_minimum_size = Vector2(0, 34)
	add_child(_preview_label)

	confirm_button = Button.new()
	confirm_button.name = "LowerCouncilConfirmResponse"
	confirm_button.text = L10n.text("確認答詢並進行正式表決")
	confirm_button.set_meta("semantic_label", confirm_button.text)
	confirm_button.custom_minimum_size = Vector2(0, 48)
	confirm_button.add_theme_font_size_override("font_size", 19)
	confirm_button.disabled = true
	confirm_button.pressed.connect(_on_confirm_pressed)
	add_child(confirm_button)


func _show_hearing(pending_bill: Dictionary, bill_definition: Dictionary) -> void:
	show()
	var hearing: Dictionary = pending_bill.get("lower_house_hearing", {})
	_update_authority_values(
		int(hearing.get("seat_count", 0)),
		int(hearing.get("majority_threshold", 0))
	)
	var bill_name := L10n.text(str(bill_definition.get("name", pending_bill.get("bill_id", "法案"))))
	_status_label.text = L10n.text("《%s》下議院答詢｜%d 席｜通過門檻 %d" % [
		bill_name,
		_authority_seat_count,
		_authority_majority_threshold,
	])
	_question_label.text = L10n.text(str(hearing.get("primary_question", "下議院正在等待市長答詢。")))
	var options: Array = hearing.get("response_options", [])
	var new_signature := JSON.stringify(options).sha256_text()
	if new_signature != _response_signature:
		_response_signature = new_signature
		_rebuild_response_buttons(options)
	_reset_hearing_interaction()
	_apply_vote_snapshot(hearing.get("initial_vote", {}).get("votes", []), false)


func _show_final_decision(decision: Dictionary) -> void:
	show()
	_selected_response_id = ""
	_latest_preview.clear()
	var final_vote: Dictionary = decision.get("final_vote", {})
	var final_votes: Array = final_vote.get("votes", [])
	_update_authority_values(final_votes.size(), int(final_vote.get("majority_threshold", 0)))
	var bill_name := L10n.text(str(decision.get("name", decision.get("bill_id", "法案"))))
	_status_label.text = L10n.text("《%s》下議院正式表決｜贊成 %d｜門檻 %d" % [
		bill_name,
		int(final_vote.get("votes_for", 0)),
		_authority_majority_threshold,
	])
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
		button.custom_minimum_size = Vector2(220, 74)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 17)
		button.pressed.connect(_on_response_pressed.bind(response_id))
		_response_row.add_child(button)
		response_buttons.append(button)


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
	if not is_instance_valid(_seat_grid):
		return
	_layout_columns = 6 if _scene.size.x < 800.0 else 10
	_seat_grid.columns = _layout_columns
	var seat_minimum := Vector2(42, 48) if _layout_columns == 6 else Vector2(46, 52)
	for seat: PanelContainer in _seats:
		seat.custom_minimum_size = seat_minimum
	_seat_grid.position = Vector2(_scene.size.x * 0.06, _scene.size.y * 0.08)
	_seat_grid.size = Vector2(_scene.size.x * 0.88, _scene.size.y * 0.86)


func _apply_vote_snapshot(votes_variant: Variant, dimmed: bool) -> void:
	var votes: Array = votes_variant if votes_variant is Array else []
	for index in _seats.size():
		var choice := str((votes[index] as Dictionary).get("choice", "abstain")) if index < votes.size() and votes[index] is Dictionary else "abstain"
		_seats[index].modulate = _vote_color(choice, 0.58 if dimmed else 0.82)


func _play_vote_reveal(votes_variant: Variant) -> void:
	var votes: Array = votes_variant if votes_variant is Array else []
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	for seat in _seats:
		seat.modulate = Color(0.35, 0.38, 0.42, 0.45)
	_vote_reveal_step_count = mini(_seats.size(), votes.size())
	_revealed_seat_count = 0
	_animation_generation += 1
	_active_tween = create_tween()
	for index in _vote_reveal_step_count:
		var vote: Dictionary = votes[index]
		_active_tween.tween_interval(0.035)
		_active_tween.tween_callback(_reveal_seat.bind(index, str(vote.get("choice", "abstain"))))


func _reveal_seat(index: int, choice: String) -> void:
	if index >= 0 and index < _seats.size():
		_seats[index].modulate = _vote_color(choice, 1.0)
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
	_authority_contract_valid = (
		_authority_seat_count == SEAT_COUNT
		and _authority_majority_threshold == MAJORITY_THRESHOLD
	)


func _vote_color(choice: String, alpha: float) -> Color:
	match choice:
		"for":
			return Color(0.48, 1.0, 0.58, alpha)
		"against":
			return Color(1.0, 0.42, 0.38, alpha)
		"absent":
			return Color(0.45, 0.48, 0.54, alpha)
		_:
			return Color(1.0, 0.82, 0.30, alpha)
