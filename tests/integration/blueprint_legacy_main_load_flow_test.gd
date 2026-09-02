extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const VerticalSliceCoordinatorScript = preload("res://scripts/app/vertical_slice_coordinator.gd")
const SaveServiceScript = preload("res://scripts/core/save_service.gd")
const ContentRegistry = preload("res://data/catalogs/content_registry.gd")

const TEST_SAVE_PATH := "user://mayor_simulator/tests/blueprint_legacy_main_load_flow.json"
const APPROVAL_CONTEXT := {
	"citizen_support": 100.0,
	"available_budget": 1.0e30,
}

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_save()
	var fixture := _write_legacy_player_snapshot()
	if _failed:
		await _finish(null)
		return
	var restore_probe = VerticalSliceCoordinatorScript.new(20_260_905, 1)
	_check(restore_probe.load_game(TEST_SAVE_PATH), "historical schema-10 fixture restores through the public coordinator load API")
	_check(
		int(restore_probe.placement_quote("公園", 5).get("base_cost", -1)) == int(fixture.get("stored_base_cost", -2)),
		"public coordinator restore retains the historical player-approved stored base cost"
	)
	if _failed:
		await _finish(null)
		return

	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var packed := load("res://scenes/Main.tscn") as PackedScene
	_check(packed != null, "Main scene is available for the legacy blueprint load flow")
	if packed == null:
		await _finish(null)
		return
	var main = packed.instantiate()
	main.start_save_path = TEST_SAVE_PATH
	root.add_child(main)
	await _settle(3)
	_check(main.start_screen != null and main.start_screen.continue_game_button != null, "Main exposes the normal Continue entrypoint")
	if main.start_screen == null or main.start_screen.continue_game_button == null:
		await _finish(main)
		return
	main.start_screen.animation_duration = 0.04
	main.start_screen.set_continue_available(true)
	main.start_screen.continue_game_button.emit_signal("pressed")
	await _wait_for_loading(main)
	_check(main._game_started and not main.start_screen.visible, "Main Continue restores the legacy snapshot through the product load path")
	if main.tutorial_overlay != null and main.tutorial_overlay.is_open():
		main.tutorial_overlay.close_as_completed(false)
		await _settle(3)

	main.call("_select_building", "公園")
	main.call("_update_scoped_municipal_pages", main.vertical_slice.get_view_model(main.selected_cell_index))
	await process_frame
	var panel = main.vertical_slice_panel
	_check(panel != null, "Main binds the restored blueprint panel")
	if panel == null:
		await _finish(main)
		return
	var active_quote: Dictionary = main.vertical_slice.placement_quote("公園", panel.selected_worker_count())
	var active_state: Dictionary = panel.active_design_state()
	var quote_label := panel.find_child("BlueprintPlacementQuote", true, false) as Label
	var submit_button := panel.find_child("SubmitBlueprintButton", true, false) as Button
	_check(
		bool(active_state.get("matches_active_approved", false))
		and int(active_quote.get("base_cost", -1)) == int(fixture.get("stored_base_cost", -2)),
		"Main panel binding keeps matching legacy player design on the stored approved base cost"
	)
	_check(
		quote_label != null and quote_label.text.contains(_format_money(int(fixture.get("stored_base_cost", 0))))
		and submit_button != null and submit_button.text == "回到地圖放置",
		"visible Main quote and CTA use the stored approved design before placement"
	)

	# Drive a real picker callback into the Main-bound design_changed signal.
	var material := panel.find_child("BlueprintMaterial", true, false) as OptionButton
	_check(material != null and material.has_method("select_choice"), "material selector exposes the production progressive-picker handler")
	if material != null:
		material.call("select_choice", "brick")
		material.call("_on_item_selected", material.selected)
		await process_frame
	var dirty_quote: Dictionary = main.vertical_slice.draft_placement_quote("公園", panel.current_design_payload())
	active_state = panel.active_design_state()
	_check(
		bool(active_state.get("design_dirty", false))
		and submit_button != null and submit_button.text == "送審自訂版"
		and quote_label != null and quote_label.text.contains(_format_money(int(dirty_quote.get("base_cost", 0))))
		and int(dirty_quote.get("base_cost", -1)) != int(fixture.get("stored_base_cost", -2)),
		"dirty UI signal reaches Main and replaces the visible stored quote with the deterministic draft quote"
	)
	# Restore the active values through the same picker path; only then may the
	# primary action return to placement.
	if material != null:
		material.call("select_choice", "steel")
		material.call("_on_item_selected", material.selected)
		await process_frame
	active_quote = main.vertical_slice.placement_quote("公園", panel.selected_worker_count())
	active_state = panel.active_design_state()
	_check(
		bool(active_state.get("matches_active_approved", false))
		and submit_button != null and submit_button.text == "回到地圖放置"
		and quote_label != null and quote_label.text.contains(_format_money(int(fixture.get("stored_base_cost", 0)))),
		"returning to approved values restores placement and the stored legacy quote"
	)

	var anchor_tile := _find_main_placeable_anchor(main, "公園", panel.selected_worker_count())
	_check(anchor_tile >= 0, "Main can choose a legal anchor for the restored three-cell approved blueprint")
	if anchor_tile >= 0 and submit_button != null:
		var funds_before := int(main.vertical_slice.treasury_balance())
		var ledger_before := _construction_ledger_count(main.vertical_slice)
		submit_button.pressed.emit()
		await process_frame
		_check(bool(main.placement_mode_active), "approved primary CTA enters Main placement mode")
		main.call("_on_grid_pressed", anchor_tile)
		await process_frame
		var confirmation := main.construction_confirmation as Control
		var confirmation_cost := confirmation.find_child("ConstructionCostBreakdown", true, false) as Label if confirmation != null else null
		var confirm_button := confirmation.find_child("ConfirmConstructionButton", true, false) as Button if confirmation != null else null
		_check(
			confirmation != null and confirmation.is_open() and confirmation_cost != null
			and confirmation_cost.text.contains(_format_money(int(active_quote.get("base_cost", 0)))),
			"Main confirmation receives the same stored approved quote that the panel displayed"
		)
		if confirm_button != null:
			confirm_button.pressed.emit()
			await process_frame
		var job: Dictionary = main.vertical_slice.active_construction_for_tile(anchor_tile)
		_check(
			str(job.get("blueprint", {}).get("id", "")) == str(active_quote.get("blueprint", {}).get("id", ""))
			and int(job.get("blueprint", {}).get("base_cost", -1)) == int(active_quote.get("base_cost", -2))
			and int(job.get("projected_labor_cost", -1)) == int(active_quote.get("total_labor_cost", -2))
			and int(job.get("projected_total_days", -1)) == int(active_quote.get("duration_days", -2))
			and Array(job.get("metadata", {}).get("occupied_tile_ids", [])).size() == 3,
			"confirmed Main placement starts the restored blueprint with matching base, labor, duration, and three cells"
		)
		_check(
			int(main.vertical_slice.treasury_balance()) == funds_before - int(active_quote.get("total_cost", 0))
			and _construction_ledger_count(main.vertical_slice) == ledger_before + 1,
			"Main confirmation writes exactly one construction ledger debit for the visible quote"
		)

	await _finish(main)


