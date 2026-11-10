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
## A unit that is already borrowed is never taken again (its real owner would be forgotten).
##
## "swap_with_self": true turns the steal into an exchange of sides (Bruce's Ao Ativar): the unit that owns the
## ability goes to the enemy field in the same moment, so the thief's field keeps the same number of units
## and no free slot is needed. Both units come home at the end of the turn.

var until := "end_of_turn"
var swap_with_self := false

func _read_parameters(data: Dictionary) -> void:
	until = String(data.get("until", "end_of_turn"))
	swap_with_self = bool(data.get("swap_with_self", false))

## Why a unit cannot be taken right now (used both to filter the targets and to guard the effect itself).
## `swapping`: the thief gives a unit in exchange, so a full field is no obstacle.
static func can_take(game: GameState, thief: int, unit: Card, swapping := false) -> bool:
	if unit == null or unit.owner == thief or unit.zone != "board":
		return false
	if unit.incarnation or unit.home_owner >= 0:
		return false
	return swapping or game.has_free_slot(thief)

## True when `source` (the unit that carries a swap ability) can go to the enemy side: it must be standing on
## the field, be the thief's own unit (not a borrowed one) and not be an Encarnação.
static func can_be_swapped_out(source: Card) -> bool:
	return source != null and source.zone == "board" and not source.incarnation and source.home_owner < 0

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var unit := game.find_unit(target_uid)
	var thief := context.controller
	var source: Card = null
	if swap_with_self:
		source = game.find_unit(context.self_uid)
		# the exchange needs both halves: without the source on the field nothing happens at all
		if not can_be_swapped_out(source) or source.owner != thief:
			return
	if not can_take(game, thief, unit, swap_with_self):
		return
	var victim: int = unit.owner
	_move_to_side(game, unit, thief, true)
	if source != null:
		# the unit that gives itself in the exchange stays as it is (it already paid its activation by exhausting),
		# so the enemy gets no free attacker out of it
		_move_to_side(game, source, victim, false)

## Sends `unit` to `new_controller`'s board for the rest of the turn, remembering who really owns it.
## `ready_to_fight`: the new master can attack with it right away (the stolen unit; not the one given in a swap).
func _move_to_side(game: GameState, unit: Card, new_controller: int, ready_to_fight: bool) -> void:
	var real_owner: int = unit.owner
	game.players[real_owner]["board"].erase(unit)
	game.players[new_controller]["board"].append(unit)
	unit.home_owner = real_owner
	unit.owner = new_controller
	if ready_to_fight:
		unit.sick = false # borrowed to fight: it can attack the turn it is taken
		if not unit.is_frozen() and not unit.is_stunned():
			unit.exhausted = false # a unit that attacked on its own turn is still tapped: it is straightened for its new master
	game.emit_event({"type": "control_change", "uid": unit.uid, "from": real_owner, "to": new_controller})
