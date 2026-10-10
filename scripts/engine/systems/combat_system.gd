class_name CombatSystem
extends RefCounted
## Combat: declaring attackers and blockers, the damage windows and the strike order.

var game: GameState

func _init(game_state: GameState) -> void:
	game = game_state

## attacks: Dictionary attacker_uid -> provoked enemy uid (0 when none).
func declare_attack(p: int, attacks: Dictionary) -> Array:
	if not game._sorcery_time(p) or game.players[p]["attacked"] or attacks.is_empty():
		return []
	var provoked_used: Array = []
	for uid in attacks:
		var c := game.find_unit(uid)
		if c == null or c.owner != p or not game.can_attack(c):
			return []
		var prov: int = attacks[uid]
		if prov != 0:
			var t := game.find_unit(prov)
			if not game.has_kw(c, "provocacao") or t == null or t.owner == p or provoked_used.has(prov) or game.is_frozen(t) or game.has_kw(t, "nao_bloqueia"):
				return []
			provoked_used.append(prov)
	game.attackers = attacks.duplicate()
	game.players[p]["attacked"] = true
	for uid in attacks:
		game.find_unit(uid).exhausted = true
	game._emit({"type": "attack", "player": p, "attackers": attacks.keys()})
	for uid in attacks:
		game._fire(game.find_unit(uid), "on_attack")
	game._check_state()
	if game.phase == "over":
		return game._flush()
	game.phase = "combat"
	game.stack_system().open_window("attack")
	game.stack_system().settle()
	return game._flush()

## blocks: Dictionary attacker_uid -> blocker_uid. One blocker per attacker,
## one attacker per blocker. Provoked units are forced onto their provoker.
## Provoked units must block their provoker (unless dead or frozen).
func forced_blocks() -> Dictionary:
	var final := {}
	for a in game.attackers:
		if game.attackers[a] != 0 and game.find_unit(game.attackers[a]) != null and not game.is_frozen(game.find_unit(game.attackers[a])):
			final[a] = game.attackers[a]
	return final

func declare_blocks(p: int, picks: Dictionary) -> Array:
	if game.phase != "blocks" or p != game.decider():
		return []
	var final := forced_blocks()
	var used: Array = final.values()
	for a in picks:
		if final.has(a):
			continue
		var b: int = picks[a]
		var att := game.find_unit(a)
		var blk := game.find_unit(b)
		if not game.attackers.has(a) or att == null or blk == null or blk.owner != p or used.has(b) or not game.can_block(blk, att):
			return []
		final[a] = b
		used.append(b)
	start_damage(final)
	game.stack_system().settle()
	return game._flush()

## Attackers that died during the windows leave combat.
func prune_attackers() -> void:
	for a in game.attackers.keys():
		if game.find_unit(a) == null:
			game.attackers.erase(a)

func to_blocks() -> void:
	game.window = ""
	prune_attackers()
	if game.attackers.is_empty():
		end_combat()
	elif game.players[game.opponent(game.active)]["board"].is_empty() or (game.auto_pass[game.opponent(game.active)] and not can_block_any()):
		start_damage(forced_blocks())
	else:
		game.phase = "blocks"

## Blocks are locked in, block triggers fire, then the damage window opens.
func start_damage(final: Dictionary) -> void:
	game.phase = "combat"
	game.blocks = final
	game._emit({"type": "blocks", "blocks": final})
	for a in final:
		game._fire(game.find_unit(final[a]), "on_block", a)
		game._fire(game.find_unit(a), "on_blocked", final[a])
	game._check_state()
	if game.phase == "over":
		game.attackers.clear()
		game.blocks.clear()
		return
	prune_attackers()
	if game.attackers.is_empty():
		end_combat()
		return
	game.stack_system().open_window("damage")

## Is there any attacker that some defending unit may legally block?
func can_block_any() -> bool:
	var forced := forced_blocks()
	for a in game.attackers:
		if forced.has(a):
			continue
		var att := game.find_unit(a)
		for blk in game.players[game.opponent(game.active)]["board"]:
			if not forced.values().has(blk.uid) and game.can_block(blk, att):
				return true
	return false

func end_combat() -> void:
	game.attackers.clear()
	game.blocks.clear()
	game.window = ""
	if game.phase != "over":
		game.phase = "main"
		game.priority = game.active

## Esquiva condition: by default the attacker has less ATK than the dodger. A card can override it with
## "esquiva": {"unless_keywords": [...]} = the attacker has none of those keywords.
func dodges(c: Card, source: Card) -> bool:
	var rule: Dictionary = c.data().get("esquiva", {})
	if rule.has("unless_keywords"):
		for kw in rule["unless_keywords"]:
			if source.has_kw(kw):
				return false
		return true
	return source.atk_total() < c.atk_total()

## When a combatant deals its combat damage: 1 = Hipervelocidade (attacking or blocking), 2 = Ataque Rápido
## (only as the attacker, and not against a blocker with Hipervelocidade), 3 = everyone else.
func strike_step(u: Card, other: Card, attacking: bool) -> int:
	if u.has_kw("hipervelocidade"):
		return 1
	if attacking and u.has_kw("ataque_rapido") and not (other != null and other.has_kw("hipervelocidade")):
		return 2
	return 3

## Dead attackers deal nothing; a blocked attacker whose blocker died hits nothing
## (Sobrepujança: all of it goes to the leader); a blocker whose attacker died deals nothing.
func resolve_combat() -> void:
	var defender := game.opponent(game.active)
	game.window = ""
	game._emit({"type": "combat_damage"})
	game._combat_damage = true
	prune_attackers()
	var pairs: Array = []
	for a in game.attackers:
		pairs.append([a, game.blocks.get(a, 0)])
	for step in [1, 2, 3]:
		for pair in pairs:
			var att := game.find_unit(pair[0])
			var blk: Card = game.find_unit(pair[1]) if pair[1] != 0 else null
			if att != null and strike_step(att, blk, true) == step:
				if pair[1] == 0:
					game._deal_damage(GameState.LEADER_UID[defender], game.atk_of(att), att)
				elif blk != null:
					var excess := game.atk_of(att) - game.hp_left(blk)
					game._deal_damage(blk.uid, game.atk_of(att), att)
					if game.has_kw(att, "sobrepujanca") and excess > 0:
						game._deal_damage(GameState.LEADER_UID[defender], excess, att)
				elif game.has_kw(att, "sobrepujanca"):
					game._deal_damage(GameState.LEADER_UID[defender], game.atk_of(att), att) # blocker already dead
			if blk != null and strike_step(blk, att, false) == step and att != null:
				game._deal_damage(att.uid, game.atk_of(blk), blk)
		game._check_state()
	# a Leader that drops to 0 mid-combat still takes the remaining strikes (overkill); the result is decided once, here
	game._combat_damage = false
	game._check_leaders()
	end_combat()
