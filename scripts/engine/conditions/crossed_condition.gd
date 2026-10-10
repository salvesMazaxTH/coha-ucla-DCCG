class_name CrossedCondition
extends Condition
## True when a Leader's life just crossed a line, read from the leader_damaged / leader_healed
## event that is being resolved (so it fires once, not while the life stays on that side):
## {"crossed_below": {"who": "enemy", "value": 12}}  -> was 12 or more, is now below 12
## {"crossed_above": {"who": "self", "value": 20}}   -> was below 20, is now 20 or more

var below := true ## true = crossed_below, false = crossed_above
var who := "self"
var value := 0

func _init(is_below: bool, spec: Dictionary) -> void:
	below = is_below
	who = String(spec.get("who", "self"))
	value = int(spec.get("value", 0))

func check(context: EffectContext) -> bool:
	var event := context.event
	if event == null:
		return false
	var player_index := context.opponent() if who == "enemy" else context.controller
	if event.player != player_index:
		return false
	if below:
		return event.hp_before >= value and event.hp_after < value
	return event.hp_before < value and event.hp_after >= value

static func error_of(spec: Variant) -> String:
	if not spec is Dictionary:
		return "crossed precisa ser um objeto"
	if String(spec.get("who", "self")) not in ["self", "enemy"]:
		return "crossed.who desconhecido \"%s\"" % spec.get("who", "")
	if not spec.has("value"):
		return "crossed sem \"value\""
	return ""
