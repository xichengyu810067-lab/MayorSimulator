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
	var design_changes: Array[Dictionary] = []
	var blueprint_requests: Array[Dictionary] = []
	panel.placement_requested.connect(func(building_name: String) -> void: placement_requests.append(building_name))
	panel.worker_count_changed.connect(func(count: int) -> void: worker_counts.append(count))
	panel.design_changed.connect(func(payload: Dictionary) -> void: design_changes.append(payload.duplicate(true)))
	panel.blueprint_submit_requested.connect(func(payload: Dictionary) -> void: blueprint_requests.append(payload.duplicate(true)))

	var review := {
		"id": "review_000001",
		"sequence": 1,
		"status": "approved",
		"blueprint": {
			"material_id": "brick",
			"size_tier": "medium",
			"floors": 2,
			"requested_workers": 7,
			"decoration_id": "flowers",
			"decoration_count": 1,
			"roof_color": "blue",
			"wall_color": "cream"
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
		},
		"blueprint_library": [{"id": "official_entry", "source": "default", "title": "官方入門版", "usage_count": 0}],
		"active_blueprint_id": "official_entry",
	})

	var material := panel.find_child("BlueprintMaterial", true, false) as OptionButton
	var size := panel.find_child("BlueprintSize", true, false) as OptionButton
	var floors := panel.find_child("BlueprintFloors", true, false) as SpinBox
	var workers := panel.find_child("BlueprintWorkers", true, false) as SpinBox
	var decoration := panel.find_child("BlueprintDecoration", true, false) as OptionButton
	var quote := panel.find_child("BlueprintPlacementQuote", true, false) as Label
	var action := panel.find_child("SubmitBlueprintButton", true, false) as Button
	var status_card := panel.find_child("BlueprintStatus", true, false) as PanelContainer
	var design_workspace := panel.find_child("BlueprintDesignWorkspace", true, false) as HBoxContainer
	var quote_card := panel.find_child("BlueprintQuoteCard", true, false) as PanelContainer
	_check(material != null and str(material.get_item_metadata(material.selected)) == "brick", "approved review did not restore material")
	_check(size != null and str(size.get_item_metadata(size.selected)) == "medium", "approved review did not restore size")
	_check(floors != null and int(floors.value) == 2, "approved review did not restore floors")
	_check(workers != null and int(workers.value) == 7, "approved review did not restore workers")
	_check(decoration != null and str(decoration.get_item_metadata(decoration.selected)) == "flowers", "approved review did not restore decoration")
	_check(quote != null and quote.visible and quote.text.contains("1,000") and quote.text.contains("50,000") and quote.text.contains("51,000") and quote.text.contains("5"), "placement quote is incomplete")
	_check(action != null and not action.disabled, "approved review placement action is disabled")
	_check(design_workspace != null and design_workspace.get_child_count() == 2, "five building design controls are not combined into two task-oriented groups")
	_check(design_workspace != null and int(design_workspace.get_meta("design_control_count", 0)) == 5, "grouped blueprint workspace lost a design control")
	_check(panel.find_child("BlueprintGroup_Size", true, false) != null and panel.find_child("BlueprintGroup_Workers", true, false) != null, "blueprint task groups are missing")
	_check(quote_card != null and status_card != null and quote_card.get_index() < status_card.get_index(), "live quote is not positioned before review and construction status")
	_check(panel.find_child("BlueprintParameterGroups", true, false) == null, "building design still depends on a TabContainer switch")
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
		panel.refresh_localization()
		panel.call("_select_picker_id", material, "eco_composite")
		_check(material.get_item_text(material.selected) == "Eco composite", "English eco-composite selection is not concise")
		_check(material.tooltip_text == "Environmentally friendly composite material", "localized picker tooltip does not preserve the full selected value")
		_check(l10n.text("草稿估價｜%s・%s・%d 樓・%s・%s｜占地 %d 格｜基礎／設計 $%s ＋ 人工 $%s ＝ 總額 $%s｜工期 %d 日").begins_with("Draft quote"), "English draft quote copy is missing")
		_check(l10n.text("%d 人") == "%d workers", "English worker summary is missing")
		var worker_summary_by_locale := {"zh_CN": "%d 人", "ja": "%d 人", "ko": "%d명"}
		for locale in ["zh_CN", "ja", "ko"]:
			l10n.set_locale(locale, false)
			_check(l10n.text("五項設計會同頁顯示；每次調整都立即重算開工前估價。") != "五項設計會同頁顯示；每次調整都立即重算開工前估價。", "%s single-page design guide is missing" % locale)
			_check(l10n.text("草稿估價｜%s・%s・%d 樓・%s・%s｜占地 %d 格｜基礎／設計 $%s ＋ 人工 $%s ＝ 總額 $%s｜工期 %d 日") != "草稿估價｜%s・%s・%d 樓・%s・%s｜占地 %d 格｜基礎／設計 $%s ＋ 人工 $%s ＝ 總額 $%s｜工期 %d 日", "%s draft quote copy is missing" % locale)
			_check(l10n.text("%d 人") == str(worker_summary_by_locale[locale]), "%s worker summary is missing" % locale)
		l10n.set_locale("zh_TW", false)
		panel.refresh_localization()
		panel.call("_select_picker_id", material, "brick")
		panel.set_view_model({"blueprint_review": review})
		panel.refresh_localization()
		_check(material.get_item_text(material.selected) == "磚造", "locale round-trip left the material caption in English")
		var library_status := panel.find_child("BlueprintLibraryStatus", true, false) as Label
		_check(library_status != null and not library_status.text.contains("Permanent"), "locale round-trip left the blueprint library status in English")

	action.pressed.emit()
	_check(placement_requests == ["住宅"], "placement action did not emit the selected building")
	material.call("set_show_all_choices", true)
	material.call("_on_item_selected", 2)
	size.call("_on_item_selected", 2)
	floors.value = 6
	workers.value = 9
	decoration.call("_on_item_selected", 1)
	_check(not worker_counts.is_empty() and worker_counts.back() == 9, "worker change was not emitted")
	_check(design_changes.size() >= 5, "each of the five real design controls must emit an immediate draft change")
	var latest_draft: Dictionary = design_changes.back() if not design_changes.is_empty() else {}
	_check(
		str(latest_draft.get("material_id", "")) == "steel"
		and str(latest_draft.get("size_tier", "")) == "large"
		and int(latest_draft.get("floors", 0)) == 6
		and int(latest_draft.get("workers", 0)) == 9
		and str(latest_draft.get("decor_id", "")) == "flags",
		"draft event did not retain the complete current UI selection"
	)
	_check(action.text == "送審自訂版", "dirty material/size draft must replace the placement CTA with custom approval")
	action.pressed.emit()
	_check(placement_requests == ["住宅"] and blueprint_requests.size() == 1, "dirty draft must submit rather than enter placement")
	_check(str(blueprint_requests[0].get("size_tier", "")) == "large" and str(blueprint_requests[0].get("material_id", "")) == "steel", "dirty submission did not retain the changed design")

	var same_review := review.duplicate(true)
	same_review["status"] = "approved"
	panel.set_view_model({"blueprint_review": same_review})
	_check(str(material.call("selected_choice_id")) == "steel", "refresh overwrote the current draft for an unchanged review")
	material.call("_on_item_selected", 1)
	size.call("_on_item_selected", 1)
	floors.value = 2
	decoration.call("_on_item_selected", 0)
	_check(action.text == "回到地圖放置", "reverting all design fields to the approved version must restore placement")
	action.pressed.emit()
	_check(placement_requests == ["住宅", "住宅"], "reverted approved design did not restore placement action")
	var station_review := review.duplicate(true)
	station_review["building_name"] = "火車站"
	station_review["blueprint"]["building_name"] = "火車站"
	panel.set_selected_building("火車站")
	panel.set_view_model({"transport_station_mode": true, "blueprint_review": station_review})
	_check(action.text == "開始連續站點規劃", "approved station blueprint does not replace generic placement with continuous planning")
	action.pressed.emit()
	_check(placement_requests == ["住宅", "住宅", "火車站"], "continuous station action did not emit the selected station")
	panel.set_selected_building("住宅")

	var next_review := review.duplicate(true)
	next_review["id"] = "review_000002"
	next_review["sequence"] = 2
	next_review["blueprint"]["material_id"] = "steel"
	next_review["blueprint"]["size_tier"] = "large"
	next_review["blueprint"]["floors"] = 4
	next_review["blueprint"]["requested_workers"] = 5
	next_review["blueprint"]["decoration_id"] = "flags"
	next_review["blueprint"]["roof_color"] = "legacy_red"
	next_review["blueprint"]["wall_color"] = "legacy_gray"
	next_review["blueprint"]["base_cost"] = 777
	panel.set_view_model({
		"blueprint_review": next_review,
		"placement_quote": {"base_cost": 777, "total_labor_cost": 50000, "total_cost": 50777, "duration_days": 5}
	})
	_check(str(material.call("selected_choice_id")) == "steel", "new review did not refresh the displayed blueprint")
	var legacy_state: Dictionary = panel.active_design_state()
	_check(bool(legacy_state.get("matches_active_approved", false)), "non-editable legacy roof/wall values cannot make an otherwise matching approved design dirty")
	_check(action.text == "回到地圖放置" and quote.text.contains("777") and quote.text.contains("50,000"), "matching legacy approved design must show its stored active quote and placement CTA")
	action.pressed.emit()
	_check(placement_requests == ["住宅", "住宅", "火車站", "住宅"], "matching legacy approved design does not restore placement")

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
