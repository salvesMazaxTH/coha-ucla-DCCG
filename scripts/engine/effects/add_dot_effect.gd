class_name AddDotEffect
extends Effect
## "add_dot": adds `amount` accumulated periodic-status markers to each target unit, or to a
## targeted Leader (negative uid; Leader markers stay all game, see GameState.add_leader_dot_markers).
## `dot` identifies the marker type (queimadura, veneno; sangramento can reuse this action too).

var dot := "queimadura"
var amount := 0

func _read_parameters(data: Dictionary) -> void:
	dot = String(data.get("dot", "queimadura"))
	amount = maxi(0, int(data.get("amount", 0)))

func apply(context: EffectContext, target_uid: int) -> void:
	if amount <= 0:
		return
	if target_uid < 0:
		context.game.add_leader_dot_markers(GameState.LEADER_UID.find(target_uid), dot, amount)
		return
	var unit := context.game.find_unit(target_uid)
	if unit == null:
		return
	context.game.add_dot_markers(unit, dot, amount)
