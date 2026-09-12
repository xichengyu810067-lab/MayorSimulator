class_name CityNavigationGrid
extends RefCounted

const CityTerrainLayoutScript = preload("res://data/catalogs/city_terrain_layout.gd")
const CityBackdropTerrainCatalog = preload("res://data/catalogs/city_backdrop_terrain.gd")
const SquareGridLayoutScript = preload("res://scripts/world/square_grid_layout.gd")

## Deterministic, stage-local navigation for the fixed 1120x820 city map.
##
## The navigation grid deliberately does not depend on Control/global canvas
## transforms.  Callers keep NPC foot positions in map_stage local space and
## convert only when rendering.  Static polygons describe the non-walkable
## scenery in city-map-background.png after its keep-aspect-covered crop.

const STAGE_SIZE := Vector2(1120.0, 820.0)
const BACKDROP_ASSET_PATH := "res://assets/images/world/backgrounds/city-map-background.png"
const BACKDROP_ISO_TILE_STEP := SquareGridLayoutScript.CELL_SIZE
const BACKDROP_ISO_MAP_ORIGIN := SquareGridLayoutScript.GRID_ORIGIN
const BACKDROP_TILE_FOOT_OFFSET_Y := 0.0
const BACKDROP_PLOT_HALF_EXTENTS := SquareGridLayoutScript.CELL_SIZE * 0.5
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
	_static_polygons = _create_layout_terrain_polygons()
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


## Layout 3's frozen backdrop classification is the shared terrain source for
## both plot legality and NPC navigation. Its geometry now comes from the
## canonical square grid while retaining the original image-derived kinds.
static func backdrop_terrain_for_coordinate(coordinate: Vector2i) -> Dictionary:
	return CityTerrainLayoutScript.model_for_coordinate(coordinate)


static func backdrop_tile_center(coordinate: Vector2i) -> Vector2:
	return SquareGridLayoutScript.center_for_coordinate(coordinate)


static func backdrop_terrain_for_plot(center: Vector2, half_extents: Vector2) -> Dictionary:
	var plot := _rect_points(center, half_extents)
	var plot_area := maxf(1.0, _polygon_area(plot))
	var coverage_by_kind: Dictionary = {}
	var feature_ids_by_kind: Dictionary = {}
	var kind_order := PackedStringArray()
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
		if not coverage_by_kind.has(kind):
			kind_order.append(kind)
		coverage_by_kind[kind] = float(coverage_by_kind.get(kind, 0.0)) + coverage
		var ids: Array = Array(feature_ids_by_kind.get(kind, [])).duplicate()
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
	set_dynamic_rect(
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
	set_dynamic_rect(
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
	set_dynamic_rect(
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
	# Once an authoritative terrain snapshot is loaded, its tile blockers own
	# natural navigation. The startup backdrop polygons must not leak layout 4
	# classification into preserved legacy terrain.
	if not _static_polygons.is_empty():
		_static_polygons.clear()
		_rebuild_static_solidity()
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
		source if not source.is_empty() else kind,
		_diamond_points(center, safe_extents)
	)
	_refresh_grid_solidity()


func set_dynamic_rect(
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
		source if not source.is_empty() else kind,
		_rect_points(center, safe_extents)
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
	var walkable_extents := Vector2(
		maxf(0.5, safe_extents.x - _foot_radius),
		maxf(0.5, safe_extents.y - _foot_radius)
	)
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
			"points": _rect_points(center_variant, walkable_extents),
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
	source: String,
	points: PackedVector2Array = PackedVector2Array()
) -> Dictionary:
	var resolved_points := points if not points.is_empty() else _rect_points(center, half_extents)
	return {
		"id": blocker_id,
		"kind": kind,
		"source": source,
		"tile_index": tile_index,
		"center": center,
		"half_extents": half_extents,
		"points": resolved_points,
	}


static func _rect_points(center: Vector2, half_extents: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(-half_extents.x, -half_extents.y),
		center + Vector2(half_extents.x, -half_extents.y),
		center + Vector2(half_extents.x, half_extents.y),
		center + Vector2(-half_extents.x, half_extents.y),
	])


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


static func _create_layout_terrain_polygons() -> Array[Dictionary]:
	var polygons: Array[Dictionary] = []
	for tile_id in CityTerrainLayoutScript.CELL_COUNT:
		if not CityTerrainLayoutScript.is_blocked_tile_id(tile_id):
			continue
		var model := CityTerrainLayoutScript.model_for_tile_id(tile_id)
		var center := Vector2(model.get("plot_center", Vector2.INF))
		if center == Vector2.INF:
			continue
		var half_extents := SquareGridLayoutScript.CELL_SIZE * 0.5
		polygons.append({
			"id": "terrain_layout4:%d" % tile_id,
			"kind": str(model.get("kind", "terrain")),
			"tile_index": tile_id,
			"center": center,
			"half_extents": half_extents,
			"points": _rect_points(center, half_extents),
		})
	return polygons


static func _create_static_polygons() -> Array[Dictionary]:
	return CityBackdropTerrainCatalog.static_polygons()
