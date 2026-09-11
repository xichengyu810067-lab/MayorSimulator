class_name TransportPlanningSession
extends RefCounted

## Serializable workflow authority for one player-authored transport planning
## session.  It stores references to the existing construction and transport
## authorities; it never owns or duplicates topology records.

const TransportModesScript = preload("res://data/catalogs/transport_modes.gd")
const BuildingFootprintsScript = preload("res://data/catalogs/building_footprints.gd")
const CityTerrainMapScript = preload("res://scripts/world/city_terrain_map.gd")
const SaveSchemaAuthorityScript = preload("res://scripts/core/save_schema_authority.gd")

const SCHEMA_VERSION := SaveSchemaAuthorityScript.TRANSPORT_PLANNING_SESSION_CURRENT_SCHEMA_VERSION
const MIN_SUPPORTED_SCHEMA_VERSION := SaveSchemaAuthorityScript.TRANSPORT_PLANNING_SESSION_MIN_SUPPORTED_SCHEMA_VERSION
const MAX_SUPPORTED_SCHEMA_VERSION := SaveSchemaAuthorityScript.TRANSPORT_PLANNING_SESSION_MAX_SUPPORTED_SCHEMA_VERSION
const WORKFLOW_ROUTE_PACKAGE_V1 := "route_package_v1"
const STATE_INACTIVE := "inactive"
const STATE_STATION_PLACEMENT := "station_placement"
const STATE_NETWORK_PLACEMENT := "network_placement"
const STATE_ROUTE_EDIT := "route_edit"
const STATE_WAITING_CONSTRUCTION := "waiting_construction"
const STATE_PAUSED := "paused"
const STATE_MATERIALIZED := "materialized"
const STATE_CLOSED := "closed"
const STATES := [
	STATE_INACTIVE,
	STATE_STATION_PLACEMENT,
	STATE_NETWORK_PLACEMENT,
	STATE_ROUTE_EDIT,
	STATE_WAITING_CONSTRUCTION,
	STATE_PAUSED,
	STATE_MATERIALIZED,
	STATE_CLOSED,
]
const RESUMABLE_STATES := [
	STATE_STATION_PLACEMENT,
	STATE_NETWORK_PLACEMENT,
	STATE_ROUTE_EDIT,
]
const STATION_REF_STATUSES := ["active", "completed", "cancelled"]
const NETWORK_REF_STATUSES := ["active", "completed", "cancelled"]

var next_session_sequence := 1
var session: Dictionary = _inactive_session()


func begin(
	station_blueprint_name: String,
	station_blueprint_library_id: String,
	requested_workflow: String = ""
) -> Dictionary:
	if station_blueprint_name not in TransportModesScript.STATION_KINDS:
		return _error("invalid_station_blueprint")
	if station_blueprint_library_id.is_empty():
		return _error("station_blueprint_library_id_required")
	if not str(session.get("state", STATE_INACTIVE)) in [STATE_INACTIVE, STATE_CLOSED, STATE_MATERIALIZED]:
		return _error("transport_planning_session_active")
	var station_spec := TransportModesScript.station_spec(station_blueprint_name)
	var mode := str(station_spec.get("route_mode", ""))
	if mode not in TransportModesScript.ROUTE_MODES:
		return _error("invalid_transport_mode")
	var session_id := "transport_planning_%06d" % next_session_sequence
	next_session_sequence += 1
	var workflow := requested_workflow
	if workflow not in ["", WORKFLOW_ROUTE_PACKAGE_V1]:
		return _error("invalid_transport_workflow")
	if workflow == WORKFLOW_ROUTE_PACKAGE_V1 and mode not in ["bus", "metro", "train"]:
		return _error("route_package_mode_unsupported")
	session = {
		"id": session_id,
		"state": STATE_STATION_PLACEMENT,
		"station_blueprint_name": station_blueprint_name,
		"station_blueprint_library_id": station_blueprint_library_id,
		"mode": mode,
		"workflow": workflow,
		"station_refs": [],
		"network_refs": [],
		"route_refs": [],
		"network_draft": {},
		"route_draft": {"station_placements": []} if workflow == WORKFLOW_ROUTE_PACKAGE_V1 else {},
		"resume_state": "",
		"closed_reason": "",
	}
	return _success()


func is_route_package() -> bool:
	return str(session.get("workflow", "")) == WORKFLOW_ROUTE_PACKAGE_V1


func record_station_draft(placement: Dictionary, worker_count: int) -> Dictionary:
	if not is_route_package():
		return _error("transport_session_not_route_package")
	var preflight := can_place_station(
		str(session.get("station_blueprint_name", "")),
		str(session.get("station_blueprint_library_id", ""))
	)
	if not bool(preflight.get("ok", false)):
		return preflight
	var anchor_tile_id := int(placement.get("anchor_tile_id", -1))
	var occupied_tile_ids: Array = Array(placement.get("occupied_tile_ids", [])).duplicate()
	if anchor_tile_id < 0 or occupied_tile_ids.is_empty() or not occupied_tile_ids.has(anchor_tile_id):
		return _error("invalid_station_draft")
	var route_draft: Dictionary = Dictionary(session.get("route_draft", {})).duplicate(true)
	var placements: Array = Array(route_draft.get("station_placements", [])).duplicate(true)
	for existing_value: Variant in placements:
		if not existing_value is Dictionary:
			continue
		var existing: Dictionary = existing_value
		if int(existing.get("anchor_tile_id", -1)) == anchor_tile_id:
			return _error("station_draft_already_recorded")
		for tile_value: Variant in existing.get("occupied_tile_ids", []):
			if occupied_tile_ids.has(int(tile_value)):
				return _error("station_draft_overlap")
	placements.append({
		"anchor_tile_id": anchor_tile_id,
		"occupied_tile_ids": occupied_tile_ids,
		"footprint_id": str(placement.get("footprint_id", "")),
		"library_id": str(placement.get("library_id", "")),
		"blueprint": Dictionary(placement.get("blueprint", {})).duplicate(true),
		"worker_count": worker_count,
		"building_cost": int(placement.get("total_cost", 0)),
		"duration_days": int(placement.get("duration_days", 0)),
	})
	route_draft["station_placements"] = placements
	session["route_draft"] = route_draft
	return _success({"station_draft_count": placements.size()})


func record_existing_station_draft(placement: Dictionary, station: Dictionary) -> Dictionary:
	if not is_route_package():
		return _error("transport_session_not_route_package")
	var preflight := can_place_station(
		str(session.get("station_blueprint_name", "")),
		str(session.get("station_blueprint_library_id", ""))
	)
	if not bool(preflight.get("ok", false)):
		return preflight
	var anchor_tile_id := int(placement.get("anchor_tile_id", -1))
	var occupied_tile_ids: Array = Array(placement.get("occupied_tile_ids", [])).duplicate()
	var station_id := str(station.get("id", ""))
	if (
		anchor_tile_id < 0
		or occupied_tile_ids.is_empty()
		or not occupied_tile_ids.has(anchor_tile_id)
		or station_id.is_empty()
		or str(station.get("building_name", "")) != str(session.get("station_blueprint_name", ""))
		or int(station.get("tile_id", -1)) != anchor_tile_id
		or str(station.get("status", "")) != "completed"
	):
		return _error("invalid_existing_station_reference")
	var route_draft: Dictionary = Dictionary(session.get("route_draft", {})).duplicate(true)
	var placements: Array = Array(route_draft.get("station_placements", [])).duplicate(true)
	for existing_value: Variant in placements:
		if not existing_value is Dictionary:
			continue
		var existing: Dictionary = existing_value
		if int(existing.get("anchor_tile_id", -1)) == anchor_tile_id:
			return _error("station_draft_already_recorded")
		for tile_value: Variant in existing.get("occupied_tile_ids", []):
			if occupied_tile_ids.has(int(tile_value)):
				return _error("station_draft_overlap")
	placements.append({
		"anchor_tile_id": anchor_tile_id,
		"occupied_tile_ids": occupied_tile_ids,
		"footprint_id": str(placement.get("footprint_id", "")),
		"library_id": "",
		"blueprint": Dictionary(placement.get("blueprint", {})).duplicate(true),
		"worker_count": 0,
		"building_cost": 0,
		"duration_days": 0,
		"reuse_existing_station": true,
		"existing_station_id": station_id,
	})
	route_draft["station_placements"] = placements
	session["route_draft"] = route_draft
	return _success({"station_draft_count": placements.size(), "station_id": station_id})


