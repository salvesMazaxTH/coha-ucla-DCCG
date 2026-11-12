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
var _sort_box: OptionButton
var _facet_buttons: Dictionary = {}
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

## Fills `box` with the filter controls: search, cost range, sort order, one menu per facet and a clear
## button. `on_change` is called (with no arguments) every time a filter changes.
func build_controls(box: Container, width: float, on_change: Callable) -> void:
	_on_change = on_change
	search_box = LineEdit.new()
	search_box.placeholder_text = "Buscar nome, texto ou id..."
	search_box.clear_button_enabled = true
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
	_sort_box = OptionButton.new()
	for option in SORT_OPTIONS:
		_sort_box.add_item(option)
	_sort_box.select(sort_option)
	_sort_box.item_selected.connect(func(index: int):
		sort_option = index
		_changed())
	box.add_child(_sort_box)

	box.add_child(_section("FILTROS"))
	for facet in FACETS:
		if not facet_values[facet["id"]].is_empty():
			box.add_child(_facet_menu(facet, width))
	var clear := Button.new()
	clear.text = "LIMPAR FILTROS"
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
		var menu := (_facet_buttons[id] as MenuButton).get_popup()
		for i in menu.item_count:
			menu.set_item_checked(i, false)
		_refresh_facet_caption(id)
	_changed()

func _changed() -> void:
	if _on_change.is_valid():
		_on_change.call()

func _facet_menu(facet: Dictionary, width: float) -> MenuButton:
	var id: String = facet["id"]
	var button := MenuButton.new()
	button.custom_minimum_size = Vector2(width, 36)
	_facet_buttons[id] = button
	var menu := button.get_popup()
	menu.hide_on_checkable_item_selection = false
	var values: Array = facet_values[id].keys()
	if id == "set":
		values.sort_custom(func(a, b): return int(a) < int(b)) # by set number, not by name
	else:
		values.sort_custom(func(a, b): return facet_label(id, String(a)).naturalnocasecmp_to(facet_label(id, String(b))) < 0)
	for index in values.size():
		var value := String(values[index])
		menu.add_check_item(facet_label(id, value), index)
		menu.set_item_metadata(index, value)
	menu.id_pressed.connect(func(index: int):
		var value := String(menu.get_item_metadata(index))
		var choices: Dictionary = selected.get(id, {})
		if choices.has(value):
			choices.erase(value)
		else:
			choices[value] = true
		if choices.is_empty():
			selected.erase(id)
		else:
			selected[id] = choices
		menu.set_item_checked(index, choices.has(value))
		_refresh_facet_caption(id)
		_changed())
	_refresh_facet_caption(id)
	return button

func _refresh_facet_caption(id: String) -> void:
	var title := ""
	for facet in FACETS:
		if facet["id"] == id:
			title = facet["title"]
			break
	var count: int = (selected.get(id, {}) as Dictionary).size()
	(_facet_buttons[id] as MenuButton).text = title if count == 0 else "%s (%d)" % [title, count]

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
class CostOrb extends Control:
	signal toggled(pressed: bool)
	var label := ""
	var pressed := false
	var _hovered := false

	func _init() -> void:
		custom_minimum_size = Vector2(0, 38)
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
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(UITheme.GOLD, 0.78))
	label.add_theme_font_override("font", UITheme.font("bold"))
	label.add_theme_constant_override("outline_size", 1)
	return label
