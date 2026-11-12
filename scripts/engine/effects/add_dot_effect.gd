class_name AddDotEffect
extends Effect
## "add_dot": adds `amount` accumulated periodic-status markers to each target unit, or to a
## targeted Leader (negative uid; Leader markers hurt and wear off at the start of its controller's turn like a unit's, see GameState.add_leader_dot_markers).
## `dot` identifies the marker type (queimadura, veneno; sangramento can reuse this action too).

## Units of some elements are innately immune to some markers (GameState.DOT_IMMUNE_ELEMENTS); Leaders never are.
## "ignores_immunity": true makes this effect put the markers on anyway; the card text must say so.

var dot := "queimadura"
var amount := 0
var ignores_immunity := false
var leader_gets_half := false ## true = a Leader target receives half the markers (rounded down, never less than 1)
var amount_from := "" ## "" = use `amount`; "event_amount" = the amount of the event a Condicional heard (unit_died: the dead unit's Veneno markers)

func _read_parameters(data: Dictionary) -> void:
	dot = String(data.get("dot", "queimadura"))
	amount = maxi(0, int(data.get("amount", 0)))
	ignores_immunity = bool(data.get("ignores_immunity", false))
	amount_from = String(data.get("amount_from", ""))
	leader_gets_half = bool(data.get("leader_gets_half", false))

func apply(context: EffectContext, target_uid: int) -> void:
	var markers := amount
	if amount_from == "event_amount" and context.event != null:
		markers = context.event.amount
	if markers <= 0:
		return
	if target_uid < 0:
		if leader_gets_half:
			markers = maxi(1, markers / 2)
		context.game.add_leader_dot_markers(GameState.LEADER_UID.find(target_uid), dot, markers)
		return
	var unit := context.game.find_unit(target_uid)
	if unit == null:
		return
	context.game.add_dot_markers(unit, dot, markers, ignores_immunity)
