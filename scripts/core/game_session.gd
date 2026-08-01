extends RefCounted

const CityStateScript = preload("res://scripts/core/city_state.gd")
const SimulationClockScript = preload("res://scripts/core/simulation_clock.gd")
const SimulationKernelScript = preload("res://scripts/core/simulation_kernel.gd")
const SaveEnvelopeScript = preload("res://scripts/core/save_envelope.gd")
const SaveServiceScript = preload("res://scripts/core/save_service.gd")

signal domain_event(event)
signal state_changed(view_model: Dictionary)

const CONTENT_VERSION := "vertical_slice_1"
const DEFAULT_SAVE_PATH := "user://mayor_simulator/autosave.json"
const MAX_SUPPORTED_VERTICAL_SLICE_METADATA_SCHEMA := 5
const MAX_SUPPORTED_POPULATION_SCHEMA := 2
const MAX_SUPPORTED_NPC_RECORD_SCHEMA := 2
const TERMINAL_FAILURE_REASONS := [
	"",
	"imprisonment_judgment",
	"grievance_above_80",
	"municipal_trust_below_40",
]

var state = null
var clock = null
var kernel = null
var save_service = null
var save_path: String = DEFAULT_SAVE_PATH


func _init(seed: int = SimulationKernelScript.DEFAULT_SEED, initial_funds: int = 50000) -> void:
	save_service = SaveServiceScript.new()
	new_game(seed, initial_funds)


func new_game(seed: int = SimulationKernelScript.DEFAULT_SEED, initial_funds: int = 50000, city_id: String = "city_001") -> void:
	state = CityStateScript.new(initial_funds, city_id)
	clock = SimulationClockScript.new()
	kernel = SimulationKernelScript.new(state, seed)
	kernel.event_emitted.connect(_on_kernel_event)
	state_changed.emit(get_view_model())


func process_frame(delta_seconds: float) -> Array:
	var elapsed_days: int = int(clock.consume_frame(delta_seconds))
	if elapsed_days <= 0:
		return []
	return advance_days_for_test(elapsed_days)


func queue_command(command_type: String, payload: Dictionary = {}, operation_id: String = ""):
	return kernel.enqueue(command_type, payload, operation_id)


func flush_commands(max_commands: int = 10000) -> Array:
	var events: Array = kernel.process_all(max_commands)
	if not events.is_empty():
		state_changed.emit(get_view_model())
	return events


func submit_command(command_type: String, payload: Dictionary = {}, operation_id: String = "") -> Array:
	var command = queue_command(command_type, payload, operation_id)
	if command == null:
		return []
	return flush_commands()


func advance_days_for_test(days: int) -> Array:
	if days <= 0:
		return []
	return submit_command("advance_day", {"days": days})


func make_envelope():
	var runtime: Dictionary = kernel.to_runtime_dict()
	var envelope = SaveEnvelopeScript.new()
	envelope.content_version = CONTENT_VERSION
	envelope.rng_seed = kernel.rng_seed
	envelope.rng_state = kernel.rng.state
	envelope.game_time = state.game_time
	envelope.event_sequence = kernel.event_sequence
	envelope.command_sequence = kernel.command_sequence
	envelope.state = state.to_dict()
	envelope.kernel = runtime
	envelope.clock = clock.to_dict()
	return envelope


func restore_envelope(envelope) -> bool:
	if envelope == null or envelope.content_version != CONTENT_VERSION:
		return false
	var restored_state = CityStateScript.from_dict(envelope.state)
	if restored_state == null:
		return false
	if not _validate_envelope_semantics(envelope, restored_state):
		return false
	var restored_clock = SimulationClockScript.new()
	restored_clock.restore(envelope.clock)
	var restored_kernel = SimulationKernelScript.new(restored_state, envelope.rng_seed)
	restored_kernel.restore_runtime_dict(_normalized_runtime(envelope))
	state = restored_state
	clock = restored_clock
	kernel = restored_kernel
	if not kernel.event_emitted.is_connected(_on_kernel_event):
		kernel.event_emitted.connect(_on_kernel_event)
	state_changed.emit(get_view_model())
	return true


