extends Effect
## "lasting_growth": the card whose Condicional heard the event gets +atk/+hp that it keeps in every zone
## (hand, deck, graveyard, field, Santuário). The growth belongs to the card, not to one copy: every copy its
## owner has, and every copy that shows up later, carries it (see GameState.add_lasting_growth).
## A move of a copy of this same card never makes it grow (it does not feed on itself).

var attack_gain := 0
var health_gain := 0

func _read_parameters(data: Dictionary) -> void:
	attack_gain = int(data.get("atk", 0))
	health_gain = int(data.get("hp", 0))

func apply(context: EffectContext, _target_uid: int) -> void:
	var card_id := context.listening_card_id
	if card_id == "":
		return
	if context.event != null and context.event.source != null and context.event.source.card_id == card_id:
		return
	context.game.add_lasting_growth(context.controller, card_id, attack_gain, health_gain)
