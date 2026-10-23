class_name DecklistView
extends Control
## A deck's list as a full-screen window, opened from the deck selection hub. The header shows the deck
## name, its Leader, how many cards of each type it has and a mana curve. Below it every card is one
## wide row (DecklistRow): the card's art as the background, its cost, name, kind and "x3" copy count.
## Tapping a row asks Main to open the very same card overlay the match uses (signal `card_chosen`).

signal card_chosen(card_id: String)
signal closed

const WINDOW_MAX_WIDTH := 1360.0
const WINDOW_HEIGHT := 940.0
const WINDOW_MARGIN := 28.0
const ROW_GAP := 10.0
const COLUMN_COUNT := 2
const CURVE_MAX_COST := 7 ## costs above this are counted in the last bar ("7+")
const CURVE_BAR_WIDTH := 34.0
const CURVE_HEIGHT := 92.0

const TYPE_NAMES := {"unit": "Unidades", "spell": "Feitiços", "artifact": "Artefatos"}

var deck_id := ""
var scroll: ScrollContainer

## `stage_size` is the size of the stage the window is centered in. The view fills the whole stage.
func open(id: String, stage_size: Vector2) -> DecklistView:
	deck_id = id
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(func(event: InputEvent):
		# a click on the dark area around the window closes it
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			closed.emit())
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var window := PanelContainer.new()
	var window_box := UITheme.box(Color("#0e0c14", 0.98), 14, Color(UITheme.GOLD, 0.7), 2, 40)
	window_box.set_content_margin_all(WINDOW_MARGIN)
	window.add_theme_stylebox_override("panel", window_box)
	window.mouse_filter = Control.MOUSE_FILTER_STOP # clicks inside the window must not close it
	window.size = Vector2(minf(stage_size.x - 60.0, WINDOW_MAX_WIDTH), minf(stage_size.y - 60.0, WINDOW_HEIGHT))
	window.position = (stage_size - window.size) / 2.0
	add_child(window)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	window.add_child(column)
	column.add_child(_header())
	column.add_child(_divider())

	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = COLUMN_COUNT
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", ROW_GAP)
	grid.add_theme_constant_override("v_separation", ROW_GAP)
	scroll.add_child(grid)
	var cards: Dictionary = DeckDB.sorted_cards(DeckDB.get_deck(deck_id)["cards"])
	var incarnation_id := String(CardDB.leader(DeckDB.get_deck(deck_id)["leader"])["incarnation"])
	for card_id in cards:
		var row := DecklistRow.new().setup(card_id, int(cards[card_id]), card_id == incarnation_id)
		row.tapped.connect(func(tapped_card_id: String): card_chosen.emit(tapped_card_id))
		grid.add_child(row)

	# the X sits on top of the window, not inside its layout
	var close_button := _close_button()
	close_button.position = window.position + Vector2(window.size.x - close_button.size.x - 14.0, 14.0)
	add_child(close_button)
	return self

## Deck name, Leader line, counts by type (left) and the mana curve (right).
func _header() -> Control:
	var deck := DeckDB.get_deck(deck_id)
	var leader := CardDB.leader(deck["leader"])
	var accent := Color(String(CardDB.essence(leader["essences"][0]).get("color", "#8a8f98")))
	var essence_names: Array = []
	for essence_id in leader["essences"]:
		essence_names.append(CardDB.essence(essence_id).get("name", essence_id))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 4)
	row.add_child(texts)
	texts.add_child(_text("LISTA DO DECK", 15, Color(UITheme.GOLD, 0.9), "title_bold"))
	texts.add_child(_text(String(deck["name"]), 40, UITheme.GOLD_LIGHT, "title_bold"))
	texts.add_child(_text("%s · %d de vida · %s" % [leader["name"], int(leader["hp"]), " / ".join(essence_names)],
			19, accent.lightened(0.35), "bold"))
	texts.add_child(_text(_counts_line(), 18, UITheme.TEXT_DIM, "bold"))
	texts.add_child(_text(_elites_line(), 18, UITheme.TEXT_DIM, "bold"))
	texts.add_child(_essences_line())

	var curve := Control.new()
	curve.custom_minimum_size = Vector2(CURVE_BAR_WIDTH * (CURVE_MAX_COST + 1) + 30.0, CURVE_HEIGHT + 44.0)
	curve.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var costs := _cost_counts()
	curve.draw.connect(func(): _draw_curve(curve, costs, accent))
	row.add_child(curve)
	# keeps the curve clear of the close button in the corner
	var corner_gap := Control.new()
	corner_gap.custom_minimum_size = Vector2(56, 0)
	row.add_child(corner_gap)
	return row

## "40 cartas · 22 Unidades · 14 Feitiços · 4 Artefatos"
func _counts_line() -> String:
	var counts_by_type := {}
	var cards: Dictionary = DeckDB.get_deck(deck_id)["cards"]
	for card_id in cards:
		var type := String(CardDB.card(card_id)["type"])
		counts_by_type[type] = int(counts_by_type.get(type, 0)) + int(cards[card_id])
	var parts: Array = ["%d cartas" % DeckDB.card_count(deck_id)]
	for type in CardDB.TYPES:
		if counts_by_type.has(type):
			parts.append("%d %s" % [counts_by_type[type], TYPE_NAMES[type]])
	return " · ".join(parts)

