class_name SaveSchemaAuthority
extends RefCounted

## Single runtime authority for persisted schema writers and supported ceilings.
## The JSON registry mirrors these constants for review and fixture discovery;
## runtime load/save code never depends on reading that file.

const REGISTRY_SCHEMA_VERSION := 1
const FUTURE_VERSION_POLICY := "explicit_reject_no_overwrite"

const SAVE_ENVELOPE_CURRENT_SCHEMA_VERSION := 1
const SAVE_ENVELOPE_MIN_SUPPORTED_SCHEMA_VERSION := 1
const SAVE_ENVELOPE_MAX_SUPPORTED_SCHEMA_VERSION := 1

const CITY_STATE_CURRENT_SCHEMA_VERSION := 2
const CITY_STATE_MIN_SUPPORTED_SCHEMA_VERSION := 1
const CITY_STATE_MAX_SUPPORTED_SCHEMA_VERSION := 2

const CURRENT_VERTICAL_SCHEMA_VERSION := 11
const MIN_SUPPORTED_VERTICAL_SLICE_METADATA_SCHEMA := 4
const MAX_SUPPORTED_VERTICAL_SLICE_METADATA_SCHEMA := 11
const SUPPORTED_VERTICAL_SLICE_METADATA_SCHEMAS := [4, 5, 6, 7, 8, 9, 10, 11]
const UNSUPPORTED_HISTORICAL_VERTICAL_SCHEMAS := [0, 1, 2, 3]
const LEGACY_MIGRATION_VERTICAL_SCHEMA_VERSION := 7
const FOOTPRINT_MIGRATION_VERTICAL_SCHEMA_VERSION := 8
const TRANSPORT_SESSION_MIGRATION_VERTICAL_SCHEMA_VERSION := 9
const TRANSPORT_REUSE_MIGRATION_VERTICAL_SCHEMA_VERSION := 10

const CURRENT_TERRAIN_LAYOUT_VERSION := 3
const MAX_SUPPORTED_TERRAIN_LAYOUT_VERSION := 3
const LEGACY_MIGRATION_TERRAIN_LAYOUT_VERSION := 2

const POPULATION_CURRENT_SCHEMA_VERSION := 2
const POPULATION_MIN_SUPPORTED_SCHEMA_VERSION := 1
const POPULATION_MAX_SUPPORTED_SCHEMA_VERSION := 2

const NPC_RECORD_CURRENT_SCHEMA_VERSION := 2
const NPC_RECORD_MIN_SUPPORTED_SCHEMA_VERSION := 1
const NPC_RECORD_MAX_SUPPORTED_SCHEMA_VERSION := 2

const TRANSPORT_NETWORK_CURRENT_SCHEMA_VERSION := 2
const TRANSPORT_NETWORK_MIN_SUPPORTED_SCHEMA_VERSION := 1
const TRANSPORT_NETWORK_MAX_SUPPORTED_SCHEMA_VERSION := 2

const TRANSPORT_PLANNING_SESSION_CURRENT_SCHEMA_VERSION := 2
const TRANSPORT_PLANNING_SESSION_MIN_SUPPORTED_SCHEMA_VERSION := 1
const TRANSPORT_PLANNING_SESSION_MAX_SUPPORTED_SCHEMA_VERSION := 2

const _VERSION_KEYS := [
	"save_envelope_schema_version",
	"city_state_schema_version",
	"vertical_slice_schema_version",
	"terrain_layout_version",
	"population_schema_version",
	"npc_record_schema_version",
	"transport_network_schema_version",
	"transport_planning_session_schema_version",
]

