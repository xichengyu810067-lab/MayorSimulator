extends SceneTree

const Buildings = preload("res://data/catalogs/buildings.gd")
const TransportActivityProfiles = preload("res://data/catalogs/transport_activity_profiles.gd")

const EXPECTED_SEMANTICS := {
	"停車場": {
		"profile_id": "parking_lot",
		"ground_features": ["parking_bays", "entry_lane"],
		"vehicles": ["car"],
		"obstacle_kinds": ["vehicle_lane"],
	},
	"公車站": {
		"profile_id": "bus_station",
		"ground_features": ["road_lane", "bus_bay", "curb"],
		"vehicles": ["bus"],
		"obstacle_kinds": ["road"],
	},
	"捷運站": {
		"profile_id": "metro_station",
		"ground_features": ["dual_rail", "sleepers", "platform_edge"],
		"vehicles": ["train"],
		"obstacle_kinds": ["rail"],
	},
	"火車站": {
		"profile_id": "train_station",
		"ground_features": ["dual_rail", "sleepers", "platform_edge"],
		"vehicles": ["train"],
		"obstacle_kinds": ["rail"],
	},
	"機場": {
		"profile_id": "airport",
		"ground_features": ["runway", "runway_centerline", "runway_lights"],
		"vehicles": ["plane"],
		"obstacle_kinds": ["runway"],
	},
	"加油站": {
		"profile_id": "gas_station",
		"ground_features": ["road_lane", "fuel_bay"],
		"vehicles": ["car", "motorcycle"],
		"obstacle_kinds": ["road", "vehicle_lane"],
	},
	"road_path": {
		"profile_id": "road_path",
		"ground_features": ["road_lane", "lane_centerline", "road_edge"],
		"vehicles": ["car", "motorcycle"],
		"obstacle_kinds": ["road"],
	},
	"rail_track": {
		"profile_id": "rail_track",
		"ground_features": ["dual_rail", "sleepers"],
		"vehicles": ["train"],
		"obstacle_kinds": ["rail"],
	},
}

var _failed := false
var _checks := 0
var _city_tile_button_script: Script


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_city_tile_button_script = load("res://scripts/world/city_tile_button.gd") as Script
	_check(_city_tile_button_script != null, "city tile renderer could not be loaded")
	if _city_tile_button_script == null:
		quit(1)
		return
	_validate_catalog_coverage()
	var transport_buildings := TransportActivityProfiles.transport_building_names()
	var transport_terrain := TransportActivityProfiles.transport_terrain_names()
	var live_subjects := PackedStringArray()
	live_subjects.append_array(transport_buildings)
	live_subjects.append_array(transport_terrain)
	_check(EXPECTED_SEMANTICS.size() == live_subjects.size(), "semantic fixture must cover every live transport subject")
	for subject: String in live_subjects:
		_check(EXPECTED_SEMANTICS.has(subject), "live transport subject has no semantic fixture: %s" % subject)
		if not EXPECTED_SEMANTICS.has(subject):
			continue
		_validate_profile_semantics(subject, EXPECTED_SEMANTICS[subject])
		_validate_isolated_tile_contract(subject)

	if _failed:
		quit(1)
	else:
		print("Transport visual animation test passed. Profiles=%d Buildings=%d Terrain=%d AutonomousVehicles=0 Checks=%d" % [
			live_subjects.size(),
			transport_buildings.size(),
			transport_terrain.size(),
			_checks,
		])
		quit(0)


func _validate_catalog_coverage() -> void:
	var snapshot := TransportActivityProfiles.validation_snapshot()
	_check(bool(snapshot.get("valid", false)), "transport activity catalog validation failed: %s" % snapshot)
	var expected_buildings: Array = Array(snapshot.get("expected_transport_buildings", []))
	var expected_terrain: Array = Array(snapshot.get("expected_terrain_profiles", []))
	_check(int(snapshot.get("profile_count", 0)) == int(snapshot.get("expected_profile_count", -1)), "profile count must be derived from live building and terrain registries")
	_check(int(snapshot.get("profile_count", 0)) == expected_buildings.size() + expected_terrain.size(), "profile count does not match live subjects")
	_check(Buildings.all().has("火車站"), "new heavy-rail station is absent from the building catalog")
	for building_name: String in expected_buildings:
		_check(Buildings.all().has(building_name), "missing transport building definition: %s" % building_name)
		_check(expected_buildings.has(building_name), "transport profile validation omitted live building: %s" % building_name)
	for expected_subject_variant: Variant in EXPECTED_SEMANTICS.keys():
		var expected_subject := str(expected_subject_variant)
		_check(expected_buildings.has(expected_subject) or expected_terrain.has(expected_subject), "orphan semantic fixture: %s" % expected_subject)


