extends RefCounted

## Append-only fact produced by the simulation kernel. `reason_tag` is
## mandatory for state-changing events so the UI and audit tools can explain
## why a value changed.

var sequence: int
var event_type: String
var game_time: int
var subject_id: String
var value_delta: Variant
var reason_tag: String
var payload: Dictionary
var caused_by: String


func _init(
		p_sequence: int = 0,
		p_event_type: String = "",
		p_game_time: int = 0,
		p_subject_id: String = "",
		p_value_delta: Variant = null,
		p_reason_tag: String = "unspecified",
		p_payload: Dictionary = {},
		p_caused_by: String = ""
) -> void:
	sequence = p_sequence
	event_type = p_event_type
	game_time = p_game_time
	subject_id = p_subject_id
	value_delta = p_value_delta
	reason_tag = p_reason_tag if not p_reason_tag.is_empty() else "unspecified"
	payload = p_payload.duplicate(true)
	caused_by = p_caused_by


func to_dict() -> Dictionary:
	return {
		"sequence": sequence,
		"event_type": event_type,
		"game_time": game_time,
		"subject_id": subject_id,
		"value_delta": value_delta,
		"reason_tag": reason_tag,
		"payload": payload.duplicate(true),
		"caused_by": caused_by,
	}


static func from_dict(data: Dictionary):
	return new(
		int(data.get("sequence", 0)),
		str(data.get("event_type", "")),
		int(data.get("game_time", 0)),
		str(data.get("subject_id", "")),
		data.get("value_delta"),
		str(data.get("reason_tag", "unspecified")),
		data.get("payload", {}) as Dictionary,
		str(data.get("caused_by", ""))
	)