const _EXPECTED_COMPONENT_MATRIX := {
	"save_envelope": {
		"current_version": SAVE_ENVELOPE_CURRENT_SCHEMA_VERSION,
		"max_supported_version": SAVE_ENVELOPE_MAX_SUPPORTED_SCHEMA_VERSION,
		"supported_read_versions": [1],
		"compatibility": "exact",
	},
	"city_state": {
		"current_version": CITY_STATE_CURRENT_SCHEMA_VERSION,
		"max_supported_version": CITY_STATE_MAX_SUPPORTED_SCHEMA_VERSION,
		"supported_read_versions": [1, 2],
		"compatibility": "migration_1_current_2_canonical_population_only",
	},
	"vertical_slice": {
		"current_version": CURRENT_VERTICAL_SCHEMA_VERSION,
		"max_supported_version": MAX_SUPPORTED_VERTICAL_SLICE_METADATA_SCHEMA,
		"supported_read_versions": SUPPORTED_VERTICAL_SLICE_METADATA_SCHEMAS,
		"compatibility": "unsupported_0_to_3_direct_read_then_write_11_for_4_to_6_migration_7_2_8_3_9_3_and_10_3_current_11_3",
	},
	"terrain_layout": {
		"current_version": CURRENT_TERRAIN_LAYOUT_VERSION,
		"max_supported_version": MAX_SUPPORTED_TERRAIN_LAYOUT_VERSION,
		"supported_read_versions": [2, 3],
		"compatibility": "migration_pair_2_current_3",
	},
	"population": {
		"current_version": POPULATION_CURRENT_SCHEMA_VERSION,
		"max_supported_version": POPULATION_MAX_SUPPORTED_SCHEMA_VERSION,
		"supported_read_versions": [1, 2],
		"compatibility": "direct_read_1_to_2",
	},
	"npc_record": {
		"current_version": NPC_RECORD_CURRENT_SCHEMA_VERSION,
		"max_supported_version": NPC_RECORD_MAX_SUPPORTED_SCHEMA_VERSION,
		"supported_read_versions": [1, 2],
		"compatibility": "direct_read_1_to_2",
	},
	"transport_network": {
		"current_version": TRANSPORT_NETWORK_CURRENT_SCHEMA_VERSION,
		"max_supported_version": TRANSPORT_NETWORK_MAX_SUPPORTED_SCHEMA_VERSION,
		"supported_read_versions": [1, 2],
		"compatibility": "migration_1_current_2_preserve_legacy_quotes",
	},
	"transport_planning_session": {
		"current_version": TRANSPORT_PLANNING_SESSION_CURRENT_SCHEMA_VERSION,
		"max_supported_version": TRANSPORT_PLANNING_SESSION_MAX_SUPPORTED_SCHEMA_VERSION,
		"supported_read_versions": [1, 2],
		"compatibility": "migration_1_current_2_preserve_legacy_quotes",
	},
}

const _EXPECTED_FIXTURES := {
	"current_round_trip": {
		"path": "res://tests/fixtures/save_schema/current_round_trip.json",
		"behavior": "current_11_round_trip_population_building_footprints_and_transport_reuse_contracts",
	},
	"supported_legacy_migration": {
		"path": "res://tests/fixtures/save_schema/supported_legacy_migration.json",
		"behavior": "city_state_1_mirror_match_to_2_and_vertical_7_layout_2_to_11_layout_3_single_footprints_inactive_transport_session",
	},
	"future_reject": {
		"path": "res://tests/fixtures/save_schema/future_reject.json",
		"behavior": FUTURE_VERSION_POLICY,
	},
	"corrupt_minimal": {
		"path": "res://tests/fixtures/save_schema/corrupt_minimal.json",
		"behavior": FUTURE_VERSION_POLICY,
	},
	"oldest_supported_vertical_4": {
		"path": "res://tests/fixtures/save_schema/oldest_supported_vertical_4.json",
		"behavior": "oldest_supported_vertical_4_direct_read_then_write_11_single_footprints_inactive_transport_session",
	},
	"unsupported_vertical_3": {
		"path": "res://tests/fixtures/save_schema/unsupported_vertical_3.json",
		"behavior": FUTURE_VERSION_POLICY,
	},
	"route_package_v1_transport": {
		"path": "res://tests/fixtures/save_schema/route_package_v1_transport.json",
		"behavior": "vertical_10_transport_1_planning_1_to_11_2_2_preserve_v1_quote",
	},
}


