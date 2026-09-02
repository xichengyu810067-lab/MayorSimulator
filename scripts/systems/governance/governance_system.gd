class_name GovernanceSystem
extends RefCounted

## Deterministic executive, bicameral legislature, and independent judiciary.

const JusticeSystemScript = preload("res://systems/governance/justice-oversight/justice_oversight_system.gd")
const LowerCouncilDatabaseScript = preload("res://systems/governance/lower-council/lower_council_database.gd")
const LowerCouncilVoteModelScript = preload("res://systems/governance/lower-council/lower_council_vote_model.gd")

const SCHEMA_VERSION := 3
const JUDICIARY_MIN_DAYS := 2
const JUDICIARY_MAX_DAYS := 15
const LOWER_HOUSE_SEAT_COUNT := 30
const LOWER_HOUSE_MAJORITY := 16
const CONCERN_LABELS := {
	"budget": "預算與成本",
	"public_opinion": "區域民意",
	"execution_feasibility": "執行可行性",
	"feasibility": "執行可行性",
	"roi": "投資效益",
	"economic_growth": "經濟成長",
	"employment": "就業",
	"environment": "環境影響",
	"public_safety": "公共安全",
	"housing": "住宅需求",
	"transport": "交通影響",
	"regional_balance": "區域平衡",
	"social_welfare": "社會福利",
	"healthcare": "醫療需求",
	"education": "教育需求",
	"administrative_efficiency": "行政效率",
	"utility_affordability": "公共服務可負擔性",
	"procedural_justice": "程序正義",
	"public_interest": "公共利益",
	"innovation": "創新效益",
	"accountability": "行政責任",
}

var seed: int = 20_260_715
var bill_definitions: Dictionary = default_bills()
var defense_templates: Dictionary = default_defense_templates()
var pending_bill: Dictionary = {}
var rejected_bills: Dictionary = {}
var active_laws: Dictionary = {}
var legislative_history: Array[Dictionary] = []
var judiciary_cases: Dictionary = {}
var oversight_cases: Dictionary = {}
var justice_system
var lower_council_database
var lower_council_vote_model
var _lower_council_contract_status: Dictionary = {
	"ok": false,
	"error_code": "lower_council_not_initialized",
	"errors": [],
	"expected_member_count": 30,
	"actual_member_count": 0,
}
var checks_and_balances_history: Array[Dictionary] = []
var municipal_trust: int = 70
var grievance: int = 0
var imprisonment_judgment: bool = false
var terminal_failure_reason: String = ""
var force_enactment_count: int = 0
var next_case_sequence: int = 1


func _init(p_seed: int = 20_260_715, p_bill_definitions: Dictionary = {}) -> void:
	seed = p_seed
	_initialize_justice_system()
	_initialize_lower_council()
	if not p_bill_definitions.is_empty():
		bill_definitions = p_bill_definitions.duplicate(true)


static func default_bills() -> Dictionary:
	return {
		"environment_act": {
			"id": "environment_act", "name": "環境保護法案", "type": "environment",
			"review_days": 4, "base_support": 53, "upper_threshold": 0,
			"debate_strength": 8, "force_trust_penalty": 9, "judicial_severity": 46,
			"effects": {"environment": 5, "monthly_expense": 180}
		},
		"transit_act": {
			"id": "transit_act", "name": "交通建設法案", "type": "traffic",
			"review_days": 4, "base_support": 51, "upper_threshold": 0,
			"debate_strength": 9, "force_trust_penalty": 10, "judicial_severity": 48,
			"effects": {"traffic": 6, "monthly_expense": 220}
		},
		"commerce_act": {
			"id": "commerce_act", "name": "商業促進法案", "type": "business",
			"review_days": 3, "base_support": 50, "upper_threshold": 0,
			"debate_strength": 7, "force_trust_penalty": 11, "judicial_severity": 51,
			"effects": {"business_bonus": 0.18, "environment": -2, "traffic": -2}
		},
		"welfare_act": {
			"id": "welfare_act", "name": "公共補助法案", "type": "welfare",
			"review_days": 4, "base_support": 52, "upper_threshold": 0,
			"debate_strength": 10, "force_trust_penalty": 9, "judicial_severity": 44,
			"effects": {"satisfaction": 5, "monthly_expense": 260}
		},
		"security_act": {
			"id": "security_act", "name": "公共安全法案", "type": "security",
			"review_days": 2, "base_support": 56, "upper_threshold": -5,
			"debate_strength": 8, "force_trust_penalty": 12, "judicial_severity": 55,
			"effects": {"security": 5, "monthly_expense": 160}
		},
		"utility_relief_act": {
			"id": "utility_relief_act", "name": "公共費用調整法案", "type": "utility",
			"review_days": 5, "base_support": 48, "upper_threshold": 5,
			"debate_strength": 11, "force_trust_penalty": 13, "judicial_severity": 58,
			"effects": {"utility_relief": 4, "monthly_expense": 150}
		},
		"industry_act": {
			"id": "industry_act", "name": "工業發展法案", "type": "industry",
			"review_days": 6, "base_support": 47, "upper_threshold": 5,
			"debate_strength": 7, "force_trust_penalty": 14, "judicial_severity": 62,
			"effects": {"industrial_bonus": 0.22, "job_attraction": 4, "environment": -4}
		},
		"social_housing_act": {
			"id": "social_housing_act", "name": "社會住宅法案", "type": "housing",
			"review_days": 4, "base_support": 54, "upper_threshold": 0,
			"debate_strength": 10, "force_trust_penalty": 9, "judicial_severity": 45,
			"effects": {"population": 20, "satisfaction": 3, "monthly_expense": 210}
		}
	}


