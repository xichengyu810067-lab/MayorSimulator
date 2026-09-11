extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const TransportPlanningSessionScript := preload("res://scripts/systems/city/transport_planning_session.gd")

const SAVE_PATH := "user://r4c_onboarding_feature_flow.json"

var _failed := false
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	root.content_scale_size = Vector2i(1440, 900)
	root.size = Vector2i(1440, 900)
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	main.start_save_path = SAVE_PATH
	root.add_child(main)
	await _settle(5)
	main.start_screen.hide()
	main.call("_initialize_fresh_game")
	main.set("_game_started", true)
	main.onboarding_progress.begin_guide()
	main.call("_refresh_onboarding_guide")
	await _settle(3)

	_check(main.onboarding_progress.current_target() == "build", "fresh guide starts at build")
	_check(main.onboarding_guide.is_product_mode(), "product guide observes input without synthetic advancement")
	_check(not main.onboarding_action_router.record_build_success("住宅", false, {"ok": false}, 0), "failed current-domain result cannot advance")
	_check(not main.onboarding_action_router.record_route_package_success({"ok": true, "session": {"workflow": "route_package_v1", "id": "session_wrong_order"}}, 0), "out-of-order success-shaped result cannot advance")
	_check(main.onboarding_progress.receipts().is_empty(), "rejected results leave onboarding receipts unchanged")
	var municipal := main.get_node_or_null("ActionDock/ActionButtonRow/MunicipalButton") as Button
	_check(municipal != null and main.onboarding_guide.target_control() == municipal, "build arrow initially points to the real municipal button")
	if municipal != null:
		await _click_at(municipal.get_global_rect().get_center())
	_check(main.onboarding_progress.current_target() == "build", "clicking a guide target alone cannot advance without domain success")

	var building_job_count_before: int = main.vertical_slice.construction.jobs.size()
	var construction_autosaves := int(main.get("_autosave_count"))
	var treasury_before_build: int = main.vertical_slice.treasury_balance()
	_press_named(main, "BuildingsButton")
	await _settle(2)
	_press_named(main, "BuildingCard_住宅")
	await _settle(2)
	_press_named(main, "SubmitBlueprintButton")
	await _settle(2)
	var build_tile := _find_placeable_anchor(main, "住宅", [main.vertical_slice.terrain_map.tile_id_for_coordinate(Vector2i(2, 3)), main.vertical_slice.terrain_map.tile_id_for_coordinate(Vector2i(6, 3))])
	_check(build_tile >= 0, "official residence has a valid placement target")
	if build_tile >= 0:
		(main.grid_buttons[build_tile] as Button).pressed.emit()
		await _settle(2)
		_press_named(main, "ConfirmConstructionButton")
		await _settle(3)
	var build_receipt := _receipt_at(main, 0)
	_check(main.onboarding_progress.current_target() == "blueprint", "construction success advances build exactly once")
	_check(str(build_receipt.get("authority_id", "")) == "construction_job" and not str(build_receipt.get("entity_id", "")).is_empty(), "build receipt uses canonical construction job authority and id")
	_check(main.vertical_slice.construction.jobs.size() == building_job_count_before + 1, "build creates one construction job")
	_check(main.vertical_slice.treasury_balance() < treasury_before_build, "build charges the authoritative treasury")
	_check(int(main.get("_autosave_count")) == construction_autosaves + 1, "build success and receipt share one autosave")
	var build_autosaves_after := int(main.get("_autosave_count"))
	main.call("_confirm_pending_construction", build_tile)
	_check(int(main.get("_autosave_count")) == build_autosaves_after and main.onboarding_progress.receipts().size() == 1, "duplicate construction callback is zero-write")

	_open_hub(main)
	_press_named(main, "BuildingsButton")
	await _settle(2)
	main.building_family_tabs.current_tab = 1
	await _settle(2)
	_press_named(main, "BuildingGroup_community")
	_press_named(main, "BuildingCard_公園")
	await _settle(3)
	var material = main.find_child("BlueprintMaterial", true, false)
	var material_before := str(material.call("selected_choice_id")) if material != null else ""
	var material_after := "brick" if material_before != "brick" else "steel"
	_check(_select_progressive_choice(material, material_after), "real blueprint picker signal changes one Park design field")
	await _settle(3)
	_check(main.onboarding_action_router.blueprint_design_changed(), "router observes a real changed design field")
	var blueprint_autosaves := int(main.get("_autosave_count"))
	_press_named(main, "SubmitCustomBlueprintButton")
	await _settle(3)
	var blueprint_receipt := _receipt_at(main, 1)
	_check(main.onboarding_progress.current_target() == "route", "successful changed Park blueprint advances once")
	_check(str(blueprint_receipt.get("authority_id", "")) == "blueprint_review" and not str(blueprint_receipt.get("entity_id", "")).is_empty(), "blueprint receipt uses canonical review id")
	_check(int(main.get("_autosave_count")) == blueprint_autosaves + 1, "blueprint success and receipt share existing autosave")
	var blueprint_autosaves_after := int(main.get("_autosave_count"))
	_press_named(main, "SubmitCustomBlueprintButton")
	await _settle(2)
	_check(int(main.get("_autosave_count")) == blueprint_autosaves_after and main.onboarding_progress.receipts().size() == 2, "duplicate blueprint signal fails closed")

	var transport_setup := _prepare_route_package(main)
	_check(bool(transport_setup.get("ok", false)), "route package reaches the authoritative ready-to-confirm state: %s" % [transport_setup])
	main.call("_open_transport_planning")
	await _settle(3)
	var route_autosaves := int(main.get("_autosave_count"))
	var route_treasury: int = main.vertical_slice.treasury_balance()
	var negative_ledger_before := _negative_ledger_count(main.vertical_slice)
	_press_named(main, "TransportPlanningSessionContinue")
	await _settle(4)
	var route_receipt := _receipt_at(main, 2)
	_check(main.onboarding_progress.current_target() == "fiscal", "successful R3 package advances route once")
	_check(str(route_receipt.get("authority_id", "")) == "transport_session" and not str(route_receipt.get("entity_id", "")).is_empty(), "route receipt uses returned canonical session id")
	_check(main.vertical_slice.treasury_balance() < route_treasury and _negative_ledger_count(main.vertical_slice) == negative_ledger_before + 1, "route package charges and records one authoritative ledger entry")
	_check(int(main.get("_autosave_count")) == route_autosaves + 1, "route package events and receipt share one autosave")
	var route_autosaves_after := int(main.get("_autosave_count"))
	var duplicate_route := main.find_child("TransportPlanningSessionContinue", true, false) as Button
	_check(duplicate_route != null and duplicate_route.disabled, "route package disables replay while construction waits")
	if duplicate_route != null:
		duplicate_route.pressed.emit()
	await _settle(2)
	_check(int(main.get("_autosave_count")) == route_autosaves_after and main.onboarding_progress.receipts().size() == 3, "duplicate route continue cannot replay the package")

	_open_hub(main)
	await _settle(2)
	_press_named(main, "FinanceButton")
	await _settle(3)
	var income_slider := main.find_child("FiscalSlider_tax_income", true, false) as HSlider
	_check(income_slider != null, "fiscal income slider exists")
	if income_slider != null:
		income_slider.value = clampf(income_slider.value + 1.0, income_slider.min_value, income_slider.max_value)
	await _settle(2)
	_press_named(main, "FiscalPreviewButton")
	await _settle(2)
	var fiscal_autosaves := int(main.get("_autosave_count"))
	var fiscal_generation := int(main.get("_fiscal_apply_generation"))
	_press_named(main, "FiscalApplyAllButton")
	await _settle(3)
	var fiscal_receipt := _receipt_at(main, 3)
	_check(main.onboarding_progress.current_target() == "city_data", "matching preview revision and changed draft advance fiscal")
	_check(str(fiscal_receipt.get("entity_id", "")) == "fiscal_apply_%06d" % (fiscal_generation + 1), "fiscal receipt binds the actual apply generation")
	_check(int(main.get("_autosave_count")) == fiscal_autosaves + 1, "fiscal apply and receipt share one autosave")
	var fiscal_autosaves_after := int(main.get("_autosave_count"))
	var duplicate_fiscal := main.find_child("FiscalApplyAllButton", true, false) as Button
	_check(duplicate_fiscal != null and duplicate_fiscal.disabled, "applied fiscal preview disables replay")
	if duplicate_fiscal != null:
		duplicate_fiscal.pressed.emit()
	_check(int(main.get("_autosave_count")) == fiscal_autosaves_after and main.onboarding_progress.receipts().size() == 4, "stale fiscal apply is zero-write")

	_open_hub(main)
	await _settle(2)
	_press_named(main, "City DataButton")
	await _settle(3)
	var city_autosaves := int(main.get("_autosave_count"))
	var first_tab: int = main.city_data_dashboard.current_tab
	main.city_data_dashboard.current_tab = (first_tab + 1) % main.city_data_dashboard.get_tab_count()
	await _settle(3)
	var city_receipt := _receipt_at(main, 4)
	_check(main.onboarding_progress.current_target() == "public_affairs", "opening data then switching to another valid tab advances")
	_check(str(city_receipt.get("authority_id", "")) == "city_data_dashboard", "city data receipt identifies dashboard authority")
	_check(int(main.get("_autosave_count")) == city_autosaves + 1, "city-data tab receipt autosaves once")

	_open_hub(main)
	await _settle(2)
	_press_named(main, "Public AffairsButton")
	await _settle(3)
	var pending_id := _first_pending_request_id(main)
	var public_autosaves := int(main.get("_autosave_count"))
	_check(not pending_id.is_empty(), "public affairs exposes a pending active request")
	if not pending_id.is_empty():
		_press_named(main, "AcceptRequest_%s" % pending_id)
	await _settle(4)
	var public_receipt := _receipt_at(main, 5)
	_check(main.onboarding_progress.current_target() == "governance", "pending-to-accepted domain success advances public affairs")
	_check(str(public_receipt.get("authority_id", "")) == "resident_request" and str(public_receipt.get("entity_id", "")) == pending_id, "public receipt binds the accepted request id")
	_check(int(main.get("_autosave_count")) == public_autosaves + 1, "public accept, completion reconciliation, and receipt use one autosave")
	main.call("_refresh_onboarding_guide")
	_check(not main.onboarding_action_router.supports_current_target() and not main.onboarding_guide.is_open(), "governance remains locked without an adapter or fake arrow")

	var saved_receipts: Array[Dictionary] = main.onboarding_progress.receipts()
	for receipt in saved_receipts:
		_check(_has_exact_receipt_keys(receipt), "each committed receipt contains only the bounded four-key contract")
	var saved_treasury: int = main.vertical_slice.treasury_balance()
	var saved_job_ids: Array[String] = _sorted_keys(main.vertical_slice.session.state.construction_jobs)
	var saved_transport_ids: Dictionary = _transport_identity(main.vertical_slice.transport.to_dict())
	var saved_request_statuses: Dictionary = _request_statuses(main)
	var restored := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	restored.start_save_path = SAVE_PATH
	root.add_child(restored)
	await _settle(4)
	restored.start_screen.hide()
	restored.set("_game_started", true)
	var load_ok: bool = restored.vertical_slice.load_game(SAVE_PATH)
	_check(load_ok, "saved six-step state loads")
	var shell_state: Dictionary = restored.vertical_slice.get_player_shell_state()
	_check(bool(restored.call("_restore_player_shell_state", shell_state)), "schema 9 onboarding shell restores")
	restored.call("_refresh_onboarding_guide")
	_check(restored.onboarding_progress.current_target() == "governance" and restored.onboarding_progress.receipts() == saved_receipts, "reload resumes exact guide target and bounded receipts")
	_check(restored.vertical_slice.treasury_balance() == saved_treasury, "reload does not replay any treasury cost")
	_check(_sorted_keys(restored.vertical_slice.session.state.construction_jobs) == saved_job_ids, "reload preserves construction IDs without replay")
	_check(_transport_identity(restored.vertical_slice.transport.to_dict()) == saved_transport_ids, "reload preserves transport IDs without replay")
	_check(_request_statuses(restored) == saved_request_statuses, "reload preserves request status without replaying accept")

	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Onboarding feature flow test passed. Checks=%d" % _checks)
	_cleanup()
	await TestCleanup.finish(self, [main, restored], exit_code)


