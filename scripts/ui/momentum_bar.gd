class_name MomentumBar
extends Control
## Compact resource summary; individual Momentum sources appear in the Reservoir.

const BATTERY_COL := Color("#7fd0ff")

var current := 0
var maximum := 0
var battery := 0
var floating := 0
var momentum_ceiling := GameState.MOMENTUM_CAP
var battery_ceiling := GameState.BATTERY_CAP

func setup(
	cur: int, mx: int, battery_value: int = 0, momentum_cap_value: int = GameState.MOMENTUM_CAP, floating_value: int = 0,
	battery_cap_value: int = GameState.BATTERY_CAP,
) -> MomentumBar:
	current = cur
	maximum = mx
	battery = battery_value
	floating = floating_value
	momentum_ceiling = momentum_cap_value
	battery_ceiling = battery_cap_value
	custom_minimum_size = Vector2(236, 54)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_PASS
	var momentum_tip := "Momentum: %d de %d disponíveis" % [cur, mx]
	if floating > 0:
		momentum_tip = "Momentum: %d do Reservatório + %d flutuante = %d (expira no fim do turno)" % [
			cur, floating, cur + floating,
		]
	tooltip_text = "%s\nBateria do seu Reservatório: %d de %d (somente Rápido e Instantâneo)" % [
		momentum_tip, battery_value, battery_ceiling,
	]
	return self

func _draw() -> void:
	var font := UITheme.font("heavy")
	draw_string(font, Vector2(0, 15), "MOMENTUM", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.GOLD_LIGHT)
	var momentum_text := "%d / %d" % [current, maximum]
	if floating > 0:
		momentum_text = "%d + %d" % [current, floating]
	draw_string(font, Vector2(135, 15), momentum_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UITheme.MOMENTUM)
	# the cells always fill the same width, so a higher ceiling (Agiota's 15) makes them thinner
	var cell_pitch := GameState.MOMENTUM_CAP * 16.0 / momentum_ceiling
	for i in momentum_ceiling:
		var color := Color(UITheme.MOMENTUM, 0.18)
		if i < current:
			color = UITheme.MOMENTUM
		elif i < current + floating:
			color = Color("#50cfff")
		draw_rect(Rect2(i * cell_pitch, 20, cell_pitch - 4.0, 5), color)
	draw_string(font, Vector2(0, 45), "BATERIA", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, BATTERY_COL)
	_draw_battery_icon(Rect2(64, 32, 44, 18))
	draw_string(font, Vector2(120, 46), "%d / %d" % [battery, battery_ceiling], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, BATTERY_COL)

## A battery outline with one bar inside per point of Bateria; empty points are dim.
func _draw_battery_icon(body: Rect2) -> void:
	var outline_width := 2.0
	draw_rect(body, BATTERY_COL, false, outline_width)
	var terminal := Rect2(body.end.x, body.position.y + body.size.y * 0.3, 4, body.size.y * 0.4)
	draw_rect(terminal, BATTERY_COL)
	var padding := 4.0
	var gap := 3.0
	var cell_count := battery_ceiling
	var cell_width := (body.size.x - padding * 2 - gap * (cell_count - 1)) / cell_count
	var cell_height := body.size.y - padding * 2
	for i in cell_count:
		var cell_x := body.position.x + padding + i * (cell_width + gap)
		var cell := Rect2(cell_x, body.position.y + padding, cell_width, cell_height)
		var color := BATTERY_COL if i < battery else Color(BATTERY_COL, 0.15)
		draw_rect(cell, color)
