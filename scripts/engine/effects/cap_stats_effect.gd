class_name CapStatsEffect
extends Effect
## "cap_stats": puts a ceiling on the target's Ataque ("atk") and Vida ("hp"). A unit above the ceiling is
## brought down to it for good; a unit already at or below it is left alone (it never grows). It is not a
## lock: later buffs can raise the unit again. Temporary bonuses go first, then the permanent value.
## Damage never kills the unit through this effect: the Vida it has left can only shrink down to the ceiling.

var attack_ceiling := 99
var health_ceiling := 99

func _read_parameters(data: Dictionary) -> void:
	attack_ceiling = int(data.get("atk", 99))
	health_ceiling = int(data.get("hp", 99))

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var unit := game.find_unit(target_uid)
	if unit == null:
		return
	var attack_lost := _cap_attack(unit)
	var health_lost := _cap_health(unit)
	if attack_lost > 0 or health_lost > 0:
		game._emit({"type": "shrink", "uid": target_uid, "atk": attack_lost, "hp": health_lost})

## Lowers the unit's Ataque to the ceiling; returns how much was taken away.
func _cap_attack(unit: Card) -> int:
	var before := unit.atk_total()
	var excess := before - attack_ceiling
	if excess <= 0:
		return 0
	var from_temporary := mini(excess, unit.temp_atk + unit.temp_atk_until_next_turn)
	var take_from_until_next_turn := mini(from_temporary, unit.temp_atk_until_next_turn)
	unit.temp_atk_until_next_turn -= take_from_until_next_turn
	unit.temp_atk -= from_temporary - take_from_until_next_turn
	# whatever is left comes off the permanent Ataque (the aura bonus is not ours to remove)
	unit.atk = maxi(0, unit.atk - (excess - from_temporary))
	return before - unit.atk_total()

## Lowers the unit's Vida to the ceiling; the damage it carries is trimmed so it keeps the same life
## (or the ceiling, if lower) and never dies from this.
func _cap_health(unit: Card) -> int:
	var life_before := unit.hp_left()
	var maximum_before := unit.hp + unit.bonus_hp + unit.temp_hp + unit.temp_hp_until_next_turn
	var excess := maximum_before - health_ceiling
	if excess <= 0:
		return 0
	var from_temporary := mini(excess, unit.temp_hp + unit.temp_hp_until_next_turn)
	var take_from_until_next_turn := mini(from_temporary, unit.temp_hp_until_next_turn)
	unit.temp_hp_until_next_turn -= take_from_until_next_turn
	unit.temp_hp -= from_temporary - take_from_until_next_turn
	unit.hp = maxi(1, unit.hp - (excess - from_temporary))
	var maximum_after := unit.hp + unit.bonus_hp + unit.temp_hp + unit.temp_hp_until_next_turn
	unit.damage = maxi(0, maximum_after - mini(life_before, maximum_after))
	return maximum_before - maximum_after
