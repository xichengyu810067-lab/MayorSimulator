extends RefCounted

## Wall-clock adapter only. Calendar time lives in CityState and advances only
## through SimCommands. No OS timestamp is persisted, so closing the game never
## creates offline progress.

const DEFAULT_DAY_LENGTH_SECONDS := 120.0
const MAX_FRAME_DELTA_SECONDS := 1.0
const DAY_BOUNDARY_EPSILON_SECONDS := 0.000001
const GAME_HOURS_PER_DAY := 12
const MINUTES_PER_HOUR := 60
const GAME_MINUTES_PER_DAY := GAME_HOURS_PER_DAY * MINUTES_PER_HOUR

var day_length_seconds: float = DEFAULT_DAY_LENGTH_SECONDS
var accumulator_seconds: float = 0.0
var paused: bool = false


func _init(p_day_length_seconds: float = DEFAULT_DAY_LENGTH_SECONDS) -> void:
	day_length_seconds = maxf(p_day_length_seconds, 0.001)


func consume_frame(delta_seconds: float) -> int:
	if paused or delta_seconds <= 0.0 or is_nan(delta_seconds) or is_inf(delta_seconds):
		return 0
	# A bounded frame delta prevents focus loss or debugger pauses from being
	# interpreted as offline simulation time.
	accumulator_seconds += minf(delta_seconds, MAX_FRAME_DELTA_SECONDS)
	var elapsed_days := int(floor((accumulator_seconds + DAY_BOUNDARY_EPSILON_SECONDS) / day_length_seconds))
	if elapsed_days > 0:
		accumulator_seconds = maxf(0.0, accumulator_seconds - float(elapsed_days) * day_length_seconds)
	return elapsed_days


func game_minutes_into_day() -> int:
	var progress := clampf(accumulator_seconds / day_length_seconds, 0.0, 1.0)
	return clampi(int(floor(progress * float(GAME_MINUTES_PER_DAY) + 0.000001)), 0, GAME_MINUTES_PER_DAY - 1)


func reset() -> void:
	accumulator_seconds = 0.0
	paused = false


func to_dict() -> Dictionary:
	return {
		"day_length_seconds": day_length_seconds,
		"accumulator_seconds": accumulator_seconds,
		"paused": paused,
	}


func restore(data: Dictionary) -> void:
	day_length_seconds = maxf(float(data.get("day_length_seconds", DEFAULT_DAY_LENGTH_SECONDS)), 0.001)
	accumulator_seconds = clampf(float(data.get("accumulator_seconds", 0.0)), 0.0, day_length_seconds)
	paused = bool(data.get("paused", false))
