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
const DEFAULT_FIRST_BLOCKER_OFFSETS := {
	"small": {
		"trees": [0],
		"river_lake": [0],
		"hill_cliff": [0],
	},
	"medium": {
		"trees": [0, 1],
		"river_lake": [0, 1],
		"hill_cliff": [0],
	},
	"large": {
		"trees": [0, 1, 2],
		"river_lake": [0, 1, 2],
		"hill_cliff": [0],
	},
}

var _failed := false
var _checks := 0


class PendingCommandDurability:
	extends RefCounted

	var delegate
	var session
	var metric_name: String
	var metric_value: int
	var operation_id: String
	var queued := false
	var register_calls := 0
	var buildings: Dictionary:
		get:
			return delegate.buildings
	var consecutive_unpaid_months: int:
		get:
			return int(delegate.consecutive_unpaid_months)

	func _init(p_delegate, p_session, p_metric_name: String, p_metric_value: int, p_operation_id: String) -> void:
		delegate = p_delegate
		session = p_session
		metric_name = p_metric_name
		metric_value = p_metric_value
		operation_id = p_operation_id

	func register_building(building_id: String, attributes: Dictionary = {}) -> Dictionary:
		register_calls += 1
		var result: Dictionary = delegate.register_building(building_id, attributes)
		if not queued:
			queued = true
			session.queue_command("metric_change", {
				"metric": metric_name,
				"value": metric_value,
				"reason_tag": "test.pending_before_building_completion",
			}, operation_id)
		return result

	func advance_week(current_day: int) -> Array[Dictionary]:
		return delegate.advance_week(current_day)

	func advance_year(current_day: int) -> Array[Dictionary]:
		return delegate.advance_year(current_day)


func _initialize() -> void:
	_test_catalog_contract()
	_test_natural_obstacle_feedback_for_every_footprint_cell()
	_test_current_existing_registration_contract()
	_test_atomic_placement_and_single_building_identity()
	_test_completion_command_fails_closed()
	_test_coordinator_completion_preflight_atomicity()
	_test_atomic_completion_observer_state()
	_test_pending_command_station_completion()
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
	_test_default_layout_obstacles_reach_placement_authority(layout_coordinator)

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


