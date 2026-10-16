# Efeitos, alvos, condições e eventos

Referência do vocabulário que uma carta pode usar no JSON (`effects`, `activated.effects`, `ability.effects`). Tudo aqui é validado ao carregar o catálogo (`CardDB.errors()`): um erro de digitação aparece como erro, não como efeito que não faz nada.

Um efeito é um objeto:

```json
{ "trigger": "on_enter", "if": "momentum_left", "action": "damage", "target": "enemy_unit", "amount": 2 }
```

Campos comuns: `trigger` (ver Eventos), `if` (ver Condições), `action`, `target`, `pick2` (usa a segunda escolha da carta), `once_per_turn`, `own_turn_only` (só funciona no turno do dono da carta), `not_in_combat`, `only_from_spell` (Ao Sofrer Dano só dispara se o dano veio de um feitiço sendo resolvido; Reflexão e combate não contam), `not_token` (Aliado Morre ignora a morte de ficha), `dying_card` (Aliado Morre só dispara se quem morreu é a carta com esse id, ex.: o Luto de Vael com `"myrra"`).

## Ações

Cada ação é uma classe em `scripts/engine/effects/`, registrada em `effect_registry.gd`.

| action | parâmetros | o que faz |
|---|---|---|
| `damage` | `amount`, `amount_from`, `ally_reduce`, `amount_if_frozen` | dano ao alvo (`amount_if_frozen`: dano maior se o alvo já estiver Congelado; `amount_from: "target_veneno_markers"`: `amount` de dano por marcador de Veneno no alvo) |
| `heal_leader` / `leader_max_up` / `heal_full` | `amount` | cura, aumenta a vida máxima ou cura tudo |
| `heal_unit` | `amount`, `per` (`"armor"`, `"half_armor"`) | cura a unidade em `amount` (se o alvo for um Líder, cura o seu Líder), ou no valor da Armadura dela (`"armor"`) ou metade arredondada pra cima (`"half_armor"`) |
| `draw` / `draw_discounted` | `amount`, `min_base_cost`, `discount` | compra cartas (a segunda dá desconto à cópia na mão) |
| `tide_mark` | — | põe a Marca da Maré |
| `search_deck` / `look_top` | `count`, `shuffle` e filtros (`essence`, `max_cost`, `type`, `types_any` (lista: serve qualquer um dos tipos), `species`, `tags`, `tags_any`), `top` | abre escolha com cartas do deck. `search_deck`: as opções são privadas de quem busca; o oponente só vê a carta escolhida (`search_take`). **Regra de design:** filtro amplo usa `top: N` (3–5): só as N cartas do topo são olhadas e as não escolhidas vão pro fundo do deck (sem embaralhar). Sem `top`, o deck inteiro é vasculhado e o embaralhamento acontece depois: só para filtros muito estreitos (uma carta específica, como a Bola de Neve do Bruno) |
| `snowball` | — | Bola de Neve: acerta o alvo com o nível atual do jogador (começa em 2 e **volta a 2 no fim do turno do dono**), quica para um lado sorteado entre os que têm unidades (+1 de dano por quique) e o nível final vira o início da próxima. `overflow_to_leader: true` dá Sobrepujança nos quiques (a carta Grande Bola de Neve usa; ao chegar no nível 8 as Bolas viram essa carta). Uma Bola lançada por unidade (sem carta) também tem Sobrepujança quando quem a lança está no nível 8+. Num Líder é um golpe só e não aumenta o nível. Quando o efeito vem de um gatilho de unidade (Tempesfrost, Ao Atacar), ele não resolve na hora: empilha uma carta virtual Bola de Neve (`virtual`, alvo forçado no alvo do ataque), que resolve depois como um feitiço comum |
| `discard_hand_pick` | — | depois de comprar, o jogador escolhe uma carta da mão (mesma tela do descarte do overdraw) e ela vai ao **cemitério** (só o overdraw de fim de turno bane) |
| `summon_hand_pick` | `rarity` | o jogador escolhe (em segredo) uma unidade da mão com essa raridade (`""` = qualquer) e ela entra em campo **sem pagar o custo**; no fim do turno é **banida** (não vai ao cemitério). Sem opção ou sem espaço no campo, nada acontece |
| `transform_self` | `into` | a unidade vira a carta `into` (Ao Entrar da nova carta roda). Use com `target: "self"`, normalmente num `listen` |
| `freeze` | — | alvo Congelado: não ataca, não desvira e não protege o Líder e perde a Rapidez (suprimida) até o fim do próximo turno. Revida normalmente (não exaure) |
| `add_dot` | `dot`, `amount` | adiciona `amount` marcadores acumuláveis do tipo `dot` à unidade alvo. `queimadura` causa dano igual aos marcadores; `veneno` e `sangramento` causam marcadores + bônus de Vida máxima (+0 em 1–5, +1 em 6–9, +2 em 10–13, depois +1 a cada 4 de Vida). O dano periódico ignora Armadura, Escudo e Escudo de Feitiço; Indestrutível ainda o impede. Em um Líder (`target: enemy_leader`) vale a mesma regra: no início do turno do dono do Líder ele sofre 1 de dano por marcador (sem bônus de Vida máxima; dano normal, a Câmara de Êxtase ainda vale). **Veneno decai devagar**: a cada tick todos os marcadores ferem, mas só 1 é removido (unidades e Líderes); Queimadura e Sangramento perdem todos. O motor não mata o Líder por acúmulo: isso é efeito de carta (`kill_leader`) |
| `exhaust` | — | a unidade alvo fica exausta (não ataca e pode ser desafiada); levanta no início do turno do dono. Combina com `freeze` na mesma escolha de alvo |
| `condemn` | — | a unidade alvo fica Condenada: morre no início do próximo turno de quem a condenou, mesmo que a fonte já tenha saído de campo. Indestrutível sobrevive (e gasta a marca); Escudo de Feitiço inimigo cancela a aplicação; sair de campo desfaz. A marca guarda o número do turno da execução (`Card.condemned_turn`) |
| `freeze_slots` | `count` (padrão 5) | Rei Gelado (Ao Entrar com `count` 5 e no início do próprio turno com `count` 1): sorteia `count` espaços do campo **inimigo** (alvo `none`), só entre os que **ainda não estão congelados**: unidades não congeladas + espaços vazios livres (sem relíquia e ainda não congelados). Se sobrarem menos que `count`, congela só os que sobraram. Unidade num espaço sorteado é congelada e exaurida (Escudo de Feitiço cancela e quebra); espaço vazio não aceita permanentes e descongela no **fim do próximo turno do oponente** |

