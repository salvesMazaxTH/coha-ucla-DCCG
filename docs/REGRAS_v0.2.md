# Regras — 0.2.2 Alpha

## Objetivo
Cada jogador tem um **Líder** com vida entre 20 e 30. Vence quem zerar a vida do Líder inimigo. Se os dois Líderes caírem ao mesmo tempo, é empate.

**Conceder:** a qualquer momento, mesmo fora do seu turno ou com a pilha ocupada, o jogador pode desistir (botão **Conceder**, com confirmação). O oponente vence na hora. A IA nunca concede.

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
- **Aposentadoria:** se ela morre ou é **banida** e a próxima conjuração passaria de 10 (o máximo de Momentum, contando o **custo atual** com reduções, mais a taxa), ela **não** volta ao Santuário: vai para o **fundo do deck** com o custo resetado e vira **carta comum para sempre** (se morrer de novo, vai para o cemitério). Ex.: Ronan (4) se aposenta na 4ª morte (4→6→8→10, a próxima seria 12); Naelthos e Jeff (5), na 3ª (5→7→9, a próxima seria 11).
- Ser devolvida para a mão não conta: ela mantém o custo que tinha no Santuário.

## Início da partida
- Os dois jogadores começam com **5 cartas** na mão.
- **Mulligan:** cada jogador pode devolver até 3 cartas ao deck, que é embaralhado, e comprar a mesma quantidade.
- Quem joga primeiro **não compra** no primeiro turno. Quem joga em segundo compra normalmente, então cada um começa o seu primeiro turno com 5 e 6 cartas, respectivamente.
- Quem joga em segundo ganha **+1 Momentum** no seu **primeiro turno** (só naquele turno; o máximo não muda) e **+1 na Reserva** nos seus **dois primeiros turnos**.

## Momentum
- O Momentum máximo começa em **1** e sobe **+1 por turno**, até o teto de **10**.
- Ele é reabastecido no início do seu turno. O que sobra vai para a **Reserva**, que guarda até **2**.
- A **Reserva** só paga **feitiços** e **habilidades** (nunca unidades nem a Encarnação) e é gasta primeiro.

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
- **Fadiga:** comprar uma carta com o deck vazio causa dano ao seu Líder. O dano é de 2 na primeira vez e **dobra** a cada nova compra (2, 4, 8, 16…): com 20 a 25 de vida, mata em até 4 compras. Com o deck vazio, o contador do deck mostra o próximo dano (ex.: -8).

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
- **Janela de invocação:** depois que o jogador da vez joga uma unidade da mão ou conjura a Encarnação do Santuário, o adversário recebe a prioridade e pode responder com uma carta ou habilidade **Rápida** ou **Instantânea**. Ao passar (ou sem jogada), o turno segue. Lenta não pode ser usada aqui, e o jogador da vez não age até a janela fechar.
- **Auto-passe:** cada jogador pode ligar ou desligar (padrão: ligado). Ligado, o sistema passa sozinho toda janela de prioridade em que você não tem nenhuma jogada legal e também pula o pedido de bloqueios quando nenhuma unidade sua pode bloquear. Desligado, você recebe todas as janelas e passa à mão. Ligar o auto-passe durante uma janela inútil já a passa.
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
| Ao Entrar | O efeito acontece quando a unidade entra em campo. Se ele pede alvo, o dono escolhe **depois** que a unidade já está no campo (pode ser ela mesma, se o alvo permitir) ou **recusa** e o efeito não acontece. Diferente de custo adicional (Necrófago), que é pago antes de a unidade entrar. |
| Ao Morrer | O efeito acontece quando a unidade morre. |
| Golpe Rápido | Causa dano de combate antes das unidades sem Golpe Rápido. |
| Sobrepujança | O dano que exceder a vida restante do bloqueador vai para o Líder inimigo. |
| Roubo de Vida | O dano causado pela unidade cura o seu Líder. |
| Ímpeto | Pode atacar no turno em que entra em campo. |
| Voo | Só pode ser bloqueada por unidades com Voo ou Longo Alcance. |
| Longo Alcance | Pode bloquear unidades com Voo. |
| Furtividade | Só pode ser bloqueada por unidades com Furtividade ou Vigilância. |
| Vigilância | Pode bloquear unidades com Furtividade. |
| Não Bloqueia | A unidade não pode bloquear (nem ser alvo de Provocação). |
| Provocação | Ao atacar, escolha uma unidade inimiga. Ela é obrigada a bloquear esta unidade, mesmo contra Voo ou Furtividade. |
| Escudo | Anula a próxima instância de dano. |
| Congelamento | A unidade não pode atacar nem bloquear até o fim do próximo turno do dono. Escudo de Feitiço anula. |
| Indestrutível | Não sofre dano (sempre 0) e não é destruída por efeitos de "destruir". Sacrifício e remoção do jogo (banimento) ainda a afetam. |
| Esquiva | A primeira vez em cada turno que receberia dano de combate de uma unidade com ataque menor que o dela, o dano é evitado. |
| Escudo de Feitiço | Anula, uma vez, o próximo efeito **inimigo** que não seja dano de combate (feitiço, habilidade, efeito em área). Depois se dissipa. Efeitos do próprio dono não o consomem. |

