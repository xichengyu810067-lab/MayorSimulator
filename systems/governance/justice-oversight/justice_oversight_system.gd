class_name JusticeOversightSystem
extends RefCounted

const SCHEMA_VERSION := 1
const DEFAULT_DATA_PATH := "res://data/databases/governance/justice-oversight/committee_members.json"
const LOWER_COUNCIL_DATA_PATH := "res://data/databases/governance/lower-council/councilors.json"
const JUDICIAL_COMMITTEE := "judicial_committee"
const OVERSIGHT_COMMITTEE := "oversight_committee"
const VALID_GENDERS := ["女性", "男性", "非二元"]
const DEFENSE_RELIEF := {
	"public_interest": 12,
	"fiscal_emergency": 8,
	"safety_emergency": 18,
}
const OVERSIGHT_DEFENSE_RELIEF := {
	"full_disclosure": 16,
	"due_process": 10,
	"corrective_action": 13,
}

var seed: int = 20_260_722
var current_year: int = 1
var committees: Dictionary = {}
var members: Dictionary = {}
var office_registry: Dictionary = {}
var administrative_officials: Dictionary = {}
var judicial_cases: Dictionary = {}
var oversight_cases: Dictionary = {}
var term_history: Array[Dictionary] = []
var next_judicial_sequence: int = 1
var next_oversight_sequence: int = 1
var _load_errors: Array[String] = []
var _terminal_failure_reason: String = ""


func _init(p_seed: int = 20_260_722) -> void:
	seed = p_seed


func initialize(path: String = DEFAULT_DATA_PATH) -> Dictionary:
	_reset()
	if not FileAccess.file_exists(path):
		return {"ok": false, "errors": ["找不到司法委員資料：%s" % path]}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "errors": ["無法開啟司法委員資料：%s" % path]}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {"ok": false, "errors": ["司法委員資料不是有效 JSON"]}
	committees = (parsed.get("committees", {}) as Dictionary).duplicate(true)
	_reserve_lower_council_members()
	for value: Variant in parsed.get("members", []):
		if not value is Dictionary:
			continue
		var member: Dictionary = value.duplicate(true)
		member["active"] = bool(member.get("active", true))
		member["reviewed_case_ids"] = (member.get("reviewed_case_ids", []) as Array).duplicate()
		_add_committee_member(member)
	return validate()


func validate() -> Dictionary:
	var errors: Array[String] = _load_errors.duplicate()
	for committee_id: String in [JUDICIAL_COMMITTEE, OVERSIGHT_COMMITTEE]:
		if not committees.has(committee_id):
			errors.append("缺少委員會：%s" % committee_id)
			continue
		var definition: Dictionary = committees[committee_id]
		var expected_capacity := 15 if committee_id == JUDICIAL_COMMITTEE else 10
		var expected_term := 5 if committee_id == JUDICIAL_COMMITTEE else 3
		if int(definition.get("capacity", 0)) != expected_capacity:
			errors.append("%s 席次必須是 %d" % [committee_id, expected_capacity])
		if int(definition.get("term_years", 0)) != expected_term:
			errors.append("%s 任期必須是 %d 個遊戲年" % [committee_id, expected_term])
		if (definition.get("responsibilities", []) as Array).is_empty():
			errors.append("%s 必須具備職務說明" % committee_id)

	if active_member_ids(JUDICIAL_COMMITTEE).size() != 15:
		errors.append("司法委員會必須有 15 名委員")
	if active_member_ids(OVERSIGHT_COMMITTEE).size() != 10:
		errors.append("監察委員會必須有 10 名委員")

	var names: Dictionary = {}
	for person_id: String in sorted_member_ids():
		var member: Dictionary = members[person_id]
		var name := str(member.get("name", ""))
		if name.is_empty() or names.has(name):
			errors.append("委員姓名空白或重複：%s" % name)
		names[name] = true
		if not VALID_GENDERS.has(str(member.get("gender", ""))):
			errors.append("%s 的性別值無效" % person_id)
		if int(member.get("age", 0)) < 18:
			errors.append("%s 的年齡無效" % person_id)
		if (member.get("personality_tags", []) as Array).size() < 3:
			errors.append("%s 至少需要三個性格標籤" % person_id)
		if (member.get("major_cases", []) as Array).is_empty():
			errors.append("%s 缺少重大案件紀錄" % person_id)
		var committee_id := str(member.get("committee_id", ""))
		if not committees.has(committee_id):
			errors.append("%s 指向不存在的委員會" % person_id)
			continue
		var required_term := int((committees[committee_id] as Dictionary).get("term_years", 0))
		if int(member.get("term_years", 0)) != required_term:
			errors.append("%s 的任期年數不符合委員會規則" % person_id)
		if int(member.get("term_end_year", 0)) - int(member.get("appointed_year", 0)) != required_term:
			errors.append("%s 的任期起訖不是 %d 年" % [person_id, required_term])

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"judicial_members": active_member_ids(JUDICIAL_COMMITTEE).size(),
		"oversight_members": active_member_ids(OVERSIGHT_COMMITTEE).size(),
		"registered_offices": office_registry.size(),
	}