func _write_legacy_player_snapshot() -> Dictionary:
	var coordinator = VerticalSliceCoordinatorScript.new(20_260_904, 1_000_000)
	var payload := {
		"building_name": "公園",
		"material_id": "steel",
		"size_tier": "large",
		"floors": 4,
		"workers": 5,
		"decor_id": "flags",
	}
	var submitted: Dictionary = coordinator.submit_blueprint(payload)
	_check(bool(submitted.get("ok", false)), "legacy fixture enters review through the public submission authority")
	if not bool(submitted.get("ok", false)):
		return {}
	var review: Dictionary = Dictionary(submitted.get("review", {}))
	coordinator.advance_days(int(review.get("review_days", 0)), APPROVAL_CONTEXT, false)
	var active: Dictionary = coordinator.active_blueprint_status("公園")
	_check(str(active.get("source", "")) == "player", "legacy fixture reaches player-approved status through public approval advancement")
	_check(coordinator.save_game(TEST_SAVE_PATH) == OK, "legacy fixture persists via the normal coordinator save authority")
	if _failed:
		return {}

	var reader := SaveServiceScript.new()
	var envelope = reader.load_primary_envelope(TEST_SAVE_PATH)
	_check(envelope != null, "normal persisted fixture is decodable before historical snapshot conversion")
	if envelope == null:
		return {}
	var park_definition = ContentRegistry.buildings_by_id().get("park", null)
	_check(park_definition != null, "legacy fixture resolves the canonical park definition")
	if park_definition == null:
		return {}
	var stored_base_cost := int(park_definition.base_cost)
	var vertical: Dictionary = envelope.state.get("metadata", {}).get("vertical_slice", {})
	var active_ids: Dictionary = vertical.get("active_blueprint_by_building", {})
	var library: Dictionary = vertical.get("blueprint_library", {})
	var library_id := str(active_ids.get("park", ""))
	var entry: Dictionary = Dictionary(library.get(library_id, {})).duplicate(true)
	var blueprint: Dictionary = Dictionary(entry.get("blueprint", {})).duplicate(true)
	_check(not library_id.is_empty() and str(entry.get("source", "")) == "player", "persisted fixture identifies its active approved player entry")
	if library_id.is_empty() or entry.is_empty():
		return {}
	blueprint["base_cost"] = stored_base_cost
	blueprint["roof_color"] = "legacy_red"
	blueprint["wall_color"] = "legacy_gray"
	entry["blueprint"] = blueprint
	library[library_id] = entry
	vertical["blueprint_library"] = library
	# Current schema validation requires the immutable approved-library record
	# and its historical review to agree. A pre-W6 save therefore carries the
	# same formerly-stored cost in both persisted records.
	var construction: Dictionary = vertical.get("construction", {}).duplicate(true)
	var reviews: Dictionary = construction.get("reviews", {}).duplicate(true)
	var review_id := str(entry.get("review_id", ""))
	var approved_review: Dictionary = Dictionary(reviews.get(review_id, {})).duplicate(true)
	_check(not review_id.is_empty() and not approved_review.is_empty(), "historical fixture keeps the approved review required by schema-10 validation")
	if _failed:
		return {}
	approved_review["blueprint"] = blueprint.duplicate(true)
	reviews[review_id] = approved_review
	construction["reviews"] = reviews
	vertical["construction"] = construction
	var metadata: Dictionary = envelope.state.get("metadata", {}).duplicate(true)
	metadata["vertical_slice"] = vertical
	envelope.state["metadata"] = metadata
	# Write both generations through SaveService so Continue restores a genuine
	# schema-10 snapshot instead of a runtime coordinator dictionary mutation.
	var writer := SaveServiceScript.new()
	_check(writer.save_atomic(TEST_SAVE_PATH, envelope) == OK, "historical snapshot primary is written through SaveService")
	_check(writer.save_atomic(TEST_SAVE_PATH, envelope) == OK, "historical snapshot backup is written through SaveService")
	return {"stored_base_cost": stored_base_cost}


