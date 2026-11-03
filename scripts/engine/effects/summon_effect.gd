class_name SummonEffect
extends Effect
## "summon": {"card": <id|"self">, "overrides": {atk, hp, keywords, effects, text...}}.
## "self" is the unit whose Ao Morrer is resolving. Overrides stick to the new instance.
## "count" (default 1) summons that many copies, stopping when the board is full (Inácio Pá-de-Cova).
## "side": "enemy" summons them for the opponent instead of the controller.

var card_id := "self"
var overrides: Dictionary = {}
var summon_count := 1
var summons_for_enemy := false

func _read_parameters(data: Dictionary) -> void:
	card_id = String(data.get("card", "self"))
	overrides = data.get("overrides", {})
	summon_count = maxi(1, int(data.get("count", 1)))
	summons_for_enemy = String(data.get("side", "own")) == "enemy"

func apply(context: EffectContext, _target_uid: int) -> void:
	var game := context.game
	var summoned_id := card_id
	if summoned_id == "self":
		if context.dying_card == null:
			return
		summoned_id = context.dying_card.card_id
	# "side": "enemy" puts the copies under the opponent's control (Cortejo de Cinzas); their board limit applies
	var receiving_player: int = 1 - context.controller if summons_for_enemy else context.controller
	for _copy in summon_count:
		if not game.has_free_slot(receiving_player):
			return
		game._summon(receiving_player, Card.new(game._uid(), summoned_id, receiving_player), false, 0, overrides)
