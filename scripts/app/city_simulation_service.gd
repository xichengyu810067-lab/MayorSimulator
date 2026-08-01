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


static func base_income(city_grid: Array, buildings: Dictionary, income_key: String) -> int:
	var income := 0
	for building_variant: Variant in city_grid:
		var building_name := str(building_variant)
		if building_name.is_empty():
			continue
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
	city_grid: Array,
	buildings: Dictionary,
	utility_fees: Dictionary,
	utility_definitions: Dictionary
) -> Dictionary:
	var revenues: Dictionary = {}
	for fee_key_variant: Variant in utility_definitions.keys():
		var fee_key := str(fee_key_variant)
		var base_units := utility_base_units(fee_key, population, city_grid)
		revenues[fee_key] = utility_fee_income(
			fee_key,
			base_units,
			city_grid,
			buildings,
			utility_fees,
			utility_definitions
		)
	return revenues


static func utility_base_units(fee_key: String, population: int, city_grid: Array) -> float:
	if fee_key == "garbage":
		return population * 0.55 + building_count(city_grid, "商店") * 20 + building_count(city_grid, "大型商場") * 45
	if fee_key == "water":
		return population * 0.70
	if fee_key == "electricity":
		return population * 0.58 + building_count(city_grid, "商店") * 28 + building_count(city_grid, "大型商場") * 70 + building_count(city_grid, "工廠") * 80
	if fee_key == "gas":
		return population * 0.45 + building_count(city_grid, "大型商場") * 30
	return 0.0


static func utility_fee_income(
	fee_key: String,
	base_units: float,
	city_grid: Array,
	buildings: Dictionary,
	utility_fees: Dictionary,
	utility_definitions: Dictionary
) -> float:
	var definition: Dictionary = utility_definitions.get(fee_key, {})
	var efficiency := 0.62
	if building_count(city_grid, str(definition.get("building", ""))) > 0:
		efficiency = 1.0
	efficiency += utility_efficiency_bonus(fee_key, city_grid, buildings)
	return base_units * float(utility_fees.get(fee_key, 0)) * efficiency / 10.0


static func utility_efficiency_bonus(fee_key: String, city_grid: Array, buildings: Dictionary) -> float:
	var bonus := 0.0
	for building_variant: Variant in city_grid:
		var building_name := str(building_variant)
		if building_name.is_empty():
			continue
		var definition_variant: Variant = buildings.get(building_name, {})
		if not definition_variant is Dictionary:
			continue
		var efficiency_variant: Variant = (definition_variant as Dictionary).get("utility_efficiency", {})
		if efficiency_variant is Dictionary:
			bonus += float((efficiency_variant as Dictionary).get(fee_key, 0.0))
	return bonus


static func service_revenues(
	population: int,
	city_grid: Array,
	service_fees: Dictionary,
	service_definitions: Dictionary
) -> Dictionary:
	var revenues: Dictionary = {}
	for service_key_variant: Variant in service_definitions.keys():
		var service_key := str(service_key_variant)
		revenues[service_key] = service_fee_income(
			service_key,
			population,
			city_grid,
			service_fees,
			service_definitions
		)
	return revenues


static func service_fee_income(
	service_key: String,
	population: int,
	city_grid: Array,
	service_fees: Dictionary,
	service_definitions: Dictionary
) -> int:
	var definition: Dictionary = service_definitions.get(service_key, {})
	var count := building_count(city_grid, str(definition.get("building", "")))
	if count <= 0:
		return 0
	var uses := float(definition.get("base_uses", 0.0)) * count
	if service_key == "tuition":
		uses = population * float(definition.get("base_uses", 0.0)) * count
	else:
		uses += population * 0.08 * count
	var fee := int(service_fees.get(service_key, 0))
	var ratio := float(fee) / maxf(1.0, float(definition.get("reasonable", 1)))
	var demand_factor := 1.0
	if ratio > 1.75:
		demand_factor = 0.58
	elif ratio > 1.25:
		demand_factor = 0.78
	elif ratio < 0.5:
		demand_factor = 1.18
	return int(round(uses * float(fee) * demand_factor))


static func maintenance_cost(city_grid: Array, buildings: Dictionary) -> int:
	return base_income(city_grid, buildings, "maintenance")


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
	for policy_name_variant: Variant in active_policies.keys():
		var policy_name := str(policy_name_variant)
		if not bool(active_policies.get(policy_name, false)):
			continue
		var policy_variant: Variant = policies.get(policy_name, {})
		if not policy_variant is Dictionary:
			continue
		var policy: Dictionary = policy_variant
		for metric_name: String in ["security", "environment", "traffic", "education", "satisfaction"]:
			patch[metric_name] = clamp_score(int(patch.get(metric_name, 0)) + int(policy.get(metric_name, 0)))
	return _metric_subset(patch)


static func city_pressure_metric_patch(
	current_metrics: Dictionary,
	population: int,
	city_grid: Array
) -> Dictionary:
	var shops := building_count(city_grid, "商店")
	var malls := building_count(city_grid, "大型商場")
	var homes := building_count(city_grid, "住宅")
	var factories := building_count(city_grid, "工廠")
	return {
		"traffic": clamp_score(int(current_metrics.get("traffic", 0)) - shops - malls * 2),
		"environment": clamp_score(int(current_metrics.get("environment", 0)) - int(shops / 2) - factories * 2),
		"security": clamp_score(int(current_metrics.get("security", 0)) - int(max(0, population - 120) / 160)),
		"satisfaction": clamp_score(int(current_metrics.get("satisfaction", 0)) + (1 if homes > 0 else 0)),
	}


static func satisfaction_result(
	current_metrics: Dictionary,
	tax_rates: Dictionary,
	tax_definitions: Dictionary,
	utility_fees: Dictionary,
	utility_definitions: Dictionary,
	service_fees: Dictionary,
	service_definitions: Dictionary,
	city_grid: Array,
	policies: Dictionary,
	active_policies: Dictionary,
	law_utility_relief: float
) -> Dictionary:
	var resident_tax_score := clamp_score(100 - int(tax_rates.get("income", 0)) * 3 - int(tax_rates.get("consumption", 0)) * 2)
	var merchant_tax_score := clamp_score(100 - int(tax_rates.get("business", 0)) * 3 - int(tax_rates.get("consumption", 0)) * 2)
	var utility_penalty := utility_satisfaction_penalty(utility_fees, utility_definitions, city_grid)
	utility_penalty += service_satisfaction_penalty(service_fees, service_definitions)
	var business_score := clamp_score(
		48
		+ building_count(city_grid, "商店") * 12
		+ building_count(city_grid, "大型商場") * 18
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
	city_grid: Array
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
		if building_count(city_grid, str(definition.get("building", ""))) == 0 and ratio > 1.0:
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
	city_grid: Array
) -> Array[String]:
	var warnings: Array[String] = []
	for fee_key_variant: Variant in utility_fees.keys():
		var fee_key := str(fee_key_variant)
		var definition: Dictionary = utility_definitions.get(fee_key, {})
		if (
			int(utility_fees[fee_key]) > int(definition.get("reasonable", 0))
			and building_count(city_grid, str(definition.get("building", ""))) == 0
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


static func building_count(city_grid: Array, building_name: String) -> int:
	var count := 0
	for item: Variant in city_grid:
		if str(item) == building_name:
			count += 1
	return count


static func building_score_bonus(city_grid: Array, buildings: Dictionary) -> int:
	return base_income(city_grid, buildings, "score_bonus")


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
