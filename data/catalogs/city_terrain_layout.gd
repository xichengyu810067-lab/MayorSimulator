class_name CityTerrainLayout
extends RefCounted

const SquareGridLayoutScript = preload("res://scripts/world/square_grid_layout.gd")
const CityBackdropTerrainCatalog = preload("res://data/catalogs/city_backdrop_terrain.gd")

## Frozen terrain classification produced by terrain layout 3 before the
## presentation projection changed from diamonds to squares. Missing tile ids
## are deliberately flat grass with zero backdrop coverage.

const LEGACY_LAYOUT_VERSION := 3
const LAYOUT_VERSION := 4
const GRID_COLUMNS := 10
const GRID_ROWS := 10
const CELL_COUNT := GRID_COLUMNS * GRID_ROWS
const LEGACY_GRID_SIZE := 8
const LEGACY_CELL_COUNT := LEGACY_GRID_SIZE * LEGACY_GRID_SIZE
const LEGACY_OFFSET := Vector2i(1, 1)
const SOURCE_ASSET := "res://assets/images/world/backgrounds/city-map-background.png"
const INVALID_COORDINATE := Vector2i(-1, -1)
const MIN_FEATURE_COVERAGE := 0.035

const FROZEN_NON_FLAT_RECORDS := {
	0: {"kind": "river_lake", "coverage": 0.623264041608023, "feature_ids": ["lake_north_central"]},
	1: {"kind": "river_lake", "coverage": 1.0, "feature_ids": ["lake_north_central"]},
	2: {"kind": "river_lake", "coverage": 1.0, "feature_ids": ["lake_north_central"]},
	3: {"kind": "river_lake", "coverage": 0.988822953516642, "feature_ids": ["lake_north_central"]},
	8: {"kind": "river_lake", "coverage": 0.952479741204858, "feature_ids": ["lake_north_central"]},
	9: {"kind": "river_lake", "coverage": 1.0, "feature_ids": ["lake_north_central"]},
	10: {"kind": "river_lake", "coverage": 1.0, "feature_ids": ["lake_north_central"]},
	11: {"kind": "river_lake", "coverage": 0.590111562687272, "feature_ids": ["lake_north_central"]},
	16: {"kind": "river_lake", "coverage": 0.119005616089063, "feature_ids": ["lake_north_central"]},
	17: {"kind": "river_lake", "coverage": 0.610400721357374, "feature_ids": ["lake_north_central"]},
	18: {"kind": "river_lake", "coverage": 0.416543943121935, "feature_ids": ["lake_north_central"]},
	64: {"kind": "hill_cliff", "coverage": 1.0, "feature_ids": ["northern_cliffs"]},
	65: {"kind": "hill_cliff", "coverage": 0.888921062515119, "feature_ids": ["northern_cliffs"]},
	66: {"kind": "river_lake", "coverage": 0.258933451878697, "feature_ids": ["lake_north_central"]},
	67: {"kind": "river_lake", "coverage": 1.0, "feature_ids": ["lake_north_central"]},
	68: {"kind": "river_lake", "coverage": 0.796739120537089, "feature_ids": ["lake_north_central"]},
	72: {"kind": "trees_scenery", "coverage": 0.32164759572168, "feature_ids": ["east_forest"]},
	73: {"kind": "trees_scenery", "coverage": 0.979563965446746, "feature_ids": ["east_forest"]},
	74: {"kind": "hill_cliff", "coverage": 0.406731682709621, "feature_ids": ["northern_cliffs"]},
	75: {"kind": "trees_scenery", "coverage": 0.145941630288969, "feature_ids": ["east_forest"]},
	79: {"kind": "trees_scenery", "coverage": 0.189598023080064, "feature_ids": ["east_path_rock_garden_upper"]},
	83: {"kind": "trees_scenery", "coverage": 0.531853221487949, "feature_ids": ["south_meadow_tree_grove"]},
	84: {"kind": "hill_cliff", "coverage": 0.0911653560286756, "feature_ids": ["west_cliff_spur"]},
	85: {"kind": "trees_scenery", "coverage": 1.03946699213596, "feature_ids": ["south_meadow_rocks", "south_meadow_tree_grove"]},
	86: {"kind": "hill_cliff", "coverage": 0.698583330426897, "feature_ids": ["west_cliff_spur"]},
	87: {"kind": "trees_scenery", "coverage": 0.582144923146387, "feature_ids": ["south_meadow_rocks"]},
	88: {"kind": "trees_scenery", "coverage": 0.353505515112665, "feature_ids": ["west_forest"]},
	89: {"kind": "trees_scenery", "coverage": 0.237427885309229, "feature_ids": ["southcentral_forest"]},
	90: {"kind": "trees_scenery", "coverage": 1.0, "feature_ids": ["west_forest"]},
	91: {"kind": "trees_scenery", "coverage": 0.468634108101122, "feature_ids": ["west_forest"]},
	98: {"kind": "trees_scenery", "coverage": 0.112991880649081, "feature_ids": ["southcentral_forest"]},
	99: {"kind": "trees_scenery", "coverage": 0.986220065703554, "feature_ids": ["southcentral_forest"]},
}


