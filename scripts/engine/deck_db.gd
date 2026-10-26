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

## Which hub section a deck belongs to: "essencia" (the default: mono-essence decks that show off one
## essence) or "especial" (decks built around a combo or a neutral Leader, with a splash of other essences).
static func section_of(id: String) -> String:
	_load()
	return String(_decks[id].get("section", SECTION_ESSENCE))

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
	# domains that appear in every guest card so far; null until the first guest card is seen
	var shared_guest_domains: Variant = null
	var elite_cards := 0
	for id in cards:
		var n: int = cards[id]
		if id != ld["incarnation"]:
			total += n
		var c := CardDB.card(id)
		var rarity: String = c.get("rarity", "")
		var default_limit := MAX_LEGENDARY_COPIES if rarity == "legendary" else MAX_COPIES
		var limit: int = int(c.get("max_copies", default_limit)) # "max_copies": 1 = Única
		if rarity == "champion" or rarity == "legendary":
			elite_cards += n
		if n > limit:
			errors.append("%s: mais de %d cópia%s" % [id, limit, "" if limit == 1 else "s"])
		# a card of several domains is on-domain only when the Leader's Incarnation has ALL of them
		var ess := CardDB.essences_of(c)
		var legal := ess.has("neutra")
		if not legal:
			legal = true
			for e in ess:
				legal = legal and ld["essences"].has(e)
		if not legal:
			off_essence += n
			var missing_domains: Array = ess.filter(func(domain): return not ld["essences"].has(domain))
			if shared_guest_domains == null:
				shared_guest_domains = missing_domains
			else:
				shared_guest_domains = shared_guest_domains.filter(func(domain): return missing_domains.has(domain))
		if c.get("transform_only", false):
			errors.append("%s: só entra em jogo por transformação" % id)
		if c.get("undraftable", false):
			errors.append("%s: não pode entrar no deck (só é colocada em jogo por um efeito)" % id)
		if CardDB.is_leader_card(id) and id != ld["incarnation"]:
			errors.append("%s: Encarnação de outro Líder" % id)
	var has_shared_domain: bool = shared_guest_domains != null and not shared_guest_domains.is_empty()
	var guest_limit := MAX_OFF_ESSENCE_SINGLE_DOMAIN if has_shared_domain else MAX_OFF_ESSENCE
	if off_essence > guest_limit:
		if has_shared_domain:
			errors.append("%d cartas de fora do domínio do Líder (máximo %d)" % [off_essence, MAX_OFF_ESSENCE_SINGLE_DOMAIN])
		else:
			errors.append("%d cartas de fora do domínio do Líder (máximo %d; até %d se todas forem de um mesmo domínio)" % [off_essence, MAX_OFF_ESSENCE, MAX_OFF_ESSENCE_SINGLE_DOMAIN])
	if elite_cards > MAX_ELITE_CARDS:
		errors.append("%d Campeões + Lendárias (máximo %d)" % [elite_cards, MAX_ELITE_CARDS])
	if total != DECK_SIZE:
		errors.append("deck tem %d cartas fora a Encarnação (precisa de %d)" % [total, DECK_SIZE])
	if int(cards.get(ld["incarnation"], 0)) != 1:
		errors.append("o deck precisa de exatamente 1 Encarnação do Líder (%s)" % ld["incarnation"])
	return errors
