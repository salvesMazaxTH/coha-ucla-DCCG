class_name DeckBuilder
extends Control
const DomainIconRowScript = preload("res://scripts/ui/domain_icon_row.gd")
const DeckLeaderTooltipScript = preload("res://scripts/ui/deck_leader_tooltip.gd")
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
const CARD_SCALE := 1.3
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
var _incarnation_id := ""
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
var _incarnation_label: Label

# The coach is deliberately advisory: DeckDB remains the authority on what is legal.
# A beginner can turn this on for the current editing session and change its plan at any time.
var _assistant_enabled := false
var _assistant_profile := ""
var _assistant_focus := ""
var _assistant_prompted := false

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
		if DeckDB.is_deckable(String(card_id)) or CardDB.is_leader_card(String(card_id)):
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
	header.add_child(_btn("IMPORTAR CÓDIGO", _open_import_code, false, 16))
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

func _classify(leader: String, cards: Dictionary, incarnation_id := "") -> Dictionary:
	if leader == "":
		return {"status": "illegal", "errors": ["O Líder deste deck não existe mais. Abra o deck para escolher outro."]}
	var errors := DeckDB.validate_cards(leader, cards, incarnation_id)
	var total: int = DeckDB.stats(leader, cards, incarnation_id)["total"]
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
	var verdict := _classify(leader, deck["cards"], String(deck.get("incarnation_id", "")))
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
	var drawn: int = DeckDB.stats(leader, deck["cards"], String(deck.get("incarnation_id", "")))["total"] if leader != "" else 0
	var leader_line := "%d/%d cartas" % [drawn, DeckDB.DECK_SIZE]
	if leader != "":
		DeckLeaderTooltipScript.attach(tile, String(CardDB.leader(leader)["name"]))
	var leader_row := HBoxContainer.new()
	leader_row.add_theme_constant_override("separation", 4)
	leader_row.position = Vector2(12, art_h + 8)
	leader_row.size = Vector2(DECK_TILE.x - 24, 28)
	leader_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sub := _lbl(leader_line, 16, color.lightened(0.35))
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	leader_row.add_child(sub)
	var domain_row := DomainIconRowScript.new().setup(DeckDB.domains_in(leader, deck["cards"], String(deck.get("incarnation_id", ""))), 23.0, 2)
	domain_row.size_flags_horizontal = Control.SIZE_SHRINK_END
	leader_row.add_child(domain_row)
	tile.add_child(leader_row)
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
		if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if DeckLeaderTooltipScript.consume_tap(tile):
				return
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
		var fresh := {"id": "", "name": "Novo deck", "description": "", "leader": leader_id, "incarnation_id": String(CardDB.leader(leader_id)["incarnation"]), "cards": {}, "problems": []}
		if template_id != "":
			var template: Dictionary = DeckDB.get_deck(template_id)
			fresh["name"] = "Meu " + String(template["name"])
			fresh["description"] = String(template.get("description", ""))
			fresh["incarnation_id"] = String(template.get("incarnation_id", CardDB.leader(leader_id)["incarnation"]))
			fresh["cards"] = (template["cards"] as Dictionary).duplicate()
		_open_editor(fresh, template_id != ""))

func _duplicate(deck: Dictionary) -> void:
	if store.is_full():
		_toast("Limite de %d decks atingido." % DeckStore.MAX_DECKS, WARN)
		return
	store.save_deck("", ("Cópia de " + String(deck["name"])).left(DeckStore.MAX_NAME), deck["leader"], deck["cards"], deck["description"], String(deck.get("incarnation_id", "")))

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
	_incarnation_id = String(deck.get("incarnation_id", ""))
	_cards = (deck["cards"] as Dictionary).duplicate()
	_dirty = start_dirty
	_saving = false
	_editing_cloud = store.is_cloud()
	_load_notes.clear()
	_assistant_enabled = false
	_assistant_profile = ""
	_assistant_focus = ""
	_assistant_prompted = false
	for problem in deck.get("problems", []):
		_load_notes.append(String(problem))
	if _leader == "":
		# the saved Leader no longer exists: a new one is needed before the editor can be built
		_pick_leader("ESCOLHA UM NOVO LÍDER PARA ESTE DECK", false, func(leader_id: String, _template: String): _set_leader(leader_id))
		return
	_ensure_incarnation()
	_show_editor()