func _find_main_placeable_anchor(main, building_name: String, workers: int) -> int:
	for tile_index in range(main.CELL_COUNT):
		if not bool(main.call("_is_tile_inside_hud_safe_area", tile_index)):
			continue
		var quote: Dictionary = main.vertical_slice.placement_footprint_quote(building_name, tile_index, workers)
		if bool(quote.get("ok", false)):
			return tile_index
	return -1


func _construction_ledger_count(coordinator) -> int:
	var count := 0
	for entry_variant in coordinator.session.state.ledger.get_entries():
		if str(entry_variant.get("reason_tag", "")) == "construction.total_cost":
			count += 1
	return count


func _wait_for_loading(main) -> void:
	for _frame in range(120):
		await process_frame
		if not main.start_screen.is_loading():
			return
	_check(false, "Main Continue loading did not finish within 120 frames")


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame


func _finish(main) -> void:
	_cleanup_save()
	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Blueprint legacy Main load flow test passed.")
	await TestCleanup.finish(self, [main] if main != null else [], exit_code)


func _cleanup_save() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	for candidate in [absolute_path, absolute_path + ".tmp", absolute_path + ".bak", absolute_path + ".recovery.tmp"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _format_money(amount: int) -> String:
	var digits := str(absi(amount))
	var insert_at := digits.length() - 3
	while insert_at > 0:
		digits = digits.insert(insert_at, ",")
		insert_at -= 3
	return digits


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Blueprint legacy Main load flow test failed: %s" % message)
