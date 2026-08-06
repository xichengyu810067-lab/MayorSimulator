class_name CityNavigationGrid
extends RefCounted

## Deterministic, stage-local navigation for the fixed 1120x820 city map.
##
## The navigation grid deliberately does not depend on Control/global canvas
## transforms.  Callers keep NPC foot positions in map_stage local space and
## convert only when rendering.  Static polygons describe the non-walkable
## scenery in city-map-background.png after its keep-aspect-covered crop.

const STAGE_SIZE := Vector2(1120.0, 820.0)
const BACKDROP_ASSET_PATH := "res://assets/images/world/backgrounds/city-map-background.png"
const BACKDROP_ISO_TILE_STEP := Vector2(56.0, 32.0)
const BACKDROP_ISO_MAP_ORIGIN := Vector2(560.0, 104.0)
const BACKDROP_TILE_FOOT_OFFSET_Y := 34.0
const BACKDROP_PLOT_HALF_EXTENTS := Vector2(49.0, 29.0)
const BACKDROP_MIN_PLOT_COVERAGE := 0.035
const GRID_CELL_SIZE := 10.0
const GRID_SIZE := Vector2i(112, 82)
const DEFAULT_FOOT_RADIUS := 9.0
const DEFAULT_DYNAMIC_HALF_EXTENTS := Vector2(64.0, 40.0)
const STRING_PULL_SAMPLE_STEP := 4.0

const KIND_RIVER_LAKE := "river_lake"
const KIND_HILL_CLIFF := "hill_cliff"
const KIND_TREES_SCENERY := "trees_scenery"

var _astar := AStarGrid2D.new()
var _foot_radius := DEFAULT_FOOT_RADIUS
var _static_polygons: Array[Dictionary] = []
var _dynamic_blockers: Dictionary = {}
var _flattened_terrain_apertures: Dictionary = {}
var _transport_crossing_apertures: Dictionary = {}
var _static_solid := PackedByteArray()
var _last_raw_path := PackedVector2Array()
var _last_path := PackedVector2Array()
var _last_query_diagnostics: Dictionary = {}


func _init(foot_radius: float = DEFAULT_FOOT_RADIUS) -> void:
	_foot_radius = maxf(0.0, foot_radius)
	_static_polygons = _create_static_polygons()
	_configure_astar()
	_rebuild_static_solidity()
	_refresh_grid_solidity()
	_reset_query_diagnostics()


func stage_size() -> Vector2:
	return STAGE_SIZE


func grid_cell_size() -> float:
	return GRID_CELL_SIZE


func foot_radius() -> float:
	return _foot_radius


func is_position_walkable(position: Vector2) -> bool:
	if not _inside_stage_with_clearance(position):
		return false
	if _point_blocked_by_static(position):
		return false
	for blocker_variant: Variant in _dynamic_blockers.values():
		var blocker: Dictionary = blocker_variant
		if _blocker_has_open_transport_aperture(blocker):
			continue
		if _point_touches_polygon(position, blocker["points"], _foot_radius):
			return false
	return true


func is_segment_walkable(from_position: Vector2, to_position: Vector2) -> bool:
	var distance := from_position.distance_to(to_position)
	var sample_count := maxi(1, ceili(distance / STRING_PULL_SAMPLE_STEP))
	for sample_index in range(sample_count + 1):
		var sample_position := from_position.lerp(
			to_position,
			float(sample_index) / float(sample_count)
		)
		if not is_position_walkable(sample_position):
			return false
	return true


func static_classification_at(position: Vector2) -> PackedStringArray:
	var kinds := PackedStringArray()
	if not _inside_stage_with_clearance(position):
		kinds.append("outside_stage")
	for polygon_data: Dictionary in _static_polygons:
		if _point_touches_polygon(position, polygon_data["points"], _foot_radius):
			var kind := str(polygon_data.get("kind", "scenery"))
			if not kinds.has(kind):
				kinds.append(kind)
	return kinds


## The backdrop polygons are the single terrain source for both plot legality
## and NPC navigation. They model scenery painted into the original image.
static func backdrop_terrain_for_coordinate(coordinate: Vector2i) -> Dictionary:
	return backdrop_terrain_for_plot(
		backdrop_tile_center(coordinate), BACKDROP_PLOT_HALF_EXTENTS
	)


static func backdrop_tile_center(coordinate: Vector2i) -> Vector2:
	return Vector2(
		BACKDROP_ISO_MAP_ORIGIN.x + float(coordinate.x - coordinate.y) * BACKDROP_ISO_TILE_STEP.x,
		BACKDROP_ISO_MAP_ORIGIN.y + float(coordinate.x + coordinate.y) * BACKDROP_ISO_TILE_STEP.y + BACKDROP_TILE_FOOT_OFFSET_Y
	)


