class_name TransportRouteGeometry
extends RefCounted

## Pure, render-layer transport geometry. The transport authority supplies only
## completed topology and operational route paths; this helper turns that data
## into immutable baked polylines shared by the renderer and vehicle sampler.

const DEFAULT_CORNER_RADIUS := 18.0
const DEFAULT_BAKE_INTERVAL := 3.0
const DEFAULT_LANE_OFFSET := 5.5
const TERMINAL_CAP_SAMPLES := 12
const EPSILON := 0.001

const MODE_LANE_OFFSETS := {
	"bus": 5.5,
	"metro": 5.0,
	"train": 5.0,
	"air": 10.0,
	"road": 5.5,
}


static func build_corridor_geometries(
	completed_tile_states: Dictionary,
	tile_centers: Dictionary,
	corner_radius: float = DEFAULT_CORNER_RADIUS
) -> Array[Dictionary]:
	var adjacency_by_kind := _adjacency_by_kind(completed_tile_states, tile_centers)
	var result: Array[Dictionary] = []
	var kinds: Array[String] = []
	for kind_variant: Variant in adjacency_by_kind.keys():
		kinds.append(str(kind_variant))
	kinds.sort()
	for kind: String in kinds:
		var adjacency: Dictionary = adjacency_by_kind[kind]
		for path_variant: Variant in _extract_graph_paths(adjacency):
			var path: Array = path_variant
			var closed := path.size() > 2 and int(path[0]) == int(path[-1])
			var geometry: Dictionary
			if path.size() == 1:
				var center := _center_for(tile_centers, int(path[0]))
				geometry = _geometry_from_points(PackedVector2Array([
					center - Vector2(27.0, 0.0),
					center + Vector2(27.0, 0.0),
				]), false)
				geometry["classification"] = "short_segment"
			else:
				geometry = build_centerline(path, tile_centers, closed, corner_radius)
				geometry["classification"] = _path_classification(path, tile_centers, adjacency, closed)
			if not bool(geometry.get("valid", false)):
				continue
			geometry["kind"] = kind
			geometry["path_tile_ids"] = path.duplicate()
			result.append(geometry)
	return result


static func build_operational_route_geometries(
	runtime_snapshot: Dictionary,
	tile_centers: Dictionary
) -> Dictionary:
	var result: Dictionary = {}
	for line_variant: Variant in runtime_snapshot.get("operational_lines", []):
		if not line_variant is Dictionary:
			continue
		var line: Dictionary = line_variant
		if str(line.get("status", "")) != "operational":
			continue
		var route_id := str(line.get("id", line.get("route_id", "")))
		var path: Array = line.get("path_tile_ids", [])
		if route_id.is_empty() or path.size() < 2:
			continue
		var mode := str(line.get("mode", "road"))
		var geometry := build_bidirectional_route(
			path,
			tile_centers,
			float(MODE_LANE_OFFSETS.get(mode, DEFAULT_LANE_OFFSET))
		)
		if not bool(geometry.get("valid", false)):
			continue
		geometry["route_id"] = route_id
		geometry["mode"] = mode
		geometry["vehicle_kind"] = str(line.get("vehicle_kind", ""))
		result[route_id] = geometry
	return result


static func build_centerline(
	path_tile_ids: Array,
	tile_centers: Dictionary,
	closed: bool = false,
	corner_radius: float = DEFAULT_CORNER_RADIUS
) -> Dictionary:
	var raw_points := PackedVector2Array()
	for tile_variant: Variant in path_tile_ids:
		var center := _center_for(tile_centers, int(tile_variant))
		if center == Vector2.INF:
			return {"valid": false, "error": "missing_tile_center"}
		if raw_points.is_empty() or not raw_points[-1].is_equal_approx(center):
			raw_points.append(center)
	if closed and raw_points.size() > 2 and raw_points[0].is_equal_approx(raw_points[-1]):
		raw_points.remove_at(raw_points.size() - 1)
	if raw_points.size() < 2:
		return {"valid": false, "error": "path_too_short"}
	var curve_result := (
		_build_closed_curve(raw_points, corner_radius)
		if closed and raw_points.size() >= 3
		else _build_open_curve(raw_points, corner_radius)
	)
	if not bool(curve_result.get("valid", false)):
		return curve_result
	var geometry := _geometry_from_points(curve_result.get("baked_points", PackedVector2Array()), closed)
	geometry["source_points"] = raw_points
	geometry["corner_contracts"] = Array(curve_result.get("corner_contracts", [])).duplicate(true)
	geometry["endpoint_start"] = geometry.get("baked_points", PackedVector2Array())[0]
	geometry["endpoint_end"] = geometry.get("baked_points", PackedVector2Array())[-1]
	return geometry


