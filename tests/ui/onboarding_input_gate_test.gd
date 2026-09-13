extends SceneTree

const OnboardingProgressScript := preload("res://scripts/app/onboarding_progress.gd")
const OnboardingGuideScript := preload("res://ui/tutorial/onboarding_guide.gd")
const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")

var _failed := false
var _map_presses := 0
var _target_presses := 0
var _advanced_targets: Array[String] = []
var _product_inputs := 0
var _defer_requests := 0
var _result_review_confirmations := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	var map_button := _button("UnderlyingMap", Vector2(60, 60), Vector2(180, 90))
	map_button.pressed.connect(func() -> void: _map_presses += 1)
	host.add_child(map_button)
	var target := _button("CurrentTarget", Vector2(520, 280), Vector2(180, 80))
	target.pressed.connect(func() -> void: _target_presses += 1)
	host.add_child(target)
	var guide = OnboardingGuideScript.new()
	guide.advanced.connect(func(target_id: String, _receipt: Dictionary) -> void: _advanced_targets.append(target_id))
	guide.target_input_observed.connect(func(_target_id: String, _input_kind: String) -> void: _product_inputs += 1)
	guide.defer_requested.connect(func() -> void: _defer_requests += 1)
	guide.result_review_confirmed.connect(func() -> void: _result_review_confirmations += 1)
	host.add_child(guide)
	await _settle(3)

	var progress = OnboardingProgressScript.new()
	progress.begin_guide()
	_check(not guide.open_product_target(progress, null, guide.INPUT_MOUSE_LEFT), "missing target fails closed")
	_check(not guide.is_open() and not guide.visible, "missing target leaves no masks or false completion surface")
	target.hide()
	_check(not guide.open_product_target(progress, target, guide.INPUT_MOUSE_LEFT), "hidden target fails closed")
	target.show()
	target.disabled = true
	_check(not guide.open_product_target(progress, target, guide.INPUT_MOUSE_LEFT), "disabled target fails closed")
	target.disabled = false
	_check(guide.open_product_target(progress, target, guide.INPUT_MOUSE_LEFT, KEY_NONE, "perform the real action"), "product target gate opens")
	await _click_at(target.get_global_rect().get_center())
	_check(_product_inputs == 1 and progress.next_index() == 0 and progress.receipts().is_empty(), "target click reaches product UI but cannot synthesize or skip an authoritative receipt")
	guide.invalidate_target()
	_check(guide.open_for_target(progress, target, guide.INPUT_MOUSE_LEFT, KEY_NONE, "authority_0", "entity_0", 1, "click"), "mouse target gate opens")
	await _settle(2)
	_check(guide.get_child_count() >= 7, "guide creates four masks plus Xiao Li, guide text, and arrow")
	for index in 4:
		_check((guide.get_child(index) as Control).mouse_filter == Control.MOUSE_FILTER_STOP, "mask %d blocks pointer input" % index)
	_check((guide.get_node("OnboardingArrow") as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE, "arrow ignores pointer input")
	_check((guide.get_node("OnboardingMessage") as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE, "guide text ignores pointer input")
	var fairy := guide.get_node("OnboardingFairy") as TextureRect
	_check(fairy != null and fairy.size == guide.FAIRY_SIZE and fairy.texture is AtlasTexture, "guide renders the existing Xiao Li atlas as a 96px fairy")
	var target_center := target.get_global_rect().get_center()
	for index in 4:
		_check(not (guide.get_child(index) as Control).get_global_rect().has_point(target_center), "mask %d leaves the target hole open" % index)

	await _click_at(map_button.get_global_rect().get_center())
	_check(_map_presses == 0 and progress.next_index() == 0, "outside click is blocked from the map and progress")
	await _click_at(target_center)
	_check(progress.next_index() == 1 and _advanced_targets == ["build"], "real current-target mouse input advances exactly once")
	var progress_after_mouse := progress.next_index()
	await _click_at(target_center)
	_check(progress.next_index() == progress_after_mouse and _advanced_targets.size() == 1, "old mouse binding cannot advance again")

	_check(guide.open_for_target(progress, target, guide.INPUT_KEY, KEY_B, "authority_1", "entity_1", 4, "key"), "key target gate opens on the scheduled day")
	target.grab_focus()
	await _settle(2)
	var presses_before_wrong_key := _target_presses
	await _press_key(KEY_ENTER)
	_check(progress.next_index() == 1, "wrong key cannot advance current target")
	_check(_target_presses == presses_before_wrong_key, "wrong key cannot leak into the focused target")
	await _press_key(KEY_B)
	_check(progress.next_index() == 2 and _advanced_targets == ["build", "blueprint"], "focused current-target key advances exactly once")

	var stale_target := _button("StaleTarget", Vector2(760, 420), Vector2(160, 70))
	host.add_child(stale_target)
	await _settle(1)
	_check(guide.open_for_target(progress, stale_target, guide.INPUT_MOUSE_LEFT, KEY_NONE, "authority_2", "entity_2", 7), "stale-reference scenario binds")
	stale_target.queue_free()
	await _settle(3)
	_check(not guide.is_open() and guide.target_control() == null, "freed target invalidates the guide reference")
	guide.set_dark_mode(true)
	guide.refresh_localization()
	_check(guide.target_control() == null, "theme and locale refresh cannot resurrect a stale target")
	var replacement := _button("ReplacementTarget", Vector2(760, 420), Vector2(160, 70))
	host.add_child(replacement)
	await _settle(2)
	_check(guide.open_for_target(progress, replacement, guide.INPUT_MOUSE_LEFT, KEY_NONE, "authority_2", "entity_2", 7), "replacement target can bind after rebuild")
	await _click_at(replacement.get_global_rect().get_center())
	_check(progress.next_index() == 3 and _advanced_targets.back() == "route", "replacement target advances the unchanged current step")

	var defer_progress = OnboardingProgressScript.new()
	defer_progress.begin_guide()
	_check(guide.show_waiting(defer_progress, "目前工人不足；可先調整工人或延後教學。"), "active unavailable presentation opens without a product target")
	_check(guide.is_waiting_mode() and not guide.is_open() and guide.target_control() == null, "active unavailable presentation owns no guided target or input hole")
	var defer_button := guide.get_node("OnboardingDeferButton") as Button
	_check(defer_button != null and defer_button.visible and defer_button.text == "延後教學", "active unavailable presentation exposes the exact defer action")
	_check(guide.get_node_or_null("OnboardingGuideCard") is PanelContainer, "active unavailable explanation uses the same solid guide card")
	for index in 4:
		_check(not (guide.get_child(index) as Control).visible, "active unavailable presentation hides input mask %d" % index)
	var map_presses_before_waiting := _map_presses
	await _click_at(map_button.get_global_rect().get_center())
	_check(_map_presses == map_presses_before_waiting + 1 and guide.is_waiting_mode(), "active unavailable presentation leaves ordinary map input available")
	defer_button.pressed.emit()
	_check(_defer_requests == 1 and defer_progress.next_index() == 0 and defer_progress.receipts().is_empty(), "defer UI requests scheduling without fabricating completion")

	var review_progress = _progress_at_judicial()
	_check(guide.show_result_review(review_progress, "司法案件 judicial_1 已結案。結果：裁處罰款；結案日期：第 1 年 1 月 22 日。"), "resolved-case review presentation opens for a case target")
	var review_button := guide.get_node("OnboardingResultReviewButton") as Button
	_check(guide.is_result_review_mode() and not guide.is_open() and review_button != null and review_button.visible and review_button.text == "已閱讀結果，繼續", "result review exposes the explicit localized confirmation action without a target gate")
	var map_presses_before_review := _map_presses
	await _click_at(map_button.get_global_rect().get_center())
	_check(_map_presses == map_presses_before_review + 1, "result review leaves ordinary map input available")
	if review_button != null:
		review_button.pressed.emit()
	_check(_result_review_confirmations == 1 and review_progress.current_target() == "judicial" and review_progress.receipts().size() == 7, "result-review UI requests authority validation without fabricating its own receipt")
	defer_button.pressed.emit()
	_check(_defer_requests == 2 and review_progress.receipts().size() == 7, "resolved-case review keeps the repeatable defer action")

	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Onboarding input gate test passed.")
	await TestCleanup.finish(self, [host], exit_code)


func _button(node_name: String, position: Vector2, button_size: Vector2) -> Button:
	var button := Button.new()
	button.name = node_name
	button.position = position
	button.size = button_size
	button.text = node_name
	return button


func _progress_at_judicial():
	var progress = OnboardingProgressScript.new()
	progress.begin_guide()
	for index in 7:
		var target_id := progress.current_target()
		var game_day := index * 3
		progress.record_current_target(target_id, {
			"kind": target_id,
			"authority_id": "authority_%d" % index,
			"entity_id": "entity_%d" % index,
			"game_day": game_day,
		})
	return progress


func _click_at(position: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.pressed = true
	down.position = position
	down.global_position = position
	root.push_input(down, true)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = position
	up.global_position = position
	root.push_input(up, true)
	await _settle(2)


func _press_key(keycode: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = keycode
	down.physical_keycode = keycode
	down.pressed = true
	root.push_input(down, true)
	await process_frame
	var up := InputEventKey.new()
	up.keycode = keycode
	up.physical_keycode = keycode
	up.pressed = false
	root.push_input(up, true)
	await _settle(2)


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Onboarding input gate check failed: %s" % message)
