extends SceneTree

const ContentRegistry = preload("res://data/catalogs/content_registry.gd")

const COORDINATOR_PATH := "res://scripts/app/vertical_slice_coordinator.gd"
const TEST_SEED := 7_071_991
const TEST_FUNDS := 5_000_000
const TEST_SAVE_PATH := "res://tests/.vertical_slice_roundtrip.json"
const CITY_CONTEXT := {
	"economic_health": 80.0,
	"public_support": 90.0,
	"park_count": 0,
	"hospital_count": 0,
	"school_count": 0,
	"utility_fee": 120,
	"regional_support": {
		"north": 80,
		"south": 80,
		"east": 80,
		"west": 80,
	},
}

var _failed := false
var _checks := 0
var _coordinator_script: Script
var _long_simulation_ms := 0.0


func _initialize() -> void:
	_cleanup_test_save()
	_coordinator_script = ResourceLoader.load(COORDINATOR_PATH, "Script", ResourceLoader.CACHE_MODE_IGNORE) as Script
	_check(_coordinator_script != null and _coordinator_script.can_instantiate(), "vertical slice coordinator compiles and can instantiate")
	if _coordinator_script == null or not _coordinator_script.can_instantiate():
		quit(1)
		return
	_test_content_registry()
	_test_population_contract()
	_test_request_completion_fact()
	_test_build_and_demolish_flow()
	_test_demolition_financial_preflight()
	_test_demolition_durability_interlock()
	_test_population_building_lifecycle()
	_test_population_scrap_and_legacy_migration()
	_test_stale_core_population_reconcile()
	_test_justice_buildings_flow()
	_test_save_round_trip()
	_test_seed_reproducibility()
	_test_long_running_simulation()
	_cleanup_test_save()
	if not _failed:
		print("Mayor Simulator vertical slice test passed. Checks=%d SoakDays=3600 SoakMs=%.3f" % [
			_checks,
			_long_simulation_ms,
		])
	quit(1 if _failed else 0)


func _test_content_registry() -> void:
	var buildings: Dictionary = ContentRegistry.buildings_by_id()
	_check(
		buildings.size() == ContentRegistry.BUILDING_IDS.size(),
		"content registry exposes every canonical building id"
	)
	_check(buildings.has("court"), "content registry exposes the court")
	_check(buildings.has("oversight_office"), "content registry exposes the oversight office")
	var core_count := 0
	var seen_ids := {}
	for building_id: Variant in buildings.keys():
		var stable_id := str(building_id)
		_check(not stable_id.is_empty(), "building registry IDs are non-empty")
		_check(not seen_ids.has(stable_id), "building registry IDs are unique")
		seen_ids[stable_id] = true
		var definition = buildings[building_id]
		if bool(definition.core_acceptance):
			core_count += 1
	_check(core_count == 8, "eight core acceptance buildings are present")
	for required_id: String in [
		"residence", "factory", "hospital", "school", "park",
		"police_station", "fire_station", "city_hall",
	]:
		_check(buildings.has(required_id), "core building exists: %s" % required_id)


func _test_population_contract() -> void:
	var coordinator = _coordinator_script.new(TEST_SEED, TEST_FUNDS)
	var npc_ids: Array[String] = coordinator.population.sorted_npc_ids()
	_check(coordinator.population.population_count() == 300, "coordinator starts with 300 persistent NPCs")
	_check(npc_ids.size() == 300, "population index exposes 300 NPC IDs")
	_check(coordinator.session.state.npcs.size() == 300, "runtime CityState hydrates all 300 NPC records")
	_check(int(coordinator.session.state.metrics.get("population", -1)) == 300, "core population metric starts at 300")
	_check(coordinator.session.kernel.command_sequence == 3, "300-resident new game uses only the three metric commands")
	_check(coordinator.session.kernel.event_sequence == 3, "bulk NPC hydration emits no per-resident domain events")
	_check(coordinator.next_operation_sequence == 4, "bulk NPC hydration consumes no operation IDs")
	var seen := {}
	for npc_id: String in npc_ids:
		_check(not npc_id.is_empty(), "NPC IDs are non-empty")
		_check(not seen.has(npc_id), "NPC IDs are unique")
		seen[npc_id] = true
		_check(coordinator.population.get_record(npc_id) != null, "NPC record is queryable: %s" % npc_id)
	_check(coordinator.visible_npc_proxies(500).size() == 80, "visible NPC proxy pool remains capped at 80")
	_check_population_mirror(coordinator, 300, "initial population")


