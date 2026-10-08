# Regras — alpha 0.2

## Objetivo
Cada jogador tem um **Líder** com vida entre 20 e 30. Vence quem zerar a vida do Líder inimigo. Se os dois Líderes caírem ao mesmo tempo, é empate.

## Deck
- O deck tem **48 cartas**, com até **3 cópias** de cada uma. O Líder fica fora dessa contagem.
- As **essências** do Líder (ígnea, aquática, glacial, vegetal, rochosa, metálica, elétrica, obscura, sagrada) definem as cartas permitidas no deck. Cartas **neutras** entram em qualquer deck.
- Uma carta pode ter **mais de uma essência** (ex.: Sabrina é aquática e glacial, com moldura meio a meio). Ela é permitida se tiver **pelo menos uma** das essências do Líder.
- **Fora da essência:** o deck pode ter até **12 cartas** (contando cópias) de essências que o Líder não tem, de qualquer raridade, com o limite normal de 3 cópias. Cartas neutras não entram nessa conta, e **Campeões** nunca podem ser de fora da essência.
- O deck tem exatamente **1 Encarnação do Líder**, o Campeão que é a versão em carta do próprio Líder.

## Encarnação do Líder (Santuário)
- A Encarnação começa no **Santuário**, fora do deck, e pode ser conjurada de lá a qualquer momento da sua fase principal.
- Cada conjuração depois da primeira custa **+2 Momentum** a mais que a anterior.
- Quando a Encarnação morre, ela volta para o Santuário. A morte dela não afeta o Líder.

## Início da partida
- Quem joga primeiro começa com **6 cartas** na mão, e o outro jogador com **7**.
- **Mulligan:** cada jogador pode devolver até 3 cartas ao deck, que é embaralhado, e comprar a mesma quantidade.
- Quem joga primeiro **não compra** no primeiro turno.

## Momentum
- O Momentum máximo começa em **1** e sobe **+1 por turno**, até o teto de **10**.
- Ele é reabastecido no início do seu turno. O que sobra **não acumula** para o turno seguinte.

## Turno
1. **Início:** o Momentum é reabastecido, você compra 1 carta e suas unidades ficam prontas.
2. **Fase principal:** jogue cartas, conjure a Encarnação e use a habilidade do Líder.
3. **Ataque**, uma vez por turno: escolha os atacantes. Os ataques sempre miram o **Líder inimigo**.
4. **Bloqueios:** o defensor escolhe quem bloqueia. Cada bloqueador bloqueia **um único** atacante, e cada atacante pode ser bloqueado por **um único** bloqueador.
5. **Dano de combate:** primeiro causam dano as unidades com Golpe Rápido, depois as demais. O dano é simultâneo dentro de cada passo. Um atacante que não foi bloqueado causa dano ao Líder.
6. **Segunda fase principal**.
7. **Fim do turno:** se você tiver mais de **10 cartas** na mão, escolha quais **banir** até ficar com 10 (não vão ao cemitério; o oponente não vê quais foram). Todo o dano nas unidades é removido, assim como os bônus temporários.

## Regras gerais
- Cada lado pode ter no máximo **8 unidades** em campo.
- Uma unidade recém-jogada não pode atacar no mesmo turno, a menos que tenha **Ímpeto**. Ela pode bloquear normalmente.
- A cura do Líder nunca passa da vida inicial dele.
- **Banimento:** carta banida sai do jogo: não vai ao cemitério, então não alimenta Encarnação, Vagante etc. e não conta como morrer. A compra não tem teto durante o turno (a mão pode passar de 10, inclusive no turno do oponente); só no fim do seu turno você bane as piores até voltar a 10. Banir da mão é oculto para o oponente; efeitos de banimento (ex.: em área) serão públicos.
- **Fadiga:** comprar uma carta com o deck vazio causa dano ao seu Líder. O dano é de 1 na primeira vez e sobe 1 a cada nova compra (2, 3, …).

## Velocidade, pilha e janelas
- Toda carta e habilidade de Líder tem uma velocidade, definida no campo `"speed"` do JSON. Sem o campo, ela é **lenta**.
  - Equipamentos (artefatos) são lentos, a não ser que tenham a tag **Saque Rápido** (`saque_rapido`), que os torna rápidos.
  - **Lenta:** só na sua fase principal, com a pilha vazia.
  - **Rápida:** também nas janelas de combate.
  - **Instantânea:** também em resposta a qualquer coisa na pilha.
