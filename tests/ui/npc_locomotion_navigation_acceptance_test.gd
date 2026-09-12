extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const TEST_SAVE_PATH := "res://tests/.npc_locomotion_navigation_acceptance.json"
const SIMULATION_DELTA := 1.0 / 30.0
const LOCOMOTION_FRAMES := 360
const DYNAMIC_REPLAN_FRAMES := 120
const NO_ROUTE_WAIT_FRAMES := 60
const PATH_SAMPLE_STEP := 4.0
const MAX_POSITION_SLACK := 1.5
const DYNAMIC_TILE_INDEX := 987
const STOP_SETTLE_GRACE_FRAMES := 6
const STOP_NEUTRAL_FRAMES: Array[int] = [0, 2]

const REQUIRED_NAVIGATION_METHODS := [
	"is_position_walkable",
	"is_segment_walkable",
	"static_classification_at",
	"nearest_safe_position",
	"find_path",
	"set_building_blocker",
	"set_construction_blocker",
	"clear_dynamic_blockers",
	"get_debug_static_polygons",
	"get_debug_dynamic_polygons",
	"get_debug_points",
	"get_last_path_trace",
	"get_last_query_diagnostics",
]
const REQUIRED_MAIN_DEBUG_METHODS := [
	"get_npc_navigation_grid",
	"get_npc_acceptance_snapshot",
	"debug_step_npc_simulation",
	"debug_set_npc_destination",
	"debug_force_npc_repath",
]
const REQUIRED_SNAPSHOT_FIELDS := [
	"record_id",
	"position",
	"feet_position",
	"visible",
	"state",
	"velocity",
	"speed",
	"travelled_distance",
	"cycle_phase",
	"frame_index",
	"is_walking",
	"actor_is_walking",
	"stop_settle_remaining",
	"stop_target_frame",
	"render_direction",
	"opaque_body_draws",
	"path",
	"path_index",
	"destination",
	"replan_count",
	"blocked_waiting",
]

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_save()
	var standalone_grid := _validate_navigation_grid_contract()
	if standalone_grid == null:
		await _finish(null)
		return

	root.content_scale_size = Vector2i(1440, 900)
	root.size = Vector2i(1440, 900)
	var main_scene = load("res://scenes/Main.tscn") as PackedScene
	_check(main_scene != null, "Main.tscn could not be loaded")
	if main_scene == null:
		await _finish(null)
		return
	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.start_save_path = TEST_SAVE_PATH
	main.start_screen.animation_duration = 0.04
	main.start_screen.new_game_button.emit_signal("pressed")
	for _frame in 120:
		await process_frame
		if not main.start_screen.is_loading():
			break
	_check(bool(main.get("_game_started")) and not main.start_screen.visible, "new game did not reach the map")
	if not bool(main.get("_game_started")):
		await _finish(main)
		return

	for method_name: String in REQUIRED_MAIN_DEBUG_METHODS:
		_check(main.has_method(method_name), "Main integration is waiting for debug API `%s`" % method_name)
	if REQUIRED_MAIN_DEBUG_METHODS.any(func(method_name: String) -> bool: return not main.has_method(method_name)):
		await _finish(main)
		return

	var main_grid_variant: Variant = main.call("get_npc_navigation_grid")
	_check(main_grid_variant is Object and main_grid_variant != null, "Main did not expose its CityNavigationGrid")
	if not main_grid_variant is Object or main_grid_variant == null:
		await _finish(main)
		return
	var main_grid: Object = main_grid_variant
	_validate_navigation_methods(main_grid, "Main navigation grid")

	var vertical_slice: Object = main.get("vertical_slice")
	var population: Object = vertical_slice.get("population") if vertical_slice != null else null
	_check(population != null, "authoritative PopulationSystem is unavailable")
	if population == null:
		_finish(main)
		return
	_check(int(population.call("population_count")) == 300, "authoritative population is not 300 before locomotion")
	var stable_hash_before := str(population.call("stable_hash"))
	_validate_proxy_authority(main, population)

	# Stop Main's ordinary process loop so this acceptance trace advances in
	# deterministic 1/30-second increments through the dedicated step helper or
	# the established update method.
	main.set_process(false)
	await _validate_distance_driven_locomotion(main, main_grid)
	await _validate_dynamic_building_replan(main, main_grid)
	await _validate_no_route_waiting(main, main_grid)

	_check(int(population.call("population_count")) == 300, "navigation/animation changed the authoritative population")
	_check(str(population.call("stable_hash")) == stable_hash_before, "navigation/animation mutated authoritative NPC data")
	await _finish(main)


