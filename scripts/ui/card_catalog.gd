class_name CardCatalog
extends RefCounted
## The search / filter / sort model behind every browsable card list (tools/card_gallery.gd and the deck
## builder), plus the sidebar controls that edit it, so both screens filter exactly the same way.
##
## Filters combine with AND; selecting several values in one facet is an OR. Search looks through the
## displayed name, id, rules text, tribe, element and keywords.

const FACETS := [
	{"id": "set", "title": "Set", "values": "set"},
	{"id": "essence", "title": "Domínio", "values": "essence"},
	{"id": "element", "title": "Elemento", "values": "element"},
	{"id": "type", "title": "Tipo", "values": "type"},
	{"id": "rarity", "title": "Raridade", "values": "rarity"},
	{"id": "tribe", "title": "Tribo", "values": "tribe"},
	{"id": "keyword", "title": "Palavra-chave", "values": "keywords"},
	{"id": "speed", "title": "Velocidade", "values": "speed"},
	{"id": "subtype", "title": "Subtipo", "values": "subtypes"},
	{"id": "action", "title": "Ação mecânica", "values": "actions"},
	{"id": "property", "title": "Características", "values": "properties"},
]
## Friendly groups for common, player-visible actions. More specific engine actions stay discoverable by text search.
const ACTION_CATEGORIES := {
	"Dano": ["damage", "add_dot", "burn", "fatigue_burn", "fight", "auto_attack", "kill_leader", "veneno_lethal"],
	"Cura": ["heal_leader", "leader_max_up", "heal_full", "heal_unit"],
	"Compra de cartas": ["draw", "draw_discounted"],
	"Busca ou recupera cartas": ["search_deck", "look_top", "look_top_to_reservoir", "look_bottom", "grave_retrieve", "grave_to_hand"],
	"Invocação": ["summon", "summon_from", "summon_hand_pick", "revive", "revive_self", "revive_pick"],
	"Remoção": ["destroy", "destroy_artifact", "banish", "condemn"],
	"Congela": ["freeze", "freeze_slots"],
	"Atordoa": ["stun"],
	"Exaure": ["exhaust"],
	"Silencia": ["silence"],
	"Remove palavras-chave ou defesas": ["suppress_keyword", "strip_defenses", "strip_armor", "strip_magic_shield"],
	"Fortalecimento": ["buff", "cap_stats", "tribe_aura", "keyword_aura", "opponent_aura"],
	"Recursos": ["gain_momentum", "gain_battery", "raise_max_momentum", "momentum_surge", "momentum_cap", "battery_cap", "spend_all_momentum"],
	"Redução de custo": ["modify_cost", "modify_cost_cards", "discount_hand", "grant_play_discount", "cost_reduction"],
	"Devolução à mão": ["return_to_hand"],
	"Descarte e moagem": ["discard_hand_pick", "hand_to_bottom", "discard_if_over", "discard_hand_all", "mill", "mill_pick"],
	"Transformação": ["transform_self"],
}
const COST_BUTTON_LAST := 6
const SORT_OPTIONS := ["Nome", "Custo: menor primeiro", "Custo: maior primeiro", "Ataque: maior primeiro", "Vida: maior primeiro", "Tipo / nome"]

var query := ""
var selected_costs: Dictionary = {} ## cost -> true; empty = any cost; COST_BUTTON_LAST means that cost or more
var sort_option := 0
var selected: Dictionary = {} ## facet id -> Dictionary of selected values
var facet_values: Dictionary = {} ## facet id -> Dictionary of every value present in the catalog

var search_box: LineEdit
var _cost_buttons: Array[CostOrb] = []
var _facet_buttons: Dictionary = {} ## facet id (or "sort") -> {header, chips, title}
var _on_change := Callable()

func _init() -> void:
	_build_facets()

func _build_facets() -> void:
	for facet in FACETS:
		facet_values[facet["id"]] = {}
	for card_id in CardDB.data()["cards"]:
		if not DeckDB.is_card_visible(String(card_id)):
			continue
		var cd: Dictionary = CardDB.card(card_id)
		for facet in FACETS:
			for value in values_for(cd, facet["id"]):
				facet_values[facet["id"]][value] = true
	# Player-facing properties that are not literal values in card data.
	facet_values["property"] = {"com habilidade ativada": true, "com Súbito": true, "Encarnação de Líder": true, "com efeito ao entrar": true, "com efeito ao morrer": true, "com efeito contínuo": true}

## The ids that pass every filter, in the chosen order. `pool` is the cards to look through.
func filtered_ids(pool: Array) -> Array[String]:
	var ids: Array[String] = []
	for card_id in pool:
		if matches(String(card_id)):
			ids.append(String(card_id))
	sort_ids(ids)
	return ids

