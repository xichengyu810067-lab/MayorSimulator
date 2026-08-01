class_name ModalPointerGuard
extends Control

const GUARD_NODE_NAME := "ModalPointerGuard"
const RELEASE_DISTANCE := 1.0

var _origin := Vector2.ZERO


func _init() -> void:
	name = GUARD_NODE_NAME
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	z_as_relative = false
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX


func arm(origin: Vector2) -> void:
	_origin = origin
	if get_parent() is Control:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		position = Vector2.ZERO
		size = get_viewport_rect().size
	show()
	move_to_front()


func _gui_input(event: InputEvent) -> void:
	accept_event()
	get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.position.distance_to(_origin) >= RELEASE_DISTANCE:
			queue_free()

