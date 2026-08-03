extends Node

signal npc_activated(slot_index: int)

const CityNavigationGridScript = preload("res://scripts/world/city_navigation_grid.gd")
const NpcActorScript = preload("res://scripts/world/npc_actor.gd")

const NPC_ACTOR_SIZE := Vector2(52, 68)
const NPC_ACTOR_FEET_OFFSET := Vector2(26, 65)
const NPC_FOOT_RADIUS := 9.0
const NPC_PERSONAL_SPACE_RADIUS := 13.0
const NPC_ACCELERATION := 150.0
const NPC_DECELERATION := 210.0
const NPC_WAYPOINT_REACHED_DISTANCE := 3.0
const NPC_REPATH_INTERVAL := 0.35
const NPC_LOCAL_WANDER_OFFSETS := [
	Vector2(62, 0),
	Vector2(40, 44),
	Vector2(0, 62),
	Vector2(-44, 40),
	Vector2(-62, 0),
	Vector2(-40, -44),
	Vector2(0, -62),
	Vector2(44, -40),
]
const NPC_PRIMARY_ROUTE_COUNT := 24
const NPC_ROUTE_SAMPLE_STEP := 18.0
const NPC_ROUTE_SPECS := [
	{"start": Vector2(104, 302), "end": Vector2(150, 302)},
	{"start": Vector2(276, 304), "end": Vector2(224, 304)},
	{"start": Vector2(349, 306), "end": Vector2(409, 306)},
	{"start": Vector2(540, 333), "end": Vector2(480, 303)},
	{"start": Vector2(598, 305), "end": Vector2(638, 305)},
	{"start": Vector2(780, 302), "end": Vector2(722, 302)},
	{"start": Vector2(880, 306), "end": Vector2(932, 334)},
	{"start": Vector2(948, 304), "end": Vector2(1008, 304)},
	{"start": Vector2(98, 406), "end": Vector2(148, 406)},
	{"start": Vector2(222, 408), "end": Vector2(174, 408)},
	{"start": Vector2(250, 404), "end": Vector2(306, 404)},
	{"start": Vector2(378, 407), "end": Vector2(326, 407)},
	{"start": Vector2(410, 405), "end": Vector2(486, 435)},
	{"start": Vector2(706, 408), "end": Vector2(650, 408)},
	{"start": Vector2(786, 406), "end": Vector2(790, 442)},
	{"start": Vector2(950, 404), "end": Vector2(1006, 404)},
	{"start": Vector2(108, 510), "end": Vector2(154, 510)},
	{"start": Vector2(236, 508), "end": Vector2(184, 508)},
	{"start": Vector2(260, 506), "end": Vector2(318, 506)},
	{"start": Vector2(392, 509), "end": Vector2(336, 509)},
	{"start": Vector2(560, 507), "end": Vector2(620, 507)},
	{"start": Vector2(764, 510), "end": Vector2(712, 510)},
	{"start": Vector2(864, 506), "end": Vector2(922, 506)},
	{"start": Vector2(948, 508), "end": Vector2(1008, 508)},
	{"start": Vector2(696, 302), "end": Vector2(648, 340)},
	{"start": Vector2(638, 506), "end": Vector2(686, 470)},
	{"start": Vector2(460, 508), "end": Vector2(520, 472)},
	{"start": Vector2(930, 408), "end": Vector2(870, 374)},
]
const NPC_SEPARATION_MARGIN := 3.0
const NPC_SCENERY_SAFE_RECT := Rect2(96, 302, 984, 300)

var _proxy_states: Array[Dictionary] = []
var _actors: Array[Button] = []
var _layer: Control
var _dark_mode := false
var _navigation
var _tile_centers := PackedVector2Array()
var _blocked_tiles: Dictionary = {}
var _crossing_tile_ids := PackedInt32Array()
var _crossing_states: Dictionary = {}
var _iso_tile_size := Vector2(128, 128)
var _iso_tile_step := Vector2(72, 40)


func mount(
	layer: Control,
	map_snapshot: Dictionary,
	dark_mode: bool,
	authoritative_proxies: Array[Dictionary]
) -> void:
	_layer = layer
	_dark_mode = dark_mode
	configure_navigation(map_snapshot)
	rebuild_actor_pool(authoritative_proxies, dark_mode)


func unmount() -> void:
	_clear_actors()
	_layer = null
	_navigation = null
	_tile_centers.clear()
	_blocked_tiles.clear()
	_crossing_tile_ids.clear()
	_crossing_states.clear()


