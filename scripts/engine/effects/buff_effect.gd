class_name BuffEffect
extends Effect
## "buff": +atk/+hp and keywords on the target unit ("temp": true = attack and keywords only
## until end of turn). "armor": N adds Armadura permanently (stacks with what it already has);
## "armor_temp": N is the same until its owner's next turn starts.
## "per": "momentum_left" multiplies atk/hp by the Momentum the controller still has
## (at least `min`, at most `max`).
## "cap_atk": this effect can give one unit at most that much attack in total (e.g. Layla).

var attack := 0
var health := 0
var armor := 0
var temporary_armor := 0
var temporary := false
var keywords: Array = []
var per := ""
var multiplier_min := 0
var multiplier_max := 99
var has_attack_cap := false
var attack_cap := 0

func _read_parameters(data: Dictionary) -> void:
	attack = int(data.get("atk", 0))
	health = int(data.get("hp", 0))
	armor = int(data.get("armor", 0))
	temporary_armor = int(data.get("armor_temp", 0))
	temporary = bool(data.get("temp", false))
	keywords = data.get("keywords", [])
	per = String(data.get("per", ""))
	multiplier_min = int(data.get("min", 0))
	multiplier_max = int(data.get("max", 99))
	has_attack_cap = data.has("cap_atk")
	attack_cap = int(data.get("cap_atk", 0))

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var unit := game.find_unit(target_uid)
	if unit == null:
		return
	var multiplier := 1
	if per == "momentum_left":
		multiplier = clampi(int(game.players[context.controller]["momentum"]), multiplier_min, multiplier_max)
	var attack_gain: int = attack * multiplier
	var health_gain: int = health * multiplier
	if has_attack_cap:
		attack_gain = mini(attack_gain, attack_cap - unit.cap_atk_gain)
		if attack_gain <= 0:
			return
		unit.cap_atk_gain += attack_gain
	if temporary:
		unit.temp_atk += attack_gain
	else:
		unit.atk += attack_gain
		unit.hp += health_gain
	unit.temp_armor += temporary_armor # lasts until the unit's owner starts their next turn
	unit.armor += armor # Armadura stacks: giving Armadura X to a unit that has Y leaves X + Y
	for keyword in keywords:
		if keyword == "escudo":
			unit.shield = true
		elif keyword == "escudo_feitico":
			unit.spell_shield = true
		elif not unit.keywords.has(keyword):
			unit.keywords.append(keyword)
			if temporary:
				unit.temp_keywords.append(keyword)
	var buff_event := {"type": "buff", "uid": target_uid, "atk": attack_gain, "hp": health_gain, "keywords": raw.get("keywords", [])}
	if armor + temporary_armor > 0:
		buff_event["armor"] = armor + temporary_armor
	game._emit(buff_event)
