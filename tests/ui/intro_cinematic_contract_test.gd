extends SceneTree

const IntroCinematicScript = preload("res://ui/tutorial/intro_cinematic.gd")
const StorySequence = preload("res://data/tutorial/story_sequence.gd")
const DECLINE_SUBTITLE := "賴依德的獨裁與貪腐，讓橋梁、商街與家庭逐漸失去依靠"
const DECLINE_TRANSLATIONS := {
	"zh_TW": "賴依德的獨裁與貪腐，讓橋梁、商街與家庭逐漸失去依靠",
	"zh_CN": "赖依德的独裁与贪腐，让桥梁、商街与家庭逐渐失去依靠",
	"en": "Mayor Laide's dictatorship and corruption left bridges, markets, and families without support.",
	"ja": "頼依德の独裁と腐敗が、橋、市場、そして家族の支えを奪っていった。",
	"ko": "라이더의 독재와 부패는 다리와 상가, 가정의 버팀목을 무너뜨렸다.",
}

var failed := false
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	_check(StorySequence.is_valid(), "story sequence remains valid for onboarding copy")
	_check(StorySequence.SHOTS.size() == 8, "story metadata retains eight chapters")
	_check(ResourceLoader.exists(IntroCinematicScript.FILM_PATH), "canonical opening film exists")
	var film_resource: Resource = load(IntroCinematicScript.FILM_PATH)
	_check(film_resource is VideoStream, "canonical opening film loads as VideoStream")

	var completed_states: Array[bool] = []
	var playback_started_count := [0]
	var playback_stopped_reasons: Array[String] = []
	var cinematic = IntroCinematicScript.new()
	root.add_child(cinematic)
	cinematic.completed.connect(func(skipped: bool) -> void: completed_states.append(skipped))
	cinematic.playback_started.connect(func() -> void: playback_started_count[0] += 1)
	cinematic.playback_stopped.connect(func(reason: String) -> void: playback_stopped_reasons.append(reason))
	await process_frame
	_check(cinematic.video_player is VideoStreamPlayer, "opening uses a VideoStreamPlayer")
	_check(cinematic.video_player.expand and not cinematic.video_player.loop and not cinematic.video_player.autoplay, "opening film covers the surface without looping or autoplaying outside open")
	_check(cinematic.video_player.bus == &"Music", "opening soundtrack uses the Music bus exactly once")
	_check(is_equal_approx(cinematic.video_player.volume_db, 0.0), "opening player does not add a second gain layer")
	_check(cinematic.open(), "cinematic opens from the canonical film")
	await process_frame
	await process_frame
	_check(cinematic.is_open() and cinematic.video_player.visible, "opening film is a visible blocking surface")
	_check(cinematic.video_player.stream is VideoStream and cinematic.video_player.is_playing(), "open assigns and starts the real film stream")
	_check(cinematic.video_player.stream_position < 2.0, "normal open starts at the beginning")
	_check(playback_started_count == [1] and playback_stopped_reasons.is_empty(), "open claims cinematic music once")
	_check(cinematic.skip_button.visible and cinematic.skip_button.custom_minimum_size.y >= 48.0, "explicit skip remains available with a readable target")

	cinematic.video_player.finished.emit()
	await process_frame
	_check(completed_states == [false], "finished playback completes exactly once without the skipped flag")
	_check(not cinematic.is_open() and cinematic.video_player.stream == null and cinematic.resident_texture_count() == 0, "natural completion closes and releases the decoder stream")
	_check(playback_stopped_reasons == ["finished"], "natural completion releases cinematic music exactly once")
	cinematic.video_player.finished.emit()
	await process_frame
	_check(completed_states == [false], "a late duplicate finished signal cannot complete twice")

	var skipped_states: Array[bool] = []
	var skipped_stop_reasons: Array[String] = []
	var skipped = IntroCinematicScript.new()
	root.add_child(skipped)
	skipped.completed.connect(func(value: bool) -> void: skipped_states.append(value))
	skipped.playback_stopped.connect(func(reason: String) -> void: skipped_stop_reasons.append(reason))
	await process_frame
	_check(skipped.open(), "skip fixture opens the real film")
	skipped.skip_button.emit_signal("pressed")
	await process_frame
	_check(skipped_states == [true] and not skipped.is_open(), "explicit skip completes once with skipped=true")
	_check(skipped.video_player.stream == null and skipped_stop_reasons == ["skipped"], "skip stops and detaches the film")
	_check(skipped.open() and skipped.video_player.stream_position < 2.0, "replay starts from the beginning")
	skipped.close()
	await process_frame
	_check(skipped_states == [true] and skipped_stop_reasons == ["skipped", "closed"], "manual close releases replay without pretending to complete")

	var missing_failures: Array[String] = []
	var missing_states: Array[bool] = []
	var missing = IntroCinematicScript.new()
	missing.film_path = "res://assets/video/opening/definitely-missing-opening-film.ogv"
	missing.load_failed.connect(func(message: String) -> void: missing_failures.append(message))
	missing.completed.connect(func(value: bool) -> void: missing_states.append(value))
	root.add_child(missing)
	await process_frame
	_check(not missing.open(), "missing film cannot silently fall back to story cards")
	_check(missing.is_open() and missing.error_label.visible and missing.error_label.text.contains("遺失"), "missing film presents a human-readable blocking error")
	_check(missing.video_player.stream == null and missing.resident_texture_count() == 0, "load failure owns no decoder stream")
	_check(missing.retry_button.visible and missing.leave_button.visible, "load failure offers retry and safe leave")
	_check(missing_failures.size() == 1 and missing_states.is_empty(), "load failure reports once without completing onboarding")
	missing.film_path = IntroCinematicScript.FILM_PATH
	missing.retry_button.emit_signal("pressed")
	await process_frame
	_check(missing.video_player.stream is VideoStream and missing.video_player.is_playing(), "retry loads the restored canonical film")
	missing.close()
	await process_frame
	_check(missing_states.is_empty(), "closing after retry still does not synthesize completion")

	var wrong_type = IntroCinematicScript.new()
	wrong_type.film_path = "res://assets/audio/storybook_v1/ui-click.wav"
	root.add_child(wrong_type)
	await process_frame
	_check(not wrong_type.open() and wrong_type.error_label.text.contains("格式"), "non-video resource fails clearly")
	wrong_type.leave_button.emit_signal("pressed")
	await process_frame
	_check(not wrong_type.is_open(), "error leave action removes the blocking surface without completing")

	for locale in ["zh_TW", "zh_CN", "en", "ja", "ko"]:
		var l10n = root.get_node_or_null("L10n")
		_check(l10n != null and bool(l10n.set_locale(locale, false)), "locale available: %s" % locale)
		if l10n != null:
			_check(str(l10n.text(DECLINE_SUBTITLE)) == str(DECLINE_TRANSLATIONS[locale]), "story localization remains exact: %s" % locale)

	if failed:
		quit(1)
	else:
		print("Intro cinematic contract test passed. CanonicalFilmLoaded=true Checks=%d" % checks)
		quit(0)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		return
	failed = true
	push_error("Intro cinematic contract failed: %s" % message)
