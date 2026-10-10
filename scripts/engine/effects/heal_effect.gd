class_name HealEffect
extends Effect
## Healing family, told apart by `action`:
## "heal_leader": heals the controller's Leader by `amount` (never above its maximum).
## "leader_max_up": raises the controller's Leader maximum HP (and current HP) by `amount`.
## "heal_full": removes all damage from the target unit.

var amount := 0

func _read_parameters(data: Dictionary) -> void:
	amount = int(data.get("amount", 0))

func apply(context: EffectContext, target_uid: int) -> void:
	match action:
		"heal_leader":
			context.game._heal_leader(context.controller, amount)
		"leader_max_up":
			context.game._raise_leader_max(context.controller, amount)
		"heal_full":
			var unit := context.game.find_unit(target_uid)
			if unit != null and unit.damage > 0:
				context.game._emit({"type": "heal", "uid": target_uid, "amount": unit.damage})
				unit.damage = 0
