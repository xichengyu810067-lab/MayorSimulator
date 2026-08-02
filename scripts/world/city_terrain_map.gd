class_name CityTerrainMap
extends RefCounted

## Authoritative logical terrain state for the city map.
##
## Tile ids are deliberately independent from row-major display order.  The
## original 8x8 ids (0..63) keep their identity in the center of the expanded
## 10x10 map; ids 64..99 fill the new outer ring in row-major order.  This lets
## old saves retain every building/construction tile id without migration.

const SCHEMA_VERSION := 1
const LAYOUT_VERSION := 2
const GRID_COLUMNS := 10
const GRID_ROWS := 10
const CELL_COUNT := GRID_COLUMNS * GRID_ROWS
const LEGACY_GRID_SIZE := 8
const LEGACY_CELL_COUNT := LEGACY_GRID_SIZE * LEGACY_GRID_SIZE
const LEGACY_OFFSET := Vector2i(1, 1)
const INVALID_COORDINATE := Vector2i(-1, -1)

const KIND_FLAT_GRASS := "flat_grass"
const KIND_TREES := "trees"
const KIND_HILL_CLIFF := "hill_cliff"
const KIND_RIVER_LAKE := "river_lake"
const KIND_ROAD_PATH := "road_path"
const KIND_RAIL_TRACK := "rail_track"

const TERRAIN_RULES := {
	KIND_FLAT_GRASS: {
		"buildable": true,
		"walkable": true,
		"flattenable": false,
	},
	KIND_TREES: {
		"buildable": false,
		"walkable": false,
		"flattenable": true,
	},
	KIND_HILL_CLIFF: {
		"buildable": false,
		"walkable": false,
		"flattenable": true,
	},
	KIND_RIVER_LAKE: {
		"buildable": false,
		"walkable": false,
		"flattenable": true,
	},
	KIND_ROAD_PATH: {
		"buildable": false,
		"walkable": false,
		"flattenable": true,
	},
	KIND_RAIL_TRACK: {
		"buildable": false,
		"walkable": false,
		"flattenable": true,
	},
}

var _coordinates_by_tile_id: Array[Vector2i] = []
var _tile_id_by_coordinate: Dictionary = {}
var _base_kinds := PackedStringArray()
var _flattened := PackedByteArray()


func _init(snapshot: Dictionary = {}) -> void:
	_initialize_coordinate_mapping()
	_reset_terrain_state()
	if not snapshot.is_empty():
		load_dict(snapshot)


func grid_size() -> Vector2i:
	return Vector2i(GRID_COLUMNS, GRID_ROWS)


func cell_count() -> int:
	return CELL_COUNT


func is_valid_tile_id(tile_id: int) -> bool:
	return tile_id >= 0 and tile_id < CELL_COUNT


func is_valid_coordinate(coordinate: Vector2i) -> bool:
	return _tile_id_by_coordinate.has(coordinate)


func coordinate_for_tile_id(tile_id: int) -> Vector2i:
	if not is_valid_tile_id(tile_id):
		return INVALID_COORDINATE
	return _coordinates_by_tile_id[tile_id]


func tile_id_for_coordinate(coordinate: Vector2i) -> int:
	return int(_tile_id_by_coordinate.get(coordinate, -1))


func coordinates_in_display_order() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for row in range(GRID_ROWS):
		for column in range(GRID_COLUMNS):
			result.append(Vector2i(column, row))
	return result


func tile_ids_in_display_order() -> PackedInt32Array:
	var result := PackedInt32Array()
	for coordinate: Vector2i in coordinates_in_display_order():
		result.append(tile_id_for_coordinate(coordinate))
	return result


func terrain_kinds() -> PackedStringArray:
	return PackedStringArray([
		KIND_FLAT_GRASS,
		KIND_TREES,
		KIND_HILL_CLIFF,
		KIND_RIVER_LAKE,
		KIND_ROAD_PATH,
		KIND_RAIL_TRACK,
	])


