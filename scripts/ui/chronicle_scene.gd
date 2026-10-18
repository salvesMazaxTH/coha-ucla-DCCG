class_name ChronicleScene
extends Control
## The big "scene" panel that opens beside the Chronicle while a row is hovered (or tapped, on a phone).
## It replays the event with full-size cards: the card that acted on the left, a medallion with the kind
## of action (and the damage or healing) in the middle, the card(s) it hit on the right, and the whole
## sentence underneath. The row stays tiny; this is where the player actually reads what happened.

const PANEL_SIZE := Vector2(640, 404)
const SIDE_MARGIN := 40.0
const CARDS_TOP := 66.0
const SOURCE_CARD_SCALE := 1.5 ## 180 x 255 px
const MANY_TARGETS_CARD_SCALE := 1.2
const MAX_TARGETS_SHOWN := 3
const MEDALLION_RADIUS := 34.0
## Size of the shield with the life left after a hit or a heal (under the medallion).
const LIFE_GEM_RADIUS := 17.0
## Pixels the panel slides in from, and how long it takes.
const SLIDE_DISTANCE := 14.0
const SHOW_SECONDS := 0.14

var entry: Dictionary = {}
var accent := Color.WHITE
var side_color := Color.WHITE
var pointer_y := 0.0 ## height (inside the panel) of the row the panel points at
var _medallion_center := Vector2.ZERO
var _beam_from := Vector2.ZERO ## the beam goes from the acting card to the card it hit
var _beam_to := Vector2.ZERO
var _resting_x := 0.0
var _show_tween: Tween

func _init() -> void:
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func shown_seq() -> int:
	return int(entry.get("seq", -1)) if visible else -1

## Fills the panel with `data` (a Chronicle entry) and places it with its top-left at `top_left`.
## `row_center_y` is where the row sits on the stage, so the little pointer lines up with it.
func show_entry(data: Dictionary, ally: bool, top_left: Vector2, row_center_y: float) -> void:
	var same_event := visible and shown_seq() == int(data.get("seq", -2))
	entry = data
	accent = data.get("accent", ChronicleRow.NEUTRAL_COLOR)
	side_color = ChronicleRow.NEUTRAL_COLOR if int(data.get("actor", -1)) < 0 else (ChronicleRow.ALLY_COLOR if ally else ChronicleRow.ENEMY_COLOR)
	pointer_y = clampf(row_center_y - top_left.y, 30.0, PANEL_SIZE.y - 30.0)
	_resting_x = top_left.x
	position.y = top_left.y
	if not same_event:
		_build_contents()
	queue_redraw()
	if visible:
		position.x = _resting_x
		return
	visible = true
	move_to_front()
	modulate.a = 0.0
	position.x = _resting_x + SLIDE_DISTANCE
	if _show_tween:
		_show_tween.kill()
	_show_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_show_tween.tween_property(self, "modulate:a", 1.0, SHOW_SECONDS)
	_show_tween.tween_property(self, "position:x", _resting_x, SHOW_SECONDS)

func hide_scene() -> void:
	if _show_tween:
		_show_tween.kill()
	visible = false
	entry = {}

# ------------------------------------------------------------ building

