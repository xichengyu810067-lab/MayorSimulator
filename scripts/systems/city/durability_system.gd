class_name DurabilitySystem
extends RefCounted

## Owns building durability and the city-wide maintenance delinquency clock.

const SCHEMA_VERSION := 1
const MAX_DURABILITY := 100
const SCRAP_THRESHOLD := 40
const NATURAL_AGING_PER_YEAR := 1
const NEGLECT_MONTH_THRESHOLD := 3
const NEGLECT_DAMAGE_PER_WEEK := 10

var buildings: Dictionary = {}
var consecutive_unpaid_months: int = 0


static func efficiency_for(durability: int) -> float:
	if durability >= 90:
		return 1.0
	if durability >= 80:
		return 0.8
	if durability >= 60:
		return 0.6
	if durability >= SCRAP_THRESHOLD:
		return 0.4
	return 0.0


static func tier_for(durability: int) -> String:
	if durability >= 90:
		return "excellent"
	if durability >= 80:
		return "good"
	if durability >= 60:
		return "worn"
	if durability >= SCRAP_THRESHOLD:
		return "critical"
	return "scrapped"


func register_building(building_id: String, attributes: Dictionary = {}) -> Dictionary:
	if building_id.is_empty():
		return _error("missing_building_id")
	if buildings.has(building_id):
		return _error("building_already_registered")
	var durability := clampi(int(attributes.get("durability", MAX_DURABILITY)), 0, MAX_DURABILITY)
	var status := "scrapped" if durability < SCRAP_THRESHOLD else "active"
	var record := {
		"id": building_id,
		"durability": durability,
		"status": status,
		"tier": tier_for(durability),
		"efficiency": efficiency_for(durability),
		"material_value": maxi(0, int(attributes.get("material_value", 0))),
		"engineering_fee": maxi(0, int(attributes.get("engineering_fee", 0))),
		"last_damage_reason": "",
		"scrapped_day": int(attributes.get("scrapped_day", -1)),
		"metadata": attributes.get("metadata", {}).duplicate(true)
	}
	buildings[building_id] = record
	return {"ok": true, "building": record.duplicate(true)}


func unregister_building(building_id: String) -> Dictionary:
	if not buildings.has(building_id):
		return _error("building_not_found")
	var removed: Dictionary = buildings[building_id]
	buildings.erase(building_id)
	return {"ok": true, "building": removed.duplicate(true)}


func record_monthly_maintenance(paid_in_full: bool, game_day: int) -> Dictionary:
	if paid_in_full:
		consecutive_unpaid_months = 0
		return {
			"type": "maintenance_paid",
			"game_day": game_day,
			"reason_tag": "maintenance.citywide.paid",
			"payload": {"consecutive_unpaid_months": 0}
		}
	consecutive_unpaid_months += 1
	return {
		"type": "maintenance_unpaid",
		"game_day": game_day,
		"reason_tag": "maintenance.citywide.unpaid",
		"payload": {
			"consecutive_unpaid_months": consecutive_unpaid_months,
			"weekly_damage_active": consecutive_unpaid_months >= NEGLECT_MONTH_THRESHOLD
		}
	}


func advance_week(game_day: int) -> Array[Dictionary]:
	var emitted: Array[Dictionary] = []
	if consecutive_unpaid_months < NEGLECT_MONTH_THRESHOLD:
		return emitted
	for building_id in _sorted_string_keys(buildings):
		var building: Dictionary = buildings[building_id]
		if str(building.get("status", "")) == "scrapped":
			continue
		var result := apply_damage(
			building_id,
			NEGLECT_DAMAGE_PER_WEEK,
			"maintenance.neglect.weekly",
			game_day
		)
		if bool(result.get("ok", false)):
			emitted.append(result["event"])
	return emitted


func advance_year(game_day: int) -> Array[Dictionary]:
	var emitted: Array[Dictionary] = []
	for building_id in _sorted_string_keys(buildings):
		var building: Dictionary = buildings[building_id]
		if str(building.get("status", "")) == "scrapped":
			continue
		var result := apply_damage(
			building_id,
			NATURAL_AGING_PER_YEAR,
			"durability.natural_aging",
			game_day
		)
		if bool(result.get("ok", false)):
			emitted.append(result["event"])
	return emitted


