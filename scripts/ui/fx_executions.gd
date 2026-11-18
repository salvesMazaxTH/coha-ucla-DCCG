class_name FxExecutions
extends RefCounted
## Executions with a look of their own. A card names one with "execution_style" on its "kill_leader" effect,
## and then it plays INSTEAD of both the default execution (the crossed slashes and "Execução") and the
## Leader's death burst: the whole death of the Leader is told here.
## A style name that is not in STYLES falls back to the default execution.

const STYLES := ["rai"]

## Rai, Imortal Imperfeito: a silent unmaking. The table sinks into a violet void, ten Fragments spiral in and
## circle the Leader, and its portrait slowly turns, loses its color and evaporates into dust and black petals
## that drift away. No pain: no shaking, no flash, no blast.
const RAI_GATHER_TIME := 0.75 ## the Fragments spiral in
const RAI_UNMAKE_TIME := 1.3 ## the portrait evaporates
const RAI_AFTERMATH_TIME := 1.0 ## the last dust drifts off and the void lifts
const RAI_FRAGMENT_COUNT := 10
const RAI_ORBIT_RADIUS := 70.0 ## where the Fragments circle the portrait while it is unmade
const RAI_TRAIL_LENGTH := 12 ## points kept in each Fragment's trail
const RAI_LIGHT := Color(0.95, 0.88, 1.0)
const RAI_DUST_COUNT := 34
const RAI_PETAL_COUNT := 18
const RAI_PETAL_COLOR := Color(0.05, 0.03, 0.07)

static var _void_shader: Shader
static var _unmaking_shader: Shader

## The Main node that owns the table.
var host
var fx_library: FxLibrary

## Leaders (by uid) that were unmade whole: once dead they are not drawn again (Main._render_leader).
var unmade_leader_uids := { }

## Read-only mirror of Main's effects layer.
var fx: Control:
	get: return host.fx

func _init(host_node, library: FxLibrary) -> void:
	host = host_node
	fx_library = library

func has_style(style_name: String) -> bool:
	return style_name in STYLES

## Plays the execution `style_name` on `leader` from moment t. Returns the moment it is over (the Leader is dead by then).
func play(style_name: String, leader: LeaderView, leader_uid: int, hp_before: int, t: float, col: Color) -> float:
	match style_name:
		"rai":
			unmade_leader_uids[leader_uid] = true
			return _rai(leader, hp_before, t, col)
	return t

func _rai(leader: LeaderView, hp_before: int, t: float, col: Color) -> float:
	var center := fx_library.center_of(leader)
	var unmake_t := t + RAI_GATHER_TIME
	var gone_t := unmake_t + RAI_UNMAKE_TIME
	void_veil(center, col, t, gone_t)
	var driver := leader.create_tween()
	driver.tween_interval(t)
	driver.tween_callback(func(): _rai_unmake_card(leader, col, unmake_t - t))
	for i in RAI_FRAGMENT_COUNT:
		_rai_fragment_in(center, col, t, gone_t, TAU * i / RAI_FRAGMENT_COUNT)
	_rai_evaporation(leader, col, unmake_t)
	fx_library.drain_leader_hp(leader, hp_before, unmake_t)
	return gone_t + RAI_AFTERMATH_TIME

