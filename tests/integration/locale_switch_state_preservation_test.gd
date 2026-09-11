extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const SWITCH_LOCALES := ["ja", "zh_TW"]
const TRACKED_OBJECT_PROPERTIES := [
	"vertical_slice",
	"map_stage",
	"npc_map_controller",
	"transport_network_layer",
	"transport_vehicle_controller",
	"start_screen",
]
const SUCCESS_MARKER := "LOCALE_SWITCH_STATE_PRESERVATION_TEST_PASSED"

var _failed := false
var _checks := 0
var _l10n


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	_l10n = root.get_node_or_null("L10n")
	if _l10n == null:
		_fail("L10n autoload is available")
		await _finish(null, "")
		return

	var original_locale := str(_l10n.current_locale)
	_check(_l10n.set_locale("en", false), "English locale can be selected without persistence")
	var packed := load("res://scenes/Main.tscn") as PackedScene
	if packed == null:
		_fail("Main scene can be loaded")
		await _finish(null, original_locale)
		return

	var main := packed.instantiate()
	root.add_child(main)
	await _settle(4)
	var municipal_overlay: Control = main.call("_ensure_municipal_overlay") as Control
	_check(municipal_overlay != null, "the lazy municipal overlay can be materialized for fiscal localization checks")
	if municipal_overlay == null:
		await _finish(main, original_locale)
		return
	municipal_overlay.call("open_page", "finance")
	await _settle(2)
	var baseline_caption := _new_game_caption(main)
	var required_objects_ready := _check_required_objects(main)
	_check(baseline_caption != null, "the start screen exposes its new-game caption")
	if not required_objects_ready or baseline_caption == null:
		await _finish(main, original_locale)
		return

	_check(main.vertical_slice.is_time_paused(), "the simulation is paused while the start screen is open")
	var baseline_ids := _capture_object_ids(main, baseline_caption)
	var baseline_state := _capture_state_summary(main)
	var previous_caption_text := baseline_caption.text
	var expected_english := str(_l10n.text("新遊戲"))
	_check(previous_caption_text == expected_english, "English is rendered before the locale-switch sequence")
	_check(expected_english != "新遊戲", "the English check observes translated text, not the source label")
	_validate_fiscal_tax_units(main, "en")

	for locale in SWITCH_LOCALES:
		_check(_l10n.set_locale(locale, false), "%s locale can be selected without persistence" % locale)
		await _settle(3)
		var current_caption := _new_game_caption(main)
		_check(current_caption != null, "%s keeps the new-game caption available" % locale)
		var current_ids := _capture_object_ids(main, current_caption)
		_check(
			current_ids == baseline_ids,
			"%s updates in place without replacing tracked game objects: expected=%s actual=%s" % [
				locale,
				baseline_ids,
				current_ids,
			]
		)
		_check(
			_capture_state_summary(main) == baseline_state,
			"%s preserves the canonical simulation and player-shell state" % locale
		)
		if current_caption != null:
			var expected_text := str(_l10n.text("新遊戲"))
			_check(
				current_caption.text == expected_text,
				"%s updates the existing new-game caption: expected='%s' actual='%s'" % [
					locale,
					expected_text,
					current_caption.text,
				]
			)
			_check(
				current_caption.text != previous_caption_text,
				"%s visibly differs from the preceding locale" % locale
			)
			previous_caption_text = current_caption.text
		_validate_fiscal_tax_units(main, locale)

	await _finish(main, original_locale)


func _check_required_objects(main) -> bool:
	var ready := true
	for property_name_variant in TRACKED_OBJECT_PROPERTIES:
		var property_name := str(property_name_variant)
		var object_value := main.get(property_name) as Object
		var available := object_value != null and is_instance_valid(object_value)
		_check(available, "Main.%s is available for identity tracking" % property_name)
		ready = ready and available
	return ready


