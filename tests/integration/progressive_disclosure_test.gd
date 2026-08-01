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
	var hub_choices := hub_root.find_child("MenuChoices", true, false) as GridContainer
	_check(hub_choices.get_child_count() == 3, "municipal root exposes three categories")
	var reached_destinations := {}
	for group_id in ["development", "governance", "community"]:
		var category_button := main.municipal_overlay.find_child("MunicipalCategory_%s" % group_id, true, false) as Button
		category_button.emit_signal("pressed")
		await _settle()
		var group_page := main.municipal_overlay.find_child("MunicipalHubGroup_%s" % group_id, true, false) as Control
		var group_choices := group_page.find_child("MenuChoices", true, false) as GridContainer
		_check(group_choices.get_child_count() == 3, "municipal category '%s' exposes three destinations" % group_id)
		for destination_variant in group_choices.get_children():
			var destination := destination_variant as Button
			destination.emit_signal("pressed")
			await _settle()
			reached_destinations[main.municipal_overlay.current_page()] = true
			main.municipal_overlay.call("_open_hub_group", group_id)
			await _settle()
		main.municipal_overlay.open_hub()
		await _settle()
	_check(reached_destinations.size() == 9, "all nine municipal destinations remain reachable")

	main.municipal_overlay.open_page("buildings")
	await _settle()
	_check(main.building_family_tabs.get_tab_count() == 3, "building selector has three broad families")
	_check(main.building_group_buttons.size() == 6, "building selector preserves all six subgroups")
	_check(main.building_buttons.size() > 3, "building selector preserves the full catalog")
	for pager_variant in main.building_card_pagers.values():
		_validate_pager(pager_variant, "building catalog")

	main.municipal_overlay.open_page("governance")
	await _settle()
	_check(main.governance_status_tabs.get_tab_count() == 3, "governance has three status choices")
	_check(main.governance_policy_cards.size() + main.governance_bill_cards.size() == 12, "governance preserves twelve cards")
	for pager_variant in main.governance_status_pagers.values():
		_validate_pager(pager_variant, "governance catalog")

	main.municipal_overlay.open_page("finance")
	await _settle()
	var fiscal_tabs := main.find_child("FiscalCategoryTabs", true, false) as TabContainer
	_check(fiscal_tabs.get_tab_count() == 3, "finance has three broad categories")
	var fiscal_leaf_count := 0
	for category_variant in fiscal_tabs.get_children():
		var subcategories := category_variant as TabContainer
		_check(subcategories.get_tab_count() == 2, "finance category exposes two subcategories")
		for subcategory_variant in subcategories.get_children():
			var rows := (subcategory_variant as Control).find_children("FiscalRow_*", "VBoxContainer", true, false)
			_check(rows.size() >= 2 and rows.size() <= 3, "finance leaf exposes two or three controls")
			fiscal_leaf_count += 1
	_check(fiscal_leaf_count == 6, "all six original finance groups remain reachable")

	main.municipal_overlay.open_page("blueprint")
	await _settle()
	var parameter_tabs := main.find_child("BlueprintParameterGroups", true, false) as TabContainer
	_check(parameter_tabs.get_tab_count() == 2, "blueprint parameters are split into two categories")
	_check(parameter_tabs.get_child(0).get_child_count() == 3, "blueprint structure category exposes three parameters")
	_check(parameter_tabs.get_child(1).get_child_count() == 2, "blueprint finishing category exposes two parameters")
	var material_picker = main.find_child("BlueprintMaterial", true, false)
	_check(material_picker.choice_count() == 4, "blueprint material picker preserves four materials")
	_check(material_picker.visible_popup_item_count() <= 3, "blueprint material picker reveals no more than three choices")
	for material_id in ["wood", "brick", "steel", "eco_composite"]:
		_check(material_picker.select_choice(material_id), "material '%s' remains reachable" % material_id)

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
		print("Progressive disclosure test passed. Destinations=9 Buildings=%d Governance=12 FiscalLeaves=6" % main.building_buttons.size())
	await TestCleanup.finish(self, [main], exit_code)


func _validate_pager(pager, context: String) -> void:
	_check(pager.visible_choice_count() <= 3, "%s initial page exceeds three choices" % context)
	var preserved_count: int = int(pager.choice_count())
	for page_index in range(pager.page_count()):
		pager.set_page(page_index)
		_check(pager.visible_choice_count() <= 3, "%s page %d exceeds three choices" % [context, page_index])
	_check(pager.choice_count() == preserved_count, "%s pagination lost choices" % context)
	pager.set_page(0)


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
			_check(node.visible_choice_count() <= 3, "marked pager '%s' exceeds three choices" % node.name)
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
