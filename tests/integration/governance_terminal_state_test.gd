extends SceneTree

const COORDINATOR_PATH := "res://scripts/app/vertical_slice_coordinator.gd"
const SAVE_PATH := "user://mayor_simulator/tests/governance_terminal_state.json"

var _failed := false


func _initialize() -> void:
	var coordinator_script := ResourceLoader.load(COORDINATOR_PATH, "Script", ResourceLoader.CACHE_MODE_IGNORE) as Script
	_check(coordinator_script != null and coordinator_script.can_instantiate(), "coordinator compiles")
	if coordinator_script == null or not coordinator_script.can_instantiate():
		quit(1)
		return

	var coordinator = coordinator_script.new(20_260_731, 250_000)
	var initial_day: int = coordinator.game_day()
	var initial_population: int = coordinator.population.population_count()
	var initial_blueprint_sequence: int = coordinator.next_blueprint_sequence
	var initial_maintenance: bool = coordinator.maintenance_payment_enabled
	coordinator.governance.set_civic_metrics(81, 70)
	_check(coordinator.governance.failure_reason() == "grievance_above_80", "failure threshold enters the terminal state")

	var rejected_blueprint: Dictionary = coordinator.submit_blueprint({"building_name": "公園"})
	_check(not bool(rejected_blueprint.get("ok", false)), "blueprint command is rejected after failure")
	_check(str(rejected_blueprint.get("error", "")) == "game_already_failed", "terminal command returns the stable failure error")
	_check(coordinator.next_blueprint_sequence == initial_blueprint_sequence, "rejected terminal command consumes no blueprint ID")

	var first_events: Array[Dictionary] = coordinator.advance_days(5, {}, false)
	_check(coordinator.game_day() == initial_day, "advance_days cannot move time after failure")
	_check(_event_count(first_events, "governance_failed") == 1, "terminal failure event is emitted exactly once")
	var second_events: Array[Dictionary] = coordinator.advance_days(5, {}, false)
	_check(second_events.is_empty(), "later days do not repeat the terminal failure event")
	_check(coordinator.process_frame(600.0, {}, false).is_empty(), "wall-clock processing remains inert after failure")
	coordinator.set_time_paused(false)
	_check(coordinator.is_time_paused(), "failed session cannot be resumed")

	var population_result: Dictionary = coordinator.adjust_population(20, "test.after_failure")
	_check(not bool(population_result.get("ok", false)), "population mutation is rejected after failure")
	_check(coordinator.population.population_count() == initial_population, "terminal population remains unchanged")
	coordinator.set_maintenance_payment(not initial_maintenance)
	_check(coordinator.maintenance_payment_enabled == initial_maintenance, "maintenance policy is immutable after failure")
	_check(not bool(coordinator.submit_bill("environment_act").get("ok", false)), "governance proposal is rejected after failure")

	_check(coordinator.save_game(SAVE_PATH) == OK, "terminal state saves")
	var restored = coordinator_script.new(1, 1)
	_check(restored.load_game(SAVE_PATH), "terminal state loads")
	_check(restored.governance.failure_reason() == "grievance_above_80", "terminal reason survives save/load")
	_check(restored.is_time_paused(), "loaded terminal session remains paused")
	_check(_event_count(restored.drain_ui_events(), "governance_failed") == 0, "loading a saved terminal event does not emit it again")
	_check(restored.advance_days(1, {}, false).is_empty(), "loaded terminal session cannot advance")

	if _failed:
		quit(1)
	else:
		print("Governance terminal-state test passed. Failure event emitted once and all mutations locked.")
		quit(0)


func _event_count(events: Array[Dictionary], event_type: String) -> int:
	var count := 0
	for event: Dictionary in events:
		if str(event.get("type", "")) == event_type:
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Governance terminal-state test failed: %s" % message)