static func default_defense_templates() -> Dictionary:
	return {
		"public_interest": {
			"id": "public_interest", "label": "公共利益緊急性", "severity_relief": 12,
			"text": "措施是為避免公共利益受到立即且不可逆的損害。"
		},
		"fiscal_emergency": {
			"id": "fiscal_emergency", "label": "財政緊急狀態", "severity_relief": 8,
			"text": "措施用於阻止市政財務在短期內失去運作能力。"
		},
		"safety_emergency": {
			"id": "safety_emergency", "label": "公共安全緊急狀態", "severity_relief": 18,
			"text": "措施用於處理居民生命安全的即時風險。"
		}
	}


func submit_bill(bill_id: String, current_day: int) -> Dictionary:
	if has_failed():
		return _terminal_error()
	if not _lower_council_is_available():
		return _lower_council_contract_error()
	if not bill_definitions.has(bill_id):
		return _error("bill_not_found")
	if not pending_bill.is_empty():
		return _error("another_bill_is_in_review")
	if active_laws.has(bill_id):
		return _error("bill_already_active")
	var definition: Dictionary = bill_definitions[bill_id]
	pending_bill = {
		"bill_id": bill_id,
		"submitted_day": current_day,
		"decision_day": current_day + clampi(int(definition.get("review_days", 2)), 2, 7),
		"status": "lower_house_review"
	}
	_record_check("executive_proposal", "executive", "legislature", bill_id, current_day, "行政提案已移交立法審議")
	return {"ok": true, "pending_bill": pending_bill.duplicate(true)}


func advance_day(current_day: int, context: Dictionary = {}) -> Array[Dictionary]:
	if not latch_failure().is_empty():
		return []
	var emitted: Array[Dictionary] = []
	# Courtroom procedure is authoritative model state. Advancing it here keeps
	# UI refreshes read-only while preserving the current stage in saves.
	justice_system.advance_judicial_procedures(current_day)
	if (
		not pending_bill.is_empty()
		and str(pending_bill.get("status", "")) == "lower_house_review"
		and current_day >= int(pending_bill.get("decision_day", 0))
	):
		emitted.append_array(_resolve_legislative_review(current_day, context))
	for case_id in _sorted_string_keys(judiciary_cases):
		var court_case: Dictionary = judiciary_cases[case_id]
		if str(court_case.get("status", "")) != "investigating":
			continue
		if current_day < int(court_case.get("decision_day", 0)):
			continue
		emitted.append(_resolve_judiciary_case(case_id, current_day, context))
		if not latch_failure().is_empty():
			return emitted
	for case_id in _sorted_string_keys(oversight_cases):
		var oversight_case: Dictionary = oversight_cases[case_id]
		if str(oversight_case.get("status", "")) != "investigating":
			continue
		if current_day < int(oversight_case.get("decision_day", 0)):
			continue
		var event: Dictionary = justice_system.resolve_oversight_case(case_id, current_day, context)
		if not bool(event.get("ok", true)):
			continue
		_apply_oversight_terminal_outcome(event, current_day)
		emitted.append(event)
		if not latch_failure().is_empty():
			return emitted
	return emitted


func force_enact(bill_id: String, current_day: int) -> Dictionary:
	if has_failed():
		return _terminal_error()
	if not rejected_bills.has(bill_id):
		return _error("bill_was_not_rejected")
	if active_laws.has(bill_id):
		return _error("bill_already_active")
	var definition: Dictionary = bill_definitions.get(bill_id, {})
	if definition.is_empty():
		return _error("bill_not_found")
	var prospective_force_count := force_enactment_count + 1
	var base_severity := clampi(
		int(definition.get("judicial_severity", 50)) + maxi(0, prospective_force_count - 1) * 8,
		0,
		100
	)
	var opened: Dictionary = justice_system.open_judicial_case(
		bill_id,
		current_day,
		base_severity,
		"%s強制施行審查" % str(definition.get("name", bill_id))
	)
	if not bool(opened.get("ok", false)):
		return opened
	force_enactment_count = prospective_force_count
	var trust_penalty := int(definition.get("force_trust_penalty", 10))
	municipal_trust = clampi(municipal_trust - trust_penalty, 0, 100)
	active_laws[bill_id] = {
		"bill_id": bill_id,
		"name": str(definition.get("name", bill_id)),
		"effects": definition.get("effects", {}).duplicate(true),
		"enacted_day": current_day,
		"forced": true,
		"status": "active"
	}
	var oversight_opened: Dictionary = justice_system.open_oversight_case(
		"official_mayor",
		["違法強制施行法案", "未遵守議會否決決議"],
		clampi(55 + prospective_force_count * 8, 0, 100),
		current_day
	)
	var court_case: Dictionary = opened["case"]
	var case_id := str(court_case["id"])
	next_case_sequence += 1
	latch_failure()
	_record_check("executive_override_checked", "executive", "judiciary", bill_id, current_day, "行政強制施行已自動進入司法審查與監察調查")
	return {
		"ok": true,
		"case": court_case.duplicate(true),
		"oversight_case": oversight_opened.get("case", {}).duplicate(true),
		"law": active_laws[bill_id].duplicate(true),
		"event": {
			"type": "bill_force_enacted",
			"subject_id": bill_id,
			"game_day": current_day,
			"value_delta": -trust_penalty,
			"reason_tag": "governance.force_enactment",
			"payload": {
				"case_id": case_id,
				"oversight_case_id": str(oversight_opened.get("case", {}).get("id", "")),
				"municipal_trust": municipal_trust
			}
		}
	}