func _validate_navigation_grid_contract() -> Object:
	var navigation_script = load("res://scripts/world/city_navigation_grid.gd")
	_check(navigation_script != null, "CityNavigationGrid script is missing")
	if navigation_script == null:
		return null
	var grid: Object = navigation_script.new()
	_validate_navigation_methods(grid, "standalone CityNavigationGrid")

	var static_polygons: Array = grid.call("get_debug_static_polygons")
	_check(static_polygons.size() >= 3, "static walkability mask has too few polygons")
	var represented_kinds := {}
	for polygon_variant: Variant in static_polygons:
		_check(polygon_variant is Dictionary, "static polygon debug record is not a Dictionary")
		if not polygon_variant is Dictionary:
			continue
		var polygon: Dictionary = polygon_variant
		var kind := str(polygon.get("kind", ""))
		var points := _path_from_variant(polygon.get("points", PackedVector2Array()))
		_check(kind in ["river_lake", "hill_cliff", "trees_scenery"], "unknown static obstacle classification: %s" % kind)
		_check(points.size() >= 3, "static polygon %s has fewer than three points" % str(polygon.get("id", kind)))
		if points.size() < 3:
			continue
		represented_kinds[kind] = true
		var representative := _polygon_representative(points)
		var classifications: PackedStringArray = grid.call("static_classification_at", representative)
		_check(kind in classifications, "static polygon %s cannot be classified at its representative point" % str(polygon.get("id", kind)))
		_check(not bool(grid.call("is_position_walkable", representative)), "static polygon %s is incorrectly walkable" % str(polygon.get("id", kind)))
	for required_kind: String in ["river_lake", "hill_cliff", "trees_scenery"]:
		_check(represented_kinds.has(required_kind), "static navigation omits %s obstacles" % required_kind)

	# Select only from bounded meadow pairs around the frozen north-central lake.
	# Selection checks endpoint walkability plus the blocked direct segment and
	# river_lake classification; it never asks pathfinding whether a pair works.
	var static_fixture: Dictionary = _find_static_lake_detour_fixture(grid)
	_check(not static_fixture.is_empty(), "static lake detour fixture finds walkable endpoints with a lake-blocked direct segment")
	if static_fixture.is_empty():
		return grid
	var static_start: Vector2 = Vector2(static_fixture.get("start", Vector2.ZERO))
	var static_target: Vector2 = Vector2(static_fixture.get("target", Vector2.ZERO))
	_check(bool(grid.call("is_position_walkable", static_start)), "static detour fixture start is not walkable")
	_check(bool(grid.call("is_position_walkable", static_target)), "static detour fixture target is not walkable")
	_check(not bool(grid.call("is_segment_walkable", static_start, static_target)), "static detour fixture no longer crosses the river/lake mask")
	_check(_segment_crosses_static_kind(grid, static_start, static_target, "river_lake"), "static detour fixture direct segment no longer crosses the intended river/lake geometry")
	var static_path: PackedVector2Array = grid.call("find_path", static_start, static_target, false)
	_check(not static_path.is_empty(), "navigation could not route around the river/lake")
	_check(str((grid.call("get_last_query_diagnostics") as Dictionary).get("status", "")) == "ok", "static detour did not report status=ok")
	_validate_path_clearance(grid, static_path, "static river/lake detour")

	# Dynamic blockers must immediately affect A* solidity and path smoothing.
	grid.call("clear_dynamic_blockers")
	var dynamic_start := Vector2(385, 445)
	var dynamic_target := Vector2(805, 445)
	var blocker_center := Vector2(595, 445)
	var before_path: PackedVector2Array = grid.call("find_path", dynamic_start, dynamic_target, false)
	_check(not before_path.is_empty(), "dynamic fixture has no baseline path")
	grid.call("set_building_blocker", DYNAMIC_TILE_INDEX, blocker_center, true, Vector2(64, 40))
	_check(not bool(grid.call("is_position_walkable", blocker_center)), "building center remains walkable")
	var dynamic_records: Array = grid.call("get_debug_dynamic_polygons")
	_check(dynamic_records.size() == 1, "building blocker was not registered exactly once")
	if not dynamic_records.is_empty():
		_check(str((dynamic_records[0] as Dictionary).get("kind", "")) == "building", "dynamic blocker kind is not building")
	var after_path: PackedVector2Array = grid.call("find_path", dynamic_start, dynamic_target, false)
	_check(not after_path.is_empty(), "navigation could not detour around a building")
	_validate_path_clearance(grid, after_path, "dynamic building detour")
	_check(_path_length(after_path) > _path_length(before_path) + 1.0, "building blocker did not produce a meaningful detour")

	grid.call("set_building_blocker", DYNAMIC_TILE_INDEX, blocker_center, false, Vector2(64, 40))
	grid.call("set_construction_blocker", DYNAMIC_TILE_INDEX, blocker_center, true, Vector2(64, 40))
	dynamic_records = grid.call("get_debug_dynamic_polygons")
	_check(dynamic_records.size() == 1 and str((dynamic_records[0] as Dictionary).get("kind", "")) == "construction", "construction blocker was not registered independently")
	grid.call("clear_dynamic_blockers")
	_check(bool(grid.call("is_position_walkable", blocker_center)), "clearing dynamic blockers did not restore the meadow")
	return grid


