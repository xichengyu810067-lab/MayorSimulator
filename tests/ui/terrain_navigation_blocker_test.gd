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
const CROSSING_TILE_ID := 91
const CROSSING_CENTER := Vector2(620, 500)

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
	_validate_transport_crossing_aperture(controller, navigation, building_centers)

	if not _failed:
		print("Terrain navigation blocker test passed. Checks=%d TerrainKinds=5 BuildingRetained=1" % _checks)
	await _finish(controller)


func _map_snapshot(
	terrain_blockers: Dictionary,
	building_centers: Dictionary,
	crossing_tile_ids: PackedInt32Array = PackedInt32Array()
) -> Dictionary:
	return {
		"tile_centers": PackedVector2Array(),
		"iso_tile_size": Vector2(104, 104),
		"iso_tile_step": Vector2(56, 32),
		"terrain_blockers": terrain_blockers,
		"building_centers": building_centers,
		"construction_centers": {},
		"crossing_tile_ids": crossing_tile_ids,
		"terrain_blocker_half_extents": TERRAIN_HALF_EXTENTS,
		"structure_blocker_half_extents": STRUCTURE_HALF_EXTENTS,
	}


func _validate_transport_crossing_aperture(controller, navigation, building_centers: Dictionary) -> void:
	var transport_blockers := {
		CROSSING_TILE_ID: {
			"center": CROSSING_CENTER,
			"kind": "transport_network",
		},
	}
	var before := CROSSING_CENTER - Vector2(70, 0)
	var after := CROSSING_CENTER + Vector2(70, 0)
	controller.sync_map_snapshot(_map_snapshot(transport_blockers, building_centers))
	_check(not navigation.is_position_walkable(CROSSING_CENTER), "road/rail barrier must be solid without a crossing record")
	_check(not navigation.is_segment_walkable(before, after), "road/rail barrier allowed an undeclared crossing")
	_check(controller.is_tile_blocked(CROSSING_TILE_ID), "undeclared transport crossing tile was reported open")

	controller.sync_map_snapshot(_map_snapshot(
		transport_blockers,
		building_centers,
		PackedInt32Array([CROSSING_TILE_ID])
	))
	_check(navigation.is_position_walkable(CROSSING_CENTER), "completed open crossing did not create a navigation aperture")
	_check(navigation.is_segment_walkable(before, after), "open crossing aperture did not connect both sides")
	_check(not controller.is_tile_blocked(CROSSING_TILE_ID), "open crossing still reports a blocked NPC tile")
	_check(
		navigation.get_debug_transport_crossing_aperture_tile_ids() == PackedInt32Array([CROSSING_TILE_ID]),
		"debug contract does not expose the open crossing aperture"
	)

	controller.set_crossing_states({str(CROSSING_TILE_ID): {"closed": true, "flash": false}})
	_check(not navigation.is_position_walkable(CROSSING_CENTER), "closed gate left its NPC aperture walkable")
	_check(not navigation.is_segment_walkable(before, after), "closed gate still permits a crossing segment")
	_check(controller.is_tile_blocked(CROSSING_TILE_ID), "closed crossing is not reported as blocked")

	# Warning-light animation must not alter the closed/open policy.
	controller.set_crossing_states({str(CROSSING_TILE_ID): {"closed": true, "flash": true}})
	_check(navigation.get_debug_transport_crossing_aperture_tile_ids().is_empty(), "flash-only update reopened a closed aperture")
	controller.set_crossing_states({str(CROSSING_TILE_ID): {"closed": false, "flash": false}})
	_check(navigation.is_segment_walkable(before, after), "reopened gate did not restore its aperture")
	_check(not navigation.is_position_walkable(BUILDING_CENTER), "crossing aperture overrode an unrelated building blocker")


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