func set_terminal_failure(reason: String) -> void:
	if _terminal_failure_reason.is_empty() and not reason.is_empty():
		_terminal_failure_reason = reason


func is_terminal_locked() -> bool:
	return not _terminal_failure_reason.is_empty()


func terminal_failure_reason() -> String:
	return _terminal_failure_reason


func register_administrative_official(person_id: String, name: String, office_id: String, role: String) -> Dictionary:
	if is_terminal_locked():
		return _terminal_error()
	if person_id.is_empty() or name.is_empty() or office_id.is_empty():
		return {"ok": false, "error": "invalid_official"}
	var conflict := _office_conflict(person_id, name)
	if not conflict.is_empty():
		return {"ok": false, "error": "one_person_one_office", "conflict": conflict}
	var record := {"person_id": person_id, "name": name, "office_id": office_id, "role": role, "status": "active"}
	administrative_officials[person_id] = record
	office_registry[person_id] = record.duplicate(true)
	return {"ok": true, "official": record.duplicate(true)}


func appoint_replacement(committee_id: String, member_data: Dictionary, appointment_year: int) -> Dictionary:
	if is_terminal_locked():
		return _terminal_error()
	if not committees.has(committee_id):
		return {"ok": false, "error": "committee_not_found"}
	var capacity := int((committees[committee_id] as Dictionary).get("capacity", 0))
	if member_ids_for_committee(committee_id, true).size() >= capacity:
		return {"ok": false, "error": "committee_at_capacity"}
	var member := member_data.duplicate(true)
	member["committee_id"] = committee_id
	member["role"] = "司法委員" if committee_id == JUDICIAL_COMMITTEE else "監察委員"
	member["appointed_year"] = appointment_year
	member["term_years"] = int((committees[committee_id] as Dictionary).get("term_years", 0))
	member["term_end_year"] = appointment_year + int(member["term_years"])
	member["active"] = true
	member["reviewed_case_ids"] = []
	var conflict := _office_conflict(str(member.get("person_id", "")), str(member.get("name", "")))
	if not conflict.is_empty():
		return {"ok": false, "error": "one_person_one_office", "conflict": conflict}
	_add_committee_member(member)
	return {"ok": true, "member": member.duplicate(true)}


