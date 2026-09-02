extends SceneTree

const BuildingFootprintsScript = preload("res://data/catalogs/building_footprints.gd")
const CityTerrainMapScript = preload("res://scripts/world/city_terrain_map.gd")
const VerticalSliceCoordinatorScript = preload("res://scripts/app/vertical_slice_coordinator.gd")

const MEDIUM_ACTIVE_SAVE_PATH := "user://tests/building_footprint_medium_active.json"
const LARGE_ACTIVE_SAVE_PATH := "user://tests/building_footprint_large_active.json"
const LARGE_COMPLETED_SAVE_PATH := "user://tests/building_footprint_large_completed.json"

const CITY_CONTEXT := {
	"population": 300,
	"security": 70,
	"environment": 70,
	"traffic": 70,
	"education": 70,
	"healthcare": 70,
}
const NATURAL_OBSTACLE_KINDS := ["trees", "river_lake", "hill_cliff"]
const FOOTPRINT_SCENARIOS := [
	{"size": "small", "display_name": "公園", "cell_count": 1},
	{"size": "medium", "display_name": "學校", "cell_count": 2},
	{"size": "large", "display_name": "體育館", "cell_count": 3},
]

var _failed := false
var _checks := 0


func _initialize() -> void:
	_test_catalog_contract()
	_test_natural_obstacle_feedback_for_every_footprint_cell()
	_test_current_existing_registration_contract()
	_test_atomic_placement_and_single_building_identity()
	_test_save_load_and_secondary_cell_lifecycle()
	if _failed:
		quit(1)
	else:
		print("Building footprint authority test passed. Checks=%d" % _checks)
		quit(0)


func _test_catalog_contract() -> void:
	var terrain = CityTerrainMapScript.new()
	_check(BuildingFootprintsScript.footprint_id_for_size("small") == "single_v1", "small maps to single_v1")
	_check(BuildingFootprintsScript.footprint_id_for_size("medium") == "line_2_east_v1", "medium maps to line_2_east_v1")
	_check(BuildingFootprintsScript.footprint_id_for_size("large") == "line_3_east_v1", "large maps to line_3_east_v1")
	_check(BuildingFootprintsScript.offsets_for_footprint("single_v1") == [Vector2i(0, 0)], "single offsets are exact")
	_check(BuildingFootprintsScript.offsets_for_footprint("line_2_east_v1") == [Vector2i(0, 0), Vector2i(1, 0)], "medium offsets are exact")
	_check(BuildingFootprintsScript.offsets_for_footprint("line_3_east_v1") == [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], "large offsets are exact")

	var anchor_coordinate := Vector2i(3, 4)
	var anchor_tile_id := terrain.tile_id_for_coordinate(anchor_coordinate)
	for size_tier: String in ["small", "medium", "large"]:
		var resolved := BuildingFootprintsScript.resolve_for_size(size_tier, anchor_tile_id, terrain)
		var expected_count: int = int({"small": 1, "medium": 2, "large": 3}[size_tier])
		_check(bool(resolved.get("ok", false)), "%s footprint resolves" % size_tier)
		_check(Array(resolved.get("occupied_tile_ids", [])).size() == expected_count, "%s uses exactly %d total cells" % [size_tier, expected_count])
		for offset_index: int in range(expected_count):
			_check(
				int(resolved.get("occupied_tile_ids", [])[offset_index]) == terrain.tile_id_for_coordinate(anchor_coordinate + Vector2i(offset_index, 0)),
				"%s stable tile id %d follows the eastward coordinate" % [size_tier, offset_index]
			)
	var east_anchor := terrain.tile_id_for_coordinate(Vector2i(9, 4))
	_check(not bool(BuildingFootprintsScript.resolve_for_size("medium", east_anchor, terrain).get("ok", false)), "medium rejects an east-edge anchor")
	_check(not bool(BuildingFootprintsScript.resolve_for_size("large", east_anchor, terrain).get("ok", false)), "large rejects an east-edge anchor")
	var next_to_east_anchor := terrain.tile_id_for_coordinate(Vector2i(8, 4))
	_check(not bool(BuildingFootprintsScript.resolve_for_size("large", next_to_east_anchor, terrain).get("ok", false)), "large rejects an anchor with only two eastward cells available")


