extends RefCounted

const LegacyBuildings = preload("res://data/catalogs/buildings.gd")
const BuildingDefinition = preload("res://data/schemas/building_definition.gd")
const MaterialDefinition = preload("res://data/schemas/material_definition.gd")
const ZoneDefinition = preload("res://data/schemas/zone_definition.gd")
const ProfessionDefinition = preload("res://data/schemas/profession_definition.gd")
const BalanceParameters = preload("res://data/schemas/balance_parameters.gd")

const BUILDING_IDS := {
	"住宅": "residence",
	"社會住宅": "social_housing",
	"商店": "shop",
	"大型商場": "mall",
	"工廠": "factory",
	"公園": "park",
	"體育館": "stadium",
	"學校": "school",
	"圖書館": "library",
	"醫院": "hospital",
	"警局": "police_station",
	"消防局": "fire_station",
	"停車場": "parking_lot",
	"公車站": "bus_station",
	"捷運站": "metro_station",
	"火車站": "train_station",
	"機場": "airport",
	"發電廠": "power_plant",
	"核能發電廠": "nuclear_power_plant",
	"瓦斯場": "gas_works",
	"加油站": "gas_station",
	"自來水廠": "water_works",
	"游泳池": "swimming_pool",
	"垃圾處理場": "waste_center",
	"法院": "court",
	"監察所": "oversight_office",
	"市政府": "city_hall"
}

const CATEGORY_IDS := {
	"住宅類": "residential",
	"商業類": "commercial",
	"產業類": "industrial",
	"休閒類": "leisure",
	"教育文化類": "education",
	"醫療類": "healthcare",
	"安全類": "safety",
	"交通類": "transport",
	"基礎建設類": "infrastructure",
	"行政類": "administration"
}

const CORE_ACCEPTANCE_BUILDINGS := [
	"住宅", "工廠", "醫院", "學校", "公園", "警局", "消防局", "市政府"
]

static func balance() -> Resource:
	return BalanceParameters.new()

static func materials() -> Dictionary:
	var result := {}
	result["wood"] = _material("wood", "木造", 0.8, 0.7, 220, 5)
	result["brick"] = _material("brick", "磚造", 1.0, 1.0, 300, 12)
	result["steel"] = _material("steel", "鋼構", 1.25, 1.4, 460, 40)
	result["eco_composite"] = _material("eco_composite", "環保複材", 1.1, 1.25, 390, 24)
	return result

static func zones() -> Dictionary:
	var result := {}
	result["mixed"] = _zone("mixed", "混合發展區", [&"residential", &"commercial", &"leisure", &"education", &"healthcare", &"safety", &"administration"])
	result["industrial"] = _zone("industrial", "產業區", [&"industrial", &"infrastructure", &"transport"])
	result["civic"] = _zone("civic", "市政公共區", [&"administration", &"education", &"healthcare", &"safety", &"leisure"])
	return result

static func professions() -> Dictionary:
	var result := {}
	result["general_service"] = _profession("general_service", "一般服務人員", "service", 32000, 1)
	result["industry_worker"] = _profession("industry_worker", "產業技術員", "industry", 39000, 1)
	result["medical_worker"] = _profession("medical_worker", "醫療人員", "medical", 62000, 3)
	result["educator"] = _profession("educator", "教育人員", "education", 52000, 3)
	result["civil_servant"] = _profession("civil_servant", "市政公務員", "government", 48000, 2)
	return result

static func buildings_by_id() -> Dictionary:
	var legacy: Dictionary = LegacyBuildings.all()
	var result := {}
	for display_name in legacy.keys():
		var source: Dictionary = legacy[display_name]
		var definition = BuildingDefinition.new()
		definition.id = StringName(BUILDING_IDS[display_name])
		definition.display_name = display_name
		definition.category_id = StringName(CATEGORY_IDS.get(source.get("category", ""), "other"))
		definition.base_cost = int(source.get("cost", 0))
		definition.monthly_maintenance = int(source.get("maintenance", 0))
		definition.base_workload = _workload_for(source)
		definition.housing_capacity = maxi(0, int(source.get("housing_capacity", source.get("population", 0))))
		definition.job_capacity = maxi(0, int(source.get("job_capacity", source.get("job_attraction", 0))))
		definition.default_material_id = _default_material_for(definition.category_id)
		definition.core_acceptance = CORE_ACCEPTANCE_BUILDINGS.has(display_name)
		definition.effects = _extract_effects(source)
		definition.description = str(source.get("description", ""))
		definition.color = source.get("color", Color.WHITE)
		definition.text_color = source.get("text_color", Color.BLACK)
		result[String(definition.id)] = definition
	return result

static func building_id_for_name(display_name: String) -> String:
	return str(BUILDING_IDS.get(display_name, display_name.to_snake_case()))

static func _workload_for(source: Dictionary) -> float:
	var cost := maxf(float(source.get("cost", 1000)), 1.0)
	var maintenance := maxf(float(source.get("maintenance", 50)), 1.0)
	return snappedf(clampf(10.0 + cost / 220.0 + maintenance / 35.0, 12.0, 96.0), 0.5)

static func _default_material_for(category_id: StringName) -> StringName:
	if category_id in [&"industrial", &"infrastructure", &"transport"]:
		return &"steel"
	if category_id in [&"leisure", &"residential"]:
		return &"wood"
	return &"brick"

static func _extract_effects(source: Dictionary) -> Dictionary:
	var ignored := ["category", "cost", "maintenance", "color", "text_color", "description"]
	var effects := {}
	for key in source.keys():
		if not ignored.has(key):
			effects[key] = source[key]
	return effects

static func _material(id: String, name: String, workload: float, price: float, value: int, floors: int) -> Resource:
	var item = MaterialDefinition.new()
	item.id = StringName(id)
	item.display_name = name
	item.workload_multiplier = workload
	item.price_multiplier = price
	item.material_value_per_size = value
	item.theoretical_max_floors = floors
	return item

static func _zone(id: String, name: String, categories: Array[StringName]) -> Resource:
	var item = ZoneDefinition.new()
	item.id = StringName(id)
	item.display_name = name
	item.compatible_categories = categories
	return item

static func _profession(id: String, name: String, tag: String, income: int, education: int) -> Resource:
	var item = ProfessionDefinition.new()
	item.id = StringName(id)
	item.display_name = name
	item.industry_tag = StringName(tag)
	item.base_income = income
	item.education_level = education
	return item
