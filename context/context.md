# the-game — Design

Card battler tático por turnos. Board fixo dividido ao meio, invocação de
criaturas/terrenos, e um "brawl" resolvido no fim do turno.

---

## 1. Tabuleiro

Grade de **3 colunas × 4 linhas** (12 tiles). Metade de cima é da IA, metade de
baixo é do jogador. Cada lado tem 2 linhas:

```
  linha 0  ┌─────────────┐   IA   — LINHA SECUNDÁRIA (back)
  linha 1  ├─────────────┤   IA   — LINHA PRINCIPAL (front)
           ╞═════════════╡   ← linha de choque (não é tile)
  linha 2  ├─────────────┤   VOCÊ — LINHA PRINCIPAL (front)
  linha 3  └─────────────┘   VOCÊ — LINHA SECUNDÁRIA (back)
            col 0  col 1  col 2
```

### Regras de ocupação

| Linha | Aceita |
|---|---|
| Principal (1 e 2) | **só criaturas** (e terreno) |
| Secundária (0 e 3) | construções, magias permanentes, terreno |

- Uma tile só aceita **uma** entidade.
- Criatura só vai na **linha principal**.
- Construção/magia permanente só vai na **linha secundária**.
- Terreno pode ir em **qualquer** linha vazia, e pode repintar uma tile que já
  tenha terreno (mas não uma que tenha criatura).

### Regra do terreno

Terreno **pinta** a tile. Uma criatura só pode ser invocada numa tile da linha
principal **se o terreno daquela tile for do mesmo elemento** da criatura.

O terreno é portanto um pré-requisito: primeiro se prepara o campo, depois se
invoca. Isso cria a tensão de uso das tiles de frente.

**Repintar é permitido.** Jogar terreno numa tile que já tem terreno troca o
elemento. A única restrição é não pisar em cima de uma criatura.

Sem isso a partida trava: se a linha principal inteiro fica pintado de um
elemento que você não tem criatura, e o terreno é permanente, você nunca mais
invoca nada nessa linha e o jogo não acaba. Foi exatamente o que apareceu em
~3% das partidas simuladas antes da regra existir.

### Magia

Magia não ocupa tile e não é jogável contra nada que não seja uma criatura
inimiga (ou a própria criatura, no caso de `BUFF`). Magias sem alvo — cura,
compra, dano no jogador — são resolvidas na hora ao clicar na carta.


---

## 2. Cartas

Quatro tipos:

| Tipo | Onde joga | Tem ATK/DEF |
|---|---|---|
| `CREATURE` | linha principal | sim |
| `TERRAIN` | qualquer linha vazia | não |
| `BUILDING` | linha secundária | não |
| `SPELL` | instantâneo, não ocupa tile | não |

### Elementos

`WATER` · `FIRE` · `EARTH` · `FROST` · `SHADOW`

Cada elemento tem um tile de terreno e uma cor de UI.

### Custos

Mana de **1 a 6** por carta.

---

## 3. Combate — modelo Magic

Lateral, dos dois lados. Uma criatura é `[ATK/DEF]`.

Na resolução, criaturas da linha principal **olhando para a mesma coluna** se
embatem:

```
A [1/3]  ←→  B [2/5]

A causa 1 de dano em B   (1 < 5, B sobrevive)
B causa 2 de dano em A   (2 < 3, A sobrevive)
```

- Cada um causa o seu ATK no outro.
- Cada um morre se o dano recebido for **>= própria DEF**.
- Quem morre **não causa dano** no mesmo brawl (a resolução é simultânea).

### Coluna vazia

Se uma criatura está na linha principal e **não tem ninguém na coluna à
frente**, ela avança e causa o seu ATK **direto no jogador** adversário.

Essa é a única forma de causar dano no jogador. Vence quem chegar a **10**.

---

## 4. Estrutura de turno