func rebuild_actor_pool(authoritative_proxies: Array[Dictionary], dark_mode: bool) -> void:
	_clear_actors()
	_dark_mode = dark_mode
	if _layer == null:
		return
	var wander_points := _npc_wander_points()
	var occupied_feet: Array[Vector2] = []
	var reserved_destinations: Array[Vector2] = []
	for i in authoritative_proxies.size():
		var proxy: Dictionary = authoritative_proxies[i]
		var npc_type := str(proxy.get("archetype", "一般居民"))
		var spawn_index := _find_open_wander_index(i * 2, wander_points, occupied_feet)
		if spawn_index < 0:
			break
		var foot_position := wander_points[spawn_index]
		occupied_feet.append(foot_position)
		var wander_target: Dictionary = _resolved_local_wander_target(
			foot_position,
			i,
			posmod(i * 3 + 2, NPC_LOCAL_WANDER_OFFSETS.size()),
			reserved_destinations
		)
		var destination := Vector2(wander_target.get("position", foot_position))
		var wander_step := int(wander_target.get("step", 0))
		reserved_destinations.append(destination)
		var path: PackedVector2Array = (
			_navigation.find_path(foot_position, destination)
			if _navigation != null
			else PackedVector2Array([foot_position, destination])
		)
		var path_index := 1 if path.size() > 1 and path[0].distance_to(foot_position) <= NPC_WAYPOINT_REACHED_DISTANCE else 0
		var position := foot_position - NPC_ACTOR_FEET_OFFSET
		var actor: Button = NpcActorScript.new()
		actor.custom_minimum_size = NPC_ACTOR_SIZE
		actor.size = NPC_ACTOR_SIZE
		actor.mouse_filter = Control.MOUSE_FILTER_STOP
		actor.call("set_actor", npc_type, dark_mode, absi(hash(str(proxy.get("npc_id", i)))))
		actor.pressed.connect(Callable(self, "_on_actor_pressed").bind(i))
		_layer.add_child(actor)
		_proxy_states.append({
			"type": npc_type,
			"record_id": str(proxy.get("npc_id", "")),
			"display_name": str(proxy.get("display_name", npc_type)),
			"family_name": str(proxy.get("family_name", "")),
			"given_name": str(proxy.get("given_name", "")),
			"latin_display_name": str(proxy.get("latin_display_name", "")),
			"pos": position,
			"foot_position": foot_position,
			"tile": _npc_tile_at_feet(foot_position),
			"target_tile": _npc_tile_at_feet(destination),
			"target_pos": destination - NPC_ACTOR_FEET_OFFSET,
			"destination": destination,
			"home_position": foot_position,
			"path": path,
			"path_index": path_index,
			"speed": 28.0 + float(posmod(i * 5, 7)) * 2.0,
			"velocity": Vector2.ZERO,
			"travelled_distance": 0.0,
			"is_walking": false,
			"state": "idle",
			"blocked_waiting": path.is_empty(),
			"repath_cooldown": 0.0,
			"wait": 0.16 + float(posmod(i * 7, 6)) * 0.11,
			"route_offset": i,
			"route_slot": spawn_index,
			"target_endpoint": 1 if i % 2 == 0 else 0,
			"goal_index": wander_step,
			"wander_step": wander_step,
			"debug_destination_locked": false,
			"active": true,
		})
		actor.position = position
		actor.z_index = int(foot_position.y)
		_actors.append(actor)


func _clear_actors() -> void:
	# Detach synchronously so slot-bound signals from an old pool cannot overlap
	# a replacement pool for one frame.
	for actor: Button in _actors:
		if not is_instance_valid(actor):
			continue
		if actor.get_parent() != null:
			actor.get_parent().remove_child(actor)
		actor.queue_free()
	_actors.clear()
	_proxy_states.clear()


func _on_actor_pressed(slot_index: int) -> void:
	npc_activated.emit(slot_index)


func set_interaction_enabled(
	enabled: bool,
	display_name_formatter: Callable,
	dismiss_hovered_callback: Callable
) -> void:
	for index in _actors.size():
		var actor := _actors[index]
		if actor == null or not is_instance_valid(actor):
			continue
		var tooltip := str(_proxy_states[index].get("display_name", ""))
		if enabled and display_name_formatter.is_valid():
			tooltip = str(display_name_formatter.call(_proxy_states[index]))
		actor.tooltip_text = tooltip if enabled else ""
		actor.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		if not enabled and dismiss_hovered_callback.is_valid():
			dismiss_hovered_callback.call(actor)


func configure_navigation(map_snapshot: Dictionary) -> void:
	_navigation = CityNavigationGridScript.new(NPC_FOOT_RADIUS)
	sync_map_snapshot(map_snapshot)


func sync_map_snapshot(map_snapshot: Dictionary) -> void:
	_tile_centers = PackedVector2Array(map_snapshot.get("tile_centers", PackedVector2Array())).duplicate()
	_iso_tile_size = Vector2(map_snapshot.get("iso_tile_size", _iso_tile_size))
	_iso_tile_step = Vector2(map_snapshot.get("iso_tile_step", _iso_tile_step))
	_crossing_tile_ids.clear()
	for tile_variant: Variant in map_snapshot.get("crossing_tile_ids", []):
		var crossing_tile_id := int(tile_variant)
		if crossing_tile_id >= 0 and not _crossing_tile_ids.has(crossing_tile_id):
			_crossing_tile_ids.append(crossing_tile_id)
	_crossing_tile_ids.sort()
	_blocked_tiles.clear()
	var declared_blocked_tiles := Dictionary(map_snapshot.get("blocked_tiles", {}))
	for tile_variant: Variant in declared_blocked_tiles.keys():
		if bool(declared_blocked_tiles[tile_variant]):
			_blocked_tiles[int(tile_variant)] = true
	var terrain_blockers := Dictionary(map_snapshot.get("terrain_blockers", {})).duplicate(true)
	var flattened_terrain_centers := Dictionary(
		map_snapshot.get("flattened_terrain_centers", {})
	).duplicate(true)
	for tile_variant: Variant in terrain_blockers.keys():
		_blocked_tiles[int(tile_variant)] = true
	if _navigation == null:
		return
	var building_centers := Dictionary(map_snapshot.get("building_centers", {})).duplicate(true)
	var construction_centers := Dictionary(map_snapshot.get("construction_centers", {})).duplicate(true)
	var derived_half_extents := Vector2(
		maxf(0.5, _iso_tile_size.x * 0.5),
		maxf(0.5, _iso_tile_step.y)
	)
	var structure_half_extents := _snapshot_vector2(
		map_snapshot,
		["dynamic_blocker_half_extents", "structure_blocker_half_extents"],
		derived_half_extents
	)
	var terrain_half_extents := _snapshot_vector2(
		map_snapshot,
		["terrain_blocker_half_extents"],
		structure_half_extents
	)
	if _navigation.has_method("set_flattened_terrain_apertures"):
		_navigation.set_flattened_terrain_apertures(
			flattened_terrain_centers, terrain_half_extents
		)
	if _navigation.has_method("sync_map_tile_blockers"):
		_navigation.sync_map_tile_blockers(
			terrain_blockers,
			building_centers,
			construction_centers,
			terrain_half_extents,
			structure_half_extents
		)
	elif _navigation.has_method("sync_dynamic_tile_blockers"):
		_navigation.sync_dynamic_tile_blockers(
			building_centers, construction_centers, structure_half_extents
		)
		_sync_terrain_blockers_fallback(terrain_blockers, terrain_half_extents)
	else:
		_navigation.clear_dynamic_blockers()
		_sync_terrain_blockers_fallback(terrain_blockers, terrain_half_extents)
		for tile_index: Variant in building_centers:
			_navigation.set_building_blocker(
				int(tile_index),
				Vector2(building_centers[tile_index]),
				true,
				structure_half_extents
			)
		for tile_index: Variant in construction_centers:
			_navigation.set_construction_blocker(
				int(tile_index),
				Vector2(construction_centers[tile_index]),
				true,
				structure_half_extents
			)
	_sync_navigation_crossing_apertures()


