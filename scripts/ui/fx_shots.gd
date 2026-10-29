class_name FxShots
extends RefCounted
## The shots that carry an effect from its source card to its target: the default flaming bolt, the
## orb of light for good effects (heal, buff, summon), and the card-specific styles (thorn, slash).
## Built on FxLibrary's poses and glow primitives; Main (`host`) owns the effects layer.

## The Main node that owns the table.
var host
## The effect toolbox (poses, glow primitives and the effects budget) the shots are drawn with.
var fx_library: FxLibrary

## Read-only mirror of Main's effects layer, so the shot code can name it as before.
var fx: Control:
	get: return host.fx

func _init(host_node, library: FxLibrary) -> void:
	host = host_node
	fx_library = library

## How long each part of the default shot takes (see _effect_bolt). Only the first shot of a trigger
## winds up, so the eye finds the source; the ones after it leave at once, like a gun already firing.
## The flight is short: the shot is spat out hard, not lobbed.
const BOLT_CHARGE_FIRST := 0.12
const BOLT_CHARGE_NEXT := 0.0
const BOLT_FLIGHT := 0.15
## How long the comet's flame tail is, as a fraction of the whole path.
const BOLT_TAIL_LENGTH := 0.3
## Time between two shots of the same trigger landing (Eryon's blows, damage spread over enemies):
## short enough to feel like a burst of gunfire, long enough to still count each hit.
const VOLLEY_GAP := 0.11
## How long each part of the good-effect orb takes (see _boon_shot). It is slower than a shot on
## purpose: a heal or a buff is delivered, not fired. The first one of a trigger charges longer
## so the eye finds the source.
const BOON_CHARGE_FIRST := 0.16
const BOON_CHARGE_NEXT := 0.07
const BOON_FLIGHT := 0.32

## Color of the bolt that carries an effect, by what the effect does: red-orange for damage,
## green for healing, ice for freezing, the marker's own color for poison/bleed and so on.
## A summon has its own fuchsia, so a card appearing never reads as a stat bonus (lime).
func _bolt_color(e: Dictionary) -> Color:
	match String(e["type"]):
		"damage", "shield_break", "magic_shield_break", "supreme_shield_break":
			return Color("#ff5a2e")
		"heal":
			return Color("#5dff8a")
		"buff":
			return Color("#b6ff7a")
		"summon":
			return Color("#ff6fe0")
		"freeze":
			return FxLibrary.ICE
		"dot":
			return CardView.dot_badge_color(String(e["dot"]))
		"condemn":
			return CardView.DOOM_COL
		"stun":
			return CardView.STUN_COL
		"exhaust", "ready", "tide_mark":
			return Color("#6fd0ff")
	return CardView.TRIGGER_COL

## The path a shot travels from `from` to `to`, shared by every hit style. It is a curve that bows
## sideways (to a random side) by `arc` times the distance between the ends, at most `arc_cap` pixels.
## Returns:
##   "ends": {"a": source center, "b": target center}, the last known positions of both ends;
##   "refresh": a Callable that updates "ends" while the two controls still exist (call it every
##     frame: if one is freed mid-flight, by a re-render or the source dying, its last position is
##     kept, so the shot still finishes its path);
##   "point_at": a Callable(u) -> Vector2, the point at fraction u of the path (0 = source, 1 = target).
func _shot_path(from: Control, to: Control, arc: float, arc_cap: float) -> Dictionary:
	var bend := 1.0 if randf() < 0.5 else -1.0
	var ends := {"a": fx_library._center_of(from), "b": fx_library._center_of(to)}
	var source_ref: WeakRef = weakref(from)
	var target_ref: WeakRef = weakref(to)
	var refresh_ends := func():
		var source_view: Control = source_ref.get_ref()
		var target_view: Control = target_ref.get_ref()
		if source_view != null:
			ends["a"] = fx_library._center_of(source_view)
		if target_view != null:
			ends["b"] = fx_library._center_of(target_view)
	var point_at := func(u: float) -> Vector2:
		var a: Vector2 = ends["a"]
		var b: Vector2 = ends["b"]
		var ctrl := (a + b) / 2.0 + (b - a).orthogonal().normalized() * minf(a.distance_to(b) * arc, arc_cap) * bend
		return a.lerp(ctrl, u).lerp(ctrl.lerp(b, u), u)
	return {"ends": ends, "refresh": refresh_ends, "point_at": point_at}

## The hit style a card's effects fly with: its JSON's optional "hit_fx" field (for example
## "espinho" on the Flor Voraz). Leaders and cards without the field use the default bolt ("").
func _hit_style_of(source: Control) -> String:
	if source is CardView:
		return String(CardDB.card((source as CardView).card_id).get("hit_fx", ""))
	return ""

## Whether an event is good for the card it lands on: healing, a summon, or a buff that only adds
## (a buff with a negative number is a debuff, and that one is fired like any hit).
func _is_boon_event(e: Dictionary) -> bool:
	match String(e["type"]):
		"heal", "summon":
			return true
		"buff":
			return int(e.get("atk", 0)) >= 0 and int(e.get("hp", 0)) >= 0
	return false

## Timing of one shot in a hit style: {"charge": the wind-up on the source before it leaves,
## "flight": its time in the air}. Big chains fire faster, so a long chain does not drag.
func _shot_timing(style: String, first_shot: bool) -> Dictionary:
	var pace := 0.55 + 0.45 * fx_library.fx_chain_scale
	match style:
		"espinho":
			return {"charge": (THORN_CHARGE_FIRST if first_shot else THORN_CHARGE_NEXT) * pace, "flight": THORN_FLIGHT * pace}
		"corte":
			return {"charge": (SLASH_CHARGE_FIRST if first_shot else SLASH_CHARGE_NEXT) * pace, "flight": SLASH_DASH * pace}
		"boon":
			return {"charge": (BOON_CHARGE_FIRST if first_shot else BOON_CHARGE_NEXT) * pace, "flight": BOON_FLIGHT * pace}
	return {"charge": (BOLT_CHARGE_FIRST if first_shot else BOLT_CHARGE_NEXT) * pace, "flight": BOLT_FLIGHT * pace}

## Plays the shot of one effect, from the card whose trigger caused it to what it hits, in the
## source card's own hit style (see _hit_style_of). Returns the time from t until the shot lands,
## which is when the effect's number pops.
## To add a new style: write a function with the same parameters that returns the same time,
## add a line for it here, and put "hit_fx": "<style name>" in the cards that should use it.
func _effect_hit(style: String, from: Control, to: Control, t: float, col: Color, first_shot: bool) -> float:
	match style:
		"espinho":
			return _thorn_shot(from, to, t, first_shot)
		"corte":
			return _slash_shot(from, to, t, first_shot)
		"boon":
			return _boon_shot(from, to, t, col, first_shot)
	return _effect_bolt(from, to, t, col, first_shot)

