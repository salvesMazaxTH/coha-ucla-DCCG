class_name DeckEffect
extends Effect
## Effects that open a deck choice after their trigger resolves, told apart by `action`:
## "search_deck": the player picks a matching card from the deck.
##   Filters (read by GameState._begin_search): essence, element, max_cost, type, types_any (one of several types), tribe,
##   card_ids (only those named cards), top (only the N cards on top of the deck are searched; the player must take
##   one eligible card and the looked-at cards not taken go, shuffled among themselves, to the bottom of the deck
##   instead of a shuffle. If none is eligible the player still sees the cards and the only way out is to
##   shuffle the deck, then `fallback_draw` still applies). Without "top" the whole deck is searched: the player sees the entire deck in its order (top first), must take an
##   eligible card (declining is refused) and the deck is shuffled afterwards; a whiff shows the deck dimmed with the
##   same "shuffle the deck" exit. Keep that for very narrow filters (a single named card, like Bruno's Bola de Neve);
##   a broad filter over the whole deck is too strong.
## "discard_hand_pick": the player picks one card from their own hand and discards it to
##   the graveyard (only the end-of-turn hand limit banishes; a normal discard goes to the graveyard).
##   `who` (default "self"): "opponent" makes the OPPONENT pick the card from their own hand (Calvin Sem-Face); an empty hand does nothing.
## "discard_if_over" (Soren): BOTH players holding MORE than `limit` cards (default 4) discard `amount` (default 1) cards
##   from their own hand to the graveyard. The controller chooses first, then the opponent; a player at the limit or below discards nothing.
## "enemy_sacrifice_pick" (Censo de Baixas): the OPPONENT picks one unit they control and sacrifices it (it dies, no Escudo
##   Supremo, Ao Morrer still triggers). With exactly one unit it is sacrificed without asking; with none nothing happens.
## "summon_hand_pick": the player picks a unit card of the given `rarity` (e.g. "champion"; "" = any) from
##   their own hand and it enters the board for free. It is banished when the turn ends.
## "grave_retrieve": the player picks a copy of `card_id` (or of any card in the `card_ids` list) from their own
## graveyard and takes it to the hand;
##   that card is BANISHED once it has been cast (the price of getting a second use out of it).
## "grave_to_hand" (Rebobinar): the player may pick ONE card from their own graveyard that passes the card filter (any
##   CardFilter key: type, types_any, tribe_any, element, max_cost, any_of...; no filter = any card) and takes it to the
##   hand, or takes none. `cost_increase` (default 0) makes that copy cost that much more from now on. The card is not banished.
## "grave_copy_to_hand": the player picks a card from their graveyard that passes the card filter; a fresh copy goes to
##   their hand and costs 0 for the rest of the current turn. The original card stays in the graveyard.
## "enemy_hand_bottom" (Bob Veyr): the player may pick ONE card from the OPPONENT'S hand (only the player sees it) and it goes to the
##   bottom of the opponent's deck, or takes none. If the card is a unit, the player discards `discard_if_unit` (default 0)
##   cards from their own hand (as many as they have). Any other card costs nothing.
##   `discard_cost` (Vesper, default 0): the player also discards that many cards from their own hand for ANY card sent.
##   `exclude_type` (Vesper, default "" = none): cards of that type are shown but cannot be picked (the player still sees the whole hand).
## "enemy_hand_tax" (Cornélia Aldrovane): the same look at the OPPONENT'S hand, but the picked card stays where it is and costs
##   `cost_increase` more while it stays in the hand (it ends when the card is played or leaves the hand). The player may pick none.
##   `only_type` (Rex Farejador, default "" = any): only cards of that type can be picked (the whole hand is still shown).
## "hand_to_bottom" (Wendell Comportão): the player may pick ONE card from their own hand and put it at the bottom of their own deck.
##   If they do, they draw `draw_after` cards (default 1). Picking none does nothing.
## "look_top": the player looks at the top `count` cards and takes one; the rest go to the
##   bottom (or the deck is shuffled, with "shuffle": true).
## "look_top_to_reservoir" (Agiota das Nuvens): the player sees the top card of their deck, then chooses to put either
##   that card or the bottom card (unseen) into their Reservoir. The choice is mandatory; an empty deck does nothing.
## "look_bottom" (Dragar): `count` cards (default 2) drawn at random from the bottom `window` cards of the deck
##   (default 5) are looked at privately; the player takes one to the hand (revealed to everyone) and the others
##   stay in the deck where they were.

var count := 4
var shuffle := false
var window := 5 ## look_bottom: how many cards at the bottom of the deck the looked-at ones are drawn from

func _read_parameters(data: Dictionary) -> void:
	count = int(data.get("count", 2 if action == "look_bottom" else 4))
	window = int(data.get("window", 5))
	shuffle = bool(data.get("shuffle", false))

func opens_choice() -> bool:
	return true

func open_choice(context: EffectContext) -> void:
	if action == "discard_hand_pick":
		var opponent_discards: bool = String(raw.get("who", "self")) == "opponent"
		if opponent_discards:
			context.game._begin_hand_discard(context.game.opponent(context.controller), context.self_uid, true)
		else:
			context.game._begin_hand_discard(context.controller, context.self_uid)
	elif action == "discard_if_over":
		context.game._begin_discard_if_over(context.controller, int(raw.get("limit", 4)), int(raw.get("amount", 1)), context.self_uid)
	elif action == "enemy_sacrifice_pick":
		context.game._begin_enemy_sacrifice(context.opponent(), context.self_uid)
	elif action == "summon_hand_pick":
		context.game._begin_hand_summon(context.controller, String(raw.get("rarity", "")), context.self_uid)
	elif action == "grave_retrieve":
		var wanted_ids: Array = raw.get("card_ids", [str(raw.get("card_id", ""))])
		context.game._begin_grave_retrieve(context.controller, wanted_ids, context.self_uid)
	elif action == "grave_to_hand":
		context.game._begin_grave_to_hand(context.controller, raw, context.self_uid)
	elif action == "grave_copy_to_hand":
		context.game._begin_grave_copy_to_hand(context.controller, raw, context.self_uid)
	elif action == "enemy_hand_bottom":
		context.game._begin_enemy_hand_bottom(context.controller, int(raw.get("discard_if_unit", 0)), context.self_uid, String(raw.get("exclude_type", "")), int(raw.get("discard_cost", 0)))
	elif action == "enemy_hand_tax":
		context.game._begin_enemy_hand_bottom(context.controller, 0, context.self_uid, "", 0, int(raw.get("cost_increase", 1)), String(raw.get("only_type", "")))
	elif action == "hand_to_bottom":
		context.game._begin_own_hand_bottom(context.controller, int(raw.get("draw_after", 1)), context.self_uid)
	elif action == "look_top":
		context.game._begin_look(context.controller, count, context.self_uid, shuffle)
	elif action == "look_top_to_reservoir":
		context.game._begin_reservoir_look(context.controller, context.self_uid)
	elif action == "look_bottom":
		context.game._begin_look_bottom(context.controller, count, window, context.self_uid)
	else:
		context.game._begin_search(context.controller, raw, context.self_uid)
