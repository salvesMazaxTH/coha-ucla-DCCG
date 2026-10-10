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
var not_in_combat := false ## "not_in_combat": the trigger is ignored during combat damage

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
	not_in_combat = bool(data.get("not_in_combat", false))
	_read_parameters(data)

## Subclasses copy their JSON parameters (amount, atk, keywords...) into fields here.
func _read_parameters(_data: Dictionary) -> void:
	pass

## Static effects never run from a trigger: "constante" ones are read by the scaling code and
## cost reductions by the cost code.
func is_static() -> bool:
	return trigger == "constante"

## True for effects that open a choice for the player after they resolve (search, look...).
func opens_choice() -> bool:
	return false

## Opens that choice (only called when opens_choice() is true).
func open_choice(_context: EffectContext) -> void:
	pass

## Applies the effect to one target. Escudo de Feitiço comes first: the first effect from the
## enemy side that hits a shielded unit is cancelled and breaks the shield.
func apply_to(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var hit_unit: Card = game.find_unit(target_uid) if target_uid > 0 else null
	if hit_unit != null and hit_unit.owner != context.controller and hit_unit.spell_shield:
		hit_unit.spell_shield = false
		game._emit({"type": "spell_shield_break", "uid": target_uid})
		return
	apply(context, target_uid)

## What the effect does to one target (target_uid is a unit, a negative Leader uid, or 0).
func apply(_context: EffectContext, _target_uid: int) -> void:
	pass
