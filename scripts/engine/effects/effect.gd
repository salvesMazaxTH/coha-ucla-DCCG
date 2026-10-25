class_name Effect
extends RefCounted
## Base class of one entry of a card's "effects" (cards.json). Each "action" is a subclass
## (DamageEffect, BuffEffect...); EffectRegistry builds them from the JSON. This base class is
## also what an unknown action becomes: an effect that does nothing.
##
## A new action: write a subclass that overrides _read_parameters() and apply(), then add one
## line to EffectRegistry.ACTIONS.

var action := "" ## the JSON "action", e.g. "damage"
var trigger := "" ## when it runs: "on_enter", "on_death"... ("" = whenever its card resolves)
var raw: Dictionary = {} ## the original JSON entry, for parameters read elsewhere (search filters...)
var target_name := "" ## the JSON "target", e.g. "enemy_unit"
var target: TargetSelector ## decides which uids the effect hits
var condition: Condition = null ## the optional "if"; null = always runs
var uses_second_pick := false ## "pick2": hits the card's second pick instead of the first
var once_per_turn := false ## "once_per_turn": the trigger works once per turn per unit
var own_turn_only := false ## "own_turn_only": the trigger is ignored during the opponent's turn
var not_in_combat := false ## "not_in_combat": the trigger is ignored during combat damage
var not_token := false ## "not_token": an Aliado Morre trigger is ignored when the unit that died was a ficha (Cientista da Morte)
## "shout": a line the card yells when this effect actually runs (its "if" passed). Purely cosmetic: the
## engine only emits a "shout" event and the UI draws it big over the card (Barão Estrondoso).
var shout := ""
## "listen": the effect reacts to a game event from anywhere (see TriggerBus). Its `trigger` then
## becomes LISTEN_PREFIX + the event name, so no ordinary trigger ever matches it.
var listen := ""
var scope := "any" ## listen only: self | ally | enemy | any, relative to the card that listens
var zones: Array = ["board"] ## listen only: where the card must be ("any" = every zone)
var when: Dictionary = {} ## listen only: facts the event must have, e.g. {"to": "graveyard"}
var min_amount := 0 ## listen only: the event's amount (healing, damage...) must be at least this much

const LISTEN_PREFIX := "listen_"
const SCOPES := ["self", "ally", "enemy", "any"]

## Fills the shared fields, then lets the subclass read its own parameters.
func setup(data: Dictionary) -> void:
	raw = data
	action = String(data.get("action", ""))
	trigger = String(data.get("trigger", ""))
	target_name = String(data.get("target", ""))
	target = TargetRegistry.make(target_name)
	condition = ConditionRegistry.parse(data.get("if", ""))
	uses_second_pick = bool(data.get("pick2", false))
	once_per_turn = bool(data.get("once_per_turn", false))
	own_turn_only = bool(data.get("own_turn_only", false))
	not_in_combat = bool(data.get("not_in_combat", false))
	not_token = bool(data.get("not_token", false))
	shout = String(data.get("shout", ""))
	if data.has("listen"):
		listen = String(data["listen"])
		trigger = LISTEN_PREFIX + listen
		scope = String(data.get("scope", "any"))
		var zone_list: Variant = data.get("zones", ["board"])
		zones = TriggerBus.ZONES.duplicate() if zone_list is String else zone_list
		when = data.get("when", {})
		min_amount = int(data.get("min_amount", 0))
	_read_parameters(data)

## Subclasses copy their JSON parameters (amount, atk, keywords...) into fields here.
func _read_parameters(_data: Dictionary) -> void:
	pass

## True when a card in `zone` should hear this listening effect.
func listens_in(zone: String) -> bool:
	return zone in zones

## Static effects never run from a trigger: "constante" ones are read by the scaling code and
## cost reductions by the cost code.
func is_static() -> bool:
	return trigger == "constante"

## True when `unit` already has the status this effect applies (Congelada for "freeze", exausta for
## "exhaust"...). A random pick never lands on such a unit, so a status effect is never wasted on a
## unit that already has it. Effects that aren't a status (damage, buff...) leave this false.
func is_already_applied_to(_unit: Card) -> bool:
	return false

