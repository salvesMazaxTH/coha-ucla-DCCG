class_name EmptyMomentumStoreEffect
extends Effect
## "empty_momentum_store": the artifact that owns this effect loses all the Momentum it had stored
## (a card with "momentum_store": N, Bateria de Segunda Mão).

func apply(context: EffectContext, _target_uid: int) -> void:
	var artifact: Card = context.game.find_relic(context.self_uid)
	if artifact == null or artifact.stored_momentum <= 0:
		return
	artifact.stored_momentum = 0
	context.game._emit({"type": "momentum_stored", "player": artifact.owner, "uid": artifact.uid, "stored": 0})
