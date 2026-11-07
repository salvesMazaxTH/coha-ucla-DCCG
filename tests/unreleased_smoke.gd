extends SceneTree
## Run with and without --dev to check release visibility gates.

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func _init() -> void:
	_test_card_visibility()
	_test_deck_visibility()
	_test_released_decks_hold_only_released_cards()
	if failures == 0:
		print("Unreleased visibility smoke tests passed (dev=%s)." % DeckDB.development_mode_enabled())
	quit(failures)

func _test_card_visibility() -> void:
	var card_id := String(CardDB.data()["cards"].keys()[0])
	var card := CardDB.card(card_id)
	var had_flag: bool = card.has("unreleased")
	var previous: Variant = card.get("unreleased", false)
	card["unreleased"] = true
	var should_show := DeckDB.development_mode_enabled()
	check(DeckDB.is_card_visible(card_id) == should_show, "card availability follows the debug launch flag")
	var catalog := CardCatalog.new()
	check(catalog.filtered_ids([card_id]).has(card_id) == should_show, "card catalog hides or reveals unreleased cards")
	if had_flag:
		card["unreleased"] = previous
	else:
		card.erase("unreleased")

func _test_deck_visibility() -> void:
	var deck_id := DeckDB.ids()[0]
	var deck := DeckDB.get_deck(deck_id)
	var had_flag: bool = deck.has("unreleased")
	var previous: Variant = deck.get("unreleased", false)
	deck["unreleased"] = true
	var should_show := DeckDB.development_mode_enabled()
	check(DeckDB.is_deck_visible(deck_id) == should_show, "deck availability follows the debug launch flag")
	check(DeckDB.available_ids().has(deck_id) == should_show, "available deck list hides or reveals unreleased decks")
	if had_flag:
		deck["unreleased"] = previous
	else:
		deck.erase("unreleased")

## A prebuilt deck that players can see must not hold a card they are not allowed to see yet.
## This replaces the old Layla-only test, which pinned "her deck and every set 2 card are unreleased" and went stale
## the day she was released: what it really protected (shipping a deck before its cards) is checked here for every deck.
## It reads the "unreleased" flags straight from the data instead of asking DeckDB, so it also means something with --dev.
func _test_released_decks_hold_only_released_cards() -> void:
	for deck_id in DeckDB.ids():
		var deck := DeckDB.get_deck(deck_id)
		var leader_is_unreleased := bool(CardDB.leader(String(deck["leader"])).get("unreleased", false))
		var deck_is_in_development := bool(deck.get("unreleased", false)) or leader_is_unreleased
		if deck_is_in_development:
			continue  # Hidden from players, so it is allowed to hold unreleased cards while it is being built.
		for card_id in deck["cards"]:
			check(not bool(CardDB.card(String(card_id)).get("unreleased", false)),
				"released deck %s holds the unreleased card %s" % [deck_id, card_id])
