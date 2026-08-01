extends Button

# The clickable Control stays larger than the painted actor.  The walk atlas is
# drawn inside a stable 64x64 box whose bottom-centre is the actor's feet.
const MINIMUM_HIT_SIZE := Vector2(52, 68)
const ART_DRAW_SIZE := Vector2(64, 64)
const ATLAS_CELL_SIZE := Vector2(192, 192)
const ATLAS_COLUMNS := 4
const ATLAS_ROWS := 4
const WALK_FRAMES_PER_DIRECTION := 4
const WALK_FRAME_DISTANCE := 5.5
const WALK_SPEED_THRESHOLD := 1.0
const WALK_DISTANCE_THRESHOLD := 0.01
const FEET_BOTTOM_INSET := 3.0
const STOP_SETTLE_DURATION := 0.14
const STOP_SETTLE_SWITCH_RATIO := 0.50
const DIRECTION_AXIS_HYSTERESIS := 0.18
const DIRECTION_LOCK_DURATION := 0.12
const NEUTRAL_FRAMES := [0, 2]

const HOVER_GOLD := Color(1.0, 0.79, 0.24, 0.96)
const HEALING_CORAL := Color(0.96, 0.48, 0.43, 0.96)
const SOFT_CREAM := Color(1.0, 0.94, 0.72, 0.96)
const SHADOW := Color(0.035, 0.045, 0.055, 0.30)
const SHADOW_CORE := Color(0.025, 0.030, 0.038, 0.22)
const REACTION_DURATION := 0.78
const TURN_BLEND_DURATION := 0.16
const BLINK_DURATION := 0.13
const BLINK_INTERVAL_MIN := 2.4
const BLINK_INTERVAL_MAX := 5.8

const DIRECTION_DOWN := "down"
const DIRECTION_LEFT := "left"
const DIRECTION_RIGHT := "right"
const DIRECTION_UP := "up"
const DIRECTION_ORDER := [
	DIRECTION_DOWN,
	DIRECTION_LEFT,
	DIRECTION_RIGHT,
	DIRECTION_UP,
]
const DIRECTION_ROWS := {
	DIRECTION_DOWN: 0,
	DIRECTION_LEFT: 1,
	DIRECTION_RIGHT: 2,
	DIRECTION_UP: 3,
}

const EXPRESSION_CALM := "calm"
const EXPRESSION_CURIOUS := "curious"
const EXPRESSION_HAPPY := "happy"
const EXPRESSION_CONCERNED := "concerned"
const EXPRESSION_PROUD := "proud"
const VALID_EXPRESSIONS := [
	EXPRESSION_CALM,
	EXPRESSION_CURIOUS,
	EXPRESSION_HAPPY,
	EXPRESSION_CONCERNED,
	EXPRESSION_PROUD,
]

# Portrait textures remain public for dialogue and old structural tests.  The
# visible world actor uses ROLE_WALK_TEXTURES below.
const ROLE_TEXTURES := {
	"一般居民": preload("res://assets/images/characters/npc/npc-resident.png"),
	"學生": preload("res://assets/images/characters/npc/npc-student.png"),
	"商人": preload("res://assets/images/characters/npc/npc-merchant.png"),
	"老年居民": preload("res://assets/images/characters/npc/npc-elderly.png"),
	"工人": preload("res://assets/images/characters/npc/npc-worker.png"),
	"公務人員": preload("res://assets/images/characters/npc/npc-civil-servant.png"),
	"議員": preload("res://assets/images/characters/npc/npc-council-member.png"),
}
const RESIDENT_VARIANT_TEXTURE := preload("res://assets/images/characters/npc/npc-resident-florist.png")

const ROLE_WALK_TEXTURES := {
	"一般居民": preload("res://assets/images/characters/npc/walk/resident/sheet-transparent.png"),
	"學生": preload("res://assets/images/characters/npc/walk/student/sheet-transparent.png"),
	"商人": preload("res://assets/images/characters/npc/walk/merchant/sheet-transparent.png"),
	"老年居民": preload("res://assets/images/characters/npc/walk/elderly/sheet-transparent.png"),
	"工人": preload("res://assets/images/characters/npc/walk/worker/sheet-transparent.png"),
	"公務人員": preload("res://assets/images/characters/npc/walk/civil-servant/sheet-transparent.png"),
	"議員": preload("res://assets/images/characters/npc/walk/council-member/sheet-transparent.png"),
}
const RESIDENT_VARIANT_WALK_TEXTURE := preload("res://assets/images/characters/npc/walk/resident-florist/sheet-transparent.png")

