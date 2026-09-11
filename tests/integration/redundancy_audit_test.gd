extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const COUNCIL_PATH := "res://data/databases/governance/lower-council/councilors.json"
const COMMITTEE_PATH := "res://data/databases/governance/justice-oversight/committee_members.json"

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1920, 1080)
	root.size = Vector2i(1920, 1080)
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await process_frame
	main._open_municipal_center()
	await process_frame

	_audit_feature_ownership(main)
	_audit_catalogs(main)
	_audit_people(main)

	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Redundancy audit passed. Features=single-owner Residents=300 Councilors=30 CommitteeMembers=25")
	await TestCleanup.finish(self, [main], exit_code)


func _audit_feature_ownership(main) -> void:
	var public_page := main.public_affairs_panel as Control
	_check(public_page.find_children("*", "ProgressBar", true, false).is_empty(), "public-affairs owns requests only; no grievance/trust bars")
	var public_text := _combined_text(public_page)
	_check(not public_text.contains("民怨") and not public_text.contains("市政信任"), "public-affairs does not repeat HUD civic metrics")

	var report_page := main.municipal_overlay.find_child("月度報告", true, false) as Control
	_check(report_page != null, "monthly report page exists")
	if report_page != null:
		_check(report_page.find_children("*", "ProgressBar", true, false).is_empty(), "monthly report does not repeat current HUD KPI bars")
		_check(report_page.find_child("MonthlySummaryChartGrid", true, false) == null, "monthly report contains no routine metric charts")
		_check(report_page.find_child("MonthlySummary", true, false) != null, "monthly report has one major-event summary section")
		_check(report_page.find_child("VersionUpdateAnnouncements", true, false) != null, "monthly report has one version-update section")
		_check(report_page.find_child("MonthlyReportDetails", true, false) == null, "monthly report has no separate details section")
		_check(report_page.find_child("MonthlyServiceSnapshot", true, false) == null, "monthly report has no separate service section")
	var city_data_page := main.municipal_overlay.find_child("城市數據", true, false) as Control
	_check(city_data_page != null, "city data page exists")
	if city_data_page != null:
		var monthly_data_grid := city_data_page.find_child("MonthlyDataChartGrid", true, false) as GridContainer
		_check(monthly_data_grid != null and monthly_data_grid.get_child_count() == 9, "city data is the single owner of all nine monthly comparison charts")

	_check(main.find_child("DemolishSelectedBuildingButton", true, false) == null, "building page has no duplicate demolition action")
	var demolition_owners := 0
	for button_variant in main.find_children("*", "Button", true, false):
		var button := button_variant as Button
		if str(button.get_meta("semantic_label", "")) == "拆除":
			demolition_owners += 1
	_check(demolition_owners == 1, "demolition has exactly one contextual owner")

	var dock_labels := {}
	for button_variant in main.action_dock.find_children("*", "Button", true, false):
		var button := button_variant as Button
		var semantic_label := str(button.get_meta("semantic_label", button.text))
		_check(not dock_labels.has(semantic_label), "ActionDock semantic action is unique: %s" % semantic_label)
		dock_labels[semantic_label] = true
	_check(dock_labels.size() == 3, "ActionDock keeps only three global actions")
	_check(not dock_labels.has("數據") and not dock_labels.has("月報"), "city data and monthly report are consolidated into the municipal hub")
	var city_data_hub_button := main.municipal_overlay.find_child("%sButton" % "city_data".capitalize(), true, false) as Button
	var report_hub_button := main.municipal_overlay.find_child("%sButton" % "report".capitalize(), true, false) as Button
	_check(city_data_hub_button != null and not city_data_hub_button.disabled, "municipal hub keeps city data directly reachable")
	_check(report_hub_button == null, "monthly report remains a contextual child instead of duplicating a hub card")
	main.municipal_overlay.open_page("report")
	var municipal_back := main.municipal_overlay.find_child("BackButton", true, false) as Button
	if municipal_back != null:
		municipal_back.emit_signal("pressed")
	_check(main.municipal_overlay.current_page() == "city_data", "monthly report returns to city data")

	var main_source := FileAccess.get_file_as_string("res://scripts/app/main.gd")
	_check(not main_source.contains("const BILL_DEFS"), "main has no parallel bill database")
	_check(not main_source.contains("const COUNCILORS"), "main has no parallel seven-member council")
	_check(not main_source.contains("var pending_bills"), "main has no parallel legislative state")
	for legacy_builder in ["_build_top_bar", "_build_left_panel", "_build_right_panel", "_build_report_panel"]:
		_check(not main_source.contains("func %s" % legacy_builder), "legacy UI builder was removed: %s" % legacy_builder)


