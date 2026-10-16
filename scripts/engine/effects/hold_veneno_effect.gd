class_name HoldVenenoEffect
extends Effect
## "hold_veneno": for a limited time, Veneno markers still hurt at their turn start but are NOT consumed.
##   "reach": "leader"    only the targeted Leader's markers (use target "enemy_leader");
##            "everyone"  every unit's and Leader's markers (use target "none").
##   "turn_starts": N     how many turn starts the hold covers (default 2).
##     reach "leader": the Leader's own turn starts, so 2 = its next two turns.
##     reach "everyone": turn starts of either player, so 2 = one for each player (one full round).
## Only Veneno is held; Queimadura and Sangramento keep being consumed. Casting it again never
## shortens a hold that is already running.

var reach := "leader"
var turn_starts := 2

func _read_parameters(data: Dictionary) -> void:
	reach = String(data.get("reach", "leader"))
	turn_starts = maxi(1, int(data.get("turn_starts", 2)))

func apply(context: EffectContext, target_uid: int) -> void:
	if reach == "everyone":
		context.game.hold_veneno_for_everyone(turn_starts)
		return
	var leader_player := GameState.LEADER_UID.find(target_uid)
	if leader_player >= 0:
		context.game.hold_veneno_on_leader(leader_player, turn_starts)
