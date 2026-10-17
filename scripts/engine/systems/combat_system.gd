class_name CombatSystem
extends RefCounted
## Combat: one attack at a time. Each ready unit taps to hit the enemy Leader's face or to
## challenge an enemy unit that is already tapped (exhausted). The challenged unit strikes back.
## Tapped enemy units do not guard the Leader: the face is always open, except to a Provocação, which
## is the only thing that forces a challenge. A Congelada Provocação doesn't force attacks into it.
##
## Flow of a combat:
##   1. "IR PARA O COMBATE" opens the "pre_combat" window: the attacker gets priority first, then the
##      defender; both may cast Rápido/Instantâneo. It ends when both pass in a row with an empty stack.
##   2. The "attacks" window: the attacker declares attacks one by one (nobody can respond),
##      until they press "ENCERRAR COMBATE" or no unit can attack anymore.

var game: GameState
## An attack whose Ao Atacar put something on the stack (a Bola de Neve): its combat damage waits
## until the stack is empty. {"attacker": uid, "target": uid}, or empty when no attack is waiting.
var pending_attack: Dictionary = {}
## Set by a "decoy" effect while an attack's triggers resolve (Hikari's Fantoche de Trapos): the unit that takes the
## attacker's blow instead of the challenged one, and the unit that takes the defender's counter-blow
## instead of the attacker. 0 = nobody. Read once by attack() and then cleared.
var redirect_hit_to := 0
var redirect_counter_to := 0

func _init(game_state: GameState) -> void:
	game = game_state

## Opens the pre-combat window (the attacker holds priority first).
func start_combat(player: int) -> void:
	game.phase = "combat"
	game.stack_passed = false
	game._emit({"type": "combat_step", "player": player})
	game.stack_system().open_window("pre_combat")

## Both players passed in a row with an empty stack: the attacks begin.
func start_attacks() -> void:
	game.stack_system().open_window("attacks")
	if not has_any_attacker():
		end_combat()

## True while the active player still has a unit that can attack something.
func has_any_attacker() -> bool:
	for unit: Card in game.players[game.active]["board"]:
		if game.can_attack(unit):
			return true
	return false

## Can `attacker` challenge `target`? The target must be an enemy unit that is tapped, and the
## attacker must be able to reach it:
##   Voo: only an attacker with Voo or Longo Alcance can challenge it.
##   Furtividade: only an attacker with Furtividade or Vigilância can challenge it.
##   Intimidação: an attacker with ATK 3 or less cannot challenge it.
##   Obsessão: the attacker may only hit the Leader, except that a tapped Provocação still stops it
##     (it can challenge only Provocação units, and then must).
##   Rompante (the turn it enters): it goes for the Leader and may only challenge a Provocação.
##   Etérea: nothing can ever challenge it (not even when it has Provocação).
func can_challenge(attacker: Card, target: Card) -> bool:
	if attacker == null or target == null or target.owner == attacker.owner or not target.exhausted:
		return false
	if game.has_kw(attacker, "obsessao") and not game.has_kw(target, "provocacao"):
		return false
	if is_rompante_rush(attacker) and not game.has_kw(target, "provocacao"):
		return false
	if game.has_kw(target, "eterea"):
		return false
	if game.has_kw(target, "voo") and not (game.has_kw(attacker, "voo") or game.has_kw(attacker, "longo_alcance")):
		return false
	if game.has_kw(target, "furtividade") and not (game.has_kw(attacker, "furtividade") or game.has_kw(attacker, "vigilancia")):
		return false
	if game.has_kw(target, "intimidacao") and game.atk_of(attacker) <= GameState.INTIMIDATE_ATK:
		return false
	return true

## Rompante: on the turn it enters, the unit can hit the enemy Leader (Ímpeto can only challenge) and
## cannot challenge ordinary tapped units. A tapped Provocação still stops it (it must challenge that
## one), so a taunt is always an answer to a Rompante finisher. From the next turn on it is a normal unit.
func is_rompante_rush(attacker: Card) -> bool:
	return attacker.sick and game.has_kw(attacker, "rompante")

## The tapped enemy Provocação units this attacker is able to challenge. When the list is not
## empty, the attacker must challenge one of them (it cannot hit the Leader or another unit).
## A Congelada Provocação forces nothing.
func forced_taunts(attacker: Card) -> Array:
	var out: Array = []
	for enemy_unit: Card in game.players[game.opponent(attacker.owner)]["board"]:
		if game.has_kw(enemy_unit, "provocacao") and not enemy_unit.is_frozen() and can_challenge(attacker, enemy_unit):
			out.append(enemy_unit.uid)
	return out

## The tapped enemy units this attacker is able to challenge (any of them, Provocação or not).
func challengeable_units(attacker: Card) -> Array:
	var out: Array = []
	for enemy_unit: Card in game.players[game.opponent(attacker.owner)]["board"]:
		if can_challenge(attacker, enemy_unit):
			out.append(enemy_unit.uid)
	return out

