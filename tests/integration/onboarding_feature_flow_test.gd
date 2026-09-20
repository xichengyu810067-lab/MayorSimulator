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
	_phase(main, "build")

	_check(main.onboarding_progress.current_target() == "build", "fresh guide starts at build")
	_check(main.onboarding_guide.is_product_mode(), "product guide observes input without synthetic advancement")
	_check(not main.onboarding_action_router.record_build_success("住宅", false, {"ok": false}, 0), "failed current-domain result cannot advance")
	_check(not main.onboarding_action_router.record_route_package_success({"ok": true, "session": {"workflow": "route_package_v1", "id": "session_wrong_order"}}, 0), "out-of-order success-shaped result cannot advance")
	_check(main.onboarding_progress.receipts().is_empty(), "rejected results leave onboarding receipts unchanged")
	var municipal := main.get_node_or_null("ActionDock/ActionButtonRow/MunicipalButton") as Button
	_check(municipal != null and main.onboarding_guide.target_control() == municipal, "build arrow initially points to the real municipal button")
	var defer_button := main.onboarding_guide.get_node("OnboardingDeferButton") as Button
	var defer_autosaves := int(main.get("_autosave_count"))
	if defer_button != null:
		defer_button.pressed.emit()
	await _settle(2)
	_check(defer_button != null and main.onboarding_progress.due_game_day() == 3, "the visible defer action schedules the unfinished build segment from 1/1 to 1/4")
	_check(main.onboarding_progress.receipts().is_empty() and main.onboarding_guide.is_waiting_mode() and not defer_button.visible, "deferring an unfinished segment preserves receipts and shows only passive waiting")
	_check(not main.vertical_slice.is_time_paused() and int(main.get("_autosave_count")) == defer_autosaves + 1, "defer keeps city time running and saves the schedule once")
	var scheduled_due: int = main.onboarding_progress.due_game_day()
	defer_button.pressed.emit()
	await _settle(2)
	_check(main.onboarding_progress.due_game_day() == scheduled_due and int(main.get("_autosave_count")) == defer_autosaves + 1, "hidden pre-due defer signal cannot reschedule or save")
	if municipal != null:
		await _click_at(municipal.get_global_rect().get_center())
		await _settle(2)
		_check(main.municipal_overlay != null and main.municipal_overlay.is_open(), "scheduled waiting card does not intercept the real municipal HUD button")
		main.municipal_overlay.close_overlay()
		await _settle(2)
	await _advance_to_onboarding_due(main, "build")
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
		var build_quote: Dictionary = main.vertical_slice.placement_footprint_quote(
			"住宅",
			build_tile,
			int(main.vertical_slice_panel.selected_worker_count()),
			int(main.placement_rotation_quarter_turns_ccw)
		)
		var build_message := _guide_message(main)
		_check(
			bool(build_quote.get("ok", false))
			and build_message.contains("$%d" % int(build_quote.get("total_cost", -1)))
			and build_message.contains("%d 個遊戲日" % int(build_quote.get("duration_days", -1)))
			and build_message.contains("%d 名工人" % int(build_quote.get("worker_count", -1))),
			"build guide renders cost, duration, and workers from the authoritative placement quote"
		)
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
	await _advance_to_onboarding_due(main, "blueprint")
	_phase(main, "blueprint")

	_open_hub(main)
	_press_named(main, "BuildingsButton")
	await _settle(2)
	main.building_family_tabs.current_tab = 1
	await _settle(2)
	_press_named(main, "BuildingGroup_community")
	_press_named(main, "BuildingCard_公園")
	await _settle(3)
	var park_entry_message := _guide_message(main)
	_check(park_entry_message.contains("公園") and park_entry_message.contains("待審") and park_entry_message.contains("不是立即核准"), "Park guide identifies the required design and distinguishes review submission from approval")
	var material = main.find_child("BlueprintMaterial", true, false)
	var material_before := str(material.call("selected_choice_id")) if material != null else ""
	var material_after := "brick" if material_before != "brick" else "steel"
	_check(_select_progressive_choice(material, material_after), "real blueprint picker signal changes one Park design field")
	await _settle(3)
	_check(main.onboarding_action_router.blueprint_design_changed(), "router observes a real changed design field")
	var residence_payload: Dictionary = main.vertical_slice_panel.current_design_payload().duplicate(true)
	residence_payload["building_name"] = "住宅"
	_check(not main.onboarding_action_router.record_blueprint_success(residence_payload, {"ok": true, "review": {"id": "review_other_building"}}, main.vertical_slice.game_day()) and main.onboarding_progress.receipts().size() == 1, "a normal Residence submission cannot impersonate the changed Park guide target")
	var park_quote: Dictionary = main.vertical_slice.draft_placement_quote("公園", main.vertical_slice_panel.current_design_payload())
	var park_message := _guide_message(main)
	_check(bool(park_quote.get("ok", false)) and park_message.contains("$%d" % int(park_quote.get("total_cost", -1))) and park_message.contains("%d 個遊戲日" % int(park_quote.get("duration_days", -1))) and park_message.contains("%d 名工人" % int(park_quote.get("worker_count", -1))), "Park guide uses the current authoritative construction quote without charging on submission")
	var blueprint_autosaves := int(main.get("_autosave_count"))
	var treasury_before_blueprint: int = main.vertical_slice.treasury_balance()
	_press_named(main, "SubmitCustomBlueprintButton")
	await _settle(3)
	var blueprint_receipt := _receipt_at(main, 1)
	_check(main.onboarding_progress.current_target() == "route", "successful changed Park blueprint advances once")
	_check(str(blueprint_receipt.get("authority_id", "")) == "blueprint_review" and not str(blueprint_receipt.get("entity_id", "")).is_empty(), "blueprint receipt uses canonical review id")
	var submitted_review: Dictionary = main.vertical_slice.construction.reviews.get(str(blueprint_receipt.get("entity_id", "")), {})
	_check(str(submitted_review.get("status", "")) == "under_review" and main.vertical_slice.treasury_balance() == treasury_before_blueprint, "submitted Park review is pending and does not charge the treasury")
	_check(int(main.get("_autosave_count")) == blueprint_autosaves + 1, "blueprint success and receipt share existing autosave")
	var blueprint_autosaves_after := int(main.get("_autosave_count"))
	_press_named(main, "SubmitCustomBlueprintButton")
	await _settle(2)
	_check(int(main.get("_autosave_count")) == blueprint_autosaves_after and main.onboarding_progress.receipts().size() == 2, "duplicate blueprint signal fails closed")
	await _advance_to_onboarding_due(main, "route")
	_phase(main, "route")

	var transport_setup := _prepare_route_package(main)
	_check(bool(transport_setup.get("ok", false)), "route package reaches the authoritative ready-to-confirm state: %s" % [transport_setup])
	main.call("_open_transport_planning")
	await _settle(3)
	var route_quote: Dictionary = main.vertical_slice.call("transport_session_package_quote", main.city_grid)
	var route_message := _guide_message(main)
	_check(
		bool(route_quote.get("ok", false))
		and route_message.contains("$%d" % int(route_quote.get("total_cost", -1)))
		and route_message.contains("每月維護 $%d" % int(route_quote.get("total_monthly_maintenance", -1)))
		and route_message.contains("%d 名工人" % int(route_quote.get("requested_workers", -1))),
		"route guide renders total cost, maintenance, and workers from the authoritative package quote"
	)
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
	await _advance_to_onboarding_due(main, "fiscal")
	_phase(main, "fiscal")

	_open_hub(main)
	await _settle(2)
	_press_named(main, "FinanceButton")
	await _settle(3)
	_check(_target_name(main) == "FiscalCategoryCard_resident_tax", "fiscal guide starts on the visible Resident Tax category instead of a hidden slider")
	var resident_tax_card := main.find_child("FiscalCategoryCard_resident_tax", true, false) as BaseButton
	if resident_tax_card != null:
		resident_tax_card.grab_focus()
	await _press_key(KEY_ENTER)
	_check(str(main.get("_selected_fiscal_category")).is_empty() and _target_name(main) == "FiscalCategoryCard_resident_tax", "non-Range guide target keeps unrelated keyboard activation gated")
	_press_named(main, "FiscalCategoryCard_resident_tax")
	await _settle(2)
	_check(_target_name(main) == "FiscalPlanCard_custom", "resident-tax category guides to the visible Custom plan")
	_press_named(main, "FiscalPlanCard_custom")
	await _settle(2)
	var income_slider := main.find_child("FiscalSlider_tax_income", true, false) as HSlider
	_check(income_slider != null and income_slider.is_visible_in_tree() and _target_name(main) == "FiscalSlider_tax_income", "fiscal income slider is visible and is the current actionable target")
	var authoritative_income_rate := int(main.tax_rates["income"])
	var fiscal_message_before := _guide_message(main)
	if income_slider != null:
		var custom_plan := main.find_child("FiscalPlanCard_custom", true, false) as BaseButton
		if custom_plan != null:
			custom_plan.grab_focus()
		await _press_key(KEY_RIGHT)
		_check(int(income_slider.value) == authoritative_income_rate, "an unfocused guided Range does not leak arrow input")
		income_slider.grab_focus()
		var draft_before_tab: Dictionary = main.call("debug_fiscal_draft_state")
		var target_before_tab := _target_name(main)
		await _press_key(KEY_TAB)
		_check(
			main.get_viewport().gui_get_focus_owner() == income_slider
			and main.call("debug_fiscal_draft_state") == draft_before_tab
			and _target_name(main) == target_before_tab,
			"a focused guided Range keeps non-arrow Tab input gated without changing draft or guide state"
		)
		await _press_key(KEY_RIGHT)
	await _settle(2)
	var fiscal_draft_state: Dictionary = main.call("debug_fiscal_draft_state")
	var fiscal_projection: Dictionary = main.call("_fiscal_projection_snapshot", true)
	var fiscal_message := _guide_message(main)
	_check(int(main.tax_rates["income"]) == authoritative_income_rate and int(fiscal_draft_state.get("dirty_count", 0)) == 1, "keyboard changes only the real fiscal draft before preview/apply")
	_check(
		fiscal_message != fiscal_message_before
		and fiscal_message.contains("草稿目前為 %d%%" % int(fiscal_draft_state.get("tax", {}).get("income", -1)))
		and fiscal_message.contains("正式值仍是 %d%%" % authoritative_income_rate)
		and fiscal_message.contains("月淨額 $%d" % int(fiscal_projection.get("net", 0)))
		and fiscal_message.contains("安全緩衝 $%d" % int(fiscal_projection.get("safety_buffer", 0)))
		and fiscal_message.contains("原因：")
		and fiscal_message.contains("代價／風險："),
		"slider adjustment refreshes meaningful draft, authority, projection, and cost/risk guidance"
	)
	_check(_target_name(main) == "FiscalBackToCategories", "a genuine slider change guides back to the visible summary surface")
	_press_named(main, "FiscalBackToCategories")
	await _settle(2)
	_check(_target_name(main) == "FiscalPreviewButton", "the restored summary surface guides to Preview")
	_press_named(main, "FiscalPreviewButton")
	await _settle(2)
	_check(_target_name(main) == "FiscalApplyAllButton", "matching preview guides to the real Apply action")
	var preview_state_before_close: Dictionary = main.call("debug_fiscal_draft_state")
	main.municipal_overlay.close_overlay()
	await _settle(2)
	_check(main.call("debug_fiscal_draft_state") == preview_state_before_close, "closing Finance preserves the pending preview without applying or discarding it")
	main.municipal_button.pressed.emit()
	await _settle(2)
	_press_named(main, "FinanceButton")
	await _settle(3)
	var reopened_preview_state: Dictionary = main.call("debug_fiscal_draft_state")
	_check(str(reopened_preview_state.get("flow_step", "")) == "preview" and int(reopened_preview_state.get("dirty_count", 0)) == 1, "reopening Finance restores the same preview and draft")
	_check(_target_name(main) == "FiscalApplyAllButton", "reopened preview keeps an actionable Apply guide target")
	var fiscal_autosaves := int(main.get("_autosave_count"))
	var fiscal_generation := int(main.get("_fiscal_apply_generation"))
	_press_named(main, "FiscalApplyAllButton")
	await _settle(3)
	var fiscal_receipt := _receipt_at(main, 3)
	_check(main.onboarding_progress.current_target() == "city_data", "matching preview revision and changed draft advance fiscal")
	_check(int(main.tax_rates["income"]) == authoritative_income_rate + 1, "Apply writes the exact one-point slider adjustment to fiscal authority")
	_check(str(fiscal_receipt.get("entity_id", "")) == "fiscal_apply_%06d" % (fiscal_generation + 1), "fiscal receipt binds the actual apply generation")
	_check(int(main.get("_autosave_count")) == fiscal_autosaves + 1, "fiscal apply and receipt share one autosave")
	var fiscal_autosaves_after := int(main.get("_autosave_count"))
	var duplicate_fiscal := main.find_child("FiscalApplyAllButton", true, false) as Button
	_check(duplicate_fiscal != null and duplicate_fiscal.disabled, "applied fiscal preview disables replay")
	if duplicate_fiscal != null:
		duplicate_fiscal.pressed.emit()
	_check(int(main.get("_autosave_count")) == fiscal_autosaves_after and main.onboarding_progress.receipts().size() == 4, "stale fiscal apply is zero-write")
	await _advance_to_onboarding_due(main, "city_data")
	_phase(main, "city_data")

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
	await _advance_to_onboarding_due(main, "public_affairs")
	_phase(main, "public_affairs")

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
	await _advance_to_onboarding_due(main, "governance")
	_phase(main, "governance")
	main.call("_refresh_onboarding_guide")
	await _settle(2)
	_check(main.onboarding_progress.current_target() == "governance" and main.onboarding_action_router.supports_current_target(), "governance adapter activates only after the first six authoritative receipts")
	_check(main.onboarding_guide.is_product_mode(), "governance guide points at real UI without synthetic advancement")
	_check(not main.onboarding_action_router.record_governance_force_success({"ok": false}, main.vertical_slice.governance, main.vertical_slice.session.state.event_book, main.vertical_slice.governance.checks_and_balances_history, main.vertical_slice.game_day()), "failed governance result cannot create a receipt")
	_check(not main.onboarding_action_router.record_judicial_defense_success("judicial_wrong_order", "public_interest", {"ok": true}, main.vertical_slice.governance, main.vertical_slice.session.state.event_book, main.vertical_slice.game_day()), "out-of-order judicial-shaped success cannot skip governance")

	var governance_step: Dictionary = await _complete_governance_step(main)
	var judicial_case_id := str(governance_step.get("judicial_case_id", ""))
	var oversight_case_id := str(governance_step.get("oversight_case_id", ""))
	var old_judicial_case_id := str(governance_step.get("old_judicial_case_id", ""))
	var old_oversight_case_id := str(governance_step.get("old_oversight_case_id", ""))
	_check(bool(governance_step.get("ok", false)), "real bill, hearing, rejection, and force-enact UI completes governance: %s" % governance_step)
	_check(main.onboarding_progress.current_target() == "judicial", "unique force-enact authority advances to judicial defense")
	var governance_receipt := _receipt_at(main, 6)
	var linked_oversight: Dictionary = main.vertical_slice.governance.oversight_cases.get(oversight_case_id, {})
	print("Onboarding linked fixture force_day=%d judicial_id=%s oversight_id=%s oversight_decision_day=%d evidence=%d trust_after_force=%d" % [int(governance_receipt.get("game_day", -1)), judicial_case_id, oversight_case_id, int(linked_oversight.get("decision_day", -1)), int(linked_oversight.get("evidence_strength", -1)), main.vertical_slice.governance.municipal_trust])
	_check(main.onboarding_progress.due_game_day() == int(governance_receipt.get("game_day", -1)) + 1, "force enact schedules judicial guidance for the next game day")
	_check(int(linked_oversight.get("decision_day", -1)) >= int(linked_oversight.get("opened_day", -1)) + 3, "linked oversight authority retains its minimum three-day review")
	await _advance_to_onboarding_due(main, "judicial")
	_phase(main, "judicial")
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
	_check(main.onboarding_progress.due_game_day() == int(judicial_receipt.get("game_day", -1)) + 1, "judicial defense schedules oversight guidance for the next game day")
	_check(main.onboarding_progress.due_game_day() < int(linked_oversight.get("decision_day", -1)), "promptly followed oversight guidance is due before the linked authority review ends")
	_check(str(judicial_receipt.get("authority_id", "")) == "judicial_case" and str(judicial_receipt.get("entity_id", "")) == judicial_case_id, "judicial receipt binds the canonical force-linked case")
	_check(str(main.vertical_slice.governance.judiciary_cases.get(judicial_case_id, {}).get("defense_template_id", "")) == "public_interest", "judicial authority stores the submitted defense")
	_check(str(main.vertical_slice.governance.judiciary_cases.get(old_judicial_case_id, {}).get("defense_template_id", "")).is_empty(), "judicial onboarding defense does not mutate the pre-existing case")
	_check(int(main.get("_autosave_count")) == judicial_autosaves + 1, "judicial defense and receipt share one autosave")
	_check(not main.onboarding_action_router.record_oversight_defense_success(oversight_case_id, "full_disclosure", {"ok": false}, main.vertical_slice.governance, main.vertical_slice.session.state.event_book, main.vertical_slice.game_day()), "failed oversight result cannot advance the linked inquiry")
	await _advance_to_onboarding_due(main, "oversight")
	_phase(main, "oversight")
	var oversight_autosaves := int(main.get("_autosave_count"))
	var oversight_authority_before: Dictionary = Dictionary(main.vertical_slice.governance.oversight_cases.get(oversight_case_id, {})).duplicate(true)
	_check(main.vertical_slice.governance.justice_system.terminal_failure_reason().is_empty(), "nine-stage fixture remains outside the separate terminal game-over path")
	_check(str(oversight_authority_before.get("status", "")) == "investigating" and main.vertical_slice.game_day() < int(oversight_authority_before.get("decision_day", -1)), "new oversight guidance reaches the force-linked inquiry while it is still investigating before its real decision day")
	if str(oversight_authority_before.get("status", "")) == "resolved":
		var review_message := (main.onboarding_guide.get_node("OnboardingMessage") as Label).text
		var review_button := main.onboarding_guide.get_node("OnboardingResultReviewButton") as Button
		_check(main.onboarding_guide.is_result_review_mode() and review_button != null and review_button.visible, "resolved oversight inquiry uses an explicit non-modal result review")
		_check(oversight_case_id in review_message and "結果：" in review_message and "結案日期：" in review_message and not "impeached" in review_message, "result review shows the linked authority id, localized outcome, and date")
		if review_button != null:
			review_button.pressed.emit()
		await _settle(3)
		_check(Dictionary(main.vertical_slice.governance.oversight_cases.get(oversight_case_id, {})) == oversight_authority_before, "reading a resolved result does not mutate governance authority")
	else:
		_open_hub(main)
		await _settle(2)
		main.call("_refresh_onboarding_guide")
		await _settle(2)
		_check(_target_name(main) == "OversightButton", "active oversight arrow points to the real municipal destination")
		_press_named(main, "OversightButton")
		await _settle(3)
		_check(str(main.oversight_panel.selected_case_id()) == oversight_case_id, "oversight page selects the exact force-linked inquiry")
		_check(_target_name(main) == "FullDisclosureDefenseButton", "oversight arrow points to a real enabled defense")
		_press_named(main, "FullDisclosureDefenseButton")
		await _settle(3)
	var oversight_receipt := _receipt_at(main, 8)
	_check(main.onboarding_progress.is_completed() and main.onboarding_progress.current_target().is_empty(), "ninth authoritative action completes onboarding")
	_check(str(oversight_receipt.get("authority_id", "")) == "oversight_case" and int(oversight_receipt.get("game_day", -1)) < int(oversight_authority_before.get("decision_day", -1)), "timely full-disclosure defense records an oversight-case receipt before adjudication, not a result-review receipt")
	_check(str(oversight_receipt.get("authority_id", "")) in ["oversight_case", "oversight_result_review"] and str(oversight_receipt.get("entity_id", "")) == oversight_case_id, "oversight receipt distinguishes a real defense from an explicit resolved-result review and binds the linked inquiry")
	if str(oversight_authority_before.get("status", "")) == "investigating":
		_check(str(main.vertical_slice.governance.oversight_cases.get(oversight_case_id, {}).get("defense_template_id", "")) == "full_disclosure", "oversight authority stores the submitted defense")
	_check(str(main.vertical_slice.governance.oversight_cases.get(old_oversight_case_id, {}).get("defense_template_id", "")).is_empty(), "oversight onboarding defense does not mutate the pre-existing case")
	_check(int(main.get("_autosave_count")) == oversight_autosaves + 1, "oversight authority action or explicit result review, final receipt, and completion share one autosave")
	_check(main.tutorial_completed, "ninth step sets the legacy tutorial-completed compatibility flag")
	main.call("_refresh_onboarding_guide")
	await _settle(2)
	_check(not main.onboarding_guide.is_open() and not main.onboarding_action_router.supports_current_target(), "completed guide releases its target and input masks")
	if main.municipal_overlay != null and main.municipal_overlay.is_open():
		main.municipal_overlay.close_overlay()
	main.call("_sync_time_pause_for_ui")
	_assert_healthy_authorities(main, "after the ninth real receipt")
	var judicial_decision_day := int(main.vertical_slice.governance.judiciary_cases.get(judicial_case_id, {}).get("decision_day", -1))
	var oversight_decision_day := int(main.vertical_slice.governance.oversight_cases.get(oversight_case_id, {}).get("decision_day", -1))
	var final_decision_day := maxi(judicial_decision_day, oversight_decision_day)
	_check(judicial_decision_day > main.vertical_slice.game_day() and oversight_decision_day > main.vertical_slice.game_day(), "both linked authorities still have real future decisions after timely onboarding completion")
	for _day in range(maxi(0, final_decision_day - main.vertical_slice.game_day())):
		var previous_day: int = main.vertical_slice.game_day()
		var decision_events: Array[Dictionary] = main.vertical_slice.advance_days(1, main.call("_vertical_city_context"), false)
		main.call("_consume_vertical_events", decision_events)
		main.call("_sync_vertical_state")
		main.call("_update_ui")
		if main.vertical_slice.game_day() != previous_day + 1:
			_check(false, "normal authority advancement stops before the linked decision day")
			break
		_assert_healthy_authorities(main, "after authority day %d" % main.vertical_slice.game_day())
		if main.vertical_slice.governance.has_failed():
			break
	var final_judicial: Dictionary = main.vertical_slice.governance.judiciary_cases.get(judicial_case_id, {})
	var final_oversight: Dictionary = main.vertical_slice.governance.oversight_cases.get(oversight_case_id, {})
	print("Onboarding linked fixture after decisions day=%d judicial=%s oversight=%s trust=%d reason=%s clock_paused=%s" % [main.vertical_slice.game_day(), str(final_judicial.get("outcome", "")), str(final_oversight.get("outcome", "")), main.vertical_slice.governance.municipal_trust, main.vertical_slice.governance.failure_reason(), str(main.vertical_slice.is_time_paused())])
	_check(main.vertical_slice.game_day() == final_decision_day, "normal city time reaches the actual last linked judicial and oversight decision day")
	_check(str(final_judicial.get("status", "")) == "resolved" and int(final_judicial.get("resolved_day", -1)) == judicial_decision_day, "force-linked judicial case is adjudicated on its actual scheduled day")
	_check(str(final_oversight.get("status", "")) == "resolved" and int(final_oversight.get("resolved_day", -1)) == oversight_decision_day and str(final_oversight.get("defense_template_id", "")) == "full_disclosure", "force-linked oversight case is adjudicated with the real submitted defense")
	_check(str(final_judicial.get("outcome", "")) == "fine", "force-linked judicial authority produces its expected real fine judgment")
	_check(str(final_oversight.get("outcome", "")) == "cleared" and int(final_oversight.get("votes_for_impeachment", -1)) == 0, "timely oversight defense produces its expected real cleared verdict with zero impeachment votes")
	_assert_healthy_authorities(main, "after both linked authority decisions")
	var saved_linked_authority := _linked_authority_snapshot(main, judicial_case_id, oversight_case_id)
	_check(saved_linked_authority["judicial"] == saved_linked_authority["core_judicial"] and saved_linked_authority["oversight"] == saved_linked_authority["core_oversight"], "Core mirrors both linked adjudicated cases before Continue")

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
	_check(_linked_authority_snapshot(restored, judicial_case_id, oversight_case_id) == saved_linked_authority, "headless Continue preserves both linked case verdicts, votes, dates, formal and Core trust, terminal state, and clock pause exactly")
	_assert_healthy_authorities(restored, "after headless Continue")
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
			_check(int(final_vote.get("votes_for", -1)) < int(final_vote.get("majority_threshold", 0)) and not bool(decision.get("lower_passed", true)), "commerce focus_primary remains an authoritative lower-house rejection after scheduled game days advance")
			_check((final_vote.get("votes", []) as Array).size() == 30 and int(final_vote.get("majority_threshold", 0)) == 16, "commerce rejection preserves 30 seats and threshold 16")
		_check(_target_name(main) == "BackButton", "%s final stage guides back without faking another action" % bill_id)
		_press_named(main, "BackButton")
		await _settle(2)
		_check(_target_name(main) == "GovernanceButton", "%s completion returns to the municipal hub" % bill_id)
		_press_named(main, "GovernanceButton")
		await _settle(3)

	var justice_system = main.vertical_slice.governance.justice_system
	var old_judicial: Dictionary = justice_system.open_judicial_case(
		"environment_act",
		main.vertical_slice.game_day(),
		45,
		"既有司法審查案件"
	)
	var old_oversight: Dictionary = justice_system.open_oversight_case(
		"official_mayor",
		["既有監察調查"],
		0,
		main.vertical_slice.game_day()
	)
	var old_judicial_case_id := str(old_judicial.get("case", {}).get("id", ""))
	var old_oversight_case_id := str(old_oversight.get("case", {}).get("id", ""))
	main.judicial_panel.refresh(justice_system)
	main.oversight_panel.refresh(justice_system)
	_check(not old_judicial_case_id.is_empty() and not old_oversight_case_id.is_empty(), "pre-existing investigating judicial and oversight fixtures open")
	_check(main.judicial_panel.select_case_by_id(old_judicial_case_id) and main.oversight_panel.select_case_by_id(old_oversight_case_id), "pre-existing cases are selected before force enact")
	_check(str(main.judicial_panel.selected_case_id()) == old_judicial_case_id and str(main.oversight_panel.selected_case_id()) == old_oversight_case_id, "force enact begins with old judicial and oversight selections")
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
	_check(main.vertical_slice.governance.judiciary_cases.size() == judicial_before.size() + 1 and main.vertical_slice.governance.oversight_cases.size() == oversight_before.size() + 1, "force enact creates no extra judicial or oversight cases")
	_check(str(governance_receipt.get("authority_id", "")) == "bill_force_enactment" and str(governance_receipt.get("entity_id", "")) == judicial_case_id, "governance receipt binds the canonical judicial ID that reconstructs the force fact")
	_check(main.vertical_slice.governance.checks_and_balances_history.size() == checks_before + 1, "force enact adds one checks-and-balances record")
	_check(main.vertical_slice.session.state.event_book.size() == event_book_before + 1, "force enact adds one core authority fact")
	_check(_force_fact_count(main.vertical_slice.session.state.event_book, judicial_case_id, oversight_case_id) == 1, "four-field governance receipt reconstructs exactly one force event and oversight link")
	_check(int(main.get("_autosave_count")) == force_autosaves + 1, "force event, linked cases, and governance receipt share one autosave")
	return {
		"ok": not judicial_case_id.is_empty() and not oversight_case_id.is_empty(),
		"judicial_case_id": judicial_case_id,
		"oversight_case_id": oversight_case_id,
		"old_judicial_case_id": old_judicial_case_id,
		"old_oversight_case_id": old_oversight_case_id,
	}


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


