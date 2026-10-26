extends SceneTree
## Browsable catalog for every card in the game. This is deliberately a development/client tool,
## not a screen in Main: run `godot --path . -s tools/card_gallery.gd` to open it.
##
## Click a card to inspect it in the exact same full-screen CardOverlay used during a match.
## Filters combine with AND; selecting several values in one filter is an OR. Search looks through
## the displayed name, id, rules text, species, element, tags and keywords. The filtering itself
## (and its sidebar controls) is CardCatalog, shared with the deck builder.

const WINDOW_MIN := Vector2i(1180, 760)
const SIDEBAR_W := 304.0
const CARD_SCALE := 1.38
const GRID_GAP := 18
const PAGE_SIZE := 48 ## keeps the gallery responsive even with a catalog full of animated frames

var root_view: Control
var cards_grid: GridContainer
var card_scroll: ScrollContainer
var count_label: Label
var overlay: ColorRect
var page := 0
var page_label: Label
var previous_page_button: Button
var next_page_button: Button
var catalog := CardCatalog.new()

func _init() -> void:
	_open.call_deferred()

func _open() -> void:
	var usable := DisplayServer.screen_get_usable_rect()
	# Do not force the minimum window size beyond the monitor. Godot centres an oversized window,
	# which puts the filter rail off-screen on a 1024px-wide display.
	root.size = Vector2i(mini(1500, usable.size.x - 20), mini(940, usable.size.y - 20))
	root.min_size = Vector2i(mini(WINDOW_MIN.x, root.size.x), mini(WINDOW_MIN.y, root.size.y))
	root.position = usable.position + (usable.size - root.size) / 2
	root.title = "UCLA — Galeria de Cartas"
	root.theme = UITheme.make()
	root.window_input.connect(_on_window_input)

	root_view = Control.new()
	root_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(root_view)
	var background := ColorRect.new()
	background.color = Color("#11101a")
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_view.add_child(background)

	var layout := HBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 16)
	layout.offset_left = 18
	layout.offset_top = 18
	layout.offset_right = -18
	layout.offset_bottom = -18
	root_view.add_child(layout)
	layout.add_child(_make_sidebar())
	layout.add_child(_make_catalog())
	root.size_changed.connect(_render_cards.call_deferred)
	# The ScrollContainer has no width until Godot has laid out this frame. Rendering now would
	# calculate one column and leave the catalog as a single vertical strip.
	_render_cards.call_deferred()

func _make_sidebar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(SIDEBAR_W, 0)
	panel.add_theme_stylebox_override("panel", UITheme.panel(12))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	box.add_child(_label("GALERIA DE CARTAS", 24, UITheme.GOLD_LIGHT, "title"))
	var help := _label("Clique em uma carta para ver os detalhes. Filtros do mesmo grupo se somam; grupos diferentes se cruzam.", 15, UITheme.TEXT_DIM)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(SIDEBAR_W - 38, 0)
	box.add_child(help)
	catalog.build_controls(box, SIDEBAR_W - 40, _restart_at_first_page)
	return panel

func _make_catalog() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UITheme.panel(12))
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)
	var top := HBoxContainer.new()
	count_label = _label("", 19, UITheme.GOLD_LIGHT, "bold")
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(count_label)
	previous_page_button = Button.new()
	previous_page_button.text = "‹"
	previous_page_button.tooltip_text = "Página anterior"
	previous_page_button.pressed.connect(func(): _change_page(-1))
	top.add_child(previous_page_button)
	page_label = _label("", 16, UITheme.TEXT_DIM)
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_label.custom_minimum_size = Vector2(90, 0)
	top.add_child(page_label)
	next_page_button = Button.new()
	next_page_button.text = "›"
	next_page_button.tooltip_text = "Próxima página"
	next_page_button.pressed.connect(func(): _change_page(1))
	top.add_child(next_page_button)
	var hint := _label("F11 tela cheia · Esc fecha o detalhe · Ctrl+F busca", 15, UITheme.TEXT_DIM)
	top.add_child(hint)
	outer.add_child(top)
	card_scroll = ScrollContainer.new()
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_scroll.resized.connect(_render_cards.call_deferred)
	outer.add_child(card_scroll)
	cards_grid = GridContainer.new()
	cards_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_grid.add_theme_constant_override("h_separation", GRID_GAP)
	cards_grid.add_theme_constant_override("v_separation", GRID_GAP)
	card_scroll.add_child(cards_grid)
	return panel

