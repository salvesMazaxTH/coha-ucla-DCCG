class_name Card
extends RefCounted
## One physical card. The same object travels between zones (deck, hand, board, graveyard,
## banished, stack) for the whole match, so a card can keep state and react wherever it is.
## Board fields are (re)initialized by enter_board(); off the board only identity and the
## hand discount matter. to_dict() gives the JSON form sent over the network.

var uid: int
var card_id: String
var owner: int
var zone := "" ## "deck" / "hand" / "board" / "relics" / "graveyard" / "banished" / "stack" / "equipped" / ""
var discount := 0 ## costs this much less while it stays in hand (Tecnomante); cleared when it leaves the hand
var turn_discount := 0 ## costs this much less until the end of the current turn while it stays in hand
var cost_mod := 0 ## added to the cost in every zone and never reset (A Vagante Sombria: -1 per card of yours sent to the graveyard)
var banish_after_cast := false ## taken back from the graveyard by "grave_retrieve": it is banished when its next cast ends
var banish_at_turn_end := false ## put into play by "summon_hand_pick" (Dona Gertrudes): banished when the turn ends
var over: Dictionary = {} ## per-instance overrides of the card data (atk, hp, keywords, effects, text...)

# board state
var incarnation := false ## the Leader's Encarnação (from the Santuário), NOT the "legendary" rarity; it keeps the flag while it sits in a hand
var atk := 0
var hp := 0
var damage := 0
var temp_atk := 0
var temp_hp := 0 ## extra Vida that lasts until the end of the turn; it soaks damage first, so nothing dies from it expiring
var temp_hp_until_next_turn := 0 ## extra Vida that lasts until this unit's owner's next turn starts
var rapidez := 0 ## Rapidez 0-3, as written on the card (0 = no Rapidez keyword): in a challenge, the faster unit deals its damage first (equal = at the same time)
var keywords: Array = []
var temp_keywords: Array = []
var keywords_until_next_turn: Array = [] ## keywords granted only until this unit's owner's next turn starts (Cortina de Fumaça Barata); they leave then
var lost_keywords: Array = [] ## keywords taken away only until the end of this turn (Saltador de Cerca); they come back then
var shield := false
var temp_armor := 0 ## extra Armadura that ends when its owner's next turn starts
var turn_armor := 0 ## extra Armadura that ends with the current turn ("temp": true on a buff)
var temp_atk_until_next_turn := 0 ## extra Ataque that also ends when its owner's next turn starts ("atk_temp", e.g. Morakhan)
var armor := 0 ## Armadura: every damage instance is reduced by this much (stacks when given more)
var critico := 0 ## Crítico level 0-4 (0 = none): each combat blow has level x 25% chance to be a critical hit
var temp_critico := 0 ## extra Crítico levels that last until the end of the turn
var attacks_made := 0 ## attacks declared this turn (Ataque Duplo lets a unit attack twice before it is spent)
var magic_shield := false
var magic_shield_until_next_turn := false ## the Escudo Mágico was granted only until its owner's next turn starts (Tyren)
var magic_shield_until_end_turn := false ## the Escudo Mágico was granted with temp:true and expires at the current turn's end
const SUPREME_SHIELD_LENGTH := {"end_turn": 1, "next_turn": 2, "": 3} ## how long each expiry lasts, to keep the longest

