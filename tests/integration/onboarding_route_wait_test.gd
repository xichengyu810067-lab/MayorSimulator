extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")

var _failed := false


class RouteAuthorityStub:
	extends RefCounted

	var package_quote: Dictionary
	var paused := false


	func _init(p_package_quote: Dictionary) -> void:
		package_quote = p_package_quote.duplicate(true)


	func transport_planning_session_snapshot() -> Dictionary:
		return {
			"state": "route_edit",
			"workflow": "route_package_v1",
			"route_draft": {"station_placements": [{}, {}]},
			"network_draft": {"tile_ids": [1, 2]},
		}


	func transport_session_package_quote(_city_grid: Array = []) -> Dictionary:
		return package_quote.duplicate(true)


	func game_day() -> int:
		return 6


	func set_time_paused(value: bool) -> void:
		paused = value


	func is_time_paused() -> bool:
		return paused


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	_check(str(main.call("_onboarding_date_label", 31)) == "第 1 年 2 月 2 日", "game day 31 renders with the authoritative 30-day month calendar")
	var original_vertical_slice = main.vertical_slice
	main.vertical_slice = RouteAuthorityStub.new({
		"ok": true,
		"can_afford": true,
		"can_start": false,
		"available_workers": 0,
		"requested_workers": 5,
	})
	_check(main.call("_resolve_route_onboarding_target") == null, "a closed route package with only a temporary worker shortage does not reopen Municipal")
	var restored: Dictionary = main.onboarding_progress.restore_from_shell_state(_route_active_shell())
	_check(bool(restored.get("ok", false)), "route waiting fixture restores through the public snapshot contract")
	main.start_screen.hide()
	main.set("_game_started", true)
	if main.municipal_overlay != null and main.municipal_overlay.is_open():
		main.municipal_overlay.close_overlay()
	main.call("_refresh_onboarding_guide")
	await process_frame
	var waiting_text := (main.onboarding_guide.get_node("OnboardingMessage") as Label).text
	_check(main.onboarding_guide.is_waiting_mode() and not main.onboarding_guide.is_open(), "temporary worker shortage uses a non-modal waiting presentation")
	_check("人力不足" in waiting_text and "可先處理城市與工程" in waiting_text, "temporary worker shortage remains visible and explains player action without promising automatic recovery")
	_check(not main.vertical_slice.is_time_paused(), "temporary worker shortage leaves city time running")

	main.vertical_slice.package_quote = {
		"ok": true,
		"can_afford": false,
		"can_start": false,
		"available_workers": 5,
		"requested_workers": 5,
		"total_cost": 125000,
	}
	_check(main.call("_resolve_route_onboarding_target") == null, "a closed package with insufficient funding does not restart the Municipal loop")
	main.call("_refresh_onboarding_guide")
	await process_frame
	waiting_text = (main.onboarding_guide.get_node("OnboardingMessage") as Label).text
	_check(main.onboarding_guide.is_waiting_mode() and "資金不足" in waiting_text and "城市財政" in waiting_text, "funding shortage uses a visible non-modal explanation and keeps the defer action")
	_check(not main.vertical_slice.is_time_paused(), "funding shortage leaves city time running")

	main.vertical_slice.package_quote = {"ok": false, "error": "transport_session_network_required"}
	_check(main.call("_resolve_route_onboarding_target") == main.municipal_button, "an invalid package requiring player repair remains reachable")
	main.call("_refresh_onboarding_guide")
	await process_frame
	waiting_text = (main.onboarding_guide.get_node("OnboardingMessage") as Label).text
	_check(main.onboarding_guide.is_waiting_mode() and "資料尚未完整" in waiting_text and "重新開啟市政中心" in waiting_text, "invalid package explains how to return to the preserved draft instead of guiding another Close")
	_check(main.vertical_slice.transport_planning_session_snapshot().get("state", "") == "route_edit", "invalid package guidance preserves the route-edit draft")

	main.vertical_slice.package_quote = {
		"ok": true,
		"can_afford": true,
		"can_start": true,
		"available_workers": 5,
		"requested_workers": 5,
	}
	_check(main.call("_resolve_route_onboarding_target") == main.municipal_button, "an authority-ready package restores the Municipal entry")
	main.call("_refresh_onboarding_guide")
	await process_frame
	_check(main.onboarding_guide.is_product_mode() and main.onboarding_guide.target_control() == main.municipal_button, "an authority-ready package replaces the waiting presentation with the real Municipal target")
	main.vertical_slice = original_vertical_slice
	if not _failed:
		print("Onboarding route wait test passed.")
	await TestCleanup.finish(self, [main], 1 if _failed else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Onboarding route wait check failed: %s" % message)


func _route_active_shell() -> Dictionary:
	return {
		"schema_version": 9,
		"tutorial_completed": false,
		"onboarding": {
			"schema_version": 2,
			"phase": "active",
			"next_index": 2,
			"current_target": "route",
			"completion_basis": "",
			"receipts": [
				{"kind": "build", "authority_id": "construction_job", "entity_id": "job_route_wait", "game_day": 0},
				{"kind": "blueprint", "authority_id": "blueprint_review", "entity_id": "review_route_wait", "game_day": 3},
			],
			"due_game_day": -1,
		},
	}
