class_name TargetRegistry
extends RefCounted
## Maps each "target" name of cards.json to its TargetSelector family.
## A new target: add its name to a family's NAMES (or write a new family and list it here).

static var _selectors: Dictionary = {} ## name -> TargetSelector (selectors hold no state, so one each is shared)

static func is_known(target_name: String) -> bool:
	return _family_of(target_name) != null

## True when the player picks this target while playing the card.
static func needs_choice(target_name: String) -> bool:
	return make(target_name).needs_choice()

## The selector for a target name; an unknown or empty name gets one that hits nothing.
static func make(target_name: String) -> TargetSelector:
	if not _selectors.has(target_name):
		var family: Variant = _family_of(target_name)
		_selectors[target_name] = family.new(target_name) if family != null else TargetSelector.new(target_name)
	return _selectors[target_name]

static func _family_of(target_name: String) -> Variant:
	if target_name in ChosenTarget.NAMES: return ChosenTarget
	if target_name in GroupTarget.NAMES: return GroupTarget
	if target_name in LeaderTarget.NAMES: return LeaderTarget
	if target_name in RandomTarget.NAMES: return RandomTarget
	if target_name in SourceTarget.NAMES: return SourceTarget
	return null
