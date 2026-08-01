class_name TransportNetworkSystem
extends RefCounted

## Authoritative transport overlay and route validator.
##
## Natural terrain remains owned by CityTerrainMap.  This model stores only
## player-authored stations, facilities, infrastructure segments, crossings,
## projects, and operational lines.  Runtime vehicles are derived exclusively
## from valid enabled routes and are never persisted as free-running map props.

const TransportModesScript = preload("res://data/catalogs/transport_modes.gd")
const CityTerrainMapScript = preload("res://scripts/world/city_terrain_map.gd")

const SCHEMA_VERSION := 1
const TRACK_KINDS := ["metro_track", "rail_track"]
const PROJECT_STATUS_PRIORITY := {
	"": 0,
	"completed": 1,
	"planned": 2,
	"under_construction": 3,
}

var next_project_sequence: int = 1
var next_segment_sequence: int = 1
var next_facility_sequence: int = 1
var next_station_sequence: int = 1
var next_route_sequence: int = 1

var projects: Dictionary = {}
var segments: Dictionary = {}
var facilities: Dictionary = {}
var stations: Dictionary = {}
var crossings: Dictionary = {}
var routes: Dictionary = {}

var _topology_map = CityTerrainMapScript.new()


func quote_project(
	operation: String,
	plan: Dictionary,
	terrain_map: Variant,
	occupied_tile_ids: Variant = [],
	construction_tile_ids: Variant = []
) -> Dictionary:
	if operation not in TransportModesScript.PROJECT_OPERATIONS:
		return _error("invalid_project_operation")
	if operation == "demolish":
		return _quote_demolition(plan)
	if terrain_map == null:
		return _error("terrain_map_required")

	var normalized_plan := _normalize_build_plan(plan)
	var occupied := _tile_set(occupied_tile_ids)
	var construction := _tile_set(construction_tile_ids)
	for tile_variant: Variant in _active_project_tile_set().keys():
		construction[int(tile_variant)] = true
	for record_variant: Variant in facilities.values():
		var facility: Dictionary = record_variant
		occupied[int(facility.get("tile_id", -1))] = true
	for record_variant: Variant in stations.values():
		var station: Dictionary = record_variant
		occupied[int(station.get("tile_id", -1))] = true

	var issues := _validate_build_plan(normalized_plan, terrain_map, occupied, construction)
	if not issues.is_empty():
		return {
			"ok": false,
			"error": "invalid_transport_plan",
			"issues": issues,
			"operation": operation,
			"plan": normalized_plan,
		}

	var segment_cost := 0
	for segment: Dictionary in normalized_plan["segments"]:
		var spec := TransportModesScript.segment_spec(str(segment.get("kind", "")))
		segment_cost += int(spec.get("build_cost_per_tile", 0)) * Array(segment.get("tile_path", [])).size()
	var facility_cost := 0
	for facility: Dictionary in normalized_plan["facilities"]:
		facility_cost += int(TransportModesScript.facility_spec(str(facility.get("kind", ""))).get("build_cost", 0))
	var station_cost := 0
	for station: Dictionary in normalized_plan["stations"]:
		station_cost += int(TransportModesScript.station_spec(str(station.get("building_name", ""))).get("build_cost", 0))
	var new_crossing_tiles := _new_crossing_tiles_for_plan(normalized_plan)
	var crossing_cost := new_crossing_tiles.size() * TransportModesScript.LEVEL_CROSSING_BUILD_COST
	var total_cost := segment_cost + facility_cost + station_cost + crossing_cost
	return {
		"ok": true,
		"operation": operation,
		"plan": normalized_plan,
		"crossing_tile_ids": new_crossing_tiles,
		"breakdown": {
			"segments": segment_cost,
			"facilities": facility_cost,
			"stations": station_cost,
			"level_crossings": crossing_cost,
		},
		"total_cost": total_cost,
	}


func plan_project(
	operation: String,
	plan: Dictionary,
	terrain_map: Variant,
	occupied_tile_ids: Variant = [],
	construction_tile_ids: Variant = []
) -> Dictionary:
	return _create_project(
		operation,
		plan,
		"planned",
		terrain_map,
		occupied_tile_ids,
		construction_tile_ids
	)


func start_project(
	operation_or_project_id: String,
	plan: Dictionary = {},
	terrain_map: Variant = null,
	occupied_tile_ids: Variant = [],
	construction_tile_ids: Variant = []
) -> Dictionary:
	if projects.has(operation_or_project_id) and plan.is_empty():
		var existing: Dictionary = projects[operation_or_project_id]
		if str(existing.get("status", "")) != "planned":
			return _error("project_not_planned")
		existing["status"] = "under_construction"
		projects[operation_or_project_id] = existing
		return {"ok": true, "project": existing.duplicate(true), "quote": existing.get("quote", {}).duplicate(true)}
	return _create_project(
		operation_or_project_id,
		plan,
		"under_construction",
		terrain_map,
		occupied_tile_ids,
		construction_tile_ids
	)


func complete_project(project_id: String) -> Dictionary:
	if not projects.has(project_id):
		return _error("project_not_found")
	var project: Dictionary = projects[project_id]
	if str(project.get("status", "")) != "under_construction":
		return _error("project_not_under_construction")
	var operation := str(project.get("operation", ""))
	var plan: Dictionary = project.get("plan", {})
	if operation == "build":
		_commit_build_project(project_id, plan)
	elif operation == "demolish":
		_commit_demolition_project(plan)
	else:
		return _error("invalid_project_operation")
	project["status"] = "completed"
	projects[project_id] = project
	_recompute_crossings()
	revalidate_routes()
	return {"ok": true, "project": project.duplicate(true), "network": network_snapshot()}


func route_quote(route_plan: Dictionary) -> Dictionary:
	var normalized := _normalize_route(route_plan)
	var mode := str(normalized.get("mode", ""))
	var mode_spec := TransportModesScript.route_spec(mode)
	if mode_spec.is_empty():
		return {
			"ok": false,
			"valid": false,
			"error": "invalid_route_mode",
			"validation_errors": ["invalid_route_mode"],
			"route": normalized,
		}

	var validation_errors: Array[String] = []
	var stop_ids: Array = normalized.get("stop_ids", [])
	var minimum_stops := int(mode_spec.get("minimum_stops", 2))
	if stop_ids.size() < minimum_stops:
		validation_errors.append("insufficient_stops")
	var seen_stops: Dictionary = {}
	var station_tile_ids: Array[int] = []
	for stop_variant: Variant in stop_ids:
		var stop_id := str(stop_variant)
		if seen_stops.has(stop_id):
			validation_errors.append("duplicate_stop:%s" % stop_id)
			continue
		seen_stops[stop_id] = true
		if not stations.has(stop_id):
			validation_errors.append("station_not_found:%s" % stop_id)
			continue
		var station: Dictionary = stations[stop_id]
		station_tile_ids.append(int(station.get("tile_id", -1)))
		if str(station.get("building_name", "")) != str(mode_spec.get("station_name", "")):
			validation_errors.append("incompatible_station:%s" % stop_id)

	var path_tile_ids: Array[int] = []
	if validation_errors.is_empty():
		if mode == "air":
			var air_result := _validate_air_route(stop_ids)
			path_tile_ids = air_result.get("path_tile_ids", [])
			validation_errors.append_array(air_result.get("errors", []))
		else:
			var guideway_kind := str(mode_spec.get("guideway_kind", ""))
			var path_result := _path_for_ordered_stops(guideway_kind, stop_ids)
			path_tile_ids = path_result.get("path_tile_ids", [])
			validation_errors.append_array(path_result.get("errors", []))
			if validation_errors.is_empty():
				var depot_kind := str(mode_spec.get("required_depot_kind", ""))
				if not _has_connected_depot(depot_kind, guideway_kind, path_tile_ids):
					validation_errors.append("connected_depot_required:%s" % depot_kind)
	if int(normalized.get("fleet_size", 0)) < 1:
		validation_errors.append("fleet_required")
	if int(normalized.get("headway_minutes", 0)) < 1:
		validation_errors.append("invalid_headway")
	if int(normalized.get("fare", 0)) < 0:
		validation_errors.append("invalid_fare")

	var valid := validation_errors.is_empty()
	return {
		"ok": true,
		"valid": valid,
		"validation_errors": validation_errors,
		"path_tile_ids": path_tile_ids,
		"station_tile_ids": station_tile_ids,
		"vehicle_kind": str(mode_spec.get("vehicle_kind", "")),
		"loop_seconds": float(mode_spec.get("loop_seconds", 10.0)),
		"route": normalized,
	}


