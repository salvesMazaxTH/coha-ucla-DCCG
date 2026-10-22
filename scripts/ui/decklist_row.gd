class_name DecklistRow
extends Control
## One card of a deck list: a wide row whose background is the card's art, darkened from the left so the
## text stays readable. From left to right: the mana cost, the name with a line under it (kind, stats,
## essence), the rarity gem and the "x3" copy count. The deck's Encarnação gets a gold frame and a tag.
## Tapping the row (a press and release that barely moved, so scrolling the list never triggers it)
## emits `tapped`; Main answers with the same card overlay the match uses.

signal tapped(card_id: String)

const ROW_HEIGHT := 84.0
const COST_ORB_CENTER := Vector2(46.0, 42.0)
const COST_ORB_RADIUS := 25.0
const TEXT_LEFT := 90.0
const COUNT_PLAQUE_SIZE := Vector2(76.0, 50.0)
const RIGHT_MARGIN := 14.0
const GEM_RADIUS := 13.0
## How far (in pixels) a press may travel and still count as a tap.
const TAP_SLOP := 14.0

const COST_COLOR := Color("#2f6fd0")
const ENCARNATION_TAG := "ENCARNAÇÃO"
const KIND_NAMES := {"unit": "Unidade", "spell": "Feitiço", "artifact": "Artefato"}

var card_id := ""
var copies := 1
var is_incarnation := false
var accent := Color("#8a8f98") ## the card's first essence color

var _card: Dictionary = {}
var _subtitle := ""
var _press_position := Vector2.ZERO
var _pressing := false
var _hovered := false
var _gem_layer: Control ## champions only: a transparent layer on top that redraws the animated gem every frame
var _gem_time := 0.0

func setup(id: String, copy_count: int, incarnation: bool) -> DecklistRow:
	card_id = id
	copies = copy_count
	is_incarnation = incarnation
	_card = CardDB.card(id)
	accent = Color(String(CardDB.essence(CardDB.essences_of(_card)[0]).get("color", "#8a8f98")))
	_subtitle = _build_subtitle()
	custom_minimum_size = Vector2(300.0, ROW_HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# PASS: the list's ScrollContainer still sees the wheel and finger drags
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_entered.connect(func():
		_hovered = true
		queue_redraw())
	mouse_exited.connect(func():
		_hovered = false
		_pressing = false
		queue_redraw())
	if String(_card["rarity"]) == "champion":
		_add_champion_gem_layer()
	return self

## The champion gem shimmers, so it lives on its own layer: only that layer redraws each frame,
## not the whole row with its art.
func _add_champion_gem_layer() -> void:
	_gem_layer = Control.new()
	_gem_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gem_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gem_layer.draw.connect(func(): _draw_champion_gem(_gem_layer, _gem_center(_gem_layer.size), GEM_RADIUS, _gem_time))
	add_child(_gem_layer)

func _process(delta: float) -> void:
	if _gem_layer != null:
		_gem_time += delta
		_gem_layer.queue_redraw()

## "Unidade · 4/6 · Aquática" or "Feitiço · Ígnea / Glacial".
func _build_subtitle() -> String:
	var type := String(_card["type"])
	var parts: Array = [KIND_NAMES.get(type, type)]
	if type == "unit":
		parts.append("%d/%d" % [int(_card["atk"]), int(_card["hp"])])
	parts.append(CardDB.essence_names(_card))
	return " · ".join(parts)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressing = true
			_press_position = event.position
		elif _pressing:
			_pressing = false
			if event.position.distance_to(_press_position) <= TAP_SLOP:
				Sfx.play("ui_click")
				tapped.emit(card_id)
		queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	ChronicleRow.draw_card_art(self, card_id, rect, accent)
	_draw_readability_gradient(rect)
	if _hovered or _pressing:
		draw_rect(rect, Color(1, 1, 1, 0.10 if _pressing else 0.06))
	# a thick accent bar on the left edge, in the essence color
	draw_rect(Rect2(0.0, 0.0, 6.0, rect.size.y), accent)
	var frame_color := UITheme.GOLD_LIGHT if is_incarnation else Color(UITheme.GOLD, 0.45 if not _hovered else 0.9)
	draw_rect(rect.grow(-1.0), frame_color, false, 3.0 if is_incarnation else 2.0)
	_draw_cost_orb()
	_draw_names(rect)
	_draw_copy_count(rect)

## Dark on the left (where the text is), fading to almost clear on the right so the art shows.
func _draw_readability_gradient(rect: Rect2) -> void:
	var dark_left := Color(0.04, 0.035, 0.06, 0.94)
	var dark_middle := Color(0.04, 0.035, 0.06, 0.70)
	var clear_right := Color(0.04, 0.035, 0.06, 0.12)
	var middle_x := rect.size.x * 0.5
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(middle_x, 0), Vector2(middle_x, rect.size.y), Vector2(0, rect.size.y)]),
			PackedColorArray([dark_left, dark_middle, dark_middle, dark_left]))
	draw_polygon(PackedVector2Array([Vector2(middle_x, 0), Vector2(rect.size.x, 0), Vector2(rect.size.x, rect.size.y), Vector2(middle_x, rect.size.y)]),
			PackedColorArray([dark_middle, clear_right, clear_right, dark_middle]))

