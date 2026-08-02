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
	_test_snapshot_validation(compatible_snapshot, first_library_id)
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


func _test_snapshot_validation(valid_snapshot: Dictionary, player_library_id: String) -> void:
	_check(
		bool(BlueprintLibraryServiceScript.validate_snapshot(1, {}, {}).get("valid", false)),
		"empty current-schema library keeps sequence one valid"
	)
	var direct_result: Dictionary = BlueprintLibraryServiceScript.validate_snapshot(
		valid_snapshot["next_blueprint_sequence"],
		valid_snapshot["blueprint_library"],
		valid_snapshot["active_blueprint_by_building"]
	)
	_check(bool(direct_result.get("valid", false)), "live blueprint library snapshot passes schema validation")
	var json_value: Variant = JSON.parse_string(JSON.stringify(valid_snapshot))
	_check(json_value is Dictionary, "blueprint snapshot survives JSON encoding")
	if json_value is Dictionary:
		var json_snapshot: Dictionary = json_value
		var json_result: Dictionary = BlueprintLibraryServiceScript.validate_snapshot(
			json_snapshot["next_blueprint_sequence"],
			json_snapshot["blueprint_library"],
			json_snapshot["active_blueprint_by_building"]
		)
		_check(bool(json_result.get("valid", false)), "integral JSON floats remain valid blueprint numbers")

	var custom_snapshot := valid_snapshot.duplicate(true)
	var custom_entry: Dictionary = custom_snapshot["blueprint_library"][player_library_id].duplicate(true)
	var custom_blueprint: Dictionary = custom_entry["blueprint"].duplicate(true)
	custom_blueprint["id"] = "blueprint_custom_import"
	custom_entry["id"] = "approved_blueprint_custom_import"
	custom_entry["blueprint"] = custom_blueprint
	custom_snapshot["blueprint_library"][custom_entry["id"]] = custom_entry
	var custom_result: Dictionary = BlueprintLibraryServiceScript.validate_snapshot(
		custom_snapshot["next_blueprint_sequence"],
		custom_snapshot["blueprint_library"],
		custom_snapshot["active_blueprint_by_building"]
	)
	_check(bool(custom_result.get("valid", false)), "custom and default blueprint IDs do not consume generated numeric sequence space")

	var corruption_cases: Array[String] = [
		"string_sequence",
		"stale_generated_sequence",
		"missing_base_cost",
		"negative_base_cost",
		"zero_version",
		"zero_floors",
		"non_integral_floors",
		"negative_decoration_count",
		"worker_overflow",
		"invalid_source",
		"invalid_status",
		"negative_usage_count",
		"missing_last_used_day",
		"invalid_last_used_day",
		"player_zero_approved_sequence",
		"player_missing_review_id",
		"default_nonzero_approved_day",
		"blueprint_building_mismatch",
		"missing_active_building",
		"invalid_active_id_type",
	]
	for case_name: String in corruption_cases:
		var corrupted := _corrupt_blueprint_snapshot(valid_snapshot, player_library_id, case_name)
		var result: Dictionary = BlueprintLibraryServiceScript.validate_snapshot(
			corrupted["next_blueprint_sequence"],
			corrupted["blueprint_library"],
			corrupted["active_blueprint_by_building"]
		)
		_check(not bool(result.get("valid", true)), "blueprint corruption is rejected: %s" % case_name)


func _corrupt_blueprint_snapshot(source: Dictionary, player_library_id: String, case_name: String) -> Dictionary:
	var corrupted := source.duplicate(true)
	var default_entry: Dictionary = corrupted["blueprint_library"]["default_park"]
	var player_entry: Dictionary = corrupted["blueprint_library"][player_library_id]
	match case_name:
		"string_sequence":
			corrupted["next_blueprint_sequence"] = "3"
		"stale_generated_sequence":
			corrupted["next_blueprint_sequence"] = 2
		"missing_base_cost":
			(player_entry["blueprint"] as Dictionary).erase("base_cost")
		"negative_base_cost":
			(player_entry["blueprint"] as Dictionary)["base_cost"] = -1
		"zero_version":
			(player_entry["blueprint"] as Dictionary)["version"] = 0
		"zero_floors":
			(player_entry["blueprint"] as Dictionary)["floors"] = 0
		"non_integral_floors":
			(player_entry["blueprint"] as Dictionary)["floors"] = 1.5
		"negative_decoration_count":
			(player_entry["blueprint"] as Dictionary)["decoration_count"] = -1
		"worker_overflow":
			(player_entry["blueprint"] as Dictionary)["requested_workers"] = 21
		"invalid_source":
			player_entry["source"] = "external"
		"invalid_status":
			player_entry["status"] = "archived"
		"negative_usage_count":
			default_entry["usage_count"] = -1
		"missing_last_used_day":
			default_entry.erase("last_used_day")
		"invalid_last_used_day":
			default_entry["last_used_day"] = -1
		"player_zero_approved_sequence":
			player_entry["approved_sequence"] = 0
		"player_missing_review_id":
			player_entry.erase("review_id")
		"default_nonzero_approved_day":
			default_entry["approved_day"] = 1
		"blueprint_building_mismatch":
			(player_entry["blueprint"] as Dictionary)["building_id"] = "residence"
		"missing_active_building":
			corrupted["active_blueprint_by_building"].erase("park")
		"invalid_active_id_type":
			corrupted["active_blueprint_by_building"]["park"] = 7
	corrupted["blueprint_library"]["default_park"] = default_entry
	corrupted["blueprint_library"][player_library_id] = player_entry
	return corrupted


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
