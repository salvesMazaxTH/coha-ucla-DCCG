class_name FxSummons
extends RefCounted
## Summons with an entrance of their own. A card names one with "summon_style", and then it plays when the card
## is summoned onto the table (the TableAnimator calls it). A style name that is not in STYLES plays nothing extra.

const STYLES := ["rai"]

## Rai, Imortal Imperfeito: he rises instead of falling. The slot cracks open with violet light, a pillar climbs
## out of it while Fragments rise from the ground and come together, and as he appears a flat shockwave rolls
## out, rays fan upward like a halo, and motes of light float up.
const RAI_RISE_TIME := 0.85 ## cracks, pillar and Fragments build up until he appears
const RAI_AFTER_APPEAR_TIME := 0.6 ## how long the table waits after he appears before the next event plays
const RAI_CRACK_COUNT := 7
const RAI_FRAGMENT_COUNT := 8
const RAI_RAY_COUNT := 7
const RAI_MOTE_COUNT := 18
const RAI_PILLAR_LIGHT_MIX := 0.35 ## how much of the pillar's color is the near-white light

## The Main node that owns the table.
var host
var fx_library: FxLibrary

## Read-only mirror of Main's effects layer.
var fx: Control:
	get: return host.fx

func _init(host_node, library: FxLibrary) -> void:
	host = host_node
	fx_library = library

func has_style(style_name: String) -> bool:
	return style_name in STYLES

## Seconds from the start of the style until the card should appear.
func arrival_delay(style_name: String) -> float:
	match style_name:
		"rai":
			return RAI_RISE_TIME
	return 0.0

## Plays the summon `style_name` over the slot at `slot_center` from moment t. Returns the moment the table can
## move on to the next event.
func play(style_name: String, slot_center: Vector2, t: float, col: Color) -> float:
	match style_name:
		"rai":
			return _rai(slot_center, t, col)
	return t

func _rai(center: Vector2, t: float, col: Color) -> float:
	var appear_t := t + RAI_RISE_TIME
	var amount_scale := clampf(fx_library.fx_scale, 0.4, 1.0)
	for i in RAI_CRACK_COUNT:
		_rai_crack(center, col, t + randf() * 0.15, appear_t, TAU * i / RAI_CRACK_COUNT + randf_range(-0.2, 0.2))
	_rai_pillar(center, col, t, appear_t)
	for i in int(RAI_FRAGMENT_COUNT * amount_scale):
		_rai_fragment_up(center, col, t + 0.05 + i * 0.06, appear_t)
	_rai_appearance(center, col, appear_t, amount_scale)
	Sfx.play_in("incarnation", appear_t)
	return appear_t + RAI_AFTER_APPEAR_TIME

## A jagged line of light splits the table from the slot outward, then fades once he has appeared.
func _rai_crack(center: Vector2, col: Color, start_t: float, appear_t: float, angle: float) -> void:
	var points := PackedVector2Array([center])
	var reach := randf_range(95.0, 150.0)
	var segments := 5
	for step in range(1, segments + 1):
		points.append(center + Vector2.from_angle(angle + randf_range(-0.25, 0.25)) * reach * step / segments)
	var crack := Line2D.new()
	crack.width = 3.0
	crack.z_index = 55
	crack.material = fx_library._additive()
	crack.default_color = col.lightened(0.25)
	crack.modulate.a = 0.0
	fx.add_child(crack)
	var reveal_points := func(progress: float):
		crack.points = points.slice(0, 2 + int(progress * (points.size() - 2)))
	var motion := crack.create_tween()
	motion.tween_interval(start_t)
	motion.tween_property(crack, "modulate:a", 1.0, 0.1)
	motion.parallel().tween_method(reveal_points, 0.0, 1.0, 0.45)
	motion.tween_interval(maxf(0.0, appear_t - start_t - 0.55))
	motion.tween_property(crack, "modulate:a", 0.0, 0.5)
	motion.tween_callback(crack.queue_free)

## A column of violet light grows up out of the slot, brightens until he appears, then thins away.
func _rai_pillar(center: Vector2, col: Color, start_t: float, appear_t: float) -> void:
	var pillar := fx_library._glow_sprite(32.0, col.lerp(host.fx_executions.RAI_LIGHT, RAI_PILLAR_LIGHT_MIX))
	pillar.position = center
	pillar.z_index = 56
	pillar.scale = Vector2(0.9, 0.1)
	pillar.modulate.a = 0.0
	fx.add_child(pillar)
	var motion := pillar.create_tween()
	motion.tween_interval(start_t + 0.1)
	motion.tween_property(pillar, "modulate:a", 0.9, RAI_RISE_TIME - 0.1)
	motion.parallel().tween_property(pillar, "scale:y", 6.0, appear_t - start_t - 0.1).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	motion.tween_property(pillar, "scale:x", 0.0, 0.5)
	motion.parallel().tween_property(pillar, "modulate:a", 0.0, 0.5)
	motion.tween_callback(pillar.queue_free)

