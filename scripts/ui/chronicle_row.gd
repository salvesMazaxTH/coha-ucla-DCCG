class_name ChronicleRow
extends Control
## One event in the in-game Chronicle list. The row is a small "tile": the art of the card that acted,
## a badge with the kind of action, a short title ("ATAQUE", "DANO"...), one line of prose and the art
## of the card it hit (with the damage or healing on top of it). Hovering or tapping the row asks Main
## to open the big ChronicleScene next to the list, where the whole event is shown with full cards.
## A "start of turn" event is drawn as a thin divider instead of a tile, so the turns read as chapters.

signal focused(row: ChronicleRow)

const ROW_HEIGHT := 50.0
const TURN_DIVIDER_HEIGHT := 28.0
const SOURCE_CHIP := Rect2(8, 5, 40, 40)
const TARGET_CHIP_SIZE := Vector2(30, 38)
const TEXT_LEFT := 56.0
## How long a new event glows after it shows up in the list.
const FRESH_GLOW_SECONDS := 1.1

## Card ids that start with this are Leaders ("leader:ronan"): their art comes from the Leaders list.
const LEADER_ID_PREFIX := "leader:"

const ALLY_COLOR := Color("#e8c25a")
const ENEMY_COLOR := Color("#e0566b")
const NEUTRAL_COLOR := Color("#8d849c")
const DAMAGE_COLOR := Color("#e8484a")
const HEAL_COLOR := Color("#3fcf74")

var entry: Dictionary = {}
var is_ally := true ## the event was done by the player looking at the screen
var is_active := false ## the big scene is open for this row right now
var _hovered := false
var _fresh_glow := 0.0 ## 1 when the row has just appeared, fading to 0

## `ally`: whether the viewer did it; `active`: the scene is showing it; `fresh`: it just happened.
func setup(data: Dictionary, ally: bool, active := false, fresh := false) -> ChronicleRow:
	entry = data
	is_ally = ally
	is_active = active
	_fresh_glow = 1.0 if fresh else 0.0
	var row_height := TURN_DIVIDER_HEIGHT if is_turn_divider() else ROW_HEIGHT
	custom_minimum_size = Vector2(0, row_height)
	size.y = row_height
	mouse_filter = Control.MOUSE_FILTER_PASS # the list behind still scrolls with wheel and drag
	if not is_turn_divider():
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return self

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	if _fresh_glow > 0.0:
		var glow_tween := create_tween()
		glow_tween.tween_method(_set_fresh_glow, 1.0, 0.0, FRESH_GLOW_SECONDS).set_ease(Tween.EASE_OUT)

func is_turn_divider() -> bool:
	return entry.get("kind", "") == "start_turn"

func set_active(active: bool) -> void:
	is_active = active
	queue_redraw()

func _set_fresh_glow(value: float) -> void:
	_fresh_glow = value
	queue_redraw()

func _on_mouse_entered() -> void:
	_hovered = true
	queue_redraw()
	if not is_turn_divider():
		focused.emit(self)

func _on_mouse_exited() -> void:
	_hovered = false
	queue_redraw()

## A tap on a phone may not move the "mouse" onto the row first, so a press also opens the scene.
func _gui_input(event: InputEvent) -> void:
	if is_turn_divider():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		focused.emit(self)

## Colour of whoever did the event: gold for the viewer, red for the opponent.
func side_color() -> Color:
	if int(entry.get("actor", -1)) < 0:
		return NEUTRAL_COLOR
	return ALLY_COLOR if is_ally else ENEMY_COLOR

func _draw() -> void:
	if is_turn_divider():
		_draw_turn_divider()
	else:
		_draw_event_tile()

func _draw_turn_divider() -> void:
	var font := UITheme.font("title_bold")
	var font_size := 11
	var title := "TURNO %d" % int(entry.get("turn", 0))
	var actor_name := String(entry.get("actor_name", ""))
	if actor_name != "":
		title += " · " + actor_name.to_upper()
	var title_width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var middle := Vector2(size.x / 2.0, size.y / 2.0 + 1.0)
	var line_color := Color(side_color(), 0.45)
	draw_line(Vector2(6, middle.y), Vector2(middle.x - title_width / 2.0 - 10, middle.y), line_color, 1.0)
	draw_line(Vector2(middle.x + title_width / 2.0 + 10, middle.y), Vector2(size.x - 6, middle.y), line_color, 1.0)
	for diamond_x in [middle.x - title_width / 2.0 - 6, middle.x + title_width / 2.0 + 6]:
		_draw_diamond(Vector2(diamond_x, middle.y), 3.0, side_color())
	draw_string(font, Vector2(middle.x - title_width / 2.0, middle.y + 4), title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(side_color(), 0.95))

