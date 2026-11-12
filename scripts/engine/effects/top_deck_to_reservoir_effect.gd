class_name TopDeckToReservoirEffect
extends Effect
## "top_deck_to_reservoir": puts the top `amount` cards (default 1) of the controller's deck into their Reservoir,
## face up, and ready unless `exhausted` is true (then tapped: no Momentum until it is untapped). It is not the
## once-per-turn hand deposit, and it does nothing with an empty deck.

var amount := 1
var exhausted := false

func _read_parameters(data: Dictionary) -> void:
	amount = int(data.get("amount", 1))
	exhausted = bool(data.get("exhausted", false))

func apply(context: EffectContext, _target_uid: int) -> void:
	context.game.move_top_deck_to_reservoir(context.controller, amount, context.self_uid, exhausted)
