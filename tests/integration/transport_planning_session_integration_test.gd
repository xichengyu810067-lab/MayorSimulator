extends SceneTree

const CoordinatorScript = preload("res://scripts/app/vertical_slice_coordinator.gd")
const TransportModesScript = preload("res://data/catalogs/transport_modes.gd")
const CityTerrainMapScript = preload("res://scripts/world/city_terrain_map.gd")
const SaveSchemaAuthorityScript = preload("res://scripts/core/save_schema_authority.gd")
const TransportPlanningSessionScript = preload("res://scripts/systems/city/transport_planning_session.gd")
const LAYOUT3_PRESERVATION_FIXTURE_PATH := "res://tests/fixtures/save_schema/layout3_preservation_migration.json"

const SAVE_PATH := "user://w4_transport_planning_session_round_trip.json"

var _failed := false
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	_test_state_semantics_fail_closed()
	_test_schema_v2_migration_and_corridor_quote_integrity()
	_test_mode_compatible_supporting_infrastructure()
	_test_continuous_session_and_round_trip()
	_test_schema_nine_migrates_inactive_and_schema_eleven_fails_closed()
	_test_close_does_not_cancel_authoritative_construction()
	_cleanup()
	if not _failed:
		print("Transport planning session integration test passed. Checks=%d Schema=11" % _checks)
	quit(1 if _failed else 0)


func _test_state_semantics_fail_closed() -> void:
	var materialized := _planning_snapshot_fixture()
	materialized["session"]["state"] = "materialized"
	_check(
		not bool(TransportPlanningSessionScript.validate_snapshot(materialized).get("valid", false)),
		"shape-valid materialized state without completed phases and a route fails closed"
	)
	var route_edit := _planning_snapshot_fixture()
	route_edit["session"]["state"] = "route_edit"
	route_edit["session"]["station_refs"] = [
		_station_ref("station_job_1", 1, "active"),
		_station_ref("station_job_2", 2, "active"),
	]
	route_edit["session"]["network_refs"] = [_network_ref("network_job_1", "project_1", "road", "completed")]
	route_edit["session"]["network_draft"] = {"kind": "road"}
	route_edit["session"]["route_draft"] = {"mode": "bus"}
	_check(
		not bool(TransportPlanningSessionScript.validate_snapshot(route_edit).get("valid", false)),
		"route edit without enough completed station references fails closed"
	)

	var network_placement := _planning_snapshot_fixture()
	network_placement["session"]["state"] = "network_placement"
	network_placement["session"]["network_draft"] = {"kind": "road"}
	_check(
		not bool(TransportPlanningSessionScript.validate_snapshot(network_placement).get("valid", false)),
		"network placement without the mode's minimum station references fails closed"
	)

	var waiting := _planning_snapshot_fixture()
	waiting["session"]["state"] = "waiting_construction"
	waiting["session"]["resume_state"] = "route_edit"
	waiting["session"]["station_refs"] = [_station_ref("station_job_1", 1, "active")]
	_check(
		not bool(TransportPlanningSessionScript.validate_snapshot(waiting).get("valid", false)),
		"waiting state cannot resume to an unreachable route phase"
	)

	var paused := _planning_snapshot_fixture()
	paused["session"]["state"] = "paused"
	paused["session"]["resume_state"] = "network_placement"
	_check(
		not bool(TransportPlanningSessionScript.validate_snapshot(paused).get("valid", false)),
		"paused state cannot resume to network placement without enough stations"
	)
	var closed := _planning_snapshot_fixture()
	closed["session"]["state"] = "closed"
	_check(
		not bool(TransportPlanningSessionScript.validate_snapshot(closed).get("valid", false)),
		"closed state requires an explicit close reason and no resume target"
	)

	var legal_waiting := _planning_snapshot_fixture()
	legal_waiting["session"]["state"] = "waiting_construction"
	legal_waiting["session"]["resume_state"] = "station_placement"
	legal_waiting["session"]["station_refs"] = [_station_ref("station_job_1", 1, "active")]
	_check(
		bool(TransportPlanningSessionScript.validate_snapshot(legal_waiting).get("valid", false)),
		"legal mid-construction station wait remains serializable"
	)