func _test_request_completion_fact() -> void:
	var coordinator = _coordinator_script.new(TEST_SEED + 30, TEST_FUNDS)
	var created: Array[Dictionary] = coordinator.refresh_requests(CITY_CONTEXT)
	_check(not created.is_empty(), "request fact fixture creates at least one resident request")
	if created.is_empty():
		return
	var request_id := str(created[0].get("request_id", ""))
	_check(coordinator.population.accept_request(request_id, coordinator.game_day()), "request fact fixture accepts the selected request")
	var completion_context: Dictionary = CITY_CONTEXT.duplicate(true)
	completion_context["park_count"] = 99
	completion_context["hospital_count"] = 99
	completion_context["school_count"] = 99
	completion_context["utility_fee"] = 0
	var completed_ids: Array[String] = coordinator.complete_requests(completion_context)
	_check(completed_ids.has(request_id), "accepted request completes when its authoritative condition is satisfied")
	var authoritative_request: Dictionary = coordinator.population.requests[request_id].to_dict()
	_check(str(authoritative_request.get("status", "")) == "completed", "authoritative request reaches completed status")
	_check(int(authoritative_request.get("completed_day", -1)) == coordinator.game_day(), "authoritative request records its completion day")
	var completed_fact: Dictionary = {}
	for record_variant in coordinator.session.state.event_book:
		var record: Dictionary = record_variant
		if str(record.get("fact_type", "")) == "npc_request_completed" and str(record.get("request_id", "")) == request_id:
			completed_fact = record
	_check(not completed_fact.is_empty(), "core event book records the completed request fact")
	_check(str(completed_fact.get("status", "")) == "completed", "completed request fact uses the authoritative completed status")
	_check(int(completed_fact.get("completed_day", -1)) == coordinator.game_day(), "completed request fact uses the authoritative completion day")


