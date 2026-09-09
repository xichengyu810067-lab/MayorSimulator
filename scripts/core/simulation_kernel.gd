extends RefCounted

const SimCommandScript = preload("res://scripts/core/sim_command.gd")
const DomainEventScript = preload("res://scripts/core/domain_event.gd")
const CityStateScript = preload("res://scripts/core/city_state.gd")

signal event_emitted(event)

const DEFAULT_SEED := 20260715

var state = null
var rng := RandomNumberGenerator.new()
var rng_seed: int = DEFAULT_SEED
var event_sequence: int = 0
var command_sequence: int = 0
var pending_commands: Array = []
var processed_operation_ids: Dictionary = {}
var _event_outbox: Array = []


func _init(p_state = null, p_seed: int = DEFAULT_SEED) -> void:
	state = p_state if p_state != null else CityStateScript.new()
	rng_seed = p_seed
	rng.seed = rng_seed
	event_sequence = state.last_event_sequence


func enqueue(command_type: String, payload: Dictionary = {}, operation_id: String = ""):
	command_sequence += 1
	var resolved_id := operation_id
	if resolved_id.is_empty():
		resolved_id = "cmd_%010d" % command_sequence
	var command = SimCommandScript.new(resolved_id, command_type, state.game_time, payload, command_sequence)
	if not submit(command):
		return null
	return command


func submit(command) -> bool:
	if command == null or command.operation_id.is_empty():
		return false
	if processed_operation_ids.has(command.operation_id):
		return false
	for queued in pending_commands:
		if queued.operation_id == command.operation_id:
			return false
	pending_commands.append(command)
	command_sequence = max(command_sequence, command.ordinal)
	return true


func process_next() -> Array:
	if pending_commands.is_empty():
		return []
	var command = pending_commands.pop_front()
	var events: Array = []
	match command.command_type:
		"advance_day":
			var days := maxi(0, int(command.payload.get("days", 1)))
			for _day_index: int in range(days):
				var previous_date: Dictionary = state.current_date()
				events.append(_emit(
					"time.day_advanced",
					state.game_time + 1,
					"calendar",
					1,
					"clock_tick",
					{},
					command.operation_id
				))
				_append_calendar_boundary_events(events, previous_date, command.operation_id)
				_append_due_scheduled_events(events, command.operation_id)
		"ledger_post":
			var amount := int(command.payload.get("amount", 0))
			var allow_overdraft := bool(command.payload.get("allow_overdraft", false))
			if state.ledger.can_post(amount, allow_overdraft):
				events.append(_emit(
					"ledger.posted",
					state.game_time,
					str(command.payload.get("source_id", "city")),
					amount,
					str(command.payload.get("reason_tag", "treasury_adjustment")),
					{
						"amount": amount,
						"allow_overdraft": allow_overdraft,
						"metadata": (command.payload.get("metadata", {}) as Dictionary).duplicate(true),
					},
					command.operation_id
				))
			else:
				events.append(_rejected(command, "insufficient_treasury"))
		"metric_change":
			var metric_payload: Dictionary = command.payload.duplicate(true)
			var metric_name := str(metric_payload.get("metric", ""))
			if metric_name.is_empty():
				events.append(_rejected(command, "metric_required"))
			else:
				events.append(_emit(
					"metric.changed",
					state.game_time,
					metric_name,
					metric_payload.get("delta"),
					str(metric_payload.get("reason_tag", "metric_adjustment")),
					metric_payload,
					command.operation_id
				))
		"upsert_building":
			events.append(_upsert_record(command, "building.upserted", "building_id"))
		"complete_building_construction":
			var building_id := str(command.payload.get("building_id", ""))
			var job_id := str(command.payload.get("job_id", ""))
			var record_value: Variant = command.payload.get("record", null)
			if building_id.is_empty():
				events.append(_rejected(command, "building_id_required"))
			elif job_id.is_empty():
				events.append(_rejected(command, "job_id_required"))
			elif not record_value is Dictionary:
				events.append(_rejected(command, "building_record_required"))
			else:
				var validation_error := _building_completion_validation_error(job_id, record_value as Dictionary)
				if not validation_error.is_empty():
					events.append(_rejected(command, validation_error))
				else:
					var record: Dictionary = (record_value as Dictionary).duplicate(true)
					record["building_id"] = building_id
					events.append(_emit(
						"building.construction_completed",
						state.game_time,
						building_id,
						null,
						str(command.payload.get("reason_tag", "building.construction_completed")),
						{"record": record, "job_id": job_id},
						command.operation_id
					))
		"remove_building":
			events.append(_remove_record(command, "building.removed", "building_id"))
		"upsert_construction":
			events.append(_upsert_record(command, "construction.upserted", "job_id"))
		"remove_construction":
			events.append(_remove_record(command, "construction.removed", "job_id"))
		"upsert_npc":
			events.append(_upsert_record(command, "npc.upserted", "npc_id"))
		"remove_npc":
			events.append(_remove_record(command, "npc.removed", "npc_id"))
		"schedule_event":
			var event_id := str(command.payload.get("event_id", "scheduled_%010d" % (event_sequence + 1)))
			var schedule_record: Dictionary = command.payload.duplicate(true)
			schedule_record.erase("event_id")
			events.append(_emit("scheduled_event.upserted", state.game_time, event_id, null, "event_scheduled", {"record": schedule_record}, command.operation_id))
		"append_event_book":
			events.append(_emit(
				"event_book.appended",
				state.game_time,
				str(command.payload.get("subject_id", "city")),
				null,
				str(command.payload.get("reason_tag", "major_event")),
				{"record": (command.payload.get("record", command.payload) as Dictionary).duplicate(true)},
				command.operation_id
			))
		"patch_governance":
			events.append(_emit("governance.patched", state.game_time, "governance", null, str(command.payload.get("reason_tag", "governance_update")), command.payload, command.operation_id))
		"patch_maintenance":
			events.append(_emit("maintenance.patched", state.game_time, "maintenance", null, str(command.payload.get("reason_tag", "maintenance_update")), command.payload, command.operation_id))
		_:
			events.append(_rejected(command, "unknown_command"))
	processed_operation_ids[command.operation_id] = true
	return events


