extends SceneTree

const OnboardingProgressScript := preload("res://scripts/app/onboarding_progress.gd")
const OnboardingActionRouterScript := preload("res://scripts/app/onboarding_action_router.gd")

var _failed := false


class GovernanceStub:
	extends RefCounted

	var judiciary_cases: Dictionary = {}
	var oversight_cases: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var governance := GovernanceStub.new()
	var judicial_case := _resolved_judicial_case()
	var oversight_case := _resolved_oversight_case()
	governance.judiciary_cases[judicial_case["id"]] = judicial_case.duplicate(true)
	governance.oversight_cases[oversight_case["id"]] = oversight_case.duplicate(true)
	var event_book := [_force_fact()]
	var progress = OnboardingProgressScript.new()
	_check(bool(progress.restore_from_shell_state(_active_shell(7, 21)).get("ok", false)), "judicial result review fixture restores")
	var router = OnboardingActionRouterScript.new(progress)

	var wrong_payload := judicial_case.duplicate(true)
	wrong_payload["outcome"] = "prison"
	_check(not router.record_case_result_review_success("judicial", wrong_payload, governance, event_book, 21), "result review rejects a payload that differs from authority")
	var duplicate_events: Array = event_book.duplicate(true)
	duplicate_events.append(_force_fact())
	_check(not router.record_case_result_review_success("judicial", judicial_case, governance, duplicate_events, 21), "result review rejects an ambiguous linked case")
	var investigating_case := judicial_case.duplicate(true)
	investigating_case["status"] = "investigating"
	investigating_case.erase("resolved_day")
	governance.judiciary_cases[judicial_case["id"]] = investigating_case.duplicate(true)
	_check(not router.record_case_result_review_success("judicial", investigating_case, governance, event_book, 21), "result review rejects an unresolved authority case")
	governance.judiciary_cases[judicial_case["id"]] = judicial_case.duplicate(true)
	_check(not router.record_case_result_review_success("judicial", judicial_case, governance, event_book, 20), "result review rejects a future resolved day and an unavailable segment")
	_check(router.record_case_result_review_success("judicial", judicial_case, governance, event_book, 21), "explicit judicial result review records the resolved linked authority case")
	var judicial_receipt: Dictionary = progress.receipts()[7]
	_check(str(judicial_receipt.get("authority_id", "")) == "judicial_result_review" and str(judicial_receipt.get("entity_id", "")) == "judicial_000001", "judicial review receipt uses its distinct authority and linked id")
	_check(progress.current_target() == "oversight" and progress.due_game_day() == 22, "judicial review schedules oversight the next game day")
	_check(progress.defer_current_target(21) and progress.due_game_day() == 25, "resolved-case review still defers the new due day by three days")
	var restored = OnboardingProgressScript.new()
	_check(bool(restored.restore_from_shell_state({"schema_version": 9, "tutorial_completed": false, "onboarding": progress.snapshot()}).get("ok", false)), "deferred result-review schedule survives save and load")
	var restored_router = OnboardingActionRouterScript.new(restored)
	_check(restored.current_target() == "oversight" and restored.due_game_day() == 25 and restored.receipts().size() == 8, "reload preserves the same unfinished oversight review and date")
	_check(not restored_router.record_case_result_review_success("oversight", oversight_case, governance, event_book, 24), "review confirmation before the deferred due day records no receipt")
	_check(restored_router.record_case_result_review_success("oversight", oversight_case, governance, event_book, 25), "explicit oversight result review completes the resolved linked authority case")
	var oversight_receipt: Dictionary = restored.receipts()[8]
	_check(str(oversight_receipt.get("authority_id", "")) == "oversight_result_review" and restored.is_completed(), "oversight review receipt has a distinct authority and completes exactly once")
	_check(not restored_router.record_case_result_review_success("oversight", oversight_case, governance, event_book, 25), "completed result review cannot replay")

	var defense_progress = OnboardingProgressScript.new()
	_check(bool(defense_progress.restore_from_shell_state(_active_shell(8, 24)).get("ok", false)), "oversight defense combination fixture restores")
	var defense_router = OnboardingActionRouterScript.new(defense_progress)
	var investigating_oversight := oversight_case.duplicate(true)
	investigating_oversight["status"] = "investigating"
	investigating_oversight["defense_template_id"] = "full_disclosure"
	investigating_oversight.erase("resolved_day")
	investigating_oversight.erase("votes_for_impeachment")
	investigating_oversight.erase("votes_against_impeachment")
	investigating_oversight["member_votes"] = []
	investigating_oversight["outcome"] = ""
	governance.oversight_cases[oversight_case["id"]] = investigating_oversight.duplicate(true)
	var defense_result := {"ok": true, "case": investigating_oversight.duplicate(true)}
	_check(defense_router.record_oversight_defense_success("oversight_000001", "full_disclosure", defense_result, governance, event_book, 24), "oversight defense accepts the same linked case after a judicial result-review receipt")
	_check(str(defense_progress.receipts()[8].get("authority_id", "")) == "oversight_case", "active oversight defense keeps its original authority receipt")

	if not _failed:
		print("Onboarding case result review test passed.")
	quit(1 if _failed else 0)


func _active_shell(next_index: int, due_game_day: int) -> Dictionary:
	var targets := ["build", "blueprint", "route", "fiscal", "city_data", "public_affairs", "governance", "judicial", "oversight"]
	var authorities := ["construction_job", "blueprint_review", "transport_session", "fiscal_apply", "city_data_dashboard", "resident_request", "bill_force_enactment", "judicial_result_review", "oversight_result_review"]
	var entities := ["job_1", "review_1", "route_1", "fiscal_1", "tab_1", "request_1", "judicial_000001", "judicial_000001", "oversight_000001"]
	var receipts: Array[Dictionary] = []
	for index in next_index:
		receipts.append({
			"kind": targets[index],
			"authority_id": authorities[index],
			"entity_id": entities[index],
			"game_day": index * 3,
		})
	return {
		"schema_version": 9,
		"tutorial_completed": false,
		"onboarding": {
			"schema_version": 2,
			"phase": "active",
			"next_index": next_index,
			"current_target": targets[next_index],
			"completion_basis": "",
			"receipts": receipts,
			"due_game_day": due_game_day,
		},
	}


func _force_fact() -> Dictionary:
	return {
		"fact_type": "bill_force_enacted",
		"case_id": "judicial_000001",
		"oversight_case_id": "oversight_000001",
	}


func _resolved_judicial_case() -> Dictionary:
	return {
		"id": "judicial_000001",
		"opened_day": 18,
		"resolved_day": 21,
		"status": "resolved",
		"procedural_stage": "judgment",
		"outcome": "fine",
		"final_severity": 51.25,
		"fine_amount": 17800,
		"member_votes": [{"person_id": "judge_1"}],
		"defense_template_id": "",
	}


func _resolved_oversight_case() -> Dictionary:
	var member_votes: Array[Dictionary] = []
	for index in 10:
		member_votes.append({"person_id": "oversight_%d" % index})
	return {
		"id": "oversight_000001",
		"opened_day": 18,
		"resolved_day": 24,
		"status": "resolved",
		"outcome": "impeached",
		"votes_for_impeachment": 6,
		"votes_against_impeachment": 4,
		"member_votes": member_votes,
		"defense_template_id": "",
	}


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Onboarding case result review check failed: %s" % message)