func save_now(path: String = "") -> Error:
	var resolved_path: String = path if not path.is_empty() else save_path
	var envelope = make_envelope()
	var validated_state = CityStateScript.from_dict(envelope.state)
	if validated_state == null or not _validate_envelope_semantics(envelope, validated_state):
		save_service.last_error_message = "Refusing to save a semantically inconsistent session snapshot."
		return ERR_INVALID_DATA
	return save_service.save_atomic(resolved_path, envelope)


func load_now(path: String = "") -> bool:
	var resolved_path: String = path if not path.is_empty() else save_path
	save_service.begin_load_attempt()
	var primary_envelope = save_service.load_primary_envelope(resolved_path)
	if primary_envelope != null and restore_envelope(primary_envelope):
		save_service.mark_primary_restored(resolved_path)
		return true
	var primary_error: String = str(save_service.last_error_message)
	if primary_envelope != null:
		primary_error = "Primary save failed semantic validation."
	var backup_envelope = save_service.load_backup_envelope(resolved_path)
	if backup_envelope == null:
		var backup_error: String = str(save_service.last_error_message)
		save_service.last_error_message = "%s Backup: %s" % [primary_error, backup_error]
		return false
	if not restore_envelope(backup_envelope):
		save_service.last_error_message = "%s Backup save failed semantic validation." % primary_error
		return false
	# Loading remains successful when the valid backup is already in memory. The
	# service keeps that backup protected if rebuilding the primary cannot finish,
	# so the next save cannot rotate a known-bad primary over the trusted copy.
	save_service.mark_backup_restored(resolved_path)
	return true


func get_view_model() -> Dictionary:
	var date: Dictionary = state.current_date()
	var grievance := float(state.metrics.get("grievance", 0.0))
	var trust := float(state.metrics.get("municipal_trust", 75.0))
	var alerts: Array[Dictionary] = []
	if grievance > 80.0:
		alerts.append({"severity": "failure", "reason_tag": "grievance_over_80"})
	elif grievance >= 70.0:
		alerts.append({"severity": "warning", "reason_tag": "grievance_near_limit"})
	if trust < 40.0:
		alerts.append({"severity": "failure", "reason_tag": "municipal_trust_below_40"})
	elif trust <= 50.0:
		alerts.append({"severity": "warning", "reason_tag": "municipal_trust_near_limit"})
	if bool(state.governance.get("failed", false)):
		alerts.append({"severity": "failure", "reason_tag": str(state.governance.get("failure_reason", "governance_failure"))})
	return {
		"city_id": state.city_id,
		"game_time": state.game_time,
		"date": date,
		"treasury": state.ledger.get_balance(),
		"metrics": state.metrics.duplicate(true),
		"building_count": state.buildings.size(),
		"construction_count": state.construction_jobs.size(),
		"npc_count": state.npcs.size(),
		"available_workers": _available_construction_workers(),
		"alerts": alerts,
		"last_event_sequence": state.last_event_sequence,
	}


func deterministic_hash() -> String:
	return JSON.stringify(_canonicalize({
		"state": state.to_dict(),
		"kernel": kernel.to_runtime_dict(),
		"clock": clock.to_dict(),
	}), "", false).sha256_text()


func _available_construction_workers() -> int:
	var assigned := 0
	for record: Variant in state.construction_jobs.values():
		if record is Dictionary:
			assigned += int((record as Dictionary).get("workers", 0))
	return maxi(0, 20 - assigned)


func _on_kernel_event(event) -> void:
	domain_event.emit(event)


func _validate_envelope_semantics(envelope, restored_state) -> bool:
	if envelope.game_time != restored_state.game_time:
		return false
	if envelope.event_sequence != restored_state.last_event_sequence:
		return false
	if not _validate_clock_snapshot(envelope.clock):
		return false
	var runtime: Dictionary = envelope.kernel
	if not runtime.is_empty():
		if not _runtime_integer_matches(runtime, "rng_seed", envelope.rng_seed):
			return false
		if not _runtime_integer_matches(runtime, "rng_state", envelope.rng_state):
			return false
		if not _runtime_integer_matches(runtime, "event_sequence", envelope.event_sequence):
			return false
		if not _runtime_integer_matches(runtime, "command_sequence", envelope.command_sequence):
			return false
		if not _validate_runtime_collections(runtime, envelope.command_sequence):
			return false
	return _validate_vertical_slice_metadata(restored_state)