func _prepare_route_package(main) -> Dictionary:
	var coordinator = main.vertical_slice
	var fixture: Dictionary = _find_route_fixture(main)
	if fixture.is_empty():
		return {"ok": false, "error": "no_authoritative_route_fixture"}
	var station_a: int = int(fixture["station_a"])
	var station_b: int = int(fixture["station_b"])
	var route_tiles: Array[int] = []
	for tile_variant: Variant in fixture["route_tiles"]:
		route_tiles.append(int(tile_variant))
	var begun: Dictionary = coordinator.begin_transport_planning_session("公車站", TransportPlanningSessionScript.WORKFLOW_ROUTE_PACKAGE_V1)
	if not bool(begun.get("ok", false)):
		return begun
	for station_tile in [station_a, station_b]:
		var drafted: Dictionary = coordinator.draft_transport_session_station(station_tile, 1)
		if not bool(drafted.get("ok", false)):
			return drafted
	var network: Dictionary = coordinator.begin_transport_session_network_placement("road", {})
	if not bool(network.get("ok", false)):
		return network
	var route: Dictionary = coordinator.draft_transport_session_network("road", route_tiles, 1)
	if not bool(route.get("ok", false)):
		return route
	return coordinator.begin_transport_session_route_edit({"fleet_size": 2, "headway_minutes": 8, "fare": 25})