func _test_natural_obstacle_feedback_for_every_footprint_cell() -> void:
	var layout_coordinator = VerticalSliceCoordinatorScript.new(20_260_909, 50_000_000)
	var represented_kinds := {}
	for tile_state: Dictionary in layout_coordinator.terrain_map.all_tile_states():
		var base_kind := str(tile_state.get("base_kind", ""))
		if base_kind in NATURAL_OBSTACLE_KINDS:
			represented_kinds[base_kind] = true
			_check(float(tile_state.get("backdrop_coverage", 0.0)) > 0.0, "%s layout obstacle has no backdrop coverage" % base_kind)
			_check(not Array(tile_state.get("backdrop_feature_ids", [])).is_empty(), "%s layout obstacle has no backdrop feature identity" % base_kind)
	for obstacle_kind: String in NATURAL_OBSTACLE_KINDS:
		_check(represented_kinds.has(obstacle_kind), "default 10x10 layout omits %s obstacles" % obstacle_kind)

	for scenario_variant: Variant in FOOTPRINT_SCENARIOS:
		var scenario: Dictionary = scenario_variant
		var cell_count := int(scenario["cell_count"])
		for blocked_offset in cell_count:
			for obstacle_kind: String in NATURAL_OBSTACLE_KINDS:
				var coordinator = VerticalSliceCoordinatorScript.new(20_261_000 + cell_count * 100 + blocked_offset * 10, 50_000_000)
				var available_run := _find_available_flat_run(coordinator, cell_count)
				var label := "%s offset %d %s" % [str(scenario["size"]), blocked_offset, obstacle_kind]
				_check(not available_run.is_empty(), "%s fixture cannot find a flat footprint" % label)
				if available_run.is_empty():
					continue
				var occupied_tiles: Array = available_run["tiles"]
				var blocked_tile_id := int(occupied_tiles[blocked_offset])
				_check(coordinator.terrain_map.configure_tile(blocked_tile_id, obstacle_kind), "%s fixture cannot install its obstacle" % label)
				var balance_before := int(coordinator.treasury_balance())
				var jobs_before: int = coordinator.construction.active_jobs().size()
				var buildings_before: int = coordinator.session.state.buildings.size()
				var sequence_before := int(coordinator.next_building_sequence)
				var rejected: Dictionary = coordinator.start_approved_building(
					str(scenario["display_name"]),
					int(available_run["anchor"]),
					20
				)
				_check(not bool(rejected.get("ok", false)), "%s placement was not rejected" % label)
				_check(str(rejected.get("error", "")) == "terrain_not_flat", "%s rejection reason is not terrain_not_flat" % label)
				_check(int(rejected.get("blocked_tile_id", -1)) == blocked_tile_id, "%s does not identify the exact blocked footprint cell" % label)
				var blocked_terrain: Dictionary = rejected.get("terrain", {})
				_check(str(blocked_terrain.get("base_kind", "")) == obstacle_kind, "%s feedback lost the obstacle kind" % label)
				_check(int(blocked_terrain.get("tile_id", -1)) == blocked_tile_id, "%s terrain feedback identifies the wrong tile" % label)
				_assert_no_placement_mutation(
					coordinator,
					balance_before,
					jobs_before,
					buildings_before,
					sequence_before,
					label
				)


