class_name ControlEffect
extends Effect
## "take_control": the effect's controller takes the control of an enemy unit until the end of the turn
## ("until": "end_of_turn", the only duration so far). While borrowed, the unit sits on the thief's board, can
## attack right away (it is not summoned, so no Ao Entrar fires) and counts as the thief's unit for every
## rule (targets, Provocação, Momentum, triggers). At the end of the turn it goes back to its real owner's board.
##
## The real owner is remembered in Card.home_owner. Anything that makes the unit leave the board meanwhile
## (death, bounce, banish) sends it to the real owner's zone, see GameState._end_borrowed_control.
## The thief needs a free slot on their field; an Encarnação is never taken (it belongs to its Leader).

var until := "end_of_turn"

func _read_parameters(data: Dictionary) -> void:
	until = String(data.get("until", "end_of_turn"))

## Why a unit cannot be taken right now (used both to filter the targets and to guard the effect itself).
static func can_take(game: GameState, thief: int, unit: Card) -> bool:
	if unit == null or unit.owner == thief or unit.zone != "board":
		return false
	if unit.incarnation:
		return false
	return game.has_free_slot(thief)

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var unit := game.find_unit(target_uid)
	var thief := context.controller
	if not can_take(game, thief, unit):
		return
	var victim: int = unit.owner
	game.players[victim]["board"].erase(unit)
	game.players[thief]["board"].append(unit)
	unit.home_owner = victim
	unit.owner = thief
	unit.sick = false # borrowed to fight: it can attack the turn it is taken
	if not unit.is_frozen() and not unit.is_stunned():
		unit.exhausted = false # a unit that attacked on its own turn is still tapped: it is straightened for its new master
	game._emit({"type": "control_change", "uid": unit.uid, "from": victim, "to": thief})
