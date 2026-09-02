extends SceneTree

const SquareGridLayoutScript = preload("res://scripts/world/square_grid_layout.gd")
const CityTerrainMapScript = preload("res://scripts/world/city_terrain_map.gd")
const CityTerrainLayoutScript = preload("res://data/catalogs/city_terrain_layout.gd")
const CityBackdropScript = preload("res://scripts/world/city_backdrop.gd")

var _failed := false
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var terrain = CityTerrainMapScript.new()
	terrain.apply_default_city_layout()
	_check(terrain.grid_size() == SquareGridLayoutScript.GRID_SIZE, "logical and visual grid dimensions diverged")
	_check(terrain.cell_count() == 100, "stable terrain tile count changed")
	_check(SquareGridLayoutScript.CELL_SIZE.x == SquareGridLayoutScript.CELL_SIZE.y, "grid cells are not square")

	var seen_tile_ids: Dictionary = {}
	var terrain_kind_counts := {"flat_grass": 0, "river_lake": 0, "hill_cliff": 0, "trees": 0}
	for row in SquareGridLayoutScript.GRID_SIZE.y:
		for column in SquareGridLayoutScript.GRID_SIZE.x:
			var coordinate := Vector2i(column, row)
			var rect := SquareGridLayoutScript.rect_for_coordinate(coordinate)
			var center := SquareGridLayoutScript.center_for_coordinate(coordinate)
			var tile_id := terrain.tile_id_for_coordinate(coordinate)
			_check(rect.size == SquareGridLayoutScript.CELL_SIZE, "cell %s has non-canonical dimensions" % coordinate)
			_check(rect.get_center().is_equal_approx(center), "cell %s rect and center disagree" % coordinate)
			_check(SquareGridLayoutScript.coordinate_for_point(center) == coordinate, "cell %s center did not round-trip" % coordinate)
			_check(tile_id >= 0 and tile_id < terrain.cell_count(), "cell %s lost its stable tile id" % coordinate)
			_check(not seen_tile_ids.has(tile_id), "tile id %d is assigned to multiple coordinates" % tile_id)
			seen_tile_ids[tile_id] = true
			var frozen_model := CityTerrainLayoutScript.model_for_tile_id(tile_id)
			var terrain_kind := CityTerrainLayoutScript.terrain_kind_for_tile_id(tile_id)
			_check(Vector2(frozen_model.get("plot_center", Vector2.INF)).is_equal_approx(center), "tile %d terrain provenance uses a non-square center" % tile_id)
			_check(terrain.base_kind(tile_id) == terrain_kind, "tile %d changed its frozen layout 3 terrain kind" % tile_id)
			terrain_kind_counts[terrain_kind] = int(terrain_kind_counts.get(terrain_kind, 0)) + 1

	_check(seen_tile_ids.size() == 100, "square projection does not cover all 100 stable tile ids")
	_check(terrain.coordinate_for_tile_id(0) == Vector2i(1, 1), "legacy tile 0 coordinate changed")
	_check(terrain.coordinate_for_tile_id(64) == Vector2i(0, 0), "outer-ring tile 64 coordinate changed")
	_check(terrain_kind_counts == {"flat_grass": 68, "river_lake": 14, "hill_cliff": 5, "trees": 13}, "frozen layout 3 terrain distribution changed: %s" % terrain_kind_counts)
	_check(is_equal_approx(float(CityTerrainLayoutScript.model_for_tile_id(0).get("coverage", -1.0)), 0.623264041608023), "tile 0 frozen coverage changed")
	_check(Array(CityTerrainLayoutScript.model_for_tile_id(85).get("feature_ids", [])) == ["south_meadow_rocks", "south_meadow_tree_grove"], "tile 85 frozen provenance changed")
	_check(is_equal_approx(float(CityTerrainLayoutScript.model_for_tile_id(99).get("coverage", -1.0)), 0.986220065703554), "tile 99 frozen coverage changed")
	var bounds := SquareGridLayoutScript.grid_rect()
	for outside: Vector2 in [
		bounds.position - Vector2(0.01, 0.01),
		Vector2(bounds.end.x, bounds.position.y),
		Vector2(bounds.position.x, bounds.end.y),
		bounds.end + Vector2(0.01, 0.01),
	]:
		_check(
			SquareGridLayoutScript.coordinate_for_point(outside) == SquareGridLayoutScript.INVALID_COORDINATE,
			"out-of-grid point %s was accepted" % outside
		)

	var backdrop = CityBackdropScript.new()
	backdrop.size = SquareGridLayoutScript.STAGE_SIZE
	root.add_child(backdrop)
	await process_frame
	_check(backdrop.has_method("set_terrain_snapshot"), "visible backdrop has no terrain-authority projection input")
	if backdrop.has_method("set_terrain_snapshot"):
		backdrop.call("set_terrain_snapshot", terrain.to_dict())
	var backdrop_debug: Dictionary = backdrop.call("debug_terrain_projection") if backdrop.has_method("debug_terrain_projection") else {}
	_check(int(backdrop_debug.get("tile_count", 0)) == 100, "visible substrate does not project all 100 terrain-authority tiles")
	_check(str(backdrop_debug.get("projection", "")) == "SquareGridLayout", "visible substrate is not bound to SquareGridLayout")
	_check(backdrop.has_method("debug_render_order"), "visible substrate exposes no render-order debug contract")
	if backdrop.has_method("debug_render_order"):
		var render_order: Dictionary = backdrop.call("debug_render_order")
		_check(bool(render_order.get("background_texture_present", false)), "natural background texture is absent")
		_check(bool(render_order.get("background_texture_visible_in_tree", false)), "natural background texture is not visible in the active canvas tree")
		_check(int(render_order.get("background_texture_z_index", -1)) == 0, "natural background texture is rendered behind the root background")
		_check(Rect2(render_order.get("background_texture_rect", Rect2())).size.is_equal_approx(backdrop.size), "natural background texture does not cover the backdrop")
	var visual_policy: Dictionary = backdrop_debug.get("visual_policy", {})
	_check(str(visual_policy.get("base_asset", "")) == "city-map-background.png", "visible substrate does not retain the natural city map as its base asset")
	_check(bool(visual_policy.get("background_primary", false)), "terrain hints replace the natural city map instead of remaining overlays")
	_check(is_zero_approx(float(visual_policy.get("flat_grass_fill_alpha", -1.0))), "flat grass still receives an artificial solid fill")
	_check(is_zero_approx(float(visual_policy.get("non_flat_fill_max_alpha", -1.0))), "non-flat terrain still receives an artificial persistent fill")
	_check(not bool(visual_policy.get("persistent_terrain_overlay", true)), "backdrop still draws persistent per-cell terrain decoration")
	_check(str(visual_policy.get("interactive_grid_owner", "")) == "CityTileButton", "interactive grid ownership is not assigned to CityTileButton")
	var projected_tiles: Dictionary = backdrop_debug.get("tiles", {})
	var lake_tile_id := terrain.tile_id_for_coordinate(Vector2i(1, 1))
	var lake_projection: Dictionary = projected_tiles.get(str(lake_tile_id), {})
	_check(str(lake_projection.get("terrain_kind", "")) == "river_lake", "visible substrate disagrees with CityTerrainMap at the frozen lake tile")
	_check(Rect2(lake_projection.get("rect", Rect2())).is_equal_approx(SquareGridLayoutScript.rect_for_coordinate(Vector2i(1, 1))), "visible lake substrate does not use canonical square bounds")
	backdrop.queue_free()
	await process_frame

	if _failed:
		quit(1)
	else:
		print("Square grid layout test passed. Checks=%d Cells=100" % _checks)
		quit(0)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Square grid layout test failed: %s" % message)
