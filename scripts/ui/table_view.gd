class_name TableView
extends Control
## Static table furniture drawn over the shader background: the two battle
## lanes, the central divider with its emblem and the command-zone sockets.
## It also draws the Provocação barrier: a rail along the divider that is closed
## everywhere except in front of the tapped Provocação units.

const LANE_X := 226.0 ## left edge of both lanes; the Sanctuary column (x 20..200) sits to the left of it
static var ENEMY_LANE := Rect2(LANE_X, 150, 910, 240)
static var MY_LANE := Rect2(LANE_X, 424, 910, 250)
const DIVIDER_Y := 407.0

## Provocação barrier: one amber rail per side lying along the divider, closed everywhere except
## in front of each tapped Provocação unit. Attackers read it at a glance: the only way through is the gap.
const BARRIER_COLOR := Color("#ffb347") ## warm amber "hold the line" light, the colour of caution tape
const BARRIER_OFFSET := 9.0 ## how far each rail sits from the divider line, toward its owner's lane
const BARRIER_THICKNESS := 8.0
const BARRIER_BEAM_LENGTH := 96.0 ## how far the light of a gap reaches toward the unit that guards it
const BARRIER_SLAM_SECONDS := 0.7
const SIDE_ENEMY := 0 ## the lane at the top of the screen
const SIDE_MINE := 1 ## the lane at the bottom

var enemy_color := Color.WHITE
var my_color := Color.WHITE
var sockets: Array = [] ## Rect2 of command-zone slots

## Per side, the openings of its barrier as Vector2(centre x, width). Empty = no barrier on that side.
var barrier_gaps: Array = [[], []]
## A barrier that just vanished fades out instead of blinking off: its last openings and how visible it still is.
var fading_gaps: Array = [[], []]
var fading_alpha: Array = [0.0, 0.0]
var slam_progress: Array = [0.0, 0.0] ## per side: the barrier closing on a new unit (0 = off, 1 = finished)
var slam_center_x: Array = [0.0, 0.0]
var _fade_tweens: Array = [null, null]
var _slam_tweens: Array = [null, null]
var _barrier_time := 0.0
var _redraw_accumulator := 0.0

## Lanes span from the command column to `right_edge` (the stage is wider on wide windows).
static func layout(right_edge: float) -> void:
	var w := right_edge - LANE_X
	ENEMY_LANE = Rect2(LANE_X, 150, w, 240)
	MY_LANE = Rect2(LANE_X, 424, w, 250)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(false) # only runs while a barrier is on the table (see set_barrier)

func _draw() -> void:
	_lane(ENEMY_LANE, enemy_color)
	_lane(MY_LANE, my_color)
	# divider: tapered gold line with a central emblem
	var cx := ENEMY_LANE.get_center().x
	var half := ENEMY_LANE.size.x / 2.0
	for i in 24:
		var k := float(i) / 24.0
		var a := (1.0 - k) * 0.5
		var x0 := cx - half * (k + 1.0 / 24.0)
		var x1 := cx - half * k
		draw_line(Vector2(x0, DIVIDER_Y), Vector2(x1, DIVIDER_Y), Color(UITheme.GOLD, a), 1.5)
		draw_line(Vector2(2 * cx - x0, DIVIDER_Y), Vector2(2 * cx - x1, DIVIDER_Y), Color(UITheme.GOLD, a), 1.5)
	_draw_barriers() # under the emblem: the rails pass behind the medallion
	var c := Vector2(cx, DIVIDER_Y)
	draw_circle(c, 15, Color("#0d0b12"))
	draw_arc(c, 15, 0, TAU, 40, Color(UITheme.GOLD, 0.8), 1.5, true)
	var d := PackedVector2Array([c + Vector2(0, -9), c + Vector2(9, 0), c + Vector2(0, 9), c + Vector2(-9, 0)])
	draw_colored_polygon(d, Color(UITheme.GOLD, 0.85))
	draw_colored_polygon(PackedVector2Array([d[0], d[1], c, d[3]]), Color(UITheme.GOLD_LIGHT, 0.6))
	for r in sockets:
		_socket(r)

func _lane(r: Rect2, col: Color) -> void:
	var sb := UITheme.box(Color(0, 0, 0, 0.28), 16, Color(col, 0.22), 1)
	draw_style_box(sb, r)
	# inner glow line and corner flourishes
	draw_style_box(UITheme.box(Color.TRANSPARENT, 12, Color(1, 1, 1, 0.035), 1), r.grow(-5))
	var L := 22.0
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if corner.x < r.get_center().x else -1.0
		var sy := 1.0 if corner.y < r.get_center().y else -1.0
		var p: Vector2 = corner + Vector2(sx * 7, sy * 7)
		draw_polyline(PackedVector2Array([p + Vector2(0, sy * L), p, p + Vector2(sx * L, 0)]), Color(UITheme.GOLD, 0.55), 1.5, true)
		_pip(p, Color(UITheme.GOLD, 0.8))

