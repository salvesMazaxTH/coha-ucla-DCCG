class_name DeckBuilder
extends Control
## The in-game deck builder: "MEUS DECKS". It lists the player's decks (kept by DeckStore: Supabase while
## signed in, this device otherwise), and edits one in a three-column screen built from the card gallery:
## filters | card catalog | the deck being built, with the engine's own rules (DeckDB) shown live.
##
## The copy limit of a card is a hard stop. Every other rule (44 cards, Elite cards, guest cards, the
## Encarnação) is only a warning, so a deck can be reshuffled through illegal states and saved as a
## draft; the list marks it LEGAL / INCOMPLETO / ILEGAL.

signal closed

const SIDEBAR_W := 300.0
const DECK_PANEL_W := 500.0
## the coloured warning bars under the deck list (INCOMPLETO / ILEGAL / LEGAL / AVISO)
const NOTE_FONT_SIZE := 18 ## message text
const NOTE_TAG_FONT_SIZE := 15 ## the coloured tag on the left
const NOTE_TAG_WIDTH := 100.0
const NOTE_PADDING := Vector2(14, 10) ## space between the bar's border and its content
const NOTE_BACKGROUND_ALPHA := 0.2
const CARD_SCALE := 1.1
const GRID_GAP := 14
const PAGE_SIZE := 24
const DECK_TILE := Vector2(340, 322) # wide enough for EDITAR + DUPLICAR + EXCLUIR on one row
const LEADER_TILE := Vector2(172, 214)
const GOOD := Color("#5fcf80")
const WARN := Color("#e8a23a")
const BAD := Color("#e8484a")
const INFO := Color("#6aa7e8")
const CURVE_SLOTS := 8 ## costs 0..6 and "7+"

var store: DeckStore
var catalog: CardCatalog
## Tests set this (before adding the builder to the tree) so they never touch the player's real decks.
var local_deck_path := ""

var _pool: Array[String] = [] ## every card a player may put in a deck
var _view := "list"
var _content: Control
var _modal_layer: Control
var _toast_layer: VBoxContainer
var _modal: Control
var _inspect_overlay: ColorRect
var _list_signature := ""

# the deck being edited
var _deck_id := ""
var _deck_name := ""
var _description := ""
var _leader := ""
var _cards: Dictionary = {}
var _dirty := false
var _saving := false
var _editing_cloud := false
var _load_notes: Array[String] = []

# editor widgets
var _card_flow: HFlowContainer
var _card_scroll: ScrollContainer
var _count_label: Label
var _page_label: Label
var _prev_button: Button
var _next_button: Button
var _domain_toggle: CheckButton
var _page := 0
var _tiles: Dictionary = {}
var _name_edit: LineEdit
var _meters: Dictionary = {}
var _curve: Control
var _curve_counts: Array = []
var _warnings_box: VBoxContainer
var _list_box: VBoxContainer
var _list_rows: Dictionary = {}
var _save_button: Button
var _status_label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.035, 0.03, 0.055, 0.95)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	_modal_layer = Control.new()
	_modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_modal_layer)
	var toast_margin := MarginContainer.new()
	toast_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	toast_margin.add_theme_constant_override("margin_bottom", 96)
	toast_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_margin)
	_toast_layer = VBoxContainer.new()
	_toast_layer.alignment = BoxContainer.ALIGNMENT_END
	_toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_margin.add_child(_toast_layer)

	for card_id in CardDB.data()["cards"]:
		if DeckDB.is_deckable(String(card_id)):
			_pool.append(String(card_id))
	store = DeckStore.new()
	store.name = "DeckStore"
	if local_deck_path != "":
		store.local_path = local_deck_path
		store.use_web_storage = false
		store.allow_cloud = false # a test file means a test: never touch the signed-in account
	add_child(store)
	store.changed.connect(_on_store_changed)
	store.saved.connect(_on_saved)
	store.failed.connect(_on_failed)
	store.import_finished.connect(_on_import_finished)
	_show_list()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		return
	get_viewport().set_input_as_handled()
	if _inspect_overlay != null:
		_close_inspect()
	elif _modal != null:
		_close_modal()
	else:
		_back()

func _back() -> void:
	if _view == "edit":
		if _dirty:
			_confirm("Sair sem salvar?", "Este deck tem alterações que ainda não foram salvas. Se sair agora, elas serão perdidas.", "SAIR SEM SALVAR", _show_list)
		else:
			_show_list()
	else:
		closed.emit()

# ================================================================ helpers

static func _lbl(text: String, font_size: int, color: Color, kind := "bold") -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_override("font", UITheme.font(kind))
	return label

static func _btn(text: String, on_press: Callable, primary := false, font_size := 16) -> Button:
	var button := Button.new()
	button.text = text
	if primary:
		button.theme_type_variation = "PrimaryButton"
	button.add_theme_font_size_override("font_size", font_size)
	button.pressed.connect(func():
		Sfx.play("ui_click")
		on_press.call())
	return button

static func _margin(horizontal: int, vertical: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", horizontal)
	margin.add_theme_constant_override("margin_right", horizontal)
	margin.add_theme_constant_override("margin_top", vertical)
	margin.add_theme_constant_override("margin_bottom", vertical)
	return margin

static func _essence_color(essence_id: String) -> Color:
	return Color(String(CardDB.essence(essence_id).get("color", "#8a8f98")))

static func _leader_color(leader_id: String) -> Color:
	if leader_id == "":
		return Color("#8a8f98")
	return _essence_color(String(CardDB.leader(leader_id)["essences"][0]))

static func _top_crop(tex: Texture2D, window: Vector2, focus := 0.06) -> Texture2D:
	if tex == null:
		return null
	var ts := tex.get_size()
	var crop_h := minf(ts.y, ts.x * window.y / window.x)
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(0, (ts.y - crop_h) * focus, ts.x, crop_h)
	return atlas

## The Leader's portrait cropped to `window`, with its lower half melting into `bg`.
static func _leader_portrait(leader_id: String, window: Vector2, bg: Color) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = window
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if leader_id != "":
		var ld: Dictionary = CardDB.leader(leader_id)
		var art := TextureRect.new()
		art.texture = _top_crop(CardView.texture(String(ld.get("art", ""))), window, float(ld.get("art_focus", 0.06)))
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_SCALE
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(art)
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(bg, 0.0), Color(bg, 1.0)])
	var fade := GradientTexture2D.new()
	fade.gradient = gradient
	fade.fill_from = Vector2(0, 0.35)
	fade.fill_to = Vector2(0, 1)
	var veil := TextureRect.new()
	veil.texture = fade
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(veil)
	return holder

