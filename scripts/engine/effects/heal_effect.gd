class_name HealEffect
extends Effect
## Healing family, told apart by `action`:
## "heal_leader": heals the controller's Leader by `amount` (never above its maximum). With "per":
##                "half_event_damage" it heals half (rounded up) of the damage of the event that made
##                the card react, but never less than `amount` (Tox Vipranna: half the Veneno tick, at least 2).
## "leader_max_up": raises the controller's Leader maximum HP (and current HP) by `amount`.
## "heal_full": removes all damage from the target unit.
## "heal_unit": heals the target unit by `amount`, or by its Armadura when "per" is "armor".
##              A Leader target (negative uid, e.g. from "ally_or_own_leader") heals that Leader instead.

var amount := 0
var per := ""

func _read_parameters(data: Dictionary) -> void:
	amount = int(data.get("amount", 0))
	per = String(data.get("per", ""))

## What "heal_leader" heals right now: `amount`, or half the triggering event's damage when that is more.
func _leader_heal_amount(context: EffectContext) -> int:
	if per == "half_event_damage" and context.event != null:
		return maxi(amount, ceili(context.event.amount / 2.0))
	return amount

func apply(context: EffectContext, target_uid: int) -> void:
	match action:
		"heal_leader":
			context.game._heal_leader(context.controller, _leader_heal_amount(context))
		"leader_max_up":
			context.game._raise_leader_max(context.controller, amount)
		"heal_full":
			var unit := context.game.find_unit(target_uid)
			if unit != null and unit.damage > 0:
				context.game._emit({"type": "heal", "uid": target_uid, "amount": unit.damage})
				unit.damage = 0
		"heal_unit":
			if target_uid < 0: # a Leader was picked: heal the controller's Leader
				context.game._heal_leader(context.controller, amount)
				return
			var unit := context.game.find_unit(target_uid)
			if unit == null or unit.damage <= 0:
				return
			var heal_amount := amount
			if per == "armor":
				heal_amount = context.game.armor_of(unit)
			elif per == "half_armor": # half the Armadura, rounded up
				heal_amount = ceili(context.game.armor_of(unit) / 2.0)
			heal_amount = mini(heal_amount, unit.damage)
			if heal_amount > 0:
				context.game._emit({"type": "heal", "uid": target_uid, "amount": heal_amount})
				unit.damage -= heal_amount
