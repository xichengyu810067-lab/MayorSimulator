extends SceneTree

const TransportModesScript = preload("res://data/catalogs/transport_modes.gd")
const TransportNetworkSystemScript = preload("res://scripts/systems/city/transport_network_system.gd")
const CityTerrainMapScript = preload("res://scripts/world/city_terrain_map.gd")

var failed := false
var checks := 0
var terrain


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	terrain = CityTerrainMapScript.new()
	_validate_catalog_and_planning_rules()
	_validate_demolition_races_and_snapshot_shapes()
	_validate_active_project_round_trips_and_reserved_ids()
	_validate_multi_attachment_route_continuity()
	_validate_disconnected_station_never_spawns_vehicle()
	_validate_complete_networks_and_persistence()
	if failed:
		quit(1)
	else:
		print("Transport network system test passed. Modes=4 Overlay=true Checks=%d" % checks)
		quit(0)


func _validate_catalog_and_planning_rules() -> void:
	var catalog := TransportModesScript.validation_snapshot()
	_check(bool(catalog.get("valid", false)), "transport mode catalog must be internally valid")
	_check(str(catalog.get("infrastructure_layer", "")) == "transport_overlay", "infrastructure must be separate from terrain")
	_check(Array(catalog.get("segment_kinds", [])).size() == 5, "all five infrastructure segment kinds must be cataloged")

	var planner = TransportNetworkSystemScript.new()
	var tree_tile := _tile(0, 0)
	terrain.configure_tile(tree_tile, "trees")
	var terrain_rejected: Dictionary = planner.quote_project("build", {
		"segments": [{"kind": "road", "tile_path": [tree_tile]}],
	}, terrain)
	_check(not bool(terrain_rejected.get("ok", false)) and _issues_have(terrain_rejected, "terrain_not_flat"), "non-flat terrain must reject infrastructure")
	terrain.configure_tile(tree_tile, "flat_grass")

	var lake_tile := _tile(1, 1)
	terrain.configure_tile(lake_tile, "river_lake")
	var before_lake_quote: Dictionary = planner.to_dict()
	var lake_plan := {
		"segments": [{"id": "lake_road", "kind": "road", "tile_path": [lake_tile]}],
	}
	var lake_quote: Dictionary = planner.quote_project("build", lake_plan, terrain)
	_check(
		not bool(lake_quote.get("ok", false)) and _issues_have(lake_quote, "terrain_not_flat"),
		"unflattened river/lake must reject a direct road quote"
	)
	_check(planner.to_dict() == before_lake_quote, "rejected river/lake quote mutated transport authority")
	var lake_start: Dictionary = planner.start_project("build", lake_plan, terrain)
	_check(
		not bool(lake_start.get("ok", false)) and _issues_have(lake_start, "terrain_not_flat"),
		"unflattened river/lake must reject direct project start"
	)
	_check(planner.to_dict() == before_lake_quote, "rejected river/lake start mutated transport authority")
	terrain.configure_tile(lake_tile, "flat_grass")

	var non_cardinal: Dictionary = planner.quote_project("build", {
		"segments": [{"kind": "road", "tile_path": [_tile(0, 0), _tile(1, 1)]}],
	}, terrain)
	_check(not bool(non_cardinal.get("ok", false)) and _issues_have(non_cardinal, "non_cardinal_segment_path"), "diagonal tile paths must be rejected")

	var occupied: Dictionary = planner.quote_project("build", {
		"segments": [{"kind": "road", "tile_path": [_tile(0, 0)]}],
	}, terrain, [_tile(0, 0)])
	_check(not bool(occupied.get("ok", false)) and _issues_have(occupied, "tile_occupied"), "occupied tiles must reject infrastructure")

	var construction: Dictionary = planner.quote_project("build", {
		"segments": [{"kind": "road", "tile_path": [_tile(0, 0)]}],
	}, terrain, [], [_tile(0, 0)])
	_check(not bool(construction.get("ok", false)) and _issues_have(construction, "tile_under_construction"), "active construction tiles must reject infrastructure")


func _validate_disconnected_station_never_spawns_vehicle() -> void:
	var network = TransportNetworkSystemScript.new()
	_check(bool(network.register_station("orphan_metro_a", "捷運站", _tile(1, 1)).get("ok", false)), "first orphan metro station registration failed")
	_check(bool(network.register_station("orphan_metro_b", "捷運站", _tile(4, 1)).get("ok", false)), "second orphan metro station registration failed")
	var created: Dictionary = network.create_route({
		"id": "orphan_metro_line",
		"name": "未連通捷運",
		"mode": "metro",
		"stop_ids": ["orphan_metro_a", "orphan_metro_b"],
		"fleet_size": 2,
		"headway_minutes": 6,
		"fare": 30,
		"enabled": true,
	})
	_check(bool(created.get("ok", false)) and not bool(created.get("valid", true)), "disconnected route should be retained as invalid player intent")
	_check(str(created.get("route", {}).get("status", "")) == "suspended", "enabled disconnected route must be suspended")
	_check(network.active_lines().is_empty(), "disconnected stations must never expose an active line")
	var runtime: Dictionary = network.visual_runtime_snapshot([], terrain)
	_check(Array(runtime.get("operational_lines", [])).is_empty(), "disconnected station runtime must contain no vehicle-producing line")
	_check(is_equal_approx(network.service_operational_factor("metro"), 0.0), "disconnected metro must produce no service factor")
	_check(network.service_revenue("metro", 300, {"base_uses": 24, "reasonable": 30}) == 0, "disconnected metro must produce no service revenue")

	var bus_network = TransportNetworkSystemScript.new()
	_check(bool(bus_network.register_station("orphan_bus_a", "公車站", _tile(1, 2)).get("ok", false)), "first orphan bus station registration failed")
	_check(bool(bus_network.register_station("orphan_bus_b", "公車站", _tile(4, 2)).get("ok", false)), "second orphan bus station registration failed")
	var bus_created: Dictionary = bus_network.create_route({
		"id": "orphan_bus_line",
		"name": "未接道路公車",
		"mode": "bus",
		"stop_ids": ["orphan_bus_a", "orphan_bus_b"],
		"fleet_size": 2,
		"headway_minutes": 8,
		"fare": 15,
		"enabled": true,
	})
	_check(bool(bus_created.get("ok", false)) and not bool(bus_created.get("valid", true)), "bus route without station road access must remain invalid")
	_check(bus_network.active_lines().is_empty(), "bus stations without road access must expose zero operational lines")
	_check(bus_network.service_revenue("bus", 300, {"base_uses": 24, "reasonable": 15}) == 0, "bus stations without road access must earn zero revenue")
	var bus_runtime: Dictionary = bus_network.visual_runtime_snapshot([], terrain)
	_check(Array(bus_runtime.get("operational_lines", [])).is_empty(), "bus stations without road access must spawn zero vehicle-producing lines")
	_check(Array(bus_runtime.get("station_access_edges", [])).is_empty(), "bus stations without road access must expose no derived visual connector")