## Crossing animation and NPC navigation share the same authoritative closed
## bit.  Flash-only changes are deliberately ignored so warning-light frames do
## not trigger city-wide A* rebuilds or resident replans.
func set_crossing_states(states: Dictionary) -> void:
	var previously_open := _open_crossing_tile_ids()
	_crossing_states = states.duplicate(true)
	var currently_open := _open_crossing_tile_ids()
	if currently_open == previously_open:
		return
	_sync_navigation_crossing_apertures()
	if not _proxy_states.is_empty():
		repath_all()


func get_open_crossing_tile_ids() -> PackedInt32Array:
	return _open_crossing_tile_ids()


func _sync_navigation_crossing_apertures() -> void:
	if _navigation != null and _navigation.has_method("set_transport_crossing_apertures"):
		_navigation.set_transport_crossing_apertures(_open_crossing_tile_ids())


func _open_crossing_tile_ids() -> PackedInt32Array:
	var result := PackedInt32Array()
	for tile_id: int in _crossing_tile_ids:
		if _crossing_is_open(tile_id):
			result.append(tile_id)
	return result


func _crossing_is_open(tile_id: int) -> bool:
	if not _crossing_tile_ids.has(tile_id):
		return false
	var state_variant: Variant = _crossing_states.get(
		str(tile_id), _crossing_states.get(tile_id, {})
	)
	var state: Dictionary = state_variant if state_variant is Dictionary else {}
	return not bool(state.get("closed", false))


func _snapshot_vector2(
	snapshot: Dictionary,
	keys: Array[String],
	fallback: Vector2
) -> Vector2:
	for key: String in keys:
		var value: Variant = snapshot.get(key, null)
		if value is Vector2:
			var resolved: Vector2 = value
			return Vector2(maxf(0.5, resolved.x), maxf(0.5, resolved.y))
		if value is Vector2i:
			var resolved_i: Vector2i = value
			return Vector2(maxf(0.5, resolved_i.x), maxf(0.5, resolved_i.y))
	return Vector2(maxf(0.5, fallback.x), maxf(0.5, fallback.y))


func _sync_terrain_blockers_fallback(
	terrain_blockers: Dictionary,
	half_extents: Vector2
) -> void:
	if _navigation == null or not _navigation.has_method("set_terrain_blocker"):
		return
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
		_navigation.set_terrain_blocker(
			int(tile_variant), center, terrain_kind, true, half_extents
		)


func get_navigation_grid():
	return _navigation


func visible_count() -> int:
	return _proxy_states.size()