func _validate_navigation_methods(grid: Object, label: String) -> void:
	for method_name: String in REQUIRED_NAVIGATION_METHODS:
		_check(grid.has_method(method_name), "%s is missing public API `%s`" % [label, method_name])


func _validate_proxy_authority(main: Object, population: Object) -> void:
	var visible_count := 0
	var record_ids := {}
	for index in 24:
		var snapshot := _npc_snapshot(main, index)
		_validate_snapshot_schema(snapshot, index)
		var record_id := str(snapshot.get("record_id", ""))
		_check(not record_id.is_empty(), "visible proxy %d has no canonical record_id" % index)
		_check(not record_ids.has(record_id), "duplicate visible proxy record_id: %s" % record_id)
		record_ids[record_id] = true
		_check(population.call("get_record", record_id) != null, "visible proxy %d is not backed by PopulationSystem: %s" % [index, record_id])
		if bool(snapshot.get("visible", false)):
			visible_count += 1
	_check(visible_count == 24, "expected 24 visible proxies, got %d" % visible_count)
	_check(record_ids.size() == 24, "visible proxy IDs are not unique")


func _validate_distance_driven_locomotion(main: Object, grid: Object) -> void:
	var previous_positions: Array[Vector2] = []
	var start_travelled: Array[float] = []
	var measured_travel: Array[float] = []
	var seen_frames: Array[Dictionary] = []
	var stopped_frame_counts: Array[int] = []
	var stopped_frame_changes: Array[int] = []
	var last_stopped_frames: Array[int] = []
	var last_stopped_distances: Array[float] = []
	var last_stopped_phases: Array[float] = []
	for index in 24:
		var snapshot := _npc_snapshot(main, index)
		previous_positions.append(Vector2(snapshot.get("position", Vector2.ZERO)))
		start_travelled.append(float(snapshot.get("travelled_distance", 0.0)))
		measured_travel.append(0.0)
		seen_frames.append({int(snapshot.get("frame_index", 0)): true})
		stopped_frame_counts.append(0)
		stopped_frame_changes.append(0)
		last_stopped_frames.append(-1)
		last_stopped_distances.append(-1.0)
		last_stopped_phases.append(-1.0)

	for frame in LOCOMOTION_FRAMES:
		_step_npcs(main, SIMULATION_DELTA)
		for index in 24:
			var snapshot := _npc_snapshot(main, index)
			var position := Vector2(snapshot.get("position", Vector2.ZERO))
			var step_distance := previous_positions[index].distance_to(position)
			var speed := maxf(float(snapshot.get("speed", 0.0)), Vector2(snapshot.get("velocity", Vector2.ZERO)).length())
			_check(step_distance <= speed * SIMULATION_DELTA + MAX_POSITION_SLACK, "NPC %d teleported %.2f px in locomotion frame %d" % [index, step_distance, frame])
			measured_travel[index] += step_distance
			previous_positions[index] = position
			seen_frames[index][int(snapshot.get("frame_index", 0))] = true
			var feet := Vector2(snapshot.get("feet_position", position))
			_check(bool(grid.call("is_position_walkable", feet)), "NPC %d entered static/dynamic scenery at frame %d: %s" % [index, frame, grid.call("static_classification_at", feet)])
			if not bool(snapshot.get("visible", false)):
				_check(false, "NPC %d became hidden during ordinary locomotion" % index)
			_check(int(snapshot.get("opaque_body_draws", -1)) == 1, "NPC %d renders more than one opaque body" % index)
			if not bool(snapshot.get("blocked_waiting", false)) and Vector2(snapshot.get("velocity", Vector2.ZERO)).is_zero_approx():
				var stopped_frame := int(snapshot.get("frame_index", -1))
				var stopped_distance := float(snapshot.get("travelled_distance", -1.0))
				var stopped_phase := float(snapshot.get("cycle_phase", -1.0))
				var settle_remaining := float(snapshot.get("stop_settle_remaining", -1.0))
				stopped_frame_counts[index] += 1
				_check(not bool(snapshot.get("is_walking", true)), "stopped NPC %d remains walking in the main simulation" % index)
				_check(not bool(snapshot.get("actor_is_walking", true)), "stopped NPC %d remains walking in the actor rig" % index)
				if last_stopped_frames[index] >= 0 and stopped_frame != last_stopped_frames[index]:
					stopped_frame_changes[index] += 1
				if last_stopped_distances[index] >= 0.0:
					_check(absf(stopped_distance - last_stopped_distances[index]) <= 0.001, "stopped NPC %d advances travelled distance" % index)
					_check(_circular_distance(stopped_phase, last_stopped_phases[index]) <= 0.001, "stopped NPC %d advances walk phase" % index)
				last_stopped_frames[index] = stopped_frame
				last_stopped_distances[index] = stopped_distance
				last_stopped_phases[index] = stopped_phase
				_check(stopped_frame_changes[index] <= 1, "stopped NPC %d keeps cycling walk frames (%d changes)" % [index, stopped_frame_changes[index]])
				_check(STOP_NEUTRAL_FRAMES.has(int(snapshot.get("stop_target_frame", -1))), "stopped NPC %d has a non-neutral settle target" % index)
				if settle_remaining <= 0.0:
					_check(STOP_NEUTRAL_FRAMES.has(stopped_frame), "stopped NPC %d did not settle on a neutral frame: %d" % [index, stopped_frame])
				if stopped_frame_counts[index] > STOP_SETTLE_GRACE_FRAMES:
					_check(settle_remaining <= 0.0, "stopped NPC %d did not finish its short settle transition" % index)
			else:
				stopped_frame_counts[index] = 0
				stopped_frame_changes[index] = 0
				last_stopped_frames[index] = -1
				last_stopped_distances[index] = -1.0
				last_stopped_phases[index] = -1.0
			if frame % 30 == 0:
				_validate_path_clearance(grid, _path_from_variant(snapshot.get("path", PackedVector2Array())), "NPC %d active path" % index, true)

	var meaningful_travel_count := 0
	var full_frame_cycle_count := 0
	for index in 24:
		var snapshot := _npc_snapshot(main, index)
		var reported_delta := float(snapshot.get("travelled_distance", 0.0)) - start_travelled[index]
		_check(absf(reported_delta - measured_travel[index]) <= 2.0, "NPC %d travelled_distance %.2f disagrees with measured %.2f" % [index, reported_delta, measured_travel[index]])
		if measured_travel[index] >= 12.0:
			meaningful_travel_count += 1
		if seen_frames[index].size() == 4:
			full_frame_cycle_count += 1
	_check(meaningful_travel_count >= 16, "too few NPCs made visible progress: %d/24" % meaningful_travel_count)
	_check(full_frame_cycle_count >= 16, "too few NPCs exercised all four distance-driven frames: %d/24" % full_frame_cycle_count)


