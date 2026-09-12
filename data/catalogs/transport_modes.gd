class_name TransportModes
extends RefCounted

const CityTerrainLayoutScript = preload("res://data/catalogs/city_terrain_layout.gd")

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
const ROUTE_PACKAGE_PRICE_MODEL_V3 := "route_package_v3"
const ROUTE_PACKAGE_PRICE_MODEL := ROUTE_PACKAGE_PRICE_MODEL_V2
const ROUTE_PACKAGE_PRICE_PROVENANCE := "transport_network_system.quote_project/build/v1"
const ROUTE_PACKAGE_REUSE_PRICE_MODEL := ROUTE_PACKAGE_PRICE_MODEL_V3
const ROUTE_PACKAGE_REUSE_PRICE_PROVENANCE := "transport_network_system.quote_completed_corridor/build/v2"
const ROUTE_PACKAGE_CORRIDOR_SCHEMA_VERSION := 1
const ROUTE_PACKAGE_QUOTE_SCHEMA_VERSION := 1
const ROUTE_PACKAGE_QUOTE_CHECKSUM_VERSION := 1
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


static func route_package_price_quote(tile_count: int, network_kind: String = "road") -> Dictionary:
	var resolved_count := maxi(0, tile_count)
	var network_spec := segment_spec(network_kind)
	if network_spec.is_empty():
		return {
			"ok": false,
			"error": "invalid_network_kind",
			"network_kind": network_kind,
			"route_tile_count": resolved_count,
		}
	return {
		"ok": true,
		"price_model": ROUTE_PACKAGE_PRICE_MODEL,
		"price_provenance": ROUTE_PACKAGE_PRICE_PROVENANCE,
		"network_kind": network_kind,
		"route_tile_count": resolved_count,
		"construction_cost": int(network_spec.get("build_cost_per_tile", 0)) * resolved_count,
		"monthly_maintenance": int(network_spec.get("monthly_maintenance_per_tile", 0)) * resolved_count,
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


static func route_package_corridor_price_quote(corridor_contract: Dictionary) -> Dictionary:
	var validation := validate_route_package_corridor_contract(corridor_contract)
	if not bool(validation.get("valid", false)):
		return {
			"ok": false,
			"error": "invalid_corridor_contract",
			"issues": Array(validation.get("issues", [])).duplicate(),
		}
	var contract := corridor_contract.duplicate(true)
	var segment_specification := segment_spec(str(contract.get("segment_kind", "")))
	var new_units := int(contract.get("new_units", 0))
	var construction_cost := int(segment_specification.get("build_cost_per_tile", 0)) * new_units
	var monthly_maintenance := int(segment_specification.get("monthly_maintenance_per_tile", 0)) * new_units
	var quote := {
		"quote_schema_version": ROUTE_PACKAGE_QUOTE_SCHEMA_VERSION,
		"price_model": ROUTE_PACKAGE_REUSE_PRICE_MODEL,
		"price_provenance": ROUTE_PACKAGE_REUSE_PRICE_PROVENANCE,
		"corridor": contract,
		"price_breakdown": {
			"reused_corridor": 0,
			"new_corridor": construction_cost,
		},
		"maintenance_breakdown": {
			"reused_corridor": 0,
			"new_corridor": monthly_maintenance,
		},
		"total_cost": construction_cost,
		"monthly_maintenance": monthly_maintenance,
		"checksum_version": ROUTE_PACKAGE_QUOTE_CHECKSUM_VERSION,
	}
	quote["checksum"] = _route_package_quote_checksum(quote)
	quote["ok"] = true
	return quote


static func validate_route_package_corridor_contract(value: Variant) -> Dictionary:
	var issues: Array[String] = []
	if not value is Dictionary:
		return {"valid": false, "issues": ["corridor_not_dictionary"]}
	var contract: Dictionary = value
	var required_keys := [
		"schema_version", "mode", "segment_kind", "classification",
		"route_tile_ids", "reused_segment_refs", "new_runs",
		"total_units", "reused_units", "new_units",
	]
	if not _has_exact_keys(contract, required_keys):
		issues.append("corridor_fields_mismatch")
	if not _is_integer_value(contract.get("schema_version", null)) or int(contract.get("schema_version", -1)) != ROUTE_PACKAGE_CORRIDOR_SCHEMA_VERSION:
		issues.append("unsupported_corridor_schema")
	var mode := str(contract.get("mode", ""))
	var segment_kind := str(contract.get("segment_kind", ""))
	if route_spec(mode).is_empty() or str(route_spec(mode).get("guideway_kind", "")) != segment_kind:
		issues.append("corridor_mode_kind_mismatch")
	var route_tiles_validation := _validated_tile_array(contract.get("route_tile_ids", null), false)
	if not bool(route_tiles_validation.get("valid", false)):
		issues.append("invalid_corridor_route_tiles")
	var route_tile_ids: Array = route_tiles_validation.get("values", [])
	var route_set: Dictionary = {}
	for tile_value: Variant in route_tile_ids:
		route_set[int(tile_value)] = true
	var reused_set: Dictionary = {}
	var refs_value: Variant = contract.get("reused_segment_refs", null)
	var previous_id := ""
	if not refs_value is Array:
		issues.append("invalid_reused_segment_refs")
	else:
		for ref_value: Variant in refs_value:
			if not ref_value is Dictionary:
				issues.append("invalid_reused_segment_ref")
				continue
			var ref: Dictionary = ref_value
			if not _has_exact_keys(ref, ["id", "kind", "tile_ids"]):
				issues.append("invalid_reused_segment_ref")
				continue
			var ref_id := str(ref.get("id", ""))
			if ref_id.is_empty() or (not previous_id.is_empty() and ref_id <= previous_id):
				issues.append("unordered_reused_segment_refs")
			previous_id = ref_id
			if str(ref.get("kind", "")) != segment_kind:
				issues.append("reused_segment_kind_mismatch")
			var ref_tiles_validation := _validated_tile_array(ref.get("tile_ids", null), false)
			if not bool(ref_tiles_validation.get("valid", false)):
				issues.append("invalid_reused_segment_tiles")
				continue
			for tile_value: Variant in ref_tiles_validation.get("values", []):
				var tile_id := int(tile_value)
				if not route_set.has(tile_id) or reused_set.has(tile_id):
					issues.append("invalid_reused_segment_partition")
				reused_set[tile_id] = true
	var new_set: Dictionary = {}
	var flattened_new_tiles: Array[int] = []
	var runs_value: Variant = contract.get("new_runs", null)
	if not runs_value is Array:
		issues.append("invalid_new_runs")
	else:
		for run_value: Variant in runs_value:
			if not run_value is Dictionary:
				issues.append("invalid_new_run")
				continue
			var run: Dictionary = run_value
			if not _has_exact_keys(run, ["kind", "tile_path"]) or str(run.get("kind", "")) != segment_kind:
				issues.append("invalid_new_run")
				continue
			var run_tiles_validation := _validated_tile_array(run.get("tile_path", null), false)
			if not bool(run_tiles_validation.get("valid", false)) or not _tiles_are_cardinally_contiguous(run_tiles_validation.get("values", [])):
				issues.append("invalid_new_run_tiles")
				continue
			for tile_value: Variant in run_tiles_validation.get("values", []):
				var tile_id := int(tile_value)
				if not route_set.has(tile_id) or reused_set.has(tile_id) or new_set.has(tile_id):
					issues.append("invalid_new_run_partition")
				new_set[tile_id] = true
				flattened_new_tiles.append(tile_id)
	var ordered_new_tiles: Array[int] = []
	for tile_value: Variant in route_tile_ids:
		var tile_id := int(tile_value)
		if new_set.has(tile_id):
			ordered_new_tiles.append(tile_id)
	if flattened_new_tiles != ordered_new_tiles:
		issues.append("unordered_new_runs")
	var total_units := int(contract.get("total_units", -1)) if _is_integer_value(contract.get("total_units", null)) else -1
	var reused_units := int(contract.get("reused_units", -1)) if _is_integer_value(contract.get("reused_units", null)) else -1
	var new_units := int(contract.get("new_units", -1)) if _is_integer_value(contract.get("new_units", null)) else -1
	if total_units != route_tile_ids.size() or reused_units != reused_set.size() or new_units != new_set.size() or reused_units + new_units != total_units:
		issues.append("corridor_unit_count_mismatch")
	if reused_set.size() + new_set.size() != route_set.size():
		issues.append("corridor_partition_incomplete")
	var expected_classification := "mixed"
	if reused_units == 0:
		expected_classification = "all_new"
	elif new_units == 0:
		expected_classification = "all_reuse"
	if str(contract.get("classification", "")) != expected_classification:
		issues.append("corridor_classification_mismatch")
	return {"valid": issues.is_empty(), "issues": issues}


static func validate_route_package_corridor_price_quote(value: Variant) -> Dictionary:
	var issues: Array[String] = []
	if not value is Dictionary:
		return {"valid": false, "issues": ["quote_not_dictionary"]}
	var quote: Dictionary = value
	for field_name: String in [
		"quote_schema_version", "price_model", "price_provenance", "corridor",
		"price_breakdown", "maintenance_breakdown", "total_cost",
		"monthly_maintenance", "checksum_version", "checksum",
	]:
		if not quote.has(field_name):
			issues.append("missing_quote_field:%s" % field_name)
	if not _is_integer_value(quote.get("quote_schema_version", null)) or int(quote.get("quote_schema_version", -1)) != ROUTE_PACKAGE_QUOTE_SCHEMA_VERSION:
		issues.append("unsupported_quote_schema")
	if str(quote.get("price_model", "")) != ROUTE_PACKAGE_REUSE_PRICE_MODEL:
		issues.append("unsupported_quote_price_model")
	if str(quote.get("price_provenance", "")) != ROUTE_PACKAGE_REUSE_PRICE_PROVENANCE:
		issues.append("invalid_quote_price_provenance")
	var corridor_validation := validate_route_package_corridor_contract(quote.get("corridor", null))
	if not bool(corridor_validation.get("valid", false)):
		issues.append("invalid_quote_corridor")
	var corridor: Dictionary = quote.get("corridor", {}) if quote.get("corridor", {}) is Dictionary else {}
	var spec := segment_spec(str(corridor.get("segment_kind", "")))
	var new_units := int(corridor.get("new_units", -1)) if _is_integer_value(corridor.get("new_units", null)) else -1
	var expected_cost := int(spec.get("build_cost_per_tile", 0)) * new_units if new_units >= 0 else -1
	var expected_maintenance := int(spec.get("monthly_maintenance_per_tile", 0)) * new_units if new_units >= 0 else -1
	if not _price_breakdown_matches(quote.get("price_breakdown", null), expected_cost):
		issues.append("invalid_quote_price_breakdown")
	if not _price_breakdown_matches(quote.get("maintenance_breakdown", null), expected_maintenance):
		issues.append("invalid_quote_maintenance_breakdown")
	if not _is_integer_value(quote.get("total_cost", null)) or int(quote.get("total_cost", -1)) != expected_cost:
		issues.append("invalid_quote_total_cost")
	if not _is_integer_value(quote.get("monthly_maintenance", null)) or int(quote.get("monthly_maintenance", -1)) != expected_maintenance:
		issues.append("invalid_quote_monthly_maintenance")
	if not _is_integer_value(quote.get("checksum_version", null)) or int(quote.get("checksum_version", -1)) != ROUTE_PACKAGE_QUOTE_CHECKSUM_VERSION:
		issues.append("unsupported_quote_checksum_version")
	var checksum := str(quote.get("checksum", ""))
	if checksum.length() != 64 or checksum != _route_package_quote_checksum(quote):
		issues.append("invalid_quote_checksum")
	return {"valid": issues.is_empty(), "issues": issues}


static func is_route_package_price_model(value: String) -> bool:
	return value in [ROUTE_PACKAGE_PRICE_MODEL_V1, ROUTE_PACKAGE_PRICE_MODEL_V2, ROUTE_PACKAGE_PRICE_MODEL_V3]


static func _route_package_quote_checksum(quote: Dictionary) -> String:
	var payload := {
		"quote_schema_version": int(quote.get("quote_schema_version", -1)),
		"price_model": str(quote.get("price_model", "")),
		"price_provenance": str(quote.get("price_provenance", "")),
		"corridor": _canonicalize(quote.get("corridor", {})),
		"price_breakdown": _canonicalize(quote.get("price_breakdown", {})),
		"maintenance_breakdown": _canonicalize(quote.get("maintenance_breakdown", {})),
		"total_cost": int(quote.get("total_cost", -1)),
		"monthly_maintenance": int(quote.get("monthly_maintenance", -1)),
		"checksum_version": int(quote.get("checksum_version", -1)),
	}
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(_canonicalize(payload)).to_utf8_buffer())
	return context.finish().hex_encode()