func _clear_content() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_tiles.clear()
	_list_rows.clear()
	_meters.clear()

func _toast(text: String, color := UITheme.GOLD_LIGHT) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.07, 0.06, 0.1, 0.96), 10, Color(color, 0.8), 2, 12))
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := _lbl(text, 19, color)
	label.custom_minimum_size = Vector2(0, 0)
	panel.add_child(label)
	_toast_layer.add_child(panel)
	var tween := panel.create_tween()
	tween.tween_interval(3.2)
	tween.tween_property(panel, "modulate:a", 0.0, 0.4)
	tween.tween_callback(panel.queue_free)

# ================================================================ modals

func _open_modal(body: Control, close_on_backdrop := true) -> void:
	_close_modal()
	_modal = Control.new()
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	if close_on_backdrop:
		shade.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed:
				_close_modal())
	_modal.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(body)
	_modal.add_child(center)
	_modal_layer.add_child(_modal)

func _close_modal() -> void:
	if _modal == null:
		return
	var old := _modal
	_modal = null
	old.queue_free()

func _confirm(title: String, text: String, ok_text: String, on_ok: Callable) -> void:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(_lbl(title, 26, UITheme.GOLD_LIGHT, "title_bold"))
	var body := _lbl(text, 18, UITheme.TEXT, "body")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(460, 0)
	box.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	row.add_child(_btn("CANCELAR", _close_modal))
	row.add_child(_btn(ok_text, func():
		_close_modal()
		on_ok.call(), true))
	box.add_child(row)
	_open_modal(panel)

## Leader (and optionally a ready-made deck to start from) chooser. `on_pick(leader_id, template_id)`.
func _pick_leader(title: String, with_templates: bool, on_pick: Callable, on_cancel := Callable()) -> void:
	var panel := PanelContainer.new()
	var width := minf(size.x - 120.0, 1320.0)
	var height := minf(size.y - 100.0, 860.0)
	panel.custom_minimum_size = Vector2(width, height)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(_lbl(title, 28, UITheme.GOLD_LIGHT, "title_bold"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 14)
	scroll.add_child(inner)
	var leader_ids: Array = CardDB.data()["leaders"].keys()
	leader_ids.sort_custom(func(a, b): return String(CardDB.leader(String(a))["name"]).naturalnocasecmp_to(String(CardDB.leader(String(b))["name"])) < 0)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 14)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(flow)
	for leader_id in leader_ids:
		flow.add_child(_leader_tile(String(leader_id), func():
			_close_modal()
			on_pick.call(String(leader_id), "")))
	if with_templates:
		inner.add_child(_lbl("OU PARTA DE UM DECK PRONTO", 18, Color(UITheme.GOLD, 0.8), "title"))
		var template_flow := HFlowContainer.new()
		template_flow.add_theme_constant_override("h_separation", 10)
		template_flow.add_theme_constant_override("v_separation", 10)
		template_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		inner.add_child(template_flow)
		for deck_id in DeckDB.ids():
			var template: Dictionary = DeckDB.get_deck(deck_id)
			var template_button := _btn(String(template["name"]), func():
				_close_modal()
				on_pick.call(String(template["leader"]), deck_id), false, 16)
			template_button.tooltip_text = "%s — %s" % [CardDB.leader(String(template["leader"]))["name"], String(template.get("description", ""))]
			template_flow.add_child(template_button)
	var cancel_row := HBoxContainer.new()
	cancel_row.alignment = BoxContainer.ALIGNMENT_END
	cancel_row.add_child(_btn("CANCELAR", func():
		_close_modal()
		if on_cancel.is_valid():
			on_cancel.call()))
	box.add_child(cancel_row)
	_open_modal(panel, false)

func _leader_tile(leader_id: String, on_click: Callable) -> Control:
	var ld: Dictionary = CardDB.leader(leader_id)
	var color := _leader_color(leader_id)
	var bg := Color(0.06, 0.055, 0.085, 0.96)
	var tile := Panel.new()
	tile.custom_minimum_size = LEADER_TILE
	tile.clip_contents = true
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tile.add_theme_stylebox_override("panel", UITheme.box(bg, 12, Color(color, 0.6), 2, 6))
	var portrait := _leader_portrait(leader_id, Vector2(LEADER_TILE.x - 8, LEADER_TILE.y * 0.68), bg)
	portrait.position = Vector2(4, 4)
	portrait.size = Vector2(LEADER_TILE.x - 8, LEADER_TILE.y * 0.68)
	tile.add_child(portrait)
	var name_label := _lbl(String(ld["name"]), 20, UITheme.GOLD_LIGHT, "title_bold")
	name_label.position = Vector2(6, LEADER_TILE.y - 62)
	name_label.size = Vector2(LEADER_TILE.x - 12, 28)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tile.add_child(name_label)
	var domains := _lbl(CardDB.leader_essence_names(ld), 15, color.lightened(0.35))
	domains.position = Vector2(6, LEADER_TILE.y - 32)
	domains.size = Vector2(LEADER_TILE.x - 12, 22)
	domains.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	domains.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tile.add_child(domains)
	tile.tooltip_text = "%s\n%s" % [ld["name"], String(ld.get("ability", {}).get("text", ""))]
	tile.mouse_entered.connect(func(): tile.modulate = Color(1.12, 1.12, 1.12))
	tile.mouse_exited.connect(func(): tile.modulate = Color.WHITE)
	tile.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			Sfx.play("ui_click")
			on_click.call())
	return tile

