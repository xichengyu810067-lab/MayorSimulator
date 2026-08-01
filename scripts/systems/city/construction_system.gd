class_name ConstructionSystem
extends RefCounted

## Deterministic, UI-agnostic blueprint review and construction scheduler.
## Every public payload is JSON-safe so it can be stored in a SaveEnvelope.

const SCHEMA_VERSION := 1
const MAX_WORKERS := 20
const REVIEW_MIN_DAYS := 2
const REVIEW_MAX_DAYS := 7
const VALID_OPERATIONS := ["build", "demolish", "move"]

var seed: int = 20_260_715
var next_review_sequence: int = 1
var next_job_sequence: int = 1
var reviews: Dictionary = {}
var jobs: Dictionary = {}
var workload_rules: Dictionary = default_workload_rules()


func _init(p_seed: int = 20_260_715, p_workload_rules: Dictionary = {}) -> void:
	seed = p_seed
	if not p_workload_rules.is_empty():
		workload_rules = p_workload_rules.duplicate(true)


static func default_workload_rules() -> Dictionary:
	return {
		"build": {
			"base": 20.0,
			"floor_points": 4.0,
			"decoration_points": 1.0,
			"size_multipliers": {"small": 0.8, "medium": 1.0, "large": 1.35},
			"material_multipliers": {"wood": 0.9, "brick": 1.0, "steel": 1.2, "concrete": 1.1, "eco_composite": 1.05}
		},
		"demolish": {
			"base": 8.0,
			"floor_points": 2.0,
			"decoration_points": 0.0,
			"size_multipliers": {"small": 0.8, "medium": 1.0, "large": 1.3},
			"material_multipliers": {"wood": 0.8, "brick": 1.0, "steel": 1.25, "concrete": 1.2, "eco_composite": 1.0}
		},
		"move": {
			"base": 14.0,
			"floor_points": 3.0,
			"decoration_points": 0.5,
			"size_multipliers": {"small": 0.8, "medium": 1.0, "large": 1.4},
			"material_multipliers": {"wood": 0.9, "brick": 1.0, "steel": 1.15, "concrete": 1.1, "eco_composite": 1.0}
		}
	}


static func effective_workers(worker_count: int) -> float:
	var clamped_workers := clampi(worker_count, 0, MAX_WORKERS)
	if clamped_workers <= 10:
		return float(clamped_workers)
	return 10.0 + float(clamped_workers - 10) * 0.9


static func duration_days(workload: float, worker_count: int) -> int:
	var effective := effective_workers(worker_count)
	if workload <= 0.0 or effective <= 0.0:
		return 0
	return int(ceil(workload / effective))


static func daily_labor_cost(worker_count: int) -> int:
	if worker_count <= 0:
		return 0
	var valid_workers := clampi(worker_count, 1, MAX_WORKERS)
	var rate := 2_000 if valid_workers <= 5 else 2_500
	return valid_workers * rate


static func total_labor_cost(workload: float, worker_count: int) -> int:
	return duration_days(workload, worker_count) * daily_labor_cost(worker_count)


static func calculate_workload_with_rules(
	blueprint: Dictionary,
	operation: String,
	rules: Dictionary
) -> float:
	if blueprint.has("workload") and blueprint["workload"] != null:
		return maxf(1.0, float(blueprint["workload"]))
	var operation_rule: Dictionary = rules.get(operation, {})
	if operation_rule.is_empty():
		return 0.0
	var floors := maxi(1, int(blueprint.get("floors", 1)))
	var decorations := maxi(0, int(blueprint.get("decoration_count", 0)))
	var points := float(operation_rule.get("base", 1.0))
	points += float(floors - 1) * float(operation_rule.get("floor_points", 0.0))
	points += float(decorations) * float(operation_rule.get("decoration_points", 0.0))
	var size_tier := str(blueprint.get("size_tier", "medium"))
	var material_id := str(blueprint.get("material_id", "brick"))
	var size_multipliers: Dictionary = operation_rule.get("size_multipliers", {})
	var material_multipliers: Dictionary = operation_rule.get("material_multipliers", {})
	points *= float(size_multipliers.get(size_tier, 1.0))
	points *= float(material_multipliers.get(material_id, 1.0))
	return maxf(1.0, ceil(points))


