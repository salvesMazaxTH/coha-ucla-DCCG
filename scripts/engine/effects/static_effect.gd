class_name StaticEffect
extends Effect
## "cost_reduction" and "scale": continuous abilities that never run from a trigger.
## GameState.cost_of reads cost_reduction and _refresh_scaling reads scale, straight from `raw`.

func is_static() -> bool:
	return action == "cost_reduction" or super()
