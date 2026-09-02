extends RefCounted

const CityStateScript = preload("res://scripts/core/city_state.gd")
const SimulationClockScript = preload("res://scripts/core/simulation_clock.gd")
const SimulationKernelScript = preload("res://scripts/core/simulation_kernel.gd")
const SaveEnvelopeScript = preload("res://scripts/core/save_envelope.gd")
const SaveSchemaAuthorityScript = preload("res://scripts/core/save_schema_authority.gd")
const SaveServiceScript = preload("res://scripts/core/save_service.gd")
const ConstructionSystemScript = preload("res://scripts/systems/city/construction_system.gd")
const PopulationSystemScript = preload("res://scripts/systems/population/population_system.gd")
const BlueprintLibraryServiceScript = preload("res://scripts/app/blueprint_library_service.gd")
const TransportNetworkSystemScript = preload("res://scripts/systems/city/transport_network_system.gd")
const TransportPlanningSessionScript = preload("res://scripts/systems/city/transport_planning_session.gd")
const CityTerrainMapScript = preload("res://scripts/world/city_terrain_map.gd")
const TransportModesScript = preload("res://data/catalogs/transport_modes.gd")
const BuildingFootprintsScript = preload("res://data/catalogs/building_footprints.gd")

signal domain_event(event)
signal state_changed(view_model: Dictionary)

const CONTENT_VERSION := "vertical_slice_1"
const DEFAULT_SAVE_PATH := "user://mayor_simulator/autosave.json"
const MIN_SUPPORTED_VERTICAL_SLICE_METADATA_SCHEMA := SaveSchemaAuthorityScript.MIN_SUPPORTED_VERTICAL_SLICE_METADATA_SCHEMA
const MAX_SUPPORTED_VERTICAL_SLICE_METADATA_SCHEMA := SaveSchemaAuthorityScript.MAX_SUPPORTED_VERTICAL_SLICE_METADATA_SCHEMA
const MIN_SUPPORTED_POPULATION_SCHEMA := SaveSchemaAuthorityScript.POPULATION_MIN_SUPPORTED_SCHEMA_VERSION
const MAX_SUPPORTED_POPULATION_SCHEMA := SaveSchemaAuthorityScript.POPULATION_MAX_SUPPORTED_SCHEMA_VERSION
const MIN_SUPPORTED_NPC_RECORD_SCHEMA := SaveSchemaAuthorityScript.NPC_RECORD_MIN_SUPPORTED_SCHEMA_VERSION
const MAX_SUPPORTED_NPC_RECORD_SCHEMA := SaveSchemaAuthorityScript.NPC_RECORD_MAX_SUPPORTED_SCHEMA_VERSION
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


## Installs the canonical population into CityState's runtime-only lookup in one
## atomic, sequence-neutral step. Persisted snapshots still contain the records
## only under metadata.vertical_slice.population.records.
func hydrate_runtime_population(population_snapshot: Dictionary) -> bool:
	if state == null:
		return false
	return state.hydrate_runtime_npcs_from_population(population_snapshot)


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
	var state_snapshot: Dictionary = state.to_dict()
	_stamp_current_writer_pair(state_snapshot)
	envelope.state = state_snapshot
	envelope.kernel = runtime
	envelope.clock = clock.to_dict()
	return envelope


func restore_envelope(envelope) -> bool:
	if envelope == null or envelope.content_version != CONTENT_VERSION:
		return false
	var candidate_envelope = _prepare_envelope_for_restore(envelope)
	if candidate_envelope == null:
		return false
	var restored_state = CityStateScript.from_dict(candidate_envelope.state)
	if restored_state == null:
		return false
	if not _validate_envelope_semantics(candidate_envelope, restored_state):
		return false
	var restored_clock = SimulationClockScript.new()
	restored_clock.restore(candidate_envelope.clock)
	var restored_kernel = SimulationKernelScript.new(restored_state, candidate_envelope.rng_seed)
	restored_kernel.restore_runtime_dict(_normalized_runtime(candidate_envelope))
	state = restored_state
	clock = restored_clock
	kernel = restored_kernel
	if not kernel.event_emitted.is_connected(_on_kernel_event):
		kernel.event_emitted.connect(_on_kernel_event)
	state_changed.emit(get_view_model())
	return true


func _stamp_current_writer_pair(state_snapshot: Dictionary) -> void:
	# The save boundary may upgrade only explicitly supported legacy snapshots.
	# Rejected migrations remain untouched and fail the semantic save gate.
	var migration := _migrate_state_snapshot_to_current_pair(state_snapshot)
	if not bool(migration.get("ok", false)):
		return
	var migrated_state: Dictionary = migration.get("state", {})
	state_snapshot.clear()
	state_snapshot.merge(migrated_state, true)


func _prepare_envelope_for_restore(envelope):
	# Work only on a deep clone. A rejected or failed migration cannot partially
	# mutate the caller's envelope or the live session.
	var candidate = SaveEnvelopeScript.from_dict(envelope.to_dict())
	if candidate == null:
		return null
	var migration := _migrate_state_snapshot_to_current_pair(candidate.state)
	if not bool(migration.get("ok", false)):
		return null
	var city_state_migration := CityStateScript.migrate_dict(migration.get("state", {}))
	if city_state_migration.is_empty():
		return null
	var population_normalization := _normalize_population_snapshot_for_restore(city_state_migration)
	if not bool(population_normalization.get("ok", false)):
		return null
	candidate.state = Dictionary(population_normalization.get("state", {})).duplicate(true)
	return candidate


func _normalize_population_snapshot_for_restore(state_snapshot: Dictionary) -> Dictionary:
	var normalized := state_snapshot.duplicate(true)
	var metadata_value: Variant = normalized.get("metadata", null)
	if not metadata_value is Dictionary:
		return {"ok": true, "state": normalized}
	var metadata: Dictionary = metadata_value
	var vertical_value: Variant = metadata.get("vertical_slice", null)
	if vertical_value == null:
		return {"ok": true, "state": normalized}
	if not vertical_value is Dictionary:
		return {"ok": false, "state": {}}
	var vertical: Dictionary = vertical_value
	var schema_value: Variant = vertical.get("schema_version", null)
	if not _is_integer_value(schema_value):
		return {"ok": false, "state": {}}
	var schema_version := int(schema_value)
	if not SaveSchemaAuthorityScript.is_supported_vertical_schema(schema_version):
		return {"ok": false, "state": {}}
	var population_value: Variant = vertical.get("population", null)
	if not population_value is Dictionary:
		return {"ok": false, "state": {}}
	var parsed_population = PopulationSystemScript.from_dict(population_value as Dictionary)
	if parsed_population == null:
		return {"ok": false, "state": {}}
	vertical["population"] = parsed_population.to_dict()
	metadata["vertical_slice"] = vertical
	normalized["metadata"] = metadata
	return {"ok": true, "state": normalized}


