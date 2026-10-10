class_name GroupCondition
extends Condition
## Combines other conditions: {"all": [...]}, {"any": [...]} or {"not": condition}.

var mode := "all" ## "all", "any" or "not"
var parts: Array = [] ## Condition objects ("not" has exactly one)

func _init(group_mode: String, conditions: Array) -> void:
	mode = group_mode
	parts = conditions

func check(context: EffectContext) -> bool:
	match mode:
		"all":
			for part: Condition in parts:
				if not part.check(context): return false
			return true
		"any":
			for part: Condition in parts:
				if part.check(context): return true
			return false
		"not":
			return not parts[0].check(context)
	return true