static func build_bidirectional_route(
	path_tile_ids: Array,
	tile_centers: Dictionary,
	lane_offset: float = DEFAULT_LANE_OFFSET
) -> Dictionary:
	var centerline := build_centerline(path_tile_ids, tile_centers, false)
	if not bool(centerline.get("valid", false)):
		return centerline
	var center_points: PackedVector2Array = centerline.get("baked_points", PackedVector2Array())
	if center_points.size() < 2:
		return {"valid": false, "error": "centerline_too_short"}
	var safe_offset := maxf(1.0, lane_offset)
	var forward_points := offset_polyline(center_points, safe_offset)
	var reversed_center := _reversed_points(center_points)
	var reverse_points := offset_polyline(reversed_center, safe_offset)
	var start_tangent := (center_points[1] - center_points[0]).normalized()
	var end_tangent := (center_points[-1] - center_points[-2]).normalized()
	var cap_reach := maxf(safe_offset * 1.35, 4.0)

	var end_cap := _sample_cubic(
		forward_points[-1],
		forward_points[-1] + end_tangent * cap_reach,
		reverse_points[0] + end_tangent * cap_reach,
		reverse_points[0],
		TERMINAL_CAP_SAMPLES
	)
	var start_cap := _sample_cubic(
		reverse_points[-1],
		reverse_points[-1] - start_tangent * cap_reach,
		forward_points[0] - start_tangent * cap_reach,
		forward_points[0],
		TERMINAL_CAP_SAMPLES
	)

	var loop_points := PackedVector2Array(forward_points)
	_append_without_first(loop_points, end_cap)
	_append_without_first(loop_points, reverse_points)
	_append_without_first(loop_points, start_cap)
	var geometry := _geometry_from_points(loop_points, true)
	if not bool(geometry.get("valid", false)):
		return geometry
	var forward_length := _polyline_length(forward_points)
	var end_cap_length := _polyline_length(end_cap)
	var reverse_length := _polyline_length(reverse_points)
	geometry["source_points"] = centerline.get("source_points", PackedVector2Array())
	geometry["centerline_points"] = center_points
	geometry["forward_points"] = forward_points
	geometry["reverse_points"] = reverse_points
	geometry["end_cap_points"] = end_cap
	geometry["start_cap_points"] = start_cap
	geometry["lane_offset"] = safe_offset
	geometry["forward_end_distance"] = forward_length
	geometry["reverse_start_distance"] = forward_length + end_cap_length
	geometry["reverse_end_distance"] = forward_length + end_cap_length + reverse_length
	geometry["centerline_fingerprint"] = geometry_fingerprint(centerline)
	geometry["bidirectional"] = true
	geometry["terminal_caps"] = 2
	return geometry


