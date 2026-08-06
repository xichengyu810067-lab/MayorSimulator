extends Button

const TransportActivityProfiles = preload("res://data/catalogs/transport_activity_profiles.gd")

const ANIMATION_REDRAW_FPS := 24.0
const ANIMATION_REDRAW_INTERVAL := 1.0 / ANIMATION_REDRAW_FPS
const ANIMATION_MAX_DELTA := 0.10

const AMBIENT_PROFILE_BY_BUILDING := {
	"住宅": "home_life",
	"社會住宅": "home_life",
	"商店": "commerce",
	"大型商場": "commerce",
	"工廠": "industry",
	"公園": "garden",
	"體育館": "civic_flags",
	"學校": "civic_flags",
	"圖書館": "quiet_lights",
	"醫院": "service_lights",
	"警局": "service_beacon",
	"消防局": "service_beacon",
	"停車場": "transport",
	"公車站": "transport",
	"捷運站": "transport",
	"火車站": "transport",
	"機場": "transport",
	"發電廠": "industry_steam",
	"核能發電廠": "industry_steam",
	"瓦斯場": "utility_pulse",
	"加油站": "transport",
	"自來水廠": "water_service",
	"游泳池": "water_service",
	"垃圾處理場": "industry",
	"法院": "civic_flags",
	"監察所": "civic_flags",
	"市政府": "civic_flags",
}

const AMBIENT_EFFECTS_BY_PROFILE := {
	"home_life": ["window_glow", "chimney_smoke"],
	"commerce": ["window_glow", "sign_sway"],
	"industry": ["chimney_smoke", "machinery_light"],
	"garden": ["vegetation_sway", "water_ripple"],
	"civic_flags": ["flag_sway", "window_glow"],
	"quiet_lights": ["window_glow", "light_glint"],
	"service_lights": ["window_glow", "beacon"],
	"service_beacon": ["beacon", "flag_sway"],
	"transport": ["station_lights", "light_glint"],
	"industry_steam": ["chimney_smoke", "steam", "machinery_light"],
	"utility_pulse": ["steam", "machinery_light"],
	"water_service": ["water_ripple", "light_glint"],
}

const ROOF_COLORS := [
	Color(0.18, 0.48, 0.88),
	Color(0.84, 0.22, 0.22),
	Color(0.20, 0.58, 0.34),
	Color(0.52, 0.30, 0.78),
	Color(0.95, 0.48, 0.66)
]
const WALL_COLORS := [
	Color(1.00, 0.91, 0.72),
	Color(1.00, 0.82, 0.54),
	Color(0.78, 0.90, 1.00),
	Color(1.00, 0.80, 0.88),
	Color(0.86, 0.96, 0.78)
]
const DECOR_COLORS := [
	Color(0.26, 0.72, 0.28),
	Color(0.92, 0.24, 0.28),
	Color(0.32, 0.49, 0.80)
]

var tile_index := 0
var building_name := ""
var building_color := Color.WHITE
var terrain_kind := 0
var terrain_type := "flat_ground"
var terrain_buildable := true
var terrain_flattenable := false
var terrain_flattened := false
var visual_shape := ""
var visual_detail := ""
var visual_asset_path := ""
var visual_texture: Texture2D
var custom_roof := -1
var custom_wall := -1
var custom_variant := -1
var custom_material := ""
var is_dark_mode := false
var selected := false
var is_building_mode := false
var placement_allowed := true
var construction_job: Dictionary = {}
var transport_activity_profile: Dictionary = {}
var ambient_animation_profile: Dictionary = {}
var _animation_time := 0.0
var _animation_draw_accumulator := 0.0

func _ready() -> void:
	text = ""
	# The map remains mouse-friendly, but every tile must also be reachable and
	# activatable with Tab/Enter/Space.
	focus_mode = Control.FOCUS_ALL
	clip_contents = false
	var empty := StyleBoxEmpty.new()
	add_theme_stylebox_override("normal", empty)
	add_theme_stylebox_override("hover", empty)
	add_theme_stylebox_override("pressed", empty)
	add_theme_stylebox_override("disabled", empty)
	var focus_ring := StyleBoxFlat.new()
	focus_ring.bg_color = Color(1.0, 0.86, 0.28, 0.08)
	focus_ring.border_color = Color(1.0, 0.78, 0.10, 0.96)
	focus_ring.set_border_width_all(4)
	focus_ring.set_corner_radius_all(10)
	add_theme_stylebox_override("focus", focus_ring)
	set_process(_has_active_visual_animation())


func _has_point(point: Vector2) -> bool:
	if size.x <= 0.0 or size.y <= 0.0:
		return false
	var center := size * 0.5
	var normalized := absf(point.x - center.x) / maxf(center.x, 1.0)
	normalized += absf(point.y - center.y) / maxf(center.y, 1.0)
	return normalized <= 1.0

func set_tile(data: Dictionary) -> void:
	tile_index = int(data.get("index", 0))
	building_name = str(data.get("building_name", ""))
	building_color = data.get("building_color", Color.WHITE)
	terrain_kind = int(data.get("terrain_kind", 0))
	terrain_type = str(data.get("terrain_type", "flat_ground")).strip_edges()
	if terrain_type.is_empty():
		terrain_type = "flat_ground"
	terrain_buildable = bool(data.get("terrain_buildable", true))
	terrain_flattenable = bool(data.get("terrain_flattenable", false))
	terrain_flattened = bool(data.get("terrain_flattened", false))
	var visual: Dictionary = data.get("visual", {})
	visual_shape = str(visual.get("shape", building_name))
	visual_detail = str(visual.get("detail", ""))
	var next_asset_path := str(visual.get("asset", ""))
	if next_asset_path != visual_asset_path:
		visual_asset_path = next_asset_path
		visual_texture = null
		if not visual_asset_path.is_empty() and ResourceLoader.exists(visual_asset_path):
			visual_texture = load(visual_asset_path) as Texture2D
	var customization: Dictionary = data.get("customization", {})
	custom_roof = int(customization.get("roof", -1))
	custom_wall = int(customization.get("wall", -1))
	custom_variant = int(customization.get("variant", -1))
	custom_material = str(customization.get("material", customization.get("material_id", "")))
	is_dark_mode = bool(data.get("dark_mode", false))
	selected = bool(data.get("selected", false))
	is_building_mode = bool(data.get("is_building_mode", false))
	placement_allowed = bool(data.get("placement_allowed", true))
	construction_job = Dictionary(data.get("construction", {})).duplicate(true)
	_refresh_animation_profiles()
	text = ""
	if not construction_job.is_empty():
		var job_name := str(construction_job.get("metadata", {}).get("building_name", "工程"))
		tooltip_text = L10n.text("%s｜施工中｜約 %d 天") % [
			L10n.text(job_name),
			int(construction_job.get("projected_remaining_days", 0))
		]
	elif building_name == "":
		if not terrain_buildable:
			tooltip_text = "%s｜%s" % [L10n.text(_terrain_label()), L10n.text("不可興建，請先整平地形")]
		else:
			tooltip_text = L10n.text("空地") if not is_building_mode or placement_allowed else L10n.text("頂部資訊列安全區｜不可施工")
	else:
		var material_label := _material_label(custom_material)
		tooltip_text = "%s - %s%s" % [
			L10n.text(building_name),
			L10n.text(visual_shape),
			" - %s" % L10n.text(material_label) if not material_label.is_empty() else ""
		]
	set_process(_has_active_visual_animation())
	queue_redraw()


func _process(delta: float) -> void:
	if not _has_active_visual_animation() or not is_visible_in_tree():
		return
	var safe_delta := minf(maxf(delta, 0.0), ANIMATION_MAX_DELTA)
	_animation_time = fposmod(_animation_time + safe_delta, 3600.0)
	_animation_draw_accumulator += safe_delta
	if _animation_draw_accumulator < ANIMATION_REDRAW_INTERVAL:
		return
	_animation_draw_accumulator = fposmod(_animation_draw_accumulator, ANIMATION_REDRAW_INTERVAL)
	queue_redraw()


func get_transport_activity_profile() -> Dictionary:
	return transport_activity_profile.duplicate(true)


func get_ambient_animation_profile() -> Dictionary:
	return ambient_animation_profile.duplicate(true)


func get_visual_animation_contract() -> Dictionary:
	return {
		"redraw_fps": ANIMATION_REDRAW_FPS,
		"redraw_interval": ANIMATION_REDRAW_INTERVAL,
		"max_runtime_delta": ANIMATION_MAX_DELTA,
		"clock_mode": "throttled_local_seconds",
		"transport_catalog_path": "res://data/catalogs/transport_activity_profiles.gd",
		"base_portrait_preserved": true,
		"ground_before_portrait": true,
		"vehicles_after_portrait": false,
		"autonomous_transport_vehicle_animation": false,
		"network_vehicle_layer_owner": "transport_network_controller",
		"terrain_type_supported": true,
		"natural_terrain_visual_source": "city-map-background.png",
		"decorative_natural_terrain_tiles": false,
		"flattened_ground_patch_only": true,
		"construction_animation_supported": true,
		"construction_replaces_portrait_until_complete": true,
	}


