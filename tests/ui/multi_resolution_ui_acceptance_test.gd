extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(2880, 1800),
]
const MUNICIPAL_PAGES: PackedStringArray = [
	"buildings",
	"governance",
	"judicial",
	"oversight",
	"blueprint",
	"finance",
	"public_affairs",
	"city_data",
	"report",
]
const GEOMETRY_EPSILON := 1.5
const MIN_INTERACTIVE_EXTENT := 44.0
const MIN_LONG_LABEL_LENGTH := 20
const SCROLL_POSITION_EPSILON := 1.0
const INFORMATIONAL_PAGE_IDS := ["city_data", "report"]

var _failed := false
var _check_count := 0
var _surface_count := 0
var _interactive_count := 0
var _scroll_container_count := 0
var _scroll_move_count := 0
var _combined_minimum_gap_count := 0
var _maximum_combined_minimum_gap := 0.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_main := load("res://scenes/Main.tscn") as PackedScene
	_check(packed_main != null, "Main scene can be loaded")
	if packed_main == null:
		await TestCleanup.finish(self, [], 1)
		return

	for resolution in RESOLUTIONS:
		root.content_scale_size = resolution
		root.size = resolution
		await _settle(3)

		var main := packed_main.instantiate()
		root.add_child(main)
		await _settle(5)
		await _validate_resolution(main, resolution)
		await TestCleanup.release_fixtures(self, [main])

	var exit_code := 1 if _failed else 0
	if _failed:
		print(
			"MULTI_RESOLUTION_UI_ACCEPTANCE_FAILED resolutions=%d municipal_pages=%d surfaces=%d interactives=%d scroll_containers=%d scroll_moves=%d combined_minimum_gaps=%d max_combined_minimum_gap=%.2f checks=%d"
			% [RESOLUTIONS.size(), MUNICIPAL_PAGES.size(), _surface_count, _interactive_count, _scroll_container_count, _scroll_move_count, _combined_minimum_gap_count, _maximum_combined_minimum_gap, _check_count]
		)
	else:
		print(
			"MULTI_RESOLUTION_UI_ACCEPTANCE_PASSED resolutions=%d municipal_pages=%d surfaces=%d interactives=%d scroll_containers=%d scroll_moves=%d combined_minimum_gaps=%d max_combined_minimum_gap=%.2f checks=%d"
			% [RESOLUTIONS.size(), MUNICIPAL_PAGES.size(), _surface_count, _interactive_count, _scroll_container_count, _scroll_move_count, _combined_minimum_gap_count, _maximum_combined_minimum_gap, _check_count]
		)
	await TestCleanup.finish(self, [], exit_code)


