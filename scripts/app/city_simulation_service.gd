class_name CitySimulationService
extends RefCounted

## Pure city-simulation calculations used by the application shell.
##
## The service owns no UI nodes, save paths, clocks, or mutable game state. It
## returns values or metric patches so CityState remains the only runtime writer
## of authoritative city metrics.

const METRIC_EFFECT_KEYS := [
	"security",
	"environment",
	"traffic",
	"education",
	"healthcare",
	"satisfaction",
]

const HEALTHCARE_SERVICE_MODEL_VERSION := "simplified_access_capacity_v1"


static func compose_month_settlement(
	tax_revenues: Dictionary,
	business_income: int,
	industrial_income: int,
	utility_income: int,
	service_income: int,
	maintenance: int,
	policy_expense: int,
	law_expense: int
) -> Dictionary:
	var tax_income := sum_int_values(tax_revenues)
	var income_entries := {
		"tax": tax_income,
		"business": business_income,
		"industry": industrial_income,
		"utility": utility_income,
		"service": service_income,
	}
	var expense_entries := {
		"policy": policy_expense,
		"law": law_expense,
	}
	return {
		"tax_income": tax_income,
		"business_income": business_income,
		"industrial_income": industrial_income,
		"utility_income": utility_income,
		"service_income": service_income,
		"maintenance": maintenance,
		"policy_expense": policy_expense,
		"law_expense": law_expense,
		"income_entries": income_entries,
		"expense_entries": expense_entries,
		"income": sum_int_values(income_entries),
		"expense": maintenance + sum_int_values(expense_entries),
	}


static func tax_revenues(
	resident_income_base: float,
	population: int,
	commercial_base: int,
	industrial_base: int,
	tax_rates: Dictionary
) -> Dictionary:
	var consumption_base := population * 14.0 + commercial_base * 0.30
	return {
		"income": int(round(resident_income_base * float(tax_rates.get("income", 0)) / 100.0)),
		"consumption": int(round(consumption_base * float(tax_rates.get("consumption", 0)) / 100.0)),
		"business": int(round(commercial_base * float(tax_rates.get("business", 0)) / 100.0)),
		"industry": int(round(industrial_base * float(tax_rates.get("industry", 0)) / 100.0)),
	}


static func base_income(building_source: Variant, buildings: Dictionary, income_key: String) -> int:
	var income := 0
	for record: Dictionary in active_building_records(building_source):
		var building_name := str(record.get("building_name", ""))
		var definition_variant: Variant = buildings.get(building_name, {})
		if definition_variant is Dictionary:
			income += int((definition_variant as Dictionary).get(income_key, 0))
	return income


static func business_income(
	commercial_base: int,
	commercial_policy_active: bool,
	law_bonus: float,
	business_activity_factor: float,
	consumption_activity_factor: float
) -> int:
	var income := commercial_base
	if commercial_policy_active:
		income = int(round(income * 1.25))
	income = int(round(income * (1.0 + law_bonus)))
	income = int(round(income * business_activity_factor))
	income = int(round(income * consumption_activity_factor))
	return income


static func industrial_income(
	industrial_base: int,
	industry_activity_factor: float,
	law_bonus: float
) -> int:
	var income := int(round(industrial_base * industry_activity_factor))
	return int(round(income * (1.0 + law_bonus)))


static func tax_activity_factor(rate: int, reasonable: int) -> float:
	var ratio := float(rate) / maxf(1.0, float(reasonable))
	if ratio > 2.0:
		return 0.78
	if ratio > 1.5:
		return 0.88
	if ratio < 0.5:
		return 1.04
	return 1.0


static func utility_revenues(
	population: int,
	building_source: Variant,
	buildings: Dictionary,
	utility_fees: Dictionary,
	utility_definitions: Dictionary
) -> Dictionary:
	var revenues: Dictionary = {}
	for fee_key_variant: Variant in utility_definitions.keys():
		var fee_key := str(fee_key_variant)
		var base_units := utility_base_units(fee_key, population, building_source)
		revenues[fee_key] = utility_fee_income(
			fee_key,
			base_units,
			building_source,
			buildings,
			utility_fees,
			utility_definitions
		)
	return revenues


