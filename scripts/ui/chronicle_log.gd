class_name ChronicleLog
extends RefCounted
## The match history: every engine event becomes a text line plus a structured entry (icon, accent,
## actor, source and target cards) that the Chronicle list and scene draw as ChronicleRow nodes.
## Main (`host`) keeps the drawing; this keeps the data and turns events into entries.

## The Main node, asked for player and card names and for the running game.
var host

## Plain text lines, kept as a fallback when no structured entry exists yet.
var log_lines: Array = []
## Structured visual history (newest last, capped at 120).
var chronicle_entries: Array = []
## The visual description of the event being logged right now; every `_log` call inside it uses it.
var _chronicle_visual_context: Dictionary = {}
## Every Chronicle entry gets a number, so a row can be found again after a redraw.
var _chronicle_next_seq := 1

## Read-only mirror of Main's running game, so the moved code keeps reading `g` as before.
var g: GameState:
	get: return host.g

func _init(host_node) -> void:
	host = host_node

## Player name as the Chronicle shows it ("Você", "IA", "J1"...). Main decides it (online / AI).
func _pname(p: int) -> String:
	return host._pname(p)

func _cname(id: String) -> String:
	return host._cname(id)

func _log(t: String) -> void:
	log_lines.append(t)
	var entry := _chronicle_visual_context.duplicate(true)
	entry["text"] = t
	if not entry.has("kind"):
		entry["kind"] = "info"
	if not entry.has("icon"):
		entry["icon"] = "·"
	if not entry.has("accent"):
		entry["accent"] = UITheme.GOLD
	if not entry.has("label"):
		entry["label"] = "EVENTO"
	if not entry.has("turn") and g != null:
		entry["turn"] = g.turn
	entry["seq"] = _chronicle_next_seq
	_chronicle_next_seq += 1
	chronicle_entries.append(entry)
	if chronicle_entries.size() > 120:
		chronicle_entries.pop_front()

func _chronicle_card_id_for_uid(uid: int) -> String:
	if g == null or uid == 0:
		return ""
	if uid < 0:
		return _chronicle_leader_card_id(GameState.LEADER_UID.find(uid))
	var unit := g.find_unit(uid)
	return "" if unit == null else unit.card_id

## The Leader is not a card of the database (and not its Incarnation either): the Chronicle names it
## "leader:<id>", and the row and the scene draw the Leader's own art for it.
func _chronicle_leader_card_id(player: int) -> String:
	if g == null or player < 0 or player >= g.players.size():
		return ""
	return ChronicleRow.LEADER_ID_PREFIX + String(g.players[player]["leader_id"])

func _chronicle_name_for_uid(uid: int) -> String:
	if uid < 0:
		return "O Líder de %s" % _pname(GameState.LEADER_UID.find(uid))
	var unit := g.find_unit(uid)
	return "uma unidade" if unit == null else _cname(unit.card_id)

func _chronicle_add_target(out: Dictionary, uid: int) -> void:
	if uid == 0:
		return
	var card_id := _chronicle_card_id_for_uid(uid)
	if card_id != "":
		out["target_card_ids"].append(card_id)

func _chronicle_accent(kind: String, dot_id := "") -> Color:
	if kind == "dot":
		return CardView.dot_badge_color(dot_id)
	return {
		"play": Color("#f3c969"), "resolve": Color("#d9b7ff"), "ability": Color("#c07bff"),
		"passive": Color("#c07bff"), "trigger": Color("#ff9a4a"), "attack": Color("#ffb45c"),
		"damage": Color("#ff5d5d"), "heal": Color("#62e58d"), "death": Color("#b8aabf"),
		"destroy": Color("#b8aabf"), "death_ward_armed": Color("#72e7ff"), "death_prevented": Color("#72e7ff"),
		"countered": Color("#c9a8ff"), "fizzle": Color("#c9a8ff"),
		"start_turn": Color("#d9b86d"), "transform": Color("#74d7ff")
	}.get(kind, Color("#8d849c"))

