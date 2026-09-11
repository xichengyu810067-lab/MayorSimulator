class_name TransportNetworkLayer
extends Control

const SquareGridLayoutScript = preload("res://scripts/world/square_grid_layout.gd")
const TransportRouteGeometryScript = preload("res://scripts/world/transport_route_geometry.gd")

## Static and construction-state rendering for the player-authored transport
## graph.  Vehicles deliberately live in TransportVehicleController so an
## isolated tile or station can never invent its own traffic.

const SEGMENT_COLORS := {
	"road": Color(0.16, 0.19, 0.23, 0.98),
	"metro_track": Color(0.10, 0.42, 0.67, 0.98),
	"rail_track": Color(0.30, 0.25, 0.20, 0.98),
	"runway": Color(0.12, 0.14, 0.17, 0.98),
	"taxiway": Color(0.22, 0.25, 0.29, 0.98),
}

var _network_snapshot: Dictionary = {}
var _tile_centers: Dictionary = {}
var _crossing_states: Dictionary = {}
var _corridor_geometries: Array[Dictionary] = []
var _route_geometries: Dictionary = {}
var _dark_mode := false


func _ready() -> void:
	name = "TransportNetworkLayer"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_redraw()


func set_network_snapshot(snapshot: Dictionary, tile_centers: Dictionary) -> void:
	_network_snapshot = snapshot.duplicate(true)
	_tile_centers = tile_centers.duplicate(true)
	var completed_states: Dictionary = _network_snapshot.get(
		"completed_tile_states",
		_network_snapshot.get("tile_states", {})
	)
	_corridor_geometries = TransportRouteGeometryScript.build_corridor_geometries(
		completed_states,
		_tile_centers
	)
	_route_geometries = TransportRouteGeometryScript.build_operational_route_geometries(
		_network_snapshot,
		_tile_centers
	)
	queue_redraw()


func set_crossing_states(states: Dictionary) -> void:
	_crossing_states = states.duplicate(true)
	queue_redraw()


func set_dark_mode(enabled: bool) -> void:
	_dark_mode = enabled
	queue_redraw()


func debug_snapshot() -> Dictionary:
	var access_segments := _project_station_access_segments()
	var connected_junctions := _project_connected_junctions()
	var corridor_debug: Array[Dictionary] = []
	for geometry: Dictionary in _corridor_geometries:
		corridor_debug.append({
			"kind": str(geometry.get("kind", "")),
			"classification": str(geometry.get("classification", "")),
			"path_tile_ids": Array(geometry.get("path_tile_ids", [])).duplicate(),
			"length": float(geometry.get("length", 0.0)),
			"fingerprint": str(geometry.get("fingerprint", "")),
		})
	var route_debug: Dictionary = {}
	for route_key_variant: Variant in _route_geometries.keys():
		var route_id := str(route_key_variant)
		var geometry: Dictionary = _route_geometries[route_id]
		route_debug[route_id] = {
			"fingerprint": str(geometry.get("fingerprint", "")),
			"centerline_fingerprint": str(geometry.get("centerline_fingerprint", "")),
			"bidirectional": bool(geometry.get("bidirectional", false)),
			"lane_offset": float(geometry.get("lane_offset", 0.0)),
		}
	return {
		"owned_by_player_network": true,
		"autonomous_vehicle_generation": false,
		"shares_map_stage_transform": get_parent() != null,
		"tile_state_count": Dictionary(_network_snapshot.get("tile_states", {})).size(),
		"operational_line_count": Array(_network_snapshot.get("operational_lines", [])).size(),
		"station_access_edge_count": Array(_network_snapshot.get("station_access_edges", [])).size(),
		"station_access_segments": access_segments,
		"completed_tile_state_count": Dictionary(_network_snapshot.get("completed_tile_states", _network_snapshot.get("tile_states", {}))).size(),
		"corridor_geometry_count": _corridor_geometries.size(),
		"corridor_geometries": corridor_debug,
		"route_geometries": route_debug,
		"connected_junction_count": connected_junctions.size(),
		"connected_junctions": connected_junctions,
		"crossing_states": _crossing_states.duplicate(true),
	}