func _validate_demolition_races_and_snapshot_shapes() -> void:
	var network = TransportNetworkSystemScript.new()
	var segment_tile := _tile(0, 5)
	var facility_tile := _tile(1, 5)
	var build_plan := {
		"segments": [{"id": "race_road", "kind": "road", "tile_path": [segment_tile]}],
		"facilities": [{"id": "race_depot", "kind": "bus_depot", "tile_id": facility_tile}],
	}
	_check(_build_and_complete(network, build_plan), "demolition-race fixture must build")
	var externally_blocked := network.quote_project(
		"demolish", {"segment_ids": ["race_road"]}, terrain, [], [segment_tile]
	)
	_check(not bool(externally_blocked.get("ok", false)) and _issues_have(externally_blocked, "tile_under_construction"), "external construction tiles must reject overlapping demolition")
	var duplicate_target := network.quote_project(
		"demolish", {"facility_ids": ["race_depot", "race_depot"]}, terrain
	)
	_check(not bool(duplicate_target.get("ok", false)) and _issues_have(duplicate_target, "duplicate_demolition_target"), "one demolition plan must not charge the same facility twice")
	var first_plan := network.plan_project(
		"demolish", {"segment_ids": ["race_road"], "facility_ids": ["race_depot"]}, terrain
	)
	_check(bool(first_plan.get("ok", false)), "first demolition plan must be accepted")
	var overlapping_segment := network.quote_project("demolish", {"segment_ids": ["race_road"]}, terrain)
	var overlapping_facility := network.quote_project("demolish", {"facility_ids": ["race_depot"]}, terrain)
	_check(not bool(overlapping_segment.get("ok", false)) and _issues_have(overlapping_segment, "tile_under_construction"), "active demolition project must reserve its whole segment")
	_check(not bool(overlapping_facility.get("ok", false)) and _issues_have(overlapping_facility, "tile_under_construction"), "active demolition project must reserve its facility")

	var missing_at_completion = TransportNetworkSystemScript.new()
	_check(_build_and_complete(missing_at_completion, {
		"segments": [{"id": "vanishing_road", "kind": "road", "tile_path": [_tile(0, 6)]}],
	}), "missing-target completion fixture must build")
	var demolition_started: Dictionary = missing_at_completion.start_project(
		"demolish", {"segment_ids": ["vanishing_road"]}, terrain
	)
	_check(bool(demolition_started.get("ok", false)), "missing-target demolition fixture must start")
	missing_at_completion.segments.erase("vanishing_road")
	var completion: Dictionary = missing_at_completion.complete_project(str(demolition_started.get("project", {}).get("id", "")))
	_check(not bool(completion.get("ok", false)) and _issues_have(completion, "segment_not_found"), "demolition completion must fail when its authoritative target vanished")

	var shape_network = TransportNetworkSystemScript.new()
	_check(_build_and_complete(shape_network, {
		"segments": [
			{"id": "shape_road", "kind": "road", "tile_path": _horizontal_path(7, 1, 3)},
			{"id": "shape_metro", "kind": "metro_track", "tile_path": [_tile(2, 6), _tile(2, 7)]},
		],
		"facilities": [{"id": "shape_depot", "kind": "bus_depot", "tile_id": _tile(1, 8)}],
		"stations": [
			{"id": "shape_stop_a", "building_name": "公車站", "tile_id": _tile(2, 8)},
			{"id": "shape_stop_b", "building_name": "公車站", "tile_id": _tile(3, 8)},
		],
	}), "snapshot-shape fixture must build")
	_check(_route_is_operational(shape_network.create_route({
		"id": "shape_route", "mode": "bus", "stop_ids": ["shape_stop_a", "shape_stop_b"],
		"fleet_size": 1, "headway_minutes": 10, "fare": 15, "enabled": true,
	})), "snapshot-shape route fixture must become operational")
	var shape_crossing_id := "level_crossing_%03d" % _tile(2, 7)
	_check(shape_network.crossings.has(shape_crossing_id), "snapshot fixture crossing must come from a real road-track overlap")
	var valid_snapshot: Dictionary = shape_network.to_dict()
	var valid_snapshot_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(valid_snapshot)
	_check(bool(valid_snapshot_result.get("valid", false)), "complete transport record shapes must validate: %s" % [valid_snapshot_result.get("issues", [])])
	var cross_collection_id := valid_snapshot.duplicate(true)
	cross_collection_id["stations"]["shape_road"] = {
		"id": "shape_road",
		"building_name": "公車站",
		"tile_id": _tile(0, 9),
		"status": "completed",
		"project_id": "external",
	}
	var cross_collection_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(cross_collection_id)
	_check(
		not bool(cross_collection_result.get("valid", true))
		and _issues_have(cross_collection_result, "transport_entity_id_cross_collection"),
		"one live entity ID must not be reused across transport collections"
	)
	var duplicate_live_layer := valid_snapshot.duplicate(true)
	var duplicate_road: Dictionary = Dictionary(duplicate_live_layer["segments"]["shape_road"]).duplicate(true)
	duplicate_road["id"] = "forged_duplicate_road"
	duplicate_live_layer["segments"]["forged_duplicate_road"] = duplicate_road
	var duplicate_live_layer_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(duplicate_live_layer)
	_check(
		not bool(duplicate_live_layer_result.get("valid", true))
		and _issues_have(duplicate_live_layer_result, "duplicate_transport_segment_layer"),
		"snapshot validation must reject a duplicate live segment layer"
	)
	var ghost_crossing := valid_snapshot.duplicate(true)
	ghost_crossing["crossings"]["level_crossing_000"] = {
		"id": "level_crossing_000", "kind": "level_crossing", "tile_id": _tile(0, 0),
		"track_kinds": ["metro_track"], "status": "completed", "build_cost": 900,
		"monthly_maintenance": 40,
	}
	var ghost_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(ghost_crossing)
	_check(not bool(ghost_result.get("valid", true)) and _issues_have(ghost_result, "ghost_crossing"), "crossing without a live road-track overlap must fail")
	var wrong_crossing_tracks := valid_snapshot.duplicate(true)
	wrong_crossing_tracks["crossings"][shape_crossing_id]["track_kinds"] = ["rail_track"]
	var wrong_tracks_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(wrong_crossing_tracks)
	_check(not bool(wrong_tracks_result.get("valid", true)) and _issues_have(wrong_tracks_result, "crossing_track_kinds_mismatch"), "crossing track_kinds must exactly match the live overlap")
	var duplicate_crossing_tile := valid_snapshot.duplicate(true)
	var duplicate_crossing_record: Dictionary = Dictionary(duplicate_crossing_tile["crossings"][shape_crossing_id]).duplicate(true)
	duplicate_crossing_record["id"] = "duplicate_crossing_id"
	duplicate_crossing_tile["crossings"]["duplicate_crossing_id"] = duplicate_crossing_record
	var duplicate_crossing_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(duplicate_crossing_tile)
	_check(not bool(duplicate_crossing_result.get("valid", true)) and _issues_have(duplicate_crossing_result, "duplicate_crossing_tile"), "two crossing IDs must not claim one overlap tile")
	var missing_rebuilt_crossing := valid_snapshot.duplicate(true)
	missing_rebuilt_crossing["crossings"].erase(shape_crossing_id)
	var missing_crossing_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(missing_rebuilt_crossing)
	_check(not bool(missing_crossing_result.get("valid", true)) and _issues_have(missing_crossing_result, "missing_rebuilt_crossing"), "every live road-track overlap must have its canonical crossing record")
	for collection_name: String in ["projects", "segments", "facilities", "stations", "crossings", "routes"]:
		var malformed_collection := valid_snapshot.duplicate(true)
		malformed_collection[collection_name] = []
		var malformed_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(malformed_collection)
		_check(not bool(malformed_result.get("valid", true)) and _issues_have(malformed_result, "%s_not_dictionary" % collection_name), "%s collection must reject non-Dictionary input" % collection_name)
	var missing_collection := valid_snapshot.duplicate(true)
	missing_collection.erase("routes")
	_check(not bool(TransportNetworkSystemScript.validate_snapshot(missing_collection).get("valid", true)), "missing transport snapshot collection must fail")
	var missing_field_cases := {
		"projects": [str(valid_snapshot["projects"].keys()[0]), "quote"],
		"segments": ["shape_road", "kind"],
		"facilities": ["shape_depot", "tile_id"],
		"stations": ["shape_stop_a", "building_name"],
		"crossings": [shape_crossing_id, "track_kinds"],
		"routes": ["shape_route", "fare"],
	}
	for collection_name: String in missing_field_cases.keys():
		var malformed_record := valid_snapshot.duplicate(true)
		var case_data: Array = missing_field_cases[collection_name]
		Dictionary(malformed_record[collection_name][str(case_data[0])]).erase(str(case_data[1]))
		_check(not bool(TransportNetworkSystemScript.validate_snapshot(malformed_record).get("valid", true)), "%s record with a missing field must fail" % collection_name)

	for sequence_field: String in [
		"next_project_sequence", "next_segment_sequence", "next_facility_sequence",
		"next_station_sequence", "next_route_sequence",
	]:
		var missing_sequence := valid_snapshot.duplicate(true)
		missing_sequence.erase(sequence_field)
		_check(not bool(TransportNetworkSystemScript.validate_snapshot(missing_sequence).get("valid", true)), "%s must be present" % sequence_field)
		var non_integer_sequence := valid_snapshot.duplicate(true)
		non_integer_sequence[sequence_field] = "1"
		_check(not bool(TransportNetworkSystemScript.validate_snapshot(non_integer_sequence).get("valid", true)), "%s must be an integer" % sequence_field)

	var first_project_id := str(valid_snapshot["projects"].keys()[0])
	for plan_field: String in ["segments", "facilities", "stations"]:
		var non_array_build_plan := valid_snapshot.duplicate(true)
		non_array_build_plan["projects"][first_project_id]["plan"][plan_field] = "not_an_array"
		var non_array_plan_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(non_array_build_plan)
		_check(not bool(non_array_plan_result.get("valid", true)) and _issues_have(non_array_plan_result, "build_plan_%s_not_array" % plan_field), "build plan %s must be an Array" % plan_field)
	var non_dictionary_build_item := valid_snapshot.duplicate(true)
	# Runtime snapshots preserve the model's Array[Dictionary] typing. Replace
	# the collection with an intentionally untyped corrupt payload instead of
	# asking Godot to reject the fixture mutation before the validator sees it.
	non_dictionary_build_item["projects"][first_project_id]["plan"]["segments"] = ["not_a_dictionary"]
	var non_dictionary_item_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(non_dictionary_build_item)
	_check(not bool(non_dictionary_item_result.get("valid", true)) and _issues_have(non_dictionary_item_result, "build_plan_segment_not_dictionary"), "every build-plan segment must be a Dictionary")
	var empty_build_item_id := valid_snapshot.duplicate(true)
	empty_build_item_id["projects"][first_project_id]["plan"]["segments"][0]["id"] = ""
	var empty_item_id_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(empty_build_item_id)
	_check(not bool(empty_item_id_result.get("valid", true)) and _issues_have(empty_item_id_result, "invalid_build_plan_segment_id"), "persisted build-plan IDs must be non-empty")
	var invalid_build_segment_kind := valid_snapshot.duplicate(true)
	invalid_build_segment_kind["projects"][first_project_id]["plan"]["segments"][0]["kind"] = "teleporter"
	var invalid_segment_kind_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(invalid_build_segment_kind)
	_check(not bool(invalid_segment_kind_result.get("valid", true)) and _issues_have(invalid_segment_kind_result, "invalid_build_segment_kind"), "build-plan segment kind must use catalog normalization")
	var invalid_build_facility_tile := valid_snapshot.duplicate(true)
	invalid_build_facility_tile["projects"][first_project_id]["plan"]["facilities"][0]["tile_id"] = "1"
	var invalid_facility_tile_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(invalid_build_facility_tile)
	_check(not bool(invalid_facility_tile_result.get("valid", true)) and _issues_have(invalid_facility_tile_result, "non_integer_build_facility_tile_id"), "build-plan facility tile must stay integer-normalized")
	var invalid_build_station_kind := valid_snapshot.duplicate(true)
	invalid_build_station_kind["projects"][first_project_id]["plan"]["stations"][0]["building_name"] = "teleporter"
	var invalid_station_kind_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(invalid_build_station_kind)
	_check(not bool(invalid_station_kind_result.get("valid", true)) and _issues_have(invalid_station_kind_result, "invalid_build_station_kind"), "build-plan station building must use catalog normalization")
	var duplicate_build_item_id := valid_snapshot.duplicate(true)
	duplicate_build_item_id["projects"][first_project_id]["plan"]["segments"][1]["id"] = "shape_road"
	duplicate_build_item_id["projects"][first_project_id]["quote"]["plan"] = duplicate_build_item_id["projects"][first_project_id]["plan"].duplicate(true)
	var duplicate_item_id_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(duplicate_build_item_id)
	_check(not bool(duplicate_item_id_result.get("valid", true)) and _issues_have(duplicate_item_id_result, "duplicate_build_plan_id"), "IDs must be unique inside one build project")
	var live_project_status_mismatch := valid_snapshot.duplicate(true)
	live_project_status_mismatch["projects"][first_project_id]["status"] = "planned"
	var live_status_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(live_project_status_mismatch)
	_check(not bool(live_status_result.get("valid", true)) and _issues_have(live_status_result, "active_build_live_id_conflict"), "planned build projects must not already own live records")
	var missing_completed_record := valid_snapshot.duplicate(true)
	missing_completed_record["segments"].erase("shape_metro")
	missing_completed_record["crossings"].erase(shape_crossing_id)
	var missing_completed_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(missing_completed_record)
	_check(not bool(missing_completed_result.get("valid", true)) and _issues_have(missing_completed_result, "completed_build_record_missing"), "completed build records may disappear only with completed demolition history")
	var mismatched_quote_total := valid_snapshot.duplicate(true)
	mismatched_quote_total["projects"][first_project_id]["quote"]["total_cost"] = int(mismatched_quote_total["projects"][first_project_id]["total_cost"]) + 1
	var quote_total_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(mismatched_quote_total)
	_check(not bool(quote_total_result.get("valid", true)) and _issues_have(quote_total_result, "project_quote_total_mismatch"), "project and quote totals must agree")
	var mismatched_quote_plan := valid_snapshot.duplicate(true)
	mismatched_quote_plan["projects"][first_project_id]["quote"]["plan"]["title"] = "tampered"
	var quote_plan_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(mismatched_quote_plan)
	_check(not bool(quote_plan_result.get("valid", true)) and _issues_have(quote_plan_result, "project_quote_plan_mismatch"), "project and quote plans must agree")
	var mismatched_quote_breakdown := valid_snapshot.duplicate(true)
	mismatched_quote_breakdown["projects"][first_project_id]["quote"]["breakdown"]["segments"] = 1
	var quote_breakdown_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(mismatched_quote_breakdown)
	_check(not bool(quote_breakdown_result.get("valid", true)) and _issues_have(quote_breakdown_result, "project_quote"), "project quote breakdown must agree with plan and total")
	var generated_sequence_cases := [
		["next_project_sequence", "projects", first_project_id, "transport_project_000999"],
		["next_segment_sequence", "segments", "shape_road", "transport_segment_000999"],
		["next_facility_sequence", "facilities", "shape_depot", "transport_facility_000999"],
		["next_station_sequence", "stations", "shape_stop_a", "transport_station_000999"],
		["next_route_sequence", "routes", "shape_route", "route_000999"],
	]
	for sequence_case: Array in generated_sequence_cases:
		var stale_sequence := valid_snapshot.duplicate(true)
		var sequence_collection := str(sequence_case[1])
		var generated_id := str(sequence_case[3])
		var generated_record: Dictionary = Dictionary(stale_sequence[sequence_collection][str(sequence_case[2])]).duplicate(true)
		generated_record["id"] = generated_id
		stale_sequence[sequence_collection][generated_id] = generated_record
		stale_sequence[str(sequence_case[0])] = 999
		var stale_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(stale_sequence)
		_check(not bool(stale_result.get("valid", true)) and _issues_have(stale_result, "sequence_not_ahead:%s" % str(sequence_case[0])), "%s must stay ahead of generated IDs" % str(sequence_case[0]))

	var identity_cases := {
		"projects": first_project_id,
		"segments": "shape_road",
		"facilities": "shape_depot",
		"stations": "shape_stop_a",
		"crossings": shape_crossing_id,
		"routes": "shape_route",
	}
	for collection_name: String in identity_cases.keys():
		var mismatched_identity := valid_snapshot.duplicate(true)
		var record_id := str(identity_cases[collection_name])
		mismatched_identity[collection_name][record_id]["id"] = "mismatched_id"
		_check(not bool(TransportNetworkSystemScript.validate_snapshot(mismatched_identity).get("valid", true)), "%s dictionary key must match record.id" % collection_name)

	var malformed_segment_paths := {
		"non-integer": [_tile(1, 7), "bad", _tile(3, 7)],
		"negative": [_tile(1, 7), -1, _tile(3, 7)],
		"duplicate": [_tile(1, 7), _tile(2, 7), _tile(2, 7)],
		"non-cardinal": [_tile(1, 7), _tile(3, 7)],
	}
	for case_name: String in malformed_segment_paths.keys():
		var malformed_path := valid_snapshot.duplicate(true)
		malformed_path["segments"]["shape_road"]["tile_path"] = malformed_segment_paths[case_name]
		_check(not bool(TransportNetworkSystemScript.validate_snapshot(malformed_path).get("valid", true)), "segment path rejects %s tiles" % case_name)

	var planned_demolition: Dictionary = shape_network.plan_project(
		"demolish", {"segment_ids": ["shape_road"]}, terrain
	)
	_check(bool(planned_demolition.get("ok", false)), "snapshot demolition fixture must plan")
	var demolition_project_id := str(planned_demolition.get("project", {}).get("id", ""))
	var active_demolition_snapshot: Dictionary = shape_network.to_dict()
	var active_demolition_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(active_demolition_snapshot)
	_check(bool(active_demolition_result.get("valid", false)), "active demolition snapshot with live targets must validate: %s" % [active_demolition_result.get("issues", [])])
	var active_demolition_decoded: Variant = JSON.parse_string(JSON.stringify(active_demolition_snapshot))
	var active_demolition_json_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(active_demolition_decoded)
	_check(bool(active_demolition_json_result.get("valid", false)), "active demolition snapshot must validate after a JSON round trip: %s" % [active_demolition_json_result.get("issues", [])])
	for target_field: String in ["segment_ids", "facility_ids", "station_ids"]:
		var non_array_demolition_plan := active_demolition_snapshot.duplicate(true)
		non_array_demolition_plan["projects"][demolition_project_id]["plan"][target_field] = "not_an_array"
		_check(not bool(TransportNetworkSystemScript.validate_snapshot(non_array_demolition_plan).get("valid", true)), "demolition %s must be an Array" % target_field)
		var missing_demolition_reference := active_demolition_snapshot.duplicate(true)
		missing_demolition_reference["projects"][demolition_project_id]["plan"][target_field] = ["missing_target"]
		_check(not bool(TransportNetworkSystemScript.validate_snapshot(missing_demolition_reference).get("valid", true)), "active demolition %s must reference live records" % target_field)
	_check(bool(shape_network.start_project(demolition_project_id).get("ok", false)), "snapshot demolition fixture must start")
	_check(bool(shape_network.complete_project(demolition_project_id).get("ok", false)), "snapshot demolition fixture must complete")
	_check(bool(TransportNetworkSystemScript.validate_snapshot(shape_network.to_dict()).get("valid", false)), "completed demolition may retain historical IDs after its targets are removed")
	_check(_build_and_complete(shape_network, {
		"segments": [{"id": "shape_road", "kind": "road", "tile_path": _horizontal_path(7, 1, 3)}],
	}), "completed demolition target must be reusable by a later build")
	var rebuilt_history_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(shape_network.to_dict())
	_check(bool(rebuilt_history_result.get("valid", false)), "legally rebuilt IDs must not make completed build/demolition history invalid: %s" % [rebuilt_history_result.get("issues", [])])

	for numeric_field: String in ["fleet_size", "headway_minutes", "fare"]:
		var malformed_route_number := valid_snapshot.duplicate(true)
		malformed_route_number["routes"]["shape_route"][numeric_field] = "1"
		_check(not bool(TransportNetworkSystemScript.validate_snapshot(malformed_route_number).get("valid", true)), "route %s must be integer-typed" % numeric_field)
	var non_array_route_stops := valid_snapshot.duplicate(true)
	non_array_route_stops["routes"]["shape_route"]["stop_ids"] = "shape_stop_a"
	_check(not bool(TransportNetworkSystemScript.validate_snapshot(non_array_route_stops).get("valid", true)), "route stop IDs must be an Array")
	var missing_route_stop := valid_snapshot.duplicate(true)
	missing_route_stop["routes"]["shape_route"]["stop_ids"] = ["shape_stop_a", "missing_stop"]
	_check(not bool(TransportNetworkSystemScript.validate_snapshot(missing_route_stop).get("valid", true)), "operational route must not reference a missing stop")
	var malformed_route_path := valid_snapshot.duplicate(true)
	malformed_route_path["routes"]["shape_route"]["path_tile_ids"] = [_tile(1, 7), "bad"]
	_check(not bool(TransportNetworkSystemScript.validate_snapshot(malformed_route_path).get("valid", true)), "route path tiles must be integer-typed")
	var non_cardinal_route_path := valid_snapshot.duplicate(true)
	non_cardinal_route_path["routes"]["shape_route"]["path_tile_ids"] = [_tile(1, 7), _tile(3, 7)]
	_check(not bool(TransportNetworkSystemScript.validate_snapshot(non_cardinal_route_path).get("valid", true)), "route path must be cardinally contiguous")
	var missing_route_path_reference := valid_snapshot.duplicate(true)
	missing_route_path_reference["routes"]["shape_route"]["path_tile_ids"] = [_tile(0, 7)]
	_check(not bool(TransportNetworkSystemScript.validate_snapshot(missing_route_path_reference).get("valid", true)), "route path must reference its mode's authored network")
	var mismatched_route_station_tiles := valid_snapshot.duplicate(true)
	mismatched_route_station_tiles["routes"]["shape_route"]["station_tile_ids"] = [_tile(3, 8), _tile(2, 8)]
	_check(not bool(TransportNetworkSystemScript.validate_snapshot(mismatched_route_station_tiles).get("valid", true)), "route station tiles must match ordered stop references")
	var forged_route_path := valid_snapshot.duplicate(true)
	forged_route_path["routes"]["shape_route"]["path_tile_ids"] = _horizontal_path(7, 1, 3)
	var forged_route_path_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(forged_route_path)
	_check(
		not bool(forged_route_path_result.get("valid", true))
		and _issues_have(forged_route_path_result, "route_path_canonical_mismatch"),
		"persisted route path must equal a fresh topology-derived quote"
	)
	var forged_route_errors := valid_snapshot.duplicate(true)
	forged_route_errors["routes"]["shape_route"]["path_tile_ids"] = []
	forged_route_errors["routes"]["shape_route"]["validation_errors"] = ["forged_error"]
	forged_route_errors["routes"]["shape_route"]["status"] = "suspended"
	var forged_route_errors_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(forged_route_errors)
	_check(
		not bool(forged_route_errors_result.get("valid", true))
		and _issues_have(forged_route_errors_result, "route_validation_errors_canonical_mismatch"),
		"persisted route errors must equal topology-derived validation errors"
	)
	var forged_route_loop := valid_snapshot.duplicate(true)
	forged_route_loop["routes"]["shape_route"]["loop_seconds"] = 999.0
	var forged_route_loop_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(forged_route_loop)
	_check(
		not bool(forged_route_loop_result.get("valid", true))
		and _issues_have(forged_route_loop_result, "route_loop_seconds_canonical_mismatch"),
		"persisted route loop duration must equal its canonical mode specification"
	)

	var coherent_suspended_route := valid_snapshot.duplicate(true)
	coherent_suspended_route["routes"]["shape_route"]["stop_ids"] = ["shape_stop_a", "removed_stop"]
	coherent_suspended_route["routes"]["shape_route"]["station_tile_ids"] = [_tile(2, 8)]
	coherent_suspended_route["routes"]["shape_route"]["path_tile_ids"] = []
	coherent_suspended_route["routes"]["shape_route"]["validation_errors"] = ["station_not_found:removed_stop"]
	coherent_suspended_route["routes"]["shape_route"]["status"] = "suspended"
	var coherent_suspended_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(coherent_suspended_route)
	_check(bool(coherent_suspended_result.get("valid", false)), "coherent suspended route may retain a removed stop as historical intent: %s" % [coherent_suspended_result.get("issues", [])])


