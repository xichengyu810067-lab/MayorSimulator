extends SceneTree

var _failed := false
var _background_presses := 0
var _primary_requests := 0
var _dismiss_requests := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(960, 640)
	root.size = Vector2i(960, 640)

	var stage := Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(stage)

	var map_button := Button.new()
	map_button.name = "MapBehindDialogue"
	map_button.position = Vector2(110, 84)
	map_button.size = Vector2(560, 280)
	map_button.pressed.connect(_on_background_pressed)
	stage.add_child(map_button)

	var card_script = load("res://ui/components/npc_dialogue_card.gd")
	_check(card_script != null, "NPC dialogue card script could not be loaded")
	if card_script == null:
		quit(1)
		return
	var card: PanelContainer = card_script.new()
	card.position = Vector2(140, 110)
	stage.add_child(card)
	card.primary_action_requested.connect(_on_primary_requested)
	card.dismiss_requested.connect(_on_dismiss_requested)

	var portrait := load("res://assets/images/characters/npc/npc-merchant.png") as Texture2D
	card.call("set_content", "黃建宏", "商人", "市場最近很熱鬧，但攤位旁的路燈需要修理。", "待回應", portrait, "查看陳情")
	await process_frame
	await process_frame

	_check(card.custom_minimum_size.x >= 420.0 and card.custom_minimum_size.x <= 500.0, "card width is outside the 420-500px map range")
	_check(card.size.x >= 420.0 and card.size.x <= 500.0, "runtime card width is outside the 420-500px map range")
	_check(card.mouse_filter == Control.MOUSE_FILTER_STOP, "dialogue card does not stop pointer input")
	_check(card.z_index >= 2000, "dialogue card does not render above map actors")
	_check(card.message_label is Label, "message_label is not exposed for main compatibility")
	_check(card.message_label.text == "市場最近很熱鬧，但攤位旁的路燈需要修理。", "message_label lost the supplied dialogue")
	_check(card.name_label.text == "黃建宏", "NPC name was not rendered")
	_check(card.role_label.text == "商人", "NPC role subtitle was not rendered")
	_check(card.petition_status_label.text == "待回應" and card._status_chip.visible, "petition status hint was not rendered")
	_check(card.portrait_rect.texture == portrait, "NPC portrait was not rendered")
	_check(card.primary_action_button.visible and card.primary_action_button.text == "查看陳情", "optional primary action was not rendered")
	_check(card.close_button.custom_minimum_size.x >= 44.0 and card.close_button.custom_minimum_size.y >= 44.0, "dismiss target is smaller than 44x44")
	_check(card.primary_action_button.custom_minimum_size.x >= 44.0 and card.primary_action_button.custom_minimum_size.y >= 44.0, "primary action target is smaller than 44x44")
	_check(card.close_button.size.x >= 44.0 and card.close_button.size.y >= 44.0, "dismiss control does not receive a 44x44 layout target")
	_check(card.primary_action_button.size.x >= 44.0 and card.primary_action_button.size.y >= 44.0, "primary action control does not receive a 44x44 layout target")

	var light_style := card.get_theme_stylebox("panel") as StyleBoxFlat
	var light_text: Color = card.message_label.get_theme_color("font_color")
	card.call("set_dark_mode", true)
	var dark_style := card.get_theme_stylebox("panel") as StyleBoxFlat
	var dark_text: Color = card.message_label.get_theme_color("font_color")
	_check(bool(card.call("is_dark_mode")), "dark-mode state was not preserved")
	_check(light_style != null and dark_style != null and not light_style.bg_color.is_equal_approx(dark_style.bg_color), "light and dark card surfaces are indistinguishable")
	_check(not light_text.is_equal_approx(dark_text), "light and dark message colors are indistinguishable")
	card.call("set_dark_mode", false)

	card.primary_action_button.emit_signal("pressed")
	card.close_button.emit_signal("pressed")
	_check(_primary_requests == 1, "primary action did not emit exactly once")
	_check(_dismiss_requests == 1, "dismiss action did not emit exactly once")

	var safe_click := card.get_global_rect().position + Vector2(112, 92)
	_push_click(safe_click)
	await process_frame
	await process_frame
	_check(_background_presses == 0, "dialogue card click passed through to the map")

	card.call("set_content", "黃建宏", "商人", "只是來向市長問好。", "", portrait, "")
	await process_frame
	_check(not card._status_chip.visible, "empty petition status did not collapse its hint")
	_check(not card.primary_action_button.visible, "empty primary action did not collapse its button")
	_check(card.message_label.text == "只是來向市長問好。", "content refresh did not update the exposed message_label")

	card.queue_free()
	stage.queue_free()
	if _failed:
		quit(1)
	else:
		print("NPC dialogue card test passed. Width=%d Primary=%d Dismiss=%d MapPresses=%d" % [card.custom_minimum_size.x, _primary_requests, _dismiss_requests, _background_presses])
		quit(0)


func _push_click(position: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.pressed = true
	down.position = position
	down.global_position = position
	root.push_input(down, true)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.button_mask = 0
	up.pressed = false
	up.position = position
	up.global_position = position
	root.push_input(up, true)


func _on_background_pressed() -> void:
	_background_presses += 1


func _on_primary_requested() -> void:
	_primary_requests += 1


func _on_dismiss_requested() -> void:
	_dismiss_requests += 1


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("NPC dialogue card test failed: %s" % message)
