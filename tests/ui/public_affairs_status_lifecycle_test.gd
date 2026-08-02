extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")

const REQUEST_A := "request_a"
const REQUEST_B := "request_b"
const NPC_A := "npc_a"
const NPC_B := "npc_b"

var _failed := false
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await process_frame
	var panel = main.public_affairs_panel
	_check(panel != null, "Main exposes the public-affairs panel")
	if panel == null:
		await TestCleanup.finish(self, [main], 1)
		return

	# Both requests begin in the only legal source state for accept/reject.
	_render(panel, "pending", "pending")
	await process_frame
	_check_rendered_snapshot(panel, {
		REQUEST_A: {"npc_id": NPC_A, "status": "pending", "expression": "concerned"},
		REQUEST_B: {"npc_id": NPC_B, "status": "pending", "expression": "concerned"},
	}, "pending")

	# Legal branch point: A is rejected while B is accepted.
	_render(panel, "rejected", "accepted")
	await process_frame
	_check_rendered_snapshot(panel, {
		REQUEST_A: {"npc_id": NPC_A, "status": "rejected", "expression": "concerned"},
		REQUEST_B: {"npc_id": NPC_B, "status": "accepted", "expression": "proud"},
	}, "decision")

	# Only an accepted request may complete. A must remain rejected in the same
	# panel instance while B advances, proving that the rebuild clears stale UI.
	_render(panel, "rejected", "completed")
	await process_frame
	_check_rendered_snapshot(panel, {
		REQUEST_A: {"npc_id": NPC_A, "status": "rejected", "expression": "concerned"},
		REQUEST_B: {"npc_id": NPC_B, "status": "completed", "expression": "proud"},
	}, "completion")

	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Public affairs status rendering test passed. Checks=%d Requests=2 Snapshots=3" % _checks)
	await TestCleanup.finish(self, [main], exit_code)


func _render(panel, status_a: String, status_b: String) -> void:
	panel.set_view_model({
		"citizen_requests": [
			_request(REQUEST_A, NPC_A, status_a),
			_request(REQUEST_B, NPC_B, status_b),
		]
	})


func _check_rendered_snapshot(panel, expected: Dictionary, phase: String) -> void:
	_check(panel.find_children("CitizenRequest_*", "PanelContainer", true, false).size() == expected.size(), "%s snapshot must expose exactly one card per request" % phase)
	_check(panel.find_children("AcceptRequest_*", "Button", true, false).size() == expected.size(), "%s snapshot must expose exactly one status button per request" % phase)
	_check(panel.find_children("RejectRequest_*", "Button", true, false).size() == expected.size(), "%s snapshot must retain one reject-control record per request" % phase)
	for request_id_variant: Variant in expected.keys():
		var request_id := str(request_id_variant)
		var spec: Dictionary = expected[request_id_variant]
		var npc_id := str(spec.get("npc_id", ""))
		var status := str(spec.get("status", ""))
		var card := panel.find_child("CitizenRequest_%s" % request_id, true, false) as PanelContainer
		var status_button := panel.find_child("AcceptRequest_%s" % request_id, true, false) as Button
		var reject_button := panel.find_child("RejectRequest_%s" % request_id, true, false) as Button
		var npc_model := panel.find_child("CitizenNpcModel_%s" % npc_id, true, false) as Button
		_check(card != null, "%s %s card is missing or has another request identity" % [phase, request_id])
		_check(status_button != null, "%s %s status button is missing" % [phase, request_id])
		_check(reject_button != null, "%s %s reject control is missing" % [phase, request_id])
		_check(npc_model != null, "%s %s NPC presentation is missing" % [phase, request_id])
		if card == null or status_button == null or reject_button == null or npc_model == null:
			continue
		_check(status_button.text == _localized(_status_text(status)), "%s %s must render only its own %s label" % [phase, request_id, status])
		var is_pending := status == "pending"
		_check(status_button.disabled == not is_pending, "%s %s actionability must match %s" % [phase, request_id, status])
		_check(reject_button.visible == is_pending and reject_button.disabled == not is_pending, "%s %s reject action must match %s" % [phase, request_id, status])
		_check(str(npc_model.get_meta("npc_id", "")) == npc_id, "%s %s NPC node must retain its authoritative id" % [phase, request_id])
		_check(str(npc_model.get_meta("npc_expression", "")) == str(spec.get("expression", "")), "%s %s NPC expression must match %s rendering" % [phase, request_id, status])


func _request(request_id: String, npc_id: String, status: String) -> Dictionary:
	return {
		"request_id": request_id,
		"npc_id": npc_id,
		"npc_name": npc_id,
		"npc_archetype": "一般居民",
		"npc_model_seed": absi(hash(npc_id)),
		"request_type": "park",
		"title": "居民陳情",
		"description": "公共事務狀態生命週期測試。",
		"status": status,
	}


func _status_text(status: String) -> String:
	return str({
		"pending": "受理",
		"rejected": "已拒絕",
		"accepted": "已受理",
		"completed": "已完成",
	}.get(status, "待回應"))


func _localized(source: String) -> String:
	var l10n = root.get_node_or_null("L10n")
	return str(l10n.call("text", source)) if l10n != null else source


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Public affairs status rendering check failed: %s" % message)
