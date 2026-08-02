extends SceneTree

const CoordinatorScript = preload("res://scripts/app/vertical_slice_coordinator.gd")
const MAIN_SCRIPT_PATH := "res://scripts/app/main.gd"

const MID_BROKEN_SAVE_PATH := "user://goal_2026_08_01/public_service_mid_broken.json"

var _failed := false
var _checks := 0
var _main_instances: Array[Node] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var l10n := root.get_node_or_null("L10n")
	if l10n != null:
		l10n.call("set_locale", "zh_TW", false)
	_cleanup_save()
	_test_healthcare_lifecycle_and_round_trip()
	_test_schema_eight_latch_recovery()
	_test_legacy_direct_effect_migration()
	_cleanup_save()
	_cleanup_main_instances()
	await process_frame
	if not _failed:
		print("Public service lifecycle integration test passed. Checks=%d" % _checks)
	quit(1 if _failed else 0)


func _test_healthcare_lifecycle_and_round_trip() -> void:
	var coordinator = CoordinatorScript.new(20_260_806, 2_000_000)
	var main = _new_main_shell(coordinator)
	var hospital_tile := _tile(coordinator, 0, 2)
	var road_tiles: Array[int] = [_tile(coordinator, 1, 2), _tile(coordinator, 2, 2)]
	var anchor_tile := _tile(coordinator, 3, 2)
	for tile_id: int in road_tiles:
		coordinator.terrain_map.flatten_tile(tile_id)
	var hospital: Dictionary = coordinator.register_existing_building(hospital_tile, "醫院")
	var anchor: Dictionary = coordinator.register_existing_building(anchor_tile, "市政府")
	_check(not hospital.is_empty() and not anchor.is_empty(), "authoritative healthcare fixtures must register")
	main.city_grid[hospital_tile] = "醫院"
	main.city_grid[anchor_tile] = "市政府"

	var baseline_healthcare := int(main.healthcare)
	var baseline_satisfaction := int(main.total_satisfaction)
	main._apply_building_effect(Dictionary(main.buildings["醫院"]))
	_check(int(main.healthcare) == baseline_healthcare, "hospital completion must not apply the legacy healthcare bonus")
	_check(int(main.total_satisfaction) == baseline_satisfaction, "hospital completion must not apply the legacy satisfaction bonus")
	var unavailable: Dictionary = main._reconcile_healthcare_service()
	_check(str(unavailable.get("status", "")) == "unavailable", "hospital without a road must be unavailable")
	_check(str(unavailable.get("reason_code", "")) == "road_missing", "hospital without a road must expose road_missing")
	_check(int(main.healthcare_applied_bonus) == 0 and int(main.healthcare) == baseline_healthcare, "unavailable hospital must not affect the metric")
	_check(main._service_fee_income("medical") == 0, "unavailable hospital must not produce medical revenue")
	_check(main._healthcare_service_visible_text(unavailable).contains("無法服務"), "visible service copy must use a concise Traditional-Chinese status")
	_check(main._healthcare_service_visible_text(unavailable).contains("缺少道路連接"), "visible service copy must explain the road gate")

	var input_snapshot: Dictionary = coordinator.public_service_input_snapshot(main.city_grid)
	_check(Dictionary(input_snapshot.get("building_records", {})) == coordinator.session.state.buildings, "service input must use all authoritative CityState building records")
	_check(Dictionary(input_snapshot.get("durability_records", {})) == coordinator.durability.buildings, "service input must use all durability records")
	_check(Array(input_snapshot.get("road_access_components", [])).is_empty(), "road components must be empty before the road is completed")
	_check(int(input_snapshot.get("capacity_per_facility", 0)) == 250, "hospital capacity must come from the public-service catalog")
	_check(int(input_snapshot.get("max_metric_bonus", 0)) == 30, "hospital metric bonus must come from the public-service catalog")
	var stable_json := JSON.stringify(input_snapshot)
	var parsed_snapshot: Variant = JSON.parse_string(stable_json)
	_check(parsed_snapshot is Dictionary, "public-service input must be JSON-safe")
	_check(input_snapshot == coordinator.public_service_input_snapshot(main.city_grid), "repeated public-service input calculation must be stable")

	var road_start: Dictionary = coordinator.start_transport_project("road", "build", road_tiles, 20, main.city_grid)
	_check(bool(road_start.get("ok", false)), "the access road must start through the coordinator")
	if not bool(road_start.get("ok", false)):
		return
	coordinator.advance_days(int(road_start.get("job", {}).get("projected_remaining_days", 0)), {}, false)
	_check(coordinator.transport.segments.size() == 1, "road must become authoritative only after completion")
	var connected: Dictionary = main._reconcile_healthcare_service()
	_check(str(connected.get("status", "")) in ["operational", "degraded"], "completed road must activate healthcare")
	_check(str(connected.get("reason_code", "")) in ["operational", "capacity_shortfall"], "connected service must expose a stable positive reason")
	_check(int(connected.get("operational_facility_count", 0)) == 1, "one connected hospital must be operational")
	_check(int(connected.get("capacity", 0)) == 250 and int(connected.get("served", 0)) == 250, "full-durability hospital must expose catalog capacity and served residents")
	_check(int(main.healthcare_applied_bonus) > 0 and int(main.healthcare) > baseline_healthcare, "connected service must apply a positive metric bonus")
	var connected_healthcare := int(main.healthcare)
	var connected_revenue: int = int(main._service_fee_income("medical"))
	_check(connected_revenue > 0, "connected service must produce medical revenue")
	var request_context: Dictionary = main._vertical_city_context()
	_check(int(request_context.get("operational_hospital_count", 0)) == 1, "request context must use operational hospital count")
	_check(int(request_context.get("operational_hospital_capacity", 0)) == 250, "request context must use operational hospital capacity")
	_check(str(connected.get("status", "")) == str(coordinator.healthcare_service_result(main.city_grid).get("status", "")), "Main and Coordinator must expose the same derived result")

	var hospital_id := str(hospital.get("building_id", ""))
	var damage: Dictionary = coordinator.durability.apply_damage(hospital_id, 15, "test.public_service.wear", coordinator.game_day())
	_check(bool(damage.get("ok", false)), "hospital durability fixture must accept damage")
	if bool(damage.get("ok", false)):
		coordinator._handle_durability_fact(damage["event"])
	var worn: Dictionary = main._reconcile_healthcare_service()
	_check(int(worn.get("capacity", 0)) == 200, "85 durability must reduce effective capacity to 80 percent")
	_check(int(main.healthcare) < connected_healthcare, "reduced capacity must lower the applied healthcare metric")
	_check(main._service_fee_income("medical") < connected_revenue, "reduced capacity must lower medical revenue")

	coordinator.set_maintenance_payment(false)
	var broken: Dictionary = main._reconcile_healthcare_service()
	_check(str(broken.get("status", "")) == "unavailable" and str(broken.get("reason_code", "")) == "maintenance_unfunded", "disabled maintenance must make healthcare unavailable")
	_check(int(main.healthcare_applied_bonus) == 0 and int(main.healthcare) == baseline_healthcare, "maintenance failure must remove only the applied service bonus")
	_check(main._service_fee_income("medical") == 0, "maintenance failure must stop medical revenue")
	var broken_healthcare := int(main.healthcare)
	var broken_shell: Dictionary = main._capture_player_shell_state()
	_check(int(broken_shell.get("schema_version", 0)) == 8, "player shell must persist schema 8")
	_check(int(broken_shell.get("healthcare_applied_bonus", -1)) == 0, "mid-broken shell must persist the zero applied-bonus latch")
	coordinator.set_player_shell_state(broken_shell)
	_check(coordinator.save_game(MID_BROKEN_SAVE_PATH) == OK, "mid-broken service state must save")

	var restored = CoordinatorScript.new(1, 1)
	_check(restored.load_game(MID_BROKEN_SAVE_PATH), "mid-broken service state must load")
	var restored_main = _loaded_main_shell(restored)
	var restored_result: Dictionary = restored_main._healthcare_service_result()
	_check(str(restored_result.get("reason_code", "")) == "maintenance_unfunded", "mid-broken load must preserve the failure reason")
	_check(int(restored_main.healthcare) == broken_healthcare and int(restored_main.healthcare_applied_bonus) == 0, "mid-broken load must preserve metric and latch without drift")
	_check(restored_main._service_fee_income("medical") == 0, "mid-broken load must keep medical revenue disabled")
	var repeated_broken: Dictionary = restored_main._reconcile_healthcare_service()
	_check(repeated_broken == restored_result and int(restored_main.healthcare) == broken_healthcare, "repeated broken-state calculation must be idempotent")

	restored.set_maintenance_payment(true)
	var repair: Dictionary = restored.repair_building(hospital_tile)
	_check(bool(repair.get("ok", false)), "worn hospital must be repairable after maintenance funding returns")
	var repaired: Dictionary = restored_main._reconcile_healthcare_service()
	_check(int(repaired.get("capacity", 0)) == 250 and int(repaired.get("operational_facility_count", 0)) == 1, "repair must restore full operational capacity")
	_check(int(restored_main.healthcare) == connected_healthcare, "repair must restore the same healthcare metric")
	_check(restored_main._service_fee_income("medical") == connected_revenue, "repair must restore the same medical revenue")
	var repaired_healthcare := int(restored_main.healthcare)
	var repaired_latch := int(restored_main.healthcare_applied_bonus)
	for _iteration in range(4):
		restored_main._reconcile_healthcare_service()
	_check(int(restored_main.healthcare) == repaired_healthcare and int(restored_main.healthcare_applied_bonus) == repaired_latch, "repeated recovery calculation must not duplicate the bonus")
	var repaired_context: Dictionary = restored_main._vertical_city_context()
	_check(int(repaired_context.get("operational_hospital_count", 0)) == 1 and int(repaired_context.get("operational_hospital_capacity", 0)) == 250, "repaired request context must restore operational values")
	_check(repaired == restored.healthcare_service_result(restored_main.city_grid), "repaired derived result must be deterministic across callers")