func _test_build_and_demolish_flow() -> void:
	var coordinator = _coordinator_script.new(TEST_SEED, TEST_FUNDS)
	var submitted: Dictionary = coordinator.submit_blueprint({
		"building_name": "公園",
		"material_id": "wood",
		"floors": 1,
		"size_tier": "small",
		"roof_color": "green",
		"wall_color": "cream",
		"decor_id": "flowers",
		"workers": 20,
	})
	_check(bool(submitted.get("ok", false)), "blueprint submission succeeds")
	if not bool(submitted.get("ok", false)):
		return
	var review: Dictionary = submitted["review"]
	_check(int(review["review_days"]) >= 2 and int(review["review_days"]) <= 7, "blueprint review lasts 2-7 days")
	var duplicate: Dictionary = coordinator.submit_blueprint({"building_name": "公園"})
	_check(not bool(duplicate.get("ok", false)) and str(duplicate.get("error", "")) == "blueprint_already_under_review", "duplicate blueprint submission is blocked while review is active")
	var pending_status: Dictionary = coordinator.blueprint_review_status("公園")
	_check(str(pending_status.get("status", "")) == "under_review", "blueprint exposes an under-review player status")
	_check(int(pending_status.get("remaining_days", 0)) == int(review["review_days"]), "player status exposes exact remaining review days")
	_check(int(pending_status.get("remaining_real_minutes", 0)) == int(review["review_days"]) * 2, "player status converts review days to real minutes")
	var review_events: Array[Dictionary] = coordinator.advance_days(int(review["review_days"]), CITY_CONTEXT)
	_check(_event_seen(review_events, "blueprint_approved"), "blueprint approval produces a UI event")
	_check(str(coordinator.construction.reviews[str(review["id"])]["status"]) == "approved", "blueprint reaches approved state")
	var approved_duplicate: Dictionary = coordinator.submit_blueprint({"building_name": "公園"})
	_check(bool(approved_duplicate.get("ok", false)), "an approved reusable blueprint does not block submission of a new custom version")
	_check(coordinator.approved_blueprints("公園").size() == 2, "starter and first player-approved park blueprints are both retained")
	_check(str(coordinator.active_blueprint_status("公園").get("source", "")) == "player", "newly approved custom blueprint becomes the active reusable version")

	var started: Dictionary = coordinator.start_approved_building("公園", 12, 20)
	_check(bool(started.get("ok", false)), "approved blueprint starts construction")
	if not bool(started.get("ok", false)):
		return
	_check(coordinator.get_building_by_tile(12).is_empty(), "tile remains empty while construction is active")
	var build_days := int(started["job"].get("projected_remaining_days", 0))
	_check(build_days > 0, "construction has a positive duration")
	var build_events: Array[Dictionary] = coordinator.advance_days(build_days, CITY_CONTEXT)
	_check(_event_seen(build_events, "building_completed"), "construction completion emits building_completed")
	var completed: Dictionary = coordinator.get_building_by_tile(12)
	_check(not completed.is_empty(), "completed building occupies its tile")
	_check(str(completed.get("building_name", "")) == "公園", "completed tile contains the requested building")

	var demolition_quote: Dictionary = coordinator.construction.estimate_job(completed.get("blueprint", {}), "demolish", 20)
	var expected_demolition_cost := int(demolition_quote.get("total_labor_cost", 0))
	var balance_before_demolition: int = int(coordinator.treasury_balance())
	var demolition_entries_before := _ledger_entries_for_reason(coordinator, "construction.demolition").size()
	var demolition: Dictionary = coordinator.start_demolition(12, 20)
	_check(bool(demolition.get("ok", false)), "demolition starts for an occupied tile")
	if not bool(demolition.get("ok", false)):
		return
	_check(int(demolition.get("total_cost", -1)) == expected_demolition_cost, "successful demolition charges the preflight quote")
	_check(coordinator.treasury_balance() == balance_before_demolition - expected_demolition_cost, "successful demolition deducts its total cost exactly once at start")
	var demolition_entries_after_start: Array[Dictionary] = _ledger_entries_for_reason(coordinator, "construction.demolition")
	_check(demolition_entries_after_start.size() == demolition_entries_before + 1, "successful demolition creates exactly one demolition ledger entry")
	if not demolition_entries_after_start.is_empty():
		var demolition_entry: Dictionary = demolition_entries_after_start.back()
		_check(int(demolition_entry.get("amount", 0)) == -expected_demolition_cost, "demolition ledger entry matches the quoted cost")
		_check(str(demolition_entry.get("source_id", "")) == str(demolition.get("job", {}).get("id", "")), "demolition ledger entry is tied to the created job")
	_check(not coordinator.get_building_by_tile(12).is_empty(), "building remains on tile during demolition")
	_check(str(coordinator.get_building_by_tile(12).get("status", "")) == "demolition", "building is marked as under demolition")
	var balance_after_demolition_start: int = int(coordinator.treasury_balance())
	var demolition_days := int(demolition["job"].get("projected_remaining_days", 0))
	_check(demolition_days > 0, "demolition has a positive duration")
	var demolition_events: Array[Dictionary] = coordinator.advance_days(demolition_days, CITY_CONTEXT)
	_check(_event_seen(demolition_events, "demolition_completed"), "demolition completion emits demolition_completed")
	_check(coordinator.treasury_balance() == balance_after_demolition_start, "demolition completion does not charge labor a second time")
	_check(_ledger_entries_for_reason(coordinator, "construction.demolition").size() == demolition_entries_before + 1, "demolition keeps exactly one ledger entry after completion")
	_check(coordinator.get_building_by_tile(12).is_empty(), "demolition completion clears the tile")
	_check(coordinator.construction.available_workers() == 20, "shared construction workers return after demolition")


func _test_demolition_financial_preflight() -> void:
	var coordinator = _coordinator_script.new(TEST_SEED + 31, 0)
	coordinator.register_existing_building(16, "公園")
	var jobs_before: Dictionary = coordinator.construction.jobs.duplicate(true)
	var sequence_before: int = coordinator.construction.next_job_sequence
	var balance_before: int = int(coordinator.treasury_balance())
	var ledger_before: Array[Dictionary] = coordinator.session.state.ledger.get_entries()
	var hash_before: String = str(coordinator.deterministic_hash())
	for attempt in range(3):
		var rejected: Dictionary = coordinator.start_demolition(16, 5)
		_check(not bool(rejected.get("ok", false)) and str(rejected.get("error", "")) == "insufficient_treasury", "zero-fund demolition attempt %d is rejected before scheduling" % (attempt + 1))
		_check(int(rejected.get("required", 0)) > 0, "zero-fund demolition attempt %d returns a positive quote" % (attempt + 1))
		_check(coordinator.construction.jobs == jobs_before, "zero-fund demolition attempt %d does not insert a cancelled job" % (attempt + 1))
		_check(coordinator.construction.next_job_sequence == sequence_before, "zero-fund demolition attempt %d does not consume a job sequence" % (attempt + 1))
		_check(coordinator.treasury_balance() == balance_before, "zero-fund demolition attempt %d does not change treasury" % (attempt + 1))
		_check(coordinator.session.state.ledger.get_entries() == ledger_before, "zero-fund demolition attempt %d does not append a ledger entry" % (attempt + 1))
		_check(coordinator.deterministic_hash() == hash_before, "zero-fund demolition attempt %d leaves the persisted state hash unchanged" % (attempt + 1))