func get_visual_animation_debug_snapshot() -> Dictionary:
	# Transport profiles now describe static station/ground semantics only.  The
	# cross-tile network controller owns every moving vehicle and phase.
	var activity_phase := 0.0
	var ambient_loop := maxf(0.1, float(ambient_animation_profile.get("loop_seconds", 4.8)))
	var ambient_phase := fposmod(_animation_time / ambient_loop, 1.0)
	var profile_id := str(transport_activity_profile.get("id", ""))
	var ambient_id := str(ambient_animation_profile.get("id", ""))
	var signature_phase := ambient_phase if not ambient_id.is_empty() or not construction_job.is_empty() else 0.0
	return {
		"tile_index": tile_index,
		"building_name": building_name,
		"terrain_type": terrain_type,
		"terrain_flattened": terrain_flattened,
		"construction_active": not construction_job.is_empty(),
		"transport_profile_id": profile_id,
		"transport_profile": transport_activity_profile.duplicate(true),
		"transport_vehicle_animation_active": false,
		"ambient_profile_id": ambient_id,
		"ambient_profile": ambient_animation_profile.duplicate(true),
		"animation_active": _has_active_visual_animation(),
		"animation_time": _animation_time,
		"activity_phase": activity_phase,
		"ambient_phase": ambient_phase,
		"animation_signature": "%s|%s|%d" % [
			profile_id,
			ambient_id if construction_job.is_empty() else "construction_site",
			roundi(signature_phase * 1000.0),
		],
	}


func debug_set_animation_time(seconds: float) -> void:
	_animation_time = fposmod(maxf(0.0, seconds), 3600.0)
	_animation_draw_accumulator = 0.0
	queue_redraw()


func debug_advance_animation(delta: float) -> void:
	_animation_time = fposmod(_animation_time + maxf(0.0, delta), 3600.0)
	_animation_draw_accumulator = 0.0
	queue_redraw()


func _refresh_animation_profiles() -> void:
	transport_activity_profile = TransportActivityProfiles.profile_for_building(building_name)
	if transport_activity_profile.is_empty():
		transport_activity_profile = TransportActivityProfiles.profile_for_terrain(terrain_type)
	ambient_animation_profile = _ambient_profile_for_building(building_name)


func _ambient_profile_for_building(target_building_name: String) -> Dictionary:
	var profile_id := str(AMBIENT_PROFILE_BY_BUILDING.get(target_building_name, ""))
	if profile_id.is_empty():
		return {}
	return {
		"id": profile_id,
		"effects": Array(AMBIENT_EFFECTS_BY_PROFILE.get(profile_id, [])).duplicate(),
		"loop_seconds": 4.8,
	}


func _has_active_visual_animation() -> bool:
	return (
		not construction_job.is_empty()
		or not ambient_animation_profile.is_empty()
	)

func _draw() -> void:
	_draw_flattened_ground_patch()
	var should_draw_grid = is_hovered() or has_focus() or selected
	if should_draw_grid:
		_draw_terrain_overlay()
	if not transport_activity_profile.is_empty() and construction_job.is_empty():
		_draw_transport_activity_ground()

	if not construction_job.is_empty():
		_draw_construction_site()
	elif building_name != "":
		_draw_building_shadow()
		_draw_building()
		_draw_ambient_animation_overlay()

	if is_building_mode and is_hovered() and building_name == "" and construction_job.is_empty():
		if placement_allowed:
			_draw_placement_indicator()
		else:
			_draw_blocked_placement_indicator()

	if is_hovered() or selected:
		_draw_selection()


func _terrain_label() -> String:
	return str({
		"flat_ground": "平坦草地",
		"flat_grass": "平坦草地",
		"trees": "樹林",
		"hill_cliff": "山丘",
		"river_lake": "河流／湖泊",
		"road_path": "道路",
		"rail_track": "軌道",
	}.get(terrain_type, "地形"))


func _draw_flattened_ground_patch() -> void:
	# Natural trees, water, and cliffs remain part of the original backdrop.
	# Only completed earthworks cover the selected plot with reclaimed ground.
	if not terrain_flattened:
		return
	var center := size * 0.5
	var reclaimed_ground := PackedVector2Array([
		Vector2(center.x - 5, 10),
		Vector2(center.x + 20, 18),
		Vector2(size.x - 13, center.y - 7),
		Vector2(size.x - 18, center.y + 11),
		Vector2(center.x + 18, size.y - 13),
		Vector2(center.x - 8, size.y - 8),
		Vector2(17, center.y + 12),
		Vector2(12, center.y - 7),
	])
	for ring: Dictionary in [
		{"scale": 1.00, "color": Color(0.48, 0.69, 0.21, 0.30)},
		{"scale": 0.91, "color": Color(0.50, 0.71, 0.22, 0.48)},
		{"scale": 0.80, "color": Color(0.54, 0.73, 0.23, 0.72)},
	]:
		var ring_points := PackedVector2Array()
		for point: Vector2 in reclaimed_ground:
			ring_points.append(center + (point - center) * float(ring["scale"]))
		draw_colored_polygon(ring_points, Color(ring["color"]))
	for tuft_offset: Vector2 in [Vector2(-22, 7), Vector2(2, -9), Vector2(24, 8)]:
		draw_line(center + tuft_offset, center + tuft_offset + Vector2(2, -5), Color(0.30, 0.55, 0.16, 0.75), 1.4, true)

func _draw_terrain_overlay() -> void:
	var c := size * 0.5
	var p := PackedVector2Array([
		Vector2(c.x, 3),
		Vector2(size.x - 4, c.y),
		Vector2(c.x, size.y - 4),
		Vector2(4, c.y)
	])
	var overlay_color := Color(1.0, 1.0, 1.0, 0.08) if not is_dark_mode else Color(0.0, 0.0, 0.0, 0.22)
	if is_building_mode and building_name == "" and construction_job.is_empty() and placement_allowed:
		overlay_color = Color(0.18, 0.78, 0.48, 0.20)
	elif is_building_mode and (building_name != "" or not construction_job.is_empty()):
		overlay_color = Color(0.88, 0.22, 0.18, 0.16)
	draw_colored_polygon(p, overlay_color)
	draw_polyline(PackedVector2Array([p[0], p[1], p[2], p[3], p[0]]), Color(1.0, 1.0, 1.0, 0.24), 1.5)


func _draw_placement_indicator() -> void:
	var center := size * 0.5
	var glow := Color(0.20, 0.86, 0.52, 0.92)
	draw_circle(center, 16.0, Color(0.02, 0.12, 0.09, 0.64))
	draw_arc(center, 17.0, 0.0, TAU, 24, glow, 3.0, true)
	draw_line(center + Vector2(-7, 0), center + Vector2(7, 0), glow, 3.0, true)
	draw_line(center + Vector2(0, -7), center + Vector2(0, 7), glow, 3.0, true)


func _draw_blocked_placement_indicator() -> void:
	var center := size * 0.5
	var blocked := Color(1.0, 0.42, 0.32, 0.96)
	draw_circle(center, 16.0, Color(0.14, 0.03, 0.02, 0.72))
	draw_arc(center, 17.0, 0.0, TAU, 24, blocked, 3.0, true)
	draw_line(center + Vector2(-7, -7), center + Vector2(7, 7), blocked, 3.0, true)
	draw_line(center + Vector2(7, -7), center + Vector2(-7, 7), blocked, 3.0, true)


func _draw_construction_site() -> void:
	var center := size * 0.5
	var foundation := PackedVector2Array([
		center + Vector2(0, -24),
		center + Vector2(36, -4),
		center + Vector2(0, 18),
		center + Vector2(-36, -4),
	])
	draw_colored_polygon(foundation, Color(0.36, 0.31, 0.27, 0.92))
	draw_polyline(PackedVector2Array([foundation[0], foundation[1], foundation[2], foundation[3], foundation[0]]), Color(0.83, 0.67, 0.38), 2.0)
	var timber := Color(0.55, 0.34, 0.16)
	for x_offset in [-24.0, 0.0, 24.0]:
		draw_line(center + Vector2(x_offset, -34), center + Vector2(x_offset, 12), timber, 4.0)
	for y_offset in [-28.0, -10.0, 8.0]:
		draw_line(center + Vector2(-30, y_offset), center + Vector2(30, y_offset), timber, 3.0)
	draw_line(center + Vector2(-28, 10), center + Vector2(24, -30), Color(0.93, 0.75, 0.36), 3.0)
	var workload := maxf(1.0, float(construction_job.get("workload", 1.0)))
	var remaining := clampf(float(construction_job.get("remaining_work", workload)), 0.0, workload)
	var progress := clampf(1.0 - remaining / workload, 0.0, 1.0)
	var bar_rect := Rect2(center + Vector2(-31, 25), Vector2(62, 8))
	draw_rect(bar_rect, Color(0.03, 0.08, 0.11, 0.80))
	draw_rect(Rect2(bar_rect.position + Vector2(2, 2), Vector2((bar_rect.size.x - 4) * progress, 4)), Color(0.20, 0.82, 0.49))
	var pulse := 0.5 + 0.5 * sin(_animation_time * 4.2)
	draw_arc(center + Vector2(31, -31), 9.0 + pulse * 1.6, 0.0, TAU, 20, Color(0.98, 0.78, 0.20, 0.66 + pulse * 0.30), 2.0)
	# A small moving hoist and restrained dust puffs give every active worksite
	# visible life without obscuring its progress bar or interaction footprint.
	var hoist_angle := -0.55 + sin(_animation_time * 2.4) * 0.24
	var hoist_origin := center + Vector2(24, -26)
	var hoist_tip := hoist_origin + Vector2(cos(hoist_angle), sin(hoist_angle)) * 18.0
	draw_line(hoist_origin, hoist_tip, Color(0.96, 0.74, 0.26), 3.0, true)
	draw_line(hoist_tip, hoist_tip + Vector2(0, 8), Color(0.30, 0.24, 0.18), 1.5, true)
	for dust_index in 3:
		var dust_phase := fposmod(_animation_time * 0.65 + float(dust_index) * 0.31, 1.0)
		var dust_center := center + Vector2(-20.0 + float(dust_index) * 18.0, 13.0 - dust_phase * 10.0)
		draw_circle(dust_center, 2.0 + dust_phase * 2.2, Color(0.86, 0.72, 0.48, (1.0 - dust_phase) * 0.28))