func _test_default_layout_obstacles_reach_placement_authority(coordinator) -> void:
	# The synthetic matrix below locks every size/offset/kind combination. This
	# bridge independently proves that layout 3's untouched backdrop-derived
	# records reach the same placement authority. Only offsets that can be the
	# first blocker in the frozen map are expected; unavailable combinations
	# remain covered by the synthetic matrix instead of rewriting the layout.
	var grid_size: Vector2i = coordinator.terrain_map.grid_size()
	for scenario_variant: Variant in FOOTPRINT_SCENARIOS:
		var scenario: Dictionary = scenario_variant
		var size_tier := str(scenario["size"])
		var cell_count := int(scenario["cell_count"])
		var observed_offsets := {
			"trees": [],
			"river_lake": [],
			"hill_cliff": [],
		}
		for row: int in range(grid_size.y):
			for column: int in range(grid_size.x - cell_count + 1):
				var anchor_tile_id := int(coordinator.terrain_map.tile_id_for_coordinate(Vector2i(column, row)))
				var resolved: Dictionary = BuildingFootprintsScript.resolve_for_size(size_tier, anchor_tile_id, coordinator.terrain_map)
				if not bool(resolved.get("ok", false)):
					continue
				var occupied_tiles: Array = resolved.get("occupied_tile_ids", [])
				var first_blocked_offset := -1
				var obstacle_kind := ""
				for offset: int in cell_count:
					var tile_id := int(occupied_tiles[offset])
					if coordinator.terrain_map.is_buildable(tile_id):
						continue
					first_blocked_offset = offset
					obstacle_kind = str(coordinator.terrain_map.base_kind(tile_id))
					break
				if obstacle_kind not in NATURAL_OBSTACLE_KINDS:
					continue
				var kind_offsets: Array = observed_offsets[obstacle_kind]
				if kind_offsets.has(first_blocked_offset):
					continue
				kind_offsets.append(first_blocked_offset)
				var blocked_tile_id := int(occupied_tiles[first_blocked_offset])
				var label := "default %s offset %d %s" % [size_tier, first_blocked_offset, obstacle_kind]
				for earlier_offset: int in first_blocked_offset:
					_check(coordinator.terrain_map.is_buildable(int(occupied_tiles[earlier_offset])), "%s has an earlier blocked footprint cell" % label)
				var blocked_state: Dictionary = coordinator.terrain_map.tile_state(blocked_tile_id)
				_check(float(blocked_state.get("backdrop_coverage", 0.0)) > 0.0, "%s is not backed by visible default-layout coverage" % label)
				_check(not Array(blocked_state.get("backdrop_feature_ids", [])).is_empty(), "%s has no default-layout feature identity" % label)
				var balance_before := int(coordinator.treasury_balance())
				var jobs_before: int = coordinator.construction.active_jobs().size()
				var buildings_before: int = coordinator.session.state.buildings.size()
				var sequence_before := int(coordinator.next_building_sequence)
				var rejected: Dictionary = coordinator.start_approved_building(
					str(scenario["display_name"]),
					anchor_tile_id,
					20
				)
				_check(not bool(rejected.get("ok", false)), "%s placement was not rejected" % label)
				_check(str(rejected.get("error", "")) == "terrain_not_flat", "%s rejection reason is not terrain_not_flat" % label)
				_check(int(rejected.get("blocked_tile_id", -1)) == blocked_tile_id, "%s does not report its native first blocker" % label)
				var feedback_terrain: Dictionary = rejected.get("terrain", {})
				_check(str(feedback_terrain.get("base_kind", "")) == obstacle_kind, "%s feedback lost its native obstacle kind" % label)
				_check(int(feedback_terrain.get("tile_id", -1)) == blocked_tile_id, "%s feedback identifies the wrong native tile" % label)
				_assert_no_placement_mutation(
					coordinator,
					balance_before,
					jobs_before,
					buildings_before,
					sequence_before,
					label
				)
		for obstacle_kind: String in NATURAL_OBSTACLE_KINDS:
			var actual_offsets: Array = observed_offsets[obstacle_kind]
			actual_offsets.sort()
			var expected_offsets: Array = DEFAULT_FIRST_BLOCKER_OFFSETS[size_tier][obstacle_kind]
			_check(actual_offsets == expected_offsets, "default %s %s first-blocker offsets changed: expected=%s actual=%s" % [size_tier, obstacle_kind, expected_offsets, actual_offsets])


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


