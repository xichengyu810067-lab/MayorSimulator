class_name OnboardingProgress
extends RefCounted

const SHELL_SCHEMA_VERSION := 9
const SNAPSHOT_SCHEMA_VERSION := 2
const MIN_SNAPSHOT_SCHEMA_VERSION := 1
const MAX_RECEIPTS := 9
const MAX_GAME_DAY := 100_000_000
const MAX_SCHEDULE_GAME_DAY := 2_000_000_000
const STAGE_DELAY_DAYS := 3
const UNSCHEDULED_GAME_DAY := -1
const MAX_ID_LENGTH := 96
const PHASE_STORY := "story"
const PHASE_ACTIVE := "active"
const PHASE_COMPLETED := "completed"
const PHASE_LOCKED := "locked"
const COMPLETION_BASIS_RECEIPTS := "receipts"
const COMPLETION_BASIS_LEGACY := "legacy_schema8"
const ORDERED_TARGETS: Array[String] = [
	"build",
	"blueprint",
	"route",
	"fiscal",
	"city_data",
	"public_affairs",
	"governance",
	"judicial",
	"oversight",
]
const SNAPSHOT_V1_KEYS := ["schema_version", "phase", "next_index", "current_target", "completion_basis", "receipts"]
const SNAPSHOT_V2_KEYS := ["schema_version", "phase", "next_index", "current_target", "completion_basis", "receipts", "due_game_day"]
const RECEIPT_KEYS := ["kind", "authority_id", "entity_id", "game_day"]

var _phase := PHASE_STORY
var _next_index := 0
var _completion_basis := ""
var _receipts: Array[Dictionary] = []
var _due_game_day := UNSCHEDULED_GAME_DAY
var _lock_reason := ""


func reset_for_new_game() -> void:
	_phase = PHASE_STORY
	_next_index = 0
	_completion_basis = ""
	_receipts.clear()
	_due_game_day = UNSCHEDULED_GAME_DAY
	_lock_reason = ""


func begin_guide() -> bool:
	if _phase != PHASE_STORY:
		return false
	_phase = PHASE_ACTIVE
	return true


func record_current_target(target_id: String, receipt: Dictionary) -> bool:
	if _phase != PHASE_ACTIVE or target_id != current_target():
		return false
	var normalized := _validate_receipt(receipt, target_id)
	if not bool(normalized.get("ok", false)):
		return false
	var receipt_day := int(Dictionary(normalized["receipt"])["game_day"])
	if is_waiting(receipt_day):
		return false
	if _receipts.size() >= MAX_RECEIPTS:
		return false
	_receipts.append(Dictionary(normalized["receipt"]).duplicate(true))
	_next_index += 1
	if _next_index >= ORDERED_TARGETS.size():
		_phase = PHASE_COMPLETED
		_completion_basis = COMPLETION_BASIS_RECEIPTS
		_due_game_day = UNSCHEDULED_GAME_DAY
	else:
		_due_game_day = receipt_day + STAGE_DELAY_DAYS
	return true


func defer_current_target(current_game_day: int) -> bool:
	if _phase != PHASE_ACTIVE or current_game_day < 0 or current_game_day > MAX_SCHEDULE_GAME_DAY:
		return false
	var schedule_base := maxi(current_game_day, _due_game_day)
	if schedule_base > MAX_SCHEDULE_GAME_DAY - STAGE_DELAY_DAYS:
		return false
	_due_game_day = schedule_base + STAGE_DELAY_DAYS
	return true


