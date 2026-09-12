extends SceneTree

const CoordinatorScript = preload("res://scripts/app/vertical_slice_coordinator.gd")
const CityStateScript = preload("res://scripts/core/city_state.gd")
const ConstructionSystemScript = preload("res://scripts/systems/city/construction_system.gd")
const SaveSchemaAuthorityScript = preload("res://scripts/core/save_schema_authority.gd")
const CityTerrainMapScript = preload("res://scripts/world/city_terrain_map.gd")
const LAYOUT2_FIXTURE_PATH := "res://tests/fixtures/save_schema/supported_legacy_migration.json"

const CURRENT_SCHEMA_PAIR := Vector2i(
	SaveSchemaAuthorityScript.CURRENT_VERTICAL_SCHEMA_VERSION,
	SaveSchemaAuthorityScript.CURRENT_TERRAIN_LAYOUT_VERSION
)

const MID_JOB_SAVE_PATH := "user://goal_2026_08_01/terrain_flatten_mid_job.json"
const COMPLETED_SAVE_PATH := "user://goal_2026_08_01/terrain_flatten_completed.json"
const LEGACY_SAVE_PATH := "user://goal_2026_08_01/terrain_flatten_legacy.json"

var _failed := false
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_saves()
	_test_async_flatten_lifecycle()
	_test_pre_schema_five_migration()
	_cleanup_saves()
	if not _failed:
		print("Terrain flatten lifecycle integration test passed. Checks=%d" % _checks)
	quit(1 if _failed else 0)


