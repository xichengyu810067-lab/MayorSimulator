extends SceneTree

const OnboardingProgressScript := preload("res://scripts/app/onboarding_progress.gd")

var _failed := false


func _initialize() -> void:
	var progress = OnboardingProgressScript.new()
	_check(progress.is_story_pending() and progress.current_target().is_empty(), "new progress starts at the story")
	_check(progress.begin_guide(), "story can transition to the ordered guide")
	for index in OnboardingProgressScript.ORDERED_TARGETS.size():
		var target_id: String = OnboardingProgressScript.ORDERED_TARGETS[index]
		var receipt_day := index * OnboardingProgressScript.STAGE_DELAY_DAYS
		_check(progress.is_current_target_available(receipt_day), "step %d becomes available on its exact scheduled day" % index)
		_check(progress.current_target() == target_id, "step %d exposes the canonical target" % index)
		_check(not progress.record_current_target("wrong", _receipt(target_id, receipt_day)), "wrong target cannot advance step %d" % index)
		_check(progress.next_index() == index, "wrong target leaves step %d unchanged" % index)
		_check(progress.record_current_target(target_id, _receipt(target_id, receipt_day)), "canonical target advances step %d" % index)
		_check(not progress.record_current_target(target_id, _receipt(target_id, receipt_day)), "the same target cannot advance twice")
		if index + 1 < OnboardingProgressScript.ORDERED_TARGETS.size():
			_check(progress.due_game_day() == receipt_day + 3 and progress.is_waiting(receipt_day), "step %d schedules the next segment three full game days later" % index)
			var next_target: String = OnboardingProgressScript.ORDERED_TARGETS[index + 1]
			_check(not progress.record_current_target(next_target, _receipt(next_target, receipt_day)), "waiting cannot insert or complete the next segment")
	_check(progress.is_completed() and progress.next_index() == 9, "nine ordered receipts complete onboarding")
	_check(progress.receipts().size() == 9, "receipt history is bounded to the nine fixed steps")
	_check(progress.due_game_day() == -1, "completed onboarding clears its schedule")

	var schema9_shell := {"schema_version": 9, "onboarding": progress.snapshot()}
	var resumed = OnboardingProgressScript.new()
	_check(bool(resumed.restore_from_shell_state(schema9_shell).get("ok", false)), "schema 9 exact completion resumes")
	_check(resumed.snapshot() == progress.snapshot(), "schema 9 completion round-trips exactly")

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
	_assert_locked({"schema_version": 10, "onboarding": active.snapshot()}, "future shell schema")
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


func _assert_locked(shell: Dictionary, label: String) -> void:
	var progress = OnboardingProgressScript.new()
	var result: Dictionary = progress.restore_from_shell_state(shell)
	_check(not bool(result.get("ok", true)) and progress.is_locked(), "%s fails closed and locks onboarding" % label)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Onboarding progress check failed: %s" % message)