static func utility_base_units(fee_key: String, population: int, building_source: Variant) -> float:
	if fee_key == "garbage":
		return population * 0.55 + building_count(building_source, "商店") * 20 + building_count(building_source, "大型商場") * 45
	if fee_key == "water":
		return population * 0.70
	if fee_key == "electricity":
		return population * 0.58 + building_count(building_source, "商店") * 28 + building_count(building_source, "大型商場") * 70 + building_count(building_source, "工廠") * 80
	if fee_key == "gas":
		return population * 0.45 + building_count(building_source, "大型商場") * 30
	return 0.0


static func utility_fee_income(
	fee_key: String,
	base_units: float,
	building_source: Variant,
	buildings: Dictionary,
	utility_fees: Dictionary,
	utility_definitions: Dictionary
) -> float:
	var definition: Dictionary = utility_definitions.get(fee_key, {})
	var efficiency := 0.62
	if building_count(building_source, str(definition.get("building", ""))) > 0:
		efficiency = 1.0
	efficiency += utility_efficiency_bonus(fee_key, building_source, buildings)
	return base_units * float(utility_fees.get(fee_key, 0)) * efficiency / 10.0


static func utility_efficiency_bonus(fee_key: String, building_source: Variant, buildings: Dictionary) -> float:
	var bonus := 0.0
	for record: Dictionary in active_building_records(building_source):
		var building_name := str(record.get("building_name", ""))
		var definition_variant: Variant = buildings.get(building_name, {})
		if not definition_variant is Dictionary:
			continue
		var efficiency_variant: Variant = (definition_variant as Dictionary).get("utility_efficiency", {})
		if efficiency_variant is Dictionary:
			bonus += float((efficiency_variant as Dictionary).get(fee_key, 0.0))
	return bonus


static func service_revenues(
	population: int,
	building_source: Variant,
	service_fees: Dictionary,
	service_definitions: Dictionary
) -> Dictionary:
	var revenues: Dictionary = {}
	for service_key_variant: Variant in service_definitions.keys():
		var service_key := str(service_key_variant)
		revenues[service_key] = service_fee_income(
			service_key,
			population,
			building_source,
			service_fees,
			service_definitions
		)
	return revenues


static func service_fee_income(
	service_key: String,
	population: int,
	building_source: Variant,
	service_fees: Dictionary,
	service_definitions: Dictionary
) -> int:
	var definition: Dictionary = service_definitions.get(service_key, {})
	var count := building_count(building_source, str(definition.get("building", "")))
	if count <= 0:
		return 0
	var uses := float(definition.get("base_uses", 0.0)) * count
	if service_key == "tuition":
		uses = population * float(definition.get("base_uses", 0.0)) * count
	else:
		uses += population * 0.08 * count
	var fee := int(service_fees.get(service_key, 0))
	var demand_factor := _service_fee_demand_factor(fee, definition)
	return int(round(uses * float(fee) * demand_factor))


