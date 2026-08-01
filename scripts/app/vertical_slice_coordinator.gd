class_name VerticalSliceCoordinator
extends RefCounted

signal changed(view_model: Dictionary)
signal ui_event(event: Dictionary)

const GameSessionScript = preload("res://scripts/core/game_session.gd")
const ContentRegistry = preload("res://data/catalogs/content_registry.gd")
const ConstructionSystemScript = preload("res://scripts/systems/city/construction_system.gd")
const DurabilitySystemScript = preload("res://scripts/systems/city/durability_system.gd")
const GovernanceSystemScript = preload("res://scripts/systems/governance/governance_system.gd")
const PopulationSystemScript = preload("res://scripts/systems/population/population_system.gd")
const BlueprintLibraryServiceScript = preload("res://scripts/app/blueprint_library_service.gd")
const VerticalSliceViewModelAssemblerScript = preload("res://scripts/app/vertical_slice_view_model_assembler.gd")
const CityTerrainMapScript = preload("res://scripts/world/city_terrain_map.gd")

const DEFAULT_SEED := 20_260_715
const DEFAULT_INITIAL_FUNDS := 250_000
const GAME_DAY_LENGTH_SECONDS := 120.0
const SAVE_PATH := "user://mayor_simulator/vertical_slice_autosave.json"
const TERRAIN_FLATTEN_COSTS := {
	"trees": 300,
	"hill_cliff": 600,
	"river_lake": 900,
	"road_path": 500,
	"rail_track": 700,
}

var session
var construction
var durability
var governance
var population
var terrain_map
var building_definitions: Dictionary = {}
var maintenance_payment_enabled := true
var selected_npc_id := ""
var selected_request_id := ""
var blueprint_library_service = BlueprintLibraryServiceScript.new()
var next_blueprint_sequence: int:
	get:
		return blueprint_library_service.next_blueprint_sequence
	set(value):
		blueprint_library_service.next_blueprint_sequence = value
var blueprint_library: Dictionary:
	get:
		return blueprint_library_service.blueprint_library
	set(value):
		blueprint_library_service.blueprint_library = value
var active_blueprint_by_building: Dictionary:
	get:
		return blueprint_library_service.active_blueprint_by_building
	set(value):
		blueprint_library_service.active_blueprint_by_building = value
var next_building_sequence := 1
var next_operation_sequence := 1
var last_save_message := "尚未儲存"
var last_city_context: Dictionary = {}
var player_shell_state: Dictionary = {}
var save_path: String = SAVE_PATH
var _queued_ui_events: Array[Dictionary] = []
var _terminal_failure_event_reason: String = ""

func _init(seed: int = DEFAULT_SEED, initial_funds: int = DEFAULT_INITIAL_FUNDS) -> void:
	new_game(seed, initial_funds)

func new_game(seed: int = DEFAULT_SEED, initial_funds: int = DEFAULT_INITIAL_FUNDS) -> void:
	session = GameSessionScript.new(seed, initial_funds)
	session.clock.day_length_seconds = GAME_DAY_LENGTH_SECONDS
	session.clock.paused = false
	construction = ConstructionSystemScript.new(seed)
	durability = DurabilitySystemScript.new()
	governance = GovernanceSystemScript.new(seed)
	population = PopulationSystemScript.new()
	population.initialize(300, seed)
	terrain_map = CityTerrainMapScript.new()
	terrain_map.apply_default_city_layout()
	building_definitions = ContentRegistry.buildings_by_id()
	blueprint_library_service.reset(building_definitions)
	maintenance_payment_enabled = true
	selected_npc_id = ""
	selected_request_id = ""
	next_building_sequence = 1
	next_operation_sequence = 1
	last_city_context = {}
	player_shell_state = {}
	_queued_ui_events.clear()
	_terminal_failure_event_reason = ""
	_set_metric("population", population.population_count(), "population.initialized")
	_set_metric("municipal_trust", governance.municipal_trust, "governance.initialized")
	_set_metric("grievance", governance.grievance, "governance.initialized")
	for npc_id: String in population.sorted_npc_ids():
		session.submit_command("upsert_npc", {
			"npc_id": npc_id,
			"record": population.get_record(npc_id).to_dict(),
			"reason_tag": "population.initialized"
		}, _operation_id("npc_seed"))
	_emit_changed()

func process_frame(delta_seconds: float, city_context: Dictionary = {}, autosave: bool = true) -> Array[Dictionary]:
	if _seal_terminal_failure():
		return drain_ui_events()
	var elapsed_days: int = int(session.clock.consume_frame(delta_seconds))
	if elapsed_days <= 0:
		return []
	return advance_days(elapsed_days, city_context, autosave)

func set_time_paused(paused: bool) -> void:
	session.clock.paused = true if _seal_terminal_failure() else paused

func is_time_paused() -> bool:
	return bool(session.clock.paused)

func advance_days(days: int, city_context: Dictionary = {}, autosave: bool = true) -> Array[Dictionary]:
	if _seal_terminal_failure():
		return drain_ui_events()
	if not city_context.is_empty():
		last_city_context = city_context.duplicate(true)
	var resolved_context: Dictionary = last_city_context.duplicate(true)
	for _index in range(maxi(0, days)):
		_advance_one_day(resolved_context, autosave)
		if _seal_terminal_failure():
			break
	_emit_changed()
	return drain_ui_events()

func submit_blueprint(payload: Dictionary) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	var display_name := str(payload.get("building_name", ""))
	var definition = _definition_for_name(display_name)
	if definition == null:
		return {"ok": false, "error": "building_definition_not_found"}
	for review_variant in construction.reviews.values():
		var existing_review: Dictionary = review_variant
		if str(existing_review.get("blueprint", {}).get("building_id", "")) != String(definition.id):
			continue
		match str(existing_review.get("status", "")):
			"under_review":
				return {"ok": false, "error": "blueprint_already_under_review"}
	var blueprint: Dictionary = blueprint_library_service.create_submission_blueprint(payload, definition)
	var result: Dictionary = construction.submit_blueprint(blueprint, game_day(), "build")
	if bool(result.get("ok", false)):
		_record_fact({
			"type": "blueprint_submitted",
			"subject_id": str(result["review"]["id"]),
			"game_day": game_day(),
			"reason_tag": "construction.blueprint_review",
			"payload": result["review"]
		})
		_push_ui_event("blueprint_submitted", {
			"building_name": display_name,
			"review": result["review"]
		})
	_emit_changed()
	return result


