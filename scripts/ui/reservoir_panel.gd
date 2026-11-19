class_name ReservoirPanel
extends Panel
## One player's Reservoir on the match table. It is built once per match and stays on screen between
## redraws: each redraw only changes what changed (a card tapped, a new card, the caption), so the
## small cards already shown are not drawn again (rebuilding them cost a big part of every action's frame).

const CELL_SIZE := Vector2(64, 72)
const CARD_SCALE := 0.36

var drop_glow: Panel ## strong yellow: the card being dragged will be deposited if released here
var _host: Control
var _caption: Label
var _instruction: Label
var _row: HBoxContainer
var _cells := { } ## card uid -> Control cell holding that card's view
var _cell_faces := { } ## card uid -> card id shown face up ("" = face down)


func build(host: Control, panel_size: Vector2, glow_color: Color) -> ReservoirPanel:
	_host = host
	size = panel_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UITheme.box(Color(0.03, 0.04, 0.09, 0.88), 8, Color(UITheme.GOLD, 0.65), 2))
	_caption = host.make_label("", 14, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_LEFT, "bold", 2)
	_caption.position = Vector2(8, 3)
	_caption.size = Vector2(390, 19)
	add_child(_caption)
	_instruction = host.make_label("ARRASTE DA MÃO PARA DEPOSITAR", 10, UITheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, "bold", 1)
	_instruction.position = Vector2(175, 3)
	_instruction.size = Vector2(225, 18)
	_instruction.visible = false
	add_child(_instruction)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(5, 23)
	scroll.size = Vector2(400, 84)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(scroll)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 3)
	scroll.add_child(_row)
	drop_glow = _make_glow(panel_size, glow_color, 4, 26)
	drop_glow.visible = false
	return self


## `cards`: the Reservoir in order. `face_up` and `can_return` say, per card uid, whether the card
## shows its face (it came in this turn) and whether it has a DEVOLVER button.
## `on_card_clicked` opens a face-up card big; `on_return` gives a card back (gets the uid).
func show_cards(
		caption_text: String, can_store: bool, cards: Array, face_up: Dictionary, can_return: Dictionary,
		on_card_clicked: Callable, on_return: Callable,
) -> void:
	_caption.text = caption_text
	_instruction.visible = can_store
	tooltip_text = "Arraste uma carta da mão para cá para depositá-la permanentemente." if can_store else ""
	var shown_uids := { }
	for card: Card in cards:
		shown_uids[card.uid] = true
	for uid in _cells.keys():
		if not shown_uids.has(uid):
			_remove_cell(uid)
	for index in cards.size():
		var card: Card = cards[index]
		var face_id: String = card.card_id if face_up.get(card.uid, false) else ""
		if _cells.has(card.uid) and _cell_faces[card.uid] != face_id:
			_remove_cell(card.uid)
		if not _cells.has(card.uid):
			_cells[card.uid] = _make_cell(face_id, on_card_clicked)
			_cell_faces[card.uid] = face_id
			_row.add_child(_cells[card.uid])
		var cell: Control = _cells[card.uid]
		var view: CardView = cell.get_child(0)
		var wanted_rotation := PI / 2.0 if card.exhausted else 0.0
		if not is_equal_approx(view.rotation, wanted_rotation):
			view.rotation = wanted_rotation
		var return_button: Button = cell.get_node_or_null("ReturnButton")
		if can_return.get(card.uid, false) and return_button == null:
			_add_return_button(cell, on_return.bind(card.uid))
		elif not can_return.get(card.uid, false) and return_button != null:
			cell.remove_child(return_button)
			return_button.queue_free()
		if cell.get_index() != index:
			_row.move_child(cell, index)


func _make_cell(face_id: String, on_card_clicked: Callable) -> Control:
	var cell := Control.new()
	cell.custom_minimum_size = CELL_SIZE
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var view := CardView.new().setup(face_id, { }, CARD_SCALE)
	view.face_down = face_id == ""
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE if view.face_down else Control.MOUSE_FILTER_STOP
	view.pivot_offset = view.size / 2.0
	view.position = (CELL_SIZE - view.size) / 2.0
	if not view.face_down:
		view.left_clicked.connect(on_card_clicked)
		view.right_clicked.connect(on_card_clicked)
	cell.add_child(view)
	return cell


func _remove_cell(uid: int) -> void:
	var cell: Control = _cells[uid]
	_row.remove_child(cell)
	cell.queue_free()
	_cells.erase(uid)
	_cell_faces.erase(uid)


## "DEVOLVER" on a card that came to the Reservoir this turn: it goes back to the bottom of the deck,
## and the next turn brings 2 cards.
func _add_return_button(cell: Control, on_pressed: Callable) -> void:
	var button: Button = _host.make_button("DEVOLVER", on_pressed)
	button.name = "ReturnButton"
	button.add_theme_font_size_override("font_size", 10)
	button.position = Vector2(0, CELL_SIZE.y - 22)
	button.size = Vector2(CELL_SIZE.x, 22)
	button.tooltip_text = "Devolve a carta desvirada ao fundo do deck; o Reservatório pula ela. No próximo turno vêm 2 cartas."
	cell.add_child(button)


func _make_glow(panel_size: Vector2, color: Color, border_width: int, shadow_size: int) -> Panel:
	var glow := Panel.new()
	glow.size = panel_size
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.draw_center = false
	style.set_corner_radius_all(8)
	style.set_border_width_all(border_width)
	style.border_color = color
	style.shadow_color = Color(color.r, color.g, color.b, 0.85)
	style.shadow_size = shadow_size
	style.shadow_offset = Vector2.ZERO
	style.anti_aliasing = true
	glow.add_theme_stylebox_override("panel", style)
	add_child(glow)
	return glow
