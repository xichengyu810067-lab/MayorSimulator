extends SceneTree

const TutorialStoryOverlayScript = preload("res://ui/tutorial/tutorial_story_overlay.gd")
const AudioDirectorScript = preload("res://scripts/audio/audio_director.gd")
const ContentRegistry = preload("res://data/catalogs/content_registry.gd")
const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")

const AUDIO_PATHS := [
	"res://assets/audio/storybook_v1/mayors-dawn-loop.wav",
	"res://assets/audio/storybook_v1/ui-click.wav",
	"res://assets/audio/storybook_v1/page-turn.wav",
	"res://assets/audio/storybook_v1/success-chime.wav",
	"res://assets/audio/storybook_v1/construction-complete.wav",
	"res://assets/audio/storybook_v1/warning-soft.wav",
]

var _failed := false
var _completed_count := 0
var _page_turn_cue_count := 0
var _audio_tree_exited := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1440, 900)
	root.size = Vector2i(1440, 900)
	var overlay = TutorialStoryOverlayScript.new()
	overlay.completed.connect(func(_skipped: bool) -> void: _completed_count += 1)
	overlay.audio_cue.connect(func(cue: String) -> void:
		if cue == "page_turn":
			_page_turn_cue_count += 1
	)
	root.add_child(overlay)
	await process_frame
	_check(overlay.PAGES.size() == 6, "tutorial contains six focused story pages")
	_check(overlay.background_picture.texture != null, "tutorial background texture loads")
	if overlay.background_picture.texture != null:
		_check(overlay.background_picture.texture.get_width() == 2880, "story background uses the target width")
		_check(overlay.background_picture.texture.get_height() == 1800, "story background uses the target height")
	_check(overlay.next_button.custom_minimum_size.y >= 48.0, "tutorial next action has a readable click target")
	_check(overlay.skip_button.tooltip_text.contains("設定頁"), "tutorial explains how to replay after skipping")
	overlay.open(true)
	await process_frame
	_check(overlay.next_button.has_focus(), "tutorial gives keyboard focus to the next action")
	var dialogue_rect: Rect2 = overlay.story_panel.get_global_rect()
	_check(dialogue_rect.position.y >= 900.0 * 0.55, "tutorial uses a bottom dialogue strip instead of a tall side board")
	_check(dialogue_rect.size.x >= 1440.0 * 0.88, "tutorial dialogue strip spans the readable safe width")
	_check(dialogue_rect.size.y <= 900.0 * 0.38, "tutorial dialogue strip keeps most of the story artwork visible")
	_check(overlay.story_panel.find_child("TutorialSpeakerBadge", true, false) != null, "tutorial presents each page as a friendly speaker badge")
	_check(overlay.story_panel.find_child("TutorialDialogueFooter", true, false) != null, "tutorial keeps progress and actions in one compact footer")
	_check(overlay.next_button.get_global_rect().end.y <= dialogue_rect.end.y + 0.5, "tutorial actions stay inside the dialogue strip")
	var initial_left: float = overlay.background_picture.offset_left
	overlay.call("_process", 8.0)
	_check(not is_equal_approx(initial_left, overlay.background_picture.offset_left), "story background animates while visible")
	var first_title: String = overlay.title_label.text
	var accept_press := InputEventKey.new()
	accept_press.keycode = KEY_ENTER
	accept_press.pressed = true
	root.push_input(accept_press)
	await process_frame
	var accept_release := InputEventKey.new()
	accept_release.keycode = KEY_ENTER
	accept_release.pressed = false
	root.push_input(accept_release)
	await process_frame
	overlay._transition.custom_step(1.0)
	await process_frame
	_check(overlay.current_page == 1 and overlay.title_label.text != first_title, "one Enter key press advances exactly one tutorial page")
	_check(overlay.body_label.text.contains(str(ContentRegistry.BUILDING_IDS.size())), "tutorial building count follows the authoritative content registry")
	var localization = root.get_node_or_null("L10n")
	_check(localization != null, "tutorial count test can access the localization authority")
	if localization != null:
		for locale in localization.SUPPORTED_LOCALES:
			_check(bool(localization.set_locale(locale, false)), "tutorial supports locale %s" % locale)
			overlay.call("_apply_page_content")
			_check(overlay.body_label.text.contains(str(ContentRegistry.BUILDING_IDS.size())) and not overlay.body_label.text.contains("%d"), "tutorial renders the authoritative building count in %s" % locale)
		localization.set_locale(localization.SOURCE_LOCALE, false)
		overlay.call("_apply_page_content")
	_check(_page_turn_cue_count == 1, "one Enter key press emits exactly one page-turn cue")
	while overlay.current_page < overlay.PAGES.size() - 1:
		overlay.next_button.emit_signal("pressed")
		overlay._transition.custom_step(1.0)
		await process_frame
	_check(overlay.next_button.text == "進入城市", "final tutorial action clearly enters the city")
	overlay.next_button.emit_signal("pressed")
	overlay._transition.custom_step(1.0)
	await process_frame
	_check(not overlay.visible and _completed_count == 1, "finishing the tutorial closes it and emits completion once")

	var audio = AudioDirectorScript.new()
	root.add_child(audio)
	await process_frame
	_check(audio.music_player != null and audio.music_player.stream != null, "music player is initialized")
	_check(audio.music_player.stream.get_length() >= 23.9, "background music provides a 24 second loop")
	_check(audio.music_player.stream is AudioStreamWAV and audio.music_player.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "background music loops continuously")
	_check(audio.sfx_players.size() == 4, "sound effects use a small overlapping playback pool")
	_check(audio.music_player.bus == &"Music", "background music is routed through the Music bus")
	for player: AudioStreamPlayer in audio.sfx_players:
		_check(player.bus == &"SFX", "sound effects are routed through the SFX bus")
	audio.start_music()
	await process_frame
	_check(audio.music_player.playing, "city BGM starts before the cinematic claim")
	audio.begin_cinematic_music()
	_check(bool(audio.audio_state().get("cinematic_music_active", false)) and not audio.music_player.playing, "cinematic claim suppresses city BGM without changing the preference")
	var music_bus := AudioServer.get_bus_index(&"Music")
	audio.set_music_enabled(false)
	_check(AudioServer.is_bus_mute(music_bus) and not audio.music_player.playing, "music-off silences the cinematic Music bus without starting city BGM")
	audio.set_music_enabled(true)
	_check(not AudioServer.is_bus_mute(music_bus) and not audio.music_player.playing, "music-on restores film audio but keeps city BGM suppressed")
	audio.end_cinematic_music()
	await process_frame
	_check(not bool(audio.audio_state().get("cinematic_music_active", true)) and audio.music_player.playing, "releasing the cinematic claim resumes city BGM from the current preference")
	audio.set_music_volume(0.5)
	audio.set_sfx_volume(0.25)
	var sfx_bus := AudioServer.get_bus_index(&"SFX")
	_check(music_bus >= 0 and is_equal_approx(AudioServer.get_bus_volume_db(music_bus), linear_to_db(0.5)), "music bus applies the normalized user gain")
	_check(sfx_bus >= 0 and is_equal_approx(AudioServer.get_bus_volume_db(sfx_bus), linear_to_db(0.25)), "SFX bus applies the normalized user gain")
	audio.play_success()
	# Let the real playback complete before teardown.  Stopping a just-started WAV
	# in the same dummy-audio frame can leave AudioStreamPlaybackWAV referenced at
	# process exit even though the player node itself is freed correctly.
	await create_timer(1.0).timeout
	_check(is_equal_approx(AudioServer.get_bus_volume_db(sfx_bus), linear_to_db(0.25)), "cue playback preserves the user SFX gain")
	audio.set_sfx_volume(0.0)
	_check(AudioServer.is_bus_mute(sfx_bus), "zero SFX volume mutes the bus without losing cue balance")
	audio.set_sfx_volume(1.0)
	_check(not AudioServer.is_bus_mute(sfx_bus), "raising SFX volume unmutes its bus")
	for path in AUDIO_PATHS:
		_check(ResourceLoader.exists(path), "audio asset exists: %s" % path)
		var stream := load(path) as AudioStream
		_check(stream != null and stream.get_length() > 0.08, "audio asset is non-empty: %s" % path)
	audio.set_music_enabled(false)
	_check(not audio.music_enabled and not audio.music_player.playing, "music can be disabled independently")
	audio.set_sfx_enabled(false)
	_check(not audio.sfx_enabled, "sound effects can be disabled independently")
	audio.set_music_enabled(true)
	await process_frame
	_check(audio.music_player.playing, "music can resume before graceful shutdown")
	audio.tree_exited.connect(func() -> void: _audio_tree_exited = true)
	await audio.settle_for_shutdown(self)
	_check(not audio.music_player.playing, "graceful shutdown stops background music")
	_check(audio.music_player.stream == null, "graceful shutdown releases the music stream")
	for player: AudioStreamPlayer in audio.sfx_players:
		_check(player.stream == null, "graceful shutdown releases every SFX stream")
	audio.free()
	audio = null
	for _frame in range(AudioDirectorScript.SHUTDOWN_FREE_SETTLE_FRAMES):
		await process_frame
	_check(_audio_tree_exited, "audio director exits the scene tree before process shutdown")

	if _failed:
		await TestCleanup.finish(self, [overlay], 1)
	else:
		print("Tutorial animation and original audio test passed. Pages=6 AudioAssets=%d" % AUDIO_PATHS.size())
		await TestCleanup.finish(self, [overlay], 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Tutorial/audio check failed: %s" % message)
