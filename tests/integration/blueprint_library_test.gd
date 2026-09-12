extends SceneTree

const Buildings = preload("res://data/catalogs/buildings.gd")

const COORDINATOR_PATH := "res://scripts/app/vertical_slice_coordinator.gd"
const SAVE_PATH := "user://mayor_simulator/blueprint_library_test.json"
const CITY_CONTEXT := {
	"population": 300,
	"security": 70,
	"environment": 70,
	"traffic": 70,
	"education": 70,
	"healthcare": 70,
}

var _failed := false


func _initialize() -> void:
	var coordinator_script := ResourceLoader.load(COORDINATOR_PATH, "Script", ResourceLoader.CACHE_MODE_IGNORE) as Script
	_check(coordinator_script != null and coordinator_script.can_instantiate(), "coordinator compiles")
	if coordinator_script == null or not coordinator_script.can_instantiate():
		quit(1)
		return
	var coordinator = coordinator_script.new(20_260_731, 2_000_000)
	_check(coordinator.blueprint_library.size() == Buildings.all().size(), "new game seeds one starter blueprint per building")
	for building_name in Buildings.all().keys():
		_check(coordinator.has_approved_blueprint(str(building_name)), "starter blueprint missing: %s" % building_name)
		_check(coordinator.approved_blueprints(str(building_name)).size() == 1, "starter library must begin with exactly one version: %s" % building_name)

	var first_anchor: int = _find_legal_park_anchor(coordinator, [])
	_check(first_anchor >= 0, "starter park fixture finds a legal complete footprint")
	if first_anchor < 0:
		quit(1)
		return
	var first_quote: Dictionary = coordinator.placement_footprint_quote("公園", first_anchor, 5)
	_check(bool(first_quote.get("ok", false)) and Array(first_quote.get("occupied_tile_ids", [])).size() == 1, "starter park fixture quote is a legal complete footprint")
	var first: Dictionary = coordinator.start_approved_building("公園", first_anchor, 5)
	_check(bool(first.get("ok", false)), "starter park blueprint starts without an introductory review burden")
	if bool(first.get("ok", false)):
		coordinator.advance_days(int(first.get("job", {}).get("projected_remaining_days", 0)), CITY_CONTEXT, false)
	var second_anchor: int = _find_legal_park_anchor(coordinator, Array(first_quote.get("occupied_tile_ids", [])))
	_check(second_anchor >= 0 and second_anchor != first_anchor, "reused park fixture finds a distinct legal complete footprint")
	if second_anchor < 0:
		quit(1)
		return
	var second_quote: Dictionary = coordinator.placement_footprint_quote("公園", second_anchor, 5)
	_check(bool(second_quote.get("ok", false)) and Array(second_quote.get("occupied_tile_ids", [])).size() == 1, "reused park fixture quote is a legal complete footprint")
	var second: Dictionary = coordinator.start_approved_building("公園", second_anchor, 5)
	_check(bool(second.get("ok", false)), "same starter park blueprint can be reused")
	_check(int(coordinator.active_blueprint_status("公園").get("usage_count", 0)) == 2, "library entry tracks both construction uses")

	var submitted: Dictionary = coordinator.submit_blueprint({
		"building_name": "公園",
		"material_id": "eco_composite",
		"floors": 1,
		"size_tier": "medium",
		"decor_id": "flags",
		"workers": 6,
	})
	_check(bool(submitted.get("ok", false)), "player can submit a custom version while starter remains available")
	if bool(submitted.get("ok", false)):
		coordinator.advance_days(int(submitted.get("review", {}).get("review_days", 0)), CITY_CONTEXT, false)
	_check(coordinator.approved_blueprints("公園").size() == 2, "approved custom version is appended without replacing starter")
	var active: Dictionary = coordinator.active_blueprint_status("公園")
	_check(str(active.get("source", "")) == "player", "newly approved custom version becomes active")
	_check(str(active.get("blueprint", {}).get("material_id", "")) == "eco_composite", "active custom blueprint retains approved parameters")
	var selected_default: Dictionary = coordinator.select_approved_blueprint("公園", "default_park")
	_check(bool(selected_default.get("ok", false)), "player can explicitly select the starter blueprint after approving a custom version")
	_check(str(coordinator.active_blueprint_status("公園").get("library_id", "")) == "default_park", "explicit starter selection becomes active before save")

	_check(coordinator.save_game(SAVE_PATH) == OK, "blueprint library saves")
	var restored = coordinator_script.new(1, 1)
	_check(restored.load_game(SAVE_PATH), "blueprint library loads")
	_check(restored.blueprint_library.size() == coordinator.blueprint_library.size(), "save round trip retains the complete blueprint library")
	_check(str(restored.active_blueprint_status("公園").get("library_id", "")) == "default_park", "historical review replay does not overwrite the player's persisted active blueprint selection")
	_check(restored.approved_blueprints("公園").size() == 2, "save round trip retains every approved park version")
	var restored_anchor: int = _find_legal_park_anchor(restored, [])
	_check(restored_anchor >= 0, "restored park fixture finds a legal complete footprint")
	if restored_anchor < 0:
		quit(1)
		return
	var restored_quote: Dictionary = restored.placement_footprint_quote("公園", restored_anchor, 5)
	_check(bool(restored_quote.get("ok", false)) and Array(restored_quote.get("occupied_tile_ids", [])).size() == 1, "restored park fixture quote is a legal complete footprint")
	var restored_build: Dictionary = restored.start_approved_building("公園", restored_anchor, 5)
	_check(bool(restored_build.get("ok", false)), "restored active starter blueprint can start a new construction job")
	_check(str(restored_build.get("blueprint_library_id", "")) == "default_park", "construction after restore uses the player's persisted active blueprint")
	_check(str(restored_build.get("job", {}).get("metadata", {}).get("blueprint_library_id", "")) == "default_park", "restored construction job records the persisted blueprint library ID")

	if _failed:
		quit(1)
	else:
		print("Blueprint library test passed. Starter=%d ParkVersions=%d" % [
			Buildings.all().size(),
			restored.approved_blueprints("公園").size(),
		])
		quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Blueprint library test failed: %s" % message)


func _find_legal_park_anchor(coordinator, excluded_tiles: Array) -> int:
	for tile_id: int in coordinator.terrain_map.tile_ids_in_display_order():
		var quote: Dictionary = coordinator.placement_footprint_quote("公園", tile_id, 5)
		var occupied_tiles: Array = quote.get("occupied_tile_ids", [])
		if (
			not bool(quote.get("ok", false))
			or str(quote.get("status", "")) != "approved"
			or occupied_tiles.size() != 1
		):
			continue
		var overlaps_excluded := false
		for occupied_tile: Variant in occupied_tiles:
			if excluded_tiles.has(int(occupied_tile)):
				overlaps_excluded = true
				break
		if not overlaps_excluded:
			return tile_id
	return -1
