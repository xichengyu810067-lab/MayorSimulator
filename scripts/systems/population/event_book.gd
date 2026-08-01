class_name MayorEventBook
extends RefCounted

## Append-only major resident events. Sequence numbers give a stable replay order.

const SCHEMA_VERSION := 1

var next_sequence: int = 1
var events: Array[Dictionary] = []


func append(
	game_day: int,
	event_type: String,
	subject_id: String,
	reason_tag: String,
	data: Dictionary = {}
) -> Dictionary:
	var event := {
		"sequence": next_sequence,
		"game_day": game_day,
		"event_type": event_type,
		"subject_id": subject_id,
		"reason_tag": reason_tag,
		"data": data.duplicate(true),
	}
	next_sequence += 1
	events.append(event)
	return event.duplicate(true)


func events_for_subject(subject_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in events:
		if str(event.get("subject_id", "")) == subject_id:
			result.append(event.duplicate(true))
	return result


func to_dict() -> Dictionary:
	var serialized_events: Array[Dictionary] = []
	for event: Dictionary in events:
		serialized_events.append(event.duplicate(true))
	return {
		"schema_version": SCHEMA_VERSION,
		"next_sequence": next_sequence,
		"events": serialized_events,
	}


static func from_dict(data: Dictionary):
	var book = new()
	book.next_sequence = maxi(1, int(data.get("next_sequence", 1)))
	var source_events: Array = data.get("events", [])
	for value: Variant in source_events:
		if value is Dictionary:
			book.events.append(Dictionary(value).duplicate(true))
	return book