func process_all(max_commands: int = 10000) -> Array:
	var emitted: Array = []
	var processed := 0
	while not pending_commands.is_empty() and processed < max_commands:
		emitted.append_array(process_next())
		processed += 1
	if not pending_commands.is_empty():
		push_error("SimulationKernel command limit reached; commands remain queued.")
	return emitted


func drain_events() -> Array:
	var events: Array = _event_outbox.duplicate()
	_event_outbox.clear()
	return events


func random_int(minimum: int, maximum: int) -> int:
	return rng.randi_range(minimum, maximum)


func to_runtime_dict() -> Dictionary:
	var pending: Array[Dictionary] = []
	for command in pending_commands:
		pending.append(command.to_dict())
	var processed_ids: Array[String] = []
	for operation_id: Variant in processed_operation_ids.keys():
		processed_ids.append(str(operation_id))
	processed_ids.sort()
	return {
		"rng_seed": str(rng_seed),
		"rng_state": str(rng.state),
		"event_sequence": event_sequence,
		"command_sequence": command_sequence,
		"pending_commands": pending,
		"processed_operation_ids": processed_ids,
	}


func restore_runtime_dict(data: Dictionary) -> void:
	rng_seed = int(str(data.get("rng_seed", str(DEFAULT_SEED))))
	rng.seed = rng_seed
	if data.has("rng_state"):
		rng.state = int(str(data["rng_state"]))
	event_sequence = int(data.get("event_sequence", state.last_event_sequence))
	command_sequence = int(data.get("command_sequence", 0))
	pending_commands.clear()
	for raw_command: Variant in data.get("pending_commands", []):
		if raw_command is Dictionary:
			pending_commands.append(SimCommandScript.from_dict(raw_command as Dictionary))
	processed_operation_ids.clear()
	for operation_id: Variant in data.get("processed_operation_ids", []):
		processed_operation_ids[str(operation_id)] = true
	_event_outbox.clear()


func _emit(
		event_type: String,
		game_time: int,
		subject_id: String,
		value_delta: Variant,
		reason_tag: String,
		payload: Dictionary,
		caused_by: String
):
	event_sequence += 1
	var event = DomainEventScript.new(event_sequence, event_type, game_time, subject_id, value_delta, reason_tag, payload, caused_by)
	if not state.apply_event(event):
		push_error("CityState rejected domain event %s #%d." % [event_type, event_sequence])
	_event_outbox.append(event)
	event_emitted.emit(event)
	return event


func _rejected(command, rejection_reason: String):
	return _emit(
		"command.rejected",
		state.game_time,
		command.operation_id,
		null,
		rejection_reason,
		{"command_type": command.command_type},
		command.operation_id
	)


func _upsert_record(command, event_type: String, id_key: String):
	var record: Dictionary = (command.payload.get("record", command.payload) as Dictionary).duplicate(true)
	var subject_id := str(command.payload.get(id_key, record.get(id_key, "")))
	if subject_id.is_empty():
		return _rejected(command, "%s_required" % id_key)
	record[id_key] = subject_id
	return _emit(event_type, state.game_time, subject_id, null, str(command.payload.get("reason_tag", "record_upsert")), {"record": record}, command.operation_id)


func _remove_record(command, event_type: String, id_key: String):
	var subject_id := str(command.payload.get(id_key, ""))
	if subject_id.is_empty():
		return _rejected(command, "%s_required" % id_key)
	return _emit(event_type, state.game_time, subject_id, null, str(command.payload.get("reason_tag", "record_removed")), {}, command.operation_id)


