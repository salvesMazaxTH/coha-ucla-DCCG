class_name InheritEquipmentEffect
extends Effect
## "inherit_equipment": an Aliado Morre effect. The unit that owns it takes over the equipment the ally that just
## died was wearing: the equipment leaves the graveyard (where it fell with its bearer) and hangs from this unit,
## giving it the same bonus it gave the fallen one (Montadora Porca-Frouxa). Use it with target "self".
## "only_if_unequipped": true = only works while this unit wears no equipment at all.
## Takes the first equipment the dead ally wore that is still in its owner's graveyard. If it wore several
## (Tobias), the others stay where they fell. Nothing happens when the ally wore nothing.

var only_if_unequipped := false

func _read_parameters(data: Dictionary) -> void:
	only_if_unequipped = bool(data.get("only_if_unequipped", false))

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var heir := game.find_unit(target_uid)
	if heir == null or context.event == null:
		return
	if only_if_unequipped and not heir.equipped_cards.is_empty():
		return
	var graveyard: Array = game.players[heir.owner]["graveyard"]
	for fallen_equipment: Card in context.event.data.get("dying_equipment", []):
		if not graveyard.has(fallen_equipment):
			continue # already taken, or sent somewhere else since the unit died
		graveyard.erase(fallen_equipment)
		# worn_grant is read before attach(), which overwrites it with the new bonus
		var granted := game.stack_system().apply_equipment_bonus(heir, fallen_equipment.worn_grant)
		game._emit({"type": "buff", "uid": heir.uid, "atk": int(granted["atk"]), "hp": int(granted["hp"]), "keywords": granted["keywords"]})
		game.stack_system().attach(heir, fallen_equipment, granted)
		return
