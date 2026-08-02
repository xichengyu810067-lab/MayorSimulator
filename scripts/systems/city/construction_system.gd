class_name ConstructionSystem
extends RefCounted

## Deterministic, UI-agnostic blueprint review and construction scheduler.
## Every public payload is JSON-safe so it can be stored in a SaveEnvelope.

const SCHEMA_VERSION := 1
const MAX_WORKERS := 20
const REVIEW_MIN_DAYS := 2
const REVIEW_MAX_DAYS := 7
const VALID_OPERATIONS := ["build", "demolish", "move"]
const VALID_REVIEW_OPERATIONS := ["build", "move"]
const VALID_REVIEW_STATUSES := ["under_review", "approved", "rejected", "in_construction", "completed"]
const VALID_JOB_STATUSES := ["active", "completed", "cancelled"]
const TERRAIN_FLATTEN_ENTITY_KIND := "terrain_flatten"
const TERRAIN_FLATTEN_BILLING_MODEL := "prepaid_total_once"
const TERRAIN_TILE_COUNT := 100
const TERRAIN_FLATTEN_WORKLOADS := {
	"trees": 12.0,
	"hill_cliff": 24.0,
	"river_lake": 36.0,
	"road_path": 18.0,
	"rail_track": 22.0,
}

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


static func infrastructure_blueprint(
	operation: String,
	infrastructure_kind: String,
	tile_count: int,
	worker_count: int
) -> Dictionary:
	## Canonical scheduler payload for transport infrastructure. Persistence
	## validation calls this same helper so a self-consistent forged workload
	## cannot drift away from the production job created here.
	if operation not in ["build", "demolish"]:
		return {}
	if infrastructure_kind.strip_edges().is_empty() or tile_count < 1:
		return {}
	if worker_count < 1 or worker_count > MAX_WORKERS:
		return {}
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
	return {
		"id": "transport_%s_%s" % [operation, infrastructure_kind],
		"version": 1,
		"building_id": "transport_%s" % infrastructure_kind,
		"material_id": "steel",
		"floors": 1,
		"size_tier": "medium",
		"roof_color": "default",
		"wall_color": "default",
		"decoration_id": "none",
		"decoration_count": 0,
		"requested_workers": worker_count,
		"base_cost": 0,
		"workload": maxf(1.0, float(tile_count) * work_per_tile),
	}


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


func estimate_terrain_flatten_job(
	tile_index: int,
	source_terrain_kind: String,
	fixed_cost: int,
	worker_count: int
) -> Dictionary:
	if tile_index < 0 or tile_index >= TERRAIN_TILE_COUNT:
		return _error("invalid_tile_id")
	if not TERRAIN_FLATTEN_WORKLOADS.has(source_terrain_kind):
		return _error("terrain_not_flattenable")
	if fixed_cost < 0:
		return _error("invalid_fixed_cost")
	if worker_count < 1 or worker_count > MAX_WORKERS:
		return _error("invalid_worker_count")
	var blueprint := terrain_flatten_blueprint(
		tile_index,
		source_terrain_kind,
		fixed_cost,
		worker_count
	)
	var estimate := estimate_job(blueprint, "build", worker_count)
	var labor_cost := int(estimate.get("total_labor_cost", 0))
	var total_cost := fixed_cost + labor_cost
	estimate["ok"] = true
	estimate["tile_index"] = tile_index
	estimate["source_terrain_kind"] = source_terrain_kind
	estimate["base_cost"] = fixed_cost
	estimate["fixed_cost"] = fixed_cost
	estimate["labor_cost"] = labor_cost
	estimate["total_cost"] = total_cost
	estimate["billing_model"] = TERRAIN_FLATTEN_BILLING_MODEL
	estimate["target_id"] = terrain_flatten_target_id(tile_index)
	estimate["blueprint"] = blueprint.duplicate(true)
	estimate["metadata"] = terrain_flatten_metadata(
		tile_index,
		source_terrain_kind,
		fixed_cost,
		labor_cost
	)
	return estimate