func _validate_resolution(main: Control, expected_resolution: Vector2i) -> void:
	var viewport_rect := _viewport_rect()
	_check(
		Vector2i(roundi(viewport_rect.size.x), roundi(viewport_rect.size.y)) == expected_resolution,
		"%s exposes the requested logical viewport" % expected_resolution
	)
	_validate_required_surface(main, viewport_rect, "Main@%s" % expected_resolution)

	var start_screen := main.get("start_screen") as Control
	_check(start_screen != null and start_screen.is_visible_in_tree(), "%s start screen is visible" % expected_resolution)
	if start_screen != null:
		_validate_required_surface(start_screen, viewport_rect, "StartScreen@%s" % expected_resolution)
		var start_card := start_screen.find_child("StartMenuCard", true, false) as Control
		_validate_required_surface(start_card, viewport_rect, "StartMenuCard@%s" % expected_resolution)
		_validate_controls_inside(
			start_card,
			[main.start_screen.new_game_button, main.start_screen.continue_game_button],
			"start actions@%s" % expected_resolution
		)
		_validate_non_overlapping_controls(
			[main.start_screen.new_game_button, main.start_screen.continue_game_button],
			"start actions@%s" % expected_resolution
		)
		_validate_interactive_target(main.start_screen.language_selector, "start language selector@%s" % expected_resolution)
		_validate_visible_control_tree(start_screen, viewport_rect, "StartScreen@%s" % expected_resolution)
		start_screen.hide()
	await _settle(2)

	_validate_required_surface(main.status_hud, viewport_rect, "StatusHud@%s" % expected_resolution)
	_validate_required_surface(main.action_dock, viewport_rect, "ActionDock@%s" % expected_resolution)
	_validate_non_overlapping_controls(
		[main.status_hud, main.action_dock],
		"persistent HUD surfaces@%s" % expected_resolution
	)

	main.settings_overlay.open()
	await _settle(2)
	_validate_modal(main.settings_overlay, "SettingsOverlay", expected_resolution)
	var settings_panel := main.settings_overlay.find_child("SettingsPanel", true, false) as Control
	_validate_required_surface(settings_panel, viewport_rect, "SettingsPanel@%s" % expected_resolution)
	_validate_controls_inside(
		settings_panel,
		[
			main.settings_overlay.close_button,
			main.settings_overlay.language_selector,
			main.settings_overlay.light_button,
			main.settings_overlay.dark_button,
			main.settings_overlay.music_button,
			main.settings_overlay.sfx_button,
			main.settings_overlay.tutorial_button,
		],
		"settings controls@%s" % expected_resolution
	)
	_validate_non_overlapping_controls(
		[main.settings_overlay.light_button, main.settings_overlay.dark_button],
		"theme actions@%s" % expected_resolution
	)
	_validate_non_overlapping_controls(
		[main.settings_overlay.music_button, main.settings_overlay.sfx_button],
		"audio actions@%s" % expected_resolution
	)
	_validate_interactive_target(main.settings_overlay.music_volume_slider, "music volume slider@%s" % expected_resolution)
	_validate_interactive_target(main.settings_overlay.sfx_volume_slider, "SFX volume slider@%s" % expected_resolution)
	main.settings_overlay.close()
	await _settle(1)

	var building_context = main.building_context_panel as Control
	_check(building_context != null, "building context panel exists@%s" % expected_resolution)
	if building_context != null:
		building_context.call("open_for", {}, viewport_rect.get_center(), viewport_rect.size)
		await _settle(1)
		var building_close := building_context.find_child("CloseBuildingContextButton", true, false) as BaseButton
		_validate_interactive_target(building_close, "building context close@%s" % expected_resolution)
		if building_close != null:
			building_close.emit_signal("pressed")
		await _settle(1)
		_check(not building_context.visible, "building context close button restores map input@%s" % expected_resolution)

	main.exit_confirmation.open()
	await _settle(2)
	_validate_modal(main.exit_confirmation, "ExitConfirmation", expected_resolution)
	_validate_non_overlapping_controls(
		[main.exit_confirmation.cancel_button, main.exit_confirmation.confirm_button],
		"exit actions@%s" % expected_resolution
	)
	main.exit_confirmation.close()
	await _settle(1)

	var municipal_button := main.find_child("MunicipalButton", true, false) as Button
	_check(municipal_button != null, "%s HUD MunicipalButton exists before municipal layout validation" % expected_resolution)
	if municipal_button == null:
		return
	municipal_button.pressed.emit()
	await _settle(2)
	var municipal_overlay := main.get("municipal_overlay") as Control
	_check(municipal_overlay != null and municipal_overlay.is_visible_in_tree(), "%s first municipal action creates the overlay" % expected_resolution)
	if municipal_overlay == null:
		return
	municipal_overlay.call("open_hub")
	await _settle(1)
	await _validate_municipal_surface(municipal_overlay, "hub", expected_resolution)
	for page_id in MUNICIPAL_PAGES:
		municipal_overlay.call("open_page", page_id)
		await _settle(2)
		_check(
			municipal_overlay.call("current_page") == page_id,
			"%s municipal page '%s' opens" % [expected_resolution, page_id]
		)
		await _validate_municipal_surface(municipal_overlay, page_id, expected_resolution)
	municipal_overlay.call("close_overlay")
	await _settle(1)