func _validate_dynamic_building_replan(main: Object, grid: Object) -> void:
	grid.call("clear_dynamic_blockers")
	var npc_index := 0
	var initial := _npc_snapshot(main, npc_index)
	var safe_target: Variant = _choose_far_walkable_target(grid, Vector2(initial.get("feet_position", Vector2.ZERO)))
	_check(safe_target != null, "could not find a far walkable destination for dynamic replan")
	if safe_target == null:
		return
	_check(bool(main.call("debug_set_npc_destination", npc_index, safe_target, true)), "Main rejected a valid NPC destination")
	for _frame in 12:
		_step_npcs(main, SIMULATION_DELTA)
	var before := _npc_snapshot(main, npc_index)
	var active_path := _path_from_variant(before.get("path", PackedVector2Array()))
	_check(active_path.size() >= 2, "NPC has no active path before dynamic blocker insertion")
	if active_path.size() < 2:
		return
	var blocker_center := _point_along_path(active_path, Vector2(before.get("feet_position", Vector2.ZERO)), 72.0)
	grid.call("set_building_blocker", DYNAMIC_TILE_INDEX, blocker_center, true, Vector2(42, 26))
	var record_id_before := str(before.get("record_id", ""))
	var position_before := Vector2(before.get("position", Vector2.ZERO))
	var replan_before := int(before.get("replan_count", 0))
	_check(bool(main.call("debug_force_npc_repath", npc_index, true)), "NPC failed to replan around a newly placed building")
	var replanned := _npc_snapshot(main, npc_index)
	_check(str(replanned.get("record_id", "")) == record_id_before, "building replan changed the canonical NPC")
	_check(bool(replanned.get("visible", false)), "building replan hid the NPC")
	_check(Vector2(replanned.get("position", Vector2.ZERO)).distance_to(position_before) <= MAX_POSITION_SLACK, "building replan teleported the NPC before movement resumed")
	_check(int(replanned.get("replan_count", 0)) > replan_before, "building replan counter did not advance")
	_validate_path_clearance(grid, _path_from_variant(replanned.get("path", PackedVector2Array())), "replanned building path")

	var previous_position := Vector2(replanned.get("position", Vector2.ZERO))
	var travel_after_replan := 0.0
	var final_replan_snapshot := replanned
	for frame in DYNAMIC_REPLAN_FRAMES:
		_step_npcs(main, SIMULATION_DELTA)
		var snapshot := _npc_snapshot(main, npc_index)
		final_replan_snapshot = snapshot
		var position := Vector2(snapshot.get("position", Vector2.ZERO))
		var step_distance := previous_position.distance_to(position)
		var speed := maxf(float(snapshot.get("speed", 0.0)), Vector2(snapshot.get("velocity", Vector2.ZERO)).length())
		_check(step_distance <= speed * SIMULATION_DELTA + MAX_POSITION_SLACK, "NPC teleported %.2f px after building replan frame %d" % [step_distance, frame])
		_check(str(snapshot.get("record_id", "")) == record_id_before, "NPC identity changed after building replan")
		_check(bool(snapshot.get("visible", false)), "NPC disappeared after building replan")
		_check(bool(grid.call("is_position_walkable", Vector2(snapshot.get("feet_position", position)))), "NPC entered the new building blocker")
		travel_after_replan += step_distance
		previous_position = position
	_check(
		travel_after_replan >= 8.0,
		"NPC did not resume progress after building replan: travel=%.2f state=%s blocked=%s path=%d/%d velocity=%s" % [
			travel_after_replan,
			str(final_replan_snapshot.get("state", "")),
			str(final_replan_snapshot.get("blocked_waiting", false)),
			int(final_replan_snapshot.get("path_index", -1)),
			_path_from_variant(final_replan_snapshot.get("path", PackedVector2Array())).size(),
			str(final_replan_snapshot.get("velocity", Vector2.ZERO)),
		]
	)
	grid.call("set_building_blocker", DYNAMIC_TILE_INDEX, blocker_center, false, Vector2(42, 26))


