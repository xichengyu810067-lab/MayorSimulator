extends SceneTree

const SaveEnvelopeScript = preload("res://scripts/core/save_envelope.gd")
const SaveServiceScript = preload("res://scripts/core/save_service.gd")
const PopulationSystemScript = preload("res://scripts/systems/population/population_system.gd")

const TEST_PATH := "user://mayor_simulator/tests/save_input_limits/slot.json"

var _failed := false
var _checks := 0


func _initialize() -> void:
	_cleanup()
	_test_limit_contracts()
	_test_oversized_primary_recovers_only_from_valid_backup()
	_test_oversized_backup_cannot_replace_valid_primary()
	_test_oversized_temporary_preserves_valid_files()
	_test_deep_json_is_rejected_before_parse_or_copy()
	_test_collection_limits()
	_test_long_string_and_non_finite_number()
	_cleanup()
	if _failed:
		quit(1)
	else:
		print("Save input limits test passed. Checks=%d" % _checks)
		quit(0)


func _test_limit_contracts() -> void:
	_check(SaveEnvelopeScript.MAX_SAVE_FILE_BYTES == 512 * 1024 * 1024, "file limit preserves the measured 200k-capacity evidence line")
	_check(SaveEnvelopeScript.MAX_POPULATION_RECORDS == PopulationSystemScript.MAX_POPULATION, "input record limit follows the production population ceiling")
	_check(SaveEnvelopeScript.MAX_MONTHLY_REPORT_HISTORY == 24, "monthly history limit matches its writer")
	_check(SaveEnvelopeScript.MAX_MAJOR_EVENT_HISTORY == 200, "major event history limit matches its writer")
	_check(SaveEnvelopeScript.MAX_CHECKS_AND_BALANCES_HISTORY == 100, "checks-and-balances history limit matches its writer")


func _test_oversized_primary_recovers_only_from_valid_backup() -> void:
	var service = _write_valid_pair("backup-valid", "primary-valid")
	var absolute_path := ProjectSettings.globalize_path(TEST_PATH)
	var backup_path := absolute_path + ".bak"
	var backup_hash := FileAccess.get_sha256(backup_path)
	_check(_write_oversized_sparse_file(absolute_path), "oversized primary fixture is created")
	var recovered = service.load_envelope(TEST_PATH)
	_check(recovered != null, "valid backup remains loadable after oversized primary rejection: %s" % service.last_error_message)
	_check(service.last_load_source == SaveServiceScript.LOAD_SOURCE_BACKUP, "oversized primary cannot be selected as the load source")
	if recovered != null:
		_check(str(recovered.state.get("marker", "")) == "backup-valid", "recovery returns the previously validated backup payload")
	var recovery_error: Error = service.mark_backup_restored(TEST_PATH)
	_check(recovery_error == OK, "validated backup can rebuild the rejected primary: %s" % service.last_error_message)
	_check(FileAccess.get_sha256(backup_path) == backup_hash, "recovery never modifies the valid backup")
	_check(not FileAccess.file_exists(absolute_path + ".tmp"), "primary recovery leaves no save temporary")
	_check(not FileAccess.file_exists(absolute_path + ".recovery.tmp"), "primary recovery leaves no recovery temporary")
	_cleanup()


func _test_oversized_backup_cannot_replace_valid_primary() -> void:
	var service = _write_valid_pair("backup-valid", "primary-valid")
	var absolute_path := ProjectSettings.globalize_path(TEST_PATH)
	var backup_path := absolute_path + ".bak"
	var primary_hash := FileAccess.get_sha256(absolute_path)
	_check(_write_oversized_sparse_file(backup_path), "oversized backup fixture is created")
	var backup = service.load_backup_envelope(TEST_PATH)
	_check(backup == null, "oversized backup is rejected")
	_check(service.last_error_message.contains("Backup save is") and service.last_error_message.contains("limit"), "oversized backup failure is diagnostic")
	_check(FileAccess.get_sha256(absolute_path) == primary_hash, "oversized backup cannot overwrite the valid primary")
	_check(FileAccess.file_exists(backup_path), "oversized backup rejection is non-destructive")
	_check(not FileAccess.file_exists(absolute_path + ".tmp"), "backup rejection leaves no save temporary")
	_check(not FileAccess.file_exists(absolute_path + ".recovery.tmp"), "backup rejection leaves no recovery temporary")
	_cleanup()


func _test_oversized_temporary_preserves_valid_files() -> void:
	var service = _write_valid_pair("backup-valid", "primary-valid")
	var absolute_path := ProjectSettings.globalize_path(TEST_PATH)
	var backup_path := absolute_path + ".bak"
	var primary_hash := FileAccess.get_sha256(absolute_path)
	var backup_hash := FileAccess.get_sha256(backup_path)
	service.set_temporary_writer_for_testing(func(path: String, _encoded: String) -> Error:
		return OK if _write_oversized_sparse_file(path) else ERR_CANT_CREATE
	)
	var save_error: Error = service.save_atomic(TEST_PATH, _make_envelope("replacement"))
	service.set_temporary_writer_for_testing(Callable())
	_check(save_error == ERR_FILE_CORRUPT, "oversized temporary is rejected before hash or JSON verification")
	_check(service.last_error_message.contains("Temporary save is") and service.last_error_message.contains("limit"), "oversized temporary failure is diagnostic")
	_check(FileAccess.get_sha256(absolute_path) == primary_hash, "oversized temporary cannot overwrite the valid primary")
	_check(FileAccess.get_sha256(backup_path) == backup_hash, "oversized temporary cannot delete or replace the valid backup")
	_check(not FileAccess.file_exists(absolute_path + ".tmp"), "rejected oversized temporary is discarded")
	_check(not FileAccess.file_exists(absolute_path + ".recovery.tmp"), "temporary rejection leaves no recovery temporary")
	_cleanup()


