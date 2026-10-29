class_name SummonCopyEffect
extends Effect
## "summon_copy" (target "ally_unit", usually with "not_rarity": ["champion"]): creates a FICHA that is an IDENTICAL copy
## of the chosen allied unit: same card, same per-instance overrides and EVERY modifier it carries right now, good or
## bad (damage, permanent and temporary buffs and debuffs, Armadura, keywords, shields, Congelada, Atordoamento, Condenada,
## periodic-status markers...). The equipment it wears is not duplicated, but what the equipment gave stays in the stats.
## Not copied: whether it is tapped or summoning-sick and its "once per turn" counters; the copy has just arrived.
## "suppress_on_enter": true makes the copy NOT fire its own Ao Entrar (the Ao Entrar effects of OTHER cards still react
## to a unit entering). Because the copy keeps the card_id, it counts for effects that count copies (Elefante Incomodante).
## As a ficha it vanishes instead of going to the graveyard or back to the hand.
## Nothing happens when the field has no free slot or the target is gone.

var suppress_on_enter := false

func _read_parameters(data: Dictionary) -> void:
	suppress_on_enter = bool(data.get("suppress_on_enter", false))

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var original := game.find_unit(target_uid)
	if original == null or not game.has_free_slot(context.controller):
		return
	var overrides: Dictionary = original.over.duplicate(true)
	overrides["token"] = true
	var copy := Card.new(game._uid(), original.card_id, context.controller)
	game._summon(context.controller, copy, false, 0, overrides, false, -1, false, suppress_on_enter)
	if copy.zone != "board":
		return # something moved it away while it entered (a reaction killed it): there is nothing left to copy onto
	copy.copy_modifiers_from(original)
	game._check_state() # the copied damage may already be lethal, and scaling is recomputed from the copied state