func create_route(route_plan: Dictionary) -> Dictionary:
	var quote := route_quote(route_plan)
	if not bool(quote.get("ok", false)):
		return quote
	var normalized: Dictionary = quote.get("route", {})
	var route_id := str(normalized.get("id", ""))
	if route_id.is_empty():
		route_id = "route_%06d" % next_route_sequence
		next_route_sequence += 1
	if routes.has(route_id):
		return _error("route_id_exists")
	var enabled := bool(normalized.get("enabled", false))
	var record := normalized.duplicate(true)
	record["id"] = route_id
	record["path_tile_ids"] = Array(quote.get("path_tile_ids", [])).duplicate()
	record["station_tile_ids"] = Array(quote.get("station_tile_ids", [])).duplicate()
	record["vehicle_kind"] = str(quote.get("vehicle_kind", ""))
	record["loop_seconds"] = float(quote.get("loop_seconds", 10.0))
	record["validation_errors"] = Array(quote.get("validation_errors", [])).duplicate()
	record["status"] = _route_status(bool(quote.get("valid", false)), enabled)
	routes[route_id] = record
	return {"ok": true, "valid": bool(quote.get("valid", false)), "route": record.duplicate(true)}


func toggle_route(route_id: String, enabled: bool) -> Dictionary:
	if not routes.has(route_id):
		return _error("route_not_found")
	var route: Dictionary = routes[route_id]
	route["enabled"] = enabled
	routes[route_id] = route
	revalidate_routes()
	return {"ok": true, "route": Dictionary(routes[route_id]).duplicate(true)}


func revalidate_routes() -> Array[Dictionary]:
	var changed: Array[Dictionary] = []
	for route_id: String in _sorted_string_keys(routes):
		var route: Dictionary = routes[route_id]
		var before_status := str(route.get("status", ""))
		var quote := route_quote(route)
		var valid := bool(quote.get("valid", false))
		route["path_tile_ids"] = Array(quote.get("path_tile_ids", [])).duplicate()
		route["station_tile_ids"] = Array(quote.get("station_tile_ids", [])).duplicate()
		route["vehicle_kind"] = str(quote.get("vehicle_kind", ""))
		route["loop_seconds"] = float(quote.get("loop_seconds", route.get("loop_seconds", 10.0)))
		route["validation_errors"] = Array(quote.get("validation_errors", [])).duplicate()
		route["status"] = _route_status(valid, bool(route.get("enabled", false)))
		routes[route_id] = route
		if str(route.get("status", "")) != before_status:
			changed.append(route.duplicate(true))
	return changed


func active_lines() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for route_id: String in _sorted_string_keys(routes):
		var route: Dictionary = routes[route_id]
		if str(route.get("status", "")) == "operational":
			result.append(route.duplicate(true))
	return result


func register_station(station_id: String, building_name: String, tile_id: int) -> Dictionary:
	if station_id.is_empty():
		return _error("station_id_required")
	if not TransportModesScript.STATION_KINDS.has(building_name):
		return _error("invalid_station_kind")
	if not _topology_map.is_valid_tile_id(tile_id):
		return _error("invalid_tile_id")
	stations[station_id] = {
		"id": station_id,
		"building_name": building_name,
		"tile_id": tile_id,
		"status": "completed",
		"project_id": "external",
	}
	revalidate_routes()
	return {"ok": true, "station": Dictionary(stations[station_id]).duplicate(true)}


func unregister_station(station_id: String) -> bool:
	if not stations.erase(station_id):
		return false
	revalidate_routes()
	return true


func tile_visual_state(tile_id: int, terrain_map: Variant) -> Dictionary:
	var visible_segments := _visible_segment_kinds_by_tile()
	var visible_facilities := _visible_facility_kinds_by_tile()
	var segment_values: Array[String] = []
	for value_variant: Variant in Array(visible_segments.get(tile_id, [])):
		segment_values.append(str(value_variant))
	segment_values.sort()
	var facility_values: Array[String] = []
	for value_variant: Variant in Array(visible_facilities.get(tile_id, [])):
		facility_values.append(str(value_variant))
	facility_values.sort()
	var connections: Dictionary = {}
	for kind: String in segment_values:
		var directions: Array[String] = []
		var kind_tiles := _visible_tiles_for_kind(kind, visible_segments)
		for direction: String in TransportModesScript.CONNECTION_DIRECTIONS:
			var neighbor := _neighbor_in_direction(tile_id, direction, terrain_map)
			if neighbor >= 0 and kind_tiles.has(neighbor):
				directions.append(direction)
		connections[kind] = directions
	var crossing_kind := ""
	if _tile_has_visible_crossing(tile_id, visible_segments):
		crossing_kind = TransportModesScript.CROSSING_KIND
	return {
		"segments": segment_values,
		"facilities": facility_values,
		"crossing": crossing_kind,
		"connections": connections,
		"project_status": _project_status_for_tile(tile_id),
	}


func visual_runtime_snapshot(city_grid: Array, terrain_map: Variant) -> Dictionary:
	var tile_id_set: Dictionary = {}
	var visible_segments := _visible_segment_kinds_by_tile()
	var visible_facilities := _visible_facility_kinds_by_tile()
	for tile_variant: Variant in visible_segments.keys():
		tile_id_set[int(tile_variant)] = true
	for tile_variant: Variant in visible_facilities.keys():
		tile_id_set[int(tile_variant)] = true
	for crossing_variant: Variant in crossings.values():
		var crossing: Dictionary = crossing_variant
		tile_id_set[int(crossing.get("tile_id", -1))] = true
	var tile_ids: Array[int] = []
	for tile_variant: Variant in tile_id_set.keys():
		var tile_id := int(tile_variant)
		if tile_id >= 0:
			tile_ids.append(tile_id)
	tile_ids.sort()
	var tile_states: Dictionary = {}
	for tile_id: int in tile_ids:
		tile_states[str(tile_id)] = tile_visual_state(tile_id, terrain_map)
	return {
		"tile_states": tile_states,
		"operational_lines": active_lines(),
		"private_road_paths": private_road_paths(city_grid, terrain_map),
		"crossings": crossings.duplicate(true),
	}