func start_terrain_flatten_job(
	tile_index: int,
	source_terrain_kind: String,
	fixed_cost: int,
	worker_count: int,
	start_day: int
) -> Dictionary:
	var estimate := estimate_terrain_flatten_job(
		tile_index,
		source_terrain_kind,
		fixed_cost,
		worker_count
	)
	if not bool(estimate.get("ok", false)):
		return estimate
	return _start_job(
		"build",
		Dictionary(estimate["blueprint"]),
		worker_count,
		start_day,
		str(estimate["target_id"]),
		"",
		Dictionary(estimate["metadata"])
	)


static func terrain_flatten_target_id(tile_index: int) -> String:
	return "terrain_tile_%03d" % tile_index


static func terrain_flatten_blueprint(
	tile_index: int,
	source_terrain_kind: String,
	fixed_cost: int,
	worker_count: int
) -> Dictionary:
	return {
		"id": "terrain_flatten_%03d_%s" % [tile_index, source_terrain_kind],
		"version": 1,
		"building_id": TERRAIN_FLATTEN_ENTITY_KIND,
		"material_id": "earthworks",
		"floors": 1,
		"size_tier": "small",
		"roof_color": "default",
		"wall_color": "default",
		"decoration_id": "none",
		"decoration_count": 0,
		"requested_workers": worker_count,
		"base_cost": fixed_cost,
		"workload": float(TERRAIN_FLATTEN_WORKLOADS.get(source_terrain_kind, 0.0)),
	}


