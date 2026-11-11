class_name FlagCondition
extends Condition
## The simple string conditions: "if": "momentum_left" | "unspent_momentum" | "unspent_momentum_threshold" (UNSPENT_MOMENTUM_THRESHOLD or more unspent until this turn's untap) | "battery_full" | "played_two" | "oldest_of_its_name" | "no_snowball_in_hand_or_deck" | "gained_momentum_this_turn" | "lethal_attack" | "no_stunned_enemy" | "armor_spent_last_turn" (this unit spent its own Armadura since its owner's previous turn began; Farkoveth).

const NAMES := ["momentum_left", "unspent_momentum", "unspent_momentum_threshold", "battery_full", "played_two", "oldest_of_its_name", "no_snowball_in_hand_or_deck", "gained_momentum_this_turn", "lethal_attack", "no_stunned_enemy", "armor_spent_last_turn"]

var name := ""

func _init(flag_name: String) -> void:
	name = flag_name

func check(context: EffectContext) -> bool:
	var player: Dictionary = context.game.players[context.controller]
	match name:
		"momentum_left": return player["momentum"] > 0
		"unspent_momentum": return player["unspent"] > 0 # plain Momentum left over at the start of this turn
		"unspent_momentum_threshold": return player["unspent"] >= GameState.UNSPENT_MOMENTUM_THRESHOLD
		"battery_full": return player["battery"] >= context.game.battery_cap(context.controller)
		"played_two": return player["played_two"]
		"oldest_of_its_name": return _is_oldest_copy_on_board(context, player)
		# an effect really raised Momentum earlier this turn (a refresh counts; the turn-start Momentum does not)
		"gained_momentum_this_turn": return player["momentum_gain_turn"] == context.game.turn
		"lethal_attack": return _attack_is_lethal(context)
		"no_stunned_enemy": return not _enemy_has_stunned_unit(context)
		"armor_spent_last_turn":
			var source_unit := context.game.find_unit(context.self_uid)
			return source_unit != null and source_unit.armor_spent_last_turn
		"no_snowball_in_hand_or_deck":
			return not _has_snowball(player["hand"]) and not _has_snowball(player["deck"])
	return true

func _enemy_has_stunned_unit(context: EffectContext) -> bool:
	for unit: Card in context.game.players[context.opponent()]["board"]:
		if unit.is_stunned():
			return true
	return false

func _has_snowball(cards: Array) -> bool:
	for card: Card in cards:
		if card.card_id in [GameState.SNOWBALL_CARD_ID, GameState.GRANDE_SNOWBALL_CARD_ID]:
			return true
	return false

## True when the attack being declared (trigger "before_attack", Ao Atacar) goes for the enemy Leader and the
## attacker's Ataque alone is enough to take it to 0. Armadura, Escudo and a possible Crítico are ignored,
## like the "worth a reply" check of the combat system: it is a prediction used for cosmetic effects (shouts).
func _attack_is_lethal(context: EffectContext) -> bool:
	if context.other_uid >= 0:
		return false # a unit is being attacked, not the Leader
	var attacker := context.game.find_unit(context.self_uid)
	if attacker == null:
		return false
	var damage := context.game.strike_power_of(attacker)
	var defender_leader_hp := int(context.game.players[context.opponent()]["leader_hp"])
	return damage > 0 and damage >= defender_leader_hp

## True when no other copy of the same card entered the controller's board before this unit.
## Uids only grow, so the smallest uid among the copies in play is the oldest one.
## Used by Cobrador de Pedágio Torto: only the first copy in play gives its Momentum.
func _is_oldest_copy_on_board(context: EffectContext, player: Dictionary) -> bool:
	var source_id := context.source_id()
	for unit: Card in player["board"]:
		if unit.card_id == source_id and unit.uid < context.self_uid:
			return false
	return true
