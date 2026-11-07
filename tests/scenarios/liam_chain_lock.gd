extends RefCounted
## Playtest do VFX de bloqueio do Liam: a IA começa no 7º turno com Liam como única carta na mão.
## Você começa o próximo turno com D'Lorafya (custo 7), bloqueada pelo efeito do Liam.
## Executar com: godot --path . -- --scenario=liam_chain_lock
## Apagar depois do playtest.

const PLAYER_DECK := "agua"
const ENEMY_DECK := "layla"

static func setup(g: GameState) -> void:
	g.first = 1
	g.mulligan(1, [])
	g.mulligan(0, [])
	g.players[0]["hand"].clear()
	g.players[1]["hand"].clear()
	g.players[0]["hand"].append(Card.new(g._uid(), "dlorafya", 0, "hand"))
	g.players[1]["hand"].append(Card.new(g._uid(), "liam_tornagron", 1, "hand"))
	g.turn = 13
	g.players[0]["max_momentum"] = 6
	g.players[1]["max_momentum"] = 7
	g.players[1]["momentum"] = 7
	g.players[1]["incarnation"]["in_zone"] = false
	g._flush()