func _inspect(card_id: String) -> void:
	_close_inspect()
	_inspect_overlay = ColorRect.new()
	_inspect_overlay.color = Color(0, 0, 0, 0.82)
	_inspect_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inspect_overlay.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_close_inspect())
	_modal_layer.add_child(_inspect_overlay)
	CardOverlay.build(_inspect_overlay, size.x, card_id)

func _close_inspect() -> void:
	if _inspect_overlay == null:
		return
	var old := _inspect_overlay
	_inspect_overlay = null
	old.queue_free()

# ================================================================ list view

func _show_list() -> void:
	_view = "list"
	_close_inspect()
	_close_modal()
	_clear_content()
	_list_signature = _signature()
	var margin := _margin(36, 24)
	_content.add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	margin.add_child(page)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	header.add_child(_btn("‹ MENU", _back, false, 18))
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(_lbl("MEUS DECKS", 40, UITheme.GOLD_LIGHT, "title_bold"))
	titles.add_child(_lbl("Monte, edite e guarde seus decks com as mesmas regras das partidas.", 17, UITheme.TEXT_DIM, "body"))
	header.add_child(titles)
	var decks := store.list()
	header.add_child(_lbl("%d / %d decks" % [decks.size(), DeckStore.MAX_DECKS], 20, UITheme.GOLD, "bold"))
	page.add_child(header)
	page.add_child(_build_banner())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 20)
	flow.add_theme_constant_override("v_separation", 20)
	scroll.add_child(flow)
	flow.add_child(_new_deck_tile())
	for deck in decks:
		flow.add_child(_deck_tile(deck))

func _signature() -> String:
	var parts: Array[String] = [str(store.is_cloud()), store.account_name(), str(store.local_decks().size())]
	for deck in store.list():
		parts.append("%s@%s" % [deck["id"], deck["updated_at"]])
	return "|".join(parts)

func _build_banner() -> Control:
	var cloud := store.is_cloud()
	var accent := GOOD if cloud else WARN
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.box(Color(accent, 0.1), 10, Color(accent, 0.55), 2))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)
	var auth := get_node_or_null("/root/SupabaseAuth")
	if cloud:
		texts.add_child(_lbl("Conta Google: %s" % store.account_name(), 20, GOOD))
		texts.add_child(_lbl("Seus decks ficam salvos na nuvem e acompanham você em qualquer aparelho.", 16, UITheme.TEXT_DIM, "body"))
		var local_count := store.local_decks().size()
		if local_count > 0:
			var import := _btn("IMPORTAR %d DECK%s DESTE DISPOSITIVO" % [local_count, "" if local_count == 1 else "S"], func():
				_toast("Importando seus decks para a conta…", INFO)
				store.import_local_decks(), true)
			row.add_child(import)
	else:
		texts.add_child(_lbl("Modo convidado", 20, WARN))
		texts.add_child(_lbl("Seus decks ficam salvos só neste dispositivo. Entre com Google para guardá-los na nuvem (e trazer os que já criou).", 16, UITheme.TEXT_DIM, "body"))
		if auth != null and auth.is_session_checked():
			row.add_child(_btn("ENTRAR COM GOOGLE", func():
				auth.sign_in_with_google(), true))
	return panel

func _classify(leader: String, cards: Dictionary) -> Dictionary:
	if leader == "":
		return {"status": "illegal", "errors": ["O Líder deste deck não existe mais. Abra o deck para escolher outro."]}
	var errors := DeckDB.validate_cards(leader, cards)
	var total: int = DeckDB.stats(leader, cards)["total"]
	var hard := errors.filter(func(message: String) -> bool:
		var size_problem := message.begins_with("deck tem ") and total < DeckDB.DECK_SIZE
		return not size_problem and not message.begins_with("o deck precisa de exatamente 1 Encarnação"))
	var status := "legal"
	if not hard.is_empty():
		status = "illegal"
	elif not errors.is_empty():
		status = "draft"
	return {"status": status, "errors": errors}

func _humanize(message: String) -> String:
	var result := message
	var colon := result.find(": ")
	if colon > 0 and CardDB.data()["cards"].has(result.left(colon)):
		result = String(CardDB.card(result.left(colon))["name"]) + result.substr(colon)
	if result.ends_with(")"):
		var open := result.rfind("(")
		if open >= 0:
			var inner := result.substr(open + 1, result.length() - open - 2)
			if CardDB.data()["cards"].has(inner):
				result = result.left(open) + "(" + String(CardDB.card(inner)["name"]) + ")"
	return result

