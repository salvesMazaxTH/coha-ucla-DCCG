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
##              "overflow_max_hp": N (opt-in, never a default) = when the heal is bigger than the Vida the
##              target was missing, it also gains +N maximum Vida for good (unit or Leader).
## "cleanse": true (any heal above except leader_max_up) also purifies the healed unit or Leader: all its
## Veneno/Queimadura/Sangramento markers are removed.

var amount := 0
var per := ""
var vipranna := false
var overflow_max_hp := 0
var cleanse := false

func _read_parameters(data: Dictionary) -> void:
	overflow_max_hp = int(data.get("overflow_max_hp", 0))
	cleanse = bool(data.get("cleanse", false))
	amount = int(data.get("amount", 0))
	per = String(data.get("per", ""))
	vipranna = bool(data.get("vipranna", false))

## What "heal_leader" heals right now: `amount`, or half the triggering event's damage when that is more.
func _leader_heal_amount(context: EffectContext) -> int:
	if per == "half_event_damage" and context.event != null:
		return maxi(amount, ceili(context.event.amount / 2.0))
	return amount

func apply(context: EffectContext, target_uid: int) -> void:
	match action:
		"heal_leader":
			var heal_amount := _leader_heal_amount(context)
			if vipranna:
				context.game._apply_vipranna_heal(context, heal_amount)
			else:
				context.game._heal_leader(context.controller, heal_amount)
			if cleanse:
				context.game.cleanse_leader_markers(context.controller)
		"leader_max_up":
			context.game._raise_leader_max(context.controller, amount)
		"heal_full":
			var unit := context.game.find_unit(target_uid)
			if unit != null and cleanse:
				context.game.cleanse_unit_markers(unit)
			if unit != null and unit.damage > 0:
				var healed_amount := unit.damage
				context.game._emit({"type": "heal", "uid": target_uid, "amount": healed_amount})
				unit.damage = 0
				context.game.emit_unit_healed(unit, healed_amount)
		"heal_unit":
			if target_uid < 0: # a Leader was picked: heal the controller's Leader
				var leader_player := context.controller
				var leader_missing: int = context.game.players[leader_player]["leader_max"] - context.game.players[leader_player]["leader_hp"]
				context.game._heal_leader(leader_player, amount)
				if cleanse:
					context.game.cleanse_leader_markers(leader_player)
				if overflow_max_hp > 0 and amount > leader_missing:
					context.game._raise_leader_max(leader_player, overflow_max_hp)
				return
			var unit := context.game.find_unit(target_uid)
			if unit == null:
				return
			if cleanse:
				context.game.cleanse_unit_markers(unit)
			var heal_amount := amount
			if per == "armor":
				heal_amount = context.game.armor_of(unit)
			elif per == "half_armor": # half the Armadura, rounded up
				heal_amount = ceili(context.game.armor_of(unit) / 2.0)
			var healed := mini(heal_amount, unit.damage)
			if healed > 0:
				context.game._emit({"type": "heal", "uid": target_uid, "amount": healed})
				unit.damage -= healed
				context.game.emit_unit_healed(unit, healed)
			# opt-in overflow: a heal that goes past what the unit was missing grows its maximum Vida for good
			if overflow_max_hp > 0 and heal_amount > healed:
				unit.hp += overflow_max_hp
				unit.record_stat_change(context.source_id(), "", {"hp": overflow_max_hp})
				context.game._emit({"type": "buff", "uid": target_uid, "atk": 0, "hp": overflow_max_hp, "keywords": []})