func _draw_event_tile() -> void:
	var accent: Color = entry.get("accent", NEUTRAL_COLOR)
	var tile := Rect2(0, 1, size.x, size.y - 2)
	var highlighted := _hovered or is_active

	# background: dark lacquer, lighter while pointed at; a coloured edge says whose action it was
	var background := Color("#1c1729") if highlighted else Color("#110e19", 0.94)
	draw_rect(tile, background)
	if _fresh_glow > 0.0:
		draw_rect(tile, Color(accent, 0.22 * _fresh_glow))
	draw_rect(Rect2(tile.position, Vector2(3, tile.size.y)), side_color())
	if highlighted:
		draw_rect(tile.grow(-0.5), Color(accent, 0.85), false, 1.0)
	else:
		draw_line(Vector2(3, tile.end.y), Vector2(tile.end.x, tile.end.y), Color(1, 1, 1, 0.05), 1.0)

	# the card that acted, with a round badge showing the kind of action
	var source_id := String(entry.get("source_card_id", ""))
	if source_id != "":
		draw_card_art(self, source_id, SOURCE_CHIP, accent)
	else:
		_draw_glyph_chip(SOURCE_CHIP, String(entry.get("icon", "·")), accent)
	_draw_action_badge(SOURCE_CHIP.end - Vector2(1, 1), accent)

	# the card(s) it hit, on the right, with the damage or healing stamped on top
	var target_ids: Array = entry.get("target_card_ids", [])
	var text_right := size.x - 8.0
	if not target_ids.is_empty():
		var target_rect := Rect2(Vector2(size.x - TARGET_CHIP_SIZE.x - 7, (size.y - TARGET_CHIP_SIZE.y) / 2.0), TARGET_CHIP_SIZE)
		if entry.has("hp_after"):
			target_rect.position.x -= 5 # room for the life shield sticking out of the right edge
		if target_ids.size() > 1:
			# a second card peeks out behind the first one
			draw_card_art(self, String(target_ids[1]), Rect2(target_rect.position + Vector2(-7, -2), target_rect.size), accent, 0.55)
		draw_card_art(self, String(target_ids[0]), target_rect, accent)
		if target_ids.size() > 2:
			_draw_count_pill(target_rect.position + Vector2(2, 4), "+%d" % (target_ids.size() - 1), accent)
		if entry.has("hp_after"):
			# the damage stamp on the upper-left corner, the life that was left on the lower-right
			# corner: both stick out of the picture so the art stays visible in the middle
			_draw_amount_stamp(target_rect.position + Vector2(3, 9))
			draw_life_gem(self, target_rect.end + Vector2(0, -7), 9.0, int(entry["hp_after"]))
		else:
			_draw_amount_stamp(target_rect.get_center() + Vector2(0, 8))
		text_right = target_rect.position.x - (14.0 if target_ids.size() > 1 else 7.0)

	# title of the action and one line of prose (the whole sentence is in the big scene)
	var text_width := maxf(20.0, text_right - TEXT_LEFT)
	var title_font := UITheme.font("title_bold")
	var title := String(entry.get("label", "EVENTO"))
	if target_ids.is_empty() and int(entry.get("amount", 0)) != 0:
		title += "  " + amount_text(entry)
	draw_string(title_font, Vector2(TEXT_LEFT, 20), fit_text(title, title_font, 10, text_width), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, accent)
	var body_font := UITheme.font("body")
	var body := fit_text(String(entry.get("text", "")), body_font, 13, text_width)
	draw_string(body_font, Vector2(TEXT_LEFT, 38), body, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT if highlighted else Color(UITheme.TEXT, 0.82))

func _draw_action_badge(center: Vector2, accent: Color) -> void:
	draw_circle(center, 9.0, Color("#0b0a10"))
	draw_arc(center, 9.0, 0, TAU, 24, accent, 1.5, true)
	var font := UITheme.font("heavy")
	var glyph := String(entry.get("icon", "·"))
	var glyph_width := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(font, center + Vector2(-glyph_width / 2.0, 4), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, accent)

## The damage ("−3") or healing ("+2") drawn as a small round stamp over the target.
func _draw_amount_stamp(center: Vector2) -> void:
	if int(entry.get("amount", 0)) == 0:
		return
	var stamp_color := HEAL_COLOR if int(entry["amount"]) > 0 else DAMAGE_COLOR
	draw_circle(center, 10.0, stamp_color)
	draw_arc(center, 10.0, 0, TAU, 24, Color(0, 0, 0, 0.7), 1.5, true)
	var font := UITheme.font("heavy")
	var text := amount_text(entry)
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string_outline(font, center + Vector2(-text_width / 2.0, 4.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.6))
	draw_string(font, center + Vector2(-text_width / 2.0, 4.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

func _draw_glyph_chip(rect: Rect2, glyph: String, accent: Color) -> void:
	draw_rect(rect, Color(accent, 0.1))
	draw_rect(rect, Color(accent, 0.55), false, 1.0)
	var font := UITheme.font("heavy")
	var glyph_width := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	draw_string(font, rect.get_center() + Vector2(-glyph_width / 2.0, 7), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, accent)

func _draw_count_pill(center: Vector2, text: String, accent: Color) -> void:
	draw_circle(center, 8, Color("#090811"))
	draw_arc(center, 8, 0, TAU, 20, accent, 1.0, true)
	var font := UITheme.font("heavy")
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	draw_string(font, center + Vector2(-text_width / 2.0, 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE)

func _draw_diamond(center: Vector2, half: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -half), center + Vector2(half, 0), center + Vector2(0, half), center + Vector2(-half, 0)]), color)