func network_snapshot_per_tile(city_grid: Array, terrain_map: Variant) -> Dictionary:
	return visual_runtime_snapshot(city_grid, terrain_map)


func navigation_blocker_ids() -> Array[int]:
	var blocker_set: Dictionary = {}
	for record_variant: Variant in segments.values():
		var segment: Dictionary = record_variant
		var spec := TransportModesScript.segment_spec(str(segment.get("kind", "")))
		if bool(spec.get("navigation_blocker", false)):
			for tile_variant: Variant in Array(segment.get("tile_path", [])):
				blocker_set[int(tile_variant)] = true
	for record_variant: Variant in facilities.values():
		var facility: Dictionary = record_variant
		var spec := TransportModesScript.facility_spec(str(facility.get("kind", "")))
		if bool(spec.get("navigation_blocker", false)):
			blocker_set[int(facility.get("tile_id", -1))] = true
	for record_variant: Variant in stations.values():
		var station: Dictionary = record_variant
		blocker_set[int(station.get("tile_id", -1))] = true
	for project_variant: Variant in projects.values():
		var project: Dictionary = project_variant
		if str(project.get("status", "")) != "under_construction":
			continue
		for tile_id: int in _project_tile_ids(project):
			blocker_set[tile_id] = true
	var result: Array[int] = []
	for tile_variant: Variant in blocker_set.keys():
		var tile_id := int(tile_variant)
		if tile_id >= 0:
			result.append(tile_id)
	result.sort()
	return result


func monthly_maintenance() -> int:
	var total := 0
	for record_variant: Variant in segments.values():
		var segment: Dictionary = record_variant
		var spec := TransportModesScript.segment_spec(str(segment.get("kind", "")))
		total += int(spec.get("monthly_maintenance_per_tile", 0)) * Array(segment.get("tile_path", [])).size()
	for record_variant: Variant in facilities.values():
		var facility: Dictionary = record_variant
		total += int(TransportModesScript.facility_spec(str(facility.get("kind", ""))).get("monthly_maintenance", 0))
	for record_variant: Variant in stations.values():
		var station: Dictionary = record_variant
		total += int(TransportModesScript.station_spec(str(station.get("building_name", ""))).get("monthly_maintenance", 0))
	total += crossings.size() * TransportModesScript.LEVEL_CROSSING_MONTHLY_MAINTENANCE
	for route: Dictionary in active_lines():
		var mode_spec := TransportModesScript.route_spec(str(route.get("mode", "")))
		total += int(route.get("fleet_size", 0)) * int(mode_spec.get("fleet_monthly_maintenance", 0))
	return total


func service_operational_factor(mode: String) -> float:
	for route: Dictionary in active_lines():
		if str(route.get("mode", "")) == mode:
			return 1.0
	return 0.0


func private_road_paths(city_grid: Array, terrain_map: Variant) -> Array[Dictionary]:
	var road_tiles := _tile_set_for_segment_kind("road")
	var components := _network_components(road_tiles, terrain_map)
	var result: Array[Dictionary] = []
	var component_sequence := 1
	for component: Array in components:
		var component_set := _tile_set(component)
		var access_tiles: Array[int] = []
		for tile_id in range(city_grid.size()):
			if str(city_grid[tile_id]).is_empty():
				continue
			for neighbor: int in _cardinal_neighbors(tile_id, terrain_map):
				if component_set.has(neighbor):
					access_tiles.append(tile_id)
					break
		if access_tiles.size() < 2:
			continue
		access_tiles.sort()
		var component_tiles: Array[int] = []
		for tile_variant: Variant in component:
			component_tiles.append(int(tile_variant))
		component_tiles.sort()
		result.append({
			"component_id": "road_component_%03d" % component_sequence,
			"tile_ids": component_tiles,
			"access_tile_ids": access_tiles,
			"access_count": access_tiles.size(),
			"active": true,
		})
		component_sequence += 1
	return result


func has_private_road_traffic(city_grid: Array, terrain_map: Variant) -> bool:
	return not private_road_paths(city_grid, terrain_map).is_empty()


func network_snapshot() -> Dictionary:
	return {
		"segments": segments.duplicate(true),
		"facilities": facilities.duplicate(true),
		"stations": stations.duplicate(true),
		"crossings": crossings.duplicate(true),
		"routes": routes.duplicate(true),
	}


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"next_project_sequence": next_project_sequence,
		"next_segment_sequence": next_segment_sequence,
		"next_facility_sequence": next_facility_sequence,
		"next_station_sequence": next_station_sequence,
		"next_route_sequence": next_route_sequence,
		"projects": projects.duplicate(true),
		"segments": segments.duplicate(true),
		"facilities": facilities.duplicate(true),
		"stations": stations.duplicate(true),
		"crossings": crossings.duplicate(true),
		"routes": routes.duplicate(true),
	}


func load_dict(data: Dictionary) -> void:
	next_project_sequence = maxi(1, int(data.get("next_project_sequence", 1)))
	next_segment_sequence = maxi(1, int(data.get("next_segment_sequence", 1)))
	next_facility_sequence = maxi(1, int(data.get("next_facility_sequence", 1)))
	next_station_sequence = maxi(1, int(data.get("next_station_sequence", 1)))
	next_route_sequence = maxi(1, int(data.get("next_route_sequence", 1)))
	projects = _dictionary_copy(data.get("projects", {}))
	segments = _dictionary_copy(data.get("segments", {}))
	facilities = _dictionary_copy(data.get("facilities", {}))
	stations = _dictionary_copy(data.get("stations", {}))
	crossings = _dictionary_copy(data.get("crossings", {}))
	routes = _dictionary_copy(data.get("routes", {}))
	_canonicalize_loaded_state()
	_recompute_crossings()
	revalidate_routes()


static func create_from_dict(data: Dictionary):
	# Use the script resource directly so first-run headless tests do not depend
	# on Godot's editor-generated global class-name cache already containing this
	# newly added type.
	var instance = (load("res://scripts/systems/city/transport_network_system.gd") as Script).new()
	instance.load_dict(data)
	return instance


