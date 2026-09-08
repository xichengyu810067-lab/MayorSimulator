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

var last_error_message: String = ""
var last_load_source: String = LOAD_SOURCE_NONE
var last_recovery_error: Error = OK

var _protected_backup_paths: Dictionary = {}
var _temporary_writer_for_testing: Callable = Callable()
var _atomic_stage_hook_for_testing: Callable = Callable()


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
	var json := JSON.new()
	var parse_error := json.parse(json_text)
	if parse_error != OK:
		last_error_message = "Save JSON parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		return null
	if not json.data is Dictionary:
		last_error_message = "Save root must be a dictionary."
		return null
	var envelope = SaveEnvelopeScript.from_dict(json.data as Dictionary)
	if envelope == null:
		last_error_message = "Save schema is unsupported or invalid."
	return envelope


func save_atomic(path: String, envelope) -> Error:
	last_error_message = ""
	var absolute_path := ProjectSettings.globalize_path(path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		last_error_message = "Unable to create save directory."
		return directory_error
	var temporary_path := absolute_path + ".tmp"
	var backup_path := absolute_path + ".bak"
	var encoded: String = encode(envelope)
	var expected_hash := encoded.sha256_text()
	var write_error: Error = _write_temporary_file(temporary_path, encoded, absolute_path, backup_path)
	if write_error != OK:
		if last_error_message.is_empty():
			last_error_message = "Unable to write temporary save file."
		_discard_temporary(temporary_path)
		return write_error
	# The durable temporary file now owns the payload. Drop the original JSON
	# before read-back parsing so two full strings do not overlap in memory.
	encoded = ""
	var verification_error: Error = _verify_temporary_file(temporary_path, expected_hash)
	if verification_error != OK:
		_discard_temporary(temporary_path)
		return verification_error
	_notify_atomic_stage_for_testing(TEST_STAGE_TEMP_VERIFIED, absolute_path, temporary_path, backup_path)
	# If a previous load recovered from this path's backup but could not rebuild
	# the primary immediately, the backup is the only trusted on-disk snapshot.
	# Install the new primary without rotating the known-bad primary over it.
	if _protected_backup_paths.has(absolute_path):
		var protected_replace_error := _replace_primary_preserving_backup(absolute_path, temporary_path)
		if protected_replace_error == OK:
			_protected_backup_paths.erase(absolute_path)
		return protected_replace_error
	if FileAccess.file_exists(backup_path):
		var remove_backup_error := DirAccess.remove_absolute(backup_path)
		if remove_backup_error != OK:
			last_error_message = "Unable to remove the previous backup save."
			_discard_temporary(temporary_path)
			return remove_backup_error
		_notify_atomic_stage_for_testing(TEST_STAGE_BACKUP_REMOVED, absolute_path, temporary_path, backup_path)
	var had_previous := FileAccess.file_exists(absolute_path)
	if had_previous:
		var backup_error := DirAccess.rename_absolute(absolute_path, backup_path)
		if backup_error != OK:
			last_error_message = "Unable to rotate previous save."
			DirAccess.remove_absolute(temporary_path)
			return backup_error
		_notify_atomic_stage_for_testing(TEST_STAGE_PRIMARY_ROTATED, absolute_path, temporary_path, backup_path)
	var replace_error := DirAccess.rename_absolute(temporary_path, absolute_path)
	if replace_error != OK:
		last_error_message = "Unable to install new save."
		if had_previous and FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(backup_path, absolute_path)
		return replace_error
	_notify_atomic_stage_for_testing(TEST_STAGE_PRIMARY_INSTALLED, absolute_path, temporary_path, backup_path)
	# Keep the immediately previous valid snapshot. Frequent autosaves make a
	# one-generation fallback essential if the newest file is later corrupted.
	return OK


func set_temporary_writer_for_testing(writer: Callable) -> void:
	# Deterministic fault injection keeps disk-full/short-write behavior testable
	# without changing the production filesystem implementation.
	_temporary_writer_for_testing = writer


func set_atomic_stage_hook_for_testing(hook: Callable) -> void:
	# The OS-kill QA harness uses this explicit opt-in callback to pause a child
	# process at real filesystem transition points.  No environment variable or
	# command-line switch can enable it inside the product on its own.
	_atomic_stage_hook_for_testing = hook


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


func _verify_temporary_file(temporary_path: String, expected_hash: String) -> Error:
	# Compare the on-disk bytes before allocating the read-back JSON string.
	# FileAccess hashes the file incrementally, preserving the previous exact
	# write-verification boundary without holding the original payload alive.
	if FileAccess.get_sha256(temporary_path) != expected_hash:
		last_error_message = "Temporary save failed byte-for-byte verification."
		return ERR_FILE_CORRUPT
	var file := FileAccess.open(temporary_path, FileAccess.READ)
	if file == null:
		last_error_message = "Unable to reopen temporary save file for verification."
		return FileAccess.get_open_error()
	var verified_text := file.get_as_text()
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK:
		last_error_message = "Unable to read temporary save file during verification."
		return read_error
	var verified_envelope = decode(verified_text)
	verified_text = ""
	if verified_envelope == null:
		var decode_error := last_error_message
		last_error_message = "Temporary save failed decode verification: %s" % decode_error
		return ERR_FILE_CORRUPT
	verified_envelope = null
	return OK


func _discard_temporary(temporary_path: String) -> void:
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(temporary_path)


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


func load_primary_envelope(path: String):
	last_error_message = ""
	return _load_absolute(ProjectSettings.globalize_path(path))


func load_backup_envelope(path: String):
	last_error_message = ""
	return _load_absolute(ProjectSettings.globalize_path(path) + ".bak")


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


func _load_absolute(absolute_path: String):
	if not FileAccess.file_exists(absolute_path):
		last_error_message = "Save file does not exist."
		return null
	var file := FileAccess.open(absolute_path, FileAccess.READ)
	if file == null:
		last_error_message = "Unable to open save file."
		return null
	var text := file.get_as_text()
	file.close()
	return decode(text)


func _rebuild_primary_from_backup(absolute_path: String) -> Error:
	var backup_path := absolute_path + ".bak"
	if not FileAccess.file_exists(backup_path):
		last_error_message = "Unable to rebuild primary save because the backup is missing."
		return ERR_FILE_NOT_FOUND
	var backup_file := FileAccess.open(backup_path, FileAccess.READ)
	if backup_file == null:
		last_error_message = "Unable to open backup while rebuilding primary save."
		return FileAccess.get_open_error()
	var backup_bytes := backup_file.get_buffer(backup_file.get_length())
	backup_file.close()
	var recovery_path := absolute_path + ".recovery.tmp"
	var recovery_file := FileAccess.open(recovery_path, FileAccess.WRITE)
	if recovery_file == null:
		last_error_message = "Unable to open recovery temporary save file."
		return FileAccess.get_open_error()
	recovery_file.store_buffer(backup_bytes)
	recovery_file.flush()
	var write_error := recovery_file.get_error()
	recovery_file.close()
	if write_error != OK:
		last_error_message = "Unable to write recovery temporary save file."
		DirAccess.remove_absolute(recovery_path)
		return write_error
	return _replace_primary_preserving_backup(absolute_path, recovery_path)


func _replace_primary_preserving_backup(absolute_path: String, temporary_path: String) -> Error:
	if FileAccess.file_exists(absolute_path):
		var remove_error := DirAccess.remove_absolute(absolute_path)
		if remove_error != OK:
			last_error_message = "Unable to remove invalid primary save."
			DirAccess.remove_absolute(temporary_path)
			return remove_error
	var replace_error := DirAccess.rename_absolute(temporary_path, absolute_path)
	if replace_error != OK:
		last_error_message = "Unable to install recovered primary save."
		DirAccess.remove_absolute(temporary_path)
		return replace_error
	return OK
