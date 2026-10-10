class_name EffectContext
extends RefCounted
## Everything one run of effects needs to know: who controls it, what triggered it and which
## targets were picked. It replaces the old loose GameState variables (_chosen2, _sac_atk,
## _dying, _milled), so nothing leaks from one effect run into an unrelated one.

var game: GameState
var controller := 0 ## the player whose effects are running
var trigger := "" ## the trigger being resolved ("" = run every effect, e.g. spells on the stack)
var self_uid := 0 ## the unit whose effects these are (0 for spells and leader abilities)
var other_uid := 0 ## the opposing unit in combat triggers (blocker, attacker, damage source)
var chosen_target := 0 ## the target picked when the card was played
var second_target := 0 ## the second pick ("pick"/"pick2", e.g. the damage target of a sacrifice spell)
var dying_card: Card = null ## the unit whose Ao Morrer is resolving (for summon "self" and revive_self)
var sacrificed_attack := 0 ## total attack of the unit a "sacrifice" just killed (read by its "then" effects)
var event: GameEvent = null ## the event that made a listening card react (null for plain triggers)
var milled_cards: Array = [] ## cards the latest mill of this run sent to the graveyard (offered by mill_pick)

func _init(game_state: GameState, controller_player: int, trigger_name: String = "") -> void:
	game = game_state
	controller = controller_player
	trigger = trigger_name

func opponent() -> int:
	return game.opponent(controller)

## The context for a sacrifice's "then" effects: no trigger filter, no source unit, and the
## second pick becomes the chosen target. The dying unit carries over.
func for_then_effects() -> EffectContext:
	var child := EffectContext.new(game, controller, "")
	child.chosen_target = second_target
	child.second_target = second_target
	child.dying_card = dying_card
	return child
