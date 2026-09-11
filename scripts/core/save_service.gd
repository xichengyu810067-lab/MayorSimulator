extends RefCounted

const SaveEnvelopeScript = preload("res://scripts/core/save_envelope.gd")

const LOAD_SOURCE_NONE := ""
const LOAD_SOURCE_PRIMARY := "primary"
const LOAD_SOURCE_BACKUP := "backup"

# These stage names are exposed only for cross-process durability tests.  The
# hook is unset in every product flow, so production writes keep the exact same
# control path and never wait for external orchestration.
const TEST_STAGE_TEMP_PARTIAL_WRITE := "temp_partial_write"
const TEST_STAGE_TEMP_VERIFIED := "temp_verified"
const TEST_STAGE_BACKUP_REMOVED := "backup_removed"
const TEST_STAGE_PRIMARY_ROTATED := "primary_rotated"
const TEST_STAGE_PRIMARY_INSTALLED := "primary_installed"
const TEST_USE_SAVE_TEMP := "save_temp"
const TEST_USE_BACKUP_RECOVERY := "backup_recovery"
const TEST_USE_PRIMARY_ROTATION := "primary_rotation"

const _PRIVATE_TEMP_ATTEMPTS := 16
const _PRIVATE_TEMP_PAYLOAD := "payload.tmp"
const _READ_CHUNK_BYTES := 1024 * 1024

var last_error_message: String = ""
var last_load_source: String = LOAD_SOURCE_NONE
var last_recovery_error: Error = OK

var _protected_backup_paths: Dictionary = {}
var _validated_backup_snapshots: Dictionary = {}
var _owned_temporary_paths: Dictionary = {}
var _temporary_writer_for_testing: Callable = Callable()
var _atomic_stage_hook_for_testing: Callable = Callable()
var _verified_use_hook_for_testing: Callable = Callable()


func encode(envelope) -> String:
	# JSON.stringify() is synchronous and read-only, so the serializer can borrow
	# the envelope's already-detached snapshot dictionaries. Calling to_dict()
	# here used to deep-copy the complete city state a second time at the save
	# peak, including the canonical population records.
	return JSON.stringify(_envelope_serialization_view(envelope), "\t", false)


func _envelope_serialization_view(envelope) -> Dictionary:
	return {
		"schema_version": envelope.schema_version,
		"content_version": envelope.content_version,
		# Keep the persisted representation byte-compatible with SaveEnvelope.
		"rng_seed": str(envelope.rng_seed),
		"rng_state": str(envelope.rng_state),
		"game_time": envelope.game_time,
		"event_sequence": envelope.event_sequence,
		"command_sequence": envelope.command_sequence,
		"state": envelope.state,
		"kernel": envelope.kernel,
		"clock": envelope.clock,
	}


func decode(json_text: String):
	var encoded := json_text.to_utf8_buffer()
	if encoded.size() > SaveEnvelopeScript.MAX_SAVE_FILE_BYTES:
		last_error_message = "Save JSON text exceeds the %d-byte input limit." % SaveEnvelopeScript.MAX_SAVE_FILE_BYTES
		return null
	var preflight_error := _preflight_json_bytes(encoded)
	encoded.resize(0)
	if not preflight_error.is_empty():
		last_error_message = preflight_error
		return null
	return _decode_preflighted(json_text)


func _decode_preflighted(json_text: String):
	var json := JSON.new()
	var parse_error := json.parse(json_text)
	if parse_error != OK:
		last_error_message = "Save JSON parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		return null
	if not json.data is Dictionary:
		last_error_message = "Save root must be a dictionary."
		return null
	var report := SaveEnvelopeScript.from_untrusted_dict_report(json.data as Dictionary)
	if not bool(report.get("ok", false)):
		last_error_message = str(report.get("error", "Save schema is unsupported or invalid."))
		return null
	return report.get("envelope", null)


