class_name TriggerBus
extends RefCounted
## Delivers GameEvents to the cards that react to them, in one place. The reactions are not run
## here: each one becomes a PendingTrigger in GameState's queue, resolved once the action is over.
##
## Two kinds of reaction:
##   - own trigger: {"trigger": "on_attack"} runs for the unit the event happened to (event.source);
##   - listening:   {"listen": "leader_damaged", "scope": "enemy", "zones": "any", "when": {...}}
##     runs for every card of the match that is in one of its zones and whose scope matches.
##
## "scope" is relative to the listening card: self (the event is about this card), ally (about
## its owner), enemy (about the opponent) or any (default). "zones" is a list among board, relics, hand,
## deck, graveyard, banished, or "any" (default: ["board"]).

const ZONES := ["board", "relics", "hand", "deck", "graveyard", "banished"]

var game: GameState

func _init(game_state: GameState) -> void:
	game = game_state

func emit(event: GameEvent) -> void:
	if game._chain_stopped():
		return
	if event.source != null and event.trigger.begins_with("on_"):
		_fire_own_effects(event)
	if event.trigger in GameEvent.LISTENABLE:
		_broadcast(event)

## The unit's own effects for this trigger (once_per_turn / not_in_combat respected).
func _fire_own_effects(event: GameEvent) -> void:
	var card := event.source
	var effects: Array = []
	var all_effects: Array = card.data()["effects"]
	for i in all_effects.size():
		var e: Dictionary = all_effects[i]
		if e.get("trigger", "") == event.trigger and e.get("not_token", false) and event.data.get("dying_is_token", false):
			continue # the ally that died was a ficha
		if e.get("trigger", "") == event.trigger and e.has("dying_card") and e["dying_card"] != event.data.get("dying_card_id", ""):
			continue # an Aliado Morre effect that only listens to one card dying (Luto: Myrra)
		if e.get("trigger", "") == event.trigger and game._combat_damage and e.get("not_in_combat", false):
			continue
		if e.get("trigger", "") == event.trigger and e.get("only_from_spell", false) and not event.data.get("from_spell", false):
			continue # an Ao Sofrer Dano effect that only reacts to damage dealt by a spell (Tyren)
		if e.get("trigger", "") == event.trigger and e.get("hit_at_least_armor", false) and not event.data.get("hit_reached_armor", true):
			continue # an Ao Sofrer Dano effect that a hit weaker than the unit's Armadura can't trigger (Tharox)
		if e.get("trigger", "") == event.trigger and e.get("own_turn_only", false) and game.active != card.owner:
			continue # an "own turn only" effect during the opponent's turn
		if e.get("trigger", "") == event.trigger and e.get("once_per_turn", false):
			if card.used_turn.get(i, -1) == game.turn:
				continue # "once per turn" effect already used this turn
			card.used_turn[i] = game.turn
		effects.append(e)
	var context := EffectContext.new(game, card.owner, event.trigger)
	context.self_uid = card.uid
	context.other_uid = event.other_uid
	context.event = event
	game.queue_trigger(PendingTrigger.new(card, effects, context, event.trigger))

## Offers the event to every card that listens to it: active player first, then the other.
func _broadcast(event: GameEvent) -> void:
	var key := Effect.LISTEN_PREFIX + event.trigger
	for player_index in [game.active, game.opponent(game.active)]:
		for zone in ZONES:
			for card: Card in game.players[player_index][zone].duplicate():
				for effect: Effect in CardDB.def(card.card_id).listeners():
					if effect.trigger == key and effect.listens_in(zone):
						_offer(card, effect, event)

func _offer(card: Card, effect: Effect, event: GameEvent) -> void:
	if not _scope_matches(effect.scope, card, event) or not _when_matches(effect.when, event):
		return
	if effect.own_turn_only and game.active != card.owner:
		return # only works during its owner's turn
	if game._chain_stopped():
		return
	var context := EffectContext.new(game, card.owner, effect.trigger)
	context.self_uid = card.uid
	context.other_uid = event.other_uid
	context.event = event
	# intervening-if: checked now, and again by _run_effects right before the effect applies
	if effect.condition != null and not effect.condition.check(context):
		return
	if effect.once_per_turn:
		var index := CardDB.def(card.card_id).effects().find(effect)
		if card.used_turn.get(index, -1) == game.turn:
			return
		card.used_turn[index] = game.turn
	game.queue_trigger(PendingTrigger.new(card, [effect], context))

func _scope_matches(scope: String, card: Card, event: GameEvent) -> bool:
	match scope:
		"self": return event.source == card
		"ally": return event.player == card.owner
		"enemy": return event.player != card.owner
	return true

## Every key of "when" must equal the same fact in the event ("to": "graveyard"...).
func _when_matches(when: Dictionary, event: GameEvent) -> bool:
	for key in when:
		if event.data.get(key) != when[key]:
			return false
	return true