func _draw_empty_decor() -> void:
	if tile_index in [27, 28, 35, 36]:
		_draw_fountain_plaza_part()
		return
		
	var flower := Color(1.0, 0.52, 0.60) if not is_dark_mode else Color(0.8, 0.4, 0.5)
	var leaf := Color(0.15, 0.45, 0.20)
	for i in range(3):
		var x := 24.0 + float((tile_index + i * 5) % 5) * 12.0
		var y := 24.0 + float(i) * 10.0
		draw_line(Vector2(x, y + 6), Vector2(x, y + 15), leaf, 2.0)
		draw_line(Vector2(x-2, y+10), Vector2(x+3, y+10), leaf, 1.5)
		draw_circle(Vector2(x, y + 4), 4.0, flower)
		draw_circle(Vector2(x-2, y + 2), 2.5, _lighten(flower, 0.2))
		draw_circle(Vector2(x+2, y + 2), 2.5, _lighten(flower, 0.2))
	if terrain_kind % 5 == 3:
		_draw_fairytale_tree(Vector2(size.x * 0.66, size.y * 0.35), 0.65)
	if terrain_kind % 6 != 5:
		_draw_mushroom(Vector2(size.x * 0.76, size.y * 0.58), 0.7)
		_draw_bush(Vector2(size.x * 0.22, size.y * 0.55), 0.65)

func _draw_fountain_plaza_part() -> void:
	var stone := Color(0.80, 0.76, 0.70) if not is_dark_mode else Color(0.35, 0.32, 0.30)
	var border := Color(0.60, 0.55, 0.50) if not is_dark_mode else Color(0.20, 0.18, 0.15)
	var water := Color(0.35, 0.85, 0.95, 0.85)
	
	var center_offset := Vector2.ZERO
	match tile_index:
		27: center_offset = Vector2(size.x, size.y)
		28: center_offset = Vector2(0, size.y)
		35: center_offset = Vector2(size.x, 0)
		36: center_offset = Vector2(0, 0)
		
	draw_circle(center_offset, 65.0, border)
	draw_circle(center_offset, 62.0, stone)
	draw_arc(center_offset, 45.0, 0, TAU, 32, border, 2.0)
	
	draw_circle(center_offset, 25.0, border)
	draw_circle(center_offset, 22.0, water)
	
	var pillar_pos = center_offset
	draw_rect(Rect2(pillar_pos + Vector2(-6, -15), Vector2(12, 15)), Color(0.85, 0.85, 0.85))
	draw_circle(pillar_pos + Vector2(0, -18), 8.0, Color(0.9, 0.9, 0.9))
	
	draw_arc(pillar_pos + Vector2(0, -15), 18.0, PI, TAU, 16, Color(1.0,1.0,1.0,0.8), 2.0)
	
	for i in range(12):
		var angle := TAU * float(i) / 12.0
		var d := Vector2(cos(angle), sin(angle))
		draw_line(center_offset + d * 26.0, center_offset + d * 62.0, border, 2.0)

func _draw_building_shadow() -> void:
	_draw_ellipse_poly(Rect2(Vector2(size.x * 0.15, size.y * 0.55), Vector2(size.x * 0.70, size.y * 0.25)), Color(0, 0, 0, 0.28))

func _draw_ellipse_poly(rect: Rect2, color: Color) -> void:
	var points := PackedVector2Array()
	var center := rect.position + rect.size * 0.5
	var radius := rect.size * 0.5
	for i in range(24):
		var angle := TAU * float(i) / 24.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)

func _draw_building() -> void:
	if visual_texture != null:
		_draw_storybook_building()
		return
	match building_name:
		"住宅":
			_draw_fairytale_house(Vector2(size.x * 0.50, size.y * 0.58), 1.1)
		"社會住宅":
			_draw_fairytale_house(Vector2(size.x * 0.35, size.y * 0.56), 0.85)
			_draw_fairytale_house(Vector2(size.x * 0.65, size.y * 0.62), 0.95)
		"商店":
			_draw_fairytale_shop(Vector2(size.x * 0.50, size.y * 0.58), 1.1)
		"大型商場":
			_draw_palace_store()
		"工廠":
			_draw_factory()
		"公園":
			_draw_park()
		"體育館":
			_draw_stadium()
		"學校":
			_draw_school()
		"圖書館":
			_draw_library()
		"醫院":
			_draw_hospital()
		"警局":
			_draw_station(Color(0.20, 0.40, 0.85), true)
		"消防局":
			_draw_station(Color(0.90, 0.25, 0.25), false)
		"停車場":
			_draw_parking()
		"公車站":
			_draw_bus_stop()
		"捷運站":
			_draw_metro()
		"機場":
			_draw_airport()
		"發電廠":
			_draw_power_plant()
		"核能發電廠":
			_draw_nuclear_power_plant()
		"瓦斯場":
			_draw_gas()
		"加油站":
			_draw_gas_station()
		"自來水廠":
			_draw_water()
		"游泳池":
			_draw_swimming_pool()
		"垃圾處理場":
			_draw_recycling()
		"法院":
			_draw_court()
		"監察所":
			_draw_oversight_office()
		"市政府":
			_draw_city_hall()
		_:
			_draw_fairytale_house(Vector2(size.x * 0.50, size.y * 0.54), 1.0)


func _draw_storybook_building() -> void:
	# The source image already contains internal breathing room.  Draw it larger
	# than the tile diamond and bottom-align it so tall civic buildings read well
	# without moving the interaction footprint.
	var draw_size := Vector2(size.x * 1.18, size.y * 1.18)
	var draw_pos := Vector2((size.x - draw_size.x) * 0.5, size.y * 0.82 - draw_size.y)
	var tint := Color.WHITE
	if is_dark_mode:
		tint = Color(0.68, 0.74, 0.86, 0.94)
	draw_texture_rect(visual_texture, Rect2(draw_pos, draw_size), false, tint)
	_draw_customization_badge()


func _draw_customization_badge() -> void:
	if custom_variant < 0 and custom_roof < 0 and custom_wall < 0 and custom_material.is_empty():
		return
	var accent_index := custom_variant if custom_variant >= 0 else 0
	var accent: Color = DECOR_COLORS[accent_index % DECOR_COLORS.size()]
	if custom_roof >= 0:
		accent = accent.lerp(ROOF_COLORS[custom_roof % ROOF_COLORS.size()], 0.42)
	var center := Vector2(size.x * 0.76, size.y * 0.64)
	draw_circle(center, 7.5, Color(0.98, 0.94, 0.76, 0.95))
	draw_circle(center, 5.0, accent)
	draw_arc(center, 8.0, 0.0, TAU, 18, Color(0.40, 0.28, 0.12, 0.85), 1.5)


func _draw_transport_activity_ground() -> void:
	match str(transport_activity_profile.get("id", "")):
		"parking_lot":
			_draw_parking_activity_ground()
		"bus_station", "gas_station", "road_path":
			_draw_road_activity_ground()
		"metro_station", "train_station", "rail_track":
			_draw_rail_activity_ground()
		"airport":
			_draw_runway_activity_ground()


func _draw_transport_activity_vehicles() -> void:
	var profile_id := str(transport_activity_profile.get("id", ""))
	var phase := _transport_phase()
	match profile_id:
		"parking_lot":
			_draw_car(_traffic_path_position(phase, 103.0, 88.0), 0.62, Color(0.20, 0.56, 0.82), 1.0)
			_draw_car(Vector2(size.x * 0.38, size.y * 0.72), 0.52, Color(0.91, 0.47, 0.24), -1.0)
		"bus_station":
			_draw_bus(_traffic_path_position(phase, 105.0, 86.0), 0.68, 1.0)
		"metro_station", "rail_track":
			_draw_train(_traffic_path_position(phase, 102.0, 79.0), 0.68, 1.0)
		"airport":
			var takeoff := smoothstep(0.52, 1.0, phase)
			var plane_position := _traffic_path_position(phase, 105.0, 70.0) + Vector2(0, -takeoff * 24.0)
			_draw_plane(plane_position, 0.64 + takeoff * 0.12, 1.0)
		"gas_station":
			_draw_car(_traffic_path_position(phase, 104.0, 89.0), 0.58, Color(0.22, 0.63, 0.48), 1.0)
			_draw_motorcycle(_traffic_path_position(fposmod(1.0 - phase + 0.28, 1.0), 99.0, 84.0), 0.66, -1.0)
		"road_path":
			_draw_car(_traffic_path_position(phase, 105.0, 86.0), 0.60, Color(0.28, 0.57, 0.84), 1.0)
			_draw_motorcycle(_traffic_path_position(fposmod(1.0 - phase + 0.35, 1.0), 98.0, 79.0), 0.64, -1.0)


func _draw_parking_activity_ground() -> void:
	var asphalt := Color(0.22, 0.27, 0.31, 0.72) if not is_dark_mode else Color(0.10, 0.14, 0.18, 0.82)
	var points := PackedVector2Array([
		Vector2(size.x * 0.08, size.y * 0.68),
		Vector2(size.x * 0.88, size.y * 0.55),
		Vector2(size.x * 0.96, size.y * 0.78),
		Vector2(size.x * 0.17, size.y * 0.91),
	])
	draw_colored_polygon(points, asphalt)
	for bay_index in 4:
		var x := size.x * (0.25 + float(bay_index) * 0.16)
		draw_line(Vector2(x, size.y * 0.68), Vector2(x + 8.0, size.y * 0.82), Color(0.96, 0.90, 0.67, 0.74), 1.4, true)