func _test_demolition_durability_interlock() -> void:
	var coordinator = _coordinator_script.new(TEST_SEED + 32, TEST_FUNDS)
	var baseline_population: int = coordinator.population.sorted_npc_ids().size()
	var residence_definition = ContentRegistry.buildings_by_id().get("residence")
	_check(residence_definition != null, "demolition durability fixture resolves the residence definition")
	if residence_definition == null:
		return
	var building: Dictionary = coordinator.register_existing_building(
		17, str(residence_definition.display_name)
	)
	_check(not building.is_empty(), "demolition durability fixture registers a populated building")
	if building.is_empty():
		return
	var building_id := str(building.get("building_id", ""))
	var resident_ids: Array = Array(building.get("resident_ids", [])).duplicate()
	var population_during_demolition: int = coordinator.population.sorted_npc_ids().size()
	var demolition: Dictionary = coordinator.start_demolition(17, 1)
	_check(bool(demolition.get("ok", false)), "long demolition starts before durability interlock test")
	if not bool(demolition.get("ok", false)):
		return
	var job_id := str(demolition.get("job", {}).get("id", ""))
	var projected_days := int(demolition.get("job", {}).get("projected_remaining_days", 0))
	_check(projected_days > 7, "one-worker demolition spans the weekly durability boundary")
	if projected_days <= 7:
		return
	var repair_during_demolition: Dictionary = coordinator.repair_building(17)
	_check(not bool(repair_during_demolition.get("ok", false)) and str(repair_during_demolition.get("error", "")) == "demolition_in_progress", "repair cannot break the demolition status/job invariant")
	coordinator.advance_days(6, CITY_CONTEXT, false)
	coordinator.drain_ui_events()

	var damage: Dictionary = coordinator.durability.apply_damage(
		building_id,
		61,
		"test.demolition_durability_tick",
		coordinator.game_day() + 1
	)
	_check(bool(damage.get("ok", false)), "durability tick can reduce a building below the scrap threshold during demolition")
	if not bool(damage.get("ok", false)):
		return
	coordinator._handle_durability_fact(damage["event"])
	var during: Dictionary = coordinator.get_building_by_tile(17)
	_check(str(during.get("status", "")) == "demolition", "durability tick cannot overwrite an active demolition marker")
	_check(int(during.get("durability", 100)) == 39, "durability still updates while demolition owns the building")
	_check(Array(during.get("resident_ids", [])) == resident_ids, "suppressed scrap does not evict residents before demolition completes")
	_check(coordinator.population.sorted_npc_ids().size() == population_during_demolition, "suppressed scrap leaves authoritative population unchanged")
	_check(coordinator.construction.jobs.has(job_id), "durability tick preserves the subsystem demolition job")
	_check(coordinator.session.state.construction_jobs.has(job_id), "durability tick preserves the core demolition-job mirror")
	if coordinator.construction.jobs.has(job_id) and coordinator.session.state.construction_jobs.has(job_id):
		var subsystem_job: Dictionary = coordinator.construction.jobs[job_id]
		var core_job: Dictionary = coordinator.session.state.construction_jobs[job_id]
		var normalized_core_job := core_job.duplicate(true)
		var core_job_id_matches := str(normalized_core_job.get("job_id", "")) == job_id
		normalized_core_job.erase("job_id")
		_check(
			core_job_id_matches and subsystem_job == normalized_core_job,
			"durability tick keeps subsystem and core job records identical: subsystem=%s core=%s" % [
				JSON.stringify(subsystem_job), JSON.stringify(core_job),
			]
		)
	var durability_ui_events: Array[Dictionary] = coordinator.drain_ui_events()
	_check(_event_count(durability_ui_events, "building_scrapped") == 0, "durability tick emits no scrap UI side effect during demolition")
	_check(_event_count(coordinator.session.state.event_book, "building_scrapped") == 0, "durability tick records damage instead of a false scrap fact during demolition")

	var remaining_days := int(coordinator.construction.jobs.get(job_id, {}).get("projected_remaining_days", 0))
	_check(remaining_days > 0, "demolition remains active after the injected durability tick")
	var completion_events: Array[Dictionary] = coordinator.advance_days(remaining_days, CITY_CONTEXT, false)
	_check(_event_count(completion_events, "demolition_completed") == 1, "interlocked demolition completes exactly once")
	_check(coordinator.get_building_by_tile(17).is_empty(), "interlocked demolition removes the building at completion")
	_check(not coordinator.session.state.construction_jobs.has(job_id), "completion removes the core demolition-job mirror")
	_check(str(coordinator.construction.jobs.get(job_id, {}).get("status", "")) == "completed", "completion retains one historical subsystem job")
	_check(coordinator.population.sorted_npc_ids().size() == baseline_population, "residents are removed once at demolition completion")
	var follow_up_events: Array[Dictionary] = coordinator.advance_days(1, CITY_CONTEXT, false)
	_check(_event_count(follow_up_events, "demolition_completed") == 0, "completed demolition cannot emit a second completion")


