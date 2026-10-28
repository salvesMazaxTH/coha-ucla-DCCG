class_name LoseDurabilityEffect
extends Effect
## "lose_durability": {"amount": N} the target artifact loses N points of Durability and breaks when none is left.
## The target is a free-standing artifact, or a unit: then it is the equipment that unit wears that wears down
## (a unit without equipment is left alone). Equipment that only gives stats has 1 Durability, so even
## "loses 1 Durability" breaks it, and the unit loses the bonus.

var amount := 1

func _read_parameters(data: Dictionary) -> void:
	amount = int(data.get("amount", 1))

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var worn_down: Card = game.find_relic(target_uid)
	if worn_down == null:
		var carrier := game.find_unit(target_uid)
		if carrier != null:
			for worn in carrier.equipped_cards: # the oldest one that can wear down
				if worn.durability_left() >= 0:
					worn_down = worn
					break
	if worn_down != null:
		game.lose_durability(worn_down, amount)