func _draw_road_activity_ground() -> void:
	var road := Color(0.19, 0.23, 0.27, 0.80) if not is_dark_mode else Color(0.08, 0.11, 0.15, 0.88)
	var edge := Color(0.71, 0.63, 0.47, 0.72) if not is_dark_mode else Color(0.42, 0.46, 0.49, 0.75)
	var road_points := PackedVector2Array([
		Vector2(-8, size.y * 0.70), Vector2(size.x + 8, size.y * 0.54),
		Vector2(size.x + 8, size.y * 0.79), Vector2(-8, size.y * 0.95),
	])
	draw_colored_polygon(road_points, road)
	draw_line(road_points[0], road_points[1], edge, 2.0, true)
	draw_line(road_points[3], road_points[2], edge, 2.0, true)
	for dash_index in 6:
		var start_ratio := float(dash_index) / 6.0
		var finish_ratio := minf(1.0, start_ratio + 0.085)
		var start := Vector2(-4, size.y * 0.825).lerp(Vector2(size.x + 4, size.y * 0.665), start_ratio)
		var finish := Vector2(-4, size.y * 0.825).lerp(Vector2(size.x + 4, size.y * 0.665), finish_ratio)
		draw_line(start, finish, Color(1.0, 0.91, 0.48, 0.82), 1.8, true)


func _draw_rail_activity_ground() -> void:
	var sleeper := Color(0.37, 0.24, 0.13, 0.86)
	var rail_dark := Color(0.12, 0.15, 0.18, 0.96)
	var rail_light := Color(0.72, 0.78, 0.82, 0.95)
	var path_start := Vector2(-8, size.y * 0.87)
	var path_end := Vector2(size.x + 8, size.y * 0.62)
	var normal := Vector2(0.16, 0.99).normalized()
	for sleeper_index in 10:
		var point := path_start.lerp(path_end, float(sleeper_index) / 9.0)
		draw_line(point - normal * 10.0, point + normal * 10.0, sleeper, 3.0, true)
	for rail_offset in [-6.0, 6.0]:
		draw_line(path_start + normal * rail_offset, path_end + normal * rail_offset, rail_dark, 4.0, true)
		draw_line(path_start + normal * rail_offset, path_end + normal * rail_offset, rail_light, 1.4, true)


func _draw_runway_activity_ground() -> void:
	var runway := Color(0.14, 0.18, 0.22, 0.88) if not is_dark_mode else Color(0.055, 0.075, 0.10, 0.94)
	var runway_points := PackedVector2Array([
		Vector2(-10, size.y * 0.72), Vector2(size.x + 10, size.y * 0.50),
		Vector2(size.x + 10, size.y * 0.82), Vector2(-10, size.y * 1.04),
	])
	draw_colored_polygon(runway_points, runway)
	for mark_index in 7:
		var ratio := (float(mark_index) + 0.18) / 7.0
		var point := Vector2(-6, size.y * 0.88).lerp(Vector2(size.x + 6, size.y * 0.66), ratio)
		draw_line(point - Vector2(4, -0.7), point + Vector2(4, -0.7), Color.WHITE, 2.0, true)
		var blink := 0.58 + 0.42 * sin(_animation_time * 4.0 + float(mark_index))
		draw_circle(point + Vector2(0, 15), 1.8, Color(0.98, 0.78, 0.24, blink))


func _transport_phase(offset: float = 0.0) -> float:
	var loop_seconds := maxf(0.1, float(transport_activity_profile.get("loop_seconds", 6.0)))
	return fposmod(_animation_time / loop_seconds + offset, 1.0)


func _traffic_path_position(phase: float, start_y: float, finish_y: float) -> Vector2:
	return Vector2(
		lerpf(-22.0, size.x + 22.0, phase),
		lerpf(start_y, finish_y, phase),
	)


func _draw_car(center: Vector2, scale: float, color: Color, direction: float) -> void:
	var body_size := Vector2(28, 10) * scale
	var body := Rect2(center - body_size * 0.5, body_size)
	draw_rect(body.grow(1.5 * scale), Color(0.06, 0.09, 0.11, 0.88))
	draw_rect(body, color)
	var roof_points := PackedVector2Array([
		center + Vector2(-7 * direction, -5) * scale,
		center + Vector2(-3 * direction, -10) * scale,
		center + Vector2(7 * direction, -10) * scale,
		center + Vector2(11 * direction, -5) * scale,
	])
	draw_colored_polygon(roof_points, _lighten(color, 0.18))
	draw_line(roof_points[1], roof_points[2], Color(0.67, 0.86, 0.92, 0.92), 2.2 * scale, true)
	for wheel_x in [-8.0, 8.0]:
		draw_circle(center + Vector2(wheel_x, 5) * scale, 3.2 * scale, Color(0.05, 0.06, 0.07))
		draw_circle(center + Vector2(wheel_x, 5) * scale, 1.3 * scale, Color(0.66, 0.62, 0.52))
	draw_circle(center + Vector2(14 * direction, -1) * scale, 1.8 * scale, Color(1.0, 0.88, 0.42, 0.90))


func _draw_bus(center: Vector2, scale: float, direction: float) -> void:
	var body_size := Vector2(45, 16) * scale
	var body := Rect2(center - body_size * 0.5, body_size)
	draw_rect(body.grow(1.7 * scale), Color(0.05, 0.09, 0.10, 0.90))
	draw_rect(body, Color(0.12, 0.58, 0.58))
	draw_rect(Rect2(body.position + Vector2(3, 3) * scale, Vector2(body.size.x - 6 * scale, 6 * scale)), Color(0.68, 0.88, 0.88))
	for divider in 4:
		var window_x := body.position.x + (float(divider) + 1.0) * body.size.x / 5.0
		draw_line(Vector2(window_x, body.position.y + 3 * scale), Vector2(window_x, body.position.y + 9 * scale), Color(0.18, 0.34, 0.36), 1.0, true)
	for wheel_x in [-14.0, 14.0]:
		draw_circle(center + Vector2(wheel_x, 8) * scale, 4.0 * scale, Color(0.04, 0.05, 0.06))
		draw_circle(center + Vector2(wheel_x, 8) * scale, 1.7 * scale, Color(0.72, 0.64, 0.48))
	draw_circle(center + Vector2(22 * direction, 1) * scale, 2.0 * scale, Color(1.0, 0.82, 0.28))


func _draw_train(center: Vector2, scale: float, direction: float) -> void:
	var body_size := Vector2(50, 15) * scale
	var body := Rect2(center - body_size * 0.5, body_size)
	draw_rect(body.grow(1.6 * scale), Color(0.05, 0.08, 0.12, 0.92))
	draw_rect(body, Color(0.24, 0.63, 0.86))
	draw_rect(Rect2(body.position + Vector2(3, 3) * scale, Vector2(body.size.x - 6 * scale, 5 * scale)), Color(0.76, 0.91, 0.98))
	for window_index in 5:
		var window_x := body.position.x + (float(window_index) + 0.7) * body.size.x / 5.8
		draw_rect(Rect2(Vector2(window_x, body.position.y + 3 * scale), Vector2(5, 5) * scale), Color(0.13, 0.31, 0.46))
	draw_line(body.position + Vector2(0, body.size.y - 3 * scale), body.end - Vector2(0, 3 * scale), Color(0.95, 0.70, 0.22), 2.0 * scale, true)
	for wheel_x in [-17.0, -6.0, 6.0, 17.0]:
		draw_circle(center + Vector2(wheel_x, 8) * scale, 2.5 * scale, Color(0.06, 0.07, 0.08))
	draw_circle(center + Vector2(24 * direction, 0) * scale, 2.0 * scale, Color(1.0, 0.89, 0.50))


func _draw_motorcycle(center: Vector2, scale: float, direction: float) -> void:
	var wheel_color := Color(0.04, 0.05, 0.06)
	var first_wheel := center + Vector2(-7, 4) * scale
	var second_wheel := center + Vector2(7, 4) * scale
	draw_circle(first_wheel, 3.4 * scale, wheel_color)
	draw_circle(second_wheel, 3.4 * scale, wheel_color)
	draw_line(first_wheel, center + Vector2(0, -2) * scale, Color(0.90, 0.42, 0.20), 2.2 * scale, true)
	draw_line(center + Vector2(0, -2) * scale, second_wheel, Color(0.90, 0.42, 0.20), 2.2 * scale, true)
	draw_line(center + Vector2(1, -2) * scale, center + Vector2(7 * direction, -7) * scale, Color(0.22, 0.27, 0.30), 1.8 * scale, true)
	draw_circle(center + Vector2(-1 * direction, -8) * scale, 3.0 * scale, Color(0.98, 0.77, 0.55))
	draw_circle(center + Vector2(8 * direction, -5) * scale, 1.4 * scale, Color(1.0, 0.90, 0.46))


func _draw_plane(center: Vector2, scale: float, direction: float) -> void:
	var outline := PackedVector2Array([
		center + Vector2(-20 * direction, 0) * scale,
		center + Vector2(-5 * direction, -4) * scale,
		center + Vector2(-1 * direction, -14) * scale,
		center + Vector2(4 * direction, -14) * scale,
		center + Vector2(7 * direction, -4) * scale,
		center + Vector2(20 * direction, 0) * scale,
		center + Vector2(7 * direction, 4) * scale,
		center + Vector2(2 * direction, 13) * scale,
		center + Vector2(-2 * direction, 13) * scale,
		center + Vector2(-5 * direction, 4) * scale,
	])
	draw_colored_polygon(outline, Color(0.09, 0.13, 0.17, 0.88))
	var inner := PackedVector2Array()
	for point: Vector2 in outline:
		inner.append(center + (point - center) * 0.86)
	draw_colored_polygon(inner, Color(0.88, 0.93, 0.96))
	draw_line(center + Vector2(-5 * direction, 0) * scale, center + Vector2(10 * direction, 0) * scale, Color(0.18, 0.57, 0.78), 2.0 * scale, true)
	draw_circle(center + Vector2(14 * direction, 0) * scale, 1.8 * scale, Color(1.0, 0.84, 0.38))


