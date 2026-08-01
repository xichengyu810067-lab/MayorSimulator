class_name MayorUserSettingsService
extends RefCounted

const SETTINGS_PATH := "user://mayor_simulator/settings.cfg"


static func load_audio_preferences() -> Dictionary:
	var defaults := {
		"found": false,
		"music_enabled": true,
		"sfx_enabled": true,
		"music_volume": 1.0,
		"sfx_volume": 1.0,
	}
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return defaults
	var keys := ["music_enabled", "sfx_enabled", "music_volume", "sfx_volume"]
	for key: String in keys:
		if config.has_section_key("audio", key):
			defaults["found"] = true
	defaults["music_enabled"] = bool(config.get_value("audio", "music_enabled", true))
	defaults["sfx_enabled"] = bool(config.get_value("audio", "sfx_enabled", true))
	defaults["music_volume"] = clampf(float(config.get_value("audio", "music_volume", 1.0)), 0.0, 1.0)
	defaults["sfx_volume"] = clampf(float(config.get_value("audio", "sfx_volume", 1.0)), 0.0, 1.0)
	return defaults


static func save_audio_preferences(state: Dictionary) -> Error:
	var absolute_path := ProjectSettings.globalize_path(SETTINGS_PATH)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK:
		return directory_error
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("audio", "music_enabled", bool(state.get("music_enabled", true)))
	config.set_value("audio", "sfx_enabled", bool(state.get("sfx_enabled", true)))
	config.set_value("audio", "music_volume", clampf(float(state.get("music_volume", 1.0)), 0.0, 1.0))
	config.set_value("audio", "sfx_volume", clampf(float(state.get("sfx_volume", 1.0)), 0.0, 1.0))
	return config.save(SETTINGS_PATH)
