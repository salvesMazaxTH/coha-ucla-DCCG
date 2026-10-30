class_name BlockHealingEffect
extends Effect
## "block_healing": the target unit or Leader cannot recover Vida (heals, Regeneração, lifesteal) for a while.
##   "turns": N   how many of the target controller's next turns the block lasts (default 1). It also covers
##                the rest of the turn it was cast in. A block already running is never shortened.
## Damage already dealt stays; the block only stops new Vida from coming back.

var turns := 1

func _read_parameters(data: Dictionary) -> void:
	turns = maxi(1, int(data.get("turns", 1)))

func apply(context: EffectContext, target_uid: int) -> void:
	var leader_player := GameState.LEADER_UID.find(target_uid)
	if leader_player >= 0:
		context.game.block_healing_on_leader(leader_player, turns)
		return
	var unit := context.game.find_unit(target_uid)
	if unit != null:
		context.game.block_healing_on_unit(unit, turns)