func blueprint_review_status(display_name: String) -> Dictionary:
	var definition = _definition_for_name(display_name)
	if definition == null:
		return {"exists": false, "status": "none"}
	var latest: Dictionary = {}
	for review_variant in construction.reviews.values():
		var review: Dictionary = review_variant
		if str(review.get("blueprint", {}).get("building_id", "")) != String(definition.id):
			continue
		if latest.is_empty() or int(review.get("sequence", 0)) > int(latest.get("sequence", 0)):
			latest = review
	if latest.is_empty():
		return active_blueprint_status(display_name)
	if str(latest.get("status", "")) not in ["under_review", "rejected"]:
		var active := active_blueprint_status(display_name)
		if bool(active.get("exists", false)):
			return active
	var result: Dictionary = latest.duplicate(true)
	result["exists"] = true
	result["building_name"] = display_name
	result["remaining_days"] = maxi(0, int(latest.get("decision_day", game_day())) - game_day())
	result["remaining_real_minutes"] = int(result["remaining_days"]) * 2
	return result


func approved_blueprints(display_name: String) -> Array[Dictionary]:
	var definition = _definition_for_name(display_name)
	if definition == null:
		return []
	return blueprint_library_service.approved_blueprints(String(definition.id))


func active_blueprint_status(display_name: String) -> Dictionary:
	var definition = _definition_for_name(display_name)
	if definition == null:
		return {"exists": false, "status": "none"}
	return blueprint_library_service.active_blueprint_status(
		String(definition.id),
		display_name,
		not governance.has_failed()
	)


func select_approved_blueprint(display_name: String, library_id: String) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	var definition = _definition_for_name(display_name)
	if definition == null:
		return {"ok": false, "error": "blueprint_not_found"}
	var result: Dictionary = blueprint_library_service.select_approved_blueprint(String(definition.id), library_id)
	if not bool(result.get("ok", false)):
		return result
	_emit_changed()
	return result


func has_approved_blueprint(display_name: String) -> bool:
	return bool(active_blueprint_status(display_name).get("exists", false))


func placement_quote(display_name: String, worker_count: int = -1) -> Dictionary:
	var review: Dictionary = active_blueprint_status(display_name)
	if not bool(review.get("exists", false)):
		return {"ok": false, "error": "blueprint_not_found"}
	var blueprint: Dictionary = review.get("blueprint", {})
	if blueprint.is_empty():
		return {"ok": false, "error": "blueprint_not_found"}
	var resolved_workers := worker_count
	if resolved_workers <= 0:
		resolved_workers = int(blueprint.get("requested_workers", 5))
	resolved_workers = clampi(resolved_workers, 1, ConstructionSystemScript.MAX_WORKERS)
	var estimate: Dictionary = construction.estimate_job(blueprint, "build", resolved_workers)
	var base_cost := int(blueprint.get("base_cost", 0))
	var labor_cost := int(estimate.get("total_labor_cost", 0))
	var total_cost := base_cost + labor_cost
	return {
		"ok": true,
		"status": str(review.get("status", "none")),
		"review_id": str(review.get("id", "")),
		"library_id": str(review.get("library_id", review.get("id", ""))),
		"blueprint_title": str(review.get("title", "核准藍圖")),
		"building_name": display_name,
		"worker_count": resolved_workers,
		"available_workers": construction.available_workers(),
		"duration_days": int(estimate.get("duration_days", 0)),
		"daily_labor_cost": int(estimate.get("daily_labor_cost", 0)),
		"base_cost": base_cost,
		"labor_cost": labor_cost,
		"total_labor_cost": labor_cost,
		"total_cost": total_cost,
		"can_afford": treasury_balance() >= total_cost,
		"blueprint": blueprint.duplicate(true)
	}


func active_construction_for_tile(tile_index: int) -> Dictionary:
	for job_variant in construction.active_jobs():
		var job: Dictionary = job_variant
		if int(job.get("metadata", {}).get("tile_index", -1)) == tile_index:
			return job.duplicate(true)
	return {}


func terrain_state_for_tile(tile_index: int) -> Dictionary:
	return terrain_map.tile_state(tile_index) if terrain_map != null else {}


func terrain_snapshot() -> Dictionary:
	return terrain_map.to_dict() if terrain_map != null else {}


func terrain_flatten_quote(tile_index: int) -> Dictionary:
	if terrain_map == null or not terrain_map.is_valid_tile_id(tile_index):
		return {"ok": false, "error": "invalid_tile_id", "tile_index": tile_index}
	var terrain: Dictionary = terrain_map.tile_state(tile_index)
	var kind := str(terrain.get("effective_kind", ""))
	var cost := int(TERRAIN_FLATTEN_COSTS.get(kind, 0))
	return {
		"ok": true,
		"tile_index": tile_index,
		"terrain": terrain,
		"cost": cost,
		"can_flatten": bool(terrain.get("flattenable", false)),
		"can_afford": treasury_balance() >= cost,
	}


func flatten_terrain(tile_index: int) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	var quote := terrain_flatten_quote(tile_index)
	if not bool(quote.get("ok", false)):
		return quote
	if get_building_by_tile(tile_index).size() > 0 or _has_active_job_on_tile(tile_index):
		return {"ok": false, "error": "terrain_in_use", "tile_index": tile_index}
	if not bool(quote.get("can_flatten", false)):
		return {"ok": false, "error": "terrain_not_flattenable", "tile_index": tile_index}
	var cost := int(quote.get("cost", 0))
	if treasury_balance() < cost:
		return {"ok": false, "error": "insufficient_treasury", "required": cost}
	var before: Dictionary = terrain_map.tile_state(tile_index)
	var result: Dictionary = terrain_map.flatten_tile(tile_index)
	if not bool(result.get("ok", false)):
		return result
	_post_ledger(-cost, "terrain.flattened", "terrain_%03d" % tile_index, {
		"tile_index": tile_index,
		"terrain_kind": str(before.get("effective_kind", "")),
	})
	_record_fact({
		"type": "terrain_flattened",
		"subject_id": "tile_%03d" % tile_index,
		"game_day": game_day(),
		"reason_tag": "terrain.flattened",
		"payload": {
			"tile_index": tile_index,
			"terrain_kind": str(before.get("effective_kind", "")),
			"cost": cost,
		},
	})
	_push_ui_event("terrain_flattened", {
		"tile_index": tile_index,
		"terrain_kind": str(before.get("effective_kind", "")),
		"cost": cost,
	})
	_emit_changed()
	return {
		"ok": true,
		"tile_index": tile_index,
		"terrain": terrain_map.tile_state(tile_index),
		"cost": cost,
	}

