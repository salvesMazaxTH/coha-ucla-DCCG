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
## its element (fogo, agua...). NEVER its domain: a Fluxo card with no element (Coagulhão) is not water.
## A card with no area animation that fits it (no cast_fx, no element, or an element with no area animation
## yet like metal, vento or sombra) is NOT an area cast: its hits fly as the default bolts, one per target,
## even when it hits the whole table (see is_area).
## The exception: a card that expressly names its own "hit_fx" (the rubies of Cuspa-Rubi, the slashes of
## Rália...) is NOT an area cast, so it keeps firing those shots, one per target (see is_area).
## Most of it is built from the same cheap pieces as the shots (soft glow dots, lines, one tinted
## rectangle, tweens). Each element animation is ONE rectangle with a shader (shaders/fire_wall,
## water_surge, ice_frost, holy_light, lightning_storm, toxic_cloud, blood_tide, stone_rockfall, vine_overgrowth for the areas; unit_burn,
## unit_drown, unit_crush, unit_overgrow, unit_corrode, unit_bleed for the single destroys), because glow dots only ever read
## as energy, never as flames, liquid, ice or rock. On phones (effect_detail below 0.7) the extra glows are skipped.

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

## Which area animation each element plays. An element missing from this list has none, so its area
## effects fly the default bolts. To give an element its own animation, write
## a function like _fire_area and add its line here and in area_cast.
## Some styles only have an area animation (gelo, luz); fogo, agua, veneno, sangue, raio, pedra and vegetal have both. A missing one falls back to the shockwave (area) or the red X (destroy).
## "fagulha" is no element: it is the light fire area that a small fire spell asks for with its own
## "cast_fx" (Fagulhame), instead of the wall of flames of the element fogo.
const ELEMENT_STYLES := {
	"fogo": "fogo", "sangue": "sangue", "agua": "agua",
	"gelo": "gelo", "luz": "luz", "raio": "raio",
	"pedra": "pedra", "vegetal": "vegetal", "veneno": "veneno",
}
## Only for the SHOTS of a single-target spell (FxShots.spell_hit_style): a Tormenta spell with no element
## still fires lightning. It never picks an area animation.
const DOMAIN_STYLES := {"furia": "fogo", "fluxo": "agua", "tormenta": "raio"}

## The styles that really have an area animation (see area_cast). Any other style (metal, vento, sombra...)
## plays the default bolts instead.
const AREA_STYLES := ["fogo", "fagulha", "agua", "gelo", "luz", "raio", "veneno", "sangue", "pedra", "vegetal"]

## The styles that have their own single-unit destroy animation (see destroy_cast).
const DESTROY_STYLES := ["fogo", "agua", "pedra", "vegetal", "veneno", "sangue", "raio", "gelo", "luz"]

## Colors of the sparks and glow around each shader (and of the unit dissolving inside it).
const FIRE_EDGE := Color("#ff5a1e")
const WATER_CORE := Color("#d8f6ff")
const ICE_GLOW := Color("#bfeaff")
const HOLY_GOLD := Color("#ffd67a")
const BOLT_BLUE := Color("#a8b0ff")
const STONE_DUST := Color("#a8947a")
const LEAF_GREEN := Color("#58b34a")
const VENOM_PURPLE := Color("#a35ad1")
const BLOOD_RED := Color("#b8212f")
const BLOOD_DARK := Color("#4a040c")

## The color the unit dissolves in after a destroy animation of `style`.
static func dissolve_color_of(style: String) -> Color:
	match style:
		"fogo": return FIRE_EDGE
		"agua": return WATER_CORE
		"pedra": return STONE_DUST
		"vegetal": return LEAF_GREEN
		"veneno": return VENOM_PURPLE
		"sangue": return BLOOD_RED
		"raio": return BOLT_BLUE
		"gelo": return ICE_GLOW
		"luz": return HOLY_GOLD
	return Color.WHITE

## The style a card plays: its "cast_fx", or the style of its element (never its domain).
## An empty string means it has none.
func style_of(card_id: String) -> String:
	var card := CardDB.card(card_id)
	if card.has("cast_fx"):
		return String(card["cast_fx"])
	for element in CardDB.elements_of(card):
		if ELEMENT_STYLES.has(element):
			return ELEMENT_STYLES[element]
	return ""

## The style of the card's domain (furia = fogo...). Only for choosing a shot, never an area animation.
func domain_style_of(card_id: String) -> String:
	for domain in CardDB.essences_of(CardDB.card(card_id)):
		if DOMAIN_STYLES.has(domain):
			return DOMAIN_STYLES[domain]
	return ""

## True when the card's effects for this trigger hit a whole group of units at once ("all_units",
## "all_enemy_units"...) with something harmful: that is what gets the area animation.
## For a spell, pass "on_play".
## A card with no area animation that fits it (see AREA_STYLES) is never an area cast: it keeps the default
## bolts, one per target. A card that expressly declares its own "hit_fx" is never an area cast either: the
## default animation (from its element) must not replace the shots the card chose for itself, not even for its "Ao Entrar".
## (A card that also declares a "cast_fx" asked for that area animation too, so it still gets it.)
func is_area(card_id: String, trigger: String) -> bool:
	var card := CardDB.card(card_id)
	if card.has("hit_fx") and not card.has("cast_fx"):
		return false
	if not style_of(card_id) in AREA_STYLES:
		return false
	for effect in card.get("effects", []):
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
		"fagulha":
			return _spark_area(origin, t)
		"agua":
			return _water_area(origin, t)
		"gelo":
			return _ice_area(origin, t)
		"luz":
			return _light_area(t)
		"raio":
			return _lightning_area(t)
		"veneno":
			return _poison_area(origin, t)
		"sangue":
			return _blood_area(origin, t)
		"pedra":
			return _stone_area(origin, t)
		"vegetal":
			return _vine_area(origin, t)
	# is_area only lets the styles above through, so this shockwave is just a safety net
	return _shockwave_area(origin, t, host.table_animator.elem_color(card_id))

## A rectangle over the whole arena with `shader`, the "aspect" already set (used by the area casts).
## Returns the rectangle; its ShaderMaterial is in its `material`.
func _arena_overlay(shader: Shader) -> ColorRect:
	var arena := _arena().grow(30.0)
	var overlay := ColorRect.new()
	overlay.position = arena.position
	overlay.size = arena.size
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var overlay_material := ShaderMaterial.new()
	overlay_material.shader = shader
	overlay_material.set_shader_parameter("aspect", arena.size.x / arena.size.y)
	overlay.material = overlay_material
	fx.add_child(overlay)
	return overlay

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
			fx_library.spawn_embers(Vector2(x, row.get_center().y), t + FIRE_SWEEP_TIME * row_and_moment[1], FIRE_EDGE, 18)
	# the heat lighting up the table
	_arena_tint(FIRE_EDGE, 0.18 if rich else 0.12, t, 0.2, FIRE_SWEEP_TIME * 0.6, 0.4)
	_shake(t + FIRE_SWEEP_TIME * 0.3, 5.0, 0.5)
	# the first hits land when the wall reaches the middle of the table
	return FIRE_SWEEP_TIME * 0.5

