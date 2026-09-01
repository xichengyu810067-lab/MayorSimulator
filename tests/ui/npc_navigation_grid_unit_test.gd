extends SceneTree

const CityNavigationGridScript = preload("res://scripts/world/city_navigation_grid.gd")
const CityTerrainLayoutScript = preload("res://data/catalogs/city_terrain_layout.gd")
const SquareGridLayoutScript = preload("res://scripts/world/square_grid_layout.gd")
const SAMPLE_STEP := 4.0

var _failed := false
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var navigation = CityNavigationGridScript.new()
	_check(navigation.stage_size() == Vector2(1120, 820), "stage size is not 1120x820")
	_check(is_equal_approx(navigation.grid_cell_size(), 10.0), "AStar grid cell size is not 10 px")
	_check(is_equal_approx(navigation.foot_radius(), 9.0), "default foot radius changed")

	_validate_square_layout_terrain(navigation)
	_validate_foot_radius_inflation(navigation)
	_validate_dynamic_replanning(navigation)
	_validate_corner_safety(navigation)
	_validate_nearest_and_no_route(navigation)
	_validate_debug_contract(navigation)

	if _failed:
		quit(1)
	else:
		print("NPC navigation grid unit test passed. Checks=%d StaticPolygons=%d" % [
			_checks,
			navigation.get_debug_static_polygons().size(),
		])
		quit(0)


func _validate_square_layout_terrain(navigation) -> void:
	var blocked_count := 0
	for tile_id in CityTerrainLayoutScript.CELL_COUNT:
		var model := CityTerrainLayoutScript.model_for_tile_id(tile_id)
		var center := Vector2(model.get("plot_center", Vector2.INF))
		var blocked := CityTerrainLayoutScript.is_blocked_tile_id(tile_id)
		_check(center != Vector2.INF, "layout 3 tile %d lacks a square center" % tile_id)
		_check(navigation.is_position_walkable(center) != blocked, "layout 3 tile %d walkability disagrees with its frozen terrain kind" % tile_id)
		var classifications: PackedStringArray = navigation.static_classification_at(center)
		if blocked:
			blocked_count += 1
			_check(classifications.has(str(model.get("kind", ""))), "layout 3 tile %d lacks its frozen static classification" % tile_id)
		else:
			_check(classifications.is_empty(), "flat layout 3 tile %d inherited non-square scenery" % tile_id)
	_check(blocked_count == 32, "frozen layout 3 static blocker count changed")


func _validate_landmarks(navigation) -> void:
	_assert_landmark(navigation, Vector2(650, 260), "river_lake", "lake")
	_assert_landmark(navigation, Vector2(835, 100), "river_lake", "river")
	_assert_landmark(navigation, Vector2(250, 120), "hill_cliff", "northwest hill")
	_assert_landmark(navigation, Vector2(960, 130), "hill_cliff", "northeast cliff")
	_assert_landmark(navigation, Vector2(55, 470), "trees_scenery", "west forest")
	_assert_landmark(navigation, Vector2(520, 760), "trees_scenery", "south forest")
	_assert_landmark(navigation, Vector2(725, 640), "trees_scenery", "meadow rocks")
	_assert_landmark(navigation, Vector2(150, 570), "trees_scenery", "west lower tree grove")
	_assert_landmark(navigation, Vector2(815, 625), "trees_scenery", "south meadow tree grove")
	_assert_landmark(navigation, Vector2(930, 542), "trees_scenery", "east upper rock garden")
	_assert_landmark(navigation, Vector2(968, 581), "trees_scenery", "east lower rock garden")
	for meadow_point: Vector2 in [Vector2(320, 430), Vector2(560, 470), Vector2(900, 520)]:
		_check(navigation.is_position_walkable(meadow_point), "open meadow is blocked at %s" % meadow_point)
		_check(navigation.static_classification_at(meadow_point).is_empty(), "open meadow was classified as scenery at %s" % meadow_point)