## Cemitério e Obscura
- **Moer N:** as N cartas do topo do seu deck vão para o seu cemitério (termo da comunidade de MTG, nome confirmado).
- **Reviver:** devolve ao campo uma unidade do cemitério do dono (ex.: O Espiritomante, custo máximo 3). A carta sai do cemitério.
- **Reviver a si mesma (Ao Morrer):** a unidade volta como uma **nova instância**, por isso não participa do combate em que morreu. Enquanto está em campo, sua entrada deixa o cemitério. O Revivente Eterno volta sempre igual. A Fênix da Chama Profana volta com -2/-2 do que tinha ao morrer e não volta se Ataque ou Vida chegar a 0. Não volta com o campo cheio.
- **Sacrifício:** a unidade sacrificada morre na hora (efeitos Ao Morrer e Aliado Morre resolvem). Como *efeito* (Colheita de Almas) ou como **custo adicional** (Necrófago Espectral: custa 0, mas exige sacrificar uma unidade que você controla; com o campo cheio, o sacrifício libera a vaga).
- **Redução de custo por cemitério:** efeito Constante. A Vagante Sombria custa 1 a menos por carta no seu cemitério (de qualquer tipo), nunca menos que 0.

## Elétrica: Momentum guardado
- **Redução de custo por Momentum guardado:** efeito Constante. A Voltexz custa 1 a menos por Momentum que sobrou no fim de cada turno seu (acumulado), nunca menos que 3. O Fulgurvoltz custa 2 a menos por turno terminado com Momentum sobrando, nunca menos que 5. O piso (`min_cost`) é exclusivo dessas duas cartas.
- **Momentum no próximo turno:** o Espírito Carregado dá +1 Momentum no início do seu próximo turno (soma ao Momentum do turno, até 10).
- **Sobrecarga (Líder Voltexz):** passiva. No início do seu turno, se a sua Reserva estiver cheia, ganhe +1 Momentum neste turno.
- Efeitos podem ter condição `if` (ex.: só se sobrou Momentum, só se a Reserva está cheia) e bônus proporcional ao Momentum restante (Voltexz: +1/+1 por Momentum, máximo +5/+5).

## Habilidade de Líder: limite de uso
- Algumas habilidades têm `once_per_turn`: 1 uso por turno, em qualquer turno (o seu ou o do adversário), reiniciando a cada turno.
- Outras têm `once_per_cycle` (Pavio Curto, do Ronan): **1 uso entre o início de um turno seu e o início do seu próximo turno**. Só o início do *seu* turno recarrega. Se usou no seu turno, não usa no do adversário; se não usou, pode usar no do adversário (e no seu turno seguinte recarrega de qualquer forma). O jogador vê isso como "1× até seu próximo turno".

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

**Gatilhos não vão para a pilha e não podem ser respondidos:** resolvem na hora em que disparam (Ao Entrar, Ao Morrer etc.). Respostas só são possíveis depois, nas janelas normais.

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

### Habilidades ativáveis
Não são gatilhos automáticos: o dono decide quando usar. O custo em Momentum aparece entre parênteses logo após o nome, e a Reserva ajuda a pagar.

- **Ao Ativar (n) [selo de velocidade] (limites):** a habilidade **vai para a pilha** como um feitiço da velocidade indicada (Lento, Rápido ou Instantâneo). Pode ser respondida e anulada. Exemplo: Yuki, *Ao Ativar (2) [RÁPIDO] (1x por turno): ganhe +2 de Ataque neste turno.*
- **Transformar (n):** é um tipo específico de ativável. Só pode ser usado na sua Fase Principal com a pilha vazia. A unidade vira a carta indicada no mesmo lugar (mantém dano e equipamento) e o Ao Entrar da nova forma dispara. **Não usa a pilha**, então não pode ser anulado. Exemplo: Alexa Neruvya, *Transformar (8): Alexa Neruvya Primordial.*
| Aliado Morre | Outra unidade que você controla **morre**, mesmo que volte na hora (Revivente, Fênix) ou seja um Lendário voltando à zona de comando. A que morreu não ativa o próprio efeito (para isso existe Ao Morrer). Sacrifício conta. Um efeito pode ser "exceto dano de combate" (`not_in_combat`): não dispara se a morte vem do dano de combate (ex.: Cientista da Morte). |
| (qualquer gatilho) | Um efeito pode ter "uma vez por turno" (`once_per_turn`): o limite é por unidade e reinicia a cada turno, de qualquer jogador (ex.: Diabrete Sombrio). |
| Constante | Sempre, enquanto a unidade está em campo. Não dispara: é recalculado a cada mudança de estado (ex.: Jeff The Death recebe +2/+2 por unidade no cemitério do dono; o dano sofrido continua valendo se o bônus encolher). |

Alvos de gatilhos que não pedem escolha do jogador: `self`, `opposed_unit` (a unidade do outro lado do combate, ou a fonte do dano), `all_ally_units`, `all_units` (ambos os lados; o efeito de dano aceita `ally_reduce` para reduzir o dano em aliados de uma essência), `random_ally_unit`, `random_other_ally_unit`, `random_enemy_unit`, `random_enemy_and_adjacent` (uma unidade inimiga aleatória e as adjacentes), `all_enemy_units`, `enemy_leader`, `own_leader` e `both_leaders` (em efeitos de compra, cada líder alvo compra). Só Ao Jogar e Ao Entrar podem usar alvo escolhido pelo jogador.

**"Qualquer alvo"** (texto padrão das cartas, alvo `any`) = qualquer unidade em campo, de qualquer lado, ou o Líder inimigo. Não inclui o seu próprio Líder.
