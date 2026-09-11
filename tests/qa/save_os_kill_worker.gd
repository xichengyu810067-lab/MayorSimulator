extends SceneTree

# This worker is intentionally not part of the assertion-matrix manifest.  It
# is launched as a child process by tools/run_save_os_kill_qa.ps1, which kills
# the process at a marker emitted from SaveService's explicit testing hook.

const GameSessionScript = preload("res://scripts/core/game_session.gd")
const SaveServiceScript = preload("res://scripts/core/save_service.gd")

const CONTROL_ROOT_ENV := "MAYOR_SAVE_KILL_QA_CONTROL_ROOT"
const SAVE_PATH := "user://mayor_simulator/tests/os_kill_recovery/autosave.json"
const TEST_SEED := 8_024_731
const TEST_INITIAL_FUNDS := 73_000
const FIRST_DELTA := 101
const SECOND_DELTA := 211
const CRASH_DELTA := 307
const FOLLOW_UP_DELTA := 401

const VALID_PHASES := [
	SaveServiceScript.TEST_STAGE_TEMP_PARTIAL_WRITE,
	SaveServiceScript.TEST_STAGE_TEMP_VERIFIED,
	SaveServiceScript.TEST_STAGE_BACKUP_REMOVED,
	SaveServiceScript.TEST_STAGE_PRIMARY_ROTATED,
	SaveServiceScript.TEST_STAGE_PRIMARY_INSTALLED,
]

var _control_root := ""
var _target_phase := ""
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_control_root = OS.get_environment(CONTROL_ROOT_ENV).strip_edges()
	_check(not _control_root.is_empty(), "%s must point to the case evidence directory" % CONTROL_ROOT_ENV)
	_check(_control_root.is_absolute_path(), "%s must be an absolute path" % CONTROL_ROOT_ENV)
	if not _failures.is_empty():
		_finish_without_result()
		return
	var mode := _user_argument("save-kill-qa-mode")
	var lifecycle_marker := {
		"schema_version": 1,
		"mode": mode,
		"process_id": OS.get_process_id(),
	}
	if not _publish_json_atomically(_control_path("worker-%s-marker.json" % mode), lifecycle_marker):
		_check(false, "worker lifecycle marker is published atomically for mode %s" % mode)
		_finish_without_result()
		return
	match mode:
		"seed":
			_run_seed()
		"crash":
			_target_phase = _user_argument("save-kill-qa-phase")
			_run_crash_writer()
		"verify":
			_target_phase = _user_argument("save-kill-qa-phase")
			_run_verifier()
		_:
			_check(false, "unknown save-kill QA mode: %s" % mode)
			_finish_without_result()


func _run_seed() -> void:
	_cleanup_save_artifacts()
	var session = GameSessionScript.new(TEST_SEED, TEST_INITIAL_FUNDS)
	_apply_ledger_delta(session, FIRST_DELTA, "os_kill_seed_a")
	var state_a := _session_snapshot(session)
	_check(session.save_now(SAVE_PATH) == OK, "first seed save succeeds")

	_apply_ledger_delta(session, SECOND_DELTA, "os_kill_seed_b")
	var state_b := _session_snapshot(session)
	_check(session.save_now(SAVE_PATH) == OK, "second seed save creates a primary/backup pair")
	var artifacts := _snapshot_artifacts()
	_expect_semantic(artifacts.get("primary", {}), true, true, str(state_b.get("deterministic_hash", "")), "seed primary is state B")
	_expect_semantic(artifacts.get("backup", {}), true, true, str(state_a.get("deterministic_hash", "")), "seed backup is state A")
	_check(not bool((artifacts.get("temporary", {}) as Dictionary).get("exists", false)), "seed leaves no standard temporary file")
	_check(not bool((artifacts.get("recovery_temporary", {}) as Dictionary).get("exists", false)), "seed leaves no recovery temporary file")

	var result := {
		"schema_version": 1,
		"mode": "seed",
		"success": _failures.is_empty(),
		"checks": _checks,
		"failures": _failures,
		"save_path": ProjectSettings.globalize_path(SAVE_PATH),
		"state_a": state_a,
		"state_b": state_b,
		"artifacts": artifacts,
	}
	if not _write_json(_control_path("seed-result.json"), result):
		_failures.append("seed result is durably written")
		push_error("Save OS-kill QA check failed: seed result is durably written")
	if _failures.is_empty():
		print("SAVE_OS_KILL_SEED_OK Checks=%d" % _checks)
		quit(0)
	else:
		_print_failures()
		quit(1)