func _draw() -> void:
	_draw_completed_corridors()
	_draw_station_access_edges()
	_draw_operational_route_lanes()
	var tile_states: Dictionary = _network_snapshot.get("tile_states", {})
	var completed_tile_states: Dictionary = _network_snapshot.get("completed_tile_states", tile_states)
	var sorted_tiles: Array[int] = []
	for key_variant: Variant in tile_states.keys():
		sorted_tiles.append(int(str(key_variant)))
	sorted_tiles.sort()
	for tile_id: int in sorted_tiles:
		var state: Dictionary = tile_states.get(str(tile_id), tile_states.get(tile_id, {}))
		var center := _center_for(tile_id)
		if center == Vector2.INF:
			continue
		var completed_state: Dictionary = completed_tile_states.get(
			str(tile_id),
			completed_tile_states.get(tile_id, {})
		)
		_draw_pending_tile_segments(tile_id, center, state, completed_state)
		_draw_facilities(center, Array(state.get("facilities", [])))
		var crossing := str(state.get("crossing", ""))
		if not crossing.is_empty():
			_draw_level_crossing(tile_id, center, crossing)
		var project_status := str(state.get("project_status", ""))
		if project_status in ["planned", "under_construction", "demolishing"]:
			_draw_construction_marker(center, project_status)


func _draw_completed_corridors() -> void:
	for geometry: Dictionary in _corridor_geometries:
		_draw_corridor_geometry(str(geometry.get("kind", "road")), geometry)
	for junction: Dictionary in _project_connected_junctions():
		if Array(junction.get("directions", [])).size() >= 3:
			_draw_connected_junction(
				Vector2(junction.get("center", Vector2.INF)),
				str(junction.get("kind", "road")),
				Array(junction.get("directions", []))
			)


func _draw_corridor_geometry(kind: String, geometry: Dictionary) -> void:
	var points: PackedVector2Array = geometry.get("baked_points", PackedVector2Array())
	if points.size() < 2:
		return
	var color: Color = SEGMENT_COLORS.get(kind, Color(0.25, 0.28, 0.31))
	match kind:
		"road":
			draw_polyline(points, Color(0.04, 0.05, 0.06, 0.42), 21.0, true)
			draw_polyline(points, color, 17.0, true)
			draw_polyline(points, Color(0.96, 0.82, 0.28, 0.82), 1.2, true)
		"metro_track", "rail_track":
			draw_polyline(points, Color(0.33, 0.27, 0.20, 0.78), 14.0, true)
			for offset in [-4.5, 4.5]:
				var rail_points := TransportRouteGeometryScript.offset_polyline(points, offset)
				draw_polyline(rail_points, color, 3.2, true)
				draw_polyline(rail_points, Color(0.80, 0.88, 0.92, 0.96), 1.0, true)
			var sleeper_distance := 0.0
			while sleeper_distance <= float(geometry.get("length", 0.0)):
				var sample: Dictionary = TransportRouteGeometryScript.sample_geometry(geometry, sleeper_distance)
				if bool(sample.get("valid", false)):
					var center := Vector2(sample["position"])
					var normal := Vector2(sample["tangent"]).orthogonal()
					draw_line(center - normal * 7.0, center + normal * 7.0, Color(0.29, 0.19, 0.12, 0.90), 1.4, true)
				sleeper_distance += 10.0
		"runway":
			draw_polyline(points, Color(0.04, 0.05, 0.07, 0.50), 31.0, true)
			draw_polyline(points, color, 27.0, true)
			draw_polyline(points, Color(1.0, 1.0, 1.0, 0.84), 1.5, true)
		"taxiway":
			draw_polyline(points, Color(0.05, 0.06, 0.08, 0.42), 17.0, true)
			draw_polyline(points, color, 13.0, true)
			draw_polyline(points, Color(0.98, 0.78, 0.12, 0.96), 1.5, true)


func _draw_operational_route_lanes() -> void:
	var route_ids: Array[String] = []
	for route_variant: Variant in _route_geometries.keys():
		route_ids.append(str(route_variant))
	route_ids.sort()
	for route_id: String in route_ids:
		var geometry: Dictionary = _route_geometries[route_id]
		var color := _route_color(route_id, str(geometry.get("mode", "road")))
		for lane_key: String in ["forward_points", "reverse_points"]:
			var points: PackedVector2Array = geometry.get(lane_key, PackedVector2Array())
			if points.size() >= 2:
				draw_polyline(points, color, 2.2, true)


