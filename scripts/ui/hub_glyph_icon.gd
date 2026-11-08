extends Control

## Small icons drawn with shapes instead of text characters. Characters like the check mark or the
## little arrows are missing from the font the web build uses, so on phones they showed up as broken
## squares; shapes look the same everywhere.

enum Kind { CHECK, ARROW_RIGHT, ARROW_DOWN, ARROW_LEFT, ARROW_UP, CLOSE }

var kind: Kind = Kind.CHECK
var icon_color: Color = Color.WHITE

## Creates an icon of `icon_size` x `icon_size` pixels that ignores the mouse.
static func make(icon_kind: Kind, icon_size: float, color: Color) -> Control:
	var icon: Control = load("res://scripts/ui/hub_glyph_icon.gd").new()
	icon.kind = icon_kind
	icon.icon_color = color
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.size = Vector2(icon_size, icon_size)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

## Puts an icon inside a button without touching the button's text: `side` is "left", "right" or "center".
## `margin` is the distance from that edge. The icon is vertically centered.
static func attach_to_button(button: Button, icon_kind: Kind, icon_size: float, color: Color, side: String, margin: float = 14.0) -> Control:
	var icon := make(icon_kind, icon_size, color)
	icon.set_anchors_preset(Control.PRESET_TOP_LEFT)
	icon.anchor_top = 0.5
	icon.anchor_bottom = 0.5
	icon.offset_top = -icon_size / 2.0
	icon.offset_bottom = icon_size / 2.0
	match side:
		"left":
			icon.anchor_left = 0.0
			icon.anchor_right = 0.0
			icon.offset_left = margin
			icon.offset_right = margin + icon_size
		"right":
			icon.anchor_left = 1.0
			icon.anchor_right = 1.0
			icon.offset_left = -margin - icon_size
			icon.offset_right = -margin
		_:
			icon.anchor_left = 0.5
			icon.anchor_right = 0.5
			icon.offset_left = -icon_size / 2.0
			icon.offset_right = icon_size / 2.0
	button.add_child(icon)
	return icon

func _draw() -> void:
	match kind:
		Kind.CHECK:
			_draw_check()
		Kind.ARROW_RIGHT:
			_draw_arrow(Vector2.RIGHT)
		Kind.ARROW_DOWN:
			_draw_arrow(Vector2.DOWN)
		Kind.ARROW_LEFT:
			_draw_arrow(Vector2.LEFT)
		Kind.ARROW_UP:
			_draw_arrow(Vector2.UP)
		Kind.CLOSE:
			_draw_close()

## A check mark: a short stroke down to the bottom, then a long one up to the top right.
func _draw_check() -> void:
	var points := PackedVector2Array([
		Vector2(size.x * 0.12, size.y * 0.54),
		Vector2(size.x * 0.40, size.y * 0.82),
		Vector2(size.x * 0.88, size.y * 0.20),
	])
	var thickness := maxf(2.0, size.x * 0.17)
	# a dark outline underneath keeps it readable on any background
	draw_polyline(points, Color(0, 0, 0, 0.55), thickness + 2.0, true)
	draw_polyline(points, icon_color, thickness, true)

## A filled triangle pointing toward `direction` (one of the four axis directions).
func _draw_arrow(direction: Vector2) -> void:
	var center := size * 0.5
	var half := size.x * 0.4
	var sideways := direction.orthogonal()
	var triangle := PackedVector2Array([
		center + direction * half * 0.8,
		center - direction * half * 0.6 + sideways * half,
		center - direction * half * 0.6 - sideways * half,
	])
	draw_colored_polygon(triangle, icon_color)

## An "X" for close buttons.
func _draw_close() -> void:
	var center := size * 0.5
	var half := size.x * 0.32
	var thickness := maxf(2.0, size.x * 0.14)
	draw_line(center + Vector2(-half, -half), center + Vector2(half, half), icon_color, thickness, true)
	draw_line(center + Vector2(-half, half), center + Vector2(half, -half), icon_color, thickness, true)