func _draw_ambient_animation_overlay() -> void:
	for effect_variant: Variant in ambient_animation_profile.get("effects", []):
		match str(effect_variant):
			"window_glow": _draw_ambient_window_glow()
			"chimney_smoke": _draw_ambient_smoke(0.0)
			"steam": _draw_ambient_smoke(1.7)
			"sign_sway": _draw_ambient_sign_sway()
			"machinery_light": _draw_ambient_machinery_light()
			"vegetation_sway": _draw_ambient_vegetation()
			"water_ripple": _draw_ambient_water_ripple()
			"flag_sway": _draw_ambient_flag()
			"beacon": _draw_ambient_beacon()
			"station_lights": _draw_ambient_station_lights()
			"light_glint": _draw_ambient_glint()


func _draw_ambient_window_glow() -> void:
	var pulse := 0.56 + 0.24 * sin(_animation_time * 1.5 + float(tile_index) * 0.31)
	for x_ratio in [0.42, 0.58]:
		draw_circle(Vector2(size.x * x_ratio, size.y * 0.50), 2.4, Color(1.0, 0.78, 0.30, pulse))


func _draw_ambient_smoke(offset: float) -> void:
	for puff_index in 3:
		var phase := fposmod(_animation_time * 0.18 + float(puff_index) * 0.31 + offset, 1.0)
		var center := Vector2(size.x * (0.61 + phase * 0.05), size.y * 0.16 - phase * 30.0)
		draw_circle(center, 3.0 + phase * 4.0, Color(0.82, 0.86, 0.86, (1.0 - phase) * 0.20))


func _draw_ambient_sign_sway() -> void:
	var sway := sin(_animation_time * 1.8 + float(tile_index)) * 3.0
	var anchor := Vector2(size.x * 0.70, size.y * 0.42)
	draw_line(anchor, anchor + Vector2(sway, 10), Color(0.38, 0.23, 0.12, 0.72), 1.6, true)
	draw_circle(anchor + Vector2(sway, 12), 3.2, Color(0.96, 0.65, 0.22, 0.72))


func _draw_ambient_machinery_light() -> void:
	var pulse := 0.35 + 0.65 * (0.5 + 0.5 * sin(_animation_time * 3.4 + float(tile_index)))
	draw_circle(Vector2(size.x * 0.68, size.y * 0.55), 3.0 + pulse, Color(0.28, 0.84, 0.94, 0.25 * pulse))
	draw_circle(Vector2(size.x * 0.68, size.y * 0.55), 1.8, Color(0.98, 0.76, 0.24, 0.82))


func _draw_ambient_vegetation() -> void:
	var sway := sin(_animation_time * 1.15 + float(tile_index) * 0.7) * 3.0
	var root := Vector2(size.x * 0.26, size.y * 0.70)
	draw_line(root, root + Vector2(sway, -12), Color(0.18, 0.46, 0.20, 0.78), 2.0, true)
	draw_circle(root + Vector2(sway - 3, -12), 4.2, Color(0.34, 0.68, 0.30, 0.62))
	draw_circle(root + Vector2(sway + 3, -11), 4.2, Color(0.25, 0.59, 0.27, 0.62))


func _draw_ambient_water_ripple() -> void:
	for ripple_index in 2:
		var phase := fposmod(_animation_time * 0.28 + float(ripple_index) * 0.52, 1.0)
		draw_arc(Vector2(size.x * 0.50, size.y * 0.67), 5.0 + phase * 13.0, 0.18, PI - 0.18, 18, Color(0.67, 0.91, 1.0, (1.0 - phase) * 0.38), 1.2, true)


func _draw_ambient_flag() -> void:
	var anchor := Vector2(size.x * 0.54, size.y * 0.24)
	var wave := sin(_animation_time * 2.0 + float(tile_index) * 0.4) * 2.2
	draw_line(anchor, anchor + Vector2(0, 18), Color(0.38, 0.27, 0.14, 0.78), 1.5, true)
	draw_colored_polygon(PackedVector2Array([
		anchor, anchor + Vector2(13, 3 + wave), anchor + Vector2(0, 8),
	]), Color(0.92, 0.31, 0.28, 0.68))


func _draw_ambient_beacon() -> void:
	var pulse := 0.5 + 0.5 * sin(_animation_time * 5.2)
	var center := Vector2(size.x * 0.50, size.y * 0.27)
	draw_circle(center, 3.0 + pulse * 3.0, Color(0.24, 0.62, 1.0, 0.16 + pulse * 0.18))
	draw_circle(center, 2.0, Color(0.95, 0.28, 0.24, 0.72 + pulse * 0.24))


func _draw_ambient_station_lights() -> void:
	var pulse := 0.55 + 0.28 * sin(_animation_time * 2.6)
	for x_ratio in [0.30, 0.70]:
		draw_circle(Vector2(size.x * x_ratio, size.y * 0.72), 2.2, Color(1.0, 0.82, 0.32, pulse))


func _draw_ambient_glint() -> void:
	var pulse := maxf(0.0, sin(_animation_time * 1.9 + float(tile_index) * 0.33))
	var center := Vector2(size.x * 0.72, size.y * 0.38)
	draw_line(center + Vector2(-4, 0), center + Vector2(4, 0), Color(1.0, 0.95, 0.70, pulse * 0.55), 1.2, true)
	draw_line(center + Vector2(0, -4), center + Vector2(0, 4), Color(1.0, 0.95, 0.70, pulse * 0.55), 1.2, true)

func _draw_fairytale_house(center: Vector2, scale: float) -> void:
	var wall := _wall_color()
	var roof := _roof_color()
	var timber := Color(0.35, 0.22, 0.12)
	
	var body_w := 42.0 * scale
	var body_h := 32.0 * scale
	var base_rect := Rect2(center + Vector2(-body_w/2, -body_h + 8*scale), Vector2(body_w, body_h))
	draw_rect(base_rect.grow(3.0 * scale), _darken(wall, 0.3))
	draw_rect(base_rect, wall)
	
	draw_line(center + Vector2(-body_w/2, -body_h + 8*scale), center + Vector2(body_w/2, -body_h + 8*scale), timber, 3.0 * scale)
	draw_line(center + Vector2(-body_w/2, -body_h/2 + 8*scale), center + Vector2(body_w/2, -body_h/2 + 8*scale), timber, 2.0 * scale)
	draw_line(center + Vector2(0, -body_h + 8*scale), center + Vector2(0, 8*scale), timber, 3.0 * scale)
	draw_line(center + Vector2(-body_w/4, -body_h + 8*scale), center + Vector2(-body_w/2, -body_h/2 + 8*scale), timber, 2.0 * scale)
	draw_line(center + Vector2(body_w/4, -body_h + 8*scale), center + Vector2(body_w/2, -body_h/2 + 8*scale), timber, 2.0 * scale)
	
	var roof_pts := PackedVector2Array([
		center + Vector2(-body_w/2 - 12*scale, -body_h + 10*scale),
		center + Vector2(0, -body_h - 28*scale),
		center + Vector2(body_w/2 + 12*scale, -body_h + 10*scale)
	])
	draw_colored_polygon(roof_pts, _darken(roof, 0.2))
	var roof_inner := PackedVector2Array([
		center + Vector2(-body_w/2 - 8*scale, -body_h + 8*scale),
		center + Vector2(0, -body_h - 24*scale),
		center + Vector2(body_w/2 + 8*scale, -body_h + 8*scale)
	])
	draw_colored_polygon(roof_inner, roof)
	
	for i in range(3):
		draw_line(center + Vector2(-15 + i*15, -body_h - 5)*scale, center + Vector2(0, -body_h - 20)*scale, _lighten(roof, 0.15), 1.5*scale)
	
	var chim_r := Rect2(center + Vector2(10*scale, -body_h - 25*scale), Vector2(8*scale, 16*scale))
	draw_rect(chim_r, Color(0.6, 0.3, 0.2))
	draw_rect(Rect2(chim_r.position - Vector2(1,1)*scale, Vector2(10*scale, 4*scale)), Color(0.4, 0.2, 0.1))
	
	_draw_arched_window(center + Vector2(-10, -5) * scale, scale * 1.2)
	_draw_arched_window(center + Vector2(10, -5) * scale, scale * 1.2)
	_draw_arched_window(center + Vector2(0, -18) * scale, scale * 0.9)
	
	_draw_flower_box(center + Vector2(-10, 2) * scale, scale)
	_draw_flower_box(center + Vector2(10, 2) * scale, scale)
	
	var door_r := Rect2(center + Vector2(-6*scale, 0), Vector2(12*scale, 16*scale))
	draw_rect(door_r, Color(0.4, 0.2, 0.1))
	draw_arc(center + Vector2(0, 0), 6*scale, PI, TAU, 16, Color(0.4, 0.2, 0.1), 12*scale)
	draw_circle(center + Vector2(3*scale, 8*scale), 1.5*scale, Color(0.9, 0.8, 0.2))
	
	_draw_bush(center + Vector2(-22, 10) * scale, 0.8 * scale)
	_draw_bush(center + Vector2(22, 10) * scale, 0.8 * scale)

func _draw_fairytale_shop(center: Vector2, scale: float) -> void:
	_draw_fairytale_house(center, scale)
	
	var awning_pts := PackedVector2Array([
		center + Vector2(-25*scale, 0),
		center + Vector2(-20*scale, -12*scale),
		center + Vector2(20*scale, -12*scale),
		center + Vector2(25*scale, 0)
	])
	draw_colored_polygon(awning_pts, Color(0.9, 0.3, 0.3))
	for i in range(1, 4):
		var x1 := -25*scale + (50*scale * (i/4.0))
		var x2 := -20*scale + (40*scale * (i/4.0))
		draw_line(Vector2(center.x + x1, center.y), Vector2(center.x + x2, center.y - 12*scale), Color(0.95, 0.9, 0.8), 6.0*scale)
		
	for i in range(5):
		var x := -20*scale + (i * 10*scale)
		draw_circle(center + Vector2(x, 0), 5*scale, Color(0.9, 0.3, 0.3) if i%2==0 else Color(0.95, 0.9, 0.8))

