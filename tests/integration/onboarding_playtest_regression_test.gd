extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const OnboardingProgressScript := preload("res://scripts/app/onboarding_progress.gd")
const OnboardingGuideScript := preload("res://ui/tutorial/onboarding_guide.gd")
const TEST_SAVE_PATH := "user://mayor_simulator/tests/onboarding_playtest_regression.json"

var _failed := false
var _npc_presses := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_save()
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_check(packed != null, "Main scene loads")
	if packed == null:
		await TestCleanup.finish(self, [], 1)
		return
	var main = packed.instantiate()
	root.add_child(main)
	await _settle(3)
	main.start_save_path = TEST_SAVE_PATH
	main.start_screen.set_continue_available(false)
	main.start_screen.animation_duration = 0.04
	main.start_screen.new_game_button.emit_signal("pressed")
	await _wait_for_loading(main)
	if main.tutorial_overlay != null and main.tutorial_overlay.is_open():
		main.tutorial_overlay.skip_button.emit_signal("pressed")
	await _settle(5)

	# A scheduled D+3 gap explains the next date without gating normal play or
	# exposing a defer action before the due day.
	var waiting_day := int(main.vertical_slice.game_day())
	_check(main.onboarding_progress.defer_current_target(waiting_day), "fixture schedules the build guide three days out")
	var due_before_rejected_request := int(main.onboarding_progress.due_game_day())
	main.call("_refresh_onboarding_guide")
	await _settle(2)
	var defer_button := main.onboarding_guide.get_node_or_null("OnboardingDeferButton") as Button
	var waiting_message := (main.onboarding_guide.get_node_or_null("OnboardingMessage") as Label).text
	_check(main.onboarding_guide.is_waiting_mode() and not main.onboarding_guide.is_open(), "pre-due D+3 interval shows passive waiting without a target input gate")
	_check(waiting_message.contains(main.call("_onboarding_date_label", due_before_rejected_request)) and waiting_message.contains("可正常遊玩"), "pre-due card explains the player date and normal play")
	_check(not (main.onboarding_guide.get_node("OnboardingArrow") as Control).visible, "pre-due card has no false arrow")
	for mask_index in 4:
		_check(not (main.onboarding_guide.get_node("OnboardingMask%d" % mask_index) as Control).visible, "pre-due mask %d does not block the game" % mask_index)
	_check(defer_button != null and not defer_button.visible, "pre-due D+3 interval hides defer")
	main.call("_on_onboarding_defer_requested")
	_check(main.onboarding_progress.due_game_day() == due_before_rejected_request, "Main rejects defer events sourced before the due day")

	# Restore an immediately active build guide without changing the persistent
	# scheduling implementation under test.
	var progress_state: Dictionary = main.onboarding_progress.snapshot()
	progress_state["due_game_day"] = waiting_day
	main.onboarding_progress.restore_from_shell_state({
		"schema_version": 9,
		"tutorial_completed": true,
		"onboarding": progress_state,
	})
	main.call("_refresh_onboarding_guide")
	await _settle(2)
	_check(main.onboarding_guide.visible and defer_button.visible, "active guide exposes one readable defer action")
	_check(main.onboarding_guide.get_node_or_null("OnboardingGuideCard") is PanelContainer, "active guide message and actions have a solid card")

	# The two non-target active presentations share the same solid card and stay
	# below the status HUD at the minimum supported viewport.
	_check(main.onboarding_guide.show_waiting(main.onboarding_progress, "目前資源不足；可先調整資源或延後教學。"), "active resource-unavailable presentation opens")
	await _settle(2)
	_check(_guide_card_clears_status_hud(main), "active resource-unavailable card stays clear of StatusHud")
	var review_progress = OnboardingProgressScript.new()
	review_progress.begin_guide()
	var receipt_day := 1
	for _receipt_index in range(7):
		var receipt_kind: String = review_progress.current_target()
		_check(review_progress.record_current_target(receipt_kind, {
			"kind": receipt_kind,
			"authority_id": "playtest_authority_%d" % _receipt_index,
			"entity_id": "playtest_entity_%d" % _receipt_index,
			"game_day": receipt_day,
		}), "fixture advances to the judicial result-review target")
		receipt_day += review_progress.STAGE_DELAY_DAYS
	_check(main.onboarding_guide.show_result_review(review_progress, "司法案件已結案；請檢視結果。"), "active result-review presentation opens")
	await _settle(2)
	_check(_guide_card_clears_status_hud(main), "active result-review card stays clear of StatusHud")
	main.call("_refresh_onboarding_guide")
	await _settle(2)

	# Reach the real dynamic placement tile, then overlap it with a real NPC
	# actor. The guide must reserve the footprint and leave the tile as the only
	# pointer owner in the target hole.
	await _click_at(main.municipal_button.get_global_rect().get_center())
	await _settle(3)
	var buildings_target := main.onboarding_guide.target_control() as Control
	if buildings_target == null:
		_check(false, "build guide reaches the Buildings destination")
		await _finish(main)
		return
	await _click_at(buildings_target.get_global_rect().get_center())
	await _settle(3)
	var residence_target := main.onboarding_guide.target_control() as Control
	if residence_target != null and residence_target.name == "BuildingGroup_housing":
		await _click_at(residence_target.get_global_rect().get_center())
		await _settle(3)
		residence_target = main.onboarding_guide.target_control() as Control
	if residence_target == null:
		_check(false, "build guide reaches the Residence card")
		await _finish(main)
		return
	await _click_at(residence_target.get_global_rect().get_center())
	await _settle(3)
	var submit_target := main.onboarding_guide.target_control() as Control
	if submit_target == null:
		_check(false, "build guide reaches the blueprint submit action")
		await _finish(main)
		return
	await _click_at(submit_target.get_global_rect().get_center())
	await _settle(4)
	var placement_target := main.onboarding_guide.target_control() as Button
	var placement_index: int = main.grid_buttons.find(placement_target)
	_check(placement_target != null and placement_index >= 0, "build guide reaches a real dynamic grid target")
	var controller = main.npc_map_controller
	_check(controller != null and controller.has_method("tutorial_reservation_snapshot"), "NPC controller exposes transient tutorial reservation evidence")
	var reservation: Dictionary = controller.call("tutorial_reservation_snapshot") if controller != null and controller.has_method("tutorial_reservation_snapshot") else {}
	_check(bool(reservation.get("active", false)) and Array(reservation.get("tile_ids", [])).has(placement_index), "dynamic target footprint is reserved from NPC navigation")
	var actors: Array[Button] = main.get_visible_npc_actors()
	var actor := actors[0] if not actors.is_empty() else null
	_check(actor != null, "fixture has a real NPC actor")
	if actor != null and placement_target != null:
		var no_reserved_tiles: Array[int] = []
		main.call("_set_onboarding_npc_reservation", no_reserved_tiles)
		var inside_proxy: Dictionary = main.get_visible_npc_snapshot(0)
		var target_local_center := placement_target.position + placement_target.size * 0.5
		var feet_offset := Vector2(inside_proxy.get("foot_position", Vector2.ZERO)) - Vector2(inside_proxy.get("pos", Vector2.ZERO))
		inside_proxy["foot_position"] = target_local_center
		inside_proxy["pos"] = target_local_center - feet_offset
		inside_proxy["destination"] = target_local_center
		inside_proxy["path"] = PackedVector2Array()
		inside_proxy["path_index"] = 0
		_check(main.debug_override_visible_npc_proxy(0, inside_proxy), "fixture places an existing NPC inside the future reservation without changing population authority")
		actor.position = Vector2(inside_proxy["pos"])
		main.call("_sync_onboarding_npc_reservation", placement_target)
		reservation = controller.call("tutorial_reservation_snapshot")
		_check(Array(reservation.get("npc_indices_inside", [])).has(0), "reservation detects an NPC already inside its target footprint")
		for _step in range(120):
			controller.step(0.1)
			if not Array(controller.call("tutorial_reservation_snapshot").get("npc_indices_inside", [])).has(0):
				break
		reservation = controller.call("tutorial_reservation_snapshot")
		_check(not Array(reservation.get("npc_indices_inside", [])).has(0), "NPC already inside the target footprint walks to safety without teleporting")

		actor.pressed.connect(func() -> void: _npc_presses += 1)
		var target_center := placement_target.get_global_rect().get_center()
		var actor_parent_local: Vector2 = actor.get_parent().get_global_transform_with_canvas().affine_inverse() * target_center
		actor.position = actor_parent_local - actor.size * 0.5
		_check(actor.get_global_rect().has_point(target_center), "real NPC hitbox overlaps the guided tile center")
		_check(actor.mouse_filter == Control.MOUSE_FILTER_IGNORE, "guided build target disables NPC pointer interception")
		await _click_at(target_center)
		await _settle(3)
		_check(_npc_presses == 0 and not bool(main.get_npc_dialogue_snapshot().get("visible", false)), "overlapping NPC cannot open dialogue over the guided target")
		_check(main._pending_construction_tile == placement_index and main.construction_confirmation.is_open(), "same physical click reaches the guided tile and opens confirmation")
		if controller.has_method("tutorial_reservation_snapshot"):
			reservation = controller.call("tutorial_reservation_snapshot")
			_check(not bool(reservation.get("active", true)), "target change to confirmation releases the transient NPC reservation")

		main.construction_confirmation.close()
		main.call("_refresh_onboarding_guide")
		await _settle(2)
		reservation = controller.call("tutorial_reservation_snapshot")
		_check(bool(reservation.get("active", false)), "returning to the placement target restores its reservation")
		main.call("_on_onboarding_defer_requested")
		reservation = controller.call("tutorial_reservation_snapshot")
		_check(not bool(reservation.get("active", true)) and main.onboarding_guide.is_waiting_mode() and not main.onboarding_guide.is_open(), "deferring an active placement guide releases its reservation and shows only passive timing")

	# Only CityBackdrop may own the source terrain image. Camera scale is 125%
	# of cover at 100%, returns to cover at the 80% endpoint, and pan never
	# exposes an edge.
	var completion_reserved_tiles: Array[int] = [placement_index]
	main.call("_set_onboarding_npc_reservation", completion_reserved_tiles)
	main.onboarding_progress.restore_from_shell_state({"schema_version": 8, "tutorial_completed": true})
	main.call("_refresh_onboarding_guide")
	reservation = controller.call("tutorial_reservation_snapshot")
	_check(not bool(reservation.get("active", true)), "guide completion releases the transient NPC reservation")
	main.call("_layout_map_stage")
	await _settle(2)
	_check(main.map_viewport.get_node_or_null("ViewportTerrainBackground") == null, "map viewport has no duplicate terrain background")
	var fill_scale := maxf(main.map_viewport.size.x / main.MAP_STAGE_SIZE.x, main.map_viewport.size.y / main.MAP_STAGE_SIZE.y)
	_check(is_equal_approx(float(main.call("_base_map_scale")), fill_scale * 1.25), "100% base scale is exactly 125% of viewport cover")
	var legacy_zoom_shell: Dictionary = main.call("_capture_player_shell_state")
	legacy_zoom_shell["map_zoom"] = 0.65
	_check(main.call("_restore_player_shell_state", legacy_zoom_shell), "legacy shell with a 65% map zoom remains loadable")
	main.call("_layout_map_stage")
	var scale_at_80: float = main.map_stage.scale.x
	_check(is_equal_approx(main.map_zoom, 0.8) and is_equal_approx(scale_at_80, fill_scale), "legacy 65% zoom clamps to the 80% cover endpoint")
	var zoom_anchor: Vector2 = main.map_viewport.get_global_rect().get_center()
	main.call("_zoom_map_at", zoom_anchor, 0.1)
	var scale_at_90: float = main.map_stage.scale.x
	_check(is_equal_approx(main.map_zoom, 0.9) and scale_at_90 > scale_at_80, "80% to 90% increases the physical map scale")
	main.call("_zoom_map_at", zoom_anchor, 0.1)
	var scale_at_100: float = main.map_stage.scale.x
	_check(is_equal_approx(main.map_zoom, 1.0) and scale_at_100 > scale_at_90, "90% to 100% increases the physical map scale")
	main.map_zoom = main.MAP_ZOOM_MIN
	main.map_pan_offset = Vector2(9999.0, -9999.0)
	main.call("_layout_map_stage")
	var stage_rect: Rect2 = main.map_stage.get_global_rect()
	var viewport_rect: Rect2 = main.map_viewport.get_global_rect()
	_check(stage_rect.encloses(viewport_rect), "80% endpoint plus clamped pan keeps the single stage terrain covering the viewport")

	# Reservation state is runtime-only and is explicitly released before the UI
	# tree is rebuilt by new/load flows.
	var one_reserved_tile: Array[int] = [placement_index]
	main.call("_set_onboarding_npc_reservation", one_reserved_tile)
	var shell_state: Dictionary = main.call("_capture_player_shell_state")
	_check(not shell_state.has("onboarding_reserved_tile_ids"), "transient NPC reservation is absent from player save state")
	var old_controller = main.npc_map_controller
	main.call("_rebuild_ui")
	reservation = old_controller.call("tutorial_reservation_snapshot")
	_check(not bool(reservation.get("active", true)) and main._onboarding_reserved_tile_ids.is_empty(), "UI rebuild/load lifecycle releases the transient NPC reservation")
	await _verify_compact_guide_layout(main)

	await _finish(main)