func _validate_modal(modal: Control, label: String, resolution: Vector2i) -> void:
	var viewport_rect := _viewport_rect()
	_check(modal != null and modal.is_visible_in_tree(), "%s@%s is visible" % [label, resolution])
	_validate_required_surface(modal, viewport_rect, "%s@%s" % [label, resolution])
	_validate_visible_control_tree(modal, viewport_rect, "%s@%s" % [label, resolution])


func _validate_municipal_surface(overlay: Control, page_id: String, resolution: Vector2i) -> void:
	var viewport_rect := _viewport_rect()
	var label := "Municipal[%s]@%s" % [page_id, resolution]
	_check(overlay != null and overlay.is_visible_in_tree(), "%s is visible" % label)
	_validate_required_surface(overlay, viewport_rect, label)

	var window := overlay.find_child("MunicipalWindow", true, false) as Control
	var page_host := overlay.find_child("PageHost", true, false) as Control
	var header_title := overlay.find_child("HeaderTitle", true, false) as Control
	var back_button := overlay.find_child("BackButton", true, false) as Control
	var close_button := overlay.find_child("CloseButton", true, false) as Control
	_validate_required_surface(window, viewport_rect, "%s window" % label)
	_validate_required_surface(page_host, window.get_global_rect() if window != null else viewport_rect, "%s page host" % label)
	_validate_controls_inside(window, [header_title, back_button, close_button], "%s header" % label)
	_validate_non_overlapping_controls([header_title, back_button, close_button], "%s header" % label)
	if page_id == "hub":
		var hub_debug: Dictionary = overlay.debug_hub_layout_state()
		_check(int(hub_debug.get("direct_card_count", 0)) == 7, "%s has seven direct destination cards" % label)
		_check(int(hub_debug.get("unique_destination_count", 0)) == 7, "%s destinations are unique" % label)
		_check(int(hub_debug.get("filler_count", -1)) == 0, "%s has no filler card" % label)
		_check(int(hub_debug.get("secondary_columns", 0)) == 2 and int(hub_debug.get("secondary_rows", 0)) == 3, "%s keeps its six-card 2x3 grid" % label)
		_check(float(hub_debug.get("minimum_target_extent", 0.0)) >= MIN_INTERACTIVE_EXTENT, "%s cards retain 44px targets" % label)
		_check(str(hub_debug.get("layout_mode", "")) == ("narrow" if resolution.x < 1400 else "wide"), "%s uses its expected responsive structure" % label)
	elif page_id == "buildings":
		for pager_variant in overlay.find_children("BuildingChoices_*", "VBoxContainer", true, false):
			var pager := pager_variant as VBoxContainer
			_check(int(pager.get("page_size")) == 6, "%s building pager favors six cards" % label)
			_check(bool(pager.get_meta("balanced_building_pager", false)), "%s building pager uses count-balanced rows" % label)
			_check(pager.has_method("debug_layout_state"), "%s building pager exposes inspectable geometry" % label)
			if pager.is_visible_in_tree() and pager.has_method("debug_layout_state"):
				var layout: Dictionary = pager.call("debug_layout_state")
				_check(int(layout.get("visible_count", 0)) <= 6, "%s visible building cards stay within six" % label)
				_check(Array(layout.get("row_counts", [])).size() <= 2, "%s building cards stay within two balanced rows" % label)

	var visible_page_count := 0
	if page_host != null:
		for child_variant in page_host.get_children():
			var child := child_variant as Control
			if child == null or not child.is_visible_in_tree():
				continue
			visible_page_count += 1
			# The active page surface itself must remain inside PageHost. Descendant
			# content may be larger only when a ScrollContainer exposes a verifiable
			# range and can bring every interactive control into its viewport.
			var page_host_rect := page_host.get_global_rect()
			var page_boundary := page_host_rect
			var active_page_label := "%s active page (PageHost=%s)" % [label, page_host_rect]
			_validate_required_surface(child, page_boundary, active_page_label)
			_validate_visible_control_tree(child, page_boundary, active_page_label)
			await _validate_page_operability(child, page_host_rect, active_page_label, page_id)
	_check(visible_page_count == 1, "%s exposes exactly one active page" % label)

	_validate_visible_control_tree(overlay, viewport_rect, label)
	_validate_container_button_siblings(overlay, label)