## The void over the whole screen (shaders/rai_void.gdshader): rises at t and quietly lifts (over `fade_time`)
## after gone_t. Also used by FxSummons.
func void_veil(center: Vector2, col: Color, t: float, gone_t: float, fade_time := RAI_AFTERMATH_TIME + 0.2) -> ColorRect:
	if _void_shader == null:
		_void_shader = load("res://scripts/ui/shaders/rai_void.gdshader")
	var to_screen := fx.get_global_transform_with_canvas()
	var screen := fx.get_viewport().get_visible_rect()
	var top_left: Vector2 = to_screen.affine_inverse() * screen.position
	var bottom_right: Vector2 = to_screen.affine_inverse() * screen.end
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0) # if the shader ever fails, nothing shows instead of a white screen
	veil.position = top_left - Vector2(40, 40)
	veil.size = bottom_right - top_left + Vector2(80, 80)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.z_index = 50
	var veil_material := ShaderMaterial.new()
	veil_material.shader = _void_shader
	veil_material.set_shader_parameter("aspect", veil.size.x / veil.size.y)
	veil_material.set_shader_parameter("focus", (center - veil.position) / veil.size)
	veil_material.set_shader_parameter("accent", col)
	veil_material.set_shader_parameter("veil", 0.0) # a tween only finds a shader parameter that was set once
	veil.material = veil_material
	fx.add_child(veil)
	var darkness := veil.create_tween()
	darkness.tween_interval(t)
	darkness.tween_property(veil_material, "shader_parameter/veil", 1.0, 0.5).from(0.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	darkness.tween_interval(gone_t - t - 0.5 - 0.2)
	darkness.tween_property(veil_material, "shader_parameter/veil", 0.0, fade_time).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	darkness.tween_callback(veil.queue_free)
	return veil

## The whole Leader (plate, HP gem, ability gem), captured as it is now, slowly turns, loses its color and
## evaporates (shaders/rai_unmaking.gdshader) until nothing of it is left. The real Leader is hidden at once
## and the picture takes its place.
func _rai_unmake_card(leader: LeaderView, col: Color, unmake_delay: float) -> void:
	if not is_instance_valid(leader):
		return
	var outlines := leader.whole_card_outlines()
	var all_points := PackedVector2Array()
	for outline in outlines:
		all_points.append_array(outline)
	var snapshot: Dictionary = host.fx_leader_death.snapshot_area(leader, all_points)
	var origin := leader.position
	leader.visible = false
	if snapshot.is_empty():
		return
	if _unmaking_shader == null:
		_unmaking_shader = load("res://scripts/ui/shaders/rai_unmaking.gdshader")
	var picture: ImageTexture = snapshot["picture"]
	var picture_point: Callable = snapshot["picture_point"]
	var picture_size := Vector2(picture.get_size())
	var unmaking := ShaderMaterial.new()
	unmaking.shader = _unmaking_shader
	unmaking.set_shader_parameter("pivot", picture_point.call(origin + LeaderView.PC) / picture_size)
	unmaking.set_shader_parameter("aspect", picture_size.x / picture_size.y)
	unmaking.set_shader_parameter("accent", col)
	unmaking.set_shader_parameter("twist", 0.0)
	unmaking.set_shader_parameter("unmake", 0.0)
	var card := Node2D.new()
	card.position = origin + LeaderView.PC
	card.z_index = 56
	for outline in outlines:
		var piece := Polygon2D.new()
		piece.texture = picture
		piece.material = unmaking
		var local_outline := PackedVector2Array()
		var picture_points := PackedVector2Array()
		for point in outline:
			local_outline.append(point - LeaderView.PC)
			picture_points.append(picture_point.call(origin + point))
		piece.polygon = local_outline
		piece.uv = picture_points
		card.add_child(piece)
	fx.add_child(card)
	var spin := card.create_tween()
	spin.tween_property(unmaking, "shader_parameter/twist", 0.35, unmake_delay).from(0.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	spin.tween_property(unmaking, "shader_parameter/twist", 1.0, RAI_UNMAKE_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	spin.tween_callback(card.queue_free)
	var evaporate := card.create_tween()
	evaporate.tween_interval(unmake_delay)
	evaporate.tween_property(unmaking, "shader_parameter/unmake", 1.0, RAI_UNMAKE_TIME).from(0.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	evaporate.parallel().tween_property(card, "position:y", card.position.y - 10.0, RAI_UNMAKE_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)

## While the Leader evaporates, dust motes and black petals come off it, the top first (as the shader
## eats it), and drift up and away, swaying, until they are gone.
func _rai_evaporation(leader: LeaderView, col: Color, unmake_t: float) -> void:
	var outlines := leader.whole_card_outlines()
	var bounds := Rect2(outlines[0][0], Vector2.ZERO)
	for outline in outlines:
		for point in outline:
			bounds = bounds.expand(point)
	var dust_color := RAI_LIGHT.lerp(col, 0.25).darkened(0.25)
	for i in RAI_DUST_COUNT + RAI_PETAL_COUNT:
		var spot := LeaderView.PC
		for attempt in 8:
			var candidate := bounds.position + Vector2(randf(), randf()) * bounds.size
			if _inside_any(candidate, outlines):
				spot = candidate
				break
		var height_share := (spot.y - bounds.position.y) / maxf(bounds.size.y, 1.0)
		var start_t := unmake_t + height_share * RAI_UNMAKE_TIME * 0.8 + randf_range(0.0, 0.15)
		var start := leader.position + spot
		if i < RAI_DUST_COUNT:
			drift(dust_mote(dust_color), start, start_t, false)
		else:
			drift(petal(col), start, start_t, true)

static func _inside_any(point: Vector2, outlines: Array) -> bool:
	for outline in outlines:
		if Geometry2D.is_point_in_polygon(point, outline):
			return true
	return false

## A soft round mote of ashen dust, medium sized.
func dust_mote(dust_color: Color) -> Node2D:
	var mote := Polygon2D.new()
	var radius := randf_range(2.5, 5.5)
	var points := PackedVector2Array()
	for corner in 10:
		points.append(Vector2.from_angle(TAU * corner / 10.0) * radius * randf_range(0.8, 1.1))
	mote.polygon = points
	mote.color = Color(dust_color, randf_range(0.55, 0.85))
	return mote

## A small black petal with a faint edge in the accent color, so it still reads over the dark void.
func petal(col: Color) -> Node2D:
	var petal := Node2D.new()
	var length := randf_range(9.0, 15.0)
	var width := length * randf_range(0.38, 0.5)
	var points := PackedVector2Array()
	for step in 9:
		var along := step / 8.0
		points.append(Vector2(lerpf(-length / 2.0, length / 2.0, along), -width / 2.0 * sin(PI * along) * (1.0 - 0.3 * along)))
	for step in range(7, 0, -1):
		var along := step / 8.0
		points.append(Vector2(lerpf(-length / 2.0, length / 2.0, along), width / 2.0 * 0.7 * sin(PI * along) * (1.0 - 0.3 * along)))
	var body := Polygon2D.new()
	body.polygon = points
	body.color = RAI_PETAL_COLOR
	petal.add_child(body)
	var edge := Line2D.new()
	edge.points = points
	edge.closed = true
	edge.width = 1.0
	edge.default_color = Color(col.lerp(RAI_LIGHT, 0.3), 0.45)
	petal.add_child(edge)
	petal.rotation = randf() * TAU
	return petal

## One mote or petal floats up and sideways from `start`, swaying (petals also tumble), and fades out.
func drift(particle: Node2D, start: Vector2, start_t: float, is_petal: bool) -> void:
	particle.position = start
	particle.z_index = 57
	particle.modulate.a = 0.0
	fx.add_child(particle)
	var life := randf_range(1.1, 1.6) if is_petal else randf_range(0.8, 1.2)
	var rise := randf_range(50.0, 95.0) if is_petal else randf_range(35.0, 70.0)
	var drift_side := randf_range(-45.0, 45.0)
	var sway := randf_range(6.0, 14.0) if is_petal else randf_range(2.0, 5.0)
	var sway_phase := randf() * TAU
	var spin := randf_range(-3.0, 3.0) if is_petal else 0.0
	var start_rotation := particle.rotation
	var float_step := func(progress: float):
		var eased := 1.0 - (1.0 - progress) * (1.0 - progress)
		var side := drift_side * eased + sin(sway_phase + progress * TAU * 1.3) * sway
		particle.position = start + Vector2(side, -rise * eased)
		particle.rotation = start_rotation + spin * progress
	var motion := particle.create_tween()
	motion.tween_interval(start_t)
	motion.tween_property(particle, "modulate:a", 1.0, 0.12)
	motion.parallel().tween_method(float_step, 0.0, 1.0, life)
	motion.parallel().tween_property(particle, "modulate:a", 0.0, life * 0.6).set_delay(life * 0.4)
	motion.tween_callback(particle.queue_free)

## A diamond of light with a soft glow around it: one Fragment of Rai.
func fragment_shape(col: Color, size: float) -> Node2D:
	var fragment := Node2D.new()
	fragment.z_index = 58
	fragment.add_child(fx_library._glow_sprite(size * 2.4, col))
	var diamond := Polygon2D.new()
	diamond.polygon = PackedVector2Array([Vector2(0, -size * 1.5), Vector2(size * 0.6, 0), Vector2(0, size * 1.5), Vector2(-size * 0.6, 0)])
	diamond.color = RAI_LIGHT
	diamond.material = fx_library._additive()
	fragment.add_child(diamond)
	return fragment

## One Fragment comes from far off at `start_angle`, spirals in and circles the portrait while it evaporates,
## closing in a little and fading out with it, leaving a fading trail of light behind.
func _rai_fragment_in(center: Vector2, col: Color, t: float, gone_t: float, start_angle: float) -> void:
	var fragment := fragment_shape(col, 7.0)
	fragment.modulate.a = 0.0
	fx.add_child(fragment)
	var trail := Line2D.new()
	trail.width = 5.0
	trail.z_index = 57
	trail.material = fx_library._additive()
	var trail_colors := Gradient.new()
	trail_colors.set_color(0, Color(col, 0.0))
	trail_colors.set_color(1, Color(col.lightened(0.3), 0.9))
	trail.gradient = trail_colors
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 0.1))
	taper.add_point(Vector2(1.0, 1.0))
	trail.width_curve = taper
	fx.add_child(trail)
	var start_radius := randf_range(430.0, 560.0)
	var total_time := gone_t - t
	var gather_share := RAI_GATHER_TIME / total_time
	var trail_holder := {"points": PackedVector2Array()} # a lambda cannot change a captured local, so the points live here
	var step := func(progress: float):
		var radius: float
		var angle: float
		if progress < gather_share:
			var gather := smoothstep(0.0, 1.0, progress / gather_share)
			radius = lerpf(start_radius, RAI_ORBIT_RADIUS, gather)
			angle = start_angle + gather * 2.6
		else:
			var unmake := (progress - gather_share) / (1.0 - gather_share)
			radius = RAI_ORBIT_RADIUS * (1.0 - 0.35 * unmake)
			angle = start_angle + 2.6 + unmake * 4.0
		var spot := center + Vector2.from_angle(angle) * radius
		fragment.position = spot
		fragment.rotation = angle
		var points: PackedVector2Array = trail_holder["points"]
		points.append(spot)
		if points.size() > RAI_TRAIL_LENGTH:
			points.remove_at(0)
		trail_holder["points"] = points
		trail.points = points
	var flight := fragment.create_tween()
	flight.tween_interval(t)
	flight.tween_property(fragment, "modulate:a", 1.0, 0.15)
	flight.parallel().tween_method(step, 0.0, 1.0, total_time)
	flight.parallel().tween_property(fragment, "modulate:a", 0.0, total_time * 0.45).set_delay(total_time * 0.55)
	flight.parallel().tween_property(trail, "modulate:a", 0.0, total_time * 0.45).set_delay(total_time * 0.55)
	flight.tween_callback(fragment.queue_free)
	flight.tween_callback(trail.queue_free)