func _migrate_state_snapshot_to_current_pair(state_snapshot: Dictionary) -> Dictionary:
	var migrated_state := state_snapshot.duplicate(true)
	var metadata_value: Variant = migrated_state.get("metadata", null)
	if not metadata_value is Dictionary:
		return {"ok": true, "migrated": false, "state": migrated_state}
	var metadata: Dictionary = metadata_value
	var vertical_value: Variant = metadata.get("vertical_slice", null)
	if not vertical_value is Dictionary:
		return {"ok": true, "migrated": false, "state": migrated_state}
	var vertical: Dictionary = vertical_value
	var schema_value: Variant = vertical.get("schema_version", 0)
	if not _is_integer_value(schema_value):
		return {"ok": false, "migrated": false, "state": {}}
	var schema_version := int(schema_value)
	if not SaveSchemaAuthorityScript.is_supported_vertical_schema(schema_version):
		return {"ok": false, "migrated": false, "state": {}}
	var footprint_migration := _migrate_legacy_building_footprints(
		migrated_state,
		vertical,
		schema_version
	)
	if not bool(footprint_migration.get("ok", false)):
		return {"ok": false, "migrated": false, "state": {}}
	vertical = footprint_migration.get("vertical", vertical)
	metadata["vertical_slice"] = vertical
	migrated_state["metadata"] = metadata
	var footprints_migrated := bool(footprint_migration.get("migrated", false))
	# Schemas four through six remain direct-read compatible because they do not
	# contain enough current subsystem state to synthesize schema ten safely.
	# Their building records are normalized now and the coordinator writes schema
	# ten on the next save without guessing any historical footprint size.
	if schema_version < SaveSchemaAuthorityScript.LEGACY_MIGRATION_VERTICAL_SCHEMA_VERSION:
		return {"ok": true, "migrated": footprints_migrated, "state": migrated_state}
	var terrain_value: Variant = vertical.get("terrain", null)
	if not terrain_value is Dictionary:
		return {"ok": false, "migrated": false, "state": {}}
	var terrain: Dictionary = terrain_value
	var layout_value: Variant = terrain.get("layout_version", null)
	if not _is_integer_value(layout_value):
		return {"ok": false, "migrated": false, "state": {}}
	var layout_version := int(layout_value)
	if SaveSchemaAuthorityScript.validate_vertical_terrain_pair(schema_version, layout_version):
		return {"ok": true, "migrated": footprints_migrated, "state": migrated_state}
	if SaveSchemaAuthorityScript.is_transport_session_migration_pair(schema_version, layout_version):
		vertical["schema_version"] = SaveSchemaAuthorityScript.CURRENT_VERTICAL_SCHEMA_VERSION
		vertical["transport_planning_session"] = TransportPlanningSessionScript.inactive_snapshot()
		metadata["vertical_slice"] = vertical
		migrated_state["metadata"] = metadata
		return {"ok": true, "migrated": true, "state": migrated_state}
	if SaveSchemaAuthorityScript.is_footprint_migration_pair(schema_version, layout_version):
		vertical["schema_version"] = SaveSchemaAuthorityScript.CURRENT_VERTICAL_SCHEMA_VERSION
		vertical["transport_planning_session"] = TransportPlanningSessionScript.inactive_snapshot()
		metadata["vertical_slice"] = vertical
		migrated_state["metadata"] = metadata
		return {"ok": true, "migrated": true, "state": migrated_state}
	if not SaveSchemaAuthorityScript.is_legacy_migration_pair(schema_version, layout_version):
		return {"ok": false, "migrated": false, "state": {}}
	var migrated_terrain := CityTerrainMapScript.migrate_snapshot_to_current(terrain)
	if migrated_terrain.is_empty():
		return {"ok": false, "migrated": false, "state": {}}
	vertical["schema_version"] = SaveSchemaAuthorityScript.CURRENT_VERTICAL_SCHEMA_VERSION
	vertical["terrain"] = migrated_terrain
	vertical["transport_planning_session"] = TransportPlanningSessionScript.inactive_snapshot()
	metadata["vertical_slice"] = vertical
	migrated_state["metadata"] = metadata
	return {"ok": true, "migrated": true, "state": migrated_state}