func apply_default_city_layout() -> void:
	# Keep the expanded map deterministic and sparse enough that the navigation
	# mesh always has multiple routes.  Coordinates, rather than tile ids, make
	# the authored layout readable while the legacy 0..63 ids remain stable.
	_reset_terrain_state()
	var authored_by_kind := {
		KIND_TREES: [
			Vector2i(0, 0), Vector2i(1, 0), Vector2i(8, 0), Vector2i(9, 0),
			Vector2i(0, 1), Vector2i(9, 1), Vector2i(2, 2), Vector2i(7, 7),
			Vector2i(0, 8), Vector2i(9, 8), Vector2i(0, 9), Vector2i(9, 9),
		],
		KIND_HILL_CLIFF: [
			Vector2i(4, 0), Vector2i(5, 0), Vector2i(7, 2),
			Vector2i(4, 9), Vector2i(5, 9),
		],
		KIND_RIVER_LAKE: [
			Vector2i(0, 5), Vector2i(1, 5), Vector2i(4, 4),
			Vector2i(4, 5), Vector2i(9, 5),
		],
	}
	for kind_variant: Variant in authored_by_kind.keys():
		var kind := str(kind_variant)
		for coordinate_variant: Variant in authored_by_kind[kind_variant]:
			var coordinate: Vector2i = coordinate_variant
			set_tile_kind(tile_id_for_coordinate(coordinate), kind)


func is_valid_terrain_kind(kind: String) -> bool:
	return TERRAIN_RULES.has(kind)


func set_tile_kind(tile_id: int, kind: String) -> bool:
	if not is_valid_tile_id(tile_id) or not is_valid_terrain_kind(kind):
		return false
	_base_kinds[tile_id] = kind
	_flattened[tile_id] = 0
	return true


func configure_tile(tile_id: int, kind: String, flattened: bool = false) -> bool:
	if not set_tile_kind(tile_id, kind):
		return false
	if flattened and kind != KIND_FLAT_GRASS and bool(TERRAIN_RULES[kind]["flattenable"]):
		_flattened[tile_id] = 1
	return true


func base_kind(tile_id: int) -> String:
	return _base_kinds[tile_id] if is_valid_tile_id(tile_id) else ""


func effective_kind(tile_id: int) -> String:
	if not is_valid_tile_id(tile_id):
		return ""
	return KIND_FLAT_GRASS if _flattened[tile_id] == 1 else _base_kinds[tile_id]


func is_flattened(tile_id: int) -> bool:
	return is_valid_tile_id(tile_id) and _flattened[tile_id] == 1


func is_buildable(tile_id: int) -> bool:
	var kind := effective_kind(tile_id)
	return not kind.is_empty() and bool(TERRAIN_RULES[kind]["buildable"])


func is_walkable(tile_id: int) -> bool:
	var kind := effective_kind(tile_id)
	return not kind.is_empty() and bool(TERRAIN_RULES[kind]["walkable"])


func is_flattenable(tile_id: int) -> bool:
	if not is_valid_tile_id(tile_id) or is_flattened(tile_id):
		return false
	return bool(TERRAIN_RULES[_base_kinds[tile_id]]["flattenable"])


func tile_state(tile_id: int) -> Dictionary:
	if not is_valid_tile_id(tile_id):
		return {}
	var original_kind := _base_kinds[tile_id]
	var resolved_kind := effective_kind(tile_id)
	return {
		"tile_id": tile_id,
		"coordinate": coordinate_for_tile_id(tile_id),
		"base_kind": original_kind,
		"effective_kind": resolved_kind,
		"flattened": is_flattened(tile_id),
		"buildable": bool(TERRAIN_RULES[resolved_kind]["buildable"]),
		"walkable": bool(TERRAIN_RULES[resolved_kind]["walkable"]),
		"flattenable": is_flattenable(tile_id),
	}


func all_tile_states() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for tile_id in range(CELL_COUNT):
		result.append(tile_state(tile_id))
	return result


