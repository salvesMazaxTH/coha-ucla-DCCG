class_name FxCasts
extends RefCounted
## Cast animations: how a spell (or a unit's trigger that hits the whole table) looks as it goes off,
## BEFORE the hits and deaths it causes are shown. There are two shapes:
## - projectile: an effect with one target flies from whoever cast it (the center of the caster's Leader
##   for a spell) to the target. That part reuses the shots of FxShots, tinted by the card's color;
## - area: an effect that hits several units at once plays ONE animation over the whole arena
##   (a wall of fire sweeping across, a water sphere bursting into a flood...), instead of one shot per target.
##
## Which area animation plays comes from the card: its own "cast_fx" field if it has one, otherwise
## its element (fogo, agua...), otherwise its domain. Elements without an animation of their own yet use
## a shockwave in the card's color (see area_cast).
## Most of it is built from the same cheap pieces as the shots (soft glow dots, lines, one tinted
## rectangle, tweens). Fire and water are one rectangle with a shader each (shaders/fire_wall.gdshader,
## shaders/water_surge.gdshader), because glow dots only ever read as energy, never as flames or liquid. On phones (effect_detail below 0.7) the extra glows are skipped.

## The Main node that owns the table.
var host
## The effect toolbox (glow primitives, embers, screen shake and the effects budget).
var fx_library: FxLibrary

## Read-only mirror of Main's effects layer.
var fx: Control:
	get: return host.fx

func _init(host_node, library: FxLibrary) -> void:
	host = host_node
	fx_library = library

## Effect actions that make an area cast worth showing: things that hurt or remove units.
## A heal or a buff spread over the allies keeps its gentle orbs (FxShots._boon_shot).
const HARMFUL_ACTIONS := ["damage", "destroy", "add_dot", "freeze", "stun", "exhaust", "condemn", "banish", "bounce", "damage_split"]

## Which area animation each element plays. An element missing from this list falls back to its
## domain (DOMAIN_STYLES), then to the generic shockwave. To give an element its own animation, write
## a function like _fire_area and add its line here and in area_cast.
const ELEMENT_STYLES := {"fogo": "fogo", "sangue": "fogo", "agua": "agua"}
const DOMAIN_STYLES := {"furia": "fogo", "fluxo": "agua"}

## Colors of the sparks and glow around the fire and water shaders.
const FIRE_EDGE := Color("#ff5a1e")
const WATER_CORE := Color("#d8f6ff")

## The area animation a card plays: its "cast_fx", or the style of its element, or of its domain.
## An empty string means the generic shockwave in the card's color.
func style_of(card_id: String) -> String:
	var card := CardDB.card(card_id)
	if card.has("cast_fx"):
		return String(card["cast_fx"])
	var element := String(card.get("element", ""))
	if ELEMENT_STYLES.has(element):
		return ELEMENT_STYLES[element]
	for domain in CardDB.essences_of(card):
		if DOMAIN_STYLES.has(domain):
			return DOMAIN_STYLES[domain]
	return ""

## True when the card's effects for this trigger hit a whole group of units at once ("all_units",
## "all_enemy_units"...) with something harmful: that is what gets the area animation.
## For a spell, pass "on_play".
func is_area(card_id: String, trigger: String) -> bool:
	for effect in CardDB.card(card_id).get("effects", []):
		if String(effect.get("trigger", "")) != trigger:
			continue
		if not String(effect.get("action", "")) in HARMFUL_ACTIONS:
			continue
		if String(effect.get("target", "")).begins_with("all_"):
			return true
	return false

## The arena: both rows of units together (the area animations cover this rectangle).
func _arena() -> Rect2:
	return TableView.ENEMY_LANE.merge(TableView.MY_LANE)

## Plays the area animation of a card at moment t, starting from `origin` (the center of the caster:
## its Leader for a spell, the unit itself for a trigger).
## Returns the time from t until the first hit should land (the hits are shown one after the other from there).
func area_cast(card_id: String, origin: Vector2, t: float) -> float:
	match style_of(card_id):
		"fogo":
			return _fire_area(origin, t)
		"agua":
			return _water_area(origin, t)
	return _shockwave_area(origin, t, host._elem_color(card_id))