func _label(text: String, font_size: int, color: Color, font_kind := "") -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if font_kind != "":
		label.add_theme_font_override("font", UITheme.font(font_kind))
	return label

func _restart_at_first_page() -> void:
	page = 0
	_render_cards()

func _change_page(delta: int) -> void:
	page = maxi(0, page + delta)
	_render_cards()

func _render_cards() -> void:
	if cards_grid == null:
		return
	for child in cards_grid.get_children():
		child.queue_free()
	var visible_ids := catalog.filtered_ids(CardDB.data()["cards"].keys())
	var total_pages := maxi(1, ceili(float(visible_ids.size()) / PAGE_SIZE))
	page = clampi(page, 0, total_pages - 1)
	var first := page * PAGE_SIZE
	var last := mini(first + PAGE_SIZE, visible_ids.size())
	count_label.text = "%d de %d cartas" % [visible_ids.size(), CardDB.data()["cards"].size()]
	page_label.text = "%d / %d" % [page + 1, total_pages]
	previous_page_button.disabled = page == 0
	next_page_button.disabled = page >= total_pages - 1
	var cell_width := CardView.BASE.x * CARD_SCALE
	# During the first layout pass the scroll container can still report zero width. The window-based
	# fallback keeps the initial render a real grid; after layout, `resized` above uses its exact width.
	var available := card_scroll.size.x - 28.0
	if available <= 1.0:
		available = root.size.x - SIDEBAR_W - 90.0
	available = maxf(1.0, available)
	cards_grid.columns = maxi(1, int((available + GRID_GAP) / (cell_width + GRID_GAP)))
	for index in range(first, last):
		var card_id: String = visible_ids[index]
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(cell_width, CardView.BASE.y * CARD_SCALE + 26.0)
		var card := CardView.new().setup(card_id, {}, CARD_SCALE)
		# Gallery cards are inspected through the overlay. Their foil shimmer is cosmetic and would
		# otherwise schedule redraws for every legendary/champion roughly 30 times per second.
		card.set_process(false)
		card.position.x = (cell_width - card.size.x) / 2.0
		card.tooltip_text = "%s\n%s" % [CardDB.card(card_id)["name"], card_id]
		card.left_clicked.connect(func(_view: CardView): _show_overlay(card_id))
		card.right_clicked.connect(func(_view: CardView): _show_overlay(card_id))
		holder.add_child(card)
		var id_label := _label(card_id.replace("_", " "), 13, UITheme.TEXT_DIM)
		id_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		id_label.position.y = card.size.y + 3.0
		id_label.size = Vector2(cell_width, 20)
		id_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(id_label)
		cards_grid.add_child(holder)
	CardView.load_queued_arts()

func _show_overlay(card_id: String) -> void:
	_close_overlay()
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.82)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			_close_overlay())
	root_view.add_child(overlay)
	CardOverlay.build(overlay, root_view.size.x, card_id)

func _close_overlay() -> void:
	if overlay == null:
		return
	var old := overlay
	overlay = null
	if is_instance_valid(old):
		old.queue_free()

func _on_window_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F11:
			_toggle_fullscreen()
		elif event.keycode == KEY_ESCAPE:
			if overlay:
				_close_overlay()
			else:
				quit()
		elif event.keycode == KEY_F and event.ctrl_pressed:
			catalog.search_box.grab_focus()
			catalog.search_box.select_all()

func _toggle_fullscreen() -> void:
	var is_full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if is_full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	# The available grid width changes only after the Window applies the new mode.
	_render_cards.call_deferred()
