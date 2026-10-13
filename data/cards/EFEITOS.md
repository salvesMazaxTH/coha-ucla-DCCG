# Efeitos, alvos, condições e eventos

Referência do vocabulário que uma carta pode usar no JSON (`effects`, `activated.effects`, `ability.effects`). Tudo aqui é validado ao carregar o catálogo (`CardDB.errors()`): um erro de digitação aparece como erro, não como efeito que não faz nada.

Um efeito é um objeto:

```json
{ "trigger": "on_enter", "if": "momentum_left", "action": "damage", "target": "enemy_unit", "amount": 2 }
```

Campos comuns: `trigger` (ver Eventos), `if` (ver Condições), `action`, `target`, `pick2` (usa a segunda escolha da carta), `once_per_turn`, `not_in_combat`, `not_token` (Aliado Morre ignora a morte de ficha).

## Ações

Cada ação é uma classe em `scripts/engine/effects/`, registrada em `effect_registry.gd`.

| action | parâmetros | o que faz |
|---|---|---|
| `damage` | `amount`, `amount_from`, `ally_reduce` | dano ao alvo |
| `heal_leader` / `leader_max_up` / `heal_full` | `amount` | cura, aumenta a vida máxima ou cura tudo |
| `heal_unit` | `amount`, `per` (`"armor"`, `"half_armor"`) | cura a unidade em `amount` (se o alvo for um Líder, cura o seu Líder), ou no valor da Armadura dela (`"armor"`) ou metade arredondada pra cima (`"half_armor"`) |
| `draw` / `draw_discounted` | `amount`, `min_base_cost`, `discount` | compra cartas (a segunda dá desconto à cópia na mão) |
| `tide_mark` | — | põe a Marca da Maré |
| `search_deck` / `look_top` | `count`, `shuffle` e filtros | abre escolha com cartas do deck |
| `snowball` | — | Bola de Neve: acerta o alvo com o nível atual do jogador, quica para um lado sorteado entre os que têm unidades (+1 de dano por quique) e o nível final vira o início da próxima. Nível 8 ou mais = Grande Bola (Sobrepujança nos quiques, custo +1 na carta). Num Líder é um golpe só e não aumenta o nível |
| `discard_hand_pick` | — | depois de comprar, o jogador escolhe uma carta da mão (mesma tela do descarte do overdraw) e ela vai ao **cemitério** (só o overdraw de fim de turno bane) |
| `transform_self` | `into` | a unidade vira a carta `into` (Ao Entrar da nova carta roda). Use com `target: "self"`, normalmente num `listen` |
| `freeze` | — | ATK do alvo fica 0 até o fim do próximo turno do dono |
| `fight` | `second_target` | o alvo (1ª escolha) e a unidade de `second_target` (2ª escolha) causam, ao mesmo tempo, dano igual ao Ataque de cada uma à outra. Não é combate; Armadura e Escudo valem, Escudo de Feitiço do inimigo cancela a luta |
| `summon` | `card` (`"self"` ou id), `overrides` | invoca uma carta |
| `mill` / `mill_pick` | `amount` | manda cartas do deck ao cemitério |
| `revive` / `revive_self` | `max_cost`, `atk`, `hp` | volta do cemitério |
| `destroy` / `banish` | — | mata / bane a unidade |
| `sacrifice` | `then` (lista de efeitos) | sacrifica; o `then` roda depois |
| `gain_momentum` | `amount`, `per`, `divisor`, `max`, `next_turn` | ganha Momentum |
| `buff` | `atk`, `hp`, `temp`, `keywords`, `armor`, `armor_temp`, `per`, `min`, `max`, `cap_atk` | bônus de ataque/vida/palavras-chave. Com `temp: true`, Ataque, Vida e palavras-chave duram só até o fim do turno |
| `counter` | `max_cost`, `kicker_cost`, `kicker_max_cost`, `only_if_targets_ally` | anula a carta escolhida na pilha. `only_if_targets_ally: true` só permite anular o que escolheu como alvo uma unidade ou o Líder de quem anula (efeitos em área não contam) |
| `modify_cost` | `amount` | muda o custo da carta (persiste entre zonas) |
| `cost_reduction` / `scale` | — | habilidades constantes (sem `target`, nunca disparam) |

## Alvos

Cada família é uma classe em `scripts/engine/targets/`.

- **Escolhidos pelo jogador:** `enemy_unit`, `ally_unit`, `other_ally_unit`, `ally_or_own_leader` (unidade aliada ou o seu Líder), `any_unit`, `any`, `enemy_stack`
- **Grupos:** `all_enemy_units`, `all_units`, `all_ally_units`, `other_ally_units`, `center_enemy_units` (meio do campo inimigo: 1 unidade se a quantidade é ímpar, as 2 do meio se é par)
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

**Triggers de unidade** (`"trigger"`, só a própria carta): `on_play`, `on_enter`, `on_death`, `on_attack`, `on_challenge` (Ao Desafiar: `opposed_unit` = a unidade desafiada), `on_challenged` (Ao Ser Desafiada: `opposed_unit` = o atacante), `on_damaged`, `on_hit_leader`, `on_turn_start`, `on_turn_end`, `on_ally_death`, `on_activate`, `transform`, `constante`.

**Eventos de escuta** (`"listen"`, de qualquer lugar): `leader_damaged`, `leader_healed`, `card_moved`, `unit_damaged` (`scope: self` = a própria unidade; tem `amount`, `hp_before`, `hp_after`), `card_drawn`, `turn_started`, `turn_ended` (nos turnos e compras, `ally` = do dono da carta), `spell_cast` (feitiço lançado; `essence_<id>: true` nos dados, ex.: `{"essence_glacial": true}`), `snowball_cast` (Bola de Neve lançada, antes dos golpes; `grande: true` se for Grande Bola, `amount` = dano inicial).

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

## Campos de carta especiais

- `spell_discount` (equipamento): `{"essence": "glacial", "amount": 1}`. O primeiro feitiço dessa essência lançado por turno pelo dono custa `amount` a menos.
- `{nivel}` (dentro do `text` de qualquer carta): vira o nível atual da Bola de Neve do dono ao desenhar a carta (mão, Santuário, escolha de cartas e visão ampliada); sem dono, vira 1. É só visual: o motor não lê o texto.
- `lethal_ward` (artefato, `true`): se o Líder do dono fosse morrer por uma instância de dano, o dano é anulado, o artefato é destruído e, até o fim do próximo turno do dono, todo dano ao Líder é dividido pela metade (arredondado pra baixo).

## Como criar uma ação nova

1. Crie `scripts/engine/effects/minha_acao_effect.gd` com `class_name MinhaAcaoEffect` e `extends Effect`.
2. Sobrescreva `_read_parameters(data)` para copiar os parâmetros do JSON em campos, e `apply(context, target_uid)` com o que a ação faz.
3. Acrescente uma linha em `EffectRegistry.ACTIONS`: `"minha_acao": MinhaAcaoEffect,`.
4. Use `"action": "minha_acao"` no JSON da carta e rode os testes: se algo estiver errado, `CardDB.errors()` diz.

Um alvo novo entra no `NAMES` de uma família (ou numa família nova listada em `TargetRegistry`); uma condição nova, em `ConditionRegistry`; um evento escutável, em `GameEvent.LISTENABLE`.
