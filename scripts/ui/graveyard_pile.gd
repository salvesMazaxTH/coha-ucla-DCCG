class_name GraveyardPile
extends Control
## A graveyard drawn as a physical pile, the way it sits on a real TCG table: the last card that
## went in lies face up on top (a little dimmed, it is out of play), a couple of card edges peek
## out under it, and a small plate at the front shows a tombstone and how many cards are inside.
## Empty: a faint card outline with the tombstone. Tap/click it to open the graveyard.
## When a Réquiem spell can be cast from inside, it glows with the playable-card green.

signal clicked

const CORNER := 4
const EDGE_COLOR := Color("#2a2438")
const DIMMED := Color(0.78, 0.78, 0.82) ## the top card is out of play: a bit darker than a live card
const BADGE_SIZE := Vector2(52, 26)

var card_scale := LeaderView.DECK_CARD_SCALE
var count := 0
var requiem := 0 ## Réquiem spells castable from in here right now
var _hovered := false
var _glow_time := 0.0
var _badge: Badge

## `top_card_id`/`top_instance`: the last card that went in ("" when the graveyard is empty).
func setup(graveyard_count: int, top_card_id: String, top_instance: Dictionary, castable_requiem: int, scale_of_cards: float) -> GraveyardPile:
	count = graveyard_count
	requiem = castable_requiem
	card_scale = scale_of_cards
	var card_size := card_size_on_screen()
	size = card_size + Vector2(0, BADGE_SIZE.y / 2.0) # the badge hangs a little below the card
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if count > 0 and top_card_id != "":
		var top_card := CardView.new().setup(top_card_id, top_instance, card_scale)
		top_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_card.modulate = DIMMED
		add_child(top_card)
	_badge = Badge.new()
	_badge.pile = self
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.size = BADGE_SIZE
	_badge.position = Vector2((card_size.x - BADGE_SIZE.x) / 2.0, card_size.y - BADGE_SIZE.y / 2.0 - 2.0)
	add_child(_badge)
	mouse_entered.connect(func(): _set_hovered(true))
	mouse_exited.connect(func(): _set_hovered(false))
	set_process(requiem > 0)
	return self

func card_size_on_screen() -> Vector2:
	return CardView.BASE * card_scale

## Center of the top card, in this node's coordinates: milled and dying cards land here.
func top_center() -> Vector2:
	return card_size_on_screen() / 2.0

func _set_hovered(on: bool) -> void:
	_hovered = on
	queue_redraw()
	_badge.queue_redraw()

func _process(delta: float) -> void:
	_glow_time += delta
	queue_redraw()

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			clicked.emit()
		accept_event()

func _draw() -> void:
	var card_rect := Rect2(Vector2.ZERO, card_size_on_screen())
	if requiem > 0:
		# same "playable" green as the hand cards: a Réquiem spell can be cast from in here
		var glow_pulse := 0.5 + 0.5 * sin(_glow_time * 4.0)
		for i in 4:
			var glow_color := Color(LeaderView.READY_GLOW, (0.85 - i * 0.2) * (0.65 + 0.35 * glow_pulse))
			draw_style_box(UITheme.box(Color(0, 0, 0, 0), CORNER + 2 + i * 2, glow_color, 2), card_rect.grow(2.0 + i * 2.0))
	if count <= 0:
		draw_style_box(UITheme.box(Color(0, 0, 0, 0.35), CORNER, Color(UITheme.TEXT, 0.22), 1), card_rect)
		LeaderView.draw_tombstone_icon(self, card_rect.get_center(), Color(UITheme.TEXT, 0.3))
		return
	# soft shadow on the table
	for i in 5:
		var shadow := card_rect.grow(1.0 + i * 1.6)
		shadow.position += Vector2(2.5, 3.5)
		draw_style_box(UITheme.box(Color(0, 0, 0, 0.08), CORNER + i * 2, Color(0, 0, 0, 0), 0), shadow)
	# the cards under the top one, slightly out of line: it reads as a pile, not a single card
	var cards_under := mini(count - 1, 2)
	for i in cards_under:
		var offset := Vector2(2.0 + i * 1.5, 2.0 + i * 1.5) * (1.0 if i % 2 == 0 else -1.0)
		draw_style_box(UITheme.box(EDGE_COLOR, CORNER, Color(UITheme.GOLD_DARK, 0.5), 1), Rect2(card_rect.position + offset, card_rect.size))
	if _hovered:
		draw_style_box(UITheme.box(Color(0, 0, 0, 0), CORNER + 2, Color(UITheme.GOLD, 0.9), 2), card_rect.grow(3.0))

## The plate in front of the pile: tombstone + count (+ the castable Réquiem count, when there is one).
class Badge extends Control:
	var pile: GraveyardPile

	func _draw() -> void:
		var plate := Rect2(Vector2.ZERO, size)
		var hot := pile._hovered
		draw_style_box(UITheme.box(Color(UITheme.GOLD_DARK, 0.6) if hot else Color("#120e22"), 6, Color(UITheme.GOLD, 0.95 if hot else 0.6), 2), plate)
		var ink := Color(UITheme.GOLD_LIGHT, 0.95) if hot else Color(UITheme.TEXT, 0.8)
		LeaderView.draw_tombstone_icon(self, Vector2(13, size.y / 2.0), ink)
		var font := UITheme.font("heavy")
		var text := str(pile.count)
		var baseline := Vector2(25, size.y / 2.0 + 6.5)
		draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color(0, 0, 0, 0.8))
		draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UITheme.TEXT)
		if pile.requiem > 0:
			var corner := Vector2(size.x - 2, 2)
			draw_circle(corner, 11, Color(0, 0, 0, 0.85))
			draw_circle(corner, 9, LeaderView.READY_GLOW.darkened(0.35))
			draw_arc(corner, 9, 0, TAU, 24, LeaderView.READY_GLOW.lightened(0.3), 1.5, true)
			draw_string(font, corner + Vector2(-5, 6), str(pile.requiem), HORIZONTAL_ALIGNMENT_LEFT, 10, 15, Color.WHITE)