func _test_async_flatten_lifecycle() -> void:
	var coordinator = CoordinatorScript.new(8_020_701, 500_000)
	var tile_id := _first_matching_layout2_nonflat_tile(coordinator, "trees")
	var initial_terrain: Dictionary = coordinator.terrain_state_for_tile(tile_id)
	_check(tile_id >= 0 and str(initial_terrain.get("base_kind", "")) == "trees", "fixture is not backdrop-derived woodland")
	_check(not Array(initial_terrain.get("backdrop_feature_ids", [])).is_empty(), "woodland fixture has no backdrop feature provenance")
	_check(not bool(initial_terrain.get("buildable", true)), "fixture starts buildable")

	var quote: Dictionary = coordinator.terrain_flatten_quote(tile_id)
	_check(bool(quote.get("ok", false)), "terrain quote succeeds")
	_check(int(quote.get("base_cost", -1)) == int(quote.get("fixed_cost", -2)), "base and fixed quote aliases disagree")
	_check(int(quote.get("worker_count", 0)) > 0, "quote omits worker count")
	_check(int(quote.get("available_workers", 0)) == 20, "quote omits available workers")
	_check(int(quote.get("duration_days", 0)) > 1, "quote does not expose a multi-day duration")
	_check(int(quote.get("labor_cost", 0)) > 0, "quote omits labor cost")
	_check(int(quote.get("total_cost", 0)) == int(quote.get("fixed_cost", 0)) + int(quote.get("labor_cost", 0)), "quote total is not fixed plus labor")
	_check(bool(quote.get("can_afford", false)) and bool(quote.get("can_start", false)), "affordable idle terrain cannot start")

	var funds_before := int(coordinator.treasury_balance())
	var started: Dictionary = coordinator.flatten_terrain(tile_id)
	_check(bool(started.get("ok", false)), "terrain flatten job starts")
	if not bool(started.get("ok", false)):
		return
	var job: Dictionary = started.get("job", {})
	var job_id := str(job.get("id", ""))
	var duration_days := int(job.get("projected_total_days", 0))
	var total_cost := int(quote.get("total_cost", 0))
	_check(str(job.get("operation", "")) == "build", "terrain scheduler operation is not build")
	_check(str(job.get("review_id", "")) == "", "terrain job unexpectedly links a blueprint review")
	_check(str(job.get("target_id", "")) == "terrain_tile_%03d" % tile_id, "terrain job target is not deterministic")
	_check(str(job.get("metadata", {}).get("entity_kind", "")) == "terrain_flatten", "terrain job metadata is not canonical")
	_check(coordinator.treasury_balance() == funds_before - total_cost, "terrain start did not deduct the quote exactly once")
	_check(_ledger_count(coordinator, "construction.terrain_flatten_total_cost") == 1, "terrain start did not create exactly one prepaid ledger entry")
	_check(not coordinator.terrain_map.is_flattened(tile_id), "terrain flattened at job start")
	_check(not coordinator.terrain_map.is_buildable(tile_id), "terrain became buildable at job start")
	_check(not coordinator.terrain_map.is_walkable(tile_id), "terrain became walkable at job start")
	_check(coordinator.construction.available_workers() == 15, "terrain job did not reserve five workers")
	_check(coordinator._transport_construction_tile_ids().has(tile_id), "terrain worksite is absent from transport construction blockers")
	_check(_event_count(coordinator.drain_ui_events(), "terrain_flatten_started") == 1, "terrain start event was not emitted exactly once")

	var duplicate: Dictionary = coordinator.flatten_terrain(tile_id)
	_check(str(duplicate.get("error", "")) == "terrain_flatten_already_active", "duplicate terrain job was not rejected")
	_check(coordinator.treasury_balance() == funds_before - total_cost, "duplicate terrain start charged treasury")
	_check(_ledger_count(coordinator, "construction.terrain_flatten_total_cost") == 1, "duplicate terrain start created another ledger entry")
	var blocked_build: Dictionary = coordinator.start_approved_building("住宅", tile_id, 5)
	_check(not bool(blocked_build.get("ok", false)), "building started during terrain earthworks")
	var blocked_transport: Dictionary = coordinator.transport_project_quote("road", "build", [tile_id], 5, [])
	_check(not bool(blocked_transport.get("ok", false)), "transport started during terrain earthworks")

	_check(coordinator.save_game(MID_JOB_SAVE_PATH) == OK, "mid-job save failed")
	_check(Array(coordinator.terrain_snapshot().get("tiles", [])).size() == 100, "mid-job save did not contain 100 terrain records")
	_check(_saved_pair(MID_JOB_SAVE_PATH) == CURRENT_SCHEMA_PAIR, "fresh mid-job save did not write the current pair")
	_check(_rewrite_saved_pair(MID_JOB_SAVE_PATH, 7, 2, tile_id, false), "mid-job fixture could not be converted to legacy pair 7/2")
	var mid_job_expected_tiles := _saved_terrain_tiles(MID_JOB_SAVE_PATH)
	_check(not mid_job_expected_tiles.is_empty(), "rewritten mid-job fixture has terrain records")
	var restored = CoordinatorScript.new(99, 1)
	var mid_job_loaded: bool = restored.load_game(MID_JOB_SAVE_PATH)
	if not mid_job_loaded:
		_diagnose_mid_job_restore(coordinator)
	_check(mid_job_loaded, "mid-job save did not load")
	_check(_runtime_pair(restored) == CURRENT_SCHEMA_PAIR, "mid-job 7/2 load did not atomically migrate to the current pair")
	_check(_terrain_records_match(restored.terrain_snapshot().get("tiles", []), mid_job_expected_tiles), "mid-job migration changed terrain records")
	_check(restored.save_game(MID_JOB_SAVE_PATH) == OK, "migrated mid-job state could not persist as current")
	_check(_saved_pair(MID_JOB_SAVE_PATH) == CURRENT_SCHEMA_PAIR, "migrated mid-job save did not persist the current pair")
	var reentered = CoordinatorScript.new(98, 1)
	_check(reentered.load_game(MID_JOB_SAVE_PATH), "current mid-job save failed migration re-entry")
	_check(_runtime_pair(reentered) == CURRENT_SCHEMA_PAIR, "migration re-entry changed the current pair")
	restored = reentered
	var restored_job: Dictionary = restored.construction.jobs.get(job_id, {})
	_check(str(restored_job.get("status", "")) == "active", "mid-job load did not preserve active status")
	_check(is_equal_approx(float(restored_job.get("remaining_work", -1.0)), float(job.get("remaining_work", -2.0))), "mid-job load changed remaining work")
	_check(int(restored_job.get("projected_remaining_days", -1)) == duration_days, "mid-job load changed remaining duration")
	_check(not restored.terrain_map.is_flattened(tile_id), "mid-job load completed terrain instantly")
	_check(not restored.terrain_map.is_buildable(tile_id) and not restored.terrain_map.is_walkable(tile_id), "mid-job load removed terrain blockers")
	_check(restored.construction.available_workers() == 15, "mid-job load released reserved workers")
	_check(restored.treasury_balance() == funds_before - total_cost, "mid-job load changed prepaid treasury balance")

	var precompletion_events: Array[Dictionary] = restored.advance_days(duration_days - 1, {}, false)
	_check(_event_count(precompletion_events, "terrain_flattened") == 0, "terrain completed before its final day")
	_check(not restored.terrain_map.is_flattened(tile_id), "terrain state changed before its final day")
	_check(str(restored.construction.jobs.get(job_id, {}).get("status", "")) == "active", "terrain job stopped before its final day")
	_check(restored.construction.available_workers() == 15, "workers released before the final day")
	_check(restored.treasury_balance() == funds_before - total_cost, "daily progression charged prepaid terrain work again")

	var completion_events: Array[Dictionary] = restored.advance_days(1, {}, false)
	_check(_event_count(completion_events, "terrain_flattened") == 1, "final day did not emit one terrain completion")
	_check(restored.terrain_map.is_flattened(tile_id), "final day did not flatten terrain")
	_check(restored.terrain_map.is_buildable(tile_id) and restored.terrain_map.is_walkable(tile_id), "completed terrain did not release build/navigation blockers")
	_check(str(restored.construction.jobs.get(job_id, {}).get("status", "")) == "completed", "completed terrain job history was not retained")
	_check(not restored.session.state.construction_jobs.has(job_id), "completed terrain job remained in the core active-job mirror")
	_check(restored.construction.available_workers() == 20, "final day did not release terrain workers")
	_check(restored.treasury_balance() == funds_before - total_cost, "terrain completion charged treasury again")
	_check(_ledger_count(restored, "construction.terrain_flatten_total_cost") == 1, "terrain lifecycle has more than one prepaid ledger entry")

	_check(restored.save_game(COMPLETED_SAVE_PATH) == OK, "completed terrain save failed")
	_check(_saved_pair(COMPLETED_SAVE_PATH) == CURRENT_SCHEMA_PAIR, "fresh completed save did not write the current pair")
	_check(_rewrite_saved_pair(COMPLETED_SAVE_PATH, 7, 2, tile_id, true), "completed fixture could not be converted to legacy pair 7/2")
	var completed_expected_tiles := _saved_terrain_tiles(COMPLETED_SAVE_PATH)
	_check(not completed_expected_tiles.is_empty(), "rewritten completed fixture has terrain records")
	var completed_reload = CoordinatorScript.new(100, 1)
	_check(completed_reload.load_game(COMPLETED_SAVE_PATH), "completed terrain save did not load")
	_check(_runtime_pair(completed_reload) == CURRENT_SCHEMA_PAIR, "completed 7/2 load did not atomically migrate to the current pair")
	_check(_terrain_records_match(completed_reload.terrain_snapshot().get("tiles", []), completed_expected_tiles), "completed migration changed terrain records")
	_check(completed_reload.terrain_map.is_flattened(tile_id), "completed terrain did not survive reload")
	_check(str(completed_reload.construction.jobs.get(job_id, {}).get("status", "")) == "completed", "completed terrain job history did not survive reload")
	_check(completed_reload.treasury_balance() == funds_before - total_cost, "completed reload deducted the quote again")
	_check(_ledger_count(completed_reload, "construction.terrain_flatten_total_cost") == 1, "completed reload duplicated the prepaid ledger entry")