func _test_schema_v2_migration_and_corridor_quote_integrity() -> void:
	var legacy := _planning_snapshot_fixture()
	legacy["schema_version"] = 1
	var migrated = TransportPlanningSessionScript.create_from_dict(legacy)
	_check(migrated != null and int(migrated.to_dict().get("schema_version", -1)) == 2, "planning schema 1 migrates to schema 2")
	var future := _planning_snapshot_fixture()
	future["schema_version"] = 3
	_check(TransportPlanningSessionScript.create_from_dict(future) == null, "future planning schema fails closed")

	var corridor_contract := {
		"schema_version": TransportModesScript.ROUTE_PACKAGE_CORRIDOR_SCHEMA_VERSION,
		"mode": "bus",
		"segment_kind": "road",
		"classification": "mixed",
		"route_tile_ids": [0, 1, 2, 3],
		"reused_segment_refs": [{"id": "segment_a", "kind": "road", "tile_ids": [0, 1]}],
		"new_runs": [{"kind": "road", "tile_path": [2, 3]}],
		"total_units": 4,
		"reused_units": 2,
		"new_units": 2,
	}
	var corridor_quote := TransportModesScript.route_package_corridor_price_quote(corridor_contract)
	_check(bool(corridor_quote.get("ok", false)), "planning fixture obtains a valid reuse-aware corridor quote")
	var planning = TransportPlanningSessionScript.new()
	_check(bool(planning.begin("公車站", "fixture_bus_station", TransportPlanningSessionScript.WORKFLOW_ROUTE_PACKAGE_V1).get("ok", false)), "route-package planning begins")
	for tile_id: int in [10, 20]:
		var placement := {
			"anchor_tile_id": tile_id,
			"occupied_tile_ids": [tile_id],
			"footprint_id": "single_tile",
			"library_id": "fixture_bus_station",
			"blueprint": {"name": "公車站"},
			"total_cost": 100,
			"duration_days": 1,
		}
		_check(bool(planning.record_station_draft(placement, 1).get("ok", false)), "route-package station draft records")
	_check(bool(planning.begin_network_placement("road").get("ok", false)), "route-package enters network placement")
	_check(bool(planning.update_network_draft("road", {"tile_ids": [0, 1, 2, 3], "worker_count": 2}).get("ok", false)), "route-package network draft records")
	_check(bool(planning.begin_route_edit().get("ok", false)), "route-package enters route editing")
	_check(bool(planning.update_route_draft({
		"corridor_quote": corridor_quote,
		"corridor_network_revision": "a".repeat(64),
	}).get("ok", false)), "valid reuse-aware quote attaches to route draft with its network revision")
	var snapshot: Dictionary = planning.to_dict()
	_check(bool(TransportPlanningSessionScript.validate_snapshot(snapshot).get("valid", false)), "planning snapshot validates with reuse-aware quote")
	var decoded_snapshot = JSON.parse_string(JSON.stringify(snapshot))
	var decoded_quote: Dictionary = decoded_snapshot.get("session", {}).get("route_draft", {}).get("corridor_quote", {})
	var decoded_quote_validation := TransportModesScript.validate_route_package_corridor_price_quote(decoded_quote)
	_check(bool(decoded_quote_validation.get("valid", false)), "JSON-decoded quote remains valid: %s" % str(decoded_quote_validation))
	var decoded_validation: Dictionary = TransportPlanningSessionScript.validate_snapshot(decoded_snapshot)
	_check(bool(decoded_validation.get("valid", false)), "JSON-decoded planning snapshot remains valid: %s" % str(decoded_validation))
	var round_trip = TransportPlanningSessionScript.create_from_dict(decoded_snapshot)
	var restored_quote: Dictionary = {}
	if round_trip != null:
		restored_quote = round_trip.to_dict().get("session", {}).get("route_draft", {}).get("corridor_quote", {})
	_check(round_trip != null, "planning snapshot survives JSON round trip")
	_check(str(restored_quote.get("checksum", "")) == str(corridor_quote.get("checksum", "")), "planning quote checksum survives JSON round trip")
	_check(int(restored_quote.get("total_cost", -1)) == int(corridor_quote.get("total_cost", -2)), "planning quote cost survives JSON round trip")
	_check(Dictionary(restored_quote.get("corridor", {})).get("route_tile_ids", []) == [0, 1, 2, 3], "planning quote corridor survives JSON round trip")
	_check(bool(TransportModesScript.validate_route_package_corridor_price_quote(restored_quote).get("valid", false)), "restored planning quote remains valid")

	var before_rejection: Dictionary = planning.to_dict()
	var tampered_quote: Dictionary = corridor_quote.duplicate(true)
	tampered_quote["total_cost"] = int(tampered_quote.get("total_cost", 0)) + 1
	_check(not bool(planning.update_route_draft({"corridor_quote": tampered_quote}).get("ok", true)), "tampered quote is rejected")
	_check(planning.to_dict() == before_rejection, "tampered quote rejection does not mutate planning state")
	var train_contract: Dictionary = corridor_contract.duplicate(true)
	train_contract["mode"] = "train"
	train_contract["segment_kind"] = "rail_track"
	train_contract["reused_segment_refs"][0]["kind"] = "rail_track"
	train_contract["new_runs"][0]["kind"] = "rail_track"
	var wrong_mode_quote: Dictionary = TransportModesScript.route_package_corridor_price_quote(train_contract)
	_check(bool(wrong_mode_quote.get("ok", false)), "different-mode quote fixture is independently valid")
	_check(not bool(planning.update_route_draft({"corridor_quote": wrong_mode_quote}).get("ok", true)), "quote for a different mode is rejected")
	_check(planning.to_dict() == before_rejection, "mode mismatch rejection does not mutate planning state")