func _test_schema_eight_latch_recovery() -> void:
	var source = CoordinatorScript.new(20_260_816, 2_000_000)
	var source_main = _new_main_shell(source)
	var hospital_tile := _tile(source, 0, 4)
	var road_tiles: Array[int] = [_tile(source, 1, 4), _tile(source, 2, 4), _tile(source, 3, 4), _tile(source, 4, 4)]
	var second_hospital_tile := _tile(source, 5, 4)
	for tile_id: int in road_tiles:
		source.terrain_map.flatten_tile(tile_id)
	source.register_existing_building(hospital_tile, "醫院")
	source.register_existing_building(second_hospital_tile, "醫院")
	source_main.city_grid[hospital_tile] = "醫院"
	source_main.city_grid[second_hospital_tile] = "醫院"
	var road_start: Dictionary = source.start_transport_project("road", "build", road_tiles, 20, source_main.city_grid)
	_check(bool(road_start.get("ok", false)), "schema-8 latch fixture road must start")
	if not bool(road_start.get("ok", false)):
		return
	source.advance_days(int(road_start.get("job", {}).get("projected_remaining_days", 0)), {}, false)
	source_main.healthcare = 75
	source_main._reconcile_healthcare_service()
	var expected_healthcare := int(source_main.healthcare)
	var expected_latch := int(source_main.healthcare_applied_bonus)
	_check(expected_healthcare == 100 and expected_latch == 25, "saturated service must latch only the 25 points actually applied from a 75 base")
	source.set_maintenance_payment(false)
	source_main._reconcile_healthcare_service()
	_check(int(source_main.healthcare) == 75 and int(source_main.healthcare_applied_bonus) == 0, "removing a saturated service bonus must restore its exact 75-point base")
	source.set_maintenance_payment(true)
	source_main._reconcile_healthcare_service()
	_check(int(source_main.healthcare) == 100 and int(source_main.healthcare_applied_bonus) == 25, "restoring saturated service must remain drift-free")
	var valid_shell: Dictionary = source_main._capture_player_shell_state()
	_check(int(valid_shell.get("healthcare_service_base", -1)) == 75, "schema 8 must preserve the service-less base for fail-safe latch recovery")

	var corrupt_shell := valid_shell.duplicate(true)
	corrupt_shell["healthcare_applied_bonus"] = 999
	var corrupt_main = _new_main_instance()
	corrupt_main.vertical_slice = source
	corrupt_main.city_grid = source_main.city_grid.duplicate()
	corrupt_main._restore_player_shell_state(corrupt_shell)
	_check(int(corrupt_main.healthcare_applied_bonus) == expected_latch, "out-of-range schema-8 latch must recover from the authoritative model")
	_check(int(corrupt_main.healthcare) == expected_healthcare, "corrupt schema-8 latch must not erase authoritative healthcare")

	var missing_shell := valid_shell.duplicate(true)
	missing_shell.erase("healthcare_applied_bonus")
	var missing_main = _new_main_instance()
	missing_main.vertical_slice = source
	missing_main.city_grid = source_main.city_grid.duplicate()
	missing_main._restore_player_shell_state(missing_shell)
	_check(int(missing_main.healthcare_applied_bonus) == expected_latch, "missing schema-8 latch must recover deterministically")
	_check(int(missing_main.healthcare) == expected_healthcare, "missing schema-8 latch must not apply the service bonus twice")

	var inconsistent_shell := valid_shell.duplicate(true)
	inconsistent_shell["healthcare_applied_bonus"] = 10
	var inconsistent_main = _new_main_instance()
	inconsistent_main.vertical_slice = source
	inconsistent_main.city_grid = source_main.city_grid.duplicate()
	inconsistent_main._restore_player_shell_state(inconsistent_shell)
	_check(int(inconsistent_main.healthcare_applied_bonus) == expected_latch, "in-range latch inconsistent with healthcare-service base must self-heal")
	source.set_maintenance_payment(false)
	inconsistent_main._reconcile_healthcare_service()
	_check(int(inconsistent_main.healthcare) == 75, "self-healed in-range latch must return to the exact base when service fails")
	source.set_maintenance_payment(true)
	inconsistent_main._reconcile_healthcare_service()


