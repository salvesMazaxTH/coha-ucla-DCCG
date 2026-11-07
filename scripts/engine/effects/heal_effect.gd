class_name HealEffect
extends Effect
## Healing family, told apart by `action`:
## "heal_leader": heals the controller's Leader by `amount` (never above its maximum). With "per":
##                "half_event_damage" it heals half (rounded up) of the damage of the event that made
##                the card react, but never less than `amount` (Tox Vipranna: half the Veneno tick, at least 2).
##                With "per": "event_damage" it heals the full damage of that event (Coagulhão: all the Sangramento dealt).
##                With "amount_from": "sacrificed_atk" (inside a sacrifice's "then") it heals the Attack the
##                sacrificed unit had, instead of `amount` (Drex).
##                With "amount_from": "shared_x" it heals the card's shared X plus `amount` (Drex: X+1 with amount 1).
##                "heal_origin": "reaction" (opt-in) reports the heal to listeners as that origin instead of "unit", so a card
##                that listens to unit heals cannot answer its own heal forever (Drex).
##                "per_turn_cap": N (opt-in) gives each instance of the card a hard budget of N Vida healed per turn:
##                the trigger that would pass N heals only what is left, later ones do nothing until the next turn.
##                "source_temp_hp": N (with per_turn_cap) also gives the card N temporary Vida per accepted trigger,
##                until its owner's next turn starts (Tox Vipranna +1).
## "leader_max_up": raises the controller's Leader maximum HP (and current HP) by `amount`.
## "heal_full": removes all damage from the target unit.
## "heal_unit": heals the target unit by `amount`, or by its Armadura when "per" is "armor". With "amount_from":
##              "shared_x" it heals the card's shared X plus `amount`, and "heal_origin" reports the heal as that
##              origin (Drex phase 2 heals itself as "reaction", so its own heal does not trigger it again).
##              A Leader target (negative uid, e.g. from "ally_or_own_leader") heals that Leader instead.
##              "overflow_max_hp": N (opt-in, never a default) = when the heal is bigger than the Vida the
##              target was missing, it also gains +N maximum Vida for good (unit or Leader).
## Every heal here tells its listeners who healed (`healed_by` in the unit_healed / leader_healed event data:
## "unit", "spell", "artifact" or "leader_ability", see EffectContext.heal_origin).
## A unit or Leader under "block_healing" recovers nothing from the heals above (cleanse still works, and
## leader_max_up is not a heal, so it still works too).
## "cleanse": true (any heal above except leader_max_up) also purifies the healed unit or Leader: all its
## Veneno/Queimadura/Sangramento markers are removed.

var amount := 0
var per := ""
var amount_from := "" ## "" = use `amount`; "sacrificed_atk" = the Attack of the unit a sacrifice just killed; "shared_x" = the card's shared X + `amount`
var origin_override := "" ## "" = the real origin (EffectContext.heal_origin)
var per_turn_cap := 0
var source_temp_hp := 0
var overflow_max_hp := 0
var cleanse := false

func _read_parameters(data: Dictionary) -> void:
	overflow_max_hp = int(data.get("overflow_max_hp", 0))
	cleanse = bool(data.get("cleanse", false))
	amount = int(data.get("amount", 0))
	per = String(data.get("per", ""))
	amount_from = String(data.get("amount_from", ""))
	origin_override = String(data.get("heal_origin", ""))
	per_turn_cap = int(data.get("per_turn_cap", 0))
	source_temp_hp = int(data.get("source_temp_hp", 0))

## What "heal_leader" heals right now: the sacrificed unit's Attack, or `amount`, or the triggering event's damage (whole, or half when that is more).
func _leader_heal_amount(context: EffectContext) -> int:
	if amount_from == "sacrificed_atk":
		return context.sacrificed_attack
	if amount_from == "shared_x":
		return context.game.shared_x_of(context.controller, context.source_id()) + amount
	if per == "event_damage" and context.event != null:
		return context.event.amount
	if per == "half_event_damage" and context.event != null:
		return maxi(amount, ceili(context.event.amount / 2.0))
	return amount

func apply(context: EffectContext, target_uid: int) -> void:
	match action:
		"heal_leader":
			var heal_amount := _leader_heal_amount(context)
			if per_turn_cap > 0:
				context.game._apply_capped_leader_heal(context, heal_amount, per_turn_cap, source_temp_hp, origin_override)
			else:
				context.game._heal_leader(context.controller, heal_amount, origin_override if origin_override != "" else context.heal_origin())
			if cleanse:
				context.game.cleanse_leader_markers(context.controller)
		"leader_max_up":
			context.game._raise_leader_max(context.controller, amount, context.heal_origin())
		"heal_full":
			var unit := context.game.find_unit(target_uid)
			if unit != null and cleanse:
				context.game.cleanse_unit_markers(unit)
			if unit != null and not context.game.unit_heal_prevented(unit, unit.damage) and unit.damage > 0:
				var healed_amount := unit.damage
				context.game._emit({"type": "heal", "uid": target_uid, "amount": healed_amount})
				unit.damage = 0
				context.game.emit_unit_healed(unit, healed_amount, context.heal_origin())
		"heal_unit":
			if target_uid < 0: # a Leader was picked: heal the controller's Leader
				var leader_player := context.controller
				var leader_missing: int = context.game.players[leader_player]["leader_max"] - context.game.players[leader_player]["leader_hp"]
				context.game._heal_leader(leader_player, amount, context.heal_origin())
				if cleanse:
					context.game.cleanse_leader_markers(leader_player)
				if overflow_max_hp > 0 and amount > leader_missing and not context.game.leader_heal_blocked(leader_player):
					context.game._raise_leader_max(leader_player, overflow_max_hp, context.heal_origin())
				return
			var unit := context.game.find_unit(target_uid)
			if unit == null:
				return
			if cleanse:
				context.game.cleanse_unit_markers(unit)
			var heal_amount := amount
			if amount_from == "shared_x":
				heal_amount = context.game.shared_x_of(context.controller, context.source_id()) + amount
			if per == "armor":
				heal_amount = context.game.armor_of(unit)
			elif per == "half_armor": # half the Armadura, rounded up
				heal_amount = ceili(context.game.armor_of(unit) / 2.0)
			if context.game.unit_heal_prevented(unit, heal_amount):
				return
			var healed := mini(heal_amount, unit.damage)
			if healed > 0:
				context.game._emit({"type": "heal", "uid": target_uid, "amount": healed})
				unit.damage -= healed
				context.game.emit_unit_healed(unit, healed, origin_override if origin_override != "" else context.heal_origin())
			# opt-in overflow: a heal that goes past what the unit was missing grows its maximum Vida for good
			if overflow_max_hp > 0 and heal_amount > healed:
				unit.hp += overflow_max_hp
				unit.record_stat_change(context.source_id(), "", {"hp": overflow_max_hp})
				context.game._emit({"type": "buff", "uid": target_uid, "atk": 0, "hp": overflow_max_hp, "keywords": []})
