class_name FuseEffect
extends Effect
## "fuse": every allied unit with card id `card` leaves the board (it does not die, so no
## Ao Morrer and no "aliado morre") and one `into` unit takes the slot of the first of them.
## The new unit gets +`atk_per`/+`hp_per`/+`armor_per` for each unit fused into it.
## Needs at least `min` of them (can_activate checks this before it can be used).

var fused_card_id := ""
var into_card_id := ""
var minimum_count := 2
var attack_per_unit := 0
var health_per_unit := 0
var armor_per_unit := 0

func _read_parameters(data: Dictionary) -> void:
	fused_card_id = String(data.get("card", ""))
	into_card_id = String(data.get("into", ""))
	minimum_count = int(data.get("min", 2))
	attack_per_unit = int(data.get("atk_per", 0))
	health_per_unit = int(data.get("hp_per", 0))
	armor_per_unit = int(data.get("armor_per", 0))

func apply(context: EffectContext, _target_uid: int) -> void:
	var game := context.game
	var board: Array = game.players[context.controller]["board"]
	var parts: Array = board.filter(func(c: Card): return c.card_id == fused_card_id and c.hp_left() > 0)
	if parts.size() < minimum_count:
		return
	var slot := board.find(parts[0])
	var fused_uids: Array = []
	for part in parts:
		board.erase(part)
		game._release_equipment(part)
		game._move(part, "") # gone without reaching the graveyard, like a token that died
		fused_uids.append(part.uid)
	var count := parts.size()
	var base := CardDB.card(into_card_id)
	var overrides := {
		"atk": int(base["atk"]) + attack_per_unit * count,
		"hp": int(base["hp"]) + health_per_unit * count,
		"armor": int(base.get("armor", 0)) + armor_per_unit * count,
	}
	game._emit({"type": "fuse", "player": context.controller, "uids": fused_uids, "card_id": into_card_id, "count": count})
	game._summon(context.controller, Card.new(game._uid(), into_card_id, context.controller), false, 0, overrides, false, slot)

## How many units this fusion would take right now (0 when below the minimum).
func available_parts(game: GameState, controller: int) -> int:
	var count: int = game.players[controller]["board"].filter(func(c: Card): return c.card_id == fused_card_id).size()
	return count if count >= minimum_count else 0