## Every target this attacker may legally hit right now: uids of units it can challenge and/or
## the enemy Leader's uid (negative). Empty when it cannot attack at all (or has nothing to hit).
## Order of the rules:
##   1. a tapped (not Congelada) Provocação it can challenge: only those;
##   2. otherwise the challengeable units (any tapped enemy unit) and the enemy Leader's face.
func attack_targets(attacker: Card) -> Array:
	if attacker == null or not game.can_attack(attacker):
		return []
	var taunts := forced_taunts(attacker)
	if not taunts.is_empty():
		return taunts
	var challengeable := challengeable_units(attacker)
	var enemy_leader: int = GameState.LEADER_UID[game.opponent(attacker.owner)]
	# Ímpeto lets a unit attack the turn it enters, but only to challenge: the Leader's face
	# waits until its next turn (otherwise Ímpeto would be free damage now that nobody blocks).
	# Rompante is the opposite: the Leader is its target on the turn it enters (only a Provocação,
	# handled above, holds it back).
	if not attacker.sick or is_rompante_rush(attacker):
		return challengeable + [enemy_leader]
	return challengeable

## True while `player` may declare an attack (their own "attacks" window, nothing pending).
func in_attacks_window(player: int) -> bool:
	return game.phase == "combat" and game.window == "attacks" and player == game.active \
		and game.priority == player and game.stack.is_empty()

## One attack: `attacker_uid` taps and hits `target_uid` (a negative uid = the enemy Leader's face,
## otherwise a challenged enemy unit). Everything resolves at once; nobody can respond.
func attack(player: int, attacker_uid: int, target_uid: int) -> Array:
	if not in_attacks_window(player):
		return []
	var attacker := game.find_unit(attacker_uid)
	if attacker == null or attacker.owner != player or not attack_targets(attacker).has(target_uid):
		return []
	var defender_unit: Card = game.find_unit(target_uid) if target_uid > 0 else null
	attacker.exhausted = true # it stays tapped between the two attacks of Ataque Duplo too
	attacker.attacks_made += 1
	var target_card_id := defender_unit.card_id if defender_unit != null else String(CardDB.leader(game.players[game.opponent(player)]["leader_id"]).get("legendary", ""))
	game._emit({"type": "attack", "player": player, "attacker": attacker_uid, "target": target_uid, "attacker_card_id": attacker.card_id, "target_card_id": target_card_id})
	redirect_hit_to = 0
	redirect_counter_to = 0
	# triggers: Ao Atacar always; Ao Desafiar / Ao Ser Desafiada only when a unit is challenged
	game._fire(attacker, "on_attack", target_uid if defender_unit != null else 0)
	if defender_unit != null:
		game._fire(attacker, "on_challenge", target_uid)
		game._fire(defender_unit, "on_challenged", attacker_uid)
	game._check_state()
	# a decoy summoned by the triggers above takes the blow (and/or the counter-blow) instead
	var struck_uid := target_uid
	if redirect_hit_to != 0 and game.find_unit(redirect_hit_to) != null:
		struck_uid = redirect_hit_to
	pending_attack = {"attacker": attacker_uid, "target": struck_uid, "counter_to": redirect_counter_to}
	redirect_hit_to = 0
	redirect_counter_to = 0
	finish_pending_attack() # does nothing yet when the triggers left something on the stack
	game.stack_system().settle()
	return game._flush()

## The attack's combat damage and the end of combat once no attacker is left. Waits while the stack
## is not empty: whatever the attack's triggers cast resolves (or is countered) before the blows land.
func finish_pending_attack() -> void:
	if pending_attack.is_empty() or not game.stack.is_empty():
		return
	var attack_info := pending_attack
	pending_attack = {}
	if game.phase == "over":
		return
	_exchange_damage(int(attack_info["attacker"]), int(attack_info["target"]), int(attack_info.get("counter_to", 0)))
	if game.phase != "over" and not has_any_attacker():
		end_combat()

## The attacker and its target deal their combat damage in Rapidez order: the faster one strikes
## first, equal Rapidez strike at the same time. A unit that is already dead (a trigger above or the
## faster strike may have killed it) deals nothing. Hitting the Leader takes nothing back.
## `counter_uid` (a decoy on the attacker's side) takes the defender's counter-blow instead of the attacker.
func _exchange_damage(attacker_uid: int, target_uid: int, counter_uid := 0) -> void:
	var defending_player := game.opponent(game.active)
	game._emit({"type": "combat_damage"})
	game._combat_damage = true
	for step in STRIKE_STEPS:
		var attacker := game.find_unit(attacker_uid)
		if attacker == null:
			break
		if target_uid < 0:
			if strike_step(attacker) == step:
				game._deal_damage(target_uid, _blow_damage(attacker, target_uid), attacker)
			continue
		var defender_unit := game.find_unit(target_uid)
		if strike_step(attacker) == step:
			if defender_unit != null:
				var blow := _blow_damage(attacker, defender_unit.uid)
				var excess := blow - game.hp_left(defender_unit)
				game._deal_damage(defender_unit.uid, blow, attacker)
				if game.has_kw(attacker, "sobrepujanca") and excess > 0:
					game._deal_damage(GameState.LEADER_UID[defending_player], excess, attacker)
			elif game.has_kw(attacker, "sobrepujanca"):
				var leader_uid: int = GameState.LEADER_UID[defending_player]
				game._deal_damage(leader_uid, _blow_damage(attacker, leader_uid), attacker) # target already dead
		defender_unit = game.find_unit(target_uid)
		attacker = game.find_unit(attacker_uid)
		if defender_unit != null and attacker != null and strike_step(defender_unit) == step:
			var counter_victim := game.find_unit(counter_uid) if counter_uid > 0 else null
			if counter_victim == null:
				counter_victim = attacker
			game._deal_damage(counter_victim.uid, _blow_damage(defender_unit, counter_victim.uid), defender_unit)
		game._check_state()
	# a Leader that drops to 0 still takes the remaining strikes (overkill); the result is decided once, here
	game._combat_damage = false
	game._check_state()
	game._check_leaders()