func matches(card_id: String) -> bool:
	if not DeckDB.is_card_visible(card_id):
		return false
	var cd: Dictionary = CardDB.card(card_id)
	var needle := query.strip_edges().to_lower()
	if needle != "" and not search_text(card_id, cd).to_lower().contains(needle):
		return false
	if not selected_costs.is_empty() and not selected_costs.has(mini(int(cd.get("cost", 0)), COST_BUTTON_LAST)):
		return false
	for facet_id in selected:
		var choices: Dictionary = selected[facet_id]
		var card_values := values_for(cd, facet_id, card_id)
		var found := false
		for choice in choices:
			if card_values.has(choice):
				found = true
				break
		if not found:
			return false
	return true

static func search_text(card_id: String, cd: Dictionary) -> String:
	var parts := [card_id, String(cd.get("name", "")), String(cd.get("text", "")), CardDB.essence_names(cd), CardDB.element_names(cd), CardDB.set_full_name(CardDB.set_number_of(cd))]
	parts.append_array(cd.get("tribe", []))
	parts.append_array(cd.get("keywords", []))
	return " ".join(parts)

static func values_for(cd: Dictionary, facet_id: String, card_id := "") -> Array:
	match facet_id:
		"set": return [str(CardDB.set_number_of(cd))] # the set number as text, like every other facet value
		"essence": return CardDB.essences_of(cd)
		"element": return CardDB.elements_of(cd)
		"type":
			var card_types: Array = [String(cd.get("type", ""))]
			if CardDB.is_unit_artifact(cd):
				card_types.append("artifact") # a unit-artifact shows up under both Unidade and Artefato
			return card_types
		"rarity", "speed": return [String(cd.get(facet_id, ""))] if cd.has(facet_id) else []
		"tribe": return cd.get("tribe", []).duplicate()
		"keyword": return _keywords_of(cd)
		"subtype": return cd.get("subtypes", []).duplicate()
		"action": return _action_categories(cd)
		"property": return _properties_of(cd, card_id)
	return []

static func _keywords_of(cd: Dictionary) -> Array:
	var found: Dictionary = {}
	for keyword in cd.get("keywords", []):
		found[String(keyword)] = true
	# Valued keywords are normalized into numeric card fields during CardDB loading,
	# so add their keyword names back for presence-based catalog filtering.
	for keyword_id in CardDB.data().get("keywords", {}):
		var definition: Dictionary = CardDB.data()["keywords"][keyword_id]
		if not definition.get("has_value", false):
			continue
		var value_field := "armor" if keyword_id == "armadura" else String(keyword_id)
		if int(cd.get(value_field, 0)) > 0:
			found[String(keyword_id)] = true
	# Tóxico stores its value in toxico_level/toxico_equals_attack and remains in keywords,
	# but keep this explicit so either printed form is treated as the same keyword.
	if int(cd.get("toxico_level", 0)) > 0 or bool(cd.get("toxico_equals_attack", false)):
		found["toxico"] = true
	return found.keys()

static func _action_categories(cd: Dictionary) -> Array:
	var found: Dictionary = {}
	if cd.has("transform"):
		found["Transformação"] = true
	for effects in [cd.get("effects", []), cd.get("deck_effects", []), cd.get("activated", {}).get("effects", [])]:
		_collect_action_categories(effects, found)
	return found.keys()

static func _collect_action_categories(effects: Array, found: Dictionary) -> void:
	for effect in effects:
		if not effect is Dictionary:
			continue
		var action := String(effect.get("action", ""))
		for category: String in ACTION_CATEGORIES:
			if ACTION_CATEGORIES[category].has(action):
				found[category] = true
		_collect_action_categories(effect.get("then", []), found)

static func _properties_of(cd: Dictionary, card_id: String) -> Array:
	var props: Array = []
	if cd.has("activated"): props.append("com habilidade ativada")
	if cd.has("subito"): props.append("com Súbito")
	if card_id != "" and CardDB.is_leader_card(card_id): props.append("Encarnação de Líder")
	for effect in cd.get("effects", []):
		if effect.get("trigger", "") == "on_enter": props.append("com efeito ao entrar")
		if effect.get("trigger", "") == "on_death": props.append("com efeito ao morrer")
		if effect.get("trigger", "") == "constante": props.append("com efeito contínuo")
	return props