func _build_contents() -> void:
	for child in get_children():
		child.queue_free()
	var source_id := String(entry.get("source_card_id", ""))
	var target_ids: Array = entry.get("target_card_ids", [])
	var source_size := CardView.BASE * SOURCE_CARD_SCALE
	var cards_middle_y := CARDS_TOP + source_size.y / 2.0
	var has_source := source_id != ""
	var has_targets := not target_ids.is_empty()

	if has_source and has_targets:
		var source_card := _add_card(source_id, Vector2(SIDE_MARGIN, CARDS_TOP), SOURCE_CARD_SCALE)
		var target_left := _add_targets(target_ids, PANEL_SIZE.x - SIDE_MARGIN)
		_beam_from = Vector2(source_card.position.x + source_card.size.x + 6, cards_middle_y)
		_beam_to = Vector2(target_left - 6, cards_middle_y)
		_medallion_center = Vector2((_beam_from.x + _beam_to.x) / 2.0, cards_middle_y)
	elif has_source:
		# nothing was hit: the card stands in the middle, the medallion beside it
		var lone_card := _add_card(source_id, Vector2(PANEL_SIZE.x / 2.0 - source_size.x / 2.0 - 50, CARDS_TOP), SOURCE_CARD_SCALE)
		_medallion_center = Vector2(lone_card.position.x + lone_card.size.x + 62, cards_middle_y)
		_beam_from = Vector2.ZERO
		_beam_to = Vector2.ZERO
	elif has_targets:
		# something happened TO a card with no card behind it (fatigue, a status ticking...)
		var right_edge := PANEL_SIZE.x / 2.0 + source_size.x / 2.0 + 50
		var target_left := _add_targets(target_ids, right_edge)
		_medallion_center = Vector2(target_left - 62, cards_middle_y)
		_beam_from = Vector2.ZERO
		_beam_to = Vector2.ZERO
	else:
		_medallion_center = Vector2(PANEL_SIZE.x / 2.0, cards_middle_y)
		_beam_from = Vector2.ZERO
		_beam_to = Vector2.ZERO

	var sentence := Label.new()
	sentence.text = String(entry.get("text", ""))
	sentence.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sentence.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sentence.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sentence.position = Vector2(28, CARDS_TOP + source_size.y + 12)
	sentence.size = Vector2(PANEL_SIZE.x - 56, PANEL_SIZE.y - sentence.position.y - 12)
	sentence.clip_text = true
	sentence.add_theme_font_override("font", UITheme.font("bold"))
	sentence.add_theme_font_size_override("font_size", 21)
	sentence.add_theme_color_override("font_color", UITheme.TEXT)
	sentence.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	sentence.add_theme_constant_override("outline_size", 4)
	sentence.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sentence)

## Lays the hit cards out from `right_edge` leftwards (fanned when there are several).
## Returns the x of the left edge of the group.
func _add_targets(target_ids: Array, right_edge: float) -> float:
	var shown_count := mini(MAX_TARGETS_SHOWN, target_ids.size())
	var card_scale := SOURCE_CARD_SCALE if shown_count == 1 else MANY_TARGETS_CARD_SCALE
	var card_size := CardView.BASE * card_scale
	var overlap_step := card_size.x * 0.42
	var group_width := card_size.x + overlap_step * (shown_count - 1)
	var left_x := right_edge - group_width
	var vertical_room := CardView.BASE.y * SOURCE_CARD_SCALE - card_size.y
	var target_dies: bool = entry.get("kind", "") in ["death", "destroy", "leader_executed"]
	for index in shown_count:
		var card_top := CARDS_TOP + vertical_room / 2.0 + (8.0 * (index - (shown_count - 1) / 2.0) if shown_count > 1 else 0.0)
		var card := _add_card(String(target_ids[index]), Vector2(left_x + overlap_step * index, card_top), card_scale)
		card.rotation_degrees = 0.0 if shown_count == 1 else (index - (shown_count - 1) / 2.0) * 4.0
		if target_dies:
			card.modulate = Color(0.55, 0.5, 0.58) # a dead card looks drained
	if target_ids.size() > shown_count:
		var more := Label.new()
		more.text = "+%d" % (target_ids.size() - shown_count)
		more.position = Vector2(right_edge - 46, CARDS_TOP - 8)
		more.size = Vector2(46, 26)
		more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		more.add_theme_font_override("font", UITheme.font("heavy"))
		more.add_theme_font_size_override("font_size", 18)
		more.add_theme_color_override("font_color", accent)
		more.add_theme_color_override("font_outline_color", Color.BLACK)
		more.add_theme_constant_override("outline_size", 5)
		more.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(more)
	return left_x

func _add_card(card_id: String, card_position: Vector2, card_scale: float) -> Control:
	var leader_id := ChronicleRow.leader_id_of(card_id)
	if leader_id != "":
		var portrait := LeaderPortrait.new().setup(leader_id, card_scale)
		portrait.position = card_position
		portrait.pivot_offset = portrait.size / 2.0
		add_child(portrait)
		return portrait
	if not CardDB.data().get("cards", {}).has(card_id):
		# an id the database doesn't know (should not happen): a plain framed box keeps the layout
		var placeholder := Panel.new()
		placeholder.size = CardView.BASE * card_scale
		placeholder.position = card_position
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(placeholder)
		return placeholder
	var card := CardView.new().setup(card_id, {}, card_scale)
	card.position = card_position
	card.pivot_offset = card.size / 2.0
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)
	return card

