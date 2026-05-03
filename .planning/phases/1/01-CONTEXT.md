# Phase 1 Context

## Goal
Estabelecer dominio canonico de cartas (Unit, Spell, Champion), raridade e essencias com neutralidade explicita, reutilizando entidades/modulos do baseline RPG.

## Constraints
- Reutilizar estrutura compartilhada (shared/core, shared/contracts).
- Evitar importar mecanicas RPG que nao fazem sentido direto para card game.

## Decisions
- Criar `shared/core/Card.js` como contrato canonico.
- Expor contratos de socket em `shared/contracts/SocketEvents.js` para reduzir drift.