static func backdrop_terrain_for_plot(center: Vector2, half_extents: Vector2) -> Dictionary:
	var plot := _diamond_points(center, half_extents)
	var plot_area := maxf(1.0, _polygon_area(plot))
	var coverage_by_kind: Dictionary = {}
	var feature_ids_by_kind: Dictionary = {}
	for polygon_data: Dictionary in _create_static_polygons():
		var overlap_area := 0.0
		for intersection: PackedVector2Array in Geometry2D.intersect_polygons(
			plot, PackedVector2Array(polygon_data["points"])
		):
			overlap_area += _polygon_area(intersection)
		var coverage := overlap_area / plot_area
		if coverage < BACKDROP_MIN_PLOT_COVERAGE:
			continue
		var kind := str(polygon_data.get("kind", ""))
		coverage_by_kind[kind] = float(coverage_by_kind.get(kind, 0.0)) + coverage
		var ids: Array = Array(feature_ids_by_kind.get(kind, [])).duplicate()
		ids.append(str(polygon_data.get("id", "")))
		feature_ids_by_kind[kind] = ids
	var winning_kind := "flat_grass"
	var winning_coverage := 0.0
	for kind_variant: Variant in coverage_by_kind.keys():
		var kind := str(kind_variant)
		var coverage := float(coverage_by_kind[kind_variant])
		if coverage > winning_coverage:
			winning_kind = kind
			winning_coverage = coverage
	return {
		"kind": winning_kind,
		"coverage": winning_coverage,
		"feature_ids": Array(feature_ids_by_kind.get(winning_kind, [])).duplicate(),
		"source_asset": BACKDROP_ASSET_PATH,
		"plot_center": center,
		"plot_half_extents": half_extents,
	}


func nearest_safe_position(position: Vector2, max_search_distance: float = 160.0) -> Variant:
	var direct_id := _position_to_id(position)
	if (
		is_position_walkable(position)
		and _astar.is_in_boundsv(direct_id)
		and not _astar.is_point_solid(direct_id)
	):
		return position
	if max_search_distance < 0.0:
		return null

	var origin_id := Vector2i(
		clampi(direct_id.x, 0, GRID_SIZE.x - 1),
		clampi(direct_id.y, 0, GRID_SIZE.y - 1)
	)
	var search_cells := ceili(max_search_distance / GRID_CELL_SIZE)
	var best_position := Vector2.ZERO
	var best_distance_squared := INF
	for y in range(
		maxi(0, origin_id.y - search_cells),
		mini(GRID_SIZE.y, origin_id.y + search_cells + 1)
	):
		for x in range(
			maxi(0, origin_id.x - search_cells),
			mini(GRID_SIZE.x, origin_id.x + search_cells + 1)
		):
			var point_id := Vector2i(x, y)
			if _astar.is_point_solid(point_id):
				continue
			var candidate := _astar.get_point_position(point_id)
			var distance_squared := position.distance_squared_to(candidate)
			if distance_squared > max_search_distance * max_search_distance:
				continue
			if distance_squared < best_distance_squared and is_position_walkable(candidate):
				best_position = candidate
				best_distance_squared = distance_squared
	if best_distance_squared == INF:
		return null
	return best_position


func find_path(
	from_position: Vector2,
	to_position: Vector2,
	snap_to_nearest: bool = true
) -> PackedVector2Array:
	_last_raw_path = PackedVector2Array()
	_last_path = PackedVector2Array()
	_last_query_diagnostics = {
		"status": "querying",
		"requested_start": from_position,
		"requested_target": to_position,
		"resolved_start": Vector2.ZERO,
		"resolved_target": Vector2.ZERO,
		"raw_point_count": 0,
		"smoothed_point_count": 0,
		"path_length": 0.0,
	}

	var resolved_start_variant: Variant = _resolve_endpoint(from_position, snap_to_nearest)
	if resolved_start_variant == null:
		_last_query_diagnostics["status"] = "no_safe_start"
		return PackedVector2Array()
	var resolved_target_variant: Variant = _resolve_endpoint(to_position, snap_to_nearest)
	if resolved_target_variant == null:
		_last_query_diagnostics["status"] = "no_safe_target"
		return PackedVector2Array()

	var resolved_start: Vector2 = resolved_start_variant
	var resolved_target: Vector2 = resolved_target_variant
	_last_query_diagnostics["resolved_start"] = resolved_start
	_last_query_diagnostics["resolved_target"] = resolved_target

	var start_id := _position_to_id(resolved_start)
	var target_id := _position_to_id(resolved_target)
	if (
		not _astar.is_in_boundsv(start_id)
		or not _astar.is_in_boundsv(target_id)
		or _astar.is_point_solid(start_id)
		or _astar.is_point_solid(target_id)
	):
		_last_query_diagnostics["status"] = "no_route"
		return PackedVector2Array()

	var astar_path := _astar.get_point_path(start_id, target_id, false)
	if astar_path.is_empty():
		_last_query_diagnostics["status"] = "no_route"
		return PackedVector2Array()

	var raw_path := PackedVector2Array()
	_append_unique_point(raw_path, resolved_start)
	for point: Vector2 in astar_path:
		_append_unique_point(raw_path, point)
	_append_unique_point(raw_path, resolved_target)
	_last_raw_path = raw_path.duplicate()
	_last_query_diagnostics["raw_point_count"] = raw_path.size()

	var smoothed_path := _string_pull_path(raw_path)
	if smoothed_path.is_empty():
		_last_query_diagnostics["status"] = "no_route"
		return PackedVector2Array()

	_last_path = smoothed_path.duplicate()
	_last_query_diagnostics["status"] = "ok"
	_last_query_diagnostics["smoothed_point_count"] = smoothed_path.size()
	_last_query_diagnostics["path_length"] = _path_length(smoothed_path)
	return smoothed_path


