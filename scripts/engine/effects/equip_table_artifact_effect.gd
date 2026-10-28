class_name EquipTableArtifactEffect
extends Effect
## "equip_table_artifact": the unit that owns this effect (the one whose Ao Ativar it is) equips itself with the chosen
## free-standing artifact from its side of the field (target "ally_artifact" with "no_subtypes": true, so only a
## pure artifact can be picked, never an Equipamento or a Local). The artifact leaves its field slot and hangs
## from the unit like any equipment, but it was never meant to be worn: its own Ao Ativar goes quiet while it is
## stored there, and it gives only what its "equipped_grant" says (nothing, if the card has none). It still counts as an artifact in play (Berengar Voss keeps scaling).
## If the unit has no room, its oldest equipment goes back to its owner's hand, as with any equipping.

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var holder := game.find_unit(context.self_uid)
	var artifact := game.find_relic(target_uid)
	if holder == null or artifact == null or artifact.owner != holder.owner:
		return
	if not (artifact.data().get("subtypes", []) as Array).is_empty():
		return
	game.players[holder.owner]["relics"].erase(artifact)
	# A card may say what it gives its bearer while worn ("equipped_grant": {"atk": N, "hp": N}). The grant is
	# remembered in worn_grant, so it is taken back when the artifact leaves the unit (like any equipment).
	var worn_bonus: Dictionary = artifact.data().get("equipped_grant", {})
	var granted := {}
	for stat in ["atk", "hp"]:
		granted[stat] = int(worn_bonus.get(stat, 0))
	holder.atk += int(granted["atk"])
	holder.hp += int(granted["hp"])
	game.stack_system().attach(holder, artifact, granted)
