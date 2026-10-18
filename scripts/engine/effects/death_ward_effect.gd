class_name DeathWardEffect
extends Effect
## "arm_death_ward": arms the free-standing artifact represented by the current unit ability.
## The GameState consumes this flag only when one of the controller's units actually dies; banish
## bypasses that death path and therefore never consumes it.

func apply(context: EffectContext, _target_uid: int) -> void:
	var relic := context.game.find_relic(context.self_uid)
	if relic == null or relic.owner != context.controller:
		return
	relic.death_ward_armed = true
	context.game._emit({"type": "death_ward_armed", "player": relic.owner, "uid": relic.uid, "card_id": relic.card_id})
