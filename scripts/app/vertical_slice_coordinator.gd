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
const CitySimulationServiceScript = preload("res://scripts/app/city_simulation_service.gd")
const BlueprintLibraryServiceScript = preload("res://scripts/app/blueprint_library_service.gd")
const VerticalSliceViewModelAssemblerScript = preload("res://scripts/app/vertical_slice_view_model_assembler.gd")
const CityTerrainMapScript = preload("res://scripts/world/city_terrain_map.gd")
const TransportNetworkSystemScript = preload("res://scripts/systems/city/transport_network_system.gd")
const TransportPlanningSessionScript = preload("res://scripts/systems/city/transport_planning_session.gd")
const TransportModesScript = preload("res://data/catalogs/transport_modes.gd")
const SaveSchemaAuthorityScript = preload("res://scripts/core/save_schema_authority.gd")
const BuildingFootprintsScript = preload("res://data/catalogs/building_footprints.gd")

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
const DEFAULT_TERRAIN_FLATTEN_WORKERS := 5

var session
var construction
var durability
var governance
var population
var terrain_map
var transport
var transport_planning_session
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

func _init(
	seed: int = DEFAULT_SEED,
	initial_funds: int = DEFAULT_INITIAL_FUNDS,
	initial_population: int = PopulationSystemScript.DEFAULT_INITIAL_POPULATION
) -> void:
	new_game(seed, initial_funds, initial_population)


func new_game(
	seed: int = DEFAULT_SEED,
	initial_funds: int = DEFAULT_INITIAL_FUNDS,
	initial_population: int = PopulationSystemScript.DEFAULT_INITIAL_POPULATION
) -> bool:
	# Reject unsupported capacity before touching the live coordinator. This also
	# keeps the invalid path free of save I/O and partial runtime state changes.
	if initial_population < 0 or initial_population > PopulationSystemScript.MAX_POPULATION:
		return false
	session = GameSessionScript.new(seed, initial_funds)
	session.clock.day_length_seconds = GAME_DAY_LENGTH_SECONDS
	session.clock.paused = false
	construction = ConstructionSystemScript.new(seed)
	durability = DurabilitySystemScript.new()
	governance = GovernanceSystemScript.new(seed)
	population = PopulationSystemScript.new()
	if not population.initialize(initial_population, seed):
		return false
	if not session.hydrate_runtime_population(population.to_dict()):
		return false
	terrain_map = CityTerrainMapScript.new()
	terrain_map.apply_default_city_layout()
	transport = TransportNetworkSystemScript.new()
	transport_planning_session = TransportPlanningSessionScript.new()
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
	_emit_changed()
	return true

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


func draft_placement_quote(display_name: String, payload: Dictionary) -> Dictionary:
	## A pre-submission quote has no library identity by design: it is derived
	## from the live draft, then submit_blueprint() invokes the same blueprint
	## service helper to prevent a quote/blueprint drift.
	var definition = _definition_for_name(display_name)
	if definition == null:
		return {"ok": false, "error": "building_definition_not_found"}
	var draft_payload := payload.duplicate(true)
	draft_payload["building_name"] = display_name
	var blueprint: Dictionary = blueprint_library_service.preview_submission_blueprint(draft_payload, definition)
	var workers := int(blueprint.get("requested_workers", 5))
	var estimate: Dictionary = construction.estimate_job(blueprint, "build", workers)
	var base_cost := int(blueprint.get("base_cost", 0))
	var labor_cost := int(estimate.get("total_labor_cost", 0))
	var size_tier := str(blueprint.get("size_tier", "medium"))
	var footprint_count: int = int({"small": 1, "medium": 2, "large": 3}.get(size_tier, 0))
	return {
		"ok": true,
		"draft": true,
		"building_name": display_name,
		"worker_count": workers,
		"available_workers": construction.available_workers(),
		"duration_days": int(estimate.get("duration_days", 0)),
		"daily_labor_cost": int(estimate.get("daily_labor_cost", 0)),
		"base_cost": base_cost,
		"labor_cost": labor_cost,
		"total_labor_cost": labor_cost,
		"total_cost": base_cost + labor_cost,
		"can_afford": treasury_balance() >= base_cost + labor_cost,
		"footprint_count": footprint_count,
		"blueprint": blueprint.duplicate(true),
	}


func placement_footprint_quote(
	display_name: String,
	anchor_tile_id: int,
	worker_count: int = -1
) -> Dictionary:
	var quote := placement_quote(display_name, worker_count)
	if not bool(quote.get("ok", false)):
		return quote
	var blueprint: Dictionary = quote.get("blueprint", {})
	var footprint := BuildingFootprintsScript.resolve_for_size(
		str(blueprint.get("size_tier", "")),
		anchor_tile_id,
		terrain_map
	)
	if not bool(footprint.get("ok", false)):
		return {
			"ok": false,
			"error": str(footprint.get("error", "invalid_footprint")),
			"anchor_tile_id": anchor_tile_id,
		}
	var occupied_tile_ids: Array[int] = []
	for tile_variant: Variant in footprint.get("occupied_tile_ids", []):
		occupied_tile_ids.append(int(tile_variant))
	var transport_tiles: Dictionary = {}
	for tile_id: int in transport_navigation_blocked_tile_ids():
		transport_tiles[tile_id] = true
	for tile_id: int in occupied_tile_ids:
		if not terrain_map.is_buildable(tile_id):
			return {
				"ok": false,
				"error": "terrain_not_flat",
				"anchor_tile_id": anchor_tile_id,
				"blocked_tile_id": tile_id,
				"terrain": terrain_map.tile_state(tile_id),
			}
		if not get_building_by_tile(tile_id).is_empty():
			return {
				"ok": false,
				"error": "tile_occupied",
				"occupancy_kind": "building",
				"blocked_tile_id": tile_id,
			}
		if not active_construction_for_tile(tile_id).is_empty():
			return {
				"ok": false,
				"error": "tile_occupied",
				"occupancy_kind": "construction",
				"blocked_tile_id": tile_id,
			}
		if transport_tiles.has(tile_id):
			return {
				"ok": false,
				"error": "tile_occupied",
				"occupancy_kind": "transport",
				"blocked_tile_id": tile_id,
			}
	quote["anchor_tile_id"] = anchor_tile_id
	quote["footprint_id"] = str(footprint.get("footprint_id", ""))
	quote["occupied_tile_ids"] = occupied_tile_ids
	quote["can_place"] = true
	return quote


func placement_footprint_preview(
	display_name: String,
	anchor_tile_id: int,
	worker_count: int = -1
) -> Dictionary:
	# Preview geometry is derived from the same size catalog as placement, while
	# keeping invalid east-edge anchors visible as an all-red group in the map UI.
	var quote := placement_quote(display_name, worker_count)
	if not bool(quote.get("ok", false)):
		return quote
	var blueprint: Dictionary = quote.get("blueprint", {})
	var footprint_id := BuildingFootprintsScript.footprint_id_for_size(
		str(blueprint.get("size_tier", ""))
	)
	var offsets := BuildingFootprintsScript.offsets_for_footprint(footprint_id)
	if footprint_id.is_empty() or offsets.is_empty():
		return {"ok": false, "error": "unsupported_building_size"}
	var preview := {
		"ok": true,
		"can_place": false,
		"anchor_tile_id": anchor_tile_id,
		"footprint_id": footprint_id,
		"footprint_count": offsets.size(),
		"occupied_tile_ids": [],
		"error": "invalid_anchor_tile_id",
	}
	var resolved := BuildingFootprintsScript.resolve_for_footprint(
		footprint_id,
		anchor_tile_id,
		terrain_map
	)
	if not bool(resolved.get("ok", false)):
		preview["error"] = str(resolved.get("error", "invalid_footprint"))
		return preview
	var placement := placement_footprint_quote(display_name, anchor_tile_id, worker_count)
	preview["occupied_tile_ids"] = Array(resolved.get("occupied_tile_ids", [])).duplicate()
	preview["can_place"] = bool(placement.get("ok", false))
	preview["error"] = "" if bool(preview["can_place"]) else str(placement.get("error", "invalid_footprint"))
	return preview


func active_construction_for_tile(tile_index: int) -> Dictionary:
	for job_variant in construction.active_jobs():
		var job: Dictionary = job_variant
		if _construction_job_tile_indices(job).has(tile_index):
			return job.duplicate(true)
	return {}


func footprint_cell_view(tile_index: int) -> Dictionary:
	var building := get_building_by_tile(tile_index)
	if not building.is_empty():
		return _footprint_cell_view(
			"building",
			building,
			_building_record_occupied_tile_ids_canonical(building),
			tile_index
		)
	var job := active_construction_for_tile(tile_index)
	if job.is_empty() or str(job.get("operation", "")) != "build":
		return {}
	var metadata: Dictionary = job.get("metadata", {})
	if str(metadata.get("footprint_id", "")).is_empty():
		return {}
	return _footprint_cell_view(
		"construction",
		job,
		_construction_job_tile_indices_canonical(job),
		tile_index
	)


func terrain_state_for_tile(tile_index: int) -> Dictionary:
	return terrain_map.tile_state(tile_index) if terrain_map != null else {}


func terrain_snapshot() -> Dictionary:
	return terrain_map.to_dict() if terrain_map != null else {}


func transport_project_quote(
	kind: String,
	operation: String,
	tile_ids: Array,
	worker_count: int = 5,
	city_grid: Array = []
) -> Dictionary:
	if transport == null:
		return {"ok": false, "error": "transport_system_unavailable"}
	var resolved_kind := "rail_track" if kind == "heavy_rail" else kind
	if operation not in TransportModesScript.PROJECT_OPERATIONS:
		return {"ok": false, "error": "invalid_project_operation"}
	if worker_count < 1 or worker_count > ConstructionSystemScript.MAX_WORKERS:
		return {"ok": false, "error": "invalid_worker_count"}
	var plan := _transport_plan_for_tiles(resolved_kind, operation, tile_ids)
	if plan.is_empty():
		return {"ok": false, "error": "invalid_transport_kind"}
	var model_quote: Dictionary = transport.quote_project(
		operation,
		plan,
		terrain_map,
		_transport_occupied_tile_ids(city_grid),
		_transport_construction_tile_ids()
	)
	if not bool(model_quote.get("ok", false)):
		return _transport_public_quote_error(model_quote)
	var project_tiles := _transport_project_tile_indices(operation, Dictionary(model_quote.get("plan", {})))
	if project_tiles.is_empty():
		return {"ok": false, "error": "transport_targets_required", "issues": ["transport_targets_required"]}
	var job_blueprint := _transport_job_blueprint(resolved_kind, project_tiles, worker_count)
	var estimate: Dictionary = construction.estimate_job(job_blueprint, operation, worker_count)
	var network_cost := int(model_quote.get("total_cost", 0))
	var labor_cost := int(estimate.get("total_labor_cost", 0))
	var total_cost := network_cost + labor_cost
	var available_workers: int = int(construction.available_workers())
	return {
		"ok": true,
		"kind": resolved_kind,
		"operation": operation,
		"tile_indices": project_tiles,
		"worker_count": worker_count,
		"available_workers": available_workers,
		"duration_days": int(estimate.get("duration_days", 0)),
		"daily_labor_cost": int(estimate.get("daily_labor_cost", 0)),
		"base_cost": network_cost,
		"network_cost": network_cost,
		"labor_cost": labor_cost,
		"total_labor_cost": labor_cost,
		"total_cost": total_cost,
		"can_afford": treasury_balance() >= total_cost,
		"can_start": available_workers >= worker_count and treasury_balance() >= total_cost,
		"breakdown": Dictionary(model_quote.get("breakdown", {})).duplicate(true),
		"crossing_tile_ids": Array(model_quote.get("crossing_tile_ids", [])).duplicate(),
		"project_plan": Dictionary(model_quote.get("plan", {})).duplicate(true),
	}


func begin_transport_planning_session(station_blueprint_name: String, workflow: String = "") -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	if station_blueprint_name not in TransportModesScript.STATION_KINDS:
		return {"ok": false, "error": "invalid_station_blueprint"}
	var active := active_blueprint_status(station_blueprint_name)
	if not bool(active.get("exists", false)):
		return {"ok": false, "error": "approved_blueprint_required"}
	var library_id := str(active.get("library_id", active.get("id", "")))
	var result: Dictionary = transport_planning_session.begin(station_blueprint_name, library_id, workflow)
	if bool(result.get("ok", false)):
		_push_ui_event("transport_planning_session_started", result.get("session", {}))
		_emit_changed()
	return result


func transport_planning_session_snapshot() -> Dictionary:
	return transport_planning_session.snapshot() if transport_planning_session != null else {"state": "inactive"}


func place_transport_session_station(
	anchor_tile_id: int,
	worker_count: int = -1
) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	if transport_planning_session == null:
		return {"ok": false, "error": "transport_planning_session_unavailable"}
	var current: Dictionary = transport_planning_session.snapshot()
	var station_name := str(current.get("station_blueprint_name", ""))
	var active := active_blueprint_status(station_name)
	var library_id := str(active.get("library_id", active.get("id", "")))
	var preflight: Dictionary = transport_planning_session.can_place_station(station_name, library_id)
	if not bool(preflight.get("ok", false)):
		return preflight
	var resolved_workers := worker_count
	if resolved_workers <= 0:
		resolved_workers = int(active.get("blueprint", {}).get("requested_workers", 5))
	var placement: Dictionary = start_approved_building(station_name, anchor_tile_id, resolved_workers)
	if not bool(placement.get("ok", false)):
		placement["session"] = transport_planning_session.snapshot()
		return placement
	var recorded: Dictionary = transport_planning_session.record_station_job(
		Dictionary(placement.get("job", {})),
		placement
	)
	if not bool(recorded.get("ok", false)):
		push_error("Transport planning session failed to record a preflighted station job.")
		return {"ok": false, "error": "transport_session_record_failed"}
	placement["session"] = transport_planning_session.snapshot()
	_push_ui_event("transport_session_station_started", {
		"job": Dictionary(placement.get("job", {})).duplicate(true),
		"session": transport_planning_session.snapshot(),
	})
	_emit_changed()
	return placement


func draft_transport_session_station(
	anchor_tile_id: int,
	worker_count: int = -1
) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	if transport_planning_session == null or not transport_planning_session.is_route_package():
		return {"ok": false, "error": "transport_session_not_route_package"}
	var current: Dictionary = transport_planning_session.snapshot()
	var station_name := str(current.get("station_blueprint_name", ""))
	var active := active_blueprint_status(station_name)
	var library_id := str(active.get("library_id", active.get("id", "")))
	var preflight: Dictionary = transport_planning_session.can_place_station(station_name, library_id)
	if not bool(preflight.get("ok", false)):
		return preflight
	var resolved_workers := worker_count
	if resolved_workers <= 0:
		resolved_workers = int(active.get("blueprint", {}).get("requested_workers", 5))
	var placement := placement_footprint_quote(station_name, anchor_tile_id, resolved_workers)
	if not bool(placement.get("ok", false)):
		return placement
	var recorded: Dictionary = transport_planning_session.record_station_draft(placement, resolved_workers)
	if not bool(recorded.get("ok", false)):
		return recorded
	_push_ui_event("transport_session_station_drafted", {
		"anchor_tile_id": anchor_tile_id,
		"occupied_tile_ids": Array(placement.get("occupied_tile_ids", [])).duplicate(),
		"session": transport_planning_session.snapshot(),
	})
	_emit_changed()
	return {
		"ok": true,
		"placement": placement.duplicate(true),
		"session": transport_planning_session.snapshot(),
		"authoritative_changes_applied": false,
	}


