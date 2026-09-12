extends SceneTree

const VerticalSliceCoordinatorScript = preload("res://scripts/app/vertical_slice_coordinator.gd")
const NpcRecordScript = preload("res://scripts/systems/population/npc_record.gd")

const POPULATION_COUNT := 200_000
const SEED := 20_260_810
const INITIAL_FUNDS := 250_000
const COHORT_SIZE := 2_048
const FULL_BATCH_COUNT := 97
const TAIL_COUNT := 1_344
const TOTAL_COVERAGE_BATCHES := FULL_BATCH_COUNT + 1
const DEFAULT_PROXY_COUNT := 24
const MAX_PROXY_COUNT := 80

const CREATE_LIMIT_MS := 60_000.0
const COHORT_P95_LIMIT_MS := 50.0
const HASH_LIMIT_MS := 60_000.0
const SAVE_LIMIT_MS := 120_000.0
const LOAD_LIMIT_MS := 120_000.0
const SAVE_BYTE_LIMIT := 512 * 1024 * 1024

var _output_root := ""
var _progress_path := ""
var _result_path := ""
var _failures: Array[String] = []
var _phase_timings_ms: Dictionary = {}


func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--population-200k-parse-only"):
		print("POPULATION_200K_CAPACITY_BENCHMARK_PARSE_ONLY_PASSED")
		quit(0)
		return
	_output_root = _user_argument("population-200k-output-root")
	if _output_root.is_empty() or not DirAccess.dir_exists_absolute(_output_root):
		printerr("population-200k-output-root must name an existing fresh evidence directory")
		quit(1)
		return
	_progress_path = _output_root.path_join("progress.jsonl")
	_result_path = _output_root.path_join("benchmark-result.json")
	var save_path := "user://mayor_simulator/performance/population_200k_capacity.json"
	var save_absolute := ProjectSettings.globalize_path(save_path)
	var node_count_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var button_count_before := _count_buttons(root)

	_mark_phase("create", "start")
	var started_usec := Time.get_ticks_usec()
	var coordinator = VerticalSliceCoordinatorScript.new(SEED, INITIAL_FUNDS, POPULATION_COUNT)
	var create_ms := _elapsed_ms(started_usec)
	_phase_timings_ms["create"] = create_ms
	_mark_phase("create", "complete", {"wall_ms": create_ms})
	_check(coordinator != null and coordinator.population != null, "production coordinator created a canonical population")
	if coordinator == null or coordinator.population == null:
		_finish({"save_path": save_absolute})
		return
	_check_ceiling(create_ms, CREATE_LIMIT_MS, "create wall time", "the provisional 60-second line", "ms")
	_check(coordinator.population.population_count() == POPULATION_COUNT, "production constructor created all 200000 canonical MayorNpcRecord values")
	_check(coordinator.session.state.npcs.size() == POPULATION_COUNT, "B4-M atomic hydration rebuilt all 200000 runtime NPC records")
	_check(int(coordinator.session.state.metrics.get("population", -1)) == POPULATION_COUNT, "runtime population metric is exactly 200000")
	_check(coordinator.session.kernel.command_sequence == 3, "200000 production creation uses only three metric commands")
	_check(coordinator.session.kernel.event_sequence == 3, "200000 production creation emits only three metric events")
	_check(coordinator.next_operation_sequence == 4, "200000 atomic hydration consumes no operation IDs")

	_mark_phase("cohort", "start")
	started_usec = Time.get_ticks_usec()
	var cohort_durations_ms: Array[float] = []
	var covered_ids: Dictionary = {}
	var first_batch := PackedStringArray()
	for batch_index: int in range(TOTAL_COVERAGE_BATCHES):
		var batch_started_usec := Time.get_ticks_usec()
		var cohort: PackedStringArray = coordinator.population.get_bounded_deterministic_cohort(COHORT_SIZE, batch_index)
		cohort_durations_ms.append(_elapsed_ms(batch_started_usec))
		if batch_index == 0:
			first_batch = cohort.duplicate()
		var expected_size := COHORT_SIZE if batch_index < FULL_BATCH_COUNT else TAIL_COUNT
		_check(cohort.size() == expected_size, "cohort batch %d has the expected size" % batch_index)
		var batch_ids: Dictionary = {}
		for npc_id: String in cohort:
			_check(not batch_ids.has(npc_id), "cohort batch %d contains no duplicate IDs" % batch_index)
			batch_ids[npc_id] = true
			_check(not covered_ids.has(npc_id), "first cohort traversal covers each NPC exactly once")
			covered_ids[npc_id] = true
			var record = coordinator.population.get_record(npc_id)
			_check(record != null and NpcRecordScript.validate_dict(record.to_dict()), "cohort record is a complete valid MayorNpcRecord: %s" % npc_id)
	var wrapped_batch: PackedStringArray = coordinator.population.get_bounded_deterministic_cohort(COHORT_SIZE, TOTAL_COVERAGE_BATCHES)
	var cohort_p95_ms := _percentile_nearest_rank(cohort_durations_ms, 0.95)
	var cohort_total_ms := _elapsed_ms(started_usec)
	_phase_timings_ms["cohort_total"] = cohort_total_ms
	_phase_timings_ms["cohort_p95"] = cohort_p95_ms
	_mark_phase("cohort", "complete", {
		"wall_ms": cohort_total_ms,
		"p95_ms": cohort_p95_ms,
		"covered": covered_ids.size(),
	})
	_check(covered_ids.size() == POPULATION_COUNT, "97 full cohorts plus the 1344 tail cover all 200000 IDs")
	_check(wrapped_batch == first_batch, "cohort batch 98 wraps to the first full batch")
	_check(coordinator.population.get_bounded_deterministic_cohort(COHORT_SIZE, 0) == first_batch, "cohort selection is deterministic")
	_check_ceiling(cohort_p95_ms, COHORT_P95_LIMIT_MS, "cohort p95", "the provisional 50ms line", "ms")

	_mark_phase("proxy_bounds", "start")
	started_usec = Time.get_ticks_usec()
	var default_proxies: Array[Dictionary] = coordinator.visible_npc_proxies(DEFAULT_PROXY_COUNT)
	var maximum_proxies: Array[Dictionary] = coordinator.visible_npc_proxies(POPULATION_COUNT)
	var proxy_ms := _elapsed_ms(started_usec)
	_phase_timings_ms["proxy_bounds"] = proxy_ms
	_mark_phase("proxy_bounds", "complete", {"wall_ms": proxy_ms})
	_check(default_proxies.size() == DEFAULT_PROXY_COUNT, "default visible proxy materialization remains 24")
	_check(maximum_proxies.size() == MAX_PROXY_COUNT, "visible proxy materialization remains capped at 80")
	_check(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - node_count_before < 200, "200000 records do not create 200000 Nodes")
	_check(_count_buttons(root) - button_count_before < 100, "200000 records do not create 200000 Buttons")

	_mark_phase("population_hash", "start")
	started_usec = Time.get_ticks_usec()
	var population_json: String = coordinator.population.to_json()
	var population_hash_before := population_json.sha256_text()
	var population_bytes := population_json.to_utf8_buffer().size()
	var population_hash_ms := _elapsed_ms(started_usec)
	population_json = ""
	_phase_timings_ms["population_hash_before"] = population_hash_ms
	_mark_phase("population_hash", "complete", {
		"wall_ms": population_hash_ms,
		"bytes": population_bytes,
		"sha256": population_hash_before,
	})
	_check_ceiling(population_hash_ms, HASH_LIMIT_MS, "population hash", "the provisional 60-second line", "ms")

	_mark_phase("full_hash", "start")
	started_usec = Time.get_ticks_usec()
	var full_hash_before: String = coordinator.deterministic_hash()
	var full_hash_ms := _elapsed_ms(started_usec)
	_phase_timings_ms["full_hash_before"] = full_hash_ms
	_mark_phase("full_hash", "complete", {"wall_ms": full_hash_ms, "sha256": full_hash_before})
	_check_ceiling(full_hash_ms, HASH_LIMIT_MS, "full hash", "the provisional 60-second line", "ms")

	coordinator.set_save_path(save_path)
	_mark_phase("save_primary", "start")
	started_usec = Time.get_ticks_usec()
	var primary_save_error: Error = coordinator.save_game(save_path)
	var primary_save_ms := _elapsed_ms(started_usec)
	_phase_timings_ms["save_primary"] = primary_save_ms
	_mark_phase("save_primary", "complete", {"wall_ms": primary_save_ms, "error": int(primary_save_error)})
	_check(primary_save_error == OK, "first production save succeeds")
	_check_ceiling(primary_save_ms, SAVE_LIMIT_MS, "first save", "the provisional 120-second line", "ms")

	_mark_phase("save_backup", "start")
	started_usec = Time.get_ticks_usec()
	var backup_save_error: Error = coordinator.save_game(save_path)
	var backup_save_ms := _elapsed_ms(started_usec)
	_phase_timings_ms["save_backup"] = backup_save_ms
	_mark_phase("save_backup", "complete", {"wall_ms": backup_save_ms, "error": int(backup_save_error)})
	_check(backup_save_error == OK, "second production save creates the retained backup")
	_check_ceiling(backup_save_ms, SAVE_LIMIT_MS, "backup-producing save", "the provisional 120-second line", "ms")

	var primary_evidence := _file_evidence(save_absolute)
	var backup_evidence := _file_evidence(save_absolute + ".bak")
	_check(bool(primary_evidence.get("exists", false)), "primary 200000 save exists")
	_check(bool(backup_evidence.get("exists", false)), "backup 200000 save exists")
	_check_ceiling(float(primary_evidence.get("bytes", 0)), SAVE_BYTE_LIMIT, "primary save size", "the provisional 512MiB line", "bytes")
	_check_ceiling(float(backup_evidence.get("bytes", 0)), SAVE_BYTE_LIMIT, "backup save size", "the provisional 512MiB line", "bytes")
	_check(str(primary_evidence.get("sha256", "")) == str(backup_evidence.get("sha256", "")), "primary and backup hashes match the identical canonical state")
	_check(not FileAccess.file_exists(save_absolute + ".tmp"), "save leaves no temporary residue")
	_check(not FileAccess.file_exists(save_absolute + ".recovery.tmp"), "save leaves no recovery temporary residue")

	_mark_phase("load", "start")
	var restored = VerticalSliceCoordinatorScript.new(SEED + 1, INITIAL_FUNDS)
	started_usec = Time.get_ticks_usec()
	var loaded: bool = restored.load_game(save_path)
	var load_ms := _elapsed_ms(started_usec)
	_phase_timings_ms["load"] = load_ms
	_mark_phase("load", "complete", {"wall_ms": load_ms, "loaded": loaded})
	_check(loaded, "production load restores the 200000 save")
	_check_ceiling(load_ms, LOAD_LIMIT_MS, "load", "the provisional 120-second line", "ms")
	if loaded:
		_check(restored.population.population_count() == POPULATION_COUNT, "loaded canonical population contains all 200000 records")
		_check(restored.session.state.npcs.size() == POPULATION_COUNT, "loaded runtime hydration contains all 200000 records")
		_check(restored.session.kernel.command_sequence == coordinator.session.kernel.command_sequence, "load adds no per-resident commands")
		_check(restored.session.kernel.event_sequence == coordinator.session.kernel.event_sequence, "load adds no per-resident events")

	_mark_phase("parity_hashes", "start")
	started_usec = Time.get_ticks_usec()
	var population_hash_after: String = restored.population.stable_hash() if loaded else ""
	var population_hash_after_ms := _elapsed_ms(started_usec)
	started_usec = Time.get_ticks_usec()
	var full_hash_after: String = restored.deterministic_hash() if loaded else ""
	var full_hash_after_ms := _elapsed_ms(started_usec)
	_phase_timings_ms["population_hash_after"] = population_hash_after_ms
	_phase_timings_ms["full_hash_after"] = full_hash_after_ms
	_mark_phase("parity_hashes", "complete", {
		"population_wall_ms": population_hash_after_ms,
		"full_wall_ms": full_hash_after_ms,
		"population_sha256": population_hash_after,
		"full_sha256": full_hash_after,
	})
	_check_ceiling(population_hash_after_ms, HASH_LIMIT_MS, "loaded population hash", "the provisional 60-second line", "ms")
	_check_ceiling(full_hash_after_ms, HASH_LIMIT_MS, "loaded full hash", "the provisional 60-second line", "ms")
	_check(population_hash_after == population_hash_before, "population hash has save/load parity")
	_check(full_hash_after == full_hash_before, "full coordinator hash has save/load parity")

	var node_count_at_capacity := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var button_count_at_capacity := _count_buttons(root)
	coordinator = null
	restored = null
	var result := {
		"schema_version": 1,
		"status": "PASS" if _failures.is_empty() else "FAIL",
		"fixed_configuration": {
			"population": POPULATION_COUNT,
			"seed": SEED,
			"cohort_size": COHORT_SIZE,
			"full_batches": FULL_BATCH_COUNT,
			"tail": TAIL_COUNT,
			"default_visible_proxies": DEFAULT_PROXY_COUNT,
			"max_visible_proxies": MAX_PROXY_COUNT,
		},
		"provisional_limits": {
			"create_ms": CREATE_LIMIT_MS,
			"cohort_p95_ms": COHORT_P95_LIMIT_MS,
			"hash_ms": HASH_LIMIT_MS,
			"save_ms_each": SAVE_LIMIT_MS,
			"load_ms": LOAD_LIMIT_MS,
			"save_bytes": SAVE_BYTE_LIMIT,
			"release_sla": false,
		},
		"timings_ms": _phase_timings_ms.duplicate(true),
		"population": {
			"count": coordinator.population.population_count() if coordinator != null else POPULATION_COUNT,
			"json_bytes": population_bytes,
			"hash_before": population_hash_before,
			"hash_after": population_hash_after,
			"hash_parity": population_hash_before == population_hash_after,
		},
		"cohort": {
			"coverage_count": covered_ids.size(),
			"unique": covered_ids.size() == POPULATION_COUNT,
			"batch_count": TOTAL_COVERAGE_BATCHES,
			"p95_ms": cohort_p95_ms,
			"wrapped_after_tail": wrapped_batch == first_batch,
		},
		"proxies": {
			"default_count": default_proxies.size(),
			"maximum_count": maximum_proxies.size(),
		},
		"objects": {
			"node_count_before": node_count_before,
			"node_count_at_capacity": node_count_at_capacity,
			"button_count_before": button_count_before,
			"button_count_at_capacity": button_count_at_capacity,
		},
		"full_hash": {
			"before": full_hash_before,
			"after": full_hash_after,
			"parity": full_hash_before == full_hash_after,
		},
		"save": {
			"path": save_absolute,
			"primary": primary_evidence,
			"backup": backup_evidence,
			"temporary_residue": FileAccess.file_exists(save_absolute + ".tmp"),
			"recovery_temporary_residue": FileAccess.file_exists(save_absolute + ".recovery.tmp"),
		},
		"failures": _failures.duplicate(),
	}
	_finish(result)