func save_atomic(path: String, envelope) -> Error:
	last_error_message = ""
	var absolute_path := ProjectSettings.globalize_path(path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		last_error_message = "Unable to create save directory."
		return directory_error
	var backup_path := absolute_path + ".bak"
	var reservation := _reserve_private_temporary(absolute_path, "save")
	if not bool(reservation.get("ok", false)):
		last_error_message = "Unable to reserve a private save temporary."
		var reservation_error: Error = int(reservation.get("error", ERR_CANT_CREATE))
		return reservation_error
	var temporary_path := str(reservation["path"])
	var encoded: String = encode(envelope)
	var expected_hash := encoded.sha256_text()
	var write_error: Error = _write_temporary_file(temporary_path, encoded, absolute_path, backup_path)
	if write_error != OK:
		if last_error_message.is_empty():
			last_error_message = "Unable to write temporary save file."
		_discard_owned_temporary(temporary_path)
		return write_error
	# The durable temporary file now owns the payload. Drop the original JSON
	# before read-back parsing so two full strings do not overlap in memory.
	encoded = ""
	var verified_snapshot := _read_validated_file_snapshot(temporary_path, "Temporary save", expected_hash)
	if not bool(verified_snapshot.get("ok", false)):
		_discard_owned_temporary(temporary_path)
		var verification_error: Error = int(verified_snapshot.get("error", ERR_FILE_CORRUPT))
		return verification_error
	verified_snapshot.erase("envelope")
	_remember_owned_fingerprint(temporary_path, verified_snapshot)
	_notify_atomic_stage_for_testing(TEST_STAGE_TEMP_VERIFIED, absolute_path, temporary_path, backup_path)
	_notify_verified_use_for_testing(TEST_USE_SAVE_TEMP, absolute_path, temporary_path, backup_path)
	if not _path_matches_snapshot(temporary_path, verified_snapshot):
		last_error_message = "Temporary save changed after validation; installation was refused."
		_abandon_owned_temporary(temporary_path)
		return ERR_FILE_CORRUPT
	# If a previous load recovered from this path's backup but could not rebuild
	# the primary immediately, the backup is the only trusted on-disk snapshot.
	# Install the new primary without rotating the known-bad primary over it.
	if _protected_backup_paths.has(absolute_path):
		var protected_replace_error := _replace_primary_preserving_backup(
			absolute_path,
			temporary_path,
			verified_snapshot,
			backup_path,
			_validated_backup_snapshots.get(backup_path, {})
		)
		if protected_replace_error == OK:
			_protected_backup_paths.erase(absolute_path)
		return protected_replace_error
	return _install_rotating_save(absolute_path, backup_path, temporary_path, verified_snapshot)


func set_temporary_writer_for_testing(writer: Callable) -> void:
	# Deterministic fault injection keeps disk-full/short-write behavior testable
	# without changing the production filesystem implementation.
	_temporary_writer_for_testing = writer


func set_atomic_stage_hook_for_testing(hook: Callable) -> void:
	# The OS-kill QA harness uses this explicit opt-in callback to pause a child
	# process at real filesystem transition points.  No environment variable or
	# command-line switch can enable it inside the product on its own.
	_atomic_stage_hook_for_testing = hook


func set_verified_use_hook_for_testing(hook: Callable) -> void:
	# Unit tests inject a race only after a candidate has been fully validated.
	# Product code has no environment or command-line route to this callback.
	_verified_use_hook_for_testing = hook


func _write_temporary_file(temporary_path: String, encoded: String, primary_path: String = "", backup_path: String = "") -> Error:
	if _temporary_writer_for_testing.is_valid():
		return int(_temporary_writer_for_testing.call(temporary_path, encoded))
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		last_error_message = "Unable to open temporary save file."
		return FileAccess.get_open_error()
	if _atomic_stage_hook_for_testing.is_valid() and not encoded.is_empty():
		# Splitting and flushing only while the testing hook is explicitly set lets
		# an external process terminate this writer with a genuine partial file on
		# disk.  The normal product path below remains a single store operation.
		var split_index := maxi(1, int(encoded.length() / 2))
		file.store_string(encoded.left(split_index))
		file.flush()
		var partial_error: Error = file.get_error()
		if partial_error != OK:
			file.close()
			last_error_message = "Unable to flush partial temporary save during testing."
			return partial_error
		_notify_atomic_stage_for_testing(TEST_STAGE_TEMP_PARTIAL_WRITE, primary_path, temporary_path, backup_path)
		file.store_string(encoded.substr(split_index))
	else:
		file.store_string(encoded)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		last_error_message = "Unable to flush temporary save file."
	return write_error


func _notify_atomic_stage_for_testing(stage: String, primary_path: String, temporary_path: String, backup_path: String) -> void:
	if not _atomic_stage_hook_for_testing.is_valid():
		return
	_atomic_stage_hook_for_testing.call(stage, {
		"primary_path": primary_path,
		"temporary_path": temporary_path,
		"backup_path": backup_path,
	})


func _notify_verified_use_for_testing(action: String, primary_path: String, temporary_path: String, backup_path: String) -> void:
	if not _verified_use_hook_for_testing.is_valid():
		return
	_verified_use_hook_for_testing.call(action, {
		"primary_path": primary_path,
		"temporary_path": temporary_path,
		"backup_path": backup_path,
	})


func _reserve_private_temporary(base_path: String, purpose: String) -> Dictionary:
	var crypto := Crypto.new()
	for _attempt: int in range(_PRIVATE_TEMP_ATTEMPTS):
		var token_bytes := crypto.generate_random_bytes(16)
		if token_bytes.size() != 16:
			return {"ok": false, "error": ERR_CANT_CREATE}
		var token := token_bytes.hex_encode()
		var directory_name := ".%s.%s.%s" % [base_path.get_file(), purpose, token]
		var directory_path := base_path.get_base_dir().path_join(directory_name)
		var directory_error := DirAccess.make_dir_absolute(directory_path)
		if directory_error == ERR_ALREADY_EXISTS:
			continue
		if directory_error != OK:
			return {"ok": false, "error": directory_error}
		var temporary_path := directory_path.path_join(_PRIVATE_TEMP_PAYLOAD)
		if FileAccess.file_exists(temporary_path):
			DirAccess.remove_absolute(directory_path)
			continue
		_owned_temporary_paths[temporary_path] = {
			"token": token,
			"directory": directory_path,
			"length": -1,
			"sha256": "",
		}
		return {"ok": true, "error": OK, "path": temporary_path}
	return {"ok": false, "error": ERR_ALREADY_EXISTS}


func _remember_owned_fingerprint(temporary_path: String, snapshot: Dictionary) -> void:
	if not _owned_temporary_paths.has(temporary_path):
		return
	var ownership: Dictionary = _owned_temporary_paths[temporary_path]
	ownership["length"] = int(snapshot.get("length", -1))
	ownership["sha256"] = str(snapshot.get("sha256", ""))


func _is_owned_temporary(temporary_path: String) -> bool:
	if not _owned_temporary_paths.has(temporary_path):
		return false
	var ownership: Dictionary = _owned_temporary_paths[temporary_path]
	var token := str(ownership.get("token", ""))
	var directory_path := str(ownership.get("directory", ""))
	return (
		not token.is_empty()
		and temporary_path.get_base_dir() == directory_path
		and directory_path.get_file().ends_with(token)
	)


func _discard_owned_temporary(temporary_path: String, expected_snapshot: Dictionary = {}) -> void:
	if not _is_owned_temporary(temporary_path):
		return
	var ownership: Dictionary = _owned_temporary_paths[temporary_path]
	var expected := expected_snapshot
	if expected.is_empty() and int(ownership.get("length", -1)) >= 0:
		expected = {
			"length": int(ownership["length"]),
			"sha256": str(ownership["sha256"]),
		}
	if FileAccess.file_exists(temporary_path):
		if not expected.is_empty() and not _path_matches_snapshot(temporary_path, expected):
			_abandon_owned_temporary(temporary_path)
			return
		DirAccess.remove_absolute(temporary_path)
	_release_owned_temporary(temporary_path)


func _consume_owned_temporary(temporary_path: String) -> void:
	_release_owned_temporary(temporary_path)


func _release_owned_temporary(temporary_path: String) -> void:
	if not _is_owned_temporary(temporary_path):
		return
	var directory_path := str((_owned_temporary_paths[temporary_path] as Dictionary).get("directory", ""))
	_owned_temporary_paths.erase(temporary_path)
	if not directory_path.is_empty() and DirAccess.dir_exists_absolute(directory_path):
		# Removal succeeds only when the private directory contains no unknown
		# files. Any foreign entry is therefore preserved fail-closed.
		DirAccess.remove_absolute(directory_path)


func _abandon_owned_temporary(temporary_path: String) -> void:
	_owned_temporary_paths.erase(temporary_path)


func _read_validated_file_snapshot(path: String, source_label: String, expected_hash: String = "") -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error_message = "Unable to open %s." % source_label.to_lower()
		return {"ok": false, "error": FileAccess.get_open_error()}
	var file_length := file.get_length()
	if file_length > SaveEnvelopeScript.MAX_SAVE_FILE_BYTES:
		file.close()
		last_error_message = "%s is %d bytes; limit is %d bytes." % [source_label, file_length, SaveEnvelopeScript.MAX_SAVE_FILE_BYTES]
		return {"ok": false, "error": ERR_FILE_CORRUPT, "length": file_length}
	var bytes := PackedByteArray()
	var scan_state := {"depth": 0, "in_string": false, "escaped": false, "string_bytes": 0}
	while file.get_position() < file_length:
		var remaining := file_length - file.get_position()
		var requested := mini(_READ_CHUNK_BYTES, remaining)
		var chunk := file.get_buffer(requested)
		if chunk.size() != requested or file.get_error() != OK:
			var read_error: Error = file.get_error()
			file.close()
			last_error_message = "Unable to read the complete %s snapshot." % source_label.to_lower()
			return {"ok": false, "error": read_error if read_error != OK else ERR_FILE_CORRUPT}
		bytes.append_array(chunk)
		var scan_error := _scan_json_bytes(chunk, scan_state)
		if not scan_error.is_empty():
			file.close()
			last_error_message = "%s %s" % [source_label, scan_error]
			return {"ok": false, "error": ERR_FILE_CORRUPT}
	file.close()
	if bool(scan_state["in_string"]) or int(scan_state["depth"]) != 0:
		last_error_message = "%s has unterminated JSON structure." % source_label
		return {"ok": false, "error": ERR_FILE_CORRUPT}
	var snapshot_hash := _sha256_bytes(bytes)
	if snapshot_hash.is_empty():
		last_error_message = "Unable to hash the %s snapshot." % source_label.to_lower()
		return {"ok": false, "error": ERR_CANT_CREATE}
	if not expected_hash.is_empty() and snapshot_hash != expected_hash:
		last_error_message = "%s failed byte-for-byte verification." % source_label
		return {"ok": false, "error": ERR_FILE_CORRUPT, "length": file_length, "sha256": snapshot_hash}
	var text := bytes.get_string_from_utf8()
	var envelope = _decode_preflighted(text)
	text = ""
	if envelope == null:
		var decode_error := last_error_message
		last_error_message = "%s failed decode verification: %s" % [source_label, decode_error]
		return {"ok": false, "error": ERR_FILE_CORRUPT, "length": file_length, "sha256": snapshot_hash}
	return {
		"ok": true,
		"error": OK,
		"bytes": bytes,
		"length": file_length,
		"sha256": snapshot_hash,
		"envelope": envelope,
	}


func _sha256_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()


func _fingerprint_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": true, "exists": false, "length": -1, "sha256": ""}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "exists": true, "error": FileAccess.get_open_error()}
	var length := file.get_length()
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		file.close()
		return {"ok": false, "exists": true, "error": ERR_CANT_CREATE}
	while file.get_position() < length:
		var remaining := length - file.get_position()
		var requested := mini(_READ_CHUNK_BYTES, remaining)
		var chunk := file.get_buffer(requested)
		if chunk.size() != requested or file.get_error() != OK or context.update(chunk) != OK:
			var read_error: Error = file.get_error()
			file.close()
			return {"ok": false, "exists": true, "error": read_error if read_error != OK else ERR_FILE_CORRUPT}
	file.close()
	return {
		"ok": true,
		"exists": true,
		"length": length,
		"sha256": context.finish().hex_encode(),
	}


func _path_matches_snapshot(path: String, snapshot: Dictionary) -> bool:
	var fingerprint := _fingerprint_path(path)
	return (
		bool(fingerprint.get("ok", false))
		and bool(fingerprint.get("exists", false))
		and int(fingerprint.get("length", -1)) == int(snapshot.get("length", -2))
		and str(fingerprint.get("sha256", "")) == str(snapshot.get("sha256", "__missing__"))
	)


func load_envelope(path: String):
	begin_load_attempt()
	var envelope = load_primary_envelope(path)
	if envelope != null:
		last_load_source = LOAD_SOURCE_PRIMARY
		return envelope
	# A backup is intentionally retained during replacement and can recover a
	# save interrupted between the two rename operations.
	envelope = load_backup_envelope(path)
	if envelope != null:
		last_load_source = LOAD_SOURCE_BACKUP
	return envelope


func begin_load_attempt() -> void:
	last_error_message = ""
	last_load_source = LOAD_SOURCE_NONE
	last_recovery_error = OK
	_validated_backup_snapshots.clear()


func load_primary_envelope(path: String):
	last_error_message = ""
	return _load_absolute(ProjectSettings.globalize_path(path), "Primary save", false)


func load_backup_envelope(path: String):
	last_error_message = ""
	return _load_absolute(ProjectSettings.globalize_path(path) + ".bak", "Backup save", true)


func mark_primary_restored(path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	last_load_source = LOAD_SOURCE_PRIMARY
	last_recovery_error = OK
	_protected_backup_paths.erase(absolute_path)


func mark_backup_restored(path: String) -> Error:
	var absolute_path := ProjectSettings.globalize_path(path)
	last_load_source = LOAD_SOURCE_BACKUP
	# Protect the known-good backup before attempting any filesystem mutation.
	# If rebuilding fails, save_atomic() will preserve it on the next save.
	_protected_backup_paths[absolute_path] = true
	last_recovery_error = _rebuild_primary_from_backup(absolute_path)
	if last_recovery_error == OK:
		_protected_backup_paths.erase(absolute_path)
	return last_recovery_error


func _load_absolute(absolute_path: String, source_label: String, remember_backup: bool):
	_validated_backup_snapshots.erase(absolute_path)
	if not FileAccess.file_exists(absolute_path):
		last_error_message = "Save file does not exist."
		return null
	var snapshot := _read_validated_file_snapshot(absolute_path, source_label)
	if not bool(snapshot.get("ok", false)):
		return null
	var envelope = snapshot.get("envelope", null)
	snapshot.erase("envelope")
	if envelope != null and remember_backup:
		# Recovery keeps the exact bytes that were scanned, hashed, parsed, and
		# semantically validated. It never re-reads backup content for adoption.
		_validated_backup_snapshots[absolute_path] = snapshot
	return envelope


func _rebuild_primary_from_backup(absolute_path: String) -> Error:
	var backup_path := absolute_path + ".bak"
	var trusted_snapshot: Dictionary = _validated_backup_snapshots.get(backup_path, {})
	if trusted_snapshot.is_empty():
		last_error_message = "Backup save was not validated for this recovery attempt."
		return ERR_FILE_CORRUPT
	_notify_verified_use_for_testing(TEST_USE_BACKUP_RECOVERY, absolute_path, "", backup_path)
	if not _path_matches_snapshot(backup_path, trusted_snapshot):
		var restored := _restore_trusted_path_after_drift(backup_path, trusted_snapshot)
		last_error_message = (
			"Backup save changed after validation; recovery was refused and the trusted backup was restored."
			if restored
			else "Backup save changed after validation; recovery was refused, and the trusted path could not be restored."
		)
		return ERR_FILE_CORRUPT
	var reservation := _reserve_private_temporary(absolute_path, "recovery")
	if not bool(reservation.get("ok", false)):
		last_error_message = "Unable to reserve a private recovery temporary."
		var reservation_error: Error = int(reservation.get("error", ERR_CANT_CREATE))
		return reservation_error
	var recovery_path := str(reservation["path"])
	var trusted_bytes: PackedByteArray = trusted_snapshot.get("bytes", PackedByteArray())
	# Godot exposes rename by path rather than by an already-open file handle.
	# Recovery therefore copies only the validated snapshot into a random,
	# atomically claimed private directory, revalidates that copy, checks both
	# public paths immediately before promotion, and verifies postconditions with
	# rollback. No later read of backup_path supplies bytes to the new primary.
	var write_error := _write_bytes_to_temporary(recovery_path, trusted_bytes)
	if write_error != OK:
		last_error_message = "Unable to write recovery temporary save file."
		_discard_owned_temporary(recovery_path)
		return write_error
	var recovery_snapshot := _read_validated_file_snapshot(
		recovery_path,
		"Recovery temporary save",
		str(trusted_snapshot.get("sha256", ""))
	)
	if not bool(recovery_snapshot.get("ok", false)):
		_discard_owned_temporary(recovery_path)
		var verification_error: Error = int(recovery_snapshot.get("error", ERR_FILE_CORRUPT))
		return verification_error
	recovery_snapshot.erase("envelope")
	_remember_owned_fingerprint(recovery_path, recovery_snapshot)
	var replace_error := _replace_primary_preserving_backup(
		absolute_path,
		recovery_path,
		recovery_snapshot,
		backup_path,
		trusted_snapshot
	)
	if replace_error == OK:
		_validated_backup_snapshots.erase(backup_path)
	return replace_error


func _write_bytes_to_temporary(temporary_path: String, bytes: PackedByteArray) -> Error:
	if not _is_owned_temporary(temporary_path) or FileAccess.file_exists(temporary_path):
		return ERR_ALREADY_EXISTS
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	return write_error


func _park_existing_path(path: String, base_path: String, purpose: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": true, "path": ""}
	var reservation := _reserve_private_temporary(base_path, purpose)
	if not bool(reservation.get("ok", false)):
		return reservation
	var parked_path := str(reservation["path"])
	var move_error := DirAccess.rename_absolute(path, parked_path)
	if move_error != OK:
		_release_owned_temporary(parked_path)
		return {"ok": false, "error": move_error}
	return {"ok": true, "error": OK, "path": parked_path}


func _quarantine_existing_path(path: String, base_path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": true, "path": ""}
	var parked := _park_existing_path(path, base_path, "untrusted")
	if bool(parked.get("ok", false)):
		# The content is deliberately no longer considered writer-owned. Keeping
		# it in the unpredictable directory preserves unknown data for diagnosis.
		_abandon_owned_temporary(str(parked.get("path", "")))
	return parked


func _restore_parked_path(parked_path: String, target_path: String, base_path: String) -> bool:
	if parked_path.is_empty():
		return not FileAccess.file_exists(target_path)
	if FileAccess.file_exists(target_path):
		var quarantine := _quarantine_existing_path(target_path, base_path)
		if not bool(quarantine.get("ok", false)):
			return false
	var restore_error := DirAccess.rename_absolute(parked_path, target_path)
	if restore_error != OK:
		return false
	_consume_owned_temporary(parked_path)
	return true


func _restore_trusted_path_after_drift(path: String, trusted_snapshot: Dictionary) -> bool:
	var quarantine := _park_existing_path(path, path, "untrusted")
	if not bool(quarantine.get("ok", false)):
		return false
	var quarantine_path := str(quarantine.get("path", ""))
	var reservation := _reserve_private_temporary(path, "restore")
	if not bool(reservation.get("ok", false)):
		_restore_parked_path(quarantine_path, path, path)
		return false
	var restore_path := str(reservation["path"])
	var trusted_bytes: PackedByteArray = trusted_snapshot.get("bytes", PackedByteArray())
	if _write_bytes_to_temporary(restore_path, trusted_bytes) != OK:
		_discard_owned_temporary(restore_path)
		_restore_parked_path(quarantine_path, path, path)
		return false
	var restore_snapshot := _read_validated_file_snapshot(
		restore_path,
		"Trusted restore temporary",
		str(trusted_snapshot.get("sha256", ""))
	)
	if not bool(restore_snapshot.get("ok", false)):
		_discard_owned_temporary(restore_path)
		_restore_parked_path(quarantine_path, path, path)
		return false
	_remember_owned_fingerprint(restore_path, restore_snapshot)
	if DirAccess.rename_absolute(restore_path, path) != OK:
		_discard_owned_temporary(restore_path, restore_snapshot)
		_restore_parked_path(quarantine_path, path, path)
		return false
	_consume_owned_temporary(restore_path)
	if not _path_matches_snapshot(path, trusted_snapshot):
		_quarantine_existing_path(path, path)
		_restore_parked_path(quarantine_path, path, path)
		return false
	if not quarantine_path.is_empty():
		_abandon_owned_temporary(quarantine_path)
	return true


func _capture_verified_primary_authority(absolute_path: String) -> Dictionary:
	if not FileAccess.file_exists(absolute_path):
		return {"ok": true, "exists": false}
	var source_snapshot := _read_validated_file_snapshot(absolute_path, "Previous primary save")
	if not bool(source_snapshot.get("ok", false)):
		return source_snapshot
	var reservation := _reserve_private_temporary(absolute_path, "primary-snapshot")
	if not bool(reservation.get("ok", false)):
		return {"ok": false, "error": int(reservation.get("error", ERR_CANT_CREATE))}
	var snapshot_path := str(reservation["path"])
	var write_error := _write_bytes_to_temporary(snapshot_path, source_snapshot.get("bytes", PackedByteArray()))
	if write_error != OK:
		_discard_owned_temporary(snapshot_path)
		return {"ok": false, "error": write_error}
	var snapshot := _read_validated_file_snapshot(
		snapshot_path,
		"Previous primary snapshot",
		str(source_snapshot.get("sha256", ""))
	)
	if not bool(snapshot.get("ok", false)):
		_discard_owned_temporary(snapshot_path)
		return snapshot
	snapshot.erase("envelope")
	_remember_owned_fingerprint(snapshot_path, snapshot)
	return {
		"ok": true,
		"exists": true,
		"path": snapshot_path,
		"length": int(snapshot.get("length", -1)),
		"sha256": str(snapshot.get("sha256", "")),
	}


func _release_primary_authority(authority: Dictionary) -> void:
	if not bool(authority.get("exists", false)):
		return
	var snapshot_path := str(authority.get("path", ""))
	if not snapshot_path.is_empty():
		_discard_owned_temporary(snapshot_path, authority)


func _primary_matches_authority(path: String, authority: Dictionary) -> bool:
	if not bool(authority.get("exists", false)):
		return not FileAccess.file_exists(path)
	return _path_matches_snapshot(path, authority)


func _restore_primary_authority_after_drift(path: String, authority: Dictionary) -> bool:
	if not bool(authority.get("exists", false)):
		var quarantine := _quarantine_existing_path(path, path)
		return bool(quarantine.get("ok", false))
	var snapshot_path := str(authority.get("path", ""))
	if snapshot_path.is_empty():
		return false
	var trusted_snapshot := _read_validated_file_snapshot(
		snapshot_path,
		"Previous primary snapshot",
		str(authority.get("sha256", ""))
	)
	if not bool(trusted_snapshot.get("ok", false)) or not _path_matches_snapshot(snapshot_path, authority):
		return false
	return _restore_trusted_path_after_drift(path, trusted_snapshot)


func _discard_verified_path_or_quarantine(path: String, expected_snapshot: Dictionary, base_path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	if _path_matches_snapshot(path, expected_snapshot):
		return DirAccess.remove_absolute(path) == OK
	var quarantine := _quarantine_existing_path(path, base_path)
	return bool(quarantine.get("ok", false))


func _install_rotating_save(absolute_path: String, backup_path: String, temporary_path: String, verified_snapshot: Dictionary) -> Error:
	if not _path_matches_snapshot(temporary_path, verified_snapshot):
		last_error_message = "Temporary save changed before rotation; installation was refused."
		_abandon_owned_temporary(temporary_path)
		return ERR_FILE_CORRUPT
	var primary_authority := _capture_verified_primary_authority(absolute_path)
	if not bool(primary_authority.get("ok", false)):
		last_error_message = "Previous primary save could not be fully verified before rotation."
		_discard_owned_temporary(temporary_path, verified_snapshot)
		return int(primary_authority.get("error", ERR_FILE_CORRUPT))
	_notify_verified_use_for_testing(TEST_USE_PRIMARY_ROTATION, absolute_path, temporary_path, backup_path)
	if not _primary_matches_authority(absolute_path, primary_authority):
		var restored_before_rotation := _restore_primary_authority_after_drift(absolute_path, primary_authority)
		_release_primary_authority(primary_authority)
		_discard_owned_temporary(temporary_path, verified_snapshot)
		last_error_message = (
			"Previous primary changed after verification; installation was refused and the verified primary was restored."
			if restored_before_rotation
			else "Previous primary changed after verification; installation was refused, and the verified primary could not be restored."
		)
		return ERR_FILE_CORRUPT
	var parked_backup := _park_existing_path(backup_path, absolute_path, "previous-backup")
	if not bool(parked_backup.get("ok", false)):
		last_error_message = "Unable to preserve the previous backup save."
		_release_primary_authority(primary_authority)
		_discard_owned_temporary(temporary_path, verified_snapshot)
		var park_error: Error = int(parked_backup.get("error", ERR_CANT_CREATE))
		return park_error
	var parked_backup_path := str(parked_backup.get("path", ""))
	if not parked_backup_path.is_empty():
		_notify_atomic_stage_for_testing(TEST_STAGE_BACKUP_REMOVED, absolute_path, temporary_path, backup_path)
	var had_previous := bool(primary_authority.get("exists", false))
	if had_previous:
		var backup_error := DirAccess.rename_absolute(absolute_path, backup_path)
		if backup_error != OK:
			last_error_message = "Unable to rotate previous save."
			_restore_parked_path(parked_backup_path, backup_path, absolute_path)
			_release_primary_authority(primary_authority)
			_discard_owned_temporary(temporary_path, verified_snapshot)
			return backup_error
		if not _path_matches_snapshot(backup_path, primary_authority):
			last_error_message = "Previous primary changed during rotation; installation was refused."
			_restore_rotating_save(absolute_path, backup_path, parked_backup_path, primary_authority)
			_release_primary_authority(primary_authority)
			_discard_owned_temporary(temporary_path, verified_snapshot)
			return ERR_FILE_CORRUPT
		_notify_atomic_stage_for_testing(TEST_STAGE_PRIMARY_ROTATED, absolute_path, temporary_path, backup_path)
	if not _path_matches_snapshot(temporary_path, verified_snapshot):
		last_error_message = "Temporary save changed during rotation; installation was refused."
		_restore_rotating_save(absolute_path, backup_path, parked_backup_path, primary_authority)
		_release_primary_authority(primary_authority)
		_abandon_owned_temporary(temporary_path)
		return ERR_FILE_CORRUPT
	# Godot has no rename-by-handle API. The random private path plus immediate
	# precondition and postcondition fingerprints bound that unavoidable window;
	# a failed postcondition restores both previous public generations.
	var replace_error := DirAccess.rename_absolute(temporary_path, absolute_path)
	if replace_error != OK:
		last_error_message = "Unable to install new save."
		_restore_rotating_save(absolute_path, backup_path, parked_backup_path, primary_authority)
		_release_primary_authority(primary_authority)
		_discard_owned_temporary(temporary_path, verified_snapshot)
		return replace_error
	_consume_owned_temporary(temporary_path)
	if not _path_matches_snapshot(absolute_path, verified_snapshot):
		last_error_message = "Installed primary failed the postcondition; the previous save was restored."
		_restore_rotating_save(absolute_path, backup_path, parked_backup_path, primary_authority)
		_release_primary_authority(primary_authority)
		return ERR_FILE_CORRUPT
	_notify_atomic_stage_for_testing(TEST_STAGE_PRIMARY_INSTALLED, absolute_path, temporary_path, backup_path)
	if not parked_backup_path.is_empty():
		_discard_owned_temporary(parked_backup_path)
	_release_primary_authority(primary_authority)
	# Keep the immediately previous valid snapshot. Frequent autosaves make a
	# one-generation fallback essential if the newest file is later corrupted.
	return OK


func _restore_rotating_save(absolute_path: String, backup_path: String, parked_backup_path: String, primary_authority: Dictionary) -> bool:
	var restored := _restore_primary_authority_after_drift(absolute_path, primary_authority)
	if FileAccess.file_exists(backup_path):
		if bool(primary_authority.get("exists", false)):
			restored = _discard_verified_path_or_quarantine(backup_path, primary_authority, absolute_path) and restored
		else:
			var quarantine := _quarantine_existing_path(backup_path, absolute_path)
			restored = bool(quarantine.get("ok", false)) and restored
	if not parked_backup_path.is_empty():
		restored = _restore_parked_path(parked_backup_path, backup_path, absolute_path) and restored
	return restored


func _preflight_json_bytes(bytes: PackedByteArray) -> String:
	var state := {"depth": 0, "in_string": false, "escaped": false, "string_bytes": 0}
	var error := _scan_json_bytes(bytes, state)
	if not error.is_empty():
		return "Save JSON text %s" % error
	if bool(state["in_string"]) or int(state["depth"]) != 0:
		return "Save JSON text has unterminated JSON structure."
	return ""


func _scan_json_bytes(bytes: PackedByteArray, state: Dictionary) -> String:
	for byte: int in bytes:
		if bool(state["in_string"]):
			if bool(state["escaped"]):
				state["escaped"] = false
				state["string_bytes"] = int(state["string_bytes"]) + 1
			elif byte == 92:
				state["escaped"] = true
				state["string_bytes"] = int(state["string_bytes"]) + 1
			elif byte == 34:
				state["in_string"] = false
				state["string_bytes"] = 0
			else:
				state["string_bytes"] = int(state["string_bytes"]) + 1
			if int(state["string_bytes"]) > SaveEnvelopeScript.MAX_STRING_BYTES:
				return "contains a string longer than %d bytes." % SaveEnvelopeScript.MAX_STRING_BYTES
			continue
		match byte:
			34:
				state["in_string"] = true
				state["escaped"] = false
				state["string_bytes"] = 0
			91, 123:
				state["depth"] = int(state["depth"]) + 1
				if int(state["depth"]) > SaveEnvelopeScript.MAX_JSON_NESTING_DEPTH:
					return "nesting exceeds %d levels." % SaveEnvelopeScript.MAX_JSON_NESTING_DEPTH
			93, 125:
				state["depth"] = int(state["depth"]) - 1
				if int(state["depth"]) < 0:
					return "contains unmatched closing JSON structure."
	return ""


func _replace_primary_preserving_backup(
	absolute_path: String,
	temporary_path: String,
	installed_snapshot: Dictionary,
	protected_path: String = "",
	protected_snapshot: Dictionary = {}
) -> Error:
	if not _path_matches_snapshot(temporary_path, installed_snapshot):
		last_error_message = "Private temporary changed before promotion; replacement was refused."
		_abandon_owned_temporary(temporary_path)
		return ERR_FILE_CORRUPT
	if not protected_snapshot.is_empty() and not _path_matches_snapshot(protected_path, protected_snapshot):
		var restored := _restore_trusted_path_after_drift(protected_path, protected_snapshot)
		last_error_message = (
			"Protected backup changed before promotion; replacement was refused and the trusted backup was restored."
			if restored
			else "Protected backup changed before promotion; replacement was refused, and the trusted path could not be restored."
		)
		_discard_owned_temporary(temporary_path, installed_snapshot)
		return ERR_FILE_CORRUPT
	var parked_primary := _park_existing_path(absolute_path, absolute_path, "previous-primary")
	if not bool(parked_primary.get("ok", false)):
		last_error_message = "Unable to preserve the previous primary save."
		_discard_owned_temporary(temporary_path, installed_snapshot)
		var park_error: Error = int(parked_primary.get("error", ERR_CANT_CREATE))
		return park_error
	var parked_primary_path := str(parked_primary.get("path", ""))
	if not _path_matches_snapshot(temporary_path, installed_snapshot):
		last_error_message = "Private temporary changed during promotion; replacement was refused."
		_restore_parked_path(parked_primary_path, absolute_path, absolute_path)
		_abandon_owned_temporary(temporary_path)
		return ERR_FILE_CORRUPT
	var replace_error := DirAccess.rename_absolute(temporary_path, absolute_path)
	if replace_error != OK:
		last_error_message = "Unable to install recovered primary save."
		_restore_parked_path(parked_primary_path, absolute_path, absolute_path)
		_discard_owned_temporary(temporary_path, installed_snapshot)
		return replace_error
	_consume_owned_temporary(temporary_path)
	var primary_matches := _path_matches_snapshot(absolute_path, installed_snapshot)
	var protected_matches := protected_snapshot.is_empty() or _path_matches_snapshot(protected_path, protected_snapshot)
	if not primary_matches or not protected_matches:
		var quarantine := _quarantine_existing_path(absolute_path, absolute_path)
		var restored_primary := bool(quarantine.get("ok", false)) and _restore_parked_path(
			parked_primary_path,
			absolute_path,
			absolute_path
		)
		if not protected_matches and not protected_snapshot.is_empty():
			_restore_trusted_path_after_drift(protected_path, protected_snapshot)
		last_error_message = (
			"Promotion postcondition failed; the previous primary was restored."
			if restored_primary
			else "Promotion postcondition failed and the previous primary could not be restored."
		)
		return ERR_FILE_CORRUPT
	if not parked_primary_path.is_empty():
		_discard_owned_temporary(parked_primary_path)
	return OK