## Crítico: every level is this much chance (in percent) that a blow is critical; level 4 is certain.
const CRITICO_CHANCE_PER_LEVEL := 25
## A critical blow adds this much damage (a card can set its own with "critico_maximo" at level 4).
const CRITICO_BONUS := 2

## The damage of one blow: the striker's ATK, plus the Crítico bonus when the roll succeeds.
## The bonus is added before Armadura and Escudo (they work on the final number). A defender with
## "imune_critico" (Rália's Desdém) cancels the critical: no bonus, and nothing grows.
func _blow_damage(striker: Card, target_uid: int) -> int:
	var damage := game.strike_power_of(striker) # a Pacifista deals 0 (and a critical never adds to a zero blow)
	var level := striker.critico_total()
	if level <= 0 or damage <= 0:
		return damage
	# level 4 is certain and never touches the random generator
	if level < 4 and game.rng.randi_range(1, 100) > level * CRITICO_CHANCE_PER_LEVEL:
		return damage
	var target := game.find_unit(target_uid) if target_uid > 0 else null
	if target != null and target.data().get("imune_critico", false):
		game._emit({"type": "crit_negated", "uid": target.uid})
		return damage
	game._emit({"type": "crit", "uid": striker.uid})
	var bonus := CRITICO_BONUS
	if level >= 4:
		bonus = int(striker.data().get("critico_maximo", {}).get("bonus", CRITICO_BONUS))
	# "critico_growth" (Vael): every critical blow raises his Crítico one level, up to 4, for ALL his copies
	# (hand, deck, field... and future ones, see GameState.grow_critico); the temporary levels don't count
	if striker.data().get("critico_growth", false) and striker.critico < 4:
		game.grow_critico(striker)
		game._emit({"type": "critico_up", "uid": striker.uid, "level": striker.critico_total()})
	return damage + bonus

## Leaves combat: back to the Main Phase, no more attacks this turn.
func end_combat() -> void:
	game.window = ""
	game.stack_passed = false
	if game.phase != "over":
		# a deck search opened by this attack (Bruno hitting the Leader) must stay open: the player
		# answers it first and the game then returns to the Main Phase
		if game.phase == "search":
			game._search_return = "main"
		else:
			game.phase = "main"
		game.priority = game.active
		game.players[game.active]["attacked"] = true
		game._emit({"type": "combat_end", "player": game.active})

## Esquiva condition (once per turn): by default the other unit has less Rapidez than the dodger.
## A card can override it with "esquiva": {"max_rapidez": N} = the other unit has Rapidez N or less.
func dodges(c: Card, source: Card) -> bool:
	var rule: Dictionary = c.data().get("esquiva", {})
	if rule.has("max_rapidez"):
		return source.rapidez_total() <= int(rule["max_rapidez"])
	return source.rapidez_total() < c.rapidez_total()

## Will `defender` get to hurt `attacker` with its counter-blow when `attacker` challenges it? No when it
## deals 0 damage, or when the attacker strikes strictly first (more Rapidez) and the blow surely kills it
## (Escudo, Esquiva, Indestrutível and Armadura are taken into account; a Crítico only adds damage, so it is
## ignored). Used by the Decoy of Hikari so it is only summoned when there is a counter-blow to dodge.
func defender_will_counter(attacker: Card, defender: Card) -> bool:
	if game.strike_power_of(defender) <= 0:
		return false
	if strike_step(attacker) <= strike_step(defender):
		return true
	if game.has_kw(defender, "indestrutivel") or defender.shield:
		return true
	if game.has_kw(defender, "esquiva") and defender.dodge_turn != game.turn and dodges(defender, attacker):
		return true
	var blow := game.damage_after_armor(defender, game.strike_power_of(attacker))
	return blow < game.hp_left(defender)

## The strike steps of one combat, fastest first (Rapidez 3 down to 0).
const STRIKE_STEPS := [3, 2, 1, 0]

## The step at which a combatant deals its combat damage: its Rapidez.
func strike_step(unit: Card) -> int:
	return unit.rapidez_total()
