class_name LowerCouncilDatabase
extends RefCounted

const SCHEMA_VERSION := 1
const DEFAULT_DATA_PATH := "res://data/databases/governance/lower-council/councilors.json"
const VALID_GENDERS := ["女性", "男性", "非二元"]
const VALID_VOTE_CHOICES := ["for", "against", "abstain", "absent"]
const REQUIRED_BILL_IDS := [
	"environment_act",
	"transit_act",
	"commerce_act",
	"welfare_act",
	"security_act",
	"utility_relief_act",
	"industry_act",
	"social_housing_act",
]
const EXPECTED_CAUCUS_SEATS := {
	"財政與發展聯盟": 7,
	"社會民生聯盟": 7,
	"綠色未來聯盟": 6,
	"公民地方聯盟": 6,
	"無黨籍": 4,
}

var schema_version: int = SCHEMA_VERSION
var chamber_id: String = "lower_council"
var seat_count: int = 30
var majority_threshold: int = 16
var members: Dictionary = {}
var dynamic_states: Dictionary = {}
var vote_history: Array[Dictionary] = []
var _vote_ids: Dictionary = {}


func load_default() -> Dictionary:
	return load_from_path(DEFAULT_DATA_PATH)


func load_from_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "errors": ["找不到議員資料檔：%s" % path]}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "errors": ["無法開啟議員資料檔：%s" % path]}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {"ok": false, "errors": ["議員資料不是有效的 JSON 物件"]}
	return load_data(parsed)


func load_data(data: Dictionary) -> Dictionary:
	_reset()
	schema_version = int(data.get("schema_version", SCHEMA_VERSION))
	chamber_id = str(data.get("chamber_id", "lower_council"))
	seat_count = int(data.get("seat_count", 30))
	majority_threshold = int(data.get("majority_threshold", 16))
	for value: Variant in data.get("members", []):
		if not value is Dictionary:
			continue
		var member: Dictionary = value.duplicate(true)
		var member_id := str(member.get("member_id", ""))
		if member_id.is_empty() or members.has(member_id):
			continue
		members[member_id] = member
		dynamic_states[member_id] = _default_dynamic_state(member)
	_seed_vote_history()
	return validate()


func validate() -> Dictionary:
	var errors: Array[String] = []
	if schema_version != SCHEMA_VERSION:
		errors.append("不支援的 schema_version：%d" % schema_version)
	if chamber_id != "lower_council":
		errors.append("chamber_id 必須是 lower_council")
	if seat_count != 30:
		errors.append("下議會席次必須是 30，目前為 %d" % seat_count)
	if majority_threshold != 16:
		errors.append("30 席議會的固定過半門檻必須是 16")
	if members.size() != seat_count:
		errors.append("議員筆數 %d 與席次 %d 不一致" % [members.size(), seat_count])

	var names: Dictionary = {}
	var districts: Dictionary = {}
	var caucus_counts: Dictionary = {}
	for member_id: String in sorted_member_ids():
		var member: Dictionary = members[member_id]
		_validate_member(member_id, member, errors, names, districts, caucus_counts)

	for caucus: String in EXPECTED_CAUCUS_SEATS.keys():
		var actual := int(caucus_counts.get(caucus, 0))
		var expected := int(EXPECTED_CAUCUS_SEATS[caucus])
		if actual != expected:
			errors.append("黨團席次錯誤：%s 應為 %d，實際為 %d" % [caucus, expected, actual])

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"member_count": members.size(),
		"vote_history_count": vote_history.size(),
		"caucus_counts": caucus_counts,
	}


func get_member(member_id: String) -> Dictionary:
	if not members.has(member_id):
		return {}
	return (members[member_id] as Dictionary).duplicate(true)


func get_dynamic_state(member_id: String) -> Dictionary:
	if not dynamic_states.has(member_id):
		return {}
	return (dynamic_states[member_id] as Dictionary).duplicate(true)