## Draws one of the small action symbols of the chronicle (the battle log) with shapes, centered on
## `center`, `radius` pixels from the middle to the edge. Called from inside another item's _draw.
## Names: play, spark, bolt, attack, minus, plus, cross, bullet, clock, cycle, forbidden, diamond;
## anything else draws a small dot.
static func draw_action_icon(canvas: CanvasItem, icon_name: String, center: Vector2, radius: float, color: Color) -> void:
	var width := maxf(1.5, radius * 0.22)
	match icon_name:
		"play":
			canvas.draw_colored_polygon(PackedVector2Array([
				center + Vector2(-0.55, -0.85) * radius,
				center + Vector2(0.9, 0.0) * radius,
				center + Vector2(-0.55, 0.85) * radius,
			]), color)
		"spark":
			# four-pointed star: long tips up/down/left/right, short points between them
			var star := PackedVector2Array()
			for index in 8:
				var angle := index * TAU / 8.0 - PI / 2.0
				var reach := 1.0 if index % 2 == 0 else 0.32
				star.append(center + Vector2.from_angle(angle) * radius * reach)
			canvas.draw_colored_polygon(star, color)
		"bolt":
			canvas.draw_colored_polygon(PackedVector2Array([
				center + Vector2(0.25, -1.0) * radius,
				center + Vector2(-0.65, 0.1) * radius,
				center + Vector2(-0.05, 0.1) * radius,
				center + Vector2(-0.3, 1.0) * radius,
				center + Vector2(0.65, -0.2) * radius,
				center + Vector2(0.05, -0.2) * radius,
			]), color)
		"attack":
			# two crossed blades
			canvas.draw_line(center + Vector2(-0.8, -0.8) * radius, center + Vector2(0.8, 0.8) * radius, color, width * 1.2, true)
			canvas.draw_line(center + Vector2(0.8, -0.8) * radius, center + Vector2(-0.8, 0.8) * radius, color, width * 1.2, true)
			canvas.draw_circle(center, radius * 0.22, color)
		"minus":
			canvas.draw_line(center + Vector2(-0.7, 0.0) * radius, center + Vector2(0.7, 0.0) * radius, color, width * 1.3, true)
		"plus":
			canvas.draw_line(center + Vector2(-0.7, 0.0) * radius, center + Vector2(0.7, 0.0) * radius, color, width * 1.3, true)
			canvas.draw_line(center + Vector2(0.0, -0.7) * radius, center + Vector2(0.0, 0.7) * radius, color, width * 1.3, true)
		"cross":
			canvas.draw_line(center + Vector2(-0.6, -0.6) * radius, center + Vector2(0.6, 0.6) * radius, color, width * 1.3, true)
			canvas.draw_line(center + Vector2(-0.6, 0.6) * radius, center + Vector2(0.6, -0.6) * radius, color, width * 1.3, true)
		"bullet":
			canvas.draw_circle(center, radius * 0.4, color)
		"clock":
			canvas.draw_arc(center, radius * 0.85, 0.0, TAU, 24, color, width, true)
			canvas.draw_line(center, center + Vector2(0.0, -0.55) * radius, color, width, true)
			canvas.draw_line(center, center + Vector2(0.4, 0.2) * radius, color, width, true)
		"cycle":
			# an open circle with an arrow head at its end
			canvas.draw_arc(center, radius * 0.7, 0.0, TAU * 0.78, 20, color, width, true)
			var tip := center + Vector2.from_angle(TAU * 0.78) * radius * 0.7
			canvas.draw_colored_polygon(PackedVector2Array([
				tip + Vector2(-0.45, -0.1) * radius,
				tip + Vector2(0.45, -0.25) * radius,
				tip + Vector2(0.0, 0.5) * radius,
			]), color)
		"forbidden":
			canvas.draw_arc(center, radius * 0.8, 0.0, TAU, 24, color, width, true)
			canvas.draw_line(center + Vector2(-0.57, 0.57) * radius, center + Vector2(0.57, -0.57) * radius, color, width, true)
		"diamond":
			canvas.draw_polyline(PackedVector2Array([
				center + Vector2(0.0, -0.8) * radius,
				center + Vector2(0.65, 0.0) * radius,
				center + Vector2(0.0, 0.8) * radius,
				center + Vector2(-0.65, 0.0) * radius,
				center + Vector2(0.0, -0.8) * radius,
			]), color, width, true)
		_:
			canvas.draw_circle(center, radius * 0.22, color)