func _verify_compact_guide_layout(main) -> void:
	var layout_guide := OnboardingGuideScript.new()
	main.add_child(layout_guide)
	var layout_progress := OnboardingProgressScript.new()
	layout_progress.begin_guide()
	var review_progress := OnboardingProgressScript.new()
	review_progress.begin_guide()
	var review_day := 0
	for receipt_index in 7:
		var receipt_target: String = review_progress.current_target()
		_check(review_progress.record_current_target(receipt_target, {"kind": receipt_target, "authority_id": "layout_authority_%d" % receipt_index, "entity_id": "layout_entity_%d" % receipt_index, "game_day": review_day}), "result-review layout fixture records ordered receipt %d" % receipt_index)
		review_day = maxi(review_day, review_progress.due_game_day())
	var long_message := "下一步請檢查城市資金、施工與居民需求。這段較長的教學提示確認靠右目標、等待日期和已結案結果都能完整閱讀；仙子、提示卡與操作按鈕不能超出畫面或擋住上方城市資訊。"
	for resolution in [Vector2i(1280, 720), Vector2i(1440, 900)]:
		root.content_scale_size = resolution
		root.size = resolution
		await _settle(4)
		_check(main.exit_button != null and main.exit_button.is_visible_in_tree(), "%s has a real enabled right-edge HUD target" % resolution)
		_check(layout_guide.open_product_target(layout_progress, main.exit_button, OnboardingGuideScript.INPUT_MOUSE_LEFT, KEY_NONE, long_message), "%s opens a target-bound guide beside the real right-edge HUD button" % resolution)
		await _settle(2)
		_assert_compact_guide_bounds(main, layout_guide, resolution, "right-edge target")
		var target_rect: Rect2 = main.exit_button.get_global_rect()
		var arrow := layout_guide.get_node("OnboardingArrow") as Control
		_check(layout_guide.target_control() == main.exit_button and arrow.visible and arrow.get_global_rect().get_center().x < target_rect.get_center().x, "%s keeps the arrow aimed from the left of its true right-edge target" % resolution)
		for mask_index in 4:
			_check(not (layout_guide.get_node("OnboardingMask%d" % mask_index) as Control).get_global_rect().has_point(target_rect.get_center()), "%s spotlight mask %d does not cover the real target" % [resolution, mask_index])
		_check(layout_guide.show_waiting(layout_progress, long_message, false), "%s opens the passive long-message waiting card" % resolution)
		await _settle(2)
		_assert_compact_guide_bounds(main, layout_guide, resolution, "waiting")
		_check(not arrow.visible and not (layout_guide.get_node("OnboardingDeferButton") as Control).visible, "%s passive waiting shows no false arrow or premature defer action" % resolution)
		_check(layout_guide.show_result_review(review_progress, long_message), "%s opens the long-message result-review card" % resolution)
		await _settle(2)
		_assert_compact_guide_bounds(main, layout_guide, resolution, "result review")
		_check((layout_guide.get_node("OnboardingResultReviewButton") as Control).visible, "%s result-review action remains visible within its card" % resolution)
	layout_guide.invalidate_target()
	layout_guide.queue_free()
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	await _settle(2)


