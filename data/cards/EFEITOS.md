# Efeitos, alvos, condições e eventos

Referência do vocabulário que uma carta pode usar no JSON (`effects`, `activated.effects`, `ability.effects`). Tudo aqui é validado ao carregar o catálogo (`CardDB.errors()`): um erro de digitação aparece como erro, não como efeito que não faz nada.

Um efeito é um objeto:

```json
{ "trigger": "on_enter", "if": "momentum_left", "action": "damage", "target": "enemy_unit", "amount": 2 }
```

Campos comuns: `trigger` (ver Eventos), `if` (ver Condições), `action`, `target`, `pick2` (usa a segunda escolha da carta), `once_per_turn`, `not_in_combat`.

## Ações

Cada ação é uma classe em `scripts/engine/effects/`, registrada em `effect_registry.gd`.

| action | parâmetros | o que faz |
|---|---|---|
| `damage` | `amount`, `amount_from`, `ally_reduce` | dano ao alvo |
| `heal_leader` / `leader_max_up` / `heal_full` | `amount` | cura, aumenta a vida máxima ou cura tudo |
| `draw` / `draw_discounted` | `amount`, `min_base_cost`, `discount` | compra cartas (a segunda dá desconto à cópia na mão) |
| `tide_mark` | — | põe a Marca da Maré |
| `search_deck` / `look_top` | `count`, `shuffle` e filtros | abre escolha com cartas do deck |
| `freeze` | — | alvo não ataca nem bloqueia até o fim do próximo turno do dono |
| `summon` | `card` (`"self"` ou id), `overrides` | invoca uma carta |
| `mill` / `mill_pick` | `amount` | manda cartas do deck ao cemitério |
| `revive` / `revive_self` | `max_cost`, `atk`, `hp` | volta do cemitério |
| `destroy` / `banish` | — | mata / bane a unidade |
| `sacrifice` | `then` (lista de efeitos) | sacrifica; o `then` roda depois |
| `gain_momentum` | `amount`, `per`, `divisor`, `max`, `next_turn` | ganha Momentum |
| `buff` | `atk`, `hp`, `temp`, `keywords`, `armor`, `armor_temp`, `per`, `min`, `max`, `cap_atk` | bônus de ataque/vida/palavras-chave |
| `counter` | — | anula a carta escolhida na pilha |
| `modify_cost` | `amount` | muda o custo da carta (persiste entre zonas) |
| `cost_reduction` / `scale` | — | habilidades constantes (sem `target`, nunca disparam) |

## Alvos

Cada família é uma classe em `scripts/engine/targets/`.

- **Escolhidos pelo jogador:** `enemy_unit`, `ally_unit`, `other_ally_unit`, `any_unit`, `any`, `enemy_stack`
- **Grupos:** `all_enemy_units`, `all_units`, `all_ally_units`, `other_ally_units`
- **Líderes:** `enemy_leader`, `own_leader`, `both_leaders`
- **Aleatórios:** `random_enemy_unit`, `random_enemy_and_adjacent`, `random_ally_unit`, `random_other_ally_unit`
- **Da própria carta:** `self`, `self_card`, `opposed_unit`, `none`

## Condições (`if`)

- Nome simples: `momentum_left`, `reserve_full`, `played_two`.
- `{"all": [...]}`, `{"any": [...]}`, `{"not": ...}`: combinam outras condições e podem ser aninhados.
- `{"compare": {"stat", "who", "op", "value"}}`: `stat` é `leader_hp`, `momentum`, `reserve`, `units`, `hand`, `deck` ou `graveyard`; `who` é `self` ou `enemy`.
- `{"crossed_below": {"who", "value"}}` / `{"crossed_above": ...}`: a vida de um Líder acabou de cruzar a linha (só vale com `listen` de `leader_damaged`/`leader_healed`).

A condição é checada quando o gatilho acontece **e** de novo na resolução.

## Eventos

**Triggers de unidade** (`"trigger"`, só a própria carta): `on_play`, `on_enter`, `on_death`, `on_attack`, `on_block`, `on_blocked`, `on_damaged`, `on_hit_leader`, `on_turn_start`, `on_turn_end`, `on_ally_death`, `on_activate`, `transform`, `constante`.

**Eventos de escuta** (`"listen"`, de qualquer lugar): `leader_damaged`, `leader_healed`, `card_moved`, `unit_damaged` (`scope: self` = a própria unidade; tem `amount`, `hp_before`, `hp_after`), `card_drawn`, `turn_started`, `turn_ended` (nos turnos e compras, `ally` = do dono da carta).

```json
{
  "listen": "card_moved",
  "scope": "ally",
  "zones": "any",
  "when": { "to": "graveyard" },
  "action": "modify_cost", "target": "self", "amount": -1
}
```

- `scope`: `self`, `ally`, `enemy` ou `any`, relativo à carta que escuta.
- `zones`: onde a carta precisa estar (`board`, `hand`, `deck`, `graveyard`, `banished`); padrão `["board"]`, `"any"` = em qualquer zona.
- `when`: fatos que o evento precisa ter. `card_moved` tem `from` e `to`.
- `listen` e `trigger` não podem aparecer juntos.

Gatilhos que disparam durante uma ação entram numa fila e resolvem depois que a ação termina, um por vez, com o jogador ativo primeiro.

## Como criar uma ação nova

1. Crie `scripts/engine/effects/minha_acao_effect.gd` com `class_name MinhaAcaoEffect` e `extends Effect`.
2. Sobrescreva `_read_parameters(data)` para copiar os parâmetros do JSON em campos, e `apply(context, target_uid)` com o que a ação faz.
3. Acrescente uma linha em `EffectRegistry.ACTIONS`: `"minha_acao": MinhaAcaoEffect,`.
4. Use `"action": "minha_acao"` no JSON da carta e rode os testes: se algo estiver errado, `CardDB.errors()` diz.

Um alvo novo entra no `NAMES` de uma família (ou numa família nova listada em `TargetRegistry`); uma condição nova, em `ConditionRegistry`; um evento escutável, em `GameEvent.LISTENABLE`.
