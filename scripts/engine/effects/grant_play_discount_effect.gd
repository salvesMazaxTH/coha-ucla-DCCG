class_name GrantPlayDiscountEffect
extends Effect
## "grant_play_discount": for the rest of this turn, ONE card in the controller's hand that matches
## "card_filter" gets a discount on its current cost. The filter's cost limits use the printed cost.
## Two kinds of discount:
## - "reduction": the card costs that much less, never below "min_cost" (default 0). A card already cheaper
##   than "min_cost" is left as it is.
## - "divisor" (when there is no "reduction"): the card costs only 1/"divisor" of its current cost, rounded UP
##   (a cost-1 card still pays 1 with divisor 2 and a cost-5 card pays 3).
## The offer is a marker on the player (players[p]["play_discount"]): it is spent by the next
## card played that matches, and it expires at the end of the turn it was granted in. Granting it again
## in the same turn just refreshes the marker, it never stacks.
## Example (Sengoku, Peso dos Séculos): {"action": "grant_play_discount", "target": "none", "reduction": 2,
## "min_cost": 1, "card_filter": {"max_cost": 7, "tribe_any": ["dragao", "dragonoide"]}}.

var card_filter: Dictionary = {}
var divisor := 2
var reduction := 0
var min_cost := 0

func _read_parameters(data: Dictionary) -> void:
	card_filter = data.get("card_filter", {})
	divisor = maxi(1, int(data.get("divisor", 2)))
	reduction = maxi(0, int(data.get("reduction", 0)))
	min_cost = maxi(0, int(data.get("min_cost", 0)))

func apply(context: EffectContext, _target_uid: int) -> void:
	context.game.players[context.controller]["play_discount"] = offer(context.game.turn)

## The marker stored on the player for the given turn.
func offer(turn: int) -> Dictionary:
	return {
		"card_filter": card_filter,
		"divisor": divisor,
		"reduction": reduction,
		"min_cost": min_cost,
		"until_turn": turn,
	}

## The cost `current_cost` becomes under an offer made by `offer()`.
static func discounted_cost(current_cost: int, play_discount: Dictionary) -> int:
	var fixed_reduction := int(play_discount.get("reduction", 0))
	if fixed_reduction > 0:
		var floor_cost := mini(current_cost, int(play_discount.get("min_cost", 0)))
		return maxi(current_cost - fixed_reduction, floor_cost)
	return ceili(float(current_cost) / int(play_discount["divisor"]))