func start_approved_building(display_name: String, tile_index: int, worker_count: int) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	if terrain_map == null or not terrain_map.is_valid_tile_id(tile_index):
		return {"ok": false, "error": "invalid_tile_id"}
	if not terrain_map.is_buildable(tile_index):
		return {
			"ok": false,
			"error": "terrain_not_flat",
			"terrain": terrain_map.tile_state(tile_index),
		}
	if get_building_by_tile(tile_index).size() > 0 or _has_active_job_on_tile(tile_index):
		return {"ok": false, "error": "tile_occupied"}
	var active := active_blueprint_status(display_name)
	var library_id := str(active.get("library_id", ""))
	if library_id.is_empty() or not blueprint_library_service.has_entry(library_id):
		return {"ok": false, "error": "approved_blueprint_required"}
	var library_entry: Dictionary = blueprint_library_service.entry(library_id)
	var blueprint: Dictionary = Dictionary(library_entry.get("blueprint", {})).duplicate(true)
	var estimate: Dictionary = construction.estimate_job(blueprint, "build", worker_count)
	var total_cost := int(blueprint.get("base_cost", 0)) + int(estimate.get("total_labor_cost", 0))
	if treasury_balance() < total_cost:
		return {"ok": false, "error": "insufficient_treasury", "required": total_cost}
	var result: Dictionary = construction.start_reusable_blueprint_job(
		library_id,
		blueprint,
		worker_count,
		game_day(),
		"tile_%02d" % tile_index,
		{"tile_index": tile_index, "building_name": display_name}
	)
	if not bool(result.get("ok", false)):
		return result
	blueprint_library_service.record_usage(library_id, game_day())
	var job: Dictionary = result["job"]
	_post_ledger(-total_cost, "construction.total_cost", str(job["id"]), {
		"base_cost": int(blueprint.get("base_cost", 0)),
		"labor_cost": int(job.get("projected_labor_cost", 0)),
		"building_name": display_name,
		"blueprint_library_id": library_id
	})
	_upsert_construction(job)
	_push_ui_event("construction_started", {"job": job, "total_cost": total_cost})
	_emit_changed()
	return {"ok": true, "job": job, "total_cost": total_cost, "blueprint_library_id": library_id}

func register_existing_building(tile_index: int, display_name: String, customization: Dictionary = {}) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	var existing := get_building_by_tile(tile_index)
	if not existing.is_empty():
		return existing
	# Existing-building registration is a migration/bootstrap seam.  Preserve its
	# structure and normalize the occupied tile to the same invariant enforced by
	# normal construction, without charging a second time.
	if terrain_map != null and terrain_map.is_valid_tile_id(tile_index) and not terrain_map.is_buildable(tile_index):
		terrain_map.flatten_tile(tile_index)
	var definition = _definition_for_name(display_name)
	if definition == null:
		return {}
	var instance_id := _next_building_id()
	var record := {
		"building_id": instance_id,
		"definition_id": String(definition.id),
		"building_name": display_name,
		"tile_index": tile_index,
		"status": "active",
		"durability": 100,
		"blueprint": {
			"version": 1,
			"building_id": String(definition.id),
			"material_id": String(definition.default_material_id),
			"floors": 2,
			"size_tier": "medium",
			"customization": customization.duplicate(true)
		}
	}
	var population_change := _adjust_population(
		maxi(0, int(definition.effects.get("population", 0))),
		"population.building_seeded",
		instance_id
	)
	record["resident_ids"] = Array(population_change["added_ids"])
	record["population_delta"] = int(population_change["actual_delta"])
	durability.register_building(instance_id, {
		"durability": 100,
		"material_value": int(definition.base_cost),
		"engineering_fee": maxi(300, int(definition.base_cost * 0.1)),
		"metadata": {"tile_index": tile_index, "building_name": display_name}
	})
	_upsert_building(record, "building.seeded")
	return record


func adjust_population(delta: int, reason_tag: String, address_id: String = "") -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	var result := _adjust_population(delta, reason_tag, address_id)
	_emit_changed()
	return result

func start_demolition(tile_index: int, worker_count: int) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	var building := get_building_by_tile(tile_index)
	if building.is_empty():
		return {"ok": false, "error": "building_not_found"}
	if str(building.get("status", "active")) == "demolition" or _has_active_job_for_target(str(building.get("building_id", ""))):
		return {"ok": false, "error": "demolition_already_active"}
	var blueprint: Dictionary = building.get("blueprint", {})
	# Demolition must be financially rejected before start_operation() allocates
	# a job ID or inserts a job. Keep the scheduler's validation order so an
	# invalid worker request is still reported before a treasury error.
	if worker_count < 1 or worker_count > ConstructionSystemScript.MAX_WORKERS:
		return {"ok": false, "error": "invalid_worker_count"}
	if worker_count > construction.available_workers():
		return {"ok": false, "error": "insufficient_workers"}
	var estimate: Dictionary = construction.estimate_job(blueprint, "demolish", worker_count)
	if float(estimate.get("workload", 0.0)) <= 0.0:
		return {"ok": false, "error": "invalid_workload"}
	var quoted_total_cost := int(estimate.get("total_labor_cost", 0))
	if treasury_balance() < quoted_total_cost:
		return {"ok": false, "error": "insufficient_treasury", "required": quoted_total_cost}
	var result: Dictionary = construction.start_operation(
		"demolish",
		blueprint,
		worker_count,
		game_day(),
		str(building["building_id"]),
		{"tile_index": tile_index, "building_name": str(building["building_name"])}
	)
	if not bool(result.get("ok", false)):
		return result
	var job: Dictionary = result["job"]
	var total_cost := int(job.get("projected_labor_cost", 0))
	_post_ledger(-total_cost, "construction.demolition", str(job["id"]), {
		"building_id": str(building["building_id"]),
		"building_name": str(building["building_name"])
	})
	var updated := building.duplicate(true)
	updated["status"] = "demolition"
	_upsert_building(updated, "building.demolition_started")
	_upsert_construction(job)
	_push_ui_event("demolition_started", {"job": job, "total_cost": total_cost})
	_emit_changed()
	return {"ok": true, "job": job, "total_cost": total_cost}

func repair_building(tile_index: int) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	var building := get_building_by_tile(tile_index)
	if building.is_empty():
		return {"ok": false, "error": "building_not_found"}
	var building_id := str(building["building_id"])
	var quote: Dictionary = durability.repair_quote(building_id)
	if not bool(quote.get("ok", false)):
		return quote
	var cost := int(quote.get("total_cost", 0))
	if treasury_balance() < cost:
		return {"ok": false, "error": "insufficient_treasury", "required": cost}
	_post_ledger(-cost, "durability.repair", building_id, {"tile_index": tile_index})
	var result: Dictionary = durability.repair(building_id, game_day())
	if bool(result.get("ok", false)):
		building["durability"] = 100
		building["status"] = "active"
		_upsert_building(building, "building.repaired")
		_record_fact(result["event"])
		_push_ui_event("building_repaired", {"tile_index": tile_index, "cost": cost})
	_emit_changed()
	return result