func _validate_profile_semantics(subject: String, expected: Dictionary) -> void:
	var profile := (
		TransportActivityProfiles.profile_for_terrain(subject)
		if TransportActivityProfiles.transport_terrain_names().has(subject)
		else TransportActivityProfiles.profile_for_building(subject)
	)
	_check(not profile.is_empty(), "missing transport activity profile: %s" % subject)
	_check(str(profile.get("id", "")) == str(expected.get("profile_id", "")), "unexpected profile id for %s: %s" % [subject, profile])
	_check(float(profile.get("loop_seconds", 0.0)) > 0.0, "network visualization timing hint must be positive: %s" % subject)
	_check(bool(profile.get("requires_operational_network", false)), "transport profile does not require an operational network: %s" % subject)
	_check(not bool(profile.get("autonomous_tile_activity", true)), "transport profile still permits autonomous tile activity: %s" % subject)
	_check(str(profile.get("vehicle_spawn_policy", "")) == "network_controller_only", "vehicle spawn ownership is not assigned to the network controller: %s" % subject)
	for key: String in ["ground_features", "vehicles", "obstacle_kinds"]:
		var actual_values: Array = Array(profile.get(key, []))
		for required_variant: Variant in expected.get(key, []):
			var required_value := str(required_variant)
			_check(actual_values.has(required_value), "%s profile lacks %s semantic '%s': %s" % [subject, key, required_value, actual_values])


func _validate_isolated_tile_contract(subject: String) -> void:
	var is_terrain := TransportActivityProfiles.transport_terrain_names().has(subject)
	var tile = _city_tile_button_script.new()
	tile.size = Vector2(128, 128)
	root.add_child(tile)
	tile.set_tile({
		"index": 17,
		"building_name": "" if is_terrain else subject,
		"building_color": Color(0.52, 0.68, 0.82),
		"terrain_type": subject if is_terrain else "flat_ground",
		"visual": {},
		"construction": {},
	})
	var expected: Dictionary = EXPECTED_SEMANTICS[subject]
	var profile: Dictionary = tile.get_transport_activity_profile()
	_check(str(profile.get("id", "")) == str(expected.get("profile_id", "")), "city tile did not resolve the correct profile for %s: %s" % [subject, profile])

	var contract: Dictionary = tile.get_visual_animation_contract()
	_check(bool(contract.get("base_portrait_preserved", false)), "transport overlay may replace the canonical building portrait")
	_check(bool(contract.get("ground_before_portrait", false)), "transport ground semantics are not layered below the portrait")
	_check(bool(contract.get("terrain_type_supported", false)), "road/rail terrain profiles are not supported by the tile contract")
	_check(not bool(contract.get("vehicles_after_portrait", false)), "city tile still claims ownership of a local vehicle layer")
	_check(not bool(contract.get("autonomous_transport_vehicle_animation", true)), "city tile still permits autonomous transport-vehicle animation")
	_check(str(contract.get("network_vehicle_layer_owner", "")) == "transport_network_controller", "transport vehicle layer is not owned by the network controller")

	tile.debug_set_animation_time(0.25)
	var before: Dictionary = tile.get_visual_animation_debug_snapshot()
	tile.debug_advance_animation(0.73)
	var after: Dictionary = tile.get_visual_animation_debug_snapshot()
	_check(not bool(before.get("transport_vehicle_animation_active", true)), "isolated transport subject autonomously activated a vehicle: %s" % subject)
	_check(not bool(after.get("transport_vehicle_animation_active", true)), "isolated transport subject activated a vehicle after local time advanced: %s" % subject)
	_check(is_equal_approx(float(after.get("activity_phase", 0.0)), float(before.get("activity_phase", 0.0))), "isolated transport subject advanced a tile-local vehicle phase: %s" % subject)

	tile.free()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Transport visual animation contract failed: %s" % message)