func _building_completion_validation_error(job_id: String, record: Dictionary) -> String:
	if not state.construction_jobs.has(job_id):
		return "construction_job_required"
	var job_value: Variant = state.construction_jobs[job_id]
	if not job_value is Dictionary:
		return "construction_job_invalid"
	var job: Dictionary = job_value
	if str(job.get("status", "")) != "completed":
		return "construction_job_not_completed"
	if str(job.get("operation", "")) != "build":
		return "construction_job_not_build"
	var metadata_value: Variant = job.get("metadata", null)
	if not metadata_value is Dictionary:
		return "building_job_metadata_required"
	var metadata: Dictionary = metadata_value
	if not str(metadata.get("entity_kind", "")).is_empty():
		return "construction_job_not_building"
	if str(record.get("status", "")) != "active":
		return "building_record_not_active"
	var job_blueprint_value: Variant = job.get("blueprint", null)
	var record_blueprint_value: Variant = record.get("blueprint", null)
	if not job_blueprint_value is Dictionary or not record_blueprint_value is Dictionary:
		return "building_blueprint_required"
	var job_blueprint: Dictionary = job_blueprint_value
	var record_blueprint: Dictionary = record_blueprint_value
	if record_blueprint != job_blueprint:
		return "building_blueprint_mismatch"
	if str(record.get("definition_id", "")) != str(job_blueprint.get("building_id", "")):
		return "building_definition_mismatch"
	if str(record.get("building_name", "")) != str(metadata.get("building_name", "")):
		return "building_name_mismatch"
	for field_name: String in ["tile_index", "anchor_tile_id", "footprint_id", "occupied_tile_ids"]:
		if not metadata.has(field_name) or not record.has(field_name):
			return "building_job_relation_required"
	if int(metadata.get("tile_index", -1)) != int(record.get("tile_index", -1)):
		return "building_tile_mismatch"
	if int(metadata.get("anchor_tile_id", -1)) != int(record.get("anchor_tile_id", -1)):
		return "building_anchor_mismatch"
	if str(metadata.get("footprint_id", "")) != str(record.get("footprint_id", "")):
		return "building_footprint_mismatch"
	var job_occupied_value: Variant = _normalized_completion_tile_ids(metadata.get("occupied_tile_ids", null))
	var record_occupied_value: Variant = _normalized_completion_tile_ids(record.get("occupied_tile_ids", null))
	if job_occupied_value == null or record_occupied_value == null:
		return "building_occupied_tiles_required"
	if record_occupied_value != job_occupied_value:
		return "building_occupied_tiles_mismatch"
	var tile_index := int(metadata.get("tile_index", -1))
	if tile_index < 0 or int(metadata.get("anchor_tile_id", -1)) != tile_index:
		return "building_job_tile_relation_invalid"
	var occupied_tile_ids: Array = job_occupied_value
	if occupied_tile_ids.is_empty() or int(occupied_tile_ids[0]) != tile_index:
		return "building_job_footprint_relation_invalid"
	if str(metadata.get("footprint_id", "")).is_empty():
		return "building_job_footprint_relation_invalid"
	if str(job.get("target_id", "")) != "tile_%02d" % tile_index:
		return "building_job_target_mismatch"
	return ""


func _normalized_completion_tile_ids(value: Variant) -> Variant:
	if not value is Array:
		return null
	var normalized: Array[int] = []
	for tile_value: Variant in value:
		if not (tile_value is int or tile_value is float):
			return null
		var numeric_value := float(tile_value)
		if not is_finite(numeric_value) or numeric_value != floor(numeric_value):
			return null
		var tile_id := int(numeric_value)
		if tile_id < 0 or normalized.has(tile_id):
			return null
		normalized.append(tile_id)
	return normalized


func _append_calendar_boundary_events(events: Array, previous_date: Dictionary, operation_id: String) -> void:
	var date: Dictionary = state.current_date()
	if int(date["month"]) != int(previous_date["month"]):
		events.append(_emit("calendar.month_started", state.game_time, "calendar", null, "month_started", date, operation_id))
	if int(date["year"]) != int(previous_date["year"]):
		events.append(_emit("calendar.year_started", state.game_time, "calendar", null, "year_started", date, operation_id))


func _append_due_scheduled_events(events: Array, operation_id: String) -> void:
	for record: Dictionary in state.due_scheduled_events(state.game_time):
		var event_id := str(record.get("event_id", ""))
		var scheduled_type := str(record.get("event_type", "scheduled_event.triggered"))
		var scheduled_payload: Dictionary = (record.get("payload", {}) as Dictionary).duplicate(true)
		events.append(_emit(
			scheduled_type,
			state.game_time,
			str(record.get("subject_id", event_id)),
			record.get("value_delta"),
			str(record.get("reason_tag", "scheduled_event_due")),
			scheduled_payload,
			str(record.get("caused_by", operation_id))
		))
		events.append(_emit("scheduled_event.removed", state.game_time, event_id, null, "scheduled_event_consumed", {}, operation_id))
