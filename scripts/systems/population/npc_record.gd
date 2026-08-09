class_name MayorNpcRecord
extends RefCounted

## Persistent, JSON-safe data for one simulated resident.
## Relationships are sparse: only residents with an actual connection are stored.

const SaveSchemaAuthorityScript = preload("res://scripts/core/save_schema_authority.gd")

const SCHEMA_VERSION := SaveSchemaAuthorityScript.NPC_RECORD_CURRENT_SCHEMA_VERSION
const MIN_SUPPORTED_SCHEMA_VERSION := SaveSchemaAuthorityScript.NPC_RECORD_MIN_SUPPORTED_SCHEMA_VERSION
const MAX_SUPPORTED_SCHEMA_VERSION := SaveSchemaAuthorityScript.NPC_RECORD_MAX_SUPPORTED_SCHEMA_VERSION

var npc_id: String = ""
var display_name: String = ""
var age: int = 18
var gender: String = "未指定"
var personality: String = "穩健"
var personality_tags: PackedStringArray = PackedStringArray()
var appearance_tags: PackedStringArray = PackedStringArray()
var preferences: PackedStringArray = PackedStringArray()
var education: String = "高中"
var income: int = 0
var salary: Variant = null
var debt: Variant = null
var address_id: String = ""
var job_id: String = ""
var employment_state: String = "待業"
var policy_attitudes: Dictionary = {}
var relationships: Dictionary = {}


func add_relationship(other_npc_id: String, relationship_type: String, affinity: int) -> void:
	if other_npc_id.is_empty() or other_npc_id == npc_id:
		return
	relationships[other_npc_id] = {
		"type": relationship_type,
		"affinity": clampi(affinity, -100, 100),
	}


func remove_relationship(other_npc_id: String) -> void:
	relationships.erase(other_npc_id)


func get_base_attitude(policy_id: String) -> int:
	return clampi(int(policy_attitudes.get(policy_id, 0)), -100, 100)


func set_base_attitude(policy_id: String, value: int) -> void:
	policy_attitudes[policy_id] = clampi(value, -100, 100)


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"npc_id": npc_id,
		"display_name": display_name,
		"age": age,
		"gender": gender,
		"personality": personality,
		"personality_tags": Array(personality_tags),
		"appearance_tags": Array(appearance_tags),
		"preferences": Array(preferences),
		"education": education,
		"income": income,
		"salary": salary,
		"debt": debt,
		"address_id": address_id,
		"job_id": job_id,
		"employment_state": employment_state,
		"policy_attitudes": _sorted_dictionary(policy_attitudes),
		"relationships": _sorted_relationships(),
	}


static func from_dict(data: Dictionary):
	if not validate_dict(data):
		return null
	var record = new()
	record.npc_id = str(data.get("npc_id", ""))
	record.display_name = str(data.get("display_name", ""))
	record.age = maxi(0, int(data.get("age", 18)))
	record.gender = str(data.get("gender", "未指定"))
	record.personality = str(data.get("personality", "穩健"))
	record.personality_tags = PackedStringArray(data.get("personality_tags", []))
	record.appearance_tags = PackedStringArray(data.get("appearance_tags", []))
	var preference_values: Array = data.get("preferences", [])
	record.preferences = PackedStringArray(preference_values)
	record.education = str(data.get("education", "高中"))
	record.income = maxi(0, int(data.get("income", 0)))
	var salary_value: Variant = data.get("salary", null)
	record.salary = maxi(0, int(salary_value)) if salary_value != null else null
	var debt_value: Variant = data.get("debt", null)
	record.debt = maxi(0, int(debt_value)) if debt_value != null else null
	record.address_id = str(data.get("address_id", ""))
	record.job_id = str(data.get("job_id", ""))
	record.employment_state = str(data.get("employment_state", "待業"))
	var attitudes: Dictionary = data.get("policy_attitudes", {})
	for key: Variant in attitudes.keys():
		record.policy_attitudes[str(key)] = clampi(int(attitudes[key]), -100, 100)
	var relation_data: Dictionary = data.get("relationships", {})
	for key: Variant in relation_data.keys():
		var relationship: Dictionary = relation_data[key]
		record.add_relationship(
			str(key),
			str(relationship.get("type", "認識")),
			int(relationship.get("affinity", 0))
		)
	return record


