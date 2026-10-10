class_name FightEffect
extends Effect
## "fight": the target (first pick) and the card's second pick fight each other.
## Each one deals damage equal to its own ATK to the other, at the same time. Armadura, Escudo and
## the other damage rules apply as for any damage. The second pick is declared on the effect with
## "second_target" (e.g. "enemy_unit"); if it is gone or protected by Escudo de Feitiço, nobody fights.

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var first_unit := game.find_unit(target_uid)
	var second_unit := game.find_unit(context.second_target)
	if first_unit == null or second_unit == null or first_unit == second_unit:
		return
	if not game.valid_targets(context.controller, String(raw.get("second_target", "enemy_unit"))).has(second_unit.uid):
		return
	# Escudo de Feitiço on the opponent of the fight cancels it, like it cancels any other spell effect
	if second_unit.owner != context.controller and second_unit.spell_shield:
		second_unit.spell_shield = false
		game._emit({"type": "spell_shield_break", "uid": second_unit.uid})
		return
	game._emit({"type": "fight", "uid": first_unit.uid, "other": second_unit.uid})
	# both strikes are measured before either lands, so a unit killed by the other still hits back
	var first_strike := first_unit.atk_total()
	var second_strike := second_unit.atk_total()
	game._deal_damage(second_unit.uid, first_strike, first_unit)
	game._deal_damage(first_unit.uid, second_strike, second_unit)