static func sample_geometry(geometry: Dictionary, distance: float) -> Dictionary:
	var points: PackedVector2Array = geometry.get("baked_points", PackedVector2Array())
	var cumulative: PackedFloat32Array = geometry.get("cumulative_lengths", PackedFloat32Array())
	var total_length := float(geometry.get("length", 0.0))
	if points.size() < 2 or cumulative.size() != points.size() or total_length <= EPSILON:
		return {"valid": false}
	var target := fposmod(distance, total_length) if bool(geometry.get("closed", false)) else clampf(distance, 0.0, total_length)
	for index in range(points.size() - 1):
		var segment_start := float(cumulative[index])
		var segment_end := float(cumulative[index + 1])
		if target > segment_end and index < points.size() - 2:
			continue
		var segment_length := maxf(segment_end - segment_start, EPSILON)
		var local := clampf((target - segment_start) / segment_length, 0.0, 1.0)
		var tangent := (points[index + 1] - points[index]).normalized()
		var lane_direction := 0
		if geometry.has("forward_end_distance"):
			if target <= float(geometry.get("forward_end_distance", 0.0)) + EPSILON:
				lane_direction = 1
			elif target <= float(geometry.get("reverse_end_distance", total_length)) + EPSILON:
				lane_direction = -1
			else:
				lane_direction = 1
		return {
			"valid": true,
			"position": points[index].lerp(points[index + 1], local),
			"angle": tangent.angle(),
			"tangent": tangent,
			"distance": target,
			"segment_index": index,
			"lane_direction": lane_direction,
		}
	return {"valid": false}