func _finish(result: Dictionary) -> void:
	result["finished_at_utc"] = Time.get_datetime_string_from_system(true, true)
	result["status"] = "PASS" if _failures.is_empty() else "FAIL"
	result["failures"] = _failures.duplicate()
	var file := FileAccess.open(_result_path, FileAccess.WRITE)
	if file == null:
		printerr("Unable to write benchmark result: %s" % _result_path)
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t", false) + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	_mark_phase("complete", "pass" if _failures.is_empty() and write_error == OK else "fail", {
		"result_path": _result_path,
		"failure_count": _failures.size(),
		"write_error": int(write_error),
	})
	if _failures.is_empty() and write_error == OK:
		print("POPULATION_200K_CAPACITY_BENCHMARK_PASSED result=%s" % _result_path)
		quit(0)
	else:
		for failure: String in _failures:
			printerr("BENCHMARK_FAILURE: %s" % failure)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _check_ceiling(actual: float, ceiling: float, label: String, line_label: String, unit: String) -> void:
	if actual > ceiling:
		_failures.append(
			"%s exceeds %s: %.3f %s > %.3f %s" % [
				label,
				line_label,
				actual,
				unit,
				ceiling,
				unit,
			]
		)


func _mark_phase(phase: String, status: String, details: Dictionary = {}) -> void:
	var marker := {
		"utc": Time.get_datetime_string_from_system(true, true),
		"ticks_usec": Time.get_ticks_usec(),
		"phase": phase,
		"status": status,
		"details": details.duplicate(true),
	}
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(_progress_path) else FileAccess.WRITE
	var file := FileAccess.open(_progress_path, mode)
	if file == null:
		return
	if mode == FileAccess.READ_WRITE:
		file.seek_end()
	file.store_line(JSON.stringify(marker))
	file.flush()
	file.close()


func _elapsed_ms(started_usec: int) -> float:
	return float(Time.get_ticks_usec() - started_usec) / 1000.0


func _percentile_nearest_rank(values: Array[float], percentile: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted_values := values.duplicate()
	sorted_values.sort()
	var rank := clampi(ceili(percentile * float(sorted_values.size())) - 1, 0, sorted_values.size() - 1)
	return sorted_values[rank]


func _file_evidence(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"path": path, "exists": false, "bytes": 0, "sha256": ""}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"path": path, "exists": false, "bytes": 0, "sha256": ""}
	var bytes := file.get_length()
	file.close()
	return {
		"path": path,
		"exists": true,
		"bytes": bytes,
		"sha256": FileAccess.get_sha256(path),
	}


func _count_buttons(node: Node) -> int:
	var count := 1 if node is Button else 0
	for child: Node in node.get_children():
		count += _count_buttons(child)
	return count


func _user_argument(name: String) -> String:
	var prefix := "--%s=" % name
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""