func _validate_isolated_scenery_routes(navigation) -> void:
	# The centers prove that the newly inventoried scenery cannot be crossed.
	# The paired shoulder points and detours prove that the masks do not swallow
	# either the tan road or the open-grass bypass beside each small island.
	var expected_islands := {
		"west_lower_tree_grove": Vector2(150, 570),
		"south_meadow_tree_grove": Vector2(815, 625),
		"east_path_rock_garden_upper": Vector2(930, 542),
		"east_path_rock_garden_lower": Vector2(968, 581),
	}
	var records_by_id := {}
	for record: Dictionary in navigation.get_debug_static_polygons():
		records_by_id[str(record.get("id", ""))] = record
	for island_id: String in expected_islands:
		_check(records_by_id.has(island_id), "static debug records omit %s" % island_id)
		if not records_by_id.has(island_id):
			continue
		var center: Vector2 = expected_islands[island_id]
		var points: PackedVector2Array = records_by_id[island_id].get(
			"points", PackedVector2Array()
		)
		_check(
			Geometry2D.is_point_in_polygon(center, points),
			"%s does not contain its audited scenery center %s" % [island_id, center]
		)
	for shoulder: Vector2 in [
		Vector2(220, 540), Vector2(220, 625),
		Vector2(725, 570), Vector2(900, 650),
		Vector2(880, 540), Vector2(986, 535),
		Vector2(925, 590), Vector2(1005, 605),
	]:
		_check(navigation.is_position_walkable(shoulder), "isolated scenery overblocked a nearby lane at %s" % shoulder)
		_check(
			navigation.static_classification_at(shoulder).is_empty(),
			"isolated scenery classified a nearby lane at %s" % shoulder
		)

	_assert_detour(
		navigation,
		Vector2(145, 475),
		Vector2(215, 635),
		"west lower tree grove"
	)
	_assert_detour(
		navigation,
		Vector2(735, 565),
		Vector2(895, 655),
		"south meadow tree grove"
	)
	_assert_detour(
		navigation,
		Vector2(880, 520),
		Vector2(986, 535),
		"east upper rock garden"
	)
	_assert_detour(
		navigation,
		Vector2(925, 575),
		Vector2(1005, 605),
		"east lower rock garden"
	)
	var east_road_path: PackedVector2Array = navigation.find_path(
		Vector2(885, 455),
		Vector2(1010, 650),
		false
	)
	_assert_safe_path(
		navigation,
		east_road_path,
		Vector2(885, 455),
		Vector2(1010, 650),
		"east dirt road remains connected"
	)


func _validate_foot_radius_inflation(navigation) -> void:
	var center := Vector2(550, 500)
	var just_outside_diamond := Vector2(622, 500)
	navigation.set_building_blocker(9, center)
	_check(not navigation.is_position_walkable(just_outside_diamond), "9px foot radius did not inflate a building footprint")
	navigation.set_building_blocker(9, center, false)
	_check(navigation.is_position_walkable(just_outside_diamond), "removing the inflated building footprint did not restore the point")
	var zero_radius_navigation = CityNavigationGridScript.new(0.0)
	zero_radius_navigation.set_building_blocker(9, center)
	_check(zero_radius_navigation.is_position_walkable(just_outside_diamond), "zero-radius control unexpectedly inflated the building footprint")


func _validate_static_detours(navigation) -> void:
	_assert_detour(
		navigation,
		Vector2(400, 290),
		Vector2(870, 250),
		"river/lake"
	)
	_assert_detour(
		navigation,
		Vector2(145, 420),
		Vector2(260, 300),
		"hill/cliff"
	)
	_assert_detour(
		navigation,
		Vector2(600, 640),
		Vector2(900, 650),
		"trees/scenery"
	)


