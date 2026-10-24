extends RefCounted
## Playtest do Ciclo da Carpideira: é o meu 10º turno (sem mulligan), com 1 Carpideira
## já em campo (acordada), 10 de Momentum e Reserva vazia, e as demais peças do combo na mão
## (mais uma Carpideira na mão).
## Roteiro sugerido: Urna (2) + Carpideira (2) + Cantora (2) + Tesoureira (3) = 9 de Momentum,
## depois sacrificar com a Urna e ver quantas voltas dá pra fazer; Fagulha (2) e Cutucada (0)
## entram quando sobrar Momentum. Colheita de Almas e Pacto de Mortalha sobram como extras.
## Apagar depois do playtest.

const PLAYER_DECK := "obscura_ciclo"
const ENEMY_DECK := "fogo"

const HAND := [
	"urna_cochichante",
	"carpideira_soluco_curto",
	"cantora_de_velorio",
	"tesoureira_troco_certo",
	"fagulha_bocejante",
	"cutucada_no_defunto",
	"cutucada_no_defunto",
	"espirito_choroso",
	"colheita_de_almas",
	"pacto_de_mortalha",
]

static func setup(g: GameState) -> void:
	# não é o começo da partida: os dois mantêm a mão (sem mulligan) e o turno é meu
	g.first = 0
	g.mulligan(0, [])
	g.mulligan(1, [])
	# mão com todas as peças (substitui a mão sorteada)
	g.players[0]["hand"].clear()
	for card_id: String in HAND:
		g.players[0]["hand"].append(Card.new(g._uid(), card_id, 0, "hand"))
	# uma Carpideira já em campo: cada Aliado que morre causa um choro por Carpideira
	_put(g, 0, "carpideira_soluco_curto")
	# 10º turno meu (eu jogo nos turnos ímpares): Momentum máximo 10 cheio, Reserva vazia
	g.turn = 19
	g.players[0]["max_momentum"] = 10
	g.players[0]["momentum"] = 10
	g.players[0]["reserve"] = 0
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