func _validate_active_project_round_trips_and_reserved_ids() -> void:
	var ordered_ids_network = TransportNetworkSystemScript.new()
	var ordered_ids_plan: Dictionary = ordered_ids_network.plan_project("build", {
		"segments": [
			{"kind": "road", "tile_path": [_tile(0, 5)]},
			{"id": "transport_segment_000001", "kind": "road", "tile_path": [_tile(2, 5)]},
		],
	}, terrain)
	_check(bool(ordered_ids_plan.get("ok", false)), "auto ID before an explicit reserved ID must plan")
	var ordered_segment_ids: Array[String] = []
	for segment: Dictionary in ordered_ids_plan.get("project", {}).get("plan", {}).get("segments", []):
		ordered_segment_ids.append(str(segment.get("id", "")))
	_check(ordered_segment_ids.has("transport_segment_000001") and ordered_segment_ids.has("transport_segment_000002"), "explicit IDs must be reserved before order-independent auto assignment")
	_check(ordered_ids_network.next_segment_sequence == 3, "order-independent segment ID assignment must leave the next sequence ahead")
	var ordered_ids_validation: Dictionary = TransportNetworkSystemScript.validate_snapshot(ordered_ids_network.to_dict())
	_check(bool(ordered_ids_validation.get("valid", false)), "mixed explicit/auto active IDs must produce a valid snapshot: %s" % [ordered_ids_validation.get("issues", [])])

	var network = TransportNetworkSystemScript.new()
	var duplicate_api_id: Dictionary = network.quote_project("build", {
		"segments": [{"id": "duplicate_api_id", "kind": "road", "tile_path": [_tile(0, 0)]}],
		"facilities": [{"id": "duplicate_api_id", "kind": "bus_depot", "tile_id": _tile(1, 0)}],
	}, terrain)
	_check(not bool(duplicate_api_id.get("ok", true)) and _issues_have(duplicate_api_id, "duplicate_transport_item_id"), "public planning API must reject duplicate explicit IDs inside one project")
	var reserved_plan := {
		"segments": [{
			"id": "transport_segment_000999", "kind": "road",
			"tile_path": _horizontal_path(1, 1, 4),
		}],
		"facilities": [{
			"id": "transport_facility_000888", "kind": "bus_depot", "tile_id": _tile(1, 2),
		}],
		"stations": [
			{"id": "transport_station_000777", "building_name": "公車站", "tile_id": _tile(2, 2)},
			{"id": "reserved_stop_b", "building_name": "公車站", "tile_id": _tile(4, 2)},
		],
	}
	var planned: Dictionary = network.plan_project("build", reserved_plan, terrain)
	_check(bool(planned.get("ok", false)), "explicit reserved-ID build project must plan")
	_check(network.next_segment_sequence == 1000, "explicit reserved segment ID must advance its generator")
	_check(network.next_facility_sequence == 889, "explicit reserved facility ID must advance its generator")
	_check(network.next_station_sequence == 778, "explicit reserved station ID must advance its generator")
	var project_id := str(planned.get("project", {}).get("id", ""))
	var planned_snapshot: Dictionary = network.to_dict()
	var planned_validation: Dictionary = TransportNetworkSystemScript.validate_snapshot(planned_snapshot)
	_check(bool(planned_validation.get("valid", false)), "legal planned build snapshot must validate: %s" % [planned_validation.get("issues", [])])
	var stale_active_sequence := planned_snapshot.duplicate(true)
	stale_active_sequence["next_segment_sequence"] = 999
	var stale_active_result: Dictionary = TransportNetworkSystemScript.validate_snapshot(stale_active_sequence)
	_check(not bool(stale_active_result.get("valid", true)) and _issues_have(stale_active_result, "sequence_not_ahead:next_segment_sequence"), "active generated IDs must participate in next-sequence validation")
	var conflicting_id_quote: Dictionary = network.quote_project("build", {
		"segments": [{
			"id": "transport_segment_000999", "kind": "road", "tile_path": [_tile(0, 4)],
		}],
	}, terrain)
	_check(not bool(conflicting_id_quote.get("ok", true)) and _issues_have(conflicting_id_quote, "transport_item_id_reserved"), "public planning API must reject an ID reserved by an active project")
	_check(bool(network.start_project(project_id).get("ok", false)), "planned reserved-ID project must start")
	var active_snapshot: Dictionary = network.to_dict()
	var active_validation: Dictionary = TransportNetworkSystemScript.validate_snapshot(active_snapshot)
	_check(bool(active_validation.get("valid", false)), "legal under-construction build snapshot must validate: %s" % [active_validation.get("issues", [])])
	var active_encoded := JSON.stringify(active_snapshot)
	var active_decoded: Variant = JSON.parse_string(active_encoded)
	var active_json_validation: Dictionary = TransportNetworkSystemScript.validate_snapshot(active_decoded)
	_check(bool(active_json_validation.get("valid", false)), "active build snapshot must validate after a JSON round trip: %s" % [active_json_validation.get("issues", [])])
	_check(bool(network.complete_project(project_id).get("ok", false)), "reserved-ID project must complete")
	var live_id_conflict: Dictionary = network.quote_project("build", {
		"segments": [{
			"id": "transport_segment_000999", "kind": "road", "tile_path": [_tile(0, 4)],
		}],
	}, terrain)
	_check(not bool(live_id_conflict.get("ok", true)) and _issues_have(live_id_conflict, "transport_item_id_reserved"), "public planning API must reject an ID already owned by a live record")
	var route: Dictionary = network.create_route({
		"id": "route_000999", "mode": "bus",
		"stop_ids": ["transport_station_000777", "reserved_stop_b"],
		"fleet_size": 1, "headway_minutes": 8, "fare": 15, "enabled": true,
	})
	_check(_route_is_operational(route), "explicit reserved route ID fixture must be operational")
	_check(network.next_route_sequence == 1000, "explicit reserved route ID must advance its generator")
	var external_station: Dictionary = network.register_station(
		"transport_station_001234", "公車站", _tile(0, 9)
	)
	_check(bool(external_station.get("ok", false)), "explicit reserved external station ID must register")
	_check(network.next_station_sequence == 1235, "explicit reserved external station ID must advance its generator")
	var completed_validation: Dictionary = TransportNetworkSystemScript.validate_snapshot(network.to_dict())
	_check(bool(completed_validation.get("valid", false)), "API-produced reserved IDs must leave a valid snapshot: %s" % [completed_validation.get("issues", [])])


