class_name CardDB
extends RefCounted
## Static card catalog loaded from data/cards.json and data/cards/<essence>/*.json.

const DECK_SIZE := 48
const MAX_COPIES := 3

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/cards.json", FileAccess.READ)
		_data = JSON.parse_string(f.get_as_text())
		_data["cards"] = {}
		for essence_id in _data["essences"]:
			var dir_path: String = "res://data/cards/" + str(essence_id)
			if not DirAccess.dir_exists_absolute(dir_path):
				continue
			for file_name in DirAccess.get_files_at(dir_path):
				if not file_name.ends_with(".json"):
					continue
				var card_file := FileAccess.open(dir_path + "/" + file_name, FileAccess.READ)
				if card_file:
					_data["cards"][file_name.trim_suffix(".json")] = JSON.parse_string(card_file.get_as_text())
	return _data

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

static func deck(id: String) -> Dictionary:
	return data()["decks"][id]

static func keyword(id: String) -> Dictionary:
	return data()["keywords"][id]

static func essence(id: String) -> Dictionary:
	return data()["essences"][id]

## Returns a list of rule violations; empty means the deck is legal.
static func validate_deck(deck_id: String) -> Array[String]:
	var errors: Array[String] = []
	var d := deck(deck_id)
	var ld := leader(d["leader"])
	var total := 0
	for id in d["cards"]:
		var n: int = d["cards"][id]
		total += n
		var c := card(id)
		if n > MAX_COPIES:
			errors.append("%s: mais de %d cópias" % [id, MAX_COPIES])
		if c["essence"] != "neutra" and not ld["essences"].has(c["essence"]):
			errors.append("%s: essência fora da identidade do Líder" % id)
		if c["rarity"] == "legendary" and id != ld["legendary"]:
			errors.append("%s: Lendário diferente do Líder" % id)
	if total != DECK_SIZE:
		errors.append("deck tem %d cartas (precisa de %d)" % [total, DECK_SIZE])
	if not d["cards"].has(ld["legendary"]):
		errors.append("falta o Campeão Lendário %s" % ld["legendary"])
	return errors
