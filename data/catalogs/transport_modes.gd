class_name TransportModes
extends RefCounted

## Canonical, JSON-safe transport rules.  This catalog deliberately describes
## infrastructure and operations rather than terrain art: roads, tracks, and
## runways live in the transport overlay and never replace natural terrain.

const SEGMENT_KINDS := {
	"road": {
		"build_cost_per_tile": 520,
		"demolish_cost_per_tile": 130,
		"monthly_maintenance_per_tile": 18,
		"navigation_blocker": true,
	},
	"metro_track": {
		"build_cost_per_tile": 920,
		"demolish_cost_per_tile": 230,
		"monthly_maintenance_per_tile": 34,
		"navigation_blocker": true,
	},
	"rail_track": {
		"build_cost_per_tile": 780,
		"demolish_cost_per_tile": 195,
		"monthly_maintenance_per_tile": 30,
		"navigation_blocker": true,
	},
	"runway": {
		"build_cost_per_tile": 2_400,
		"demolish_cost_per_tile": 600,
		"monthly_maintenance_per_tile": 95,
		"navigation_blocker": true,
	},
	"taxiway": {
		"build_cost_per_tile": 900,
		"demolish_cost_per_tile": 225,
		"monthly_maintenance_per_tile": 32,
		"navigation_blocker": true,
	},
}

const FACILITY_KINDS := {
	"bus_depot": {
		"network_kind": "road",
		"build_cost": 3_600,
		"demolish_cost": 900,
		"monthly_maintenance": 120,
		"navigation_blocker": true,
	},
	"metro_depot": {
		"network_kind": "metro_track",
		"build_cost": 8_800,
		"demolish_cost": 2_200,
		"monthly_maintenance": 310,
		"navigation_blocker": true,
	},
	"rail_depot": {
		"network_kind": "rail_track",
		"build_cost": 7_600,
		"demolish_cost": 1_900,
		"monthly_maintenance": 280,
		"navigation_blocker": true,
	},
	"rail_signal": {
		"network_kind": "rail_track",
		"build_cost": 650,
		"demolish_cost": 165,
		"monthly_maintenance": 18,
		"navigation_blocker": true,
	},
}

const STATION_KINDS := {
	"公車站": {
		"route_mode": "bus",
		"build_cost": 1_600,
		"demolish_cost": 400,
		"monthly_maintenance": 50,
	},
	"捷運站": {
		"route_mode": "metro",
		"build_cost": 5_000,
		"demolish_cost": 1_250,
		"monthly_maintenance": 220,
	},
	"火車站": {
		"route_mode": "train",
		"build_cost": 6_500,
		"demolish_cost": 1_625,
		"monthly_maintenance": 260,
	},
	"機場": {
		"route_mode": "air",
		"build_cost": 12_000,
		"demolish_cost": 3_000,
		"monthly_maintenance": 600,
	},
}

const ROUTE_MODES := {
	"bus": {
		"station_name": "公車站",
		"guideway_kind": "road",
		"required_depot_kind": "bus_depot",
		"vehicle_kind": "bus",
		"minimum_stops": 2,
		"loop_seconds": 12.0,
		"fleet_monthly_maintenance": 42,
	},
	"metro": {
		"station_name": "捷運站",
		"guideway_kind": "metro_track",
		"required_depot_kind": "metro_depot",
		"vehicle_kind": "metro_train",
		"minimum_stops": 2,
		"loop_seconds": 9.0,
		"fleet_monthly_maintenance": 150,
	},
	"train": {
		"station_name": "火車站",
		"guideway_kind": "rail_track",
		"required_depot_kind": "rail_depot",
		"vehicle_kind": "train",
		"minimum_stops": 2,
		"loop_seconds": 10.5,
		"fleet_monthly_maintenance": 180,
	},
	"air": {
		"station_name": "機場",
		"guideway_kind": "runway",
		"required_depot_kind": "",
		"vehicle_kind": "plane",
		"minimum_stops": 1,
		"loop_seconds": 16.0,
		"fleet_monthly_maintenance": 420,
	},
}

const CROSSING_KIND := "level_crossing"
const LEVEL_CROSSING_BUILD_COST := 900
const LEVEL_CROSSING_MONTHLY_MAINTENANCE := 40
const ROUTE_PACKAGE_PRICE_MODEL_V1 := "route_package_v1"
const ROUTE_PACKAGE_PRICE_MODEL_V2 := "route_package_v2"
const ROUTE_PACKAGE_PRICE_MODEL := ROUTE_PACKAGE_PRICE_MODEL_V2
const ROUTE_PACKAGE_PRICE_PROVENANCE := "transport_network_system.quote_project/build/v1"
const ROUTE_BASE_CONSTRUCTION_PER_TILE := 1_000
const ROUTE_BASE_MAINTENANCE_PER_TILE := 300
const ROUTE_BASE_TILE_LIMIT := 10
const ROUTE_LONG_DISTANCE_MULTIPLIER := 1.02
const PROJECT_OPERATIONS := ["build", "demolish"]
const PROJECT_STATUSES := ["planned", "under_construction", "completed"]
const CONNECTION_DIRECTIONS := ["n", "e", "s", "w"]


static func segment_spec(kind: String) -> Dictionary:
	return Dictionary(SEGMENT_KINDS.get(kind, {})).duplicate(true)