func _test_atomic_placement_and_single_building_identity() -> void:
	var coordinator = VerticalSliceCoordinatorScript.new(20_260_902, 50_000_000)
	var medium_run := _find_available_flat_run(coordinator, 2)
	_check(not medium_run.is_empty(), "a legal medium footprint exists")
	if medium_run.is_empty():
		return
	var medium_anchor := int(medium_run["anchor"])
	var medium_tiles: Array = medium_run["tiles"]
	var building_count_before: int = coordinator.session.state.buildings.size()
	var sequence_before: int = int(coordinator.next_building_sequence)
	var medium_start: Dictionary = coordinator.start_approved_building("學校", medium_anchor, 20)
	_check(bool(medium_start.get("ok", false)), "medium building starts on a legal two-cell footprint")
	_check(Array(medium_start.get("occupied_tile_ids", [])).size() == 2, "medium start returns two occupied cells")
	_check(coordinator.session.state.buildings.size() == building_count_before, "construction does not pre-create partial building records")
	for tile_variant: Variant in medium_tiles:
		_check(not coordinator.active_construction_for_tile(int(tile_variant)).is_empty(), "each medium cell resolves to the one active job")
	_complete_job(coordinator, medium_start)
	_check(coordinator.session.state.buildings.size() == building_count_before + 1, "medium completion creates one building record")
	_check(coordinator.next_building_sequence == sequence_before + 1, "medium completion allocates one building identity")
	var medium_record := coordinator.get_building_by_tile(int(medium_tiles[0]))
	_check(str(medium_record.get("footprint_id", "")) == "line_2_east_v1", "medium record persists its canonical footprint id")
	_check(Array(medium_record.get("occupied_tile_ids", [])) == medium_tiles, "medium record persists both stable tile ids")
	_check(str(coordinator.get_building_by_tile(int(medium_tiles[1])).get("building_id", "")) == str(medium_record.get("building_id", "")), "secondary cell resolves to the anchor building identity")

	var collision_balance: int = int(coordinator.treasury_balance())
	var collision_job_count: int = coordinator.construction.active_jobs().size()
	var collision_building_count: int = coordinator.session.state.buildings.size()
	var collision_sequence: int = int(coordinator.next_building_sequence)
	var building_collision := coordinator.start_approved_building("公園", int(medium_tiles[1]), 5)
	_check(not bool(building_collision.get("ok", false)) and str(building_collision.get("occupancy_kind", "")) == "building", "any occupied building cell rejects the whole placement")
	_assert_no_placement_mutation(coordinator, collision_balance, collision_job_count, collision_building_count, collision_sequence, "building collision")

	var large_run := _find_available_flat_run(coordinator, 3)
	_check(not large_run.is_empty(), "a legal large footprint exists")
	if large_run.is_empty():
		return
	var large_start: Dictionary = coordinator.start_approved_building("體育館", int(large_run["anchor"]), 20)
	_check(bool(large_start.get("ok", false)), "large building starts on a legal three-cell footprint")
	_check(Array(large_start.get("occupied_tile_ids", [])).size() == 3, "large start returns exactly three occupied cells")
	var construction_balance: int = int(coordinator.treasury_balance())
	var construction_jobs: int = coordinator.construction.active_jobs().size()
	var construction_buildings: int = coordinator.session.state.buildings.size()
	var construction_sequence: int = int(coordinator.next_building_sequence)
	var construction_collision := coordinator.start_approved_building("公園", int(large_run["tiles"][1]), 5)
	_check(not bool(construction_collision.get("ok", false)) and str(construction_collision.get("occupancy_kind", "")) == "construction", "any active construction cell rejects the whole placement")
	_assert_no_placement_mutation(coordinator, construction_balance, construction_jobs, construction_buildings, construction_sequence, "construction collision")
	_complete_job(coordinator, large_start)
	_check(coordinator.session.state.buildings.size() == construction_buildings + 1, "large completion still creates one building record")
	var large_record := coordinator.get_building_by_tile(int(large_run["tiles"][2]))
	_check(str(large_record.get("footprint_id", "")) == "line_3_east_v1", "large secondary cell resolves to the three-cell record")

	var terrain_pair := _find_flat_then_nonbuildable_pair(coordinator)
	_check(not terrain_pair.is_empty(), "a flat anchor followed by nonbuildable terrain exists")
	if not terrain_pair.is_empty():
		var terrain_balance: int = int(coordinator.treasury_balance())
		var terrain_jobs: int = coordinator.construction.active_jobs().size()
		var terrain_buildings: int = coordinator.session.state.buildings.size()
		var terrain_sequence: int = int(coordinator.next_building_sequence)
		var terrain_collision := coordinator.start_approved_building("學校", int(terrain_pair["anchor"]), 5)
		_check(not bool(terrain_collision.get("ok", false)) and str(terrain_collision.get("error", "")) == "terrain_not_flat", "one nonbuildable footprint cell rejects the whole placement")
		_assert_no_placement_mutation(coordinator, terrain_balance, terrain_jobs, terrain_buildings, terrain_sequence, "terrain collision")

	var road_run := _find_available_flat_run(coordinator, 2)
	_check(not road_run.is_empty(), "a legal road run exists for transport occupancy")
	if not road_run.is_empty():
		var road_tiles: Array = road_run["tiles"]
		var road_start: Dictionary = coordinator.start_transport_project("road", "build", road_tiles, 5, [])
		_check(bool(road_start.get("ok", false)), "road project starts for transport occupancy counterexample")
		_complete_job(coordinator, road_start)
		_check(coordinator.transport_navigation_blocked_tile_ids().has(int(road_tiles[0])), "completed road owns its navigation tile")
		var transport_balance: int = int(coordinator.treasury_balance())
		var transport_jobs: int = coordinator.construction.active_jobs().size()
		var transport_buildings: int = coordinator.session.state.buildings.size()
		var transport_sequence: int = int(coordinator.next_building_sequence)
		var transport_collision := coordinator.start_approved_building("公園", int(road_tiles[0]), 5)
		_check(not bool(transport_collision.get("ok", false)) and str(transport_collision.get("occupancy_kind", "")) == "transport", "transport occupancy rejects the whole building placement")
		_assert_no_placement_mutation(coordinator, transport_balance, transport_jobs, transport_buildings, transport_sequence, "transport collision")

	var small_run := _find_available_flat_run(coordinator, 1)
	_check(not small_run.is_empty(), "a legal small footprint remains")
	if not small_run.is_empty():
		var small_count: int = coordinator.session.state.buildings.size()
		var small_start: Dictionary = coordinator.start_approved_building("公園", int(small_run["anchor"]), 5)
		_check(bool(small_start.get("ok", false)), "small building starts on one cell")
		_check(Array(small_start.get("occupied_tile_ids", [])).size() == 1, "small start returns exactly one cell")
		_complete_job(coordinator, small_start)
		_check(coordinator.session.state.buildings.size() == small_count + 1, "small completion creates one building record")