func _test_pre_schema_five_migration() -> void:
	var legacy = CoordinatorScript.new(8_020_702, 500_000)
	var compat_snapshot: Dictionary = CityTerrainMapScript.synthesized_layout3_compat_snapshot()
	var occupied_tile := _first_nonflat_unflattened_tile(compat_snapshot)
	_check(occupied_tile >= 0, "legacy fixture has no background-derived blocked tile")
	var seeded: Dictionary = legacy.register_existing_building(occupied_tile, "住宅")
	_check(not seeded.is_empty(), "legacy fixture building was not registered")
	legacy._stash_subsystems()
	var vertical: Dictionary = legacy.session.state.metadata.get("vertical_slice", {})
	vertical["schema_version"] = 4
	vertical.erase("terrain")
	legacy.session.state.metadata["vertical_slice"] = vertical
	_check(legacy.session.save_now(LEGACY_SAVE_PATH) == OK, "legacy pre-terrain fixture could not save")
	var migrated = CoordinatorScript.new(1, 1)
	_check(migrated.load_game(LEGACY_SAVE_PATH), "legacy pre-terrain fixture could not load")
	_check(not migrated.get_building_by_tile(occupied_tile).is_empty(), "legacy migration lost its occupied building")
	_check(migrated.terrain_map.is_flattened(occupied_tile) and migrated.terrain_map.is_buildable(occupied_tile), "pre-schema-five occupied tile was not normalized")
	_check(str(migrated.terrain_map.to_dict().get("tiles", [])[occupied_tile].get("base_kind", "")) == str(compat_snapshot.get("tiles", [])[occupied_tile].get("base_kind", "")), "pre-schema-five normalization reclassified the occupied tile")