# ------------------------------------------------------------ drawing (behind the cards)

func _draw() -> void:
	if entry.is_empty():
		return
	var panel_rect := Rect2(Vector2.ZERO, PANEL_SIZE)
	var panel_style := UITheme.box(Color("#0e0b16", 0.97), 16, Color(accent, 0.7), 2, 28)
	draw_style_box(panel_style, panel_rect)
	# a soft light of the action's colour behind the cards
	for ring in 10:
		var ring_radius := 260.0 - ring * 22.0
		draw_circle(_medallion_center, ring_radius, Color(accent, 0.012 + ring * 0.004))
	# header: kind of action on the left, turn and who did it on the right
	draw_rect(Rect2(16, 14, 4, 26), accent)
	var title_font := UITheme.font("title_bold")
	draw_string(title_font, Vector2(28, 35), String(entry.get("label", "EVENTO")), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, accent)
	var who := "TURNO %d" % int(entry.get("turn", 0))
	if String(entry.get("actor_name", "")) != "":
		who += "  ·  " + String(entry["actor_name"]).to_upper()
	var who_width := title_font.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(title_font, Vector2(PANEL_SIZE.x - 22 - who_width, 32), who, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, side_color)
	draw_line(Vector2(16, 50), Vector2(PANEL_SIZE.x - 16, 50), Color(accent, 0.25), 1.0)
	# the little pointer on the right edge, aimed at the row in the list
	var tip := Vector2(PANEL_SIZE.x + 11, pointer_y)
	draw_colored_polygon(PackedVector2Array([Vector2(PANEL_SIZE.x - 1, pointer_y - 11), tip, Vector2(PANEL_SIZE.x - 1, pointer_y + 11)]), Color("#0e0b16"))
	draw_polyline(PackedVector2Array([Vector2(PANEL_SIZE.x, pointer_y - 11), tip, Vector2(PANEL_SIZE.x, pointer_y + 11)]), Color(accent, 0.7), 2.0, true)
	if _beam_to.x > _beam_from.x:
		_draw_beam()
	_draw_medallion()

## A glowing line from the acting card to the card it hit, with an arrow head.
func _draw_beam() -> void:
	for glow_width in [14.0, 8.0, 3.0]:
		var glow_alpha := 0.9 if glow_width < 4.0 else 0.12
		draw_line(_beam_from, _beam_to - Vector2(10, 0), Color(accent, glow_alpha), glow_width, true)
	draw_colored_polygon(PackedVector2Array([_beam_to, _beam_to + Vector2(-16, -10), _beam_to + Vector2(-16, 10)]), accent)

func _draw_medallion() -> void:
	draw_circle(_medallion_center, MEDALLION_RADIUS + 5, Color(0, 0, 0, 0.55))
	draw_circle(_medallion_center, MEDALLION_RADIUS, Color("#15111f"))
	draw_arc(_medallion_center, MEDALLION_RADIUS, 0, TAU, 48, accent, 3.0, true)
	draw_arc(_medallion_center, MEDALLION_RADIUS - 6, 0, TAU, 48, Color(accent, 0.3), 1.0, true)
	var glyph_font := UITheme.font("heavy")
	var glyph := String(entry.get("icon", "·"))
	var glyph_width := glyph_font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	draw_string(glyph_font, _medallion_center + Vector2(-glyph_width / 2.0, 12), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, accent)
	var amount := ChronicleRow.amount_text(entry)
	if amount == "":
		return
	var amount_color := ChronicleRow.HEAL_COLOR if int(entry["amount"]) > 0 else ChronicleRow.DAMAGE_COLOR
	var amount_width := glyph_font.get_string_size(amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 36).x
	var amount_position := _medallion_center + Vector2(-amount_width / 2.0, MEDALLION_RADIUS + 42)
	if entry.has("hp_after"):
		# the amount slides left to make room for an arrow and the life shield
		amount_position.x -= LIFE_GEM_RADIUS + 22
		var arrow_left := amount_position.x + amount_width + 10
		var arrow_y := amount_position.y - 12
		draw_line(Vector2(arrow_left, arrow_y), Vector2(arrow_left + 20, arrow_y), Color(UITheme.TEXT, 0.7), 3.0, true)
		draw_colored_polygon(PackedVector2Array([Vector2(arrow_left + 27, arrow_y), Vector2(arrow_left + 18, arrow_y - 6), Vector2(arrow_left + 18, arrow_y + 6)]), Color(UITheme.TEXT, 0.7))
		var gem_center := Vector2(arrow_left + 34 + LIFE_GEM_RADIUS, arrow_y + 1)
		ChronicleRow.draw_life_gem(self, gem_center, LIFE_GEM_RADIUS, int(entry["hp_after"]))
		var caption_font := UITheme.font("title_bold")
		var caption := "VIDA" if int(entry["hp_after"]) > 0 else "CAIU"
		var caption_width := caption_font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(caption_font, gem_center + Vector2(-caption_width / 2.0, LIFE_GEM_RADIUS + 20), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(UITheme.TEXT, 0.75))
	draw_string_outline(glyph_font, amount_position, amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, 8, Color(0, 0, 0, 0.95))
	draw_string(glyph_font, amount_position, amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, amount_color)

