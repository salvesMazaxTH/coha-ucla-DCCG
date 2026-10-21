class_name GameState
extends RefCounted
## Pure, UI-free rules engine. Every public action validates input, mutates
## state and returns an Array of event Dictionaries the UI can animate.
## Invalid actions return [] and leave state untouched.

const START_HAND := 5
const MULLIGAN_MAX := 3
const HAND_LIMIT := 10
const BOARD_LIMIT := 8
const MOMENTUM_CAP := 10
const MOMENTUM_OVERFLOW_CAP := 20 ## the most Momentum a turn can hold when an effect says "overflow" (Eryon's deck); the part above MOMENTUM_CAP vanishes at the end of the turn
const LETHAL_WARD_NEGATED_HITS := 3 # Câmara de Êxtase: how many hits it negates after saving the Leader
const RESERVE_CAP := 2 ## unspent Momentum banked at turn start; pays only spells and abilities
const COMMANDER_TAX_STEP := 1 ## the Encarnação's tax grows by this much per previous cast: +1, then +2, +3, +4... (totals 1, 3, 6, 10)
const WEAK_UNIT_MAX_HP := 3 ## "weak_enemy_unit" targets: enemy units with this much current Vida or less (Isarelis)
const INTIMIDATE_ATK := 3 ## Intimidacao: attackers with this ATK or less cannot challenge it
const SECOND_BONUS_TURNS := 2 ## the second player's first turns that start with +1 Momentum and +1 Reserve (refill)
const SNOWBALL_GRANDE_AT := 8 ## Bola de Neve level at which every Bola de Neve card of the player evolves into a Grande Bola de Neve
const SNOWBALL_BASE_LEVEL := 2 ## Bola de Neve level a player starts at; each player's own base can grow permanently (Devaneio Gelado), see players[p]["snowball_base"]
const SNOWBALL_CARD_ID := "bola_de_neve"
const GRANDE_SNOWBALL_CARD_ID := "grande_bola_de_neve" ## a card of its own (transform_only): it only exists through that evolution
const REQUIEM_EXTRA_COST := 2 ## Réquiem: a spell cast from the graveyard costs this much more, then is banished

## Periodic marker rules. New marker types reuse add_dot/resolve_dot; only their damage policy differs.
const DOT_RULES := {
	"queimadura": "flat",
	"veneno": "poison",
	"sangramento": "life_bracket",
}

## Innate immunity of UNITS to a marker kind, given by essence: a unit with any of these
## essences can never receive that kind of marker. Leaders have no immunity. A card effect skips it by saying so explicitly
## ("ignores_immunity" in the effect, "toxico_ignores_immunity" on the card for its Tóxico).
## Sangramento has no immune essence yet.
const DOT_IMMUNE_ESSENCES := {
	"veneno": ["venenosa", "metalica"],
	"queimadura": ["ignea"],
	"sangramento": [],
}

## Each Veneno marker deals 2 damage, then half the pile (rounded up) is removed.
const VENENO_DAMAGE_PER_MARKER := 2

## Leaders are addressed with negative uids so targets are a single int.
const LEADER_UID := [-1, -2]

var players: Array = []
var active := 0
var turn := 0
var veneno_held_until := 0 ## while turn <= this, no Veneno marker is consumed anywhere (Greve Geral dos Antídotos)
var veneno_lethal_until := 0 ## while turn <= this, a unit's Veneno tick deals damage equal to its current Vida (Neráxia)
var first := 0 ## who takes turn 1 (skips that draw, mulligans first; the other gets the early Momentum bonus)
var phase := "mulligan"
var winner := -1 ## -1 none, 0/1 player, 2 draw
## Units with Provocação that just entered and wait for their controller to choose whether they
## enter tapped (phase "enter_tapped"), oldest first. Holds uids.
var pending_tap: Array = []
var _enter_tapped_return := "main" ## the phase to go back to after the choice
## Pending deterministic deck search. The matching cards are public until chosen.
var pending_search: Dictionary = {}
## Ao Entrar waiting for its owner to pick a target, after the unit is already on the board
## (phase "enter_target"): {player, uid, card_id, spec}. Optional: target 0 skips the effect.
var pending_enter: Dictionary = {}
## Spells, equipment and leader abilities wait here (LIFO) until both players let them resolve.
## Item: {sid, player, kind:"card"|"ability"|"unit_ability"|"subito"|"enter_trigger", uid, card_id, target, speed}
## ("unit_ability" = a unit's Ao Ativar; uid is the unit, card_id its card.
## "enter_trigger" = the Ao Entrar of a unit just played: uid is the unit, target the ally picked; uncounterable.
## "subito" = a unit summoned with Súbito; uid is the card, plus "slot" where it enters.)
var stack: Array = []
## Who may act during "main"/"combat". Casting hands priority to the opponent (response);
## a pass with items on the stack resolves the whole stack.
var priority := 0
## Combat window while phase == "combat": "pre_combat" (attacker first, then defender; both may
## cast Rápido/Instantâneo; ends when both pass in a row), then "attacks" (attacks one by one; between two
## attacks only the attacker may cast an Instantâneo, and the defender answers it through the stack).
var window := ""
## Main-phase response window right after the active player summoned a unit from hand or
## the Santuário (stack empty): the opponent holds priority and may cast Rápido/Instantâneo.
var summon_window := false
## The other player has already passed since the newest item was put on the stack. The player
## holding priority may still stack another Instantâneo (and the opponent answers again);
## passing instead resolves the stack. So the stack resolves when both players pass in a row.
var stack_passed := false
## Turns the "pass, then it comes back to the caster" rule on or off (on in real games; with it
## off, the opponent's pass resolves the stack at once, which the older stack tests expect).
var self_response_enabled := true
var _summon_pending := false # a summon's search delays its response window
## Per seat: skip priority windows where that player has no legal play (a player can turn
## this off to be asked every time). Also skips a block prompt with no possible blocker.
var auto_pass: Array = [true, true]
## Per seat: "PASSAR TUDO". Until the end of the opponent's turn, every response window that player
## would be asked about is passed for them, even when they do have a legal play. Cleared when a turn begins.
var skip_rest_of_turn: Array = [false, false]
var _search_return := "main"
## True while combat damage is being dealt and the deaths it causes are resolved; effects
## marked "not_in_combat" stay silent then (Cientista da Morte).
var _combat_damage := false
## True while a spell's effects are being resolved; damage it deals (with no unit as the source) counts as
## "from a spell" for effects marked "only_from_spell" (Tyren).
var _spell_resolving := false
## Cards sent to the graveyard by the latest mill (offered by mill_pick).
var rng := RandomNumberGenerator.new()
var _next_uid := 1
var _events: Array = []
## Triggers that happened but have not resolved yet (PendingTrigger), oldest first.
var _pending: Array = []
var _bus: TriggerBus ## built on first use (RemoteState never runs GameState._init)
var _stack_system: StackSystem ## built on first use, like _bus
var _combat_system: CombatSystem ## built on first use, like _bus
const EVENT_CAP := 300 ## events one action may produce before triggers/effects stop resolving
const MAX_TRIGGERS_PER_ACTION := 60 ## queued triggers resolved in one go, so trigger loops always end
## Cards played from hand while they wait on the stack (uid -> Card); stack items themselves stay plain dicts.
var _stack_cards: Dictionary = {}
## Only set on a preview copy (see preview_copy): the card with this uid resolves with no effects at all,
## so the AI can compare "cast it for real" against "cast it and nothing happens".
var preview_blank_uid := 0

func _init(deck_a: String = "", deck_b: String = "", seed_value: int = 0, first_player: int = 0) -> void:
	if deck_a == "":
		return # an empty game, filled in by preview_copy()
	rng.seed = seed_value if seed_value != 0 else randi()
	first = first_player
	for i in 2:
		players.append(_make_player(i, [deck_a, deck_b][i]))
	for i in 2:
		_draw(i, START_HAND)
	_events.clear()

## The stack and priority windows (built on first use, like bus()).
func stack_system() -> StackSystem:
	if _stack_system == null:
		_stack_system = StackSystem.new(self)
	return _stack_system

## Attack, block and damage resolution (built on first use).
func combat_system() -> CombatSystem:
	if _combat_system == null:
		_combat_system = CombatSystem.new(self)
	return _combat_system

## Delivers GameEvents to the cards that react to them (own triggers and "listen").
func bus() -> TriggerBus:
	if _bus == null:
		_bus = TriggerBus.new(self)
	return _bus

func _make_player(i: int, deck_id: String) -> Dictionary:
	var d := DeckDB.get_deck(deck_id)
	var ld := CardDB.leader(d["leader"])
	var deck: Array = []
	for id in d["cards"]:
		if id == ld["legendary"]:
			continue
		for n in int(d["cards"][id]):
			deck.append(Card.new(_uid(), id, i, "deck"))
	_shuffle(deck)
	return {
		"index": i, "deck_id": deck_id, "leader_id": d["leader"],
		"leader_hp": int(ld["hp"]), "leader_max": int(ld["hp"]),
		"momentum": 0, "max_momentum": 0, "reserve": 0,
			"saved_momentum": 0, "idle_turns": 0, "next_momentum": 0, "play_restrictions": [], "leaked": 0, "unspent": 0,
		"deck": deck, "hand": [], "board": [], "relics": [], "graveyard": [], "banished": [],
		"legendary": {"card_id": ld["legendary"], "in_zone": true, "casts": 0},
		"ability_used": false, "passive_used": false, "attacked": false, "fatigue": 0, "mulligan_done": false,
		"played_two": false,
		"snowball": SNOWBALL_BASE_LEVEL, # damage the next Bola de Neve starts at (grows with every Bola de Neve cast, goes back to snowball_base at the end of the owner's turn)
		"snowball_base": SNOWBALL_BASE_LEVEL, # the level the Bola de Neve goes back to every turn; raised for the rest of the game by Devaneio Gelado
		"critico_growth": {}, # card_id -> Crítico level reached by "critico_growth" cards (Vael), shared by every copy of it
		"glacial_discount_used": false, # the Amuleto Glacial discount was already spent this turn
		"damage_negated_until": 0, # Câmara de Êxtase aftermath: the Leader's next hits are negated while turn <= this
		"damage_negated_left": 0, # ...and this is how many hits are still left to negate
		"leader_dots": {}, # dot_id -> markers on the Leader. They tick at every turn start of its controller and are consumed like a unit's
		"leader_veneno_held_until": 0, # while turn <= this, this Leader's Veneno markers hurt but are not consumed (Antídoto Fora de Estoque)
		"frozen_slots": 0, # Rei Gelado: empty field slots of this player that accept no permanent
		"frozen_slots_until": 0, # they thaw at the end of this player's own turn, once the turn counter reaches this
		"relic_fall_turns": {}, # card_id -> turn in which the last copy of that free-standing artifact left this player's field (Erguer o Baluarte lockout)
	}

func _uid() -> int:
	_next_uid += 1
	return _next_uid

func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t

func _emit(e: Dictionary) -> void:
	_events.append(e)

## Triggers and effects stop resolving once a Leader is down (combat strikes still land, so the overkill shows,
## but nothing new fires off it) or when one action has already produced EVENT_CAP events (runaway chain).
func _chain_stopped() -> bool:
	return _events.size() >= EVENT_CAP or players[0]["leader_hp"] <= 0 or players[1]["leader_hp"] <= 0

func _flush() -> Array:
	var out := _events
	_events = []
	return out

# ---------------------------------------------------------------- previews (used by the AI)

## Variables a preview never copies or compares: the helper systems are rebuilt on first use, the event list
## starts empty, and the random generator / uid counter move on even when a spell changes nothing.
const PREVIEW_SKIPPED_VARIABLES := ["_bus", "_stack_system", "_combat_system", "_events", "rng", "_next_uid"]

