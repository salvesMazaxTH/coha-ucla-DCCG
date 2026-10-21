extends RefCounted
## Playtest do OTK do Barão Estrondoso: é o meu 10º turno, com Eryon e Cobrador de Pedágio Torto
## em campo (já acordados), Barão Estrondoso e Dona Gertrudes Fura-Fila na mão.
## Momentum: 10 do turno + 1 do Cobrador (já contado, como se o gatilho de início de turno tivesse rodado).
## Apagar depois do playtest.

const PLAYER_DECK := "eryon"
const ENEMY_DECK := "fogo"

static func setup(g: GameState) -> void:
	# não é o começo da partida: os dois mantêm a mão (sem mulligan) e o turno é meu
	g.first = 0
	g.mulligan(0, [])
	g.mulligan(1, [])
	_put(g, 0, "eryon")
	_put(g, 0, "cobrador_de_pedagio_torto")
	# o Barão só ataca se tiver uma unidade inimiga pra atacar: um alvo no campo do Ronan
	# (virada: só unidade virada pode ser atacada)
	var target_unit := _put(g, 1, "marmorea_cascalhuda")
	target_unit.exhausted = true
	for card_id in ["barao_estrondoso", "dona_gertrudes_fura_fila"]:
		g.players[0]["hand"].append(Card.new(g._uid(), card_id, 0, "hand"))
	# 10º turno meu (eu jogo nos turnos ímpares): Momentum máximo 10, +1 do Cobrador
	g.turn = 19
	g.players[0]["max_momentum"] = 10
	g.players[0]["momentum"] = 11
	g.players[1]["max_momentum"] = 9
	g._flush()

## Põe uma carta direto no campo, resolve as escolhas que a entrada pedir e tira o enjoo de invocação.
static func _put(g: GameState, player: int, card_id: String) -> Card:
	var uid := g._uid()
	g._summon(player, Card.new(uid, card_id, player), false, 0)
	g._flush()
	if g.phase == "search":
		g.choose_search(player, int(g.pending_search["cards"][0]["uid"]))
		g._flush()
	if g.phase == "enter_tapped":
		g.choose_enter_tapped(player, false)
		g._flush()
	g.pending_tap.erase(uid)
	var unit := g.find_unit(uid)
	unit.sick = false
	return unit