var supreme_shield := false ## Escudo Supremo: one charge that absorbs absolutely anything aimed at this card (a free-standing artifact can hold it too)
var supreme_shield_expires := "" ## "" = until used; "next_turn" = until its owner's next turn starts; "end_turn" = until the current turn ends
var exhausted := false
var sick := true
var bonus_atk := 0 ## from "constante" scale effects (see GameState._refresh_scaling)
var bonus_hp := 0
var has_bonus := false ## bonus_* were computed at least once (they only show up in to_dict then)
var surge_keywords: Array = [] ## keywords given while the owner has 11+ Momentum ("momentum_surge"); recomputed by _refresh_scaling
var surge_critico := 0 ## Crítico level given by the same surge (the higher of it and the unit's own wins)
var surge_active := false ## the surge was on at the last refresh: Escudo is granted only when it turns on, not on every refresh
var frozen := 0 ## Congelada: the turn at whose END it thaws; 0 = not frozen
var stun_markers := 0 ## Atordoamento: each marker costs the unit one untap (one start of its owner's turn); 0 = not stunned
var condemned_turn := 0 ## Condenada: the turn at whose START it dies; 0 = not condemned
var dot_markers: Dictionary = {} ## accumulated periodic-status markers, keyed by dot id
var tide_mark := false
var used_turn: Dictionary = {} ## effect index -> turn it was last used (once_per_turn)
var capped_uses: Dictionary = {} ## effect index -> [turn, times it fired that turn] (max_per_turn on a unit trigger)
var conditional_uses_turn := -1 ## the turn "conditional_uses_per_turn" is counting (Seymour)
var conditional_uses := 0 ## how many Condicional effects of this card were triggered in that turn
var trigger_counts: Dictionary = {} ## trigger -> how many times this instance fired it, only counted for triggers that have "nth" effects (Vørn Ω)
var equipment: Card = null
var equipment_grant: Dictionary = {} ## what the equipment gave this unit ({atk, hp, armor, keywords}); taken back when the equipment leaves
var cap_atk_gain := 0 ## attack given so far by "cap_atk" buffs
var dodge_turn := -1 ## turn its Esquiva was last used
var activated_turn := -1 ## turn its Ao Ativar was last used
var vipranna_heal_turn := -1 ## turn in which this Tox Vipranna last accepted a healing trigger
var vipranna_heal_total := 0 ## requested healing accepted by this Vipranna during that turn
var vipranna_heal_locked := false ## later triggers stay off after this instance reaches the 15-point threshold
var leader_damage_guard_turn := -1 ## turn in which this card reduced the first damage to its Leader
var death_ward_armed := false ## a free-standing artifact is ready to prevent one allied unit death
var charges_used := 0 ## Condicional firings spent so far by a card with "charges": N (Ampola Curativa)

## Card-data fields that are an ability or a keyword's number: silence() deletes them from the unit.
const SILENCED_FIELDS := ["activated", "transform", "rapidez", "critico", "armor", "adjacent_armor", "esquiva", "inert", "imune_critico",
		"critico_growth", "critico_maximo", "toxico_level", "toxico_equals_attack", "toxico_ignores_immunity",
		"toxico_hits_leader", "leader_damage_reduction", "conditional_uses_per_turn",
		"lethal_touch_immune", "lethal_ward", "death_ward", "spell_discount"]

func _init(card_uid: int, id: String, owner_player: int, in_zone: String = "") -> void:
	uid = card_uid
	card_id = id
	owner = owner_player
	zone = in_zone

## Uses a card with "charges" has left (-1 when the card has no limited uses).
func charges_left() -> int:
	var total: int = int(data().get("charges", 0))
	if total <= 0:
		return -1
	return maxi(total - charges_used, 0)

## Card data with this instance's overrides applied.
func data() -> Dictionary:
	return CardDB.card_for(card_id, {"over": over})

## This instance's effects as Effect objects: its own overrides if it has any, else the catalog's.
func effect_list() -> Array:
	if over.has("effects"):
		return EffectRegistry.parse_list(over["effects"])
	return CardDB.def(card_id).effects()

## Puts fresh board state on the card as it enters the board.
func enter_board(is_incarnation: bool, overrides: Dictionary = {}) -> void:
	over = overrides
	var cd := data()
	var kws: Array = cd.get("keywords", []).duplicate()
	incarnation = is_incarnation
	banish_at_turn_end = false # a revived copy is a normal unit again
	atk = int(cd["atk"])
	hp = int(cd["hp"])
	damage = 0
	temp_atk = 0
	temp_hp = 0
	temp_hp_until_next_turn = 0
	rapidez = int(cd.get("rapidez", 0))
	armor = int(cd.get("armor", 0))
	temp_armor = 0
	turn_armor = 0
	temp_atk_until_next_turn = 0
	magic_shield_until_next_turn = false
	magic_shield_until_end_turn = false
	supreme_shield = kws.has("escudo_supremo")
	supreme_shield_expires = ""
	critico = int(cd.get("critico", 0))
	temp_critico = 0
	attacks_made = 0
	shield = kws.has("escudo")
	magic_shield = kws.has("escudo_magico")
	kws.erase("escudo")
	kws.erase("escudo_magico")
	kws.erase("escudo_supremo")
	keywords = kws
	temp_keywords = []
	keywords_until_next_turn = []
	lost_keywords = []
	exhausted = false
	sick = true
	bonus_atk = 0
	bonus_hp = 0
	has_bonus = false
	frozen = 0
	condemned_turn = 0
	dot_markers = {}
	tide_mark = false
	used_turn = {}
	capped_uses = {}
	conditional_uses_turn = -1
	conditional_uses = 0
	trigger_counts = {}
	equipment = null
	equipment_grant = {}
	cap_atk_gain = 0
	dodge_turn = -1
	activated_turn = -1
	vipranna_heal_turn = -1
	vipranna_heal_total = 0
	vipranna_heal_locked = false
	leader_damage_guard_turn = -1
	death_ward_armed = false

