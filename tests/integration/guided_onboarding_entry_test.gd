extends SceneTree

const IntroCinematicScript := preload("res://ui/tutorial/intro_cinematic.gd")
const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const TEST_SAVE_PATH := "user://mayor_simulator/tests/guided_onboarding_entry.json"

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_save()
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	_check(str(ProjectSettings.get_setting("application/run/main_scene", "")) == "res://scenes/Main.tscn", "project.godot enters the canonical Main scene")

	var first = _new_main()
	await _settle(3)
	_check(str(first.get_script().resource_path) == "res://scripts/app/main.gd", "Main.tscn uses the canonical main.gd")
	first.start_save_path = TEST_SAVE_PATH
	first.start_screen.animation_duration = 0.04
	first.start_screen.new_game_button.emit_signal("pressed")
	await _wait_for_loading(first)
	await _settle(3)
	_check(first.tutorial_overlay != null and first.tutorial_overlay.get_script() == IntroCinematicScript, "formal new-game entry owns IntroCinematic rather than TutorialStoryOverlay")
	_check(first.tutorial_overlay.name == "IntroCinematic" and first.tutorial_overlay.is_open(), "first entry visibly opens the fixed CG sequence")
	_check(first.tutorial_overlay.current_index == 0 and first.tutorial_overlay.PAGES.size() == 8, "first entry starts on shot one of eight")
	_check(first.tutorial_overlay.skip_button != null and first.tutorial_overlay.skip_button.visible, "the previously supported skip action remains available")
	_check(first.onboarding_progress.is_story_pending() and first.onboarding_progress.receipts().is_empty(), "CG presentation cannot create an authoritative receipt")
	_check(not first.onboarding_guide.is_open() and first.vertical_slice.is_time_paused(), "CG blocks the guide and pauses simulation until completion")
	_assert_cinematic_modal_order(first, "initial CG")
	root.content_scale_size = Vector2i(1440, 900)
	root.size = Vector2i(1440, 900)
	await _settle(3)
	_assert_cinematic_modal_order(first, "resized initial CG")
	var cg_authority_before := _presentation_authority_snapshot(first)
	await _click_at(first.municipal_button.get_global_rect().get_center())
	_check(first.municipal_overlay == null, "CG consumes the pointer before the underlying Municipal button can open its lazy overlay")
	_check(_presentation_authority_snapshot(first) == cg_authority_before, "CG pointer handling cannot change date, funds, report history, or guide receipts")

	first.tutorial_overlay.skip_button.emit_signal("pressed")
	await _settle(5)
	_check(not first.tutorial_overlay.is_open(), "skip closes the CG")
	_check(first.onboarding_progress.is_active() and first.onboarding_progress.current_target() == "build", "skip begins the same ordered nine-step guide at build")
	_check(first.onboarding_progress.receipts().is_empty(), "skip grants no build or later receipt")
	_check(first.onboarding_guide.is_open() and first.onboarding_guide.is_product_mode(), "build target receives the arrow and mask guide")
	_check(first.onboarding_guide.target_control() != null, "build guide binds a real visible product control")
	_check(not first.vertical_slice.is_time_paused(), "product guide does not freeze the game clock")
	_check(first.vertical_slice.has_save_game(TEST_SAVE_PATH), "story-to-guide transition is persisted for continue")
	_assert_guide_presentation(first, first.municipal_button, "bottom-edge Municipal target")
	var guide_authority_before := _presentation_authority_snapshot(first)
	await _click_at(first.municipal_button.get_global_rect().get_center())
	await _settle(4)
	_check(first.municipal_overlay != null and first.municipal_overlay.is_open(), "guided Municipal target opens the real lazy modal")
	var buildings_target := first.onboarding_guide.target_control() as Control
	_check(buildings_target != null and buildings_target.name == "BuildingsButton", "guide rebinds to the real Buildings destination inside the Municipal modal")
	_assert_guide_presentation(first, buildings_target, "Municipal modal target")
	_check(_presentation_authority_snapshot(first) == guide_authority_before, "opening the guided Municipal modal cannot change date, funds, report history, or guide receipts")
	first.settings_overlay.open()
	await _settle(2)
	_check(_draws_after(first.settings_overlay, first.onboarding_guide), "Settings opened after the guide retains modal priority")
	first.settings_overlay.close()
	first.exit_confirmation.open()
	await _settle(2)
	_check(_draws_after(first.exit_confirmation, first.onboarding_guide), "Exit confirmation opened after the guide retains terminal modal priority")
	first.exit_confirmation.close()
	await _click_at(buildings_target.get_global_rect().get_center())
	await _settle(3)
	var residence_target := first.onboarding_guide.target_control() as Control
	if residence_target != null and residence_target.name == "BuildingGroup_housing":
		await _click_at(residence_target.get_global_rect().get_center())
		await _settle(3)
		residence_target = first.onboarding_guide.target_control() as Control
	_check(residence_target != null and residence_target.name == "BuildingCard_住宅", "guided housing group click advances through the real Residence card")
	await _click_at(residence_target.get_global_rect().get_center())
	await _settle(4)
	var blueprint_target := first.onboarding_guide.target_control() as Control
	var blueprint_scroll := _scroll_ancestor(blueprint_target)
	var blueprint_viewport := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var target_rect := blueprint_target.get_global_rect() if blueprint_target != null else Rect2()
	var effective_rect := target_rect.intersection(blueprint_viewport)
	if blueprint_scroll != null:
		effective_rect = effective_rect.intersection(blueprint_scroll.get_global_rect())
	_check(blueprint_target != null and blueprint_target.name == "SubmitBlueprintButton", "Residence selection binds the guide to the real SubmitBlueprintButton")
	_check(blueprint_scroll != null and blueprint_scroll.scroll_vertical > 0, "product guide scrolls the blueprint ScrollContainer to reveal SubmitBlueprintButton")
	_check(effective_rect.has_area() and effective_rect.encloses(target_rect), "SubmitBlueprintButton has a complete clickable rect inside its clip viewport")
	var blueprint_authority_before := _presentation_authority_snapshot(first)
	await _click_at(blueprint_target.get_global_rect().get_center())
	await _settle(4)
	_check(first.placement_mode_active, "real SubmitBlueprintButton click enters placement mode")
	_check(first.onboarding_progress.receipts().is_empty(), "entering placement from SubmitBlueprintButton creates no build receipt")
	_check(_presentation_authority_snapshot(first) == blueprint_authority_before, "SubmitBlueprintButton click changes neither date, funds, report history, nor authoritative receipts")
	var placement_target := first.onboarding_guide.target_control() as Button
	var placement_index: int = first.grid_buttons.find(placement_target)
	var placement_workers: int = int(first.vertical_slice_panel.selected_worker_count()) if first.vertical_slice_panel != null else 5
	var placement_quote: Dictionary = first.vertical_slice.placement_footprint_quote(first.placement_building_name, placement_index, placement_workers)
	var placement_viewport := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var placement_target_rect := placement_target.get_global_rect() if placement_target != null else Rect2()
	var placement_effective_rect := placement_target_rect.intersection(placement_viewport)
	var placement_scroll := _scroll_ancestor(placement_target)
	if placement_scroll != null:
		placement_effective_rect = placement_effective_rect.intersection(placement_scroll.get_global_rect())
	_check(placement_target != null and placement_index >= 0, "build guide binds a real dynamic grid tile")
	_check(bool(placement_quote.get("ok", false)) and str(placement_quote.get("status", "")) == "approved" and bool(placement_quote.get("can_afford", false)), "build guide tile has an approved affordable authoritative placement quote")
	_check(placement_effective_rect.encloses(placement_target_rect) and placement_effective_rect.has_point(placement_target_rect.get_center()), "build guide tile center is fully visible through viewport and clipping ancestors")
	var occupied_tile_ids: Array = placement_quote.get("occupied_tile_ids", [])
	_check(not occupied_tile_ids.is_empty(), "build guide quote exposes its complete dynamic footprint")
	for occupied_tile_variant: Variant in occupied_tile_ids:
		_check(first._is_tile_inside_hud_safe_area(int(occupied_tile_variant)), "build guide quote keeps every occupied footprint tile outside the HUD safe area")
	var placement_authority_before := _presentation_authority_snapshot(first)
	await _click_at(placement_target_rect.get_center())
	await _settle(4)
	_check(first._pending_construction_tile == placement_index, "real guided grid click selects the dynamic quoted anchor tile")
	_check(first.construction_confirmation != null and first.construction_confirmation.is_open(), "real guided grid click opens construction confirmation")
	var confirmation_target := first.onboarding_guide.target_control() as Control
	_check(confirmation_target != null and confirmation_target.name == "ConfirmConstructionButton", "guide rebinds to the real construction confirmation action")
	_check(_presentation_authority_snapshot(first) == placement_authority_before, "construction confirmation opens before changing date, funds, jobs, report history, or receipts")

	await TestCleanup.release_fixtures(self, [first])
	var resumed = _new_main()
	await _settle(3)
	resumed.start_save_path = TEST_SAVE_PATH
	resumed.start_screen.set_continue_available(true)
	resumed.start_screen.animation_duration = 0.04
	resumed.start_screen.continue_game_button.emit_signal("pressed")
	await _wait_for_loading(resumed)
	await _settle(5)
	_check(resumed.onboarding_progress.is_active() and resumed.onboarding_progress.current_target() == "build", "continue restores the exact first actionable target")
	_check(resumed.onboarding_progress.receipts().is_empty(), "continue cannot synthesize receipts")
	_check(not resumed.tutorial_overlay.is_open(), "continue does not replay an already-seen CG")
	_check(resumed.onboarding_guide.is_open() and resumed.onboarding_guide.is_product_mode(), "continue restores the real target guide")

	var replay_authority_before := _presentation_authority_snapshot(resumed)
	resumed.call("_replay_tutorial")
	await _settle(3)
	_check(resumed.tutorial_overlay.is_open() and resumed.tutorial_overlay.current_index == 0, "settings replay reopens the CG from shot one")
	_assert_cinematic_modal_order(resumed, "settings replay CG")
	_check(_presentation_authority_snapshot(resumed) == replay_authority_before, "replaying the CG cannot change date, funds, report history, or guide receipts")
	resumed.tutorial_overlay.skip_button.emit_signal("pressed")
	await _settle(3)
	_check(resumed.onboarding_progress.current_target() == "build" and resumed.onboarding_progress.receipts().is_empty(), "replay completion cannot reset, complete, or skip the authoritative guide")

	_cleanup_save()
	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Guided onboarding formal entry test passed.")
	await TestCleanup.finish(self, [resumed], exit_code)


