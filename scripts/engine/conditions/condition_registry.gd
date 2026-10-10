class_name ConditionRegistry
extends RefCounted
## Turns the "if" of cards.json into a Condition object.
## "if" is a flag name ("momentum_left") or an object: {"all": [...]}, {"any": [...]},
## {"not": ...} or {"compare": {...}}. These nest freely.

## The Condition for an "if" value, or null when there is none (the effect always runs).
static func parse(value: Variant) -> Condition:
	if value == null or (value is String and value == ""):
		return null
	if value is String:
		return FlagCondition.new(value)
	if value is Dictionary:
		if value.has("all"): return GroupCondition.new("all", _parse_each(value["all"]))
		if value.has("any"): return GroupCondition.new("any", _parse_each(value["any"]))
		if value.has("not"): return GroupCondition.new("not", [_parse_or_true(value["not"])])
		if value.has("compare"): return CompareCondition.new(value["compare"])
		if value.has("crossed_below"): return CrossedCondition.new(true, value["crossed_below"])
		if value.has("crossed_above"): return CrossedCondition.new(false, value["crossed_above"])
	return Condition.new()

## The problem with an "if" value, or "" when it is valid (checked when the catalog loads).
static func error_of(value: Variant) -> String:
	if value is String:
		return "" if value in FlagCondition.NAMES else "if desconhecido \"%s\"" % value
	if value is Dictionary and value.size() == 1:
		var key: String = value.keys()[0]
		match key:
			"all", "any":
				if not value[key] is Array:
					return "if.%s precisa ser uma lista" % key
				for part in value[key]:
					var problem := error_of(part)
					if problem != "": return problem
				return ""
			"not":
				return error_of(value["not"])
			"compare":
				return CompareCondition.error_of(value["compare"])
			"crossed_below", "crossed_above":
				return CrossedCondition.error_of(value[key])
	return "if desconhecido \"%s\"" % str(value)

static func _parse_each(values: Variant) -> Array:
	var conditions: Array = []
	if values is Array:
		for value in values:
			conditions.append(_parse_or_true(value))
	return conditions

static func _parse_or_true(value: Variant) -> Condition:
	var condition := parse(value)
	return condition if condition != null else Condition.new()