## The short title a Chronicle row shows above its sentence.
func _chronicle_label(kind: String) -> String:
	return {
		"play": "JOGADA", "resolve": "RESOLUÇÃO", "ability": "HABILIDADE", "passive": "PASSIVA",
		"trigger": "GATILHO", "attack": "ATAQUE", "damage": "DANO", "heal": "CURA", "death": "MORTE",
		"destroy": "DESTRUIÇÃO", "dot": "STATUS", "countered": "ANULADA", "fizzle": "SEM EFEITO",
		"start_turn": "TURNO", "transform": "TRANSFORMAÇÃO", "summon": "INVOCAÇÃO", "enter_from_deck": "INVOCAÇÃO",
		"relic_enter": "RELÍQUIA", "revive": "RETORNO", "return_to_hand": "DE VOLTA À MÃO",
		"card_created": "CRIAÇÃO", "search_take": "BUSCA", "leader_executed": "EXECUÇÃO",
		"shield_break": "ESCUDO", "magic_shield_break": "ESCUDO", "supreme_shield_break": "ESCUDO", "freeze": "CONGELADA", "thaw": "DEGELO",
		"exhaust": "EXAUSTÃO", "stun": "ATORDOADA", "stun_tick": "ATORDOADA", "shrink": "ENCOLHIMENTO", "dodge": "ESQUIVA", "reflect": "REFLEXO", "condemn": "CONDENADA",
		"doom": "SENTENÇA", "doom_resisted": "RESISTIU", "fatigue": "FADIGA", "ban": "BANIMENTO",
		"concede": "DESISTÊNCIA", "enter_tapped": "PROVOCAÇÃO", "death_ward_armed": "BALUARTE",
		"death_prevented": "BALUARTE"
	}.get(kind, "EVENTO")

## Which player did the event (-1 when it can't be told): the event says it, or the card behind it belongs to someone.
func _chronicle_actor(e: Dictionary) -> int:
	if e.has("player"):
		return int(e["player"])
	# damage, healing, statuses: whoever caused it (the hit card's owner is not the one acting)
	var uid_keys := ["src"] if e.has("src") else ["attacker", "uid"]
	for uid_key in uid_keys:
		var uid := int(e.get(uid_key, 0))
		if uid < 0:
			return GameState.LEADER_UID.find(uid)
		if uid > 0 and g != null:
			var unit := g.find_unit(uid)
			if unit != null:
				return unit.owner
	return -1

func _chronicle_icon(kind: String) -> String:
	return {
		"play": "▶", "resolve": "✦", "ability": "✦", "passive": "✦", "trigger": "⚡",
		"attack": "⚔", "damage": "−", "heal": "+", "death": "×", "destroy": "×",
		"dot": "•", "start_turn": "◷", "transform": "↻", "countered": "⊘", "fizzle": "⊘",
		"death_ward_armed": "◇", "death_prevented": "◇"
	}.get(kind, "·")

