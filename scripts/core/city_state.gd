extends RefCounted

const LedgerScript = preload("res://scripts/core/ledger.gd")

const SNAPSHOT_SCHEMA_VERSION := 1
const MIN_SUPPORTED_SNAPSHOT_SCHEMA_VERSION := 1
const DAYS_PER_MONTH := 30
const MONTHS_PER_YEAR := 12

var city_id: String = "city_001"
var game_time: int = 0
var last_event_sequence: int = 0
var ledger = null
var metrics: Dictionary = {}
var buildings: Dictionary = {}
var construction_jobs: Dictionary = {}
var npcs: Dictionary = {}
var scheduled_events: Dictionary = {}
var event_book: Array[Dictionary] = []
var governance: Dictionary = {}
var maintenance: Dictionary = {}
var metadata: Dictionary = {}


func _init(initial_funds: int = 50000, p_city_id: String = "city_001") -> void:
	city_id = p_city_id
	ledger = LedgerScript.new(initial_funds, 0)
	metrics = {
		"population": 0,
		"satisfaction": 50.0,
		"grievance": 0.0,
		"municipal_trust": 75.0,
		"environment": 50.0,
		"security": 50.0,
		"education": 50.0,
		"healthcare": 50.0,
		"unemployment_rate": 0.0,
	}
	governance = {
		"active_laws": [],
		"pending_bills": [],
		"rejected_bills": [],
		"judicial_cases": [],
		"oversight_cases": [],
		"committee_summary": {},
		"failed": false,
		"failure_reason": "",
	}
	maintenance = {
		"unpaid_months": 0,
		"last_paid_game_time": 0,
	}


func current_date() -> Dictionary:
	var year := int(game_time / (DAYS_PER_MONTH * MONTHS_PER_YEAR)) + 1
	var year_day := game_time % (DAYS_PER_MONTH * MONTHS_PER_YEAR)
	var month := int(year_day / DAYS_PER_MONTH) + 1
	var day := year_day % DAYS_PER_MONTH + 1
	return {"year": year, "month": month, "day": day, "game_time": game_time}


func metric_value(metric_name: String, fallback: Variant = 0) -> Variant:
	if metric_name.is_empty() or not metrics.has(metric_name):
		return _deep_copy(fallback)
	return _deep_copy(metrics[metric_name])


func set_metric_value(metric_name: String, value: Variant) -> bool:
	if metric_name.is_empty():
		return false
	metrics[metric_name] = _deep_copy(value)
	_clamp_failure_metrics(metric_name)
	return true


func set_metric_values(values: Dictionary) -> bool:
	for metric_name_variant: Variant in values.keys():
		if str(metric_name_variant).is_empty():
			return false
	for metric_name_variant: Variant in values.keys():
		var metric_name := str(metric_name_variant)
		set_metric_value(metric_name, values[metric_name_variant])
	return true