func remove_station_draft(anchor_tile_id: int) -> Dictionary:
	if not is_route_package() or str(session.get("state", "")) != STATE_STATION_PLACEMENT:
		return _error("transport_session_not_placing_stations")
	var route_draft: Dictionary = Dictionary(session.get("route_draft", {})).duplicate(true)
	var placements: Array = Array(route_draft.get("station_placements", [])).duplicate(true)
	for index in range(placements.size()):
		var value: Variant = placements[index]
		if value is Dictionary and int((value as Dictionary).get("anchor_tile_id", -1)) == anchor_tile_id:
			placements.remove_at(index)
			route_draft["station_placements"] = placements
			session["route_draft"] = route_draft
			return _success({"station_draft_count": placements.size()})
	return _error("station_draft_not_found")


func station_draft_count() -> int:
	if not is_route_package():
		return 0
	return Array(Dictionary(session.get("route_draft", {})).get("station_placements", [])).size()


func can_place_station(station_blueprint_name: String, station_blueprint_library_id: String) -> Dictionary:
	if str(session.get("state", "")) != STATE_STATION_PLACEMENT:
		return _error("transport_session_not_placing_stations")
	if station_blueprint_name != str(session.get("station_blueprint_name", "")):
		return _error("transport_session_station_blueprint_mismatch")
	if station_blueprint_library_id != str(session.get("station_blueprint_library_id", "")):
		return _error("transport_session_station_blueprint_changed")
	return _success()


func record_station_job(job: Dictionary, placement: Dictionary) -> Dictionary:
	var preflight := can_place_station(
		str(session.get("station_blueprint_name", "")),
		str(session.get("station_blueprint_library_id", ""))
	)
	if not bool(preflight.get("ok", false)):
		return preflight
	var job_id := str(job.get("id", ""))
	var anchor_tile_id := int(placement.get("anchor_tile_id", -1))
	if job_id.is_empty() or anchor_tile_id < 0:
		return _error("invalid_station_job_reference")
	for ref_value: Variant in session.get("station_refs", []):
		if ref_value is Dictionary and str((ref_value as Dictionary).get("job_id", "")) == job_id:
			return _error("station_job_already_recorded")
	var refs: Array = Array(session.get("station_refs", [])).duplicate(true)
	refs.append({
		"job_id": job_id,
		"station_id": "",
		"anchor_tile_id": anchor_tile_id,
		"occupied_tile_ids": Array(placement.get("occupied_tile_ids", [])).duplicate(),
		"status": "active",
	})
	session["station_refs"] = refs
	return _success()


func begin_network_placement(network_kind: String, draft: Dictionary = {}) -> Dictionary:
	if str(session.get("state", "")) != STATE_STATION_PLACEMENT:
		return _error("transport_session_not_placing_stations")
	var mode_spec := TransportModesScript.route_spec(str(session.get("mode", "")))
	var minimum_stops := int(mode_spec.get("minimum_stops", 1))
	var authored_stops := station_draft_count() if is_route_package() else Array(session.get("station_refs", [])).size()
	if authored_stops < minimum_stops:
		return _error("transport_session_requires_more_stations", {"required": minimum_stops})
	if not _network_kind_matches_mode(network_kind, mode_spec):
		return _error("transport_session_network_kind_mismatch")
	session["network_draft"] = draft.duplicate(true)
	session["network_draft"]["kind"] = network_kind
	session["state"] = STATE_NETWORK_PLACEMENT
	session["resume_state"] = ""
	return _success()


func update_network_draft(network_kind: String, draft: Dictionary) -> Dictionary:
	if str(session.get("state", "")) != STATE_NETWORK_PLACEMENT:
		return _error("transport_session_not_placing_network")
	var mode_spec := TransportModesScript.route_spec(str(session.get("mode", "")))
	if not _network_kind_matches_mode(network_kind, mode_spec):
		return _error("transport_session_network_kind_mismatch")
	session["network_draft"] = draft.duplicate(true)
	session["network_draft"]["kind"] = network_kind
	return _success()


func record_network_job(project: Dictionary, job: Dictionary) -> Dictionary:
	if str(session.get("state", "")) != STATE_NETWORK_PLACEMENT:
		return _error("transport_session_not_placing_network")
	var project_id := str(project.get("id", ""))
	var job_id := str(job.get("id", ""))
	var kind := str(session.get("network_draft", {}).get("kind", ""))
	if project_id.is_empty() or job_id.is_empty() or not _is_network_kind(kind):
		return _error("invalid_network_job_reference")
	for ref_value: Variant in session.get("network_refs", []):
		if ref_value is Dictionary and str((ref_value as Dictionary).get("project_id", "")) == project_id:
			return _error("network_project_already_recorded")
	var refs: Array = Array(session.get("network_refs", [])).duplicate(true)
	refs.append({
		"project_id": project_id,
		"job_id": job_id,
		"kind": kind,
		"status": "active",
	})
	session["network_refs"] = refs
	return _success()


func begin_route_edit(draft: Dictionary = {}) -> Dictionary:
	if str(session.get("state", "")) != STATE_NETWORK_PLACEMENT:
		return _error("transport_session_not_placing_network")
	var candidate := session.duplicate(true)
	var route_draft := Dictionary(candidate.get("route_draft", {})).duplicate(true) if is_route_package() else {}
	route_draft.merge(draft, true)
	candidate["route_draft"] = route_draft
	candidate["route_draft"]["mode"] = str(candidate.get("mode", ""))
	candidate["state"] = STATE_ROUTE_EDIT
	candidate["resume_state"] = ""
	var semantic_error := _validate_state_semantics(candidate)
	if not semantic_error.is_empty():
		return _error(semantic_error)
	session = candidate
	return _success()


func update_route_draft(draft: Dictionary) -> Dictionary:
	if str(session.get("state", "")) != STATE_ROUTE_EDIT:
		return _error("transport_session_not_editing_route")
	var updated := Dictionary(session.get("route_draft", {})).duplicate(true) if is_route_package() else {}
	updated.merge(draft, true)
	if updated.has("corridor_quote"):
		var corridor_quote_validation := TransportModesScript.validate_route_package_corridor_price_quote(
			updated.get("corridor_quote", null)
		)
		if not bool(corridor_quote_validation.get("valid", false)):
			return _error("invalid_corridor_quote")
		var corridor: Dictionary = Dictionary(updated.get("corridor_quote", {})).get("corridor", {})
		if str(corridor.get("mode", "")) != str(session.get("mode", "")):
			return _error("corridor_quote_mode_mismatch")
	session["route_draft"] = updated
	session["route_draft"]["mode"] = str(session.get("mode", ""))
	return _success()


