# Requirements: UCLA Card Game Continuation

**Defined:** 2026-05-03
**Core Value:** A regra de deck e a resolucao de jogo devem ser corretas e server-authoritative, com arquitetura modular que permita expandir cartas/efeitos sem retrabalho estrutural.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Card Domain

- [ ] **CARD-01**: O sistema modela tres tipos de carta: Unit, Spell e Champion.
- [ ] **CARD-02**: Champion reutiliza comportamento base de Unit com atributos de poder superiores definidos por dados.
- [ ] **CARD-03**: O sistema modela raridades Comum, Epico e Lendario de forma canonica no dominio compartilhado.
- [ ] **CARD-04**: Cada carta suporta de zero a duas essencias entre: obscura, ignea, eletrica, sagrada, aquatica, glacial, terrestre, aerea, crepuscular.
- [ ] **CARD-05**: Cartas sem essencia sao tratadas explicitamente como neutras.

### Deck Rules (Authoritative)

- [ ] **DECK-01**: O servidor rejeita qualquer deck com tamanho diferente de 48 cartas.
- [ ] **DECK-02**: O servidor aplica limite maximo de 2 copias para cartas do tipo Champion.
- [ ] **DECK-03**: O servidor aplica limite maximo de 3 copias para cartas Lendarias (Unit ou Spell).
- [ ] **DECK-04**: O servidor aplica limite maximo de 4 copias para outras Units (Comum e Epico).
- [ ] **DECK-05**: O servidor aplica a regra critica de coesao: toda carta nao-neutra deve compartilhar ao menos uma essencia com outra carta do deck.
- [ ] **DECK-06**: Cartas neutras nao invalidam a regra de coesao por essencia.
- [ ] **DECK-07**: O servidor retorna erros de validacao estruturados por regra violada (tamanho, copias, coesao, formato).

### Deckbuilding (Client)

- [ ] **DBLD-01**: Existe uma pagina separada de deckbuilding desacoplada da tela de partida.
- [ ] **DBLD-02**: O deckbuilder impede erros basicos em tempo de montagem (tamanho alvo, limites de copia, formato).
- [ ] **DBLD-03**: O deckbuilder gera codigo de deck valido e importavel.
- [ ] **DBLD-04**: O cliente envia deck code para o backend sem assumir autoridade de validacao.
- [ ] **DBLD-05**: O cliente exibe feedback claro quando o backend rejeita o deck.

### Architecture and Flow

- [ ] **ARCH-01**: O backend permanece server-authoritative para validacao e transicoes de estado de jogo.
- [ ] **ARCH-02**: O sistema usa contratos compartilhados de eventos/payload para reduzir drift client-server.
- [ ] **ARCH-03**: O fluxo de acao/efeito usa pipeline/event bus inspirado na arquitetura RPG e adaptado ao card game.
- [ ] **ARCH-04**: Conceitos do RPG que nao se aplicam diretamente (ex.: damageMode global complexo) sao removidos ou adaptados por regra de carta.
- [ ] **ARCH-05**: A camada de rede valida intents antes de mutar estado de jogo.

### Match and Sync

- [ ] **SYNC-01**: Dois jogadores conseguem iniciar partida multiplayer com deck validado no servidor.
- [ ] **SYNC-02**: O servidor emite snapshots/eventos ordenados para manter renderizacao deterministica no cliente.
- [ ] **SYNC-03**: O turno respeita validacoes de acao no servidor antes de broadcast.

### Quality and Verification

- [ ] **QUAL-01**: Existem testes automatizados para as regras autoritativas de deck (tamanho, copias, coesao).
- [ ] **QUAL-02**: Existem testes de contrato para encode/decode de deck code e cenarios invalidos.
- [ ] **QUAL-03**: Existem testes de integracao dos principais eventos Socket.IO do fluxo deck->join->partida.

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Competitive and Product Evolution

- **EVO-01**: Modo espectador com feed de eventos atrasado.
- **EVO-02**: Sistema de replay deterministico a partir de logs/eventos.
- **EVO-03**: Modo ranked com progressao/MMR.
- **EVO-04**: Modos alternativos (draft/arena) apos estabilizacao do core.

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature                                         | Reason                                                                    |
| ----------------------------------------------- | ------------------------------------------------------------------------- |
| Portar integralmente formulas de combate do RPG | O card game requer adaptacao seletiva, nao copia literal de mecanicas RPG |
| Sistema de switch/reserva 3v3 do RPG            | Nao e parte do escopo central de deckbuilding/validacao do card game      |
| Reescrita total para framework frontend novo    | Alto custo e baixo retorno antes de estabilizar regras centrais           |
| Reescrita completa em TypeScript nesta fase     | Eleva risco/tempo durante fase de consolidacao de regras                  |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status  |
| ----------- | ----- | ------- |
| CARD-01     | TBC   | Pending |
| CARD-02     | TBC   | Pending |
| CARD-03     | TBC   | Pending |
| CARD-04     | TBC   | Pending |
| CARD-05     | TBC   | Pending |
| DECK-01     | TBC   | Pending |
| DECK-02     | TBC   | Pending |
| DECK-03     | TBC   | Pending |
| DECK-04     | TBC   | Pending |
| DECK-05     | TBC   | Pending |
| DECK-06     | TBC   | Pending |
| DECK-07     | TBC   | Pending |
| DBLD-01     | TBC   | Pending |
| DBLD-02     | TBC   | Pending |
| DBLD-03     | TBC   | Pending |
| DBLD-04     | TBC   | Pending |
| DBLD-05     | TBC   | Pending |
| ARCH-01     | TBC   | Pending |
| ARCH-02     | TBC   | Pending |
| ARCH-03     | TBC   | Pending |
| ARCH-04     | TBC   | Pending |
| ARCH-05     | TBC   | Pending |
| SYNC-01     | TBC   | Pending |
| SYNC-02     | TBC   | Pending |
| SYNC-03     | TBC   | Pending |
| QUAL-01     | TBC   | Pending |
| QUAL-02     | TBC   | Pending |
| QUAL-03     | TBC   | Pending |

**Coverage:**

- v1 requirements: 28 total
- Mapped to phases: 0
- Unmapped: 28

---

_Requirements defined: 2026-05-03_
_Last updated: 2026-05-03 after initial definition_