func _test_mode_compatible_supporting_infrastructure() -> void:
	var train_signal := _planning_snapshot_fixture()
	train_signal["session"]["station_blueprint_name"] = "火車站"
	train_signal["session"]["mode"] = "train"
	train_signal["session"]["state"] = "network_placement"
	train_signal["session"]["station_refs"] = [
		_station_ref("train_station_job_1", 1, "active"),
		_station_ref("train_station_job_2", 2, "active"),
	]
	train_signal["session"]["network_draft"] = {"kind": "rail_signal"}
	_check(
		bool(TransportPlanningSessionScript.validate_snapshot(train_signal).get("valid", false)),
		"train session accepts a rail-signal project supported by its rail guideway"
	)

	var air_taxiway := _planning_snapshot_fixture()
	air_taxiway["session"]["station_blueprint_name"] = "機場"
	air_taxiway["session"]["mode"] = "air"
	air_taxiway["session"]["state"] = "network_placement"
	air_taxiway["session"]["station_refs"] = [_station_ref("airport_job_1", 3, "active")]
	air_taxiway["session"]["network_draft"] = {"kind": "taxiway"}
	_check(
		bool(TransportPlanningSessionScript.validate_snapshot(air_taxiway).get("valid", false)),
		"air session accepts its taxiway support segment"
	)

	var cross_mode := train_signal.duplicate(true)
	cross_mode["session"]["network_draft"] = {"kind": "metro_track"}
	_check(
		not bool(TransportPlanningSessionScript.validate_snapshot(cross_mode).get("valid", false)),
		"session still rejects infrastructure from another transport mode"
	)