func restore_from_shell_state(shell_state: Dictionary) -> Dictionary:
	var shell_schema_result := _bounded_integer(shell_state.get("schema_version", 0), 0, SHELL_SCHEMA_VERSION + 1)
	if not bool(shell_schema_result.get("ok", false)):
		return _lock("invalid_shell_schema")
	var shell_schema := int(shell_schema_result["value"])
	if shell_schema > SHELL_SCHEMA_VERSION:
		return _lock("future_shell_schema")
	if shell_schema <= 8:
		reset_for_new_game()
		if bool(shell_state.get("tutorial_completed", false)):
			_phase = PHASE_COMPLETED
			_next_index = ORDERED_TARGETS.size()
			_completion_basis = COMPLETION_BASIS_LEGACY
		return {"ok": true, "source_schema": shell_schema, "migration": "schema8_compatibility"}
	if not shell_state.has("onboarding") or not (shell_state["onboarding"] is Dictionary):
		return _lock("missing_onboarding_snapshot")
	var validation := _validate_snapshot(shell_state["onboarding"] as Dictionary)
	if not bool(validation.get("ok", false)):
		return _lock(str(validation.get("error", "invalid_onboarding_snapshot")))
	var normalized: Dictionary = validation["snapshot"]
	_phase = str(normalized["phase"])
	_next_index = int(normalized["next_index"])
	_completion_basis = str(normalized["completion_basis"])
	_due_game_day = int(normalized["due_game_day"])
	_receipts.clear()
	for receipt_variant: Variant in normalized["receipts"]:
		_receipts.append(Dictionary(receipt_variant).duplicate(true))
	_lock_reason = ""
	return {
		"ok": true,
		"source_schema": shell_schema,
		"migration": "onboarding_snapshot_v1_to_v2" if int(validation["source_schema"]) == 1 else "none",
	}


func snapshot() -> Dictionary:
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"phase": _phase,
		"next_index": _next_index,
		"current_target": current_target(),
		"completion_basis": _completion_basis,
		"receipts": receipts(),
		"due_game_day": _due_game_day,
	}


func receipts() -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	for receipt in _receipts:
		copy.append(receipt.duplicate(true))
	return copy


func current_target() -> String:
	if _phase == PHASE_ACTIVE and _next_index >= 0 and _next_index < ORDERED_TARGETS.size():
		return ORDERED_TARGETS[_next_index]
	return ""


func next_index() -> int:
	return _next_index


func due_game_day() -> int:
	return _due_game_day


func is_waiting(current_game_day: int) -> bool:
	return _phase == PHASE_ACTIVE and _due_game_day >= 0 and current_game_day < _due_game_day


func is_current_target_available(current_game_day: int) -> bool:
	return _phase == PHASE_ACTIVE and not is_waiting(current_game_day)


func phase() -> String:
	return _phase


func lock_reason() -> String:
	return _lock_reason


func is_story_pending() -> bool:
	return _phase == PHASE_STORY


func is_active() -> bool:
	return _phase == PHASE_ACTIVE


func is_completed() -> bool:
	return _phase == PHASE_COMPLETED


func is_locked() -> bool:
	return _phase == PHASE_LOCKED