func flatten_tile(tile_id: int) -> Dictionary:
	if not is_valid_tile_id(tile_id):
		return {"ok": false, "error": "invalid_tile_id", "tile_id": tile_id}
	if effective_kind(tile_id) == KIND_FLAT_GRASS:
		return {
			"ok": true,
			"changed": false,
			"status": "already_flat",
			"tile": tile_state(tile_id),
		}
	if not is_flattenable(tile_id):
		return {
			"ok": false,
			"error": "terrain_not_flattenable",
			"tile": tile_state(tile_id),
		}
	_flattened[tile_id] = 1
	return {
		"ok": true,
		"changed": true,
		"status": "flattened",
		"tile": tile_state(tile_id),
	}


func flatten(tile_id: int) -> Dictionary:
	return flatten_tile(tile_id)


func restore_base_terrain(tile_id: int) -> bool:
	if not is_valid_tile_id(tile_id):
		return false
	_flattened[tile_id] = 0
	return true


func non_walkable_tile_ids() -> PackedInt32Array:
	var result := PackedInt32Array()
	for tile_id in range(CELL_COUNT):
		if not is_walkable(tile_id):
			result.append(tile_id)
	return result


func navigation_blockers(tile_centers: PackedVector2Array) -> Dictionary:
	var blockers: Dictionary = {}
	for tile_id in non_walkable_tile_ids():
		if tile_id < 0 or tile_id >= tile_centers.size():
			continue
		blockers[tile_id] = {
			"center": tile_centers[tile_id],
			"kind": effective_kind(tile_id),
		}
	return blockers


func to_dict() -> Dictionary:
	var serialized_tiles: Array[Dictionary] = []
	for tile_id in range(CELL_COUNT):
		serialized_tiles.append({
			"tile_id": tile_id,
			"base_kind": _base_kinds[tile_id],
			"flattened": is_flattened(tile_id),
		})
	return {
		"schema_version": SCHEMA_VERSION,
		"layout_version": LAYOUT_VERSION,
		"grid_columns": GRID_COLUMNS,
		"grid_rows": GRID_ROWS,
		"tiles": serialized_tiles,
	}


static func validate_snapshot(snapshot: Dictionary) -> Dictionary:
	var required_top_level := [
		"schema_version", "layout_version", "grid_columns", "grid_rows", "tiles",
	]
	if snapshot.size() != required_top_level.size():
		return _snapshot_error("invalid_snapshot_shape")
	for field_name: String in required_top_level:
		if not snapshot.has(field_name):
			return _snapshot_error("missing_%s" % field_name)
	if not _is_integer_value(snapshot["schema_version"]) or int(snapshot["schema_version"]) != SCHEMA_VERSION:
		return _snapshot_error("unsupported_schema")
	if not _is_integer_value(snapshot["layout_version"]) or int(snapshot["layout_version"]) != LAYOUT_VERSION:
		return _snapshot_error("unsupported_layout")
	if not _is_integer_value(snapshot["grid_columns"]) or int(snapshot["grid_columns"]) != GRID_COLUMNS:
		return _snapshot_error("invalid_grid_columns")
	if not _is_integer_value(snapshot["grid_rows"]) or int(snapshot["grid_rows"]) != GRID_ROWS:
		return _snapshot_error("invalid_grid_rows")
	var tiles_value: Variant = snapshot["tiles"]
	if not tiles_value is Array or (tiles_value as Array).size() != CELL_COUNT:
		return _snapshot_error("invalid_tile_count")
	var seen_tile_ids: Dictionary = {}
	for tile_value: Variant in tiles_value:
		if not tile_value is Dictionary:
			return _snapshot_error("invalid_tile_record")
		var tile: Dictionary = tile_value
		if tile.size() != 3 or not tile.has("tile_id") or not tile.has("base_kind") or not tile.has("flattened"):
			return _snapshot_error("invalid_tile_record_shape")
		var tile_id_value: Variant = tile["tile_id"]
		if not _is_integer_value(tile_id_value):
			return _snapshot_error("invalid_tile_id")
		var tile_id := int(tile_id_value)
		if tile_id < 0 or tile_id >= CELL_COUNT or seen_tile_ids.has(tile_id):
			return _snapshot_error("invalid_tile_id")
		var kind_value: Variant = tile["base_kind"]
		if not kind_value is String or not TERRAIN_RULES.has(str(kind_value)):
			return _snapshot_error("invalid_terrain_kind")
		var flattened_value: Variant = tile["flattened"]
		if not flattened_value is bool:
			return _snapshot_error("invalid_flattened_flag")
		if str(kind_value) == KIND_FLAT_GRASS and bool(flattened_value):
			return _snapshot_error("flat_grass_cannot_be_flattened")
		seen_tile_ids[tile_id] = true
	if seen_tile_ids.size() != CELL_COUNT:
		return _snapshot_error("incomplete_tile_coverage")
	for tile_id: int in range(CELL_COUNT):
		if not seen_tile_ids.has(tile_id):
			return _snapshot_error("incomplete_tile_coverage")
	return {"valid": true, "error": ""}


