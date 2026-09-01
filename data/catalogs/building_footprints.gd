class_name BuildingFootprints
extends RefCounted

## Canonical logical occupancy for buildings.
##
## A building remains one domain record anchored at its westernmost tile.  The
## occupied tile ids are derived through CityTerrainMap so the stable, non-row-
## major tile identities remain authoritative.

const SINGLE_V1 := "single_v1"
const LINE_2_EAST_V1 := "line_2_east_v1"
const LINE_3_EAST_V1 := "line_3_east_v1"

const SMALL := "small"
const MEDIUM := "medium"
const LARGE := "large"

# Only the schema 4-8 migration path may write this marker.  It records the
# deliberate decision to retain a legacy building/job as one occupied tile
# even when its historical blueprint happened to say medium or large.
const LEGACY_SINGLE_PROVENANCE_FIELD := "footprint_provenance"
const LEGACY_SINGLE_PROVENANCE := "legacy_schema_4_8_single_v1"

const FOOTPRINTS := {
	SINGLE_V1: {
		"size_tier": SMALL,
		"offsets": [Vector2i(0, 0)],
	},
	LINE_2_EAST_V1: {
		"size_tier": MEDIUM,
		"offsets": [Vector2i(0, 0), Vector2i(1, 0)],
	},
	LINE_3_EAST_V1: {
		"size_tier": LARGE,
		"offsets": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
	},
}

const FOOTPRINT_BY_SIZE := {
	SMALL: SINGLE_V1,
	MEDIUM: LINE_2_EAST_V1,
	LARGE: LINE_3_EAST_V1,
}


static func footprint_id_for_size(size_tier: String) -> String:
	return str(FOOTPRINT_BY_SIZE.get(size_tier, ""))


static func size_for_footprint(footprint_id: String) -> String:
	if not FOOTPRINTS.has(footprint_id):
		return ""
	return str((FOOTPRINTS[footprint_id] as Dictionary).get("size_tier", ""))