## True for effects that open a choice for the player after they resolve (search, look...).
func opens_choice() -> bool:
	return false

## Opens that choice (only called when opens_choice() is true).
func open_choice(_context: EffectContext) -> void:
	pass

## Escudo Mágico, the one place that decides it. True when `unit`'s shield cancels this effect.
## It works like a temporary Inalcançável: the unit can still be picked as a target, but an effect from the
## enemy side that AIMS at it (a chosen target, from any source: spell, unit, artifact, Leader ability) does
## nothing to it and only breaks the shield. Area, random and untargeted effects (aimed_by_choice false) pass
## through it whole and the shield stays, as do the effects of the unit's own side. Once broken, the card's
## later aimed effects in the same run skip that unit too (the shield cancels the whole card on it).
func cancelled_by_magic_shield(context: EffectContext, unit: Card, aimed_by_choice: bool) -> bool:
	if unit.owner == context.controller or not aimed_by_choice:
		return false
	if context.shielded_uids.has(unit.uid):
		return true
	if not unit.magic_shield:
		return false
	unit.magic_shield = false
	context.shielded_this_effect.append(unit.uid)
	context.game._emit({"type": "magic_shield_break", "uid": unit.uid})
	return true

## True for effects that hurt the card they land on even when they come from its own side (destroy, banish,
## sacrifice): Escudo Supremo absorbs those too. Every other own-side effect passes through it.
func harms_own_target() -> bool:
	return false

## Escudo Supremo, the one place that decides it. True when `holder` (a unit or a free-standing artifact) has the
## charge and this effect is aimed at it: any effect from the enemy side, whatever its origin (spell, unit, artifact,
## Leader ability), or an own-side effect that harms it. The charge is spent, and the card's later effects in the same
## run skip that holder too. Escudo Mágico is tried first, so the stronger shield is kept when the weaker one is enough.
func absorbed_by_supreme_shield(context: EffectContext, holder: Card) -> bool:
	if not holder.supreme_shield and not context.shielded_uids.has(holder.uid):
		return false
	if holder.owner == context.controller and not harms_own_target():
		return false
	if context.shielded_uids.has(holder.uid):
		return true
	context.game.spend_supreme_shield(holder, context.self_uid)
	context.shielded_this_effect.append(holder.uid)
	return true

## Every shield that can stop this effect on `holder`, weakest first. aimed_by_choice: the effect lands on
## `holder` because it was picked as the target (Escudo Mágico only stops those).
func cancelled_by_any_shield(context: EffectContext, holder: Card, aimed_by_choice: bool) -> bool:
	return cancelled_by_magic_shield(context, holder, aimed_by_choice) or absorbed_by_supreme_shield(context, holder)

## Applies the effect to one target. Shields come first (see cancelled_by_any_shield).
func apply_to(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var hit_unit: Card = game.find_unit(target_uid) if target_uid > 0 else null
	var held_card: Card = hit_unit if hit_unit != null else (game.find_relic(target_uid) if target_uid > 0 else null)
	# an enemy effect AIMS at this unit (a chosen target): tell the listeners (Sino), even if a shield then stops the effect
	if hit_unit != null and hit_unit.owner != context.controller and target.needs_choice():
		var targeted := GameEvent.new("unit_targeted", hit_unit.owner, hit_unit)
		targeted.other_uid = context.self_uid
		game.bus().emit(targeted)
	if held_card != null and cancelled_by_any_shield(context, held_card, target.needs_choice()):
		return
	# Imunidade contra <essência>: a card of that essence from the enemy side has no effect on the unit it AIMS at
	# (nothing is spent). Untargeted and area effects still reach it, as with Inalcançável.
	if hit_unit != null and hit_unit.owner != context.controller and target.needs_choice() \
			and game.is_immune_to_essence_of(hit_unit, context.source_id()):
		game._emit({"type": "dot_immune", "uid": target_uid, "dot": ""})
		return
	apply(context, target_uid)

## What the effect does to one target (target_uid is a unit, a negative Leader uid, or 0).
func apply(_context: EffectContext, _target_uid: int) -> void:
	pass
