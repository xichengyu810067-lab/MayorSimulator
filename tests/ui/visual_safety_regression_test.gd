extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const START_CARD_COLOR := Color(1.0, 0.96, 0.84, 0.96)
const TOAST_BACKGROUND := Color(0.04, 0.12, 0.19, 0.95)

var _failed := false
var _l10n: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1440, 900)
	root.size = Vector2i(1440, 900)
	_l10n = root.get_node_or_null("L10n")
	_check(_l10n != null, "localization service is available")
	var packed_main: PackedScene = load("res://scenes/Main.tscn")
	_check(packed_main != null, "main scene could not be loaded")
	if packed_main == null:
		await TestCleanup.finish(self, [], 1)
		return

	var main = packed_main.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.start_screen.hide()
	_check(main.municipal_overlay == null, "municipal overlay remains lazy before the first municipal action")
	var municipal_button := main.find_child("MunicipalButton", true, false) as Button
	_check(municipal_button != null, "HUD MunicipalButton exists before first municipal action")
	if municipal_button == null:
		await TestCleanup.finish(self, [main], 1)
		return
	municipal_button.pressed.emit()
	await _settle(4)
	var municipal_overlay := main.get("municipal_overlay") as Control
	_check(municipal_overlay != null and municipal_overlay.is_visible_in_tree(), "first municipal action creates and opens the overlay through the public HUD button")
	_check(municipal_overlay != null and municipal_overlay.call("current_page") == "hub", "municipal overlay opens on hub")
	if municipal_overlay == null:
		await TestCleanup.finish(self, [main], 1)
		return

	await _validate_fixed_municipal_tooltip(main)
	await _validate_companion_safe_margin(main)
	_validate_status_contrast(main)
	_validate_hud_placement_boundary(main)

	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Visual safety regression test passed.")
	await TestCleanup.finish(self, [main], exit_code)


func _validate_fixed_municipal_tooltip(main) -> void:
	main.municipal_overlay.open_hub()
	await process_frame
	var hub := main.municipal_overlay.find_child("MunicipalHubRoot", true, false) as Control
	var safe_label := hub.find_child("HubSafeTooltip", true, false) as Label if hub != null else null
	var button := main.municipal_overlay.find_child("GovernanceButton", true, false) as Button
	_check(safe_label != null and button != null, "municipal safe tooltip controls exist")
	if safe_label == null or button == null:
		return
	var default_text := safe_label.text
	button.mouse_entered.emit()
	_check(button.tooltip_text.is_empty(), "municipal card no longer spawns a floating tooltip over neighbouring text")
	_check(safe_label.text == str(_l10n.call("text", str(button.get_meta("semantic_description", "")))), "municipal description appears in the fixed safe row")
	button.mouse_exited.emit()
	_check(safe_label.text == default_text, "municipal fixed safe row restores its page instruction")


func _validate_companion_safe_margin(main) -> void:
	var window := main.municipal_overlay.find_child("MunicipalWindow", true, false) as Control
	_check(window != null, "municipal window exists")
	if window == null:
		return
	var right_gap := root.size.x - window.get_global_rect().end.x
	_check(right_gap >= 200.0, "municipal window reserves the lower-right companion safe area")
	main.municipal_overlay.open_page("public_affairs")
	await process_frame
	for button_variant in main.municipal_overlay.find_children("AcceptRequest_*", "Button", true, false):
		var button := button_variant as Button
		_check(window.get_global_rect().encloses(button.get_global_rect()), "citizen-affairs action remains inside the companion-safe municipal window")


func _validate_status_contrast(main) -> void:
	main.start_screen.set_continue_available(false)
	var missing_color: Color = main.start_screen.save_status_label.get_theme_color("font_color")
	_check(_contrast_ratio(missing_color, START_CARD_COLOR) >= 4.5, "missing-save text reaches 4.5:1 contrast on the start card")
	main.call("_set_hint", "施工提示", false)
	var success_color: Color = main.hint_label.get_theme_color("font_color")
	_check(_contrast_ratio(success_color, TOAST_BACKGROUND) >= 4.5, "construction success text reaches 4.5:1 contrast on the toast")
	_check(main.hint_label.get_theme_constant("outline_size") >= 2, "toast status text has a readable outline")


func _validate_hud_placement_boundary(main) -> void:
	var unsafe_index := -1
	var safe_index := -1
	for index in main.grid_buttons.size():
		if bool(main.call("_is_tile_inside_hud_safe_area", index)):
			if safe_index < 0:
				safe_index = index
		elif unsafe_index < 0:
			unsafe_index = index
	_check(unsafe_index >= 0, "at least one tile under the top HUD is excluded from placement")
	_check(safe_index >= 0, "the HUD boundary leaves usable construction tiles")
	if unsafe_index < 0:
		return
	main.placement_mode_active = true
	main.placement_building_name = "商店"
	main.call("_update_tile_visual", unsafe_index, "")
	var unsafe_tile = main.grid_buttons[unsafe_index]
	_check(not bool(unsafe_tile.get("placement_allowed")), "unsafe tile receives the blocked placement state")
	main.call("_on_grid_pressed", unsafe_index)
	_check(bool(main.placement_mode_active), "rejecting a HUD-covered tile keeps placement mode active")
	_check(int(main.get("_pending_construction_tile")) == -1, "HUD-covered tile never opens a construction quote")
	_check(main.hint_label.text == str(_l10n.call("text", "此地格位於頂部資訊列安全區內，請選擇下方空地。")), "HUD boundary explains why the tile is unavailable")


func _contrast_ratio(first: Color, second: Color) -> float:
	var first_luminance := _relative_luminance(first)
	var second_luminance := _relative_luminance(second)
	return (maxf(first_luminance, second_luminance) + 0.05) / (minf(first_luminance, second_luminance) + 0.05)


func _relative_luminance(color: Color) -> float:
	return 0.2126 * _linear_channel(color.r) + 0.7152 * _linear_channel(color.g) + 0.0722 * _linear_channel(color.b)


func _linear_channel(value: float) -> float:
	if value <= 0.04045:
		return value / 12.92
	return pow((value + 0.055) / 1.055, 2.4)


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Visual safety check failed: %s" % message)
