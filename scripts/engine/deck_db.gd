class_name DeckDB
extends RefCounted
## Prebuilt decks, one file each in data/decks/prebuilt/<id>.json.
## Fields: name, description, order (grid position), leader, cards {card_id: copies}.

const DECK_SIZE := 48
const MAX_COPIES := 3
const PREBUILT_DIR := "res://data/decks/prebuilt"

static var _decks: Dictionary = {}
static var _ids: Array[String] = []

static func _load() -> void:
	if not _decks.is_empty():
		return
	for file_name in DirAccess.get_files_at(PREBUILT_DIR):
		if not file_name.ends_with(".json"):
			continue
		var f := FileAccess.open(PREBUILT_DIR + "/" + file_name, FileAccess.READ)
		if f == null:
			continue
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			_decks[file_name.trim_suffix(".json")] = parsed
	var ids: Array[String] = []
	for id in _decks:
		ids.append(String(id))
	ids.sort_custom(func(a: String, b: String) -> bool:
		var oa: int = int(_decks[a].get("order", 999))
		var ob: int = int(_decks[b].get("order", 999))
		return oa < ob if oa != ob else a < b)
	_ids = ids

## Prebuilt deck ids in display order.
static func ids() -> Array[String]:
	_load()
	return _ids

static func has(id: String) -> bool:
	_load()
	return _decks.has(id)

static func get_deck(id: String) -> Dictionary:
	_load()
	return _decks[id]

## Total number of cards in the deck list (the Leader is not counted).
static func card_count(id: String) -> int:
	var total := 0
	var cards: Dictionary = get_deck(id)["cards"]
	for cid in cards:
		total += int(cards[cid])
	return total

## Returns a list of rule violations; empty means the deck is legal.
static func validate(deck_id: String) -> Array[String]:
	var errors: Array[String] = []
	var d := get_deck(deck_id)
	var ld := CardDB.leader(d["leader"])
	var total := 0
	for id in d["cards"]:
		var n: int = d["cards"][id]
		total += n
		var c := CardDB.card(id)
		if n > MAX_COPIES:
			errors.append("%s: mais de %d cópias" % [id, MAX_COPIES])
		# dual cards are legal when the Leader shares any of their essences
		var ess := CardDB.essences_of(c)
		var legal := ess.has("neutra")
		for e in ess:
			legal = legal or ld["essences"].has(e)
		if not legal:
			errors.append("%s: essência fora da identidade do Líder" % id)
		if CardDB.is_leader_card(id) and id != ld["legendary"]:
			errors.append("%s: Encarnação de outro Líder" % id)
	if total != DECK_SIZE:
		errors.append("deck tem %d cartas (precisa de %d)" % [total, DECK_SIZE])
	if not d["cards"].has(ld["legendary"]):
		errors.append("falta a Encarnação do Líder %s" % ld["legendary"])
	return errors