func _validate_no_route_waiting(main: Object, grid: Object) -> void:
	grid.call("clear_dynamic_blockers")
	var npc_index := 0
	var before := _npc_snapshot(main, npc_index)
	var record_id := str(before.get("record_id", ""))
	var position := Vector2(before.get("position", Vector2.ZERO))
	var accepted := bool(main.call("debug_set_npc_destination", npc_index, Vector2(-500, -500), false))
	_check(not accepted, "out-of-stage destination unexpectedly produced a route without endpoint snapping")
	var waiting := _npc_snapshot(main, npc_index)
	_check(bool(waiting.get("blocked_waiting", false)), "no-route NPC did not enter blocked_waiting state")
	_check(str(waiting.get("state", "")) == "waiting", "no-route NPC state is not waiting")
	var last_stopped_frame := -1
	var stopped_frame_changes := 0
	var last_stopped_distance := -1.0
	var last_stopped_phase := -1.0
	for wait_frame in NO_ROUTE_WAIT_FRAMES:
		_step_npcs(main, SIMULATION_DELTA)
		var snapshot := _npc_snapshot(main, npc_index)
		_check(str(snapshot.get("record_id", "")) == record_id, "no-route wait changed NPC identity")
		_check(bool(snapshot.get("visible", false)), "no-route wait hid the NPC")
		_check(Vector2(snapshot.get("position", Vector2.ZERO)).distance_to(position) <= 0.5, "no-route NPC moved or teleported instead of waiting")
		var stopped_frame := int(snapshot.get("frame_index", -1))
		var stopped_distance := float(snapshot.get("travelled_distance", -1.0))
		var stopped_phase := float(snapshot.get("cycle_phase", -1.0))
		var settle_remaining := float(snapshot.get("stop_settle_remaining", -1.0))
		_check(not bool(snapshot.get("is_walking", true)), "no-route NPC remains walking in the main simulation")
		_check(not bool(snapshot.get("actor_is_walking", true)), "no-route NPC remains walking in the actor rig")
		_check(int(snapshot.get("opaque_body_draws", -1)) == 1, "no-route NPC renders more than one opaque body")
		if last_stopped_frame >= 0 and stopped_frame != last_stopped_frame:
			stopped_frame_changes += 1
		if last_stopped_distance >= 0.0:
			_check(absf(stopped_distance - last_stopped_distance) <= 0.001, "no-route NPC advances travelled distance while waiting")
			_check(_circular_distance(stopped_phase, last_stopped_phase) <= 0.001, "no-route NPC advances walk phase while waiting")
		last_stopped_frame = stopped_frame
		last_stopped_distance = stopped_distance
		last_stopped_phase = stopped_phase
		_check(stopped_frame_changes <= 1, "no-route NPC keeps cycling walk frames while waiting")
		_check(STOP_NEUTRAL_FRAMES.has(int(snapshot.get("stop_target_frame", -1))), "no-route NPC has a non-neutral settle target")
		if settle_remaining <= 0.0:
			_check(STOP_NEUTRAL_FRAMES.has(stopped_frame), "no-route NPC did not settle on a neutral frame: %d" % stopped_frame)
		if wait_frame >= STOP_SETTLE_GRACE_FRAMES:
			_check(settle_remaining <= 0.0, "no-route NPC did not finish its short settle transition")