const ATLAS_PATHS := {
	"resident": "res://assets/images/characters/npc/walk/resident/sheet-transparent.png",
	"student": "res://assets/images/characters/npc/walk/student/sheet-transparent.png",
	"merchant": "res://assets/images/characters/npc/walk/merchant/sheet-transparent.png",
	"elderly": "res://assets/images/characters/npc/walk/elderly/sheet-transparent.png",
	"worker": "res://assets/images/characters/npc/walk/worker/sheet-transparent.png",
	"civil-servant": "res://assets/images/characters/npc/walk/civil-servant/sheet-transparent.png",
	"council-member": "res://assets/images/characters/npc/walk/council-member/sheet-transparent.png",
	"resident-florist": "res://assets/images/characters/npc/walk/resident-florist/sheet-transparent.png",
}

const ROLE_COLORS := {
	"一般居民": Color(0.38, 0.48, 0.26),
	"學生": Color(0.91, 0.61, 0.18),
	"商人": Color(0.62, 0.25, 0.16),
	"老年居民": Color(0.43, 0.61, 0.72),
	"工人": Color(0.20, 0.37, 0.54),
	"公務人員": Color(0.12, 0.28, 0.47),
	"議員": Color(0.42, 0.20, 0.47),
}

const ROLE_SKIN_COLORS := {
	"一般居民": Color(0.95, 0.75, 0.56),
	"學生": Color(0.96, 0.76, 0.58),
	"商人": Color(0.90, 0.66, 0.49),
	"老年居民": Color(0.94, 0.78, 0.65),
	"工人": Color(0.94, 0.72, 0.53),
	"公務人員": Color(0.94, 0.73, 0.55),
	"議員": Color(0.94, 0.72, 0.54),
}

var npc_type := "一般居民"
var is_dark_mode := false
var is_walking := false
var motion_phase := 0.0
var facing_sign := 1.0
var appearance_variant := 0
var portrait_mode := false

# Kept for dialogue/compatibility.  World rendering uses walk_texture.
var actor_texture: Texture2D = ROLE_TEXTURES["一般居民"]
var walk_texture: Texture2D = ROLE_WALK_TEXTURES["一般居民"]

var expression_state := EXPRESSION_CALM
var expression_intensity := 1.0
var interaction_reaction_remaining := 0.0
var turn_reaction_remaining := 0.0

var current_velocity := Vector2.ZERO
var travelled_distance := 0.0
var current_direction := DIRECTION_DOWN
var previous_direction := DIRECTION_DOWN
var current_frame := 0
var cycle_phase := 0.0

var _animation_seed := 1
var _blink_rng := RandomNumberGenerator.new()
var _blink_wait_remaining := 1.0
var _blink_elapsed := 0.0
var _blink_active := false
var _legacy_blink_override := false
var _last_locomotion_delta := 0.0
var _stop_settle_remaining := 0.0
var _stop_source_frame := 0
var _stop_target_frame := 0
var _direction_lock_remaining := 0.0


func _ready() -> void:
	text = ""
	focus_mode = Control.FOCUS_NONE if portrait_mode else Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_IGNORE if portrait_mode else Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_ARROW if portrait_mode else Control.CURSOR_POINTING_HAND
	custom_minimum_size = custom_minimum_size.max(MINIMUM_HIT_SIZE)
	size = size.max(MINIMUM_HIT_SIZE)
	clip_contents = false
	var empty := StyleBoxEmpty.new()
	add_theme_stylebox_override("normal", empty)
	add_theme_stylebox_override("hover", empty)
	add_theme_stylebox_override("pressed", empty)
	add_theme_stylebox_override("disabled", empty)
	var focus_ring := StyleBoxFlat.new()
	focus_ring.bg_color = Color(1.0, 0.86, 0.28, 0.08)
	focus_ring.border_color = Color(1.0, 0.78, 0.10, 0.98)
	focus_ring.set_border_width_all(3)
	focus_ring.set_corner_radius_all(12)
	add_theme_stylebox_override("focus", focus_ring)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	pressed.connect(_on_actor_pressed)
	resized.connect(queue_redraw)
	_reset_blink_schedule()
	set_process(true)