static func facet_label(facet_id: String, value: String) -> String:
	match facet_id:
		"set": return CardDB.set_full_name(int(value))
		"essence": return String(CardDB.essence(value).get("name", value))
		"element": return String(CardDB.element(value).get("name", value))
		"tribe": return String(CardDB.data().get("tribe", {}).get(value, {}).get("name", value))
		"keyword": return String(CardDB.data().get("keywords", {}).get(value, {}).get("name", value))
		"rarity": return {"common": "Comum", "epic": "Épica", "champion": "Campeão", "legendary": "Lendário"}.get(value, value)
		"type": return {"unit": "Unidade", "spell": "Feitiço", "artifact": "Artefato"}.get(value, value)
		"speed": return {"lento": "Lento", "rapido": "Rápido", "instantaneo": "Instantâneo"}.get(value, value)
		"subtype": return {"equipment": "Equipamento", "local": "Local"}.get(value, value)
		"action": return value
	return value.replace("_", " ").capitalize()

func sort_ids(ids: Array[String]) -> void:
	var option := sort_option
	ids.sort_custom(func(a: String, b: String):
		var ca := CardDB.card(a)
		var cb := CardDB.card(b)
		match option:
			1: return int(ca.get("cost", 0)) < int(cb.get("cost", 0)) or (int(ca.get("cost", 0)) == int(cb.get("cost", 0)) and String(ca["name"]).naturalnocasecmp_to(String(cb["name"])) < 0)
			2: return int(ca.get("cost", 0)) > int(cb.get("cost", 0)) or (int(ca.get("cost", 0)) == int(cb.get("cost", 0)) and String(ca["name"]).naturalnocasecmp_to(String(cb["name"])) < 0)
			3: return int(ca.get("atk", -1)) > int(cb.get("atk", -1))
			4: return int(ca.get("hp", -1)) > int(cb.get("hp", -1))
			5: return String(ca.get("type", "")).naturalnocasecmp_to(String(cb.get("type", ""))) < 0 or (ca.get("type", "") == cb.get("type", "") and String(ca["name"]).naturalnocasecmp_to(String(cb["name"])) < 0)
		return String(ca["name"]).naturalnocasecmp_to(String(cb["name"])) < 0)

# ---------------------------------------------------------------- sidebar controls

## Fills `box` with the filter controls: search, cost range, sort order, one folding list per facet and a
## clear button. `on_change` is called (with no arguments) every time a filter changes.
## Nothing here opens a popup: the choices unfold inside the sidebar, so they scale with it on phones.
func build_controls(box: Container, width: float, on_change: Callable) -> void:
	_on_change = on_change
	search_box = LineEdit.new()
	search_box.placeholder_text = "Buscar nome, texto ou id..."
	search_box.clear_button_enabled = true
	search_box.add_theme_font_size_override("font_size", 18)
	search_box.custom_minimum_size = Vector2(0, 46)
	search_box.text_changed.connect(func(text: String):
		query = text
		_changed())
	box.add_child(search_box)

	box.add_child(_section("CUSTO"))
	var cost_row := HBoxContainer.new()
	cost_row.add_theme_constant_override("separation", 0)
	_cost_buttons.clear()
	for cost in COST_BUTTON_LAST + 1:
		var button := _cost_button(cost)
		_cost_buttons.append(button)
		cost_row.add_child(button)
	box.add_child(cost_row)

	box.add_child(_section("ORDENAR"))
	var sort_values: Array = []
	for index in SORT_OPTIONS.size():
		sort_values.append(index)
	box.add_child(_folding_list("sort", "Ordenar", sort_values, width, true))

	box.add_child(_section("FILTROS"))
	for facet in FACETS:
		if not facet_values[facet["id"]].is_empty():
			box.add_child(_folding_list(facet["id"], facet["title"], _sorted_values(facet["id"]), width, false))
	var clear := Button.new()
	clear.text = "LIMPAR FILTROS"
	clear.add_theme_font_size_override("font_size", 18)
	clear.custom_minimum_size = Vector2(0, 48)
	clear.pressed.connect(clear_filters)
	box.add_child(clear)

func clear_filters() -> void:
	selected.clear()
	query = ""
	selected_costs.clear()
	for button in _cost_buttons:
		button.set_pressed_no_signal(false)
	if search_box != null:
		search_box.text = ""
	for id in _facet_buttons:
		if id == "sort":
			continue
		for chip in (_facet_buttons[id]["chips"] as Container).get_children():
			(chip as Button).set_pressed_no_signal(false)
		_refresh_facet_caption(id)
	_changed()

func _changed() -> void:
	if _on_change.is_valid():
		_on_change.call()