func _test_current_existing_registration_contract() -> void:
	var coordinator = VerticalSliceCoordinatorScript.new(20_260_908, 50_000_000)
	var large_run := _find_available_flat_run(coordinator, 3)
	_check(not large_run.is_empty(), "current existing-building registration finds a large footprint")
	if large_run.is_empty():
		return
	var large_tiles: Array = large_run["tiles"]
	var record: Dictionary = coordinator.register_existing_building(
		int(large_run["anchor"]),
		"體育館",
		{},
		BuildingFootprintsScript.LARGE
	)
	_check(not record.is_empty(), "current existing-building registration accepts an explicit valid size")
	_check(str(record.get("blueprint", {}).get("size_tier", "")) == BuildingFootprintsScript.LARGE, "current existing-building blueprint retains its explicit size")
	_check(str(record.get("footprint_id", "")) == BuildingFootprintsScript.LINE_3_EAST_V1, "current existing-building size derives line_3_east_v1")
	_check(Array(record.get("occupied_tile_ids", [])) == large_tiles, "current existing-building registration derives exact occupied cells")
	_check(not record.has(BuildingFootprintsScript.LEGACY_SINGLE_PROVENANCE_FIELD), "current existing-building writer never sets legacy provenance")
	for tile_variant: Variant in large_tiles:
		_check(str(coordinator.get_building_by_tile(int(tile_variant)).get("building_id", "")) == str(record.get("building_id", "")), "current existing-building occupied cells share one identity")


