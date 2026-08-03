extends SceneTree

const OUTPUT_PATH := "res://.tmp/transport-vehicle-gallery.png"
const VehicleControllerScript := preload("res://scripts/world/transport_vehicle_controller.gd")


func _initialize() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	call_deferred("_capture")


func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Transport vehicle gallery requires a visible display driver")
		quit(1)
		return
	var stage := Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(stage)
	var background := ColorRect.new()
	background.color = Color("#dce9d2")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(background)
	_add_title(stage)
	var controller = VehicleControllerScript.new()
	stage.add_child(controller)
	await process_frame
	var centers := _build_centers(stage)
	controller.move_to_front()
	var snapshot := _build_snapshot()
	controller.set_runtime_snapshot(snapshot, centers)
	controller.debug_set_simulation_time(2.75)
	for _frame in range(12):
		await process_frame
	var debug: Dictionary = controller.debug_route_snapshot()
	var kinds: Array[String] = []
	for vehicle_variant: Variant in debug.get("vehicles", []):
		var vehicle: Dictionary = vehicle_variant
		var kind := str(vehicle.get("vehicle_kind", ""))
		if kind not in kinds:
			kinds.append(kind)
		if not bool(vehicle.get("uses_authored_sprite", false)):
			push_error("Transport gallery rejected procedural fallback for %s" % kind)
			quit(1)
			return
	kinds.sort()
	var required := ["bus", "car", "metro_train", "motorcycle", "plane", "train"]
	if kinds != required:
		push_error("Transport gallery coverage mismatch: %s" % [kinds])
		quit(1)
		return
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.get_width() < 1280 or image.get_height() < 720:
		push_error("Transport gallery returned an invalid viewport image: %s" % [image.get_size() if image != null else Vector2i.ZERO])
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.tmp"))
	var save_error := image.save_png(OUTPUT_PATH)
	if save_error != OK:
		push_error("Transport gallery save failed: %s" % error_string(save_error))
		quit(1)
		return
	print("TRANSPORT_VEHICLE_GALLERY_PASSED kinds=%s size=%s path=%s" % [kinds, image.get_size(), OUTPUT_PATH])
	quit(0)


func _add_title(stage: Control) -> void:
	var title := Label.new()
	title.text = "交通載具動態視覺驗收"
	title.position = Vector2(64, 28)
	title.add_theme_font_size_override("font_size", 30)
	stage.add_child(title)
	var labels := ["公車／道路", "地鐵／軌道", "火車／鐵路", "飛機／跑道", "汽車與機車／道路"]
	for index in labels.size():
		var label := Label.new()
		label.text = labels[index]
		label.position = Vector2(64, 116 + index * 112)
		label.add_theme_font_size_override("font_size", 20)
		stage.add_child(label)


func _build_centers(stage: Control) -> Dictionary:
	var centers := {}
	for row in 5:
		var y := 140.0 + row * 112.0
		var road := ColorRect.new()
		road.color = Color("#79827a") if row in [0, 4] else Color("#89969a")
		road.position = Vector2(250, y - 14)
		road.size = Vector2(890, 28)
		stage.add_child(road)
		for column in 4:
			var tile_id := row * 10 + column
			centers[str(tile_id)] = Vector2(320 + column * 250, y)
	return centers


func _build_snapshot() -> Dictionary:
	var lines: Array[Dictionary] = []
	var modes := [
		["bus", "bus", 0],
		["metro", "metro_train", 10],
		["train", "train", 20],
		["air", "plane", 30],
	]
	for index in modes.size():
		var mode_spec: Array = modes[index]
		var first := int(mode_spec[2])
		lines.append({
			"id": "gallery_%s" % mode_spec[0],
			"mode": mode_spec[0],
			"vehicle_kind": mode_spec[1],
			"status": "operational",
			"path_tile_ids": [first, first + 1, first + 2, first + 3],
			"fleet_size": 1,
			"loop_seconds": 10.0 + index,
		})
	return {
		"operational_lines": lines,
		"private_road_paths": [{
			"path_tile_ids": [40, 41, 42, 43],
			"operational": true,
		}],
		"crossings": {},
	}