func _validate_multi_attachment_route_continuity() -> void:
	var network = TransportNetworkSystemScript.new()
	_check(_build_and_complete(network, {
		"segments": [
			{"id": "upper_disconnected_road", "kind": "road", "tile_path": _horizontal_path(1, 1, 3)},
			{"id": "lower_disconnected_road", "kind": "road", "tile_path": _horizontal_path(3, 1, 3)},
		],
		"stations": [
			{"id": "multi_stop_a", "building_name": "公車站", "tile_id": _tile(1, 0)},
			{"id": "multi_stop_middle", "building_name": "公車站", "tile_id": _tile(2, 2)},
			{"id": "multi_stop_c", "building_name": "公車站", "tile_id": _tile(3, 4)},
		],
	}), "multi-attachment route fixture must build")
	var created: Dictionary = network.create_route({
		"id": "multi_attachment_route", "mode": "bus",
		"stop_ids": ["multi_stop_a", "multi_stop_middle", "multi_stop_c"],
		"fleet_size": 1, "headway_minutes": 8, "fare": 15, "enabled": true,
	})
	_check(bool(created.get("ok", false)) and not bool(created.get("valid", true)), "one station must not splice disconnected guideway attachments")
	var route: Dictionary = created.get("route", {})
	_check(str(route.get("status", "")) == "suspended", "disconnected multi-attachment route must suspend")
	var published_path: Array = route.get("path_tile_ids", [])
	_check(published_path.is_empty() or _path_is_cardinal(published_path), "three-stop route generator must never publish a non-cardinal splice")
	var validation: Dictionary = TransportNetworkSystemScript.validate_snapshot(network.to_dict())
	_check(bool(validation.get("valid", false)), "suspended multi-attachment route snapshot must remain coherent: %s" % [validation.get("issues", [])])


