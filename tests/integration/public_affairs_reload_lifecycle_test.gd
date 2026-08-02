extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const TEST_SAVE_PATH := "user://mayor_simulator/tests/public_affairs_reload_lifecycle.json"
const REQUIRED_REQUEST_TYPES := ["park", "hospital", "school"]

var _failed := false
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_save()
	root.content_scale_size = Vector2i(1920, 1080)
	root.size = Vector2i(1920, 1080)

	var packed: PackedScene = load("res://scenes/Main.tscn")
	_check(packed != null, "Main scene can be loaded")
	if packed == null:
		await _finish([])
		return

	var first = packed.instantiate()
	root.add_child(first)
	await _settle(3)
	first.start_save_path = TEST_SAVE_PATH
	first.start_screen.set_continue_available(false)
	first.start_screen.animation_duration = 0.04
	first.start_screen.new_game_button.emit_signal("pressed")
	await _wait_for_loading(first, "new game")
	_check(first._game_started and not first.start_screen.visible, "New enters the live Main scene")
	if first.tutorial_overlay != null and first.tutorial_overlay.is_open():
		first.tutorial_overlay.close_as_completed(false)
		first.tutorial_overlay._transition.custom_step(1.0)
	await _settle(2)
	_check(first.tutorial_completed, "the first instance records tutorial completion before saving")

	var initial_records: Dictionary = _request_records_by_id(first)
	var initial_by_type: Dictionary = _request_ids_by_type(initial_records)
	_check(initial_records.size() == 3, "an empty new city exposes exactly the three canonical opening requests")
	for request_type: String in REQUIRED_REQUEST_TYPES:
		_check(initial_by_type.has(request_type), "opening requests include %s" % request_type)
	if not _has_required_request_types(initial_by_type):
		await _finish([first])
		return

	var completed_id := str(initial_by_type["park"])
	var accepted_id := str(initial_by_type["hospital"])
	var rejected_id := str(initial_by_type["school"])
	var expected: Dictionary = {}
	for request_id: String in [completed_id, accepted_id, rejected_id]:
		var initial: Dictionary = initial_records[request_id]
		_check(not request_id.is_empty(), "opening request id is non-empty")
		_check(not str(initial.get("npc_id", "")).is_empty(), "%s has an authoritative NPC id" % request_id)
		_check(not str(initial.get("title", "")).is_empty(), "%s has a stable title" % request_id)
		expected[request_id] = {
			"request_id": request_id,
			"npc_id": str(initial.get("npc_id", "")),
			"request_type": str(initial.get("request_type", "")),
			"title": str(initial.get("title", "")),
			"status": (
				"completed" if request_id == completed_id
				else ("accepted" if request_id == accepted_id else "rejected")
			),
		}
	_check(completed_id != accepted_id and completed_id != rejected_id and accepted_id != rejected_id, "the three lifecycle branches retain distinct request identities")

	first.call("_open_municipal_center")
	first.municipal_overlay.call("open_page", "public_affairs")
	await _settle(2)
	_check(first.public_affairs_panel != null, "Main mounts the real public-affairs page")
	if first.public_affairs_panel == null:
		await _finish([first])
		return

	var completed_accept := first.public_affairs_panel._request_buttons.get(completed_id) as Button
	_check(completed_accept != null, "park request exposes its real accept action")
	if completed_accept != null:
		completed_accept.emit_signal("pressed")
	await _settle(2)

	var accepted_accept := first.public_affairs_panel._request_buttons.get(accepted_id) as Button
	_check(accepted_accept != null, "hospital request exposes its real accept action after the panel rebuild")
	if accepted_accept != null:
		accepted_accept.emit_signal("pressed")
	await _settle(2)

	var rejected_action := first.public_affairs_panel._reject_buttons.get(rejected_id) as Button
	_check(rejected_action != null, "school request exposes its real reject action after the panel rebuild")
	if rejected_action != null:
		rejected_action.emit_signal("pressed")
	await _settle(2)

	var completed_ids: Array[String] = first.vertical_slice.complete_requests({
		"park_count": 99,
		"hospital_count": 0,
		"operational_hospital_count": 0,
		"operational_hospital_capacity": 0,
		"school_count": 0,
		"utility_fee": 999,
	})
	_check(completed_ids == [completed_id], "only the accepted park request completes under the isolated completion context")
	first.call("_consume_vertical_events", first.vertical_slice.drain_ui_events())
	await _settle(2)

	_validate_authoritative_records(first, expected, "before save")
	_validate_public_affairs_cards(first.public_affairs_panel, expected, "before save")
	_check(first.call("_autosave", "test:public_affairs_reload_lifecycle") == OK, "Main performs a real isolated autosave")
	_check(FileAccess.file_exists(ProjectSettings.globalize_path(TEST_SAVE_PATH)), "the isolated save exists before the first Main instance is released")

	await TestCleanup.release_fixtures(self, [first])
	var resumed = packed.instantiate()
	root.add_child(resumed)
	await _settle(3)
	resumed.start_save_path = TEST_SAVE_PATH
	resumed.start_screen.set_continue_available(true)
	resumed.start_screen.animation_duration = 0.04
	resumed.start_screen.continue_game_button.emit_signal("pressed")
	await _wait_for_loading(resumed, "continue")
	_check(resumed._game_started and not resumed.start_screen.visible, "a new Main instance reaches the city through Continue")
	_check(resumed.tutorial_completed and not resumed.tutorial_overlay.is_open(), "Continue restores shell state without reopening the tutorial")

	resumed.call("_open_municipal_center")
	resumed.municipal_overlay.call("open_page", "public_affairs")
	await _settle(2)
	_validate_authoritative_records(resumed, expected, "after Continue")
	_validate_public_affairs_cards(resumed.public_affairs_panel, expected, "after Continue")

	var restored_records: Dictionary = _request_records_by_id(resumed)
	_check(restored_records.size() == initial_records.size(), "Continue restores the complete public-affairs history without adding replacement requests")
	for request_id: String in expected.keys():
		var restored: Dictionary = restored_records.get(request_id, {})
		_check(str(restored.get("status", "pending")) != "pending", "%s does not regress to pending after Continue" % request_id)

	await _finish([resumed])