static func offset_polyline(points: PackedVector2Array, offset: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	if points.size() < 2:
		return result
	for index in points.size():
		var tangent: Vector2
		if index == 0:
			tangent = points[1] - points[0]
		elif index == points.size() - 1:
			tangent = points[-1] - points[-2]
		else:
			tangent = points[index + 1] - points[index - 1]
		if tangent.length_squared() <= EPSILON:
			tangent = Vector2.RIGHT
		result.append(points[index] + tangent.normalized().orthogonal() * offset)
	return result


static func geometry_fingerprint(geometry: Dictionary) -> String:
	var canonical: Array = []
	var points: PackedVector2Array = geometry.get("baked_points", PackedVector2Array())
	for point: Vector2 in points:
		canonical.append([snappedf(point.x, 0.001), snappedf(point.y, 0.001)])
	return JSON.stringify(canonical).sha256_text()


static func _build_open_curve(points: PackedVector2Array, corner_radius: float) -> Dictionary:
	var curve := Curve2D.new()
	curve.bake_interval = DEFAULT_BAKE_INTERVAL
	var corners: Array[Dictionary] = []
	curve.add_point(points[0])
	for index in range(1, points.size() - 1):
		var corner := _corner_contract(points[index - 1], points[index], points[index + 1], corner_radius)
		if not bool(corner.get("rounded", false)):
			curve.add_point(points[index])
			continue
		curve.add_point(
			Vector2(corner["entry"]),
			Vector2.ZERO,
			Vector2(corner["entry_out_handle"])
		)
		curve.add_point(
			Vector2(corner["exit"]),
			Vector2(corner["exit_in_handle"]),
			Vector2.ZERO
		)
		corners.append(corner)
	curve.add_point(points[-1])
	var baked := curve.get_baked_points()
	if baked.size() < 2:
		return {"valid": false, "error": "curve_bake_failed"}
	baked[0] = points[0]
	baked[-1] = points[-1]
	return {"valid": true, "baked_points": baked, "corner_contracts": corners}


static func _build_closed_curve(points: PackedVector2Array, corner_radius: float) -> Dictionary:
	var contracts: Array[Dictionary] = []
	for index in points.size():
		contracts.append(_corner_contract(
			points[(index - 1 + points.size()) % points.size()],
			points[index],
			points[(index + 1) % points.size()],
			corner_radius
		))
	var curve := Curve2D.new()
	curve.bake_interval = DEFAULT_BAKE_INTERVAL
	var first: Dictionary = contracts[0]
	curve.add_point(Vector2(first.get("exit", points[0])))
	for index in range(1, points.size()):
		var corner: Dictionary = contracts[index]
		if not bool(corner.get("rounded", false)):
			curve.add_point(points[index])
			continue
		curve.add_point(Vector2(corner["entry"]), Vector2.ZERO, Vector2(corner["entry_out_handle"]))
		curve.add_point(Vector2(corner["exit"]), Vector2(corner["exit_in_handle"]), Vector2.ZERO)
	if bool(first.get("rounded", false)):
		curve.add_point(Vector2(first["entry"]), Vector2.ZERO, Vector2(first["entry_out_handle"]))
		curve.add_point(Vector2(first["exit"]), Vector2(first["exit_in_handle"]), Vector2.ZERO)
	else:
		curve.add_point(points[0])
	var baked := curve.get_baked_points()
	if baked.size() < 3:
		return {"valid": false, "error": "closed_curve_bake_failed"}
	baked[-1] = baked[0]
	var rounded_contracts: Array[Dictionary] = []
	for contract_variant: Variant in contracts:
		if bool(Dictionary(contract_variant).get("rounded", false)):
			rounded_contracts.append(Dictionary(contract_variant))
	return {"valid": true, "baked_points": baked, "corner_contracts": rounded_contracts}


static func _corner_contract(previous: Vector2, vertex: Vector2, next: Vector2, radius: float) -> Dictionary:
	var incoming := (vertex - previous).normalized()
	var outgoing := (next - vertex).normalized()
	if incoming.length_squared() <= EPSILON or outgoing.length_squared() <= EPSILON:
		return {"rounded": false, "vertex": vertex}
	if absf(incoming.cross(outgoing)) <= EPSILON and incoming.dot(outgoing) > 0.0:
		return {"rounded": false, "vertex": vertex}
	var safe_radius := minf(
		minf(maxf(1.0, radius), previous.distance_to(vertex) * 0.35),
		vertex.distance_to(next) * 0.35
	)
	var entry := vertex - incoming * safe_radius
	var exit := vertex + outgoing * safe_radius
	return {
		"rounded": true,
		"vertex": vertex,
		"entry": entry,
		"exit": exit,
		"entry_out_handle": (vertex - entry) * (2.0 / 3.0),
		"exit_in_handle": (vertex - exit) * (2.0 / 3.0),
		"incoming_tangent": incoming,
		"entry_tangent": incoming,
		"exit_tangent": outgoing,
		"outgoing_tangent": outgoing,
		"radius": safe_radius,
	}


static func _geometry_from_points(points: PackedVector2Array, closed: bool) -> Dictionary:
	if points.size() < 2:
		return {"valid": false, "error": "geometry_too_short"}
	var cumulative := PackedFloat32Array([0.0])
	var total_length := 0.0
	for index in range(points.size() - 1):
		total_length += points[index].distance_to(points[index + 1])
		cumulative.append(total_length)
	if total_length <= EPSILON:
		return {"valid": false, "error": "geometry_zero_length"}
	var result := {
		"valid": true,
		"closed": closed,
		"baked_points": PackedVector2Array(points),
		"cumulative_lengths": cumulative,
		"length": total_length,
	}
	result["fingerprint"] = geometry_fingerprint(result)
	return result


static func _sample_cubic(
	p0: Vector2,
	p1: Vector2,
	p2: Vector2,
	p3: Vector2,
	sample_count: int
) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in range(maxi(2, sample_count) + 1):
		var t := float(index) / float(maxi(2, sample_count))
		var inverse := 1.0 - t
		result.append(
			p0 * inverse * inverse * inverse
			+ p1 * 3.0 * inverse * inverse * t
			+ p2 * 3.0 * inverse * t * t
			+ p3 * t * t * t
		)
	return result


static func _append_without_first(target: PackedVector2Array, source: PackedVector2Array) -> void:
	for index in range(1, source.size()):
		target.append(source[index])


static func _reversed_points(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in range(points.size() - 1, -1, -1):
		result.append(points[index])
	return result


static func _polyline_length(points: PackedVector2Array) -> float:
	var result := 0.0
	for index in range(points.size() - 1):
		result += points[index].distance_to(points[index + 1])
	return result


static func _center_for(tile_centers: Dictionary, tile_id: int) -> Vector2:
	var value: Variant = tile_centers.get(str(tile_id), tile_centers.get(tile_id, null))
	return value if value is Vector2 else Vector2.INF


static func _adjacency_by_kind(tile_states: Dictionary, tile_centers: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for tile_key_variant: Variant in tile_states.keys():
		var tile_id := int(str(tile_key_variant))
		if _center_for(tile_centers, tile_id) == Vector2.INF:
			continue
		var state_value: Variant = tile_states[tile_key_variant]
		if not state_value is Dictionary:
			continue
		var state: Dictionary = state_value
		var connections: Dictionary = state.get("connections", {})
		var neighbours: Dictionary = state.get("neighbours", {})
		for kind_variant: Variant in state.get("segments", []):
			var kind := str(kind_variant)
			if kind.is_empty():
				continue
			var adjacency: Dictionary = result.get(kind, {})
			if not adjacency.has(tile_id):
				adjacency[tile_id] = []
			for direction_variant: Variant in connections.get(kind, []):
				var neighbour_id := int(neighbours.get(str(direction_variant), -1))
				if neighbour_id < 0 or _center_for(tile_centers, neighbour_id) == Vector2.INF:
					continue
				var neighbour_value: Variant = tile_states.get(str(neighbour_id), tile_states.get(neighbour_id, null))
				if not neighbour_value is Dictionary or kind not in Array(Dictionary(neighbour_value).get("segments", [])):
					continue
				var current_neighbours: Array = adjacency.get(tile_id, [])
				if not current_neighbours.has(neighbour_id):
					current_neighbours.append(neighbour_id)
				adjacency[tile_id] = current_neighbours
				var reverse_neighbours: Array = adjacency.get(neighbour_id, [])
				if not reverse_neighbours.has(tile_id):
					reverse_neighbours.append(tile_id)
				adjacency[neighbour_id] = reverse_neighbours
			result[kind] = adjacency
	for kind_variant: Variant in result.keys():
		var adjacency: Dictionary = result[kind_variant]
		for tile_variant: Variant in adjacency.keys():
			var neighbours: Array = adjacency[tile_variant]
			neighbours.sort()
			adjacency[tile_variant] = neighbours
		result[kind_variant] = adjacency
	return result


static func _extract_graph_paths(adjacency: Dictionary) -> Array:
	var result: Array = []
	var visited: Dictionary = {}
	var nodes: Array[int] = []
	for node_variant: Variant in adjacency.keys():
		nodes.append(int(node_variant))
	nodes.sort()
	for node: int in nodes:
		var neighbours: Array = adjacency.get(node, [])
		if neighbours.is_empty():
			result.append([node])
			continue
		if neighbours.size() == 2:
			continue
		for neighbour_variant: Variant in neighbours:
			var neighbour := int(neighbour_variant)
			if visited.has(_edge_key(node, neighbour)):
				continue
			result.append(_trace_path(node, neighbour, adjacency, visited))
	for node: int in nodes:
		for neighbour_variant: Variant in adjacency.get(node, []):
			var neighbour := int(neighbour_variant)
			if visited.has(_edge_key(node, neighbour)):
				continue
			result.append(_trace_path(node, neighbour, adjacency, visited))
	return result


static func _trace_path(start: int, first: int, adjacency: Dictionary, visited: Dictionary) -> Array:
	var path: Array = [start, first]
	visited[_edge_key(start, first)] = true
	var previous := start
	var current := first
	while true:
		var neighbours: Array = adjacency.get(current, [])
		if current == start or neighbours.size() != 2:
			break
		var next := int(neighbours[0]) if int(neighbours[0]) != previous else int(neighbours[1])
		var edge := _edge_key(current, next)
		if visited.has(edge):
			if next == start and int(path[-1]) != start:
				path.append(start)
			break
		visited[edge] = true
		path.append(next)
		previous = current
		current = next
	return path


static func _edge_key(first: int, second: int) -> String:
	return "%d:%d" % [mini(first, second), maxi(first, second)]


static func _path_classification(
	path: Array,
	tile_centers: Dictionary,
	adjacency: Dictionary,
	closed: bool
) -> String:
	if closed:
		return "loop"
	if Array(adjacency.get(int(path[0]), [])).size() > 2 or Array(adjacency.get(int(path[-1]), [])).size() > 2:
		return "crossing_branch"
	if path.size() <= 2:
		return "terminal"
	for index in range(1, path.size() - 1):
		var previous := _center_for(tile_centers, int(path[index - 1]))
		var current := _center_for(tile_centers, int(path[index]))
		var next := _center_for(tile_centers, int(path[index + 1]))
		if absf((current - previous).normalized().cross((next - current).normalized())) > EPSILON:
			return "turn"
	return "straight"
