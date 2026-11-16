class_name ProfileStats
extends RefCounted
## Turns the account's online match history (rows of deck_match_results, newest first) into the numbers
## the profile screen shows. The account's overall wins, losses and streaks are deliberately never
## computed (the profile must not show who wins more overall); results per deck, card and domain are.
## Matches recorded before the profile columns existed carry no deck snapshot:
## for those the deck's current content is used, and their card plays are unknown.

## Below this many games a domain's winrate only ranks after the domains that have enough games.
const MIN_GAMES_FOR_WINRATE := 3
const RECENT_MATCH_COUNT := 5

static func winrate(wins: int, games: int) -> float:
	return float(wins) / games if games > 0 else 0.0

## `account_decks` is SupabaseAuth.state.decks: the saved decks, used for old matches of "mine:" decks.
static func compute(rows: Array, account_decks: Array) -> Dictionary:
	var matches: Array = []
	for row in rows:
		if row is Dictionary and ["win", "loss", "draw"].has(String(row.get("result", ""))):
			matches.append(_match_from_row(row, account_decks))
	# Both seats of one match share a created_at (you against yourself), and the database may return
	# equal timestamps in any order, so the order is fixed here instead of trusting the rows.
	matches.sort_custom(_is_newer)
	var stats := {
		"games": matches.size(),
		"recent": matches.slice(0, RECENT_MATCH_COUNT),
		"tracked_play_games": 0,
		"known_deck_games": 0,
	}
	for match_info in matches:
		if match_info.plays_known:
			stats.tracked_play_games += 1
		if not match_info.cards.is_empty():
			stats.known_deck_games += 1
	_add_deck_and_leader(stats, matches)
	_add_favorite_cards(stats, matches)
	_add_domains(stats, matches)
	return stats

static func _is_newer(first: Dictionary, second: Dictionary) -> bool:
	if first.created_at != second.created_at:
		return first.created_at > second.created_at
	if first.deck_key != second.deck_key:
		return first.deck_key < second.deck_key
	return first.result < second.result

## One match in a common shape: {deck_key, result, created_at, leader_id, cards, plays, plays_known}.
## `cards` is empty when the deck is unknown (a saved deck that was deleted, for example).
static func _match_from_row(row: Dictionary, account_decks: Array) -> Dictionary:
	var deck_key := String(row.get("deck_key", ""))
	var leader_id := ""
	var cards := {}
	var deck_exists := not _current_deck(deck_key, account_decks).is_empty()
	if row.get("deck_cards") is Dictionary:
		cards = row.deck_cards
		leader_id = String(row.get("leader_id", "")) if row.get("leader_id") != null else ""
	else:
		var current_deck := _current_deck(deck_key, account_decks)
		cards = current_deck.get("cards", {})
		leader_id = String(current_deck.get("leader", ""))
	var plays: Variant = row.get("card_plays")
	return {
		"deck_key": deck_key,
		"deck_exists": deck_exists,
		"result": String(row.result),
		"created_at": String(row.get("created_at", "")),
		"leader_id": leader_id,
		"cards": cards,
		"plays": plays if plays is Dictionary else {},
		"plays_known": plays is Dictionary,
	}

## What the deck holds today: a prebuilt deck, a registered deck of the account, or a saved deck's content.
static func _current_deck(deck_key: String, account_decks: Array) -> Dictionary:
	if DeckDB.has(deck_key):
		return DeckDB.get_deck(deck_key)
	var saved_id := deck_key.trim_prefix(DeckDB.PLAYER_PREFIX)
	for saved_deck in account_decks:
		if saved_deck is Dictionary and String(saved_deck.get("id", "")) == saved_id and saved_deck.get("content") is Dictionary:
			return saved_deck.content
	return {}

## Most played deck and most played Leader, each as {key, games, wins}. Deleted decks never become
## the favorite deck.
static func _add_deck_and_leader(stats: Dictionary, matches: Array) -> void:
	var by_deck := {}
	var by_leader := {}
	for match_info in matches:
		if match_info.deck_exists:
			_tally(by_deck, match_info.deck_key, match_info.result)
		if match_info.leader_id != "":
			_tally(by_leader, match_info.leader_id, match_info.result)
	stats["favorite_deck"] = _most_played(by_deck)
	stats["favorite_leader"] = _most_played(by_leader)

static func _tally(totals: Dictionary, key: String, result: String) -> void:
	if not totals.has(key):
		# matches come newest first, so the smaller order is the one played most recently
		totals[key] = {"key": key, "games": 0, "wins": 0, "order": totals.size()}
	totals[key].games += 1
	if result == "win":
		totals[key].wins += 1

## The entry with the most games; a tie goes to the one played most recently, so the favorite only
## changes when a new match is played.
static func _most_played(totals: Dictionary) -> Dictionary:
	var best := {}
	for entry in totals.values():
		if best.is_empty() or _is_more_played(entry, best):
			best = entry
	return best