func set_building_blocker(
	tile_index: int,
	center: Vector2,
	enabled: bool = true,
	half_extents: Vector2 = DEFAULT_DYNAMIC_HALF_EXTENTS
) -> void:
	set_dynamic_diamond(
		"building:%d" % tile_index,
		center,
		half_extents,
		enabled,
		"building",
		tile_index,
		"building"
	)


func set_construction_blocker(
	tile_index: int,
	center: Vector2,
	enabled: bool = true,
	half_extents: Vector2 = DEFAULT_DYNAMIC_HALF_EXTENTS
) -> void:
	set_dynamic_diamond(
		"construction:%d" % tile_index,
		center,
		half_extents,
		enabled,
		"construction",
		tile_index,
		"construction"
	)


func set_terrain_blocker(
	tile_index: int,
	center: Vector2,
	terrain_kind: String,
	enabled: bool = true,
	half_extents: Vector2 = DEFAULT_DYNAMIC_HALF_EXTENTS
) -> void:
	set_dynamic_diamond(
		"terrain:%d" % tile_index,
		center,
		half_extents,
		enabled,
		terrain_kind if not terrain_kind.is_empty() else "terrain",
		tile_index,
		"terrain"
	)


func sync_dynamic_tile_blockers(
	building_centers: Dictionary,
	construction_centers: Dictionary,
	half_extents: Vector2 = DEFAULT_DYNAMIC_HALF_EXTENTS
) -> void:
	# Replace only city-tile blockers.  Custom diagnostic or gameplay blockers
	# with another source remain intact.  The batch refreshes A* once, avoiding
	# repeated 112x82 scans while loading a city with many occupied tiles.
	var retained: Dictionary = {}
	for blocker_id_variant: Variant in _dynamic_blockers.keys():
		var blocker_id := str(blocker_id_variant)
		var blocker: Dictionary = _dynamic_blockers[blocker_id_variant]
		var source := str(blocker.get("source", "dynamic"))
		if source not in ["building", "construction"]:
			retained[blocker_id] = blocker
	_dynamic_blockers = retained
	var safe_extents := Vector2(maxf(0.5, half_extents.x), maxf(0.5, half_extents.y))
	for tile_variant: Variant in building_centers.keys():
		var tile_index := int(tile_variant)
		var center: Vector2 = building_centers[tile_variant]
		var blocker_id := "building:%d" % tile_index
		_dynamic_blockers[blocker_id] = _dynamic_blocker_record(
			blocker_id, center, safe_extents, "building", tile_index, "building"
		)
	for tile_variant: Variant in construction_centers.keys():
		var tile_index := int(tile_variant)
		var center: Vector2 = construction_centers[tile_variant]
		var blocker_id := "construction:%d" % tile_index
		_dynamic_blockers[blocker_id] = _dynamic_blocker_record(
			blocker_id, center, safe_extents, "construction", tile_index, "construction"
		)
	_refresh_grid_solidity()


