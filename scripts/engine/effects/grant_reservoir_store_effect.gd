class_name GrantReservoirStoreEffect
extends Effect
## "grant_reservoir_store": the controller may deposit `limit` (default 1) cards from their hand into their Reservoir
## during this turn. Two of them in the same turn add up. Ends with the turn (Eletroad).

var limit := 1

func _read_parameters(data: Dictionary) -> void:
	limit = int(data.get("limit", 1))

func apply(context: EffectContext, _target_uid: int) -> void:
	context.game.grant_reservoir_stores(context.controller, limit)