func _ledger_count(coordinator, reason_tag: String) -> int:
	var count := 0
	for entry_value: Variant in coordinator.session.state.ledger.get_entries():
		if entry_value is Dictionary and str((entry_value as Dictionary).get("reason_tag", "")) == reason_tag:
			count += 1
	return count


func _diagnose_mid_job_restore(coordinator) -> void:
	var envelope = coordinator.session.save_service.load_primary_envelope(MID_JOB_SAVE_PATH)
	if envelope == null:
		print("TERRAIN_RESTORE_DIAGNOSTIC envelope=null")
		return
	var restored_state = CityStateScript.from_dict(envelope.state)
	var probe = coordinator.session
	print("TERRAIN_RESTORE_DIAGNOSTIC state=%s clock=%s runtime=%s vertical=%s" % [
		str(restored_state != null),
		str(probe._validate_clock_snapshot(envelope.clock)),
		str(probe._validate_runtime_collections(envelope.kernel, envelope.command_sequence)),
		str(probe._validate_vertical_slice_metadata(restored_state, envelope.kernel) if restored_state != null else false),
	])
	if restored_state == null:
		return
	var vertical: Dictionary = restored_state.metadata.get("vertical_slice", {})
	print("TERRAIN_RESTORE_DIAGNOSTIC seq=%s nontransport=%s transport=%s terrain=%s" % [
		str(probe._validate_current_vertical_sequences(vertical, restored_state, envelope.kernel)),
		str(probe._validate_current_vertical_non_transport(vertical, restored_state)),
		str(probe._validate_transport_construction_links(vertical, restored_state)),
		str(probe._validate_terrain_construction_links(vertical, restored_state)),
	])
	var construction: Dictionary = vertical.get("construction", {})
	print("TERRAIN_RESTORE_DIAGNOSTIC construction=%s blueprint_links=%s core=%s demolition=%s capacity=%s" % [
		JSON.stringify(ConstructionSystemScript.validate_snapshot(construction)),
		str(probe._validate_blueprint_construction_links(vertical, construction)),
		str(probe._validate_construction_core_mirror(construction, restored_state)),
		str(probe._validate_building_demolition_jobs(construction, restored_state)),
		str(probe._validate_active_construction_capacity_and_tiles(construction, restored_state)),
	])


func _event_count(events: Array[Dictionary], event_type: String) -> int:
	var count := 0
	for event: Dictionary in events:
		if str(event.get("type", "")) == event_type:
			count += 1
	return count


func _first_backdrop_terrain_tile(coordinator, preferred_kind: String) -> int:
	for state_variant: Variant in coordinator.terrain_map.all_tile_states():
		var state: Dictionary = state_variant
		if (
			str(state.get("base_kind", "")) == preferred_kind
			and not Array(state.get("backdrop_feature_ids", [])).is_empty()
		):
			return int(state.get("tile_id", -1))
	return -1


func _runtime_pair(coordinator) -> Vector2i:
	var vertical: Dictionary = coordinator.session.state.metadata.get("vertical_slice", {})
	var terrain: Dictionary = vertical.get("terrain", {})
	return Vector2i(
		int(vertical.get("schema_version", -1)),
		int(terrain.get("layout_version", -1))
	)


func _saved_pair(save_path: String) -> Vector2i:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not parsed is Dictionary:
		return Vector2i(-1, -1)
	var state_value: Variant = (parsed as Dictionary).get("state", null)
	if not state_value is Dictionary:
		return Vector2i(-1, -1)
	var metadata: Dictionary = (state_value as Dictionary).get("metadata", {})
	var vertical: Dictionary = metadata.get("vertical_slice", {})
	var terrain: Dictionary = vertical.get("terrain", {})
	return Vector2i(
		int(vertical.get("schema_version", -1)),
		int(terrain.get("layout_version", -1))
	)