## Silenciada: the unit lost every keyword and effect (see silence()).
func is_silenced() -> bool:
	return bool(over.get("silenced", false))

## Silence (permanent while the unit stays on the board): strips the card's keywords and every ability, and puts the
## unit back to its printed Ataque and Vida (buffs and equipment stats are gone). It keeps the damage it already took
## and its status effects (Veneno, Congelada...).
## It only removes what belongs to THIS unit. A Constante of an ally (species_aura, adjacent_armor...) is the ally's
## effect, not this unit's, so its bonus stays until that ally is silenced or leaves: bonus_atk / bonus_hp are
## therefore left alone here (GameState._refresh_scaling rebuilds them from the allies' auras and drops the unit's own
## scaling, which went away with its effects). SilenceEffect refreshes and then calls keep_alive_with_one_hp().
## It is written as per-instance overrides ("over"), so everything that reads the card through data() sees a card without
## abilities, and the network mirror carries it for free. A null override deletes that field from the merged data.
## Entering the board again starts clean (enter_board replaces "over").
func silence() -> void:
	var cd := data()
	# back to the printed stats: permanent buffs, temporary buffs, scaling bonuses and what the equipment gave
	atk = int(cd["atk"])
	hp = int(cd["hp"])
	temp_atk = 0
	temp_hp = 0
	temp_hp_until_next_turn = 0
	temp_atk_until_next_turn = 0
	cap_atk_gain = 0
	equipment_grant = {} # the equipment stays attached but gives nothing now, so there is nothing to take back later
	keep_alive_with_one_hp()
	# keywords the card had: the printed ones plus whatever it gained since (an equipment's, a buff's)
	keywords = []
	temp_keywords = []
	keywords_until_next_turn = []
	lost_keywords = [] # nothing left to give back
	shield = false
	magic_shield = false
	magic_shield_until_next_turn = false
	magic_shield_until_end_turn = false
	supreme_shield = false
	supreme_shield_expires = ""
	# keyword numbers: Rapidez and Crítico are keyword-only; of the Armadura only the printed part goes
	rapidez = 0
	critico = 0
	temp_critico = 0
	armor = maxi(0, armor - int(cd.get("armor", 0)))
	var silenced_over := over.duplicate(true)
	silenced_over["silenced"] = true
	silenced_over["keywords"] = []
	silenced_over["effects"] = []
	silenced_over["text"] = "Silenciada: perdeu as palavras-chave e os efeitos."
	for lost_field in SILENCED_FIELDS:
		silenced_over[lost_field] = null
	over = silenced_over

## Like losing an equipment: a silence never kills the unit, it stays with 1 Vida.
func keep_alive_with_one_hp() -> void:
	if hp_left() < 1:
		damage = hp + bonus_hp + temp_hp + temp_hp_until_next_turn - 1

## Escudo Supremo granted by an effect. `expires` is "" (until used), "next_turn" or "end_turn". A longer protection
## is never shortened by a later, shorter grant.
func grant_supreme_shield(expires := "") -> void:
	if supreme_shield and SUPREME_SHIELD_LENGTH[supreme_shield_expires] >= SUPREME_SHIELD_LENGTH[expires]:
		return
	supreme_shield = true
	supreme_shield_expires = expires

func has_kw(kw: String) -> bool:
	if kw == "escudo":
		return shield
	if kw == "escudo_magico":
		return magic_shield
	if kw == "escudo_supremo":
		return supreme_shield
	if kw == "inerte":
		return keywords.has(kw) or bool(data().get("inert", false))
	return keywords.has(kw) or surge_keywords.has(kw)

func armor_total() -> int:
	return armor + temp_armor + turn_armor

## ATK right now (a Congelada unit keeps its full ATK: it still strikes back when challenged).
func atk_total() -> int:
	return maxi(0, atk + temp_atk + temp_atk_until_next_turn + bonus_atk)

## Rapidez right now (0-3). A Congelada unit has its Rapidez suppressed, so it counts as Rapidez 0 until it thaws.
func rapidez_total() -> int:
	if is_frozen() or is_stunned():
		return 0
	return clampi(rapidez, 0, 3)

## Crítico level right now (0 = none, 4 = every blow is critical).
func critico_total() -> int:
	return clampi(maxi(critico + temp_critico, surge_critico), 0, 4)

func hp_left() -> int:
	return hp + bonus_hp + temp_hp + temp_hp_until_next_turn - damage

## Congelada until the end of the next turn: it doesn't attack, doesn't untap and
## doesn't guard its Leader (see CombatSystem.attack_targets). ATK and strike back stay whole.
func is_frozen() -> bool:
	return frozen > 0

