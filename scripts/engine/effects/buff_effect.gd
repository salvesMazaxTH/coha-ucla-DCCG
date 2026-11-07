class_name BuffEffect
extends Effect
## "buff": +atk/+hp and keywords on the target unit ("temp": true = attack, hp and keywords
## only until end of turn). "armor": N adds Armadura permanently (stacks with what it already has);
## "armor_temp": N is the same until its owner's next turn starts. With "temp": true "armor" also lasts only until end of turn. "atk_temp": N does that for Ataque.
## "armor_min": N raises the unit's Armadura to N when it is lower (nothing happens when it already has N or more).
## "magic_shield_temp": true gives Escudo Mágico only until its owner's next turn starts (Tyren; a unit that already
## has a permanent Escudo Mágico keeps it as it is).
## "supreme_shield_until": "next_turn" gives Escudo Supremo until its owner's next turn starts. The "escudo_supremo" keyword
## gives it for good, or only until the end of the turn with "temp": true. A Supremo that is already there is never made shorter.
## "per": "momentum_left" multiplies atk/hp by the Momentum the controller still has
## (at least `min`, at most `max`). "per_offset": N is added to that multiplier afterwards (Voltexz: +X/+X, X = Momentum left + 1).
## "per": "own_artifacts" multiplies them by the artifacts the controller has in play
## (Otávio Rebite-Quente: +1 Ataque for each one). "per": "sacrificed_atk" multiplies them by the Ataque of the unit a
## "sacrifice" just killed (Esther: she gains +X/+X, X = that Ataque).
## "cap_atk": this effect can give one unit at most that much attack in total (e.g. Layla).
## "critico_max": true  a unit that has any Crítico at all goes up to Crítico 4 until the end of the turn (units without Crítico are untouched).
## "hp_temp_until_next_turn": N gives temporary Vida until the unit's owner's next turn starts.
## "keywords_this_turn": [...] gives these keywords only until the end of the turn while atk/hp stay permanent
## (Mali: +1 Ataque permanent and, only this turn, Escudo Mágico, from one effect so both share one count).
## "keywords_until_next_turn": [...] gives these keywords until the unit's owner's next turn starts (a keyword the unit already
## has stays as it is) - Cortina de Fumaça Barata gives Furtividade this way.
## "keywords_until_owner_turn_end": [...] gives these keywords until the END of the turn its owner plays next (so they last through
## that whole turn, including when the unit is on the other side's board - Jurema Falamansa hands an enemy Pacifista for its next turn).
## "rapidez_until_next_turn": N lends the unit Rapidez N until its owner's next turn starts (it never lowers a Rapidez the unit already has);
## Corrente de Ar pairs it with Esquiva, which does nothing on a unit without Rapidez.
## "bonus_if_card": {"card": id, "atk": N, "hp": N}: when the target is that card, it also gains this permanently (Myrra -> Vael).
## "bonus_if_tribe": {"tribe": [...], "atk": N, "hp": N}: when the target has any of these tribe, it also gains this permanently (Consagração).
## "only_tribe": [...]: the buff only lands on targets that have at least one of these tribe; any other target is left
## untouched (Mefi'Urdim gives Escudo Mágico only to his divindades, celestiais and anjos).
## "only_rarity": [...]: the buff only lands on targets of one of these rarities; any other target is left untouched
## (Otávio gives Ataque Duplo only to a Lendária).
## "copy_atk": "highest_ally": the unit takes the Ataque of the OTHER allied unit with the highest Ataque (nothing happens when it
## already has as much). With "temp": true it lasts until the end of the turn (Nerithia, Ao Desafiar). Ignores atk/hp.
## "copy_atk_min_gain": N (with copy_atk) is a pity: the copy always gives at least +N Ataque, even when no ally has more
## (Nerithia: at least +2 when she challenges).
## "atk_multiply": N multiplies the unit's current Ataque (base + permanent gains) by N on top of the plain "atk" gain (Vørn Ω doubles with 2).
## "cleanse": true also purifies every target the buff lands on (all its Veneno/Queimadura/Sangramento markers go away).
## "rapidez_temp": N ADDS N Rapidez until the end of the turn (it stacks with the Rapidez the unit already has, total capped at 3).
## "rapidez_temp_needs_rapidez": true only gives it to a unit that already has some Rapidez (Drake's power).
## "tribe_temp_bonus": {"tribe": [...], "atk": N, "ignore_rapidez_need": true}: a target of one of these tribe also gets +N Ataque until the
## end of the turn, and (with ignore_rapidez_need) gets "rapidez_temp" even without any Rapidez (Drake: a Dragão Negro gets +1 Ataque and +1 Rapidez).
## "hp_floor": N (with a negative "hp") means this effect never takes the unit's Vida below N: it removes only as much Vida as
## fits (the Ataque loss still lands in full). A unit already at N or less loses no Vida (Alexa Neruvya Mar-Mãe: -2/-2, but it never dies from it).

