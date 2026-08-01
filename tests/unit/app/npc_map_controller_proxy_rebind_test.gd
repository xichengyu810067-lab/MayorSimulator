extends SceneTree

const NpcMapControllerScript = preload("res://scripts/app/npc_map_controller.gd")
const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")

class FakeNpcActor extends Button:
	var set_actor_calls := 0
	var last_type := ""
	var last_dark_mode := false
	var last_seed := 0

	func set_actor(type_name: String, dark_mode: bool, variant_seed: int = 0) -> void:
		set_actor_calls += 1
		last_type = type_name
		last_dark_mode = dark_mode
		last_seed = variant_seed


var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var controller = NpcMapControllerScript.new()
	root.add_child(controller)
	var states: Array[Dictionary] = [
		_proxy_state("npc_a", "一般居民", Vector2(10, 20)),
		_proxy_state("npc_b", "學生", Vector2(30, 40)),
		_proxy_state("npc_c", "工人", Vector2(50, 60)),
	]
	var actors: Array[Button] = []
	for _index in states.size():
		var actor := FakeNpcActor.new()
		controller.add_child(actor)
		actors.append(actor)
	controller.bind_existing_proxy_pool(states, actors)

	var desired: Array[Dictionary] = [
		_proxy("npc_b", "學生", "居民 B"),
		_proxy("npc_a", "一般居民", "居民 A"),
		_proxy("npc_d", "商人", "居民 D"),
	]
	_check(controller.reconcile_proxy_pool(desired, true), "same-size authoritative roster requested a rebuild")
	_check(str(states[0].get("record_id", "")) == "npc_a", "retained npc_a did not keep slot 0")
	_check(str(states[1].get("record_id", "")) == "npc_b", "retained npc_b did not keep slot 1")
	_check(str(states[2].get("record_id", "")) == "npc_d", "vacated slot did not receive npc_d")
	_check(Vector2(states[0].get("pos", Vector2.ZERO)) == Vector2(10, 20), "retained npc_a locomotion position changed")
	_check(Vector2(states[1].get("pos", Vector2.ZERO)) == Vector2(30, 40), "retained npc_b locomotion position changed")
	_check((actors[0] as FakeNpcActor).set_actor_calls == 0, "unchanged npc_a actor was reset")
	_check((actors[1] as FakeNpcActor).set_actor_calls == 0, "unchanged npc_b actor was reset")
	_check((actors[2] as FakeNpcActor).set_actor_calls == 1, "new npc_d actor was not reset exactly once")
	_check((actors[2] as FakeNpcActor).last_type == "商人", "new npc_d archetype was not applied")
	_check((actors[2] as FakeNpcActor).last_dark_mode, "dark-mode binding was not forwarded")

	var ids_before_mismatch := _record_ids(states)
	_check(not controller.reconcile_proxy_pool(desired.slice(0, 2), true), "cardinality mismatch did not request rebuild")
	_check(_record_ids(states) == ids_before_mismatch, "cardinality mismatch partially rewrote the visible pool")

	var malformed: Array[Dictionary] = [
		_proxy("", "一般居民", "空白一"),
		_proxy("", "學生", "空白二"),
		_proxy("npc_d", "商人", "居民 D"),
	]
	_check(controller.reconcile_proxy_pool(malformed, false), "malformed same-size roster unexpectedly requested rebuild")
	_check(str(states[0].get("record_id", "stale")) == "", "blank authoritative id left a stale slot identity")
	_check(str(states[1].get("record_id", "stale")) == "", "second blank authoritative id left a stale slot identity")

	var exit_code := 1 if _failed else 0
	if not _failed:
		print("NPC map controller proxy rebind passed. StableSlots=2 Rebound=1 MismatchAtomic=true")
	await TestCleanup.finish(self, [controller], exit_code)


func _proxy_state(record_id: String, archetype: String, position: Vector2) -> Dictionary:
	return {
		"record_id": record_id,
		"type": archetype,
		"display_name": record_id,
		"pos": position,
		"foot_position": position + Vector2(26, 65),
		"velocity": Vector2(3, 4),
		"travelled_distance": 12.0,
	}


func _proxy(record_id: String, archetype: String, display_name: String) -> Dictionary:
	return {
		"npc_id": record_id,
		"archetype": archetype,
		"display_name": display_name,
		"family_name": "",
		"given_name": "",
		"latin_display_name": display_name,
	}


func _record_ids(states: Array[Dictionary]) -> PackedStringArray:
	var ids := PackedStringArray()
	for state: Dictionary in states:
		ids.append(str(state.get("record_id", "")))
	return ids


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("NPC map controller proxy rebind failed: %s" % message)