func record_route_package_jobs(
	station_jobs: Array,
	station_placements: Array,
	network_jobs: Array,
	package_quote: Dictionary
) -> Dictionary:
	if not is_route_package() or str(session.get("state", "")) != STATE_ROUTE_EDIT:
		return _error("transport_session_not_route_package_edit")
	if station_placements.is_empty() or network_jobs.is_empty():
		return _error("invalid_route_package_jobs")
	var station_refs: Array = []
	var station_job_index := 0
	for index in range(station_jobs.size()):
		if not station_jobs[index] is Dictionary:
			return _error("invalid_route_package_jobs")
	for placement_value: Variant in station_placements:
		if not placement_value is Dictionary:
			return _error("invalid_route_package_jobs")
		var placement: Dictionary = placement_value
		if bool(placement.get("reuse_existing_station", false)):
			var station_id := str(placement.get("existing_station_id", ""))
			if station_id.is_empty():
				return _error("invalid_existing_station_reference")
			station_refs.append({
				"job_id": "",
				"station_id": station_id,
				"anchor_tile_id": int(placement.get("anchor_tile_id", -1)),
				"occupied_tile_ids": Array(placement.get("occupied_tile_ids", [])).duplicate(),
				"status": "completed",
				"source": "existing",
			})
			continue
		if station_job_index >= station_jobs.size():
			return _error("invalid_route_package_jobs")
		var job: Dictionary = station_jobs[station_job_index]
		station_job_index += 1
		station_refs.append({
			"job_id": str(job.get("id", "")),
			"station_id": "",
			"anchor_tile_id": int(placement.get("anchor_tile_id", -1)),
			"occupied_tile_ids": Array(placement.get("occupied_tile_ids", [])).duplicate(),
			"status": "active",
		})
	if station_job_index != station_jobs.size():
		return _error("invalid_route_package_jobs")
	var network_refs: Array = []
	for item_value: Variant in network_jobs:
		if not item_value is Dictionary:
			return _error("invalid_route_package_jobs")
		var item: Dictionary = item_value
		var project: Dictionary = item.get("project", {})
		var job: Dictionary = item.get("job", {})
		var kind := str(item.get("kind", ""))
		if str(project.get("id", "")).is_empty() or str(job.get("id", "")).is_empty() or not _is_network_kind(kind):
			return _error("invalid_route_package_jobs")
		network_refs.append({
			"project_id": str(project.get("id", "")),
			"job_id": str(job.get("id", "")),
			"kind": kind,
			"status": "active",
		})
	var candidate := session.duplicate(true)
	candidate["station_refs"] = station_refs
	candidate["network_refs"] = network_refs
	var route_draft: Dictionary = Dictionary(candidate.get("route_draft", {})).duplicate(true)
	route_draft["package_quote"] = package_quote.duplicate(true)
	candidate["route_draft"] = route_draft
	candidate["state"] = STATE_WAITING_CONSTRUCTION
	candidate["resume_state"] = STATE_ROUTE_EDIT
	var semantic_error := _validate_state_semantics(candidate)
	if not semantic_error.is_empty():
		return _error(semantic_error)
	session = candidate
	return _success()


func record_route(route: Dictionary) -> Dictionary:
	if str(session.get("state", "")) != STATE_ROUTE_EDIT:
		return _error("transport_session_not_editing_route")
	var route_id := str(route.get("id", ""))
	if route_id.is_empty():
		return _error("invalid_route_reference")
	var refs: Array = Array(session.get("route_refs", [])).duplicate(true)
	if not refs.has(route_id):
		refs.append(route_id)
	var candidate := session.duplicate(true)
	candidate["route_refs"] = refs
	candidate["state"] = STATE_MATERIALIZED
	candidate["resume_state"] = ""
	var semantic_error := _validate_state_semantics(candidate)
	if not semantic_error.is_empty():
		return _error(semantic_error)
	session = candidate
	return _success()


func mark_route_deleted(route_id: String) -> Dictionary:
	if route_id.is_empty():
		return _error("route_id_required")
	var refs: Array = Array(session.get("route_refs", [])).duplicate()
	if not refs.has(route_id):
		return _error("transport_session_route_not_found")
	refs.erase(route_id)
	session["route_refs"] = refs
	if str(session.get("state", "")) == STATE_MATERIALIZED:
		session["state"] = STATE_ROUTE_EDIT
	return _success()


func wait_for_construction(resume_state: String = STATE_NETWORK_PLACEMENT) -> Dictionary:
	var current_state := str(session.get("state", ""))
	if current_state not in RESUMABLE_STATES:
		return _error("transport_session_cannot_wait")
	if resume_state not in RESUMABLE_STATES:
		return _error("invalid_transport_session_resume_state")
	if not has_active_jobs():
		return _error("transport_session_has_no_active_jobs")
	var candidate := session.duplicate(true)
	candidate["resume_state"] = resume_state
	candidate["state"] = STATE_WAITING_CONSTRUCTION
	var semantic_error := _validate_state_semantics(candidate)
	if not semantic_error.is_empty():
		return _error(semantic_error)
	session = candidate
	return _success()


func pause() -> Dictionary:
	var current_state := str(session.get("state", ""))
	if current_state not in RESUMABLE_STATES and current_state != STATE_WAITING_CONSTRUCTION:
		return _error("transport_session_cannot_pause")
	var candidate := session.duplicate(true)
	if current_state != STATE_WAITING_CONSTRUCTION:
		candidate["resume_state"] = current_state
	candidate["state"] = STATE_PAUSED
	var semantic_error := _validate_state_semantics(candidate)
	if not semantic_error.is_empty():
		return _error(semantic_error)
	session = candidate
	return _success()


func resume() -> Dictionary:
	if str(session.get("state", "")) != STATE_PAUSED:
		return _error("transport_session_not_paused")
	var resume_state := str(session.get("resume_state", ""))
	if resume_state not in RESUMABLE_STATES:
		return _error("invalid_transport_session_resume_state")
	session["state"] = resume_state
	session["resume_state"] = ""
	return _success()


func close(reason: String = "player_closed") -> Dictionary:
	if str(session.get("state", STATE_INACTIVE)) == STATE_INACTIVE:
		return _error("transport_planning_session_inactive")
	session["state"] = STATE_CLOSED
	session["resume_state"] = ""
	session["closed_reason"] = reason if not reason.is_empty() else "player_closed"
	return _success()