func _test_deep_json_is_rejected_before_parse_or_copy() -> void:
	var nested_text := "0"
	for _index: int in range(SaveEnvelopeScript.MAX_JSON_NESTING_DEPTH):
		nested_text = "[%s]" % nested_text
	var json_text := (
		'{"schema_version":1,"content_version":"vertical_slice_1","rng_seed":"1","rng_state":"1",'
		+ '"game_time":0,"event_sequence":0,"command_sequence":0,"state":{"nested":'
		+ nested_text
		+ '},"kernel":{},"clock":{}}'
	)
	var service = SaveServiceScript.new()
	_check(service.decode(json_text) == null, "deep JSON is rejected")
	_check(service.last_error_message.contains("nesting exceeds"), "deep JSON is rejected by the pre-parse scanner")

	var nested_value: Variant = 0
	for _index: int in range(SaveEnvelopeScript.MAX_JSON_NESTING_DEPTH):
		nested_value = [nested_value]
	var data: Dictionary = _make_envelope("deep-copy-guard").to_dict()
	data["state"] = {"nested": nested_value}
	var report := SaveEnvelopeScript.from_untrusted_dict_report(data)
	_check(not bool(report.get("ok", false)), "deep in-memory payload is rejected before migration copy")
	_check(str(report.get("error", "")).contains("nesting exceeds"), "deep in-memory rejection is diagnostic")


func _test_collection_limits() -> void:
	_check_oversized_collection("requests", SaveEnvelopeScript.MAX_REQUESTS)
	_check_oversized_collection("income_transactions", SaveEnvelopeScript.MAX_TRANSACTIONS)
	_check_oversized_collection("events", SaveEnvelopeScript.MAX_EVENTS)
	_check_oversized_collection("records", SaveEnvelopeScript.MAX_POPULATION_RECORDS)
	_check_oversized_collection("monthly_report_history", SaveEnvelopeScript.MAX_MONTHLY_REPORT_HISTORY)
	_check_oversized_collection("major_event_history", SaveEnvelopeScript.MAX_MAJOR_EVENT_HISTORY)
	_check_oversized_collection("checks_and_balances_history", SaveEnvelopeScript.MAX_CHECKS_AND_BALANCES_HISTORY)


func _check_oversized_collection(collection_name: String, limit: int) -> void:
	var oversized: Array = []
	oversized.resize(limit + 1)
	var data: Dictionary = _make_envelope("collection-limit").to_dict()
	data["state"] = {collection_name: oversized}
	var report := SaveEnvelopeScript.from_untrusted_dict_report(data)
	_check(not bool(report.get("ok", false)), "%s above its collection limit is rejected" % collection_name)
	_check(str(report.get("error", "")).contains("'%s'" % collection_name), "%s rejection names the offending collection" % collection_name)


func _test_long_string_and_non_finite_number() -> void:
	var data: Dictionary = _make_envelope("string-limit").to_dict()
	data["state"] = {"text": "x".repeat(SaveEnvelopeScript.MAX_STRING_BYTES + 1)}
	var report := SaveEnvelopeScript.from_untrusted_dict_report(data)
	_check(not bool(report.get("ok", false)), "overlong string is rejected")
	_check(str(report.get("error", "")).contains("string exceeds"), "overlong string rejection is diagnostic")

	data = _make_envelope("numeric-limit").to_dict()
	data["state"] = {"not_finite": INF}
	report = SaveEnvelopeScript.from_untrusted_dict_report(data)
	_check(not bool(report.get("ok", false)), "non-finite numeric value is rejected")
	_check(str(report.get("error", "")).contains("non-finite"), "non-finite numeric rejection is diagnostic")


func _write_valid_pair(backup_marker: String, primary_marker: String):
	_cleanup()
	var service = SaveServiceScript.new()
	_check(service.save_atomic(TEST_PATH, _make_envelope(backup_marker)) == OK, "baseline save writes")
	_check(service.save_atomic(TEST_PATH, _make_envelope(primary_marker)) == OK, "second save creates primary and backup")
	return service


func _make_envelope(marker: String):
	var envelope = SaveEnvelopeScript.new()
	envelope.rng_seed = 17
	envelope.rng_state = 19
	envelope.game_time = 23
	envelope.state = {"marker": marker}
	envelope.kernel = {"pending_commands": []}
	envelope.clock = {"tick_rate": 1.0}
	return envelope


func _write_oversized_sparse_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.seek(SaveEnvelopeScript.MAX_SAVE_FILE_BYTES)
	file.store_8(0)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	return error == OK


func _cleanup() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_PATH)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	for suffix: String in ["", ".tmp", ".bak", ".recovery.tmp"]:
		var candidate := absolute_path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Save input limits check failed: %s" % message)