func _test_population_building_lifecycle() -> void:
	var coordinator = _coordinator_script.new(TEST_SEED + 20, TEST_FUNDS)
	var baseline_ids: Array[String] = coordinator.population.sorted_npc_ids()
	var submitted: Dictionary = coordinator.submit_blueprint({
		"building_name": "住宅",
		"material_id": "brick",
		"floors": 2,
		"size_tier": "medium",
		"workers": 20,
	})
	_check(bool(submitted.get("ok", false)), "residence blueprint can enter review")
	if not bool(submitted.get("ok", false)):
		return
	var review: Dictionary = submitted["review"]
	coordinator.advance_days(int(review.get("review_days", 0)), CITY_CONTEXT)
	var started: Dictionary = coordinator.start_approved_building("住宅", 13, 20)
	_check(bool(started.get("ok", false)), "residence construction can start")
	if not bool(started.get("ok", false)):
		return
	coordinator.advance_days(int(started.get("job", {}).get("projected_remaining_days", 0)), CITY_CONTEXT)
	var completed: Dictionary = coordinator.get_building_by_tile(13)
	var resident_ids := PackedStringArray(completed.get("resident_ids", []))
	_check(resident_ids.size() == 28, "residence completion stores all 28 added resident IDs")
	_check(int(completed.get("population_delta", 0)) == 28, "residence completion records its actual population delta")
	_check_population_mirror(coordinator, 328, "completed residence")
	for resident_id: String in resident_ids:
		_check(coordinator.population.get_record(resident_id) != null, "completed residence owns canonical resident: %s" % resident_id)

	var demolition: Dictionary = coordinator.start_demolition(13, 20)
	_check(bool(demolition.get("ok", false)), "populated residence demolition can start")
	if not bool(demolition.get("ok", false)):
		return
	coordinator.advance_days(int(demolition.get("job", {}).get("projected_remaining_days", 0)), CITY_CONTEXT)
	_check_population_mirror(coordinator, 300, "demolished residence")
	for baseline_id: String in baseline_ids:
		_check(coordinator.population.get_record(baseline_id) != null, "residence demolition preserves baseline resident: %s" % baseline_id)