func _run_crash_writer() -> void:
	_check(VALID_PHASES.has(_target_phase), "crash phase is supported: %s" % _target_phase)
	var seed_result := _read_json(_control_path("seed-result.json"))
	_check(not seed_result.is_empty(), "seed result is readable before the crash write")
	if not _failures.is_empty():
		_finish_without_result()
		return

	var session = GameSessionScript.new(TEST_SEED + 1, 1)
	_check(session.load_now(SAVE_PATH), "crash writer loads the seeded primary")
	_check(session.save_service.last_load_source == SaveServiceScript.LOAD_SOURCE_PRIMARY, "crash writer starts from the primary")
	var expected_b: Dictionary = seed_result.get("state_b", {})
	_check(session.deterministic_hash() == str(expected_b.get("deterministic_hash", "")), "crash writer starts from exact state B")
	_apply_ledger_delta(session, CRASH_DELTA, "os_kill_intended_c")
	var state_c := _session_snapshot(session)
	var encoded_c: String = session.save_service.encode(session.make_envelope())
	state_c["encoded_utf8_bytes"] = encoded_c.to_utf8_buffer().size()
	var intent := {
		"schema_version": 1,
		"mode": "crash",
		"phase": _target_phase,
		"success_before_interruption": _failures.is_empty(),
		"checks_before_interruption": _checks,
		"state_c": state_c,
	}
	_check(_write_json(_control_path("crash-intent.json"), intent), "crash intent is durably written before save_atomic")
	if not _failures.is_empty():
		_finish_without_result()
		return

	session.save_service.set_atomic_stage_hook_for_testing(Callable(self, "_on_atomic_stage"))
	var unexpected_error: Error = session.save_now(SAVE_PATH)
	_check(false, "save returned instead of being externally terminated at %s (error=%d)" % [_target_phase, unexpected_error])
	_finish_without_result()


func _on_atomic_stage(stage: String, paths: Dictionary) -> void:
	if stage != _target_phase:
		return
	var marker := {
		"schema_version": 1,
		"phase": stage,
		"process_id": OS.get_process_id(),
		"primary_path": str(paths.get("primary_path", "")),
		"temporary_path": str(paths.get("temporary_path", "")),
		"backup_path": str(paths.get("backup_path", "")),
		"ready_for_forced_termination": true,
	}
	if not _publish_json_atomically(_control_path("interrupt-marker.json"), marker):
		push_error("Unable to write the OS-kill synchronization marker.")
		quit(1)
		return
	print("SAVE_OS_KILL_STAGE_READY Phase=%s Pid=%d" % [stage, OS.get_process_id()])
	# The parent PowerShell process must be the only path out of this loop.  A
	# normal quit would turn this into simulated fault injection rather than an
	# operating-system process termination test.
	while true:
		OS.delay_msec(50)


