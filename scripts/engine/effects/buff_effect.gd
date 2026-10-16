class_name BuffEffect
extends Effect
## "buff": +atk/+hp and keywords on the target unit ("temp": true = attack, hp and keywords
## only until end of turn). "armor": N adds Armadura permanently (stacks with what it already has);
## "armor_temp": N is the same until its owner's next turn starts. "atk_temp": N does that for Ataque.
## "armor_min": N raises the unit's Armadura to N when it is lower (nothing happens when it already has N or more).
## "spell_shield_temp": true gives Escudo de Feitiço only until its owner's next turn starts (a unit that already
## has a permanent Escudo de Feitiço keeps it as it is).
## "per": "momentum_left" multiplies atk/hp by the Momentum the controller still has
## (at least `min`, at most `max`).
## "cap_atk": this effect can give one unit at most that much attack in total (e.g. Layla).
## "critico_max": true  a unit that has any Crítico at all goes up to Crítico 4 until the end of the turn (units without Crítico are untouched).
## "bonus_if_card": {"card": id, "atk": N, "hp": N}: when the target is that card, it also gains this permanently (Myrra -> Vael).

var attack := 0
var health := 0
var armor := 0
var temporary_armor := 0
var minimum_armor := 0
var temporary_spell_shield := false
var temporary_attack_until_next_turn := 0
var temporary := false
var keywords: Array = []
var per := ""
var multiplier_min := 0
var multiplier_max := 99
var has_attack_cap := false
var attack_cap := 0
var minimum_rapidez := 0
var critico_to_max := false
var bonus_card := ""
var bonus_attack := 0
var bonus_health := 0
var temporary_critico := 0 ## "critico_temp": N extra Crítico levels until the end of the turn (the total never passes 4)

func _read_parameters(data: Dictionary) -> void:
	attack = int(data.get("atk", 0))
	health = int(data.get("hp", 0))
	armor = int(data.get("armor", 0))
	temporary_armor = int(data.get("armor_temp", 0))
	minimum_armor = int(data.get("armor_min", 0))
	temporary_spell_shield = bool(data.get("spell_shield_temp", false))
	temporary_attack_until_next_turn = int(data.get("atk_temp", 0))
	temporary = bool(data.get("temp", false))
	keywords = data.get("keywords", [])
	per = String(data.get("per", ""))
	multiplier_min = int(data.get("min", 0))
	multiplier_max = int(data.get("max", 99))
	has_attack_cap = data.has("cap_atk")
	attack_cap = int(data.get("cap_atk", 0))
	minimum_rapidez = int(data.get("rapidez_min", 0))
	critico_to_max = bool(data.get("critico_max", false))
	var bonus: Dictionary = data.get("bonus_if_card", {})
	bonus_card = String(bonus.get("card", ""))
	bonus_attack = int(bonus.get("atk", 0))
	bonus_health = int(bonus.get("hp", 0))
	temporary_critico = int(data.get("critico_temp", 0))

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var unit := game.find_unit(target_uid)
	if unit == null:
		return
	if critico_to_max:
		if unit.critico_total() < 1:
			return
		var missing_levels: int = 4 - unit.critico_total()
		unit.temp_critico += missing_levels
		game._emit({"type": "buff", "uid": target_uid, "atk": 0, "hp": 0, "keywords": [], "critico": missing_levels})
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
		unit.temp_hp += health_gain
	else:
		unit.atk += attack_gain
		unit.hp += health_gain
	if bonus_card != "" and unit.card_id == bonus_card:
		unit.atk += bonus_attack
		unit.hp += bonus_health
		attack_gain += bonus_attack
		health_gain += bonus_health
	unit.temp_atk_until_next_turn += temporary_attack_until_next_turn # ends when the unit's owner starts their next turn
	attack_gain += temporary_attack_until_next_turn
	unit.temp_armor += temporary_armor # lasts until the unit's owner starts their next turn
	unit.armor += armor # Armadura stacks: giving Armadura X to a unit that has Y leaves X + Y
	var armor_raised_to := 0
	if minimum_armor > unit.armor:
		unit.armor = minimum_armor
		armor_raised_to = minimum_armor
	if temporary_spell_shield and not unit.spell_shield:
		unit.spell_shield = true
		unit.spell_shield_until_next_turn = true
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
	if minimum_rapidez > unit.rapidez:
		unit.rapidez = minimum_rapidez
		buff_event["rapidez"] = minimum_rapidez
	if armor + temporary_armor > 0:
		buff_event["armor"] = armor + temporary_armor
	elif armor_raised_to > 0:
		buff_event["armor"] = armor_raised_to
	if temporary_critico > 0:
		unit.temp_critico = mini(4, unit.temp_critico + temporary_critico)
		buff_event["critico"] = temporary_critico
	game._emit(buff_event)
