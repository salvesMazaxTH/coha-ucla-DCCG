class_name ReturnToHandEffect
extends Effect
## "return_to_hand": the target card goes back to its owner's hand (a bounce, or a card coming back from the graveyard).
## It is not a death: a unit sent back from the board has no Ao Morrer and no Aliado Morre, and its equipment is released.
## Use any unit target to bounce a unit, or "self_card" on an "on_death" trigger so the dying card comes back from the graveyard.
##   "cost_increase": N (optional, default 0): the card costs N more from now on, every time it comes back, with no cap
##   (Nerithia gets 1 more expensive per return; she may end up impossible to pay, a dead draw until she is discarded).

var cost_increase := 0

func _read_parameters(data: Dictionary) -> void:
	cost_increase = int(data.get("cost_increase", 0))

func apply(context: EffectContext, target_uid: int) -> void:
	var card := context.game.find_card(target_uid)
	if card != null:
		context.game.return_to_hand(card, cost_increase)