**Regra geral dos sorteios de status:** efeitos que aplicam um status (`freeze`, `exhaust`, ...) com alvo aleatório nunca caem em unidade que já tem esse status; se todas já têm, o efeito não tem alvo. Quem define isso é `Effect.is_already_applied_to()` — um status novo (envenenado, paralisado...) só precisa sobrescrever esse método.
| `add_card` | `card` (id da carta), `to` (`deck_top` padrão ou `hand`) | Nythera: cria uma carta nova para o dono do efeito (alvo `none`) e a põe no topo do deck (a próxima compra) ou na mão. Uma Bola de Neve criada já nasce Grande se o dono estiver no nível Grande (no fim do turno dele as Grandes voltam a ser Bola de Neve) |
| `fight` | `second_target` | o alvo (1ª escolha) e a unidade de `second_target` (2ª escolha) causam, ao mesmo tempo, dano igual ao Ataque de cada uma à outra. Não é combate; Armadura e Escudo valem, Escudo de Feitiço do inimigo cancela a luta |
| `summon` | `card` (`"self"` ou id), `overrides` | invoca uma carta |
| `mill` / `mill_pick` | `amount`, `who` (`"enemy"` tritura o deck do oponente; padrão: o próprio) | manda cartas do deck ao cemitério do dono do deck. Com `who: "enemy"`, se faltar carta no deck do oponente para moer `amount`, ele sofre 1 Fadiga (uma só por efeito); moer o próprio deck nunca causa Fadiga |
| `fatigue_burn` | (nenhuma) | o oponente sofre agora a próxima Fadiga dele (2, 4, 8, 16…), mesmo com cartas no deck, e o contador avança |
| `grave_retrieve` | `card_id` ou `card_ids` (lista) | escolhe uma cópia no cemitério e leva à mão; ela é banida quando o próximo lançamento acabar |
| `snowball_level` | `amount` (padrão 1) | sobe o nível da Bola de Neve do controlador sem lançá-la (alvo `none`); `multiply` (ex.: 2) multiplica o nível em vez de somar; `permanent: true` (Devaneio Gelado) também sobe, pelo resto do jogo, o nível a que a Bola volta no fim de cada turno do dono (`snowball_base` do jogador, começa em 2) |
| `revive` / `revive_self` | `max_cost`, `atk`, `hp` | volta do cemitério |
| `destroy` / `banish` | `requires_markers` (só `banish`) | mata / bane a unidade. `requires_markers: {"dot": "veneno", "amount": X}` bane só se a unidade tiver X ou mais marcadores desse tipo, senão nada acontece |
| `kill_leader` | `requires_markers` | o Líder alvo (`target: enemy_leader`) morre na hora, ignorando Câmara de Êxtase, mas só se tiver `{"dot": "veneno", "amount": X}` marcadores ou mais; senão nada acontece (Viprax, com 8) |
| `hold_veneno` | `reach` (`leader` padrão ou `everyone`), `turn_starts` (padrão 2) | por tempo limitado, os marcadores de **Veneno** ainda causam dano no início do turno, mas **não decaem** (nem o 1 marcador de sempre). `reach: leader` (alvo `enemy_leader`): só o Veneno daquele Líder, nos próximos `turn_starts` turnos do dono dele (Antídoto Fora de Estoque). `reach: everyone` (alvo `none`): Veneno de todas as unidades e Líderes, nos próximos `turn_starts` inícios de turno de qualquer jogador, então 2 = uma rodada (Greve Geral dos Antídotos). Queimadura e Sangramento continuam sendo consumidos normalmente. Jogar de novo nunca encurta uma pausa em andamento |
| (campo da carta) `toxico_hits_leader` | — | `true` em uma unidade com Tóxico: o dano de combate dela ao Líder também coloca marcadores de Veneno nele (X do Tóxico X dela) |
| (palavra-chave) `toxico:N` / `toxico:atk` | — | em `keywords`: `"toxico"` coloca 1 marcador de Veneno por golpe; `"toxico:2"`, `"toxico:3"`… colocam N; `"toxico:atk"` coloca tantos marcadores quanto o Ataque atual da unidade (com buffs; Zophiróx). `toxico` continua na lista de keywords, então concessões e silêncios funcionam; uma unidade que só ganhou Tóxico em jogo tem Tóxico 1 |
| `sacrifice` | `then` (lista de efeitos) | sacrifica; o `then` roda depois |
| `gain_momentum` | `amount`, `per`, `divisor`, `max`, `next_turn` | ganha Momentum (`next_turn` com `amount` negativo = dívida: o próximo turno começa com menos Momentum, sem mexer no máximo e sem passar de 0) |
| `buff` | `atk`, `hp`, `temp`, `keywords`, `armor`, `armor_temp`, `atk_temp`, `critico_temp`, `per`, `min`, `max`, `cap_atk`, `bonus_if_card`, `armor_min`, `spell_shield_temp` | bônus de ataque/vida/palavras-chave. `atk_temp: N` dá N de Ataque até o início do próximo turno do dono da unidade (como `armor_temp`). `critico_temp: N` soma N níveis de Crítico até o fim do turno (total máximo 4). Com `temp: true`, Ataque, Vida e palavras-chave duram só até o fim do turno. `armor_min: N` faz a Armadura passar a ser N se for menor (nunca diminui). `spell_shield_temp: true` dá Escudo de Feitiço até o início do próximo turno do dono da unidade (não tira um escudo permanente que ela já tenha) |
| `counter` | `max_cost`, `kicker_cost`, `kicker_max_cost`, `only_if_targets_ally` | anula a carta escolhida na pilha. `only_if_targets_ally: true` só permite anular o que escolheu como alvo uma unidade ou o Líder de quem anula (efeitos em área não contam) |
| `modify_cost` | `amount` | muda o custo da carta (persiste entre zonas) |
| `cost_reduction` / `scale` | `per` (`own_artifacts` conta os artefatos do controlador, em campo ou equipados) | habilidades constantes (sem `target`, nunca disparam) |

