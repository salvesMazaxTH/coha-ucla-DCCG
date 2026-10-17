# Regras — 0.2.2 Alpha

## Objetivo

Cada jogador tem um **Líder** com vida entre 20 e 30. Vence quem zerar a vida do Líder inimigo. Se os dois Líderes caírem ao mesmo tempo, é empate.

**Conceder:** a qualquer momento, mesmo fora do seu turno ou com a pilha ocupada, o jogador pode desistir (botão **Conceder**, com confirmação). O oponente vence na hora. A IA nunca concede.

## Deck

- O deck tem **44 cartas**, com até **3 cópias** de cada uma, mais a **Encarnação** (que fica no Santuário). O Líder fica fora dessa contagem.
- **Única:** cartas com `"max_copies": 1` (ex.: Rusco) só podem ter 1 cópia no deck.
- As **essências** do Líder (ígnea, aquática, glacial, vegetal, rochosa, metálica, elétrica, obscura, sagrada, venenosa) definem as cartas permitidas no deck. Cartas **neutras** entram em qualquer deck.
- Uma carta pode ter **mais de uma essência** (ex.: Sabrina é aquática e glacial, com moldura meio a meio). Ela é permitida se tiver **pelo menos uma** das essências do Líder.
- **Fora da essência:** o deck pode ter até **12 cartas** (contando cópias) de essências que o Líder não tem, de qualquer raridade, com o limite normal de 3 cópias. Cartas neutras não entram nessa conta, e **Campeões** nunca podem ser de fora da essência.
- O deck tem exatamente **1 Encarnação do Líder**, o Campeão que é a versão em carta do próprio Líder.

## Encarnação do Líder (Santuário)

- A Encarnação começa no **Santuário**, fora do deck, e pode ser conjurada de lá a qualquer momento da sua fase principal.
- A taxa cresce a cada conjuração: a 2ª custa **+1 Momentum**, a 3ª **+3** (1+2), a 4ª **+6** (1+2+3), a 5ª **+10**, e assim por diante.
- Quando a Encarnação morre, ela volta para o Santuário. A morte dela não afeta o Líder.
- **Aposentadoria:** se ela morre ou é **banida** e a próxima conjuração passaria de 10 (o máximo de Momentum, contando o **custo atual** com reduções, mais a taxa), ela **não** volta ao Santuário: vai para o **fundo do deck** com o custo resetado e vira **carta comum para sempre** (se morrer de novo, vai para o cemitério). Ex.: Ronan (4) conjura por 4→5→7→10 e se aposenta na 4ª morte (a próxima seria 14); Naelthos (5): 5→6→8, e na 3ª morte a próxima seria 11, então se aposenta; Jeff (6): 6→7→9, e na 3ª morte a próxima seria 12, então se aposenta.
- Ser devolvida para a mão não conta: ela mantém o custo que tinha no Santuário.

## Início da partida

- Os dois jogadores começam com **5 cartas** na mão.
- **Mulligan:** cada jogador pode devolver até 3 cartas ao deck, que é embaralhado, e comprar a mesma quantidade.
- Quem joga primeiro **não compra** no primeiro turno. Quem joga em segundo compra normalmente, então cada um começa o seu primeiro turno com 5 e 6 cartas, respectivamente.
- Quem joga em segundo, nos seus **dois primeiros turnos**, ganha **+1 Momentum** (só naquele turno; o máximo não muda) e **recarrega 1 da Reserva** (até o limite de 2).

## Momentum

- O Momentum máximo começa em **1** e sobe **+1 por turno**, até o teto de **10**.
- Ele é reabastecido no início do seu turno. O que sobra vai para a **Reserva**, que guarda até **2**.
- A **Reserva** só paga **feitiços** e **habilidades** (nunca unidades nem a Encarnação) e é gasta primeiro.

## Turno

1. **Início:** o Momentum é reabastecido, você compra 1 carta e suas unidades ficam prontas (desviram).
2. **Fase principal:** jogue cartas, conjure a Encarnação e use a habilidade do Líder.
3. **Combate**, uma vez por turno (veja _Combate_ abaixo).
4. **Segunda fase principal**.
5. **Fim do turno:** se você tiver mais de **10 cartas** na mão, escolha quais **banir** até ficar com 10 (não vão ao cemitério; o oponente não vê quais foram). Os bônus temporários acabam. **O dano nas unidades continua marcado** (só curas e Regeneração o removem).

## Combate

