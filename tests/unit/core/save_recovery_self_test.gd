extends SceneTree

const GameSessionScript = preload("res://scripts/core/game_session.gd")
const SaveEnvelopeScript = preload("res://scripts/core/save_envelope.gd")
const SaveServiceScript = preload("res://scripts/core/save_service.gd")
const CityStateScript = preload("res://scripts/core/city_state.gd")
const VerticalSliceCoordinatorScript = preload("res://scripts/app/vertical_slice_coordinator.gd")
const BlueprintLibraryServiceScript = preload("res://scripts/app/blueprint_library_service.gd")
const ConstructionSystemScript = preload("res://scripts/systems/city/construction_system.gd")
const TransportNetworkSystemScript = preload("res://scripts/systems/city/transport_network_system.gd")
const SaveSchemaAuthorityScript = preload("res://scripts/core/save_schema_authority.gd")
const PopulationSystemScript = preload("res://scripts/systems/population/population_system.gd")
const NpcRecordScript = preload("res://scripts/systems/population/npc_record.gd")
const CityTerrainMapScript = preload("res://scripts/world/city_terrain_map.gd")
const BuildingFootprintsScript = preload("res://data/catalogs/building_footprints.gd")

const TEST_ROOT := "user://mayor_simulator/tests/save_recovery"
const DECODE_FAILURE_PATH := TEST_ROOT + "/decode_failure.json"
const SEMANTIC_FAILURE_PATH := TEST_ROOT + "/semantic_failure.json"
const SHORT_WRITE_PATH := TEST_ROOT + "/short_write.json"
const REPORTED_WRITE_FAILURE_PATH := TEST_ROOT + "/reported_write_failure.json"
const INCONSISTENT_ENVELOPE_PATH := TEST_ROOT + "/inconsistent_envelope.json"
const UNSUPPORTED_ENVELOPE_SCHEMA_PATH := TEST_ROOT + "/unsupported_envelope_schema.json"
const UNSUPPORTED_STATE_SCHEMA_PATH := TEST_ROOT + "/unsupported_state_schema.json"
const LEGACY_MINIMAL_RUNTIME_PATH := TEST_ROOT + "/legacy_minimal_runtime.json"
const CURRENT_SCHEMA_NON_TRANSPORT_PATH := TEST_ROOT + "/current_schema_non_transport.json"
const SCHEMA_PAIR_MIGRATION_PATH := TEST_ROOT + "/schema_pair_migration.json"
const RUNTIME_POPULATION_GATE_PATH := TEST_ROOT + "/runtime_population_gate.json"
const SCHEMA_AUTHORITY_REGISTRY_PATH := "res://data/save_schema_authority_registry.json"
const CURRENT_ROUND_TRIP_FIXTURE_PATH := "res://tests/fixtures/save_schema/current_round_trip.json"
const SUPPORTED_LEGACY_FIXTURE_PATH := "res://tests/fixtures/save_schema/supported_legacy_migration.json"
const FUTURE_REJECT_FIXTURE_PATH := "res://tests/fixtures/save_schema/future_reject.json"
const CORRUPT_MINIMAL_FIXTURE_PATH := "res://tests/fixtures/save_schema/corrupt_minimal.json"
const OLDEST_SUPPORTED_FIXTURE_PATH := "res://tests/fixtures/save_schema/oldest_supported_vertical_4.json"
const UNSUPPORTED_VERTICAL_FIXTURE_PATH := "res://tests/fixtures/save_schema/unsupported_vertical_3.json"
const TEST_SEED := 8_024_611
const TEST_FUNDS := 73_000

var _failed := false
var _checks := 0


func _initialize() -> void:
	_cleanup_all()
	_test_decode_failure_recovers_and_rebuilds_primary()
	_test_semantic_failure_recovers_and_preserves_backup_on_next_save()
	_test_temporary_write_failures_preserve_both_snapshots()
	_test_well_formed_inconsistent_envelope_uses_backup()
	_test_unsupported_schemas_use_backup()
	_test_current_schema_non_transport_corruption_uses_backup()
	_test_current_schema_cross_layer_corruption_uses_backup()
	_test_vertical_metadata_schema_boundary()
	_test_vertical_terrain_pairing_boundary()
	_test_building_footprint_schema_boundary()
	_test_city_state_population_migration_boundary()
	_test_non_vertical_runtime_population_save_gate()
	_test_strict_population_restore_boundary()
	_test_schema_authority_runtime_constants()
	_test_schema_authority_registry_contract()
	_test_tracked_schema_fixtures()
	_test_schema_one_minimal_runtime_remains_compatible()
	_cleanup_all()
	if _failed:
		quit(1)
	else:
		print("Save recovery self-test passed. Checks=%d" % _checks)
		quit(0)


func _test_decode_failure_recovers_and_rebuilds_primary() -> void:
	var fixture := _seed_valid_pair(DECODE_FAILURE_PATH)
	_check(_write_text(DECODE_FAILURE_PATH, "{ definitely-not-valid-json"), "decode fixture corrupts only the primary")
	var restored = GameSessionScript.new(1, 1)
	_check(restored.load_now(DECODE_FAILURE_PATH), "decode-invalid primary falls back to the valid backup")
	_check(restored.save_service.last_load_source == SaveServiceScript.LOAD_SOURCE_BACKUP, "decode recovery records backup as the load source")
	_check(restored.save_service.last_recovery_error == OK, "decode recovery rebuilds the primary successfully")
	_check(restored.deterministic_hash() == str(fixture["hash"]), "decode recovery restores the exact backup state")
	_check(_read_text(DECODE_FAILURE_PATH) == _read_text(DECODE_FAILURE_PATH + ".bak"), "rebuilt primary is byte-identical to the trusted backup")
	_assert_exact_candidate(DECODE_FAILURE_PATH, false, str(fixture["hash"]), int(fixture["balance"]), "decode recovery primary")
	_assert_exact_candidate(DECODE_FAILURE_PATH, true, str(fixture["hash"]), int(fixture["balance"]), "decode recovery backup")


func _test_semantic_failure_recovers_and_preserves_backup_on_next_save() -> void:
	var fixture := _seed_valid_pair(SEMANTIC_FAILURE_PATH)
	var primary_data: Variant = JSON.parse_string(_read_text(SEMANTIC_FAILURE_PATH))
	_check(primary_data is Dictionary, "semantic fixture starts as valid JSON")
	if not primary_data is Dictionary:
		return
	(primary_data as Dictionary)["content_version"] = "unsupported_content_version"
	_check(
		_write_text(SEMANTIC_FAILURE_PATH, JSON.stringify(primary_data, "\t", false)),
		"semantic fixture keeps a decodable envelope with an unsupported content version"
	)
	var decoder = SaveServiceScript.new()
	var decodable_primary = decoder.load_primary_envelope(SEMANTIC_FAILURE_PATH)
	_check(decodable_primary != null, "semantic-invalid primary still passes JSON and envelope decoding")
	var semantic_probe = GameSessionScript.new(2, 2)
	_check(not semantic_probe.restore_envelope(decodable_primary), "strict content-version validation rejects the semantic-invalid primary")

	var restored = GameSessionScript.new(3, 3)
	_check(restored.load_now(SEMANTIC_FAILURE_PATH), "semantic-invalid primary falls back after restore_envelope rejects it")
	_check(restored.save_service.last_load_source == SaveServiceScript.LOAD_SOURCE_BACKUP, "semantic recovery records backup as the load source")
	_check(restored.save_service.last_recovery_error == OK, "semantic recovery safely rebuilds the primary")
	_check(restored.deterministic_hash() == str(fixture["hash"]), "semantic recovery restores the exact backup state")
	_check(_read_text(SEMANTIC_FAILURE_PATH) == _read_text(SEMANTIC_FAILURE_PATH + ".bak"), "semantic recovery leaves both on-disk snapshots valid and identical")

	restored.submit_command("ledger_post", {
		"amount": 777,
		"source_id": "recovery_test",
		"reason_tag": "recovery.follow_up",
		"metadata": {"test": true},
	}, "recovery_follow_up")
	var updated_hash: String = restored.deterministic_hash()
	var updated_balance: int = restored.state.ledger.get_balance()
	_check(restored.save_now(SEMANTIC_FAILURE_PATH) == OK, "first save after backup recovery succeeds")
	_check(_read_text(SEMANTIC_FAILURE_PATH) != _read_text(SEMANTIC_FAILURE_PATH + ".bak"), "first post-recovery save keeps the previous valid snapshot as backup")
	_assert_exact_candidate(SEMANTIC_FAILURE_PATH, false, updated_hash, updated_balance, "post-recovery primary")
	_assert_exact_candidate(SEMANTIC_FAILURE_PATH, true, str(fixture["hash"]), int(fixture["balance"]), "post-recovery backup")


func _test_temporary_write_failures_preserve_both_snapshots() -> void:
	_seed_valid_pair(SHORT_WRITE_PATH)
	var primary_before := _read_text(SHORT_WRITE_PATH)
	var backup_before := _read_text(SHORT_WRITE_PATH + ".bak")
	var short_writer = GameSessionScript.new(5, 5)
	_check(short_writer.load_now(SHORT_WRITE_PATH), "short-write fixture loads before fault injection")
	short_writer.submit_command("ledger_post", {
		"amount": 19,
		"source_id": "short_write_fixture",
		"reason_tag": "test.short_write",
	}, "short_write_change")
	short_writer.save_service.set_temporary_writer_for_testing(Callable(self, "_write_short_temporary"))
	var short_error: Error = short_writer.save_now(SHORT_WRITE_PATH)
	_check(short_error == ERR_FILE_CORRUPT, "silent short write is rejected by read-back/decode verification")
	_check(short_writer.save_service.last_error_message.contains("verification"), "short-write rejection records a verification error")
	_check(_read_text(SHORT_WRITE_PATH) == primary_before, "short write leaves the primary snapshot untouched")
	_check(_read_text(SHORT_WRITE_PATH + ".bak") == backup_before, "short write leaves the trusted backup untouched")
	_check(not FileAccess.file_exists(ProjectSettings.globalize_path(SHORT_WRITE_PATH) + ".tmp"), "short-write temporary file is discarded")

	_seed_valid_pair(REPORTED_WRITE_FAILURE_PATH)
	primary_before = _read_text(REPORTED_WRITE_FAILURE_PATH)
	backup_before = _read_text(REPORTED_WRITE_FAILURE_PATH + ".bak")
	var failed_writer = GameSessionScript.new(6, 6)
	_check(failed_writer.load_now(REPORTED_WRITE_FAILURE_PATH), "reported-write-error fixture loads before fault injection")
	failed_writer.save_service.set_temporary_writer_for_testing(Callable(self, "_report_temporary_write_failure"))
	var reported_error: Error = failed_writer.save_now(REPORTED_WRITE_FAILURE_PATH)
	_check(reported_error == ERR_FILE_CANT_WRITE, "temporary writer error is returned to the caller")
	_check(_read_text(REPORTED_WRITE_FAILURE_PATH) == primary_before, "reported write error leaves the primary snapshot untouched")
	_check(_read_text(REPORTED_WRITE_FAILURE_PATH + ".bak") == backup_before, "reported write error leaves the backup snapshot untouched")


func _test_well_formed_inconsistent_envelope_uses_backup() -> void:
	var fixture := _seed_valid_pair(INCONSISTENT_ENVELOPE_PATH)
	var primary_data: Variant = JSON.parse_string(_read_text(INCONSISTENT_ENVELOPE_PATH))
	_check(primary_data is Dictionary, "inconsistent-envelope fixture starts as valid JSON")
	if not primary_data is Dictionary:
		return
	(primary_data as Dictionary)["game_time"] = int((primary_data as Dictionary).get("game_time", 0)) + 1
	_check(
		_write_text(INCONSISTENT_ENVELOPE_PATH, JSON.stringify(primary_data, "\t", false)),
		"inconsistent-envelope fixture remains well-formed JSON"
	)
	var decoder = SaveServiceScript.new()
	var decodable_primary = decoder.load_primary_envelope(INCONSISTENT_ENVELOPE_PATH)
	_check(decodable_primary != null, "well-formed inconsistent primary passes envelope decoding")
	var semantic_probe = GameSessionScript.new(7, 7)
	_check(not semantic_probe.restore_envelope(decodable_primary), "game-time disagreement fails semantic validation")
	var restored = GameSessionScript.new(8, 8)
	_check(restored.load_now(INCONSISTENT_ENVELOPE_PATH), "well-formed inconsistent primary falls back to backup")
	_check(restored.save_service.last_load_source == SaveServiceScript.LOAD_SOURCE_BACKUP, "inconsistent-envelope recovery records backup source")
	_check(restored.deterministic_hash() == str(fixture["hash"]), "inconsistent-envelope recovery restores the exact backup state")