func _test_save_load_and_secondary_cell_lifecycle() -> void:
	var medium_source = VerticalSliceCoordinatorScript.new(20_260_903, 50_000_000)
	var medium_run := _find_available_flat_run(medium_source, 2)
	_check(not medium_run.is_empty(), "medium lifecycle finds a legal footprint")
	if medium_run.is_empty():
		return
	var medium_tiles: Array = medium_run["tiles"]
	var medium_start: Dictionary = medium_source.start_approved_building("學校", int(medium_run["anchor"]), 20)
	_check(bool(medium_start.get("ok", false)), "medium lifecycle starts an active building job")
	if not bool(medium_start.get("ok", false)):
		return
	var medium_job_id := str(medium_start.get("job", {}).get("id", ""))
	var medium_funds := int(medium_source.treasury_balance())
	var medium_job_sequence := int(medium_source.construction.next_job_sequence)
	var medium_building_sequence := int(medium_source.next_building_sequence)
	var medium_job_count: int = medium_source.construction.active_jobs().size()
	_check(medium_source.save_game(MEDIUM_ACTIVE_SAVE_PATH) == OK, "medium active footprint saves")
	var medium_loaded = VerticalSliceCoordinatorScript.new(20_260_904, 1)
	_check(medium_loaded.load_game(MEDIUM_ACTIVE_SAVE_PATH), "medium active footprint loads")
	_check(medium_loaded.treasury_balance() == medium_funds, "medium active load preserves funds")
	_check(medium_loaded.construction.next_job_sequence == medium_job_sequence, "medium active load preserves job sequence")
	_check(medium_loaded.next_building_sequence == medium_building_sequence, "medium active load preserves building sequence")
	_check(medium_loaded.construction.active_jobs().size() == medium_job_count, "medium active load preserves one job identity")
	_check(medium_loaded.session.state.buildings.is_empty(), "medium active load creates no premature economic building identity")
	for tile_variant: Variant in medium_tiles:
		var tile_id := int(tile_variant)
		_check(str(medium_loaded.active_construction_for_tile(tile_id).get("id", "")) == medium_job_id, "medium active load maps every occupied cell to the same job")
		_check(medium_loaded.get_building_by_tile(tile_id).is_empty(), "medium active load keeps occupied job cells out of completed buildings")
	var medium_loaded_job: Dictionary = medium_loaded.construction.jobs.get(medium_job_id, {})
	_check(_as_int_array(medium_loaded_job.get("metadata", {}).get("occupied_tile_ids", [])) == _as_int_array(medium_tiles), "medium active job retains exact occupied ids")
	_complete_job(medium_loaded, {"ok": true, "job": medium_loaded_job})
	_check(medium_loaded.session.state.buildings.size() == 1, "medium completion creates exactly one economic identity")
	var medium_record: Dictionary = medium_loaded.get_building_by_tile(int(medium_tiles[1]))
	var medium_building_id := str(medium_record.get("building_id", ""))
	_check(not medium_building_id.is_empty(), "medium secondary cell resolves after completion")
	var medium_damage: Dictionary = medium_loaded.durability.apply_damage(
		medium_building_id,
		20,
		"test.medium_secondary_repair",
		medium_loaded.game_day()
	)
	_check(bool(medium_damage.get("ok", false)), "medium lifecycle applies repairable damage")
	if bool(medium_damage.get("ok", false)):
		medium_loaded.call("_handle_durability_fact", medium_damage["event"])
	var medium_repair: Dictionary = medium_loaded.repair_building(int(medium_tiles[1]))
	_check(bool(medium_repair.get("ok", false)), "medium repair accepts a secondary occupied cell")
	_check(int(medium_loaded.get_building_by_tile(int(medium_tiles[0])).get("durability", 0)) == 100, "medium secondary repair updates the anchor record")
	_check(medium_loaded.session.state.buildings.size() == 1, "medium repair does not duplicate the economic identity")

	var large_source = VerticalSliceCoordinatorScript.new(20_260_905, 50_000_000)
	var large_run := _find_available_flat_run(large_source, 3)
	_check(not large_run.is_empty(), "large lifecycle finds a legal footprint")
	if large_run.is_empty():
		return
	var large_tiles: Array = large_run["tiles"]
	var large_start: Dictionary = large_source.start_approved_building("體育館", int(large_run["anchor"]), 20)
	_check(bool(large_start.get("ok", false)), "large lifecycle starts an active building job")
	if not bool(large_start.get("ok", false)):
		return
	var large_job_id := str(large_start.get("job", {}).get("id", ""))
	var large_funds := int(large_source.treasury_balance())
	var large_job_sequence := int(large_source.construction.next_job_sequence)
	var large_building_sequence := int(large_source.next_building_sequence)
	_check(large_source.save_game(LARGE_ACTIVE_SAVE_PATH) == OK, "large active footprint saves")
	var large_loaded = VerticalSliceCoordinatorScript.new(20_260_906, 1)
	_check(large_loaded.load_game(LARGE_ACTIVE_SAVE_PATH), "large active footprint loads")
	_check(large_loaded.treasury_balance() == large_funds, "large active load preserves funds")
	_check(large_loaded.construction.next_job_sequence == large_job_sequence, "large active load preserves job sequence")
	_check(large_loaded.next_building_sequence == large_building_sequence, "large active load preserves building sequence")
	_check(large_loaded.session.state.buildings.is_empty(), "large active load creates no premature economic building identity")
	for tile_variant: Variant in large_tiles:
		var tile_id := int(tile_variant)
		_check(str(large_loaded.active_construction_for_tile(tile_id).get("id", "")) == large_job_id, "large active load maps every occupied cell to the same job")
	var large_loaded_job: Dictionary = large_loaded.construction.jobs.get(large_job_id, {})
	_check(_as_int_array(large_loaded_job.get("metadata", {}).get("occupied_tile_ids", [])) == _as_int_array(large_tiles), "large active job retains exact occupied ids")
	_complete_job(large_loaded, {"ok": true, "job": large_loaded_job})
	_check(large_loaded.session.state.buildings.size() == 1, "large completion creates exactly one economic identity")
	_check(large_loaded.save_game(LARGE_COMPLETED_SAVE_PATH) == OK, "completed large footprint saves")
	var large_reloaded = VerticalSliceCoordinatorScript.new(20_260_907, 1)
	_check(large_reloaded.load_game(LARGE_COMPLETED_SAVE_PATH), "completed large footprint reloads")
	var large_secondary := int(large_tiles[2])
	var large_record: Dictionary = large_reloaded.get_building_by_tile(large_secondary)
	var large_building_id := str(large_record.get("building_id", ""))
	_check(not large_building_id.is_empty(), "reloaded large secondary cell resolves to its anchor identity")
	var demolition: Dictionary = large_reloaded.start_demolition(large_secondary, 20)
	_check(bool(demolition.get("ok", false)), "large demolition accepts a secondary occupied cell")
	_check(int(demolition.get("job", {}).get("metadata", {}).get("tile_index", -1)) == int(large_tiles[0]), "large secondary demolition normalizes its job to the anchor")
	for tile_variant: Variant in large_tiles:
		_check(str(large_reloaded.get_building_by_tile(int(tile_variant)).get("building_id", "")) == large_building_id, "large demolition retains all occupied lookups until completion")
	_complete_job(large_reloaded, demolition)
	_check(large_reloaded.session.state.buildings.is_empty(), "large demolition removes the single economic identity")
	for tile_variant: Variant in large_tiles:
		var tile_id := int(tile_variant)
		_check(large_reloaded.get_building_by_tile(tile_id).is_empty(), "large demolition releases every occupied cell")
		_check(large_reloaded.active_construction_for_tile(tile_id).is_empty(), "large demolition leaves no construction occupancy")