func mark_job_completed(job_id: String, materialized_id: String = "") -> Dictionary:
	if job_id.is_empty():
		return _error("job_id_required")
	var updated := false
	var station_updated := false
	var station_refs: Array = Array(session.get("station_refs", [])).duplicate(true)
	for index in range(station_refs.size()):
		var ref_value: Variant = station_refs[index]
		if not ref_value is Dictionary or str((ref_value as Dictionary).get("job_id", "")) != job_id:
			continue
		var ref: Dictionary = (ref_value as Dictionary).duplicate(true)
		ref["status"] = "completed"
		if not materialized_id.is_empty():
			ref["station_id"] = materialized_id
		station_refs[index] = ref
		updated = true
		station_updated = true
	if station_updated:
		session["station_refs"] = station_refs
	var network_updated := false
	var network_refs: Array = Array(session.get("network_refs", [])).duplicate(true)
	for index in range(network_refs.size()):
		var ref_value: Variant = network_refs[index]
		if not ref_value is Dictionary or str((ref_value as Dictionary).get("job_id", "")) != job_id:
			continue
		var ref: Dictionary = (ref_value as Dictionary).duplicate(true)
		ref["status"] = "completed"
		network_refs[index] = ref
		updated = true
		network_updated = true
	if network_updated:
		session["network_refs"] = network_refs
	if not updated:
		return _error("transport_session_job_not_found")
	_resume_after_jobs_if_ready()
	return _success()


func mark_job_cancelled(job_id: String) -> Dictionary:
	if job_id.is_empty():
		return _error("job_id_required")
	var updated := _set_reference_job_status("station_refs", job_id, "cancelled")
	updated = _set_reference_job_status("network_refs", job_id, "cancelled") or updated
	if not updated:
		return _error("transport_session_job_not_found")
	_resume_after_jobs_if_ready()
	return _success()


func has_active_jobs() -> bool:
	for field_name: String in ["station_refs", "network_refs"]:
		for ref_value: Variant in session.get(field_name, []):
			if ref_value is Dictionary and str((ref_value as Dictionary).get("status", "")) == "active":
				return true
	return false


func snapshot() -> Dictionary:
	return session.duplicate(true)


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"next_session_sequence": next_session_sequence,
		"session": session.duplicate(true),
	}


func load_dict(data: Dictionary) -> bool:
	var migrated := migrate_snapshot(data)
	if migrated.is_empty():
		return false
	var validation := validate_snapshot(migrated)
	if not bool(validation.get("valid", false)):
		return false
	next_session_sequence = int(migrated.get("next_session_sequence", 1))
	session = Dictionary(migrated.get("session", _inactive_session())).duplicate(true)
	if session.get("route_draft", null) is Dictionary:
		var route_draft: Dictionary = session.get("route_draft", {})
		if route_draft.has("corridor_quote") and route_draft.get("corridor_quote", null) is Dictionary:
			route_draft["corridor_quote"] = _normalize_corridor_quote(route_draft.get("corridor_quote", {}))
			session["route_draft"] = route_draft
	return true


static func create_from_dict(data: Dictionary):
	var instance = (load("res://scripts/systems/city/transport_planning_session.gd") as Script).new()
	return instance if instance.load_dict(data) else null


static func migrate_snapshot(data: Dictionary) -> Dictionary:
	var schema_value: Variant = data.get("schema_version", null)
	if not _is_integer_value(schema_value):
		return {}
	var source_version := int(schema_value)
	if source_version < MIN_SUPPORTED_SCHEMA_VERSION or source_version > MAX_SUPPORTED_SCHEMA_VERSION:
		return {}
	var migrated := data.duplicate(true)
	migrated["schema_version"] = SCHEMA_VERSION
	return migrated if bool(validate_snapshot(migrated).get("valid", false)) else {}


static func inactive_snapshot() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"next_session_sequence": 1,
		"session": _inactive_session(),
	}


static func validate_snapshot(data: Dictionary) -> Dictionary:
	if not _is_integer_value(data.get("schema_version", null)) or int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		return {"valid": false, "error": "unsupported_schema"}
	if not _is_integer_value(data.get("next_session_sequence", null)) or int(data.get("next_session_sequence", 0)) < 1:
		return {"valid": false, "error": "invalid_next_session_sequence"}
	var session_value: Variant = data.get("session", null)
	if not session_value is Dictionary:
		return {"valid": false, "error": "invalid_session"}
	var current: Dictionary = session_value
	var state_value: Variant = current.get("state", null)
	if not state_value is String or str(state_value) not in STATES:
		return {"valid": false, "error": "invalid_session_state"}
	if str(state_value) == STATE_INACTIVE:
		return {"valid": true, "error": ""} if current.size() == 1 else {"valid": false, "error": "invalid_inactive_session"}
	for string_field: String in ["id", "station_blueprint_name", "station_blueprint_library_id", "mode", "resume_state", "closed_reason"]:
		if not current.get(string_field, null) is String:
			return {"valid": false, "error": "invalid_session_field:%s" % string_field}
	var workflow_value: Variant = current.get("workflow", "")
	if not workflow_value is String or str(workflow_value) not in ["", WORKFLOW_ROUTE_PACKAGE_V1]:
		return {"valid": false, "error": "invalid_transport_workflow"}
	if str(current.get("id", "")).is_empty() or str(current.get("station_blueprint_library_id", "")).is_empty():
		return {"valid": false, "error": "missing_session_identity"}
	var id_suffix := str(current.get("id", "")).trim_prefix("transport_planning_")
	if not id_suffix.is_valid_int() or int(id_suffix) < 1 or int(data.get("next_session_sequence", 0)) <= int(id_suffix):
		return {"valid": false, "error": "invalid_session_sequence"}
	var station_name := str(current.get("station_blueprint_name", ""))
	if station_name not in TransportModesScript.STATION_KINDS:
		return {"valid": false, "error": "invalid_station_blueprint"}
	if str(TransportModesScript.station_spec(station_name).get("route_mode", "")) != str(current.get("mode", "")):
		return {"valid": false, "error": "station_mode_mismatch"}
	if str(current.get("resume_state", "")) != "" and str(current.get("resume_state", "")) not in RESUMABLE_STATES:
		return {"valid": false, "error": "invalid_resume_state"}
	for dictionary_field: String in ["network_draft", "route_draft"]:
		if not current.get(dictionary_field, null) is Dictionary:
			return {"valid": false, "error": "invalid_session_field:%s" % dictionary_field}
	var route_draft: Dictionary = current.get("route_draft", {})
	if route_draft.has("corridor_quote"):
		var corridor_quote_validation := TransportModesScript.validate_route_package_corridor_price_quote(
			route_draft.get("corridor_quote", null)
		)
		if not bool(corridor_quote_validation.get("valid", false)):
			return {"valid": false, "error": "invalid_corridor_quote"}
		var corridor: Dictionary = Dictionary(route_draft.get("corridor_quote", {})).get("corridor", {})
		if str(corridor.get("mode", "")) != str(current.get("mode", "")):
			return {"valid": false, "error": "corridor_quote_mode_mismatch"}
	for array_field: String in ["station_refs", "network_refs", "route_refs"]:
		if not current.get(array_field, null) is Array:
			return {"valid": false, "error": "invalid_session_field:%s" % array_field}
	var seen_jobs: Dictionary = {}
	var seen_station_ids: Dictionary = {}
	for ref_value: Variant in current.get("station_refs", []):
		if not ref_value is Dictionary:
			return {"valid": false, "error": "invalid_station_ref"}
		var ref: Dictionary = ref_value
		if not _valid_ref_strings(ref, ["job_id", "station_id", "status"]):
			return {"valid": false, "error": "invalid_station_ref"}
		var station_job_id := str(ref.get("job_id", ""))
		var source := str(ref.get("source", ""))
		if ref.has("source") and not ref.get("source") is String:
			return {"valid": false, "error": "invalid_station_ref"}
		if source not in ["", "existing"]:
			return {"valid": false, "error": "invalid_station_ref"}
		if str(ref.get("status", "")) not in STATION_REF_STATUSES:
			return {"valid": false, "error": "invalid_station_ref"}
		if source == "existing":
			if not station_job_id.is_empty() or str(ref.get("status", "")) != "completed":
				return {"valid": false, "error": "invalid_existing_station_ref"}
		elif station_job_id.is_empty() or seen_jobs.has(station_job_id):
			return {"valid": false, "error": "invalid_station_ref"}
		else:
			seen_jobs[station_job_id] = true
		if not _is_integer_value(ref.get("anchor_tile_id", null)) or int(ref.get("anchor_tile_id", -1)) < 0 or int(ref.get("anchor_tile_id", -1)) >= 100:
			return {"valid": false, "error": "invalid_station_anchor"}
		if not _valid_unique_integer_array(ref.get("occupied_tile_ids", null)):
			return {"valid": false, "error": "invalid_station_occupied_tiles"}
		if not _integer_array_has(ref.get("occupied_tile_ids", []), int(ref.get("anchor_tile_id", -1))):
			return {"valid": false, "error": "station_anchor_not_occupied"}
		if str(ref.get("status", "")) == "completed" and str(ref.get("station_id", "")).is_empty():
			return {"valid": false, "error": "completed_station_missing_identity"}
		var station_id := str(ref.get("station_id", ""))
		if not station_id.is_empty():
			if seen_station_ids.has(station_id):
				return {"valid": false, "error": "duplicate_station_reference"}
			seen_station_ids[station_id] = true
	for ref_value: Variant in current.get("network_refs", []):
		if not ref_value is Dictionary:
			return {"valid": false, "error": "invalid_network_ref"}
		var ref: Dictionary = ref_value
		if not _valid_ref_strings(ref, ["project_id", "job_id", "kind", "status"]):
			return {"valid": false, "error": "invalid_network_ref"}
		var network_job_id := str(ref.get("job_id", ""))
		if str(ref.get("project_id", "")).is_empty() or network_job_id.is_empty() or seen_jobs.has(network_job_id):
			return {"valid": false, "error": "invalid_network_ref"}
		seen_jobs[network_job_id] = true
		if not _is_network_kind(str(ref.get("kind", ""))) or str(ref.get("status", "")) not in NETWORK_REF_STATUSES:
			return {"valid": false, "error": "invalid_network_ref"}
		if not _network_kind_matches_mode(
			str(ref.get("kind", "")),
			TransportModesScript.route_spec(str(current.get("mode", "")))
		):
			return {"valid": false, "error": "network_mode_mismatch"}
	var seen_routes: Dictionary = {}
	for route_value: Variant in current.get("route_refs", []):
		if not route_value is String or str(route_value).is_empty() or seen_routes.has(str(route_value)):
			return {"valid": false, "error": "invalid_route_ref"}
		seen_routes[str(route_value)] = true
	var semantic_error := _validate_state_semantics(current)
	if not semantic_error.is_empty():
		return {"valid": false, "error": semantic_error}
	return {"valid": true, "error": ""}