func submit_defense(case_id: String, template_id: String) -> Dictionary:
	if has_failed():
		return _terminal_error()
	return justice_system.submit_defense(case_id, template_id)


func submit_oversight_defense(case_id: String, template_id: String) -> Dictionary:
	if has_failed():
		return _terminal_error()
	return justice_system.submit_oversight_defense(case_id, template_id)


func open_oversight_investigation(
	target_official_id: String,
	allegations: Array,
	evidence_strength: int,
	current_day: int
) -> Dictionary:
	if has_failed():
		return _terminal_error()
	return justice_system.open_oversight_case(
		target_official_id,
		allegations,
		evidence_strength,
		current_day
	)


func committee_summary() -> Dictionary:
	return justice_system.committee_summary()


func separation_of_powers_snapshot() -> Dictionary:
	var committee := committee_summary()
	var stopped_laws := 0
	for law_variant in active_laws.values():
		if str((law_variant as Dictionary).get("status", "active")) == "stopped_by_court":
			stopped_laws += 1
	var recent_check: Dictionary = checks_and_balances_history.back().duplicate(true) if not checks_and_balances_history.is_empty() else {}
	var pending_name := "目前無待審法案"
	if not pending_bill.is_empty():
		var bill_id := str(pending_bill.get("bill_id", ""))
		pending_name = "%s審議中" % str(bill_definitions.get(bill_id, {}).get("name", bill_id))
	return {
		"executive": {
			"title": "行政權",
			"owner": "市長與市政團隊",
			"role": "提出法案、執行法律與管理市政",
			"status": "政策執行中｜強制施行 %d 次" % force_enactment_count,
		},
		"legislature": {
			"title": "立法權",
			"owner": "下議院 30 席＋上議院區域審查",
			"role": "辯論、表決、通過或否決法案",
			"status": "%s｜已完成 %d 案" % [pending_name, legislative_history.size()],
			"seat_count": lower_council_database.seat_count if lower_council_database != null else 0,
			"data_contract": lower_council_contract_status(),
		},
		"judiciary": {
			"title": "司法權",
			"owner": "獨立司法委員會",
			"role": "審查違法行政、裁定罰款／停令／監禁",
			"status": "審理中 %d 案｜法院停令 %d 件" % [int(committee.get("judicial_open_cases", 0)), stopped_laws],
		},
		"oversight": {
			"owner": "獨立監察委員會",
			"status": "調查中 %d 案" % int(committee.get("oversight_open_cases", 0)),
		},
		"recent_check": recent_check,
		"flow_summary": str(recent_check.get("summary", "制衡軌跡：行政提案 → 立法表決 → 司法獨立審查違法行為")),
	}


func advance_committee_year(new_year: int) -> Array[Dictionary]:
	if has_failed():
		latch_failure()
		return []
	var events: Array[Dictionary] = justice_system.advance_year(new_year)
	var expired: Array[String] = []
	for event: Dictionary in events:
		if str(event.get("type", "")) == "committee_term_expired":
			expired.append(str(event.get("person_id", "")))
	for person_id: String in expired:
		var renewed: Dictionary = justice_system.renew_member_term(person_id, new_year)
		if bool(renewed.get("ok", false)):
			events.append(renewed["event"])
	return events


func set_civic_metrics(p_grievance: int, p_municipal_trust: int) -> void:
	if has_failed():
		latch_failure()
		return
	grievance = clampi(p_grievance, 0, 100)
	municipal_trust = clampi(p_municipal_trust, 0, 100)
	latch_failure()


func adjust_civic_metrics(grievance_delta: int, trust_delta: int) -> Dictionary:
	if has_failed():
		return _terminal_error()
	var before_grievance := grievance
	var before_trust := municipal_trust
	grievance = clampi(grievance + grievance_delta, 0, 100)
	municipal_trust = clampi(municipal_trust + trust_delta, 0, 100)
	latch_failure()
	return {
		"ok": true,
		"grievance_before": before_grievance,
		"grievance_after": grievance,
		"trust_before": before_trust,
		"trust_after": municipal_trust,
		"failure_reason": failure_reason()
	}


func has_failed() -> bool:
	return not failure_reason().is_empty()


func failure_reason() -> String:
	if not terminal_failure_reason.is_empty():
		return terminal_failure_reason
	return _derived_failure_reason()


func latch_failure() -> String:
	if terminal_failure_reason.is_empty():
		terminal_failure_reason = _derived_failure_reason()
	if not terminal_failure_reason.is_empty() and justice_system != null:
		justice_system.set_terminal_failure(terminal_failure_reason)
	return terminal_failure_reason