func _find_route_fixture(main) -> Dictionary:
	var coordinator = main.vertical_slice
	var grid_size: Vector2i = coordinator.terrain_map.grid_size()
	for station_row in range(0, grid_size.y - 1):
		for first_column in range(0, grid_size.x - 4):
			var station_a: int = coordinator.terrain_map.tile_id_for_coordinate(Vector2i(first_column, station_row))
			var station_b: int = coordinator.terrain_map.tile_id_for_coordinate(Vector2i(first_column + 4, station_row))
			var first_quote: Dictionary = coordinator.placement_footprint_quote("公車站", station_a, 1)
			var second_quote: Dictionary = coordinator.placement_footprint_quote("公車站", station_b, 1)
			if not bool(first_quote.get("ok", false)) or not bool(second_quote.get("ok", false)):
				continue
			var route_tiles: Array[int] = []
			for column in range(first_column, first_column + 5):
				route_tiles.append(coordinator.terrain_map.tile_id_for_coordinate(Vector2i(column, station_row + 1)))
			var route_quote: Dictionary = coordinator.transport_project_quote("road", "build", route_tiles, 1, main.city_grid)
			if bool(route_quote.get("ok", false)):
				return {"station_a": station_a, "station_b": station_b, "route_tiles": route_tiles}
	return {}


