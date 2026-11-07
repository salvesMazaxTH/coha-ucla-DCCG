extends RefCounted
## Playtest do Rai'Emofitir: ele está no seu campo, já acordado (sem enjoo de invocação).
## O inimigo tem uma Tromba de Aluguel (2/4) que buffs permanentes deixaram em 20/20.
## O que conferir: ao desafiar, o Rai ganha Indestrutível até o fim do turno, mata a Tromba
## com Toque Letal e ela é banida em vez de ir para o cemitério.
## Apagar depois do playtest.

const PLAYER_DECK := "sagrada"
const ENEMY_DECK := "fogo"

static func setup(g: GameState) -> void:
	# não é o começo da partida: os dois mantêm a mão (sem mulligan) e o turno é meu
	g.first = 0
	g.mulligan(0, [])
	g.mulligan(1, [])
	_put(g, 0, "rai_emofitir")
	var giant := _put(g, 1, "tromba_de_aluguel")
	# de 2/4 para 20/20 com buffs permanentes (aparecem no painel Modificadores da carta)
	_buff(giant, "afiar_a_lamina", {"atk": 18})
	_buff(giant, "remendeira_de_esquina", {"hp": 16})
	giant.exhausted = true # virada, para o Rai poder desafiá-la
	g.players[0]["max_momentum"] = 10
	g.players[0]["momentum"] = 10
	g._flush()

## Buff permanente, registrado com a carta de origem como um efeito de verdade faria.
static func _buff(unit: Card, source: String, changes: Dictionary) -> void:
	unit.atk += int(changes.get("atk", 0))
	unit.hp += int(changes.get("hp", 0))
	unit.record_stat_change(source, "", changes)

## Põe uma carta direto no campo, resolve as escolhas que a entrada pedir e tira o enjoo de invocação.
static func _put(g: GameState, player: int, card_id: String) -> Card:
	var uid := g._uid()
	g._summon(player, Card.new(uid, card_id, player), false, 0)
	g._flush()
	if g.phase == "search":
		g.choose_search(player, 0) # recusa a busca
		g._flush()
	if g.phase == "enter_tapped":
		g.choose_enter_tapped(player, false)
		g._flush()
	g.pending_tap.erase(uid)
	var unit := g.find_unit(uid)
	unit.sick = false
	return unit
