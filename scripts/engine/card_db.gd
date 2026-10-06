class_name CardDB
extends RefCounted
## Static card catalog loaded from data/cards.json.

const DECK_SIZE := 48
const MAX_COPIES := 3

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/cards.json", FileAccess.READ)
		_data = JSON.parse_string(f.get_as_text())
	return _data

static func card(id: String) -> Dictionary:
	return data()["cards"][id]

static func leader(id: String) -> Dictionary:
	return data()["leaders"][id]

static func deck(id: String) -> Dictionary:
	return data()["decks"][id]

static func keyword(id: String) -> Dictionary:
	return data()["keywords"][id]

static func element(id: String) -> Dictionary:
	return data()["elements"][id]

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
		if c["element"] != "neutral" and not ld["elements"].has(c["element"]):
			errors.append("%s: afinidade fora da identidade do Líder" % id)
		if c["rarity"] == "legendary" and id != ld["legendary"]:
			errors.append("%s: Lendário diferente do Líder" % id)
	if total != DECK_SIZE:
		errors.append("deck tem %d cartas (precisa de %d)" % [total, DECK_SIZE])
	if not d["cards"].has(ld["legendary"]):
		errors.append("falta o Campeão Lendário %s" % ld["legendary"])
	return errors