func _test_continuous_session_and_round_trip() -> void:
	var coordinator = CoordinatorScript.new(20_260_902, 3_000_000)
	coordinator.terrain_map = CityTerrainMapScript.new()
	var first_tile := _tile(coordinator, 2, 3)
	var second_tile := _tile(coordinator, 4, 3)
	var city_grid := _empty_city_grid(coordinator)
	var begun: Dictionary = coordinator.begin_transport_planning_session("公車站")
	_check(bool(begun.get("ok", false)), "a bus-station blueprint starts one planning session")
	var session_id := str(begun.get("session", {}).get("id", ""))
	_check(not session_id.is_empty(), "planning session receives a stable identity")
	_check(bool(coordinator.pause_transport_planning_session().get("ok", false)), "station placement session can pause")
	_check(str(coordinator.transport_planning_session_snapshot().get("state", "")) == "paused", "pause state is authoritative")
	_check(bool(coordinator.resume_transport_planning_session().get("ok", false)), "paused session resumes")
	_check(str(coordinator.transport_planning_session_snapshot().get("state", "")) == "station_placement", "resume returns to station placement")

	var first: Dictionary = coordinator.place_transport_session_station(first_tile, 5)
	_check(bool(first.get("ok", false)), "first station starts without closing the planning session")
	var funds_after_first := coordinator.treasury_balance()
	var jobs_after_first: int = int(coordinator.construction.jobs.size())
	var refs_after_first := Array(coordinator.transport_planning_session_snapshot().get("station_refs", [])).duplicate(true)
	var invalid: Dictionary = coordinator.place_transport_session_station(first_tile, 5)
	_check(not bool(invalid.get("ok", false)), "invalid overlapping second station is rejected")
	_check(coordinator.treasury_balance() == funds_after_first, "invalid second station does not deduct funds")
	_check(coordinator.construction.jobs.size() == jobs_after_first, "invalid second station leaves no partial construction job")
	_check(
		Array(coordinator.transport_planning_session_snapshot().get("station_refs", [])) == refs_after_first,
		"invalid second station leaves the first station reference unchanged"
	)
	var second: Dictionary = coordinator.place_transport_session_station(second_tile, 5)
	_check(bool(second.get("ok", false)), "same session starts a second station of the selected type")
	_check(
		Array(coordinator.transport_planning_session_snapshot().get("station_refs", [])).size() == 2,
		"one session retains both station job identities"
	)

	var wait_result: Dictionary = coordinator.wait_for_transport_session_construction("station_placement")
	_check(bool(wait_result.get("ok", false)), "active station construction can enter waiting state")
	var before_save := coordinator.transport_planning_session_snapshot()
	var save_error: Error = coordinator.save_game(SAVE_PATH)
	_check(
		save_error == OK,
		"active planning session saves: %s" % coordinator.session.save_service.last_error_message
	)
	var restored = CoordinatorScript.new(1, 1)
	var loaded := restored.load_game(SAVE_PATH)
	_check(loaded, "active planning session reloads")
	var after_load: Dictionary = restored.transport_planning_session_snapshot()
	_check(str(after_load.get("id", "")) == session_id, "session identity survives save/load")
	_check(str(after_load.get("state", "")) == "waiting_construction", "waiting state survives save/load")
	_check(
		_ref_ids(after_load.get("station_refs", []), "job_id") == _ref_ids(before_save.get("station_refs", []), "job_id"),
		"station job references survive save/load"
	)

	var station_days := _maximum_active_days(restored)
	restored.advance_days(station_days, {}, false)
	_check(str(restored.transport_planning_session_snapshot().get("state", "")) == "station_placement", "station completion resumes the requested phase")
	var station_refs: Array = restored.transport_planning_session_snapshot().get("station_refs", [])
	_check(_all_refs_status(station_refs, "completed"), "both completed jobs materialize station identities")
	_check(not str(Dictionary(station_refs[0]).get("station_id", "")).is_empty(), "completed station reference points at topology identity")

	var road_tiles := _horizontal_tiles(restored, 1, 2, 5)
	var begin_network: Dictionary = restored.begin_transport_session_network_placement(
		"road", {"tile_ids": road_tiles.duplicate()}
	)
	_check(bool(begin_network.get("ok", false)), "same session transitions from stations to network placement")
	var failed_network_session_before := restored.transport_planning_session_snapshot()
	var failed_network_transport_before: Dictionary = restored.transport.to_dict()
	var failed_network_construction_before: Dictionary = restored.construction.to_dict()
	var failed_network_funds_before := restored.treasury_balance()
	var failed_network: Dictionary = restored.start_transport_session_network_project(
		"road", [first_tile], 10, city_grid
	)
	var failed_network_session_after := restored.transport_planning_session_snapshot()
	_check(not bool(failed_network.get("ok", false)), "invalid network command fails")
	_check(bool(failed_network.get("draft_retained", false)), "failed network command explicitly reports retained player draft")
	_check(not bool(failed_network.get("authoritative_changes_applied", true)), "failed network command explicitly reports no authoritative mutation")
	_check(
		str(failed_network_session_after.get("state", "")) == str(failed_network_session_before.get("state", ""))
		and Array(failed_network_session_after.get("station_refs", [])) == Array(failed_network_session_before.get("station_refs", []))
		and Array(failed_network_session_after.get("network_refs", [])) == Array(failed_network_session_before.get("network_refs", []))
		and Array(failed_network_session_after.get("route_refs", [])) == Array(failed_network_session_before.get("route_refs", [])),
		"failed network command changes only the editable draft"
	)
	_check(restored.transport.to_dict() == failed_network_transport_before, "failed network command leaves topology unchanged")
	_check(restored.construction.to_dict() == failed_network_construction_before, "failed network command leaves jobs unchanged")
	_check(restored.treasury_balance() == failed_network_funds_before, "failed network command leaves treasury unchanged")
	var road: Dictionary = restored.start_transport_session_network_project("road", road_tiles, 10, city_grid)
	_check(bool(road.get("ok", false)), "same session starts its guideway project")
	_check(str(restored.transport_planning_session_snapshot().get("id", "")) == session_id, "network placement does not recreate the session")
	var road_wait: Dictionary = restored.wait_for_transport_session_construction("network_placement")
	_check(bool(road_wait.get("ok", false)), "network construction can enter waiting state")
	var network_before_save: Dictionary = restored.transport_planning_session_snapshot()
	_check(restored.save_game(SAVE_PATH) == OK, "waiting network project saves in the same session")
	var network_restored = CoordinatorScript.new(3, 3)
	_check(network_restored.load_game(SAVE_PATH), "waiting network project reloads")
	var network_after_load: Dictionary = network_restored.transport_planning_session_snapshot()
	_check(str(network_after_load.get("id", "")) == session_id, "network reload retains the original session id")
	_check(
		_ref_ids(network_after_load.get("network_refs", []), "project_id") == _ref_ids(network_before_save.get("network_refs", []), "project_id"),
		"network project references survive save/load"
	)
	var restored_draft: Dictionary = network_after_load.get("network_draft", {})
	var expected_draft: Dictionary = network_before_save.get("network_draft", {})
	_check(
		str(restored_draft.get("kind", "")) == str(expected_draft.get("kind", ""))
		and int(restored_draft.get("worker_count", 0)) == int(expected_draft.get("worker_count", 0))
		and _integer_list(restored_draft.get("tile_ids", [])) == _integer_list(expected_draft.get("tile_ids", [])),
		"network draft survives save/load"
	)
	restored = network_restored
	restored.advance_days(_maximum_active_days(restored), {}, false)
	_check(str(restored.transport_planning_session_snapshot().get("state", "")) == "network_placement", "network completion resumes network placement")

	var depot_tile := _tile(restored, 1, 3)
	var depot: Dictionary = restored.start_transport_session_network_project("bus_depot", [depot_tile], 10, city_grid)
	_check(bool(depot.get("ok", false)), "same network phase can place its required depot")
	restored.advance_days(_maximum_active_days(restored), {}, false)
	var route_edit: Dictionary = restored.begin_transport_session_route_edit({
		"station_tile_ids": [first_tile, second_tile],
	})
	_check(bool(route_edit.get("ok", false)), "same session transitions to route edit")
	var failed_route_session_before := restored.transport_planning_session_snapshot()
	var failed_route_transport_before: Dictionary = restored.transport.to_dict()
	var failed_route_construction_before: Dictionary = restored.construction.to_dict()
	var failed_route_funds_before := restored.treasury_balance()
	var failed_route: Dictionary = restored.materialize_transport_session_route(
		[first_tile], 2, 8, 25, city_grid
	)
	var failed_route_session_after := restored.transport_planning_session_snapshot()
	_check(not bool(failed_route.get("ok", false)), "invalid route command fails")
	_check(bool(failed_route.get("draft_retained", false)), "failed route command explicitly reports retained player draft")
	_check(not bool(failed_route.get("authoritative_changes_applied", true)), "failed route command explicitly reports no authoritative mutation")
	_check(
		str(failed_route_session_after.get("state", "")) == str(failed_route_session_before.get("state", ""))
		and Array(failed_route_session_after.get("station_refs", [])) == Array(failed_route_session_before.get("station_refs", []))
		and Array(failed_route_session_after.get("network_refs", [])) == Array(failed_route_session_before.get("network_refs", []))
		and Array(failed_route_session_after.get("route_refs", [])) == Array(failed_route_session_before.get("route_refs", [])),
		"failed route command changes only the editable draft"
	)
	_check(restored.transport.to_dict() == failed_route_transport_before, "failed route command leaves topology unchanged")
	_check(restored.construction.to_dict() == failed_route_construction_before, "failed route command leaves jobs unchanged")
	_check(restored.treasury_balance() == failed_route_funds_before, "failed route command leaves treasury unchanged")
	var route: Dictionary = restored.materialize_transport_session_route(
		[first_tile, second_tile], 2, 8, 25, city_grid
	)
	_check(bool(route.get("ok", false)), "route edit materializes an operational route")
	_check(str(restored.transport_planning_session_snapshot().get("state", "")) == "materialized", "successful route marks session materialized")
	_check(Array(restored.transport_planning_session_snapshot().get("route_refs", [])).size() == 1, "materialized session stores only the authoritative route identity")
	var authoritative_planning: Dictionary = restored.transport_planning_session.to_dict()
	var authoritative_construction: Dictionary = restored.construction.to_dict()
	var authoritative_transport: Dictionary = restored.transport.to_dict()
	var authoritative_buildings: Dictionary = restored.session.state.buildings.duplicate(true)
	_check(
		bool(TransportPlanningSessionScript.validate_references(
			authoritative_planning, authoritative_construction, authoritative_transport, authoritative_buildings
		).get("valid", false)),
		"materialized session validates against authoritative jobs and topology"
	)
	var route_id := str(authoritative_planning.get("session", {}).get("route_refs", [""])[0])
	var cross_mode_transport := authoritative_transport.duplicate(true)
	cross_mode_transport["routes"][route_id]["mode"] = "train"
	_check(
		not bool(TransportPlanningSessionScript.validate_references(
			authoritative_planning, authoritative_construction, cross_mode_transport, authoritative_buildings
		).get("valid", false)),
		"cross-mode authoritative route reference fails closed"
	)
	var foreign_station_transport := authoritative_transport.duplicate(true)
	foreign_station_transport["routes"][route_id]["stop_ids"][0] = "station_outside_session"
	_check(
		not bool(TransportPlanningSessionScript.validate_references(
			authoritative_planning, authoritative_construction, foreign_station_transport, authoritative_buildings
		).get("valid", false)),
		"route cannot reference a station outside this session's completed station identities"
	)
	var closed: Dictionary = restored.close_transport_planning_session("player_done")
	_check(bool(closed.get("ok", false)) and str(closed.get("session", {}).get("state", "")) == "closed", "materialized session closes explicitly")
	var dangling_closed_planning: Dictionary = restored.transport_planning_session.to_dict()
	var dangling_closed_transport := authoritative_transport.duplicate(true)
	dangling_closed_transport["routes"].erase(route_id)
	_check(
		not bool(TransportPlanningSessionScript.validate_references(
			dangling_closed_planning, authoritative_construction, dangling_closed_transport, authoritative_buildings
		).get("valid", false)),
		"closed session still rejects a dangling route reference"
	)


