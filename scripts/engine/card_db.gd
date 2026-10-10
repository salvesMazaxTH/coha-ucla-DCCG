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

static func _load() -> void:
	_errors.clear()
	_defs.clear()
	_data = _read_json("res://data/cards.json")
	if _data.is_empty():
		_data = {"essences": {}, "triggers": {}, "species": {}, "keywords": {}, "leaders": {}}
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
	for kw in cd.get("keywords", []):
		if not _data["keywords"].has(kw):
			err.call("keyword desconhecida \"%s\"" % kw)
	for s in cd.get("species", []):
		if not _data.get("species", {}).has(s):
			err.call("espécie desconhecida \"%s\"" % s)
	if cd.has("speed") and cd["speed"] not in SPEEDS:
		err.call("speed desconhecida \"%s\"" % cd["speed"])
	if cd.has("transform") and not _data["cards"].has(cd["transform"].get("into", "")):
		err.call("transform.into inexistente \"%s\"" % cd["transform"].get("into", ""))
	_validate_effects(err, cd.get("effects", []))
	if cd.has("activated"):
		var act: Dictionary = cd["activated"]
		if not act.has("cost"):
			err.call("activated sem \"cost\"")
		if act.has("speed") and act["speed"] not in SPEEDS:
			err.call("activated.speed desconhecida \"%s\"" % act["speed"])
		_validate_effects(err, act.get("effects", []))
	for e in cd.get("deck_effects", []):
		if e.get("action", "") not in DECK_ACTIONS:
			err.call("deck_effects: action desconhecida \"%s\"" % e.get("action", ""))
		_check_trigger_if(err, e)

static func _validate_leader(lid: String, ld: Dictionary) -> void:
	var err := func(msg: String): _errors.append("líder %s: %s" % [lid, msg])
	for field in ["name", "hp", "legendary", "ability"]:
		if not ld.has(field):
			err.call("falta \"%s\"" % field)
	if not _data["cards"].has(ld.get("legendary", "")):
		err.call("legendary inexistente \"%s\"" % ld.get("legendary", ""))
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
			if zone not in TriggerBus.ZONES:
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
	return m

static func leader(id: String) -> Dictionary:
	return data()["leaders"][id]

## True for a Leader's own champion card (cast from the Command Zone).
## Artifacts are a card type of their own; equipment is an artifact subtype.
static func is_artifact(cd: Dictionary) -> bool:
	return cd.get("type", "") == "artifact"

static func is_equipment(cd: Dictionary) -> bool:
	return is_artifact(cd) and cd.get("subtypes", []).has("equipment")

static func is_leader_card(id: String) -> bool:
	for lid in data()["leaders"]:
		if data()["leaders"][lid]["legendary"] == id:
			return true
	return false

static func keyword(id: String) -> Dictionary:
	return data()["keywords"][id]

static func essence(id: String) -> Dictionary:
	return data()["essences"][id]

## A card's essences: "essence" is one id or an Array of ids (dual cards, e.g. aquática + glacial).
static func essences_of(cd: Dictionary) -> Array:
	var e: Variant = cd.get("essence", "neutra")
	return (e as Array).duplicate() if e is Array else [String(e)]

static func has_essence(cd: Dictionary, id: String) -> bool:
	return essences_of(cd).has(id)

## Display name of a card's essences ("Aquática / Glacial").
static func essence_names(cd: Dictionary) -> String:
	var names: Array = []
	for id in essences_of(cd):
		names.append(essence(id).get("name", id))
	return " / ".join(names)

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

## Display name of a card's species ("Humano / Dragão"); empty when it has none.
static func species_names(cd: Dictionary) -> String:
	var names: Array = []
	for id in cd.get("species", []):
		names.append(data().get("species", {}).get(id, {}).get("name", id))
	return " / ".join(names)