func _validate_authoritative_records(main, expected: Dictionary, phase: String) -> void:
	var records: Dictionary = _request_records_by_id(main)
	for request_id: String in expected.keys():
		var spec: Dictionary = expected[request_id]
		_check(records.has(request_id), "%s retains request %s" % [phase, request_id])
		if not records.has(request_id):
			continue
		var record: Dictionary = records[request_id]
		for identity_key: String in ["request_id", "npc_id", "request_type", "title"]:
			_check(str(record.get(identity_key, "")) == str(spec.get(identity_key, "")), "%s %s retains %s" % [phase, request_id, identity_key])
		var status := str(spec.get("status", ""))
		_check(str(record.get("status", "")) == status, "%s %s remains %s" % [phase, request_id, status])
		if status in ["accepted", "completed"]:
			_check(int(record.get("accepted_day", -1)) >= 0, "%s %s retains its accepted day" % [phase, request_id])
		if status == "rejected":
			_check(int(record.get("rejected_day", -1)) >= 0, "%s %s retains its rejected day" % [phase, request_id])
		if status == "completed":
			_check(int(record.get("completed_day", -1)) >= 0, "%s %s retains its completed day" % [phase, request_id])


func _validate_public_affairs_cards(panel, expected: Dictionary, phase: String) -> void:
	_check(panel != null, "%s keeps the public-affairs panel mounted" % phase)
	if panel == null:
		return
	for request_id: String in expected.keys():
		var spec: Dictionary = expected[request_id]
		var npc_id := str(spec.get("npc_id", ""))
		var status := str(spec.get("status", ""))
		var card := panel.find_child("CitizenRequest_%s" % request_id, true, false) as PanelContainer
		var status_button := panel.find_child("AcceptRequest_%s" % request_id, true, false) as Button
		var reject_button := panel.find_child("RejectRequest_%s" % request_id, true, false) as Button
		var npc_model := panel.find_child("CitizenNpcModel_%s" % npc_id, true, false) as Button
		_check(card != null, "%s %s card retains its request id" % [phase, request_id])
		_check(status_button != null, "%s %s retains its status control" % [phase, request_id])
		_check(reject_button != null, "%s %s retains its reject-control record" % [phase, request_id])
		_check(npc_model != null, "%s %s retains its NPC model" % [phase, request_id])
		if card == null or status_button == null or reject_button == null or npc_model == null:
			continue
		_check(status_button.text == _localized(_status_text(status)), "%s %s renders exact %s text" % [phase, request_id, status])
		_check(status_button.disabled, "%s %s terminal status is not actionable" % [phase, request_id])
		_check(not reject_button.visible and reject_button.disabled, "%s %s cannot return through the reject branch" % [phase, request_id])
		_check(str(npc_model.get_meta("npc_id", "")) == npc_id, "%s %s model retains the authoritative NPC id" % [phase, request_id])
		_check(str(npc_model.get_meta("model_source", "")) == "authoritative_npc_record", "%s %s model still comes from the authoritative NPC record" % [phase, request_id])
		var card_text := _descendant_label_text(card)
		_check(card_text.contains(_localized(str(spec.get("title", "")))), "%s %s card retains its request title" % [phase, request_id])
		_check(card_text.contains(_localized(_status_text(status))), "%s %s card copy retains its terminal status" % [phase, request_id])