## Evaluates healthcare from authoritative building, road, durability, and
## maintenance inputs. The result contains only JSON-safe scalar values so the
## application layer can persist or compare it without introducing aliases.
static func healthcare_service_result(input: Dictionary) -> Dictionary:
	var demand := maxi(0, int(input.get("population", input.get("demand", 0))))
	var capacity_per_facility := maxi(0, int(input.get("capacity_per_facility", 0)))
	var max_metric_bonus := maxi(0, int(input.get("max_metric_bonus", 0)))
	var durability_records: Dictionary = (
		input.get("durability_records", {})
		if input.get("durability_records", {}) is Dictionary
		else {}
	)
	var access_tiles := _healthcare_access_tile_set(input.get("road_access_components", []))
	var facilities := _healthcare_facility_records(input.get("building_records", {}))
	var active_facility_count := facilities.size()
	if active_facility_count == 0:
		return _healthcare_result(
			"unavailable", "facility_missing", 0, 0, 0, demand, 0, 0.0, 0
		)

	var accessible_facilities: Array[Dictionary] = []
	for facility: Dictionary in facilities:
		var tile_index := int(facility.get("tile_index", facility.get("tile_id", -1)))
		if access_tiles.has(tile_index):
			accessible_facilities.append(facility)
	if accessible_facilities.is_empty():
		return _healthcare_result(
			"unavailable", "road_missing", active_facility_count, 0, 0, demand, 0, 0.0, 0
		)

	var maintenance_ready := (
		bool(input.get("maintenance_enabled", true))
		and int(input.get("unpaid_maintenance_months", 0)) == 0
	)
	if not maintenance_ready:
		return _healthcare_result(
			"unavailable", "maintenance_unfunded", active_facility_count,
			accessible_facilities.size(), 0, demand, 0, 0.0, 0
		)

	var operational_facility_count := 0
	var effective_capacity := 0
	for facility: Dictionary in accessible_facilities:
		var efficiency := _healthcare_facility_efficiency(facility, durability_records)
		if efficiency <= 0.0:
			continue
		operational_facility_count += 1
		effective_capacity += int(round(float(capacity_per_facility) * efficiency))
	var served := mini(demand, effective_capacity)
	var coverage := 1.0 if demand == 0 and operational_facility_count > 0 else 0.0
	if demand > 0:
		coverage = clampf(float(served) / float(demand), 0.0, 1.0)
	var metric_bonus := int(round(float(max_metric_bonus) * coverage))
	var reason_code := "operational" if served >= demand and operational_facility_count > 0 else "capacity_shortfall"
	var status := "operational" if reason_code == "operational" else "degraded"
	return _healthcare_result(
		status,
		reason_code,
		active_facility_count,
		accessible_facilities.size(),
		operational_facility_count,
		demand,
		served,
		coverage,
		metric_bonus,
		effective_capacity
	)


## Calculates medical-service income from facilities that passed the healthcare
## gates and the residents actually served. Other service_fee_income callers
## retain their legacy city-grid API and formulas.
static func medical_service_revenue(
	population: int,
	fee: int,
	service_definition: Dictionary,
	result: Dictionary
) -> int:
	var reason_code := str(result.get("reason_code", ""))
	if reason_code not in ["operational", "capacity_shortfall"]:
		return 0
	var operational_facility_count := maxi(
		0,
		int(result.get("operational_facility_count", result.get("count", 0)))
	)
	var served := mini(maxi(0, population), maxi(0, int(result.get("served", 0))))
	if operational_facility_count <= 0 or served <= 0 or fee <= 0:
		return 0
	var uses := float(service_definition.get("base_uses", 0.0)) * operational_facility_count
	uses += float(served) * 0.08
	return int(round(
		uses
		* float(fee)
		* _service_fee_demand_factor(fee, service_definition)
	))


static func _healthcare_facility_records(building_records_value: Variant) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	if building_records_value is Dictionary:
		var building_records: Dictionary = building_records_value
		var building_ids: Array = building_records.keys()
		building_ids.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		for building_id_variant: Variant in building_ids:
			var record_value: Variant = building_records[building_id_variant]
			if not record_value is Dictionary:
				continue
			var record: Dictionary = (record_value as Dictionary).duplicate(true)
			if not record.has("building_id"):
				record["building_id"] = str(building_id_variant)
			if _is_active_healthcare_facility(record):
				records.append(record)
	elif building_records_value is Array:
		for record_value: Variant in building_records_value:
			if record_value is Dictionary and _is_active_healthcare_facility(record_value as Dictionary):
				records.append((record_value as Dictionary).duplicate(true))
		records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var a_id := str(a.get("building_id", ""))
			var b_id := str(b.get("building_id", ""))
			if a_id == b_id:
				return int(a.get("tile_index", a.get("tile_id", -1))) < int(b.get("tile_index", b.get("tile_id", -1)))
			return a_id < b_id
		)
	return records


