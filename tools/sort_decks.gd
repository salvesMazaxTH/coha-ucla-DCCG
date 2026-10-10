extends SceneTree
## Rewrites every prebuilt deck with its cards sorted by printed cost (see DeckDB.sorted_cards).
## Only the order of the lines changes, never the deck itself. Run it after editing a deck:
## Godot --headless --path . -s tools/sort_decks.gd

func _init() -> void:
	var changed_count := 0
	for deck_id in DeckDB.ids():
		var deck: Dictionary = DeckDB.get_deck(deck_id).duplicate()
		var sorted_deck_cards := DeckDB.sorted_cards(deck["cards"])
		# the JSON parser reads every number as a float, so turn them back into whole numbers
		# (otherwise the file would say "3.0" instead of "3")
		for card_id in sorted_deck_cards:
			sorted_deck_cards[card_id] = int(sorted_deck_cards[card_id])
		deck["cards"] = sorted_deck_cards
		deck["order"] = int(deck["order"])
		# the third argument keeps the keys (name, description, ...) in the file's own order
		var new_text := JSON.stringify(deck, "  ", false) + "
"
		var path := DeckDB.PREBUILT_DIR + "/" + deck_id + ".json"
		if FileAccess.get_file_as_string(path) == new_text:
			continue
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(new_text)
		changed_count += 1
		print("ordenado: ", deck_id)
	print("decks reescritos: %d" % changed_count)
	quit()
