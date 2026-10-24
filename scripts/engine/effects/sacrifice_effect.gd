class_name SacrificeEffect
extends Effect
## "sacrifice": kills one of the controller's own units; the "then" effects run only if it
## happened, and can read its attack ("amount_from": "sacrificed_atk") or its printed cost
## ("amount_from": "sacrificed_cost", used by gain_momentum).

var then_effects: Array = [] ## Effect objects

func _read_parameters(data: Dictionary) -> void:
	then_effects = EffectRegistry.parse_list(data.get("then", []))

## Escudo Supremo absorbs even a sacrifice: the charge is spent, nobody dies and the "then" effects don't run.
func harms_own_target() -> bool:
	return true

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var victim := game.find_unit(target_uid)
	if victim == null or victim.owner != context.controller:
		return
	var then_context := context.for_then_effects()
	then_context.sacrificed_attack = victim.atk_total() # last known attack, buffs included
	then_context.sacrificed_cost = int(CardDB.card(victim.card_id).get("cost", 0))
	victim.damage = victim.hp + victim.bonus_hp + victim.temp_hp + victim.temp_hp_until_next_turn
	game._emit({"type": "sacrifice", "player": context.controller, "uid": target_uid})
	if not then_effects.is_empty():
		# The victim leaves the board before the "then" effects, so a summon has its slot back even on a full board.
		# Its Ao Morrer / Aliado Morre triggers are only queued here and resolve afterwards.
		game._move_dead_units()
	game._run_effects(then_context, then_effects)