## The default hit style: the effect is spat out of its source as a flaming comet that slams into
## its target (a hard, fast shot, not a floating orb):
## 1. wind-up (first shot of a trigger only): the source card pulls back while a hot spark swells on it;
## 2. launch: a muzzle flash and the source card kicks back, away from the target (every shot, like recoil);
## 3. flight: a blunt white-hot head on a nearly straight line, dragging a long flickering tail of
##    flame that sheds embers behind it;
## 4. impact: a sharp flash, spikes of light bursting out where it hits, a quick shockwave and
##    sparks thrown on in the travel direction.
## Follows both ends if they move. Returns the time from t until the comet lands.
func _effect_bolt(from: Control, to: Control, t: float, col: Color, first_shot: bool) -> float:
	var timing := _shot_timing("", first_shot)
	var charge: float = timing["charge"]
	var flight: float = timing["flight"]
	var launch_t := t + charge
	var impact_t := launch_t + flight
	var rich := fx_library.fx_scale >= 0.7 # big chains skip the costliest layers (wide glow, flame flicker)
	var hot := col.lightened(0.6)
	# almost straight, because it is shot hard; a slight random bend keeps a volley from being one line
	var path := _shot_path(from, to, 0.06, 28.0)
	var ends: Dictionary = path["ends"]
	var refresh_ends: Callable = path["refresh"]
	var point_at: Callable = path["point_at"]
	# the lambdas below reach the comet's nodes through this dictionary instead of capturing them:
	# Godot reports an error when a lambda runs after a node it captured was freed (the head is
	# freed on landing, and a table reset frees everything mid-flight)
	var parts := {}
	var alive := func(key: String) -> Node:
		var node = parts.get(key)
		return node if is_instance_valid(node) else null

	# --- the head: a fireball pointing along +x, round and white-hot at the front, tapering into the
	# tail at the back, inside a stretched glow
	var head := Node2D.new()
	head.z_index = 26
	head.visible = false
	if rich:
		var head_glow := fx_library._glow_sprite(30.0, Color(col, 0.6))
		head_glow.scale.x *= 1.6
		head.add_child(head_glow)
	var head_points := PackedVector2Array()
	var head_colors := PackedColorArray()
	for i in 9: # the round front: a half circle from the top to the bottom
		var angle := lerpf(-PI / 2.0, PI / 2.0, i / 8.0)
		head_points.append(Vector2.from_angle(angle) * 9.0 + Vector2(4, 0))
		head_colors.append(Color.WHITE if absf(angle) < 0.6 else hot)
	head_points.append(Vector2(-18, 0)) # the back narrows into the tail
	head_colors.append(Color(col, 0.0))
	var head_shape := Polygon2D.new()
	head_shape.polygon = head_points
	head_shape.vertex_colors = head_colors
	head_shape.material = fx_library._additive()
	head.add_child(head_shape)
	var head_core := fx_library._glow_sprite(10.0, Color.WHITE)
	head_core.position = Vector2(6, 0)
	head.add_child(head_core)
	fx.add_child(head)
	parts["head"] = head

	# --- 1. wind-up (first shot only): the source card pulls back while a spark swells on it
	if first_shot:
		var spark := fx_library._glow_sprite(26.0, Color(hot, 0.95))
		spark.z_index = 25
		spark.visible = false
		fx.add_child(spark)
		parts["spark"] = spark
		var st := fx.create_tween()
		st.tween_interval(t)
		st.tween_callback(func():
			var spark_node: Sprite2D = alive.call("spark")
			if spark_node == null:
				return # the table was reset mid-animation
			refresh_ends.call()
			spark_node.position = ends["a"]
			spark_node.visible = true)
		st.tween_property(spark, "scale", spark.scale, charge).from(Vector2.ZERO).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		st.tween_callback(spark.queue_free)
		if from is CardView:
			var windup_card: CardView = from
			var windup := windup_card.create_tween()
			windup.tween_interval(t)
			windup.tween_method(func(k: float):
				var away: Vector2 = (ends["a"] - ends["b"]).normalized()
				windup_card.shake = away * 7.0 * k, 0.0, 1.0, charge).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# --- 2. launch: a quick muzzle flash a little in front of the source, and the card kicks back
	var muzzle := fx_library._glow_sprite(40.0, Color(hot, 0.95))
	muzzle.z_index = 25
	muzzle.visible = false
	fx.add_child(muzzle)
	parts["muzzle"] = muzzle
	var mt := fx.create_tween()
	mt.tween_interval(launch_t)
	mt.tween_callback(func():
		var muzzle_node: Sprite2D = alive.call("muzzle")
		if muzzle_node == null:
			return
		refresh_ends.call()
		muzzle_node.position = point_at.call(0.04)
		muzzle_node.visible = true)
	mt.tween_property(muzzle, "scale", muzzle.scale * 1.5, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	mt.parallel().tween_property(muzzle, "modulate:a", 0.0, 0.09)
	mt.tween_callback(muzzle.queue_free)
	if from is CardView:
		var source_card: CardView = from
		var kick := source_card.create_tween()
		kick.tween_interval(launch_t)
		kick.tween_method(func(k: float):
			var away: Vector2 = (ends["a"] - ends["b"]).normalized()
			source_card.shake = away * 9.0 * (1.0 - k), 0.0, 1.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		kick.tween_callback(func(): source_card.shake = Vector2.ZERO)

	# --- 3. flight: two layers of tail behind the head, a wide flickering flame and a thin hot core
	var flame := Line2D.new()
	flame.width = 30.0
	var flame_gradient := Gradient.new()
	flame_gradient.set_color(0, Color(col, 0.0))
	flame_gradient.set_color(1, Color(hot, 0.95))
	flame_gradient.add_point(0.55, Color(col, 0.6))
	flame.gradient = flame_gradient
	var core := Line2D.new()
	core.width = 9.0
	var core_gradient := Gradient.new()
	core_gradient.set_color(0, Color(hot, 0.0))
	core_gradient.set_color(1, Color.WHITE)
	core.gradient = core_gradient
	var tail_width := Curve.new() # a point at the back, as wide as the head at the front
	tail_width.add_point(Vector2(0, 0.0))
	tail_width.add_point(Vector2(0.7, 0.55))
	tail_width.add_point(Vector2(1, 1))
	var tails: Array[Line2D] = [flame, core]
	for tail in tails:
		tail.width_curve = tail_width
		tail.joint_mode = Line2D.LINE_JOINT_ROUND
		tail.end_cap_mode = Line2D.LINE_CAP_ROUND
		tail.material = fx_library._additive()
		tail.z_index = 25
		tail.visible = false
		fx.add_child(tail)
	var embers := CPUParticles2D.new()
	embers.emitting = false
	embers.local_coords = false # embers stay where they were dropped, drifting and fading
	embers.amount = maxi(8, int(26 * fx_library.fx_scale))
	embers.lifetime = 0.35
	embers.spread = 25.0
	embers.gravity = Vector2(0, 60)
	embers.initial_velocity_min = 40.0
	embers.initial_velocity_max = 150.0
	embers.scale_amount_min = 2.5
	embers.scale_amount_max = 5.5
	var ember_shrink := Curve.new() # embers shrink away instead of popping out
	ember_shrink.add_point(Vector2(0, 1))
	ember_shrink.add_point(Vector2(1, 0))
	embers.scale_amount_curve = ember_shrink
	var ember_ramp := Gradient.new()
	ember_ramp.set_color(0, Color(hot, 1.0))
	ember_ramp.set_color(1, Color(col, 0.0))
	embers.color_ramp = ember_ramp
	embers.material = fx_library._additive()
	embers.z_index = 25
	fx.add_child(embers)
	parts["embers"] = embers
	# `head_at` runs from 0 to 1 (fast out of the source, then holding its speed); the tail trails
	# BOLT_TAIL_LENGTH behind it, and after the impact (`collapse` going from 0 to 1) it is pulled in
	var paint := func(head_at: float, collapse: float):
		refresh_ends.call()
		var tail_start := lerpf(clampf(head_at - BOLT_TAIL_LENGTH, 0.0, 1.0), head_at, collapse)
		var tip: Vector2 = point_at.call(head_at)
		var heading: Vector2 = tip - point_at.call(maxf(head_at - 0.03, 0.0))
		var side := heading.orthogonal().normalized()
		var now := Time.get_ticks_msec() / 1000.0
		var core_points := PackedVector2Array()
		var flame_points := PackedVector2Array()
		for j in 16:
			var along := j / 15.0
			var point: Vector2 = point_at.call(lerpf(tail_start, head_at, along))
			core_points.append(point)
			# the flame licks from side to side, more at the back than near the head
			var lick := sin(j * 1.7 - now * 38.0) * 5.0 * (1.0 - along) if rich else 0.0
			flame_points.append(point + side * lick)
		for tail in tails:
			if is_instance_valid(tail):
				tail.visible = true
		if is_instance_valid(flame):
			flame.points = flame_points
		if is_instance_valid(core):
			core.points = core_points
		var head_node: Node2D = alive.call("head")
		if head_node != null:
			head_node.position = tip
			if heading.length() > 0.5:
				head_node.rotation = heading.angle()
		var embers_node: CPUParticles2D = alive.call("embers")
		if embers_node != null:
			embers_node.position = tip
			if heading.length() > 0.5:
				embers_node.direction = -heading.normalized() # thrown off backwards, like sparks off a flare
	var ft := fx.create_tween()
	ft.tween_interval(launch_t)
	ft.tween_callback(func():
		var head_node: Node2D = alive.call("head")
		if head_node != null:
			head_node.visible = true
		var embers_node: CPUParticles2D = alive.call("embers")
		if embers_node != null:
			embers_node.emitting = true)
	ft.tween_method(func(k: float):
		paint.call(ease(k, 0.7), 0.0)
		var head_node: Node2D = alive.call("head")
		if head_node != null:
			# stretched along its path, with a fast flicker like a living flame
			var flicker := 1.0 + 0.12 * sin(k * TAU * 6.0)
			head_node.scale = Vector2(1.5, 0.85) * flicker, 0.0, 1.0, flight)
	ft.tween_callback(func():
		var embers_node: CPUParticles2D = alive.call("embers")
		if embers_node != null:
			embers_node.emitting = false
		var head_node: Node2D = alive.call("head")
		if head_node != null:
			head_node.queue_free())
	ft.tween_method(func(c: float): paint.call(1.0, c), 0.0, 1.0, 0.08)
	ft.tween_callback(func():
		for tail in tails:
			if is_instance_valid(tail):
				tail.queue_free())
	ft.tween_interval(embers.lifetime)
	ft.tween_callback(embers.queue_free)

	# --- 4. impact: a sharp flash, spikes of light, a quick shockwave and sparks thrown on ahead
	var flare := Node2D.new()
	flare.z_index = 27
	flare.visible = false
	flare.add_child(fx_library._glow_sprite(58.0, Color(col, 0.9)))
	flare.add_child(fx_library._glow_sprite(24.0, Color.WHITE))
	fx.add_child(flare)
	# the spikes point along +x (the travel direction): most burst forward, a few go sideways and back
	var spikes := Node2D.new()
	spikes.z_index = 27
	spikes.visible = false
	for i in 9:
		var angle := randf_range(-1.2, 1.2) if i < 6 else randf_range(1.6, TAU - 1.6)
		var spike := Line2D.new()
		spike.points = PackedVector2Array([Vector2.from_angle(angle) * 10.0, Vector2.from_angle(angle) * randf_range(42.0, 78.0)])
		spike.width = randf_range(3.0, 6.0)
		var spike_width := Curve.new() # thick at the center, sharp at the end
		spike_width.add_point(Vector2(0, 1))
		spike_width.add_point(Vector2(1, 0))
		spike.width_curve = spike_width
		spike.default_color = Color(hot, 1.0)
		spike.material = fx_library._additive()
		spikes.add_child(spike)
	fx.add_child(spikes)
	var shock := fx_library._ring_line(46.0, 5.0, Color(hot, 0.95))
	shock.z_index = 27
	shock.visible = false
	fx.add_child(shock)
	var burst := CPUParticles2D.new()
	burst.emitting = false
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = maxi(6, int(18 * fx_library.fx_scale))
	burst.lifetime = 0.4
	burst.spread = 50.0
	burst.gravity = Vector2(0, 520)
	burst.damping_min = 140.0
	burst.damping_max = 240.0
	burst.initial_velocity_min = 260.0
	burst.initial_velocity_max = 540.0
	burst.scale_amount_min = 2.5
	burst.scale_amount_max = 5.0
	var burst_ramp := Gradient.new()
	burst_ramp.set_color(0, Color.WHITE)
	burst_ramp.set_color(1, Color(col, 0.0))
	burst_ramp.add_point(0.35, Color(hot, 1.0))
	burst.color_ramp = burst_ramp
	burst.material = fx_library._additive()
	burst.z_index = 27
	fx.add_child(burst)
	parts["flare"] = flare
	parts["spikes"] = spikes
	parts["shock"] = shock
	parts["burst"] = burst
	var it := fx.create_tween()
	it.tween_interval(impact_t)
	it.tween_callback(func():
		var flare_node: Node2D = alive.call("flare")
		var spikes_node: Node2D = alive.call("spikes")
		var shock_node: Line2D = alive.call("shock")
		var burst_node: CPUParticles2D = alive.call("burst")
		if flare_node == null or spikes_node == null or shock_node == null or burst_node == null:
			return
		refresh_ends.call()
		var b: Vector2 = ends["b"]
		var travel: Vector2 = (b - point_at.call(0.85)).normalized()
		flare_node.position = b
		flare_node.scale = Vector2(0.3, 0.3)
		flare_node.visible = true
		spikes_node.position = b
		spikes_node.rotation = travel.angle()
		spikes_node.scale = Vector2(0.3, 0.3)
		spikes_node.visible = true
		shock_node.position = b
		shock_node.scale = Vector2(0.3, 0.3)
		shock_node.visible = true
		burst_node.position = b
		burst_node.direction = travel
		burst_node.emitting = true)
	it.tween_property(flare, "scale", Vector2(1.1, 1.1), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	it.parallel().tween_property(spikes, "scale", Vector2(1.2, 1.2), 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	it.parallel().tween_property(spikes, "modulate:a", 0.0, 0.16).set_delay(0.04)
	it.parallel().tween_property(shock, "scale", Vector2(1.3, 1.3), 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	it.parallel().tween_property(shock, "modulate:a", 0.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	it.parallel().tween_property(flare, "modulate:a", 0.0, 0.18).set_delay(0.04)
	it.tween_interval(0.45)
	it.tween_callback(func():
		for key in ["flare", "spikes", "shock", "burst"]:
			var node: Node = alive.call(key)
			if node != null:
				node.queue_free())
	return charge + flight

## The hit style of good effects (heal, buff, summon): instead of being shot at its target, the
## effect is carried to it as a ball of light the eye can follow (a lobbed orb, not a projectile):
## 1. charge: light gathers on the source (a ring closing in on it, a growing orb);
## 2. launch: a soft flash, the source card kicks back, and a soft glow marks the target;
## 3. flight: the orb arcs to the target, stretched along its path, with a short comet tail and embers;
## 4. arrival: a flash, a ring and sparks thrown on in the travel direction.
## Follows both ends if they move. Returns the time from t until the orb lands.
func _boon_shot(from: Control, to: Control, t: float, col: Color, first_shot: bool) -> float:
	var timing := _shot_timing("boon", first_shot)
	var charge: float = timing["charge"]
	var flight: float = timing["flight"]
	var rich := fx_library.fx_scale >= 0.7 # big chains skip the costliest layers (wide glow, reticle)
	var hot := col.lightened(0.6)
	# a wide arc, like something lobbed (a straight line reads as a laser)
	var path := _shot_path(from, to, 0.32, 150.0)
	var ends: Dictionary = path["ends"]
	var refresh_ends: Callable = path["refresh"]
	var point_at: Callable = path["point_at"]
	var target_radius: float = fx_library._pose(to)["w"] * 0.6 if to is CardView else 70.0
	# the lambdas below reach the bolt's nodes through this dictionary instead of capturing them:
	# Godot reports an error when a lambda runs after a node it captured was freed (the orb is
	# freed on landing, and a table reset frees everything mid-flight)
	var parts := {}
	var alive := func(key: String) -> Node:
		var node = parts.get(key)
		return node if is_instance_valid(node) else null

	# --- the orb: wide glow, colored body, white-hot core
	var orb := Node2D.new()
	orb.z_index = 26
	orb.visible = false
	if rich:
		orb.add_child(fx_library._glow_sprite(46.0, Color(col, 0.55)))
	orb.add_child(fx_library._glow_sprite(22.0, col))
	orb.add_child(fx_library._glow_sprite(10.0, Color(hot, 1.0)))
	fx.add_child(orb)
	parts["orb"] = orb

	# --- 1. charge: a ring closes in on the source while the orb swells there
	var charge_ring := fx_library._ring_line(fx_library._pose(from)["w"] * 0.55 if from is CardView else 70.0, 4.0, Color(hot, 0.9))
	charge_ring.z_index = 25
	charge_ring.visible = false
	fx.add_child(charge_ring)
	parts["charge_ring"] = charge_ring
	var ct := fx.create_tween()
	ct.tween_interval(t)
	ct.tween_callback(func():
		var orb_node: Node2D = alive.call("orb")
		var ring_node: Line2D = alive.call("charge_ring")
		if orb_node == null or ring_node == null:
			return # the table was reset mid-animation
		refresh_ends.call()
		ring_node.position = ends["a"]
		ring_node.visible = true
		orb_node.position = ends["a"]
		orb_node.scale = Vector2.ZERO
		orb_node.visible = true)
	ct.tween_property(charge_ring, "scale", Vector2(0.15, 0.15), charge).from(Vector2.ONE).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	ct.parallel().tween_property(charge_ring, "modulate:a", 1.0, charge * 0.6).from(0.0)
	ct.parallel().tween_property(orb, "scale", Vector2.ONE, charge).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ct.tween_callback(charge_ring.queue_free)

	# --- 2. launch: muzzle flash on the source and a kick back, away from the target
	var launch_t := t + charge
	var muzzle := fx_library._glow_sprite(60.0, Color(hot, 0.9))
	muzzle.z_index = 25
	muzzle.visible = false
	fx.add_child(muzzle)
	parts["muzzle"] = muzzle
	var mt := fx.create_tween()
	mt.tween_interval(launch_t)
	mt.tween_callback(func():
		var muzzle_node: Sprite2D = alive.call("muzzle")
		if muzzle_node == null:
			return
		muzzle_node.position = ends["a"]
		muzzle_node.visible = true)
	mt.tween_property(muzzle, "scale", muzzle.scale * 1.6, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	mt.parallel().tween_property(muzzle, "modulate:a", 0.0, 0.16)
	mt.tween_callback(muzzle.queue_free)
	if from is CardView:
		var cv: CardView = from
		var kick := cv.create_tween()
		kick.tween_interval(launch_t)
		kick.tween_method(func(k: float):
			var away: Vector2 = (ends["a"] - ends["b"]).normalized()
			cv.shake = away * 10.0 * (1.0 - k), 0.0, 1.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		kick.tween_callback(func(): cv.shake = Vector2.ZERO)

	# lock-on reticle: four brackets that close in on the target and spin while the orb is on its way
	# target mark: a soft glow with a thin ring that settles on the target while the orb is on its way
	var reticle: Node2D = null
	if rich:
		reticle = Node2D.new()
		reticle.z_index = 25
		reticle.visible = false
		reticle.modulate.a = 0.0
		reticle.add_child(fx_library._glow_sprite(target_radius, Color(col, 0.35)))
		reticle.add_child(fx_library._ring_line(target_radius * 0.85, 3.0, Color(hot, 0.7)))
		fx.add_child(reticle)
		parts["reticle"] = reticle
		var rt := fx.create_tween()
		rt.tween_interval(launch_t)
		rt.tween_callback(func():
			var reticle_node: Node2D = alive.call("reticle")
			if reticle_node == null:
				return
			reticle_node.position = ends["b"]
			reticle_node.visible = true)
		rt.tween_property(reticle, "modulate:a", 1.0, flight * 0.5)
		rt.parallel().tween_property(reticle, "scale", Vector2.ONE, flight).from(Vector2(1.4, 1.4)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		# on impact the mark swells outward and vanishes
		rt.tween_property(reticle, "scale", Vector2(1.35, 1.35), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		rt.parallel().tween_property(reticle, "modulate:a", 0.0, 0.16)
		rt.tween_callback(reticle.queue_free)

	# --- 3. flight: a short comet tail right behind the orb, plus embers it sheds along the way
	var tails: Array[Line2D] = []
	var tail := Line2D.new()
	tail.width = 18.0
	tail.joint_mode = Line2D.LINE_JOINT_ROUND
	tail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	tail.end_cap_mode = Line2D.LINE_CAP_ROUND
	var tail_gradient := Gradient.new()
	tail_gradient.set_color(0, Color(col, 0.0))
	tail_gradient.set_color(1, Color(hot, 0.9))
	tail.gradient = tail_gradient
	var tail_width := Curve.new() # pointed at the back, as wide as the orb at the front
	tail_width.add_point(Vector2(0, 0.0))
	tail_width.add_point(Vector2(1, 1))
	tail.width_curve = tail_width
	tail.material = fx_library._additive()
	tail.z_index = 25
	tail.visible = false
	fx.add_child(tail)
	tails.append(tail)
	var sparks := CPUParticles2D.new()
	sparks.emitting = false
	sparks.local_coords = false # embers stay where they were dropped, drifting and fading
	sparks.amount = maxi(10, int(40 * fx_library.fx_scale))
	sparks.lifetime = 0.5
	sparks.spread = 180.0
	sparks.gravity = Vector2(0, 40)
	sparks.initial_velocity_min = 15.0
	sparks.initial_velocity_max = 70.0
	sparks.scale_amount_min = 3.0
	sparks.scale_amount_max = 7.0
	var ember_shrink := Curve.new() # embers shrink away instead of popping out
	ember_shrink.add_point(Vector2(0, 1))
	ember_shrink.add_point(Vector2(1, 0))
	sparks.scale_amount_curve = ember_shrink
	var spark_ramp := Gradient.new()
	spark_ramp.set_color(0, Color(hot, 1.0))
	spark_ramp.set_color(1, Color(col, 0.0))
	sparks.color_ramp = spark_ramp
	sparks.material = fx_library._additive()
	sparks.z_index = 25
	fx.add_child(sparks)
	parts["sparks"] = sparks
	# `head` runs from 0 to 1, speeding up; the tail trails just 0.12 behind it (a long tail reads
	# as a beam), and after the impact (`collapse` going from 0 to 1) it is pulled into the target
	var paint := func(head: float, collapse: float):
		refresh_ends.call()
		var tail_start := clampf(head - 0.12, 0.0, 1.0)
		tail_start = lerpf(tail_start, head, collapse)
		var pts := PackedVector2Array()
		for j in 13:
			pts.append(point_at.call(lerpf(tail_start, head, j / 12.0)))
		for ln in tails:
			if is_instance_valid(ln):
				ln.visible = true
				ln.points = pts
		var tip: Vector2 = point_at.call(head)
		var orb_node: Node2D = alive.call("orb")
		if orb_node != null:
			orb_node.position = tip
			# turn the orb along its path, so its stretch points where it is going
			var heading: Vector2 = tip - point_at.call(maxf(head - 0.03, 0.0))
			if heading.length() > 0.5:
				orb_node.rotation = heading.angle()
		var sparks_node: CPUParticles2D = alive.call("sparks")
		if sparks_node != null:
			sparks_node.position = tip
		var reticle_node: Node2D = alive.call("reticle")
		if reticle_node != null:
			reticle_node.position = ends["b"]
	var ft := fx.create_tween()
	ft.tween_interval(launch_t)
	ft.tween_callback(func():
		var sparks_node: CPUParticles2D = alive.call("sparks")
		if sparks_node != null:
			sparks_node.emitting = true)
	ft.tween_method(func(k: float):
		paint.call(ease(k, 1.4), 0.0)
		var orb_node: Node2D = alive.call("orb")
		if orb_node != null:
			# stretched along the path (squash and stretch) with a quick flicker, like a living flame
			var flicker := 1.0 + 0.1 * sin(k * TAU * 5.0)
			orb_node.scale = Vector2(1.35, 0.8) * flicker, 0.0, 1.0, flight)
	ft.tween_callback(func():
		var sparks_node: CPUParticles2D = alive.call("sparks")
		if sparks_node != null:
			sparks_node.emitting = false
		var orb_node: Node2D = alive.call("orb")
		if orb_node != null:
			orb_node.queue_free())
	ft.tween_method(func(c: float): paint.call(1.0, c), 0.0, 1.0, 0.12)
	ft.tween_callback(func():
		for ln in tails:
			if is_instance_valid(ln):
				ln.queue_free())
	ft.tween_interval(sparks.lifetime)
	ft.tween_callback(sparks.queue_free)

	# --- 4. impact: a round flash, shockwave ring, sparks thrown on along the travel direction
	var impact_t := launch_t + flight
	var flare := Node2D.new()
	flare.z_index = 27
	flare.visible = false
	flare.add_child(fx_library._glow_sprite(70.0, Color(col, 0.9)))
	flare.add_child(fx_library._glow_sprite(30.0, Color(hot, 1.0)))
	fx.add_child(flare)
	var shock := fx_library._ring_line(64.0, 6.0, Color(hot, 0.95))
	shock.z_index = 27
	shock.visible = false
	fx.add_child(shock)
	var burst := CPUParticles2D.new()
	burst.emitting = false
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = maxi(8, int(22 * fx_library.fx_scale))
	burst.lifetime = 0.5
	burst.spread = 55.0
	burst.gravity = Vector2(0, 520)
	burst.damping_min = 120.0
	burst.damping_max = 220.0
	burst.initial_velocity_min = 220.0
	burst.initial_velocity_max = 480.0
	burst.scale_amount_min = 2.5
	burst.scale_amount_max = 5.0
	var burst_ramp := Gradient.new()
	burst_ramp.set_color(0, Color.WHITE)
	burst_ramp.set_color(1, Color(col, 0.0))
	burst_ramp.add_point(0.35, Color(hot, 1.0))
	burst.color_ramp = burst_ramp
	burst.material = fx_library._additive()
	burst.z_index = 27
	fx.add_child(burst)
	parts["flare"] = flare
	parts["shock"] = shock
	parts["burst"] = burst
	var it := fx.create_tween()
	it.tween_interval(impact_t)
	it.tween_callback(func():
		var flare_node: Node2D = alive.call("flare")
		var shock_node: Line2D = alive.call("shock")
		var burst_node: CPUParticles2D = alive.call("burst")
		if flare_node == null or shock_node == null or burst_node == null:
			return
		refresh_ends.call()
		var b: Vector2 = ends["b"]
		var travel: Vector2 = (b - point_at.call(0.85)).normalized()
		flare_node.position = b
		flare_node.rotation = travel.angle()
		flare_node.scale = Vector2(0.35, 0.35)
		flare_node.visible = true
		shock_node.position = b
		shock_node.scale = Vector2(0.25, 0.25)
		shock_node.visible = true
		burst_node.position = b
		burst_node.direction = travel
		burst_node.emitting = true)
	it.tween_property(flare, "scale", Vector2(1.25, 1.25), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	it.parallel().tween_property(shock, "scale", Vector2(1.4, 1.4), 0.36).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	it.parallel().tween_property(shock, "modulate:a", 0.0, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	it.parallel().tween_property(flare, "modulate:a", 0.0, 0.26).set_delay(0.06)
	it.tween_interval(0.5)
	it.tween_callback(func():
		for key in ["flare", "shock", "burst"]:
			var node: Node = alive.call(key)
			if node != null:
				node.queue_free())
	return charge + flight


## Timing of the "espinho" hit style (see _thorn_shot): the plant rears back a little longer on
## its first spit so the eye finds it, then fires the rest quickly; thorns fly faster than bolts.
const THORN_CHARGE_FIRST := 0.16
const THORN_CHARGE_NEXT := 0.06
const THORN_FLIGHT := 0.22
## How long a thorn stays stuck in its target (quivering, then still) before it drops off.
const THORN_STUCK_TIME := 0.55
## Colors of the Flor Voraz's thorns (taken from its art): crimson at the base, cream at the tip.
const THORN_BASE_COLOR := Color("#8e1b1f")
const THORN_TIP_COLOR := Color("#f4e6b0")
const THORN_OUTLINE_COLOR := Color("#2a0607")
const POLLEN_COLOR := Color("#e8f07a")
const SAP_COLOR := Color("#7fd04a")

## The "espinho" hit style: the source plant spits a thorn that sticks in its target.
## 1. rear back: the source card leans away from the target (anticipation);
## 2. spit: it snaps forward, throwing a puff of pollen toward the target;
## 3. flight: a crimson-and-cream thorn flies fast on a slight arc, pointing where it goes;
## 4. impact: the thorn sinks its tip in (a bit off-center, so a volley of thorns spreads over the
##    target instead of piling on one spot), quivers, splashes sap and drops off a moment later.
## Follows both ends if they move. Returns the time from t until the thorn lands.
func _thorn_shot(from: Control, to: Control, t: float, first_shot: bool) -> float:
	var timing := _shot_timing("espinho", first_shot)
	var charge: float = timing["charge"]
	var flight: float = timing["flight"]
	var launch_t := t + charge
	var impact_t := launch_t + flight
	# a thorn is thrown hard, so its arc is much flatter than a bolt's
	var path := _shot_path(from, to, 0.12, 60.0)
	var ends: Dictionary = path["ends"]
	var refresh_ends: Callable = path["refresh"]
	var point_at: Callable = path["point_at"]
	# where on the target this thorn sticks, relative to the target's center
	var stick_offset := Vector2(randf_range(-18.0, 18.0), randf_range(-18.0, 18.0))
	# the lambdas below reach the shot's nodes through this dictionary instead of capturing them
	# (same reason as in _effect_bolt: the nodes may be freed while a lambda is still scheduled)
	var parts := {}
	var alive := func(key: String) -> Node:
		var node = parts.get(key)
		return node if is_instance_valid(node) else null

	# --- the thorn: a narrow spike pointing along +x, crimson base fading to a cream tip, with a
	# dark outline and a faint red glow behind it so it reads on a small phone screen
	var thorn := Node2D.new()
	thorn.z_index = 26
	thorn.visible = false
	thorn.scale = Vector2(1.25, 1.25)
	thorn.add_child(fx_library._glow_sprite(20.0, Color(THORN_BASE_COLOR.lightened(0.3), 0.45)))
	var spike_points := PackedVector2Array([Vector2(22, 0), Vector2(-12, -5.5), Vector2(-17, 0), Vector2(-12, 5.5)])
	var spike := Polygon2D.new()
	spike.polygon = spike_points
	spike.vertex_colors = PackedColorArray([THORN_TIP_COLOR, THORN_BASE_COLOR, THORN_BASE_COLOR.darkened(0.3), THORN_BASE_COLOR])
	thorn.add_child(spike)
	var outline := Line2D.new()
	outline.points = spike_points
	outline.closed = true
	outline.width = 1.6
	outline.default_color = THORN_OUTLINE_COLOR
	outline.joint_mode = Line2D.LINE_JOINT_ROUND
	thorn.add_child(outline)
	fx.add_child(thorn)
	parts["thorn"] = thorn
	# how far the thorn's center sits back from its tip (so the tip, not the middle, goes in)
	var tip_length := 22.0 * thorn.scale.x * 0.55

	# --- 1 and 2. rear back, then snap forward toward the target as the thorn leaves
	if from is CardView:
		var cv: CardView = from
		var lunge := cv.create_tween()
		lunge.tween_interval(t)
		lunge.tween_method(func(k: float):
			var away: Vector2 = (ends["a"] - ends["b"]).normalized()
			cv.shake = away * 9.0 * k, 0.0, 1.0, charge).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		lunge.tween_method(func(k: float):
			var toward: Vector2 = (ends["b"] - ends["a"]).normalized()
			cv.shake = toward * 12.0 * (1.0 - k), 0.0, 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		lunge.tween_callback(func(): cv.shake = Vector2.ZERO)
	var pollen := CPUParticles2D.new()
	pollen.emitting = false
	pollen.one_shot = true
	pollen.explosiveness = 0.9
	pollen.local_coords = false
	pollen.amount = maxi(6, int(16 * fx_library.fx_scale))
	pollen.lifetime = 0.55
	pollen.spread = 35.0
	pollen.gravity = Vector2(0, 30)
	pollen.damping_min = 180.0
	pollen.damping_max = 260.0
	pollen.initial_velocity_min = 80.0
	pollen.initial_velocity_max = 230.0
	pollen.scale_amount_min = 3.0
	pollen.scale_amount_max = 6.5
	var pollen_ramp := Gradient.new()
	pollen_ramp.set_color(0, Color(POLLEN_COLOR, 0.95))
	pollen_ramp.set_color(1, Color(SAP_COLOR, 0.0))
	pollen.color_ramp = pollen_ramp
	pollen.z_index = 25
	fx.add_child(pollen)
	parts["pollen"] = pollen
	var pt := fx.create_tween()
	pt.tween_interval(launch_t)
	pt.tween_callback(func():
		var pollen_node: CPUParticles2D = alive.call("pollen")
		if pollen_node == null:
			return # the table was reset mid-animation
		refresh_ends.call()
		pollen_node.position = ends["a"]
		pollen_node.direction = (ends["b"] - ends["a"]).normalized()
		pollen_node.emitting = true)
	pt.tween_interval(pollen.lifetime + 0.1)
	pt.tween_callback(func():
		var pollen_node: Node = alive.call("pollen")
		if pollen_node != null:
			pollen_node.queue_free())

	# --- 3. flight: the thorn flies along the path, turned the way it is going, with a short streak
	var streak := Line2D.new()
	streak.width = 5.0
	var streak_gradient := Gradient.new()
	streak_gradient.set_color(0, Color(THORN_BASE_COLOR, 0.0))
	streak_gradient.set_color(1, Color(THORN_TIP_COLOR, 0.55))
	streak.gradient = streak_gradient
	var streak_width := Curve.new() # pointed at the back
	streak_width.add_point(Vector2(0, 0.0))
	streak_width.add_point(Vector2(1, 1))
	streak.width_curve = streak_width
	streak.z_index = 25
	streak.visible = false
	fx.add_child(streak)
	parts["streak"] = streak
	var ft := fx.create_tween()
	ft.tween_interval(launch_t)
	ft.tween_method(func(k: float):
		refresh_ends.call()
		var head := ease(k, 1.2) # speeds up a little, like a dart
		var thorn_node: Node2D = alive.call("thorn")
		if thorn_node == null:
			return
		var tip: Vector2 = point_at.call(head)
		var heading: Vector2 = tip - point_at.call(maxf(head - 0.03, 0.0))
		if heading.length() > 0.5:
			thorn_node.rotation = heading.angle()
		thorn_node.position = tip
		thorn_node.visible = true
		var streak_node: Line2D = alive.call("streak")
		if streak_node != null:
			var streak_points := PackedVector2Array()
			var streak_start := maxf(head - 0.08, 0.0)
			for j in 7:
				streak_points.append(point_at.call(lerpf(streak_start, head, j / 6.0)))
			streak_node.points = streak_points
			streak_node.visible = true, 0.0, 1.0, flight)
	ft.tween_callback(func():
		var streak_node: Node = alive.call("streak")
		if streak_node != null:
			streak_node.queue_free())

	# --- 4. impact: a small flash, sap splashing back out, and the thorn stuck in and quivering
	var flash := fx_library._glow_sprite(34.0, Color(THORN_TIP_COLOR, 0.85))
	flash.z_index = 27
	flash.visible = false
	fx.add_child(flash)
	parts["flash"] = flash
	var sap := CPUParticles2D.new()
	sap.emitting = false
	sap.one_shot = true
	sap.explosiveness = 1.0
	sap.local_coords = false
	sap.amount = maxi(6, int(14 * fx_library.fx_scale))
	sap.lifetime = 0.5
	sap.spread = 60.0
	sap.gravity = Vector2(0, 620)
	sap.damping_min = 60.0
	sap.damping_max = 120.0
	sap.initial_velocity_min = 120.0
	sap.initial_velocity_max = 300.0
	sap.scale_amount_min = 2.5
	sap.scale_amount_max = 5.5
	# each droplet is either green sap or (less often) a red bit of the thorn, never a mix of both
	var droplet_colors := Gradient.new()
	droplet_colors.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	droplet_colors.set_color(0, SAP_COLOR)
	droplet_colors.set_color(1, THORN_BASE_COLOR.lightened(0.15))
	droplet_colors.set_offset(1, 0.7)
	sap.color_initial_ramp = droplet_colors
	var sap_fade := Gradient.new()
	sap_fade.set_color(0, Color.WHITE)
	sap_fade.set_color(1, Color(1, 1, 1, 0))
	sap.color_ramp = sap_fade
	sap.z_index = 27
	fx.add_child(sap)
	parts["sap"] = sap
	# where the thorn is stuck right now (it follows the target if the target moves)
	var stuck_spot := func() -> Vector2:
		return ends["b"] + stick_offset
	# the angle the thorn went in at, set on impact (a dictionary so the lambdas can change it)
	var stuck_angle := {"value": 0.0}
	var it := fx.create_tween()
	it.tween_interval(impact_t)
	it.tween_callback(func():
		var flash_node: Sprite2D = alive.call("flash")
		var sap_node: CPUParticles2D = alive.call("sap")
		if flash_node == null or sap_node == null:
			return
		refresh_ends.call()
		var hit_point: Vector2 = stuck_spot.call()
		var travel: Vector2 = (ends["b"] - point_at.call(0.85)).normalized()
		flash_node.position = hit_point
		flash_node.scale *= 0.4
		flash_node.visible = true
		sap_node.position = hit_point
		sap_node.direction = -travel # sap squirts back out the way the thorn came in
		sap_node.emitting = true
		stuck_angle["value"] = travel.angle()
		var thorn_node: Node2D = alive.call("thorn")
		if thorn_node != null:
			thorn_node.rotation = travel.angle()
			thorn_node.position = hit_point - travel * tip_length)
	it.tween_property(flash, "scale", flash.scale * 1.1, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	it.parallel().tween_property(flash, "modulate:a", 0.0, 0.18).set_delay(0.04)
	# stuck: the thorn quivers (fast at first, dying down) and stays on the target if it moves
	it.parallel().tween_method(func(k: float):
		refresh_ends.call()
		var thorn_node: Node2D = alive.call("thorn")
		if thorn_node == null:
			return
		var quiver := deg_to_rad(9.0) * sin(k * TAU * 4.0) * pow(1.0 - k, 2.0)
		thorn_node.rotation = stuck_angle["value"] + quiver
		thorn_node.position = stuck_spot.call() - Vector2.from_angle(stuck_angle["value"]) * tip_length, 0.0, 1.0, THORN_STUCK_TIME)
	# then it drops off: falls, tips over and fades
	it.tween_method(func(k: float):
		var thorn_node: Node2D = alive.call("thorn")
		if thorn_node == null:
			return
		var resting: Vector2 = stuck_spot.call() - Vector2.from_angle(stuck_angle["value"]) * tip_length
		thorn_node.position = resting + Vector2(0, 46.0 * k * k)
		thorn_node.rotation = stuck_angle["value"] + 0.9 * k
		thorn_node.modulate.a = 1.0 - k, 0.0, 1.0, 0.35)
	it.tween_callback(func():
		for key in ["thorn", "flash", "sap"]:
			var node: Node = alive.call(key)
			if node != null:
				node.queue_free())
	return charge + flight

## Timing of the "corte" hit style (see _slash_shot): the blade-wielder gathers herself a little before
## her first strike, then cuts one target after another without pausing; the dash to the target is
## almost instant, because a blow with a sword has no projectile to follow.
const SLASH_CHARGE_FIRST := 0.14
const SLASH_CHARGE_NEXT := 0.0
const SLASH_DASH := 0.05
## How long one cut takes to be drawn across its target, and how long it takes to fade afterwards.
const SLASH_SWEEP_TIME := 0.07
const SLASH_FADE_TIME := 0.3
## Colors of the cuts: a white-hot core, steel-blue edges and warm sparks flying off the blade.
const SLASH_CORE_COLOR := Color("#ffffff")
const SLASH_EDGE_COLOR := Color("#8fc4ff")
const SLASH_SPARK_COLOR := Color("#ffe8b0")

## The "corte" hit style, for sword fighters (no magic, so nothing flies out of them):
## 1. gather (first strike of a trigger only): the source card pulls back while a steel glint swells on it;
## 2. dash: the card snaps toward its target and a thin, fast trail of air links the two;
## 3. impact: two crossing cuts are drawn across the target (an X, a different angle every time, so a
##    volley over several targets never repeats itself), with a flash and sparks thrown along the blade.
## Follows both ends if they move. Returns the time from t until the cut lands.
func _slash_shot(from: Control, to: Control, t: float, first_shot: bool) -> float:
	var timing := _shot_timing("corte", first_shot)
	var charge: float = timing["charge"]
	var dash: float = timing["flight"]
	var launch_t := t + charge
	var impact_t := launch_t + dash
	var rich := fx_library.fx_scale >= 0.7 # big chains skip the costliest layers (wide glow, second cut)
	var path := _shot_path(from, to, 0.0, 0.0) # a straight line: the dash does not bow
	var ends: Dictionary = path["ends"]
	var refresh_ends: Callable = path["refresh"]
	# a cut is about as long as the target is big, and lands a little off-center so cuts do not pile up
	var target_extent := to.size * to.scale
	var cut_length := clampf(maxf(target_extent.x, target_extent.y) * 0.9, 120.0, 240.0)
	var cut_offset := Vector2(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0))
	# the lambdas below reach the shot's nodes through this dictionary instead of capturing them
	# (same reason as in _effect_bolt: the nodes may be freed while a lambda is still scheduled)
	var parts := {}
	var alive := func(key: String) -> Node:
		var node = parts.get(key)
		return node if is_instance_valid(node) else null

	# --- 1. gather: the source leans away from the target while a steel glint swells on it
	if first_shot:
		var glint := fx_library._glow_sprite(24.0, Color(SLASH_EDGE_COLOR.lightened(0.5), 0.95))
		glint.z_index = 25
		glint.visible = false
		fx.add_child(glint)
		parts["glint"] = glint
		var gt := fx.create_tween()
		gt.tween_interval(t)
		gt.tween_callback(func():
			var glint_node: Sprite2D = alive.call("glint")
			if glint_node == null:
				return # the table was reset mid-animation
			refresh_ends.call()
			glint_node.position = ends["a"]
			glint_node.visible = true)
		gt.tween_property(glint, "scale", glint.scale, charge).from(Vector2.ZERO).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		gt.tween_callback(glint.queue_free)

	# --- 2. dash: the source card snaps toward the target
	if from is CardView:
		var source_card: CardView = from
		var lunge := source_card.create_tween()
		lunge.tween_interval(t)
		if first_shot:
			lunge.tween_method(func(k: float):
				var away: Vector2 = (ends["a"] - ends["b"]).normalized()
				source_card.shake = away * 8.0 * k, 0.0, 1.0, charge).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		lunge.tween_method(func(k: float):
			var toward: Vector2 = (ends["b"] - ends["a"]).normalized()
			source_card.shake = toward * 16.0 * (1.0 - k), 0.0, 1.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		lunge.tween_callback(func(): source_card.shake = Vector2.ZERO)
	var trail := Line2D.new()
	trail.width = 3.0
	trail.material = fx_library._additive()
	var trail_gradient := Gradient.new()
	trail_gradient.set_color(0, Color(SLASH_EDGE_COLOR, 0.0))
	trail_gradient.set_color(1, Color(SLASH_CORE_COLOR, 0.7))
	trail.gradient = trail_gradient
	trail.z_index = 25
	trail.visible = false
	fx.add_child(trail)
	parts["trail"] = trail
	var trail_tween := fx.create_tween()
	trail_tween.tween_interval(launch_t)
	trail_tween.tween_callback(func():
		var trail_node: Line2D = alive.call("trail")
		if trail_node == null:
			return
		refresh_ends.call()
		trail_node.points = PackedVector2Array([ends["a"], ends["b"]])
		trail_node.visible = true)
	trail_tween.tween_property(trail, "modulate:a", 0.0, dash + 0.12).from(1.0)
	trail_tween.tween_callback(func():
		var trail_node: Node = alive.call("trail")
		if trail_node != null:
			trail_node.queue_free())

	# --- 3. impact: the cuts, the flash and the sparks all live in one holder, freed together
	var cuts_holder := Node2D.new()
	cuts_holder.z_index = 27
	fx.add_child(cuts_holder)
	parts["cuts"] = cuts_holder
	var it := fx.create_tween()
	it.tween_interval(impact_t)
	it.tween_callback(func():
		var holder: Node2D = alive.call("cuts")
		if holder == null:
			return
		refresh_ends.call()
		var center: Vector2 = ends["b"] + cut_offset
		# a diagonal stroke, tilted a different amount (and leaning either way) on every blow
		var first_direction := Vector2.from_angle(deg_to_rad(randf_range(25.0, 60.0)))
		if randf() < 0.5:
			first_direction.x = -first_direction.x
		_add_slash_cut(holder, center, first_direction, cut_length, 0.0, rich)
		if rich:
			# the second cut crosses the first one, a little shorter and a moment later
			var second_direction := Vector2(-first_direction.x, first_direction.y).rotated(deg_to_rad(randf_range(-12.0, 12.0)))
			_add_slash_cut(holder, center, second_direction, cut_length * 0.8, 0.05, rich)
		var flash := fx_library._glow_sprite(46.0, Color(SLASH_CORE_COLOR, 0.8))
		flash.position = center
		holder.add_child(flash)
		var flash_tween := flash.create_tween()
		flash_tween.tween_property(flash, "scale", flash.scale * 1.1, 0.09).from(flash.scale * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		flash_tween.parallel().tween_property(flash, "modulate:a", 0.0, 0.2).set_delay(0.04)
		var sparks := CPUParticles2D.new()
		sparks.emitting = false
		sparks.one_shot = true
		sparks.explosiveness = 1.0
		sparks.local_coords = false
		sparks.amount = maxi(5, int(12 * fx_library.fx_scale))
		sparks.lifetime = 0.4
		sparks.direction = first_direction
		sparks.spread = 70.0
		sparks.gravity = Vector2(0, 400)
		sparks.damping_min = 80.0
		sparks.damping_max = 160.0
		sparks.initial_velocity_min = 140.0
		sparks.initial_velocity_max = 380.0
		sparks.scale_amount_min = 2.0
		sparks.scale_amount_max = 4.0
		var spark_ramp := Gradient.new()
		spark_ramp.set_color(0, Color(SLASH_SPARK_COLOR, 0.95))
		spark_ramp.set_color(1, Color(SLASH_EDGE_COLOR, 0.0))
		sparks.color_ramp = spark_ramp
		sparks.position = center
		holder.add_child(sparks)
		sparks.emitting = true
		# everything of this blow is gone once the last cut has faded and the sparks have fallen
		var cleanup := holder.create_tween()
		cleanup.tween_interval(0.05 + SLASH_SWEEP_TIME + SLASH_FADE_TIME + 0.3)
		cleanup.tween_callback(holder.queue_free))
	return charge + dash

## One cut of the "corte" hit style, drawn across a target after `delay` seconds: a stroke that is
## swept from one end to the other in a blink, pointed at both ends, then thins out and fades.
## `direction` is the way the blade travels, `center` the middle of the stroke.
func _add_slash_cut(holder: Node2D, center: Vector2, direction: Vector2, length: float, delay: float, rich: bool) -> void:
	var start := center - direction * length / 2.0
	var finish := center + direction * length / 2.0
	# the blade swings in a slight arc, bowed to a random side
	var bowed_middle := center + direction.orthogonal() * length * 0.12 * (1.0 if randf() < 0.5 else -1.0)
	var point_on_cut := func(u: float) -> Vector2:
		return start.lerp(bowed_middle, u).lerp(bowed_middle.lerp(finish, u), u)
	var pointed_ends := Curve.new()
	pointed_ends.add_point(Vector2(0.0, 0.05))
	pointed_ends.add_point(Vector2(0.5, 1.0))
	pointed_ends.add_point(Vector2(1.0, 0.05))
	var cut := Node2D.new()
	cut.visible = false
	holder.add_child(cut)
	var edge: Line2D = null
	if rich:
		edge = Line2D.new()
		edge.width = 16.0
		edge.default_color = Color(SLASH_EDGE_COLOR, 0.55)
		edge.width_curve = pointed_ends
		edge.material = fx_library._additive()
		cut.add_child(edge)
	var core := Line2D.new()
	core.width = 6.0
	core.default_color = SLASH_CORE_COLOR
	core.width_curve = pointed_ends
	core.material = fx_library._additive()
	cut.add_child(core)
	# these lambdas only touch nodes that are children of `cut`, which also owns the tween: both end together
	var cut_tween := cut.create_tween()
	cut_tween.tween_interval(delay)
	cut_tween.tween_callback(func(): cut.visible = true)
	cut_tween.tween_method(func(k: float):
		var head := ease(k, 0.4) # the stroke starts fast and slows into the end of the swing
		var points := PackedVector2Array()
		for step in 9:
			points.append(point_on_cut.call(head * step / 8.0))
		core.points = points
		if edge != null:
			edge.points = points, 0.0, 1.0, SLASH_SWEEP_TIME)
	cut_tween.tween_property(cut, "modulate:a", 0.0, SLASH_FADE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	cut_tween.parallel().tween_property(core, "width", 1.0, SLASH_FADE_TIME)
	if edge != null:
		cut_tween.parallel().tween_property(edge, "width", 3.0, SLASH_FADE_TIME)
