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
## "listen": the effect reacts to a game event from anywhere (see TriggerBus). Its `trigger` then
## becomes LISTEN_PREFIX + the event name, so no ordinary trigger ever matches it.
var listen := ""
var scope := "any" ## listen only: self | ally | enemy | any, relative to the card that listens
var zones: Array = ["board"] ## listen only: where the card must be ("any" = every zone)
var when: Dictionary = {} ## listen only: facts the event must have, e.g. {"to": "graveyard"}

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
	if data.has("listen"):
		listen = String(data["listen"])
		trigger = LISTEN_PREFIX + listen
		scope = String(data.get("scope", "any"))
		var zone_list: Variant = data.get("zones", ["board"])
		zones = TriggerBus.ZONES.duplicate() if zone_list is String else zone_list
		when = data.get("when", {})
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

## Applies the effect to one target. Escudo de Feitiço comes first: the first effect from the
## enemy side that hits a shielded unit is cancelled and breaks the shield, and the card's later
## effects in the same run skip that unit too (the shield cancels the whole card on it). Separate
## hits of the same effect (Repique Desgovernado) are separate spells: only the first is cancelled.
func apply_to(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var hit_unit: Card = game.find_unit(target_uid) if target_uid > 0 else null
	if hit_unit != null and hit_unit.owner != context.controller:
		if context.shielded_uids.has(target_uid):
			return
		if hit_unit.spell_shield:
			hit_unit.spell_shield = false
			context.shielded_this_effect.append(target_uid)
			game._emit({"type": "spell_shield_break", "uid": target_uid})
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
