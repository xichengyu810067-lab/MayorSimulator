extends Control

var is_dark_mode := false
var bg_texture_rect: TextureRect

func _ready() -> void:
	var tex = load("res://assets/images/world/backgrounds/city-map-background.png")
	if tex:
		bg_texture_rect = TextureRect.new()
		bg_texture_rect.texture = tex
		# Set expand mode so it can fill the area
		bg_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# Keep aspect covered ensures it fills the area without stretching weirdly
		bg_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg_texture_rect)
		set_dark_mode(is_dark_mode)

func set_dark_mode(enabled: bool) -> void:
	is_dark_mode = enabled
	if bg_texture_rect:
		if is_dark_mode:
			# Simple dimming for dark mode
			bg_texture_rect.modulate = Color(0.6, 0.6, 0.7)
		else:
			bg_texture_rect.modulate = Color.WHITE
