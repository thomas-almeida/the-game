# the-game

Card battler tático por turnos em Godot 4. Tabuleiro 3×4 dividido ao meio, você
invoca criaturas e terrains, e um **brawl** resolve tudo no fim do turno.

O design completo (regras, combate, assets, pendências) está em
[`context/context.md`](context/context.md).

## Rodando

Godot instalado em `C:\Godot\Godot_v4.7.2-stable_win64.exe`.

```
1. abre o Godot
2. Project Manager > Importar
3. aponta para C:\Repos\the-game\project.godot
4. Importar & Editar
```

O Godot **não fica instalado no repo**. Ele só lê e escreve os `.tscn` e `.gd`
aqui, que é o que vai para o Git. Na primeira abertura ele importa ~1700 assets
e leva um minuto.

Rodar direto, sem abrir o editor:

```powershell
C:\Godot\Godot_v4.7.2-stable_win64.exe --path C:\Repos\the-game
```

## Como se joga

0. **`L`** abre e fecha o log. Ele fica escondido de propósito: é conferência,
   não leitura de jogo. Deixá-lo à vista fazia o jogador ler texto em vez de
   olhar o tabuleiro, e o tabuleiro era justamente o que não tinha feedback.

1. **Clique no dado** (canto inferior direito). Ele gira e trava no número da
   sua mana. O sorteio é do jogo — o dado só mostra a consequência. O dado do
   rival, no topo direito, rola sozinho.

2. Clique numa carta da mão. As tiles do seu lado ficam **verde** (pode jogar)
   ou **vermelha** (não pode, e o motivo aparece na faixa de baixo).
3. Clique numa tile verde para invocar.
4. Clique numa magia para conjurá-la. Se ela precisar de alvo, as criaturas
   válidas piscam — clique numa delas.
5. **Terminar Turno** passa a vez pra IA, que joga e dispara o brawl. No fim
   a rodada para de novo esperando você clicar no dado.

`Botão direito` cancela a seleção ou o alvo pendente.

O tabuleiro tem 3 colunas × 4 linhas. A linha de cima é da IA, a de baixo é
sua, e cada lado tem uma **principal** (frente, só criaturas) e uma
**secundária** (fundo, construções).

## Estrutura

A apresentação é uma cena 3D de verdade; a leitura (textos, números) fica numa
camada 2D por cima, porque texto em plano inclinado é ilegível.

```
project.godot          config do projeto (autoload Game, input, viewport)
context/context.md     o design
scripts/
  game.gd              autoload: estado da partida, máquina de turnos, fila de eventos
  card_data.gd         definição de uma carta
  card_db.gd           catálogo + composição do baralho
  board.gd             tabuleiro 3×4 e suas linhas
  board_entity.gd      uma carta colocada no tabuleiro
  player_state.gd      HP, mana, baralho, mão, descarte
  rules.gd             validação de posicionamento + resolução do brawl
  ai_brain.gd          heurística do oponente
  ui/
    card_view.gd       desenho 2D da carta (textura da carta no leque e nas tiles)
    ui_kit.gd          cores, texto, barras, dobra acentos que a fonte não tem
  view/
    main_3d.gd         raiz: câmera, luzes, picking, sincronismo com o Game
    board_3d.gd        monta as 12 tiles e anima entrada/dano/morte
    tile_3d.gd         laje com espessura, terreno pintado, realce de alvo
    entity_3d.gd       criatura em pé (sprite) ou permanente deitado
    hand_view.gd       a mão: leque com perspectiva 3D calculada em GDScript
    die_3d.gd          d6 de verdade: pips desenhados em runtime, rola até o
                       número sorteado pelo Game
    entity_3d.gd       criatura em pé: slimes animados (Idle/Walk/Attack/Hurt/
                       Death), tint por elemento; permanente deitado
    card_face.gd       rasteriza a face da carta uma vez e entrega a textura
    hud.gd             camada 2D: log colorido, barras, números, faixa da carta
scenes/main.tscn       cena raiz (Node3D)
tests/
  sim.gd               simula N partidas headless e valida o estado
  trace.gd             roda uma partida e imprime o log + tabuleiro
  shot.gd              renderiza a tela e salva um PNG
tools/
  make_terrain_tiles.py  gera os tiles de terreno achatados
```

### Decisões de apresentação

- **Tabuleiro é 3D de verdade**; só os sprites são 2D. As tiles são caixas com
  espessura que pegam luz, o terreno é pintado por cima, e as criaturas ficam
  em pé encarando a câmera (`BILLBOARD_FIXED_Y`).