func _validate_dynamic_replanning(navigation) -> void:
	var start := Vector2(300, 500)
	var target := Vector2(800, 500)
	var baseline: PackedVector2Array = navigation.find_path(start, target, false)
	_assert_safe_path(navigation, baseline, start, target, "baseline meadow")
	var baseline_length := _path_length(baseline)

	navigation.set_building_blocker(27, Vector2(550, 500))
	_check(not navigation.is_position_walkable(Vector2(550, 500)), "building center remained walkable")
	var building_path: PackedVector2Array = navigation.find_path(start, target, false)
	_assert_safe_path(navigation, building_path, start, target, "building detour")
	_check(_path_length(building_path) > baseline_length + 5.0, "building did not force a meaningful detour")
	_check(str(navigation.get_last_query_diagnostics().get("status", "")) == "ok", "building replan diagnostics are not ok")

	navigation.set_building_blocker(27, Vector2(550, 500), false)
	navigation.set_construction_blocker(27, Vector2(550, 500))
	var construction_path: PackedVector2Array = navigation.find_path(start, target, false)
	_assert_safe_path(navigation, construction_path, start, target, "construction detour")
	_check(_path_length(construction_path) > baseline_length + 5.0, "construction did not block the tile")
	var dynamic_records: Array[Dictionary] = navigation.get_debug_dynamic_polygons()
	_check(dynamic_records.size() == 1, "construction blocker debug record count is wrong")
	if dynamic_records.size() == 1:
		_check(str(dynamic_records[0].get("kind", "")) == "construction", "construction blocker kind is missing")

	navigation.set_construction_blocker(27, Vector2(550, 500), false)
	var restored_path: PackedVector2Array = navigation.find_path(start, target, false)
	_assert_safe_path(navigation, restored_path, start, target, "demolition restoration")
	_check(absf(_path_length(restored_path) - baseline_length) <= 0.01, "removing the blocker did not restore the original route")

	navigation.sync_dynamic_tile_blockers(
		{27: Vector2(550, 500)},
		{28: Vector2(680, 500)}
	)
	var batched_records: Array[Dictionary] = navigation.get_debug_dynamic_polygons()
	_check(batched_records.size() == 2, "batched dynamic tile sync did not replace both blocker sets")
	navigation.sync_dynamic_tile_blockers({}, {})
	_check(navigation.get_debug_dynamic_polygons().is_empty(), "empty batched sync did not clear stale city blockers")


func _validate_corner_safety(navigation) -> void:
	navigation.clear_dynamic_blockers()
	navigation.set_dynamic_diamond("corner:east", Vector2(520, 500), Vector2(14, 14), true, "test")
	navigation.set_dynamic_diamond("corner:south", Vector2(500, 520), Vector2(14, 14), true, "test")
	var start := Vector2(455, 455)
	var target := Vector2(555, 555)
	_check(not navigation.is_segment_walkable(start, target), "corner fixture did not block the direct diagonal")
	var path: PackedVector2Array = navigation.find_path(start, target, false)
	_assert_safe_path(navigation, path, start, target, "corner-cut prevention")
	_check(path.size() >= 3, "corner obstacles were incorrectly collapsed to a direct diagonal")
	navigation.clear_dynamic_blockers()


func _validate_nearest_and_no_route(navigation) -> void:
	var unsafe_lake_point := SquareGridLayoutScript.center_for_coordinate(Vector2i(1, 1))
	var nearest_variant: Variant = navigation.nearest_safe_position(unsafe_lake_point, 160.0)
	_check(nearest_variant != null, "nearest-safe lookup failed near the lake")
	if nearest_variant != null:
		var nearest: Vector2 = nearest_variant
		_check(navigation.is_position_walkable(nearest), "nearest-safe lookup returned a blocked point")
		_check(nearest.distance_to(unsafe_lake_point) <= 160.0, "nearest-safe lookup exceeded its search radius")
	_check(navigation.nearest_safe_position(unsafe_lake_point, 5.0) == null, "nearest-safe ignored a strict search radius")

	navigation.set_dynamic_diamond(
		"test:stage_barrier",
		Vector2(560, 410),
		Vector2(12, 500),
		true,
		"test"
	)
	var no_route: PackedVector2Array = navigation.find_path(Vector2(300, 500), Vector2(800, 500), false)
	_check(no_route.is_empty(), "a full-height barrier still returned a route")
	_check(str(navigation.get_last_query_diagnostics().get("status", "")) == "no_route", "no-route diagnostics status is missing")
	navigation.clear_dynamic_blockers()