func _validate_required_surface(control: Control, outer_rect: Rect2, label: String) -> void:
	_surface_count += 1
	_check(control != null and is_instance_valid(control), "%s exists" % label)
	if control == null or not is_instance_valid(control):
		return
	var rect := control.get_global_rect()
	var node_path := str(control.get_path())
	_check(_rect_is_finite(rect), "%s node '%s' has finite geometry: %s" % [label, node_path, rect])
	_check(rect.size.x > GEOMETRY_EPSILON and rect.size.y > GEOMETRY_EPSILON, "%s node '%s' has a positive area: %s" % [label, node_path, rect])
	_check(_encloses_with_epsilon(outer_rect, rect), "%s node '%s' stays inside %s: %s" % [label, node_path, outer_rect, rect])


func _validate_visible_control_tree(surface: Control, viewport_rect: Rect2, label: String) -> void:
	if surface == null:
		return
	var controls: Array[Control] = [surface]
	for node_variant in surface.find_children("*", "Control", true, false):
		var control := node_variant as Control
		if control != null:
			controls.append(control)

	for control in controls:
		if not control.is_visible_in_tree():
			continue
		var rect := control.get_global_rect()
		var node_path := str(control.get_path())
		_check(_rect_is_finite(rect), "%s control '%s' has finite geometry" % [label, node_path])
		_check(rect.size.x >= 0.0 and rect.size.y >= 0.0, "%s control '%s' has no negative size: %s" % [label, node_path, rect])
		if rect.size.x <= GEOMETRY_EPSILON or rect.size.y <= GEOMETRY_EPSILON:
			continue
		if not _has_clipping_ancestor(control, surface):
			_check(
				_encloses_with_epsilon(viewport_rect, rect),
				"%s unclipped control '%s' stays inside the viewport: %s" % [label, node_path, rect]
			)


func _validate_page_operability(page: Control, page_host_rect: Rect2, label: String, page_id: String) -> void:
	var scroll_containers := _visible_scroll_containers(page)
	var initial_scroll_positions: Array[Dictionary] = []
	for scroll: ScrollContainer in scroll_containers:
		_scroll_container_count += 1
		initial_scroll_positions.append({
			"scroll": scroll,
			"horizontal": scroll.scroll_horizontal,
			"vertical": scroll.scroll_vertical,
		})
		_validate_scroll_range(scroll, label)
		await _exercise_scroll_range(scroll, label)

	var buttons := _visible_interactive_buttons(page)
	for button: BaseButton in buttons:
		_interactive_count += 1
		await _bring_button_into_view(button, page, page_host_rect, label)

	if page_id in INFORMATIONAL_PAGE_IDS:
		_check(buttons.is_empty(), "%s information page has no invented action button" % label)
		var long_label := _pick_long_label(page)
		_check(
			long_label != null,
			"%s includes a visible long content sentinel for scrollable-page checks" % label
		)
		if long_label != null:
			await _bring_label_into_view(long_label as Label, page, page_host_rect, label)

	# Page inspection must not mutate the player's scroll position. Restore both
	# axes after all range and per-control traversal, then verify the restoration.
	for snapshot_index in range(initial_scroll_positions.size() - 1, -1, -1):
		var snapshot: Dictionary = initial_scroll_positions[snapshot_index]
		var scroll := snapshot.get("scroll") as ScrollContainer
		if scroll == null or not is_instance_valid(scroll):
			continue
		scroll.scroll_horizontal = int(snapshot.get("horizontal", 0))
		scroll.scroll_vertical = int(snapshot.get("vertical", 0))
	await _settle(2)
	for snapshot in initial_scroll_positions:
		var scroll := snapshot.get("scroll") as ScrollContainer
		if scroll == null or not is_instance_valid(scroll):
			continue
		_check(
			absf(float(scroll.scroll_horizontal - int(snapshot.get("horizontal", 0)))) <= SCROLL_POSITION_EPSILON
			and absf(float(scroll.scroll_vertical - int(snapshot.get("vertical", 0)))) <= SCROLL_POSITION_EPSILON,
			"%s scroll '%s' restores its original position" % [label, scroll.get_path()]
		)


