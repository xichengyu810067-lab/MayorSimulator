extends Resource

@export var id: StringName
@export var display_name: String
@export var compatible_categories: Array[StringName] = []
@export_range(0.0, 1.0, 0.05) var mismatch_efficiency: float = 0.8

func accepts(category_id: StringName) -> bool:
	return compatible_categories.has(category_id)

func to_dict() -> Dictionary:
	var categories: Array[String] = []
	for category in compatible_categories:
		categories.append(String(category))
	return {
		"id": String(id),
		"display_name": display_name,
		"compatible_categories": categories,
		"mismatch_efficiency": mismatch_efficiency
	}
