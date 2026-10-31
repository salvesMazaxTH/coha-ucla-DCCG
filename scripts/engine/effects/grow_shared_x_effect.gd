class_name GrowSharedXEffect
extends Effect
## "grow_shared_x": makes the shared X of this card grow by `amount` (default 1) for its controller (Drex).
## Every copy of the card, on the board or still to be drawn, reads the same X (see GameState.shared_x_of).

func apply(context: EffectContext, _target_uid: int) -> void:
	var growth := int(raw.get("amount", 1))
	context.game.grow_shared_x(context.controller, context.source_id(), growth)