## One Fragment rises from the ground below the slot, drifting toward the middle, and is absorbed as he appears.
func _rai_fragment_up(center: Vector2, col: Color, start_t: float, appear_t: float) -> void:
	var fragment: Node2D = host.fx_executions.fragment_shape(col, 6.0)
	var start := center + Vector2(randf_range(-75.0, 75.0), randf_range(90.0, 130.0))
	var sway := randf_range(8.0, 16.0) * (1.0 if randf() < 0.5 else -1.0)
	fragment.position = start
	fragment.modulate.a = 0.0
	fx.add_child(fragment)
	var rise := func(progress: float):
		var eased := progress * progress
		fragment.position = start.lerp(center, eased) + Vector2(sin(progress * TAU) * sway * (1.0 - progress), 0.0)
		fragment.scale = Vector2.ONE * (1.0 - 0.6 * eased)
	var motion := fragment.create_tween()
	motion.tween_interval(start_t)
	motion.tween_property(fragment, "modulate:a", 1.0, 0.1)
	motion.parallel().tween_method(rise, 0.0, 1.0, maxf(0.2, appear_t - start_t))
	motion.tween_callback(fragment.queue_free)

## The moment he appears: a flash, two flat shockwaves along the table, rays fanning upward like a halo, and
## light motes floating up.
func _rai_appearance(center: Vector2, col: Color, appear_t: float, amount_scale: float) -> void:
	var light: Color = host.fx_executions.RAI_LIGHT
	var burst := Node2D.new()
	burst.position = center
	burst.z_index = 59
	burst.modulate.a = 0.0
	fx.add_child(burst)

	var flash := fx_library._glow_sprite(32.0, light)
	flash.scale = Vector2.ONE * 2.0
	burst.add_child(flash)
	var wave_near := fx_library._ring_line(60.0, 4.0, light)
	var wave_far := fx_library._ring_line(60.0, 3.0, col.lightened(0.2))
	wave_near.scale = Vector2(0.3, 0.1)
	wave_far.scale = Vector2(0.3, 0.1)
	burst.add_child(wave_near)
	burst.add_child(wave_far)

	var rays: Array[Polygon2D] = []
	for i in RAI_RAY_COUNT:
		var ray := Polygon2D.new()
		var length := randf_range(150.0, 230.0)
		ray.polygon = PackedVector2Array([Vector2(0, -4.0), Vector2(length, 0), Vector2(0, 4.0)])
		ray.color = light if i % 2 == 0 else col.lightened(0.35)
		ray.material = fx_library._additive()
		ray.rotation = deg_to_rad(lerpf(-155.0, -25.0, i / float(RAI_RAY_COUNT - 1)))
		ray.scale = Vector2(0.2, 1.0)
		burst.add_child(ray)
		rays.append(ray)

	var reveal := burst.create_tween()
	reveal.tween_interval(appear_t)
	reveal.tween_callback(func(): burst.modulate.a = 1.0)
	reveal.tween_interval(0.8)
	reveal.tween_callback(burst.queue_free)
	var spread := burst.create_tween()
	spread.tween_interval(appear_t)
	spread.tween_property(flash, "scale", Vector2.ONE * 5.0, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	spread.parallel().tween_property(flash, "modulate:a", 0.0, 0.5).from(1.0)
	spread.parallel().tween_property(wave_near, "scale", Vector2(3.2, 1.0), 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	spread.parallel().tween_property(wave_near, "modulate:a", 0.0, 0.55).from(1.0)
	spread.parallel().tween_property(wave_far, "scale", Vector2(4.4, 1.4), 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC).set_delay(0.1)
	spread.parallel().tween_property(wave_far, "modulate:a", 0.0, 0.7).from(0.9).set_delay(0.1)
	for ray in rays:
		spread.parallel().tween_property(ray, "scale:x", 1.0, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		spread.parallel().tween_property(ray, "modulate:a", 0.0, 0.6).from(1.0).set_ease(Tween.EASE_IN)

	var mote_color: Color = light.lerp(col, 0.2)
	for i in int(RAI_MOTE_COUNT * amount_scale):
		_rai_mote(center, mote_color, appear_t)

## One mote of light floats straight up from around the slot, swaying a little, and fades.
func _rai_mote(center: Vector2, mote_color: Color, appear_t: float) -> void:
	var mote: Node2D = host.fx_executions.dust_mote(mote_color)
	mote.material = fx_library._additive()
	var start := center + Vector2(randf_range(-55.0, 55.0), randf_range(-30.0, 60.0))
	var life := randf_range(1.0, 1.5)
	var rise := randf_range(110.0, 200.0)
	var sway := randf_range(5.0, 12.0)
	var sway_phase := randf() * TAU
	mote.position = start
	mote.z_index = 60
	mote.modulate.a = 0.0
	fx.add_child(mote)
	var float_up := func(progress: float):
		var eased := 1.0 - (1.0 - progress) * (1.0 - progress)
		mote.position = start + Vector2(sin(sway_phase + progress * TAU) * sway, -rise * eased)
	var motion := mote.create_tween()
	motion.tween_interval(appear_t + randf() * 0.2)
	motion.tween_property(mote, "modulate:a", 1.0, 0.08)
	motion.parallel().tween_method(float_up, 0.0, 1.0, life)
	motion.parallel().tween_property(mote, "modulate:a", 0.0, life * 0.5).set_delay(life * 0.5)
	motion.tween_callback(mote.queue_free)