func _test_unsupported_schemas_use_backup() -> void:
	var envelope_fixture := _seed_valid_pair(UNSUPPORTED_ENVELOPE_SCHEMA_PATH)
	var envelope_data: Variant = JSON.parse_string(_read_text(UNSUPPORTED_ENVELOPE_SCHEMA_PATH))
	_check(envelope_data is Dictionary, "unsupported-envelope fixture starts as valid JSON")
	if envelope_data is Dictionary:
		(envelope_data as Dictionary)["schema_version"] = 999
		_check(_write_text(UNSUPPORTED_ENVELOPE_SCHEMA_PATH, JSON.stringify(envelope_data, "\t", false)), "unsupported envelope schema remains valid JSON")
		var envelope_decoder = SaveServiceScript.new()
		_check(envelope_decoder.load_primary_envelope(UNSUPPORTED_ENVELOPE_SCHEMA_PATH) == null, "unsupported envelope schema is rejected at the migration boundary")
		var envelope_restored = GameSessionScript.new(9, 9)
		_check(envelope_restored.load_now(UNSUPPORTED_ENVELOPE_SCHEMA_PATH), "unsupported envelope schema falls back to backup")
		_check(envelope_restored.deterministic_hash() == str(envelope_fixture["hash"]), "envelope-schema fallback restores exact backup state")

	var state_fixture := _seed_valid_pair(UNSUPPORTED_STATE_SCHEMA_PATH)
	var state_data: Variant = JSON.parse_string(_read_text(UNSUPPORTED_STATE_SCHEMA_PATH))
	_check(state_data is Dictionary, "unsupported-state fixture starts as valid JSON")
	if state_data is Dictionary:
		var state_snapshot: Variant = (state_data as Dictionary).get("state", {})
		_check(state_snapshot is Dictionary, "unsupported-state fixture contains a state snapshot")
		if state_snapshot is Dictionary:
			(state_snapshot as Dictionary)["schema_version"] = 999
			_check(_write_text(UNSUPPORTED_STATE_SCHEMA_PATH, JSON.stringify(state_data, "\t", false)), "unsupported state schema remains valid JSON")
			var state_decoder = SaveServiceScript.new()
			var decoded_state_primary = state_decoder.load_primary_envelope(UNSUPPORTED_STATE_SCHEMA_PATH)
			_check(decoded_state_primary != null, "unsupported CityState schema still passes outer envelope decoding")
			var state_probe = GameSessionScript.new(10, 10)
			_check(not state_probe.restore_envelope(decoded_state_primary), "unsupported CityState schema is rejected at its migration boundary")
			var state_restored = GameSessionScript.new(11, 11)
			_check(state_restored.load_now(UNSUPPORTED_STATE_SCHEMA_PATH), "unsupported CityState schema falls back to backup")
			_check(state_restored.deterministic_hash() == str(state_fixture["hash"]), "state-schema fallback restores exact backup state")


func _test_vertical_metadata_schema_boundary() -> void:
	var source = _canonical_current_session(13, 13)
	var current_probe = GameSessionScript.new(14, 14)
	_check(current_probe.restore_envelope(source.make_envelope()), "population schema two remains restorable")
	var current_vertical: Dictionary = source.state.metadata["vertical_slice"].duplicate(true)
	var legacy_vertical := current_vertical.duplicate(true)
	legacy_vertical["schema_version"] = 5
	for current_only_field: String in ["construction", "next_blueprint_sequence", "blueprint_library", "active_blueprint_by_building", "transport"]:
		legacy_vertical.erase(current_only_field)
	source.state.metadata["vertical_slice"] = legacy_vertical
	var legacy_vertical_probe = GameSessionScript.new(141, 141)
	_check(legacy_vertical_probe.restore_envelope(source.make_envelope()), "schema five remains compatible without schema-six construction, blueprint, or transport fields")
	source.state.metadata["vertical_slice"] = current_vertical

	var legacy_population: Dictionary = Dictionary(current_vertical["population"]).duplicate(true)
	legacy_population["schema_version"] = 1
	legacy_population.erase("next_transaction_sequence")
	legacy_population.erase("income_transactions")
	source.state.metadata["vertical_slice"]["population"] = legacy_population
	var legacy_population_probe = GameSessionScript.new(15, 15)
	_check(legacy_population_probe.restore_envelope(source.make_envelope()), "population schema one remains backward compatible")
	source.state.metadata["vertical_slice"]["population"] = Dictionary(current_vertical["population"]).duplicate(true)

	source.state.metadata["vertical_slice"]["terminal_failure_event_reason"] = "invented_failure"
	var invalid_reason_probe = GameSessionScript.new(16, 16)
	_check(not invalid_reason_probe.restore_envelope(source.make_envelope()), "unknown terminal failure reason is rejected semantically")

	source.state.metadata["vertical_slice"]["terminal_failure_event_reason"] = ""
	source.state.metadata["vertical_slice"]["population"]["schema_version"] = GameSessionScript.MAX_SUPPORTED_POPULATION_SCHEMA + 1
	var future_population_probe = GameSessionScript.new(17, 17)
	_check(not future_population_probe.restore_envelope(source.make_envelope()), "population schema three is rejected at its migration boundary")

	source.state.metadata["vertical_slice"]["population"]["schema_version"] = GameSessionScript.MAX_SUPPORTED_POPULATION_SCHEMA
	source.state.metadata["vertical_slice"]["schema_version"] = GameSessionScript.MAX_SUPPORTED_VERTICAL_SLICE_METADATA_SCHEMA + 1
	var future_schema_probe = GameSessionScript.new(18, 18)
	_check(not future_schema_probe.restore_envelope(source.make_envelope()), "future vertical metadata schema is rejected at its migration boundary")


func _test_vertical_terrain_pairing_boundary() -> void:
	var source = _canonical_current_session(19, 19)
	_check(source.save_now(SCHEMA_PAIR_MIGRATION_PATH) == OK, "fresh current save writes through the atomic save boundary")
	var decoder = SaveServiceScript.new()
	var current_envelope = decoder.load_primary_envelope(SCHEMA_PAIR_MIGRATION_PATH)
	_check(current_envelope != null, "fresh current save decodes from disk")
	if current_envelope == null:
		return
	var current_vertical: Dictionary = current_envelope.state.get("metadata", {}).get("vertical_slice", {})
	var terrain_snapshot: Dictionary = current_vertical.get("terrain", {})
	_check(int(current_vertical.get("schema_version", -1)) == 10, "fresh save does not write vertical schema 10")
	_check(int(terrain_snapshot.get("layout_version", -1)) == 3, "fresh save does not write terrain layout 3")
	_check(
		SaveSchemaAuthorityScript.validate_vertical_terrain_pair(
			int(current_vertical.get("schema_version", -1)),
			int(terrain_snapshot.get("layout_version", -1))
		),
		"current vertical schema and terrain layout are an authorized pair"
	)
	_check(SaveSchemaAuthorityScript.is_legacy_migration_pair(7, 2), "registry authority does not expose 7/2 as the migration input")
	_check(SaveSchemaAuthorityScript.is_transport_session_migration_pair(9, 3), "registry authority does not expose 9/3 as the session migration input")
	var schema_nine_envelope = _copy_envelope_with_pair(current_envelope, 9, 3)
	(schema_nine_envelope.state["metadata"]["vertical_slice"] as Dictionary).erase("transport_planning_session")
	var schema_nine_probe = GameSessionScript.new(191, 191)
	_check(schema_nine_probe.restore_envelope(schema_nine_envelope), "schema 9 did not migrate to the session-aware current schema")
	var schema_nine_migrated: Dictionary = schema_nine_probe.state.metadata.get("vertical_slice", {})
	_check(int(schema_nine_migrated.get("schema_version", -1)) == 10, "schema 9 migration did not write schema 10")
	_check(
		str(schema_nine_migrated.get("transport_planning_session", {}).get("session", {}).get("state", "")) == "inactive",
		"schema 9 migration invented an active transport session"
	)

	var legacy_envelope = _copy_envelope_with_pair(current_envelope, 7, 2)
	var legacy_tiles_json := JSON.stringify(
		legacy_envelope.state.get("metadata", {}).get("vertical_slice", {}).get("terrain", {}).get("tiles", [])
	)
	var migrated_probe = GameSessionScript.new(20, 20)
	_check(migrated_probe.restore_envelope(legacy_envelope), "legacy 7/2 envelope did not migrate")
	var migrated_vertical: Dictionary = migrated_probe.state.metadata.get("vertical_slice", {})
	_check(int(migrated_vertical.get("schema_version", -1)) == 10, "legacy migration did not set vertical schema 10")
	_check(int(migrated_vertical.get("terrain", {}).get("layout_version", -1)) == 3, "legacy migration did not set terrain layout 3")
	_check(
		JSON.stringify(migrated_vertical.get("terrain", {}).get("tiles", [])) == legacy_tiles_json,
		"legacy migration changed one or more of the 100 tile records"
	)
	_check(Array(migrated_vertical.get("terrain", {}).get("tiles", [])).size() == 100, "legacy migration did not preserve 100 tile records")
	var reentry_probe = GameSessionScript.new(21, 21)
	_check(reentry_probe.restore_envelope(migrated_probe.make_envelope()), "already-current migrated envelope failed re-entry")
	_check(
		JSON.stringify(reentry_probe.state.metadata.get("vertical_slice", {}).get("terrain", {}).get("tiles", [])) == legacy_tiles_json,
		"migration re-entry changed terrain records"
	)

	for invalid_pair: Dictionary in [
		{"schema": 8, "layout": 2, "label": "8/2 mismatch"},
		{"schema": 7, "layout": 3, "label": "7/3 mismatch"},
		{"schema": 11, "layout": 3, "label": "future vertical schema"},
		{"schema": 9, "layout": 4, "label": "future terrain layout"},
	]:
		var invalid_envelope = _copy_envelope_with_pair(
			current_envelope,
			int(invalid_pair["schema"]),
			int(invalid_pair["layout"])
		)
		var rejection_probe = GameSessionScript.new(22, 22)
		var rejection_hash_before := rejection_probe.deterministic_hash()
		_check(not rejection_probe.restore_envelope(invalid_envelope), "%s was not rejected" % invalid_pair["label"])
		_check(rejection_probe.deterministic_hash() == rejection_hash_before, "%s partially applied state" % invalid_pair["label"])
	_check(
		not SaveSchemaAuthorityScript.validate_vertical_terrain_pair(8, 2),
		"schema eight with terrain layout two is rejected"
	)
	_check(
		not SaveSchemaAuthorityScript.validate_vertical_terrain_pair(7, 3),
		"schema seven with terrain layout three is rejected"
	)


func _copy_envelope_with_pair(envelope, schema_version: int, layout_version: int):
	var copied = SaveEnvelopeScript.from_dict(envelope.to_dict())
	var state_snapshot: Dictionary = copied.state.duplicate(true)
	var metadata: Dictionary = state_snapshot.get("metadata", {}).duplicate(true)
	var vertical: Dictionary = metadata.get("vertical_slice", {}).duplicate(true)
	var terrain: Dictionary = vertical.get("terrain", {}).duplicate(true)
	vertical["schema_version"] = schema_version
	terrain["layout_version"] = layout_version
	vertical["terrain"] = terrain
	metadata["vertical_slice"] = vertical
	state_snapshot["metadata"] = metadata
	copied.state = state_snapshot
	return copied