func _process(delta: float) -> void:
	var needs_redraw := false
	if interaction_reaction_remaining > 0.0:
		interaction_reaction_remaining = maxf(0.0, interaction_reaction_remaining - delta)
		needs_redraw = true
	# Modern callers advance locomotion timers through set_locomotion(delta), so
	# deterministic simulation and rendering share one clock.  Only the legacy
	# phase API relies on SceneTree processing for these timers.
	if _legacy_blink_override:
		needs_redraw = _advance_locomotion_timers(delta) or needs_redraw
	if not _legacy_blink_override:
		if _blink_active:
			_blink_elapsed += delta
			needs_redraw = true
			if _blink_elapsed >= BLINK_DURATION:
				_blink_active = false
				_blink_elapsed = 0.0
				_blink_wait_remaining = _next_blink_interval()
		else:
			_blink_wait_remaining -= delta
			if _blink_wait_remaining <= 0.0:
				_blink_active = true
				_blink_elapsed = 0.0
				needs_redraw = true
	if needs_redraw:
		queue_redraw()


func set_portrait_mode(enabled: bool) -> void:
	portrait_mode = enabled
	mouse_filter = Control.MOUSE_FILTER_IGNORE if enabled else Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_ARROW if enabled else Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE if enabled else Control.FOCUS_ALL
	set_meta("portrait_mode", enabled)
	queue_redraw()


func set_actor(type_name: String, dark_mode: bool, variant_seed: int = 0) -> void:
	npc_type = type_name if ROLE_TEXTURES.has(type_name) else "一般居民"
	is_dark_mode = dark_mode
	appearance_variant = absi(variant_seed) % 2
	actor_texture = (
		RESIDENT_VARIANT_TEXTURE
		if npc_type == "一般居民" and appearance_variant == 1
		else ROLE_TEXTURES[npc_type]
	)
	walk_texture = (
		RESIDENT_VARIANT_WALK_TEXTURE
		if npc_type == "一般居民" and appearance_variant == 1
		else ROLE_WALK_TEXTURES[npc_type]
	)
	expression_state = EXPRESSION_CALM
	expression_intensity = 1.0
	interaction_reaction_remaining = 0.0
	turn_reaction_remaining = 0.0
	current_velocity = Vector2.ZERO
	travelled_distance = 0.0
	current_direction = DIRECTION_DOWN
	previous_direction = DIRECTION_DOWN
	current_frame = 0
	cycle_phase = 0.0
	is_walking = false
	motion_phase = 0.0
	facing_sign = 1.0
	_stop_settle_remaining = 0.0
	_stop_source_frame = 0
	_stop_target_frame = 0
	_direction_lock_remaining = 0.0
	_animation_seed = maxi(1, absi(hash("%s:%d" % [npc_type, variant_seed])))
	_blink_rng.seed = _animation_seed
	_legacy_blink_override = false
	_reset_blink_schedule()
	text = ""
	tooltip_text = type_name
	queue_redraw()


# New locomotion contract.  travelled_distance is the real distance moved in
# this update, not desired travel.  The actor accumulates it, so a blocked NPC
# with non-zero desired velocity does not keep walking in place.
func set_locomotion(velocity: Vector2, travelled_distance: float, delta: float) -> void:
	var was_walking := is_walking
	current_velocity = velocity
	_last_locomotion_delta = maxf(0.0, delta)
	_advance_locomotion_timers(_last_locomotion_delta)
	var safe_distance := maxf(0.0, travelled_distance)
	self.travelled_distance += safe_distance
	var measured_speed := safe_distance / maxf(delta, 0.0001) if delta > 0.0 else 0.0
	var effective_speed := maxf(velocity.length(), measured_speed)
	var walking_now := effective_speed > WALK_SPEED_THRESHOLD and safe_distance > WALK_DISTANCE_THRESHOLD
	if velocity.length_squared() > WALK_SPEED_THRESHOLD * WALK_SPEED_THRESHOLD:
		_begin_direction_change(_direction_from_velocity(velocity))
	if current_direction == DIRECTION_RIGHT:
		facing_sign = 1.0
	elif current_direction == DIRECTION_LEFT:
		facing_sign = -1.0
	cycle_phase = _cycle_phase_for_distance(self.travelled_distance)
	motion_phase = cycle_phase * TAU
	if walking_now:
		_stop_settle_remaining = 0.0
		current_frame = _frame_for_distance(self.travelled_distance)
	elif was_walking:
		_begin_stop_settle()
	is_walking = walking_now
	_legacy_blink_override = false
	queue_redraw()