var attack := 0
var health := 0
var health_floor := 0 ## "hp_floor": the Vida that is left (hp_left) never drops under this because of this effect; 0 = no floor
var armor := 0
var temporary_armor := 0
var minimum_armor := 0
var temporary_magic_shield := false
var supreme_shield_until := "" ## "next_turn" or "end_turn": a timed Escudo Supremo ("" = none asked for)
var temporary_attack_until_next_turn := 0
var temporary_health_until_next_turn := 0
var temporary := false
var keywords: Array = []
var keywords_this_turn: Array = []
var keywords_until_next_turn: Array = []
var keywords_until_owner_turn_end: Array = []
var per := ""
var multiplier_min := 0
var multiplier_max := 99
var multiplier_offset := 0 ## "per_offset": added to the multiplier after the min/max clamp
var has_attack_cap := false
var attack_cap := 0
var minimum_rapidez := 0
var temporary_rapidez := 0 ## "rapidez_until_next_turn"
var critico_to_max := false
var bonus_card := ""
var bonus_attack := 0
var bonus_health := 0
var temporary_critico := 0 ## "critico_temp": N extra Crítico levels until the end of the turn (the total never passes 4)
var copy_attack_source := "" ## "copy_atk": "highest_ally" = copy the Ataque of the strongest other allied unit
var bonus_tribe: Array = [] ## "bonus_if_tribe": tribe that earn the extra bonus below
var tribe_bonus_attack := 0
var tribe_bonus_health := 0
var only_tribe: Array = [] ## "only_tribe": the target must share one of these tribe or the buff does nothing
var only_rarity: Array = [] ## "only_rarity": the target must be one of these rarities or the buff does nothing
var cleanse := false
var attack_multiplier := 1
var copy_minimum_gain := 0 ## "copy_atk_min_gain": the copy never gives less than this much Ataque
var added_rapidez_this_turn := 0 ## "rapidez_temp": Rapidez added on top until the end of the turn
var added_rapidez_needs_rapidez := false ## "rapidez_temp_needs_rapidez": only for a unit that already has Rapidez
var turn_bonus_tribe: Array = [] ## "tribe_temp_bonus": tribe that earn the end-of-turn extras below
var turn_bonus_attack := 0
var turn_bonus_ignores_rapidez_need := false