func _linked_authority_snapshot(main, judicial_case_id: String, oversight_case_id: String) -> Dictionary:
	var governance = main.vertical_slice.governance
	var core_governance: Dictionary = main.vertical_slice.session.state.governance
	return {
		"judicial": _case_result_identity(governance.judiciary_cases.get(judicial_case_id, {})),
		"oversight": _case_result_identity(governance.oversight_cases.get(oversight_case_id, {})),
		"core_judicial": _case_result_identity(_core_linked_case(core_governance.get("judicial_cases", []), judicial_case_id)),
		"core_oversight": _case_result_identity(_core_linked_case(core_governance.get("oversight_cases", []), oversight_case_id)),
		"formal_trust": governance.municipal_trust,
		"core_trust": int(main.vertical_slice.session.state.metrics.get("municipal_trust", -1)),
		"formal_failed": governance.has_failed(),
		"formal_reason": str(governance.failure_reason()),
		"core_failed": bool(core_governance.get("failed", true)),
		"core_reason": str(core_governance.get("failure_reason", "missing")),
		"justice_reason": governance.justice_system.terminal_failure_reason(),
		"clock_paused": bool(main.vertical_slice.session.clock.paused),
	}


func _core_linked_case(cases: Array, case_id: String) -> Dictionary:
	for case_variant: Variant in cases:
		if case_variant is Dictionary and str(Dictionary(case_variant).get("id", "")) == case_id:
			return Dictionary(case_variant)
	return {}


