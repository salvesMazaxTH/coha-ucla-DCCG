extends RefCounted
## Playtest das animações de área (cada feitiço cobre a arena inteira).
## 99 de Momentum; o oponente tem o campo cheio (8 unidades) com 30 de Vida cada.
## A mão, da esquerda para a direita:
##   1. Avalanche (gelo)                 2. Zero Absoluto (gelo)
##   3. Tempestade Estática (raio)       4. Joio e Trigo (luz)
##   5. Cicuta no Chá (nuvem tóxica)     6. Névoa de Esporos (nuvem tóxica)
##   7. Última Badalada (luz)            8. Expurgo Sagrado (luz, limpa a mesa: deixe por último)
## Apagar depois do playtest.

const PLAYER_DECK := "sagrada"
const ENEMY_DECK := "fogo"

const HAND := [
	"avalanche",
	"zero_absoluto",
	"tempestade_estatica",
	"joio_e_trigo",
	"cicuta_no_cha",
	"nevoa_de_esporos_teimosos",
	"ultima_badalada",
	"expurgo_sagrado",
]

## Quantas unidades o oponente tem em campo (o campo cheio é GameState.BOARD_LIMIT = 8).
const ENEMY_UNIT_COUNT := 8
## Vida extra de cada unidade inimiga, para aguentar todos os feitiços de dano.
const ENEMY_EXTRA_HP := 26

static func setup(g: GameState) -> void:
	# não é o começo da partida: os dois mantêm a mão (sem mulligan) e o turno é meu
	g.first = 0
	g.mulligan(0, [])
	g.mulligan(1, [])
	# a mão só com os feitiços do teste (substitui a mão sorteada)
	g.players[0]["hand"].clear()
	for card_id: String in HAND:
		g.players[0]["hand"].append(Card.new(g._uid(), card_id, 0, "hand"))
	# o campo inimigo cheio de unidades parrudas
	for i in ENEMY_UNIT_COUNT:
		var unit := _put(g, 1, "tromba_de_aluguel")
		_buff(unit, "remendeira_de_esquina", {"hp": ENEMY_EXTRA_HP})
	# Momentum de sobra para jogar a mão inteira neste turno
	g.players[0]["max_momentum"] = 10
	g.players[0]["momentum"] = 99
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
