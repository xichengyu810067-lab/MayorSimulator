extends Resource

@export var id: StringName
@export var display_name: String
@export var industry_tag: StringName
@export var base_income: int = 32000
@export var education_level: int = 1

func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"display_name": display_name,
		"industry_tag": String(industry_tag),
		"base_income": base_income,
		"education_level": education_level
	}
