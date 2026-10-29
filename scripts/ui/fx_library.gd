class_name FxLibrary
extends RefCounted
## The table's animation toolbox: where a card is (poses) and how it flies, plus every visual effect
## the event player (Main._animate) can ask for: lunges, impacts, freezes, shields, shouts, embers...
## The shots that carry an effect from its source card to its target live in FxShots.
##
## It draws on Main's effects layer (`fx`). Main is `host`: what the effects only read (the layer, the
## game state, the cards on screen) is mirrored below, anything else is asked of `host` explicitly.

## The pale blue of ice, shared with Main (frozen tags, freeze effects, ice shots).
const ICE := Color("#bfefff")

## The Main node that owns the table.
var host

## Read-only mirrors of Main's state, so the effect code can name them as before.
var fx: Control:
	get: return host.fx
var layer: Control:
	get: return host.layer
var g: GameState:
	get: return host.g
var viewer: int:
	get: return host.viewer
var views: Dictionary:
	get: return host.views
var hand_uids: Dictionary:
	get: return host.hand_uids
var col_x: float:
	get: return host.col_x
var lane_cx: float:
	get: return host.lane_cx

func _init(host_node) -> void:
	host = host_node

## Pose of a Control as its visual center, rotation and on-screen width.
func _pose(v: Control) -> Dictionary:
	var zoom: float = v.zoom if v is CardView else 1.0 # a zoomed card is bigger without a node scale
	var s: float = v.scale.x * zoom
	return {"c": v.position + v.pivot_offset + (v.size / 2.0 - v.pivot_offset).rotated(v.rotation) * s,
		"rot": v.rotation, "w": v.size.x * s}

func _apply_pose(v: Control, p: Dictionary) -> void:
	var s: float = p["w"] / v.size.x
	v.rotation = p["rot"]
	v.scale = Vector2.ONE * s
	v.position = p["c"] - v.pivot_offset - (v.size / 2.0 - v.pivot_offset).rotated(p["rot"]) * s

## Where every card is right now, taken before a re-render replaces it.
func _snapshot() -> Dictionary:
	var out := {}
	for k in views:
		var v = views[k]
		if v is CardView and is_instance_valid(v) and not v.is_queued_for_deletion():
			out[k] = {"pose": _pose(v), "card_id": v.card_id, "inst": v.inst.duplicate(true), "hand": hand_uids.has(k)}
	return out

func _center_of(c: Control) -> Vector2:
	if c is LeaderView:
		return c.position + LeaderView.PC
	return _pose(c)["c"]