func _draw_arched_window(pos: Vector2, scale: float) -> void:
	var glow := Color(1.0, 0.9, 0.4) if is_dark_mode else Color(0.7, 0.9, 1.0)
	var frame := Color(0.3, 0.15, 0.1)
	draw_rect(Rect2(pos + Vector2(-4, 0)*scale, Vector2(8, 8)*scale), glow)
	draw_circle(pos + Vector2(0, 0)*scale, 4*scale, glow)
	draw_line(pos + Vector2(0, -4)*scale, pos + Vector2(0, 8)*scale, frame, 1.5*scale)
	draw_line(pos + Vector2(-4, 2)*scale, pos + Vector2(4, 2)*scale, frame, 1.5*scale)
	draw_arc(pos + Vector2(0, 0)*scale, 4.5*scale, PI, TAU, 12, frame, 2.0*scale)
	draw_line(pos + Vector2(-4, 8)*scale, pos + Vector2(4, 8)*scale, frame, 2.0*scale)
	draw_line(pos + Vector2(-4, 0)*scale, pos + Vector2(-4, 8)*scale, frame, 2.0*scale)
	draw_line(pos + Vector2(4, 0)*scale, pos + Vector2(4, 8)*scale, frame, 2.0*scale)

func _draw_flower_box(pos: Vector2, scale: float) -> void:
	draw_rect(Rect2(pos + Vector2(-6, 0)*scale, Vector2(12, 4)*scale), Color(0.4, 0.25, 0.15))
	draw_circle(pos + Vector2(-4, -1)*scale, 2.5*scale, Color(0.9, 0.2, 0.4))
	draw_circle(pos + Vector2(0, -2)*scale, 2.5*scale, Color(1.0, 0.6, 0.8))
	draw_circle(pos + Vector2(4, -1)*scale, 2.5*scale, Color(0.9, 0.2, 0.4))

func _draw_fairytale_tree(pos: Vector2, scale: float) -> void:
	draw_rect(Rect2(pos + Vector2(-4, 5) * scale, Vector2(8, 20) * scale), Color(0.45, 0.28, 0.18))
	var c := Color(0.25, 0.65, 0.35)
	draw_circle(pos, 18 * scale, _darken(c, 0.2))
	draw_circle(pos + Vector2(0, -3) * scale, 15 * scale, c)
	draw_circle(pos + Vector2(-10, 5) * scale, 12 * scale, c)
	draw_circle(pos + Vector2(10, 5) * scale, 12 * scale, c)
	draw_circle(pos + Vector2(-5, -8) * scale, 10 * scale, _lighten(c, 0.2))

func _draw_palace_store() -> void:
	var wall := _wall_color()
	var roof := _roof_color()
	draw_rect(Rect2(Vector2(size.x * 0.22, size.y * 0.34), Vector2(size.x * 0.56, size.y * 0.36)), wall)
	for x in [0.30, 0.44, 0.58]:
		draw_rect(Rect2(Vector2(size.x * x, size.y * 0.45), Vector2(10, size.y * 0.23)), Color(0.95, 0.88, 0.70))
	var roof_pts := PackedVector2Array([Vector2(size.x * 0.18, size.y * 0.35), Vector2(size.x * 0.50, size.y * 0.10), Vector2(size.x * 0.82, size.y * 0.35)])
	draw_colored_polygon(roof_pts, _darken(roof, 0.2))
	draw_colored_polygon(PackedVector2Array([Vector2(size.x * 0.22, size.y * 0.34), Vector2(size.x * 0.50, size.y * 0.14), Vector2(size.x * 0.78, size.y * 0.34)]), roof)
	_draw_arched_window(Vector2(size.x * 0.50, size.y * 0.48), 2.0)
	_draw_bush(Vector2(size.x * 0.25, size.y * 0.65), 1.2)
	_draw_bush(Vector2(size.x * 0.75, size.y * 0.65), 1.2)

func _draw_factory() -> void:
	var wall := Color(0.8, 0.65, 0.5)
	var roof := Color(0.6, 0.3, 0.2)
	draw_rect(Rect2(Vector2(size.x * 0.22, size.y * 0.43), Vector2(size.x * 0.58, size.y * 0.26)), wall)
	draw_colored_polygon(PackedVector2Array([
		Vector2(size.x * 0.20, size.y * 0.43),
		Vector2(size.x * 0.34, size.y * 0.25),
		Vector2(size.x * 0.48, size.y * 0.43),
		Vector2(size.x * 0.62, size.y * 0.25),
		Vector2(size.x * 0.82, size.y * 0.43)
	]), roof)
	draw_rect(Rect2(Vector2(size.x * 0.68, size.y * 0.10), Vector2(14, 38)), Color(0.4, 0.3, 0.3))
	draw_circle(Vector2(size.x * 0.75, size.y * 0.05), 8, Color(0.9, 0.9, 0.9, 0.8))
	draw_circle(Vector2(size.x * 0.80, -5), 6, Color(0.9, 0.9, 0.9, 0.5))
	for i in range(3):
		_draw_arched_window(Vector2(size.x * (0.30 + i * 0.14), size.y * 0.55), 1.2)

func _draw_park() -> void:
	_draw_fairytale_tree(Vector2(size.x * 0.30, size.y * 0.40), 1.2)
	_draw_fairytale_tree(Vector2(size.x * 0.75, size.y * 0.35), 1.0)
	draw_circle(Vector2(size.x * 0.50, size.y * 0.60), 18, Color(0.35, 0.75, 0.90))
	draw_circle(Vector2(size.x * 0.50, size.y * 0.60), 14, Color(0.9, 0.95, 1.0))
	for i in range(6):
		var angle := TAU * float(i) / 6.0
		var pos := Vector2(size.x * 0.50, size.y * 0.60) + Vector2(cos(angle), sin(angle)) * 24.0
		_draw_bush(pos, 0.6)

func _draw_stadium() -> void:
	draw_circle(Vector2(size.x * 0.50, size.y * 0.50), 32, Color(0.9, 0.3, 0.5))
	draw_circle(Vector2(size.x * 0.50, size.y * 0.50), 22, Color(0.95, 0.9, 0.7))
	draw_circle(Vector2(size.x * 0.50, size.y * 0.50), 12, Color(0.3, 0.7, 0.3))
	for i in range(8):
		var angle := TAU * float(i) / 8.0
		var pos := Vector2(size.x * 0.50, size.y * 0.50) + Vector2(cos(angle), sin(angle)) * 32.0
		draw_circle(pos, 6, Color(1.0, 0.8, 0.2))

func _draw_school() -> void:
	var wall := _wall_color()
	var roof := _roof_color()
	draw_rect(Rect2(Vector2(size.x * 0.20, size.y * 0.38), Vector2(size.x * 0.60, size.y * 0.31)), wall)
	draw_colored_polygon(PackedVector2Array([Vector2(size.x * 0.15, size.y * 0.38), Vector2(size.x * 0.50, size.y * 0.12), Vector2(size.x * 0.85, size.y * 0.38)]), roof)
	draw_rect(Rect2(Vector2(size.x * 0.42, size.y * 0.05), Vector2(size.x * 0.16, size.y * 0.40)), wall)
	draw_colored_polygon(PackedVector2Array([Vector2(size.x * 0.40, size.y * 0.05), Vector2(size.x * 0.50, -size.y * 0.10), Vector2(size.x * 0.60, size.y * 0.05)]), _darken(roof, 0.1))
	draw_circle(Vector2(size.x * 0.50, size.y * 0.25), 8, Color(1.0, 0.9, 0.3))
	draw_circle(Vector2(size.x * 0.50, size.y * 0.25), 6, Color(0.9, 0.8, 0.2))
	for i in range(3):
		_draw_arched_window(Vector2(size.x * (0.28 + i * 0.22), size.y * 0.50), 1.5)

func _draw_library() -> void:
	draw_rect(Rect2(Vector2(size.x * 0.24, size.y * 0.38), Vector2(size.x * 0.52, size.y * 0.31)), Color(0.8, 0.7, 0.9))
	draw_colored_polygon(PackedVector2Array([Vector2(size.x * 0.20, size.y * 0.38), Vector2(size.x * 0.50, size.y * 0.15), Vector2(size.x * 0.80, size.y * 0.38)]), Color(0.5, 0.3, 0.7))
	for x in [0.32, 0.45, 0.58]:
		draw_rect(Rect2(Vector2(size.x * x, size.y * 0.44), Vector2(8, size.y * 0.24)), Color(1.0, 0.9, 0.7))
	_draw_arched_window(Vector2(size.x * 0.50, size.y * 0.30), 1.5)

func _draw_hospital() -> void:
	draw_rect(Rect2(Vector2(size.x * 0.25, size.y * 0.32), Vector2(size.x * 0.50, size.y * 0.38)), Color(1.0, 0.98, 0.98))
	draw_colored_polygon(PackedVector2Array([Vector2(size.x * 0.20, size.y * 0.32), Vector2(size.x * 0.50, size.y * 0.12), Vector2(size.x * 0.80, size.y * 0.32)]), Color(0.9, 0.2, 0.3))
	draw_rect(Rect2(Vector2(size.x * 0.46, size.y * 0.41), Vector2(10, 28)), Color(0.9, 0.2, 0.3))
	draw_rect(Rect2(Vector2(size.x * 0.36, size.y * 0.50), Vector2(30, 10)), Color(0.9, 0.2, 0.3))
	_draw_bush(Vector2(size.x * 0.25, size.y * 0.65), 1.0)
	_draw_bush(Vector2(size.x * 0.75, size.y * 0.65), 1.0)

