extends SceneTree

const CitySimulationServiceScript = preload("res://scripts/app/city_simulation_service.gd")
const CityStateScript = preload("res://scripts/core/city_state.gd")
const BuildingsCatalogScript = preload("res://data/catalogs/buildings.gd")

const TAX_DEFINITIONS := {
	"income": {"name": "所得稅", "max": 30, "reasonable": 10},
	"consumption": {"name": "消費稅", "max": 20, "reasonable": 5},
	"business": {"name": "商業營業稅", "max": 25, "reasonable": 8},
	"industry": {"name": "工業營業稅", "max": 25, "reasonable": 10},
}
const UTILITY_DEFINITIONS := {
	"garbage": {"name": "垃圾處理費", "reasonable": 20, "building": "垃圾處理場"},
	"water": {"name": "水費", "reasonable": 25, "building": "自來水廠"},
	"electricity": {"name": "電費", "reasonable": 30, "building": "發電廠"},
	"gas": {"name": "瓦斯費", "reasonable": 20, "building": "瓦斯場"},
}
const SERVICE_DEFINITIONS := {
	"bus": {"name": "公車票", "reasonable": 15, "building": "公車站", "base_uses": 18},
	"metro": {"name": "捷運票", "reasonable": 30, "building": "捷運站", "base_uses": 24},
	"parking": {"name": "停車費", "reasonable": 20, "building": "停車場", "base_uses": 14},
	"medical": {"name": "看病費", "reasonable": 50, "building": "醫院", "base_uses": 8},
	"tuition": {"name": "學費", "reasonable": 100, "building": "學校", "base_uses": 0.22},
	"stadium": {"name": "體育館門票", "reasonable": 80, "building": "體育館", "base_uses": 10},
}

var failed := false