func _test_schema_nine_migrates_inactive_and_schema_eleven_fails_closed() -> void:
	var source = CoordinatorScript.new(20_260_903, 500_000)
	source.call("_stash_subsystems")
	var legacy_envelope = source.session.make_envelope()
	var legacy_vertical: Dictionary = legacy_envelope.state.get("metadata", {}).get("vertical_slice", {}).duplicate(true)
	var layout3_fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT3_PRESERVATION_FIXTURE_PATH))
	var layout3_terrain: Dictionary = layout3_fixture.get("state", {}).get("metadata", {}).get("vertical_slice", {}).get("terrain", {}) if layout3_fixture is Dictionary else {}
	_check(not layout3_terrain.is_empty(), "schema 9 candidate has immutable layout 3 terrain")
	if layout3_terrain.is_empty():
		return
	legacy_vertical["schema_version"] = 9
	legacy_vertical["terrain"] = layout3_terrain.duplicate(true)
	legacy_vertical.erase("transport_planning_session")
	legacy_envelope.state["metadata"]["vertical_slice"] = legacy_vertical
	var migrated = CoordinatorScript.new(2, 2)
	_check(migrated.session.restore_envelope(legacy_envelope), "schema 9 migrates through the explicit session boundary")
	var migrated_vertical: Dictionary = migrated.session.state.metadata.get("vertical_slice", {})
	_check(int(migrated_vertical.get("schema_version", -1)) == SaveSchemaAuthorityScript.CURRENT_VERTICAL_SCHEMA_VERSION, "schema 9 migrates to the current authority schema")
	_check(int(migrated_vertical.get("terrain", {}).get("layout_version", -1)) == SaveSchemaAuthorityScript.CURRENT_TERRAIN_LAYOUT_VERSION, "schema 9 migrates to the current authority terrain layout")
	_check(str(migrated_vertical.get("terrain", {}).get("classification_provenance", "")) == CityTerrainMapScript.PROVENANCE_PRESERVED_LAYOUT_3, "schema 9 migration preserves layout 3 provenance")
	_check(str(migrated_vertical.get("transport_planning_session", {}).get("session", {}).get("state", "")) == "inactive", "schema 9 migration creates no active session")

	var corrupt = CoordinatorScript.new(20_260_904, 500_000)
	corrupt.call("_stash_subsystems")
	var corrupt_vertical: Dictionary = corrupt.session.state.metadata.get("vertical_slice", {}).duplicate(true)
	corrupt_vertical.erase("transport_planning_session")
	corrupt.session.state.metadata["vertical_slice"] = corrupt_vertical
	_check(corrupt.session.save_now("user://w4_corrupt_missing_session.json") == ERR_INVALID_DATA, "current schema missing session fails closed")
	corrupt.call("_stash_subsystems")
	corrupt_vertical = corrupt.session.state.metadata.get("vertical_slice", {}).duplicate(true)
	corrupt_vertical["transport_planning_session"]["session"] = {"state": "invented"}
	corrupt.session.state.metadata["vertical_slice"] = corrupt_vertical
	_check(corrupt.session.save_now("user://w4_corrupt_bad_session.json") == ERR_INVALID_DATA, "current schema malformed session fails closed")
	var corrupt_reference = CoordinatorScript.new(20_260_906, 500_000)
	corrupt_reference.terrain_map = CityTerrainMapScript.new()
	_check(bool(corrupt_reference.begin_transport_planning_session("公車站").get("ok", false)), "corrupt reference fixture begins session")
	_check(bool(corrupt_reference.place_transport_session_station(_tile(corrupt_reference, 5, 5), 5).get("ok", false)), "corrupt reference fixture starts station")
	corrupt_reference.call("_stash_subsystems")
	var reference_vertical: Dictionary = corrupt_reference.session.state.metadata.get("vertical_slice", {}).duplicate(true)
	reference_vertical["transport_planning_session"]["session"]["station_refs"][0]["job_id"] = "missing_job"
	corrupt_reference.session.state.metadata["vertical_slice"] = reference_vertical
	_check(corrupt_reference.session.save_now("user://w4_corrupt_missing_job_ref.json") == ERR_INVALID_DATA, "current schema dangling session job reference fails closed")
	_check(SaveSchemaAuthorityScript.validate_vertical_terrain_pair(SaveSchemaAuthorityScript.CURRENT_VERTICAL_SCHEMA_VERSION, SaveSchemaAuthorityScript.CURRENT_TERRAIN_LAYOUT_VERSION), "current authority schema remains paired with current terrain layout")


