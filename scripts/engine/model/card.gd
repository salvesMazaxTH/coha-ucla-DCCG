class_name Card
extends RefCounted
## One physical card. The same object travels between zones (deck, hand, board, graveyard,
## banished, stack) for the whole match, so a card can keep state and react wherever it is.
## Board fields are (re)initialized by enter_board(); off the board only identity and the
## hand discount matter. to_dict() gives the JSON form sent over the network.

var uid: int
var card_id: String
var owner: int
var zone := "" ## "deck" / "hand" / "board" / "graveyard" / "banished" / "stack" / "equipped" / ""
var discount := 0 ## costs this much less while it stays in hand (Tecnomante); cleared when it leaves the hand
var over: Dictionary = {} ## per-instance overrides of the card data (atk, hp, keywords, effects, text...)

# board state
var legendary := false
var atk := 0
var hp := 0
var damage := 0
var temp_atk := 0
var keywords: Array = []
var temp_keywords: Array = []
var shield := false
var spell_shield := false
var exhausted := false
var sick := true
var bonus_atk := 0 ## from "constante" scale effects (see GameState._refresh_scaling)
var bonus_hp := 0
var has_bonus := false ## bonus_* were computed at least once (they only show up in to_dict then)
var frozen := 0 ## turn at whose end it thaws; 0 = not frozen
var tide_mark := false
var used_turn: Dictionary = {} ## effect index -> turn it was last used (once_per_turn)
var equipment: Card = null
var cap_atk_gain := 0 ## attack given so far by "cap_atk" buffs
var dodge_turn := -1 ## turn its Esquiva was last used
var activated_turn := -1 ## turn its Ao Ativar was last used

func _init(card_uid: int, id: String, owner_player: int, in_zone: String = "") -> void:
	uid = card_uid
	card_id = id
	owner = owner_player
	zone = in_zone

## Card data with this instance's overrides applied.
func data() -> Dictionary:
	return CardDB.card_for(card_id, {"over": over})

## Puts fresh board state on the card as it enters the board.
func enter_board(is_legendary: bool, overrides: Dictionary = {}) -> void:
	over = overrides
	var cd := data()
	var kws: Array = cd.get("keywords", []).duplicate()
	legendary = is_legendary
	atk = int(cd["atk"])
	hp = int(cd["hp"])
	damage = 0
	temp_atk = 0
	shield = kws.has("escudo")
	spell_shield = kws.has("escudo_feitico")
	kws.erase("escudo")
	kws.erase("escudo_feitico")
	keywords = kws
	temp_keywords = []
	exhausted = false
	sick = true
	bonus_atk = 0
	bonus_hp = 0
	has_bonus = false
	frozen = 0
	tide_mark = false
	used_turn = {}
	equipment = null
	cap_atk_gain = 0
	dodge_turn = -1
	activated_turn = -1

func has_kw(kw: String) -> bool:
	if kw == "escudo":
		return shield
	if kw == "escudo_feitico":
		return spell_shield
	return keywords.has(kw)

func atk_total() -> int:
	return maxi(0, atk + temp_atk + bonus_atk)

func hp_left() -> int:
	return hp + bonus_hp - damage

## Congelada: can't attack or block until the end of its owner's next turn.
func is_frozen() -> bool:
	return frozen > 0

## JSON form: {uid, card_id} off the board (plus "discount" in hand); the full unit on the board.
func to_dict() -> Dictionary:
	var d := {"uid": uid, "card_id": card_id}
	if zone == "hand" and discount > 0:
		d["discount"] = discount
	if zone != "board":
		return d
	d.merge({
		"owner": owner, "legendary": legendary, "atk": atk, "hp": hp, "damage": damage,
		"temp_atk": temp_atk, "keywords": keywords.duplicate(), "temp_keywords": temp_keywords.duplicate(),
		"shield": shield, "spell_shield": spell_shield, "exhausted": exhausted, "sick": sick,
	})
	if not over.is_empty():
		d["over"] = over.duplicate(true)
	if has_bonus:
		d["bonus_atk"] = bonus_atk
		d["bonus_hp"] = bonus_hp
	if frozen > 0:
		d["frozen"] = frozen
	if tide_mark:
		d["tide_mark"] = true
	if not used_turn.is_empty():
		d["used_turn"] = used_turn.duplicate()
	if equipment != null:
		d["equipment"] = {"uid": equipment.uid, "card_id": equipment.card_id}
	if cap_atk_gain > 0:
		d["cap_atk_gain"] = cap_atk_gain
	if dodge_turn >= 0:
		d["dodge_turn"] = dodge_turn
	if activated_turn >= 0:
		d["activated_turn"] = activated_turn
	return d

## Rebuilds a card from to_dict() output (network mirror). Board cards need "owner".
static func from_dict(d: Dictionary, in_zone: String, owner_player: int) -> Card:
	var c := Card.new(int(d["uid"]), String(d["card_id"]), int(d.get("owner", owner_player)), in_zone)
	c.discount = int(d.get("discount", 0))
	c.over = d.get("over", {})
	if in_zone != "board":
		return c
	c.legendary = bool(d["legendary"])
	c.atk = int(d["atk"])
	c.hp = int(d["hp"])
	c.damage = int(d["damage"])
	c.temp_atk = int(d["temp_atk"])
	c.keywords = d["keywords"]
	c.temp_keywords = d["temp_keywords"]
	c.shield = bool(d["shield"])
	c.spell_shield = bool(d["spell_shield"])
	c.exhausted = bool(d["exhausted"])
	c.sick = bool(d["sick"])
	c.has_bonus = d.has("bonus_atk")
	c.bonus_atk = int(d.get("bonus_atk", 0))
	c.bonus_hp = int(d.get("bonus_hp", 0))
	c.frozen = int(d.get("frozen", 0))
	c.tide_mark = bool(d.get("tide_mark", false))
	c.used_turn = d.get("used_turn", {})
	if d.has("equipment"):
		c.equipment = Card.new(int(d["equipment"]["uid"]), String(d["equipment"]["card_id"]), c.owner, "equipped")
	c.cap_atk_gain = int(d.get("cap_atk_gain", 0))
	c.dodge_turn = int(d.get("dodge_turn", -1))
	c.activated_turn = int(d.get("activated_turn", -1))
	return c
