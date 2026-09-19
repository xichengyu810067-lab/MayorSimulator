extends SceneTree

const UiIconCatalog = preload("res://ui/theme/ui_icon_catalog.gd")

const REQUIRED_KEYS: PackedStringArray = [
	"time", "month", "next_day", "next_month", "funds", "treasury", "population", "capacity", "satisfaction",
	"wellbeing", "security", "environment", "traffic", "education", "healthcare", "grievance", "complaint", "trust", "score", "rating", "city_level", "city_hall",
	"municipal", "settings", "theme", "exit", "buildings", "governance", "judicial", "oversight",
	"justice", "blueprint", "finance", "public_affairs", "city_data", "report", "building_housing",
	"building_economy", "building_community", "building_mobility", "building_utilities", "building_civic",
	"customize", "style", "roof", "exterior", "maintenance", "demolish", "material", "size",
	"floors", "workers", "decoration", "new", "continue",
]

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(UiIconCatalog.VERSION == "storybook_v2", "unexpected active icon-set version")
	_check(UiIconCatalog.CANONICAL_FILENAMES.size() == 37, "canonical delivery must contain 36 functional icons plus one fallback")
	_check(REQUIRED_KEYS.size() == UiIconCatalog.KEY_TO_FILENAME.size(), "contract key list must cover the complete semantic catalog")
	for catalog_key in UiIconCatalog.KEY_TO_FILENAME.keys():
		_check(str(catalog_key) in REQUIRED_KEYS, "semantic catalog key is absent from the contract: %s" % catalog_key)
	var unique_files: Dictionary = {}
	for filename in UiIconCatalog.CANONICAL_FILENAMES:
		unique_files[str(filename)] = true
	_check(unique_files.size() == UiIconCatalog.CANONICAL_FILENAMES.size(), "canonical filenames contain duplicates")

	for key in REQUIRED_KEYS:
		_check(UiIconCatalog.has_key(key), "required semantic key is missing: %s" % key)
		var key_path := UiIconCatalog.path_for(key)
		_check(key_path.begins_with(UiIconCatalog.ROOT_PATH + "/"), "key escapes active icon root: %s" % key)
	_check(UiIconCatalog.path_for("security").ends_with("/building_civic.png"), "security must keep its dedicated civic-service symbol")
	_check(UiIconCatalog.path_for("traffic").ends_with("/building_mobility.png"), "traffic must keep its dedicated mobility symbol")
	_check(UiIconCatalog.path_for("environment").ends_with("/environment.png"), "environment must not borrow the community icon")
	_check(UiIconCatalog.path_for("education").ends_with("/education.png"), "education must not borrow the community icon")
	_check(UiIconCatalog.path_for("healthcare").ends_with("/healthcare.png"), "healthcare must not borrow the generic wellbeing icon")
	_check(UiIconCatalog.path_for("capacity").ends_with("/building_housing.png"), "housing capacity reuses the canonical housing symbol")

	for filename in UiIconCatalog.CANONICAL_FILENAMES:
		_validate_icon(str(filename))

	var unknown_path := UiIconCatalog.path_for("__deliberately_unknown_icon__")
	_check(unknown_path.ends_with("/%s" % UiIconCatalog.FALLBACK_FILENAME), "unknown key does not resolve to the neutral fallback")

	if _failed:
		quit(1)
	else:
		print("UI icon catalog contract test passed. Files=%d Keys=%d" % [
			UiIconCatalog.CANONICAL_FILENAMES.size(),
			REQUIRED_KEYS.size(),
		])
		quit(0)


func _validate_icon(filename: String) -> void:
	var resource_path := "%s/%s" % [UiIconCatalog.ROOT_PATH, filename]
	_check(ResourceLoader.exists(resource_path), "icon resource is missing: %s" % resource_path)
	var texture := load(resource_path) as Texture2D
	_check(texture != null, "icon cannot load as Texture2D: %s" % resource_path)
	if texture == null:
		return
	_check(texture.get_width() == 256 and texture.get_height() == 256, "icon is not a 256x256 master: %s" % filename)

	var disk_path := ProjectSettings.globalize_path(resource_path)
	var image := Image.load_from_file(disk_path)
	_check(image != null and not image.is_empty(), "icon source PNG cannot be inspected: %s" % filename)
	if image == null or image.is_empty():
		return
	_check(image.get_width() == 256 and image.get_height() == 256, "source PNG geometry is not 256x256: %s" % filename)
	_check(not _touches_edge(image), "visible pixels touch the delivery edge: %s" % filename)
	var bounds := _visible_bounds(image)
	_check(bounds.size.x > 0 and bounds.size.y > 0, "icon has no visible content: %s" % filename)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return
	var center := bounds.position + bounds.size * 0.5
	_check(center.distance_to(Vector2(128, 128)) <= 10.5, "optical bounds are off-center by more than 4%%: %s" % filename)
	var coverage := float(bounds.size.x * bounds.size.y) / float(256 * 256)
	_check(coverage >= 0.26 and coverage <= 0.84, "visible bounding coverage is outside the approved range: %s %.3f" % [filename, coverage])
	_check(_visible_magenta_pixels(image) == 0, "visible chroma-key fringe remains: %s" % filename)


func _touches_edge(image: Image) -> bool:
	for x in image.get_width():
		if image.get_pixel(x, 0).a > 0.03 or image.get_pixel(x, image.get_height() - 1).a > 0.03:
			return true
	for y in image.get_height():
		if image.get_pixel(0, y).a > 0.03 or image.get_pixel(image.get_width() - 1, y).a > 0.03:
			return true
	return false


func _visible_bounds(image: Image) -> Rect2:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a <= 0.03:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Rect2()
	return Rect2(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


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
	push_error("UI icon catalog contract failed: %s" % message)