# ------------------------------------------------------------ the Leader's plaque

## The Leader is not a card on the board (its Incarnation is a different card): in the scene it gets
## a plaque of its own, the same size as a card, with the Leader's art, its essence colour, a
## "LÍDER" tag on top and its name below.
class LeaderPortrait extends Control:
	const TAG_HEIGHT := 22.0
	const BANNER_HEIGHT := 34.0

	var leader_card_id := ""
	var leader_name := ""
	var essence_color := Color.WHITE

	func setup(leader_id: String, card_scale: float) -> LeaderPortrait:
		var leader_data := CardDB.leader(leader_id)
		leader_card_id = ChronicleRow.LEADER_ID_PREFIX + leader_id
		leader_name = String(leader_data.get("name", ""))
		var essences: Array = leader_data.get("essences", [])
		if not essences.is_empty():
			essence_color = Color(CardDB.essence(String(essences[0]))["color"])
		size = CardView.BASE * card_scale
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		return self

	func _draw() -> void:
		draw_style_box(UITheme.box(Color("#120e1a"), 10, essence_color, 3, 14), Rect2(Vector2.ZERO, size))
		var art_rect := Rect2(Vector2(7, 7), size - Vector2(14, 14 + BANNER_HEIGHT))
		ChronicleRow.draw_card_art(self, leader_card_id, art_rect, essence_color)
		# "LÍDER" tag over the top edge of the art
		var tag_font := UITheme.font("heavy")
		var tag_width := tag_font.get_string_size("LÍDER", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 22
		var tag_rect := Rect2(Vector2((size.x - tag_width) / 2.0, 0), Vector2(tag_width, TAG_HEIGHT))
		draw_style_box(UITheme.box(essence_color.darkened(0.35), 6, Color(UITheme.GOLD, 0.9), 1), tag_rect)
		draw_string_outline(tag_font, tag_rect.position + Vector2(0, 16), "LÍDER", HORIZONTAL_ALIGNMENT_CENTER, tag_width, 14, 3, Color.BLACK)
		draw_string(tag_font, tag_rect.position + Vector2(0, 16), "LÍDER", HORIZONTAL_ALIGNMENT_CENTER, tag_width, 14, UITheme.GOLD)
		# name banner under the art
		var banner := Rect2(Vector2(7, size.y - 7 - BANNER_HEIGHT + 4), Vector2(size.x - 14, BANNER_HEIGHT - 4))
		draw_style_box(UITheme.box(essence_color.darkened(0.55), 5, Color(essence_color, 0.9), 1), banner)
		var name_font := UITheme.font("title_bold")
		var name_text := ChronicleRow.fit_text(leader_name, name_font, 19, banner.size.x - 10)
		draw_string_outline(name_font, banner.position + Vector2(5, 22), name_text, HORIZONTAL_ALIGNMENT_CENTER, banner.size.x - 10, 19, 4, Color.BLACK)
		draw_string(name_font, banner.position + Vector2(5, 22), name_text, HORIZONTAL_ALIGNMENT_CENTER, banner.size.x - 10, 19, UITheme.TEXT)