func _draw_cost_orb() -> void:
	draw_circle(COST_ORB_CENTER, COST_ORB_RADIUS + 3.0, Color(0, 0, 0, 0.85))
	draw_circle(COST_ORB_CENTER, COST_ORB_RADIUS, COST_COLOR.darkened(0.35))
	draw_circle(COST_ORB_CENTER - Vector2(0, 3), COST_ORB_RADIUS - 5.0, COST_COLOR)
	draw_arc(COST_ORB_CENTER, COST_ORB_RADIUS, 0.0, TAU, 32, Color(UITheme.GOLD_LIGHT, 0.8), 2.0, true)
	var cost_text := str(int(_card["cost"]))
	var font := UITheme.font("heavy")
	var text_width := font.get_string_size(cost_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 32).x
	draw_string_outline(font, COST_ORB_CENTER + Vector2(-text_width / 2.0, 11.0), cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, 5, Color(0, 0, 0, 0.8))
	draw_string(font, COST_ORB_CENTER + Vector2(-text_width / 2.0, 11.0), cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color.WHITE)

func _draw_names(rect: Rect2) -> void:
	var text_right := rect.size.x - RIGHT_MARGIN - COUNT_PLAQUE_SIZE.x - 50.0
	var available := text_right - TEXT_LEFT
	var name_font := UITheme.font("heavy")
	var name_text := ChronicleRow.fit_text(String(_card["name"]), name_font, 28, available)
	var name_position := Vector2(TEXT_LEFT, 40.0)
	draw_string_outline(name_font, name_position, name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, 6, Color(0, 0, 0, 0.85))
	draw_string(name_font, name_position, name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, UITheme.TEXT)
	var detail_font := UITheme.font("bold")
	var detail_text := ChronicleRow.fit_text(_subtitle, detail_font, 18, available)
	var detail_position := Vector2(TEXT_LEFT, 66.0)
	draw_string_outline(detail_font, detail_position, detail_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color(0, 0, 0, 0.85))
	draw_string(detail_font, detail_position, detail_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, accent.lightened(0.45))
	if is_incarnation:
		draw_string(detail_font, Vector2(TEXT_LEFT, 20.0), ENCARNATION_TAG, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.GOLD_LIGHT)

func _draw_copy_count(rect: Rect2) -> void:
	if _gem_layer == null: # champions get their animated gem from the layer on top
		_draw_rarity_gem(_gem_center(rect.size), GEM_RADIUS)
	var plaque := Rect2(Vector2(rect.size.x - RIGHT_MARGIN - COUNT_PLAQUE_SIZE.x, (rect.size.y - COUNT_PLAQUE_SIZE.y) / 2.0), COUNT_PLAQUE_SIZE)
	draw_style_box(UITheme.box(Color(0.05, 0.04, 0.08, 0.92), 10, UITheme.GOLD, 2), plaque)
	var count_text := "x%d" % copies
	var font := UITheme.font("heavy")
	var text_width := font.get_string_size(count_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 32).x
	draw_string(font, plaque.position + Vector2((plaque.size.x - text_width) / 2.0, 36.0), count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, UITheme.GOLD_LIGHT)

func _gem_center(row_size: Vector2) -> Vector2:
	return Vector2(row_size.x - RIGHT_MARGIN - COUNT_PLAQUE_SIZE.x - 26.0, row_size.y / 2.0)