func _request_records_by_id(main) -> Dictionary:
	var result: Dictionary = {}
	var requests: Array = main.vertical_slice.get_view_model().get("citizen_requests", [])
	for request_variant: Variant in requests:
		if not request_variant is Dictionary:
			continue
		var request: Dictionary = request_variant
		var request_id := str(request.get("request_id", ""))
		if not request_id.is_empty():
			result[request_id] = request.duplicate(true)
	return result


func _request_ids_by_type(records: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for request_id: String in records.keys():
		var request: Dictionary = records[request_id]
		result[str(request.get("request_type", ""))] = request_id
	return result


func _has_required_request_types(by_type: Dictionary) -> bool:
	for request_type: String in REQUIRED_REQUEST_TYPES:
		if not by_type.has(request_type):
			return false
	return true


func _descendant_label_text(node: Node) -> String:
	var lines := PackedStringArray()
	for label_variant: Variant in node.find_children("*", "Label", true, false):
		var label := label_variant as Label
		if label != null:
			lines.append(label.text)
	return "\n".join(lines)


func _status_text(status: String) -> String:
	return str({
		"accepted": "已受理",
		"rejected": "已拒絕",
		"completed": "已完成",
	}.get(status, "待回應"))


func _localized(source: String) -> String:
	var l10n = root.get_node_or_null("L10n")
	return str(l10n.call("text", source)) if l10n != null else source


func _wait_for_loading(main, phase: String) -> void:
	for _frame in range(180):
		await process_frame
		if not main.start_screen.is_loading():
			return
	_fail("%s loading did not finish within 180 frames" % phase)


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame


func _cleanup_save() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	for suffix: String in ["", ".tmp", ".bak"]:
		var candidate := absolute_path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _finish(fixtures: Array) -> void:
	_cleanup_save()
	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Public affairs reload lifecycle test passed. Checks=%d Requests=3" % _checks)
	await TestCleanup.finish(self, fixtures, exit_code)


func _fail(message: String) -> void:
	_failed = true
	push_error("Public affairs reload lifecycle failed: %s" % message)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_fail(message)
