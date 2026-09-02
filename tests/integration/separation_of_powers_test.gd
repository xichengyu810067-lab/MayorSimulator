extends SceneTree

const GovernanceSystem = preload("res://scripts/systems/governance/governance_system.gd")

var _failed := false


func _initialize() -> void:
	var bill := {
		"id": "separation_test",
		"name": "三權制衡測試法案",
		"type": "industry",
		"review_days": 2,
		"upper_threshold": 90,
		"debate_strength": 0,
		"force_trust_penalty": 10,
		"judicial_severity": 75,
		"risk_level": 100,
		"concern_impacts": {
			"public_opinion": -100, "budget": -100, "social_welfare": -100,
			"environment": -100, "execution_feasibility": -100, "roi": -100,
			"regional_balance": -100, "healthcare": -100, "public_safety": -100,
			"housing": -100, "transport": -100, "economic_growth": -100,
			"employment": -100, "administrative_efficiency": -100, "education": -100,
			"utility_affordability": -100, "procedural_justice": -100,
			"public_interest": -100, "innovation": -100, "accountability": -100,
		},
		"effects": {"industrial_bonus": 0.1},
	}
	var governance = GovernanceSystem.new(20_260_731, {"separation_test": bill})
	_check(governance.lower_council_database != null, "30-member lower-council database loads into the authoritative governance system")
	_check(governance.lower_council_database.members.size() == 30, "authoritative lower chamber contains 30 individual members")
	_check(bool(governance.lower_council_contract_status().get("ok", false)), "authoritative lower-chamber data contract is observable and healthy")

	var submitted: Dictionary = governance.submit_bill("separation_test", 0)
	_check(bool(submitted.get("ok", false)), "executive can submit a proposal to the legislature")
	_check(str(governance.checks_and_balances_history.back().get("action", "")) == "executive_proposal", "proposal creates an executive-to-legislative check record")
	var events: Array[Dictionary] = governance.advance_day(2, {
		"game_day": 2,
		"economic_health": 0,
		"budget_health": 0,
		"public_support": 0,
		"regional_support": {"north": 0, "east": 0, "south": 0, "west": 0},
	})
	_check(events.size() == 1 and str(events[0].get("type", "")) == "lower_house_hearing_ready", "due proposal opens the lower-house hearing")
	_check(governance.legislative_history.is_empty(), "hearing does not enter permanent history before the mayor answers")
	var hearing: Dictionary = governance.pending_bill.get("lower_house_hearing", {})
	var initial_vote: Dictionary = hearing.get("initial_vote", {})
	var responses: Array = hearing.get("response_options", [])
	_check(responses.size() == 3, "lower-house hearing offers three evidence responses")
	var vote_history_before: int = governance.lower_council_database.vote_history.size()
	var preview: Dictionary = governance.preview_lower_house_response(str((responses[0] as Dictionary).get("id", "")))
	_check(bool(preview.get("ok", false)) and governance.lower_council_database.vote_history.size() == vote_history_before, "final-vote preview is read-only")
	var answered: Dictionary = governance.answer_lower_house_hearing(str((responses[0] as Dictionary).get("id", "")), 2)
	_check(bool(answered.get("ok", false)), "mayor response conducts the legislature's formal vote")
	_check(governance.legislative_history.size() == 1, "formal legislative decision enters permanent history")
	var decision: Dictionary = governance.legislative_history[0]
	var final_vote: Dictionary = decision.get("final_vote", {})
	_check(str(initial_vote.get("model", "")) == "lower_council_30_member", "initial vote uses the 30-person model")
	_check((initial_vote.get("votes", []) as Array).size() == 30, "initial stage records 30 individual choices")
	_check((final_vote.get("votes", []) as Array).size() == 30, "final stage records 30 individual choices")
	_check(governance.lower_council_database.vote_history.size() == vote_history_before + 30, "only the formal vote appends 30 vote-history records")
	_check(int(final_vote.get("votes_for", 0)) + int(final_vote.get("votes_against", 0)) + int(final_vote.get("abstentions", 0)) + int(final_vote.get("absences", 0)) == 30, "all lower-chamber outcomes reconcile to 30 seats")
	_check(not bool(decision.get("passed", true)), "legislature can reject the executive proposal")

	var forced: Dictionary = governance.force_enact("separation_test", 3)
	_check(bool(forced.get("ok", false)), "executive override remains possible as a risky exceptional power")
	_check(not governance.judiciary_cases.is_empty(), "override automatically opens an independent judicial case")
	_check(not governance.oversight_cases.is_empty(), "override automatically opens an independent oversight case")
	_check(str(governance.checks_and_balances_history.back().get("action", "")) == "executive_override_checked", "override creates a judiciary check record")
	var snapshot: Dictionary = governance.separation_of_powers_snapshot()
	_check(int(snapshot.get("legislature", {}).get("seat_count", 0)) == 30, "branch snapshot exposes the authoritative lower-chamber seat count")
	_check(str(snapshot.get("executive", {}).get("role", "")).contains("執行法律"), "branch snapshot states executive responsibility")
	_check(str(snapshot.get("judiciary", {}).get("role", "")).contains("審查違法行政"), "branch snapshot states independent judicial responsibility")

	var restored = GovernanceSystem.create_from_dict(governance.to_dict())
	_check(restored.lower_council_database.vote_history.size() == governance.lower_council_database.vote_history.size(), "individual legislative vote history survives serialization")
	_check(restored.checks_and_balances_history == governance.checks_and_balances_history, "checks-and-balances trail survives serialization")

	var unavailable = GovernanceSystem.new(20_260_732, {"separation_test": bill})
	unavailable.lower_council_database = null
	unavailable.lower_council_vote_model = null
	var unavailable_vote: Dictionary = unavailable._lower_house_vote(bill, {"game_day": 2}, false, {})
	_check(not bool(unavailable_vote.get("ok", true)), "missing authoritative lower-chamber data fails closed")
	_check(str(unavailable_vote.get("model", "")) == "lower_council_unavailable", "contract failure is explicit instead of using the legacy seven-profile model")
	_check((unavailable_vote.get("votes", []) as Array).is_empty(), "contract failure never fabricates substitute member votes")
	var unavailable_status: Dictionary = unavailable.lower_council_contract_status()
	_check(not bool(unavailable_status.get("ok", true)), "lower-chamber contract failure remains observable after detection")
	_check(str(unavailable_status.get("error_code", "")) == "lower_council_runtime_unavailable", "contract failure exposes a stable error code")
	var blocked_submission: Dictionary = unavailable.submit_bill("separation_test", 0)
	_check(not bool(blocked_submission.get("ok", true)), "executive proposal is blocked when the authoritative legislature is unavailable")
	_check(str(blocked_submission.get("error", "")) == "lower_council_runtime_unavailable", "blocked proposal returns the data-contract error")
	_check(unavailable.pending_bill.is_empty(), "fail-closed proposal does not enter a fake review flow")

	if _failed:
		quit(1)
	else:
		print("Separation of powers test passed. Seats=30 Checks=%d Judicial=%d Oversight=%d" % [
			governance.checks_and_balances_history.size(),
			governance.judiciary_cases.size(),
			governance.oversight_cases.size(),
		])
		quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Separation of powers test failed: %s" % message)
