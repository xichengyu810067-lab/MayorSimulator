class_name AudioDirector
extends Node

const MUSIC = preload("res://assets/audio/storybook_v1/mayors-dawn-loop.wav")
const UI_CLICK = preload("res://assets/audio/storybook_v1/ui-click.wav")
const PAGE_TURN = preload("res://assets/audio/storybook_v1/page-turn.wav")
const SUCCESS = preload("res://assets/audio/storybook_v1/success-chime.wav")
const CONSTRUCTION_COMPLETE = preload("res://assets/audio/storybook_v1/construction-complete.wav")
const WARNING = preload("res://assets/audio/storybook_v1/warning-soft.wav")

const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
const MUSIC_BASE_DB := -23.0
const SFX_BASE_DB := -9.0
const SHUTDOWN_STOP_SETTLE_FRAMES := 3
const SHUTDOWN_DETACH_SETTLE_FRAMES := 3
const SHUTDOWN_FREE_SETTLE_FRAMES := 3

var music_enabled := true
var sfx_enabled := true
var music_volume := 1.0
var sfx_volume := 1.0
var music_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var _next_sfx_player := 0
var _shutdown_settled := false
var _cinematic_music_active := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_audio_bus(MUSIC_BUS)
	_ensure_audio_bus(SFX_BUS)
	music_player = AudioStreamPlayer.new()
	music_player.name = "StorybookMusic"
	music_player.bus = MUSIC_BUS
	music_player.volume_db = MUSIC_BASE_DB
	var loop_stream := MUSIC.duplicate() as AudioStreamWAV
	if loop_stream != null:
		loop_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		loop_stream.loop_begin = 0
		loop_stream.loop_end = int(loop_stream.get_length() * loop_stream.mix_rate)
		music_player.stream = loop_stream
	else:
		music_player.stream = MUSIC
	add_child(music_player)
	for index in 4:
		var player := AudioStreamPlayer.new()
		player.name = "StorybookSfx_%d" % index
		player.bus = SFX_BUS
		player.volume_db = SFX_BASE_DB
		add_child(player)
		sfx_players.append(player)
	_apply_music_bus_state()
	_apply_bus_volume(SFX_BUS, sfx_volume)


func _exit_tree() -> void:
	shutdown()


func shutdown() -> void:
	if _shutdown_settled:
		return
	stop_all()
	detach_streams()
	_shutdown_settled = true


func settle_for_shutdown(tree: SceneTree) -> void:
	if _shutdown_settled:
		return
	stop_all()
	# AudioServer consumes playback commands asynchronously. Keep the same
	# frame barriers used by the leak-clean test teardown before releasing WAVs.
	for _frame in range(SHUTDOWN_STOP_SETTLE_FRAMES):
		await tree.process_frame
	detach_streams()
	for _frame in range(SHUTDOWN_DETACH_SETTLE_FRAMES):
		await tree.process_frame
	_shutdown_settled = true


func stop_all() -> void:
	if is_instance_valid(music_player):
		music_player.stop()
	for player in sfx_players:
		if is_instance_valid(player):
			player.stop()


func detach_streams() -> void:
	if is_instance_valid(music_player):
		music_player.stream = null
	for player in sfx_players:
		if is_instance_valid(player):
			player.stream = null


func start_music() -> void:
	if music_enabled and not _cinematic_music_active and music_player != null and not music_player.playing:
		music_player.play()


func stop_music() -> void:
	if music_player != null:
		music_player.stop()


func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	_apply_music_bus_state()
	if music_enabled:
		start_music()
	else:
		stop_music()


func set_sfx_enabled(enabled: bool) -> void:
	sfx_enabled = enabled


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_music_bus_state()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume(SFX_BUS, sfx_volume)


func audio_state() -> Dictionary:
	return {
		"music_enabled": music_enabled,
		"sfx_enabled": sfx_enabled,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"cinematic_music_active": _cinematic_music_active,
	}


func begin_cinematic_music() -> void:
	if _cinematic_music_active:
		return
	_cinematic_music_active = true
	stop_music()
	_apply_music_bus_state()


func end_cinematic_music() -> void:
	if not _cinematic_music_active:
		return
	_cinematic_music_active = false
	_apply_music_bus_state()
	start_music()


func play_ui_click() -> void:
	_play_sfx(UI_CLICK, -13.0)


func play_page_turn() -> void:
	_play_sfx(PAGE_TURN, -8.0)


func play_success() -> void:
	_play_sfx(SUCCESS, -7.0)


func play_construction_complete() -> void:
	_play_sfx(CONSTRUCTION_COMPLETE, -6.0)


func play_warning() -> void:
	_play_sfx(WARNING, -8.0)


func play_cue(cue: String) -> void:
	match cue:
		"page_turn": play_page_turn()
		"success": play_success()
		"construction_complete": play_construction_complete()
		"warning": play_warning()
		_: play_ui_click()


func _play_sfx(stream: AudioStream, volume_db: float) -> void:
	if not sfx_enabled or stream == null or sfx_players.is_empty():
		return
	var player := sfx_players[_next_sfx_player]
	_next_sfx_player = (_next_sfx_player + 1) % sfx_players.size()
	player.stream = stream
	player.volume_db = volume_db
	player.play()


func _ensure_audio_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var bus_index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, bus_name)
	AudioServer.set_bus_send(bus_index, &"Master")


func _apply_bus_volume(bus_name: StringName, linear_volume: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	var safe_volume := clampf(linear_volume, 0.0, 1.0)
	AudioServer.set_bus_mute(bus_index, safe_volume <= 0.0001)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(safe_volume, 0.0001)))


func _apply_music_bus_state() -> void:
	var bus_index := AudioServer.get_bus_index(MUSIC_BUS)
	if bus_index < 0:
		return
	var safe_volume := clampf(music_volume, 0.0, 1.0)
	AudioServer.set_bus_mute(bus_index, not music_enabled or safe_volume <= 0.0001)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(safe_volume, 0.0001)))
