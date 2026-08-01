extends Resource

@export var seconds_per_game_day: float = 30.0
@export var days_per_month: int = 30
@export var months_per_year: int = 12
@export var construction_worker_cap: int = 20
@export var low_worker_daily_wage: int = 2000
@export var high_worker_daily_wage: int = 2500
@export var high_worker_threshold: int = 6
@export var unpaid_maintenance_grace_months: int = 3
@export var weekly_neglect_damage: int = 10
@export var annual_aging_damage: int = 1
@export var scrap_threshold: int = 40
@export var initial_npc_count: int = 300
@export var maximum_npc_count: int = 500
@export var maximum_visible_npc_proxies: int = 80

func to_dict() -> Dictionary:
	return {
		"seconds_per_game_day": seconds_per_game_day,
		"days_per_month": days_per_month,
		"months_per_year": months_per_year,
		"construction_worker_cap": construction_worker_cap,
		"low_worker_daily_wage": low_worker_daily_wage,
		"high_worker_daily_wage": high_worker_daily_wage,
		"high_worker_threshold": high_worker_threshold,
		"unpaid_maintenance_grace_months": unpaid_maintenance_grace_months,
		"weekly_neglect_damage": weekly_neglect_damage,
		"annual_aging_damage": annual_aging_damage,
		"scrap_threshold": scrap_threshold,
		"initial_npc_count": initial_npc_count,
		"maximum_npc_count": maximum_npc_count,
		"maximum_visible_npc_proxies": maximum_visible_npc_proxies
	}
