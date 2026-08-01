extends SceneTree

const CityTerrainMapScript = preload("res://scripts/world/city_terrain_map.gd")

var _failed := false
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var terrain = CityTerrainMapScript.new()
	_check(terrain.grid_size() == Vector2i(10, 10), "terrain grid is not 10x10")
	_check(terrain.cell_count() == 100, "terrain grid does not expose 100 logical tiles")
	_check(terrain.coordinate_for_tile_id(0) == Vector2i(1, 1), "legacy tile 0 moved")
	_check(terrain.coordinate_for_tile_id(7) == Vector2i(8, 1), "legacy tile 7 moved")
	_check(terrain.coordinate_for_tile_id(8) == Vector2i(1, 2), "legacy tile 8 moved")
	_check(terrain.coordinate_for_tile_id(63) == Vector2i(8, 8), "legacy tile 63 moved")
	_check(terrain.coordinate_for_tile_id(64) == Vector2i(0, 0), "outer-ring tile 64 is unstable")
	_check(terrain.coordinate_for_tile_id(73) == Vector2i(9, 0), "outer-ring top-right id is unstable")
	_check(terrain.coordinate_for_tile_id(74) == Vector2i(0, 1), "outer-ring left id is unstable")
	_check(terrain.coordinate_for_tile_id(75) == Vector2i(9, 1), "outer-ring right id is unstable")
	_check(terrain.coordinate_for_tile_id(90) == Vector2i(0, 9), "outer-ring bottom-left id is unstable")
	_check(terrain.coordinate_for_tile_id(99) == Vector2i(9, 9), "outer-ring tile 99 is unstable")

	var seen_coordinates: Dictionary = {}
	for tile_id in range(terrain.cell_count()):
		var coordinate: Vector2i = terrain.coordinate_for_tile_id(tile_id)
		_check(not seen_coordinates.has(coordinate), "duplicate coordinate %s" % coordinate)
		seen_coordinates[coordinate] = true
		_check(terrain.tile_id_for_coordinate(coordinate) == tile_id, "tile/coordinate round trip failed for %d" % tile_id)
	_check(seen_coordinates.size() == 100, "coordinate map does not cover all 100 cells")
	_check(terrain.tile_ids_in_display_order()[0] == 64, "display order does not start at coordinate (0,0)")
	_check(terrain.tile_id_for_coordinate(Vector2i(1, 1)) == 0, "legacy center coordinate no longer resolves to tile 0")

	var expected_kinds := PackedStringArray([
		"flat_grass", "trees", "hill_cliff", "river_lake", "road_path", "rail_track"
	])
	for kind: String in expected_kinds:
		_check(terrain.terrain_kinds().has(kind), "terrain catalog omits %s" % kind)

	for fixture: Dictionary in [
		{"tile": 0, "kind": "trees"},
		{"tile": 1, "kind": "hill_cliff"},
		{"tile": 2, "kind": "river_lake"},
		{"tile": 3, "kind": "road_path"},
		{"tile": 4, "kind": "rail_track"},
	]:
		var tile_id := int(fixture["tile"])
		_check(terrain.set_tile_kind(tile_id, str(fixture["kind"])), "could not configure terrain fixture")
		_check(not terrain.is_buildable(tile_id), "%s terrain is buildable before flattening" % fixture["kind"])
		_check(not terrain.is_walkable(tile_id), "%s terrain is walkable before flattening" % fixture["kind"])
		_check(terrain.is_flattenable(tile_id), "%s terrain is not flattenable" % fixture["kind"])

	var flattened: Dictionary = terrain.flatten_tile(0)
	_check(bool(flattened.get("ok", false)) and bool(flattened.get("changed", false)), "tree tile did not flatten")
	_check(terrain.base_kind(0) == "trees", "flattening destroyed the authored base terrain")
	_check(terrain.effective_kind(0) == "flat_grass", "flattening did not resolve to flat grass")
	_check(terrain.is_buildable(0) and terrain.is_walkable(0), "flattened tile did not become buildable/walkable")
	_check(not terrain.is_flattenable(0), "already flattened tile remains flattenable")
	_check(terrain.restore_base_terrain(0), "base terrain could not be restored")
	_check(not terrain.is_walkable(0) and terrain.effective_kind(0) == "trees", "restoring base terrain did not restore its blocker")
	_check(bool(terrain.flatten_tile(5).get("ok", false)) and not bool(terrain.flatten_tile(5).get("changed", true)), "flat grass flatten is not idempotent")
	_check(not terrain.set_tile_kind(5, "lava"), "unknown terrain kind was accepted")
	_check(not bool(terrain.flatten_tile(100).get("ok", true)), "out-of-range tile flattened")

	terrain.flatten_tile(0)
	var serialized: Dictionary = terrain.to_dict()
	var restored = CityTerrainMapScript.create_from_dict(serialized)
	_check(restored.coordinate_for_tile_id(63) == Vector2i(8, 8), "serialization changed legacy mapping")
	_check(restored.base_kind(0) == "trees" and restored.is_flattened(0), "flattened terrain did not round-trip")
	_check(restored.effective_kind(3) == "road_path" and not restored.is_walkable(3), "road blocker did not round-trip")
	_check(restored.effective_kind(4) == "rail_track" and not restored.is_walkable(4), "rail blocker did not round-trip")

	var compact = CityTerrainMapScript.create_from_dict({
		"terrain_by_tile": {
			"64": {"base_kind": "river_lake", "flattened": false},
			"65": {"base_kind": "rail_track", "flattened": true},
			"66": {"base_kind": "unknown", "flattened": true},
		}
	})
	_check(compact.effective_kind(64) == "river_lake", "compact river state did not load")
	_check(compact.effective_kind(65) == "flat_grass" and compact.base_kind(65) == "rail_track", "compact flattened rail did not load")
	_check(compact.effective_kind(66) == "flat_grass", "invalid compact terrain did not retain safe default")

	var centers := PackedVector2Array()
	centers.resize(100)
	for tile_id in range(100):
		centers[tile_id] = Vector2(200 + tile_id, 400)
	var blockers: Dictionary = restored.navigation_blockers(centers)
	_check(blockers.has(3) and str(blockers[3].get("kind", "")) == "road_path", "road navigation blocker is missing")
	_check(blockers.has(4) and str(blockers[4].get("kind", "")) == "rail_track", "rail navigation blocker is missing")
	_check(not blockers.has(0), "flattened tree still emits a navigation blocker")

	if not _failed:
		print("City terrain map unit test passed. Checks=%d Cells=100 Legacy=64 OuterRing=36" % _checks)
	quit(1 if _failed else 0)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("City terrain map unit test failed: %s" % message)
