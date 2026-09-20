extends SceneTree

const MainScene := preload("res://scenes/Main.tscn")
const IntroCinematicScript := preload("res://ui/tutorial/intro_cinematic.gd")
const TEST_SAVE_PATH := "user://mayor_simulator/tests/intro_cinematic_visible_acceptance.json"
const NATURAL_TIMEOUT_MSEC := 110_000


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_save()
	if DisplayServer.get_name().to_lower() == "headless":
		push_error("Visible cinematic acceptance requires a non-headless display driver.")
		quit(1)
		return
	root.content_scale_size = Vector2i(1440, 900)
	root.size = Vector2i(1440, 900)
	var main = MainScene.instantiate()
	root.add_child(main)
	await process_frame
	main.start_save_path = TEST_SAVE_PATH
	main.start_screen.animation_duration = 0.35
	main.start_screen.new_game_button.emit_signal("pressed")
	for _frame in range(240):
		await process_frame
		if not main.start_screen.is_loading():
			break
	if main.start_screen.is_loading() or main.start_screen.visible:
		await _fail_and_finish(main, "Visible cinematic acceptance could not finish the real new-game loading flow.")
		return
	var cinematic = main.tutorial_overlay
	var video_player := cinematic.video_player as VideoStreamPlayer if cinematic != null else null
	if (
		cinematic == null
		or not cinematic.is_open()
		or video_player == null
		or not video_player.is_visible_in_tree()
		or not video_player.is_playing()
		or video_player.stream == null
		or not video_player.stream is VideoStream
		or str(video_player.stream.resource_path) != IntroCinematicScript.FILM_PATH
	):
		await _fail_and_finish(main, "Visible cinematic acceptance did not reach the canonical OGV player through Main/new game.")
		return
	var initial_audio_state: Dictionary = main.audio_director.audio_state()
	if not bool(initial_audio_state.get("cinematic_music_active", false)) or main.audio_director.music_player.playing:
		await _fail_and_finish(main, "Visible cinematic acceptance did not establish the product Music claim before playback.")
		return
	print("VISIBLE_INTRO_CINEMATIC_READY: Canonical OGV is playing from Main/new game on the visible root. Human picture, subtitle, and audible-mix review remain PENDING while this helper waits for natural completion.")

	var wall_started_msec := Time.get_ticks_msec()
	var first_position := float(video_player.stream_position)
	var greatest_position := first_position
	var progress_samples := 0
	while cinematic.is_open() and Time.get_ticks_msec() - wall_started_msec < NATURAL_TIMEOUT_MSEC:
		await process_frame
		var position := float(video_player.stream_position)
		if position > greatest_position + 0.25:
			greatest_position = position
			progress_samples += 1
	var wall_seconds := float(Time.get_ticks_msec() - wall_started_msec) / 1000.0
	var final_audio_state: Dictionary = main.audio_director.audio_state()
	var passed := (
		is_equal_approx(Engine.time_scale, 1.0)
		and first_position < 2.0
		and greatest_position >= 88.0
		and progress_samples > 20
		and wall_seconds >= 88.0
		and wall_seconds <= 110.0
		and not cinematic.is_open()
		and video_player.stream == null
		and bool(main.tutorial_completed)
		and main.onboarding_progress.is_active()
		and main.onboarding_progress.current_target() == "build"
		and main.vertical_slice.has_save_game(TEST_SAVE_PATH)
		and not bool(final_audio_state.get("cinematic_music_active", true))
		and main.audio_director.music_player.playing == main.music_enabled
	)
	if not passed:
		await _fail_and_finish(
			main,
			"Visible cinematic natural playback failed: wall=%.3f first=%.3f max=%.3f samples=%d open=%s stream=%s tutorial_completed=%s guide=%s audio=%s" % [
				wall_seconds,
				first_position,
				greatest_position,
				progress_samples,
				cinematic.is_open(),
				video_player.stream,
				main.tutorial_completed,
				main.onboarding_progress.current_target(),
				final_audio_state,
			]
		)
		return
	print(
		"VISIBLE_INTRO_CINEMATIC_ACCEPTANCE_COMPLETED natural_playback=PASS wall_seconds=%.3f max_position=%.3f human_visual_review=PENDING human_audio_review=PENDING os_mouse=PENDING" % [
			wall_seconds,
			greatest_position,
		]
	)
	await _finish(main, 0)


func _fail_and_finish(main, message: String) -> void:
	push_error(message)
	await _finish(main, 1)


func _finish(main, exit_code: int) -> void:
	if main != null and is_instance_valid(main):
		main.queue_free()
		await process_frame
		await process_frame
	_cleanup_save()
	quit(exit_code)


func _cleanup_save() -> void:
	var path := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