func reuse_transport_session_station(tile_id: int) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	if transport_planning_session == null or not transport_planning_session.is_route_package():
		return {"ok": false, "error": "transport_session_not_route_package"}
	var current: Dictionary = transport_planning_session.snapshot()
	var station_name := str(current.get("station_blueprint_name", ""))
	var active := active_blueprint_status(station_name)
	var library_id := str(active.get("library_id", active.get("id", "")))
	var preflight: Dictionary = transport_planning_session.can_place_station(station_name, library_id)
	if not bool(preflight.get("ok", false)):
		return preflight
	var reusable := _transport_reusable_station_placement(tile_id, current)
	if not bool(reusable.get("ok", false)):
		return reusable
	var recorded: Dictionary = transport_planning_session.record_existing_station_draft(
		Dictionary(reusable.get("placement", {})),
		Dictionary(reusable.get("station", {}))
	)
	if not bool(recorded.get("ok", false)):
		return recorded
	_push_ui_event("transport_session_station_reused", {
		"station": Dictionary(reusable.get("station", {})).duplicate(true),
		"session": transport_planning_session.snapshot(),
	})
	_emit_changed()
	return {
		"ok": true,
		"station": Dictionary(reusable.get("station", {})).duplicate(true),
		"placement": Dictionary(reusable.get("placement", {})).duplicate(true),
		"session": transport_planning_session.snapshot(),
		"authoritative_changes_applied": false,
	}


func remove_transport_session_station_draft(anchor_tile_id: int) -> Dictionary:
	if transport_planning_session == null:
		return {"ok": false, "error": "transport_planning_session_unavailable"}
	var result: Dictionary = transport_planning_session.remove_station_draft(anchor_tile_id)
	if bool(result.get("ok", false)):
		_emit_changed()
	return result


func begin_transport_session_network_placement(
	network_kind: String,
	draft: Dictionary = {}
) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	var result: Dictionary = transport_planning_session.begin_network_placement(network_kind, draft)
	if bool(result.get("ok", false)):
		_push_ui_event("transport_session_network_placement", result.get("session", {}))
		_emit_changed()
	return result


func start_transport_session_network_project(
	network_kind: String,
	tile_ids: Array,
	worker_count: int = 5,
	city_grid: Array = []
) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	var draft := {
		"kind": network_kind,
		"operation": "build",
		"tile_ids": tile_ids.duplicate(),
		"worker_count": worker_count,
	}
	var draft_result: Dictionary = transport_planning_session.update_network_draft(network_kind, draft)
	if not bool(draft_result.get("ok", false)):
		return draft_result
	var started: Dictionary = start_transport_project(
		network_kind,
		"build",
		tile_ids,
		worker_count,
		city_grid
	)
	if not bool(started.get("ok", false)):
		# The attempted geometry remains an editable player draft.  The failed
		# authority command is atomic: no project, job, reference, or charge was applied.
		started["draft_retained"] = true
		started["authoritative_changes_applied"] = false
		started["session"] = transport_planning_session.snapshot()
		return started
	var recorded: Dictionary = transport_planning_session.record_network_job(
		Dictionary(started.get("project", {})),
		Dictionary(started.get("job", {}))
	)
	if not bool(recorded.get("ok", false)):
		push_error("Transport planning session failed to record a preflighted network job.")
		return {"ok": false, "error": "transport_session_record_failed"}
	started["session"] = transport_planning_session.snapshot()
	_emit_changed()
	return started


func draft_transport_session_network(
	network_kind: String,
	tile_ids: Array,
	worker_count: int = 5
) -> Dictionary:
	if transport_planning_session == null or not transport_planning_session.is_route_package():
		return {"ok": false, "error": "transport_session_not_route_package"}
	var draft := {
		"kind": network_kind,
		"operation": "build",
		"tile_ids": tile_ids.duplicate(),
		"worker_count": worker_count,
	}
	var result: Dictionary = transport_planning_session.update_network_draft(network_kind, draft)
	if bool(result.get("ok", false)):
		_emit_changed()
	return result


func begin_transport_session_route_edit(draft: Dictionary = {}) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	var result: Dictionary = transport_planning_session.begin_route_edit(draft)
	if bool(result.get("ok", false)):
		_push_ui_event("transport_session_route_edit", result.get("session", {}))
		_emit_changed()
	return result


func update_transport_session_route_settings(fleet_size: int, headway_minutes: int, fare: int) -> Dictionary:
	if transport_planning_session == null or not transport_planning_session.is_route_package():
		return {"ok": false, "error": "transport_session_not_route_package"}
	var result: Dictionary = transport_planning_session.update_route_draft({
		"fleet_size": clampi(fleet_size, 1, 40),
		"headway_minutes": clampi(headway_minutes, 1, 60),
		"fare": clampi(fare, 0, 500),
	})
	if bool(result.get("ok", false)):
		_emit_changed()
	return result


func transport_session_package_quote(city_grid: Array = []) -> Dictionary:
	return _build_transport_session_package_quote(city_grid, true)


func _build_transport_session_package_quote(city_grid: Array, cache_corridor_quote: bool) -> Dictionary:
	if transport_planning_session == null or not transport_planning_session.is_route_package():
		return {"ok": false, "error": "transport_session_not_route_package"}
	var current: Dictionary = transport_planning_session.snapshot()
	if str(current.get("state", "")) != TransportPlanningSessionScript.STATE_ROUTE_EDIT:
		return {"ok": false, "error": "transport_session_not_editing_route"}
	var route_draft: Dictionary = current.get("route_draft", {})
	var placements: Array = Array(route_draft.get("station_placements", [])).duplicate(true)
	var minimum_stops := int(TransportModesScript.route_spec(str(current.get("mode", ""))).get("minimum_stops", 2))
	if placements.size() < minimum_stops:
		return {"ok": false, "error": "transport_session_requires_more_stations", "required": minimum_stops}
	var occupied_station_tiles: Array[int] = []
	var station_cost := 0
	var normalized_placements: Array = []
	for placement_value: Variant in placements:
		if not placement_value is Dictionary:
			return {"ok": false, "error": "invalid_station_draft"}
		var placement: Dictionary = placement_value
		var reuse_existing := bool(placement.get("reuse_existing_station", false))
		var workers := int(placement.get("worker_count", 0))
		var current_station_id := ""
		var refreshed: Dictionary
		if reuse_existing:
			var reusable := _transport_reusable_station_placement(
				int(placement.get("anchor_tile_id", -1)), current
			)
			if not bool(reusable.get("ok", false)):
				return reusable
			current_station_id = str(Dictionary(reusable.get("station", {})).get("id", ""))
			if current_station_id != str(placement.get("existing_station_id", "")):
				return {"ok": false, "error": "transport_station_reference_changed"}
			refreshed = Dictionary(reusable.get("placement", {})).duplicate(true)
		else:
			refreshed = placement_footprint_quote(
				str(current.get("station_blueprint_name", "")),
				int(placement.get("anchor_tile_id", -1)),
				workers
			)
		if not bool(refreshed.get("ok", false)):
			return refreshed
		if not reuse_existing and str(refreshed.get("library_id", "")) != str(placement.get("library_id", "")):
			return {"ok": false, "error": "transport_session_station_blueprint_changed"}
		for tile_value: Variant in refreshed.get("occupied_tile_ids", []):
			var tile_id := int(tile_value)
			if occupied_station_tiles.has(tile_id):
				return {"ok": false, "error": "station_draft_overlap"}
			occupied_station_tiles.append(tile_id)
		station_cost += 0 if reuse_existing else int(refreshed.get("total_cost", 0))
		var normalized: Dictionary
		if reuse_existing:
			normalized = {
				"anchor_tile_id": int(refreshed.get("anchor_tile_id", -1)),
				"occupied_tile_ids": Array(refreshed.get("occupied_tile_ids", [])).duplicate(),
				"footprint_id": str(refreshed.get("footprint_id", "")),
				"library_id": "",
				"blueprint": Dictionary(refreshed.get("blueprint", {})).duplicate(true),
				"worker_count": 0,
				"building_cost": 0,
				"duration_days": 0,
				"reuse_existing_station": true,
				"existing_station_id": current_station_id,
			}
		else:
			normalized = placement.duplicate(true)
			normalized["blueprint"] = Dictionary(refreshed.get("blueprint", {})).duplicate(true)
			normalized["building_cost"] = int(refreshed.get("total_cost", 0))
			normalized["duration_days"] = int(refreshed.get("duration_days", 0))
			normalized["worker_count"] = workers
		normalized_placements.append(normalized)
	var network_draft: Dictionary = current.get("network_draft", {})
	var network_kind := str(network_draft.get("kind", ""))
	var route_tiles: Array = Array(network_draft.get("tile_ids", [])).duplicate()
	if route_tiles.is_empty():
		return {"ok": false, "error": "transport_session_network_required"}
	var occupied_tiles: Array[int] = _transport_occupied_tile_ids(city_grid)
	for station_tile: int in occupied_station_tiles:
		if not occupied_tiles.has(station_tile):
			occupied_tiles.append(station_tile)
	var network_revision: String = str(transport.authority_revision())
	var model_quote: Dictionary = transport.quote_completed_corridor(
		str(current.get("mode", "")),
		route_tiles,
		terrain_map,
		occupied_tiles,
		_transport_construction_tile_ids()
	)
	if not bool(model_quote.get("ok", false)):
		return _transport_public_quote_error(model_quote)
	var plan: Dictionary = Dictionary(model_quote.get("plan", {})).duplicate(true)
	var corridor_quote: Dictionary = Dictionary(model_quote.get("corridor_quote", {})).duplicate(true)
	var corridor_quote_validation := TransportModesScript.validate_route_package_corridor_price_quote(corridor_quote)
	if not bool(corridor_quote_validation.get("valid", false)):
		return {"ok": false, "error": "transport_package_invalid_corridor_quote"}
	var route_construction_cost := int(Dictionary(model_quote.get("breakdown", {})).get("segments", 0))
	var route_monthly_maintenance := int(Dictionary(model_quote.get("maintenance_breakdown", {})).get("segments", 0))
	var segments: Array = Array(plan.get("segments", [])).duplicate(true)
	var crossing_tiles: Array = Array(model_quote.get("crossing_tile_ids", [])).duplicate()
	var crossing_cost := crossing_tiles.size() * TransportModesScript.LEVEL_CROSSING_BUILD_COST
	var support_plans: Array = []
	var support_cost := 0
	var support_maintenance := 0
	var mode_spec := TransportModesScript.route_spec(str(current.get("mode", "")))
	var depot_kind := str(mode_spec.get("required_depot_kind", ""))
	if not depot_kind.is_empty() and not _transport_package_has_connected_support(depot_kind, network_kind, route_tiles, plan, occupied_tiles):
		var support_tile := _transport_package_support_tile(route_tiles, occupied_tiles)
		if support_tile < 0:
			return {"ok": false, "error": "transport_package_support_tile_required", "support_kind": depot_kind}
		var support_plan := _transport_plan_for_tiles(depot_kind, "build", [support_tile])
		var support_quote: Dictionary = transport.quote_project(
			"build", support_plan, terrain_map, occupied_tiles, _transport_construction_tile_ids()
		)
		if not bool(support_quote.get("ok", false)):
			return _transport_public_quote_error(support_quote)
		support_plan = Dictionary(support_quote.get("plan", {})).duplicate(true)
		support_plans.append({"kind": depot_kind, "plan": support_plan, "tile_ids": [support_tile]})
		support_cost += int(support_quote.get("total_cost", 0))
		support_maintenance += int(TransportModesScript.facility_spec(depot_kind).get("monthly_maintenance", 0))
	var total_cost := station_cost + route_construction_cost + support_cost + crossing_cost
	var crossing_maintenance := crossing_tiles.size() * TransportModesScript.LEVEL_CROSSING_MONTHLY_MAINTENANCE
	var available_workers := int(construction.available_workers())
	var workers_per_network_job := int(network_draft.get("worker_count", 5))
	var requested_workers := workers_per_network_job * ((1 if not segments.is_empty() else 0) + support_plans.size())
	for placement: Dictionary in normalized_placements:
		if not bool(placement.get("reuse_existing_station", false)):
			requested_workers += int(placement.get("worker_count", 0))
	var result := {
		"ok": true,
		"workflow": TransportPlanningSessionScript.WORKFLOW_ROUTE_PACKAGE_V1,
		"price_model": TransportModesScript.ROUTE_PACKAGE_REUSE_PRICE_MODEL,
		"price_provenance": TransportModesScript.ROUTE_PACKAGE_REUSE_PRICE_PROVENANCE,
		"quote_network_revision": network_revision,
		"corridor_quote": corridor_quote,
		"corridor_contract": Dictionary(corridor_quote.get("corridor", {})).duplicate(true),
		"mode": str(current.get("mode", "")),
		"network_kind": network_kind,
		"route_tile_ids": route_tiles,
		"route_tile_count": route_tiles.size(),
		"station_placements": normalized_placements,
		"route_project_plan": plan,
		"support_plans": support_plans,
		"worker_count": workers_per_network_job,
		"available_workers": available_workers,
		"requested_workers": requested_workers,
		"station_building_cost": station_cost,
		"route_construction_cost": route_construction_cost,
		"support_facility_cost": support_cost,
		"level_crossing_cost": crossing_cost,
		"total_cost": total_cost,
		"route_monthly_maintenance": route_monthly_maintenance,
		"support_monthly_maintenance": support_maintenance,
		"level_crossing_monthly_maintenance": crossing_maintenance,
		"total_monthly_maintenance": route_monthly_maintenance + support_maintenance + crossing_maintenance,
		"crossing_tile_ids": crossing_tiles,
		"can_afford": treasury_balance() >= total_cost,
		"can_start": treasury_balance() >= total_cost and available_workers >= requested_workers,
	}
	if cache_corridor_quote:
		var cache_result: Dictionary = transport_planning_session.update_route_draft({
			"corridor_quote": corridor_quote,
			"corridor_network_revision": network_revision,
		})
		if not bool(cache_result.get("ok", false)):
			return cache_result
	return result