# Backward-compatible phase-driven API.  It keeps old callers functional while
# main.gd migrates to set_locomotion(), but only the Vector2 API can select all
# four direction rows and prevent blocked residents from walking in place.
func set_motion(walking: bool, phase: float, direction_x: float = 0.0) -> void:
	var was_walking := is_walking
	motion_phase = phase
	cycle_phase = fposmod(phase, TAU) / TAU
	if walking:
		_stop_settle_remaining = 0.0
		current_frame = int(floor(cycle_phase * float(WALK_FRAMES_PER_DIRECTION))) % WALK_FRAMES_PER_DIRECTION
	elif was_walking:
		_begin_stop_settle()
	is_walking = walking
	if absf(direction_x) > 0.05:
		var next_facing := 1.0 if direction_x >= 0.0 else -1.0
		facing_sign = next_facing
		_begin_direction_change(DIRECTION_RIGHT if next_facing > 0.0 else DIRECTION_LEFT)
	current_velocity = Vector2(facing_sign, 0.0) if walking else Vector2.ZERO
	_legacy_blink_override = true
	queue_redraw()


func set_expression(expression_name: String, intensity: float = 1.0) -> void:
	expression_state = expression_name if expression_name in VALID_EXPRESSIONS else EXPRESSION_CALM
	expression_intensity = clampf(intensity, 0.0, 1.0)
	queue_redraw()


func play_interaction_reaction() -> void:
	interaction_reaction_remaining = REACTION_DURATION
	queue_redraw()


func _on_actor_pressed() -> void:
	play_interaction_reaction()


func visual_expression() -> String:
	if interaction_reaction_remaining > 0.0:
		return EXPRESSION_HAPPY
	if is_hovered():
		return EXPRESSION_CURIOUS
	return expression_state


func blink_amount() -> float:
	if visual_expression() == EXPRESSION_HAPPY:
		return 1.0
	if _legacy_blink_override:
		# Preserve the deterministic legacy probe used by the existing test while
		# the production Vector2 API uses a per-resident RNG schedule.
		var blink_clock := fposmod(motion_phase, 41.0)
		if blink_clock > 1.20:
			return 0.0
		return sin(PI * blink_clock / 1.20)
	if not _blink_active:
		return 0.0
	return sin(PI * clampf(_blink_elapsed / BLINK_DURATION, 0.0, 1.0))


func interaction_amount() -> float:
	return clampf(interaction_reaction_remaining / REACTION_DURATION, 0.0, 1.0)


func sprite_path_for_type(role: String) -> String:
	var texture: Texture2D = ROLE_TEXTURES.get(role, ROLE_TEXTURES["一般居民"])
	return texture.resource_path


func walk_sprite_path_for_type(role: String, variant_seed: int = 0) -> String:
	if role == "一般居民" and absi(variant_seed) % 2 == 1:
		return RESIDENT_VARIANT_WALK_TEXTURE.resource_path
	var texture: Texture2D = ROLE_WALK_TEXTURES.get(role, ROLE_WALK_TEXTURES["一般居民"])
	return texture.resource_path


