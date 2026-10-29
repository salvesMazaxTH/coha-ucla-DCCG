extends RefCounted
## Playtest visual do painel "Modificadores" do overlay da carta. Apagar depois do playtest.
## Clique em cada unidade para abrir o overlay:
## Você:
##   Paquiderme Sem Vergonha: MUITOS modificadores (equipamento, aura Constante, ×2, ×3, fim do turno,
##     até seu turno, Poder do Líder e debuffs). Passa de 6 linhas, então mostra a linha "+N outras fontes".
##   Matriarca Pisa-Mansinho: sem modificadores (é ela quem dá +1/+1 ao Paquiderme), então sem painel.
## Inimigo:
##   Tromba de Aluguel: só dois buffs, de cartas diferentes.
##   Sentinela Dorminhoca: só dois debuffs, de cartas diferentes.

static func setup(g: GameState) -> void:
	_put(g, 0, "matriarca_pisa_mansinho") # Constante: seus outros Elefantes têm +1/+1
	var pachyderm := _put(g, 0, "paquiderme_sem_vergonha")
	# equipamento de verdade: a Coleira dá +2/+2 e aparece como "Equipamento"
	var collar := Card.new(g._uid(), "coleira_de_bronze_gigante", 0, "hand")
	var collar_grant := g.stack_system().apply_equipment_bonus(pachyderm, {"atk": 2, "hp": 2})
	g.stack_system().attach(pachyderm, collar, collar_grant)
	_modify(pachyderm, "afiar_a_lamina", "", {"atk": 2}) # duas vezes o mesmo efeito: linha ×2
	_modify(pachyderm, "afiar_a_lamina", "", {"atk": 2})
	_modify(pachyderm, "tecnomante", "", {"hp": 1}) # três vezes: linha ×3
	_modify(pachyderm, "tecnomante", "", {"hp": 1})
	_modify(pachyderm, "tecnomante", "", {"hp": 1})
	_modify(pachyderm, "pisoteio_autorizado", "end_turn", {"atk": 3})
	_modify(pachyderm, "hoje_ninguem_erra", "end_turn", {"critico": 1})
	_modify(pachyderm, "", "next_turn", {"armor": 2}) # sem carta de origem = Poder do Líder
	_modify(pachyderm, "cortina_de_fumaca_barata", "end_turn", {"atk": -2})
	_modify(pachyderm, "gatuno_do_beco_torto", "", {"hp": -1})

	var trunk := _put(g, 1, "tromba_de_aluguel")
	_modify(trunk, "afiar_a_lamina", "", {"atk": 2})
	_modify(trunk, "remendeira_de_esquina", "", {"hp": 2})

	var sentinel := _put(g, 1, "sentinela_dorminhoca")
	_modify(sentinel, "estouro_da_manada", "", {"atk": -1})
	_modify(sentinel, "gatuno_do_beco_torto", "", {"hp": -2})

	g.players[0]["momentum"] = 10
	g._refresh_scaling() # recalcula a aura da Matriarca agora, antes da primeira ação
	g._flush()

## Changes the unit's stats the way an effect would and records where the change came from.
## until: "" permanente, "end_turn" até o fim do turno, "next_turn" até o próximo turno de quem a controla.
static func _modify(unit: Card, source: String, until: String, changes: Dictionary) -> void:
	var atk_change := int(changes.get("atk", 0))
	var hp_change := int(changes.get("hp", 0))
	var armor_change := int(changes.get("armor", 0))
	var critico_change := int(changes.get("critico", 0))
	match until:
		"end_turn":
			unit.temp_atk += atk_change
			unit.temp_hp += hp_change
			unit.turn_armor += armor_change
			unit.temp_critico += critico_change
		"next_turn":
			unit.temp_atk_until_next_turn += atk_change
			unit.temp_hp_until_next_turn += hp_change
			unit.temp_armor += armor_change
		_:
			unit.atk += atk_change
			unit.hp += hp_change
			unit.armor += armor_change
			unit.critico += critico_change
	unit.record_stat_change(source, until, changes)

static func _put(g: GameState, player: int, card_id: String) -> Card:
	var uid := g._uid()
	g._summon(player, Card.new(uid, card_id, player), false, 0)
	g._flush()
	if g.phase == "search":
		g.choose_search(player, 0) # recusa a busca (mão vazia de propósito)
		g._flush()
	if g.phase == "enter_tapped":
		g.choose_enter_tapped(player, false)
		g._flush()
	g.pending_tap.erase(uid)
	var unit := g.find_unit(uid)
	unit.sick = false
	return unit
