class_name DamageEffect
extends Effect
## "damage": deals `amount` damage to each target.
## "amount_from": "sacrificed_atk" uses the attack of the unit a "sacrifice" just killed;
## "self_half_armor" uses half of this unit's own Armadura, rounded up (Tharox).
## "ally_reduce": {"essence", "amount"} = own units of that essence take only that much.

var amount := 0
var amount_from := ""
var ally_reduce: Dictionary = {}

func _read_parameters(data: Dictionary) -> void:
	amount = int(data.get("amount", 0))
	amount_from = String(data.get("amount_from", ""))
	ally_reduce = data.get("ally_reduce", {})

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var damage_amount := context.sacrificed_attack if amount_from == "sacrificed_atk" else amount
	if amount_from == "self_half_armor":
		var source_unit := game.find_unit(context.self_uid)
		damage_amount = ceili(game.armor_of(source_unit) / 2.0) if source_unit != null else 0
	var victim := game.find_unit(target_uid)
	if not ally_reduce.is_empty() and victim != null and victim.owner == context.controller \
			and CardDB.has_essence(victim.data(), ally_reduce["essence"]):
		damage_amount = int(ally_reduce["amount"])
	game._deal_damage(target_uid, damage_amount, null)
