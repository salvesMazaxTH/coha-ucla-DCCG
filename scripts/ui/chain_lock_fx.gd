class_name ChainLockFx
extends RefCounted
## "Proibida de jogar": a padlock hanging where two crossed chains meet, drawn over a card that a play
## restriction currently bars (Liam Tornagron's "can't play cards that cost 5 or more", and any other
## restrict_play effect). Reusable: any CanvasItem can call draw() from its own _draw(), giving the
## rectangle and the outline of the card face.
##
## The caller keeps three animation values, each from 0 to 1 (CardView tweens them):
##   lock_in  0 = nothing yet, 1 = chained and closed. The chains whip in from the corners, the padlock
##            drops in and its shackle slams shut at SNAP_AT with a burst of sparks.
##   release  0 = still locked, 1 = gone. The shackle springs open, the chains go slack and everything fades.
##   rattle   1 = just tugged (the player tried to drag the card), dying down to 0. The padlock jerks,
##            the chains shiver and the card flushes red for a moment.
## The resting motion (a slow sway and a glint running over the padlock every few seconds) comes from `time`.
## It is all plain shapes, about a hundred small ones per card, so it stays cheap on phones.

const LOCK_IN_SECONDS := 0.75
const RELEASE_SECONDS := 0.45
const RATTLE_SECONDS := 0.5
const SNAP_AT := 0.78 ## the moment of lock_in at which the shackle slams shut (and the "clank" sound plays)

## Where the chains cross and the padlock hangs, as a fraction of the card. High enough that the whole
## padlock stays inside the part of a hand card that is on screen (Main hides the bottom 22%).
const LOCK_POINT := Vector2(0.5, 0.43)
## The four ends of the two chains, as fractions of the card. Each pair of opposite corners passes
## through LOCK_POINT, so the chains cross exactly under the padlock.
const CHAIN_ENDS := [Vector2(0.03, 0.06), Vector2(0.97, 0.06), Vector2(0.97, 0.80), Vector2(0.03, 0.80)]

## Chain links, in base card pixels (the card is 120 x 170 at scale 1).
const LINK_STEP := 6.6 ## distance between the centres of two links in a row
const LINK_HALF_LENGTH := 4.4
const LINK_HALF_WIDTH := 2.5

## Padlock, in base card pixels, measured from the point where it hangs (the chain crossing).
const SHACKLE_RADIUS := 8.0 ## radius of the arch of the U-shaped shackle (its centre line)
const SHACKLE_THICKNESS := 4.2
const SHACKLE_LEG_BOTTOM := 11.0 ## where the legs of the closed shackle disappear into the body
const SHACKLE_OPEN_LIFT := 6.5 ## how far the shackle rises when the padlock is open
const BODY_RECT := Rect2(-15.0, 8.0, 30.0, 24.0)
const BODY_CORNER := 4.5
const KEYHOLE_CENTER := Vector2(0.0, 18.5)

const VEIL := Color(0.13, 0.15, 0.19, 0.42) ## cold grey dusk over the whole card: "out of reach for now"
const RATTLE_TINT := Color(0.9, 0.12, 0.08)
const OUTLINE := Color("#0b0d10")
const STEEL := Color("#9aa4ae")
const STEEL_DARK := Color("#6c7680")
const STEEL_LIGHT := Color("#eef3f7")
const IRON_TOP := Color("#626c78")
const IRON_BOTTOM := Color("#1f232a")
const BRASS := Color("#d8b25a")
const BRASS_LIGHT := Color("#fff0b8")
const SPARK := Color(1.0, 0.92, 0.66)

const IDLE_SWAY := 0.05 ## radians (about 3 degrees) the padlock swings while at rest
const GLINT_PERIOD := 3.4 ## seconds between two glints on the padlock
const GLINT_SECONDS := 0.55