func _initialize() -> void:
	var hospital_service: Dictionary = BuildingsCatalogScript.all().get("醫院", {}).get("public_service", {})
	_check(hospital_service == {
		"id": "healthcare",
		"model": "simplified_access_capacity_v1",
		"capacity_per_facility": 250,
		"max_metric_bonus": 30,
	}, "hospital catalog declares the deterministic access-capacity service contract")
	var buildings := {
		"商店": {"commercial_income": 1000, "maintenance": 50, "score_bonus": 2},
		"大型商場": {"commercial_income": 3000, "maintenance": 200, "score_bonus": 3},
		"工廠": {"industrial_income": 5000, "maintenance": 300, "score_bonus": 4},
		"發電廠": {"maintenance": 400, "utility_efficiency": {"electricity": 0.10}},
		"公車站": {"maintenance": 40},
		"學校": {"maintenance": 100},
	}
	var city_grid := ["商店", "大型商場", "工廠", "發電廠", "公車站", "學校"]
	var tax_rates := {"income": 10, "consumption": 5, "business": 8, "industry": 10}
	var utility_fees := {"garbage": 20, "water": 25, "electricity": 30, "gas": 20}
	var service_fees := {"bus": 15, "metro": 30, "parking": 20, "medical": 50, "tuition": 100, "stadium": 80}
	var policies := {
		"商業振興": {
			"expense": 250,
			"satisfaction": 2,
			"environment": 1,
			"traffic": 2,
		}
	}
	var active_policies := {"商業振興": true}
	var metrics := {
		"satisfaction": 70,
		"security": 70,
		"environment": 70,
		"traffic": 70,
		"education": 70,
		"healthcare": 70,
	}

	var commercial_base: int = CitySimulationServiceScript.base_income(city_grid, buildings, "commercial_income")
	var industrial_base: int = CitySimulationServiceScript.base_income(city_grid, buildings, "industrial_income")
	_check(commercial_base == 4000, "commercial base remains the sum of placed building definitions")
	_check(industrial_base == 5000, "industrial base remains the sum of placed building definitions")

	var tax_revenues: Dictionary = CitySimulationServiceScript.tax_revenues(
		10_000.0,
		300,
		commercial_base,
		industrial_base,
		tax_rates
	)
	_check(tax_revenues == {"income": 1000, "consumption": 270, "business": 320, "industry": 500}, "tax bases, rates, and rounding are unchanged")
	var business_income: int = CitySimulationServiceScript.business_income(commercial_base, true, 0.18, 1.0, 1.0)
	var industrial_income: int = CitySimulationServiceScript.industrial_income(industrial_base, 1.0, 0.22)
	_check(business_income == 5900, "commercial policy and law bonuses retain sequential rounding")
	_check(industrial_income == 6100, "industrial law bonus retains the existing rounding rule")

	var utility_revenues: Dictionary = CitySimulationServiceScript.utility_revenues(
		300,
		city_grid,
		buildings,
		utility_fees,
		UTILITY_DEFINITIONS
	)
	_check(is_equal_approx(float(utility_revenues.get("garbage", 0.0)), 285.2), "garbage revenue keeps the no-infrastructure efficiency factor")
	_check(is_equal_approx(float(utility_revenues.get("water", 0.0)), 325.5), "water revenue keeps the no-infrastructure efficiency factor")
	_check(is_equal_approx(float(utility_revenues.get("electricity", 0.0)), 1161.6), "electricity revenue keeps building and efficiency bonuses")
	_check(is_equal_approx(float(utility_revenues.get("gas", 0.0)), 204.6), "gas revenue keeps the no-infrastructure efficiency factor")
	var utility_total := int(round(_sum_float_values(utility_revenues)))
	_check(utility_total == 1977, "utility income still rounds once after summing all utilities")

	var service_revenues: Dictionary = CitySimulationServiceScript.service_revenues(
		300,
		city_grid,
		service_fees,
		SERVICE_DEFINITIONS
	)
	_check(int(service_revenues.get("bus", 0)) == 630, "bus uses keep the building and population formula")
	_check(int(service_revenues.get("tuition", 0)) == 6600, "tuition keeps the population share formula")
	_check(CitySimulationServiceScript.sum_int_values(service_revenues) == 7230, "missing service buildings still produce zero revenue")

	var healthcare_input := _healthcare_input()
	var healthcare_result: Dictionary = CitySimulationServiceScript.healthcare_service_result(healthcare_input)
	_check(str(healthcare_result.get("model_version", "")) == "simplified_access_capacity_v1", "healthcare model exposes its stable version")
	_check(str(healthcare_result.get("status", "")) == "operational" and str(healthcare_result.get("reason_code", "")) == "operational", "two accessible maintained hospitals are operational")
	_check(int(healthcare_result.get("count", 0)) == 2 and int(healthcare_result.get("capacity", 0)) == 500, "two hospitals provide 500 effective capacity")
	_check(int(healthcare_result.get("demand", 0)) == 300 and int(healthcare_result.get("served", 0)) == 300, "healthcare demand is capped by effective capacity")
	_check(is_equal_approx(float(healthcare_result.get("coverage", 0.0)), 1.0) and int(healthcare_result.get("metric_bonus", 0)) == 30, "full healthcare coverage grants the configured metric bonus")
	_check(
		CitySimulationServiceScript.medical_service_revenue(300, 50, SERVICE_DEFINITIONS.medical, healthcare_result) == 2000,
		"medical revenue uses two operational facilities and 300 served residents"
	)

	var no_facility_input: Dictionary = healthcare_input.duplicate(true)
	no_facility_input["building_records"] = {}
	var no_facility_result: Dictionary = CitySimulationServiceScript.healthcare_service_result(no_facility_input)
	_check(str(no_facility_result.get("reason_code", "")) == "facility_missing" and _healthcare_outputs_are_zero(no_facility_result), "missing facilities produce the stable unavailable result")

	var no_road_input: Dictionary = healthcare_input.duplicate(true)
	no_road_input["road_access_components"] = []
	var no_road_result: Dictionary = CitySimulationServiceScript.healthcare_service_result(no_road_input)
	_check(str(no_road_result.get("reason_code", "")) == "road_missing" and _healthcare_outputs_are_zero(no_road_result), "facilities without road access produce no service")
	_check(CitySimulationServiceScript.medical_service_revenue(300, 50, SERVICE_DEFINITIONS.medical, no_road_result) == 0, "road-disconnected healthcare produces no medical revenue")

	var maintenance_off_input: Dictionary = healthcare_input.duplicate(true)
	maintenance_off_input["maintenance_enabled"] = false
	var maintenance_off_result: Dictionary = CitySimulationServiceScript.healthcare_service_result(maintenance_off_input)
	_check(str(maintenance_off_result.get("reason_code", "")) == "maintenance_unfunded" and _healthcare_outputs_are_zero(maintenance_off_result), "disabled maintenance gates all healthcare output")
	_check(CitySimulationServiceScript.medical_service_revenue(300, 50, SERVICE_DEFINITIONS.medical, maintenance_off_result) == 0, "maintenance-disabled healthcare produces no revenue")

	var unpaid_input: Dictionary = healthcare_input.duplicate(true)
	unpaid_input["unpaid_maintenance_months"] = 1
	var unpaid_result: Dictionary = CitySimulationServiceScript.healthcare_service_result(unpaid_input)
	_check(str(unpaid_result.get("reason_code", "")) == "maintenance_unfunded" and _healthcare_outputs_are_zero(unpaid_result), "one unpaid maintenance month gates all healthcare output")
	_check(CitySimulationServiceScript.medical_service_revenue(300, 50, SERVICE_DEFINITIONS.medical, unpaid_result) == 0, "unpaid healthcare produces no revenue")

	var one_hospital_input: Dictionary = healthcare_input.duplicate(true)
	var one_hospital_buildings: Dictionary = one_hospital_input["building_records"]
	one_hospital_buildings.erase("hospital_2")
	one_hospital_input["building_records"] = one_hospital_buildings
	var one_hospital_durability: Dictionary = one_hospital_input["durability_records"]
	one_hospital_durability.erase("hospital_2")
	one_hospital_input["durability_records"] = one_hospital_durability
	var one_hospital_result: Dictionary = CitySimulationServiceScript.healthcare_service_result(one_hospital_input)
	_check(str(one_hospital_result.get("reason_code", "")) == "capacity_shortfall", "one hospital reports a stable capacity shortfall")
	_check(int(one_hospital_result.get("capacity", 0)) == 250 and int(one_hospital_result.get("served", 0)) == 250, "one hospital serves its exact 250-resident capacity")
	_check(is_equal_approx(float(one_hospital_result.get("coverage", 0.0)), 250.0 / 300.0) and int(one_hospital_result.get("metric_bonus", 0)) == 25, "partial coverage scales the metric bonus deterministically")
	_check(
		CitySimulationServiceScript.medical_service_revenue(300, 50, SERVICE_DEFINITIONS.medical, one_hospital_result) == 1400,
		"medical revenue uses one operational facility and 250 served residents"
	)

	var worn_input: Dictionary = one_hospital_input.duplicate(true)
	worn_input["durability_records"] = {"hospital_1": {"durability": 80, "efficiency": 0.8, "status": "active"}}
	var worn_result: Dictionary = CitySimulationServiceScript.healthcare_service_result(worn_input)
	_check(int(worn_result.get("capacity", 0)) == 200 and int(worn_result.get("served", 0)) == 200, "0.8 durability efficiency scales one hospital to capacity 200")

	var repeated_result: Dictionary = CitySimulationServiceScript.healthcare_service_result(healthcare_input.duplicate(true))
	var healthcare_json := JSON.stringify(healthcare_result)
	var round_trip_value: Variant = JSON.parse_string(healthcare_json)
	_check(JSON.stringify(repeated_result) == healthcare_json, "repeated healthcare evaluation is byte-stable")
	_check(
		round_trip_value is Dictionary
		and _healthcare_results_match(round_trip_value as Dictionary, healthcare_result),
		"healthcare output survives a JSON round trip"
	)

	_check(CitySimulationServiceScript.maintenance_cost(city_grid, buildings) == 1090, "maintenance remains the sum of placed buildings")
	_check(CitySimulationServiceScript.policy_expense(policies, active_policies) == 250, "only active policy expenses are counted")

	var settlement: Dictionary = CitySimulationServiceScript.compose_month_settlement(
		tax_revenues,
		business_income,
		industrial_income,
		utility_total,
		CitySimulationServiceScript.sum_int_values(service_revenues),
		1090,
		250,
		180
	)
	_check(int(settlement.get("income", 0)) == 23_297, "monthly income categories retain their exact total")
	_check(int(settlement.get("expense", 0)) == 1520, "monthly maintenance, policy, and law expense retain their exact total")
	_check(int((settlement.get("income_entries", {}) as Dictionary).get("tax", 0)) == 2090, "tax income stays separately auditable")

	var pressure_patch: Dictionary = CitySimulationServiceScript.city_pressure_metric_patch(metrics, 300, city_grid)
	_check(pressure_patch == {"traffic": 67, "environment": 68, "security": 69, "satisfaction": 70}, "monthly city pressure formulas are unchanged")
	var effect_patch: Dictionary = CitySimulationServiceScript.metric_effect_patch(metrics, {"security": 3, "environment": -2, "satisfaction": 4})
	_check(int(effect_patch.get("security", 0)) == 73 and int(effect_patch.get("environment", 0)) == 68 and int(effect_patch.get("satisfaction", 0)) == 74, "building effects return a bounded authoritative metric patch")
	var policy_patch: Dictionary = CitySimulationServiceScript.monthly_policy_metric_patch(metrics, policies, active_policies)
	_check(int(policy_patch.get("environment", 0)) == 71 and int(policy_patch.get("traffic", 0)) == 72 and int(policy_patch.get("satisfaction", 0)) == 72, "monthly policy effects preserve their metric deltas")

	var satisfaction_result: Dictionary = CitySimulationServiceScript.satisfaction_result(
		metrics,
		tax_rates,
		TAX_DEFINITIONS,
		utility_fees,
		UTILITY_DEFINITIONS,
		service_fees,
		SERVICE_DEFINITIONS,
		city_grid,
		policies,
		active_policies,
		4.0
	)
	_check(satisfaction_result.get("group_satisfaction", {}) == {"一般居民": 68, "學生家庭": 70, "商人": 76, "老年居民": 70}, "resident-group satisfaction retains tax, service, and city inputs")
	_check(int(satisfaction_result.get("satisfaction", 0)) == 80, "aggregate satisfaction keeps policy, tax, fee, and law adjustments")

	var score_metrics := metrics.duplicate(true)
	score_metrics["satisfaction"] = 80
	var score_result: Dictionary = CitySimulationServiceScript.score_result(
		score_metrics,
		250_000,
		300,
		CitySimulationServiceScript.building_score_bonus(city_grid, buildings),
		CitySimulationServiceScript.tax_pressure_score(tax_rates, TAX_DEFINITIONS),
		0
	)
	_check(score_result == {"ranking_score": 88, "best_score": 88, "city_rating": "A 級城市"}, "city score, best score, and rating thresholds are unchanged")
	_check(CitySimulationServiceScript.tax_pressure_score(tax_rates, TAX_DEFINITIONS) == 32, "weighted tax pressure formula is unchanged")

	var specs: Array[Dictionary] = [
		{"id": "security"},
		{"id": "traffic"},
		{"id": "education"},
	]
	var priority: Array[Dictionary] = CitySimulationServiceScript.prioritized_metric_specs(
		specs,
		{"security": 30, "traffic": 30, "education": 80}
	)
	_check(str(priority[0].get("id", "")) == "security" and str(priority[1].get("id", "")) == "traffic", "metric priority keeps deterministic ID tie-breaking")

	var state = CityStateScript.new(250_000)
	_check(state.set_metric_values(metrics), "CityState accepts one atomic metric patch API")
	_check(int(state.metric_value("traffic", -1)) == 70, "CityState exposes the authoritative metric value")
	_check(state.set_metric_values(pressure_patch), "CityState applies service output through its controlled writer")
	_check(int(state.metric_value("traffic", -1)) == 67 and int(state.metric_value("security", -1)) == 69, "service patches become the single authoritative values")
	var nested_metric := {"values": [1, 2]}
	_check(state.set_metric_value("test_nested", nested_metric), "CityState controlled writer accepts compatible custom metrics")
	var read_copy: Dictionary = state.metric_value("test_nested", {})
	(read_copy.get("values", []) as Array).append(3)
	_check((state.metric_value("test_nested", {}) as Dictionary).get("values", []).size() == 2, "CityState metric reads do not leak mutable aliases")
	_check(not state.set_metric_values({"": 1, "traffic": 99}) and int(state.metric_value("traffic", -1)) == 67, "invalid batch keys cannot partially mutate authoritative metrics")

	if failed:
		quit(1)
	else:
		print("City simulation service self-test passed. Income=%d Expense=%d Score=%d" % [
			int(settlement.get("income", 0)),
			int(settlement.get("expense", 0)),
			int(score_result.get("ranking_score", 0)),
		])
		quit(0)