func apply_event(event) -> bool:
	if event == null or event.sequence <= last_event_sequence:
		return false
	var accepted := true
	match event.event_type:
		"time.day_advanced":
			game_time = max(game_time, int(event.game_time))
		"ledger.posted":
			var amount := int(event.payload.get("amount", event.value_delta if event.value_delta != null else 0))
			var entry: Dictionary = ledger.post(
				event.sequence,
				event.game_time,
				amount,
				event.reason_tag,
				event.subject_id,
				event.payload.get("metadata", {}) as Dictionary,
				bool(event.payload.get("allow_overdraft", false))
			)
			accepted = not entry.is_empty()
		"metric.changed":
			var metric_name := str(event.payload.get("metric", event.subject_id))
			if metric_name.is_empty():
				accepted = false
			elif event.payload.has("value"):
				set_metric_value(metric_name, event.payload["value"])
			else:
				set_metric_value(
					metric_name,
					float(metrics.get(metric_name, 0.0)) + float(event.value_delta if event.value_delta != null else event.payload.get("delta", 0.0))
				)
		"building.upserted":
			buildings[event.subject_id] = event.payload.get("record", event.payload).duplicate(true)
		"building.removed":
			buildings.erase(event.subject_id)
		"construction.upserted":
			construction_jobs[event.subject_id] = event.payload.get("record", event.payload).duplicate(true)
		"construction.removed":
			construction_jobs.erase(event.subject_id)
		"npc.upserted":
			npcs[event.subject_id] = event.payload.get("record", event.payload).duplicate(true)
		"npc.removed":
			npcs.erase(event.subject_id)
		"scheduled_event.upserted":
			scheduled_events[event.subject_id] = event.payload.get("record", event.payload).duplicate(true)
		"scheduled_event.removed":
			scheduled_events.erase(event.subject_id)
		"event_book.appended":
			var record: Dictionary = event.payload.get("record", event.payload).duplicate(true)
			record["event_sequence"] = event.sequence
			record["game_time"] = event.game_time
			event_book.append(record)
		"governance.patched":
			for key: Variant in event.payload.keys():
				governance[key] = _deep_copy(event.payload[key])
		"maintenance.patched":
			for key: Variant in event.payload.keys():
				maintenance[key] = _deep_copy(event.payload[key])
		"command.rejected", "calendar.month_started", "calendar.year_started":
			pass
		_:
			# Unknown events remain valid audit facts. Feature systems can listen to
			# them without forcing the core snapshot to understand every domain.
			pass
	if accepted:
		last_event_sequence = event.sequence
	return accepted


func due_scheduled_events(at_game_time: int) -> Array[Dictionary]:
	var due: Array[Dictionary] = []
	for event_id: Variant in scheduled_events.keys():
		var record: Dictionary = scheduled_events[event_id]
		if int(record.get("due_game_time", 0)) <= at_game_time:
			var copy := record.duplicate(true)
			copy["event_id"] = str(event_id)
			due.append(copy)
	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_time := int(a.get("due_game_time", 0))
		var b_time := int(b.get("due_game_time", 0))
		if a_time == b_time:
			return str(a.get("event_id", "")) < str(b.get("event_id", ""))
		return a_time < b_time
	)
	return due


func to_dict() -> Dictionary:
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"city_id": city_id,
		"game_time": game_time,
		"last_event_sequence": last_event_sequence,
		"ledger": ledger.to_dict(),
		"metrics": metrics.duplicate(true),
		"buildings": buildings.duplicate(true),
		"construction_jobs": construction_jobs.duplicate(true),
		"npcs": npcs.duplicate(true),
		"scheduled_events": scheduled_events.duplicate(true),
		"event_book": event_book.duplicate(true),
		"governance": governance.duplicate(true),
		"maintenance": maintenance.duplicate(true),
		"metadata": metadata.duplicate(true),
	}


static func from_dict(data: Dictionary):
	var migrated := migrate_dict(data)
	if migrated.is_empty():
		return null
	for dictionary_field: String in ["ledger", "metrics", "buildings", "construction_jobs", "npcs", "scheduled_events", "governance", "maintenance", "metadata"]:
		if not migrated.get(dictionary_field, {}) is Dictionary:
			return null
	if not migrated.get("event_book", []) is Array:
		return null
	if not _is_integer_value(migrated.get("game_time", 0)) or not _is_integer_value(migrated.get("last_event_sequence", 0)):
		return null
	var state = new(0, str(migrated.get("city_id", "city_001")))
	var loaded_ledger = LedgerScript.from_dict(migrated.get("ledger", {}) as Dictionary)
	if loaded_ledger == null:
		return null
	state.ledger = loaded_ledger
	state.game_time = int(migrated.get("game_time", 0))
	state.last_event_sequence = int(migrated.get("last_event_sequence", 0))
	var loaded_metrics: Dictionary = migrated.get("metrics", {})
	for metric_name: Variant in loaded_metrics.keys():
		state.metrics[metric_name] = state._deep_copy(loaded_metrics[metric_name])
	state.buildings = (migrated.get("buildings", {}) as Dictionary).duplicate(true)
	state.construction_jobs = (migrated.get("construction_jobs", {}) as Dictionary).duplicate(true)
	state.npcs = (migrated.get("npcs", {}) as Dictionary).duplicate(true)
	if not loaded_metrics.has("population"):
		# Schema-1 snapshots created before the population mirror was introduced
		# remain loadable; their already-persisted NPC collection is authoritative.
		state.metrics["population"] = state.npcs.size()
	state.scheduled_events = (migrated.get("scheduled_events", {}) as Dictionary).duplicate(true)
	state.event_book.clear()
	for raw_record: Variant in migrated.get("event_book", []):
		if raw_record is Dictionary:
			state.event_book.append((raw_record as Dictionary).duplicate(true))
		else:
			return null
	var loaded_governance: Dictionary = migrated.get("governance", {})
	for governance_key: Variant in loaded_governance.keys():
		state.governance[governance_key] = state._deep_copy(loaded_governance[governance_key])
	var loaded_maintenance: Dictionary = migrated.get("maintenance", {})
	for maintenance_key: Variant in loaded_maintenance.keys():
		state.maintenance[maintenance_key] = state._deep_copy(loaded_maintenance[maintenance_key])
	state.metadata = (migrated.get("metadata", {}) as Dictionary).duplicate(true)
	if not state.validate_semantics():
		return null
	return state