func _validate_scroll_range(scroll: ScrollContainer, label: String) -> void:
	var node_path := str(scroll.get_path())
	var rect := scroll.get_global_rect()
	_check(_rect_is_finite(rect), "%s scroll '%s' has finite geometry" % [label, node_path])
	_check(rect.size.x > GEOMETRY_EPSILON and rect.size.y > GEOMETRY_EPSILON, "%s scroll '%s' has positive viewport area" % [label, node_path])

	var vertical_bar := scroll.get_v_scroll_bar()
	_check(vertical_bar != null, "%s scroll '%s' exposes a vertical range" % [label, node_path])
	if vertical_bar == null:
		return
	var range_values := [vertical_bar.min_value, vertical_bar.max_value, vertical_bar.page, vertical_bar.value]
	var range_is_finite := true
	for value: float in range_values:
		range_is_finite = range_is_finite and is_finite(value)
	_check(range_is_finite, "%s scroll '%s' has finite range values" % [label, node_path])
	var maximum_scroll := maxf(0.0, vertical_bar.max_value - vertical_bar.page)
	_check(
		float(scroll.scroll_vertical) >= vertical_bar.min_value - SCROLL_POSITION_EPSILON
		and float(scroll.scroll_vertical) <= maximum_scroll + SCROLL_POSITION_EPSILON,
		"%s scroll '%s' position stays inside 0..%.2f" % [label, node_path, maximum_scroll]
	)

	var content_extent := 0.0
	var combined_minimum_extent := 0.0
	for child_variant in scroll.get_children():
		var child := child_variant as Control
		if child != null and child.is_visible_in_tree():
			content_extent = maxf(content_extent, child.size.y)
			combined_minimum_extent = maxf(combined_minimum_extent, child.get_combined_minimum_size().y)
	var combined_minimum_gap := maxf(0.0, combined_minimum_extent - content_extent)
	if combined_minimum_gap > GEOMETRY_EPSILON:
		_combined_minimum_gap_count += 1
		_maximum_combined_minimum_gap = maxf(_maximum_combined_minimum_gap, combined_minimum_gap)
	# Range.page can retain the content minimum when the bar is hidden; the
	# ScrollContainer's actual rect is the independent viewport geometry.
	var viewport_extent := rect.size.y
	var content_overflows := content_extent > viewport_extent + GEOMETRY_EPSILON
	if content_overflows:
		_check(
			scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED,
			"%s scroll '%s' enables vertical scrolling (actual=%.2f combined_min=%.2f viewport=%.2f range_page=%.2f range=%.2f)" % [label, node_path, content_extent, combined_minimum_extent, viewport_extent, vertical_bar.page, maximum_scroll]
		)
		_check(
			maximum_scroll > GEOMETRY_EPSILON,
			"%s scroll '%s' exposes a positive range for overflow (actual=%.2f combined_min=%.2f viewport=%.2f range_page=%.2f range=%.2f)" % [label, node_path, content_extent, combined_minimum_extent, viewport_extent, vertical_bar.page, maximum_scroll]
		)
	else:
		_check(
			maximum_scroll <= GEOMETRY_EPSILON,
			"%s scroll '%s' has no phantom range (actual=%.2f combined_min=%.2f viewport=%.2f range_page=%.2f range=%.2f)" % [label, node_path, content_extent, combined_minimum_extent, viewport_extent, vertical_bar.page, maximum_scroll]
		)