func get_animation_contract() -> Dictionary:
	return {
		"atlas_size": Vector2i(768, 768),
		"cell_size": Vector2i(192, 192),
		"columns": ATLAS_COLUMNS,
		"rows": ATLAS_ROWS,
		"frame_count": ATLAS_COLUMNS * ATLAS_ROWS,
		"frames_per_direction": WALK_FRAMES_PER_DIRECTION,
		"directions": DIRECTION_ORDER.duplicate(),
		"direction_order": DIRECTION_ORDER.duplicate(),
		"direction_rows": DIRECTION_ROWS.duplicate(true),
		"atlas_paths": ATLAS_PATHS.duplicate(true),
		"active_atlas_path": walk_texture.resource_path if walk_texture != null else "",
		"runtime_hit_rect": MINIMUM_HIT_SIZE,
		"runtime_draw_size": ART_DRAW_SIZE,
		"frame_distance": WALK_FRAME_DISTANCE,
		"walk_cycle_distance": WALK_FRAME_DISTANCE * float(WALK_FRAMES_PER_DIRECTION),
		"neutral_frames": NEUTRAL_FRAMES.duplicate(),
		"stop_settle_seconds": STOP_SETTLE_DURATION,
		"feet_anchor_mode": "bottom_center",
		"distance_mode": "delta_per_update",
		"turn_blend_seconds": TURN_BLEND_DURATION,
		"turn_transition_mode": "single_body_temporal_lock",
		"opaque_body_draws_per_frame": 1,
		"direction_axis_hysteresis": DIRECTION_AXIS_HYSTERESIS,
		"direction_lock_seconds": DIRECTION_LOCK_DURATION,
		"uses_horizontal_mirroring": false,
		"locomotion_api": "set_locomotion",
	}


func get_locomotion_debug_snapshot() -> Dictionary:
	return {
		"direction": current_direction,
		"render_direction": _render_direction(),
		"previous_direction": previous_direction,
		"frame_index": current_frame,
		"atlas_frame_index": int(DIRECTION_ROWS[current_direction]) * WALK_FRAMES_PER_DIRECTION + current_frame,
		"source_rect": debug_source_rect(),
		"feet_anchor": debug_feet_anchor(),
		"visual_bounds": debug_visual_bounds(),
		"is_walking": is_walking,
		"cycle_phase": cycle_phase,
		"velocity": current_velocity,
		"travelled_distance": travelled_distance,
		"turn_blend": _turn_new_direction_weight(),
		"turn_blend_remaining": turn_reaction_remaining,
		"direction_lock_remaining": _direction_lock_remaining,
		"stop_settle_remaining": _stop_settle_remaining,
		"stop_source_frame": _stop_source_frame,
		"stop_target_frame": _stop_target_frame,
		"opaque_body_draws": 1,
		"last_delta": _last_locomotion_delta,
		"active_atlas_path": walk_texture.resource_path if walk_texture != null else "",
	}


# Pure deterministic sampler for tests.  Unlike set_locomotion(), the supplied
# distance here is a cumulative sample distance and does not mutate the actor.
func debug_sample_locomotion(direction: String, travelled_distance: float, speed: float) -> Dictionary:
	var safe_direction := direction if direction in DIRECTION_ORDER else DIRECTION_DOWN
	var safe_distance := maxf(0.0, travelled_distance)
	var walking_now := absf(speed) > WALK_SPEED_THRESHOLD
	var distance_frame := _frame_for_distance(safe_distance)
	var frame_index := distance_frame if walking_now else _nearest_neutral_frame(distance_frame)
	return {
		"direction": safe_direction,
		"frame_index": frame_index,
		"is_walking": walking_now,
		"cycle_phase": _cycle_phase_for_distance(safe_distance),
		"feet_anchor": debug_feet_anchor(),
		"source_rect": _source_rect_for(safe_direction, frame_index),
	}


func debug_current_direction() -> String:
	return current_direction


func debug_current_frame() -> int:
	return current_frame


func debug_source_rect() -> Rect2:
	return _source_rect_for(_render_direction(), current_frame)


func debug_feet_anchor() -> Vector2:
	return Vector2(size.x * 0.5, size.y - FEET_BOTTOM_INSET)


func debug_visual_bounds() -> Rect2:
	var feet := debug_feet_anchor()
	return Rect2(feet - Vector2(ART_DRAW_SIZE.x * 0.5, ART_DRAW_SIZE.y), ART_DRAW_SIZE)


func _draw() -> void:
	if walk_texture == null:
		return
	var feet := debug_feet_anchor()
	var visual_bounds := debug_visual_bounds()
	_draw_ground_shadow(feet)

	# Draw exactly one opaque body.  Cross-fading two directional full-body
	# frames reads as a translucent ghost when several residents turn at once.
	# Main already eases velocity through corners, so switching the dominant
	# directional row here is both cleaner and more grounded at map scale.
	var render_direction := _render_direction()
	_draw_atlas_frame(render_direction, current_frame, visual_bounds, 1.0)

	_draw_expression_details(feet, render_direction)
	if is_hovered():
		_draw_hover_feedback(feet)
	if interaction_reaction_remaining > 0.0:
		_draw_interaction_feedback(feet)