static func _is_active_healthcare_facility(record: Dictionary) -> bool:
	var definition_id := str(record.get("definition_id", "")).to_lower()
	var building_name := str(record.get("building_name", ""))
	if definition_id != "hospital" and building_name != "醫院":
		return false
	return str(record.get("status", "active")) not in ["scrapped", "demolition"]


static func _healthcare_access_tile_set(components_value: Variant) -> Dictionary:
	var components: Array = []
	if components_value is Array:
		components = components_value
	elif components_value is Dictionary:
		var component_map: Dictionary = components_value
		var component_ids: Array = component_map.keys()
		component_ids.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		for component_id: Variant in component_ids:
			components.append(component_map[component_id])
	var tiles: Dictionary = {}
	for component_value: Variant in components:
		if not component_value is Dictionary:
			continue
		var tile_ids_value: Variant = (component_value as Dictionary).get("access_tile_ids", [])
		if tile_ids_value is Array:
			for tile_id_value: Variant in tile_ids_value:
				tiles[int(tile_id_value)] = true
		elif tile_ids_value is PackedInt32Array:
			for tile_id: int in tile_ids_value:
				tiles[tile_id] = true
		elif tile_ids_value is PackedInt64Array:
			for tile_id: int in tile_ids_value:
				tiles[tile_id] = true
	return tiles


static func _healthcare_facility_efficiency(
	facility: Dictionary,
	durability_records: Dictionary
) -> float:
	var building_id := str(facility.get("building_id", facility.get("id", "")))
	var durability_value: Variant = durability_records.get(building_id, {})
	var durability_record: Dictionary = durability_value if durability_value is Dictionary else {}
	if str(durability_record.get("status", "active")) == "scrapped":
		return 0.0
	if durability_record.has("efficiency"):
		return clampf(float(durability_record.get("efficiency", 0.0)), 0.0, 1.0)
	var durability := clampi(
		int(durability_record.get("durability", facility.get("durability", 100))),
		0,
		100
	)
	if durability >= 90:
		return 1.0
	if durability >= 80:
		return 0.8
	if durability >= 60:
		return 0.6
	if durability >= 40:
		return 0.4
	return 0.0


static func _healthcare_result(
	status: String,
	reason_code: String,
	facility_count: int,
	road_accessible_facility_count: int,
	operational_facility_count: int,
	demand: int,
	served: int,
	coverage: float,
	metric_bonus: int,
	capacity: int = 0
) -> Dictionary:
	return {
		"model_version": HEALTHCARE_SERVICE_MODEL_VERSION,
		"status": status,
		"reason_code": reason_code,
		"count": operational_facility_count,
		"facility_count": facility_count,
		"road_accessible_facility_count": road_accessible_facility_count,
		"operational_facility_count": operational_facility_count,
		"capacity": capacity,
		"demand": demand,
		"served": served,
		"coverage": coverage,
		"metric_bonus": metric_bonus,
	}


static func _service_fee_demand_factor(fee: int, definition: Dictionary) -> float:
	var ratio := float(fee) / maxf(1.0, float(definition.get("reasonable", 1)))
	if ratio > 1.75:
		return 0.58
	if ratio > 1.25:
		return 0.78
	if ratio < 0.5:
		return 1.18
	return 1.0


static func maintenance_cost(building_source: Variant, buildings: Dictionary) -> int:
	return base_income(building_source, buildings, "maintenance")


static func policy_expense(policies: Dictionary, active_policies: Dictionary) -> int:
	var total := 0
	for policy_name_variant: Variant in active_policies.keys():
		var policy_name := str(policy_name_variant)
		if bool(active_policies.get(policy_name, false)):
			var definition_variant: Variant = policies.get(policy_name, {})
			if definition_variant is Dictionary:
				total += int((definition_variant as Dictionary).get("expense", 0))
	return total