func _socket(r: Rect2) -> void:
	draw_style_box(UITheme.box(Color(0, 0, 0, 0.4), 10, Color(UITheme.GOLD, 0.35), 1), r)
	draw_style_box(UITheme.box(Color.TRANSPARENT, 8, Color(UITheme.GOLD, 0.12), 1), r.grow(-4))

func _pip(c: Vector2, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -3), c + Vector2(3, 0), c + Vector2(0, 3), c + Vector2(-3, 0)]), col)

# ---------------------------------------------------------------- Provocação barriers

## Main tells us where the tapped Provocação units of one side stand. `gaps` holds one
## Vector2(centre x, width) per unit; an empty array removes that side's barrier.
func set_barrier(side: int, gaps: Array) -> void:
	var previous: Array = barrier_gaps[side]
	if gaps.is_empty() and not previous.is_empty():
		_fade_barrier_out(side, previous)
	barrier_gaps[side] = gaps
	set_process(true)
	queue_redraw()

func _fade_barrier_out(side: int, last_gaps: Array) -> void:
	if _fade_tweens[side] != null:
		_fade_tweens[side].kill()
	fading_gaps[side] = last_gaps
	var fade := create_tween()
	fade.tween_method(func(value: float): fading_alpha[side] = value, 1.0, 0.0, 0.35)
	fade.tween_callback(func(): fading_alpha[side] = 0.0)
	_fade_tweens[side] = fade

## A Provocação unit just closed the way at `center_x`: the rail slams down there with a flash and ripples.
func slam(side: int, center_x: float) -> void:
	slam_center_x[side] = center_x
	if _slam_tweens[side] != null:
		_slam_tweens[side].kill()
	var closing := create_tween()
	closing.tween_method(func(value: float): slam_progress[side] = value, 0.001, 1.0, BARRIER_SLAM_SECONDS)
	closing.tween_callback(func(): slam_progress[side] = 0.0)
	_slam_tweens[side] = closing
	set_process(true)

func _barrier_animating() -> bool:
	for side in 2:
		if not barrier_gaps[side].is_empty() or fading_alpha[side] > 0.0 or slam_progress[side] > 0.0:
			return true
	return false

func _process(delta: float) -> void:
	_barrier_time += delta
	_redraw_accumulator += delta
	if _redraw_accumulator >= 0.033: ## ~30 fps is plenty for a slow shimmer
		_redraw_accumulator = 0.0
		queue_redraw()
	if not _barrier_animating():
		set_process(false)
		queue_redraw()

func _draw_barriers() -> void:
	for side in 2:
		if fading_alpha[side] > 0.0:
			_draw_barrier(side, fading_gaps[side], fading_alpha[side])
		if not barrier_gaps[side].is_empty():
			_draw_barrier(side, barrier_gaps[side], 1.0)

func _draw_barrier(side: int, gaps: Array, visibility: float) -> void:
	var direction := -1.0 if side == SIDE_ENEMY else 1.0 ## toward the lane this barrier protects
	var rail_y := DIVIDER_Y + direction * BARRIER_OFFSET
	var slam_amount: float = slam_progress[side]
	var slamming := slam_amount > 0.0 and slam_amount < 1.0
	var thickness := BARRIER_THICKNESS * (1.0 + (0.7 * pow(1.0 - slam_amount, 3.0) if slamming else 0.0))
	var lane_left := ENEMY_LANE.position.x
	var lane_right := ENEMY_LANE.end.x
	var openings := _merged_openings(gaps, lane_left, lane_right)

	# the light and the arrows of each opening go under the rail
	for gap in gaps:
		_draw_gap_light(gap.x, minf(gap.y, lane_right - lane_left), rail_y, direction, visibility)

	# solid rail between the openings
	var cursor := lane_left
	for opening in openings:
		if opening[0] - cursor > 2.0:
			_draw_rail_segment(cursor, opening[0], rail_y, direction, thickness, visibility)
		cursor = opening[1]
	if lane_right - cursor > 2.0:
		_draw_rail_segment(cursor, lane_right, rail_y, direction, thickness, visibility)

	# posts: both ends of the lane and both sides of every opening (the ones at the opening glow brighter)
	var post_xs: Array = [[lane_left, 0.35], [lane_right, 0.35]]
	for opening in openings:
		post_xs.append([opening[0], 1.0])
		post_xs.append([opening[1], 1.0])
	for post in post_xs:
		var pop := 1.0
		if slamming:
			pop += 0.6 * pow(1.0 - slam_amount, 2.0) * (1.0 - clampf(absf(post[0] - slam_center_x[side]) / 260.0, 0.0, 1.0))
		_draw_post(post[0], rail_y, thickness, post[1], pop, visibility)

	if slamming:
		_draw_slam(slam_amount, slam_center_x[side], rail_y, thickness)