func _test_close_does_not_cancel_authoritative_construction() -> void:
	var coordinator = CoordinatorScript.new(20_260_905, 500_000)
	coordinator.terrain_map = CityTerrainMapScript.new()
	var tile_id := _tile(coordinator, 7, 7)
	_check(bool(coordinator.begin_transport_planning_session("公車站").get("ok", false)), "close fixture begins session")
	var started: Dictionary = coordinator.place_transport_session_station(tile_id, 10)
	_check(bool(started.get("ok", false)), "close fixture starts station construction")
	var closed: Dictionary = coordinator.cancel_transport_planning_session()
	_check(bool(closed.get("ok", false)), "cancelling planning succeeds while construction is active")
	coordinator.advance_days(_maximum_active_days(coordinator), {}, false)
	_check(not coordinator.get_building_by_tile(tile_id).is_empty(), "closing planning does not cancel or orphan authoritative construction")
	_check(str(coordinator.transport_planning_session_snapshot().get("state", "")) == "closed", "construction materialization does not reopen a closed session")


func _planning_snapshot_fixture() -> Dictionary:
	return {
		"schema_version": 2,
		"next_session_sequence": 2,
		"session": {
			"id": "transport_planning_000001",
			"state": "station_placement",
			"station_blueprint_name": "公車站",
			"station_blueprint_library_id": "fixture_bus_station",
			"mode": "bus",
			"station_refs": [],
			"network_refs": [],
			"route_refs": [],
			"network_draft": {},
			"route_draft": {},
			"resume_state": "",
			"closed_reason": "",
		},
	}


