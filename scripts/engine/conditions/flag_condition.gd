class_name FlagCondition
extends Condition
## The simple string conditions: "if": "momentum_left" | "unspent_momentum" | "momentum_leaked" | "reserve_full" | "played_two" | "oldest_of_its_name" | "no_snowball_in_hand_or_deck".

const NAMES := ["momentum_left", "unspent_momentum", "momentum_leaked", "reserve_full", "played_two", "oldest_of_its_name", "no_snowball_in_hand_or_deck"]

var name := ""

func _init(flag_name: String) -> void:
	name = flag_name

func check(context: EffectContext) -> bool:
	var player: Dictionary = context.game.players[context.controller]
	match name:
		"momentum_left": return player["momentum"] > 0
		"unspent_momentum": return player["unspent"] > 0 # plain Momentum left over at the start of this turn
		"momentum_leaked": return player["leaked"] > 0 # Momentum that spilled past the Reserve last turn
		"reserve_full": return player["reserve"] >= GameState.RESERVE_CAP
		"played_two": return player["played_two"]
		"oldest_of_its_name": return _is_oldest_copy_on_board(context, player)
		"no_snowball_in_hand_or_deck":
			return not _has_snowball(player["hand"]) and not _has_snowball(player["deck"])
	return true

func _has_snowball(cards: Array) -> bool:
	for card: Card in cards:
		if card.card_id in [GameState.SNOWBALL_CARD_ID, GameState.GRANDE_SNOWBALL_CARD_ID]:
			return true
	return false

## True when no other copy of the same card entered the controller's board before this unit.
## Uids only grow, so the smallest uid among the copies in play is the oldest one.
## Used by Cobrador de Pedágio Torto: only the first copy in play gives its Momentum.
func _is_oldest_copy_on_board(context: EffectContext, player: Dictionary) -> bool:
	var source_id := context.source_id()
	for unit: Card in player["board"]:
		if unit.card_id == source_id and unit.uid < context.self_uid:
			return false
	return true
