class_name MomentumBar
extends Control
## Momentum as a row of crystals: lit (available), spent (hollow) and locked
## (not unlocked yet this game), with an "x/y" readout, then the Reserva: up to
## RESERVE_CAP smaller arcane crystals that only pay for spells and abilities.

const RESERVE_COL := Color("#7fd0ff")

var current := 0
var maximum := 0
var reserve := 0

func setup(cur: int, mx: int, res: int = 0) -> MomentumBar:
	current = cur
	maximum = mx
	reserve = res
	custom_minimum_size = Vector2(290, 30)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = "Momentum: %d de %d disponíveis
Reserva: %d de %d (só feitiços e habilidades)" % [cur, mx, res, GameState.RESERVE_CAP]
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
	var rx := x + font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x + 12
	for i in GameState.RESERVE_CAP:
		var c := Vector2(rx + i * 13, 15)
		var pts := PackedVector2Array([c + Vector2(0, -9), c + Vector2(5.5, -2), c + Vector2(0, 9), c + Vector2(-5.5, -2)])
		var outline := pts + PackedVector2Array([pts[0]])
		if i < reserve:
			draw_circle(c, 8, Color(RESERVE_COL, 0.22))
			draw_colored_polygon(pts, RESERVE_COL)
			draw_colored_polygon(PackedVector2Array([pts[0], pts[1], c + Vector2(0, -1), pts[3]]), Color("#e6f7ff"))
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -1), pts[1], pts[2]]), RESERVE_COL.darkened(0.4))
			draw_polyline(outline, Color("#f0faff"), 1.0, true)
		else:
			draw_colored_polygon(pts, Color(RESERVE_COL.darkened(0.75), 0.7))
			draw_polyline(outline, Color(RESERVE_COL, 0.4), 1.0, true)
	var rt := "%d/%d" % [reserve, GameState.RESERVE_CAP]
	var rtx := rx + GameState.RESERVE_CAP * 13 - 1
	draw_string_outline(font, Vector2(rtx, 22), rt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 4, Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(rtx, 22), rt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, RESERVE_COL)