func _test_legacy_direct_effect_migration() -> void:
	var legacy = CoordinatorScript.new(20_260_826, 500_000)
	var legacy_main = _new_main_shell(legacy)
	var hospital_tile := _tile(legacy, 7, 7)
	legacy.register_existing_building(hospital_tile, "醫院")
	legacy_main.city_grid[hospital_tile] = "醫院"
	legacy_main.healthcare = 81
	legacy_main.total_satisfaction = 73
	legacy_main._healthcare_legacy_migration_applied = false
	var legacy_shell := {"schema_version": 7}
	legacy_main._restore_player_shell_state(legacy_shell)
	_check(int(legacy_main.healthcare) == 70, "schema<8 must remove the active hospital's legacy healthcare bonus once")
	var migrated_satisfaction := int(legacy_main.total_satisfaction)
	legacy_main._restore_player_shell_state(legacy_shell)
	_check(int(legacy_main.healthcare) == 70 and int(legacy_main.total_satisfaction) == migrated_satisfaction, "repeated legacy restore must not migrate direct effects twice")

	var scrapped = CoordinatorScript.new(20_260_827, 500_000)
	var scrapped_main = _new_main_shell(scrapped)
	var scrapped_tile := _tile(scrapped, 7, 6)
	var scrapped_record: Dictionary = scrapped.register_existing_building(scrapped_tile, "醫院")
	scrapped_main.city_grid[scrapped_tile] = "醫院"
	var damage: Dictionary = scrapped.durability.apply_damage(str(scrapped_record.get("building_id", "")), 70, "test.legacy.scrapped", scrapped.game_day())
	if bool(damage.get("ok", false)):
		scrapped._handle_durability_fact(damage["event"])
	scrapped_main.building_customizations[scrapped_tile] = {"effects_inactive": true}
	scrapped_main.healthcare = 70
	scrapped_main._healthcare_legacy_migration_applied = false
	scrapped_main._restore_player_shell_state(legacy_shell)
	_check(int(scrapped_main.healthcare) == 70, "legacy migration must not subtract a scrapped/effects-inactive hospital twice")


