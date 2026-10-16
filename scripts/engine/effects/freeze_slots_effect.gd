class_name FreezeSlotsEffect
extends Effect
## "freeze_slots": Rei Gelado. Freezes random slots of the ENEMY field (use it with target "none").
##   "count": N  how many of the BOARD_LIMIT slots are frozen (default 5), occupied or not.
## A unit standing in a frozen slot is frozen AND exhausted. An empty frozen slot accepts no permanent
## (GameState.has_free_slot counts it as taken) and thaws at the END of its owner's next turn, so the
## owner really feels it.
## Only slots that can still be frozen are rolled: units that are not Congelada yet and empty slots that are
## not frozen yet (the free ones, not the ones taken by a relic). If there are fewer than `count`, all of them are hit.

var count := 5

func _read_parameters(data: Dictionary) -> void:
	count = int(data.get("count", 5))

func apply(context: EffectContext, _target_uid: int) -> void:
	var game := context.game
	var victim: int = game.opponent(context.controller)
	var victim_state: Dictionary = game.players[victim]
	var units_on_board: Array = victim_state["board"]

	# the pool of slots that can still be frozen: a unit is its own entry, and so is each free empty slot
	var pool: Array = []
	for unit: Card in units_on_board:
		if not unit.is_frozen():
			pool.append(unit)
	var free_slots: int = game.BOARD_LIMIT - game.slots_used(victim) - int(victim_state["frozen_slots"])
	for empty_slot in maxi(0, free_slots):
		pool.append(null) # null = an empty slot
	game._shuffle(pool)
	var chosen: Array = pool.slice(0, mini(count, pool.size()))

	var chosen_positions: Array = []
	var blocked_count := 0
	for entry: Variant in chosen:
		if entry == null:
			chosen_positions.append(units_on_board.size() + blocked_count)
			blocked_count += 1
			continue
		var unit: Card = entry
		chosen_positions.append(units_on_board.find(unit))
		# Escudo de Feitiço cancels the effect on that unit and breaks, like any effect from the enemy side
		if unit.spell_shield:
			unit.spell_shield = false
			game._emit({"type": "spell_shield_break", "uid": unit.uid})
			continue
		FreezeEffect.new().apply(context, unit.uid)
		ExhaustEffect.new().apply(context, unit.uid)

	if blocked_count > 0:
		victim_state["frozen_slots"] += blocked_count
		# thaws at the end of the victim's next turn: that is turn+1 when the caster is playing now, else turn+2
		victim_state["frozen_slots_until"] = game.turn + (1 if game.active == context.controller else 2)
	game._emit({"type": "slots_frozen", "player": victim, "positions": chosen_positions, "blocked": blocked_count})
