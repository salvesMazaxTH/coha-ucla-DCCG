class_name SnowballEffect
extends Effect
## "snowball": a Bola de Neve. Hits the target for the caster's current snowball level, then bounces
## along the target's board: the direction (left or right) is chosen ONCE and kept to the last unit,
## and every bounce hits for 1 more than the one before.
## The level is shared by every Bola de Neve of the player (in hand, or cast by a unit): after a cast
## the next one starts at the damage where this one stopped.
## When the level reaches `grande_at`, every Bola de Neve is a Grande Bola de Neve: it costs
## `grande_cost` more (see GameState.cost_of) and each hit has Sobrepujança (excess damage goes to the
## Leader of the player who owns the hit unit).
## Aimed at a Leader (negative uid) it is one plain hit: no bounce, and the level doesn't grow.

var grande_at := GameState.SNOWBALL_GRANDE_AT

func _read_parameters(data: Dictionary) -> void:
	grande_at = int(data.get("grande_at", GameState.SNOWBALL_GRANDE_AT))

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var caster: int = context.controller
	var start_damage: int = int(game.players[caster]["snowball"])
	var is_grande := start_damage >= grande_at
	game._emit({"type": "snowball", "player": caster, "uid": target_uid, "amount": start_damage, "grande": is_grande})
	# listeners (Princesa Wanessa becomes Tempesfrost) hear about every Bola de Neve before it hits
	var cast_event := GameEvent.new("snowball_cast", caster, null)
	cast_event.amount = start_damage
	cast_event.data["grande"] = is_grande
	game.bus().emit(cast_event)

	if target_uid < 0:
		game._deal_damage(target_uid, start_damage, null)
		return
	var first_unit := game.find_unit(target_uid)
	if first_unit == null:
		return

	# the whole path is decided before any damage, so units dying along the way don't change it
	var bounce_path := _bounce_path(game, first_unit)
	var damage_now := start_damage
	_hit(game, caster, first_unit, damage_now, is_grande)
	for next_unit: Card in bounce_path:
		damage_now += 1
		# a unit that left the board mid-cast (e.g. died to a death trigger) is skipped but still counts
		if game.find_unit(next_unit.uid) != null:
			_hit(game, caster, next_unit, damage_now, is_grande)

	# the future Bolas de Neve start where this one stopped
	game.players[caster]["snowball"] = maxi(int(game.players[caster]["snowball"]), damage_now)

## The units after `first_unit` in the bounce direction, nearest first. The direction is a coin flip
## only when both sides have units; otherwise the side that has units is used.
func _bounce_path(game: GameState, first_unit: Card) -> Array:
	var board: Array = game.players[first_unit.owner]["board"]
	var index := board.find(first_unit)
	var left_side: Array = []
	var right_side: Array = []
	for left_index in range(index - 1, -1, -1):
		left_side.append(board[left_index])
	for right_index in range(index + 1, board.size()):
		right_side.append(board[right_index])
	if left_side.is_empty():
		return right_side
	if right_side.is_empty():
		return left_side
	return left_side if game.rng.randi_range(0, 1) == 0 else right_side

## One hit. A Grande hit also sends the excess over the unit's remaining life to its owner's Leader.
func _hit(game: GameState, caster: int, unit: Card, damage_amount: int, is_grande: bool) -> void:
	# Escudo de Feitiço of an enemy unit cancels the hit (and breaks)
	if unit.owner != caster and unit.spell_shield:
		unit.spell_shield = false
		game._emit({"type": "spell_shield_break", "uid": unit.uid})
		return
	var life_before := unit.hp_left()
	var dealt := game._deal_damage(unit.uid, damage_amount, null)
	if is_grande and dealt > life_before:
		game._deal_damage(game.LEADER_UID[unit.owner], dealt - life_before, null)
