class_name ResolveDotEffect
extends Effect
## "resolve_dot": makes the target's markers of one kind tick right now, exactly like at the start of its
## owner's turn (damage by the markers, then the usual wear-off), instead of waiting for that turn.
##   "dot": the marker kind that ticks (default "sangramento"). Other kinds on the target stay untouched.
##   "consume": false = the markers hurt but none wear off ("ferem, mas ficam", like a held Veneno), so
##              they still tick at the next turn start. Default true (the normal wear-off).
## Works on a unit or on a Leader (negative uid). A target without those markers takes nothing.

var dot := "sangramento"
var consume := true

func _read_parameters(data: Dictionary) -> void:
	dot = String(data.get("dot", "sangramento"))
	consume = bool(data.get("consume", true))

func apply(context: EffectContext, target_uid: int) -> void:
	var leader_player := GameState.LEADER_UID.find(target_uid)
	if leader_player >= 0:
		context.game._resolve_leader_dot(leader_player, dot, not consume)
		return
	context.game.resolve_dot(context.game.find_unit(target_uid), dot, not consume)