# ------------------------------------------------------------ shared with ChronicleScene

## The life a card or Leader was left with, drawn like the HP shield on the cards (green, gold rim).
## At 0 the shield turns red: that hit was lethal.
static func draw_life_gem(canvas: CanvasItem, center: Vector2, radius: float, life: int) -> void:
	var fill_color := CardView.HP_COL if life > 0 else DAMAGE_COLOR
	var outline := PackedVector2Array()
	for corner in [[-0.9, -0.88], [0.9, -0.88], [0.92, 0.08], [0, 1.02], [-0.92, 0.08]]:
		outline.append(center + Vector2(corner[0], corner[1]) * radius)
	var rim := PackedVector2Array()
	var shadow := PackedVector2Array()
	for point in outline:
		rim.append(center + (point - center) * 1.18)
		shadow.append(center + (point - center) * 1.22 + Vector2(0, 1.5))
	canvas.draw_colored_polygon(shadow, Color(0, 0, 0, 0.6))
	canvas.draw_colored_polygon(rim, UITheme.GOLD)
	canvas.draw_colored_polygon(outline, fill_color.darkened(0.15))
	var font := UITheme.font("heavy")
	var font_size := int(radius * 1.35)
	var text := str(life)
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var text_position := Vector2(center.x - text_width / 2.0, center.y + font_size * 0.3)
	canvas.draw_string_outline(font, text_position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, maxi(3, font_size / 4), Color(0, 0, 0, 0.9))
	canvas.draw_string(font, text_position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

## "−3" for damage, "+2" for healing, "" when the event has no amount.
static func amount_text(data: Dictionary) -> String:
	var amount := int(data.get("amount", 0))
	if amount == 0:
		return ""
	return ("+%d" if amount > 0 else "−%d") % absi(amount)

## Draws a card's art filling `rect`, cropped like a portrait (keeps the upper part, where faces are).
## The Leader's id inside a "leader:<id>" card id, or "" for an ordinary card.
static func leader_id_of(card_id: String) -> String:
	if not card_id.begins_with(LEADER_ID_PREFIX):
		return ""
	var leader_id := card_id.trim_prefix(LEADER_ID_PREFIX)
	return leader_id if CardDB.data().get("leaders", {}).has(leader_id) else ""

## Art file of a card or of a Leader ("" when unknown).
static func art_file_of(card_id: String) -> String:
	var leader_id := leader_id_of(card_id)
	if leader_id != "":
		return String(CardDB.leader(leader_id).get("art", ""))
	if card_id != "" and CardDB.data().get("cards", {}).has(card_id):
		return String(CardDB.card(card_id).get("art", ""))
	return ""

static func draw_card_art(canvas: CanvasItem, card_id: String, rect: Rect2, accent: Color, opacity := 1.0) -> void:
	var art_texture: Texture2D = null
	var art_file := art_file_of(card_id)
	if art_file != "":
		art_texture = CardView.texture(art_file)
	if art_texture != null:
		# Leader portraits are tall with the face near the top, so their crop leans higher
		var is_leader := leader_id_of(card_id) != ""
		var crop_height := 0.08 if is_leader else 0.3
		# a card's own "art_crop" (set for its card window) keeps the face in frame here too
		var card_crop: Dictionary = {} if is_leader else CardDB.card(card_id).get("art_crop", {})
		var region := CardView.art_source_rect(art_texture.get_size(), rect.size, card_crop, 0.5, crop_height)
		canvas.draw_texture_rect_region(art_texture, rect, region, Color(1, 1, 1, opacity))
	else:
		canvas.draw_rect(rect, Color(accent, 0.16 * opacity))
	canvas.draw_rect(rect, Color(0, 0, 0, 0.8 * opacity), false, 2.0)
	canvas.draw_rect(rect.grow(-1.0), Color(accent, 0.75 * opacity), false, 1.0)

## Cuts `text` with "…" so it fits in `max_width` pixels.
static func fit_text(text: String, font: Font, font_size: int, max_width: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
		return text
	var clipped := text
	while clipped.length() > 1 and font.get_string_size(clipped + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
		clipped = clipped.left(clipped.length() - 1)
	return clipped + "…"
