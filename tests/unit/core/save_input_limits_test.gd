extends SceneTree

const SaveEnvelopeScript = preload("res://scripts/core/save_envelope.gd")
const SaveServiceScript = preload("res://scripts/core/save_service.gd")
const PopulationSystemScript = preload("res://scripts/systems/population/population_system.gd")

const TEST_PATH := "user://mayor_simulator/tests/save_input_limits/slot.json"

var _failed := false
var _checks := 0
var _race_action := ""
var _race_replacement := ""
var _race_replaced_path := ""


func _initialize() -> void:
	_cleanup()
	_test_limit_contracts()
	_test_oversized_primary_recovers_only_from_valid_backup()
	_test_oversized_backup_cannot_replace_valid_primary()
	_test_oversized_temporary_preserves_valid_files()
	_test_verified_temporary_replacement_is_refused()
	_test_validated_backup_replacement_is_refused()
	_test_file_size_boundary()
	_test_json_scanner_boundaries()
	_test_depth_boundaries()
	_test_collection_limits()
	_test_string_boundaries_and_non_finite_number()
	_cleanup()
	if _failed:
		quit(1)
	else:
		print("Save input limits test passed. Checks=%d" % _checks)
		quit(0)


func _test_limit_contracts() -> void:
	_check(SaveEnvelopeScript.MAX_SAVE_FILE_BYTES == 512 * 1024 * 1024, "file limit preserves the measured 200k-capacity evidence line")
	_check(SaveEnvelopeScript.MAX_JSON_NESTING_DEPTH == 64, "JSON nesting limit remains 64")
	_check(SaveEnvelopeScript.MAX_STRING_BYTES == 16 * 1024 * 1024, "string limit remains 16 MiB")
	_check(SaveEnvelopeScript.MAX_TOTAL_CONTAINER_ITEMS == 12_000_000, "total container-item limit remains 12 million")
	_check(SaveEnvelopeScript.MAX_ITEMS_PER_CONTAINER == 2_000_000, "single-container limit remains 2 million")
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

func _test_verified_temporary_replacement_is_refused() -> void:
	var service = _write_valid_pair("backup-valid", "primary-valid")
	var absolute_path := ProjectSettings.globalize_path(TEST_PATH)
	var backup_path := absolute_path + ".bak"
	var primary_before := _read_bytes(absolute_path)
	var backup_before := _read_bytes(backup_path)
	var foreign_path := absolute_path + ".foreign"
	var unknown_legacy_temp := absolute_path + ".tmp"
	_check(_write_text(foreign_path, "foreign-owner-data"), "foreign sentinel is created")
	_check(_write_text(unknown_legacy_temp, "unknown-legacy-temp"), "unknown fixed temp sentinel is created")
	_race_action = SaveServiceScript.TEST_USE_SAVE_TEMP
	_race_replacement = service.encode(_make_envelope("tamperedxxx"))
	_race_replaced_path = ""
	service.set_verified_use_hook_for_testing(Callable(self, "_replace_verified_candidate"))
	var save_error: Error = service.save_atomic(TEST_PATH, _make_envelope("replacement"))
	service.set_verified_use_hook_for_testing(Callable())
	_check(save_error == ERR_FILE_CORRUPT, "replacing the validated unique save temp is refused")
	_check(service.last_error_message.contains("changed after validation"), "save-temp race reports the validation/use drift")
	_check(_race_replaced_path != absolute_path + ".tmp" and _race_replaced_path.get_base_dir() != absolute_path.get_base_dir(), "save temp uses a private unpredictable directory")
	_check(_read_bytes(absolute_path) == primary_before, "save-temp race preserves primary byte-for-byte")
	_check(_read_bytes(backup_path) == backup_before, "save-temp race preserves backup byte-for-byte")
	_check(not _race_replaced_path.is_empty() and _read_text(_race_replaced_path) == _race_replacement, "replacement temp is preserved as unknown data")
	_check(_read_text(foreign_path) == "foreign-owner-data", "save-temp race never deletes an unrelated file")
	_check(_read_text(unknown_legacy_temp) == "unknown-legacy-temp", "save-temp race never deletes an unowned fixed temp")
	_cleanup()