func calculate_workload(blueprint: Dictionary, operation: String = "build") -> float:
	return calculate_workload_with_rules(blueprint, operation, workload_rules)


func estimate_job(blueprint: Dictionary, operation: String, worker_count: int) -> Dictionary:
	var workload := calculate_workload(blueprint, operation)
	var days := duration_days(workload, worker_count)
	return {
		"operation": operation,
		"workload": workload,
		"worker_count": worker_count,
		"duration_days": days,
		"daily_labor_cost": daily_labor_cost(worker_count),
		"total_labor_cost": days * daily_labor_cost(worker_count)
	}


func submit_blueprint(
	blueprint: Dictionary,
	submitted_day: int,
	operation: String = "build"
) -> Dictionary:
	if operation not in VALID_OPERATIONS:
		return _error("invalid_operation")
	if operation == "demolish":
		return _error("demolition_does_not_require_blueprint_review")
	var normalized := _normalize_blueprint(blueprint)
	var validation_error := _validate_blueprint(normalized, operation)
	if not validation_error.is_empty():
		return _error(validation_error)
	var review_id := "review_%06d" % next_review_sequence
	var duration := _deterministic_review_days(review_id, normalized)
	var review := {
		"id": review_id,
		"sequence": next_review_sequence,
		"operation": operation,
		"blueprint": normalized,
		"submitted_day": submitted_day,
		"review_days": duration,
		"decision_day": submitted_day + duration,
		"status": "under_review",
		"decision_reason": ""
	}
	reviews[review_id] = review
	next_review_sequence += 1
	return {"ok": true, "review": review.duplicate(true)}


func advance_reviews(current_day: int, context: Dictionary = {}) -> Array[Dictionary]:
	var emitted: Array[Dictionary] = []
	for review_id in _sorted_string_keys(reviews):
		var review: Dictionary = reviews[review_id]
		if str(review.get("status", "")) != "under_review":
			continue
		if current_day < int(review.get("decision_day", 0)):
			continue
		var decision := _evaluate_review(review, context)
		review["status"] = "approved" if bool(decision["approved"]) else "rejected"
		review["decision_reason"] = str(decision["reason"])
		review["resolved_day"] = current_day
		reviews[review_id] = review
		emitted.append({
			"type": "blueprint_%s" % review["status"],
			"subject_id": review_id,
			"game_day": current_day,
			"reason_tag": review["decision_reason"],
			"payload": review.duplicate(true)
		})
	return emitted


func start_approved_job(
	review_id: String,
	worker_count: int,
	start_day: int,
	target_id: String = "",
	metadata: Dictionary = {}
) -> Dictionary:
	if not reviews.has(review_id):
		return _error("review_not_found")
	var review: Dictionary = reviews[review_id]
	if str(review.get("status", "")) != "approved":
		return _error("blueprint_not_approved")
	var result := _start_job(
		str(review.get("operation", "build")),
		review.get("blueprint", {}),
		worker_count,
		start_day,
		target_id,
		review_id,
		metadata
	)
	if bool(result.get("ok", false)):
		review["status"] = "in_construction"
		review["job_id"] = str(result["job"]["id"])
		reviews[review_id] = review
	return result


func start_reusable_blueprint_job(
	approval_id: String,
	blueprint: Dictionary,
	worker_count: int,
	start_day: int,
	target_id: String = "",
	metadata: Dictionary = {}
) -> Dictionary:
	# Approved blueprint-library entries are durable permits, not consumable
	# review tickets. Reusing one starts an independent job without mutating the
	# historical review that originally granted approval.
	if approval_id.is_empty():
		return _error("approved_blueprint_required")
	var normalized := _normalize_blueprint(blueprint)
	var validation_error := _validate_blueprint(normalized, "build")
	if not validation_error.is_empty():
		return _error(validation_error)
	var job_metadata := metadata.duplicate(true)
	job_metadata["blueprint_library_id"] = approval_id
	return _start_job(
		"build",
		normalized,
		worker_count,
		start_day,
		target_id,
		"",
		job_metadata
	)