func _deck_tile(deck: Dictionary) -> Control:
	var leader: String = deck["leader"]
	var color := _leader_color(leader)
	var bg := Color(0.06, 0.055, 0.085, 0.96)
	var verdict := _classify(leader, deck["cards"])
	var status: String = verdict["status"]
	var status_color := GOOD if status == "legal" else (WARN if status == "draft" else BAD)
	var tile := Panel.new()
	tile.custom_minimum_size = DECK_TILE
	tile.clip_contents = true
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tile.add_theme_stylebox_override("panel", UITheme.box(bg, 12, Color(color, 0.6), 2, 8))
	var art_h := 150.0
	var portrait := _leader_portrait(leader, Vector2(DECK_TILE.x - 8, art_h), bg)
	portrait.position = Vector2(4, 4)
	portrait.size = Vector2(DECK_TILE.x - 8, art_h)
	tile.add_child(portrait)

	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", UITheme.box(Color(status_color.darkened(0.55), 0.95), 8, status_color, 2))
	badge.add_child(_lbl({"legal": "LEGAL", "draft": "INCOMPLETO", "illegal": "ILEGAL"}[status], 14, status_color.lightened(0.3), "heavy"))
	badge.position = Vector2(12, 12)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(badge)

	var name_label := _lbl(String(deck["name"]), 22, UITheme.GOLD_LIGHT, "title_bold")
	name_label.position = Vector2(12, art_h - 22)
	name_label.size = Vector2(DECK_TILE.x - 24, 32)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(name_label)
	var drawn: int = DeckDB.stats(leader, deck["cards"])["total"] if leader != "" else 0
	var leader_line := "%s · %d/%d cartas" % [CardDB.leader(leader)["name"] if leader != "" else "Líder desconhecido", drawn, DeckDB.DECK_SIZE]
	var sub := _lbl(leader_line, 16, color.lightened(0.35))
	sub.position = Vector2(12, art_h + 12)
	sub.size = Vector2(DECK_TILE.x - 24, 22)
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(sub)
	var note_text := "Pronto para jogar." if status == "legal" else _humanize(String(verdict["errors"][0]))
	if not (deck["problems"] as Array).is_empty():
		note_text = String(deck["problems"][0])
	var note := _lbl(note_text, 14, status_color.lightened(0.15), "body")
	note.position = Vector2(12, art_h + 38)
	note.size = Vector2(DECK_TILE.x - 24, 40)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.max_lines_visible = 2
	note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(note)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	buttons.position = Vector2(10, DECK_TILE.y - 52)
	buttons.size = Vector2(DECK_TILE.x - 20, 42)
	var edit := _btn("EDITAR", func(): _open_editor(deck), true, 15)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(edit)
	buttons.add_child(_btn("DUPLICAR", func(): _duplicate(deck), false, 14))
	buttons.add_child(_btn("EXCLUIR", func(): _ask_delete(deck), false, 14))
	tile.add_child(buttons)
	tile.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			Sfx.play("ui_click")
			_open_editor(deck))
	return tile

func _new_deck_tile() -> Control:
	var tile := Panel.new()
	tile.custom_minimum_size = DECK_TILE
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tile.add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.GOLD, 0.05), 12, Color(UITheme.GOLD, 0.5), 2, 4))
	var plus := _lbl("+", 96, Color(UITheme.GOLD_LIGHT, 0.7), "title_bold")
	plus.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plus.offset_bottom = -30
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(plus)
	var caption := _lbl("NOVO DECK", 24, UITheme.GOLD_LIGHT, "title_bold")
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -80
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(caption)
	tile.mouse_entered.connect(func(): tile.modulate = Color(1.12, 1.12, 1.12))
	tile.mouse_exited.connect(func(): tile.modulate = Color.WHITE)
	tile.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			Sfx.play("ui_click")
			_new_deck())
	return tile

func _new_deck() -> void:
	if store.is_full():
		_toast("Limite de %d decks atingido. Exclua algum para criar outro." % DeckStore.MAX_DECKS, WARN)
		return
	_pick_leader("NOVO DECK — ESCOLHA O LÍDER", true, func(leader_id: String, template_id: String):
		var fresh := {"id": "", "name": "Novo deck", "description": "", "leader": leader_id, "cards": {}, "problems": []}
		if template_id != "":
			var template: Dictionary = DeckDB.get_deck(template_id)
			fresh["name"] = "Meu " + String(template["name"])
			fresh["description"] = String(template.get("description", ""))
			fresh["cards"] = (template["cards"] as Dictionary).duplicate()
		_open_editor(fresh, template_id != ""))

func _duplicate(deck: Dictionary) -> void:
	if store.is_full():
		_toast("Limite de %d decks atingido." % DeckStore.MAX_DECKS, WARN)
		return
	store.save_deck("", ("Cópia de " + String(deck["name"])).left(DeckStore.MAX_NAME), deck["leader"], deck["cards"], deck["description"])

func _ask_delete(deck: Dictionary) -> void:
	_confirm("Excluir deck", "Excluir \"%s\"? Isso não pode ser desfeito." % deck["name"], "EXCLUIR", func(): store.delete_deck(String(deck["id"])))

# ================================================================ store events

func _on_store_changed() -> void:
	if _view == "list":
		if _signature() != _list_signature and _modal == null:
			_show_list()
	elif store.is_cloud() != _editing_cloud:
		_editing_cloud = store.is_cloud()
		_deck_id = ""
		_dirty = true
		_toast("Seu destino mudou (%s). Salve de novo para guardar este deck." % ("conta Google" if _editing_cloud else "este dispositivo"), WARN)
		_update_save_state()

func _on_saved(deck: Dictionary) -> void:
	if _view == "edit" and _saving:
		_saving = false
		_deck_id = String(deck["id"])
		_dirty = false
		_editing_cloud = bool(deck["cloud"])
		_toast("Deck salvo", GOOD)
		_update_save_state()
	elif _view == "list":
		_toast("Deck salvo", GOOD)

func _on_failed(message: String) -> void:
	_saving = false
	_toast(message, BAD)
	if _view == "edit":
		_update_save_state()

func _on_import_finished(imported: int, failed_count: int) -> void:
	if failed_count > 0:
		_toast("%d deck%s importado%s; %d não foi possível importar (continuam neste dispositivo)." % [imported, "" if imported == 1 else "s", "" if imported == 1 else "s", failed_count], WARN)
	else:
		_toast("%d deck%s importado%s para a sua conta." % [imported, "" if imported == 1 else "s", "" if imported == 1 else "s"], GOOD)
	if _view == "list":
		_show_list()

# ================================================================ editor

