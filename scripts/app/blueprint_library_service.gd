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

const MATERIAL_COST_MULTIPLIERS := {
	"wood": 0.85,
	"brick": 1.0,
	"steel": 1.30,
	"eco_composite": 1.15,
}
const SIZE_COST_MULTIPLIERS := {"small": 0.75, "medium": 1.0, "large": 1.50}
const DECORATION_COST_MULTIPLIERS := {"flowers": 1.0, "flags": 1.04, "window_trim": 1.02}


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


static func validate_snapshot(
	next_sequence_value: Variant,
	library_value: Variant,
	active_value: Variant
) -> Dictionary:
	if not library_value is Dictionary:
		return _snapshot_error("invalid_blueprint_library")
	if not active_value is Dictionary:
		return _snapshot_error("invalid_active_blueprint_mapping")
	var library: Dictionary = library_value
	var active: Dictionary = active_value
	if not _is_integer_value(next_sequence_value) or int(next_sequence_value) < 1:
		return _snapshot_error("invalid_next_blueprint_sequence")
	var highest_generated_sequence := 0
	var library_building_ids: Dictionary = {}
	for library_key: Variant in library.keys():
		var entry_value: Variant = library[library_key]
		if not entry_value is Dictionary:
			return _snapshot_error("invalid_blueprint_library_entry")
		var entry: Dictionary = entry_value
		var entry_error := _validate_snapshot_entry(library_key, entry)
		if not entry_error.is_empty():
			return _snapshot_error(entry_error)
		var blueprint: Dictionary = entry["blueprint"]
		library_building_ids[str(entry["building_id"])] = true
		highest_generated_sequence = maxi(
			highest_generated_sequence,
			_generated_blueprint_sequence(str(blueprint["id"]))
		)
	if int(next_sequence_value) <= highest_generated_sequence:
		return _snapshot_error("next_blueprint_sequence_not_ahead")
	for building_key: Variant in active.keys():
		if not building_key is String or str(building_key).is_empty():
			return _snapshot_error("invalid_active_blueprint_building_id")
		var selected_value: Variant = active[building_key]
		if not selected_value is String or (selected_value as String).is_empty():
			return _snapshot_error("invalid_active_blueprint_id")
		var selected_id := str(selected_value)
		if not library.has(selected_id):
			return _snapshot_error("active_blueprint_missing_from_library")
		var selected_entry_value: Variant = library[selected_id]
		if not selected_entry_value is Dictionary:
			return _snapshot_error("invalid_active_blueprint_entry")
		if str((selected_entry_value as Dictionary).get("building_id", "")) != str(building_key):
			return _snapshot_error("active_blueprint_building_mismatch")
	for building_id_variant: Variant in library_building_ids.keys():
		if not active.has(str(building_id_variant)):
			return _snapshot_error("missing_active_blueprint_for_building")
	return {"valid": true, "error": ""}


static func _validate_snapshot_entry(library_key: Variant, entry: Dictionary) -> String:
	if not library_key is String or str(library_key).is_empty():
		return "invalid_blueprint_library_identity"
	for field_name: String in [
		"id", "building_id", "building_name", "title", "source", "status",
		"approved_day", "approved_sequence", "usage_count", "blueprint",
	]:
		if not entry.has(field_name):
			return "missing_blueprint_entry_field_%s" % field_name
	var library_id := str(library_key)
	if not entry["id"] is String or str(entry["id"]) != library_id:
		return "invalid_blueprint_library_identity"
	for string_field: String in ["building_id", "building_name", "title"]:
		var string_value: Variant = entry[string_field]
		if not string_value is String or str(string_value).is_empty():
			return "invalid_blueprint_entry_%s" % string_field
	var source_value: Variant = entry["source"]
	if not source_value is String or str(source_value) not in ["default", "player"]:
		return "invalid_blueprint_entry_source"
	if not entry["status"] is String or str(entry["status"]) != "approved":
		return "invalid_blueprint_entry_status"
	for integer_field: String in ["approved_day", "approved_sequence", "usage_count"]:
		if not _is_nonnegative_integer(entry[integer_field]):
			return "invalid_blueprint_entry_%s" % integer_field
	var blueprint_value: Variant = entry["blueprint"]
	if not blueprint_value is Dictionary:
		return "invalid_blueprint_library_payload"
	var blueprint: Dictionary = blueprint_value
	var blueprint_error := _validate_snapshot_blueprint(blueprint)
	if not blueprint_error.is_empty():
		return "invalid_blueprint_%s" % blueprint_error
	var building_id := str(entry["building_id"])
	if str(blueprint["building_id"]) != building_id:
		return "blueprint_building_mismatch"
	var usage_count := int(entry["usage_count"])
	if usage_count > 0:
		if (
			not _is_nonnegative_integer(entry.get("last_used_day", null))
			or int(entry["last_used_day"]) < int(entry["approved_day"])
		):
			return "invalid_blueprint_usage_lifecycle"
	elif entry.has("last_used_day"):
		return "invalid_unused_blueprint_lifecycle"
	var source := str(source_value)
	if source == "default":
		if int(entry["approved_day"]) != 0 or int(entry["approved_sequence"]) != 0:
			return "invalid_default_blueprint_approval"
		if library_id != "default_%s" % building_id:
			return "invalid_default_blueprint_identity"
		if entry.has("review_id"):
			return "invalid_default_blueprint_review"
	else:
		if int(entry["approved_sequence"]) < 1:
			return "invalid_player_blueprint_approval"
		var review_id_value: Variant = entry.get("review_id", null)
		if not review_id_value is String or str(review_id_value).is_empty():
			return "invalid_player_blueprint_review"
		if library_id != "approved_%s" % str(blueprint["id"]):
			return "invalid_player_blueprint_identity"
	return ""