func _draw_station(color: Color, shield: bool) -> void:
	draw_rect(Rect2(Vector2(size.x * 0.25, size.y * 0.35), Vector2(size.x * 0.50, size.y * 0.34)), _lighten(color, 0.4))
	draw_colored_polygon(PackedVector2Array([Vector2(size.x * 0.20, size.y * 0.35), Vector2(size.x * 0.50, size.y * 0.10), Vector2(size.x * 0.80, size.y * 0.35)]), color)
	if shield:
		draw_colored_polygon(PackedVector2Array([Vector2(size.x * 0.50, size.y * 0.40), Vector2(size.x * 0.65, size.y * 0.48), Vector2(size.x * 0.60, size.y * 0.65), Vector2(size.x * 0.50, size.y * 0.70), Vector2(size.x * 0.40, size.y * 0.65), Vector2(size.x * 0.35, size.y * 0.48)]), Color(1.0, 0.9, 0.3))
	else:
		_draw_arched_window(Vector2(size.x * 0.50, size.y * 0.50), 2.0)
		draw_rect(Rect2(Vector2(size.x * 0.45, size.y * 0.50), Vector2(10, 25)), Color(0.4, 0.2, 0.1))

func _draw_parking() -> void:
	var asphalt := Color(0.4, 0.4, 0.45)
	draw_rect(Rect2(Vector2(size.x * 0.18, size.y * 0.28), Vector2(size.x * 0.64, size.y * 0.44)), asphalt)
	for i in range(5):
		var x := size.x * (0.22 + i * 0.12)
		draw_line(Vector2(x, size.y * 0.34), Vector2(x + 12, size.y * 0.66), Color.WHITE, 2.0)
	_draw_pictogram_p(Vector2(size.x * 0.64, size.y * 0.38))

func _draw_bus_stop() -> void:
	draw_rect(Rect2(Vector2(size.x * 0.30, size.y * 0.38), Vector2(size.x * 0.42, size.y * 0.28)), Color(0.4, 0.8, 0.75))
	draw_colored_polygon(PackedVector2Array([Vector2(size.x * 0.25, size.y * 0.38), Vector2(size.x * 0.50, size.y * 0.15), Vector2(size.x * 0.75, size.y * 0.38)]), Color(0.15, 0.6, 0.7))
	draw_line(Vector2(size.x * 0.24, size.y * 0.30), Vector2(size.x * 0.24, size.y * 0.75), Color(0.2, 0.25, 0.3), 4)
	draw_circle(Vector2(size.x * 0.24, size.y * 0.25), 10, Color(1.0, 0.9, 0.2))

func _draw_metro() -> void:
	draw_rect(Rect2(Vector2(size.x * 0.25, size.y * 0.32), Vector2(size.x * 0.50, size.y * 0.38)), Color(0.4, 0.7, 0.95))
	draw_colored_polygon(PackedVector2Array([Vector2(size.x * 0.20, size.y * 0.32), Vector2(size.x * 0.50, size.y * 0.10), Vector2(size.x * 0.80, size.y * 0.32)]), Color(0.2, 0.45, 0.85))
	for i in range(4):
		draw_line(Vector2(size.x * 0.35, size.y * (0.43 + i * 0.07)), Vector2(size.x * 0.65, size.y * (0.43 + i * 0.07)), Color(0.1, 0.2, 0.3), 3)

func _draw_airport() -> void:
	draw_rect(Rect2(Vector2(size.x * 0.18, size.y * 0.52), Vector2(size.x * 0.64, size.y * 0.15)), Color(0.3, 0.32, 0.35))
	draw_line(Vector2(size.x * 0.22, size.y * 0.595), Vector2(size.x * 0.78, size.y * 0.595), Color.WHITE, 3)
	draw_rect(Rect2(Vector2(size.x * 0.34, size.y * 0.25), Vector2(size.x * 0.32, size.y * 0.26)), Color(0.8, 0.9, 0.95))
	draw_colored_polygon(PackedVector2Array([Vector2(size.x * 0.25, size.y * 0.25), Vector2(size.x * 0.50, size.y * 0.05), Vector2(size.x * 0.75, size.y * 0.25)]), Color(0.4, 0.6, 0.8))

func _draw_power_plant() -> void:
	_draw_factory()
	var bolt := Color(1.0, 0.9, 0.2)
	draw_colored_polygon(PackedVector2Array([Vector2(size.x * 0.40, size.y * 0.15), Vector2(size.x * 0.60, size.y * 0.15), Vector2(size.x * 0.50, size.y * 0.40), Vector2(size.x * 0.65, size.y * 0.40), Vector2(size.x * 0.35, size.y * 0.75), Vector2(size.x * 0.45, size.y * 0.45), Vector2(size.x * 0.30, size.y * 0.45)]), bolt)

func _draw_nuclear_power_plant() -> void:
	_draw_power_plant()
	for x_ratio: float in [0.38, 0.50, 0.62]:
		var tower_top := Vector2(size.x * x_ratio, size.y * 0.46)
		draw_circle(tower_top, 18, Color(0.9, 0.95, 1.0, 0.95))
		draw_circle(tower_top, 11, Color(0.75, 0.82, 0.92, 0.75))
		var stem := Rect2(tower_top + Vector2(-3, 8), Vector2(6, 20))
		draw_rect(stem, Color(0.6, 0.64, 0.70))
		draw_rect(stem, Color(0.85, 0.90, 0.95), false, 1.2)
		draw_rect(Rect2(stem.position + Vector2(-7, 20), Vector2(14, 3)), Color(0.9, 0.3, 0.15))
	draw_arc(Vector2(size.x * 0.50, size.y * 0.13), 10, 0, TAU, 24, Color(1.0, 0.9, 0.18), 3.0)
	draw_circle(Vector2(size.x * 0.50, size.y * 0.13), 6, Color(1.0, 0.22, 0.2, 0.8))

func _draw_gas() -> void:
	draw_circle(Vector2(size.x * 0.35, size.y * 0.50), 22, Color(0.6, 0.45, 0.75))
	draw_circle(Vector2(size.x * 0.65, size.y * 0.52), 18, Color(0.7, 0.55, 0.85))
	draw_line(Vector2(size.x * 0.25, size.y * 0.68), Vector2(size.x * 0.75, size.y * 0.68), Color(0.4, 0.3, 0.45), 5)

func _draw_gas_station() -> void:
	draw_rect(Rect2(Vector2(size.x * 0.20, size.y * 0.42), Vector2(size.x * 0.60, size.y * 0.24)), Color(0.62, 0.62, 0.66))
	draw_rect(Rect2(Vector2(size.x * 0.16, size.y * 0.30), Vector2(size.x * 0.68, size.y * 0.18)), Color(0.90, 0.52, 0.20))
	for i in range(3):
		var x := size.x * (0.34 + i * 0.16)
		draw_rect(Rect2(Vector2(x, size.y * 0.20), Vector2(10, 30)), Color(0.12, 0.12, 0.14))
		draw_circle(Vector2(x, size.y * 0.20), 6, Color(0.2, 0.6, 0.95))
		draw_line(Vector2(x - 4, size.y * 0.20), Vector2(x + 4, size.y * 0.20), Color.WHITE, 1.6)
	draw_line(Vector2(size.x * 0.23, size.y * 0.64), Vector2(size.x * 0.77, size.y * 0.64), Color(1.0, 1.0, 1.0, 0.55), 2.8)
	draw_line(Vector2(size.x * 0.23, size.y * 0.60), Vector2(size.x * 0.77, size.y * 0.60), Color(0.3, 0.75, 0.95), 2.0)

func _draw_swimming_pool() -> void:
	var deck := Rect2(Vector2(size.x * 0.16, size.y * 0.32), Vector2(size.x * 0.68, size.y * 0.44))
	draw_rect(deck, Color(0.81, 0.79, 0.70))
	var water := Rect2(Vector2(size.x * 0.22, size.y * 0.42), Vector2(size.x * 0.56, size.y * 0.26))
	draw_rect(water, Color(0.19, 0.73, 0.93))
	for i in range(4):
		var lane_x := water.position.x + float(i + 1) * (water.size.x / 5.0)
		draw_line(Vector2(lane_x, water.position.y + 4), Vector2(lane_x, water.position.y + water.size.y - 4), Color.WHITE, 1.2)
	draw_rect(Rect2(Vector2(size.x * 0.70, size.y * 0.53), Vector2(12, 20)), Color(0.93, 0.88, 0.70))
	draw_colored_polygon(PackedVector2Array([Vector2(size.x * 0.70, size.y * 0.53), Vector2(size.x * 0.76, size.y * 0.49), Vector2(size.x * 0.78, size.y * 0.53)]), Color(0.97, 0.95, 0.83))
	draw_circle(Vector2(size.x * 0.66, size.y * 0.38), 6, Color(0.95, 0.65, 0.12))
	_draw_arched_window(Vector2(size.x * 0.30, size.y * 0.54), 0.9)
	draw_line(Vector2(size.x * 0.24, size.y * 0.58), Vector2(size.x * 0.35, size.y * 0.58), Color(1.0, 1.0, 1.0, 0.6), 1.4)

func _draw_water() -> void:
	draw_rect(Rect2(Vector2(size.x * 0.42, size.y * 0.35), Vector2(16, 30)), Color(0.4, 0.45, 0.48))
	draw_circle(Vector2(size.x * 0.50, size.y * 0.30), 25, Color(0.25, 0.7, 0.9))
	draw_rect(Rect2(Vector2(size.x * 0.25, size.y * 0.60), Vector2(size.x * 0.50, 10)), Color(0.2, 0.6, 0.8))