## Fagulha (Fagulhame): the LIGHT fire area, for small spells that only singe the table (the wall of
## flames of _fire_area is for the big ones, like Pira-Mundo and D'Lorafya). A card picks it with
## "cast_fx": "fagulha".
## 1. a small spark swells on the caster;
## 2. a handful of sparks shoot out of it, each one to its own spot on the rows of units (the near row
##    first, then the far one);
## 3. where each spark lands it crackles: a quick flash and a little spray of embers that fall.
## The table only gets a faint warm glow and does not shake. No shader: a few glow dots and particles.
const SPARK_CHARGE_TIME := 0.18 ## the spark swelling on the caster
const SPARK_FLIGHT_TIME := 0.2 ## each spark's flight to its spot
const SPARK_ROW_DELAY := 0.12 ## the far row crackles this much after the near one
const SPARK_HOT := Color("#ffd27a")
func _spark_area(origin: Vector2, t: float) -> float:
	var rich := fx_library.fx_scale >= 0.7
	var arena := _arena()
	var caster_below := origin.y > arena.get_center().y
	var near_row := TableView.MY_LANE if caster_below else TableView.ENEMY_LANE
	var far_row := TableView.ENEMY_LANE if caster_below else TableView.MY_LANE
	# 1. the spark on the caster, fading as soon as the sparks have left it
	var charge := _charge_ball(origin, 22.0, SPARK_HOT, t, SPARK_CHARGE_TIME)
	var charge_fade := charge.create_tween()
	charge_fade.tween_interval(t + SPARK_CHARGE_TIME)
	charge_fade.tween_property(charge, "modulate:a", 0.0, 0.2)
	charge_fade.tween_callback(charge.queue_free)
	# 2 and 3. the sparks: a few spots on each row, a little shuffled so they do not look lined up
	var spots_per_row := 4 if rich else 3
	var launch_t := t + SPARK_CHARGE_TIME
	var row_index := 0
	for row in [near_row, far_row]:
		for i in spots_per_row:
			var spot := Vector2(
				lerpf(row.position.x + 60.0, row.end.x - 60.0, (i + randf_range(0.25, 0.75)) / spots_per_row),
				row.get_center().y + randf_range(-30.0, 30.0))
			# the sparks of one row leave a little apart from each other, not all in the same frame
			var leave_t := launch_t + row_index * SPARK_ROW_DELAY + i * 0.03
			_flying_spark(origin, spot, leave_t)
			_spark_crackle(spot, leave_t + SPARK_FLIGHT_TIME, rich)
		row_index += 1
	# the faint warm light of the sparks on the table
	_arena_tint(FIRE_EDGE, 0.07 if rich else 0.05, launch_t, 0.12, 0.2, 0.3)
	# the first hits land when the sparks reach the near row
	return SPARK_CHARGE_TIME + SPARK_FLIGHT_TIME