func renew_member_term(person_id: String, appointment_year: int) -> Dictionary:
	if is_terminal_locked():
		return _terminal_error()
	if not members.has(person_id):
		return {"ok": false, "error": "member_not_found"}
	var member: Dictionary = members[person_id]
	if bool(member.get("active", true)):
		return {"ok": false, "error": "member_term_still_active"}
	var committee_id := str(member.get("committee_id", ""))
	if not committees.has(committee_id):
		return {"ok": false, "error": "committee_not_found"}
	var term_years := int((committees[committee_id] as Dictionary).get("term_years", 0))
	member["appointed_year"] = appointment_year
	member["term_years"] = term_years
	member["term_end_year"] = appointment_year + term_years
	member["active"] = true
	members[person_id] = member
	var event := {
		"type": "committee_member_reappointed",
		"person_id": person_id,
		"committee_id": committee_id,
		"game_year": appointment_year,
		"term_end_year": appointment_year + term_years,
	}
	term_history.append(event.duplicate(true))
	return {"ok": true, "member": member.duplicate(true), "event": event}


func advance_year(new_year: int) -> Array[Dictionary]:
	if is_terminal_locked():
		return []
	if new_year <= current_year:
		return []
	var events: Array[Dictionary] = []
	for year: int in range(current_year + 1, new_year + 1):
		for person_id: String in sorted_member_ids():
			var member: Dictionary = members[person_id]
			member["age"] = int(member.get("age", 0)) + 1
			members[person_id] = member
			if not bool(member.get("active", true)):
				continue
			if year < int(member.get("term_end_year", 0)):
				continue
			member["active"] = false
			members[person_id] = member
			var event := {
				"type": "committee_term_expired",
				"person_id": person_id,
				"committee_id": str(member.get("committee_id", "")),
				"game_year": year,
			}
			term_history.append(event.duplicate(true))
			events.append(event)
	current_year = new_year
	return events


func open_judicial_case(
	bill_id: String,
	current_day: int,
	base_severity: int,
	case_name: String = "行政違法審查"
) -> Dictionary:
	if is_terminal_locked():
		return _terminal_error()
	if active_member_ids(JUDICIAL_COMMITTEE).size() != 15:
		return {"ok": false, "error": "judicial_committee_not_fully_seated"}
	var case_id := "judicial_%06d" % next_judicial_sequence
	var investigation_days := 2 + (_stable_int("%d|%s" % [seed, case_id]) % 14)
	var court_case := {
		"id": case_id,
		"sequence": next_judicial_sequence,
		"name": case_name,
		"bill_id": bill_id,
		"opened_day": current_day,
		"investigation_days": investigation_days,
		"decision_day": current_day + investigation_days,
		"status": "investigating",
		"base_severity": clampi(base_severity, 0, 100),
		"defense_template_id": "",
		"committee_member_ids": active_member_ids(JUDICIAL_COMMITTEE),
		"member_votes": [],
		"outcome": "",
	}
	judicial_cases[case_id] = court_case
	next_judicial_sequence += 1
	return {"ok": true, "case": court_case.duplicate(true)}


func submit_defense(case_id: String, template_id: String) -> Dictionary:
	if is_terminal_locked():
		return _terminal_error()
	if not judicial_cases.has(case_id):
		return {"ok": false, "error": "case_not_found"}
	if not DEFENSE_RELIEF.has(template_id):
		return {"ok": false, "error": "defense_template_not_found"}
	var court_case: Dictionary = judicial_cases[case_id]
	if str(court_case.get("status", "")) != "investigating":
		return {"ok": false, "error": "case_not_investigating"}
	court_case["defense_template_id"] = template_id
	judicial_cases[case_id] = court_case
	return {"ok": true, "case": court_case.duplicate(true)}


