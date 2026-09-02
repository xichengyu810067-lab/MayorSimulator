extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const TEST_SAVE_PATH := "user://mayor_simulator/tests/progressive_disclosure.json"

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1920, 1080)
	root.size = Vector2i(1920, 1080)
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(3)
	main.start_save_path = TEST_SAVE_PATH
	main.start_screen.animation_duration = 0.01

	_check(main.start_screen.language_selector.choice_count() == 5, "start screen keeps five languages")
	_check(main.start_screen.language_selector.visible_popup_item_count() == 5, "start screen exposes all five languages on one popup page")
	_check(main.start_screen.language_selector.shows_all_choices(), "start screen language selector has no More paging")
	for locale in ["zh_TW", "zh_CN", "en", "ja", "ko"]:
		_check(main.start_screen.language_selector.select_choice(locale), "language '%s' remains reachable" % locale)
	main.start_screen.language_selector.select_choice("zh_TW")

	main.start_screen.new_game_button.emit_signal("pressed")
	for _frame in range(120):
		await process_frame
		if not main.start_screen.is_loading():
			break
	_check(main._game_started, "progressive-disclosure test enters the city")

	main.municipal_overlay.open_hub()
	await _settle()
	var hub_root := main.municipal_overlay.find_child("MunicipalHubRoot", true, false) as Control
	var wide_debug: Dictionary = main.municipal_overlay.debug_hub_layout_state()
	_check(hub_root != null, "municipal direct hub root exists")
	_check(int(wide_debug.get("direct_card_count", 0)) == 7, "municipal root exposes seven direct destinations")
	_check(int(wide_debug.get("unique_destination_count", 0)) == 7, "municipal root exposes no duplicate destination")
	_check(int(wide_debug.get("filler_count", -1)) == 0, "municipal root exposes no filler card")
	_check(int(wide_debug.get("intermediate_page_count", -1)) == 0, "municipal root exposes no category intermediate page")
	_check(wide_debug.get("destinations", []) == ["buildings", "governance", "judicial", "oversight", "finance", "public_affairs", "city_data"], "municipal root exposes the required seven destinations in visual order")
	_check(str(wide_debug.get("featured_destination", "")) == "buildings", "buildings owns the featured card")
	_check(str(wide_debug.get("layout_mode", "")) == "wide", "1920px hub uses featured-left layout")
	_check(int(wide_debug.get("secondary_columns", 0)) == 2 and int(wide_debug.get("secondary_rows", 0)) == 3, "wide hub secondary destinations use 2x3")
	_check(bool(wide_debug.get("secondary_equal_heights", false)), "wide hub secondary destinations are equal height")
	_check(bool(wide_debug.get("featured_spans_full_height", false)), "wide featured card spans all three rows")
	_check(float(wide_debug.get("featured_width_ratio", 0.0)) >= 0.30 and float(wide_debug.get("featured_width_ratio", 0.0)) <= 0.38, "wide featured card occupies approximately one third of the hub")
	_check(float(wide_debug.get("minimum_target_extent", 0.0)) >= 44.0, "wide hub cards retain 44px targets")
	var contextual_parents: Dictionary = wide_debug.get("contextual_parents", {})
	_check(contextual_parents.get("blueprint", "") == "buildings" and contextual_parents.get("transport_planning", "") == "buildings" and contextual_parents.get("report", "") == "city_data", "contextual municipal children expose their required back destinations")
	var reached_destinations := {}
	for page_id_variant in wide_debug.get("destinations", []):
		var page_id := str(page_id_variant)
		var destination := main.municipal_overlay.find_child("%sButton" % page_id.capitalize(), true, false) as Button
		_check(destination != null, "direct municipal destination '%s' exists" % page_id)
		if destination != null:
			destination.emit_signal("pressed")
			await _settle()
			reached_destinations[main.municipal_overlay.current_page()] = true
		main.municipal_overlay.open_hub()
		await _settle()
	_check(reached_destinations.size() == 7, "all seven direct municipal destinations remain reachable")
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	await _settle(4)
	var narrow_debug: Dictionary = main.municipal_overlay.debug_hub_layout_state()
	_check(str(narrow_debug.get("layout_mode", "")) == "narrow", "1280px hub places the featured card above the secondary grid")
	_check(bool(narrow_debug.get("featured_precedes_secondary", false)), "narrow featured card is above all six secondary cards")
	_check(int(narrow_debug.get("secondary_columns", 0)) == 2 and int(narrow_debug.get("secondary_rows", 0)) == 3, "narrow secondary destinations remain 2x3")
	_check(bool(narrow_debug.get("secondary_equal_heights", false)), "narrow secondary destinations remain equal height")
	var narrow_host_rect: Rect2 = narrow_debug.get("host_rect", Rect2())
	var narrow_featured_rect: Rect2 = narrow_debug.get("featured_rect", Rect2())
	_check(absf(narrow_featured_rect.size.x - narrow_host_rect.size.x) <= 1.0, "narrow featured card spans the top row width")
	_check(float(narrow_debug.get("minimum_target_extent", 0.0)) >= 44.0, "narrow hub cards retain 44px targets")
	root.content_scale_size = Vector2i(1920, 1080)
	root.size = Vector2i(1920, 1080)
	await _settle(4)

	main.municipal_overlay.open_page("buildings")
	await _settle()
	_validate_balanced_building_distribution(main)
	_check(main.building_family_tabs.get_tab_count() == 3, "building selector has three broad families")
	_check(main.building_group_buttons.size() == 6, "building selector preserves all six subgroups")
	_check(main.building_buttons.size() > 3, "building selector preserves the full catalog")
	for pager_variant in main.building_card_pagers.values():
		_validate_building_pager(pager_variant, "building catalog")
	var residential_card := main.find_child("BuildingCard_住宅", true, false) as Button
	_check(residential_card != null, "residential building card is reachable")
	if residential_card != null:
		residential_card.emit_signal("pressed")
		await _settle()
		_check(main.municipal_overlay.current_page() == "blueprint", "building-card selection does not enter blueprint design directly")
		_check(main.selected_building == "住宅", "direct blueprint entry lost the selected building authority")
		_check(main.find_child("OpenTransportPlanningButton", true, false) == null, "non-transport building does not expose transport shortcut")
	main.municipal_overlay.open_page("buildings")
	await _settle()

	main.municipal_overlay.open_page("governance")
	await _settle()
	_check(main.governance_status_tabs.get_tab_count() == 3, "governance has three status choices")
	_check(main.governance_policy_cards.size() + main.governance_bill_cards.size() == 12, "governance preserves twelve cards")
	for pager_variant in main.governance_status_pagers.values():
		_validate_pager(pager_variant, "governance catalog")

	main.municipal_overlay.open_page("finance")
	await _settle()
	_check(main.find_child("FiscalCategoryTabs", true, false) == null, "finance removes the old nested fiscal TabContainer")
	var fiscal_ui: Dictionary = Dictionary(main.call("debug_fiscal_draft_state")).get("ui", {})
	var fiscal_categories: Array = fiscal_ui.get("category_ids", [])
	_check(fiscal_categories.size() == 6, "finance has six focused category cards")
	_check(Array(fiscal_ui.get("plan_ids", [])).size() == 3, "each finance category offers three plan cards")
	var fiscal_control_count := 0
	for category_id_variant in fiscal_categories:
		var category_id := str(category_id_variant)
		var category_card := main.find_child("FiscalCategoryCard_%s" % category_id, true, false) as Button
		_check(category_card != null and category_card.custom_minimum_size.y >= 44.0, "fiscal category '%s' remains reachable" % category_id)
		if category_card == null:
			continue
		category_card.pressed.emit()
		await _settle()
		var custom_plan := main.find_child("FiscalPlanCard_custom", true, false) as Button
		_check(custom_plan != null and custom_plan.custom_minimum_size.y >= 44.0, "fiscal category '%s' exposes a reachable custom plan" % category_id)
		if custom_plan == null:
			continue
		custom_plan.pressed.emit()
		await _settle()
		var visible_rows := 0
		for row_variant in main.find_children("FiscalRow_*", "VBoxContainer", true, false):
			if (row_variant as Control).is_visible_in_tree():
				visible_rows += 1
		_check(visible_rows == 2, "fiscal category '%s' custom plan exposes exactly two controls" % category_id)
		fiscal_control_count += visible_rows
		var back_button := main.find_child("FiscalBackToCategories", true, false) as Button
		_check(back_button != null, "fiscal category '%s' exposes a back-to-categories action" % category_id)
		if back_button != null:
			back_button.pressed.emit()
			await _settle()
	_check(fiscal_control_count == 12, "all twelve fiscal controls remain reachable through category cards")

	main.municipal_overlay.open_page("blueprint")
	await _settle()
	var parameter_page := main.find_child("BlueprintDesignWorkspace", true, false) as HBoxContainer
	_check(parameter_page != null, "blueprint design parameters are presented on one page")
	if parameter_page != null:
		_check(parameter_page.get_meta("single_page_design", false) == true, "blueprint design single-page meta flag is set")
		_check(parameter_page.get_child_count() == 2, "blueprint does not combine its five controls into two task-oriented groups")
		_check(int(parameter_page.get_meta("design_control_count", 0)) == 5, "blueprint workspace lost one of the five design controls")
		_check(main.find_child("BlueprintGroup_Size", true, false) != null, "material, size, and floors are not grouped as building specifications")
		_check(main.find_child("BlueprintGroup_Workers", true, false) != null, "workers and decoration are not grouped as construction setup")
	var material_picker = main.find_child("BlueprintMaterial", true, false)
	_check(material_picker != null, "blueprint material picker is reachable")
	if material_picker != null:
		_check(material_picker.choice_count() == 4, "blueprint material picker preserves four materials")
		_check(material_picker.visible_popup_item_count() <= 3, "blueprint material picker reveals no more than three choices")
		for material_id in ["wood", "brick", "steel", "eco_composite"]:
			_check(material_picker.select_choice(material_id), "material '%s' remains reachable" % material_id)
	var design_controls := ["BlueprintMaterial", "BlueprintSize", "BlueprintFloors", "BlueprintWorkers", "BlueprintDecoration"]
	for control_name in design_controls:
		var control = main.find_child(control_name, true, false)
		_check(control != null, "design control '%s' is reachable from blueprint page" % control_name)

	main.municipal_overlay.open_page("public_affairs")
	await _settle()
	_check(main.public_affairs_panel._requests_pager.choice_count() == main.public_affairs_panel._request_buttons.size(), "public-affairs pager preserves every request")
	_validate_pager(main.public_affairs_panel._requests_pager, "public-affairs requests")

	main.city_grid[18] = "住宅"
	main.building_customizations[18] = {"variant": 0, "roof": 0, "wall": 0}
	main.vertical_slice.register_existing_building(18, "住宅", main.building_customizations[18])
	main.call("_select_built_cell", 18)
	await _settle()
	_check(main.building_context_panel._root_actions.visible and main.building_context_panel._root_actions.get_child_count() == 3, "building context root exposes three actions")
	main.building_context_panel._appearance_button.emit_signal("pressed")
	await _settle()
	_check(main.building_context_panel._customize_actions.visible and main.building_context_panel._customize_actions.get_child_count() == 3, "appearance submenu exposes three actions")

	_validate_all_marked_groups(main)
	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Progressive disclosure test passed. Destinations=7 Buildings=%d Governance=12 FiscalLeaves=6" % main.building_buttons.size())
	await TestCleanup.finish(self, [main], exit_code)