func _test_validated_backup_replacement_is_refused() -> void:
	var service = _write_valid_pair("backup-valid", "primary-valid")
	var absolute_path := ProjectSettings.globalize_path(TEST_PATH)
	var backup_path := absolute_path + ".bak"
	var primary_before := _read_bytes(absolute_path)
	var backup_before := _read_bytes(backup_path)
	var foreign_path := absolute_path + ".foreign"
	_check(_write_text(foreign_path, "foreign-owner-data"), "backup-race foreign sentinel is created")
	service.begin_load_attempt()
	var backup = service.load_backup_envelope(TEST_PATH)
	_check(backup != null, "backup race starts from a validated backup snapshot")
	_race_action = SaveServiceScript.TEST_USE_BACKUP_RECOVERY
	_race_replacement = service.encode(_make_envelope("backup-evil!"))
	_race_replaced_path = ""
	service.set_verified_use_hook_for_testing(Callable(self, "_replace_verified_candidate"))
	var recovery_error: Error = service.mark_backup_restored(TEST_PATH)
	service.set_verified_use_hook_for_testing(Callable())
	_check(recovery_error == ERR_FILE_CORRUPT, "replacing the validated backup before recovery is refused")
	_check(service.last_error_message.contains("changed after validation"), "backup race reports the validation/use drift")
	_check(_read_bytes(absolute_path) == primary_before, "backup race preserves the valid primary byte-for-byte")
	_check(_read_bytes(backup_path) == backup_before, "backup race restores the validated backup byte-for-byte")
	_check(_find_private_payload_with_text("untrusted", _race_replacement), "replaced backup is quarantined rather than deleted")
	_check(_read_text(foreign_path) == "foreign-owner-data", "backup race never deletes an unrelated file")
	_cleanup()


func _test_file_size_boundary() -> void:
	_cleanup()
	var absolute_path := ProjectSettings.globalize_path(TEST_PATH)
	_check(_write_sparse_file(absolute_path, SaveEnvelopeScript.MAX_SAVE_FILE_BYTES, 125), "exact 512 MiB sparse boundary fixture is created")
	var service = SaveServiceScript.new()
	_check(service.load_primary_envelope(TEST_PATH) == null, "malformed exact-limit file is rejected")
	_check(service.last_error_message.contains("unmatched closing"), "exact-limit file reaches the scanner instead of the over-limit gate")
	_check(not service.last_error_message.contains("limit is"), "exact 512 MiB is not misclassified as oversized")
	_cleanup()


func _test_json_scanner_boundaries() -> void:
	var service = SaveServiceScript.new()
	var state := {"depth": 0, "in_string": false, "escaped": false, "string_bytes": 0}
	var chunks: Array[PackedByteArray] = [
		PackedByteArray([34, 97, 92]),
		PackedByteArray([34, 92, 92, 228]),
		PackedByteArray([184, 173, 34]),
	]
	for chunk: PackedByteArray in chunks:
		_check(service._scan_json_bytes(chunk, state).is_empty(), "escaped quote/backslash and split UTF-8 chunk scans safely")
	_check(not bool(state["in_string"]) and not bool(state["escaped"]), "scanner carries escape and string state across chunk boundaries")
	_check(int(state["string_bytes"]) == 0, "closing quote resets the byte counter after split UTF-8")