## Alvos

Cada família é uma classe em `scripts/engine/targets/`.

- **Escolhidos pelo jogador:** `enemy_unit`, `ally_unit`, `other_ally_unit`, `ally_or_own_leader` (unidade aliada ou o seu Líder), `any_unit`, `any`, `enemy_stack`
- **Grupos:** `all_enemy_units`, `all_units`, `all_ally_units`, `other_ally_units`, `center_enemy_units` (meio do campo inimigo: 1 unidade se a quantidade é ímpar, as 2 do meio se é par)
- **Líderes:** `enemy_leader`, `own_leader`, `both_leaders`
- **Aleatórios:** `random_enemy_unit`, `random_frozen_enemy_unit` (só unidades já Congeladas), `random_enemy_and_adjacent`, `random_ally_unit`, `random_other_ally_unit`
- **Da própria carta:** `self`, `self_card`, `opposed_unit`, `attack_target` (só em Ao Atacar: a unidade desafiada, ou o Líder inimigo se o ataque foi no Líder), `none`

## Condições (`if`)

- Nome simples: `momentum_left`, `reserve_full`, `played_two`.
- `{"all": [...]}`, `{"any": [...]}`, `{"not": ...}`: combinam outras condições e podem ser aninhados.
- `{"compare": {"stat", "who", "op", "value"}}`: `stat` é `leader_hp`, `momentum`, `reserve`, `units`, `hand`, `deck` ou `graveyard`; `who` é `self` ou `enemy`.
- `{"crossed_below": {"who", "value"}}` / `{"crossed_above": ...}`: a vida de um Líder acabou de cruzar a linha (só vale com `listen` de `leader_damaged`/`leader_healed`).