func settle_month(income_entries: Dictionary, expense_entries: Dictionary, maintenance_cost: int, city_context: Dictionary = {}, autosave: bool = true) -> Dictionary:
	if governance.has_failed():
		var terminal: Dictionary = _terminal_command_error()
		terminal["balance"] = treasury_balance()
		return terminal
	var income_total := 0
	var expense_total := 0
	for reason in _sorted_keys(income_entries):
		var amount := maxi(0, int(income_entries[reason]))
		if amount > 0:
			_post_ledger(amount, "income.%s" % reason, "city_monthly", {})
			income_total += amount
	for reason in _sorted_keys(expense_entries):
		var amount := maxi(0, int(expense_entries[reason]))
		if amount <= 0:
			continue
		if treasury_balance() >= amount:
			_post_ledger(-amount, "expense.%s" % reason, "city_monthly", {})
			expense_total += amount
		else:
			governance.adjust_civic_metrics(1, -1)
	var paid_maintenance := maintenance_payment_enabled and treasury_balance() >= maintenance_cost
	if paid_maintenance and maintenance_cost > 0:
		_post_ledger(-maintenance_cost, "expense.maintenance", "city_maintenance", {})
		expense_total += maintenance_cost
	var maintenance_event: Dictionary = durability.record_monthly_maintenance(paid_maintenance, game_day())
	_record_fact(maintenance_event)
	session.submit_command("patch_maintenance", {
		"unpaid_months": durability.consecutive_unpaid_months,
		"last_paid_game_time": game_day() if paid_maintenance else int(session.state.maintenance.get("last_paid_game_time", 0)),
		"reason_tag": str(maintenance_event.get("reason_tag", "maintenance.monthly"))
	}, _operation_id("maintenance"))
	if not paid_maintenance:
		governance.adjust_civic_metrics(3, -1)
	_sync_governance_to_core("governance.monthly_settlement")
	complete_requests(city_context)
	_seal_terminal_failure()
	var save_error: Error = OK
	if autosave:
		save_error = save_game()
	return {
		"ok": true,
		"income": income_total,
		"expense": expense_total,
		"maintenance_paid": paid_maintenance,
		"balance": treasury_balance(),
		"save_error": save_error,
		"failed": governance.has_failed(),
		"failure_reason": governance.failure_reason(),
	}

func submit_bill(bill_reference: String, city_context: Dictionary = {}) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	var bill_id := _bill_id_for_reference(bill_reference)
	var result: Dictionary = governance.submit_bill(bill_id, game_day())
	if bool(result.get("ok", false)):
		_record_fact({
			"type": "bill_submitted",
			"subject_id": bill_id,
			"game_day": game_day(),
			"reason_tag": "governance.bill_submitted",
			"payload": result["pending_bill"]
		})
		_sync_governance_to_core("governance.bill_submitted")
	_emit_changed()
	return result

func _bill_id_for_reference(bill_reference: String) -> String:
	if governance.bill_definitions.has(bill_reference):
		return bill_reference
	for bill_id: String in _sorted_keys(governance.bill_definitions):
		var definition: Dictionary = governance.bill_definitions[bill_id]
		if str(definition.get("name", "")) == bill_reference:
			return bill_id
	return bill_reference

func force_latest_rejected(autosave: bool = true) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	var bill_id := latest_rejected_bill_id()
	if bill_id.is_empty():
		return {"ok": false, "error": "no_rejected_bill"}
	var result: Dictionary = governance.force_enact(bill_id, game_day())
	if bool(result.get("ok", false)):
		_record_fact(result["event"])
		_sync_governance_to_core("governance.force_enactment")
		_push_ui_event("bill_force_enacted", result)
		_seal_terminal_failure()
		if autosave:
			save_game()
	_emit_changed()
	return result


func sync_governance_state(reason_tag: String = "governance.external_update") -> void:
	_sync_governance_to_core(reason_tag)
	_seal_terminal_failure()
	_emit_changed()

func latest_rejected_bill_id() -> String:
	for index in range(governance.legislative_history.size() - 1, -1, -1):
		var item: Dictionary = governance.legislative_history[index]
		var bill_id := str(item.get("bill_id", ""))
		if not bool(item.get("passed", false)) and not governance.active_laws.has(bill_id):
			return bill_id
	return ""

func refresh_requests(city_context: Dictionary) -> Array[Dictionary]:
	if governance.has_failed():
		_seal_terminal_failure()
		return []
	var created: Array[Dictionary] = population.generate_requests(game_day(), city_context, 4)
	for request in created:
		_record_fact({
			"type": "npc_request_created",
			"subject_id": str(request.get("npc_id", "")),
			"game_day": game_day(),
			"reason_tag": "resident.request_created",
			"payload": request
		})
	_emit_changed()
	return created


func initialize_requests_without_history(city_context: Dictionary) -> Array[Dictionary]:
	if governance.has_failed():
		_seal_terminal_failure()
		return []
	var created: Array[Dictionary] = population.generate_requests(game_day(), city_context, 4)
	_emit_changed()
	return created


func set_player_shell_state(state: Dictionary) -> void:
	player_shell_state = state.duplicate(true)


func get_player_shell_state() -> Dictionary:
	return player_shell_state.duplicate(true)

func select_npc(npc_id: String, city_context: Dictionary) -> Dictionary:
	selected_npc_id = npc_id
	selected_request_id = ""
	refresh_requests(city_context)
	for request in population.active_requests():
		if str(request.get("npc_id", "")) == npc_id:
			selected_request_id = str(request.get("request_id", ""))
			break
	_emit_changed()
	return population.materialize_proxy(npc_id)

func accept_selected_request(autosave: bool = true) -> bool:
	if governance.has_failed():
		_seal_terminal_failure()
		return false
	if selected_request_id.is_empty():
		return false
	var accepted: bool = bool(population.accept_request(selected_request_id, game_day()))
	if accepted:
		_record_fact({
			"type": "npc_request_accepted",
			"subject_id": selected_npc_id,
			"game_day": game_day(),
			"reason_tag": "resident.request_accepted",
			"payload": {"request_id": selected_request_id}
		})
		_push_ui_event("npc_request_accepted", {"request_id": selected_request_id})
		if autosave:
			save_game()
	_emit_changed()
	return accepted

func accept_request_by_id(request_id: String, autosave: bool = true) -> bool:
	if governance.has_failed():
		_seal_terminal_failure()
		return false
	for request in population.active_requests():
		if str(request.get("request_id", "")) != request_id:
			continue
		selected_request_id = request_id
		selected_npc_id = str(request.get("npc_id", ""))
		return accept_selected_request(autosave)
	return false

