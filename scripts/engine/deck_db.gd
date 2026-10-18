class_name DeckDB
extends RefCounted
## Prebuilt decks, one file each in data/decks/prebuilt/<id>.json.
## Fields: name, description, order (grid position), leader, cards {card_id: copies}.

## Cards that are drawn: the deck list without the Encarnação, which waits in the Sanctuary instead.
const DECK_SIZE := 44
const MAX_COPIES := 3
## Legendary cards default to fewer copies than the rest; a card can still override with "max_copies".
const MAX_LEGENDARY_COPIES := 2
## Champions + legendaries together (counting copies) in one deck.
const MAX_ELITE_CARDS := 20
## Cards outside the Leader's essences (neutral ones don't count); champions can never be off-essence.
const MAX_OFF_ESSENCE := 12
## Off-essence cards must all share one of at most this many "secondary essences" the player picks.
## A neutral Leader picks them like any other: every non-neutral card is off-essence for it.
const MAX_SECONDARY_ESSENCES := 2
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

## Total number of cards in the deck list: DECK_SIZE plus the Encarnação (the Leader is not counted).
static func card_count(id: String) -> int:
	var total := 0
	var cards: Dictionary = get_deck(id)["cards"]
	for cid in cards:
		total += int(cards[cid])
	return total

## The deck list in the order the files are kept: printed cost (lowest first), then units before
## spells and other types, then card id. Used by tools/sort_decks.gd and checked by the tests.
static func sorted_cards(cards: Dictionary) -> Dictionary:
	var card_ids: Array = cards.keys()
	card_ids.sort_custom(_comes_before)
	var sorted: Dictionary = {}
	for card_id in card_ids:
		sorted[card_id] = cards[card_id]
	return sorted

static func _comes_before(first_id: String, second_id: String) -> bool:
	var first_card := CardDB.card(first_id)
	var second_card := CardDB.card(second_id)
	var first_cost := int(first_card.get("cost", 0))
	var second_cost := int(second_card.get("cost", 0))
	if first_cost != second_cost:
		return first_cost < second_cost
	var first_type := CardDB.TYPES.find(first_card.get("type", ""))
	var second_type := CardDB.TYPES.find(second_card.get("type", ""))
	if first_type != second_type:
		return first_type < second_type
	return first_id < second_id

## Returns a list of rule violations; empty means the deck is legal.
static func validate(deck_id: String) -> Array[String]:
	var d := get_deck(deck_id)
	return validate_cards(d["leader"], d["cards"])

## Same check for any {card_id: copies} list under the given Leader.
static func validate_cards(leader_id: String, cards: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var ld := CardDB.leader(leader_id)
	var total := 0 # cards that are drawn, so the Encarnação is not counted
	var off_essence := 0
	var off_essence_sets: Array = [] # the essences of each distinct off-essence card
	var elite_cards := 0
	for id in cards:
		var n: int = cards[id]
		if id != ld["legendary"]:
			total += n
		var c := CardDB.card(id)
		var rarity: String = c.get("rarity", "")
		var default_limit := MAX_LEGENDARY_COPIES if rarity == "legendary" else MAX_COPIES
		var limit: int = int(c.get("max_copies", default_limit)) # "max_copies": 1 = Única
		if rarity == "champion" or rarity == "legendary":
			elite_cards += n
		if n > limit:
			errors.append("%s: mais de %d cópia%s" % [id, limit, "" if limit == 1 else "s"])
		# dual cards count as on-essence when the Leader shares any of their essences
		var ess := CardDB.essences_of(c)
		var legal := ess.has("neutra")
		for e in ess:
			legal = legal or ld["essences"].has(e)
		if not legal:
			off_essence += n
			off_essence_sets.append(ess)
			if c.get("rarity", "") == "champion":
				errors.append("%s: Campeão não pode ser de fora da essência do Líder" % id)
		if c.get("transform_only", false):
			errors.append("%s: só entra em jogo por transformação" % id)
		if c.get("undraftable", false):
			errors.append("%s: não pode entrar no deck (só é colocada em jogo por um efeito)" % id)
		if CardDB.is_leader_card(id) and id != ld["legendary"]:
			errors.append("%s: Encarnação de outro Líder" % id)
	if off_essence > MAX_OFF_ESSENCE:
		errors.append("%d cartas de fora da essência do Líder (máximo %d)" % [off_essence, MAX_OFF_ESSENCE])
	_check_secondary_essences(off_essence_sets, errors)
	if elite_cards > MAX_ELITE_CARDS:
		errors.append("%d Campeões + Lendárias (máximo %d)" % [elite_cards, MAX_ELITE_CARDS])
	if total != DECK_SIZE:
		errors.append("deck tem %d cartas fora a Encarnação (precisa de %d)" % [total, DECK_SIZE])
	if int(cards.get(ld["legendary"], 0)) != 1:
		errors.append("o deck precisa de exatamente 1 Encarnação do Líder (%s)" % ld["legendary"])
	return errors

## Off-essence cards must be covered by at most MAX_SECONDARY_ESSENCES essences: every one of them has
## to carry at least one of the chosen secondary essences (a dual card may satisfy it with either half).
## The choice is not stored, so it is enough that some valid choice exists.
static func _check_secondary_essences(off_essence_sets: Array, errors: Array[String]) -> void:
	if off_essence_sets.is_empty():
		return
	var candidates: Array[String] = []
	for ess in off_essence_sets:
		for e in ess:
			if not candidates.has(e):
				candidates.append(e)
	for first_index in candidates.size():
		if _covers_all(off_essence_sets, [candidates[first_index]]):
			return
		for second_index in range(first_index + 1, candidates.size()):
			if _covers_all(off_essence_sets, [candidates[first_index], candidates[second_index]]):
				return
	errors.append("cartas de fora da essência do Líder precisam compartilhar uma de até %d essências secundárias" % MAX_SECONDARY_ESSENCES)

static func _covers_all(off_essence_sets: Array, chosen: Array) -> bool:
	for ess in off_essence_sets:
		var covered := false
		for e in chosen:
			covered = covered or ess.has(e)
		if not covered:
			return false
	return true