func _draw_pending_tile_segments(
	tile_id: int,
	center: Vector2,
	state: Dictionary,
	completed_state: Dictionary
) -> void:
	var completed_kinds: Array = completed_state.get("segments", [])
	var connections: Dictionary = state.get("connections", {})
	for kind_variant: Variant in state.get("segments", []):
		var kind := str(kind_variant)
		if completed_kinds.has(kind):
			continue
		var directions: Array = connections.get(kind, [])
		if directions.is_empty():
			draw_dashed_line(center - Vector2(22, 0), center + Vector2(22, 0), Color(1.0, 0.66, 0.08, 0.92), 4.0, 6.0, true)
			continue
		for direction_variant: Variant in directions:
			var neighbour_center := _center_for(_neighbour_for(tile_id, str(direction_variant)))
			if neighbour_center != Vector2.INF:
				draw_dashed_line(center, center.lerp(neighbour_center, 0.54), Color(1.0, 0.66, 0.08, 0.92), 4.0, 6.0, true)


func _route_color(route_id: String, mode: String) -> Color:
	var base: Color = {
		"bus": Color(0.18, 0.86, 0.66, 0.72),
		"metro": Color(0.20, 0.68, 1.0, 0.78),
		"train": Color(1.0, 0.55, 0.24, 0.76),
		"air": Color(0.84, 0.92, 1.0, 0.72),
	}.get(mode, Color(0.96, 0.82, 0.28, 0.72))
	var stable := 0
	for index in route_id.length():
		stable = (stable * 31 + route_id.unicode_at(index)) % 17
	return Color.from_hsv(
		fposmod(base.h + float(stable) * 0.008, 1.0),
		base.s,
		base.v,
		base.a
	)


func _draw_station_access_edges() -> void:
	# Draw only edges derived by TransportNetworkSystem from completed topology.
	# The layer never fabricates a connector from station proximity alone.
	for segment_variant: Variant in _project_station_access_segments():
		var segment: Dictionary = segment_variant
		_draw_segment(
			str(segment.get("kind", "road")),
			Vector2(segment.get("from", Vector2.INF)),
			Vector2(segment.get("to", Vector2.INF))
		)


func _project_station_access_segments() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for edge_variant: Variant in _network_snapshot.get("station_access_edges", []):
		if not edge_variant is Dictionary:
			continue
		var edge: Dictionary = edge_variant
		var network_center := _center_for(int(edge.get("network_tile_id", -1)))
		var station_center := _center_for(int(edge.get("station_tile_id", -1)))
		if network_center == Vector2.INF or station_center == Vector2.INF:
			continue
		result.append({
			"station_id": str(edge.get("station_id", "")),
			"kind": str(edge.get("kind", "road")),
			"from": network_center,
			"to": station_center,
		})
	return result


func _draw_tile_segments(tile_id: int, center: Vector2, state: Dictionary) -> void:
	var connections: Dictionary = state.get("connections", {})
	for kind_variant: Variant in state.get("segments", []):
		var kind := str(kind_variant)
		var directions: Array = connections.get(kind, [])
		if directions.is_empty():
			_draw_segment_stub(center, kind)
			continue
		for direction_variant: Variant in directions:
			var direction := str(direction_variant)
			var neighbour_id := _neighbour_for(tile_id, direction)
			var neighbour_center := _center_for(neighbour_id)
			if neighbour_center == Vector2.INF:
				continue
			_draw_segment(kind, center, center.lerp(neighbour_center, 0.54))
		_draw_connected_junction(center, kind, directions)


func _project_connected_junctions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var tile_states: Dictionary = _network_snapshot.get(
		"completed_tile_states",
		_network_snapshot.get("tile_states", {})
	)
	var sorted_tiles: Array[int] = []
	for key_variant: Variant in tile_states.keys():
		sorted_tiles.append(int(str(key_variant)))
	sorted_tiles.sort()
	for tile_id: int in sorted_tiles:
		var state: Dictionary = tile_states.get(str(tile_id), tile_states.get(tile_id, {}))
		var connections: Dictionary = state.get("connections", {})
		for kind_variant: Variant in state.get("segments", []):
			var kind := str(kind_variant)
			var contract := connected_junction_contract(_center_for(tile_id), kind, connections.get(kind, []))
			if contract.is_empty():
				continue
			contract["tile_id"] = tile_id
			result.append(contract)
	return result