func reject_request_by_id(request_id: String, autosave: bool = true) -> bool:
	if governance.has_failed():
		_seal_terminal_failure()
		return false
	var request = population.requests.get(request_id)
	if request == null:
		return false
	selected_request_id = request_id
	selected_npc_id = str(request.npc_id)
	var rejected: bool = bool(population.reject_request(request_id, game_day()))
	if rejected:
		var authoritative_request: Dictionary = request.to_dict()
		_record_fact({
			"type": "npc_request_rejected",
			"subject_id": selected_npc_id,
			"game_day": game_day(),
			"reason_tag": "resident.request_rejected",
			"payload": authoritative_request,
		})
		_push_ui_event("npc_request_rejected", {"request_id": request_id})
		if autosave:
			save_game()
	_emit_changed()
	return rejected

func complete_requests(city_context: Dictionary) -> Array[String]:
	if governance.has_failed():
		_seal_terminal_failure()
		return []
	var completed: Array[String] = []
	for request in population.active_requests():
		var request_id := str(request.get("request_id", ""))
		if str(request.get("status", "")) == "accepted" and population.complete_request(request_id, game_day(), city_context):
			var authoritative_request: Dictionary = population.requests[request_id].to_dict()
			completed.append(request_id)
			_record_fact({
				"type": "npc_request_completed",
				"subject_id": str(authoritative_request.get("npc_id", "")),
				"game_day": game_day(),
				"reason_tag": "resident.request_completed",
				"payload": authoritative_request
			})
			_push_ui_event("npc_request_completed", {"request_id": request_id})
	return completed

func visible_npc_proxies(limit: int = 24) -> Array[Dictionary]:
	var prioritized := PackedStringArray()
	for request in population.active_requests():
		var npc_id := str(request.get("npc_id", ""))
		if not prioritized.has(npc_id):
			prioritized.append(npc_id)
	for npc_id: String in population.sorted_npc_ids():
		if prioritized.size() >= clampi(limit, 0, 80):
			break
		if not prioritized.has(npc_id):
			prioritized.append(npc_id)
	return population.get_visible_proxy_data(prioritized, limit)

func set_maintenance_payment(enabled: bool) -> void:
	if governance.has_failed():
		_seal_terminal_failure()
		return
	maintenance_payment_enabled = enabled
	_emit_changed()

func get_building_by_tile(tile_index: int) -> Dictionary:
	for building_id in _sorted_keys(session.state.buildings):
		var building: Dictionary = session.state.buildings[building_id]
		if int(building.get("tile_index", -1)) == tile_index:
			return building.duplicate(true)
	return {}

func _has_active_job_on_tile(tile_index: int) -> bool:
	for job in construction.active_jobs():
		if int(job.get("metadata", {}).get("tile_index", -1)) == tile_index:
			return true
	return false

func _has_active_job_for_target(target_id: String) -> bool:
	if target_id.is_empty():
		return false
	for job in construction.active_jobs():
		if str(job.get("target_id", "")) == target_id:
			return true
	return false

func treasury_balance() -> int:
	return session.state.ledger.get_balance()

func game_day() -> int:
	return session.state.game_time

func current_date() -> Dictionary:
	return session.state.current_date()

func get_view_model(selected_tile_index: int = -1) -> Dictionary:
	var active_requests: Array[Dictionary] = population.active_requests()
	var public_affairs_requests: Array[Dictionary] = population.public_affairs_requests()
	var npc_proxies: Dictionary = {}
	for request: Dictionary in public_affairs_requests:
		var request_npc_id := str(request.get("npc_id", ""))
		if not npc_proxies.has(request_npc_id):
			npc_proxies[request_npc_id] = population.materialize_proxy(request_npc_id)
	if not selected_npc_id.is_empty() and not npc_proxies.has(selected_npc_id):
		npc_proxies[selected_npc_id] = population.materialize_proxy(selected_npc_id)
	return VerticalSliceViewModelAssemblerScript.assemble({
		"localizer": _localization_service(),
		"core": session.get_view_model(),
		"treasury": treasury_balance(),
		"reviews": construction.reviews,
		"jobs": construction.active_jobs(),
		"available_workers": construction.available_workers(),
		"selected_building": get_building_by_tile(selected_tile_index),
		"durability_records": durability.buildings,
		"committee": governance.committee_summary(),
		"pending_bill": governance.pending_bill,
		"bill_definitions": governance.bill_definitions,
		"active_laws": governance.active_laws,
		"latest_rejected_bill_id": latest_rejected_bill_id(),
		"grievance": governance.grievance,
		"municipal_trust": governance.municipal_trust,
		"failure": governance.failure_reason(),
		"active_requests": active_requests,
		"public_affairs_requests": public_affairs_requests,
		"npc_proxies": npc_proxies,
		"selected_npc_id": selected_npc_id,
		"selected_request_id": selected_request_id,
		"population": population.population_count(),
		"save_text": last_save_message,
		"maintenance_enabled": maintenance_payment_enabled,
		"unpaid_maintenance_months": durability.consecutive_unpaid_months,
	})


func _localization_service():
	var main_loop := Engine.get_main_loop()
	if not main_loop is SceneTree:
		return null
	return (main_loop as SceneTree).root.get_node_or_null("L10n")

func set_save_path(path: String) -> void:
	save_path = path if not path.is_empty() else SAVE_PATH
	session.save_path = save_path


func save_game(path: String = "") -> Error:
	_stash_subsystems()
	var resolved_path := path if not path.is_empty() else save_path
	var error: Error = session.save_now(resolved_path)
	last_save_message = "已儲存：第 %d 年 %d 月 %d 日" % [current_date()["year"], current_date()["month"], current_date()["day"]] if error == OK else "儲存失敗（錯誤 %d）" % error
	_emit_changed()
	return error

func has_save_game(path: String = "") -> bool:
	var resolved_path := path if not path.is_empty() else save_path
	var absolute_path := ProjectSettings.globalize_path(resolved_path)
	return FileAccess.file_exists(absolute_path) or FileAccess.file_exists(absolute_path + ".bak")

func load_game(path: String = "") -> bool:
	var resolved_path := path if not path.is_empty() else save_path
	if not session.load_now(resolved_path):
		last_save_message = "找不到可讀取的垂直切片存檔。"
		_emit_changed()
		return false
	_queued_ui_events.clear()
	session.clock.day_length_seconds = GAME_DAY_LENGTH_SECONDS
	session.clock.paused = false
	_restore_subsystems()
	_seal_terminal_failure()
	last_save_message = "已讀取：第 %d 年 %d 月 %d 日" % [current_date()["year"], current_date()["month"], current_date()["day"]]
	_push_ui_event("save_loaded", {"buildings": session.state.buildings.duplicate(true)})
	_emit_changed()
	return true