static func current_writer_versions() -> Dictionary:
	return {
		"save_envelope_schema_version": SAVE_ENVELOPE_CURRENT_SCHEMA_VERSION,
		"city_state_schema_version": CITY_STATE_CURRENT_SCHEMA_VERSION,
		"vertical_slice_schema_version": CURRENT_VERTICAL_SCHEMA_VERSION,
		"terrain_layout_version": CURRENT_TERRAIN_LAYOUT_VERSION,
		"population_schema_version": POPULATION_CURRENT_SCHEMA_VERSION,
		"npc_record_schema_version": NPC_RECORD_CURRENT_SCHEMA_VERSION,
		"transport_network_schema_version": TRANSPORT_NETWORK_CURRENT_SCHEMA_VERSION,
		"transport_planning_session_schema_version": TRANSPORT_PLANNING_SESSION_CURRENT_SCHEMA_VERSION,
	}


static func version_ceiling() -> Dictionary:
	return {
		"save_envelope_schema_version": SAVE_ENVELOPE_MAX_SUPPORTED_SCHEMA_VERSION,
		"city_state_schema_version": CITY_STATE_MAX_SUPPORTED_SCHEMA_VERSION,
		"vertical_slice_schema_version": MAX_SUPPORTED_VERTICAL_SLICE_METADATA_SCHEMA,
		"terrain_layout_version": MAX_SUPPORTED_TERRAIN_LAYOUT_VERSION,
		"population_schema_version": POPULATION_MAX_SUPPORTED_SCHEMA_VERSION,
		"npc_record_schema_version": NPC_RECORD_MAX_SUPPORTED_SCHEMA_VERSION,
		"transport_network_schema_version": TRANSPORT_NETWORK_MAX_SUPPORTED_SCHEMA_VERSION,
		"transport_planning_session_schema_version": TRANSPORT_PLANNING_SESSION_MAX_SUPPORTED_SCHEMA_VERSION,
	}


static func validate_vertical_terrain_pair(vertical_schema_version: int, terrain_layout_version: int) -> bool:
	# Semantic validation accepts only the current pair. The legacy pair must pass
	# through the explicit migration boundary before this check.
	return (
		vertical_schema_version == CURRENT_VERTICAL_SCHEMA_VERSION
		and terrain_layout_version == CURRENT_TERRAIN_LAYOUT_VERSION
	)


static func is_legacy_migration_pair(vertical_schema_version: int, terrain_layout_version: int) -> bool:
	return (
		vertical_schema_version == LEGACY_MIGRATION_VERTICAL_SCHEMA_VERSION
		and terrain_layout_version == LEGACY_MIGRATION_TERRAIN_LAYOUT_VERSION
	)


static func is_footprint_migration_pair(vertical_schema_version: int, terrain_layout_version: int) -> bool:
	return (
		vertical_schema_version == FOOTPRINT_MIGRATION_VERTICAL_SCHEMA_VERSION
		and terrain_layout_version == CURRENT_TERRAIN_LAYOUT_VERSION
	)


static func is_transport_session_migration_pair(vertical_schema_version: int, terrain_layout_version: int) -> bool:
	return (
		vertical_schema_version == TRANSPORT_SESSION_MIGRATION_VERTICAL_SCHEMA_VERSION
		and terrain_layout_version == CURRENT_TERRAIN_LAYOUT_VERSION
	)


static func is_transport_reuse_migration_pair(vertical_schema_version: int, terrain_layout_version: int) -> bool:
	return (
		vertical_schema_version == TRANSPORT_REUSE_MIGRATION_VERTICAL_SCHEMA_VERSION
		and terrain_layout_version == CURRENT_TERRAIN_LAYOUT_VERSION
	)


static func is_supported_vertical_schema(vertical_schema_version: int) -> bool:
	return vertical_schema_version in SUPPORTED_VERTICAL_SLICE_METADATA_SCHEMAS