func _new_main_shell(coordinator):
	var main = _new_main_instance()
	main.vertical_slice = coordinator
	main.city_grid.clear()
	for _index in coordinator.terrain_map.cell_count():
		main.city_grid.append("")
	main._initialize_city_metric_defaults()
	main.healthcare_applied_bonus = 0
	main._healthcare_legacy_migration_applied = true
	return main


func _loaded_main_shell(coordinator):
	var main = _new_main_instance()
	main.vertical_slice = coordinator
	main._rebuild_city_from_core()
	main._restore_player_shell_state(coordinator.get_player_shell_state())
	return main


func _new_main_instance():
	var main_script: Script = load(MAIN_SCRIPT_PATH)
	var main: Node = main_script.new()
	_main_instances.append(main)
	return main


func _cleanup_main_instances() -> void:
	for main: Node in _main_instances:
		if is_instance_valid(main):
			main.free()
	_main_instances.clear()


func _tile(coordinator, x: int, y: int) -> int:
	return int(coordinator.terrain_map.tile_id_for_coordinate(Vector2i(x, y)))


func _cleanup_save() -> void:
	var absolute := ProjectSettings.globalize_path(MID_BROKEN_SAVE_PATH)
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		var candidate := absolute + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Public service lifecycle integration test failed: %s" % message)
