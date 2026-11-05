class_name ModifyCostCardsEffect
extends Effect
## "modify_cost_cards": permanently changes the cost of EVERY matching card the controller owns in the "affected_zones"
## (by default hand and deck), by `amount` (negative = cheaper). It uses the same per-copy "cost_mod" as modify_cost,
## which is kept in every zone, so a card in the deck is already cheaper when it is drawn (Mali Magarc).
## "card_types" (empty = every card) and "card_filter" (any CardFilter key) narrow which cards are touched.
## "min_cost" stops a reduction at that cost, taking only what fits for each card: a card already at or below
## the floor is left alone, it is never raised.
## Example: {"action": "modify_cost_cards", "affected_zones": ["hand", "deck"], "card_types": ["spell"], "amount": -1, "min_cost": 1}.

var amount := 0
var affected_zones: Array = ["hand"]
var card_types: Array = []
var card_filter: Dictionary = {}
var min_cost := 0

func _read_parameters(data: Dictionary) -> void:
	amount = int(data.get("amount", 0))
	affected_zones = data.get("affected_zones", ["hand"])
	card_types = data.get("card_types", [])
	card_filter = data.get("card_filter", {})
	min_cost = int(data.get("min_cost", 0))

func apply(context: EffectContext, _target_uid: int) -> void:
	if amount == 0:
		return
	var game := context.game
	for zone_name in affected_zones:
		for card: Card in game.players[context.controller][String(zone_name)]:
			if _matches(card):
				game.add_cost_mod(context.controller, card, amount, min_cost)

func _matches(card: Card) -> bool:
	var card_data := CardDB.card(card.card_id)
	var type_matches := card_types.is_empty()
	for wanted_type in card_types:
		type_matches = type_matches or CardDB.has_type(card_data, String(wanted_type))
	return type_matches and (card_filter.is_empty() or CardFilter.matches(card.card_id, card_filter))