func _test_atomic_completion_observer_state() -> void:
	for scenario_variant: Variant in FOOTPRINT_SCENARIOS:
		var scenario: Dictionary = scenario_variant
		var coordinator = VerticalSliceCoordinatorScript.new(20_261_000 + int(scenario.get("cell_count", 0)), 50_000_000)
		var cell_count := int(scenario.get("cell_count", 0))
		var display_name := str(scenario.get("display_name", ""))
		var run := _find_available_flat_run(coordinator, cell_count)
		_check(not run.is_empty(), "%s atomic completion fixture finds a legal footprint" % display_name)
		if run.is_empty():
			continue
		var started: Dictionary = coordinator.start_approved_building(display_name, int(run.get("anchor", -1)), 20)
		_check(bool(started.get("ok", false)), "%s atomic completion fixture starts" % display_name)
		if not bool(started.get("ok", false)):
			continue
		var job_id := str(started.get("job", {}).get("id", ""))
		var observed_states: Array[Dictionary] = []
		var pending_metric := "test_pending_completion_%d" % cell_count
		var completion_observer := func(event) -> void:
			if str(event.event_type) not in ["building.upserted", "building.construction_completed"]:
				return
			var record: Dictionary = event.payload.get("record", {})
			if str(record.get("building_name", "")) != display_name:
				return
			observed_states.append({
				"event_type": str(event.event_type),
				"building_present": coordinator.session.state.buildings.has(str(record.get("building_id", ""))),
				"construction_present": coordinator.session.state.construction_jobs.has(job_id),
			})
		coordinator.session.domain_event.connect(completion_observer)
		coordinator.drain_ui_events()
		var pending_durability := PendingCommandDurability.new(
			coordinator.durability,
			coordinator.session,
			pending_metric,
			cell_count,
			"test_pending_before_building_completion_%d" % cell_count
		)
		coordinator.durability = pending_durability
		var completion_events := coordinator.advance_days(int(started.get("job", {}).get("projected_remaining_days", 0)), CITY_CONTEXT, false)
		coordinator.durability = pending_durability.delegate
		coordinator.session.domain_event.disconnect(completion_observer)
		_check(pending_durability.queued, "%s completion fixture queues an earlier pending command" % display_name)
		_check(pending_durability.register_calls == 1, "%s completion registers durability exactly once" % display_name)
		_check(int(coordinator.session.state.metrics.get(pending_metric, -1)) == cell_count, "%s earlier pending command is flushed before completion" % display_name)
		_check(_ui_event_count(completion_events, "building_completed") == 1, "%s queued command does not suppress or duplicate completion UI" % display_name)
		_check(not _ui_event_seen(completion_events, "building_completion_failed"), "%s queued command is not mistaken for completion failure" % display_name)
		_check(observed_states.size() == 1, "%s completion emits one observable building authority transition" % display_name)
		if observed_states.size() == 1:
			var observed: Dictionary = observed_states[0]
			_check(bool(observed.get("building_present", false)) and not bool(observed.get("construction_present", true)), "%s completion never exposes completed building authority beside its old construction job: %s" % [display_name, observed])
		for tile_variant: Variant in run.get("tiles", []):
			var tile_id := int(tile_variant)
			_check(coordinator.active_construction_for_tile(tile_id).is_empty(), "%s completion clears construction from occupied tile %d" % [display_name, tile_id])
			_check(not coordinator.get_building_by_tile(tile_id).is_empty(), "%s completion activates occupied tile %d" % [display_name, tile_id])
		_check(not coordinator.session.state.construction_jobs.has(job_id), "%s completion removes its core construction mirror" % display_name)
		var completed_building_count: int = coordinator.session.state.buildings.size()
		var days_to_next_month := 31 - int(coordinator.current_date().get("day", 1))
		var later_events: Array[Dictionary] = coordinator.advance_days(days_to_next_month, CITY_CONTEXT, false)
		_check(not _ui_event_seen(later_events, "building_completed"), "%s later day/month ticks do not repeat completion" % display_name)
		_check(coordinator.session.state.buildings.size() == completed_building_count, "%s later day/month ticks do not duplicate building authority" % display_name)
		var save_path := "user://tests/building_footprint_atomic_%s.json" % str(scenario.get("size", "unknown"))
		_check(coordinator.save_game(save_path) == OK, "%s completed atomic state saves" % display_name)
		var reloaded = VerticalSliceCoordinatorScript.new(20_262_000 + cell_count, 1)
		_check(reloaded.load_game(save_path), "%s completed atomic state reloads" % display_name)
		_check(not reloaded.session.state.construction_jobs.has(job_id), "%s reload does not resurrect the completed construction mirror" % display_name)
		for tile_variant: Variant in run.get("tiles", []):
			var tile_id := int(tile_variant)
			_check(reloaded.active_construction_for_tile(tile_id).is_empty(), "%s reload keeps occupied tile %d out of construction" % [display_name, tile_id])
			_check(not reloaded.get_building_by_tile(tile_id).is_empty(), "%s reload restores occupied building tile %d" % [display_name, tile_id])


