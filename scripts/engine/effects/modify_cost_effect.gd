class_name ModifyCostEffect
extends Effect
## "modify_cost": changes the cost of the target card by `amount` (negative = cheaper) for the rest
## of the match, in whatever zone it is. Use target "self_card" so a card can cheapen itself.
## "per": "unspent_momentum" multiplies `amount` by the plain Momentum the controller left unspent
## (the Bateria never counts). "max_per_turn" caps how much one trigger may change the cost (Voltexz: 4).
## "min_cost" stops a reduction at that cost, taking only what fits.
## The Encarnação keeps its total on the player (see GameState.add_cost_mod), so it also works from the Santuário
## (target uid 0).

var amount := 0
var per := ""
var min_cost := 0
var max_per_turn := 0

func _read_parameters(data: Dictionary) -> void:
	amount = int(data.get("amount", 0))
	per = String(data.get("per", ""))
	min_cost = int(data.get("min_cost", 0))
	max_per_turn = int(data.get("max_per_turn", 0))

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var change := amount
	if per == "unspent_momentum":
		change *= int(game.players[context.controller]["unspent"])
	if max_per_turn > 0:
		change = clampi(change, -max_per_turn, max_per_turn)
	if change == 0:
		return
	var card: Card = game.find_card(target_uid) if target_uid > 0 else null
	if target_uid > 0 and card == null:
		return
	game.add_cost_mod(context.controller, card, change, min_cost)