static func validate_snapshot(snapshot: Dictionary) -> Dictionary:
	var issues: Array[String] = []
	var schema_version := int(snapshot.get("schema_version", 0))
	if schema_version < 1 or schema_version > SCHEMA_VERSION:
		issues.append("unsupported_schema_version")
	if not _is_json_safe(snapshot):
		issues.append("snapshot_not_json_safe")
	var segment_records: Dictionary = snapshot.get("segments", {}) if snapshot.get("segments", {}) is Dictionary else {}
	for id_variant: Variant in segment_records.keys():
		var record_variant: Variant = segment_records[id_variant]
		if not record_variant is Dictionary:
			issues.append("segment_not_dictionary:%s" % str(id_variant))
			continue
		var record: Dictionary = record_variant
		if str(record.get("kind", "")) not in TransportModesScript.SEGMENT_KINDS:
			issues.append("unknown_segment_kind:%s" % str(id_variant))
		if not record.get("tile_path", []) is Array or Array(record.get("tile_path", [])).is_empty():
			issues.append("invalid_segment_path:%s" % str(id_variant))
	var facility_records: Dictionary = snapshot.get("facilities", {}) if snapshot.get("facilities", {}) is Dictionary else {}
	for id_variant: Variant in facility_records.keys():
		var record_variant: Variant = facility_records[id_variant]
		if not record_variant is Dictionary or str((record_variant as Dictionary).get("kind", "")) not in TransportModesScript.FACILITY_KINDS:
			issues.append("invalid_facility:%s" % str(id_variant))
	var station_records: Dictionary = snapshot.get("stations", {}) if snapshot.get("stations", {}) is Dictionary else {}
	for id_variant: Variant in station_records.keys():
		var record_variant: Variant = station_records[id_variant]
		if not record_variant is Dictionary or str((record_variant as Dictionary).get("building_name", "")) not in TransportModesScript.STATION_KINDS:
			issues.append("invalid_station:%s" % str(id_variant))
	var project_records: Dictionary = snapshot.get("projects", {}) if snapshot.get("projects", {}) is Dictionary else {}
	for id_variant: Variant in project_records.keys():
		var record_variant: Variant = project_records[id_variant]
		if not record_variant is Dictionary:
			issues.append("invalid_project:%s" % str(id_variant))
			continue
		var record: Dictionary = record_variant
		if str(record.get("operation", "")) not in TransportModesScript.PROJECT_OPERATIONS:
			issues.append("invalid_project_operation:%s" % str(id_variant))
		if str(record.get("status", "")) not in TransportModesScript.PROJECT_STATUSES:
			issues.append("invalid_project_status:%s" % str(id_variant))
	var route_records: Dictionary = snapshot.get("routes", {}) if snapshot.get("routes", {}) is Dictionary else {}
	for id_variant: Variant in route_records.keys():
		var record_variant: Variant = route_records[id_variant]
		if not record_variant is Dictionary or str((record_variant as Dictionary).get("mode", "")) not in TransportModesScript.ROUTE_MODES:
			issues.append("invalid_route:%s" % str(id_variant))
	return {"valid": issues.is_empty(), "issues": issues, "schema_version": schema_version}


func _canonicalize_loaded_state() -> void:
	# JSON.parse_string represents every JSON number as a float.  Restore the
	# integer fields owned by this schema so save -> load -> save is byte-shape
	# deterministic instead of merely numerically equivalent.
	for segment_id: String in _sorted_string_keys(segments):
		var segment: Dictionary = segments[segment_id]
		segment["tile_path"] = _int_array(segment.get("tile_path", []))
		segments[segment_id] = segment
	for facility_id: String in _sorted_string_keys(facilities):
		var facility: Dictionary = facilities[facility_id]
		facility["tile_id"] = int(facility.get("tile_id", -1))
		facilities[facility_id] = facility
	for station_id: String in _sorted_string_keys(stations):
		var station: Dictionary = stations[station_id]
		station["tile_id"] = int(station.get("tile_id", -1))
		stations[station_id] = station
	for project_id: String in _sorted_string_keys(projects):
		var project: Dictionary = projects[project_id]
		var operation := str(project.get("operation", ""))
		var plan: Dictionary = project.get("plan", {})
		plan = _normalize_build_plan(plan) if operation == "build" else _normalize_demolition_plan(plan)
		project["plan"] = plan
		project["total_cost"] = int(project.get("total_cost", 0))
		var quote: Dictionary = project.get("quote", {})
		quote["plan"] = plan.duplicate(true)
		quote["total_cost"] = int(quote.get("total_cost", project["total_cost"]))
		quote["crossing_tile_ids"] = _int_array(quote.get("crossing_tile_ids", []))
		var breakdown: Dictionary = quote.get("breakdown", {})
		for key: String in ["segments", "facilities", "stations", "level_crossings"]:
			breakdown[key] = int(breakdown.get(key, 0))
		quote["breakdown"] = breakdown
		project["quote"] = quote
		projects[project_id] = project
	for route_id: String in _sorted_string_keys(routes):
		var route: Dictionary = routes[route_id]
		route["fleet_size"] = int(route.get("fleet_size", 0))
		route["headway_minutes"] = int(route.get("headway_minutes", 0))
		route["fare"] = int(route.get("fare", 0))
		route["path_tile_ids"] = _int_array(route.get("path_tile_ids", []))
		route["station_tile_ids"] = _int_array(route.get("station_tile_ids", []))
		route["loop_seconds"] = float(route.get("loop_seconds", 10.0))
		routes[route_id] = route


func _create_project(
	operation: String,
	plan: Dictionary,
	status: String,
	terrain_map: Variant,
	occupied_tile_ids: Variant,
	construction_tile_ids: Variant
) -> Dictionary:
	var quote := quote_project(operation, plan, terrain_map, occupied_tile_ids, construction_tile_ids)
	if not bool(quote.get("ok", false)):
		return quote
	var project_id := "transport_project_%06d" % next_project_sequence
	next_project_sequence += 1
	var normalized_plan: Dictionary = quote.get("plan", {}).duplicate(true)
	if operation == "build":
		normalized_plan = _assign_build_entity_ids(normalized_plan)
	var stored_quote := quote.duplicate(true)
	stored_quote["plan"] = normalized_plan.duplicate(true)
	var project := {
		"id": project_id,
		"operation": operation,
		"status": status,
		"plan": normalized_plan,
		"quote": stored_quote,
		"total_cost": int(quote.get("total_cost", 0)),
	}
	projects[project_id] = project
	return {"ok": true, "project": project.duplicate(true), "quote": stored_quote.duplicate(true)}


func _quote_demolition(plan: Dictionary) -> Dictionary:
	var normalized := _normalize_demolition_plan(plan)
	var issues: Array[String] = []
	var segment_cost := 0
	for id_variant: Variant in normalized["segment_ids"]:
		var segment_id := str(id_variant)
		if not segments.has(segment_id):
			issues.append("segment_not_found:%s" % segment_id)
			continue
		var segment: Dictionary = segments[segment_id]
		var spec := TransportModesScript.segment_spec(str(segment.get("kind", "")))
		segment_cost += int(spec.get("demolish_cost_per_tile", 0)) * Array(segment.get("tile_path", [])).size()
	var facility_cost := 0
	for id_variant: Variant in normalized["facility_ids"]:
		var facility_id := str(id_variant)
		if not facilities.has(facility_id):
			issues.append("facility_not_found:%s" % facility_id)
			continue
		var facility: Dictionary = facilities[facility_id]
		facility_cost += int(TransportModesScript.facility_spec(str(facility.get("kind", ""))).get("demolish_cost", 0))
	var station_cost := 0
	for id_variant: Variant in normalized["station_ids"]:
		var station_id := str(id_variant)
		if not stations.has(station_id):
			issues.append("station_not_found:%s" % station_id)
			continue
		var station: Dictionary = stations[station_id]
		station_cost += int(TransportModesScript.station_spec(str(station.get("building_name", ""))).get("demolish_cost", 0))
	if normalized["segment_ids"].is_empty() and normalized["facility_ids"].is_empty() and normalized["station_ids"].is_empty():
		issues.append("demolition_targets_required")
	if not issues.is_empty():
		return {"ok": false, "error": "invalid_transport_plan", "issues": issues, "operation": "demolish", "plan": normalized}
	return {
		"ok": true,
		"operation": "demolish",
		"plan": normalized,
		"crossing_tile_ids": [],
		"breakdown": {"segments": segment_cost, "facilities": facility_cost, "stations": station_cost, "level_crossings": 0},
		"total_cost": segment_cost + facility_cost + station_cost,
	}


