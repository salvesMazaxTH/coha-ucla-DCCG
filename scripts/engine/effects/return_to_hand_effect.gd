class_name ReturnToHandEffect
extends Effect
## "return_to_hand": the target card goes back to its owner's hand (a bounce, or a card coming back from the graveyard).
## It is not a death: a unit sent back from the board has no Ao Morrer or Aliado Morre; its permanent buffs stay with it,
## and its equipment returns separately to its owner's hand.
## Use any unit target to bounce a unit, or "self_card" on an "on_death" trigger so the dying card comes back from the graveyard.
##   "cost_increase": N (optional, default 0): the card costs N more from now on, every time it comes back, with no cap
##   (used with "cost_increase_doubles", Nerithia's increase starts at 2 and doubles on each return).
##   "cost_increase_doubles": true (optional): double the next increase on each return, starting at "cost_increase".
##   "discount_returned_this_turn": N (optional, default 0): only when the target really reaches the hand,
##   the returned card costs N less until the end of the turn (Naelys, and her Leader's Maré de Retorno).
##   "needs_drawn_card": true (optional): the return only happens if a card was drawn earlier in this same
##   effect run (Naelys pays for the return with her draw).

var cost_increase := 0
var cost_increase_doubles := false
var discount_returned_this_turn := 0
var needs_drawn_card := false

func _read_parameters(data: Dictionary) -> void:
	cost_increase = int(data.get("cost_increase", 0))
	cost_increase_doubles = bool(data.get("cost_increase_doubles", false))
	discount_returned_this_turn = int(data.get("discount_returned_this_turn", 0))
	needs_drawn_card = bool(data.get("needs_drawn_card", false))

func apply(context: EffectContext, target_uid: int) -> void:
	var card := context.game.find_card(target_uid)
	if card == null or (needs_drawn_card and context.last_drawn_card == null):
		return
	var increase := cost_increase + card.cost_mod if cost_increase_doubles else cost_increase
	var owner_player := card.owner
	if context.game.return_to_hand(card, increase):
		if owner_player == context.controller:
			context.returned_ally_count += 1
		if discount_returned_this_turn > 0:
			card.turn_discount += discount_returned_this_turn