func deterministic_hash() -> String:
	_stash_subsystems()
	return JSON.stringify(_canonicalize(session.make_envelope().to_dict())).sha256_text()

func drain_ui_events() -> Array[Dictionary]:
	var result := _queued_ui_events.duplicate(true)
	_queued_ui_events.clear()
	return result

func _advance_one_day(city_context: Dictionary, autosave: bool = true) -> void:
	session.advance_days_for_test(1)
	var current_day := game_day()
	var should_save := false
	for event in construction.advance_reviews(current_day, {
		"available_budget": treasury_balance(),
		"citizen_support": 100 - governance.grievance,
		"permits_enabled": true
	}):
		if str(event.get("type", "")) == "blueprint_approved":
			blueprint_library_service.archive_approved_blueprint(
				Dictionary(event.get("payload", {})),
				building_definitions,
				game_day()
			)
		_record_fact(event)
		_push_ui_event(str(event.get("type", "blueprint_review")), event)
	for event in construction.advance_jobs_day(current_day):
		should_save = _handle_construction_fact(event) or should_save
	for event in governance.advance_day(current_day, _governance_context(city_context)):
		should_save = _handle_governance_fact(event) or should_save
	if _seal_terminal_failure():
		if should_save and autosave:
			save_game()
		return
	if current_day % 7 == 0:
		for event in durability.advance_week(current_day):
			_handle_durability_fact(event)
	var date := current_date()
	if int(date["day"]) == 1 and current_day > 0:
		_push_ui_event("month_started", date)
	if int(date["day"]) == 1 and int(date["month"]) == 1 and current_day > 0:
		for event in durability.advance_year(current_day):
			_handle_durability_fact(event)
		population.advance_year(int(date["year"]), current_day)
		for event: Dictionary in governance.advance_committee_year(int(date["year"])):
			_record_fact(event)
			_push_ui_event(str(event.get("type", "committee_term")), event)
		_sync_population_to_core("population.annual_update")
	complete_requests(city_context)
	refresh_requests(city_context)
	_sync_governance_to_core("governance.daily_sync")
	if should_save and autosave:
		save_game()

func _handle_construction_fact(event: Dictionary) -> bool:
	_record_fact(event)
	var event_type := str(event.get("type", ""))
	var job_id := str(event.get("subject_id", ""))
	if construction.jobs.has(job_id):
		_upsert_construction(construction.jobs[job_id])
	if event_type != "construction_completed":
		return false
	var job: Dictionary = event.get("payload", {})
	var operation := str(job.get("operation", "build"))
	var metadata: Dictionary = job.get("metadata", {})
	if operation == "build":
		var display_name := str(metadata.get("building_name", ""))
		var definition = _definition_for_name(display_name)
		var instance_id := _next_building_id()
		var record := {
			"building_id": instance_id,
			"definition_id": str(job.get("blueprint", {}).get("building_id", "")),
			"building_name": display_name,
			"tile_index": int(metadata.get("tile_index", -1)),
			"status": "active",
			"durability": 100,
			"blueprint": job.get("blueprint", {}).duplicate(true)
		}
		var population_change := _adjust_population(
			maxi(0, int(definition.effects.get("population", 0))) if definition != null else 0,
			"population.building_completed",
			instance_id
		)
		record["resident_ids"] = Array(population_change["added_ids"])
		record["population_delta"] = int(population_change["actual_delta"])
		durability.register_building(instance_id, {
			"durability": 100,
			"material_value": int(definition.base_cost) if definition != null else 1000,
			"engineering_fee": maxi(300, int((definition.base_cost if definition != null else 1000) * 0.1)),
			"metadata": metadata
		})
		_upsert_building(record, "building.construction_completed")
		_push_ui_event("building_completed", record)
	elif operation == "demolish":
		var target_id := str(job.get("target_id", ""))
		var building_record: Dictionary = session.state.buildings.get(target_id, {})
		var population_change := _remove_population_ids(
			_resident_ids_from_building(building_record),
			"population.building_demolished"
		)
		durability.unregister_building(target_id)
		session.submit_command("remove_building", {
			"building_id": target_id,
			"reason_tag": "building.demolition_completed"
		}, _operation_id("building_remove"))
		_push_ui_event("demolition_completed", {
			"building_id": target_id,
			"tile_index": int(metadata.get("tile_index", -1)),
			"building_name": str(metadata.get("building_name", "")),
			"population_delta": int(population_change["actual_delta"])
		})
	session.submit_command("remove_construction", {
		"job_id": job_id,
		"reason_tag": "construction.completed"
	}, _operation_id("job_remove"))
	return true

func _handle_durability_fact(event: Dictionary) -> void:
	_record_fact(event)
	var building_id := str(event.get("subject_id", ""))
	if not session.state.buildings.has(building_id):
		return
	var record: Dictionary = session.state.buildings[building_id].duplicate(true)
	var previous_status := str(record.get("status", "active"))
	var durability_record: Dictionary = durability.get_building(building_id)
	record["durability"] = int(durability_record.get("durability", record.get("durability", 100)))
	record["status"] = str(durability_record.get("status", record.get("status", "active")))
	var population_change := {
		"requested_delta": 0,
		"actual_delta": 0,
		"added_ids": PackedStringArray(),
		"removed_ids": PackedStringArray(),
	}
	if record["status"] == "scrapped" and previous_status != "scrapped":
		population_change = _remove_population_ids(
			_resident_ids_from_building(record),
			"population.building_scrapped"
		)
		record["resident_ids"] = []
		record["population_delta"] = 0
	_upsert_building(record, str(event.get("reason_tag", "building.durability")))
	if record["status"] == "scrapped":
		var payload := record.duplicate(true)
		payload["population_delta"] = int(population_change["actual_delta"])
		_push_ui_event("building_scrapped", payload)

func _handle_governance_fact(event: Dictionary) -> bool:
	_record_fact(event)
	var event_type := str(event.get("type", ""))
	if event_type == "judiciary_fine":
		var fine := -int(event.get("value_delta", 0))
		if fine > 0:
			_post_ledger(-mini(fine, treasury_balance()), "judiciary.fine", str(event.get("subject_id", "court")), {})
	_push_ui_event(event_type, event)
	_sync_governance_to_core(str(event.get("reason_tag", "governance.updated")))
	return event_type.begins_with("judiciary_") or event_type.begins_with("oversight_")

