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
	await _settle(2)
	_check(main.onboarding_progress.current_target() == "governance" and main.onboarding_action_router.supports_current_target(), "governance adapter activates only after the first six authoritative receipts")
	_check(main.onboarding_guide.is_product_mode(), "governance guide points at real UI without synthetic advancement")
	_check(not main.onboarding_action_router.record_governance_force_success({"ok": false}, main.vertical_slice.governance, main.vertical_slice.session.state.event_book, main.vertical_slice.governance.checks_and_balances_history, main.vertical_slice.game_day()), "failed governance result cannot create a receipt")
	_check(not main.onboarding_action_router.record_judicial_defense_success("judicial_wrong_order", "public_interest", {"ok": true}, main.vertical_slice.governance, main.vertical_slice.session.state.event_book, main.vertical_slice.game_day()), "out-of-order judicial-shaped success cannot skip governance")

	var governance_step: Dictionary = await _complete_governance_step(main)
	var judicial_case_id := str(governance_step.get("judicial_case_id", ""))
	var oversight_case_id := str(governance_step.get("oversight_case_id", ""))
	_check(bool(governance_step.get("ok", false)), "real bill, hearing, rejection, and force-enact UI completes governance: %s" % governance_step)
	_check(main.onboarding_progress.current_target() == "judicial", "unique force-enact authority advances to judicial defense")
	var ambiguous_event_book: Array = main.vertical_slice.session.state.event_book.duplicate(true)
	for record_variant: Variant in main.vertical_slice.session.state.event_book:
		if record_variant is Dictionary and str(Dictionary(record_variant).get("fact_type", "")) == "bill_force_enacted" and str(Dictionary(record_variant).get("case_id", "")) == judicial_case_id:
			ambiguous_event_book.append(Dictionary(record_variant).duplicate(true))
			break
	_check(main.onboarding_action_router.linked_case_id("judicial", ambiguous_event_book).is_empty(), "ambiguous reload force facts fail closed before judicial routing")
	_check(not main.onboarding_action_router.record_judicial_defense_success(judicial_case_id, "public_interest", {"ok": false}, main.vertical_slice.governance, main.vertical_slice.session.state.event_book, main.vertical_slice.game_day()), "failed judicial result cannot advance the linked case")

	_open_hub(main)
	await _settle(2)
	main.call("_refresh_onboarding_guide")
	await _settle(2)
	_check(_target_name(main) == "JudicialButton", "judicial arrow points to the real municipal destination")
	_press_named(main, "JudicialButton")
	await _settle(3)
	_check(str(main.judicial_panel.selected_case_id()) == judicial_case_id, "judicial page selects the exact force-linked case")
	_check(_target_name(main) == "PublicInterestDefenseButton", "judicial arrow points to a real enabled defense")
	var judicial_autosaves := int(main.get("_autosave_count"))
	_press_named(main, "PublicInterestDefenseButton")
	await _settle(3)
	var judicial_receipt := _receipt_at(main, 7)
	_check(main.onboarding_progress.current_target() == "oversight", "successful linked judicial defense advances once")
	_check(str(judicial_receipt.get("authority_id", "")) == "judicial_case" and str(judicial_receipt.get("entity_id", "")) == judicial_case_id, "judicial receipt binds the canonical force-linked case")
	_check(str(main.vertical_slice.governance.judiciary_cases.get(judicial_case_id, {}).get("defense_template_id", "")) == "public_interest", "judicial authority stores the submitted defense")
	_check(int(main.get("_autosave_count")) == judicial_autosaves + 1, "judicial defense and receipt share one autosave")
	_check(not main.onboarding_action_router.record_oversight_defense_success(oversight_case_id, "full_disclosure", {"ok": false}, main.vertical_slice.governance, main.vertical_slice.session.state.event_book, main.vertical_slice.game_day()), "failed oversight result cannot advance the linked inquiry")

	_open_hub(main)
	await _settle(2)
	main.call("_refresh_onboarding_guide")
	await _settle(2)
	_check(_target_name(main) == "OversightButton", "oversight arrow points to the real municipal destination")
	_press_named(main, "OversightButton")
	await _settle(3)
	_check(str(main.oversight_panel.selected_case_id()) == oversight_case_id, "oversight page selects the exact force-linked inquiry")
	_check(_target_name(main) == "FullDisclosureDefenseButton", "oversight arrow points to a real enabled defense")
	var oversight_autosaves := int(main.get("_autosave_count"))
	_press_named(main, "FullDisclosureDefenseButton")
	await _settle(3)
	var oversight_receipt := _receipt_at(main, 8)
	_check(main.onboarding_progress.is_completed() and main.onboarding_progress.current_target().is_empty(), "ninth authoritative action completes onboarding")
	_check(str(oversight_receipt.get("authority_id", "")) == "oversight_case" and str(oversight_receipt.get("entity_id", "")) == oversight_case_id, "oversight receipt binds the canonical force-linked inquiry")
	_check(str(main.vertical_slice.governance.oversight_cases.get(oversight_case_id, {}).get("defense_template_id", "")) == "full_disclosure", "oversight authority stores the submitted defense")
	_check(int(main.get("_autosave_count")) == oversight_autosaves + 1, "oversight defense, final receipt, and completion share one autosave")
	_check(main.tutorial_completed, "ninth step sets the legacy tutorial-completed compatibility flag")
	main.call("_refresh_onboarding_guide")
	await _settle(2)
	_check(not main.onboarding_guide.is_open() and not main.onboarding_action_router.supports_current_target(), "completed guide releases its target and input masks")

	var saved_receipts: Array[Dictionary] = main.onboarding_progress.receipts()
	_check(saved_receipts.size() == 9, "completed guide persists exactly nine bounded receipts")
	for receipt in saved_receipts:
		_check(_has_exact_receipt_keys(receipt), "each committed receipt contains only the bounded four-key contract")
	var saved_treasury: int = main.vertical_slice.treasury_balance()
	var saved_job_ids: Array[String] = _sorted_keys(main.vertical_slice.session.state.construction_jobs)
	var saved_transport_ids: Dictionary = _transport_identity(main.vertical_slice.transport.to_dict())
	var saved_request_statuses: Dictionary = _request_statuses(main)
	var saved_governance: Dictionary = _governance_identity(main)
	var saved_force_fact_count := _force_fact_count(main.vertical_slice.session.state.event_book, judicial_case_id, oversight_case_id)
	await TestCleanup.release_fixtures(self, [main])
	var restored := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	restored.start_save_path = SAVE_PATH
	root.add_child(restored)
	await _settle(4)
	restored.start_screen.set_continue_available(true)
	restored.start_screen.animation_duration = 0.01
	restored.start_screen.continue_game_button.emit_signal("pressed")
	await _wait_for_loading(restored)
	_check(restored.get("_game_started"), "actual Continue reloads the completed onboarding save")
	restored.call("_refresh_onboarding_guide")
	await _settle(2)
	_check(restored.onboarding_progress.is_completed() and restored.onboarding_progress.receipts() == saved_receipts, "Continue restores exact completed guide and bounded receipts")
	_check(restored.tutorial_completed and not restored.onboarding_guide.is_open(), "Continue does not reopen or replay the completed guide")
	_check(restored.vertical_slice.treasury_balance() == saved_treasury, "reload does not replay any treasury cost")
	_check(_sorted_keys(restored.vertical_slice.session.state.construction_jobs) == saved_job_ids, "reload preserves construction IDs without replay")
	_check(_transport_identity(restored.vertical_slice.transport.to_dict()) == saved_transport_ids, "reload preserves transport IDs without replay")
	_check(_request_statuses(restored) == saved_request_statuses, "reload preserves request status without replaying accept")
	_check(_governance_identity(restored) == saved_governance, "Continue preserves bill, force, case, and defense authority IDs/counts without replay")
	_check(_force_fact_count(restored.vertical_slice.session.state.event_book, judicial_case_id, oversight_case_id) == saved_force_fact_count and saved_force_fact_count == 1, "Continue preserves exactly one reconstructible force event")
	_check(int(restored.get("_autosave_count")) == 0, "Continue itself does not create a replay autosave")

	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Onboarding feature flow test passed. Checks=%d" % _checks)
	_cleanup()
	await TestCleanup.finish(self, [restored], exit_code)