func _ensure_incarnation() -> void:
	_incarnation_id = DeckDB.resolved_incarnation_id(_leader, _incarnation_id)
	if int(_cards.get(_incarnation_id, 0)) <= 0:
		_cards[_incarnation_id] = 1

func _set_leader(leader_id: String) -> void:
	var previous_incarnation := _incarnation_id
	_leader = leader_id
	_incarnation_id = previous_incarnation if CardDB.is_incarnation_option(leader_id, previous_incarnation) else String(CardDB.leader(leader_id)["incarnation"])
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
	if not _assistant_prompted:
		_assistant_prompted = true
		_offer_deck_assistant.call_deferred()

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
	(tile["minus"] as Button).disabled = copies <= (1 if card_id == _incarnation_id else 0)
	(tile["plus"] as Button).disabled = copies >= limit or card_id == _incarnation_id

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
	var incarnation_row := HBoxContainer.new()
	_incarnation_label = _lbl("", 15, UITheme.GOLD_LIGHT, "bold")
	_incarnation_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	incarnation_row.add_child(_incarnation_label)
	incarnation_row.add_child(_btn("TROCAR", _open_incarnation_picker, false, 14))
	box.add_child(incarnation_row)
	_refresh_incarnation_label()
	var coach_row := HBoxContainer.new()
	var coach_title := _lbl("ASSISTENTE DE DECK", 15, INFO, "heavy")
	coach_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coach_row.add_child(coach_title)
	coach_row.add_child(_btn("CONFIGURAR" if _assistant_enabled else "ATIVAR", _offer_deck_assistant, false, 14))
	box.add_child(coach_row)

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
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 8)
	var import_button := _btn("IMPORTAR DECKCODE", _open_import_code, false, 15)
	import_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(import_button)
	var export_button := _btn("EXPORTAR DECKCODE", _export_code, false, 15)
	export_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(export_button)
	box.add_child(code_row)
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

func _refresh_incarnation_label() -> void:
	if _incarnation_label == null or not is_instance_valid(_incarnation_label) or not CardDB.data()["cards"].has(_incarnation_id):
		return
	_incarnation_label.text = "Encarnação: %s" % String(CardDB.card(_incarnation_id)["name"])

func _open_incarnation_picker() -> void:
	var options := CardDB.incarnation_options(_leader)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(size.x - 100.0, 700.0), 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(_lbl("ESCOLHA A ENCARNAÇÃO", 26, UITheme.GOLD_LIGHT, "title_bold"))
	var explanation := _lbl("Uma cópia fica no Santuário. Ao trocar, a cópia reservada atual é substituída; cópias extras continuam no deck e seguem o limite normal.", 16, UITheme.TEXT_DIM, "body")
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(explanation)
	for card_id in options:
		var cd: Dictionary = CardDB.card(card_id)
		var marker := " ✓" if card_id == _incarnation_id else ""
		var option_button := _btn("%s%s · custo %d\n%s" % [cd.get("name", card_id), marker, int(cd.get("cost", 0)), cd.get("text", "")], func():
			_select_incarnation(card_id), false, 17)
		option_button.custom_minimum_size = Vector2(620, 64)
		box.add_child(option_button)
	var close_row := HBoxContainer.new()
	close_row.alignment = BoxContainer.ALIGNMENT_END
	close_row.add_child(_btn("FECHAR", _close_modal))
	box.add_child(close_row)
	_open_modal(panel, false)