func _test_depth_boundaries() -> void:
	var service = SaveServiceScript.new()
	var exact_text := "[".repeat(SaveEnvelopeScript.MAX_JSON_NESTING_DEPTH) + "]".repeat(SaveEnvelopeScript.MAX_JSON_NESTING_DEPTH)
	var exact_state := {"depth": 0, "in_string": false, "escaped": false, "string_bytes": 0}
	_check(service._scan_json_bytes(exact_text.to_utf8_buffer(), exact_state).is_empty(), "scanner accepts exact depth 64")
	_check(int(exact_state["depth"]) == 0, "exact depth 64 closes cleanly")
	var over_text := "[".repeat(SaveEnvelopeScript.MAX_JSON_NESTING_DEPTH + 1)
	var over_state := {"depth": 0, "in_string": false, "escaped": false, "string_bytes": 0}
	_check(service._scan_json_bytes(over_text.to_utf8_buffer(), over_state).contains("nesting exceeds"), "scanner rejects depth 65")
	var exact_tree: Variant = 0
	for _index: int in range(SaveEnvelopeScript.MAX_JSON_NESTING_DEPTH - 1):
		exact_tree = [exact_tree]
	var report := SaveEnvelopeScript.validate_untrusted_dict({"nested": exact_tree})
	_check(bool(report.get("ok", false)), "in-memory validator accepts exact depth 64")
	exact_tree = [exact_tree]
	report = SaveEnvelopeScript.validate_untrusted_dict({"nested": exact_tree})
	_check(not bool(report.get("ok", false)) and str(report.get("error", "")).contains("nesting exceeds"), "in-memory validator rejects depth 65")
	report = SaveEnvelopeScript.validate_untrusted_dict_with_lower_limits_for_testing(
		{"nested": exact_tree},
		{"max_json_nesting_depth": SaveEnvelopeScript.MAX_JSON_NESTING_DEPTH + 100}
	)
	_check(not bool(report.get("ok", false)) and str(report.get("error", "")).contains("64"), "test-only depth override cannot raise the product ceiling")


func _test_collection_limits() -> void:
	_check_lower_named_collection("requests", "max_requests")
	_check_lower_named_collection("income_transactions", "max_transactions")
	_check_lower_named_collection("events", "max_events")
	_check_lower_named_collection("records", "max_population_records")
	_check_lower_named_collection("monthly_report_history", "max_monthly_report_history")
	_check_lower_named_collection("major_event_history", "max_major_event_history")
	_check_lower_named_collection("checks_and_balances_history", "max_checks_and_balances_history")
	var two_items := {"items": [null, null]}
	var report := SaveEnvelopeScript.validate_untrusted_dict_with_lower_limits_for_testing(two_items, {"max_items_per_container": 2})
	_check(bool(report.get("ok", false)), "lower-only validator accepts the exact per-container boundary")
	report = SaveEnvelopeScript.validate_untrusted_dict_with_lower_limits_for_testing(two_items, {"max_items_per_container": 1})
	_check(not bool(report.get("ok", false)) and str(report.get("error", "")).contains("limit is 1"), "lower-only validator rejects one above the per-container boundary")
	report = SaveEnvelopeScript.validate_untrusted_dict_with_lower_limits_for_testing(two_items, {"max_total_container_items": 3})
	_check(bool(report.get("ok", false)), "lower-only validator accepts the exact total-item boundary")
	report = SaveEnvelopeScript.validate_untrusted_dict_with_lower_limits_for_testing(two_items, {"max_total_container_items": 2})
	_check(not bool(report.get("ok", false)) and str(report.get("error", "")).contains("more than 2"), "lower-only validator rejects one above the total-item boundary")
	var monthly_items: Array = []
	monthly_items.resize(SaveEnvelopeScript.MAX_MONTHLY_REPORT_HISTORY + 1)
	report = SaveEnvelopeScript.validate_untrusted_dict_with_lower_limits_for_testing(
		{"monthly_report_history": monthly_items},
		{"max_monthly_report_history": SaveEnvelopeScript.MAX_MONTHLY_REPORT_HISTORY + 100}
	)
	_check(not bool(report.get("ok", false)), "test-only collection override cannot raise the product ceiling")


func _check_lower_named_collection(collection_name: String, limit_key: String) -> void:
	var data := {collection_name: [null, null, null]}
	var lower_limits := {}
	lower_limits[limit_key] = 3
	var report := SaveEnvelopeScript.validate_untrusted_dict_with_lower_limits_for_testing(data, lower_limits)
	_check(bool(report.get("ok", false)), "%s accepts its exact lower-only boundary" % collection_name)
	var collection: Array = data[collection_name]
	collection.append(null)
	report = SaveEnvelopeScript.validate_untrusted_dict_with_lower_limits_for_testing(data, lower_limits)
	_check(not bool(report.get("ok", false)), "%s rejects one above its lower-only boundary" % collection_name)
	_check(str(report.get("error", "")).contains("'%s'" % collection_name), "%s rejection names the offending collection" % collection_name)


