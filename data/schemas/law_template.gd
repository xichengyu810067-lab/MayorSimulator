extends Resource

@export var id: StringName
@export var display_name: String
@export var category_id: StringName
@export var impact_level: int = 1
@export var description: String
@export var effects: Dictionary = {}
@export var debate_topic: String

func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"display_name": display_name,
		"category_id": String(category_id),
		"impact_level": impact_level,
		"description": description,
		"effects": effects.duplicate(true),
		"debate_topic": debate_topic
	}
