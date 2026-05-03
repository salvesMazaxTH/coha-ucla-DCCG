# UCLA Card Game Continuation

## What This Is

Continuidade de um card game multiplayer server-authoritative, evoluindo de um prototipo incompleto para uma base de producao modular e escalavel. O objetivo e reutilizar ao maximo os padroes arquiteturais do RPG turn-based documentado em `GAME_ARCHITECTURE_v6_2 (current).md`, adaptando o que fizer sentido para mecanicas de cartas. O produto final inclui fluxo de deckbuilding dedicado no client e validacao completa de deck no backend.

## Core Value

A regra de deck e a resolucao de jogo devem ser corretas e server-authoritative, com arquitetura modular que permita expandir cartas/efeitos sem retrabalho estrutural.

## Requirements

### Validated

- ✓ Servidor Express + Socket.IO com estado central no backend — existente (`server/server.js`, `server/core/GameInstance.js`)
- ✓ Modelo de dominio compartilhado para entidades/jogador/estado — existente (`shared/core/*`)
- ✓ Motor de combate separado em validacao e resolucao — existente (`engine/CombatEngine.js`, `engine/CombatResolver.js`)
- ✓ Pipeline de efeitos orientado a eventos (hooks) — existente (`shared/effects/EffectBus.js`)

### Active

- [ ] Implementar modelo canonico de cartas (Unit, Spell, Champion), raridades e essencias em schema compartilhado
- [ ] Implementar validacao de deck server-authoritative para 48 cartas, limites por copia e regra critica de coesao por essencia
- [ ] Criar pagina separada de deckbuilding com prevencao de erros basicos e geracao de deck code valido
- [ ] Garantir revalidacao backend do deck recebido (nunca confiar no client)
- [ ] Adaptar/reutilizar padroes do RPG (pipeline, contexto, entidades, envelopes de evento) para o card game sem carregar regras indevidas
- [ ] Completar contrato de eventos socket para fluxo real de partida (join/match/start/play/end-turn/state-sync)
- [ ] Cobrir validacoes criticas com testes automatizados

### Out of Scope

- Sistema de switch/reserva 3v3 do RPG — nao pertence ao contexto principal de deckbuilding e validacao de card game
- Reproducao literal de formulas de combate do RPG (ex.: damageMode completo) — sera adaptado apenas quando fizer sentido em cartas
- Persistencia/banco de dados completo nesta etapa inicial — foco em regras core e arquitetura

## Context

- Repositorio atual ja contem pilares reutilizaveis: `ActionStack`, `GameState`, `Entity`, `EffectBus`, renderizacao modular no frontend.
- Documento de arquitetura base do RPG foi lido integralmente e sera usado como referencia principal de organizacao.
- O estado atual possui lacunas importantes:
  - `DeckValidator` ainda usa regras antigas (30 cartas / max 3 copias)
  - `Keywords.js` vazio
  - `SocketHandler` com matchmaking incompleto
  - Frontend com partes em placeholder/teste
- Regras obrigatorias do produto foram definidas:
  - Tipos: Unit, Spell, Champion
  - Raridades: Comum, Epico, Lendario
  - Essencias (ate 2 por carta) e neutras
  - Deck exatamente 48 cartas
  - Regra critica: toda carta nao-neutra deve compartilhar pelo menos uma essencia com outra carta do deck
  - Limites por copia: Champion 2, Lendario 3, outras Units 4

## Constraints

- **Architecture**: Reutilizar ao maximo arquitetura do RPG (pipeline/eventos/delegacao) — consistencia e escalabilidade
- **Authority**: Backend valida tudo e define estado canonico — integridade competitiva
- **Compatibility**: Aproveitar estrutura existente sem quebrar o fluxo atual de renderizacao — evolucao incremental
- **Scope**: Priorizar regras de deck e fluxo deckbuilder antes de features cosmeticas — reduzir risco funcional
- **Quality**: Evitar duplicacao de logica entre client e server — mesma semantica com responsabilidades separadas

## Key Decisions

| Decision                                                               | Rationale                                                         | Outcome   |
| ---------------------------------------------------------------------- | ----------------------------------------------------------------- | --------- |
| Usar arquitetura RPG como baseline principal                           | Ja existe modelo robusto de pipeline, hooks e estado autoritativo | — Pending |
| Adaptar/remover conceitos de combate direto (ex.: damageMode completo) | Nem toda abstracao do RPG serve para mecanica de cartas           | — Pending |
| Centralizar regra de deck em schema compartilhado + validator backend  | Evita drift entre client e server e reforca anti-cheat            | — Pending |
| Criar pagina de deckbuilding separada                                  | UX e validacao preliminar sem poluir tela principal de partida    | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):

1. Requirements invalidated? -> Move to Out of Scope with reason
2. Requirements validated? -> Move to Validated with phase reference
3. New requirements emerged? -> Add to Active
4. Decisions to log? -> Add to Key Decisions
5. "What This Is" still accurate? -> Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):

1. Full review of all sections
2. Core Value check - still the right priority?
3. Audit Out of Scope - reasons still valid?
4. Update Context with current state

---

_Last updated: 2026-05-03 after initialization_
