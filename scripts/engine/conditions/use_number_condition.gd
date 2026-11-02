class_name UseNumberCondition
extends Condition
## True when the Condicional being resolved is use number N of the turn for a card with
## "conditional_uses_per_turn" (the 1st shot, the 2nd shot...):
## {"conditional_use": 2}  -> only the 2nd use of the turn
## The number is read from the context, where the TriggerBus wrote it when the event was offered
## (the use counter moves on afterwards, and the condition is checked again right before the effect applies).

var number := 1

func _init(use_number: int) -> void:
	number = use_number

func check(context: EffectContext) -> bool:
	return context.conditional_use == number

static func error_of(value: Variant) -> String:
	if not (value is int or value is float) or int(value) < 1:
		return "conditional_use precisa ser um número a partir de 1"
	return ""