func start_transport_session_package(city_grid: Array = [], _failure_injection_stage: String = "") -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	if not _failure_injection_stage.is_empty() and (
		not OS.is_debug_build() or _failure_injection_stage != "after_first_candidate_project"
	):
		return {"ok": false, "error": "invalid_transport_package_failure_injection"}
	var current_draft: Dictionary = Dictionary(transport_planning_session.snapshot().get("route_draft", {}))
	var cached_quote_value: Variant = current_draft.get("corridor_quote", null)
	var cached_revision := str(current_draft.get("corridor_network_revision", ""))
	if cached_quote_value != null:
		var cached_validation := TransportModesScript.validate_route_package_corridor_price_quote(cached_quote_value)
		if not bool(cached_validation.get("valid", false)):
			return {"ok": false, "error": "transport_package_cached_quote_invalid"}
		if cached_revision.length() != 64 or not cached_revision.is_valid_hex_number(false):
			return {"ok": false, "error": "transport_package_cached_revision_invalid"}
	var quote := _build_transport_session_package_quote(city_grid, false)
	if not bool(quote.get("ok", false)):
		return quote
	if cached_quote_value != null and (
		cached_revision != str(quote.get("quote_network_revision", ""))
		or cached_quote_value != quote.get("corridor_quote", null)
	):
		return {"ok": false, "error": "transport_package_quote_stale"}
	var precommit_validation := _validate_transport_package_quote_for_commit(quote, city_grid)
	if not bool(precommit_validation.get("ok", false)):
		return precommit_validation
	var total_cost := int(quote.get("total_cost", 0))
	if treasury_balance() < total_cost:
		return {"ok": false, "error": "insufficient_treasury", "required": total_cost}
	if int(quote.get("available_workers", 0)) < int(quote.get("requested_workers", 0)):
		return {"ok": false, "error": "insufficient_workers"}
	var candidate_envelope = session.make_envelope()
	var candidate_metadata: Dictionary = Dictionary(candidate_envelope.state.get("metadata", {})).duplicate(true)
	candidate_metadata["vertical_slice"] = _vertical_slice_subsystem_snapshot()
	candidate_envelope.state["metadata"] = candidate_metadata
	var candidate_core = GameSessionScript.new(1, 0)
	if not candidate_core.restore_envelope(candidate_envelope):
		return {"ok": false, "error": "transport_package_candidate_clone_failed"}
	var candidate_construction = ConstructionSystemScript.create_from_dict(construction.to_dict())
	var candidate_transport = TransportNetworkSystemScript.create_from_dict(transport.to_dict())
	var candidate_planning = TransportPlanningSessionScript.create_from_dict(transport_planning_session.to_dict())
	var candidate_blueprints = BlueprintLibraryServiceScript.new()
	var library_snapshot := blueprint_library_service.snapshot()
	candidate_blueprints.restore(
		int(library_snapshot.get("next_blueprint_sequence", 1)),
		Dictionary(library_snapshot.get("blueprint_library", {})),
		Dictionary(library_snapshot.get("active_blueprint_by_building", {})),
		building_definitions
	)
	if candidate_construction == null:
		return {"ok": false, "error": "transport_package_construction_clone_failed"}
	if candidate_transport == null:
		return {"ok": false, "error": "transport_package_transport_clone_failed"}
	if candidate_planning == null:
		return {
			"ok": false,
			"error": "transport_package_planning_clone_failed",
			"validation": TransportPlanningSessionScript.validate_snapshot(transport_planning_session.to_dict()),
		}
	var station_jobs: Array = []
	var placements: Array = Array(quote.get("station_placements", [])).duplicate(true)
	for placement_value: Variant in placements:
		var placement: Dictionary = placement_value
		if bool(placement.get("reuse_existing_station", false)):
			continue
		var blueprint: Dictionary = Dictionary(placement.get("blueprint", {})).duplicate(true)
		var library_id := str(placement.get("library_id", ""))
		var anchor := int(placement.get("anchor_tile_id", -1))
		var started: Dictionary = candidate_construction.start_reusable_blueprint_job(
			library_id,
			blueprint,
			int(placement.get("worker_count", 0)),
			game_day(),
			"tile_%02d" % anchor,
			{
				"tile_index": anchor,
				"anchor_tile_id": anchor,
				"footprint_id": str(placement.get("footprint_id", "")),
				"occupied_tile_ids": Array(placement.get("occupied_tile_ids", [])).duplicate(),
				"building_name": str(transport_planning_session.snapshot().get("station_blueprint_name", "")),
			}
		)
		if not bool(started.get("ok", false)):
			return {"ok": false, "error": str(started.get("error", "transport_package_station_preflight_failed"))}
		if not candidate_blueprints.record_usage(library_id, game_day()):
			return {"ok": false, "error": "transport_package_blueprint_usage_failed"}
		station_jobs.append(Dictionary(started.get("job", {})).duplicate(true))
	var network_jobs: Array = []
	var all_project_specs: Array = []
	if not Array(Dictionary(quote.get("route_project_plan", {})).get("segments", [])).is_empty():
		all_project_specs.append({
			"kind": str(quote.get("network_kind", "")),
			"plan": Dictionary(quote.get("route_project_plan", {})).duplicate(true),
			"corridor": true,
		})
	all_project_specs.append_array(Array(quote.get("support_plans", [])).duplicate(true))
	var candidate_occupied: Array[int] = _transport_occupied_tile_ids(city_grid)
	var candidate_construction_tiles: Array[int] = _transport_construction_tile_ids()
	for placement: Dictionary in placements:
		for tile_value: Variant in placement.get("occupied_tile_ids", []):
			var tile_id := int(tile_value)
			if not candidate_occupied.has(tile_id):
				candidate_occupied.append(tile_id)
			if not candidate_construction_tiles.has(tile_id):
				candidate_construction_tiles.append(tile_id)
	for spec_value: Variant in all_project_specs:
		var spec: Dictionary = spec_value
		var kind := str(spec.get("kind", ""))
		var plan: Dictionary = Dictionary(spec.get("plan", {})).duplicate(true)
		var planned: Dictionary = candidate_transport.plan_project(
			"build", plan, terrain_map, candidate_occupied, candidate_construction_tiles
		)
		if not bool(planned.get("ok", false)):
			return _transport_public_quote_error(planned)
		var project: Dictionary = planned.get("project", {})
		var project_id := str(project.get("id", ""))
		var project_tiles := _transport_project_tile_indices("build", Dictionary(project.get("plan", {})))
		var started_project: Dictionary = candidate_transport.start_project(project_id)
		if not bool(started_project.get("ok", false)):
			return started_project
		var job_result: Dictionary = candidate_construction.start_infrastructure_job(
			"build", kind, project_tiles, int(quote.get("worker_count", 5)), game_day(),
			{
				"project_id": project_id,
				"transport_project_id": project_id,
				"transport_kind": kind,
				"source_decision_id": str(project.get("plan", {}).get("source_decision_id", "")),
			}
		)
		if not bool(job_result.get("ok", false)):
			return job_result
		var job: Dictionary = job_result.get("job", {})
		var segment_refs: Array = []
		for segment_value: Variant in Dictionary(project.get("plan", {})).get("segments", []):
			if segment_value is Dictionary:
				segment_refs.append({
					"id": str((segment_value as Dictionary).get("id", "")),
					"kind": str((segment_value as Dictionary).get("kind", "")),
					"tile_ids": Array((segment_value as Dictionary).get("tile_path", [])).duplicate(),
				})
		network_jobs.append({
			"kind": kind,
			"project": Dictionary(started_project.get("project", project)).duplicate(true),
			"job": job.duplicate(true),
			"segment_refs": segment_refs,
		})
		for tile_id: int in project_tiles:
			if not candidate_construction_tiles.has(tile_id):
				candidate_construction_tiles.append(tile_id)
		if _failure_injection_stage == "after_first_candidate_project":
			return {"ok": false, "error": "transport_package_injected_candidate_failure"}
	var reused_network_refs := _transport_package_reused_network_refs(quote)
	if reused_network_refs.is_empty() and not Array(
		Dictionary(quote.get("corridor_contract", {})).get("reused_segment_refs", [])
	).is_empty():
		return {"ok": false, "error": "transport_package_reused_refs_missing"}
	var planned_session: Dictionary = candidate_planning.record_route_package_jobs(
		station_jobs,
		placements,
		network_jobs,
		_transport_package_persisted_quote(quote, network_jobs, station_jobs, placements),
		reused_network_refs
	)
	if not bool(planned_session.get("ok", false)):
		return planned_session
	var operation_sequence := next_operation_sequence
	var all_jobs: Array = station_jobs.duplicate(true)
	for item: Dictionary in network_jobs:
		all_jobs.append(Dictionary(item.get("job", {})).duplicate(true))
	for job: Dictionary in all_jobs:
		candidate_core.submit_command("upsert_construction", {
			"job_id": str(job.get("id", "")),
			"record": job,
			"reason_tag": "construction.updated",
		}, "transport_package_construction_%06d" % operation_sequence)
		operation_sequence += 1
		if not candidate_core.state.construction_jobs.has(str(job.get("id", ""))):
			return {"ok": false, "error": "transport_package_core_job_preflight_failed"}
	var balance_before := int(candidate_core.state.ledger.get_balance())
	if total_cost > 0:
		candidate_core.submit_command("ledger_post", {
			"amount": -total_cost,
			"reason_tag": "construction.transport_package_total",
			"source_id": str(candidate_planning.snapshot().get("id", "transport_package")),
			"metadata": {
				"price_model": str(quote.get("price_model", "")),
				"price_provenance": str(quote.get("price_provenance", "")),
				"quote_network_revision": str(quote.get("quote_network_revision", "")),
				"classification": str(Dictionary(quote.get("corridor_contract", {})).get("classification", "")),
				"station_building_cost": int(quote.get("station_building_cost", 0)),
				"route_construction_cost": int(quote.get("route_construction_cost", 0)),
				"support_facility_cost": int(quote.get("support_facility_cost", 0)),
				"level_crossing_cost": int(quote.get("level_crossing_cost", 0)),
				"route_monthly_maintenance": int(quote.get("route_monthly_maintenance", 0)),
			},
			"allow_overdraft": false,
		}, "transport_package_ledger_%06d" % operation_sequence)
		operation_sequence += 1
	if int(candidate_core.state.ledger.get_balance()) != balance_before - total_cost:
		return {"ok": false, "error": "transport_package_ledger_preflight_failed"}
	var immediate_route: Dictionary = {}
	if not candidate_planning.has_active_jobs():
		var immediate_result := _materialize_candidate_transport_package(
			candidate_transport,
			candidate_planning,
			quote
		)
		if not bool(immediate_result.get("ok", false)):
			return immediate_result
		immediate_route = Dictionary(immediate_result.get("route", {})).duplicate(true)
	precommit_validation = _validate_transport_package_quote_for_commit(quote, city_grid)
	if not bool(precommit_validation.get("ok", false)):
		return precommit_validation
	# The complete candidate has passed every terrain, occupancy, worker,
	# construction, topology, route-draft, and treasury check. Replace all live
	# authorities only now, so no error path can leave a partial package behind.
	session = candidate_core
	construction = candidate_construction
	transport = candidate_transport
	transport_planning_session = candidate_planning
	blueprint_library_service = candidate_blueprints
	next_operation_sequence = operation_sequence
	for job: Dictionary in all_jobs:
		_push_ui_event("construction_started", {"job": job.duplicate(true), "transport_package": true})
	if not immediate_route.is_empty():
		_record_fact({
			"type": "transport_route_created",
			"subject_id": str(immediate_route.get("id", "")),
			"game_day": game_day(),
			"reason_tag": "transport.route.created",
			"payload": immediate_route.duplicate(true),
		})
		_push_ui_event("transport_package_materialized", {
			"route": immediate_route.duplicate(true),
			"session": transport_planning_session.snapshot(),
		})
	_push_ui_event("transport_package_started", {
		"session": transport_planning_session.snapshot(),
		"total_cost": total_cost,
		"quote": quote.duplicate(true),
	})
	_emit_changed()
	return {
		"ok": true,
		"session": transport_planning_session.snapshot(),
		"quote": quote.duplicate(true),
		"jobs": all_jobs,
		"total_cost": total_cost,
		"route": immediate_route,
	}


func _transport_package_persisted_quote(
	quote: Dictionary,
	network_jobs: Array = [],
	station_jobs: Array = [],
	station_placements: Array = []
) -> Dictionary:
	var new_segment_refs: Array = []
	var new_project_ids: Array[String] = []
	var new_job_ids: Array[String] = []
	for item_value: Variant in network_jobs:
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value
		var project_id := str(Dictionary(item.get("project", {})).get("id", ""))
		var job_id := str(Dictionary(item.get("job", {})).get("id", ""))
		if not project_id.is_empty() and not new_project_ids.has(project_id):
			new_project_ids.append(project_id)
		if not job_id.is_empty() and not new_job_ids.has(job_id):
			new_job_ids.append(job_id)
		for segment_ref_value: Variant in item.get("segment_refs", []):
			if segment_ref_value is Dictionary:
				var segment_ref: Dictionary = (segment_ref_value as Dictionary).duplicate(true)
				segment_ref["project_id"] = project_id
				segment_ref["job_id"] = job_id
				new_segment_refs.append(segment_ref)
	for station_job_value: Variant in station_jobs:
		if station_job_value is Dictionary:
			var station_job_id := str((station_job_value as Dictionary).get("id", ""))
			if not station_job_id.is_empty() and not new_job_ids.has(station_job_id):
				new_job_ids.append(station_job_id)
	var blueprint_usage_before: Array = []
	for placement_value: Variant in station_placements:
		if not placement_value is Dictionary or bool((placement_value as Dictionary).get("reuse_existing_station", false)):
			continue
		var library_id := str((placement_value as Dictionary).get("library_id", ""))
		if library_id.is_empty() or not blueprint_library_service.blueprint_library.has(library_id):
			continue
		var library_entry: Dictionary = blueprint_library_service.blueprint_library[library_id]
		blueprint_usage_before.append({
			"library_id": library_id,
			"usage_count": int(library_entry.get("usage_count", 0)),
			"had_last_used_day": library_entry.has("last_used_day"),
			"last_used_day": int(library_entry.get("last_used_day", 0)),
		})
	var corridor_quote: Dictionary = Dictionary(quote.get("corridor_quote", {})).duplicate(true)
	return {
		"workflow": str(quote.get("workflow", "")),
		"price_model": str(quote.get("price_model", "")),
		"price_provenance": str(quote.get("price_provenance", "")),
		"quote_network_revision": str(quote.get("quote_network_revision", "")),
		"corridor_quote": corridor_quote,
		"price_breakdown": Dictionary(corridor_quote.get("price_breakdown", {})).duplicate(true),
		"maintenance_breakdown": Dictionary(corridor_quote.get("maintenance_breakdown", {})).duplicate(true),
		"reused_segment_refs": Array(Dictionary(corridor_quote.get("corridor", {})).get("reused_segment_refs", [])).duplicate(true),
		"new_segment_refs": new_segment_refs,
		"new_project_ids": new_project_ids,
		"new_job_ids": new_job_ids,
		"blueprint_usage_before": blueprint_usage_before,
		"mode": str(quote.get("mode", "")),
		"network_kind": str(quote.get("network_kind", "")),
		"route_tile_count": int(quote.get("route_tile_count", 0)),
		"station_building_cost": int(quote.get("station_building_cost", 0)),
		"route_construction_cost": int(quote.get("route_construction_cost", 0)),
		"support_facility_cost": int(quote.get("support_facility_cost", 0)),
		"level_crossing_cost": int(quote.get("level_crossing_cost", 0)),
		"total_cost": int(quote.get("total_cost", 0)),
		"route_monthly_maintenance": int(quote.get("route_monthly_maintenance", 0)),
		"support_monthly_maintenance": int(quote.get("support_monthly_maintenance", 0)),
		"level_crossing_monthly_maintenance": int(quote.get("level_crossing_monthly_maintenance", 0)),
		"total_monthly_maintenance": int(quote.get("total_monthly_maintenance", 0)),
		"crossing_tile_ids": Array(quote.get("crossing_tile_ids", [])).duplicate(),
	}


