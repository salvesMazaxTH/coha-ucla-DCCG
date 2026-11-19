class_name ChroniclePanel
extends Panel
## The Chronicle column of the match table. It is built once per match and stays on screen between
## redraws: each redraw only adds the new event rows and removes the ones that left the list, so the
## rows already shown are not drawn again (rebuilding the whole list cost most of every action's frame).

signal row_focused(row: ChronicleRow)
signal card_clicked(card_id: String)

const ChronicleRowScript = preload("res://scripts/ui/chronicle_row.gd")

const LIST_TOP := 40.0 ## below the title, inside the panel
const ROWS_KEPT := 80
const TOP_FADE_HEIGHT := 16

var rows_box: VBoxContainer
var _scroll: ScrollContainer
var _empty_note: Label


func build(host: Control, panel_size: Vector2) -> ChroniclePanel:
	size = panel_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UITheme.box(Color(0.035, 0.03, 0.055, 0.92), 10, Color(UITheme.GOLD, 0.45), 1, 12))
	var title: Label = host.make_label("CRÔNICA", 15, UITheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 3)
	title.position = Vector2(0, 7)
	title.size = Vector2(panel_size.x, 20)
	add_child(title)
	add_child(host.menu_screens.ornament(Vector2(panel_size.x / 2.0, 31), 92))

	# the list sits in a darker well, so the rows read as one block
	var list_size := Vector2(panel_size.x - 12, panel_size.y - LIST_TOP - 6)
	var well := Panel.new()
	well.position = Vector2(6, LIST_TOP)
	well.size = list_size
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_theme_stylebox_override("panel", UITheme.box(Color(0, 0, 0, 0.35), 6))
	add_child(well)
	_scroll = ScrollContainer.new()
	_scroll.position = well.position
	_scroll.size = list_size
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_style_thin_scrollbar(_scroll.get_v_scroll_bar())
	add_child(_scroll)
	rows_box = VBoxContainer.new()
	rows_box.custom_minimum_size = Vector2(list_size.x - 6, 0)
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_box.add_theme_constant_override("separation", 2)
	rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(rows_box)

	_empty_note = host.make_label("Nada aconteceu ainda.", 14, Color(UITheme.TEXT, 0.4), HORIZONTAL_ALIGNMENT_CENTER, "body")
	_empty_note.position = well.position + Vector2(0, list_size.y / 2.0 - 10)
	_empty_note.size = Vector2(list_size.x, 20)
	_empty_note.visible = false
	add_child(_empty_note)

	# the oldest rows fade out under the top edge of the list instead of being cut flat
	var top_fade := Control.new()
	top_fade.position = well.position
	top_fade.size = Vector2(list_size.x, TOP_FADE_HEIGHT)
	top_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_fade.draw.connect(
		func():
			for line in TOP_FADE_HEIGHT:
				top_fade.draw_line(
					Vector2(0, line + 0.5),
					Vector2(list_size.x, line + 0.5),
					Color(0.035, 0.03, 0.055, 0.9 * (1.0 - float(line) / TOP_FADE_HEIGHT)),
					1.0,
				),
	)
	add_child(top_fade)
	return self


## Where the list is, in the coordinates of the panel's parent.
func list_rect() -> Rect2:
	return Rect2(position + _scroll.position, _scroll.size)


## Shows the last ROWS_KEPT entries. Rows whose entry did not change stay as they are; only new rows
## are created (and glow if their seq is newer than `seen_seq`). `is_ally` tells if the viewer did an entry.
func show_entries(entries: Array, is_ally: Callable, open_seq: int, seen_seq: int) -> void:
	var wanted: Array = entries.slice(maxi(0, entries.size() - ROWS_KEPT))
	var wanted_by_seq := { }
	for raw: Dictionary in wanted:
		wanted_by_seq[int(raw.get("seq", 0))] = raw
	var kept_rows := { } ## seq -> row still matching its entry
	for row: ChronicleRow in rows_box.get_children():
		var seq := int(row.entry.get("seq", 0))
		var raw: Dictionary = wanted_by_seq.get(seq, { })
		var still_shown: bool = not raw.is_empty() and raw == row.entry and is_ally.call(raw) == row.is_ally and not kept_rows.has(seq)
		if still_shown:
			kept_rows[seq] = row
		else:
			rows_box.remove_child(row)
			row.queue_free()
	var added_a_row := false
	for index in wanted.size():
		var raw: Dictionary = wanted[index]
		var seq := int(raw.get("seq", 0))
		var row: ChronicleRow = kept_rows.get(seq)
		if row == null:
			row = ChronicleRowScript.new().setup(raw, is_ally.call(raw), seq == open_seq, seq > seen_seq)
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.focused.connect(row_focused.emit)
			row.card_clicked.connect(card_clicked.emit)
			rows_box.add_child(row)
			added_a_row = true
		elif row.is_active != (seq == open_seq):
			row.set_active(seq == open_seq)
		if row.get_index() != index:
			rows_box.move_child(row, index)
	_empty_note.visible = wanted.is_empty()
	if added_a_row:
		_scroll.call_deferred("set", "scroll_vertical", 999999)


## A slim gold scrollbar, so the list doesn't lose width to a chunky default one.
static func _style_thin_scrollbar(bar: ScrollBar) -> void:
	var track := UITheme.box(Color(1, 1, 1, 0.04), 3)
	track.content_margin_left = 2
	track.content_margin_right = 2
	var grabber := UITheme.box(Color(UITheme.GOLD, 0.45), 3)
	var grabber_hover := UITheme.box(Color(UITheme.GOLD, 0.8), 3)
	bar.custom_minimum_size.x = 6
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("grabber", grabber)
	bar.add_theme_stylebox_override("grabber_highlight", grabber_hover)
	bar.add_theme_stylebox_override("grabber_pressed", grabber_hover)
