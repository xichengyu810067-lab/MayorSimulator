extends SceneTree

const OnboardingProgressScript := preload("res://scripts/app/onboarding_progress.gd")

var _failed := false


func _initialize() -> void:
	var progress = OnboardingProgressScript.new()
	_check(progress.is_story_pending() and progress.current_target().is_empty(), "new progress starts at the story")
	_check(progress.begin_guide(), "story can transition to the ordered guide")
	var receipt_day := 0
	for index in OnboardingProgressScript.ORDERED_TARGETS.size():
		var target_id: String = OnboardingProgressScript.ORDERED_TARGETS[index]
		_check(progress.is_current_target_available(receipt_day), "step %d becomes available on its exact scheduled day" % index)
		_check(progress.current_target() == target_id, "step %d exposes the canonical target" % index)
		_check(not progress.record_current_target("wrong", _receipt(target_id, receipt_day)), "wrong target cannot advance step %d" % index)
		_check(progress.next_index() == index, "wrong target leaves step %d unchanged" % index)
		_check(progress.record_current_target(target_id, _receipt(target_id, receipt_day)), "canonical target advances step %d" % index)
		_check(not progress.record_current_target(target_id, _receipt(target_id, receipt_day)), "the same target cannot advance twice")
		if index + 1 < OnboardingProgressScript.ORDERED_TARGETS.size():
			var next_target: String = OnboardingProgressScript.ORDERED_TARGETS[index + 1]
			var wait_days := 1 if next_target in ["judicial", "oversight"] else 3
			_check(progress.due_game_day() == receipt_day + wait_days and progress.is_waiting(receipt_day), "step %d schedules the next segment after its specified delay" % index)
			_check(not progress.record_current_target(next_target, _receipt(next_target, receipt_day)), "waiting cannot insert or complete the next segment")
			receipt_day += wait_days
	_check(progress.is_completed() and progress.next_index() == 9, "nine ordered receipts complete onboarding")
	_check(progress.receipts().size() == 9, "receipt history is bounded to the nine fixed steps")
	_check(progress.due_game_day() == -1, "completed onboarding clears its schedule")

	var schema9_shell := {"schema_version": 9, "onboarding": progress.snapshot()}
	var resumed = OnboardingProgressScript.new()
	_check(bool(resumed.restore_from_shell_state(schema9_shell).get("ok", false)), "schema 9 exact completion resumes")
	_check(resumed.snapshot() == progress.snapshot(), "schema 9 completion round-trips exactly")
	var schema10_shell := {
		"schema_version": 10,
		"onboarding": progress.snapshot(),
		"building_metric_baselines": _metric_baselines(65),
	}
	var current_resumed = OnboardingProgressScript.new()
	_check(bool(current_resumed.restore_from_shell_state(schema10_shell).get("ok", false)), "schema 10 exact completion and metric baselines resume")
	_check(current_resumed.snapshot() == progress.snapshot(), "schema 10 onboarding state round-trips exactly")
	_check(not _legacy_schema9_reader_accepts(schema10_shell), "schema 9 reader rejects a schema 10 shell")

	var active = OnboardingProgressScript.new()
	active.begin_guide()
	active.record_current_target("build", _receipt("build", 0))
	_check(not active.record_current_target("blueprint", _receipt("blueprint", 0)), "same-day blueprint success cannot bypass pacing")
	active.record_current_target("blueprint", _receipt("blueprint", 3))
	var active_resumed = OnboardingProgressScript.new()
	_check(bool(active_resumed.restore_from_shell_state({"schema_version": 9, "onboarding": active.snapshot()}).get("ok", false)), "schema 9 active state resumes")
	_check(active_resumed.current_target() == "route" and active_resumed.receipts().size() == 2 and active_resumed.due_game_day() == 6, "schema 9 resumes the exact third target and schedule")

	var v1_snapshot := active.snapshot()
	v1_snapshot["schema_version"] = 1
	v1_snapshot.erase("due_game_day")
	var v1_resumed = OnboardingProgressScript.new()
	var v1_restore: Dictionary = v1_resumed.restore_from_shell_state({"schema_version": 9, "onboarding": v1_snapshot})
	_check(bool(v1_restore.get("ok", false)) and str(v1_restore.get("migration", "")) == "onboarding_snapshot_v1_to_v2", "snapshot v1 migrates explicitly")
	_check(v1_resumed.current_target() == "route" and v1_resumed.due_game_day() == -1 and v1_resumed.is_current_target_available(0), "snapshot v1 keeps its current segment immediately available")

	var deferred = OnboardingProgressScript.new()
	deferred.begin_guide()
	_check(deferred.defer_current_target(0) and deferred.due_game_day() == 3, "1/1 defer schedules 1/4")
	_check(deferred.defer_current_target(0) and deferred.due_game_day() == 6, "a repeated defer schedules 1/7")
	_check(deferred.defer_current_target(0) and deferred.due_game_day() == 9, "another repeated defer schedules 1/10")
	_check(not deferred.record_current_target("build", _receipt("build", 8)) and deferred.record_current_target("build", _receipt("build", 9)), "a deferred segment records only on or after its due day")
	var overdue = OnboardingProgressScript.new()
	overdue.begin_guide()
	overdue.defer_current_target(0)
	_check(overdue.defer_current_target(4) and overdue.due_game_day() == 7, "overdue defer uses max(due,current)+3")

	var case_pacing = OnboardingProgressScript.new()
	case_pacing.begin_guide()
	for index in 7:
		var target_id: String = OnboardingProgressScript.ORDERED_TARGETS[index]
		var day := maxi(0, case_pacing.due_game_day())
		_check(case_pacing.record_current_target(target_id, _receipt(target_id, day)), "case pacing setup records ordered step %d" % index)
	var governance_day := int(case_pacing.receipts()[6]["game_day"])
	_check(case_pacing.current_target() == "judicial" and case_pacing.due_game_day() == governance_day + 1, "governance schedules judicial guidance the next day")
	_check(not case_pacing.record_current_target("judicial", _receipt("judicial", governance_day)), "pre-due judicial receipt cannot bypass guidance")
	for shell_schema in [9, 10]:
		var shell := {"schema_version": shell_schema, "onboarding": case_pacing.snapshot()}
		if shell_schema == 10:
			shell["building_metric_baselines"] = _metric_baselines(65)
		var restored_case = OnboardingProgressScript.new()
		_check(bool(restored_case.restore_from_shell_state(shell).get("ok", false)) and restored_case.snapshot() == case_pacing.snapshot(), "schema %d retains the active one-day judicial schedule" % shell_schema)
	_check(case_pacing.defer_current_target(governance_day) and case_pacing.due_game_day() == governance_day + 4, "explicit judicial defer adds three days to its one-day schedule")
	var judicial_day := case_pacing.due_game_day()
	_check(case_pacing.record_current_target("judicial", _receipt("judicial", judicial_day)), "judicial defense records on its deferred due day")
	_check(case_pacing.current_target() == "oversight" and case_pacing.due_game_day() == judicial_day + 1, "judicial schedules oversight guidance the next day")
	_check(not case_pacing.record_current_target("oversight", _receipt("oversight", judicial_day)), "pre-due oversight receipt cannot bypass guidance")
	_check(case_pacing.defer_current_target(judicial_day) and case_pacing.due_game_day() == judicial_day + 4, "explicit oversight defer still adds three days")
	var oversight_shell := {"schema_version": 10, "onboarding": case_pacing.snapshot(), "building_metric_baselines": _metric_baselines(65)}
	var restored_oversight = OnboardingProgressScript.new()
	_check(bool(restored_oversight.restore_from_shell_state(oversight_shell).get("ok", false)) and restored_oversight.snapshot() == case_pacing.snapshot(), "schema 10 retains the deferred oversight date without rescheduling on reload")

	var legacy_complete = OnboardingProgressScript.new()
	_check(bool(legacy_complete.restore_from_shell_state({"schema_version": 8, "tutorial_completed": true}).get("ok", false)), "schema 8 completed tutorial migrates")
	_check(legacy_complete.is_completed() and legacy_complete.receipts().is_empty(), "schema 8 completion grants compatibility only, not synthetic receipts")
	_check(str(legacy_complete.snapshot()["completion_basis"]) == "legacy_schema8", "legacy completion remains distinguishable from real receipts")
	var legacy_story = OnboardingProgressScript.new()
	_check(bool(legacy_story.restore_from_shell_state({"schema_version": 8, "tutorial_completed": false}).get("ok", false)), "schema 8 incomplete tutorial migrates")
	_check(legacy_story.is_story_pending(), "schema 8 incomplete tutorial resumes from the story")

	var unknown_target := active.snapshot()
	unknown_target["current_target"] = "unknown"
	_assert_locked({"schema_version": 9, "onboarding": unknown_target}, "unknown target")
	var impossible_order := active.snapshot()
	impossible_order["next_index"] = 3
	impossible_order["current_target"] = "fiscal"
	_assert_locked({"schema_version": 9, "onboarding": impossible_order}, "impossible receipt order")
	var arbitrary_receipt := active.snapshot()
	var receipts: Array = arbitrary_receipt["receipts"]
	var first_receipt: Dictionary = Dictionary(receipts[0]).duplicate(true)
	first_receipt["callback"] = "free"
	receipts[0] = first_receipt
	_assert_locked({"schema_version": 9, "onboarding": arbitrary_receipt}, "receipt with an arbitrary field")
	var missing_baselines := {"schema_version": 10, "onboarding": active.snapshot()}
	_assert_locked(missing_baselines, "schema 10 missing metric baselines")
	var extra_baseline := schema10_shell.duplicate(true)
	extra_baseline["building_metric_baselines"]["unknown"] = 70
	_assert_locked(extra_baseline, "schema 10 arbitrary metric baseline")
	var floating_baseline := schema10_shell.duplicate(true)
	floating_baseline["building_metric_baselines"]["environment"] = 65.5
	_assert_locked(floating_baseline, "schema 10 fractional metric baseline")
	var out_of_range_baseline := schema10_shell.duplicate(true)
	out_of_range_baseline["building_metric_baselines"]["environment"] = 101
	_assert_locked(out_of_range_baseline, "schema 10 out-of-range metric baseline")
	_assert_locked({"schema_version": 11, "onboarding": active.snapshot()}, "future shell schema")
	var future_snapshot := active.snapshot()
	future_snapshot["schema_version"] = 3
	_assert_locked({"schema_version": 9, "onboarding": future_snapshot}, "future onboarding schema")
	var malformed_schedule := active.snapshot()
	malformed_schedule["due_game_day"] = "tomorrow"
	_assert_locked({"schema_version": 9, "onboarding": malformed_schedule}, "malformed onboarding schedule")

	if _failed:
		quit(1)
	else:
		print("Onboarding progress state test passed.")
		quit(0)


func _receipt(kind: String, game_day: int) -> Dictionary:
	return {"kind": kind, "authority_id": "authority_%d" % game_day, "entity_id": "entity_%d" % game_day, "game_day": game_day}


func _metric_baselines(value: int) -> Dictionary:
	var baselines: Dictionary = {}
	for metric_name: String in OnboardingProgressScript.BUILDING_METRIC_BASELINE_KEYS:
		baselines[metric_name] = value
	return baselines


func _legacy_schema9_reader_accepts(shell: Dictionary) -> bool:
	var schema_value: Variant = shell.get("schema_version", 0)
	if typeof(schema_value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	return int(schema_value) <= 9


func _assert_locked(shell: Dictionary, label: String) -> void:
	var progress = OnboardingProgressScript.new()
	var result: Dictionary = progress.restore_from_shell_state(shell)
	_check(not bool(result.get("ok", true)) and progress.is_locked(), "%s fails closed and locks onboarding" % label)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Onboarding progress check failed: %s" % message)
