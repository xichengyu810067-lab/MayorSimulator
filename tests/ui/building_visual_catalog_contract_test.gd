extends SceneTree

const Buildings = preload("res://data/catalogs/buildings.gd")
const BuildingVisuals = preload("res://data/catalogs/building_visuals.gd")
const ContentRegistry = preload("res://data/catalogs/content_registry.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var buildings := Buildings.all()
	_check(not buildings.is_empty(), "buildable catalog must not be empty")
	_check(BuildingVisuals.BY_DISPLAY_NAME.size() == buildings.size(), "visual catalog must cover every buildable entry")
	_check(ContentRegistry.BUILDING_IDS.size() == buildings.size(), "content registry must cover every buildable entry")
	var unique_ids: Dictionary = {}
	var unique_paths: Dictionary = {}
	for building_name in buildings.keys():
		var definition := BuildingVisuals.definition(str(building_name))
		_check(not definition.is_empty(), "missing visual definition: %s" % building_name)
		var asset_id := str(definition.get("id", ""))
		var asset_path := str(definition.get("asset", ""))
		_check(not asset_id.is_empty(), "missing visual id: %s" % building_name)
		_check(ContentRegistry.BUILDING_IDS.has(building_name), "missing content-registry id: %s" % building_name)
		_check(asset_id == ContentRegistry.building_id_for_name(str(building_name)), "visual and content-registry ids differ for %s" % building_name)
		_check(not unique_ids.has(asset_id), "visual id is shared: %s" % asset_id)
		_check(not unique_paths.has(asset_path), "building image is shared: %s" % asset_path)
		unique_ids[asset_id] = true
		unique_paths[asset_path] = true
		_validate_asset(str(building_name), asset_path)
	for visual_name in BuildingVisuals.BY_DISPLAY_NAME.keys():
		_check(buildings.has(visual_name), "orphan visual definition: %s" % visual_name)
	for registry_name in ContentRegistry.BUILDING_IDS.keys():
		_check(buildings.has(registry_name), "orphan content-registry id: %s" % registry_name)

	if _failed:
		quit(1)
	else:
		print("Building visual catalog contract test passed. Buildings=%d UniqueAssets=%d" % [
			buildings.size(),
			unique_paths.size(),
		])
		quit(0)


func _validate_asset(building_name: String, asset_path: String) -> void:
	_check(ResourceLoader.exists(asset_path), "asset is missing for %s: %s" % [building_name, asset_path])
	var texture := load(asset_path) as Texture2D
	_check(texture != null, "asset cannot load for %s" % building_name)
	if texture == null:
		return
	_check(texture.get_width() == 256 and texture.get_height() == 256, "asset must be 256x256: %s" % building_name)
	var image := Image.load_from_file(ProjectSettings.globalize_path(asset_path))
	_check(image != null and not image.is_empty(), "source PNG cannot be read: %s" % building_name)
	if image == null or image.is_empty():
		return
	_check(not _touches_edge(image), "visible pixels touch delivery edge: %s" % building_name)
	_check(_visible_magenta_pixels(image) == 0, "chroma-key fringe remains: %s" % building_name)


func _touches_edge(image: Image) -> bool:
	for x in image.get_width():
		if image.get_pixel(x, 0).a > 0.03 or image.get_pixel(x, image.get_height() - 1).a > 0.03:
			return true
	for y in image.get_height():
		if image.get_pixel(0, y).a > 0.03 or image.get_pixel(image.get_width() - 1, y).a > 0.03:
			return true
	return false


func _visible_magenta_pixels(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.08 and pixel.r > 0.86 and pixel.b > 0.86 and pixel.g < 0.30:
				count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Building visual catalog contract failed: %s" % message)