- **Não existe bloqueio.** Para atacar, a unidade **vira (fica exaurida)**, e a carta aparece deitada. Ela só desvira no início do próximo turno do dono, então fica exposta durante o turno inteiro do oponente.
- Cada ataque escolhe um alvo:
  - o **Líder inimigo** (não leva dano de volta); ou
  - **desafiar** uma unidade inimiga que **já está exaurida**. As duas trocam dano de combate.
- **Só a Provocação segura o ataque:** unidades exauridas comuns **não** protegem o Líder; o atacante pode desafiá-las ou ir direto no Líder. Se houver uma **Provocação exaurida** (não Congelada) que ele consiga desafiar, ele **é obrigado** a desafiá-la. Unidades que ele não consegue desafiar (por Voo, Furtividade, Intimidação, Etérea) não contam. Obsessão só desafia Provocação (e é obrigada a isso se houver uma exaurida). Rompante (no turno em que entra) só desafia Provocação e, sem ela, vai no Líder.
- **Ataque 0 também ataca e desafia:** a unidade vira, a animação do ataque acontece normalmente e ela não causa dano, mas o defensor ainda revida. Serve, por exemplo, para o Morakhan se autoinduzir dano no próprio turno.
- **Restrições de desafio:** Voo, Furtividade, Intimidação, Etérea (no alvo) e Obsessão (no atacante); veja a tabela de keywords.
- **Provocação:** se o oponente tem uma unidade com Provocação **exaurida**, todo atacante que **puder** desafiá-la é obrigado a desafiar ela (ou outra Provocação exaurida, à escolha), e não as outras exauridas. Quem não pode desafiá-la (por Voo, Furtividade, Intimidação etc.) fica livre. Toda unidade com Provocação, em **qualquer** entrada (mão, reviver, invocar), deixa o controlador escolher se ela **entra exaurida**.
- **Fluxo:**
  1. **IR PARA O COMBATE** abre a **janela de preparação**: o atacante tem a prioridade primeiro, depois o defensor. Os dois podem usar cartas e habilidades **Rápidas** e **Instantâneas**. Ela fecha quando os dois passam seguidos com a pilha vazia.
  2. **Ataques:** o atacante declara um ataque de cada vez (arrastando a unidade até o alvo). Cada ataque resolve na hora: **não há janelas entre os ataques** e ninguém pode responder; os gatilhos resolvem na hora.
  3. **ENCERRAR COMBATE** (ou nenhuma unidade podendo atacar) volta para a fase principal.
- **Ordem do dano (Rapidez):** toda unidade tem uma velocidade de 4 níveis. A mais lenta (a da vasta maioria) não mostra nada na carta; as mais ágeis têm a palavra-chave **Rapidez 1**, **Rapidez 2** ou **Rapidez 3** (tag na carta). Sem a palavra-chave, a unidade tem Rapidez 0 (o motor usa exatamente a mesma escala da carta, de 0 a 3). Num desafio, quem tem mais Rapidez bate primeiro; se matar, não leva o revide. Rapidez igual bate ao mesmo tempo. Uma unidade **congelada** mantém o ATK, mas tem a Rapidez suprimida (conta como Rapidez 0) até descongelar: se desafiada, ainda revida.
- **Crítico (X):** palavra-chave de 1 a 4. Cada dano de combate que a unidade causa (ataque, revide ou golpe no Líder) tem X × 25% de chance de ser **crítico**: **+2 de dano**, somado antes de Armadura e Escudo. No Crítico 4 o crítico é certo. Efeitos podem dar níveis temporários (até o fim do turno), sempre com o máximo de 4. Uma unidade com a marca **Desdém** (Rália) é imune: o crítico contra ela não acontece. Vael é a exceção: começa no Crítico 1, sobe 1 nível permanente a cada crítico que causa e, no Crítico 4, seus críticos dão **+4** e ele ganha **Ataque Duplo**.
- **Ataque Duplo:** a unidade ataca duas vezes por turno. Ela fica exausta depois do primeiro ataque, mas ainda pode fazer o segundo; só deixa de poder atacar depois dele.
- As mortes e o fim de jogo são verificados depois de cada ataque, então o jogo pode acabar no meio do combate.
- **Vida temporária** (de bônus temporários) absorve o dano primeiro. Quando o bônus acaba, o dano marcado cai na mesma quantidade, então a unidade nunca morre só porque o bônus acabou.

## Regras gerais