func start_operation(
	operation: String,
	payload: Dictionary,
	worker_count: int,
	start_day: int,
	target_id: String,
	metadata: Dictionary = {}
) -> Dictionary:
	if operation not in ["demolish", "move"]:
		return _error("operation_requires_approved_blueprint")
	return _start_job(operation, payload, worker_count, start_day, target_id, "", metadata)


func start_infrastructure_job(
	operation: String,
	infrastructure_kind: String,
	tile_indices: Array,
	worker_count: int,
	start_day: int,
	metadata: Dictionary = {}
) -> Dictionary:
	## Infrastructure projects reuse the authoritative worker scheduler without
	## pretending that a road or rail corridor is a single building blueprint.
	if operation not in ["build", "demolish"]:
		return _error("invalid_infrastructure_operation")
	if infrastructure_kind.strip_edges().is_empty():
		return _error("missing_infrastructure_kind")
	var normalized_tiles: Array[int] = []
	for tile_variant: Variant in tile_indices:
		var tile_index := int(tile_variant)
		if tile_index < 0 or normalized_tiles.has(tile_index):
			return _error("invalid_infrastructure_tiles")
		normalized_tiles.append(tile_index)
	if normalized_tiles.is_empty():
		return _error("invalid_infrastructure_tiles")
	var work_per_tile: float = float({
		"road": 5.0,
		"metro_track": 9.0,
		"rail_track": 8.0,
		"runway": 11.0,
		"taxiway": 7.0,
		"bus_depot": 12.0,
		"metro_depot": 16.0,
		"rail_depot": 16.0,
		"rail_signal": 4.0,
	}.get(infrastructure_kind, 7.0))
	var blueprint := {
		"id": "transport_%s_%s" % [operation, infrastructure_kind],
		"version": 1,
		"building_id": "transport_%s" % infrastructure_kind,
		"material_id": "steel",
		"floors": 1,
		"size_tier": "medium",
		"decoration_count": 0,
		"requested_workers": worker_count,
		"base_cost": 0,
		"workload": maxf(1.0, float(normalized_tiles.size()) * float(work_per_tile)),
	}
	var job_metadata := metadata.duplicate(true)
	job_metadata["entity_kind"] = "transport_project"
	job_metadata["infrastructure_kind"] = infrastructure_kind
	job_metadata["tile_indices"] = normalized_tiles.duplicate()
	return _start_job(
		operation,
		blueprint,
		worker_count,
		start_day,
		str(job_metadata.get("project_id", "transport_%s" % infrastructure_kind)),
		"",
		job_metadata
	)


func reassign_workers(job_id: String, worker_count: int, current_day: int) -> Dictionary:
	if not jobs.has(job_id):
		return _error("job_not_found")
	if worker_count < 1 or worker_count > MAX_WORKERS:
		return _error("invalid_worker_count")
	var job: Dictionary = jobs[job_id]
	if str(job.get("status", "")) != "active":
		return _error("job_not_active")
	var available_with_current := available_workers() + int(job.get("worker_count", 0))
	if worker_count > available_with_current:
		return _error("insufficient_workers")
	job["worker_count"] = worker_count
	job["projected_remaining_days"] = duration_days(float(job["remaining_work"]), worker_count)
	job["last_assignment_day"] = current_day
	jobs[job_id] = job
	return {"ok": true, "job": job.duplicate(true)}


func cancel_job(job_id: String, current_day: int) -> Dictionary:
	if not jobs.has(job_id):
		return _error("job_not_found")
	var job: Dictionary = jobs[job_id]
	if str(job.get("status", "")) != "active":
		return _error("job_not_active")
	job["status"] = "cancelled"
	job["cancelled_day"] = current_day
	jobs[job_id] = job
	return {"ok": true, "job": job.duplicate(true)}