## The same six-sided gem the card shows at the bottom of its frame (common, epic and legendary).
func _draw_rarity_gem(center: Vector2, radius: float) -> void:
	var gem_color := Color("#f2f2f2")
	match String(_card["rarity"]):
		"epic": gem_color = Color("#9b4fd6")
		"legendary": gem_color = Color("#ff8a1c")
	var outline := PackedVector2Array()
	for corner in [[0, -1.0], [0.85, -0.3], [0.85, 0.3], [0, 1.0], [-0.85, 0.3], [-0.85, -0.3]]:
		outline.append(center + Vector2(corner[0], corner[1]) * radius)
	draw_colored_polygon(outline, gem_color.darkened(0.4))
	draw_colored_polygon(PackedVector2Array([outline[0], outline[1], center, outline[5]]), gem_color.lightened(0.25))
	draw_colored_polygon(PackedVector2Array([outline[1], outline[2], outline[3], center]), gem_color)
	draw_colored_polygon(PackedVector2Array([outline[5], center, outline[3], outline[4]]), gem_color.darkened(0.2))
	draw_polyline(outline + PackedVector2Array([outline[0]]), Color(0, 0, 0, 0.8), 1.5, true)

## The champion gem as the card draws it (CardView._champion_gem): eight-sided, every facet cycling through
## the rainbow, a pulsing aura, a white glint sweeping across every few seconds and twinkling stars.
## `time` is in seconds.
func _draw_champion_gem(canvas: Control, center: Vector2, base_radius: float, time: float) -> void:
	var radius := base_radius * 1.2
	var outline := PackedVector2Array()
	for corner in [[0, -1.15], [0.6, -0.7], [1.0, 0], [0.6, 0.7], [0, 1.15], [-0.6, 0.7], [-1.0, 0], [-0.6, -0.7]]:
		outline.append(center + Vector2(corner[0], corner[1]) * radius)
	var pulse := 0.5 + 0.5 * sin(time * 3.0)
	canvas.draw_circle(center, radius * (1.9 + 0.2 * pulse), Color(1, 1, 1, 0.10 + 0.08 * pulse))
	canvas.draw_colored_polygon(_grown(outline, center, 1.25), Color("#07060a"))
	# one triangle per side, each with its own hue slowly rotating around the color wheel;
	# facets facing up-left are lighter, the ones facing down-right darker
	for side in outline.size():
		var hue := fposmod(time * 0.2 + side / float(outline.size()) * 0.6, 1.0)
		var facing_light := 0.5 + 0.5 * cos((float(side) - 6.5) / outline.size() * TAU)
		var facet_color := Color.from_hsv(hue, 0.8, 0.6 + 0.4 * facing_light)
		canvas.draw_colored_polygon(PackedVector2Array([outline[side], outline[(side + 1) % outline.size()], center]), facet_color)
	canvas.draw_polyline(outline + PackedVector2Array([outline[0]]), UITheme.GOLD, 1.0, true)
	# white glint: sweeps left to right once every 2.8 s, resting the rest of the cycle
	var sweep := fposmod(time, 2.8) / 0.9
	if sweep < 1.0:
		var band_x := lerpf(-1.4, 1.4, sweep) * radius
		var band := PackedVector2Array([center + Vector2(band_x - 0.35 * radius, -1.3 * radius), center + Vector2(band_x + 0.1 * radius, -1.3 * radius),
			center + Vector2(band_x - 0.1 * radius, 1.3 * radius), center + Vector2(band_x - 0.55 * radius, 1.3 * radius)])
		for piece in Geometry2D.intersect_polygons(band, outline):
			canvas.draw_colored_polygon(piece, Color(1, 1, 1, 0.75))
	canvas.draw_circle(center + Vector2(-radius * 0.3, -radius * 0.45), radius * 0.14, Color(1, 1, 1, 0.9))
	for star in [[Vector2(-1.5, -0.8), 0.0], [Vector2(1.5, -1.1), 2.1], [Vector2(0.9, -1.9), 4.2]]:
		var twinkle := maxf(0.0, sin(time * 4.0 + float(star[1])))
		if twinkle > 0.05:
			_draw_sparkle(canvas, center + Vector2(star[0]) * radius, radius * 0.55 * twinkle, Color(1, 1, 1, 0.5 + 0.5 * twinkle))

## Four-pointed star, `radius` from the center to each tip.
func _draw_sparkle(canvas: Control, center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for point_index in 8:
		var angle := point_index * TAU / 8.0 - PI / 2.0
		points.append(center + Vector2(cos(angle), sin(angle)) * (radius if point_index % 2 == 0 else radius * 0.25))
	canvas.draw_colored_polygon(points, color)

## The polygon scaled away from `center` by `factor`.
func _grown(points: PackedVector2Array, center: Vector2, factor: float) -> PackedVector2Array:
	var grown_points := PackedVector2Array()
	for point in points:
		grown_points.append(center + (point - center) * factor)
	return grown_points
