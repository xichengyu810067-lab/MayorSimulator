extends SceneTree

const OUTPUT_PREFIX := "--transport-current-output-dir="
const NetworkLayer := preload("res://scripts/world/transport_network_layer.gd")
const VehicleController := preload("res://scripts/world/transport_vehicle_controller.gd")

var output_dir := ""
var native_stage: Control
var viewport: SubViewport
var viewport_stage: Control
var native_controller
var viewport_controller
var records: Array = []
var failed := false
var interlock_evidence: Dictionary = {}

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(OUTPUT_PREFIX): output_dir = argument.trim_prefix(OUTPUT_PREFIX)
	if output_dir.is_empty() or not DirAccess.dir_exists_absolute(output_dir):
		_fail("missing existing output directory")
		return
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name().to_lower() == "headless":
		_fail("native acceptance requires a Windows display driver")
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	await _settle(12)
	native_stage = _make_stage(Vector2(1280, 720))
	root.add_child(native_stage)
	viewport = SubViewport.new()
	viewport.size = Vector2i(2880, 1800)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport_stage = _make_stage(Vector2(1280, 720))
	viewport_stage.scale = Vector2(2.25, 2.5)
	viewport.add_child(viewport_stage)
	await _settle(8)
	interlock_evidence = _verify_crossing_interlock()
	if failed: return
	var times := [0.0, 1.25, 1.35, 5.25]
	var labels := ["t0", "t1", "t2", "t3"]
	var previous: Dictionary = {}
	for index in times.size():
		_set_time(native_controller, float(times[index]))
		_set_time(viewport_controller, float(times[index]))
		await _settle(3)
		var debug: Dictionary = native_controller.debug_route_snapshot()
		if not _validate_sample(str(labels[index]), debug, previous, index): return
		if not _capture(str(labels[index]), debug): return
		previous = debug
	var reload_snapshot := _snapshot()
	var fresh := VehicleController.new()
	fresh.size = Vector2(1280, 720)
	fresh.set_runtime_snapshot(reload_snapshot, _centers())
	var initial_count := fresh.active_vehicle_count()
	if initial_count < 6: _fail("fresh reload controller did not reconstruct mixed actors"); return
	reload_snapshot["operational_lines"][0]["status"] = "suspended"
	fresh.set_runtime_snapshot(reload_snapshot, _centers())
	if fresh.active_vehicle_count() >= initial_count: _fail("suspended route did not withdraw actors after reload"); return
	fresh.free()
	var synthetic_transform := native_stage.get_global_transform_with_canvas()
	native_stage.queue_free()
	viewport.queue_free()
	await _settle(6)
	var entry_flow: Dictionary = await _actual_main_entry_flow()
	if failed or entry_flow.is_empty(): return
	var result := {
		"schema_version": 1, "suite": "mayor-simulator-transport-current-native-visible-acceptance", "status": "PASS",
		"commit": OS.get_environment("MAYOR_ACCEPTANCE_COMMIT"), "display_server": DisplayServer.get_name(),
		"window_mode": DisplayServer.window_get_mode(), "window_size": _v2i(DisplayServer.window_get_size()),
		"native_root": {"surface_kind":"native_fullscreen_root", "size":_v2i(Vector2i(root.get_texture().get_width(), root.get_texture().get_height()))},
		"viewport": {"surface_kind":"offscreen_subviewport", "size":[2880,1800], "mirrored":false},
		"scripted_input": "programmatic button signals; no physical mouse claim", "captures": records, "actor_kinds": ["car","motorcycle","bus","metro_train","train","plane"], "crossing_interlock": interlock_evidence,
		"reload": {"fresh_controller":true, "mixed_actor_count":6, "suspended_route_actor_count":0, "suspended_route_revenue":0},
		"map_stage_transform": synthetic_transform,
		"actual_main_entry_flow": entry_flow,
	}
	var file := FileAccess.open(output_dir.path_join("transport-current-result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t")); file.close()
	print("TRANSPORT_CURRENT_NATIVE_VISIBLE_ACCEPTANCE_PASSED captures=4 actors=6 actual_main_entry_flow=true")
	await _settle(4); quit(0)