func _draw_atlas_frame(direction: String, frame_index: int, destination: Rect2, alpha: float) -> void:
	if alpha <= 0.001:
		return
	var source := _source_rect_for(direction, frame_index)
	if is_dark_mode:
		var rim := Color(0.62, 0.82, 0.92, 0.13 * alpha)
		for offset in [Vector2(-0.8, 0), Vector2(0.8, 0), Vector2(0, -0.8), Vector2(0, 0.8)]:
			draw_texture_rect_region(walk_texture, Rect2(destination.position + offset, destination.size), source, rim, false, true)
	draw_texture_rect_region(walk_texture, destination, source, Color(1.0, 1.0, 1.0, alpha), false, true)


func _draw_ground_shadow(feet: Vector2) -> void:
	# The shadow is deliberately independent from the atlas frame.  No whole-
	# actor bob, squash or stride offset is applied to the feet anchor.
	_draw_ellipse(feet + Vector2(0, -0.8), Vector2(10.5, 2.9), SHADOW, 28)
	_draw_ellipse(feet + Vector2(0, -0.6), Vector2(7.2, 1.65), SHADOW_CORE, 24)


func _draw_expression_details(feet: Vector2, render_direction: String) -> void:
	if expression_intensity <= 0.01 or render_direction == DIRECTION_UP:
		return
	var expression := visual_expression()
	var face_center := feet + _face_offset_for_direction(render_direction)
	var skin: Color = ROLE_SKIN_COLORS.get(npc_type, ROLE_SKIN_COLORS["一般居民"])
	var face_alpha := expression_intensity
	if face_alpha <= 0.02:
		return
	var ink := Color(0.20, 0.105, 0.075, 0.94 * face_alpha)
	var line_width := 0.82
	var blink := blink_amount()
	var eye_positions: Array[Vector2] = []
	if render_direction == DIRECTION_DOWN:
		eye_positions = [face_center + Vector2(-2.25, -0.2), face_center + Vector2(2.25, -0.2)]
	else:
		eye_positions = [face_center]

	if blink > 0.46 or expression == EXPRESSION_HAPPY:
		for eye_position in eye_positions:
			draw_circle(eye_position, 1.35, Color(skin, face_alpha))
			draw_arc(eye_position + Vector2(0, 0.25), 1.18, PI + 0.16, TAU - 0.16, 8, ink, line_width, true)

	if expression == EXPRESSION_HAPPY:
		var cheek := Color(1.0, 0.43, 0.43, 0.28 * face_alpha)
		if render_direction == DIRECTION_DOWN:
			draw_circle(face_center + Vector2(-4.1, 2.4), 0.85, cheek)
			draw_circle(face_center + Vector2(4.1, 2.4), 0.85, cheek)
		draw_arc(face_center + Vector2(0, 2.7), 1.45, 0.18, PI - 0.18, 10, ink, line_width, true)
	elif expression == EXPRESSION_CURIOUS:
		draw_arc(face_center + Vector2(0, -2.1), 1.45, PI + 0.18, TAU - 0.26, 8, ink, line_width, true)
	elif expression == EXPRESSION_CONCERNED:
		if render_direction == DIRECTION_DOWN:
			draw_line(face_center + Vector2(-3.2, -1.8), face_center + Vector2(-1.1, -2.4), ink, line_width, true)
			draw_line(face_center + Vector2(1.1, -2.4), face_center + Vector2(3.2, -1.8), ink, line_width, true)
		draw_arc(face_center + Vector2(0, 3.6), 1.3, PI + 0.20, TAU - 0.20, 9, ink, line_width, true)
	elif expression == EXPRESSION_PROUD:
		draw_arc(face_center + Vector2(0, 2.7), 1.3, 0.20, PI - 0.20, 9, ink, line_width, true)


func _draw_hover_feedback(feet: Vector2) -> void:
	var ring := _ellipse_points(feet + Vector2(0, -0.7), Vector2(13.0, 3.8), 32, true)
	draw_polyline(ring, Color(HOVER_GOLD, 0.82), 1.35, true)
	var sparkle_center := feet + Vector2(17.0 * facing_sign, -53.0)
	_draw_sparkle(sparkle_center, 3.2, Color(SOFT_CREAM, 0.92))


