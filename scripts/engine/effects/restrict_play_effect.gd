class_name RestrictPlayEffect
extends Effect
## "restrict_play": limits which cards a player may play for a while (see PlayRestriction for the
## "restriction" format: mode, match by essence / rarity / card_type / cost, duration in turns).
## "who": "self" (default) restricts the controller, "opponent" restricts the other player.
## It covers every way of playing a card: hand, Réquiem from the graveyard, Súbito and the Encarnação.

var restriction: Dictionary = {}
var restricts_opponent := false

func _read_parameters(data: Dictionary) -> void:
	restriction = data.get("restriction", {})
	restricts_opponent = String(data.get("who", "self")) == "opponent"

func apply(context: EffectContext, _target_uid: int) -> void:
	var restricted_player := 1 - context.controller if restricts_opponent else context.controller
	context.game.add_play_restriction(restricted_player, restriction)