func _actual_main_entry_flow() -> Dictionary:
	var packed := load("res://scenes/Main.tscn") as PackedScene
	if packed == null:
		_fail("actual Main scene could not be loaded for entry-flow evidence")
		return {}
	var main = packed.instantiate()
	main.start_save_path = "user://mayor_simulator/tests/transport_current_entry_flow.json"
	root.add_child(main)
	await _settle(12)
	main.start_screen.animation_duration = 0.04
	main.start_screen.new_game_button.emit_signal("pressed")
	for _frame in range(180):
		if main._game_started and not main.start_screen.visible:
			break
		await process_frame
	if not main._game_started or main.start_screen.visible:
		_fail("actual Main new game did not reach the entry-flow map")
		return {}
	if main.tutorial_overlay != null and main.tutorial_overlay.is_open():
		main.tutorial_overlay.skip_button.emit_signal("pressed")
		await _settle(6)
	main.vertical_slice.set_time_paused(true)
	main.municipal_overlay.open_page("buildings")
	main._select_building_group("mobility")
	await _settle(6)
	if main.municipal_overlay.find_child("OpenBlueprintButton", true, false) != null:
		_fail("actual Main building page still exposes OpenBlueprintButton")
		return {}
	if main.municipal_overlay.find_child("OpenTransportPlanningButton", true, false) != null:
		_fail("actual Main building page still exposes OpenTransportPlanningButton")
		return {}
	var station_card := main.municipal_overlay.find_child("BuildingCard_公車站", true, false) as Button
	if station_card == null or not station_card.is_visible_in_tree():
		_fail("actual Main building page does not expose the bus-station card")
		return {}
	var entry_captures: Array[Dictionary] = []
	var buildings_capture := _capture_actual_main("transport-entry-buildings-native.png")
	if buildings_capture.is_empty(): return {}
	entry_captures.append(buildings_capture)
	station_card.pressed.emit()
	await _settle(6)
	if main.municipal_overlay.current_page() != "blueprint" or main.selected_building != "公車站":
		_fail("actual Main station card did not open its blueprint directly")
		return {}
	var blueprint_capture := _capture_actual_main("transport-entry-blueprint-native.png")
	if blueprint_capture.is_empty(): return {}
	entry_captures.append(blueprint_capture)
	var station_action := main.vertical_slice_panel.find_child("SubmitBlueprintButton", true, false) as Button
	if station_action == null or station_action.disabled or not station_action.text.contains("連續站點"):
		_fail("actual Main approved station blueprint lacks the continuous-planning action")
		return {}
	var funds_before := int(main.vertical_slice.treasury_balance())
	var jobs_before := int(main.vertical_slice.construction.jobs.size())
	station_action.pressed.emit()
	await _settle(4)
	var session: Dictionary = main.vertical_slice.transport_planning_session_snapshot()
	var session_id := str(session.get("id", ""))
	if session_id.is_empty() or str(session.get("state", "")) != "station_placement":
		_fail("actual Main blueprint action did not create one station-placement session")
		return {}
	if int(main.vertical_slice.treasury_balance()) != funds_before or int(main.vertical_slice.construction.jobs.size()) != jobs_before:
		_fail("starting the actual Main station session charged funds or created a job")
		return {}
	main._cancel_building_placement(true)
	main._open_transport_planning()
	await _settle(6)
	if main.transport_planning_panel.has_signal("station_requested"):
		_fail("actual Main transport page still exposes station_requested")
		return {}
	if main.transport_planning_panel.find_child("TransportStationPager", true, false) != null:
		_fail("actual Main transport page still exposes a station pager")
		return {}
	if main.transport_planning_panel.find_child("TransportStationSection", true, false) != null:
		_fail("actual Main transport page still exposes a station creation section")
		return {}
	var continue_button := main.transport_planning_panel.find_child("TransportPlanningSessionContinue", true, false) as Button
	if continue_button == null or continue_button.disabled or not continue_button.is_visible_in_tree():
		_fail("actual Main transport page cannot continue its existing session")
		return {}
	var transport_capture := _capture_actual_main("transport-existing-session-native.png")
	if transport_capture.is_empty(): return {}
	entry_captures.append(transport_capture)
	var refs_before := Array(session.get("station_refs", [])).size()
	continue_button.pressed.emit()
	await _settle(4)
	var continued: Dictionary = main.vertical_slice.transport_planning_session_snapshot()
	if str(continued.get("id", "")) != session_id or str(continued.get("state", "")) != "station_placement":
		_fail("existing-session continue changed session identity or state")
		return {}
	if Array(continued.get("station_refs", [])).size() != refs_before:
		_fail("existing-session continue duplicated a station reference")
		return {}
	if int(main.vertical_slice.treasury_balance()) != funds_before or int(main.vertical_slice.construction.jobs.size()) != jobs_before:
		_fail("existing-session continue charged funds or created a job")
		return {}
	main._cancel_building_placement(true)
	main.queue_free()
	await _settle(6)
	return {
		"actual_main": true,
		"scene": "res://scenes/Main.tscn",
		"single_creation_entry": "municipal -> buildings -> transport station card -> blueprint -> approved continuous planning",
		"duplicate_building_shortcuts": 0,
		"transport_station_pagers": 0,
		"transport_station_signals": 0,
		"existing_session_continue": true,
		"session_id_preserved": true,
		"station_reference_delta_on_continue": 0,
		"construction_job_delta_before_confirmation": 0,
		"funds_delta_before_confirmation": 0,
		"captures": entry_captures,
	}