func _find_placeable_anchor(main, building_name: String, excluded: Array) -> int:
	for index in range(main.city_grid.size() - 1, -1, -1):
		if index in excluded or not main.call("_is_tile_inside_hud_safe_area", index):
			continue
		var quote: Dictionary = main.vertical_slice.placement_footprint_quote(building_name, index, 1)
		if bool(quote.get("ok", false)) and str(quote.get("status", "")) == "approved":
			return index
	return -1


func _open_hub(main) -> void:
	if main.municipal_overlay != null and main.municipal_overlay.is_open():
		main.municipal_overlay.close_overlay()
	main.municipal_button.pressed.emit()


func _press_named(main, node_name: String) -> void:
	var button := main.find_child(node_name, true, false) as BaseButton
	_check(button != null and not button.disabled, "%s is a real enabled UI target" % node_name)
	if button != null and not button.disabled:
		button.pressed.emit()


func _select_progressive_choice(control, choice_id: String) -> bool:
	if control == null:
		return false
	for index in control.item_count:
		if str(control.get_item_metadata(index)) == choice_id:
			control.item_selected.emit(index)
			return true
	return false


func _receipt_at(main, index: int) -> Dictionary:
	var receipts: Array[Dictionary] = main.onboarding_progress.receipts()
	return receipts[index] if index >= 0 and index < receipts.size() else {}


func _has_exact_receipt_keys(receipt: Dictionary) -> bool:
	return (
		receipt.size() == 4
		and receipt.has("kind")
		and receipt.has("authority_id")
		and receipt.has("entity_id")
		and receipt.has("game_day")
	)


func _first_pending_request_id(main) -> String:
	for request_variant: Variant in main.vertical_slice.get_view_model(main.selected_cell_index).get("citizen_requests", []):
		if request_variant is Dictionary and str(Dictionary(request_variant).get("status", "")) == "pending":
			return str(Dictionary(request_variant).get("request_id", ""))
	return ""


func _negative_ledger_count(coordinator) -> int:
	var result := 0
	for entry: Dictionary in coordinator.session.state.ledger.get_entries():
		if int(entry.get("amount", 0)) < 0:
			result += 1
	return result


func _transport_identity(snapshot: Dictionary) -> Dictionary:
	var result := {}
	for key in ["projects", "routes", "stations", "facilities", "segments"]:
		result[key] = _sorted_keys(Dictionary(snapshot.get(key, {})))
	return result


func _request_statuses(main) -> Dictionary:
	var result := {}
	for request_variant: Variant in main.vertical_slice.get_view_model(main.selected_cell_index).get("citizen_requests", []):
		if request_variant is Dictionary:
			var request := request_variant as Dictionary
			result[str(request.get("request_id", ""))] = str(request.get("status", ""))
	return result


func _sorted_keys(value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key_variant: Variant in value.keys():
		result.append(str(key_variant))
	result.sort()
	return result


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


func _cleanup() -> void:
	for path in [SAVE_PATH, "%s.bak" % SAVE_PATH, "%s.tmp" % SAVE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Onboarding feature flow check failed: %s" % message)