- Unidades, a Encarnação, atacar e encerrar o turno seguem a regra das lentas. Unidades não usam a pilha.
- **Pilha:** feitiços, equipamentos e habilidades vão para a pilha, e a prioridade passa para o adversário.
  - Quem tem prioridade pode responder com uma Instantânea ou passar.
  - Quando alguém passa, a pilha inteira resolve, do mais novo para o mais antigo.
  - Um efeito cujo alvo deixou de ser válido é anulado.
  - **Anular (counter):** alguns Instantâneos (ex.: Negação de Neraqa) miram um feitiço ou habilidade **inimiga** na pilha. **Equipar não pode ser anulado**, mas pode ser respondido (o equipamento é conjurado em velocidade lenta e fica na pilha até resolver). O item anulado sai da pilha sem efeito, e a carta vai para o cemitério. Se o custo do alvo passa do limite da carta, o custo extra (ex.: +3) é cobrado automaticamente quando você escolhe esse alvo.
- **Janelas de combate:** depois de declarar os atacantes, as janelas vêm nesta ordem:
  1. Ataque, para o atacante.
  2. Preparação, para o defensor.
  3. Bloqueios.
  4. Dano: o atacante tem a prioridade primeiro.
- **Na janela de dano:**
  - Se o atacante passa, a prioridade vai para o defensor.
  - O dano de combate acontece quando os dois passam seguidos com a pilha vazia.
  - Se alguém joga algo, a pilha resolve normalmente e a prioridade volta para o atacante.
- Atacantes que morrem durante as janelas saem do combate.
- **Os bloqueios são definitivos.** Se o bloqueador morre antes do dano, o atacante continua bloqueado e não acerta o Líder. Com Sobrepujança, todo o dano dele vai para o Líder.
- Se o atacante morre antes do dano, o bloqueador não causa dano.
- Quem não tem nenhuma jogada possível passa automaticamente.
- **Ordem de resolução no combate:**
  - Os atacantes causam dano na **ordem em que foram declarados** (a UI mostra esse número em cada atacante). Cada atacante bate primeiro, o bloqueador dele logo em seguida. Golpe Rápido sempre vem antes, em um passo à parte.
  - O dano dentro de um passo **não é totalmente simultâneo**: efeitos reativos (como Ao Sofrer Dano) resolvem na hora e podem afetar os pares seguintes. As mortes só são processadas ao fim do passo, então quem recebeu dano letal ainda bate de volta no mesmo passo.
  - Quando unidades dos dois lados morrem ao mesmo tempo, as mortes (Ao Morrer, Aliado Morre) resolvem primeiro para o **jogador da vez**, depois para o oponente.

## Olhar o topo do deck
- Alguns efeitos (ex.: Serpente Marinha) olham as N cartas do topo do deck. Só o dono vê essas cartas; ele coloca 1 na mão, e só essa é revelada ao oponente. As outras vão para o fundo do deck.

## Tipos de carta
- **Unidade (comum ou épica), Campeão e Lendário:** são unidades, com Ataque e Vida.
- **Feitiço:** produz o efeito e vai para o cemitério.
- **Artefato:** tipo de carta próprio (categoria ainda em expansão). Fica em jogo até algo o remover.
  - **Equipamento:** é um artefato ("Artefato · Equipamento"). Anexa-se a uma unidade aliada, fica visível sob ela e dá o bônus. Quando a unidade morre, o equipamento vai junto para o cemitério. Cada unidade tem no máximo um; equipar outro descarta o antigo.

## Espécies
- Uma unidade pode ter uma ou mais **espécies** (ex.: Ronan é Dragonoide, Humano e Dragão), no campo `"species"` do JSON. Os nomes ficam em `species` no `cards.json`. Algumas cartas não têm espécie.
- A espécie aparece numa faixa logo acima do nome, e também no texto completo.
- Efeitos de busca no deck podem filtrar por espécie (`"species": "merfolk"`). É a base para sinergias de tribo.

## Keywords
| Keyword | Efeito |
|---|---|
| Ao Entrar | O efeito acontece quando a unidade entra em campo. |
| Ao Morrer | O efeito acontece quando a unidade morre. |
| Golpe Rápido | Causa dano de combate antes das unidades sem Golpe Rápido. |
| Sobrepujança | O dano que exceder a vida restante do bloqueador vai para o Líder inimigo. |
| Roubo de Vida | O dano causado pela unidade cura o seu Líder. |
| Ímpeto | Pode atacar no turno em que entra em campo. |
| Voo | Só pode ser bloqueada por unidades com Voo ou Longo Alcance. |
| Longo Alcance | Pode bloquear unidades com Voo. |
| Furtividade | Só pode ser bloqueada por unidades com Furtividade ou Vigília. |
| Vigília | Pode bloquear unidades com Furtividade. |
| Provocação | Ao atacar, escolha uma unidade inimiga. Ela é obrigada a bloquear esta unidade, mesmo contra Voo ou Furtividade. |
| Escudo | Anula a próxima instância de dano. |
| Congelamento | A unidade não pode atacar nem bloquear até o fim do próximo turno do dono. Escudo de Feitiço anula. |
| Indestrutível | Não sofre dano (sempre 0) e não é destruída por efeitos de "destruir". Sacrifício e remoção do jogo (banimento) ainda a afetam. |
| Escudo de Feitiço | Anula, uma vez, o próximo efeito **inimigo** que não seja dano de combate (feitiço, habilidade, efeito em área). Depois se dissipa. Efeitos do próprio dono não o consomem. |

