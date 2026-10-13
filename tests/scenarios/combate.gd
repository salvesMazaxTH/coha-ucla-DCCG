extends RefCounted
## Playtest do rework de combate (tap + desafio). Apagar depois do playtest.
## Você (Maré): Sentinela de Coral já ferida (Regeneração), Tritão Lanceiro e Gaivota (Voo).
## Inimigo: Colosso de Arenito tapped (Provocação), Fênix Menor tapped (Voo), Salamandra de pé.
## Mão: Naelthos (Provocação: pergunta se entra tapped) e Maré Curativa (pode curar o seu Líder).

static func setup(g: GameState) -> void:
	var sentinel := _put(g, 0, "sentinela_coral")
	sentinel.damage = 2 # dano persistente: a Regeneração limpa no fim do turno
	_put(g, 0, "tritao_lanceiro")
	_put(g, 0, "gaivota_da_tempestade")
	_put(g, 1, "colosso_de_arenito").exhausted = true # Provocação tapped: obriga o desafio
	_put(g, 1, "fenix_menor").exhausted = true # Voo: só Voo/Longo Alcance desafia
	_put(g, 1, "salamandra") # de pé: não pode ser desafiada
	g.players[0]["momentum"] = 10
	for card_id in ["naelthos", "mare_curativa"]:
		g.players[0]["hand"].append(Card.new(g._uid(), card_id, 0, "hand"))
	g._flush()

static func _put(g: GameState, player: int, card_id: String) -> Card:
	var uid := g._uid()
	g._summon(player, Card.new(uid, card_id, player), false, 0)
	g._flush()
	if g.phase == "search":
		g.choose_search(player, int(g.pending_search["cards"][0]["uid"]))
		g._flush()
	if g.phase == "enter_tapped": # Provocação entrando: o cenário decide o tap
		g.choose_enter_tapped(player, false)
		g._flush()
	g.pending_tap.erase(uid)
	var unit := g.find_unit(uid)
	unit.sick = false
	return unit