## A tinted rectangle over the whole arena that fades in and out (the light of the blast on the table).
func _arena_tint(col: Color, peak_alpha: float, t: float, rise: float, hold: float, fall: float) -> void:
	var tint := ColorRect.new()
	var arena := _arena().grow(30.0)
	tint.position = arena.position
	tint.size = arena.size
	tint.color = Color(col, 1.0)
	tint.modulate.a = 0.0
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tint.material = fx_library._additive()
	fx.add_child(tint)
	var tween := tint.create_tween()
	tween.tween_interval(t)
	tween.tween_property(tint, "modulate:a", peak_alpha, rise)
	tween.tween_interval(hold)
	tween.tween_property(tint, "modulate:a", 0.0, fall)
	tween.tween_callback(tint.queue_free)

## A short screen shake at moment t (the same trauma shake as the heavy hits, but lighter).
func _shake(t: float, strength: float, duration: float) -> void:
	var rest_position: Vector2 = host.position
	var shake_driver: Tween = host.create_tween()
	shake_driver.tween_interval(t)
	shake_driver.tween_method(fx_library._apply_screen_trauma.bind(rest_position, strength), 0.0, 1.0, duration)
	shake_driver.tween_callback(func(): host.position = rest_position)

## A glowing ball that swells on the caster: the wind-up before every area cast.
## Returns the ball, so an animation can keep moving it.
func _charge_ball(center: Vector2, radius: float, col: Color, t: float, duration: float) -> Sprite2D:
	var ball := fx_library._glow_sprite(radius, col)
	ball.position = center
	var full_scale := ball.scale
	# remembered so an animation can grow the ball relative to its full size later
	ball.set_meta("full_scale", full_scale.x)
	ball.scale = Vector2.ZERO
	fx.add_child(ball)
	var tween := ball.create_tween()
	tween.tween_interval(t)
	tween.tween_property(ball, "scale", full_scale, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return ball

## Fogo (Pira-Mundo, D'Lorafya): a wall of real flames (shaders/fire_wall.gdshader) sweeps over the
## arena from the caster's side to the far side, leaving smoke and embers behind it, while the whole
## table glows orange. One rectangle and one shader, cheap on phones.
const FIRE_SWEEP_TIME := 0.75
const FIRE_FADE_TIME := 0.35
static var _fire_shader: Shader
func _fire_area(origin: Vector2, t: float) -> float:
	if _fire_shader == null:
		_fire_shader = load("res://scripts/ui/shaders/fire_wall.gdshader")
	var rich := fx_library.fx_scale >= 0.7
	var arena := _arena().grow(30.0)
	var fire := ColorRect.new()
	fire.position = arena.position
	fire.size = arena.size
	fire.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fire_material := ShaderMaterial.new()
	fire_material.shader = _fire_shader
	fire_material.set_shader_parameter("aspect", arena.size.x / arena.size.y)
	# the wall starts at the caster's edge of the arena (a caster below the middle = from the bottom)
	var caster_below := origin.y > arena.get_center().y
	fire_material.set_shader_parameter("from_bottom", 1.0 if caster_below else 0.0)
	fire.material = fire_material
	fx.add_child(fire)
	var tween := fire.create_tween()
	tween.tween_interval(t)
	tween.tween_method(func(value: float): fire_material.set_shader_parameter("progress", value), 0.0, 1.0, FIRE_SWEEP_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(func(value: float): fire_material.set_shader_parameter("fade", value), 1.0, 0.0, FIRE_FADE_TIME)
	tween.tween_callback(fire.queue_free)
	# sparks thrown up as the wall passes over each row of units
	var ember_points := 3 if rich else 2
	var near_row := TableView.MY_LANE if caster_below else TableView.ENEMY_LANE
	var far_row := TableView.ENEMY_LANE if caster_below else TableView.MY_LANE
	for row_and_moment in [[near_row, 0.4], [far_row, 0.7]]:
		var row: Rect2 = row_and_moment[0]
		for i in ember_points:
			var x := lerpf(row.position.x + 80.0, row.end.x - 80.0, (i + 0.5) / ember_points)
			fx_library._embers(Vector2(x, row.get_center().y), t + FIRE_SWEEP_TIME * row_and_moment[1], FIRE_EDGE, 18)
	# the heat lighting up the table
	_arena_tint(FIRE_EDGE, 0.18 if rich else 0.12, t, 0.2, FIRE_SWEEP_TIME * 0.6, 0.4)
	_shake(t + FIRE_SWEEP_TIME * 0.3, 5.0, 0.5)
	# the first hits land when the wall reaches the middle of the table
	return FIRE_SWEEP_TIME * 0.5

## Agua (Julgamento da Era Afogada, Tsunami): a real wave (shaders/water_surge.gdshader) rolls over
## the arena from the caster's side, foam on its crest, covers the table for a moment with light
## dancing on the bottom, and drains away in patches. One rectangle and one shader, cheap on phones.
const WATER_ROLL_TIME := 0.6
const WATER_HOLD_TIME := 0.45
const WATER_DRAIN_TIME := 0.55
static var _water_shader: Shader
func _water_area(origin: Vector2, t: float) -> float:
	if _water_shader == null:
		_water_shader = load("res://scripts/ui/shaders/water_surge.gdshader")
	var arena := _arena().grow(30.0)
	var water := ColorRect.new()
	water.position = arena.position
	water.size = arena.size
	water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var water_material := ShaderMaterial.new()
	water_material.shader = _water_shader
	water_material.set_shader_parameter("aspect", arena.size.x / arena.size.y)
	# the wave starts at the caster's edge of the arena (a caster below the middle = from the bottom)
	var caster_below := origin.y > arena.get_center().y
	water_material.set_shader_parameter("from_bottom", 1.0 if caster_below else 0.0)
	water.material = water_material
	fx.add_child(water)
	var tween := water.create_tween()
	tween.tween_interval(t)
	tween.tween_method(func(value: float): water_material.set_shader_parameter("progress", value), 0.0, 1.0, WATER_ROLL_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(WATER_HOLD_TIME)
	tween.tween_method(func(value: float): water_material.set_shader_parameter("drain", value), 0.0, 1.0, WATER_DRAIN_TIME)
	tween.tween_callback(water.queue_free)
	# spray thrown up where the crest crashes into each row of units
	var near_row := TableView.MY_LANE if caster_below else TableView.ENEMY_LANE
	var far_row := TableView.ENEMY_LANE if caster_below else TableView.MY_LANE
	for row_and_moment in [[near_row, 0.3], [far_row, 0.6]]:
		var row: Rect2 = row_and_moment[0]
		for i in 3:
			var x := lerpf(row.position.x + 80.0, row.end.x - 80.0, (i + 0.5) / 3.0)
			fx_library._embers(Vector2(x, row.get_center().y), t + WATER_ROLL_TIME * row_and_moment[1], WATER_CORE, 14)
	_shake(t + WATER_ROLL_TIME * 0.3, 6.0, 0.5)
	# the first hits land when the wave reaches the middle of the table
	return WATER_ROLL_TIME * 0.5

## ---- Destroy casts: a spell that destroys ONE unit (Reduzir a Cinzas, Afogar) ----
## Instead of the red X, the unit is taken by its element (burned, drowned) and dissolves inside it.
## Only the card's own "cast_fx" or element counts here, never its domain: a Fúria kick with no
## element (Chute no Portão) keeps the X instead of bursting into flames.

## The destroy animation of a spell: "fogo", "agua", or "" when it keeps the X.
func destroy_style_of(card_id: String) -> String:
	var card := CardDB.card(card_id)
	var style := String(card["cast_fx"]) if card.has("cast_fx") else String(ELEMENT_STYLES.get(String(card.get("element", "")), ""))
	return style if style in ["fogo", "agua"] else ""

## Plays the destroy animation of `style` over the unit `unit_view` at moment t.
## Returns the time from t until the unit should start dissolving (inside the fire / under the water).
func destroy_cast(style: String, unit_view: Control, t: float) -> float:
	var center: Vector2 = fx_library._center_of(unit_view)
	var card_size: Vector2 = unit_view.size * unit_view.scale
	match style:
		"fogo":
			return _burn_unit(center, card_size, t)
		"agua":
			return _drown_unit(center, card_size, t)
	return 0.0

## A small rectangle with a shader, placed over a card (used by the destroy casts).
## Returns the rectangle; its ShaderMaterial is in its `material`.
func _unit_overlay(shader: Shader, rect: Rect2) -> ColorRect:
	var overlay := ColorRect.new()
	overlay.position = rect.position
	overlay.size = rect.size
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var overlay_material := ShaderMaterial.new()
	overlay_material.shader = shader
	overlay_material.set_shader_parameter("aspect", rect.size.x / rect.size.y)
	overlay.material = overlay_material
	fx.add_child(overlay)
	return overlay

## Fogo (Reduzir a Cinzas): flames (shaders/unit_burn.gdshader) climb the card from its base, the unit
## dissolves inside them, then they die out. The rectangle is wider and taller than the card so the
## tongues of fire lick past its edges.
const BURN_CLIMB_TIME := 0.45
const BURN_HOLD_TIME := 0.45
const BURN_FADE_TIME := 0.4
static var _burn_shader: Shader
func _burn_unit(center: Vector2, card_size: Vector2, t: float) -> float:
	if _burn_shader == null:
		_burn_shader = load("res://scripts/ui/shaders/unit_burn.gdshader")
	var flame_size := Vector2(card_size.x * 1.35, card_size.y * 1.45)
	# the base of the flames sits a little below the card's bottom edge; the extra height goes up
	var flame_rect := Rect2(Vector2(center.x - flame_size.x * 0.5, center.y + card_size.y * 0.55 - flame_size.y), flame_size)
	var overlay := _unit_overlay(_burn_shader, flame_rect)
	var burn_material: ShaderMaterial = overlay.material
	var tween := overlay.create_tween()
	tween.tween_interval(t)
	tween.tween_method(func(value: float): burn_material.set_shader_parameter("progress", value), 0.0, 1.0, BURN_CLIMB_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(BURN_HOLD_TIME)
	tween.tween_method(func(value: float): burn_material.set_shader_parameter("fade", value), 1.0, 0.0, BURN_FADE_TIME)
	tween.tween_callback(overlay.queue_free)
	fx_library._embers(Vector2(center.x, center.y + card_size.y * 0.4), t + 0.1, FIRE_EDGE, 16)
	fx_library._embers(center, t + BURN_CLIMB_TIME, FIRE_EDGE, 20)
	_shake(t + 0.1, 3.0, 0.35)
	# the unit starts dissolving once the flames have climbed most of the way
	return BURN_CLIMB_TIME * 0.8

## Agua (Afogar): water (shaders/unit_drown.gdshader) rises over the card like a tank filling up,
## bubbles escaping, the unit dissolves under it, then the water drains away in patches.
const DROWN_RISE_TIME := 0.5
const DROWN_HOLD_TIME := 0.5
const DROWN_DRAIN_TIME := 0.45
static var _drown_shader: Shader
func _drown_unit(center: Vector2, card_size: Vector2, t: float) -> float:
	if _drown_shader == null:
		_drown_shader = load("res://scripts/ui/shaders/unit_drown.gdshader")
	var water_size := card_size * Vector2(1.2, 1.12)
	var water_rect := Rect2(center - water_size * 0.5, water_size)
	var overlay := _unit_overlay(_drown_shader, water_rect)
	var drown_material: ShaderMaterial = overlay.material
	var tween := overlay.create_tween()
	tween.tween_interval(t)
	tween.tween_method(func(value: float): drown_material.set_shader_parameter("level", value), 0.0, 1.0, DROWN_RISE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_interval(DROWN_HOLD_TIME)
	tween.tween_method(func(value: float): drown_material.set_shader_parameter("drain", value), 0.0, 1.0, DROWN_DRAIN_TIME)
	tween.tween_callback(overlay.queue_free)
	fx_library._embers(Vector2(center.x, center.y + card_size.y * 0.45), t + 0.05, WATER_CORE, 12)
	fx_library._embers(Vector2(center.x, center.y - card_size.y * 0.5), t + DROWN_RISE_TIME, WATER_CORE, 14)
	# the unit starts dissolving once it is fully under water
	return DROWN_RISE_TIME

## Generic area cast (elements without their own animation yet): a ball in the card's color swells
## on the caster and a shockwave runs over the whole arena.
func _shockwave_area(origin: Vector2, t: float, col: Color) -> float:
	var charge_time := 0.25
	var ball := _charge_ball(origin, 60.0, col.lightened(0.2), t, charge_time)
	var ball_tween := ball.create_tween()
	ball_tween.tween_interval(t + charge_time)
	ball_tween.tween_property(ball, "modulate:a", 0.0, 0.2)
	ball_tween.tween_callback(ball.queue_free)
	var wave := fx_library._ring_line(40.0, 14.0, Color(col.lightened(0.35), 0.9))
	wave.position = origin
	wave.modulate.a = 0.0
	fx.add_child(wave)
	var wave_tween := wave.create_tween()
	wave_tween.tween_interval(t + charge_time)
	wave_tween.tween_property(wave, "modulate:a", 1.0, 0.03)
	wave_tween.tween_property(wave, "scale", Vector2.ONE * 22.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	wave_tween.parallel().tween_property(wave, "modulate:a", 0.0, 0.6)
	wave_tween.tween_callback(wave.queue_free)
	_arena_tint(col, 0.18, t + charge_time, 0.08, 0.15, 0.3)
	_shake(t + charge_time, 4.0, 0.4)
	return charge_time + 0.2
