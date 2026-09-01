class_name SquareGridLayout
extends RefCounted

## Canonical stage-local projection for the fixed 10x10 city grid.
##
## Logical tile ids remain owned by CityTerrainMap.  This class owns only the
## coordinate geometry so every visual, hit target, route endpoint, and NPC
## tile lookup agrees on the same axis-aligned square cells.

const STAGE_SIZE := Vector2(1120.0, 820.0)
const GRID_SIZE := Vector2i(10, 10)
const CELL_SIZE := Vector2(70.0, 70.0)
const GRID_ORIGIN := Vector2(210.0, 60.0)
const INVALID_COORDINATE := Vector2i(-1, -1)


static func grid_rect() -> Rect2:
	return Rect2(GRID_ORIGIN, Vector2(GRID_SIZE) * CELL_SIZE)


static func is_valid_coordinate(coordinate: Vector2i) -> bool:
	return (
		coordinate.x >= 0
		and coordinate.x < GRID_SIZE.x
		and coordinate.y >= 0
		and coordinate.y < GRID_SIZE.y
	)


static func rect_for_coordinate(coordinate: Vector2i) -> Rect2:
	if not is_valid_coordinate(coordinate):
		return Rect2()
	return Rect2(
		GRID_ORIGIN + Vector2(coordinate) * CELL_SIZE,
		CELL_SIZE
	)


static func center_for_coordinate(coordinate: Vector2i) -> Vector2:
	if not is_valid_coordinate(coordinate):
		return Vector2.INF
	return rect_for_coordinate(coordinate).get_center()


static func coordinate_for_point(point: Vector2) -> Vector2i:
	if not grid_rect().has_point(point):
		return INVALID_COORDINATE
	var local := point - GRID_ORIGIN
	var coordinate := Vector2i(
		floori(local.x / CELL_SIZE.x),
		floori(local.y / CELL_SIZE.y)
	)
	return coordinate if is_valid_coordinate(coordinate) else INVALID_COORDINATE
