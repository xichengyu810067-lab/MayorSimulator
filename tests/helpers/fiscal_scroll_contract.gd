extends RefCounted

## Shared GUI-only acceptance for the responsive fiscal page. The product may
## use AUTO scrolling at every resolution; acceptance depends on actual content
## overflow, a truthful range, control reachability, and state restoration.

const GEOMETRY_EPSILON := 1.5


static func expected_slider_names(scene: Object) -> Array[String]:
	var names: Array[String] = []
	if scene == null or not is_instance_valid(scene):
		return names
	var property_names: Array[StringName] = [&"tax_rates", &"utility_fees", &"service_fees"]
	var prefixes: Array[String] = ["tax", "utility", "service"]
	for index in property_names.size():
		var property_name := property_names[index]
		var definitions: Variant = scene.get(property_name)
		if definitions is Dictionary:
			var keys: Array = (definitions as Dictionary).keys()
			keys.sort()
			for key: Variant in keys:
				names.append("FiscalSlider_%s_%s" % [prefixes[index], str(key)])
	names.sort()
	return names


static func validate(
	tree: SceneTree,
	overlay: Control,
	fiscal_tabs: TabContainer,
	expected_slider_names: Array[String]
) -> Dictionary:
	var failures: Array[String] = []
	var expected_name_set := {}
	for slider_name in expected_slider_names:
		if expected_name_set.has(slider_name):
			failures.append("Authoritative fiscal dictionaries derived duplicate slider '%s'." % slider_name)
		expected_name_set[slider_name] = true
	var result := {
		"ok": false,
		"logical_viewport": [
			roundi(tree.root.get_visible_rect().size.x),
			roundi(tree.root.get_visible_rect().size.y),
		],
		"overflow": false,
		"vertical_scroll_mode": -1,
		"actual_content_height": 0.0,
		"combined_minimum_height": 0.0,
		"viewport_height": 0.0,
		"range_page": 0.0,
		"maximum_scroll": 0.0,
		"reached_range_end": false,
		"content_moved": false,
		"verified_slider_count": 0,
		"verified_slider_names": [],
		"expected_slider_count": expected_slider_names.size(),
		"expected_slider_names": expected_slider_names,
		"scroll_restored": false,
		"tabs_restored": false,
		"errors": failures,
	}
	if overlay == null or not is_instance_valid(overlay):
		failures.append("Fiscal scroll contract could not find the municipal overlay.")
		result["errors"] = failures
		return result
	if fiscal_tabs == null or not is_instance_valid(fiscal_tabs):
		failures.append("Fiscal scroll contract could not find FiscalCategoryTabs.")
		result["errors"] = failures
		return result

	var fiscal_scroll := overlay.find_child("稅率與公共事業費", true, false) as ScrollContainer
	if fiscal_scroll == null:
		failures.append("Fiscal scroll contract could not find the fiscal ScrollContainer.")
		result["errors"] = failures
		return result
	var vertical_bar := fiscal_scroll.get_v_scroll_bar()
	var content := _first_visible_control_child(fiscal_scroll)
	if vertical_bar == null or content == null:
		failures.append("Fiscal ScrollContainer does not expose its range and content.")
		result["errors"] = failures
		return result

	var actual_slider_names: Array[String] = []
	var actual_name_set := {}
	for node_variant in fiscal_tabs.find_children("FiscalSlider_*", "HSlider", true, false):
		var slider := node_variant as HSlider
		if slider == null:
			continue
		var slider_name := str(slider.name)
		actual_slider_names.append(slider_name)
		if actual_name_set.has(slider_name):
			failures.append("Fiscal UI exposes duplicate slider node '%s'." % slider_name)
		actual_name_set[slider_name] = true
	actual_slider_names.sort()
	if expected_slider_names.is_empty():
		failures.append("Fiscal slider expectation could not be derived from the authoritative fiscal dictionaries.")
	elif actual_slider_names != expected_slider_names:
		failures.append(
			"Fiscal UI slider names do not match the authoritative fiscal dictionaries: actual=%s expected=%s." % [
				actual_slider_names,
				expected_slider_names,
			]
		)

	var original_scroll := Vector2i(fiscal_scroll.scroll_horizontal, fiscal_scroll.scroll_vertical)
	var original_root_tab := fiscal_tabs.current_tab
	var original_sub_tabs: Array[Dictionary] = []
	for category_index in range(fiscal_tabs.get_tab_count()):
		var subcategories := fiscal_tabs.get_child(category_index) as TabContainer
		if subcategories != null:
			original_sub_tabs.append({"tabs": subcategories, "current": subcategories.current_tab})

	var scroll_rect := fiscal_scroll.get_global_rect()
	var actual_content_height := content.size.y
	var combined_minimum_height := content.get_combined_minimum_size().y
	var viewport_height := scroll_rect.size.y
	var maximum_scroll := maxf(0.0, vertical_bar.max_value - vertical_bar.page)
	var overflows := actual_content_height > viewport_height + GEOMETRY_EPSILON
	result["overflow"] = overflows
	result["vertical_scroll_mode"] = fiscal_scroll.vertical_scroll_mode
	result["actual_content_height"] = snappedf(actual_content_height, 0.001)
	result["combined_minimum_height"] = snappedf(combined_minimum_height, 0.001)
	result["viewport_height"] = snappedf(viewport_height, 0.001)
	result["range_page"] = snappedf(vertical_bar.page, 0.001)
	result["maximum_scroll"] = snappedf(maximum_scroll, 0.001)

	if not _rect_is_finite(scroll_rect) or viewport_height <= GEOMETRY_EPSILON:
		failures.append("Fiscal ScrollContainer has invalid viewport geometry: %s." % scroll_rect)
	if overflows:
		if fiscal_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
			failures.append(_range_diagnostic("Overflowing fiscal content has vertical scrolling disabled", result))
		if maximum_scroll <= GEOMETRY_EPSILON:
			failures.append(_range_diagnostic("Overflowing fiscal content has no positive scroll range", result))
	else:
		if maximum_scroll > GEOMETRY_EPSILON:
			failures.append(_range_diagnostic("Non-overflowing fiscal content exposes a phantom scroll range", result))

	if maximum_scroll > GEOMETRY_EPSILON:
		fiscal_scroll.scroll_vertical = 0
		await _settle(tree, 2)
		var content_top_y := content.get_global_rect().position.y
		fiscal_scroll.scroll_vertical = roundi(maximum_scroll)
		await _settle(tree, 2)
		result["reached_range_end"] = absf(float(fiscal_scroll.scroll_vertical) - maximum_scroll) <= GEOMETRY_EPSILON
		result["content_moved"] = content.get_global_rect().position.y < content_top_y - GEOMETRY_EPSILON
		if not bool(result["reached_range_end"]):
			failures.append(_range_diagnostic("Fiscal ScrollContainer cannot reach its declared range end", result))
		if not bool(result["content_moved"]):
			failures.append(_range_diagnostic("Fiscal scroll range does not physically move its content", result))

	var verified_sliders := {}
	for category_index in range(fiscal_tabs.get_tab_count()):
		fiscal_tabs.current_tab = category_index
		await _settle(tree, 2)
		var subcategories := fiscal_tabs.get_child(category_index) as TabContainer
		if subcategories == null:
			failures.append("Fiscal category %d is not a TabContainer." % category_index)
			continue
		for subcategory_index in range(subcategories.get_tab_count()):
			subcategories.current_tab = subcategory_index
			await _settle(tree, 2)
			var leaf_slider_count := 0
			var leaf_row_count := 0
			for row_variant in fiscal_tabs.find_children("FiscalRow_*", "VBoxContainer", true, false):
				var row := row_variant as VBoxContainer
				if row == null or not row.is_visible_in_tree():
					continue
				leaf_row_count += 1
				var row_sliders: Array[Node] = row.find_children("FiscalSlider_*", "HSlider", true, false)
				if row_sliders.size() != 1:
					failures.append(
						"Fiscal row '%s' exposes %d sliders; expected exactly one." % [row.get_path(), row_sliders.size()]
					)
				elif not expected_name_set.has(str(row_sliders[0].name)):
					failures.append("Fiscal row '%s' exposes unknown slider '%s'." % [row.get_path(), row_sliders[0].name])
			for node_variant in fiscal_tabs.find_children("FiscalSlider_*", "HSlider", true, false):
				var slider := node_variant as HSlider
				if slider == null or not slider.is_visible_in_tree():
					continue
				leaf_slider_count += 1
				verified_sliders[str(slider.name)] = true
				var raw_rect := slider.get_global_rect()
				if not _rect_is_finite(raw_rect) or not raw_rect.has_area():
					failures.append("Fiscal slider '%s' has invalid geometry: %s." % [slider.get_path(), raw_rect])
					continue
				fiscal_scroll.ensure_control_visible(slider)
				await _settle(tree, 2)
				var effective_rect := _effective_visible_rect(tree, slider).intersection(fiscal_scroll.get_global_rect())
				if not effective_rect.has_area() or not _encloses_with_epsilon(effective_rect, slider.get_global_rect()):
					failures.append(
						"Fiscal slider '%s' cannot be fully scrolled into view: raw=%s effective=%s scroll=%s." % [
							slider.get_path(), slider.get_global_rect(), effective_rect, fiscal_scroll.get_global_rect(),
						]
					)
			if leaf_slider_count < 2 or leaf_slider_count > 3:
				failures.append("Fiscal category %d:%d exposes %d visible sliders; expected 2-3." % [category_index, subcategory_index, leaf_slider_count])
			if leaf_row_count != leaf_slider_count:
				failures.append(
					"Fiscal category %d:%d exposes %d rows for %d sliders." % [
						category_index,
						subcategory_index,
						leaf_row_count,
						leaf_slider_count,
					]
				)
	result["verified_slider_count"] = verified_sliders.size()
	var verified_slider_names: Array[String] = []
	verified_slider_names.assign(verified_sliders.keys())
	verified_slider_names.sort()
	result["verified_slider_names"] = verified_slider_names
	if verified_slider_names != expected_slider_names:
		failures.append(
			"Fiscal scroll traversal did not reach the authoritative slider set: actual=%s expected=%s." % [
				verified_slider_names,
				expected_slider_names,
			]
		)

	for snapshot in original_sub_tabs:
		var subcategories := snapshot.get("tabs") as TabContainer
		if subcategories != null and is_instance_valid(subcategories):
			subcategories.current_tab = int(snapshot.get("current", 0))
	fiscal_tabs.current_tab = original_root_tab
	fiscal_scroll.scroll_horizontal = original_scroll.x
	fiscal_scroll.scroll_vertical = original_scroll.y
	await _settle(tree, 3)
	result["scroll_restored"] = (
		absf(float(fiscal_scroll.scroll_horizontal - original_scroll.x)) <= GEOMETRY_EPSILON
		and absf(float(fiscal_scroll.scroll_vertical - original_scroll.y)) <= GEOMETRY_EPSILON
	)
	var tabs_restored := fiscal_tabs.current_tab == original_root_tab
	for snapshot in original_sub_tabs:
		var subcategories := snapshot.get("tabs") as TabContainer
		if subcategories != null and is_instance_valid(subcategories):
			tabs_restored = tabs_restored and subcategories.current_tab == int(snapshot.get("current", 0))
	result["tabs_restored"] = tabs_restored
	if not bool(result["scroll_restored"]):
		failures.append("Fiscal scroll position was not restored after traversal.")
	if not tabs_restored:
		failures.append("Fiscal category selection was not restored after traversal.")

	result["errors"] = failures
	result["ok"] = failures.is_empty()
	return result


static func _range_diagnostic(message: String, result: Dictionary) -> String:
	return "%s (actual=%.2f combined_min=%.2f viewport=%.2f range_page=%.2f max_scroll=%.2f mode=%d)." % [
		message,
		float(result.get("actual_content_height", 0.0)),
		float(result.get("combined_minimum_height", 0.0)),
		float(result.get("viewport_height", 0.0)),
		float(result.get("range_page", 0.0)),
		float(result.get("maximum_scroll", 0.0)),
		int(result.get("vertical_scroll_mode", -1)),
	]


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
	return (
		inner.position.x >= outer.position.x - GEOMETRY_EPSILON
		and inner.position.y >= outer.position.y - GEOMETRY_EPSILON
		and inner.end.x <= outer.end.x + GEOMETRY_EPSILON
		and inner.end.y <= outer.end.y + GEOMETRY_EPSILON
	)


static func _rect_is_finite(rect: Rect2) -> bool:
	return (
		is_finite(rect.position.x)
		and is_finite(rect.position.y)
		and is_finite(rect.size.x)
		and is_finite(rect.size.y)
	)


static func _settle(tree: SceneTree, frames: int) -> void:
	for _frame in range(frames):
		await tree.process_frame
