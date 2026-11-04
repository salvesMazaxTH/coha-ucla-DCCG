extends Control

## Red diagonal ribbon with white "BANIDO" text, drawn across whatever it is added to (a deck tile, a
## Leader tile, the hub showcase). It fills its parent, ignores the mouse, and relies on the parent
## having clip_contents on so the ends of the band are cut at the tile border.

const RIBBON_COLOR := Color(0.72, 0.07, 0.09, 0.94)
const RIBBON_EDGE_COLOR := Color(0.3, 0.02, 0.03, 0.95)
const RIBBON_TEXT := "BANIDO"
const TILT_RADIANS := -0.5 # negative = rising to the right

## Adds a ribbon that covers `parent`. The ribbon's size follows the parent's size.
static func attach(parent: Control) -> Control:
	var ribbon: Control = load("res://scripts/ui/banned_ribbon.gd").new()
	ribbon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(ribbon)
	return ribbon

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)

func _draw() -> void:
	# The band is sized from the shorter side so it stays readable on small tiles and does not swallow big ones.
	var band_height := clampf(minf(size.x, size.y) * 0.2, 22.0, 70.0)
	var band_length := size.length() * 1.3
	var font := UITheme.font("heavy")
	var font_size := int(band_height * 0.68)
	draw_set_transform(size * 0.5, TILT_RADIANS, Vector2.ONE)
	var band := Rect2(Vector2(-band_length * 0.5, -band_height * 0.5), Vector2(band_length, band_height))
	draw_rect(band, RIBBON_COLOR)
	draw_rect(band, RIBBON_EDGE_COLOR, false, 2.0)
	var text_width := font.get_string_size(RIBBON_TEXT, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	var baseline := font.get_ascent(font_size) - font.get_height(font_size) * 0.5
	draw_string(font, Vector2(-text_width * 0.5, baseline), RIBBON_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
