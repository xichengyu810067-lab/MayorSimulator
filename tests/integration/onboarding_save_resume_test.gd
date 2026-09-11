extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1440, 900)
	root.size = Vector2i(1440, 900)
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(3)
	main.start_screen.hide()
	main.set("_game_started", true)

	var schema8_complete := main.call("_capture_player_shell_state") as Dictionary
	schema8_complete["schema_version"] = 8
	schema8_complete.erase("onboarding")
	schema8_complete["tutorial_completed"] = true
	schema8_complete["tax_rates"] = {"income": 16, "consumption": 5, "business": 8, "industry": 10}
	_check(bool(main.call("_restore_player_shell_state", schema8_complete)), "schema 8 completed shell restores")
	_check(main.onboarding_progress.is_completed() and main.tutorial_completed, "schema 8 true maps to compatibility completion")
	_check(main.onboarding_progress.receipts().is_empty(), "schema 8 completion does not authorize domain receipts")
	_check(int(main.tax_rates["income"]) == 16, "valid schema 8 applies Main-owned fields after validation")

	var schema8_story := schema8_complete.duplicate(true)
	schema8_story["tutorial_completed"] = false
	_check(bool(main.call("_restore_player_shell_state", schema8_story)), "schema 8 incomplete shell restores")
	_check(main.onboarding_progress.is_story_pending() and not main.tutorial_completed, "schema 8 false resumes at story first shot")

	main.onboarding_progress.reset_for_new_game()
	main.onboarding_progress.begin_guide()
	main.onboarding_progress.record_current_target("build", _receipt("build", 0))
	main.onboarding_progress.record_current_target("blueprint", _receipt("blueprint", 1))
	main.tax_rates["income"] = 19
	var schema9_active := main.call("_capture_player_shell_state") as Dictionary
	_check(int(schema9_active["schema_version"]) == 9, "captured shell advances to schema 9")
	var incoming_copy := schema9_active.duplicate(true)
	main.tax_rates["income"] = 7
	_check(bool(main.call("_restore_player_shell_state", schema9_active)), "schema 9 active shell restores")
	_check(main.tutorial_completed, "schema 9 active restore preserves the legacy story-seen flag")
	_check(main.onboarding_progress.current_target() == "route", "schema 9 resumes the exact current target")
	_check(main.onboarding_progress.receipts().size() == 2, "schema 9 preserves bounded receipts")
	_check(int(main.tax_rates["income"]) == 19, "valid schema 9 applies Main-owned fields")
	_check(schema9_active == incoming_copy, "valid restore does not rewrite the incoming snapshot")

	var before_tax := int(main.tax_rates["income"])
	var before_autosaves := int(main.get("_autosave_count"))
	var malformed := schema9_active.duplicate(true)
	malformed["tax_rates"]["income"] = 29
	malformed["onboarding"]["current_target"] = "unknown"
	var malformed_copy := malformed.duplicate(true)
	_check(not bool(main.call("_restore_player_shell_state", malformed)), "malformed schema 9 is rejected")
	_check(main.onboarding_progress.is_locked(), "malformed schema 9 locks only onboarding")
	_check(int(main.tax_rates["income"]) == before_tax, "malformed schema does not mutate Main-owned tax state")
	_check(int(main.get("_autosave_count")) == before_autosaves, "malformed restore does not autosave")
	_check(main.call("_autosave", "test:locked_onboarding") == ERR_INVALID_DATA, "locked onboarding prevents later autosave overwrite")
	_check(malformed == malformed_copy, "malformed incoming snapshot remains byte-structure equivalent")

	var future := schema9_active.duplicate(true)
	future["schema_version"] = 10
	future["tax_rates"]["income"] = 28
	var future_copy := future.duplicate(true)
	_check(not bool(main.call("_restore_player_shell_state", future)), "future shell schema is rejected")
	_check(int(main.tax_rates["income"]) == before_tax, "future schema does not mutate Main-owned fields")
	_check(int(main.get("_autosave_count")) == before_autosaves, "future schema does not autosave")
	_check(future == future_copy, "future incoming snapshot remains unchanged")

	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Onboarding save/resume test passed.")
	await TestCleanup.finish(self, [main], exit_code)


func _receipt(kind: String, index: int) -> Dictionary:
	return {"kind": kind, "authority_id": "authority_%d" % index, "entity_id": "entity_%d" % index, "game_day": index + 1}


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Onboarding save/resume check failed: %s" % message)