func _validate_transport_package_quote_for_commit(quote: Dictionary, city_grid: Array) -> Dictionary:
	var corridor_validation := TransportModesScript.validate_route_package_corridor_price_quote(
		quote.get("corridor_quote", null)
	)
	if not bool(corridor_validation.get("valid", false)):
		return {"ok": false, "error": "transport_package_quote_invalid"}
	var quoted_revision := str(quote.get("quote_network_revision", ""))
	if quoted_revision.is_empty() or quoted_revision != transport.authority_revision():
		return {"ok": false, "error": "transport_package_network_revision_stale"}
	var fresh := _build_transport_session_package_quote(city_grid, false)
	if not bool(fresh.get("ok", false)):
		return fresh
	if fresh != quote:
		return {"ok": false, "error": "transport_package_quote_stale"}
	return {"ok": true}


func _transport_package_reused_network_refs(quote: Dictionary) -> Array:
	var result: Array = []
	var corridor: Dictionary = quote.get("corridor_contract", {})
	for ref_value: Variant in corridor.get("reused_segment_refs", []):
		if not ref_value is Dictionary:
			return []
		var ref: Dictionary = ref_value
		var segment_id := str(ref.get("id", ""))
		if not transport.segments.has(segment_id) or not transport.segments[segment_id] is Dictionary:
			return []
		var segment: Dictionary = transport.segments[segment_id]
		if (
			str(segment.get("status", "")) != "completed"
			or str(segment.get("kind", "")) != str(ref.get("kind", ""))
		):
			return []
		result.append({
			"project_id": str(segment.get("project_id", "")),
			"job_id": "",
			"segment_id": segment_id,
			"kind": str(ref.get("kind", "")),
			"tile_ids": Array(ref.get("tile_ids", [])).duplicate(),
			"status": "completed",
			"source": "existing",
		})
	var mode_spec: Dictionary = TransportModesScript.route_spec(str(quote.get("mode", "")))
	var depot_kind := str(mode_spec.get("required_depot_kind", ""))
	if not depot_kind.is_empty() and Array(quote.get("support_plans", [])).is_empty():
		var guideway_kind := str(mode_spec.get("guideway_kind", ""))
		var route_tiles: Array = Dictionary(quote.get("corridor_contract", {})).get("route_tile_ids", [])
		var facility_ids: Array[String] = []
		for facility_id_value: Variant in transport.facilities.keys():
			facility_ids.append(str(facility_id_value))
		facility_ids.sort()
		for facility_id: String in facility_ids:
			var facility: Dictionary = transport.facilities[facility_id]
			if str(facility.get("kind", "")) != depot_kind or str(facility.get("status", "completed")) != "completed":
				continue
			var isolated = TransportNetworkSystemScript.create_from_dict(transport.to_dict())
			if isolated == null:
				return []
			for other_id_value: Variant in isolated.facilities.keys():
				var other_id := str(other_id_value)
				if other_id != facility_id and str(Dictionary(isolated.facilities[other_id]).get("kind", "")) == depot_kind:
					isolated.facilities.erase(other_id)
			if not bool(isolated.call("_has_connected_depot", depot_kind, guideway_kind, route_tiles)):
				continue
			result.append({
				"project_id": str(facility.get("project_id", "")),
				"job_id": "",
				"entity_id": facility_id,
				"kind": depot_kind,
				"status": "completed",
				"source": "existing_support",
			})
			break
	return result


func _transport_route_metadata_from_package_quote(package_quote: Dictionary) -> Dictionary:
	return {
		"price_model": str(package_quote.get("price_model", "")),
		"price_provenance": str(package_quote.get("price_provenance", "")),
		"route_tile_count": int(package_quote.get("route_tile_count", 0)),
		"route_construction_cost": int(package_quote.get("route_construction_cost", 0)),
		"route_monthly_maintenance": int(package_quote.get("route_monthly_maintenance", 0)),
		"quote_network_revision": str(package_quote.get("quote_network_revision", "")),
		"corridor_quote": Dictionary(package_quote.get("corridor_quote", {})).duplicate(true),
		"reused_segment_refs": Array(package_quote.get("reused_segment_refs", [])).duplicate(true),
		"new_segment_refs": Array(package_quote.get("new_segment_refs", [])).duplicate(true),
		"new_project_ids": Array(package_quote.get("new_project_ids", [])).duplicate(),
		"new_job_ids": Array(package_quote.get("new_job_ids", [])).duplicate(),
		"price_breakdown": Dictionary(package_quote.get("price_breakdown", {})).duplicate(true),
		"maintenance_breakdown": Dictionary(package_quote.get("maintenance_breakdown", {})).duplicate(true),
	}


func _materialize_candidate_transport_package(candidate_transport, candidate_planning, quote: Dictionary) -> Dictionary:
	var current: Dictionary = candidate_planning.snapshot()
	var station_ids: Array = []
	for ref_value: Variant in current.get("station_refs", []):
		if not ref_value is Dictionary or str((ref_value as Dictionary).get("status", "")) != "completed":
			return {"ok": false, "error": "transport_package_station_not_completed"}
		station_ids.append(str((ref_value as Dictionary).get("station_id", "")))
	var route_draft: Dictionary = current.get("route_draft", {})
	var route_plan := {
		"name": "%s %02d" % [_transport_route_mode_label(str(current.get("mode", ""))), int(candidate_transport.next_route_sequence)],
		"mode": str(current.get("mode", "")),
		"stop_ids": station_ids,
		"fleet_size": int(route_draft.get("fleet_size", 2)),
		"headway_minutes": int(route_draft.get("headway_minutes", 10)),
		"fare": int(route_draft.get("fare", 30)),
		"enabled": true,
	}
	var persisted_quote := quote if quote.has("new_segment_refs") else _transport_package_persisted_quote(quote)
	route_plan.merge(_transport_route_metadata_from_package_quote(persisted_quote), true)
	var route_validation: Dictionary = candidate_transport.route_quote(route_plan)
	if not bool(route_validation.get("ok", false)) or not bool(route_validation.get("valid", false)):
		return {
			"ok": false,
			"error": "transport_route_invalid",
			"validation_errors": Array(route_validation.get("validation_errors", [])).duplicate(),
		}
	var created: Dictionary = candidate_transport.create_route(route_plan)
	if not bool(created.get("ok", false)) or not bool(created.get("valid", false)):
		return created
	var route: Dictionary = created.get("route", {})
	var recorded: Dictionary = candidate_planning.record_route(route)
	if not bool(recorded.get("ok", false)):
		return recorded
	return {"ok": true, "route": route.duplicate(true)}


func materialize_transport_session_route(
	station_tile_ids: Array,
	fleet_size: int,
	headway_minutes: int,
	fare: int,
	city_grid: Array = []
) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	var current: Dictionary = transport_planning_session.snapshot()
	var draft := {
		"mode": str(current.get("mode", "")),
		"station_tile_ids": station_tile_ids.duplicate(),
		"fleet_size": fleet_size,
		"headway_minutes": headway_minutes,
		"fare": fare,
	}
	var draft_result: Dictionary = transport_planning_session.update_route_draft(draft)
	if not bool(draft_result.get("ok", false)):
		return draft_result
	var created: Dictionary = create_transport_route(
		str(current.get("mode", "")),
		station_tile_ids,
		fleet_size,
		headway_minutes,
		fare,
		city_grid
	)
	if not bool(created.get("ok", false)):
		# Preserve the attempted route for correction while explicitly reporting
		# that topology, references, construction, and treasury remain untouched.
		created["draft_retained"] = true
		created["authoritative_changes_applied"] = false
		created["session"] = transport_planning_session.snapshot()
		return created
	var recorded: Dictionary = transport_planning_session.record_route(Dictionary(created.get("route", {})))
	if not bool(recorded.get("ok", false)):
		push_error("Transport planning session failed to record a created route.")
		return {"ok": false, "error": "transport_session_record_failed"}
	created["session"] = transport_planning_session.snapshot()
	_emit_changed()
	return created


func wait_for_transport_session_construction(resume_state: String = "network_placement") -> Dictionary:
	var result: Dictionary = transport_planning_session.wait_for_construction(resume_state)
	if bool(result.get("ok", false)):
		_emit_changed()
	return result


func pause_transport_planning_session() -> Dictionary:
	var result: Dictionary = transport_planning_session.pause()
	if bool(result.get("ok", false)):
		_emit_changed()
	return result


func resume_transport_planning_session() -> Dictionary:
	var result: Dictionary = transport_planning_session.resume()
	if bool(result.get("ok", false)):
		_emit_changed()
	return result


func close_transport_planning_session(reason: String = "player_closed") -> Dictionary:
	var result: Dictionary = transport_planning_session.close(reason)
	if bool(result.get("ok", false)):
		_push_ui_event("transport_planning_session_closed", result.get("session", {}))
		_emit_changed()
	return result


func cancel_transport_planning_session() -> Dictionary:
	var planning_snapshot: Dictionary = transport_planning_session.snapshot()
	var package_quote: Dictionary = Dictionary(planning_snapshot.get("route_draft", {})).get("package_quote", {})
	if package_quote.is_empty():
		return close_transport_planning_session("player_cancelled_planning")
	if not Dictionary(planning_snapshot.get("route_ref", {})).is_empty():
		return {"ok": false, "error": "transport_package_already_materialized"}
	var candidate_envelope = session.make_envelope()
	var candidate_metadata: Dictionary = Dictionary(candidate_envelope.state.get("metadata", {})).duplicate(true)
	candidate_metadata["vertical_slice"] = _vertical_slice_subsystem_snapshot()
	candidate_envelope.state["metadata"] = candidate_metadata
	var candidate_core = GameSessionScript.new(1, 0)
	if not candidate_core.restore_envelope(candidate_envelope):
		return {"ok": false, "error": "transport_package_rollback_core_clone_failed"}
	var candidate_construction = ConstructionSystemScript.create_from_dict(construction.to_dict())
	var candidate_transport = TransportNetworkSystemScript.create_from_dict(transport.to_dict())
	var candidate_planning = TransportPlanningSessionScript.create_from_dict(transport_planning_session.to_dict())
	var candidate_population = PopulationSystemScript.from_dict(population.to_dict())
	var candidate_durability = DurabilitySystemScript.create_from_dict(durability.to_dict())
	var candidate_blueprints = BlueprintLibraryServiceScript.new()
	var library_snapshot := blueprint_library_service.snapshot()
	candidate_blueprints.restore(
		int(library_snapshot.get("next_blueprint_sequence", 1)),
		Dictionary(library_snapshot.get("blueprint_library", {})),
		Dictionary(library_snapshot.get("active_blueprint_by_building", {})),
		building_definitions
	)
	if candidate_construction == null or candidate_transport == null or candidate_planning == null or candidate_population == null or candidate_durability == null:
		return {"ok": false, "error": "transport_package_rollback_clone_failed"}
	var new_job_ids: Array[String] = []
	for job_id_value: Variant in package_quote.get("new_job_ids", []):
		var job_id := str(job_id_value)
		if job_id.is_empty() or new_job_ids.has(job_id):
			return {"ok": false, "error": "transport_package_rollback_job_manifest_invalid"}
		new_job_ids.append(job_id)
	var operation_sequence := next_operation_sequence
	var station_refs_by_job: Dictionary = {}
	for station_ref_value: Variant in planning_snapshot.get("station_refs", []):
		if station_ref_value is Dictionary:
			var station_job_id := str((station_ref_value as Dictionary).get("job_id", ""))
			if not station_job_id.is_empty():
				station_refs_by_job[station_job_id] = station_ref_value
	for job_id: String in new_job_ids:
		if not candidate_construction.jobs.has(job_id):
			return {"ok": false, "error": "transport_package_rollback_job_missing", "job_id": job_id}
		var job: Dictionary = candidate_construction.jobs[job_id]
		var job_status := str(job.get("status", ""))
		if job_status == "active":
			var cancelled: Dictionary = candidate_construction.cancel_job(job_id, game_day())
			if not bool(cancelled.get("ok", false)):
				return cancelled
		elif job_status == "completed" and station_refs_by_job.has(job_id):
			var station_ref: Dictionary = station_refs_by_job[job_id]
			var station_id := str(station_ref.get("station_id", ""))
			if station_id.is_empty() or not candidate_core.state.buildings.has(station_id):
				return {"ok": false, "error": "transport_package_rollback_station_missing", "job_id": job_id}
			var building: Dictionary = candidate_core.state.buildings[station_id]
			var resident_ids := PackedStringArray()
			for resident_id_value: Variant in building.get("resident_ids", []):
				resident_ids.append(str(resident_id_value))
			var removed_residents: PackedStringArray = candidate_population.remove_residents_by_id(
				resident_ids, game_day(), "population.transport_package_rolled_back"
			)
			if removed_residents.size() != resident_ids.size():
				return {"ok": false, "error": "transport_package_rollback_population_mismatch", "job_id": job_id}
			for resident_id: String in removed_residents:
				candidate_core.submit_command("remove_npc", {
					"npc_id": resident_id,
					"reason_tag": "population.transport_package_rolled_back",
				}, "transport_package_rollback_npc_%06d" % operation_sequence)
				operation_sequence += 1
			if int(candidate_core.state.metrics.get("population", -1)) != candidate_population.population_count():
				candidate_core.submit_command("metric_change", {
					"metric": "population",
					"value": candidate_population.population_count(),
					"reason_tag": "population.transport_package_rolled_back",
				}, "transport_package_rollback_population_%06d" % operation_sequence)
				operation_sequence += 1
			if not bool(candidate_durability.unregister_building(station_id).get("ok", false)):
				return {"ok": false, "error": "transport_package_rollback_durability_missing", "job_id": job_id}
			if not bool(candidate_transport.unregister_station(station_id)):
				return {"ok": false, "error": "transport_package_rollback_station_authority_missing", "job_id": job_id}
			candidate_core.submit_command("remove_building", {
				"building_id": station_id,
				"reason_tag": "building.transport_package_rolled_back",
			}, "transport_package_rollback_building_%06d" % operation_sequence)
			operation_sequence += 1
			if candidate_core.state.buildings.has(station_id):
				return {"ok": false, "error": "transport_package_rollback_building_failed", "job_id": job_id}
		elif job_status not in ["completed", "cancelled"]:
			return {"ok": false, "error": "transport_package_rollback_job_status_invalid", "job_id": job_id}
		candidate_construction.jobs.erase(job_id)
		if candidate_core.state.construction_jobs.has(job_id):
			candidate_core.submit_command("remove_construction", {
				"job_id": job_id,
				"reason_tag": "construction.transport_package_rolled_back",
			}, "transport_package_rollback_job_%06d" % operation_sequence)
			operation_sequence += 1
		if candidate_core.state.construction_jobs.has(job_id):
			return {"ok": false, "error": "transport_package_rollback_core_job_failed", "job_id": job_id}
	var new_project_ids: Array = Array(package_quote.get("new_project_ids", [])).duplicate()
	var rolled_back_projects: Dictionary = candidate_transport.rollback_build_projects(new_project_ids)
	if not bool(rolled_back_projects.get("ok", false)):
		return rolled_back_projects
	for usage_value: Variant in package_quote.get("blueprint_usage_before", []):
		if not usage_value is Dictionary:
			return {"ok": false, "error": "transport_package_rollback_blueprint_manifest_invalid"}
		var usage: Dictionary = usage_value
		var library_id := str(usage.get("library_id", ""))
		if library_id.is_empty() or not candidate_blueprints.blueprint_library.has(library_id):
			return {"ok": false, "error": "transport_package_rollback_blueprint_missing"}
		var library_entry: Dictionary = candidate_blueprints.blueprint_library[library_id]
		library_entry["usage_count"] = int(usage.get("usage_count", 0))
		if bool(usage.get("had_last_used_day", false)):
			library_entry["last_used_day"] = int(usage.get("last_used_day", 0))
		else:
			library_entry.erase("last_used_day")
		candidate_blueprints.blueprint_library[library_id] = library_entry
	var total_cost := int(package_quote.get("total_cost", 0))
	if total_cost > 0:
		var balance_before := int(candidate_core.state.ledger.get_balance())
		candidate_core.submit_command("ledger_post", {
			"amount": total_cost,
			"reason_tag": "construction.transport_package_rollback",
			"source_id": str(planning_snapshot.get("id", "transport_package")),
			"metadata": {
				"original_price_model": str(package_quote.get("price_model", "")),
				"original_quote_network_revision": str(package_quote.get("quote_network_revision", "")),
			},
			"allow_overdraft": true,
		}, "transport_package_rollback_ledger_%06d" % operation_sequence)
		operation_sequence += 1
		if int(candidate_core.state.ledger.get_balance()) != balance_before + total_cost:
			return {"ok": false, "error": "transport_package_rollback_ledger_failed"}
	var closed: Dictionary = candidate_planning.rollback_route_package()
	if not bool(closed.get("ok", false)):
		return closed
	session = candidate_core
	construction = candidate_construction
	transport = candidate_transport
	transport_planning_session = candidate_planning
	blueprint_library_service = candidate_blueprints
	population = candidate_population
	durability = candidate_durability
	next_operation_sequence = operation_sequence
	_push_ui_event("transport_package_rolled_back", {
		"session": transport_planning_session.snapshot(),
		"job_ids": new_job_ids.duplicate(),
		"project_ids": new_project_ids.duplicate(),
		"refunded_cost": total_cost,
	})
	_emit_changed()
	return {
		"ok": true,
		"session": transport_planning_session.snapshot(),
		"rolled_back_job_ids": new_job_ids.duplicate(),
		"rolled_back_project_ids": new_project_ids.duplicate(),
		"refunded_cost": total_cost,
	}