static func validate_dict(data: Dictionary) -> bool:
	var schema_value: Variant = data.get("schema_version", null)
	if not _is_integer_value(schema_value):
		return false
	var schema_version := int(schema_value)
	if schema_version < MIN_SUPPORTED_SCHEMA_VERSION or schema_version > MAX_SUPPORTED_SCHEMA_VERSION:
		return false
	var expected_keys := [
		"schema_version", "npc_id", "display_name", "age", "gender",
		"personality", "preferences", "education", "income", "address_id",
		"job_id", "employment_state", "policy_attitudes", "relationships",
	]
	if schema_version >= 2:
		expected_keys.append_array(["personality_tags", "appearance_tags", "salary", "debt"])
	if not _has_exact_keys(data, expected_keys):
		return false
	for string_field: String in [
		"npc_id", "display_name", "gender", "personality", "education",
		"address_id", "job_id", "employment_state",
	]:
		if not data[string_field] is String:
			return false
	if str(data["npc_id"]).is_empty() or str(data["display_name"]).is_empty():
		return false
	if not _is_integer_value(data["age"]) or int(data["age"]) < 0:
		return false
	if not _is_integer_value(data["income"]) or int(data["income"]) < 0:
		return false
	if not _is_string_array(data["preferences"]):
		return false
	if schema_version >= 2:
		if not _is_string_array(data["personality_tags"]) or not _is_string_array(data["appearance_tags"]):
			return false
		for nullable_money_field: String in ["salary", "debt"]:
			var money_value: Variant = data[nullable_money_field]
			if money_value != null and (not _is_integer_value(money_value) or int(money_value) < 0):
				return false
	var attitudes_value: Variant = data["policy_attitudes"]
	if not attitudes_value is Dictionary:
		return false
	for policy_id: Variant in (attitudes_value as Dictionary).keys():
		var attitude: Variant = (attitudes_value as Dictionary)[policy_id]
		if str(policy_id).is_empty() or not _is_integer_value(attitude) or int(attitude) < -100 or int(attitude) > 100:
			return false
	var relationships_value: Variant = data["relationships"]
	if not relationships_value is Dictionary:
		return false
	for other_id_value: Variant in (relationships_value as Dictionary).keys():
		var other_id := str(other_id_value)
		var relationship_value: Variant = (relationships_value as Dictionary)[other_id_value]
		if other_id.is_empty() or other_id == str(data["npc_id"]) or not relationship_value is Dictionary:
			return false
		var relationship: Dictionary = relationship_value
		if not _has_exact_keys(relationship, ["type", "affinity"]):
			return false
		if not relationship["type"] is String or str(relationship["type"]).is_empty():
			return false
		if not _is_integer_value(relationship["affinity"]) or int(relationship["affinity"]) < -100 or int(relationship["affinity"]) > 100:
			return false
	return true


func _sorted_relationships() -> Dictionary:
	var result := {}
	var keys: Array = relationships.keys()
	keys.sort()
	for key: Variant in keys:
		var relationship: Dictionary = relationships[key]
		result[str(key)] = {
			"type": str(relationship.get("type", "認識")),
			"affinity": clampi(int(relationship.get("affinity", 0)), -100, 100),
		}
	return result


static func _sorted_dictionary(source: Dictionary) -> Dictionary:
	var result := {}
	var keys: Array = source.keys()
	keys.sort()
	for key: Variant in keys:
		result[str(key)] = source[key]
	return result


static func _is_integer_value(value: Variant) -> bool:
	return value is int or (value is float and is_finite(float(value)) and float(value) == roundf(float(value)))


static func _is_string_array(value: Variant) -> bool:
	if not value is Array:
		return false
	for item: Variant in value:
		if not item is String:
			return false
	return true


static func _has_exact_keys(value: Dictionary, expected_keys: Array) -> bool:
	if value.size() != expected_keys.size():
		return false
	for key: Variant in expected_keys:
		if not value.has(key):
			return false
	return true