func _validate_clock_snapshot(clock_data: Dictionary) -> bool:
	if clock_data.is_empty():
		return true
	for numeric_field: String in ["day_length_seconds", "accumulator_seconds"]:
		if clock_data.has(numeric_field) and not _is_finite_number(clock_data[numeric_field]):
			return false
	var day_length := float(clock_data.get("day_length_seconds", SimulationClockScript.DEFAULT_DAY_LENGTH_SECONDS))
	var accumulator := float(clock_data.get("accumulator_seconds", 0.0))
	return day_length > 0.0 and accumulator >= 0.0 and accumulator <= day_length


func _runtime_integer_matches(runtime: Dictionary, field_name: String, expected: int) -> bool:
	if not runtime.has(field_name) or not _is_integer_value(runtime[field_name]):
		return false
	return int(str(runtime[field_name])) == expected


func _validate_runtime_collections(runtime: Dictionary, command_limit: int) -> bool:
	var pending_value: Variant = runtime.get("pending_commands", [])
	var processed_value: Variant = runtime.get("processed_operation_ids", [])
	if not pending_value is Array or not processed_value is Array:
		return false
	for raw_command: Variant in pending_value:
		if not raw_command is Dictionary:
			return false
		var command: Dictionary = raw_command
		if str(command.get("operation_id", "")).is_empty() or str(command.get("command_type", "")).is_empty():
			return false
		if not command.get("payload", {}) is Dictionary:
			return false
		if not _is_integer_value(command.get("game_time", 0)) or not _is_integer_value(command.get("ordinal", 0)):
			return false
		var ordinal := int(command.get("ordinal", 0))
		if int(command.get("game_time", 0)) < 0 or ordinal < 0 or ordinal > command_limit:
			return false
	for operation_id: Variant in processed_value:
		if not operation_id is String or (operation_id as String).is_empty():
			return false
	return true


func _normalized_runtime(envelope) -> Dictionary:
	var runtime: Dictionary = envelope.kernel.duplicate(true)
	if not runtime.has("rng_seed"):
		runtime["rng_seed"] = str(envelope.rng_seed)
	if not runtime.has("rng_state"):
		runtime["rng_state"] = str(envelope.rng_state)
	if not runtime.has("event_sequence"):
		runtime["event_sequence"] = envelope.event_sequence
	if not runtime.has("command_sequence"):
		runtime["command_sequence"] = envelope.command_sequence
	if not runtime.has("pending_commands"):
		runtime["pending_commands"] = []
	if not runtime.has("processed_operation_ids"):
		runtime["processed_operation_ids"] = []
	return runtime