## Draws the whole effect. `base` is the transform the caller is drawing the card face with (it is set
## again at the end, so the caller can keep drawing). `card` and `card_outline` are in face coordinates,
## `s` is the face size divided by the base card size.
static func draw(canvas: CanvasItem, base: Transform2D, card: Rect2, card_outline: PackedVector2Array, s: float,
		time: float, lock_in: float, release: float, rattle: float) -> void:
	if lock_in <= 0.0 or release >= 1.0:
		return
	canvas.draw_set_transform_matrix(base)
	var fade := 1.0 - smoothstep(0.25, 1.0, release) ## everything fades out while the lock is released
	var tug_phase := (1.0 - rattle) * TAU * 3.5 ## runs while a rattle dies down: three and a half shakes
	var tug := rattle * sin(tug_phase) ## -1..1, a decaying back-and-forth jerk
	var detail := GraphicsQuality.effect_detail >= 0.7 ## phones skip the thinnest highlights

	# 1. The veil: the card dims to a cold grey, and flushes red for a moment when tugged.
	var veil := VEIL
	veil.a *= smoothstep(0.0, 0.4, lock_in) * fade
	canvas.draw_colored_polygon(card_outline, veil)
	if rattle > 0.0:
		canvas.draw_colored_polygon(card_outline, Color(RATTLE_TINT, 0.24 * rattle * fade))

	# 2. The chains: each half whips in from its corner toward the padlock, and goes slack when released.
	var hang_point := card.position + card.size * LOCK_POINT
	var reveal := smoothstep(0.0, 0.55, lock_in)
	var slack := release * release * 34.0 * s
	var shiver := rattle * 1.6 * s
	for end_fraction in CHAIN_ENDS:
		var chain_end: Vector2 = card.position + card.size * end_fraction
		_draw_chain_half(canvas, chain_end, hang_point, reveal, s, fade, shiver, tug_phase, slack, detail)

	# 3. The padlock: drops in from above with a little overshoot, sways at rest, jerks when tugged,
	# and tumbles down when released.
	var fall := smoothstep(0.3, SNAP_AT, lock_in)
	var drop_offset := (1.0 - _back_out(fall)) * -26.0 * s
	var tumble := release * release
	var lock_alpha := smoothstep(0.3, 0.42, lock_in) * fade
	var angle := IDLE_SWAY * sin(time * 1.6) + 0.32 * tug + 0.6 * tumble
	var pop := 1.0 + 0.25 * (1.0 - fall)
	var hang_position := hang_point + Vector2(0.0, drop_offset + tumble * 40.0 * s)
	canvas.draw_set_transform_matrix(base * Transform2D(angle, Vector2(pop, pop), 0.0, hang_position))
	# the shackle stays open until the snap, then slams down; it springs open again on release
	var lift := SHACKLE_OPEN_LIFT * (1.0 - smoothstep(SNAP_AT - 0.06, SNAP_AT, lock_in))
	lift = maxf(lift, SHACKLE_OPEN_LIFT * smoothstep(0.0, 0.25, release))
	_draw_padlock(canvas, s, lock_alpha, lift, time, detail)
	if lock_in > SNAP_AT and lock_in < 1.0:
		_draw_clank(canvas, s, (lock_in - SNAP_AT) / (1.0 - SNAP_AT))
	canvas.draw_set_transform_matrix(base)

## One half of a chain, from its loose end at the card edge to the padlock. Links alternate between one
## seen face-on (an oval ring) and one seen edge-on (a short bar), which is what makes it read as a chain.
static func _draw_chain_half(canvas: CanvasItem, from: Vector2, to: Vector2, reveal: float, s: float, alpha: float,
		shiver: float, tug_phase: float, slack: float, detail: bool) -> void:
	var direction := (to - from).normalized()
	var across := direction.orthogonal()
	var full_length := from.distance_to(to)
	var shown_length := full_length * reveal
	var step := LINK_STEP * s
	var link_count := int(shown_length / step) + 1
	for link_index in link_count:
		var along := link_index * step
		var toward_lock := along / full_length ## 0 at the card edge, 1 under the padlock
		var link_center := from + direction * along
		link_center += across * shiver * sin(tug_phase * 1.7 + link_index * 1.3)
		link_center.y += slack * (0.35 + 0.65 * toward_lock) # the loose middle sags more than the ends
		# while whipping in, the leading links glint brighter
		var leading_glow := 0.0
		if reveal < 1.0:
			leading_glow = 1.0 - clampf((shown_length - along) / (step * 2.5), 0.0, 1.0)
		if link_index % 2 == 0:
			_draw_face_on_link(canvas, link_center, direction, across, s, alpha, leading_glow, detail)
		else:
			_draw_edge_on_link(canvas, link_center, direction, across, s, alpha, leading_glow, detail)