func _sum_float_values(values: Dictionary) -> float:
	var total := 0.0
	for value: Variant in values.values():
		total += float(value)
	return total


func _healthcare_input() -> Dictionary:
	return {
		"population": 300,
		"building_records": {
			"hospital_2": {
				"building_id": "hospital_2",
				"definition_id": "hospital",
				"building_name": "醫院",
				"tile_index": 11,
				"status": "active",
			},
			"hospital_1": {
				"building_id": "hospital_1",
				"definition_id": "hospital",
				"building_name": "醫院",
				"tile_index": 10,
				"status": "active",
			},
			"hospital_scrapped": {
				"building_id": "hospital_scrapped",
				"definition_id": "hospital",
				"building_name": "醫院",
				"tile_index": 12,
				"status": "scrapped",
			},
			"hospital_demolition": {
				"building_id": "hospital_demolition",
				"definition_id": "hospital",
				"building_name": "醫院",
				"tile_index": 13,
				"status": "demolition",
			},
		},
		"road_access_components": [
			{"id": "road_b", "access_tile_ids": [11, 13]},
			{"id": "road_a", "access_tile_ids": [10, 12]},
		],
		"durability_records": {
			"hospital_1": {"durability": 100, "efficiency": 1.0, "status": "active"},
			"hospital_2": {"durability": 100, "efficiency": 1.0, "status": "active"},
		},
		"maintenance_enabled": true,
		"unpaid_maintenance_months": 0,
		"capacity_per_facility": 250,
		"max_metric_bonus": 30,
	}


func _healthcare_outputs_are_zero(result: Dictionary) -> bool:
	return (
		int(result.get("count", -1)) == 0
		and int(result.get("capacity", -1)) == 0
		and int(result.get("served", -1)) == 0
		and is_zero_approx(float(result.get("coverage", -1.0)))
		and int(result.get("metric_bonus", -1)) == 0
	)


func _healthcare_results_match(actual: Dictionary, expected: Dictionary) -> bool:
	for key: String in ["model_version", "status", "reason_code"]:
		if str(actual.get(key, "")) != str(expected.get(key, "")):
			return false
	for key: String in [
		"count",
		"facility_count",
		"road_accessible_facility_count",
		"operational_facility_count",
		"capacity",
		"demand",
		"served",
		"metric_bonus",
	]:
		if int(actual.get(key, -1)) != int(expected.get(key, -1)):
			return false
	return is_equal_approx(
		float(actual.get("coverage", -1.0)),
		float(expected.get("coverage", -1.0))
	)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	failed = true
	push_error("City simulation service self-test failed: %s" % label)
