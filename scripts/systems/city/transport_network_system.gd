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
		return _quote_demolition(plan, construction_tile_ids)
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
		var demolition_issues := _demolition_target_issues(_normalize_demolition_plan(plan))
		if not demolition_issues.is_empty():
			return {
				"ok": false,
				"error": "invalid_transport_plan",
				"issues": demolition_issues,
				"operation": operation,
				"plan": plan.duplicate(true),
			}
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
			path_tile_ids = _int_array(air_result.get("path_tile_ids", []))
			validation_errors.append_array(air_result.get("errors", []))
		else:
			var guideway_kind := str(mode_spec.get("guideway_kind", ""))
			var path_result := _path_for_ordered_stops(guideway_kind, stop_ids)
			path_tile_ids = _int_array(path_result.get("path_tile_ids", []))
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
	next_route_sequence = _sequence_ahead_of_reserved_id(route_id, "route_", next_route_sequence)
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


func delete_route(route_id: String) -> Dictionary:
	if not routes.has(route_id):
		return _error("route_not_found")
	var removed: Dictionary = Dictionary(routes[route_id]).duplicate(true)
	routes.erase(route_id)
	return {"ok": true, "route": removed}


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
	var reserved_ids := _active_and_live_build_entity_ids()
	var updating_external := (
		stations.has(station_id)
		and stations[station_id] is Dictionary
		and str(Dictionary(stations[station_id]).get("project_id", "")) == "external"
	)
	if reserved_ids.has(station_id) and not updating_external:
		return _error("station_id_exists")
	for segment_variant: Variant in segments.values():
		if segment_variant is Dictionary and Array((segment_variant as Dictionary).get("tile_path", [])).has(tile_id):
			return _error("station_tile_occupied")
	for facility_variant: Variant in facilities.values():
		if facility_variant is Dictionary and int((facility_variant as Dictionary).get("tile_id", -1)) == tile_id:
			return _error("station_tile_occupied")
	for other_station_id: String in _sorted_string_keys(stations):
		if other_station_id == station_id:
			continue
		var other_station: Dictionary = stations[other_station_id]
		if int(other_station.get("tile_id", -1)) == tile_id:
			return _error("station_tile_occupied")
	next_station_sequence = _sequence_ahead_of_reserved_id(
		station_id, "transport_station_", next_station_sequence
	)
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
	var neighbours: Dictionary = {}
	for kind: String in segment_values:
		var directions: Array[String] = []
		var kind_tiles := _visible_tiles_for_kind(kind, visible_segments)
		for direction: String in TransportModesScript.CONNECTION_DIRECTIONS:
			var neighbor := _neighbor_in_direction(tile_id, direction, terrain_map)
			if neighbor >= 0 and kind_tiles.has(neighbor):
				directions.append(direction)
				neighbours[direction] = neighbor
		connections[kind] = directions
	var crossing_kind := ""
	if _tile_has_visible_crossing(tile_id, visible_segments):
		crossing_kind = TransportModesScript.CROSSING_KIND
	return {
		"segments": segment_values,
		"facilities": facility_values,
		"crossing": crossing_kind,
		"connections": connections,
		"neighbours": neighbours,
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


func incremental_monthly_maintenance() -> int:
	# Buildings registered by the city grid already contribute their maintenance
	# through CitySimulationService.  Keep monthly_maintenance() as the complete
	# transport ledger while exposing a non-duplicating value for composition
	# with that existing municipal-building ledger.
	var total := monthly_maintenance()
	for record_variant: Variant in stations.values():
		var station: Dictionary = record_variant
		if str(station.get("project_id", "")) != "external":
			continue
		total -= int(TransportModesScript.station_spec(str(station.get("building_name", ""))).get("monthly_maintenance", 0))
	return maxi(0, total)


func service_revenue(mode: String, population: int, service_definition: Dictionary) -> int:
	if mode not in TransportModesScript.ROUTE_MODES:
		return 0
	var route_spec := TransportModesScript.route_spec(mode)
	var expected_station_name := str(route_spec.get("station_name", ""))
	var base_uses := maxf(0.0, float(service_definition.get("base_uses", 0.0)))
	var reasonable_fare := maxf(1.0, float(service_definition.get("reasonable", 1.0)))
	var reference_headway := maxf(1.0, float(service_definition.get("reference_headway_minutes", 10.0)))
	var total := 0.0
	for route: Dictionary in active_lines():
		if str(route.get("mode", "")) != mode:
			continue
		var served_stop_ids: Dictionary = {}
		for stop_variant: Variant in Array(route.get("stop_ids", [])):
			var stop_id := str(stop_variant)
			if served_stop_ids.has(stop_id) or not stations.has(stop_id):
				continue
			var station: Dictionary = stations[stop_id]
			if str(station.get("building_name", "")) != expected_station_name:
				continue
			served_stop_ids[stop_id] = true
		if served_stop_ids.is_empty():
			continue
		var fare := maxi(0, int(route.get("fare", 0)))
		var fleet_size := maxi(0, int(route.get("fleet_size", 0)))
		var headway_minutes := maxi(1, int(route.get("headway_minutes", 0)))
		if fare <= 0 or fleet_size <= 0:
			continue
		var fare_ratio := float(fare) / reasonable_fare
		var demand_factor := 1.0
		if fare_ratio > 1.75:
			demand_factor = 0.58
		elif fare_ratio > 1.25:
			demand_factor = 0.78
		elif fare_ratio < 0.5:
			demand_factor = 1.18
		var frequency_factor := clampf(reference_headway / float(headway_minutes), 0.25, 2.0)
		var uses_per_stop := base_uses + float(maxi(0, population)) * 0.08
		var served_uses := uses_per_stop * float(served_stop_ids.size()) * float(fleet_size) * frequency_factor
		total += served_uses * float(fare) * demand_factor
	return int(round(total))


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
		var vehicle_path: Array[int] = []
		for start_index in range(access_tiles.size() - 1):
			var starts := _network_attachments(access_tiles[start_index], component_set, terrain_map)
			for end_index in range(start_index + 1, access_tiles.size()):
				var goal_set := _tile_set(_network_attachments(access_tiles[end_index], component_set, terrain_map))
				var candidate := _shortest_path_between_sets(component_set, starts, goal_set, terrain_map)
				if candidate.size() > vehicle_path.size():
					vehicle_path = candidate
		if vehicle_path.size() < 2:
			continue
		var component_tiles: Array[int] = []
		for tile_variant: Variant in component:
			component_tiles.append(int(tile_variant))
		component_tiles.sort()
		result.append({
			"component_id": "road_component_%03d" % component_sequence,
			"tile_ids": component_tiles,
			"path_tile_ids": vehicle_path,
			"access_tile_ids": access_tiles,
			"access_count": access_tiles.size(),
			"active": true,
			"operational": true,
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
	var schema_value: Variant = snapshot.get("schema_version", null)
	var schema_version := int(schema_value) if _is_integer_value(schema_value) else -1
	if not _is_integer_value(schema_value):
		issues.append("invalid_schema_version_type")
	elif schema_version != SCHEMA_VERSION:
		issues.append("unsupported_schema_version")
	if not _is_json_safe(snapshot):
		issues.append("snapshot_not_json_safe")
	for field_name: String in ["projects", "segments", "facilities", "stations", "crossings", "routes"]:
		if not snapshot.has(field_name):
			issues.append("missing_snapshot_field:%s" % field_name)
		elif not snapshot[field_name] is Dictionary:
			issues.append("%s_not_dictionary" % field_name)
	var project_records: Dictionary = snapshot.get("projects", {}) if snapshot.get("projects", {}) is Dictionary else {}
	var segment_records: Dictionary = snapshot.get("segments", {}) if snapshot.get("segments", {}) is Dictionary else {}
	var facility_records: Dictionary = snapshot.get("facilities", {}) if snapshot.get("facilities", {}) is Dictionary else {}
	var station_records: Dictionary = snapshot.get("stations", {}) if snapshot.get("stations", {}) is Dictionary else {}
	var crossing_records: Dictionary = snapshot.get("crossings", {}) if snapshot.get("crossings", {}) is Dictionary else {}
	var route_records: Dictionary = snapshot.get("routes", {}) if snapshot.get("routes", {}) is Dictionary else {}
	var topology_map = CityTerrainMapScript.new()
	var active_plan_ids := _snapshot_active_build_plan_ids(project_records)
	_append_snapshot_sequence_issues(issues, snapshot, "next_project_sequence", project_records, "transport_project_")
	_append_snapshot_sequence_issues(
		issues, snapshot, "next_segment_sequence", segment_records, "transport_segment_",
		active_plan_ids.get("segments", [])
	)
	_append_snapshot_sequence_issues(
		issues, snapshot, "next_facility_sequence", facility_records, "transport_facility_",
		active_plan_ids.get("facilities", [])
	)
	_append_snapshot_sequence_issues(
		issues, snapshot, "next_station_sequence", station_records, "transport_station_",
		active_plan_ids.get("stations", [])
	)
	_append_snapshot_sequence_issues(issues, snapshot, "next_route_sequence", route_records, "route_")
	for id_variant: Variant in segment_records.keys():
		var record_variant: Variant = segment_records[id_variant]
		if not record_variant is Dictionary:
			issues.append("segment_not_dictionary:%s" % str(id_variant))
			continue
		var record: Dictionary = record_variant
		_append_missing_record_fields(issues, "segment", id_variant, record, ["id", "kind", "tile_path", "status", "project_id"])
		_append_snapshot_record_identity_issue(issues, "segment", id_variant, record)
		if not record.get("kind", null) is String or str(record.get("kind", "")) not in TransportModesScript.SEGMENT_KINDS:
			issues.append("unknown_segment_kind:%s" % str(id_variant))
		_validate_snapshot_tile_array(
			record.get("tile_path", null), issues, "segment_path:%s" % str(id_variant), false, true, true,
			topology_map
		)
		if not record.get("status", null) is String or str(record.get("status", "")).is_empty():
			issues.append("invalid_segment_status:%s" % str(id_variant))
		if not record.get("project_id", null) is String or str(record.get("project_id", "")).is_empty():
			issues.append("invalid_segment_project_id:%s" % str(id_variant))
	for id_variant: Variant in facility_records.keys():
		var record_variant: Variant = facility_records[id_variant]
		if not record_variant is Dictionary:
			issues.append("facility_not_dictionary:%s" % str(id_variant))
			continue
		var record: Dictionary = record_variant
		_append_missing_record_fields(issues, "facility", id_variant, record, ["id", "kind", "tile_id", "status", "project_id"])
		_append_snapshot_record_identity_issue(issues, "facility", id_variant, record)
		if not record.get("kind", null) is String or str(record.get("kind", "")) not in TransportModesScript.FACILITY_KINDS:
			issues.append("invalid_facility:%s" % str(id_variant))
		_append_snapshot_tile_id_issue(issues, "facility", id_variant, record.get("tile_id", null))
		if not record.get("status", null) is String or str(record.get("status", "")).is_empty():
			issues.append("invalid_facility_status:%s" % str(id_variant))
		if not record.get("project_id", null) is String or str(record.get("project_id", "")).is_empty():
			issues.append("invalid_facility_project_id:%s" % str(id_variant))
	for id_variant: Variant in station_records.keys():
		var record_variant: Variant = station_records[id_variant]
		if not record_variant is Dictionary:
			issues.append("station_not_dictionary:%s" % str(id_variant))
			continue
		var record: Dictionary = record_variant
		_append_missing_record_fields(issues, "station", id_variant, record, ["id", "building_name", "tile_id", "status", "project_id"])
		_append_snapshot_record_identity_issue(issues, "station", id_variant, record)
		if not record.get("building_name", null) is String or str(record.get("building_name", "")) not in TransportModesScript.STATION_KINDS:
			issues.append("invalid_station:%s" % str(id_variant))
		_append_snapshot_tile_id_issue(issues, "station", id_variant, record.get("tile_id", null))
		if not record.get("status", null) is String or str(record.get("status", "")).is_empty():
			issues.append("invalid_station_status:%s" % str(id_variant))
		if not record.get("project_id", null) is String or str(record.get("project_id", "")).is_empty():
			issues.append("invalid_station_project_id:%s" % str(id_variant))
	var active_build_id_owners: Dictionary = {}
	var completed_demolition_targets := _snapshot_completed_demolition_targets(project_records)
	for id_variant: Variant in project_records.keys():
		var record_variant: Variant = project_records[id_variant]
		if not record_variant is Dictionary:
			issues.append("project_not_dictionary:%s" % str(id_variant))
			continue
		var record: Dictionary = record_variant
		_append_missing_record_fields(issues, "project", id_variant, record, ["id", "operation", "status", "plan", "quote", "total_cost"])
		_append_snapshot_record_identity_issue(issues, "project", id_variant, record)
		var operation := str(record.get("operation", ""))
		var project_status := str(record.get("status", ""))
		if not record.get("operation", null) is String or operation not in TransportModesScript.PROJECT_OPERATIONS:
			issues.append("invalid_project_operation:%s" % str(id_variant))
		if not record.get("status", null) is String or project_status not in TransportModesScript.PROJECT_STATUSES:
			issues.append("invalid_project_status:%s" % str(id_variant))
		if not record.get("plan", null) is Dictionary or not record.get("quote", null) is Dictionary or not _is_number(record.get("total_cost", null)):
			issues.append("invalid_project_shape:%s" % str(id_variant))
		elif operation == "build":
			var build_plan: Dictionary = record.get("plan", {})
			_append_missing_record_fields(
				issues, "build_plan", id_variant, build_plan,
				["title", "source_decision_id", "segments", "facilities", "stations"]
			)
			_append_snapshot_build_plan_issues(
				issues, id_variant, build_plan, project_status,
				segment_records, facility_records, station_records,
				active_build_id_owners, completed_demolition_targets, topology_map
			)
		elif operation == "demolish":
			var demolition_plan: Dictionary = record.get("plan", {})
			_append_missing_record_fields(
				issues, "demolition_plan", id_variant, demolition_plan,
				["title", "source_decision_id", "segment_ids", "facility_ids", "station_ids"]
			)
			_append_snapshot_demolition_plan_issues(
				issues, id_variant, demolition_plan, project_status,
				segment_records, facility_records, station_records
			)
			_append_snapshot_completed_demolition_relation_issues(
				issues, id_variant, demolition_plan, project_status,
				segment_records, facility_records, station_records, project_records
			)
		_append_snapshot_project_quote_issues(
			issues, id_variant, record, operation, topology_map
		)
	_append_snapshot_topology_issues(
		issues,
		project_records,
		segment_records,
		facility_records,
		station_records
	)
	_append_snapshot_live_project_relation_issues(
		issues, "segment", segment_records, project_records
	)
	_append_snapshot_live_project_relation_issues(
		issues, "facility", facility_records, project_records
	)
	_append_snapshot_live_project_relation_issues(
		issues, "station", station_records, project_records
	)
	var expected_crossings := _snapshot_expected_crossings(segment_records)
	var crossing_tiles_seen: Dictionary = {}
	for id_variant: Variant in crossing_records.keys():
		var record_variant: Variant = crossing_records[id_variant]
		if not record_variant is Dictionary:
			issues.append("crossing_not_dictionary:%s" % str(id_variant))
			continue
		var record: Dictionary = record_variant
		_append_missing_record_fields(issues, "crossing", id_variant, record, ["id", "kind", "tile_id", "track_kinds", "status", "build_cost", "monthly_maintenance"])
		_append_snapshot_record_identity_issue(issues, "crossing", id_variant, record)
		if (
			not record.get("kind", null) is String
			or str(record.get("kind", "")) != TransportModesScript.CROSSING_KIND
			or not record.get("track_kinds", null) is Array
		):
			issues.append("invalid_crossing:%s" % str(id_variant))
		_append_snapshot_tile_id_issue(issues, "crossing", id_variant, record.get("tile_id", null))
		_append_snapshot_crossing_rebuild_issues(
			issues, id_variant, record, expected_crossings, crossing_tiles_seen
		)
	for expected_id: String in _sorted_string_keys(expected_crossings):
		if not crossing_records.has(expected_id):
			issues.append("missing_rebuilt_crossing:%s" % expected_id)
	var route_semantic_network = null
	if _snapshot_route_semantic_inputs_safe(segment_records, facility_records, station_records):
		route_semantic_network = (load("res://scripts/systems/city/transport_network_system.gd") as Script).new()
		route_semantic_network.segments = segment_records.duplicate(true)
		route_semantic_network.facilities = facility_records.duplicate(true)
		route_semantic_network.stations = station_records.duplicate(true)
	for id_variant: Variant in route_records.keys():
		var record_variant: Variant = route_records[id_variant]
		if not record_variant is Dictionary:
			issues.append("route_not_dictionary:%s" % str(id_variant))
			continue
		var record: Dictionary = record_variant
		_append_missing_record_fields(issues, "route", id_variant, record, [
			"id", "name", "mode", "stop_ids", "fleet_size", "headway_minutes", "fare", "enabled",
			"path_tile_ids", "station_tile_ids", "vehicle_kind", "loop_seconds", "validation_errors", "status",
		])
		_append_snapshot_record_identity_issue(issues, "route", id_variant, record)
		_append_snapshot_route_issues(
			issues,
			id_variant,
			record,
			station_records,
			segment_records,
			topology_map,
			route_semantic_network
		)
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


func _quote_demolition(plan: Dictionary, construction_tile_ids: Variant = []) -> Dictionary:
	var normalized := _normalize_demolition_plan(plan)
	var issues := _demolition_target_issues(normalized)
	var blocked_tiles := _tile_set(construction_tile_ids)
	for tile_variant: Variant in _active_project_tile_set().keys():
		blocked_tiles[int(tile_variant)] = true
	for tile_id: int in _demolition_target_tile_ids(normalized):
		if blocked_tiles.has(tile_id):
			issues.append("tile_under_construction:%d" % tile_id)
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
	if not issues.is_empty():
		return {"ok": false, "error": "invalid_transport_plan", "issues": _unique_strings(issues), "operation": "demolish", "plan": normalized}
	return {
		"ok": true,
		"operation": "demolish",
		"plan": normalized,
		"crossing_tile_ids": [],
		"breakdown": {"segments": segment_cost, "facilities": facility_cost, "stations": station_cost, "level_crossings": 0},
		"total_cost": segment_cost + facility_cost + station_cost,
	}


func _demolition_target_issues(plan: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	var seen_targets: Dictionary = {}
	for id_variant: Variant in plan.get("segment_ids", []):
		var segment_id := str(id_variant)
		var target_key := "segment:%s" % segment_id
		if seen_targets.has(target_key):
			issues.append("duplicate_demolition_target:%s" % target_key)
		seen_targets[target_key] = true
		if not segments.has(segment_id):
			issues.append("segment_not_found:%s" % segment_id)
	for id_variant: Variant in plan.get("facility_ids", []):
		var facility_id := str(id_variant)
		var target_key := "facility:%s" % facility_id
		if seen_targets.has(target_key):
			issues.append("duplicate_demolition_target:%s" % target_key)
		seen_targets[target_key] = true
		if not facilities.has(facility_id):
			issues.append("facility_not_found:%s" % facility_id)
	for id_variant: Variant in plan.get("station_ids", []):
		var station_id := str(id_variant)
		var target_key := "station:%s" % station_id
		if seen_targets.has(target_key):
			issues.append("duplicate_demolition_target:%s" % target_key)
		seen_targets[target_key] = true
		if not stations.has(station_id):
			issues.append("station_not_found:%s" % station_id)
	if Array(plan.get("segment_ids", [])).is_empty() and Array(plan.get("facility_ids", [])).is_empty() and Array(plan.get("station_ids", [])).is_empty():
		issues.append("demolition_targets_required")
	return _unique_strings(issues)


func _demolition_target_tile_ids(plan: Dictionary) -> Array[int]:
	var tile_set: Dictionary = {}
	for id_variant: Variant in plan.get("segment_ids", []):
		var segment: Dictionary = segments.get(str(id_variant), {})
		for tile_variant: Variant in segment.get("tile_path", []):
			tile_set[int(tile_variant)] = true
	for id_variant: Variant in plan.get("facility_ids", []):
		var facility: Dictionary = facilities.get(str(id_variant), {})
		var tile_id := int(facility.get("tile_id", -1))
		if tile_id >= 0:
			tile_set[tile_id] = true
	for id_variant: Variant in plan.get("station_ids", []):
		var station: Dictionary = stations.get(str(id_variant), {})
		var tile_id := int(station.get("tile_id", -1))
		if tile_id >= 0:
			tile_set[tile_id] = true
	var result: Array[int] = []
	for tile_variant: Variant in tile_set.keys():
		result.append(int(tile_variant))
	result.sort()
	return result


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
	var reserved_entity_ids := _active_and_live_build_entity_ids()
	var explicit_plan_ids: Dictionary = {}
	for segment: Dictionary in plan["segments"]:
		_append_build_entity_id_issues(
			str(segment.get("id", "")), "segment", reserved_entity_ids, explicit_plan_ids, issues
		)
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
		_append_build_entity_id_issues(
			str(facility.get("id", "")), "facility", reserved_entity_ids, explicit_plan_ids, issues
		)
		var kind := str(facility.get("kind", ""))
		var tile_id := int(facility.get("tile_id", -1))
		if kind not in TransportModesScript.FACILITY_KINDS:
			issues.append("invalid_facility_kind:%s" % kind)
		_validate_build_tile(tile_id, terrain_map, occupied, construction, issues)
		if structure_tiles.has(tile_id) or planned_by_tile.has(tile_id):
			issues.append("transport_structure_overlap:%d" % tile_id)
		structure_tiles[tile_id] = true
	for station: Dictionary in plan["stations"]:
		_append_build_entity_id_issues(
			str(station.get("id", "")), "station", reserved_entity_ids, explicit_plan_ids, issues
		)
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


func _active_and_live_build_entity_ids() -> Dictionary:
	var result: Dictionary = {}
	for collection: Dictionary in [segments, facilities, stations]:
		for id_variant: Variant in collection.keys():
			result[str(id_variant)] = "live"
	for project_variant: Variant in projects.values():
		if not project_variant is Dictionary:
			continue
		var project: Dictionary = project_variant
		if (
			str(project.get("operation", "")) != "build"
			or str(project.get("status", "")) not in ["planned", "under_construction"]
			or not project.get("plan", null) is Dictionary
		):
			continue
		var project_id := str(project.get("id", ""))
		var active_plan: Dictionary = project.get("plan", {})
		for field_name: String in ["segments", "facilities", "stations"]:
			for item_variant: Variant in _array_value(active_plan.get(field_name, [])):
				if not item_variant is Dictionary:
					continue
				var item_id := str((item_variant as Dictionary).get("id", ""))
				if not item_id.is_empty():
					result[item_id] = "active:%s" % project_id
	return result


func _append_build_entity_id_issues(
	item_id: String,
	item_kind: String,
	reserved_entity_ids: Dictionary,
	explicit_plan_ids: Dictionary,
	issues: Array[String]
) -> void:
	# Empty IDs are intentional input: _assign_build_entity_ids gives them a
	# reserved generated ID after the quote succeeds.
	if item_id.is_empty():
		return
	if explicit_plan_ids.has(item_id):
		issues.append("duplicate_transport_item_id:%s:%s" % [item_kind, item_id])
	else:
		explicit_plan_ids[item_id] = item_kind
	if reserved_entity_ids.has(item_id):
		issues.append("transport_item_id_reserved:%s:%s" % [item_kind, item_id])


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
	# Reserve every explicit generated-form ID before assigning any empty one so
	# input order cannot make an auto ID collide with a later explicit record.
	for record_variant: Variant in result.get("segments", []):
		if record_variant is Dictionary:
			next_segment_sequence = _sequence_ahead_of_reserved_id(
				str((record_variant as Dictionary).get("id", "")),
				"transport_segment_", next_segment_sequence
			)
	for record_variant: Variant in result.get("facilities", []):
		if record_variant is Dictionary:
			next_facility_sequence = _sequence_ahead_of_reserved_id(
				str((record_variant as Dictionary).get("id", "")),
				"transport_facility_", next_facility_sequence
			)
	for record_variant: Variant in result.get("stations", []):
		if record_variant is Dictionary:
			next_station_sequence = _sequence_ahead_of_reserved_id(
				str((record_variant as Dictionary).get("id", "")),
				"transport_station_", next_station_sequence
			)
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
	var attachments_by_stop: Array[Array] = []
	for stop_variant: Variant in stop_ids:
		var stop_id := str(stop_variant)
		var station: Dictionary = stations.get(stop_id, {})
		var attachments := _network_attachments(
			int(station.get("tile_id", -1)), guideway_tiles, _topology_map
		)
		attachments_by_stop.append(attachments)
		if attachments.is_empty():
			errors.append("station_not_connected:%s" % stop_id)
	if not errors.is_empty() or attachments_by_stop.is_empty():
		return {"path_tile_ids": [], "errors": _unique_strings(errors)}

	# Keep one best continuous path per attachment of the current stop.  A
	# station may touch two disconnected guideway components; independently
	# finding each pair of legs can otherwise splice those components together
	# and publish a non-cardinal vehicle teleport at a three-stop route.
	var path_by_attachment: Dictionary = {}
	for attachment_variant: Variant in attachments_by_stop[0]:
		var attachment := int(attachment_variant)
		path_by_attachment[attachment] = [attachment]
	for stop_index in range(1, stop_ids.size()):
		var next_paths: Dictionary = {}
		for start_variant: Variant in path_by_attachment.keys():
			var start := int(start_variant)
			var prefix: Array = path_by_attachment[start]
			for goal_variant: Variant in attachments_by_stop[stop_index]:
				var goal := int(goal_variant)
				var goal_set: Dictionary = {}
				goal_set[goal] = true
				var leg := _shortest_path_between_sets(
					guideway_tiles, [start], goal_set, _topology_map
				)
				if leg.is_empty():
					continue
				var candidate: Array[int] = _int_array(prefix)
				for leg_index in range(1, leg.size()):
					candidate.append(int(leg[leg_index]))
				if not next_paths.has(goal) or candidate.size() < Array(next_paths[goal]).size():
					next_paths[goal] = candidate
		if next_paths.is_empty():
			errors.append(
				"stops_disconnected:%s:%s" % [str(stop_ids[stop_index - 1]), str(stop_ids[stop_index])]
			)
			return {"path_tile_ids": [], "errors": _unique_strings(errors)}
		path_by_attachment = next_paths

	var full_path: Array[int] = []
	var ordered_endpoints: Array[int] = []
	for endpoint_variant: Variant in path_by_attachment.keys():
		ordered_endpoints.append(int(endpoint_variant))
	ordered_endpoints.sort()
	for endpoint: int in ordered_endpoints:
		var candidate: Array[int] = _int_array(path_by_attachment[endpoint])
		if full_path.is_empty() or candidate.size() < full_path.size():
			full_path = candidate
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


static func _segment_overlap_allowed(first_kind: String, second_kind: String) -> bool:
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


static func _sorted_string_keys(source: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key_variant: Variant in source.keys():
		result.append(str(key_variant))
	result.sort()
	return result


func _dictionary_copy(source: Variant) -> Dictionary:
	return Dictionary(source).duplicate(true) if source is Dictionary else {}


func _sequence_ahead_of_reserved_id(record_id: String, generated_prefix: String, current: int) -> int:
	if not record_id.begins_with(generated_prefix):
		return current
	var suffix := record_id.trim_prefix(generated_prefix)
	if suffix.is_empty() or not suffix.is_valid_int():
		return current
	var sequence := int(suffix)
	return maxi(current, sequence + 1) if sequence >= 0 else current


static func _append_missing_record_fields(
	issues: Array[String],
	record_kind: String,
	record_id: Variant,
	record: Dictionary,
	required_fields: Array
) -> void:
	for field_variant: Variant in required_fields:
		var field_name := str(field_variant)
		if not record.has(field_name):
			issues.append("missing_%s_field:%s:%s" % [record_kind, str(record_id), field_name])


static func _append_snapshot_sequence_issues(
	issues: Array[String],
	snapshot: Dictionary,
	field_name: String,
	records: Dictionary,
	generated_prefix: String,
	additional_record_ids: Variant = []
) -> void:
	if not snapshot.has(field_name):
		issues.append("missing_sequence_field:%s" % field_name)
		return
	var value: Variant = snapshot[field_name]
	if not _is_integer_value(value) or int(value) < 1:
		issues.append("invalid_sequence:%s" % field_name)
		return
	var highest_existing := _highest_generated_record_sequence(
		records, generated_prefix, additional_record_ids
	)
	if int(value) <= highest_existing:
		issues.append("sequence_not_ahead:%s:%d" % [field_name, highest_existing])


static func _highest_generated_record_sequence(
	records: Dictionary,
	generated_prefix: String,
	additional_record_ids: Variant = []
) -> int:
	var highest := 0
	var ids: Array = records.keys()
	if additional_record_ids is Array:
		ids.append_array(additional_record_ids)
	for key_variant: Variant in ids:
		if not key_variant is String:
			continue
		var record_id: String = key_variant
		if not record_id.begins_with(generated_prefix):
			continue
		var suffix := record_id.trim_prefix(generated_prefix)
		if suffix.is_valid_int() and int(suffix) >= 0:
			highest = maxi(highest, int(suffix))
	return highest


static func _snapshot_active_build_plan_ids(project_records: Dictionary) -> Dictionary:
	var result := {"segments": [], "facilities": [], "stations": []}
	for project_variant: Variant in project_records.values():
		if not project_variant is Dictionary:
			continue
		var project: Dictionary = project_variant
		if (
			str(project.get("operation", "")) != "build"
			or str(project.get("status", "")) not in ["planned", "under_construction"]
			or not project.get("plan", null) is Dictionary
		):
			continue
		var plan: Dictionary = project.get("plan", {})
		for field_name: String in ["segments", "facilities", "stations"]:
			var items: Variant = plan.get(field_name, null)
			if not items is Array:
				continue
			for item_variant: Variant in items:
				if not item_variant is Dictionary:
					continue
				var item_id: Variant = (item_variant as Dictionary).get("id", null)
				if item_id is String and not str(item_id).is_empty():
					(result[field_name] as Array).append(str(item_id))
	return result


static func _snapshot_completed_demolition_targets(project_records: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var target_specs := {
		"segment_ids": "segment",
		"facility_ids": "facility",
		"station_ids": "station",
	}
	for project_variant: Variant in project_records.values():
		if not project_variant is Dictionary:
			continue
		var project: Dictionary = project_variant
		if (
			str(project.get("operation", "")) != "demolish"
			or str(project.get("status", "")) != "completed"
			or not project.get("plan", null) is Dictionary
		):
			continue
		var plan: Dictionary = project.get("plan", {})
		for field_name: String in target_specs.keys():
			var values: Variant = plan.get(field_name, null)
			if not values is Array:
				continue
			for value_variant: Variant in values:
				if value_variant is String and not str(value_variant).is_empty():
					result["%s:%s" % [str(target_specs[field_name]), str(value_variant)]] = true
	return result


static func _append_snapshot_topology_issues(
	issues: Array[String],
	project_records: Dictionary,
	segment_records: Dictionary,
	facility_records: Dictionary,
	station_records: Dictionary
) -> void:
	var entity_id_owners: Dictionary = {}
	for collection_spec: Dictionary in [
		{"kind": "segment", "records": segment_records},
		{"kind": "facility", "records": facility_records},
		{"kind": "station", "records": station_records},
	]:
		var records: Dictionary = collection_spec["records"]
		for id_variant: Variant in records.keys():
			if not id_variant is String or str(id_variant).is_empty():
				continue
			var entity_id := str(id_variant)
			if entity_id_owners.has(entity_id):
				issues.append(
					"transport_entity_id_cross_collection:%s:%s:%s" % [
						entity_id, str(entity_id_owners[entity_id]), str(collection_spec["kind"])
					]
				)
			else:
				entity_id_owners[entity_id] = str(collection_spec["kind"])

	var segment_layers_by_tile: Dictionary = {}
	for segment_id: String in _sorted_string_keys(segment_records):
		var segment_value: Variant = segment_records[segment_id]
		if not segment_value is Dictionary:
			continue
		var segment: Dictionary = segment_value
		var kind := str(segment.get("kind", ""))
		var path_value: Variant = segment.get("tile_path", null)
		if kind not in TransportModesScript.SEGMENT_KINDS or not path_value is Array:
			continue
		for tile_variant: Variant in path_value:
			if not _is_integer_value(tile_variant):
				continue
			var tile_id := int(tile_variant)
			if tile_id < 0 or tile_id >= CityTerrainMapScript.CELL_COUNT:
				continue
			_append_snapshot_segment_layer_issue(
				issues,
				segment_layers_by_tile,
				tile_id,
				kind,
				"live:%s" % segment_id
			)

	var live_structure_tiles: Dictionary = {}
	for collection_spec: Dictionary in [
		{"kind": "facility", "records": facility_records},
		{"kind": "station", "records": station_records},
	]:
		var records: Dictionary = collection_spec["records"]
		for record_id: String in _sorted_string_keys(records):
			var record_value: Variant = records[record_id]
			if not record_value is Dictionary:
				continue
			var tile_value: Variant = (record_value as Dictionary).get("tile_id", null)
			if not _is_integer_value(tile_value):
				continue
			var tile_id := int(tile_value)
			if tile_id < 0 or tile_id >= CityTerrainMapScript.CELL_COUNT:
				continue
			var owner := "%s:%s" % [str(collection_spec["kind"]), record_id]
			if live_structure_tiles.has(tile_id):
				issues.append(
					"transport_structure_tile_conflict:%d:%s:%s" % [
						tile_id, str(live_structure_tiles[tile_id]), owner
					]
				)
			else:
				live_structure_tiles[tile_id] = owner
			if segment_layers_by_tile.has(tile_id):
				issues.append(
					"transport_structure_segment_tile_conflict:%d:%s" % [tile_id, owner]
				)

	var active_tile_owners: Dictionary = {}
	for project_id: String in _sorted_string_keys(project_records):
		var project_value: Variant = project_records[project_id]
		if not project_value is Dictionary:
			continue
		var project: Dictionary = project_value
		if str(project.get("status", "")) not in ["planned", "under_construction"]:
			continue
		var plan_value: Variant = project.get("plan", null)
		if not plan_value is Dictionary:
			continue
		var plan: Dictionary = plan_value
		if str(project.get("operation", "")) == "demolish":
			_append_snapshot_active_demolition_tile_issues(
				issues,
				project_id,
				plan,
				segment_records,
				facility_records,
				station_records,
				active_tile_owners
			)
			continue
		if str(project.get("operation", "")) != "build":
			continue
		var local_segment_tiles: Dictionary = {}
		var local_structure_tiles: Dictionary = {}
		var segment_values: Variant = plan.get("segments", null)
		if segment_values is Array:
			for segment_value: Variant in segment_values:
				if not segment_value is Dictionary:
					continue
				var segment: Dictionary = segment_value
				var kind := str(segment.get("kind", ""))
				var path_value: Variant = segment.get("tile_path", null)
				if kind not in TransportModesScript.SEGMENT_KINDS or not path_value is Array:
					continue
				var segment_id := str(segment.get("id", ""))
				for tile_variant: Variant in path_value:
					if not _is_integer_value(tile_variant):
						continue
					var tile_id := int(tile_variant)
					if tile_id < 0 or tile_id >= CityTerrainMapScript.CELL_COUNT:
						continue
					_append_snapshot_active_tile_owner_issue(
						issues, active_tile_owners, tile_id, project_id
					)
					if live_structure_tiles.has(tile_id):
						issues.append(
							"active_transport_build_hits_live_structure:%s:%d:%s" % [
								project_id, tile_id, str(live_structure_tiles[tile_id])
							]
						)
					if local_structure_tiles.has(tile_id):
						issues.append("active_transport_plan_structure_overlap:%s:%d" % [project_id, tile_id])
					local_segment_tiles[tile_id] = true
					_append_snapshot_segment_layer_issue(
						issues,
						segment_layers_by_tile,
						tile_id,
						kind,
						"active:%s:%s" % [project_id, segment_id]
					)
		for structure_spec: Dictionary in [
			{"field": "facilities", "kind": "facility"},
			{"field": "stations", "kind": "station"},
		]:
			var structure_values: Variant = plan.get(str(structure_spec["field"]), null)
			if not structure_values is Array:
				continue
			for structure_value: Variant in structure_values:
				if not structure_value is Dictionary:
					continue
				var tile_value: Variant = (structure_value as Dictionary).get("tile_id", null)
				if not _is_integer_value(tile_value):
					continue
				var tile_id := int(tile_value)
				if tile_id < 0 or tile_id >= CityTerrainMapScript.CELL_COUNT:
					continue
				_append_snapshot_active_tile_owner_issue(
					issues, active_tile_owners, tile_id, project_id
				)
				if live_structure_tiles.has(tile_id):
					issues.append(
						"active_transport_build_hits_live_structure:%s:%d:%s" % [
							project_id, tile_id, str(live_structure_tiles[tile_id])
						]
					)
				if segment_layers_by_tile.has(tile_id):
					issues.append(
						"active_transport_structure_hits_segment:%s:%d" % [project_id, tile_id]
					)
				if local_segment_tiles.has(tile_id) or local_structure_tiles.has(tile_id):
					issues.append("active_transport_plan_structure_overlap:%s:%d" % [project_id, tile_id])
				local_structure_tiles[tile_id] = str(structure_spec["kind"])


static func _append_snapshot_segment_layer_issue(
	issues: Array[String],
	layers_by_tile: Dictionary,
	tile_id: int,
	kind: String,
	owner: String
) -> void:
	var layers: Dictionary = layers_by_tile.get(tile_id, {})
	if layers.has(kind):
		issues.append(
			"duplicate_transport_segment_layer:%d:%s:%s:%s" % [
				tile_id, kind, str(layers[kind]), owner
			]
		)
	for other_kind_variant: Variant in layers.keys():
		var other_kind := str(other_kind_variant)
		if other_kind == kind or _segment_overlap_allowed(other_kind, kind):
			continue
		issues.append(
			"incompatible_transport_segment_layers:%d:%s:%s" % [tile_id, other_kind, kind]
		)
	if not layers.has(kind):
		layers[kind] = owner
		layers_by_tile[tile_id] = layers


static func _append_snapshot_active_tile_owner_issue(
	issues: Array[String],
	active_tile_owners: Dictionary,
	tile_id: int,
	project_id: String
) -> void:
	if active_tile_owners.has(tile_id) and str(active_tile_owners[tile_id]) != project_id:
		issues.append(
			"active_transport_project_tile_conflict:%d:%s:%s" % [
				tile_id, str(active_tile_owners[tile_id]), project_id
			]
		)
		return
	active_tile_owners[tile_id] = project_id


static func _append_snapshot_active_demolition_tile_issues(
	issues: Array[String],
	project_id: String,
	plan: Dictionary,
	segment_records: Dictionary,
	facility_records: Dictionary,
	station_records: Dictionary,
	active_tile_owners: Dictionary
) -> void:
	for segment_id_variant: Variant in _array_value_static(plan.get("segment_ids", null)):
		var segment_value: Variant = segment_records.get(str(segment_id_variant), null)
		if not segment_value is Dictionary:
			continue
		for tile_variant: Variant in _array_value_static((segment_value as Dictionary).get("tile_path", null)):
			if _is_integer_value(tile_variant):
				var tile_id := int(tile_variant)
				if tile_id >= 0 and tile_id < CityTerrainMapScript.CELL_COUNT:
					_append_snapshot_active_tile_owner_issue(
						issues, active_tile_owners, tile_id, project_id
					)
	for collection_spec: Dictionary in [
		{"ids": plan.get("facility_ids", null), "records": facility_records},
		{"ids": plan.get("station_ids", null), "records": station_records},
	]:
		var records: Dictionary = collection_spec["records"]
		for record_id_variant: Variant in _array_value_static(collection_spec["ids"]):
			var record_value: Variant = records.get(str(record_id_variant), null)
			if not record_value is Dictionary:
				continue
			var tile_value: Variant = (record_value as Dictionary).get("tile_id", null)
			if _is_integer_value(tile_value):
				var tile_id := int(tile_value)
				if tile_id >= 0 and tile_id < CityTerrainMapScript.CELL_COUNT:
					_append_snapshot_active_tile_owner_issue(
						issues, active_tile_owners, tile_id, project_id
					)


static func _array_value_static(source: Variant) -> Array:
	return source if source is Array else []


static func _append_snapshot_build_plan_issues(
	issues: Array[String],
	project_id: Variant,
	plan: Dictionary,
	project_status: String,
	segment_records: Dictionary,
	facility_records: Dictionary,
	station_records: Dictionary,
	active_build_id_owners: Dictionary,
	completed_demolition_targets: Dictionary,
	topology_map
) -> void:
	var project_label := str(project_id)
	if not plan.get("title", null) is String:
		issues.append("invalid_build_plan_title:%s" % project_label)
	if not plan.get("source_decision_id", null) is String:
		issues.append("invalid_build_plan_source_decision_id:%s" % project_label)
	var item_specs: Array[Dictionary] = [
		{"field": "segments", "kind": "segment", "records": segment_records},
		{"field": "facilities", "kind": "facility", "records": facility_records},
		{"field": "stations", "kind": "station", "records": station_records},
	]
	var seen_project_ids: Dictionary = {}
	var item_count := 0
	for spec: Dictionary in item_specs:
		var field_name := str(spec["field"])
		var item_kind := str(spec["kind"])
		var values: Variant = plan.get(field_name, null)
		if not values is Array:
			issues.append("build_plan_%s_not_array:%s" % [field_name, project_label])
			continue
		var live_records: Dictionary = spec["records"]
		for index in (values as Array).size():
			item_count += 1
			var item_variant: Variant = (values as Array)[index]
			if not item_variant is Dictionary:
				issues.append("build_plan_%s_not_dictionary:%s:%d" % [item_kind, project_label, index])
				continue
			var item: Dictionary = item_variant
			var item_id_value: Variant = item.get("id", null)
			if not item_id_value is String or str(item_id_value).is_empty():
				issues.append("invalid_build_plan_%s_id:%s:%d" % [item_kind, project_label, index])
				_append_snapshot_build_item_shape_issues(
					issues, project_label, item_kind, index, item, topology_map
				)
				continue
			var item_id := str(item_id_value)
			if seen_project_ids.has(item_id):
				issues.append("duplicate_build_plan_id:%s:%s" % [project_label, item_id])
			seen_project_ids[item_id] = item_kind
			_append_snapshot_build_item_shape_issues(
				issues, project_label, item_kind, index, item, topology_map
			)
			if project_status in ["planned", "under_construction"]:
				for other_spec: Dictionary in item_specs:
					var other_records: Dictionary = other_spec["records"]
					if other_records.has(item_id):
						issues.append(
							"active_build_live_id_conflict:%s:%s" % [project_label, item_id]
						)
						break
				if active_build_id_owners.has(item_id):
					issues.append(
						"active_build_plan_id_conflict:%s:%s:%s" % [
							project_label, item_id, str(active_build_id_owners[item_id])
						]
					)
				else:
					active_build_id_owners[item_id] = "%s:%s" % [project_label, item_kind]
			elif project_status == "completed":
				var historical_target_key := "%s:%s" % [item_kind, item_id]
				if not live_records.has(item_id):
					if not completed_demolition_targets.has(historical_target_key):
						issues.append("completed_build_record_missing:%s:%s" % [project_label, item_id])
					continue
				var live_variant: Variant = live_records[item_id]
				if live_variant is Dictionary:
					var live_record: Dictionary = live_variant
					var live_owner := str(live_record.get("project_id", ""))
					if live_owner == project_label:
						if not _snapshot_build_item_matches_live(item_kind, item, live_record):
							issues.append(
								"completed_build_live_shape_mismatch:%s:%s" % [project_label, item_id]
							)
					elif not completed_demolition_targets.has(historical_target_key):
						issues.append(
							"completed_build_live_owner_mismatch:%s:%s:%s" % [
								project_label, item_id, live_owner
							]
						)
	if item_count == 0:
		issues.append("build_plan_items_required:%s" % project_label)


static func _append_snapshot_build_item_shape_issues(
	issues: Array[String],
	project_id: String,
	item_kind: String,
	index: int,
	item: Dictionary,
	topology_map
) -> void:
	var label := "%s:%s:%d" % [project_id, item_kind, index]
	if item_kind == "segment":
		_append_missing_record_fields(issues, "build_segment", label, item, ["id", "kind", "tile_path"])
		if not item.get("kind", null) is String or str(item.get("kind", "")) not in TransportModesScript.SEGMENT_KINDS:
			issues.append("invalid_build_segment_kind:%s" % label)
		_validate_snapshot_tile_array(
			item.get("tile_path", null), issues, "build_segment_path:%s" % label,
			false, true, true, topology_map
		)
	elif item_kind == "facility":
		_append_missing_record_fields(issues, "build_facility", label, item, ["id", "kind", "tile_id"])
		if not item.get("kind", null) is String or str(item.get("kind", "")) not in TransportModesScript.FACILITY_KINDS:
			issues.append("invalid_build_facility_kind:%s" % label)
		_append_snapshot_tile_id_issue(issues, "build_facility", label, item.get("tile_id", null))
	else:
		_append_missing_record_fields(issues, "build_station", label, item, ["id", "building_name", "tile_id"])
		if not item.get("building_name", null) is String or str(item.get("building_name", "")) not in TransportModesScript.STATION_KINDS:
			issues.append("invalid_build_station_kind:%s" % label)
		_append_snapshot_tile_id_issue(issues, "build_station", label, item.get("tile_id", null))


static func _snapshot_build_item_matches_live(
	item_kind: String,
	item: Dictionary,
	live_record: Dictionary
) -> bool:
	if str(item.get("id", "")) != str(live_record.get("id", "")):
		return false
	if item_kind == "segment":
		return (
			str(item.get("kind", "")) == str(live_record.get("kind", ""))
			and item.get("tile_path", null) is Array
			and live_record.get("tile_path", null) is Array
			and Array(item.get("tile_path", [])) == Array(live_record.get("tile_path", []))
		)
	if item_kind == "facility":
		return (
			str(item.get("kind", "")) == str(live_record.get("kind", ""))
			and _is_integer_value(item.get("tile_id", null))
			and _is_integer_value(live_record.get("tile_id", null))
			and int(item.get("tile_id", -1)) == int(live_record.get("tile_id", -1))
		)
	return (
		str(item.get("building_name", "")) == str(live_record.get("building_name", ""))
		and _is_integer_value(item.get("tile_id", null))
		and _is_integer_value(live_record.get("tile_id", null))
		and int(item.get("tile_id", -1)) == int(live_record.get("tile_id", -1))
	)


static func _append_snapshot_project_quote_issues(
	issues: Array[String],
	project_id: Variant,
	project: Dictionary,
	operation: String,
	topology_map
) -> void:
	var project_label := str(project_id)
	var total_value: Variant = project.get("total_cost", null)
	if not _is_integer_value(total_value) or int(total_value) < 0:
		issues.append("invalid_project_total_cost:%s" % project_label)
	var quote_value: Variant = project.get("quote", null)
	if not quote_value is Dictionary:
		return
	var quote: Dictionary = quote_value
	_append_missing_record_fields(
		issues, "project_quote", project_label, quote,
		["ok", "operation", "plan", "crossing_tile_ids", "breakdown", "total_cost"]
	)
	if not quote.get("ok", null) is bool or not bool(quote.get("ok", false)):
		issues.append("invalid_project_quote_ok:%s" % project_label)
	if not quote.get("operation", null) is String or str(quote.get("operation", "")) != operation:
		issues.append("project_quote_operation_mismatch:%s" % project_label)
	if not quote.get("plan", null) is Dictionary or quote.get("plan", null) != project.get("plan", null):
		issues.append("project_quote_plan_mismatch:%s" % project_label)
	var quote_total: Variant = quote.get("total_cost", null)
	if not _is_integer_value(quote_total) or int(quote_total) < 0:
		issues.append("invalid_project_quote_total:%s" % project_label)
	elif _is_integer_value(total_value) and int(quote_total) != int(total_value):
		issues.append("project_quote_total_mismatch:%s" % project_label)
	var crossing_tiles := _validate_snapshot_tile_array(
		quote.get("crossing_tile_ids", null), issues,
		"project_quote_crossing_tiles:%s" % project_label, true, true, false, topology_map
	)
	var breakdown_value: Variant = quote.get("breakdown", null)
	if not breakdown_value is Dictionary:
		issues.append("project_quote_breakdown_not_dictionary:%s" % project_label)
		return
	var breakdown: Dictionary = breakdown_value
	var breakdown_total := 0
	var breakdown_valid := true
	for field_name: String in ["segments", "facilities", "stations", "level_crossings"]:
		if not breakdown.has(field_name):
			issues.append("missing_project_quote_breakdown:%s:%s" % [project_label, field_name])
			breakdown_valid = false
			continue
		var value: Variant = breakdown[field_name]
		if not _is_integer_value(value) or int(value) < 0:
			issues.append("invalid_project_quote_breakdown:%s:%s" % [project_label, field_name])
			breakdown_valid = false
			continue
		breakdown_total += int(value)
	if breakdown_valid and _is_integer_value(total_value) and breakdown_total != int(total_value):
		issues.append("project_quote_breakdown_total_mismatch:%s" % project_label)
	if operation == "demolish":
		if not crossing_tiles.is_empty() or int(breakdown.get("level_crossings", -1)) != 0:
			issues.append("demolition_quote_has_crossing_cost:%s" % project_label)
		return
	if operation != "build" or not project.get("plan", null) is Dictionary:
		return
	var plan: Dictionary = project.get("plan", {})
	var expected := {"segments": 0, "facilities": 0, "stations": 0}
	var expected_valid := true
	var segment_values: Variant = plan.get("segments", null)
	if not segment_values is Array:
		expected_valid = false
	else:
		for item_variant: Variant in segment_values:
			if not item_variant is Dictionary:
				expected_valid = false
				continue
			var item: Dictionary = item_variant
			var spec := TransportModesScript.segment_spec(str(item.get("kind", "")))
			if spec.is_empty() or not item.get("tile_path", null) is Array:
				expected_valid = false
				continue
			expected["segments"] += int(spec.get("build_cost_per_tile", 0)) * Array(item["tile_path"]).size()
	var facility_values: Variant = plan.get("facilities", null)
	if not facility_values is Array:
		expected_valid = false
	else:
		for item_variant: Variant in facility_values:
			if not item_variant is Dictionary:
				expected_valid = false
				continue
			var spec := TransportModesScript.facility_spec(str((item_variant as Dictionary).get("kind", "")))
			if spec.is_empty():
				expected_valid = false
				continue
			expected["facilities"] += int(spec.get("build_cost", 0))
	var station_values: Variant = plan.get("stations", null)
	if not station_values is Array:
		expected_valid = false
	else:
		for item_variant: Variant in station_values:
			if not item_variant is Dictionary:
				expected_valid = false
				continue
			var spec := TransportModesScript.station_spec(str((item_variant as Dictionary).get("building_name", "")))
			if spec.is_empty():
				expected_valid = false
				continue
			expected["stations"] += int(spec.get("build_cost", 0))
	if expected_valid and breakdown_valid:
		for field_name: String in expected.keys():
			if int(breakdown.get(field_name, -1)) != int(expected[field_name]):
				issues.append("project_quote_cost_mismatch:%s:%s" % [project_label, field_name])
		if int(breakdown.get("level_crossings", -1)) != crossing_tiles.size() * TransportModesScript.LEVEL_CROSSING_BUILD_COST:
			issues.append("project_quote_cost_mismatch:%s:level_crossings" % project_label)


static func _append_snapshot_live_project_relation_issues(
	issues: Array[String],
	item_kind: String,
	live_records: Dictionary,
	project_records: Dictionary
) -> void:
	var plan_field := "%ss" % item_kind
	if item_kind == "facility":
		plan_field = "facilities"
	for id_variant: Variant in live_records.keys():
		var live_variant: Variant = live_records[id_variant]
		if not live_variant is Dictionary:
			continue
		var live_record: Dictionary = live_variant
		var record_id := str(id_variant)
		if str(live_record.get("status", "")) != "completed":
			issues.append("live_%s_not_completed:%s" % [item_kind, record_id])
		var owner := str(live_record.get("project_id", ""))
		if owner == "external":
			if item_kind != "station":
				issues.append("invalid_external_%s_owner:%s" % [item_kind, record_id])
			continue
		if not project_records.has(owner) or not project_records[owner] is Dictionary:
			issues.append("missing_live_%s_project:%s:%s" % [item_kind, record_id, owner])
			continue
		var project: Dictionary = project_records[owner]
		if str(project.get("operation", "")) != "build" or str(project.get("status", "")) != "completed":
			issues.append("invalid_live_%s_project_state:%s:%s" % [item_kind, record_id, owner])
			continue
		if not project.get("plan", null) is Dictionary:
			continue
		var plan: Dictionary = project.get("plan", {})
		var items: Variant = plan.get(plan_field, null)
		if not items is Array:
			continue
		var matched := false
		for item_variant: Variant in items:
			if not item_variant is Dictionary or str((item_variant as Dictionary).get("id", "")) != record_id:
				continue
			matched = _snapshot_build_item_matches_live(
				item_kind, item_variant as Dictionary, live_record
			)
			break
		if not matched:
			issues.append("live_%s_missing_from_project_plan:%s:%s" % [item_kind, record_id, owner])


static func _append_snapshot_completed_demolition_relation_issues(
	issues: Array[String],
	project_id: Variant,
	plan: Dictionary,
	project_status: String,
	segment_records: Dictionary,
	facility_records: Dictionary,
	station_records: Dictionary,
	project_records: Dictionary
) -> void:
	if project_status != "completed":
		return
	var project_label := str(project_id)
	var demolition_sequence := _snapshot_generated_sequence(project_label, "transport_project_")
	var target_specs: Array[Dictionary] = [
		{"field": "segment_ids", "kind": "segment", "records": segment_records},
		{"field": "facility_ids", "kind": "facility", "records": facility_records},
		{"field": "station_ids", "kind": "station", "records": station_records},
	]
	for spec: Dictionary in target_specs:
		var values: Variant = plan.get(str(spec["field"]), null)
		if not values is Array:
			continue
		var live_records: Dictionary = spec["records"]
		for id_variant: Variant in values:
			if not id_variant is String or not live_records.has(str(id_variant)):
				continue
			var live_variant: Variant = live_records[str(id_variant)]
			if not live_variant is Dictionary:
				continue
			var owner := str((live_variant as Dictionary).get("project_id", ""))
			if str(spec["kind"]) == "station" and owner == "external":
				continue
			var owner_sequence := _snapshot_generated_sequence(owner, "transport_project_")
			if demolition_sequence < 0 or owner_sequence <= demolition_sequence or not project_records.has(owner):
				issues.append(
					"completed_demolition_target_still_live:%s:%s:%s" % [
						project_label, str(spec["kind"]), str(id_variant)
					]
				)


static func _snapshot_generated_sequence(record_id: String, prefix: String) -> int:
	if not record_id.begins_with(prefix):
		return -1
	var suffix := record_id.trim_prefix(prefix)
	return int(suffix) if suffix.is_valid_int() and int(suffix) >= 0 else -1


static func _snapshot_expected_crossings(segment_records: Dictionary) -> Dictionary:
	var kinds_by_tile: Dictionary = {}
	for segment_variant: Variant in segment_records.values():
		if not segment_variant is Dictionary:
			continue
		var segment: Dictionary = segment_variant
		if str(segment.get("status", "")) != "completed":
			continue
		var kind := str(segment.get("kind", ""))
		if kind not in TransportModesScript.SEGMENT_KINDS or not segment.get("tile_path", null) is Array:
			continue
		for tile_variant: Variant in segment.get("tile_path", []):
			if not _is_integer_value(tile_variant):
				continue
			var tile_id := int(tile_variant)
			if tile_id < 0 or tile_id >= CityTerrainMapScript.CELL_COUNT:
				continue
			var kinds: Array = kinds_by_tile.get(tile_id, [])
			if not kinds.has(kind):
				kinds.append(kind)
			kinds_by_tile[tile_id] = kinds
	var result: Dictionary = {}
	for tile_variant: Variant in kinds_by_tile.keys():
		var tile_id := int(tile_variant)
		var kinds: Array = kinds_by_tile[tile_variant]
		if not kinds.has("road") or (not kinds.has("metro_track") and not kinds.has("rail_track")):
			continue
		var crossing_id := "level_crossing_%03d" % tile_id
		var track_kinds: Array[String] = []
		for track_kind: String in TRACK_KINDS:
			if kinds.has(track_kind):
				track_kinds.append(track_kind)
		result[crossing_id] = {
			"id": crossing_id,
			"kind": TransportModesScript.CROSSING_KIND,
			"tile_id": tile_id,
			"track_kinds": track_kinds,
			"status": "completed",
			"build_cost": TransportModesScript.LEVEL_CROSSING_BUILD_COST,
			"monthly_maintenance": TransportModesScript.LEVEL_CROSSING_MONTHLY_MAINTENANCE,
		}
	return result


static func _append_snapshot_crossing_rebuild_issues(
	issues: Array[String],
	crossing_id: Variant,
	record: Dictionary,
	expected_crossings: Dictionary,
	crossing_tiles_seen: Dictionary
) -> void:
	var crossing_label := str(crossing_id)
	var tile_value: Variant = record.get("tile_id", null)
	if _is_integer_value(tile_value):
		var tile_id := int(tile_value)
		if crossing_tiles_seen.has(tile_id):
			issues.append("duplicate_crossing_tile:%d" % tile_id)
		crossing_tiles_seen[tile_id] = crossing_label
		var canonical_id := "level_crossing_%03d" % tile_id
		if crossing_label != canonical_id or str(record.get("id", "")) != canonical_id:
			issues.append("crossing_id_not_canonical:%s:%s" % [crossing_label, canonical_id])
	if not expected_crossings.has(crossing_label):
		issues.append("ghost_crossing:%s" % crossing_label)
		return
	var expected: Dictionary = expected_crossings[crossing_label]
	if (
		not record.get("track_kinds", null) is Array
		or Array(record.get("track_kinds", [])) != Array(expected.get("track_kinds", []))
	):
		issues.append("crossing_track_kinds_mismatch:%s" % crossing_label)
	if str(record.get("kind", "")) != str(expected.get("kind", "")):
		issues.append("crossing_kind_mismatch:%s" % crossing_label)
	if str(record.get("status", "")) != "completed":
		issues.append("crossing_status_mismatch:%s" % crossing_label)
	for field_name: String in ["build_cost", "monthly_maintenance"]:
		var value: Variant = record.get(field_name, null)
		if not _is_integer_value(value) or int(value) != int(expected[field_name]):
			issues.append("crossing_%s_mismatch:%s" % [field_name, crossing_label])


static func _append_snapshot_record_identity_issue(
	issues: Array[String],
	record_kind: String,
	record_key: Variant,
	record: Dictionary
) -> void:
	var record_id: Variant = record.get("id", null)
	if (
		not record_key is String
		or str(record_key).is_empty()
		or not record_id is String
		or str(record_id).is_empty()
		or str(record_id) != str(record_key)
	):
		issues.append("%s_record_id_mismatch:%s" % [record_kind, str(record_key)])


static func _append_snapshot_tile_id_issue(
	issues: Array[String],
	record_kind: String,
	record_id: Variant,
	value: Variant
) -> void:
	if not _is_integer_value(value):
		issues.append("non_integer_%s_tile_id:%s" % [record_kind, str(record_id)])
		return
	var tile_id := int(value)
	if tile_id < 0 or tile_id >= CityTerrainMapScript.CELL_COUNT:
		issues.append("invalid_%s_tile_id:%s:%d" % [record_kind, str(record_id), tile_id])


static func _validate_snapshot_tile_array(
	source: Variant,
	issues: Array[String],
	field_label: String,
	allow_empty: bool,
	reject_duplicates: bool,
	require_cardinal_contiguity: bool,
	topology_map
) -> Array[int]:
	var result: Array[int] = []
	if not source is Array:
		issues.append("%s_not_array" % field_label)
		return result
	if not allow_empty and (source as Array).is_empty():
		issues.append("%s_required" % field_label)
	var seen: Dictionary = {}
	var previous_tile := -1
	var previous_valid := false
	for index in (source as Array).size():
		var value: Variant = (source as Array)[index]
		if not _is_integer_value(value):
			issues.append("non_integer_%s:%d" % [field_label, index])
			previous_valid = false
			continue
		var tile_id := int(value)
		if tile_id < 0 or tile_id >= CityTerrainMapScript.CELL_COUNT:
			issues.append("invalid_%s:%d" % [field_label, tile_id])
			previous_valid = false
			continue
		if reject_duplicates and seen.has(tile_id):
			issues.append("duplicate_%s:%d" % [field_label, tile_id])
		if require_cardinal_contiguity and previous_valid and not _snapshot_tiles_are_cardinal_neighbors(previous_tile, tile_id, topology_map):
			issues.append("non_cardinal_%s:%d:%d" % [field_label, previous_tile, tile_id])
		seen[tile_id] = true
		result.append(tile_id)
		previous_tile = tile_id
		previous_valid = true
	return result


static func _snapshot_tiles_are_cardinal_neighbors(first_tile: int, second_tile: int, topology_map) -> bool:
	var first_coordinate: Vector2i = topology_map.coordinate_for_tile_id(first_tile)
	var second_coordinate: Vector2i = topology_map.coordinate_for_tile_id(second_tile)
	return (
		first_coordinate != CityTerrainMapScript.INVALID_COORDINATE
		and second_coordinate != CityTerrainMapScript.INVALID_COORDINATE
		and absi(first_coordinate.x - second_coordinate.x) + absi(first_coordinate.y - second_coordinate.y) == 1
	)


static func _append_snapshot_demolition_plan_issues(
	issues: Array[String],
	project_id: Variant,
	plan: Dictionary,
	project_status: String,
	segment_records: Dictionary,
	facility_records: Dictionary,
	station_records: Dictionary
) -> void:
	var target_specs: Array[Dictionary] = [
		{"field": "segment_ids", "kind": "segment", "records": segment_records},
		{"field": "facility_ids", "kind": "facility", "records": facility_records},
		{"field": "station_ids", "kind": "station", "records": station_records},
	]
	var target_count := 0
	var require_live_references := project_status in ["planned", "under_construction"]
	for spec: Dictionary in target_specs:
		var field_name := str(spec["field"])
		var target_value: Variant = plan.get(field_name, null)
		if not target_value is Array:
			issues.append("demolition_%s_not_array:%s" % [field_name, str(project_id)])
			continue
		var seen_ids: Dictionary = {}
		var records: Dictionary = spec["records"]
		for index in (target_value as Array).size():
			var id_value: Variant = (target_value as Array)[index]
			if not id_value is String or str(id_value).is_empty():
				issues.append("invalid_demolition_%s_id:%s:%d" % [str(spec["kind"]), str(project_id), index])
				continue
			var target_id := str(id_value)
			target_count += 1
			if seen_ids.has(target_id):
				issues.append("duplicate_demolition_%s_id:%s:%s" % [str(spec["kind"]), str(project_id), target_id])
			seen_ids[target_id] = true
			if require_live_references and not records.has(target_id):
				issues.append("missing_demolition_%s_reference:%s:%s" % [str(spec["kind"]), str(project_id), target_id])
	if target_count == 0:
		issues.append("demolition_targets_required:%s" % str(project_id))


static func _append_snapshot_route_issues(
	issues: Array[String],
	route_id: Variant,
	record: Dictionary,
	station_records: Dictionary,
	segment_records: Dictionary,
	topology_map,
	semantic_network
) -> void:
	var route_label := str(route_id)
	var validation_errors: Array[String] = []
	var validation_errors_shape_valid := true
	var errors_value: Variant = record.get("validation_errors", null)
	if not errors_value is Array:
		issues.append("route_validation_errors_not_array:%s" % route_label)
		validation_errors_shape_valid = false
	else:
		for error_index in (errors_value as Array).size():
			var error_value: Variant = (errors_value as Array)[error_index]
			if not error_value is String:
				issues.append("invalid_route_validation_error:%s:%d" % [route_label, error_index])
				validation_errors_shape_valid = false
			else:
				validation_errors.append(str(error_value))

	var mode_value: Variant = record.get("mode", null)
	var mode := str(mode_value) if mode_value is String else ""
	var mode_spec := TransportModesScript.route_spec(mode)
	if not mode_value is String or mode_spec.is_empty():
		issues.append("invalid_route_mode:%s" % route_label)
	if not record.get("name", null) is String:
		issues.append("invalid_route_name:%s" % route_label)
	if not record.get("vehicle_kind", null) is String:
		issues.append("invalid_route_vehicle_kind:%s" % route_label)
	elif not mode_spec.is_empty() and str(record.get("vehicle_kind", "")) != str(mode_spec.get("vehicle_kind", "")):
		issues.append("route_vehicle_kind_mismatch:%s" % route_label)

	var enabled_value: Variant = record.get("enabled", null)
	if not enabled_value is bool:
		issues.append("invalid_route_enabled:%s" % route_label)
	var status_value: Variant = record.get("status", null)
	var status := str(status_value) if status_value is String else ""
	if not status_value is String or status not in ["operational", "disabled", "suspended", "invalid"]:
		issues.append("invalid_route_status:%s" % route_label)
	elif enabled_value is bool and validation_errors_shape_valid:
		var route_is_valid := validation_errors.is_empty()
		var expected_status := "operational" if route_is_valid and bool(enabled_value) else "disabled"
		if not route_is_valid:
			expected_status = "suspended" if bool(enabled_value) else "invalid"
		if status != expected_status:
			issues.append("route_status_mismatch:%s:%s:%s" % [route_label, status, expected_status])

	_append_snapshot_route_integer_issue(issues, route_label, record, "fleet_size", 1, "fleet_required", validation_errors)
	_append_snapshot_route_integer_issue(issues, route_label, record, "headway_minutes", 1, "invalid_headway", validation_errors)
	_append_snapshot_route_integer_issue(issues, route_label, record, "fare", 0, "invalid_fare", validation_errors)
	var loop_value: Variant = record.get("loop_seconds", null)
	if not _is_number(loop_value) or float(loop_value) <= 0.0:
		issues.append("invalid_route_loop_seconds:%s" % route_label)

	var stop_ids: Array[String] = []
	var expected_station_tiles: Array[int] = []
	var stop_value: Variant = record.get("stop_ids", null)
	if not stop_value is Array:
		issues.append("route_stop_ids_not_array:%s" % route_label)
	else:
		var seen_stops: Dictionary = {}
		for stop_index in (stop_value as Array).size():
			var stop_variant: Variant = (stop_value as Array)[stop_index]
			if not stop_variant is String or str(stop_variant).is_empty():
				issues.append("invalid_route_stop_id:%s:%d" % [route_label, stop_index])
				continue
			var stop_id := str(stop_variant)
			stop_ids.append(stop_id)
			if seen_stops.has(stop_id):
				if not validation_errors.has("duplicate_stop:%s" % stop_id):
					issues.append("undeclared_duplicate_route_stop:%s:%s" % [route_label, stop_id])
				continue
			seen_stops[stop_id] = true
			if not station_records.has(stop_id):
				if not validation_errors.has("station_not_found:%s" % stop_id):
					issues.append("missing_route_stop_reference:%s:%s" % [route_label, stop_id])
				continue
			if not station_records[stop_id] is Dictionary:
				continue
			var station: Dictionary = station_records[stop_id]
			expected_station_tiles.append(int(station.get("tile_id", -1)))
			if (
				not mode_spec.is_empty()
				and str(station.get("building_name", "")) != str(mode_spec.get("station_name", ""))
				and not validation_errors.has("incompatible_station:%s" % stop_id)
			):
				issues.append("undeclared_incompatible_route_stop:%s:%s" % [route_label, stop_id])
		if not mode_spec.is_empty():
			var minimum_stops := int(mode_spec.get("minimum_stops", 1))
			if stop_ids.size() < minimum_stops and not validation_errors.has("insufficient_stops"):
				issues.append("undeclared_insufficient_route_stops:%s" % route_label)

	var station_tiles := _validate_snapshot_tile_array(
		record.get("station_tile_ids", null), issues, "route_station_tiles:%s" % route_label, true, false, false,
		topology_map
	)
	if stop_value is Array and record.get("station_tile_ids", null) is Array and station_tiles != expected_station_tiles:
		issues.append("route_station_tile_reference_mismatch:%s" % route_label)

	var path_tiles := _validate_snapshot_tile_array(
		record.get("path_tile_ids", null), issues, "route_path:%s" % route_label, true, false, true,
		topology_map
	)
	if validation_errors_shape_valid and validation_errors.is_empty() and path_tiles.is_empty():
		issues.append("route_path_required:%s" % route_label)
	if not mode_spec.is_empty() and not path_tiles.is_empty():
		var allowed_kinds: Array[String] = [str(mode_spec.get("guideway_kind", ""))]
		if mode == "air":
			allowed_kinds = ["taxiway", "runway"]
		var network_tiles := _snapshot_segment_tiles_for_kinds(segment_records, allowed_kinds)
		for tile_id: int in path_tiles:
			if not network_tiles.has(tile_id):
				issues.append("missing_route_path_reference:%s:%d" % [route_label, tile_id])
	if semantic_network != null and _snapshot_route_record_recompute_safe(record):
		_append_snapshot_route_canonical_issues(issues, route_label, record, semantic_network)


static func _snapshot_route_semantic_inputs_safe(
	segment_records: Dictionary,
	facility_records: Dictionary,
	station_records: Dictionary
) -> bool:
	for segment_value: Variant in segment_records.values():
		if not segment_value is Dictionary:
			return false
		var segment: Dictionary = segment_value
		if (
			str(segment.get("kind", "")) not in TransportModesScript.SEGMENT_KINDS
			or not _snapshot_tile_array_recompute_safe(segment.get("tile_path", null))
		):
			return false
	for facility_value: Variant in facility_records.values():
		if not facility_value is Dictionary:
			return false
		var facility: Dictionary = facility_value
		if (
			str(facility.get("kind", "")) not in TransportModesScript.FACILITY_KINDS
			or not _snapshot_tile_value_recompute_safe(facility.get("tile_id", null))
		):
			return false
	for station_value: Variant in station_records.values():
		if not station_value is Dictionary:
			return false
		var station: Dictionary = station_value
		if (
			str(station.get("building_name", "")) not in TransportModesScript.STATION_KINDS
			or not _snapshot_tile_value_recompute_safe(station.get("tile_id", null))
		):
			return false
	return true


static func _snapshot_route_record_recompute_safe(record: Dictionary) -> bool:
	var mode_value: Variant = record.get("mode", null)
	if not mode_value is String or TransportModesScript.route_spec(str(mode_value)).is_empty():
		return false
	var stop_ids_value: Variant = record.get("stop_ids", null)
	if not stop_ids_value is Array:
		return false
	for stop_id_value: Variant in stop_ids_value:
		if not stop_id_value is String:
			return false
	return (
		_is_integer_value(record.get("fleet_size", null))
		and _is_integer_value(record.get("headway_minutes", null))
		and _is_integer_value(record.get("fare", null))
		and record.get("enabled", null) is bool
	)


static func _snapshot_tile_array_recompute_safe(value: Variant) -> bool:
	if not value is Array:
		return false
	for tile_value: Variant in value:
		if not _snapshot_tile_value_recompute_safe(tile_value):
			return false
	return true


static func _snapshot_tile_value_recompute_safe(value: Variant) -> bool:
	return (
		_is_integer_value(value)
		and int(value) >= 0
		and int(value) < CityTerrainMapScript.CELL_COUNT
	)


static func _append_snapshot_route_canonical_issues(
	issues: Array[String],
	route_id: String,
	record: Dictionary,
	semantic_network
) -> void:
	var quote: Dictionary = semantic_network.route_quote(record)
	if not bool(quote.get("ok", false)):
		issues.append("route_canonical_quote_failed:%s" % route_id)
		return
	if not _snapshot_string_array_matches(
		record.get("validation_errors", null), quote.get("validation_errors", [])
	):
		issues.append("route_validation_errors_canonical_mismatch:%s" % route_id)
	if not _snapshot_integer_array_matches(
		record.get("path_tile_ids", null), quote.get("path_tile_ids", [])
	):
		issues.append("route_path_canonical_mismatch:%s" % route_id)
	if not _snapshot_integer_array_matches(
		record.get("station_tile_ids", null), quote.get("station_tile_ids", [])
	):
		issues.append("route_station_tiles_canonical_mismatch:%s" % route_id)
	if (
		not record.get("vehicle_kind", null) is String
		or str(record.get("vehicle_kind", "")) != str(quote.get("vehicle_kind", ""))
	):
		issues.append("route_vehicle_kind_canonical_mismatch:%s" % route_id)
	var loop_value: Variant = record.get("loop_seconds", null)
	var expected_loop_value: Variant = quote.get("loop_seconds", null)
	if (
		not _is_number(loop_value)
		or not _is_number(expected_loop_value)
		or not is_equal_approx(float(loop_value), float(expected_loop_value))
	):
		issues.append("route_loop_seconds_canonical_mismatch:%s" % route_id)
	var expected_status := "operational" if bool(quote.get("valid", false)) and bool(record.get("enabled", false)) else "disabled"
	if not bool(quote.get("valid", false)):
		expected_status = "suspended" if bool(record.get("enabled", false)) else "invalid"
	if not record.get("status", null) is String or str(record.get("status", "")) != expected_status:
		issues.append("route_status_canonical_mismatch:%s:%s" % [route_id, expected_status])


static func _snapshot_string_array_matches(actual_value: Variant, expected_value: Variant) -> bool:
	if not actual_value is Array or not expected_value is Array:
		return false
	if (actual_value as Array).size() != (expected_value as Array).size():
		return false
	for index in (actual_value as Array).size():
		var actual_item: Variant = (actual_value as Array)[index]
		var expected_item: Variant = (expected_value as Array)[index]
		if not actual_item is String or not expected_item is String or str(actual_item) != str(expected_item):
			return false
	return true


static func _snapshot_integer_array_matches(actual_value: Variant, expected_value: Variant) -> bool:
	if not actual_value is Array or not expected_value is Array:
		return false
	if (actual_value as Array).size() != (expected_value as Array).size():
		return false
	for index in (actual_value as Array).size():
		var actual_item: Variant = (actual_value as Array)[index]
		var expected_item: Variant = (expected_value as Array)[index]
		if (
			not _is_integer_value(actual_item)
			or not _is_integer_value(expected_item)
			or int(actual_item) != int(expected_item)
		):
			return false
	return true


static func _append_snapshot_route_integer_issue(
	issues: Array[String],
	route_id: String,
	record: Dictionary,
	field_name: String,
	minimum_value: int,
	expected_error: String,
	validation_errors: Array[String]
) -> void:
	var value: Variant = record.get(field_name, null)
	if not _is_integer_value(value):
		issues.append("non_integer_route_%s:%s" % [field_name, route_id])
		return
	if int(value) < minimum_value and not validation_errors.has(expected_error):
		issues.append("undeclared_invalid_route_%s:%s" % [field_name, route_id])


static func _snapshot_segment_tiles_for_kinds(segment_records: Dictionary, kinds: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for segment_variant: Variant in segment_records.values():
		if not segment_variant is Dictionary:
			continue
		var segment: Dictionary = segment_variant
		if str(segment.get("kind", "")) not in kinds or not segment.get("tile_path", null) is Array:
			continue
		for tile_variant: Variant in segment.get("tile_path", []):
			if _is_integer_value(tile_variant):
				result[int(tile_variant)] = true
	return result


static func _is_integer_value(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		return is_finite(float(value)) and float(value) == roundf(float(value))
	return false


static func _is_number(value: Variant) -> bool:
	return value is int or (value is float and is_finite(float(value)))


static func _is_json_safe(value: Variant) -> bool:
	if value is float:
		return is_finite(float(value))
	if value == null or value is bool or value is int or value is String:
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
