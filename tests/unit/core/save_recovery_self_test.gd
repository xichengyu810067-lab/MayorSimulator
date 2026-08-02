extends SceneTree

const GameSessionScript = preload("res://scripts/core/game_session.gd")
const SaveServiceScript = preload("res://scripts/core/save_service.gd")
const CityStateScript = preload("res://scripts/core/city_state.gd")
const VerticalSliceCoordinatorScript = preload("res://scripts/app/vertical_slice_coordinator.gd")
const BlueprintLibraryServiceScript = preload("res://scripts/app/blueprint_library_service.gd")
const ConstructionSystemScript = preload("res://scripts/systems/city/construction_system.gd")
const TransportNetworkSystemScript = preload("res://scripts/systems/city/transport_network_system.gd")

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