func _normalize_build_plan(plan: Dictionary) -> Dictionary:
	var normalized_segments: Array[Dictionary] = []
	for record_variant: Variant in _array_value(plan.get("segments", [])):
		if not record_variant is Dictionary:
			normalized_segments.append({"kind": "", "tile_path": []})
			continue
		var record: Dictionary = record_variant
		normalized_segments.append({
			"id": str(record.get("id", record.get("segment_id", ""))),
			"kind": str(record.get("kind", "")),
			"tile_path": _int_array(record.get("tile_path", record.get("tile_ids", []))),
		})
	var normalized_facilities: Array[Dictionary] = []
	for record_variant: Variant in _array_value(plan.get("facilities", [])):
		if not record_variant is Dictionary:
			normalized_facilities.append({"kind": "", "tile_id": -1})
			continue
		var record: Dictionary = record_variant
		normalized_facilities.append({
			"id": str(record.get("id", record.get("facility_id", ""))),
			"kind": str(record.get("kind", "")),
			"tile_id": int(record.get("tile_id", -1)),
		})
	var normalized_stations: Array[Dictionary] = []
	for record_variant: Variant in _array_value(plan.get("stations", [])):
		if not record_variant is Dictionary:
			normalized_stations.append({"building_name": "", "tile_id": -1})
			continue
		var record: Dictionary = record_variant
		normalized_stations.append({
			"id": str(record.get("id", record.get("station_id", ""))),
			"building_name": str(record.get("building_name", "")),
			"tile_id": int(record.get("tile_id", -1)),
		})
	return {
		"title": str(plan.get("title", "交通建設專案")),
		"source_decision_id": str(plan.get("source_decision_id", "")),
		"segments": normalized_segments,
		"facilities": normalized_facilities,
		"stations": normalized_stations,
	}


func _normalize_demolition_plan(plan: Dictionary) -> Dictionary:
	return {
		"title": str(plan.get("title", "交通拆除專案")),
		"source_decision_id": str(plan.get("source_decision_id", "")),
		"segment_ids": _string_array(plan.get("segment_ids", [])),
		"facility_ids": _string_array(plan.get("facility_ids", [])),
		"station_ids": _string_array(plan.get("station_ids", [])),
	}


func _normalize_route(route_plan: Dictionary) -> Dictionary:
	return {
		"id": str(route_plan.get("id", route_plan.get("route_id", ""))),
		"name": str(route_plan.get("name", "交通路線")),
		"mode": str(route_plan.get("mode", "")),
		"stop_ids": _string_array(route_plan.get("stop_ids", [])),
		"fleet_size": int(route_plan.get("fleet_size", 0)),
		"headway_minutes": int(route_plan.get("headway_minutes", 0)),
		"fare": int(route_plan.get("fare", 0)),
		"enabled": bool(route_plan.get("enabled", false)),
	}


func _validate_build_plan(
	plan: Dictionary,
	terrain_map: Variant,
	occupied: Dictionary,
	construction: Dictionary
) -> Array[String]:
	var issues: Array[String] = []
	var planned_by_tile: Dictionary = {}
	var existing_by_tile := _completed_segment_kinds_by_tile()
	for segment: Dictionary in plan["segments"]:
		var kind := str(segment.get("kind", ""))
		var path: Array = segment.get("tile_path", [])
		if kind not in TransportModesScript.SEGMENT_KINDS:
			issues.append("invalid_segment_kind:%s" % kind)
			continue
		if path.is_empty():
			issues.append("empty_segment_path:%s" % kind)
			continue
		if not _path_is_cardinally_contiguous(path, terrain_map):
			issues.append("non_cardinal_segment_path:%s" % kind)
		for tile_variant: Variant in path:
			var tile_id := int(tile_variant)
			_validate_build_tile(tile_id, terrain_map, occupied, construction, issues)
			var existing_kinds: Array = existing_by_tile.get(tile_id, [])
			for existing_kind_variant: Variant in existing_kinds:
				var existing_kind := str(existing_kind_variant)
				if existing_kind == kind:
					issues.append("segment_already_exists:%s:%d" % [kind, tile_id])
				elif not _segment_overlap_allowed(existing_kind, kind):
					issues.append("incompatible_segment_overlap:%s:%s:%d" % [existing_kind, kind, tile_id])
			var planned_kinds: Array = planned_by_tile.get(tile_id, [])
			for planned_kind_variant: Variant in planned_kinds:
				var planned_kind := str(planned_kind_variant)
				if planned_kind == kind:
					issues.append("duplicate_segment_tile:%s:%d" % [kind, tile_id])
				elif not _segment_overlap_allowed(planned_kind, kind):
					issues.append("incompatible_segment_overlap:%s:%s:%d" % [planned_kind, kind, tile_id])
			planned_kinds.append(kind)
			planned_by_tile[tile_id] = planned_kinds
	var structure_tiles: Dictionary = {}
	for facility: Dictionary in plan["facilities"]:
		var kind := str(facility.get("kind", ""))
		var tile_id := int(facility.get("tile_id", -1))
		if kind not in TransportModesScript.FACILITY_KINDS:
			issues.append("invalid_facility_kind:%s" % kind)
		_validate_build_tile(tile_id, terrain_map, occupied, construction, issues)
		if structure_tiles.has(tile_id) or planned_by_tile.has(tile_id):
			issues.append("transport_structure_overlap:%d" % tile_id)
		structure_tiles[tile_id] = true
	for station: Dictionary in plan["stations"]:
		var building_name := str(station.get("building_name", ""))
		var tile_id := int(station.get("tile_id", -1))
		if building_name not in TransportModesScript.STATION_KINDS:
			issues.append("invalid_station_kind:%s" % building_name)
		_validate_build_tile(tile_id, terrain_map, occupied, construction, issues)
		if structure_tiles.has(tile_id) or planned_by_tile.has(tile_id):
			issues.append("transport_structure_overlap:%d" % tile_id)
		structure_tiles[tile_id] = true
	if plan["segments"].is_empty() and plan["facilities"].is_empty() and plan["stations"].is_empty():
		issues.append("project_items_required")
	return _unique_strings(issues)


func _validate_build_tile(
	tile_id: int,
	terrain_map: Variant,
	occupied: Dictionary,
	construction: Dictionary,
	issues: Array[String]
) -> void:
	if not terrain_map.is_valid_tile_id(tile_id):
		issues.append("invalid_tile_id:%d" % tile_id)
		return
	if not terrain_map.is_buildable(tile_id):
		issues.append("terrain_not_flat:%d" % tile_id)
	if occupied.has(tile_id):
		issues.append("tile_occupied:%d" % tile_id)
	if construction.has(tile_id):
		issues.append("tile_under_construction:%d" % tile_id)