func _test_completion_command_fails_closed() -> void:
	var cases := [
		{"label": "active job", "expected": "construction_job_not_completed"},
		{"label": "non-build job", "operation": "demolish", "expected": "construction_job_not_build"},
		{"label": "transport project", "entity_kind": "transport_project", "expected": "construction_job_not_building"},
		{"label": "terrain flatten", "entity_kind": "terrain_flatten", "expected": "construction_job_not_building"},
		{"label": "blueprint mismatch", "record_mismatch": "blueprint", "expected": "building_blueprint_mismatch"},
		{"label": "tile mismatch", "record_mismatch": "tile", "expected": "building_tile_mismatch"},
		{"label": "footprint mismatch", "record_mismatch": "footprint", "expected": "building_footprint_mismatch"},
		{"label": "occupied tiles mismatch", "record_mismatch": "occupied", "expected": "building_occupied_tiles_mismatch"},
		{"label": "fractional tile", "record_mismatch": "tile_fractional", "expected": "building_tile_required"},
		{"label": "fractional anchor", "record_mismatch": "anchor_fractional", "expected": "building_anchor_required"},
		{"label": "numeric tile string", "record_mismatch": "tile_numeric_string", "expected": "building_tile_required"},
		{"label": "invalid anchor string", "record_mismatch": "anchor_invalid_string", "expected": "building_anchor_required"},
		{"label": "boolean tile", "record_mismatch": "tile_boolean", "expected": "building_tile_required"},
		{"label": "NaN tile", "record_mismatch": "tile_nan", "expected": "building_tile_required"},
		{"label": "infinite anchor", "record_mismatch": "anchor_infinite", "expected": "building_anchor_required"},
		{"label": "numeric footprint", "record_mismatch": "footprint_numeric", "expected": "building_footprint_required"},
		{"label": "fractional immutable tile", "job_mismatch": "tile_fractional", "expected": "building_job_tile_required"},
		{"label": "numeric immutable footprint", "job_mismatch": "footprint_numeric", "expected": "building_job_footprint_required"},
	]
	for case_index: int in range(cases.size()):
		var case: Dictionary = cases[case_index]
		var coordinator = VerticalSliceCoordinatorScript.new(20_263_000 + case_index, 50_000_000)
		var run := _find_available_flat_run(coordinator, 2)
		_check(not run.is_empty(), "%s fail-closed fixture finds a legal footprint" % str(case["label"]))
		if run.is_empty():
			continue
		var started: Dictionary = coordinator.start_approved_building("學校", int(run["anchor"]), 20)
		_check(bool(started.get("ok", false)), "%s fail-closed fixture starts" % str(case["label"]))
		if not bool(started.get("ok", false)):
			continue
		var job: Dictionary = Dictionary(started.get("job", {})).duplicate(true)
		var job_id := str(job.get("id", ""))
		if str(case.get("label", "")) != "active job":
			job["status"] = "completed"
			job["remaining_work"] = 0.0
			job["projected_remaining_days"] = 0
			job["elapsed_days"] = maxi(1, int(job.get("elapsed_days", 0)))
			job["completed_day"] = coordinator.game_day()
		if case.has("operation"):
			job["operation"] = str(case["operation"])
		if case.has("entity_kind"):
			var metadata: Dictionary = Dictionary(job.get("metadata", {})).duplicate(true)
			metadata["entity_kind"] = str(case["entity_kind"])
			job["metadata"] = metadata
		match str(case.get("job_mismatch", "")):
			"tile_fractional":
				var metadata: Dictionary = Dictionary(job.get("metadata", {})).duplicate(true)
				metadata["tile_index"] = float(metadata.get("tile_index", -1)) + 0.5
				job["metadata"] = metadata
			"footprint_numeric":
				var metadata: Dictionary = Dictionary(job.get("metadata", {})).duplicate(true)
				metadata["footprint_id"] = 123
				job["metadata"] = metadata
		if str(case.get("label", "")) != "active job":
			coordinator.session.submit_command("upsert_construction", {
				"job_id": job_id,
				"record": job,
				"reason_tag": "test.invalid_completion_job",
			}, "test_invalid_completion_job_%d" % case_index)
		var record := _completion_record_for_job(job, "test_building_%d" % case_index)
		match str(case.get("record_mismatch", "")):
			"blueprint":
				var blueprint: Dictionary = Dictionary(record["blueprint"]).duplicate(true)
				blueprint["version"] = int(blueprint.get("version", 1)) + 1
				record["blueprint"] = blueprint
			"tile":
				record["tile_index"] = int(record.get("tile_index", -1)) + 1
			"footprint":
				record["footprint_id"] = BuildingFootprintsScript.SINGLE_V1
			"occupied":
				record["occupied_tile_ids"] = [int(record.get("anchor_tile_id", -1))]
			"tile_fractional":
				record["tile_index"] = float(record.get("tile_index", -1)) + 0.5
			"anchor_fractional":
				record["anchor_tile_id"] = float(record.get("anchor_tile_id", -1)) + 0.5
			"tile_numeric_string":
				record["tile_index"] = str(record.get("tile_index", -1))
			"anchor_invalid_string":
				record["anchor_tile_id"] = "invalid"
			"tile_boolean":
				record["tile_index"] = true
			"tile_nan":
				record["tile_index"] = NAN
			"anchor_infinite":
				record["anchor_tile_id"] = INF
			"footprint_numeric":
				record["footprint_id"] = 123
		var buildings_before: Dictionary = coordinator.session.state.buildings.duplicate(true)
		var jobs_before: Dictionary = coordinator.session.state.construction_jobs.duplicate(true)
		var rejection_events: Array = coordinator.session.submit_command("complete_building_construction", {
			"building_id": str(record["building_id"]),
			"job_id": job_id,
			"record": record,
			"reason_tag": "test.invalid_completion",
		}, "test_invalid_completion_%d" % case_index)
		_check(rejection_events.size() == 1 and str(rejection_events[0].event_type) == "command.rejected", "%s completion command rejects" % str(case["label"]))
		if rejection_events.size() == 1:
			_check(str(rejection_events[0].reason_tag) == str(case["expected"]), "%s rejection is fail-closed and specific" % str(case["label"]))
		_check(coordinator.session.state.buildings == buildings_before, "%s rejection writes no building authority" % str(case["label"]))
		_check(coordinator.session.state.construction_jobs == jobs_before, "%s rejection writes no construction authority" % str(case["label"]))
	_test_json_integer_scalar_completion()


