class_name SaveSchemaAuthority
extends RefCounted

## Shared save-schema authority. The registry and these runtime constants define
## the only writer pair and the only layout-bearing migration input.

const LEGACY_MIGRATION_VERTICAL_SCHEMA_VERSION := 7
const LEGACY_MIGRATION_TERRAIN_LAYOUT_VERSION := 2
const CURRENT_VERTICAL_SCHEMA_VERSION := 8
const CURRENT_TERRAIN_LAYOUT_VERSION := 3
const MAX_SUPPORTED_VERTICAL_SLICE_METADATA_SCHEMA := CURRENT_VERTICAL_SCHEMA_VERSION
const MAX_SUPPORTED_TERRAIN_LAYOUT_VERSION := CURRENT_TERRAIN_LAYOUT_VERSION
const REGISTRY_SCHEMA_VERSION := 1


static func validate_vertical_terrain_pair(vertical_schema_version: int, terrain_layout_version: int) -> bool:
	# Semantic validation only accepts the current pair. The legacy pair must pass
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


static func validate_registry_json(registry_json: String) -> bool:
	# This is a test/tooling contract gate only. Runtime save validation remains
	# constant-backed and never reads registry files during a load or save.
	var parser := JSON.new()
	if parser.parse(registry_json) != OK or not parser.data is Dictionary:
		return false
	var registry: Dictionary = parser.data
	if not _is_integer_value(registry.get("registry_schema_version", null)):
		return false
	if int(registry["registry_schema_version"]) != REGISTRY_SCHEMA_VERSION:
		return false
	if not _matches_version_pair(registry.get("current_writer", null), CURRENT_VERTICAL_SCHEMA_VERSION, CURRENT_TERRAIN_LAYOUT_VERSION):
		return false
	if not _matches_version_pair(registry.get("version_ceiling", null), MAX_SUPPORTED_VERTICAL_SLICE_METADATA_SCHEMA, MAX_SUPPORTED_TERRAIN_LAYOUT_VERSION):
		return false
	if str(registry.get("future_version_policy", "")) != "explicit_reject_no_overwrite":
		return false
	var matrix: Variant = registry.get("supported_version_matrix", null)
	return _contains_pair_with_contract(
		matrix,
		CURRENT_VERTICAL_SCHEMA_VERSION,
		CURRENT_TERRAIN_LAYOUT_VERSION,
		"current",
		true
	) and _contains_pair_with_contract(
		matrix,
		LEGACY_MIGRATION_VERTICAL_SCHEMA_VERSION,
		LEGACY_MIGRATION_TERRAIN_LAYOUT_VERSION,
		"legacy_migration_input",
		false
	) and _has_unique_current_writer(matrix) and _contains_pair(
		registry.get("rejected_combinations", null),
		CURRENT_VERTICAL_SCHEMA_VERSION,
		LEGACY_MIGRATION_TERRAIN_LAYOUT_VERSION
	) and _contains_pair(
		registry.get("rejected_combinations", null),
		LEGACY_MIGRATION_VERTICAL_SCHEMA_VERSION,
		CURRENT_TERRAIN_LAYOUT_VERSION
	) and _contains_active_migration(registry.get("migration_registry", null))


static func _matches_version_pair(value: Variant, vertical_schema_version: int, terrain_layout_version: int) -> bool:
	if not value is Dictionary:
		return false
	var pair: Dictionary = value
	return _is_integer_value(pair.get("vertical_slice_schema_version", null)) \
		and _is_integer_value(pair.get("terrain_layout_version", null)) \
		and int(pair["vertical_slice_schema_version"]) == vertical_schema_version \
		and int(pair["terrain_layout_version"]) == terrain_layout_version


static func _contains_pair(value: Variant, vertical_schema_version: int, terrain_layout_version: int) -> bool:
	if not value is Array:
		return false
	for item: Variant in value:
		if _matches_version_pair(item, vertical_schema_version, terrain_layout_version):
			return true
	return false


static func _contains_pair_with_contract(
	value: Variant,
	vertical_schema_version: int,
	terrain_layout_version: int,
	status: String,
	writer_allowed: bool
) -> bool:
	if not value is Array:
		return false
	for item: Variant in value:
		if (
			_matches_version_pair(item, vertical_schema_version, terrain_layout_version)
			and str((item as Dictionary).get("status", "")) == status
			and (item as Dictionary).get("writer_allowed", null) is bool
			and bool((item as Dictionary)["writer_allowed"]) == writer_allowed
		):
			return true
	return false


static func _contains_active_migration(value: Variant) -> bool:
	if not value is Array:
		return false
	for item: Variant in value:
		if not item is Dictionary:
			continue
		var migration: Dictionary = item
		if (
			str(migration.get("id", "")) == "vertical_7_layout_2_to_8_layout_3"
			and str(migration.get("source", "")) == "vertical_7_layout_2"
			and str(migration.get("target", "")) == "vertical_8_layout_3"
			and str(migration.get("status", "")) == "active"
		):
			return true
	return false


static func _has_unique_current_writer(value: Variant) -> bool:
	if not value is Array:
		return false
	var writer_count := 0
	for item: Variant in value:
		if not item is Dictionary:
			continue
		var entry: Dictionary = item
		var writer_value: Variant = entry.get("writer_allowed", null)
		if not writer_value is bool or not bool(writer_value):
			continue
		writer_count += 1
		if (
			not _matches_version_pair(entry, CURRENT_VERTICAL_SCHEMA_VERSION, CURRENT_TERRAIN_LAYOUT_VERSION)
			or str(entry.get("status", "")) != "current"
		):
			return false
	return writer_count == 1


static func _is_integer_value(value: Variant) -> bool:
	return value is int or (value is float and is_finite(float(value)) and float(value) == roundf(float(value)))