func resolve_judicial_case(case_id: String, current_day: int, context: Dictionary = {}) -> Dictionary:
	if is_terminal_locked():
		return _terminal_error()
	if not judicial_cases.has(case_id):
		return {"ok": false, "error": "case_not_found"}
	var court_case: Dictionary = judicial_cases[case_id]
	if str(court_case.get("status", "")) != "investigating":
		return {"ok": false, "error": "case_not_investigating"}
	if current_day < int(court_case.get("decision_day", 0)):
		return {"ok": false, "error": "decision_not_due"}
	var defense_relief := int(DEFENSE_RELIEF.get(str(court_case.get("defense_template_id", "")), 0))
	var effectiveness_values: Dictionary = context.get("policy_effectiveness", {})
	var effectiveness := clampf(float(effectiveness_values.get(str(court_case.get("bill_id", "")), 0.0)), -20.0, 20.0)
	var member_votes: Array[Dictionary] = []
	var severity_total := 0.0
	for person_id: String in active_member_ids(JUDICIAL_COMMITTEE):
		var member: Dictionary = members[person_id]
		var severity := float(court_case.get("base_severity", 50)) - defense_relief - effectiveness * 0.5
		severity += _judicial_personality_bias(member)
		severity += _stable_variation(case_id, person_id, 4.0)
		severity = clampf(severity, 0.0, 100.0)
		severity_total += severity
		member_votes.append({
			"person_id": person_id,
			"severity": snappedf(severity, 0.01),
			"recommendation": _judicial_outcome(severity),
		})
		_record_member_case(person_id, case_id)
	var final_severity := severity_total / maxf(1.0, float(member_votes.size()))
	var outcome := _judicial_outcome(final_severity)
	var fine_amount := 0
	if outcome == "fine":
		fine_amount = 5_000 + int(round(final_severity)) * 250
	court_case["status"] = "resolved"
	court_case["resolved_day"] = current_day
	court_case["final_severity"] = snappedf(final_severity, 0.01)
	court_case["outcome"] = outcome
	court_case["fine_amount"] = fine_amount
	court_case["member_votes"] = member_votes
	judicial_cases[case_id] = court_case
	return {
		"ok": true,
		"type": "judiciary_%s" % outcome,
		"subject_id": case_id,
		"game_day": current_day,
		"value_delta": -fine_amount,
		"reason_tag": "judiciary.committee_%s" % outcome,
		"payload": {"case": court_case.duplicate(true)},
	}


func open_oversight_case(
	target_official_id: String,
	allegations: Array,
	evidence_strength: int,
	current_day: int
) -> Dictionary:
	if is_terminal_locked():
		return _terminal_error()
	if not administrative_officials.has(target_official_id):
		return {"ok": false, "error": "target_is_not_administrative_official"}
	var target: Dictionary = administrative_officials[target_official_id]
	if str(target.get("status", "active")) != "active":
		return {"ok": false, "error": "official_not_active"}
	if active_member_ids(OVERSIGHT_COMMITTEE).size() != 10:
		return {"ok": false, "error": "oversight_committee_not_fully_seated"}
	var case_id := "oversight_%06d" % next_oversight_sequence
	var review_days := 3 + (_stable_int("%d|%s" % [seed, case_id]) % 8)
	var oversight_case := {
		"id": case_id,
		"sequence": next_oversight_sequence,
		"target_official_id": target_official_id,
		"target_name": str(target.get("name", target_official_id)),
		"allegations": allegations.duplicate(true),
		"evidence_strength": clampi(evidence_strength, 0, 100),
		"opened_day": current_day,
		"decision_day": current_day + review_days,
		"status": "investigating",
		"defense_template_id": "",
		"committee_member_ids": active_member_ids(OVERSIGHT_COMMITTEE),
		"member_votes": [],
		"outcome": "",
	}
	oversight_cases[case_id] = oversight_case
	next_oversight_sequence += 1
	return {"ok": true, "case": oversight_case.duplicate(true)}


func submit_oversight_defense(case_id: String, template_id: String) -> Dictionary:
	if is_terminal_locked():
		return _terminal_error()
	if not oversight_cases.has(case_id):
		return {"ok": false, "error": "case_not_found"}
	if not OVERSIGHT_DEFENSE_RELIEF.has(template_id):
		return {"ok": false, "error": "defense_template_not_found"}
	var oversight_case: Dictionary = oversight_cases[case_id]
	if str(oversight_case.get("status", "")) != "investigating":
		return {"ok": false, "error": "case_not_investigating"}
	oversight_case["defense_template_id"] = template_id
	oversight_cases[case_id] = oversight_case
	return {"ok": true, "case": oversight_case.duplicate(true)}


