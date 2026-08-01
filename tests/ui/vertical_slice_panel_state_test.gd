extends SceneTree

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var VerticalSlicePanelScript = load("res://ui/shell/vertical_slice_panel.gd")
	if VerticalSlicePanelScript == null:
		push_error("Vertical slice panel script could not be loaded.")
		quit(1)
		return
	var panel = VerticalSlicePanelScript.new()
	root.add_child(panel)
	panel.set_selected_building("住宅")

	var placement_requests: Array[String] = []
	var worker_counts: Array[int] = []
	panel.placement_requested.connect(func(building_name: String) -> void: placement_requests.append(building_name))
	panel.worker_count_changed.connect(func(count: int) -> void: worker_counts.append(count))

	var review := {
		"id": "review_000001",
		"sequence": 1,
		"status": "approved",
		"blueprint": {
			"material_id": "brick",
			"size_tier": "large",
			"floors": 6,
			"requested_workers": 7,
			"decoration_id": "flags"
		}
	}
	panel.set_view_model({
		"available_workers": 20,
		"blueprint_review": review,
		"placement_quote": {
			"base_cost": 1000,
			"total_labor_cost": 50000,
			"total_cost": 51000,
			"duration_days": 5
		}
	})

	var material := panel.find_child("BlueprintMaterial", true, false) as OptionButton
	var size := panel.find_child("BlueprintSize", true, false) as OptionButton
	var floors := panel.find_child("BlueprintFloors", true, false) as SpinBox
	var workers := panel.find_child("BlueprintWorkers", true, false) as SpinBox
	var decoration := panel.find_child("BlueprintDecoration", true, false) as OptionButton
	var quote := panel.find_child("BlueprintPlacementQuote", true, false) as Label
	var action := panel.find_child("SubmitBlueprintButton", true, false) as Button
	var status_card := panel.find_child("BlueprintStatus", true, false) as PanelContainer
	_check(material != null and str(material.get_item_metadata(material.selected)) == "brick", "approved review did not restore material")
	_check(size != null and str(size.get_item_metadata(size.selected)) == "large", "approved review did not restore size")
	_check(floors != null and int(floors.value) == 6, "approved review did not restore floors")
	_check(workers != null and int(workers.value) == 7, "approved review did not restore workers")
	_check(decoration != null and str(decoration.get_item_metadata(decoration.selected)) == "flags", "approved review did not restore decoration")
	_check(quote != null and quote.visible and quote.text.contains("1,000") and quote.text.contains("50,000") and quote.text.contains("51,000") and quote.text.contains("5"), "placement quote is incomplete")
	_check(action != null and not action.disabled, "approved review placement action is disabled")
	_check(_has_style_states(material, ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]), "blueprint option buttons still use incomplete default styles")
	_check(material.get_theme_constant("modulate_arrow") == 1, "blueprint option arrow does not follow the readable text color")
	_check(_has_style_states(material.get_popup(), ["panel", "hover"]), "blueprint option popup still uses default styles")
	_check(material.get_theme_font_size("font_size") >= 18 and material.get_popup().get_theme_font_size("font_size") >= 18, "blueprint picker or popup text is smaller than 18px")
	_check(material.custom_minimum_size.x >= 166.0, "blueprint picker width is too small for localized selections")
	_check(_has_style_states(floors.get_line_edit(), ["normal", "focus", "read_only"]), "blueprint floor input still uses default styles")
	_check(_has_style_states(workers.get_line_edit(), ["normal", "focus", "read_only"]), "blueprint worker input still uses default styles")
	_check(_has_style_states(floors, ["up_background", "up_background_hovered", "up_background_pressed", "up_background_disabled", "down_background", "down_background_hovered", "down_background_pressed", "down_background_disabled"]), "blueprint spin buttons still use incomplete default styles")
	_check(floors.has_theme_color_override("up_icon_modulate") and floors.has_theme_color_override("down_icon_modulate"), "blueprint spin arrows do not follow the readable text color")
	_check(action.has_theme_stylebox_override("focus"), "blueprint action button has no focus style")
	var status_style := status_card.get_theme_stylebox("panel") as StyleBoxFlat if status_card != null else null
	_check(status_style != null and status_style.content_margin_left >= 12.0 and status_style.content_margin_top >= 10.0 and status_style.content_margin_right >= 12.0 and status_style.content_margin_bottom >= 10.0, "blueprint status card has no safe content margins")
	var light_picker_style := material.get_theme_stylebox("normal") as StyleBoxFlat
	var light_picker_background := light_picker_style.bg_color if light_picker_style != null else Color.TRANSPARENT
	panel.set_dark_mode(true)
	var dark_picker_style := material.get_theme_stylebox("normal") as StyleBoxFlat
	_check(dark_picker_style != null and dark_picker_style.bg_color != light_picker_background, "blueprint controls did not refresh for dark mode")
	_check(_has_style_states(material.get_popup(), ["panel", "hover"]), "blueprint popup styles were lost after theme refresh")
	var l10n = root.get_node_or_null("L10n")
	_check(l10n != null, "localization service is unavailable for picker checks")
	var original_locale := str(l10n.current_locale) if l10n != null else "zh_TW"
	if l10n != null:
		l10n.set_locale("en", false)
		l10n.localize_tree(panel)
		panel.call("_select_picker_id", material, "eco_composite")
		_check(material.get_item_text(material.selected) == "Eco composite", "English eco-composite selection is not concise")
		_check(material.tooltip_text == "Environmentally friendly composite material", "localized picker tooltip does not preserve the full selected value")

	action.pressed.emit()
	_check(placement_requests == ["住宅"], "placement action did not emit the selected building")
	workers.value = 9
	_check(not worker_counts.is_empty() and worker_counts.back() == 9, "worker change was not emitted")

	material.select_choice("wood")
	var same_review := review.duplicate(true)
	same_review["status"] = "completed"
	panel.set_view_model({"blueprint_review": same_review})
	_check(str(material.get_item_metadata(material.selected)) == "wood", "refresh overwrote the current draft for an unchanged review")

	var next_review := review.duplicate(true)
	next_review["id"] = "review_000002"
	next_review["sequence"] = 2
	next_review["blueprint"]["material_id"] = "steel"
	panel.set_view_model({"blueprint_review": next_review})
	_check(str(material.get_item_metadata(material.selected)) == "steel", "new review did not refresh the displayed blueprint")

	panel.queue_free()
	if l10n != null:
		l10n.set_locale(original_locale, false)
	if _failed:
		quit(1)
	else:
		print("Vertical slice panel state test passed.")
		quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)


func _has_style_states(control, states: Array[String]) -> bool:
	if control == null:
		return false
	for state in states:
		if not control.has_theme_stylebox_override(state):
			return false
	return true
