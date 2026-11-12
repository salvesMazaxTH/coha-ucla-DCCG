class_name DeckDB
extends RefCounted
## Prebuilt decks, one file each in data/decks/prebuilt/<id>.json.
## Fields: name, description, order (grid position), leader, cards {card_id: copies}.
## Decks that are not files (the player's own, or the ones a match server received) are registered at
## run time under an id with a prefix; every function below that takes a deck id accepts them too.

## Cards that are drawn: the deck list without the Encarnação, which waits in the Sanctuary instead.
const DECK_SIZE := 59
const MAX_COPIES := 4
## Legendary cards have a lower copy limit; exceptional cards can override it.
const MAX_LEGENDARY_COPIES := 3
## Champions together (counting copies) in one deck.
const MAX_ELITE_CARDS := 24
## Deck domains. A deck uses at most MAX_DOMAINS domains: the Leader's own plus any others (a neutral
## Leader counts Neutro as its domain, so it adds at most 2 real ones). A card of several domains that has
## one of the Leader's counts only as the Leader's. Neutral cards never add a domain.
## Main domain: at least MAIN_DOMAIN_MIN cards of the deck (60 with the Encarnação) are of the Leader's
## domain. A neutral Leader may make any one domain its main one, Neutro included.
const MAX_DOMAINS := 3
const MAIN_DOMAIN_MIN := (DECK_SIZE + 1) / 2 + 1
const PREBUILT_DIR := "res://data/decks/prebuilt"
const SECTION_LEADERS := "essencia"
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

static func development_mode_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--dev")

static func is_card_visible(card_id: String) -> bool:
	return development_mode_enabled() or not bool(CardDB.card(card_id).get("unreleased", false))

static func is_leader_visible(leader_id: String) -> bool:
	if not CardDB.data()["leaders"].has(leader_id):
		return false
	return development_mode_enabled() or not bool(CardDB.leader(leader_id).get("unreleased", false))

static func visible_leader_ids() -> Array[String]:
	var visible: Array[String] = []
	for leader_id in CardDB.data()["leaders"]:
		if is_leader_visible(String(leader_id)):
			visible.append(String(leader_id))
	return visible

static func is_deck_visible(deck_id: String) -> bool:
	if not has(deck_id):
		return false
	if development_mode_enabled():
		return true
	var deck: Dictionary = get_deck(deck_id)
	return not bool(deck.get("unreleased", false)) and is_leader_visible(String(deck.get("leader", "")))

## A banned Leader ("banned": true in its data/leaders file) is still listed everywhere, marked BANIDO, but cannot be
## picked or played unless the game runs in development mode. This is a rule for the menus and the match
## server only: validate_cards / GameState stay unaware of it so the tests can keep building these decks.
static func is_leader_banned(leader_id: String) -> bool:
	if development_mode_enabled() or not CardDB.data()["leaders"].has(leader_id):
		return false
	return bool(CardDB.leader(leader_id).get("banned", false))

## A banned card ("banned": true in its data/cards file) works like a banned Leader: still listed, marked BANIDO,
## but it cannot go into a deck unless the game runs in development mode. Same scope: menus and match server only.
static func is_card_banned(card_id: String) -> bool:
	if development_mode_enabled() or not CardDB.data()["cards"].has(card_id):
		return false
	return bool(CardDB.card(card_id).get("banned", false))

## True when any card of a {card_id: copies} list is banned.
static func has_banned_card(cards: Dictionary) -> bool:
	for card_id in cards:
		if is_card_banned(String(card_id)):
			return true
	return false

## A deck is banned when its Leader is (the prebuilt deck and any deck the player builds around that Leader)
## or when it holds a banned card.
static func is_deck_banned(deck_id: String) -> bool:
	if not has(deck_id):
		return false
	var deck: Dictionary = get_deck(deck_id)
	return is_leader_banned(String(deck["leader"])) or has_banned_card(deck.get("cards", {}))

static func available_ids() -> Array[String]:
	var available: Array[String] = []
	for deck_id in ids():
		if is_deck_visible(deck_id):
			available.append(deck_id)
	return available

## Which hub section a deck belongs to: "essencia" (the default: ESSENCIAIS, exactly one prebuilt deck
## per Leader) or "meus" (the player's own decks).
static func section_of(id: String) -> String:
	_load()
	if _custom_decks.has(id):
		return SECTION_MINE
	return String(_decks[id].get("section", SECTION_LEADERS))

static func has(id: String) -> bool:
	_load()
	return _decks.has(id) or _custom_decks.has(id)