```
ROUND N
  ├─ ROLL     cada jogador rola 1d6 → mana da rodada
  ├─ DRAW     cada jogador completa a mão até 5
  ├─ BUILD    jogador joga cartas (paga mana, ocupa tiles)
  ├─ BUILD    IA joga cartas
  ├─ BRAWL    resolução de combate (ver seção 3)
  ├─ PUNISH   criaturas ganham 1 de dano (atrito estilo Magic)
  └─ NEXT     checa vitória (HP ≤ 0) → próximo round
```

### Regras herdadas de Magic

- **Summoning sickness** — uma criatura invocada no round atual **não**
  participa do brawl daquele round.
- **Turn punishment** — 1 de dano em todas as criaturas no fim do round.

Ambas estão expostas como constantes em `scripts/game.gd`.

### Ajustes que o protótipo exigiu

Três coisas quebraram a partida quando testadas, e foram corrigidas. Todas as
três são constantes agora, então dá pra sentir cada uma isoladamente:

| Ajuste | Por quê |
|---|---|
| **Mana acumula** (`MANA_CARRYOVER`) | 1d6 por round com custos de 1 a 6 pagava no máximo uma carta por turno. A partida travava no round 9 sem nunca se decidir. |
| **Descarte volta pro baralho** | Sem reciclagem, os 20 cards acabavam e a partida morria sozinha com o tabuleiro vazio. |
| **DEF mínimo 2** | Com atrito de 1 e summoning sickness, toda criatura 1/1 morria no mesmo round em que era invocada. O tabuleiro nunca se formava. |
| **Terreno pode ser repintado** | Linha principal pintada do elemento errado trancava a partida para sempre. |

Também: o baralho inicial tem **terreno para todo elemento que tem criatura**
(senão aquela criatura é invocável) e **custos cobrindo 1 a 6** (senão as
cartas caras nunca são testadas).

Depois dos quatro ajustes, 240 partidas simuladas terminam sempre, com o
placar em torno de 50/50 e partida mais longa com 14 rounds.

---

## 5. Condição de vitória

HP do jogador começa em **10**. Primeiro a zerar perde.

---

## 6. Layout dos assets

| Uso | Arquivo |
|---|---|
| Tokens de criatura | `1 Characters/*/U_*.png`, `3 Dungeon Enemies/*/U_*.png` |
| Terreno | `assets/generated/terrain/*.png` (32×32, gerado por `tools/make_terrain_tiles.py`) |
| Ícones | `4 GUI/3 Icons/Icon_*.png` (10×10) |
| Fonte | `4 GUI/TinyFontCraftpixPixel.otf` |

Sprites são folhas de 32×32 em faixa horizontal. `U_` = olhando pra cima
(jogador), `D_` = olhando pra baixo (IA).

Os tiles de terreno são **gerados**, não usados direto do kit: os PNGs
originais do kit de ruínas são RGBA com borda transparente, e um tile de
terreno é quadrado por definição — a transparência só atrapalha. O script
achata sobre fundo opaco e quantiza para paleta.

### Fonte sem acento

A `TinyFontCraftpixPixel` do kit é Latin básico: **não tem nenhum acento**. Como
a UI está em português, `UiKit.fold()` traduz os caracteres antes de desenhar
("VOCÊ" → "VOCE", "×" → "x"). Se trocar por uma fonte pixel com acentos, pode
remover esse mapa.

---

## 7. Estado atual

**Funciona:** tabuleiro, linhas, regra do terreno, mão, mana, descarte, brawl
com dano lateral, coluna vazia batendo no jogador, atrito, sumoning sickness,
magias com alvo, condição de vitória, IA.

**Não implementado (de propósito no MVP):**

- As construções não têm efeito mecânico nenhum — só ocupam tile e são
  descartáveis. A linha secundária está lá, mas é inerte.
- Sem animação. O turno da IA e o brawl resolvem de uma vez, num único passo
  síncrono; o log é a única forma de acompanhar.
- Só contra IA. O tabuleiro já é simétrico e o estado é indexado por
  `Board.Side`, então 2 jogadores locais é essencialmente um segundo
  `PlayerState` e trocar quem joga na fase `PLAYER_BUILD`.
- `GAME_OVER` não tem tela de fim, só um aviso.

