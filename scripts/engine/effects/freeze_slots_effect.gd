class_name FreezeSlotsEffect
extends Effect
## "freeze_slots": Rei Gelado. Freezes random slots of the ENEMY field (use it with target "none").
##   "count": N  how many of the BOARD_LIMIT slots are frozen (default 5), occupied or not.
## A unit standing in a frozen slot is frozen AND exhausted. An empty frozen slot accepts no permanent
## (GameState.has_free_slot counts it as taken) and thaws at the END of its owner's next turn, so the
## owner really feels it. Slots are counted left to right: positions beyond the last unit are the empty ones.

var count := 5

func _read_parameters(data: Dictionary) -> void:
	count = int(data.get("count", 5))

func apply(context: EffectContext, _target_uid: int) -> void:
	var game := context.game
	var victim: int = game.opponent(context.controller)
	var victim_state: Dictionary = game.players[victim]

	# pick `count` distinct positions out of the whole field
	var positions: Array = range(game.BOARD_LIMIT)
	game._shuffle(positions)
	var chosen_positions: Array = positions.slice(0, mini(count, positions.size()))

	var hit_units: Array = []
	var empty_hit_count := 0
	var units_on_board: Array = victim_state["board"]
	for position: int in chosen_positions:
		if position < units_on_board.size():
			hit_units.append(units_on_board[position])
		else:
			empty_hit_count += 1

	for unit: Card in hit_units:
		# Escudo de Feitiço cancels the effect on that unit and breaks, like any effect from the enemy side
		if unit.spell_shield:
			unit.spell_shield = false
			game._emit({"type": "spell_shield_break", "uid": unit.uid})
			continue
		FreezeEffect.new().apply(context, unit.uid)
		ExhaustEffect.new().apply(context, unit.uid)

	# empty slots can only be blocked while they exist: relics and units already fill part of the field
	var free_slots: int = game.BOARD_LIMIT - game.slots_used(victim) - int(victim_state["frozen_slots"])
	var blocked_count := mini(empty_hit_count, maxi(0, free_slots))
	if blocked_count > 0:
		victim_state["frozen_slots"] += blocked_count
		# thaws at the end of the victim's next turn: that is turn+1 when the caster is playing now, else turn+2
		victim_state["frozen_slots_until"] = game.turn + (1 if game.active == context.controller else 2)
	game._emit({"type": "slots_frozen", "player": victim, "positions": chosen_positions, "blocked": blocked_count})
