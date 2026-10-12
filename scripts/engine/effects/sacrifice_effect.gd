class_name SacrificeEffect
extends Effect
## "sacrifice": kills one of the controller's own units; the "then" effects run only if it
## happened, and can read its attack ("amount_from": "sacrificed_atk").

var then_effects: Array = [] ## Effect objects

func _read_parameters(data: Dictionary) -> void:
	then_effects = EffectRegistry.parse_list(data.get("then", []))

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var victim := game.find_unit(target_uid)
	if victim == null or victim.owner != context.controller:
		return
	var then_context := context.for_then_effects()
	then_context.sacrificed_attack = victim.atk_total() # last known attack, buffs included
	victim.damage = victim.hp + victim.bonus_hp + victim.temp_hp
	game._emit({"type": "sacrifice", "player": context.controller, "uid": target_uid})
	game._run_effects(then_context, then_effects)