func _derived_failure_reason() -> String:
	if imprisonment_judgment:
		return "imprisonment_judgment"
	if grievance > 80:
		return "grievance_above_80"
	if municipal_trust < 40:
		return "municipal_trust_below_40"
	return ""


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"seed": seed,
		"bill_definitions": bill_definitions.duplicate(true),
		"defense_templates": defense_templates.duplicate(true),
		"pending_bill": pending_bill.duplicate(true),
		"rejected_bills": rejected_bills.duplicate(true),
		"active_laws": active_laws.duplicate(true),
		"legislative_history": legislative_history.duplicate(true),
		"judiciary_cases": judiciary_cases.duplicate(true),
		"oversight_cases": oversight_cases.duplicate(true),
		"justice_system": justice_system.to_dict(),
		"lower_council": lower_council_database.to_dict() if lower_council_database != null else {},
		"lower_council_contract": lower_council_contract_status(),
		"checks_and_balances_history": checks_and_balances_history.duplicate(true),
		"municipal_trust": municipal_trust,
		"grievance": grievance,
		"imprisonment_judgment": imprisonment_judgment,
		"terminal_failure_reason": terminal_failure_reason,
		"force_enactment_count": force_enactment_count,
		"next_case_sequence": next_case_sequence
	}


func load_dict(data: Dictionary) -> void:
	seed = int(data.get("seed", 20_260_715))
	bill_definitions = data.get("bill_definitions", default_bills()).duplicate(true)
	defense_templates = data.get("defense_templates", default_defense_templates()).duplicate(true)
	pending_bill = data.get("pending_bill", {}).duplicate(true)
	rejected_bills = data.get("rejected_bills", {}).duplicate(true)
	active_laws = data.get("active_laws", {}).duplicate(true)
	legislative_history.clear()
	for item in data.get("legislative_history", []):
		legislative_history.append(item.duplicate(true))
	_initialize_lower_council()
	var lower_council_state: Dictionary = data.get("lower_council", {})
	if not lower_council_state.is_empty() and _lower_council_is_available():
		var lower_council_load_result: Dictionary = lower_council_database.load_state(lower_council_state)
		if not bool(lower_council_load_result.get("ok", false)):
			_set_lower_council_contract_error(
				"lower_council_saved_state_invalid",
				lower_council_load_result.get("errors", [])
			)
		else:
			lower_council_vote_model = LowerCouncilVoteModelScript.new(lower_council_database, seed)
	if _lower_council_is_available() and str(pending_bill.get("status", "")) == "lower_house_data_error":
		# A save made while the catalog was unavailable may resume after the
		# authoritative 30-member contract is restored and validates again.
		pending_bill["status"] = "lower_house_review"
		pending_bill.erase("data_contract")
	checks_and_balances_history.clear()
	for item in data.get("checks_and_balances_history", []):
		if item is Dictionary:
			checks_and_balances_history.append((item as Dictionary).duplicate(true))
	_initialize_justice_system()
	var justice_state: Dictionary = data.get("justice_system", {})
	if not justice_state.is_empty():
		justice_system.load_state(justice_state)
	else:
		justice_system.judicial_cases = (data.get("judiciary_cases", {}) as Dictionary).duplicate(true)
		justice_system.oversight_cases = (data.get("oversight_cases", {}) as Dictionary).duplicate(true)
	judiciary_cases = justice_system.judicial_cases
	oversight_cases = justice_system.oversight_cases
	municipal_trust = clampi(int(data.get("municipal_trust", 70)), 0, 100)
	grievance = clampi(int(data.get("grievance", 0)), 0, 100)
	imprisonment_judgment = bool(data.get("imprisonment_judgment", false))
	if _is_mayor_impeached():
		municipal_trust = mini(municipal_trust, 39)
	terminal_failure_reason = str(data.get("terminal_failure_reason", ""))
	if terminal_failure_reason not in ["", "imprisonment_judgment", "grievance_above_80", "municipal_trust_below_40"]:
		terminal_failure_reason = ""
	latch_failure()
	force_enactment_count = maxi(0, int(data.get("force_enactment_count", 0)))
	next_case_sequence = maxi(1, int(data.get("next_case_sequence", 1)))


static func create_from_dict(data: Dictionary) -> GovernanceSystem:
	var instance := GovernanceSystem.new()
	instance.load_dict(data)
	return instance


func _resolve_legislative_review(current_day: int, context: Dictionary) -> Array[Dictionary]:
	var bill_id := str(pending_bill.get("bill_id", ""))
	var definition: Dictionary = bill_definitions.get(bill_id, {})
	var vote_context := context.duplicate(true)
	vote_context["game_day"] = current_day
	var first_vote := _lower_house_vote(definition, vote_context, false, {})
	if not bool(first_vote.get("ok", false)):
		return _pause_legislative_review_for_contract_error(bill_id, current_day, first_vote)
	var debate := _build_debate(definition, first_vote, vote_context)
	var response_options := _build_mayor_response_options(debate)
	var ranked_concerns: Array = debate.get("ranked_concerns", [])
	var primary_concern := str(ranked_concerns[0]) if not ranked_concerns.is_empty() else "execution_feasibility"
	var hearing := {
		"created_day": current_day,
		"seat_count": LOWER_HOUSE_SEAT_COUNT,
		"majority_threshold": LOWER_HOUSE_MAJORITY,
		"initial_vote": first_vote.duplicate(true),
		"concern_counts": (debate.get("concern_counts", {}) as Dictionary).duplicate(true),
		"ranked_concerns": ranked_concerns.duplicate(true),
		"primary_concern": primary_concern,
		"primary_question": "下議院主要質詢：市府將如何回應%s疑慮？" % _concern_label(primary_concern),
		"response_options": response_options.duplicate(true),
		"vote_context": vote_context.duplicate(true),
	}
	pending_bill["status"] = "awaiting_mayor_response"
	pending_bill["lower_house_hearing"] = hearing
	_record_check(
		"lower_house_hearing",
		"legislature",
		"executive",
		bill_id,
		current_day,
		"下議院完成 30 席初步意向並等待市長答詢；尚未正式表決"
	)
	return [{
		"type": "lower_house_hearing_ready",
		"subject_id": bill_id,
		"game_day": current_day,
		"reason_tag": "governance.lower_house_hearing_ready",
		"payload": pending_bill.duplicate(true),
	}]


