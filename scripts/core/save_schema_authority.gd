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


static func validate_vertical_terrain_pair(vertical_schema_version: int, terrain_layout_version: int) -> bool:
	# Layout-bearing snapshots are only valid when their vertical schema has an
	# explicitly activated pair. Schema 8/layout 3 stays deliberately rejected
	# until B5 lands and C3 performs the atomic writer/migration activation.
	return (
		vertical_schema_version == CURRENT_VERTICAL_SCHEMA_VERSION
		and terrain_layout_version == CURRENT_TERRAIN_LAYOUT_VERSION
	)
