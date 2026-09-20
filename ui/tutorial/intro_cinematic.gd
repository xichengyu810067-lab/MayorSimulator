class_name IntroCinematic
extends Control

const StorySequence = preload("res://data/tutorial/story_sequence.gd")
const FILM_PATH := "res://assets/video/opening/civic_tale_opening_1080p30.ogv"
const FILM_DURATION_SECONDS := 90.0
const CHAPTER_DURATION_SECONDS := 11.25
const MUSIC_BUS := &"Music"
const PAGES := StorySequence.SHOTS

signal completed(skipped: bool)
signal load_failed(message: String)
signal audio_cue(cue: String)
signal playback_started
signal playback_stopped(reason: String)

var current_index := 0
var current_page: int:
	get:
		return current_index
var film_path := FILM_PATH
var _completed_emitted := false
var _closing := false
var _playback_claimed := false
var _loaded_stream: VideoStream
var _fade: Tween
var video_player: VideoStreamPlayer
var error_panel: Control
var error_label: Label
var retry_button: Button
var leave_button: Button
var skip_button: Button
var story_panel: Control


func _init() -> void:
	name = "IntroCinematic"
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_as_relative = false
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	visibility_changed.connect(_on_visibility_changed)


func _process(_delta: float) -> void:
	if not is_open() or video_player == null or not video_player.is_playing():
		return
	current_index = clampi(
		int(floor(float(video_player.stream_position) / CHAPTER_DURATION_SECONDS)),
		0,
		PAGES.size() - 1
	)


func open(reset_to_start: bool = true) -> bool:
	if not StorySequence.is_valid():
		return _show_load_error("開場動畫資料無效，無法安全播放。")
	if not ResourceLoader.exists(film_path):
		return _show_load_error("開場影片遺失，請重試或稍後從設定重新播放。")
	var resource := ResourceLoader.load(film_path)
	if not resource is VideoStream:
		return _show_load_error("開場影片格式無效，請重試或稍後從設定重新播放。")
	var stream := resource as VideoStream
	_release_playback("reopened")
	_completed_emitted = false
	_closing = false
	error_panel.hide()
	video_player.show()
	_loaded_stream = stream
	video_player.stream = _loaded_stream
	current_index = 0 if reset_to_start or current_index < 0 or current_index >= PAGES.size() else current_index
	show()
	move_to_front()
	modulate.a = 0.0
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade.tween_property(self, "modulate:a", 1.0, 0.20)
	_claim_playback()
	video_player.play()
	if reset_to_start:
		video_player.stream_position = 0.0
	else:
		video_player.stream_position = float(current_index) * CHAPTER_DURATION_SECONDS
	skip_button.grab_focus()
	return true


func advance() -> void:
	# The real opening film advances on its own. Kept as a no-op compatibility
	# surface for callers that previously advanced individual story cards.
	return


func close() -> void:
	if _closing:
		return
	_closing = true
	_release_playback("closed")
	hide()
	_closing = false


func close_as_completed(skipped: bool = false) -> void:
	_complete(skipped)


func is_open() -> bool:
	return visible and not _closing


func resident_texture_count() -> int:
	return 1 if _loaded_stream != null else 0


func _exit_tree() -> void:
	_release_playback("unloaded")


func _finish() -> void:
	_complete(false)


func _complete(skipped: bool) -> void:
	if _completed_emitted or _closing or not visible or _loaded_stream == null:
		return
	_completed_emitted = true
	_closing = true
	_release_playback("skipped" if skipped else "finished")
	hide()
	_closing = false
	audio_cue.emit("click" if skipped else "success")
	completed.emit(skipped)


func _claim_playback() -> void:
	if _playback_claimed:
		return
	_playback_claimed = true
	playback_started.emit()


func _release_playback(reason: String) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = null
	if video_player != null:
		video_player.stop()
		video_player.stream = null
	_loaded_stream = null
	if _playback_claimed:
		_playback_claimed = false
		playback_stopped.emit(reason)


func _show_load_error(message: String) -> bool:
	if _closing:
		return false
	_closing = true
	_release_playback("load_failed")
	video_player.hide()
	error_label.text = message
	error_panel.show()
	show()
	move_to_front()
	modulate.a = 1.0
	_closing = false
	retry_button.grab_focus()
	load_failed.emit(message)
	return false


func _retry() -> void:
	open(true)


func _on_visibility_changed() -> void:
	if visible or _closing:
		return
	_release_playback("hidden")


func _build() -> void:
	story_panel = self
	var background := ColorRect.new()
	background.color = Color("#05090c")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	video_player = VideoStreamPlayer.new()
	video_player.name = "OpeningFilmPlayer"
	video_player.expand = true
	video_player.loop = false
	video_player.autoplay = false
	video_player.bus = MUSIC_BUS
	video_player.volume_db = 0.0
	video_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	video_player.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	video_player.finished.connect(_finish)
	add_child(video_player)

	skip_button = Button.new()
	skip_button.name = "CinematicSkipButton"
	skip_button.text = "跳過片頭"
	skip_button.tooltip_text = "立即結束片頭並進入實作導覽；可從設定重新播放"
	skip_button.custom_minimum_size = Vector2(140.0, 48.0)
	skip_button.anchor_left = 1.0
	skip_button.anchor_top = 0.0
	skip_button.anchor_right = 1.0
	skip_button.anchor_bottom = 0.0
	skip_button.offset_left = -164.0
	skip_button.offset_top = 24.0
	skip_button.offset_right = -24.0
	skip_button.offset_bottom = 72.0
	skip_button.pressed.connect(func() -> void: close_as_completed(true))
	add_child(skip_button)

	error_panel = CenterContainer.new()
	error_panel.name = "OpeningFilmErrorPanel"
	error_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	error_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(error_panel)
	var error_card := VBoxContainer.new()
	error_card.custom_minimum_size = Vector2(560.0, 190.0)
	error_card.alignment = BoxContainer.ALIGNMENT_CENTER
	error_card.add_theme_constant_override("separation", 18)
	error_panel.add_child(error_card)
	error_label = Label.new()
	error_label.name = "CinematicError"
	error_label.add_theme_font_size_override("font_size", 24)
	error_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.68))
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	error_card.add_child(error_label)
	var error_actions := HBoxContainer.new()
	error_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	error_actions.add_theme_constant_override("separation", 12)
	error_card.add_child(error_actions)
	retry_button = Button.new()
	retry_button.name = "OpeningFilmRetryButton"
	retry_button.text = "重試播放"
	retry_button.custom_minimum_size = Vector2(140.0, 48.0)
	retry_button.pressed.connect(_retry)
	error_actions.add_child(retry_button)
	leave_button = Button.new()
	leave_button.name = "OpeningFilmLeaveButton"
	leave_button.text = "稍後再看"
	leave_button.tooltip_text = "關閉片頭錯誤；故事不會標記完成，可從設定重試"
	leave_button.custom_minimum_size = Vector2(140.0, 48.0)
	leave_button.pressed.connect(close)
	error_actions.add_child(leave_button)
	error_panel.hide()