static func get_deck(id: String) -> Dictionary:
	_load()
	return _custom_decks[id] if _custom_decks.has(id) else _decks[id]

# ---------------------------------------------------------------- decks registered at run time

## Adds (or replaces) a deck that is not one of the prebuilt files, so the hub, the match and the deck
## list can use it like any other deck. The caller has already checked it is legal.
static func register_custom(
	id: String,
	deck_name: String,
	description: String,
	leader_id: String,
	cards: Dictionary,
	incarnation_id := "",
) -> void:
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
		"incarnation_id": resolved_incarnation_id(leader_id, incarnation_id),
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
## Returns {"deck": {name, description, leader, incarnation_id, cards}, "errors": [String]}; the deck
## may be used only when errors is empty. Nothing in `raw` is trusted: unknown cards, an Encarnação
## that does not share the Leader's name, tokens and odd copy counts are all errors.
static func check_incoming(raw: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not raw is Dictionary:
		return {"deck": {}, "errors": ["deck ausente ou malformado"] as Array[String]}
	var leader_id := String(raw.get("leader", ""))
	if not CardDB.data()["leaders"].has(leader_id):
		return {"deck": {}, "errors": ["Líder desconhecido"] as Array[String]}
	if is_leader_banned(leader_id):
		return {"deck": {}, "errors": ["Líder banido"] as Array[String]}
	var cards: Dictionary = {}
	var raw_cards: Variant = raw.get("cards", {})
	if not raw_cards is Dictionary:
		return {"deck": {}, "errors": ["lista de cartas malformada"] as Array[String]}
	var requested_incarnation := String(raw.get("incarnation_id", ""))
	if requested_incarnation != "" and not CardDB.is_incarnation_option(leader_id, requested_incarnation):
		errors.append("%s não pode ser a Encarnação deste Líder" % requested_incarnation)
	var incarnation_id := resolved_incarnation_id(leader_id, requested_incarnation)
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
		elif id != incarnation_id and not is_deckable(id, leader_id):
			errors.append("%s: não pode entrar no deck" % id)
		elif is_card_banned(id):
			errors.append("%s: carta banida" % id)
		else:
			cards[id] = copies
	var deck_name := String(raw.get("name", "")).strip_edges().left(MAX_CUSTOM_NAME)
	var deck := {
		"name": deck_name if deck_name != "" else "Deck sem nome",
		"description": String(raw.get("description", "")).left(MAX_CUSTOM_DESCRIPTION),
		"leader": leader_id,
		"incarnation_id": incarnation_id,
		"cards": cards,
	}
	if errors.is_empty():
		errors.append_array(validate_cards(leader_id, cards, incarnation_id))
	return {"deck": deck, "errors": errors}

## Total number of cards in the deck list: DECK_SIZE plus the Encarnação (the Leader is not counted).
static func card_count(id: String) -> int:
	var total := 0
	var cards: Dictionary = get_deck(id)["cards"]
	for cid in cards:
		total += int(cards[cid])
	return total

## Unique domains represented by a deck, the most numerous first (copies of the deck carrying each
## domain; a dual card counts for both). Ties follow CardDB.DOMAIN_ORDER. The Leader's domains always
## appear, even with no card of them. The Encarnação is included even in old deck records that omit it
## from the card-count dictionary.
static func domains_in(leader_id: String, cards: Dictionary, selected_incarnation_id := "") -> Array[String]:
	var copies_by_domain: Dictionary = {}
	if CardDB.data()["leaders"].has(leader_id):
		for domain in CardDB.leader_essences(CardDB.leader(leader_id)):
			copies_by_domain[String(domain)] = 0
	for card_id in cards:
		var copies := int(cards[card_id])
		if copies <= 0 or not CardDB.data()["cards"].has(String(card_id)):
			continue
		for domain in CardDB.essences_of(CardDB.card(String(card_id))):
			copies_by_domain[String(domain)] = int(copies_by_domain.get(String(domain), 0)) + copies
	if leader_id != "" and CardDB.data()["leaders"].has(leader_id):
		var incarnation_id := resolved_incarnation_id(leader_id, selected_incarnation_id)
		if CardDB.data()["cards"].has(incarnation_id) and not cards.has(incarnation_id):
			for domain in CardDB.essences_of(CardDB.card(incarnation_id)):
				copies_by_domain[String(domain)] = int(copies_by_domain.get(String(domain), 0)) + 1
	var ordered: Array[String] = []
	for domain in copies_by_domain:
		ordered.append(String(domain))
	ordered.sort_custom(func(first_id: String, second_id: String) -> bool:
		if copies_by_domain[first_id] != copies_by_domain[second_id]:
			return copies_by_domain[first_id] > copies_by_domain[second_id]
		return CardDB.domain_rank(first_id) < CardDB.domain_rank(second_id))
	return ordered

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
	return validate_cards(d["leader"], d["cards"], String(d.get("incarnation_id", "")))

## Resolve a saved/manual choice while keeping decks written before incarnation selection compatible.
static func resolved_incarnation_id(leader_id: String, selected_id := "") -> String:
	if selected_id != "" and CardDB.is_incarnation_option(leader_id, selected_id):
		return selected_id
	return String(CardDB.leader(leader_id).get("incarnation", ""))

## Most copies of one card a deck may hold, including explicit exceptions.
static func copy_limit(card_id: String) -> int:
	var c := CardDB.card(card_id)
	var default_limit := MAX_LEGENDARY_COPIES if c.get("rarity", "") == "legendary" else MAX_COPIES
	return int(c.get("max_copies", default_limit))

## A card that brings a domain the Leader lacks: it is not neutral and none of its domains is the Leader's.
static func is_outside_leader_domain(leader_id: String, card_id: String) -> bool:
	var card_domains := CardDB.essences_of(CardDB.card(card_id))
	return not card_domains.has("neutra") and not is_in_leader_domain(leader_id, card_id)

## Every way of choosing `size` items from `items`, each way as an array in the original order.
static func _combinations(items: Array, size: int) -> Array:
	if size == 0:
		return [[]]
	var result: Array = []
	for index in range(items.size() - size + 1):
		for rest in _combinations(items.slice(index + 1), size - 1):
			result.append([items[index]] + rest)
	return result

## Whether every card group (a {"domains", "copies"} dictionary) has at least one domain in `deck_domains`.
static func _all_groups_fit(deck_domains: Array, groups: Array) -> bool:
	return groups.all(func(group): return group["domains"].any(func(domain): return deck_domains.has(domain)))

## Which domains the deck uses and whether that is allowed. Returns:
##   domains       the deck's domains (the Leader's plus the ones other cards bring; empty when invalid)
##   mode          "ok" or "invalid"
##   error         why it is invalid ("" when it is not)
##   main_domains  the main domain (the Leader's domains; for a neutral Leader, its best domain)
##   main_copies   cards of the main domain, the Encarnação included
## The Encarnação is a card of the list like any other. The deck is invalid as soon as the cards outside
## the main domain no longer leave room for MAIN_DOMAIN_MIN of it, so a complete deck that is not
## invalid always reaches the minimum.
static func domain_check(leader_id: String, cards: Dictionary) -> Dictionary:
	var leader_domains: Array = CardDB.leader(leader_id)["essences"].filter(func(domain): return domain != "neutra")
	var neutral_leader := leader_domains.is_empty()
	var groups: Array = []
	var total_copies := 0
	var main_copies := 0
	var copies_by_domain: Dictionary = {}
	for card_id in cards:
		var copies := int(cards[card_id])
		if copies <= 0:
			continue
		total_copies += copies
		var card_domains := CardDB.essences_of(CardDB.card(card_id))
		for domain in card_domains:
			copies_by_domain[domain] = int(copies_by_domain.get(domain, 0)) + copies
		if card_domains.any(func(domain): return leader_domains.has(domain)):
			main_copies += copies
		elif not card_domains.has("neutra"):
			groups.append({"domains": card_domains, "copies": copies})
	var main_domains: Array = leader_domains
	if neutral_leader:
		var best_domain := "neutra"
		for domain in CardDB.DOMAIN_ORDER:
			if int(copies_by_domain.get(domain, 0)) > int(copies_by_domain.get(best_domain, 0)):
				best_domain = domain
		main_domains = [best_domain]
		main_copies = int(copies_by_domain.get(best_domain, 0))
	var result := {"domains": [], "mode": "invalid", "error": "", "main_domains": main_domains, "main_copies": main_copies}
	# a neutral Leader's own domain (Neutro) takes one of the MAX_DOMAINS places
	var other_domains_allowed := MAX_DOMAINS - maxi(1, leader_domains.size())
	var other_domains: Array = CardDB.DOMAIN_ORDER.filter(func(domain): return domain != "neutra" and not leader_domains.has(domain))
	var domains_found := false
	for size in range(0, other_domains_allowed + 1):
		for candidate in _combinations(other_domains, size):
			if not domains_found and _all_groups_fit(candidate, groups):
				result["domains"] = leader_domains + candidate
				domains_found = true
	if not domains_found:
		result["error"] = "o deck usa domínios demais (máximo %d, contando o do Líder)" % MAX_DOMAINS
		return result
	var room_outside_main := DECK_SIZE + 1 - MAIN_DOMAIN_MIN
	if total_copies - main_copies > room_outside_main:
		result["error"] = "o domínio principal precisa de %d cartas, e as outras já passam de %d" % [MAIN_DOMAIN_MIN, room_outside_main]
		return result
	result["mode"] = "ok"
	return result

## Strictly the Leader's own domain: at least one domain of the card is one the Leader has. Unlike a
## non-guest, a neutral card does not pass (unless the Leader itself is neutral), because neutral fits any deck.
static func is_in_leader_domain(leader_id: String, card_id: String) -> bool:
	var leader_domains: Array = CardDB.leader(leader_id)["essences"]
	var card_domains := CardDB.essences_of(CardDB.card(card_id))
	return card_domains.any(func(domain): return leader_domains.has(domain))

## Cards a player may put in a deck by hand. With no Leader context, canonical Encarnações are
## conservatively reserved; when a Leader is supplied, the other Leaders' Champions are draftable.
## Tokens and cards that only enter through effects or transformations are never draftable.
static func is_deckable(card_id: String, leader_id := "") -> bool:
	var c := CardDB.card(card_id)
	var leader_card_blocked := CardDB.is_leader_card(card_id) and leader_id == ""
	return not (leader_card_blocked or c.get("token", false) or c.get("undraftable", false) or c.get("transform_only", false))

## The totals the deck rules are written in, for any {card_id: copies} list under the given Leader:
##   total              cards that are drawn (one selected Encarnação copy is not counted)
##   elite              Champions, counting copies
##   domain_mode        "ok" or "invalid" (see domain_check)
##   deck_domains       the domains the deck uses (empty when invalid)
##   domain_error       why the domains are not allowed ("" when they are)
##   main_domains       the main domain and main_copies, its cards (see domain_check)
##   incarnation        copies of the Leader's Encarnação in the list
static func stats(leader_id: String, cards: Dictionary, selected_incarnation_id := "") -> Dictionary:
	var incarnation_id := resolved_incarnation_id(leader_id, selected_incarnation_id)
	var total := 0
	var elite_cards := 0
	for id in cards:
		var n: int = cards[id]
		total += n
		if String(id) == incarnation_id and n > 0:
			total -= 1 # reserve exactly one physical copy; other copies stay in the draw deck
		var rarity: String = CardDB.card(id).get("rarity", "")
		if rarity == "champion":
			elite_cards += n
	var domain_result := domain_check(leader_id, cards)
	return {
		"total": total,
		"elite": elite_cards,
		"domain_mode": domain_result["mode"],
		"deck_domains": domain_result["domains"],
		"domain_error": domain_result["error"],
		"main_domains": domain_result["main_domains"],
		"main_copies": domain_result["main_copies"],
		"incarnation": int(cards.get(incarnation_id, 0)),
	}

## Same check for any {card_id: copies} list under the given Leader.
static func validate_cards(leader_id: String, cards: Dictionary, selected_incarnation_id := "") -> Array[String]:
	var errors: Array[String] = []
	var incarnation_id := resolved_incarnation_id(leader_id, selected_incarnation_id)
	if selected_incarnation_id != "" and not CardDB.is_incarnation_option(leader_id, selected_incarnation_id):
		errors.append("%s não pode ser a Encarnação deste Líder" % selected_incarnation_id)
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
	var incarnation_copies := int(cards.get(incarnation_id, 0))
	if incarnation_copies > 1:
		errors.append("A Encarnação escolhida só pode ter 1 cópia (%d encontradas)" % incarnation_copies)
	var totals := stats(leader_id, cards, incarnation_id)
	if totals["domain_error"] != "":
		errors.append(totals["domain_error"])
	if totals["elite"] > MAX_ELITE_CARDS:
		errors.append("%d Campeões (máximo %d)" % [totals["elite"], MAX_ELITE_CARDS])
	if totals["total"] != DECK_SIZE:
		errors.append("deck tem %d cartas fora a Encarnação (precisa de %d)" % [totals["total"], DECK_SIZE])
	if totals["incarnation"] == 0:
		errors.append("o deck precisa de exatamente 1 Encarnação do Líder (%s)" % incarnation_id)
	return errors