func _fly(v: Control, from: Dictionary, to: Dictionary, t0: float, dur: float, arc := 0.0, hide := false) -> Tween:
	_apply_pose(v, from)
	var tw := v.create_tween()
	if hide:
		v.visible = false
	if t0 > 0.0:
		tw.tween_interval(t0)
	if hide:
		tw.tween_callback(func(): v.visible = true)
	tw.tween_method(func(t: float):
		var c: Vector2 = from["c"].lerp(to["c"], t)
		c.y -= arc * 4.0 * t * (1.0 - t)
		_apply_pose(v, {"c": c, "rot": lerp_angle(from["rot"], to["rot"], t), "w": lerpf(from["w"], to["w"], t)}),
		0.0, 1.0, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	return tw

## A unit that enters the board straight from the deck: it leaves the top of its owner's pile face
## down, flips face up halfway (like a drawn card) and lands in its slot with the same small bounce
## and sound as a unit played from the hand. Returns how long it takes.
func _enter_from_deck(v: CardView, owner_player: int, t0: float) -> float:
	const FLIGHT_TIME := 0.5
	var deck_pose: Dictionary = host._deck_top_pose(owner_player)
	var to := _pose(v)
	v.z_index = 20
	v.face_down = true
	var tw := _fly(v, deck_pose, to, t0, FLIGHT_TIME, 60.0, true)
	tw.tween_callback(func(): v.z_index = 0)
	var landing_scale: Vector2 = Vector2.ONE * (to["w"] / v.size.x)
	tw.tween_property(v, "scale", landing_scale * 1.1, 0.06)
	tw.tween_property(v, "scale", landing_scale, 0.1)
	var flip := v.create_tween()
	flip.tween_interval(t0 + FLIGHT_TIME * 0.45)
	flip.tween_callback(func():
		v.face_down = false
		v.queue_redraw())
	Sfx.play_in("card_place", t0 + FLIGHT_TIME - 0.04)
	return FLIGHT_TIME + 0.1

## A drawn card is a physical card: it slides off the top of the viewer's deck pile face down,
## lifts in a soft arc toward the hand while turning over (it narrows to its edge, the face
## shows, it widens again) and settles into its hand slot, slowing down as it arrives.
const DRAW_FLIGHT_TIME := 0.62
const DRAW_ARC_HEIGHT := 90.0 ## how high the card lifts above the straight line from deck to hand
const DRAW_TILT_DEGREES := -10.0 ## the card leans a little while it travels, like one tossed by hand

func _draw_from_deck(v: CardView, to: Dictionary, t0: float) -> void:
	var from: Dictionary = host._deck_top_pose(viewer)
	_apply_pose(v, from)
	v.face_down = true
	v.visible = false
	v.z_index = 25
	var flight := v.create_tween()
	if t0 > 0.0:
		flight.tween_interval(t0)
	flight.tween_callback(func(): v.visible = true)
	flight.tween_method(func(progress: float):
		var eased := 1.0 - pow(1.0 - progress, 3.0) # quick start, gentle landing
		var center: Vector2 = from["c"].lerp(to["c"], eased)
		center.y -= DRAW_ARC_HEIGHT * 4.0 * eased * (1.0 - eased)
		var tilt := deg_to_rad(DRAW_TILT_DEGREES) * sin(PI * eased)
		_apply_pose(v, {"c": center, "rot": lerp_angle(from["rot"], to["rot"], eased) + tilt, "w": lerpf(from["w"], to["w"], eased)})
		# turning over: the card narrows to its edge around the middle of the flight, then shows its face
		var turn := clampf((eased - 0.25) / 0.5, 0.0, 1.0)
		if v.face_down and turn >= 0.5:
			v.face_down = false
			v.queue_redraw()
		v.scale.x *= maxf(0.04, absf(cos(PI * turn))),
		0.0, 1.0, DRAW_FLIGHT_TIME)
	flight.tween_callback(func(): v.z_index = 0)

## A unit sent back to the opponent's hand (a bounce) is not a death: the card lifts off its slot, turns
## face down while it travels (the viewer must not read the opponent's hand) and slides into the fan along
## the top edge, shrinking to the size of the cards there. `ghost` stands where the unit was on the table.
## Starts at moment t; returns how long the flight takes.
const BOUNCE_FLIGHT_TIME := 0.55
const BOUNCE_LIFT_HEIGHT := 30.0 ## how far the card rises before it heads for the hand
func _bounce_to_enemy_hand_fx(ghost: CardView, owner_player: int, t: float) -> float:
	var from := _pose(ghost)
	var hand_size: int = g.players[owner_player]["hand"].size()
	var card_size: Vector2 = CardView.BASE * host.ENEMY_HAND_SCALE
	# the last card of the fan: the bounced card is always added at the end of the hand
	var to := {
		"c": Vector2(lane_cx + host.EHAND_DX + (hand_size - 1) / 2.0 * 30.0, host._screen_top() - card_size.y * (0.5 - host.ENEMY_HAND_SHOWN)),
		"rot": PI,
		"w": card_size.x,
	}
	ghost.z_index = 25
	var flight := ghost.create_tween()
	if t > 0.0:
		flight.tween_interval(t)
	flight.tween_method(func(progress: float):
		var eased := ease(progress, -1.6) # slow lift-off, quicker towards the hand
		var center: Vector2 = from["c"].lerp(to["c"], eased)
		center.y -= BOUNCE_LIFT_HEIGHT * 4.0 * eased * (1.0 - eased) * (1.0 - eased) # a small hop at the start
		_apply_pose(ghost, {"c": center, "rot": lerp_angle(from["rot"], to["rot"], eased), "w": lerpf(from["w"], to["w"], eased)})
		# turning over: it narrows to its edge around the middle of the flight, then shows its back
		var turn := clampf((progress - 0.2) / 0.5, 0.0, 1.0)
		if not ghost.face_down and turn >= 0.5:
			ghost.face_down = true
			ghost.queue_redraw()
		ghost.scale.x *= maxf(0.04, absf(cos(PI * turn)))
		ghost.modulate.a = 1.0 - clampf((progress - 0.85) / 0.15, 0.0, 1.0), # melts into the real card already in the fan
		0.0, 1.0, BOUNCE_FLIGHT_TIME)
	flight.tween_callback(ghost.queue_free)
	return BOUNCE_FLIGHT_TIME

## Timing of a milled card: it pops out of the deck face up, stays readable for a blink, then drops
## into the graveyard icon. Short on purpose: both graveyards can be opened at any time.
const MILL_RISE_TIME := 0.2
const MILL_HOLD_TIME := 0.2
const MILL_DROP_TIME := 0.24
const MILL_CARD_W := 140.0 ## on-screen width while the card is shown
const MILL_STAGGER := 0.1 ## delay between one milled card and the next (shrinks when many are milled)
const MILL_MAX_STAGGER_TOTAL := 0.4 ## the whole row of starts never takes longer than this

## The cards `card_ids` leave the top of `deck_owner`'s deck one after another and land in their
## graveyard. Starts at moment t; returns how long the animation queue should wait (the cards keep
## flying on their own after that, they overlap with whatever plays next).
func _mill_fx(deck_owner: int, card_ids: Array, t: float) -> float:
	var leader_view = views.get(GameState.LEADER_UID[deck_owner])
	if not (leader_view is LeaderView) or card_ids.is_empty():
		return 0.0
	var deck_pose: Dictionary = host._deck_top_pose(deck_owner)
	var grave_pose: Dictionary = host._graveyard_pose(deck_owner)
	# the card is shown a bit toward the middle of the table, so the Leader's own frame doesn't hide it
	var middle_y: float = (host._screen_top() + host._screen_bottom()) / 2.0
	var shown_pose := {"c": deck_pose["c"] + Vector2(0, 170.0 * signf(middle_y - deck_pose["c"].y)), "rot": 0.0, "w": MILL_CARD_W}
	# a pile in the HUD column shows the card over the table instead, not over the buttons
	shown_pose["c"].x = minf(shown_pose["c"].x, col_x - 26.0 - MILL_CARD_W / 2.0)
	var stagger := minf(MILL_STAGGER, MILL_MAX_STAGGER_TOTAL / card_ids.size())
	var total_time := MILL_RISE_TIME + MILL_HOLD_TIME + MILL_DROP_TIME
	for i in card_ids.size():
		var ghost := _ghost(card_ids[i], host._display_instance_for_id(String(card_ids[i]), deck_owner), deck_pose, MILL_CARD_W / CardView.BASE.x) # built at its biggest size: only shrinks, never blurs
		ghost.z_index = 30
		ghost.visible = false
		var flight := ghost.create_tween()
		flight.tween_interval(t + i * stagger)
		flight.tween_callback(func(): ghost.visible = true)
		flight.tween_method(func(seconds: float):
			var pose: Dictionary
			if seconds < MILL_RISE_TIME:
				pose = _blend_pose(deck_pose, shown_pose, seconds / MILL_RISE_TIME)
			elif seconds < MILL_RISE_TIME + MILL_HOLD_TIME:
				pose = shown_pose
			else:
				var drop_progress := (seconds - MILL_RISE_TIME - MILL_HOLD_TIME) / MILL_DROP_TIME
				pose = _blend_pose(shown_pose, grave_pose, drop_progress)
				ghost.modulate.a = 1.0 - drop_progress * drop_progress
			_apply_pose(ghost, pose),
			0.0, total_time, total_time)
		flight.tween_callback(ghost.queue_free)
	return (card_ids.size() - 1) * stagger + 0.1

## A pose between two poses, eased (0 = `from`, 1 = `to`).
func _blend_pose(from: Dictionary, to: Dictionary, progress: float) -> Dictionary:
	var eased := ease(clampf(progress, 0.0, 1.0), -2.0) if progress < 1.0 else 1.0
	return {"c": from["c"].lerp(to["c"], eased), "rot": lerp_angle(from["rot"], to["rot"], eased), "w": lerpf(from["w"], to["w"], eased)}

func _ghost(card_id: String, inst: Dictionary, pose: Dictionary, size_scale := 1.15) -> CardView:
	var v := CardView.new().setup(card_id, inst, size_scale)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.pivot_offset = v.size / 2.0
	fx.add_child(v)
	_apply_pose(v, pose)
	return v

## Timing of an attack lunge: pull back, rush in, stay on the target a moment, walk back.
const LUNGE_WINDUP_TIME := 0.1375
const LUNGE_STRIKE_TIME := 0.1375
const LUNGE_HOLD_TIME := 0.07
const LUNGE_RETURN_TIME := 0.23
## When the attacker touches its target (where the hit lands), counted from the lunge start.
const LUNGE_IMPACT_TIME := LUNGE_WINDUP_TIME + LUNGE_STRIKE_TIME
const LUNGE_TOTAL_TIME := LUNGE_IMPACT_TIME + LUNGE_HOLD_TIME + LUNGE_RETURN_TIME
## A unit lying down (tap) or standing up (untap): a short pause after the action, then a slow turn.
const TAP_DELAY := 0.12
## How long a stand-in summoned just to take a blow (Fantoche de Trapos) stays readable before the blow lands.
const SHORT_LIVED_ARRIVAL_TIME := 0.6
const TAP_TIME := 0.45

func _lunge(a: CardView, target: Control, t: float) -> void:
	var tw := a.create_tween()
	tw.tween_interval(t)
	# The direction is measured when the lunge starts, not now: the table was already redrawn in its
	# final state (the attacker lying tapped), but on screen the card still stands where it was until
	# the tap animation plays after the hit. "lunge" is drawn in the card's own space, so the offset
	# is turned back by the card's rotation and divided by its scale.
	tw.tween_callback(func():
		a.z_index = 20
		var offset_to_target: Vector2 = ((_center_of(target) - _center_of(a)) * 0.72 / a.scale.x).rotated(-a.rotation)
		var strike := a.create_tween()
		strike.tween_property(a, "lunge", -offset_to_target * 0.22, LUNGE_WINDUP_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		strike.tween_property(a, "lunge", offset_to_target, LUNGE_STRIKE_TIME).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		strike.tween_interval(LUNGE_HOLD_TIME)
		strike.tween_property(a, "lunge", Vector2.ZERO, LUNGE_RETURN_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		strike.tween_callback(func(): a.z_index = 0))

## How long a transformation holds the animation queue.
const TRANSFORM_TIME := 0.75

## A card becomes another one (a unit with Transformar, a Bola de Neve in hand becoming Grande...).
## _render already drew the new card, so a ghost of the old one is laid over it and, at moment t,
## burns away in the new card's color: it reveals the new card beneath, which pops with a flash and a
## ring of light. The ghost is created now, so the old card stays on screen until the moment arrives.
func _transform_fx(uid: int, from_id: String, into_id: String, actors: Dictionary, old: Dictionary, t: float) -> void:
	var new_view: CardView = actors[uid]
	var old_instance: Dictionary = old[uid]["inst"] if old.has(uid) else {}
	var old_pose: Dictionary = old[uid]["pose"] if old.has(uid) else _pose(new_view)
	var old_card := _ghost(from_id, old_instance, old_pose)
	old_card.z_index = 20
	var color: Color = host._elem_color(into_id).lightened(0.35)
	old_card.dissolve(t, color, 0.45)
	var pop := new_view.create_tween()
	pop.tween_interval(t + 0.1)
	pop.tween_callback(func(): new_view.flash = 0.8)
	pop.tween_property(new_view, "proc", 1.0, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(new_view, "proc", 0.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pop.parallel().tween_property(new_view, "flash", 0.0, 0.5)
	var ring := new_view.create_tween()
	ring.tween_interval(t + 0.14)
	ring.tween_property(new_view, "proc_wave", 1.0, 0.55).from(0.001)
	ring.tween_callback(func(): new_view.proc_wave = 0.0)
	_embers(_center_of(new_view), t + 0.1, color, 24)
	_impact(new_view, "Transformou!", color, t + 0.15, false)

## Câmara de Êxtase cancelling a killing blow: at the moment of impact the Chamber pulses and sends a
## ring of light to the Leader, "Anulado!" floats over the Leader (like a Magic Shield), the Leader
## takes no damage and does not flinch, then the spent Chamber holds a beat and dissolves slowly.
## `ward` is a ghost of the Chamber (it is already off the table), `leader` the Leader's view.
const WARD_FADE_DELAY := 0.55
const WARD_FADE_TIME := 1.1

func _ward_fx(leader: Control, ward: CardView, t: float, col: Color) -> void:
	if leader != null:
		_impact(leader, "Anulado!", col, t, false)
		_embers(_center_of(leader), t, col, 18)
		var ring := Line2D.new()
		var points := PackedVector2Array()
		for i in 33:
			points.append(Vector2.from_angle(TAU * i / 32.0) * 60.0)
		ring.points = points
		ring.width = 5.0
		ring.default_color = Color(col, 0.85)
		ring.position = _center_of(leader)
		ring.z_index = 58
		ring.scale = Vector2(0.3, 0.3)
		ring.modulate.a = 0.0
		fx.add_child(ring)
		var ring_tween := ring.create_tween()
		ring_tween.tween_interval(t)
		ring_tween.tween_property(ring, "modulate:a", 1.0, 0.05)
		ring_tween.tween_property(ring, "scale", Vector2.ONE * 2.2, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		ring_tween.parallel().tween_property(ring, "modulate:a", 0.0, 0.5)
		ring_tween.tween_callback(ring.queue_free)
	if ward == null:
		return
	if leader != null:
		# a thread of light from the Chamber to the Leader just before the impact
		_streak(ward, leader, maxf(0.0, t - STREAK_T), col)
	var pulse := ward.create_tween()
	pulse.tween_interval(t)
	pulse.tween_callback(func(): ward.flash = 0.9)
	pulse.tween_property(ward, "proc", 1.0, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pulse.tween_property(ward, "proc", 0.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.parallel().tween_property(ward, "flash", 0.0, 0.5)
	var wave := ward.create_tween()
	wave.tween_interval(t + 0.04)
	wave.tween_property(ward, "proc_wave", 1.0, 0.55).from(0.001)
	wave.tween_callback(func(): ward.proc_wave = 0.0)
	_embers(_center_of(ward), t + 0.05, col, 16)
	ward.dissolve(t + WARD_FADE_DELAY, col, WARD_FADE_TIME)

## Combat damage at or above this makes the whole screen react (see _crushing_blow_fx).
const CRUSHING_BLOW_DAMAGE := 7
const CRUSHING_BLOW_SHAKE_TIME := 1.2

## Heavy-hit feedback, kept cheap on purpose (no full-screen overlays, no scaling of the whole
## screen): a decaying trauma shake of the screen (strength = trauma squared, 1.2s) plus one
## shockwave ring and a few sparks at the impact point.
func _crushing_blow_fx(target: Control, amount: int, t: float) -> void:
	var center := _center_of(target)
	var power := clampf(float(amount - CRUSHING_BLOW_DAMAGE) / 8.0, 0.0, 1.0) # 7 dmg = base, 15+ = max
	var strength := 6.0 + 6.0 * power ## peak shake in pixels

	var rest_position: Vector2 = host.position
	var shake_driver: Tween = host.create_tween()
	shake_driver.tween_interval(t)
	shake_driver.tween_method(_apply_screen_trauma.bind(rest_position, strength), 0.0, 1.0, CRUSHING_BLOW_SHAKE_TIME)
	shake_driver.tween_callback(func(): host.position = rest_position)

	var ring := Line2D.new()
	var points := PackedVector2Array()
	for i in 33:
		points.append(Vector2.from_angle(TAU * i / 32.0) * 60.0)
	ring.points = points
	ring.width = 6.0
	ring.default_color = Color(1.0, 0.85, 0.6, 0.8)
	ring.position = center
	ring.z_index = 58
	ring.scale = Vector2(0.2, 0.2)
	ring.modulate.a = 0.0
	fx.add_child(ring)
	var ring_tween := ring.create_tween()
	ring_tween.tween_interval(t)
	ring_tween.tween_property(ring, "modulate:a", 1.0, 0.02)
	ring_tween.tween_property(ring, "scale", Vector2.ONE * (3.5 + 1.5 * power), 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	ring_tween.parallel().tween_property(ring, "modulate:a", 0.0, 0.45)
	ring_tween.tween_callback(ring.queue_free)
	_embers(center, t, Color(1.0, 0.6, 0.25), 14)

## Execution (a card effect kills the Leader outright, e.g. Viprax): deliberately unlike a hit.
## The Leader trembles while a ring closes in on it (wind-up), then two slashes cross it, the screen
## takes the heaviest shake, "Execução" appears in the effect's color and the HP count drains to zero
## instead of dropping in one step. Returns the time at which the animation is over.
const EXECUTION_WINDUP_TIME := 0.55
const EXECUTION_DRAIN_TIME := 0.9

func _execution_fx(leader: LeaderView, hp_before: int, t: float, col: Color) -> float:
	var center := _center_of(leader)
	var strike_t := t + EXECUTION_WINDUP_TIME

	# wind-up: the Leader trembles harder and harder, a ring closes in on it
	var base := leader.position
	var tremble := leader.create_tween()
	tremble.tween_interval(t)
	tremble.tween_method(func(k: float): leader.position = base + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 7.0 * k, 0.0, 1.0, EXECUTION_WINDUP_TIME)
	tremble.tween_callback(func(): leader.position = base)
	var ring := Line2D.new()
	var points := PackedVector2Array()
	for i in 33:
		points.append(Vector2.from_angle(TAU * i / 32.0) * 60.0)
	ring.points = points
	ring.width = 5.0
	ring.default_color = Color(col, 0.9)
	ring.position = center
	ring.z_index = 58
	ring.scale = Vector2.ONE * 3.2
	ring.modulate.a = 0.0
	fx.add_child(ring)
	var ring_tween := ring.create_tween()
	ring_tween.tween_interval(t)
	ring_tween.tween_property(ring, "modulate:a", 1.0, 0.15)
	ring_tween.parallel().tween_property(ring, "scale", Vector2.ONE * 0.9, EXECUTION_WINDUP_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	ring_tween.tween_callback(ring.queue_free)

	# strike: two crossing slashes, the heaviest screen shake and sparks in the effect's color
	_cross_slash_fx(center, Vector2(95, 75), col, strike_t)
	_crushing_blow_fx(leader, 15, strike_t)
	_embers(center, strike_t, col, 30)

	var title: Label = host._label("Execução", 52, col.lightened(0.35), HORIZONTAL_ALIGNMENT_CENTER, "heavy", 12)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	title.size = Vector2(340, 66)
	title.pivot_offset = title.size / 2.0
	title.position = center - title.size / 2.0 + Vector2(0, -28)
	title.scale = Vector2(1.8, 1.8)
	title.modulate.a = 0.0
	fx.add_child(title)
	var title_tween := title.create_tween()
	title_tween.tween_interval(strike_t)
	title_tween.tween_property(title, "modulate:a", 1.0, 0.05)
	title_tween.parallel().tween_property(title, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	title_tween.tween_interval(0.9)
	title_tween.tween_property(title, "modulate:a", 0.0, 0.3)
	title_tween.tween_callback(title.queue_free)

	# the HP count runs down to zero instead of dropping in one step
	var drain := leader.create_tween()
	drain.tween_interval(strike_t)
	drain.tween_method(func(shown_hp: float):
		leader.hp = roundi(shown_hp)
		leader.queue_redraw(), float(hp_before), 0.0, EXECUTION_DRAIN_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	drain.tween_callback(func():
		leader.hp = 0
		leader.queue_redraw())
	return strike_t + EXECUTION_DRAIN_TIME + 0.6

## A card yells its line (an effect's "shout", Barão Estrondoso). Unlike every other float it uses the
## racing font (UITheme "shout") and builds up: the screen dims, each word but the last slams in over
## the card, bigger and hotter than the one before, and gets knocked away by the next; after a beat
## the last word EXPLODES: white flash, a dark slanted band, red and cyan ghost copies that jitter
## and snap together, a color-cycling title, shockwave, shake and sparks.
## Words are split on plain spaces only: write a no-break space (U+00A0) between the words that must
## stay together, so "... INCOMODAM MUITO MAIS!" explodes "MUITO MAIS!" as one finale.
## Returns the time at which the next animation may start (the finale is still fading out then).
const SHOUT_WORD_GAP := 0.17 ## seconds between two build-up words
const SHOUT_COMMA_PAUSE := 0.14 ## extra beat after a build-up word that ends with a comma
const SHOUT_DRAMATIC_PAUSE := 0.3 ## extra beat before the last word explodes
const SHOUT_FINALE_HOLD := 1.0 ## how long the exploded word stays on screen
## The looks a shout can have (an effect's "shout_style"; unknown names fall back to "atomic"):
## font = UITheme font kind, buildup = colors of the build-up words (hotter each time), finale = colors the
## exploded word cycles through, ghost_a / ghost_b = the two jittering copies under it, dim = the screen
## tint while the card talks, band = the dark slanted band, edge = its two edge lines, sparks_a / sparks_b.
const SHOUT_STYLES := {
	"atomic": {
		"font": "shout",
		"buildup": [Color("#ffe14a"), Color("#ffab2e"), Color("#ff6a1f"), Color("#ff2f4f")],
		"finale": [Color("#fff6c8"), Color("#ffd23a"), Color("#ff7a1a"), Color("#ffffff")],
		"ghost_a": Color(1.0, 0.1, 0.35, 0.8), "ghost_b": Color(0.1, 0.95, 1.0, 0.8),
		"dim": Color(0.02, 0.0, 0.04), "band": Color(0.08, 0.0, 0.02, 0.88), "edge": Color("#e0b84a"),
		"sparks_a": Color("#ff9a2a"), "sparks_b": Color("#7af4ff"),
	},
	"wild": { # circus poster font, sand / amber / terracotta build-up, leaf green and sunset orange finale
		"font": "shout_wild",
		"buildup": [Color("#f6e3a1"), Color("#e9b44c"), Color("#d9733a"), Color("#b8452c")],
		"finale": [Color("#fff1c1"), Color("#9bdc4f"), Color("#f2a33a"), Color("#ffffff")],
		"ghost_a": Color(0.25, 0.8, 0.3, 0.8), "ghost_b": Color(1.0, 0.55, 0.1, 0.8),
		"dim": Color(0.0, 0.05, 0.02), "band": Color(0.03, 0.1, 0.04, 0.88), "edge": Color("#8fd14f"),
		"sparks_a": Color("#9bdc4f"), "sparks_b": Color("#f2a33a"),
	},
}

func _shout_fx(speaker: Control, text: String, t: float, style_name := "") -> float:
	var style: Dictionary = SHOUT_STYLES.get(style_name, SHOUT_STYLES["atomic"])
	var buildup_colors: Array = style["buildup"]
	var finale_colors: Array = style["finale"]
	var screen: Vector2 = host.get_viewport_rect().size
	var words := text.split(" ", false)
	if words.is_empty():
		return t
	var finale_word := words[words.size() - 1].replace(" ", " ")
	var buildup_words := words.slice(0, words.size() - 1)
	# everything happens over the speaker, pushed inside the screen near its borders
	var anchor := _center_of(speaker)
	anchor.x = clampf(anchor.x, screen.x * 0.3, screen.x * 0.7)
	anchor.y = clampf(anchor.y, screen.y * 0.25, screen.y * 0.75)
	# when each build-up word appears: a word ending with a comma holds the beat a little longer
	var appear_times: Array[float] = []
	var next_appear_t := t
	for buildup_word in buildup_words:
		appear_times.append(next_appear_t)
		next_appear_t += SHOUT_WORD_GAP + (SHOUT_COMMA_PAUSE if buildup_word.ends_with(",") else 0.0)
	var boom_t := next_appear_t + SHOUT_DRAMATIC_PAUSE
	var end_t := boom_t + SHOUT_FINALE_HOLD

	# the whole screen dims while the card talks
	var dim := ColorRect.new()
	dim.color = style["dim"]
	dim.size = screen
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.z_index = 60
	dim.modulate.a = 0.0
	fx.add_child(dim)
	var dim_tween := dim.create_tween()
	dim_tween.tween_interval(t)
	dim_tween.tween_property(dim, "modulate:a", 0.45, 0.15)
	dim_tween.tween_interval(end_t - t - 0.15)
	dim_tween.tween_property(dim, "modulate:a", 0.0, 0.3)
	dim_tween.tween_callback(dim.queue_free)

	# build-up: one word at a time, each bigger, hotter and tilted the other way
	for i in buildup_words.size():
		var appear_t := appear_times[i]
		var is_last_buildup_word := i == buildup_words.size() - 1
		var leave_t := boom_t if is_last_buildup_word else appear_times[i + 1]
		var tilt_side := -1.0 if i % 2 == 0 else 1.0
		var word_color: Color = buildup_colors[mini(i, buildup_colors.size() - 1)]
		var word := _shout_label(String(buildup_words[i]).to_upper(), 30 + 7 * i, word_color, screen.x * 0.9, style["font"])
		word.position = anchor - word.size / 2.0 + Vector2(tilt_side * 18.0, -40.0 + 12.0 * i)
		word.rotation = deg_to_rad(7.0 * tilt_side)
		word.scale = Vector2.ONE * 2.4
		var word_tween := word.create_tween()
		word_tween.tween_interval(appear_t)
		word_tween.tween_property(word, "modulate:a", 1.0, 0.03)
		word_tween.parallel().tween_property(word, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var resting_position := word.position
		if is_last_buildup_word:
			# the dramatic beat: the last word shivers, as if holding its breath
			word_tween.tween_method(func(k: float): word.position = resting_position + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 4.0 * k, 0.0, 1.0, leave_t - appear_t - 0.12)
		else:
			word_tween.tween_interval(leave_t - appear_t - 0.12)
		# knocked away by the next word
		word_tween.tween_property(word, "position", resting_position + Vector2(tilt_side * -160.0, -110.0), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		word_tween.parallel().tween_property(word, "rotation", word.rotation - tilt_side * 0.6, 0.25)
		word_tween.parallel().tween_property(word, "modulate:a", 0.0, 0.25)
		word_tween.tween_callback(word.queue_free)

	# finale: a white flash...
	var flash := ColorRect.new()
	flash.color = Color.WHITE
	flash.size = screen
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 64
	flash.modulate.a = 0.0
	fx.add_child(flash)
	var flash_tween := flash.create_tween()
	flash_tween.tween_interval(boom_t)
	flash_tween.tween_property(flash, "modulate:a", 0.7, 0.03)
	flash_tween.tween_property(flash, "modulate:a", 0.0, 0.3)
	flash_tween.tween_callback(flash.queue_free)

	# ...a dark slanted band with gold edges sweeps across, under the word...
	var band := Control.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.z_index = 61
	band.position = anchor
	band.rotation = deg_to_rad(-6.0)
	band.scale = Vector2(0.0, 1.0)
	fx.add_child(band)
	var band_width := screen.x * 1.6
	var band_height := 110.0
	## each stripe: [color, top edge, height]; the dark body and its two gold edges
	var stripes := [[style["band"], -band_height / 2.0, band_height],
		[style["edge"], -band_height / 2.0 - 5.0, 4.0],
		[style["edge"], band_height / 2.0 + 1.0, 4.0]]
	for stripe in stripes:
		var stripe_rect := ColorRect.new()
		stripe_rect.color = stripe[0]
		stripe_rect.position = Vector2(-band_width / 2.0, stripe[1])
		stripe_rect.size = Vector2(band_width, stripe[2])
		stripe_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.add_child(stripe_rect)
	var band_tween := band.create_tween()
	band_tween.tween_interval(boom_t)
	band_tween.tween_property(band, "scale:x", 1.0, 0.18).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	band_tween.tween_interval(SHOUT_FINALE_HOLD - 0.18)
	band_tween.tween_property(band, "scale:y", 0.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	band_tween.tween_callback(band.queue_free)

	# ...red and cyan ghosts that jitter apart and snap together under the real word...
	var finale_text := finale_word.to_upper()
	for ghost_side in [-1.0, 1.0]:
		var ghost_color: Color = style["ghost_a"] if ghost_side < 0 else style["ghost_b"]
		var ghost := _shout_label(finale_text, 76, ghost_color, screen.x - 32.0, style["font"])
		ghost.position = anchor - ghost.size / 2.0
		ghost.rotation = deg_to_rad(-4.0)
		var ghost_rest := ghost.position
		var ghost_tween := ghost.create_tween()
		ghost_tween.tween_interval(boom_t)
		ghost_tween.tween_property(ghost, "modulate:a", 1.0, 0.02)
		ghost_tween.tween_method(func(k: float):
			var spread := (1.0 - k) * 16.0 + 3.0
			ghost.position = ghost_rest + Vector2(ghost_side * spread + randf_range(-3, 3), randf_range(-3, 3)), 0.0, 1.0, 0.6)
		ghost_tween.tween_interval(SHOUT_FINALE_HOLD - 0.62)
		ghost_tween.tween_property(ghost, "modulate:a", 0.0, 0.25)
		ghost_tween.tween_callback(ghost.queue_free)

	# ...and the word itself, slammed in from huge, its color cycling white-hot / gold / orange
	var title := _shout_label(finale_text, 76, finale_colors[0], screen.x - 32.0, style["font"])
	title.z_index = 63
	title.add_theme_color_override("font_outline_color", Color(0.12, 0.0, 0.02))
	title.position = anchor - title.size / 2.0
	title.rotation = deg_to_rad(-4.0)
	title.scale = Vector2.ONE * 3.2
	var title_tween := title.create_tween()
	title_tween.tween_interval(boom_t)
	title_tween.tween_property(title, "modulate:a", 1.0, 0.02)
	title_tween.parallel().tween_property(title, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	title_tween.parallel().tween_method(func(k: float):
		var cycle := fmod(k * 6.0, float(finale_colors.size()))
		var from_index := int(cycle)
		var to_index := (from_index + 1) % finale_colors.size()
		title.add_theme_color_override("font_color", finale_colors[from_index].lerp(finale_colors[to_index], cycle - from_index)), 0.0, 1.0, SHOUT_FINALE_HOLD)
	title_tween.tween_property(title, "modulate:a", 0.0, 0.25)
	title_tween.parallel().tween_property(title, "scale", Vector2(1.6, 0.2), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	title_tween.tween_callback(title.queue_free)

	# BOOM, shockwave, screen shake and sparks
	Sfx.play_in("atomic_boom", boom_t)
	_crushing_blow_fx(speaker, 15, boom_t)
	_embers(anchor, boom_t, style["sparks_a"], 40)
	_embers(anchor, boom_t + 0.08, style["sparks_b"], 18)
	return boom_t + 0.35

## A label in the shout font, hidden, already added to the fx layer, sized to its text and pivoting on
## its center. The font shrinks if needed so the text never gets wider than `max_width` (phones).
func _shout_label(text: String, font_size: int, color: Color, max_width: float, font_kind := "shout") -> Label:
	var shout_font := UITheme.font(font_kind)
	var text_width := shout_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if text_width > max_width:
		font_size = int(font_size * max_width / text_width)
	var label: Label = host._label(text, font_size, color, HORIZONTAL_ALIGNMENT_CENTER, font_kind, maxi(6, font_size / 7))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	label.z_index = 62
	label.modulate.a = 0.0
	fx.add_child(label)
	label.reset_size()
	label.pivot_offset = label.size / 2.0
	return label

## The "X" of every destruction: two slashes that cross over `center`, the second 0.09s after the first.
## `half_extent` is how far each slash reaches from the center (half the width and height of the X).
const CROSS_SLASH_SECOND_DELAY := 0.09
const CROSS_SLASH_FORM_TIME := 0.12 ## how long one slash takes to be drawn
func _cross_slash_fx(center: Vector2, half_extent: Vector2, col: Color, t: float) -> void:
	_execution_slash(center, Vector2(-half_extent.x, -half_extent.y), half_extent, col, t)
	_execution_slash(center, Vector2(half_extent.x, -half_extent.y), Vector2(-half_extent.x, half_extent.y), col, t + CROSS_SLASH_SECOND_DELAY)

## One slash of the execution: a bright line drawn from `from_offset` to `to_offset` (relative to
## `center`) in a few frames, then fading out.
func _execution_slash(center: Vector2, from_offset: Vector2, to_offset: Vector2, col: Color, t: float) -> void:
	var slash := Line2D.new()
	slash.width = 10.0
	slash.default_color = col.lightened(0.6)
	slash.position = center
	slash.z_index = 59
	slash.points = PackedVector2Array([from_offset, from_offset])
	slash.modulate.a = 0.0
	fx.add_child(slash)
	var slash_tween := slash.create_tween()
	slash_tween.tween_interval(t)
	slash_tween.tween_property(slash, "modulate:a", 1.0, 0.01)
	slash_tween.tween_method(func(k: float): slash.points = PackedVector2Array([from_offset, from_offset.lerp(to_offset, k)]), 0.0, 1.0, 0.12)
	slash_tween.tween_property(slash, "modulate:a", 0.0, 0.4)
	slash_tween.tween_callback(slash.queue_free)

## One frame of the screen shake: trauma falls from 1 to 0 and the offset scales with trauma squared.
func _apply_screen_trauma(progress: float, rest_position: Vector2, strength: float) -> void:
	var trauma := 1.0 - progress
	var intensity := trauma * trauma * strength
	host.position = rest_position + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * intensity

## Shake + red flash on the target and a floating number over it.
func _impact(target: Control, text: String, col: Color, t: float, hurt: bool) -> void:
	var tw := target.create_tween()
	tw.tween_interval(t)
	if hurt and target is CardView:
		var cv: CardView = target
		tw.tween_callback(func(): cv.flash = 1.0)
		tw.tween_method(func(k: float): cv.shake = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 11.0 * (1.0 - k), 0.0, 1.0, 0.32)
		tw.parallel().tween_property(cv, "flash", 0.0, 0.4)
		tw.tween_callback(func(): cv.shake = Vector2.ZERO)
	elif hurt and target is LeaderView:
		var base := target.position
		tw.tween_method(func(k: float): target.position = base + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 9.0 * (1.0 - k), 0.0, 1.0, 0.32)
		tw.tween_callback(func(): target.position = base)
	var l: Label = host._label(text, 46, col, HORIZONTAL_ALIGNMENT_CENTER, "heavy", 10)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.size = Vector2(160, 58)
	l.pivot_offset = l.size / 2.0
	l.position = _center_of(target) - l.size / 2.0 + Vector2(0, -16)
	l.scale = Vector2(0.4, 0.4)
	l.modulate.a = 0.0
	fx.add_child(l)
	var lt := l.create_tween()
	lt.tween_interval(t)
	lt.tween_property(l, "modulate:a", 1.0, 0.06)
	lt.parallel().tween_property(l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	lt.parallel().tween_property(l, "position:y", l.position.y - 46, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	lt.tween_property(l, "modulate:a", 0.0, 0.25)
	lt.tween_callback(l.queue_free)

## A unit gets frozen. _render already drew it covered in ice, so the ice is wiped off now and, at
## moment t, it slams back on: a white-blue flash with two shockwaves, the ice growing over the card
## from nothing, a shiver and a burst of flying shards.
func _freeze_fx(target: Control, t: float) -> void:
	if not target is CardView:
		return
	var cv: CardView = target
	cv.frost_grow = 0.0
	var spread := cv.create_tween()
	spread.tween_interval(t)
	spread.tween_property(cv, "frost_grow", 1.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var burst := cv.create_tween()
	burst.tween_interval(t)
	burst.tween_property(cv, "frost_burst", 1.0, 0.65).from(0.001)
	burst.tween_callback(func(): cv.frost_burst = 0.0)
	var shiver := cv.create_tween()
	shiver.tween_interval(t)
	shiver.tween_method(func(k: float): cv.shake = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 4.0 * (1.0 - k), 0.0, 1.0, 0.4)
	shiver.tween_callback(func(): cv.shake = Vector2.ZERO)
	_frost_shards(_center_of(cv), t, 30)

## Empty slots get frozen (Rei Gelado). _render already drew them covered in ice, so the ice is wiped
## off, and at moment t it slams back on like it does on a unit: flash, shockwaves, growing ice, shards.
func _freeze_slots_fx(frozen_player: int, t: float) -> void:
	for node in layer.get_children():
		if not node is FrozenSlotView or node.owner_player != frozen_player:
			continue
		var tile: FrozenSlotView = node
		tile.frost_grow = 0.0
		var spread := tile.create_tween()
		spread.tween_interval(t)
		spread.tween_property(tile, "frost_grow", 1.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var burst := tile.create_tween()
		burst.tween_interval(t)
		burst.tween_property(tile, "frost_burst", 1.0, 0.65).from(0.001)
		burst.tween_callback(func(): tile.frost_burst = 0.0)
		_frost_shards(tile.position + tile.size / 2.0, t, 24)

## Ice shards thrown outward from a point at moment t, falling a little as they fade.
func _frost_shards(c: Vector2, t: float, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = maxi(6, int(amount * fx_scale))
	p.lifetime = 0.9
	p.explosiveness = 0.95
	p.position = c
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(45, 65)
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 220)
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 230.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 7.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1.0))
	ramp.set_color(ramp.get_point_count() - 1, Color(ICE, 0.0))
	p.color_ramp = ramp
	p.z_index = 30
	fx.add_child(p)
	var tw := fx.create_tween()
	tw.tween_interval(t)
	tw.tween_callback(func():
		if is_instance_valid(p):
			p.emitting = true)
	tw.tween_interval(1.4)
	tw.tween_callback(func():
		if is_instance_valid(p):
			p.queue_free())

## Escudo Supremo: a gold-and-ivory burst, with layered rings and star-like rays.
func _supreme_shield_fx(target: Control, t: float) -> void:
	var burst := Node2D.new()
	burst.position = _center_of(target)
	burst.z_index = 55
	fx.add_child(burst)
	var outer := _ring_line(34.0, 4.0, Color("#ffd86b"))
	outer.modulate.a = 0.0
	burst.add_child(outer)
	var inner := _ring_line(22.0, 2.5, Color("#fff5cf"))
	inner.modulate.a = 0.0
	burst.add_child(inner)
	var flare := _glow_sprite(42.0, Color("#ffe9a3", 0.9))
	flare.modulate.a = 0.0
	burst.add_child(flare)
	var rays: Array[Line2D] = []
	for i in 8:
		var ray := Line2D.new()
		ray.points = PackedVector2Array([Vector2(0, -27), Vector2(0, -43 if i % 2 == 0 else -37)])
		ray.width = 2.5 if i % 2 == 0 else 1.5
		ray.default_color = Color("#fff5cf") if i % 2 == 0 else Color("#ffd86b")
		ray.rotation = TAU * float(i) / 8.0
		ray.scale = Vector2(0.35, 0.35)
		ray.modulate.a = 0.0
		burst.add_child(ray)
		rays.append(ray)
	var tw := burst.create_tween()
	tw.tween_interval(t)
	tw.tween_property(outer, "modulate:a", 1.0, 0.04)
	tw.parallel().tween_property(inner, "modulate:a", 1.0, 0.04)
	tw.parallel().tween_property(flare, "modulate:a", 1.0, 0.04)
	for ray in rays:
		tw.parallel().tween_property(ray, "modulate:a", 1.0, 0.04)
	tw.tween_property(outer, "scale", Vector2(2.0, 2.0), 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(outer, "modulate:a", 0.0, 0.42)
	tw.parallel().tween_property(inner, "scale", Vector2(1.45, 1.45), 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(inner, "modulate:a", 0.0, 0.34)
	tw.parallel().tween_property(flare, "scale", Vector2(2.0, 2.0), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(flare, "modulate:a", 0.0, 0.3)
	for ray in rays:
		tw.parallel().tween_property(ray, "scale", Vector2(1.4, 1.4), 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(ray, "modulate:a", 0.0, 0.3)
	tw.tween_callback(burst.queue_free)


## Condenada / Ceifada: violet wisps of dark smoke rising off a unit at moment t, plus a short shiver.
## `heavy` makes the sentence being carried out bigger and darker than the mark being placed.
func _doom_fx(target: Control, t: float, heavy: bool) -> void:
	if not target is CardView:
		return
	var cv: CardView = target
	var shiver := cv.create_tween()
	shiver.tween_interval(t)
	shiver.tween_method(func(k: float): cv.shake = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * (6.0 if heavy else 3.0) * (1.0 - k), 0.0, 1.0, 0.45)
	shiver.tween_callback(func(): cv.shake = Vector2.ZERO)
	var wisps := CPUParticles2D.new()
	wisps.emitting = false
	wisps.one_shot = true
	wisps.amount = maxi(8, int((46 if heavy else 24) * fx_scale))
	wisps.lifetime = 1.1
	wisps.explosiveness = 0.8
	wisps.position = _center_of(cv)
	wisps.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	wisps.emission_rect_extents = Vector2(40, 60)
	wisps.direction = Vector2(0, -1)
	wisps.spread = 40.0
	wisps.gravity = Vector2(0, -60)
	wisps.initial_velocity_min = 40.0
	wisps.initial_velocity_max = 150.0
	wisps.scale_amount_min = 5.0
	wisps.scale_amount_max = 11.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(CardView.DOOM_COL, 0.9))
	ramp.set_color(ramp.get_point_count() - 1, Color("#160726", 0.0))
	wisps.color_ramp = ramp
	wisps.z_index = 30
	fx.add_child(wisps)
	var tw := fx.create_tween()
	tw.tween_interval(t)
	tw.tween_callback(func():
		if is_instance_valid(wisps):
			wisps.emitting = true)
	tw.tween_interval(1.5)
	tw.tween_callback(func():
		if is_instance_valid(wisps):
			wisps.queue_free())

## Effects budget of the current _animate batch: 1.0 for a lone hit, shrinking as more
## triggers/deaths pile up (a Diabrete chain would otherwise spawn dozens of emitters at once).
## Also scaled by GraphicsQuality.effect_detail, so phones always get lighter effects.
var fx_scale := 1.0
## The chain part of _fx_scale alone (without the phone economy): sets how fast shots fly, so the
## game paces the same on every device.
var fx_chain_scale := 1.0

## Draws the death shader, a particle burst and a gradient line once, invisibly, so the GPU
## compiles them at startup instead of freezing the first time a unit dies.
func _prewarm_fx() -> void:
	var holder := Control.new()
	holder.modulate.a = 0.01
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.add_child(holder)
	var r := ColorRect.new()
	r.size = Vector2(8, 8)
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/ui/shaders/dissolve.gdshader")
	m.set_shader_parameter("size", r.size)
	m.set_shader_parameter("edge_color", Color.ORANGE)
	m.set_shader_parameter("progress", 0.5)
	r.material = m
	holder.add_child(r)
	var r2 := ColorRect.new()
	r2.size = Vector2(8, 8)
	var m2 := ShaderMaterial.new()
	m2.shader = load("res://scripts/ui/shaders/banish.gdshader")
	m2.set_shader_parameter("size", r2.size)
	m2.set_shader_parameter("progress", 0.5)
	r2.material = m2
	holder.add_child(r2)
	var p := CPUParticles2D.new()
	p.amount = 4
	p.one_shot = true
	p.emitting = true
	p.color_ramp = Gradient.new()
	holder.add_child(p)
	var ln := Line2D.new()
	ln.points = PackedVector2Array([Vector2.ZERO, Vector2(8, 8)])
	ln.gradient = Gradient.new()
	holder.add_child(ln)
	# effect bolts: additive glow sprites, lines and world-space sparks
	holder.add_child(_glow_sprite(8.0, Color.WHITE))
	var glow_line := _ring_line(8.0, 2.0, Color.WHITE)
	holder.add_child(glow_line)
	var trail := CPUParticles2D.new()
	trail.amount = 4
	trail.one_shot = true
	trail.local_coords = false
	trail.material = _additive()
	trail.color_ramp = Gradient.new()
	trail.emitting = true
	holder.add_child(trail)
	# thorn hit style: a polygon with per-vertex colors
	var thorn_spike := Polygon2D.new()
	thorn_spike.polygon = PackedVector2Array([Vector2.ZERO, Vector2(8, 0), Vector2(0, 8)])
	thorn_spike.vertex_colors = PackedColorArray([Color.WHITE, Color.RED, Color.GREEN])
	holder.add_child(thorn_spike)
	# floating numbers / trigger tags: big outlined glyphs are rasterized on first use
	var num: Label = host._label("-0123456789+/!", 46, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, "heavy", 10)
	num.size = Vector2(400, 58)
	holder.add_child(num)
	var tg: Label = host._label("Ao Morrer Aliado Morre Ao Entrar Escudo Maré Congelada", 17, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, "heavy", 4)
	tg.position = Vector2(0, 60)
	holder.add_child(tg)
	var shout_glyphs: Label = host._label("SUPER HIPER ULTRA MEGA… ATÔMICA!", 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, "shout", 10)
	shout_glyphs.position = Vector2(0, 90)
	holder.add_child(shout_glyphs)
	host.get_tree().create_timer(0.5).timeout.connect(holder.queue_free)

func _embers(c: Vector2, t: float, col: Color, amount := 36) -> void:
	amount = maxi(4, int(amount * fx_scale))
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = 1.0
	p.explosiveness = 0.85
	p.position = c
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(55, 75)
	p.direction = Vector2(0, -1)
	p.spread = 40.0
	p.gravity = Vector2(0, -90)
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 70.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(col.lightened(0.4), 1.0))
	ramp.set_color(ramp.get_point_count() - 1, Color(col, 0.0))
	p.color_ramp = ramp
	fx.add_child(p)
	var tw := fx.create_tween()
	tw.tween_interval(t)
	tw.tween_callback(func():
		if is_instance_valid(p):
			p.emitting = true)
	tw.tween_interval(1.6)
	tw.tween_callback(func():
		if is_instance_valid(p):
			p.queue_free())

const BANISH_COL := Color(0.8, 0.7, 1.0)

## Banish flourish at a card's center: a pale ring contracting onto it while motes of light
## are pulled inward (the opposite of the death embers, which rise and scatter).
func _banish_fx(c: Vector2, w: float, t: float) -> void:
	var rad := w * 0.75
	var ring := Line2D.new()
	var pts := PackedVector2Array()
	for i in 33:
		pts.append(Vector2.from_angle(TAU * i / 32.0) * rad)
	ring.points = pts
	ring.width = 5.0
	ring.default_color = Color(BANISH_COL.lightened(0.4), 0.9)
	ring.position = c
	ring.z_index = 24
	ring.visible = false
	fx.add_child(ring)
	var rt := ring.create_tween()
	rt.tween_interval(t)
	rt.tween_callback(func(): ring.visible = true)
	rt.tween_property(ring, "scale", Vector2(0.05, 0.05), 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	rt.parallel().tween_property(ring, "modulate:a", 0.0, 0.8).set_delay(0.5)
	rt.tween_callback(ring.queue_free)
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = maxi(6, int(28 * fx_scale))
	p.lifetime = 0.7
	p.explosiveness = 0.7
	p.position = c
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
	p.emission_sphere_radius = rad
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 10.0
	p.radial_accel_min = -(rad * 2.4)
	p.radial_accel_max = -(rad * 3.4)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(BANISH_COL.lightened(0.5), 0.0))
	ramp.set_color(ramp.get_point_count() - 1, Color(BANISH_COL, 1.0))
	p.color_ramp = ramp
	p.z_index = 23
	fx.add_child(p)
	var tw := fx.create_tween()
	tw.tween_interval(t)
	tw.tween_callback(func():
		if is_instance_valid(p):
			p.emitting = true)
	tw.tween_interval(1.0)
	tw.tween_callback(func():
		if is_instance_valid(p):
			p.queue_free())

## A unit's trigger went off: the card pops with a hot rim light, a ring pulses out of it,
## light sweeps across it, sparks fly and a tag names the trigger, in the same orange as
## trigger names in the rules text, so what follows reads as coming from this card.
func _trigger_fx(v: Control, trigger: String, t: float) -> void:
	if v is CardView:
		var cv: CardView = v
		var tw := cv.create_tween()
		tw.tween_interval(t)
		tw.tween_callback(func(): cv.z_index = maxi(cv.z_index, 15))
		tw.tween_property(cv, "proc", 1.0, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(cv, "proc", 0.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(func(): cv.z_index = 0 if cv.z_index == 15 else cv.z_index)
		var wt := cv.create_tween()
		wt.tween_interval(t + 0.04)
		wt.tween_property(cv, "proc_wave", 1.0, 0.55).from(0.001)
		wt.tween_callback(func(): cv.proc_wave = 0.0)
	var c := _center_of(v)
	_embers(c, t + 0.05, CardView.TRIGGER_COL, 16)
	var trg: Dictionary = CardDB.data()["triggers"].get(trigger, {})
	if trg.is_empty():
		return
	var tag: Label = host._label(String(trg["name"]), 17, CardView.TRIGGER_COL.lightened(0.3), HORIZONTAL_ALIGNMENT_CENTER, "heavy", 4)
	tag.add_theme_stylebox_override("normal", UITheme.box(Color(0.05, 0.03, 0.02, 0.92), 12, Color(CardView.TRIGGER_COL, 0.95), 2, 10))
	tag.z_index = 25
	tag.modulate.a = 0.0
	fx.add_child(tag)
	tag.reset_size()
	tag.pivot_offset = tag.size / 2.0
	# sits on the card's top edge; pushed inside the screen near its borders
	var half_h: float = _pose(v)["w"] * CardView.BASE.y / CardView.BASE.x / 2.0 if v is CardView else 60.0
	var vw: float = host.get_viewport_rect().size.x
	var pos := Vector2(c.x - tag.size.x / 2.0, c.y - half_h - tag.size.y * 0.55)
	pos.x = clampf(pos.x, 8.0, vw - tag.size.x - 8.0)
	pos.y = maxf(pos.y, 6.0)
	tag.position = pos
	tag.scale = Vector2(0.55, 0.55)
	var lt := tag.create_tween()
	lt.tween_interval(t)
	lt.tween_property(tag, "modulate:a", 1.0, 0.08)
	lt.parallel().tween_property(tag, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	lt.parallel().tween_property(tag, "position:y", pos.y - 10.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	lt.tween_property(tag, "modulate:a", 0.0, 0.25)
	lt.tween_callback(tag.queue_free)

## Bolt of light from a trigger's source to what its effect hits, so the effect visibly comes
## from that card. Follows both ends if they move. Returns the travel time.
const STREAK_T := 0.2

func _streak(from: Control, to: Control, t: float, col: Color) -> float:
	var lines: Array[Line2D] = []
	for i in 2: # wide soft glow under a thin hot core
		if i == 0 and fx_scale < 0.7:
			continue ## big chains: only the thin core, the soft glow is the costly overdraw
		var ln := Line2D.new()
		ln.width = 16.0 if i == 0 else 5.0
		ln.joint_mode = Line2D.LINE_JOINT_ROUND
		ln.begin_cap_mode = Line2D.LINE_CAP_ROUND
		ln.end_cap_mode = Line2D.LINE_CAP_ROUND
		var gr := Gradient.new()
		var head := col.lightened(0.55) if i == 1 else col
		gr.set_color(0, Color(head, 0.0))
		gr.set_color(gr.get_point_count() - 1, Color(head, 0.35 if i == 0 else 1.0))
		ln.gradient = gr
		var wc := Curve.new()
		wc.add_point(Vector2(0, 0.15))
		wc.add_point(Vector2(1, 1))
		ln.width_curve = wc
		ln.z_index = 24
		ln.visible = false
		fx.add_child(ln)
		lines.append(ln)
	var bend := 1.0 if randf() < 0.5 else -1.0
	var wf: WeakRef = weakref(from) # either end may be freed mid-flight (re-render, dissolve)
	var wt: WeakRef = weakref(to)
	var paint := func(k: float, fade: float):
		var f: Control = wf.get_ref()
		var d: Control = wt.get_ref()
		if f == null or d == null:
			return
		var a := _center_of(f)
		var b := _center_of(d)
		var ctrl := (a + b) / 2.0 + (b - a).orthogonal().normalized() * minf(a.distance_to(b) * 0.18, 70.0) * bend
		var head := ease(k, -2.0)
		var tail := clampf(head - 0.45, 0.0, 1.0) + fade * (head - clampf(head - 0.45, 0.0, 1.0))
		var pts := PackedVector2Array()
		for j in 13:
			var u := lerpf(tail, head, j / 12.0)
			pts.append(a.lerp(ctrl, u).lerp(ctrl.lerp(b, u), u))
		for ln in lines:
			if is_instance_valid(ln):
				ln.visible = true
				ln.points = pts
	var tw := fx.create_tween()
	tw.tween_interval(t)
	tw.tween_method(func(k: float): paint.call(k, 0.0), 0.0, 1.0, STREAK_T)
	tw.tween_method(func(f: float): paint.call(1.0, f), 0.0, 1.0, 0.14)
	tw.tween_callback(func():
		for ln in lines:
			if is_instance_valid(ln):
				ln.queue_free())
	return STREAK_T


## Shared by every glow sprite: additive blending, so overlapping light adds up and burns white.
var _additive_material: CanvasItemMaterial
## Soft round dot (white center fading to transparent), tinted by each sprite's modulate.
var _soft_dot_texture: GradientTexture2D

func _additive() -> CanvasItemMaterial:
	if _additive_material == null:
		_additive_material = CanvasItemMaterial.new()
		_additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive_material

## A glowing dot of light of the given radius and color (additive, so it glows over anything).
func _glow_sprite(radius: float, col: Color) -> Sprite2D:
	if _soft_dot_texture == null:
		var gr := Gradient.new()
		gr.set_color(0, Color.WHITE)
		gr.set_color(1, Color(1, 1, 1, 0))
		gr.add_point(0.3, Color(1, 1, 1, 0.6))
		_soft_dot_texture = GradientTexture2D.new()
		_soft_dot_texture.gradient = gr
		_soft_dot_texture.fill = GradientTexture2D.FILL_RADIAL
		_soft_dot_texture.fill_from = Vector2(0.5, 0.5)
		_soft_dot_texture.fill_to = Vector2(1.0, 0.5)
		_soft_dot_texture.width = 64
		_soft_dot_texture.height = 64
	var s := Sprite2D.new()
	s.texture = _soft_dot_texture
	s.material = _additive()
	s.modulate = col
	s.scale = Vector2.ONE * radius / 32.0
	return s

## A thin circle outline of the given radius, centered on its own position.
func _ring_line(radius: float, width: float, col: Color) -> Line2D:
	var ring := Line2D.new()
	var pts := PackedVector2Array()
	for i in 33:
		pts.append(Vector2.from_angle(TAU * i / 32.0) * radius)
	ring.points = pts
	ring.width = width
	ring.default_color = col
	ring.material = _additive()
	return ring