func _exercise_scroll_range(scroll: ScrollContainer, label: String) -> void:
	var vertical_bar := scroll.get_v_scroll_bar()
	if vertical_bar == null:
		return
	var maximum_scroll := maxf(0.0, vertical_bar.max_value - vertical_bar.page)
	if maximum_scroll <= GEOMETRY_EPSILON:
		return
	var original_vertical := scroll.scroll_vertical
	var content := _first_visible_control_child(scroll)
	scroll.scroll_vertical = 0
	await _settle(2)
	var content_top_y := content.get_global_rect().position.y if content != null else 0.0
	scroll.scroll_vertical = roundi(maximum_scroll)
	await _settle(2)
	_scroll_move_count += 1
	_check(
		absf(float(scroll.scroll_vertical) - maximum_scroll) <= SCROLL_POSITION_EPSILON,
		"%s scroll '%s' reaches the end of its declared range" % [label, scroll.get_path()]
	)
	if content != null:
		_check(
			content.get_global_rect().position.y < content_top_y - GEOMETRY_EPSILON,
			"%s scroll '%s' physically moves overflowing content" % [label, scroll.get_path()]
		)
	scroll.scroll_vertical = original_vertical
	await _settle(2)


func _bring_button_into_view(button: BaseButton, page: Control, page_host_rect: Rect2, label: String) -> void:
	var node_path := str(button.get_path())
	var raw_rect := button.get_global_rect()
	_check(_rect_is_finite(raw_rect), "%s interactive '%s' has finite geometry" % [label, node_path])
	_check(
		raw_rect.size.x > GEOMETRY_EPSILON and raw_rect.size.y > GEOMETRY_EPSILON,
		"%s interactive '%s' has positive raw area: %s" % [label, node_path, raw_rect]
	)
	_check(
		raw_rect.size.x + GEOMETRY_EPSILON >= MIN_INTERACTIVE_EXTENT
		and raw_rect.size.y + GEOMETRY_EPSILON >= MIN_INTERACTIVE_EXTENT,
		"%s interactive '%s' reaches the %.0fx%.0f minimum target: %s" % [label, node_path, MIN_INTERACTIVE_EXTENT, MIN_INTERACTIVE_EXTENT, raw_rect]
	)

	# Work from the innermost scroller outward. The final outer adjustment keeps
	# the already-positioned control visible through every nested viewport.
	for scroll: ScrollContainer in _scroll_ancestors(button, page):
		scroll.ensure_control_visible(button)
		await _settle(2)
		_scroll_move_count += 1

	var effective_rect := _effective_visible_rect(button).intersection(page_host_rect)
	_check(
		_rect_is_finite(effective_rect) and effective_rect.has_area(),
		"%s interactive '%s' can enter the effective viewport: %s" % [label, node_path, effective_rect]
	)
	_check(
		effective_rect.size.x + GEOMETRY_EPSILON >= MIN_INTERACTIVE_EXTENT
		and effective_rect.size.y + GEOMETRY_EPSILON >= MIN_INTERACTIVE_EXTENT,
		"%s interactive '%s' exposes at least %.0fx%.0f clickable pixels after scrolling: %s" % [label, node_path, MIN_INTERACTIVE_EXTENT, MIN_INTERACTIVE_EXTENT, effective_rect]
	)


func _validate_interactive_target(control: Control, label: String) -> void:
	_check(control != null and is_instance_valid(control), "%s exists" % label)
	if control == null or not is_instance_valid(control):
		return
	_check(
		control.custom_minimum_size.x >= MIN_INTERACTIVE_EXTENT and control.custom_minimum_size.y >= MIN_INTERACTIVE_EXTENT,
		"%s declares at least %.0fx%.0f logical pixels: %s" % [label, MIN_INTERACTIVE_EXTENT, MIN_INTERACTIVE_EXTENT, control.custom_minimum_size]
	)
	var rect := control.get_global_rect()
	_check(
		rect.size.x + GEOMETRY_EPSILON >= MIN_INTERACTIVE_EXTENT and rect.size.y + GEOMETRY_EPSILON >= MIN_INTERACTIVE_EXTENT,
		"%s receives at least %.0fx%.0f logical pixels after layout: %s" % [label, MIN_INTERACTIVE_EXTENT, MIN_INTERACTIVE_EXTENT, rect]
	)


func _pick_long_label(page: Control) -> Label:
	if page == null:
		return null
	var selected: Label
	var selected_length := -1
	for node_variant in page.find_children("*", "Label", true, false):
		var label := node_variant as Label
		if label == null or not label.is_visible_in_tree():
			continue
		var current_length := str(label.text).length()
		if current_length > selected_length:
			selected = label
			selected_length = current_length
	if selected != null and selected_length >= MIN_LONG_LABEL_LENGTH:
		return selected
	return null