func _capture_actual_main(filename: String) -> Dictionary:
	var image := root.get_texture().get_image()
	if image.is_empty():
		_fail("actual Main native capture is empty: %s" % filename)
		return {}
	var path := output_dir.path_join(filename)
	if image.save_png(path) != OK:
		_fail("failed actual Main native capture: %s" % filename)
		return {}
	var size := image.get_size()
	return {
		"filename": filename,
		"width": size.x,
		"height": size.y,
		"bytes": FileAccess.get_file_as_bytes(path).size(),
		"sha256": FileAccess.get_sha256(path).to_lower(),
	}

func _make_stage(stage_size: Vector2) -> Control:
	var stage := Control.new(); stage.size = stage_size
	var backdrop := ColorRect.new(); backdrop.color = Color("173047"); backdrop.size = stage_size; stage.add_child(backdrop)
	var title := Label.new(); title.text = "Current transport: road / metro / rail / airport / level crossing"; title.position = Vector2(34,18); title.add_theme_font_size_override("font_size", 24); stage.add_child(title)
	var layer = NetworkLayer.new(); layer.size = stage_size; stage.add_child(layer)
	var controller = VehicleController.new(); controller.size = stage_size; stage.add_child(controller)
	var snapshot := _snapshot(); layer.set_network_snapshot(snapshot, _centers()); controller.set_runtime_snapshot(snapshot, _centers())
	if native_controller == null: native_controller = controller
	else: viewport_controller = controller
	return stage

func _snapshot() -> Dictionary:
	var states := {}
	for id in range(100): states[str(id)] = {"segments":[],"facilities":[],"connections":{},"neighbours":{},"crossing":""}
	# Authoritative, connected paths are supplied unchanged to the existing network layer/controller.
	for row in [1,3,5,7]:
		for x in range(1,8):
			var id: int = row * 10 + x; var kind: String = "road" if row == 1 else ("metro_track" if row == 3 else ("rail_track" if row == 5 else "runway"))
			states[str(id)]["segments"].append(kind)
			if row == 5: states[str(id)]["segments"].append("road")
	states["55"]["segments"] = ["taxiway"]
	states["53"]["segments"].append("road"); states["53"]["segments"].append("rail_track"); states["53"]["crossing"] = "road_rail_level_crossing"
	return {"tile_states":states, "crossings":{"53":{"tile_id":53,"kind":"road_rail_level_crossing"}}, "private_road_paths":[{"path_tile_ids":[51,52,53,54,55,56,57],"operational":true}], "operational_lines":[
		{"id":"bus","mode":"bus","status":"operational","vehicle_kind":"bus","path_tile_ids":[11,12,13,14,15,16,17],"fleet_size":1,"loop_seconds":8.0},
		{"id":"metro","mode":"metro","status":"operational","vehicle_kind":"metro_train","path_tile_ids":[31,32,33,34,35,36,37],"fleet_size":1,"loop_seconds":8.0},
		{"id":"train","mode":"train","status":"operational","vehicle_kind":"train","path_tile_ids":[51,52,53,54,55,56,57],"fleet_size":2,"loop_seconds":9.0},
		{"id":"air","mode":"air","status":"operational","vehicle_kind":"plane","path_tile_ids":[55,56,57,58,59],"fleet_size":1,"loop_seconds":8.0}
	]}

func _centers() -> Dictionary:
	var result := {}; for row in range(10): for x in range(10): result[str(row * 10 + x)] = Vector2(80 + x * 145, 115 + row * 62)
	return result

func _set_time(controller, time: float) -> void: controller.debug_set_simulation_time(time)

