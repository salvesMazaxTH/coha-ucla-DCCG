class_name AutoAttackEffect
extends Effect
## "auto_attack": after this attack deals its damage, the attacking unit attacks again by itself, at a
## random target it could legally hit (a forced Provocação first, otherwise any challengeable enemy
## unit or the enemy Leader). Meant for the trigger "on_attack" with "target": "none".
## The extra attack does not fire Ao Atacar again, so it cannot repeat forever.

func apply(context: EffectContext, _target_uid: int) -> void:
	var attacker_uid := context.self_uid
	var queue: Array = context.game.combat_system().auto_attack_queue
	if not queue.has(attacker_uid):
		queue.append(attacker_uid)