func _validate_complete_networks_and_persistence() -> void:
	var network = TransportNetworkSystemScript.new()

	var bus_plan := {
		"title": "玩家公車路網",
		"segments": [{"id": "road_main", "kind": "road", "tile_path": _horizontal_path(1, 1, 5)}],
		"facilities": [{"id": "bus_depot_main", "kind": "bus_depot", "tile_id": _tile(1, 2)}],
		"stations": [
			{"id": "bus_stop_a", "building_name": "公車站", "tile_id": _tile(2, 2)},
			{"id": "bus_stop_b", "building_name": "公車站", "tile_id": _tile(4, 2)},
		],
	}
	var bus_quote: Dictionary = network.quote_project("build", bus_plan, terrain)
	_check(bool(bus_quote.get("ok", false)) and int(bus_quote.get("total_cost", 0)) == 9_400, "bus network quote must include road, depot, and both stops")
	_check(_build_and_complete(network, bus_plan), "bus transport project did not complete")
	var bus_route := network.create_route({
		"id": "bus_line_1", "name": "市區公車", "mode": "bus",
		"stop_ids": ["bus_stop_a", "bus_stop_b"], "fleet_size": 2,
		"headway_minutes": 8, "fare": 15, "enabled": true,
	})
	_check(_route_is_operational(bus_route), "complete bus road, stops, depot, and fleet must activate")

	var metro_plan := {
		"title": "玩家捷運路網",
		"segments": [{"id": "metro_main", "kind": "metro_track", "tile_path": _horizontal_path(3, 1, 5)}],
		"facilities": [{"id": "metro_depot_main", "kind": "metro_depot", "tile_id": _tile(1, 4)}],
		"stations": [
			{"id": "metro_station_a", "building_name": "捷運站", "tile_id": _tile(2, 4)},
			{"id": "metro_station_b", "building_name": "捷運站", "tile_id": _tile(4, 4)},
		],
	}
	var metro_quote: Dictionary = network.quote_project("build", metro_plan, terrain)
	_check(bool(metro_quote.get("ok", false)) and int(metro_quote.get("total_cost", 0)) == 23_400, "metro quote must include track, depot, and stations")
	_check(_build_and_complete(network, metro_plan), "metro transport project did not complete")
	var metro_route := network.create_route({
		"id": "metro_line_1", "name": "藍線", "mode": "metro",
		"stop_ids": ["metro_station_a", "metro_station_b"], "fleet_size": 2,
		"headway_minutes": 5, "fare": 30, "enabled": true,
	})
	_check(_route_is_operational(metro_route), "complete metro stations, tracks, depot, and fleet must activate")

	var train_plan := {
		"title": "玩家火車路網",
		"segments": [{"id": "rail_main", "kind": "rail_track", "tile_path": _horizontal_path(6, 1, 5)}],
		"facilities": [
			{"id": "rail_depot_main", "kind": "rail_depot", "tile_id": _tile(1, 7)},
			{"id": "rail_signal_main", "kind": "rail_signal", "tile_id": _tile(5, 7)},
		],
		"stations": [
			{"id": "train_station_a", "building_name": "火車站", "tile_id": _tile(2, 7)},
			{"id": "train_station_b", "building_name": "火車站", "tile_id": _tile(4, 7)},
		],
	}
	var train_quote: Dictionary = network.quote_project("build", train_plan, terrain)
	_check(bool(train_quote.get("ok", false)) and int(train_quote.get("total_cost", 0)) == 25_150, "train quote must include track, depot, signal, and stations")
	_check(_build_and_complete(network, train_plan), "train transport project did not complete")
	var train_route := network.create_route({
		"id": "train_line_1", "name": "城際線", "mode": "train",
		"stop_ids": ["train_station_a", "train_station_b"], "fleet_size": 1,
		"headway_minutes": 15, "fare": 60, "enabled": true,
	})
	_check(_route_is_operational(train_route), "complete heavy rail network must activate")

	var air_plan := {
		"title": "玩家機場路網",
		"segments": [
			{"id": "airport_road", "kind": "road", "tile_path": [_tile(7, 5)]},
			{"id": "airport_taxiway", "kind": "taxiway", "tile_path": [_tile(8, 6), _tile(8, 7), _tile(8, 8), _tile(7, 8), _tile(6, 8)]},
			{"id": "airport_runway", "kind": "runway", "tile_path": _horizontal_path(9, 4, 7)},
		],
		"stations": [{"id": "airport_terminal", "building_name": "機場", "tile_id": _tile(8, 5)}],
	}
	var air_quote: Dictionary = network.quote_project("build", air_plan, terrain)
	_check(bool(air_quote.get("ok", false)) and int(air_quote.get("total_cost", 0)) == 26_620, "airport quote must include road access, taxiway, runway, and terminal")
	_check(_build_and_complete(network, air_plan), "airport transport project did not complete")
	var air_route := network.create_route({
		"id": "air_line_1", "name": "區域航線", "mode": "air",
		"stop_ids": ["airport_terminal"], "fleet_size": 1,
		"headway_minutes": 30, "fare": 120, "enabled": true,
	})
	_check(_route_is_operational(air_route), "airport needs one terminal, a three-plus runway, taxiway, road access, and fleet")
	_check(network.active_lines().size() == 4, "all four complete transport modes must be operational")
	for line: Dictionary in network.active_lines():
		_check(not Array(line.get("path_tile_ids", [])).is_empty(), "operational route must publish its authoritative tile path")
		_check(not Array(line.get("station_tile_ids", [])).is_empty(), "operational route must publish station tile ids")
		_check(not str(line.get("vehicle_kind", "")).is_empty() and float(line.get("loop_seconds", 0.0)) > 0.0, "operational route must publish vehicle runtime semantics")
		_check(_path_is_cardinal(Array(line.get("path_tile_ids", []))), "vehicle runtime path must remain cardinally contiguous across tile boundaries")

	var crossing_plan := {
		"title": "道路跨越捷運軌道",
		"segments": [{"id": "crossing_road", "kind": "road", "tile_path": [_tile(5, 2), _tile(5, 3), _tile(5, 4)]}],
	}
	var crossing_quote: Dictionary = network.quote_project("build", crossing_plan, terrain)
	_check(bool(crossing_quote.get("ok", false)), "road-track crossing plan should be valid")
	_check(Array(crossing_quote.get("crossing_tile_ids", [])).has(_tile(5, 3)), "road and metro overlap must automatically quote a level crossing")
	_check(int(crossing_quote.get("total_cost", 0)) == 2_460, "level crossing build charge must be included exactly once")
	_check(_build_and_complete(network, crossing_plan), "crossing road project did not complete")
	var crossing_id := "level_crossing_%03d" % _tile(5, 3)
	_check(network.crossings.has(crossing_id), "completed overlap must create an authoritative crossing record")
	var crossing_visual: Dictionary = network.tile_visual_state(_tile(5, 3), terrain)
	_check(Array(crossing_visual.get("segments", [])).has("road") and Array(crossing_visual.get("segments", [])).has("metro_track"), "crossing tile must retain both infrastructure layers")
	_check(str(crossing_visual.get("crossing", "")) == "level_crossing", "crossing visual state must expose the crossing kind")
	_check(not Dictionary(crossing_visual.get("neighbours", {})).is_empty(), "completed network visual state must publish neighbour tile ids for cross-tile rendering")
	_check(str(crossing_visual.get("project_status", "")) == "completed", "completed infrastructure must retain project provenance")
	var all_mode_validation: Dictionary = TransportNetworkSystemScript.validate_snapshot(network.to_dict())
	_check(bool(all_mode_validation.get("valid", false)), "legal all-mode snapshot with a real crossing must validate: %s" % [all_mode_validation.get("issues", [])])

	var empty_city: Array[String] = []
	for _index in range(CityTerrainMapScript.CELL_COUNT):
		empty_city.append("")
	_check(not network.has_private_road_traffic(empty_city, terrain), "roads without two built-building access points must not generate private traffic")
	var connected_city := empty_city.duplicate()
	connected_city[_tile(2, 2)] = "住宅"
	connected_city[_tile(4, 2)] = "商店"
	_check(network.has_private_road_traffic(connected_city, terrain), "connected road component with two building accesses may generate private traffic")
	var private_paths := network.private_road_paths(connected_city, terrain)
	_check(private_paths.size() >= 1 and int(private_paths[0].get("access_count", 0)) >= 2, "private road runtime must expose auditable building access points")
	_check(bool(private_paths[0].get("operational", false)) and _path_is_cardinal(Array(private_paths[0].get("path_tile_ids", []))), "private traffic must receive an operational cardinal road path instead of an unordered component")

	var blocker_ids := network.navigation_blocker_ids()
	_check(blocker_ids.has(_tile(5, 3)) and blocker_ids.has(_tile(8, 5)), "roads, tracks, facilities, and stations must feed navigation blockers")
	_check(network.monthly_maintenance() == 4_434, "monthly maintenance must include infrastructure, facilities, stations, crossing, and active fleets")
	_check(network.incremental_monthly_maintenance() == network.monthly_maintenance(), "project-built transport stations must remain in incremental maintenance")
	_check(is_equal_approx(network.service_operational_factor("bus"), 1.0) and is_equal_approx(network.service_operational_factor("metro"), 1.0), "valid enabled services must expose their operational factor")
	var metro_service_definition := {"base_uses": 24, "reasonable": 30, "reference_headway_minutes": 10}
	var baseline_metro_revenue := network.service_revenue("metro", 300, metro_service_definition)
	_check(baseline_metro_revenue > 0, "operational metro route must earn route-derived revenue")
	var baseline_metro_route: Dictionary = Dictionary(network.routes["metro_line_1"]).duplicate(true)
	var comparison_route := baseline_metro_route.duplicate(true)
	comparison_route["fare"] = 15
	network.routes["metro_line_1"] = comparison_route
	_check(network.service_revenue("metro", 300, metro_service_definition) < baseline_metro_revenue, "route fare must affect transport revenue")
	comparison_route = baseline_metro_route.duplicate(true)
	comparison_route["headway_minutes"] = 10
	network.routes["metro_line_1"] = comparison_route
	_check(network.service_revenue("metro", 300, metro_service_definition) < baseline_metro_revenue, "route headway must affect transport revenue")
	comparison_route = baseline_metro_route.duplicate(true)
	comparison_route["fleet_size"] = 1
	network.routes["metro_line_1"] = comparison_route
	_check(network.service_revenue("metro", 300, metro_service_definition) < baseline_metro_revenue, "route fleet size must affect transport revenue")
	network.routes["metro_line_1"] = baseline_metro_route
	var maintenance_before_external := network.monthly_maintenance()
	_check(bool(network.register_station("unserved_external_metro", "捷運站", _tile(0, 0)).get("ok", false)), "external unserved metro station fixture must register")
	_check(network.monthly_maintenance() == maintenance_before_external + int(TransportModesScript.station_spec("捷運站").get("monthly_maintenance", 0)), "complete maintenance ledger must retain external station maintenance")
	_check(network.incremental_monthly_maintenance() == maintenance_before_external, "incremental maintenance must remove station upkeep already charged by the city building ledger")
	_check(network.service_revenue("metro", 300, metro_service_definition) == baseline_metro_revenue, "station outside every operational route must earn no transport revenue")

	var runtime := network.visual_runtime_snapshot(connected_city, terrain)
	_check(Array(runtime.get("operational_lines", [])).size() == 4, "runtime snapshot must contain only the four operational lines")
	var access_edges: Array = runtime.get("station_access_edges", [])
	_check(not access_edges.is_empty(), "completed station guideway access must be derived for rendering")
	var bus_stations_with_access: Dictionary = {}
	for edge_variant: Variant in access_edges:
		var edge: Dictionary = edge_variant
		if str(edge.get("station_id", "")).begins_with("bus_stop_"):
			bus_stations_with_access[str(edge.get("station_id", ""))] = true
			_check(str(edge.get("kind", "")) == "road", "bus station access edge must terminate on a completed road")
	_check(bus_stations_with_access.has("bus_stop_a") and bus_stations_with_access.has("bus_stop_b"), "each completed bus station must expose at least one same-cell or cardinal road access edge")
	_check(Dictionary(runtime.get("tile_states", {})).has(str(_tile(5, 3))), "runtime snapshot must expose crossing tile state")
	_check(Dictionary(runtime.get("crossings", {})).has(crossing_id), "runtime snapshot must expose authoritative crossing records")

	var removal_quote := network.quote_project("demolish", {"segment_ids": ["metro_main"]}, terrain)
	_check(bool(removal_quote.get("ok", false)) and int(removal_quote.get("total_cost", 0)) == 1_150, "track demolition must have a deterministic per-tile quote")
	var removal_started := network.start_project("demolish", {"segment_ids": ["metro_main"]}, terrain)
	_check(bool(removal_started.get("ok", false)), "metro track demolition failed to start")
	var removal_project_id := str(removal_started.get("project", {}).get("id", ""))
	_check(bool(network.complete_project(removal_project_id).get("ok", false)), "metro track demolition failed to complete")
	_check(str(network.routes.get("metro_line_1", {}).get("status", "")) == "suspended", "removing a required segment must immediately suspend its enabled route")
	_check(network.active_lines().size() == 3 and is_equal_approx(network.service_operational_factor("metro"), 0.0), "suspended metro must produce no active line, vehicle, or service factor")
	_check(network.service_revenue("metro", 300, metro_service_definition) == 0, "suspended metro route must earn zero revenue despite an unserved station")
	_check(not network.crossings.has(crossing_id), "orphan level crossing must disappear after its track is removed")

	var snapshot := network.to_dict()
	_check(not snapshot.has("station_access_edges"), "derived station access edges must never enter the persisted transport schema")
	var validation := TransportNetworkSystemScript.validate_snapshot(snapshot)
	_check(bool(validation.get("valid", false)), "authoritative transport snapshot must validate before persistence: %s" % [validation.get("issues", [])])
	var encoded := JSON.stringify(snapshot)
	var decoded: Variant = JSON.parse_string(encoded)
	_check(decoded is Dictionary, "transport snapshot must be JSON-safe")
	var decoded_validation: Dictionary = TransportNetworkSystemScript.validate_snapshot(decoded)
	_check(bool(decoded_validation.get("valid", false)), "JSON-decoded transport snapshot must validate before restore: %s" % [decoded_validation.get("issues", [])])
	var restored = TransportNetworkSystemScript.create_from_dict(decoded)
	var restored_snapshot: Dictionary = restored.to_dict()
	_check(restored_snapshot == snapshot, "transport network must survive a deterministic JSON round trip")
	_check(restored.station_access_edges(terrain) == network.station_access_edges(terrain), "station access edges must be recomputed deterministically after reload")
	_check(restored.active_lines().size() == 3 and str(restored.routes.get("metro_line_1", {}).get("status", "")) == "suspended", "route operational and suspension states must survive loading")
	_check(restored.navigation_blocker_ids() == network.navigation_blocker_ids(), "navigation blockers must survive loading")
	var deletion_copy = TransportNetworkSystemScript.create_from_dict(decoded)
	var deleted: Dictionary = deletion_copy.delete_route("train_line_1")
	_check(bool(deleted.get("ok", false)) and not deletion_copy.routes.has("train_line_1") and deletion_copy.active_lines().size() == 2, "deleting a route must withdraw its operational line without deleting shared infrastructure")
	_check(str(deletion_copy.delete_route("train_line_1").get("error", "")) == "route_not_found", "deleting a missing route must fail deterministically")


