extends RefCounted
## Playtest do OTK de Fim de Turno do Eryon: é o meu 10º turno, começando com 10 de Momentum,
## com Eryon e Foguista Exagerado (custo 4) em campo, já acordados.
## Roteiro: ativar o Eryon sacrificando o Foguista (+4, vai a 14), passar o turno e
## ver o Fim do Turno gastar os 14 e dar 14 - 5 = 9 golpes de 2 (18 de dano) espalhados
## entre as 2 unidades do Ronan (4 e 5 de Vida) e o Líder dele (9 de Vida).
## Apagar depois do playtest.

const PLAYER_DECK := "eryon"
const ENEMY_DECK := "fogo"

const ENEMY_LEADER_HP := 9

static func setup(g: GameState) -> void:
	# não é o começo da partida: os dois mantêm a mão (sem mulligan) e o turno é meu
	g.first = 0
	g.mulligan(0, [])
	g.mulligan(1, [])
	_put(g, 0, "eryon")
	# a unidade de custo 4 que vai ser sacrificada pelo poder do Eryon
	_put(g, 0, "foguista_exagerado")
	# duas unidades de Vida média no campo do Ronan, pra "roubar" golpes do Líder
	_put(g, 1, "desmontador_de_quinquilharia")
	_put(g, 1, "lord_of_the_shadowflame")
	g.players[1]["leader_hp"] = ENEMY_LEADER_HP
	# 10º turno meu (eu jogo nos turnos ímpares): Momentum máximo 10, cheio
	g.turn = 19
	g.players[0]["max_momentum"] = 10
	g.players[0]["momentum"] = 10
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
