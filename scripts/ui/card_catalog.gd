class_name CardCatalog
extends RefCounted
## The search / filter / sort model behind every browsable card list (tools/card_gallery.gd and the deck
## builder), plus the sidebar controls that edit it, so both screens filter exactly the same way.
##
## Filters combine with AND; selecting several values in one facet is an OR. Search looks through the
## displayed name, id, rules text, species, element, tags and keywords.

const FACETS := [
	{"id": "essence", "title": "Domínio", "values": "essence"},
	{"id": "element", "title": "Elemento", "values": "element"},
	{"id": "type", "title": "Tipo", "values": "type"},
	{"id": "rarity", "title": "Raridade", "values": "rarity"},
	{"id": "species", "title": "Espécie", "values": "species"},
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
	"Busca ou recupera cartas": ["search_deck", "look_top", "look_bottom", "grave_retrieve", "grave_to_hand"],
	"Invocação": ["summon", "summon_from", "summon_hand_pick", "revive", "revive_self", "revive_pick"],
	"Remoção": ["destroy", "destroy_artifact", "banish", "condemn"],
	"Congela": ["freeze", "freeze_slots"],
	"Atordoa": ["stun"],
	"Exaure": ["exhaust"],
	"Silencia": ["silence"],
	"Remove palavras-chave ou defesas": ["suppress_keyword", "strip_defenses"],
	"Fortalecimento": ["buff", "cap_stats", "species_aura"],
	"Recursos": ["gain_momentum", "gain_reserve", "raise_max_momentum", "momentum_surge", "momentum_cap", "spend_all_momentum"],
	"Redução de custo": ["modify_cost", "discount_hand", "cost_reduction"],
	"Devolução à mão": ["return_to_hand"],
	"Descarte e moagem": ["discard_hand_pick", "mill", "mill_pick"],
	"Transformação": ["transform_self"],
}
const SORT_OPTIONS := ["Nome", "Custo: menor primeiro", "Custo: maior primeiro", "Ataque: maior primeiro", "Vida: maior primeiro", "Tipo / nome"]

var query := ""
var min_cost := 0 ## 0 = no limit
var max_cost := 0 ## 0 = no limit
var sort_option := 0
var selected: Dictionary = {} ## facet id -> Dictionary of selected values
var facet_values: Dictionary = {} ## facet id -> Dictionary of every value present in the catalog

var search_box: LineEdit
var _min_box: SpinBox
var _max_box: SpinBox
var _sort_box: OptionButton
var _facet_buttons: Dictionary = {}
var _on_change := Callable()

func _init() -> void:
	_build_facets()

func _build_facets() -> void:
	for facet in FACETS:
		facet_values[facet["id"]] = {}
	for card_id in CardDB.data()["cards"]:
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
	var cd: Dictionary = CardDB.card(card_id)
	var needle := query.strip_edges().to_lower()
	if needle != "" and not search_text(card_id, cd).to_lower().contains(needle):
		return false
	var cost := int(cd.get("cost", 0))
	if min_cost > 0 and cost < min_cost:
		return false
	if max_cost > 0 and cost > max_cost:
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
	var parts := [card_id, String(cd.get("name", "")), String(cd.get("text", "")), CardDB.essence_names(cd), CardDB.element_names(cd)]
	parts.append_array(cd.get("species", []))
	parts.append_array(cd.get("keywords", []))
	return " ".join(parts)

static func values_for(cd: Dictionary, facet_id: String, card_id := "") -> Array:
	match facet_id:
		"essence": return CardDB.essences_of(cd)
		"element": return CardDB.elements_of(cd)
		"type":
			var card_types: Array = [String(cd.get("type", ""))]
			if CardDB.is_unit_artifact(cd):
				card_types.append("artifact") # a unit-artifact shows up under both Unidade and Artefato
			return card_types
		"rarity", "speed": return [String(cd.get(facet_id, ""))] if cd.has(facet_id) else []
		"species": return cd.get("species", []).duplicate()
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
		"essence": return String(CardDB.essence(value).get("name", value))
		"element": return String(CardDB.element(value).get("name", value))
		"species": return String(CardDB.data().get("species", {}).get(value, {}).get("name", value))
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
	cost_row.add_theme_constant_override("separation", 8)
	_min_box = _cost_box("mín.", func(value: int): min_cost = value)
	_max_box = _cost_box("máx.", func(value: int): max_cost = value)
	cost_row.add_child(_min_box)
	cost_row.add_child(_max_box)
	box.add_child(cost_row)

	box.add_child(_section("ORDENAR"))
	_sort_box = OptionButton.new()
	for option in SORT_OPTIONS:
		_sort_box.add_item(option)
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
	min_cost = 0
	max_cost = 0
	if search_box != null:
		search_box.text = ""
		_min_box.value = 0
		_max_box.value = 0
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

func _cost_box(placeholder: String, setter: Callable) -> SpinBox:
	var box := SpinBox.new()
	box.min_value = 0
	box.max_value = 20
	box.step = 1
	box.allow_greater = true
	box.custom_minimum_size = Vector2(120, 36)
	box.tooltip_text = "Custo " + placeholder
	box.get_line_edit().placeholder_text = placeholder
	box.value_changed.connect(func(value: float):
		setter.call(int(value))
		_changed())
	return box

static func _section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(UITheme.GOLD, 0.78))
	label.add_theme_font_override("font", UITheme.font("bold"))
	label.add_theme_constant_override("outline_size", 1)
	return label