func _draw_recycling() -> void:
	draw_rect(Rect2(Vector2(size.x * 0.26, size.y * 0.36), Vector2(size.x * 0.48, size.y * 0.32)), Color(0.55, 0.7, 0.4))
	draw_colored_polygon(PackedVector2Array([Vector2(size.x * 0.20, size.y * 0.36), Vector2(size.x * 0.50, size.y * 0.15), Vector2(size.x * 0.80, size.y * 0.36)]), Color(0.3, 0.55, 0.25))
	draw_line(Vector2(size.x * 0.35, size.y * 0.48), Vector2(size.x * 0.50, size.y * 0.40), Color(0.9, 1.0, 0.8), 4)
	draw_line(Vector2(size.x * 0.50, size.y * 0.40), Vector2(size.x * 0.65, size.y * 0.55), Color(0.9, 1.0, 0.8), 4)
	draw_line(Vector2(size.x * 0.65, size.y * 0.55), Vector2(size.x * 0.45, size.y * 0.60), Color(0.9, 1.0, 0.8), 4)

func _draw_city_hall() -> void:
	var wall := _wall_color()
	var roof := _roof_color()
	draw_rect(Rect2(Vector2(size.x * 0.26, size.y * 0.35), Vector2(size.x * 0.48, size.y * 0.34)), wall)
	draw_rect(Rect2(Vector2(size.x * 0.15, size.y * 0.25), Vector2(size.x * 0.18, size.y * 0.44)), wall)
	draw_rect(Rect2(Vector2(size.x * 0.67, size.y * 0.25), Vector2(size.x * 0.18, size.y * 0.44)), wall)
	draw_colored_polygon(PackedVector2Array([Vector2(size.x * 0.10, size.y * 0.26), Vector2(size.x * 0.24, 0), Vector2(size.x * 0.38, size.y * 0.26)]), roof)
	draw_colored_polygon(PackedVector2Array([Vector2(size.x * 0.62, size.y * 0.26), Vector2(size.x * 0.76, 0), Vector2(size.x * 0.90, size.y * 0.26)]), roof)
	draw_colored_polygon(PackedVector2Array([Vector2(size.x * 0.30, size.y * 0.36), Vector2(size.x * 0.50, size.y * 0.10), Vector2(size.x * 0.70, size.y * 0.36)]), _darken(roof, 0.15))
	
	_draw_arched_window(Vector2(size.x * 0.24, size.y * 0.40), 1.5)
	_draw_arched_window(Vector2(size.x * 0.76, size.y * 0.40), 1.5)
	
	var door_r := Rect2(Vector2(size.x * 0.42, size.y * 0.45), Vector2(size.x * 0.16, size.y * 0.24))
	draw_rect(door_r, Color(0.4, 0.2, 0.1))
	draw_arc(Vector2(size.x * 0.50, size.y * 0.45), size.x * 0.08, PI, TAU, 16, Color(0.4, 0.2, 0.1), 16)
	
	_draw_bush(Vector2(size.x * 0.35, size.y * 0.68), 1.2)
	_draw_bush(Vector2(size.x * 0.65, size.y * 0.68), 1.2)


func _draw_court() -> void:
	var stone := _wall_color()
	var trim := _darken(building_color, 0.30)
	draw_rect(Rect2(Vector2(size.x * 0.20, size.y * 0.34), Vector2(size.x * 0.60, size.y * 0.38)), stone)
	draw_colored_polygon(PackedVector2Array([
		Vector2(size.x * 0.16, size.y * 0.35),
		Vector2(size.x * 0.50, size.y * 0.08),
		Vector2(size.x * 0.84, size.y * 0.35),
	]), trim)
	for x_ratio: float in [0.28, 0.42, 0.58, 0.72]:
		draw_rect(Rect2(Vector2(size.x * x_ratio - 3, size.y * 0.37), Vector2(6, size.y * 0.29)), Color(0.96, 0.96, 0.90))
	draw_rect(Rect2(Vector2(size.x * 0.16, size.y * 0.68), Vector2(size.x * 0.68, 7)), trim)
	var center := Vector2(size.x * 0.50, size.y * 0.24)
	draw_line(center + Vector2(0, -10), center + Vector2(0, 10), Color(0.95, 0.78, 0.20), 2)
	draw_line(center + Vector2(-13, -4), center + Vector2(13, -4), Color(0.95, 0.78, 0.20), 2)
	draw_line(center + Vector2(-10, -4), center + Vector2(-15, 6), Color(0.95, 0.78, 0.20), 2)
	draw_line(center + Vector2(10, -4), center + Vector2(15, 6), Color(0.95, 0.78, 0.20), 2)


func _draw_oversight_office() -> void:
	var wall := _wall_color()
	var roof := _roof_color()
	draw_rect(Rect2(Vector2(size.x * 0.24, size.y * 0.30), Vector2(size.x * 0.52, size.y * 0.42)), wall)
	draw_colored_polygon(PackedVector2Array([
		Vector2(size.x * 0.18, size.y * 0.31),
		Vector2(size.x * 0.50, size.y * 0.05),
		Vector2(size.x * 0.82, size.y * 0.31),
	]), roof)
	for y_ratio: float in [0.40, 0.54]:
		for x_ratio: float in [0.34, 0.50, 0.66]:
			draw_rect(Rect2(Vector2(size.x * x_ratio - 4, size.y * y_ratio), Vector2(8, 10)), Color(0.80, 0.94, 1.0))
	var eye_center := Vector2(size.x * 0.50, size.y * 0.22)
	draw_arc(eye_center, 13, 0, TAU, 24, Color(0.96, 0.90, 0.55), 3)
	draw_circle(eye_center, 4, Color(0.10, 0.28, 0.34))
	draw_rect(Rect2(Vector2(size.x * 0.44, size.y * 0.59), Vector2(size.x * 0.12, size.y * 0.13)), _darken(wall, 0.45))

func _draw_lily(pos: Vector2, scale: float) -> void:
	draw_circle(pos, 6.0 * scale, Color(0.18, 0.60, 0.28, 0.9))
	draw_line(pos, pos + Vector2(5, -5) * scale, Color(0.55, 0.90, 0.60), 1.5 * scale)
	draw_circle(pos + Vector2(6, -4) * scale, 3.0 * scale, Color(1.0, 0.75, 0.90))

func _draw_mushroom(pos: Vector2, scale: float) -> void:
	draw_rect(Rect2(pos + Vector2(-3, 2) * scale, Vector2(6, 8) * scale), Color(0.98, 0.88, 0.68))
	draw_circle(pos + Vector2(0, 0) * scale, 8.0 * scale, Color(0.90, 0.22, 0.30))
	draw_circle(pos + Vector2(-3, -2) * scale, 2.0 * scale, Color(1.0, 0.95, 0.85))
	draw_circle(pos + Vector2(4, 2) * scale, 1.8 * scale, Color(1.0, 0.95, 0.85))

func _draw_bush(pos: Vector2, scale: float) -> void:
	draw_circle(pos + Vector2(-6, 3) * scale, 9 * scale, Color(0.20, 0.60, 0.25))
	draw_circle(pos + Vector2(3, -2) * scale, 10 * scale, Color(0.25, 0.70, 0.30))
	draw_circle(pos + Vector2(10, 4) * scale, 8 * scale, Color(0.18, 0.55, 0.22))
	
	draw_circle(pos + Vector2(-4, 2)*scale, 1.5*scale, Color(1.0, 0.6, 0.8))
	draw_circle(pos + Vector2(5, 0)*scale, 1.5*scale, Color(1.0, 0.8, 0.4))

func _draw_pictogram_p(pos: Vector2) -> void:
	var white := Color.WHITE
	draw_line(pos, pos + Vector2(0, 26), white, 4)
	draw_line(pos, pos + Vector2(16, 0), white, 4)
	draw_line(pos + Vector2(16, 0), pos + Vector2(16, 12), white, 4)
	draw_line(pos + Vector2(0, 12), pos + Vector2(16, 12), white, 4)

func _draw_selection() -> void:
	var c := size * 0.5
	var p := PackedVector2Array([
		Vector2(c.x, 2),
		Vector2(size.x - 2, c.y),
		Vector2(c.x, size.y - 2),
		Vector2(2, c.y),
		Vector2(c.x, 2)
	])
	var color := Color(1.0, 0.88, 0.20) if selected else Color(1.0, 1.0, 1.0, 0.85)
	draw_polyline(p, color, 4.0)

func _roof_color() -> Color:
	if custom_roof >= 0:
		return ROOF_COLORS[custom_roof % ROOF_COLORS.size()]
	return _darken(building_color, 0.15)

func _wall_color() -> Color:
	var base_color: Color
	if custom_wall >= 0:
		base_color = WALL_COLORS[custom_wall % WALL_COLORS.size()]
	else:
		base_color = _lighten(building_color, 0.4)
	return _material_tint(base_color, custom_material)


func _material_tint(base_color: Color, material_id: String) -> Color:
	var tint := base_color
	var amount := 0.0
	match material_id:
		"wood":
			tint = Color(0.72, 0.48, 0.27)
			amount = 0.28
		"brick":
			tint = Color(0.72, 0.32, 0.22)
			amount = 0.38
		"steel":
			tint = Color(0.43, 0.58, 0.68)
			amount = 0.42
		"concrete":
			tint = Color(0.58, 0.60, 0.62)
			amount = 0.36
		"eco_composite":
			tint = Color(0.34, 0.64, 0.43)
			amount = 0.32
	return base_color.lerp(tint, amount)


func _material_label(material_id: String) -> String:
	match material_id:
		"wood": return "木造"
		"brick": return "磚造"
		"steel": return "鋼構"
		"concrete": return "混凝土"
		"eco_composite": return "環保複材"
		_: return ""

func _lighten(color: Color, amount: float) -> Color:
	return Color(lerpf(color.r, 1.0, amount), lerpf(color.g, 1.0, amount), lerpf(color.b, 1.0, amount), color.a)

func _darken(color: Color, amount: float) -> Color:
	return Color(lerpf(color.r, 0.0, amount), lerpf(color.g, 0.0, amount), lerpf(color.b, 0.0, amount), color.a)
