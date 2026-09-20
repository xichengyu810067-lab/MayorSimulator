class_name BuildingTerrainLabels
extends RefCounted

## Human-reviewed building placement labels for the stable 10x10 city grid.
##
## These labels are intentionally independent from CityTerrainMap's historical
## backdrop classifier and flattening state.  The source review covered every
## tile.  The final review kept 50 and 71 blocked, and changed 32, 48, 64, 78,
## 88, and 96 to buildable candidates.

const CELL_COUNT := 100

const BLOCKED_TILE_IDS := [
	0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
	10, 11, 12, 13, 14, 19, 20,
	50, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
	65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77,
	84, 86, 87, 89, 90, 91, 92, 93, 94, 95, 97, 98, 99,
]


static func is_buildable(tile_id: int) -> bool:
	return tile_id >= 0 and tile_id < CELL_COUNT and not BLOCKED_TILE_IDS.has(tile_id)


static func is_blocked(tile_id: int) -> bool:
	return tile_id >= 0 and tile_id < CELL_COUNT and BLOCKED_TILE_IDS.has(tile_id)


static func blocked_tile_ids() -> Array[int]:
	var result: Array[int] = []
	for tile_id: int in BLOCKED_TILE_IDS:
		result.append(tile_id)
	return result