func start_transport_project(
	kind: String,
	operation: String,
	tile_ids: Array,
	worker_count: int = 5,
	city_grid: Array = []
) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	var quote := transport_project_quote(kind, operation, tile_ids, worker_count, city_grid)
	if not bool(quote.get("ok", false)):
		return quote
	if int(quote.get("available_workers", 0)) < worker_count:
		return {"ok": false, "error": "insufficient_workers"}
	var total_cost := int(quote.get("total_cost", 0))
	if treasury_balance() < total_cost:
		return {"ok": false, "error": "insufficient_treasury", "required": total_cost}
	var plan: Dictionary = Dictionary(quote.get("project_plan", {})).duplicate(true)
	var planned: Dictionary = transport.plan_project(
		operation,
		plan,
		terrain_map,
		_transport_occupied_tile_ids(city_grid),
		_transport_construction_tile_ids()
	)
	if not bool(planned.get("ok", false)):
		return _transport_public_quote_error(planned)
	var project: Dictionary = planned.get("project", {})
	var project_id := str(project.get("id", ""))
	var project_tiles := _transport_project_tile_indices(operation, Dictionary(project.get("plan", {})))
	var started_project: Dictionary = transport.start_project(project_id)
	if not bool(started_project.get("ok", false)):
		transport.projects.erase(project_id)
		return started_project
	var job_result: Dictionary = construction.start_infrastructure_job(
		operation,
		str(quote.get("kind", kind)),
		project_tiles,
		worker_count,
		game_day(),
		{
			"project_id": project_id,
			"transport_project_id": project_id,
			"transport_kind": str(quote.get("kind", kind)),
			"source_decision_id": str(project.get("plan", {}).get("source_decision_id", "")),
		}
	)
	if not bool(job_result.get("ok", false)):
		transport.projects.erase(project_id)
		return job_result
	var job: Dictionary = job_result.get("job", {})
	_post_ledger(-total_cost, "construction.transport_total_cost", str(job.get("id", project_id)), {
		"project_id": project_id,
		"transport_kind": str(quote.get("kind", kind)),
		"network_cost": int(quote.get("network_cost", 0)),
		"labor_cost": int(job.get("projected_labor_cost", 0)),
	})
	_upsert_construction(job)
	_push_ui_event("transport_project_started", {
		"project": Dictionary(started_project.get("project", project)).duplicate(true),
		"job": job.duplicate(true),
		"total_cost": total_cost,
	})
	_emit_changed()
	return {
		"ok": true,
		"project": Dictionary(started_project.get("project", project)).duplicate(true),
		"job": job.duplicate(true),
		"total_cost": total_cost,
	}


func create_transport_route(
	mode: String,
	station_tile_ids: Array,
	fleet_size: int,
	headway_minutes: int,
	fare: int,
	_city_grid: Array = [],
	route_metadata: Dictionary = {}
) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	_reconcile_transport_stations_from_buildings()
	var resolved_stops := _transport_station_ids_for_tiles(mode, station_tile_ids)
	if not bool(resolved_stops.get("ok", false)):
		return resolved_stops
	var route_plan := {
		"name": "%s %02d" % [_transport_route_mode_label(mode), int(transport.next_route_sequence)],
		"mode": mode,
		"stop_ids": Array(resolved_stops.get("stop_ids", [])).duplicate(),
		"fleet_size": fleet_size,
		"headway_minutes": headway_minutes,
		"fare": fare,
		"enabled": true,
	}
	for field_name: String in [
		"price_model", "price_provenance", "route_tile_count", "route_construction_cost",
		"route_monthly_maintenance", "quote_network_revision", "corridor_quote",
		"reused_segment_refs", "new_segment_refs", "new_project_ids", "new_job_ids",
		"price_breakdown", "maintenance_breakdown",
	]:
		if route_metadata.has(field_name):
			route_plan[field_name] = route_metadata[field_name].duplicate(true) if route_metadata[field_name] is Array or route_metadata[field_name] is Dictionary else route_metadata[field_name]
	var validation: Dictionary = transport.route_quote(route_plan)
	if not bool(validation.get("ok", false)):
		return validation
	if not bool(validation.get("valid", false)):
		return {
			"ok": false,
			"error": "transport_route_invalid",
			"validation_errors": Array(validation.get("validation_errors", [])).duplicate(),
			"route": route_plan,
		}
	var result: Dictionary = transport.create_route(route_plan)
	if not bool(result.get("ok", false)):
		return result
	var route: Dictionary = result.get("route", {})
	_record_fact({
		"type": "transport_route_created",
		"subject_id": str(route.get("id", "")),
		"game_day": game_day(),
		"reason_tag": "transport.route.created",
		"payload": route.duplicate(true),
	})
	_push_ui_event("transport_route_created", route)
	_emit_changed()
	return {"ok": true, "valid": true, "route": route.duplicate(true)}


func _try_materialize_completed_transport_package() -> Dictionary:
	if transport_planning_session == null or not transport_planning_session.is_route_package():
		return {"ok": false, "error": "transport_session_not_route_package"}
	var current: Dictionary = transport_planning_session.snapshot()
	if (
		str(current.get("state", "")) != TransportPlanningSessionScript.STATE_ROUTE_EDIT
		or transport_planning_session.has_active_jobs()
		or not Array(current.get("route_refs", [])).is_empty()
	):
		return {"ok": false, "error": "transport_package_not_ready"}
	var route_draft: Dictionary = current.get("route_draft", {})
	var package_quote: Dictionary = route_draft.get("package_quote", {})
	var reference_validation := TransportPlanningSessionScript.validate_references(
		transport_planning_session.to_dict(),
		construction.to_dict(),
		transport.to_dict(),
		session.state.buildings
	)
	if not bool(reference_validation.get("valid", false)):
		return {
			"ok": false,
			"error": "transport_package_reference_validation_failed",
			"detail": str(reference_validation.get("error", "")),
		}
	var candidate_transport = TransportNetworkSystemScript.create_from_dict(transport.to_dict())
	var candidate_planning = TransportPlanningSessionScript.create_from_dict(transport_planning_session.to_dict())
	if candidate_transport == null or candidate_planning == null:
		return {"ok": false, "error": "transport_package_materialization_clone_failed"}
	var created := _materialize_candidate_transport_package(candidate_transport, candidate_planning, package_quote)
	if not bool(created.get("ok", false)):
		_push_ui_event("transport_package_route_activation_failed", created.duplicate(true))
		return created
	transport = candidate_transport
	transport_planning_session = candidate_planning
	var route: Dictionary = Dictionary(created.get("route", {})).duplicate(true)
	_record_fact({
		"type": "transport_route_created",
		"subject_id": str(route.get("id", "")),
		"game_day": game_day(),
		"reason_tag": "transport.route.created",
		"payload": route.duplicate(true),
	})
	_push_ui_event("transport_package_materialized", {
		"route": route.duplicate(true),
		"session": transport_planning_session.snapshot(),
	})
	return {"ok": true, "route": route, "session": transport_planning_session.snapshot()}


func set_transport_route_enabled(route_id: String, enabled: bool, _city_grid: Array = []) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	if transport == null or not transport.routes.has(route_id):
		return {"ok": false, "error": "route_not_found"}
	if enabled:
		var validation: Dictionary = transport.route_quote(Dictionary(transport.routes[route_id]))
		if not bool(validation.get("valid", false)):
			return {
				"ok": false,
				"error": "transport_route_invalid",
				"validation_errors": Array(validation.get("validation_errors", [])).duplicate(),
			}
	var result: Dictionary = transport.toggle_route(route_id, enabled)
	if not bool(result.get("ok", false)):
		return result
	var route: Dictionary = result.get("route", {})
	_record_fact({
		"type": "transport_route_enabled" if enabled else "transport_route_disabled",
		"subject_id": route_id,
		"game_day": game_day(),
		"reason_tag": "transport.route.enabled" if enabled else "transport.route.disabled",
		"payload": route.duplicate(true),
	})
	_push_ui_event("transport_route_enabled" if enabled else "transport_route_disabled", route)
	_emit_changed()
	return {"ok": true, "route": route.duplicate(true)}


func delete_transport_route(route_id: String) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	if transport == null or not transport.routes.has(route_id):
		return {"ok": false, "error": "route_not_found"}
	var deleted: Dictionary = transport.delete_route(route_id)
	if not bool(deleted.get("ok", false)):
		return deleted
	var removed: Dictionary = Dictionary(deleted.get("route", {})).duplicate(true)
	if transport_planning_session != null:
		transport_planning_session.mark_route_deleted(route_id)
	_record_fact({
		"type": "transport_route_deleted",
		"subject_id": route_id,
		"game_day": game_day(),
		"reason_tag": "transport.route.deleted",
		"payload": removed.duplicate(true),
	})
	_push_ui_event("transport_route_deleted", removed)
	_emit_changed()
	return {"ok": true, "route": removed}


func revalidate_transport_routes() -> Array[Dictionary]:
	return transport.revalidate_routes() if transport != null else []


func transport_view_model(city_grid: Array = []) -> Dictionary:
	if transport == null:
		return {"planning_unlocked": true, "routes": []}
	var route_models: Array[Dictionary] = []
	for route_id in _sorted_keys(transport.routes):
		var route: Dictionary = Dictionary(transport.routes[route_id]).duplicate(true)
		route["route_id"] = str(route.get("id", route_id))
		route["stop_count"] = Array(route.get("stop_ids", [])).size()
		route["path_tile_count"] = Array(route.get("path_tile_ids", [])).size()
		route["path_length"] = int(route["path_tile_count"])
		route["status_detail"] = _transport_route_status_detail(route)
		route["can_toggle"] = true
		route["can_delete"] = true
		route_models.append(route)
	var project_models: Array[Dictionary] = []
	for project_id in _sorted_keys(transport.projects):
		project_models.append(Dictionary(transport.projects[project_id]).duplicate(true))
	var result := {
		"planning_unlocked": true,
		"routes": route_models,
		"projects": project_models,
		"segments": transport.segments.duplicate(true),
		"facilities": transport.facilities.duplicate(true),
		"stations": transport.stations.duplicate(true),
		"crossings": transport.crossings.duplicate(true),
		"operational_lines": transport.active_lines(),
		"monthly_maintenance": transport.monthly_maintenance(),
		"private_road_traffic": transport.has_private_road_traffic(city_grid, terrain_map),
		"network": transport.network_snapshot(),
	}
	if transport_planning_session != null and transport_planning_session.is_route_package():
		var planning_state := str(transport_planning_session.snapshot().get("state", ""))
		if planning_state == TransportPlanningSessionScript.STATE_ROUTE_EDIT:
			result["package_quote"] = transport_session_package_quote(city_grid)
	return result


func transport_visual_snapshot(city_grid: Array) -> Dictionary:
	return transport.visual_runtime_snapshot(city_grid, terrain_map) if transport != null else {}


func transport_navigation_blocked_tile_ids() -> PackedInt32Array:
	var result := PackedInt32Array()
	if transport == null:
		return result
	for tile_id: int in transport.navigation_blocker_ids():
		result.append(tile_id)
	return result