func preview_lower_house_response(response_id: String, context: Dictionary = {}) -> Dictionary:
	if pending_bill.is_empty():
		return _error("no_pending_bill")
	if str(pending_bill.get("status", "")) != "awaiting_mayor_response":
		return _error("lower_house_not_awaiting_response")
	var hearing: Dictionary = pending_bill.get("lower_house_hearing", {})
	var response := _hearing_response_option(hearing, response_id)
	if response.is_empty():
		return _error("lower_house_response_not_found")
	var bill_id := str(pending_bill.get("bill_id", ""))
	var definition: Dictionary = bill_definitions.get(bill_id, {})
	var vote_context: Dictionary = hearing.get("vote_context", {}).duplicate(true)
	for key: Variant in context.keys():
		vote_context[key] = context[key]
	var evidence: Dictionary = response.get("feature_updates", {}).duplicate(true)
	var final_preview := _lower_house_vote(definition, vote_context, true, evidence, false)
	if not bool(final_preview.get("ok", false)):
		return final_preview
	final_preview["readonly"] = true
	final_preview["response_id"] = response_id
	final_preview["debate_evidence"] = evidence
	final_preview["model_input_signature"] = _response_model_input_signature(evidence)
	return final_preview


func answer_lower_house_hearing(response_id: String, current_day: int, context: Dictionary = {}) -> Dictionary:
	if pending_bill.is_empty():
		return _error("no_pending_bill")
	if str(pending_bill.get("status", "")) != "awaiting_mayor_response":
		return _error("lower_house_not_awaiting_response")
	var hearing: Dictionary = pending_bill.get("lower_house_hearing", {})
	var response := _hearing_response_option(hearing, response_id)
	if response.is_empty():
		return _error("lower_house_response_not_found")
	var bill_id := str(pending_bill.get("bill_id", ""))
	var definition: Dictionary = bill_definitions.get(bill_id, {})
	var vote_context: Dictionary = hearing.get("vote_context", {}).duplicate(true)
	for key: Variant in context.keys():
		vote_context[key] = context[key]
	vote_context["game_day"] = current_day
	var evidence: Dictionary = response.get("feature_updates", {}).duplicate(true)
	var final_vote := _lower_house_vote(definition, vote_context, true, evidence, true)
	if not bool(final_vote.get("ok", false)):
		var paused_events := _pause_legislative_review_for_contract_error(bill_id, current_day, final_vote)
		return {
			"ok": false,
			"error": str(final_vote.get("error", "lower_council_vote_contract_invalid")),
			"events": paused_events,
		}
	var selected_debate := {
		"rounds": 1,
		"concern_counts": (hearing.get("concern_counts", {}) as Dictionary).duplicate(true),
		"feature_updates": evidence,
		"selected_response": response.duplicate(true),
		"model_input_signature": _response_model_input_signature(evidence),
	}
	var events := _complete_legislative_review(
		current_day,
		definition,
		hearing.get("initial_vote", {}).duplicate(true),
		selected_debate,
		final_vote,
		vote_context,
		response
	)
	return {
		"ok": true,
		"response_id": response_id,
		"decision": legislative_history.back().duplicate(true),
		"events": events,
	}


func _complete_legislative_review(
	current_day: int,
	definition: Dictionary,
	first_vote: Dictionary,
	debate: Dictionary,
	final_vote: Dictionary,
	context: Dictionary,
	mayor_response: Dictionary
) -> Array[Dictionary]:
	var emitted: Array[Dictionary] = []
	var bill_id := str(pending_bill.get("bill_id", ""))
	var lower_passed := bool(final_vote.get("passed", int(final_vote["votes_for"]) > int(final_vote["votes_against"])))
	var upper_vote := {
		"passed": false,
		"votes": [],
		"veto_regions": []
	}
	if lower_passed:
		upper_vote = _upper_house_vote(definition, context)
	var passed := lower_passed and bool(upper_vote["passed"])
	var result := {
		"bill_id": bill_id,
		"name": str(definition.get("name", bill_id)),
		"submitted_day": int(pending_bill.get("submitted_day", current_day)),
		"resolved_day": current_day,
		"first_vote": first_vote,
		"debate": debate,
		"mayor_response": mayor_response.duplicate(true),
		"final_vote": final_vote,
		"lower_passed": lower_passed,
		"upper_vote": upper_vote,
		"passed": passed,
		"status": "enacted" if passed else "rejected"
	}
	legislative_history.append(result.duplicate(true))
	if passed:
		active_laws[bill_id] = {
			"bill_id": bill_id,
			"name": str(definition.get("name", bill_id)),
			"effects": definition.get("effects", {}).duplicate(true),
			"enacted_day": current_day,
			"forced": false,
			"status": "active"
		}
		emitted.append({
			"type": "bill_enacted",
			"subject_id": bill_id,
			"game_day": current_day,
			"reason_tag": "governance.two_house_approved",
			"payload": result.duplicate(true)
		})
		_record_check("legislative_approval", "legislature", "executive", bill_id, current_day, "兩院通過法案，行政權依法執行")
	else:
		rejected_bills[bill_id] = result.duplicate(true)
		var reason := "lower_house_rejected" if not lower_passed else "upper_house_veto"
		emitted.append({
			"type": "bill_rejected",
			"subject_id": bill_id,
			"game_day": current_day,
			"reason_tag": "governance.%s" % reason,
			"payload": result.duplicate(true)
		})
		_record_check("legislative_rejection", "legislature", "executive", bill_id, current_day, "立法權否決法案，行政權不得逕行施行")
	pending_bill.clear()
	return emitted