static func validate_references(
	data: Dictionary,
	construction_snapshot: Dictionary,
	transport_snapshot: Dictionary,
	buildings_snapshot: Dictionary
) -> Dictionary:
	var shape := validate_snapshot(data)
	if not bool(shape.get("valid", false)):
		return shape
	var current: Dictionary = data.get("session", {})
	if str(current.get("state", "")) == STATE_INACTIVE:
		return {"valid": true, "error": ""}
	var jobs_value: Variant = construction_snapshot.get("jobs", null)
	var projects_value: Variant = transport_snapshot.get("projects", null)
	var routes_value: Variant = transport_snapshot.get("routes", null)
	var stations_value: Variant = transport_snapshot.get("stations", null)
	if not jobs_value is Dictionary or not projects_value is Dictionary or not routes_value is Dictionary or not stations_value is Dictionary:
		return {"valid": false, "error": "missing_reference_authority"}
	var jobs: Dictionary = jobs_value
	var projects: Dictionary = projects_value
	var routes: Dictionary = routes_value
	var stations: Dictionary = stations_value
	var route_draft: Dictionary = Dictionary(current.get("route_draft", {}))
	var station_placements: Array = Array(route_draft.get("station_placements", []))
	if not _reused_route_draft_placements_match_authority(current, station_placements, stations, buildings_snapshot):
		return {"valid": false, "error": "existing_station_placement_authority_mismatch"}
	var station_refs: Array = current.get("station_refs", [])
	for ref_index in range(station_refs.size()):
		var ref_value: Variant = station_refs[ref_index]
		var ref: Dictionary = ref_value
		var job_id := str(ref.get("job_id", ""))
		if str(ref.get("source", "")) == "existing":
			var station_id := str(ref.get("station_id", ""))
			if not _existing_station_reference_matches_placement(
				ref,
				station_placements,
				ref_index
			):
				return {"valid": false, "error": "existing_station_placement_mismatch"}
			if not stations.has(station_id) or not stations[station_id] is Dictionary:
				return {"valid": false, "error": "station_reference_missing"}
			var station: Dictionary = stations[station_id]
			if (
				str(station.get("id", "")) != station_id
				or str(station.get("building_name", "")) != str(current.get("station_blueprint_name", ""))
				or int(station.get("tile_id", -1)) != int(ref.get("anchor_tile_id", -1))
				or str(station.get("status", "")) != "completed"
			):
				return {"valid": false, "error": "station_reference_mismatch"}
			if not _existing_station_building_matches_reference(
				station_id,
				ref,
				current,
				buildings_snapshot
			):
				return {"valid": false, "error": "station_building_reference_mismatch"}
			continue
		if not jobs.has(job_id) or not jobs[job_id] is Dictionary:
			return {"valid": false, "error": "station_job_reference_missing"}
		var job: Dictionary = jobs[job_id]
		var metadata_value: Variant = job.get("metadata", null)
		if not metadata_value is Dictionary:
			return {"valid": false, "error": "station_job_metadata_missing"}
		var metadata: Dictionary = metadata_value
		if (
			str(job.get("operation", "")) != "build"
			or str(metadata.get("building_name", "")) != str(current.get("station_blueprint_name", ""))
			or str(metadata.get("blueprint_library_id", "")) != str(current.get("station_blueprint_library_id", ""))
			or int(metadata.get("anchor_tile_id", -1)) != int(ref.get("anchor_tile_id", -1))
			or not _integer_arrays_equal(metadata.get("occupied_tile_ids", []), ref.get("occupied_tile_ids", []))
			or not _reference_status_matches_job(str(ref.get("status", "")), str(job.get("status", "")))
		):
			return {"valid": false, "error": "station_job_reference_mismatch"}
	for ref_value: Variant in current.get("network_refs", []):
		var ref: Dictionary = ref_value
		var job_id := str(ref.get("job_id", ""))
		var project_id := str(ref.get("project_id", ""))
		if not jobs.has(job_id) or not jobs[job_id] is Dictionary or not projects.has(project_id) or not projects[project_id] is Dictionary:
			return {"valid": false, "error": "network_reference_missing"}
		var job: Dictionary = jobs[job_id]
		var project: Dictionary = projects[project_id]
		var metadata_value: Variant = job.get("metadata", null)
		if not metadata_value is Dictionary:
			return {"valid": false, "error": "network_job_metadata_missing"}
		var metadata: Dictionary = metadata_value
		if (
			str(metadata.get("entity_kind", "")) != "transport_project"
			or str(metadata.get("transport_project_id", "")) != project_id
			or str(metadata.get("transport_kind", "")) != str(ref.get("kind", ""))
			or not _reference_status_matches_job(str(ref.get("status", "")), str(job.get("status", "")))
			or not _reference_status_matches_project(str(ref.get("status", "")), str(project.get("status", "")))
		):
			return {"valid": false, "error": "network_reference_mismatch"}
	var completed_station_ids := _completed_station_ids(current)
	for route_value: Variant in current.get("route_refs", []):
		var route_id := str(route_value)
		if not routes.has(route_id) or not routes[route_id] is Dictionary:
			return {"valid": false, "error": "route_reference_missing"}
		var route: Dictionary = routes[route_id]
		if str(route.get("id", "")) != route_id or str(route.get("mode", "")) != str(current.get("mode", "")):
			return {"valid": false, "error": "route_reference_mode_mismatch"}
		var stop_ids_value: Variant = route.get("stop_ids", null)
		if not stop_ids_value is Array:
			return {"valid": false, "error": "route_reference_station_mismatch"}
		for stop_id_value: Variant in stop_ids_value:
			if not stop_id_value is String or not completed_station_ids.has(str(stop_id_value)):
				return {"valid": false, "error": "route_reference_station_mismatch"}
	return {"valid": true, "error": ""}


