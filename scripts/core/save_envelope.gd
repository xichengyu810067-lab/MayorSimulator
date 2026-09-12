extends RefCounted

const SaveSchemaAuthorityScript = preload("res://scripts/core/save_schema_authority.gd")

const CURRENT_SCHEMA_VERSION := SaveSchemaAuthorityScript.SAVE_ENVELOPE_CURRENT_SCHEMA_VERSION
const MIN_SUPPORTED_SCHEMA_VERSION := SaveSchemaAuthorityScript.SAVE_ENVELOPE_MIN_SUPPORTED_SCHEMA_VERSION
const MAX_SUPPORTED_SCHEMA_VERSION := SaveSchemaAuthorityScript.SAVE_ENVELOPE_MAX_SUPPORTED_SCHEMA_VERSION

# These hard limits bound untrusted save input before any migration or deep
# copy. The 512 MiB file ceiling matches the existing 200k-capacity evidence
# line (the measured production save is about 170 MiB). A string receives twice
# the existing 8 MiB memory-pipeline fixture, request history receives five
# entries per maximum resident, transaction/event history receives ten, and the
# total item ceiling receives sixty. Writer-owned 24/200/100 report histories
# retain their existing exact caps.
const MAX_SAVE_FILE_BYTES := 512 * 1024 * 1024
const MAX_JSON_NESTING_DEPTH := 64
const MAX_STRING_BYTES := 16 * 1024 * 1024
const MAX_TOTAL_CONTAINER_ITEMS := 12_000_000
const MAX_ITEMS_PER_CONTAINER := 2_000_000
const MAX_POPULATION_RECORDS := 200_000
const MAX_REQUESTS := 1_000_000
const MAX_TRANSACTIONS := 2_000_000
const MAX_EVENTS := 2_000_000
const MAX_MONTHLY_REPORT_HISTORY := 24
const MAX_MAJOR_EVENT_HISTORY := 200
const MAX_CHECKS_AND_BALANCES_HISTORY := 100

var schema_version: int = CURRENT_SCHEMA_VERSION
var content_version: String = "vertical_slice_1"
var rng_seed: int = 0
var rng_state: int = 0
var game_time: int = 0
var event_sequence: int = 0
var command_sequence: int = 0
var state: Dictionary = {}
var kernel: Dictionary = {}
var clock: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"content_version": content_version,
		# RNG values are strings to preserve all 64 bits through JSON readers.
		"rng_seed": str(rng_seed),
		"rng_state": str(rng_state),
		"game_time": game_time,
		"event_sequence": event_sequence,
		"command_sequence": command_sequence,
		"state": state.duplicate(true),
		"kernel": kernel.duplicate(true),
		"clock": clock.duplicate(true),
	}


static func from_dict(data: Dictionary):
	var result := from_untrusted_dict_report(data)
	return result.get("envelope", null) if bool(result.get("ok", false)) else null


static func from_untrusted_dict_report(data: Dictionary) -> Dictionary:
	var validation := validate_untrusted_dict(data)
	if not bool(validation.get("ok", false)):
		return validation
	var migrated := _migrate_validated_dict(data)
	if migrated.is_empty():
		return {"ok": false, "error": "Save envelope schema version is unsupported."}
	var state_value: Variant = migrated.get("state", {})
	var kernel_value: Variant = migrated.get("kernel", {})
	var clock_value: Variant = migrated.get("clock", {})
	if not state_value is Dictionary or not kernel_value is Dictionary or not clock_value is Dictionary:
		return {"ok": false, "error": "Save envelope state, kernel, and clock must be dictionaries."}
	for field_name: String in ["rng_seed", "rng_state", "game_time", "event_sequence", "command_sequence"]:
		if not _is_integer_value(migrated.get(field_name, 0)):
			return {"ok": false, "error": "Save envelope field '%s' must be an integer." % field_name}
	var envelope = new()
	envelope.schema_version = int(migrated.get("schema_version", CURRENT_SCHEMA_VERSION))
	envelope.content_version = str(migrated.get("content_version", "vertical_slice_1"))
	envelope.rng_seed = int(str(migrated.get("rng_seed", "0")))
	envelope.rng_state = int(str(migrated.get("rng_state", "0")))
	envelope.game_time = int(migrated.get("game_time", 0))
	envelope.event_sequence = int(migrated.get("event_sequence", 0))
	envelope.command_sequence = int(migrated.get("command_sequence", 0))
	if envelope.content_version.is_empty() or envelope.game_time < 0 or envelope.event_sequence < 0 or envelope.command_sequence < 0:
		return {"ok": false, "error": "Save envelope counters and content version are invalid."}
	envelope.state = (state_value as Dictionary).duplicate(true)
	envelope.kernel = (kernel_value as Dictionary).duplicate(true)
	envelope.clock = (clock_value as Dictionary).duplicate(true)
	return {"ok": true, "error": "", "envelope": envelope}