func _lower_house_vote(
	definition: Dictionary,
	context: Dictionary,
	after_debate: bool,
	feature_updates: Dictionary,
	persist_final: bool = true
) -> Dictionary:
	if not _lower_council_is_available():
		return _lower_council_contract_error_vote()
	var bill := definition.duplicate(true)
	bill["id"] = str(bill.get("id", pending_bill.get("bill_id", "")))
	bill["version"] = int(bill.get("version", 1))
	var vote_context := context.duplicate(true)
	vote_context["municipal_trust"] = municipal_trust
	vote_context["grievance"] = grievance
	var stage := "final" if after_debate else "initial"
	var raw_result: Dictionary
	if after_debate and persist_final:
		raw_result = lower_council_vote_model.conduct_vote(bill, vote_context, stage, feature_updates)
	else:
		raw_result = lower_council_vote_model.preview_vote(bill, vote_context, stage, feature_updates)
	if not bool(raw_result.get("ok", false)):
		_set_lower_council_contract_error(
			"lower_council_vote_contract_invalid",
			raw_result.get("errors", [str(raw_result.get("error", "vote model returned ok=false"))])
		)
		return _lower_council_contract_error_vote()
	var normalized_votes: Array[Dictionary] = []
	for vote_variant in raw_result.get("votes", []):
		var vote: Dictionary = vote_variant
		var normalized := vote.duplicate(true)
		normalized["supports"] = str(vote.get("choice", "abstain")) == "for"
		normalized["concern"] = str(vote.get("primary_reason", "feasibility"))
		normalized_votes.append(normalized)
	return {
		"ok": true,
		"votes_for": int(raw_result.get("votes_for", 0)),
		"votes_against": int(raw_result.get("votes_against", 0)),
		"abstentions": int(raw_result.get("abstentions", 0)),
		"absences": int(raw_result.get("absences", 0)),
		"majority_threshold": int(raw_result.get("majority_threshold", 16)),
		"passed": bool(raw_result.get("passed", false)),
		"stage": stage,
		"model": "lower_council_30_member",
		"votes": normalized_votes,
	}


func _pause_legislative_review_for_contract_error(
	bill_id: String,
	current_day: int,
	vote_error: Dictionary
) -> Array[Dictionary]:
	var contract_status := lower_council_contract_status()
	pending_bill["status"] = "lower_house_data_error"
	pending_bill["data_contract"] = contract_status
	_record_check(
		"legislative_data_contract_error",
		"legislature",
		"executive",
		bill_id,
		current_day,
		"下議院 30 席資料契約無效；審議已停止，未產生替代表決"
	)
	return [{
		"ok": false,
		"type": "legislative_data_contract_error",
		"subject_id": bill_id,
		"game_day": current_day,
		"reason_tag": "governance.lower_council_data_contract_error",
		"error": str(vote_error.get("error", contract_status.get("error_code", "lower_council_data_contract_invalid"))),
		"payload": {
			"contract_status": contract_status,
			"vote_error": vote_error.duplicate(true),
		},
	}]


func _build_debate(definition: Dictionary, first_vote: Dictionary, context: Dictionary) -> Dictionary:
	var concern_counts := {}
	for vote in first_vote.get("votes", []):
		if not bool(vote.get("supports", false)):
			var concern := str(vote.get("concern", "execution_feasibility"))
			concern_counts[concern] = int(concern_counts.get(concern, 0)) + 1
	var debate_strength := float(definition.get("debate_strength", 8))
	debate_strength += float(context.get("mayor_argument_bonus", 0.0))
	var ranked_concerns := _ranked_concerns(concern_counts)
	for fallback in ["budget", "public_opinion", "execution_feasibility"]:
		if ranked_concerns.size() >= 3:
			break
		if fallback not in ranked_concerns:
			ranked_concerns.append(fallback)
	var updates := {}
	for concern_key: String in ranked_concerns:
		updates[concern_key] = debate_strength if int(concern_counts.get(concern_key, 0)) > 0 else 0.0
	return {
		"rounds": 1,
		"concern_counts": concern_counts,
		"ranked_concerns": ranked_concerns,
		"debate_strength": debate_strength,
		"feature_updates": updates,
	}


