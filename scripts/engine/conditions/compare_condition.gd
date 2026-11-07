class_name CompareCondition
extends Condition
## Compares a number of the game against a value:
## {"compare": {"stat": "leader_hp", "who": "enemy", "op": "<", "value": 12}}
## stat: leader_hp | momentum | reserve | units | hand | deck | graveyard
##       source_hp | source_armor: a number of the unit that carries the effect (only in a card's own "if",
##       not in a play_condition). Drex: {"stat": "source_hp", "op": ">=", "value": 10} = phase 2.
## who: "self" (the effect's controller, default) or "enemy"
## "vs": "enemy" compares against the enemy's same stat (plus "value" as an offset, default 0) instead of a plain number:
## {"stat": "units", "op": ">", "vs": "enemy"} = "you have more units than the opponent" (Magni's play_condition).

const UNIT_STATS := ["source_hp", "source_armor"]
const STATS := ["leader_hp", "momentum", "reserve", "units", "hand", "deck", "graveyard", "source_hp", "source_armor"]
const OPERATORS := ["<", "<=", "==", "!=", ">=", ">"]

var stat := ""
var who := "self"
var operator := ">="
var value := 0
var versus_enemy := false

func _init(spec: Dictionary) -> void:
	stat = String(spec.get("stat", ""))
	who = String(spec.get("who", "self"))
	operator = String(spec.get("op", ">="))
	value = int(spec.get("value", 0))
	versus_enemy = String(spec.get("vs", "")) == "enemy"

func check(context: EffectContext) -> bool:
	if stat in UNIT_STATS:
		return _compare(_read_source_unit_stat(context))
	return check_players(context.game, context.controller)

## The effect's own unit (the card that is reacting) read through "source_hp" (maximum Vida with every buff,
## damage not subtracted) or "source_armor" (the Armadura it really has). 0 when the source is no longer on the board.
func _read_source_unit_stat(context: EffectContext) -> int:
	var unit := context.game.find_unit(context.self_uid)
	if unit == null:
		return 0
	return unit.hp_total() if stat == "source_hp" else context.game.armor_of(unit)

## The same comparison without an effect context: `controller` is the player the "self" side means.
## Used by a card's play_condition, which is checked before the card is played (GameState.play_condition_met).
func check_players(game: GameState, controller: int) -> bool:
	var player_index := 1 - controller if who == "enemy" else controller
	var current := _read_stat(game.players[player_index])
	var target_value := value
	if versus_enemy:
		target_value += _read_stat(game.players[1 - player_index])
	return _compare(current, target_value)

## `current` against `target_value` with this condition's operator.
func _compare(current: int, target_value := value) -> bool:
	match operator:
		"<": return current < target_value
		"<=": return current <= target_value
		"==": return current == target_value
		"!=": return current != target_value
		">=": return current >= target_value
		">": return current > target_value
	return false

func _read_stat(player: Dictionary) -> int:
	match stat:
		"leader_hp": return int(player["leader_hp"])
		"momentum": return int(player["momentum"])
		"reserve": return int(player["reserve"])
		"units": return player["board"].size()
		"hand": return player["hand"].size()
		"deck": return player["deck"].size()
		"graveyard": return player["graveyard"].size()
	return 0

## The compare specs of a card's play_condition: {"compare": {...}} is one, {"all": [{"compare": {...}}, ...]} is
## several that must all hold (Magni). Returns [] when the shape is wrong (the catalog check reports it).
static func play_condition_specs(play_condition: Dictionary) -> Array:
	var specs: Array = []
	if play_condition.has("compare"):
		specs.append(play_condition["compare"])
	elif play_condition.has("all") and play_condition["all"] is Array:
		for part in play_condition["all"]:
			if not part is Dictionary or not part.has("compare"):
				return []
			specs.append(part["compare"])
	return specs

## The problem with a compare spec, or "" when it is valid (checked when the catalog loads).
static func error_of(spec: Variant) -> String:
	if not spec is Dictionary:
		return "compare precisa ser um objeto"
	if String(spec.get("stat", "")) not in STATS:
		return "compare.stat desconhecido \"%s\"" % spec.get("stat", "")
	if String(spec.get("who", "self")) not in ["self", "enemy"]:
		return "compare.who desconhecido \"%s\"" % spec.get("who", "")
	if String(spec.get("op", ">=")) not in OPERATORS:
		return "compare.op desconhecido \"%s\"" % spec.get("op", "")
	if spec.has("vs") and String(spec["vs"]) != "enemy":
		return "compare.vs desconhecido \"%s\"" % spec["vs"]
	return ""