func load_dict(data: Dictionary) -> void:
	_reset_terrain_state()
	var raw_tiles: Variant = data.get("tiles", [])
	if raw_tiles is Array and not (raw_tiles as Array).is_empty():
		for tile_variant: Variant in raw_tiles:
			if not tile_variant is Dictionary:
				continue
			_load_tile_record(tile_variant)
		return

	# Tolerate a compact dictionary form for callers that persist only changed
	# tiles. String keys keep the snapshot JSON-safe.
	var compact_tiles: Variant = data.get("terrain_by_tile", {})
	if compact_tiles is Dictionary:
		for tile_key: Variant in compact_tiles.keys():
			var record_variant: Variant = compact_tiles[tile_key]
			if not record_variant is Dictionary:
				continue
			var record: Dictionary = Dictionary(record_variant).duplicate(true)
			record["tile_id"] = int(str(tile_key))
			_load_tile_record(record)


static func create_from_dict(data: Dictionary) -> CityTerrainMap:
	return CityTerrainMap.new(data)


func _load_tile_record(record: Dictionary) -> void:
	var tile_id := int(record.get("tile_id", -1))
	var kind := str(record.get("base_kind", record.get("kind", KIND_FLAT_GRASS)))
	if not configure_tile(tile_id, kind, bool(record.get("flattened", false))):
		return


func _initialize_coordinate_mapping() -> void:
	_coordinates_by_tile_id.clear()
	_tile_id_by_coordinate.clear()

	# Preserve the original row-major 8x8 tile ids in the central 8x8 area.
	for legacy_row in range(LEGACY_GRID_SIZE):
		for legacy_column in range(LEGACY_GRID_SIZE):
			_register_coordinate(Vector2i(
				legacy_column + LEGACY_OFFSET.x,
				legacy_row + LEGACY_OFFSET.y
			))

	# Append the 36 new outer-ring coordinates in display row-major order.
	for row in range(GRID_ROWS):
		for column in range(GRID_COLUMNS):
			var coordinate := Vector2i(column, row)
			if _tile_id_by_coordinate.has(coordinate):
				continue
			_register_coordinate(coordinate)

	assert(_coordinates_by_tile_id.size() == CELL_COUNT)
	assert(_tile_id_by_coordinate.size() == CELL_COUNT)


func _register_coordinate(coordinate: Vector2i) -> void:
	var tile_id := _coordinates_by_tile_id.size()
	_coordinates_by_tile_id.append(coordinate)
	_tile_id_by_coordinate[coordinate] = tile_id


func _reset_terrain_state() -> void:
	_base_kinds.clear()
	_flattened.clear()
	for _tile_id in range(CELL_COUNT):
		_base_kinds.append(KIND_FLAT_GRASS)
		_flattened.append(0)


static func _snapshot_error(code: String) -> Dictionary:
	return {"valid": false, "error": code}


static func _is_integer_value(value: Variant) -> bool:
	return value is int or (value is float and is_finite(float(value)) and float(value) == roundf(float(value)))