func _test_building_footprint_schema_boundary() -> void:
	var coordinator = VerticalSliceCoordinatorScript.new(23, 230_000)
	var buildable_tiles := _find_free_buildable_tiles(coordinator, 1)
	_check(buildable_tiles.size() == 1, "footprint schema fixture finds one buildable anchor")
	if buildable_tiles.is_empty():
		return
	var anchor_tile_id := int(buildable_tiles[0])
	var seeded: Dictionary = coordinator.register_existing_building(anchor_tile_id, "公園")
	_check(not seeded.is_empty(), "footprint schema fixture registers one legacy-compatible building")
	coordinator.call("_stash_subsystems")
	var current_envelope = coordinator.session.make_envelope()
	var current_vertical: Dictionary = current_envelope.state.get("metadata", {}).get("vertical_slice", {})
	var current_record: Dictionary = current_envelope.state.get("buildings", {}).get(str(seeded.get("building_id", "")), {})
	_check(int(current_vertical.get("schema_version", -1)) == 10, "current footprint writer uses vertical schema ten")
	_check(int(current_record.get("anchor_tile_id", -1)) == anchor_tile_id, "current record persists its anchor tile id")
	_check(str(current_record.get("footprint_id", "")) == BuildingFootprintsScript.SINGLE_V1, "current record persists single_v1")
	_check(Array(current_record.get("occupied_tile_ids", [])) == [anchor_tile_id], "current record persists its occupied tile ids")
	_check(str(current_record.get("blueprint", {}).get("size_tier", "")) == BuildingFootprintsScript.SMALL, "current seeded record writes a size matching single_v1")
	_check(not current_record.has(BuildingFootprintsScript.LEGACY_SINGLE_PROVENANCE_FIELD), "current seeded writer never claims legacy provenance")
	var current_probe = GameSessionScript.new(24, 24)
	_check(current_probe.restore_envelope(current_envelope), "schema-ten footprint envelope restores")
	if current_probe.state != null:
		var round_trip_record: Dictionary = current_probe.make_envelope().state.get("buildings", {}).get(str(seeded.get("building_id", "")), {})
		_check(str(round_trip_record.get("footprint_id", "")) == BuildingFootprintsScript.SINGLE_V1, "schema-ten round trip retains footprint id")
		_check(Array(round_trip_record.get("occupied_tile_ids", [])) == [anchor_tile_id], "schema-ten round trip retains occupied tile ids")
		_check(not round_trip_record.has(BuildingFootprintsScript.LEGACY_SINGLE_PROVENANCE_FIELD), "schema-ten current round trip does not invent legacy provenance")

	var legacy_data: Dictionary = current_envelope.to_dict()
	var legacy_vertical: Dictionary = legacy_data.get("state", {}).get("metadata", {}).get("vertical_slice", {})
	legacy_vertical["schema_version"] = SaveSchemaAuthorityScript.FOOTPRINT_MIGRATION_VERTICAL_SCHEMA_VERSION
	var legacy_buildings: Dictionary = legacy_data.get("state", {}).get("buildings", {})
	for record_value: Variant in legacy_buildings.values():
		var legacy_record: Dictionary = record_value
		legacy_record.erase("anchor_tile_id")
		legacy_record.erase("footprint_id")
		legacy_record.erase("occupied_tile_ids")
	var legacy_envelope = SaveEnvelopeScript.from_dict(legacy_data)
	var legacy_probe = GameSessionScript.new(25, 25)
	_check(legacy_envelope != null and legacy_probe.restore_envelope(legacy_envelope), "schema-eight building without footprint migrates")
	if legacy_probe.state != null:
		var migrated_vertical: Dictionary = legacy_probe.state.metadata.get("vertical_slice", {})
		var migrated_record: Dictionary = legacy_probe.state.buildings.get(str(seeded.get("building_id", "")), {})
		_check(int(migrated_vertical.get("schema_version", -1)) == 10, "schema-eight building migrates to schema ten")
		_check(str(migrated_record.get("footprint_id", "")) == BuildingFootprintsScript.SINGLE_V1, "schema-eight building never guesses a larger legacy footprint")
		_check(Array(migrated_record.get("occupied_tile_ids", [])) == [anchor_tile_id], "schema-eight migration occupies only its anchor")
		_check(str(migrated_record.get(BuildingFootprintsScript.LEGACY_SINGLE_PROVENANCE_FIELD, "")) == BuildingFootprintsScript.LEGACY_SINGLE_PROVENANCE, "schema-eight migration marks its narrowed single-tile provenance")
		var migrated_reentry = GameSessionScript.new(251, 251)
		_check(migrated_reentry.restore_envelope(legacy_probe.make_envelope()), "schema-eight legacy single provenance remains readable after schema-ten round trip")
	for legacy_schema: int in [4, 5, 6, 7]:
		var older_data: Dictionary = current_envelope.to_dict()
		var older_vertical: Dictionary = older_data.get("state", {}).get("metadata", {}).get("vertical_slice", {})
		older_vertical["schema_version"] = legacy_schema
		if legacy_schema == SaveSchemaAuthorityScript.LEGACY_MIGRATION_VERTICAL_SCHEMA_VERSION:
			(older_vertical.get("terrain", {}) as Dictionary)["layout_version"] = SaveSchemaAuthorityScript.LEGACY_MIGRATION_TERRAIN_LAYOUT_VERSION
		for record_value: Variant in (older_data.get("state", {}).get("buildings", {}) as Dictionary).values():
			var older_record: Dictionary = record_value
			older_record.erase("anchor_tile_id")
			older_record.erase("footprint_id")
			older_record.erase("occupied_tile_ids")
		var older_envelope = SaveEnvelopeScript.from_dict(older_data)
		var older_probe = GameSessionScript.new(270 + legacy_schema, 270 + legacy_schema)
		_check(older_envelope != null and older_probe.restore_envelope(older_envelope), "schema %d legacy building restores" % legacy_schema)
		if older_probe.state == null:
			continue
		var older_record: Dictionary = older_probe.state.buildings.get(str(seeded.get("building_id", "")), {})
		_check(str(older_record.get("footprint_id", "")) == BuildingFootprintsScript.SINGLE_V1, "schema %d legacy building normalizes to single_v1" % legacy_schema)
		_check(str(older_record.get(BuildingFootprintsScript.LEGACY_SINGLE_PROVENANCE_FIELD, "")) == BuildingFootprintsScript.LEGACY_SINGLE_PROVENANCE, "schema %d legacy building records narrowed provenance" % legacy_schema)
		var older_coordinator = VerticalSliceCoordinatorScript.new(280 + legacy_schema, 280 + legacy_schema)
		older_coordinator.session = older_probe
		older_coordinator.call("_restore_subsystems")
		older_coordinator.call("_stash_subsystems")
		_check(int(older_coordinator.session.make_envelope().state.get("metadata", {}).get("vertical_slice", {}).get("schema_version", -1)) == 10, "schema %d legacy building writes schema ten after coordinator restore" % legacy_schema)

	var live_probe = GameSessionScript.new(26, 26)
	for corruption: String in ["missing", "duplicate", "offset_mismatch", "size_mismatch", "null_provenance", "invalid_provenance", "legacy_marker_shape", "out_of_bounds", "overlap", "future"]:
		var corrupted_data: Dictionary = current_envelope.to_dict()
		_apply_footprint_corruption(corrupted_data, corruption)
		var corrupted_envelope = SaveEnvelopeScript.from_dict(corrupted_data)
		var before_hash := live_probe.deterministic_hash()
		_check(corrupted_envelope != null, "%s footprint corruption reaches semantic validation" % corruption)
		_check(corrupted_envelope == null or not live_probe.restore_envelope(corrupted_envelope), "%s footprint corruption is rejected" % corruption)
		_check(live_probe.deterministic_hash() == before_hash, "%s footprint rejection has no partial apply" % corruption)

	var job_source = VerticalSliceCoordinatorScript.new(252, 500_000)
	var job_tiles := _find_free_buildable_run(job_source, 2)
	_check(job_tiles.size() == 2, "building-job footprint fixture finds two buildable tiles")
	if job_tiles.size() == 2:
		var job_start: Dictionary = job_source.start_approved_building("學校", int(job_tiles[0]), 5)
		_check(bool(job_start.get("ok", false)), "current medium building job starts for schema validation")
		if bool(job_start.get("ok", false)):
			job_source.call("_stash_subsystems")
			var current_job_data: Dictionary = job_source.session.make_envelope().to_dict()
			var job_id := str(job_start.get("job", {}).get("id", ""))
			var mismatched_job_data := current_job_data.duplicate(true)
			var mismatch_state: Dictionary = mismatched_job_data.get("state", {})
			var mismatch_vertical_job: Dictionary = mismatch_state.get("metadata", {}).get("vertical_slice", {}).get("construction", {}).get("jobs", {}).get(job_id, {})
			var mismatch_core_job: Dictionary = mismatch_state.get("construction_jobs", {}).get(job_id, {})
			(mismatch_vertical_job.get("blueprint", {}) as Dictionary)["size_tier"] = BuildingFootprintsScript.SMALL
			(mismatch_core_job.get("blueprint", {}) as Dictionary)["size_tier"] = BuildingFootprintsScript.SMALL
			var mismatched_job_envelope = SaveEnvelopeScript.from_dict(mismatched_job_data)
			var mismatched_job_probe = GameSessionScript.new(253, 253)
			_check(mismatched_job_envelope != null and not mismatched_job_probe.restore_envelope(mismatched_job_envelope), "schema-ten active job rejects blueprint size and footprint mismatch")

			var legacy_job_data := current_job_data.duplicate(true)
			var legacy_job_state: Dictionary = legacy_job_data.get("state", {})
			var legacy_job_vertical: Dictionary = legacy_job_state.get("metadata", {}).get("vertical_slice", {})
			legacy_job_vertical["schema_version"] = SaveSchemaAuthorityScript.FOOTPRINT_MIGRATION_VERTICAL_SCHEMA_VERSION
			for legacy_job_record: Dictionary in [
				legacy_job_vertical.get("construction", {}).get("jobs", {}).get(job_id, {}),
				legacy_job_state.get("construction_jobs", {}).get(job_id, {}),
			]:
				var legacy_job_metadata: Dictionary = legacy_job_record.get("metadata", {})
				legacy_job_metadata.erase("anchor_tile_id")
				legacy_job_metadata.erase("footprint_id")
				legacy_job_metadata.erase("occupied_tile_ids")
			var legacy_job_envelope = SaveEnvelopeScript.from_dict(legacy_job_data)
			var legacy_job_probe = GameSessionScript.new(254, 254)
			_check(legacy_job_envelope != null and legacy_job_probe.restore_envelope(legacy_job_envelope), "schema-eight active medium job migrates as a marked legacy single")
			if legacy_job_probe.state != null:
				var migrated_job: Dictionary = legacy_job_probe.state.metadata.get("vertical_slice", {}).get("construction", {}).get("jobs", {}).get(job_id, {})
				var migrated_job_metadata: Dictionary = migrated_job.get("metadata", {})
				_check(str(migrated_job.get("blueprint", {}).get("size_tier", "")) == BuildingFootprintsScript.MEDIUM, "legacy job preserves its historical medium blueprint")
				_check(str(migrated_job_metadata.get("footprint_id", "")) == BuildingFootprintsScript.SINGLE_V1, "legacy job narrows occupancy to single_v1")
				_check(Array(migrated_job_metadata.get("occupied_tile_ids", [])) == [int(job_tiles[0])], "legacy job occupies only its anchor")
				_check(str(migrated_job_metadata.get(BuildingFootprintsScript.LEGACY_SINGLE_PROVENANCE_FIELD, "")) == BuildingFootprintsScript.LEGACY_SINGLE_PROVENANCE, "legacy job records narrowed provenance")
				var legacy_job_reentry = GameSessionScript.new(255, 255)
				_check(legacy_job_reentry.restore_envelope(legacy_job_probe.make_envelope()), "marked legacy active job remains readable on schema-ten re-entry")


func _apply_footprint_corruption(data: Dictionary, corruption: String) -> void:
	var state_snapshot: Dictionary = data.get("state", {})
	var vertical: Dictionary = state_snapshot.get("metadata", {}).get("vertical_slice", {})
	var buildings: Dictionary = state_snapshot.get("buildings", {})
	var building_id := str(buildings.keys()[0])
	var record: Dictionary = buildings[building_id]
	match corruption:
		"missing":
			record.erase("occupied_tile_ids")
		"duplicate":
			record["occupied_tile_ids"] = [int(record.get("anchor_tile_id", -1)), int(record.get("anchor_tile_id", -1))]
		"offset_mismatch":
			record["footprint_id"] = BuildingFootprintsScript.LINE_2_EAST_V1
			record["occupied_tile_ids"] = [int(record.get("anchor_tile_id", -1))]
		"size_mismatch":
			(record.get("blueprint", {}) as Dictionary)["size_tier"] = BuildingFootprintsScript.MEDIUM
		"null_provenance":
			record[BuildingFootprintsScript.LEGACY_SINGLE_PROVENANCE_FIELD] = null
		"invalid_provenance":
			record[BuildingFootprintsScript.LEGACY_SINGLE_PROVENANCE_FIELD] = "forged_legacy_marker"
		"legacy_marker_shape":
			var terrain = CityTerrainMapScript.new()
			var anchor := int(record.get("anchor_tile_id", -1))
			var coordinate := terrain.coordinate_for_tile_id(anchor)
			record["footprint_id"] = BuildingFootprintsScript.LINE_2_EAST_V1
			record["occupied_tile_ids"] = [anchor, terrain.tile_id_for_coordinate(coordinate + Vector2i(1, 0))]
			record[BuildingFootprintsScript.LEGACY_SINGLE_PROVENANCE_FIELD] = BuildingFootprintsScript.LEGACY_SINGLE_PROVENANCE
		"out_of_bounds":
			var terrain = CityTerrainMapScript.new()
			var east_anchor := terrain.tile_id_for_coordinate(Vector2i(9, 0))
			record["tile_index"] = east_anchor
			record["anchor_tile_id"] = east_anchor
			record["footprint_id"] = BuildingFootprintsScript.LINE_3_EAST_V1
			record["occupied_tile_ids"] = [east_anchor]
		"overlap":
			var duplicate := record.duplicate(true)
			duplicate["building_id"] = "building_000999"
			buildings["building_000999"] = duplicate
			vertical["next_building_sequence"] = 1000
		"future":
			vertical["schema_version"] = SaveSchemaAuthorityScript.CURRENT_VERTICAL_SCHEMA_VERSION + 1


func _test_schema_authority_registry_contract() -> void:
	var registry_json := FileAccess.get_file_as_string(SCHEMA_AUTHORITY_REGISTRY_PATH)
	_check(not registry_json.is_empty(), "schema authority registry fixture is present")
	_check(
		SaveSchemaAuthorityScript.validate_registry_json(registry_json),
		"registry current and planned pairs agree with authority constants"
	)
	_check(
		not SaveSchemaAuthorityScript.validate_registry_json(""),
		"missing registry text fails safely"
	)
	_check(
		not SaveSchemaAuthorityScript.validate_registry_json("{ malformed"),
		"malformed registry JSON fails safely"
	)
	var registry_value: Variant = JSON.parse_string(registry_json)
	_check(registry_value is Dictionary, "registry fixture parses for missing-field coverage")
	if registry_value is Dictionary:
		var missing_current_writer: Dictionary = (registry_value as Dictionary).duplicate(true)
		missing_current_writer.erase("current_writer")
		_check(
			not SaveSchemaAuthorityScript.validate_registry_json(JSON.stringify(missing_current_writer)),
			"registry missing current writer fails safely"
		)
		var extra_writer: Dictionary = (registry_value as Dictionary).duplicate(true)
		extra_writer["additional_writer"] = {
			"id": "forged_future_writer",
			"writer_allowed": true,
		}
		_check(
			not SaveSchemaAuthorityScript.validate_registry_json(JSON.stringify(extra_writer)),
			"registry with an additional future writer fails safely"
		)
		var fabricated_migration: Dictionary = (registry_value as Dictionary).duplicate(true)
		fabricated_migration["migration_registry"].append({
			"id": "fabricated_npc_migration",
			"status": "active",
		})
		_check(
			not SaveSchemaAuthorityScript.validate_registry_json(JSON.stringify(fabricated_migration)),
			"registry rejects migration claims without a real implementation and fixture"
		)


