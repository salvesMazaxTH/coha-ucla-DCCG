class_name PendingTrigger
extends RefCounted
## A trigger that already happened but has not resolved yet. The TriggerBus queues these while an
## action is still running; GameState resolves them one at a time once the action is over and the
## board is stable (active player's triggers first).

var source: Card ## the card the triggered effects belong to (null for a Leader passive)
var effects: Array ## Effect objects to run
var context: EffectContext
## Name shown to the UI through the "trigger" event ("on_death", or a listen effect's own trigger...); "" = no announcement.
var announce_as := ""

func _init(source_card: Card, effect_list: Array, effect_context: EffectContext, announcement := "") -> void:
	source = source_card
	effects = effect_list
	context = effect_context
	announce_as = announcement

func controller() -> int:
	return context.controller

func resolve(game: GameState) -> void:
	var announced := source != null and announce_as != "" and game._announce(source, effects, announce_as)
	if not announced:
		# nobody to show as the source (a Leader passive): the UI must not keep crediting the previous trigger's card
		game._emit({"type": "trigger_end"})
	game._run_effects(context, effects)
