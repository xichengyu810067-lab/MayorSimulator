extends Control

const SquareGridLayoutScript = preload("res://scripts/world/square_grid_layout.gd")
const CityTerrainMapScript = preload("res://scripts/world/city_terrain_map.gd")

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
			"non_flat_fill_max_alpha": 0.0,
			"persistent_terrain_overlay": false,
			"interactive_grid_owner": "CityTileButton",
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
	var grid_bounds := SquareGridLayoutScript.grid_rect()
	draw_rect(grid_bounds.grow(12.0), Color(0.91, 0.86, 0.68, 0.58), false, 2.0)