## Cemitério e Obscura
- **Moer N:** as N cartas do topo do seu deck vão para o seu cemitério (termo da comunidade de MTG, nome confirmado).
- **Reviver:** devolve ao campo uma unidade do cemitério do dono (ex.: O Espiritomante, custo máximo 3). A carta sai do cemitério.
- **Reviver a si mesma (Ao Morrer):** a unidade volta como uma **nova instância**, por isso não participa do combate em que morreu. Enquanto está em campo, sua entrada deixa o cemitério. O Revivente Eterno volta sempre igual. A Fênix da Chama Profana volta com -2/-2 do que tinha ao morrer e não volta se Ataque ou Vida chegar a 0. Não volta com o campo cheio.
- **Sacrifício:** a unidade sacrificada morre na hora (efeitos Ao Morrer e Aliado Morre resolvem). Como *efeito* (Cientista da Morte, Colheita de Almas) ou como **custo adicional** (Necrófago Espectral: custa 0, mas exige sacrificar uma unidade que você controla; com o campo cheio, o sacrifício libera a vaga).
- **Redução de custo por cemitério:** efeito Constante. A Vagante Sombria custa 1 a menos por carta no seu cemitério (de qualquer tipo), nunca menos que 0.

## Passivas de Líder
- Algumas habilidades de Líder são **passivas**: não custam Momentum, não são clicáveis e disparam sozinhas num gatilho. A passiva do Jeff (*Ceifa*): quando uma unidade aliada morre **durante o seu turno**, 1 de dano ao Líder inimigo, **uma vez por turno**. Não ativa no turno do oponente.

## Identidade visual das essências
- **Obscura:** gradiente de pretos e cinzas-escuros (mais para o preto), com uma caveira em cinza escuro no lugar da arte ainda não feita.

## Controles
- **Clique esquerdo:** jogar uma carta, selecionar atacantes, escolher alvos e atribuir bloqueios (primeiro o seu bloqueador, depois o atacante).
- **Clique direito numa carta:** abre o texto completo em tela cheia.
- **Clique direito ou Esc durante a escolha de alvo:** cancela.

## Gatilhos
Gatilhos dizem *quando* um efeito acontece. Eles abrem o texto da carta no lugar de frases por extenso, e ficam em `triggers` no `cards.json`.

| Gatilho | Quando |
|---|---|
| Ao Jogar | A carta é jogada da mão (feitiços e equipamentos). |
| Ao Entrar | A unidade entra em campo. |
| Ao Morrer | A unidade morre. |
| Ao Atacar | A unidade é declarada atacante. |
| Ao Bloquear | A unidade é declarada bloqueadora. |
| Ao Ser Bloqueada | Um bloqueador é atribuído a esta unidade atacante. |
| Ao Sofrer Dano | A unidade sofre dano (Escudo anulando o dano não conta). |
| Ao Atingir o Líder | A unidade causa dano a um Líder. |
| No Início do Turno | Começa o turno do dono da unidade. |
| No Fim do Turno | Termina o turno do dono da unidade. |
| Aliado Morre | Outra unidade que você controla **morre**, mesmo que volte na hora (Revivente, Fênix) ou seja um Lendário voltando à zona de comando. A que morreu não ativa o próprio efeito (para isso existe Ao Morrer). Sacrifício conta. |
| (qualquer gatilho) | Um efeito pode ter "uma vez por turno" (`once_per_turn`): o limite é por unidade e reinicia a cada turno, de qualquer jogador (ex.: Cientista da Morte). |
| Constante | Sempre, enquanto a unidade está em campo. Não dispara: é recalculado a cada mudança de estado (ex.: Jeff The Death recebe +2/+2 por unidade no cemitério do dono; o dano sofrido continua valendo se o bônus encolher). |

Alvos de gatilhos que não pedem escolha do jogador: `self`, `opposed_unit` (a unidade do outro lado do combate, ou a fonte do dano), `all_ally_units`, `all_units` (ambos os lados; o efeito de dano aceita `ally_reduce` para reduzir o dano em aliados de uma essência), `random_ally_unit`, `random_other_ally_unit`, `random_enemy_unit`, `random_enemy_and_adjacent` (uma unidade inimiga aleatória e as adjacentes), `all_enemy_units`, `enemy_leader`, `own_leader` e `both_leaders` (em efeitos de compra, cada líder alvo compra). Só Ao Jogar e Ao Entrar podem usar alvo escolhido pelo jogador.

**"Qualquer alvo"** (texto padrão das cartas, alvo `any`) = qualquer unidade em campo, de qualquer lado, ou o Líder inimigo. Não inclui o seu próprio Líder.