func resolve_due_oversight_cases(current_day: int, context: Dictionary = {}) -> Array[Dictionary]:
	if is_terminal_locked():
		return []
	var events: Array[Dictionary] = []
	for case_id: String in _sorted_keys(oversight_cases):
		var oversight_case: Dictionary = oversight_cases[case_id]
		if str(oversight_case.get("status", "")) != "investigating":
			continue
		if current_day < int(oversight_case.get("decision_day", 0)):
			continue
		var event: Dictionary = resolve_oversight_case(case_id, current_day, context)
		if bool(event.get("ok", true)):
			events.append(event)
	return events


func resolve_oversight_case(case_id: String, current_day: int, context: Dictionary = {}) -> Dictionary:
	if is_terminal_locked():
		return _terminal_error()
	if not oversight_cases.has(case_id):
		return {"ok": false, "error": "case_not_found"}
	var oversight_case: Dictionary = oversight_cases[case_id]
	if str(oversight_case.get("status", "")) != "investigating":
		return {"ok": false, "error": "case_not_investigating"}
	if current_day < int(oversight_case.get("decision_day", 0)):
		return {"ok": false, "error": "decision_not_due"}
	return _resolve_oversight_case(case_id, current_day, context)


func committee_summary() -> Dictionary:
	var judicial_active := active_member_ids(JUDICIAL_COMMITTEE).size()
	var oversight_active := active_member_ids(OVERSIGHT_COMMITTEE).size()
	var judicial_open := 0
	var oversight_open := 0
	for value: Variant in judicial_cases.values():
		if str((value as Dictionary).get("status", "")) == "investigating":
			judicial_open += 1
	for value: Variant in oversight_cases.values():
		if str((value as Dictionary).get("status", "")) == "investigating":
			oversight_open += 1
	return {
		"judicial_active": judicial_active,
		"judicial_capacity": 15,
		"judicial_term_years": 5,
		"judicial_open_cases": judicial_open,
		"oversight_active": oversight_active,
		"oversight_capacity": 10,
		"oversight_term_years": 3,
		"oversight_open_cases": oversight_open,
		"current_year": current_year,
	}


func active_member_ids(committee_id: String) -> Array[String]:
	return member_ids_for_committee(committee_id, true)


func member_ids_for_committee(committee_id: String, active_only: bool = true) -> Array[String]:
	var result: Array[String] = []
	for person_id: String in sorted_member_ids():
		var member: Dictionary = members[person_id]
		if str(member.get("committee_id", "")) != committee_id:
			continue
		if active_only and not bool(member.get("active", true)):
			continue
		result.append(person_id)
	return result


func sorted_member_ids() -> Array[String]:
	return _sorted_keys(members)


func get_member(person_id: String) -> Dictionary:
	return (members.get(person_id, {}) as Dictionary).duplicate(true)


func to_dict() -> Dictionary:
	var member_data: Array[Dictionary] = []
	for person_id: String in sorted_member_ids():
		member_data.append((members[person_id] as Dictionary).duplicate(true))
	return {
		"schema_version": SCHEMA_VERSION,
		"seed": seed,
		"current_year": current_year,
		"committees": committees.duplicate(true),
		"members": member_data,
		"administrative_officials": administrative_officials.duplicate(true),
		"judicial_cases": judicial_cases.duplicate(true),
		"oversight_cases": oversight_cases.duplicate(true),
		"term_history": term_history.duplicate(true),
		"next_judicial_sequence": next_judicial_sequence,
		"next_oversight_sequence": next_oversight_sequence,
	}