func _station_ref(job_id: String, tile_id: int, status: String) -> Dictionary:
	return {
		"job_id": job_id,
		"station_id": "station_%s" % job_id if status == "completed" else "",
		"anchor_tile_id": tile_id,
		"occupied_tile_ids": [tile_id],
		"status": status,
	}


func _network_ref(job_id: String, project_id: String, kind: String, status: String) -> Dictionary:
	return {
		"project_id": project_id,
		"job_id": job_id,
		"kind": kind,
		"status": status,
	}


func _maximum_active_days(coordinator) -> int:
	var result := 0
	for job_value: Variant in coordinator.construction.active_jobs():
		result = maxi(result, int((job_value as Dictionary).get("projected_remaining_days", 0)))
	return maxi(1, result)


func _all_refs_status(refs: Array, expected: String) -> bool:
	if refs.is_empty():
		return false
	for ref_value: Variant in refs:
		if not ref_value is Dictionary or str((ref_value as Dictionary).get("status", "")) != expected:
			return false
	return true


func _ref_ids(refs: Array, field_name: String) -> Array[String]:
	var result: Array[String] = []
	for ref_value: Variant in refs:
		if ref_value is Dictionary:
			result.append(str((ref_value as Dictionary).get(field_name, "")))
	return result


func _integer_list(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in values:
		result.append(int(value))
	return result


func _horizontal_tiles(coordinator, start_x: int, y: int, end_x: int) -> Array[int]:
	var result: Array[int] = []
	for x in range(start_x, end_x + 1):
		result.append(_tile(coordinator, x, y))
	return result


func _tile(coordinator, x: int, y: int) -> int:
	return int(coordinator.terrain_map.tile_id_for_coordinate(Vector2i(x, y)))


func _empty_city_grid(coordinator) -> Array:
	var result: Array = []
	result.resize(coordinator.terrain_map.cell_count())
	result.fill("")
	return result


func _cleanup() -> void:
	for relative_path: String in [
		SAVE_PATH,
		SAVE_PATH + ".bak",
		SAVE_PATH + ".tmp",
		"user://w4_corrupt_missing_session.json",
		"user://w4_corrupt_bad_session.json",
		"user://w4_corrupt_missing_job_ref.json",
	]:
		var absolute := ProjectSettings.globalize_path(relative_path)
		if FileAccess.file_exists(absolute):
			DirAccess.remove_absolute(absolute)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Transport planning session integration test failed: %s" % message)