func _bring_label_into_view(label: Label, page: Control, page_host_rect: Rect2, context: String) -> void:
	var node_path := str(label.get_path())
	var raw_rect := label.get_global_rect()
	var needs_vertical_reveal := (
		raw_rect.position.y < page_host_rect.position.y - GEOMETRY_EPSILON
		or raw_rect.end.y > page_host_rect.end.y + GEOMETRY_EPSILON
	)
	var vertical_reveal_observed := false
	_check(
		_rect_is_finite(raw_rect),
		"%s label '%s' has finite geometry: %s" % [context, node_path, raw_rect]
	)
	_check(
		raw_rect.size.x > 0.0 and raw_rect.size.y > 0.0,
		"%s label '%s' has positive geometry: %s" % [context, node_path, raw_rect]
	)
	_check(
		not label.clip_text,
		"%s label '%s' keeps copy fully readable (no clip): %s" % [context, node_path, label.text]
	)
	for scroll: ScrollContainer in _scroll_ancestors(label, page):
		_check(
			scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
			"%s long label '%s' forbids horizontal scrolling" % [context, node_path]
		)
		_check(
			scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED,
			"%s long label '%s' permits vertical reveal" % [context, node_path]
		)
		var vertical_before := scroll.scroll_vertical
		scroll.ensure_control_visible(label)
		await _settle(2)
		_scroll_move_count += 1
		vertical_reveal_observed = vertical_reveal_observed or absf(float(scroll.scroll_vertical - vertical_before)) > GEOMETRY_EPSILON
	var revealed_rect := label.get_global_rect()
	var host_intersection := revealed_rect.intersection(page_host_rect)
	_check(
		_rect_is_finite(revealed_rect)
		and host_intersection.size.x >= revealed_rect.size.x - GEOMETRY_EPSILON
		and host_intersection.size.y >= revealed_rect.size.y - GEOMETRY_EPSILON
		and host_intersection.has_area(),
		"%s long label '%s' is scrolled fully into the page host: host=%s rect=%s" % [context, node_path, page_host_rect, revealed_rect]
	)
	if needs_vertical_reveal:
		_check(vertical_reveal_observed, "%s long label '%s' is revealed by vertical scrolling" % [context, node_path])


func _visible_scroll_containers(page: Control) -> Array[ScrollContainer]:
	var result: Array[ScrollContainer] = []
	if page is ScrollContainer and page.is_visible_in_tree():
		result.append(page as ScrollContainer)
	for node_variant in page.find_children("*", "ScrollContainer", true, false):
		var scroll := node_variant as ScrollContainer
		if scroll != null and scroll.is_visible_in_tree():
			result.append(scroll)
	return result


func _visible_interactive_buttons(page: Control) -> Array[BaseButton]:
	var result: Array[BaseButton] = []
	if page is BaseButton and _is_interactive_button(page as BaseButton):
		result.append(page as BaseButton)
	for node_variant in page.find_children("*", "BaseButton", true, false):
		var button := node_variant as BaseButton
		if _is_interactive_button(button):
			result.append(button)
	return result


func _is_interactive_button(button: BaseButton) -> bool:
	return (
		button != null
		and button.is_visible_in_tree()
		and not button.disabled
		and button.mouse_filter != Control.MOUSE_FILTER_IGNORE
	)


func _scroll_ancestors(control: Control, boundary: Control) -> Array[ScrollContainer]:
	var result: Array[ScrollContainer] = []
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			result.append(ancestor as ScrollContainer)
		if ancestor == boundary:
			break
		ancestor = ancestor.get_parent()
	return result


func _first_visible_control_child(parent: Control) -> Control:
	for child_variant in parent.get_children():
		var child := child_variant as Control
		if child != null and child.is_visible_in_tree():
			return child
	return null