func _validate_vertical_slice_metadata(restored_state) -> bool:
	if not restored_state.metadata.has("vertical_slice"):
		return true
	var vertical_value: Variant = restored_state.metadata["vertical_slice"]
	if not vertical_value is Dictionary:
		return false
	var vertical: Dictionary = vertical_value
	var schema_value: Variant = vertical.get("schema_version", 0)
	if not _is_integer_value(schema_value):
		return false
	var schema_version := int(schema_value)
	if schema_version < 0 or schema_version > MAX_SUPPORTED_VERTICAL_SLICE_METADATA_SCHEMA:
		return false
	# Schema 4 adds an optional persisted UI-event latch. Older saves omit it;
	# current saves must keep it string-typed and inside the governance failure
	# vocabulary so a forged value cannot suppress or invent terminal events.
	if vertical.has("terminal_failure_event_reason"):
		var terminal_reason: Variant = vertical["terminal_failure_event_reason"]
		if not terminal_reason is String or str(terminal_reason) not in TERMINAL_FAILURE_REASONS:
			return false
	# Schemas 1-2 predate the canonical persistent population snapshot. Schema 3
	# and later require it, so a missing block is corruption rather than a legacy save.
	if schema_version < 3:
		return true
	var population_value: Variant = vertical.get("population", null)
	if not population_value is Dictionary:
		return false
	var population: Dictionary = population_value
	var population_schema: Variant = population.get("schema_version", 1)
	if not _is_integer_value(population_schema) or int(population_schema) < 1 or int(population_schema) > MAX_SUPPORTED_POPULATION_SCHEMA:
		return false
	var population_schema_version := int(population_schema)
	var records_value: Variant = population.get("records", null)
	if not records_value is Array:
		return false
	var canonical_ids: Dictionary = {}
	for record_value: Variant in records_value:
		if not record_value is Dictionary:
			return false
		var record: Dictionary = record_value
		var record_schema: Variant = record.get("schema_version", 1)
		if not _is_integer_value(record_schema) or int(record_schema) < 1 or int(record_schema) > MAX_SUPPORTED_NPC_RECORD_SCHEMA:
			return false
		for nonnegative_field: String in ["income", "salary", "debt"]:
			if not record.has(nonnegative_field) or record[nonnegative_field] == null:
				continue
			if not _is_integer_value(record[nonnegative_field]) or int(record[nonnegative_field]) < 0:
				return false
		var npc_id := str(record.get("npc_id", ""))
		if npc_id.is_empty() or canonical_ids.has(npc_id):
			return false
		canonical_ids[npc_id] = true
	if canonical_ids.size() != restored_state.npcs.size():
		return false
	for core_id: Variant in restored_state.npcs.keys():
		if not canonical_ids.has(str(core_id)):
			return false
	var requests_value: Variant = population.get("requests", [])
	if not requests_value is Array:
		return false
	for request_value: Variant in requests_value:
		if not request_value is Dictionary:
			return false
		var request_npc_id := str((request_value as Dictionary).get("npc_id", ""))
		if not request_npc_id.is_empty() and not canonical_ids.has(request_npc_id):
			return false
	if population_schema_version >= 2 and not _validate_population_finance_snapshot(population):
		return false
	for building_value: Variant in restored_state.buildings.values():
		var building: Dictionary = building_value
		if not building.has("resident_ids"):
			continue
		var resident_ids_value: Variant = building["resident_ids"]
		if not resident_ids_value is Array:
			return false
		for resident_id: Variant in resident_ids_value:
			if not canonical_ids.has(str(resident_id)):
				return false
	return true


func _validate_population_finance_snapshot(population: Dictionary) -> bool:
	var next_sequence_value: Variant = population.get("next_transaction_sequence", null)
	var transactions_value: Variant = population.get("income_transactions", null)
	if not _is_integer_value(next_sequence_value) or int(next_sequence_value) < 1 or not transactions_value is Array:
		return false
	var seen_transaction_ids: Dictionary = {}
	var highest_generated_sequence := 0
	for transaction_value: Variant in transactions_value:
		if not transaction_value is Dictionary:
			return false
		var transaction: Dictionary = transaction_value
		var transaction_id := str(transaction.get("transaction_id", "")).strip_edges()
		var npc_id := str(transaction.get("npc_id", "")).strip_edges()
		var source_type := str(transaction.get("source_type", "")).strip_edges().to_lower()
		if transaction_id.is_empty() or seen_transaction_ids.has(transaction_id) or npc_id.is_empty():
			return false
		if source_type not in ["salary", "investment", "insurance", "inheritance", "other"]:
			return false
		if not _is_integer_value(transaction.get("game_day", -1)) or int(transaction.get("game_day", -1)) < 0:
			return false
		if not _is_integer_value(transaction.get("amount", 0)) or int(transaction.get("amount", 0)) <= 0:
			return false
		if not transaction.get("metadata", {}) is Dictionary:
			return false
		seen_transaction_ids[transaction_id] = true
		var suffix := transaction_id.trim_prefix("income_tx_")
		if suffix.is_valid_int():
			highest_generated_sequence = maxi(highest_generated_sequence, int(suffix))
	return int(next_sequence_value) > highest_generated_sequence


func _is_integer_value(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		return is_finite(float(value)) and is_equal_approx(float(value), roundf(float(value)))
	if value is String:
		return (value as String).is_valid_int()
	return false


func _is_finite_number(value: Variant) -> bool:
	return (value is int) or (value is float and is_finite(float(value)))


func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var output: Dictionary = {}
		var keys: Array = (value as Dictionary).keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		for key: Variant in keys:
			output[str(key)] = _canonicalize((value as Dictionary)[key])
		return output
	if value is Array:
		var output: Array = []
		for item: Variant in value:
			output.append(_canonicalize(item))
		return output
	if value is float and is_equal_approx(float(value), roundf(float(value))):
		return int(value)
	return value
