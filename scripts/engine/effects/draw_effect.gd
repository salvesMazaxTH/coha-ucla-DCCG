class_name DrawEffect
extends Effect
## Drawing family, told apart by `action`:
## "draw": draws `amount` cards. Targeting the enemy Leader makes the opponent draw instead.
## "draw_discounted": draws a card; if its base cost is at least `min_base_cost`, that copy
## costs `discount` less.

var amount := 0
var min_base_cost := 0
var discount := 1

func _read_parameters(data: Dictionary) -> void:
	amount = int(data.get("amount", 0))
	min_base_cost = int(data.get("min_base_cost", 0))
	discount = int(data.get("discount", 1))

func apply(context: EffectContext, target_uid: int) -> void:
	if action == "draw_discounted":
		context.last_drawn_card = context.game._draw_discounted(context.controller, min_base_cost, discount)
		return
	var enemy := context.opponent()
	var drawer := enemy if target_uid == GameState.LEADER_UID[enemy] else context.controller
	context.game._draw(drawer, amount)