func _test_json_integer_scalar_completion() -> void:
	var coordinator = VerticalSliceCoordinatorScript.new(20_263_100, 50_000_000)
	var run := _find_available_flat_run(coordinator, 2)
	_check(not run.is_empty(), "JSON integer scalar fixture finds a legal footprint")
	if run.is_empty():
		return
	var started: Dictionary = coordinator.start_approved_building("學校", int(run["anchor"]), 20)
	_check(bool(started.get("ok", false)), "JSON integer scalar fixture starts")
	if not bool(started.get("ok", false)):
		return
	var job: Dictionary = Dictionary(started.get("job", {})).duplicate(true)
	var job_id := str(job.get("id", ""))
	job["status"] = "completed"
	job["remaining_work"] = 0.0
	job["projected_remaining_days"] = 0
	job["completed_day"] = coordinator.game_day()
	var metadata: Dictionary = Dictionary(job.get("metadata", {})).duplicate(true)
	metadata["tile_index"] = float(metadata.get("tile_index", -1))
	metadata["anchor_tile_id"] = float(metadata.get("anchor_tile_id", -1))
	var occupied_as_json_numbers: Array = []
	for tile_value: Variant in metadata.get("occupied_tile_ids", []):
		occupied_as_json_numbers.append(float(tile_value))
	metadata["occupied_tile_ids"] = occupied_as_json_numbers
	job["metadata"] = metadata
	coordinator.session.submit_command("upsert_construction", {
		"job_id": job_id,
		"record": job,
		"reason_tag": "test.json_integer_completion_job",
	}, "test_json_integer_completion_job")
	var record := _completion_record_for_job(job, "test_json_integer_building")
	var completion_events: Array = coordinator.session.submit_command("complete_building_construction", {
		"building_id": str(record["building_id"]),
		"job_id": job_id,
		"record": record,
		"reason_tag": "test.json_integer_completion",
	}, "test_json_integer_completion")
	_check(completion_events.size() == 1 and str(completion_events[0].event_type) == "building.construction_completed", "JSON n.0 integer scalars complete normally")
	_check(coordinator.session.state.buildings.has(str(record["building_id"])), "JSON n.0 completion writes building authority once")
	_check(not coordinator.session.state.construction_jobs.has(job_id), "JSON n.0 completion consumes its construction authority")