func _build_and_complete(network, plan: Dictionary) -> bool:
	var started: Dictionary = network.start_project("build", plan, terrain)
	if not bool(started.get("ok", false)):
		push_error("Transport test project failed to start: %s" % started)
		return false
	var project: Dictionary = started.get("project", {})
	if str(project.get("status", "")) != "under_construction":
		return false
	var completed: Dictionary = network.complete_project(str(project.get("id", "")))
	return bool(completed.get("ok", false)) and str(completed.get("project", {}).get("status", "")) == "completed"


func _route_is_operational(result: Dictionary) -> bool:
	return (
		bool(result.get("ok", false))
		and bool(result.get("valid", false))
		and str(result.get("route", {}).get("status", "")) == "operational"
	)


func _horizontal_path(row: int, first_column: int, last_column: int) -> Array[int]:
	var result: Array[int] = []
	for column in range(first_column, last_column + 1):
		result.append(_tile(column, row))
	return result


func _tile(column: int, row: int) -> int:
	return int(terrain.tile_id_for_coordinate(Vector2i(column, row)))


func _path_is_cardinal(path: Array) -> bool:
	for index in range(1, path.size()):
		var previous: Vector2i = terrain.coordinate_for_tile_id(int(path[index - 1]))
		var current: Vector2i = terrain.coordinate_for_tile_id(int(path[index]))
		if absi(current.x - previous.x) + absi(current.y - previous.y) != 1:
			return false
	return true


func _issues_have(result: Dictionary, prefix: String) -> bool:
	for issue_variant: Variant in result.get("issues", []):
		if str(issue_variant).begins_with(prefix):
			return true
	return false


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		return
	failed = true
	push_error("Transport network system test failed: %s" % label)
