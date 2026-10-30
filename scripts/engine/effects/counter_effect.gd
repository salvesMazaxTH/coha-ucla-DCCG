class_name CounterEffect
extends Effect
## "counter": cancels the chosen card on the stack. Not stopped by Escudo Mágico (it hits a
## stack item, not a unit), so it skips that check.
## The filters that decide which stack items it may hit ("max_cost", "only_if_ability"...) live in
## StackSystem.counter_extra.
## "owner_draws": N gives the player whose spell/ability was countered N cards (Contracorrente).
## "owner_gains_momentum": N gives that player N Momentum (Atraso de Voo).
## Both consolation prizes are paid only when the item really was cancelled.

var owner_draws := 0
var owner_gains_momentum := 0

func _read_parameters(data: Dictionary) -> void:
	owner_draws = int(data.get("owner_draws", 0))
	owner_gains_momentum = int(data.get("owner_gains_momentum", 0))

func apply_to(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var countered_item := game.stack_system().stack_item(target_uid)
	if countered_item.is_empty():
		return
	var item_owner := int(countered_item["player"])
	game._counter(context.controller, target_uid)
	if not game.stack_system().stack_item(target_uid).is_empty():
		return # it was uncounterable: nothing was cancelled, so nobody gets the prize
	if owner_draws > 0:
		game._draw(item_owner, owner_draws)
	if owner_gains_momentum > 0:
		game.gain_momentum(item_owner, owner_gains_momentum)
