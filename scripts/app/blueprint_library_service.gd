class_name BlueprintLibraryService
extends RefCounted

## Blueprint catalog state and deterministic data transformations.
##
## Construction commands, ledger posts, events, and save orchestration remain
## in VerticalSliceCoordinator. This service only manages blueprint IDs,
## library records, active selections, defaults, usage counters, and compatible
## snapshot data.

var next_blueprint_sequence := 1
var blueprint_library: Dictionary = {}
var active_blueprint_by_building: Dictionary = {}


func reset(building_definitions: Dictionary) -> void:
	next_blueprint_sequence = 1
	blueprint_library = {}
	active_blueprint_by_building = {}
	seed_default_blueprints(building_definitions)


func restore(
	p_next_blueprint_sequence: int,
	p_blueprint_library: Dictionary,
	p_active_blueprint_by_building: Dictionary,
	building_definitions: Dictionary
) -> void:
	next_blueprint_sequence = maxi(1, p_next_blueprint_sequence)
	blueprint_library = p_blueprint_library.duplicate(true)
	active_blueprint_by_building = p_active_blueprint_by_building.duplicate(true)
	seed_default_blueprints(building_definitions)


func snapshot() -> Dictionary:
	return {
		"next_blueprint_sequence": next_blueprint_sequence,
		"blueprint_library": blueprint_library.duplicate(true),
		"active_blueprint_by_building": active_blueprint_by_building.duplicate(true),
	}


func create_submission_blueprint(payload: Dictionary, definition) -> Dictionary:
	var blueprint_id := "blueprint_%06d" % next_blueprint_sequence
	next_blueprint_sequence += 1
	return {
		"id": blueprint_id,
		"version": 1,
		"building_id": String(definition.id),
		"material_id": str(payload.get("material_id", definition.default_material_id)),
		"floors": maxi(1, int(payload.get("floors", 1))),
		"size_tier": str(payload.get("size_tier", "medium")),
		"roof_color": str(payload.get("roof_color", "blue")),
		"wall_color": str(payload.get("wall_color", "cream")),
		"decoration_id": str(payload.get("decor_id", payload.get("decoration_id", "flowers"))),
		"decoration_count": 1,
		"requested_workers": clampi(int(payload.get("workers", 5)), 1, 20),
		"base_cost": definition.base_cost,
	}


func approved_blueprints(building_id: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for entry_variant: Variant in blueprint_library.values():
		if not entry_variant is Dictionary:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("building_id", "")) == building_id:
			entries.append(entry.duplicate(true))
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if str(a.get("source", "")) != str(b.get("source", "")):
			return str(a.get("source", "")) == "default"
		return int(a.get("approved_sequence", 0)) < int(b.get("approved_sequence", 0))
	)
	return entries


func active_blueprint_status(
	building_id: String,
	display_name: String,
	allow_active_selection_update: bool = true
) -> Dictionary:
	var library_id := str(active_blueprint_by_building.get(building_id, ""))
	if library_id.is_empty() or not blueprint_library.has(library_id):
		var entries := approved_blueprints(building_id)
		if entries.is_empty():
			return {"exists": false, "status": "none"}
		library_id = str(entries[0].get("id", ""))
		if allow_active_selection_update:
			active_blueprint_by_building[building_id] = library_id
	var entry: Dictionary = blueprint_library[library_id]
	return {
		"exists": true,
		"status": "approved",
		"id": library_id,
		"library_id": library_id,
		"sequence": int(entry.get("approved_sequence", 0)),
		"building_name": display_name,
		"blueprint": Dictionary(entry.get("blueprint", {})).duplicate(true),
		"source": str(entry.get("source", "default")),
		"title": str(entry.get("title", "核准藍圖")),
		"usage_count": int(entry.get("usage_count", 0)),
		"approved_day": int(entry.get("approved_day", 0)),
		"remaining_days": 0,
		"remaining_real_minutes": 0,
	}


func select_approved_blueprint(building_id: String, library_id: String) -> Dictionary:
	if not blueprint_library.has(library_id):
		return {"ok": false, "error": "blueprint_not_found"}
	var entry: Dictionary = blueprint_library[library_id]
	if str(entry.get("building_id", "")) != building_id:
		return {"ok": false, "error": "blueprint_building_mismatch"}
	active_blueprint_by_building[building_id] = library_id
	return {"ok": true, "entry": entry.duplicate(true)}


func has_entry(library_id: String) -> bool:
	return blueprint_library.has(library_id)