static func is_valid_tile_id(tile_id: int) -> bool:
	return tile_id >= 0 and tile_id < CELL_COUNT


static func coordinate_for_tile_id(tile_id: int) -> Vector2i:
	if not is_valid_tile_id(tile_id):
		return INVALID_COORDINATE
	if tile_id < LEGACY_CELL_COUNT:
		return Vector2i(
			tile_id % LEGACY_GRID_SIZE + LEGACY_OFFSET.x,
			int(tile_id / LEGACY_GRID_SIZE) + LEGACY_OFFSET.y
		)
	var outer_tile_id := LEGACY_CELL_COUNT
	for row in GRID_ROWS:
		for column in GRID_COLUMNS:
			var coordinate := Vector2i(column, row)
			if _is_legacy_coordinate(coordinate):
				continue
			if outer_tile_id == tile_id:
				return coordinate
			outer_tile_id += 1
	return INVALID_COORDINATE


static func tile_id_for_coordinate(coordinate: Vector2i) -> int:
	if not SquareGridLayoutScript.is_valid_coordinate(coordinate):
		return -1
	if _is_legacy_coordinate(coordinate):
		return (
			(coordinate.y - LEGACY_OFFSET.y) * LEGACY_GRID_SIZE
			+ coordinate.x - LEGACY_OFFSET.x
		)
	var outer_tile_id := LEGACY_CELL_COUNT
	for row in GRID_ROWS:
		for column in GRID_COLUMNS:
			var candidate := Vector2i(column, row)
			if _is_legacy_coordinate(candidate):
				continue
			if candidate == coordinate:
				return outer_tile_id
			outer_tile_id += 1
	return -1


static func model_for_tile_id(tile_id: int) -> Dictionary:
	return _square_model_for_tile_id(tile_id)


static func legacy_model_for_tile_id(tile_id: int) -> Dictionary:
	if not is_valid_tile_id(tile_id):
		return {}
	var coordinate := coordinate_for_tile_id(tile_id)
	var frozen: Dictionary = FROZEN_NON_FLAT_RECORDS.get(tile_id, {})
	return {
		"tile_id": tile_id,
		"coordinate": coordinate,
		"kind": str(frozen.get("kind", "flat_grass")),
		"coverage": float(frozen.get("coverage", 0.0)),
		"feature_ids": Array(frozen.get("feature_ids", [])).duplicate(),
		"source_asset": SOURCE_ASSET,
		"plot_center": SquareGridLayoutScript.center_for_coordinate(coordinate),
		"plot_half_extents": SquareGridLayoutScript.CELL_SIZE * 0.5,
	}


