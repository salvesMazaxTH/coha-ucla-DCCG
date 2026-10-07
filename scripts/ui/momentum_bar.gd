class_name MomentumBar
extends Control
## Momentum as a row of crystals: lit (available), spent (hollow) and locked
## (not unlocked yet this game), with an "x/y" readout.

var current := 0
var maximum := 0

func setup(cur: int, mx: int) -> MomentumBar:
	current = cur
	maximum = mx
	custom_minimum_size = Vector2(240, 30)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = "Momentum: %d de %d disponíveis" % [cur, mx]
	return self

func _draw() -> void:
	var font := UITheme.font("heavy")
	var cap := GameState.MOMENTUM_CAP
	var step := 16.0
	for i in cap:
		var c := Vector2(9 + i * step, 15)
		var pts := PackedVector2Array([c + Vector2(0, -12), c + Vector2(7, -3), c + Vector2(0, 12), c + Vector2(-7, -3)])
		var outline := pts + PackedVector2Array([pts[0]])
		if i < current:
			draw_circle(c, 10, Color(UITheme.MOMENTUM, 0.18))
			draw_colored_polygon(pts, UITheme.MOMENTUM)
			draw_colored_polygon(PackedVector2Array([pts[0], pts[1], c + Vector2(0, -1), pts[3]]), Color("#fff4b8"))
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -1), pts[1], pts[2]]), UITheme.MOMENTUM.darkened(0.35))
			draw_polyline(outline, Color("#fffbe0"), 1.0, true)
		elif i < maximum:
			draw_colored_polygon(pts, Color(UITheme.MOMENTUM.darkened(0.7), 0.85))
			draw_polyline(outline, Color(UITheme.MOMENTUM, 0.55), 1.2, true)
		else:
			draw_colored_polygon(pts, Color(0, 0, 0, 0.4))
			draw_polyline(outline, Color(1, 1, 1, 0.12), 1.0, true)
	var t := "%d/%d" % [current, maximum]
	var x := 9 + cap * step - 4
	draw_string_outline(font, Vector2(x, 23), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, 4, Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(x, 23), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("#ffe680"))