static func metric_effect_patch(current_metrics: Dictionary, effects: Dictionary, direction: int = 1) -> Dictionary:
	var patch: Dictionary = {}
	for metric_name: String in METRIC_EFFECT_KEYS:
		var source_key := "satisfaction" if metric_name == "satisfaction" else metric_name
		var current := int(current_metrics.get(metric_name, 0))
		patch[metric_name] = clamp_score(current + direction * int(effects.get(source_key, 0)))
	return patch


static func monthly_policy_metric_patch(
	current_metrics: Dictionary,
	policies: Dictionary,
	active_policies: Dictionary
) -> Dictionary:
	var patch := current_metrics.duplicate(true)
	var deltas := monthly_policy_metric_deltas(policies, active_policies)
	for metric_name: String in METRIC_EFFECT_KEYS:
		patch[metric_name] = clamp_score(
			int(patch.get(metric_name, 0)) + int(deltas.get(metric_name, 0))
		)
	return _metric_subset(patch)


static func monthly_policy_metric_deltas(
	policies: Dictionary,
	active_policies: Dictionary
) -> Dictionary:
	var deltas: Dictionary = {}
	for metric_name: String in METRIC_EFFECT_KEYS:
		deltas[metric_name] = 0
	for policy_name_variant: Variant in active_policies.keys():
		var policy_name := str(policy_name_variant)
		if not bool(active_policies.get(policy_name, false)):
			continue
		var policy_variant: Variant = policies.get(policy_name, {})
		if not policy_variant is Dictionary:
			continue
		var policy: Dictionary = policy_variant
		for metric_name: String in ["security", "environment", "traffic", "education", "satisfaction"]:
			deltas[metric_name] = int(deltas.get(metric_name, 0)) + int(policy.get(metric_name, 0))
	return deltas


static func city_pressure_metric_patch(
	current_metrics: Dictionary,
	population: int,
	building_source: Variant
) -> Dictionary:
	var deltas := city_pressure_metric_deltas(population, building_source)
	var patch: Dictionary = {}
	for metric_name: String in METRIC_EFFECT_KEYS:
		if deltas.has(metric_name):
			patch[metric_name] = clamp_score(
				int(current_metrics.get(metric_name, 0)) + int(deltas[metric_name])
			)
	return patch


static func city_pressure_metric_deltas(
	population: int,
	building_source: Variant
) -> Dictionary:
	var shops := building_count(building_source, "商店")
	var malls := building_count(building_source, "大型商場")
	var homes := building_count(building_source, "住宅")
	var factories := building_count(building_source, "工廠")
	return {
		"traffic": -shops - malls * 2,
		"environment": -int(shops / 2) - factories * 2,
		"security": -int(max(0, population - 120) / 160),
		"satisfaction": 1 if homes > 0 else 0,
	}


