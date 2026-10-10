class_name TargetSelector
extends RefCounted
## Base class of an effect's "target" (cards.json): decides which uids the effect hits.
## Each family of targets is a subclass; TargetRegistry maps the JSON names to them.
## This base class is also the "no target" selector (static effects), which hits nothing.

var name := "" ## the JSON name, e.g. "enemy_unit"

func _init(target_name: String = "") -> void:
	name = target_name

## True when the player picks this target while playing the card (enemy_unit, any...).
func needs_choice() -> bool:
	return false

## The uids (units, or negative Leader uids) the effect is applied to, in order.
func resolve(_context: EffectContext, _effect: Effect) -> Array:
	return []