func _assert_compact_guide_bounds(main, guide: Control, resolution: Vector2i, mode: String) -> void:
	var viewport := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var inset := Rect2(Vector2(12.0, 0.0), viewport.size - Vector2(24.0, 0.0))
	var card := guide.get_node("OnboardingGuideCard") as PanelContainer
	_check(card != null and card.is_visible_in_tree() and inset.encloses(card.get_global_rect()), "%s %s keeps the entire guide card at least 12px from both screen sides" % [resolution, mode])
	_check(_guide_card_clears_status_hud(main, guide), "%s %s card does not obscure the persistent city HUD" % [resolution, mode])
	for node_name in ["OnboardingFairy", "OnboardingMessage", "OnboardingArrow", "OnboardingDeferButton", "OnboardingResultReviewButton"]:
		var companion := guide.get_node(node_name) as Control
		if companion.visible:
			_check(viewport.encloses(companion.get_global_rect()), "%s %s keeps %s fully visible" % [resolution, mode, node_name])
			if node_name in ["OnboardingMessage", "OnboardingDeferButton", "OnboardingResultReviewButton"]:
				_check(card.get_global_rect().encloses(companion.get_global_rect()), "%s %s contains %s inside its styled card" % [resolution, mode, node_name])


func _finish(main) -> void:
	_cleanup_save()
	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Onboarding playtest regression test passed.")
	await TestCleanup.finish(self, [main], exit_code)


func _guide_card_clears_status_hud(main, guide_override: Control = null) -> bool:
	var guide: Control = guide_override if guide_override != null else main.onboarding_guide
	var card := guide.get_node_or_null("OnboardingGuideCard") as PanelContainer
	if card == null or not card.is_visible_in_tree() or main.status_hud == null:
		return false
	return not card.get_global_rect().intersects(main.status_hud.get_global_rect())


func _wait_for_loading(main) -> void:
	for _frame in range(120):
		await process_frame
		if not main.start_screen.is_loading():
			return
	_check(false, "loading animation finishes within 120 frames")


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


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame


func _cleanup_save() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	for candidate in [absolute_path, absolute_path + ".tmp", absolute_path + ".bak"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Onboarding playtest regression check failed: %s" % message)