A condição é checada quando o gatilho acontece **e** de novo na resolução.

## Eventos

**Triggers de unidade** (`"trigger"`, só a própria carta): `on_play`, `on_enter`, `on_death`, `on_attack`, `on_challenge` (Ao Desafiar: `opposed_unit` = a unidade desafiada), `on_challenged` (Ao Ser Desafiada: `opposed_unit` = o atacante), `on_damaged`, `on_hit_leader`, `on_turn_start`, `on_turn_end`, `on_ally_death`, `on_activate`, `transform`, `constante`, `condicional`. Os dois últimos são rótulos de leitura: `constante` é o único usado em `"trigger"` (Jeff, Berengar Voss); `condicional` não vai em `"trigger"`. Ele aparece sozinho na face da carta quando ela tem um efeito `"listen"` (ou `lethal_ward`/`spell_discount`), e a face também mostra "Constante" para regras sempre ligadas (`cost_reduction`, `scale`, `adjacent_armor`).

**Eventos de escuta** (`"listen"`, de qualquer lugar): `leader_damaged`, `leader_healed`, `card_moved`, `unit_damaged` (`scope: self` = a própria unidade; tem `amount`, `hp_before`, `hp_after`), `card_drawn`, `turn_started`, `turn_ended` (nos turnos e compras, `ally` = do dono da carta), `spell_cast` (feitiço lançado; `essence_<id>: true` nos dados, ex.: `{"essence_glacial": true}`), `snowball_cast` (Bola de Neve lançada, antes dos golpes; `grande: true` se for Grande Bola, `amount` = dano inicial), `snowball_grande` (o nível da Bola de Neve acabou de cruzar para Grande; dispara só na passagem).

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

- `spell_discount` (equipamento): `{"essence": "glacial", "amount": 2, "min_cost": 1}`; vários equipamentos somam, e `min_cost` (opcional) é o piso do custo. O primeiro feitiço dessa essência lançado por turno pelo dono custa `amount` a menos.
- `face_text` (feitiço, opcional): versão curta do texto, desenhada só no rosto da carta pequena quando o `text` completo não cabe. A visão ampliada continua mostrando o `text`. Aceita `{nivel}`.
- `{nivel}` (dentro do `text` de qualquer carta): vira o nível atual da Bola de Neve do dono ao desenhar a carta (mão, Santuário, escolha de cartas e visão ampliada); sem dono, vira 2. É só visual: o motor não lê o texto.
- `lethal_ward` (artefato, `true`): se o Líder do dono fosse morrer por uma instância de dano, o dano é anulado, o artefato é destruído e, até o fim do próximo turno do dono, todo dano ao Líder é dividido pela metade (arredondado pra baixo).

## Como criar uma ação nova

1. Crie `scripts/engine/effects/minha_acao_effect.gd` com `class_name MinhaAcaoEffect` e `extends Effect`.
2. Sobrescreva `_read_parameters(data)` para copiar os parâmetros do JSON em campos, e `apply(context, target_uid)` com o que a ação faz.
3. Acrescente uma linha em `EffectRegistry.ACTIONS`: `"minha_acao": MinhaAcaoEffect,`.
4. Use `"action": "minha_acao"` no JSON da carta e rode os testes: se algo estiver errado, `CardDB.errors()` diz.

Um alvo novo entra no `NAMES` de uma família (ou numa família nova listada em `TargetRegistry`); uma condição nova, em `ConditionRegistry`; um evento escutável, em `GameEvent.LISTENABLE`.

## Campos de Crítico (na própria carta, fora de `effects`)

- Palavra-chave `"critico:N"` em `keywords` (N de 1 a 4): nível impresso de Crítico.
- `critico_growth: true`: cada crítico causado sobe o Crítico da carta em 1 nível permanente (até 4). Hoje só Vael. O nível alcançado vale para TODAS as cópias dele do jogador (campo, mão, deck, cemitério, banidas) e para as futuras.
- `critico_maximo: {"bonus": 4, "ataque_duplo": true}`: ao chegar no Crítico 4 o crítico da carta dá `bonus` (em vez de +2) e `ataque_duplo` libera o segundo ataque. Hoje só Vael.
- `imune_critico: true`: o dano de combate que a carta recebe nunca é crítico (Desdém de Rália).