- **Texto é sempre 2D.** Os números de ATK/DEF e o dano acumulado são
  projetados da posição 3D para a tela (`camera.unproject_position`), então
  continuam nítidos com a carta inclinada.
- **A mão é 2D com projeção 3D calculada em GDScript.** Não é um nó 3D porque
  vários quads texturizados quase coplanares num leque não renderizavam de
  forma confiável — apareciam uma ou três das cinco cartas, sem erro no
  console, em três APIs diferentes (`QuadMesh`, `Sprite3D`, `no_depth_test`).
  Em `HandView` a projeção dos 4 cantos é feita na mão e a carta vira um
  polígono texturizado: é a mesma conta de uma câmera pinhole, dá o que importa
  (o topo mais estreito que a base) e é determinístico.
- **Nada acontece num frame só.** `Game.end_turn()` roda o turno inteiro da IA,
  o brawl e a rodada nova de uma vez. A cena toca isso em sequência: um respiro
  com "TURNO DO RIVAL" e o tabuleiro escurecido, os eventos de dano um a um
  (número flutuante + tile piscando + tremor de câmera), o dado rolando no fim,
  e só então "SUA VEZ" com o controle de volta.
- **Quem está jogando fica visível.** O painel do lado ativo ganha moldura
  acesa e o outro apaga; o botão vira "TURNO DO RIVAL..." e trava. Um botão
  desabilitado sem rótulo é um aviso fácil de ignorar.
- **A barra de vida tem rastro.** A barra desce em ~0.3s e uma faixa amarela
  fica para trás drenando devagar, com uma divisória brillante no ponto do
  impacto. A diferença de velocidade entre as duas é o que faz o olho ler
  "levou dano" em vez de "um número mudou".
- **O dado é o gatilho da sorteada, não o contrário.** A rodada para na fase
  ROLL e só continua quando o jogador clica no dado. O número já foi escolhido
  pelo `Game`; a animação é a consequência visível. Sem isso a mana era
  sorteada dentro do mesmo `end_turn` e nunca aparecia — só virava linha de
  log. Por isso `Game` ganhou `commit_roll()`: no jogo é o clique, no sim é a
  chamada.
- **O d6 é geometria, não sprite.** Os pips são desenhados num `Image` em
  runtime, e a rotação final é calculada para trazer a face sorteada na direção
  da câmera. Sem física: um corpo rígido tombando em direção aleatória nem
  sempre para no número certo, e aí a face mostrada contradiz a mana.
- **As criaturas são slimes animados.** O pacote `slime-mobs` tem três
  modelos com Idle, Walk, Run, Attack, Hurt e Death em quadros de 64×64, então
  a criatura finalmente se mexe: avança e ataca no brawl, leva Hurt ao apanhar
  e Death ao cair. Antes era um frame único e estático — nada se movia.
- **Três modelos, dez criaturas.** A variedade vem do **tint por elemento**
  (água azul, fogo laranja, terra marrom, gelo claro, sombra roxo) sobre o
  mesmo slime. O tint vai a 55% para o branco porque a 45% a criatura de fogo
  sumia dentro do terreno de lava — que é justamente o par que a regra mais
  exige.
- **O corpo do slime é minúsculo dentro do quadro.** Medido no PNG: 19×22
  pixels num quadro de 64×64, ou 30%. Por isso `pixel_size` é 0.05 e não
  0.019: o que importa é o corpo visível, não a folha.
- **Props de terreno não podem tapar a criatura.** As peças 3D são baixas e
  ficam nos cantos; o centro da tile é do board de verdade.
- **Terreno tem volume.** O PNG virou cor de base da laje e peças 3D são
  erguidas em cima — pedras, poças, cratera de lava, cristais de gelo, obelisco
  de sombra. Decalque quad chapado ficava com cara de adesivo colado; volume dá
  sombra e o elemento é legível de relance.
- **Hover não abre nada.** Passar o mouse só levanta a carta, traz para a
  frente e aplica o **tilt estilo react-tilt** — ela gira nos dois eixos
  conforme o ponteiro se move dentro dela, e a borda sob o ponteiro avança
  (é a projeção que faz ela crescer, o que dá a profundidade). Tem também
  um brilho especular seguindo o cursor. Só a carta sob o ponteiro reage,
  nunca a mão inteira nem a do oponente. O painel de leitura abre no
  **clique esquerdo**, com a carta em 2.2×. `Botão direito` ou clicar fora
  fecha.
- **Hover é resolvido por polígono, não por proximidade.** Com o leque todo
  sobreposto, o centro de uma carta fica coberto pela seguinte, então
  "centro mais próximo" escolheria a carta errada. O `HandView` testa ponto
  dentro do quad projetado, percorrendo a pilha de trás para frente — ou
  seja, o mesmo que está visível.