func _read_parameters(data: Dictionary) -> void:
	only_tribe = data.get("only_tribe", [])
	only_rarity = data.get("only_rarity", [])
	cleanse = bool(data.get("cleanse", false))
	attack_multiplier = int(data.get("atk_multiply", 1))
	copy_minimum_gain = int(data.get("copy_atk_min_gain", 0))
	attack = int(data.get("atk", 0))
	health = int(data.get("hp", 0))
	health_floor = int(data.get("hp_floor", 0))
	armor = int(data.get("armor", 0))
	temporary_armor = int(data.get("armor_temp", 0))
	minimum_armor = int(data.get("armor_min", 0))
	temporary_magic_shield = bool(data.get("magic_shield_temp", false))
	supreme_shield_until = String(data.get("supreme_shield_until", ""))
	temporary_attack_until_next_turn = int(data.get("atk_temp", 0))
	temporary_health_until_next_turn = int(data.get("hp_temp_until_next_turn", 0))
	temporary = bool(data.get("temp", false))
	keywords = data.get("keywords", [])
	keywords_this_turn = data.get("keywords_this_turn", [])
	keywords_until_next_turn =data.get("keywords_until_next_turn", [])
	keywords_until_owner_turn_end = data.get("keywords_until_owner_turn_end", [])
	per = String(data.get("per", ""))
	multiplier_min = int(data.get("min", 0))
	multiplier_max = int(data.get("max", 99))
	multiplier_offset = int(data.get("per_offset", 0))
	has_attack_cap = data.has("cap_atk")
	attack_cap = int(data.get("cap_atk", 0))
	minimum_rapidez = int(data.get("rapidez_min", 0))
	temporary_rapidez = int(data.get("rapidez_until_next_turn", 0))
	critico_to_max = bool(data.get("critico_max", false))
	var bonus: Dictionary = data.get("bonus_if_card", {})
	bonus_card = String(bonus.get("card", ""))
	bonus_attack = int(bonus.get("atk", 0))
	bonus_health = int(bonus.get("hp", 0))
	temporary_critico = int(data.get("critico_temp", 0))
	copy_attack_source = String(data.get("copy_atk", ""))
	var tribe_bonus: Dictionary = data.get("bonus_if_tribe", {})
	bonus_tribe = tribe_bonus.get("tribe", [])
	tribe_bonus_attack = int(tribe_bonus.get("atk", 0))
	tribe_bonus_health = int(tribe_bonus.get("hp", 0))
	added_rapidez_this_turn = int(data.get("rapidez_temp", 0))
	added_rapidez_needs_rapidez = bool(data.get("rapidez_temp_needs_rapidez", false))
	var turn_bonus: Dictionary = data.get("tribe_temp_bonus", {})
	turn_bonus_tribe = turn_bonus.get("tribe", [])
	turn_bonus_attack = int(turn_bonus.get("atk", 0))
	turn_bonus_ignores_rapidez_need = bool(turn_bonus.get("ignore_rapidez_need", false))

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var unit := game.find_unit(target_uid)
	if unit == null:
		return
	if not only_tribe.is_empty() and not _has_any_tribe(unit, only_tribe):
		return
	if not only_rarity.is_empty() and not only_rarity.has(CardDB.card(unit.card_id).get("rarity", "")):
		return
	if cleanse:
		game.cleanse_unit_markers(unit)
	if copy_attack_source == "highest_ally":
		_copy_highest_ally_attack(game, unit, context.source_id())
		return
	if critico_to_max:
		if unit.critico_total() < 1:
			return
		var missing_levels: int = 4 - unit.critico_total()
		unit.temp_critico += missing_levels
		unit.record_stat_change(context.source_id(), "end_turn", {"critico": missing_levels})
		game._emit({"type": "buff", "uid": target_uid, "atk": 0, "hp": 0, "keywords": [], "critico": missing_levels})
		return
	var multiplier := 1
	if per == "momentum_left":
		multiplier = clampi(int(game.players[context.controller]["momentum"]), multiplier_min, multiplier_max) + multiplier_offset
	elif per == "own_artifacts":
		multiplier = game.artifact_count(context.controller)
	elif per == "sacrificed_atk":
		multiplier = context.sacrificed_attack
	var attack_gain: int = attack * multiplier
	var health_gain: int = health * multiplier
	if health_floor > 0 and health_gain < 0:
		# only remove the Vida that fits above the floor (a unit already at the floor loses none)
		var removable_health: int = maxi(0, unit.hp_left() - health_floor)
		health_gain = -mini(-health_gain, removable_health)
	if attack_multiplier > 1:
		attack_gain += (unit.atk + unit.intrinsic_atk) * (attack_multiplier - 1)
	if attack_gain < 0:
		# Ataque never goes below 0: a debuff removes only the Ataque the unit still has
		attack_gain = maxi(attack_gain, -unit.atk_total())
	if has_attack_cap:
		attack_gain = mini(attack_gain, attack_cap - unit.cap_atk_gain)
		if attack_gain <= 0:
			return
		unit.cap_atk_gain += attack_gain
	# what this buff changed, per how long it lasts, for the overlay's source list (Card.stat_sources)
	var permanent_changes := {}
	var end_of_turn_changes := {}
	var until_next_turn_changes := {}
	if temporary:
		end_of_turn_changes = {"atk": attack_gain, "hp": health_gain, "armor": armor}
	else:
		permanent_changes = {"atk": attack_gain, "hp": health_gain, "armor": armor}
	until_next_turn_changes = {"atk": temporary_attack_until_next_turn, "hp": temporary_health_until_next_turn, "armor": temporary_armor}
	if temporary:
		unit.temp_atk += attack_gain
		unit.temp_hp += health_gain
	else:
		unit.atk += attack_gain
		unit.hp += health_gain
	if bonus_card != "" and unit.card_id == bonus_card:
		unit.atk += bonus_attack
		unit.hp += bonus_health
		_add_changes(permanent_changes, {"atk": bonus_attack, "hp": bonus_health})
		attack_gain += bonus_attack
		health_gain += bonus_health
	if not bonus_tribe.is_empty() and _shares_tribe(unit):
		unit.atk += tribe_bonus_attack
		unit.hp += tribe_bonus_health
		_add_changes(permanent_changes, {"atk": tribe_bonus_attack, "hp": tribe_bonus_health})
		attack_gain += tribe_bonus_attack
		health_gain += tribe_bonus_health
	var is_turn_bonus_tribe: bool = not turn_bonus_tribe.is_empty() and _has_any_tribe(unit, turn_bonus_tribe)
	if is_turn_bonus_tribe and turn_bonus_attack != 0:
		unit.temp_atk += turn_bonus_attack
		_add_changes(end_of_turn_changes, {"atk": turn_bonus_attack})
		attack_gain += turn_bonus_attack
	unit.temp_atk_until_next_turn += temporary_attack_until_next_turn # ends when the unit's owner starts their next turn
	attack_gain += temporary_attack_until_next_turn
	unit.temp_hp_until_next_turn += temporary_health_until_next_turn # ends when the unit's owner starts their next turn
	health_gain += temporary_health_until_next_turn
	unit.temp_armor += temporary_armor # lasts until the unit's owner starts their next turn
	if temporary: # "temp": true makes the plain Armadura last only until the end of this turn
		unit.turn_armor += armor
	else:
		unit.armor += armor # Armadura stacks: giving Armadura X to a unit that has Y leaves X + Y
	var armor_raised_to := 0
	if minimum_armor > unit.armor:
		_add_changes(permanent_changes, {"armor": minimum_armor - unit.armor})
		unit.armor = minimum_armor
		armor_raised_to = minimum_armor
	if temporary_magic_shield and not unit.magic_shield:
		unit.magic_shield = true
		unit.magic_shield_until_next_turn = true
	if supreme_shield_until != "":
		unit.grant_supreme_shield(supreme_shield_until)
	for keyword in keywords:
		_grant_keyword(unit, keyword, temporary)
	# the keywords of "keywords_this_turn" always end with the turn, whatever "temp" says about the stats
	for keyword in keywords_this_turn:
		_grant_keyword(unit, keyword, true)
	var granted_keywords: Array = raw.get("keywords", []).duplicate()
	granted_keywords.append_array(keywords_this_turn)
	for keyword in keywords_until_next_turn:
		if not unit.keywords.has(keyword):
			unit.keywords.append(keyword)
			unit.keywords_until_next_turn.append(keyword)
			granted_keywords.append(keyword)
	for keyword in keywords_until_owner_turn_end:
		if not unit.keywords.has(keyword):
			unit.keywords.append(keyword)
			unit.keywords_until_owner_turn_end.append(keyword)
			granted_keywords.append(keyword)
	var buff_event := {"type": "buff", "uid": target_uid, "atk": attack_gain, "hp": health_gain, "keywords": granted_keywords}
	if minimum_rapidez > unit.rapidez:
		_add_changes(permanent_changes, {"rapidez": minimum_rapidez - unit.rapidez})
		unit.rapidez = minimum_rapidez
		buff_event["rapidez"] = minimum_rapidez
	if temporary_rapidez > unit.rapidez_total():
		_add_changes(until_next_turn_changes, {"rapidez": temporary_rapidez - unit.rapidez_total()})
		unit.rapidez_until_next_turn = temporary_rapidez
		buff_event["rapidez"] = temporary_rapidez
	if added_rapidez_this_turn > 0:
		var has_rapidez: bool = maxi(unit.rapidez, unit.rapidez_until_next_turn) + unit.temp_rapidez > 0
		var may_receive: bool = has_rapidez or not added_rapidez_needs_rapidez or (is_turn_bonus_tribe and turn_bonus_ignores_rapidez_need)
		if may_receive:
			var rapidez_before: int = unit.rapidez_total()
			unit.temp_rapidez += added_rapidez_this_turn
			_add_changes(end_of_turn_changes, {"rapidez": unit.rapidez_total() - rapidez_before})
			buff_event["rapidez"] = unit.rapidez_total()
	if armor + temporary_armor > 0:
		buff_event["armor"] = armor + temporary_armor
	elif armor_raised_to > 0:
		buff_event["armor"] = armor_raised_to
	if temporary_critico > 0:
		var critico_before := unit.temp_critico
		unit.temp_critico = mini(4, unit.temp_critico + temporary_critico)
		_add_changes(end_of_turn_changes, {"critico": unit.temp_critico - critico_before})
		buff_event["critico"] = temporary_critico
	unit.record_stat_change(context.source_id(), "", permanent_changes)
	unit.record_stat_change(context.source_id(), "end_turn", end_of_turn_changes)
	unit.record_stat_change(context.source_id(), "next_turn", until_next_turn_changes)
	game._emit(buff_event)