## "20 Elites (8 Lendárias · 12 Campeãs)": champions + legendaries, counting copies (DeckDB.MAX_ELITE_CARDS is the limit).
func _elites_line() -> String:
	var legendary_copies := 0
	var champion_copies := 0
	var cards: Dictionary = DeckDB.get_deck(deck_id)["cards"]
	for card_id in cards:
		var rarity := String(CardDB.card(card_id).get("rarity", ""))
		if rarity == "legendary":
			legendary_copies += int(cards[card_id])
		elif rarity == "champion":
			champion_copies += int(cards[card_id])
	var elite_copies := legendary_copies + champion_copies
	return "%d %s (%d %s · %d %s)" % [elite_copies, "Elite" if elite_copies == 1 else "Elites",
			legendary_copies, "Lendária" if legendary_copies == 1 else "Lendárias",
			champion_copies, "Campeã" if champion_copies == 1 else "Campeãs"]

## "Aquática ×20 · Sagrada ×12 · Neutra ×6": how many copies of the deck carry each essence, most
## numerous first, each in its own color. Neutral counts as an essence here; a dual card counts for both of its.
func _essences_line() -> Control:
	var cards: Dictionary = DeckDB.get_deck(deck_id)["cards"]
	var copies_by_essence := {}
	for card_id in cards:
		for essence_id in CardDB.essences_of(CardDB.card(card_id)):
			copies_by_essence[essence_id] = int(copies_by_essence.get(essence_id, 0)) + int(cards[card_id])
	var essence_ids: Array = copies_by_essence.keys()
	essence_ids.sort_custom(func(first_id: String, second_id: String) -> bool:
		if copies_by_essence[first_id] != copies_by_essence[second_id]:
			return copies_by_essence[first_id] > copies_by_essence[second_id]
		return first_id < second_id)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index in essence_ids.size():
		var essence_id: String = essence_ids[index]
		if index > 0:
			line.add_child(_untrimmed_text("·", 18, UITheme.TEXT_DIM, "bold"))
		var essence_color := Color(String(CardDB.essence(essence_id).get("color", "#8a8f98")))
		line.add_child(_untrimmed_text("%s ×%d" % [CardDB.essence(essence_id).get("name", essence_id), copies_by_essence[essence_id]],
				18, DecklistRow.essence_text_color(essence_color), "bold"))
	return line

## How many copies of the deck cost 0, 1, 2 ... CURVE_MAX_COST (the last slot also holds anything dearer).
func _cost_counts() -> Array:
	var counts: Array = []
	counts.resize(CURVE_MAX_COST + 1)
	counts.fill(0)
	var cards: Dictionary = DeckDB.get_deck(deck_id)["cards"]
	for card_id in cards:
		var slot := mini(int(CardDB.card(card_id)["cost"]), CURVE_MAX_COST)
		counts[slot] += int(cards[card_id])
	return counts

func _draw_curve(canvas: Control, counts: Array, accent: Color) -> void:
	var tallest := 1
	for count in counts:
		tallest = maxi(tallest, int(count))
	var font := UITheme.font("bold")
	for slot in counts.size():
		var left := 15.0 + slot * CURVE_BAR_WIDTH
		var bar_height := CURVE_HEIGHT * float(counts[slot]) / tallest
		var bar := Rect2(left + 4.0, 22.0 + CURVE_HEIGHT - bar_height, CURVE_BAR_WIDTH - 8.0, bar_height)
		if counts[slot] > 0:
			canvas.draw_rect(bar, Color(accent, 0.85))
			canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x, 3.0)), accent.lightened(0.5))
			canvas.draw_string(font, Vector2(left, bar.position.y - 4.0), str(counts[slot]), HORIZONTAL_ALIGNMENT_CENTER,
					CURVE_BAR_WIDTH, 15, UITheme.TEXT)
		var cost_text := "%d+" % slot if slot == CURVE_MAX_COST else str(slot)
		canvas.draw_string(font, Vector2(left, 22.0 + CURVE_HEIGHT + 20.0), cost_text, HORIZONTAL_ALIGNMENT_CENTER,
				CURVE_BAR_WIDTH, 17, UITheme.TEXT_DIM)
	canvas.draw_line(Vector2(15, 22.0 + CURVE_HEIGHT), Vector2(canvas.size.x - 15, 22.0 + CURVE_HEIGHT), Color(UITheme.GOLD, 0.5), 2.0)

func _divider() -> Control:
	var line := ColorRect.new()
	line.color = Color(UITheme.GOLD, 0.45)
	line.custom_minimum_size = Vector2(0, 2)
	return line

## An X in the window's top right corner.
func _close_button() -> Button:
	var button_size := Vector2(60, 60)
	var button := Button.new()
	button.custom_minimum_size = button_size
	button.size = button_size
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "Fechar a lista."
	var icon := Control.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = button_size / 2.0
	icon.draw.connect(func():
		icon.draw_line(Vector2(-12, -12), Vector2(12, 12), UITheme.GOLD_LIGHT, 4.0, true)
		icon.draw_line(Vector2(12, -12), Vector2(-12, 12), UITheme.GOLD_LIGHT, 4.0, true))
	button.add_child(icon)
	button.pressed.connect(func(): closed.emit())
	return button

## A label that keeps its full width. Labels that trim with "..." have no minimum width, so side by side
## in an HBoxContainer they would shrink to nothing.
func _untrimmed_text(text: String, font_size: int, color: Color, font_kind: String) -> Label:
	var label := _text(text, font_size, color, font_kind)
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	return label

func _text(text: String, font_size: int, color: Color, font_kind: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UITheme.font(font_kind))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