static func _draw_face_on_link(canvas: CanvasItem, center: Vector2, direction: Vector2, across: Vector2, s: float,
		alpha: float, glow: float, detail: bool) -> void:
	var ring := PackedVector2Array()
	for point_index in 13:
		var a := point_index * TAU / 12.0
		ring.append(center + direction * cos(a) * LINK_HALF_LENGTH * s + across * sin(a) * LINK_HALF_WIDTH * s)
	canvas.draw_polyline(ring, Color(OUTLINE, 0.9 * alpha), 2.7 * s)
	canvas.draw_polyline(ring, Color(STEEL.lerp(STEEL_LIGHT, glow), alpha), 1.3 * s)
	if detail:
		# a short bright arc on the side that faces the light (the top)
		var lit_side := ring.slice(7, 11) if across.y > 0.0 else ring.slice(1, 5)
		canvas.draw_polyline(lit_side, Color(STEEL_LIGHT, 0.8 * alpha), 0.6 * s)

static func _draw_edge_on_link(canvas: CanvasItem, center: Vector2, direction: Vector2, across: Vector2, s: float,
		alpha: float, glow: float, detail: bool) -> void:
	var half := direction * LINK_HALF_LENGTH * 0.95 * s
	canvas.draw_line(center - half, center + half, Color(OUTLINE, 0.9 * alpha), 3.2 * s)
	canvas.draw_line(center - half, center + half, Color(STEEL_DARK.lerp(STEEL_LIGHT, glow), alpha), 1.6 * s)
	if detail:
		var toward_top := -0.45 if across.y > 0.0 else 0.45 # the highlight sits on the upper edge of the bar
		var lit := across * toward_top * s
		canvas.draw_line(center - half * 0.7 + lit, center + half * 0.7 + lit, Color(STEEL_LIGHT, 0.55 * alpha), 0.5 * s)

## The padlock itself, drawn around its hanging point (0, 0): the shackle loops over the chain crossing
## and the body hangs below it. `lift` raises the shackle out of the body (an open padlock).
static func _draw_padlock(canvas: CanvasItem, s: float, alpha: float, lift: float, time: float, detail: bool) -> void:
	if alpha <= 0.0:
		return
	var body := Rect2(BODY_RECT.position * s, BODY_RECT.size * s)
	var body_outline := _rounded_rect_points(body, BODY_CORNER * s)
	# soft drop shadow on the card
	var shadow_outline := PackedVector2Array()
	for point in body_outline:
		shadow_outline.append(point + Vector2(2.0, 3.0) * s)
	canvas.draw_colored_polygon(shadow_outline, Color(0, 0, 0, 0.35 * alpha))

	# shackle: a thick U, drawn behind the body so its legs vanish into it
	var shackle := PackedVector2Array()
	var leg_bottom := (SHACKLE_LEG_BOTTOM - lift) * s
	var arch_center := Vector2(0.0, -lift * s)
	var radius := SHACKLE_RADIUS * s
	shackle.append(Vector2(-radius, leg_bottom))
	for point_index in 13:
		var a := PI + point_index * PI / 12.0
		shackle.append(arch_center + Vector2(cos(a), sin(a)) * radius)
	shackle.append(Vector2(radius, leg_bottom))
	canvas.draw_polyline(shackle, Color(OUTLINE, alpha), (SHACKLE_THICKNESS + 2.0) * s)
	canvas.draw_polyline(shackle, Color(STEEL, alpha), SHACKLE_THICKNESS * s)
	if detail:
		var shine := PackedVector2Array()
		for point_index in 7:
			var a := PI * 1.1 + point_index * PI * 0.4 / 6.0
			shine.append(arch_center + Vector2(cos(a), sin(a)) * (radius - 0.6 * s))
		canvas.draw_polyline(shine, Color(STEEL_LIGHT, 0.85 * alpha), 1.1 * s)

	# body: dark iron, lighter at the top, with a brass rim, four rivets and a keyhole
	var shades := PackedColorArray()
	for point in body_outline:
		var depth := (point.y - body.position.y) / body.size.y
		shades.append(Color(IRON_TOP.lerp(IRON_BOTTOM, depth), alpha))
	canvas.draw_polygon(body_outline, shades)
	var closed_outline := body_outline.duplicate()
	closed_outline.append(body_outline[0])
	canvas.draw_polyline(closed_outline, Color(OUTLINE, alpha), 2.2 * s)
	var rim := _rounded_rect_points(body.grow(-2.2 * s), (BODY_CORNER - 2.0) * s)
	rim.append(rim[0])
	canvas.draw_polyline(rim, Color(BRASS, 0.95 * alpha), 1.2 * s)
	canvas.draw_line(Vector2(body.position.x + 5.0 * s, body.position.y + 4.2 * s),
		Vector2(body.end.x - 5.0 * s, body.position.y + 4.2 * s), Color(1, 1, 1, 0.22 * alpha), 1.2 * s)
	for corner_sign in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var rivet: Vector2 = body.get_center() + corner_sign * (body.size / 2.0 - Vector2(4.6, 4.6) * s)
		canvas.draw_circle(rivet, 1.3 * s, Color(BRASS, alpha))
		canvas.draw_circle(rivet + Vector2(-0.4, -0.4) * s, 0.5 * s, Color(BRASS_LIGHT, alpha))
	var keyhole := KEYHOLE_CENTER * s
	canvas.draw_circle(keyhole + Vector2(0, 1.2) * s, 4.6 * s, Color(BRASS, alpha))
	canvas.draw_circle(keyhole, 2.6 * s, Color(OUTLINE, alpha))
	canvas.draw_colored_polygon(PackedVector2Array([keyhole + Vector2(-1.6, 0.8) * s, keyhole + Vector2(1.6, 0.8) * s,
		keyhole + Vector2(0.9, 6.2) * s, keyhole + Vector2(-0.9, 6.2) * s]), Color(OUTLINE, alpha))

	# every few seconds a glint of light runs across the body
	var glint := fmod(time, GLINT_PERIOD) / GLINT_SECONDS
	if glint < 1.0:
		var band_x := lerpf(body.position.x - 8.0 * s, body.end.x + 2.0 * s, glint)
		var band := PackedVector2Array([Vector2(band_x, body.end.y), Vector2(band_x + 4.5 * s, body.end.y),
			Vector2(band_x + 10.5 * s, body.position.y), Vector2(band_x + 6.0 * s, body.position.y)])
		for piece in Geometry2D.intersect_polygons(band, body_outline):
			canvas.draw_colored_polygon(piece, Color(1, 1, 1, 0.32 * sin(glint * PI) * alpha))