## Converts a raw engine event into the visual relationship shown by ChronicleRow.
## The event still supplies the prose through _log_event; this only supplies its art and direction.
func _chronicle_visual_for_event(e: Dictionary) -> Dictionary:
	var kind := String(e.get("type", "info"))
	var out := {"kind": kind, "icon": _chronicle_icon(kind), "accent": _chronicle_accent(kind, String(e.get("dot", ""))),
		"label": _chronicle_label(kind), "source_card_id": "", "target_card_ids": [], "amount": 0,
		"turn": int(e.get("turn", g.turn if g != null else 0))}
	var actor := _chronicle_actor(e)
	out["actor"] = actor
	out["actor_name"] = _pname(actor) if actor >= 0 else ""
	if kind == "damage" or kind == "fatigue":
		out["amount"] = -int(e.get("amount", 0))
	elif kind == "heal":
		out["amount"] = int(e.get("amount", 0))
	elif kind == "dot" and e.has("damage"):
		out["amount"] = -int(e["damage"])
	# how much life the target was left with after this damage / healing (shown beside the amount)
	if (kind == "damage" or kind == "heal") and e.has("hp_after"):
		out["hp_after"] = maxi(0, int(e["hp_after"]))
	match kind:
		"play", "resolve", "fizzle", "countered":
			out["source_card_id"] = String(e.get("card_id", ""))
			_chronicle_add_target(out, int(e.get("target", 0)))
			_chronicle_add_target(out, int(e.get("target2", 0)))
		"ability", "passive":
			out["source_card_id"] = _chronicle_leader_card_id(int(e.get("player", 0)))
			_chronicle_add_target(out, int(e.get("target", 0)))
		"trigger":
			out["source_card_id"] = String(e.get("card_id", ""))
			_chronicle_add_target(out, int(e.get("target", 0)))
		"attack":
			out["source_card_id"] = String(e.get("attacker_card_id", ""))
			if out["source_card_id"] == "":
				out["source_card_id"] = _chronicle_card_id_for_uid(int(e.get("attacker", 0)))
			# an attack on the Leader: the event carries the Incarnation's id, but the target is the Leader
			if int(e.get("target", 0)) < 0:
				_chronicle_add_target(out, int(e["target"]))
			elif String(e.get("target_card_id", "")) != "":
				out["target_card_ids"].append(String(e["target_card_id"]))
			else:
				_chronicle_add_target(out, int(e.get("target", 0)))
		"damage", "heal", "shield_break", "magic_shield_break", "supreme_shield_break", "freeze", "exhaust", "dodge", "dot", "destroy", "death", "condemn", "doom", "doom_resisted", "thaw":
			out["source_card_id"] = _chronicle_card_id_for_uid(int(e.get("src", 0)))
			if kind in ["death", "destroy"] and String(e.get("card_id", "")) != "":
				out["target_card_ids"].append(String(e["card_id"]))
			else:
				_chronicle_add_target(out, int(e.get("uid", 0)))
		"reflect":
			out["source_card_id"] = _chronicle_card_id_for_uid(int(e.get("uid", 0)))
			_chronicle_add_target(out, int(e.get("target", 0)))
		"transform":
			out["source_card_id"] = String(e.get("from", ""))
			if String(e.get("card_id", "")) != "":
				out["target_card_ids"].append(String(e["card_id"]))
		"leader_executed":
			_chronicle_add_target(out, GameState.LEADER_UID[int(e.get("player", 0))])
		"death_ward_armed":
			out["source_card_id"] = String(e.get("card_id", ""))
			_chronicle_add_target(out, int(e.get("uid", 0)))
		"death_prevented":
			out["source_card_id"] = String(e.get("ward_card_id", ""))
			if String(e.get("card_id", "")) != "":
				out["target_card_ids"].append(String(e["card_id"]))
		"summon", "relic_enter", "enter_from_deck", "revive", "return_to_hand", "card_created", "search_take":
			out["source_card_id"] = String(e.get("card_id", ""))
	return out