func sync_map_tile_blockers(
	terrain_blockers: Dictionary,
	building_centers: Dictionary,
	construction_centers: Dictionary,
	terrain_half_extents: Vector2 = DEFAULT_DYNAMIC_HALF_EXTENTS,
	structure_half_extents: Vector2 = DEFAULT_DYNAMIC_HALF_EXTENTS
) -> void:
	# Replace the complete map-owned blocker set in one A* refresh. Custom
	# diagnostic/gameplay blockers remain untouched.
	var retained: Dictionary = {}
	for blocker_id_variant: Variant in _dynamic_blockers.keys():
		var blocker_id := str(blocker_id_variant)
		var blocker: Dictionary = _dynamic_blockers[blocker_id_variant]
		var source := str(blocker.get("source", "dynamic"))
		if source not in ["terrain", "building", "construction"]:
			retained[blocker_id] = blocker
	_dynamic_blockers = retained

	var safe_terrain_extents := _safe_half_extents(terrain_half_extents)
	var safe_structure_extents := _safe_half_extents(structure_half_extents)
	for tile_variant: Variant in terrain_blockers.keys():
		var terrain_variant: Variant = terrain_blockers[tile_variant]
		var center := Vector2.ZERO
		var terrain_kind := "terrain"
		if terrain_variant is Dictionary:
			var terrain_record: Dictionary = terrain_variant
			var center_variant: Variant = terrain_record.get(
				"center", terrain_record.get("position", null)
			)
			if not center_variant is Vector2:
				continue
			center = center_variant
			terrain_kind = str(terrain_record.get("kind", "terrain"))
		elif terrain_variant is Vector2:
			center = terrain_variant
		else:
			continue
		var tile_index := int(tile_variant)
		var blocker_id := "terrain:%d" % tile_index
		_dynamic_blockers[blocker_id] = _dynamic_blocker_record(
			blocker_id,
			center,
			safe_terrain_extents,
			terrain_kind if not terrain_kind.is_empty() else "terrain",
			tile_index,
			"terrain"
		)

	for tile_variant: Variant in building_centers.keys():
		var tile_index := int(tile_variant)
		var center_variant: Variant = building_centers[tile_variant]
		if not center_variant is Vector2:
			continue
		var blocker_id := "building:%d" % tile_index
		_dynamic_blockers[blocker_id] = _dynamic_blocker_record(
			blocker_id,
			center_variant,
			safe_structure_extents,
			"building",
			tile_index,
			"building"
		)

	for tile_variant: Variant in construction_centers.keys():
		var tile_index := int(tile_variant)
		var center_variant: Variant = construction_centers[tile_variant]
		if not center_variant is Vector2:
			continue
		var blocker_id := "construction:%d" % tile_index
		_dynamic_blockers[blocker_id] = _dynamic_blocker_record(
			blocker_id,
			center_variant,
			safe_structure_extents,
			"construction",
			tile_index,
			"construction"
		)
	_refresh_grid_solidity()


func set_dynamic_diamond(
	blocker_id: String,
	center: Vector2,
	half_extents: Vector2,
	enabled: bool = true,
	kind: String = "dynamic",
	tile_index: int = -1,
	source: String = ""
) -> void:
	if blocker_id.is_empty():
		return
	if not enabled:
		_dynamic_blockers.erase(blocker_id)
		_refresh_grid_solidity()
		return
	var safe_extents := _safe_half_extents(half_extents)
	_dynamic_blockers[blocker_id] = _dynamic_blocker_record(
		blocker_id,
		center,
		safe_extents,
		kind,
		tile_index,
		source if not source.is_empty() else kind
	)
	_refresh_grid_solidity()


func clear_dynamic_blockers() -> void:
	if _dynamic_blockers.is_empty() and _transport_crossing_apertures.is_empty():
		return
	_dynamic_blockers.clear()
	_transport_crossing_apertures.clear()
	_refresh_grid_solidity()


## Completed earthworks only open the selected plot. Other parts of the same
## backdrop feature remain solid.
func set_flattened_terrain_apertures(
	flattened_centers: Dictionary,
	half_extents: Vector2 = BACKDROP_PLOT_HALF_EXTENTS
) -> void:
	var next_apertures: Dictionary = {}
	var safe_extents := _safe_half_extents(half_extents)
	var edge_normal_length := sqrt(
		1.0 / (safe_extents.x * safe_extents.x)
		+ 1.0 / (safe_extents.y * safe_extents.y)
	)
	var clearance_scale := clampf(1.0 - _foot_radius * edge_normal_length, 0.05, 1.0)
	var walkable_extents := safe_extents * clearance_scale
	for tile_variant: Variant in flattened_centers.keys():
		var center_variant: Variant = flattened_centers[tile_variant]
		if not center_variant is Vector2:
			continue
		var tile_index := int(tile_variant)
		next_apertures[tile_index] = {
			"id": "flattened_terrain:%d" % tile_index,
			"tile_index": tile_index,
			"center": center_variant,
			"half_extents": safe_extents,
			"walkable_half_extents": walkable_extents,
			"points": _diamond_points(center_variant, walkable_extents),
		}
	_flattened_terrain_apertures = next_apertures
	_rebuild_static_solidity()
	_refresh_grid_solidity()


