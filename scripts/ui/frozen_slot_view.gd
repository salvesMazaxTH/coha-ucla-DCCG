class_name FrozenSlotView
extends Control
## An empty board slot frozen by Rei Gelado, drawn with the same ice language as a frozen unit
## (CardView): a deep blue veil, rime on top, crystals standing on the bottom, icicles hanging from the
## top, a big slowly turning snowflake, twinkling glints and a white frosted crust around the edge.
## There is no card inside, so it also shows a dark empty "hole" the ice has sealed shut.

## How far the ice has grown (0 = bare, 1 = fully covered). Tweened by Main when the slot freezes.
var frost_grow := 1.0:
	set(v):
		frost_grow = v
		queue_redraw()

## 0..1 while the freezing-moment flash and shockwaves play, 0 otherwise.
var frost_burst := 0.0:
	set(v):
		frost_burst = v
		queue_redraw()

## Which player's lane this slot belongs to (Main uses it to find the right tiles when a freeze happens).
var owner_player := -1

var _animation_time := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_animation_time += delta
	queue_redraw() # the snowflake turns and the glints twinkle all the time

func _draw() -> void:
	var scale_factor := size.x / CardView.BASE.x
	var frame := Rect2(Vector2.ZERO, size)
	var corner_radius := 8.0 * scale_factor
	var grow := frost_grow
	var deep := CardView.FROST_DEEP
	# the sealed hole: dark teal at the bottom fading to a bluer top, as if seen through thick ice
	_rounded_fill(frame, corner_radius, Color("#06222e"))
	_rounded_fill(frame, corner_radius, Color(deep, 0.38 * grow))
	# rime: white frost thickest at the top edge
	var rime_height := size.y * 0.4
	for strip in 12:
		var strip_top := rime_height * strip / 12.0
		var strip_alpha := 0.5 * grow * (1.0 - strip / 12.0)
		draw_rect(Rect2(Vector2(corner_radius * 0.5, strip_top + 2.0), Vector2(size.x - corner_radius, rime_height / 12.0 + 1.0)), Color(1, 1, 1, strip_alpha))
	# ice piling up from the bottom, with crystals standing on it
	var pile_height := size.y * 0.35
	for strip in 10:
		var strip_top := size.y - pile_height + pile_height * strip / 10.0
		var strip_alpha := 0.6 * grow * (strip + 1) / 10.0
		draw_rect(Rect2(Vector2(corner_radius * 0.5, strip_top), Vector2(size.x - corner_radius, pile_height / 10.0 + 1.0)), Color(0.85, 0.96, 1, strip_alpha))
	for crystal in CardView.FROST_CRYSTALS:
		var base := Vector2(size.x * crystal[0], size.y - 2.0 * scale_factor)
		var half_width: float = crystal[2] * scale_factor
		var tip := base + Vector2(0, -crystal[1] * scale_factor * 1.5 * grow)
		draw_colored_polygon(PackedVector2Array([base + Vector2(-half_width, 0), tip, base + Vector2(half_width, 0)]), Color(0.7, 0.92, 1.0, 0.92 * grow))
		draw_colored_polygon(PackedVector2Array([base, tip, base + Vector2(half_width, 0)]), Color(1, 1, 1, 0.85 * grow)) # the lit facet
	_draw_snowflake(frame.get_center(), size.x * 0.3 * (0.4 + 0.6 * grow), scale_factor, Color(1, 1, 1, 0.85 * grow))
	# the crust: a bright white edge with a deep blue line just inside it
	_rounded_line(frame.grow(-1.0 * scale_factor), corner_radius, Color(1, 1, 1, 0.95 * grow), 2.8 * scale_factor)
	_rounded_line(frame.grow(-4.0 * scale_factor), maxf(corner_radius - 2.0 * scale_factor, 0.0), Color(deep, 0.7 * grow), 1.6 * scale_factor)
	for icicle in CardView.FROST_ICICLES:
		var icicle_base := Vector2(size.x * icicle[0], 1.0 * scale_factor)
		var icicle_half_width: float = icicle[2] * scale_factor
		var icicle_tip := icicle_base + Vector2(0, icicle[1] * scale_factor * 1.4 * grow)
		draw_colored_polygon(PackedVector2Array([icicle_base + Vector2(-icicle_half_width, 0), icicle_tip, icicle_base + Vector2(icicle_half_width, 0)]), Color(0.72, 0.93, 1.0, 0.95 * grow))
		draw_colored_polygon(PackedVector2Array([icicle_base, icicle_tip, icicle_base + Vector2(-icicle_half_width, 0)]), Color(1, 1, 1, 0.9 * grow))
		draw_polyline(PackedVector2Array([icicle_base + Vector2(-icicle_half_width, 0), icicle_tip, icicle_base + Vector2(icicle_half_width, 0)]), Color(deep.darkened(0.2), 0.8 * grow), 0.8 * scale_factor, true)
	for glint_index in CardView.FROST_GLINTS.size():
		var twinkle := maxf(0.0, sin(_animation_time * 2.2 + glint_index * 1.9))
		if twinkle > 0.05:
			_draw_glint(CardView.FROST_GLINTS[glint_index] * size, (3.0 + 6.0 * twinkle) * scale_factor, Color(1, 1, 1, twinkle * grow))
	if frost_burst > 0.0 and frost_burst < 1.0:
		var reach := 1.0 - pow(1.0 - frost_burst, 3.0)
		var fade := 1.0 - frost_burst
		_rounded_fill(frame, corner_radius, Color(0.85, 0.97, 1.0, 0.75 * fade * fade))
		_rounded_line(frame.grow((4.0 + 44.0 * reach) * scale_factor), corner_radius + 16.0 * reach * scale_factor, Color(1, 1, 1, 0.95 * pow(fade, 1.4)), (6.0 - 4.0 * reach) * scale_factor)
		var late_reach := 1.0 - pow(1.0 - clampf(frost_burst * 1.3 - 0.15, 0.0, 1.0), 3.0)
		_rounded_line(frame.grow((4.0 + 30.0 * late_reach) * scale_factor), corner_radius + 10.0 * late_reach * scale_factor, Color(deep, 0.8 * pow(fade, 1.4)), (5.0 - 3.0 * late_reach) * scale_factor)

