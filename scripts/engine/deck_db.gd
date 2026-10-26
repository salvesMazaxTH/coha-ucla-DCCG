class_name DeckDB
extends RefCounted
## Prebuilt decks, one file each in data/decks/prebuilt/<id>.json.
## Fields: name, description, order (grid position), leader, cards {card_id: copies}.
## Decks that are not files (the player's own, or the ones a match server received) are registered at
## run time under an id with a prefix; every function below that takes a deck id accepts them too.

## Cards that are drawn: the deck list without the Encarnação, which waits in the Sanctuary instead.
const DECK_SIZE := 44
const MAX_COPIES := 3
## Legendary cards default to fewer copies than the rest; a card can still override with "max_copies".
const MAX_LEGENDARY_COPIES := 2
## Champions + legendaries together (counting copies) in one deck.
const MAX_ELITE_CARDS := 20
## Guest cards: cards outside the Leader's domains (neutral ones don't count), of any rarity.
## They can come from any domains, in any mix, up to MAX_OFF_ESSENCE. If one domain appears in EVERY
## guest card (a multi-domain guest counts for each domain the Leader lacks), the cap rises to
## MAX_OFF_ESSENCE_SINGLE_DOMAIN: that shared domain works like a secondary domain.
## A neutral Leader has no domain, so every non-neutral card is a guest for it.
const MAX_OFF_ESSENCE := 10
const MAX_OFF_ESSENCE_SINGLE_DOMAIN := 15
const PREBUILT_DIR := "res://data/decks/prebuilt"
const SECTION_ESSENCE := "essencia"
const SECTION_SPECIAL := "especial"
## The player's own decks (built in MEUS DECKS) share the hub with the prebuilt ones.
const SECTION_MINE := "meus"
## Id prefixes of decks registered at run time: the player's own decks on this device, and the decks
## the match server received from the players of a room.
const PLAYER_PREFIX := "mine:"
const ROOM_PREFIX := "room:"
const MAX_CUSTOM_NAME := 60
const MAX_CUSTOM_DESCRIPTION := 400
const MAX_CUSTOM_COPIES := 99

static var _decks: Dictionary = {}
static var _ids: Array[String] = []
## Decks added at run time with register_custom, in the order they were registered.
static var _custom_decks: Dictionary = {}
static var _custom_ids: Array[String] = []

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

## Prebuilt deck ids in display order (decks registered at run time are not included: see custom_ids).
## A copy, so a caller that appends the player's own decks to it cannot corrupt the prebuilt list.
static func ids() -> Array[String]:
	_load()
	return _ids.duplicate()

## Which hub section a deck belongs to: "essencia" (the default: mono-essence decks that show off one
## essence), "especial" (decks built around a combo or a neutral Leader, with a splash of other essences)
## or "meus" (the player's own decks).
static func section_of(id: String) -> String:
	_load()
	if _custom_decks.has(id):
		return SECTION_MINE
	return String(_decks[id].get("section", SECTION_ESSENCE))

static func has(id: String) -> bool:
	_load()
	return _decks.has(id) or _custom_decks.has(id)

static func get_deck(id: String) -> Dictionary:
	_load()
	return _custom_decks[id] if _custom_decks.has(id) else _decks[id]

# ---------------------------------------------------------------- decks registered at run time

## Adds (or replaces) a deck that is not one of the prebuilt files, so the hub, the match and the deck
## list can use it like any other deck. The caller has already checked it is legal.
static func register_custom(id: String, deck_name: String, description: String, leader_id: String, cards: Dictionary) -> void:
	_load()
	if not _custom_decks.has(id):
		_custom_ids.append(id)
	var copies: Dictionary = {}
	for card_id in cards:
		copies[String(card_id)] = int(cards[card_id])
	_custom_decks[id] = {
		"name": deck_name,
		"description": description,
		"leader": leader_id,
		"cards": sorted_cards(copies),
	}