func get_proxy_snapshot(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= _proxy_states.size():
		return {}
	return _proxy_states[slot_index].duplicate(true)


func get_proxy_snapshots() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for proxy: Dictionary in _proxy_states:
		snapshots.append(proxy.duplicate(true))
	return snapshots


func get_actor(slot_index: int) -> Button:
	if slot_index < 0 or slot_index >= _actors.size():
		return null
	return _actors[slot_index]


func get_actors() -> Array[Button]:
	var result: Array[Button] = []
	for actor: Button in _actors:
		result.append(actor)
	return result


func debug_override_proxy(slot_index: int, proxy: Dictionary) -> bool:
	if slot_index < 0 or slot_index >= _proxy_states.size():
		return false
	_proxy_states[slot_index] = proxy.duplicate(true)
	return true


func bind_existing_proxy_pool(
	proxy_states: Array[Dictionary],
	actors: Array[Button]
) -> void:
	_proxy_states = proxy_states
	_actors = actors


# Rebinds authoritative identities without disturbing slot-local locomotion.
# Returns false when the actor pool cardinality must be rebuilt by its owner.
func reconcile_proxy_pool(desired: Array[Dictionary], dark_mode: bool) -> bool:
	if desired.size() != _proxy_states.size() or _actors.size() != _proxy_states.size():
		return false
	if desired.is_empty():
		return true

	var desired_by_id := {}
	for proxy: Dictionary in desired:
		var record_id := str(proxy.get("npc_id", ""))
		if not record_id.is_empty():
			desired_by_id[record_id] = proxy

	# Retained residents keep their current world slot. Only vacated slots are
	# rebound, so an authoritative roster refresh cannot reset locomotion.
	var assigned: Array[Dictionary] = []
	var used_ids := {}
	for _index in desired.size():
		assigned.append({})
	for slot_index in desired.size():
		var current_id := str(_proxy_states[slot_index].get("record_id", ""))
		if not current_id.is_empty() and desired_by_id.has(current_id) and not used_ids.has(current_id):
			assigned[slot_index] = desired_by_id[current_id]
			used_ids[current_id] = true

	var next_empty_slot := 0
	for proxy: Dictionary in desired:
		var record_id := str(proxy.get("npc_id", ""))
		if not record_id.is_empty() and used_ids.has(record_id):
			continue
		while next_empty_slot < assigned.size() and not assigned[next_empty_slot].is_empty():
			next_empty_slot += 1
		if next_empty_slot >= assigned.size():
			break
		assigned[next_empty_slot] = proxy
		if not record_id.is_empty():
			used_ids[record_id] = true

	for slot_index in assigned.size():
		var proxy: Dictionary = assigned[slot_index]
		if proxy.is_empty():
			# Preserve the previous defensive behavior for malformed duplicate or
			# blank ids; never leave a stale identity in a visible slot.
			proxy = desired[slot_index]
		_apply_proxy_to_slot(slot_index, proxy, dark_mode)
	return true


func _apply_proxy_to_slot(slot_index: int, proxy: Dictionary, dark_mode: bool) -> void:
	if slot_index < 0 or slot_index >= _proxy_states.size() or slot_index >= _actors.size():
		return
	var npc: Dictionary = _proxy_states[slot_index]
	var previous_record_id := str(npc.get("record_id", ""))
	var previous_type := str(npc.get("type", "一般居民"))
	var next_type := str(proxy.get("archetype", "一般居民"))
	var next_record_id := str(proxy.get("npc_id", ""))
	npc["type"] = next_type
	npc["record_id"] = next_record_id
	npc["display_name"] = str(proxy.get("display_name", next_type))
	npc["family_name"] = str(proxy.get("family_name", ""))
	npc["given_name"] = str(proxy.get("given_name", ""))
	npc["latin_display_name"] = str(proxy.get("latin_display_name", ""))
	_proxy_states[slot_index] = npc
	var actor: Button = _actors[slot_index]
	if previous_record_id != next_record_id or previous_type != next_type:
		actor.call("set_actor", next_type, dark_mode, absi(hash(next_record_id)))
	actor.tooltip_text = str(npc["display_name"])


func get_wander_points() -> PackedVector2Array:
	return _npc_wander_points()


func find_open_wander_index(
	preferred_index: int,
	points: PackedVector2Array,
	occupied_feet: Array[Vector2]
) -> int:
	return _find_open_wander_index(preferred_index, points, occupied_feet)


func resolve_local_wander_target(
	home_position: Vector2,
	npc_index: int,
	preferred_step: int,
	reserved_destinations: Array[Vector2] = []
) -> Dictionary:
	return _resolved_local_wander_target(
		home_position, npc_index, preferred_step, reserved_destinations
	)


func tile_at_feet(feet_position: Vector2) -> int:
	return _npc_tile_at_feet(feet_position)


func get_route_slots_snapshot() -> Array[Dictionary]:
	return _npc_route_slots()


func is_position_scenery_safe(position: Vector2) -> bool:
	return _npc_position_is_scenery_safe(position)


func is_tile_blocked(tile_index: int) -> bool:
	return _npc_tile_has_obstacle(tile_index)


func _npc_wander_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	for route_variant: Variant in NPC_ROUTE_SPECS:
		var route: Dictionary = route_variant
		for key in ["start", "end"]:
			var candidate := Vector2(route.get(key, Vector2.ZERO)) + NPC_ACTOR_FEET_OFFSET
			if _navigation != null:
				var safe_variant: Variant = _navigation.nearest_safe_position(candidate, 120.0)
				if safe_variant == null:
					continue
				candidate = safe_variant
			var duplicate := false
			for existing: Vector2 in points:
				if existing.distance_to(candidate) < NPC_PERSONAL_SPACE_RADIUS * 2.1:
					duplicate = true
					break
			if not duplicate:
				points.append(candidate)
	return points


func _find_open_wander_index(
	preferred_index: int,
	points: PackedVector2Array,
	occupied_feet: Array[Vector2]
) -> int:
	if points.is_empty():
		return -1
	for offset in points.size():
		var candidate_index := posmod(preferred_index + offset, points.size())
		var candidate := points[candidate_index]
		var open := true
		for occupied: Vector2 in occupied_feet:
			if occupied.distance_to(candidate) < NPC_PERSONAL_SPACE_RADIUS * 2.0 + NPC_SEPARATION_MARGIN:
				open = false
				break
		if open:
			return candidate_index
	return -1


func _find_reachable_wander_goal(
	npc_index: int,
	spawn_index: int,
	points: PackedVector2Array
) -> int:
	if points.size() < 2:
		return spawn_index
	var start := points[spawn_index]
	var stride := maxi(3, int(points.size() / 2) + posmod(npc_index * 3, 7))
	for attempt in points.size():
		var candidate_index := posmod(spawn_index + stride + attempt * 3, points.size())
		var candidate := points[candidate_index]
		if start.distance_to(candidate) < 110.0:
			continue
		if _navigation == null or not _navigation.find_path(start, candidate).is_empty():
			return candidate_index
	return posmod(spawn_index + 1, points.size())


func _resolved_local_wander_target(
	home_position: Vector2,
	npc_index: int,
	preferred_step: int,
	reserved_destinations: Array[Vector2] = []
) -> Dictionary:
	if _navigation == null or NPC_LOCAL_WANDER_OFFSETS.is_empty():
		return {"position": home_position, "step": 0}
	var direction_step := 1 if npc_index % 2 == 0 else -1
	var radius_scale := 0.86 + float(posmod(npc_index * 7, 5)) * 0.06
	for attempt in NPC_LOCAL_WANDER_OFFSETS.size():
		var step := posmod(preferred_step + attempt * direction_step, NPC_LOCAL_WANDER_OFFSETS.size())
		var requested := home_position + Vector2(NPC_LOCAL_WANDER_OFFSETS[step]) * radius_scale
		var safe_variant: Variant = _navigation.nearest_safe_position(requested, 52.0)
		if safe_variant == null:
			continue
		var candidate: Vector2 = safe_variant
		if home_position.distance_to(candidate) < 30.0:
			continue
		var destination_free := true
		for reserved: Vector2 in reserved_destinations:
			if reserved.distance_to(candidate) < NPC_PERSONAL_SPACE_RADIUS * 2.6:
				destination_free = false
				break
		if not destination_free:
			continue
		if _navigation.find_path(home_position, candidate).is_empty():
			continue
		return {"position": candidate, "step": step}
	return {"position": home_position, "step": posmod(preferred_step, NPC_LOCAL_WANDER_OFFSETS.size())}


func _npc_route_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for route_variant: Variant in NPC_ROUTE_SPECS:
		var route: Dictionary = route_variant
		slots.append({
			"start": Vector2(route.get("start", Vector2.ZERO)),
			"end": Vector2(route.get("end", Vector2.ZERO)),
		})
	return slots


func _npc_route_position(slot_index: int, endpoint: int) -> Vector2:
	var slots := _npc_route_slots()
	if slot_index < 0 or slot_index >= slots.size():
		return Vector2.ZERO
	return slots[slot_index]["end" if endpoint == 1 else "start"]


func _preferred_npc_route_slot(proxy_index: int) -> int:
	if proxy_index < NPC_PRIMARY_ROUTE_COUNT:
		return proxy_index
	return posmod(proxy_index, maxi(1, NPC_PRIMARY_ROUTE_COUNT))


func _find_available_npc_route_slot(
	preferred_index: int,
	occupied_slots: Dictionary,
	spawn_endpoint: int = 0,
	except_npc_index: int = -1
) -> int:
	var slots := _npc_route_slots()
	if slots.is_empty():
		return -1
	for offset in slots.size():
		var candidate := posmod(preferred_index + offset, slots.size())
		if occupied_slots.has(candidate) or not _npc_route_slot_is_walkable(candidate):
			continue
		var spawn_position := _npc_route_position(candidate, clampi(spawn_endpoint, 0, 1))
		if _npc_position_overlaps_other(except_npc_index, spawn_position):
			continue
		return candidate
	return -1


func _npc_route_slot_is_walkable(slot_index: int) -> bool:
	var start := _npc_route_position(slot_index, 0)
	var finish := _npc_route_position(slot_index, 1)
	if _navigation != null:
		return _navigation.is_segment_walkable(
			start + NPC_ACTOR_FEET_OFFSET,
			finish + NPC_ACTOR_FEET_OFFSET
		)
	var sample_count := maxi(2, ceili(start.distance_to(finish) / NPC_ROUTE_SAMPLE_STEP))
	for sample_index in range(sample_count + 1):
		var position := start.lerp(finish, float(sample_index) / float(sample_count))
		if not _npc_position_is_scenery_safe(position):
			return false
		var tile_index := _npc_tile_at_feet(position + NPC_ACTOR_FEET_OFFSET)
		if _npc_tile_has_obstacle(tile_index):
			return false
	return true


func _npc_position_is_scenery_safe(position: Vector2) -> bool:
	if _navigation != null:
		return _navigation.is_position_walkable(position + NPC_ACTOR_FEET_OFFSET)
	return NPC_SCENERY_SAFE_RECT.encloses(Rect2(position, NPC_ACTOR_SIZE))


func _npc_tile_at_feet(feet_position: Vector2) -> int:
	var closest_index := -1
	var closest_score := INF
	for tile_index in _tile_centers.size():
		var center := _tile_centers[tile_index]
		var score := (
			absf(feet_position.x - center.x) / (_iso_tile_size.x * 0.5)
			+ absf(feet_position.y - center.y) / _iso_tile_step.y
		)
		if score <= 1.0 and score < closest_score:
			closest_score = score
			closest_index = tile_index
	return closest_index


func _npc_tile_has_obstacle(tile_index: int) -> bool:
	return (
		tile_index >= 0
		and _blocked_tiles.has(tile_index)
		and not _crossing_is_open(tile_index)
	)


func _occupied_npc_route_slots(except_npc_index: int = -1) -> Dictionary:
	var occupied := {}
	for index in _proxy_states.size():
		if index == except_npc_index:
			continue
		var npc: Dictionary = _proxy_states[index]
		if bool(npc.get("active", true)):
			occupied[int(npc.get("route_slot", -1))] = true
	return occupied


func _npc_position_overlaps_other(npc_index: int, position: Vector2) -> bool:
	return _npc_foot_overlaps_other(npc_index, position + NPC_ACTOR_FEET_OFFSET)


func _npc_foot_overlaps_other(npc_index: int, foot_position: Vector2) -> bool:
	return _npc_blocking_index(npc_index, foot_position) >= 0


func _npc_blocking_index(npc_index: int, foot_position: Vector2) -> int:
	var minimum_distance := NPC_PERSONAL_SPACE_RADIUS * 2.0 + NPC_SEPARATION_MARGIN
	for other_index in _proxy_states.size():
		if other_index == npc_index:
			continue
		var other: Dictionary = _proxy_states[other_index]
		if not bool(other.get("active", true)):
			continue
		var other_foot := Vector2(other.get(
			"foot_position",
			Vector2(other.get("pos", Vector2.ZERO)) + NPC_ACTOR_FEET_OFFSET
		))
		if foot_position.distance_to(other_foot) < minimum_distance:
			return other_index
	return -1


func _insert_npc_crowd_detour(
	npc_index: int,
	blocking_index: int,
	foot_position: Vector2,
	waypoint: Vector2,
	path: PackedVector2Array,
	path_index: int
) -> PackedVector2Array:
	if blocking_index < 0 or blocking_index >= _proxy_states.size() or path_index >= path.size():
		return PackedVector2Array()
	var blocker: Dictionary = _proxy_states[blocking_index]
	var blocker_foot := Vector2(blocker.get("foot_position", Vector2.ZERO))
	var approach := foot_position.direction_to(blocker_foot)
	if approach.length_squared() <= 0.001:
		approach = foot_position.direction_to(waypoint)
	if approach.length_squared() <= 0.001:
		approach = Vector2.RIGHT
	var preferred_sign := 1.0 if posmod(npc_index + blocking_index, 2) == 0 else -1.0
	for side_sign in [preferred_sign, -preferred_sign]:
		var lateral := approach.rotated(PI * 0.5) * float(side_sign)
		var first_detour := foot_position + lateral * 24.0
		var second_detour := blocker_foot + lateral * 35.0 + approach * 8.0
		if _npc_foot_overlaps_other(npc_index, first_detour):
			continue
		if _npc_foot_overlaps_other(npc_index, second_detour):
			continue
		if _navigation != null and (
			not _navigation.is_segment_walkable(foot_position, first_detour)
			or not _navigation.is_segment_walkable(first_detour, second_detour)
			or not _navigation.is_segment_walkable(second_detour, waypoint)
		):
			continue
		var detoured_path := PackedVector2Array([foot_position, first_detour, second_detour])
		for remaining_index in range(path_index, path.size()):
			if detoured_path[detoured_path.size() - 1].distance_to(path[remaining_index]) > 0.01:
				detoured_path.append(path[remaining_index])
		return detoured_path
	return PackedVector2Array()


func _npc_separation_steering(npc_index: int, foot_position: Vector2) -> Vector2:
	var steering := Vector2.ZERO
	var influence_distance := NPC_PERSONAL_SPACE_RADIUS * 2.8
	for other_index in _proxy_states.size():
		if other_index == npc_index:
			continue
		var other: Dictionary = _proxy_states[other_index]
		if not bool(other.get("active", true)):
			continue
		var other_foot := Vector2(other.get(
			"foot_position",
			Vector2(other.get("pos", Vector2.ZERO)) + NPC_ACTOR_FEET_OFFSET
		))
		var offset := foot_position - other_foot
		var distance := offset.length()
		if distance >= influence_distance:
			continue
		if distance <= 0.001:
			offset = Vector2.RIGHT.rotated(float(npc_index + 1) * 1.618)
			distance = 0.001
		steering += offset.normalized() * (1.0 - distance / influence_distance)
	return steering.limit_length(1.0)


func step(delta: float) -> void:
	if _actors.is_empty() or _proxy_states.is_empty() or delta <= 0.0:
		return
	# Preserve the established fixed-size substeps exactly. They keep obstacle
	# and crowd checks stable after a slow frame.
	var remaining := minf(delta, 0.25)
	while remaining > 0.0001:
		var step_delta := minf(remaining, 0.05)
		_update_step(step_delta)
		remaining -= step_delta


func _update_step(delta: float) -> void:
	for i in _proxy_states.size():
		if i >= _actors.size():
			continue
		var npc: Dictionary = _proxy_states[i]
		var actor := _actors[i]
		actor.visible = bool(npc.get("active", true))
		if not actor.visible:
			continue
		var foot_position := Vector2(npc.get(
			"foot_position",
			Vector2(npc.get("pos", Vector2.ZERO)) + NPC_ACTOR_FEET_OFFSET
		))
		var previous_foot := foot_position
		var velocity := Vector2(npc.get("velocity", Vector2.ZERO))
		var moved_distance := 0.0
		var blocked_waiting := false
		var state := "waiting"

		if actor.is_hovered():
			npc["wait"] = maxf(float(npc.get("wait", 0.0)), 0.18)
			velocity = Vector2.ZERO
		elif float(npc.get("wait", 0.0)) > 0.0:
			npc["wait"] = maxf(0.0, float(npc.get("wait", 0.0)) - delta)
			velocity = velocity.move_toward(Vector2.ZERO, NPC_DECELERATION * delta)
		elif _navigation != null and not _navigation.is_position_walkable(foot_position):
			var safe_variant: Variant = _navigation.nearest_safe_position(foot_position, 190.0)
			if safe_variant == null:
				velocity = Vector2.ZERO
				blocked_waiting = true
			else:
				var safe_position: Vector2 = safe_variant
				var evacuation_direction := foot_position.direction_to(safe_position)
				var evacuation_speed := minf(float(npc.get("speed", 32.0)), 26.0)
				velocity = velocity.move_toward(evacuation_direction * evacuation_speed, NPC_ACCELERATION * delta)
				var evacuation_step := velocity * delta
				if evacuation_step.length() > foot_position.distance_to(safe_position):
					evacuation_step = evacuation_direction * foot_position.distance_to(safe_position)
				var proposed_evacuation := foot_position + evacuation_step
				if (
					proposed_evacuation.distance_to(safe_position) < foot_position.distance_to(safe_position)
					and not _npc_foot_overlaps_other(i, proposed_evacuation)
				):
					foot_position = proposed_evacuation
					moved_distance = previous_foot.distance_to(foot_position)
					state = "walking"
				else:
					velocity = Vector2.ZERO
					blocked_waiting = true
		else:
			var path: PackedVector2Array = npc.get("path", PackedVector2Array())
			var path_index := int(npc.get("path_index", 0))
			while path_index < path.size() and foot_position.distance_to(path[path_index]) <= 0.35:
				path_index += 1
			npc["path_index"] = path_index
			if path.is_empty():
				velocity = velocity.move_toward(Vector2.ZERO, NPC_DECELERATION * delta)
				blocked_waiting = bool(npc.get("blocked_waiting", true))
				if not bool(npc.get("debug_destination_locked", false)):
					var cooldown := maxf(0.0, float(npc.get("repath_cooldown", 0.0)) - delta)
					npc["repath_cooldown"] = cooldown
					if cooldown <= 0.0:
						_assign_next_wander_destination(i)
						npc = _proxy_states[i]
			elif path_index >= path.size():
				velocity = velocity.move_toward(Vector2.ZERO, NPC_DECELERATION * delta)
				npc["blocked_waiting"] = false
				if not bool(npc.get("debug_destination_locked", false)):
					npc["wait"] = 0.34 + float(posmod(i * 5, 5)) * 0.13
					npc["path"] = PackedVector2Array()
					npc["path_index"] = 0
			else:
				var waypoint := path[path_index]
				var to_waypoint := waypoint - foot_position
				var waypoint_distance := to_waypoint.length()
				var direction := to_waypoint.normalized() if waypoint_distance > 0.001 else Vector2.ZERO
				var separation := _npc_separation_steering(i, foot_position)
				var heading := (direction + separation * 0.28).normalized()
				var speed := float(npc.get("speed", 32.0))
				var desired_velocity := heading * speed
				velocity = velocity.move_toward(desired_velocity, NPC_ACCELERATION * delta).limit_length(speed)
				var movement := velocity * delta
				if movement.length() > waypoint_distance:
					movement = direction * waypoint_distance
				var proposed := foot_position + movement
				var segment_safe: bool = (
					_navigation == null
					or _navigation.is_segment_walkable(foot_position, proposed)
				)
				var blocking_index := _npc_blocking_index(i, proposed) if segment_safe else -1
				if segment_safe and blocking_index < 0:
					foot_position = proposed
					moved_distance = previous_foot.distance_to(foot_position)
					state = "walking" if moved_distance > 0.01 else "waiting"
					blocked_waiting = false
				else:
					velocity = velocity.move_toward(Vector2.ZERO, NPC_DECELERATION * delta)
					blocked_waiting = true
					var cooldown := maxf(0.0, float(npc.get("repath_cooldown", 0.0)) - delta)
					npc["repath_cooldown"] = cooldown
					if segment_safe and blocking_index >= 0 and cooldown <= 0.0:
						var detoured_path := _insert_npc_crowd_detour(
							i, blocking_index, foot_position, waypoint, path, path_index
						)
						if not detoured_path.is_empty():
							npc["path"] = detoured_path
							npc["path_index"] = 1
							npc["local_avoidance_count"] = int(npc.get("local_avoidance_count", 0)) + 1
							npc["blocked_waiting"] = false
							blocked_waiting = false
							npc["repath_cooldown"] = NPC_REPATH_INTERVAL
						else:
							npc["wait"] = 0.06 + float(posmod(i * 7, 4)) * 0.03
					elif not segment_safe and cooldown <= 0.0:
						debug_force_repath(i, true)
						npc = _proxy_states[i]

		var actual_velocity := (foot_position - previous_foot) / delta if moved_distance > 0.0 else Vector2.ZERO
		npc["foot_position"] = foot_position
		npc["pos"] = foot_position - NPC_ACTOR_FEET_OFFSET
		npc["velocity"] = actual_velocity
		npc["travelled_distance"] = float(npc.get("travelled_distance", 0.0)) + moved_distance
		npc["is_walking"] = moved_distance > 0.01
		npc["state"] = state if moved_distance > 0.01 else "waiting"
		npc["blocked_waiting"] = blocked_waiting
		npc["tile"] = _npc_tile_at_feet(foot_position)
		var destination := Vector2(npc.get("destination", foot_position))
		npc["target_pos"] = destination - NPC_ACTOR_FEET_OFFSET
		npc["target_tile"] = _npc_tile_at_feet(destination)
		_proxy_states[i] = npc
		actor.position = Vector2(npc["pos"])
		actor.call("set_locomotion", actual_velocity, moved_distance, delta)
		actor.z_index = int(foot_position.y)


func _assign_next_wander_destination(npc_index: int) -> bool:
	if npc_index < 0 or npc_index >= _proxy_states.size():
		return false
	var npc: Dictionary = _proxy_states[npc_index]
	var foot_position := Vector2(npc.get("foot_position", Vector2.ZERO))
	var home_position := Vector2(npc.get("home_position", foot_position))
	var reserved_destinations: Array[Vector2] = []
	for other_index in _proxy_states.size():
		if other_index == npc_index:
			continue
		reserved_destinations.append(Vector2(_proxy_states[other_index].get(
			"destination", _proxy_states[other_index].get("foot_position", Vector2.ZERO)
		)))
	var direction_step := 1 if npc_index % 2 == 0 else -1
	var preferred_step := int(npc.get("wander_step", npc_index)) + direction_step
	for attempt in NPC_LOCAL_WANDER_OFFSETS.size():
		var target_data := _resolved_local_wander_target(
			home_position,
			npc_index,
			preferred_step + attempt * direction_step,
			reserved_destinations
		)
		var candidate := Vector2(target_data.get("position", home_position))
		if foot_position.distance_to(candidate) < 26.0:
			continue
		if _set_destination(npc_index, candidate, true, false, false):
			npc = _proxy_states[npc_index]
			var resolved_step := int(target_data.get("step", preferred_step))
			npc["goal_index"] = resolved_step
			npc["wander_step"] = resolved_step
			_proxy_states[npc_index] = npc
			return true
	return false


func _set_destination(
	npc_index: int,
	target: Vector2,
	snap_to_nearest: bool,
	lock_destination: bool,
	count_replan: bool
) -> bool:
	if npc_index < 0 or npc_index >= _proxy_states.size() or _navigation == null:
		return false
	var npc: Dictionary = _proxy_states[npc_index]
	var foot_position := Vector2(npc.get(
		"foot_position",
		Vector2(npc.get("pos", Vector2.ZERO)) + NPC_ACTOR_FEET_OFFSET
	))
	var path: PackedVector2Array = _navigation.find_path(foot_position, target, snap_to_nearest)
	if count_replan:
		npc["replan_count"] = int(npc.get("replan_count", 0)) + 1
	npc["debug_destination_locked"] = lock_destination
	npc["destination"] = target
	npc["target_pos"] = target - NPC_ACTOR_FEET_OFFSET
	npc["target_tile"] = _npc_tile_at_feet(target)
	npc["velocity"] = Vector2.ZERO
	npc["wait"] = 0.0
	if path.is_empty():
		npc["path"] = PackedVector2Array()
		npc["path_index"] = 0
		npc["state"] = "waiting"
		npc["is_walking"] = false
		npc["blocked_waiting"] = true
		npc["repath_cooldown"] = NPC_REPATH_INTERVAL
		_proxy_states[npc_index] = npc
		if npc_index < _actors.size():
			_actors[npc_index].call("set_locomotion", Vector2.ZERO, 0.0, 0.0)
		return false
	npc["path"] = path
	npc["path_index"] = (
		1
		if path.size() > 1 and path[0].distance_to(foot_position) <= NPC_WAYPOINT_REACHED_DISTANCE
		else 0
	)
	npc["destination"] = path[path.size() - 1]
	npc["target_pos"] = Vector2(npc["destination"]) - NPC_ACTOR_FEET_OFFSET
	npc["target_tile"] = _npc_tile_at_feet(Vector2(npc["destination"]))
	npc["state"] = "waiting"
	npc["is_walking"] = false
	npc["blocked_waiting"] = false
	npc["repath_cooldown"] = NPC_REPATH_INTERVAL
	_proxy_states[npc_index] = npc
	return true


func debug_set_destination(
	npc_index: int,
	target: Vector2,
	snap_to_nearest: bool = true
) -> bool:
	return _set_destination(npc_index, target, snap_to_nearest, true, true)


func debug_force_repath(npc_index: int, snap_to_nearest: bool = true) -> bool:
	if npc_index < 0 or npc_index >= _proxy_states.size():
		return false
	var npc: Dictionary = _proxy_states[npc_index]
	return _set_destination(
		npc_index,
		Vector2(npc.get("destination", npc.get("foot_position", Vector2.ZERO))),
		snap_to_nearest,
		bool(npc.get("debug_destination_locked", false)),
		true
	)


func get_acceptance_snapshot(npc_index: int) -> Dictionary:
	if npc_index < 0 or npc_index >= _proxy_states.size():
		return {}
	var npc: Dictionary = _proxy_states[npc_index]
	var actor_snapshot := {}
	if npc_index < _actors.size() and _actors[npc_index].has_method("get_locomotion_debug_snapshot"):
		actor_snapshot = _actors[npc_index].call("get_locomotion_debug_snapshot")
	return {
		"record_id": str(npc.get("record_id", "")),
		"position": Vector2(npc.get("pos", Vector2.ZERO)),
		"feet_position": Vector2(npc.get("foot_position", Vector2.ZERO)),
		"visible": npc_index < _actors.size() and _actors[npc_index].visible,
		"state": str(npc.get("state", "waiting")),
		"velocity": Vector2(npc.get("velocity", Vector2.ZERO)),
		"speed": float(npc.get("speed", 0.0)),
		"is_walking": bool(npc.get("is_walking", false)),
		"travelled_distance": float(npc.get("travelled_distance", 0.0)),
		"cycle_phase": float(actor_snapshot.get("cycle_phase", 0.0)),
		"frame_index": int(actor_snapshot.get("frame_index", 0)),
		"actor_is_walking": bool(actor_snapshot.get("is_walking", false)),
		"stop_settle_remaining": float(actor_snapshot.get("stop_settle_remaining", 0.0)),
		"stop_target_frame": int(actor_snapshot.get("stop_target_frame", 0)),
		"render_direction": str(actor_snapshot.get("render_direction", actor_snapshot.get("direction", "down"))),
		"opaque_body_draws": int(actor_snapshot.get("opaque_body_draws", 1)),
		"path": PackedVector2Array(npc.get("path", PackedVector2Array())).duplicate(),
		"path_index": int(npc.get("path_index", 0)),
		"destination": Vector2(npc.get("destination", Vector2.ZERO)),
		"replan_count": int(npc.get("replan_count", 0)),
		"blocked_waiting": bool(npc.get("blocked_waiting", false)),
	}


func repath_all() -> void:
	for npc_index in _proxy_states.size():
		debug_force_repath(npc_index, true)