static func connected_junction_contract(center: Vector2, kind: String, directions: Array) -> Dictionary:
	if center == Vector2.INF or kind not in SEGMENT_COLORS:
		return {}
	var unique_directions: Array[String] = []
	for direction_variant: Variant in directions:
		var direction := str(direction_variant)
		if direction in ["n", "e", "s", "w"] and direction not in unique_directions:
			unique_directions.append(direction)
	if unique_directions.size() < 2:
		return {}
	unique_directions.sort()
	var has_horizontal := "e" in unique_directions or "w" in unique_directions
	var has_vertical := "n" in unique_directions or "s" in unique_directions
	return {
		"kind": kind,
		"center": center,
		"directions": unique_directions,
		"has_perpendicular_turn": has_horizontal and has_vertical,
		"filled_center": true,
	}


func _draw_connected_junction(center: Vector2, kind: String, directions: Array) -> void:
	if connected_junction_contract(center, kind, directions).is_empty():
		return
	var color: Color = SEGMENT_COLORS.get(kind, Color(0.25, 0.28, 0.31))
	match kind:
		"road":
			draw_circle(center, 10.5, Color(0.04, 0.05, 0.06, 0.42))
			draw_circle(center, 8.5, color)
			draw_circle(center, 1.5, Color(0.96, 0.82, 0.28, 0.92))
		"metro_track", "rail_track":
			draw_circle(center, 7.0, Color(0.33, 0.27, 0.20, 0.78))
			draw_circle(center, 5.2, color)
			draw_circle(center, 1.5, Color(0.80, 0.88, 0.92, 0.96))
		"runway":
			draw_circle(center, 15.5, Color(0.04, 0.05, 0.07, 0.50))
			draw_circle(center, 13.5, color)
			draw_circle(center, 1.8, Color.WHITE)
		"taxiway":
			draw_circle(center, 8.5, Color(0.05, 0.06, 0.08, 0.42))
			draw_circle(center, 6.5, color)
			draw_circle(center, 1.4, Color(0.98, 0.78, 0.12, 0.96))


func _draw_segment_stub(center: Vector2, kind: String) -> void:
	var tangent := Vector2(27.0, 0.0)
	if kind in ["runway", "taxiway"]:
		tangent = Vector2(34.0, 0.0)
	_draw_segment(kind, center - tangent, center + tangent)


func _draw_segment(kind: String, from: Vector2, to: Vector2) -> void:
	var color: Color = SEGMENT_COLORS.get(kind, Color(0.25, 0.28, 0.31))
	match kind:
		"road":
			draw_line(from, to, Color(0.04, 0.05, 0.06, 0.42), 21.0, true)
			draw_line(from, to, color, 17.0, true)
			draw_dashed_line(from, to, Color(0.96, 0.82, 0.28, 0.92), 1.8, 7.0, true)
		"metro_track", "rail_track":
			var vector := to - from
			var normal := vector.normalized().orthogonal() if vector.length() > 0.01 else Vector2.UP
			draw_line(from, to, Color(0.33, 0.27, 0.20, 0.78), 14.0, true)
			for offset in [-4.5, 4.5]:
				draw_line(from + normal * offset, to + normal * offset, color, 3.2, true)
				draw_line(from + normal * offset, to + normal * offset, Color(0.80, 0.88, 0.92, 0.96), 1.0, true)
			var length := vector.length()
			if length > 1.0:
				for step in range(0, int(length), 10):
					var p := from + vector.normalized() * float(step)
					draw_line(p - normal * 7.0, p + normal * 7.0, Color(0.29, 0.19, 0.12, 0.90), 1.4, true)
		"runway":
			draw_line(from, to, Color(0.04, 0.05, 0.07, 0.50), 31.0, true)
			draw_line(from, to, color, 27.0, true)
			draw_dashed_line(from, to, Color.WHITE, 2.3, 11.0, true)
		"taxiway":
			draw_line(from, to, Color(0.05, 0.06, 0.08, 0.42), 17.0, true)
			draw_line(from, to, color, 13.0, true)
			draw_line(from, to, Color(0.98, 0.78, 0.12, 0.96), 1.5, true)


