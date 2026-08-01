extends RefCounted

## Immutable-at-the-boundary request sent from a presentation layer to the
## simulation. Payloads are deep-copied so UI code cannot mutate a queued
## command after submission.

var operation_id: String
var command_type: String
var game_time: int
var payload: Dictionary
var ordinal: int


func _init(
		p_operation_id: String = "",
		p_command_type: String = "",
		p_game_time: int = 0,
		p_payload: Dictionary = {},
		p_ordinal: int = 0
) -> void:
	operation_id = p_operation_id
	command_type = p_command_type
	game_time = p_game_time
	payload = p_payload.duplicate(true)
	ordinal = p_ordinal


func to_dict() -> Dictionary:
	return {
		"operation_id": operation_id,
		"command_type": command_type,
		"game_time": game_time,
		"payload": payload.duplicate(true),
		"ordinal": ordinal,
	}


static func from_dict(data: Dictionary):
	return new(
		str(data.get("operation_id", "")),
		str(data.get("command_type", "")),
		int(data.get("game_time", 0)),
		data.get("payload", {}) as Dictionary,
		int(data.get("ordinal", 0))
	)