func _open_editor(deck: Dictionary, start_dirty := false) -> void:
	_deck_id = String(deck["id"])
	_deck_name = String(deck["name"])
	_description = String(deck.get("description", ""))
	_leader = String(deck["leader"])
	_cards = (deck["cards"] as Dictionary).duplicate()
	_dirty = start_dirty
	_saving = false
	_editing_cloud = store.is_cloud()
	_load_notes.clear()
	for problem in deck.get("problems", []):
		_load_notes.append(String(problem))
	if _leader == "":
		# the saved Leader no longer exists: a new one is needed before the editor can be built
		_pick_leader("ESCOLHA UM NOVO LÍDER PARA ESTE DECK", false, func(leader_id: String, _template: String): _set_leader(leader_id))
		return
	_ensure_incarnation()
	_show_editor()

func _ensure_incarnation() -> void:
	var incarnation := String(CardDB.leader(_leader)["incarnation"])
	if not _cards.has(incarnation):
		_cards[incarnation] = 1

func _set_leader(leader_id: String) -> void:
	if _leader != "":
		_cards.erase(String(CardDB.leader(_leader)["incarnation"]))
	_leader = leader_id
	_ensure_incarnation()
	_dirty = true
	_show_editor()

func _show_editor() -> void:
	_view = "edit"
	_close_inspect()
	_clear_content()
	catalog = CardCatalog.new()
	_page = 0
	var margin := _margin(22, 18)
	_content.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)
	row.add_child(_build_sidebar())
	row.add_child(_build_catalog())
	row.add_child(_build_deck_panel())
	_render_cards.call_deferred()
	_refresh_deck_panel()

func _build_sidebar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(SIDEBAR_W, 0)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	box.add_child(_lbl("CATÁLOGO", 26, UITheme.GOLD_LIGHT, "title_bold"))
	var help := _lbl("Clique numa carta para adicioná-la. Botão direito (ou segurar) mostra os detalhes.", 15, UITheme.TEXT_DIM, "body")
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(SIDEBAR_W - 40, 0)
	box.add_child(help)
	catalog.build_controls(box, SIDEBAR_W - 40, _restart_pages)
	return panel

func _build_catalog() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	_count_label = _lbl("", 19, UITheme.GOLD_LIGHT)
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_count_label)
	_domain_toggle = CheckButton.new()
	_domain_toggle.text = "Só o domínio do Líder"
	_domain_toggle.tooltip_text = "Mostra só as cartas dos domínios do Líder: esconde as convidadas e também as neutras."
	_domain_toggle.toggled.connect(func(_on: bool): _restart_pages())
	top.add_child(_domain_toggle)
	_prev_button = _btn("‹", func(): _change_page(-1))
	_prev_button.tooltip_text = "Página anterior"
	top.add_child(_prev_button)
	_page_label = _lbl("", 16, UITheme.TEXT_DIM)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.custom_minimum_size = Vector2(80, 0)
	top.add_child(_page_label)
	_next_button = _btn("›", func(): _change_page(1))
	_next_button.tooltip_text = "Próxima página"
	top.add_child(_next_button)
	outer.add_child(top)
	_card_scroll = ScrollContainer.new()
	_card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_card_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_card_scroll)
	_card_flow = HFlowContainer.new()
	_card_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_flow.add_theme_constant_override("h_separation", GRID_GAP)
	_card_flow.add_theme_constant_override("v_separation", GRID_GAP)
	_card_scroll.add_child(_card_flow)
	return panel

func _restart_pages() -> void:
	_page = 0
	_render_cards()

func _change_page(delta: int) -> void:
	_page = maxi(0, _page + delta)
	_render_cards()
	_card_scroll.scroll_vertical = 0

func _visible_ids() -> Array[String]:
	var pool: Array = _pool
	if _domain_toggle != null and _domain_toggle.button_pressed:
		pool = _pool.filter(func(card_id: String) -> bool: return DeckDB.is_in_leader_domain(_leader, card_id))
	return catalog.filtered_ids(pool)

func _render_cards() -> void:
	if _card_flow == null or not is_instance_valid(_card_flow):
		return
	for child in _card_flow.get_children():
		_card_flow.remove_child(child)
		child.queue_free()
	_tiles.clear()
	var ids := _visible_ids()
	var total_pages := maxi(1, ceili(float(ids.size()) / PAGE_SIZE))
	_page = clampi(_page, 0, total_pages - 1)
	var first := _page * PAGE_SIZE
	var last := mini(first + PAGE_SIZE, ids.size())
	_count_label.text = "%d de %d cartas" % [ids.size(), _pool.size()]
	_page_label.text = "%d / %d" % [_page + 1, total_pages]
	_prev_button.disabled = _page == 0
	_next_button.disabled = _page >= total_pages - 1
	for index in range(first, last):
		_card_flow.add_child(_card_tile(ids[index]))
	CardView.load_queued_arts()

