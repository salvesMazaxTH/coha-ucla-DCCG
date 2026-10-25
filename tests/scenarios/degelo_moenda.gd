extends RefCounted
## Playtest do Degelo na Moenda: é o meu 10º turno (sem mulligan), campo vazio, 10 de Momentum,
## Reserva vazia, e o deck do oponente com 27 cartas (o que sobra mais ou menos no turno 10).
## Roteiro sugerido: Moenda (4) + Zuleica (2) + Fagulha (2) = 8 de Momentum. Depois:
##   1. ativar a Fagulha (+1 de Momentum, ela exaure);
##   2. ativar a Zuleica mirando a Fagulha (-1 de Momentum, -1 de Vida, a Moenda mói 2);
##   3. repetir 1 e 2 até o deck do oponente acabar; cada moagem com o deck vazio vira Fadiga.
## A Cutucada dá uma volta de graça (sem pagar Vida) e a Maré Curativa compra mais 4 voltas.
## Apagar depois do playtest.

const PLAYER_DECK := "fluxo_moenda"
const ENEMY_DECK := "fogo"

const HAND := [
	"moenda_do_seu_belmiro",
	"zuleica_degela_tudo",
	"fagulha_bocejante",
	"cutucada_no_defunto",
	"mare_curativa",
	"mare_curativa",
	"trituracao_em_massa",
	"geada_relampago",
]

## Cartas que ficam no deck do oponente, como se já tivesse comprado por 10 turnos.
const ENEMY_DECK_SIZE := 27

static func setup(g: GameState) -> void:
	# não é o começo da partida: os dois mantêm a mão (sem mulligan) e o turno é meu
	g.first = 0
	g.mulligan(0, [])
	g.mulligan(1, [])
	# mão com todas as peças (substitui a mão sorteada)
	g.players[0]["hand"].clear()
	for card_id: String in HAND:
		g.players[0]["hand"].append(Card.new(g._uid(), card_id, 0, "hand"))
	# o oponente já comprou boa parte do deck
	var enemy_deck: Array = g.players[1]["deck"]
	while enemy_deck.size() > ENEMY_DECK_SIZE:
		enemy_deck.pop_back()
	# 10º turno meu (eu jogo nos turnos ímpares): Momentum máximo 10 cheio, Reserva vazia
	g.turn = 19
	g.players[0]["max_momentum"] = 10
	g.players[0]["momentum"] = 10
	g.players[0]["reserve"] = 0
	g.players[1]["max_momentum"] = 9
	g._flush()
