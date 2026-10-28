class_name CardDB
extends RefCounted
## Static card catalog loaded from data/cards.json and data/cards/<essence>/*.json.

static var _data: Dictionary = {}
static var _defs: Dictionary = {} ## id -> CardDef
static var _errors: Array[String] = []

## The effect vocabulary lives in EffectRegistry, TargetRegistry and ConditionRegistry; a typo is
## checked on load so it is an error, not a silent no-op.
const DECK_ACTIONS := ["summon_self"]
const TYPES := ["unit", "spell", "artifact"]
const SPEEDS := ["lento", "rapido", "instantaneo"]

static func data() -> Dictionary:
	if _data.is_empty():
		_load()
	return _data

## A keyword with a value is written "armadura:1" or "rapidez:2" in "keywords". The value becomes
## the card's internal stat (the keyword tag itself is drawn from it), so the entry leaves the list:
## - "armadura:N" -> "armor" N
## - "rapidez:N" (Rapidez 1-3) -> "rapidez" N (a card without the keyword has Rapidez 0)
## - "critico:N" (Crítico 1-4) -> "critico" N
## - "toxico:N" (Tóxico 2+) -> "toxico_level" N, and "toxico:atk" -> "toxico_equals_attack" (X = its Ataque).
##   Unlike the others, "toxico" itself stays in the keyword list so grants, silences and has_kw keep working.
static func _apply_valued_keywords(cd: Dictionary) -> void:
	var plain_keywords: Array = []
	for keyword in cd.get("keywords", []):
		if String(keyword).begins_with("armadura:"):
			cd["armor"] = int(String(keyword).trim_prefix("armadura:"))
		elif String(keyword).begins_with("rapidez:"):
			cd["rapidez"] = int(String(keyword).trim_prefix("rapidez:"))
		elif String(keyword).begins_with("critico:"):
			cd["critico"] = int(String(keyword).trim_prefix("critico:"))
		elif String(keyword).begins_with("toxico:"):
			var toxico_value := String(keyword).trim_prefix("toxico:")
			if toxico_value == "atk":
				cd["toxico_equals_attack"] = true
			else:
				cd["toxico_level"] = int(toxico_value)
			plain_keywords.append("toxico")
		else:
			plain_keywords.append(keyword)
	cd["keywords"] = plain_keywords

static func _load() -> void:
	_errors.clear()
	_defs.clear()
	_data = _read_json("res://data/cards.json")
	if _data.is_empty():
		_data = {"essences": {}, "elements": {}, "triggers": {}, "species": {}, "keywords": {}, "leaders": {}}
	_data["cards"] = {}
	for essence_id in _data["essences"]:
		var dir_path: String = "res://data/cards/" + str(essence_id)
		if not DirAccess.dir_exists_absolute(dir_path):
			continue
		for file_name in DirAccess.get_files_at(dir_path):
			if not file_name.ends_with(".json"):
				continue
			var id := file_name.trim_suffix(".json")
			var cd := _read_json(dir_path + "/" + file_name)
			if cd.is_empty():
				continue
			_apply_valued_keywords(cd)
			_data["cards"][id] = cd
			_defs[id] = CardDef.new(id, cd)
	for id in _data["cards"]:
		_validate_card(id, _data["cards"][id])
	for lid in _data["leaders"]:
		_validate_leader(lid, _data["leaders"][lid])

