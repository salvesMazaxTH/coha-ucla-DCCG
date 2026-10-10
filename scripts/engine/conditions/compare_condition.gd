class_name CompareCondition
extends Condition
## Compares a number of the game against a value:
## {"compare": {"stat": "leader_hp", "who": "enemy", "op": "<", "value": 12}}
## stat: leader_hp | momentum | reserve | units | hand | deck | graveyard
## who: "self" (the effect's controller, default) or "enemy"

const STATS := ["leader_hp", "momentum", "reserve", "units", "hand", "deck", "graveyard"]
const OPERATORS := ["<", "<=", "==", "!=", ">=", ">"]

var stat := ""
var who := "self"
var operator := ">="
var value := 0

func _init(spec: Dictionary) -> void:
	stat = String(spec.get("stat", ""))
	who = String(spec.get("who", "self"))
	operator = String(spec.get("op", ">="))
	value = int(spec.get("value", 0))

func check(context: EffectContext) -> bool:
	var player_index := context.opponent() if who == "enemy" else context.controller
	var current := _read_stat(context.game.players[player_index])
	match operator:
		"<": return current < value
		"<=": return current <= value
		"==": return current == value
		"!=": return current != value
		">=": return current >= value
		">": return current > value
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
	return ""