## Removes every registered deck whose id starts with `prefix` (PLAYER_PREFIX / ROOM_PREFIX).
static func clear_custom(prefix: String) -> void:
	for id in _custom_ids.duplicate():
		if id.begins_with(prefix):
			_custom_decks.erase(id)
			_custom_ids.erase(id)

## Ids of the registered decks that start with `prefix`, in registration order.
static func custom_ids(prefix: String) -> Array[String]:
	var matching: Array[String] = []
	for id in _custom_ids:
		if id.begins_with(prefix):
			matching.append(id)
	return matching

## Checks a deck that arrived from outside (a client talking to the match server) and cleans it.
## Returns {"deck": {name, description, leader, cards}, "errors": [String]}; the deck may be used only
## when errors is empty. Nothing in `raw` is trusted: unknown cards, Leader cards that are not the
## Leader's own Encarnação, tokens and odd copy counts are all errors.
static func check_incoming(raw: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not raw is Dictionary:
		return {"deck": {}, "errors": ["deck ausente ou malformado"] as Array[String]}
	var leader_id := String(raw.get("leader", ""))
	if not CardDB.data()["leaders"].has(leader_id):
		return {"deck": {}, "errors": ["Líder desconhecido"] as Array[String]}
	var cards: Dictionary = {}
	var raw_cards: Variant = raw.get("cards", {})
	if not raw_cards is Dictionary:
		return {"deck": {}, "errors": ["lista de cartas malformada"] as Array[String]}
	var incarnation_id := String(CardDB.leader(leader_id)["incarnation"])
	for card_id in raw_cards:
		var id := String(card_id)
		var copies_value: Variant = raw_cards[card_id]
		if not (copies_value is int or copies_value is float):
			errors.append("%s: quantidade inválida" % id)
			continue
		var copies := int(copies_value)
		if not CardDB.data()["cards"].has(id):
			errors.append("%s: carta desconhecida" % id)
		elif copies < 1 or copies > MAX_CUSTOM_COPIES:
			errors.append("%s: quantidade inválida" % id)
		elif id != incarnation_id and not is_deckable(id):
			errors.append("%s: não pode entrar no deck" % id)
		else:
			cards[id] = copies
	var deck_name := String(raw.get("name", "")).strip_edges().left(MAX_CUSTOM_NAME)
	var deck := {
		"name": deck_name if deck_name != "" else "Deck sem nome",
		"description": String(raw.get("description", "")).left(MAX_CUSTOM_DESCRIPTION),
		"leader": leader_id,
		"cards": cards,
	}
	if errors.is_empty():
		errors.append_array(validate_cards(leader_id, cards))
	return {"deck": deck, "errors": errors}

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

## Most copies of one card a deck may hold ("max_copies": 1 = Única).
static func copy_limit(card_id: String) -> int:
	var c := CardDB.card(card_id)
	var default_limit := MAX_LEGENDARY_COPIES if c.get("rarity", "") == "legendary" else MAX_COPIES
	return int(c.get("max_copies", default_limit))

## The card's domains the Leader lacks. A card of several domains is on-domain only when the Leader's
## Incarnation has ALL of them; a neutral card never counts as a guest. Empty = not a guest card.
static func missing_domains(leader_id: String, card_id: String) -> Array:
	var leader_domains: Array = CardDB.leader(leader_id)["essences"]
	var card_domains := CardDB.essences_of(CardDB.card(card_id))
	if card_domains.has("neutra"):
		return []
	return card_domains.filter(func(domain): return not leader_domains.has(domain))

static func is_guest(leader_id: String, card_id: String) -> bool:
	return not missing_domains(leader_id, card_id).is_empty()

## Strictly the Leader's own domain: every domain of the card is one the Leader has. Unlike a non-guest,
## a neutral card does not pass (unless the Leader itself is neutral), because neutral fits any deck.
static func is_in_leader_domain(leader_id: String, card_id: String) -> bool:
	var leader_domains: Array = CardDB.leader(leader_id)["essences"]
	var card_domains := CardDB.essences_of(CardDB.card(card_id))
	return card_domains.all(func(domain): return leader_domains.has(domain))

## Cards a player may put in a deck by hand: not a Leader's own card (the Encarnação is added by the
## Leader), not a token and not one that only enters play through an effect or a transformation.
static func is_deckable(card_id: String) -> bool:
	var c := CardDB.card(card_id)
	return not (CardDB.is_leader_card(card_id) or c.get("token", false) or c.get("undraftable", false) or c.get("transform_only", false))

## The totals the deck rules are written in, for any {card_id: copies} list under the given Leader:
##   total              cards that are drawn (the Encarnação is not counted)
##   elite              Champions + Legendaries, counting copies
##   off_essence        guest cards, counting copies
##   guest_limit        how many guest cards are allowed right now (rises when one domain is in every guest card)
##   shared_guest_domain  true when such a domain exists
##   incarnation        copies of the Leader's Encarnação in the list
static func stats(leader_id: String, cards: Dictionary) -> Dictionary:
	var ld := CardDB.leader(leader_id)
	var total := 0
	var elite_cards := 0
	var off_essence := 0
	# domains that appear in every guest card so far; null until the first guest card is seen
	var shared_guest_domains: Variant = null
	for id in cards:
		var n: int = cards[id]
		if id != ld["incarnation"]:
			total += n
		var rarity: String = CardDB.card(id).get("rarity", "")
		if rarity == "champion" or rarity == "legendary":
			elite_cards += n
		var missing := missing_domains(leader_id, id)
		if not missing.is_empty():
			off_essence += n
			if shared_guest_domains == null:
				shared_guest_domains = missing
			else:
				shared_guest_domains = shared_guest_domains.filter(func(domain): return missing.has(domain))
	var has_shared_domain: bool = shared_guest_domains != null and not shared_guest_domains.is_empty()
	return {
		"total": total,
		"elite": elite_cards,
		"off_essence": off_essence,
		"guest_limit": MAX_OFF_ESSENCE_SINGLE_DOMAIN if has_shared_domain else MAX_OFF_ESSENCE,
		"shared_guest_domain": has_shared_domain,
		"incarnation": int(cards.get(ld["incarnation"], 0)),
	}

## Same check for any {card_id: copies} list under the given Leader.
static func validate_cards(leader_id: String, cards: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var ld := CardDB.leader(leader_id)
	for id in cards:
		var n: int = cards[id]
		var c := CardDB.card(id)
		var limit := copy_limit(id)
		if n > limit:
			errors.append("%s: mais de %d cópia%s" % [id, limit, "" if limit == 1 else "s"])
		if c.get("transform_only", false):
			errors.append("%s: só entra em jogo por transformação" % id)
		if c.get("undraftable", false):
			errors.append("%s: não pode entrar no deck (só é colocada em jogo por um efeito)" % id)
		if CardDB.is_leader_card(id) and id != ld["incarnation"]:
			errors.append("%s: Encarnação de outro Líder" % id)
	var totals := stats(leader_id, cards)
	if totals["off_essence"] > totals["guest_limit"]:
		if totals["shared_guest_domain"]:
			errors.append("%d cartas de fora do domínio do Líder (máximo %d)" % [totals["off_essence"], MAX_OFF_ESSENCE_SINGLE_DOMAIN])
		else:
			errors.append("%d cartas de fora do domínio do Líder (máximo %d; até %d se todas forem de um mesmo domínio)" % [totals["off_essence"], MAX_OFF_ESSENCE, MAX_OFF_ESSENCE_SINGLE_DOMAIN])
	if totals["elite"] > MAX_ELITE_CARDS:
		errors.append("%d Campeões + Lendárias (máximo %d)" % [totals["elite"], MAX_ELITE_CARDS])
	if totals["total"] != DECK_SIZE:
		errors.append("deck tem %d cartas fora a Encarnação (precisa de %d)" % [totals["total"], DECK_SIZE])
	if totals["incarnation"] != 1:
		errors.append("o deck precisa de exatamente 1 Encarnação do Líder (%s)" % ld["incarnation"])
	return errors
