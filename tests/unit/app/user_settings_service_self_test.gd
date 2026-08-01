extends SceneTree

const UserSettingsService := preload("res://scripts/app/user_settings_service.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var settings_path := UserSettingsService.SETTINGS_PATH
	var absolute_path := ProjectSettings.globalize_path(settings_path)
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)
	var defaults: Dictionary = UserSettingsService.load_audio_preferences()
	_check(not bool(defaults.get("found", true)), "missing preferences report found=false")
	_check(bool(defaults.get("music_enabled", false)) and bool(defaults.get("sfx_enabled", false)), "missing preferences use enabled defaults")

	var config := ConfigFile.new()
	config.set_value("localization", "locale", "ja")
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	_check(directory_error == OK, "settings parent directory can be created")
	_check(config.save(settings_path) == OK, "localization fixture can be saved")
	var save_error: Error = UserSettingsService.save_audio_preferences({
		"music_enabled": false,
		"sfx_enabled": true,
		"music_volume": 0.34,
		"sfx_volume": 1.4,
	})
	_check(save_error == OK, "audio preferences save successfully")
	var loaded: Dictionary = UserSettingsService.load_audio_preferences()
	_check(bool(loaded.get("found", false)), "saved audio preferences report found=true")
	_check(not bool(loaded.get("music_enabled", true)) and bool(loaded.get("sfx_enabled", false)), "audio toggles round-trip")
	_check(is_equal_approx(float(loaded.get("music_volume", 0.0)), 0.34), "music volume round-trips")
	_check(is_equal_approx(float(loaded.get("sfx_volume", 0.0)), 1.0), "SFX volume clamps before persistence")
	config = ConfigFile.new()
	_check(config.load(settings_path) == OK and str(config.get_value("localization", "locale", "")) == "ja", "audio save preserves localization preferences")
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)
	if _failed:
		quit(1)
	else:
		print("User settings service self-test passed.")
		quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("User settings service self-test failed: %s" % message)
