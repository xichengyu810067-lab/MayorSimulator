class_name SemanticPalette
extends RefCounted

# Shared UI-only semantic colors. World, terrain, NPC and illustration colors
# intentionally remain outside this palette.
const LIGHT := {
	"surface_base": Color("f7f9fc"),
	"surface_raised": Color("ffffff"),
	"surface_muted": Color("edf2f7"),
	"text_primary": Color("172033"),
	"text_secondary": Color("405066"),
	"text_on_accent": Color("ffffff"),
	"text_disabled": Color("405066"),
	"border_default": Color("637486"),
	"border_focus": Color("006d8f"),
	"border_disabled": Color("718092"),
	"action_primary": Color("006d8f"),
	"action_primary_hover": Color("005675"),
	"action_primary_disabled": Color("aab7c4"),
	"success": Color("067a46"),
	"caution": Color("946200"),
	"danger": Color("d83227"),
	"scrim": Color(0.04, 0.06, 0.09, 0.70),
}

const DARK := {
	"surface_base": Color("121a24"),
	"surface_raised": Color("192535"),
	"surface_muted": Color("223142"),
	"text_primary": Color("f5f7fa"),
	"text_secondary": Color("c6d0da"),
	"text_on_accent": Color("ffffff"),
	"text_disabled": Color("a8b2be"),
	"border_default": Color("7d93a8"),
	"border_focus": Color("5ad4ff"),
	"border_disabled": Color("7d93a8"),
	"action_primary": Color("006f98"),
	"action_primary_hover": Color("005674"),
	"action_primary_disabled": Color("465a6c"),
	"success": Color("59d890"),
	"caution": Color("f6c453"),
	"danger": Color("d83227"),
	"scrim": Color(0.005, 0.01, 0.02, 0.82),
}


static func color_for(dark_mode: bool, role: String) -> Color:
	var palette: Dictionary = DARK if dark_mode else LIGHT
	return palette.get(role, palette["text_primary"]) as Color


static func roles(dark_mode: bool) -> Dictionary:
	return (DARK if dark_mode else LIGHT).duplicate()


static func contrast_ratio(first: Color, second: Color) -> float:
	var lighter := maxf(_relative_luminance(first), _relative_luminance(second))
	var darker := minf(_relative_luminance(first), _relative_luminance(second))
	return (lighter + 0.05) / (darker + 0.05)


static func _relative_luminance(color: Color) -> float:
	var channels := [color.r, color.g, color.b]
	for index in channels.size():
		var channel := float(channels[index])
		channels[index] = channel / 12.92 if channel <= 0.04045 else pow((channel + 0.055) / 1.055, 2.4)
	return float(channels[0]) * 0.2126 + float(channels[1]) * 0.7152 + float(channels[2]) * 0.0722