static func terrain_flatten_metadata(
	tile_index: int,
	source_terrain_kind: String,
	fixed_cost: int,
	labor_cost: int
) -> Dictionary:
	return {
		"entity_kind": TERRAIN_FLATTEN_ENTITY_KIND,
		"tile_index": tile_index,
		"source_terrain_kind": source_terrain_kind,
		"base_cost": fixed_cost,
		"fixed_cost": fixed_cost,
		"labor_cost": labor_cost,
		"total_cost": fixed_cost + labor_cost,
		"billing_model": TERRAIN_FLATTEN_BILLING_MODEL,
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
	if worker_count < 1 or worker_count > MAX_WORKERS:
		return _error("invalid_worker_count")
	var normalized_tiles: Array[int] = []
	for tile_variant: Variant in tile_indices:
		var tile_index := int(tile_variant)
		if tile_index < 0 or normalized_tiles.has(tile_index):
			return _error("invalid_infrastructure_tiles")
		normalized_tiles.append(tile_index)
	if normalized_tiles.is_empty():
		return _error("invalid_infrastructure_tiles")
	var blueprint := infrastructure_blueprint(
		operation,
		infrastructure_kind,
		normalized_tiles.size(),
		worker_count
	)
	if blueprint.is_empty():
		return _error("invalid_infrastructure_blueprint")
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


static func validate_snapshot(snapshot: Dictionary) -> Dictionary:
	var schema_value: Variant = snapshot.get("schema_version", null)
	if not _is_integer_value(schema_value) or int(schema_value) != SCHEMA_VERSION:
		return _snapshot_error("unsupported_schema")
	if not _is_integer_value(snapshot.get("seed", null)):
		return _snapshot_error("invalid_seed")
	var workload_rules_value: Variant = snapshot.get("workload_rules", null)
	if not workload_rules_value is Dictionary:
		return _snapshot_error("invalid_workload_rules")
	var workload_rules: Dictionary = workload_rules_value
	var workload_rules_error := _validate_snapshot_workload_rules(workload_rules)
	if not workload_rules_error.is_empty():
		return _snapshot_error(workload_rules_error)
	var reviews_value: Variant = snapshot.get("reviews", null)
	var jobs_value: Variant = snapshot.get("jobs", null)
	if not reviews_value is Dictionary:
		return _snapshot_error("invalid_reviews")
	if not jobs_value is Dictionary:
		return _snapshot_error("invalid_jobs")
	var reviews: Dictionary = reviews_value
	var jobs: Dictionary = jobs_value
	var next_review_error := _validate_snapshot_sequence(
		snapshot.get("next_review_sequence", null), reviews, "review_", "next_review_sequence"
	)
	if not next_review_error.is_empty():
		return _snapshot_error(next_review_error)
	var next_job_error := _validate_snapshot_sequence(
		snapshot.get("next_job_sequence", null), jobs, "job_", "next_job_sequence"
	)
	if not next_job_error.is_empty():
		return _snapshot_error(next_job_error)
	for review_key: Variant in reviews.keys():
		var review_value: Variant = reviews[review_key]
		if not review_value is Dictionary:
			return _snapshot_error("invalid_review_record")
		var review: Dictionary = review_value
		var review_error := _validate_snapshot_review(review_key, review, workload_rules)
		if not review_error.is_empty():
			return _snapshot_error(review_error)
	for job_key: Variant in jobs.keys():
		var job_value: Variant = jobs[job_key]
		if not job_value is Dictionary:
			return _snapshot_error("invalid_job_record")
		var job: Dictionary = job_value
		var job_error := _validate_snapshot_job(job_key, job, workload_rules)
		if not job_error.is_empty():
			return _snapshot_error(job_error)
	var relationship_error := _validate_snapshot_review_job_relationships(reviews, jobs)
	if not relationship_error.is_empty():
		return _snapshot_error(relationship_error)
	return {"valid": true, "error": ""}


static func _validate_snapshot_sequence(
	value: Variant,
	records: Dictionary,
	generated_prefix: String,
	field_name: String
) -> String:
	if not _is_integer_value(value) or int(value) < 1:
		return "invalid_%s" % field_name
	var highest_existing := 0
	for record_key: Variant in records.keys():
		if not record_key is String:
			continue
		highest_existing = maxi(
			highest_existing,
			_generated_sequence(str(record_key), generated_prefix)
		)
	if int(value) <= highest_existing:
		return "%s_not_ahead" % field_name
	return ""


static func _validate_snapshot_workload_rules(rules: Dictionary) -> String:
	if not _is_json_safe(rules):
		return "invalid_workload_rules"
	for operation: String in VALID_OPERATIONS:
		var operation_value: Variant = rules.get(operation, null)
		if not operation_value is Dictionary:
			return "invalid_workload_rule_%s" % operation
		var operation_rule: Dictionary = operation_value
		for field_name: String in ["base", "floor_points", "decoration_points"]:
			if not _is_nonnegative_number(operation_rule.get(field_name, null)):
				return "invalid_workload_rule_%s_%s" % [operation, field_name]
		for multiplier_field: String in ["size_multipliers", "material_multipliers"]:
			var multipliers_value: Variant = operation_rule.get(multiplier_field, null)
			if not multipliers_value is Dictionary or (multipliers_value as Dictionary).is_empty():
				return "invalid_workload_rule_%s_%s" % [operation, multiplier_field]
			for multiplier_key: Variant in (multipliers_value as Dictionary).keys():
				if (
					not multiplier_key is String
					or str(multiplier_key).is_empty()
					or not _is_nonnegative_number((multipliers_value as Dictionary)[multiplier_key])
				):
					return "invalid_workload_rule_%s_%s_value" % [operation, multiplier_field]
	return ""


static func _validate_snapshot_review(
	review_key: Variant,
	review: Dictionary,
	rules: Dictionary
) -> String:
	if not review_key is String or str(review_key).is_empty():
		return "invalid_review_id"
	for field_name: String in [
		"id", "sequence", "operation", "blueprint", "submitted_day", "review_days",
		"decision_day", "status", "decision_reason",
	]:
		if not review.has(field_name):
			return "missing_review_field_%s" % field_name
	var review_id_value: Variant = review["id"]
	if not review_id_value is String or str(review_id_value) != str(review_key):
		return "invalid_review_id"
	var sequence_value: Variant = review["sequence"]
	if not _is_integer_value(sequence_value) or int(sequence_value) < 1:
		return "invalid_review_sequence"
	var generated_sequence := _generated_sequence(str(review_key), "review_")
	if generated_sequence > 0 and int(sequence_value) != generated_sequence:
		return "review_sequence_mismatch"
	var operation_value: Variant = review["operation"]
	if not operation_value is String or str(operation_value) not in VALID_REVIEW_OPERATIONS:
		return "invalid_review_operation"
	var blueprint_value: Variant = review["blueprint"]
	if not blueprint_value is Dictionary:
		return "invalid_review_blueprint"
	var blueprint: Dictionary = blueprint_value
	var blueprint_error := _validate_snapshot_blueprint(blueprint, false)
	if not blueprint_error.is_empty():
		return "invalid_review_blueprint_%s" % blueprint_error
	var calculated_workload := calculate_workload_with_rules(blueprint, str(operation_value), rules)
	if not _is_positive_number(calculated_workload):
		return "invalid_review_calculated_workload"
	var submitted_day_value: Variant = review["submitted_day"]
	var review_days_value: Variant = review["review_days"]
	var decision_day_value: Variant = review["decision_day"]
	if not _is_nonnegative_integer(submitted_day_value):
		return "invalid_review_submitted_day"
	if (
		not _is_integer_value(review_days_value)
		or int(review_days_value) < REVIEW_MIN_DAYS
		or int(review_days_value) > REVIEW_MAX_DAYS
	):
		return "invalid_review_days"
	if (
		not _is_nonnegative_integer(decision_day_value)
		or int(decision_day_value) != int(submitted_day_value) + int(review_days_value)
	):
		return "invalid_review_decision_day"
	var status_value: Variant = review["status"]
	if not status_value is String or str(status_value) not in VALID_REVIEW_STATUSES:
		return "invalid_review_status"
	var reason_value: Variant = review["decision_reason"]
	if not reason_value is String:
		return "invalid_review_decision_reason"
	var status := str(status_value)
	if status == "under_review":
		if not str(reason_value).is_empty() or review.has("resolved_day") or review.has("job_id"):
			return "invalid_pending_review_lifecycle"
	elif status in ["approved", "rejected"]:
		if str(reason_value).is_empty() or not _is_resolved_review_day(review, int(decision_day_value)):
			return "invalid_resolved_review_lifecycle"
		if review.has("job_id"):
			return "invalid_resolved_review_job_link"
	else:
		if str(reason_value).is_empty() or not _is_resolved_review_day(review, int(decision_day_value)):
			return "invalid_construction_review_lifecycle"
		var job_id_value: Variant = review.get("job_id", null)
		if not job_id_value is String or str(job_id_value).is_empty():
			return "invalid_construction_review_job_id"
	return ""


static func _validate_snapshot_job(
	job_key: Variant,
	job: Dictionary,
	rules: Dictionary
) -> String:
	if not job_key is String or str(job_key).is_empty():
		return "invalid_job_id"
	for field_name: String in [
		"id", "sequence", "operation", "review_id", "target_id", "blueprint",
		"worker_count", "workload", "remaining_work", "start_day", "elapsed_days",
		"projected_total_days", "projected_remaining_days", "projected_labor_cost",
		"labor_cost_paid", "status", "metadata",
	]:
		if not job.has(field_name):
			return "missing_job_field_%s" % field_name
	var job_id_value: Variant = job["id"]
	if not job_id_value is String or str(job_id_value) != str(job_key):
		return "invalid_job_id"
	var sequence_value: Variant = job["sequence"]
	if not _is_integer_value(sequence_value) or int(sequence_value) < 1:
		return "invalid_job_sequence"
	var generated_sequence := _generated_sequence(str(job_key), "job_")
	if generated_sequence > 0 and int(sequence_value) != generated_sequence:
		return "job_sequence_mismatch"
	var operation_value: Variant = job["operation"]
	if not operation_value is String or str(operation_value) not in VALID_OPERATIONS:
		return "invalid_job_operation"
	if not job["review_id"] is String or not job["target_id"] is String:
		return "invalid_job_reference_shape"
	var blueprint_value: Variant = job["blueprint"]
	if not blueprint_value is Dictionary:
		return "invalid_job_blueprint"
	var blueprint: Dictionary = blueprint_value
	var blueprint_error := _validate_snapshot_blueprint(blueprint, false)
	if not blueprint_error.is_empty():
		return "invalid_job_blueprint_%s" % blueprint_error
	var metadata_value: Variant = job["metadata"]
	if not metadata_value is Dictionary or not _is_json_safe(metadata_value):
		return "invalid_job_metadata"
	var worker_value: Variant = job["worker_count"]
	if not _is_integer_value(worker_value) or int(worker_value) < 1 or int(worker_value) > MAX_WORKERS:
		return "invalid_job_workers"
	var workload_value: Variant = job["workload"]
	var remaining_value: Variant = job["remaining_work"]
	if not _is_positive_number(workload_value):
		return "invalid_job_workload"
	if not _is_nonnegative_number(remaining_value) or float(remaining_value) > float(workload_value):
		return "invalid_job_remaining_work"
	var expected_workload := calculate_workload_with_rules(
		blueprint,
		str(operation_value),
		rules
	)
	if expected_workload <= 0.0 or float(workload_value) != expected_workload:
		return "job_workload_mismatch"
	for integer_field: String in [
		"start_day", "elapsed_days", "projected_remaining_days", "projected_labor_cost", "labor_cost_paid",
	]:
		if not _is_nonnegative_integer(job[integer_field]):
			return "invalid_job_%s" % integer_field
	if not _is_integer_value(job["projected_total_days"]) or int(job["projected_total_days"]) < 1:
		return "invalid_job_projected_total_days"
	var worker_count := int(worker_value)
	var remaining_work := float(remaining_value)
	if int(job["projected_remaining_days"]) != duration_days(remaining_work, worker_count):
		return "job_remaining_projection_mismatch"
	if not _projection_matches_possible_initial_assignment(
		float(workload_value),
		int(job["projected_total_days"]),
		int(job["projected_labor_cost"])
	):
		return "job_total_projection_mismatch"
	var elapsed_days := int(job["elapsed_days"])
	var labor_paid := int(job["labor_cost_paid"])
	if elapsed_days == 0:
		if labor_paid != 0 or not is_equal_approx(remaining_work, float(workload_value)):
			return "job_zero_elapsed_progress_mismatch"
	else:
		if labor_paid < elapsed_days * daily_labor_cost(1):
			return "job_labor_paid_too_low"
		if labor_paid > elapsed_days * daily_labor_cost(MAX_WORKERS) or labor_paid % 500 != 0:
			return "job_labor_paid_invalid"
		if remaining_work > 0.0:
			var completed_work := float(workload_value) - remaining_work
			if completed_work + 0.00001 < float(elapsed_days):
				return "job_progress_too_low"
			if completed_work > effective_workers(MAX_WORKERS) * float(elapsed_days) + 0.00001:
				return "job_progress_too_high"
	var status_value: Variant = job["status"]
	if not status_value is String or str(status_value) not in VALID_JOB_STATUSES:
		return "invalid_job_status"
	var status := str(status_value)
	if status == "active":
		if remaining_work <= 0.0 or int(job["projected_remaining_days"]) <= 0:
			return "invalid_active_job_progress"
		if job.has("completed_day") or job.has("cancelled_day"):
			return "invalid_active_job_lifecycle"
	elif status == "completed":
		if not is_zero_approx(remaining_work) or int(job["projected_remaining_days"]) != 0 or elapsed_days < 1:
			return "invalid_completed_job_progress"
		if not _is_job_terminal_day(job, "completed_day") or job.has("cancelled_day"):
			return "invalid_completed_job_lifecycle"
	else:
		if remaining_work <= 0.0 or int(job["projected_remaining_days"]) <= 0:
			return "invalid_cancelled_job_progress"
		if not _is_job_terminal_day(job, "cancelled_day") or job.has("completed_day"):
			return "invalid_cancelled_job_lifecycle"
	if job.has("last_assignment_day"):
		if (
			not _is_nonnegative_integer(job["last_assignment_day"])
			or int(job["last_assignment_day"]) < int(job["start_day"])
		):
			return "invalid_job_last_assignment_day"
	var metadata: Dictionary = metadata_value
	if str(metadata.get("entity_kind", "")) == TERRAIN_FLATTEN_ENTITY_KIND:
		var terrain_error := _validate_snapshot_terrain_flatten_job(job, blueprint, metadata)
		if not terrain_error.is_empty():
			return terrain_error
	return ""


static func _validate_snapshot_terrain_flatten_job(
	job: Dictionary,
	blueprint: Dictionary,
	metadata: Dictionary
) -> String:
	if str(job.get("operation", "")) != "build" or not str(job.get("review_id", "")).is_empty():
		return "invalid_terrain_flatten_operation"
	for required_field: String in [
		"entity_kind", "tile_index", "source_terrain_kind", "base_cost",
		"fixed_cost", "labor_cost", "total_cost", "billing_model",
	]:
		if not metadata.has(required_field):
			return "missing_terrain_flatten_metadata_%s" % required_field
	if metadata.size() != 8:
		return "invalid_terrain_flatten_metadata_shape"
	var tile_value: Variant = metadata["tile_index"]
	if not _is_integer_value(tile_value) or int(tile_value) < 0 or int(tile_value) >= TERRAIN_TILE_COUNT:
		return "invalid_terrain_flatten_tile"
	var source_value: Variant = metadata["source_terrain_kind"]
	if not source_value is String or not TERRAIN_FLATTEN_WORKLOADS.has(str(source_value)):
		return "invalid_terrain_flatten_source"
	for cost_field: String in ["base_cost", "fixed_cost", "labor_cost", "total_cost"]:
		if not _is_nonnegative_integer(metadata[cost_field]):
			return "invalid_terrain_flatten_%s" % cost_field
	var fixed_cost := int(metadata["fixed_cost"])
	var labor_cost := int(metadata["labor_cost"])
	if int(metadata["base_cost"]) != fixed_cost:
		return "terrain_flatten_base_cost_mismatch"
	if labor_cost != int(job.get("projected_labor_cost", -1)):
		return "terrain_flatten_labor_cost_mismatch"
	if int(metadata["total_cost"]) != fixed_cost + labor_cost:
		return "terrain_flatten_total_cost_mismatch"
	if str(metadata["billing_model"]) != TERRAIN_FLATTEN_BILLING_MODEL:
		return "invalid_terrain_flatten_billing_model"
	var initial_workers := int(blueprint.get("requested_workers", 0))
	var workload := float(job.get("workload", 0.0))
	if (
		int(job.get("projected_total_days", 0)) != duration_days(workload, initial_workers)
		or int(job.get("projected_labor_cost", -1)) != total_labor_cost(workload, initial_workers)
	):
		return "terrain_flatten_initial_projection_mismatch"
	var expected_blueprint := terrain_flatten_blueprint(
		int(tile_value),
		str(source_value),
		fixed_cost,
		initial_workers
	)
	if not _snapshot_values_equivalent(blueprint, expected_blueprint):
		return "terrain_flatten_blueprint_mismatch"
	if str(job.get("target_id", "")) != terrain_flatten_target_id(int(tile_value)):
		return "terrain_flatten_target_mismatch"
	var expected_metadata := terrain_flatten_metadata(
		int(tile_value),
		str(source_value),
		fixed_cost,
		labor_cost
	)
	if not _snapshot_values_equivalent(metadata, expected_metadata):
		return "terrain_flatten_metadata_mismatch"
	return ""


static func _validate_snapshot_blueprint(blueprint: Dictionary, require_nonempty_id: bool) -> String:
	for field_name: String in [
		"id", "version", "building_id", "material_id", "floors", "size_tier",
		"roof_color", "wall_color", "decoration_id", "decoration_count",
		"requested_workers", "base_cost",
	]:
		if not blueprint.has(field_name):
			return "missing_%s" % field_name
	var id_value: Variant = blueprint["id"]
	if not id_value is String or (require_nonempty_id and str(id_value).is_empty()):
		return "id"
	for string_field: String in ["building_id", "material_id", "size_tier", "roof_color", "wall_color", "decoration_id"]:
		var string_value: Variant = blueprint[string_field]
		if not string_value is String or (string_field in ["building_id", "material_id", "size_tier"] and str(string_value).is_empty()):
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
		or int(blueprint["requested_workers"]) > MAX_WORKERS
	):
		return "requested_workers"
	if not _is_integer_value(blueprint["base_cost"]) or int(blueprint["base_cost"]) < 0:
		return "base_cost"
	if blueprint.has("workload") and not _is_positive_number(blueprint["workload"]):
		return "workload"
	return ""


