class_name ShoutEffect
extends Effect
## "shout": an effect that changes nothing in the game; it only exists to carry a "shout" (the cinematic
## line a card yells) and an "if" saying when. Use it with "target": "none", e.g. trigger "before_attack"
## plus "if": "lethal_attack" for a unit that yells when it goes for the kill.

func apply(_context: EffectContext, _target_uid: int) -> void:
	pass