static func facility_spec(kind: String) -> Dictionary:
	return Dictionary(FACILITY_KINDS.get(kind, {})).duplicate(true)


static func station_spec(display_name: String) -> Dictionary:
	return Dictionary(STATION_KINDS.get(display_name, {})).duplicate(true)


static func route_spec(mode: String) -> Dictionary:
	return Dictionary(ROUTE_MODES.get(mode, {})).duplicate(true)


static func segment_kinds() -> Array[String]:
	var result: Array[String] = []
	for kind_variant: Variant in SEGMENT_KINDS.keys():
		result.append(str(kind_variant))
	result.sort()
	return result


static func facility_kinds() -> Array[String]:
	var result: Array[String] = []
	for kind_variant: Variant in FACILITY_KINDS.keys():
		result.append(str(kind_variant))
	result.sort()
	return result


static func route_modes() -> Array[String]:
	var result: Array[String] = []
	for mode_variant: Variant in ROUTE_MODES.keys():
		result.append(str(mode_variant))
	result.sort()
	return result


static func route_package_construction_cost(tile_count: int) -> int:
	return _route_package_scaled_cost(tile_count, ROUTE_BASE_CONSTRUCTION_PER_TILE)


static func route_package_monthly_maintenance(tile_count: int) -> int:
	return _route_package_scaled_cost(tile_count, ROUTE_BASE_MAINTENANCE_PER_TILE)


static func route_package_price_quote(tile_count: int) -> Dictionary:
	var resolved_count := maxi(0, tile_count)
	var road_spec := segment_spec("road")
	return {
		"price_model": ROUTE_PACKAGE_PRICE_MODEL,
		"price_provenance": ROUTE_PACKAGE_PRICE_PROVENANCE,
		"route_tile_count": resolved_count,
		"construction_cost": int(road_spec.get("build_cost_per_tile", 0)) * resolved_count,
		"monthly_maintenance": int(road_spec.get("monthly_maintenance_per_tile", 0)) * resolved_count,
	}


static func route_package_v1_price_quote(tile_count: int) -> Dictionary:
	var resolved_count := maxi(0, tile_count)
	var exponent := maxi(0, resolved_count - ROUTE_BASE_TILE_LIMIT)
	return {
		"price_model": ROUTE_PACKAGE_PRICE_MODEL_V1,
		"route_tile_count": resolved_count,
		"long_distance_exponent": exponent,
		"construction_cost": route_package_construction_cost(resolved_count),
		"monthly_maintenance": route_package_monthly_maintenance(resolved_count),
	}


static func is_route_package_price_model(value: String) -> bool:
	return value in [ROUTE_PACKAGE_PRICE_MODEL_V1, ROUTE_PACKAGE_PRICE_MODEL_V2]


static func _route_package_scaled_cost(tile_count: int, base_per_tile: int) -> int:
	var resolved_count := maxi(0, tile_count)
	var base_tiles := mini(resolved_count, ROUTE_BASE_TILE_LIMIT)
	var excess_tiles := maxi(0, resolved_count - ROUTE_BASE_TILE_LIMIT)
	if excess_tiles == 0:
		return base_per_tile * base_tiles
	var exponent := excess_tiles
	var long_distance_unit := float(base_per_tile) * pow(ROUTE_LONG_DISTANCE_MULTIPLIER, exponent)
	return int(ceil(float(base_per_tile * base_tiles) + float(excess_tiles) * long_distance_unit))


static func validation_snapshot() -> Dictionary:
	var issues: Array[String] = []
	for kind: String in segment_kinds():
		var spec := segment_spec(kind)
		for key: String in ["build_cost_per_tile", "demolish_cost_per_tile", "monthly_maintenance_per_tile", "navigation_blocker"]:
			if not spec.has(key):
				issues.append("segment:%s:missing:%s" % [kind, key])
	for kind: String in facility_kinds():
		var spec := facility_spec(kind)
		for key: String in ["network_kind", "build_cost", "demolish_cost", "monthly_maintenance", "navigation_blocker"]:
			if not spec.has(key):
				issues.append("facility:%s:missing:%s" % [kind, key])
		if str(spec.get("network_kind", "")) not in SEGMENT_KINDS:
			issues.append("facility:%s:unknown_network" % kind)
	for mode: String in route_modes():
		var spec := route_spec(mode)
		for key: String in ["station_name", "guideway_kind", "required_depot_kind", "vehicle_kind", "minimum_stops", "loop_seconds", "fleet_monthly_maintenance"]:
			if not spec.has(key):
				issues.append("route:%s:missing:%s" % [mode, key])
		if str(spec.get("guideway_kind", "")) not in SEGMENT_KINDS:
			issues.append("route:%s:unknown_guideway" % mode)
		var depot_kind := str(spec.get("required_depot_kind", ""))
		if not depot_kind.is_empty() and depot_kind not in FACILITY_KINDS:
			issues.append("route:%s:unknown_depot" % mode)
	return {
		"valid": issues.is_empty(),
		"issues": issues,
		"segment_kinds": segment_kinds(),
		"facility_kinds": facility_kinds(),
		"route_modes": route_modes(),
		"infrastructure_layer": "transport_overlay",
		"terrain_authority": false,
	}