func _run_verifier() -> void:
	_check(VALID_PHASES.has(_target_phase), "verification phase is supported: %s" % _target_phase)
	var seed_result := _read_json(_control_path("seed-result.json"))
	var crash_intent := _read_json(_control_path("crash-intent.json"))
	var interrupt_marker := _read_json(_control_path("interrupt-marker.json"))
	_check(not seed_result.is_empty(), "verifier reads seed expectations")
	_check(not crash_intent.is_empty(), "verifier reads the pre-interruption intent")
	_check(not interrupt_marker.is_empty(), "verifier reads the exact interrupted temporary path")
	_check(str(crash_intent.get("phase", "")) == _target_phase, "crash intent phase matches verifier phase")
	if not _failures.is_empty():
		_write_verification_result({}, {}, {}, {}, "", ERR_INVALID_DATA)
		quit(1)
		return

	var state_a: Dictionary = seed_result.get("state_a", {})
	var state_b: Dictionary = seed_result.get("state_b", {})
	var state_c: Dictionary = crash_intent.get("state_c", {})
	var interrupted_temporary_path := str(interrupt_marker.get("temporary_path", ""))
	var before_load := _snapshot_artifacts(interrupted_temporary_path)
	_validate_interrupted_topology(before_load, state_a, state_b, state_c)

	var restored = GameSessionScript.new(TEST_SEED + 2, 1)
	var loaded := restored.load_now(SAVE_PATH)
	_check(loaded, "a fresh process loads after interruption at %s" % _target_phase)
	var expected_loaded: Dictionary = state_c if _target_phase == SaveServiceScript.TEST_STAGE_PRIMARY_INSTALLED else state_b
	var expected_source := SaveServiceScript.LOAD_SOURCE_BACKUP if _target_phase == SaveServiceScript.TEST_STAGE_PRIMARY_ROTATED else SaveServiceScript.LOAD_SOURCE_PRIMARY
	_check(restored.save_service.last_load_source == expected_source, "load source matches the interrupted topology")
	_check(restored.save_service.last_recovery_error == OK, "backup-to-primary recovery reports OK")
	_check(restored.deterministic_hash() == str(expected_loaded.get("deterministic_hash", "")), "relaunch restores the exact expected semantic state")
	_check(restored.state.ledger.get_balance() == int(expected_loaded.get("balance", -1)), "relaunch restores the exact expected balance")
	var load_source: String = restored.save_service.last_load_source
	var recovery_error: Error = restored.save_service.last_recovery_error
	var after_load := _snapshot_artifacts()
	_expect_semantic(after_load.get("primary", {}), true, true, str(expected_loaded.get("deterministic_hash", "")), "post-load primary is semantically exact")
	if _target_phase == SaveServiceScript.TEST_STAGE_PRIMARY_ROTATED:
		_expect_semantic(after_load.get("backup", {}), true, true, str(state_b.get("deterministic_hash", "")), "backup remains trusted after rebuilding the missing primary")

	_apply_ledger_delta(restored, FOLLOW_UP_DELTA, "os_kill_follow_up_d")
	var state_d := _session_snapshot(restored)
	_check(restored.save_now(SAVE_PATH) == OK, "first normal save after recovery succeeds")
	var after_follow_up := _snapshot_artifacts()
	_expect_semantic(after_follow_up.get("primary", {}), true, true, str(state_d.get("deterministic_hash", "")), "follow-up primary is exact state D")
	_expect_semantic(after_follow_up.get("backup", {}), true, true, str(expected_loaded.get("deterministic_hash", "")), "follow-up backup preserves the recovered state")
	_check(not bool((after_follow_up.get("temporary", {}) as Dictionary).get("exists", false)), "follow-up save leaves no stale .tmp")
	_check(not bool((after_follow_up.get("recovery_temporary", {}) as Dictionary).get("exists", false)), "follow-up save leaves no stale .recovery.tmp")

	_write_verification_result(before_load, after_load, after_follow_up, state_d, load_source, recovery_error)
	if _failures.is_empty():
		print("SAVE_OS_KILL_VERIFY_OK Phase=%s Checks=%d" % [_target_phase, _checks])
		quit(0)
	else:
		_print_failures()
		quit(1)