func _validate_debug_contract(navigation) -> void:
	var static_polygons: Array[Dictionary] = navigation.get_debug_static_polygons()
	_check(static_polygons.size() >= 10, "static debug polygons are incomplete")
	var found_kinds := {}
	for record: Dictionary in static_polygons:
		_check(record.has("id") and record.has("kind") and record.has("points"), "static debug record shape is incomplete")
		_check((record.get("points", PackedVector2Array()) as PackedVector2Array).size() >= 3, "static debug polygon has fewer than three points")
		found_kinds[str(record.get("kind", ""))] = true
	for required_kind: String in ["river_lake", "hill_cliff", "trees_scenery"]:
		_check(found_kinds.has(required_kind), "static debug polygons omit %s" % required_kind)
	var blocked_points: Array[Dictionary] = navigation.get_debug_points(false)
	_check(not blocked_points.is_empty(), "blocked debug point API returned nothing")
	if not blocked_points.is_empty():
		var record: Dictionary = blocked_points[0]
		for key: String in ["id", "position", "walkable", "static_kinds", "dynamic_ids"]:
			_check(record.has(key), "debug point record omits %s" % key)
	var snapshot: Dictionary = navigation.get_debug_snapshot(false)
	for key: String in ["stage_size", "grid_cell_size", "grid_size", "foot_radius", "static_polygons", "dynamic_polygons", "points", "raw_path", "path", "query"]:
		_check(snapshot.has(key), "debug snapshot omits %s" % key)


func _assert_landmark(navigation, point: Vector2, expected_kind: String, label: String) -> void:
	_check(not navigation.is_position_walkable(point), "%s landmark remained walkable at %s" % [label, point])
	var classifications: PackedStringArray = navigation.static_classification_at(point)
	_check(classifications.has(expected_kind), "%s landmark lacks %s classification: %s" % [label, expected_kind, classifications])


func _assert_detour(navigation, start: Vector2, target: Vector2, label: String) -> void:
	_check(navigation.is_position_walkable(start), "%s start is blocked: %s" % [label, start])
	_check(navigation.is_position_walkable(target), "%s target is blocked: %s" % [label, target])
	_check(not navigation.is_segment_walkable(start, target), "%s fixture does not cross its static obstacle" % label)
	var path: PackedVector2Array = navigation.find_path(start, target, false)
	_assert_safe_path(navigation, path, start, target, "%s detour" % label)
	_check(path.size() >= 3, "%s path did not retain an obstacle-avoiding turn" % label)
	_check(_path_length(path) > start.distance_to(target) + 0.01, "%s path did not detour" % label)


func _assert_safe_path(
	navigation,
	path: PackedVector2Array,
	expected_start: Vector2,
	expected_target: Vector2,
	label: String
) -> void:
	_check(not path.is_empty(), "%s returned no path; diagnostics=%s" % [label, navigation.get_last_query_diagnostics()])
	if path.is_empty():
		return
	_check(path[0].is_equal_approx(expected_start), "%s changed its safe start point" % label)
	_check(path[path.size() - 1].is_equal_approx(expected_target), "%s changed its safe target point" % label)
	for point_index in range(1, path.size()):
		var from_point := path[point_index - 1]
		var to_point := path[point_index]
		_check(navigation.is_segment_walkable(from_point, to_point), "%s contains an unsafe smoothed segment %s -> %s" % [label, from_point, to_point])
		var sample_count := maxi(1, ceili(from_point.distance_to(to_point) / SAMPLE_STEP))
		for sample_index in range(sample_count + 1):
			var sample := from_point.lerp(to_point, float(sample_index) / float(sample_count))
			_check(navigation.is_position_walkable(sample), "%s 4px sample entered an obstacle at %s" % [label, sample])


func _path_length(path: PackedVector2Array) -> float:
	var length := 0.0
	for point_index in range(1, path.size()):
		length += path[point_index - 1].distance_to(path[point_index])
	return length


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("NPC navigation grid unit test failed: %s" % message)