static func satisfaction_result(
	current_metrics: Dictionary,
	tax_rates: Dictionary,
	tax_definitions: Dictionary,
	utility_fees: Dictionary,
	utility_definitions: Dictionary,
	service_fees: Dictionary,
	service_definitions: Dictionary,
	building_source: Variant,
	policies: Dictionary,
	active_policies: Dictionary,
	law_utility_relief: float
) -> Dictionary:
	var resident_tax_score := clamp_score(100 - int(tax_rates.get("income", 0)) * 3 - int(tax_rates.get("consumption", 0)) * 2)
	var merchant_tax_score := clamp_score(100 - int(tax_rates.get("business", 0)) * 3 - int(tax_rates.get("consumption", 0)) * 2)
	var utility_penalty := utility_satisfaction_penalty(utility_fees, utility_definitions, building_source)
	utility_penalty += service_satisfaction_penalty(service_fees, service_definitions)
	var business_score := clamp_score(
		48
		+ building_count(building_source, "商店") * 12
		+ building_count(building_source, "大型商場") * 18
		+ (14 if bool(active_policies.get("商業振興", false)) else 0)
	)
	var satisfaction := int(current_metrics.get("satisfaction", 0))
	var groups := {
		"一般居民": average_int([resident_tax_score, int(current_metrics.get("security", 0)), int(current_metrics.get("healthcare", 0)), int(current_metrics.get("environment", 0))]),
		"學生家庭": average_int([int(current_metrics.get("education", 0)), int(current_metrics.get("healthcare", 0)), int(current_metrics.get("environment", 0)), satisfaction]),
		"商人": average_int([merchant_tax_score, business_score, int(current_metrics.get("traffic", 0))]),
		"老年居民": average_int([int(current_metrics.get("healthcare", 0)), int(current_metrics.get("security", 0)), int(current_metrics.get("environment", 0)), satisfaction]),
	}
	var policy_bonus := 0
	for policy_name_variant: Variant in active_policies.keys():
		var policy_name := str(policy_name_variant)
		if not bool(active_policies.get(policy_name, false)):
			continue
		var definition_variant: Variant = policies.get(policy_name, {})
		if definition_variant is Dictionary:
			policy_bonus += int((definition_variant as Dictionary).get("satisfaction", 0))
	var tax_penalty := 0
	var pressure := tax_pressure_score(tax_rates, tax_definitions)
	if pressure <= 40:
		tax_penalty = 3
	elif pressure >= 82:
		tax_penalty = -10
	elif pressure >= 60:
		tax_penalty = -5
	return {
		"group_satisfaction": groups,
		"satisfaction": clamp_score(average_int(groups.values()) + policy_bonus + tax_penalty - utility_penalty + law_utility_relief),
	}


static func score_result(
	current_metrics: Dictionary,
	funds: int,
	population: int,
	building_score_bonus: int,
	tax_pressure: int,
	previous_best_score: int
) -> Dictionary:
	var fiscal_score := 55
	if funds >= 12000:
		fiscal_score = 90
	elif funds >= 5000:
		fiscal_score = 75
	elif funds >= 0:
		fiscal_score = 55
	else:
		fiscal_score = 20
	var population_score := clampi(int(population / 3), 0, 100)
	var score := average_int([
		int(current_metrics.get("satisfaction", 0)),
		fiscal_score,
		population_score,
		int(current_metrics.get("environment", 0)),
		int(current_metrics.get("security", 0)),
		int(current_metrics.get("education", 0)),
		int(current_metrics.get("healthcare", 0)),
	])
	score += building_score_bonus
	if tax_pressure > 82:
		score -= 8
	if funds < 0:
		score -= 15
	var ranking_score := clamp_score(score)
	return {
		"ranking_score": ranking_score,
		"best_score": max(previous_best_score, ranking_score),
		"city_rating": rating_for_score(ranking_score),
	}


static func tax_pressure_score(tax_rates: Dictionary, tax_definitions: Dictionary) -> int:
	var income_pressure := float(tax_rates.get("income", 0)) / float(tax_definitions.get("income", {}).get("max", 1)) * 100.0
	var consumption_pressure := float(tax_rates.get("consumption", 0)) / float(tax_definitions.get("consumption", {}).get("max", 1)) * 100.0
	var business_pressure := float(tax_rates.get("business", 0)) / float(tax_definitions.get("business", {}).get("max", 1)) * 100.0
	var industry_pressure := float(tax_rates.get("industry", 0)) / float(tax_definitions.get("industry", {}).get("max", 1)) * 100.0
	return int(round(income_pressure * 0.38 + consumption_pressure * 0.24 + business_pressure * 0.20 + industry_pressure * 0.18))