func _rewrite_saved_pair(save_path: String, schema_version: int, layout_version: int, tile_id: int, flattened: bool) -> bool:
	if not SaveSchemaAuthorityScript.is_legacy_migration_pair(schema_version, layout_version):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not parsed is Dictionary:
		return false
	var envelope: Dictionary = parsed
	var state_value: Variant = envelope.get("state", null)
	if not state_value is Dictionary:
		return false
	var state_snapshot: Dictionary = state_value
	var metadata: Dictionary = state_snapshot.get("metadata", {})
	var vertical: Dictionary = metadata.get("vertical_slice", {})
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT2_FIXTURE_PATH))
	if not fixture is Dictionary:
		return false
	var terrain: Dictionary = fixture.get("state", {}).get("metadata", {}).get("vertical_slice", {}).get("terrain", {}).duplicate(true)
	var source_terrain: Dictionary = vertical.get("terrain", {})
	var source_tiles: Array = Array(source_terrain.get("tiles", []))
	var source_record: Dictionary = source_tiles[tile_id] if tile_id >= 0 and tile_id < source_tiles.size() else {}
	var terrain_tiles: Array = Array(terrain.get("tiles", []))
	var terrain_record: Dictionary = terrain_tiles[tile_id] if tile_id >= 0 and tile_id < terrain_tiles.size() else {}
	if source_record.is_empty() or terrain_record.is_empty() or str(source_record.get("base_kind", "")) != str(terrain_record.get("base_kind", "") ) or str(terrain_record.get("base_kind", "")) == "flat_grass":
		return false
	terrain_record["flattened"] = flattened
	vertical["schema_version"] = schema_version
	terrain["layout_version"] = layout_version
	terrain.erase("classification_provenance")
	vertical["terrain"] = terrain
	metadata["vertical_slice"] = vertical
	state_snapshot["metadata"] = metadata
	envelope["state"] = state_snapshot
	var file := FileAccess.open(ProjectSettings.globalize_path(save_path), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(envelope, "\t", false))
	file.flush()
	var write_error := file.get_error()
	file.close()
	return write_error == OK


func _saved_terrain_tiles(save_path: String) -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not parsed is Dictionary:
		return []
	return Array(parsed.get("state", {}).get("metadata", {}).get("vertical_slice", {}).get("terrain", {}).get("tiles", [])).duplicate(true)


func _terrain_records_match(actual_records: Variant, expected_records: Variant) -> bool:
	if not actual_records is Array or not expected_records is Array:
		return false
	var actual: Array = actual_records
	var expected: Array = expected_records
	if actual.size() != expected.size() or actual.is_empty():
		return false
	for index in actual.size():
		if not actual[index] is Dictionary or not expected[index] is Dictionary:
			return false
		var actual_record: Dictionary = actual[index]
		var expected_record: Dictionary = expected[index]
		for key: String in ["tile_id", "base_kind", "flattened"]:
			if not actual_record.has(key) or not expected_record.has(key):
				return false
		if int(actual_record["tile_id"]) != int(expected_record["tile_id"]):
			return false
		if str(actual_record["base_kind"]) != str(expected_record["base_kind"]):
			return false
		if bool(actual_record["flattened"]) != bool(expected_record["flattened"]):
			return false
	return true


func _first_matching_layout2_nonflat_tile(coordinator, required_kind: String) -> int:
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT2_FIXTURE_PATH))
	var terrain: Dictionary = fixture.get("state", {}).get("metadata", {}).get("vertical_slice", {}).get("terrain", {}) if fixture is Dictionary else {}
	for record_value: Variant in Array(terrain.get("tiles", [])):
		var record: Dictionary = record_value
		var tile_id := int(record.get("tile_id", -1))
		if str(record.get("base_kind", "")) == required_kind and not bool(record.get("flattened", false)) and str(coordinator.terrain_state_for_tile(tile_id).get("base_kind", "")) == required_kind:
			return tile_id
	return -1


func _first_nonflat_unflattened_tile(snapshot: Dictionary) -> int:
	for record_value: Variant in Array(snapshot.get("tiles", [])):
		var record: Dictionary = record_value
		if str(record.get("base_kind", "")) != "flat_grass" and not bool(record.get("flattened", false)):
			return int(record.get("tile_id", -1))
	return -1


func _cleanup_saves() -> void:
	for save_path: String in [MID_JOB_SAVE_PATH, COMPLETED_SAVE_PATH, LEGACY_SAVE_PATH]:
		var absolute_path := ProjectSettings.globalize_path(save_path)
		for suffix: String in ["", ".tmp", ".bak"]:
			var candidate := absolute_path + suffix
			if FileAccess.file_exists(candidate):
				DirAccess.remove_absolute(candidate)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Terrain flatten lifecycle integration failed: %s" % message)