func _test_coordinator_completion_preflight_atomicity() -> void:
	var coordinator = VerticalSliceCoordinatorScript.new(20_263_900, 50_000_000)
	var original_run := _find_available_flat_run(coordinator, 1)
	_check(not original_run.is_empty(), "coordinator atomicity fixture finds its original legal footprint")
	if original_run.is_empty():
		return
	var started: Dictionary = coordinator.start_approved_building("住宅", int(original_run["anchor"]), 20)
	_check(bool(started.get("ok", false)), "coordinator atomicity fixture starts")
	if not bool(started.get("ok", false)):
		return
	var completed_job: Dictionary = Dictionary(started.get("job", {})).duplicate(true)
	var job_id := str(completed_job.get("id", ""))
	completed_job["status"] = "completed"
	completed_job["remaining_work"] = 0.0
	completed_job["projected_remaining_days"] = 0
	completed_job["elapsed_days"] = maxi(1, int(completed_job.get("elapsed_days", 0)))
	completed_job["completed_day"] = coordinator.game_day()
	coordinator.construction.jobs[job_id] = completed_job.duplicate(true)
	coordinator.session.submit_command("upsert_construction", {
		"job_id": job_id,
		"record": completed_job,
		"reason_tag": "test.atomicity_completed_job",
	}, "test_atomicity_completed_job")
	var alternate_run := _find_available_flat_run(coordinator, 1, Array(original_run["tiles"]))
	_check(not alternate_run.is_empty(), "coordinator atomicity fixture finds a second legal footprint")
	if alternate_run.is_empty():
		return
	var rejected_job := completed_job.duplicate(true)
	var rejected_metadata: Dictionary = Dictionary(rejected_job.get("metadata", {})).duplicate(true)
	rejected_metadata["tile_index"] = int(alternate_run["anchor"])
	rejected_metadata["anchor_tile_id"] = int(alternate_run["anchor"])
	rejected_metadata["occupied_tile_ids"] = Array(alternate_run["tiles"]).duplicate()
	rejected_job["target_id"] = "tile_%02d" % int(alternate_run["anchor"])
	rejected_job["metadata"] = rejected_metadata
	var footprint_validation := BuildingFootprintsScript.validate_persisted_record(
		rejected_metadata,
		coordinator.terrain_map,
		str(rejected_job.get("blueprint", {}).get("size_tier", ""))
	)
	_check(bool(footprint_validation.get("valid", false)), "coordinator atomicity rejection passes footprint validation first")
	var rejected_record := _completion_record_for_job(rejected_job, "building_candidate")
	_check(
		coordinator.session.kernel.building_completion_validation_error(job_id, rejected_record) == "building_tile_mismatch",
		"coordinator atomicity fixture reaches a specific core completion mismatch"
	)
	coordinator.drain_ui_events()
	var save_hash_before: String = coordinator.deterministic_hash()
	var population_before: Dictionary = coordinator.population.to_dict()
	var durability_before: Dictionary = coordinator.durability.to_dict()
	var construction_before: Dictionary = coordinator.construction.to_dict()
	var core_before: Dictionary = coordinator.session.state.to_dict()
	var transport_before: Dictionary = coordinator.transport.to_dict()
	var transport_session_before: Dictionary = coordinator.transport_planning_session.to_dict()
	var building_sequence_before: int = coordinator.next_building_sequence
	var operation_sequence_before: int = coordinator.next_operation_sequence
	var event_sequence_before: int = coordinator.session.kernel.event_sequence
	var command_sequence_before: int = coordinator.session.kernel.command_sequence
	var rejected := coordinator._complete_building_construction(rejected_job, rejected_metadata)
	var rejection_events: Array[Dictionary] = coordinator.drain_ui_events()
	var save_hash_after: String = coordinator.deterministic_hash()
	_check(not rejected, "coordinator rejects the core completion mismatch")
	_check(_ui_event_count(rejection_events, "building_completion_failed") == 1, "coordinator emits one completion failure")
	if _ui_event_count(rejection_events, "building_completion_failed") == 1:
		_check(str(rejection_events[0].get("payload", {}).get("error", "")) == "building_tile_mismatch", "coordinator exposes the core mismatch reason")
	_check(coordinator.population.to_dict() == population_before, "rejected completion preserves canonical population")
	_check(coordinator.durability.to_dict() == durability_before, "rejected completion preserves durability authority")
	_check(coordinator.construction.to_dict() == construction_before, "rejected completion preserves construction authority")
	_check(coordinator.session.state.to_dict() == core_before, "rejected completion preserves CityState authority and resident ownership")
	_check(coordinator.transport.to_dict() == transport_before, "rejected completion preserves transport authority")
	_check(coordinator.transport_planning_session.to_dict() == transport_session_before, "rejected completion preserves transport planning state")
	_check(coordinator.next_building_sequence == building_sequence_before, "rejected completion consumes no building identity")
	_check(coordinator.next_operation_sequence == operation_sequence_before, "rejected completion consumes no coordinator operation")
	_check(coordinator.session.kernel.event_sequence == event_sequence_before, "rejected completion emits no domain event")
	_check(coordinator.session.kernel.command_sequence == command_sequence_before, "rejected completion submits no core command")
	_check(save_hash_after == save_hash_before, "rejected completion preserves the full save-visible envelope")
	var original_metadata: Dictionary = Dictionary(completed_job.get("metadata", {})).duplicate(true)
	var population_count_before_success: int = coordinator.population.population_count()
	var completed := coordinator._complete_building_construction(completed_job, original_metadata)
	var completion_events: Array[Dictionary] = coordinator.drain_ui_events()
	_check(completed, "validated coordinator completion still succeeds")
	_check(_ui_event_count(completion_events, "building_completed") == 1, "validated completion emits one success event")
	_check(not _ui_event_seen(completion_events, "building_completion_failed"), "validated completion emits no failure event")
	_check(coordinator.session.state.buildings.size() == 1, "validated completion writes one building authority")
	_check(not coordinator.session.state.construction_jobs.has(job_id), "validated completion consumes its core construction authority")
	_check(coordinator.population.population_count() > population_count_before_success, "validated completion applies its population effect")
	var completed_id := str(coordinator.session.state.buildings.keys()[0])
	_check(not coordinator.durability.get_building(completed_id).is_empty(), "validated completion registers durability")