func _build_mayor_response_options(debate: Dictionary) -> Array[Dictionary]:
	var ranked: Array = debate.get("ranked_concerns", [])
	var base_strength := clampf(float(debate.get("debate_strength", 8.0)), 1.0, 100.0)
	var first := str(ranked[0])
	var second := str(ranked[1])
	var third := str(ranked[2])
	var focus_updates := {}
	focus_updates[first] = minf(100.0, base_strength + 18.0)
	var balance_updates := {}
	balance_updates[first] = minf(100.0, base_strength + 10.0)
	balance_updates[second] = minf(100.0, base_strength + 10.0)
	var comprehensive_updates := {}
	comprehensive_updates[first] = minf(100.0, base_strength + 5.0)
	comprehensive_updates[second] = minf(100.0, base_strength + 5.0)
	comprehensive_updates[third] = minf(100.0, base_strength + 5.0)
	return [
		{
			"id": "focus_primary",
			"label": "聚焦主要疑慮",
			"description": "提出具體證據，優先回應%s。" % _concern_label(first),
			"focus_concerns": [first],
			"feature_updates": focus_updates,
		},
		{
			"id": "balance_coalition",
			"label": "平衡兩項質詢",
			"description": "同時回應%s與%s，爭取跨黨團支持。" % [_concern_label(first), _concern_label(second)],
			"focus_concerns": [first, second],
			"feature_updates": balance_updates,
		},
		{
			"id": "comprehensive_commitment",
			"label": "提出全面執行承諾",
			"description": "以完整執行方案回應%s、%s與%s。" % [_concern_label(first), _concern_label(second), _concern_label(third)],
			"focus_concerns": [first, second, third],
			"feature_updates": comprehensive_updates,
		},
	]


func _ranked_concerns(concern_counts: Dictionary) -> Array[String]:
	var ranked: Array[String] = []
	for key: Variant in concern_counts.keys():
		ranked.append(str(key))
	ranked.sort_custom(func(left: String, right: String) -> bool:
		var left_count := int(concern_counts.get(left, 0))
		var right_count := int(concern_counts.get(right, 0))
		return left < right if left_count == right_count else left_count > right_count
	)
	return ranked


func _hearing_response_option(hearing: Dictionary, response_id: String) -> Dictionary:
	for option_variant: Variant in hearing.get("response_options", []):
		if option_variant is Dictionary and str((option_variant as Dictionary).get("id", "")) == response_id:
			return (option_variant as Dictionary).duplicate(true)
	return {}


func _concern_label(concern: String) -> String:
	return str(CONCERN_LABELS.get(concern, concern.replace("_", " ")))


func _response_model_input_signature(evidence: Dictionary) -> String:
	var sorted_evidence := {}
	var keys: Array[String] = []
	for key: Variant in evidence.keys():
		keys.append(str(key))
	keys.sort()
	for key: String in keys:
		sorted_evidence[key] = evidence[key]
	return JSON.stringify({"debate_evidence": sorted_evidence}).sha256_text()


func _upper_house_vote(definition: Dictionary, context: Dictionary) -> Dictionary:
	var regional_support: Dictionary = context.get("regional_support", {})
	if regional_support.is_empty():
		var baseline := float(context.get("public_support", 50.0)) - float(grievance) * 0.25
		regional_support = {
			"north": baseline,
			"east": baseline - 2.0,
			"south": baseline + 1.0,
			"west": baseline - 1.0
		}
	var threshold := float(definition.get("upper_threshold", 0))
	var votes: Array[Dictionary] = []
	var veto_regions: Array[String] = []
	for region_id in _sorted_string_keys(regional_support):
		var support_score := float(regional_support[region_id])
		var supports := support_score >= threshold
		if not supports:
			veto_regions.append(region_id)
		votes.append({
			"region_id": region_id,
			"support_score": support_score,
			"threshold": threshold,
			"supports": supports
		})
	return {
		"passed": veto_regions.is_empty(),
		"votes": votes,
		"veto_regions": veto_regions
	}


func _resolve_judiciary_case(case_id: String, current_day: int, context: Dictionary) -> Dictionary:
	var event: Dictionary = justice_system.resolve_judicial_case(case_id, current_day, context)
	if not bool(event.get("ok", false)):
		return {
			"type": "judiciary_resolution_error",
			"subject_id": case_id,
			"game_day": current_day,
			"reason_tag": "judiciary.resolution_error",
			"payload": event,
		}
	var court_case: Dictionary = event.get("payload", {}).get("case", {})
	var bill_id := str(court_case.get("bill_id", ""))
	var outcome := str(court_case.get("outcome", "fine"))
	var fine_amount := int(court_case.get("fine_amount", 0))
	var trust_penalty := 0
	if outcome == "fine":
		trust_penalty = 4
	elif outcome == "stop_order":
		trust_penalty = 9
		if active_laws.has(bill_id):
			var law: Dictionary = active_laws[bill_id]
			law["status"] = "stopped_by_court"
			law["stopped_day"] = current_day
			active_laws[bill_id] = law
	else:
		trust_penalty = 20
		imprisonment_judgment = true
	municipal_trust = clampi(municipal_trust - trust_penalty, 0, 100)
	latch_failure()
	var payload: Dictionary = event.get("payload", {})
	payload["municipal_trust"] = municipal_trust
	payload["failure_reason"] = failure_reason()
	event["payload"] = payload
	_record_check("judicial_ruling", "judiciary", "executive", bill_id, current_day, "司法裁定：%s；行政權必須遵守" % outcome)
	return event