static func _reused_route_draft_placements_match_authority(
	current: Dictionary,
	station_placements: Array,
	stations: Dictionary,
	buildings: Dictionary
) -> bool:
	var terrain_mapping = CityTerrainMapScript.new()
	for placement_value: Variant in station_placements:
		if not placement_value is Dictionary:
			return false
		var placement: Dictionary = placement_value
		if not bool(placement.get("reuse_existing_station", false)):
			continue
		var station_id := str(placement.get("existing_station_id", ""))
		if station_id.is_empty() or not stations.has(station_id) or not stations[station_id] is Dictionary:
			return false
		if not buildings.has(station_id) or not buildings[station_id] is Dictionary:
			return false
		var station: Dictionary = stations[station_id]
		var building: Dictionary = buildings[station_id]
		var footprint_validation := BuildingFootprintsScript.validate_persisted_record(building, terrain_mapping)
		if not bool(footprint_validation.get("valid", false)):
			return false
		var anchor_tile_id := int(placement.get("anchor_tile_id", -1))
		var canonical_tiles: Array = Array(footprint_validation.get("occupied_tile_ids", []))
		if (
			str(station.get("id", "")) != station_id
			or str(station.get("building_name", "")) != str(current.get("station_blueprint_name", ""))
			or int(station.get("tile_id", -1)) != anchor_tile_id
			or str(station.get("status", "")) != "completed"
			or str(building.get("building_id", "")) != station_id
			or str(building.get("status", "")) != "active"
			or str(building.get("building_name", "")) != str(current.get("station_blueprint_name", ""))
			or int(building.get("anchor_tile_id", building.get("tile_index", -1))) != anchor_tile_id
			or str(placement.get("footprint_id", "")) != str(footprint_validation.get("footprint_id", ""))
			or not _integer_arrays_equal(placement.get("occupied_tile_ids", []), canonical_tiles)
		):
			return false
	return true


static func _existing_station_reference_matches_placement(
	ref: Dictionary,
	station_placements: Array,
	ref_index: int
) -> bool:
	if ref_index < 0 or ref_index >= station_placements.size():
		return false
	var placement_value: Variant = station_placements[ref_index]
	if not placement_value is Dictionary:
		return false
	var placement: Dictionary = placement_value
	return (
		bool(placement.get("reuse_existing_station", false))
		and str(placement.get("existing_station_id", "")) == str(ref.get("station_id", ""))
		and int(placement.get("anchor_tile_id", -1)) == int(ref.get("anchor_tile_id", -1))
		and _integer_arrays_equal(placement.get("occupied_tile_ids", []), ref.get("occupied_tile_ids", []))
	)


static func _existing_station_building_matches_reference(
	station_id: String,
	ref: Dictionary,
	current: Dictionary,
	buildings: Dictionary
) -> bool:
	if not buildings.has(station_id) or not buildings[station_id] is Dictionary:
		return false
	var building: Dictionary = buildings[station_id]
	return (
		str(building.get("building_id", "")) == station_id
		and str(building.get("status", "")) == "active"
		and str(building.get("building_name", "")) == str(current.get("station_blueprint_name", ""))
		and int(building.get("anchor_tile_id", building.get("tile_index", -1))) == int(ref.get("anchor_tile_id", -1))
		and _integer_arrays_equal(building.get("occupied_tile_ids", []), ref.get("occupied_tile_ids", []))
	)


func _resume_after_jobs_if_ready() -> void:
	if str(session.get("state", "")) != STATE_WAITING_CONSTRUCTION or has_active_jobs():
		return
	var resume_state := str(session.get("resume_state", ""))
	session["state"] = resume_state if resume_state in RESUMABLE_STATES else STATE_NETWORK_PLACEMENT
	session["resume_state"] = ""


func _set_reference_job_status(field_name: String, job_id: String, status: String) -> bool:
	var refs: Array = Array(session.get(field_name, [])).duplicate(true)
	for index in range(refs.size()):
		var ref_value: Variant = refs[index]
		if not ref_value is Dictionary or str((ref_value as Dictionary).get("job_id", "")) != job_id:
			continue
		var ref: Dictionary = (ref_value as Dictionary).duplicate(true)
		ref["status"] = status
		refs[index] = ref
		session[field_name] = refs
		return true
	return false


func _success(extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "session": snapshot()}
	result.merge(extra, true)
	return result


static func _error(error_code: String, extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "error": error_code}
	result.merge(extra, true)
	return result


static func _inactive_session() -> Dictionary:
	return {"state": STATE_INACTIVE}


static func network_kind_matches_mode(mode: String, network_kind: String) -> bool:
	return _network_kind_matches_mode(network_kind, TransportModesScript.route_spec(mode))


static func _network_kind_matches_mode(network_kind: String, mode_spec: Dictionary) -> bool:
	var guideway_kind := str(mode_spec.get("guideway_kind", ""))
	if network_kind == guideway_kind:
		return true
	var depot_kind := str(mode_spec.get("required_depot_kind", ""))
	if not depot_kind.is_empty() and network_kind == depot_kind:
		return true
	# Facilities whose canonical network_kind matches the session guideway are
	# supporting infrastructure for the same mode (for example rail signals).
	var facility_spec := TransportModesScript.facility_spec(network_kind)
	if not facility_spec.is_empty() and str(facility_spec.get("network_kind", "")) == guideway_kind:
		return true
	# Air topology models taxiways as their own segment kind rather than a
	# facility, but they remain a runway-session support project.
	return guideway_kind == "runway" and network_kind == "taxiway"


static func _is_network_kind(kind: String) -> bool:
	return kind in TransportModesScript.SEGMENT_KINDS or kind in TransportModesScript.FACILITY_KINDS


static func _valid_ref_strings(ref: Dictionary, fields: Array[String]) -> bool:
	for field_name: String in fields:
		if not ref.get(field_name, null) is String:
			return false
	return true


static func _valid_unique_integer_array(value: Variant) -> bool:
	if not value is Array or (value as Array).is_empty():
		return false
	var seen: Dictionary = {}
	for item: Variant in value:
		if not _is_integer_value(item) or int(item) < 0 or int(item) >= 100 or seen.has(int(item)):
			return false
		seen[int(item)] = true
	return true


