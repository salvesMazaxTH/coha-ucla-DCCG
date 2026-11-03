class_name GrantPlayDiscountEffect
extends Effect
## "grant_play_discount": for the rest of this turn, ONE card in the controller's hand that matches
## "card_filter" costs only 1/"divisor" of its current cost, rounded UP (the reduction is rounded down, so a
## cost-1 card still pays 1 with divisor 2 and a cost-5 card pays 3). The filter's cost limits use the printed cost.
## The offer is a marker on the player (players[p]["play_discount"]): it is spent by the next
## card played that matches, and it expires at the end of the turn it was granted in. Granting it again
## in the same turn just refreshes the marker, it never stacks.
## Example (Sengoku, Peso dos Séculos): {"action": "grant_play_discount", "target": "none", "divisor": 2,
## "card_filter": {"max_cost": 6, "tribe": "dragonoide"}}.

var card_filter: Dictionary = {}
var divisor := 2

func _read_parameters(data: Dictionary) -> void:
	card_filter = data.get("card_filter", {})
	divisor = maxi(1, int(data.get("divisor", 2)))

func apply(context: EffectContext, _target_uid: int) -> void:
	context.game.players[context.controller]["play_discount"] = {
		"card_filter": card_filter,
		"divisor": divisor,
		"until_turn": context.game.turn,
	}