## Gives the unit one keyword; with `only_this_turn` it ends with the turn (shields and plain keywords alike).
func _grant_keyword(unit: Card, keyword: String, only_this_turn: bool) -> void:
	if keyword == "escudo":
		unit.shield = true
	elif keyword == "escudo_supremo":
		unit.grant_supreme_shield("end_turn" if only_this_turn else "")
	elif keyword == "escudo_magico":
		if not unit.magic_shield:
			unit.magic_shield = true
			if only_this_turn:
				unit.magic_shield_until_end_turn = true
		elif not only_this_turn:
			# A new permanent grant makes the protection survive any temporary grant already present.
			unit.magic_shield = true
			unit.magic_shield_until_end_turn = false
			unit.magic_shield_until_next_turn = false
	elif not unit.keywords.has(keyword):
		unit.keywords.append(keyword)
		if only_this_turn:
			unit.temp_keywords.append(keyword)

## Adds the stat changes in `extra` to `changes` (both {stat name: amount}).
func _add_changes(changes: Dictionary, extra: Dictionary) -> void:
	for stat_name in extra:
		changes[stat_name] = int(changes.get(stat_name, 0)) + int(extra[stat_name])

## True when the unit has at least one of the tribe that earn the "bonus_if_tribe" extra.
func _shares_tribe(unit: Card) -> bool:
	return _has_any_tribe(unit, bonus_tribe)

## True when the unit's card lists at least one of the given tribe.
func _has_any_tribe(unit: Card, wanted_tribe: Array) -> bool:
	for tribe in CardDB.card(unit.card_id).get("tribe", []):
		if wanted_tribe.has(tribe):
			return true
	return false

## The unit's Ataque rises to match the strongest OTHER unit on its side. The difference is the gain, so the unit's own
## bonuses stay and it never loses Ataque by copying a weaker ally.
func _copy_highest_ally_attack(game: GameState, unit: Card, source: String) -> void:
	var highest_ally_attack := 0
	for ally: Card in game.players[unit.owner]["board"]:
		if ally != unit:
			highest_ally_attack = maxi(highest_ally_attack, game.atk_of(ally))
	var attack_gain: int = maxi(highest_ally_attack - game.atk_of(unit), copy_minimum_gain)
	if attack_gain <= 0:
		return
	if temporary:
		unit.temp_atk += attack_gain
	else:
		unit.atk += attack_gain
	unit.record_stat_change(source, "end_turn" if temporary else "", {"atk": attack_gain})
	game._emit({"type": "buff", "uid": unit.uid, "atk": attack_gain, "hp": 0, "keywords": []})
