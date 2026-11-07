class_name FxShots
extends RefCounted
## The shots that carry an effect from its source card to its target: the default flaming bolt, the
## orb of light for good effects (heal, buff, summon), and the card-specific styles (thorn, bullet,
## ruby, slash).
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

## Elements whose single-target spells fire the default bolt in a color of their own, instead of the
## color of their domain. To give another element its own shot color, add its line here.
const ELEMENT_SHOT_COLORS := {
	"luz": Color("#fff1b8"), # white-yellow, like holy light
}

## Elements (or area styles) whose single-target spells fly a shot of their own instead of the
## default bolt: a real lightning strike, a thrown rock, an ice shard, a glob of venom, a wind blade.
const SPELL_SHOT_STYLES := {"raio": "raio", "pedra": "pedra", "gelo": "gelo", "veneno": "veneno", "vento": "vento"}

## The hit style a single-target spell fires with: its own "hit_fx" when it declares one (that always
## wins), else the shot of one of its elements, else the shot of its area style (FxCasts.style_of:
## a Tormenta spell with no shot element fires lightning), else the default bolt ("").
## The element is looked up first because some elements (vento) have a shot but no area animation.
func spell_hit_style(card_id: String) -> String:
	var card := CardDB.card(card_id)
	if card.has("hit_fx"):
		return String(card["hit_fx"])
	for element in CardDB.elements_of(card):
		if SPELL_SHOT_STYLES.has(element):
			return SPELL_SHOT_STYLES[element]
	return String(SPELL_SHOT_STYLES.get(host.fx_casts.style_of(card_id), ""))

## The color a single-target spell's shots fly in: its element's color from ELEMENT_SHOT_COLORS when
## it has one there, otherwise `domain_color` (what every other spell uses).
func spell_shot_color(card_id: String, domain_color: Color) -> Color:
	for element in CardDB.elements_of(CardDB.card(card_id)):
		if ELEMENT_SHOT_COLORS.has(element):
			return ELEMENT_SHOT_COLORS[element]
	return domain_color

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
		"tiro":
			return {"charge": (BULLET_CHARGE_FIRST if first_shot else BULLET_CHARGE_NEXT) * pace, "flight": BULLET_FLIGHT * pace}
		"rubi":
			return {"charge": (RUBY_CHARGE_FIRST if first_shot else RUBY_CHARGE_NEXT) * pace, "flight": RUBY_FLIGHT * pace}
		"boon":
			return {"charge": (BOON_CHARGE_FIRST if first_shot else BOON_CHARGE_NEXT) * pace, "flight": BOON_FLIGHT * pace}
		"raio":
			return {"charge": (LIGHTNING_CHARGE_FIRST if first_shot else LIGHTNING_CHARGE_NEXT) * pace, "flight": LIGHTNING_FLIGHT * pace}
		"pedra":
			return {"charge": (ROCK_CHARGE_FIRST if first_shot else ROCK_CHARGE_NEXT) * pace, "flight": ROCK_FLIGHT * pace}
		"gelo":
			return {"charge": (ICE_CHARGE_FIRST if first_shot else ICE_CHARGE_NEXT) * pace, "flight": ICE_FLIGHT * pace}
		"veneno":
			return {"charge": (VENOM_CHARGE_FIRST if first_shot else VENOM_CHARGE_NEXT) * pace, "flight": VENOM_FLIGHT * pace}
		"vento":
			return {"charge": (WIND_CHARGE_FIRST if first_shot else WIND_CHARGE_NEXT) * pace, "flight": WIND_FLIGHT * pace}
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
		"tiro":
			return _bullet_shot(from, to, t, first_shot)
		"rubi":
			return _ruby_shot(from, to, t, first_shot)
		"boon":
			return _boon_shot(from, to, t, col, first_shot)
		"raio":
			return _lightning_shot(from, to, t, col, first_shot)
		"pedra":
			return _rock_shot(from, to, t, first_shot)
		"gelo":
			return _ice_shot(from, to, t, first_shot)
		"veneno":
			return _venom_shot(from, to, t, first_shot)
		"vento":
			return _wind_shot(from, to, t, first_shot)
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

## Timing of the "tiro" hit style (see _bullet_shot): the shooter takes a short aim before its first
## shot, then fires the rest without pausing; a bullet crosses the table almost instantly.
const BULLET_CHARGE_FIRST := 0.10
const BULLET_CHARGE_NEXT := 0.0
const BULLET_FLIGHT := 0.17
## The tracer is a short streak of this many pixels that travels, never a line stretched across the
## whole table (a long thin line in 0.07s read as a laser beam).
const BULLET_STREAK_LENGTH := 42.0
## How long the muzzle flash lasts, and how long the smoke from the impact lingers.
const BULLET_MUZZLE_TIME := 0.09
const BULLET_SMOKE_TIME := 0.5
## Colors of the shot: a hot white-yellow tracer, orange sparks, and gray smoke.
const BULLET_TRACER_COLOR := Color("#fff2b8")
const BULLET_SPARK_COLOR := Color("#ffb347")
const BULLET_SMOKE_COLOR := Color("#9a9a9a")