static func validate_registry_json(registry_json: String) -> bool:
	var parser := JSON.new()
	if parser.parse(registry_json) != OK or not parser.data is Dictionary:
		return false
	var registry: Dictionary = parser.data
	if not _has_exact_keys(registry, [
		"registry_schema_version",
		"authority_owner",
		"current_writer",
		"version_ceiling",
		"supported_version_matrix",
		"paired_support_matrix",
		"fixture_registry",
		"migration_registry",
		"future_version_policy",
	]):
		return false
	if not _is_integer_value(registry.get("registry_schema_version", null)):
		return false
	if int(registry["registry_schema_version"]) != REGISTRY_SCHEMA_VERSION:
		return false
	if str(registry.get("authority_owner", "")) != "scripts/core/save_schema_authority.gd":
		return false
	if str(registry.get("future_version_policy", "")) != FUTURE_VERSION_POLICY:
		return false
	if not _validate_current_writer(registry.get("current_writer", null)):
		return false
	if not _matches_versions(registry.get("version_ceiling", null), version_ceiling()):
		return false
	return (
		_validate_component_matrix(registry.get("supported_version_matrix", null))
		and _validate_paired_support_matrix(registry.get("paired_support_matrix", null))
		and _validate_fixture_registry(registry.get("fixture_registry", null))
		and _validate_migration_registry(registry.get("migration_registry", null))
	)