func _card_tile(card_id: String) -> Control:
	var cell_w := CardView.BASE.x * CARD_SCALE
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(cell_w, CardView.BASE.y * CARD_SCALE + 40.0)
	var card := CardView.new().setup(card_id, {}, CARD_SCALE)
	card.set_process(false)
	card.tooltip_text = "%s\n%s" % [CardDB.card(card_id)["name"], card_id]
	card.left_clicked.connect(func(_view: CardView): _add_card(card_id))
	card.right_clicked.connect(func(_view: CardView): _inspect(card_id))
	holder.add_child(card)

	var frame := Panel.new()
	frame.position = Vector2.ZERO
	frame.size = card.size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_box := UITheme.box(Color.TRANSPARENT, 8, UITheme.GOLD_LIGHT, 3)
	frame_box.bg_color = Color(UITheme.GOLD, 0.0)
	frame.add_theme_stylebox_override("panel", frame_box)
	holder.add_child(frame)

	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.04, 0.08, 0.94), 12, UITheme.GOLD_LIGHT, 2))
	var badge_label := _lbl("", 17, UITheme.GOLD_LIGHT, "heavy")
	badge.add_child(badge_label)
	badge.position = Vector2(cell_w - 50, 4)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(badge)

	var guest_tag: Control = null
	if DeckDB.is_guest(_leader, card_id):
		guest_tag = PanelContainer.new()
		guest_tag.add_theme_stylebox_override("panel", UITheme.box(Color(WARN.darkened(0.5), 0.94), 6, WARN, 1))
		guest_tag.add_child(_lbl("CONVIDADA", 12, WARN.lightened(0.3), "heavy"))
		guest_tag.position = Vector2(4, 4)
		guest_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		guest_tag.tooltip_text = "Fora do domínio do Líder: conta no limite de cartas convidadas."
		holder.add_child(guest_tag)

	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 6)
	controls.position = Vector2(0, card.size.y + 4.0)
	controls.size = Vector2(cell_w, 32)
	var minus := _btn("-", func(): _remove_card(card_id), false, 18)
	minus.custom_minimum_size = Vector2(34, 30)
	controls.add_child(minus)
	var counter := _lbl("", 16, UITheme.TEXT)
	counter.custom_minimum_size = Vector2(44, 0)
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.add_child(counter)
	var plus := _btn("+", func(): _add_card(card_id), false, 18)
	plus.custom_minimum_size = Vector2(34, 30)
	controls.add_child(plus)
	holder.add_child(controls)
	_tiles[card_id] = {"frame": frame_box, "badge": badge, "badge_label": badge_label, "counter": counter, "minus": minus, "plus": plus}
	_refresh_tile(card_id)
	return holder

func _refresh_tile(card_id: String) -> void:
	if not _tiles.has(card_id):
		return
	var tile: Dictionary = _tiles[card_id]
	var copies := int(_cards.get(card_id, 0))
	var limit := DeckDB.copy_limit(card_id)
	(tile["frame"] as StyleBoxFlat).bg_color = Color(UITheme.GOLD, 0.12 if copies > 0 else 0.0)
	(tile["frame"] as StyleBoxFlat).border_color = Color(UITheme.GOLD_LIGHT, 1.0 if copies > 0 else 0.0)
	(tile["badge"] as Control).visible = copies > 0
	(tile["badge_label"] as Label).text = "×%d" % copies
	var counter := tile["counter"] as Label
	counter.text = "%d/%d" % [copies, limit]
	counter.add_theme_color_override("font_color", UITheme.GOLD_LIGHT if copies >= limit else UITheme.TEXT)
	(tile["minus"] as Button).disabled = copies <= 0
	(tile["plus"] as Button).disabled = copies >= limit

func _build_deck_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(DECK_PANEL_W, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	_name_edit = LineEdit.new()
	_name_edit.text = _deck_name
	_name_edit.max_length = DeckStore.MAX_NAME
	_name_edit.placeholder_text = "Nome do deck"
	_name_edit.add_theme_font_size_override("font_size", 22)
	_name_edit.custom_minimum_size = Vector2(0, 42)
	_name_edit.text_changed.connect(func(text: String):
		_deck_name = text
		_mark_dirty())
	box.add_child(_name_edit)

	box.add_child(_build_leader_header())
	box.add_child(_build_meters())

	_curve = Control.new()
	_curve.custom_minimum_size = Vector2(0, 96)
	_curve.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curve.draw.connect(_draw_curve)
	box.add_child(_curve)

	var warnings_scroll := ScrollContainer.new()
	warnings_scroll.custom_minimum_size = Vector2(0, 128)
	warnings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(warnings_scroll)
	_warnings_box = VBoxContainer.new()
	_warnings_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_warnings_box.add_theme_constant_override("separation", 5)
	warnings_scroll.add_child(_warnings_box)

	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(list_scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 4)
	list_scroll.add_child(_list_box)

	_status_label = _lbl("", 15, UITheme.TEXT_DIM, "body")
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_status_label)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	footer.add_child(_btn("‹ VOLTAR", _back, false, 17))
	footer.add_child(_btn("LIMPAR", _ask_clear, false, 17))
	_save_button = _btn("SALVAR DECK", _save, true, 18)
	_save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_button.custom_minimum_size = Vector2(0, 48)
	footer.add_child(_save_button)
	box.add_child(footer)
	return panel

func _build_leader_header() -> Control:
	var bg := Color(0.06, 0.055, 0.085, 1.0)
	var holder := Panel.new()
	holder.custom_minimum_size = Vector2(0, 100)
	holder.clip_contents = true
	holder.add_theme_stylebox_override("panel", UITheme.box(bg, 10, Color(_leader_color(_leader), 0.7), 2))
	var portrait := _leader_portrait(_leader, Vector2(DECK_PANEL_W - 24, 100), bg)
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(portrait)
	var info := VBoxContainer.new()
	info.position = Vector2(14, 14)
	info.size = Vector2(DECK_PANEL_W - 200, 70)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ld: Dictionary = CardDB.leader(_leader)
	var title := _lbl(String(ld["name"]), 24, UITheme.GOLD_LIGHT, "title_bold")
	title.add_theme_constant_override("outline_size", 5)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(title)
	var domains := _lbl("Domínio: %s · Vida %d" % [CardDB.leader_essence_names(ld), int(ld["hp"])], 16, _leader_color(_leader).lightened(0.4))
	domains.add_theme_constant_override("outline_size", 4)
	domains.add_theme_color_override("font_outline_color", Color.BLACK)
	info.add_child(domains)
	holder.add_child(info)
	holder.tooltip_text = String(ld.get("ability", {}).get("text", ""))
	var change := _btn("TROCAR LÍDER", func():
		_pick_leader("TROCAR O LÍDER", false, func(leader_id: String, _template: String):
			if leader_id != _leader:
				_set_leader(leader_id)), false, 15)
	change.position = Vector2(DECK_PANEL_W - 24 - 146, 14)
	change.size = Vector2(134, 38)
	holder.add_child(change)
	return holder

