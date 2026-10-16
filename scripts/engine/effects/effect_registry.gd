class_name EffectRegistry
extends RefCounted
## Maps each "action" of cards.json to its Effect class.
## A new action: write its class in this folder and add one line here.

static var ACTIONS: Dictionary = {
	"damage": DamageEffect,
	"heal_leader": HealEffect,
	"leader_max_up": HealEffect,
	"heal_full": HealEffect,
	"heal_unit": HealEffect,
	"draw": DrawEffect,
	"draw_discounted": DrawEffect,
	"tide_mark": TideMarkEffect,
	"search_deck": DeckEffect,
	"look_top": DeckEffect,
	"grave_retrieve": DeckEffect,
	"freeze": FreezeEffect,
	"exhaust": ExhaustEffect,
	"freeze_slots": FreezeSlotsEffect,
	"add_card": AddCardEffect,
	"snowball": SnowballEffect,
	"snowball_level": SnowballLevelEffect,
	"transform_self": TransformEffect,
	"discard_hand_pick": DeckEffect,
	"summon_hand_pick": DeckEffect,
	"fight": FightEffect,
	"summon": SummonEffect,
	"mill": MillEffect,
	"fatigue_burn": FatigueBurnEffect,
	"mill_pick": MillEffect,
	"revive": ReviveEffect,
	"revive_self": ReviveEffect,
	"revive_pick": ReviveEffect,
	"destroy": RemoveEffect,
	"destroy_artifact": RemoveEffect,
	"banish": RemoveEffect,
	"sacrifice": SacrificeEffect,
	"fuse": FuseEffect,
	"gain_momentum": GainMomentumEffect,
	"buff": BuffEffect,
	"counter": CounterEffect,
	"modify_cost": ModifyCostEffect,
	"cost_reduction": StaticEffect,
	"scale": StaticEffect,
}

## Actions with no target: continuous abilities, never run by a trigger.
const STATIC_ACTIONS := ["cost_reduction", "scale"]

static func is_known(action: String) -> bool:
	return ACTIONS.has(action)

## The Effect object for one JSON entry (an unknown action becomes an effect that does nothing).
static func parse(data: Dictionary) -> Effect:
	var effect_class: Variant = ACTIONS.get(String(data.get("action", "")), Effect)
	var effect: Effect = effect_class.new()
	effect.setup(data)
	return effect

## Effect objects for a JSON "effects" list, in the same order.
static func parse_list(entries: Array) -> Array:
	var effects: Array = []
	for data in entries:
		if data is Dictionary:
			effects.append(parse(data))
	return effects
