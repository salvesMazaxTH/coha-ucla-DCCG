class_name DeckEffect
extends Effect
## Effects that open a deck choice after their trigger resolves, told apart by `action`:
## "search_deck": the player picks a matching card from the deck.
##   Filters (read by GameState._begin_search): essence, max_cost, type, types_any (one of several types), species, tags (all of them),
##   tags_any (at least one of them), top (only the N cards on top of the deck are searched; the matches
##   are revealed to everyone and the looked-at cards not taken go to the bottom of the deck instead of
##   a shuffle). Without "top" the whole deck is searched: keep that for very narrow filters (a single named
##   card, like Bruno's Bola de Neve); a broad filter over the whole deck is too strong.
## "discard_hand_pick": the player picks one card from their own hand and discards it to
##   the graveyard (only the end-of-turn hand limit banishes; a normal discard goes to the graveyard).
## "summon_hand_pick": the player picks a unit card of the given `rarity` (e.g. "champion"; "" = any) from
##   their own hand and it enters the board for free. It is banished when the turn ends.
## "grave_retrieve": the player picks a copy of `card_id` (or of any card in the `card_ids` list) from their own
## graveyard and takes it to the hand;
##   that card is BANISHED once it has been cast (the price of getting a second use out of it).
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
	elif action == "summon_hand_pick":
		context.game._begin_hand_summon(context.controller, String(raw.get("rarity", "")), context.self_uid)
	elif action == "grave_retrieve":
		var wanted_ids: Array = raw.get("card_ids", [str(raw.get("card_id", ""))])
		context.game._begin_grave_retrieve(context.controller, wanted_ids, context.self_uid)
	elif action == "look_top":
		context.game._begin_look(context.controller, count, context.self_uid, shuffle)
	else:
		context.game._begin_search(context.controller, raw, context.self_uid)