func _build_meters() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	for definition in [["total", "Cartas", "Cartas que você compra: exatamente %d (sem a Encarnação)." % DeckDB.DECK_SIZE],
			["elite", "Campeões + Lendárias", "Máximo de %d cartas Campeão ou Lendária juntas." % DeckDB.MAX_ELITE_CARDS],
			["off", "Convidadas", "Cartas de fora do domínio do Líder: até %d, ou até %d se todas forem de um mesmo domínio." % [DeckDB.MAX_OFF_ESSENCE, DeckDB.MAX_OFF_ESSENCE_SINGLE_DOMAIN]],
			["inc", "Encarnação", "O deck precisa de exatamente 1 Encarnação do Líder."]]:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 2)
		cell.tooltip_text = definition[2]
		var line := HBoxContainer.new()
		var title := _lbl(definition[1], 15, UITheme.TEXT_DIM)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(title)
		var value := _lbl("", 17, UITheme.TEXT, "heavy")
		line.add_child(value)
		cell.add_child(line)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 10)
		bar.add_theme_stylebox_override("background", UITheme.box(Color(1, 1, 1, 0.08), 5))
		cell.add_child(bar)
		_meters[definition[0]] = {"bar": bar, "value": value}
		grid.add_child(cell)
	return grid

func _set_meter(key: String, amount: int, maximum: int, color: Color, caption := "") -> void:
	var meter: Dictionary = _meters[key]
	var bar := meter["bar"] as ProgressBar
	bar.max_value = maxi(1, maximum)
	bar.value = mini(amount, maximum)
	bar.add_theme_stylebox_override("fill", UITheme.box(color, 5))
	var value := meter["value"] as Label
	value.text = caption if caption != "" else "%d/%d" % [amount, maximum]
	value.add_theme_color_override("font_color", color.lightened(0.25))

func _draw_curve() -> void:
	var font := UITheme.font("bold")
	var width := _curve.size.x - 20.0
	var slot_w := width / CURVE_SLOTS
	var baseline := 70.0
	var tallest := 1
	for count in _curve_counts:
		tallest = maxi(tallest, int(count))
	for slot in _curve_counts.size():
		var left := 10.0 + slot * slot_w
		var count := int(_curve_counts[slot])
		var bar_h := (baseline - 14.0) * float(count) / tallest
		if count > 0:
			var bar := Rect2(left + 5.0, baseline - bar_h, slot_w - 10.0, bar_h)
			_curve.draw_rect(bar, Color(DecklistRow.COST_COLOR, 0.9))
			_curve.draw_rect(Rect2(bar.position, Vector2(bar.size.x, 3.0)), DecklistRow.COST_COLOR.lightened(0.5))
			_curve.draw_string(font, Vector2(left, bar.position.y - 3.0), str(count), HORIZONTAL_ALIGNMENT_CENTER, slot_w, 14, UITheme.TEXT)
		var caption := "%d+" % slot if slot == CURVE_SLOTS - 1 else str(slot)
		_curve.draw_string(font, Vector2(left, baseline + 18.0), caption, HORIZONTAL_ALIGNMENT_CENTER, slot_w, 15, UITheme.TEXT_DIM)
	_curve.draw_line(Vector2(10, baseline), Vector2(_curve.size.x - 10, baseline), Color(UITheme.GOLD, 0.5), 2.0)
	_curve.draw_string(font, Vector2(10, 12), "CURVA DE CUSTO", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(UITheme.GOLD, 0.7))

# ---------------------------------------------------------------- editing

func _add_card(card_id: String) -> void:
	var copies := int(_cards.get(card_id, 0))
	var limit := DeckDB.copy_limit(card_id)
	if copies >= limit:
		_toast("%s: o máximo é %d cópia%s." % [CardDB.card(card_id)["name"], limit, "" if limit == 1 else "s"], WARN)
		return
	_cards[card_id] = copies + 1
	_cards_changed(card_id)

func _remove_card(card_id: String) -> void:
	var copies := int(_cards.get(card_id, 0))
	if copies <= 0:
		return
	if copies == 1:
		_cards.erase(card_id)
	else:
		_cards[card_id] = copies - 1
	_cards_changed(card_id)

func _cards_changed(card_id: String) -> void:
	_mark_dirty()
	_refresh_tile(card_id)
	_refresh_deck_panel()

func _ask_clear() -> void:
	_confirm("Limpar o deck?", "Todas as cartas serão removidas (o Líder e a Encarnação ficam).", "LIMPAR", func():
		_cards.clear()
		_ensure_incarnation()
		_mark_dirty()
		_render_cards()
		_refresh_deck_panel())

func _mark_dirty() -> void:
	_dirty = true
	_update_save_state()

func _save() -> void:
	if _saving:
		return
	_saving = true
	_update_save_state()
	store.save_deck(_deck_id, _deck_name, _leader, _cards, _description)

func _update_save_state() -> void:
	if _save_button == null or not is_instance_valid(_save_button):
		return
	_save_button.disabled = _saving
	_save_button.text = "SALVANDO…" if _saving else "SALVAR DECK"
	var destination := "na conta Google" if _editing_cloud else "neste dispositivo"
	if _saving:
		_status_label.text = "Salvando %s…" % destination
		_status_label.add_theme_color_override("font_color", INFO)
	elif _dirty:
		_status_label.text = "Alterações não salvas (serão guardadas %s)" % destination
		_status_label.add_theme_color_override("font_color", WARN)
	else:
		_status_label.text = "Tudo salvo %s" % destination
		_status_label.add_theme_color_override("font_color", GOOD)