func load_state(data: Dictionary) -> Dictionary:
	var base := initialize()
	if not bool(base.get("ok", false)):
		return base
	if data.is_empty():
		return base
	seed = int(data.get("seed", seed))
	current_year = maxi(1, int(data.get("current_year", 1)))
	if data.has("members"):
		members.clear()
		office_registry.clear()
		_load_errors.clear()
		_reserve_lower_council_members()
		for value: Variant in data.get("members", []):
			if value is Dictionary:
				_add_committee_member(value)
	administrative_officials = (data.get("administrative_officials", {}) as Dictionary).duplicate(true)
	for person_id: String in _sorted_keys(administrative_officials):
		var record: Dictionary = administrative_officials[person_id]
		if _office_conflict(person_id, str(record.get("name", ""))).is_empty():
			office_registry[person_id] = record.duplicate(true)
	judicial_cases = (data.get("judicial_cases", {}) as Dictionary).duplicate(true)
	oversight_cases = (data.get("oversight_cases", {}) as Dictionary).duplicate(true)
	term_history.clear()
	for value: Variant in data.get("term_history", []):
		if value is Dictionary:
			term_history.append(value.duplicate(true))
	next_judicial_sequence = maxi(1, int(data.get("next_judicial_sequence", 1)))
	next_oversight_sequence = maxi(1, int(data.get("next_oversight_sequence", 1)))
	return validate()


func stable_hash() -> String:
	return JSON.stringify(_canonicalize(to_dict())).sha256_text()


func _resolve_oversight_case(case_id: String, current_day: int, context: Dictionary) -> Dictionary:
	var oversight_case: Dictionary = oversight_cases[case_id]
	var defense_relief := int(OVERSIGHT_DEFENSE_RELIEF.get(str(oversight_case.get("defense_template_id", "")), 0))
	var member_votes: Array[Dictionary] = []
	var votes_for := 0
	var official_risk: Dictionary = context.get("official_integrity_risk", {})
	var target_id := str(oversight_case.get("target_official_id", ""))
	for person_id: String in active_member_ids(OVERSIGHT_COMMITTEE):
		var member: Dictionary = members[person_id]
		var score := float(oversight_case.get("evidence_strength", 50)) - defense_relief
		score += float(official_risk.get(target_id, 0)) * 0.25
		score += _oversight_personality_bias(member)
		score += _stable_variation(case_id, person_id, 5.0)
		var impeach := score >= 55.0
		if impeach:
			votes_for += 1
		member_votes.append({"person_id": person_id, "score": snappedf(score, 0.01), "impeach": impeach})
		_record_member_case(person_id, case_id)
	var impeached := votes_for >= 6
	oversight_case["status"] = "resolved"
	oversight_case["resolved_day"] = current_day
	oversight_case["votes_for_impeachment"] = votes_for
	oversight_case["votes_against_impeachment"] = 10 - votes_for
	oversight_case["member_votes"] = member_votes
	oversight_case["outcome"] = "impeached" if impeached else "cleared"
	oversight_cases[case_id] = oversight_case
	if impeached and administrative_officials.has(target_id):
		var official: Dictionary = administrative_officials[target_id]
		official["status"] = "impeached"
		official["impeached_day"] = current_day
		administrative_officials[target_id] = official
		office_registry[target_id] = official.duplicate(true)
	return {
		"type": "oversight_impeachment" if impeached else "oversight_cleared",
		"subject_id": target_id,
		"game_day": current_day,
		"reason_tag": "oversight.committee_decision",
		"payload": {"case": oversight_case.duplicate(true)},
	}


