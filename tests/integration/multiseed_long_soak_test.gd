extends SceneTree

## Reproducible, multi-seed extension of vertical_slice_test.gd's established
## 3,600-day soak contract. Distribution data is reported for observation only;
## no demographic ratio is treated as a balance pass/fail threshold.

const COORDINATOR_PATH := "res://scripts/app/vertical_slice_coordinator.gd"
const SOAK_DAYS := 3_600
const RUNS_PER_SEED := 2
const INITIAL_FUNDS := 5_000_000
const SUMMARY_PATH := "user://qa/multiseed_long_soak_summary.json"
const SEEDS: Array[int] = [
	1,
	42,
	270_419,
	7_071_991,
	20_260_715,
	31_415_926,
	2_147_483_646,
]
const CITY_CONTEXT := {
	"economic_health": 80.0,
	"public_support": 90.0,
	"park_count": 0,
	"hospital_count": 0,
	"school_count": 0,
	"utility_fee": 120,
	"regional_support": {
		"north": 80,
		"south": 80,
		"east": 80,
		"west": 80,
	},
}

var _failed := false
var _checks := 0
var _failures: Array[String] = []
var _coordinator_script: Script
var _results: Array[Dictionary] = []
var _suite_started_usec := 0


func _initialize() -> void:
	_suite_started_usec = Time.get_ticks_usec()
	_coordinator_script = ResourceLoader.load(
		COORDINATOR_PATH,
		"Script",
		ResourceLoader.CACHE_MODE_IGNORE
	) as Script
	_check(
		_coordinator_script != null and _coordinator_script.can_instantiate(),
		"vertical slice coordinator compiles and can instantiate"
	)
	if _coordinator_script == null or not _coordinator_script.can_instantiate():
		_finish()
		return

	var profile_hashes := {}
	for seed: int in SEEDS:
		var primary := _run_seed(seed, "primary")
		var replay := _run_seed(seed, "replay")
		var deterministic := (
			str(primary.get("initial_state_hash", "")) == str(replay.get("initial_state_hash", ""))
			and str(primary.get("final_state_hash", "")) == str(replay.get("final_state_hash", ""))
			and str(primary.get("initial_population_hash", "")) == str(replay.get("initial_population_hash", ""))
			and str(primary.get("final_population_hash", "")) == str(replay.get("final_population_hash", ""))
			and str(primary.get("event_digest", "")) == str(replay.get("event_digest", ""))
		)
		_check(deterministic, "seed %d complete 3,600-day replay is deterministic" % seed)
		var profile_hash := str(primary.get("initial_profile_hash", ""))
		_check(not profile_hash.is_empty(), "seed %d exposes a non-empty population profile hash" % seed)
		_check(not profile_hashes.has(profile_hash), "seed %d produces a distinct resident profile" % seed)
		profile_hashes[profile_hash] = seed
		_results.append({
			"seed": seed,
			"deterministic_replay": deterministic,
			"primary": primary,
			"replay": replay,
		})

	_check(profile_hashes.size() == SEEDS.size(), "all configured seeds produce distinct resident profiles")
	_finish()


