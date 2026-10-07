# Regras — alpha 0.1

## Objetivo
Cada jogador tem um **Líder** com vida entre 20 e 30. Vence quem zerar a vida do Líder inimigo. Se os dois Líderes caírem ao mesmo tempo, é empate.

## Deck
- O deck tem **48 cartas**, com até **3 cópias** de cada uma. O Líder fica fora dessa contagem.
- As **essências** do Líder (ígnea, aquática, glacial, vegetal, rochosa, metálica, elétrica, obscura, sagrada) definem as cartas permitidas no deck. Cartas **neutras** entram em qualquer deck.
- O deck tem exatamente **1 Campeão Lendário**, que é a versão em carta do próprio Líder.

## Campeão Lendário (Zona de Comando)
- O Lendário começa na **Zona de Comando**, fora do deck, e pode ser conjurado de lá a qualquer momento da sua fase principal.
- Cada conjuração depois da primeira custa **+2 Momentum** a mais que a anterior.
- Quando o Lendário morre, ele volta para a Zona de Comando. A morte dele não afeta o Líder.

## Início da partida
- Quem joga primeiro começa com **6 cartas** na mão, e o outro jogador com **7**.
- **Mulligan:** cada jogador pode devolver até 3 cartas ao deck, que é embaralhado, e comprar a mesma quantidade.
- Quem joga primeiro **não compra** no primeiro turno.

## Momentum
- O Momentum máximo começa em **1** e sobe **+1 por turno**, até o teto de **10**.
- Ele é reabastecido no início do seu turno. O que sobra **não acumula** para o turno seguinte.

## Turno
1. **Início:** o Momentum é reabastecido, você compra 1 carta e suas criaturas ficam prontas.
2. **Fase principal:** jogue cartas, conjure o Lendário e use a habilidade do Líder.
3. **Ataque**, uma vez por turno: escolha os atacantes. Os ataques sempre miram o **Líder inimigo**.
4. **Bloqueios:** o defensor escolhe quem bloqueia. Cada bloqueador bloqueia **um único** atacante, e cada atacante pode ser bloqueado por **um único** bloqueador.
5. **Dano de combate:** primeiro causam dano as criaturas com Golpe Rápido, depois as demais. O dano é simultâneo dentro de cada passo. Um atacante que não foi bloqueado causa dano ao Líder.
6. **Segunda fase principal**.
7. **Fim do turno:** se você tiver mais de **10 cartas** na mão, escolha quais descartar até ficar com 10. Todo o dano nas criaturas é removido, assim como os bônus temporários.

## Regras gerais
- Cada lado pode ter no máximo **8 criaturas** em campo.
- Uma criatura recém-jogada não pode atacar no mesmo turno, a menos que tenha **Ímpeto**. Ela pode bloquear normalmente.
- A cura do Líder nunca passa da vida inicial dele.
- **Fadiga:** comprar uma carta com o deck vazio causa dano ao seu Líder. O dano é de 1 na primeira vez e sobe 1 a cada nova compra (2, 3, …).
- No v0.1 não existem instantâneos. A única ação possível no turno do adversário é bloquear.

## Tipos de carta
- **Campeão e Unidade:** são criaturas, com Ataque e Vida.
- **Feitiço:** produz o efeito e vai para o cemitério.
- **Equipamento:** dá um bônus permanente a uma criatura aliada.

## Keywords
| Keyword | Efeito |
|---|---|
| Ao Entrar | O efeito acontece quando a criatura entra em campo. |
| Ao Morrer | O efeito acontece quando a criatura morre. |
| Golpe Rápido | Causa dano de combate antes das criaturas sem Golpe Rápido. |
| Sobrepujança | O dano que exceder a vida restante do bloqueador vai para o Líder inimigo. |
| Roubo de Vida | O dano causado pela criatura cura o seu Líder. |
| Ímpeto | Pode atacar no turno em que entra em campo. |
| Voo | Só pode ser bloqueada por criaturas com Voo ou Longo Alcance. |
| Longo Alcance | Pode bloquear criaturas com Voo. |
| Furtivo | Só pode ser bloqueada por criaturas com Furtivo ou Vigia. |
| Vigia | Pode bloquear criaturas com Furtivo. |
| Provocação | Ao atacar, escolha uma criatura inimiga. Ela é obrigada a bloquear esta criatura, mesmo contra Voo ou Furtivo. |
| Escudo | Anula a próxima instância de dano. |

## Controles
- **Clique esquerdo:** jogar uma carta, selecionar atacantes, escolher alvos e atribuir bloqueios (primeiro o seu bloqueador, depois o atacante).
- **Clique direito numa carta:** abre o texto completo em tela cheia.
- **Clique direito ou Esc durante a escolha de alvo:** cancela.

## Gatilhos
Gatilhos dizem *quando* um efeito acontece. Eles abrem o texto da carta no lugar de frases por extenso, e ficam em `triggers` no `cards.json`.

| Gatilho | Quando |
|---|---|
| Ao Jogar | A carta é jogada da mão (feitiços e equipamentos). |
| Ao Entrar | A criatura entra em campo. |
| Ao Morrer | A criatura morre. |
| Ao Atacar | A criatura é declarada atacante. |
| Ao Bloquear | A criatura é declarada bloqueadora. |
| Ao Ser Bloqueada | Um bloqueador é atribuído a esta criatura atacante. |
| Ao Sofrer Dano | A criatura sofre dano (Escudo anulando o dano não conta). |
| Ao Atingir o Líder | A criatura causa dano a um Líder. |
| No Início do Turno | Começa o turno do dono da criatura. |
| No Fim do Turno | Termina o turno do dono da criatura. |

Alvos de gatilhos que não pedem escolha do jogador: `self`, `opposed_creature` (a criatura do outro lado do combate, ou a fonte do dano), `all_ally_creatures`, `all_creatures` (ambos os lados; o efeito de dano aceita `ally_reduce` para reduzir o dano em aliados de uma essência), `random_ally_creature`, `random_other_ally_creature`, `random_enemy_creature`, `random_enemy_and_adjacent` (uma criatura inimiga aleatória e as adjacentes), `all_enemy_creatures`, `enemy_leader` e `own_leader`. Só Ao Jogar e Ao Entrar podem usar alvo escolhido pelo jogador.
