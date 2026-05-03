# GAME_ARCHITECTURE.md — Champion Arena (UCLA RPG)

> Documentação mestre da arquitetura do sistema. Referência técnica completa para desenvolvimento, manutenção e extensão do jogo.
> **v6.2 (estado operacional atual)** — O modo jogável atual voltou a ser **3v3 fixo**: cada jogador seleciona **3 campeões**, com **3 slots simultâneos em campo** (inicial e máximo). O sistema de **Switch/troca/reserva está temporariamente desabilitado por tempo indeterminado**.

---

## Índice

1. [Visão Geral](#1-visão-geral)
2. [Stack Tecnológica](#2-stack-tecnológica)
3. [Estrutura de Arquivos](#3-estrutura-de-arquivos)
4. [Fluxo de Jogo (Game Loop)](#4-fluxo-de-jogo-game-loop)
5. [Camada de Rede — Socket.IO](#5-camada-de-rede--socketio)
6. [Gerenciamento de Sessão — GameMatch e Player](#6-gerenciamento-de-sessão--gamematch-e-player)
7. [Classe Champion e Módulos Delegados](#7-classe-champion-e-módulos-delegados)
8. [Sistema de Ultômetro (ultMeter)](#8-sistema-de-ultômetro-ultmeter)
9. [Pipeline de Combate — DamageEvent](#9-pipeline-de-combate--damageevent)
10. [TurnResolver — Resolução de Turnos](#10-turnresolver--resolução-de-turnos)
11. [Sistema de Contexto e Efeitos Estruturados](#11-sistema-de-contexto-e-efeitos-estruturados)
12. [Fórmulas de Dano e Defesa](#12-fórmulas-de-dano-e-defesa)
13. [Sistema de Afinidades Elementais](#13-sistema-de-afinidades-elementais)
14. [Sistema de Hooks — CombatEvents](#14-sistema-de-hooks--combatevents)
15. [Sistema de StatusEffects](#15-sistema-de-statuseffects)
16. [Sistema de Escudos (Shields)](#16-sistema-de-escudos-shields)
17. [Sistema de Modificadores de Dano](#17-sistema-de-modificadores-de-dano)
18. [Status do Sistema de Switch (Temporariamente Desabilitado)](#18-status-do-sistema-de-switch-temporariamente-desabilitado)
19. [Gerenciador de Animações — AnimsAndLogManager](#19-gerenciador-de-animações--animsandlogmanager)
20. [Sistema de Áudio — AudioManager](#26-sistema-de-áudio--audiomanager)
21. [Sistema de VFX — vfxManager](#20-sistema-de-vfx--vfxmanager)
22. [Indicadores de Status — StatusIndicator](#21-indicadores-de-status--statusindicator)
23. [Histórico de Turnos](#22-histórico-de-turnos)
24. [Modo de Edição / Debug](#23-modo-de-edição--debug)
25. [Como Criar um Novo Campeão](#24-como-criar-um-novo-campeão)
26. [Decisões de Design e Convenções](#25-decisões-de-design-e-convenções)

---

## 1. Visão Geral

**Champion Arena** é um jogo de arena turn-based multiplayer 1v1, jogado no browser. Dois jogadores se conectam via Socket.IO, selecionam equipes de **3 campeões** cada, e alternam turnos usando habilidades até que um time não tenha mais nenhum campeão real em campo (tokens e entidades especiais não contam).

### Formato de Equipe (estado operacional atual)

Cada jogador seleciona **3 campeões**. Os **3 ficam em campo simultaneamente** e esse também é o **máximo por time** durante a partida. O sistema de **Switch/troca/reserva** está **temporariamente desabilitado por tempo indeterminado**.

### Princípios Arquiteturais

- **Server Authoritative**: Todo o estado de jogo vive no servidor. O cliente apenas renderiza e envia intenções de ação; o servidor valida, processa e retransmite o estado canônico.
- **Código Compartilhado**: A pasta `/shared` contém código que roda tanto no Node.js (server) quanto no browser (client) — `Champion.js`, `DamageEvent.js`, `TurnResolver.js`, e utilitários.
- **Event-Driven**: Passivas, efeitos de campeões e status-effects se comunicam via sistema de hooks (`combatEvents.js`), sem acoplamento direto com o motor de combate.
- **Animações Determinísticas**: O cliente recebe envelopes estruturados com arrays tipados de eventos ordenados, e os anima sequencialmente em fila — nunca há corrida ou sobreposição visual.
- **Delegação Modular**: A classe `Champion` delega comportamento a 3 módulos especializados (`championCombat.js`, `championStatus.js`, `championUI.js`), mantendo-se como fachada.

---

## 2. Stack Tecnológica

| Camada       | Tecnologia                           |
| ------------ | ------------------------------------ |
| Servidor     | Node.js + Express 5 (ES Modules)     |
| Comunicação  | Socket.IO 4.8 (WebSocket)            |
| Cliente      | Vanilla JS (ES Modules, `import`)    |
| UI/Estilo    | HTML5 + CSS3 (sem framework)         |
| Fontes       | Google Fonts (Montserrat) + Boxicons |
| Debug mobile | Eruda (injetado em `index.html`)     |

---

## 3. Estrutura de Arquivos

```
/
├── src/
│   └── server.js                   # Express + Socket.IO + lógica de jogo
│
├── public/                         # Servido estaticamente pelo Express
│   ├── index.html                  # Único HTML — SPA com múltiplas "telas"
│   ├── js/
│   │   ├── main.js                 # Entrada do cliente; UI e socket
│   │   ├── gameGlossary.js         # Glossário interativo de termos de jogo
│   │   └── animation/
│   │       ├── animsAndLogManager.js  # Sistema de fila de animações
│   │       └── skillAnimations.js     # Animações WebGL one-shot de skills (Three.js)
│   ├── utils/
│   │   └── AudioManager.js            # SFX + música (singleton, client-only)
│   ├── styles/
│   │   ├── base.css                # Resets e defaults globais
│   │   ├── layout.css              # Grid e containers
│   │   ├── ui.css                  # Botões, overlays, barras
│   │   ├── animations.css          # Efeitos de combate
│   │   └── vfx.css                 # Camadas canvas
│   └── assets/
│       └── portraits/              # Imagens dos campeões
│
├── shared/                         # Código isomórfico (server + client)
│   │
│   ├── core/
│   │   ├── Champion.js             # Classe central do campeão (fachada)
│   │   ├── championCombat.js       # Dano, cura, escudos, buffs, taunt
│   │   ├── championStatus.js       # Aplicação e remoção de status-effects
│   │   └── championUI.js           # Renderização DOM e atualização de HP/ult bars
│   │
│   ├── engine/
│   │   ├── combat/
│   │   │   ├── Action.js           # DTO de ação pendente
│   │   │   ├── combatEvents.js     # Sistema de hooks (emitCombatEvent)
│   │   │   ├── DamageEvent.js      # Orquestrador da pipeline de dano
│   │   │   ├── snapshotChampions.js # Serialização para sync com cliente
│   │   │   ├── TurnResolver.js     # Resolução completa de um turno
│   │   │   └── pipeline/           # Etapas numeradas da pipeline de dano

**Sobre o campo `timing` (`pre`/`post`) nos diálogos:**

Eventos visuais (como dano, cura, buff, etc.) podem registrar diálogos associados ao evento, usando o campo `timing`:
- `pre`: o diálogo é exibido antes da animação do evento.
- `post`: o diálogo é exibido após a animação do evento.
Se não houver evento visual associado, o diálogo é enviado como global (fora da ordem dos eventos).
Esses campos permitem controlar a ordem e o momento exato em que mensagens aparecem durante a sequência de animações, garantindo feedback claro e contextual ao jogador.
│   │   │       ├── 01_preChecks.js
│   │   │       ├── 02_prepareDamage.js
│   │   │       ├── 03_composeDamage.js
│   │   │       ├── 04_beforeHooks.js
│   │   │       ├── 05_applyDamage.js
│   │   │       ├── 06_finishing.js
│   │   │       ├── 07_afterHooks.js
│   │   │       ├── 08_extraQueue.js
│   │   │       └── 09_resultBuilder.js
│   │   │
│   │   └── match/                  # Estado de sessão/partida
│   │       ├── GameMatch.js        # Container mestre (LobbyState + CombatState)
│   │       └── Player.js           # Dados de um jogador conectado
│   │
│   ├── data/
│   │   ├── championDB.js           # Re-export do índice de campeões
│   │   ├── champions/
│   │   │   ├── index.js            # Índice de todos os campeões registrados
│   │   │   ├── basicStrike.js      # Golpe básico global de contato (melee)
│   │   │   ├── basicShot.js        # Disparo básico global à distância (ranged)
│   │   │   ├── totalBlock.js       # Bloqueio defensivo global (self)
│   │   │   └── <champion>/         # Um diretório por campeão
│   │   │       ├── index.js        # Re-export: { ...data, skills, passive }
│   │   │       ├── data.js         # Stats base (HP, ATK, DEF, SPD, etc.)
│   │   │       ├── skills.js       # Array de skills
│   │   │       └── passive.js      # Objeto passiva com hooks
│   │   └── statusEffects/
│   │       ├── effectsRegistry.js
│   │       ├── stunned.js
│   │       ├── paralyzed.js
│   │       ├── rooted.js
│   │       ├── inert.js
│   │       ├── chilled.js
│   │       ├── frozen.js
│   │       ├── burning.js
│   │       ├── absoluteImmunity.js
│   │       ├── conductor.js
│   │       ├── poisoned.js         # (a implementar)
│   │       ├── bleeding.js         # (a implementar)
│   │       └── tributoDeSangue.js   # (a implementar)
│   │
│   ├── ui/
│   │   ├── formatters.js           # HTML formatters (nomes com cor de time)
│   │   ├── elementEmoji.js         # Mapeamento elemento → emoji
│   │   └── statusIndicator.js      # Gerenciador visual de ícones de status
│   │
│   ├── utils/
│   │   └── id.js                   # Gerador de IDs únicos
│   │
│   └── vfx/
│       ├── vfxManager.js           # Controle de canvas VFX sobre portraits
│       ├── shieldCanvas.js
│       ├── fireStanceCanvas.js
│       ├── frozenCanvas.js
│       ├── waterBubbleCanvas.js
│       └── obliterate.js
│
├── scripts/
│   ├── test.js
│   └── damageEventLab.js          # Laboratorio CLI isolado da pipeline de dano (DamageEvent)
├── exportChampionsToJson.js
└── package.json
```

### Notas sobre localização dos módulos

| Módulo               | Caminho canônico                        |
| -------------------- | --------------------------------------- |
| `DamageEvent`        | `shared/engine/combat/DamageEvent.js`   |
| `TurnResolver`       | `shared/engine/combat/TurnResolver.js`  |
| `Action`             | `shared/engine/combat/Action.js`        |
| `combatEvents`       | `shared/engine/combat/combatEvents.js`  |
| Pipeline steps       | `shared/engine/combat/pipeline/0N_*.js` |
| `GameMatch`          | `shared/engine/match/GameMatch.js`      |
| `Player`             | `shared/engine/match/Player.js`         |
| `Champion`           | `shared/core/Champion.js`               |
| `championCombat`     | `shared/core/championCombat.js`         |
| `championStatus`     | `shared/core/championStatus.js`         |
| `championUI`         | `shared/core/championUI.js`             |
| `formatChampionName` | `shared/ui/formatters.js`               |
| `server.js`          | `src/server.js`                         |

---

## 4. Fluxo de Jogo (Game Loop)

```
[LOGIN] → [SELEÇÃO DE CAMPEÕES (3)] → [ARENA / TURNOS (3 ativos fixos)] → [FIM DE JOGO]
```

O servidor gerencia toda a sessão por meio de uma instância de `GameMatch` (ver seção 6). `GameMatch` delega estado de lobby a `LobbyState` e estado de combate a `CombatState` — o `server.js` acessa ambos via interface pública de `GameMatch`.

### 4.1 Login

1. Jogador digita username e clica em "Entrar na Arena".
2. Cliente emite `requestPlayerSlot` com `username`.
3. Servidor tenta alocar o jogador no slot 0 (Time 1) ou slot 1 (Time 2). Máximo 2 jogadores.
4. Cria `new Player({ id, username, team })` e registra via `match.setPlayer(slot, player)`.
5. Servidor responde com `playerAssigned` → `{ playerId, team, username }`.

> No `editMode.autoLogin = true`, o servidor loga o jogador automaticamente com nome "Player1"/"Player2".

### 4.2 Seleção de Campeões

1. Quando ambos os jogadores conectam, servidor emite `allPlayersConnected` seguido de `startChampionSelection`.
2. Cliente exibe grade. Jogador monta equipe de **3 campeões** (drag & drop para ordenar).
3. Ao confirmar, cliente emite `selectTeam` com `{ team, champions: string[3] }`.
4. Servidor valida. Quando **ambos** confirmam, emite `allTeamsSelected` + `gameStateUpdate`.

> Timer de seleção: **120 segundos**. Ao expirar, campeões aleatórios preenchem os slots vazios.

### 4.3 Início de Partida

1. Servidor instancia os 3 campeões de cada equipe via `assignChampionsToTeam()` — slots 0, 1 e 2.
2. Não há fila de reserva no modo atual.
3. Partida começa com `match.startCombat()`.

### 4.4 Turno

```
[Jogadores agem] → [Ambos clicam "Finalizar Turno"] → [Servidor processa] → [Animações no client] → [Novo turno]
```

**Fase de Resolução (`handleEndTurn`):** Ambos confirmam. O servidor então:

1. Emite `turnLocked` para travar a UI dos jogadores.
2. Instancia `TurnResolver` e chama `resolver.resolveTurn()`:
   - Ordena `pendingActions` por `priority DESC` → `speed DESC` → desempate aleatório.

- Sistema de switch está desativado no modo atual.
- Executa cada ação de skill via `executeSkillAction()`.
- Processa mortes pós-resolução via `processChampionDeaths()`.

3. Não processa substituições (switch/reserva desativados).
4. Emite envelopes `combatAction` para cada resultado de ação executada.
5. Emite mortes de campeões (sem spawn automático de reserva no modo atual).
6. Dispara hooks `onTurnEnd`.
7. Limpa ações, avança turno, emite `combatPhaseComplete`.

**Fase pós-animações (`handleStartTurn`):** Ambos os clientes emitem `combatAnimationsFinished`. O servidor então:

1. Dispara hooks `onTurnStart` (DoTs como `burning` respondem aqui).
2. Executa `scheduledEffects` agendados para o turno atual.
3. Processa mortes por DoT/efeitos.
4. Purga status-effects e stat modifiers expirados.
5. Aplica regen global de ultômetro (+3 unidades por campeão vivo).
6. Emite envelope de "Início do Turno" com os efeitos visuais.
7. Emite `turnUpdate` e `gameStateUpdate`.

### 4.5 Morte e Pontuação (sem substituição)

- Se HP chega a 0 dentro de `applyDamage`, `target.alive = false`.
- Mortes são processadas pelo `TurnResolver.processChampionDeaths()` apenas **após todas as ações do turno** serem resolvidas.
- Para cada morte: `match.removeChampionFromGame(championId)`, que registra no histórico e move para `deadChampions`.
- Não há substituição automática por reserva no modo atual.
- Se um time ficar **sem nenhum campeão real** (`!entityType` ou `entityType === "champion"`) em `activeChampions`, o jogo termina imediatamente com vitória do adversário. Tokens e entidades especiais não contam para manter o jogador vivo.

### 4.6 Fim de Jogo

- `gameOver` é emitido com `{ winnerTeam, winnerName }`.
- Surrender: qualquer jogador pode se render a qualquer momento, concedendo vitória imediata ao adversário.

---

## 5. Camada de Rede — Socket.IO

### Eventos Cliente → Servidor

| Evento                     | Payload                           | Descrição                                      |
| -------------------------- | --------------------------------- | ---------------------------------------------- |
| `requestPlayerSlot`        | `username: string`                | Solicita entrada no jogo                       |
| `selectTeam`               | `{ team, champions: string[] }`   | Confirma seleção de equipe (3 campeões)        |
| `requestSkillUse`          | `{ userId, skillKey }`            | Pré-validação antes de mostrar overlay de alvo |
| `useSkill`                 | `{ userId, skillKey, targetIds }` | Enfileira ação com alvos confirmados           |
| `requestSwitch`            | —                                 | **Desativado por tempo indeterminado**         |
| `requestUndoActions`       | —                                 | Cancela todas as ações pendentes do jogador    |
| `endTurn`                  | —                                 | Confirma fim de turno                          |
| `surrender`                | —                                 | Rendição imediata                              |
| `combatAnimationsFinished` | —                                 | Informa que o cliente terminou as animações    |
| `debugResetCombat`         | —                                 | Reset de combate (debug)                       |
| `removeChampion`           | `{ championId }`                  | Remove campeão (edit mode)                     |

### Eventos Servidor → Cliente

| Evento                      | Payload                         | Descrição                                    |
| --------------------------- | ------------------------------- | -------------------------------------------- |
| `playerAssigned`            | `{ playerId, team, username }`  | Confirmação de login                         |
| `serverFull`                | `string`                        | Sala lotada                                  |
| `waitingForOpponent`        | `string`                        | Aguardando segundo jogador                   |
| `allPlayersConnected`       | —                               | Ambos jogadores conectados                   |
| `startChampionSelection`    | `{ timeLeft }`                  | Inicia seleção (timer)                       |
| `allTeamsSelected`          | —                               | Ambos confirmaram equipes                    |
| `gameStateUpdate`           | `{ champions[], currentTurn }`  | Estado completo do jogo                      |
| `combatAction`              | envelope tipado (ver seção 5.1) | Envelope de ação de combate                  |
| `combatLog`                 | `string`                        | Mensagem de log avulsa                       |
| `combatPhaseComplete`       | —                               | Todas as ações foram emitidas                |
| `turnLocked`                | —                               | Turno travado para resolução                 |
| `championRemoved`           | `championId: string`            | Campeão morreu                               |
| `championSwitchedOut`       | —                               | **Desativado por tempo indeterminado**       |
| `backChampionUpdate`        | —                               | **Desativado por tempo indeterminado**       |
| `turnUpdate`                | `number`                        | Número do novo turno                         |
| `playerConfirmedEndTurn`    | `playerSlot: number`            | Um jogador confirmou fim de turno            |
| `playerCanceledEndTurn`     | `playerSlot: number`            | Jogador cancelou confirmação de turno        |
| `waitingForOpponentEndTurn` | `string`                        | Aguardando adversário                        |
| `scoreUpdate`               | `{ player1, player2 }`          | Placar atualizado                            |
| `switchesUpdate`            | —                               | **Desativado por tempo indeterminado**       |
| `switchQueued`              | —                               | **Desativado por tempo indeterminado**       |
| `switchDenied`              | —                               | **Desativado por tempo indeterminado**       |
| `skillApproved`             | `{ userId, skillKey }`          | Skill pré-validada                           |
| `skillDenied`               | `string`                        | Motivo da negação                            |
| `actionFailed`              | `string`                        | Ação rejeitada                               |
| `actionsCanceled`           | —                               | Ações desfeitas com sucesso                  |
| `gameOver`                  | `{ winnerTeam, winnerName }`    | Fim de jogo                                  |
| `opponentDisconnected`      | `{ timeout }`                   | Oponente desconectou                         |
| `opponentReconnected`       | —                               | Oponente reconectou                          |
| `forceLogout`               | `string`                        | Desconexão forçada                           |
| `playerCountUpdate`         | `number`                        | Contagem de jogadores conectados             |
| `playerNamesUpdate`         | `[slot, username][]`            | Nomes dos jogadores                          |
| `editModeUpdate`            | `object`                        | Configurações de edit mode (sem server-only) |

### 5.2 Envelope de Ação (`combatAction`), Contexto e Timing (v5.1)

O envelope enviado do servidor para o cliente contém:

```js
{
  action: {
    userId, userName, skillKey, skillName, targetId, targetName
  },
  damageEvents: [ { ... } ],
  healEvents: [ { ... } ],
  shieldEvents: [ { ... } ],
  buffEvents: [ { ... } ],
  resourceEvents: [ { ... } ],
  dialogEvents: [ { ... } ],
  redirectionEvents: [ { ... } ],
  state: [ { ... } ]
}
```

- **Diálogos**: Todos os diálogos de combate agora usam `showDialog(message, duration?)` (bloqueante se sem duração, não-bloqueante se com duração).
- **Sequenciamento**: O cliente processa cada grupo (damageEvents, healEvents, etc.) em ordem, animando cada um sequencialmente.
- **Contexto**: O contexto (`context`) é criado por `TurnResolver.createBaseContext`, contendo informações do turno, campeões vivos, buffers de eventos visuais, etc.
- **Agendamento**: Efeitos podem ser agendados via `context.schedule`, processados em turnos futuros.

#### Constantes de Timing (v5.1)

```js
FLOAT_LIFETIME:   1900ms    // Número flutuante de dano
DEATH_ANIM:       2000ms    // Colapso de morte
DIALOG_DISPLAY:   2350ms    // Balão de diálogo
DIALOG_LEAVE:      160ms    // Fade out do diálogo
BETWEEN_EFFECTS:    60ms    // Intervalo entre efeitos
BETWEEN_ACTIONS:    60ms    // Intervalo entre ações
```

- **Esses valores controlam a duração de animações, diálogos e intervalos entre efeitos/ações.**
- **Toda a lógica de timing está centralizada em `animsAndLogManager.js` e alinhada ao CSS.**

#### Mudanças recentes

- Sistema de diálogos unificado (`showDialog`/`runDialogs`).
- Diálogos agora podem ser bloqueantes ou não-bloqueantes conforme o campo `duration`.
- Remoção de APIs antigas de diálogo.
- Refatoração para centralizar e simplificar a exibição de diálogos.

### 5.2 Mudanças v5.1.x — Sistema de Diálogos Unificado

**[2026-03-30]**

- **Unificação do sistema de diálogos:**
  - Todos os diálogos de combate agora são exibidos via uma única função `showDialog(message, duration?)`.
  - O parâmetro `duration` é opcional:
    - Se fornecido, o diálogo é exibido de forma não-bloqueante e some automaticamente após o tempo especificado (em ms).
    - Se omitido, o diálogo é bloqueante: só avança após o usuário clicar ou pressionar skip (nunca avança sozinho).
- **Remoção de APIs antigas:**
  - As funções `showBlockingDialog` e `showNonBlockingDialog` foram removidas.
  - Todos os pontos de exibição de diálogo (eventos, globais, helpers de animação) usam agora `showDialog` ou `runDialogs`.
- **API de múltiplos diálogos:**
  - O helper `runDialogs(dialogs)` exibe uma sequência de diálogos, respeitando o campo `duration` ou `blocking` de cada item.
  - Exemplo de uso:
    ```js
    runDialogs([
      { message: "Mensagem 1", duration: 1200 },
      { message: "Mensagem 2" }, // bloqueante
      { message: "Mensagem 3", duration: 800 },
    ]);
    ```
- **Semântica preservada:**
  - O comportamento de bloqueio permanece: diálogos sem `duration` nunca avançam sozinhos.
  - Diálogos não-bloqueantes (`duration` ou `{ blocking: false }`) avançam automaticamente após o tempo.
- **Refatoração interna:**
  - A lógica de exibição de diálogos foi centralizada e simplificada.
  - Funções intermediárias redundantes (ex: `processEventDialogs`) foram eliminadas e a lógica foi injetada diretamente nos despachantes de eventos.

---

## 6. Gerenciamento de Sessão — GameMatch e Player

**Arquivos**: `shared/engine/match/GameMatch.js`, `shared/engine/match/Player.js`

Estas duas classes encapsulam todo o estado mutável de uma partida no servidor. O `server.js` mantém uma instância de `GameMatch` e nunca manipula `activeChampions`, `pendingActions`, timers ou scores diretamente; tudo passa pela interface pública de `GameMatch`.

---

### 6.1 Player

`Player` representa um jogador conectado. É um objeto de dados simples sem lógica de combate.

```js
// shared/engine/match/Player.js
new Player({ id, username, team });
```

#### Propriedades

| Propriedade            | Tipo           | Descrição                                       |
| ---------------------- | -------------- | ----------------------------------------------- |
| `id`                   | `string`       | ID único do jogador (`"player1"` / `"player2"`) |
| `username`             | `string`       | Nome exibido                                    |
| `team`                 | `1 \| 2`       | Time do jogador                                 |
| `socketId`             | `string\|null` | Socket atual (pode mudar em reconexão)          |
| `selectedChampionKeys` | `string[]`     | Keys dos 3 campeões selecionados (em ordem)     |
| `remainingSwitches`    | `number`       | Mantido por compatibilidade; atualmente 0       |

#### Métodos

```js
player.setSocket(socketId);
player.clearSocket();
player.setSelectedChampionKeys(keys); // Define seleção de equipe (array de 3)
player.clearChampionSelection();
player.isTeamSelected(); // → boolean (seleção não-vazia)
```

---

### 6.2 GameMatch

`GameMatch` é o container mestre de uma partida. Internamente delega responsabilidades a duas classes privadas: **`LobbyState`** (gerencia sockets, timers e seleção) e **`CombatState`** (gerencia campeões, turnos, ações e placar). A API pública de `GameMatch` expõe os métodos de ambas.

```js
const match = new GameMatch();
```

#### Estrutura Interna

```
GameMatch
├── players: [Player|null, Player|null]   ← slot 0 e slot 1
├── lobby: LobbyState                     ← sockets, timers de seleção e desconexão
└── combat: CombatState                   ← campeões, turnos, ações e placar
```

---

#### 6.2.1 LobbyState

Gerencia o ciclo de entrada/saída de jogadores: mapeamento socket↔slot, timers de seleção de campeão e timers de reconexão.

```js
match.assignSocketToSlot(socketId, slot);
match.getSlotBySocket(socketId); // → slot | undefined
match.removeSocket(socketId);

match.setSelectionTimer(slot, timerId);
match.clearSelectionTimer(slot);

match.setDisconnectionTimer(slot, timerId);
match.getDisconnectionTimer(slot); // → timerId | undefined
match.clearDisconnectionTimer(slot);
```

---

#### 6.2.2 CombatState

Gerencia todo o estado de combate de uma partida.

```js
// Estado interno principal
combat.currentTurn; // number — turno atual (começa em 1)
combat.pendingActions; // Action[] — ações enfileiradas no turno corrente
combat.activeChampions; // Map<id, Champion> — campeões ativos em campo
combat.deadChampions; // Map<id, Champion> — campeões eliminados
// combat.benchedChampions; // desativado no modo atual
// combat.playerScores; // removido — sistema de pontos desativado
combat.gameEnded; // boolean
combat.started; // boolean
combat.playersReadyToEndTurn; // Set<slot>
combat.finishedAnimationSockets; // Set<socketId>
combat.combatSnapshot; // [{championKey, id, team, combatSlot}] — composição inicial
combat.turnHistory; // Map<turn, TurnData>
combat.scheduledEffects; // Effect[] — efeitos agendados para turnos futuros
// combat.reserveQueues; // desativado no modo atual
```

#### Métodos de CombatState

```js
// Equipe e posicionamento
combat.getTeamLine(team)              // → Champion[] ordenados por combatSlot
combat.getAdjacentChampions(target, {side})  // → Champion[] à esquerda/direita
combat.getChampionAtSlot(team, slot)  // → Champion | null
combat.getNextAvailableSlot(team, max) // → number | null
combat.canSpawnOnTeam(team, max)      // → boolean (slot livre?)
combat.getAliveCountForTeam(team)     // → number
combat.getAliveChampionsForTeam(team) // → Champion[]

// Registro/remoção
combat.registerChampion(champion, { trackSnapshot? })
combat.removeChampion(championId)     // → Champion | null
combat.removeChampionFromGame(championId, maxScore) // Morte com scoring + histórico
combat.removeChampionFromGame(championId) // Morte com checagem de fim de jogo baseada em campeões reais
combat.getChampion(championId)        // Busca em active + dead
combat.getAliveChampions()            // → Champion[] vivos

// Turno
combat.ensureTurnEntry()              // → TurnData (lazy-init)
combat.logTurnEvent(eventType, data)
```

---

#### 6.2.3 API Pública de GameMatch — Referência Completa

Toda interação do `server.js` com o estado da partida usa os métodos abaixo.

**Jogadores**

```js
match.getPlayer(slot); // → Player | null
match.setPlayer(slot, player);
match.getOpponent(slot); // → Player do outro slot
match.areBothPlayersConnected(); // → boolean
match.getConnectedCount(); // → 0 | 1 | 2
match.getPlayerNamesEntries(); // → [[slot, username], ...]
match.isTeamSelected(slot); // → boolean
match.clearPlayers(); // reseta players + lobby + combat
```

**Campeões**

```js
match.registerChampion(champion, { trackSnapshot? })
match.removeChampion(championId)
match.removeChampionFromGame(championId, maxScore)
match.getChampion(championId)
match.getAliveChampions()
```

**Turnos e Ações**

```js
match.getCurrentTurn();
match.nextTurn();
match.enqueueAction(action);
match.clearActions();

match.addReadyPlayer(slot);
match.removeReadyPlayer(slot);
match.isPlayerReady(slot);
match.getReadyPlayersCount();
match.clearTurnReadiness();

match.addFinishedAnimationSocket(socketId);
match.clearFinishedAnimationSockets();
match.getFinishedAnimationCount();
```

**Placar**

```js
// Sistema de pontos removido: não há mais addPointForSlot, setWinnerScore ou getScorePayload
match.isGameEnded();
```

**Ciclo de Combate**

```js
match.startCombat();
match.isCombatStarted();
match.resetCombat();
```

**Histórico e Efeitos Agendados**

```js
match.ensureTurnEntry();
match.logTurnEvent(eventType, eventData);
```

---

## 7. Classe Champion e Módulos Delegados

### 7.1 Champion (Fachada)

**Arquivo**: `shared/core/Champion.js`

A classe `Champion` é o objeto central de dados de um campeão, compartilhado entre server e client. Ela delega operações a 3 módulos especializados:

| Módulo              | Arquivo        | Responsabilidade                                   |
| ------------------- | -------------- | -------------------------------------------------- |
| `championCombat.js` | `shared/core/` | Dano, cura, escudos, buffs/debuffs, taunt, redução |
| `championStatus.js` | `shared/core/` | Aplicar/remover/purgar status-effects              |
| `championUI.js`     | `shared/core/` | Renderização DOM, barras de HP/ult, indicadores    |

### Propriedades Principais

```js
// Identidade
champion.id                  // string — ID único (ex: "ralia-uuid-...")
champion.name
champion.portrait            // path da imagem
champion.team                // 1 | 2
champion.combatSlot          // number — posição na line (0 ou 1)
champion.elementalAffinities // string[] (ex: ["lightning"])
champion.entityType          // "champion"

// Stats Atuais
champion.HP / champion.maxHP
champion.Attack / champion.Defense / champion.Speed
champion.Evasion / champion.Critical / champion.LifeSteal

// Stats Base (imutáveis, referência)
champion.baseAttack, champion.baseDefense, champion.baseSpeed, ...

// Recurso
champion.ultMeter            // 0 … ultCap
champion.ultCap              // máximo de unidades (padrão: 24 = 6 barras × 4 unidades)

// Combate
champion.skills              // Skill[]
champion.passive             // { key, hooks... } | null
champion.statusEffects       // Map<string, StatusEffectInstance>
champion.alive               // boolean
champion.hasActedThisTurn    // boolean

// Modificadores
champion.damageModifiers
champion.statModifiers
champion.tauntEffects
champion.damageReductionModifiers

// Runtime (temporário)
champion.runtime = {
  shields: Shield[],
  hookEffects: HookEffect[],
  currentContext: object,
  // Pode conter campos customizados por campeão (ex: fireStance, form, etc.)
}
```

Onde `StatusEffectInstance` representa o objeto completo do efeito ativo (não só duração), incluindo dados e handlers de hook:

```js
{
  key: "burning",
  expiresAtTurn: 12,
  duration: 2,
  appliedAtTurn: 10,
  hookScope: { onTurnStart: "owner" },
  subtypes: ["dot", "fire"],
  onTurnStart({ owner, context }) {
    // hook function do status-effect
  },
  // ...metadata adicional (source, flags, etc.)
}
```

### Factory

```js
Champion.fromBaseData(baseData, id, team, { combatSlot });
```

Cria a instância completa e injeta automaticamente um `hookEffect` de **imunidade elemental**: se o campeão tem afinidade com um elemento, ele é imune a status-effects com subtipo daquele elemento.

### Serialização

```js
champion.serialize() → {
  id, championKey, team, combatSlot, name, portrait,
  HP, maxHP, Attack, Defense, Speed, Evasion, Critical, LifeSteal,
  ultMeter, ultCap,
  runtime: { ...semHooksNemContext },
  statusEffects: [[key, safeValue], ...]
}
```

### 7.2 championCombat.js

Funções puras para mecânicas de dano, stats e escudos:

| Função                                   | Propósito                                         |
| ---------------------------------------- | ------------------------------------------------- |
| `takeDamage(champ, amount, ctx)`         | Consome escudos primeiro, depois HP               |
| `heal(champ, amount, ctx)`               | Restaura HP (capped em maxHP)                     |
| `modifyStat(champ, config)`              | Aplica buff/debuff baseado no sinal               |
| `buffStat(champ, config)`                | Buff com porcentagem ou valor flat                |
| `debuffStat(champ, config)`              | Debuff com porcentagem ou flat                    |
| `addShield(champ, config)`               | Adiciona camada de escudo (regular/spell/supreme) |
| `applyTaunt(champ, config)`              | Aplica efeito de taunt                            |
| `applyDamageReduction(champ, config)`    | Adiciona modificador de redução de dano           |
| `getTotalDamageReduction(champ)`         | Agrega reduções ativas → `{ flat, percent }`      |
| `purgeExpiredStatModifiers(champ, turn)` | Remove modifiers expirados, recalcula stats       |
| `addDamageModifier(champ, mod)`          | Adiciona modifier de dano de saída                |
| `getDamageModifiers(champ)`              | Retorna lista ativa                               |

### 7.3 championStatus.js

Gerenciamento de status-effects com validação de imunidade e armazenamento único em `statusEffects` (Map):

```js
applyStatusEffect(champ, key, duration, context, metadata, stackCount);
// 1. Valida registry
// 2. emitCombatEvent("onStatusEffectIncoming") — imunidades podem cancelar
// 3. Instancia via definition.createInstance(...) → new StatusEffect(...)
// 4. Registra em champion.statusEffects Map<string, StatusEffect>
// 5. Executa onStatusEffectAdded (quando existir)

removeStatusEffect(champ, name);
hasStatusEffect(champ, name);
getStatusEffect(champ, name);
purgeExpiredStatusEffects(champ, currentTurn);
```

As operações acima usam a key canônica do efeito diretamente (ex.: `"burning"`, `"frozen"`, `"absoluteImmunity"`). A camada de status aceita aliases legados em português apenas para compatibilidade.

### 7.4 championUI.js

Renderização DOM (executada apenas no client):

```js
renderChampion(champ, container, handlers); // Cria estrutura DOM completa
updateChampionUI(champ, options); // Sincroniza HP/ult bars, indicadores
syncChampionActionStateUI(champ); // Estado visual de ação (marcador)
destroyChampion(champ); // Remove elemento DOM
```

#### Estrutura DOM de um Campeão

```html
<div class="champion" data-champion-id="..." data-team="1">
  <div class="portrait-wrapper">
    <div class="portrait"><img src="..." /></div>
    <!-- canvas VFX são inseridos aqui -->
  </div>
  <h3 class="champion-name">Nome</h3>
  <p>HP: <span class="hp">100/200</span></p>
  <div class="hp-bar">
    <div class="hp-fill" />
    <div class="hp-segments" />
  </div>
  <div class="ult-bar">
    <div class="ult-fill" />
    <div class="ult-segments" />
  </div>
  <!-- indicadores de status renderizados pelo StatusIndicator -->
</div>
```

---

## 8. Sistema de Ultômetro (ultMeter)

Todos os campeões usam o **ultômetro** como sistema unificado de recurso para ultimates.

### Representação Interna

- **Barras visuais**: 6
- **Unidades internas**: 24 (cada barra = 4 unidades)

```js
champion.ultMeter = 0; // 0–24
champion.ultCap = 24; // padrão
```

### Ganho de Ultômetro

| Ação                       | Ganho           |
| -------------------------- | --------------- |
| Causar dano (skill normal) | +3 unidades     |
| Causar dano (ultimate)     | +1 unidade      |
| Tomar dano                 | +1 unidade      |
| Curar aliado               | +1 unidade      |
| Buffar aliado              | +1 unidade      |
| **Regen global por turno** | **+3 unidades** |

A regen global é aplicada no `handleStartTurn()` via `applyGlobalTurnRegen(champion, context, resolver)`, que **roteia através de `resolver.applyResourceChange()`** — garantindo que hooks como `onResourceGain` disparem normalmente (ex: passiva do Eryon acumula Ressonância a cada regen). Fallback para `champion.addUlt()` direto se sem resolver.

### Custo de Ultimates

```js
{
  isUltimate: true,
  ultCost: 4        // barras; servidor converte: costUnits = ultCost * 4
}
```

Conversão: `champion.getSkillCost(skill)` retorna `skill.ultCost * 4` (unidades internas).

---

## 9. Pipeline de Combate — DamageEvent

**Arquivo principal**: `shared/engine/combat/DamageEvent.js`
**Etapas**: `shared/engine/combat/pipeline/01_preChecks.js` … `09_resultBuilder.js`

`DamageEvent` é uma **classe instanciada por evento** (não singleton). Cada evento de dano cria uma instância independente, executa a pipeline numerada e retorna um resultado estruturado.

### Contrato Obrigatório de Dano

Toda instanciação de `new DamageEvent({...})` deve informar obrigatoriamente o campo `type`, com valor string exato `"physical"` ou `"magical"`.

Esse campo é parte do contrato canônico do motor de combate e passa por toda a pipeline, pelos hooks e pelo resultado final do evento.

### Relação com `basicShot`

O `basicShot` não fixa mais o tipo de dano no próprio arquivo base. O `type` do `DamageEvent` é decidido pela cópia da skill usada por cada campeão.

Exemplo:

```js
{ ...basicShot, type: "magical" }
```

Na prática, isso permite que o perfil do campeão, incluindo uma convenção como `damageType` em seus dados base, determine se o disparo básico será físico ou mágico sem precisar alterar a skill compartilhada.

### Convenção Oficial de Papéis

| Camada               | Alias canônico              |
| -------------------- | --------------------------- |
| Skill layer          | `user`, `targets`           |
| CombatEvents/hooks   | `source`, `target`, `owner` |
| DamageEvent/pipeline | `attacker`, `defender`      |

Não cruzar aliases entre camadas.

### `damageMode` (skill) vs `mode` (DamageEvent)

- Skills declaram `damageMode` (ex: `"standard"`, `"piercing"`, `"absolute"`).
- O `DamageEvent` opera com `mode` e usa `DamageEvent.Modes` como enum canônico.
- Quando não houver override explícito, o fluxo padrão deve respeitar `skill.damageMode ?? DamageEvent.Modes.STANDARD`.
- No estado atual:
  - `basicStrike` usa `damageMode: "standard"`.
  - `basicShot` usa `damageMode: "standard"`.
  - `totalBlock` é skill defensiva de hook e não instancia `DamageEvent` (sem fluxo de dano direto).

### Uso

```js
const result = new DamageEvent({
  baseDamage,
  attacker: user,
  defender: target,
  skill,
  type: "physical", // obrigatório: "physical" | "magical"
  context,
  mode: skill.damageMode ?? DamageEvent.Modes.STANDARD,
  piercingPercentage, // % da defesa do alvo a ignorar (0-100, modo piercing, default 100)
  critOptions, // { force?, disable? }
  allChampions, // Map — necessário para hooks
}).execute();
```

### Estado Interno da Instância

```js
this.baseDamage; // valor original recebido (imutável)
this.damage; // valor em transformação
this.finalDamage; // foto após composeDamage
this.preMitigationDamage; // foto antes da defesa
this.actualDmg; // dano efetivamente descontado do HP
this.hpAfter; // HP do defender após apply
this.crit; // { didCrit, bonus, roll, forced, critExtra, critBonusFactor }
this.lifesteal; // resultado de lifesteal ou null
this.beforeLogs; // string[] — logs de beforeHooks
this.afterLogs; // string[] — logs de afterHooks
this.extraResults; // resultados de DamageEvents extras (reações)
this.damageDepth; // profundidade de recursão (0 = ação principal)
```

### Fluxo Completo

```
skill.resolve({ user, targets, context })
  └── new DamageEvent(params).execute()
        ├── 1. preChecks()             [01_preChecks.js]
        ├── 2. prepareDamage()         [02_prepareDamage.js]
        ├── 3. composeDamage()         [03_composeDamage.js]
        ├── 4. runBeforeHooks()        [04_beforeHooks.js]
        ├── 5. applyDamage()           [05_applyDamage.js]
        ├── 6. processFinishing()      [06_finishing.js]
        ├── 7. runAfterHooks()         [07_afterHooks.js]
        ├── 8. processExtraQueue()     [08_extraQueue.js]
        └── 9. buildFinalResult()      [09_resultBuilder.js]
```

---

### Etapas em Detalhe

#### `01_preChecks.js`

```
├── emitCombatEvent("onDamageIncoming", ...)
│     → status-effects com onDamageIncoming (ex: absoluteImmunity) podem cancelar
│     → se cancelado: registerDamage({ flags:{immune:true} }); retorna
│
├── Evasão? (saltado se mode === "absolute" ou skill.cannotBeEvaded)
│     → rola evasão com defender.Evasion
│     → se evadido: registerDamage({ flags:{evaded:true} }); retorna
│
└── [Shield Block — reservado]
```

#### `02_prepareDamage.js` (saltado se mode === "absolute")

```
├── processCrit()
│     → rola chance vs Critical stat; dispara emitCombatEvent("onCriticalHit")
│     → popula this.crit = { didCrit, bonus, roll, forced, critExtra, critBonusFactor }
│
├── applyDamageModifiers()
│     → purga expirados; itera attacker.getDamageModifiers()
│     → cada mod.apply({ baseDamage, attacker, defender, skill }) → novo valor
│
└── applyAffinity()
      → weak:   (damage * 1.675) + 5
      → resist: damage *= 0.6
      → registra dialogEvent
```

#### `03_composeDamage.js`

```
├── ABSOLUTE: retorna sem modificação
│
├── Aplica crítico: damage += critExtra (se didCrit)
│
├── Defesa: mitPct = defToMitPct(defenseUsed)  ← curva não-linear
│   (crítico ignora buffs de defesa: usa Math.min(baseDefense, currentDefense))
│
├── STANDARD: damage -= damage * mitPct → redução % → redução flat
├── PIERCING: defenseUsed *= (1 - piercingPercentage/100) → mitPct(effectiveDef) → redução % → flat
│
├── Floor: Math.max(damage, 5)       ← exceto se ignoreMinimumFloor
├── Cap:   Math.min(damage, 999)     ← GLOBAL_DMG_CAP
├── Override: editMode.damageOutput sobrescreve se definido
│
└── Foto: this.finalDamage = this.damage
```

#### `04_beforeHooks.js` (saltado se mode === "absolute")

```
├── emitCombatEvent("onBeforeDmgDealing", ...)
└── emitCombatEvent("onBeforeDmgTaking", ...)

Retornos podem sobrescrever: damage, crit, logs, effects
```

#### `05_applyDamage.js`

```
defender.takeDamage(damage, context)
  → consome escudos regulares (FIFO) antes de debitar HP
  → se HP ≤ 0: defender.alive = false

context.registerDamage({ target, amount, sourceId, isCritical })
```

#### `06_finishing.js` — Pipeline de Finishing (Contrato Atual)

O pipeline de finishing agora é **genérico** e não depende mais de flags como `isObliterate` ou funções `obliterateRule`. Toda skill que executa ("finishing move") deve definir o campo `finishingType` (ex: "regular", "obliterate", etc). O pipeline verifica se a skill possui um tipo de finishing e aplica a lógica correspondente.

**Contrato oficial:**

- O pipeline espera que skills que executam tenham:
  - `finishingType: "regular"` (ou outro tipo, como "obliterate")
  - Opcionalmente, métodos auxiliares como `finishingRule()` e `finishingDialog()` para customizar o limiar e a mensagem.
- Ao atingir o limiar de execução, o pipeline registra:
  - `{ finishing: true, finishingType: "..." }` no evento de dano.
- Não existe mais flag `isObliterate`, nem função `obliterateRule`.

**Exemplo de skill (Isarelis):**

```js
{
  key: "golpe_de_misericordia",
  name: "Golpe de Misericórdia",
  bf: 85,
  damageMode: "standard",
  contact: true,
  isUltimate: true,
  ultCost: 3,
  priority: 0,
  executeThreshold: 0.2, // 20%
  stealthBonus: 0.5, // +50% dano se invisível
  damageBonusRatio: 0.2,
  piercingRatio: 0.6,
  finishingType: "regular",
  description() { ... },
  finishingRule({ defender }) {
    const maxHP = defender?.maxHP;
    if (!Number.isFinite(maxHP) || maxHP <= 0) return this.executeThreshold;
    return Math.min(this.executeThreshold, 80 / maxHP);
  },
  finishingDialog({ attacker, defender }) {
    return `${formatChampionName(attacker)} executa ${formatChampionName(defender)}!`;
  },
  resolve({ user, targets, context }) { ... }
}
```

**Resumo:**

- O pipeline de finishing é extensível e usa apenas `{ finishing: true, finishingType }`.
- Não há mais flags soltas ou nomes "obliterate" hardcoded.
- O tipo de finishing é definido por skill, e o frontend/animador consome apenas esse contrato.

#### `07_afterHooks.js`

```
├── emitCombatEvent("onAfterDmgTaking", ...)
├── emitCombatEvent("onAfterDmgDealing", ...)  ← suprimido se isDot
└── _applyLifeSteal()
      → heal = actualDmg * LifeSteal / 100 (floor aplicado em champion.heal)
```

#### `08_extraQueue.js`

```
Para cada extra em context.extraDamageQueue:
  → new DamageEvent({ ...extra, damageDepth+1 }).execute()
  → resultados em this.extraResults
```

#### `09_resultBuilder.js` — monta e retorna resultado final com `journey: { base, mitigated, actual }`.

### Damage Modes

| Mode         | Comportamento                                                                                                                                    |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `"standard"` | Pipeline completa com defesa, crit, hooks                                                                                                        |
| `"absolute"` | Bypassa prepareDamage, beforeHooks, evasão — dano direto ao HP                                                                                   |
| `"piercing"` | Ignora `piercingPercentage`% da defesa do alvo antes de calcular mitigação. Default 100% (ignora toda a defesa). Todo o baseDamage é perfurante. |

### `damageDepth` e Reações

`context.damageDepth` (padrão `0`) rastreia recursão. Passivas que geram dano de reação devem verificar depth antes de enfileirar.

### Flags de Skill

| Flag                                | Efeito                                          |
| ----------------------------------- | ----------------------------------------------- |
| `cannotBeEvaded: true`              | Pula evasão em `preChecks`                      |
| `cannotBeBlocked: true`             | Pula shield block em `preChecks`                |
| `obliterateRule(dmgEvent) → number` | Se HP/maxHP ≤ threshold → mata instantaneamente |

---

## 10. TurnResolver — Resolução de Turnos

**Arquivo**: `shared/engine/combat/TurnResolver.js`

`TurnResolver` é a classe responsável por processar todas as ações pendentes de um turno. Instanciada pelo `server.js` a cada chamada de `handleEndTurn()`.

### Instanciação

```js
const resolver = new TurnResolver(match, editMode);
const { actionResults, deathResults } = resolver.resolveTurn();
```

### Fluxo de `resolveTurn()`

1. **Loop de ações**: Enquanto houver ações pendentes:
   - Ordena por `priority DESC` → `speed DESC` → `Math.random()`.
   - Shifts a próxima ação.

- Sistema de switch está desativado no modo atual.
- Skills normais executam `executeSkillAction()`.

2. **Mortes pós-turno**: `processChampionDeaths()` coleta campeões com `alive === false`.
3. Retorna `{ actionResults, deathResults }`.

### `executeSkillAction(action, turnExecutionMap, context)`

```
1. Verifica se user está vivo → senão reembolsa recurso e retorna
2. canExecuteAction(user) → emitCombatEvent("onValidateAction")
  → hooks podem negar (stunned, frozen, etc.)
3. Resolve skill pelo skillKey
4. resolveSkillTargets() → resolve taunt, preenche roles, valida alvos
5. performSkillExecution() → executa skill.resolve(), captura snapshot intermediário
6. Retorna { executed, user, skill, context, action }
```

### `canExecuteAction(user, action)`

Emite `onValidateAction` para todos os campeões. Se qualquer hook retornar `{ deny: true }`, a ação é negada com mensagem.

### `resolveSkillTargets(user, skill, action, context)`

- **Taunt**: Se o usuário está tauntado, redireciona alvos "enemy" para o taunter.
- **AoE**: `targetSpec` com `"all-enemies"` / `"all-allies"` / `"all"` preenche automaticamente.
- **Normal**: Resolve `action.targetIds` para instâncias Champion vivas.
- Retorna objeto `{ enemy: Champion, ally: Champion, ... }` ou `null` se nenhum alvo válido.

### `performSkillExecution(user, skill, targets, context)`

1. Injeta `context` em todos os campeões via `runtime.currentContext`.
2. Chama `skill.resolve({ user, targets, context })`.
3. Limpa `runtime.currentContext`.
4. Registra uso de skill no histórico do turno.
5. Aplica regen de ultômetro pós-ação via `applyUltMeterFromContext()`.
6. Emite `onActionResolved` hook.

### `applyUltMeterFromContext({ user, context })`

| Condição                   | Ganho para user | Ganho para alvo |
| -------------------------- | --------------- | --------------- |
| Causou dano (skill normal) | +3              | —               |
| Causou dano (ultimate)     | +1              | —               |
| Curou aliado               | +1              | —               |
| Buffou aliado              | +1              | —               |
| Tomou dano                 | —               | +1 por alvo     |

### `createBaseContext({ sourceId })`

Cria o objeto `context` completo com todos os registries e helpers. Ver seção 11.

---

## 11. Sistema de Contexto e Efeitos Estruturados

### O Objeto `context`

Criado por `TurnResolver.createBaseContext()` a cada execução de skill ou início de turno. Serve como **acumulador de eventos de visualização** e helpers para a pipeline de combate.

```js
context = {
  currentTurn: number,
  editMode: object,
  allChampions: Map,
  aliveChampions: Champion[],
  // executionIndex, turnExecutionMap, currentSkill: podem ser injetados conforme necessário

  visual: {
    damageEvents:      [],
    healEvents:        [],
    buffEvents:        [],
    resourceEvents:    [],
    shieldEvents:      [],
    redirectionEvents: [],
    globalDialogs:     [], // fallback para diálogos não associados a eventos
  },

  // Helpers
  schedule(scheduledEffect),              // agenda efeito para turno futuro
  getTeamLine(team),                      // → Champion[] ordenados por combatSlot
  getAdjacentChampions(target, {side}),   // → Champion[] adjacentes

  // Registries
  registerDamage({ ... }),
  registerHeal({ ... }),
  registerBuff({ ... }),
  registerShield({ ... }),
  registerResourceChange({ ... }),
  registerDialog({ ... }),
}
```

#### Novo sistema de diálogos contextualizados

Ao invés de um array separado `dialogEvents`, agora os diálogos são automaticamente vinculados ao último evento relevante registrado (dano, cura, buff, escudo, recurso etc.) via o campo `dialogs` de cada evento. Isso garante que mensagens de diálogo sejam exibidas junto ao evento visual correspondente na UI.

Se um diálogo for registrado quando não há evento relevante (ex: diálogos globais de sistema), ele é adicionado ao array `visual.globalDialogs`.

Exemplo de evento com diálogos:

```js
{
  type: "damage",
  targetId: "ralia-uuid-...",
  sourceId: "kael-uuid-...",
  amount: 120,
  dialogs: [
    { message: "Ralia resistiu ao golpe!", blocking: true, sourceId: ..., targetId: ... }
  ]
}
```

O fallback global:

```js
visual.globalDialogs.push({ message: "Algo aconteceu!", ... });
```

### Efeitos Agendados (`context.schedule`)

```js
context.schedule({
  turnToHappen: context.currentTurn + 2,
  type: "damage" | "spawnChampion" | custom,
  payload: { ... },
  dialog: { message } // opcional — exibido ao executar
});
```

Efeitos são armazenados em `combat.scheduledEffects` e processados em `handleStartTurn()`.

### Como os Envelopes São Construídos

```
emitCombatEnvelopesFromContext({ user, skill, context })
  └── buildMainEnvelopeFromContext()
        → filtra context.visual.* onde damageDepth === 0
        → cada evento pode conter seu array de dialogs
        → globalDialogs são enviados separadamente se existirem
        → gera { action, damageEvents, healEvents, ..., state }
        → io.emit("combatAction", envelope)
```

---

## 12. Fórmulas de Dano e Defesa

### Fórmula de Dano Base

```
baseDamage = (user.Attack × BF / 100) + bonusFlat
```

### Defesa → Redução Percentual

Curva não linear em dois segmentos (`03_composeDamage.js → defenseToPercent`):

**Segmento 1 — Interpolação linear (Defense 0–220):**

| Defense | Redução |
| ------- | ------- |
| 0       | 0%      |
| 35      | 25%     |
| 60      | 40%     |
| 85      | 53%     |
| 110     | 60%     |
| 150     | 65%     |
| 200     | 72%     |
| 220     | 78%     |

**Segmento 2 — Cauda assintótica (Defense > 220):**

```
reduction = 0.75 + (0.95 - 0.75) × (1 - e^(-0.0045 × (defense - 220)))
```

Cap: nunca ultrapassa **95%**.

### Crítico

- Chance máxima: `MAX_CRIT_CHANCE = 95%`
- Bônus padrão: `DEFAULT_CRIT_BONUS = 55%` (`critBonusOverride` pode sobrescrever)
- Crítico **ignora buffs de defesa**: usa `Math.min(baseDefense, currentDefense)`
- Pode ser forçado (`critOptions.force`) ou bloqueado (`critOptions.disable`)

### Dano Mínimo

`Math.max(damage, 5)`, exceto se `context.ignoreMinimumFloor = true`.

### Cap Global

`DamageEvent.GLOBAL_DMG_CAP = 999`.

### Arredondamento e Precisão

Valores de dano e cura **não são arredondados para múltiplo de 5**. Eles percorrem toda a pipeline como **floats** e só sofrem `Math.floor` em pontos estratégicos — predominantemente nos métodos `takeDamage()` e `heal()` do campeão. Isso preserva a máxima fidedignidade do valor real após todos os processamentos percentuais, evitando que clamps intermediários distorçam o resultado final.

`roundToFive` é usado **apenas para buffs/debuffs de stats** (que não sejam HP). Dano, cura e HP são sempre inteiros, mas não necessariamente múltiplos de 5.

---

## 13. Sistema de Afinidades Elementais

### Ciclo Elemental

```
fire → ice → earth → lightning → water → fire → ...
```

Cada elemento é forte contra o próximo e fraco contra o anterior.

### Cálculo

```
Relação         → Efeito
═══════════════════════════════════════════
weak (fraqueza) → Math.floor(damage × 1.675 + 5)
resist          → damage *= 0.6
neutral         → sem modificação
```

### Declaração

```js
// Campeão:
elementalAffinities: ["lightning"];

// Skill:
element: "lightning";
```

### Emojis

```js
fire: "🔥", water: "🌊", lightning: "⚡", earth: "🌱", ice: "❄️"
```

---

## 14. Sistema de Hooks — CombatEvents

**Arquivo**: `shared/engine/combat/combatEvents.js`

`emitCombatEvent(eventName, payload, champions)` itera sobre todos os campeões e dispara o hook em:

1. `champ.passive` — passiva permanente.
2. `champ.statusEffects` — instâncias ativas de status no Map.
3. `champ.runtime.hookEffects` — efeitos temporários de runtime (não-status).

### Tabela de Hooks

| Hook                     | Quando dispara                       | Quem recebe tipicamente   |
| ------------------------ | ------------------------------------ | ------------------------- |
| `onDamageIncoming`       | Antes de qualquer cálculo de dano    | Alvo (imunidades)         |
| `onStatusEffectIncoming` | Antes de aplicar um status-effect    | Alvo (imunidades de CC)   |
| `onValidateAction`       | Antes de o campeão executar uma ação | Usuário (CC que bloqueia) |
| `onBeforeDmgDealing`     | Antes do atacante causar dano        | Atacante                  |
| `onBeforeDmgTaking`      | Antes do alvo receber dano           | Alvo                      |
| `onAfterDmgDealing`      | Após o atacante causar dano          | Atacante                  |
| `onAfterDmgTaking`       | Após o alvo receber dano             | Alvo                      |
| `onAfterLifeSteal`       | Após lifesteal ser aplicado          | Atacante                  |
| `onAfterHealing`         | Após cura ser registrada             | Todos                     |
| `onCriticalHit`          | Quando um crítico ocorre             | Atacante                  |
| `onTurnStart`            | Início de turno (após animações)     | Todos                     |
| `onTurnEnd`              | Fim de turno (antes de limpar ações) | Todos                     |
| `onActionResolved`       | Após resolução completa de uma ação  | Todos                     |
| `onChampionDeath`        | Quando um campeão morre              | Todos                     |
| `onResourceGain`         | Quando recurso (ult) é ganho         | Todos                     |
| `onResourceSpend`        | Quando recurso é consumido           | Todos                     |

### Contrato de Retorno de Hooks

```ts
{
  damage?: number,
  crit?: object,
  ignoreMinimumFloor?: boolean,
  log?: string | string[],
  logs?: string[],
  effects?: Effect[],
  deny?: boolean,      // (onValidateAction) nega a ação
  cancel?: boolean,    // (onDamageIncoming, onStatusEffectIncoming) cancela o evento
  immune?: boolean,    // (onDamageIncoming)
  message?: string,
}
```

### Scopes de Hook

```js
hookScope: {
  onBeforeDmgTaking: "target",
  onAfterDmgDealing: "source",
  onTurnStart: "source",
}
```

Scopes disponíveis: `"source"`, `"target"`, `"sourceOrTarget"`, `"allies"`, ou `undefined` (todos).

### Hook Effects Temporários (`runtime.hookEffects`)

```js
champion.runtime.hookEffects.push({
  key: "efeito_especial",
  group: "system", // runtime.hookEffects agora é para efeitos temporários não-status
  expiresAtTurn: context.currentTurn + 2,
  hookScope: { onBeforeDmgTaking: "target" },
  onBeforeDmgTaking({ damage }) {
    return { damage: damage * 0.5 };
  },
});
```

---

## 15. Sistema de StatusEffects

**Pasta**: `shared/data/statusEffects/`

StatusEffects são objetos de comportamento registrados em `effectsRegistry.js`. Quando aplicados, viram instâncias no `champion.statusEffects` (Map), com ciclo de vida autoritativo por `expiresAtTurn`.

Em termos práticos, o status é a própria fonte de hook. Ou seja: o motor de eventos lê os handlers diretamente da instância do status ativo, sem precisar espelhar esse status em `runtime.hookEffects`.

Importante: o valor armazenado no Map é a instância completa do status-effect (incluindo funções de hook como `onTurnStart`, `onBeforeDmgTaking`, etc.), não apenas `{ expiresAtTurn }`.

### Registry

```js
export const StatusEffectsRegistry = {
  paralyzed,
  stunned,
  rooted,
  inert,
  chilled,
  frozen,
  burning,
  bleeding,
  absoluteImmunity,
  conductor,
  // poisoned,     ← futuro
};
```

### Efeitos Implementados

| Efeito             | Key                | Tipo   | Subtypes          | Comportamento                                                          |
| ------------------ | ------------------ | ------ | ----------------- | ---------------------------------------------------------------------- |
| Paralisado         | `paralyzed`        | debuff | softCC, lightning | -100% SPD, 40% chance de negar ação                                    |
| Atordoado          | `stunned`          | debuff | hardCC            | Não pode agir (stun)                                                   |
| Enraizado          | `rooted`           | debuff | hardCC, nature    | Não pode usar skills de contato                                        |
| Inerte             | `inert`            | debuff | hardCC            | Não pode agir (auto-imposto)                                           |
| Gelado             | `chilled`          | debuff | statMod, ice      | -50% SPD/ATK                                                           |
| Congelado          | `frozen`           | debuff | hardCC, ice       | -100% SPD/ATK, não age, quebra ao sofrer dano                          |
| Queimando          | `burning`          | debuff | dot, fire         | 15 + 4% maxHP de dano no início do turno                               |
| Sangramento        | `bleeding`         | debuff | dot, physical     | 8% maxHP por stack no início do turno; acumula stacks e renova duração |
| Imunidade Absoluta | `absoluteImmunity` | buff   | immunity          | Imune a todo dano + debuffs                                            |
| Condutor           | `conductor`        | buff   | lightning         | Amplifica skills elétricas                                             |

### Regra de Hard CC

Apenas **um** hard CC (`subtypes: ["hardCC"]`) pode estar ativo por vez em um campeão.

### Ciclo de Vida

```
1. APLICAÇÃO: champion.applyStatusEffect(key, duration, context, metadata, stackCount)
   ├── Valida no StatusEffectsRegistry
   ├── emitCombatEvent("onStatusEffectIncoming") — pode cancelar
  ├── definition.createInstance(...) constrói `new StatusEffect(...)`
  ├── se for stackable e já existir, reaplica/refresh mantendo a mesma key canônica
   └── Registra em champion.statusEffects Map.set(key, statusEffectInstance)

2. DISPARO: emitCombatEvent itera passivas + statusEffects ativos + runtime.hookEffects

3. EXPIRAÇÃO: champion.purgeExpiredStatusEffects(currentTurn)
   → statusEffects.delete(key)

4. LIMPEZA DE RUNTIME (se houver): champion.purgeExpiredHookEffects(currentTurn)
   → remove apenas hookEffects de runtime com expiresAtTurn vencido
```

### Contrato da Instancia

Cada item do `champion.statusEffects` deve atender ao contrato abaixo:

```js
const effect = champion.statusEffects.get("burning");

effect instanceof StatusEffect; // true
typeof effect.onTurnStart === "function"; // hook direto na instância
effect.expiresAtTurn; // controle de expiração
```

### Serialização

```js
statusEffects: [["bleeding", { expiresAtTurn: 5, stacks: 3, stackCount: 3 }], ...]
// cliente reconstrói: new Map(snap.statusEffects)
```

No snapshot de rede/serialização, funções não trafegam. Ou seja, o cliente recebe uma versão data-only para UI/indicadores; os hooks funcionais permanecem no estado autoritativo do servidor.

---

## 16. Sistema de Escudos (Shields)

```js
// champion.runtime.shields
{
  amount: number,
  type: "regular" | "supremo" | "feitiço" | string,
  source: string,    // skill key
}
```

| Tipo        | Comportamento                                                      |
| ----------- | ------------------------------------------------------------------ |
| `"regular"` | Absorve HP de dano antes do HP do campeão (dentro de `takeDamage`) |
| `"supremo"` | Bloqueia a **ação inteiramente** (verificado em `preChecks`)       |
| `"feitiço"` | Bloqueia skills sem contato                                        |

Escudos regulares são consumidos em ordem FIFO.

---

## 17. Sistema de Modificadores de Dano

`champion.damageModifiers` — modifica o dano de saída:

```js
{
  name: string,
  apply({ baseDamage, user, target, skill }) → number,
  permanent: boolean,
  expiresAtTurn: number,
}
```

`champion.damageReductionModifiers` — reduz o dano recebido. Acessado via `getTotalDamageReduction()` → `{ flat, percent }`.

`champion.statModifiers` — buffs/debuffs de stats:

```js
{
  statName: string,
  amount: number,
  expiresAtTurn: number,
  isPermanent: boolean,
  ignoreMinimum?: boolean,
}
```

---

## 18. Status do Sistema de Switch (Temporariamente Desabilitado)

O sistema de **Switch/troca/reserva** está **temporariamente desabilitado por tempo indeterminado**.

### Status atual

- `requestSwitch` está desativado.
- Não há processamento de `switchResults` no fluxo de turno.
- Não há `spawnFromReserve()` no modo jogável atual.
- Eventos visuais de switch (`championSwitchedOut`, `backChampionUpdate`, `switchesUpdate`, `switchQueued`) estão desativados.

### Modo jogável vigente

- Formato **3v3 fixo**.
- **3 campeões por equipe** na seleção inicial.
- **3 campeões simultâneos em campo**.
- **3 como máximo por equipe** durante toda a partida.

---

## 19. Gerenciador de Animações — AnimsAndLogManager

**Arquivo**: `public/js/animation/animsAndLogManager.js`

Factory `createCombatAnimationManager(deps)` instanciada em `main.js`.

### Filosofia: Fila Determinística

```
Server emits → handler enqueues → drainQueue() processa um por vez → animações → applyStateSnapshots → next
```

### API Pública

```js
combatAnimations.handleCombatAction(envelope); // enqueue "combatAction"
combatAnimations.handleCombatLog(text); // enqueue "combatLog"
combatAnimations.handleGameStateUpdate(gameState); // enqueue "gameStateUpdate"
combatAnimations.handleTurnUpdate(turn); // enqueue "turnUpdate"
combatAnimations.handleChampionRemoved(championId); // enqueue "championRemoved"
// combatAnimations.handleChampionSwitchedOut(champId); // desativado no modo atual
combatAnimations.handleCombatPhaseComplete(); // enqueue "combatPhaseComplete"
combatAnimations.handleGameOver(data); // enqueue "gameOver"
combatAnimations.appendToLog(text);
combatAnimations.reset();
```

### Tipos de Item na Fila

| Tipo                  | Processamento                                                    |
| --------------------- | ---------------------------------------------------------------- |
| `combatAction`        | `processCombatAction(envelope)`                                  |
| `gameStateUpdate`     | `processGameStateUpdate(gameState)`                              |
| `turnUpdate`          | `processTurnUpdate(turn)`                                        |
| `championRemoved`     | `processChampionRemoved(id)` — animação de morte                 |
| `championSwitchedOut` | Desativado no modo atual                                         |
| `combatLog`           | `processCombatLog(text)` — dialog se relevante                   |
| `combatPhaseComplete` | Marca `currentPhase = "combat"` → dispara onQueueEmpty ao drenar |
| `gameOver`            | `handleGameOver(data)` — overlay final                           |

### Processamento de `combatAction`

```
1. handleActionDialog(action)
   └── Resolve userName/targetName via activeChampions (fallback: action.*Name)
       → showBlockingDialog

2. for ([key, events] of Object.entries(eventGroups)):
   ├── "damageEvents"      → animateDamage(event)
   ├── "healEvents"        → animateHeal(event)
   ├── "shieldEvents"      → animateShield(event)
   ├── "buffEvents"        → animateBuff (apenas primeiro evento do grupo)
   ├── "resourceEvents"    → animateResourceChange(event)
   ├── "redirectionEvents" → animateTauntRedirection(event)
   └── "dialogEvents"      → showBlockingDialog / showNonBlockingDialog

3. applyStateSnapshots(state)
   └── syncChampionFromSnapshot(champion, snap)
   └── champion.updateUI(options)
   └── syncChampionVFX(champion)
```

### Lógica de `animateDamage`

```
1. evaded?           → animateEvasion
2. immune?           → animateImmune
3. shieldBlocked?    → animateShieldBlock
4. isDot?            → showBlockingDialog pré-dano
5. Aplica classe .damage (shake + tint); cria float
6. finishing?        → playFinishingEffect
   senão             → updateVisualHP; isCritical → dialog "CRÍTICO"
```

### `syncChampionFromSnapshot`

Sincroniza stats, runtime, statusEffects e alive do champion local com o snapshot do servidor.

### Damage Tier (Tamanho do Float)

```
>= 251 → tier 6 | >= 151 → tier 5 | >= 101 → tier 4
>= 61  → tier 3 | >= 31  → tier 2 | else   → tier 1
```

### Constantes de Timing

```js
FLOAT_LIFETIME:   1900ms    // Número flutuante de dano
DEATH_ANIM:       2000ms    // Colapso de morte
DIALOG_DISPLAY:   2350ms    // Balão de diálogo
DIALOG_LEAVE:      160ms    // Fade out do diálogo
BETWEEN_EFFECTS:    60ms    // Intervalo entre efeitos
BETWEEN_ACTIONS:    60ms    // Intervalo entre ações
```

### Callback `onQueueEmpty`

Quando a fila esvazia **durante a fase "combat"**, o manager chama `onQueueEmpty()`, que dispara `socket.emit("combatAnimationsFinished")` no main.js, sinalizando ao servidor que as animações terminaram.

---

## 20. Sistema de VFX — vfxManager e Skill Animations

### 20.1 vfxManager — VFX Contínuos

**Arquivo**: `shared/vfx/vfxManager.js`

VFX contínuos renderizados via canvas HTML5 sobre o retrato do campeão. `syncChampionVFX(champion)` compara o estado atual com `champion._vfxState` e liga/desliga canvas conforme necessário.

| VFX                | Trigger                                                      |
| ------------------ | ------------------------------------------------------------ |
| `shield`           | `runtime.shields.length > 0`                                 |
| `fireStanceIdle`   | `runtime.fireStance === "postura"`                           |
| `fireStanceActive` | `runtime.fireStance === "brasa_viva"`                        |
| `frozen`           | `statusEffects.has("frozen")`                                |
| `waterBubble`      | `runtime.form === "bola_agua"`                               |
| `finishing`        | `playFinishingEffect(el, { variant })` — chamado diretamente |

### 20.2 Skill Animations — One-Shot WebGL

**Arquivo**: `public/js/animation/skillAnimations.js`

Sistema registry-based para animações one-shot de skills, renderizadas em `#webgl-container` overlay via Three.js (global).

```js
// Registrar nova animação:
registerSkillAnimation("skill_key", async ({ targetEl, userEl }) => { ... });

// Disparar (no-op se não registrada):
await animateSkill(skillKey, { targetEl, userEl });
```

**Integração**: chamado em `animsAndLogManager.js → processCombatAction()` logo após o dialog de ação, usando `action.skillKey`.

**Animação registrada atualmente:**

| Skill           | Campeão | Efeito                                                                                                                      |
| --------------- | ------- | --------------------------------------------------------------------------------------------------------------------------- |
| `gancho_rapido` | Kai     | Swipe trail + fist impact (procedural texture) + smoke particles. Direção calculada de `userEl` → `targetEl`. Lifetime: 2s. |

### 20.3 VFX WebGL One-Shot — deathClaim (Jeff)

**Arquivo**: `shared/vfx/deathClaim.js`

Efeito cinematográfico especial **"A Morte O Reclama"** disparado na Ultimate do Jeff the Death. WebGL com canvas full-screen, independente do sistema de skill animations.

---

## 21. Indicadores de Status — StatusIndicator

**Arquivo**: `shared/ui/statusIndicator.js`

```js
StatusIndicator.updateChampionIndicators(champion);
StatusIndicator.animateIndicatorAdd(champion, key);
StatusIndicator.animateIndicatorRemove(champion, key);
StatusIndicator.startRotationLoop();
StatusIndicator.clearIndicators(champion);
```

Cada status-effect tem um ícone visual (emoji ou imagem) com fundo colorido, renderizado sob o portrait do campeão. Se houver mais indicadores do que cabem, um loop de rotação os alterna.

---

## 22. Histórico de Turnos

Mantido em `match.combat.turnHistory: Map<number, TurnData>`:

```js
{
  events: [{ type, ...data, timestamp }],
  championsDeadThisTurn: [],
  skillsUsedThisTurn: {},    // { [championId]: skillKey[] }
  damageDealtThisTurn: {},   // { [championId]: totalDamage }
}
```

---

## 23. Modo de Edição / Debug

```js
const editMode = {
  enabled: true,
  autoLogin: true, // Pula tela de login
  autoSelection: false, // Seleção automática de campeões
  actMultipleTimesPerTurn: false,
  unavailableChampions: false, // Exibe campeões unreleased
  damageOutput: null, // Força dano fixo. null = desativado (SERVER-ONLY)
  alwaysCrit: false, // Força crítico sempre (SERVER-ONLY)
  alwaysEvade: false, // Força evasão sempre (SERVER-ONLY)
  executionOverride: null, // Sobrescreve threshold de obliterateRule (SERVER-ONLY)
  freeCostSkills: false, // Skills não consomem recurso
};
```

**Separação server/client**: `damageOutput`, `alwaysCrit`, `alwaysEvade` e `executionOverride` **não são enviados ao cliente**. O server emite `editModeUpdate` apenas com as propriedades de UI.

### 23.1 Damage Lab (harness CLI para agentes)

- Script: `scripts/damageEventLab.js`
- Atalho: `npm run damage-lab`
- Objetivo: executar cenarios de dano em isolamento (sem subir match completa), com rastreio de campos (`--track`), pre-skills (`--pre-skill`) e comparacao de passiva (`--compare-passive`).
- Uso no GSD/Copilot: funciona como "MCP" local de verificacao tecnica para agents, reduzindo custo de reproducao e permitindo validacao deterministica de hipoteses (critico, mitigacao, afinidade, hooks e thresholds de HP).
- Recomendacao operacional: rodar `damage-lab` antes/depois de mudancas em `DamageEvent`, steps da pipeline e `skills.js` para provar comportamento esperado.

---

## 24. Como Criar um Novo Campeão

### 1. Criar a pasta com 4 arquivos

```
shared/data/champions/meu_campeao/
├── index.js       # Re-export
├── data.js        # Stats base
├── skills.js      # Array de skills
└── passive.js     # Objeto passiva
```

### 2. `data.js` — Stats base

```js
export default {
  name: "Meu Campeão",
  portrait: "/assets/portraits/meu_campeao.webp",
  HP: 500,
  Attack: 80,
  Defense: 40,
  Speed: 70,
  Evasion: 0,
  Critical: 10,
  LifeSteal: 0,
  elementalAffinities: ["lightning"],
  damageType: "magical", // convenção do campeão para orientar skills compartilhadas como basicShot
  // unreleased: true,  ← oculta do pool padrão
};
```

### 3. `skills.js` — Array de habilidades

```js
import data from "./data.js";
import { DamageEvent } from "../../../engine/combat/DamageEvent.js";
import basicStrike from "../basicStrike.js";
import basicShot from "../basicShot.js";
import totalBlock from "../totalBlock.js";

const skills = [
  { ...basicStrike },
  { ...basicShot, type: data.damageType ?? "physical" },
  { ...totalBlock },
  {
    key: "minha_skill",
    name: "Nome da Skill",
    priority: 0,
    element: "fire",
    contact: true,
    damageMode: "standard",
    cannotBeEvaded: false,
    description() {
      return `Descrição.`;
    },
    targetSpec: ["enemy"],
    resolve({ user, targets, context }) {
      const [enemy] = targets;
      const baseDamage = (user.Attack * 80) / 100 + 30;
      return new DamageEvent({
        baseDamage,
        attacker: user,
        defender: enemy,
        skill: this,
        type: "physical",
        context,
        mode: this.damageMode,
        allChampions: context?.allChampions,
      }).execute();
    },
  },
  {
    key: "minha_ultimate",
    name: "Minha Ultimate",
    isUltimate: true,
    ultCost: 4, // 4 barras = 16 unidades
    priority: 0,
    // ...
  },
];
export default skills;
```

### 4. `passive.js` — Hooks

```js
import { formatChampionName } from "../../../ui/formatters.js";

const passive = {
  key: "passiva_meu_campeao",
  name: "Nome da Passiva",
  description: "Descrição.",

  hookScope: {
    onAfterDmgDealing: "source",
    onAfterDmgTaking: "target",
  },

  onAfterDmgDealing({ source, target, owner, damage, crit, skill, context }) {
    // ...
  },
  onAfterDmgTaking({ source, target, owner, damage, context }) {
    // ...
  },
  onTurnStart({ owner, context, allChampions }) {
    // ...
  },
};
export default passive;
```

### 5. `index.js` — Re-export

```js
import data from "./data.js";
import passive from "./passive.js";
import skills from "./skills.js";

export default { ...data, skills, passive };
```

### 6. Registrar no índice

```js
// shared/data/champions/index.js
import meu_campeao from "./meu_campeao/index.js";
const championDB = { /* ... */ meu_campeao };
export default championDB;
```

### 7. Boas Práticas

- **Dano sempre via `new DamageEvent(params).execute()`** — nunca debite HP diretamente.
- **Registros de cura/buff/escudo via `context.register*()`** — nunca escreva em `context.visual` diretamente.
- **Passivas devem verificar `damageDepth`** antes de enfileirar dano extra: `if (context.damageDepth > 0) return;`
- **`isDot = true`** em danos de tick de status-effects para suprimir `onAfterDmgDealing`.
- **`allChampions`** deve sempre ser passado ao `DamageEvent` se hooks de passivas precisam disparar.
- Use `context.getTeamLine(team)` e `context.getAdjacentChampions(target)` para skills posicionais.
- Use `context.schedule()` para efeitos que devem ocorrer em turnos futuros.

---

## 25. Decisões de Design e Convenções

### Por que 3v3 fixo no estado atual?

O formato **3v3 fixo** simplifica o fluxo de partida, reduz variáveis de sincronização de estado e mantém o combate mais previsível no estado atual do projeto. O sistema de switch permanece desativado por tempo indeterminado.

### Por que DamageEvent em vez de CombatResolver singleton?

- Cada evento tem seu próprio `this.damage`, `this.crit`, `this.actualDmg`.
- Pipeline linear e legível (`execute()` → etapas numeradas em arquivos separados).
- Recursão (`processExtraQueue`) cria novas instâncias isoladas — sem contaminação de estado.

### Por que a pipeline é dividida em 9 arquivos numerados?

Cada arquivo é responsável por exatamente uma etapa. Permite localizar bugs rapidamente, adicionar/remover etapas sem tocar no orquestrador, e testar individualmente.

### Por que TurnResolver como classe?

Encapsula toda a lógica de resolução de turno — ordenação de ações, validação via hooks, execução de skills, regen de ult, morte pós-turno. Evita que o `server.js` cresça desnecessariamente e facilita testes.

### Por que Champion delega a 3 módulos?

`Champion.js` permanece como fachada enxuta enquanto `championCombat.js`, `championStatus.js` e `championUI.js` lidam com domínios específicos. Facilita manutenção e impede que um único arquivo tenha centenas de métodos.

### Por que dados de campeão divididos em data/skills/passive.js?

Separar stats puros, habilidades com lógica de combate, e passivas com hooks permite navegar, editar e debugar cada aspecto independentemente.

### Por que GameMatch + LobbyState + CombatState?

O reset de uma partida é um único `match.resetCombat()`. LobbyState e CombatState têm responsabilidades claras e separadas. A interface pública de `GameMatch` é o único ponto de acesso.

### Por que status-effects como instâncias no Map?

Porque isso elimina duplicidade de estado. O status vive em uma única fonte de verdade (`champion.statusEffects`) e a expiração é centralizada por turno. O runtime continua para efeitos temporários que não são status, mantendo responsabilidades separadas.

### Por que Server Authoritative?

Num jogo PvP, o cliente não pode ser confiado para computar estado final.

### Por que a fila de animações no cliente?

Socket.IO pode entregar múltiplos eventos em rajada. A fila garante sequencialidade total; `applyStateSnapshots` ao final de cada ação garante consistência visual.

### Por que sincronização de animações (handshake)?

`handleStartTurn()` só roda **após ambos os clientes terminarem suas animações**. Isso garante que DoTs e efeitos de início de turno não sobreponham animações de combate em andamento.

### Convenção: Precisão de valores numéricos

Dano e cura trafegam como **floats** por toda a pipeline e só sofrem `Math.floor` nos endpoints (`takeDamage`, `heal`). `roundToFive` é reservado apenas para **buffs/debuffs de stats** (exceto HP). Isso garante que o valor final seja o mais fiel possível ao resultado real dos cálculos percentuais, sem distorções por arredondamentos intermediários.

### Aliases de hooks canônicos

| Nome legado       | Nome canônico atual  |
| ----------------- | -------------------- |
| `onBeforeDealing` | `onBeforeDmgDealing` |
| `onBeforeTaking`  | `onBeforeDmgTaking`  |
| `onAfterDealing`  | `onAfterDmgDealing`  |
| `onAfterTaking`   | `onAfterDmgTaking`   |

### `editMode` separado entre server e client

Flags que afetam combate (`damageOutput`, `alwaysCrit`, `alwaysEvade`, `executionOverride`) não são enviados ao cliente.

### Constantes de Jogo

| Constante                 | Valor   | Descrição                      |
| ------------------------- | ------- | ------------------------------ |
| `TEAM_SIZE`               | 3       | Campeões por equipe na seleção |
| `MAX_SCORE`               | 3       | Pontos para vencer             |
| Slots simultâneos         | 3       | Campeões em campo por time     |
| `CHAMPION_SELECTION_TIME` | 120s    | Timer de seleção               |
| `DISCONNECT_TIMEOUT`      | 30s     | Timeout de reconexão           |
| `ultCap` (padrão)         | 24      | 6 barras × 4 unidades          |
| Ult regen global          | +3/turn | Regen para todos os vivos      |
| Switches por jogador      | 0       | Sistema desativado atualmente  |

### Por que AudioManager como singleton?

Centraliza preload, volume e estado (enabled/disabled, playlist index) num único lugar. O cliente importa `audioManager` de qualquer módulo sem risco de múltiplas instâncias com estado inconsistente.

### Campeões Registrados (v5.2)

**22 campeões no DB** — ativos (sem `unreleased: true`) vs inativos:

| Key                  | Nome                                     | Status         |
| -------------------- | ---------------------------------------- | -------------- |
| `ralia`              | Ralia                                    | ativo          |
| `naelthos`           | Naelthos                                 | ativo          |
| `naelys`             | Naelys                                   | ativo          |
| `tharox`             | Tharox                                   | ativo          |
| `vael`               | Vael                                     | ativo          |
| `voltexz`            | Voltexz                                  | ativo          |
| `serene`             | Serene                                   | ativo          |
| `reyskarone`         | Reyskarone                               | ativo          |
| `gryskarchu`         | Gryskarchu                               | ativo          |
| `node_sparckina_07`  | Node Sparckina 07                        | ativo          |
| `kai`                | Kai                                      | ativo          |
| `barao_estrondoso`   | Barão Estrondoso                         | ativo          |
| `blyskartri`         | Blyskartri                               | ativo          |
| `elias_cross`        | Elias Cross                              | ativo          |
| `nythera`            | Nythera                                  | ativo          |
| `vulnara`            | Vulnara                                  | ativo          |
| `kael_drath_vulcano` | Kael Drath Vulcano                       | ativo          |
| `jeff_the_death`     | Jeff the Death                           | ativo          |
| `eryon`              | Eryon (Eidolon)                          | ativo          |
| `torren`             | Torren                                   | ativo          |
| `lana`               | Lana                                     | ativo          |
| `lana_dino`          | Tutu (**token** — `entityType: "token"`) | ativo          |
| `bruno`              | Bruno                                    | **unreleased** |

3 campeões comentados no índice (sem arquivo removido): `laisaelis`, `laiserisa`, `laisaelis_laiserisa`.

**Tokens**: Campeões com `entityType: "token"` entram em campo via efeito de skill (ex: Tutu invocada por Lana), não por seleção de equipe.

---

## 26. Sistema de Áudio — AudioManager

**Arquivo**: `public/js/utils/AudioManager.js`  
**Escopo**: client-only (não existe no servidor).

Singleton exportado como `audioManager`. Centraliza preload, registro, volume e playback de SFX e música de fundo.

### Categorias de som

| Categoria  | Registro                              | Controles                     |
| ---------- | ------------------------------------- | ----------------------------- |
| **SFX**    | `heal`, `damage`, `victory`, `defeat` | `sfxEnabled`, `sfxVolume`     |
| **Música** | `main`, `main2`                       | `musicEnabled`, `musicVolume` |

Ambas multiplicadas por `globalVolume` (master).

### API pública

```js
audioManager.preloadAll(); // chamado ao iniciar o cliente
audioManager.play("damage"); // dispara SFX
audioManager.playMusic(["main", "main2"]); // playlist em loop
audioManager.toggleMusic(bool);
audioManager.setMusicVolume(float);
audioManager.toggleSFX(bool);
audioManager.setSFXVolume(float);
audioManager.stopMusic();
```

### Integração

- **`main.js`**: chama `preloadAll()` no init; liga controles de UI (checkboxes/sliders de volume) via `toggleMusic`, `setMusicVolume`, `toggleSFX`, `setSFXVolume`.
- **`animsAndLogManager.js`**: importa `audioManager` e dispara SFX nos eventos de combate (dano, cura, etc.).