func transport_monthly_maintenance() -> int:
	return transport.monthly_maintenance() if transport != null else 0


func transport_incremental_monthly_maintenance() -> int:
	return transport.incremental_monthly_maintenance() if transport != null else 0


func transport_service_revenue(mode: String, resident_population: int, service_definition: Dictionary) -> int:
	return transport.service_revenue(mode, resident_population, service_definition) if transport != null else 0


func transport_service_operational_factor(mode: String) -> float:
	return transport.service_operational_factor(mode) if transport != null else 0.0


func transport_has_private_road_traffic(city_grid: Array) -> bool:
	return transport != null and transport.has_private_road_traffic(city_grid, terrain_map)


func public_service_input_snapshot(city_grid: Array) -> Dictionary:
	var hospital_service: Dictionary = {}
	var hospital_definition = building_definitions.get("hospital")
	if hospital_definition != null:
		var definition_effects: Dictionary = hospital_definition.effects
		var service_value: Variant = definition_effects.get("public_service", {})
		if service_value is Dictionary:
			hospital_service = (service_value as Dictionary).duplicate(true)
	var road_access_components: Array[Dictionary] = []
	if transport != null and terrain_map != null:
		road_access_components = transport.private_road_paths(city_grid, terrain_map)
	return {
		"population": population.population_count() if population != null else 0,
		"building_records": session.state.buildings.duplicate(true) if session != null else {},
		"road_access_components": road_access_components.duplicate(true),
		"durability_records": durability.buildings.duplicate(true) if durability != null else {},
		"maintenance_enabled": maintenance_payment_enabled,
		"unpaid_maintenance_months": durability.consecutive_unpaid_months if durability != null else 0,
		"capacity_per_facility": maxi(0, int(hospital_service.get("capacity_per_facility", 0))),
		"max_metric_bonus": maxi(0, int(hospital_service.get("max_metric_bonus", 0))),
	}


func healthcare_service_result(city_grid: Array) -> Dictionary:
	return CitySimulationServiceScript.healthcare_service_result(
		public_service_input_snapshot(city_grid)
	)


func terrain_flatten_quote(tile_index: int, worker_count: int = DEFAULT_TERRAIN_FLATTEN_WORKERS) -> Dictionary:
	if terrain_map == null or not terrain_map.is_valid_tile_id(tile_index):
		return {"ok": false, "error": "invalid_tile_id", "tile_index": tile_index}
	var terrain: Dictionary = terrain_map.tile_state(tile_index)
	var source_kind := str(terrain.get("base_kind", ""))
	var fixed_cost := int(TERRAIN_FLATTEN_COSTS.get(source_kind, 0))
	var estimate: Dictionary = construction.estimate_terrain_flatten_job(
		tile_index,
		source_kind,
		fixed_cost,
		worker_count
	)
	if not bool(estimate.get("ok", false)):
		var failed := estimate.duplicate(true)
		failed["tile_index"] = tile_index
		failed["terrain"] = terrain
		return failed
	var labor_cost := int(estimate.get("labor_cost", 0))
	var total_cost := int(estimate.get("total_cost", fixed_cost + labor_cost))
	var available_workers := int(construction.available_workers())
	var terrain_in_use := get_building_by_tile(tile_index).size() > 0 or _has_active_job_on_tile(tile_index)
	var can_flatten := bool(terrain.get("flattenable", false))
	var can_afford := treasury_balance() >= total_cost
	return {
		"ok": true,
		"tile_index": tile_index,
		"terrain": terrain,
		"source_terrain_kind": source_kind,
		"worker_count": worker_count,
		"available_workers": available_workers,
		"duration_days": int(estimate.get("duration_days", 0)),
		"daily_labor_cost": int(estimate.get("daily_labor_cost", 0)),
		"base_cost": fixed_cost,
		"fixed_cost": fixed_cost,
		"labor_cost": labor_cost,
		"total_labor_cost": labor_cost,
		"total_cost": total_cost,
		# Legacy callers displayed `cost`; it now means the exact prepaid total.
		"cost": total_cost,
		"billing_model": str(estimate.get("billing_model", "")),
		"can_flatten": can_flatten,
		"can_afford": can_afford,
		"can_start": can_flatten and not terrain_in_use and available_workers >= worker_count and can_afford,
		"terrain_in_use": terrain_in_use,
	}


func flatten_terrain(tile_index: int, worker_count: int = DEFAULT_TERRAIN_FLATTEN_WORKERS) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	var quote := terrain_flatten_quote(tile_index, worker_count)
	if not bool(quote.get("ok", false)):
		return quote
	var active_job := active_construction_for_tile(tile_index)
	if not active_job.is_empty():
		if str(active_job.get("metadata", {}).get("entity_kind", "")) == ConstructionSystemScript.TERRAIN_FLATTEN_ENTITY_KIND:
			return {"ok": false, "error": "terrain_flatten_already_active", "tile_index": tile_index}
		return {"ok": false, "error": "terrain_in_use", "tile_index": tile_index}
	if get_building_by_tile(tile_index).size() > 0:
		return {"ok": false, "error": "terrain_in_use", "tile_index": tile_index}
	if not bool(quote.get("can_flatten", false)):
		return {"ok": false, "error": "terrain_not_flattenable", "tile_index": tile_index}
	if worker_count > int(quote.get("available_workers", 0)):
		return {"ok": false, "error": "insufficient_workers"}
	var total_cost := int(quote.get("total_cost", 0))
	if treasury_balance() < total_cost:
		return {"ok": false, "error": "insufficient_treasury", "required": total_cost}
	var result: Dictionary = construction.start_terrain_flatten_job(
		tile_index,
		str(quote.get("source_terrain_kind", "")),
		int(quote.get("fixed_cost", 0)),
		worker_count,
		game_day()
	)
	if not bool(result.get("ok", false)):
		return result
	var job: Dictionary = result.get("job", {})
	_post_ledger(-total_cost, "construction.terrain_flatten_total_cost", str(job.get("id", "terrain_%03d" % tile_index)), {
		"tile_index": tile_index,
		"terrain_kind": str(quote.get("source_terrain_kind", "")),
		"base_cost": int(quote.get("base_cost", 0)),
		"fixed_cost": int(quote.get("fixed_cost", 0)),
		"labor_cost": int(quote.get("labor_cost", 0)),
		"total_cost": total_cost,
		"billing_model": str(quote.get("billing_model", "")),
	})
	_upsert_construction(job)
	_record_fact({
		"type": "terrain_flatten_started",
		"subject_id": str(job.get("id", "tile_%03d" % tile_index)),
		"game_day": game_day(),
		"reason_tag": "terrain.flatten.started",
		"payload": {
			"tile_index": tile_index,
			"terrain_kind": str(quote.get("source_terrain_kind", "")),
			"job_id": str(job.get("id", "")),
			"worker_count": worker_count,
			"duration_days": int(job.get("projected_total_days", 0)),
			"total_cost": total_cost,
		},
	})
	_push_ui_event("terrain_flatten_started", {
		"tile_index": tile_index,
		"terrain_kind": str(quote.get("source_terrain_kind", "")),
		"job": job.duplicate(true),
		"worker_count": worker_count,
		"duration_days": int(job.get("projected_total_days", 0)),
		"base_cost": int(quote.get("base_cost", 0)),
		"labor_cost": int(quote.get("labor_cost", 0)),
		"total_cost": total_cost,
	})
	_emit_changed()
	return {
		"ok": true,
		"tile_index": tile_index,
		"terrain": terrain_map.tile_state(tile_index),
		"job": job.duplicate(true),
		"cost": total_cost,
		"base_cost": int(quote.get("base_cost", 0)),
		"labor_cost": int(quote.get("labor_cost", 0)),
		"total_cost": total_cost,
	}

func start_approved_building(display_name: String, tile_index: int, worker_count: int) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	if terrain_map == null or not terrain_map.is_valid_tile_id(tile_index):
		return {"ok": false, "error": "invalid_tile_id"}
	var placement := placement_footprint_quote(display_name, tile_index, worker_count)
	if not bool(placement.get("ok", false)):
		if str(placement.get("error", "")) == "blueprint_not_found":
			return {"ok": false, "error": "approved_blueprint_required"}
		return placement
	var library_id := str(placement.get("library_id", ""))
	if library_id.is_empty() or not blueprint_library_service.has_entry(library_id):
		return {"ok": false, "error": "approved_blueprint_required"}
	var blueprint: Dictionary = Dictionary(placement.get("blueprint", {})).duplicate(true)
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
		{
			"tile_index": tile_index,
			"anchor_tile_id": tile_index,
			"footprint_id": str(placement.get("footprint_id", "")),
			"occupied_tile_ids": Array(placement.get("occupied_tile_ids", [])).duplicate(),
			"building_name": display_name,
		}
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
	return {
		"ok": true,
		"job": job,
		"total_cost": total_cost,
		"blueprint_library_id": library_id,
		"anchor_tile_id": tile_index,
		"footprint_id": str(placement.get("footprint_id", "")),
		"occupied_tile_ids": Array(placement.get("occupied_tile_ids", [])).duplicate(),
	}