func _run_seed(seed: int, run_label: String) -> Dictionary:
	var coordinator = _coordinator_script.new(seed, INITIAL_FUNDS)
	var registered: Dictionary = coordinator.register_existing_building(0, "市政府")
	_check(not registered.is_empty(), "%s seed %d registers the established soak city hall" % [run_label, seed])

	var starting_ids: Array[String] = coordinator.population.sorted_npc_ids()
	var starting_ages := {}
	for npc_id: String in starting_ids:
		starting_ages[npc_id] = int(coordinator.population.get_record(npc_id).age)
	var initial_population_hash: String = coordinator.population.stable_hash()
	var initial_profile_hash := _population_profile_hash(coordinator)
	var initial_state_hash: String = coordinator.deterministic_hash()
	var initial_distribution := _population_distribution(coordinator)

	var run_started_usec := Time.get_ticks_usec()
	var elapsed_events: Array[Dictionary] = coordinator.advance_days(SOAK_DAYS, CITY_CONTEXT, false)
	var duration_ms := float(Time.get_ticks_usec() - run_started_usec) / 1000.0

	_check(coordinator.game_day() == SOAK_DAYS, "%s seed %d advances all 3,600 days" % [run_label, seed])
	_check(not coordinator.governance.has_failed(), "%s seed %d reaches the horizon without terminal failure" % [run_label, seed])
	_check(coordinator.governance.failure_reason().is_empty(), "%s seed %d has no terminal failure reason" % [run_label, seed])
	var date: Dictionary = coordinator.current_date()
	_check(
		int(date.get("year", -1)) == 11 and int(date.get("month", -1)) == 1 and int(date.get("day", -1)) == 1,
		"%s seed %d calendar reaches year 11 month 1 day 1" % [run_label, seed]
	)

	var ending_ids: Array[String] = coordinator.population.sorted_npc_ids()
	var unique_ids := {}
	for npc_id: String in ending_ids:
		unique_ids[npc_id] = true
	_check(coordinator.population.population_count() == 300, "%s seed %d retains 300 canonical residents" % [run_label, seed])
	_check(ending_ids.size() == 300, "%s seed %d exposes 300 sorted resident IDs" % [run_label, seed])
	_check(unique_ids.size() == ending_ids.size(), "%s seed %d introduces no duplicate resident IDs" % [run_label, seed])
	_check(ending_ids == starting_ids, "%s seed %d preserves stable resident identity" % [run_label, seed])

	var core_ids: Array[String] = []
	for core_id: Variant in coordinator.session.state.npcs.keys():
		core_ids.append(str(core_id))
	core_ids.sort()
	_check(core_ids == ending_ids, "%s seed %d keeps the core NPC mirror authoritative" % [run_label, seed])
	_check(
		int(coordinator.session.state.metrics.get("population", -1)) == ending_ids.size(),
		"%s seed %d keeps the core population metric synchronized" % [run_label, seed]
	)
	for npc_id: String in ending_ids:
		var record = coordinator.population.get_record(npc_id)
		_check(record != null, "%s seed %d retains resident %s" % [run_label, seed, npc_id])
		if record == null:
			continue
		_check(
			int(record.age) == int(starting_ages.get(npc_id, -10)) + 10,
			"%s seed %d advances resident %s age exactly ten years" % [run_label, seed, npc_id]
		)
		_check(
			coordinator.session.state.npcs.has(npc_id)
			and _canonical_json(coordinator.session.state.npcs[npc_id]) == _canonical_json(record.to_dict()),
			"%s seed %d keeps resident %s identical in the core mirror" % [run_label, seed, npc_id]
		)

	_check(coordinator.session.state.ledger.verify_balance(), "%s seed %d ledger recomputes to its stored balance" % [run_label, seed])
	_check(coordinator.treasury_balance() >= 0, "%s seed %d respects the no-overdraft treasury contract" % [run_label, seed])
	_check(
		coordinator.governance.grievance >= 0 and coordinator.governance.grievance <= 100,
		"%s seed %d keeps grievance in its declared 0..100 range" % [run_label, seed]
	)
	_check(
		coordinator.governance.municipal_trust >= 0 and coordinator.governance.municipal_trust <= 100,
		"%s seed %d keeps municipal trust in its declared 0..100 range" % [run_label, seed]
	)
	_check(
		int(coordinator.session.state.metrics.get("grievance", -1)) == coordinator.governance.grievance,
		"%s seed %d keeps grievance mirrored in core metrics" % [run_label, seed]
	)
	_check(
		int(coordinator.session.state.metrics.get("municipal_trust", -1)) == coordinator.governance.municipal_trust,
		"%s seed %d keeps municipal trust mirrored in core metrics" % [run_label, seed]
	)
	# This is the pre-existing vertical-slice 3,600-day soak contract, not a new
	# inferred balance threshold. It protects the UI-facing event batch bound.
	_check(elapsed_events.size() < 1_000, "%s seed %d preserves the established event-batch bound" % [run_label, seed])
	_check(coordinator.drain_ui_events().is_empty(), "%s seed %d drains the UI event queue after delivery" % [run_label, seed])

	# deterministic_hash() first stashes every final subsystem snapshot into the
	# envelope metadata; scan only after that so finite-value coverage is final,
	# not the initial snapshot left by the pre-soak hash.
	var final_state_hash: String = coordinator.deterministic_hash()
	var envelope: Dictionary = coordinator.session.make_envelope().to_dict()
	var non_finite_paths: Array[String] = []
	_collect_non_finite_paths(envelope, "$", non_finite_paths)
	_check(
		non_finite_paths.is_empty(),
		"%s seed %d keeps every numeric envelope value finite%s" % [
			run_label,
			seed,
			"" if non_finite_paths.is_empty() else ": " + ", ".join(non_finite_paths),
		]
	)

	var final_distribution := _population_distribution(coordinator)
	return {
		"run_label": run_label,
		"duration_ms": snappedf(duration_ms, 0.001),
		"game_day": coordinator.game_day(),
		"date": date,
		"event_count": elapsed_events.size(),
		"event_digest": _canonical_json(elapsed_events).sha256_text(),
		"treasury": coordinator.treasury_balance(),
		"population": ending_ids.size(),
		"grievance": coordinator.governance.grievance,
		"municipal_trust": coordinator.governance.municipal_trust,
		"initial_state_hash": initial_state_hash,
		"final_state_hash": final_state_hash,
		"initial_population_hash": initial_population_hash,
		"final_population_hash": coordinator.population.stable_hash(),
		"initial_profile_hash": initial_profile_hash,
		"initial_distribution": initial_distribution,
		"final_distribution": final_distribution,
		"non_finite_paths": non_finite_paths,
	}


func _population_profile_hash(coordinator) -> String:
	var profiles: Array[Dictionary] = []
	for npc_id: String in coordinator.population.sorted_npc_ids():
		profiles.append(coordinator.population.get_record(npc_id).to_dict())
	return _canonical_json(profiles).sha256_text()