func _npc_snapshot(main: Object, index: int) -> Dictionary:
	var snapshot_variant: Variant = main.call("get_npc_acceptance_snapshot", index)
	if snapshot_variant is Dictionary:
		return snapshot_variant
	_check(false, "get_npc_acceptance_snapshot(%d) did not return a Dictionary" % index)
	return {}


func _validate_snapshot_schema(snapshot: Dictionary, index: int) -> void:
	for field_name: String in REQUIRED_SNAPSHOT_FIELDS:
		_check(snapshot.has(field_name), "NPC acceptance snapshot %d omits `%s`" % [index, field_name])
	_check(snapshot.get("position", null) is Vector2, "NPC snapshot %d position is not Vector2" % index)
	_check(snapshot.get("feet_position", null) is Vector2, "NPC snapshot %d feet_position is not Vector2" % index)
	_check(snapshot.get("velocity", null) is Vector2, "NPC snapshot %d velocity is not Vector2" % index)
	_check(snapshot.get("path", null) is PackedVector2Array or snapshot.get("path", null) is Array, "NPC snapshot %d path is not a point array" % index)


func _step_npcs(main: Object, delta: float) -> void:
	main.call("debug_step_npc_simulation", delta)


func _validate_path_clearance(grid: Object, path: PackedVector2Array, label: String, allow_empty: bool = false) -> void:
	if path.is_empty():
		_check(allow_empty, "%s is empty" % label)
		return
	for point: Vector2 in path:
		_check(bool(grid.call("is_position_walkable", point)), "%s waypoint is not walkable: %s" % [label, point])
	for index in range(path.size() - 1):
		var start := path[index]
		var finish := path[index + 1]
		var sample_count := maxi(1, ceili(start.distance_to(finish) / PATH_SAMPLE_STEP))
		for sample_index in range(sample_count + 1):
			var sample := start.lerp(finish, float(sample_index) / float(sample_count))
			_check(bool(grid.call("is_position_walkable", sample)), "%s cuts an obstacle between waypoints %d and %d at %s" % [label, index, index + 1, sample])