func _assign_build_entity_ids(plan: Dictionary) -> Dictionary:
	var result := plan.duplicate(true)
	var assigned_segments: Array[Dictionary] = []
	for record_variant: Variant in result.get("segments", []):
		var record: Dictionary = record_variant
		if str(record.get("id", "")).is_empty():
			record["id"] = "transport_segment_%06d" % next_segment_sequence
			next_segment_sequence += 1
		assigned_segments.append(record)
	result["segments"] = assigned_segments
	var assigned_facilities: Array[Dictionary] = []
	for record_variant: Variant in result.get("facilities", []):
		var record: Dictionary = record_variant
		if str(record.get("id", "")).is_empty():
			record["id"] = "transport_facility_%06d" % next_facility_sequence
			next_facility_sequence += 1
		assigned_facilities.append(record)
	result["facilities"] = assigned_facilities
	var assigned_stations: Array[Dictionary] = []
	for record_variant: Variant in result.get("stations", []):
		var record: Dictionary = record_variant
		if str(record.get("id", "")).is_empty():
			record["id"] = "transport_station_%06d" % next_station_sequence
			next_station_sequence += 1
		assigned_stations.append(record)
	result["stations"] = assigned_stations
	return result


func _commit_build_project(project_id: String, plan: Dictionary) -> void:
	for record_variant: Variant in plan.get("segments", []):
		var record: Dictionary = record_variant
		var segment_id := str(record.get("id", ""))
		var stored := record.duplicate(true)
		stored["status"] = "completed"
		stored["project_id"] = project_id
		segments[segment_id] = stored
	for record_variant: Variant in plan.get("facilities", []):
		var record: Dictionary = record_variant
		var facility_id := str(record.get("id", ""))
		var stored := record.duplicate(true)
		stored["status"] = "completed"
		stored["project_id"] = project_id
		facilities[facility_id] = stored
	for record_variant: Variant in plan.get("stations", []):
		var record: Dictionary = record_variant
		var station_id := str(record.get("id", ""))
		var stored := record.duplicate(true)
		stored["status"] = "completed"
		stored["project_id"] = project_id
		stations[station_id] = stored


func _commit_demolition_project(plan: Dictionary) -> void:
	for id_variant: Variant in plan.get("segment_ids", []):
		segments.erase(str(id_variant))
	for id_variant: Variant in plan.get("facility_ids", []):
		facilities.erase(str(id_variant))
	for id_variant: Variant in plan.get("station_ids", []):
		stations.erase(str(id_variant))


func _recompute_crossings() -> void:
	var by_tile := _completed_segment_kinds_by_tile()
	var rebuilt: Dictionary = {}
	var tile_ids: Array[int] = []
	for tile_variant: Variant in by_tile.keys():
		tile_ids.append(int(tile_variant))
	tile_ids.sort()
	for tile_id: int in tile_ids:
		var kinds: Array = by_tile.get(tile_id, [])
		if not kinds.has("road") or (not kinds.has("metro_track") and not kinds.has("rail_track")):
			continue
		var crossing_id := "level_crossing_%03d" % tile_id
		var track_kinds: Array[String] = []
		for track_kind: String in TRACK_KINDS:
			if kinds.has(track_kind):
				track_kinds.append(track_kind)
		rebuilt[crossing_id] = {
			"id": crossing_id,
			"kind": TransportModesScript.CROSSING_KIND,
			"tile_id": tile_id,
			"track_kinds": track_kinds,
			"status": "completed",
			"build_cost": TransportModesScript.LEVEL_CROSSING_BUILD_COST,
			"monthly_maintenance": TransportModesScript.LEVEL_CROSSING_MONTHLY_MAINTENANCE,
		}
	crossings = rebuilt


func _new_crossing_tiles_for_plan(plan: Dictionary) -> Array[int]:
	var by_tile := _completed_segment_kinds_by_tile()
	for segment: Dictionary in plan.get("segments", []):
		var kind := str(segment.get("kind", ""))
		for tile_variant: Variant in segment.get("tile_path", []):
			var tile_id := int(tile_variant)
			var kinds: Array = by_tile.get(tile_id, [])
			if not kinds.has(kind):
				kinds.append(kind)
			by_tile[tile_id] = kinds
	var result: Array[int] = []
	for tile_variant: Variant in by_tile.keys():
		var tile_id := int(tile_variant)
		var kinds: Array = by_tile[tile_variant]
		var crossing_id := "level_crossing_%03d" % tile_id
		if kinds.has("road") and (kinds.has("metro_track") or kinds.has("rail_track")) and not crossings.has(crossing_id):
			result.append(tile_id)
	result.sort()
	return result


func _path_for_ordered_stops(guideway_kind: String, stop_ids: Array) -> Dictionary:
	var errors: Array[String] = []
	var guideway_tiles := _tile_set_for_segment_kind(guideway_kind)
	var full_path: Array[int] = []
	for index in range(stop_ids.size() - 1):
		var from_id := str(stop_ids[index])
		var to_id := str(stop_ids[index + 1])
		var from_station: Dictionary = stations.get(from_id, {})
		var to_station: Dictionary = stations.get(to_id, {})
		var starts := _network_attachments(int(from_station.get("tile_id", -1)), guideway_tiles, _topology_map)
		var goals := _network_attachments(int(to_station.get("tile_id", -1)), guideway_tiles, _topology_map)
		if starts.is_empty():
			errors.append("station_not_connected:%s" % from_id)
			continue
		if goals.is_empty():
			errors.append("station_not_connected:%s" % to_id)
			continue
		var path := _shortest_path_between_sets(guideway_tiles, starts, _tile_set(goals), _topology_map)
		if path.is_empty():
			errors.append("stops_disconnected:%s:%s" % [from_id, to_id])
			continue
		if full_path.is_empty():
			full_path.append_array(path)
		else:
			for path_index in range(1, path.size()):
				full_path.append(int(path[path_index]))
	return {"path_tile_ids": full_path, "errors": _unique_strings(errors)}


func _has_connected_depot(depot_kind: String, guideway_kind: String, path_tile_ids: Array) -> bool:
	if depot_kind.is_empty() or path_tile_ids.is_empty():
		return false
	var guideway_tiles := _tile_set_for_segment_kind(guideway_kind)
	var path_set := _tile_set(path_tile_ids)
	for record_variant: Variant in facilities.values():
		var facility: Dictionary = record_variant
		if str(facility.get("kind", "")) != depot_kind:
			continue
		var starts := _network_attachments(int(facility.get("tile_id", -1)), guideway_tiles, _topology_map)
		if starts.is_empty():
			continue
		if not _shortest_path_between_sets(guideway_tiles, starts, path_set, _topology_map).is_empty():
			return true
	return false


