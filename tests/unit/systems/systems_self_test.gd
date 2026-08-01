extends SceneTree

const Construction := preload("res://scripts/systems/city/construction_system.gd")
const Durability := preload("res://scripts/systems/city/durability_system.gd")
const Governance := preload("res://scripts/systems/governance/governance_system.gd")


func _initialize() -> void:
	_test_construction()
	_test_durability()
	_test_governance()
	print("Mayor Simulator systems self-test passed.")
	quit(0)


func _test_construction() -> void:
	var system = Construction.new(12345)
	var blueprint := {
		"id": "bp_hospital",
		"building_id": "hospital",
		"material_id": "eco_composite",
		"floors": 3,
		"size_tier": "large",
		"decoration_count": 2,
		"requested_workers": 5,
		"base_cost": 25_000
	}
	# Regression: normalized blueprints without an explicit workload must use rules,
	# not accidentally acquire a null workload that collapses to one point.
	var rule_workload: float = system.calculate_workload(blueprint, "build")
	assert(rule_workload > 20.0, "Rule-driven workload must survive normalization")
	var submission: Dictionary = system.submit_blueprint(blueprint, 10)
	assert(bool(submission.get("ok", false)))
	var normalized: Dictionary = submission["review"]["blueprint"]
	assert(not normalized.has("workload"), "Absent workload must remain absent")
	assert(system.calculate_workload(normalized, "build") == rule_workload)
	var review_days := int(submission["review"]["review_days"])
	assert(review_days >= 2 and review_days <= 7)
	var review_events: Array[Dictionary] = system.advance_reviews(
		10 + review_days,
		{"available_budget": 1_000_000, "citizen_support": 60}
	)
	assert(review_events.size() == 1)
	var started: Dictionary = system.start_approved_job(
		str(submission["review"]["id"]), 20, 10 + review_days, "cell_12"
	)
	assert(bool(started.get("ok", false)))
	assert(system.available_workers() == 0)
	assert(Construction.effective_workers(5) == 5.0)
	assert(Construction.effective_workers(6) == 6.0)
	assert(Construction.effective_workers(10) == 10.0)
	assert(is_equal_approx(Construction.effective_workers(11), 10.9))
	assert(Construction.effective_workers(20) == 19.0)
	assert(Construction.duration_days(100.0, 5) == 20)
	assert(Construction.duration_days(100.0, 6) == 17)
	assert(Construction.duration_days(100.0, 10) == 10)
	assert(Construction.duration_days(100.0, 11) == 10)
	assert(Construction.duration_days(100.0, 20) == 6)
	assert(Construction.daily_labor_cost(5) == 10_000)
	assert(Construction.daily_labor_cost(6) == 15_000)
	var json_state = JSON.parse_string(JSON.stringify(system.to_dict()))
	var restored = Construction.create_from_dict(json_state)
	assert(restored.available_workers() == 0)
	assert(restored.calculate_workload(normalized, "build") == rule_workload)


func _test_durability() -> void:
	assert(Durability.efficiency_for(40) == 0.4)
	assert(Durability.efficiency_for(39) == 0.0)
	var system = Durability.new()
	assert(bool(system.register_building("building_40", {
		"durability": 40, "material_value": 100_000, "engineering_fee": 2_000
	}).get("ok", false)))
	assert(bool(system.register_building("building_39", {"durability": 39}).get("ok", false)))
	assert(str(system.get_building("building_40")["status"]) == "active")
	assert(str(system.get_building("building_39")["status"]) == "scrapped")
	system.record_monthly_maintenance(false, 30)
	system.record_monthly_maintenance(false, 60)
	system.record_monthly_maintenance(false, 90)
	var weekly: Array[Dictionary] = system.advance_week(97)
	assert(weekly.size() == 1)
	assert(str(system.get_building("building_40")["status"]) == "scrapped")
	var repair_denied: Dictionary = system.repair("building_40", 98)
	assert(not bool(repair_denied.get("ok", false)))
	var restored = Durability.create_from_dict(JSON.parse_string(JSON.stringify(system.to_dict())))
	assert(restored.consecutive_unpaid_months == 3)
	assert(str(restored.get_building("building_40")["status"]) == "scrapped")


