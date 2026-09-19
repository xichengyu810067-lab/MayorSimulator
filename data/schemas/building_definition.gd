extends Resource

@export var id: StringName
@export var display_name: String
@export var category_id: StringName
@export var base_cost: int
@export var monthly_maintenance: int
@export var base_workload: float
@export var housing_capacity: int = 0
@export var job_capacity: int = 0
@export var default_material_id: StringName = &"brick"
@export var core_acceptance: bool = false
@export var effects: Dictionary = {}
@export var description: String
@export var color: Color = Color.WHITE
@export var text_color: Color = Color.BLACK

func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"display_name": display_name,
		"category_id": String(category_id),
		"base_cost": base_cost,
		"monthly_maintenance": monthly_maintenance,
		"base_workload": base_workload,
		"housing_capacity": housing_capacity,
		"job_capacity": job_capacity,
		"default_material_id": String(default_material_id),
		"core_acceptance": core_acceptance,
		"effects": effects.duplicate(true),
		"description": description,
		"color": color.to_html(true),
		"text_color": text_color.to_html(true)
	}