## The instant the shackle slams shut (`progress` 0..1): a white flash, a brass shockwave ring and
## sparks flying out of the shackle.
static func _draw_clank(canvas: CanvasItem, s: float, progress: float) -> void:
	var fading := 1.0 - progress
	var spread := 1.0 - pow(fading, 3.0) # fast at first, then slowing down
	var origin := Vector2(0.0, BODY_RECT.position.y * s)
	canvas.draw_circle(origin, 9.0 * s, Color(1, 1, 1, 0.55 * fading * fading))
	canvas.draw_arc(origin, lerpf(6.0, 36.0, spread) * s, 0.0, TAU, 32, Color(BRASS_LIGHT, 0.75 * fading), (0.6 + 2.2 * fading) * s)
	var spark_count := 4 + int(8.0 * GraphicsQuality.effect_detail)
	for spark_index in spark_count:
		# fixed but uneven angles and speeds, so the burst looks random without changing between frames
		var a := spark_index * TAU / spark_count + 0.37 * sin(spark_index * 12.9)
		var speed := 0.75 + 0.25 * sin(spark_index * 7.3)
		var outward := Vector2(cos(a), sin(a))
		var tip := origin + outward * lerpf(4.0, 28.0 * speed, spread) * s
		canvas.draw_line(tip - outward * 5.0 * fading * s, tip, Color(SPARK, fading), 1.4 * s)

## Corner-rounded rectangle as an outline of points (not closed: the last point is not repeated).
static func _rounded_rect_points(rect: Rect2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var corners := [[rect.position + Vector2(radius, radius), PI], [Vector2(rect.end.x - radius, rect.position.y + radius), PI * 1.5],
		[rect.end - Vector2(radius, radius), 0.0], [Vector2(rect.position.x + radius, rect.end.y - radius), PI * 0.5]]
	for corner in corners:
		for point_index in 4:
			var a: float = corner[1] + PI / 2.0 * point_index / 3.0
			points.append(corner[0] + Vector2(cos(a), sin(a)) * radius)
	return points

## Ease that overshoots its target a little before settling (the padlock landing).
static func _back_out(x: float) -> float:
	var overshoot := 1.70158
	return 1.0 + (overshoot + 1.0) * pow(x - 1.0, 3.0) + overshoot * pow(x - 1.0, 2.0)
