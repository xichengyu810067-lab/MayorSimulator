extends SceneTree

const GameSessionScript = preload("res://scripts/core/game_session.gd")
const SaveServiceScript = preload("res://scripts/core/save_service.gd")
const CityStateScript = preload("res://scripts/core/city_state.gd")

const TEST_ROOT := "user://mayor_simulator/tests/save_recovery"
const DECODE_FAILURE_PATH := TEST_ROOT + "/decode_failure.json"
const SEMANTIC_FAILURE_PATH := TEST_ROOT + "/semantic_failure.json"
const SHORT_WRITE_PATH := TEST_ROOT + "/short_write.json"
const REPORTED_WRITE_FAILURE_PATH := TEST_ROOT + "/reported_write_failure.json"
const INCONSISTENT_ENVELOPE_PATH := TEST_ROOT + "/inconsistent_envelope.json"
const UNSUPPORTED_ENVELOPE_SCHEMA_PATH := TEST_ROOT + "/unsupported_envelope_schema.json"
const UNSUPPORTED_STATE_SCHEMA_PATH := TEST_ROOT + "/unsupported_state_schema.json"
const LEGACY_MINIMAL_RUNTIME_PATH := TEST_ROOT + "/legacy_minimal_runtime.json"
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
	var source = GameSessionScript.new(13, 13)
	source.state.metadata["vertical_slice"] = {
		"schema_version": GameSessionScript.MAX_SUPPORTED_VERTICAL_SLICE_METADATA_SCHEMA,
		"population": {
			"schema_version": GameSessionScript.MAX_SUPPORTED_POPULATION_SCHEMA,
			"records": [],
			"requests": [],
			"next_transaction_sequence": 1,
			"income_transactions": [],
		},
		"terminal_failure_event_reason": "",
	}
	var current_probe = GameSessionScript.new(14, 14)
	_check(current_probe.restore_envelope(source.make_envelope()), "population schema two remains restorable")

	source.state.metadata["vertical_slice"]["population"] = {"schema_version": 1, "records": [], "requests": []}
	var legacy_population_probe = GameSessionScript.new(15, 15)
	_check(legacy_population_probe.restore_envelope(source.make_envelope()), "population schema one remains backward compatible")
	source.state.metadata["vertical_slice"]["population"] = {
		"schema_version": GameSessionScript.MAX_SUPPORTED_POPULATION_SCHEMA,
		"records": [],
		"requests": [],
		"next_transaction_sequence": 1,
		"income_transactions": [],
	}

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
