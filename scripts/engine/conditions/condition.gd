class_name Condition
extends RefCounted
## Base class of an effect's "if" (cards.json): the effect only runs when check() is true.
## ConditionRegistry builds the right subclass from the JSON value.

## True when the effect may run in this context.
func check(_context: EffectContext) -> bool:
	return true