func apply_damage(
	building_id: String,
	amount: int,
	reason_tag: String,
	game_day: int
) -> Dictionary:
	if not buildings.has(building_id):
		return _error("building_not_found")
	if amount <= 0:
		return _error("damage_must_be_positive")
	var building: Dictionary = buildings[building_id]
	if str(building.get("status", "")) == "scrapped":
		return _error("building_already_scrapped")
	var before := int(building.get("durability", MAX_DURABILITY))
	var after := clampi(before - amount, 0, MAX_DURABILITY)
	building["durability"] = after
	building["last_damage_reason"] = reason_tag
	building["tier"] = tier_for(after)
	building["efficiency"] = efficiency_for(after)
	var scrapped := after < SCRAP_THRESHOLD
	if scrapped:
		building["status"] = "scrapped"
		building["scrapped_day"] = game_day
	buildings[building_id] = building
	return {
		"ok": true,
		"event": {
			"type": "building_scrapped" if scrapped else "building_damaged",
			"subject_id": building_id,
			"game_day": game_day,
			"value_before": before,
			"value_after": after,
			"value_delta": after - before,
			"reason_tag": reason_tag,
			"payload": {
				"tier": building["tier"],
				"efficiency": building["efficiency"],
				"scrapped": scrapped
			}
		},
		"building": building.duplicate(true)
	}


func repair_quote(building_id: String) -> Dictionary:
	if not buildings.has(building_id):
		return _error("building_not_found")
	var building: Dictionary = buildings[building_id]
	if str(building.get("status", "")) == "scrapped":
		return _error("scrapped_building_requires_demolition")
	var lost_durability := MAX_DURABILITY - int(building.get("durability", MAX_DURABILITY))
	var material_component := int(ceil(
		float(lost_durability) / 100.0 * float(building.get("material_value", 0))
	))
	var engineering_component := int(building.get("engineering_fee", 0))
	return {
		"ok": true,
		"building_id": building_id,
		"lost_durability": lost_durability,
		"material_component": material_component,
		"engineering_component": engineering_component,
		"total_cost": material_component + engineering_component
	}


func repair(building_id: String, game_day: int) -> Dictionary:
	var quote := repair_quote(building_id)
	if not bool(quote.get("ok", false)):
		return quote
	var building: Dictionary = buildings[building_id]
	var before := int(building.get("durability", MAX_DURABILITY))
	building["durability"] = MAX_DURABILITY
	building["status"] = "active"
	building["tier"] = tier_for(MAX_DURABILITY)
	building["efficiency"] = efficiency_for(MAX_DURABILITY)
	building["last_repaired_day"] = game_day
	buildings[building_id] = building
	return {
		"ok": true,
		"cost": int(quote["total_cost"]),
		"building": building.duplicate(true),
		"event": {
			"type": "building_repaired",
			"subject_id": building_id,
			"game_day": game_day,
			"value_before": before,
			"value_after": MAX_DURABILITY,
			"value_delta": MAX_DURABILITY - before,
			"reason_tag": "durability.repair",
			"payload": {"cost": int(quote["total_cost"])}
		}
	}


func get_building(building_id: String) -> Dictionary:
	if not buildings.has(building_id):
		return {}
	return buildings[building_id].duplicate(true)


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"consecutive_unpaid_months": consecutive_unpaid_months,
		"buildings": buildings.duplicate(true)
	}


func load_dict(data: Dictionary) -> void:
	consecutive_unpaid_months = maxi(0, int(data.get("consecutive_unpaid_months", 0)))
	buildings = data.get("buildings", {}).duplicate(true)


static func create_from_dict(data: Dictionary) -> DurabilitySystem:
	var instance := DurabilitySystem.new()
	instance.load_dict(data)
	return instance


static func _sorted_string_keys(source: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key in source.keys():
		result.append(str(key))
	result.sort()
	return result


static func _error(code: String) -> Dictionary:
	return {"ok": false, "error": code}
