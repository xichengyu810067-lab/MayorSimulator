class_name TransportActivityProfiles
extends RefCounted

const Buildings = preload("res://data/catalogs/buildings.gd")

# These profiles describe static ground semantics and vehicle compatibility.
# They never authorize a tile to spawn or move a vehicle by itself: operational
# routes and vehicle positions belong to the transport-network controller.
const PROFILES := {
	"停車場": {
		"id": "parking_lot",
		"subject_type": "building",
		"terrain_type": "parking_lot",
		"ground_features": ["parking_bays", "entry_lane"],
		"vehicles": ["car"],
		"obstacle_kinds": ["vehicle_lane"],
		"loop_seconds": 8.0,
		"requires_operational_network": true,
		"autonomous_tile_activity": false,
		"vehicle_spawn_policy": "network_controller_only",
	},
	"公車站": {
		"id": "bus_station",
		"subject_type": "building",
		"terrain_type": "bus_lane",
		"ground_features": ["road_lane", "bus_bay", "curb"],
		"vehicles": ["bus"],
		"obstacle_kinds": ["road"],
		"loop_seconds": 9.0,
		"requires_operational_network": true,
		"autonomous_tile_activity": false,
		"vehicle_spawn_policy": "network_controller_only",
	},
	"捷運站": {
		"id": "metro_station",
		"subject_type": "building",
		"terrain_type": "rail_track",
		"ground_features": ["dual_rail", "sleepers", "platform_edge"],
		"vehicles": ["train"],
		"obstacle_kinds": ["rail"],
		"loop_seconds": 7.2,
		"requires_operational_network": true,
		"autonomous_tile_activity": false,
		"vehicle_spawn_policy": "network_controller_only",
	},
	"火車站": {
		"id": "train_station",
		"subject_type": "building",
		"terrain_type": "rail_track",
		"ground_features": ["dual_rail", "sleepers", "platform_edge"],
		"vehicles": ["train"],
		"obstacle_kinds": ["rail"],
		"loop_seconds": 8.4,
		"requires_operational_network": true,
		"autonomous_tile_activity": false,
		"vehicle_spawn_policy": "network_controller_only",
	},
	"機場": {
		"id": "airport",
		"subject_type": "building",
		"terrain_type": "runway",
		"ground_features": ["runway", "runway_centerline", "runway_lights"],
		"vehicles": ["plane"],
		"obstacle_kinds": ["runway"],
		"loop_seconds": 11.0,
		"requires_operational_network": true,
		"autonomous_tile_activity": false,
		"vehicle_spawn_policy": "network_controller_only",
	},
	"加油站": {
		"id": "gas_station",
		"subject_type": "building",
		"terrain_type": "service_lane",
		"ground_features": ["road_lane", "fuel_bay"],
		"vehicles": ["car", "motorcycle"],
		"obstacle_kinds": ["road", "vehicle_lane"],
		"loop_seconds": 8.8,
		"requires_operational_network": true,
		"autonomous_tile_activity": false,
		"vehicle_spawn_policy": "network_controller_only",
	},
	"road_path": {
		"id": "road_path",
		"subject_type": "terrain",
		"terrain_type": "road_path",
		"ground_features": ["road_lane", "lane_centerline", "road_edge"],
		"vehicles": ["car", "motorcycle"],
		"obstacle_kinds": ["road"],
		"loop_seconds": 6.6,
		"requires_operational_network": true,
		"autonomous_tile_activity": false,
		"vehicle_spawn_policy": "network_controller_only",
	},
	"rail_track": {
		"id": "rail_track",
		"subject_type": "terrain",
		"terrain_type": "rail_track",
		"ground_features": ["dual_rail", "sleepers"],
		"vehicles": ["train"],
		"obstacle_kinds": ["rail"],
		"loop_seconds": 7.2,
		"requires_operational_network": true,
		"autonomous_tile_activity": false,
		"vehicle_spawn_policy": "network_controller_only",
	},
}

const TERRAIN_ALIASES := {
	"road": "road_path",
	"road_path": "road_path",
	"highway": "road_path",
	"rail": "rail_track",
	"rail_track": "rail_track",
	"track": "rail_track",
}

const REQUIRED_SEMANTICS := {
	"停車場": {"ground_features": ["parking_bays"], "vehicles": ["car"]},
	"公車站": {"ground_features": ["road_lane", "bus_bay"], "vehicles": ["bus"]},
	"捷運站": {"ground_features": ["dual_rail"], "vehicles": ["train"]},
	"火車站": {"ground_features": ["dual_rail", "platform_edge"], "vehicles": ["train"]},
	"機場": {"ground_features": ["runway"], "vehicles": ["plane"]},
	"加油站": {"ground_features": ["fuel_bay"], "vehicles": ["car", "motorcycle"]},
	"road_path": {"ground_features": ["road_lane"], "vehicles": ["car", "motorcycle"]},
	"rail_track": {"ground_features": ["dual_rail"], "vehicles": ["train"]},
}