func _complete_governance_step(main) -> Dictionary:
	_open_hub(main)
	await _settle(2)
	main.call("_refresh_onboarding_guide")
	await _settle(2)
	_check(_target_name(main) == "GovernanceButton", "governance arrow points to the real municipal destination")
	_press_named(main, "GovernanceButton")
	await _settle(3)
	var plans: Array[Dictionary] = [
		{"bill_id": "environment_act", "button": "GovernanceBill_環境保護法案", "expected_status": ""},
		{"bill_id": "transit_act", "button": "GovernanceBill_交通建設法案", "expected_status": "enacted"},
		{"bill_id": "commerce_act", "button": "GovernanceBill_商業促進法案", "expected_status": "rejected"},
	]
	for plan: Dictionary in plans:
		var bill_id := str(plan["bill_id"])
		_check(_target_name(main) == str(plan["button"]), "%s arrow points to the real built-in bill button" % bill_id)
		_press_named(main, str(plan["button"]))
		await _settle(2)
		_check(str(main.vertical_slice.governance.pending_bill.get("bill_id", "")) == bill_id, "%s submission enters authority" % bill_id)
		var decision_day := int(main.vertical_slice.governance.pending_bill.get("decision_day", -1))
		var days_due: int = decision_day - main.vertical_slice.game_day()
		_check(days_due >= 0, "%s has a non-stale decision day" % bill_id)
		var events: Array[Dictionary] = main.vertical_slice.advance_days(days_due, main.call("_vertical_city_context"), false)
		main.call("_consume_vertical_events", events)
		main.call("_update_ui")
		await _settle(3)
		var pending: Dictionary = main.vertical_slice.governance.pending_bill
		var response_id := str(main.call("_onboarding_governance_response_id", pending))
		_check(not response_id.is_empty(), "%s resolves to a bounded real response" % bill_id)
		if bill_id in ["transit_act", "commerce_act"]:
			_check(response_id == "focus_primary", "%s uses the fixed focus_primary characterization" % bill_id)
		_check(_target_name(main) == "LowerCouncilResponse_%s" % response_id, "%s arrow points to the characterized response" % bill_id)
		_press_named(main, "LowerCouncilResponse_%s" % response_id)
		await _settle(2)
		_check(_target_name(main) == "LowerCouncilConfirmResponse", "%s requires the real confirmation button" % bill_id)
		_press_named(main, "LowerCouncilConfirmResponse")
		await _settle(4)
		var decision := _latest_decision(main, bill_id)
		var expected_status := str(plan["expected_status"])
		_check(not decision.is_empty() and (expected_status.is_empty() or str(decision.get("status", "")) == expected_status), "%s reaches its characterized terminal result" % bill_id)
		if bill_id == "commerce_act":
			var final_vote: Dictionary = decision.get("final_vote", {})
			_check(int(final_vote.get("votes_for", -1)) == 14 and int(final_vote.get("votes_against", -1)) == 7, "commerce focus_primary preserves the exact 14/7 tally")
			_check((final_vote.get("votes", []) as Array).size() == 30 and int(final_vote.get("majority_threshold", 0)) == 16, "commerce rejection preserves 30 seats and threshold 16")
		_check(_target_name(main) == "BackButton", "%s final stage guides back without faking another action" % bill_id)
		_press_named(main, "BackButton")
		await _settle(2)
		_check(_target_name(main) == "GovernanceButton", "%s completion returns to the municipal hub" % bill_id)
		_press_named(main, "GovernanceButton")
		await _settle(3)

	var judicial_before: Array = main.vertical_slice.governance.judiciary_cases.keys()
	var oversight_before: Array = main.vertical_slice.governance.oversight_cases.keys()
	var checks_before: int = main.vertical_slice.governance.checks_and_balances_history.size()
	var event_book_before: int = main.vertical_slice.session.state.event_book.size()
	var force_autosaves := int(main.get("_autosave_count"))
	_check(main.vertical_slice.latest_rejected_bill_id() == "commerce_act", "commerce is the genuine latest rejected bill")
	_check(_target_name(main) == "ForceRejectedBillButton", "governance completion arrow points to the real force-enact UI")
	_press_named(main, "ForceRejectedBillButton")
	await _settle(4)
	var judicial_case_id := _single_new_id(main.vertical_slice.governance.judiciary_cases, judicial_before)
	var oversight_case_id := _single_new_id(main.vertical_slice.governance.oversight_cases, oversight_before)
	var governance_receipt := _receipt_at(main, 6)
	_check(not judicial_case_id.is_empty() and not oversight_case_id.is_empty(), "force enact creates one linked judicial and one linked oversight case")
	_check(str(governance_receipt.get("authority_id", "")) == "bill_force_enactment" and str(governance_receipt.get("entity_id", "")) == judicial_case_id, "governance receipt binds the canonical judicial ID that reconstructs the force fact")
	_check(main.vertical_slice.governance.checks_and_balances_history.size() == checks_before + 1, "force enact adds one checks-and-balances record")
	_check(main.vertical_slice.session.state.event_book.size() == event_book_before + 1, "force enact adds one core authority fact")
	_check(_force_fact_count(main.vertical_slice.session.state.event_book, judicial_case_id, oversight_case_id) == 1, "four-field governance receipt reconstructs exactly one force event and oversight link")
	_check(int(main.get("_autosave_count")) == force_autosaves + 1, "force event, linked cases, and governance receipt share one autosave")
	return {"ok": not judicial_case_id.is_empty() and not oversight_case_id.is_empty(), "judicial_case_id": judicial_case_id, "oversight_case_id": oversight_case_id}


