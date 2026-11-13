class_name FxLeaderDeath
extends RefCounted
## What the table shows when a Leader dies, right before the victory / defeat / draw screen.
## Almost always (99%) it is the "burst": the top half of the Leader's portrait blows apart into a few big,
## irregular, heavy shards, leaving a jagged edge behind. The other 1% belongs to `alternatives`: other
## death animations can be registered there later (register_variant) and are picked without touching the animator.

const DEFAULT_VARIANT := "burst"
const ALTERNATIVE_CHANCE := 0.01
const SHARD_SEED_COUNT := 7 ## few shards, so each one is big
const SEED_MIN_DISTANCE := 30.0
const SEED_MAX_WEIGHT := 700.0 ## a bigger weight makes a bigger shard (the seeds are not equal)
const MIN_SHARD_AREA := 60.0
const FLIGHT_TIME := 1.1
const GRAVITY := 1100.0 ## heavy: they fall hard and do not fly far
const BURST_LENGTH := 1.3 ## from the burst until the result screen may show
const SHAKE_STRENGTH := 9.0
const SHAKE_TIME := 0.55
const FLASH_COLOR := Color(1.0, 0.92, 0.8)

## The Main node that owns the table.
var host
var fx_library: FxLibrary
## Other death animations by name: a Callable (leader_view, t) -> seconds until the result screen may show.
var alternatives := { }

## Read-only mirror of Main's effects layer.
var fx: Control:
	get: return host.fx

func _init(host_node, library: FxLibrary) -> void:
	host = host_node
	fx_library = library

func register_variant(variant_name: String, animation: Callable) -> void:
	alternatives[variant_name] = animation

## `roll` is a number from 0 to 1 (random unless a test passes one).
func pick_variant(roll := randf()) -> String:
	if not alternatives.is_empty() and roll < ALTERNATIVE_CHANCE:
		var variant_names := alternatives.keys()
		return variant_names[randi() % variant_names.size()]
	return DEFAULT_VARIANT

## Plays the death animation at moment t. Returns how many seconds after t the result screen may show.
func play(leader_view: LeaderView, t: float) -> float:
	var variant := pick_variant()
	if alternatives.has(variant):
		return alternatives[variant].call(leader_view, t)
	return burst(leader_view, t)

func burst(leader_view: LeaderView, t: float) -> float:
	var center := fx_library.center_of(leader_view) + Vector2(0.0, 20.0)
	var color := leader_view.elem_color
	var driver := leader_view.create_tween()
	driver.tween_interval(t)
	driver.tween_callback(func(): _break_top_half(leader_view))
	_flash(center, t)
	fx_library.spawn_embers(center, t, color, 26)
	fx_library.spawn_embers(center, t + 0.04, FLASH_COLOR, 10)
	var rest_position: Vector2 = host.position
	var shake_driver: Tween = host.create_tween()
	shake_driver.tween_interval(t)
	shake_driver.tween_method(fx_library._apply_screen_trauma.bind(rest_position, SHAKE_STRENGTH), 0.0, 1.0, SHAKE_TIME)
	shake_driver.tween_callback(func(): host.position = rest_position)
	return BURST_LENGTH

func _flash(center: Vector2, t: float) -> void:
	var glow := fx_library._glow_sprite(120.0, FLASH_COLOR)
	glow.position = center
	glow.modulate.a = 0.0
	glow.z_index = 57
	fx.add_child(glow)
	var tween := glow.create_tween()
	tween.tween_interval(t)
	tween.tween_property(glow, "modulate:a", 1.0, 0.04)
	tween.tween_property(glow, "modulate:a", 0.0, 0.3)
	tween.tween_callback(glow.queue_free)