func _apply_oversight_terminal_outcome(event: Dictionary, current_day: int) -> void:
	if str(event.get("type", "")) != "oversight_impeachment":
		return
	if str(event.get("subject_id", "")) != "official_mayor":
		return
	municipal_trust = mini(municipal_trust, 39)
	var payload: Dictionary = event.get("payload", {})
	var oversight_case: Dictionary = payload.get("case", {})
	payload["case_id"] = str(oversight_case.get("id", ""))
	payload["municipal_trust"] = municipal_trust
	payload["failure_reason"] = "municipal_trust_below_40"
	event["payload"] = payload
	_record_check("mayor_impeached", "oversight", "executive", "official_mayor", current_day, "監察委員會通過彈劾行政官員。")
	latch_failure()


func _initialize_justice_system() -> void:
	justice_system = JusticeSystemScript.new(seed)
	justice_system.initialize()
	justice_system.register_administrative_official("official_mayor", "現任市長", "mayor", "市長")
	judiciary_cases = justice_system.judicial_cases
	oversight_cases = justice_system.oversight_cases


func _is_mayor_impeached() -> bool:
	if justice_system == null:
		return false
	var mayor: Dictionary = justice_system.administrative_officials.get("official_mayor", {})
	return str(mayor.get("status", "")) == "impeached"


func _initialize_lower_council() -> void:
	lower_council_database = null
	lower_council_vote_model = null
	var candidate_database = LowerCouncilDatabaseScript.new()
	var load_result: Dictionary = candidate_database.load_default()
	if not bool(load_result.get("ok", false)):
		_set_lower_council_contract_error(
			"lower_council_default_catalog_invalid",
			load_result.get("errors", [])
		)
		return
	lower_council_database = candidate_database
	lower_council_vote_model = LowerCouncilVoteModelScript.new(lower_council_database, seed)
	_lower_council_contract_status = {
		"ok": true,
		"error_code": "",
		"errors": [],
		"expected_member_count": 30,
		"actual_member_count": lower_council_database.members.size(),
		"seat_count": lower_council_database.seat_count,
		"majority_threshold": lower_council_database.majority_threshold,
	}


func lower_council_contract_status() -> Dictionary:
	return _lower_council_contract_status.duplicate(true)


func _lower_council_is_available() -> bool:
	if (
		bool(_lower_council_contract_status.get("ok", false))
		and lower_council_database != null
		and lower_council_vote_model != null
	):
		return true
	if bool(_lower_council_contract_status.get("ok", false)):
		_set_lower_council_contract_error(
			"lower_council_runtime_unavailable",
			["30-member lower-council database or vote model is unavailable"]
		)
	return false


func _set_lower_council_contract_error(error_code: String, errors_variant: Variant) -> void:
	var errors: Array[String] = []
	if errors_variant is Array:
		for error_variant: Variant in errors_variant:
			errors.append(str(error_variant))
	elif not str(errors_variant).is_empty():
		errors.append(str(errors_variant))
	var actual_member_count := 0
	if lower_council_database != null:
		actual_member_count = lower_council_database.members.size()
	lower_council_database = null
	lower_council_vote_model = null
	_lower_council_contract_status = {
		"ok": false,
		"error_code": error_code,
		"errors": errors,
		"expected_member_count": 30,
		"actual_member_count": actual_member_count,
	}


func _lower_council_contract_error() -> Dictionary:
	var status := lower_council_contract_status()
	return {
		"ok": false,
		"error": str(status.get("error_code", "lower_council_data_contract_invalid")),
		"contract_status": status,
	}


func _lower_council_contract_error_vote() -> Dictionary:
	var result := _lower_council_contract_error()
	result.merge({
		"votes_for": 0,
		"votes_against": 0,
		"abstentions": 0,
		"absences": 0,
		"majority_threshold": 16,
		"passed": false,
		"model": "lower_council_unavailable",
		"votes": [],
	})
	return result


func _record_check(
	action: String,
	from_branch: String,
	to_branch: String,
	subject_id: String,
	game_day: int,
	summary: String
) -> void:
	checks_and_balances_history.append({
		"action": action,
		"from_branch": from_branch,
		"to_branch": to_branch,
		"subject_id": subject_id,
		"game_day": game_day,
		"summary": summary,
	})
	while checks_and_balances_history.size() > 100:
		checks_and_balances_history.pop_front()


func _judiciary_duration(case_id: String, bill_id: String) -> int:
	var span := JUDICIARY_MAX_DAYS - JUDICIARY_MIN_DAYS + 1
	return JUDICIARY_MIN_DAYS + (_stable_int("%d|%s|%s" % [seed, case_id, bill_id]) % span)


static func _stable_int(value: String) -> int:
	var result := 7
	for index in value.length():
		result = int((result * 31 + value.unicode_at(index)) % 2_147_483_647)
	return result


static func _sorted_string_keys(source: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key in source.keys():
		result.append(str(key))
	result.sort()
	return result


static func _error(code: String) -> Dictionary:
	return {"ok": false, "error": code}


func _terminal_error() -> Dictionary:
	var reason := latch_failure()
	return {
		"ok": false,
		"error": "game_already_failed",
		"failure_reason": reason,
	}
