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

## True for a target that is rolled again before every hit (Repique Desgovernado): the effect then asks
## hit_count() and calls resolve_hit() once per hit, so a hit never lands on a unit that the earlier hits of
## the same effect already left with no Vida. Every other target is resolved once, up front.
func hits_one_at_a_time() -> bool:
	return false

## How many hits a one-at-a-time target hands out (only asked when hits_one_at_a_time() is true).
func hit_count(_context: EffectContext, _effect: Effect) -> int:
	return 0

## The uid of the next hit, rolled now (empty when nobody is left to hit).
func resolve_hit(_context: EffectContext, _effect: Effect) -> Array:
	return []