static func migrate_dict(data: Dictionary) -> Dictionary:
	var validation := validate_untrusted_dict(data)
	if not bool(validation.get("ok", false)):
		return {}
	return _migrate_validated_dict(data)


static func _migrate_validated_dict(data: Dictionary) -> Dictionary:
	if not _is_integer_value(data.get("schema_version", -1)):
		return {}
	var source_version := int(data.get("schema_version", -1))
	if source_version < MIN_SUPPORTED_SCHEMA_VERSION or source_version > MAX_SUPPORTED_SCHEMA_VERSION:
		return {}
	# Version 1 is currently the only persisted envelope shape. Keeping migration
	# behind this explicit boundary prevents a future schema from being accepted
	# accidentally through permissive Dictionary defaults.
	return data.duplicate(true)


static func validate_untrusted_dict(data: Dictionary) -> Dictionary:
	return _validate_untrusted_dict_with_limits(data, {})


static func validate_untrusted_dict_with_lower_limits_for_testing(data: Dictionary, lower_limits: Dictionary) -> Dictionary:
	# Tests may exercise exact boundaries with small fixtures, but this entrypoint
	# can only tighten production ceilings. It cannot make runtime input more
	# permissive even if product code calls it accidentally.
	return _validate_untrusted_dict_with_limits(data, lower_limits)


static func _validate_untrusted_dict_with_limits(data: Dictionary, lower_limits: Dictionary) -> Dictionary:
	for field_name: String in ["schema_version", "game_time", "event_sequence", "command_sequence"]:
		if not data.has(field_name):
			continue
		var value: Variant = data[field_name]
		if not _is_integer_value(value):
			return {"ok": false, "error": "Save envelope field '%s' must be a finite integer." % field_name}
		if field_name != "schema_version" and int(value) < 0:
			return {"ok": false, "error": "Save envelope field '%s' must not be negative." % field_name}
	for field_name: String in ["rng_seed", "rng_state"]:
		if data.has(field_name) and not _is_integer_value(data[field_name]):
			return {"ok": false, "error": "Save envelope field '%s' must be an integer." % field_name}
	return _validate_bounded_tree(data, lower_limits)


static func _validate_bounded_tree(root: Variant, lower_limits: Dictionary = {}) -> Dictionary:
	var max_depth := _lower_limit(lower_limits, "max_json_nesting_depth", MAX_JSON_NESTING_DEPTH)
	var max_total_items := _lower_limit(lower_limits, "max_total_container_items", MAX_TOTAL_CONTAINER_ITEMS)
	var max_container_items := _lower_limit(lower_limits, "max_items_per_container", MAX_ITEMS_PER_CONTAINER)
	var max_string_bytes := _lower_limit(lower_limits, "max_string_bytes", MAX_STRING_BYTES)
	var stack: Array[Dictionary] = [{"value": root, "depth": 1, "entered": false}]
	var total_items := 0
	while not stack.is_empty():
		var frame: Dictionary = stack[stack.size() - 1]
		var depth := int(frame["depth"])
		if depth > max_depth:
			return {"ok": false, "error": "Save payload nesting exceeds %d levels." % max_depth}
		if not bool(frame["entered"]):
			var value: Variant = frame["value"]
			if value is Dictionary:
				var dictionary: Dictionary = value
				var size_error := _validate_container_size(dictionary.size(), max_container_items)
				if not size_error.is_empty():
					return {"ok": false, "error": size_error}
				total_items += dictionary.size()
				if total_items > max_total_items:
					return {"ok": false, "error": "Save payload contains more than %d container items." % max_total_items}
				frame["entered"] = true
				frame["kind"] = "dictionary"
				frame["keys"] = dictionary.keys()
				frame["index"] = 0
				continue
			if value is Array:
				var array: Array = value
				var size_error := _validate_container_size(array.size(), max_container_items)
				if not size_error.is_empty():
					return {"ok": false, "error": size_error}
				total_items += array.size()
				if total_items > max_total_items:
					return {"ok": false, "error": "Save payload contains more than %d container items." % max_total_items}
				frame["entered"] = true
				frame["kind"] = "array"
				frame["index"] = 0
				continue
			var scalar_error := _validate_scalar(value, max_string_bytes)
			if not scalar_error.is_empty():
				return {"ok": false, "error": scalar_error}
			stack.pop_back()
			continue
		if str(frame["kind"]) == "dictionary":
			var dictionary: Dictionary = frame["value"]
			var keys: Array = frame["keys"]
			var index := int(frame["index"])
			if index >= keys.size():
				stack.pop_back()
				continue
			var key: Variant = keys[index]
			frame["index"] = index + 1
			var key_name := str(key)
			var key_error := _validate_string(key_name, max_string_bytes)
			if not key_error.is_empty():
				return {"ok": false, "error": "Save dictionary key %s" % key_error}
			var child: Variant = dictionary[key]
			var collection_error := _validate_named_collection_size(key_name, child, lower_limits)
			if not collection_error.is_empty():
				return {"ok": false, "error": collection_error}
			if child is Dictionary or child is Array:
				stack.append({"value": child, "depth": depth + 1, "entered": false})
			else:
				var scalar_error := _validate_scalar(child, max_string_bytes)
				if not scalar_error.is_empty():
					return {"ok": false, "error": scalar_error}
		else:
			var array: Array = frame["value"]
			var index := int(frame["index"])
			if index >= array.size():
				stack.pop_back()
				continue
			frame["index"] = index + 1
			var child: Variant = array[index]
			if child is Dictionary or child is Array:
				stack.append({"value": child, "depth": depth + 1, "entered": false})
			else:
				var scalar_error := _validate_scalar(child, max_string_bytes)
				if not scalar_error.is_empty():
					return {"ok": false, "error": scalar_error}
	return {"ok": true, "error": ""}