- Cada lado pode ter no máximo **8 unidades** em campo.
- Uma unidade recém-jogada não pode atacar no mesmo turno, a menos que tenha **Ímpeto**, e mesmo com Ímpeto ela só pode **desafiar** nesse turno (o Líder inimigo, só a partir do próximo). Ela pode ser desafiada normalmente se estiver exaurida (ex.: entrou exaurida com Provocação). **Rompante** é a variante oposta: no turno em que entra, a unidade pode atacar o **Líder inimigo** (não desafia unidades comuns); só uma **Provocação exaurida** que ela possa desafiar a segura (aí ela é obrigada a desafiá-la). A partir do próximo turno é uma unidade normal.
- A cura do Líder nunca passa da vida inicial dele.
- **Banimento:** carta banida sai do jogo: não vai ao cemitério, então não alimenta Encarnação, Vagante etc. e não conta como morrer. A compra não tem teto durante o turno (a mão pode passar de 10, inclusive no turno do oponente); só no fim do seu turno você bane as piores até voltar a 10. Banir da mão é oculto para o oponente; efeitos de banimento (ex.: em área) serão públicos. **Banir uma unidade em campo** é mais forte que destruir (equivale a exilar): ignora Indestrutível, a unidade não morre (sem Ao Morrer nem Aliado Morre) e não vai ao cemitério; o equipamento dela vai ao cemitério.
- **Fadiga:** comprar uma carta com o deck vazio causa dano ao seu Líder. O dano é de 2 na primeira vez e **dobra** a cada nova compra (2, 4, 8, 16…): com 20 a 25 de vida, mata em até 4 compras. Com o deck vazio, o contador do deck mostra o próximo dano (ex.: -8).

## Velocidade, pilha e janelas

- Toda carta e habilidade de Líder tem uma velocidade, definida no campo `"speed"` do JSON. Sem o campo, ela é **lenta**.
  - Equipamentos (artefatos) são lentos, a não ser que tenham a tag **Saque Rápido** (`saque_rapido`), que os torna rápidos.
  - **Lenta:** só na sua fase principal, com a pilha vazia.
  - **Rápida:** também nas janelas de combate.
  - **Instantânea:** também em resposta a qualquer coisa na pilha.
- Unidades, a Encarnação, atacar e encerrar o turno seguem a regra das lentas. Unidades não usam a pilha.
  - Exceção: **Súbito (N)**. Pagando N (a Reserva ajuda), a unidade pode ser invocada em qualquer janela onde uma Rápida caberia. Essa invocação é uma habilidade, não uma jogada: vai para a pilha (Rápida), pode ser respondida e anulada (anulada, a carta vai para o cemitério) e a unidade só entra quando ela resolve. Na sua fase principal livre, a carta é jogada normalmente, pelo custo normal.
- **Pilha:** feitiços, equipamentos e habilidades vão para a pilha, e a prioridade passa para o adversário.
  - Quem tem prioridade pode responder com uma Instantânea ou passar.
  - Quando alguém passa, a pilha inteira resolve, do mais novo para o mais antigo.
  - Um efeito cujo alvo deixou de ser válido é anulado.
  - **Anular (counter):** alguns Instantâneos (ex.: Negação de Neraqa) miram um feitiço ou habilidade **inimiga** na pilha. **Equipar não pode ser anulado**, mas pode ser respondido (o equipamento é conjurado em velocidade lenta e fica na pilha até resolver). O item anulado sai da pilha sem efeito, e a carta vai para o cemitério. Se o custo do alvo passa do limite da carta, o custo extra (ex.: +3) é cobrado automaticamente quando você escolhe esse alvo.
- **Janela de invocação:** depois que o jogador da vez joga uma unidade da mão ou conjura a Encarnação do Santuário, o adversário recebe a prioridade e pode responder com uma carta ou habilidade **Rápida** ou **Instantânea**. Ao passar (ou sem jogada), o turno segue. Lenta não pode ser usada aqui, e o jogador da vez não age até a janela fechar.
- **Ao Entrar na pilha:** se a unidade jogada tem **Ao Entrar**, ele não resolve na hora: vai para a pilha como um item próprio (substitui a janela de invocação). O adversário tem a prioridade primeiro e só pode responder com **Instantâneo**. O Ao Entrar **não pode ser anulado** e resolve mesmo que a unidade morra em resposta. Se o adversário responde, o dono do Ao Entrar pode responder à resposta; a pilha resolve do item mais novo para o mais antigo.
- **Auto-passe:** cada jogador pode ligar ou desligar (padrão: ligado). Ligado, o sistema passa sozinho toda janela de prioridade em que você não tem nenhuma jogada legal. Desligado, você recebe todas as janelas e passa à mão. Ligar o auto-passe durante uma janela inútil já a passa.
- **Janela de combate:** só existe a janela de preparação, antes dos ataques (veja _Combate_). Durante os ataques ninguém joga nada.
- Quem não tem nenhuma jogada possível passa automaticamente.
- Quando unidades dos dois lados morrem ao mesmo tempo, as mortes (Ao Morrer, Aliado Morre) resolvem primeiro para o **jogador da vez**, depois para o oponente.