func _validate_air_route(stop_ids: Array) -> Dictionary:
	var errors: Array[String] = []
	if stop_ids.is_empty():
		return {"path_tile_ids": [], "errors": ["airport_required"]}
	var airport: Dictionary = stations.get(str(stop_ids[0]), {})
	var airport_tile := int(airport.get("tile_id", -1))
	var road_tiles := _tile_set_for_segment_kind("road")
	if _network_attachments(airport_tile, road_tiles, _topology_map).is_empty():
		errors.append("airport_road_access_required")
	var taxiway_tiles := _tile_set_for_segment_kind("taxiway")
	var taxi_starts := _network_attachments(airport_tile, taxiway_tiles, _topology_map)
	if taxi_starts.is_empty():
		errors.append("airport_taxiway_required")
	var valid_runways: Array[Dictionary] = []
	for segment_id: String in _sorted_string_keys(segments):
		var segment: Dictionary = segments[segment_id]
		if str(segment.get("kind", "")) != "runway":
			continue
		var path: Array = segment.get("tile_path", [])
		if path.size() >= 3 and _path_is_straight(path, _topology_map):
			valid_runways.append(segment)
	if valid_runways.is_empty():
		errors.append("runway_length_required")
	return _air_path_result(valid_runways, taxiway_tiles, taxi_starts, errors)


func _air_path_result(
	valid_runways: Array[Dictionary],
	taxiway_tiles: Dictionary,
	taxi_starts: Array[int],
	errors: Array[String]
) -> Dictionary:
	if not errors.is_empty():
		return {"path_tile_ids": [], "errors": _unique_strings(errors)}
	for runway: Dictionary in valid_runways:
		var runway_path: Array = runway.get("tile_path", [])
		var taxi_goals: Dictionary = {}
		# A taxiway joins a runway at an endpoint.  This makes the published air
		# route a single cardinally contiguous polyline suitable for rendering;
		# appending an arbitrary authored runway order could otherwise teleport a
		# plane from the taxiway to the far end of the runway.
		for runway_tile_variant: Variant in [runway_path.front(), runway_path.back()]:
			var runway_tile := int(runway_tile_variant)
			for neighbor: int in _cardinal_neighbors(runway_tile, _topology_map):
				if taxiway_tiles.has(neighbor):
					taxi_goals[neighbor] = true
		var taxi_path := _shortest_path_between_sets(taxiway_tiles, taxi_starts, taxi_goals, _topology_map)
		if taxi_path.is_empty():
			continue
		var taxi_end := int(taxi_path.back())
		var ordered_runway: Array[int] = _int_array(runway_path)
		if not _cardinal_neighbors(taxi_end, _topology_map).has(int(ordered_runway.front())):
			ordered_runway.reverse()
		var result: Array[int] = []
		result.append_array(taxi_path)
		for runway_tile_variant: Variant in ordered_runway:
			result.append(int(runway_tile_variant))
		return {"path_tile_ids": result, "errors": []}
	return {"path_tile_ids": [], "errors": ["taxiway_runway_disconnected"]}


func _route_status(valid: bool, enabled: bool) -> String:
	if valid and enabled:
		return "operational"
	if valid:
		return "disabled"
	return "suspended" if enabled else "invalid"


func _completed_segment_kinds_by_tile() -> Dictionary:
	var result: Dictionary = {}
	for record_variant: Variant in segments.values():
		var segment: Dictionary = record_variant
		var kind := str(segment.get("kind", ""))
		for tile_variant: Variant in Array(segment.get("tile_path", [])):
			var tile_id := int(tile_variant)
			var kinds: Array = result.get(tile_id, [])
			if not kinds.has(kind):
				kinds.append(kind)
			result[tile_id] = kinds
	return result


func _visible_segment_kinds_by_tile() -> Dictionary:
	var result := _completed_segment_kinds_by_tile()
	for project_variant: Variant in projects.values():
		var project: Dictionary = project_variant
		if str(project.get("operation", "")) != "build" or str(project.get("status", "")) not in ["planned", "under_construction"]:
			continue
		for segment_variant: Variant in Dictionary(project.get("plan", {})).get("segments", []):
			var segment: Dictionary = segment_variant
			var kind := str(segment.get("kind", ""))
			for tile_variant: Variant in Array(segment.get("tile_path", [])):
				var tile_id := int(tile_variant)
				var kinds: Array = result.get(tile_id, [])
				if not kinds.has(kind):
					kinds.append(kind)
				result[tile_id] = kinds
	return result


func _visible_facility_kinds_by_tile() -> Dictionary:
	var result: Dictionary = {}
	for record_variant: Variant in facilities.values():
		var facility: Dictionary = record_variant
		var tile_id := int(facility.get("tile_id", -1))
		var kinds: Array = result.get(tile_id, [])
		kinds.append(str(facility.get("kind", "")))
		result[tile_id] = kinds
	for project_variant: Variant in projects.values():
		var project: Dictionary = project_variant
		if str(project.get("operation", "")) != "build" or str(project.get("status", "")) not in ["planned", "under_construction"]:
			continue
		for facility_variant: Variant in Dictionary(project.get("plan", {})).get("facilities", []):
			var facility: Dictionary = facility_variant
			var tile_id := int(facility.get("tile_id", -1))
			var kinds: Array = result.get(tile_id, [])
			kinds.append(str(facility.get("kind", "")))
			result[tile_id] = kinds
	return result


