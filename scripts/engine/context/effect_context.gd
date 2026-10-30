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
var source_card_id := "" ## the card being resolved from the stack (spells...), "" when a unit's own effect runs
var is_leader_ability := false ## these effects are a Leader's ability
var chosen_target := 0 ## the target picked when the card was played
var forced_target := false ## the chosen target needs no re-check (a Bola de Neve cast by a unit aims at what the unit attacked)
var second_target := 0 ## the second pick ("pick"/"pick2", e.g. the damage target of a sacrifice spell)
var dying_card: Card = null ## the unit whose Ao Morrer is resolving (for summon "self" and revive_self)
var sacrificed_attack := 0 ## total attack of the unit a "sacrifice" just killed (read by its "then" effects)
var sacrificed_cost := 0 ## printed Momentum cost of the unit a "sacrifice" just killed (read by its "then" effects)
var returned_ally_count := 0 ## allied units a "return_to_hand" of this run sent back to the hand (read by "gain_momentum" per "returned_allies")
var last_drawn_card: Card = null ## the latest card drawn by this effect run, for follow-up effects
var event: GameEvent = null ## the event that made a listening card react (null for plain triggers)
var milled_cards: Array = [] ## cards the latest mill of this run sent to the graveyard (offered by mill_pick)

var shielded_uids: Array[int] = [] ## units whose shield cancelled an earlier effect of this run: the card's later aimed effects skip them
var shielded_this_effect: Array[int] = [] ## shields broken by the effect running now; repeated hits of one effect (Repique) are independent, so they only count once that effect is over

func _init(game_state: GameState, controller_player: int, trigger_name: String = "") -> void:
	game = game_state
	controller = controller_player
	trigger = trigger_name

func opponent() -> int:
	return game.opponent(controller)

## The card these effects come from: the spell/card on the stack, else the unit running its own
## effect (alive on the board or the one whose Ao Morrer is resolving). "" for Leader abilities.
func source_id() -> String:
	if source_card_id != "":
		return source_card_id
	if dying_card != null:
		return dying_card.card_id
	var source_unit: Card = game.find_unit(self_uid) if self_uid > 0 else null
	return source_unit.card_id if source_unit != null else ""

## Who is healing when an effect of this run heals: "unit" (a unit's own effect, including its Ao Morrer and
## Ativar), "spell" (a spell from the stack), "artifact" (an artifact or equipment), "leader_ability" (the
## Leader's ability). It travels in the heal events as `healed_by`, so a listener can ask for a given origin.
func heal_origin() -> String:
	if is_leader_ability:
		return "leader_ability"
	if source_card_id != "":
		var source_type := String(CardDB.card(source_card_id).get("type", ""))
		return "spell" if source_type == "spell" else "artifact"
	if dying_card != null or game.find_unit(self_uid) != null:
		return "unit"
	return "artifact" if self_uid > 0 else ""

## The context for a sacrifice's "then" effects: no trigger filter, and the second pick becomes
## the chosen target. The dying unit, the unit whose effect this is (so "self" in a "then" still
## means the sacrificer, e.g. Esther) and where the effects come from (the spell or ability that
## sacrificed) carry over.
func for_then_effects() -> EffectContext:
	var child := EffectContext.new(game, controller, "")
	child.self_uid = self_uid
	child.source_card_id = source_card_id
	child.is_leader_ability = is_leader_ability
	child.chosen_target = second_target
	child.second_target = second_target
	child.dying_card = dying_card
	return child
