class_name DiscardHandEffect
extends Effect
## "discard_hand_all" (Queima de Arquivo): the controller discards their ENTIRE hand to the graveyard, no choice involved.
## It is a plain effect (not a choice screen), so effects listed after it in the same card, like a draw, see the empty hand.
## An empty hand does nothing and says nothing.

func apply(context: EffectContext, _target_uid: int) -> void:
	context.game._discard_whole_hand(context.controller)