static func _validate_snapshot_blueprint(blueprint: Dictionary) -> String:
	for field_name: String in [
		"id", "version", "building_id", "material_id", "floors", "size_tier",
		"roof_color", "wall_color", "decoration_id", "decoration_count",
		"requested_workers", "base_cost",
	]:
		if not blueprint.has(field_name):
			return "missing_%s" % field_name
	for string_field: String in ["id", "building_id", "material_id", "size_tier", "roof_color", "wall_color", "decoration_id"]:
		var string_value: Variant = blueprint[string_field]
		if not string_value is String or (string_field in ["id", "building_id", "material_id", "size_tier"] and str(string_value).is_empty()):
			return string_field
	if not _is_integer_value(blueprint["version"]) or int(blueprint["version"]) < 1:
		return "version"
	if not _is_integer_value(blueprint["floors"]) or int(blueprint["floors"]) < 1:
		return "floors"
	if not _is_integer_value(blueprint["decoration_count"]) or int(blueprint["decoration_count"]) < 0:
		return "decoration_count"
	if (
		not _is_integer_value(blueprint["requested_workers"])
		or int(blueprint["requested_workers"]) < 1
		or int(blueprint["requested_workers"]) > 20
	):
		return "requested_workers"
	if not _is_integer_value(blueprint["base_cost"]) or int(blueprint["base_cost"]) < 0:
		return "base_cost"
	if blueprint.has("workload") and not _is_positive_number(blueprint["workload"]):
		return "workload"
	return ""


static func _generated_blueprint_sequence(blueprint_id: String) -> int:
	if not blueprint_id.begins_with("blueprint_"):
		return 0
	var suffix := blueprint_id.trim_prefix("blueprint_")
	if suffix.is_empty() or not suffix.is_valid_int():
		return 0
	return maxi(0, int(suffix))


func preview_submission_blueprint(payload: Dictionary, definition) -> Dictionary:
	## The preview and submitted blueprint intentionally share this exact
	## normalization/cost authority.  UI quote callers must never manufacture a
	## parallel estimate from an approved (possibly older) blueprint.
	var defaults := _default_blueprint_for_definition(definition)
	var material_id := str(payload.get("material_id", defaults["material_id"]))
	if not MATERIAL_COST_MULTIPLIERS.has(material_id):
		material_id = str(defaults["material_id"])
	var size_tier := str(payload.get("size_tier", defaults["size_tier"]))
	if not SIZE_COST_MULTIPLIERS.has(size_tier):
		size_tier = str(defaults["size_tier"])
	var decoration_id := str(payload.get("decor_id", payload.get("decoration_id", defaults["decoration_id"])))
	if not DECORATION_COST_MULTIPLIERS.has(decoration_id):
		decoration_id = str(defaults["decoration_id"])
	var floors := clampi(int(payload.get("floors", defaults["floors"])), 1, 40)
	var requested_workers := clampi(int(payload.get("workers", payload.get("requested_workers", defaults["requested_workers"]))), 1, 20)
	return {
		"version": 1,
		"building_id": String(definition.id),
		"material_id": material_id,
		"floors": floors,
		"size_tier": size_tier,
		"roof_color": str(payload.get("roof_color", "blue")),
		"wall_color": str(payload.get("wall_color", "cream")),
		"decoration_id": decoration_id,
		"decoration_count": 1,
		"requested_workers": requested_workers,
		"base_cost": _design_base_cost(definition, defaults, material_id, size_tier, floors, decoration_id),
	}


func create_submission_blueprint(payload: Dictionary, definition) -> Dictionary:
	var blueprint_id := "blueprint_%06d" % next_blueprint_sequence
	next_blueprint_sequence += 1
	var blueprint := preview_submission_blueprint(payload, definition)
	blueprint["id"] = blueprint_id
	return blueprint


static func _design_base_cost(
	definition,
	defaults: Dictionary,
	material_id: String,
	size_tier: String,
	floors: int,
	decoration_id: String
) -> int:
	## Keep every catalog default exactly price-compatible while making each
	## player-visible design choice directly affect the quoted construction cost.
	var material_ratio: float = float(MATERIAL_COST_MULTIPLIERS[material_id]) / float(MATERIAL_COST_MULTIPLIERS[str(defaults["material_id"])])
	var size_ratio: float = float(SIZE_COST_MULTIPLIERS[size_tier]) / float(SIZE_COST_MULTIPLIERS[str(defaults["size_tier"])])
	var floor_ratio := maxf(0.50, 1.0 + float(floors - int(defaults["floors"])) * 0.08)
	var decor_ratio: float = float(DECORATION_COST_MULTIPLIERS[decoration_id]) / float(DECORATION_COST_MULTIPLIERS[str(defaults["decoration_id"])])
	return maxi(1, int(round(float(definition.base_cost) * material_ratio * size_ratio * floor_ratio * decor_ratio)))


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


static func _snapshot_error(code: String) -> Dictionary:
	return {"valid": false, "error": code}


static func _is_integer_value(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		return is_finite(float(value)) and float(value) == roundf(float(value))
	return false


static func _is_nonnegative_integer(value: Variant) -> bool:
	return _is_integer_value(value) and int(value) >= 0


static func _is_positive_number(value: Variant) -> bool:
	return (
		(value is int and int(value) > 0)
		or (value is float and is_finite(float(value)) and float(value) > 0.0)
	)