func _draw_interaction_feedback(feet: Vector2) -> void:
	var remaining := interaction_amount()
	var progress := 1.0 - remaining
	var ring := _ellipse_points(feet + Vector2(0, -0.7), Vector2(13.0 + progress * 4.0, 3.8 + progress), 32, true)
	draw_polyline(ring, Color(HOVER_GOLD, remaining * 0.88), 1.35, true)
	var heart_center := feet + Vector2(-18.0 * facing_sign, -57.0 - progress * 6.0)
	_draw_heart(heart_center, 3.6 * (0.85 + sin(progress * PI) * 0.24), Color(HEALING_CORAL, remaining))
	_draw_sparkle(heart_center + Vector2(5.4 * facing_sign, -1.2), 1.8, Color(SOFT_CREAM, remaining * 0.9))


func _direction_from_velocity(velocity: Vector2) -> String:
	var abs_x := absf(velocity.x)
	var abs_y := absf(velocity.y)
	var currently_horizontal := current_direction in [DIRECTION_LEFT, DIRECTION_RIGHT]
	var use_horizontal := currently_horizontal
	if currently_horizontal:
		# A vertical row only wins after it clears the current horizontal axis by
		# the hysteresis margin.  Small separation-steering noise near 45 degrees
		# therefore cannot swap atlas rows every frame.
		if abs_y > abs_x * (1.0 + DIRECTION_AXIS_HYSTERESIS):
			use_horizontal = false
	else:
		if abs_x > abs_y * (1.0 + DIRECTION_AXIS_HYSTERESIS):
			use_horizontal = true
	if use_horizontal:
		if abs_x <= WALK_SPEED_THRESHOLD and currently_horizontal:
			return current_direction
		return DIRECTION_RIGHT if velocity.x >= 0.0 else DIRECTION_LEFT
	if abs_y <= WALK_SPEED_THRESHOLD and not currently_horizontal:
		return current_direction
	return DIRECTION_DOWN if velocity.y >= 0.0 else DIRECTION_UP


func _begin_direction_change(next_direction: String) -> void:
	if next_direction not in DIRECTION_ORDER or next_direction == current_direction:
		return
	if _direction_lock_remaining > 0.0:
		return
	previous_direction = current_direction
	current_direction = next_direction
	turn_reaction_remaining = TURN_BLEND_DURATION
	_direction_lock_remaining = DIRECTION_LOCK_DURATION


func _begin_stop_settle() -> void:
	_stop_source_frame = current_frame
	_stop_target_frame = _nearest_neutral_frame(current_frame)
	if _stop_target_frame == current_frame:
		_stop_settle_remaining = 0.0
		return
	_stop_settle_remaining = STOP_SETTLE_DURATION


func _advance_locomotion_timers(delta: float) -> bool:
	var needs_redraw := false
	var safe_delta := maxf(0.0, delta)
	if turn_reaction_remaining > 0.0:
		turn_reaction_remaining = maxf(0.0, turn_reaction_remaining - safe_delta)
		needs_redraw = true
	if _direction_lock_remaining > 0.0:
		_direction_lock_remaining = maxf(0.0, _direction_lock_remaining - safe_delta)
	if _stop_settle_remaining > 0.0:
		_stop_settle_remaining = maxf(0.0, _stop_settle_remaining - safe_delta)
		var switch_at := STOP_SETTLE_DURATION * (1.0 - STOP_SETTLE_SWITCH_RATIO)
		if _stop_settle_remaining <= switch_at and current_frame != _stop_target_frame:
			current_frame = _stop_target_frame
			needs_redraw = true
	return needs_redraw


func _nearest_neutral_frame(frame_index: int) -> int:
	var safe_frame := posmod(frame_index, WALK_FRAMES_PER_DIRECTION)
	if safe_frame in NEUTRAL_FRAMES:
		return safe_frame
	# The atlas contract is neutral / left-contact / neutral / right-contact.
	# Continue the stride toward its next neutral rather than snapping backward
	# to frame zero on every stop.
	return 2 if safe_frame == 1 else 0