## Opens completed level-crossing tiles for pedestrian navigation.  The
## aperture only overrides a map-owned transport blocker with the same tile id;
## buildings, construction, natural terrain, and arbitrary gameplay blockers
## remain solid even if a malformed crossing record points at their tile.
func set_transport_crossing_apertures(tile_ids: PackedInt32Array) -> void:
	var next_apertures: Dictionary = {}
	for tile_id: int in tile_ids:
		if tile_id >= 0:
			next_apertures[tile_id] = true
	if next_apertures == _transport_crossing_apertures:
		return
	_transport_crossing_apertures = next_apertures
	_refresh_grid_solidity()


func get_debug_transport_crossing_aperture_tile_ids() -> PackedInt32Array:
	var tile_ids := PackedInt32Array()
	var sorted_ids: Array[int] = []
	for tile_variant: Variant in _transport_crossing_apertures.keys():
		sorted_ids.append(int(tile_variant))
	sorted_ids.sort()
	for tile_id: int in sorted_ids:
		tile_ids.append(tile_id)
	return tile_ids


func get_debug_static_polygons() -> Array[Dictionary]:
	return _duplicate_polygon_records(_static_polygons)


func get_debug_flattened_terrain_apertures() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var tile_ids: Array = _flattened_terrain_apertures.keys()
	tile_ids.sort()
	for tile_variant: Variant in tile_ids:
		var record: Dictionary = _flattened_terrain_apertures[tile_variant]
		var copy := record.duplicate(true)
		copy["points"] = PackedVector2Array(record["points"]).duplicate()
		records.append(copy)
	return records


func get_debug_dynamic_polygons() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var ids: Array = _dynamic_blockers.keys()
	ids.sort()
	for blocker_id: Variant in ids:
		var blocker: Dictionary = _dynamic_blockers[blocker_id]
		var copy := blocker.duplicate(true)
		copy["points"] = PackedVector2Array(blocker["points"]).duplicate()
		records.append(copy)
	return records


func get_debug_points(include_walkable: bool = false) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for y in GRID_SIZE.y:
		for x in GRID_SIZE.x:
			var point_id := Vector2i(x, y)
			var position := _astar.get_point_position(point_id)
			var walkable := not _astar.is_point_solid(point_id)
			if walkable and not include_walkable:
				continue
			records.append({
				"id": point_id,
				"position": position,
				"walkable": walkable,
				"static_kinds": static_classification_at(position),
				"dynamic_ids": _dynamic_ids_at(position),
			})
	return records


func get_last_raw_path_trace() -> PackedVector2Array:
	return _last_raw_path.duplicate()


func get_last_path_trace() -> PackedVector2Array:
	return _last_path.duplicate()


func get_last_query_diagnostics() -> Dictionary:
	return _last_query_diagnostics.duplicate(true)


func get_debug_snapshot(include_walkable_points: bool = false) -> Dictionary:
	return {
		"stage_size": STAGE_SIZE,
		"grid_cell_size": GRID_CELL_SIZE,
		"grid_size": GRID_SIZE,
		"foot_radius": _foot_radius,
		"static_polygons": get_debug_static_polygons(),
		"flattened_terrain_apertures": get_debug_flattened_terrain_apertures(),
		"dynamic_polygons": get_debug_dynamic_polygons(),
		"points": get_debug_points(include_walkable_points),
		"raw_path": get_last_raw_path_trace(),
		"path": get_last_path_trace(),
		"query": get_last_query_diagnostics(),
	}


func _configure_astar() -> void:
	_astar.region = Rect2i(Vector2i.ZERO, GRID_SIZE)
	_astar.cell_size = Vector2(GRID_CELL_SIZE, GRID_CELL_SIZE)
	_astar.offset = Vector2(GRID_CELL_SIZE * 0.5, GRID_CELL_SIZE * 0.5)
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.jumping_enabled = false
	_astar.update()


func _rebuild_static_solidity() -> void:
	_static_solid.resize(GRID_SIZE.x * GRID_SIZE.y)
	_static_solid.fill(0)
	for y in GRID_SIZE.y:
		for x in GRID_SIZE.x:
			var point_id := Vector2i(x, y)
			var position := _astar.get_point_position(point_id)
			if not _inside_stage_with_clearance(position) or _point_blocked_by_static(position):
				_static_solid[_flat_index(point_id)] = 1


func _refresh_grid_solidity() -> void:
	for y in GRID_SIZE.y:
		for x in GRID_SIZE.x:
			var point_id := Vector2i(x, y)
			var blocked := _static_solid[_flat_index(point_id)] == 1
			if not blocked:
				var position := _astar.get_point_position(point_id)
				blocked = _point_blocked_by_dynamic(position)
			_astar.set_point_solid(point_id, blocked)


