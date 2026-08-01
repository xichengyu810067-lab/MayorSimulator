extends RefCounted

const CURRENT_SCHEMA_VERSION := 1
const MIN_SUPPORTED_SCHEMA_VERSION := 1

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
	var migrated := migrate_dict(data)
	if migrated.is_empty():
		return null
	var state_value: Variant = migrated.get("state", {})
	var kernel_value: Variant = migrated.get("kernel", {})
	var clock_value: Variant = migrated.get("clock", {})
	if not state_value is Dictionary or not kernel_value is Dictionary or not clock_value is Dictionary:
		return null
	for field_name: String in ["rng_seed", "rng_state", "game_time", "event_sequence", "command_sequence"]:
		if not _is_integer_value(migrated.get(field_name, 0)):
			return null
	var envelope = new()
	envelope.schema_version = int(migrated.get("schema_version", CURRENT_SCHEMA_VERSION))
	envelope.content_version = str(migrated.get("content_version", "vertical_slice_1"))
	envelope.rng_seed = int(str(migrated.get("rng_seed", "0")))
	envelope.rng_state = int(str(migrated.get("rng_state", "0")))
	envelope.game_time = int(migrated.get("game_time", 0))
	envelope.event_sequence = int(migrated.get("event_sequence", 0))
	envelope.command_sequence = int(migrated.get("command_sequence", 0))
	if envelope.content_version.is_empty() or envelope.game_time < 0 or envelope.event_sequence < 0 or envelope.command_sequence < 0:
		return null
	envelope.state = (state_value as Dictionary).duplicate(true)
	envelope.kernel = (kernel_value as Dictionary).duplicate(true)
	envelope.clock = (clock_value as Dictionary).duplicate(true)
	return envelope


static func migrate_dict(data: Dictionary) -> Dictionary:
	if not _is_integer_value(data.get("schema_version", -1)):
		return {}
	var source_version := int(data.get("schema_version", -1))
	if source_version < MIN_SUPPORTED_SCHEMA_VERSION or source_version > CURRENT_SCHEMA_VERSION:
		return {}
	# Version 1 is currently the only persisted envelope shape. Keeping migration
	# behind this explicit boundary prevents a future schema from being accepted
	# accidentally through permissive Dictionary defaults.
	return data.duplicate(true)


static func _is_integer_value(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		return is_finite(float(value)) and is_equal_approx(float(value), roundf(float(value)))
	if value is String:
		return (value as String).is_valid_int()
	return false