func _test_population_scrap_and_legacy_migration() -> void:
	var scrapped = _coordinator_script.new(TEST_SEED + 21, TEST_FUNDS)
	var scrapped_building: Dictionary = scrapped.register_existing_building(14, "住宅")
	_check_population_mirror(scrapped, 328, "seeded residence before scrapping")
	var damage: Dictionary = scrapped.durability.apply_damage(
		str(scrapped_building.get("building_id", "")),
		61,
		"test.force_scrap",
		scrapped.game_day()
	)
	_check(bool(damage.get("ok", false)), "residence can enter scrapped state")
	if bool(damage.get("ok", false)):
		scrapped._handle_durability_fact(damage["event"])
	var scrapped_record: Dictionary = scrapped.get_building_by_tile(14)
	_check(str(scrapped_record.get("status", "")) == "scrapped", "scrapped residence status reaches core state")
	_check(PackedStringArray(scrapped_record.get("resident_ids", [])).is_empty(), "scrapped residence clears its resident ownership list")
	_check_population_mirror(scrapped, 300, "scrapped residence")
	var scrap_demolition: Dictionary = scrapped.start_demolition(14, 20)
	_check(bool(scrap_demolition.get("ok", false)), "scrapped residence can be demolished")
	if bool(scrap_demolition.get("ok", false)):
		scrapped.advance_days(int(scrap_demolition.get("job", {}).get("projected_remaining_days", 0)), CITY_CONTEXT)
	_check_population_mirror(scrapped, 300, "scrapped residence after demolition")

	var legacy = _coordinator_script.new(TEST_SEED + 22, TEST_FUNDS)
	var baseline_ids: Array[String] = legacy.population.sorted_npc_ids()
	var legacy_building: Dictionary = legacy.register_existing_building(15, "住宅")
	var originally_assigned := PackedStringArray(legacy_building.get("resident_ids", []))
	legacy.population.remove_residents_by_id(originally_assigned, legacy.game_day(), "test.legacy_setup")
	legacy._sync_population_to_core("test.legacy_setup")
	legacy_building.erase("resident_ids")
	legacy_building.erase("population_delta")
	legacy._upsert_building(legacy_building, "test.legacy_building")
	_check_population_mirror(legacy, 300, "legacy residence without resident IDs")
	var legacy_demolition: Dictionary = legacy.start_demolition(15, 20)
	_check(bool(legacy_demolition.get("ok", false)), "legacy residence demolition can start")
	if bool(legacy_demolition.get("ok", false)):
		legacy.advance_days(int(legacy_demolition.get("job", {}).get("projected_remaining_days", 0)), CITY_CONTEXT)
	_check_population_mirror(legacy, 300, "legacy residence after demolition")
	for baseline_id: String in baseline_ids:
		_check(legacy.population.get_record(baseline_id) != null, "legacy demolition never removes baseline resident: %s" % baseline_id)


func _test_stale_core_population_reconcile() -> void:
	var coordinator = _coordinator_script.new(TEST_SEED + 23, TEST_FUNDS)
	coordinator.session.submit_command("upsert_npc", {
		"npc_id": "npc_stale_core_only",
		"record": {"npc_id": "npc_stale_core_only", "display_name": "stale"},
		"reason_tag": "test.inject_stale_core_npc",
	}, "test_inject_stale_core_npc")
	_check(coordinator.session.state.npcs.size() == 301, "test fixture injects one stale core-only NPC")
	coordinator._sync_population_to_core("test.reconcile_stale_core_npc")
	_check(not coordinator.session.state.npcs.has("npc_stale_core_only"), "population reconcile removes stale core-only NPC")
	_check_population_mirror(coordinator, 300, "stale core reconciliation")


func _test_justice_buildings_flow() -> void:
	var coordinator = _coordinator_script.new(TEST_SEED + 1, TEST_FUNDS)
	var building_names := ["法院", "監察所"]
	for index: int in range(building_names.size()):
		var building_name: String = building_names[index]
		var submitted: Dictionary = coordinator.submit_blueprint({
			"building_name": building_name,
			"material_id": "brick",
			"floors": 2,
			"size_tier": "medium",
			"roof_color": "blue",
			"wall_color": "white",
			"decor_id": "flags",
			"workers": 20,
		})
		_check(bool(submitted.get("ok", false)), "%s blueprint submission succeeds" % building_name)
		if not bool(submitted.get("ok", false)):
			continue
		var review: Dictionary = submitted["review"]
		coordinator.advance_days(int(review["review_days"]), CITY_CONTEXT)
		var build_tile := 22 + index
		var started: Dictionary = coordinator.start_approved_building(building_name, build_tile, 20)
		_check(bool(started.get("ok", false)), "%s construction starts" % building_name)
		if not bool(started.get("ok", false)):
			continue
		coordinator.advance_days(int(started["job"].get("projected_remaining_days", 0)), CITY_CONTEXT)
		var completed: Dictionary = coordinator.get_building_by_tile(build_tile)
		_check(str(completed.get("building_name", "")) == building_name, "%s can be completed on the city map" % building_name)