func _validate_interrupted_topology(artifacts: Dictionary, state_a: Dictionary, state_b: Dictionary, state_c: Dictionary) -> void:
	var primary: Dictionary = artifacts.get("primary", {})
	var backup: Dictionary = artifacts.get("backup", {})
	var temporary: Dictionary = artifacts.get("temporary", {})
	var recovery_temporary: Dictionary = artifacts.get("recovery_temporary", {})
	_check(not bool(recovery_temporary.get("exists", false)), "interrupted normal save does not create .recovery.tmp")
	match _target_phase:
		SaveServiceScript.TEST_STAGE_TEMP_PARTIAL_WRITE:
			_expect_semantic(primary, true, true, str(state_b.get("deterministic_hash", "")), "partial-temp interruption keeps primary B")
			_expect_semantic(backup, true, true, str(state_a.get("deterministic_hash", "")), "partial-temp interruption keeps backup A")
			_check(bool(temporary.get("exists", false)), "partial temporary file exists after process termination")
			_check(int(temporary.get("size_bytes", 0)) > 0, "partial temporary file contains flushed bytes")
			_check(int(temporary.get("size_bytes", 0)) < int(state_c.get("encoded_utf8_bytes", 0)), "partial temporary file is smaller than intended state C")
			_check(not bool(temporary.get("semantic_valid", false)), "partial temporary file is not accepted as a semantic save")
		SaveServiceScript.TEST_STAGE_TEMP_VERIFIED:
			_expect_semantic(primary, true, true, str(state_b.get("deterministic_hash", "")), "verified-temp interruption keeps primary B")
			_expect_semantic(backup, true, true, str(state_a.get("deterministic_hash", "")), "verified-temp interruption keeps backup A")
			_expect_semantic(temporary, true, true, str(state_c.get("deterministic_hash", "")), "verified temporary file contains exact state C")
		SaveServiceScript.TEST_STAGE_BACKUP_REMOVED:
			_expect_semantic(primary, true, true, str(state_b.get("deterministic_hash", "")), "backup-removal interruption keeps primary B")
			_check(not bool(backup.get("exists", false)), "old backup is absent at the controlled transition")
			_expect_semantic(temporary, true, true, str(state_c.get("deterministic_hash", "")), "backup-removal interruption keeps verified state C temp")
		SaveServiceScript.TEST_STAGE_PRIMARY_ROTATED:
			_check(not bool(primary.get("exists", false)), "primary is absent between the two rename operations")
			_expect_semantic(backup, true, true, str(state_b.get("deterministic_hash", "")), "rotated backup contains exact state B")
			_expect_semantic(temporary, true, true, str(state_c.get("deterministic_hash", "")), "rotated transition keeps verified state C temp")
		SaveServiceScript.TEST_STAGE_PRIMARY_INSTALLED:
			_expect_semantic(primary, true, true, str(state_c.get("deterministic_hash", "")), "installed primary contains exact state C")
			_expect_semantic(backup, true, true, str(state_b.get("deterministic_hash", "")), "installed primary retains state B backup")
			_check(not bool(temporary.get("exists", false)), "installed primary consumes the temporary file")


func _write_verification_result(before_load: Dictionary, after_load: Dictionary, after_follow_up: Dictionary, state_d: Dictionary, load_source: String, recovery_error: Error) -> void:
	var result := {
		"schema_version": 1,
		"mode": "verify",
		"phase": _target_phase,
		"success": _failures.is_empty(),
		"checks": _checks,
		"failures": _failures,
		"load_source": load_source,
		"recovery_error": recovery_error,
		"before_load": before_load,
		"after_load": after_load,
		"state_d": state_d,
		"after_follow_up_save": after_follow_up,
	}
	if not _write_json(_control_path("verify-result.json"), result):
		_failures.append("verification result could not be written")


func _apply_ledger_delta(session, amount: int, operation_id: String) -> void:
	var before: int = session.state.ledger.get_balance()
	var events: Array = session.submit_command("ledger_post", {
		"amount": amount,
		"source_id": "save_os_kill_qa",
		"reason_tag": "qa.os_kill",
		"metadata": {"qa_only": true},
	}, operation_id)
	_check(not events.is_empty(), "ledger command %s emits an event" % operation_id)
	_check(session.state.ledger.get_balance() == before + amount, "ledger command %s changes balance exactly once" % operation_id)


func _session_snapshot(session) -> Dictionary:
	return {
		"deterministic_hash": session.deterministic_hash(),
		"balance": session.state.ledger.get_balance(),
		"game_time": session.state.game_time,
		"event_sequence": session.kernel.event_sequence,
		"command_sequence": session.kernel.command_sequence,
	}