static func _validate_snapshot_review_job_relationships(reviews: Dictionary, jobs: Dictionary) -> String:
	for review_key: Variant in reviews.keys():
		var review: Dictionary = reviews[review_key]
		var status := str(review["status"])
		if status not in ["in_construction", "completed"]:
			continue
		var job_id := str(review["job_id"])
		if not jobs.has(job_id) or not jobs[job_id] is Dictionary:
			return "review_job_missing"
		var linked_job: Dictionary = jobs[job_id]
		if str(linked_job["review_id"]) != str(review_key):
			return "review_job_reference_mismatch"
		if str(linked_job["operation"]) != str(review["operation"]) or linked_job["blueprint"] != review["blueprint"]:
			return "review_job_payload_mismatch"
		if status == "completed" and str(linked_job["status"]) != "completed":
			return "review_job_status_mismatch"
		if status == "in_construction" and str(linked_job["status"]) not in ["active", "cancelled"]:
			return "review_job_status_mismatch"
	for job_key: Variant in jobs.keys():
		var job: Dictionary = jobs[job_key]
		var review_id := str(job["review_id"])
		if review_id.is_empty():
			continue
		if not reviews.has(review_id) or not reviews[review_id] is Dictionary:
			return "job_review_missing"
		var linked_review: Dictionary = reviews[review_id]
		if str(linked_review.get("job_id", "")) != str(job_key):
			return "job_review_reference_mismatch"
	return ""