func _test_string_boundaries_and_non_finite_number() -> void:
	var exact_value := "x".repeat(SaveEnvelopeScript.MAX_STRING_BYTES)
	var report := SaveEnvelopeScript.validate_untrusted_dict({"text": exact_value})
	_check(bool(report.get("ok", false)), "exact 16 MiB ASCII string is accepted")
	var exact_utf8_value := "x".repeat(SaveEnvelopeScript.MAX_STRING_BYTES - 3) + "中"
	report = SaveEnvelopeScript.validate_untrusted_dict({"text": exact_utf8_value})
	_check(bool(report.get("ok", false)), "exact 16 MiB split-width UTF-8 string is accepted")
	var over_value := exact_value + "x"
	report = SaveEnvelopeScript.validate_untrusted_dict({"text": over_value})
	_check(not bool(report.get("ok", false)), "16 MiB plus one byte is rejected")
	_check(str(report.get("error", "")).contains("string exceeds"), "overlong string rejection is diagnostic")
	report = SaveEnvelopeScript.validate_untrusted_dict_with_lower_limits_for_testing(
		{"text": over_value},
		{"max_string_bytes": SaveEnvelopeScript.MAX_STRING_BYTES + 100}
	)
	_check(not bool(report.get("ok", false)), "test-only string override cannot raise the product ceiling")

	report = SaveEnvelopeScript.validate_untrusted_dict({"not_finite": INF})
	_check(not bool(report.get("ok", false)), "non-finite numeric value is rejected")
	_check(str(report.get("error", "")).contains("non-finite"), "non-finite numeric rejection is diagnostic")


func _replace_verified_candidate(action: String, paths: Dictionary) -> void:
	if action != _race_action:
		return
	_race_replaced_path = (
		str(paths.get("temporary_path", ""))
		if action == SaveServiceScript.TEST_USE_SAVE_TEMP
		else str(paths.get("backup_path", ""))
	)
	_write_text(_race_replaced_path, _race_replacement)


func _find_private_payload_with_text(purpose: String, expected_text: String) -> bool:
	var absolute_path := ProjectSettings.globalize_path(TEST_PATH)
	var base_directory := absolute_path.get_base_dir()
	var prefix := ".%s.bak.%s." % [absolute_path.get_file(), purpose]
	var directory := DirAccess.open(base_directory)
	if directory == null:
		return false
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if directory.current_is_dir() and entry.begins_with(prefix):
			var candidate := base_directory.path_join(entry).path_join("payload.tmp")
			if _read_text(candidate) == expected_text:
				directory.list_dir_end()
				return true
		entry = directory.get_next()
	directory.list_dir_end()
	return false


func _read_bytes(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	return write_error == OK


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
	return _write_sparse_file(path, SaveEnvelopeScript.MAX_SAVE_FILE_BYTES + 1, 0)


func _write_sparse_file(path: String, size_bytes: int, first_byte: int) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_8(first_byte)
	file.seek(size_bytes - 1)
	file.store_8(0)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	return error == OK


func _cleanup() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_PATH)
	var base_directory := absolute_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(base_directory)
	for suffix: String in ["", ".tmp", ".bak", ".recovery.tmp", ".foreign"]:
		var candidate := absolute_path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)
	var directory := DirAccess.open(base_directory)
	if directory != null:
		directory.list_dir_begin()
		var entry := directory.get_next()
		while not entry.is_empty():
			if directory.current_is_dir() and entry.begins_with(".%s." % absolute_path.get_file()):
				var private_directory := base_directory.path_join(entry)
				var payload := private_directory.path_join("payload.tmp")
				if FileAccess.file_exists(payload):
					DirAccess.remove_absolute(payload)
				DirAccess.remove_absolute(private_directory)
			entry = directory.get_next()
		directory.list_dir_end()
	_race_action = ""
	_race_replacement = ""
	_race_replaced_path = ""


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Save input limits check failed: %s" % message)