static func utility_satisfaction_penalty(
	utility_fees: Dictionary,
	utility_definitions: Dictionary,
	building_source: Variant
) -> int:
	var penalty := 0
	for fee_key_variant: Variant in utility_fees.keys():
		var fee_key := str(fee_key_variant)
		var definition: Dictionary = utility_definitions.get(fee_key, {})
		var ratio := float(utility_fees[fee_key]) / maxf(1.0, float(definition.get("reasonable", 1)))
		if ratio > 1.75:
			penalty += 7
		elif ratio > 1.25:
			penalty += 3
		elif ratio < 0.45:
			penalty -= 1
		if building_count(building_source, str(definition.get("building", ""))) == 0 and ratio > 1.0:
			penalty += 2
	return max(0, penalty)


static func service_satisfaction_penalty(service_fees: Dictionary, service_definitions: Dictionary) -> int:
	var penalty := 0
	for service_key_variant: Variant in service_fees.keys():
		var service_key := str(service_key_variant)
		var definition: Dictionary = service_definitions.get(service_key, {})
		var ratio := float(service_fees[service_key]) / maxf(1.0, float(definition.get("reasonable", 1)))
		if ratio > 1.75:
			penalty += 3
		elif ratio > 1.25:
			penalty += 1
		elif ratio < 0.5:
			penalty -= 1
	return max(0, penalty)


static func migration_pressure(
	tax_pressure: int,
	current_metrics: Dictionary,
	utility_fees: Dictionary,
	utility_definitions: Dictionary,
	service_fees: Dictionary,
	service_definitions: Dictionary
) -> int:
	var pressure := 0
	if tax_pressure > 82:
		pressure += 4
	if int(current_metrics.get("satisfaction", 0)) < 40:
		pressure += 5
	for metric_name: String in ["environment", "traffic", "security"]:
		if int(current_metrics.get(metric_name, 0)) < 40:
			pressure += 3
	for fee_key_variant: Variant in utility_fees.keys():
		var fee_key := str(fee_key_variant)
		if float(utility_fees[fee_key]) > float(utility_definitions.get(fee_key, {}).get("reasonable", 0)) * 1.75:
			pressure += 2
	for service_key_variant: Variant in service_fees.keys():
		var service_key := str(service_key_variant)
		if float(service_fees[service_key]) > float(service_definitions.get(service_key, {}).get("reasonable", 0)) * 1.75:
			pressure += 1
	return pressure


static func migration_reason(
	tax_rates: Dictionary,
	tax_definitions: Dictionary,
	utility_fees: Dictionary,
	utility_definitions: Dictionary,
	service_fees: Dictionary,
	service_definitions: Dictionary,
	current_metrics: Dictionary
) -> String:
	var reasons: Array[String] = []
	for tax_key_variant: Variant in tax_rates.keys():
		var tax_key := str(tax_key_variant)
		var definition: Dictionary = tax_definitions.get(tax_key, {})
		if float(tax_rates[tax_key]) > float(definition.get("reasonable", 0)) * 1.8:
			reasons.append("高%s" % str(definition.get("name", tax_key)))
	for fee_key_variant: Variant in utility_fees.keys():
		var fee_key := str(fee_key_variant)
		var definition: Dictionary = utility_definitions.get(fee_key, {})
		if float(utility_fees[fee_key]) > float(definition.get("reasonable", 0)) * 1.75:
			reasons.append("高%s" % str(definition.get("name", fee_key)))
	for service_key_variant: Variant in service_fees.keys():
		var service_key := str(service_key_variant)
		var definition: Dictionary = service_definitions.get(service_key, {})
		if float(service_fees[service_key]) > float(definition.get("reasonable", 0)) * 1.75:
			reasons.append("高%s" % str(definition.get("name", service_key)))
	if int(current_metrics.get("environment", 0)) < 40:
		reasons.append("環境惡化")
	if int(current_metrics.get("traffic", 0)) < 40:
		reasons.append("交通不佳")
	if int(current_metrics.get("security", 0)) < 40:
		reasons.append("治安不佳")
	if reasons.is_empty():
		return "公共事業費用或城市條件造成部分居民搬離。"
	return "%s造成居民不滿，人口下降。" % "與".join(reasons)