func _population_distribution(coordinator) -> Dictionary:
	var ages: Array[int] = []
	var gender_histogram := {}
	var education_histogram := {}
	var personality_histogram := {}
	var employment_histogram := {}
	for npc_id: String in coordinator.population.sorted_npc_ids():
		var record = coordinator.population.get_record(npc_id)
		ages.append(int(record.age))
		_increment_histogram(gender_histogram, str(record.gender))
		_increment_histogram(education_histogram, str(record.education))
		_increment_histogram(personality_histogram, str(record.personality))
		_increment_histogram(employment_histogram, str(record.employment_state))
	var age_total := 0
	for age: int in ages:
		age_total += age
	return {
		"count": ages.size(),
		"age_min": ages.min() if not ages.is_empty() else 0,
		"age_max": ages.max() if not ages.is_empty() else 0,
		"age_average": snappedf(float(age_total) / float(ages.size()), 0.001) if not ages.is_empty() else 0.0,
		"gender_histogram": _sorted_dictionary(gender_histogram),
		"education_histogram": _sorted_dictionary(education_histogram),
		"personality_histogram": _sorted_dictionary(personality_histogram),
		"employment_histogram": _sorted_dictionary(employment_histogram),
	}


func _finish() -> void:
	var duration_ms := float(Time.get_ticks_usec() - _suite_started_usec) / 1000.0
	var summary := {
		"schema_version": 1,
		"suite": "mayor-simulator-multiseed-long-soak",
		"passed": not _failed,
		"seed_count": SEEDS.size(),
		"seeds": SEEDS,
		"runs_per_seed": RUNS_PER_SEED,
		"run_count": SEEDS.size() * RUNS_PER_SEED,
		"soak_days_per_run": SOAK_DAYS,
		"total_simulated_days": SEEDS.size() * RUNS_PER_SEED * SOAK_DAYS,
		"checks": _checks,
		"failure_count": _failures.size(),
		"failures": _failures,
		"duration_ms": snappedf(duration_ms, 0.001),
		"distribution_policy": "reported_only_no_ratio_gate",
		"event_bound_source": "existing_vertical_slice_3600_day_soak_contract",
		"results": _results,
	}
	var write_error := _write_summary(summary)
	if write_error != OK:
		_failed = true
		_failures.append("machine-readable summary write failed with error %d" % write_error)
		summary["passed"] = false
		summary["failure_count"] = _failures.size()
		summary["failures"] = _failures
	print("MULTISEED_LONG_SOAK_SUMMARY=" + JSON.stringify(summary))
	if not _failed:
		print(
			"Mayor Simulator multi-seed long-soak test passed. Seeds=%d Runs=%d SoakDaysPerRun=%d TotalDays=%d Checks=%d DurationMs=%.3f Summary=%s" % [
				SEEDS.size(),
				SEEDS.size() * RUNS_PER_SEED,
				SOAK_DAYS,
				SEEDS.size() * RUNS_PER_SEED * SOAK_DAYS,
				_checks,
				duration_ms,
				SUMMARY_PATH,
			]
		)
	quit(1 if _failed else 0)


func _write_summary(summary: Dictionary) -> Error:
	var absolute_directory := ProjectSettings.globalize_path("user://qa")
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK:
		return directory_error
	var file := FileAccess.open(SUMMARY_PATH, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(summary, "  "))
	file.flush()
	var file_error := file.get_error()
	file.close()
	return file_error


func _collect_non_finite_paths(value: Variant, path: String, failures: Array[String]) -> void:
	if value is float:
		if not is_finite(float(value)):
			failures.append(path)
		return
	if value is Dictionary:
		var dictionary: Dictionary = value
		for key: Variant in dictionary.keys():
			_collect_non_finite_paths(dictionary[key], "%s.%s" % [path, str(key)], failures)
		return
	if value is Array:
		var array: Array = value
		for index: int in range(array.size()):
			_collect_non_finite_paths(array[index], "%s[%d]" % [path, index], failures)


func _increment_histogram(histogram: Dictionary, key: String) -> void:
	histogram[key] = int(histogram.get(key, 0)) + 1


func _canonical_json(value: Variant) -> String:
	return JSON.stringify(_canonicalize(value))


func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var dictionary: Dictionary = value
		var result := {}
		for key: String in _sorted_keys(dictionary):
			result[key] = _canonicalize(dictionary[key])
		return result
	if value is Array:
		var array_result: Array = []
		for item: Variant in value:
			array_result.append(_canonicalize(item))
		return array_result
	if value is PackedStringArray:
		return Array(value)
	if value is float and is_equal_approx(float(value), roundf(float(value))):
		return int(value)
	return value


func _sorted_dictionary(source: Dictionary) -> Dictionary:
	var result := {}
	for key: String in _sorted_keys(source):
		result[key] = source[key]
	return result


func _sorted_keys(source: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key: Variant in source.keys():
		keys.append(str(key))
	keys.sort()
	return keys


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	_failures.append(label)
	push_error("Multi-seed long-soak check failed: %s" % label)