static func _generated_sequence(record_id: String, prefix: String) -> int:
	if not record_id.begins_with(prefix):
		return 0
	var suffix := record_id.trim_prefix(prefix)
	if suffix.is_empty() or not suffix.is_valid_int():
		return 0
	return maxi(0, int(suffix))


static func _is_resolved_review_day(review: Dictionary, decision_day: int) -> bool:
	var resolved_value: Variant = review.get("resolved_day", null)
	return _is_nonnegative_integer(resolved_value) and int(resolved_value) >= decision_day


static func _is_job_terminal_day(job: Dictionary, field_name: String) -> bool:
	var terminal_value: Variant = job.get(field_name, null)
	return _is_nonnegative_integer(terminal_value) and int(terminal_value) >= int(job["start_day"])


static func _projection_matches_possible_initial_assignment(
	workload: float,
	projected_days: int,
	projected_labor_cost: int
) -> bool:
	for initial_workers: int in range(1, MAX_WORKERS + 1):
		var candidate_days := duration_days(workload, initial_workers)
		if (
			projected_days == candidate_days
			and projected_labor_cost == candidate_days * daily_labor_cost(initial_workers)
		):
			return true
	return false


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


static func _is_nonnegative_number(value: Variant) -> bool:
	return _is_number(value) and float(value) >= 0.0