func _point_blocked_by_static(position: Vector2) -> bool:
	if _point_inside_flattened_terrain_aperture(position):
		return false
	for polygon_data: Dictionary in _static_polygons:
		if _point_touches_polygon(position, polygon_data["points"], _foot_radius):
			return true
	return false


func _point_inside_flattened_terrain_aperture(position: Vector2) -> bool:
	for aperture_variant: Variant in _flattened_terrain_apertures.values():
		var aperture: Dictionary = aperture_variant
		if _point_touches_polygon(position, aperture["points"], 0.0):
			return true
	return false


func _point_blocked_by_dynamic(position: Vector2) -> bool:
	for blocker_variant: Variant in _dynamic_blockers.values():
		var blocker: Dictionary = blocker_variant
		if _blocker_has_open_transport_aperture(blocker):
			continue
		if _point_touches_polygon(position, blocker["points"], _foot_radius):
			return true
	return false


func _blocker_has_open_transport_aperture(blocker: Dictionary) -> bool:
	return (
		str(blocker.get("kind", "")) == "transport_network"
		and _transport_crossing_apertures.has(int(blocker.get("tile_index", -1)))
	)


func _point_touches_polygon(
	position: Vector2,
	polygon: PackedVector2Array,
	clearance: float
) -> bool:
	if polygon.size() < 3:
		return false
	if Geometry2D.is_point_in_polygon(position, polygon):
		return true
	if clearance <= 0.0:
		return false
	var clearance_squared := clearance * clearance
	for point_index in polygon.size():
		var start := polygon[point_index]
		var finish := polygon[(point_index + 1) % polygon.size()]
		var closest := Geometry2D.get_closest_point_to_segment(position, start, finish)
		if position.distance_squared_to(closest) <= clearance_squared:
			return true
	return false


func _inside_stage_with_clearance(position: Vector2) -> bool:
	return (
		position.x >= _foot_radius
		and position.y >= _foot_radius
		and position.x <= STAGE_SIZE.x - _foot_radius
		and position.y <= STAGE_SIZE.y - _foot_radius
	)


func _resolve_endpoint(position: Vector2, snap_to_nearest: bool) -> Variant:
	var point_id := _position_to_id(position)
	if (
		is_position_walkable(position)
		and _astar.is_in_boundsv(point_id)
		and not _astar.is_point_solid(point_id)
	):
		return position
	if not snap_to_nearest:
		return null
	return nearest_safe_position(position)


func _position_to_id(position: Vector2) -> Vector2i:
	return Vector2i(
		floori(position.x / GRID_CELL_SIZE),
		floori(position.y / GRID_CELL_SIZE)
	)


func _string_pull_path(raw_path: PackedVector2Array) -> PackedVector2Array:
	if raw_path.is_empty():
		return PackedVector2Array()
	if raw_path.size() == 1:
		return raw_path.duplicate() if is_position_walkable(raw_path[0]) else PackedVector2Array()
	var result := PackedVector2Array([raw_path[0]])
	var anchor_index := 0
	while anchor_index < raw_path.size() - 1:
		var selected_index := -1
		for candidate_index in range(raw_path.size() - 1, anchor_index, -1):
			if is_segment_walkable(raw_path[anchor_index], raw_path[candidate_index]):
				selected_index = candidate_index
				break
		if selected_index < 0:
			return PackedVector2Array()
		_append_unique_point(result, raw_path[selected_index])
		anchor_index = selected_index
	return result


func _append_unique_point(points: PackedVector2Array, point: Vector2) -> void:
	if points.is_empty() or not points[points.size() - 1].is_equal_approx(point):
		points.append(point)


func _path_length(path: PackedVector2Array) -> float:
	var length := 0.0
	for point_index in range(1, path.size()):
		length += path[point_index - 1].distance_to(path[point_index])
	return length


func _flat_index(point_id: Vector2i) -> int:
	return point_id.y * GRID_SIZE.x + point_id.x


func _dynamic_ids_at(position: Vector2) -> PackedStringArray:
	var ids := PackedStringArray()
	var blocker_ids: Array = _dynamic_blockers.keys()
	blocker_ids.sort()
	for blocker_id: Variant in blocker_ids:
		var blocker: Dictionary = _dynamic_blockers[blocker_id]
		if _point_touches_polygon(position, blocker["points"], _foot_radius):
			ids.append(str(blocker_id))
	return ids


func _duplicate_polygon_records(source: Array[Dictionary]) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for polygon_data: Dictionary in source:
		var copy := polygon_data.duplicate(true)
		copy["points"] = PackedVector2Array(polygon_data["points"]).duplicate()
		records.append(copy)
	return records