func _test_schema_authority_runtime_constants() -> void:
	_check(SaveEnvelopeScript.CURRENT_SCHEMA_VERSION == SaveSchemaAuthorityScript.SAVE_ENVELOPE_CURRENT_SCHEMA_VERSION, "SaveEnvelope current schema uses the shared authority")
	_check(SaveEnvelopeScript.MIN_SUPPORTED_SCHEMA_VERSION == SaveSchemaAuthorityScript.SAVE_ENVELOPE_MIN_SUPPORTED_SCHEMA_VERSION, "SaveEnvelope minimum schema uses the shared authority")
	_check(SaveEnvelopeScript.MAX_SUPPORTED_SCHEMA_VERSION == SaveSchemaAuthorityScript.SAVE_ENVELOPE_MAX_SUPPORTED_SCHEMA_VERSION, "SaveEnvelope ceiling uses the shared authority")
	_check(CityStateScript.SNAPSHOT_SCHEMA_VERSION == SaveSchemaAuthorityScript.CITY_STATE_CURRENT_SCHEMA_VERSION, "CityState current schema uses the shared authority")
	_check(CityStateScript.MIN_SUPPORTED_SNAPSHOT_SCHEMA_VERSION == SaveSchemaAuthorityScript.CITY_STATE_MIN_SUPPORTED_SCHEMA_VERSION, "CityState minimum schema uses the shared authority")
	_check(CityStateScript.MAX_SUPPORTED_SNAPSHOT_SCHEMA_VERSION == SaveSchemaAuthorityScript.CITY_STATE_MAX_SUPPORTED_SCHEMA_VERSION, "CityState ceiling uses the shared authority")
	_check(GameSessionScript.MAX_SUPPORTED_VERTICAL_SLICE_METADATA_SCHEMA == SaveSchemaAuthorityScript.MAX_SUPPORTED_VERTICAL_SLICE_METADATA_SCHEMA, "vertical schema ceiling uses the shared authority")
	_check(GameSessionScript.MIN_SUPPORTED_VERTICAL_SLICE_METADATA_SCHEMA == SaveSchemaAuthorityScript.MIN_SUPPORTED_VERTICAL_SLICE_METADATA_SCHEMA, "vertical schema floor uses the shared authority")
	_check(SaveSchemaAuthorityScript.SUPPORTED_VERTICAL_SLICE_METADATA_SCHEMAS == [4, 5, 6, 7, 8, 9, 10], "vertical support is limited to proven schema shapes")
	for unsupported_schema: int in [0, 1, 2, 3]:
		_check(not SaveSchemaAuthorityScript.is_supported_vertical_schema(unsupported_schema), "unproven vertical schema %d is explicitly unsupported" % unsupported_schema)
	_check(CityTerrainMapScript.LAYOUT_VERSION == SaveSchemaAuthorityScript.CURRENT_TERRAIN_LAYOUT_VERSION, "terrain current layout agrees with the shared authority")
	_check(CityTerrainMapScript.LAYOUT_VERSION == SaveSchemaAuthorityScript.MAX_SUPPORTED_TERRAIN_LAYOUT_VERSION, "terrain layout ceiling agrees with current runtime")
	_check(PopulationSystemScript.SCHEMA_VERSION == SaveSchemaAuthorityScript.POPULATION_CURRENT_SCHEMA_VERSION, "population current schema uses the shared authority")
	_check(PopulationSystemScript.MIN_SUPPORTED_SCHEMA_VERSION == SaveSchemaAuthorityScript.POPULATION_MIN_SUPPORTED_SCHEMA_VERSION, "population minimum schema uses the shared authority")
	_check(PopulationSystemScript.MAX_SUPPORTED_SCHEMA_VERSION == SaveSchemaAuthorityScript.POPULATION_MAX_SUPPORTED_SCHEMA_VERSION, "population ceiling uses the shared authority")
	_check(NpcRecordScript.SCHEMA_VERSION == SaveSchemaAuthorityScript.NPC_RECORD_CURRENT_SCHEMA_VERSION, "NPC current schema uses the shared authority")
	_check(NpcRecordScript.MIN_SUPPORTED_SCHEMA_VERSION == SaveSchemaAuthorityScript.NPC_RECORD_MIN_SUPPORTED_SCHEMA_VERSION, "NPC minimum schema uses the shared authority")
	_check(NpcRecordScript.MAX_SUPPORTED_SCHEMA_VERSION == SaveSchemaAuthorityScript.NPC_RECORD_MAX_SUPPORTED_SCHEMA_VERSION, "NPC ceiling uses the shared authority")
	_check(GameSessionScript.MAX_SUPPORTED_POPULATION_SCHEMA == PopulationSystemScript.MAX_SUPPORTED_SCHEMA_VERSION, "GameSession population ceiling cannot drift from PopulationSystem")
	_check(GameSessionScript.MAX_SUPPORTED_NPC_RECORD_SCHEMA == NpcRecordScript.MAX_SUPPORTED_SCHEMA_VERSION, "GameSession NPC ceiling cannot drift from MayorNpcRecord")
	_check(PopulationSystemScript.MAX_POPULATION == 200_000, "persisted population ceiling is 200000")


func _test_city_state_population_migration_boundary() -> void:
	var legacy_data := _read_fixture_dictionary(SUPPORTED_LEGACY_FIXTURE_PATH)
	_check(not legacy_data.is_empty(), "CityState v1 migration fixture is readable")
	if legacy_data.is_empty():
		return
	var valid_legacy = SaveEnvelopeScript.from_dict(legacy_data)
	var valid_probe = GameSessionScript.new(811, 811)
	_check(valid_legacy != null and valid_probe.restore_envelope(valid_legacy), "matching CityState v1 NPC mirror migrates")
	if valid_probe.state != null:
		var migrated_snapshot: Dictionary = valid_probe.make_envelope().state
		_check(int(migrated_snapshot.get("schema_version", -1)) == SaveSchemaAuthorityScript.CITY_STATE_CURRENT_SCHEMA_VERSION, "CityState v1 migration writes schema two")
		_check(not migrated_snapshot.has("npcs"), "migrated CityState writer removes the persisted NPC mirror")
		_check(valid_probe.state.npcs.size() == 1, "migrated CityState rebuilds the runtime NPC lookup")

	var live_session = GameSessionScript.new(812, 812)
	for case_name: String in ["record_mismatch", "duplicate_canonical_id", "missing_mirror_id", "invalid_canonical_record", "core_only_population"]:
		var corrupted := legacy_data.duplicate(true)
		_apply_city_state_population_corruption(corrupted, case_name)
		var candidate = SaveEnvelopeScript.from_dict(corrupted)
		var before_hash := live_session.deterministic_hash()
		_check(candidate != null, "%s reaches CityState migration validation" % case_name)
		_check(candidate == null or not live_session.restore_envelope(candidate), "%s is rejected" % case_name)
		_check(live_session.deterministic_hash() == before_hash, "%s does not partially apply" % case_name)

	var current_coordinator = VerticalSliceCoordinatorScript.new(813, 813_000)
	current_coordinator.call("_stash_subsystems")
	var current_envelope = current_coordinator.session.make_envelope()
	var current_state: Dictionary = current_envelope.state
	var current_population: Dictionary = current_state.get("metadata", {}).get("vertical_slice", {}).get("population", {})
	_check(int(current_state.get("schema_version", -1)) == 2, "current writer uses CityState schema two")
	_check(not current_state.has("npcs"), "current writer persists no CityState NPC mirror")
	_check(Array(current_population.get("records", [])).size() == 300, "current writer persists all 300 records once under canonical population")
	var current_probe = GameSessionScript.new(814, 814)
	_check(current_probe.restore_envelope(current_envelope), "current CityState v2 envelope restores")
	_check(current_probe.state != null and current_probe.state.npcs.size() == 300, "current restore hydrates 300 runtime NPC records")
	var capacity_coordinator = VerticalSliceCoordinatorScript.new(815, 815_000, 500)
	capacity_coordinator.call("_stash_subsystems")
	var capacity_envelope = capacity_coordinator.session.make_envelope()
	var capacity_probe = GameSessionScript.new(816, 816)
	_check(capacity_probe.restore_envelope(capacity_envelope), "current 500-resident save remains readable")
	_check(capacity_probe.state != null and capacity_probe.state.npcs.size() == 500, "current 500-resident save hydrates every runtime NPC")
	var legacy_capacity_data: Dictionary = capacity_envelope.to_dict()
	var legacy_capacity_population: Dictionary = legacy_capacity_data.get("state", {}).get("metadata", {}).get("vertical_slice", {}).get("population", {})
	legacy_capacity_population["schema_version"] = 1
	legacy_capacity_population.erase("next_transaction_sequence")
	legacy_capacity_population.erase("income_transactions")
	for record_value: Variant in legacy_capacity_population.get("records", []):
		var legacy_record: Dictionary = record_value
		legacy_record["schema_version"] = 1
		for current_only_field: String in ["personality_tags", "appearance_tags", "salary", "debt"]:
			legacy_record.erase(current_only_field)
	var legacy_capacity_envelope = SaveEnvelopeScript.from_dict(legacy_capacity_data)
	var legacy_capacity_probe = GameSessionScript.new(817, 817)
	_check(legacy_capacity_envelope != null and legacy_capacity_probe.restore_envelope(legacy_capacity_envelope), "legacy 500-resident save remains readable")
	_check(legacy_capacity_probe.state != null and legacy_capacity_probe.state.npcs.size() == 500, "legacy 500-resident save hydrates every runtime NPC")
	var future_state_data: Dictionary = current_envelope.to_dict()
	(future_state_data["state"] as Dictionary)["schema_version"] = SaveSchemaAuthorityScript.CITY_STATE_MAX_SUPPORTED_SCHEMA_VERSION + 1
	var future_state_envelope = SaveEnvelopeScript.from_dict(future_state_data)
	var future_hash := current_probe.deterministic_hash()
	_check(future_state_envelope != null and not current_probe.restore_envelope(future_state_envelope), "future CityState schema is explicitly rejected")
	_check(current_probe.deterministic_hash() == future_hash, "future CityState rejection does not overwrite the live session")
	var over_ceiling_data: Dictionary = current_envelope.to_dict()
	var over_ceiling_state: Dictionary = over_ceiling_data.get("state", {})
	var over_ceiling_population: Dictionary = over_ceiling_state.get("metadata", {}).get("vertical_slice", {}).get("population", {})
	var over_ceiling_records: Array = []
	over_ceiling_records.resize(PopulationSystemScript.MAX_POPULATION + 1)
	over_ceiling_population["records"] = over_ceiling_records
	over_ceiling_population["next_npc_sequence"] = PopulationSystemScript.MAX_POPULATION + 2
	(over_ceiling_state.get("metrics", {}) as Dictionary)["population"] = over_ceiling_records.size()
	var over_ceiling_envelope = SaveEnvelopeScript.from_dict(over_ceiling_data)
	var ceiling_hash := current_probe.deterministic_hash()
	_check(over_ceiling_records.size() == 200_001, "over-ceiling fixture declares 200001 NPC slots")
	_check(over_ceiling_envelope != null and not current_probe.restore_envelope(over_ceiling_envelope), "persisted population above 200000 is rejected")
	_check(current_probe.deterministic_hash() == ceiling_hash, "population ceiling rejection does not overwrite the live session")


func _apply_city_state_population_corruption(data: Dictionary, case_name: String) -> void:
	var state_snapshot: Dictionary = data.get("state", {})
	var vertical: Dictionary = state_snapshot.get("metadata", {}).get("vertical_slice", {})
	var population: Dictionary = vertical.get("population", {})
	var records: Array = population.get("records", [])
	match case_name:
		"record_mismatch":
			var mirror: Dictionary = state_snapshot.get("npcs", {})
			var record: Dictionary = mirror.get("npc_000001", {})
			record["income"] = int(record.get("income", 0)) + 1
		"duplicate_canonical_id":
			records.append(Dictionary(records[0]).duplicate(true))
		"missing_mirror_id":
			(state_snapshot.get("npcs", {}) as Dictionary).erase("npc_000001")
		"invalid_canonical_record":
			records[0] = "invalid"
		"core_only_population":
			vertical.erase("population")


func _test_non_vertical_runtime_population_save_gate() -> void:
	_cleanup_path(RUNTIME_POPULATION_GATE_PATH)
	var session = GameSessionScript.new(901, 9_001)
	_check(session.save_now(RUNTIME_POPULATION_GATE_PATH) == OK, "non-vertical empty-population primary save succeeds")
	_check(session.save_now(RUNTIME_POPULATION_GATE_PATH) == OK, "non-vertical empty-population backup save succeeds")
	var primary_before := _read_text(RUNTIME_POPULATION_GATE_PATH)
	var backup_before := _read_text(RUNTIME_POPULATION_GATE_PATH + ".bak")
	var runtime_population = PopulationSystemScript.new()
	runtime_population.initialize(1, 901)
	_check(session.hydrate_runtime_population(runtime_population.to_dict()), "non-vertical fixture hydrates one runtime NPC")
	session.state.metrics["population"] = 1
	var missing_canonical_hash := session.deterministic_hash()
	_check(session.save_now(RUNTIME_POPULATION_GATE_PATH) == ERR_INVALID_DATA, "non-empty runtime NPCs without canonical metadata are rejected before save I/O")
	_check(session.deterministic_hash() == missing_canonical_hash, "missing-canonical save rejection does not mutate the live session")
	_check(_read_text(RUNTIME_POPULATION_GATE_PATH) == primary_before, "missing-canonical rejection preserves the primary byte-for-byte")
	_check(_read_text(RUNTIME_POPULATION_GATE_PATH + ".bak") == backup_before, "missing-canonical rejection preserves the backup byte-for-byte")

	session.state.metadata["vertical_slice"] = {
		"schema_version": SaveSchemaAuthorityScript.CURRENT_VERTICAL_SCHEMA_VERSION,
		"population": runtime_population.to_dict(),
	}
	var runtime_id := str(runtime_population.sorted_npc_ids()[0])
	(session.state.npcs[runtime_id] as Dictionary)["income"] = int((session.state.npcs[runtime_id] as Dictionary).get("income", 0)) + 1
	var mismatch_hash := session.deterministic_hash()
	_check(session.save_now(RUNTIME_POPULATION_GATE_PATH) == ERR_INVALID_DATA, "runtime/canonical full-record mismatch is rejected before save I/O")
	_check(session.deterministic_hash() == mismatch_hash, "runtime mismatch rejection does not mutate the live session")
	_check(_read_text(RUNTIME_POPULATION_GATE_PATH) == primary_before, "runtime mismatch rejection preserves the primary byte-for-byte")
	_check(_read_text(RUNTIME_POPULATION_GATE_PATH + ".bak") == backup_before, "runtime mismatch rejection preserves the backup byte-for-byte")