static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_errors.append("%s: arquivo não encontrado" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		_errors.append("%s: JSON inválido" % path)
		return {}
	return parsed

## Problems found while loading the catalog (empty when every card is well formed).
static func errors() -> Array[String]:
	data()
	return _errors

static func def(id: String) -> CardDef:
	data()
	if _defs.has(id):
		return _defs[id]
	# cards added to the data at runtime (test fixtures) have no cached CardDef: build a fresh one
	# each time, so later edits to their dictionary are always seen
	return CardDef.new(id, _data["cards"][id])

static func _validate_card(id: String, cd: Dictionary) -> void:
	var err := func(msg: String): _errors.append("carta %s: %s" % [id, msg])
	for field in ["name", "type", "cost", "text"]:
		if not cd.has(field):
			err.call("falta \"%s\"" % field)
	var type: String = cd.get("type", "")
	if type not in TYPES:
		err.call("type desconhecido \"%s\"" % type)
	if type == "unit":
		for field in ["atk", "hp"]:
			if not cd.has(field):
				err.call("unidade sem \"%s\"" % field)
	for e in essences_of(cd):
		if not _data["essences"].has(e):
			err.call("essência desconhecida \"%s\"" % e)
	var allowed_elements: Array = []
	var any_element_allowed := false # a domain without an "elements" list (Neutra) accepts any element
	for e in essences_of(cd):
		if _data["essences"].has(e) and _data["essences"][e].has("elements"):
			allowed_elements.append_array(_data["essences"][e]["elements"])
		else:
			any_element_allowed = true
	for element_id in elements_of(cd):
		if not _data.get("elements", {}).has(element_id):
			err.call("elemento desconhecido \"%s\"" % element_id)
		elif not any_element_allowed and not allowed_elements.has(element_id):
			err.call("elemento \"%s\" não combina com o domínio da carta (cada domínio lista seus elementos em \"elements\")" % element_id)
	for kw in cd.get("keywords", []):
		if not _data["keywords"].has(kw):
			err.call("keyword desconhecida \"%s\"" % kw)
	for s in cd.get("species", []):
		if not _data.get("species", {}).has(s):
			err.call("espécie desconhecida \"%s\"" % s)
	if cd.has("rapidez") and int(cd["rapidez"]) not in [1, 2, 3]:
		err.call("rapidez precisa ser \"rapidez:1\" a \"rapidez:3\" em keywords")
	if cd.has("critico") and int(cd["critico"]) not in [1, 2, 3, 4]:
		err.call("crítico precisa ser \"critico:1\" a \"critico:4\" em keywords")
	if cd.has("speed") and cd["speed"] not in SPEEDS:
		err.call("speed desconhecida \"%s\"" % cd["speed"])
	# Súbito: "subito" is the full cost of summoning it outside your own idle Main Phase
	if cd.has("subito") and (type != "unit" or int(cd["subito"]) <= int(cd.get("cost", 0))):
		err.call("subito precisa ser uma unidade com custo Súbito maior que o custo normal")
	if cd.has("transform") and not _data["cards"].has(cd["transform"].get("into", "")):
		err.call("transform.into inexistente \"%s\"" % cd["transform"].get("into", ""))
	if cd.has("art_crop"):
		var crop = cd["art_crop"]
		if not crop is Dictionary:
			err.call("art_crop precisa ser um objeto {x, y, zoom}")
		else:
			for crop_key in crop:
				if crop_key not in ["x", "y", "zoom"]:
					err.call("art_crop: campo desconhecido \"%s\"" % crop_key)
			for focus_key in ["x", "y"]:
				if crop.has(focus_key) and not (float(crop[focus_key]) >= 0.0 and float(crop[focus_key]) <= 1.0):
					err.call("art_crop.%s precisa ficar entre 0 e 1" % focus_key)
			if crop.has("zoom") and float(crop["zoom"]) < 1.0:
				err.call("art_crop.zoom precisa ser pelo menos 1")
	_validate_effects(err, cd.get("effects", []))
	if cd.has("activated"):
		var act: Dictionary = cd["activated"]
		if not act.has("cost"):
			err.call("activated sem \"cost\"")
		if act.has("speed") and act["speed"] not in SPEEDS:
			err.call("activated.speed desconhecida \"%s\"" % act["speed"])
		if act.get("exhaust", false) and type != "unit":
			err.call("activated.exhaust só pode ser usado por unidades; artefatos usam once_per_turn")
		_validate_effects(err, act.get("effects", []))
	if cd.has("equip_from_field"):
		var equip_action: Dictionary = cd["equip_from_field"]
		if type != "artifact" or not (cd.get("subtypes", []) as Array).is_empty():
			err.call("equip_from_field só pode ser usado por artefatos sem subtipo")
		if not equip_action.has("cost"):
			err.call("equip_from_field sem \"cost\"")
		if equip_action.has("speed") and equip_action["speed"] not in SPEEDS:
			err.call("equip_from_field.speed desconhecida \"%s\"" % equip_action["speed"])
		_validate_effects(err, equip_action.get("effects", []))
	for e in cd.get("deck_effects", []):
		if e.get("action", "") not in DECK_ACTIONS:
			err.call("deck_effects: action desconhecida \"%s\"" % e.get("action", ""))
		_check_trigger_if(err, e)

static func _validate_leader(lid: String, ld: Dictionary) -> void:
	var err := func(msg: String): _errors.append("líder %s: %s" % [lid, msg])
	for field in ["name", "hp", "incarnation", "ability"]:
		if not ld.has(field):
			err.call("falta \"%s\"" % field)
	if not _data["cards"].has(ld.get("incarnation", "")):
		err.call("incarnation inexistente \"%s\"" % ld.get("incarnation", ""))
	elif not is_incarnation_option(lid, String(ld["incarnation"])):
		err.call("incarnation precisa ser uma unidade Campeã ou Lendária com o nome do Líder")
	for e in ld.get("essences", []):
		if not _data["essences"].has(e):
			err.call("essência desconhecida \"%s\"" % e)
	var ab: Dictionary = ld.get("ability", {})
	if ab.has("trigger") and not _data["triggers"].has(ab["trigger"]):
		err.call("ability.trigger desconhecido \"%s\"" % ab["trigger"])
	if ab.has("speed") and ab["speed"] not in SPEEDS:
		err.call("ability.speed desconhecida \"%s\"" % ab["speed"])
	_validate_effects(err, ab.get("effects", []))

static func _validate_effects(err: Callable, effects: Array) -> void:
	for e in effects:
		if not e is Dictionary:
			err.call("efeito não é objeto: %s" % str(e))
			continue
		var action: String = e.get("action", "")
		if not EffectRegistry.is_known(action):
			err.call("action desconhecida \"%s\"" % action)
		if action not in EffectRegistry.STATIC_ACTIONS:
			if not e.has("target"):
				err.call("efeito \"%s\" sem target" % action)
			elif not TargetRegistry.is_known(String(e["target"])):
				err.call("target desconhecido \"%s\"" % e["target"])
		_check_trigger_if(err, e)
		for kw in e.get("keywords", []):
			if not _data["keywords"].has(kw):
				err.call("keyword desconhecida \"%s\" em efeito" % kw)
		if action == "restrict_play" or e.has("restriction"):
			var restriction_problem := PlayRestriction.error_of(e.get("restriction", null), _data["essences"])
			if restriction_problem != "":
				err.call(restriction_problem)
		if action == "summon" and e.get("card", "self") != "self" and not _data["cards"].has(e["card"]):
			err.call("summon de carta inexistente \"%s\"" % e["card"])
		_validate_effects(err, e.get("then", []))

static func _check_trigger_if(err: Callable, e: Dictionary) -> void:
	if e.has("trigger") and not _data["triggers"].has(e["trigger"]):
		err.call("trigger desconhecido \"%s\"" % e["trigger"])
	if e.has("listen"):
		_check_listen(err, e)
	if e.has("if"):
		var problem := ConditionRegistry.error_of(e["if"])
		if problem != "":
			err.call(problem)

## The "listen" form: {"listen": event, "scope": ..., "zones": [...] | "any", "when": {...}}.
static func _check_listen(err: Callable, e: Dictionary) -> void:
	if e.has("trigger"):
		err.call("efeito com \"listen\" não pode ter \"trigger\"")
	if e["listen"] not in GameEvent.LISTENABLE:
		err.call("listen desconhecido \"%s\"" % e["listen"])
	if e.get("scope", "any") not in Effect.SCOPES:
		err.call("scope desconhecido \"%s\"" % e["scope"])
	var zones: Variant = e.get("zones", ["board"])
	if zones is String:
		if zones != "any":
			err.call("zones texto só aceita \"any\", não \"%s\"" % zones)
	elif zones is Array:
		for zone in zones:
			if zone not in TriggerBus.ZONES and zone != TriggerBus.SANCTUARY and zone != TriggerBus.EQUIPPED:
				err.call("zona desconhecida \"%s\"" % zone)
	if not e.get("when", {}) is Dictionary:
		err.call("when precisa ser um objeto")

static func card(id: String) -> Dictionary:
	return data()["cards"][id]

## Card data with a summoned instance's overrides (atk, hp, keywords, effects, text...) applied.
static func card_for(id: String, inst: Dictionary = {}) -> Dictionary:
	var cd: Dictionary = data()["cards"][id]
	var over: Dictionary = inst.get("over", {})
	if over.is_empty():
		return cd
	var m := cd.duplicate()
	m.merge(over, true)
	for field in over:
		if over[field] == null:
			m.erase(field) # a null override removes the field (a silenced unit loses its abilities)
	return m

static func leader(id: String) -> Dictionary:
	return data()["leaders"][id]

## True for a Leader's own champion card (cast from the Command Zone).
## Artifacts are a card type of their own; equipment is an artifact subtype.
static func is_artifact(cd: Dictionary) -> bool:
	return cd.get("type", "") == "artifact"

static func is_equipment(cd: Dictionary) -> bool:
	return is_artifact(cd) and cd.get("subtypes", []).has("equipment")

## "Local": a free-standing artifact that is a place on the field (Baluarte Santo). Only a label, no rule of its own.
static func is_local(cd: Dictionary) -> bool:
	return is_artifact(cd) and cd.get("subtypes", []).has("local")

## A free-standing artifact (an artifact that is not Equipar): it stays on its owner's side of the
## field, taking one of the BOARD_LIMIT slots, until an effect destroys it. It never fights.
static func is_relic(cd: Dictionary) -> bool:
	return is_artifact(cd) and not is_equipment(cd)

static func is_leader_card(id: String) -> bool:
	for lid in data()["leaders"]:
		if is_incarnation_option(String(lid), id):
			return true
	return false

## A Leader's Encarnação is a Champion or Legendary unit whose printed name is the Leader's name, optionally
## followed by a comma and a title (e.g. "Voltexz, Raio Obliterador"). This lets future versions
## of a character be chosen without classifying every Leader's card as globally undraftable.
static func is_incarnation_option(leader_id: String, card_id: String) -> bool:
	if not data()["leaders"].has(leader_id) or not data()["cards"].has(card_id):
		return false
	var cd: Dictionary = card(card_id)
	if String(cd.get("type", "")) != "unit" or not ["champion", "legendary"].has(String(cd.get("rarity", ""))):
		return false
	var leader_name := String(data()["leaders"][leader_id].get("name", "")).strip_edges().to_lower()
	var card_name := String(cd.get("name", "")).strip_edges().to_lower()
	return card_name == leader_name or card_name.begins_with(leader_name + ",")

## All same-entity Encarnação choices, in display-name order. The configured default should always
## be among these; retain it as a recovery option for older/temporarily incomplete catalogs.
static func incarnation_options(leader_id: String) -> Array[String]:
	var options: Array[String] = []
	if not data()["leaders"].has(leader_id):
		return options
	for card_id in data()["cards"]:
		if is_incarnation_option(leader_id, String(card_id)):
			options.append(String(card_id))
	var default_id := String(data()["leaders"][leader_id].get("incarnation", ""))
	if options.is_empty() and data()["cards"].has(default_id):
		options.append(default_id)
	options.sort_custom(func(first: String, second: String) -> bool:
		return String(card(first).get("name", first)).naturalnocasecmp_to(String(card(second).get("name", second))) < 0)
	return options

static func keyword(id: String) -> Dictionary:
	return data()["keywords"][id]

static func essence(id: String) -> Dictionary:
	return data()["essences"][id]

## A card's essences: "essence" is one id or an Array of ids (dual cards, e.g. natureza + trevas).
static func essences_of(cd: Dictionary) -> Array:
	var e: Variant = cd.get("essence", "neutra")
	return (e as Array).duplicate() if e is Array else [String(e)]

static func has_essence(cd: Dictionary, id: String) -> bool:
	return essences_of(cd).has(id)

## Display name of a card's domains ("Natureza / Trevas").
static func essence_names(cd: Dictionary) -> String:
	var names: Array = []
	for id in essences_of(cd):
		names.append(essence(id).get("name", id))
	return " / ".join(names)

## Display name of a Leader's domains. A Leader keeps them under "essences" (a card uses "essence"),
## so essence_names() would read a Leader as neutral.
static func leader_essence_names(leader_data: Dictionary) -> String:
	var names: Array = []
	for id in leader_data.get("essences", ["neutra"]):
		names.append(essence(id).get("name", id))
	return " / ".join(names)

static func element(id: String) -> Dictionary:
	return data()["elements"][id]

## A card's elements: "element" is one id, an Array of ids, or missing (many cards have none).
## The element carries tribal synergies and innate immunities; it does not affect deckbuilding.
static func elements_of(cd: Dictionary) -> Array:
	var e: Variant = cd.get("element", [])
	return (e as Array).duplicate() if e is Array else ([String(e)] if String(e) != "" else [])

static func has_element(cd: Dictionary, id: String) -> bool:
	return elements_of(cd).has(id)

## Display name of a card's elements ("Água / Gelo"); empty when it has none.
static func element_names(cd: Dictionary) -> String:
	var names: Array = []
	for id in elements_of(cd):
		names.append(element(id).get("name", id))
	return " / ".join(names)

## The one-line label written on the card face (species strip): species and element side by side
## ("HUMANO · GELO"). A spell or artifact has no species, so it shows just the element ("Gelo").
## The element is plain lettering on purpose: it must not be confused with the domain badge.
static func species_and_element_label(cd: Dictionary) -> String:
	var parts: Array = []
	if species_names(cd) != "":
		parts.append(species_names(cd))
	if element_names(cd) != "":
		parts.append(element_names(cd))
	return " · ".join(parts)

## Flavor text is cosmetic only, so its roll uses its own RNG and never touches the match RNG.
static var _flavor_rng := RandomNumberGenerator.new()
static var _flavor_salt := 0

## Call at the start of each match: every card then shows one fixed line for the whole match.
static func reroll_flavor() -> void:
	_flavor_salt = _flavor_rng.randi()

## "flavor" is a String or an Array of Strings; the first entry is the card's main line.
static func flavor_lines(cd: Dictionary) -> Array:
	var f: Variant = cd.get("flavor", "")
	var lines: Array = (f as Array).duplicate() if f is Array else [String(f)]
	return lines.filter(func(s): return String(s) != "")

## The main line outside a match; during a match, the line picked for it ("" if the card has none).
static func flavor_for(cd: Dictionary, in_match := false) -> String:
	var lines := flavor_lines(cd)
	if lines.is_empty():
		return ""
	if not in_match or lines.size() == 1:
		return lines[0]
	return lines[hash("%s|%d" % [cd.get("name", ""), _flavor_salt]) % lines.size()]

## Display name of a card's species ("Humano / Dragão"), or its visual-only override.
static func species_names(cd: Dictionary) -> String:
	var display_label := String(cd.get("species_display", "")).strip_edges()
	if not display_label.is_empty():
		return display_label
	var names: Array = []
	for id in cd.get("species", []):
		names.append(data().get("species", {}).get(id, {}).get("name", id))
	return " / ".join(names)
