extends SceneTree

const CityTerrainMapScript = preload("res://scripts/world/city_terrain_map.gd")
const NpcMapControllerScript = preload("res://scripts/app/npc_map_controller.gd")

const TERRAIN_KINDS := [
	"trees",
	"hill_cliff",
	"river_lake",
	"road_path",
	"rail_track",
]
const TERRAIN_HALF_EXTENTS := Vector2(22, 14)
const STRUCTURE_HALF_EXTENTS := Vector2(24, 16)
const BUILDING_TILE_ID := 90
const BUILDING_CENTER := Vector2(820, 500)

var _failed := false
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var terrain = CityTerrainMapScript.new()
	var centers := PackedVector2Array()
	centers.resize(terrain.cell_count())
	for tile_id in range(terrain.cell_count()):
		centers[tile_id] = Vector2(40, 40)
	for index in range(TERRAIN_KINDS.size()):
		centers[index] = Vector2(300 + index * 90, 500)
		_check(
			terrain.set_tile_kind(index, TERRAIN_KINDS[index]),
			"could not configure %s fixture" % TERRAIN_KINDS[index]
		)

	var controller = NpcMapControllerScript.new()
	get_root().add_child(controller)
	var building_centers := {BUILDING_TILE_ID: BUILDING_CENTER}
	controller.configure_navigation(_map_snapshot(
		terrain.navigation_blockers(centers),
		building_centers
	))
	var navigation = controller.get_navigation_grid()
	_check(navigation != null, "NPC map controller did not create navigation authority")
	if navigation == null:
		await _finish(controller)
		return

	_validate_all_terrain_blockers(navigation, centers)
	_check(
		not navigation.is_position_walkable(BUILDING_CENTER),
		"building blocker was not installed beside terrain blockers"
	)

	# Rebuild the controller snapshot after each leveling action. Every flattened
	# terrain blocker must disappear, while the unrelated building blocker must
	# survive every complete map-owned blocker synchronization.
	for tile_id in range(TERRAIN_KINDS.size()):
		var result: Dictionary = terrain.flatten_tile(tile_id)
		_check(
			bool(result.get("ok", false)) and bool(result.get("changed", false)),
			"%s terrain did not flatten" % TERRAIN_KINDS[tile_id]
		)
		controller.sync_map_snapshot(_map_snapshot(
			terrain.navigation_blockers(centers),
			building_centers
		))
		var records := _records_by_id(navigation.get_debug_dynamic_polygons())
		_check(
			not records.has("terrain:%d" % tile_id),
			"flattened %s still has a terrain blocker" % TERRAIN_KINDS[tile_id]
		)
		_check(
			navigation.is_position_walkable(centers[tile_id]),
			"flattened %s center remains unwalkable" % TERRAIN_KINDS[tile_id]
		)
		_check(
			records.has("building:%d" % BUILDING_TILE_ID),
			"building blocker was discarded while flattening %s" % TERRAIN_KINDS[tile_id]
		)
		_check(
			not navigation.is_position_walkable(BUILDING_CENTER),
			"building center became walkable while flattening %s" % TERRAIN_KINDS[tile_id]
		)

	var final_records := _records_by_id(navigation.get_debug_dynamic_polygons())
	_check(final_records.size() == 1, "flattened map retained stale terrain blockers")
	_check(
		str(final_records.get("building:%d" % BUILDING_TILE_ID, {}).get("source", "")) == "building",
		"final structure blocker lost its building classification"
	)

	if not _failed:
		print("Terrain navigation blocker test passed. Checks=%d TerrainKinds=5 BuildingRetained=1" % _checks)
	await _finish(controller)


func _map_snapshot(terrain_blockers: Dictionary, building_centers: Dictionary) -> Dictionary:
	return {
		"tile_centers": PackedVector2Array(),
		"iso_tile_size": Vector2(104, 104),
		"iso_tile_step": Vector2(56, 32),
		"terrain_blockers": terrain_blockers,
		"building_centers": building_centers,
		"construction_centers": {},
		"terrain_blocker_half_extents": TERRAIN_HALF_EXTENTS,
		"structure_blocker_half_extents": STRUCTURE_HALF_EXTENTS,
	}


func _validate_all_terrain_blockers(navigation, centers: PackedVector2Array) -> void:
	var records := _records_by_id(navigation.get_debug_dynamic_polygons())
	_check(records.size() == TERRAIN_KINDS.size() + 1, "initial blocker set is incomplete")
	for tile_id in range(TERRAIN_KINDS.size()):
		var blocker_id := "terrain:%d" % tile_id
		_check(records.has(blocker_id), "%s is missing from terrain blockers" % TERRAIN_KINDS[tile_id])
		if records.has(blocker_id):
			var record: Dictionary = records[blocker_id]
			_check(str(record.get("kind", "")) == TERRAIN_KINDS[tile_id], "%s blocker kind was rewritten" % TERRAIN_KINDS[tile_id])
			_check(str(record.get("source", "")) == "terrain", "%s blocker source is not terrain" % TERRAIN_KINDS[tile_id])
		_check(
			not navigation.is_position_walkable(centers[tile_id]),
			"%s center remains walkable" % TERRAIN_KINDS[tile_id]
		)


func _records_by_id(records: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for record: Dictionary in records:
		result[str(record.get("id", ""))] = record
	return result


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Terrain navigation blocker test failed: %s" % message)


func _finish(controller: Node) -> void:
	if controller != null and is_instance_valid(controller):
		controller.queue_free()
	await process_frame
	quit(1 if _failed else 0)