func _log_event(e: Dictionary) -> void:
	_chronicle_visual_context = _chronicle_visual_for_event(e)
	match e["type"]:
		"play":
			if e.get("subito", false):
				_log("%s invocou %s com Súbito" % [_pname(e["player"]), _cname(e["card_id"])])
			elif e.has("source_uid"):
				var caster_unit := g.find_unit(int(e["source_uid"]))
				_log("%s lançou %s%s" % [_pname(e["player"]), _cname(e["card_id"]), "" if caster_unit == null else " com " + _cname(caster_unit.card_id)])
			else:
				_log("%s jogou %s%s" % [_pname(e["player"]), _cname(e["card_id"]), " (Réquiem)" if e.get("requiem", false) else ""])
		"ability":
			_log("%s usou %s" % [_pname(e["player"]), CardDB.leader(g.players[e["player"]]["leader_id"])["ability"]["name"]])
		"transform":
			_log("%s transformou %s em %s" % [_pname(e["player"]), _cname(e["from"]), _cname(e["card_id"])])
		"passive":
			_log("%s ativou %s" % [_pname(e["player"]), CardDB.leader(g.players[e["player"]]["leader_id"])["ability"]["name"]])
		"shout":
			_log("%s: “%s”" % [_cname(e["card_id"]), e["text"]])
		"trigger":
			var trg: Dictionary = CardDB.data()["triggers"].get(e["trigger"], {})
			_log("%s: %s" % [_cname(e["card_id"]), trg.get("name", e["trigger"])])
		"resolve":
			var resolved_name := _cname(String(e.get("card_id", ""))) if String(e.get("card_id", "")) != "" else "a habilidade do Líder"
			_log("%s resolveu" % resolved_name)
		"attack":
			var attacker := g.find_unit(e["attacker"])
			var attacker_name := _cname(String(e["attacker_card_id"])) if attacker == null and e.get("attacker_card_id", "") != "" else ("uma unidade" if attacker == null else _cname(attacker.card_id))
			if int(e["target"]) < 0:
				_log("%s atacou o Líder com %s" % [_pname(e["player"]), attacker_name])
			else:
				var challenged := g.find_unit(e["target"])
				var target_name := _cname(String(e["target_card_id"])) if challenged == null and e.get("target_card_id", "") != "" else ("uma unidade" if challenged == null else _cname(challenged.card_id))
				_log("%s desafiou %s com %s" % [_pname(e["player"]), target_name, attacker_name])
		"enter_tapped":
			if e["tapped"]:
				var tapped_unit := g.find_unit(e["uid"])
				_log("%s entrou exaurida (Provocação)" % ("Uma unidade" if tapped_unit == null else _cname(tapped_unit.card_id)))
		"heal":
			if e.get("regeneration", false):
				var regenerated := g.find_unit(e["uid"])
				if regenerated != null:
					_log("%s regenerou %d" % [_cname(regenerated.card_id), e["amount"]])
			else:
				_log("%s recuperou %d de Vida" % [_chronicle_name_for_uid(int(e["uid"])), int(e["amount"])])
		"damage":
			_log("%s sofreu %d de dano" % [_chronicle_name_for_uid(int(e["uid"])), int(e["amount"])])
		"death":
			_log("%s morreu" % (_cname(String(e["card_id"])) if e.get("card_id", "") != "" else _chronicle_name_for_uid(int(e.get("uid", 0)))))
		"leader_executed":
			_log("O Líder de %s foi executado!" % _pname(e["player"]))
		"concede":
			host.conceded = e["player"]
			_log("%s desistiu da partida" % _pname(e["player"]))
		"fatigue":
			_log("%s: fadiga %d" % [_pname(e["player"]), e["amount"]])
		"start_turn":
			_log("— Turno %d: %s —" % [e["turn"], _pname(e["player"])])
			if int(e["turn"]) == 1:
				host._first_banner(e["player"])
		"extra_turn_promised":
			_log("%s vai jogar um turno extra!" % _pname(e["player"]))
		"ban":
			_log("%s baniu uma carta da mão" % _pname(e["player"]))
		"search_reveal":
			if e.get("private", false):
				# the options of a deck search stay secret; only the card taken is announced (search_take)
				if int(e.get("looked", 0)) > 0:
					_log("%s olhou as %d cartas do topo do deck" % [_pname(e["player"]), int(e["looked"])])
				else:
					_log("%s procurou uma carta no deck" % _pname(e["player"]))
			else:
				var names: Array = []
				for c in e["cards"]:
					names.append(_cname(c["card_id"]))
				_log("%s revelou: %s" % [_pname(e["player"]), ", ".join(names)])
		"look_top":
			if e.get("from_bottom", false):
				_log("%s olhou %d cartas do fundo do deck" % [_pname(e["player"]), e["cards"].size()])
			else:
				_log("%s olhou as %d cartas do topo do deck" % [_pname(e["player"]), e["cards"].size()])
		"look_bottom":
			_log("%s colocou as outras no fundo do deck" % _pname(e["player"]))
		"search_shuffle":
			_log("%s embaralhou o deck" % _pname(e["player"]))
		"mill":
			var milled: Array = []
			for cid in e["cards"]:
				milled.append(_cname(cid))
			_log("Do deck de %s ao cemitério: %s" % [_pname(e["player"]), ", ".join(milled)])
		"reflect":
			var mirror := g.find_unit(e["uid"])
			_log("%s refletiu %d de dano" % ["Uma unidade" if mirror == null else _cname(mirror.card_id), int(e["amount"])])
		"revive":
			_log("%s reviveu %s" % [_pname(e["player"]), _cname(e["card_id"])])
		"return_to_hand":
			_log("%s voltou para a mão de %s" % [_cname(e["card_id"]), _pname(e["player"])])
		"relic_enter":
			_log("%s colocou %s em campo" % [_pname(e["player"]), _cname(e["card_id"])])
		"summon":
			_log("%s invocou %s" % [_pname(e["player"]), _cname(e["card_id"])])
		"relic_destroyed":
			_log("%s foi destruído" % _cname(e["card_id"]))
		"durability_lost":
			_log("%s perdeu 1 de Durabilidade (restam %d)" % [_cname(e["card_id"]), int(e["left"])])
		"death_ward_armed":
			_log("%s foi armado: a próxima morte de uma unidade será negada" % _cname(e["card_id"]))
		"death_prevented":
			_log("%s foi destruído para impedir a morte de %s" % [_cname(e["ward_card_id"]), _cname(e["card_id"])])
		"fuse":
			_log("%d fichas se fundiram em %s" % [int(e["count"]), _cname(e["card_id"])])
		"attach":
			_log("%s foi equipado em uma unidade" % _cname(e["card_id"]))
		"equipment_returned":
			_log("%s voltou para a mão (a unidade foi reequipada)" % _cname(e["card_id"]))
		"equipment_break":
			_log("%s foi ao cemitério com a unidade equipada" % _cname(e["card_id"]))
		"destroy":
			var destroyed := g.find_unit(e["uid"])
			_log("%s foi destruída" % ("Uma unidade" if destroyed == null else _cname(destroyed.card_id)))
		"banish":
			_log("%s foi banida" % _cname(e["card_id"]))

		"sacrifice":
			var sacrificed := g.find_unit(e["uid"])
			_log("%s sacrificou %s" % [_pname(e["player"]), "uma unidade" if sacrificed == null else _cname(sacrificed.card_id)])
		"freeze":
			var frozen := g.find_unit(e["uid"])
			_log("%s foi congelada" % ("Uma unidade" if frozen == null else _cname(frozen.card_id)))
		"stun":
			_log("%s foi atordoada" % _chronicle_name_for_uid(int(e["uid"])))
		"stun_tick":
			_log("%s se recupera do atordoamento (%d marcador(es) restante(s))" % [_chronicle_name_for_uid(int(e["uid"])), int(e["markers"])])
		"shrink":
			_log("%s foi encolhida (-%d Ataque, -%d Vida)" % [_chronicle_name_for_uid(int(e["uid"])), int(e["atk"]), int(e["hp"])])
		"shield_break":
			_log("%s perdeu o Escudo" % _chronicle_name_for_uid(int(e["uid"])))
		"dodge":
			_log("%s esquivou do ataque" % _chronicle_name_for_uid(int(e["uid"])))
		"dot":
			var dotted := g.find_unit(e["uid"])
			var dot_names := {"queimadura": "Queimadura", "veneno": "Veneno", "sangramento": "Sangramento"}
			var dotted_name := "Uma unidade" if dotted == null else _cname(dotted.card_id)
			if int(e["uid"]) < 0: # a Leader holds the markers
				dotted_name = "O Líder de %s" % _pname(GameState.LEADER_UID.find(int(e["uid"])))
			if e.get("cleared", false):
				_log("%s sofreu %d de %s%s" % [dotted_name, int(e.get("damage", e.get("amount", 0))), dot_names.get(String(e.get("dot", "")), "status"), " (marcadores mantidos)" if e.get("held", false) else ""])
			else:
				_log("%s recebeu %d marcador(es) de %s" % [dotted_name, int(e.get("amount", 0)), dot_names.get(String(e.get("dot", "")), "status")])
		"dot_immune":
			var immune_unit := g.find_unit(e["uid"])
			var immune_name := "Uma unidade" if immune_unit == null else _cname(immune_unit.card_id)
			if int(e["uid"]) < 0:
				immune_name = "O Líder de %s" % _pname(GameState.LEADER_UID.find(int(e["uid"])))
			_log("%s é imune a %s" % [immune_name, {"queimadura": "Queimadura", "veneno": "Veneno", "sangramento": "Sangramento", "congelar": "Congelamento"}.get(String(e.get("dot", "")), "esse status")])
		"condemn":
			var condemned := g.find_unit(e["uid"])
			_log("%s foi condenada" % ("Uma unidade" if condemned == null else _cname(condemned.card_id)))
		"doom":
			var doomed := g.find_unit(e["uid"])
			_log("%s foi ceifada pela condenação" % ("Uma unidade" if doomed == null else _cname(doomed.card_id)))
		"doom_resisted":
			var resisted := g.find_unit(e["uid"])
			_log("%s resistiu à condenação" % ("Uma unidade" if resisted == null else _cname(resisted.card_id)))
		"exhaust":
			var exhausted_unit := g.find_unit(e["uid"])
			_log("%s ficou exausta" % ("Uma unidade" if exhausted_unit == null else _cname(exhausted_unit.card_id)))
		"ready":
			var readied_unit := g.find_unit(e["uid"])
			_log("%s desvirou" % ("Uma unidade" if readied_unit == null else _cname(readied_unit.card_id)))
		"card_created":
			_log("%s criou %s no %s" % [_pname(e["player"]), _cname(e["card_id"]), "topo do deck" if e["to"] == "deck_top" else "mão"])
		"slots_frozen":
			_log("%d espaços do campo de %s foram sorteados para congelar (%d vazios bloqueados)" % [e["positions"].size(), _pname(e["player"]), e["blocked"]])
		"slots_thaw":
			_log("Os espaços congelados de %s descongelaram" % _pname(e["player"]))
		"thaw":
			var thawed := g.find_unit(e["uid"])
			if thawed != null:
				_log("%s descongelou" % _cname(thawed.card_id))
		"incarnation_retired":
			_log("%s foi para o fundo do deck como carta comum" % _cname(e["card_id"]))
		"enter_skip":
			_log("%s: Ao Entrar recusado" % _cname(e["card_id"]))
		"search_empty":
			_log("%s não encontrou uma carta que atendesse à busca" % _pname(e["player"]))
		"enter_from_deck":
			_log("%s saiu do deck e entrou em campo para %s" % [_cname(e["card_id"]), _pname(e["player"])])
		"search_take":
			_log("%s escolheu %s na busca" % [_pname(e["player"]), _cname(e["card_id"])])
		"fizzle":
			_log("%s foi anulado (alvo inválido)" % (_cname(e["card_id"]) if e["kind"] in ["card", "subito"] else "Habilidade"))
		"countered":
			_log("%s anulou %s" % [_pname(e["by"]), _cname(e["card_id"]) if e["kind"] in ["card", "subito"] else "a habilidade de " + _pname(e["player"])])
		"magic_shield_break":
			var shielded := g.find_unit(e["uid"])
			_log("Escudo Mágico anulou o efeito" + ("" if shielded == null else " em " + _cname(shielded.card_id)))
		"supreme_shield_break":
			var supreme_holder: Card = g.find_unit(e["uid"])
			if supreme_holder == null:
				supreme_holder = g.find_relic(e["uid"]) # a free-standing artifact (Baluarte Santo) can hold it too
			_log("Escudo Supremo absorveu" + ("" if supreme_holder == null else " em " + _cname(supreme_holder.card_id)))
		"tide_draw":
			_log("%s: a maré retorna, compra 1" % _pname(e["player"]))
		"snowball":
			_log("%s: %s com %d de dano inicial" % [_pname(e["player"]), "Grande Bola de Neve" if e["grande"] else "Bola de Neve", int(e["amount"])])
		"snowball_evolve":
			_log("%s: a Bola de Neve chegou ao nível Grande, e %d carta(s) viraram Grande Bola de Neve" % [_pname(e["player"]), int(e["count"])])
		"snowball_devolve":
			_log("%s: o nível da Bola de Neve acabou, e %d carta(s) voltaram a ser Bola de Neve" % [_pname(e["player"]), int(e["count"])])
		"snowball_reset":
			_log("%s: a Bola de Neve volta ao nível %d" % [_pname(e["player"]), int(e["level"])])
		"snowball_level":
			_log("%s: o nível da Bola de Neve sobe para %d" % [_pname(e["player"]), int(e["level"])])
		"relic_redirect":
			var saved_unit := g.find_unit(e["saved"])
			_log("%s foi destruído no lugar de %s" % [_cname(e["card_id"]), "uma unidade" if saved_unit == null else _cname(saved_unit.card_id)])
		"lethal_ward":
			_log("%s anulou %d de dano que mataria o Líder de %s" % [_cname(e["card_id"]), int(e["amount"]), _pname(e["player"])])
		"leader_hit_negated":
			_log("O Líder de %s anulou um golpe de %d (restam %d)" % [_pname(e["player"]), int(e["amount"]), int(e["left"])])
		"discard_pick":
			_log("%s escolhe uma carta da mão para descartar" % _pname(e["player"]))
		"hand_summon_pick":
			_log("%s escolhe um campeão da mão para entrar em campo de graça" % _pname(e["player"]))
		"hand_summon":
			_log("%s colocou %s em campo direto da mão (será banido no fim do turno)" % [_pname(e["player"]), _cname(e["card_id"])])
		"search_decline":
			_log("%s preferiu não pegar nenhuma das cartas encontradas" % _pname(e["player"]))
		"hand_summon_skip":
			_log("%s preferiu não colocar nenhum campeão em campo" % _pname(e["player"]))
		"discard":
			_log("%s descartou %s" % [_pname(e["player"]), _cname(e["card_id"])])
	_chronicle_visual_context = {}
