class_name EquipSelfEffect
extends Effect
## "equip_self": a free-standing pure artifact equips itself onto the chosen allied unit.
## The artifact's equipped_grant is applied and remembered so it can be removed normally later.

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var artifact := game.find_relic(context.self_uid)
	var holder := game.find_unit(target_uid)
	if artifact == null or holder == null or artifact.owner != context.controller or holder.owner != artifact.owner:
		return
	game.players[artifact.owner]["relics"].erase(artifact)
	var grant: Dictionary = artifact.data().get("equipped_grant", {})
	var granted := game.stack_system().apply_equipment_bonus(holder, grant)
	game.stack_system().attach(holder, artifact, granted)
