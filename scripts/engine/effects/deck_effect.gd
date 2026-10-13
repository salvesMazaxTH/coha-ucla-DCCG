class_name DeckEffect
extends Effect
## Effects that open a deck choice after their trigger resolves, told apart by `action`:
## "search_deck": the player picks a matching card from the deck.
##   Filters (read by GameState._begin_search): essence, max_cost, type, species, tags.
## "discard_hand_pick": the player picks one card from their own hand and discards it to
##   the graveyard (only the end-of-turn hand limit banishes; a normal discard goes to the graveyard).
## "look_top": the player looks at the top `count` cards and takes one; the rest go to the
##   bottom (or the deck is shuffled, with "shuffle": true).

var count := 4
var shuffle := false

func _read_parameters(data: Dictionary) -> void:
	count = int(data.get("count", 4))
	shuffle = bool(data.get("shuffle", false))

func opens_choice() -> bool:
	return true

func open_choice(context: EffectContext) -> void:
	if action == "discard_hand_pick":
		context.game._begin_hand_discard(context.controller, context.self_uid)
	elif action == "look_top":
		context.game._begin_look(context.controller, count, context.self_uid, shuffle)
	else:
		context.game._begin_search(context.controller, raw, context.self_uid)