static func _integer_array_has(value: Variant, expected: int) -> bool:
	if not value is Array:
		return false
	for item: Variant in value:
		if _is_integer_value(item) and int(item) == expected:
			return true
	return false


static func _integer_arrays_equal(left: Variant, right: Variant) -> bool:
	if not left is Array or not right is Array or (left as Array).size() != (right as Array).size():
		return false
	for index in range((left as Array).size()):
		if (
			not _is_integer_value((left as Array)[index])
			or not _is_integer_value((right as Array)[index])
			or int((left as Array)[index]) != int((right as Array)[index])
		):
			return false
	return true


static func _snapshot_has_active_jobs(current: Dictionary) -> bool:
	for field_name: String in ["station_refs", "network_refs"]:
		for ref_value: Variant in current.get(field_name, []):
			if ref_value is Dictionary and str((ref_value as Dictionary).get("status", "")) == "active":
				return true
	return false


static func _validate_state_semantics(current: Dictionary) -> String:
	if str(current.get("workflow", "")) == WORKFLOW_ROUTE_PACKAGE_V1:
		return _validate_route_package_semantics(current)
	var state := str(current.get("state", ""))
	var resume_state := str(current.get("resume_state", ""))
	var closed_reason := str(current.get("closed_reason", ""))
	if state == STATE_CLOSED:
		if not resume_state.is_empty() or closed_reason.is_empty():
			return "invalid_closed_session_fields"
		return _validate_closed_history_semantics(current)
	if not closed_reason.is_empty():
		return "unexpected_closed_reason"
	if state in [STATE_WAITING_CONSTRUCTION, STATE_PAUSED]:
		if resume_state not in RESUMABLE_STATES:
			return "invalid_resume_state"
		if state == STATE_WAITING_CONSTRUCTION and not _snapshot_has_active_jobs(current):
			return "waiting_without_active_jobs"
		return _validate_phase_semantics(current, resume_state)
	if not resume_state.is_empty():
		return "unexpected_resume_state"
	if state == STATE_MATERIALIZED:
		return _validate_materialized_semantics(current)
	return _validate_phase_semantics(current, state)


static func _validate_route_package_semantics(current: Dictionary) -> String:
	var state := str(current.get("state", ""))
	var resume_state := str(current.get("resume_state", ""))
	var closed_reason := str(current.get("closed_reason", ""))
	if state == STATE_CLOSED:
		if closed_reason.is_empty() or not resume_state.is_empty():
			return "invalid_closed_session_fields"
		return ""
	if not closed_reason.is_empty():
		return "unexpected_closed_reason"
	if state == STATE_MATERIALIZED:
		return _validate_materialized_semantics(current)
	if state == STATE_PAUSED:
		if resume_state not in RESUMABLE_STATES:
			return "invalid_resume_state"
		return _validate_route_package_phase(current, resume_state)
	if state == STATE_WAITING_CONSTRUCTION:
		if resume_state != STATE_ROUTE_EDIT or not _snapshot_has_active_jobs(current):
			return "waiting_without_active_jobs"
		return _validate_route_package_phase(current, STATE_ROUTE_EDIT, true)
	if not resume_state.is_empty():
		return "unexpected_resume_state"
	return _validate_route_package_phase(current, state)


static func _validate_route_package_phase(current: Dictionary, phase: String, materializing: bool = false) -> String:
	var station_refs: Array = current.get("station_refs", [])
	var network_refs: Array = current.get("network_refs", [])
	var route_refs: Array = current.get("route_refs", [])
	var network_draft: Dictionary = current.get("network_draft", {})
	var route_draft: Dictionary = current.get("route_draft", {})
	var placements_value: Variant = route_draft.get("station_placements", null)
	if not placements_value is Array:
		return "invalid_station_drafts"
	var placements: Array = placements_value
	var seen_anchors: Dictionary = {}
	var seen_tiles: Dictionary = {}
	for placement_value: Variant in placements:
		if not placement_value is Dictionary:
			return "invalid_station_draft"
		var placement: Dictionary = placement_value
		var anchor := int(placement.get("anchor_tile_id", -1))
		if anchor < 0 or anchor >= 100 or seen_anchors.has(anchor):
			return "invalid_station_draft"
		seen_anchors[anchor] = true
		var occupied_value: Variant = placement.get("occupied_tile_ids", null)
		if not _valid_unique_integer_array(occupied_value) or not _integer_array_has(occupied_value, anchor):
			return "invalid_station_draft"
		for tile_value: Variant in occupied_value:
			var tile_id := int(tile_value)
			if seen_tiles.has(tile_id):
				return "station_draft_overlap"
			seen_tiles[tile_id] = true
		var reuse_existing := bool(placement.get("reuse_existing_station", false))
		if reuse_existing:
			if (
				str(placement.get("existing_station_id", "")).is_empty()
				or not placement.get("blueprint", null) is Dictionary
				or int(placement.get("worker_count", -1)) != 0
				or int(placement.get("building_cost", -1)) != 0
				or int(placement.get("duration_days", -1)) != 0
			):
				return "invalid_existing_station_draft"
		elif (
			str(placement.get("library_id", "")).is_empty()
			or not placement.get("blueprint", null) is Dictionary
			or int(placement.get("worker_count", 0)) < 1
			or int(placement.get("building_cost", -1)) < 0
		):
			return "invalid_station_draft"
	if phase == STATE_STATION_PLACEMENT:
		if not station_refs.is_empty() or not network_refs.is_empty() or not route_refs.is_empty() or not network_draft.is_empty():
			return "unreachable_station_placement_state"
		return ""
	var minimum_stops := _minimum_stops(current)
	if placements.size() < minimum_stops:
		return "transport_session_requires_more_stations"
	var network_kind := str(network_draft.get("kind", ""))
	if not _network_kind_matches_mode(network_kind, TransportModesScript.route_spec(str(current.get("mode", "")))):
		return "transport_session_network_kind_mismatch"
	if phase == STATE_NETWORK_PLACEMENT:
		if not station_refs.is_empty() or not network_refs.is_empty() or not route_refs.is_empty():
			return "unreachable_network_placement_state"
		return ""
	if phase != STATE_ROUTE_EDIT:
		return "invalid_session_state"
	var tile_ids_value: Variant = network_draft.get("tile_ids", null)
	if not _valid_unique_integer_array(tile_ids_value):
		return "transport_session_network_required"
	if str(route_draft.get("mode", "")) != str(current.get("mode", "")):
		return "route_draft_mode_mismatch"
	if not route_refs.is_empty():
		return "unreachable_route_edit_state"
	if materializing:
		if station_refs.size() != placements.size() or network_refs.is_empty():
			return "invalid_route_package_jobs"
	elif not station_refs.is_empty() or not network_refs.is_empty():
		return "route_package_jobs_before_confirmation"
	return ""


static func _validate_closed_history_semantics(current: Dictionary) -> String:
	if not Array(current.get("route_refs", [])).is_empty():
		return _validate_materialized_semantics(current)
	if not Dictionary(current.get("route_draft", {})).is_empty():
		return _validate_phase_semantics(current, STATE_ROUTE_EDIT)
	if (
		not Array(current.get("network_refs", [])).is_empty()
		or not Dictionary(current.get("network_draft", {})).is_empty()
	):
		return _validate_phase_semantics(current, STATE_NETWORK_PLACEMENT)
	return _validate_phase_semantics(current, STATE_STATION_PLACEMENT)


