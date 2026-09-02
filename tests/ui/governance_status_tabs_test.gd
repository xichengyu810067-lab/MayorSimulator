extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1920, 1080)
	root.size = Vector2i(1920, 1080)
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await process_frame
	var l10n = root.get_node_or_null("L10n")

	var tabs := main.governance_status_tabs as TabContainer
	_check(tabs != null and tabs.get_tab_count() == 3, "governance exposes exactly three status tabs")
	_check(l10n != null and tabs.get_tab_title(0).begins_with(l10n.text("已實施")), "first tab is implemented")
	_check(l10n != null and tabs.get_tab_title(1).begins_with(l10n.text("審核中")), "second tab is under review")
	_check(l10n != null and tabs.get_tab_title(2).begins_with(l10n.text("未實施")), "third tab is unimplemented")
	_check(main.find_child("SeparationOfPowersDashboard", true, false) == null, "policy and bill page excludes the separation-of-powers dashboard")
	_check(main.find_child("GovernmentBranchGrid", true, false) == null, "policy and bill page excludes government branch cards")
	_check(main.governance_policy_cards.size() == 4, "all four policies have categorized cards")
	_check(main.governance_bill_cards.size() == 8, "all eight bills have categorized cards")
	_check(main.find_children("GovernanceKindTag_Policy_*", "Label", true, false).size() == 4, "every policy has a policy tag")
	_check(main.find_children("GovernanceKindTag_Bill_*", "Label", true, false).size() == 8, "every bill has a bill tag")
	_check(_parent_name(main.governance_policy_cards["環保政策"]) == "unimplemented_policy_Grid", "disabled policy begins in unimplemented")
	_check(_parent_name(main.governance_bill_cards["交通建設法案"]) == "unimplemented_bill_Grid", "new bill begins in unimplemented")

	main._toggle_policy(true, "環保政策")
	await process_frame
	_check(_parent_name(main.governance_policy_cards["環保政策"]) == "implemented_policy_Grid", "enabled policy moves to implemented")
	_check((main.policy_checks["環保政策"] as CheckBox).button_pressed, "implemented policy retains its enabled state")
	_check(tabs.current_tab == 0, "enabling a policy prioritizes the implemented tab")

	main._submit_bill("交通建設法案")
	await process_frame
	_check(_parent_name(main.governance_bill_cards["交通建設法案"]) == "review_bill_Grid", "submitted bill moves to review")
	_check(tabs.current_tab == 1, "successful submission opens the review tab")
	var decision_day := int(main.vertical_slice.governance.pending_bill.get("decision_day", -1))
	var hearing_events: Array[Dictionary] = main.vertical_slice.advance_days(
		decision_day - main.vertical_slice.game_day(),
		{"public_support": 70, "regional_support": {"north": 70, "east": 70, "south": 70, "west": 70}},
		false
	)
	main._consume_vertical_events(hearing_events)
	main._update_ui()
	await process_frame
	var hearing_signature: Dictionary = main.lower_council_stage.debug_signature()
	_check(bool(hearing_signature.get("visible", false)), "review bill opens the lower-council hearing stage on decision day")
	_check(int(hearing_signature.get("seat_count", 0)) == 30 and int(hearing_signature.get("majority_threshold", 0)) == 16, "hearing stage shows 30 seats and threshold 16")
	_check(int(hearing_signature.get("response_option_count", 0)) == 3, "hearing stage shows exactly three mayor response choices")

	main.vertical_slice.governance.pending_bill.clear()
	main.vertical_slice.governance.active_laws["transit_act"] = {
		"bill_id": "transit_act",
		"name": "交通建設法案",
		"status": "active",
		"effects": {},
	}
	main._update_ui()
	await process_frame
	_check(_parent_name(main.governance_bill_cards["交通建設法案"]) == "implemented_bill_Grid", "active bill moves to implemented")
	_check((main.bill_buttons["交通建設法案"] as Button).disabled, "implemented bill cannot be submitted again")
	main.municipal_overlay.open_page("governance")
	await process_frame
	_check(tabs.current_tab == 0, "reopening governance prioritizes implemented policies and bills")

	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Governance status tabs test passed. Policies=4 Bills=8 Tabs=3")
	await TestCleanup.finish(self, [main], exit_code)


func _parent_name(node_variant: Variant) -> String:
	var node := node_variant as Node
	return node.get_parent().name if node != null and node.get_parent() != null else ""


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Governance status tabs check failed: %s" % message)
