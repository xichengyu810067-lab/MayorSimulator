extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const UserSettingsService := preload("res://scripts/app/user_settings_service.gd")

var _failed := false
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var packed_main: PackedScene = load("res://scenes/Main.tscn")
	_check(packed_main != null, "Main scene could not be loaded")
	if packed_main == null:
		await TestCleanup.finish(self, [], 1)
		return

	var first = packed_main.instantiate()
	root.add_child(first)
	await process_frame
	await process_frame
	_check(first.settings_overlay.music_volume_slider != null, "settings omits the music volume slider")
	_check(first.settings_overlay.sfx_volume_slider != null, "settings omits the SFX volume slider")
	first.settings_overlay.music_volume_slider.value = 37.0
	first.settings_overlay.sfx_volume_slider.value = 62.0
	first.settings_overlay.music_button.button_pressed = false
	first.settings_overlay.sfx_button.button_pressed = false
	await process_frame
	_check(is_equal_approx(first.music_volume, 0.37), "Main did not receive music slider changes")
	_check(is_equal_approx(first.sfx_volume, 0.62), "Main did not receive SFX slider changes")
	var first_audio: Dictionary = first.audio_director.audio_state()
	_check(is_equal_approx(float(first_audio.get("music_volume", -1.0)), 0.37), "music gain did not reach AudioDirector")
	_check(is_equal_approx(float(first_audio.get("sfx_volume", -1.0)), 0.62), "SFX gain did not reach AudioDirector")
	_check(not bool(first_audio.get("music_enabled", true)) and not bool(first_audio.get("sfx_enabled", true)), "independent audio toggles did not reach AudioDirector")
	var stored: Dictionary = UserSettingsService.load_audio_preferences()
	_check(bool(stored.get("found", false)), "audio preferences were not persisted globally")
	_check(is_equal_approx(float(stored.get("music_volume", -1.0)), 0.37) and is_equal_approx(float(stored.get("sfx_volume", -1.0)), 0.62), "persisted audio volumes differ from the sliders")
	_check(not bool(stored.get("music_enabled", true)) and not bool(stored.get("sfx_enabled", true)), "persisted audio toggles differ from the controls")

	await TestCleanup.release_fixtures(self, [first])
	var second = packed_main.instantiate()
	root.add_child(second)
	await process_frame
	await process_frame
	_check(is_equal_approx(second.music_volume, 0.37) and is_equal_approx(second.sfx_volume, 0.62), "new Main instance did not restore global audio volumes")
	_check(not second.music_enabled and not second.sfx_enabled, "new Main instance did not restore global audio toggles")
	_check(is_equal_approx(second.settings_overlay.music_volume_slider.value, 37.0), "restored music value is not reflected in Settings")
	_check(is_equal_approx(second.settings_overlay.sfx_volume_slider.value, 62.0), "restored SFX value is not reflected in Settings")
	var music_bus := AudioServer.get_bus_index(&"Music")
	var sfx_bus := AudioServer.get_bus_index(&"SFX")
	_check(music_bus >= 0 and is_equal_approx(AudioServer.get_bus_volume_db(music_bus), linear_to_db(0.37)), "restored Music bus gain is incorrect")
	_check(sfx_bus >= 0 and is_equal_approx(AudioServer.get_bus_volume_db(sfx_bus), linear_to_db(0.62)), "restored SFX bus gain is incorrect")

	if _failed:
		await TestCleanup.finish(self, [second], 1)
	else:
		print("Audio settings integration test passed. Checks=%d" % _checks)
		await TestCleanup.finish(self, [second], 0)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Audio settings integration failed: %s" % message)