func _sync_population_to_core(reason_tag: String) -> void:
	var canonical_ids := {}
	for npc_id: String in population.sorted_npc_ids():
		canonical_ids[npc_id] = true
	for npc_id: String in _sorted_keys(session.state.npcs):
		if canonical_ids.has(npc_id):
			continue
		session.submit_command("remove_npc", {
			"npc_id": npc_id,
			"reason_tag": reason_tag
		}, _operation_id("npc_remove"))
	for npc_id: String in population.sorted_npc_ids():
		var canonical_record: Dictionary = population.get_record(npc_id).to_dict()
		if session.state.npcs.has(npc_id) and _state_values_equivalent(session.state.npcs[npc_id], canonical_record):
			continue
		session.submit_command("upsert_npc", {
			"npc_id": npc_id,
			"record": canonical_record,
			"reason_tag": reason_tag
		}, _operation_id("npc_sync"))
	if int(session.state.metrics.get("population", -1)) != population.population_count():
		_set_metric("population", population.population_count(), reason_tag)


func _adjust_population(delta: int, reason_tag: String, address_id: String = "") -> Dictionary:
	var added_ids := PackedStringArray()
	var removed_ids := PackedStringArray()
	if delta > 0:
		added_ids = population.add_residents(delta, game_day(), reason_tag, address_id)
	elif delta < 0:
		removed_ids = population.remove_residents(-delta, game_day(), reason_tag)
	_normalize_selected_population_references(removed_ids)
	_sync_population_to_core(reason_tag)
	return {
		"requested_delta": delta,
		"actual_delta": added_ids.size() - removed_ids.size(),
		"added_ids": added_ids,
		"removed_ids": removed_ids,
	}


func _remove_population_ids(npc_ids: PackedStringArray, reason_tag: String) -> Dictionary:
	var removed_ids: PackedStringArray = population.remove_residents_by_id(npc_ids, game_day(), reason_tag)
	_normalize_selected_population_references(removed_ids)
	_sync_population_to_core(reason_tag)
	return {
		"requested_delta": -npc_ids.size(),
		"actual_delta": -removed_ids.size(),
		"added_ids": PackedStringArray(),
		"removed_ids": removed_ids,
	}


func _normalize_selected_population_references(removed_ids: PackedStringArray = PackedStringArray()) -> void:
	if removed_ids.has(selected_npc_id) or (not selected_npc_id.is_empty() and population.get_record(selected_npc_id) == null):
		selected_npc_id = ""
		selected_request_id = ""
	elif not selected_request_id.is_empty() and not population.requests.has(selected_request_id):
		selected_request_id = ""