## The "tiro" hit style, for modern firearms (nothing magic flies out of the shooter):
## 1. aim (first shot of a trigger only): the shooter leans a little toward its target;
## 2. fire: a muzzle flash and a few sparks burst out of the source, and the card kicks back (recoil);
## 3. flight: a thin white-hot tracer line crosses the table in a straight line, nearly instantly;
## 4. impact: a small flash, orange sparks thrown back the way the bullet came, a puff of gray smoke
##    and a dark mark where it hit (a bit off-center, so a volley spreads over the target).
## Follows both ends if they move. Returns the time from t until the bullet lands.
func _bullet_shot(from: Control, to: Control, t: float, first_shot: bool) -> float:
	var timing := _shot_timing("tiro", first_shot)
	var charge: float = timing["charge"]
	var flight: float = timing["flight"]
	var launch_t := t + charge
	var impact_t := launch_t + flight
	var rich := fx_library.fx_scale >= 0.7 # big chains skip the smoke and the bullet mark
	var path := _shot_path(from, to, 0.0, 0.0) # a bullet flies straight
	var ends: Dictionary = path["ends"]
	var refresh_ends: Callable = path["refresh"]
	var point_at: Callable = path["point_at"]
	# where on the target this bullet lands, relative to the target's center
	var hit_offset := Vector2(randf_range(-16.0, 16.0), randf_range(-16.0, 16.0))
	# the lambdas below reach the shot's nodes through this dictionary instead of capturing them
	# (same reason as in _effect_bolt: the nodes may be freed while a lambda is still scheduled)
	var parts := {}
	var alive := func(key: String) -> Node:
		var node = parts.get(key)
		return node if is_instance_valid(node) else null

	# --- 1 and 2. aim, then recoil: the source card leans toward the target, then is kicked back
	if from is CardView:
		var shooter: CardView = from
		var recoil := shooter.create_tween()
		recoil.tween_interval(t)
		if first_shot:
			recoil.tween_method(func(k: float):
				var toward: Vector2 = (ends["b"] - ends["a"]).normalized()
				shooter.shake = toward * 5.0 * k, 0.0, 1.0, charge).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		recoil.tween_method(func(k: float):
			var away: Vector2 = (ends["a"] - ends["b"]).normalized()
			shooter.shake = away * 13.0 * (1.0 - k), 0.0, 1.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		recoil.tween_callback(func(): shooter.shake = Vector2.ZERO)

	# --- 2. fire: muzzle flash and sparks at the source, all in one holder freed together
	var muzzle_holder := Node2D.new()
	muzzle_holder.z_index = 27
	fx.add_child(muzzle_holder)
	parts["muzzle"] = muzzle_holder
	var mt := fx.create_tween()
	mt.tween_interval(launch_t)
	mt.tween_callback(func():
		var holder: Node2D = alive.call("muzzle")
		if holder == null:
			return # the table was reset mid-animation
		refresh_ends.call()
		var toward: Vector2 = (ends["b"] - ends["a"]).normalized()
		var muzzle_point: Vector2 = ends["a"] + toward * 34.0 # a little ahead of the card, where the barrel would be
		var flash := fx_library._glow_sprite(30.0, Color(BULLET_TRACER_COLOR, 0.95))
		flash.position = muzzle_point
		holder.add_child(flash)
		var flash_tween := flash.create_tween()
		flash_tween.tween_property(flash, "scale", flash.scale * 1.2, BULLET_MUZZLE_TIME).from(flash.scale * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		flash_tween.parallel().tween_property(flash, "modulate:a", 0.0, BULLET_MUZZLE_TIME).set_delay(0.02)
		var muzzle_sparks := CPUParticles2D.new()
		muzzle_sparks.emitting = false
		muzzle_sparks.one_shot = true
		muzzle_sparks.explosiveness = 1.0
		muzzle_sparks.local_coords = false
		muzzle_sparks.amount = maxi(4, int(8 * fx_library.fx_scale))
		muzzle_sparks.lifetime = 0.2
		muzzle_sparks.direction = toward
		muzzle_sparks.spread = 22.0
		muzzle_sparks.gravity = Vector2(0, 300)
		muzzle_sparks.initial_velocity_min = 160.0
		muzzle_sparks.initial_velocity_max = 380.0
		muzzle_sparks.scale_amount_min = 1.5
		muzzle_sparks.scale_amount_max = 3.0
		var muzzle_ramp := Gradient.new()
		muzzle_ramp.set_color(0, Color(BULLET_TRACER_COLOR, 0.95))
		muzzle_ramp.set_color(1, Color(BULLET_SPARK_COLOR, 0.0))
		muzzle_sparks.color_ramp = muzzle_ramp
		muzzle_sparks.position = muzzle_point
		holder.add_child(muzzle_sparks)
		muzzle_sparks.emitting = true
		var cleanup := holder.create_tween()
		cleanup.tween_interval(0.4)
		cleanup.tween_callback(holder.queue_free))

	# --- 3. flight: a thin tracer line (pointed at the back) with a tiny bright head
	var tracer := Line2D.new()
	tracer.width = 5.0
	tracer.material = fx_library._additive()
	var tracer_gradient := Gradient.new()
	tracer_gradient.set_color(0, Color(BULLET_SPARK_COLOR, 0.0))
	tracer_gradient.set_color(1, Color(BULLET_TRACER_COLOR, 0.95))
	tracer.gradient = tracer_gradient
	var tracer_width := Curve.new()
	tracer_width.add_point(Vector2(0, 0.0))
	tracer_width.add_point(Vector2(1, 1.0))
	tracer.width_curve = tracer_width
	tracer.z_index = 26
	tracer.visible = false
	fx.add_child(tracer)
	parts["tracer"] = tracer
	var head := fx_library._glow_sprite(7.0, Color(BULLET_TRACER_COLOR, 1.0))
	head.z_index = 26
	head.visible = false
	fx.add_child(head)
	parts["head"] = head
	var ft := fx.create_tween()
	ft.tween_interval(launch_t)
	ft.tween_method(func(k: float):
		refresh_ends.call()
		var tracer_node: Line2D = alive.call("tracer")
		var head_node: Sprite2D = alive.call("head")
		if tracer_node == null or head_node == null:
			return
		var front: Vector2 = ends["a"].lerp(ends["b"] + hit_offset, k)
		var start_point: Vector2 = ends["a"]
		var back: Vector2 = front - (front - start_point).limit_length(BULLET_STREAK_LENGTH)
		tracer_node.points = PackedVector2Array([back, front])
		tracer_node.visible = true
		head_node.position = front
		head_node.visible = true, 0.0, 1.0, flight)
	ft.tween_callback(func():
		for key in ["tracer", "head"]:
			var node: Node = alive.call(key)
			if node != null:
				node.queue_free())

	# --- 4. impact: flash, sparks bouncing back, smoke and a dark mark, all in one holder freed together
	var impact_holder := Node2D.new()
	impact_holder.z_index = 27
	fx.add_child(impact_holder)
	parts["impact"] = impact_holder
	var it := fx.create_tween()
	it.tween_interval(impact_t)
	it.tween_callback(func():
		var holder: Node2D = alive.call("impact")
		if holder == null:
			return
		refresh_ends.call()
		var hit_point: Vector2 = ends["b"] + hit_offset
		var travel: Vector2 = (ends["b"] - ends["a"]).normalized()
		var flash := fx_library._glow_sprite(24.0, Color(BULLET_TRACER_COLOR, 0.9))
		flash.position = hit_point
		holder.add_child(flash)
		var flash_tween := flash.create_tween()
		flash_tween.tween_property(flash, "scale", flash.scale * 1.1, 0.07).from(flash.scale * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		flash_tween.parallel().tween_property(flash, "modulate:a", 0.0, 0.16).set_delay(0.03)
		var sparks := CPUParticles2D.new()
		sparks.emitting = false
		sparks.one_shot = true
		sparks.explosiveness = 1.0
		sparks.local_coords = false
		sparks.amount = maxi(5, int(11 * fx_library.fx_scale))
		sparks.lifetime = 0.35
		sparks.direction = -travel # sparks ricochet back out the way the bullet came in
		sparks.spread = 55.0
		sparks.gravity = Vector2(0, 520)
		sparks.damping_min = 60.0
		sparks.damping_max = 140.0
		sparks.initial_velocity_min = 140.0
		sparks.initial_velocity_max = 380.0
		sparks.scale_amount_min = 1.8
		sparks.scale_amount_max = 3.6
		var spark_ramp := Gradient.new()
		spark_ramp.set_color(0, Color(BULLET_TRACER_COLOR, 0.95))
		spark_ramp.set_color(1, Color(BULLET_SPARK_COLOR, 0.0))
		sparks.color_ramp = spark_ramp
		sparks.position = hit_point
		holder.add_child(sparks)
		sparks.emitting = true
		if rich:
			var smoke := CPUParticles2D.new()
			smoke.emitting = false
			smoke.one_shot = true
			smoke.explosiveness = 0.8
			smoke.local_coords = false
			smoke.amount = 5
			smoke.lifetime = BULLET_SMOKE_TIME
			smoke.direction = Vector2.UP
			smoke.spread = 60.0
			smoke.gravity = Vector2(0, -25)
			smoke.damping_min = 40.0
			smoke.damping_max = 80.0
			smoke.initial_velocity_min = 30.0
			smoke.initial_velocity_max = 70.0
			smoke.scale_amount_min = 5.0
			smoke.scale_amount_max = 9.0
			var smoke_ramp := Gradient.new()
			smoke_ramp.set_color(0, Color(BULLET_SMOKE_COLOR, 0.45))
			smoke_ramp.set_color(1, Color(BULLET_SMOKE_COLOR, 0.0))
			smoke.color_ramp = smoke_ramp
			smoke.position = hit_point
			holder.add_child(smoke)
			smoke.emitting = true
			# the bullet mark: a small dark spot that fades (a normal-blend dot, since the glow sprite is additive)
			var mark := Polygon2D.new()
			var mark_points := PackedVector2Array()
			for step in 8:
				mark_points.append(hit_point + Vector2.from_angle(TAU * step / 8.0) * 3.5)
			mark.polygon = mark_points
			mark.color = Color(0.05, 0.04, 0.04, 0.85)
			holder.add_child(mark)
			var mark_tween := mark.create_tween()
			mark_tween.tween_interval(0.25)
			mark_tween.tween_property(mark, "modulate:a", 0.0, 0.3)
		var cleanup := holder.create_tween()
		cleanup.tween_interval(BULLET_SMOKE_TIME + 0.2)
		cleanup.tween_callback(holder.queue_free))
	return charge + flight

## Timing of the "rubi" hit style (see _ruby_shot): the spitter draws a breath before her first spit,
## then sprays the rest without pausing; a crystal flies a little slower than a bullet, so it reads.
const RUBY_CHARGE_FIRST := 0.14
const RUBY_CHARGE_NEXT := 0.0
const RUBY_FLIGHT := 0.2
## How long the crystal burst on the target takes to fade, and when the whole impact is cleaned up.
const RUBY_BURST_FADE := 0.26
const RUBY_IMPACT_LIFETIME := 0.6
## Colors of the rubies (taken from the Cuspa-Rubi's art): a bright red lit face, a deep red shadow
## face, a pale pink shine for flashes, and a dark outline so a small crystal still reads on a phone.
const RUBY_LIGHT_COLOR := Color("#ff3346")
const RUBY_DARK_COLOR := Color("#8c0016")
const RUBY_SHINE_COLOR := Color("#ffc4cc")
const RUBY_OUTLINE_COLOR := Color("#2b0006")

## One ruby crystal, pointing along +x: a long faceted shard whose upper face is lit and lower face is
## in shadow (two flat polygons, which is what makes it look cut), with a dark outline and, if
## `with_glow`, a faint red glow behind it. `size` scales the whole crystal (1.0 = the main shot).
func _ruby_crystal(size: float, with_glow: bool) -> Node2D:
	var crystal := Node2D.new()
	crystal.scale = Vector2.ONE * size
	if with_glow:
		crystal.add_child(fx_library._glow_sprite(18.0, Color(RUBY_LIGHT_COLOR, 0.45)))
	var tip := Vector2(17, 0)
	var back := Vector2(-14, 0)
	var lit_face := Polygon2D.new()
	lit_face.polygon = PackedVector2Array([tip, Vector2(4, -5.5), Vector2(-10, -3.5), back])
	lit_face.vertex_colors = PackedColorArray([RUBY_SHINE_COLOR, RUBY_LIGHT_COLOR, RUBY_LIGHT_COLOR, RUBY_DARK_COLOR])
	crystal.add_child(lit_face)
	var shadow_face := Polygon2D.new()
	shadow_face.polygon = PackedVector2Array([tip, back, Vector2(-10, 3.5), Vector2(4, 5.5)])
	shadow_face.color = RUBY_DARK_COLOR
	crystal.add_child(shadow_face)
	var outline := Line2D.new()
	outline.points = PackedVector2Array([tip, Vector2(4, -5.5), Vector2(-10, -3.5), back, Vector2(-10, 3.5), Vector2(4, 5.5)])
	outline.closed = true
	outline.width = 1.4
	outline.default_color = RUBY_OUTLINE_COLOR
	outline.joint_mode = Line2D.LINE_JOINT_ROUND
	crystal.add_child(outline)
	return crystal

## The "rubi" hit style, for the Cuspa-Rubi, who spits rubies (crystals, not fire):
## 1. breath (first shot of a trigger only): the spitter leans back, away from the target;
## 2. spit: she snaps forward and a few tiny red chips spray out of her toward the target;
## 3. flight: a long ruby crystal flies point-first on a slight arc, with a short red streak and
##    (when the effects budget allows it) two small chips flying beside it, like the spray in her art;
## 4. impact: the crystal bursts into a red star of spikes with a flash, and shards bounce off
##    (a bit off-center, so a volley spreads over the target).
## Kept light for phones: a handful of flat polygons and two small particle bursts per shot, fewer
## when many shots fire at once. Follows both ends if they move. Returns the time until it lands.
func _ruby_shot(from: Control, to: Control, t: float, first_shot: bool) -> float:
	var timing := _shot_timing("rubi", first_shot)
	var charge: float = timing["charge"]
	var flight: float = timing["flight"]
	var launch_t := t + charge
	var impact_t := launch_t + flight
	var rich := fx_library.fx_scale >= 0.7 # big chains skip the side chips and use fewer spikes
	var path := _shot_path(from, to, 0.1, 50.0)
	var ends: Dictionary = path["ends"]
	var refresh_ends: Callable = path["refresh"]
	var point_at: Callable = path["point_at"]
	# where on the target this crystal lands, relative to the target's center
	var hit_offset := Vector2(randf_range(-16.0, 16.0), randf_range(-16.0, 16.0))
	# the lambdas below reach the shot's nodes through this dictionary instead of capturing them
	# (same reason as in _effect_bolt: the nodes may be freed while a lambda is still scheduled)
	var parts := {}
	var alive := func(key: String) -> Node:
		var node = parts.get(key)
		return node if is_instance_valid(node) else null

	# --- 1 and 2. lean back for breath, then snap forward as she spits
	if from is CardView:
		var spitter: CardView = from
		var lunge := spitter.create_tween()
		lunge.tween_interval(t)
		if first_shot:
			lunge.tween_method(func(k: float):
				var away: Vector2 = (ends["a"] - ends["b"]).normalized()
				spitter.shake = away * 8.0 * k, 0.0, 1.0, charge).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		lunge.tween_method(func(k: float):
			var toward: Vector2 = (ends["b"] - ends["a"]).normalized()
			spitter.shake = toward * 10.0 * (1.0 - k), 0.0, 1.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		lunge.tween_callback(func(): spitter.shake = Vector2.ZERO)

	var spray := CPUParticles2D.new()
	spray.emitting = false
	spray.one_shot = true
	spray.explosiveness = 0.95
	spray.local_coords = false
	spray.amount = maxi(3, int(7 * fx_library.fx_scale))
	spray.lifetime = 0.35
	spray.spread = 25.0
	spray.gravity = Vector2(0, 260)
	spray.damping_min = 120.0
	spray.damping_max = 200.0
	spray.initial_velocity_min = 140.0
	spray.initial_velocity_max = 320.0
	spray.angle_min = 0.0
	spray.angle_max = 360.0
	spray.scale_amount_min = 2.0
	spray.scale_amount_max = 3.5
	var spray_ramp := Gradient.new()
	spray_ramp.set_color(0, RUBY_LIGHT_COLOR)
	spray_ramp.set_color(1, Color(RUBY_DARK_COLOR, 0.0))
	spray.color_ramp = spray_ramp
	spray.z_index = 25
	fx.add_child(spray)
	parts["spray"] = spray
	var st := fx.create_tween()
	st.tween_interval(launch_t)
	st.tween_callback(func():
		var spray_node: CPUParticles2D = alive.call("spray")
		if spray_node == null:
			return # the table was reset mid-animation
		refresh_ends.call()
		var toward: Vector2 = (ends["b"] - ends["a"]).normalized()
		spray_node.position = ends["a"] + toward * 26.0 # from the mouth, a little ahead of the card
		spray_node.direction = toward
		spray_node.emitting = true)
	st.tween_interval(spray.lifetime + 0.1)
	st.tween_callback(func():
		var spray_node: Node = alive.call("spray")
		if spray_node != null:
			spray_node.queue_free())

	# --- 3. flight: the main crystal, its streak, and (rich only) two small chips beside it
	var crystal := _ruby_crystal(1.25, true)
	crystal.z_index = 26
	crystal.visible = false
	fx.add_child(crystal)
	parts["crystal"] = crystal
	var streak := Line2D.new()
	streak.width = 5.0
	streak.material = fx_library._additive()
	var streak_gradient := Gradient.new()
	streak_gradient.set_color(0, Color(RUBY_DARK_COLOR, 0.0))
	streak_gradient.set_color(1, Color(RUBY_LIGHT_COLOR, 0.6))
	streak.gradient = streak_gradient
	var streak_width := Curve.new() # pointed at the back
	streak_width.add_point(Vector2(0, 0.0))
	streak_width.add_point(Vector2(1, 1))
	streak.width_curve = streak_width
	streak.z_index = 25
	streak.visible = false
	fx.add_child(streak)
	parts["streak"] = streak
	# each chip: how far it sits to the side of the path, and how far behind the main crystal
	var chips := []
	if rich:
		for side in [-1.0, 1.0]:
			var chip := _ruby_crystal(randf_range(0.4, 0.55), false)
			chip.z_index = 25
			chip.visible = false
			fx.add_child(chip)
			var key := "chip_%d" % chips.size()
			parts[key] = chip
			chips.append({"key": key, "side": side * randf_range(9.0, 15.0), "lag": randf_range(0.05, 0.12)})
	var ft := fx.create_tween()
	ft.tween_interval(launch_t)
	ft.tween_method(func(k: float):
		refresh_ends.call()
		var head := ease(k, 1.3) # leaves the mouth hard and keeps speeding up a little
		var crystal_node: Node2D = alive.call("crystal")
		if crystal_node == null:
			return
		var tip: Vector2 = point_at.call(head)
		var heading: Vector2 = tip - point_at.call(maxf(head - 0.03, 0.0))
		if heading.length() > 0.5:
			crystal_node.rotation = heading.angle()
		crystal_node.position = tip
		crystal_node.visible = true
		var side_axis: Vector2 = heading.normalized().orthogonal()
		for chip_info in chips:
			var chip_node: Node2D = alive.call(chip_info["key"])
			if chip_node == null:
				continue
			var chip_u: float = maxf(head - chip_info["lag"], 0.0)
			chip_node.position = point_at.call(chip_u) + side_axis * chip_info["side"] * minf(chip_u * 4.0, 1.0)
			chip_node.rotation = crystal_node.rotation
			chip_node.visible = chip_u > 0.0
		var streak_node: Line2D = alive.call("streak")
		if streak_node != null:
			var streak_points := PackedVector2Array()
			var streak_start := maxf(head - 0.1, 0.0)
			for j in 6:
				streak_points.append(point_at.call(lerpf(streak_start, head, j / 5.0)))
			streak_node.points = streak_points
			streak_node.visible = true, 0.0, 1.0, flight)
	ft.tween_callback(func():
		var keys := ["crystal", "streak"]
		for chip_info in chips:
			keys.append(chip_info["key"])
		for key in keys:
			var node: Node = alive.call(key)
			if node != null:
				node.queue_free())

	# --- 4. impact: a flash, a red star of crystal spikes and shards bouncing off, in one holder
	var impact_holder := Node2D.new()
	impact_holder.z_index = 27
	fx.add_child(impact_holder)
	parts["impact"] = impact_holder
	var it := fx.create_tween()
	it.tween_interval(impact_t)
	it.tween_callback(func():
		var holder: Node2D = alive.call("impact")
		if holder == null:
			return
		refresh_ends.call()
		var hit_point: Vector2 = ends["b"] + hit_offset
		var travel: Vector2 = (ends["b"] - point_at.call(0.85)).normalized()
		var flash := fx_library._glow_sprite(28.0, Color(RUBY_SHINE_COLOR, 0.9))
		flash.position = hit_point
		holder.add_child(flash)
		var flash_tween := flash.create_tween()
		flash_tween.tween_property(flash, "scale", flash.scale * 1.15, 0.08).from(flash.scale * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		flash_tween.parallel().tween_property(flash, "modulate:a", 0.0, 0.2).set_delay(0.04)
		# the star: thin spikes of ruby around the hit point that shoot out and fade (like the
		# red starbursts on the ground in the card's art)
		var star := Node2D.new()
		star.position = hit_point
		holder.add_child(star)
		var spike_count := 7 if rich else 5
		var first_angle := randf() * TAU
		for i in spike_count:
			var angle := first_angle + TAU * i / spike_count + randf_range(-0.25, 0.25)
			var reach := randf_range(16.0, 30.0)
			var spike := Polygon2D.new()
			spike.polygon = PackedVector2Array([Vector2(reach, 0), Vector2(3, -2.6), Vector2(3, 2.6)])
			spike.vertex_colors = PackedColorArray([RUBY_SHINE_COLOR, RUBY_LIGHT_COLOR, RUBY_DARK_COLOR])
			spike.rotation = angle
			star.add_child(spike)
		var star_tween := star.create_tween()
		star_tween.tween_property(star, "scale", Vector2.ONE, 0.08).from(Vector2.ONE * 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		star_tween.tween_property(star, "modulate:a", 0.0, RUBY_BURST_FADE)
		# shards: small red bits thrown back out the way the crystal came in, then falling
		var shards := CPUParticles2D.new()
		shards.emitting = false
		shards.one_shot = true
		shards.explosiveness = 1.0
		shards.local_coords = false
		shards.amount = maxi(4, int(10 * fx_library.fx_scale))
		shards.lifetime = 0.45
		shards.direction = -travel
		shards.spread = 70.0
		shards.gravity = Vector2(0, 640)
		shards.damping_min = 60.0
		shards.damping_max = 130.0
		shards.initial_velocity_min = 120.0
		shards.initial_velocity_max = 300.0
		shards.angle_min = 0.0
		shards.angle_max = 360.0
		shards.scale_amount_min = 2.2
		shards.scale_amount_max = 4.2
		var shard_ramp := Gradient.new()
		shard_ramp.set_color(0, RUBY_LIGHT_COLOR)
		shard_ramp.set_color(1, Color(RUBY_DARK_COLOR, 0.0))
		shards.color_ramp = shard_ramp
		shards.position = hit_point
		holder.add_child(shards)
		shards.emitting = true
		var cleanup := holder.create_tween()
		cleanup.tween_interval(RUBY_IMPACT_LIFETIME)
		cleanup.tween_callback(holder.queue_free))
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

## ---------------------------------------------------------------------------------------------
## Lightning ("raio"): the single-target shot of lightning spells (Fio Desencapado, Raio Encadeado...)

## Timing of the "raio" hit style: a short crackle on the caster before the first strike, then the
## strike itself is almost instant (lightning does not travel, it is just there).
const LIGHTNING_CHARGE_FIRST := 0.16
const LIGHTNING_CHARGE_NEXT := 0.0
const LIGHTNING_FLIGHT := 0.05
## How long the bolt stays on the table flickering after it lands, and how long it takes to go out.
const LIGHTNING_HOLD_TIME := 0.2
const LIGHTNING_FADE_TIME := 0.14
## How often the bolt redraws its zigzag while it is on the table (a new jagged shape each time is
## what makes it crackle).
const LIGHTNING_FLICKER_STEP := 0.045
## The bolt's zigzag: how many segments from end to end, and how far each corner may swerve
## sideways (a fraction of the distance, at most LIGHTNING_MAX_SWERVE pixels).
const LIGHTNING_SEGMENTS := 11
const LIGHTNING_SWERVE := 0.09
const LIGHTNING_MAX_SWERVE := 30.0

## A jagged lightning line from a to b: a straight line broken into LIGHTNING_SEGMENTS pieces, each
## inner corner pushed sideways at random (the ends stay put, so the bolt always touches both cards).
func _lightning_points(a: Vector2, b: Vector2) -> PackedVector2Array:
	var sideways := (b - a).orthogonal().normalized()
	var swerve := minf(a.distance_to(b) * LIGHTNING_SWERVE, LIGHTNING_MAX_SWERVE)
	var points := PackedVector2Array([a])
	for step in range(1, LIGHTNING_SEGMENTS):
		var along := float(step) / LIGHTNING_SEGMENTS
		points.append(a.lerp(b, along) + sideways * randf_range(-1.0, 1.0) * swerve)
	points.append(b)
	return points

## A small fork of lightning splitting off the main bolt at `start`, going roughly toward `heading`.
func _lightning_fork_points(start: Vector2, heading: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array([start])
	var tip := start
	for step in 3:
		tip += heading.rotated(randf_range(-0.6, 0.6)) * randf_range(14.0, 24.0)
		points.append(tip)
	return points

## The "raio" hit style, a real thunderbolt (not a beam):
## 1. crackle (first shot of a trigger only): purple sparks snap around the caster;
## 2. strike: a jagged bolt appears from the caster to the target at once, a bright core inside a
##    wide purple glow, with small forks splitting off it;
## 3. flicker: for a moment the bolt keeps redrawing its zigzag and flashing brighter and dimmer;
## 4. impact: a flash on the target and purple sparks bursting out; then the bolt goes out.
## `col` is the spell's color (Tormenta's purple). Follows both ends if they move. Returns the time
## from t until the bolt lands.
func _lightning_shot(from: Control, to: Control, t: float, col: Color, first_shot: bool) -> float:
	var timing := _shot_timing("raio", first_shot)
	var charge: float = timing["charge"]
	var flight: float = timing["flight"]
	var launch_t := t + charge
	var impact_t := launch_t + flight
	var rich := fx_library.fx_scale >= 0.7 # big chains skip the forks
	var path := _shot_path(from, to, 0.0, 0.0)
	var ends: Dictionary = path["ends"]
	var refresh_ends: Callable = path["refresh"]
	var core_color := col.lightened(0.7) # almost white, tinted purple
	var glow_color := Color(col, 0.45)
	# the lambdas below reach the shot's nodes through this dictionary instead of capturing them
	# (the nodes may be freed by a table reset while a lambda is still scheduled)
	var parts := {}
	var alive := func(key: String) -> Node:
		var node = parts.get(key)
		return node if is_instance_valid(node) else null

	# --- 1. crackle on the caster (first shot only)
	if first_shot and charge > 0.0:
		var crackle_tween := fx.create_tween()
		crackle_tween.tween_interval(t)
		crackle_tween.tween_callback(func():
			refresh_ends.call()
			var crackle := CPUParticles2D.new()
			crackle.emitting = false
			crackle.one_shot = true
			crackle.explosiveness = 0.6
			crackle.local_coords = false
			crackle.amount = maxi(4, int(10 * fx_library.fx_scale))
			crackle.lifetime = 0.18
			crackle.spread = 180.0
			crackle.gravity = Vector2.ZERO
			crackle.initial_velocity_min = 60.0
			crackle.initial_velocity_max = 160.0
			crackle.scale_amount_min = 1.5
			crackle.scale_amount_max = 3.0
			crackle.color = core_color
			crackle.material = fx_library._additive()
			crackle.z_index = 27
			crackle.position = ends["a"]
			fx.add_child(crackle)
			crackle.emitting = true
			var cleanup := crackle.create_tween()
			cleanup.tween_interval(0.5)
			cleanup.tween_callback(crackle.queue_free))

	# --- 2 and 3. the bolt: a wide glow line and a thin core line, plus forks, all in one holder
	var bolt_holder := Node2D.new()
	bolt_holder.z_index = 26
	bolt_holder.visible = false
	fx.add_child(bolt_holder)
	parts["bolt"] = bolt_holder
	var glow_line := Line2D.new()
	glow_line.width = 22.0
	glow_line.default_color = glow_color
	glow_line.material = fx_library._additive()
	glow_line.joint_mode = Line2D.LINE_JOINT_ROUND
	bolt_holder.add_child(glow_line)
	parts["glow"] = glow_line
	var core_line := Line2D.new()
	core_line.width = 5.0
	core_line.default_color = core_color
	core_line.material = fx_library._additive()
	bolt_holder.add_child(core_line)
	parts["core"] = core_line
	var fork_count := 2 if rich else 0
	for fork_index in fork_count:
		var fork := Line2D.new()
		fork.width = 3.0
		fork.default_color = Color(core_color, 0.8)
		fork.material = fx_library._additive()
		bolt_holder.add_child(fork)
		parts["fork_%d" % fork_index] = fork
	# draws a new zigzag (called again at every flicker step)
	var redraw_bolt := func():
		var holder: Node2D = alive.call("bolt")
		if holder == null:
			return
		refresh_ends.call()
		var points := _lightning_points(ends["a"], ends["b"])
		(alive.call("glow") as Line2D).points = points
		(alive.call("core") as Line2D).points = points
		var heading: Vector2 = (ends["b"] - ends["a"]).normalized()
		for fork_index in fork_count:
			var fork: Line2D = alive.call("fork_%d" % fork_index)
			var split_at := points[randi_range(2, points.size() - 3)]
			var side := heading.orthogonal() * (1.0 if randf() < 0.5 else -1.0)
			fork.points = _lightning_fork_points(split_at, (heading + side).normalized())
		# each flash is a little brighter or dimmer than the last
		holder.modulate.a = randf_range(0.65, 1.0)
	var bolt_tween := fx.create_tween()
	bolt_tween.tween_interval(launch_t)
	bolt_tween.tween_callback(func():
		var holder: Node2D = alive.call("bolt")
		if holder != null:
			holder.visible = true
		redraw_bolt.call())
	var flicker_count := int(ceil((flight + LIGHTNING_HOLD_TIME) / LIGHTNING_FLICKER_STEP))
	for flicker_index in flicker_count:
		bolt_tween.tween_interval(LIGHTNING_FLICKER_STEP)
		bolt_tween.tween_callback(redraw_bolt)
	bolt_tween.tween_property(bolt_holder, "modulate:a", 0.0, LIGHTNING_FADE_TIME)
	bolt_tween.tween_callback(bolt_holder.queue_free)

	# --- 4. impact: a flash and a burst of sparks on the target
	var impact_holder := Node2D.new()
	impact_holder.z_index = 27
	fx.add_child(impact_holder)
	parts["impact"] = impact_holder
	var impact_tween := fx.create_tween()
	impact_tween.tween_interval(impact_t)
	impact_tween.tween_callback(func():
		var holder: Node2D = alive.call("impact")
		if holder == null:
			return
		refresh_ends.call()
		var hit_point: Vector2 = ends["b"]
		var flash := fx_library._glow_sprite(56.0, Color(core_color, 0.9))
		flash.position = hit_point
		holder.add_child(flash)
		var flash_tween := flash.create_tween()
		flash_tween.tween_property(flash, "scale", flash.scale * 1.15, 0.08).from(flash.scale * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		flash_tween.parallel().tween_property(flash, "modulate:a", 0.0, 0.25).set_delay(0.05)
		var sparks := CPUParticles2D.new()
		sparks.emitting = false
		sparks.one_shot = true
		sparks.explosiveness = 1.0
		sparks.local_coords = false
		sparks.amount = maxi(6, int(14 * fx_library.fx_scale))
		sparks.lifetime = 0.3
		sparks.spread = 180.0
		sparks.gravity = Vector2.ZERO
		sparks.damping_min = 200.0
		sparks.damping_max = 400.0
		sparks.initial_velocity_min = 180.0
		sparks.initial_velocity_max = 420.0
		sparks.scale_amount_min = 1.5
		sparks.scale_amount_max = 3.2
		var spark_ramp := Gradient.new()
		spark_ramp.set_color(0, Color(core_color, 1.0))
		spark_ramp.set_color(1, Color(col, 0.0))
		sparks.color_ramp = spark_ramp
		sparks.material = fx_library._additive()
		sparks.position = hit_point
		holder.add_child(sparks)
		sparks.emitting = true
		var cleanup := holder.create_tween()
		cleanup.tween_interval(0.5)
		cleanup.tween_callback(holder.queue_free))
	return charge + flight

## ---------------------------------------------------------------------------------------------
## Rock ("pedra"): the single-target shot of stone/earth spells (Projétil Geomântico, Deslizamento
## de Placas...)

## Timing of the "pedra" hit style: the caster heaves before the first throw; a rock is heavy, so it
## flies slower than a bolt, on a high arc.
const ROCK_CHARGE_FIRST := 0.16
const ROCK_CHARGE_NEXT := 0.0
const ROCK_FLIGHT := 0.3
## How long the dust from the impact lingers.
const ROCK_DUST_TIME := 0.55
## Colors of the rock: brown stone, a dark outline, a lighter top face, and the dust it raises.
const ROCK_COLOR := Color("#8a6f4d")
const ROCK_DARK_COLOR := Color("#3b2c1d")
const ROCK_LIGHT_COLOR := Color("#b89a72")
const ROCK_DUST_COLOR := Color("#a8947a")

## A lumpy rock drawn around (0, 0): an uneven polygon with a dark outline and a lighter face on top.
func _make_rock(radius: float) -> Node2D:
	var rock := Node2D.new()
	var outline_points := PackedVector2Array()
	var corner_count := 8
	for corner in corner_count:
		var angle := TAU * corner / corner_count
		outline_points.append(Vector2.from_angle(angle) * radius * randf_range(0.72, 1.08))
	var body := Polygon2D.new()
	body.polygon = outline_points
	body.color = ROCK_COLOR
	rock.add_child(body)
	# the lit face: the same shape, smaller, pushed up and to the left
	var face_points := PackedVector2Array()
	for point in outline_points:
		face_points.append(point * 0.55 + Vector2(-radius * 0.18, -radius * 0.2))
	var face := Polygon2D.new()
	face.polygon = face_points
	face.color = ROCK_LIGHT_COLOR
	rock.add_child(face)
	var outline := Line2D.new()
	outline.points = outline_points
	outline.closed = true
	outline.width = 3.0
	outline.default_color = ROCK_DARK_COLOR
	outline.joint_mode = Line2D.LINE_JOINT_ROUND
	rock.add_child(outline)
	return rock

## The "pedra" hit style, a thrown rock:
## 1. heave (first shot of a trigger only): the caster leans back, away from the target;
## 2. throw: the caster snaps forward;
## 3. flight: a lumpy brown rock tumbles over on a high arc, shedding a trail of dust;
## 4. impact: it smashes into the target: chips of stone bounce off, a cloud of dust rises and the
##    target card is knocked back the way the rock was going.
## Follows both ends if they move. Returns the time from t until the rock lands.
func _rock_shot(from: Control, to: Control, t: float, first_shot: bool) -> float:
	var timing := _shot_timing("pedra", first_shot)
	var charge: float = timing["charge"]
	var flight: float = timing["flight"]
	var launch_t := t + charge
	var impact_t := launch_t + flight
	var rich := fx_library.fx_scale >= 0.7 # big chains skip the dust trail
	var path := _shot_path(from, to, 0.3, 110.0) # a rock is lobbed: a high arc
	var ends: Dictionary = path["ends"]
	var refresh_ends: Callable = path["refresh"]
	var point_at: Callable = path["point_at"]
	# the lambdas below reach the shot's nodes through this dictionary instead of capturing them
	var parts := {}
	var alive := func(key: String) -> Node:
		var node = parts.get(key)
		return node if is_instance_valid(node) else null

	# --- 1 and 2. heave and throw: the caster card leans back, then snaps toward the target
	if from is CardView:
		var thrower_ref: WeakRef = weakref(from)
		var throw_motion := fx.create_tween()
		throw_motion.tween_interval(t)
		if first_shot and charge > 0.0:
			throw_motion.tween_method(func(k: float):
				var thrower = thrower_ref.get_ref()
				if thrower is CardView:
					var away: Vector2 = (ends["a"] - ends["b"]).normalized()
					thrower.shake = away * 8.0 * k, 0.0, 1.0, charge).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		throw_motion.tween_method(func(k: float):
			var thrower = thrower_ref.get_ref()
			if thrower is CardView:
				var toward: Vector2 = (ends["b"] - ends["a"]).normalized()
				thrower.shake = toward * 10.0 * (1.0 - k), 0.0, 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		throw_motion.tween_callback(func():
			var thrower = thrower_ref.get_ref()
			if thrower is CardView:
				thrower.shake = Vector2.ZERO)

	# --- 3. flight: the tumbling rock, with a dust emitter riding along behind it
	var rock := _make_rock(21.0)
	rock.z_index = 26
	rock.visible = false
	fx.add_child(rock)
	parts["rock"] = rock
	if rich:
		var trail := CPUParticles2D.new()
		trail.emitting = false
		trail.local_coords = false # the dust stays where it was shed, so it draws a trail
		trail.amount = 14
		trail.lifetime = 0.35
		trail.spread = 180.0
		trail.gravity = Vector2(0, 40)
		trail.initial_velocity_min = 5.0
		trail.initial_velocity_max = 25.0
		trail.scale_amount_min = 5.0
		trail.scale_amount_max = 9.0
		var trail_ramp := Gradient.new()
		trail_ramp.set_color(0, Color(ROCK_DUST_COLOR, 0.55))
		trail_ramp.set_color(1, Color(ROCK_DUST_COLOR, 0.0))
		trail.color_ramp = trail_ramp
		trail.z_index = 25
		fx.add_child(trail)
		parts["trail"] = trail
	var spin_direction := 1.0 if randf() < 0.5 else -1.0
	var flight_tween := fx.create_tween()
	flight_tween.tween_interval(launch_t)
	flight_tween.tween_callback(func():
		var trail_node: CPUParticles2D = alive.call("trail")
		if trail_node != null:
			trail_node.position = ends["a"]
			trail_node.emitting = true)
	flight_tween.tween_method(func(k: float):
		refresh_ends.call()
		var rock_node: Node2D = alive.call("rock")
		if rock_node == null:
			return
		var position_now: Vector2 = point_at.call(k)
		rock_node.position = position_now
		rock_node.rotation = spin_direction * k * TAU * 1.2 # it tumbles over as it flies
		# a lobbed rock looks a little bigger at the top of its arc, as if closer to the camera
		rock_node.scale = Vector2.ONE * (1.0 + 0.25 * sin(k * PI))
		rock_node.visible = true
		var trail_node: CPUParticles2D = alive.call("trail")
		if trail_node != null:
			trail_node.position = position_now, 0.0, 1.0, flight)
	flight_tween.tween_callback(func():
		var rock_node: Node = alive.call("rock")
		if rock_node != null:
			rock_node.queue_free()
		var trail_node: CPUParticles2D = alive.call("trail")
		if trail_node != null:
			trail_node.emitting = false
			var trail_cleanup := trail_node.create_tween()
			trail_cleanup.tween_interval(0.4)
			trail_cleanup.tween_callback(trail_node.queue_free))

	# --- 4. impact: stone chips, a dust cloud, and the target knocked back
	var impact_holder := Node2D.new()
	impact_holder.z_index = 27
	fx.add_child(impact_holder)
	parts["impact"] = impact_holder
	var target_ref: WeakRef = weakref(to)
	var impact_tween := fx.create_tween()
	impact_tween.tween_interval(impact_t)
	impact_tween.tween_callback(func():
		var holder: Node2D = alive.call("impact")
		if holder == null:
			return
		refresh_ends.call()
		var hit_point: Vector2 = ends["b"]
		var travel: Vector2 = (ends["b"] - ends["a"]).normalized()
		var chips := CPUParticles2D.new()
		chips.emitting = false
		chips.one_shot = true
		chips.explosiveness = 1.0
		chips.local_coords = false
		chips.amount = maxi(6, int(14 * fx_library.fx_scale))
		chips.lifetime = 0.45
		chips.direction = Vector2.UP
		chips.spread = 75.0
		chips.gravity = Vector2(0, 700) # stone is heavy: the chips fall back down fast
		chips.initial_velocity_min = 120.0
		chips.initial_velocity_max = 280.0
		chips.angular_velocity_min = -360.0
		chips.angular_velocity_max = 360.0
		chips.scale_amount_min = 4.5
		chips.scale_amount_max = 8.5
		var chip_ramp := Gradient.new()
		chip_ramp.set_color(0, ROCK_COLOR)
		chip_ramp.set_color(1, Color(ROCK_DARK_COLOR, 0.0))
		chips.color_ramp = chip_ramp
		chips.position = hit_point
		holder.add_child(chips)
		chips.emitting = true
		var dust := CPUParticles2D.new()
		dust.emitting = false
		dust.one_shot = true
		dust.explosiveness = 0.9
		dust.local_coords = false
		dust.amount = maxi(6, int(12 * fx_library.fx_scale))
		dust.lifetime = ROCK_DUST_TIME
		dust.spread = 180.0
		dust.gravity = Vector2(0, -20)
		dust.damping_min = 60.0
		dust.damping_max = 120.0
		dust.initial_velocity_min = 40.0
		dust.initial_velocity_max = 110.0
		dust.scale_amount_min = 12.0
		dust.scale_amount_max = 20.0
		var dust_ramp := Gradient.new()
		dust_ramp.set_color(0, Color(ROCK_DUST_COLOR, 0.6))
		dust_ramp.set_color(1, Color(ROCK_DUST_COLOR, 0.0))
		dust.color_ramp = dust_ramp
		dust.position = hit_point
		holder.add_child(dust)
		dust.emitting = true
		# the target is knocked back the way the rock was going, then settles
		var struck = target_ref.get_ref()
		if struck is CardView:
			var knock := fx.create_tween()
			knock.tween_method(func(k: float):
				var target_view = target_ref.get_ref()
				if target_view is CardView:
					target_view.shake = travel * 12.0 * (1.0 - k), 0.0, 1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var cleanup := holder.create_tween()
		cleanup.tween_interval(ROCK_DUST_TIME + 0.2)
		cleanup.tween_callback(holder.queue_free))
	return charge + flight

# ---------------------------------------------------------------------------------------------
# Shared helper of the ice, venom and wind shots

## A burst of particles that all fly out at once and then stop (the splash, the shards, the puff of
## an impact). Only the settings every burst shares are set here; each shot sets its own direction,
## speed and size on the returned node, adds it to the scene and then sets `emitting = true`.
func _particle_burst(amount: int, lifetime: float, start_color: Color, end_color: Color) -> CPUParticles2D:
	var burst := CPUParticles2D.new()
	burst.emitting = false
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.local_coords = false
	burst.amount = maxi(4, int(amount * fx_library.fx_scale)) # big chains throw fewer particles
	burst.lifetime = lifetime
	var fade_ramp := Gradient.new()
	fade_ramp.set_color(0, start_color)
	fade_ramp.set_color(1, end_color)
	burst.color_ramp = fade_ramp
	return burst

## Knocks the target card back the way the shot was going (`travel`, by `distance` pixels), then
## lets it settle back in place.
func _knock_back(to: Control, travel: Vector2, distance: float, duration: float) -> void:
	if not to is CardView:
		return
	var target_ref: WeakRef = weakref(to)
	var knock := fx.create_tween()
	knock.tween_method(func(k: float):
		var target_view = target_ref.get_ref()
		if target_view is CardView:
			target_view.shake = travel * distance * (1.0 - k), 0.0, 1.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# ---------------------------------------------------------------------------------------------
# "gelo": an ice shard

const ICE_CHARGE_FIRST := 0.18 ## the frost gathering on the caster before the first shard
const ICE_CHARGE_NEXT := 0.0
const ICE_FLIGHT := 0.22 ## time in the air: a shard is fast and flies almost straight
const ICE_SHATTER_TIME := 0.5 ## how long the shards and the frost of the impact last
const ICE_BODY_COLOR := Color("#a9e6ff")
const ICE_LIGHT_COLOR := Color("#f2ffff")
const ICE_DARK_COLOR := Color("#3f8fb8")
const ICE_FROST_COLOR := Color("#dff6ff")

## Builds the ice shard, pointing right (+x): a long sharp crystal with a bright lit facet down its
## middle and a dark blue edge.
func _make_ice_shard(length: float) -> Node2D:
	var shard := Node2D.new()
	var width := length * 0.28
	var outline_points := PackedVector2Array([
		Vector2(length * 0.6, 0), # the sharp tip, in front
		Vector2(length * 0.05, -width * 0.5),
		Vector2(-length * 0.4, -width * 0.3),
		Vector2(-length * 0.32, 0), # the broken-off back end
		Vector2(-length * 0.4, width * 0.3),
		Vector2(length * 0.05, width * 0.5),
	])
	var body := Polygon2D.new()
	body.polygon = outline_points
	body.color = Color(ICE_BODY_COLOR, 0.9)
	shard.add_child(body)
	var facet := Polygon2D.new() # the lit face: a thin bright sliver along the top half
	facet.polygon = PackedVector2Array([
		Vector2(length * 0.55, 0), Vector2(length * 0.05, -width * 0.38), Vector2(-length * 0.3, -width * 0.15), Vector2(length * 0.05, -width * 0.05),
	])
	facet.color = ICE_LIGHT_COLOR
	shard.add_child(facet)
	var edge := Line2D.new()
	var closed_outline := outline_points.duplicate()
	closed_outline.append(outline_points[0])
	edge.points = closed_outline
	edge.width = 2.0
	edge.default_color = ICE_DARK_COLOR
	edge.joint_mode = Line2D.LINE_JOINT_SHARP
	shard.add_child(edge)
	var glow := fx_library._glow_sprite(length * 0.55, Color(ICE_BODY_COLOR, 0.45))
	glow.z_index = -1
	shard.add_child(glow)
	return shard

## The "gelo" hit style, an ice shard:
## 1. frost (first shot of a trigger only): a cold glow swells on the caster and frost sparkles drift in;
## 2. flight: a sharp crystal flies almost straight at the target, point first, leaving a trail of
##    glittering ice dust;
## 3. impact: it shatters: splinters of ice fly off, a puff of frost spreads and a cold flash blinks
##    on the target, which is jolted back a little.
## Follows both ends if they move. Returns the time from t until the shard lands.
func _ice_shot(from: Control, to: Control, t: float, first_shot: bool) -> float:
	var timing := _shot_timing("gelo", first_shot)
	var charge: float = timing["charge"]
	var flight: float = timing["flight"]
	var launch_t := t + charge
	var impact_t := launch_t + flight
	var rich := fx_library.fx_scale >= 0.7 # big chains skip the frost on the caster and the trail
	var path := _shot_path(from, to, 0.06, 30.0) # nearly straight
	var ends: Dictionary = path["ends"]
	var refresh_ends: Callable = path["refresh"]
	var point_at: Callable = path["point_at"]
	# the lambdas below reach the shot's nodes through this dictionary instead of capturing them
	var parts := {}
	var alive := func(key: String) -> Node:
		var node = parts.get(key)
		return node if is_instance_valid(node) else null

	# --- 1. frost gathering on the caster
	if first_shot and charge > 0.0 and rich:
		var frost_glow := fx_library._glow_sprite(48.0, Color(ICE_BODY_COLOR, 0.0))
		frost_glow.position = ends["a"]
		frost_glow.z_index = 26
		fx.add_child(frost_glow)
		var frost_tween := frost_glow.create_tween()
		frost_tween.tween_interval(t)
		frost_tween.tween_property(frost_glow, "modulate:a", 1.0, charge)
		frost_tween.parallel().tween_property(frost_glow, "scale", Vector2.ONE * 1.3, charge)
		frost_tween.tween_property(frost_glow, "modulate:a", 0.0, 0.15)
		frost_tween.tween_callback(frost_glow.queue_free)

	# --- 2. flight: the shard, pointing where it goes, with glittering dust behind it
	var shard := _make_ice_shard(54.0)
	shard.z_index = 26
	shard.visible = false
	fx.add_child(shard)
	parts["shard"] = shard
	if rich:
		var glitter := CPUParticles2D.new()
		glitter.emitting = false
		glitter.local_coords = false # the dust stays where it was shed, so it draws a trail
		glitter.amount = 18
		glitter.lifetime = 0.3
		glitter.spread = 180.0
		glitter.gravity = Vector2.ZERO
		glitter.initial_velocity_min = 5.0
		glitter.initial_velocity_max = 30.0
		glitter.scale_amount_min = 2.0
		glitter.scale_amount_max = 4.5
		var glitter_ramp := Gradient.new()
		glitter_ramp.set_color(0, ICE_LIGHT_COLOR)
		glitter_ramp.set_color(1, Color(ICE_BODY_COLOR, 0.0))
		glitter.color_ramp = glitter_ramp
		glitter.material = fx_library._additive()
		glitter.z_index = 25
		fx.add_child(glitter)
		parts["glitter"] = glitter
	var flight_tween := fx.create_tween()
	flight_tween.tween_interval(launch_t)
	flight_tween.tween_callback(func():
		var glitter_node: CPUParticles2D = alive.call("glitter")
		if glitter_node != null:
			glitter_node.position = ends["a"]
			glitter_node.emitting = true)
	flight_tween.tween_method(func(k: float):
		refresh_ends.call()
		var shard_node: Node2D = alive.call("shard")
		if shard_node == null:
			return
		var position_now: Vector2 = point_at.call(k)
		var position_ahead: Vector2 = point_at.call(minf(k + 0.05, 1.0))
		shard_node.position = position_now
		if position_ahead != position_now:
			shard_node.rotation = (position_ahead - position_now).angle() # always point first
		shard_node.visible = true
		var glitter_node: CPUParticles2D = alive.call("glitter")
		if glitter_node != null:
			glitter_node.position = position_now, 0.0, 1.0, flight).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	flight_tween.tween_callback(func():
		var shard_node: Node = alive.call("shard")
		if shard_node != null:
			shard_node.queue_free()
		var glitter_node: CPUParticles2D = alive.call("glitter")
		if glitter_node != null:
			glitter_node.emitting = false
			var glitter_cleanup := glitter_node.create_tween()
			glitter_cleanup.tween_interval(0.35)
			glitter_cleanup.tween_callback(glitter_node.queue_free))

	# --- 3. impact: the shard shatters into splinters and a puff of frost
	var impact_holder := Node2D.new()
	impact_holder.z_index = 27
	fx.add_child(impact_holder)
	parts["impact"] = impact_holder
	var impact_tween := fx.create_tween()
	impact_tween.tween_interval(impact_t)
	impact_tween.tween_callback(func():
		var holder: Node2D = alive.call("impact")
		if holder == null:
			return
		refresh_ends.call()
		var hit_point: Vector2 = ends["b"]
		var travel: Vector2 = (ends["b"] - ends["a"]).normalized()
		var flash := fx_library._glow_sprite(60.0, Color(ICE_LIGHT_COLOR, 0.95))
		flash.position = hit_point
		holder.add_child(flash)
		var flash_tween := flash.create_tween()
		flash_tween.tween_property(flash, "scale", Vector2.ONE * 1.5, 0.16)
		flash_tween.parallel().tween_property(flash, "modulate:a", 0.0, 0.2)
		# splinters: thrown on in the direction the shard was flying, then falling
		var splinters := _particle_burst(16, 0.45, ICE_LIGHT_COLOR, Color(ICE_BODY_COLOR, 0.0))
		splinters.direction = travel
		splinters.spread = 70.0
		splinters.gravity = Vector2(0, 500)
		splinters.initial_velocity_min = 140.0
		splinters.initial_velocity_max = 320.0
		splinters.angular_velocity_min = -540.0
		splinters.angular_velocity_max = 540.0
		splinters.scale_amount_min = 3.0
		splinters.scale_amount_max = 7.0
		splinters.position = hit_point
		holder.add_child(splinters)
		splinters.emitting = true
		# frost: a soft white-blue puff that spreads out and slows down
		var frost := _particle_burst(12, ICE_SHATTER_TIME, Color(ICE_FROST_COLOR, 0.65), Color(ICE_FROST_COLOR, 0.0))
		frost.explosiveness = 0.9
		frost.spread = 180.0
		frost.gravity = Vector2.ZERO
		frost.damping_min = 80.0
		frost.damping_max = 140.0
		frost.initial_velocity_min = 50.0
		frost.initial_velocity_max = 120.0
		frost.scale_amount_min = 10.0
		frost.scale_amount_max = 18.0
		frost.position = hit_point
		holder.add_child(frost)
		frost.emitting = true
		_knock_back(to, travel, 7.0, 0.16)
		var cleanup := holder.create_tween()
		cleanup.tween_interval(ICE_SHATTER_TIME + 0.2)
		cleanup.tween_callback(holder.queue_free))
	return charge + flight

# ---------------------------------------------------------------------------------------------
# "veneno": a glob of venom

const VENOM_CHARGE_FIRST := 0.16 ## the venom bubbling up on the caster before the first glob
const VENOM_CHARGE_NEXT := 0.0
const VENOM_FLIGHT := 0.32 ## time in the air: a glob is lobbed, slower than a shard
const VENOM_SPLASH_TIME := 0.6 ## how long the splash and the bubbles of the impact last
const VENOM_PURPLE := Color("#8a3fb8")
const VENOM_DARK := Color("#3a1550")
const VENOM_GREEN := Color("#94f252")

## Builds the venom glob: a dark purple drop with a sickly green shine on it.
func _make_venom_glob(radius: float) -> Node2D:
	var glob := Node2D.new()
	var outline_points := PackedVector2Array()
	for corner in 14:
		var angle := TAU * corner / 14.0
		outline_points.append(Vector2.from_angle(angle) * radius)
	var rim := Polygon2D.new() # a darker rim, drawn a little bigger behind the body
	var rim_points := PackedVector2Array()
	for point in outline_points:
		rim_points.append(point * 1.15)
	rim.polygon = rim_points
	rim.color = VENOM_DARK
	glob.add_child(rim)
	var body := Polygon2D.new()
	body.polygon = outline_points
	body.color = VENOM_PURPLE
	glob.add_child(body)
	var shine := fx_library._glow_sprite(radius * 0.55, Color(VENOM_GREEN, 0.85))
	shine.position = Vector2(-radius * 0.3, -radius * 0.35)
	glob.add_child(shine)
	return glob

## The "veneno" hit style, a glob of venom:
## 1. bubbling (first shot of a trigger only): green bubbles rise on the caster;
## 2. flight: a wobbling purple glob is lobbed on an arc, stretching in the direction it flies and
##    dripping venom that falls away behind it;
## 3. impact: it splats on the target: purple splashes fly up and fall back, green drops scatter and
##    a few bubbles rise and pop over the target.
## Follows both ends if they move. Returns the time from t until the glob lands.
func _venom_shot(from: Control, to: Control, t: float, first_shot: bool) -> float:
	var timing := _shot_timing("veneno", first_shot)
	var charge: float = timing["charge"]
	var flight: float = timing["flight"]
	var launch_t := t + charge
	var impact_t := launch_t + flight
	var rich := fx_library.fx_scale >= 0.7 # big chains skip the bubbles on the caster and the drips
	var path := _shot_path(from, to, 0.22, 80.0) # lobbed: a medium arc
	var ends: Dictionary = path["ends"]
	var refresh_ends: Callable = path["refresh"]
	var point_at: Callable = path["point_at"]
	# the lambdas below reach the shot's nodes through this dictionary instead of capturing them
	var parts := {}
	var alive := func(key: String) -> Node:
		var node = parts.get(key)
		return node if is_instance_valid(node) else null

	# --- 1. bubbling on the caster
	if first_shot and charge > 0.0 and rich:
		var bubbles := _particle_burst(10, 0.4, Color(VENOM_GREEN, 0.9), Color(VENOM_PURPLE, 0.0))
		bubbles.explosiveness = 0.3
		bubbles.direction = Vector2.UP
		bubbles.spread = 35.0
		bubbles.gravity = Vector2(0, -120)
		bubbles.initial_velocity_min = 20.0
		bubbles.initial_velocity_max = 60.0
		bubbles.scale_amount_min = 3.0
		bubbles.scale_amount_max = 7.0
		bubbles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		bubbles.emission_sphere_radius = 22.0
		bubbles.position = ends["a"]
		bubbles.z_index = 26
		fx.add_child(bubbles)
		var bubble_tween := bubbles.create_tween()
		bubble_tween.tween_interval(t)
		bubble_tween.tween_callback(func(): bubbles.emitting = true)
		bubble_tween.tween_interval(0.8)
		bubble_tween.tween_callback(bubbles.queue_free)

	# --- 2. flight: the wobbling glob, dripping venom
	var glob := _make_venom_glob(17.0)
	glob.z_index = 26
	glob.visible = false
	fx.add_child(glob)
	parts["glob"] = glob
	if rich:
		var drips := CPUParticles2D.new()
		drips.emitting = false
		drips.local_coords = false # the drops stay where they fell off, so they draw a trail
		drips.amount = 12
		drips.lifetime = 0.4
		drips.spread = 180.0
		drips.gravity = Vector2(0, 420) # the drops fall
		drips.initial_velocity_min = 0.0
		drips.initial_velocity_max = 20.0
		drips.scale_amount_min = 3.0
		drips.scale_amount_max = 6.0
		var drip_ramp := Gradient.new()
		drip_ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		drip_ramp.colors = PackedColorArray([VENOM_PURPLE, VENOM_GREEN, Color(VENOM_GREEN, 0.0)])
		drips.color_ramp = drip_ramp
		drips.z_index = 25
		fx.add_child(drips)
		parts["drips"] = drips
	var flight_tween := fx.create_tween()
	flight_tween.tween_interval(launch_t)
	flight_tween.tween_callback(func():
		var drip_node: CPUParticles2D = alive.call("drips")
		if drip_node != null:
			drip_node.position = ends["a"]
			drip_node.emitting = true)
	flight_tween.tween_method(func(k: float):
		refresh_ends.call()
		var glob_node: Node2D = alive.call("glob")
		if glob_node == null:
			return
		var position_now: Vector2 = point_at.call(k)
		var position_ahead: Vector2 = point_at.call(minf(k + 0.05, 1.0))
		glob_node.position = position_now
		if position_ahead != position_now:
			glob_node.rotation = (position_ahead - position_now).angle()
		# a liquid wobbles: it stretches along the way it flies and squashes back, over and over
		var wobble := sin(k * TAU * 3.0) * 0.18
		glob_node.scale = Vector2(1.2 + wobble, 0.85 - wobble)
		glob_node.visible = true
		var drip_node: CPUParticles2D = alive.call("drips")
		if drip_node != null:
			drip_node.position = position_now, 0.0, 1.0, flight)
	flight_tween.tween_callback(func():
		var glob_node: Node = alive.call("glob")
		if glob_node != null:
			glob_node.queue_free()
		var drip_node: CPUParticles2D = alive.call("drips")
		if drip_node != null:
			drip_node.emitting = false
			var drip_cleanup := drip_node.create_tween()
			drip_cleanup.tween_interval(0.45)
			drip_cleanup.tween_callback(drip_node.queue_free))

	# --- 3. impact: the splat
	var impact_holder := Node2D.new()
	impact_holder.z_index = 27
	fx.add_child(impact_holder)
	parts["impact"] = impact_holder
	var impact_tween := fx.create_tween()
	impact_tween.tween_interval(impact_t)
	impact_tween.tween_callback(func():
		var holder: Node2D = alive.call("impact")
		if holder == null:
			return
		refresh_ends.call()
		var hit_point: Vector2 = ends["b"]
		var travel: Vector2 = (ends["b"] - ends["a"]).normalized()
		# the splat itself: a dark purple stain that spreads out flat and fades
		var stain := _make_venom_glob(20.0)
		stain.position = hit_point
		stain.rotation = travel.angle()
		holder.add_child(stain)
		var stain_tween := stain.create_tween()
		stain_tween.tween_property(stain, "scale", Vector2(2.1, 1.6), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		stain_tween.tween_property(stain, "modulate:a", 0.0, 0.3)
		# purple splashes: thrown up and on, then falling back down
		var splash := _particle_burst(18, 0.5, VENOM_PURPLE, Color(VENOM_DARK, 0.0))
		splash.direction = (travel + Vector2.UP).normalized()
		splash.spread = 80.0
		splash.gravity = Vector2(0, 650)
		splash.initial_velocity_min = 110.0
		splash.initial_velocity_max = 260.0
		splash.scale_amount_min = 4.0
		splash.scale_amount_max = 8.0
		splash.position = hit_point
		holder.add_child(splash)
		splash.emitting = true
		# green drops: smaller and faster, glowing
		var drops := _particle_burst(12, 0.4, VENOM_GREEN, Color(VENOM_GREEN, 0.0))
		drops.spread = 180.0
		drops.gravity = Vector2(0, 500)
		drops.initial_velocity_min = 90.0
		drops.initial_velocity_max = 200.0
		drops.scale_amount_min = 2.5
		drops.scale_amount_max = 4.5
		drops.material = fx_library._additive()
		drops.position = hit_point
		holder.add_child(drops)
		drops.emitting = true
		# bubbles: rise slowly over the target after the splat, like the venom is already at work
		var rising_bubbles := _particle_burst(8, VENOM_SPLASH_TIME, Color(VENOM_GREEN, 0.9), Color(VENOM_PURPLE, 0.0))
		rising_bubbles.explosiveness = 0.5
		rising_bubbles.direction = Vector2.UP
		rising_bubbles.spread = 30.0
		rising_bubbles.gravity = Vector2(0, -90)
		rising_bubbles.initial_velocity_min = 15.0
		rising_bubbles.initial_velocity_max = 45.0
		rising_bubbles.scale_amount_min = 3.5
		rising_bubbles.scale_amount_max = 7.0
		rising_bubbles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		rising_bubbles.emission_sphere_radius = 26.0
		rising_bubbles.position = hit_point
		holder.add_child(rising_bubbles)
		rising_bubbles.emitting = true
		_knock_back(to, travel, 6.0, 0.2)
		var cleanup := holder.create_tween()
		cleanup.tween_interval(VENOM_SPLASH_TIME + 0.25)
		cleanup.tween_callback(holder.queue_free))
	return charge + flight

# ---------------------------------------------------------------------------------------------
# "vento": a wind blade

const WIND_CHARGE_FIRST := 0.14 ## the air swirling around the caster before the first blade
const WIND_CHARGE_NEXT := 0.0
const WIND_FLIGHT := 0.17 ## time in the air: the fastest shot of all
const WIND_GUST_TIME := 0.45 ## how long the cut and the swirl of the impact last
const WIND_COLOR := Color("#c9f0e2")
const WIND_LIGHT_COLOR := Color("#ffffff")

## Builds the wind blade, flying right (+x): a thin see-through crescent bulging forward, made of
## an outer arc and an inner arc pulled back.
func _make_wind_blade(radius: float) -> Node2D:
	var blade := Node2D.new()
	var crescent := PackedVector2Array()
	var steps := 12
	for step in steps + 1: # the outer arc, from the top tip to the bottom tip
		var angle := lerpf(-1.15, 1.15, float(step) / steps)
		crescent.append(Vector2.from_angle(angle) * radius)
	for step in range(steps, -1, -1): # the inner arc, back from the bottom tip to the top one
		var angle := lerpf(-1.15, 1.15, float(step) / steps)
		crescent.append(Vector2.from_angle(angle) * radius * 0.72 - Vector2(radius * 0.12, 0))
	var body := Polygon2D.new()
	body.polygon = crescent
	body.color = Color(WIND_COLOR, 0.75)
	body.material = fx_library._additive()
	blade.add_child(body)
	var cutting_edge := Line2D.new() # the bright front edge
	for step in steps + 1:
		var angle := lerpf(-1.05, 1.05, float(step) / steps)
		cutting_edge.add_point(Vector2.from_angle(angle) * radius)
	cutting_edge.width = 3.0
	cutting_edge.default_color = WIND_LIGHT_COLOR
	cutting_edge.begin_cap_mode = Line2D.LINE_CAP_ROUND
	cutting_edge.end_cap_mode = Line2D.LINE_CAP_ROUND
	blade.add_child(cutting_edge)
	# speed lines streaming off the back of the blade
	for line_index in 3:
		var height := (line_index - 1) * radius * 0.45
		var streak := Line2D.new()
		streak.points = PackedVector2Array([Vector2(-radius * 0.1, height), Vector2(-radius * 1.6, height)])
		streak.width = 2.0
		var streak_fade := Gradient.new()
		streak_fade.set_color(0, Color(WIND_COLOR, 0.8))
		streak_fade.set_color(1, Color(WIND_COLOR, 0.0))
		streak.gradient = streak_fade
		blade.add_child(streak)
	return blade

## The "vento" hit style, a wind blade:
## 1. swirl (first shot of a trigger only): wisps of air spin around the caster;
## 2. release: the caster card is pushed back by the gust (every shot);
## 3. flight: a pale see-through crescent shoots almost straight at the target, spinning a little,
##    with speed lines behind it;
## 4. impact: a bright cut flashes across the target, wisps of air whirl out around it and the
##    target is shoved hard the way the wind was blowing.
## Follows both ends if they move. Returns the time from t until the blade lands.
func _wind_shot(from: Control, to: Control, t: float, first_shot: bool) -> float:
	var timing := _shot_timing("vento", first_shot)
	var charge: float = timing["charge"]
	var flight: float = timing["flight"]
	var launch_t := t + charge
	var impact_t := launch_t + flight
	var rich := fx_library.fx_scale >= 0.7 # big chains skip the swirl on the caster
	var path := _shot_path(from, to, 0.1, 50.0) # almost straight, with a slight curve
	var ends: Dictionary = path["ends"]
	var refresh_ends: Callable = path["refresh"]
	var point_at: Callable = path["point_at"]
	# the lambdas below reach the shot's nodes through this dictionary instead of capturing them
	var parts := {}
	var alive := func(key: String) -> Node:
		var node = parts.get(key)
		return node if is_instance_valid(node) else null

	# --- 1. swirl of air around the caster
	if first_shot and charge > 0.0 and rich:
		var swirl := _particle_burst(14, 0.35, Color(WIND_COLOR, 0.7), Color(WIND_COLOR, 0.0))
		swirl.explosiveness = 0.4
		swirl.spread = 180.0
		swirl.gravity = Vector2.ZERO
		swirl.initial_velocity_min = 30.0
		swirl.initial_velocity_max = 60.0
		swirl.tangential_accel_min = 500.0 # pushes every wisp sideways: they spin around the card
		swirl.tangential_accel_max = 700.0
		swirl.scale_amount_min = 3.0
		swirl.scale_amount_max = 6.0
		swirl.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		swirl.emission_sphere_radius = 30.0
		swirl.material = fx_library._additive()
		swirl.position = ends["a"]
		swirl.z_index = 26
		fx.add_child(swirl)
		var swirl_tween := swirl.create_tween()
		swirl_tween.tween_interval(t)
		swirl_tween.tween_callback(func(): swirl.emitting = true)
		swirl_tween.tween_interval(0.7)
		swirl_tween.tween_callback(swirl.queue_free)

	# --- 2. release: the gust pushes the caster back
	if from is CardView:
		var caster_ref: WeakRef = weakref(from)
		var push := fx.create_tween()
		push.tween_interval(launch_t)
		push.tween_method(func(k: float):
			var caster = caster_ref.get_ref()
			if caster is CardView:
				var away: Vector2 = (ends["a"] - ends["b"]).normalized()
				caster.shake = away * 6.0 * (1.0 - k), 0.0, 1.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# --- 3. flight: the crescent blade
	var blade := _make_wind_blade(30.0)
	blade.z_index = 26
	blade.visible = false
	fx.add_child(blade)
	parts["blade"] = blade
	var flight_tween := fx.create_tween()
	flight_tween.tween_interval(launch_t)
	flight_tween.tween_method(func(k: float):
		refresh_ends.call()
		var blade_node: Node2D = alive.call("blade")
		if blade_node == null:
			return
		var position_now: Vector2 = point_at.call(k)
		var position_ahead: Vector2 = point_at.call(minf(k + 0.05, 1.0))
		blade_node.position = position_now
		if position_ahead != position_now:
			# faces where it flies, rocking a little from side to side like a thrown blade of air
			blade_node.rotation = (position_ahead - position_now).angle() + sin(k * TAU * 2.0) * 0.2
		blade_node.scale = Vector2.ONE * (0.8 + 0.35 * k) # it grows as it gathers speed
		blade_node.visible = true, 0.0, 1.0, flight)
	flight_tween.tween_callback(func():
		var blade_node: Node = alive.call("blade")
		if blade_node != null:
			blade_node.queue_free())

	# --- 4. impact: the cut, the whirl of air and the shove
	var impact_holder := Node2D.new()
	impact_holder.z_index = 27
	fx.add_child(impact_holder)
	parts["impact"] = impact_holder
	var impact_tween := fx.create_tween()
	impact_tween.tween_interval(impact_t)
	impact_tween.tween_callback(func():
		var holder: Node2D = alive.call("impact")
		if holder == null:
			return
		refresh_ends.call()
		var hit_point: Vector2 = ends["b"]
		var travel: Vector2 = (ends["b"] - ends["a"]).normalized()
		# the cut: a bright slash across the target, at a slant to the way the blade came in
		var cut_direction := travel.rotated(PI / 2.0 + 0.5)
		var cut := Line2D.new()
		cut.points = PackedVector2Array([hit_point - cut_direction * 55.0, hit_point + cut_direction * 55.0])
		cut.width = 7.0
		var cut_fade := Gradient.new() # thin at both ends, bright in the middle
		cut_fade.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		cut_fade.colors = PackedColorArray([Color(WIND_COLOR, 0.0), WIND_LIGHT_COLOR, Color(WIND_COLOR, 0.0)])
		cut.gradient = cut_fade
		cut.material = fx_library._additive()
		holder.add_child(cut)
		var cut_tween := cut.create_tween()
		cut_tween.tween_property(cut, "width", 1.0, 0.25)
		cut_tween.parallel().tween_property(cut, "modulate:a", 0.0, 0.25)
		# wisps of air whirling out around the target
		var whirl := _particle_burst(18, WIND_GUST_TIME, Color(WIND_LIGHT_COLOR, 0.85), Color(WIND_COLOR, 0.0))
		whirl.spread = 180.0
		whirl.gravity = Vector2.ZERO
		whirl.initial_velocity_min = 80.0
		whirl.initial_velocity_max = 170.0
		whirl.tangential_accel_min = 400.0 # sideways push: the wisps curl around instead of flying straight
		whirl.tangential_accel_max = 650.0
		whirl.damping_min = 60.0
		whirl.damping_max = 120.0
		whirl.scale_amount_min = 3.0
		whirl.scale_amount_max = 6.0
		whirl.material = fx_library._additive()
		whirl.position = hit_point
		holder.add_child(whirl)
		whirl.emitting = true
		_knock_back(to, travel, 16.0, 0.26) # wind shoves harder than it hurts
		var cleanup := holder.create_tween()
		cleanup.tween_interval(WIND_GUST_TIME + 0.2)
		cleanup.tween_callback(holder.queue_free))
	return charge + flight