func _add_committee_member(member: Dictionary) -> void:
	var person_id := str(member.get("person_id", ""))
	var name := str(member.get("name", ""))
	if person_id.is_empty() or members.has(person_id):
		_load_errors.append("委員 person_id 空白或重複：%s" % person_id)
		return
	var conflict := _office_conflict(person_id, name)
	if not conflict.is_empty():
		_load_errors.append("一人一職衝突：%s 與 %s" % [name, conflict.get("office_id", "unknown")])
		return
	var stored := member.duplicate(true)
	stored["active"] = bool(stored.get("active", true))
	stored["reviewed_case_ids"] = (stored.get("reviewed_case_ids", []) as Array).duplicate()
	members[person_id] = stored
	office_registry[person_id] = {
		"person_id": person_id,
		"name": name,
		"office_id": "committee:%s" % str(stored.get("committee_id", "")),
		"role": str(stored.get("role", "委員")),
	}


func _reserve_lower_council_members() -> void:
	if not FileAccess.file_exists(LOWER_COUNCIL_DATA_PATH):
		return
	var file := FileAccess.open(LOWER_COUNCIL_DATA_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	for value: Variant in parsed.get("members", []):
		if not value is Dictionary:
			continue
		var person_id := str(value.get("member_id", ""))
		if person_id.is_empty():
			continue
		office_registry[person_id] = {
			"person_id": person_id,
			"name": str(value.get("name", "")),
			"office_id": "lower_council",
			"role": "下議院議員",
		}


func _office_conflict(person_id: String, name: String) -> Dictionary:
	if office_registry.has(person_id):
		return (office_registry[person_id] as Dictionary).duplicate(true)
	for record: Dictionary in office_registry.values():
		if not name.is_empty() and str(record.get("name", "")) == name:
			return record.duplicate(true)
	return {}


func _record_member_case(person_id: String, case_id: String) -> void:
	if not members.has(person_id):
		return
	var member: Dictionary = members[person_id]
	var reviewed: Array = member.get("reviewed_case_ids", [])
	if not reviewed.has(case_id):
		reviewed.append(case_id)
	member["reviewed_case_ids"] = reviewed
	members[person_id] = member


func _judicial_personality_bias(member: Dictionary) -> float:
	var result := 0.0
	var tags: Array = member.get("personality_tags", [])
	for tag: String in tags:
		if tag in ["重人權", "同理", "重公平", "重復原"]:
			result -= 2.0
		elif tag in ["保守", "重秩序", "重安全", "威嚴"]:
			result += 2.0
	return result


func _oversight_personality_bias(member: Dictionary) -> float:
	var result := 0.0
	var tags: Array = member.get("personality_tags", [])
	for tag: String in tags:
		if tag in ["正直", "重透明", "重問責", "嚴格"]:
			result += 2.5
		elif tag in ["保守", "審慎", "低調"]:
			result -= 1.0
	return result


func _judicial_outcome(severity: float) -> String:
	if severity >= 80.0:
		return "prison"
	if severity >= 55.0:
		return "stop_order"
	return "fine"


func _stable_variation(case_id: String, person_id: String, amplitude: float) -> float:
	var raw := float(_stable_int("%d|%s|%s" % [seed, case_id, person_id]) % 2001) / 1000.0 - 1.0
	return raw * amplitude


func _reset() -> void:
	current_year = 1
	committees.clear()
	members.clear()
	office_registry.clear()
	administrative_officials.clear()
	judicial_cases.clear()
	oversight_cases.clear()
	term_history.clear()
	next_judicial_sequence = 1
	next_oversight_sequence = 1
	_load_errors.clear()
	_terminal_failure_reason = ""


static func _sorted_keys(source: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in source.keys():
		result.append(str(key))
	result.sort()
	return result


static func _stable_int(value: String) -> int:
	var result := 23
	for index: int in value.length():
		result = int((result * 31 + value.unicode_at(index)) % 2_147_483_647)
	return result


func _terminal_error() -> Dictionary:
	return {
		"ok": false,
		"error": "game_already_failed",
		"failure_reason": _terminal_failure_reason,
	}


static func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: String in _sorted_keys(value):
			result[key] = _canonicalize(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_canonicalize(item))
		return result
	if value is float and is_equal_approx(float(value), roundf(float(value))):
		return int(roundf(float(value)))
	return value
