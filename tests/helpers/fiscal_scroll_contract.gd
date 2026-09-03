extends RefCounted

const GEOMETRY_EPSILON := 1.5
const CATEGORY_IDS := ["resident_tax", "industry_tax", "utilities", "environment_energy", "city_services", "education_leisure"]


static func expected_slider_names(scene: Object) -> Array[String]:
	var names: Array[String] = []
	if scene == null or not is_instance_valid(scene):
		return names
	var properties: Array[StringName] = [&"tax_rates", &"utility_fees", &"service_fees"]
	var prefixes := ["tax", "utility", "service"]
	for index in properties.size():
		var values: Variant = scene.get(properties[index])
		if values is Dictionary:
			var keys: Array = values.keys()
			keys.sort()
			for key in keys:
				names.append("FiscalSlider_%s_%s" % [prefixes[index], str(key)])
	names.sort()
	return names


static func validate(tree: SceneTree, overlay: Control, _legacy_tabs: Variant, expected_names: Array[String]) -> Dictionary:
	var failures: Array[String] = []
	var result := {
		"ok": false,
		"logical_viewport": [roundi(tree.root.get_visible_rect().size.x), roundi(tree.root.get_visible_rect().size.y)],
		"overflow": false, "vertical_scroll_mode": -1, "actual_content_height": 0.0,
		"combined_minimum_height": 0.0, "viewport_height": 0.0, "range_page": 0.0,
		"maximum_scroll": 0.0, "reached_range_end": false, "content_moved": false,
		"category_count": 0, "plan_count": 0, "verified_slider_count": 0,
		"verified_slider_names": [], "expected_slider_count": expected_names.size(),
		"expected_slider_names": expected_names, "preview_hidden_in_edit": false,
		"scroll_restored": false, "navigation_restored": false, "tabs_restored": false,
		"errors": failures,
	}
	if overlay == null or not is_instance_valid(overlay):
		failures.append("Fiscal scroll contract could not find the municipal overlay.")
		result["errors"] = failures
		return result
	var scroll := overlay.find_child("稅率與公共事業費", true, false) as ScrollContainer
	var category_grid := overlay.find_child("FiscalCategoryCardGrid", true, false) as GridContainer
	var custom_editor := overlay.find_child("FiscalCustomEditor", true, false) as Control
	var preview := overlay.find_child("FiscalDraftPreview", true, false) as Control
	var back_button := overlay.find_child("FiscalBackToCategories", true, false) as Button
	if scroll == null or category_grid == null or custom_editor == null or preview == null or back_button == null:
		failures.append("Fiscal card, custom-editor, preview, or scroll surface is incomplete.")
		result["errors"] = failures
		return result
	if overlay.find_child("FiscalCategoryTabs", true, false) != null:
		failures.append("Legacy FiscalCategoryTabs must not coexist with the six-card workflow.")
	var cards: Array[Button] = []
	for category_id: String in CATEGORY_IDS:
		var card := overlay.find_child("FiscalCategoryCard_%s" % category_id, true, false) as Button
		if card == null:
			failures.append("Missing fiscal category card '%s'." % category_id)
		else:
			cards.append(card)
			if card.custom_minimum_size.y < 44.0:
				failures.append("Fiscal category card '%s' is below the 44px target." % category_id)
	var plans := overlay.find_children("FiscalPlanCard_*", "Button", true, false)
	result["category_count"] = cards.size()
	result["plan_count"] = plans.size()
	if cards.size() != 6:
		failures.append("Fiscal category card count is %d; expected 6." % cards.size())
	if plans.size() != 3:
		failures.append("Fiscal plan card count is %d; expected 3." % plans.size())
	for plan_variant in plans:
		var plan := plan_variant as Button
		if plan != null and plan.custom_minimum_size.y < 44.0:
			failures.append("Fiscal plan card '%s' is below the 44px target." % plan.name)

	var vertical_bar := scroll.get_v_scroll_bar()
	var content := _first_visible_control_child(scroll)
	if vertical_bar == null or content == null:
		failures.append("Fiscal ScrollContainer does not expose its range and content.")
		result["errors"] = failures
		return result
	var original_scroll := Vector2i(scroll.scroll_horizontal, scroll.scroll_vertical)
	var viewport_height := scroll.get_global_rect().size.y
	var maximum_scroll := maxf(0.0, vertical_bar.max_value - vertical_bar.page)
	var overflows := content.size.y > viewport_height + GEOMETRY_EPSILON
	result["overflow"] = overflows
	result["vertical_scroll_mode"] = scroll.vertical_scroll_mode
	result["actual_content_height"] = snappedf(content.size.y, 0.001)
	result["combined_minimum_height"] = snappedf(content.get_combined_minimum_size().y, 0.001)
	result["viewport_height"] = snappedf(viewport_height, 0.001)
	result["range_page"] = snappedf(vertical_bar.page, 0.001)
	result["maximum_scroll"] = snappedf(maximum_scroll, 0.001)
	if overflows and (scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED or maximum_scroll <= GEOMETRY_EPSILON):
		failures.append("Overflowing fiscal content is not scrollable.")
	if not overflows and maximum_scroll > GEOMETRY_EPSILON:
		failures.append("Non-overflowing fiscal content exposes a phantom scroll range.")
	if maximum_scroll > GEOMETRY_EPSILON:
		scroll.scroll_vertical = 0
		await _settle(tree, 2)
		var initial_y := content.get_global_rect().position.y
		scroll.scroll_vertical = roundi(maximum_scroll)
		await _settle(tree, 2)
		result["reached_range_end"] = absf(float(scroll.scroll_vertical) - maximum_scroll) <= GEOMETRY_EPSILON
		result["content_moved"] = content.get_global_rect().position.y < initial_y - GEOMETRY_EPSILON
		if not bool(result["reached_range_end"]) or not bool(result["content_moved"]):
			failures.append("Fiscal page cannot traverse its declared scroll range.")

	var verified := {}
	var custom_plan := overlay.find_child("FiscalPlanCard_custom", true, false) as Button
	if custom_plan == null:
		failures.append("Missing custom fiscal plan card.")
	else:
		for card in cards:
			card.pressed.emit()
			await _settle(tree, 2)
			custom_plan.pressed.emit()
			await _settle(tree, 2)
			var visible_count := 0
			for slider_variant in custom_editor.find_children("FiscalSlider_*", "HSlider", true, false):
				var slider := slider_variant as HSlider
				if slider == null or not slider.is_visible_in_tree():
					continue
				visible_count += 1
				verified[str(slider.name)] = true
				scroll.ensure_control_visible(slider)
				await _settle(tree, 2)
				var effective := _effective_visible_rect(tree, slider).intersection(scroll.get_global_rect())
				if not effective.has_area() or not _encloses_with_epsilon(effective, slider.get_global_rect()):
					failures.append("Fiscal slider '%s' cannot be fully scrolled into view." % slider.get_path())
			if visible_count != 2:
				failures.append("Fiscal category '%s' exposes %d custom sliders; expected 2." % [card.name, visible_count])
			back_button.pressed.emit()
			await _settle(tree, 2)
	var verified_names: Array[String] = []
	verified_names.assign(verified.keys())
	verified_names.sort()
	result["verified_slider_count"] = verified_names.size()
	result["verified_slider_names"] = verified_names
	if verified_names != expected_names:
		failures.append("Fiscal card traversal did not reach the authoritative slider set: actual=%s expected=%s." % [verified_names, expected_names])
	result["preview_hidden_in_edit"] = not preview.is_visible_in_tree()
	if not bool(result["preview_hidden_in_edit"]):
		failures.append("EDIT must not show the whole-draft preview during category traversal.")
	scroll.scroll_horizontal = original_scroll.x
	scroll.scroll_vertical = original_scroll.y
	await _settle(tree, 3)
	result["scroll_restored"] = absf(float(scroll.scroll_vertical - original_scroll.y)) <= GEOMETRY_EPSILON
	result["navigation_restored"] = category_grid.is_visible_in_tree() and not custom_editor.is_visible_in_tree()
	result["tabs_restored"] = result["navigation_restored"]
	result["errors"] = failures
	result["ok"] = failures.is_empty()
	return result


static func _first_visible_control_child(parent: Control) -> Control:
	for child_variant in parent.get_children():
		var child := child_variant as Control
		if child != null and child.is_visible_in_tree():
			return child
	return null


static func _effective_visible_rect(tree: SceneTree, control: Control) -> Rect2:
	var visible_rect := control.get_global_rect().intersection(Rect2(Vector2.ZERO, tree.root.get_visible_rect().size))
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is Control and (ancestor as Control).clip_contents:
			visible_rect = visible_rect.intersection((ancestor as Control).get_global_rect())
		ancestor = ancestor.get_parent()
	return visible_rect


static func _encloses_with_epsilon(outer: Rect2, inner: Rect2) -> bool:
	return inner.position.x >= outer.position.x - GEOMETRY_EPSILON and inner.position.y >= outer.position.y - GEOMETRY_EPSILON and inner.end.x <= outer.end.x + GEOMETRY_EPSILON and inner.end.y <= outer.end.y + GEOMETRY_EPSILON


static func _settle(tree: SceneTree, frames: int) -> void:
	for _frame in range(frames):
		await tree.process_frame