func _test_governance() -> void:
	var system = Governance.new(99)
	var committee_summary: Dictionary = system.committee_summary()
	assert(int(committee_summary.get("judicial_active", 0)) == 15)
	assert(int(committee_summary.get("oversight_active", 0)) == 10)
	assert(int(committee_summary.get("judicial_term_years", 0)) == 5)
	assert(int(committee_summary.get("oversight_term_years", 0)) == 3)
	var submitted: Dictionary = system.submit_bill("environment_act", 1)
	assert(bool(submitted.get("ok", false)))
	var decision_day := int(submitted["pending_bill"]["decision_day"])
	var events: Array[Dictionary] = system.advance_day(decision_day, {
		"public_support": 80,
		"economic_health": 70,
		"mayor_argument_bonus": 10,
		"regional_support": {"north": 70, "south": -1}
	})
	assert(events.size() == 1)
	assert(str(events[0]["type"]) == "bill_rejected")
	assert(system.rejected_bills.has("environment_act"))
	var forced: Dictionary = system.force_enact("environment_act", decision_day)
	assert(bool(forced.get("ok", false)))
	assert(not (forced.get("oversight_case", {}) as Dictionary).is_empty())
	assert(system.oversight_cases.size() == 1)
	var court_case: Dictionary = forced["case"]
	assert(int(court_case["investigation_days"]) >= 2)
	assert(int(court_case["investigation_days"]) <= 15)
	assert(bool(system.submit_defense(str(court_case["id"]), "public_interest").get("ok", false)))
	var restored = Governance.create_from_dict(JSON.parse_string(JSON.stringify(system.to_dict())))
	assert(restored.judiciary_cases.has(str(court_case["id"])))
	var court_events: Array[Dictionary] = restored.advance_day(int(court_case["decision_day"]), {})
	assert(court_events.size() >= 1)
	assert(str(court_events[0]["type"]) == "judiciary_fine")
	var boundary_system = Governance.new(100)
	boundary_system.set_civic_metrics(80, 40)
	assert(not boundary_system.has_failed(), "Failure bounds are strict at grievance 80 and trust 40")
	var grievance_failure = Governance.new(101)
	grievance_failure.set_civic_metrics(81, 40)
	assert(grievance_failure.failure_reason() == "grievance_above_80")
	grievance_failure.set_civic_metrics(0, 100)
	assert(grievance_failure.failure_reason() == "grievance_above_80", "Terminal failure cannot be reversed by later metric writes")
	var trust_failure = Governance.new(102)
	trust_failure.set_civic_metrics(80, 39)
	assert(trust_failure.failure_reason() == "municipal_trust_below_40")
	var stop_system = Governance.new(5)
	stop_system.rejected_bills["industry_act"] = {"status": "rejected"}
	var stopped_force: Dictionary = stop_system.force_enact("industry_act", 1)
	var stopped_case: Dictionary = stopped_force["case"]
	var stop_events: Array[Dictionary] = stop_system.advance_day(int(stopped_case["decision_day"]), {})
	assert(str(stop_events[0]["type"]) == "judiciary_stop_order")
	var prison_system = Governance.new(6)
	prison_system.force_enactment_count = 3
	prison_system.rejected_bills["industry_act"] = {"status": "rejected"}
	var prison_force: Dictionary = prison_system.force_enact("industry_act", 1)
	var prison_case: Dictionary = prison_force["case"]
	var prison_events: Array[Dictionary] = prison_system.advance_day(int(prison_case["decision_day"]), {})
	assert(str(prison_events[0]["type"]) == "judiciary_prison")
	assert(prison_system.failure_reason() == "imprisonment_judgment")
	var oversight_system = Governance.new(77)
	var opened_oversight: Dictionary = oversight_system.open_oversight_investigation(
		"official_mayor",
		["行政失職", "違法執行"],
		90,
		10
	)
	assert(bool(opened_oversight.get("ok", false)))
	var oversight_case: Dictionary = opened_oversight["case"]
	var oversight_events: Array[Dictionary] = oversight_system.advance_day(int(oversight_case["decision_day"]), {})
	assert(oversight_events.size() == 1)
	assert(str(oversight_events[0]["type"]) == "oversight_impeachment")
	assert((oversight_events[0]["payload"]["case"]["member_votes"] as Array).size() == 10)
	assert(oversight_system.failure_reason() == "municipal_trust_below_40", "Mayor impeachment enters the existing governance-authority terminal state")
	assert(oversight_system.justice_system.is_terminal_locked(), "Mayor impeachment locks later justice mutations")
	assert(not bool(oversight_system.submit_bill("transit_act", int(oversight_case["decision_day"])).get("ok", false)), "Governance commands are rejected after failure")
	assert(oversight_system.advance_day(int(oversight_case["decision_day"]) + 1, {}).is_empty(), "Governance no longer advances after failure")
	var oversight_restored = Governance.create_from_dict(JSON.parse_string(JSON.stringify(oversight_system.to_dict())))
	assert(oversight_restored.oversight_cases.size() == 1)
	assert(oversight_restored.failure_reason() == "municipal_trust_below_40", "Terminal failure survives JSON round-trip")
	var legacy_oversight_state: Dictionary = oversight_system.to_dict()
	legacy_oversight_state["schema_version"] = 2
	legacy_oversight_state.erase("terminal_failure_reason")
	legacy_oversight_state["municipal_trust"] = 70
	var legacy_oversight = Governance.create_from_dict(JSON.parse_string(JSON.stringify(legacy_oversight_state)))
	assert(legacy_oversight.failure_reason() == "municipal_trust_below_40", "Legacy impeached-mayor saves migrate into the existing terminal state")