func _polygon_representative(points: PackedVector2Array) -> Vector2:
	var centroid := Vector2.ZERO
	for point: Vector2 in points:
		centroid += point
	centroid /= float(points.size())
	if Geometry2D.is_point_in_polygon(centroid, points):
		return centroid
	return points[0]


func _choose_far_walkable_target(grid: Object, start: Vector2) -> Variant:
	var candidates := [
		Vector2(900, 560), Vector2(220, 560), Vector2(880, 400),
		Vector2(250, 400), Vector2(760, 650), Vector2(420, 640),
	]
	for candidate: Vector2 in candidates:
		if start.distance_to(candidate) < 260.0 or not bool(grid.call("is_position_walkable", candidate)):
			continue
		var path: PackedVector2Array = grid.call("find_path", start, candidate, true)
		if not path.is_empty():
			return candidate
	return null


func _point_along_path(path: PackedVector2Array, from_position: Vector2, requested_distance: float) -> Vector2:
	var previous := from_position
	var remaining := requested_distance
	for point: Vector2 in path:
		var segment_length := previous.distance_to(point)
		if segment_length >= remaining and segment_length > 0.001:
			return previous.lerp(point, remaining / segment_length)
		remaining -= segment_length
		previous = point
	return path[path.size() - 1]


func _path_from_variant(value: Variant) -> PackedVector2Array:
	if value is PackedVector2Array:
		return value
	var path := PackedVector2Array()
	if value is Array:
		for point: Variant in value:
			if point is Vector2:
				path.append(point)
	return path