static func model_for_coordinate(coordinate: Vector2i) -> Dictionary:
	return model_for_tile_id(tile_id_for_coordinate(coordinate))


static func legacy_model_for_coordinate(coordinate: Vector2i) -> Dictionary:
	return legacy_model_for_tile_id(tile_id_for_coordinate(coordinate))


static func terrain_kind_for_tile_id(tile_id: int) -> String:
	var kind := str(model_for_tile_id(tile_id).get("kind", ""))
	return "trees" if kind == "trees_scenery" else kind


static func legacy_terrain_kind_for_tile_id(tile_id: int) -> String:
	var kind := str(legacy_model_for_tile_id(tile_id).get("kind", ""))
	return "trees" if kind == "trees_scenery" else kind


static func is_blocked_tile_id(tile_id: int) -> bool:
	return terrain_kind_for_tile_id(tile_id) != "flat_grass"


static func _square_model_for_tile_id(tile_id: int) -> Dictionary:
	if not is_valid_tile_id(tile_id):
		return {}
	var coordinate := coordinate_for_tile_id(tile_id)
	var plot_rect := SquareGridLayoutScript.rect_for_coordinate(coordinate)
	var plot := PackedVector2Array([
		plot_rect.position,
		plot_rect.position + Vector2(plot_rect.size.x, 0.0),
		plot_rect.end,
		plot_rect.position + Vector2(0.0, plot_rect.size.y),
	])
	var plot_area := plot_rect.size.x * plot_rect.size.y
	var coverage_by_kind: Dictionary = {}
	var feature_ids_by_kind: Dictionary = {}
	var kind_order := PackedStringArray()
	for polygon_data: Dictionary in CityBackdropTerrainCatalog.static_polygons():
		var overlap_area := 0.0
		for intersection: PackedVector2Array in Geometry2D.intersect_polygons(
			plot, PackedVector2Array(polygon_data["points"])
		):
			overlap_area += _polygon_area(intersection)
		var feature_coverage := overlap_area / plot_area
		if feature_coverage < MIN_FEATURE_COVERAGE:
			continue
		var kind := str(polygon_data.get("kind", ""))
		if not coverage_by_kind.has(kind):
			kind_order.append(kind)
			coverage_by_kind[kind] = 0.0
			feature_ids_by_kind[kind] = []
		coverage_by_kind[kind] = float(coverage_by_kind[kind]) + feature_coverage
		var ids: Array = feature_ids_by_kind[kind]
		ids.append(str(polygon_data.get("id", "")))
		feature_ids_by_kind[kind] = ids
	var winning_kind := "flat_grass"
	var winning_coverage := 0.0
	for kind: String in kind_order:
		var coverage := float(coverage_by_kind[kind])
		if coverage > winning_coverage:
			winning_kind = kind
			winning_coverage = coverage
	return {
		"tile_id": tile_id,
		"coordinate": coordinate,
		"kind": winning_kind,
		"coverage": winning_coverage,
		"feature_ids": Array(feature_ids_by_kind.get(winning_kind, [])).duplicate(),
		"source_asset": SOURCE_ASSET,
		"plot_center": plot_rect.get_center(),
		"plot_half_extents": plot_rect.size * 0.5,
	}


static func _polygon_area(points: PackedVector2Array) -> float:
	if points.size() < 3:
		return 0.0
	var doubled_area := 0.0
	for point_index in points.size():
		var current := points[point_index]
		var next := points[(point_index + 1) % points.size()]
		doubled_area += current.x * next.y - next.x * current.y
	return absf(doubled_area) * 0.5


static func _is_legacy_coordinate(coordinate: Vector2i) -> bool:
	return (
		coordinate.x >= LEGACY_OFFSET.x
		and coordinate.x < LEGACY_OFFSET.x + LEGACY_GRID_SIZE
		and coordinate.y >= LEGACY_OFFSET.y
		and coordinate.y < LEGACY_OFFSET.y + LEGACY_GRID_SIZE
	)
