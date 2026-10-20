class_name AutoAttackEffect
extends Effect
## "auto_attack": BEFORE the attack the player declared, the attacking unit attacks by itself, at a
## random target WITHOUT ANY restriction (every enemy unit, tapped or not, plus the enemy Leader). Meant for the trigger "before_attack"
## (displayed as "Ao Atacar") with "target": "none". The extra attack fires no Ao Atacar, so it cannot repeat forever.

func apply(context: EffectContext, _target_uid: int) -> void:
	var attacker_uid := context.self_uid
	var queue: Array = context.game.combat_system().auto_attack_queue
	if not queue.has(attacker_uid):
		queue.append(attacker_uid)
