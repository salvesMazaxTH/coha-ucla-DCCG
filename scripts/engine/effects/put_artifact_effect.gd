class_name PutArtifactEffect
extends Effect
## "put_artifact": {"card": <id>, "unique": true} puts a fresh free-standing artifact on the controller's
## side of the field, taking a slot, without playing it from the hand (the Leader ability "Erguer o
## Baluarte" uses it, since "summon" only creates units).
## "unique": the effect does nothing while the controller already has a copy of that artifact on the field.
## Nothing happens either when the field has no free slot.

var card_id := ""
var unique := false

func _read_parameters(data: Dictionary) -> void:
	card_id = String(data.get("card", ""))
	unique = bool(data.get("unique", false))

func apply(context: EffectContext, _target_uid: int) -> void:
	var game := context.game
	if not can_put(game, context.controller):
		return
	game._place_relic(context.controller, Card.new(game._uid(), card_id, context.controller))

## True when the artifact could enter the field of player p right now. Also asked by the Leader ability,
## so its cost is never paid for an effect that would do nothing.
func can_put(game: GameState, p: int) -> bool:
	if not game.has_free_slot(p):
		return false
	if unique:
		for relic: Card in game.players[p]["relics"]:
			if relic.card_id == card_id:
				return false
	return true