static func _is_more_played(entry: Dictionary, other: Dictionary) -> bool:
	if entry.games != other.games:
		return entry.games > other.games
	return entry.order < other.order

## The top 3 cards of the most played deck: most copies first, then the most plays, then the best
## winrate over the matches whose deck had the card.
static func _add_favorite_cards(stats: Dictionary, matches: Array) -> void:
	stats["favorite_cards"] = []
	var favorite_deck: Dictionary = stats.favorite_deck
	if favorite_deck.is_empty():
		return
	var deck_cards := {}
	for match_info in matches: # the newest known content of that deck
		if match_info.deck_key == favorite_deck.key and not match_info.cards.is_empty():
			deck_cards = match_info.cards
			break
	var plays_by_card := {}
	var record_by_card := {}
	for match_info in matches:
		for card_id in match_info.plays:
			plays_by_card[card_id] = int(plays_by_card.get(card_id, 0)) + int(match_info.plays[card_id])
		for card_id in match_info.cards:
			if int(match_info.cards[card_id]) > 0:
				_tally(record_by_card, String(card_id), match_info.result)
	var ranked: Array = []
	for card_id in deck_cards:
		if not CardDB.data()["cards"].has(String(card_id)):
			continue
		var record: Dictionary = record_by_card.get(String(card_id), {"games": 0, "wins": 0})
		ranked.append({
			"card_id": String(card_id),
			"copies": int(deck_cards[card_id]),
			"plays": int(plays_by_card.get(String(card_id), 0)),
			"games": record.games,
			"wins": record.wins,
		})
	ranked.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		if first.copies != second.copies:
			return first.copies > second.copies
		if first.plays != second.plays:
			return first.plays > second.plays
		var first_rate := winrate(first.wins, first.games)
		var second_rate := winrate(second.wins, second.games)
		if first_rate != second_rate:
			return first_rate > second_rate
		return first.card_id < second.card_id) # last resort: a full tie must not reorder between openings
	stats["favorite_cards"] = ranked.slice(0, 3)
	var most_played := {}
	for card_id in plays_by_card:
		if not CardDB.data()["cards"].has(String(card_id)):
			continue
		var plays := int(plays_by_card[card_id])
		if most_played.is_empty() or plays > most_played.plays or (plays == most_played.plays and String(card_id) < most_played.card_id):
			most_played = {"card_id": String(card_id), "plays": plays}
	stats["most_played_card"] = most_played

## Neutral is left out: almost every deck carries it. A match counts for a domain when the deck has at
## least one card of it or its Leader belongs to it. "Favorite" is the most matches; copies only break ties.
static func _add_domains(stats: Dictionary, matches: Array) -> void:
	var by_domain := {}
	for match_info in matches:
		var copies_by_domain := _copies_by_domain(match_info.leader_id, match_info.cards)
		for domain_id in copies_by_domain:
			if domain_id == "neutra":
				continue
			if not by_domain.has(domain_id):
				by_domain[domain_id] = {"domain_id": domain_id, "games": 0, "wins": 0, "copies": 0}
			by_domain[domain_id].games += 1
			by_domain[domain_id].copies += copies_by_domain[domain_id]
			if match_info.result == "win":
				by_domain[domain_id].wins += 1
	var domains: Array = by_domain.values()
	var by_use := domains.duplicate()
	by_use.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		if first.games != second.games:
			return first.games > second.games
		if first.copies != second.copies:
			return first.copies > second.copies
		return first.domain_id < second.domain_id)
	var by_rate := domains.duplicate()
	by_rate.sort_custom(_better_winrate)
	stats["favorite_domains"] = by_use.slice(0, 2)
	stats["best_domains"] = by_rate.slice(0, 2)
	stats["worst_domain"] = by_rate.back() if by_rate.size() > 2 else {}

## Domains with enough games come first; then the higher winrate; then more games.
static func _better_winrate(first: Dictionary, second: Dictionary) -> bool:
	var first_enough: bool = first.games >= MIN_GAMES_FOR_WINRATE
	var second_enough: bool = second.games >= MIN_GAMES_FOR_WINRATE
	if first_enough != second_enough:
		return first_enough
	var first_rate := winrate(first.wins, first.games)
	var second_rate := winrate(second.wins, second.games)
	if first_rate != second_rate:
		return first_rate > second_rate
	if first.games != second.games:
		return first.games > second.games
	return first.domain_id < second.domain_id

static func _copies_by_domain(leader_id: String, cards: Dictionary) -> Dictionary:
	var copies_by_domain := {}
	if CardDB.data()["leaders"].has(leader_id):
		for domain_id in CardDB.leader_essences(CardDB.leader(leader_id)):
			copies_by_domain[String(domain_id)] = 0
	for card_id in cards:
		if not CardDB.data()["cards"].has(String(card_id)):
			continue
		for domain_id in CardDB.essences_of(CardDB.card(String(card_id))):
			copies_by_domain[String(domain_id)] = int(copies_by_domain.get(String(domain_id), 0)) + int(cards[card_id])
	return copies_by_domain