static func _resident_ids_from_building(building: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	var raw_ids: Variant = building.get("resident_ids", [])
	if raw_ids is PackedStringArray or raw_ids is Array:
		for raw_id: Variant in raw_ids:
			var npc_id := str(raw_id)
			if not npc_id.is_empty() and not result.has(npc_id):
				result.append(npc_id)
	return result


static func _state_values_equivalent(left: Variant, right: Variant) -> bool:
	var left_type := typeof(left)
	var right_type := typeof(right)
	if left_type in [TYPE_INT, TYPE_FLOAT] and right_type in [TYPE_INT, TYPE_FLOAT]:
		return float(left) == float(right)
	if left_type != right_type:
		return false
	if left is Dictionary:
		if left.size() != right.size():
			return false
		for key: Variant in left.keys():
			if not right.has(key) or not _state_values_equivalent(left[key], right[key]):
				return false
		return true
	if left is Array:
		if left.size() != right.size():
			return false
		for index: int in range(left.size()):
			if not _state_values_equivalent(left[index], right[index]):
				return false
		return true
	return left == right

func _record_fact(event: Dictionary) -> void:
	var payload: Dictionary = event.get("payload", {}).duplicate(true)
	payload["fact_type"] = str(event.get("type", "domain_fact"))
	payload["value_delta"] = event.get("value_delta")
	session.submit_command("append_event_book", {
		"subject_id": str(event.get("subject_id", "city")),
		"reason_tag": str(event.get("reason_tag", "domain_fact")),
		"record": payload
	}, _operation_id("fact"))

func _post_ledger(amount: int, reason_tag: String, source_id: String, metadata: Dictionary) -> void:
	if amount == 0:
		return
	session.submit_command("ledger_post", {
		"amount": amount,
		"reason_tag": reason_tag,
		"source_id": source_id,
		"metadata": metadata,
		"allow_overdraft": false
	}, _operation_id("ledger"))

func _upsert_building(record: Dictionary, reason_tag: String) -> void:
	session.submit_command("upsert_building", {
		"building_id": str(record.get("building_id", "")),
		"record": record,
		"reason_tag": reason_tag
	}, _operation_id("building"))

func _upsert_construction(job: Dictionary) -> void:
	session.submit_command("upsert_construction", {
		"job_id": str(job.get("id", "")),
		"record": job,
		"reason_tag": "construction.updated"
	}, _operation_id("construction"))

func _set_metric(metric: String, value: Variant, reason_tag: String) -> void:
	session.submit_command("metric_change", {
		"metric": metric,
		"value": value,
		"reason_tag": reason_tag
	}, _operation_id("metric"))

func _sync_governance_to_core(reason_tag: String) -> void:
	_set_metric("grievance", governance.grievance, reason_tag)
	_set_metric("municipal_trust", governance.municipal_trust, reason_tag)
	session.submit_command("patch_governance", {
		"active_laws": governance.active_laws.values(),
		"pending_bills": [] if governance.pending_bill.is_empty() else [governance.pending_bill],
		"rejected_bills": governance.rejected_bills.values(),
		"judicial_cases": governance.judiciary_cases.values(),
		"oversight_cases": governance.oversight_cases.values(),
		"committee_summary": governance.committee_summary(),
		"failed": governance.has_failed(),
		"failure_reason": governance.failure_reason(),
		"reason_tag": reason_tag
	}, _operation_id("governance"))

func _stash_subsystems() -> void:
	var blueprint_snapshot: Dictionary = blueprint_library_service.snapshot()
	session.state.metadata["vertical_slice"] = {
		"schema_version": 5,
		"construction": construction.to_dict(),
		"durability": durability.to_dict(),
		"governance": governance.to_dict(),
		"population": population.to_dict(),
		"terrain": terrain_map.to_dict() if terrain_map != null else {},
		"maintenance_payment_enabled": maintenance_payment_enabled,
		"selected_npc_id": selected_npc_id,
		"selected_request_id": selected_request_id,
		"next_blueprint_sequence": int(blueprint_snapshot["next_blueprint_sequence"]),
		"blueprint_library": Dictionary(blueprint_snapshot["blueprint_library"]),
		"active_blueprint_by_building": Dictionary(blueprint_snapshot["active_blueprint_by_building"]),
		"next_building_sequence": next_building_sequence,
		"next_operation_sequence": next_operation_sequence,
		"last_city_context": last_city_context.duplicate(true),
		"player_shell_state": player_shell_state.duplicate(true),
		"terminal_failure_event_reason": _terminal_failure_event_reason,
	}

func _restore_subsystems() -> void:
	var data: Dictionary = session.state.metadata.get("vertical_slice", {})
	construction = ConstructionSystemScript.create_from_dict(data.get("construction", {}))
	durability = DurabilitySystemScript.create_from_dict(data.get("durability", {}))
	governance = GovernanceSystemScript.create_from_dict(data.get("governance", {}))
	var population_data: Variant = data.get("population", {})
	var has_population_snapshot := population_data is Dictionary and (population_data as Dictionary).has("records") and (population_data as Dictionary).get("records") is Array
	population = PopulationSystemScript.from_dict(population_data as Dictionary) if population_data is Dictionary else null
	if population == null or not has_population_snapshot:
		population = PopulationSystemScript.new()
		population.initialize(300, int(session.kernel.rng_seed))
	var terrain_data: Variant = data.get("terrain", {})
	if terrain_data is Dictionary and not (terrain_data as Dictionary).is_empty():
		terrain_map = CityTerrainMapScript.create_from_dict(terrain_data)
	else:
		terrain_map = CityTerrainMapScript.new()
		terrain_map.apply_default_city_layout()
	maintenance_payment_enabled = bool(data.get("maintenance_payment_enabled", true))
	selected_npc_id = str(data.get("selected_npc_id", ""))
	selected_request_id = str(data.get("selected_request_id", ""))
	next_building_sequence = maxi(1, int(data.get("next_building_sequence", 1)))
	next_operation_sequence = maxi(1, int(data.get("next_operation_sequence", 1)))
	last_city_context = Dictionary(data.get("last_city_context", {})).duplicate(true)
	player_shell_state = Dictionary(data.get("player_shell_state", {})).duplicate(true)
	_terminal_failure_event_reason = str(data.get("terminal_failure_event_reason", ""))
	for building_id in session.state.buildings.keys():
		var suffix := str(building_id).trim_prefix("building_")
		if suffix.is_valid_int():
			next_building_sequence = maxi(next_building_sequence, int(suffix) + 1)
	# Saves created before terrain schema 5 had no authored terrain snapshot.
	# Occupied and active-worksite tiles are normalized to flat so loading an old
	# city can never strand an existing structure on newly introduced terrain.
	for building_variant: Variant in session.state.buildings.values():
		var building_record: Dictionary = building_variant
		var occupied_tile := int(building_record.get("tile_index", -1))
		if terrain_map.is_valid_tile_id(occupied_tile) and not terrain_map.is_buildable(occupied_tile):
			terrain_map.flatten_tile(occupied_tile)
	for job_variant: Variant in construction.active_jobs():
		var job: Dictionary = job_variant
		var job_tile := int(job.get("metadata", {}).get("tile_index", -1))
		if terrain_map.is_valid_tile_id(job_tile) and not terrain_map.is_buildable(job_tile):
			terrain_map.flatten_tile(job_tile)
	building_definitions = ContentRegistry.buildings_by_id()
	blueprint_library_service.restore(
		int(data.get("next_blueprint_sequence", 1)),
		Dictionary(data.get("blueprint_library", {})),
		Dictionary(data.get("active_blueprint_by_building", {})),
		building_definitions
	)
	for review_variant in construction.reviews.values():
		var historical_review: Dictionary = review_variant
		if str(historical_review.get("status", "")) in ["approved", "in_construction", "completed"]:
			blueprint_library_service.archive_approved_blueprint(
				historical_review,
				building_definitions,
				game_day()
			)
	_normalize_selected_population_references()
	_sync_population_to_core("population.load_reconcile" if has_population_snapshot else "population.load_fallback")

func _definition_for_name(display_name: String):
	var building_id := ContentRegistry.building_id_for_name(display_name)
	return building_definitions.get(building_id)

func _next_building_id() -> String:
	var id := "building_%06d" % next_building_sequence
	next_building_sequence += 1
	return id

func _operation_id(prefix: String) -> String:
	var id := "coord_%s_%010d" % [prefix, next_operation_sequence]
	next_operation_sequence += 1
	return id

func _seal_terminal_failure() -> bool:
	if governance == null:
		return false
	var reason: String = governance.latch_failure()
	if reason.is_empty():
		return false
	session.clock.paused = true
	if _terminal_failure_event_reason == reason:
		return true
	_terminal_failure_event_reason = reason
	_sync_governance_to_core("governance.failed")
	_push_ui_event("governance_failed", {"failure_reason": reason})
	return true

func _terminal_command_error() -> Dictionary:
	_seal_terminal_failure()
	return {
		"ok": false,
		"error": "game_already_failed",
		"failure_reason": governance.failure_reason(),
	}

func _push_ui_event(event_type: String, payload: Dictionary) -> void:
	var event := {"type": event_type, "payload": payload.duplicate(true), "game_day": game_day()}
	_queued_ui_events.append(event)
	ui_event.emit(event)

func _emit_changed() -> void:
	changed.emit(get_view_model())

func _governance_context(city_context: Dictionary) -> Dictionary:
	return {
		"game_day": game_day(),
		"economic_health": float(city_context.get("economic_health", 60.0)),
		"budget_health": clampf(50.0 + float(treasury_balance()) / 20_000.0, 0.0, 100.0),
		"public_support": float(city_context.get("public_support", 100 - governance.grievance)),
		"environment_health": float(city_context.get("environment", city_context.get("environment_health", 50.0))),
		"security_health": float(city_context.get("security", city_context.get("security_health", 50.0))),
		"traffic_pressure": 100.0 - float(city_context.get("traffic", 50.0)),
		"housing_pressure": float(city_context.get("housing_pressure", 50.0)),
		"regional_support": city_context.get("regional_support", {}),
		"mayor_argument_bonus": float(city_context.get("mayor_argument_bonus", 2.0)),
		"policy_effectiveness": city_context.get("policy_effectiveness", {})
	}

static func _sorted_keys(source: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key in source.keys():
		result.append(str(key))
	result.sort()
	return result

static func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var source: Dictionary = value
		var result := {}
		for key in _sorted_keys(source):
			result[key] = _canonicalize(source[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_canonicalize(item))
		return result
	# JSON restores all numeric literals through a generic Variant path. Treat
	# integral floats as integers so a save/load round trip hashes identically.
	if value is float and is_equal_approx(float(value), roundf(float(value))):
		return int(value)
	return value