func _test_save_round_trip() -> void:
	var source = _coordinator_script.new(TEST_SEED, TEST_FUNDS)
	var source_building: Dictionary = source.register_existing_building(3, "住宅", {"wall_color": "white"})
	var resident_ids_before := PackedStringArray(source_building.get("resident_ids", []))
	_check(resident_ids_before.size() == 28, "save fixture residence owns 28 residents")
	_check_population_mirror(source, 328, "save fixture residence")
	source.set_maintenance_payment(false)
	source.refresh_requests(CITY_CONTEXT)
	source.advance_days(45, CITY_CONTEXT)
	var balance_before: int = int(source.treasury_balance())
	var date_before: Dictionary = source.current_date()
	var population_hash_before: String = source.population.stable_hash()
	_check(source.save_game(TEST_SAVE_PATH) == OK, "versioned snapshot saves atomically")
	var persisted_state: Dictionary = source.session.make_envelope().state
	_check(not persisted_state.has("npcs"), "save JSON omits the runtime CityState NPC mirror")
	_check(Array(persisted_state.get("metadata", {}).get("vertical_slice", {}).get("population", {}).get("records", [])).size() == 328, "save JSON keeps all records under canonical population only")
	var hash_before: String = source.deterministic_hash()
	var operation_sequence_before: int = source.next_operation_sequence
	var event_sequence_before: int = source.session.kernel.event_sequence

	var restored = _coordinator_script.new(123, 1)
	_check(restored.load_game(TEST_SAVE_PATH), "saved vertical slice loads")
	var hash_after: String = restored.deterministic_hash()
	_check(hash_before == hash_after, "save round-trip preserves deterministic coordinator hash")
	_check(restored.next_operation_sequence == operation_sequence_before, "load reconciliation does not add operation IDs when population is already equivalent")
	_check(restored.session.kernel.event_sequence == event_sequence_before, "load reconciliation does not emit events when population is already equivalent")
	_check(restored.treasury_balance() == balance_before, "save round-trip preserves treasury")
	_check(restored.current_date() == date_before, "save round-trip preserves game date")
	_check(restored.population.population_count() == 328, "save round-trip preserves building-added NPCs")
	_check(restored.population.stable_hash() == population_hash_before, "save round-trip preserves population records")
	var restored_building: Dictionary = restored.get_building_by_tile(3)
	_check(str(restored_building.get("building_name", "")) == "住宅", "save round-trip preserves buildings")
	_check(PackedStringArray(restored_building.get("resident_ids", [])) == resident_ids_before, "save round-trip preserves exact building resident ownership")
	_check_population_mirror(restored, 328, "restored residence")
	var idempotent_operation_sequence: int = restored.next_operation_sequence
	var idempotent_event_sequence: int = restored.session.kernel.event_sequence
	restored._sync_population_to_core("test.idempotent_reconcile")
	_check(restored.next_operation_sequence == idempotent_operation_sequence, "repeated population reconciliation is operation-idempotent")
	_check(restored.session.kernel.event_sequence == idempotent_event_sequence, "repeated population reconciliation is event-idempotent")
	_check(not restored.maintenance_payment_enabled, "save round-trip preserves maintenance preference")


func _test_seed_reproducibility() -> void:
	var first = _coordinator_script.new(TEST_SEED, TEST_FUNDS)
	var second = _coordinator_script.new(TEST_SEED, TEST_FUNDS)
	_check(first.deterministic_hash() == second.deterministic_hash(), "same seed starts from identical state")
	var first_submission: Dictionary = first.submit_blueprint({
		"building_name": "學校", "material_id": "brick", "floors": 2,
		"size_tier": "medium", "decor_id": "trees", "workers": 10,
	})
	var second_submission: Dictionary = second.submit_blueprint({
		"building_name": "學校", "material_id": "brick", "floors": 2,
		"size_tier": "medium", "decor_id": "trees", "workers": 10,
	})
	_check(first_submission == second_submission, "same seed produces identical blueprint review")
	var review_days := int(first_submission.get("review", {}).get("review_days", 0))
	first.advance_days(review_days, CITY_CONTEXT)
	second.advance_days(review_days, CITY_CONTEXT)
	var first_start: Dictionary = first.start_approved_building("學校", 8, 10)
	var second_start: Dictionary = second.start_approved_building("學校", 8, 10)
	_check(first_start == second_start, "same commands produce identical construction jobs")
	var build_days := int(first_start.get("job", {}).get("projected_remaining_days", 0))
	first.advance_days(build_days, CITY_CONTEXT)
	second.advance_days(build_days, CITY_CONTEXT)
	_check(first.deterministic_hash() == second.deterministic_hash(), "same seed and command stream replay identically")