func _new_main():
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main := packed.instantiate()
	root.add_child(main)
	return main


func _wait_for_loading(main) -> void:
	for _frame in range(120):
		await process_frame
		if not main.start_screen.is_loading():
			return
	_fail("loading animation did not finish within 120 frames")


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame


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


func _assert_cinematic_modal_order(main, phase: String) -> void:
	var cinematic := main.tutorial_overlay as Control
	var viewport_rect := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	_check(cinematic != null and not cinematic.z_as_relative and cinematic.z_index == RenderingServer.CANVAS_ITEM_Z_MAX, "%s owns an absolute top-level canvas order" % phase)
	_check(cinematic != null and viewport_rect.encloses(cinematic.get_global_rect()), "%s covers the resized viewport" % phase)
	_check(_draws_after(cinematic, main.status_hud) and _draws_after(cinematic, main.action_dock), "%s draws above every persistent HUD surface" % phase)
	for actor: Button in main.get_visible_npc_actors():
		_check(cinematic.z_index > actor.z_index, "%s draws above each depth-sorted NPC actor" % phase)
	_check(cinematic.get_parent() == main and cinematic.get_index() == main.get_child_count() - 1, "%s moves to the front of the real Main sibling stack" % phase)


func _assert_guide_presentation(main, expected_target: Control, phase: String) -> void:
	var guide := main.onboarding_guide as Control
	var viewport_rect := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	_check(guide != null and guide.target_control() == expected_target, "%s keeps the authoritative product target" % phase)
	_check(guide != null and not guide.z_as_relative and guide.z_index == RenderingServer.CANVAS_ITEM_Z_MAX, "%s owns absolute modal presentation order" % phase)
	if main.municipal_overlay != null and main.municipal_overlay.is_open():
		_check(_draws_after(guide, main.municipal_overlay), "%s remains visible above the Municipal modal containing its target" % phase)
	var target_rect := expected_target.get_global_rect() if expected_target != null else Rect2()
	for node_name in ["OnboardingFairy", "OnboardingMessage", "OnboardingArrow"]:
		var companion := guide.get_node_or_null(node_name) as Control
		_check(companion != null and companion.is_visible_in_tree(), "%s keeps %s visible" % [phase, node_name])
		if companion != null:
			_check(viewport_rect.encloses(companion.get_global_rect()), "%s keeps %s inside the viewport" % [phase, node_name])
	var fairy := guide.get_node_or_null("OnboardingFairy") as Control
	var message := guide.get_node_or_null("OnboardingMessage") as Control
	_check(fairy != null and not fairy.get_global_rect().intersects(target_rect), "%s keeps the fairy outside the target hit area" % phase)
	_check(message != null and not message.get_global_rect().intersects(target_rect), "%s keeps the readable message outside the target hit area" % phase)
	var target_center := target_rect.get_center()
	for index in 4:
		_check(not (guide.get_child(index) as Control).get_global_rect().has_point(target_center), "%s keeps mask %d outside the target hole" % [phase, index])


func _draws_after(front: Control, back: Control) -> bool:
	if front == null or back == null:
		return false
	if front.z_index != back.z_index:
		return front.z_index > back.z_index
	return front.get_parent() == back.get_parent() and front.get_index() > back.get_index()


func _presentation_authority_snapshot(main) -> Dictionary:
	return {
		"game_day": main.vertical_slice.game_day(),
		"treasury": main.vertical_slice.treasury_balance(),
		"construction_jobs": main.vertical_slice.session.state.construction.jobs.duplicate(true),
		"report_history": main.city_report_history_service.snapshot(),
		"receipts": main.onboarding_progress.receipts(),
	}


func _scroll_ancestor(control: Control) -> ScrollContainer:
	var ancestor := control.get_parent() if control != null else null
	while ancestor != null:
		if ancestor is ScrollContainer:
			return ancestor as ScrollContainer
		ancestor = ancestor.get_parent()
	return null


func _cleanup_save() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	for candidate in [absolute_path, absolute_path + ".tmp", absolute_path + ".bak"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _fail(message: String) -> void:
	_failed = true
	push_error("Guided onboarding entry check failed: %s" % message)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)