## Openings as sorted [left, right] pairs: clamped inside the lane, overlapping ones merged into one.
func _merged_openings(gaps: Array, lane_left: float, lane_right: float) -> Array:
	var spans: Array = []
	for gap in gaps:
		spans.append([maxf(lane_left, gap.x - gap.y / 2.0), minf(lane_right, gap.x + gap.y / 2.0)])
	spans.sort_custom(func(a, b): return a[0] < b[0])
	var merged: Array = []
	for span in spans:
		if not merged.is_empty() and span[0] <= merged[-1][1] + 6.0:
			merged[-1][1] = maxf(merged[-1][1], span[1])
		else:
			merged.append(span)
	return merged

## A stretch of solid barrier: soft glow, dark body, hazard stripes sliding along it, a lit edge on the
## side the attackers face and a slow bright sweep of light.
func _draw_rail_segment(left: float, right: float, rail_y: float, direction: float, thickness: float, visibility: float) -> void:
	var body := Rect2(left, rail_y - thickness / 2.0, right - left, thickness)
	for i in 5:
		var spread := 2.0 + i * 2.6
		draw_rect(body.grow_individual(0, spread, 0, spread), Color(BARRIER_COLOR, 0.07 * visibility))
	draw_rect(body, Color("#14110a", 0.95 * visibility))

	# hazard stripes: slanted amber bands, clipped to the body where they poke out at the ends
	var body_polygon := PackedVector2Array([body.position, Vector2(body.end.x, body.position.y), body.end, Vector2(body.position.x, body.end.y)])
	var band := 9.0
	var slide := fmod(_barrier_time * 14.0, band * 2.0)
	var x := left - thickness - band * 2.0 + slide
	var stripe_color := Color(BARRIER_COLOR, 0.92 * visibility)
	while x < right:
		var stripe := PackedVector2Array([Vector2(x, body.end.y), Vector2(x + band, body.end.y),
			Vector2(x + band + thickness, body.position.y), Vector2(x + thickness, body.position.y)])
		if x >= left and x + band + thickness <= right:
			draw_colored_polygon(stripe, stripe_color)
		else:
			for piece in Geometry2D.intersect_polygons(stripe, body_polygon):
				draw_colored_polygon(piece, stripe_color)
		x += band * 2.0

	# edges: dark outline, and a bright bevel on the face the attackers see (the one toward the divider)
	draw_line(body.position, Vector2(body.end.x, body.position.y), Color("#07060a", 0.9 * visibility), 1.0)
	draw_line(Vector2(body.position.x, body.end.y), body.end, Color("#07060a", 0.9 * visibility), 1.0)
	var lit_y := rail_y - direction * (thickness / 2.0 + 0.5)
	draw_line(Vector2(left, lit_y), Vector2(right, lit_y), Color(1, 0.96, 0.82, 0.45 * visibility), 1.0)

	# a slow sweep of light, brightest in the middle
	var sweep_x := left - 60.0 + fmod(_barrier_time * 150.0, (right - left) + 120.0)
	for k in range(-7, 8):
		var piece_left := maxf(left, sweep_x + k * 5.0)
		var piece_right := minf(right, sweep_x + k * 5.0 + 5.0)
		if piece_right > piece_left:
			draw_rect(Rect2(piece_left, body.position.y, piece_right - piece_left, thickness), Color(1, 0.95, 0.8, 0.3 * (1.0 - absf(k) / 8.0) * visibility))