func _validate_snapshot(value: Dictionary) -> Dictionary:
	if not value.has("schema_version"):
		return {"ok": false, "error": "onboarding_snapshot_keys"}
	var schema_result := _bounded_integer(value["schema_version"], MIN_SNAPSHOT_SCHEMA_VERSION, SNAPSHOT_SCHEMA_VERSION)
	if not bool(schema_result.get("ok", false)):
		return {"ok": false, "error": "onboarding_snapshot_schema"}
	var source_schema := int(schema_result["value"])
	var expected_keys := SNAPSHOT_V1_KEYS if source_schema == 1 else SNAPSHOT_V2_KEYS
	if not _has_exact_keys(value, expected_keys):
		return {"ok": false, "error": "onboarding_snapshot_keys"}
	if not (value["phase"] is String) or not (value["current_target"] is String) or not (value["completion_basis"] is String):
		return {"ok": false, "error": "onboarding_snapshot_types"}
	if not (value["receipts"] is Array):
		return {"ok": false, "error": "onboarding_receipts_type"}
	var index_result := _bounded_integer(value["next_index"], 0, ORDERED_TARGETS.size())
	if not bool(index_result.get("ok", false)):
		return {"ok": false, "error": "onboarding_next_index"}
	var phase_value := str(value["phase"])
	var next_value := int(index_result["value"])
	var target_value := str(value["current_target"])
	var basis_value := str(value["completion_basis"])
	var due_result := _bounded_integer(value.get("due_game_day", UNSCHEDULED_GAME_DAY), UNSCHEDULED_GAME_DAY, MAX_SCHEDULE_GAME_DAY)
	if not bool(due_result.get("ok", false)):
		return {"ok": false, "error": "onboarding_due_game_day"}
	var due_value := int(due_result["value"])
	var raw_receipts: Array = value["receipts"]
	if raw_receipts.size() > MAX_RECEIPTS:
		return {"ok": false, "error": "onboarding_receipts_bounded"}
	var normalized_receipts: Array[Dictionary] = []
	for receipt_index in raw_receipts.size():
		if not (raw_receipts[receipt_index] is Dictionary) or receipt_index >= ORDERED_TARGETS.size():
			return {"ok": false, "error": "onboarding_receipt_type"}
		var receipt_result := _validate_receipt(raw_receipts[receipt_index] as Dictionary, ORDERED_TARGETS[receipt_index])
		if not bool(receipt_result.get("ok", false)):
			return {"ok": false, "error": str(receipt_result.get("error", "onboarding_receipt_invalid"))}
		normalized_receipts.append(Dictionary(receipt_result["receipt"]).duplicate(true))
	match phase_value:
		PHASE_STORY:
			if next_value != 0 or target_value != "" or basis_value != "" or not normalized_receipts.is_empty() or due_value != UNSCHEDULED_GAME_DAY:
				return {"ok": false, "error": "onboarding_story_order"}
		PHASE_ACTIVE:
			if next_value >= ORDERED_TARGETS.size() or target_value != ORDERED_TARGETS[next_value] or basis_value != "" or normalized_receipts.size() != next_value:
				return {"ok": false, "error": "onboarding_active_order"}
		PHASE_COMPLETED:
			if next_value != ORDERED_TARGETS.size() or target_value != "" or due_value != UNSCHEDULED_GAME_DAY:
				return {"ok": false, "error": "onboarding_completed_order"}
			if basis_value == COMPLETION_BASIS_RECEIPTS and normalized_receipts.size() != ORDERED_TARGETS.size():
				return {"ok": false, "error": "onboarding_completed_receipts"}
			if basis_value == COMPLETION_BASIS_LEGACY and not normalized_receipts.is_empty():
				return {"ok": false, "error": "onboarding_legacy_receipts"}
			if basis_value not in [COMPLETION_BASIS_RECEIPTS, COMPLETION_BASIS_LEGACY]:
				return {"ok": false, "error": "onboarding_completion_basis"}
		_:
			return {"ok": false, "error": "onboarding_unknown_phase"}
	return {"ok": true, "source_schema": source_schema, "snapshot": {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"phase": phase_value,
		"next_index": next_value,
		"current_target": target_value,
		"completion_basis": basis_value,
		"receipts": normalized_receipts,
		"due_game_day": due_value,
	}}


func _validate_receipt(value: Dictionary, expected_kind: String) -> Dictionary:
	if not _has_exact_keys(value, RECEIPT_KEYS):
		return {"ok": false, "error": "onboarding_receipt_keys"}
	if not (value["kind"] is String) or str(value["kind"]) != expected_kind:
		return {"ok": false, "error": "onboarding_receipt_kind"}
	if not _valid_id(value["authority_id"]) or not _valid_id(value["entity_id"]):
		return {"ok": false, "error": "onboarding_receipt_id"}
	var day_result := _bounded_integer(value["game_day"], 0, MAX_GAME_DAY)
	if not bool(day_result.get("ok", false)):
		return {"ok": false, "error": "onboarding_receipt_game_day"}
	return {"ok": true, "receipt": {
		"kind": expected_kind,
		"authority_id": str(value["authority_id"]),
		"entity_id": str(value["entity_id"]),
		"game_day": int(day_result["value"]),
	}}


func _valid_id(value: Variant) -> bool:
	if not (value is String):
		return false
	var text := str(value)
	return text.length() >= 1 and text.length() <= MAX_ID_LENGTH and text.is_valid_identifier()


func _bounded_integer(value: Variant, minimum: int, maximum: int) -> Dictionary:
	if typeof(value) == TYPE_INT:
		var integer_value := int(value)
		return {"ok": integer_value >= minimum and integer_value <= maximum, "value": integer_value}
	if typeof(value) == TYPE_FLOAT and is_finite(float(value)) and is_equal_approx(float(value), floor(float(value))):
		var float_integer := int(value)
		return {"ok": float_integer >= minimum and float_integer <= maximum, "value": float_integer}
	return {"ok": false, "value": minimum}


func _has_exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true


func _lock(reason: String) -> Dictionary:
	_phase = PHASE_LOCKED
	_next_index = 0
	_completion_basis = ""
	_receipts.clear()
	_due_game_day = UNSCHEDULED_GAME_DAY
	_lock_reason = reason
	return {"ok": false, "error": reason}
