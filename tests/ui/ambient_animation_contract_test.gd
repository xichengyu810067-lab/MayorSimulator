extends SceneTree

const Buildings = preload("res://data/catalogs/buildings.gd")

const SUPPORTED_EFFECTS := [
	"window_glow",
	"chimney_smoke",
	"steam",
	"sign_sway",
	"machinery_light",
	"vegetation_sway",
	"water_ripple",
	"flag_sway",
	"beacon",
	"station_lights",
	"light_glint",
]

var _failed := false
var _checks := 0
var _city_tile_button_script: Script


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_city_tile_button_script = load("res://scripts/world/city_tile_button.gd") as Script
	_check(_city_tile_button_script != null, "city tile renderer could not be loaded")
	if _city_tile_button_script == null:
		quit(1)
		return
	var buildings := Buildings.all()
	_check(not buildings.is_empty(), "ambient animation contract requires a non-empty live building catalog")
	for building_name_variant: Variant in buildings.keys():
		_validate_completed_building(str(building_name_variant), buildings[building_name_variant])
		_validate_construction_animation(str(building_name_variant), buildings[building_name_variant])

	if _failed:
		quit(1)
	else:
		print("Ambient animation contract test passed. Buildings=%d Completed=%d Construction=%d Checks=%d" % [
			buildings.size(),
			buildings.size(),
			buildings.size(),
			_checks,
		])
		quit(0)


func _validate_completed_building(building_name: String, definition: Dictionary) -> void:
	var tile = _create_tile(building_name, definition, {})
	var ambient: Dictionary = tile.get_ambient_animation_profile()
	_check(not ambient.is_empty(), "building has no ambient animation profile: %s" % building_name)
	_check(not str(ambient.get("id", "")).is_empty(), "building ambient profile has no stable id: %s" % building_name)
	_check(float(ambient.get("loop_seconds", 0.0)) > 0.0, "building ambient loop duration must be positive: %s" % building_name)
	var effects: Array = Array(ambient.get("effects", []))
	_check(not effects.is_empty(), "building ambient profile has no rendered effects: %s" % building_name)
	for effect_variant: Variant in effects:
		var effect := str(effect_variant)
		_check(SUPPORTED_EFFECTS.has(effect), "building references an unsupported ambient draw effect: %s -> %s" % [building_name, effect])

	tile.debug_set_animation_time(0.15)
	var before: Dictionary = tile.get_visual_animation_debug_snapshot()
	tile.debug_advance_animation(0.61)
	var after: Dictionary = tile.get_visual_animation_debug_snapshot()
	_check(bool(before.get("animation_active", false)), "completed building animation is inactive: %s" % building_name)
	_check(str(before.get("ambient_profile_id", "")) == str(ambient.get("id", "")), "debug snapshot lost the ambient profile id: %s" % building_name)
	_check(str(after.get("animation_signature", "")) != str(before.get("animation_signature", "")), "completed building snapshot did not change with time: %s" % building_name)
	tile.free()


func _validate_construction_animation(building_name: String, definition: Dictionary) -> void:
	var construction := {
		"metadata": {"building_name": building_name},
		"workload": 12.0,
		"remaining_work": 7.0,
		"projected_remaining_days": 2,
	}
	var tile = _create_tile(building_name, definition, construction)
	var contract: Dictionary = tile.get_visual_animation_contract()
	_check(bool(contract.get("construction_animation_supported", false)), "tile contract does not declare construction animation support: %s" % building_name)
	_check(bool(contract.get("construction_replaces_portrait_until_complete", false)), "construction animation layering is not explicit: %s" % building_name)

	tile.debug_set_animation_time(0.20)
	var before: Dictionary = tile.get_visual_animation_debug_snapshot()
	tile.debug_advance_animation(0.67)
	var after: Dictionary = tile.get_visual_animation_debug_snapshot()
	_check(bool(before.get("construction_active", false)), "construction state is not active for %s" % building_name)
	_check(bool(before.get("animation_active", false)), "construction animation is not active for %s" % building_name)
	_check(str(before.get("animation_signature", "")).contains("construction_site"), "construction snapshot lacks its stable animation signature: %s" % building_name)
	_check(str(after.get("animation_signature", "")) != str(before.get("animation_signature", "")), "construction snapshot did not change with time: %s" % building_name)
	tile.free()


func _create_tile(building_name: String, definition: Dictionary, construction: Dictionary):
	var tile = _city_tile_button_script.new()
	tile.size = Vector2(128, 128)
	root.add_child(tile)
	tile.set_tile({
		"index": 11,
		"building_name": building_name,
		"building_color": definition.get("color", Color.WHITE),
		"terrain_type": "flat_ground",
		"visual": {},
		"construction": construction,
	})
	return tile


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Ambient animation contract failed: %s" % message)