func _draw_facilities(center: Vector2, facilities: Array) -> void:
	for facility_variant: Variant in facilities:
		var facility := str(facility_variant)
		match facility:
			"bus_depot":
				draw_rect(Rect2(center + Vector2(-19, -14), Vector2(38, 28)), Color(0.08, 0.55, 0.49, 0.96), true)
				draw_string(ThemeDB.fallback_font, center + Vector2(-13, 6), "BUS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
			"metro_depot":
				_draw_depot(center, Color(0.08, 0.50, 0.80), "M")
			"rail_depot":
				_draw_depot(center, Color(0.62, 0.32, 0.14), "R")
			"rail_signal":
				draw_line(center + Vector2(0, 15), center + Vector2(0, -11), Color(0.15, 0.12, 0.10), 3.0, true)
				draw_circle(center + Vector2(0, -13), 6.0, Color(0.11, 0.13, 0.15))
				draw_circle(center + Vector2(0, -14), 3.0, Color(0.95, 0.16, 0.12))


func _draw_depot(center: Vector2, color: Color, glyph: String) -> void:
	var body := Rect2(center + Vector2(-20, -15), Vector2(40, 30))
	draw_rect(body, color, true)
	draw_rect(body, Color(0.95, 0.98, 1.0, 0.85), false, 2.0)
	draw_string(ThemeDB.fallback_font, center + Vector2(-5, 6), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


func _draw_level_crossing(tile_id: int, center: Vector2, crossing_kind: String) -> void:
	var state: Dictionary = _crossing_states.get(str(tile_id), _crossing_states.get(tile_id, {}))
	var closed := bool(state.get("closed", false))
	var flash := bool(state.get("flash", false))
	var barrier_color := Color(0.96, 0.16, 0.12) if closed else Color(0.96, 0.78, 0.18)
	for side in [-1.0, 1.0]:
		var post := center + Vector2(23.0 * side, 2.0)
		draw_line(post + Vector2(0, 12), post + Vector2(0, -9), Color(0.18, 0.15, 0.12), 3.0, true)
		var arm_end := post + (Vector2(-24.0 * side, 0.0) if closed else Vector2(-16.0 * side, -18.0))
		draw_line(post + Vector2(0, -7), arm_end, Color.WHITE, 5.0, true)
		draw_dashed_line(post + Vector2(0, -7), arm_end, barrier_color, 2.0, 5.0, true)
		draw_circle(post + Vector2(0, -11), 4.5, Color(0.10, 0.11, 0.12))
		draw_circle(post + Vector2(0, -11), 2.5, Color(1.0, 0.12, 0.08) if flash else Color(0.45, 0.12, 0.10))
	draw_string(ThemeDB.fallback_font, center + Vector2(-20, 28), "平交道", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE if _dark_mode else Color(0.12, 0.10, 0.08))
	if crossing_kind.contains("metro"):
		draw_circle(center, 5.0, Color(0.10, 0.52, 0.83, 0.88))


func _draw_construction_marker(center: Vector2, status: String) -> void:
	var color := Color(1.0, 0.70, 0.08, 0.92) if status != "demolishing" else Color(0.94, 0.24, 0.16, 0.92)
	var polygon := construction_marker_points(center)
	for point_index in 4:
		draw_dashed_line(
			polygon[point_index],
			polygon[point_index + 1],
			color,
			3.0,
			6.0,
			true
		)


static func construction_marker_points(center: Vector2) -> PackedVector2Array:
	var half_size := SquareGridLayoutScript.CELL_SIZE * 0.5 - Vector2(6, 6)
	return PackedVector2Array([
		center + Vector2(-half_size.x, -half_size.y),
		center + Vector2(half_size.x, -half_size.y),
		center + Vector2(half_size.x, half_size.y),
		center + Vector2(-half_size.x, half_size.y),
		center + Vector2(-half_size.x, -half_size.y),
	])


func _center_for(tile_id: int) -> Vector2:
	if tile_id < 0:
		return Vector2.INF
	var value: Variant = _tile_centers.get(str(tile_id), _tile_centers.get(tile_id, null))
	return value if value is Vector2 else Vector2.INF


func _neighbour_for(tile_id: int, direction: String) -> int:
	var tile_states: Dictionary = _network_snapshot.get("tile_states", {})
	var state: Dictionary = tile_states.get(str(tile_id), tile_states.get(tile_id, {}))
	var neighbours: Dictionary = state.get("neighbours", {})
	return int(neighbours.get(direction, -1))