static func _is_positive_number(value: Variant) -> bool:
	return _is_number(value) and float(value) > 0.0


static func _is_number(value: Variant) -> bool:
	return value is int or (value is float and is_finite(float(value)))


static func _is_json_safe(value: Variant) -> bool:
	if value is float:
		return is_finite(float(value))
	if value == null or value is bool or value is int or value is String:
		return true
	if value is Array:
		for item: Variant in value:
			if not _is_json_safe(item):
				return false
		return true
	if value is Dictionary:
		for key_variant: Variant in value.keys():
			if not key_variant is String or not _is_json_safe(value[key_variant]):
				return false
		return true
	return false


static func _snapshot_values_equivalent(left: Variant, right: Variant) -> bool:
	if _is_number(left) and _is_number(right):
		return is_equal_approx(float(left), float(right))
	if left is Dictionary and right is Dictionary:
		if (left as Dictionary).size() != (right as Dictionary).size():
			return false
		for key_variant: Variant in (left as Dictionary).keys():
			if (
				not (right as Dictionary).has(key_variant)
				or not _snapshot_values_equivalent(
					(left as Dictionary)[key_variant],
					(right as Dictionary)[key_variant]
				)
			):
				return false
		return true
	if left is Array and right is Array:
		if (left as Array).size() != (right as Array).size():
			return false
		for index: int in range((left as Array).size()):
			if not _snapshot_values_equivalent((left as Array)[index], (right as Array)[index]):
				return false
		return true
	return left == right
