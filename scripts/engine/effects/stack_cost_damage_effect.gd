class_name StackCostDamageEffect
extends Effect
## "damage_leader_by_stack_cost": the chosen spell/ability on the stack (target "enemy_stack") is NOT cancelled;
## its caster's Leader takes damage equal to that item's Momentum cost, at most `max` (Represália Ardente).
## Nothing happens when the item is gone by the time this resolves.

var maximum := 99

func _read_parameters(data: Dictionary) -> void:
	maximum = int(data.get("max", 99))

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var punished_item := game.stack_system().stack_item(target_uid)
	if punished_item.is_empty():
		return
	var damage_amount := mini(game.stack_cost(punished_item), maximum)
	if damage_amount <= 0:
		return
	game._deal_damage(GameState.LEADER_UID[int(punished_item["player"])], damage_amount, null)