static func _diamond_points(center: Vector2, half_extents: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(0.0, -half_extents.y),
		center + Vector2(half_extents.x, 0.0),
		center + Vector2(0.0, half_extents.y),
		center + Vector2(-half_extents.x, 0.0),
	])


static func _polygon_area(points: PackedVector2Array) -> float:
	if points.size() < 3:
		return 0.0
	var doubled_area := 0.0
	for point_index in points.size():
		var current := points[point_index]
		var next := points[(point_index + 1) % points.size()]
		doubled_area += current.x * next.y - next.x * current.y
	return absf(doubled_area) * 0.5


func _safe_half_extents(half_extents: Vector2) -> Vector2:
	return Vector2(maxf(0.5, half_extents.x), maxf(0.5, half_extents.y))


func _dynamic_blocker_record(
	blocker_id: String,
	center: Vector2,
	half_extents: Vector2,
	kind: String,
	tile_index: int,
	source: String
) -> Dictionary:
	return {
		"id": blocker_id,
		"kind": kind,
		"source": source,
		"tile_index": tile_index,
		"center": center,
		"half_extents": half_extents,
		"points": _diamond_points(center, half_extents),
	}


func _reset_query_diagnostics() -> void:
	_last_query_diagnostics = {
		"status": "not_queried",
		"requested_start": Vector2.ZERO,
		"requested_target": Vector2.ZERO,
		"resolved_start": Vector2.ZERO,
		"resolved_target": Vector2.ZERO,
		"raw_point_count": 0,
		"smoothed_point_count": 0,
		"path_length": 0.0,
	}