func _snapshot_artifacts(temporary_path: String = "") -> Dictionary:
	var absolute_path := ProjectSettings.globalize_path(SAVE_PATH)
	return {
		"primary": _inspect_candidate(absolute_path),
		"backup": _inspect_candidate(absolute_path + ".bak"),
		"temporary": _inspect_candidate(temporary_path if not temporary_path.is_empty() else absolute_path + ".tmp"),
		"recovery_temporary": _inspect_candidate(absolute_path + ".recovery.tmp"),
	}


func _inspect_candidate(absolute_path: String) -> Dictionary:
	var result := {
		"path": absolute_path,
		"exists": FileAccess.file_exists(absolute_path),
		"size_bytes": 0,
		"sha256": "",
		"decode_valid": false,
		"semantic_valid": false,
		"deterministic_hash": "",
		"balance": 0,
	}
	if not bool(result["exists"]):
		return result
	var file := FileAccess.open(absolute_path, FileAccess.READ)
	if file == null:
		result["read_error"] = FileAccess.get_open_error()
		return result
	result["size_bytes"] = file.get_length()
	var text := file.get_as_text()
	var read_error: Error = file.get_error()
	file.close()
	result["read_error"] = read_error
	result["sha256"] = FileAccess.get_sha256(absolute_path)
	if read_error != OK:
		return result
	var decoder = SaveServiceScript.new()
	var envelope = decoder.decode(text)
	result["decode_valid"] = envelope != null
	if envelope == null:
		result["decode_error"] = decoder.last_error_message
		return result
	var probe = GameSessionScript.new(TEST_SEED + 3, 1)
	var semantic_valid: bool = probe.restore_envelope(envelope)
	result["semantic_valid"] = semantic_valid
	if semantic_valid:
		result["deterministic_hash"] = probe.deterministic_hash()
		result["balance"] = probe.state.ledger.get_balance()
	return result


func _expect_semantic(candidate: Dictionary, expected_exists: bool, expected_semantic: bool, expected_hash: String, message: String) -> void:
	_check(bool(candidate.get("exists", false)) == expected_exists, "%s existence" % message)
	if not expected_exists:
		return
	_check(bool(candidate.get("semantic_valid", false)) == expected_semantic, "%s semantic validity" % message)
	if expected_semantic:
		_check(str(candidate.get("deterministic_hash", "")) == expected_hash, "%s deterministic hash" % message)


func _cleanup_save_artifacts() -> void:
	var absolute_path := ProjectSettings.globalize_path(SAVE_PATH)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	for suffix: String in ["", ".bak", ".tmp", ".recovery.tmp"]:
		var candidate := absolute_path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _user_argument(name: String) -> String:
	var prefix := "--%s=" % name
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.substr(prefix.length())
	return ""


func _control_path(file_name: String) -> String:
	return _control_root.path_join(file_name)


func _write_json(absolute_path: String, value: Variant) -> bool:
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return false
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t", false))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	return write_error == OK


func _publish_json_atomically(absolute_path: String, value: Variant) -> bool:
	# The parent waits on the final name. Publishing through a same-directory
	# rename prevents it from observing a zero-length or partially written JSON
	# marker between FileAccess.open() and close().
	var partial_path := absolute_path + ".partial"
	if FileAccess.file_exists(absolute_path) or FileAccess.file_exists(partial_path):
		return false
	if not _write_json(partial_path, value):
		return false
	return DirAccess.rename_absolute(partial_path, absolute_path) == OK


func _read_json(absolute_path: String) -> Dictionary:
	var file := FileAccess.open(absolute_path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK:
		return {}
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures.append(message)
	push_error("Save OS-kill QA check failed: %s" % message)


func _finish_without_result() -> void:
	_print_failures()
	quit(1)


func _print_failures() -> void:
	for failure: String in _failures:
		print("SAVE_OS_KILL_FAILURE: %s" % failure)