- **Selecionar não move nem aumenta a carta.** Só acende uma borda na cor do
  elemento, para o tabuleiro continuar visível.
- **Clique na carta não abre nada.** Não existe modal de detalhe: o clique
  seleciona (borda + tiles verdes + faixa no canto inferior esquerdo com nome,
  ATK/DEF e a regra) e o clique seguinte na tile invoca. Um modal aqui
  sequestrava o clique — o jogador achava que estava invocando e só lia.
- **A mão fica no canto inferior direito**, espalhando para a esquerda, com as
  cartas bem sobrepostas — cada uma mostra só uma fatia da anterior.
- **Picking sem colisão 3D.** Cartas são escolhidas por proximidade em espaço
  de tela; tiles, por raycast contra o plano do chão. Mais barato e mais fácil
  de acertar numa câmera inclinada do que áreas de colisão.
- **A face da carta é rasterizada uma vez** num `SubViewport` e aplicada num
  `Sprite3D`. Isso mantém o texto nítido em vez de ter que usar `Label3D`
  (que borra quando inclinado).
- **`Game` não sabe que existe 3D.** Ele só acumula uma fila de eventos
  (`take_events()`); a cena drena a fila e decide o que animar. Por isso a
  lógica continua testável headless, sem tocar em textura nenhuma.

## Testes

A lógica roda headless, sem janelas:

```powershell
# 60 partidas completas, dos dois lados com a mesma heurística,
# validando invariantes do tabuleiro a cada turno
C:\Godot\Godot_v4.7.2-stable_win64_console.exe --headless `
  --path C:\Repos\the-game --script res://tests/sim.gd

# uma partida com log detalhado e o tabuleiro final
C:\Godot\Godot_v4.7.2-stable_win64_console.exe --headless `
  --path C:\Repos\the-game --script res://tests/trace.gd -- 20

# screenshot da tela depois de N turnos
C:\Godot\Godot_v4.7.2-stable_win64_console.exe --path C:\Repos\the-game `
  res://tests/shot.tscn -- 8
```

`sim.gd` checa a cada turno que nenhuma criatura está fora da linha principal,
que toda criatura está em tile com terreno do elemento dela, que uma tile não
tem duas entidades, que nada morto sobrou no tabuleiro e que nenhuma carta
existe em dois lugares.

## Ajustes rápidos

O equilíbrio mora em constantes no topo de `scripts/game.gd`:

| Constante | Padrão | O que faz |
|---|---|---|
| `STARTING_HP` | 10 | dano para vencer |
| `HAND_SIZE` | 5 | cartas na mão |
| `MANA_DICE` / `MANA_DIE_FACES` | 1 / 6 | rolagem de mana |
| `MANA_CARRYOVER` | `true` | mana não gasta acumula |
| `MANA_MAX` | 10 | teto do acúmulo |
| `TURN_PUNISHMENT_DAMAGE` | 1 | atrito; `0` desliga |
| `USE_SUMMONING_SICKNESS` | `true` | invocação nova não luta no mesmo round |
| `SHUFFLE_DECK` | `true` | embaralha o baralho |
| `SEED` | `20260101` | `0` = aleatório a cada partida |
| `VS_AI` | `true` | `false` deixa o modo 2 jogadores (em construção) |

As cartas estão todas em `CardDB.all()`, com ATK/DEF, custo e elemento.

## Notas

- **Fonte sem acento.** `TinyFontCraftpixPixel.otf` (do kit) é Latin básico.
  `UiKit.fold()` traduz os acentos antes de desenhar. Trocar por uma fonte pixel
  com acentos deixa esse mapa dispensável.
- **Tiles de terreno são gerados.** Os PNGs do kit de ruínas têm borda
  transparente; um tile de terreno não precisa disso. `tools/make_terrain_tiles.py`
  achata e quantiza para paleta.
- **Terreno não vira entidade.** Ele só pinta a tile. Criatura e construção são
  as únicas coisas que ocupam tile.
- **Carta sem mana escurece, não fica transparente.** Escurecer o tom
  continua legível; baixar o alpha fazia a carta sumir.
- **Arquivos `.import` vão para o Git.** São ~944 arquivos de texto, um por
  asset. É o que a documentação do Godot recomenda, porque é neles que mora a
  configuração de importação (filtro nearest, normal map, compressão). Se
  preferir menos ruído no diff, dá para ignorá-los — o Godot regenera na
  primeira abertura, mas as configurações se perdem.
- **Arquivos `.uid` vão para o Git.** O Godot 4.4+ gera um `.uid` por script;
  eles são parte do projeto e devem ser versionados.