## The moment of the burst: the portrait as it is on screen turns into shards and the real top half goes away.
## Without a screen to read (headless) the top half just goes away.
func _break_top_half(leader_view: LeaderView) -> void:
	if not is_instance_valid(leader_view):
		return
	var screen_image := fx.get_viewport().get_texture().get_image()
	var outline := leader_view.top_piece_outline()
	var origin := leader_view.position
	leader_view.top_destroyed = true
	if screen_image == null or screen_image.is_empty():
		return
	var to_canvas: Transform2D = fx.get_global_transform_with_canvas()
	var pixels_per_unit: float = float(screen_image.get_width()) / fx.get_viewport().get_visible_rect().size.x
	var piece_rect := Rect2(origin + outline[0], Vector2.ZERO)
	for point in outline:
		piece_rect = piece_rect.expand(origin + point)
	var corner_a: Vector2 = to_canvas * piece_rect.position * pixels_per_unit
	var corner_b: Vector2 = to_canvas * piece_rect.end * pixels_per_unit
	var wanted := Rect2i(Vector2i(corner_a.floor()), Vector2i((corner_b - corner_a).ceil())).intersection(Rect2i(Vector2i.ZERO, screen_image.get_size()))
	if wanted.size.x < 4 or wanted.size.y < 4:
		return
	var picture := ImageTexture.create_from_image(screen_image.get_region(wanted))
	var random := RandomNumberGenerator.new()
	random.randomize()
	var burst_center := origin + LeaderView.PC + Vector2(0.0, 20.0)
	var shards := Node2D.new()
	shards.z_index = 56
	fx.add_child(shards)
	var flights: Array = [] # per shard: [node, start position, velocity, spin]
	for polygon in split_into_shards(outline, random):
		var centroid := Vector2.ZERO
		for point in polygon:
			centroid += point
		centroid /= polygon.size()
		var shard := Polygon2D.new()
		shard.texture = picture
		shard.position = origin + centroid
		var local_outline := PackedVector2Array()
		var picture_points := PackedVector2Array()
		for point in polygon:
			local_outline.append(point - centroid)
			picture_points.append(to_canvas * (origin + point) * pixels_per_unit - Vector2(wanted.position))
		shard.polygon = local_outline
		shard.uv = picture_points
		var edge := Line2D.new()
		edge.points = local_outline
		edge.closed = true
		edge.width = 1.6
		edge.default_color = Color(0.05, 0.03, 0.03, 0.7)
		shard.add_child(edge)
		shards.add_child(shard)
		# the bigger the shard, the heavier: it is thrown less and spins less
		var weight := clampf(sqrt(polygon_area(polygon)) / 35.0, 0.7, 2.0)
		var outward := (origin + centroid - burst_center).normalized()
		var velocity := outward * random.randf_range(60.0, 170.0) / weight + Vector2(0.0, -random.randf_range(140.0, 300.0) / weight)
		flights.append([shard, shard.position, velocity, random.randf_range(-2.5, 2.5) / weight])
	var fly_shards := func(elapsed: float):
		for entry in flights:
			var shard_node: Polygon2D = entry[0]
			shard_node.position = entry[1] + entry[2] * elapsed + Vector2(0.0, GRAVITY * elapsed * elapsed * 0.5)
			shard_node.rotation = entry[3] * elapsed
		shards.modulate.a = clampf((FLIGHT_TIME - elapsed) / (FLIGHT_TIME * 0.35), 0.0, 1.0)
	var flight := shards.create_tween()
	flight.tween_method(fly_shards, 0.0, FLIGHT_TIME, FLIGHT_TIME)
	flight.tween_callback(shards.queue_free)

## Cuts `outline` into irregular pieces: a few random points inside it, each with its own weight, and every
## piece is the part of the outline closest to its point (a heavier point claims more room).
static func split_into_shards(outline: PackedVector2Array, random: RandomNumberGenerator) -> Array:
	var bounds := Rect2(outline[0], Vector2.ZERO)
	for point in outline:
		bounds = bounds.expand(point)
	var seeds: Array[Vector2] = []
	var tries := 0
	while seeds.size() < SHARD_SEED_COUNT and tries < 400:
		tries += 1
		var candidate := Vector2(random.randf_range(bounds.position.x, bounds.end.x), random.randf_range(bounds.position.y, bounds.end.y))
		if not Geometry2D.is_point_in_polygon(candidate, outline):
			continue
		var far_enough := true
		for other in seeds:
			if other.distance_to(candidate) < SEED_MIN_DISTANCE:
				far_enough = false
				break
		if far_enough:
			seeds.append(candidate)
	var weights: Array[float] = []
	for i in seeds.size():
		weights.append(random.randf_range(0.0, SEED_MAX_WEIGHT))
	var shards: Array = []
	for i in seeds.size():
		var pieces: Array = [outline]
		for j in seeds.size():
			if j == i:
				continue
			var half_plane := _half_plane(seeds[i], seeds[j], weights[i], weights[j])
			var clipped: Array = []
			for piece in pieces:
				clipped.append_array(Geometry2D.intersect_polygons(piece, half_plane))
			pieces = clipped
		for piece in pieces:
			if polygon_area(piece) >= MIN_SHARD_AREA:
				shards.append(piece)
	return shards

## A huge rectangle covering everything on seed_a's side of the line that separates it from seed_b.
static func _half_plane(seed_a: Vector2, seed_b: Vector2, weight_a: float, weight_b: float) -> PackedVector2Array:
	var axis := seed_b - seed_a
	var normal := axis.normalized()
	var boundary := (seed_a + seed_b) / 2.0 + axis * (weight_a - weight_b) / (2.0 * axis.length_squared())
	var tangent := normal.rotated(PI / 2.0)
	var reach := 1000.0
	return PackedVector2Array([
		boundary + tangent * reach,
		boundary - tangent * reach,
		boundary - tangent * reach - normal * reach,
		boundary + tangent * reach - normal * reach,
	])

static func polygon_area(polygon: PackedVector2Array) -> float:
	var twice_area := 0.0
	for i in polygon.size():
		var next_point := polygon[(i + 1) % polygon.size()]
		twice_area += polygon[i].x * next_point.y - next_point.x * polygon[i].y
	return absf(twice_area) / 2.0