func _migrate_legacy_building_footprints(
	state_snapshot: Dictionary,
	vertical: Dictionary,
	source_schema_version: int
) -> Dictionary:
	var terrain_mapping = CityTerrainMapScript.new()
	var buildings_value: Variant = state_snapshot.get("buildings", null)
	if not buildings_value is Dictionary:
		return {"ok": false}
	var buildings: Dictionary = buildings_value
	var migrated := false
	if source_schema_version < SaveSchemaAuthorityScript.TRANSPORT_SESSION_MIGRATION_VERTICAL_SCHEMA_VERSION:
		for building_key: Variant in buildings.keys():
			var record_value: Variant = buildings[building_key]
			if not record_value is Dictionary:
				return {"ok": false}
			var record: Dictionary = record_value
			var tile_value: Variant = record.get("tile_index", null)
			if not _is_integer_value(tile_value):
				return {"ok": false}
			var legacy_fields := BuildingFootprintsScript.legacy_single_fields(int(tile_value), terrain_mapping)
			if legacy_fields.is_empty():
				return {"ok": false}
			for field_name: String in legacy_fields.keys():
				record[field_name] = legacy_fields[field_name]
			buildings[building_key] = record
			migrated = true
		var construction_value: Variant = vertical.get("construction", null)
		if construction_value is Dictionary:
			var construction: Dictionary = construction_value
			var jobs_value: Variant = construction.get("jobs", null)
			if jobs_value is Dictionary:
				var jobs: Dictionary = jobs_value
				for job_key: Variant in jobs.keys():
					var job_value: Variant = jobs[job_key]
					if not job_value is Dictionary:
						return {"ok": false}
					var job: Dictionary = job_value
					var metadata_value: Variant = job.get("metadata", null)
					if not metadata_value is Dictionary:
						continue
					var job_metadata: Dictionary = metadata_value
					if not _is_building_construction_job(job, job_metadata):
						continue
					var tile_value: Variant = job_metadata.get("tile_index", null)
					if not _is_integer_value(tile_value):
						return {"ok": false}
					var job_fields := BuildingFootprintsScript.legacy_single_fields(int(tile_value), terrain_mapping)
					if job_fields.is_empty():
						return {"ok": false}
					for field_name: String in job_fields.keys():
						job_metadata[field_name] = job_fields[field_name]
					job["metadata"] = job_metadata
					jobs[job_key] = job
					var core_jobs_value: Variant = state_snapshot.get("construction_jobs", null)
					if core_jobs_value is Dictionary and (core_jobs_value as Dictionary).has(job_key):
						var core_job_value: Variant = (core_jobs_value as Dictionary)[job_key]
						if not core_job_value is Dictionary:
							return {"ok": false}
						var migrated_core_job := job.duplicate(true)
						migrated_core_job["job_id"] = str((core_job_value as Dictionary).get("job_id", job_key))
						(core_jobs_value as Dictionary)[job_key] = migrated_core_job
						state_snapshot["construction_jobs"] = core_jobs_value
					migrated = true
				construction["jobs"] = jobs
			vertical["construction"] = construction
	state_snapshot["buildings"] = buildings
	if not _validate_building_footprint_records_in_snapshot(buildings, terrain_mapping, true):
		return {"ok": false}
	return {"ok": true, "migrated": migrated, "vertical": vertical}


func save_now(path: String = "") -> Error:
	var resolved_path: String = path if not path.is_empty() else save_path
	if not _validate_runtime_population_save_boundary():
		save_service.last_error_message = "Refusing to save: runtime NPC data does not exactly match canonical population metadata."
		return ERR_INVALID_DATA
	var envelope = make_envelope()
	var validated_state = CityStateScript.from_dict(envelope.state)
	if validated_state == null or not _validate_envelope_semantics(envelope, validated_state):
		save_service.last_error_message = "Refusing to save a semantically inconsistent session snapshot."
		return ERR_INVALID_DATA
	return save_service.save_atomic(resolved_path, envelope)