static func profile_for(subject: String) -> Dictionary:
	var resolved_subject := str(TERRAIN_ALIASES.get(subject, subject))
	return Dictionary(PROFILES.get(resolved_subject, {})).duplicate(true)


static func profile_for_building(building_name: String) -> Dictionary:
	var profile := profile_for(building_name)
	return profile if str(profile.get("subject_type", "")) == "building" else {}


static func profile_for_terrain(terrain_type: String) -> Dictionary:
	var profile := profile_for(terrain_type)
	return profile if str(profile.get("subject_type", "")) == "terrain" else {}


static func transport_building_names() -> PackedStringArray:
	var result := PackedStringArray()
	var definitions: Dictionary = Buildings.all()
	for building_name_variant: Variant in definitions.keys():
		var building_name := str(building_name_variant)
		var definition: Dictionary = definitions[building_name_variant]
		if str(definition.get("category", "")) == "交通類":
			result.append(building_name)
	result.sort()
	return result


static func transport_terrain_names() -> PackedStringArray:
	var result := PackedStringArray()
	for subject_variant: Variant in PROFILES.keys():
		var subject := str(subject_variant)
		var profile: Dictionary = PROFILES[subject_variant]
		if str(profile.get("subject_type", "")) == "terrain":
			result.append(subject)
	result.sort()
	return result


static func validation_snapshot() -> Dictionary:
	var expected_buildings := transport_building_names()
	var missing_buildings := PackedStringArray()
	var orphan_buildings := PackedStringArray()
	var missing_virtual_profiles := PackedStringArray()
	var semantic_issues := PackedStringArray()
	var expected_terrain_profiles := transport_terrain_names()

	for building_name: String in expected_buildings:
		var profile := profile_for_building(building_name)
		if profile.is_empty():
			missing_buildings.append(building_name)
			continue
		_validate_profile_semantics(building_name, profile, semantic_issues)

	for subject_variant: Variant in PROFILES.keys():
		var subject := str(subject_variant)
		var profile: Dictionary = PROFILES[subject_variant]
		if str(profile.get("subject_type", "")) == "building" and not expected_buildings.has(subject):
			orphan_buildings.append(subject)

	for virtual_subject: String in expected_terrain_profiles:
		var profile := profile_for_terrain(virtual_subject)
		if profile.is_empty():
			missing_virtual_profiles.append(virtual_subject)
		else:
			_validate_profile_semantics(virtual_subject, profile, semantic_issues)

	return {
		"valid": (
			missing_buildings.is_empty()
			and orphan_buildings.is_empty()
			and missing_virtual_profiles.is_empty()
			and semantic_issues.is_empty()
		),
		"expected_transport_buildings": expected_buildings,
		"missing_transport_buildings": missing_buildings,
		"orphan_transport_buildings": orphan_buildings,
		"missing_virtual_profiles": missing_virtual_profiles,
		"expected_terrain_profiles": expected_terrain_profiles,
		"semantic_issues": semantic_issues,
		"profile_count": PROFILES.size(),
		"expected_profile_count": expected_buildings.size() + expected_terrain_profiles.size(),
	}


static func _validate_profile_semantics(
	subject: String,
	profile: Dictionary,
	issues: PackedStringArray
) -> void:
	for required_key: String in ["id", "subject_type", "terrain_type", "ground_features", "vehicles", "obstacle_kinds", "loop_seconds", "requires_operational_network", "autonomous_tile_activity", "vehicle_spawn_policy"]:
		if not profile.has(required_key):
			issues.append("%s:missing:%s" % [subject, required_key])
	if float(profile.get("loop_seconds", 0.0)) <= 0.0:
		issues.append("%s:invalid:loop_seconds" % subject)
	if not bool(profile.get("requires_operational_network", false)):
		issues.append("%s:invalid:requires_operational_network" % subject)
	if bool(profile.get("autonomous_tile_activity", true)):
		issues.append("%s:invalid:autonomous_tile_activity" % subject)
	if str(profile.get("vehicle_spawn_policy", "")) != "network_controller_only":
		issues.append("%s:invalid:vehicle_spawn_policy" % subject)
	var semantic_requirements: Dictionary = REQUIRED_SEMANTICS.get(subject, {})
	for required_ground_variant: Variant in semantic_requirements.get("ground_features", []):
		var required_ground := str(required_ground_variant)
		if required_ground not in Array(profile.get("ground_features", [])):
			issues.append("%s:missing_ground:%s" % [subject, required_ground])
	for required_vehicle_variant: Variant in semantic_requirements.get("vehicles", []):
		var required_vehicle := str(required_vehicle_variant)
		if required_vehicle not in Array(profile.get("vehicles", [])):
			issues.append("%s:missing_vehicle:%s" % [subject, required_vehicle])