func _select_incarnation(card_id: String) -> void:
	if not CardDB.is_incarnation_option(_leader, card_id):
		_toast("Essa carta não pode ser a Encarnação deste Líder.", BAD)
		return
	if int(_cards.get(card_id, 0)) > 1:
		_toast("Reduza esta carta a 1 cópia antes de escolhê-la como Encarnação.", WARN)
		return
	var previous_id := _incarnation_id
	if int(_cards.get(card_id, 0)) <= 0:
		var previous_copies := int(_cards.get(previous_id, 0))
		if previous_copies > 1:
			_cards[previous_id] = previous_copies - 1
		else:
			_cards.erase(previous_id)
		_cards[card_id] = 1
	_incarnation_id = card_id
	_close_modal()
	_mark_dirty()
	_refresh_tile(previous_id)
	_refresh_tile(card_id)
	_refresh_deck_panel()

## A short, plain-language interview. It gives the analysis a declared game plan instead of
## pretending that every legal pile of cards has the same goal.
func _offer_deck_assistant() -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(size.x - 100.0, 650.0), 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(_lbl("ASSISTENTE DE DECK", 28, UITheme.GOLD_LIGHT, "title_bold"))
	var intro := _lbl("Quer usar o assistente? Ele acompanha as escolhas deste deck e aponta problemas de construção. Ele só aconselha: você continua no controle.", 17, UITheme.TEXT, "body")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(590, 0)
	box.add_child(intro)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_child(_btn("NÃO USAR AGORA", func():
		_assistant_enabled = false
		_refresh_deck_panel()
		_close_modal()))
	actions.add_child(_btn("USAR ASSISTENTE", func():
		_close_modal()
		_ask_archetype(), true))
	box.add_child(actions)
	_open_modal(panel, false)

func _ask_archetype() -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(size.x - 100.0, 700.0), 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(_lbl("QUAL É O PLANO DO DECK?", 26, UITheme.GOLD_LIGHT, "title_bold"))
	box.add_child(_lbl("Não existe resposta errada. O assistente vai comparar suas cartas com a estratégia escolhida.", 16, UITheme.TEXT_DIM, "body"))
	var choices := VBoxContainer.new()
	choices.add_theme_constant_override("separation", 7)
	box.add_child(choices)
	for choice in [["aggro", "AGGRO", "Vencer cedo, pressionando desde os primeiros turnos."], ["midrange", "MIDRANGE", "Disputar bem o meio de jogo com ameaças consistentes."], ["control", "CONTROL", "Responder ao rival e vencer com calma no fim do jogo."], ["combo", "COMBO", "Montar uma combinação ou uma sinergia poderosa."], ["unsure", "NÃO SEI AINDA", "Quero montar e aprender o que cada tipo de carta faz."]]:
		var key := String(choice[0])
		choices.add_child(_btn("%s — %s" % [choice[1], choice[2]], func():
			_assistant_profile = key
			_close_modal()
			_ask_assistant_focus(), false, 17))
	var back := HBoxContainer.new()
	back.alignment = BoxContainer.ALIGNMENT_END
	back.add_child(_btn("VOLTAR", _offer_deck_assistant))
	box.add_child(back)
	_open_modal(panel, false)