func _visible_tiles_for_kind(kind: String, by_tile: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for tile_variant: Variant in by_tile.keys():
		if Array(by_tile[tile_variant]).has(kind):
			result[int(tile_variant)] = true
	return result


func _tile_has_visible_crossing(tile_id: int, by_tile: Dictionary) -> bool:
	var kinds: Array = by_tile.get(tile_id, [])
	return kinds.has("road") and (kinds.has("metro_track") or kinds.has("rail_track"))


func _project_status_for_tile(tile_id: int) -> String:
	var best_status := ""
	for project_variant: Variant in projects.values():
		var project: Dictionary = project_variant
		if not _project_tile_ids(project).has(tile_id):
			continue
		var status := str(project.get("status", ""))
		if int(PROJECT_STATUS_PRIORITY.get(status, 0)) > int(PROJECT_STATUS_PRIORITY.get(best_status, 0)):
			best_status = status
	return best_status


func _project_tile_ids(project: Dictionary) -> Array[int]:
	var result_set: Dictionary = {}
	var plan: Dictionary = project.get("plan", {})
	if str(project.get("operation", "")) == "build":
		for segment_variant: Variant in plan.get("segments", []):
			for tile_variant: Variant in Dictionary(segment_variant).get("tile_path", []):
				result_set[int(tile_variant)] = true
		for facility_variant: Variant in plan.get("facilities", []):
			result_set[int(Dictionary(facility_variant).get("tile_id", -1))] = true
		for station_variant: Variant in plan.get("stations", []):
			result_set[int(Dictionary(station_variant).get("tile_id", -1))] = true
	else:
		for id_variant: Variant in plan.get("segment_ids", []):
			var segment: Dictionary = segments.get(str(id_variant), {})
			for tile_variant: Variant in segment.get("tile_path", []):
				result_set[int(tile_variant)] = true
		for id_variant: Variant in plan.get("facility_ids", []):
			var facility: Dictionary = facilities.get(str(id_variant), {})
			result_set[int(facility.get("tile_id", -1))] = true
		for id_variant: Variant in plan.get("station_ids", []):
			var station: Dictionary = stations.get(str(id_variant), {})
			result_set[int(station.get("tile_id", -1))] = true
	var result: Array[int] = []
	for tile_variant: Variant in result_set.keys():
		var tile_id := int(tile_variant)
		if tile_id >= 0:
			result.append(tile_id)
	result.sort()
	return result


func _active_project_tile_set() -> Dictionary:
	var result: Dictionary = {}
	for project_variant: Variant in projects.values():
		var project: Dictionary = project_variant
		if str(project.get("status", "")) not in ["planned", "under_construction"]:
			continue
		for tile_id: int in _project_tile_ids(project):
			result[tile_id] = true
	return result


func _tile_set_for_segment_kind(kind: String) -> Dictionary:
	var result: Dictionary = {}
	for record_variant: Variant in segments.values():
		var segment: Dictionary = record_variant
		if str(segment.get("kind", "")) != kind:
			continue
		for tile_variant: Variant in Array(segment.get("tile_path", [])):
			result[int(tile_variant)] = true
	return result


func _network_attachments(tile_id: int, network_tiles: Dictionary, terrain_map: Variant) -> Array[int]:
	var result: Array[int] = []
	if network_tiles.has(tile_id):
		result.append(tile_id)
	for neighbor: int in _cardinal_neighbors(tile_id, terrain_map):
		if network_tiles.has(neighbor) and not result.has(neighbor):
			result.append(neighbor)
	result.sort()
	return result


func _shortest_path_between_sets(
	network_tiles: Dictionary,
	starts: Array,
	goals: Dictionary,
	terrain_map: Variant
) -> Array[int]:
	if starts.is_empty() or goals.is_empty():
		return []
	var ordered_starts: Array[int] = []
	for value_variant: Variant in starts:
		var value := int(value_variant)
		if network_tiles.has(value) and not ordered_starts.has(value):
			ordered_starts.append(value)
	ordered_starts.sort()
	var queue: Array[int] = []
	var previous: Dictionary = {}
	for start: int in ordered_starts:
		queue.append(start)
		previous[start] = -1
	var cursor := 0
	var end_tile := -1
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		if goals.has(current):
			end_tile = current
			break
		for neighbor: int in _cardinal_neighbors(current, terrain_map):
			if not network_tiles.has(neighbor) or previous.has(neighbor):
				continue
			previous[neighbor] = current
			queue.append(neighbor)
	if end_tile < 0:
		return []
	var result: Array[int] = []
	var current := end_tile
	while current >= 0:
		result.push_front(current)
		current = int(previous.get(current, -1))
	return result


func _network_components(network_tiles: Dictionary, terrain_map: Variant) -> Array[Array]:
	var result: Array[Array] = []
	var remaining := network_tiles.duplicate()
	var ordered_tiles: Array[int] = []
	for tile_variant: Variant in remaining.keys():
		ordered_tiles.append(int(tile_variant))
	ordered_tiles.sort()
	for seed: int in ordered_tiles:
		if not remaining.has(seed):
			continue
		var component: Array = []
		var queue: Array[int] = [seed]
		remaining.erase(seed)
		var cursor := 0
		while cursor < queue.size():
			var current := queue[cursor]
			cursor += 1
			component.append(current)
			for neighbor: int in _cardinal_neighbors(current, terrain_map):
				if remaining.has(neighbor):
					remaining.erase(neighbor)
					queue.append(neighbor)
		component.sort()
		result.append(component)
	return result


func _cardinal_neighbors(tile_id: int, terrain_map: Variant) -> Array[int]:
	var result: Array[int] = []
	if terrain_map == null or not terrain_map.is_valid_tile_id(tile_id):
		return result
	var coordinate: Vector2i = terrain_map.coordinate_for_tile_id(tile_id)
	for offset: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var neighbor := int(terrain_map.tile_id_for_coordinate(coordinate + offset))
		if neighbor >= 0:
			result.append(neighbor)
	return result


func _neighbor_in_direction(tile_id: int, direction: String, terrain_map: Variant) -> int:
	if terrain_map == null or not terrain_map.is_valid_tile_id(tile_id):
		return -1
	var offsets := {
		"n": Vector2i(0, -1),
		"e": Vector2i(1, 0),
		"s": Vector2i(0, 1),
		"w": Vector2i(-1, 0),
	}
	if not offsets.has(direction):
		return -1
	var coordinate: Vector2i = terrain_map.coordinate_for_tile_id(tile_id)
	return int(terrain_map.tile_id_for_coordinate(coordinate + Vector2i(offsets[direction])))


func _path_is_cardinally_contiguous(path: Array, terrain_map: Variant) -> bool:
	if path.is_empty():
		return false
	var seen: Dictionary = {}
	for index in range(path.size()):
		var tile_id := int(path[index])
		if not terrain_map.is_valid_tile_id(tile_id) or seen.has(tile_id):
			return false
		seen[tile_id] = true
		if index > 0:
			var previous := int(path[index - 1])
			if not _cardinal_neighbors(previous, terrain_map).has(tile_id):
				return false
	return true


func _path_is_straight(path: Array, terrain_map: Variant) -> bool:
	if path.size() < 2 or not _path_is_cardinally_contiguous(path, terrain_map):
		return false
	var first: Vector2i = terrain_map.coordinate_for_tile_id(int(path[0]))
	var second: Vector2i = terrain_map.coordinate_for_tile_id(int(path[1]))
	var direction := second - first
	for index in range(2, path.size()):
		var previous: Vector2i = terrain_map.coordinate_for_tile_id(int(path[index - 1]))
		var current: Vector2i = terrain_map.coordinate_for_tile_id(int(path[index]))
		if current - previous != direction:
			return false
	return true


func _segment_overlap_allowed(first_kind: String, second_kind: String) -> bool:
	return (
		(first_kind == "road" and second_kind in TRACK_KINDS)
		or (second_kind == "road" and first_kind in TRACK_KINDS)
	)


func _tile_set(source: Variant) -> Dictionary:
	var result: Dictionary = {}
	if source is Dictionary:
		for key_variant: Variant in (source as Dictionary).keys():
			result[int(str(key_variant))] = true
	elif source is Array:
		for value_variant: Variant in source:
			result[int(value_variant)] = true
	elif source is PackedInt32Array:
		for value: int in source:
			result[value] = true
	return result


func _int_array(source: Variant) -> Array[int]:
	var result: Array[int] = []
	if source is Array or source is PackedInt32Array:
		for value_variant: Variant in source:
			result.append(int(value_variant))
	return result


func _string_array(source: Variant) -> Array[String]:
	var result: Array[String] = []
	if source is Array or source is PackedStringArray:
		for value_variant: Variant in source:
			result.append(str(value_variant))
	return result


func _array_value(source: Variant) -> Array:
	return source if source is Array else []


func _unique_strings(source: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for value: String in source:
		if not result.has(value):
			result.append(value)
	return result


func _sorted_string_keys(source: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key_variant: Variant in source.keys():
		result.append(str(key_variant))
	result.sort()
	return result


func _dictionary_copy(source: Variant) -> Dictionary:
	return Dictionary(source).duplicate(true) if source is Dictionary else {}


static func _is_json_safe(value: Variant) -> bool:
	if value == null or value is bool or value is int or value is float or value is String:
		return true
	if value is Array:
		for item: Variant in value:
			if not _is_json_safe(item):
				return false
		return true
	if value is Dictionary:
		for key_variant: Variant in value.keys():
			if not key_variant is String:
				return false
			if not _is_json_safe(value[key_variant]):
				return false
		return true
	return false


static func _error(code: String) -> Dictionary:
	return {"ok": false, "error": code}