func _capture_object_ids(main, caption: Label) -> Dictionary:
	var result := {"main": int(main.get_instance_id())}
	for property_name_variant in TRACKED_OBJECT_PROPERTIES:
		var property_name := str(property_name_variant)
		var object_value := main.get(property_name) as Object
		result[property_name] = (
			-1
			if object_value == null or not is_instance_valid(object_value)
			else int(object_value.get_instance_id())
		)
	result["new_game_caption"] = (
		-1
		if caption == null or not is_instance_valid(caption)
		else int(caption.get_instance_id())
	)
	return result


func _capture_state_summary(main) -> Dictionary:
	var vertical_slice = main.vertical_slice
	var main_shell_state := {
		"city_grid": main.city_grid,
		"building_customizations": main.building_customizations,
		"active_policies": main.active_policies,
		"tax_rates": main.tax_rates,
		"utility_fees": main.utility_fees,
		"service_fees": main.service_fees,
		"announcements": main.announcements,
		"selected_building": main.selected_building,
		"selected_cell_index": main.selected_cell_index,
		"game_started": main._game_started,
		"tutorial_completed": main.tutorial_completed,
		"map_action_mode": main.map_action_mode,
	}
	return {
		"game_day": int(vertical_slice.game_day()),
		"treasury_balance": int(vertical_slice.treasury_balance()),
		"population_count": int(vertical_slice.population.population_count()),
		"time_paused": bool(vertical_slice.is_time_paused()),
		"canonical_state_hash": _variant_hash(vertical_slice.session.state.to_dict()),
		"construction_hash": _variant_hash(vertical_slice.construction.to_dict()),
		"durability_hash": _variant_hash(vertical_slice.durability.to_dict()),
		"governance_hash": _variant_hash(vertical_slice.governance.to_dict()),
		"population_hash": _variant_hash(vertical_slice.population.to_dict()),
		"terrain_hash": _variant_hash(vertical_slice.terrain_snapshot()),
		"transport_hash": _variant_hash(vertical_slice.transport.to_dict()),
		"player_shell_hash": _variant_hash(vertical_slice.get_player_shell_state()),
		"main_shell_hash": _variant_hash(main_shell_state),
	}


func _variant_hash(value: Variant) -> int:
	return hash(JSON.stringify(value))


func _new_game_caption(main) -> Label:
	if main == null or main.start_screen == null or main.start_screen.new_game_button == null:
		return null
	return _first_descendant_label(main.start_screen.new_game_button)


func _validate_fiscal_tax_units(main, locale: String) -> void:
	var expected_sources := {
		"income": "% / 所得",
		"consumption": "% / 消費額",
	}
	for tax_key_variant in expected_sources.keys():
		var tax_key := str(tax_key_variant)
		var unit_label := main.find_child("FiscalTaxUnit_%s" % tax_key, true, false) as Label
		_check(unit_label != null, "%s keeps the %s tax unit available" % [locale, tax_key])
		if unit_label == null:
			continue
		var expected := str(_l10n.text(str(expected_sources[tax_key])))
		_check(
			unit_label.text == expected,
			"%s renders the %s tax unit from its canonical source: expected='%s' actual='%s'" % [
				locale,
				tax_key,
				expected,
				unit_label.text,
			]
		)


func _first_descendant_label(node: Node) -> Label:
	for child in node.get_children():
		if child is Label:
			return child as Label
		var nested := _first_descendant_label(child)
		if nested != null:
			return nested
	return null


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame


func _finish(main, original_locale: String) -> void:
	var fixtures: Array = []
	if main != null and is_instance_valid(main):
		fixtures.append(main)
	await TestCleanup.release_fixtures(self, fixtures)
	if _l10n != null and not original_locale.is_empty():
		_l10n.set_locale(original_locale, false)
	var exit_code := 1 if _failed else 0
	if not _failed:
		print("%s Checks=%d" % [SUCCESS_MARKER, _checks])
	quit(exit_code)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failed = true
	push_error("Locale-switch state-preservation check failed: %s" % message)