## A full, independent copy of this game for the AI to try a move on ("what would happen if I cast this?").
## Every Card is copied too, so nothing done on the copy touches this game. The random generator is copied
## with its current state, so random effects pick the same way they would right now.
## Returns null when a safe copy can't be made (triggers still waiting to resolve, or a network game).
func preview_copy() -> GameState:
	if not _pending.is_empty() or get_script() != GameState:
		return null
	var copy := GameState.new()
	var copied_cards := {} # original Card -> its copy, so a card referenced from two places stays one card
	for property in get_property_list():
		if not (property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var variable_name: String = property["name"]
		if variable_name in PREVIEW_SKIPPED_VARIABLES:
			continue
		copy.set(variable_name, _preview_copy_value(get(variable_name), copied_cards))
	copy.rng.seed = rng.seed
	copy.rng.state = rng.state
	copy._next_uid = _next_uid
	return copy

static func _preview_copy_value(value: Variant, copied_cards: Dictionary) -> Variant:
	if value is Card:
		return _preview_copy_card(value, copied_cards)
	if value is Array:
		var array_copy: Array = value.duplicate(false)
		for index in array_copy.size():
			array_copy[index] = _preview_copy_value(array_copy[index], copied_cards)
		return array_copy
	if value is Dictionary:
		var dictionary_copy: Dictionary = value.duplicate(false)
		for key in dictionary_copy.keys():
			dictionary_copy[key] = _preview_copy_value(dictionary_copy[key], copied_cards)
		return dictionary_copy
	return value # numbers, strings, flags (other objects are shared: they are read-only data)

static func _preview_copy_card(card: Card, copied_cards: Dictionary) -> Card:
	if copied_cards.has(card):
		return copied_cards[card]
	var card_copy := Card.new(card.uid, card.card_id, card.owner, card.zone)
	copied_cards[card] = card_copy
	for property in card.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			card_copy.set(property["name"], _preview_copy_value(card.get(property["name"]), copied_cards))
	return card_copy

## Text describing everything that matters in this game right now (Leaders, every card in every zone, the stack,
## markers, counters...). Two games with the same snapshot are the same game, give or take random luck.
func preview_snapshot() -> String:
	var snapshot := {}
	for property in get_property_list():
		if not (property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var variable_name: String = property["name"]
		if variable_name in PREVIEW_SKIPPED_VARIABLES or variable_name == "preview_blank_uid":
			continue
		snapshot[variable_name] = _snapshot_value(get(variable_name))
	return var_to_str(snapshot)

static func _snapshot_value(value: Variant) -> Variant:
	if value is Card:
		var card_fields := {}
		for property in value.get_property_list():
			if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
				var field: Variant = value.get(property["name"])
				# a card inside a card (its equipment) is written as its uid, so the snapshot never loops
				card_fields[property["name"]] = field.uid if field is Card else _snapshot_value(field)
		return card_fields
	if value is Array:
		var array_snapshot: Array = []
		for element in value:
			array_snapshot.append(_snapshot_value(element))
		return array_snapshot
	if value is Dictionary:
		var dictionary_snapshot := {}
		for key in value:
			dictionary_snapshot[key] = _snapshot_value(value[key])
		return dictionary_snapshot
	if value is Object:
		return null # helper objects (pending triggers) are not part of what the board looks like
	return value

# ---------------------------------------------------------------- queries

func opponent(p: int) -> int:
	return 1 - p

## The player whose input the game is waiting for.
func decider() -> int:
	match phase:
		"mulligan":
			return first if not players[first]["mulligan_done"] else opponent(first)
		"enter_tapped":
			var waiting := find_unit(int(pending_tap[0])) if not pending_tap.is_empty() else null
			return waiting.owner if waiting != null else active
		"search":
			return int(pending_search.get("player", active))
		"enter_target":
			return int(pending_enter.get("player", active))
		"main", "combat":
			return priority
	return active

## The unit with this uid on either board, or null.
func find_unit(uid: int) -> Card:
	for p in players:
		for c: Card in p["board"]:
			if c.uid == uid:
				return c
	return null

## The card with this uid in any zone of either player (board, hand, deck, graveyard, banished), or null.
func find_card(uid: int) -> Card:
	for p in players:
		for zone in TriggerBus.ZONES:
			for c: Card in p[zone]:
				if c.uid == uid:
					return c
	return null

## The free-standing artifact with this uid on either side of the field, or null.
func find_relic(uid: int) -> Card:
	for p in players:
		for c: Card in p["relics"]:
			if c.uid == uid:
				return c
	return null

## How many of p's BOARD_LIMIT field slots are taken: units plus free-standing artifacts.
func slots_used(p: int) -> int:
	return players[p]["board"].size() + players[p]["relics"].size()

## True while p still has a free field slot for a unit or an artifact. Slots frozen by Rei Gelado don't count.
func has_free_slot(p: int) -> bool:
	return slots_used(p) + int(players[p]["frozen_slots"]) < BOARD_LIMIT

## Moves a card to another zone (the caller takes it out of its old array and puts it in the new one).
## The single place a card changes zone, so later "goes to the graveyard" hooks live here.
## `extra_data` is added to the card_moved event ("unit_died": true tells that an equipment fell because its unit died).
func _move(c: Card, to_zone: String, extra_data := {}) -> void:
	var from_zone := c.zone
	c.zone = to_zone
	if to_zone != "hand":
		c.discount = 0
	# a Bola de Neve that reaches the hand, deck or graveyard of a player already at Grande level is born Grande
	# (the copy that was being cast, one fetched from the graveyard, one created by an effect...)
	if c.card_id == SNOWBALL_CARD_ID and to_zone in ["hand", "deck", "graveyard"] and snowball_is_grande(c.owner):
		c.card_id = GRANDE_SNOWBALL_CARD_ID
	# a "critico_growth" copy (Vael) always carries the level its owner's copies have reached, wherever it is going
	if CardDB.card(c.card_id).get("critico_growth", false):
		c.critico = maxi(c.critico, int(players[c.owner]["critico_growth"].get(c.card_id, 0)))
	var moved := GameEvent.new("card_moved", c.owner, c)
	moved.data = {"from": from_zone, "to": to_zone}
	moved.data.merge(extra_data)
	bus().emit(moved)

## A "critico_growth" card (Vael) landed a critical: its Crítico goes up one level (max 4) for EVERY copy
## its owner has, in the deck, hand, field, graveyard or banished, and for the copies that show up later.
## Returns the new level.
func grow_critico(striker: Card) -> int:
	var owner: int = striker.owner
	var reached: int = int(players[owner]["critico_growth"].get(striker.card_id, 0))
	var new_level := mini(4, maxi(reached, striker.critico) + 1)
	players[owner]["critico_growth"][striker.card_id] = new_level
	for zone in ["deck", "hand", "board", "relics", "graveyard", "banished"]:
		for copy: Card in players[owner][zone]:
			if copy.card_id == striker.card_id:
				copy.critico = new_level
	striker.critico = new_level
	return new_level

func card_of(c: Card) -> Dictionary:
	return c.data()

func has_kw(c: Card, kw: String) -> bool:
	return c.has_kw(kw)

## Veneno markers one Tóxico hit leaves. Plain Tóxico is 1; a card can print "toxico:N" (level N) or
## "toxico:atk" (X is its current Ataque, buffs included). A unit that only gained Tóxico in play has 1.
func toxico_markers(source: Card) -> int:
	var card_data := source.data()
	if card_data.get("toxico_equals_attack", false):
		return maxi(1, source.atk_total())
	return maxi(1, int(card_data.get("toxico_level", 1)))

func atk_of(c: Card) -> int:
	return c.atk_total()

## The damage this unit deals when it strikes (combat blow or "fight" effect): its Ataque, except a
## Pacifista, whose strike is always 0 no matter how much Ataque it has. Effects that only read the
## Ataque (Intimidação, scaling...) keep using atk_of.
func strike_power_of(c: Card) -> int:
	if has_kw(c, "pacifista"):
		return 0
	return atk_of(c)

func hp_left(c: Card) -> int:
	return c.hp_left()

## Unit cards in a player's graveyard.
func graveyard_units(p: int) -> int:
	var n := 0
	for e: Card in players[p]["graveyard"]:
		if CardDB.card(e.card_id)["type"] == "unit":
			n += 1
	return n

## Recomputes the "constante" effects of board units. Action "scale" gives
## atk/hp per counted thing (e.g. +2/+2 per unit card in the own graveyard).
func _refresh_scaling() -> void:
	for p in 2:
		for c: Card in players[p]["board"]:
			var b := scale_bonus(p, card_of(c))
			var aura := species_aura_bonus(c)
			var surge := momentum_surge_of(p, c)
			c.bonus_atk = b.x + aura.x + int(surge.get("atk", 0))
			c.bonus_hp = b.y + aura.y
			c.has_bonus = true
			var surge_keywords: Array = surge.get("keywords", [])
			# Escudo is a one-use flag, not a keyword that stays on: it is granted once, at the moment the surge turns on
			if surge_keywords.has("escudo"):
				surge_keywords.erase("escudo")
				if not c.surge_active:
					c.shield = true
			c.surge_keywords = surge_keywords
			c.surge_critico = int(surge.get("critico", 0))
			c.surge_active = not surge.is_empty()

## What a unit's "momentum_surge" Constante gives it right now: {atk, keywords, critico}, or {} while its
## controller has less than the effect's "min_momentum" (default: one above MOMENTUM_CAP, i.e. 11+).
## Barão Estrondoso: +15 Ataque, Escudo (once, when the surge turns on), Sobrepujança, Ímpeto and Crítico 4
## only while the surge is on.
func momentum_surge_of(p: int, c: Card) -> Dictionary:
	for e in card_of(c).get("effects", []):
		if e.get("trigger", "") != "constante" or e.get("action", "") != "momentum_surge":
			continue
		if int(players[p]["momentum"]) < int(e.get("min_momentum", MOMENTUM_CAP + 1)):
			continue
		return {"atk": int(e.get("atk", 0)), "keywords": e.get("keywords", []).duplicate(), "critico": int(e.get("critico", 0))}
	return {}

## Atk/hp a card's "constante" scale effects would give it under player p right
## now.
func scale_bonus(p: int, cd: Dictionary) -> Vector2i:
	var out := Vector2i.ZERO
	for e in cd.get("effects", []):
		if e.get("trigger", "") != "constante" or e.get("action", "") != "scale":
			continue
		var n := _scale_count(p, e)
		out += Vector2i(n * int(e.get("atk", 0)), n * int(e.get("hp", 0)))
	return out * constants_multiplier(p)

## Which of a player's units on the board carry a "doubler" Constante (action "double_constants",
## "double_enter" or "double_death"). `ignoring_uid` skips one unit (a doubler never doubles its own Ao Entrar).
func has_doubler(p: int, doubler_action: String, ignoring_uid := 0) -> bool:
	for source: Card in players[p]["board"]:
		if source.uid == ignoring_uid:
			continue
		for e in card_of(source).get("effects", []):
			if e.get("trigger", "") == "constante" and e.get("action", "") == doubler_action:
				return true
	return false

## 2 while the player has a "double_constants" unit (Contador Exagerado), else 1. It never stacks: two of them still give 2.
## Only the text Constantes (scale, species_aura, graveyard_armor, adjacent_armor) are multiplied; keywords like Armadura or Rapidez are not.
func constants_multiplier(p: int) -> int:
	return 2 if has_doubler(p, "double_constants") else 1

## What the "species_aura" effects of the OTHER allied units on the board give unit `c`:
## x = Ataque, y = Vida, z = Armadura. An aura only reaches units sharing one of its species
## (a card can list several, e.g. ["divindade", "celestial"]). The source's own aura does not reach itself
## unless the effect says "include_self": true (Mefi'Urdim).
func species_aura_bonus(c: Card) -> Vector3i:
	var bonus := Vector3i.ZERO
	var unit_species: Array = card_of(c).get("species", [])
	if unit_species.is_empty():
		return bonus
	for source: Card in players[c.owner]["board"]:
		for e in card_of(source).get("effects", []):
			if e.get("trigger", "") != "constante" or e.get("action", "") != "species_aura":
				continue
			if source == c and not bool(e.get("include_self", false)):
				continue
			for aura_species in e.get("species", []):
				if unit_species.has(aura_species):
					bonus += Vector3i(int(e.get("atk", 0)), int(e.get("hp", 0)), int(e.get("armor", 0)))
					break # one aura gives its bonus once, however many species match
	return bonus * constants_multiplier(c.owner)

## Armadura a unit gets from its own "graveyard_armor" effect: +1 per card of the given type and
## essence in its owner's graveyard (e.g. Sagrada spells for Nerithia).
func graveyard_armor_of(c: Card) -> int:
	var total := 0
	for e in card_of(c).get("effects", []):
		if e.get("trigger", "") != "constante" or e.get("action", "") != "graveyard_armor":
			continue
		for entry: Card in players[c.owner]["graveyard"]:
			var entry_data := CardDB.card(entry.card_id)
			if entry_data.get("type", "") == String(e.get("card_type", "spell")) and entry_data.get("essence", "") == String(e.get("essence", "")):
				total += 1
	return total * constants_multiplier(c.owner)

## Damage reduction from a graveyard threshold, or -1 when the card has no active one.
## This replaces Armadura for that hit, so it may reduce damage all the way to 0.
func graveyard_damage_reduction_of(c: Card, amount: int) -> int:
	for e in card_of(c).get("effects", []):
		if e.get("trigger", "") != "constante" or e.get("action", "") != "graveyard_damage_reduction":
			continue
		var count := 0
		for entry: Card in players[c.owner]["graveyard"]:
			var entry_data := CardDB.card(entry.card_id)
			if entry_data.get("type", "") == String(e.get("card_type", "spell")) and entry_data.get("essence", "") == String(e.get("essence", "")):
				count += 1
		if count < int(e.get("minimum_count", 2)):
			continue
		var divisor := maxi(1, int(e.get("divisor", 2)))
		return maxi(0, ceili(float(amount) / divisor) - int(e.get("flat_reduction", 0)))
	return -1

func _scale_count(p: int, e: Dictionary) -> int:
	match e.get("per", ""):
		"own_graveyard_units": return graveyard_units(p)
		"enemy_graveyard_units": return graveyard_units(opponent(p))
		"own_artifacts": return artifact_count(p)
	return 0

## Artifacts a player has in play: free-standing ones plus the equipment worn by their units.
func artifact_count(p: int) -> int:
	var n: int = players[p]["relics"].size()
	for c: Card in players[p]["board"]:
		if c.equipment != null:
			n += 1
	return n

## What a "scale" card counts right now (shown in its text off the board), or -1 if it has none.
func scale_count(p: int, cd: Dictionary) -> int:
	for e in cd.get("effects", []):
		if e.get("trigger", "") == "constante" and e.get("action", "") == "scale":
			return _scale_count(p, e)
	return -1

## The Encarnação left the board by dying or being banished (a return to hand doesn't count).
## If its next cast would cost more than the Momentum cap, it retires: it goes to the bottom of
## the deck as a normal card at its base cost, for good. Otherwise it goes back to the Santuário.
func _legendary_leaves(p: int) -> void:
	var l: Dictionary = players[p]["legendary"]
	if legendary_cost(p) <= MOMENTUM_CAP:
		l["in_zone"] = true
		return
	l["retired"] = true
	players[p]["deck"].insert(0, Card.new(_uid(), l["card_id"], p, "deck")) # draws pop the back
	_emit({"type": "legendary_retired", "player": p, "card_id": l["card_id"]})

func legendary_cost(p: int) -> int:
	var l: Dictionary = players[p]["legendary"]
	return cost_of(p, CardDB.card(l["card_id"])) + commander_tax(int(l["casts"]))

## Extra cost of the Encarnação after `casts` previous casts: 1 + 2 + ... + casts, times COMMANDER_TAX_STEP.
static func commander_tax(casts: int) -> int:
	return COMMANDER_TAX_STEP * casts * (casts + 1) / 2

## Congelada: no attack, no untap, no guarding the Leader until the end of the next turn.
func is_frozen(c: Card) -> bool:
	return c.is_frozen()

## The unit is ready to attack: not tapped, not Congelada, not summoning sick (unless Ímpeto or
## Rompante). A unit with 0 ATK may attack too: it deals no damage, but the attack animation plays
## and the defender still strikes back (Morakhan can use it to hurt himself).
func can_attack(c: Card) -> bool:
	# a tapped unit may attack again only while it still has attacks left (Ataque Duplo)
	var has_attack_left := not c.exhausted or (c.attacks_made > 0 and c.attacks_made < attacks_allowed(c))
	return has_attack_left and not has_kw(c, "inerte") and not c.is_frozen() and not c.is_stunned() and (not c.sick or has_kw(c, "impeto") or has_kw(c, "rompante"))

## Attacks per turn: 2 with Ataque Duplo, which a card can also earn by reaching Crítico 4
## ("critico_maximo": {"ataque_duplo": true}, Vael); otherwise 1.
func attacks_allowed(c: Card) -> int:
	if has_kw(c, "ataque_duplo"):
		return 2
	if c.critico_total() >= 4 and c.data().get("critico_maximo", {}).get("ataque_duplo", false):
		return 2
	return 1

## Can `attacker` challenge `target` (an exhausted or Vulnerable enemy unit within reach)? See CombatSystem.
func can_challenge(attacker: Card, target: Card) -> bool:
	return combat_system().can_challenge(attacker, target)

## Every uid `attacker` may hit right now (challengeable units and/or the enemy Leader's negative uid).
func attack_targets(attacker: Card) -> Array:
	return combat_system().attack_targets(attacker)

## Effect spec of a card/ability that needs a chosen target, or "" if none.
func target_spec(effects: Array) -> String:
	for e in effects:
		if e.get("target", "") in ["enemy_unit", "enemy_flying_unit", "enemy_taunt_unit", "weak_enemy_unit", "ally_unit", "other_ally_unit", "ally_or_own_leader", "any_unit", "any", "enemy_stack", "enemy_artifact"]:
			return e["target"]
	return ""

## Second target a card needs on top of its first (e.g. the damage target after the sacrifice), or "".
## Declared on a "then" effect with "pick": true, or on a top-level effect with "pick2": true
## (Relâmpagos Gêmeos; "same_target_ok" on the card lets both picks be the same target).
## A "fight" effect names its second unit with "second_target" instead.
func second_spec(cd: Dictionary) -> String:
	if cd["type"] == "unit":
		return "" # a unit's Ao Entrar picks its targets after it enters (see enter_second_spec)
	for e in cd.get("effects", []):
		if e.get("pick2", false):
			return e["target"]
		if e.has("second_target"):
			return e["second_target"]
		for t in e.get("then", []):
			if t.get("pick", false):
				return t["target"]
	return ""

## True when a spell would do nothing right now (only revive effects, and no unit to bring back).
func is_dud(p: int, cd: Dictionary) -> bool:
	var effects: Array = cd.get("effects", [])
	if effects.is_empty():
		return false
	for e in effects:
		if e.get("action") != "revive":
			return false
		if has_free_slot(p):
			for grave: Card in players[p]["graveyard"]:
				var gd := CardDB.card(grave.card_id)
				if gd["type"] == "unit" and int(gd["cost"]) <= int(e.get("max_cost", 99)):
					return false
	return true

## Target a card needs when played: its additional sacrifice cost (the unit to sacrifice)
## or the chosen target of its effects. A unit's Ao Entrar target is picked after it enters
## (see enter_spec), so it is not part of playing it.
func card_spec(cd: Dictionary) -> String:
	if cd.get("cost_sacrifice", false):
		return "ally_unit"
	return "" if cd["type"] == "unit" else target_spec(cd["effects"])

## Target spec of a unit's Ao Entrar, or "".
func enter_spec(cd: Dictionary) -> String:
	var on_enter: Array = []
	for e in cd.get("effects", []):
		if e.get("trigger", "") == "on_enter":
			on_enter.append(e)
	return target_spec(on_enter)

## Target spec of the second pick of a unit's Ao Entrar (an on_enter effect with "pick2": true), or "".
## It is asked after the first pick; "same_target_ok" on the card lets both picks be the same target.
func enter_second_spec(cd: Dictionary) -> String:
	for e in cd.get("effects", []):
		if e.get("trigger", "") == "on_enter" and e.get("pick2", false):
			return e["target"]
	return ""

## Momentum cost of a card for player p, after its cost_reduction effects (no trigger: they apply
## wherever the card is, not only on the board, so they are not "Constante")
## (e.g. per: "saved_momentum" =
## per Momentum that leaked past the Reserva by the start of the owner's turns, over the whole game; "idle_turns" =
## per owner turn that started with Momentum leaking past the Reserva; "unspent_momentum" = a flat "amount" off when
## at least "threshold" plain Momentum was left over from the previous turn). Never below 0, or below the effect's "min_cost".
func cost_of(p: int, cd: Dictionary, card: Card = null) -> int:
	var c := int(cd["cost"]) - (card.discount if card != null else 0) # per-copy discount (Tecnomante); stacks with cost_reduction, same "min_cost" floor
	if card != null:
		c += card.cost_mod # permanent per-copy change (modify_cost), kept in every zone
	var floor_cost := 0
	for e in cd.get("effects", []):
		if e.get("action", "") != "cost_reduction":
			continue
		var n := 0
		match e.get("per", ""):
			"saved_momentum": n = int(players[p]["saved_momentum"])
			"idle_turns": n = int(players[p]["idle_turns"])
			"unspent_momentum": n = 1 if int(players[p]["unspent"]) >= int(e.get("threshold", 1)) else 0
		c -= n * int(e.get("amount", 1))
		floor_cost = maxi(floor_cost, int(e.get("min_cost", 0)))
	var amulet_discount := glacial_discount(p, cd)
	if amulet_discount > 0:
		# the amulets' own "min_cost" floor never raises a spell that was already cheaper than it
		floor_cost = maxi(floor_cost, mini(glacial_discount_floor(p, cd), c))
	c -= amulet_discount
	var requiem_extra := REQUIEM_EXTRA_COST if card != null and card.zone == "graveyard" else 0
	return maxi(c, floor_cost) + requiem_extra

## Sets the Bola de Neve level of player p. When the level crosses into Grande (from below
## SNOWBALL_GRANDE_AT to at or above it) every Bola de Neve card of p evolves into a Grande Bola de Neve,
## and listeners hear "snowball_grande" once (Princesa Wanessa becomes Tempesfrost even if the Grande
## level came from a card and not from a cast).
func set_snowball_level(p: int, new_level: int) -> void:
	var old_level: int = int(players[p]["snowball"])
	players[p]["snowball"] = new_level
	if old_level < SNOWBALL_GRANDE_AT and new_level >= SNOWBALL_GRANDE_AT:
		_evolve_snowball_cards(p)
		var crossing := GameEvent.new("snowball_grande", p, null)
		crossing.amount = new_level
		bus().emit(crossing)

## End of p's own turn: the Bola de Neve level goes back to the player's base level, so a combo has to happen inside a single turn.
## If it was Grande, every Grande Bola de Neve card of p turns back into a normal Bola de Neve.
func reset_snowball_level(p: int) -> void:
	var was_grande := snowball_is_grande(p)
	var base_level: int = int(players[p]["snowball_base"])
	var level_before: int = int(players[p]["snowball"])
	players[p]["snowball"] = base_level
	if was_grande:
		_devolve_snowball_cards(p)
	if level_before != base_level: # decks with no Bola de Neve never move the level, so there is nothing to announce
		_emit({"type": "snowball_reset", "player": p, "level": base_level})

func snowball_is_grande(p: int) -> bool:
	return int(players[p]["snowball"]) >= SNOWBALL_GRANDE_AT

## Turns every Bola de Neve card of player p (hand, deck, graveyard and the stack) into a Grande Bola de
## Neve. The card keeps its uid, its discount and its cost changes: only the card it is changes.
func _evolve_snowball_cards(p: int) -> void:
	var evolved := 0
	var evolved_uids: Array = [] # lets the UI play the transformation on the cards that are visible (the hand)
	for zone_name in ["hand", "deck", "graveyard"]:
		for c: Card in players[p][zone_name]:
			if c.card_id == SNOWBALL_CARD_ID:
				c.card_id = GRANDE_SNOWBALL_CARD_ID
				evolved += 1
				evolved_uids.append(c.uid)
	for item in stack:
		if int(item["player"]) == p and item["kind"] == "card" and item["card_id"] == SNOWBALL_CARD_ID:
			item["card_id"] = GRANDE_SNOWBALL_CARD_ID
			evolved += 1
	if evolved > 0:
		_emit({"type": "snowball_evolve", "player": p, "count": evolved, "uids": evolved_uids})

## The reverse of _evolve_snowball_cards: every Grande Bola de Neve card of player p goes back to being a Bola de Neve.
func _devolve_snowball_cards(p: int) -> void:
	var reverted := 0
	var reverted_uids: Array = []
	for zone_name in ["hand", "deck", "graveyard"]:
		for c: Card in players[p][zone_name]:
			if c.card_id == GRANDE_SNOWBALL_CARD_ID:
				c.card_id = SNOWBALL_CARD_ID
				reverted += 1
				reverted_uids.append(c.uid)
	for item in stack:
		if int(item["player"]) == p and item["kind"] == "card" and item["card_id"] == GRANDE_SNOWBALL_CARD_ID:
			item["card_id"] = SNOWBALL_CARD_ID
			reverted += 1
	if reverted > 0:
		_emit({"type": "snowball_devolve", "player": p, "count": reverted, "uids": reverted_uids})

## Momentum off the first spell of an essence each turn, from the equipped "spell_discount" artifacts
## (Amuleto do Primeiro Floco) on p's units. The discounts of several amulets add up.
## 0 when there is none, it is not that essence, or it was spent.
func glacial_discount(p: int, cd: Dictionary) -> int:
	var total := 0
	for rule in _applicable_discount_rules(p, cd):
		total += int(rule["amount"])
	return total

## The cost the amulets' discount cannot push the spell under: the highest "min_cost" among the amulets that apply.
func glacial_discount_floor(p: int, cd: Dictionary) -> int:
	var floor_cost := 0
	for rule in _applicable_discount_rules(p, cd):
		floor_cost = maxi(floor_cost, int(rule.get("min_cost", 0)))
	return floor_cost

func _applicable_discount_rules(p: int, cd: Dictionary) -> Array:
	var rules: Array = []
	if cd.get("type", "") != "spell" or players[p]["glacial_discount_used"]:
		return rules
	for unit: Card in players[p]["board"]:
		if unit.equipment == null:
			continue
		var rule: Dictionary = unit.equipment.data().get("spell_discount", {})
		if not rule.is_empty() and CardDB.has_essence(cd, String(rule["essence"])):
			rules.append(rule)
	return rules

## Momentum p can spend on a play: the Reserva only counts for spells and leader abilities.
## Momentum above MOMENTUM_CAP (a temporary overflow) only pays neutral cards and leader abilities:
## pass the card's data as `cd` so any other essence sees at most MOMENTUM_CAP.
func budget(p: int, spell: bool, cd := {}) -> int:
	var plain_momentum := int(players[p]["momentum"])
	if not cd.is_empty() and not CardDB.has_essence(cd, "neutra"):
		plain_momentum = mini(plain_momentum, MOMENTUM_CAP)
	return plain_momentum + (int(players[p]["reserve"]) if spell else 0)

## Gives player p Momentum right now. Normally it stops at MOMENTUM_CAP; with `overflow` it may go up
## to MOMENTUM_OVERFLOW_CAP. It never lowers Momentum the player already has above the cap.
func gain_momentum(p: int, gain: int, overflow := false) -> void:
	var pl: Dictionary = players[p]
	var current := int(pl["momentum"])
	var ceiling := MOMENTUM_OVERFLOW_CAP if overflow else MOMENTUM_CAP
	pl["momentum"] = maxi(current, mini(ceiling, current + gain))
	_refresh_scaling() # a surge (11+ Momentum) may have just turned on
	_emit({"type": "momentum", "player": p})

## Pays `amount`; spells and abilities drain the Reserva first so more plain Momentum is
## left over to bank next turn.
func _pay(p: int, amount: int, spell: bool) -> void:
	var pl: Dictionary = players[p]
	if spell:
		var r := mini(amount, int(pl["reserve"]))
		pl["reserve"] -= r
		amount -= r
	pl["momentum"] -= amount
	_refresh_scaling() # a surge (11+ Momentum) may have just turned off

static func _is_spell(cd: Dictionary) -> bool:
	return cd.get("type", "") == "spell"

## include_unreachable: also lists the enemy units with Inalcançável (only to explain why a target is refused).
## effects: the effect dictionaries about to be aimed at the pick. A target that cannot satisfy one of their
## "requires_markers" (Ponto Final Sem Vírgula needs 3+ Veneno) is not offered: the effect would do nothing.
func valid_targets(p: int, spec: String, self_uid: int = 0, include_unreachable := false, effects: Array = []) -> Array:
	var out: Array = []
	var mine: Array = players[p]["board"]
	# Inalcançável: enemy units with it can't be picked as a target by this player
	# (effects that don't aim, like area or random ones, still reach them)
	var theirs: Array = []
	for enemy_unit: Card in players[opponent(p)]["board"]:
		if include_unreachable or not has_kw(enemy_unit, "inalcancavel"):
			theirs.append(enemy_unit)
	match spec:
		"enemy_unit":
			for c: Card in theirs: out.append(c.uid)
		"enemy_flying_unit": # an enemy unit with Voo (Estilingueiro Teimoso)
			for c: Card in theirs:
				if c.has_kw("voo"): out.append(c.uid)
		"enemy_taunt_unit": # an enemy unit with Provocação (Saltador de Cerca)
			for c: Card in theirs:
				if c.has_kw("provocacao"): out.append(c.uid)
		"weak_enemy_unit": # an enemy unit whose current Vida is WEAK_UNIT_MAX_HP or less (Isarelis' execution)
			for c: Card in theirs:
				if c.hp_left() <= WEAK_UNIT_MAX_HP: out.append(c.uid)
		"ally_unit":
			for c: Card in mine: out.append(c.uid)
		"other_ally_unit":
			for c: Card in mine:
				if c.uid != self_uid: out.append(c.uid)
		"ally_or_own_leader": # an ally unit or your own Leader (healing like Maré Curativa)
			for c: Card in mine: out.append(c.uid)
			out.append(LEADER_UID[p])
		"any_unit":
			for c: Card in mine + theirs: out.append(c.uid)
		"any":
			for c: Card in mine + theirs: out.append(c.uid)
			out.append(LEADER_UID[opponent(p)])
		"enemy_artifact": # a free-standing artifact on the opponent's side
			for c: Card in players[opponent(p)]["relics"]: out.append(c.uid)
		"enemy_stack":
			for it in stack:
				if it["player"] != p and not stack_system().is_uncounterable(it): out.append(it["sid"])
	if not effects.is_empty():
		out = out.filter(func(target_uid: int) -> bool: return meets_marker_requirement(target_uid, spec, effects))
	return out

## False when an effect aimed with `spec` only works on a target holding enough markers ("requires_markers":
## the banish of Ponto Final Sem Vírgula, the execution of Viprax) and this target does not have them.
## A Leader target uid is negative. Effects aimed at another spec are not about this pick and are ignored.
func meets_marker_requirement(target_uid: int, spec: String, effects: Array) -> bool:
	for effect in effects:
		var requirement: Dictionary = effect.get("requires_markers", {})
		if requirement.is_empty() or effect.get("target", "") != spec:
			continue
		var dot_id := String(requirement.get("dot", ""))
		var needed := int(requirement.get("amount", 0))
		var held := 0
		if target_uid < 0:
			held = leader_dot_markers(LEADER_UID.find(target_uid), dot_id)
		else:
			var unit := find_unit(target_uid)
			held = int(unit.dot_markers.get(dot_id, 0)) if unit != null else 0
		if held < needed:
			return false
	return true

## True when the only thing stopping an aimed effect is Inalcançável: there would be a target without it.
## The screen keeps such an action enabled and explains the refusal when the player aims at the unit.
func targets_blocked_by_reach(p: int, spec: String, self_uid: int = 0) -> bool:
	return spec != "" and spec != "enemy_stack" and valid_targets(p, spec, self_uid).is_empty() 		and not valid_targets(p, spec, self_uid, true).is_empty()

## Targets a card from hand can be played on right now (counters filter by reach and Momentum).
func card_targets(p: int, cd: Dictionary, inst: Card = null) -> Array:
	var spec := card_spec(cd)
	var out := valid_targets(p, spec, 0, false, cd.get("effects", []))
	if spec != "enemy_stack":
		return out
	var ok: Array = []
	for sid in out:
		var x := counter_extra(cd, sid)
		if x >= 0 and cost_of(p, cd, inst) + x <= budget(p, _is_spell(cd), cd):
			ok.append(sid)
	return ok

## Speed of a card or leader ability: "lento" (default), "rapido" or "instantaneo".
func speed_of(src: Dictionary) -> String:
	if src.has("speed"):
		return String(src["speed"])
	if (src.get("keywords", []) as Array).has("saque_rapido") or (src.get("tags", []) as Array).has("saque_rapido"):
		return "rapido"
	return "lento"

## Lento: own Main Phase with an empty stack. Rápido: also the pre-combat window (both players)
## and the summon response window. Instantâneo: also as a response to anything on the stack, and in the attacks
## window with an empty stack: for the attacker between two attacks, and for the defender while they hold
## priority to react to a declared attack. Only the priority holder passes the first check above.
func can_cast_speed(p: int, speed: String) -> bool:
	if phase not in ["main", "combat"] or p != priority:
		return false
	if not stack.is_empty():
		return speed == "instantaneo"
	if phase == "main":
		return p == active or (summon_window and speed != "lento")
	if window == "attacks":
		return speed == "instantaneo"
	return window == "pre_combat" and speed != "lento"

## Units, the Legendary and ending the turn: own Main Phase, empty stack.
func _sorcery_time(p: int) -> bool:
	return _main_phase_idle(p)

## Own Main Phase, empty stack, nothing pending.
func _main_phase_idle(p: int) -> bool:
	return phase == "main" and p == active and priority == p and stack.is_empty() and not summon_window

## True when p still has a legal attack this turn (so "IR PARA O COMBATE" is worth offering).
func can_go_to_combat(p: int) -> bool:
	if not _sorcery_time(p) or players[p]["attacked"]:
		return false
	for unit: Card in players[p]["board"]:
		if can_attack(unit):
			return true
	return false

## Ends the first Main Phase and opens the pre-combat window (attacker first, then defender).
func go_to_combat(p: int) -> Array:
	if not can_go_to_combat(p):
		return []
	combat_system().start_combat(p)
	stack_system().settle()
	return _flush()

## One attack during the "attacks" window: `attacker_uid` taps and hits `target_uid`
## (the enemy Leader's negative uid, or an enemy unit it can challenge). Resolves at once.
func attack_unit(p: int, attacker_uid: int, target_uid: int) -> Array:
	return combat_system().attack(p, attacker_uid, target_uid)

## "ENCERRAR COMBATE": the attacker stops attacking and goes to the second Main Phase.
func end_combat(p: int) -> Array:
	if not combat_system().in_attacks_window(p):
		return []
	combat_system().end_combat()
	stack_system().settle()
	return _flush()

## Leaves combat without attacking: no more attacks this turn (second Main Phase).
## Works from the Main Phase (skipping combat entirely) or from the attacks window.
func skip_combat(p: int) -> Array:
	if combat_system().in_attacks_window(p):
		return end_combat(p)
	if not _main_phase_idle(p) or players[p]["attacked"]:
		return []
	players[p]["attacked"] = true
	_emit({"type": "combat_skipped", "player": p})
	return _flush()

## Súbito (cards.json unit field "subito": its Súbito cost, e.g. 5 = "Súbito (5)"): outside your own
## idle Main Phase, the unit can still be summoned in any window where a Rápido spell could be cast,
## by paying its Súbito cost. That summon is an ability, not a play: it goes on the stack (Rápido),
## so the opponent can respond to it and counter it. In your own idle Main Phase it is played normally.
func is_subito_play(p: int, cd: Dictionary) -> bool:
	return cd.get("type", "") == "unit" and cd.has("subito") and not _sorcery_time(p) and can_cast_speed(p, "rapido")

## The Súbito cost for this copy: the normal cost (with its discounts) plus the Súbito premium.
func subito_cost(p: int, cd: Dictionary, card: Card = null) -> int:
	var premium := int(cd["subito"]) - int(cd["cost"])
	return cost_of(p, cd, card) + premium

## allow_unreachable: true for the screen (see targets_blocked_by_reach); the AI and the actions stay strict.
func can_play(p: int, hand_uid: int, allow_unreachable := false) -> bool:
	var inst := _castable_card(p, hand_uid)
	if inst == null:
		return false
	var cd := CardDB.card(inst.card_id)
	if is_play_restricted(p, cd):
		return false
	if is_subito_play(p, cd):
		# paid like an ability, so the Reserva counts
		return inst.zone == "hand" and has_free_slot(p) and not cd.get("cost_sacrifice", false) \
			and subito_cost(p, cd, inst) <= budget(p, true, cd)
	if cost_of(p, cd, inst) > budget(p, _is_spell(cd), cd):
		return false
	if cd["type"] == "unit":
		if not _sorcery_time(p):
			return false
		if cd.get("cost_sacrifice", false):
			return not players[p]["board"].is_empty() # the sacrifice also frees the slot
		return has_free_slot(p)
	if CardDB.is_relic(cd):
		return _sorcery_time(p) and has_free_slot(p) # put on the field like a unit, but through the stack
	if not can_cast_speed(p, speed_of(cd)):
		return false
	var spec := target_spec(cd["effects"])
	return spec == "" or not card_targets(p, cd, inst).is_empty() or (allow_unreachable and targets_blocked_by_reach(p, spec))

## Starts a play restriction on p (see PlayRestriction for the rule format). It lasts `turns` turns
## counting the current one (`turn` goes up at every player's turn start, so no cleanup is needed).
func add_play_restriction(p: int, rule: Dictionary) -> void:
	var still_active: Array = []
	for existing in players[p]["play_restrictions"]:
		if int(existing["until_turn"]) >= turn:
			still_active.append(existing) # drop the ones that already ended
	still_active.append({"rule": rule, "until_turn": turn + int(rule.get("turns", 1)) - 1})
	players[p]["play_restrictions"] = still_active

## True when an active restriction of p bars this card (its data `cd`). It covers every way of
## playing a card: hand, Réquiem from the graveyard, Súbito and the Encarnação.
func is_play_restricted(p: int, cd: Dictionary) -> bool:
	for restriction in players[p]["play_restrictions"]:
		if int(restriction["until_turn"]) >= turn and PlayRestriction.blocks(restriction["rule"], cd):
			return true
	return false

func can_cast_legendary(p: int) -> bool:
	if is_play_restricted(p, CardDB.card(players[p]["legendary"]["card_id"])):
		return false
	return _sorcery_time(p) and players[p]["legendary"]["in_zone"] \
		and legendary_cost(p) <= players[p]["momentum"] and has_free_slot(p)

func can_use_ability(p: int, allow_unreachable := false) -> bool:
	var ab: Dictionary = CardDB.leader(players[p]["leader_id"])["ability"]
	if ab.get("passive", false):
		return false # passives fire on their own trigger
	if not can_cast_speed(p, speed_of(ab)) or int(ab["cost"]) > budget(p, true):
		return false
	if (ab.get("once_per_turn", false) or ab.get("once_per_cycle", false)) and players[p]["ability_used"]:
		return false
	if ab.get("blocked_after_debt", false) and players[p].get("paid_debt_this_turn", false):
		return false # the loan was just repaid this turn: no borrowing again right away
	for effect in EffectRegistry.parse_list(ab["effects"]):
		if effect is PutArtifactEffect and not effect.can_put(self, p):
			return false # the artifact is already out (or there is no free slot): the ability would do nothing
	var spec := target_spec(ab["effects"])
	return spec == "" or not valid_targets(p, spec, 0, false, ab["effects"]).is_empty() or (allow_unreachable and targets_blocked_by_reach(p, spec))

## Unit Ao Ativar (cards.json unit field "activated": {cost, speed, effects, once_per_turn, exhaust}):
## paid like an ability (Reserva counts) and put on the stack, so it can be answered and countered.
## "exhaust": the unit must be ready (not exhausted) and becomes exhausted, so it cannot attack
## that turn (and an attacker cannot activate). Being exhausted also means the opponent may challenge it.
func can_activate(p: int, uid: int, allow_unreachable := false) -> bool:
	var c := _activatable_card(uid)
	if c == null or c.owner != p:
		return false
	var ab: Dictionary = card_of(c).get("activated", {})
	if ab.is_empty() or not can_cast_speed(p, speed_of(ab)) or int(ab["cost"]) > budget(p, true):
		return false
	if ab.get("exhaust", false) and c.has_kw("inerte"):
		return false # an inert unit cannot turn to activate an ability
	if ab.get("once_per_turn", false) and c.activated_turn == turn:
		return false
	if _has_action(ab["effects"], "arm_death_ward") and c.death_ward_armed:
		return false # rearming an already active death shield would only waste Momentum
	if ab.get("exhaust", false) and c.exhausted:
		return false
	if _has_action(ab["effects"], "revive_pick") and (not has_free_slot(p) or revive_options(p).is_empty()):
		return false # nothing to bring back, or no slot for it
	for fusion in ab["effects"]:
		if fusion.get("action", "") == "fuse" and EffectRegistry.parse(fusion).available_parts(self, p) == 0:
			return false # not enough units to fuse
	var spec := target_spec(ab["effects"])
	return spec == "" or not valid_targets(p, spec, uid, false, ab["effects"]).is_empty() or (allow_unreachable and targets_blocked_by_reach(p, spec, uid))

## The card whose Ao Ativar can be used: a unit on the board or a free-standing artifact.
func _activatable_card(uid: int) -> Card:
	var unit := find_unit(uid)
	return unit if unit != null else find_relic(uid)

## True if one of these effect dictionaries has this action.
func _has_action(effects: Array, action_name: String) -> bool:
	for e in effects:
		if e.get("action", "") == action_name:
			return true
	return false

## Transformar (cards.json unit field "transform": {into, cost}) (cards.json unit field {into, cost}): Lento, paid like an ability
## (Reserva counts), and it never uses the stack, so it cannot be answered or countered.
func can_transform(p: int, uid: int) -> bool:
	var c := find_unit(uid)
	if c == null or c.owner != p or not _sorcery_time(p):
		return false
	var tf: Dictionary = card_of(c).get("transform", {})
	return not tf.is_empty() and int(tf["cost"]) <= budget(p, true)

func _hand_card(p: int, uid: int) -> Card:
	for c: Card in players[p]["hand"]:
		if c.uid == uid:
			return c
	return null

## True for a spell with Réquiem (it can be cast from the graveyard).
func is_requiem(c: Card) -> bool:
	var cd := CardDB.card(c.card_id)
	return cd["type"] == "spell" and (cd.get("keywords", []) as Array).has("requiem")

## The card a play action with this uid refers to: from the hand, or a Réquiem spell in the graveyard.
func _castable_card(p: int, uid: int) -> Card:
	var from_hand := _hand_card(p, uid)
	if from_hand != null:
		return from_hand
	for c: Card in players[p]["graveyard"]:
		if c.uid == uid and is_requiem(c):
			return c
	return null

## Réquiem spells in p's graveyard that p could cast right now, newest first.
func requiem_cards(p: int) -> Array:
	var out: Array = []
	for c: Card in players[p]["graveyard"]:
		if is_requiem(c) and can_play(p, c.uid):
			out.append(c)
	out.reverse()
	return out

## Banishes a Réquiem spell once its cast is over (resolved, fizzled or countered).
func _banish_requiem(c: Card) -> void:
	players[c.owner]["banished"].append(c)
	_move(c, "banished")
	_emit({"type": "banish", "uid": c.uid, "player": c.owner, "card_id": c.card_id})

# ---------------------------------------------------------------- actions

## Put back up to MULLIGAN_MAX cards and redraw that many.
func mulligan(p: int, hand_uids: Array) -> Array:
	if phase != "mulligan" or p != decider() or hand_uids.size() > MULLIGAN_MAX:
		return []
	var pl: Dictionary = players[p]
	var back: Array = []
	for uid in hand_uids:
		var c := _hand_card(p, uid)
		if c == null:
			return []
		back.append(c)
	for c: Card in back:
		pl["hand"].erase(c)
		pl["deck"].append(c)
		_move(c, "deck")
	_shuffle(pl["deck"])
	_draw(p, back.size())
	pl["mulligan_done"] = true
	_emit({"type": "mulligan", "player": p, "count": back.size()})
	if players[0]["mulligan_done"] and players[1]["mulligan_done"]:
		_start_turn(first, false)
	return _flush()

## slot: where a unit enters the board (0 = leftmost, -1 = rightmost); ignored for spells.
func play_card(p: int, hand_uid: int, target: int = 0, target2: int = 0, slot: int = -1) -> Array:
	if not can_play(p, hand_uid):
		return []
	var inst := _castable_card(p, hand_uid)
	var from_graveyard := inst.zone == "graveyard" # Réquiem
	var cd := CardDB.card(inst.card_id)
	if is_subito_play(p, cd):
		return _play_subito(p, inst, cd, slot)
	var sacrifice: bool = cd["type"] == "unit" and cd.get("cost_sacrifice", false)
	var spec := target_spec(cd["effects"])
	if sacrifice:
		if not valid_targets(p, "ally_unit").has(target):
			return []
	elif cd["type"] != "unit" and spec != "" and not card_targets(p, cd, inst).has(target):
		return []
	var spec2 := second_spec(cd)
	if spec2 != "" and ((target2 == target and not cd.get("same_target_ok", false)) or not valid_targets(p, spec2).has(target2)):
		return []
	var pl: Dictionary = players[p]
	var spent_glacial_discount := glacial_discount(p, cd) > 0 # read before paying: the discount is for the first spell only
	_pay(p, cost_of(p, cd, inst) + (counter_extra(cd, target) if spec == "enemy_stack" else 0), _is_spell(cd))
	if spent_glacial_discount:
		pl["glacial_discount_used"] = true
	pl["graveyard" if from_graveyard else "hand"].erase(inst)
	if int(cd.get("cost", 0)) == 2 or int(cd.get("atk", 0)) == 2 or int(cd.get("hp", 0)) == 2:
		pl["played_two"] = true # Rusco: a card with cost, ATK or HP exactly 2 this turn
	_move(inst, "")
	var play_event := {"type": "play", "player": p, "uid": hand_uid, "card_id": inst.card_id}
	if target != 0:
		play_event["target"] = target
	if target2 != 0:
		play_event["target2"] = target2
	if from_graveyard:
		play_event["requiem"] = true
	_emit(play_event)
	if sacrifice:
		# additional cost: the chosen ally dies first (its Ao Morrer / Aliado Morre resolve before the card enters)
		var sacrificed_index: int = pl["board"].find(find_unit(target))
		if sacrificed_index >= 0 and sacrificed_index < slot:
			slot -= 1 # the slot was picked with the sacrificed unit still on the board
		find_unit(target).damage = 1000000
		_emit({"type": "sacrifice", "player": p, "uid": target})
		_check_state()
		if phase == "over":
			return _flush()
		if not has_free_slot(p): # a death effect refilled the slot
			pl["graveyard"].append(inst)
			_move(inst, "graveyard")
			stack_system().settle()
			return _flush()
	if cd["type"] == "unit":
		_summon(p, inst, false, 0, {}, true, slot, true)
		_check_state()
		stack_system().open_summon_window(p)
	else:
		_stack_cards[hand_uid] = inst
		_move(inst, "stack")
		if cd["type"] == "spell":
			_announce_spell_cast(p, inst, cd)
		stack_system().push(p, "card", hand_uid, inst.card_id, target, speed_of(cd), target2, from_graveyard)
	stack_system().settle()
	return _flush()

## Súbito: pays the Súbito cost and puts the summon on the stack as a Rápido ability. The unit
## enters (at `slot`) only when that item resolves; if it is countered, the card goes to the graveyard.
func _play_subito(p: int, inst: Card, cd: Dictionary, slot: int) -> Array:
	_pay(p, subito_cost(p, cd, inst), true)
	players[p]["hand"].erase(inst)
	if int(cd.get("cost", 0)) == 2 or int(cd.get("atk", 0)) == 2 or int(cd.get("hp", 0)) == 2:
		players[p]["played_two"] = true # Rusco counts it too
	_move(inst, "")
	_emit({"type": "play", "player": p, "uid": inst.uid, "card_id": inst.card_id, "subito": true})
	_stack_cards[inst.uid] = inst
	_move(inst, "stack")
	stack_system().push(p, "subito", inst.uid, inst.card_id, 0, "rapido")
	stack[-1]["slot"] = slot
	stack_system().settle()
	return _flush()

func cast_legendary(p: int, _target: int = 0, slot: int = -1) -> Array:
	if not can_cast_legendary(p):
		return []
	var pl: Dictionary = players[p]
	pl["momentum"] -= legendary_cost(p)
	pl["legendary"]["in_zone"] = false
	pl["legendary"]["casts"] += 1
	var c := Card.new(_uid(), pl["legendary"]["card_id"], p)
	_emit({"type": "play", "player": p, "uid": c.uid, "card_id": c.card_id, "legendary": true})
	_summon(p, c, true, 0, {}, true, slot, true)
	_check_state()
	stack_system().open_summon_window(p)
	stack_system().settle()
	return _flush()

func activate(p: int, uid: int, target: int = 0) -> Array:
	if not can_activate(p, uid):
		return []
	var c := _activatable_card(uid)
	var ab: Dictionary = card_of(c)["activated"]
	var spec := target_spec(ab["effects"])
	if spec != "" and not valid_targets(p, spec, uid, false, ab["effects"]).has(target):
		return []
	_pay(p, int(ab["cost"]), true)
	c.activated_turn = turn
	if ab.get("exhaust", false) and not c.has_kw("inerte"):
		c.exhausted = true
	_emit({"type": "trigger", "uid": uid, "player": p, "card_id": c.card_id, "trigger": "on_activate", "target": target})
	stack_system().push(p, "unit_ability", uid, c.card_id, target, speed_of(ab))
	stack_system().settle()
	return _flush()

func use_ability(p: int, target: int = 0) -> Array:
	if not can_use_ability(p):
		return []
	var ab: Dictionary = CardDB.leader(players[p]["leader_id"])["ability"]
	var spec := target_spec(ab["effects"])
	if spec != "" and not valid_targets(p, spec, 0, false, ab["effects"]).has(target):
		return []
	_pay(p, int(ab["cost"]), true)
	players[p]["ability_used"] = true
	_emit({"type": "ability", "player": p, "target": target})
	stack_system().push(p, "ability", 0, "", target, speed_of(ab))
	stack_system().settle()
	return _flush()

## Transformar (paid): the unit becomes its "transform" card, then the usual checks run.
func transform(p: int, uid: int) -> Array:
	if not can_transform(p, uid):
		return []
	var c := find_unit(uid)
	var tf: Dictionary = card_of(c)["transform"]
	_pay(p, int(tf["cost"]), true)
	_emit({"type": "trigger", "uid": uid, "player": p, "card_id": c.card_id, "trigger": "transform"})
	transform_into(c, tf["into"])
	_check_state()
	stack_system().settle()
	return _flush()

## The unit becomes card `into_id` in place (same uid, keeps damage, exhaustion and equipment; base
## stats and keywords come from the new card), then its Ao Entrar fires. Used by the paid
## Transformar and by the "transform_self" effect.
func transform_into(c: Card, into_id: String) -> void:
	var uid := c.uid
	var p := c.owner
	var from: String = c.card_id
	var cd := CardDB.card(into_id)
	var kws: Array = cd.get("keywords", []).duplicate()
	c.card_id = into_id
	c.over = {}
	c.used_turn = {}
	c.atk = int(cd["atk"])
	c.hp = int(cd["hp"])
	c.shield = c.shield or kws.has("escudo")
	c.spell_shield = c.spell_shield or kws.has("escudo_feitico")
	if kws.has("escudo_supremo"):
		c.grant_supreme_shield()
	kws.erase("escudo")
	kws.erase("escudo_feitico")
	kws.erase("escudo_supremo")
	c.keywords = kws
	if not c.equipment_grant.is_empty(): # the equipment stays on, so what it gave the unit stays too
		c.atk += int(c.equipment_grant.get("atk", 0))
		c.hp += int(c.equipment_grant.get("hp", 0))
		for keyword in c.equipment_grant.get("keywords", []):
			if not c.keywords.has(keyword):
				c.keywords.append(keyword)
	c.sick = false # a transformed unit is not summoning sick: it can act right away
	_emit({"type": "transform", "player": p, "uid": uid, "from": from, "card_id": into_id})
	_announce(c, cd["effects"], "on_enter")
	var target := uid if target_spec(cd["effects"]) == "ally_unit" else 0
	run_enter_effects(_enter_context(p, uid, target), cd["effects"])

## Exiles a unit from the board: it never dies (no Ao Morrer) and never reaches the graveyard;
## its equipment does. A banished ficha just vanishes. A banished Encarnação goes back to the
## Santuário (or retires) exactly as if it had died, so a single banish never costs a deck its Encarnação.
func banish_unit(exiled: Card) -> void:
	var owner_player: int = exiled.owner
	players[owner_player]["board"].erase(exiled)
	_release_equipment(exiled)
	if exiled.legendary:
		_move(exiled, "")
		_legendary_leaves(owner_player)
	elif exiled.data().get("token", false):
		_move(exiled, "")
	else:
		players[owner_player]["banished"].append(exiled)
		_move(exiled, "banished")
	_emit({"type": "banish", "uid": exiled.uid, "player": owner_player, "card_id": exiled.card_id})

## Sends a card back to its owner's hand: a unit from the board (a bounce, not a death: no Ao Morrer, no Aliado Morre)
## or a card from the graveyard. `cost_increase` makes this copy cost that much more from now on (it stacks on every return).
## A token just vanishes; an Encarnação goes back to its own zone. Cards in any other zone are left alone.
## The hand may go past HAND_LIMIT: the owner discards the excess at the end of their turn, as with any overdraw.
func return_to_hand(c: Card, cost_increase := 0) -> void:
	var owner_player: int = c.owner
	if c.zone == "board":
		players[owner_player]["board"].erase(c)
		_release_equipment(c)
		if c.legendary:
			_move(c, "")
			_legendary_leaves(owner_player)
			_emit({"type": "return_to_hand", "uid": c.uid, "player": owner_player, "card_id": c.card_id})
			return
		if c.data().get("token", false):
			_move(c, "")
			_emit({"type": "return_to_hand", "uid": c.uid, "player": owner_player, "card_id": c.card_id})
			return
	elif c.zone == "graveyard":
		players[owner_player]["graveyard"].erase(c)
	else:
		return
	c.cost_mod += cost_increase
	players[owner_player]["hand"].append(c)
	_move(c, "hand")
	_emit({"type": "return_to_hand", "uid": c.uid, "player": owner_player, "card_id": c.card_id})

## Gives up priority. With items on the stack, everything resolves (newest first);
## in an empty combat window the combat moves on to the next window.
func pass_priority(p: int) -> Array:
	if phase not in ["main", "combat"] or p != priority:
		return []
	if stack.is_empty() and phase == "main" and not summon_window:
		return [] # nothing to pass: end the turn instead
	_emit({"type": "pass", "player": p})
	stack_system().pass_once()
	stack_system().settle()
	return _flush()

## Gives up the match: the opponent wins at once. Allowed at any moment, even off-turn or mid-stack.
func concede(p: int) -> Array:
	if phase == "over":
		return []
	_emit({"type": "concede", "player": p})
	winner = opponent(p)
	phase = "over"
	_emit({"type": "game_over", "winner": winner})
	return _flush()

func end_turn(p: int) -> Array:
	if not _sorcery_time(p):
		return []
	if players[p]["hand"].size() > HAND_LIMIT:
		phase = "discard"
		_emit({"type": "discard_required", "player": p, "count": players[p]["hand"].size() - HAND_LIMIT})
		return _flush()
	_finish_turn()
	return _flush()

func discard(p: int, hand_uids: Array) -> Array:
	var need: int = players[p]["hand"].size() - HAND_LIMIT
	if phase != "discard" or p != active or hand_uids.size() != need:
		return []
	for uid in hand_uids:
		if _hand_card(p, uid) == null:
			return []
	for uid in hand_uids:
		var c := _hand_card(p, uid)
		players[p]["hand"].erase(c)
		# Banished, not discarded: the card never reaches the graveyard (hidden from the opponent).
		players[p]["banished"].append(c)
		_move(c, "banished")
		_emit({"type": "ban", "player": p, "uid": uid})
	phase = "main"
	_finish_turn()
	return _flush()

## Picks the target of the pending Ao Entrar (0 = decline: its targeted effects are skipped,
## the rest still happen), then the unit's summon response window opens.
## An Ao Entrar with a second pick asks twice (pending_enter["first"] holds the first answer):
## declining the first pick skips every targeted effect, declining the second skips only the "pick2" ones.
func choose_enter_target(p: int, target: int) -> Array:
	if phase != "enter_target" or p != decider():
		return []
	var uid := int(pending_enter["uid"])
	var asking_second: bool = pending_enter.has("first")
	var asked_spec: String = pending_enter["spec2"] if asking_second else pending_enter["spec"]
	var entering_effects: Array = CardDB.card(pending_enter["card_id"]).get("effects", [])
	if target != 0 and not valid_targets(p, asked_spec, uid, false, entering_effects).has(target):
		return []
	var same_target_ok: bool = CardDB.card(pending_enter["card_id"]).get("same_target_ok", false)
	if asking_second and target != 0 and target == int(pending_enter["first"]) and not same_target_ok:
		return []
	if not asking_second and target != 0 and pending_enter.get("spec2", "") != "":
		# the second pick comes next, unless nothing is left to pick
		var second_options := valid_targets(p, pending_enter["spec2"], uid, false, entering_effects)
		if not same_target_ok:
			second_options.erase(target)
		if not second_options.is_empty():
			pending_enter["first"] = target
			_emit({"type": "enter_target", "player": p, "uid": uid, "card_id": pending_enter["card_id"]})
			return _flush()
	var first_target: int = int(pending_enter["first"]) if asking_second else target
	var second_target: int = target if asking_second else 0
	var respond: bool = pending_enter.get("respond", false)
	pending_enter.clear()
	phase = "main"
	var c := find_unit(uid)
	var effects: Array = card_of(c)["effects"]
	if first_target == 0 or (asking_second and second_target == 0):
		_emit({"type": "enter_skip", "player": p, "uid": uid, "card_id": c.card_id})
	# a declined (or impossible) pick drops the effects that needed it, the rest still happen
	var rest: Array = []
	for e in effects:
		var needs_pick: bool = target_spec([e]) != ""
		var dropped: bool = needs_pick and (first_target == 0 or (e.get("pick2", false) and second_target == 0))
		if not dropped:
			rest.append(e)
	effects = rest
	_trigger_enter(p, c, effects, first_target, respond, second_target)
	_check_state()
	stack_system().after_search()
	stack_system().settle()
	return _flush()

## A Provocação that just entered waits for its controller: enter tapped or not.
## Returns false when no living unit is waiting (units that already left are dropped).
func ask_enter_tapped() -> bool:
	while not pending_tap.is_empty() and find_unit(int(pending_tap[0])) == null:
		pending_tap.pop_front()
	if pending_tap.is_empty():
		return false
	if phase != "enter_tapped":
		_enter_tapped_return = phase
		phase = "enter_tapped"
	var unit := find_unit(int(pending_tap[0]))
	_emit({"type": "enter_tapped_choice", "player": unit.owner, "uid": unit.uid, "card_id": unit.card_id})
	return true

## The controller's answer for the waiting Provocação: tapped = true makes it enter exhausted,
## so it forces enemy attackers to challenge it (and can be challenged).
func choose_enter_tapped(p: int, tapped: bool) -> Array:
	if phase != "enter_tapped" or pending_tap.is_empty() or p != decider():
		return []
	var unit := find_unit(int(pending_tap.pop_front()))
	if unit != null:
		if tapped and not unit.has_kw("inerte"):
			unit.exhausted = true
		_emit({"type": "enter_tapped", "player": p, "uid": unit.uid, "tapped": tapped})
	# the next waiting Provocação is asked by settle(); otherwise the game goes back to where it was
	phase = _enter_tapped_return
	_check_state()
	stack_system().after_search()
	stack_system().settle()
	return _flush()

## Choose one of the public cards revealed by a deterministic deck search.
func choose_search(p: int, card_uid: int) -> Array:
	if phase != "search" or p != decider():
		return []
	var options: Array = pending_search.get("cards", [])
	var chosen: Dictionary = {}
	for c in options:
		if int(c["uid"]) == card_uid:
			chosen = c
			break
	if chosen.is_empty():
		return []
	if pending_search.get("revive", false):
		# a new copy of the chosen card enters the board; the card itself stays in the graveyard
		pending_search.clear()
		phase = _search_return
		_emit({"type": "revive", "player": p, "card_id": chosen["card_id"]})
		if has_free_slot(p):
			_summon(p, Card.new(_uid(), chosen["card_id"], p), false, 0)
		_resolve_stack()
		_check_state()
		stack_system().after_search()
		stack_system().settle()
		return _flush()
	if pending_search.get("hand_summon", false):
		# Dona Gertrudes: the chosen card goes from the hand to the board without paying its cost
		var summoned_card := _hand_card(p, card_uid)
		if summoned_card == null or not has_free_slot(p):
			return []
		players[p]["hand"].erase(summoned_card)
		pending_search.clear()
		phase = _search_return
		_emit({"type": "hand_summon", "player": p, "uid": card_uid, "card_id": summoned_card.card_id})
		_summon(p, summoned_card, false, 0, {}, true)
		summoned_card.banish_at_turn_end = true # set after entering, because enter_board resets it
		_resolve_stack()
		_check_state()
		stack_system().after_search()
		stack_system().settle()
		return _flush()
	if pending_search.get("discard_hand", false):
		# the chosen card leaves the hand for the graveyard (a normal discard; only overdraw banishes)
		var discarded_card := _hand_card(p, card_uid)
		if discarded_card == null:
			return []
		players[p]["hand"].erase(discarded_card)
		players[p]["graveyard"].append(discarded_card)
		_move(discarded_card, "graveyard")
		pending_search.clear()
		phase = _search_return
		_emit({"type": "discard", "player": p, "uid": card_uid, "card_id": discarded_card.card_id})
		_resolve_stack()
		_check_state()
		stack_system().after_search()
		stack_system().settle()
		return _flush()
	if pending_search.get("grave", false):
		# Moer + escolher: the card comes out of the graveyard; the others stay there
		var grave: Array = players[p]["graveyard"]
		var gi := -1
		for i in grave.size():
			if grave[i].uid == card_uid:
				gi = i
				break
		if gi < 0:
			return []
		var taken: Card = grave[gi]
		grave.remove_at(gi)
		if pending_search.get("banish_after_cast", false):
			taken.banish_after_cast = true # banished when this cast ends (see StackSystem)
		players[p]["hand"].append(taken)
		_move(taken, "hand")
		pending_search.clear()
		phase = _search_return
		_emit({"type": "search_take", "player": p, "uid": card_uid, "card_id": chosen["card_id"]})
		_resolve_stack()
		_check_state() # resumes the triggers that waited for this choice
		stack_system().after_search()
		stack_system().settle()
		return _flush()
	var deck: Array = players[p]["deck"]
	var found: Card = null
	for c: Card in deck:
		if c.uid == card_uid:
			found = c
			break
	if found == null:
		return []
	deck.erase(found)
	players[p]["hand"].append(found)
	_move(found, "hand")
	var look: bool = pending_search.get("look", false)
	var top_search: bool = pending_search.has("to_bottom") # a search limited to the top N cards
	var reshuffle: bool = pending_search.get("shuffle", false)
	if (look or top_search) and not reshuffle:
		# the cards not taken go to the bottom of the deck, unrevealed
		var not_taken: Array = []
		if top_search:
			not_taken = pending_search["to_bottom"]
		else:
			for c in options:
				not_taken.append(int(c["uid"]))
		for uid in not_taken:
			if int(uid) == card_uid:
				continue
			for d: Card in deck:
				if d.uid == int(uid):
					deck.erase(d)
					deck.push_front(d)
					break
	else:
		_shuffle(deck)
	pending_search.clear()
	phase = _search_return
	_emit({"type": "search_take", "player": p, "uid": card_uid, "card_id": chosen["card_id"]})
	_emit({"type": "look_bottom" if (look or top_search) and not reshuffle else "search_shuffle", "player": p})
	_resolve_stack() # a search opened mid-resolution: finish the rest of the stack
	_check_state() # resumes the triggers that waited for this choice
	stack_system().after_search()
	stack_system().settle()
	return _flush()

# ---------------------------------------------------------------- stack & combat (see systems/)

## Momentum cost of a spell/ability on the stack.
func stack_cost(item: Dictionary) -> int:
	return stack_system().stack_cost(item)

## Extra Momentum a counter must pay to hit stack item `sid` (-1 when out of reach).
func counter_extra(cd: Dictionary, sid: int) -> int:
	return stack_system().counter_extra(cd, sid)

func _resolve_stack() -> void:
	stack_system().resolve_stack()

func _counter(p: int, sid: int) -> void:
	stack_system().counter(p, sid)

## A free-standing artifact resolved: it takes a field slot (or goes to the graveyard if the
## field filled up while it waited on the stack).
func _place_relic(p: int, c: Card) -> void:
	if not has_free_slot(p):
		players[p]["graveyard"].append(c)
		_move(c, "graveyard")
		return
	players[p]["relics"].append(c)
	_move(c, "relics")
	c.supreme_shield = CardDB.card(c.card_id).get("keywords", []).has("escudo_supremo") # an artifact can be born protected (Baluarte Santo)
	c.supreme_shield_expires = ""
	_emit({"type": "relic_enter", "player": p, "uid": c.uid, "card_id": c.card_id})

## True when a copy of `card_id` left p's field `turns` or fewer turns ago (the current turn counts as 0).
func relic_fell_within(p: int, card_id: String, turns: int) -> bool:
	var fall_turns: Dictionary = players[p].get("relic_fall_turns", {})
	return fall_turns.has(card_id) and turn - int(fall_turns[card_id]) <= turns

## Escudo Supremo: spends the holder's one charge. True when there was a charge to spend.
func spend_supreme_shield(holder: Card, source_uid := 0) -> bool:
	if not holder.supreme_shield:
		return false
	holder.supreme_shield = false
	holder.supreme_shield_expires = ""
	_emit({"type": "supreme_shield_break", "uid": holder.uid, "src": source_uid})
	return true

## Destroys a free-standing artifact: it leaves the field (freeing its slot) for the graveyard.
func destroy_relic(c: Card) -> void:
	var p := c.owner
	if not players[p]["relics"].has(c):
		return
	players[p]["relics"].erase(c)
	players[p]["relic_fall_turns"][c.card_id] = turn
	players[p]["graveyard"].append(c)
	_emit({"type": "relic_destroyed", "player": p, "uid": c.uid, "card_id": c.card_id})
	_move(c, "graveyard")
	# Ao Morrer of a free-standing artifact (Baluarte Santo heals its Leader), same pattern as a dying unit
	var death_context := EffectContext.new(self, p, "on_death")
	death_context.self_uid = c.uid
	death_context.dying_card = c
	if not _chain_stopped():
		queue_trigger(PendingTrigger.new(c, c.effect_list(), death_context, "on_death"))

func _release_equipment(c: Card, unit_died := false) -> void:
	stack_system().release_equipment(c, unit_died)

## Can p do anything right now besides passing?
func _has_play(p: int) -> bool:
	return stack_system().has_play(p)

## "PASSAR TUDO": p stops being asked for responses during the rest of the opponent's turn.
## Valid at any moment of the opponent's turn. If p is being asked right now, that window is passed too;
## otherwise the flag just waits for the opponent's next play. A stack that would kill p's Leader is never
## passed for them: the window stays open so p can still answer it.
func pass_rest_of_turn(p: int) -> Array:
	if phase not in ["main", "combat"] or p == active or skip_rest_of_turn[p]:
		return []
	skip_rest_of_turn[p] = true
	if p != priority or stack_system().stack_would_kill_leader(p):
		_emit({"type": "pass_all_on", "player": p})
		return _flush()
	_emit({"type": "pass", "player": p})
	stack_system().pass_once()
	stack_system().settle()
	return _flush()

## Takes "PASSAR TUDO" back: from now on p is asked for responses again. Windows already passed stay passed.
## A setting like set_auto_pass, so it is allowed at any moment.
func cancel_pass_rest_of_turn(p: int) -> Array:
	if not skip_rest_of_turn[p]:
		return []
	skip_rest_of_turn[p] = false
	_emit({"type": "pass_all_off", "player": p})
	return _flush()

## Turns p's auto-pass on or off. Turning it on while p holds an unusable window passes it.
func set_auto_pass(p: int, on: bool) -> Array:
	auto_pass[p] = on
	if on:
		stack_system().settle()
	return _flush()

# ---------------------------------------------------------------- internals

## ask: played from hand/Santuário, so a targeted Ao Entrar waits for its owner's pick
## (phase "enter_target") instead of resolving right away.
## slot: board position to enter at (0 = leftmost); -1 or past the end = rightmost. Position
## matters for adjacency (Armadura from neighbours, "random_enemy_and_adjacent", ...).
## respond: the unit was played (hand or Legendary), so its Ao Entrar goes on the stack as an item the
## opponent may answer with an Instantâneo (it cannot be countered) instead of resolving at once.
func _summon(p: int, c: Card, legendary: bool, target: int, over: Dictionary = {}, ask := false, slot := -1, respond := false) -> void:
	var uid := c.uid
	var card_id := c.card_id
	c.owner = p
	c.enter_board(legendary, over)
	var cd := c.data()
	_move(c, "board")
	var board: Array = players[p]["board"]
	if slot < 0 or slot >= board.size():
		board.append(c)
	else:
		board.insert(slot, c)
	_emit({"type": "summon", "player": p, "uid": uid, "card_id": card_id})
	# Listeners such as Alderion react to the exact unit that just entered, including summoned Plants.
	var entered := GameEvent.new("unit_entered", p, c)
	entered.data["plant"] = CardDB.card(c.card_id).get("species", []).has("planta")
	bus().emit(entered)
	# Leaders may react to their first token entering each turn. The card is already on the
	# board, so a passive buff can include the newly summoned token among its legal targets.
	if cd.get("token", false):
		_fire_leader_passive(p, "on_ally_token_summon", uid)
	# Provocação: on any entry its controller chooses whether it enters tapped (asked once things settle)
	if has_kw(c, "provocacao") and not has_kw(c, "inerte"):
		pending_tap.append(uid)
	var spec := enter_spec(cd)
	var enter_options: Array = valid_targets(p, spec, uid, false, cd.get("effects", [])) if spec != "" else []
	# the unit itself as the only possible target is no real choice: it is picked without asking
	var only_itself: bool = enter_options.size() == 1 and enter_options[0] == uid
	if only_itself and target == 0:
		target = uid
	if ask and spec != "" and not enter_options.is_empty() and not only_itself:
		pending_enter = {"player": p, "uid": uid, "card_id": card_id, "spec": spec, "spec2": enter_second_spec(cd), "respond": respond}
		phase = "enter_target"
		_emit({"type": "enter_target", "player": p, "uid": uid, "card_id": card_id})
		return
	# "ally_unit" Ao Entrar with no chosen ally falls back to the unit itself
	if target == 0 and target_spec(cd["effects"]) == "ally_unit":
		target = uid
	_trigger_enter(p, c, cd["effects"], target, respond)

## Runs the unit's Ao Entrar `effects`, or (respond) puts them on the stack so the opponent can answer first.
func _trigger_enter(p: int, c: Card, effects: Array, target: int, respond: bool, second_target := 0) -> void:
	if respond and _has_enter_effects(effects):
		stack_system().push(p, "enter_trigger", c.uid, c.card_id, target, "instantaneo", second_target)
		return
	_announce(c, effects, "on_enter")
	run_enter_effects(_enter_context(p, c.uid, target, second_target), effects)

## Runs a unit's Ao Entrar effects; a second time when its controller has a "double_enter" unit (Arauto Repeteco)
## on the board that is not the entering unit itself. The same chosen target is used, no new input is asked.
func run_enter_effects(context: EffectContext, effects: Array) -> void:
	var doubled := has_doubler(context.controller, "double_enter", context.self_uid)
	_run_effects(context, effects)
	if doubled:
		_run_effects(context, effects)

func _has_enter_effects(effects: Array) -> bool:
	for e in effects:
		if (e.trigger if e is Effect else e.get("trigger", "")) == "on_enter":
			return true
	return false

## Tells the listening cards (Mestra do Gelo Frígido) that p cast a spell. The event's data says
## which essences the spell has, one "essence_<id>": true fact each, for the "when" filter.
func _announce_spell_cast(p: int, spell: Card, cd: Dictionary) -> void:
	var cast := GameEvent.new("spell_cast", p, spell)
	for essence_id in CardDB.essences_of(cd):
		cast.data["essence_" + String(essence_id)] = true
	bus().emit(cast)

## Context for a unit's Ao Entrar effects; `target` is the ally the player chose (0 if none).
func _enter_context(p: int, uid: int, target: int, second_target := 0) -> EffectContext:
	var context := EffectContext.new(self, p, "on_enter")
	context.self_uid = uid
	context.chosen_target = target
	context.second_target = second_target
	return context

## Tells the UI that unit c's `trigger` went off, so it can show where the effects that
## follow come from. Only when at least one of `effects` actually runs for that trigger.
func _announce(c: Card, effects: Array, trigger: String) -> void:
	for e in effects:
		var entry_trigger: String = e.trigger if e is Effect else e.get("trigger", "")
		if entry_trigger == trigger:
			_emit({"type": "trigger", "uid": c.uid, "player": c.owner, "card_id": c.card_id, "trigger": trigger})
			return

## Fires a unit's own trigger. Depth-capped so on_damaged chains cannot loop forever.
func _fire(c: Card, trigger: String, other_uid: int = 0, event_data: Dictionary = {}) -> void:
	if c == null:
		return
	var event := GameEvent.new(trigger, c.owner, c)
	event.other_uid = other_uid
	event.data = event_data
	bus().emit(event)

## Gatilhos (cards.json "triggers"): on_play, on_enter, on_death, before_attack, on_attack, on_challenge,
## on_challenged, on_damaged, on_hit_leader, on_turn_start, on_turn_end. "constante" never fires
## here: it is continuous and handled by _refresh_scaling.
## other_uid is the opposing unit in combat triggers (challenged unit, attacker, damage source).
func _run_effects(context: EffectContext, effects: Array) -> void:
	context.shielded_uids.clear() # a repeated run (Arauto Repeteco) is a new application
	context.shielded_this_effect.clear()
	for entry in effects:
		# entries are Effect objects (raw card dictionaries are parsed on the fly)
		var effect: Effect = entry if entry is Effect else EffectRegistry.parse(entry)
		if _chain_stopped():
			return
		if context.trigger != "" and effect.trigger != context.trigger:
			continue
		if context.trigger == "" and effect.listen != "":
			continue # listening effects only run when their event happens
		if effect.is_static() or effect.action == "cost_reduction":
			continue
		if effect.condition != null and not effect.condition.check(context):
			continue
		if effect.target.hits_one_at_a_time():
			# one hit at a time: nothing else resolves in between (deaths and their Ao Morrer wait for _check_state)
			for hit in effect.target.hit_count(context, effect):
				for target_uid in effect.target.resolve_hit(context, effect):
					effect.apply_to(context, target_uid)
		else:
			for target_uid in effect.target.resolve(context, effect):
				effect.apply_to(context, target_uid)
		context.shielded_uids.append_array(context.shielded_this_effect)
		context.shielded_this_effect.clear()
		if effect.opens_choice() and effect.trigger == context.trigger:
			effect.open_choice(context)

## Effects a card has while it sits in the deck ("deck_effects": [{trigger, if, action}]).
## "summon_self": that copy leaves the deck and enters its owner's board (no shuffle, nothing is
## drawn). Optional "cost": paid on the way in like an ability (Reserva first, then Momentum); if it
## can't be paid, or the board is full, the copy stays in the deck.
func _fire_deck_effects(p: int, trigger: String) -> void:
	for c in players[p]["deck"].duplicate():
		for e in CardDB.card(c.card_id).get("deck_effects", []):
			if e.get("trigger", "") != trigger:
				continue
			var condition := ConditionRegistry.parse(e.get("if", ""))
			if condition != null and not condition.check(EffectContext.new(self, p, trigger)):
				continue
			var fee := int(e.get("cost", 0))
			if e.get("action", "") == "summon_self" and players[p]["deck"].has(c) and has_free_slot(p) and budget(p, true) >= fee:
				_pay(p, fee, true)
				players[p]["deck"].erase(c)
				_emit({"type": "deck_summon", "player": p, "uid": c.uid, "card_id": c.card_id})
				_summon(p, c, false, 0)

func _begin_search(p: int, e: Dictionary, source_uid: int) -> void:
	if phase == "search":
		return
	var matches: Array = []
	var seen: Dictionary = {}
	# "top": N looks only at the N cards on top of the deck (the top is the back of the array);
	# without it the whole deck is searched, which is only for very narrow filters (a single named card)
	var top_only := int(e.get("top", 0)) > 0
	var searched: Array = players[p]["deck"]
	if top_only:
		var deck_size: int = searched.size()
		searched = searched.slice(maxi(deck_size - int(e["top"]), 0), deck_size)
	for c in searched:
		var cd := CardDB.card(c.card_id)
		if e.get("essence", "") != "" and not CardDB.has_essence(cd, e["essence"]):
			continue
		if e.has("max_cost") and int(cd.get("cost", 999)) > int(e["max_cost"]):
			continue
		if e.has("type") and cd.get("type", "") != e["type"]:
			continue
		if e.has("types_any") and not e["types_any"].has(cd.get("type", "")):
			continue
		# "card_ids": only these named cards (Recado Urgente ao Barão finds only the Barão)
		if e.has("card_ids") and not e["card_ids"].has(c.card_id):
			continue
		if e.has("species") and not cd.get("species", []).has(e["species"]):
			continue
		if e.has("tags"):
			var card_tags: Array = cd.get("tags", [])
			var matches_tags := true
			for tag in e["tags"]:
				if not card_tags.has(tag):
					matches_tags = false
					break
			if not matches_tags:
				continue
		if e.has("tags_any"):
			# at least ONE of these tags is enough (Chamado da Nevasca finds any piece of the combo)
			var has_any_tag := false
			for tag in e["tags_any"]:
				if CardDB.card(c.card_id).get("tags", []).has(tag):
					has_any_tag = true
					break
			if not has_any_tag:
				continue
		# a whole-deck search lists each card once; a top-N look shows every copy, because each one is really there
		if not top_only:
			if seen.has(c.card_id):
				continue
			seen[c.card_id] = true
		matches.append({"uid": c.uid, "card_id": c.card_id})
	if matches.is_empty():
		_emit({"type": "search_empty", "player": p, "source_uid": source_uid})
		# "fallback_draw": the consolation prize when nothing matched, so the spell is never a dead card (Recado Urgente)
		if int(e.get("fallback_draw", 0)) > 0:
			_draw(p, int(e["fallback_draw"]))
		return
	# "deck_search": the options are private to the searcher; the opponent only learns the card that was taken (search_take)
	pending_search = {"player": p, "source_uid": source_uid, "cards": matches, "deck_search": true}
	if top_only:
		# the cards looked at but not taken go to the bottom of the deck instead of a shuffle
		var looked_uids: Array = []
		# every card looked at, topmost first; "cards" holds only the eligible ones, so the UI can show the rest dimmed
		var looked_cards: Array = []
		for c: Card in searched:
			looked_uids.append(c.uid)
		for index in range(searched.size() - 1, -1, -1):
			looked_cards.append({"uid": searched[index].uid, "card_id": searched[index].card_id})
		pending_search["to_bottom"] = looked_uids
		pending_search["looked"] = searched.size()
		pending_search["looked_cards"] = looked_cards
	_search_return = phase
	phase = "search"
	_emit({"type": "search_reveal", "player": p, "source_uid": source_uid, "cards": matches, "private": true, "looked": pending_search.get("looked", 0)})

## The player picks one card from their own hand to discard to the graveyard.
## Uses the same choice screen as the overdraw banish; the options are private to the owner.
func _begin_hand_discard(p: int, source_uid: int) -> void:
	if phase == "search":
		return
	var options: Array = []
	for c: Card in players[p]["hand"]:
		options.append({"uid": c.uid, "card_id": c.card_id})
	if options.is_empty():
		_emit({"type": "search_empty", "player": p, "source_uid": source_uid})
		return
	pending_search = {"player": p, "source_uid": source_uid, "cards": options, "discard_hand": true}
	_search_return = phase
	phase = "search"
	_emit({"type": "discard_pick", "player": p, "source_uid": source_uid})

## The player picks a unit card (of `rarity`; "" = any) from their own hand; it enters the board
## for free and is banished at the end of the turn. The options are private to the owner.
func _begin_hand_summon(p: int, rarity: String, source_uid: int) -> void:
	if phase == "search":
		return
	var options: Array = []
	for c: Card in players[p]["hand"]:
		var card_data := CardDB.card(c.card_id)
		if card_data["type"] == "unit" and (rarity == "" or card_data.get("rarity", "") == rarity):
			options.append({"uid": c.uid, "card_id": c.card_id})
	if options.is_empty() or not has_free_slot(p):
		_emit({"type": "search_empty", "player": p, "source_uid": source_uid})
		return
	pending_search = {"player": p, "source_uid": source_uid, "cards": options, "hand_summon": true}
	_search_return = phase
	phase = "search"
	_emit({"type": "hand_summon_pick", "player": p, "source_uid": source_uid})

## Offers every copy of `card_id` in the graveyard (just one entry per copy); the pick goes to the
## hand marked to be banished after its next cast.
func _begin_grave_retrieve(p: int, wanted_ids: Array, source_uid: int) -> void:
	if phase == "search":
		return
	var options: Array = []
	for c in players[p]["graveyard"]:
		if wanted_ids.has(c.card_id):
			options.append({"uid": c.uid, "card_id": c.card_id})
	if options.is_empty():
		_emit({"type": "search_empty", "player": p, "source_uid": source_uid})
		return
	pending_search = {"player": p, "source_uid": source_uid, "cards": options, "grave": true, "banish_after_cast": true}
	_search_return = phase
	phase = "search"
	_emit({"type": "search_reveal", "player": p, "source_uid": source_uid, "cards": options})

## Offers the cards just milled (public: they are in the graveyard); one goes to the hand.
func _begin_grave_pick(p: int, milled: Array, source_uid: int) -> void:
	if phase == "search":
		return
	var options: Array = []
	for c in milled:
		for g in players[p]["graveyard"]:
			if g.uid == c.uid:
				options.append({"uid": c.uid, "card_id": c.card_id})
				break
	if options.is_empty():
		_emit({"type": "search_empty", "player": p, "source_uid": source_uid})
		return
	pending_search = {"player": p, "source_uid": source_uid, "cards": options, "grave": true}
	_search_return = phase
	phase = "search"
	_emit({"type": "search_reveal", "player": p, "source_uid": source_uid, "cards": options})

## Unit cards in p's graveyard a "revive_pick" could bring back (one entry per different card).
func revive_options(p: int, max_cost := 99) -> Array:
	var options: Array = []
	var seen: Dictionary = {}
	for c: Card in players[p]["graveyard"]:
		var cd := CardDB.card(c.card_id)
		if cd["type"] != "unit" or int(cd.get("cost", 0)) > max_cost or seen.has(c.card_id):
			continue
		seen[c.card_id] = true
		options.append({"uid": c.uid, "card_id": c.card_id})
	return options

## Offers the unit cards of p's graveyard; a copy of the chosen one enters the board
## (Ossuário Sem Fundo). Uses the same choice screen as the searches.
func _begin_revive_pick(p: int, max_cost: int, source_uid: int) -> void:
	if phase == "search":
		return
	var options := revive_options(p, max_cost)
	if options.is_empty() or not has_free_slot(p):
		_emit({"type": "search_empty", "player": p, "source_uid": source_uid})
		return
	pending_search = {"player": p, "source_uid": source_uid, "cards": options, "revive": true}
	_search_return = phase
	phase = "search"
	_emit({"type": "search_reveal", "player": p, "source_uid": source_uid, "cards": options})

## Private look at the top `n` cards: only the owner sees them (StateView hides them from
## the other seat); the one taken is revealed by search_take, the rest go to the bottom (or, with "shuffle", the deck is shuffled).
func _begin_look(p: int, n: int, source_uid: int, reshuffle: bool = false) -> void:
	if phase == "search":
		return
	var deck: Array = players[p]["deck"]
	var top: Array = []
	for i in range(deck.size() - 1, maxi(deck.size() - n, 0) - 1, -1): # top of the deck is the back
		top.append({"uid": deck[i].uid, "card_id": deck[i].card_id})
	if top.is_empty():
		_emit({"type": "search_empty", "player": p, "source_uid": source_uid})
		return
	pending_search = {"player": p, "source_uid": source_uid, "cards": top, "look": true, "shuffle": reshuffle}
	_search_return = phase
	phase = "search"
	_emit({"type": "look_top", "player": p, "source_uid": source_uid, "cards": top})

## Returns damage actually dealt. source is the dealing unit or null.
## Armadura a unit really has: its own (printed + buffs), plus the "graveyard_armor" it counts
## itself, the "species_aura" Armadura of its allies, and "adjacent_armor" from the allies
## standing right next to it on the board (the board order is the order the units were played).
## The adjacent Armadura is a text Constante, so a Contador Exagerado doubles it.
func armor_of(c: Card) -> int:
	var total := c.armor_total() + graveyard_armor_of(c)
	if players[c.owner]["board"].has(c):
		total += species_aura_bonus(c).z
	var board: Array = players[c.owner]["board"]
	var index := board.find(c)
	if index < 0:
		return total
	var adjacent_total := 0
	for neighbour_index in [index - 1, index + 1]:
		if neighbour_index >= 0 and neighbour_index < board.size():
			adjacent_total += int(card_of(board[neighbour_index]).get("adjacent_armor", 0))
	return total + adjacent_total * constants_multiplier(c.owner)

## Damage a unit takes from one hit of `amount` after its Armadura: reduced, but never below 1
## (a hit of 0 stays 0).
func damage_after_armor(c: Card, amount: int) -> int:
	if amount <= 0:
		return 0
	var graveyard_reduction := graveyard_damage_reduction_of(c, amount)
	if graveyard_reduction >= 0:
		return graveyard_reduction
	return maxi(1, amount - armor_of(c))

func _deal_damage(t: int, amount: int, source: Card) -> int:
	return _deal_damage_internal(t, amount, source, false)

## Periodic damage is already an applied status, so its damage bypasses Armadura, Escudo and
## Escudo de Feitiço. Indestrutível remains the stronger protection and still prevents it.
func _deal_dot_damage(t: int, amount: int, dot_id: String) -> int:
	return _deal_damage_internal(t, amount, null, true, dot_id)

## Santa Maria Helena: the first damage instance to her Leader each turn is reduced by 3,
## but the hit itself can never be reduced below 1. This applies before other Leader modifiers.
func _apply_leader_damage_guard(p: int, amount: int, src_uid: int) -> int:
	for c: Card in players[p]["board"]:
		var reduction := int(c.data().get("leader_damage_reduction", 0))
		if reduction <= 0 or c.leader_damage_guard_turn == turn:
			continue
		c.leader_damage_guard_turn = turn
		var reduced := maxi(1, amount - reduction)
		var prevented := amount - reduced
		if prevented > 0:
			_emit({"type": "leader_guard", "uid": c.uid, "amount": prevented, "src": src_uid})
		return reduced
	return amount

func _deal_damage_internal(t: int, amount: int, source: Card, bypass_unit_protections: bool, damage_kind := "") -> int:
	if amount <= 0:
		return 0
	var dealt := 0
	var src_uid := source.uid if source != null else 0
	if t < 0:
		var tp := LEADER_UID.find(t)
		var hp_before: int = players[tp]["leader_hp"]
		amount = _apply_leader_damage_guard(tp, amount, src_uid)
		# Câmara de Êxtase aftermath: the next 3 damage instances are reduced to 0, until the end of the
		# controller's next turn (whichever comes first)
		if amount > 0 and turn <= int(players[tp]["damage_negated_until"]) and int(players[tp]["damage_negated_left"]) > 0:
			players[tp]["damage_negated_left"] -= 1
			_emit({"type": "leader_hit_negated", "uid": t, "player": tp, "amount": amount, "src": src_uid, "left": int(players[tp]["damage_negated_left"])})
			return 0
		# Câmara de Êxtase: a killing blow is cancelled completely and the Chamber is spent
		var ward := _lethal_ward_of(tp)
		if ward != null and amount >= hp_before:
			_trigger_lethal_ward(tp, ward, amount, src_uid)
			return 0
		players[tp]["leader_hp"] -= amount
		dealt = amount
		# "hp_after": the life left once this hit landed (the Chronicle shows it next to the damage)
		_emit({"type": "damage", "uid": t, "amount": amount, "src": src_uid, "hp_after": players[tp]["leader_hp"]})
		var damaged := GameEvent.new("leader_damaged", tp, source)
		damaged.amount = amount
		damaged.hp_before = hp_before
		damaged.hp_after = players[tp]["leader_hp"]
		if damage_kind != "":
			damaged.data = {"dot": damage_kind}
		bus().emit(damaged)
		if source != null:
			_fire(source, "on_hit_leader", 0, {"hit_damage": amount})
		# Tóxico normally skips Leaders; a card with "toxico_hits_leader" is the exception
		if _combat_damage and source != null and has_kw(source, "toxico") and source.data().get("toxico_hits_leader", false):
			add_leader_dot_markers(tp, "veneno", toxico_markers(source))
	else:
		var c := find_unit(t)
		if c == null:
			return 0
		if has_kw(c, "indestrutivel"):
			return 0 # damage is always 0 against it (Escudo isn't consumed)
		# Imunidade contra Obscura: the combat damage of an enemy Obscura unit is always 0 (Escudo isn't
		# consumed). Effect damage is covered in Effect.apply_to, and only when it aims at this unit.
		if _combat_damage and source != null and source.owner != c.owner and is_immune_to_essence_of(c, source.card_id):
			_emit({"type": "dot_immune", "uid": t, "dot": ""})
			return 0
		# Escudo Supremo absorbs any damage at all (even a periodic tick) and is spent by it
		if spend_supreme_shield(c, src_uid):
			return 0
		# What the hit was worth before Armadura, and the Armadura it met (Tharox only grows from hard hits)
		var raw_amount := amount
		var armor_before := armor_of(c)
		if not bypass_unit_protections:
			# Esquiva: the first combat damage each turn from a qualifying attacker is avoided
			if _combat_damage and has_kw(c, "esquiva") and source != null and combat_system().dodges(c, source) 				and c.dodge_turn != turn:
				c.dodge_turn = turn
				_emit({"type": "dodge", "uid": t, "src": src_uid})
				return 0
			# Armadura: reduces every damage instance, but a hit always deals at least 1
			amount = damage_after_armor(c, amount)
			if c.shield:
				c.shield = false
				_emit({"type": "shield_break", "uid": t, "src": src_uid})
				return 0
		# Baluarte Santo: cancel the complete damage instance if it would kill this unit.
		# For combat Toque Letal, any connected hit is lethal unless the target is immune.
		var total_hp := c.hp + c.bonus_hp + c.temp_hp + c.temp_hp_until_next_turn
		var lethal_touch := _combat_damage and source != null and has_kw(source, "toque_letal") \
			and not _immune_to_lethal_touch(c)
		if (c.damage + amount >= total_hp or lethal_touch) and _consume_death_ward(c, src_uid):
			return 0
		c.damage += amount
		dealt = amount
		var damage_event := {"type": "damage", "uid": t, "amount": amount, "src": src_uid, "hp_after": c.hp_left()}
		if damage_kind != "":
			damage_event["dot"] = damage_kind
		_emit(damage_event)
		var unit_hurt := GameEvent.new("unit_damaged", c.owner, c)
		unit_hurt.other_uid = src_uid
		unit_hurt.amount = amount
		unit_hurt.hp_before = c.hp_left() + amount
		unit_hurt.hp_after = c.hp_left()
		if damage_kind != "":
			unit_hurt.data = {"dot": damage_kind}
		bus().emit(unit_hurt)
		# Mar que Retorna: the marked unit survived damage -> its owner draws once
		if c.tide_mark and c.hp_left() > 0:
			c.tide_mark = false
			_emit({"type": "tide_draw", "uid": t, "player": c.owner})
			_draw(c.owner, 1)
		# Ao Sofrer Dano only fires if the unit survived the damage; a lethal hit just kills it
		if c.hp_left() > 0:
			_fire(c, "on_damaged", src_uid, {"from_spell": _spell_resolving and source == null,
				"hit_reached_armor": raw_amount >= armor_before})
		# Reflexão: half of the damage taken (rounded up) goes back to the unit that dealt it. The
		# returning damage has no source, so two mirrors facing each other can't bounce it forever.
		if has_kw(c, "reflexao") and source != null and source != c and find_unit(src_uid) != null:
			_emit({"type": "reflect", "uid": t, "target": src_uid, "amount": ceili(amount / 2.0)})
			_deal_damage(src_uid, ceili(amount / 2.0), null)
		# Toque Letal is a combat-damage rider, not a destroy effect: Escudo and Esquiva
		# return before this point with dealt == 0, while Indestrutível is checked here as
		# the first absolute protection. Keep the data flag/keyword hook for future protections
		# such as Imunidade contra Obscura without making them damage effects.
		if _combat_damage and source != null and has_kw(source, "toque_letal") and dealt > 0 \
				and not _immune_to_lethal_touch(c):
			c.damage = maxi(c.damage, c.hp + c.bonus_hp + c.temp_hp + c.temp_hp_until_next_turn)
		# Tóxico X: combat damage that really got through leaves X Veneno markers (blocked damage returned above)
		if _combat_damage and source != null and has_kw(source, "toxico") and dealt > 0 and c.hp_left() > 0:
			add_dot_markers(c, "veneno", toxico_markers(source), source.data().get("toxico_ignores_immunity", false))
	if _combat_damage and source != null and dealt > 0:
		burn_target_of_combat_damage_dealer(source, t)
	if source != null and has_kw(source, "roubo_de_vida"):
		_heal_leader(source.owner, dealt)
	return dealt

## A unit with "burns_on_combat_damage": N leaves N Queimadura markers on what its combat damage hit.
func burn_target_of_combat_damage_dealer(dealer: Card, target_uid: int) -> void:
	var burn_markers := int(dealer.data().get("burns_on_combat_damage", 0))
	if burn_markers <= 0:
		return
	if target_uid < 0:
		add_leader_dot_markers(LEADER_UID.find(target_uid), "queimadura", burn_markers)
		return
	var burned_unit := find_unit(target_uid)
	if burned_unit != null and burned_unit.hp_left() > 0:
		add_dot_markers(burned_unit, "queimadura", burn_markers)

## Puts `amount` accumulating markers of the `dot_id` kind on the unit (they resolve at its controller's turn start).
func add_dot_markers(unit: Card, dot_id: String, amount: int, ignores_immunity := false) -> void:
	if not ignores_immunity and unit_is_immune_to_dot(unit, dot_id):
		_emit({"type": "dot_immune", "uid": unit.uid, "dot": dot_id})
		return
	unit.dot_markers[dot_id] = int(unit.dot_markers.get(dot_id, 0)) + amount
	_emit({"type": "dot", "uid": unit.uid, "dot": dot_id, "amount": amount, "total": int(unit.dot_markers[dot_id])})

## Puts markers on a Leader (player `p`). Like a unit's, they hurt it and are consumed at the start
## of its controller's turn (see _resolve_leader_dot), unless a card holds the Veneno in place.
## Any number of markers is harmless to the engine; killing a Leader by markers is a card effect.
func add_leader_dot_markers(p: int, dot_id: String, amount: int) -> void:
	var leader_dots: Dictionary = players[p]["leader_dots"]
	leader_dots[dot_id] = int(leader_dots.get(dot_id, 0)) + amount
	_emit({"type": "dot", "uid": LEADER_UID[p], "dot": dot_id, "amount": amount, "total": int(leader_dots[dot_id])})

## Purify: removes every periodic-status marker (Veneno, Queimadura, Sangramento) from the unit.
func cleanse_unit_markers(unit: Card) -> void:
	if unit.dot_markers.is_empty():
		return
	unit.dot_markers = {}
	_emit({"type": "cleanse", "uid": unit.uid})

## Purify: removes every periodic-status marker from the Leader of player `p`.
func cleanse_leader_markers(p: int) -> void:
	if players[p]["leader_dots"].is_empty():
		return
	players[p]["leader_dots"] = {}
	_emit({"type": "cleanse", "uid": LEADER_UID[p]})

## True when one of the unit's essences makes it immune to markers of `dot_id`.
func unit_is_immune_to_dot(unit: Card, dot_id: String) -> bool:
	return _essences_are_immune_to_dot(CardDB.essences_of(unit.data()), dot_id)

func _essences_are_immune_to_dot(essences: Array, dot_id: String) -> bool:
	for immune_essence in DOT_IMMUNE_ESSENCES.get(dot_id, []):
		if essences.has(immune_essence):
			return true
	return false

## Kills the Leader of player `p` on the spot (a card effect, e.g. Viprax's execution). Câmara de
## Êxtase and the damage halving do not apply. This is not damage: it emits its own "leader_executed"
## event (never a "damage" one) so the UI can play a dedicated execution animation instead of a big hit.
func kill_leader_outright(p: int, dot_id := "") -> void:
	var hp_before: int = players[p]["leader_hp"]
	if hp_before <= 0:
		return
	players[p]["leader_hp"] = 0
	var execution_event := {"type": "leader_executed", "uid": LEADER_UID[p], "player": p, "hp_before": hp_before}
	if dot_id != "":
		execution_event["dot"] = dot_id
	_emit(execution_event)

## How many markers of `dot_id` the Leader of player `p` holds.
func leader_dot_markers(p: int, dot_id: String) -> int:
	return int(players[p]["leader_dots"].get(dot_id, 0))

## True when unit `c` has the Imunidade contra <essência> of the essence of the card `source_card_id` (keyword "imunidade_" + essence).
## Only the opposing side's cards of that essence are blocked; the unit's own owner can still affect it.
func is_immune_to_essence_of(c: Card, source_card_id: String) -> bool:
	if source_card_id == "":
		return false
	var source_essence: String = str(CardDB.card(source_card_id).get("essence", ""))
	return source_essence != "" and has_kw(c, "imunidade_" + source_essence)

func _immune_to_lethal_touch(c: Card) -> bool:
	if c == null:
		return true
	return has_kw(c, "indestrutivel") \
		or has_kw(c, "imunidade_obscura") \
		or bool(c.data().get("lethal_touch_immune", false))

## The free-standing artifact of player p that cancels a lethal blow to their Leader (Câmara de Êxtase), if any.
func _lethal_ward_of(p: int) -> Card:
	for relic: Card in players[p]["relics"]:
		if relic.data().get("lethal_ward", false):
			return relic
	return null

## The Chamber cancels `prevented` damage, is destroyed, and then negates the Leader's next 3 damage
## instances (even in this same turn) until the end of its controller's next turn. `source_uid` is the unit whose blow was cancelled (0 = not a unit), so the
## screen can show that blow landing on the Leader.
func _trigger_lethal_ward(p: int, ward: Card, prevented: int, source_uid := 0) -> void:
	var until := turn + (2 if p == active else 1)
	players[p]["damage_negated_until"] = maxi(int(players[p]["damage_negated_until"]), until)
	players[p]["damage_negated_left"] = LETHAL_WARD_NEGATED_HITS
	_emit({"type": "lethal_ward", "player": p, "uid": ward.uid, "card_id": ward.card_id, "amount": prevented, "src": source_uid, "hits": LETHAL_WARD_NEGATED_HITS})
	destroy_relic(ward)

## How many of the Leader's next hits are still reduced to 0 by the Câmara de Êxtase aftermath (0 once its window closed).
func leader_negations_left(p: int) -> int:
	if turn > int(players[p]["damage_negated_until"]):
		return 0
	return int(players[p]["damage_negated_left"])

func _heal_leader(p: int, amount: int) -> void:
	var pl: Dictionary = players[p]
	var healed: int = min(amount, pl["leader_max"] - pl["leader_hp"])
	if healed > 0:
		var hp_before: int = pl["leader_hp"]
		pl["leader_hp"] += healed
		_emit({"type": "heal", "uid": LEADER_UID[p], "amount": healed, "hp_after": pl["leader_hp"]})
		_emit_leader_healed(p, healed, hp_before)

## Tox Vipranna's poison-healing trigger: each instance has a soft 15-point budget per turn.
## The trigger that reaches or crosses 15 resolves in full; later triggers from that instance are
## ignored until its controller's next turn. Each accepted trigger gives Vipranna +1 temporary Vida
## until the start of her owner's next turn.
func _apply_vipranna_heal(context: EffectContext, amount: int) -> void:
	var vipranna := find_unit(context.self_uid)
	if vipranna == null or vipranna.card_id != "tox_vipranna" or amount <= 0:
		return
	if vipranna.vipranna_heal_turn != turn:
		vipranna.vipranna_heal_turn = turn
		vipranna.vipranna_heal_total = 0
		vipranna.vipranna_heal_locked = false
	if vipranna.vipranna_heal_locked:
		return
	_heal_leader(context.controller, amount)
	vipranna.vipranna_heal_total += amount
	vipranna.temp_hp_until_next_turn += 1
	_emit({"type": "buff", "uid": vipranna.uid, "atk": 0, "hp": 1, "keywords": [], "until_next_turn": true})
	if vipranna.vipranna_heal_total >= 15:
		vipranna.vipranna_heal_locked = true

## Raises the Leader's maximum life and its current life by the same amount (can pass the starting life).
func _raise_leader_max(p: int, amount: int) -> void:
	var pl: Dictionary = players[p]
	pl["leader_max"] += amount
	var hp_before: int = pl["leader_hp"]
	pl["leader_hp"] += amount
	_emit({"type": "heal", "uid": LEADER_UID[p], "amount": amount, "hp_after": pl["leader_hp"]})
	_emit_leader_healed(p, amount, hp_before)

## Tells the listeners (Seymour) that a unit just got `amount` Vida back. Call it after the damage was removed.
func emit_unit_healed(unit: Card, amount: int) -> void:
	var healed := GameEvent.new("unit_healed", unit.owner, unit)
	healed.amount = amount
	healed.hp_after = unit.hp_left()
	healed.hp_before = healed.hp_after - amount
	bus().emit(healed)

func _emit_leader_healed(p: int, amount: int, hp_before: int) -> void:
	var healed := GameEvent.new("leader_healed", p)
	healed.amount = amount
	healed.hp_before = hp_before
	healed.hp_after = players[p]["leader_hp"]
	bus().emit(healed)

## Fadiga: damage of the next draw from an empty deck. Doubles each time: 2, 4, 8, 16…
func fatigue_next(p: int) -> int:
	return 2 << int(players[p]["fatigue"])

## Player `p` suffers one Fadiga: damage to their Leader, and the next one doubles. A draw from an empty deck,
## milling an already-empty deck and Hora Extra Compulsória all end up here.
func suffer_fatigue(p: int) -> void:
	var damage_amount := fatigue_next(p)
	players[p]["fatigue"] += 1
	_emit({"type": "fatigue", "player": p, "amount": damage_amount})
	_deal_damage(LEADER_UID[p], damage_amount, null)

func _draw(p: int, n: int) -> void:
	var pl: Dictionary = players[p]
	for i in n:
		if pl["deck"].is_empty():
			suffer_fatigue(p)
			continue
		var c: Card = pl["deck"].pop_back()
		pl["hand"].append(c)
		_move(c, "hand")
		_emit({"type": "draw", "player": p, "uid": c.uid})
		bus().emit(GameEvent.new("card_drawn", p, c))

## Draws the first card (from the top) whose base cost is at least `min_base_cost`; that copy costs
## `discount` less while it stays in hand (Tecnomante). Nothing happens, and no Fadiga, if none qualifies.
func _draw_discounted(p: int, min_base_cost: int, discount: int) -> void:
	var deck: Array = players[p]["deck"]
	for i in range(deck.size() - 1, -1, -1):
		if int(CardDB.card(deck[i].card_id)["cost"]) >= min_base_cost:
			var c: Card = deck[i]
			deck.remove_at(i)
			players[p]["hand"].append(c)
			_move(c, "hand")
			c.discount += discount
			_emit({"type": "draw", "player": p, "uid": c.uid})
			bus().emit(GameEvent.new("card_drawn", p, c))
			return

## Stabilizes the game after an action: moves dead units out, then resolves the queued triggers one
## at a time (active player's first), looping until nothing is left to do. A trigger that opens a
## choice (search, enter target) pauses the queue; it resumes when the choice is made.
func _check_state() -> void:
	var resolved := 0
	while true:
		_move_dead_units()
		if _pending.is_empty() or phase in ["search", "enter_target", "enter_tapped"]:
			break
		if _chain_stopped() or resolved >= MAX_TRIGGERS_PER_ACTION:
			_pending.clear() # a Leader is down or a trigger loop ran away: nothing new resolves
			break
		resolved += 1
		_take_next_pending().resolve(self)
	if not _combat_damage:
		_check_leaders()

## Called by the TriggerBus (and the death/passive code) when a trigger fires.
func queue_trigger(trigger: PendingTrigger) -> void:
	_pending.append(trigger)

## APNAP: the oldest trigger of the active player goes first, else the oldest of the opponent.
func _take_next_pending() -> PendingTrigger:
	for i in _pending.size():
		if _pending[i].controller() == active:
			return _pending.pop_at(i)
	return _pending.pop_front()

## Moves dead units out and queues their Ao Morrer / Aliado Morre. Loops until stable.
## Deaths are processed active player first (APNAP), then the opponent.
func _move_dead_units() -> void:
	var changed := true
	while changed:
		changed = false
		_refresh_scaling()
		# decided before anyone leaves, so a "double_death" unit that dies together with its allies still doubles them
		var death_doubled := [has_doubler(0, "double_death"), has_doubler(1, "double_death")]
		for p in [active, opponent(active)]:
			for c in players[p]["board"].duplicate():
				if hp_left(c) <= 0:
					if _prevent_unit_death(c):
						changed = true
						continue
					var dead_uid: int = c.uid # a revive_self below gives c a new uid
					var dying_is_token: bool = c.data().get("token", false) # "not_token" effects ignore a token dying
					var dying_card_id: String = c.card_id # "dying_card" effects only hear this card (Luto: Myrra)
					var effects: Array = c.effect_list()
					players[p]["board"].erase(c)
					changed = true
					_emit({"type": "death", "uid": dead_uid, "player": p, "card_id": dying_card_id})
					_release_equipment(c, true)
					if c.legendary:
						_move(c, "")
						_legendary_leaves(p)
					elif c.data().get("token", false):
						_move(c, "") # a ficha dies without ever reaching the graveyard (Vagante, Jeff don't count it)
					else:
						players[p]["graveyard"].append(c)
						_move(c, "graveyard")
					var death_context := EffectContext.new(self, p, "on_death")
					death_context.self_uid = dead_uid
					death_context.dying_card = c
					if not _chain_stopped():
						queue_trigger(PendingTrigger.new(c, effects, death_context, "on_death"))
						if death_doubled[p]:
							queue_trigger(PendingTrigger.new(c, effects, death_context, "on_death"))
					# Aliado Morre fires on every death, even if the unit comes right back (Revivente, Fênix)
					# or a Legendary returns to its zone.
					for ally in players[p]["board"].duplicate():
						if players[p]["board"].has(ally):
							_fire(ally, "on_ally_death", dead_uid, {"dying_is_token": dying_is_token, "dying_card_id": dying_card_id})
					for relic in players[p]["relics"].duplicate(): # free-standing artifacts hear it too
						_fire(relic, "on_ally_death", dead_uid, {"dying_is_token": dying_is_token, "dying_card_id": dying_card_id})
					_fire_leader_passive(p, "on_ally_death")

## Returns the Baluarte-like artifact of p, if any.
func _death_ward_of(p: int) -> Card:
	for relic: Card in players[p]["relics"]:
		if relic.data().get("death_ward", false):
			return relic
	return null

## Consumes the automatic ward when a unit would die. Banishment bypasses this death path.
## `source_uid` is the unit whose blow was cancelled (0 = not a unit), so the screen can show that blow landing.
func _consume_death_ward(victim: Card, source_uid := 0) -> bool:
	var ward := _death_ward_of(victim.owner)
	if ward == null:
		return false
	_emit({"type": "death_prevented", "player": victim.owner, "uid": victim.uid, "card_id": victim.card_id,
		"ward_uid": ward.uid, "ward_card_id": ward.card_id, "src": source_uid})
	destroy_relic(ward)
	return true

## Fallback for deaths from effects not intercepted at their damage/removal point.
func _prevent_unit_death(victim: Card) -> bool:
	if not _consume_death_ward(victim):
		return false
	var total_hp := victim.hp + victim.bonus_hp + victim.temp_hp + victim.temp_hp_until_next_turn
	victim.damage = maxi(0, total_hp - 1)
	victim.condemned_turn = 0
	return true

func _check_leaders() -> void:
	if phase == "over":
		return
	var dead := [players[0]["leader_hp"] <= 0, players[1]["leader_hp"] <= 0]
	if dead[0] or dead[1]:
		winner = 2 if dead[0] and dead[1] else (1 if dead[0] else 0)
		phase = "over"
		_emit({"type": "game_over", "winner": winner})

## Leader passive ("passive": true in the leader's ability): runs its effects when `trigger` happens,
## once per turn if "once_per_turn", or at most "max_per_turn" times a turn. `trigger_unit_uid` is the unit that
## caused the trigger (the token that just entered): the passive's "random_other_ally_unit" never picks it.
## Depth-capped like unit triggers.
func _fire_leader_passive(p: int, trigger: String, trigger_unit_uid := 0) -> void:
	var ab: Dictionary = CardDB.leader(players[p]["leader_id"])["ability"]
	if not ab.get("passive", false) or ab.get("trigger", "") != trigger or _chain_stopped():
		return
	if ab.get("own_turn_only", false) and active != p:
		return
	if ab.get("once_per_turn", false) and players[p]["passive_used"]:
		return
	# "passive_uses" only exists for passives with a limit above 1 (it is wiped every turn start)
	if ab.has("max_per_turn") and int(players[p].get("passive_uses", 0)) >= int(ab["max_per_turn"]):
		return
	if _passive_refunds_nothing(p, ab):
		return # nothing leaked: do not announce a passive that does nothing (e.g. on the first turn)
	var passive_context := EffectContext.new(self, p, "")
	passive_context.self_uid = trigger_unit_uid
	var passive_effects := EffectRegistry.parse_list(ab["effects"])
	if _passive_has_nobody_to_target(passive_effects, passive_context):
		return # e.g. Crescimento do Dossel when the only plant is the token that just entered
	players[p]["passive_used"] = true
	if ab.has("max_per_turn"):
		players[p]["passive_uses"] = int(players[p].get("passive_uses", 0)) + 1
	_emit({"type": "passive", "player": p})
	queue_trigger(PendingTrigger.new(null, passive_effects, passive_context))

## True when every effect of the passive is a random ally pick with no candidate, so firing it would
## only announce "ativou ..." and burn one of its uses for nothing.
func _passive_has_nobody_to_target(effects: Array, context: EffectContext) -> bool:
	if effects.is_empty():
		return false
	for effect: Effect in effects:
		var selector := effect.target as RandomTarget
		if selector == null or not selector.has_no_ally_candidates(context, effect):
			return false
	return true

## True when every effect of the passive is a "leaked" Momentum refund (Sobrecarga) and the refund
## comes to 0, so firing it would only show a pointless "ativou Sobrecarga".
func _passive_refunds_nothing(p: int, ability: Dictionary) -> bool:
	var effects: Array = ability["effects"]
	if effects.is_empty():
		return false
	for effect_data: Dictionary in effects:
		if effect_data.get("action", "") != "gain_momentum" or effect_data.get("per", "") != "leaked":
			return false
		var divisor := maxi(1, int(effect_data.get("divisor", 1)))
		var refund := mini(int(effect_data.get("max", MOMENTUM_CAP)), int(players[p]["leaked"]) / divisor)
		if refund > 0:
			return false
	return true

func _finish_turn() -> void:
	bus().emit(GameEvent.new("turn_ended", active))
	for c in players[active]["board"].duplicate():
		_fire(c, "on_turn_end")
	_fire_deck_effects(active, "on_turn_end")
	_check_state()
	if phase == "over":
		return
	reset_snowball_level(active)
	# Momentum above the normal cap was only a temporary overflow: it vanishes now, before it can bank
	if int(players[active]["momentum"]) > MOMENTUM_CAP:
		players[active]["momentum"] = MOMENTUM_CAP
		_refresh_scaling()
		_emit({"type": "momentum", "player": active})
	# Dona Gertrudes: the champions she borrowed from the hand leave the game now
	for p in players:
		for c: Card in p["board"].duplicate():
			if c.banish_at_turn_end:
				banish_unit(c)
	for p in players:
		for c in p["board"]:
			# Damage stays marked between turns. Temporary Vida soaked damage first, so when it
			# expires it takes that much damage away with it (a unit never dies from a buff ending).
			c.damage = maxi(0, c.damage - c.temp_hp)
			c.temp_hp = 0
			c.temp_atk = 0
			c.turn_armor = 0
			c.temp_critico = 0
			for kw in c.temp_keywords:
				c.keywords.erase(kw)
			c.temp_keywords.clear()
			for kw in c.lost_keywords: # a keyword taken away "this turn" comes back
				if not c.keywords.has(kw):
					c.keywords.append(kw)
			c.lost_keywords.clear()
			if c.spell_shield_until_end_turn:
				c.spell_shield = false
				c.spell_shield_until_end_turn = false
			if c.supreme_shield_expires == "end_turn":
				c.supreme_shield = false
				c.supreme_shield_expires = ""
			c.tide_mark = false
	# a free-standing artifact can hold a temporary Escudo Supremo too
	for relic_owner in players:
		for relic: Card in relic_owner["relics"]:
			if relic.supreme_shield_expires == "end_turn":
				relic.supreme_shield = false
				relic.supreme_shield_expires = ""
	# Congelada ends at the END of the turn after the one it was applied in, so that turn really felt it
	for q in players:
		for c: Card in q["board"]:
			if c.frozen > 0 and turn >= c.frozen:
				c.frozen = 0
				_emit({"type": "thaw", "uid": c.uid})
	# Rei Gelado: the frozen empty slots thaw at the END of their owner's turn, so that turn really felt them
	var ending: Dictionary = players[active]
	if int(ending["frozen_slots"]) > 0 and turn >= int(ending["frozen_slots_until"]):
		ending["frozen_slots"] = 0
		_emit({"type": "slots_thaw", "player": active})
	_emit({"type": "end_turn", "player": active})
	_start_turn(opponent(active), true)

func _start_turn(p: int, draw: bool) -> void:
	active = p
	priority = p
	summon_window = false
	_summon_pending = false
	skip_rest_of_turn = [false, false]
	turn += 1
	phase = "main"
	var pl: Dictionary = players[p]
	# Momentum that leaks past a full Reserva, after the opponent's turn too, is what really went
	# unspent (Voltexz and Fulgurvoltz get cheaper by it)
	var leaked: int = int(pl["reserve"]) + int(pl["momentum"]) - RESERVE_CAP
	pl["leaked"] = maxi(0, leaked) # Sobrecarga refunds part of it this turn
	pl["unspent"] = int(pl["momentum"]) # plain Momentum left from the last turn (Gigante Elétrico)
	if leaked > 0:
		pl["saved_momentum"] += leaked
		pl["idle_turns"] += 1
	pl["reserve"] = mini(RESERVE_CAP, int(pl["reserve"]) + int(pl["momentum"])) # bank what went unspent
	pl["max_momentum"] = min(MOMENTUM_CAP, pl["max_momentum"] + 1)
	pl["momentum"] = pl["max_momentum"]
	if p != first and turn <= SECOND_BONUS_TURNS * 2:
		# going second: on each of the first SECOND_BONUS_TURNS turns, +1 Momentum (this turn only)
		# and 1 Reserva refilled (never past the cap)
		pl["reserve"] = mini(RESERVE_CAP, int(pl["reserve"]) + 1)
		pl["momentum"] += 1
	for i in 2:
		var q: Dictionary = players[i]
		# once_per_turn: refreshed every turn, so instants can be used on either turn.
		# once_per_cycle: refreshed only when its owner's own turn starts.
		if i == p or not CardDB.leader(q["leader_id"])["ability"].get("once_per_cycle", false):
			q["ability_used"] = false
		q["passive_used"] = false
		q.erase("passive_uses")
	# remembered for the whole turn: a Leader ability with "blocked_after_debt" (Eryon's loan) cannot be
	# used on the turn its owner pays a Momentum debt, so the loan can't be rolled over forever
	pl["paid_debt_this_turn"] = int(pl["next_momentum"]) < 0
	if int(pl["next_momentum"]) != 0:
		# positive = Momentum promised for this turn; negative = a debt (Ritual do Degelo), never below 0
		pl["momentum"] = clampi(int(pl["momentum"]) + int(pl["next_momentum"]), 0, MOMENTUM_CAP)
		pl["next_momentum"] = 0
	pl["attacked"] = false
	pl["played_two"] = false
	pl["glacial_discount_used"] = false
	for c in pl["board"]:
		if c.temp_hp_until_next_turn > 0:
			c.damage = maxi(0, c.damage - c.temp_hp_until_next_turn)
			c.temp_hp_until_next_turn = 0
		if c.is_stunned(): # an Atordoada unit loses one marker instead of untapping
			c.stun_markers -= 1
			_emit({"type": "stun_tick", "uid": c.uid, "markers": c.stun_markers})
		elif not c.is_frozen(): # a Congelada unit stays tapped through this whole turn
			c.exhausted = false
		c.sick = false
		c.temp_armor = 0
		c.temp_atk_until_next_turn = 0
		if c.spell_shield_until_next_turn:
			c.spell_shield = false
			c.spell_shield_until_next_turn = false
		if c.supreme_shield_expires == "next_turn":
			c.supreme_shield = false
			c.supreme_shield_expires = ""
		for expiring_keyword in c.keywords_until_next_turn:
			c.keywords.erase(expiring_keyword)
		c.keywords_until_next_turn = []
		c.attacks_made = 0
	_emit({"type": "start_turn", "player": p, "turn": turn})
	_regenerate_all_units()
	_resolve_dot_markers(p)
	_resolve_condemned()
	bus().emit(GameEvent.new("turn_started", p))
	_fire_leader_passive(p, "on_turn_start")
	for c in pl["board"].duplicate():
		# A unit killed by its own periodic damage no longer gets a turn-start trigger.
		if find_unit(c.uid) != null:
			_fire(c, "on_turn_start")
	if draw:
		_draw(p, 1)
	_check_state()

## Regeneração: at the start of every turn (either player's) all the damage of each unit that has it is
## healed. It happens before the periodic markers and the turn-start triggers, so damage dealt at the end of
## the previous turn (Flor Voraz) is still on the unit while end-of-turn effects resolve, and damage that
## the new turn itself deals (markers, turn-start triggers) stays on the unit.
func _regenerate_all_units() -> void:
	for pl in players:
		for unit: Card in pl["board"]:
			if has_kw(unit, "regeneracao") and unit.damage > 0:
				var healed_amount: int = unit.damage
				unit.damage = 0
				_emit({"type": "heal", "uid": unit.uid, "amount": healed_amount, "regeneration": true, "hp_after": unit.hp_left()})

## Resolves every periodic marker on every unit controlled by p, and on p's Leader, at the start of that turn.
func _resolve_dot_markers(p: int) -> void:
	for unit: Card in players[p]["board"].duplicate():
		for dot_id in unit.dot_markers.keys().duplicate():
			resolve_dot(unit, String(dot_id))
	for dot_id in players[p]["leader_dots"].keys().duplicate():
		_resolve_leader_dot(p, String(dot_id))

## A Leader's markers hurt it for 3 damage per marker and then half the pile is removed. It is normal
## damage, so Câmara de Êxtase still applies. While its Veneno is held (see veneno_is_held) the
## markers hurt but none wear off.
func _resolve_leader_dot(p: int, dot_id: String) -> void:
	var markers := leader_dot_markers(p, dot_id)
	if markers <= 0:
		return
	var held := veneno_is_held(dot_id, LEADER_UID[p])
	var consumed := 0 if held else markers_consumed_per_tick(dot_id, markers)
	var damage := markers * VENENO_DAMAGE_PER_MARKER if dot_id == "veneno" else markers
	_emit({"type": "dot", "uid": LEADER_UID[p], "dot": dot_id, "amount": markers, "damage": damage, "total": markers - consumed, "cleared": true, "held": held})
	_deal_dot_damage(LEADER_UID[p], damage, dot_id)
	if held:
		return
	# markers added by a trigger during the damage above wait for the next turn
	var remaining := leader_dot_markers(p, dot_id) - consumed
	if remaining > 0:
		players[p]["leader_dots"][dot_id] = remaining
	else:
		players[p]["leader_dots"].erase(dot_id)

## How many markers wear off at one tick: Veneno loses half its pile, rounded up; the other kinds
## (Queimadura, Sangramento) lose all of them.
func markers_consumed_per_tick(dot_id: String, markers: int) -> int:
	if dot_id == "veneno":
		return ceili(float(markers) / 2.0)
	return markers

## True when the Veneno markers of `target_uid` (a unit, or a Leader's negative uid) are not consumed
## right now: either a Greve Geral dos Antídotos is running, or a Leader's own hold is.
func veneno_is_held(dot_id: String, target_uid: int) -> bool:
	if dot_id != "veneno":
		return false
	if turn <= veneno_held_until:
		return true
	var leader_player := LEADER_UID.find(target_uid)
	return leader_player >= 0 and turn <= int(players[leader_player]["leader_veneno_held_until"])

## Nobody's Veneno is consumed for the next `turn_starts` turn starts (of either player).
func hold_veneno_for_everyone(turn_starts: int) -> void:
	veneno_held_until = maxi(veneno_held_until, turn + turn_starts)
	_emit({"type": "veneno_hold", "player": -1, "turn_starts": turn_starts})

## The Veneno on the Leader of player `p` is not consumed for the next `turn_starts` turn starts of
## that Leader's controller.
func hold_veneno_on_leader(p: int, turn_starts: int) -> void:
	var first_turn_start := turn + (2 if p == active else 1)
	var until := first_turn_start + 2 * (turn_starts - 1)
	players[p]["leader_veneno_held_until"] = maxi(int(players[p]["leader_veneno_held_until"]), until)
	_emit({"type": "veneno_hold", "player": p, "turn_starts": turn_starts})

## Until the start of player `p`'s next turn, the Veneno tick of every poisoned unit deals damage equal to
## that unit's current Vida. The window closes right before the tick of `p`'s own next turn start, so
## when `p` casts it on their own turn it only reaches the opponent's turn start.
func make_veneno_lethal_until_next_turn_of(p: int) -> void:
	var next_turn_start := turn + (2 if p == active else 1)
	veneno_lethal_until = maxi(veneno_lethal_until, next_turn_start - 1)
	_emit({"type": "veneno_lethal", "player": p})

## Carries out every sentence that is due: a Condenada unit (on either board) dies when the turn
## number stored on it arrives. Indestrutível survives, but the mark is spent either way.
func _resolve_condemned() -> void:
	for player_index in 2:
		for unit: Card in players[player_index]["board"].duplicate():
			if not unit.is_condemned() or unit.condemned_turn > turn:
				continue
			unit.condemned_turn = 0
			if unit.has_kw("indestrutivel"):
				_emit({"type": "doom_resisted", "uid": unit.uid})
				continue
			unit.damage = 1000000
			_emit({"type": "doom", "uid": unit.uid})
	# Clear the dead right away, so a doomed unit gets no start-of-turn trigger.
	_check_state()

## Resolves one marker type. Only the markers present when this call starts are consumed;
## a new marker added by an on_damaged trigger remains for the next turn. Veneno loses half its
## pile, rounded up, and none while it is held (see veneno_is_held): the markers hurt and stay.
func resolve_dot(unit: Card, dot_id: String) -> void:
	if unit == null:
		return
	var markers := int(unit.dot_markers.get(dot_id, 0))
	if markers <= 0:
		return
	var damage := dot_damage(dot_id, unit, markers)
	var held := veneno_is_held(dot_id, unit.uid)
	var consumed := 0 if held else markers_consumed_per_tick(dot_id, markers)
	_emit({"type": "dot", "uid": unit.uid, "dot": dot_id, "amount": markers, "damage": damage, "total": markers - consumed, "cleared": true, "held": held})
	_deal_dot_damage(unit.uid, damage, dot_id)
	if held:
		return
	var remaining := int(unit.dot_markers.get(dot_id, 0)) - consumed
	if remaining > 0:
		unit.dot_markers[dot_id] = remaining
	else:
		unit.dot_markers.erase(dot_id)

## Calculates the damage for one periodic marker type without applying it.
func dot_damage(dot_id: String, unit: Card, markers: int) -> int:
	if unit == null or markers <= 0:
		return 0
	if dot_id == "veneno":
		var normal_damage := markers * VENENO_DAMAGE_PER_MARKER
		if turn <= veneno_lethal_until:
			# Neráxia's window: the tick takes all the Vida the unit has left (never less than the normal tick)
			return maxi(normal_damage, unit.hp_left())
		return normal_damage
	if DOT_RULES.get(dot_id, "flat") != "life_bracket":
		return markers
	var max_hp := unit.hp + unit.bonus_hp + unit.temp_hp + unit.temp_hp_until_next_turn
	var life_bonus := 0
	if max_hp >= 6 and max_hp <= 9:
		life_bonus = 1
	elif max_hp >= 10:
		life_bonus = 2 + floori((max_hp - 10) / 4)
	return markers + life_bonus

## Test helpers: apply one raw effect dictionary / run raw effect dictionaries as a trigger would.
func _apply_effect(player: int, effect_data: Dictionary, target_uid: int, source_card_id := "") -> void:
	var context := EffectContext.new(self, player, "")
	context.source_card_id = source_card_id
	EffectRegistry.parse(effect_data).apply_to(context, target_uid)

func _run_effect_dicts(player: int, effects: Array, trigger: String, chosen: int, self_uid: int, source_card_id := "") -> void:
	var context := EffectContext.new(self, player, trigger)
	context.chosen_target = chosen
	context.self_uid = self_uid
	context.source_card_id = source_card_id
	_run_effects(context, effects)
