extends Node

const IDLE_FRAME_TARGET := 12

var _idle_frames := 0
var _started_usec := 0


func _ready() -> void:
	_started_usec = Time.get_ticks_usec()
	print("P3_OBJECTDB_PROBE_START scene=%s pid=%d" % [get_tree().current_scene.scene_file_path, OS.get_process_id()])
	print("P3_OBJECTDB_PROBE_IDLE_TARGET frames=%d" % IDLE_FRAME_TARGET)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	_idle_frames += 1
	if _idle_frames < IDLE_FRAME_TARGET:
		return
	print("P3_OBJECTDB_PROBE_NORMAL_QUIT frames=%d elapsed_usec=%d" % [_idle_frames, Time.get_ticks_usec() - _started_usec])
	get_tree().quit(0)