func _render_direction() -> String:
	if turn_reaction_remaining <= 0.0 or previous_direction == current_direction:
		return current_direction
	# Hold the old row briefly, then switch once.  This retains the 0.16-second
	# turn transition while guaranteeing that only one opaque body is rendered.
	return previous_direction if turn_reaction_remaining > TURN_BLEND_DURATION * 0.5 else current_direction


func _source_rect_for(direction: String, frame_index: int) -> Rect2:
	var safe_direction := direction if direction in DIRECTION_ORDER else DIRECTION_DOWN
	var safe_frame := posmod(frame_index, WALK_FRAMES_PER_DIRECTION)
	return Rect2(
		Vector2(float(safe_frame) * ATLAS_CELL_SIZE.x, float(int(DIRECTION_ROWS[safe_direction])) * ATLAS_CELL_SIZE.y),
		ATLAS_CELL_SIZE
	)


func _frame_for_distance(distance: float) -> int:
	return int(floor(maxf(0.0, distance) / WALK_FRAME_DISTANCE)) % WALK_FRAMES_PER_DIRECTION


func _cycle_phase_for_distance(distance: float) -> float:
	var cycle_distance := WALK_FRAME_DISTANCE * float(WALK_FRAMES_PER_DIRECTION)
	return fposmod(maxf(0.0, distance), cycle_distance) / cycle_distance


func _turn_new_direction_weight() -> float:
	if turn_reaction_remaining <= 0.0 or previous_direction == current_direction:
		return 1.0
	return 1.0 - clampf(turn_reaction_remaining / TURN_BLEND_DURATION, 0.0, 1.0)


func _face_offset_for_direction(direction: String) -> Vector2:
	match direction:
		DIRECTION_LEFT:
			return Vector2(-3.8, -44.0)
		DIRECTION_RIGHT:
			return Vector2(3.8, -44.0)
		_:
			return Vector2(0.0, -44.5)


func _reset_blink_schedule() -> void:
	_blink_active = false
	_blink_elapsed = 0.0
	# Seeded initial staggering prevents residents created on the same frame from
	# blinking together while preserving deterministic visual tests.
	_blink_wait_remaining = 0.7 + _blink_rng.randf_range(0.0, BLINK_INTERVAL_MAX - 0.7)


func _next_blink_interval() -> float:
	return _blink_rng.randf_range(BLINK_INTERVAL_MIN, BLINK_INTERVAL_MAX)


func outline_for_type(role: String) -> Color:
	var color: Color = ROLE_COLORS.get(role, ROLE_COLORS["一般居民"])
	return color.lightened(0.24) if is_dark_mode else color.darkened(0.16)


func _outfit_color() -> Color:
	return ROLE_COLORS.get(npc_type, ROLE_COLORS["一般居民"])


func _hair_color() -> Color:
	if npc_type == "老年居民":
		return Color(0.82, 0.81, 0.75)
	if npc_type in ["商人", "議員"]:
		return Color(0.24, 0.13, 0.09)
	return Color(0.32, 0.20, 0.12)


func _draw_heart(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(24):
		var angle := TAU * float(index) / 24.0
		var x := 16.0 * pow(sin(angle), 3.0)
		var y := 13.0 * cos(angle) - 5.0 * cos(2.0 * angle) - 2.0 * cos(3.0 * angle) - cos(4.0 * angle)
		points.append(center + Vector2(x / 17.0, -y / 17.0) * radius)
	draw_colored_polygon(points, color)


func _draw_sparkle(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0, -radius),
		center + Vector2(radius * 0.24, -radius * 0.24),
		center + Vector2(radius, 0),
		center + Vector2(radius * 0.24, radius * 0.24),
		center + Vector2(0, radius),
		center + Vector2(-radius * 0.24, radius * 0.24),
		center + Vector2(-radius, 0),
		center + Vector2(-radius * 0.24, -radius * 0.24),
	])
	draw_colored_polygon(points, color)


func _draw_ellipse(center: Vector2, radii: Vector2, color: Color, segments: int) -> void:
	draw_colored_polygon(_ellipse_points(center, radii, segments, false), color)


func _ellipse_points(center: Vector2, radii: Vector2, segments: int, close: bool) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count := maxi(8, segments)
	for index in range(count):
		var angle := TAU * float(index) / float(count)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	if close and not points.is_empty():
		points.append(points[0])
	return points
