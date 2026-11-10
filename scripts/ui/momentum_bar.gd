class_name MomentumBar
extends Control
## Compact resource summary; individual Momentum sources appear in the Reservoir.

const BATTERY_COL := Color("#7fd0ff")

var current := 0
var maximum := 0
var battery := 0

func setup(cur: int, mx: int, battery_value: int = 0, _cap: int = GameState.MOMENTUM_CAP) -> MomentumBar:
	current = cur
	maximum = mx
	battery = battery_value
	custom_minimum_size = Vector2(236, 54)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = (
		"Momentum: %d de %d disponíveis\nBateria do seu Reservatório: %d de %d (somente Rápido e Instantâneo)"
		% [cur, mx, battery_value, GameState.BATTERY_CAP]
	)
	return self

func _draw() -> void:
	var font := UITheme.font("heavy")
	draw_string(font, Vector2(0, 15), "MOMENTUM", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.GOLD_LIGHT)
	draw_string(font, Vector2(135, 15), "%d / %d" % [current, maximum], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UITheme.MOMENTUM)
	for i in GameState.MOMENTUM_CAP:
		var color := UITheme.MOMENTUM if i < current else Color(UITheme.MOMENTUM, 0.18)
		draw_rect(Rect2(i * 16.0, 20, 12, 5), color)
	draw_string(font, Vector2(0, 45), "BATERIA DO SEU RESERVATÓRIO", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, BATTERY_COL)
	draw_string(font, Vector2(177, 45), "%d / %d" % [battery, GameState.BATTERY_CAP], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, BATTERY_COL)