func _refresh_deck_panel() -> void:
	if _list_box == null or not is_instance_valid(_list_box) or _view != "edit":
		return
	var totals := DeckDB.stats(_leader, _cards)
	var total: int = totals["total"]
	_set_meter("total", total, DeckDB.DECK_SIZE, GOOD if total == DeckDB.DECK_SIZE else (WARN if total < DeckDB.DECK_SIZE else BAD))
	_set_meter("elite", totals["elite"], DeckDB.MAX_ELITE_CARDS, GOOD if totals["elite"] <= DeckDB.MAX_ELITE_CARDS else BAD)
	var guest_limit: int = totals["guest_limit"]
	_set_meter("off", totals["off_essence"], guest_limit, GOOD if totals["off_essence"] <= guest_limit else BAD)
	_set_meter("inc", totals["incarnation"], 1, GOOD if totals["incarnation"] == 1 else BAD)

	_curve_counts = []
	_curve_counts.resize(CURVE_SLOTS)
	_curve_counts.fill(0)
	var incarnation := String(CardDB.leader(_leader)["incarnation"])
	for card_id in _cards:
		if card_id == incarnation:
			continue
		var slot := mini(int(CardDB.card(card_id)["cost"]), CURVE_SLOTS - 1)
		_curve_counts[slot] += int(_cards[card_id])
	_curve.queue_redraw()

	_refresh_warnings(DeckDB.validate_cards(_leader, _cards), totals)
	_refresh_list(incarnation)
	_update_save_state()

func _refresh_warnings(errors: Array[String], totals: Dictionary) -> void:
	for child in _warnings_box.get_children():
		_warnings_box.remove_child(child)
		child.queue_free()
	if errors.is_empty():
		_warnings_box.add_child(_note("Deck legal: pronto para jogar.", GOOD, "LEGAL"))
	for message in errors:
		var size_problem := message.begins_with("deck tem ") or message.begins_with("o deck precisa de exatamente 1 Encarnação")
		_warnings_box.add_child(_note(_humanize(message), WARN if size_problem and int(totals["total"]) <= DeckDB.DECK_SIZE else BAD, "INCOMPLETO" if size_problem and int(totals["total"]) <= DeckDB.DECK_SIZE else "ILEGAL"))
	if bool(totals["shared_guest_domain"]) and int(totals["off_essence"]) > DeckDB.MAX_OFF_ESSENCE:
		_warnings_box.add_child(_note("O limite de convidadas subiu para %d porque todas elas são de um mesmo domínio." % DeckDB.MAX_OFF_ESSENCE_SINGLE_DOMAIN, INFO, "INFO"))
	for load_note in _load_notes:
		_warnings_box.add_child(_note(load_note, INFO, "AVISO"))

func _note(text: String, color: Color, tag: String) -> Control:
	var panel := PanelContainer.new()
	var panel_style := UITheme.box(Color(color, NOTE_BACKGROUND_ALPHA), 8, Color(color, 0.75), 2)
	panel_style.content_margin_left = NOTE_PADDING.x
	panel_style.content_margin_right = NOTE_PADDING.x
	panel_style.content_margin_top = NOTE_PADDING.y
	panel_style.content_margin_bottom = NOTE_PADDING.y
	panel.add_theme_stylebox_override("panel", panel_style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var chip := _lbl(tag, NOTE_TAG_FONT_SIZE, color.lightened(0.35), "heavy")
	chip.custom_minimum_size = Vector2(NOTE_TAG_WIDTH, 0)
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(chip)
	var message := _lbl(text, NOTE_FONT_SIZE, UITheme.TEXT, "body")
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message.custom_minimum_size = Vector2(DECK_PANEL_W - NOTE_TAG_WIDTH - 2.0 * NOTE_PADDING.x - 40.0, 0)
	row.add_child(message)
	return panel

func _refresh_list(incarnation: String) -> void:
	var ordered: Array = DeckDB.sorted_cards(_cards).keys()
	ordered.erase(incarnation)
	if _cards.has(incarnation):
		ordered.push_front(incarnation)
	for card_id in _list_rows.keys():
		if not _cards.has(card_id):
			var stale: Control = _list_rows[card_id]["wrap"]
			_list_box.remove_child(stale)
			stale.queue_free()
			_list_rows.erase(card_id)
	for index in ordered.size():
		var card_id := String(ordered[index])
		if not _list_rows.has(card_id):
			_list_rows[card_id] = _make_list_row(card_id, card_id == incarnation)
			_list_box.add_child(_list_rows[card_id]["wrap"])
		var entry: Dictionary = _list_rows[card_id]
		var row := entry["row"] as DecklistRow
		row.copies = int(_cards[card_id])
		row.queue_redraw()
		if entry.has("plus"):
			(entry["plus"] as Button).disabled = row.copies >= DeckDB.copy_limit(card_id)
		_list_box.move_child(entry["wrap"], index)

func _make_list_row(card_id: String, is_incarnation: bool) -> Dictionary:
	var wrap := HBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)
	var row := DecklistRow.new().setup(card_id, int(_cards[card_id]), is_incarnation)
	row.tapped.connect(_inspect)
	row.tooltip_text = "Clique para ver a carta"
	wrap.add_child(row)
	var entry := {"wrap": wrap, "row": row}
	if not is_incarnation:
		var buttons := VBoxContainer.new()
		buttons.add_theme_constant_override("separation", 6)
		buttons.alignment = BoxContainer.ALIGNMENT_CENTER
		var plus := _btn("+", func(): _add_card(card_id), false, 18)
		plus.custom_minimum_size = Vector2(44, 38)
		var minus := _btn("-", func(): _remove_card(card_id), false, 18)
		minus.custom_minimum_size = Vector2(44, 38)
		buttons.add_child(plus)
		buttons.add_child(minus)
		wrap.add_child(buttons)
		entry["plus"] = plus
	return entry