## A six-armed snowflake with side branches, slowly turning.
func _draw_snowflake(center: Vector2, arm_length: float, scale_factor: float, color: Color) -> void:
	for arm_index in 6:
		var direction := Vector2.from_angle(_animation_time * 0.15 + arm_index * TAU / 6.0)
		draw_line(center, center + direction * arm_length, color, 2.4 * scale_factor, true)
		for branch_at in [0.55, 0.8]:
			var branch_base: Vector2 = center + direction * arm_length * branch_at
			for side in [-1.0, 1.0]:
				draw_line(branch_base, branch_base + direction.rotated(side * 0.9) * arm_length * 0.28, color, 1.8 * scale_factor, true)
	var core_radius := arm_length * 0.14
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -core_radius), center + Vector2(core_radius, 0), center + Vector2(0, core_radius), center + Vector2(-core_radius, 0)]), Color(1, 1, 1, color.a))

## A four-pointed star of light.
func _draw_glint(center: Vector2, radius: float, color: Color) -> void:
	var inner := radius * 0.18
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -radius), center + Vector2(inner, -inner), center + Vector2(radius, 0), center + Vector2(inner, inner),
		center + Vector2(0, radius), center + Vector2(-inner, inner), center + Vector2(-radius, 0), center + Vector2(-inner, -inner)]), color)

func _rounded_fill(rect: Rect2, radius: float, color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(radius))
	style.anti_aliasing = true
	draw_style_box(style, rect)

func _rounded_line(rect: Rect2, radius: float, color: Color, width: float) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.draw_center = false
	style.border_color = color
	style.set_border_width_all(maxi(1, int(round(width))))
	style.set_corner_radius_all(int(radius))
	style.anti_aliasing = true
	draw_style_box(style, rect)