## A steel-and-gold bollard standing across the rail with an amber lamp in the middle.
func _draw_post(x: float, rail_y: float, thickness: float, brightness: float, pop: float, visibility: float) -> void:
	var half_width := 4.5 * pop
	var half_height := (thickness / 2.0 + 8.0) * pop
	var body := Rect2(x - half_width, rail_y - half_height, half_width * 2.0, half_height * 2.0)
	draw_rect(body.grow(1.5), Color("#07060a", 0.9 * visibility))
	draw_rect(body, Color(UITheme.GOLD_DARK, visibility))
	draw_rect(Rect2(body.position, Vector2(half_width, body.size.y)), Color(UITheme.GOLD, 0.9 * visibility)) ## the lit half
	var lamp_pulse := 0.5 + 0.5 * sin(_barrier_time * 4.0 + x * 0.05)
	var lamp_center := Vector2(x, rail_y)
	draw_circle(lamp_center, (7.0 + 2.0 * lamp_pulse) * pop, Color(BARRIER_COLOR, (0.12 + 0.12 * lamp_pulse) * brightness * visibility))
	draw_circle(lamp_center, 3.4 * pop, Color("#07060a", visibility))
	draw_circle(lamp_center, 2.4 * pop, Color(BARRIER_COLOR.lerp(UITheme.GOLD_LIGHT, 0.5 * lamp_pulse), (0.55 + 0.45 * brightness) * visibility))

## The way through: a cone of amber light spilling from the opening toward the unit that guards it, with
## arrows marching along it, so the eye follows the gap straight to the Provocação unit.
func _draw_gap_light(center_x: float, width: float, rail_y: float, direction: float, visibility: float) -> void:
	var half := width / 2.0
	var spill := 14.0 ## the cone widens a little as it goes
	var toward_unit := PackedVector2Array([Vector2(center_x - half, rail_y), Vector2(center_x + half, rail_y),
		Vector2(center_x + half + spill, rail_y + direction * BARRIER_BEAM_LENGTH), Vector2(center_x - half - spill, rail_y + direction * BARRIER_BEAM_LENGTH)])
	var near := Color(BARRIER_COLOR, 0.34 * visibility)
	var far := Color(BARRIER_COLOR, 0.0)
	draw_polygon(toward_unit, PackedColorArray([near, near, far, far]))
	var toward_attackers := PackedVector2Array([Vector2(center_x - half, rail_y), Vector2(center_x + half, rail_y),
		Vector2(center_x + half, rail_y - direction * 34.0), Vector2(center_x - half, rail_y - direction * 34.0)])
	var soft := Color(BARRIER_COLOR, 0.16 * visibility)
	draw_polygon(toward_attackers, PackedColorArray([soft, soft, far, far]))

	# arrows marching from the attackers' side, through the gap, into the unit
	var flow := fmod(_barrier_time * 0.9, 1.0)
	var arrow_half_width := minf(half * 0.5, 26.0)
	for i in 4:
		var travel := (i + flow) / 4.0
		var along := lerpf(-24.0, BARRIER_BEAM_LENGTH * 0.8, travel)
		var arrow_alpha := sin(travel * PI) * visibility
		var arrow := PackedVector2Array([
			Vector2(center_x - arrow_half_width, rail_y + direction * (along - 7.0)),
			Vector2(center_x, rail_y + direction * (along + 7.0)),
			Vector2(center_x + arrow_half_width, rail_y + direction * (along - 7.0))])
		draw_polyline(arrow, Color("#07060a", 0.55 * arrow_alpha), 5.2, true)
		draw_polyline(arrow, Color(BARRIER_COLOR.lightened(0.25), 0.95 * arrow_alpha), 3.0, true)

## The instant the rail closes on a new unit: a white-hot flash running along it and two ripples of
## amber light pushing out toward both lanes.
func _draw_slam(progress: float, center_x: float, rail_y: float, thickness: float) -> void:
	var eased := 1.0 - pow(1.0 - progress, 3.0)
	var fade := pow(1.0 - progress, 1.5)
	var reach := 50.0 + 230.0 * eased
	for i in 6:
		var flash_half := reach * (1.0 - i / 6.0)
		draw_rect(Rect2(center_x - flash_half, rail_y - thickness / 2.0 - 2.0, flash_half * 2.0, thickness + 4.0), Color(1, 0.95, 0.75, 0.2 * fade))
	for wave_index in 2:
		var wave_progress := clampf((progress - wave_index * 0.16) / 0.84, 0.0, 1.0)
		if wave_progress <= 0.0:
			continue
		var wave_reach := 1.0 - pow(1.0 - wave_progress, 3.0)
		var wave_half := 70.0 + 150.0 * wave_reach
		for toward_lane in [-1.0, 1.0]:
			var wave_y: float = rail_y + toward_lane * (6.0 + 34.0 * wave_reach)
			draw_line(Vector2(center_x - wave_half, wave_y), Vector2(center_x + wave_half, wave_y),
				Color(BARRIER_COLOR.lightened(0.3), 0.8 * pow(1.0 - wave_progress, 1.4)), 3.0 - 2.0 * wave_reach, true)