static func _price_breakdown_matches(value: Variant, expected_new_value: int) -> bool:
	if not value is Dictionary:
		return false
	var breakdown: Dictionary = value
	return (
		_has_exact_keys(breakdown, ["reused_corridor", "new_corridor"])
		and _is_integer_value(breakdown.get("reused_corridor", null))
		and int(breakdown.get("reused_corridor", -1)) == 0
		and _is_integer_value(breakdown.get("new_corridor", null))
		and int(breakdown.get("new_corridor", -1)) == expected_new_value
	)


static func _validated_tile_array(value: Variant, allow_empty: bool) -> Dictionary:
	if not value is Array or (value as Array).is_empty() and not allow_empty:
		return {"valid": false, "values": []}
	var seen: Dictionary = {}
	var values: Array[int] = []
	for item: Variant in value:
		if not _is_integer_value(item):
			return {"valid": false, "values": []}
		var tile_id := int(item)
		if tile_id < 0 or tile_id >= 100 or seen.has(tile_id):
			return {"valid": false, "values": []}
		seen[tile_id] = true
		values.append(tile_id)
	return {"valid": true, "values": values}


static func _tiles_are_cardinally_contiguous(tile_ids: Array) -> bool:
	for index: int in range(1, tile_ids.size()):
		var previous := CityTerrainLayoutScript.coordinate_for_tile_id(int(tile_ids[index - 1]))
		var current := CityTerrainLayoutScript.coordinate_for_tile_id(int(tile_ids[index]))
		if (
			previous == CityTerrainLayoutScript.INVALID_COORDINATE
			or current == CityTerrainLayoutScript.INVALID_COORDINATE
			or absi(previous.x - current.x) + absi(previous.y - current.y) != 1
		):
			return false
	return true


static func _has_exact_keys(value: Dictionary, expected_keys: Array) -> bool:
	if value.size() != expected_keys.size():
		return false
	for key: Variant in expected_keys:
		if not value.has(key):
			return false
	return true


static func _is_integer_value(value: Variant) -> bool:
	return value is int or (value is float and is_finite(float(value)) and float(value) == roundf(float(value)))


static func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		var keys: Array[String] = []
		for key: Variant in (value as Dictionary).keys():
			keys.append(str(key))
		keys.sort()
		for key: String in keys:
			result[key] = _canonicalize((value as Dictionary)[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_canonicalize(item))
		return result
	if value is float and is_finite(float(value)) and float(value) == roundf(float(value)):
		return int(value)
	return value


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
