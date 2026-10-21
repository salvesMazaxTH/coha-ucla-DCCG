extends RefCounted
## Playtest do OTK da Viprax: meu 9º turno (Momentum 9), Viprax em campo (já acordada) e
## 2 Brindes Envenenados na mão. O Líder inimigo começa sem Veneno.
## Roteiro: 2 Brindes (6 de Momentum, 4 marcadores) -> Viprax ataca o Líder (Tóxico 2 + 1 do
## Ao Atingir = 7) -> ativa a Viprax (3): +1 marcador = 8, o Líder morre.
## Apagar depois do playtest.

const PLAYER_DECK := "venenosa"
const ENEMY_DECK := "fogo"

static func setup(g: GameState) -> void:
	# não é o começo da partida: os dois mantêm a mão (sem mulligan) e o turno é meu
	g.first = 0
	g.mulligan(0, [])
	g.mulligan(1, [])
	_put(g, 0, "viprax")
	for i in 2:
		g.players[0]["hand"].append(Card.new(g._uid(), "brinde_envenenado", 0, "hand"))
	# 9º turno meu (eu jogo nos turnos ímpares): Momentum 9 = 3 + 3 dos Brindes + 3 da ativação
	g.turn = 17
	g.players[0]["max_momentum"] = 9
	g.players[0]["momentum"] = 9
	g.players[1]["max_momentum"] = 8
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