func _validate_pager(pager, context: String) -> void:
	_check(pager.visible_choice_count() <= 3, "%s initial page exceeds three choices" % context)
	var preserved_count: int = int(pager.choice_count())
	for page_index in range(pager.page_count()):
		pager.set_page(page_index)
		_check(pager.visible_choice_count() <= 3, "%s page %d exceeds three choices" % [context, page_index])
	_check(pager.choice_count() == preserved_count, "%s pagination lost choices" % context)
	pager.set_page(0)


func _validate_building_pager(pager, context: String) -> void:
	_check(pager.page_size == 6, "%s does not favor six visible cards" % context)
	_check(bool(pager.get_meta("balanced_building_pager", false)), "%s does not opt into balanced rows" % context)
	_check(pager.has_method("debug_layout_state"), "%s does not expose inspectable balanced geometry" % context)
	if not pager.has_method("debug_layout_state"):
		return
	var preserved_count: int = int(pager.choice_count())
	for page_index in range(pager.page_count()):
		pager.set_page(page_index)
		var visible_count: int = int(pager.visible_choice_count())
		var layout: Dictionary = pager.debug_layout_state()
		_check(visible_count <= 6, "%s page %d exceeds six choices" % [context, page_index])
		_check(Array(layout.get("row_counts", [])) == _expected_building_rows(visible_count), "%s page %d does not balance %d visible cards" % [context, page_index, visible_count])
	_check(pager.choice_count() == preserved_count, "%s pagination lost choices" % context)
	pager.set_page(0)