func _find_available_flat_run(coordinator, length: int) -> Dictionary:
	var blocked_transport: PackedInt32Array = coordinator.transport_navigation_blocked_tile_ids()
	for row: int in range(coordinator.terrain_map.grid_size().y):
		for column: int in range(coordinator.terrain_map.grid_size().x - length + 1):
			var tiles: Array[int] = []
			var available := true
			for offset: int in range(length):
				var tile_id: int = int(coordinator.terrain_map.tile_id_for_coordinate(Vector2i(column + offset, row)))
				if (
					not coordinator.terrain_map.is_buildable(tile_id)
					or not coordinator.get_building_by_tile(tile_id).is_empty()
					or not coordinator.active_construction_for_tile(tile_id).is_empty()
					or blocked_transport.has(tile_id)
				):
					available = false
					break
				tiles.append(tile_id)
			if available:
				return {"anchor": tiles[0], "tiles": tiles}
	return {}


func _find_flat_then_nonbuildable_pair(coordinator) -> Dictionary:
	for row: int in range(coordinator.terrain_map.grid_size().y):
		for column: int in range(coordinator.terrain_map.grid_size().x - 1):
			var anchor: int = int(coordinator.terrain_map.tile_id_for_coordinate(Vector2i(column, row)))
			var east: int = int(coordinator.terrain_map.tile_id_for_coordinate(Vector2i(column + 1, row)))
			if (
				coordinator.terrain_map.is_buildable(anchor)
				and not coordinator.terrain_map.is_buildable(east)
				and coordinator.get_building_by_tile(anchor).is_empty()
				and coordinator.active_construction_for_tile(anchor).is_empty()
			):
				return {"anchor": anchor, "blocked": east}
	return {}


func _complete_job(coordinator, start_result: Dictionary) -> void:
	if not bool(start_result.get("ok", false)):
		return
	var days := int(start_result.get("job", {}).get("projected_remaining_days", 0))
	coordinator.advance_days(days, CITY_CONTEXT, false)


func _as_int_array(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if value is Array or value is PackedInt32Array or value is PackedInt64Array:
		for item: Variant in value:
			result.append(int(item))
	return result


func _assert_no_placement_mutation(
	coordinator,
	expected_balance: int,
	expected_job_count: int,
	expected_building_count: int,
	expected_sequence: int,
	label: String
) -> void:
	_check(coordinator.treasury_balance() == expected_balance, "%s does not deduct funds" % label)
	_check(coordinator.construction.active_jobs().size() == expected_job_count, "%s does not create a partial job" % label)
	_check(coordinator.session.state.buildings.size() == expected_building_count, "%s does not create a partial building" % label)
	_check(coordinator.next_building_sequence == expected_sequence, "%s does not consume a building identity" % label)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Building footprint authority test failed: %s" % message)