static func _validate_phase_semantics(current: Dictionary, phase: String) -> String:
	var station_refs: Array = current.get("station_refs", [])
	var network_refs: Array = current.get("network_refs", [])
	var route_refs: Array = current.get("route_refs", [])
	var network_draft: Dictionary = current.get("network_draft", {})
	var route_draft: Dictionary = current.get("route_draft", {})
	if phase == STATE_STATION_PLACEMENT:
		if not network_refs.is_empty() or not route_refs.is_empty() or not network_draft.is_empty() or not route_draft.is_empty():
			return "unreachable_station_placement_state"
		return ""
	var minimum_stops := _minimum_stops(current)
	if station_refs.size() < minimum_stops:
		return "transport_session_requires_more_stations"
	if phase == STATE_NETWORK_PLACEMENT:
		if not route_refs.is_empty() or not route_draft.is_empty():
			return "unreachable_network_placement_state"
		var network_kind := str(network_draft.get("kind", ""))
		if not _network_kind_matches_mode(network_kind, TransportModesScript.route_spec(str(current.get("mode", "")))):
			return "transport_session_network_kind_mismatch"
		return ""
	if phase != STATE_ROUTE_EDIT:
		return "invalid_session_state"
	if _completed_station_ids(current).size() < minimum_stops:
		return "transport_session_completed_stations_required"
	if not route_refs.is_empty():
		return "unreachable_route_edit_state"
	var guideway_kind := str(TransportModesScript.route_spec(str(current.get("mode", ""))).get("guideway_kind", ""))
	if not _has_non_cancelled_network_kind(current, guideway_kind):
		return "transport_session_network_required"
	if str(route_draft.get("mode", "")) != str(current.get("mode", "")):
		return "route_draft_mode_mismatch"
	return ""


static func _validate_materialized_semantics(current: Dictionary) -> String:
	var route_refs: Array = current.get("route_refs", [])
	if route_refs.size() != 1:
		return "materialized_route_required"
	var minimum_stops := _minimum_stops(current)
	if _completed_station_ids(current).size() < minimum_stops:
		return "materialized_completed_stations_required"
	var mode_spec := TransportModesScript.route_spec(str(current.get("mode", "")))
	var guideway_kind := str(mode_spec.get("guideway_kind", ""))
	if not _has_completed_network_kind(current, guideway_kind):
		return "materialized_completed_guideway_required"
	var depot_kind := str(mode_spec.get("required_depot_kind", ""))
	if not depot_kind.is_empty() and not _has_completed_network_kind(current, depot_kind):
		return "materialized_completed_depot_required"
	if str(Dictionary(current.get("route_draft", {})).get("mode", "")) != str(current.get("mode", "")):
		return "route_draft_mode_mismatch"
	return ""


static func _minimum_stops(current: Dictionary) -> int:
	return int(TransportModesScript.route_spec(str(current.get("mode", ""))).get("minimum_stops", 1))


static func _completed_station_ids(current: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for ref_value: Variant in current.get("station_refs", []):
		if not ref_value is Dictionary:
			continue
		var ref: Dictionary = ref_value
		var station_id := str(ref.get("station_id", ""))
		if str(ref.get("status", "")) == "completed" and not station_id.is_empty():
			result[station_id] = true
	return result


static func _has_non_cancelled_network_kind(current: Dictionary, kind: String) -> bool:
	for ref_value: Variant in current.get("network_refs", []):
		if (
			ref_value is Dictionary
			and str((ref_value as Dictionary).get("kind", "")) == kind
			and str((ref_value as Dictionary).get("status", "")) != "cancelled"
		):
			return true
	return false


static func _has_completed_network_kind(current: Dictionary, kind: String) -> bool:
	for ref_value: Variant in current.get("network_refs", []):
		if (
			ref_value is Dictionary
			and str((ref_value as Dictionary).get("kind", "")) == kind
			and str((ref_value as Dictionary).get("status", "")) == "completed"
		):
			return true
	return false


static func _is_integer_value(value: Variant) -> bool:
	return value is int or (value is float and is_equal_approx(float(value), floor(float(value))))


static func _reference_status_matches_job(reference_status: String, job_status: String) -> bool:
	return (
		(reference_status == "active" and job_status == "active")
		or (reference_status == "completed" and job_status == "completed")
		or (reference_status == "cancelled" and job_status == "cancelled")
	)


static func _reference_status_matches_project(reference_status: String, project_status: String) -> bool:
	return (
		(reference_status == "active" and project_status == "under_construction")
		or (reference_status == "completed" and project_status == "completed")
		or (reference_status == "cancelled" and project_status in ["planned", "under_construction"])
	)


static func _normalize_corridor_quote(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var source: Dictionary = value
	var corridor: Dictionary = source.get("corridor", {})
	var refs: Array[Dictionary] = []
	for ref_value: Variant in corridor.get("reused_segment_refs", []):
		if ref_value is Dictionary:
			var ref: Dictionary = ref_value
			refs.append({
				"id": str(ref.get("id", "")),
				"kind": str(ref.get("kind", "")),
				"tile_ids": _normalized_int_array(ref.get("tile_ids", [])),
			})
	var runs: Array[Dictionary] = []
	for run_value: Variant in corridor.get("new_runs", []):
		if run_value is Dictionary:
			var run: Dictionary = run_value
			runs.append({
				"kind": str(run.get("kind", "")),
				"tile_path": _normalized_int_array(run.get("tile_path", [])),
			})
	var normalized_corridor := {
		"schema_version": int(corridor.get("schema_version", -1)),
		"mode": str(corridor.get("mode", "")),
		"segment_kind": str(corridor.get("segment_kind", "")),
		"classification": str(corridor.get("classification", "")),
		"route_tile_ids": _normalized_int_array(corridor.get("route_tile_ids", [])),
		"reused_segment_refs": refs,
		"new_runs": runs,
		"total_units": int(corridor.get("total_units", -1)),
		"reused_units": int(corridor.get("reused_units", -1)),
		"new_units": int(corridor.get("new_units", -1)),
	}
	var price_breakdown: Dictionary = source.get("price_breakdown", {})
	var maintenance_breakdown: Dictionary = source.get("maintenance_breakdown", {})
	var result := {
		"quote_schema_version": int(source.get("quote_schema_version", -1)),
		"price_model": str(source.get("price_model", "")),
		"price_provenance": str(source.get("price_provenance", "")),
		"corridor": normalized_corridor,
		"price_breakdown": {
			"reused_corridor": int(price_breakdown.get("reused_corridor", -1)),
			"new_corridor": int(price_breakdown.get("new_corridor", -1)),
		},
		"maintenance_breakdown": {
			"reused_corridor": int(maintenance_breakdown.get("reused_corridor", -1)),
			"new_corridor": int(maintenance_breakdown.get("new_corridor", -1)),
		},
		"total_cost": int(source.get("total_cost", -1)),
		"monthly_maintenance": int(source.get("monthly_maintenance", -1)),
		"checksum_version": int(source.get("checksum_version", -1)),
		"checksum": str(source.get("checksum", "")),
	}
	if source.has("ok"):
		result["ok"] = bool(source.get("ok", false))
	return result


static func _normalized_int_array(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if value is Array:
		for item: Variant in value:
			result.append(int(item))
	return result
