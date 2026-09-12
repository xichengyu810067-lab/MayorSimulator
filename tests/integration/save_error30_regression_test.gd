extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const VerticalSliceCoordinatorScript := preload("res://scripts/app/vertical_slice_coordinator.gd")
const TEST_SAVE_PATH := "user://mayor_simulator/tests/save_error30_regression.json"

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_save()
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.city_grid[18] = "大型商場"
	main.building_customizations[18] = {"variant": 0, "roof": 0, "wall": 0}
	var building: Dictionary = main.vertical_slice.register_existing_building(
		18, "大型商場", main.building_customizations[18]
	)
	_check(not building.is_empty(), "employment fixture registers a job-providing building")
	main.vertical_slice.set_player_shell_state(main.call("_capture_player_shell_state"))
	_check(main.vertical_slice.save_game(TEST_SAVE_PATH) == OK, "fixture establishes a valid persisted population snapshot")
	var boundary_before: bool = bool(main.vertical_slice.session.call("_validate_runtime_population_save_boundary"))
	var matches: Array[Dictionary] = main.call("_match_available_jobs")
	var mismatch := _first_population_mismatch(main)
	_check(boundary_before, "fixture begins with an exact canonical/runtime population pair")
	_check(not matches.is_empty(), "monthly job matching mutates resident employment records")
	_check(mismatch.is_empty(), "canonical and runtime employment fields remain exact")
	main.vertical_slice.set_player_shell_state(main.call("_capture_player_shell_state"))
	_check(main.vertical_slice.save_game(TEST_SAVE_PATH) == OK, "post-matching save succeeds")
	var boundary_after: bool = bool(main.vertical_slice.session.call("_validate_runtime_population_save_boundary"))
	_check(boundary_after, "persisted job matching snapshot passes the exact save boundary")
	var restored = VerticalSliceCoordinatorScript.new()
	_check(restored.load_game(TEST_SAVE_PATH), "post-matching save reloads")
	_check(restored.session.call("_validate_runtime_population_save_boundary"), "reloaded employment state keeps the save boundary exact")
	for match_record: Dictionary in matches:
		var npc_id := str(match_record.get("npc_id", ""))
		var expected_job_id := str(match_record.get("job_id", ""))
		_check(not npc_id.is_empty() and not expected_job_id.is_empty(), "match exposes stable resident and job IDs")
		_check(str(restored.population.get_record(npc_id).job_id) == expected_job_id, "reloaded canonical NPC preserves matched employment")
		_check(str(restored.session.state.npcs[npc_id].get("job_id", "")) == expected_job_id, "reloaded runtime mirror preserves matched employment")
	_cleanup_save()
	if not _failed:
		print("Save error 30 employment-sync regression passed.")
	await TestCleanup.finish(self, [main], 1 if _failed else 0)


func _first_population_mismatch(main) -> Dictionary:
	for npc_id: String in main.vertical_slice.population.sorted_npc_ids():
		var canonical: Dictionary = main.vertical_slice.population.get_record(npc_id).to_dict()
		var runtime_value: Variant = main.vertical_slice.session.state.npcs.get(npc_id, null)
		if not runtime_value is Dictionary:
			return {"npc_id": npc_id, "field": "record_missing"}
		var runtime: Dictionary = runtime_value
		for field: String in ["job_id", "salary", "employment_state"]:
			if canonical.get(field) != runtime.get(field):
				return {
					"npc_id": npc_id,
					"field": field,
					"canonical": canonical.get(field),
					"runtime": runtime.get(field),
				}
	return {}


func _cleanup_save() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	for candidate: String in [absolute_path, absolute_path + ".tmp", absolute_path + ".bak"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _fail(message: String) -> void:
	_failed = true
	push_error("Save error 30 regression failed: %s" % message)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)
