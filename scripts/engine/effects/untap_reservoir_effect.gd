class_name UntapReservoirEffect
extends Effect
## "untap_reservoir": untaps up to `amount` tapped cards (default 1) of the controller's Reservoir.
## "per": "returned_allies" untaps `amount` cards for each allied unit that a "return_to_hand" earlier in the same effect run
## sent back to the hand (Kazeminus).
## Unlike a floating gain, it can never give more Momentum than the cards the Reservoir holds. It does nothing
## when every Reservoir card is already ready.

var amount := 1
var per := ""

func _read_parameters(data: Dictionary) -> void:
	amount = int(data.get("amount", 1))
	per = String(data.get("per", ""))

func apply(context: EffectContext, _target_uid: int) -> void:
	var untap_count := amount
	if per == "returned_allies":
		untap_count = amount * context.returned_ally_count
	if untap_count <= 0:
		return
	context.game.untap_reservoir_cards(context.controller, untap_count)