static func _validate_current_writer(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var writer: Dictionary = value
	var expected_keys := _VERSION_KEYS.duplicate()
	expected_keys.append_array(["id", "writer_allowed"])
	return (
		_has_exact_keys(writer, expected_keys)
		and str(writer.get("id", "")) == "game_session_save_boundary"
		and writer.get("writer_allowed", null) is bool
		and bool(writer["writer_allowed"])
		and _matches_versions(writer, current_writer_versions(), ["id", "writer_allowed"])
	)


static func _validate_component_matrix(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != _EXPECTED_COMPONENT_MATRIX.size():
		return false
	var seen: Dictionary = {}
	for item: Variant in value:
		if not item is Dictionary:
			return false
		var entry: Dictionary = item
		if not _has_exact_keys(entry, [
			"component", "current_version", "max_supported_version",
			"supported_read_versions", "compatibility",
		]):
			return false
		var component := str(entry.get("component", ""))
		if seen.has(component) or not _EXPECTED_COMPONENT_MATRIX.has(component):
			return false
		seen[component] = true
		var expected: Dictionary = _EXPECTED_COMPONENT_MATRIX[component]
		if (
			not _is_integer_value(entry.get("current_version", null))
			or not _is_integer_value(entry.get("max_supported_version", null))
			or int(entry["current_version"]) != int(expected["current_version"])
			or int(entry["max_supported_version"]) != int(expected["max_supported_version"])
			or not _integer_arrays_equal(entry.get("supported_read_versions", null), expected["supported_read_versions"])
			or str(entry.get("compatibility", "")) != str(expected["compatibility"])
		):
			return false
	return seen.size() == _EXPECTED_COMPONENT_MATRIX.size()


static func _validate_paired_support_matrix(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != 7:
		return false
	var expected := [
		{
			"vertical_slice_schema_versions": UNSUPPORTED_HISTORICAL_VERTICAL_SCHEMAS,
			"terrain_layout_version": null,
			"status": "explicit_unsupported_no_proven_format",
			"writer_allowed": false,
		},
		{
			"vertical_slice_schema_versions": [4, 5, 6],
			"terrain_layout_version": null,
			"status": "direct_read_then_write_current_single_footprints",
			"writer_allowed": false,
		},
		{
			"vertical_slice_schema_versions": [LEGACY_MIGRATION_VERTICAL_SCHEMA_VERSION],
			"terrain_layout_version": LEGACY_MIGRATION_TERRAIN_LAYOUT_VERSION,
			"status": "migration_input",
			"writer_allowed": false,
		},
		{
			"vertical_slice_schema_versions": [FOOTPRINT_MIGRATION_VERTICAL_SCHEMA_VERSION],
			"terrain_layout_version": CURRENT_TERRAIN_LAYOUT_VERSION,
			"status": "footprint_migration_input",
			"writer_allowed": false,
		},
		{
			"vertical_slice_schema_versions": [TRANSPORT_SESSION_MIGRATION_VERTICAL_SCHEMA_VERSION],
			"terrain_layout_version": CURRENT_TERRAIN_LAYOUT_VERSION,
			"status": "transport_session_migration_input",
			"writer_allowed": false,
		},
		{
			"vertical_slice_schema_versions": [TRANSPORT_REUSE_MIGRATION_VERTICAL_SCHEMA_VERSION],
			"terrain_layout_version": CURRENT_TERRAIN_LAYOUT_VERSION,
			"status": "transport_reuse_migration_input",
			"writer_allowed": false,
		},
		{
			"vertical_slice_schema_versions": [CURRENT_VERTICAL_SCHEMA_VERSION],
			"terrain_layout_version": CURRENT_TERRAIN_LAYOUT_VERSION,
			"status": "current",
			"writer_allowed": true,
		},
	]
	var writer_count := 0
	for index: int in range(expected.size()):
		var entry_value: Variant = (value as Array)[index]
		if not entry_value is Dictionary:
			return false
		var entry: Dictionary = entry_value
		if not _has_exact_keys(entry, [
			"vertical_slice_schema_versions", "terrain_layout_version", "status", "writer_allowed",
		]):
			return false
		var expected_entry: Dictionary = expected[index]
		if not _integer_arrays_equal(
			entry.get("vertical_slice_schema_versions", null),
			expected_entry["vertical_slice_schema_versions"]
		):
			return false
		var expected_terrain: Variant = expected_entry["terrain_layout_version"]
		var actual_terrain: Variant = entry.get("terrain_layout_version", "missing")
		if expected_terrain == null:
			if actual_terrain != null:
				return false
		elif not _is_integer_value(actual_terrain) or int(actual_terrain) != int(expected_terrain):
			return false
		if (
			str(entry.get("status", "")) != str(expected_entry["status"])
			or not entry.get("writer_allowed", null) is bool
			or bool(entry["writer_allowed"]) != bool(expected_entry["writer_allowed"])
		):
			return false
		if bool(entry["writer_allowed"]):
			writer_count += 1
	return writer_count == 1


static func _validate_fixture_registry(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != _EXPECTED_FIXTURES.size():
		return false
	var seen: Dictionary = {}
	for item: Variant in value:
		if not item is Dictionary:
			return false
		var entry: Dictionary = item
		if not _has_exact_keys(entry, ["id", "path", "behavior"]):
			return false
		var fixture_id := str(entry.get("id", ""))
		if seen.has(fixture_id) or not _EXPECTED_FIXTURES.has(fixture_id):
			return false
		seen[fixture_id] = true
		var expected: Dictionary = _EXPECTED_FIXTURES[fixture_id]
		if str(entry.get("path", "")) != str(expected["path"]):
			return false
		if str(entry.get("behavior", "")) != str(expected["behavior"]):
			return false
	return seen.size() == _EXPECTED_FIXTURES.size()


static func _validate_migration_registry(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != 5:
		return false
	var city_item: Variant = (value as Array)[0]
	var terrain_item: Variant = (value as Array)[1]
	var footprint_item: Variant = (value as Array)[2]
	var transport_session_item: Variant = (value as Array)[3]
	var transport_reuse_item: Variant = (value as Array)[4]
	if not city_item is Dictionary or not terrain_item is Dictionary or not footprint_item is Dictionary or not transport_session_item is Dictionary or not transport_reuse_item is Dictionary:
		return false
	var city_migration: Dictionary = city_item
	var migration: Dictionary = terrain_item
	var footprint_migration: Dictionary = footprint_item
	var transport_session_migration: Dictionary = transport_session_item
	var transport_reuse_migration: Dictionary = transport_reuse_item
	return (
		_has_exact_keys(city_migration, [
			"id", "source", "target", "precondition", "implementation", "test", "fixture", "status",
		])
		and str(city_migration.get("id", "")) == "city_state_1_npc_mirror_to_2"
		and _matches_city_state_version(city_migration.get("source", null), 1)
		and _matches_city_state_version(city_migration.get("target", null), CITY_STATE_CURRENT_SCHEMA_VERSION)
		and str(city_migration.get("precondition", "")) == "canonical_population_exactly_matches_mirror_or_both_empty;nonempty_core_only_reject"
		and _string_arrays_equal(city_migration.get("implementation", null), [
			"scripts/core/city_state.gd:migrate_dict",
		])
		and str(city_migration.get("test", "")) == "res://tests/unit/core/save_recovery_self_test.gd"
		and str(city_migration.get("fixture", "")) == "res://tests/fixtures/save_schema/supported_legacy_migration.json"
		and str(city_migration.get("status", "")) == "active"
		and
		_has_exact_keys(migration, [
			"id", "source", "target", "implementation", "test", "fixture", "status",
		])
		and str(migration.get("id", "")) == "vertical_7_layout_2_to_11_layout_3"
		and _matches_pair(
			migration.get("source", null),
			LEGACY_MIGRATION_VERTICAL_SCHEMA_VERSION,
			LEGACY_MIGRATION_TERRAIN_LAYOUT_VERSION
		)
		and _matches_pair(
			migration.get("target", null),
			CURRENT_VERTICAL_SCHEMA_VERSION,
			CURRENT_TERRAIN_LAYOUT_VERSION
		)
		and _string_arrays_equal(migration.get("implementation", null), [
			"scripts/core/game_session.gd:_migrate_state_snapshot_to_current_pair",
			"scripts/world/city_terrain_map.gd:migrate_snapshot_to_current",
			"data/catalogs/building_footprints.gd:legacy_single_fields",
		])
		and str(migration.get("test", "")) == "res://tests/unit/core/save_recovery_self_test.gd"
		and str(migration.get("fixture", "")) == "res://tests/fixtures/save_schema/supported_legacy_migration.json"
		and str(migration.get("status", "")) == "active"
		and
		_has_exact_keys(footprint_migration, [
			"id", "source", "target", "implementation", "test", "status",
		])
		and str(footprint_migration.get("id", "")) == "vertical_8_layout_3_to_11_layout_3"
		and _matches_pair(
			footprint_migration.get("source", null),
			FOOTPRINT_MIGRATION_VERTICAL_SCHEMA_VERSION,
			CURRENT_TERRAIN_LAYOUT_VERSION
		)
		and _matches_pair(
			footprint_migration.get("target", null),
			CURRENT_VERTICAL_SCHEMA_VERSION,
			CURRENT_TERRAIN_LAYOUT_VERSION
		)
		and _string_arrays_equal(footprint_migration.get("implementation", null), [
			"scripts/core/game_session.gd:_migrate_state_snapshot_to_current_pair",
			"data/catalogs/building_footprints.gd:legacy_single_fields",
		])
		and str(footprint_migration.get("test", "")) == "res://tests/unit/core/save_recovery_self_test.gd"
		and str(footprint_migration.get("status", "")) == "active"
		and
		_has_exact_keys(transport_session_migration, [
			"id", "source", "target", "implementation", "test", "status",
		])
		and str(transport_session_migration.get("id", "")) == "vertical_9_layout_3_to_11_layout_3"
		and _matches_pair(
			transport_session_migration.get("source", null),
			TRANSPORT_SESSION_MIGRATION_VERTICAL_SCHEMA_VERSION,
			CURRENT_TERRAIN_LAYOUT_VERSION
		)
		and _matches_pair(
			transport_session_migration.get("target", null),
			CURRENT_VERTICAL_SCHEMA_VERSION,
			CURRENT_TERRAIN_LAYOUT_VERSION
		)
		and _string_arrays_equal(transport_session_migration.get("implementation", null), [
			"scripts/core/game_session.gd:_migrate_state_snapshot_to_current_pair",
			"scripts/systems/city/transport_planning_session.gd:to_dict",
		])
		and str(transport_session_migration.get("test", "")) == "res://tests/unit/core/save_recovery_self_test.gd"
		and str(transport_session_migration.get("status", "")) == "active"
		and
		_has_exact_keys(transport_reuse_migration, [
			"id", "source", "target", "implementation", "test", "fixture", "status",
		])
		and str(transport_reuse_migration.get("id", "")) == "vertical_10_transport_1_planning_1_to_11_2_2"
		and _matches_transport_reuse_versions(
			transport_reuse_migration.get("source", null),
			TRANSPORT_REUSE_MIGRATION_VERTICAL_SCHEMA_VERSION,
			1,
			1
		)
		and _matches_transport_reuse_versions(
			transport_reuse_migration.get("target", null),
			CURRENT_VERTICAL_SCHEMA_VERSION,
			TRANSPORT_NETWORK_CURRENT_SCHEMA_VERSION,
			TRANSPORT_PLANNING_SESSION_CURRENT_SCHEMA_VERSION
		)
		and _string_arrays_equal(transport_reuse_migration.get("implementation", null), [
			"scripts/core/game_session.gd:_migrate_state_snapshot_to_current_pair",
			"scripts/systems/city/transport_network_system.gd:migrate_snapshot",
			"scripts/systems/city/transport_planning_session.gd:migrate_snapshot",
		])
		and str(transport_reuse_migration.get("test", "")) == "res://tests/unit/core/save_recovery_self_test.gd"
		and str(transport_reuse_migration.get("fixture", "")) == "res://tests/fixtures/save_schema/route_package_v1_transport.json"
		and str(transport_reuse_migration.get("status", "")) == "active"
	)


static func _matches_transport_reuse_versions(
	value: Variant,
	vertical_schema_version: int,
	transport_network_schema_version: int,
	transport_planning_session_schema_version: int
) -> bool:
	if not value is Dictionary:
		return false
	var versions: Dictionary = value
	return (
		_has_exact_keys(versions, [
			"vertical_slice_schema_version",
			"terrain_layout_version",
			"transport_network_schema_version",
			"transport_planning_session_schema_version",
		])
		and _is_integer_value(versions.get("vertical_slice_schema_version", null))
		and int(versions["vertical_slice_schema_version"]) == vertical_schema_version
		and _is_integer_value(versions.get("terrain_layout_version", null))
		and int(versions["terrain_layout_version"]) == CURRENT_TERRAIN_LAYOUT_VERSION
		and _is_integer_value(versions.get("transport_network_schema_version", null))
		and int(versions["transport_network_schema_version"]) == transport_network_schema_version
		and _is_integer_value(versions.get("transport_planning_session_schema_version", null))
		and int(versions["transport_planning_session_schema_version"]) == transport_planning_session_schema_version
	)


static func _matches_city_state_version(value: Variant, version: int) -> bool:
	if not value is Dictionary:
		return false
	var source: Dictionary = value
	return (
		_has_exact_keys(source, ["city_state_schema_version"])
		and _is_integer_value(source.get("city_state_schema_version", null))
		and int(source["city_state_schema_version"]) == version
	)


static func _matches_versions(value: Variant, expected: Dictionary, ignored_keys: Array = []) -> bool:
	if not value is Dictionary:
		return false
	var versions: Dictionary = value
	for key: String in _VERSION_KEYS:
		if not _is_integer_value(versions.get(key, null)):
			return false
		if int(versions[key]) != int(expected[key]):
			return false
	var allowed_keys := _VERSION_KEYS.duplicate()
	allowed_keys.append_array(ignored_keys)
	return _has_exact_keys(versions, allowed_keys)


static func _matches_pair(value: Variant, vertical_schema_version: int, terrain_layout_version: int) -> bool:
	if not value is Dictionary:
		return false
	var pair: Dictionary = value
	return (
		_has_exact_keys(pair, ["vertical_slice_schema_version", "terrain_layout_version"])
		and _is_integer_value(pair.get("vertical_slice_schema_version", null))
		and int(pair["vertical_slice_schema_version"]) == vertical_schema_version
		and _is_integer_value(pair.get("terrain_layout_version", null))
		and int(pair["terrain_layout_version"]) == terrain_layout_version
	)


static func _integer_arrays_equal(value: Variant, expected: Array) -> bool:
	if not value is Array or (value as Array).size() != expected.size():
		return false
	for index: int in range(expected.size()):
		var item: Variant = (value as Array)[index]
		if not _is_integer_value(item) or int(item) != int(expected[index]):
			return false
	return true


static func _string_arrays_equal(value: Variant, expected: Array) -> bool:
	if not value is Array or (value as Array).size() != expected.size():
		return false
	for index: int in range(expected.size()):
		if str((value as Array)[index]) != str(expected[index]):
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