func _find_static_lake_detour_fixture(grid: Object) -> Dictionary:
	var debug_points: Array = grid.call("get_debug_points", true)
	var best_length: int = 0
	var best_start: Vector2 = Vector2.ZERO
	var best_target: Vector2 = Vector2.ZERO
	var best_row: int = -1
	var best_start_x: int = -1
	var best_end_x: int = -1
	for start_index: int in range(1, debug_points.size() - 1):
		var previous_variant: Variant = debug_points[start_index - 1]
		var start_variant: Variant = debug_points[start_index]
		if not previous_variant is Dictionary or not start_variant is Dictionary:
			continue
		var previous: Dictionary = previous_variant
		var run_start: Dictionary = start_variant
		var previous_id_variant: Variant = previous.get("id", null)
		var start_id_variant: Variant = run_start.get("id", null)
		if not previous_id_variant is Vector2i or not start_id_variant is Vector2i:
			continue
		var previous_id: Vector2i = previous_id_variant
		var start_id: Vector2i = start_id_variant
		if not bool(previous.get("walkable", false)) or not _is_pure_river_lake_grid_record(run_start):
			continue
		if previous_id.y != start_id.y or previous_id.x != start_id.x - 1:
			continue

		var end_index: int = start_index
		var end_id: Vector2i = start_id
		while end_index + 1 < debug_points.size():
			var next_variant: Variant = debug_points[end_index + 1]
			if not next_variant is Dictionary:
				break
			var next_record: Dictionary = next_variant
			var next_id_variant: Variant = next_record.get("id", null)
			if not next_id_variant is Vector2i:
				break
			var next_id: Vector2i = next_id_variant
			if not _is_pure_river_lake_grid_record(next_record) or next_id.y != start_id.y or next_id.x != end_id.x + 1:
				break
			end_index += 1
			end_id = next_id

		if end_index + 1 >= debug_points.size():
			continue
		var following_variant: Variant = debug_points[end_index + 1]
		if not following_variant is Dictionary:
			continue
		var following: Dictionary = following_variant
		var following_id_variant: Variant = following.get("id", null)
		var previous_position_variant: Variant = previous.get("position", null)
		var following_position_variant: Variant = following.get("position", null)
		if not following_id_variant is Vector2i or not previous_position_variant is Vector2 or not following_position_variant is Vector2:
			continue
		var following_id: Vector2i = following_id_variant
		if following_id.y != start_id.y or following_id.x != end_id.x + 1 or not bool(following.get("walkable", false)):
			continue
		var run_length: int = end_index - start_index + 1
		if run_length > best_length:
			best_length = run_length
			best_start = previous_position_variant
			best_target = following_position_variant
			best_row = start_id.y
			best_start_x = start_id.x
			best_end_x = end_id.x

	if best_length <= 0:
		return {}
	return {
		"id": "river_lake_row_%d_x_%d_to_%d" % [best_row, best_start_x, best_end_x],
		"start": best_start,
		"target": best_target,
	}


func _is_pure_river_lake_grid_record(record: Dictionary) -> bool:
	if bool(record.get("walkable", false)):
		return false
	var static_kinds_variant: Variant = record.get("static_kinds", null)
	if not static_kinds_variant is PackedStringArray:
		return false
	var static_kinds: PackedStringArray = static_kinds_variant
	return static_kinds.has("river_lake") and not static_kinds.has("hill_cliff") and not static_kinds.has("trees_scenery") and not static_kinds.has("outside_stage")


func _segment_crosses_static_kind(grid: Object, start: Vector2, target: Vector2, static_kind: String) -> bool:
	var distance: float = start.distance_to(target)
	var sample_count: int = maxi(1, ceili(distance / PATH_SAMPLE_STEP))
	for sample_index: int in range(sample_count + 1):
		var sample: Vector2 = start.lerp(target, float(sample_index) / float(sample_count))
		var classifications: PackedStringArray = grid.call("static_classification_at", sample)
		if classifications.has(static_kind):
			return true
	return false


func _path_length(path: PackedVector2Array) -> float:
	var result := 0.0
	for index in range(path.size() - 1):
		result += path[index].distance_to(path[index + 1])
	return result


func _circular_distance(first: float, second: float) -> float:
	var difference := absf(fposmod(first, 1.0) - fposmod(second, 1.0))
	return minf(difference, 1.0 - difference)


func _cleanup_save() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	for suffix: String in ["", ".tmp", ".bak"]:
		var candidate := absolute_path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("NPC locomotion/navigation acceptance failed: %s" % message)


func _finish(main: Variant) -> void:
	_cleanup_save()
	var exit_code := 1 if _failed else 0
	if not _failed:
		print("NPC locomotion/navigation acceptance passed. Population=300 Proxies=24 Frames=%d DynamicReplan=1 NoRouteWait=1" % LOCOMOTION_FRAMES)
	await TestCleanup.finish(self, [main], exit_code)
