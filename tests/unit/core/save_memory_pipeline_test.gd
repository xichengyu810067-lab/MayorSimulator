extends SceneTree

const SaveEnvelopeScript = preload("res://scripts/core/save_envelope.gd")
const SaveServiceScript = preload("res://scripts/core/save_service.gd")

const TEST_PATH := "user://mayor_simulator/tests/save_memory_pipeline/large.json"
const PAYLOAD_BYTES := 8 * 1024 * 1024

var _failed := false
var _checks := 0


class TrackingEnvelope:
	extends RefCounted

	var schema_version := 1
	var content_version := "vertical_slice_1"
	var rng_seed := 17
	var rng_state := 19
	var game_time := 23
	var event_sequence := 0
	var command_sequence := 0
	var state: Dictionary = {}
	var kernel: Dictionary = {}
	var clock: Dictionary = {}
	var to_dict_calls := 0

	func to_dict() -> Dictionary:
		to_dict_calls += 1
		return {
			"schema_version": schema_version,
			"content_version": content_version,
			"rng_seed": str(rng_seed),
			"rng_state": str(rng_state),
			"game_time": game_time,
			"event_sequence": event_sequence,
			"command_sequence": command_sequence,
			"state": state.duplicate(true),
			"kernel": kernel.duplicate(true),
			"clock": clock.duplicate(true),
		}


func _initialize() -> void:
	_cleanup()
	_test_serialization_shape_matches_save_envelope()
	_test_large_atomic_save_avoids_envelope_deep_copy()
	_cleanup()
	if _failed:
		quit(1)
	else:
		print("Save memory pipeline test passed. Checks=%d PayloadBytes=%d" % [_checks, PAYLOAD_BYTES])
		quit(0)


func _test_serialization_shape_matches_save_envelope() -> void:
	var envelope = SaveEnvelopeScript.new()
	envelope.content_version = "vertical_slice_1"
	envelope.rng_seed = 17
	envelope.rng_state = 19
	envelope.game_time = 23
	envelope.state = {"marker": "schema-shape"}
	envelope.kernel = {"pending": []}
	envelope.clock = {"elapsed": 0.5}
	var service = SaveServiceScript.new()
	_check(
		service.encode(envelope) == JSON.stringify(envelope.to_dict(), "\t", false),
		"borrowed serialization view remains byte-compatible with SaveEnvelope.to_dict()"
	)


func _test_large_atomic_save_avoids_envelope_deep_copy() -> void:
	var envelope := TrackingEnvelope.new()
	envelope.state = {"large_payload": "x".repeat(PAYLOAD_BYTES)}
	var service = SaveServiceScript.new()
	var save_error: Error = service.save_atomic(TEST_PATH, envelope)
	_check(save_error == OK, "large atomic save completes successfully: %s" % service.last_error_message)
	_check(envelope.to_dict_calls == 0, "save pipeline does not deep-copy the envelope through to_dict()")
	var absolute_path := ProjectSettings.globalize_path(TEST_PATH)
	_check(FileAccess.file_exists(absolute_path), "large atomic save installs the primary file")
	var file := FileAccess.open(absolute_path, FileAccess.READ)
	_check(file != null, "large atomic save can be reopened")
	if file == null:
		return
	var saved_size := file.get_length()
	file.close()
	_check(saved_size >= PAYLOAD_BYTES, "persisted payload retains the complete large value")
	_check(service.load_primary_envelope(TEST_PATH) != null, "large saved payload passes schema decode verification")


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
	push_error("Save memory pipeline check failed: %s" % message)
