extends Control

const SquareGridLayoutScript = preload("res://scripts/world/square_grid_layout.gd")
const CityTerrainMapScript = preload("res://scripts/world/city_terrain_map.gd")

const TERRAIN_COLORS := {
	"flat_grass": Color("7ead47"),
	"trees": Color("43763f"),
	"hill_cliff": Color("8a765d"),
	"river_lake": Color("3f91bd"),
	"road_path": Color("796f62"),
	"rail_track": Color("746556"),
}

var is_dark_mode := false
var bg_texture_rect: TextureRect
var _terrain_map = null
var _terrain_snapshot: Dictionary = {}

func _ready() -> void:
	var tex = load("res://assets/images/world/backgrounds/city-map-background.png")
	if tex:
		bg_texture_rect = TextureRect.new()
		bg_texture_rect.texture = tex
		bg_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg_texture_rect.z_index = -1
		add_child(bg_texture_rect)
		set_dark_mode(is_dark_mode)
	queue_redraw()


func set_terrain_snapshot(snapshot: Dictionary) -> bool:
	if snapshot == _terrain_snapshot and _terrain_map != null:
		return true
	var validation: Dictionary = CityTerrainMapScript.validate_snapshot(snapshot)
	if not bool(validation.get("valid", false)):
		return false
	_terrain_snapshot = snapshot.duplicate(true)
	_terrain_map = CityTerrainMapScript.create_from_dict(snapshot)
	queue_redraw()
	return true


func debug_terrain_projection() -> Dictionary:
	var projected_tiles: Dictionary = {}
	if _terrain_map != null:
		for tile_id in _terrain_map.cell_count():
			var coordinate: Vector2i = _terrain_map.coordinate_for_tile_id(tile_id)
			projected_tiles[str(tile_id)] = {
				"terrain_kind": _terrain_map.effective_kind(tile_id),
				"base_kind": _terrain_map.base_kind(tile_id),
				"flattened": _terrain_map.is_flattened(tile_id),
				"rect": SquareGridLayoutScript.rect_for_coordinate(coordinate),
			}
	return {
		"projection": "SquareGridLayout",
		"tile_count": projected_tiles.size(),
		"tiles": projected_tiles,
		"visual_policy": {
			"base_asset": "city-map-background.png",
			"background_primary": true,
			"flat_grass_fill_alpha": 0.0,
			"non_flat_fill_max_alpha": 0.18,
		},
	}

func set_dark_mode(enabled: bool) -> void:
	is_dark_mode = enabled
	if bg_texture_rect:
		if is_dark_mode:
			bg_texture_rect.modulate = Color(0.6, 0.6, 0.7)
		else:
			bg_texture_rect.modulate = Color.WHITE
	queue_redraw()


func _draw() -> void:
	if _terrain_map == null:
		return
	var grid_bounds := SquareGridLayoutScript.grid_rect()
	draw_rect(grid_bounds.grow(12.0), Color(0.91, 0.86, 0.68, 0.58), false, 2.0)
	for tile_id in _terrain_map.cell_count():
		var coordinate: Vector2i = _terrain_map.coordinate_for_tile_id(tile_id)
		var rect := SquareGridLayoutScript.rect_for_coordinate(coordinate)
		var kind: String = _terrain_map.effective_kind(tile_id)
		_draw_terrain_tile(rect, kind, tile_id)


func _draw_terrain_tile(rect: Rect2, kind: String, tile_id: int) -> void:
	var fill: Color = TERRAIN_COLORS.get(kind, TERRAIN_COLORS["flat_grass"])
	if is_dark_mode:
		fill = fill.darkened(0.32)
	if kind != "flat_grass":
		draw_rect(rect.grow(-1.0), Color(fill, 0.18 if not is_dark_mode else 0.13), true)
	draw_rect(rect.grow(-1.0), Color(0.94, 0.91, 0.76, 0.34), false, 1.0)
	var center := rect.get_center()
	match kind:
		"river_lake":
			_draw_water_marks(rect, center, tile_id)
		"trees":
			_draw_tree_marks(center, tile_id)
		"hill_cliff":
			_draw_hill_marks(center)
		"flat_grass":
			pass


func _draw_water_marks(rect: Rect2, center: Vector2, tile_id: int) -> void:
	var ripple := Color(0.82, 0.95, 1.0, 0.34 if not is_dark_mode else 0.24)
	var drift := float((tile_id * 11) % 9) - 4.0
	for offset_y in [-16.0, 0.0, 16.0]:
		var start := Vector2(rect.position.x + 10.0 + drift, center.y + offset_y)
		var end := Vector2(rect.end.x - 10.0 + drift, center.y + offset_y)
		draw_dashed_line(start, end, ripple, 1.5, 8.0, true)


func _draw_tree_marks(center: Vector2, tile_id: int) -> void:
	var leaf := Color(0.16, 0.38, 0.18, 0.28) if not is_dark_mode else Color(0.09, 0.22, 0.13, 0.24)
	var trunk := Color(0.35, 0.22, 0.12, 0.30)
	var shift := float((tile_id * 7) % 7) - 3.0
	for offset in [Vector2(-17.0 + shift, 8.0), Vector2(2.0, -10.0), Vector2(18.0 - shift, 10.0)]:
		draw_line(center + offset + Vector2(0, 6), center + offset + Vector2(0, 14), trunk, 3.0, true)
		draw_circle(center + offset, 10.0, leaf)
		draw_circle(center + offset + Vector2(-5, 2), 6.0, leaf.lightened(0.08))


func _draw_hill_marks(center: Vector2) -> void:
	var ridge := Color(0.93, 0.83, 0.62, 0.34) if not is_dark_mode else Color(0.62, 0.56, 0.46, 0.26)
	for scale_value: float in [1.0, 0.72]:
		var width: float = 25.0 * scale_value
		var height: float = 18.0 * scale_value
		var origin := center + Vector2((1.0 - scale_value) * 13.0, (1.0 - scale_value) * -8.0)
		var points := PackedVector2Array([
			origin + Vector2(-width, height),
			origin + Vector2(0, -height),
			origin + Vector2(width, height),
		])
		draw_polyline(PackedVector2Array([points[0], points[1], points[2]]), ridge, 2.0, true)