func _audit_catalogs(main) -> void:
	_check(_keys_are_disjoint(main.TAX_DEFS, main.UTILITY_DEFS), "tax and utility identifiers are disjoint")
	_check(_keys_are_disjoint(main.TAX_DEFS, main.SERVICE_DEFS), "tax and service identifiers are disjoint")
	_check(_keys_are_disjoint(main.UTILITY_DEFS, main.SERVICE_DEFS), "utility and service identifiers are disjoint")

	var catalog: Dictionary = main._governance_bill_catalog()
	var canonical: Dictionary = main.vertical_slice.governance.bill_definitions
	_check(catalog.size() == canonical.size() and canonical.size() == 8, "UI bill catalog is derived one-to-one from canonical governance definitions")
	var bill_names := {}
	for definition_variant in canonical.values():
		var definition: Dictionary = definition_variant
		var bill_name := str(definition.get("name", ""))
		_check(not bill_name.is_empty() and not bill_names.has(bill_name), "canonical bill name is unique: %s" % bill_name)
		bill_names[bill_name] = true
		_check(catalog.has(bill_name), "UI exposes canonical bill: %s" % bill_name)

	var building_names := {}
	for building_name in main.buildings.keys():
		_check(not building_names.has(building_name), "building function is unique: %s" % building_name)
		building_names[building_name] = true
	var policy_names := {}
	for policy_name in main.policies.keys():
		_check(not policy_names.has(policy_name), "policy is unique: %s" % policy_name)
		policy_names[policy_name] = true


func _audit_people(main) -> void:
	var resident_ids := {}
	var resident_profiles := {}
	for npc_id: String in main.vertical_slice.population.sorted_npc_ids():
		var record = main.vertical_slice.population.get_record(npc_id)
		_check(not resident_ids.has(npc_id), "resident id is unique: %s" % npc_id)
		var profile_signature := "%s|%d|%s|%s|%s|%s" % [record.display_name, record.age, record.gender, record.personality, record.address_id, record.job_id]
		_check(not resident_profiles.has(profile_signature), "resident profile is not duplicated: %s" % npc_id)
		resident_ids[npc_id] = true
		resident_profiles[profile_signature] = true
	_check(resident_ids.size() == 300, "resident source of truth contains 300 people")
	_check(main.vertical_slice.session.state.npcs.size() == resident_ids.size(), "core NPC mirror has the canonical resident count")
	_check(int(main.vertical_slice.session.state.metrics.get("population", -1)) == resident_ids.size(), "core population metric has the canonical resident count")
	for core_npc_id: Variant in main.vertical_slice.session.state.npcs.keys():
		_check(resident_ids.has(str(core_npc_id)), "core NPC mirror references a canonical resident: %s" % str(core_npc_id))

	var rendered_ids := {}
	for proxy_variant in main.get_visible_npc_snapshots():
		var proxy: Dictionary = proxy_variant
		var record_id := str(proxy.get("record_id", ""))
		_check(resident_ids.has(record_id), "rendered NPC proxy references a canonical resident: %s" % record_id)
		_check(not rendered_ids.has(record_id), "rendered NPC proxy is not duplicated: %s" % record_id)
		rendered_ids[record_id] = true
	_check(rendered_ids.size() == 24, "map renders 24 unique proxies without a second person database")

	var council_data := _read_json(COUNCIL_PATH)
	var committee_data := _read_json(COMMITTEE_PATH)
	var official_ids := {}
	var official_names := {}
	var council_members: Array = council_data.get("members", [])
	var committee_members: Array = committee_data.get("members", [])
	_check(council_members.size() == 30, "lower council contains 30 members")
	_check(committee_members.size() == 25, "justice and oversight committees contain 25 members")
	for member_variant in council_members:
		_audit_official(member_variant as Dictionary, "member_id", official_ids, official_names)
	for member_variant in committee_members:
		_audit_official(member_variant as Dictionary, "person_id", official_ids, official_names)
	_check(official_ids.size() == 55 and official_names.size() == 55, "all institutional officials are unique across rosters")


func _audit_official(member: Dictionary, id_key: String, ids: Dictionary, names: Dictionary) -> void:
	var person_id := str(member.get(id_key, ""))
	var person_name := str(member.get("name", ""))
	_check(not person_id.is_empty() and not ids.has(person_id), "official id is unique: %s" % person_id)
	_check(not person_name.is_empty() and not names.has(person_name), "official name is unique: %s" % person_name)
	ids[person_id] = true
	names[person_name] = true


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(parsed is Dictionary, "JSON database can be parsed: %s" % path)
	return parsed as Dictionary if parsed is Dictionary else {}


func _keys_are_disjoint(first: Dictionary, second: Dictionary) -> bool:
	for key in first.keys():
		if second.has(key):
			return false
	return true


func _combined_text(root_node: Node) -> String:
	var result := ""
	for label_variant in root_node.find_children("*", "Label", true, false):
		result += "\n%s" % str((label_variant as Label).text)
	for button_variant in root_node.find_children("*", "Button", true, false):
		result += "\n%s" % str((button_variant as Button).text)
	return result


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Redundancy audit failed: %s" % message)