func register_existing_building(
	tile_index: int,
	display_name: String,
	customization: Dictionary = {},
	size_tier: String = BuildingFootprintsScript.SMALL
) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	var footprint := BuildingFootprintsScript.resolve_for_size(size_tier, tile_index, terrain_map)
	if not bool(footprint.get("ok", false)):
		return {}
	var occupied_tile_ids: Array = Array(footprint.get("occupied_tile_ids", [])).duplicate()
	var definition = _definition_for_name(display_name)
	if definition == null:
		return {}
	for occupied_tile_id: int in occupied_tile_ids:
		var existing := get_building_by_tile(occupied_tile_id)
		if not existing.is_empty():
			return existing if occupied_tile_id == tile_index else {}
	# Existing-building registration is a current bootstrap seam. It does not
	# charge construction costs, but its explicit size still derives the same
	# canonical footprint as normal construction. Legacy single-tile provenance
	# is written only by GameSession's schema 4-8 migration path.
	for occupied_tile_id: int in occupied_tile_ids:
		if not terrain_map.is_buildable(occupied_tile_id):
			terrain_map.flatten_tile(occupied_tile_id)
	var instance_id := _next_building_id()
	var record := {
		"building_id": instance_id,
		"definition_id": String(definition.id),
		"building_name": display_name,
		"tile_index": tile_index,
		"anchor_tile_id": tile_index,
		"footprint_id": str(footprint.get("footprint_id", "")),
		"occupied_tile_ids": occupied_tile_ids,
		"status": "active",
		"durability": 100,
		"blueprint": {
			"version": 1,
			"building_id": String(definition.id),
			"material_id": String(definition.default_material_id),
			"floors": 2,
			"size_tier": size_tier,
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
	_register_transport_station_for_building(record)
	return record


func adjust_population(delta: int, reason_tag: String, address_id: String = "") -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	var result := _adjust_population(delta, reason_tag, address_id)
	_emit_changed()
	return result


func match_population_jobs(open_jobs: Array[Dictionary]) -> Array[Dictionary]:
	if population == null:
		return []
	var matches: Array[Dictionary] = population.match_open_jobs(open_jobs, game_day())
	if matches.is_empty():
		return matches
	# Employment is part of the canonical NPC record. Keep the runtime-only
	# CityState lookup exact at the same boundary that mutates those records, so
	# the fail-closed save gate never observes a partially mirrored population.
	_sync_population_to_core("population.job_matched")
	return matches

func start_demolition(tile_index: int, worker_count: int) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	var building := get_building_by_tile(tile_index)
	if building.is_empty():
		return {"ok": false, "error": "building_not_found"}
	if str(building.get("status", "active")) == "demolition" or _has_active_job_for_target(str(building.get("building_id", ""))):
		return {"ok": false, "error": "demolition_already_active"}
	var blueprint: Dictionary = building.get("blueprint", {})
	var anchor_tile_id := int(building.get("anchor_tile_id", building.get("tile_index", tile_index)))
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
		{"tile_index": anchor_tile_id, "building_name": str(building["building_name"])}
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
	var anchor_tile_id := int(building.get("anchor_tile_id", building.get("tile_index", tile_index)))
	if _has_active_demolition_job_for_target(building_id):
		return {"ok": false, "error": "demolition_in_progress"}
	var quote: Dictionary = durability.repair_quote(building_id)
	if not bool(quote.get("ok", false)):
		return quote
	var cost := int(quote.get("total_cost", 0))
	if treasury_balance() < cost:
		return {"ok": false, "error": "insufficient_treasury", "required": cost}
	_post_ledger(-cost, "durability.repair", building_id, {"tile_index": anchor_tile_id})
	var result: Dictionary = durability.repair(building_id, game_day())
	if bool(result.get("ok", false)):
		building["durability"] = 100
		building["status"] = "active"
		_upsert_building(building, "building.repaired")
		_record_fact(result["event"])
		_push_ui_event("building_repaired", {"tile_index": anchor_tile_id, "cost": cost})
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


func preview_lower_house_response(response_id: String, city_context: Dictionary = {}) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	return governance.preview_lower_house_response(response_id, _governance_context(city_context))


func answer_lower_house_hearing(response_id: String, city_context: Dictionary = {}) -> Dictionary:
	if governance.has_failed():
		return _terminal_command_error()
	var result: Dictionary = governance.answer_lower_house_hearing(
		response_id,
		game_day(),
		_governance_context(city_context)
	)
	if not bool(result.get("ok", false)):
		return result
	for event_variant: Variant in result.get("events", []):
		if event_variant is Dictionary:
			_handle_governance_fact(event_variant)
	_sync_governance_to_core("governance.lower_house_response")
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
		var occupied_value: Variant = building.get("occupied_tile_ids", null)
		if occupied_value is Array or occupied_value is PackedInt32Array or occupied_value is PackedInt64Array:
			for occupied_variant: Variant in occupied_value:
				if int(occupied_variant) == tile_index:
					return building.duplicate(true)
		if occupied_value == null and int(building.get("tile_index", -1)) == tile_index:
			return building.duplicate(true)
	return {}

func _has_active_job_on_tile(tile_index: int) -> bool:
	for job in construction.active_jobs():
		if _construction_job_tile_indices(job).has(tile_index):
			return true
	return false

func _has_active_job_for_target(target_id: String) -> bool:
	if target_id.is_empty():
		return false
	for job in construction.active_jobs():
		if str(job.get("target_id", "")) == target_id:
			return true
	return false


func _has_active_demolition_job_for_target(target_id: String) -> bool:
	if target_id.is_empty():
		return false
	for job in construction.active_jobs():
		if (
			str(job.get("target_id", "")) == target_id
			and str(job.get("operation", "")) == "demolish"
		):
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
	if error == OK:
		last_save_message = "已儲存：第 %d 年 %d 月 %d 日" % [current_date()["year"], current_date()["month"], current_date()["day"]]
	else:
		last_save_message = "儲存失敗（錯誤 %d）｜%s" % [error, _save_failure_hint()]
		var diagnostic_code := _save_failure_code()
		if not diagnostic_code.is_empty():
			# Expected negative-path tests deliberately provoke save failures. Keep a
			# data-free diagnostic in stdout without converting the handled error into
			# an engine warning that release gates would treat as an unhandled defect.
			print("SAVE_FAILURE error=%d reason=%s" % [error, diagnostic_code])
	_emit_changed()
	return error


func _save_failure_hint() -> String:
	var diagnostic := str(session.save_service.last_error_message)
	if diagnostic.contains("runtime NPC data"):
		return "人口資料同步不一致，請保留目前畫面並重試。"
	if diagnostic.contains("semantically inconsistent"):
		return "存檔狀態驗證未通過，請保留目前畫面並重試。"
	return "存檔寫入或驗證失敗，請保留目前畫面並重試。"


func _save_failure_code() -> String:
	var diagnostic := str(session.save_service.last_error_message)
	if diagnostic.contains("runtime NPC data"):
		return "runtime_population_mismatch"
	if diagnostic.contains("semantically inconsistent"):
		return "semantic_snapshot_invalid"
	if diagnostic.contains("temporary") or diagnostic.contains("Temporary"):
		return "temporary_write_or_verification_failed"
	if diagnostic.is_empty():
		return ""
	return "save_io_or_verification_failed"

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
	if str(metadata.get("entity_kind", "")) == ConstructionSystemScript.TERRAIN_FLATTEN_ENTITY_KIND:
		var tile_index := int(metadata.get("tile_index", -1))
		var source_kind := str(metadata.get("source_terrain_kind", ""))
		var flatten_result: Dictionary = terrain_map.flatten_tile(tile_index) if terrain_map != null else {
			"ok": false,
			"error": "terrain_system_unavailable",
		}
		if bool(flatten_result.get("ok", false)):
			var flattened_payload := {
				"tile_index": tile_index,
				"terrain_kind": source_kind,
				"job_id": job_id,
				"base_cost": int(metadata.get("base_cost", 0)),
				"labor_cost": int(metadata.get("labor_cost", 0)),
				"total_cost": int(metadata.get("total_cost", 0)),
				"cost": int(metadata.get("total_cost", 0)),
			}
			_record_fact({
				"type": "terrain_flattened",
				"subject_id": "tile_%03d" % tile_index,
				"game_day": game_day(),
				"reason_tag": "terrain.flattened",
				"payload": flattened_payload.duplicate(true),
			})
			_push_ui_event("terrain_flattened", flattened_payload)
		else:
			_push_ui_event("terrain_flatten_completion_failed", {
				"tile_index": tile_index,
				"job_id": job_id,
				"error": str(flatten_result.get("error", "terrain_flatten_completion_failed")),
			})
		session.submit_command("remove_construction", {
			"job_id": job_id,
			"reason_tag": "construction.completed"
		}, _operation_id("job_remove"))
		return true
	if str(metadata.get("entity_kind", "")) == "transport_project":
		var project_id := str(metadata.get("transport_project_id", metadata.get("project_id", job.get("target_id", ""))))
		var completion: Dictionary = transport.complete_project(project_id) if transport != null else {"ok": false, "error": "transport_system_unavailable"}
		if bool(completion.get("ok", false)):
			var completed_project: Dictionary = completion.get("project", {})
			if transport_planning_session != null:
				transport_planning_session.mark_job_completed(job_id, project_id)
			_try_materialize_completed_transport_package()
			_record_fact({
				"type": "transport_project_completed",
				"subject_id": project_id,
				"game_day": game_day(),
				"reason_tag": "transport.project.completed",
				"payload": completed_project.duplicate(true),
			})
			_push_ui_event("transport_project_completed", {
				"project": completed_project.duplicate(true),
				"network": Dictionary(completion.get("network", {})).duplicate(true),
			})
		else:
			_push_ui_event("transport_project_completion_failed", {
				"project_id": project_id,
				"error": str(completion.get("error", "transport_project_completion_failed")),
			})
		session.submit_command("remove_construction", {
			"job_id": job_id,
			"reason_tag": "construction.completed"
		}, _operation_id("job_remove"))
		return true
	if operation == "build":
		var display_name := str(metadata.get("building_name", ""))
		var definition = _definition_for_name(display_name)
		var footprint_validation := BuildingFootprintsScript.validate_persisted_record(
			metadata,
			terrain_map,
			str(job.get("blueprint", {}).get("size_tier", ""))
		)
		if not bool(footprint_validation.get("valid", false)):
			_push_ui_event("building_completion_failed", {
				"job_id": job_id,
				"error": str(footprint_validation.get("error", "invalid_footprint")),
			})
			return false
		var instance_id := _next_building_id()
		var record := {
			"building_id": instance_id,
			"definition_id": str(job.get("blueprint", {}).get("building_id", "")),
			"building_name": display_name,
			"tile_index": int(metadata.get("tile_index", -1)),
			"anchor_tile_id": int(footprint_validation.get("anchor_tile_id", -1)),
			"footprint_id": str(footprint_validation.get("footprint_id", "")),
			"occupied_tile_ids": Array(footprint_validation.get("occupied_tile_ids", [])).duplicate(),
			"status": "active",
			"durability": 100,
			"blueprint": job.get("blueprint", {}).duplicate(true)
		}
		if bool(footprint_validation.get("legacy_single_provenance", false)):
			record[BuildingFootprintsScript.LEGACY_SINGLE_PROVENANCE_FIELD] = (
				BuildingFootprintsScript.LEGACY_SINGLE_PROVENANCE
			)
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
		var completion_operation_id := _operation_id("building_complete")
		var completion_events: Array = session.submit_command("complete_building_construction", {
			"building_id": instance_id,
			"job_id": job_id,
			"record": record,
			"reason_tag": "building.construction_completed",
		}, completion_operation_id)
		var completion_emitted := false
		for completion_event in completion_events:
			if (
				str(completion_event.event_type) == "building.construction_completed"
				and str(completion_event.caused_by) == completion_operation_id
			):
				completion_emitted = true
				break
		if not completion_emitted:
			_push_ui_event("building_completion_failed", {
				"job_id": job_id,
				"error": "building_authority_transition_failed",
			})
			return false
		_register_transport_station_for_building(record)
		if transport_planning_session != null:
			transport_planning_session.mark_job_completed(job_id, instance_id)
		_try_materialize_completed_transport_package()
		_push_ui_event("building_completed", record)
		return true
	elif operation == "demolish":
		var target_id := str(job.get("target_id", ""))
		var building_record: Dictionary = session.state.buildings.get(target_id, {})
		var population_change := _remove_population_ids(
			_resident_ids_from_building(building_record),
			"population.building_demolished"
		)
		durability.unregister_building(target_id)
		if transport != null:
			transport.unregister_station(target_id)
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
	var building_id := str(event.get("subject_id", ""))
	var demolition_in_progress := _has_active_demolition_job_for_target(building_id)
	var recorded_event := event
	if demolition_in_progress and str(event.get("type", "")) == "building_scrapped":
		recorded_event = event.duplicate(true)
		recorded_event["type"] = "building_damaged"
		var recorded_payload: Dictionary = Dictionary(event.get("payload", {})).duplicate(true)
		recorded_payload["scrapped"] = false
		recorded_event["payload"] = recorded_payload
	_record_fact(recorded_event)
	if not session.state.buildings.has(building_id):
		return
	var record: Dictionary = session.state.buildings[building_id].duplicate(true)
	var previous_status := str(record.get("status", "active"))
	var durability_record: Dictionary = durability.get_building(building_id)
	record["durability"] = int(durability_record.get("durability", record.get("durability", 100)))
	record["status"] = (
		"demolition"
		if demolition_in_progress
		else str(durability_record.get("status", record.get("status", "active")))
	)
	var population_change := {
		"requested_delta": 0,
		"actual_delta": 0,
		"added_ids": PackedStringArray(),
		"removed_ids": PackedStringArray(),
	}
	if not demolition_in_progress and record["status"] == "scrapped" and previous_status != "scrapped":
		population_change = _remove_population_ids(
			_resident_ids_from_building(record),
			"population.building_scrapped"
		)
		record["resident_ids"] = []
		record["population_delta"] = 0
		if transport != null:
			transport.unregister_station(building_id)
	_upsert_building(record, str(event.get("reason_tag", "building.durability")))
	if not demolition_in_progress and record["status"] == "scrapped":
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
	return (
		event_type == "lower_house_hearing_ready"
		or event_type.begins_with("judiciary_")
		or event_type.begins_with("oversight_")
	)

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
	session.state.metadata["vertical_slice"] = _vertical_slice_subsystem_snapshot()


func _vertical_slice_subsystem_snapshot() -> Dictionary:
	var blueprint_snapshot: Dictionary = blueprint_library_service.snapshot()
	return {
		"schema_version": SaveSchemaAuthorityScript.CURRENT_VERTICAL_SCHEMA_VERSION,
		"construction": construction.to_dict(),
		"durability": durability.to_dict(),
		"governance": governance.to_dict(),
		"population": population.to_dict(),
		"terrain": terrain_map.to_dict() if terrain_map != null else {},
		"transport": transport.to_dict() if transport != null else TransportNetworkSystemScript.new().to_dict(),
		"transport_planning_session": (
			transport_planning_session.to_dict()
			if transport_planning_session != null
			else TransportPlanningSessionScript.inactive_snapshot()
		),
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
		population.initialize(int(session.state.metrics.get("population", 0)), int(session.kernel.rng_seed))
	var terrain_data: Variant = data.get("terrain", {})
	if terrain_data is Dictionary and not (terrain_data as Dictionary).is_empty():
		terrain_map = CityTerrainMapScript.create_from_dict(terrain_data)
	else:
		terrain_map = CityTerrainMapScript.new()
		terrain_map.apply_default_city_layout()
	var source_schema := int(data.get("schema_version", 0))
	var transport_data: Variant = data.get("transport", {})
	if source_schema >= 6 and transport_data is Dictionary and not (transport_data as Dictionary).is_empty():
		transport = TransportNetworkSystemScript.create_from_dict(transport_data)
	else:
		# Schema 5 and earlier did not persist a transport overlay. Preserve the
		# city and bootstrap an empty network, then reconcile completed stations.
		transport = TransportNetworkSystemScript.new()
	var transport_planning_value: Variant = data.get("transport_planning_session", {})
	if source_schema >= SaveSchemaAuthorityScript.CURRENT_VERTICAL_SCHEMA_VERSION and transport_planning_value is Dictionary:
		transport_planning_session = TransportPlanningSessionScript.create_from_dict(
			transport_planning_value as Dictionary
		)
	else:
		transport_planning_session = TransportPlanningSessionScript.new()
	if transport_planning_session == null:
		transport_planning_session = TransportPlanningSessionScript.new()
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
	# Only those legacy cities normalize occupied/worksite tiles. Current
	# terrain-flatten jobs must remain unflattened until their completion day.
	if source_schema < 5:
		for building_variant: Variant in session.state.buildings.values():
			var building_record: Dictionary = building_variant
			for occupied_tile: int in _building_record_occupied_tile_ids(building_record):
				if terrain_map.is_valid_tile_id(occupied_tile) and not terrain_map.is_buildable(occupied_tile):
					terrain_map.flatten_tile(occupied_tile)
		for job_variant: Variant in construction.active_jobs():
			var job: Dictionary = job_variant
			for job_tile: int in _construction_job_tile_indices(job):
				if terrain_map.is_valid_tile_id(job_tile) and not terrain_map.is_buildable(job_tile):
					terrain_map.flatten_tile(job_tile)
	building_definitions = ContentRegistry.buildings_by_id()
	var preserve_persisted_active_blueprints := data.has("active_blueprint_by_building")
	blueprint_library_service.restore(
		int(data.get("next_blueprint_sequence", 1)),
		Dictionary(data.get("blueprint_library", {})),
		Dictionary(data.get("active_blueprint_by_building", {})),
		building_definitions
	)
	var persisted_active_blueprints: Dictionary = blueprint_library_service.active_blueprint_by_building.duplicate(true)
	for review_variant in construction.reviews.values():
		var historical_review: Dictionary = review_variant
		if str(historical_review.get("status", "")) in ["approved", "in_construction", "completed"]:
			blueprint_library_service.archive_approved_blueprint(
				historical_review,
				building_definitions,
				game_day()
			)
	if preserve_persisted_active_blueprints:
		# Current saves persist the player's explicit library choice. Historical
		# review replay may restore missing entries, but must not make them active.
		blueprint_library_service.active_blueprint_by_building = persisted_active_blueprints
	_reconcile_transport_stations_from_buildings()
	_normalize_selected_population_references()
	if not session.hydrate_runtime_population(population.to_dict()):
		push_error("Failed to hydrate the restored runtime NPC lookup from canonical population data.")


func _transport_plan_for_tiles(kind: String, operation: String, tile_ids: Array) -> Dictionary:
	var normalized_tiles: Array[int] = []
	for tile_variant: Variant in tile_ids:
		var tile_id := int(tile_variant)
		if tile_id >= 0 and not normalized_tiles.has(tile_id):
			normalized_tiles.append(tile_id)
	if normalized_tiles.is_empty():
		return {
			"title": "交通工程",
			"segments": [],
			"facilities": [],
			"stations": [],
		} if operation == "build" else {
			"title": "交通拆除工程",
			"segment_ids": [],
			"facility_ids": [],
			"station_ids": [],
		}
	if operation == "build":
		if TransportModesScript.SEGMENT_KINDS.has(kind):
			return {
				"title": "興建%s" % kind,
				"segments": [{"kind": kind, "tile_path": normalized_tiles.duplicate()}],
				"facilities": [],
				"stations": [],
			}
		if TransportModesScript.FACILITY_KINDS.has(kind):
			var facility_plan: Array[Dictionary] = []
			for tile_id: int in normalized_tiles:
				facility_plan.append({"kind": kind, "tile_id": tile_id})
			return {
				"title": "設置%s" % kind,
				"segments": [],
				"facilities": facility_plan,
				"stations": [],
			}
		return {}
	var selected_set: Dictionary = {}
	for tile_id: int in normalized_tiles:
		selected_set[tile_id] = true
	var segment_ids: Array[String] = []
	var facility_ids: Array[String] = []
	if TransportModesScript.SEGMENT_KINDS.has(kind):
		for segment_id in _sorted_keys(transport.segments):
			var segment: Dictionary = transport.segments[segment_id]
			if str(segment.get("kind", "")) != kind:
				continue
			for segment_tile_variant: Variant in segment.get("tile_path", []):
				if selected_set.has(int(segment_tile_variant)):
					segment_ids.append(segment_id)
					break
	elif TransportModesScript.FACILITY_KINDS.has(kind):
		for facility_id in _sorted_keys(transport.facilities):
			var facility: Dictionary = transport.facilities[facility_id]
			if str(facility.get("kind", "")) == kind and selected_set.has(int(facility.get("tile_id", -1))):
				facility_ids.append(facility_id)
	else:
		return {}
	return {
		"title": "拆除%s" % kind,
		"segment_ids": segment_ids,
		"facility_ids": facility_ids,
		"station_ids": [],
	}


func _transport_package_has_connected_support(
	depot_kind: String,
	network_kind: String,
	route_tiles: Array,
	route_plan: Dictionary,
	occupied_tiles: Array[int]
) -> bool:
	var candidate = TransportNetworkSystemScript.create_from_dict(transport.to_dict())
	if candidate == null:
		return false
	var started: Dictionary = candidate.start_project(
		"build", route_plan, terrain_map, occupied_tiles, _transport_construction_tile_ids()
	)
	if not bool(started.get("ok", false)):
		return false
	var project_id := str(started.get("project", {}).get("id", ""))
	if not bool(candidate.complete_project(project_id).get("ok", false)):
		return false
	return bool(candidate.call("_has_connected_depot", depot_kind, network_kind, route_tiles))


func _transport_package_support_tile(route_tiles: Array, occupied_tiles: Array[int]) -> int:
	var unavailable: Dictionary = {}
	for tile_value: Variant in route_tiles:
		unavailable[int(tile_value)] = true
	for tile_id: int in occupied_tiles:
		unavailable[tile_id] = true
	for tile_id: int in _transport_construction_tile_ids():
		unavailable[tile_id] = true
	for route_tile_value: Variant in route_tiles:
		var coordinate: Vector2i = terrain_map.coordinate_for_tile_id(int(route_tile_value))
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var candidate_tile := int(terrain_map.tile_id_for_coordinate(coordinate + offset))
			if (
				candidate_tile >= 0
				and not unavailable.has(candidate_tile)
				and terrain_map.is_buildable(candidate_tile)
			):
				return candidate_tile
	return -1


func _transport_project_tile_indices(operation: String, plan: Dictionary) -> Array[int]:
	var tile_set: Dictionary = {}
	if operation == "build":
		for segment_variant: Variant in plan.get("segments", []):
			var segment: Dictionary = segment_variant
			for tile_variant: Variant in segment.get("tile_path", []):
				tile_set[int(tile_variant)] = true
		for facility_variant: Variant in plan.get("facilities", []):
			tile_set[int(Dictionary(facility_variant).get("tile_id", -1))] = true
		for station_variant: Variant in plan.get("stations", []):
			tile_set[int(Dictionary(station_variant).get("tile_id", -1))] = true
	else:
		for segment_id_variant: Variant in plan.get("segment_ids", []):
			var segment: Dictionary = transport.segments.get(str(segment_id_variant), {})
			for tile_variant: Variant in segment.get("tile_path", []):
				tile_set[int(tile_variant)] = true
		for facility_id_variant: Variant in plan.get("facility_ids", []):
			var facility: Dictionary = transport.facilities.get(str(facility_id_variant), {})
			tile_set[int(facility.get("tile_id", -1))] = true
		for station_id_variant: Variant in plan.get("station_ids", []):
			var station: Dictionary = transport.stations.get(str(station_id_variant), {})
			tile_set[int(station.get("tile_id", -1))] = true
	var result: Array[int] = []
	for tile_variant: Variant in tile_set.keys():
		var tile_id := int(tile_variant)
		if tile_id >= 0:
			result.append(tile_id)
	result.sort()
	return result


func _transport_job_blueprint(kind: String, tile_indices: Array[int], worker_count: int) -> Dictionary:
	var work_per_tile := float({
		"road": 5.0,
		"metro_track": 9.0,
		"rail_track": 8.0,
		"runway": 11.0,
		"taxiway": 7.0,
		"bus_depot": 12.0,
		"metro_depot": 16.0,
		"rail_depot": 16.0,
		"rail_signal": 4.0,
	}.get(kind, 7.0))
	return {
		"id": "transport_%s" % kind,
		"version": 1,
		"building_id": "transport_%s" % kind,
		"material_id": "steel",
		"floors": 1,
		"size_tier": "medium",
		"decoration_count": 0,
		"requested_workers": worker_count,
		"base_cost": 0,
		"workload": maxf(1.0, float(tile_indices.size()) * work_per_tile),
	}


func _transport_occupied_tile_ids(city_grid: Array) -> Array[int]:
	var occupied: Dictionary = {}
	for tile_id in range(city_grid.size()):
		if not str(city_grid[tile_id]).is_empty():
			occupied[tile_id] = true
	for building_variant: Variant in session.state.buildings.values():
		for tile_id: int in _building_record_occupied_tile_ids(Dictionary(building_variant)):
			if tile_id >= 0:
				occupied[tile_id] = true
	var result: Array[int] = []
	for tile_variant: Variant in occupied.keys():
		result.append(int(tile_variant))
	result.sort()
	return result


func _transport_construction_tile_ids() -> Array[int]:
	var tile_set: Dictionary = {}
	for job_variant: Variant in construction.active_jobs():
		for tile_id: int in _construction_job_tile_indices(job_variant):
			tile_set[tile_id] = true
	var result: Array[int] = []
	for tile_variant: Variant in tile_set.keys():
		result.append(int(tile_variant))
	result.sort()
	return result


func _construction_job_tile_indices(job_variant: Variant) -> Array[int]:
	var result := _construction_job_tile_indices_canonical(job_variant)
	result.sort()
	return result


func _construction_job_tile_indices_canonical(job_variant: Variant) -> Array[int]:
	if not job_variant is Dictionary:
		return []
	var metadata: Dictionary = Dictionary(job_variant).get("metadata", {})
	var result: Array[int] = []
	var multiple: Variant = metadata.get("occupied_tile_ids", metadata.get("tile_indices", []))
	if multiple is Array or multiple is PackedInt32Array or multiple is PackedInt64Array:
		for tile_variant: Variant in multiple:
			var tile_id := int(tile_variant)
			if tile_id >= 0 and not result.has(tile_id):
				result.append(tile_id)
	var single := int(metadata.get("tile_index", -1))
	if single >= 0 and not result.has(single):
		result.append(single)
	return result


func _building_record_occupied_tile_ids(building: Dictionary) -> Array[int]:
	var result := _building_record_occupied_tile_ids_canonical(building)
	result.sort()
	return result


func _building_record_occupied_tile_ids_canonical(building: Dictionary) -> Array[int]:
	var result: Array[int] = []
	var occupied_value: Variant = building.get("occupied_tile_ids", null)
	if occupied_value is Array or occupied_value is PackedInt32Array or occupied_value is PackedInt64Array:
		for tile_variant: Variant in occupied_value:
			var tile_id := int(tile_variant)
			if tile_id >= 0 and not result.has(tile_id):
				result.append(tile_id)
	else:
		var tile_id := int(building.get("tile_index", -1))
		if tile_id >= 0:
			result.append(tile_id)
	return result


func _footprint_cell_view(
	kind: String,
	owner: Dictionary,
	occupied_tile_ids: Array[int],
	tile_index: int
) -> Dictionary:
	var footprint_index := occupied_tile_ids.find(tile_index)
	if footprint_index < 0:
		return {}
	var metadata: Dictionary = owner.get("metadata", {}) if kind == "construction" else {}
	var anchor_tile_id := int(
		metadata.get("anchor_tile_id", metadata.get("tile_index", -1))
		if kind == "construction"
		else owner.get("anchor_tile_id", owner.get("tile_index", -1))
	)
	var footprint_id := str(
		metadata.get("footprint_id", "")
		if kind == "construction"
		else owner.get("footprint_id", "")
	)
	var building_name := str(
		metadata.get("building_name", "")
		if kind == "construction"
		else owner.get("building_name", "")
	)
	return {
		"kind": kind,
		"tile_id": tile_index,
		"anchor_tile_id": anchor_tile_id,
		"owner_anchor_tile_id": anchor_tile_id,
		"footprint_id": footprint_id,
		"occupied_tile_ids": occupied_tile_ids.duplicate(),
		"footprint_index": footprint_index,
		"footprint_count": occupied_tile_ids.size(),
		"role": "anchor" if tile_index == anchor_tile_id else "secondary",
		"building_name": building_name,
		"owner_id": str(owner.get("building_id", owner.get("id", ""))),
		"owner": owner.duplicate(true),
	}


func _transport_public_quote_error(model_result: Dictionary) -> Dictionary:
	var result := model_result.duplicate(true)
	var raw_issues: Array = model_result.get("issues", [])
	var public_issues: Array[String] = []
	for issue_variant: Variant in raw_issues:
		var issue := str(issue_variant)
		if issue.begins_with("tile_under_construction:"):
			public_issues.append(issue.replace("tile_under_construction:", "construction_conflict:"))
		elif issue.begins_with("non_cardinal_segment_path:"):
			public_issues.append(issue.replace("non_cardinal_segment_path:", "path_not_cardinally_contiguous:"))
		else:
			public_issues.append(issue)
	result["model_issues"] = raw_issues.duplicate()
	result["issues"] = public_issues
	if public_issues.has("demolition_targets_required"):
		result["error"] = "transport_target_not_found"
	return result


func _transport_station_ids_for_tiles(mode: String, station_tile_ids: Array) -> Dictionary:
	var mode_spec := TransportModesScript.route_spec(mode)
	if mode_spec.is_empty():
		return {"ok": false, "error": "invalid_route_mode"}
	var expected_name := str(mode_spec.get("station_name", ""))
	var stop_ids: Array[String] = []
	var seen_tiles: Dictionary = {}
	for tile_variant: Variant in station_tile_ids:
		var tile_id := int(tile_variant)
		if seen_tiles.has(tile_id):
			return {"ok": false, "error": "duplicate_station_tile", "tile_index": tile_id}
		seen_tiles[tile_id] = true
		var matched_id := ""
		for station_id in _sorted_keys(transport.stations):
			var station: Dictionary = transport.stations[station_id]
			if int(station.get("tile_id", -1)) == tile_id and str(station.get("building_name", "")) == expected_name and str(station.get("status", "")) == "completed":
				matched_id = station_id
				break
		if matched_id.is_empty():
			return {
				"ok": false,
				"error": "transport_station_not_found",
				"tile_index": tile_id,
				"expected_building_name": expected_name,
			}
		stop_ids.append(matched_id)
	return {"ok": true, "stop_ids": stop_ids}


func _transport_reusable_station_placement(tile_id: int, current: Dictionary) -> Dictionary:
	if tile_id < 0 or tile_id >= CityTerrainMapScript.CELL_COUNT:
		return {"ok": false, "error": "invalid_tile_id"}
	if not active_construction_for_tile(tile_id).is_empty():
		return {"ok": false, "error": "station_under_construction", "tile_index": tile_id}
	var building := get_building_by_tile(tile_id)
	if building.is_empty():
		return {"ok": false, "error": "transport_station_not_found", "tile_index": tile_id}
	var anchor_tile_id := int(building.get("anchor_tile_id", building.get("tile_index", -1)))
	if not active_construction_for_tile(anchor_tile_id).is_empty():
		return {"ok": false, "error": "station_under_construction", "tile_index": anchor_tile_id}
	var expected_name := str(current.get("station_blueprint_name", ""))
	if str(building.get("building_name", "")) != expected_name:
		return {
			"ok": false,
			"error": "transport_station_incompatible",
			"tile_index": anchor_tile_id,
			"expected_building_name": expected_name,
		}
	if str(building.get("status", "")) != "active":
		return {"ok": false, "error": "transport_station_not_completed", "tile_index": anchor_tile_id}
	var station_id := str(building.get("building_id", ""))
	if station_id.is_empty() or transport == null or not transport.stations.has(station_id):
		return {"ok": false, "error": "transport_station_not_found", "tile_index": anchor_tile_id}
	var station_value: Variant = transport.stations.get(station_id, null)
	if not station_value is Dictionary:
		return {"ok": false, "error": "transport_station_not_found", "tile_index": anchor_tile_id}
	var station: Dictionary = station_value
	if (
		str(station.get("id", "")) != station_id
		or str(station.get("building_name", "")) != expected_name
		or int(station.get("tile_id", -1)) != anchor_tile_id
		or str(station.get("status", "")) != "completed"
	):
		return {"ok": false, "error": "transport_station_authority_mismatch", "tile_index": anchor_tile_id}
	var occupied_tile_ids := _building_record_occupied_tile_ids_canonical(building)
	if occupied_tile_ids.is_empty() or not occupied_tile_ids.has(anchor_tile_id):
		return {"ok": false, "error": "invalid_station_footprint", "tile_index": anchor_tile_id}
	return {
		"ok": true,
		"station": station.duplicate(true),
		"placement": {
			"ok": true,
			"anchor_tile_id": anchor_tile_id,
			"occupied_tile_ids": occupied_tile_ids.duplicate(),
			"footprint_id": str(building.get("footprint_id", "")),
			"blueprint": Dictionary(building.get("blueprint", {})).duplicate(true),
			"worker_count": 0,
			"total_cost": 0,
			"duration_days": 0,
			"reuse_existing_station": true,
			"existing_station_id": station_id,
		},
	}


func _register_transport_station_for_building(record: Dictionary) -> bool:
	if transport == null:
		return false
	var building_name := str(record.get("building_name", ""))
	if not TransportModesScript.STATION_KINDS.has(building_name):
		return false
	if str(record.get("status", "active")) == "scrapped":
		return false
	var result: Dictionary = transport.register_station(
		str(record.get("building_id", "")),
		building_name,
		int(record.get("tile_index", -1))
	)
	return bool(result.get("ok", false))


func _reconcile_transport_stations_from_buildings() -> void:
	if transport == null:
		return
	for station_id in _sorted_keys(transport.stations):
		var station: Dictionary = transport.stations[station_id]
		if str(station.get("project_id", "")) != "external":
			continue
		var building: Dictionary = session.state.buildings.get(station_id, {})
		if building.is_empty() or str(building.get("status", "active")) == "scrapped" or not TransportModesScript.STATION_KINDS.has(str(building.get("building_name", ""))):
			transport.unregister_station(station_id)
	for building_id in _sorted_keys(session.state.buildings):
		if transport.stations.has(building_id):
			continue
		_register_transport_station_for_building(Dictionary(session.state.buildings[building_id]))


func _transport_route_status_detail(route: Dictionary) -> String:
	var errors: Array = route.get("validation_errors", [])
	if not errors.is_empty():
		var text_errors := PackedStringArray()
		for error_variant: Variant in errors:
			text_errors.append(str(error_variant))
		return ", ".join(text_errors)
	return "路網驗證通過" if str(route.get("status", "")) == "operational" else "玩家已停駛"


func _transport_route_mode_label(mode: String) -> String:
	return {
		"bus": "公車路線",
		"metro": "捷運路線",
		"train": "火車路線",
		"air": "航空路線",
	}.get(mode, "交通路線")


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
