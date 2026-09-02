extends SceneTree

const VerticalSliceCoordinatorScript = preload("res://scripts/app/vertical_slice_coordinator.gd")

const APPROVAL_CONTEXT := {
	"citizen_support": 100.0,
	"available_budget": 1.0e30,
}

var _failed := false


func _initialize() -> void:
	var coordinator = VerticalSliceCoordinatorScript.new(20_260_902, 1_000_000)
	var baseline := {
		"building_name": "公園",
		"material_id": "brick",
		"size_tier": "medium",
		"floors": 2,
		"workers": 5,
		"decor_id": "flowers",
	}
	var base_quote: Dictionary = coordinator.draft_placement_quote("公園", baseline)
	_check(bool(base_quote.get("ok", false)), "a current UI draft receives an estimate without an approved blueprint")
	_check(int(base_quote.get("footprint_count", 0)) == 2, "medium draft footprint is exactly two square cells")

	var material_quote := coordinator.draft_placement_quote("公園", _with(baseline, "material_id", "steel"))
	_check(int(material_quote.get("base_cost", 0)) != int(base_quote.get("base_cost", 0)), "material selection changes the direct quote")
	var small_quote := coordinator.draft_placement_quote("公園", _with(baseline, "size_tier", "small"))
	var large_quote := coordinator.draft_placement_quote("公園", _with(baseline, "size_tier", "large"))
	_check(int(small_quote.get("footprint_count", 0)) == 1 and int(large_quote.get("footprint_count", 0)) == 3, "small, medium, and large drafts expose 1/2/3-cell footprints")
	_check(int(small_quote.get("base_cost", 0)) != int(large_quote.get("base_cost", 0)), "size selection changes the direct quote")
	var floors_quote := coordinator.draft_placement_quote("公園", _with(baseline, "floors", 8))
	_check(int(floors_quote.get("base_cost", 0)) != int(base_quote.get("base_cost", 0)), "floor selection changes the direct quote")
	var workers_quote := coordinator.draft_placement_quote("公園", _with(baseline, "workers", 12))
	_check(
		int(workers_quote.get("total_labor_cost", 0)) != int(base_quote.get("total_labor_cost", 0))
		or int(workers_quote.get("duration_days", 0)) != int(base_quote.get("duration_days", 0)),
		"worker selection changes labor or schedule directly"
	)
	var decor_quote := coordinator.draft_placement_quote("公園", _with(baseline, "decor_id", "flags"))
	_check(int(decor_quote.get("base_cost", 0)) != int(base_quote.get("base_cost", 0)), "decoration selection changes the direct quote")

	var submitted_medium: Dictionary = coordinator.submit_blueprint(baseline)
	_check(bool(submitted_medium.get("ok", false)), "the quoted medium draft submits for review")
	_approve(coordinator, submitted_medium)
	var approved_medium: Dictionary = coordinator.active_blueprint_status("公園")
	_check(
		str(approved_medium.get("blueprint", {}).get("size_tier", "")) == "medium",
		"the first approved blueprint remains the medium design"
	)

	var large_steel_payload := _with(_with(baseline, "size_tier", "large"), "material_id", "steel")
	var final_draft_quote: Dictionary = coordinator.draft_placement_quote("公園", large_steel_payload)
	var submitted_large: Dictionary = coordinator.submit_blueprint(large_steel_payload)
	_check(bool(submitted_large.get("ok", false)), "a changed large steel draft submits as a new review")
	var submitted_blueprint: Dictionary = Dictionary(submitted_large.get("review", {}).get("blueprint", {})).duplicate(true)
	var quoted_blueprint: Dictionary = Dictionary(final_draft_quote.get("blueprint", {})).duplicate(true)
	submitted_blueprint.erase("id")
	_check(submitted_blueprint == quoted_blueprint, "submitted blueprint is exactly the same normalized draft used by the quote")
	_check(int(submitted_blueprint.get("base_cost", 0)) == int(final_draft_quote.get("base_cost", -1)), "submitted construction cost cannot drift from the quoted cost")
	_approve(coordinator, submitted_large)
	var approved_large: Dictionary = coordinator.active_blueprint_status("公園")
	var active_blueprint: Dictionary = Dictionary(approved_large.get("blueprint", {}))
	_check(str(active_blueprint.get("id", "")) == str(submitted_large.get("review", {}).get("blueprint", {}).get("id", "")), "approved custom blueprint becomes the only placement authority")

	var workers := int(large_steel_payload.get("workers", 5))
	var final_placement_quote: Dictionary = coordinator.placement_quote("公園", workers)
	_check(
		int(final_placement_quote.get("base_cost", -1)) == int(final_draft_quote.get("base_cost", -2))
		and int(final_placement_quote.get("total_labor_cost", -1)) == int(final_draft_quote.get("total_labor_cost", -2))
		and int(final_placement_quote.get("total_cost", -1)) == int(final_draft_quote.get("total_cost", -2))
		and int(final_placement_quote.get("duration_days", -1)) == int(final_draft_quote.get("duration_days", -2)),
		"only an approved matching design may expose the actual placement quote"
	)
	var anchor_tile := _find_placeable_anchor(coordinator, "公園", workers)
	_check(anchor_tile >= 0, "approved large blueprint finds a legal three-cell placement anchor")
	var funds_before := coordinator.treasury_balance()
	var started: Dictionary = coordinator.start_approved_building("公園", anchor_tile, workers)
	_check(bool(started.get("ok", false)), "approved matching blueprint starts construction")
	var job: Dictionary = Dictionary(started.get("job", {}))
	var job_blueprint: Dictionary = Dictionary(job.get("blueprint", {}))
	_check(str(job_blueprint.get("id", "")) == str(active_blueprint.get("id", "")), "started job uses the approved blueprint identity")
	_check(
		str(job_blueprint.get("size_tier", "")) == "large"
		and int(job_blueprint.get("base_cost", -1)) == int(final_placement_quote.get("base_cost", -2))
		and int(job.get("projected_labor_cost", -1)) == int(final_placement_quote.get("total_labor_cost", -2))
		and int(job.get("projected_total_days", -1)) == int(final_placement_quote.get("duration_days", -2)),
		"started job cost and duration exactly match the final placement quote"
	)
	_check(int(started.get("total_cost", -1)) == int(final_placement_quote.get("total_cost", -2)), "start result total equals final quote total")
	_check(Array(started.get("occupied_tile_ids", [])).size() == 3, "large start reserves exactly three occupied cells")
	_check(coordinator.treasury_balance() == funds_before - int(final_placement_quote.get("total_cost", 0)), "construction deducts the final quote exactly once")
	var after_first_charge := coordinator.treasury_balance()
	var duplicate_start: Dictionary = coordinator.start_approved_building("公園", anchor_tile, workers)
	_check(not bool(duplicate_start.get("ok", false)) and coordinator.treasury_balance() == after_first_charge, "a rejected duplicate placement cannot charge construction twice")
	if _failed:
		quit(1)
		return
	print("Blueprint draft quote flow test passed.")
	quit(0)


func _with(source: Dictionary, key: String, value: Variant) -> Dictionary:
	var result := source.duplicate(true)
	result[key] = value
	return result


func _approve(coordinator, submitted: Dictionary) -> void:
	var review: Dictionary = Dictionary(submitted.get("review", {}))
	coordinator.advance_days(int(review.get("review_days", 0)), APPROVAL_CONTEXT, false)
	_check(str(coordinator.blueprint_review_status("公園").get("status", "")) == "approved", "review approval reaches the active blueprint library")


func _find_placeable_anchor(coordinator, building_name: String, workers: int) -> int:
	for tile_index in range(100):
		var quote: Dictionary = coordinator.placement_footprint_quote(building_name, tile_index, workers)
		if bool(quote.get("ok", false)):
			return tile_index
	return -1


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