static func _create_static_polygons() -> Array[Dictionary]:
	# Coordinates were authored in the fixed map_stage space, not in the source
	# texture's 1672x941 pixel space.  Keep these records simple and non-self-
	# intersecting so they are also suitable for debug overlay rendering.
	return [
		{
			"id": "river_north",
			"kind": KIND_RIVER_LAKE,
			"points": PackedVector2Array([
				Vector2(778, -12), Vector2(895, -12), Vector2(879, 42),
				Vector2(846, 88), Vector2(858, 139), Vector2(843, 185),
				Vector2(808, 221), Vector2(780, 201), Vector2(792, 156),
				Vector2(779, 111), Vector2(791, 66),
			]),
		},
		{
			"id": "lake_north_central",
			"kind": KIND_RIVER_LAKE,
			"points": PackedVector2Array([
				Vector2(468, 224), Vector2(518, 200), Vector2(581, 196),
				Vector2(641, 207), Vector2(701, 214), Vector2(757, 194),
				Vector2(807, 215), Vector2(810, 261), Vector2(778, 301),
				Vector2(718, 329), Vector2(638, 336), Vector2(564, 330),
				Vector2(507, 310), Vector2(475, 281),
			]),
		},
		{
			"id": "northwest_cliffs",
			"kind": KIND_HILL_CLIFF,
			"points": PackedVector2Array([
				Vector2(-12, -12), Vector2(466, -12), Vector2(456, 68),
				Vector2(418, 98), Vector2(402, 141), Vector2(367, 164),
				Vector2(365, 207), Vector2(321, 228), Vector2(281, 215),
				Vector2(247, 243), Vector2(205, 233), Vector2(187, 268),
				Vector2(135, 285), Vector2(87, 258), Vector2(38, 269),
				Vector2(-12, 239),
			]),
		},
		{
			"id": "northern_cliffs",
			"kind": KIND_HILL_CLIFF,
			"points": PackedVector2Array([
				Vector2(438, -12), Vector2(781, -12), Vector2(776, 66),
				Vector2(746, 99), Vector2(731, 142), Vector2(697, 171),
				Vector2(651, 170), Vector2(624, 192), Vector2(570, 184),
				Vector2(542, 166), Vector2(501, 173), Vector2(456, 147),
				Vector2(428, 105),
			]),
		},
		{
			"id": "northeast_cliffs",
			"kind": KIND_HILL_CLIFF,
			"points": PackedVector2Array([
				Vector2(884, -12), Vector2(1132, -12), Vector2(1132, 290),
				Vector2(1082, 276), Vector2(1042, 250), Vector2(1010, 253),
				Vector2(982, 231), Vector2(944, 239), Vector2(911, 214),
				Vector2(875, 203), Vector2(861, 168), Vector2(881, 121),
			]),
		},
		{
			"id": "west_cliff_spur",
			"kind": KIND_HILL_CLIFF,
			"points": PackedVector2Array([
				Vector2(-12, 238), Vector2(56, 246), Vector2(101, 264),
				Vector2(141, 286), Vector2(178, 311), Vector2(202, 337),
				Vector2(188, 367), Vector2(154, 381), Vector2(119, 361),
				Vector2(82, 377), Vector2(42, 358), Vector2(-12, 369),
			]),
		},
		{
			"id": "west_forest",
			"kind": KIND_TREES_SCENERY,
			"points": PackedVector2Array([
				Vector2(-12, 216), Vector2(49, 226), Vector2(82, 255),
				Vector2(91, 300), Vector2(111, 340), Vector2(100, 394),
				Vector2(119, 438), Vector2(99, 484), Vector2(118, 529),
				Vector2(96, 575), Vector2(119, 625), Vector2(102, 678),
				Vector2(64, 711), Vector2(-12, 708),
			]),
		},
		{
			"id": "east_forest",
			"kind": KIND_TREES_SCENERY,
			"points": PackedVector2Array([
				Vector2(1017, 244), Vector2(1065, 235), Vector2(1132, 218),
				Vector2(1132, 691), Vector2(1069, 678), Vector2(1038, 647),
				Vector2(1048, 603), Vector2(1027, 568), Vector2(1044, 525),
				Vector2(1021, 484), Vector2(1036, 446), Vector2(1012, 405),
				Vector2(1029, 363), Vector2(1007, 319),
			]),
		},
		{
			"id": "southwest_forest",
			"kind": KIND_TREES_SCENERY,
			"points": PackedVector2Array([
				Vector2(-12, 688), Vector2(76, 679), Vector2(143, 699),
				Vector2(203, 679), Vector2(259, 705), Vector2(310, 688),
				Vector2(354, 717), Vector2(375, 756), Vector2(361, 832),
				Vector2(-12, 832),
			]),
		},
		{
			"id": "southcentral_forest",
			"kind": KIND_TREES_SCENERY,
			"points": PackedVector2Array([
				Vector2(337, 717), Vector2(390, 686), Vector2(450, 681),
				Vector2(500, 703), Vector2(548, 686), Vector2(603, 701),
				Vector2(647, 680), Vector2(702, 692), Vector2(749, 722),
				Vector2(763, 762), Vector2(749, 832), Vector2(330, 832),
			]),
		},
		{
			"id": "southeast_forest",
			"kind": KIND_TREES_SCENERY,
			"points": PackedVector2Array([
				Vector2(729, 742), Vector2(775, 704), Vector2(827, 690),
				Vector2(878, 704), Vector2(921, 681), Vector2(973, 694),
				Vector2(1013, 672), Vector2(1057, 688), Vector2(1132, 675),
				Vector2(1132, 832), Vector2(730, 832),
			]),
		},
		{
			"id": "south_meadow_rocks",
			"kind": KIND_TREES_SCENERY,
			"points": PackedVector2Array([
				Vector2(657, 625), Vector2(695, 603), Vector2(739, 600),
				Vector2(779, 616), Vector2(797, 644), Vector2(778, 674),
				Vector2(736, 685), Vector2(691, 675), Vector2(663, 653),
			]),
		},
		# The following compact scenery islands sit inside the otherwise open
		# meadow.  Their outlines follow only the visible tree/rock/flower mass;
		# the adjacent tan paths and grass lanes deliberately remain outside.
		{
			"id": "west_lower_tree_grove",
			"kind": KIND_TREES_SCENERY,
			"points": PackedVector2Array([
				Vector2(88, 520), Vector2(119, 505), Vector2(153, 514),
				Vector2(184, 533), Vector2(202, 554), Vector2(201, 583),
				Vector2(180, 611), Vector2(143, 624), Vector2(106, 612),
				Vector2(90, 582),
			]),
		},
		{
			"id": "south_meadow_tree_grove",
			"kind": KIND_TREES_SCENERY,
			"points": PackedVector2Array([
				Vector2(748, 612), Vector2(772, 586), Vector2(807, 575),
				Vector2(844, 588), Vector2(874, 609), Vector2(867, 641),
				Vector2(842, 669), Vector2(805, 682), Vector2(778, 666),
				Vector2(758, 642),
			]),
		},
		{
			"id": "east_path_rock_garden_upper",
			"kind": KIND_TREES_SCENERY,
			"points": PackedVector2Array([
				Vector2(899, 537), Vector2(914, 523), Vector2(939, 519),
				Vector2(958, 530), Vector2(957, 549), Vector2(940, 562),
				Vector2(914, 562), Vector2(899, 550),
			]),
		},
		{
			"id": "east_path_rock_garden_lower",
			"kind": KIND_TREES_SCENERY,
			"points": PackedVector2Array([
				Vector2(947, 577), Vector2(959, 565), Vector2(977, 567),
				Vector2(988, 579), Vector2(982, 593), Vector2(964, 599),
				Vector2(949, 591),
			]),
		},
	]