func _test_long_running_simulation() -> void:
	var coordinator = _coordinator_script.new(31_415_926, TEST_FUNDS)
	coordinator.register_existing_building(0, "市政府")
	var starting_ids: Array[String] = coordinator.population.sorted_npc_ids()
	var first_id := starting_ids[0]
	var starting_age: int = int(coordinator.population.get_record(first_id).age)
	var soak_started_usec := Time.get_ticks_usec()
	var elapsed_events: Array[Dictionary] = coordinator.advance_days(3_600, CITY_CONTEXT)
	_long_simulation_ms = float(Time.get_ticks_usec() - soak_started_usec) / 1000.0
	_check(coordinator.game_day() == 3_600, "ten game years advance without a non-terminating event")
	_check(_long_simulation_ms <= 30_000.0, "ten-year deterministic simulation completes within the 30-second acceptance ceiling")
	_check(int(coordinator.current_date()["year"]) == 11, "calendar reaches year 11 after ten elapsed years")
	_check(coordinator.population.population_count() == 300, "long simulation retains the intended population")
	var ending_ids: Array[String] = coordinator.population.sorted_npc_ids()
	var unique_ids := {}
	for npc_id: String in ending_ids:
		unique_ids[npc_id] = true
	_check(unique_ids.size() == ending_ids.size(), "long simulation introduces no duplicate NPC IDs")
	_check(ending_ids == starting_ids, "long simulation preserves stable NPC identity")
	_check(coordinator.population.get_record(first_id).age == starting_age + 10, "NPC ages advance once per game year")
	_check(elapsed_events.size() < 1_000, "long simulation UI event queue remains bounded")
	_check(coordinator.treasury_balance() >= 0, "long simulation treasury never becomes negative")
	for metric_name: Variant in coordinator.session.state.metrics.keys():
		var metric_value: Variant = coordinator.session.state.metrics[metric_name]
		if metric_value is int or metric_value is float:
			_check(is_finite(float(metric_value)), "long simulation keeps numeric metric finite: %s" % str(metric_name))


func _event_seen(events: Array[Dictionary], event_type: String) -> bool:
	for event: Dictionary in events:
		if str(event.get("type", "")) == event_type:
			return true
	return false


func _event_count(events: Array[Dictionary], event_type: String) -> int:
	var count := 0
	for event: Dictionary in events:
		if str(event.get("type", "")) == event_type:
			count += 1
	return count


func _ledger_entries_for_reason(coordinator, reason_tag: String) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for entry_variant in coordinator.session.state.ledger.get_entries():
		var entry: Dictionary = entry_variant
		if str(entry.get("reason_tag", "")) == reason_tag:
			matches.append(entry)
	return matches


func _check_population_mirror(coordinator, expected_count: int, label: String) -> void:
	var population_ids: Array[String] = coordinator.population.sorted_npc_ids()
	var core_ids: Array[String] = []
	for core_id: Variant in coordinator.session.state.npcs.keys():
		core_ids.append(str(core_id))
	core_ids.sort()
	_check(coordinator.population.population_count() == expected_count, "%s canonical population count" % label)
	_check(int(coordinator.session.state.metrics.get("population", -1)) == expected_count, "%s core population metric" % label)
	_check(coordinator.session.state.npcs.size() == expected_count, "%s core NPC record count" % label)
	_check(core_ids == population_ids, "%s core and canonical NPC IDs match" % label)
	for npc_id: String in population_ids:
		_check(
			coordinator.session.state.npcs.get(npc_id, {}) == coordinator.population.get_record(npc_id).to_dict(),
			"%s runtime and canonical NPC record match: %s" % [label, npc_id]
		)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Vertical slice test failed: %s" % label)


func _cleanup_test_save() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	for suffix: String in ["", ".tmp", ".bak"]:
		var candidate := absolute_path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)