func _validate_controls_inside(outer: Control, controls: Array, label: String) -> void:
	_check(outer != null and is_instance_valid(outer), "%s container exists" % label)
	if outer == null or not is_instance_valid(outer):
		return
	var outer_rect := outer.get_global_rect()
	for control_variant in controls:
		var control := control_variant as Control
		_check(control != null and is_instance_valid(control), "%s control exists" % label)
		if control == null or not is_instance_valid(control) or not control.is_visible_in_tree():
			continue
		_check(
			_encloses_with_epsilon(outer_rect, control.get_global_rect()),
			"%s control '%s' stays inside its surface" % [label, control.name]
		)


func _validate_non_overlapping_controls(controls: Array, label: String) -> void:
	var visible_controls: Array[Control] = []
	for control_variant in controls:
		var control := control_variant as Control
		if control != null and is_instance_valid(control) and control.is_visible_in_tree():
			visible_controls.append(control)
	for first_index in range(visible_controls.size()):
		for second_index in range(first_index + 1, visible_controls.size()):
			var first := visible_controls[first_index]
			var second := visible_controls[second_index]
			_check(
				not _has_material_overlap(first.get_global_rect(), second.get_global_rect()),
				"%s controls '%s' and '%s' do not overlap" % [label, first.name, second.name]
			)


func _validate_container_button_siblings(surface: Control, label: String) -> void:
	var containers: Array[Container] = []
	if surface is Container:
		containers.append(surface as Container)
	for node_variant in surface.find_children("*", "Container", true, false):
		var container := node_variant as Container
		if container != null and container.is_visible_in_tree():
			containers.append(container)
	for container in containers:
		var buttons: Array[Control] = []
		for child_variant in container.get_children():
			var button := child_variant as BaseButton
			if button == null or not button.is_visible_in_tree():
				continue
			var effective_rect := _effective_visible_rect(button)
			if effective_rect.has_area():
				buttons.append(button)
			else:
				_check(
					_has_scroll_container_ancestor(button, surface),
					"%s/%s visible button '%s' has zero effective area outside scroll content" % [label, container.name, button.get_path()]
				)
		if buttons.size() > 1:
			_validate_non_overlapping_controls(buttons, "%s/%s button siblings" % [label, container.name])


func _effective_visible_rect(control: Control) -> Rect2:
	var visible_rect := control.get_global_rect().intersection(_viewport_rect())
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is Control and (ancestor as Control).clip_contents:
			visible_rect = visible_rect.intersection((ancestor as Control).get_global_rect())
		ancestor = ancestor.get_parent()
	return visible_rect


func _has_clipping_ancestor(control: Control, boundary: Control) -> bool:
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is Control and (ancestor as Control).clip_contents:
			return true
		if ancestor == boundary:
			break
		ancestor = ancestor.get_parent()
	return false


func _has_scroll_container_ancestor(control: Control, boundary: Control) -> bool:
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			return true
		if ancestor == boundary:
			break
		ancestor = ancestor.get_parent()
	return false


func _has_material_overlap(first: Rect2, second: Rect2) -> bool:
	var overlap := first.intersection(second)
	return overlap.size.x > GEOMETRY_EPSILON and overlap.size.y > GEOMETRY_EPSILON


func _encloses_with_epsilon(outer: Rect2, inner: Rect2) -> bool:
	return (
		inner.position.x >= outer.position.x - GEOMETRY_EPSILON
		and inner.position.y >= outer.position.y - GEOMETRY_EPSILON
		and inner.end.x <= outer.end.x + GEOMETRY_EPSILON
		and inner.end.y <= outer.end.y + GEOMETRY_EPSILON
	)


func _rect_is_finite(rect: Rect2) -> bool:
	return (
		is_finite(rect.position.x)
		and is_finite(rect.position.y)
		and is_finite(rect.size.x)
		and is_finite(rect.size.y)
	)


func _viewport_rect() -> Rect2:
	return Rect2(Vector2.ZERO, root.get_visible_rect().size)


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame


func _check(condition: bool, message: String) -> void:
	_check_count += 1
	if condition:
		return
	_failed = true
	push_error("Multi-resolution UI acceptance failed: %s" % message)