static func _validate_container_size(size: int, limit: int) -> String:
	if size > limit:
		return "Save payload container has %d items; limit is %d." % [size, limit]
	return ""


static func _validate_named_collection_size(key: String, collection: Variant, lower_limits: Dictionary = {}) -> String:
	if not collection is Array and not collection is Dictionary:
		return ""
	var limit := -1
	match key:
		"records":
			limit = _lower_limit(lower_limits, "max_population_records", MAX_POPULATION_RECORDS)
		"requests":
			limit = _lower_limit(lower_limits, "max_requests", MAX_REQUESTS)
		"income_transactions", "transactions", "entries":
			limit = _lower_limit(lower_limits, "max_transactions", MAX_TRANSACTIONS)
		"events", "event_book":
			limit = _lower_limit(lower_limits, "max_events", MAX_EVENTS)
		"monthly_report_history":
			limit = _lower_limit(lower_limits, "max_monthly_report_history", MAX_MONTHLY_REPORT_HISTORY)
		"major_event_history":
			limit = _lower_limit(lower_limits, "max_major_event_history", MAX_MAJOR_EVENT_HISTORY)
		"checks_and_balances_history":
			limit = _lower_limit(lower_limits, "max_checks_and_balances_history", MAX_CHECKS_AND_BALANCES_HISTORY)
	if limit >= 0:
		var collection_size: int = collection.size()
		if collection_size > limit:
			return "Save collection '%s' has %d items; limit is %d." % [key, collection_size, limit]
	return ""


static func _validate_scalar(value: Variant, max_string_bytes: int = MAX_STRING_BYTES) -> String:
	if value == null or value is bool or value is int:
		return ""
	if value is float:
		return "" if is_finite(float(value)) else "Save payload contains a non-finite number."
	if value is String:
		return _validate_string(value as String, max_string_bytes)
	return "Save payload contains a non-JSON value of type %s." % type_string(typeof(value))


static func _validate_string(value: String, limit: int = MAX_STRING_BYTES) -> String:
	var character_count := value.length()
	if character_count > limit:
		return "string exceeds %d UTF-8 bytes." % limit
	# A Unicode scalar uses at most four UTF-8 bytes. Normal product strings avoid
	# an allocation here; only unusually large strings need an exact byte count.
	if character_count > int(limit / 4) and value.to_utf8_buffer().size() > limit:
		return "string exceeds %d UTF-8 bytes." % limit
	return ""


static func _lower_limit(lower_limits: Dictionary, key: String, production_limit: int) -> int:
	if not lower_limits.has(key):
		return production_limit
	return mini(production_limit, maxi(0, int(lower_limits[key])))


static func _is_integer_value(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		return is_finite(float(value)) and is_equal_approx(float(value), roundf(float(value)))
	if value is String:
		return (value as String).is_valid_int()
	return false