func _sorted_values(id: String) -> Array:
	var values: Array = facet_values[id].keys()
	if id == "set":
		values.sort_custom(func(a, b): return int(a) < int(b)) # by set number, not by name
	else:
		values.sort_custom(func(a, b): return facet_label(id, String(a)).naturalnocasecmp_to(facet_label(id, String(b))) < 0)
	return values

## A header button that unfolds a row of chips under it. `single_choice` makes the chips work as one
## choice (the sort order); otherwise each chip toggles one value of the facet `id`.
func _folding_list(id: String, title: String, values: Array, width: float, single_choice: bool) -> Control:
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 6)
	var header := FoldingHeader.new()
	header.custom_minimum_size = Vector2(width, 48)
	holder.add_child(header)
	var chips := HFlowContainer.new()
	chips.visible = false
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	holder.add_child(chips)
	_facet_buttons[id] = {"header": header, "chips": chips, "title": title}
	header.pressed.connect(func():
		chips.visible = not chips.visible
		header.open = chips.visible
		header.queue_redraw())
	var group := ButtonGroup.new() if single_choice else null
	for value in values:
		var chip := _chip(SORT_OPTIONS[value] if single_choice else facet_label(id, String(value)))
		if single_choice:
			chip.button_group = group
			chip.button_pressed = value == sort_option
			chip.toggled.connect(func(on: bool):
				if on:
					sort_option = value
					_refresh_facet_caption(id)
					_changed())
		else:
			chip.toggled.connect(func(on: bool):
				var choices: Dictionary = selected.get(id, {})
				if on:
					choices[String(value)] = true
				else:
					choices.erase(String(value))
				if choices.is_empty():
					selected.erase(id)
				else:
					selected[id] = choices
				_refresh_facet_caption(id)
				_changed())
		if id == "rarity":
			_add_rarity_gem(chip, String(value))
		elif id == "essence":
			_add_domain_seal(chip, String(value))
		elif id == "speed":
			_add_speed_icon(chip, String(value))
		chips.add_child(chip)
	_refresh_facet_caption(id)
	return holder

## Puts the same rarity gem the cards carry (just smaller) at the left of a rarity chip, with a slightly smaller font.
static func _add_rarity_gem(chip: Button, rarity: String) -> void:
	chip.add_theme_font_size_override("font_size", 15)
	var gem_radius := 9.0
	var gap := 8.0
	for style_name in ["normal", "hover", "pressed", "hover_pressed"]:
		var style: StyleBoxFlat = chip.get_theme_stylebox(style_name)
		style.content_margin_left = 12 + gem_radius * 2 + gap
	var gem := RarityGem.new()
	gem.rarity = rarity
	gem.radius = gem_radius
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gem.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gem.offset_left = 12
	chip.add_child(gem)

## Puts the same domain seal the cards carry (smaller) at the left of a domain chip.
static func _add_domain_seal(chip: Button, domain_id: String) -> void:
	var seal_size := 25.0
	_reserve_icon_room(chip, seal_size)
	_add_centered_icon(chip, CardView.new().setup_domain_badge(domain_id, seal_size), Vector2.ONE * seal_size)

## Puts the speed seal's icon (hourglass / bolt / double bolt, same drawing as the cards) at the left of a speed chip.
static func _add_speed_icon(chip: Button, speed: String) -> void:
	var icon := SpeedIcon.new()
	icon.speed = speed
	var icon_width := 22.0 if speed == "instantaneo" else 14.0
	icon.custom_minimum_size = Vector2(icon_width, 22)
	_reserve_icon_room(chip, icon_width)
	_add_centered_icon(chip, icon, icon.custom_minimum_size)

static func _reserve_icon_room(chip: Button, icon_width: float) -> void:
	chip.add_theme_font_size_override("font_size", 15)
	for style_name in ["normal", "hover", "pressed", "hover_pressed"]:
		var style: StyleBoxFlat = chip.get_theme_stylebox(style_name)
		style.content_margin_left = 10 + icon_width + 6

## Anchors `icon` to the chip's left edge, vertically centered, so it stays inside whatever height the chip gets.
static func _add_centered_icon(chip: Button, icon: Control, icon_size: Vector2) -> void:
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchor(SIDE_LEFT, 0.0)
	icon.set_anchor(SIDE_RIGHT, 0.0)
	icon.set_anchor(SIDE_TOP, 0.5)
	icon.set_anchor(SIDE_BOTTOM, 0.5)
	icon.offset_left = 10
	icon.offset_right = 10 + icon_size.x
	icon.offset_top = -icon_size.y / 2.0
	icon.offset_bottom = icon_size.y / 2.0
	chip.add_child(icon)