static func average_utility_fee_ratio(utility_fees: Dictionary, utility_definitions: Dictionary) -> float:
	if utility_fees.is_empty():
		return 0.0
	var total := 0.0
	for fee_key_variant: Variant in utility_fees.keys():
		var fee_key := str(fee_key_variant)
		total += float(utility_fees[fee_key]) / maxf(1.0, float(utility_definitions.get(fee_key, {}).get("reasonable", 1)))
	return total / utility_fees.size()


static func infrastructure_warnings(
	utility_fees: Dictionary,
	utility_definitions: Dictionary,
	building_source: Variant
) -> Array[String]:
	var warnings: Array[String] = []
	for fee_key_variant: Variant in utility_fees.keys():
		var fee_key := str(fee_key_variant)
		var definition: Dictionary = utility_definitions.get(fee_key, {})
		if (
			int(utility_fees[fee_key]) > int(definition.get("reasonable", 0))
			and building_count(building_source, str(definition.get("building", ""))) == 0
		):
			warnings.append("%s收費偏高，但缺少%s，基礎設施評價下降。" % [definition.get("name", fee_key), definition.get("building", "")])
	return warnings


static func prioritized_metric_specs(specs: Array[Dictionary], current_metrics: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for spec: Dictionary in specs:
		result.append(spec.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_id := str(a.get("id", ""))
		var b_id := str(b.get("id", ""))
		var a_value := int(current_metrics.get(a_id, 0))
		var b_value := int(current_metrics.get(b_id, 0))
		if a_value == b_value:
			return a_id < b_id
		return a_value < b_value
	)
	return result


static func building_count(building_source: Variant, building_name: String) -> int:
	var count := 0
	for record: Dictionary in active_building_records(building_source):
		if str(record.get("building_name", "")) == building_name:
			count += 1
	return count


static func building_score_bonus(building_source: Variant, buildings: Dictionary) -> int:
	return base_income(building_source, buildings, "score_bonus")


static func active_building_records(building_source: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if building_source is Dictionary:
		var source: Dictionary = building_source
		var record_ids: Array = source.keys()
		record_ids.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		for record_id_variant: Variant in record_ids:
			var record_value: Variant = source[record_id_variant]
			if not record_value is Dictionary:
				continue
			var record: Dictionary = (record_value as Dictionary).duplicate(true)
			if str(record.get("status", "active")) == "scrapped":
				continue
			if not record.has("building_id"):
				record["building_id"] = str(record_id_variant)
			if not str(record.get("building_name", "")).is_empty():
				result.append(record)
		return result
	if building_source is Array:
		var source_array: Array = building_source
		for tile_index: int in range(source_array.size()):
			var building_name := str(source_array[tile_index])
			if not building_name.is_empty():
				result.append({
					"building_id": "legacy_tile_%06d" % tile_index,
					"building_name": building_name,
					"status": "active",
				})
	return result


static func sum_int_values(values: Dictionary) -> int:
	var total := 0
	for value: Variant in values.values():
		total += int(value)
	return total


static func average_int(values: Array) -> int:
	if values.is_empty():
		return 0
	var total := 0.0
	for value: Variant in values:
		total += float(value)
	return int(round(total / values.size()))


static func clamp_score(value: Variant) -> int:
	return clampi(int(value), 0, 100)


static func rating_for_score(score: int) -> String:
	if score >= 90:
		return "S 級城市"
	if score >= 75:
		return "A 級城市"
	if score >= 60:
		return "B 級城市"
	if score >= 40:
		return "C 級城市"
	return "危機城市"


static func _metric_subset(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for metric_name: String in METRIC_EFFECT_KEYS:
		if source.has(metric_name):
			result[metric_name] = source[metric_name]
	return result