func _case_result_identity(case_payload: Dictionary) -> Dictionary:
	if case_payload.is_empty():
		return {}
	return {
		"id": str(case_payload.get("id", "")),
		"status": str(case_payload.get("status", "")),
		"outcome": str(case_payload.get("outcome", "")),
		"resolved_day": int(case_payload.get("resolved_day", -1)),
		"defense_template_id": str(case_payload.get("defense_template_id", "")),
		"votes_for_impeachment": int(case_payload.get("votes_for_impeachment", -1)),
		"votes_against_impeachment": int(case_payload.get("votes_against_impeachment", -1)),
		"member_vote_count": (case_payload.get("member_votes", []) as Array).size(),
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


func _advance_to_onboarding_due(main, expected_target: String) -> void:
	var current_day: int = main.vertical_slice.game_day()
	var due_day: int = main.onboarding_progress.due_game_day()
	main.call("_refresh_onboarding_guide")
	_check(main.onboarding_progress.current_target() == expected_target, "%s is the scheduled next segment" % expected_target)
	var expected_delay := 1 if expected_target in ["judicial", "oversight"] else 3
	_check(due_day == current_day + expected_delay and main.onboarding_progress.is_waiting(current_day), "%s waits its specified number of game days" % expected_target)
	var waiting_message := (main.onboarding_guide.get_node("OnboardingMessage") as Label).text
	_check(main.onboarding_guide.is_waiting_mode() and not main.onboarding_guide.is_open(), "%s waiting interval has a passive card, not a target input gate" % expected_target)
	_check(waiting_message.contains(main.call("_onboarding_date_label", due_day)) and waiting_message.contains("可正常遊玩"), "%s waiting card shows its due date and normal play" % expected_target)
	_check(not (main.onboarding_guide.get_node("OnboardingDeferButton") as Button).visible, "%s waiting card has no ineffective defer action" % expected_target)
	_check(not (main.onboarding_guide.get_node("OnboardingArrow") as Control).visible, "%s waiting card has no arrow" % expected_target)
	if main.municipal_overlay != null and main.municipal_overlay.is_open():
		main.municipal_overlay.close_overlay()
	await _settle(2)
	main.call("_sync_time_pause_for_ui")
	_check(not main.vertical_slice.is_time_paused(), "%s schedule permits normal time progression" % expected_target)
	var events: Array[Dictionary] = main.vertical_slice.advance_days(
		due_day - current_day,
		main.call("_vertical_city_context"),
		false
	)
	main.call("_consume_vertical_events", events)
	main.call("_sync_vertical_state")
	main.call("_update_ui")
	main.call("_refresh_onboarding_guide")
	await _settle(3)
	_check(main.vertical_slice.game_day() == due_day and main.onboarding_progress.is_current_target_available(due_day), "%s opens on its exact due day" % expected_target)
	_check(main.onboarding_guide.is_product_mode(), "%s due segment restores product guidance" % expected_target)


func _cleanup() -> void:
	for path in [SAVE_PATH, "%s.bak" % SAVE_PATH, "%s.tmp" % SAVE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame


func _phase(main, name: String) -> void:
	print("Onboarding feature flow phase=%s" % name)
	var message_label := main.onboarding_guide.get_node_or_null("OnboardingMessage") as Label
	var message := message_label.text if message_label != null else ""
	_check(main.onboarding_progress.current_target() == name, "%s phase matches the current authoritative onboarding target" % name)
	_check(
		message.contains("現在：")
		and message.contains("原因：")
		and message.contains("結果：")
		and message.contains("代價／風險："),
		"%s phase keeps a readable action, reason, result, and cost/risk explanation" % name
	)


func _guide_message(main) -> String:
	var message_label := main.onboarding_guide.get_node_or_null("OnboardingMessage") as Label
	return message_label.text if message_label != null else ""


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


func _assert_healthy_authorities(main, label: String) -> void:
	var governance = main.vertical_slice.governance
	var core_governance: Dictionary = main.vertical_slice.session.state.governance
	var core_trust := int(main.vertical_slice.session.state.metrics.get("municipal_trust", -1))
	var formal_reason := str(governance.failure_reason())
	_check(core_trust == governance.municipal_trust, "%s keeps Core and formal municipal trust equal" % label)
	_check(bool(core_governance.get("failed", true)) == governance.has_failed() and str(core_governance.get("failure_reason", "missing")) == formal_reason, "%s keeps Core and formal terminal state equal" % label)
	_check(governance.justice_system.terminal_failure_reason() == formal_reason, "%s keeps judicial terminal state equal to governance" % label)
	_check(main.vertical_slice.is_time_paused() == bool(main.vertical_slice.session.clock.paused), "%s keeps the clock pause view equal to the saved authority" % label)
	_check(governance.municipal_trust >= 40 and formal_reason.is_empty() and not main.vertical_slice.is_time_paused(), "%s remains a healthy city with an advancing clock" % label)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Onboarding feature flow check failed: %s" % message)