## Atordoada: it was tapped by the stun and stays tapped for as many of its owner's turn starts as it has markers.
## Like a Congelada unit it doesn't attack and has no Rapidez, but it is tapped, so it can be challenged.
func is_stunned() -> bool:
	return stun_markers > 0

func is_condemned() -> bool:
	return condemned_turn > 0

## JSON form: {uid, card_id} off the board (plus "discount" in hand); the full unit on the board.
func to_dict() -> Dictionary:
	var d := {"uid": uid, "card_id": card_id}
	if zone == "hand" and discount > 0:
		d["discount"] = discount
	if zone == "hand" and turn_discount > 0:
		d["turn_discount"] = turn_discount
	if cost_mod != 0:
		d["cost_mod"] = cost_mod
	if banish_after_cast:
		d["banish_after_cast"] = true # so the client can warn that the next cast banishes it
	if death_ward_armed:
		d["death_ward_armed"] = true
	if charges_used > 0:
		d["charges_used"] = charges_used
	if supreme_shield: # written before the board-only part: a free-standing artifact can hold it too
		d["supreme_shield"] = true
		if supreme_shield_expires != "":
			d["supreme_shield_expires"] = supreme_shield_expires
	if zone != "board":
		return d
	d.merge({
		"owner": owner, "incarnation": incarnation, "atk": atk, "hp": hp, "damage": damage,
		"temp_atk": temp_atk, "keywords": keywords.duplicate(), "temp_keywords": temp_keywords.duplicate(),
		"shield": shield, "magic_shield": magic_shield, "exhausted": exhausted, "sick": sick,
	})
	if not over.is_empty():
		d["over"] = over.duplicate(true)
	if armor > 0:
		d["armor"] = armor
	if temp_armor > 0:
		d["temp_armor"] = temp_armor
	if turn_armor > 0:
		d["turn_armor"] = turn_armor
	if temp_atk_until_next_turn > 0:
		d["temp_atk_until_next_turn"] = temp_atk_until_next_turn
	if magic_shield_until_next_turn:
		d["magic_shield_until_next_turn"] = true
	if magic_shield_until_end_turn:
		d["magic_shield_until_end_turn"] = true
	if not keywords_until_next_turn.is_empty():
		d["keywords_until_next_turn"] = keywords_until_next_turn.duplicate()
	if not lost_keywords.is_empty():
		d["lost_keywords"] = lost_keywords.duplicate()
	if temp_hp > 0:
		d["temp_hp"] = temp_hp
	if temp_hp_until_next_turn > 0:
		d["temp_hp_until_next_turn"] = temp_hp_until_next_turn
	if rapidez != 0:
		d["rapidez"] = rapidez
	if critico > 0:
		d["critico"] = critico
	if temp_critico > 0:
		d["temp_critico"] = temp_critico
	if attacks_made > 0:
		d["attacks_made"] = attacks_made
	if has_bonus:
		d["bonus_atk"] = bonus_atk
		d["bonus_hp"] = bonus_hp
	if not surge_keywords.is_empty():
		d["surge_keywords"] = surge_keywords.duplicate()
	if surge_critico > 0:
		d["surge_critico"] = surge_critico
	if surge_active:
		d["surge_active"] = true
	if frozen > 0:
		d["frozen"] = frozen
	if stun_markers > 0:
		d["stun_markers"] = stun_markers
	if condemned_turn > 0:
		d["condemned_turn"] = condemned_turn
	if not dot_markers.is_empty():
		d["dot_markers"] = dot_markers.duplicate()
	if tide_mark:
		d["tide_mark"] = true
	if not used_turn.is_empty():
		d["used_turn"] = used_turn.duplicate()
	if not capped_uses.is_empty():
		d["capped_uses"] = capped_uses.duplicate()
	if conditional_uses > 0:
		d["conditional_uses"] = [conditional_uses_turn, conditional_uses]
	if not trigger_counts.is_empty():
		d["trigger_counts"] = trigger_counts.duplicate()
	if equipment != null:
		d["equipment"] = {"uid": equipment.uid, "card_id": equipment.card_id}
		if not equipment_grant.is_empty():
			d["equipment_grant"] = equipment_grant.duplicate(true)
	if cap_atk_gain > 0:
		d["cap_atk_gain"] = cap_atk_gain
	if dodge_turn >= 0:
		d["dodge_turn"] = dodge_turn
	if activated_turn >= 0:
		d["activated_turn"] = activated_turn
	if vipranna_heal_turn >= 0:
		d["vipranna_heal_turn"] = vipranna_heal_turn
		d["vipranna_heal_total"] = vipranna_heal_total
		if vipranna_heal_locked:
			d["vipranna_heal_locked"] = true
	if leader_damage_guard_turn >= 0:
		d["leader_damage_guard_turn"] = leader_damage_guard_turn
	return d