func _ask_assistant_focus() -> void:
	var options: Array = []
	match _assistant_profile:
		"aggro": options = [["burn", "DANO DIRETO", "Quero finalizar o Líder adversário com magias e efeitos de dano."], ["board", "CRIATURAS RÁPIDAS", "Quero lotar a mesa cedo e atacar com unidades baratas."]]
		"midrange": options = [["pressure", "PRESSÃO CONSTANTE", "Quero curvas equilibradas e ameaças em todo turno."], ["value", "VALOR", "Quero cartas que trocam bem e geram vantagens."]]
		"control": options = [["removal", "MUITAS RESPOSTAS", "Quero remover ou atrapalhar as ameaças do rival."], ["late", "FINAL DE JOGO", "Quero sobreviver e ganhar com cartas fortes mais tarde."]]
		"combo": options = [["spells", "COMBO DE EFEITOS", "Quero achar peças com compras e magias."], ["tribal", "SINERGIA DE TRIBO", "Quero muitas cartas da mesma espécie trabalhando juntas."]]
		_: options = [["learn", "APRENDER", "Quero dicas gerais enquanto experimento."], ["balanced", "EQUILIBRADO", "Quero um deck versátil sem compromisso com um plano único."]]
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(size.x - 100.0, 650.0), 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(_lbl("MAIS UMA PERGUNTA", 26, UITheme.GOLD_LIGHT, "title_bold"))
	box.add_child(_lbl("O que você mais quer que este deck faça?", 17, UITheme.TEXT, "body"))
	for option in options:
		var key := String(option[0])
		box.add_child(_btn("%s — %s" % [option[1], option[2]], func():
			_assistant_focus = key
			_assistant_enabled = true
			_close_modal()
			_refresh_deck_panel(), false, 17))
	var back := HBoxContainer.new()
	back.alignment = BoxContainer.ALIGNMENT_END
	back.add_child(_btn("VOLTAR", _ask_archetype))
	box.add_child(back)
	_open_modal(panel, false)

## Shareable, versioned deck code (the compact format lives in DeckCode).
func _make_deck_code() -> String:
	return DeckCode.encode(_deck_name.strip_edges(), _leader, _incarnation_id, _cards)

func _decode_deck_code(code: String) -> Dictionary:
	var decoded := DeckCode.decode(code)
	if decoded.has("error"):
		return decoded
	var parsed: Dictionary = decoded["payload"]
	var leader := String(parsed.get("leader", ""))
	if not CardDB.data()["leaders"].has(leader):
		return {"error": "O deckCode contém um Líder desconhecido."}
	var raw_cards: Variant = parsed.get("cards", {})
	if not raw_cards is Dictionary:
		return {"error": "A lista de cartas do deckCode está inválida."}
	var cards: Dictionary = {}
	var incarnation := String(parsed.get("incarnation_id", CardDB.leader(leader)["incarnation"]))
	if not CardDB.is_incarnation_option(leader, incarnation):
		return {"error": "O deckCode escolhe uma carta que não pode ser a Encarnação deste Líder."}
	for raw_id in raw_cards:
		var card_id := String(raw_id)
		var value: Variant = raw_cards[raw_id]
		if not (value is int or value is float) or float(value) != float(int(value)) or int(value) < 1 or int(value) > DeckStore.MAX_CARD_COPIES:
			return {"error": "Quantidade inválida para a carta %s." % card_id}
		if not CardDB.data()["cards"].has(card_id):
			return {"error": "O deckCode contém uma carta desconhecida: %s." % card_id}
		if card_id != incarnation and not DeckDB.is_deckable(card_id, leader):
			return {"error": "A carta %s não pode entrar em um deck." % card_id}
		cards[card_id] = int(value)
	return {
		"deck": {
			"id": "",
			"name": DeckStore.clean_name(String(parsed.get("name", "Deck importado"))),
			"description": String(parsed.get("description", "")),
			"leader": leader,
			"incarnation_id": incarnation,
			"cards": cards,
			"problems": [],
		}
	}

func _open_import_code() -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(size.x - 100.0, 680.0), 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(_lbl("IMPORTAR DECKCODE", 26, UITheme.GOLD_LIGHT, "title_bold"))
	var help := _lbl("Cole aqui o código do deck. O deck será aberto no builder como um rascunho; salve para guardar.", 16, UITheme.TEXT_DIM, "body")
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help)
	var input := TextEdit.new()
	input.custom_minimum_size = Vector2(620, 110)
	input.placeholder_text = "CSA2.…"
	box.add_child(input)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_child(_btn("CANCELAR", _close_modal))
	actions.add_child(_btn("IMPORTAR DECK", func():
		var result := _decode_deck_code(input.text)
		if result.has("error"):
			_toast(String(result["error"]), BAD)
			return
		_close_modal()
		if _view == "edit":
			_confirm("Importar deckCode?", "O deckCode vai substituir o conteúdo que está aberto. O deck importado será um novo deck.", "SUBSTITUIR", func(): _open_editor(result["deck"], true))
		else:
			_open_editor(result["deck"], true), true))
	box.add_child(actions)
	_open_modal(panel, false)
	input.grab_focus()