func advance_jobs_day(current_day: int) -> Array[Dictionary]:
	var emitted: Array[Dictionary] = []
	for job_id in _sorted_string_keys(jobs):
		var job: Dictionary = jobs[job_id]
		if str(job.get("status", "")) != "active":
			continue
		var workers := int(job.get("worker_count", 0))
		var labor_cost := daily_labor_cost(workers)
		job["elapsed_days"] = int(job.get("elapsed_days", 0)) + 1
		job["labor_cost_paid"] = int(job.get("labor_cost_paid", 0)) + labor_cost
		job["remaining_work"] = maxf(
			0.0,
			float(job.get("remaining_work", 0.0)) - effective_workers(workers)
		)
		job["projected_remaining_days"] = duration_days(float(job["remaining_work"]), workers)
		emitted.append({
			"type": "construction_labor_charged",
			"subject_id": job_id,
			"game_day": current_day,
			"value_delta": -labor_cost,
			"reason_tag": "construction_labor.%s" % str(job.get("operation", "build")),
			"payload": {"worker_count": workers}
		})
		if float(job["remaining_work"]) <= 0.0:
			job["status"] = "completed"
			job["completed_day"] = current_day
			var review_id := str(job.get("review_id", ""))
			if not review_id.is_empty() and reviews.has(review_id):
				var review: Dictionary = reviews[review_id]
				review["status"] = "completed"
				reviews[review_id] = review
			emitted.append({
				"type": "construction_completed",
				"subject_id": job_id,
				"game_day": current_day,
				"reason_tag": "construction.%s.completed" % str(job.get("operation", "build")),
				"payload": job.duplicate(true)
			})
		jobs[job_id] = job
	return emitted


func available_workers() -> int:
	var allocated := 0
	for job in jobs.values():
		if str(job.get("status", "")) == "active":
			allocated += int(job.get("worker_count", 0))
	return maxi(0, MAX_WORKERS - allocated)


func active_jobs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for job_id in _sorted_string_keys(jobs):
		var job: Dictionary = jobs[job_id]
		if str(job.get("status", "")) == "active":
			result.append(job.duplicate(true))
	return result


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"seed": seed,
		"next_review_sequence": next_review_sequence,
		"next_job_sequence": next_job_sequence,
		"workload_rules": workload_rules.duplicate(true),
		"reviews": reviews.duplicate(true),
		"jobs": jobs.duplicate(true)
	}


func load_dict(data: Dictionary) -> void:
	seed = int(data.get("seed", 20_260_715))
	next_review_sequence = int(data.get("next_review_sequence", 1))
	next_job_sequence = int(data.get("next_job_sequence", 1))
	workload_rules = data.get("workload_rules", default_workload_rules()).duplicate(true)
	reviews = data.get("reviews", {}).duplicate(true)
	jobs = data.get("jobs", {}).duplicate(true)


static func create_from_dict(data: Dictionary) -> ConstructionSystem:
	var instance := ConstructionSystem.new()
	instance.load_dict(data)
	return instance


func _start_job(
	operation: String,
	blueprint: Dictionary,
	worker_count: int,
	start_day: int,
	target_id: String,
	review_id: String,
	metadata: Dictionary
) -> Dictionary:
	if operation not in VALID_OPERATIONS:
		return _error("invalid_operation")
	if worker_count < 1 or worker_count > MAX_WORKERS:
		return _error("invalid_worker_count")
	if worker_count > available_workers():
		return _error("insufficient_workers")
	var workload := calculate_workload(blueprint, operation)
	if workload <= 0.0:
		return _error("invalid_workload")
	var job_id := "job_%06d" % next_job_sequence
	var total_days := duration_days(workload, worker_count)
	var job := {
		"id": job_id,
		"sequence": next_job_sequence,
		"operation": operation,
		"review_id": review_id,
		"target_id": target_id,
		"blueprint": _normalize_blueprint(blueprint),
		"worker_count": worker_count,
		"workload": workload,
		"remaining_work": workload,
		"start_day": start_day,
		"elapsed_days": 0,
		"projected_total_days": total_days,
		"projected_remaining_days": total_days,
		"projected_labor_cost": total_days * daily_labor_cost(worker_count),
		"labor_cost_paid": 0,
		"status": "active",
		"metadata": metadata.duplicate(true)
	}
	jobs[job_id] = job
	next_job_sequence += 1
	return {"ok": true, "job": job.duplicate(true)}