func _test_strict_population_restore_boundary() -> void:
	var coordinator = VerticalSliceCoordinatorScript.new(902, 902_000)
	coordinator.call("_stash_subsystems")
	var base_data: Dictionary = coordinator.session.make_envelope().to_dict()
	var live_session = GameSessionScript.new(903, 903_000)
	for case_name: String in ["malformed_record", "malformed_request", "malformed_transaction", "malformed_event"]:
		var malformed := base_data.duplicate(true)
		_apply_strict_population_corruption(malformed, case_name)
		var malformed_population: Dictionary = malformed.get("state", {}).get("metadata", {}).get("vertical_slice", {}).get("population", {})
		_check(PopulationSystemScript.from_dict(malformed_population) == null, "%s fails the strict PopulationSystem parser" % case_name)
		var candidate = SaveEnvelopeScript.from_dict(malformed)
		var before_hash := live_session.deterministic_hash()
		_check(candidate != null, "%s remains dictionary-shaped through envelope decoding" % case_name)
		_check(candidate == null or not live_session.restore_envelope(candidate), "%s is rejected before live-session assignment" % case_name)
		_check(live_session.deterministic_hash() == before_hash, "%s rejection has no partial apply" % case_name)


func _apply_strict_population_corruption(data: Dictionary, case_name: String) -> void:
	var population: Dictionary = data.get("state", {}).get("metadata", {}).get("vertical_slice", {}).get("population", {})
	var first_npc_id := str(population.get("records", [])[0].get("npc_id", ""))
	match case_name:
		"malformed_record":
			(population.get("records", [])[0] as Dictionary)["age"] = "40"
		"malformed_request":
			(population.get("requests", []) as Array).append({
				"schema_version": 2,
				"request_id": "request_000001",
				"npc_id": first_npc_id,
				"request_type": "park",
				"title": "Malformed request",
				"description": "",
				"status": "pending",
				"created_day": "0",
				"accepted_day": -1,
				"rejected_day": -1,
				"completed_day": -1,
				"payload": {},
			})
		"malformed_transaction":
			(population.get("income_transactions", []) as Array).append({
				"transaction_id": "income_tx_0000000001",
				"npc_id": first_npc_id,
				"game_day": 0,
				"source_type": "salary",
				"amount": "100",
				"metadata": {},
			})
		"malformed_event":
			var event_book: Dictionary = population.get("event_book", {})
			event_book["next_sequence"] = int(event_book.get("next_sequence", 1)) + 1
			(event_book.get("events", []) as Array).append({
				"sequence": int(event_book["next_sequence"]) - 1,
				"game_day": "0",
				"event_type": "malformed_event",
				"subject_id": first_npc_id,
				"reason_tag": "test.malformed",
				"data": {},
			})


func _test_tracked_schema_fixtures() -> void:
	var current_data := _read_fixture_dictionary(CURRENT_ROUND_TRIP_FIXTURE_PATH)
	_check(not current_data.is_empty(), "tracked current round-trip fixture is readable")
	if current_data.is_empty():
		return
	var current_envelope = SaveEnvelopeScript.from_dict(current_data)
	_check(current_envelope != null, "tracked current fixture decodes as SaveEnvelope")
	if current_envelope == null:
		return
	_assert_fixture_versions(current_envelope, true, "tracked current fixture")
	var current_probe = GameSessionScript.new(301, 301)
	_check(current_probe.restore_envelope(current_envelope), "tracked current fixture restores")
	if current_probe.state != null:
		var round_trip = current_probe.make_envelope()
		_check(not round_trip.state.has("npcs"), "tracked current fixture persists the population only once")
		_check(
			_canonical_fixture_json(round_trip.to_dict()) == _canonical_fixture_json(current_envelope.to_dict()),
			"tracked current fixture round-trips without field loss"
		)

	var legacy_data := _read_fixture_dictionary(SUPPORTED_LEGACY_FIXTURE_PATH)
	_check(not legacy_data.is_empty(), "tracked supported legacy fixture is readable")
	var legacy_envelope = SaveEnvelopeScript.from_dict(legacy_data) if not legacy_data.is_empty() else null
	_check(legacy_envelope != null, "tracked supported legacy fixture decodes as SaveEnvelope")
	if legacy_envelope != null:
		var legacy_vertical: Dictionary = legacy_envelope.state.get("metadata", {}).get("vertical_slice", {})
		var legacy_tiles_json := _canonical_fixture_json(legacy_vertical.get("terrain", {}).get("tiles", []))
		_check(int(legacy_vertical.get("schema_version", -1)) == SaveSchemaAuthorityScript.LEGACY_MIGRATION_VERTICAL_SCHEMA_VERSION, "legacy fixture starts at vertical schema seven")
		_check(int(legacy_vertical.get("terrain", {}).get("layout_version", -1)) == SaveSchemaAuthorityScript.LEGACY_MIGRATION_TERRAIN_LAYOUT_VERSION, "legacy fixture starts at terrain layout two")
		_check(int(legacy_vertical.get("population", {}).get("schema_version", -1)) == PopulationSystemScript.MIN_SUPPORTED_SCHEMA_VERSION, "legacy fixture covers population schema one direct-read compatibility")
		_check(int(legacy_vertical.get("population", {}).get("records", [])[0].get("schema_version", -1)) == NpcRecordScript.MIN_SUPPORTED_SCHEMA_VERSION, "legacy fixture covers NPC schema one direct-read compatibility")
		var legacy_probe = GameSessionScript.new(302, 302)
		_check(legacy_probe.restore_envelope(legacy_envelope), "tracked supported legacy fixture restores through the real migration path")
		if legacy_probe.state != null:
			var migrated_vertical: Dictionary = legacy_probe.state.metadata.get("vertical_slice", {})
			_check(int(migrated_vertical.get("schema_version", -1)) == SaveSchemaAuthorityScript.CURRENT_VERTICAL_SCHEMA_VERSION, "legacy fixture migrates to current vertical schema")
			_check(int(migrated_vertical.get("terrain", {}).get("layout_version", -1)) == SaveSchemaAuthorityScript.CURRENT_TERRAIN_LAYOUT_VERSION, "legacy fixture migrates to terrain layout three")
			_check(_canonical_fixture_json(migrated_vertical.get("terrain", {}).get("tiles", [])) == legacy_tiles_json, "tracked migration preserves every terrain record")
			var legacy_population = PopulationSystemScript.from_dict(migrated_vertical.get("population", {}))
			_check(legacy_population != null and legacy_population.records.size() == 1, "population schema one fixture remains directly readable")
			var legacy_record = NpcRecordScript.from_dict(migrated_vertical.get("population", {}).get("records", [])[0])
			_check(legacy_record != null and legacy_record.salary == null and legacy_record.debt == null, "NPC schema one fixture uses compatibility defaults without a fabricated migration")

	var oldest_data := _read_fixture_dictionary(OLDEST_SUPPORTED_FIXTURE_PATH)
	_check(not oldest_data.is_empty(), "tracked oldest-supported fixture is readable")
	var oldest_envelope = SaveEnvelopeScript.from_dict(oldest_data) if not oldest_data.is_empty() else null
	_check(oldest_envelope != null, "tracked vertical schema four fixture decodes as SaveEnvelope")
	if oldest_envelope != null:
		_check(int(oldest_envelope.state.get("schema_version", -1)) == 1, "oldest-supported fixture starts at CityState schema one")
		_check(int(oldest_envelope.state.get("metadata", {}).get("vertical_slice", {}).get("schema_version", -1)) == SaveSchemaAuthorityScript.MIN_SUPPORTED_VERTICAL_SLICE_METADATA_SCHEMA, "oldest-supported fixture starts at vertical schema four")
		var oldest_probe = GameSessionScript.new(304, 304)
		_check(oldest_probe.restore_envelope(oldest_envelope), "oldest-supported vertical schema four restores")
		_check(oldest_probe.state != null and oldest_probe.state.npcs.size() == 1, "oldest-supported restore preserves its complete resident")
		_check(not oldest_probe.make_envelope().state.has("npcs"), "oldest-supported restore upgrades to the CityState v2 single-copy writer")

	var unsupported_vertical_data := _read_fixture_dictionary(UNSUPPORTED_VERTICAL_FIXTURE_PATH)
	_check(not unsupported_vertical_data.is_empty(), "tracked unsupported vertical fixture is readable")
	var unsupported_vertical_envelope = SaveEnvelopeScript.from_dict(unsupported_vertical_data) if not unsupported_vertical_data.is_empty() else null
	var unsupported_vertical_probe = GameSessionScript.new(305, 305)
	var unsupported_vertical_hash := unsupported_vertical_probe.deterministic_hash()
	_check(unsupported_vertical_envelope != null, "tracked vertical schema three fixture reaches restore validation")
	_check(unsupported_vertical_envelope == null or not unsupported_vertical_probe.restore_envelope(unsupported_vertical_envelope), "unproven vertical schema three is explicitly rejected")
	_check(unsupported_vertical_probe.deterministic_hash() == unsupported_vertical_hash, "unsupported vertical schema rejection does not partially apply")

	var live_session = GameSessionScript.new(303, 303)
	live_session.advance_days_for_test(2)
	var live_hash := live_session.deterministic_hash()
	var future_data := _read_fixture_dictionary(FUTURE_REJECT_FIXTURE_PATH)
	_check(not future_data.is_empty(), "tracked future fixture is readable")
	var future_envelope = SaveEnvelopeScript.from_dict(future_data) if not future_data.is_empty() else null
	_check(future_envelope != null, "tracked future fixture reaches semantic validation")
	_check(int(future_envelope.state.get("schema_version", -1)) > SaveSchemaAuthorityScript.CITY_STATE_MAX_SUPPORTED_SCHEMA_VERSION, "tracked future fixture targets CityState schema rejection")
	_check(not live_session.restore_envelope(future_envelope), "tracked future fixture is explicitly rejected")
	_check(live_session.deterministic_hash() == live_hash, "future rejection does not overwrite the live session")

	var unsupported_data := current_data.duplicate(true)
	var unsupported_state: Dictionary = unsupported_data.get("state", {}).duplicate(true)
	var unsupported_metadata: Dictionary = unsupported_state.get("metadata", {}).duplicate(true)
	var unsupported_vertical: Dictionary = unsupported_metadata.get("vertical_slice", {}).duplicate(true)
	var unsupported_population: Dictionary = unsupported_vertical.get("population", {}).duplicate(true)
	var unsupported_records: Array = unsupported_population.get("records", []).duplicate(true)
	var unsupported_record: Dictionary = Dictionary(unsupported_records[0]).duplicate(true)
	unsupported_record["schema_version"] = NpcRecordScript.MIN_SUPPORTED_SCHEMA_VERSION - 1
	unsupported_records[0] = unsupported_record
	unsupported_population["records"] = unsupported_records
	unsupported_vertical["population"] = unsupported_population
	unsupported_metadata["vertical_slice"] = unsupported_vertical
	unsupported_state["metadata"] = unsupported_metadata
	unsupported_data["state"] = unsupported_state
	var unsupported_envelope = SaveEnvelopeScript.from_dict(unsupported_data)
	_check(unsupported_envelope != null, "unsupported NPC fixture reaches semantic validation")
	_check(not live_session.restore_envelope(unsupported_envelope), "unsupported NPC schema is explicitly rejected")
	_check(live_session.deterministic_hash() == live_hash, "unsupported rejection does not overwrite the live session")

	var corrupt_data := _read_fixture_dictionary(CORRUPT_MINIMAL_FIXTURE_PATH)
	_check(not corrupt_data.is_empty(), "tracked corrupt-minimal fixture is readable JSON")
	var corrupt_envelope = SaveEnvelopeScript.from_dict(corrupt_data) if not corrupt_data.is_empty() else null
	_check(corrupt_envelope != null, "tracked corrupt-minimal fixture reaches semantic validation")
	_check(not live_session.restore_envelope(corrupt_envelope), "tracked corrupt-minimal fixture is rejected")
	_check(live_session.deterministic_hash() == live_hash, "corrupt rejection does not overwrite the live session")

	var future_npc_data: Dictionary = unsupported_record.duplicate(true)
	future_npc_data["schema_version"] = NpcRecordScript.MAX_SUPPORTED_SCHEMA_VERSION + 1
	_check(NpcRecordScript.from_dict(future_npc_data) == null, "MayorNpcRecord rejects a future schema at its own boundary")
	var future_population_data: Dictionary = unsupported_population.duplicate(true)
	future_population_data["schema_version"] = PopulationSystemScript.MAX_SUPPORTED_SCHEMA_VERSION + 1
	_check(PopulationSystemScript.from_dict(future_population_data) == null, "PopulationSystem rejects a future schema at its own boundary")


func _assert_fixture_versions(envelope, current: bool, label: String) -> void:
	var expected_city_state := SaveSchemaAuthorityScript.CITY_STATE_CURRENT_SCHEMA_VERSION if current else SaveSchemaAuthorityScript.CITY_STATE_MIN_SUPPORTED_SCHEMA_VERSION
	var expected_vertical := SaveSchemaAuthorityScript.CURRENT_VERTICAL_SCHEMA_VERSION if current else SaveSchemaAuthorityScript.LEGACY_MIGRATION_VERTICAL_SCHEMA_VERSION
	var expected_terrain := SaveSchemaAuthorityScript.CURRENT_TERRAIN_LAYOUT_VERSION if current else SaveSchemaAuthorityScript.LEGACY_MIGRATION_TERRAIN_LAYOUT_VERSION
	var vertical: Dictionary = envelope.state.get("metadata", {}).get("vertical_slice", {})
	var records: Array = vertical.get("population", {}).get("records", [])
	_check(envelope.schema_version == SaveSchemaAuthorityScript.SAVE_ENVELOPE_CURRENT_SCHEMA_VERSION, "%s has SaveEnvelope schema one" % label)
	_check(int(envelope.state.get("schema_version", -1)) == expected_city_state, "%s has the expected CityState schema" % label)
	_check(envelope.state.has("npcs") != current, "%s has the expected persisted NPC mirror shape" % label)
	_check(int(vertical.get("schema_version", -1)) == expected_vertical, "%s has the expected vertical schema" % label)
	_check(int(vertical.get("terrain", {}).get("layout_version", -1)) == expected_terrain, "%s has the expected terrain layout" % label)
	_check(int(vertical.get("population", {}).get("schema_version", -1)) in [1, 2], "%s has a supported population schema" % label)
	_check(not records.is_empty() and int(records[0].get("schema_version", -1)) in [1, 2], "%s has a supported NPC record schema" % label)