static func _chip(text: String) -> Button:
	var chip := Button.new()
	chip.text = text
	chip.toggle_mode = true
	chip.custom_minimum_size = Vector2(0, 40)
	chip.add_theme_font_size_override("font_size", 17)
	var off := UITheme.box(Color("#1d1a26"), 16, Color(UITheme.GOLD, 0.35), 2)
	var on := UITheme.box(Color("#c99a3a"), 16, UITheme.GOLD_LIGHT, 2)
	for style in [off, on]:
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 4
		style.content_margin_bottom = 4
	chip.add_theme_stylebox_override("normal", off)
	chip.add_theme_stylebox_override("hover", off)
	chip.add_theme_stylebox_override("pressed", on)
	chip.add_theme_stylebox_override("hover_pressed", on)
	chip.add_theme_color_override("font_pressed_color", Color("#1a1206"))
	chip.add_theme_color_override("font_hover_pressed_color", Color("#1a1206"))
	return chip

func _refresh_facet_caption(id: String) -> void:
	var entry: Dictionary = _facet_buttons[id]
	var title: String = entry["title"]
	if id == "sort":
		title = SORT_OPTIONS[sort_option]
	else:
		var count: int = (selected.get(id, {}) as Dictionary).size()
		if count > 0:
			title = "%s (%d)" % [title, count]
	(entry["header"] as Button).text = title

## The header of a folding list: a big left-aligned button with an arrow on the right.
class FoldingHeader extends Button:
	var open := false

	func _init() -> void:
		alignment = HORIZONTAL_ALIGNMENT_LEFT
		text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		add_theme_font_size_override("font_size", 20)

	func _draw() -> void:
		var center := Vector2(size.x - 20, size.y / 2)
		var arrow := PackedVector2Array([center + Vector2(-7, -4), center + Vector2(7, -4), center + Vector2(0, 5)]) if open \
			else PackedVector2Array([center + Vector2(-4, -7), center + Vector2(5, 0), center + Vector2(-4, 7)])
		draw_colored_polygon(arrow, UITheme.GOLD_LIGHT)

## A toggle for one cost; the last one stands for "that cost or more".
func _cost_button(cost: int) -> CostOrb:
	var orb := CostOrb.new()
	orb.label = "%d+" % cost if cost == COST_BUTTON_LAST else str(cost)
	orb.tooltip_text = "Custo %s" % orb.label
	orb.toggled.connect(func(pressed: bool):
		if pressed:
			selected_costs[cost] = true
		else:
			selected_costs.erase(cost)
		_changed())
	return orb

## The cost orb printed on every card, used as a toggle: dimmed when off, full colour with a light ring when on.
## Draws a card's rarity gem (animated for champions) inside a button.
class RarityGem extends Control:
	var rarity := "common"
	var radius := 9.0
	var _time := 0.0

	func _ready() -> void:
		set_process(rarity == "champion")

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var center := Vector2(radius * 1.3, size.y / 2.0)
		CardView.draw_rarity_gem(self, center, radius, rarity, UITheme.GOLD_LIGHT, _time)

## Draws the speed seal's icon inside a button.
class SpeedIcon extends Control:
	var speed := "lento"

	func _draw() -> void:
		var colors := {"lento": Color("#a9b6c8"), "rapido": Color("#ffd27a"), "instantaneo": Color("#7fe8ff")}
		CardView.draw_speed_icon(self, size / 2.0, 5.6 * 1.5, speed, colors.get(speed, Color.WHITE), 1.5)

class CostOrb extends Control:
	signal toggled(pressed: bool)
	var label := ""
	var pressed := false
	var _hovered := false

	func _init() -> void:
		custom_minimum_size = Vector2(0, 46)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func():
			_hovered = true
			queue_redraw())
		mouse_exited.connect(func():
			_hovered = false
			queue_redraw())

	func set_pressed_no_signal(value: bool) -> void:
		pressed = value
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			pressed = not pressed
			queue_redraw()
			toggled.emit(pressed)
			accept_event()

	func _draw() -> void:
		var center := size / 2
		var radius := minf(size.x, size.y) / 2 / 1.083
		var body := UITheme.MOMENTUM if pressed else UITheme.MOMENTUM.darkened(0.3 if _hovered else 0.55)
		CardView.draw_gem(self, "orb", center, radius, body, label, Color.WHITE, 1.0, 2)
		if pressed:
			draw_arc(center, radius * 1.2, 0, TAU, 40, UITheme.GOLD_LIGHT, 2.0, true)

static func _section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color(UITheme.GOLD, 0.78))
	label.add_theme_font_override("font", UITheme.font("bold"))
	label.add_theme_constant_override("outline_size", 1)
	return label