## Rebuilds a card from to_dict() output (network mirror). Board cards need "owner".
static func from_dict(d: Dictionary, in_zone: String, owner_player: int) -> Card:
	var c := Card.new(int(d["uid"]), String(d["card_id"]), int(d.get("owner", owner_player)), in_zone)
	c.discount = int(d.get("discount", 0))
	c.turn_discount = int(d.get("turn_discount", 0))
	c.cost_mod = int(d.get("cost_mod", 0))
	c.death_ward_armed = bool(d.get("death_ward_armed", false))
	c.charges_used = int(d.get("charges_used", 0))
	c.supreme_shield = bool(d.get("supreme_shield", false))
	c.supreme_shield_expires = String(d.get("supreme_shield_expires", ""))
	c.over = d.get("over", {})
	if in_zone != "board":
		return c
	c.incarnation = bool(d["incarnation"])
	c.atk = int(d["atk"])
	c.hp = int(d["hp"])
	c.damage = int(d["damage"])
	c.temp_atk = int(d["temp_atk"])
	c.keywords = d["keywords"]
	c.temp_keywords = d["temp_keywords"]
	c.armor = int(d.get("armor", 0))
	c.temp_armor = int(d.get("temp_armor", 0))
	c.turn_armor = int(d.get("turn_armor", 0))
	c.temp_atk_until_next_turn = int(d.get("temp_atk_until_next_turn", 0))
	c.magic_shield_until_next_turn = bool(d.get("magic_shield_until_next_turn", false))
	c.magic_shield_until_end_turn = bool(d.get("magic_shield_until_end_turn", false))
	c.keywords_until_next_turn = d.get("keywords_until_next_turn", [])
	c.lost_keywords = d.get("lost_keywords", [])
	c.temp_hp = int(d.get("temp_hp", 0))
	c.temp_hp_until_next_turn = int(d.get("temp_hp_until_next_turn", 0))
	c.rapidez = int(d.get("rapidez", 0))
	c.critico = int(d.get("critico", 0))
	c.temp_critico = int(d.get("temp_critico", 0))
	c.attacks_made = int(d.get("attacks_made", 0))
	c.shield = bool(d["shield"])
	c.magic_shield = bool(d["magic_shield"])
	c.exhausted = bool(d["exhausted"])
	c.sick = bool(d["sick"])
	c.has_bonus = d.has("bonus_atk")
	c.bonus_atk = int(d.get("bonus_atk", 0))
	c.bonus_hp = int(d.get("bonus_hp", 0))
	c.surge_keywords = d.get("surge_keywords", []).duplicate()
	c.surge_critico = int(d.get("surge_critico", 0))
	c.surge_active = bool(d.get("surge_active", false))
	c.frozen = int(d.get("frozen", 0))
	c.stun_markers = int(d.get("stun_markers", 0))
	c.condemned_turn = int(d.get("condemned_turn", 0))
	c.dot_markers = d.get("dot_markers", {}).duplicate()
	# Compatibility with snapshots produced before periodic markers became generic.
	if d.has("burn") and int(d["burn"]) > 0:
		c.dot_markers["queimadura"] = int(d["burn"])
	c.tide_mark = bool(d.get("tide_mark", false))
	c.used_turn = d.get("used_turn", {})
	c.capped_uses = d.get("capped_uses", {}).duplicate()
	c.trigger_counts = d.get("trigger_counts", {}).duplicate()
	if d.has("conditional_uses"):
		c.conditional_uses_turn = int(d["conditional_uses"][0])
		c.conditional_uses = int(d["conditional_uses"][1])
	if d.has("equipment"):
		c.equipment = Card.new(int(d["equipment"]["uid"]), String(d["equipment"]["card_id"]), c.owner, "equipped")
		c.equipment_grant = d.get("equipment_grant", {})
	c.cap_atk_gain = int(d.get("cap_atk_gain", 0))
	c.dodge_turn = int(d.get("dodge_turn", -1))
	c.activated_turn = int(d.get("activated_turn", -1))
	c.vipranna_heal_turn = int(d.get("vipranna_heal_turn", -1))
	c.vipranna_heal_total = int(d.get("vipranna_heal_total", 0))
	c.vipranna_heal_locked = bool(d.get("vipranna_heal_locked", false))
	c.leader_damage_guard_turn = int(d.get("leader_damage_guard_turn", -1))
	return c