func _validate_balanced_building_distribution(main) -> void:
	var pager = main.building_card_pagers.values()[0] if not main.building_card_pagers.is_empty() else null
	_check(pager != null, "building catalog provides a pager for balance validation")
	if pager == null:
		return
	_check(pager.has_method("balanced_rows_for_count"), "balanced building pager exposes deterministic count distribution")
	if not pager.has_method("balanced_rows_for_count"):
		return
	for count in range(1, 7):
		_check(Array(pager.balanced_rows_for_count(count)) == _expected_building_rows(count), "%d-card page uses the expected balanced rows" % count)


func _expected_building_rows(visible_count: int) -> Array:
	match visible_count:
		0: return []
		1: return [1]
		2: return [2]
		3: return [3]
		4: return [2, 2]
		5: return [3, 2]
		_: return [3, 3]


func _validate_all_marked_groups(main: Node) -> void:
	var marked_groups := 0
	for node_variant in main.find_children("*", "Control", true, false):
		var node := node_variant as Control
		if not bool(node.get_meta("progressive_choice_group", false)):
			continue
		marked_groups += 1
		if node is TabContainer:
			_check((node as TabContainer).get_tab_count() <= 3, "marked tab group '%s' exceeds three choices" % node.name)
		elif node.has_method("visible_choice_count"):
			var limit := 6 if bool(node.get_meta("balanced_building_pager", false)) else 3
			_check(node.visible_choice_count() <= limit, "marked pager '%s' exceeds %d choices" % [node.name, limit])
		else:
			var visible_choices := 0
			for child_variant in node.get_children():
				if child_variant is Control and bool(child_variant.get_meta("progressive_choice", false)) and (child_variant as Control).visible:
					visible_choices += 1
			_check(visible_choices <= 3, "marked group '%s' exposes %d choices" % [node.name, visible_choices])
	_check(marked_groups >= 20, "progressive-disclosure coverage unexpectedly dropped")


func _settle(frames: int = 2) -> void:
	for _frame in range(frames):
		await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Progressive disclosure check failed: %s" % message)
