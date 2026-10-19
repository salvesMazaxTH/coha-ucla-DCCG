class_name SourceTarget
extends TargetSelector
## Targets taken from the trigger itself: self (the unit whose effect it is, on the board), self_card
## (the same card wherever it is), event_source (the card that caused a listening event), opposed_unit
## (the other unit in a combat trigger), attack_target (what an Ao Atacar attack is aimed at: the challenged
## unit, or the enemy Leader when no unit was challenged) and none (the effect runs once with target 0).

const NAMES := ["self", "self_card", "event_source", "opposed_unit", "attack_target", "none"]

func resolve(context: EffectContext, _effect: Effect) -> Array:
	match name:
		"self":
			if context.game.find_unit(context.self_uid) != null:
				return [context.self_uid]
		"self_card": # the card itself in any zone (deck, hand, graveyard...), for listeners that work off the board
			if context.game.find_card(context.self_uid) != null:
				return [context.self_uid]
		"event_source": # the card that caused a listening event, e.g. the Plant that just entered
			if context.event != null and context.event.source != null and context.game.find_unit(context.event.source.uid) != null:
				return [context.event.source.uid]
		"opposed_unit":
			if context.game.find_unit(context.other_uid) != null:
				return [context.other_uid]
		"attack_target": # an on_attack trigger carries the challenged unit, or 0 when the Leader is the target
			if context.other_uid == 0:
				return [GameState.LEADER_UID[context.opponent()]]
			if context.game.find_unit(context.other_uid) != null:
				return [context.other_uid]
		"none":
			return [0]
	return []