func update_dynamic_state(member_id: String, changes: Dictionary) -> bool:
	if not dynamic_states.has(member_id):
		return false
	var state: Dictionary = dynamic_states[member_id]
	for key: Variant in changes.keys():
		match str(key):
			"mayor_relationship":
				state[key] = clampi(int(changes[key]), -100, 100)
			"district_support", "caucus_relationship", "integrity_risk", "fatigue":
				state[key] = clampi(int(changes[key]), 0, 100)
			"commitments":
				state[key] = (changes[key] as Array).duplicate(true) if changes[key] is Array else []
			"suspended":
				state[key] = bool(changes[key])
			_:
				continue
	dynamic_states[member_id] = state
	return true


func sorted_member_ids() -> Array[String]:
	var result: Array[String] = []
	for key: Variant in members.keys():
		result.append(str(key))
	result.sort()
	return result


func members_by_caucus(caucus: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for member_id: String in sorted_member_ids():
		var member: Dictionary = members[member_id]
		if str(member.get("caucus", "")) == caucus:
			result.append(member.duplicate(true))
	return result


func append_vote(record: Dictionary) -> bool:
	var vote_id := str(record.get("vote_id", ""))
	var member_id := str(record.get("member_id", ""))
	var bill_id := str(record.get("bill_id", ""))
	var choice := str(record.get("choice", ""))
	if vote_id.is_empty() or _vote_ids.has(vote_id):
		return false
	if not members.has(member_id) or bill_id.is_empty():
		return false
	if not VALID_VOTE_CHOICES.has(choice):
		return false
	if str(record.get("stage", "")).is_empty():
		return false
	var stored := record.duplicate(true)
	stored["schema_version"] = SCHEMA_VERSION
	vote_history.append(stored)
	_vote_ids[vote_id] = true
	return true


func vote_history_for_member(member_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in vote_history:
		if str(record.get("member_id", "")) == member_id:
			result.append(record.duplicate(true))
	return result


func vote_history_for_bill(bill_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in vote_history:
		if str(record.get("bill_id", "")) == bill_id:
			result.append(record.duplicate(true))
	return result


func to_dict() -> Dictionary:
	var member_data: Array[Dictionary] = []
	var state_data: Dictionary = {}
	for member_id: String in sorted_member_ids():
		member_data.append((members[member_id] as Dictionary).duplicate(true))
		state_data[member_id] = (dynamic_states[member_id] as Dictionary).duplicate(true)
	return {
		"schema_version": SCHEMA_VERSION,
		"chamber_id": chamber_id,
		"seat_count": seat_count,
		"majority_threshold": majority_threshold,
		"members": member_data,
		"dynamic_states": state_data,
		"vote_history": vote_history.duplicate(true),
	}


func load_state(data: Dictionary) -> Dictionary:
	var base_result := load_data(data)
	if not bool(base_result.get("ok", false)):
		return base_result
	var saved_states: Dictionary = data.get("dynamic_states", {})
	for member_id: String in sorted_member_ids():
		if saved_states.has(member_id) and saved_states[member_id] is Dictionary:
			dynamic_states[member_id] = (saved_states[member_id] as Dictionary).duplicate(true)
	if data.has("vote_history"):
		vote_history.clear()
		_vote_ids.clear()
		for value: Variant in data.get("vote_history", []):
			if value is Dictionary:
				append_vote(value)
	return validate()


func stable_hash() -> String:
	return JSON.stringify(_sorted_variant(to_dict())).sha256_text()


func _reset() -> void:
	members.clear()
	dynamic_states.clear()
	vote_history.clear()
	_vote_ids.clear()


func _seed_vote_history() -> void:
	for member_id: String in sorted_member_ids():
		var member: Dictionary = members[member_id]
		var seed_votes: Dictionary = member.get("seed_votes", {})
		for bill_id: String in REQUIRED_BILL_IDS:
			if not seed_votes.has(bill_id):
				continue
			append_vote({
				"vote_id": "seed_%s_%s" % [member_id, bill_id],
				"member_id": member_id,
				"bill_id": bill_id,
				"bill_version": 1,
				"game_day": -1,
				"stage": "historical_seed",
				"choice": str(seed_votes[bill_id]),
				"support_score": 50.0,
				"primary_reason": "seed_profile",
				"public_opinion_snapshot": 50,
				"budget_health_snapshot": 50,
				"caucus_recommendation": "neutral",
				"changed_vote": false,
			})


func _validate_member(
	member_id: String,
	member: Dictionary,
	errors: Array[String],
	names: Dictionary,
	districts: Dictionary,
	caucus_counts: Dictionary
) -> void:
	if not member_id.match("LC-???"):
		errors.append("議員 ID 格式錯誤：%s" % member_id)
	var display_name := str(member.get("name", ""))
	if display_name.is_empty() or names.has(display_name):
		errors.append("議員姓名空白或重複：%s" % display_name)
	names[display_name] = true
	var district := str(member.get("district", ""))
	if district.is_empty() or districts.has(district):
		errors.append("議員選區空白或重複：%s" % district)
	districts[district] = true
	if not VALID_GENDERS.has(str(member.get("gender", ""))):
		errors.append("%s 的性別值無效" % member_id)
	if int(member.get("age", 0)) < 18:
		errors.append("%s 的年齡無效" % member_id)
	var tags: Array = member.get("personality_tags", [])
	if tags.size() != 3:
		errors.append("%s 必須有三個性格標籤" % member_id)
	var concerns: Array = member.get("concerns", [])
	var weight_total := 0
	var concern_keys: Dictionary = {}
	if concerns.size() != 3:
		errors.append("%s 必須有三項主要關注點" % member_id)
	for value: Variant in concerns:
		if not value is Dictionary:
			continue
		var concern: Dictionary = value
		var concern_key := str(concern.get("key", ""))
		if concern_key.is_empty() or concern_keys.has(concern_key):
			errors.append("%s 的關注點 key 空白或重複" % member_id)
		concern_keys[concern_key] = true
		weight_total += int(concern.get("weight", 0))
	if weight_total != 100:
		errors.append("%s 的關注點權重合計為 %d，不是 100" % [member_id, weight_total])
	var behavior: Dictionary = member.get("behavior", {})
	for key: String in ["public_sensitivity", "persuasion_resistance", "caucus_discipline", "risk_tolerance"]:
		var value := int(behavior.get(key, -1))
		if value < 0 or value > 100:
			errors.append("%s 的 %s 超出 0 至 100" % [member_id, key])
	var seed_votes: Dictionary = member.get("seed_votes", {})
	for bill_id: String in REQUIRED_BILL_IDS:
		if not seed_votes.has(bill_id) or not VALID_VOTE_CHOICES.has(str(seed_votes.get(bill_id, ""))):
			errors.append("%s 缺少有效的 %s 歷史投票" % [member_id, bill_id])
	var caucus := str(member.get("caucus", ""))
	caucus_counts[caucus] = int(caucus_counts.get(caucus, 0)) + 1


func _default_dynamic_state(member: Dictionary) -> Dictionary:
	var caucus := str(member.get("caucus", ""))
	return {
		"mayor_relationship": 0,
		"district_support": 50,
		"caucus_relationship": 50 if caucus == "無黨籍" else 70,
		"integrity_risk": 0,
		"fatigue": 0,
		"commitments": [],
		"suspended": false,
	}


static func _sorted_variant(value: Variant) -> Variant:
	if value is Dictionary:
		var source: Dictionary = value
		var result: Dictionary = {}
		var keys: Array[String] = []
		for key: Variant in source.keys():
			keys.append(str(key))
		keys.sort()
		for key: String in keys:
			result[key] = _sorted_variant(source[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_sorted_variant(item))
		return result
	if value is float and is_equal_approx(float(value), roundf(float(value))):
		return int(roundf(float(value)))
	return value
