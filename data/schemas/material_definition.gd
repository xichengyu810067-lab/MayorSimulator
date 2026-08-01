extends Resource

@export var id: StringName
@export var display_name: String
@export_range(0.1, 5.0, 0.05) var workload_multiplier: float = 1.0
@export_range(0.1, 5.0, 0.05) var price_multiplier: float = 1.0
@export var material_value_per_size: int = 300
@export var theoretical_max_floors: int = 8

func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"display_name": display_name,
		"workload_multiplier": workload_multiplier,
		"price_multiplier": price_multiplier,
		"material_value_per_size": material_value_per_size,
		"theoretical_max_floors": theoretical_max_floors
	}