func _export_code() -> void:
	var code := _make_deck_code()
	DisplayServer.clipboard_set(code)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(size.x - 100.0, 680.0), 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(_lbl("DECKCODE COPIADO", 26, UITheme.GOLD_LIGHT, "title_bold"))
	var help := _lbl("O código já está na área de transferência. Você também pode selecioná-lo e copiar daqui:", 16, UITheme.TEXT_DIM, "body")
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help)
	var output := TextEdit.new()
	output.text = code
	output.custom_minimum_size = Vector2(620, 110)
	output.editable = false
	box.add_child(output)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_child(_btn("FECHAR", _close_modal, true))
	box.add_child(actions)
	_open_modal(panel, false)

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
	if card_id == _incarnation_id:
		_toast("A Encarnação escolhida fica limitada a 1 cópia.", WARN)
		return
	var limit := DeckDB.copy_limit(card_id)
	if copies >= limit:
		_toast("%s: o máximo é %d cópia%s." % [CardDB.card(card_id)["name"], limit, "" if limit == 1 else "s"], WARN)
		return
	_cards[card_id] = copies + 1
	_cards_changed(card_id)

func _remove_card(card_id: String) -> void:
	var copies := int(_cards.get(card_id, 0))
	if copies <= (1 if card_id == _incarnation_id else 0):
		if card_id == _incarnation_id:
			_toast("Escolha outra Encarnação antes de remover esta última cópia.", WARN)
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
	store.save_deck(_deck_id, _deck_name, _leader, _cards, _description, _incarnation_id)

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
	var totals := DeckDB.stats(_leader, _cards, _incarnation_id)
	var total: int = totals["total"]
	_set_meter("total", total, DeckDB.DECK_SIZE, GOOD if total == DeckDB.DECK_SIZE else (WARN if total < DeckDB.DECK_SIZE else BAD))
	_set_meter("elite", totals["elite"], DeckDB.MAX_ELITE_CARDS, GOOD if totals["elite"] <= DeckDB.MAX_ELITE_CARDS else BAD)
	var guest_limit: int = totals["guest_limit"]
	_set_meter("off", totals["off_essence"], guest_limit, GOOD if totals["off_essence"] <= guest_limit else BAD)
	_set_meter("inc", totals["incarnation"], 1, GOOD if totals["incarnation"] == 1 else BAD)

	_curve_counts = []
	_curve_counts.resize(CURVE_SLOTS)
	_curve_counts.fill(0)
	var incarnation := _incarnation_id
	for card_id in _cards:
		var slot := mini(int(CardDB.card(card_id)["cost"]), CURVE_SLOTS - 1)
		var copies := int(_cards[card_id])
		if String(card_id) == incarnation:
			copies -= 1
		_curve_counts[slot] += maxi(0, copies)
	_curve.queue_redraw()

	_refresh_incarnation_label()
	_refresh_warnings(DeckDB.validate_cards(_leader, _cards, _incarnation_id), totals)
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
	for coach_note in _coach_notes():
		_warnings_box.add_child(_note(String(coach_note["text"]), coach_note["color"] as Color, String(coach_note["tag"])))
	for load_note in _load_notes:
		_warnings_box.add_child(_note(load_note, INFO, "AVISO"))

