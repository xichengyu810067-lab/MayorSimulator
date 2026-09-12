extends SceneTree

const OUTPUT_JSON := "res://artifacts/playtests/building-blueprint-flow.json"
const OUTPUT_SCREENSHOT := "res://artifacts/screenshots/ui-tests/building-blueprint-flow-complete.png"
const MAX_REVIEW_DAYS := 10
const MAX_CONSTRUCTION_DAYS := 60


func _initialize() -> void:
	call_deferred("_run_flow")


func _run_flow() -> void:
	if DisplayServer.get_name().to_lower() == "headless":
		_fail("Playtest requires a visible display driver.")
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	await _settle(5)

	var packed_scene: PackedScene = load("res://scenes/Main.tscn")
	var scene := packed_scene.instantiate()
	root.add_child(scene)
	await _settle(5)
	scene.start_screen.animation_duration = 0.04
	if not _press(scene.start_screen.new_game_button, "new-game start action"):
		return
	for _frame in range(120):
		await process_frame
		if not scene.start_screen.is_loading():
			break
	if scene.start_screen.visible:
		_fail("New-game loading did not enter the playable city.")
		return
	var started_at := Time.get_ticks_msec()
	var navigation_actions := 0
	var configuration_actions := 0
	var review_day_advances := 0
	var construction_day_advances := 0

	var municipal_button := scene.get("municipal_button") as Button
	if not _press(municipal_button, "municipal HUD button"):
		return
	navigation_actions += 1
	await _settle()

	var overlay = scene.get("municipal_overlay")
	var buildings_button := overlay.find_child("BuildingsButton", true, false) as Button
	if not _press(buildings_button, "building hub card"):
		return
	navigation_actions += 1
	await _settle()

	var economy_filter := overlay.find_child("BuildingGroup_economy", true, false) as Button
	if not _press(economy_filter, "economy category filter"):
		return
	navigation_actions += 1
	await _settle()

	var shop_card := overlay.find_child("BuildingCard_商店", true, false) as Button
	if not _press(shop_card, "shop building card"):
		return
	navigation_actions += 1
	await _settle()
	if str(scene.get("selected_building")) != "商店":
		_fail("Building card did not select 商店.")
		return
	if overlay.find_child("OpenBlueprintButton", true, false) != null or overlay.find_child("OpenTransportPlanningButton", true, false) != null:
		_fail("Building page still exposes duplicate blueprint or transport shortcuts.")
		return
	if str(overlay.call("current_page")) != "blueprint":
		_fail("Building card did not open the blueprint page directly.")
		return

	var material := overlay.find_child("BlueprintMaterial", true, false) as OptionButton
	var size := overlay.find_child("BlueprintSize", true, false) as OptionButton
	var floors := overlay.find_child("BlueprintFloors", true, false) as SpinBox
	var workers := overlay.find_child("BlueprintWorkers", true, false) as SpinBox
	var decoration := overlay.find_child("BlueprintDecoration", true, false) as OptionButton
	if material == null or size == null or floors == null or workers == null or decoration == null:
		_fail("One or more blueprint parameter controls are missing.")
		return
	material.select_choice("brick")
	size.select_choice("medium")
	floors.value = 2
	workers.value = 5
	decoration.select_choice("flags")
	configuration_actions += 5
	await _settle()

	var submit := overlay.find_child("SubmitBlueprintButton", true, false) as Button
	if not _press(submit, "blueprint submit button"):
		return
	navigation_actions += 1
	await _settle()
	if scene.get("vertical_slice").construction.reviews.is_empty():
		_fail("Submitting the blueprint did not create a review.")
		return
	var review_status := overlay.find_child("BlueprintReviewStatus", true, false) as Label
	if review_status == null or not review_status.text.contains("已收件") or not review_status.text.contains("遊戲日"):
		_fail("Blueprint page did not show an immediate receipt and real-time estimate.")
		return
	if not submit.disabled or not submit.text.contains("審核中"):
		_fail("Blueprint submit button did not visibly lock while review is active.")
		return
	var review_count_before: int = int(scene.get("vertical_slice").construction.reviews.size())
	var duplicate: Dictionary = scene.get("vertical_slice").submit_blueprint({"building_name": "商店"})
	if bool(duplicate.get("ok", false)) or str(duplicate.get("error", "")) != "blueprint_already_under_review":
		_fail("Duplicate blueprint submission was not rejected during review.")
		return
	if scene.get("vertical_slice").construction.reviews.size() != review_count_before:
		_fail("Duplicate submission created an extra review record.")
		return

	var close_button := overlay.find_child("CloseButton", true, false) as Button
	if not _press(close_button, "close municipal overlay"):
		return
	navigation_actions += 1
	await _settle()

	while not bool(scene.call("_has_approved_blueprint_for_selected")) and review_day_advances < MAX_REVIEW_DAYS:
		scene.call("_next_day")
		review_day_advances += 1
		await _settle()
	if not bool(scene.call("_has_approved_blueprint_for_selected")):
		_fail("Blueprint was not approved within %d days." % MAX_REVIEW_DAYS)
		return

	if not _press(municipal_button, "municipal HUD button after approval"):
		return
	navigation_actions += 1
	await _settle()
	if not _press(buildings_button, "building hub card after approval"):
		return
	navigation_actions += 1
	await _settle()
	if not _press(economy_filter, "economy category filter after approval"):
		return
	navigation_actions += 1
	await _settle()
	if not _press(shop_card, "approved shop building card"):
		return
	navigation_actions += 1
	await _settle()
	if str(overlay.call("current_page")) != "blueprint":
		_fail("Approved building card did not reopen its blueprint directly.")
		return
	if submit.disabled or not submit.text.contains("放置"):
		_fail("Approved blueprint did not expose the placement action.")
		return
	if not _press(submit, "approved blueprint placement action"):
		return
	navigation_actions += 1
	await _settle()
	if not bool(scene.get("placement_mode_active")):
		_fail("Approved blueprint action did not enter placement mode.")
		return

	var city_grid: Array = scene.get("city_grid")
	var tile_index := -1
	for candidate_index in city_grid.size():
		if str(city_grid[candidate_index]).is_empty() and bool(scene.call("_is_tile_inside_hud_safe_area", candidate_index)):
			tile_index = candidate_index
			break
	if tile_index < 0:
		_fail("No HUD-safe empty map tile was available for construction.")
		return
	var grid_buttons: Array = scene.get("grid_buttons")
	var funds_before_quote := int(scene.get("funds"))
	if not _press(grid_buttons[tile_index] as Button, "empty map tile"):
		return
	navigation_actions += 1
	await _settle()
	var construction_confirmation = scene.get("construction_confirmation")
	if construction_confirmation == null or not construction_confirmation.is_open():
		_fail("Pressing an empty tile in placement mode did not open the cost confirmation.")
		return
	if not scene.get("vertical_slice").construction.jobs.is_empty():
		_fail("Construction started before the quoted total was confirmed.")
		return
	if int(scene.get("funds")) != funds_before_quote:
		_fail("Opening the construction quote changed treasury funds.")
		return
	var cancel_construction := construction_confirmation.find_child("CancelConstructionButton", true, false) as Button
	if not _press(cancel_construction, "construction quote cancel action"):
		return
	navigation_actions += 1
	await _settle()
	if not bool(scene.get("placement_mode_active")) or int(scene.get("funds")) != funds_before_quote:
		_fail("Cancelling the construction quote did not preserve placement and treasury state.")
		return
	if not _press(grid_buttons[tile_index] as Button, "empty map tile after quote cancellation"):
		return
	navigation_actions += 1
	await _settle()
	var confirm_construction := construction_confirmation.find_child("ConfirmConstructionButton", true, false) as Button
	if not _press(confirm_construction, "construction quote confirmation"):
		return
	navigation_actions += 1
	await _settle()
	if scene.get("vertical_slice").construction.jobs.is_empty():
		_fail("Confirming the quoted total did not start a construction job.")
		return
	if bool(scene.get("placement_mode_active")):
		_fail("Construction confirmation did not leave placement mode.")
		return
	if int(scene.get("funds")) >= funds_before_quote:
		_fail("Construction confirmation did not deduct the quoted total.")
		return

	while str((scene.get("city_grid") as Array)[tile_index]) != "商店" and construction_day_advances < MAX_CONSTRUCTION_DAYS:
		scene.call("_next_day")
		construction_day_advances += 1
		await _settle()
	if str((scene.get("city_grid") as Array)[tile_index]) != "商店":
		_fail("商店 construction did not complete within %d days." % MAX_CONSTRUCTION_DAYS)
		return

	await _settle(4)
	var screenshot_error := root.get_texture().get_image().save_png(OUTPUT_SCREENSHOT)
	if screenshot_error != OK:
		_fail("Could not save completion screenshot: %d" % screenshot_error)
		return

	var essential_actions := navigation_actions
	var total_actions := navigation_actions + configuration_actions + review_day_advances + construction_day_advances
	var result := {
		"result": "passed",
		"building": "商店",
		"tile_index": tile_index,
		"navigation_actions": navigation_actions,
		"configuration_actions": configuration_actions,
		"essential_actions_excluding_time_advance": essential_actions + configuration_actions,
		"review_day_advances": review_day_advances,
		"construction_day_advances": construction_day_advances,
		"total_ui_actions": total_actions,
		"elapsed_milliseconds": Time.get_ticks_msec() - started_at,
		"building_category_scrolls": 0,
		"blueprint_parameter_scrolls": 0,
		"completed_building_on_map": str((scene.get("city_grid") as Array)[tile_index])
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/playtests"))
	var file := FileAccess.open(OUTPUT_JSON, FileAccess.WRITE)
	if file == null:
		_fail("Could not write playtest evidence JSON.")
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("BUILDING_BLUEPRINT_PLAYTEST %s" % JSON.stringify(result))
	quit(0)


func _press(button: Button, label: String) -> bool:
	if button == null or not is_instance_valid(button):
		_fail("Missing UI control: %s." % label)
		return false
	if button.disabled:
		_fail("UI control is disabled: %s." % label)
		return false
	button.emit_signal("pressed")
	return true


func _settle(frames: int = 3) -> void:
	for _index in range(frames):
		await process_frame


func _fail(message: String) -> void:
	push_error("Building/blueprint playtest failed: %s" % message)
	quit(1)