func _evaluate_review(review: Dictionary, context: Dictionary) -> Dictionary:
	var blueprint: Dictionary = review.get("blueprint", {})
	var operation := str(review.get("operation", "build"))
	var validation_error := _validate_blueprint(blueprint, operation)
	if not validation_error.is_empty():
		return {"approved": false, "reason": validation_error}
	var blocked_ids: Array = context.get("blocked_building_ids", [])
	if str(blueprint.get("building_id", "")) in blocked_ids:
		return {"approved": false, "reason": "building_type_blocked"}
	if not bool(context.get("permits_enabled", true)):
		return {"approved": false, "reason": "permits_suspended"}
	var requested_workers := clampi(int(blueprint.get("requested_workers", 5)), 1, MAX_WORKERS)
	var estimate := estimate_job(blueprint, operation, requested_workers)
	var available_budget := float(context.get("available_budget", 1.0e30))
	var non_labor_cost := float(blueprint.get("base_cost", 0.0))
	if available_budget < non_labor_cost + float(estimate["total_labor_cost"]):
		return {"approved": false, "reason": "insufficient_budget"}
	if float(context.get("citizen_support", 50.0)) < 20.0:
		return {"approved": false, "reason": "insufficient_public_support"}
	return {"approved": true, "reason": "review_rules_satisfied"}


func _normalize_blueprint(blueprint: Dictionary) -> Dictionary:
	var normalized := {
		"id": str(blueprint.get("id", blueprint.get("blueprint_id", ""))),
		"version": maxi(1, int(blueprint.get("version", 1))),
		"building_id": str(blueprint.get("building_id", blueprint.get("building_type", ""))),
		"material_id": str(blueprint.get("material_id", "brick")),
		"floors": maxi(1, int(blueprint.get("floors", 1))),
		"size_tier": str(blueprint.get("size_tier", "medium")),
		"roof_color": str(blueprint.get("roof_color", "default")),
		"wall_color": str(blueprint.get("wall_color", "default")),
		"decoration_id": str(blueprint.get("decoration_id", "none")),
		"decoration_count": maxi(0, int(blueprint.get("decoration_count", 0))),
		"requested_workers": clampi(int(blueprint.get("requested_workers", 5)), 1, MAX_WORKERS),
		"base_cost": maxi(0, int(blueprint.get("base_cost", 0)))
	}
	# Absence is meaningful: it delegates to the versioned workload rules.
	if blueprint.has("workload") and blueprint["workload"] != null:
		normalized["workload"] = maxf(1.0, float(blueprint["workload"]))
	return normalized


func _validate_blueprint(blueprint: Dictionary, operation: String) -> String:
	if operation not in VALID_OPERATIONS:
		return "invalid_operation"
	if str(blueprint.get("building_id", "")).is_empty():
		return "missing_building_id"
	if int(blueprint.get("floors", 0)) < 1:
		return "invalid_floors"
	if calculate_workload(blueprint, operation) <= 0.0:
		return "invalid_workload"
	return ""


func _deterministic_review_days(review_id: String, blueprint: Dictionary) -> int:
	var stable_text := "%d|%s|%s|%s|%d|%s" % [
		seed,
		review_id,
		str(blueprint.get("building_id", "")),
		str(blueprint.get("material_id", "")),
		int(blueprint.get("floors", 1)),
		str(blueprint.get("size_tier", "medium"))
	]
	var span := REVIEW_MAX_DAYS - REVIEW_MIN_DAYS + 1
	return REVIEW_MIN_DAYS + (_stable_int(stable_text) % span)


static func _stable_int(value: String) -> int:
	var result := 7
	for index in value.length():
		result = int((result * 31 + value.unicode_at(index)) % 2_147_483_647)
	return result


static func _sorted_string_keys(source: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key in source.keys():
		result.append(str(key))
	result.sort()
	return result


static func _error(code: String) -> Dictionary:
	return {"ok": false, "error": code}