## Heuristics are intentionally conservative and start after a few non-incarnation cards.
## They explain a mismatch with the player's stated plan; they never make a deck illegal.
func _coach_notes() -> Array[Dictionary]:
	var notes: Array[Dictionary] = []
	if not _assistant_enabled:
		return notes
	var total := 0
	var cheap := 0 # cost 0-2
	var middle := 0 # cost 3-5
	var expensive := 0 # cost 6+
	var spells := 0
	var units := 0
	var late_threats := 0 # sizeable units that can close a control game
	var burn := 0
	var targeted_removal := 0 # one enemy unit at a time
	var area_removal := 0 # affects every/each enemy unit
	var draw := 0
	var species: Dictionary = {}
	var incarnation := _incarnation_id
	for card_id in _cards:
		var copies := int(_cards[card_id])
		if String(card_id) == incarnation:
			copies -= 1
		if copies <= 0:
			continue
		var card: Dictionary = CardDB.card(String(card_id))
		var cost := int(card.get("cost", 0))
		total += copies
		if cost <= 2:
			cheap += copies
		elif cost <= 5:
			middle += copies
		else:
			expensive += copies
		if String(card.get("type", "")) == "spell":
			spells += copies
		if String(card.get("type", "")) == "unit":
			units += copies
			if cost >= 6:
				late_threats += copies
		for specie in card.get("species", []):
			species[String(specie)] = int(species.get(String(specie), 0)) + copies
		var has_targeted_removal := false
		var has_area_removal := false
		var has_draw := false
		var has_burn := false
		for effect in card.get("effects", []):
			var action := String(effect.get("action", ""))
			var target := String(effect.get("target", ""))
			if action == "draw":
				has_draw = true
			# "all_enemy_units" (Tempestade Estática) and future all_* targets are AoE;
			# a single target such as any_unit is a punctual answer.
			if (action == "destroy" or action == "damage") and target.contains("unit"):
				if target.begins_with("all_") or target.begins_with("each_"):
					has_area_removal = true
				else:
					has_targeted_removal = true
			if action == "damage" and (target == "enemy_leader" or target == "both_leaders"):
				has_burn = true
		if has_draw:
			draw += copies
		if has_targeted_removal:
			targeted_removal += copies
		if has_area_removal:
			area_removal += copies
		if has_burn:
			burn += copies
	var plan_name: String = String({"aggro": "Aggro", "midrange": "Midrange", "control": "Control", "combo": "Combo", "unsure": "exploração"}.get(_assistant_profile, ""))
	notes.append({"text": "Plano acompanhado: %s. O assistente atualiza estas dicas a cada carta adicionada ou removida." % plan_name, "color": INFO, "tag": "ASSISTENTE"})
	if total < 12:
		notes.append({"text": "Ainda há poucas cartas para julgar a estratégia (%d/12). Continue montando; as dicas mais fortes aparecem quando a base do deck existir." % total, "color": INFO, "tag": "EM ANÁLISE"})
		return notes
	match _assistant_profile:
		"aggro":
			if cheap < maxi(8, ceili(total * 0.35)):
				notes.append({"text": "Seu aggro tem poucas jogadas baratas (%d). Sem presença nos turnos iniciais, ele perde seu maior ponto forte." % cheap, "color": BAD, "tag": "MUITO GRAVE"})
			if expensive > ceili(total * 0.25):
				notes.append({"text": "A curva está pesada para aggro: %d cartas custam 6 ou mais. Troque parte delas por pressão cedo." % expensive, "color": WARN, "tag": "MÉDIO"})
			if _assistant_focus == "burn":
				if burn == 0:
					notes.append({"text": "Você escolheu aggro de dano direto, mas o deck não tem dano ao Líder adversário. Adicione finalizadores de burn ou escolha outro plano." , "color": BAD, "tag": "MUITO GRAVE"})
				elif burn < 4:
					notes.append({"text": "Há só %d cartas de dano direto. Um burn mais confiável normalmente precisa de mais formas de fechar a partida." % burn, "color": WARN, "tag": "MÉDIO"})
		"midrange":
			if middle < ceili(total * 0.40):
				notes.append({"text": "Faltam cartas de custo 3 a 5 (%d). Midrange precisa ocupar bem o meio da partida." % middle, "color": BAD, "tag": "GRAVE"})
			if cheap < 4:
				notes.append({"text": "Poucas cartas baratas podem fazer você perder o tabuleiro antes das ameaças médias chegarem.", "color": WARN, "tag": "MÉDIO"})
		"control":
			var total_removal := targeted_removal + area_removal
			if targeted_removal < 2:
				notes.append({"text": "Control precisa de respostas pontuais: há %d remoções diretas e %d em área. Remoção em área não resolve uma ameaça grande sozinha." % [targeted_removal, area_removal], "color": BAD, "tag": "GRAVE"})
			elif total_removal < 3:
				notes.append({"text": "Há poucas respostas no total (%d pontuais + %d em área). Adicione mais remoções para o plano control ser confiável." % [targeted_removal, area_removal], "color": WARN, "tag": "MÉDIO"})
			if draw < 2:
				notes.append({"text": "Há pouca compra de cartas (%d). Sem reposição, control pode ficar sem respostas no fim da partida." % draw, "color": WARN, "tag": "MÉDIO"})
			if _assistant_focus == "late" and late_threats < 3:
				notes.append({"text": "Você escolheu vencer no fim de jogo, mas há só %d criaturas grandes (custo 6+). Inclua mais finalizadores para transformar o controle da mesa em vitória." % late_threats, "color": BAD, "tag": "GRAVE"})
		"combo":
			if _assistant_focus == "spells":
				if spells < 6:
					notes.append({"text": "Um combo de efeitos ainda tem poucas magias (%d). Defina as peças e inclua meios de encontrá-las." % spells, "color": BAD, "tag": "GRAVE"})
				if draw < 3:
					notes.append({"text": "Combos precisam de consistência: só %d cartas compram cartas. Procure mais formas de achar suas peças." % draw, "color": WARN, "tag": "MÉDIO"})
			else:
				var dominant := 0
				for specie in species:
					dominant = maxi(dominant, int(species[specie]))
				if dominant < 8:
					notes.append({"text": "A sinergia de tribo ainda não apareceu: a espécie mais presente ocupa só %d cartas. Concentre mais o deck numa espécie." % dominant, "color": BAD, "tag": "GRAVE"})
		"unsure":
			if cheap < 4:
				notes.append({"text": "Dica de iniciante: coloque algumas cartas de custo 0 a 2 para ter o que jogar cedo.", "color": WARN, "tag": "DICA"})
			if units == 0:
				notes.append({"text": "O deck ainda não tem unidades. Unidades ajudam a disputar a mesa e tornam a primeira versão mais fácil de jogar.", "color": WARN, "tag": "DICA"})
	return notes

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
		row.is_incarnation = card_id == incarnation
		row.queue_redraw()
		if entry.has("plus"):
			(entry["plus"] as Button).disabled = row.copies >= DeckDB.copy_limit(card_id) or card_id == incarnation
			(entry["minus"] as Button).disabled = row.copies <= (1 if card_id == incarnation else 0)
		_list_box.move_child(entry["wrap"], index)

func _make_list_row(card_id: String, is_incarnation: bool) -> Dictionary:
	var wrap := HBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)
	var row := DecklistRow.new().setup(card_id, int(_cards[card_id]), is_incarnation)
	row.tapped.connect(_inspect)
	row.tooltip_text = "Clique para ver a carta"
	wrap.add_child(row)
	var entry := {"wrap": wrap, "row": row}
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var plus := _btn("+", func(): _add_card(card_id), false, 18)
	plus.custom_minimum_size = Vector2(44, 38)
	var minus := _btn("-", func(): _remove_card(card_id), false, 18)
	minus.custom_minimum_size = Vector2(44, 38)
	minus.disabled = int(_cards[card_id]) <= (1 if is_incarnation else 0)
	buttons.add_child(plus)
	buttons.add_child(minus)
	wrap.add_child(buttons)
	entry["plus"] = plus
	entry["minus"] = minus
	return entry
