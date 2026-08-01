extends SceneTree

const BlueprintLibraryServiceScript = preload("res://scripts/app/blueprint_library_service.gd")
const ContentRegistry = preload("res://data/catalogs/content_registry.gd")

var failed := false


func _initialize() -> void:
	var definitions: Dictionary = ContentRegistry.buildings_by_id()
	var service = BlueprintLibraryServiceScript.new()
	service.reset(definitions)
	_check(service.next_blueprint_sequence == 1, "new library starts at blueprint sequence one")
	_check(service.blueprint_library.size() == definitions.size(), "new library seeds exactly one default per building definition")
	_check(service.active_blueprint_by_building.size() == definitions.size(), "every building begins with an active default blueprint")
	var park_default: Dictionary = service.entry("default_park")
	_check(str(park_default.get("id", "")) == "default_park" and str(park_default.get("source", "")) == "default", "park default keeps its public library identity")
	_check(str(park_default.get("blueprint", {}).get("id", "")) == "blueprint_default_park", "default blueprint ID format is unchanged")

	var snapshot_before: Dictionary = service.snapshot()
	var snapshot_library: Dictionary = snapshot_before.get("blueprint_library", {})
	var mutated_default: Dictionary = snapshot_library.get("default_park", {})
	mutated_default["usage_count"] = 99
	snapshot_library["default_park"] = mutated_default
	_check(int(service.entry("default_park").get("usage_count", -1)) == 0, "snapshot returns a deep copy instead of mutable authority")

	var park_definition = definitions["park"]
	var first_blueprint: Dictionary = service.create_submission_blueprint({
		"material_id": "eco_composite",
		"floors": 0,
		"decor_id": "flags",
		"workers": 99,
	}, park_definition)
	_check(str(first_blueprint.get("id", "")) == "blueprint_000001" and service.next_blueprint_sequence == 2, "first player blueprint consumes the exact six-digit ID")
	_check(int(first_blueprint.get("floors", 0)) == 1 and int(first_blueprint.get("requested_workers", 0)) == 20, "submission normalization preserves floor and worker bounds")
	_check(str(first_blueprint.get("decoration_id", "")) == "flags", "legacy decor_id input keeps its mapping")
	var first_review := {
		"id": "review_000007",
		"sequence": 7,
		"resolved_day": 11,
		"blueprint": first_blueprint,
	}
	var first_library_id: String = service.archive_approved_blueprint(first_review, definitions, 99)
	_check(first_library_id == "approved_blueprint_000001", "approved library ID remains derived from the player blueprint ID")
	var first_entry: Dictionary = service.entry(first_library_id)
	_check(str(first_entry.get("title", "")) == "自訂核准版 1" and int(first_entry.get("approved_day", 0)) == 11, "first custom title and resolved day are unchanged")
	_check(str(service.active_blueprint_status("park", "公園").get("library_id", "")) == first_library_id, "newly approved player blueprint becomes active")

	var second_blueprint: Dictionary = service.create_submission_blueprint({}, park_definition)
	_check(str(second_blueprint.get("id", "")) == "blueprint_000002" and service.next_blueprint_sequence == 3, "second player blueprint preserves monotonic ID allocation")
	var second_library_id: String = service.archive_approved_blueprint({
		"id": "review_000003",
		"sequence": 3,
		"resolved_day": 12,
		"blueprint": second_blueprint,
	}, definitions, 99)
	var approved: Array[Dictionary] = service.approved_blueprints("park")
	_check(approved.size() == 3, "park library retains default and both player versions")
	_check(str(approved[0].get("id", "")) == "default_park", "default blueprint always sorts first")
	_check(str(approved[1].get("id", "")) == second_library_id and str(approved[2].get("id", "")) == first_library_id, "player blueprints sort only by approved review sequence")

	var selected: Dictionary = service.select_approved_blueprint("park", "default_park")
	_check(bool(selected.get("ok", false)) and str(service.active_blueprint_status("park", "公園").get("library_id", "")) == "default_park", "explicit active selection preserves the facade result")
	var mismatch: Dictionary = service.select_approved_blueprint("residence", "default_park")
	_check(str(mismatch.get("error", "")) == "blueprint_building_mismatch", "cross-building selection keeps its exact error")
	_check(str(service.active_blueprint_status("park", "公園").get("library_id", "")) == "default_park", "rejected selection cannot mutate the active park blueprint")
	_check(str(service.select_approved_blueprint("park", "missing").get("error", "")) == "blueprint_not_found", "unknown library ID keeps its exact error")

	_check(service.record_usage("default_park", 20), "existing blueprint usage can be recorded")
	_check(int(service.entry("default_park").get("usage_count", 0)) == 1 and int(service.entry("default_park").get("last_used_day", 0)) == 20, "usage count and last-used day update together")
	_check(not service.record_usage("missing", 21), "missing blueprint cannot gain usage")

	service.active_blueprint_by_building["park"] = "missing"
	var read_only_fallback: Dictionary = service.active_blueprint_status("park", "公園", false)
	_check(str(read_only_fallback.get("library_id", "")) == "default_park", "invalid active selection falls back to sorted first entry")
	_check(str(service.active_blueprint_by_building.get("park", "")) == "missing", "read-only fallback does not repair active state")
	service.active_blueprint_status("park", "公園", true)
	_check(str(service.active_blueprint_by_building.get("park", "")) == "default_park", "writable fallback repairs active state")

	service.select_approved_blueprint("park", first_library_id)
	var compatible_snapshot: Dictionary = service.snapshot()
	_check(_sorted_strings(compatible_snapshot.keys()) == ["active_blueprint_by_building", "blueprint_library", "next_blueprint_sequence"], "snapshot keeps the three schema-4 flat field names")
	var restored = BlueprintLibraryServiceScript.new()
	restored.restore(
		int(compatible_snapshot["next_blueprint_sequence"]),
		compatible_snapshot["blueprint_library"],
		compatible_snapshot["active_blueprint_by_building"],
		definitions
	)
	_check(restored.snapshot() == compatible_snapshot, "complete service snapshot round-trips without shape or value drift")
	restored.select_approved_blueprint("park", "default_park")
	_check(str(restored.active_blueprint_by_building.get("park", "")) == "default_park", "restored library still permits an explicit default selection")
	_check(restored.archive_approved_blueprint(first_review, definitions, 99) == first_library_id, "historical duplicate archival retains its existing library ID")
	_check(str(restored.active_blueprint_by_building.get("park", "")) == first_library_id, "historical duplicate archival retains the legacy active-selection replay behavior")

	var legacy = BlueprintLibraryServiceScript.new()
	legacy.restore(0, {}, {}, definitions)
	_check(legacy.next_blueprint_sequence == 1 and legacy.blueprint_library.size() == definitions.size(), "legacy missing fields rebuild defaults and clamp sequence to one")

	if failed:
		quit(1)
	else:
		print("Blueprint library service self-test passed. Defaults=%d ParkVersions=%d" % [definitions.size(), approved.size()])
		quit(0)


func _sorted_strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(str(value))
	result.sort()
	return result


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	failed = true
	push_error("Blueprint library service self-test failed: %s" % label)