func _validate_runtime_population_save_boundary() -> bool:
	var metadata_value: Variant = state.metadata.get("vertical_slice", null)
	if metadata_value == null:
		return state.npcs.is_empty()
	if not metadata_value is Dictionary:
		return false
	var population_value: Variant = (metadata_value as Dictionary).get("population", null)
	if population_value == null:
		return state.npcs.is_empty()
	if not population_value is Dictionary:
		return false
	var population: Dictionary = population_value
	if not PopulationSystemScript.validate_snapshot(population):
		return false
	# The metadata block was produced by PopulationSystem.to_dict(). Full snapshot
	# validation plus direct comparison avoids constructing a second 200k-object
	# PopulationSystem merely to validate the save boundary.
	var canonical_records: Array = population.get("records", [])
	if canonical_records.size() != state.npcs.size():
		return false
	for record_value: Variant in canonical_records:
		var record: Dictionary = record_value
		var npc_id := str(record.get("npc_id", ""))
		if npc_id.is_empty() or not state.npcs.has(npc_id):
			return false
		if _canonicalize(state.npcs[npc_id]) != _canonicalize(record):
			return false
	return true


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
	var state_snapshot: Dictionary = state.to_dict()
	_stamp_current_writer_pair(state_snapshot)
	return JSON.stringify(_canonicalize({
		"state": state_snapshot,
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
	return _validate_vertical_slice_metadata(restored_state, runtime)


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
	var seen_operation_ids: Dictionary = {}
	for operation_id: Variant in processed_value:
		if not operation_id is String or (operation_id as String).is_empty():
			return false
		if seen_operation_ids.has(operation_id):
			return false
		seen_operation_ids[operation_id] = true
	for raw_command: Variant in pending_value:
		if not raw_command is Dictionary:
			return false
		var command: Dictionary = raw_command
		var operation_id_value: Variant = command.get("operation_id", null)
		if not operation_id_value is String or (operation_id_value as String).is_empty():
			return false
		if seen_operation_ids.has(operation_id_value):
			return false
		seen_operation_ids[operation_id_value] = true
		if not command.get("command_type", null) is String or str(command["command_type"]).is_empty():
			return false
		if not command.get("payload", {}) is Dictionary:
			return false
		if not _is_integer_value(command.get("game_time", 0)) or not _is_integer_value(command.get("ordinal", 0)):
			return false
		var ordinal := int(command.get("ordinal", 0))
		if int(command.get("game_time", 0)) < 0 or ordinal < 0 or ordinal > command_limit:
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


func _validate_vertical_slice_metadata(restored_state, runtime: Dictionary) -> bool:
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
	if not SaveSchemaAuthorityScript.is_supported_vertical_schema(schema_version):
		return false
	# Schema 4 adds an optional persisted UI-event latch. Older saves omit it;
	# current saves must keep it string-typed and inside the governance failure
	# vocabulary so a forged value cannot suppress or invent terminal events.
	if vertical.has("terminal_failure_event_reason"):
		var terminal_reason: Variant = vertical["terminal_failure_event_reason"]
		if not terminal_reason is String or str(terminal_reason) not in TERMINAL_FAILURE_REASONS:
			return false
	if not _validate_core_building_records(
		restored_state,
		schema_version >= 6,
		schema_version >= SaveSchemaAuthorityScript.CURRENT_VERTICAL_SCHEMA_VERSION
	):
		return false
	var population_value: Variant = vertical.get("population", null)
	if not population_value is Dictionary:
		return false
	var population: Dictionary = population_value
	var parsed_population = PopulationSystemScript.from_dict(population)
	if parsed_population == null:
		return false
	var normalized_population: Dictionary = parsed_population.to_dict()
	var records_value: Variant = normalized_population.get("records", null)
	var canonical_ids: Dictionary = {}
	var canonical_records: Dictionary = {}
	for record_value: Variant in records_value:
		var record: Dictionary = record_value
		var npc_id := str(record.get("npc_id", ""))
		if npc_id.is_empty() or canonical_ids.has(npc_id):
			return false
		canonical_ids[npc_id] = true
		canonical_records[npc_id] = record
	if canonical_ids.size() != restored_state.npcs.size():
		return false
	for core_id: Variant in restored_state.npcs.keys():
		var npc_id := str(core_id)
		if not canonical_ids.has(npc_id):
			return false
		if _canonicalize(restored_state.npcs[core_id]) != _canonicalize(canonical_records[npc_id]):
			return false
	var requests_value: Variant = normalized_population.get("requests", [])
	if not requests_value is Array:
		return false
	for request_value: Variant in requests_value:
		if not request_value is Dictionary:
			return false
		var request_npc_id := str((request_value as Dictionary).get("npc_id", ""))
		if not request_npc_id.is_empty() and not canonical_ids.has(request_npc_id):
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
	# Schema 6 makes construction, blueprint selection, and the player-authored
	# transport network authoritative. Schema 7 adds the complete terrain snapshot
	# and asynchronous terrain-job cross-links. Schema 8 atomically pairs that
	# snapshot with backdrop-authoritative terrain layout 3. Earlier schemas retain
	# their established migration paths in VerticalSliceCoordinator.
	if schema_version >= 6:
		if runtime.is_empty() or not _validate_current_vertical_sequences(vertical, restored_state, runtime):
			return false
		if not _validate_current_vertical_non_transport(vertical, restored_state):
			return false
		var transport_value: Variant = vertical.get("transport", null)
		if not transport_value is Dictionary:
			return false
		var transport_validation: Dictionary = TransportNetworkSystemScript.validate_snapshot(transport_value as Dictionary)
		if not bool(transport_validation.get("valid", false)):
			return false
		if not _validate_transport_construction_links(vertical, restored_state):
			return false
		if (
			schema_version >= SaveSchemaAuthorityScript.TRANSPORT_SESSION_MIGRATION_VERTICAL_SCHEMA_VERSION
			and not _validate_building_construction_footprints(vertical)
		):
			return false
		if schema_version >= SaveSchemaAuthorityScript.CURRENT_VERTICAL_SCHEMA_VERSION:
			var planning_value: Variant = vertical.get("transport_planning_session", null)
			if not planning_value is Dictionary:
				return false
			var planning_validation: Dictionary = TransportPlanningSessionScript.validate_snapshot(
				planning_value as Dictionary
			)
			if not bool(planning_validation.get("valid", false)):
				return false
			var planning_reference_validation: Dictionary = TransportPlanningSessionScript.validate_references(
				planning_value as Dictionary,
				vertical.get("construction", {}),
				transport_value as Dictionary
			)
			if not bool(planning_reference_validation.get("valid", false)):
				return false
	if schema_version >= 7:
		var terrain_value: Variant = vertical.get("terrain", null)
		if not terrain_value is Dictionary:
			return false
		var terrain_validation: Dictionary = CityTerrainMapScript.validate_snapshot(terrain_value as Dictionary)
		if not bool(terrain_validation.get("valid", false)):
			return false
		if not SaveSchemaAuthorityScript.validate_vertical_terrain_pair(
			schema_version,
			int((terrain_value as Dictionary).get("layout_version", -1))
		):
			return false
		if not _validate_terrain_construction_links(vertical, restored_state):
			return false
	return true


func _validate_core_building_records(
	restored_state,
	require_current_status: bool,
	require_footprints: bool
) -> bool:
	for building_value: Variant in restored_state.buildings.values():
		if not building_value is Dictionary:
			return false
		if not require_current_status:
			continue
		var status_value: Variant = (building_value as Dictionary).get("status", null)
		if not status_value is String or str(status_value) not in ["active", "demolition", "scrapped"]:
			return false
	return _validate_building_footprint_records_in_snapshot(
		restored_state.buildings,
		CityTerrainMapScript.new(),
		require_footprints
	)


func _validate_building_footprint_records_in_snapshot(
	buildings: Dictionary,
	terrain_mapping,
	require_footprints: bool
) -> bool:
	var occupied_owners: Dictionary = {}
	for building_key: Variant in buildings.keys():
		var record_value: Variant = buildings[building_key]
		if not record_value is Dictionary:
			return false
		var record: Dictionary = record_value
		var has_any_footprint_field := (
			record.has("anchor_tile_id")
			or record.has("footprint_id")
			or record.has("occupied_tile_ids")
		)
		if not require_footprints and not has_any_footprint_field:
			continue
		var validation := BuildingFootprintsScript.validate_persisted_record(record, terrain_mapping)
		if not bool(validation.get("valid", false)):
			return false
		for tile_id: int in validation.get("occupied_tile_ids", []):
			if occupied_owners.has(tile_id):
				return false
			occupied_owners[tile_id] = str(building_key)
	return true


func _validate_building_construction_footprints(vertical: Dictionary) -> bool:
	var construction_value: Variant = vertical.get("construction", null)
	if not construction_value is Dictionary:
		return false
	var jobs_value: Variant = (construction_value as Dictionary).get("jobs", null)
	if not jobs_value is Dictionary:
		return false
	var terrain_mapping = CityTerrainMapScript.new()
	for job_value: Variant in (jobs_value as Dictionary).values():
		if not job_value is Dictionary:
			return false
		var job: Dictionary = job_value
		var metadata_value: Variant = job.get("metadata", null)
		if not metadata_value is Dictionary:
			return false
		var metadata: Dictionary = metadata_value
		if not _is_building_construction_job(job, metadata):
			continue
		var validation := BuildingFootprintsScript.validate_persisted_record(
			metadata,
			terrain_mapping,
			str(job.get("blueprint", {}).get("size_tier", ""))
		)
		if not bool(validation.get("valid", false)):
			return false
	return true


func _is_building_construction_job(job: Dictionary, metadata: Dictionary) -> bool:
	return (
		str(job.get("operation", "")) == "build"
		and str(metadata.get("entity_kind", "")) not in [
			"transport_project",
			ConstructionSystemScript.TERRAIN_FLATTEN_ENTITY_KIND,
		]
		and not str(metadata.get("building_name", "")).is_empty()
	)


func _validate_current_vertical_sequences(vertical: Dictionary, restored_state, runtime: Dictionary) -> bool:
	var next_building_value: Variant = vertical.get("next_building_sequence", null)
	if not _is_integer_value(next_building_value) or int(next_building_value) < 1:
		return false
	var highest_building_sequence := 0
	for building_key: Variant in restored_state.buildings.keys():
		var building_id := str(building_key)
		if not building_id.begins_with("building_"):
			continue
		var suffix := building_id.trim_prefix("building_")
		if suffix.is_valid_int():
			highest_building_sequence = maxi(highest_building_sequence, int(suffix))
	if int(next_building_value) <= highest_building_sequence:
		return false

	var next_operation_value: Variant = vertical.get("next_operation_sequence", null)
	if not _is_integer_value(next_operation_value) or int(next_operation_value) < 1:
		return false
	var highest_operation_sequence := 0
	for operation_id: Variant in runtime.get("processed_operation_ids", []):
		highest_operation_sequence = maxi(highest_operation_sequence, _coordinator_operation_sequence(str(operation_id)))
	for pending_value: Variant in runtime.get("pending_commands", []):
		if pending_value is Dictionary:
			highest_operation_sequence = maxi(
				highest_operation_sequence,
				_coordinator_operation_sequence(str((pending_value as Dictionary).get("operation_id", "")))
			)
	return int(next_operation_value) > highest_operation_sequence


func _coordinator_operation_sequence(operation_id: String) -> int:
	if not operation_id.begins_with("coord_"):
		return 0
	var separator_index := operation_id.rfind("_")
	if separator_index < 0 or separator_index >= operation_id.length() - 1:
		return 0
	var suffix := operation_id.substr(separator_index + 1)
	if suffix.length() != 10 or not suffix.is_valid_int():
		return 0
	return maxi(0, int(suffix))


func _validate_current_vertical_non_transport(vertical: Dictionary, restored_state) -> bool:
	var construction_value: Variant = vertical.get("construction", null)
	if not construction_value is Dictionary:
		return false
	var construction: Dictionary = construction_value
	var construction_validation: Dictionary = ConstructionSystemScript.validate_snapshot(construction)
	if not bool(construction_validation.get("valid", false)):
		return false
	var blueprint_validation: Dictionary = BlueprintLibraryServiceScript.validate_snapshot(
		vertical.get("next_blueprint_sequence", null),
		vertical.get("blueprint_library", null),
		vertical.get("active_blueprint_by_building", null)
	)
	if not bool(blueprint_validation.get("valid", false)):
		return false
	return (
		_validate_blueprint_construction_links(vertical, construction)
		and _validate_construction_core_mirror(construction, restored_state)
		and _validate_building_demolition_jobs(construction, restored_state)
		and _validate_active_construction_capacity_and_tiles(construction, restored_state)
	)


func _validate_blueprint_construction_links(vertical: Dictionary, construction: Dictionary) -> bool:
	var next_sequence := int(vertical.get("next_blueprint_sequence", 0))
	var library: Dictionary = vertical.get("blueprint_library", {})
	var reviews: Dictionary = construction.get("reviews", {})
	var jobs: Dictionary = construction.get("jobs", {})
	var highest_generated_sequence := 0
	for entry_value: Variant in library.values():
		var entry: Dictionary = entry_value
		var blueprint: Dictionary = entry.get("blueprint", {})
		highest_generated_sequence = maxi(
			highest_generated_sequence,
			_generated_blueprint_sequence(str(blueprint.get("id", "")))
		)
		if str(entry.get("source", "")) != "player":
			continue
		var review_id := str(entry.get("review_id", ""))
		if review_id.is_empty() or not reviews.has(review_id) or not reviews[review_id] is Dictionary:
			return false
		var review: Dictionary = reviews[review_id]
		if (
			str(review.get("id", "")) != review_id
			or str(review.get("status", "")) not in ["approved", "in_construction", "completed"]
			or int(entry.get("approved_sequence", -1)) != int(review.get("sequence", -2))
			or int(entry.get("approved_day", -1)) != int(review.get("resolved_day", -2))
			or _canonicalize(entry.get("blueprint", {})) != _canonicalize(review.get("blueprint", {}))
		):
			return false
	for review_value: Variant in reviews.values():
		var review: Dictionary = review_value
		var review_blueprint: Dictionary = review.get("blueprint", {})
		var blueprint_id := str(review_blueprint.get("id", ""))
		highest_generated_sequence = maxi(highest_generated_sequence, _generated_blueprint_sequence(blueprint_id))
		if str(review.get("status", "")) not in ["approved", "in_construction", "completed"]:
			continue
		var library_id := "approved_%s" % blueprint_id
		if not library.has(library_id) or not library[library_id] is Dictionary:
			return false
		if str((library[library_id] as Dictionary).get("review_id", "")) != str(review.get("id", "")):
			return false
	for job_value: Variant in jobs.values():
		var job: Dictionary = job_value
		var job_blueprint: Dictionary = job.get("blueprint", {})
		highest_generated_sequence = maxi(
			highest_generated_sequence,
			_generated_blueprint_sequence(str(job_blueprint.get("id", "")))
		)
	return next_sequence > highest_generated_sequence


func _generated_blueprint_sequence(blueprint_id: String) -> int:
	if not blueprint_id.begins_with("blueprint_"):
		return 0
	var suffix := blueprint_id.trim_prefix("blueprint_")
	if suffix.is_empty() or not suffix.is_valid_int():
		return 0
	return maxi(0, int(suffix))


func _validate_construction_core_mirror(construction: Dictionary, restored_state) -> bool:
	var active_jobs: Dictionary = {}
	var subsystem_jobs: Dictionary = construction.get("jobs", {})
	for job_key: Variant in subsystem_jobs.keys():
		var job: Dictionary = subsystem_jobs[job_key]
		if str(job.get("status", "")) == "active":
			active_jobs[str(job_key)] = job
	var core_jobs: Dictionary = {}
	for core_key: Variant in restored_state.construction_jobs.keys():
		var core_value: Variant = restored_state.construction_jobs[core_key]
		if not core_value is Dictionary:
			return false
		var core_job: Dictionary = Dictionary(core_value).duplicate(true)
		# SimulationKernel._upsert_record() adds the command-layer identity field
		# to the core mirror. ConstructionSystem owns `id`; both identities must
		# agree, then the remaining authoritative payload must match exactly.
		if str(core_job.get("job_id", "")) != str(core_key):
			return false
		core_job.erase("job_id")
		core_jobs[str(core_key)] = core_job
	return _canonicalize(active_jobs) == _canonicalize(core_jobs)


func _validate_building_demolition_jobs(construction: Dictionary, restored_state) -> bool:
	var demolition_counts: Dictionary = {}
	var subsystem_jobs: Dictionary = construction.get("jobs", {})
	for job_value: Variant in subsystem_jobs.values():
		var job: Dictionary = job_value
		if str(job.get("status", "")) != "active" or str(job.get("operation", "")) != "demolish":
			continue
		var metadata: Dictionary = job.get("metadata", {})
		if str(metadata.get("entity_kind", "")) == "transport_project":
			continue
		var target_id := str(job.get("target_id", ""))
		if target_id.is_empty() or not restored_state.buildings.has(target_id):
			return false
		demolition_counts[target_id] = int(demolition_counts.get(target_id, 0)) + 1
		if int(demolition_counts[target_id]) > 1:
			return false
	for building_key: Variant in restored_state.buildings.keys():
		var building: Dictionary = restored_state.buildings[building_key]
		var building_id := str(building_key)
		var demolition_job_count := int(demolition_counts.get(building_id, 0))
		if (str(building.get("status", "")) == "demolition") != (demolition_job_count == 1):
			return false
	return true


func _validate_active_construction_capacity_and_tiles(construction: Dictionary, restored_state) -> bool:
	var allocated_workers := 0
	var tile_owners: Dictionary = {}
	var jobs: Dictionary = construction.get("jobs", {})
	for job_key: Variant in jobs.keys():
		var job: Dictionary = jobs[job_key]
		if str(job.get("status", "")) != "active":
			continue
		var metadata: Dictionary = job.get("metadata", {})
		allocated_workers += int(job.get("worker_count", 0))
		if allocated_workers > ConstructionSystemScript.MAX_WORKERS:
			return false
		var tile_ids_value: Variant = _validated_active_job_tile_ids(job)
		if tile_ids_value == null:
			return false
		var tile_ids: Array[int] = tile_ids_value
		for tile_id: int in tile_ids:
			if tile_owners.has(tile_id):
				return false
			tile_owners[tile_id] = str(job_key)
			if str(job.get("operation", "")) == "build" and not _core_building_id_at_tile(restored_state, tile_id).is_empty():
				return false
		if str(metadata.get("entity_kind", "")) != "transport_project" and str(job.get("operation", "")) in ["demolish", "move"]:
			if str(job.get("operation", "")) == "move":
				# The scheduler still exposes the legacy operation token, but the
				# coordinator has no authoritative source/destination completion path.
				return false
			var target_id := str(job.get("target_id", ""))
			if not restored_state.buildings.has(target_id):
				return false
			var target: Dictionary = restored_state.buildings[target_id]
			if tile_ids.size() != 1 or int(target.get("tile_index", -1)) != tile_ids[0]:
				return false
	return true


func _core_building_id_at_tile(restored_state, tile_id: int) -> String:
	for building_key: Variant in restored_state.buildings.keys():
		var building_value: Variant = restored_state.buildings[building_key]
		if not building_value is Dictionary:
			continue
		var building: Dictionary = building_value
		var occupied_value: Variant = building.get("occupied_tile_ids", null)
		if occupied_value is Array:
			for occupied_variant: Variant in occupied_value:
				if _is_integer_value(occupied_variant) and int(occupied_variant) == tile_id:
					return str(building_key)
		elif int(building.get("tile_index", -1)) == tile_id:
			return str(building_key)
	return ""


func _validated_active_job_tile_ids(job: Dictionary) -> Variant:
	var metadata_value: Variant = job.get("metadata", null)
	if not metadata_value is Dictionary:
		return null
	var metadata: Dictionary = metadata_value
	var result: Array[int] = []
	if str(metadata.get("entity_kind", "")) == "transport_project":
		var multiple_value: Variant = metadata.get("tile_indices", null)
		if not multiple_value is Array or (multiple_value as Array).is_empty():
			return null
		for tile_variant: Variant in multiple_value:
			if not _is_integer_value(tile_variant):
				return null
			var tile_id := int(tile_variant)
			if tile_id < 0 or tile_id >= CityTerrainMapScript.CELL_COUNT or result.has(tile_id):
				return null
			result.append(tile_id)
	elif _is_building_construction_job(job, metadata) and metadata.has("footprint_id"):
		var validation := BuildingFootprintsScript.validate_persisted_record(
			metadata,
			CityTerrainMapScript.new(),
			str(job.get("blueprint", {}).get("size_tier", ""))
		)
		if not bool(validation.get("valid", false)):
			return null
		for tile_id: int in validation.get("occupied_tile_ids", []):
			result.append(tile_id)
	else:
		var tile_value: Variant = metadata.get("tile_index", null)
		if not _is_integer_value(tile_value):
			return null
		var tile_id := int(tile_value)
		if tile_id < 0 or tile_id >= CityTerrainMapScript.CELL_COUNT:
			return null
		result.append(tile_id)
	result.sort()
	return result


func _validate_terrain_construction_links(vertical: Dictionary, restored_state) -> bool:
	var terrain_snapshot: Dictionary = vertical.get("terrain", {})
	var terrain_map = CityTerrainMapScript.create_from_dict(terrain_snapshot)
	for building_value: Variant in restored_state.buildings.values():
		if not building_value is Dictionary:
			return false
		var footprint_validation := BuildingFootprintsScript.validate_persisted_record(
			building_value as Dictionary,
			terrain_map
		)
		if not bool(footprint_validation.get("valid", false)):
			return false
		for occupied_tile_id: int in footprint_validation.get("occupied_tile_ids", []):
			if not terrain_map.is_buildable(occupied_tile_id):
				return false
	var construction: Dictionary = vertical.get("construction", {})
	var jobs: Dictionary = construction.get("jobs", {})
	for job_value: Variant in jobs.values():
		if not job_value is Dictionary:
			return false
		var job: Dictionary = job_value
		var metadata_value: Variant = job.get("metadata", null)
		if not metadata_value is Dictionary:
			return false
		var metadata: Dictionary = metadata_value
		if str(job.get("status", "")) == "active" and _is_building_construction_job(job, metadata):
			var footprint_tiles_value: Variant = _validated_active_job_tile_ids(job)
			if footprint_tiles_value == null:
				return false
			for occupied_tile_id: int in footprint_tiles_value:
				if not terrain_map.is_buildable(occupied_tile_id):
					return false
		if str(metadata.get("entity_kind", "")) != ConstructionSystemScript.TERRAIN_FLATTEN_ENTITY_KIND:
			continue
		if str(job.get("operation", "")) != "build" or not str(job.get("review_id", "")).is_empty():
			return false
		var tile_value: Variant = metadata.get("tile_index", null)
		if not _is_integer_value(tile_value):
			return false
		var tile_id := int(tile_value)
		if not terrain_map.is_valid_tile_id(tile_id):
			return false
		var source_kind := str(metadata.get("source_terrain_kind", ""))
		if terrain_map.base_kind(tile_id) != source_kind:
			return false
		var fixed_cost_value: Variant = metadata.get("fixed_cost", null)
		var labor_cost_value: Variant = metadata.get("labor_cost", null)
		if not _is_integer_value(fixed_cost_value) or not _is_integer_value(labor_cost_value):
			return false
		var blueprint_value: Variant = job.get("blueprint", null)
		if not blueprint_value is Dictionary:
			return false
		var blueprint: Dictionary = blueprint_value
		var expected_blueprint := ConstructionSystemScript.terrain_flatten_blueprint(
			tile_id,
			source_kind,
			int(fixed_cost_value),
			int(blueprint.get("requested_workers", 0))
		)
		var expected_metadata := ConstructionSystemScript.terrain_flatten_metadata(
			tile_id,
			source_kind,
			int(fixed_cost_value),
			int(labor_cost_value)
		)
		if (
			str(job.get("target_id", "")) != ConstructionSystemScript.terrain_flatten_target_id(tile_id)
			or _canonicalize(blueprint) != _canonicalize(expected_blueprint)
			or _canonicalize(metadata) != _canonicalize(expected_metadata)
		):
			return false
		var status := str(job.get("status", ""))
		if status == "active":
			if (
				terrain_map.is_flattened(tile_id)
				or not terrain_map.is_flattenable(tile_id)
				or not _core_building_id_at_tile(restored_state, tile_id).is_empty()
			):
				return false
		elif status == "completed" and not terrain_map.is_flattened(tile_id):
			return false
	return true


func _validate_transport_construction_links(vertical: Dictionary, restored_state) -> bool:
	var construction: Dictionary = vertical.get("construction", {})
	var transport: Dictionary = vertical.get("transport", {})
	var jobs: Dictionary = construction.get("jobs", {})
	var projects: Dictionary = transport.get("projects", {})
	var active_jobs_by_project: Dictionary = {}
	for job_key: Variant in jobs.keys():
		var job: Dictionary = jobs[job_key]
		if str(job.get("status", "")) != "active":
			continue
		var metadata: Dictionary = job.get("metadata", {})
		if str(metadata.get("entity_kind", "")) != "transport_project":
			continue
		var project_id := str(metadata.get("transport_project_id", ""))
		if (
			project_id.is_empty()
			or str(metadata.get("project_id", "")) != project_id
			or str(job.get("target_id", "")) != project_id
			or active_jobs_by_project.has(project_id)
			or not projects.has(project_id)
			or not projects[project_id] is Dictionary
		):
			return false
		var project: Dictionary = projects[project_id]
		var expected_kind := _transport_project_snapshot_kind(project, transport)
		if (
			str(project.get("status", "")) != "under_construction"
			or str(project.get("operation", "")) != str(job.get("operation", ""))
			or expected_kind.is_empty()
			or str(job.get("review_id", "")) != ""
		):
			return false
		var expected_tiles := _transport_project_snapshot_tile_ids(project, transport)
		var actual_tiles_value: Variant = _validated_active_job_tile_ids(job)
		if actual_tiles_value == null or expected_tiles.is_empty():
			return false
		var actual_tiles: Array[int] = actual_tiles_value
		if actual_tiles != expected_tiles:
			return false
		var blueprint_value: Variant = job.get("blueprint", null)
		if not blueprint_value is Dictionary:
			return false
		var blueprint: Dictionary = blueprint_value
		var initial_workers_value: Variant = blueprint.get("requested_workers", null)
		if not _is_integer_value(initial_workers_value):
			return false
		var initial_workers := int(initial_workers_value)
		var expected_blueprint := ConstructionSystemScript.infrastructure_blueprint(
			str(project.get("operation", "")),
			expected_kind,
			expected_tiles.size(),
			initial_workers
		)
		var expected_metadata := {
			"project_id": project_id,
			"transport_project_id": project_id,
			"transport_kind": expected_kind,
			"source_decision_id": str((project.get("plan", {}) as Dictionary).get("source_decision_id", "")),
			"entity_kind": "transport_project",
			"infrastructure_kind": expected_kind,
			"tile_indices": expected_tiles.duplicate(),
		}
		if (
			expected_blueprint.is_empty()
			or _canonicalize(blueprint) != _canonicalize(expected_blueprint)
			or _canonicalize(metadata) != _canonicalize(expected_metadata)
			or int(job.get("projected_total_days", -1)) != ConstructionSystemScript.duration_days(
				float(expected_blueprint.get("workload", 0.0)), initial_workers
			)
			or int(job.get("projected_labor_cost", -1)) != ConstructionSystemScript.total_labor_cost(
				float(expected_blueprint.get("workload", 0.0)), initial_workers
			)
			or int(job.get("projected_remaining_days", -1)) != ConstructionSystemScript.duration_days(
				float(job.get("remaining_work", 0.0)), int(job.get("worker_count", 0))
			)
		):
			return false
		active_jobs_by_project[project_id] = str(job_key)

	for project_key: Variant in projects.keys():
		var project: Dictionary = projects[project_key]
		var status := str(project.get("status", ""))
		if status == "planned":
			# Coordinator starts a planned project and its construction job in one
			# synchronous command. A detached persisted plan would reserve tiles forever.
			return false
		if status == "under_construction" and not active_jobs_by_project.has(str(project_key)):
			return false
		if status == "completed" and active_jobs_by_project.has(str(project_key)):
			return false
	return _validate_external_transport_station_mirror(transport, restored_state)


func _transport_project_snapshot_kind(project: Dictionary, transport: Dictionary) -> String:
	var kinds: Dictionary = {}
	var plan: Dictionary = project.get("plan", {})
	if str(project.get("operation", "")) == "build":
		for segment_value: Variant in plan.get("segments", []):
			if not segment_value is Dictionary:
				return ""
			kinds[str((segment_value as Dictionary).get("kind", ""))] = true
		for facility_value: Variant in plan.get("facilities", []):
			if not facility_value is Dictionary:
				return ""
			kinds[str((facility_value as Dictionary).get("kind", ""))] = true
		# Stations are authoritative building projects in the coordinator, not
		# scheduler infrastructure jobs.
		if not Array(plan.get("stations", [])).is_empty():
			return ""
	else:
		for collection_spec: Dictionary in [
			{"ids": plan.get("segment_ids", []), "records": transport.get("segments", {})},
			{"ids": plan.get("facility_ids", []), "records": transport.get("facilities", {})},
		]:
			var records: Dictionary = collection_spec["records"]
			for record_id: Variant in collection_spec["ids"]:
				var record_value: Variant = records.get(str(record_id), null)
				if not record_value is Dictionary:
					return ""
				kinds[str((record_value as Dictionary).get("kind", ""))] = true
		if not Array(plan.get("station_ids", [])).is_empty():
			return ""
	if kinds.size() != 1:
		return ""
	var kind := str(kinds.keys()[0])
	if kind not in TransportModesScript.SEGMENT_KINDS and kind not in TransportModesScript.FACILITY_KINDS:
		return ""
	return kind


func _transport_project_snapshot_tile_ids(project: Dictionary, transport: Dictionary) -> Array[int]:
	var result: Array[int] = []
	var plan: Dictionary = project.get("plan", {})
	if str(project.get("operation", "")) == "build":
		for segment_value: Variant in plan.get("segments", []):
			if not segment_value is Dictionary:
				return []
			for tile_variant: Variant in (segment_value as Dictionary).get("tile_path", []):
				_append_unique_snapshot_tile(result, tile_variant)
		for facility_value: Variant in plan.get("facilities", []):
			if not facility_value is Dictionary:
				return []
			_append_unique_snapshot_tile(result, (facility_value as Dictionary).get("tile_id", null))
		for station_value: Variant in plan.get("stations", []):
			if not station_value is Dictionary:
				return []
			_append_unique_snapshot_tile(result, (station_value as Dictionary).get("tile_id", null))
	else:
		for segment_id: Variant in plan.get("segment_ids", []):
			var segment_value: Variant = Dictionary(transport.get("segments", {})).get(str(segment_id), null)
			if not segment_value is Dictionary:
				return []
			for tile_variant: Variant in (segment_value as Dictionary).get("tile_path", []):
				_append_unique_snapshot_tile(result, tile_variant)
		for collection_spec: Dictionary in [
			{"ids": plan.get("facility_ids", []), "records": transport.get("facilities", {})},
			{"ids": plan.get("station_ids", []), "records": transport.get("stations", {})},
		]:
			var records: Dictionary = collection_spec["records"]
			for record_id: Variant in collection_spec["ids"]:
				var record_value: Variant = records.get(str(record_id), null)
				if not record_value is Dictionary:
					return []
				_append_unique_snapshot_tile(result, (record_value as Dictionary).get("tile_id", null))
	result.sort()
	return result


func _append_unique_snapshot_tile(result: Array[int], tile_value: Variant) -> void:
	if not _is_integer_value(tile_value):
		return
	var tile_id := int(tile_value)
	if tile_id >= 0 and tile_id < CityTerrainMapScript.CELL_COUNT and not result.has(tile_id):
		result.append(tile_id)


func _validate_external_transport_station_mirror(transport: Dictionary, restored_state) -> bool:
	var stations: Dictionary = transport.get("stations", {})
	for station_key: Variant in stations.keys():
		var station_value: Variant = stations[station_key]
		if not station_value is Dictionary:
			return false
		var station: Dictionary = station_value
		if str(station.get("project_id", "")) != "external":
			continue
		if (
			not station.get("status", null) is String
			or str(station["status"]) != "completed"
			or not station.get("building_name", null) is String
			or str(station["building_name"]) not in TransportModesScript.STATION_KINDS
			or not _is_integer_value(station.get("tile_id", null))
			or int(station["tile_id"]) < 0
			or int(station["tile_id"]) >= CityTerrainMapScript.CELL_COUNT
		):
			return false
		var building_value: Variant = restored_state.buildings.get(str(station_key), null)
		if not building_value is Dictionary:
			return false
		var building: Dictionary = building_value
		if (
			not building.get("building_id", null) is String
			or str(building["building_id"]) != str(station_key)
			or not building.get("building_name", null) is String
			or str(building["building_name"]) != str(station["building_name"])
			or not building.get("status", null) is String
			or str(building["status"]) == "scrapped"
			or not _is_integer_value(building.get("tile_index", null))
			or int(building["tile_index"]) != int(station["tile_id"])
		):
			return false
	for building_key: Variant in restored_state.buildings.keys():
		var building: Dictionary = restored_state.buildings[building_key]
		if (
			str(building.get("building_name", "")) not in TransportModesScript.STATION_KINDS
			or str(building.get("status", "active")) == "scrapped"
		):
			continue
		if not stations.has(str(building_key)) or not stations[str(building_key)] is Dictionary:
			return false
		var station: Dictionary = stations[str(building_key)]
		if (
			str(station.get("project_id", "")) != "external"
			or not station.get("status", null) is String
			or str(station["status"]) != "completed"
			or not building.get("building_id", null) is String
			or str(building["building_id"]) != str(building_key)
			or not building.get("building_name", null) is String
			or not building.get("status", null) is String
			or not _is_integer_value(building.get("tile_index", null))
			or not station.get("building_name", null) is String
			or str(station["building_name"]) != str(building["building_name"])
			or not _is_integer_value(station.get("tile_id", null))
			or int(station["tile_id"]) != int(building["tile_index"])
		):
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