## Olhar o topo do deck

- Alguns efeitos (ex.: Serpente Marinha) olham as N cartas do topo do deck. Só o dono vê essas cartas; ele coloca 1 na mão, e só essa é revelada ao oponente. As outras vão para o fundo do deck. O Oráculo das Marés faz o mesmo, mas revela a carta pega ao oponente e embaralha o deck em vez de mandar as outras para o fundo.

## Tipos de carta

- **Unidade (comum ou épica), Campeão e Lendário:** são unidades, com Ataque e Vida.
- **Feitiço:** produz o efeito e vai para o cemitério.
- **Artefato:** tipo de carta próprio (categoria ainda em expansão). Fica em jogo até algo o remover.
  - **Equipamento:** é um artefato ("Artefato · Equipamento"). Anexa-se a uma unidade aliada, fica visível sob ela e dá o bônus. Quando a unidade morre, o equipamento vai junto para o cemitério. Cada unidade tem no máximo um; equipar outro descarta o antigo.
  - **Local:** artefato solto no campo ("Artefato · Local"). Ocupa um espaço e nunca luta. Alguns não vão no deck: só entram em jogo por um efeito (o Baluarte Santo, erguido pela habilidade do Líder Mefi'Urdim). O Baluarte, se um efeito fosse destruir uma unidade aliada, é destruído no lugar dela; ao morrer, cura 3 do Líder do dono.

## Espécies

- Uma unidade pode ter uma ou mais **espécies** (ex.: Ronan é Dragonoide, Humano e Dragão), no campo `"species"` do JSON. Os nomes ficam em `species` no `cards.json`. Algumas cartas não têm espécie.
- A espécie aparece numa faixa logo acima do nome, e também no texto completo.
- Efeitos de busca no deck podem filtrar por espécie (`"species": "merfolk"`). É a base para sinergias de tribo.

## Keywords

| Keyword           | Efeito                                                                                                                                                                                                                                                                                        |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ao Entrar         | O efeito acontece quando a unidade entra em campo. Se ele pede alvo, o dono escolhe **depois** que a unidade já está no campo (pode ser ela mesma, se o alvo permitir) ou **recusa** e o efeito não acontece. Diferente de custo adicional (Necrófago), que é pago antes de a unidade entrar. |
| Ao Morrer         | O efeito acontece quando a unidade morre.                                                                                                                                                                                                                                                     |
| Sobrepujança      | Ao desafiar, o dano que exceder a vida restante da unidade desafiada vai para o Líder inimigo.                                                                                                                                                                                                |
| Roubo de Vida     | O dano causado pela unidade cura o seu Líder.                                                                                                                                                                                                                                                 |
| Ímpeto            | Pode atacar no turno em que entra em campo, mas só para desafiar.                                                                                                                                                                                                                                          |
| Rompante          | No turno em que entra em campo, pode atacar o Líder (não desafia unidades comuns), mas uma Provocação exaurida a obriga a desafiá-la. Depois disso é normal.                                                                                                                                                                |
| Voo               | Só pode ser desafiada por unidades com Voo ou Longo Alcance.                                                                                                                                                                                                                                  |
| Longo Alcance     | Pode desafiar unidades com Voo.                                                                                                                                                                                                                                                               |
| Furtividade       | Só pode ser desafiada por unidades com Furtividade ou Vigilância.                                                                                                                                                                                                                             |
| Vigilância        | Pode desafiar unidades com Furtividade.                                                                                                                                                                                                                                                       |
| Intimidação       | Unidades com ATK 3 ou menor (o ATK de agora, com buffs e debuffs) não podem desafiar esta unidade.                                                                                                                                                                                            |
| Obsessão          | Só ataca o Líder inimigo, mas uma Provocação exaurida ainda a obriga a desafiá-la.                                                                                                                                                                                                                                |
| Provocação        | Ao entrar, o dono escolhe se ela entra exaurida. Exaurida, obriga todo atacante inimigo que puder desafiá-la a desafiar ela (ou outra Provocação exaurida), passando na frente das outras exauridas.                                                                                                                                   |
| Inalcançável      | Não pode ser alvo de feitiços, habilidades ou efeitos **do oponente**. Efeitos sem alvo (área, aleatórios) ainda a afetam, e ela ainda pode ser desafiada. Os efeitos do próprio dono a miram normalmente.                                                                                    |
| Imunidade contra <essência> | Existe uma por essência (Imunidade contra Obscura, Ígnea...). O dano de combate de unidades daquela essência do oponente é 0, e feitiços, habilidades e efeitos dela do oponente que **escolhem** a unidade como alvo são ignorados, sem gastar nada (Escudo e Escudo de Feitiço continuam). Efeitos sem alvo ou em área ainda a afetam, e cartas do próprio dono ou de outras essências também. |
| Pacifista         | O dano de combate desta unidade é sempre 0, mesmo com buffs de Ataque. Ela ainda ataca ou desafia, sofre o golpe de volta e fica exaurida. Efeitos que não são dano de combate (feitiços, habilidades) funcionam normalmente. |
| Etérea            | Não pode ser desafiada por nada (com Provocação, não obriga ninguém). Só sai do campo por feitiços e habilidades.                                                                                                                                                                             |
| Regeneração       | No fim de cada turno (de qualquer jogador), todo o dano desta unidade é curado.                                                                                                                                                                                                               |
| Reflexão          | Sempre que sofrer dano de uma unidade (combate ou efeito), devolve a ela metade desse dano, arredondada pra cima. Não reflete dano de Fadiga nem de feitiço sem unidade de origem, e não reflete o próprio reflexo. |
| Escudo            | Anula a próxima instância de dano.                                                                                                                                                                                                                                                            |
| Congelamento      | A unidade não ataca, não desvira e tem a Rapidez suprimida (conta como sem Rapidez) até o fim do próximo turno. Revida normalmente. Uma Provocação Congelada não obriga ataques. Congelar não exaure. Escudo de Feitiço anula. |
| Exaurir / Espaços congelados | **Exaurir** deixa a unidade exausta (não ataca e pode ser desafiada) até o início do turno do dono. O Rei Gelado ainda congela espaços do campo (5 ao entrar e 1 no início de cada turno seu), sorteando só entre os que ainda não estão congelados: unidade num espaço sorteado é congelada e exaurida; espaço vazio não aceita permanentes até o fim do próximo turno do dono do campo. Sorteios de status nunca caem em quem já tem aquele status. |
| Indestrutível     | Não sofre dano (sempre 0) e não é destruída por efeitos de "destruir". Sacrifício e remoção do jogo (banimento) ainda a afetam.                                                                                                                                                               |
| Toque Letal       | Quando esta unidade causar dano de combate a uma unidade, destrua aquela unidade imediatamente. Escudo, Indestrutível e outras proteções absolutas que impeçam o dano ou a destruição sobrevivem.                                                                                                                                 |
| Esquiva           | A primeira vez em cada turno que receberia dano de combate de uma unidade com **Rapidez** menor que a dela, o dano é evitado. (Algumas cartas trocam a condição, ex.: "sem Rapidez" ou "Rapidez N ou menor".)                                                                                                    |
| Crítico (X)       | Cada dano de combate causado tem X × 25% de chance de ganhar +2 de dano (certo no nível 4). Ver "Crítico" no combate. |
| Ataque Duplo      | Pode atacar duas vezes por turno; fica exausta depois do primeiro ataque, mas ainda pode fazer o segundo. |
| Escudo de Feitiço | Anula, uma vez, o próximo efeito **inimigo** que não seja dano de combate (feitiço, habilidade, efeito em área). Depois se dissipa. Efeitos do próprio dono não o consomem.                                                                                                                   |
| Súbito (N)        | Pagando N, pode ser invocada em qualquer janela de velocidade Rápida. A invocação vai para a pilha como habilidade (não é jogada) e pode ser respondida e anulada. Ver "Velocidade, pilha e janelas". |

## Cemitério e Obscura

- **Moer N:** as N cartas do topo do seu deck vão para o seu cemitério (termo da comunidade de MTG, nome confirmado).
- **Reviver:** devolve ao campo uma unidade do cemitério do dono (ex.: O Espiritomante, custo máximo 4). A carta sai do cemitério.
- **Reviver a si mesma (Ao Morrer):** a unidade volta como uma **nova instância**, por isso não participa do combate em que morreu. Enquanto está em campo, sua entrada deixa o cemitério. O Revivente Eterno volta sempre igual. A Fênix da Chama Profana volta com -2/-2 do que tinha ao morrer e não volta se Ataque ou Vida chegar a 0. Não volta com o campo cheio.
- **Sacrifício:** a unidade sacrificada morre na hora (efeitos Ao Morrer e Aliado Morre resolvem). Como _efeito_ (Colheita de Almas) ou como **custo adicional** (Necrófago Espectral: custa 0, mas exige sacrificar uma unidade que você controla; com o campo cheio, o sacrifício libera a vaga).
- **Redução de custo por cemitério:** a Vagante Sombria escuta o jogo de qualquer zona (deck, mão, cemitério, campo): sempre que uma carta _sua_ vai para o seu cemitério, o custo dela cai em 1, de forma permanente (nunca menos que 0). Só conta o que acontece depois que ela existe no jogo: cartas que já estavam no cemitério não reduzem. Fichas e cartas banidas não vão ao cemitério, então não contam.

## Elétrica: Momentum guardado

- **Redução de custo por Momentum guardado:** efeito sem nome (não é Constante). A Voltexz custa 1 a menos por Momentum que **vazou** da Reserva no início de cada turno seu (acumulado; o que sobra depois do turno do oponente, e só o que não cabe nos 2 da Reserva), nunca menos que 3. O Fulgurvoltz custa 2 a menos por turno iniciado com Momentum vazando, nunca menos que 5. O piso (`min_cost`) é exclusivo dessas duas cartas.
- **Fulgurvoltz:** não destrói nada ao entrar. Seu Ao Ativar (5, Lento) **exaure a unidade** (não pode estar exausta; quem atacou no turno não ativa, e quem ativou não ataca; exaurida, ela pode ser desafiada) e destrói todas as unidades inimigas; vai para a pilha, então o oponente pode responder e anulá-lo (ex.: Negação de Neraqa, que precisa pagar o +2, já que o custo passa de 4). A Reserva paga habilidades, então no piso de custo (5) dá para entrar e ativar no mesmo turno.
- **Momentum no próximo turno:** o Espírito Carregado dá +1 Momentum no início do seu próximo turno (soma ao Momentum do turno, até 10).
- **Sobrecarga (Líder Voltexz):** passiva. No início do seu turno, recupere metade (arredondada para baixo, máx. 2) do Momentum que vazou da Reserva, como Momentum neste turno. "Vazar" = o que não cabe nos 2 da Reserva.
- **Efeitos no deck (`deck_effects`):** efeitos que a carta tem enquanto está no deck, não em campo. `summon_self` tira aquela cópia do deck e a coloca em campo (sem embaralhar e sem comprar; com o campo cheio, ela fica no deck). O `cost` opcional é pago na entrada como uma habilidade (a Reserva vale e é gasta primeiro); sem como pagar, a cópia fica no deck. Rusco: no fim do seu turno, se você jogou da mão uma carta com custo, ATK ou VIDA impressos exatamente 2 (`if: played_two`), e você paga 2 de Momentum, ele sai do deck e entra em campo.
- Efeitos podem ter condição `if` (ex.: só se sobrou Momentum, só se a Reserva está cheia) e bônus proporcional ao Momentum restante (Voltexz: +1/+1 por Momentum nas suas _outras_ unidades, de +1/+1 a +5/+5: mesmo sem Momentum sobrando dá +1/+1).

## Glacial: Bola de Neve

- **Nível da Bola de Neve:** cada jogador tem um nível, que começa em 1. A Bola de Neve (feitiço Lento, Lendária: até 2 cópias no deck) acerta uma unidade inimiga com o nível atual de dano e **quica**: sorteia esquerda ou direita (só entre lados que têm unidades) e segue nesse sentido até a última unidade, causando 1 de dano a mais a cada quique. No fim, o dano do último golpe vira o nível de **toda** Bola de Neve futura desse jogador, de qualquer fonte (a carta, Bruno, Nythera, Wanessa Tempesfrost...). O texto da carta mostra o nível atual do dono no lugar de `{nivel}` (na mão, no Santuário, na escolha de cartas e na visão ampliada); fora de uma partida mostra 1.
- **Líder como alvo:** acertar um Líder é um golpe só e **não** aumenta o nível.
- **Recuperar do cemitério:** Ysvane (Ao Entrar) devolve uma Bola de Neve (ou Grande Bola de Neve) do cemitério para a mão (`grave_retrieve`). Essa cópia fica marcada e, quando o lançamento termina (resolvida, anulada ou sem alvo), é **banida** em vez de ir ao cemitério: cada cópia rende no máximo dois lançamentos.
- **Grande Bola de Neve:** é uma carta própria (arte, custo 3, texto), não draftável (`transform_only`). Quando o nível do jogador chega a 8, toda Bola de Neve dele (mão, baralho, cemitério e a que estiver na pilha) vira Grande Bola de Neve, e uma Bola que chegar a essas zonas depois disso já vem Grande. Cada quique da Grande tem Sobrepujança (o excesso vai ao Líder dono da unidade; efeito `overflow_to_leader`). Uma Bola lançada por unidade (Nythera, Tempesfrost) não é uma carta que possa evoluir, mas com o nível em 8 ou mais o motor lança a Grande Bola de Neve no lugar da comum: todas as Bolas de Neve, em qualquer lugar, têm Sobrepujança.
- **Princesa Wanessa** se transforma em Wanessa Tempesfrost automaticamente quando o seu controlador lança uma Grande Bola de Neve (evento `snowball_cast`, antes dos golpes) ou quando o nível da Bola de Neve cruza para Grande (evento `snowball_grande`, por exemplo com Ladeira Abaixo e Sem Freio). A Tempesfrost lança a Bola de Neve no alvo do ataque: no Líder é um golpe simples (sem quicar, sem subir o nível); numa unidade inimiga desafiada a Bola quica normalmente. A Bola da Tempesfrost vai para a **pilha** como a carta Bola de Neve (ou Grande Bola de Neve), com o fantasma voando da Tempesfrost: dá para reagir e anulá-la. Ela é uma carta virtual (não passa pela mão nem pelo cemitério) e não conta como feitiço lançado (`spell_cast`), então escutas de feitiço não disparam. O dano de combate da Tempesfrost só acontece depois que a pilha esvazia; se a Bola for anulada, sobra apenas o dano de combate.
- **Amuleto do Primeiro Floco:** o primeiro feitiço glacial lançado por turno custa (2) a menos, mas nunca menos de (1). Vários Amuletos em campo acumulam o desconto (o piso de 1 continua valendo; só o primeiro feitiço glacial do turno).
- **Câmara de Êxtase:** se o seu Líder fosse morrer por uma instância de dano, o dano é anulado, a Câmara é destruída e, até o fim do seu próximo turno, todo dano ao seu Líder é dividido pela metade (arredondado para baixo).
- **Descarte da mão (Folheio Pé-na-Neve):** você escolhe a carta na mesma tela do descarte do overdraw, mas ela vai ao **cemitério**. Só o descarte de overdraw no fim do turno bane.

## Habilidade de Líder: limite de uso

- Algumas habilidades têm `once_per_turn`: 1 uso por turno, em qualquer turno (o seu ou o do adversário), reiniciando a cada turno.
- Outras têm `once_per_cycle` (Pavio Curto, do Ronan): **1 uso entre o início de um turno seu e o início do seu próximo turno**. Só o início do _seu_ turno recarrega. Se usou no seu turno, não usa no do adversário; se não usou, pode usar no do adversário (e no seu turno seguinte recarrega de qualquer forma). O jogador vê isso como "1× até seu próximo turno".

## Passivas de Líder

- Algumas habilidades de Líder são **passivas**: não custam Momentum, não são clicáveis e disparam sozinhas num gatilho. A passiva do Jeff (_Ceifa_): quando uma unidade aliada morre **durante o seu turno**, 1 de dano ao Líder inimigo, **uma vez por turno**. Não ativa no turno do oponente.

## Identidade visual das essências

- **Obscura:** gradiente de pretos e cinzas-escuros (mais para o preto), com uma caveira em cinza escuro no lugar da arte ainda não feita.

## Controles

- **Clique esquerdo:** jogar uma carta, escolher alvos e responder às escolhas (ex.: entrar exaurida).
- **Arrastar uma unidade sua até um alvo** durante os ataques: ataca. Os alvos válidos (unidades inimigas exauridas que ela pode desafiar e o Líder inimigo, ou só a Provocação que a obriga) brilham.
- **Clique direito numa carta:** abre o texto completo em tela cheia.
- **Clique direito ou Esc durante a escolha de alvo:** cancela.

## Gatilhos

Gatilhos dizem _quando_ um efeito acontece. Eles abrem o texto da carta no lugar de frases por extenso, e ficam em `triggers` no `cards.json`.

**Gatilhos não vão para a pilha e não podem ser respondidos:** resolvem na hora em que disparam (Ao Entrar, Ao Morrer etc.). Respostas só são possíveis depois, nas janelas normais.

| Gatilho            | Quando                                                   |
| ------------------ | -------------------------------------------------------- |
| Ao Jogar           | A carta é jogada da mão (feitiços e equipamentos).       |
| Ao Entrar          | A unidade entra em campo.                                |
| Ao Morrer          | A unidade morre.                                         |
| Ao Atacar          | A unidade ataca (o Líder ou desafiando uma unidade).     |
| Ao Desafiar        | A unidade ataca desafiando uma unidade inimiga.          |
| Ao Ser Desafiada   | A unidade é desafiada por um atacante inimigo.           |
| Ao Sofrer Dano     | A unidade sofre dano (Escudo anulando o dano não conta). |
| Ao Atingir o Líder | A unidade causa dano a um Líder.                         |
| No Início do Turno | Começa o turno do dono da unidade.                       |
| No Fim do Turno    | Termina o turno do dono da unidade.                      |

### Habilidades ativáveis

Não são gatilhos automáticos: o dono decide quando usar. O custo em Momentum aparece entre parênteses logo após o nome, e a Reserva ajuda a pagar.

- **Ao Ativar (n) [selo de velocidade] (limites):** a habilidade **vai para a pilha** como um feitiço da velocidade indicada (Lento, Rápido ou Instantâneo). Pode ser respondida e anulada. Exemplo: Yuki, _Ao Ativar (2) [RÁPIDO] (1x por turno): ganhe +2 de Ataque neste turno._
- **Transformar (n):** é um tipo específico de ativável. Só pode ser usado na sua Fase Principal com a pilha vazia. A unidade vira a carta indicada no mesmo lugar (mantém dano e equipamento) e o Ao Entrar da nova forma dispara. A unidade transformada **não fica com enjoo de invocação**: pode atacar e ativar na hora. **Não usa a pilha**, então não pode ser anulado. Exemplo: Alexa Neruvya, _Transformar (8): Alexa Neruvya Primordial._
  | Aliado Morre | Outra unidade que você controla **morre**, mesmo que volte na hora (Revivente, Fênix) ou seja um Lendário voltando ao Santuário. A que morreu não ativa o próprio efeito (para isso existe Ao Morrer). Sacrifício conta. Um efeito pode ser "exceto dano de combate" (`not_in_combat`) ou "exceto fichas" (`not_token`): não dispara se a morte vem do dano de combate / se quem morreu era uma ficha (ex.: Cientista da Morte). |
  | (qualquer gatilho) | Um efeito pode ter "uma vez por turno" (`once_per_turn`): o limite é por unidade e reinicia a cada turno, de qualquer jogador (ex.: Diabrete Sombrio). |
  | Constante | Sempre, enquanto a unidade está em campo (só em campo; reduções de custo não são Constante). Também são Constante: o bônus de espécie de outra unidade aliada (`species_aura`) e a Armadura por feitiços no cemitério (`graveyard_armor`). Não dispara: é recalculado a cada mudança de estado (ex.: Jeff The Death recebe +1/+1 por unidade no cemitério do dono; o dano sofrido continua valendo se o bônus encolher). |

Alvos de gatilhos que não pedem escolha do jogador: `self`, `opposed_unit` (a unidade do outro lado do desafio, ou a fonte do dano), `attack_target` (em Ao Atacar: a unidade desafiada, ou o Líder inimigo), `all_ally_units`, `other_ally_units` (todas as suas outras unidades, sem a fonte), `all_units` (ambos os lados; o efeito de dano aceita `ally_reduce` para reduzir o dano em aliados de uma essência), `random_ally_unit`, `random_other_ally_unit`, `random_enemy_unit`, `random_enemy_and_adjacent` (uma unidade inimiga aleatória e as adjacentes), `all_enemy_units`, `enemy_leader`, `own_leader` e `both_leaders` (em efeitos de compra, cada líder alvo compra). Só Ao Jogar e Ao Entrar podem usar alvo escolhido pelo jogador.

**"Qualquer alvo"** (texto padrão das cartas, alvo `any`) = qualquer unidade em campo, de qualquer lado, ou o Líder inimigo. Não inclui o seu próprio Líder.