func _latest_decision(main, bill_id: String) -> Dictionary:
	for index in range(main.vertical_slice.governance.legislative_history.size() - 1, -1, -1):
		var decision: Dictionary = main.vertical_slice.governance.legislative_history[index]
		if str(decision.get("bill_id", "")) == bill_id:
			return decision.duplicate(true)
	return {}


func _single_new_id(cases: Dictionary, previous_ids: Array) -> String:
	var added: Array[String] = []
	for case_id_variant: Variant in cases.keys():
		if not previous_ids.has(case_id_variant):
			added.append(str(case_id_variant))
	return added[0] if added.size() == 1 else ""


func _force_fact_count(event_book: Array, judicial_case_id: String, oversight_case_id: String) -> int:
	var count := 0
	for record_variant: Variant in event_book:
		if not (record_variant is Dictionary):
			continue
		var record := record_variant as Dictionary
		if (
			str(record.get("fact_type", "")) == "bill_force_enacted"
			and str(record.get("case_id", "")) == judicial_case_id
			and str(record.get("oversight_case_id", "")) == oversight_case_id
		):
			count += 1
	return count


func _governance_identity(main) -> Dictionary:
	var governance = main.vertical_slice.governance
	var decision_signatures: Array[Dictionary] = []
	for decision_variant: Variant in governance.legislative_history:
		if not (decision_variant is Dictionary):
			continue
		var decision := decision_variant as Dictionary
		var final_vote: Dictionary = decision.get("final_vote", {})
		decision_signatures.append({
			"bill_id": str(decision.get("bill_id", "")),
			"status": str(decision.get("status", "")),
			"response_id": str(decision.get("mayor_response", {}).get("id", "")),
			"votes_for": int(final_vote.get("votes_for", -1)),
			"votes_against": int(final_vote.get("votes_against", -1)),
			"seat_count": (final_vote.get("votes", []) as Array).size(),
		})
	var judicial_defenses := {}
	for case_id_variant: Variant in governance.judiciary_cases.keys():
		var case_id := str(case_id_variant)
		judicial_defenses[case_id] = str(governance.judiciary_cases[case_id_variant].get("defense_template_id", ""))
	var oversight_defenses := {}
	for case_id_variant: Variant in governance.oversight_cases.keys():
		var case_id := str(case_id_variant)
		oversight_defenses[case_id] = str(governance.oversight_cases[case_id_variant].get("defense_template_id", ""))
	return {
		"decisions": decision_signatures,
		"active_law_ids": _sorted_keys(governance.active_laws),
		"rejected_bill_ids": _sorted_keys(governance.rejected_bills),
		"judicial_defenses": judicial_defenses,
		"oversight_defenses": oversight_defenses,
		"checks_count": governance.checks_and_balances_history.size(),
		"force_count": int(governance.force_enactment_count),
	}


func _target_name(main) -> String:
	var target := main.onboarding_guide.target_control() as Control
	return str(target.name) if target != null and is_instance_valid(target) else ""


func _wait_for_loading(main) -> void:
	for _frame in range(240):
		await process_frame
		if not main.start_screen.is_loading():
			return


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