func entry(library_id: String) -> Dictionary:
	if not blueprint_library.has(library_id):
		return {}
	return Dictionary(blueprint_library[library_id]).duplicate(true)


func record_usage(library_id: String, used_day: int) -> bool:
	if not blueprint_library.has(library_id):
		return false
	var library_entry: Dictionary = blueprint_library[library_id]
	library_entry["usage_count"] = int(library_entry.get("usage_count", 0)) + 1
	library_entry["last_used_day"] = used_day
	blueprint_library[library_id] = library_entry
	return true


func archive_approved_blueprint(
	review: Dictionary,
	building_definitions: Dictionary,
	fallback_game_day: int
) -> String:
	var blueprint: Dictionary = Dictionary(review.get("blueprint", {})).duplicate(true)
	var building_id := str(blueprint.get("building_id", ""))
	if building_id.is_empty():
		return ""
	var blueprint_id := str(blueprint.get("id", "blueprint_%06d" % int(review.get("sequence", 0))))
	var library_id := "approved_%s" % blueprint_id
	if blueprint_library.has(library_id):
		active_blueprint_by_building[building_id] = library_id
		return library_id
	var custom_count := 0
	for entry_variant: Variant in blueprint_library.values():
		if not entry_variant is Dictionary:
			continue
		var library_entry: Dictionary = entry_variant
		if str(library_entry.get("building_id", "")) == building_id and str(library_entry.get("source", "")) == "player":
			custom_count += 1
	var definition = building_definitions.get(building_id)
	var display_name := str(definition.display_name) if definition != null else building_id
	blueprint_library[library_id] = {
		"id": library_id,
		"building_id": building_id,
		"building_name": display_name,
		"title": "自訂核准版 %d" % (custom_count + 1),
		"source": "player",
		"status": "approved",
		"approved_day": int(review.get("resolved_day", fallback_game_day)),
		"approved_sequence": int(review.get("sequence", 0)),
		"review_id": str(review.get("id", "")),
		"usage_count": 0,
		"blueprint": blueprint,
	}
	active_blueprint_by_building[building_id] = library_id
	return library_id


func seed_default_blueprints(building_definitions: Dictionary) -> void:
	for building_id in _sorted_keys(building_definitions):
		var definition = building_definitions[building_id]
		var library_id := "default_%s" % str(building_id)
		if blueprint_library.has(library_id):
			if not active_blueprint_by_building.has(str(building_id)):
				active_blueprint_by_building[str(building_id)] = library_id
			continue
		blueprint_library[library_id] = {
			"id": library_id,
			"building_id": str(building_id),
			"building_name": str(definition.display_name),
			"title": "官方入門版",
			"source": "default",
			"status": "approved",
			"approved_day": 0,
			"approved_sequence": 0,
			"usage_count": 0,
			"blueprint": _default_blueprint_for_definition(definition),
		}
		active_blueprint_by_building[str(building_id)] = library_id


static func _default_blueprint_for_definition(definition) -> Dictionary:
	var building_id := String(definition.id)
	var large_ids := ["mall", "stadium", "airport", "power_plant", "nuclear_power_plant", "gas_works", "water_works", "waste_center"]
	var small_ids := ["residence", "shop", "park", "parking_lot", "bus_station", "metro_station", "gas_station", "swimming_pool"]
	var two_floor_ids := ["residence", "mall", "factory", "school", "library", "hospital", "police_station", "fire_station", "train_station", "airport", "court", "oversight_office", "city_hall"]
	var three_floor_ids := ["social_housing"]
	var decoration_id := "flowers"
	if building_id in ["court", "oversight_office", "city_hall", "school", "police_station", "fire_station"]:
		decoration_id = "flags"
	elif building_id in ["factory", "power_plant", "nuclear_power_plant", "gas_works", "water_works", "waste_center"]:
		decoration_id = "window_trim"
	return {
		"id": "blueprint_default_%s" % building_id,
		"version": 1,
		"building_id": building_id,
		"material_id": String(definition.default_material_id),
		"floors": 3 if building_id in three_floor_ids else (2 if building_id in two_floor_ids else 1),
		"size_tier": "large" if building_id in large_ids else ("small" if building_id in small_ids else "medium"),
		"roof_color": "blue",
		"wall_color": "cream",
		"decoration_id": decoration_id,
		"decoration_count": 1,
		"requested_workers": 5,
		"base_cost": int(definition.base_cost),
	}


static func _sorted_keys(source: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in source.keys():
		result.append(str(key))
	result.sort()
	return result