static func offsets_for_footprint(footprint_id: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not FOOTPRINTS.has(footprint_id):
		return result
	for offset_variant: Variant in (FOOTPRINTS[footprint_id] as Dictionary).get("offsets", []):
		result.append(offset_variant as Vector2i)
	return result


static func resolve_for_size(size_tier: String, anchor_tile_id: int, terrain_map) -> Dictionary:
	var footprint_id := footprint_id_for_size(size_tier)
	if footprint_id.is_empty():
		return {"ok": false, "error": "unsupported_building_size"}
	return resolve_for_footprint(footprint_id, anchor_tile_id, terrain_map)


static func resolve_for_footprint(footprint_id: String, anchor_tile_id: int, terrain_map) -> Dictionary:
	if not FOOTPRINTS.has(footprint_id):
		return {"ok": false, "error": "unsupported_footprint"}
	if terrain_map == null or not terrain_map.is_valid_tile_id(anchor_tile_id):
		return {"ok": false, "error": "invalid_anchor_tile_id"}
	var anchor_coordinate: Vector2i = terrain_map.coordinate_for_tile_id(anchor_tile_id)
	var occupied_tile_ids: Array[int] = []
	for offset: Vector2i in offsets_for_footprint(footprint_id):
		var coordinate := anchor_coordinate + offset
		if not terrain_map.is_valid_coordinate(coordinate):
			return {
				"ok": false,
				"error": "footprint_out_of_bounds",
				"anchor_tile_id": anchor_tile_id,
				"footprint_id": footprint_id,
			}
		var tile_id := int(terrain_map.tile_id_for_coordinate(coordinate))
		if tile_id < 0 or occupied_tile_ids.has(tile_id):
			return {"ok": false, "error": "invalid_footprint_mapping"}
		occupied_tile_ids.append(tile_id)
	return {
		"ok": true,
		"anchor_tile_id": anchor_tile_id,
		"footprint_id": footprint_id,
		"size_tier": size_for_footprint(footprint_id),
		"occupied_tile_ids": occupied_tile_ids,
	}


static func validate_persisted_record(
	record: Dictionary,
	terrain_map,
	authoritative_size_tier: String = ""
) -> Dictionary:
	for field_name: String in ["tile_index", "anchor_tile_id", "footprint_id", "occupied_tile_ids"]:
		if not record.has(field_name):
			return {"valid": false, "error": "missing_%s" % field_name}
	if not _is_integer_value(record.get("tile_index", null)):
		return {"valid": false, "error": "invalid_tile_index"}
	if not _is_integer_value(record.get("anchor_tile_id", null)):
		return {"valid": false, "error": "invalid_anchor_tile_id"}
	var anchor_tile_id := int(record["anchor_tile_id"])
	if int(record["tile_index"]) != anchor_tile_id:
		return {"valid": false, "error": "anchor_tile_mismatch"}
	var footprint_value: Variant = record.get("footprint_id", null)
	if not footprint_value is String or not FOOTPRINTS.has(str(footprint_value)):
		return {"valid": false, "error": "invalid_footprint_id"}
	var occupied_value: Variant = record.get("occupied_tile_ids", null)
	if not occupied_value is Array:
		return {"valid": false, "error": "invalid_occupied_tile_ids"}
	var occupied_tile_ids: Array[int] = []
	for tile_variant: Variant in occupied_value:
		if not _is_integer_value(tile_variant):
			return {"valid": false, "error": "invalid_occupied_tile_id"}
		var tile_id := int(tile_variant)
		if occupied_tile_ids.has(tile_id):
			return {"valid": false, "error": "duplicate_occupied_tile_id"}
		occupied_tile_ids.append(tile_id)
	var resolved := resolve_for_footprint(str(footprint_value), anchor_tile_id, terrain_map)
	if not bool(resolved.get("ok", false)):
		return {"valid": false, "error": str(resolved.get("error", "invalid_footprint"))}
	if occupied_tile_ids != (resolved.get("occupied_tile_ids", []) as Array):
		return {"valid": false, "error": "footprint_offsets_mismatch"}
	var provenance_value: Variant = record.get(LEGACY_SINGLE_PROVENANCE_FIELD, null)
	var has_legacy_provenance := record.has(LEGACY_SINGLE_PROVENANCE_FIELD)
	if has_legacy_provenance:
		if not provenance_value is String or str(provenance_value) != LEGACY_SINGLE_PROVENANCE:
			return {"valid": false, "error": "invalid_footprint_provenance"}
		if str(footprint_value) != SINGLE_V1 or occupied_tile_ids != [anchor_tile_id]:
			return {"valid": false, "error": "legacy_footprint_provenance_mismatch"}
	else:
		var resolved_size_tier := authoritative_size_tier
		if resolved_size_tier.is_empty():
			var blueprint_value: Variant = record.get("blueprint", null)
			if blueprint_value is Dictionary:
				resolved_size_tier = str((blueprint_value as Dictionary).get("size_tier", ""))
		var expected_footprint_id := footprint_id_for_size(resolved_size_tier)
		if expected_footprint_id.is_empty():
			return {"valid": false, "error": "invalid_building_size_tier"}
		if str(footprint_value) != expected_footprint_id:
			return {"valid": false, "error": "building_size_footprint_mismatch"}
	return {
		"valid": true,
		"anchor_tile_id": anchor_tile_id,
		"footprint_id": str(footprint_value),
		"size_tier": authoritative_size_tier if not authoritative_size_tier.is_empty() else str(resolved.get("size_tier", "")),
		"occupied_tile_ids": occupied_tile_ids,
		"legacy_single_provenance": has_legacy_provenance,
	}


static func legacy_single_fields(tile_index: int, terrain_map) -> Dictionary:
	var resolved := resolve_for_footprint(SINGLE_V1, tile_index, terrain_map)
	if not bool(resolved.get("ok", false)):
		return {}
	return {
		"anchor_tile_id": tile_index,
		"footprint_id": SINGLE_V1,
		"occupied_tile_ids": [tile_index],
		LEGACY_SINGLE_PROVENANCE_FIELD: LEGACY_SINGLE_PROVENANCE,
	}


static func _is_integer_value(value: Variant) -> bool:
	return value is int or (value is float and is_equal_approx(value, roundf(value)))
