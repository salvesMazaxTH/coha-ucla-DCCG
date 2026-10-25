class_name PutArtifactEffect
extends Effect
## "put_artifact": {"card": <id>, "unique": true} puts a fresh free-standing artifact on the controller's
## side of the field, taking a slot, without playing it from the hand (the Leader ability "Erguer o
## Baluarte" uses it, since "summon" only creates units).
## "unique": the effect does nothing while the controller already has a copy of that artifact on the field.
## Nothing happens either when the field has no free slot.
## "lockout_turns": N: nothing happens (and the Leader ability is unavailable) while a copy of that artifact left the
## controller's field N or fewer turns ago. The turn counter ticks on every player's turn, so N = 2 means a fall
## in the controller's own turn X, in the opponent's X+1 or in X+2 blocks the controller's turn X+2, and a fall in X+2 also blocks X+4.
## "charges_left": N: an artifact with "charges" enters with only N uses still available (the rest count as already
## spent), e.g. the Ampola Curativa that the Leva-Frascos Apressado leaves behind has 1 of its 2 uses. Without it, the
## artifact enters with all its uses.

var card_id := ""
var unique := false
var lockout_turns := 0
var charges_left := -1 ## -1 = all the uses

func _read_parameters(data: Dictionary) -> void:
	card_id = String(data.get("card", ""))
	unique = bool(data.get("unique", false))
	lockout_turns = int(data.get("lockout_turns", 0))
	charges_left = int(data.get("charges_left", -1))

func apply(context: EffectContext, _target_uid: int) -> void:
	var game := context.game
	if not can_put(game, context.controller):
		return
	var artifact := Card.new(game._uid(), card_id, context.controller)
	if charges_left >= 0:
		var total_charges := int(artifact.data().get("charges", 0))
		artifact.charges_used = maxi(total_charges - charges_left, 0)
	game._place_relic(context.controller, artifact)

## True when the artifact could enter the field of player p right now. Also asked by the Leader ability,
## so its cost is never paid for an effect that would do nothing.
func can_put(game: GameState, p: int) -> bool:
	if not game.has_free_slot(p):
		return false
	if lockout_turns > 0 and game.relic_fell_within(p, card_id, lockout_turns):
		return false
	if unique:
		for relic: Card in game.players[p]["relics"]:
			if relic.card_id == card_id:
				return false
	return true