## One spark flying from `from` to `to`, leaving at moment t (a hot dot with a faint glow around it).
func _flying_spark(from: Vector2, to: Vector2, t: float) -> void:
	var spark := fx_library._glow_sprite(9.0, Color.WHITE)
	var spark_glow := fx_library._glow_sprite(26.0, Color(FIRE_EDGE, 0.7))
	spark_glow.scale /= spark.scale # the glow is a child of the spark, so undo the spark's own scale
	spark.add_child(spark_glow)
	spark.position = from
	spark.visible = false
	spark.z_index = 26
	fx.add_child(spark)
	var tween := spark.create_tween()
	tween.tween_interval(t)
	tween.tween_callback(func(): spark.visible = true)
	tween.tween_property(spark, "position", to, SPARK_FLIGHT_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(spark.queue_free)

## Where a spark lands, at moment t: a quick hot flash and a little spray of embers that fall away.
func _spark_crackle(at: Vector2, t: float, rich: bool) -> void:
	var flash := fx_library._glow_sprite(30.0, SPARK_HOT)
	flash.position = at
	flash.z_index = 26
	var full_scale := flash.scale
	flash.scale = Vector2.ZERO
	fx.add_child(flash)
	var flash_tween := flash.create_tween()
	flash_tween.tween_interval(t)
	flash_tween.tween_property(flash, "scale", full_scale, 0.06)
	flash_tween.tween_property(flash, "modulate:a", 0.0, 0.22)
	flash_tween.tween_callback(flash.queue_free)
	var embers := CPUParticles2D.new()
	embers.emitting = false
	embers.one_shot = true
	embers.explosiveness = 1.0
	embers.amount = 14 if rich else 8
	embers.lifetime = 0.5
	embers.position = at
	embers.z_index = 26
	embers.spread = 180.0
	embers.gravity = Vector2(0, 320) # embers fall, they do not float like smoke
	embers.initial_velocity_min = 70.0
	embers.initial_velocity_max = 180.0
	embers.scale_amount_min = 2.0
	embers.scale_amount_max = 3.5
	embers.material = fx_library._additive()
	var ember_colors := Gradient.new()
	ember_colors.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	ember_colors.colors = PackedColorArray([Color.WHITE, SPARK_HOT, Color(FIRE_EDGE, 0.0)])
	embers.color_ramp = ember_colors
	fx.add_child(embers)
	var ember_tween := embers.create_tween()
	ember_tween.tween_interval(t)
	ember_tween.tween_callback(func(): embers.emitting = true)
	ember_tween.tween_interval(0.7)
	ember_tween.tween_callback(embers.queue_free)

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
			fx_library.spawn_embers(Vector2(x, row.get_center().y), t + WATER_ROLL_TIME * row_and_moment[1], WATER_CORE, 14)
	_shake(t + WATER_ROLL_TIME * 0.3, 6.0, 0.5)
	# the first hits land when the wave reaches the middle of the table
	return WATER_ROLL_TIME * 0.5

## Gelo (Avalanche, Zero Absoluto): frost (shaders/ice_frost.gdshader) spreads over the arena from the
## caster's side, crystal plates growing with cracks and sparkles, holds a moment frozen solid, then
## the plates shatter one by one.
const ICE_SPREAD_TIME := 0.65
const ICE_HOLD_TIME := 0.4
const ICE_SHATTER_TIME := 0.45
static var _ice_shader: Shader
func _ice_area(origin: Vector2, t: float) -> float:
	if _ice_shader == null:
		_ice_shader = load("res://scripts/ui/shaders/ice_frost.gdshader")
	var overlay := _arena_overlay(_ice_shader)
	var ice_material: ShaderMaterial = overlay.material
	var arena := _arena().grow(30.0)
	# the frost starts at the caster's edge of the arena (a caster below the middle = from the bottom)
	var caster_below := origin.y > arena.get_center().y
	ice_material.set_shader_parameter("from_bottom", 1.0 if caster_below else 0.0)
	var tween := overlay.create_tween()
	tween.tween_interval(t)
	tween.tween_method(func(value: float): ice_material.set_shader_parameter("progress", value), 0.0, 1.0, ICE_SPREAD_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_interval(ICE_HOLD_TIME)
	tween.tween_method(func(value: float): ice_material.set_shader_parameter("fade", value), 1.0, 0.0, ICE_SHATTER_TIME)
	tween.tween_callback(overlay.queue_free)
	# ice shards flying when the plates shatter, over each row of units
	var shatter_moment := t + ICE_SPREAD_TIME + ICE_HOLD_TIME
	for row in [TableView.MY_LANE, TableView.ENEMY_LANE]:
		for i in 3:
			var x := lerpf(row.position.x + 80.0, row.end.x - 80.0, (i + 0.5) / 3.0)
			fx_library.spawn_embers(Vector2(x, row.get_center().y), shatter_moment, ICE_GLOW, 12)
	# the cold light on the table
	_arena_tint(ICE_GLOW, 0.12, t, 0.3, ICE_SPREAD_TIME + ICE_HOLD_TIME * 0.5, 0.4)
	_shake(shatter_moment, 4.0, 0.35)
	# the first hits land when the frost reaches the middle of the table
	return ICE_SPREAD_TIME * 0.5

## Luz (Expurgo Sagrado, Última Badalada): shafts of holy light (shaders/holy_light.gdshader) pour
## down over the arena from above, wherever the caster is, then softly go out.
const LIGHT_DESCEND_TIME := 0.7
const LIGHT_HOLD_TIME := 0.45
const LIGHT_FADE_TIME := 0.5
static var _light_shader: Shader
func _light_area(t: float) -> float:
	if _light_shader == null:
		_light_shader = load("res://scripts/ui/shaders/holy_light.gdshader")
	var overlay := _arena_overlay(_light_shader)
	var light_material: ShaderMaterial = overlay.material
	var tween := overlay.create_tween()
	tween.tween_interval(t)
	tween.tween_method(func(value: float): light_material.set_shader_parameter("progress", value), 0.0, 1.0, LIGHT_DESCEND_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(LIGHT_HOLD_TIME)
	tween.tween_method(func(value: float): light_material.set_shader_parameter("fade", value), 1.0, 0.0, LIGHT_FADE_TIME)
	tween.tween_callback(overlay.queue_free)
	# motes of light rising from each row as the light reaches it (top row first)
	var rich := fx_library.fx_scale >= 0.7
	var top_row := TableView.ENEMY_LANE if TableView.ENEMY_LANE.position.y < TableView.MY_LANE.position.y else TableView.MY_LANE
	var bottom_row := TableView.MY_LANE if top_row == TableView.ENEMY_LANE else TableView.ENEMY_LANE
	for row_and_moment in [[top_row, 0.35], [bottom_row, 0.7]]:
		var row: Rect2 = row_and_moment[0]
		for i in (3 if rich else 2):
			var x := lerpf(row.position.x + 80.0, row.end.x - 80.0, (i + 0.5) / (3.0 if rich else 2.0))
			fx_library.spawn_embers(Vector2(x, row.get_center().y), t + LIGHT_DESCEND_TIME * row_and_moment[1], HOLY_GOLD, 12)
	_arena_tint(HOLY_GOLD, 0.16 if rich else 0.1, t, 0.35, LIGHT_DESCEND_TIME + LIGHT_HOLD_TIME * 0.5, 0.5)
	# the first hits land when the light reaches the top row of units
	return LIGHT_DESCEND_TIME * 0.4

## Raio (Tempestade Estática, Cumulonimbra): the arena darkens under a storm and bolts
## (shaders/lightning_storm.gdshader) strike the two rows one after another, the table jolting at each.
const STORM_TIME := 1.0
const STORM_FADE_TIME := 0.3
## The bolts strike at these parts of the storm's timeline (must match strike_moment in the shader).
const BOLT_COUNT := 6
static var _lightning_shader: Shader
func _lightning_area(t: float) -> float:
	if _lightning_shader == null:
		_lightning_shader = load("res://scripts/ui/shaders/lightning_storm.gdshader")
	var overlay := _arena_overlay(_lightning_shader)
	var storm_material: ShaderMaterial = overlay.material
	# a new seed each cast, so the bolts never strike the same places twice
	storm_material.set_shader_parameter("seed", randf() * 100.0)
	var tween := overlay.create_tween()
	tween.tween_interval(t)
	tween.tween_method(func(value: float): storm_material.set_shader_parameter("progress", value), 0.0, 1.0, STORM_TIME)
	tween.tween_method(func(value: float): storm_material.set_shader_parameter("fade", value), 1.0, 0.0, STORM_FADE_TIME)
	tween.tween_callback(overlay.queue_free)
	# a small jolt of the table at each strike
	for i in BOLT_COUNT:
		var strike_moment := (i + 0.3) / BOLT_COUNT * 0.82 * STORM_TIME
		_shake(t + strike_moment, 3.5, 0.15)
	# the first hits land with the first bolt
	return (0.3 / BOLT_COUNT) * 0.82 * STORM_TIME

## Veneno (Cicuta no Chá, Névoa de Esporos Teimosos): a thick toxic cloud (shaders/toxic_cloud.gdshader)
## rolls over the arena from the caster's side, spores drifting in it, hangs a moment and thins away.
const POISON_ROLL_TIME := 0.75
const POISON_HOLD_TIME := 0.5
const POISON_FADE_TIME := 0.6
static var _poison_shader: Shader
func _poison_area(origin: Vector2, t: float) -> float:
	if _poison_shader == null:
		_poison_shader = load("res://scripts/ui/shaders/toxic_cloud.gdshader")
	var overlay := _arena_overlay(_poison_shader)
	var cloud_material: ShaderMaterial = overlay.material
	var arena := _arena().grow(30.0)
	# the cloud starts at the caster's edge of the arena (a caster below the middle = from the bottom)
	var caster_below := origin.y > arena.get_center().y
	cloud_material.set_shader_parameter("from_bottom", 1.0 if caster_below else 0.0)
	var tween := overlay.create_tween()
	tween.tween_interval(t)
	tween.tween_method(func(value: float): cloud_material.set_shader_parameter("progress", value), 0.0, 1.0, POISON_ROLL_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(POISON_HOLD_TIME)
	tween.tween_method(func(value: float): cloud_material.set_shader_parameter("fade", value), 1.0, 0.0, POISON_FADE_TIME)
	tween.tween_callback(overlay.queue_free)
	# spore puffs rising from each row as the cloud swallows it (near row first)
	var rich := fx_library.fx_scale >= 0.7
	var near_row := TableView.MY_LANE if caster_below else TableView.ENEMY_LANE
	var far_row := TableView.ENEMY_LANE if caster_below else TableView.MY_LANE
	for row_and_moment in [[near_row, 0.35], [far_row, 0.7]]:
		var row: Rect2 = row_and_moment[0]
		for i in (3 if rich else 2):
			var x := lerpf(row.position.x + 80.0, row.end.x - 80.0, (i + 0.5) / (3.0 if rich else 2.0))
			fx_library.spawn_embers(Vector2(x, row.get_center().y), t + POISON_ROLL_TIME * row_and_moment[1], VENOM_PURPLE, 10)
	# no shake: poison is quiet, it seeps in instead of hitting
	# the first hits land when the cloud reaches the near row of units
	return POISON_ROLL_TIME * 0.4

## Pedra: a rockslide (shaders/stone_rockfall.gdshader). Boulders rain over the whole arena, each landing at
## its own moment with a puff of dust and cracks in the ground; the table jolts on the landings, then the
## rubble lies there for a moment and crumbles to dust. One rectangle and one shader, plus a few particles.
const STONE_FALL_TIME := 0.95
const STONE_HOLD_TIME := 0.45
const STONE_CRUMBLE_TIME := 0.6
static var _stone_shader: Shader
func _stone_area(origin: Vector2, t: float) -> float:
	if _stone_shader == null:
		_stone_shader = load("res://scripts/ui/shaders/stone_rockfall.gdshader")
	var overlay := _arena_overlay(_stone_shader)
	var stone_material: ShaderMaterial = overlay.material
	var tween := overlay.create_tween()
	tween.tween_interval(t)
	tween.tween_method(func(value: float): stone_material.set_shader_parameter("progress", value), 0.0, 1.0, STONE_FALL_TIME)
	tween.tween_interval(STONE_HOLD_TIME)
	tween.tween_method(func(value: float): stone_material.set_shader_parameter("fade", value), 1.0, 0.0, STONE_CRUMBLE_TIME)
	tween.tween_callback(overlay.queue_free)
	var rich := fx_library.fx_scale >= 0.7
	# the table jolts as the boulders land (the first ones, the bulk, the last ones)
	_shake(t + STONE_FALL_TIME * 0.3, 7.0, 0.3)
	_shake(t + STONE_FALL_TIME * 0.6, 11.0, 0.35)
	if rich:
		_shake(t + STONE_FALL_TIME * 0.9, 8.0, 0.3)
	_arena_tint(STONE_DUST, 0.1, t + STONE_FALL_TIME * 0.25, 0.3, STONE_FALL_TIME * 0.4, 0.5)
	# dust thrown up from each row as the rocks hit it
	for row_and_moment in [[TableView.ENEMY_LANE, 0.5], [TableView.MY_LANE, 0.75]]:
		var row: Rect2 = row_and_moment[0]
		for i in (3 if rich else 2):
			var x := lerpf(row.position.x + 80.0, row.end.x - 80.0, (i + 0.5) / (3.0 if rich else 2.0))
			fx_library.spawn_embers(Vector2(x, row.get_center().y), t + STONE_FALL_TIME * row_and_moment[1], STONE_DUST, 12)
	# the first hits land when the first boulders have reached the table
	return STONE_FALL_TIME * 0.45

## Vegetal: a thicket (shaders/vine_overgrowth.gdshader). Thorny vines sprout from the caster's edge of the
## arena and snake across it with leaves opening along them, hold for a moment, then wither brown and break
## apart. Quiet like the poison cloud, no shake. One rectangle and one shader, plus a few particles.
const VINE_GROW_TIME := 0.95
const VINE_HOLD_TIME := 0.5
const VINE_WITHER_TIME := 0.7
const DRY_LEAF_BROWN := Color("#a07a38")
static var _vine_shader: Shader
func _vine_area(origin: Vector2, t: float) -> float:
	if _vine_shader == null:
		_vine_shader = load("res://scripts/ui/shaders/vine_overgrowth.gdshader")
	var overlay := _arena_overlay(_vine_shader)
	var vine_material: ShaderMaterial = overlay.material
	var arena := _arena().grow(30.0)
	# the vines start at the caster's edge of the arena (a caster below the middle = from the bottom)
	var caster_below := origin.y > arena.get_center().y
	vine_material.set_shader_parameter("from_bottom", 1.0 if caster_below else 0.0)
	var tween := overlay.create_tween()
	tween.tween_interval(t)
	tween.tween_method(func(value: float): vine_material.set_shader_parameter("progress", value), 0.0, 1.0, VINE_GROW_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(VINE_HOLD_TIME)
	tween.tween_method(func(value: float): vine_material.set_shader_parameter("fade", value), 1.0, 0.0, VINE_WITHER_TIME)
	tween.tween_callback(overlay.queue_free)
	var rich := fx_library.fx_scale >= 0.7
	var near_row := TableView.MY_LANE if caster_below else TableView.ENEMY_LANE
	var far_row := TableView.ENEMY_LANE if caster_below else TableView.MY_LANE
	# green specks as the vines pass each row (near row first)...
	for row_and_moment in [[near_row, 0.35], [far_row, 0.75]]:
		var row: Rect2 = row_and_moment[0]
		for i in (3 if rich else 2):
			var x := lerpf(row.position.x + 80.0, row.end.x - 80.0, (i + 0.5) / (3.0 if rich else 2.0))
			fx_library.spawn_embers(Vector2(x, row.get_center().y), t + VINE_GROW_TIME * row_and_moment[1], LEAF_GREEN, 8)
	# ...and dry brown leaves falling as they wither
	if rich:
		for row in [near_row, far_row]:
			fx_library.spawn_embers(row.get_center(), t + VINE_GROW_TIME + VINE_HOLD_TIME + 0.1, DRY_LEAF_BROWN, 10)
	# the first hits land when the vines reach the near row of units
	return VINE_GROW_TIME * 0.4

## Sangue (Coagulhão, and the Fúria cards of the element sangue): a thick tide of blood
## (shaders/blood_tide.gdshader) seeps over the arena from the caster's side, pumped like a heart:
## 1. a dark red glow swells on the caster;
## 2. the tide advances in two surges, "ba-dum", one per heartbeat: the vessels in it light up, the table
##    jolts and drops of blood splash up from the row it reaches;
## 3. it lies on the table for a moment, throbbing once more, weaker;
## 4. it clots: darkens to maroon, cracks and flakes away in patches.
## One rectangle and one shader, plus a few plain particles, cheap on phones.
const BLOOD_FIRST_SURGE_TIME := 0.38 ## the first beat carries the tide past the middle of the table
const BLOOD_SECOND_SURGE_TIME := 0.42 ## the second beat carries it to the far edge
const BLOOD_FIRST_SURGE_REACH := 0.55 ## how much of the tide's path the first beat covers (0 to 1)
const BLOOD_HOLD_TIME := 0.1 ## almost no pause: the tide must not sit on the table, it clots right after the second beat
const BLOOD_CLOT_TIME := 0.55
static var _blood_shader: Shader
func _blood_area(origin: Vector2, t: float) -> float:
	if _blood_shader == null:
		_blood_shader = load("res://scripts/ui/shaders/blood_tide.gdshader")
	var rich := fx_library.fx_scale >= 0.7
	var overlay := _arena_overlay(_blood_shader)
	var blood_material: ShaderMaterial = overlay.material
	var arena := _arena().grow(30.0)
	# the tide starts at the caster's edge of the arena (a caster below the middle = from the bottom)
	var caster_below := origin.y > arena.get_center().y
	blood_material.set_shader_parameter("from_bottom", 1.0 if caster_below else 0.0)
	var set_progress := func(value: float): blood_material.set_shader_parameter("progress", value)
	var tide := overlay.create_tween()
	tide.tween_interval(t)
	tide.tween_method(set_progress, 0.0, BLOOD_FIRST_SURGE_REACH, BLOOD_FIRST_SURGE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tide.tween_method(set_progress, BLOOD_FIRST_SURGE_REACH, 1.0, BLOOD_SECOND_SURGE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tide.tween_interval(BLOOD_HOLD_TIME)
	tide.tween_method(func(value: float): blood_material.set_shader_parameter("clot", value), 0.0, 1.0, BLOOD_CLOT_TIME)
	tide.tween_callback(overlay.queue_free)
	# the heartbeats: two strong ones that push the tide, and a weaker one while it lies on the table
	var second_beat := t + BLOOD_FIRST_SURGE_TIME
	var last_beat := second_beat + BLOOD_SECOND_SURGE_TIME + BLOOD_HOLD_TIME * 0.5
	var beats := overlay.create_tween()
	var beat_moment := 0.0
	for beat in [[t, 1.0], [second_beat, 0.9], [last_beat, 0.5]]:
		beats.tween_interval(beat[0] - beat_moment)
		beats.tween_method(func(value: float): blood_material.set_shader_parameter("pulse", value), 0.0, beat[1], 0.07)
		beats.tween_method(func(value: float): blood_material.set_shader_parameter("pulse", value), beat[1], 0.0, 0.3).set_ease(Tween.EASE_OUT)
		beat_moment = beat[0] + 0.37
	_shake(t, 5.0, 0.25)
	_shake(second_beat, 4.0, 0.25)
	# 1. the dark red glow on the caster, gone once the tide has left it
	var charge := _charge_ball(origin, 30.0, BLOOD_RED, t, 0.16)
	var charge_fade := charge.create_tween()
	charge_fade.tween_interval(t + 0.2)
	charge_fade.tween_property(charge, "modulate:a", 0.0, 0.3)
	charge_fade.tween_callback(charge.queue_free)
	# 2. drops of blood splashing up where the tide reaches each row of units (near row on the first beat)
	var near_row := TableView.MY_LANE if caster_below else TableView.ENEMY_LANE
	var far_row := TableView.ENEMY_LANE if caster_below else TableView.MY_LANE
	var splashes_per_row := 3 if rich else 2
	for row_and_moment in [[near_row, t + BLOOD_FIRST_SURGE_TIME * 0.35], [far_row, second_beat + BLOOD_SECOND_SURGE_TIME * 0.3]]:
		var row: Rect2 = row_and_moment[0]
		for i in splashes_per_row:
			var x := lerpf(row.position.x + 80.0, row.end.x - 80.0, (i + randf_range(0.3, 0.7)) / splashes_per_row)
			_blood_splash(Vector2(x, row.get_center().y + randf_range(-20.0, 20.0)), row_and_moment[1] + i * 0.04, rich)
	# the faint red light of the blood on the table
	_arena_tint(BLOOD_RED, 0.1 if rich else 0.07, t, 0.25, BLOOD_FIRST_SURGE_TIME + BLOOD_SECOND_SURGE_TIME - 0.2, 0.4)
	# the first hits land when the first beat has carried the tide to the middle of the table
	return BLOOD_FIRST_SURGE_TIME * 0.8

## A splash of blood at moment t: thick drops thrown up that fall back down. Normal blending (not
## additive, so they look like liquid, not sparks).
func _blood_splash(at: Vector2, t: float, rich: bool) -> void:
	var drops := CPUParticles2D.new()
	drops.emitting = false
	drops.one_shot = true
	drops.explosiveness = 0.9
	drops.amount = 12 if rich else 7
	drops.lifetime = 0.6
	drops.position = at
	drops.z_index = 26
	drops.direction = Vector2(0, -1)
	drops.spread = 55.0
	drops.gravity = Vector2(0, 700) # heavy drops, they fall back fast
	drops.initial_velocity_min = 120.0
	drops.initial_velocity_max = 260.0
	drops.scale_amount_min = 2.5
	drops.scale_amount_max = 5.0
	var drop_colors := Gradient.new()
	drop_colors.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	drop_colors.colors = PackedColorArray([Color("#e0303a"), BLOOD_RED, Color(BLOOD_DARK, 0.0)])
	drops.color_ramp = drop_colors
	fx.add_child(drops)
	var tween := drops.create_tween()
	tween.tween_interval(t)
	tween.tween_callback(func(): drops.emitting = true)
	tween.tween_interval(0.8)
	tween.tween_callback(drops.queue_free)

## ---- Destroy casts: a spell that destroys ONE unit (Reduzir a Cinzas, Afogar) ----
## Instead of the red X, the unit is taken by its element (burned, drowned) and dissolves inside it.
## Only the card's own "destroy_fx", "cast_fx" or element counts here, never its domain: a Fúria kick with no
## element (Chute no Portão) keeps the X instead of bursting into flames.

## The destroy animation of a card (a spell, or a unit's trigger / activated ability): one of DESTROY_STYLES,
## or "" when it keeps the X.
func destroy_style_of(card_id: String) -> String:
	var card := CardDB.card(card_id)
	# the card's own "destroy_fx" wins (so a "cast_fx" meant for its area damage never decides how a unit dies),
	# then its "cast_fx", then the style of its element
	var style := ""
	if card.has("destroy_fx"):
		style = String(card["destroy_fx"])
	elif card.has("cast_fx"):
		style = String(card["cast_fx"])
	else:
		style = String(ELEMENT_STYLES.get(String(card.get("element", "")), ""))
	return style if style in DESTROY_STYLES else ""

## Plays the destroy animation of `style` over the unit `unit_view` at moment t.
## Returns the time from t until the unit should start dissolving (inside the fire / under the water).
func destroy_cast(style: String, unit_view: Control, t: float) -> float:
	var center: Vector2 = fx_library.center_of(unit_view)
	var card_size: Vector2 = unit_view.size * unit_view.scale
	match style:
		"fogo":
			return _burn_unit(center, card_size, t)
		"agua":
			return _drown_unit(center, card_size, t)
		"pedra":
			return _crush_unit(center, card_size, t)
		"vegetal":
			return _overgrow_unit(center, card_size, t)
		"veneno":
			return _corrode_unit(center, card_size, t)
		"sangue":
			return _bleed_unit(center, card_size, t)
		"raio":
			return _electrocute_unit(center, card_size, t)
		"gelo":
			return _freeze_unit(unit_view, center, card_size, t)
		"luz":
			return _smite_unit(center, card_size, t)
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
	fx_library.spawn_embers(Vector2(center.x, center.y + card_size.y * 0.4), t + 0.1, FIRE_EDGE, 16)
	fx_library.spawn_embers(center, t + BURN_CLIMB_TIME, FIRE_EDGE, 20)
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
	fx_library.spawn_embers(Vector2(center.x, center.y + card_size.y * 0.45), t + 0.05, WATER_CORE, 12)
	fx_library.spawn_embers(Vector2(center.x, center.y - card_size.y * 0.5), t + DROWN_RISE_TIME, WATER_CORE, 14)
	# the unit starts dissolving once it is fully under water
	return DROWN_RISE_TIME

## Pedra (Desabamento Oportuno): boulders (shaders/unit_crush.gdshader) fall on the card one after
## another and pile up, the table jolting at each; the unit dissolves under the pile, then the rocks
## crumble to dust. The rectangle reaches well above the card: that is the sky the rocks fall through.
const CRUSH_FALL_TIME := 0.6
const CRUSH_HOLD_TIME := 0.4
const CRUSH_CRUMBLE_TIME := 0.45
static var _crush_shader: Shader
func _crush_unit(center: Vector2, card_size: Vector2, t: float) -> float:
	if _crush_shader == null:
		_crush_shader = load("res://scripts/ui/shaders/unit_crush.gdshader")
	var rock_size := Vector2(card_size.x * 1.3, card_size.y * 1.6)
	# the bottom of the rectangle sits just below the card; the extra height goes up
	var rock_rect := Rect2(Vector2(center.x - rock_size.x * 0.5, center.y + card_size.y * 0.55 - rock_size.y), rock_size)
	var overlay := _unit_overlay(_crush_shader, rock_rect)
	var crush_material: ShaderMaterial = overlay.material
	# where the card's top edge is inside the rectangle (the pile stops there)
	crush_material.set_shader_parameter("card_top", (center.y - card_size.y * 0.5 - rock_rect.position.y) / rock_size.y)
	var tween := overlay.create_tween()
	tween.tween_interval(t)
	tween.tween_method(func(value: float): crush_material.set_shader_parameter("progress", value), 0.0, 1.0, CRUSH_FALL_TIME)
	tween.tween_interval(CRUSH_HOLD_TIME)
	tween.tween_method(func(value: float): crush_material.set_shader_parameter("fade", value), 1.0, 0.0, CRUSH_CRUMBLE_TIME)
	tween.tween_callback(overlay.queue_free)
	# the first rock lands about a third of the way in; the heavy jolt comes with it
	var first_landing := t + CRUSH_FALL_TIME * 0.32
	_shake(first_landing, 7.0, 0.3)
	_shake(t + CRUSH_FALL_TIME * 0.75, 5.0, 0.3)
	fx_library.spawn_embers(Vector2(center.x, center.y + card_size.y * 0.4), first_landing, STONE_DUST, 14)
	fx_library.spawn_embers(center, t + CRUSH_FALL_TIME + CRUSH_HOLD_TIME, STONE_DUST, 16)
	# the unit starts dissolving once most of the pile is on it
	return CRUSH_FALL_TIME * 0.8

## Vegetal (Capina Seletiva): vines (shaders/unit_overgrow.gdshader) sprout from the base of the card
## and climb over it with leaves opening, the unit is taken under them, then they wither and fall apart.
const OVERGROW_TIME := 0.6
const OVERGROW_HOLD_TIME := 0.45
const OVERGROW_WITHER_TIME := 0.5
static var _overgrow_shader: Shader
func _overgrow_unit(center: Vector2, card_size: Vector2, t: float) -> float:
	if _overgrow_shader == null:
		_overgrow_shader = load("res://scripts/ui/shaders/unit_overgrow.gdshader")
	var vine_size := card_size * Vector2(1.25, 1.15)
	var vine_rect := Rect2(center - vine_size * 0.5, vine_size)
	var overlay := _unit_overlay(_overgrow_shader, vine_rect)
	var vine_material: ShaderMaterial = overlay.material
	var tween := overlay.create_tween()
	tween.tween_interval(t)
	tween.tween_method(func(value: float): vine_material.set_shader_parameter("progress", value), 0.0, 1.0, OVERGROW_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(OVERGROW_HOLD_TIME)
	tween.tween_method(func(value: float): vine_material.set_shader_parameter("fade", value), 1.0, 0.0, OVERGROW_WITHER_TIME)
	tween.tween_callback(overlay.queue_free)
	fx_library.spawn_embers(Vector2(center.x, center.y + card_size.y * 0.45), t + 0.05, LEAF_GREEN, 10)
	# dry leaves falling off as the vines wither
	fx_library.spawn_embers(center, t + OVERGROW_TIME + OVERGROW_HOLD_TIME, Color("#8a6a2e"), 14)
	# the unit starts dissolving once the vines have climbed most of the way
	return OVERGROW_TIME * 0.85

## Veneno (Ponto Final sem Vírgula): venom (shaders/unit_corrode.gdshader) oozes down the card from its
## top in drips and eats holes through it with acid-green rims; the unit dissolves, then the venom fades.
const CORRODE_TIME := 0.65
const CORRODE_HOLD_TIME := 0.4
const CORRODE_FADE_TIME := 0.45
static var _corrode_shader: Shader
func _corrode_unit(center: Vector2, card_size: Vector2, t: float) -> float:
	if _corrode_shader == null:
		_corrode_shader = load("res://scripts/ui/shaders/unit_corrode.gdshader")
	var venom_size := card_size * Vector2(1.15, 1.1)
	var venom_rect := Rect2(center - venom_size * 0.5, venom_size)
	var overlay := _unit_overlay(_corrode_shader, venom_rect)
	var venom_material: ShaderMaterial = overlay.material
	var tween := overlay.create_tween()
	tween.tween_interval(t)
	tween.tween_method(func(value: float): venom_material.set_shader_parameter("progress", value), 0.0, 1.0, CORRODE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_interval(CORRODE_HOLD_TIME)
	tween.tween_method(func(value: float): venom_material.set_shader_parameter("fade", value), 1.0, 0.0, CORRODE_FADE_TIME)
	tween.tween_callback(overlay.queue_free)
	# toxic fumes rising off the card
	fx_library.spawn_embers(Vector2(center.x, center.y - card_size.y * 0.3), t + CORRODE_TIME * 0.6, Color("#9dff52"), 12)
	# the unit starts dissolving once the venom has eaten into it
	return CORRODE_TIME * 0.85

## Sangue: the unit is bled dry (shaders/unit_bleed.gdshader). A mix of the two liquid destroys, blood
## drips down from the top (like the venom) while a pool rises from the bottom (like the water), plus its
## own mark: a wound opens in the middle of the card and veins race out of it, glowing at each of three
## heartbeats, with a spurt of blood and a jolt on the strong beats. The unit dissolves once the blood meets
## over it, then the blood clots and flakes away.
const BLEED_TIME := 0.75
const BLEED_HOLD_TIME := 0.4
const BLEED_CLOT_TIME := 0.5
static var _bleed_shader: Shader
func _bleed_unit(center: Vector2, card_size: Vector2, t: float) -> float:
	if _bleed_shader == null:
		_bleed_shader = load("res://scripts/ui/shaders/unit_bleed.gdshader")
	var blood_size := card_size * Vector2(1.18, 1.12)
	var blood_rect := Rect2(center - blood_size * 0.5, blood_size)
	var overlay := _unit_overlay(_bleed_shader, blood_rect)
	var bleed_material: ShaderMaterial = overlay.material
	var tween := overlay.create_tween()
	tween.tween_interval(t)
	tween.tween_method(func(value: float): bleed_material.set_shader_parameter("progress", value), 0.0, 1.0, BLEED_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_interval(BLEED_HOLD_TIME)
	tween.tween_method(func(value: float): bleed_material.set_shader_parameter("fade", value), 1.0, 0.0, BLEED_CLOT_TIME)
	tween.tween_callback(overlay.queue_free)
	# three heartbeats (moment, strength): each one rises fast and falls slowly, like the blood tide
	var beats := [[t + 0.05, 1.0], [t + 0.38, 0.85], [t + 0.7, 0.55]]
	var pulse_tween := overlay.create_tween()
	var beat_clock := 0.0
	for beat in beats:
		pulse_tween.tween_interval(beat[0] - beat_clock)
		pulse_tween.tween_method(func(value: float): bleed_material.set_shader_parameter("pulse", value), 0.0, beat[1], 0.07)
		pulse_tween.tween_method(func(value: float): bleed_material.set_shader_parameter("pulse", value), beat[1], 0.0, 0.25)
		beat_clock = beat[0] + 0.32
	# a spurt from the wound and a jolt on the two strong beats (the weak last one is only seen, not felt)
	var rich: bool = fx_library.fx_scale >= 0.7
	for beat in beats.slice(0, 2):
		_blood_splash(center, beat[0], rich)
		_shake(beat[0], 3.0, 0.2)
	# the unit starts dissolving once the drips and the pool have met over it
	return BLEED_TIME * 0.85

## Raio: the unit is electrocuted (shaders/unit_electrocute.gdshader). Jagged bolts strike the card and keep
## crackling over it, the whole card strobing blue-white, and twice, very quickly, a skeleton "X-ray" flashes
## over it (the body goes dark and the bones light up). The unit starts dissolving between the two flashes,
## so the second one catches it already breaking up, then the bolts die out.
const ELECTROCUTE_STRIKE_TIME := 0.15
const ELECTROCUTE_HOLD_TIME := 0.5
const ELECTROCUTE_FADE_TIME := 0.25
## When each X-ray flash starts (seconds after the first strike), and how long one lasts: it lights up almost
## at once and goes out a little slower.
const XRAY_FLASH_MOMENTS := [0.12, 0.3]
const XRAY_RISE_TIME := 0.02
const XRAY_FALL_TIME := 0.07
static var _electrocute_shader: Shader
func _electrocute_unit(center: Vector2, card_size: Vector2, t: float) -> float:
	if _electrocute_shader == null:
		_electrocute_shader = load("res://scripts/ui/shaders/unit_electrocute.gdshader")
	var arc_size := card_size * Vector2(1.18, 1.12)
	var arc_rect := Rect2(center - arc_size * 0.5, arc_size)
	var overlay := _unit_overlay(_electrocute_shader, arc_rect)
	var electric_material: ShaderMaterial = overlay.material
	var tween := overlay.create_tween()
	tween.tween_interval(t)
	tween.tween_method(func(value: float): electric_material.set_shader_parameter("progress", value), 0.0, 1.0, ELECTROCUTE_STRIKE_TIME)
	tween.tween_interval(ELECTROCUTE_HOLD_TIME)
	tween.tween_method(func(value: float): electric_material.set_shader_parameter("fade", value), 1.0, 0.0, ELECTROCUTE_FADE_TIME)
	tween.tween_callback(overlay.queue_free)
	# the two X-ray flashes, on their own tween (it dies with the overlay)
	var xray_tween := overlay.create_tween()
	var xray_clock := 0.0
	for moment in XRAY_FLASH_MOMENTS:
		var flash_start: float = t + moment
		xray_tween.tween_interval(flash_start - xray_clock)
		xray_tween.tween_method(func(value: float): electric_material.set_shader_parameter("xray", value), 0.0, 1.0, XRAY_RISE_TIME)
		xray_tween.tween_method(func(value: float): electric_material.set_shader_parameter("xray", value), 1.0, 0.0, XRAY_FALL_TIME)
		xray_clock = flash_start + XRAY_RISE_TIME + XRAY_FALL_TIME
		_shake(flash_start, 3.0, 0.1)
	# sparks off the card, and a jolt with the first strike
	fx_library.spawn_embers(center, t + 0.05, BOLT_BLUE, 14)
	fx_library.spawn_embers(Vector2(center.x, center.y + card_size.y * 0.3), t + 0.25, BOLT_BLUE, 10)
	_shake(t, 4.0, 0.2)
	# the unit starts dissolving between the two flashes
	return XRAY_FLASH_MOMENTS[0] + XRAY_RISE_TIME + XRAY_FALL_TIME + 0.05

## Luz: the unit is smitten by holy light (shaders/unit_smite.gdshader). A pillar of golden-white light falls
## from above onto the card, a bright veil washes the card out, and a halo (a ring and soft rays) opens from its
## middle. The unit starts dissolving inside the veil, so it fades away in the light as the veil clears.
## The rectangle is much taller than the card (the pillar comes from above) and a little wider.
const SMITE_RECT_WIDTH_FACTOR := 1.8
const SMITE_RECT_HEIGHT_FACTOR := 2.4
const SMITE_FALL_TIME := 0.2
const SMITE_WASH_START := 0.1
const SMITE_WASH_RISE_TIME := 0.2
const SMITE_WASH_FALL_TIME := 0.55
const SMITE_HALO_START := 0.2
const SMITE_HALO_TIME := 0.5
const SMITE_BEAM_HOLD_TIME := 0.3
const SMITE_BEAM_FADE_TIME := 0.4
static var _smite_shader: Shader
func _smite_unit(center: Vector2, card_size: Vector2, t: float) -> float:
	if _smite_shader == null:
		_smite_shader = load("res://scripts/ui/shaders/unit_smite.gdshader")
	var light_size := Vector2(card_size.x * SMITE_RECT_WIDTH_FACTOR, card_size.y * SMITE_RECT_HEIGHT_FACTOR)
	var light_rect := Rect2(center - light_size * 0.5, light_size)
	var overlay := _unit_overlay(_smite_shader, light_rect)
	var light_material: ShaderMaterial = overlay.material
	light_material.set_shader_parameter("card_uv_size", Vector2(card_size.x / light_size.x, card_size.y / light_size.y))
	# the pillar falls, holds, then fades; the overlay goes away when it is gone
	var tween := overlay.create_tween()
	tween.tween_interval(t)
	tween.tween_method(func(value: float): light_material.set_shader_parameter("progress", value), 0.0, 1.0, SMITE_FALL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_interval(SMITE_BEAM_HOLD_TIME)
	tween.tween_method(func(value: float): light_material.set_shader_parameter("beam_strength", value), 1.0, 0.0, SMITE_BEAM_FADE_TIME)
	tween.tween_callback(overlay.queue_free)
	# the veil over the card: rises fast, clears slower while the unit dissolves (own tween, it dies with the overlay)
	var wash_tween := overlay.create_tween()
	wash_tween.tween_interval(t + SMITE_WASH_START)
	wash_tween.tween_method(func(value: float): light_material.set_shader_parameter("wash", value), 0.0, 1.0, SMITE_WASH_RISE_TIME)
	wash_tween.tween_method(func(value: float): light_material.set_shader_parameter("wash", value), 1.0, 0.0, SMITE_WASH_FALL_TIME)
	# the halo opening
	var halo_tween := overlay.create_tween()
	halo_tween.tween_interval(t + SMITE_HALO_START)
	halo_tween.tween_method(func(value: float): light_material.set_shader_parameter("halo", value), 0.0, 1.0, SMITE_HALO_TIME)
	# gold motes rising off the card, and a soft jolt when the light lands
	fx_library.spawn_embers(center, t + SMITE_WASH_START + SMITE_WASH_RISE_TIME * 0.5, HOLY_GOLD, 22)
	fx_library.spawn_embers(Vector2(center.x, center.y - card_size.y * 0.2), t + SMITE_WASH_START + SMITE_WASH_RISE_TIME, Color.WHITE, 10)
	_shake(t + SMITE_FALL_TIME * 0.6, 2.0, 0.15)
	# the unit starts dissolving once the veil is at its peak (the card is hidden in the light)
	return SMITE_WASH_START + SMITE_WASH_RISE_TIME

## Gelo: the unit is frozen solid and shatters (shaders/unit_freeze.gdshader). Frost creeps in from the edges
## of the card and cracks run out of its middle. At the moment it breaks, a picture of the frozen card is taken
## off the screen, the real card is hidden and the picture flies apart in shards (_shatter_unit), with a pale
## flash, a burst of ice splinters and a jolt.
const FREEZE_TIME := 0.5
const FREEZE_CRACK_START := 0.35
const FREEZE_CRACK_TIME := 0.25
const FREEZE_SHATTER_MOMENT := 0.62
const FREEZE_AFTER_SHATTER_TIME := 0.3 ## how long the flash overlay lives after the break
static var _freeze_shader: Shader
func _freeze_unit(unit_view: Control, center: Vector2, card_size: Vector2, t: float) -> float:
	if _freeze_shader == null:
		_freeze_shader = load("res://scripts/ui/shaders/unit_freeze.gdshader")
	var frost_size := card_size * Vector2(1.18, 1.12)
	var frost_rect := Rect2(center - frost_size * 0.5, frost_size)
	var overlay := _unit_overlay(_freeze_shader, frost_rect)
	var frost_material: ShaderMaterial = overlay.material
	# the frost creeping in; at the break the card turns into shards, then the overlay goes away
	var tween := overlay.create_tween()
	tween.tween_interval(t)
	tween.tween_method(func(value: float): frost_material.set_shader_parameter("progress", value), 0.0, 1.0, FREEZE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(FREEZE_SHATTER_MOMENT - FREEZE_TIME)
	tween.tween_callback(func():
		frost_material.set_shader_parameter("shattered", 1.0)
		_shatter_unit(unit_view, center, card_size))
	tween.tween_interval(FREEZE_AFTER_SHATTER_TIME)
	tween.tween_callback(overlay.queue_free)
	# the cracks spreading, on their own tween (it dies with the overlay)
	var crack_tween := overlay.create_tween()
	crack_tween.tween_interval(t + FREEZE_CRACK_START)
	crack_tween.tween_method(func(value: float): frost_material.set_shader_parameter("cracks", value), 0.0, 1.0, FREEZE_CRACK_TIME)
	# the shatter flash: lights up at once, goes out slower
	var flash_tween := overlay.create_tween()
	flash_tween.tween_interval(t + FREEZE_SHATTER_MOMENT)
	flash_tween.tween_method(func(value: float): frost_material.set_shader_parameter("flash", value), 0.0, 1.0, 0.03)
	flash_tween.tween_method(func(value: float): frost_material.set_shader_parameter("flash", value), 1.0, 0.0, 0.25)
	# a little chill while it freezes, then the splinters and the jolt when it breaks
	fx_library.spawn_embers(Vector2(center.x, center.y - card_size.y * 0.3), t + FREEZE_TIME * 0.4, ICE_GLOW, 8)
	fx_library.spawn_embers(center, t + FREEZE_SHATTER_MOMENT, ICE_GLOW, 18)
	fx_library.spawn_embers(center, t + FREEZE_SHATTER_MOMENT + 0.05, Color.WHITE, 8)
	_shake(t + FREEZE_SHATTER_MOMENT, 4.0, 0.2)
	# the real card is already gone (hidden) at the break, so main can start its dissolve there
	return FREEZE_SHATTER_MOMENT

const SHARD_COLUMNS := 4
const SHARD_ROWS := 6
const SHARD_FLIGHT_TIME := 0.75
## Breaks `unit_view` into flying shards of its own picture. The picture is read back from the screen (so it
## shows the frost and the cracks), cut into triangles over a jittered grid, and the real card is hidden in the
## same frame. Without a screen to read (headless) the card is just hidden.
func _shatter_unit(unit_view: Control, center: Vector2, card_size: Vector2) -> void:
	var screen_image := fx.get_viewport().get_texture().get_image()
	if is_instance_valid(unit_view):
		unit_view.visible = false
	if screen_image == null or screen_image.is_empty():
		return
	# where the card is on the screen, in pixels (the window may be stretched to the 1600x900 design size)
	var to_canvas: Transform2D = fx.get_global_transform_with_canvas()
	var pixels_per_unit: float = float(screen_image.get_width()) / fx.get_viewport().get_visible_rect().size.x
	var card_rect := Rect2(center - card_size * 0.5, card_size)
	var corner_a: Vector2 = to_canvas * card_rect.position * pixels_per_unit
	var corner_b: Vector2 = to_canvas * card_rect.end * pixels_per_unit
	var wanted := Rect2i(Vector2i(corner_a.floor()), Vector2i((corner_b - corner_a).ceil())).intersection(Rect2i(Vector2i.ZERO, screen_image.get_size()))
	if wanted.size.x < 4 or wanted.size.y < 4:
		return
	var picture := ImageTexture.create_from_image(screen_image.get_region(wanted))
	# the grid of corners; the inner ones are shaken loose so the shards are not all alike
	var corners: Array = []
	for row in SHARD_ROWS + 1:
		for column in SHARD_COLUMNS + 1:
			var corner := card_rect.position + Vector2(card_size.x * column / SHARD_COLUMNS, card_size.y * row / SHARD_ROWS)
			if column > 0 and column < SHARD_COLUMNS and row > 0 and row < SHARD_ROWS:
				corner += Vector2(randf_range(-0.3, 0.3) * card_size.x / SHARD_COLUMNS, randf_range(-0.3, 0.3) * card_size.y / SHARD_ROWS)
			corners.append(corner)
	var shards := Node2D.new()
	fx.add_child(shards)
	var flights: Array = [] # per shard: [node, start position, velocity, spin]
	var gravity := card_size.y * 5.0
	for row in SHARD_ROWS:
		for column in SHARD_COLUMNS:
			var top_left: Vector2 = corners[row * (SHARD_COLUMNS + 1) + column]
			var top_right: Vector2 = corners[row * (SHARD_COLUMNS + 1) + column + 1]
			var bottom_left: Vector2 = corners[(row + 1) * (SHARD_COLUMNS + 1) + column]
			var bottom_right: Vector2 = corners[(row + 1) * (SHARD_COLUMNS + 1) + column + 1]
			# each cell is cut along one of its two diagonals
			var triangles: Array = [[top_left, top_right, bottom_right], [top_left, bottom_right, bottom_left]] if randf() < 0.5 \
				else [[top_left, top_right, bottom_left], [top_right, bottom_right, bottom_left]]
			for triangle in triangles:
				var centroid: Vector2 = (triangle[0] + triangle[1] + triangle[2]) / 3.0
				var shard := Polygon2D.new()
				shard.texture = picture
				shard.position = centroid
				var outline := PackedVector2Array()
				var picture_points := PackedVector2Array()
				for point in triangle:
					outline.append(point - centroid)
					picture_points.append(to_canvas * point * pixels_per_unit - Vector2(wanted.position))
				shard.polygon = outline
				shard.uv = picture_points
				shards.add_child(shard)
				# thrown away from the middle of the card, a little upward, spinning
				var outward: Vector2 = (centroid - center).normalized()
				var velocity: Vector2 = outward * card_size.x * randf_range(0.8, 2.4) + Vector2(0.0, -card_size.y * randf_range(0.2, 0.9))
				flights.append([shard, centroid, velocity, randf_range(-6.0, 6.0)])
	var fly_shards := func(elapsed: float):
		for entry in flights:
			var shard_node: Polygon2D = entry[0]
			shard_node.position = entry[1] + entry[2] * elapsed + Vector2(0.0, gravity * elapsed * elapsed * 0.5)
			shard_node.rotation = entry[3] * elapsed
		# the shards fade over the last part of the flight
		shards.modulate.a = clampf((SHARD_FLIGHT_TIME - elapsed) / (SHARD_FLIGHT_TIME * 0.4), 0.0, 1.0)
	var flight := shards.create_tween()
	flight.tween_method(fly_shards, 0.0, SHARD_FLIGHT_TIME, SHARD_FLIGHT_TIME)
	flight.tween_callback(shards.queue_free)

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
