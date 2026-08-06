class_name SaveSchemaAuthority
extends RefCounted

## Shared save-schema authority. C1 establishes the current writer/read ceiling
## without activating the B5 backdrop layout or the later C3 migration.

const MAX_SUPPORTED_VERTICAL_SLICE_METADATA_SCHEMA := 7
const MAX_SUPPORTED_TERRAIN_LAYOUT_VERSION := 2
const CURRENT_VERTICAL_SCHEMA_VERSION := 7
const CURRENT_TERRAIN_LAYOUT_VERSION := 2
const PLANNED_ACTIVATION_VERTICAL_SCHEMA_VERSION := 8
const PLANNED_ACTIVATION_TERRAIN_LAYOUT_VERSION := 3
const REGISTRY_SCHEMA_VERSION := 1


static func validate_vertical_terrain_pair(vertical_schema_version: int, terrain_layout_version: int) -> bool:
	# Layout-bearing snapshots are only valid when their vertical schema has an
	# explicitly activated pair. Schema 8/layout 3 stays deliberately rejected
	# until B5 lands and C3 performs the atomic writer/migration activation.
	return (
		vertical_schema_version == CURRENT_VERTICAL_SCHEMA_VERSION
		and terrain_layout_version == CURRENT_TERRAIN_LAYOUT_VERSION
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
	return _contains_pair(registry.get("supported_version_matrix", null), CURRENT_VERTICAL_SCHEMA_VERSION, CURRENT_TERRAIN_LAYOUT_VERSION) \
		and _contains_pair(registry.get("supported_version_matrix", null), PLANNED_ACTIVATION_VERTICAL_SCHEMA_VERSION, PLANNED_ACTIVATION_TERRAIN_LAYOUT_VERSION) \
		and _contains_pair(registry.get("rejected_combinations", null), PLANNED_ACTIVATION_VERTICAL_SCHEMA_VERSION, CURRENT_TERRAIN_LAYOUT_VERSION)


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


static func _is_integer_value(value: Variant) -> bool:
	return value is int or (value is float and is_finite(float(value)) and float(value) == roundf(float(value)))