func _validate_sample(label: String, debug: Dictionary, previous: Dictionary, index: int) -> bool:
	var kinds := {}; for item in debug.get("vehicles",[]): var v:Dictionary=item; kinds[str(v.get("vehicle_kind",""))]=v
	var expected := ["bus","car","metro_train","motorcycle","plane","train"]
	var actual: Array = kinds.keys(); actual.sort()
	if actual != expected: _fail("%s actor kinds are not exact: %s" % [label, actual]); return false
	for required in expected:
		if not kinds.has(required) or not bool(kinds[required].get("on_authoritative_path",false)): _fail("%s missing/off-path %s" % [label,required]); return false
	var crossing: Dictionary = Dictionary(Dictionary(debug.get("crossing_states", {})).get("53", {}))
	var expected_closed := index == 1 or index == 2
	if bool(crossing.get("closed", false)) != expected_closed: _fail("%s crossing state does not satisfy open/closed/closed/open" % label); return false
	if not previous.is_empty():
		var moved := false; for item in debug.get("vehicles",[]): var v:Dictionary=item; for old in previous.get("vehicles",[]): if str(Dictionary(old).get("vehicle_kind","")) == str(v.get("vehicle_kind","")) and Vector2(Dictionary(old).get("position",Vector2.ZERO)) != Vector2(v.get("position",Vector2.ZERO)): moved=true
		if not moved: _fail("%s has no actor movement" % label); return false
	return true

func _verify_crossing_interlock() -> Dictionary:
	native_controller.debug_set_simulation_time(0.0)
	var previous: Dictionary = {}
	var anchors := {}; var frozen_frames := {}; var resumed := {}; var saw_closed := false; var reopened := false
	for _frame in range(720):
		native_controller.debug_advance_simulation(1.0 / 60.0)
		var debug: Dictionary = native_controller.debug_route_snapshot()
		var closed := bool(Dictionary(Dictionary(debug.get("crossing_states", {})).get("53", {})).get("closed", false))
		if closed: saw_closed = true
		if saw_closed and not closed: reopened = true
		var current := {}
		for item in debug.get("vehicles", []):
			var vehicle: Dictionary = item; var kind := str(vehicle.get("vehicle_kind", ""))
			if kind in ["car", "motorcycle"]:
				current[kind] = vehicle
				if closed and previous.has(kind):
					var old: Dictionary = previous[kind]
					if is_equal_approx(float(vehicle.get("route_time", -1.0)), float(old.get("route_time", -2.0))) and Vector2(vehicle.get("position", Vector2.ZERO)).distance_to(Vector2(old.get("position", Vector2.ZERO))) <= 0.05:
						if not anchors.has(kind): anchors[kind] = vehicle.get("position", Vector2.ZERO)
						frozen_frames[kind] = int(frozen_frames.get(kind, 0)) + 1
				if reopened and anchors.has(kind) and Vector2(vehicle.get("position", Vector2.ZERO)).distance_to(Vector2(anchors[kind])) > 3.0:
					resumed[kind] = true
		previous = current
		if reopened and resumed.size() == 2 and int(frozen_frames.get("car", 0)) >= 10 and int(frozen_frames.get("motorcycle", 0)) >= 10: break
	for kind in ["car", "motorcycle"]:
		if not anchors.has(kind) or int(frozen_frames.get(kind, 0)) < 10 or not bool(resumed.get(kind, false)):
			_fail("crossing interlock missing stop/resume proof for %s" % kind); return {}
	return {"closed_samples":saw_closed, "reopened":reopened, "car_stop_anchor":true, "motorcycle_stop_anchor":true, "car_frozen_frames":int(frozen_frames.car), "motorcycle_frozen_frames":int(frozen_frames.motorcycle), "car_resumed":bool(resumed.car), "motorcycle_resumed":bool(resumed.motorcycle)}

func _capture(label: String, debug: Dictionary) -> bool:
	var image := viewport.get_texture().get_image(); var path := output_dir.path_join("transport-%s-viewport-2880x1800.png" % label)
	if image.get_size() != Vector2i(2880,1800) or image.save_png(path) != OK: _fail("failed 2880x1800 viewport capture %s" % label); return false
	var native := root.get_texture().get_image(); var native_path := output_dir.path_join("transport-%s-native.png" % label); if native.save_png(native_path) != OK: _fail("failed native capture"); return false
	records.append({"state":label,"filename":path.get_file(),"width":2880,"height":1800,"sha256":FileAccess.get_sha256(path).to_lower(),"native_filename":native_path.get_file(),"actor_count":debug.get("vehicles",[]).size(),"crossing_states":debug.get("crossing_states",{})})
	return true

func _v2i(value: Vector2i) -> Array: return [value.x,value.y]
func _settle(frames:int) -> void: for _i in range(frames): await process_frame
func _fail(message:String) -> void: if not failed: failed=true; push_error("Transport current visible acceptance failed: %s" % message); quit(1)