func _test_pending_command_station_completion() -> void:
	var coordinator = VerticalSliceCoordinatorScript.new(20_264_000, 50_000_000)
	var run := _find_available_flat_run(coordinator, 1)
	_check(not run.is_empty(), "station pending-command fixture finds a legal footprint")
	if run.is_empty():
		return
	var started: Dictionary = coordinator.start_approved_building("公車站", int(run["anchor"]), 20)
	_check(bool(started.get("ok", false)), "station pending-command fixture starts")
	if not bool(started.get("ok", false)):
		return
	coordinator.drain_ui_events()
	var pending_durability := PendingCommandDurability.new(
		coordinator.durability,
		coordinator.session,
		"test_station_pending_completion",
		1,
		"test_station_pending_completion"
	)
	coordinator.durability = pending_durability
	var completion_events := coordinator.advance_days(int(started.get("job", {}).get("projected_remaining_days", 0)), CITY_CONTEXT, false)
	coordinator.durability = pending_durability.delegate
	_check(pending_durability.queued, "station completion queues an earlier pending command")
	_check(pending_durability.register_calls == 1, "station completion registers durability exactly once")
	_check(_ui_event_count(completion_events, "building_completed") == 1, "station completion emits exactly one observable building completion")
	_check(not _ui_event_seen(completion_events, "building_completion_failed"), "station pending command is not mistaken for completion failure")
	var station_record: Dictionary = coordinator.get_building_by_tile(int(run["anchor"]))
	var station_id := str(station_record.get("building_id", ""))
	_check(not station_id.is_empty(), "station completion creates its building authority")
	_check(coordinator.transport.stations.has(station_id), "station completion registers transport authority exactly once")
	var station_count: int = coordinator.transport.stations.size()
	var later_events: Array[Dictionary] = coordinator.advance_days(1, CITY_CONTEXT, false)
	_check(_ui_event_count(later_events, "building_completed") == 0, "later station tick does not repeat completion UI")
	_check(coordinator.transport.stations.size() == station_count, "later station tick does not duplicate transport authority")


func _completion_record_for_job(job: Dictionary, building_id: String) -> Dictionary:
	var metadata: Dictionary = job.get("metadata", {})
	var blueprint: Dictionary = job.get("blueprint", {})
	return {
		"building_id": building_id,
		"definition_id": str(blueprint.get("building_id", "")),
		"building_name": str(metadata.get("building_name", "")),
		"tile_index": int(metadata.get("tile_index", -1)),
		"anchor_tile_id": int(metadata.get("anchor_tile_id", -1)),
		"footprint_id": str(metadata.get("footprint_id", "")),
		"occupied_tile_ids": Array(metadata.get("occupied_tile_ids", [])).duplicate(),
		"status": "active",
		"durability": 100,
		"blueprint": blueprint.duplicate(true),
	}


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


func _find_available_flat_run(coordinator, length: int, excluded_tile_ids: Array = []) -> Dictionary:
	var blocked_transport: PackedInt32Array = coordinator.transport_navigation_blocked_tile_ids()
	for row: int in range(coordinator.terrain_map.grid_size().y):
		for column: int in range(coordinator.terrain_map.grid_size().x - length + 1):
			var tiles: Array[int] = []
			var available := true
			for offset: int in range(length):
				var tile_id: int = int(coordinator.terrain_map.tile_id_for_coordinate(Vector2i(column + offset, row)))
				if (
					not coordinator.terrain_map.is_buildable(tile_id)
					or excluded_tile_ids.has(tile_id)
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


func _ui_event_seen(events: Array[Dictionary], event_type: String) -> bool:
	for event: Dictionary in events:
		if str(event.get("type", "")) == event_type:
			return true
	return false


func _ui_event_count(events: Array[Dictionary], event_type: String) -> int:
	var count := 0
	for event: Dictionary in events:
		if str(event.get("type", "")) == event_type:
			count += 1
	return count


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
