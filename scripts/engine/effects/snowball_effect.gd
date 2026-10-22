class_name SnowballEffect
extends Effect
## "snowball": a Bola de Neve. Hits the target for the caster's current snowball level, then bounces
## along the target's board: the direction (left or right) is chosen ONCE and kept to the last unit,
## and every bounce hits for 1 more than the one before.
## The level is shared by every Bola de Neve of the player (in hand, or cast by a unit): after a cast
## the next one starts at the damage where this one stopped.
## Reaching level GameState.SNOWBALL_GRANDE_AT turns every Bola de Neve card of the player into the
## Grande Bola de Neve card (see GameState.set_snowball_level). That card has its own cost and text, and
## sets "overflow_to_leader": every hit has Sobrepujança (the excess damage goes to the Leader of the
## player who owns the hit unit). A Bola de Neve cast by a unit (Nythera, Tempesfrost) has no card to
## evolve, so when the caster is at Grande level the effect casts the Grande Bola de Neve card's effect
## instead of its own: every Bola is Grande from level 7 on, and that card stays the one definition.
## Aimed at a Leader (negative uid) it is one plain hit: no bounce, and the level doesn't grow.
## A Bola cast by a unit is not thrown at once: it goes onto the stack as the Bola de Neve card (the
## Grande one at Grande level), exactly like one played from the hand, so the opponent can respond
## or counter it. It hits when that stack item resolves (see StackSystem.push_unit_snowball).

var overflow_to_leader := false ## set by the Grande Bola de Neve card itself

func _read_parameters(data: Dictionary) -> void:
	overflow_to_leader = bool(data.get("overflow_to_leader", false))

## The "snowball" effect of the Grande Bola de Neve card, used when a plain Bola is cast at Grande level.
func _grande_effect() -> Effect:
	for effect_data: Dictionary in CardDB.card(GameState.GRANDE_SNOWBALL_CARD_ID)["effects"]:
		if effect_data.get("action", "") == "snowball":
			return EffectRegistry.parse(effect_data)
	return null

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var caster: int = context.controller
	if context.trigger != "on_play":
		var card_id: String = GameState.GRANDE_SNOWBALL_CARD_ID if game.snowball_is_grande(caster) else GameState.SNOWBALL_CARD_ID
		game.stack_system().push_unit_snowball(caster, context.self_uid, card_id, target_uid)
		return
	# a Bola without a card to evolve (cast by a unit) becomes the Grande one as soon as its caster is Grande
	if not overflow_to_leader and game.snowball_is_grande(caster):
		_grande_effect().apply(context, target_uid)
		return
	var start_damage: int = int(game.players[caster]["snowball"])
	game._emit({"type": "snowball", "player": caster, "uid": target_uid, "amount": start_damage, "grande": overflow_to_leader})
	# listeners (Princesa Wanessa becomes Tempesfrost) hear about every Bola de Neve before it hits
	var cast_event := GameEvent.new("snowball_cast", caster, null)
	cast_event.amount = start_damage
	cast_event.data["grande"] = overflow_to_leader
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
	_hit(context, first_unit, damage_now)
	for next_unit: Card in bounce_path:
		damage_now += 1
		# a unit that left the board mid-cast (e.g. died to a death trigger) is skipped but still counts
		if game.find_unit(next_unit.uid) != null:
			_hit(context, next_unit, damage_now)

	# the future Bolas de Neve start where this one stopped
	game.set_snowball_level(caster, maxi(int(game.players[caster]["snowball"]), damage_now))

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

## One hit. With "overflow_to_leader" it also sends the excess over the unit's remaining life to its owner's Leader.
func _hit(context: EffectContext, unit: Card, damage_amount: int) -> void:
	var game := context.game
	# Escudo de Feitiço of an enemy unit cancels the hit (and breaks)
	if cancelled_by_any_shield(context, unit):
		return
	var life_before := unit.hp_left()
	var dealt := game._deal_damage(unit.uid, damage_amount, null)
	if overflow_to_leader and dealt > life_before:
		game._deal_damage(game.LEADER_UID[unit.owner], dealt - life_before, null)
