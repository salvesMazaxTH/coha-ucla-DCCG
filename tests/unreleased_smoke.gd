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
	_test_layla_release_flags()
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

func _test_layla_release_flags() -> void:
	var deck := DeckDB.get_deck("layla")
	var dev_mode := DeckDB.development_mode_enabled()
	check(bool(deck.get("unreleased", false)), "Layla deck is marked unreleased")
	check(DeckDB.is_deck_visible("layla") == dev_mode, "Layla deck is only available in debug mode")
	check(DeckDB.available_ids().has("layla") == dev_mode, "Layla prebuilt deck is filtered from the hub outside debug mode")
	for card_id in deck["cards"]:
		var id := String(card_id)
		var set_number := int(CardDB.card(id).get("set", 0))
		var should_be_unreleased := set_number != 1
		check(bool(CardDB.card(id).get("unreleased", false)) == should_be_unreleased,
			"Layla deck card %s follows its set release status" % id)
		check(DeckDB.is_card_visible(id) == (dev_mode or not should_be_unreleased),
			"Layla deck card %s visibility follows debug mode" % id)