static func migrate_dict(data: Dictionary) -> Dictionary:
	if not _is_integer_value(data.get("schema_version", -1)):
		return {}
	var source_version := int(data.get("schema_version", -1))
	if source_version < MIN_SUPPORTED_SNAPSHOT_SCHEMA_VERSION or source_version > SNAPSHOT_SCHEMA_VERSION:
		return {}
	# Version 1 remains readable as-is. Future migrations must be added here
	# explicitly instead of being synthesized by permissive default values.
	return data.duplicate(true)


func validate_semantics() -> bool:
	if city_id.is_empty() or game_time < 0 or last_event_sequence < 0:
		return false
	if ledger == null or not ledger.verify_balance():
		return false
	var population_value: Variant = metrics.get("population", npcs.size())
	if not _is_integer_value(population_value) or int(population_value) < 0 or int(population_value) != npcs.size():
		return false
	for bounded_metric: String in ["grievance", "municipal_trust"]:
		if not metrics.has(bounded_metric):
			continue
		var metric_value: Variant = metrics[bounded_metric]
		if not _is_numeric_value(metric_value) or float(metric_value) < 0.0 or float(metric_value) > 100.0:
			return false
	for collection: Dictionary in [buildings, construction_jobs, npcs, scheduled_events]:
		for record_value: Variant in collection.values():
			if not record_value is Dictionary:
				return false
	for entry: Dictionary in ledger.get_entries():
		var sequence_value: Variant = entry.get("event_sequence", 0)
		if not _is_integer_value(sequence_value):
			return false
		var sequence := int(sequence_value)
		if sequence < 0 or sequence > last_event_sequence:
			return false
	for event_record: Dictionary in event_book:
		if event_record.has("event_sequence"):
			var event_sequence_value: Variant = event_record["event_sequence"]
			if not _is_integer_value(event_sequence_value):
				return false
			var recorded_sequence := int(event_sequence_value)
			if recorded_sequence < 0 or recorded_sequence > last_event_sequence:
				return false
	return true


func deterministic_hash() -> String:
	return JSON.stringify(_canonicalize(to_dict()), "", false).sha256_text()


func _clamp_failure_metrics(metric_name: String) -> void:
	if metric_name == "grievance":
		metrics[metric_name] = clampf(float(metrics[metric_name]), 0.0, 100.0)
	elif metric_name == "municipal_trust":
		metrics[metric_name] = clampf(float(metrics[metric_name]), 0.0, 100.0)


func _deep_copy(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value


static func _is_integer_value(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		return is_finite(float(value)) and is_equal_approx(float(value), roundf(float(value)))
	if value is String:
		return (value as String).is_valid_int()
	return false


static func _is_numeric_value(value: Variant) -> bool:
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