func _read_fixture_dictionary(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(_read_text(path))
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _canonical_fixture_json(value: Variant) -> String:
	return JSON.stringify(_canonical_fixture_value(value))


func _canonical_fixture_value(value: Variant) -> Variant:
	if value is Dictionary:
		var source: Dictionary = value
		var keys: Array = source.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		var result := {}
		for key: Variant in keys:
			result[str(key)] = _canonical_fixture_value(source[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_canonical_fixture_value(item))
		return result
	if value is PackedStringArray:
		return Array(value)
	if value is int:
		return float(value)
	return value


func _test_current_schema_non_transport_corruption_uses_backup() -> void:
	var corruption_cases: Array[String] = [
		"construction_not_dictionary",
		"reviews_not_dictionary",
		"jobs_not_dictionary",
		"review_record_not_dictionary",
		"job_record_not_dictionary",
		"blueprint_library_not_dictionary",
		"active_blueprints_not_dictionary",
		"active_blueprint_missing_library_id",
		"construction_core_mismatch",
		"demolition_status_without_job",
		"demolition_job_without_status",
		"duplicate_demolition_jobs",
	]
	for case_name: String in corruption_cases:
		var fixture := _seed_valid_current_schema_pair(CURRENT_SCHEMA_NON_TRANSPORT_PATH)
		var primary_data: Variant = JSON.parse_string(_read_text(CURRENT_SCHEMA_NON_TRANSPORT_PATH))
		_check(primary_data is Dictionary, "%s fixture starts as valid JSON" % case_name)
		if not primary_data is Dictionary:
			continue
		var state_value: Variant = (primary_data as Dictionary).get("state", null)
		if not state_value is Dictionary:
			_check(false, "%s fixture contains a state dictionary" % case_name)
			continue
		var state_snapshot: Dictionary = state_value
		var metadata_value: Variant = state_snapshot.get("metadata", null)
		if not metadata_value is Dictionary:
			_check(false, "%s fixture contains metadata" % case_name)
			continue
		var vertical_value: Variant = (metadata_value as Dictionary).get("vertical_slice", null)
		if not vertical_value is Dictionary:
			_check(false, "%s fixture contains current vertical metadata" % case_name)
			continue
		var vertical: Dictionary = vertical_value
		_apply_non_transport_corruption(case_name, vertical, state_snapshot)
		_check(
			_write_text(CURRENT_SCHEMA_NON_TRANSPORT_PATH, JSON.stringify(primary_data, "\t", false)),
			"%s primary corruption remains well-formed JSON" % case_name
		)
		var decoder = SaveServiceScript.new()
		var corrupted_envelope = decoder.load_primary_envelope(CURRENT_SCHEMA_NON_TRANSPORT_PATH)
		_check(corrupted_envelope != null, "%s corruption passes outer envelope decoding" % case_name)
		if corrupted_envelope == null:
			continue
		var semantic_probe = GameSessionScript.new(19, 19)
		var probe_hash_before := semantic_probe.deterministic_hash()
		_check(not semantic_probe.restore_envelope(corrupted_envelope), "%s corruption is rejected before restore" % case_name)
		_check(semantic_probe.deterministic_hash() == probe_hash_before, "%s rejection does not partially apply state" % case_name)

		var restored = GameSessionScript.new(20, 20)
		_check(restored.load_now(CURRENT_SCHEMA_NON_TRANSPORT_PATH), "%s corruption falls back to the valid backup" % case_name)
		_check(restored.save_service.last_load_source == SaveServiceScript.LOAD_SOURCE_BACKUP, "%s recovery records backup source" % case_name)
		_check(restored.save_service.last_recovery_error == OK, "%s recovery safely rebuilds primary" % case_name)
		_check(restored.deterministic_hash() == str(fixture["hash"]), "%s recovery restores the exact backup state" % case_name)
		_check(_read_text(CURRENT_SCHEMA_NON_TRANSPORT_PATH) == _read_text(CURRENT_SCHEMA_NON_TRANSPORT_PATH + ".bak"), "%s recovery never leaves a partially accepted primary" % case_name)


func _test_current_schema_cross_layer_corruption_uses_backup() -> void:
	var corruption_cases: Array[Dictionary] = [
		{"name": "runtime_processed_duplicate_id", "fixture": "base"},
		{"name": "runtime_pending_duplicate_id", "fixture": "pending_command"},
		{"name": "runtime_pending_processed_overlap", "fixture": "pending_command"},
		{"name": "stale_next_building_sequence", "fixture": "building"},
		{"name": "core_building_not_dictionary", "fixture": "building"},
		{"name": "core_building_invalid_current_status", "fixture": "building"},
		{"name": "stale_next_operation_sequence", "fixture": "base"},
		{
			"name": "stale_next_blueprint_sequence_pending_review",
			"fixture": "player_blueprint_pending",
			"construction_valid": true,
			"blueprint_valid": true,
		},
		{
			"name": "stale_next_blueprint_sequence_rejected_review",
			"fixture": "player_blueprint_rejected",
			"construction_valid": true,
			"blueprint_valid": true,
		},
		{
			"name": "player_library_review_id_mismatch",
			"fixture": "player_blueprint_approved",
			"construction_valid": true,
			"blueprint_valid": true,
		},
		{
			"name": "player_library_sequence_mismatch",
			"fixture": "player_blueprint_approved",
			"construction_valid": true,
			"blueprint_valid": true,
		},
		{
			"name": "player_library_day_mismatch",
			"fixture": "player_blueprint_approved",
			"construction_valid": true,
			"blueprint_valid": true,
		},
		{
			"name": "player_library_blueprint_mismatch",
			"fixture": "player_blueprint_approved",
			"construction_valid": true,
			"blueprint_valid": true,
		},
		{
			"name": "approved_review_missing_library_entry",
			"fixture": "player_blueprint_approved",
			"construction_valid": true,
			"blueprint_valid": true,
		},
		{
			"name": "active_move_job",
			"fixture": "active_build",
			"construction_valid": true,
		},
		{
			"name": "active_workers_above_capacity",
			"fixture": "two_active_builds",
			"construction_valid": true,
		},
		{
			"name": "active_job_tile_overlap",
			"fixture": "two_active_builds",
			"construction_valid": true,
		},
		{
			"name": "external_station_status_mismatch",
			"fixture": "external_station",
			"transport_valid": false,
			"transport_issue": "live_station_not_completed",
		},
		{
			"name": "external_station_type_mismatch",
			"fixture": "external_station",
			"transport_valid": true,
		},
		{
			"name": "external_station_mirror_mismatch",
			"fixture": "external_station",
			"transport_valid": true,
		},
		{
			"name": "external_station_missing_for_building",
			"fixture": "external_station",
			"transport_valid": true,
		},
		{
			"name": "under_construction_transport_project_without_job",
			"fixture": "active_transport",
			"construction_valid": true,
			"transport_valid": true,
		},
		{
			"name": "transport_job_project_operation_mismatch",
			"fixture": "active_transport",
			"construction_valid": true,
			"transport_valid": true,
		},
		{
			"name": "transport_job_project_tile_mismatch",
			"fixture": "active_transport",
			"construction_valid": true,
			"transport_valid": true,
		},
		{
			"name": "transport_job_project_id_mismatch",
			"fixture": "active_transport",
			"construction_valid": true,
			"transport_valid": true,
		},
		{
			"name": "transport_job_blueprint_mismatch",
			"fixture": "active_transport",
			"construction_valid": true,
			"transport_valid": true,
		},
		{
			"name": "transport_job_source_decision_mismatch",
			"fixture": "active_transport",
			"construction_valid": true,
			"transport_valid": true,
		},
	]
	var fixture_cache: Dictionary = {}
	for corruption_case: Dictionary in corruption_cases:
		var case_name := str(corruption_case["name"])
		var fixture_kind := str(corruption_case["fixture"])
		if not fixture_cache.has(fixture_kind):
			fixture_cache[fixture_kind] = _build_current_schema_corruption_fixture(
				fixture_kind,
				CURRENT_SCHEMA_NON_TRANSPORT_PATH
			)
		var fixture: Dictionary = fixture_cache[fixture_kind]
		if not _install_current_schema_corruption_fixture(CURRENT_SCHEMA_NON_TRANSPORT_PATH, fixture):
			_check(false, "%s installs a valid primary/backup fixture pair" % case_name)
			continue
		var primary_data: Variant = JSON.parse_string(_read_text(CURRENT_SCHEMA_NON_TRANSPORT_PATH))
		_check(primary_data is Dictionary, "%s fixture starts as valid JSON" % case_name)
		if not primary_data is Dictionary:
			continue
		var state_value: Variant = (primary_data as Dictionary).get("state", null)
		var runtime_value: Variant = (primary_data as Dictionary).get("kernel", null)
		if not state_value is Dictionary or not runtime_value is Dictionary:
			_check(false, "%s fixture contains state and runtime dictionaries" % case_name)
			continue
		var state_snapshot: Dictionary = state_value
		var runtime: Dictionary = runtime_value
		var metadata_value: Variant = state_snapshot.get("metadata", null)
		if not metadata_value is Dictionary:
			_check(false, "%s fixture contains metadata" % case_name)
			continue
		var vertical_value: Variant = (metadata_value as Dictionary).get("vertical_slice", null)
		if not vertical_value is Dictionary:
			_check(false, "%s fixture contains current vertical metadata" % case_name)
			continue
		var vertical: Dictionary = vertical_value
		_check(
			_apply_current_schema_cross_layer_corruption(
				case_name,
				vertical,
				state_snapshot,
				runtime
			),
			"%s corruption mutator found its canonical source record" % case_name
		)
		_assert_corrupted_component_diagnostics(corruption_case, vertical)
		_assert_current_schema_corruption_falls_back(
			case_name,
			primary_data,
			fixture,
			CURRENT_SCHEMA_NON_TRANSPORT_PATH
		)


func _assert_current_schema_corruption_falls_back(
	case_name: String,
	primary_data: Dictionary,
	fixture: Dictionary,
	path: String
) -> void:
	_check(
		_write_text(path, JSON.stringify(primary_data, "\t", false)),
		"%s primary corruption remains well-formed JSON" % case_name
	)
	var decoder = SaveServiceScript.new()
	var corrupted_envelope = decoder.load_primary_envelope(path)
	_check(corrupted_envelope != null, "%s corruption passes outer envelope decoding" % case_name)
	if corrupted_envelope == null:
		return
	var semantic_probe = GameSessionScript.new(21, 21)
	var probe_hash_before := semantic_probe.deterministic_hash()
	_check(not semantic_probe.restore_envelope(corrupted_envelope), "%s corruption is rejected before restore" % case_name)
	_check(semantic_probe.deterministic_hash() == probe_hash_before, "%s rejection does not partially apply state" % case_name)

	var restored = GameSessionScript.new(22, 22)
	_check(restored.load_now(path), "%s corruption falls back to the valid backup" % case_name)
	_check(restored.save_service.last_load_source == SaveServiceScript.LOAD_SOURCE_BACKUP, "%s recovery records backup source" % case_name)
	_check(restored.save_service.last_recovery_error == OK, "%s recovery safely rebuilds primary" % case_name)
	_check(restored.deterministic_hash() == str(fixture["hash"]), "%s recovery restores the exact backup state" % case_name)
	_check(_read_text(path) == _read_text(path + ".bak"), "%s recovery never leaves a partially accepted primary" % case_name)


func _assert_corrupted_component_diagnostics(corruption_case: Dictionary, vertical: Dictionary) -> void:
	var case_name := str(corruption_case["name"])
	if corruption_case.has("construction_valid"):
		var construction_snapshot: Dictionary = vertical.get("construction", {})
		var construction_result: Dictionary = ConstructionSystemScript.validate_snapshot(
			construction_snapshot
		)
		_check(
			bool(construction_result.get("valid", false)) == bool(corruption_case["construction_valid"]),
			"%s construction component diagnostic remains isolated: %s" % [case_name, construction_result]
		)
	if corruption_case.has("blueprint_valid"):
		var blueprint_result: Dictionary = BlueprintLibraryServiceScript.validate_snapshot(
			vertical.get("next_blueprint_sequence", null),
			vertical.get("blueprint_library", null),
			vertical.get("active_blueprint_by_building", null)
		)
		_check(
			bool(blueprint_result.get("valid", false)) == bool(corruption_case["blueprint_valid"]),
			"%s blueprint component diagnostic remains isolated: %s" % [case_name, blueprint_result]
		)
	if corruption_case.has("transport_valid"):
		var transport_snapshot: Dictionary = vertical.get("transport", {})
		var transport_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(
			transport_snapshot
		)
		_check(
			bool(transport_result.get("valid", false)) == bool(corruption_case["transport_valid"]),
			"%s transport component diagnostic has the expected validity: %s" % [case_name, transport_result]
		)
		var issue_fragment := str(corruption_case.get("transport_issue", ""))
		if not issue_fragment.is_empty():
			_check(
				_array_has_text_fragment(transport_result.get("issues", []), issue_fragment),
				"%s transport diagnostic names %s: %s" % [case_name, issue_fragment, transport_result]
			)


func _apply_non_transport_corruption(case_name: String, vertical: Dictionary, state_snapshot: Dictionary) -> void:
	var construction: Dictionary = vertical.get("construction", {})
	match case_name:
		"construction_not_dictionary":
			vertical["construction"] = []
		"reviews_not_dictionary":
			construction["reviews"] = []
		"jobs_not_dictionary":
			construction["jobs"] = []
		"review_record_not_dictionary":
			construction["reviews"] = {"review_bad": []}
		"job_record_not_dictionary":
			construction["jobs"] = {"job_bad": []}
		"blueprint_library_not_dictionary":
			vertical["blueprint_library"] = []
		"active_blueprints_not_dictionary":
			vertical["active_blueprint_by_building"] = []
		"active_blueprint_missing_library_id":
			vertical["active_blueprint_by_building"] = {"park": "approved_missing"}
		"construction_core_mismatch":
			var orphan_job := _active_construction_job("job_900001", "build", "tile_1")
			state_snapshot["construction_jobs"] = {"job_900001": orphan_job}
		"demolition_status_without_job":
			state_snapshot["buildings"] = {
				"building_900001": {"building_id": "building_900001", "status": "demolition"},
			}
		"demolition_job_without_status":
			var demolition_job := _active_construction_job("job_900002", "demolish", "building_900002")
			construction["jobs"] = {"job_900002": demolition_job}
			state_snapshot["construction_jobs"] = {"job_900002": demolition_job.duplicate(true)}
			state_snapshot["buildings"] = {
				"building_900002": {"building_id": "building_900002", "status": "active"},
			}
		"duplicate_demolition_jobs":
			var first_job := _active_construction_job("job_900003", "demolish", "building_900003")
			var second_job := _active_construction_job("job_900004", "demolish", "building_900003")
			construction["jobs"] = {"job_900003": first_job, "job_900004": second_job}
			state_snapshot["construction_jobs"] = {
				"job_900003": first_job.duplicate(true),
				"job_900004": second_job.duplicate(true),
			}
			state_snapshot["buildings"] = {
				"building_900003": {"building_id": "building_900003", "status": "demolition"},
			}


func _active_construction_job(job_id: String, operation: String, target_id: String) -> Dictionary:
	return {
		"id": job_id,
		"operation": operation,
		"target_id": target_id,
		"blueprint": {"building_id": "park"},
		"metadata": {},
		"worker_count": 5,
		"status": "active",
	}


func _apply_current_schema_cross_layer_corruption(
	case_name: String,
	vertical: Dictionary,
	state_snapshot: Dictionary,
	runtime: Dictionary
) -> bool:
	var construction_value: Variant = vertical.get("construction", null)
	var transport_value: Variant = vertical.get("transport", null)
	if not construction_value is Dictionary or not transport_value is Dictionary:
		return false
	var construction: Dictionary = construction_value
	var transport: Dictionary = transport_value
	var jobs: Dictionary = construction.get("jobs", {})
	match case_name:
		"runtime_processed_duplicate_id":
			var processed: Array = runtime.get("processed_operation_ids", [])
			if processed.is_empty():
				return false
			processed.append(processed[0])
			runtime["processed_operation_ids"] = processed
		"runtime_pending_duplicate_id":
			var pending: Array = runtime.get("pending_commands", [])
			if pending.is_empty() or not pending[0] is Dictionary:
				return false
			pending.append((pending[0] as Dictionary).duplicate(true))
			runtime["pending_commands"] = pending
		"runtime_pending_processed_overlap":
			var pending: Array = runtime.get("pending_commands", [])
			var processed: Array = runtime.get("processed_operation_ids", [])
			if pending.is_empty() or processed.is_empty() or not pending[0] is Dictionary:
				return false
			var pending_command: Dictionary = pending[0]
			pending_command["operation_id"] = str(processed[0])
			pending[0] = pending_command
			runtime["pending_commands"] = pending
		"stale_next_building_sequence":
			var buildings: Dictionary = state_snapshot.get("buildings", {})
			if buildings.is_empty():
				return false
			vertical["next_building_sequence"] = 1
		"core_building_not_dictionary":
			var buildings: Dictionary = state_snapshot.get("buildings", {})
			var building_ids := _sorted_string_dictionary_keys(buildings)
			if building_ids.is_empty():
				return false
			buildings[building_ids[0]] = "not_a_dictionary"
			state_snapshot["buildings"] = buildings
		"core_building_invalid_current_status":
			var buildings: Dictionary = state_snapshot.get("buildings", {})
			var building_ids := _sorted_string_dictionary_keys(buildings)
			if building_ids.is_empty() or not buildings[building_ids[0]] is Dictionary:
				return false
			var building: Dictionary = buildings[building_ids[0]]
			building["status"] = "forged_status"
			buildings[building_ids[0]] = building
			state_snapshot["buildings"] = buildings
		"stale_next_operation_sequence":
			vertical["next_operation_sequence"] = 1
		"stale_next_blueprint_sequence_pending_review", "stale_next_blueprint_sequence_rejected_review":
			var review_blueprint_id := _first_generated_review_blueprint_id(construction)
			if review_blueprint_id.is_empty():
				return false
			vertical["next_blueprint_sequence"] = 1
		"player_library_review_id_mismatch":
			var library_id := _first_player_library_id(vertical)
			if library_id.is_empty():
				return false
			var library: Dictionary = vertical["blueprint_library"]
			var entry: Dictionary = library[library_id]
			entry["review_id"] = "review_missing_from_construction"
			library[library_id] = entry
		"player_library_sequence_mismatch":
			var library_id := _first_player_library_id(vertical)
			if library_id.is_empty():
				return false
			var library: Dictionary = vertical["blueprint_library"]
			var entry: Dictionary = library[library_id]
			entry["approved_sequence"] = int(entry.get("approved_sequence", 0)) + 1
			library[library_id] = entry
		"player_library_day_mismatch":
			var library_id := _first_player_library_id(vertical)
			if library_id.is_empty():
				return false
			var library: Dictionary = vertical["blueprint_library"]
			var entry: Dictionary = library[library_id]
			entry["approved_day"] = int(entry.get("approved_day", 0)) + 1
			library[library_id] = entry
		"player_library_blueprint_mismatch":
			var library_id := _first_player_library_id(vertical)
			if library_id.is_empty():
				return false
			var library: Dictionary = vertical["blueprint_library"]
			var entry: Dictionary = library[library_id]
			var blueprint: Dictionary = entry.get("blueprint", {})
			blueprint["material_id"] = "steel" if str(blueprint.get("material_id", "")) != "steel" else "brick"
			entry["blueprint"] = blueprint
			library[library_id] = entry
		"approved_review_missing_library_entry":
			var library_id := _first_player_library_id(vertical)
			if library_id.is_empty():
				return false
			var library: Dictionary = vertical["blueprint_library"]
			var entry: Dictionary = library[library_id]
			var building_id := str(entry.get("building_id", ""))
			library.erase(library_id)
			var active: Dictionary = vertical["active_blueprint_by_building"]
			active[building_id] = "default_%s" % building_id
		"active_move_job":
			var job_id := _first_active_non_transport_job_id(construction)
			if job_id.is_empty():
				return false
			var job: Dictionary = jobs[job_id]
			var workload_rules: Dictionary = construction.get("workload_rules", {})
			_rewrite_job_operation(job, "move", workload_rules)
			jobs[job_id] = job
			_mirror_job_in_core(state_snapshot, job_id, job)
		"active_workers_above_capacity":
			var active_job_ids := _active_non_transport_job_ids(construction)
			if active_job_ids.size() < 2:
				return false
			var job_id := active_job_ids[1]
			var job: Dictionary = jobs[job_id]
			_rewrite_active_job_workers(job, 11)
			jobs[job_id] = job
			_mirror_job_in_core(state_snapshot, job_id, job)
		"active_job_tile_overlap":
			var active_job_ids := _active_non_transport_job_ids(construction)
			if active_job_ids.size() < 2:
				return false
			var first_job: Dictionary = jobs[active_job_ids[0]]
			var second_job: Dictionary = jobs[active_job_ids[1]]
			var first_metadata: Dictionary = first_job.get("metadata", {})
			var second_metadata: Dictionary = second_job.get("metadata", {})
			if not first_metadata.has("tile_index"):
				return false
			second_metadata["tile_index"] = int(first_metadata["tile_index"])
			second_job["metadata"] = second_metadata
			jobs[active_job_ids[1]] = second_job
			_mirror_job_in_core(state_snapshot, active_job_ids[1], second_job)
		"external_station_status_mismatch":
			var station_id := _first_external_station_id(transport)
			if station_id.is_empty():
				return false
			var stations: Dictionary = transport.get("stations", {})
			var station: Dictionary = stations[station_id]
			station["status"] = "planned"
			stations[station_id] = station
		"external_station_type_mismatch":
			var station_id := _first_external_station_id(transport)
			if station_id.is_empty():
				return false
			var stations: Dictionary = transport.get("stations", {})
			var station: Dictionary = stations[station_id]
			station["building_name"] = "捷運站"
			stations[station_id] = station
		"external_station_mirror_mismatch":
			var station_id := _first_external_station_id(transport)
			if station_id.is_empty():
				return false
			var stations: Dictionary = transport.get("stations", {})
			var station: Dictionary = stations[station_id]
			station["tile_id"] = (int(station.get("tile_id", 0)) + 1) % 100
			stations[station_id] = station
		"external_station_missing_for_building":
			var station_id := _first_external_station_id(transport)
			if station_id.is_empty():
				return false
			var stations: Dictionary = transport.get("stations", {})
			stations.erase(station_id)
		"under_construction_transport_project_without_job":
			var job_id := _first_active_transport_job_id(construction)
			if job_id.is_empty():
				return false
			jobs.erase(job_id)
			var core_jobs: Dictionary = state_snapshot.get("construction_jobs", {})
			core_jobs.erase(job_id)
		"transport_job_project_operation_mismatch":
			var job_id := _first_active_transport_job_id(construction)
			if job_id.is_empty():
				return false
			var job: Dictionary = jobs[job_id]
			job["operation"] = "demolish"
			jobs[job_id] = job
			_mirror_job_in_core(state_snapshot, job_id, job)
		"transport_job_project_tile_mismatch":
			var job_id := _first_active_transport_job_id(construction)
			if job_id.is_empty():
				return false
			var job: Dictionary = jobs[job_id]
			var metadata: Dictionary = job.get("metadata", {})
			var existing_tiles: Array = metadata.get("tile_indices", [])
			metadata["tile_indices"] = [_first_tile_not_in(existing_tiles)]
			job["metadata"] = metadata
			jobs[job_id] = job
			_mirror_job_in_core(state_snapshot, job_id, job)
		"transport_job_project_id_mismatch":
			var job_id := _first_active_transport_job_id(construction)
			if job_id.is_empty():
				return false
			var job: Dictionary = jobs[job_id]
			job["target_id"] = "transport_project_missing"
			jobs[job_id] = job
			_mirror_job_in_core(state_snapshot, job_id, job)
		"transport_job_blueprint_mismatch":
			var job_id := _first_active_transport_job_id(construction)
			if job_id.is_empty():
				return false
			var job: Dictionary = jobs[job_id]
			var blueprint: Dictionary = job.get("blueprint", {})
			blueprint["material_id"] = "brick"
			job["blueprint"] = blueprint
			jobs[job_id] = job
			_mirror_job_in_core(state_snapshot, job_id, job)
		"transport_job_source_decision_mismatch":
			var job_id := _first_active_transport_job_id(construction)
			if job_id.is_empty():
				return false
			var job: Dictionary = jobs[job_id]
			var metadata: Dictionary = job.get("metadata", {})
			metadata["source_decision_id"] = "forged_decision"
			job["metadata"] = metadata
			jobs[job_id] = job
			_mirror_job_in_core(state_snapshot, job_id, job)
		_:
			return false
	return true


func _build_current_schema_corruption_fixture(fixture_kind: String, path: String) -> Dictionary:
	_cleanup_path(path)
	var initial_funds := 0 if fixture_kind == "player_blueprint_rejected" else 1_000_000
	var coordinator = _canonical_current_coordinator(TEST_SEED, initial_funds, 5)
	match fixture_kind:
		"base":
			pass
		"pending_command":
			var pending_command = coordinator.session.queue_command(
				"ledger_post",
				{
					"amount": 1,
					"source_id": "pending_fixture",
					"reason_tag": "save_recovery.pending_fixture",
					"metadata": {"fixture": true},
				},
				"pending_fixture_unique"
			)
			_check(pending_command != null, "pending-command fixture queues through the public session API")
		"building":
			var tiles := _find_free_buildable_tiles(coordinator, 1)
			_check(tiles.size() == 1, "building fixture finds a buildable tile")
			if not tiles.is_empty():
				_check(
					not coordinator.register_existing_building(tiles[0], "公園").is_empty(),
					"building fixture registers through the coordinator API"
				)
		"player_blueprint_pending", "player_blueprint_rejected", "player_blueprint_approved":
			var submitted: Dictionary = coordinator.submit_blueprint({"building_name": "公園"})
			_check(bool(submitted.get("ok", false)), "%s fixture submits a player blueprint" % fixture_kind)
			if bool(submitted.get("ok", false)) and fixture_kind != "player_blueprint_pending":
				var review: Dictionary = submitted.get("review", {})
				coordinator.advance_days(int(review.get("review_days", 0)), {}, false)
				var review_id := str(review.get("id", ""))
				var expected_status := "rejected" if fixture_kind == "player_blueprint_rejected" else "approved"
				var resolved_review: Dictionary = coordinator.construction.reviews.get(review_id, {})
				_check(
					str(resolved_review.get("status", "")) == expected_status,
					"%s fixture reaches %s through coordinator day advancement" % [fixture_kind, expected_status]
				)
		"active_build", "two_active_builds":
			var requested_count := 2 if fixture_kind == "two_active_builds" else 1
			var tiles := _find_free_buildable_tiles(coordinator, requested_count)
			_check(tiles.size() == requested_count, "%s fixture finds distinct buildable tiles" % fixture_kind)
			for tile_id: int in tiles:
				var started: Dictionary = coordinator.start_approved_building("住宅", tile_id, 10)
				_check(bool(started.get("ok", false)), "%s fixture starts a canonical building job" % fixture_kind)
		"external_station":
			var tiles := _find_free_buildable_tiles(coordinator, 1)
			_check(tiles.size() == 1, "external-station fixture finds a buildable tile")
			if not tiles.is_empty():
				_check(
					not coordinator.register_existing_building(tiles[0], "公車站").is_empty(),
					"external-station fixture registers through the coordinator API"
				)
		"active_transport":
			var road_tiles := _find_free_cardinal_transport_path(coordinator)
			_check(road_tiles.size() >= 2, "active-transport fixture finds a cardinal buildable path")
			if road_tiles.size() >= 2:
				var started: Dictionary = coordinator.start_transport_project(
					"road", "build", road_tiles, 5, []
				)
				_check(bool(started.get("ok", false)), "active-transport fixture starts through the coordinator API")
		_:
			_check(false, "unknown current-schema corruption fixture kind: %s" % fixture_kind)
	coordinator.call("_stash_subsystems")
	_check(
		coordinator.session.save_now(path) == OK,
		"%s fixture current-schema primary save succeeds" % fixture_kind
	)
	_check(
		coordinator.session.save_now(path) == OK,
		"%s fixture current-schema backup save succeeds" % fixture_kind
	)
	var primary_text := _read_text(path)
	var backup_text := _read_text(path + ".bak")
	_check(not primary_text.is_empty(), "%s fixture produces a primary payload" % fixture_kind)
	_check(primary_text == backup_text, "%s fixture starts with identical trusted snapshots" % fixture_kind)
	return {
		"text": primary_text,
		"hash": coordinator.session.deterministic_hash(),
		"balance": coordinator.session.state.ledger.get_balance(),
	}


func _install_current_schema_corruption_fixture(path: String, fixture: Dictionary) -> bool:
	_cleanup_path(path)
	var text := str(fixture.get("text", ""))
	return not text.is_empty() and _write_text(path, text) and _write_text(path + ".bak", text)


func _find_free_buildable_tiles(coordinator, requested_count: int) -> Array[int]:
	var result: Array[int] = []
	for tile_id: int in range(coordinator.terrain_map.cell_count()):
		if not coordinator.terrain_map.is_buildable(tile_id):
			continue
		if not coordinator.get_building_by_tile(tile_id).is_empty():
			continue
		if not coordinator.active_construction_for_tile(tile_id).is_empty():
			continue
		result.append(tile_id)
		if result.size() >= requested_count:
			break
	return result


func _find_free_buildable_run(coordinator, length: int) -> Array[int]:
	for row: int in range(coordinator.terrain_map.grid_size().y):
		for column: int in range(coordinator.terrain_map.grid_size().x - length + 1):
			var result: Array[int] = []
			for offset: int in range(length):
				var tile_id := int(coordinator.terrain_map.tile_id_for_coordinate(Vector2i(column + offset, row)))
				if (
					not coordinator.terrain_map.is_buildable(tile_id)
					or not coordinator.get_building_by_tile(tile_id).is_empty()
					or not coordinator.active_construction_for_tile(tile_id).is_empty()
				):
					result.clear()
					break
				result.append(tile_id)
			if result.size() == length:
				return result
	return []


func _find_free_cardinal_transport_path(coordinator) -> Array[int]:
	for tile_id: int in range(coordinator.terrain_map.cell_count()):
		if not coordinator.terrain_map.is_buildable(tile_id):
			continue
		if not coordinator.get_building_by_tile(tile_id).is_empty():
			continue
		var coordinate: Vector2i = coordinator.terrain_map.coordinate_for_tile_id(tile_id)
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var neighbour_id: int = coordinator.terrain_map.tile_id_for_coordinate(coordinate + direction)
			if neighbour_id < 0 or not coordinator.terrain_map.is_buildable(neighbour_id):
				continue
			if not coordinator.get_building_by_tile(neighbour_id).is_empty():
				continue
			return [tile_id, neighbour_id]
	return []


func _first_generated_review_blueprint_id(construction: Dictionary) -> String:
	var reviews: Dictionary = construction.get("reviews", {})
	for review_id: String in _sorted_string_dictionary_keys(reviews):
		var review_value: Variant = reviews[review_id]
		if not review_value is Dictionary:
			continue
		var review: Dictionary = review_value
		var blueprint: Dictionary = review.get("blueprint", {})
		var blueprint_id := str(blueprint.get("id", ""))
		if blueprint_id.begins_with("blueprint_"):
			return blueprint_id
	return ""


func _first_player_library_id(vertical: Dictionary) -> String:
	var library_value: Variant = vertical.get("blueprint_library", null)
	if not library_value is Dictionary:
		return ""
	var library: Dictionary = library_value
	for library_id: String in _sorted_string_dictionary_keys(library):
		var entry_value: Variant = library[library_id]
		if entry_value is Dictionary and str((entry_value as Dictionary).get("source", "")) == "player":
			return library_id
	return ""


func _active_non_transport_job_ids(construction: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var jobs: Dictionary = construction.get("jobs", {})
	for job_id: String in _sorted_string_dictionary_keys(jobs):
		var job_value: Variant = jobs[job_id]
		if not job_value is Dictionary:
			continue
		var job: Dictionary = job_value
		var metadata: Dictionary = job.get("metadata", {})
		if (
			str(job.get("status", "")) == "active"
			and str(metadata.get("entity_kind", "")) != "transport_project"
		):
			result.append(job_id)
	return result


func _first_active_non_transport_job_id(construction: Dictionary) -> String:
	var job_ids := _active_non_transport_job_ids(construction)
	return job_ids[0] if not job_ids.is_empty() else ""


func _first_active_transport_job_id(construction: Dictionary) -> String:
	var jobs: Dictionary = construction.get("jobs", {})
	for job_id: String in _sorted_string_dictionary_keys(jobs):
		var job_value: Variant = jobs[job_id]
		if not job_value is Dictionary:
			continue
		var job: Dictionary = job_value
		var metadata: Dictionary = job.get("metadata", {})
		if (
			str(job.get("status", "")) == "active"
			and str(metadata.get("entity_kind", "")) == "transport_project"
		):
			return job_id
	return ""


func _first_external_station_id(transport: Dictionary) -> String:
	var stations: Dictionary = transport.get("stations", {})
	for station_id: String in _sorted_string_dictionary_keys(stations):
		var station_value: Variant = stations[station_id]
		if station_value is Dictionary and str((station_value as Dictionary).get("project_id", "")) == "external":
			return station_id
	return ""


func _rewrite_job_operation(job: Dictionary, operation: String, workload_rules: Dictionary) -> void:
	job["operation"] = operation
	var blueprint: Dictionary = job.get("blueprint", {})
	var workload: float = ConstructionSystemScript.calculate_workload_with_rules(
		blueprint,
		operation,
		workload_rules
	)
	var worker_count := int(job.get("worker_count", 1))
	var projected_days: int = ConstructionSystemScript.duration_days(workload, worker_count)
	job["workload"] = workload
	job["remaining_work"] = workload
	job["elapsed_days"] = 0
	job["projected_total_days"] = projected_days
	job["projected_remaining_days"] = projected_days
	job["projected_labor_cost"] = projected_days * ConstructionSystemScript.daily_labor_cost(worker_count)
	job["labor_cost_paid"] = 0


func _rewrite_active_job_workers(job: Dictionary, worker_count: int) -> void:
	var workload := float(job.get("workload", 0.0))
	var remaining_work := float(job.get("remaining_work", workload))
	var projected_total_days: int = ConstructionSystemScript.duration_days(workload, worker_count)
	job["worker_count"] = worker_count
	job["projected_total_days"] = projected_total_days
	job["projected_remaining_days"] = ConstructionSystemScript.duration_days(remaining_work, worker_count)
	job["projected_labor_cost"] = projected_total_days * ConstructionSystemScript.daily_labor_cost(worker_count)


func _mirror_job_in_core(state_snapshot: Dictionary, job_id: String, job: Dictionary) -> void:
	var core_jobs: Dictionary = state_snapshot.get("construction_jobs", {})
	var core_job := job.duplicate(true)
	core_job["job_id"] = job_id
	core_jobs[job_id] = core_job
	state_snapshot["construction_jobs"] = core_jobs


func _first_tile_not_in(tile_ids: Array) -> int:
	for tile_id: int in range(100):
		if not tile_ids.has(tile_id):
			return tile_id
	return 0


func _sorted_string_dictionary_keys(source: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in source.keys():
		result.append(str(key))
	result.sort()
	return result


func _array_has_text_fragment(values: Variant, fragment: String) -> bool:
	if not values is Array:
		return false
	for value: Variant in values:
		if str(value).contains(fragment):
			return true
	return false


func _test_schema_one_minimal_runtime_remains_compatible() -> void:
	var fixture := _seed_valid_pair(LEGACY_MINIMAL_RUNTIME_PATH)
	var legacy_data: Variant = JSON.parse_string(_read_text(LEGACY_MINIMAL_RUNTIME_PATH))
	_check(legacy_data is Dictionary, "legacy compatibility fixture starts as valid JSON")
	if not legacy_data is Dictionary:
		return
	(legacy_data as Dictionary).erase("kernel")
	_check(_write_text(LEGACY_MINIMAL_RUNTIME_PATH, JSON.stringify(legacy_data, "\t", false)), "schema-one fixture accepts a legacy minimal runtime section")
	var restored = GameSessionScript.new(12, 12)
	_check(restored.load_now(LEGACY_MINIMAL_RUNTIME_PATH), "schema-one save without nested kernel remains loadable")
	_check(restored.save_service.last_load_source == SaveServiceScript.LOAD_SOURCE_PRIMARY, "legacy minimal runtime loads from primary without fallback")
	_check(restored.state.game_time == 5, "legacy minimal runtime preserves game time")
	_check(restored.state.ledger.get_balance() == int(fixture["balance"]), "legacy minimal runtime preserves treasury")
	restored.advance_days_for_test(1)
	_check(restored.state.game_time == 6, "legacy minimal runtime can continue deterministic simulation")
	_check(restored.save_now(LEGACY_MINIMAL_RUNTIME_PATH) == OK, "legacy minimal runtime upgrades through the normal save boundary")


func _seed_valid_pair(path: String) -> Dictionary:
	_cleanup_path(path)
	var source = GameSessionScript.new(TEST_SEED, TEST_FUNDS)
	source.advance_days_for_test(5)
	source.submit_command("ledger_post", {
		"amount": 321,
		"source_id": "fixture",
		"reason_tag": "fixture.income",
		"metadata": {"fixture": true},
	}, "fixture_income")
	_check(source.save_now(path) == OK, "%s initial primary save succeeds" % path.get_file())
	_check(source.save_now(path) == OK, "%s second save creates a valid backup" % path.get_file())
	_check(FileAccess.file_exists(ProjectSettings.globalize_path(path) + ".bak"), "%s backup exists" % path.get_file())
	return {
		"hash": source.deterministic_hash(),
		"balance": source.state.ledger.get_balance(),
	}


func _seed_valid_current_schema_pair(path: String) -> Dictionary:
	_cleanup_path(path)
	var source = _canonical_current_session(TEST_SEED, TEST_FUNDS, 5)
	_check(source.save_now(path) == OK, "%s current-schema primary save succeeds" % path.get_file())
	_check(source.save_now(path) == OK, "%s current-schema backup save succeeds" % path.get_file())
	return {
		"hash": source.deterministic_hash(),
		"balance": source.state.ledger.get_balance(),
	}


func _canonical_current_session(seed: int, initial_funds: int, days: int = 0):
	var coordinator = _canonical_current_coordinator(seed, initial_funds, days)
	coordinator.call("_stash_subsystems")
	return coordinator.session


func _canonical_current_coordinator(seed: int, initial_funds: int, days: int = 0):
	var coordinator = VerticalSliceCoordinatorScript.new(seed, initial_funds)
	if days > 0:
		coordinator.advance_days(days, {}, false)
	return coordinator


func _assert_exact_candidate(path: String, backup: bool, expected_hash: String, expected_balance: int, label: String) -> void:
	var service = SaveServiceScript.new()
	var envelope = service.load_backup_envelope(path) if backup else service.load_primary_envelope(path)
	_check(envelope != null, "%s decodes without fallback" % label)
	if envelope == null:
		return
	_check(envelope.content_version == GameSessionScript.CONTENT_VERSION, "%s has the current content version" % label)
	_check(int(envelope.state.get("schema_version", -1)) == CityStateScript.SNAPSHOT_SCHEMA_VERSION, "%s has the current CityState schema" % label)
	var exact_session = GameSessionScript.new(9, 9)
	_check(exact_session.restore_envelope(envelope), "%s passes full restore validation" % label)
	if exact_session.state == null:
		return
	_check(exact_session.state.ledger.verify_balance(), "%s preserves the ledger invariant" % label)
	_check(exact_session.state.ledger.get_balance() == expected_balance, "%s preserves the expected balance" % label)
	_check(exact_session.deterministic_hash() == expected_hash, "%s preserves the expected deterministic hash" % label)


func _write_text(path: String, text: String) -> bool:
	var absolute_path := ProjectSettings.globalize_path(path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return false
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	var write_error := file.get_error()
	file.close()
	return write_error == OK


func _write_short_temporary(absolute_path: String, text: String) -> Error:
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text.left(maxi(1, int(text.length() / 2))))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	return write_error


func _report_temporary_write_failure(_absolute_path: String, _text: String) -> Error:
	return ERR_FILE_CANT_WRITE


func _read_text(path: String) -> String:
	var file := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _cleanup_all() -> void:
	_cleanup_path(DECODE_FAILURE_PATH)
	_cleanup_path(SEMANTIC_FAILURE_PATH)
	_cleanup_path(SHORT_WRITE_PATH)
	_cleanup_path(REPORTED_WRITE_FAILURE_PATH)
	_cleanup_path(INCONSISTENT_ENVELOPE_PATH)
	_cleanup_path(UNSUPPORTED_ENVELOPE_SCHEMA_PATH)
	_cleanup_path(UNSUPPORTED_STATE_SCHEMA_PATH)
	_cleanup_path(LEGACY_MINIMAL_RUNTIME_PATH)
	_cleanup_path(CURRENT_SCHEMA_NON_TRANSPORT_PATH)
	_cleanup_path(SCHEMA_PAIR_MIGRATION_PATH)
	_cleanup_path(RUNTIME_POPULATION_GATE_PATH)


func _cleanup_path(path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	for suffix: String in ["", ".tmp", ".bak", ".recovery.tmp"]:
		var candidate := absolute_path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Save recovery check failed: %s" % message)
