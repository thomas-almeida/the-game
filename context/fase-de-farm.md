# Fase de farm — especificação

> Decidido pelo orquestrador em conjunto com o usuário. **Este documento é a
> fonte da verdade.** Qualquer agente que descobrir que o código diverge daqui
> deve parar e reportar, não "consertar" por conta própria — divergência entre
> agente e spec é sempre bug de um dos dois lados.

## Cadência

A cada **3 rodadas**, a rodada 3 é o round de farm.

```
round 1  preparação   round 2  preparação   round 3  FARM
round 4  preparação   round 5  preparação   round 6  FARM
```

Regra: `round % 3 == 0`.

## Onde a fase entra na rodada

```
ROLL          (clique no dado: compra 1 carta + rola a mana)
PLAYER_BUILD  (jogador invoca terreno e criaturas)
AI_BUILD      (IA joga)
FARM          <<< NOVO — antes do brawl, como aquecimento
BRAWL
PUNISH
```

A fase de farm acontece **antes** do confronto direto, que é a intenção: é o
aquecimento, não o combate.

## Layout 3D

Uma trilha por jogador, do lado do próprio dono, **fora dos limites do
tabuleiro**:

| Trilha | Posição | Direção do caminhada |
|---|---|---|
| jogador | embaixo, além da linha 3 | da esquerda para a direita (+X) |
| rival | em cima, além da linha 0 | da direita para a esquerda (−X) |

As criaturas do jogador atiram nos mobs da trilha **do jogador**; as do rival,
na trilha do rival. Duas partidas independentes, dois placares.

O tabuleiro não muda de significado: linhas 0–3 continuam sendo as mesmas,
criaturas continuam só na linha principal. As trilhas são elemento novo, e a
câmera precisa de um enquadramento que as inclua.

## Regras

1. Cada trilha spawna **6 mobs genéricos**, em fila, com vida variada de 1 a 6.
   Eles não atacam de volta: a fase é aquecimento, não punição.
2. Cada criatura na linha principal do dono atira **exatamente uma vez** por
   fase de farm, no **mobo da frente** da sua trilha. Isso torna o placar uma
   função direta do estado do tabuleiro — que é o que faz o bônus valer.
3. O dano é o **ATK atual** da criatura no momento do tiro.
4. O mobo morre quando a vida chega a 0 e para de avançar.
5. A trilha acaba quando todos os mobs morreram ou atravessaram.
6. Vence quem destruiu mais. **Empate não dá bônus a ninguém** — sem isso o
   prêmio vira resultado do dado, não da jogada.

## Bonus - por elemento do proprio tabuleiro

> **Reescrito duas vezes pelo usuario.** A ideia final nao e um premio por
> vencer a fase: o bonus vem de **quais criaturas estao no seu campo**, e
> aplica automaticamente. E isso que cria variacao de build - mono-elemento
> concentra, misto espalha.

### O gatilho

Conta as criaturas do jogador **por elemento no tabuleiro agora** e aplica o
bonus de cada elemento presente. Nao ha sorteio nem escolha.

```
3 fogo                      -> bonus de fogo
1 fogo + 1 agua + 1 terra   -> bonus de fogo + de agua + de terra, todos junto
```

### Tabela

| Elemento | Bonus por criatura daquele elemento | Intencao |
|---|---|---|
| **FOGO** | +1 ATK em todas as criaturas | agressao |
| **GELO** | +1 de mana na proxima rolagem | tempo |
| **TERRA** | +1 de vida curada | sobrevivencia |
| **SOMBRA** | +1 ATK em todas as criaturas | escala |
| **AGUA** | +1 DEF em todas as criaturas | defesa |

Agua nao estava na sugestao original e o jogo tem cinco elementos. **+1 DEF**
fecha a simetria com Sombra: as duas defensivas ampliam o tabuleiro inteiro,
as duas ofensivas fazem algo unico, e Gelo e o unico que mexe no tempo.

### O numero que importa: maximo de 3 criaturas

O tabuleiro tem **3 colunas** e `Rules.can_place` so permite criatura na
linha principal, com uma entidade por tile. Entao **o maximo e 3 criaturas**.

E isso que define o balanceamento do bonus:

- **Com contagem simples** (ter 1 fogo = mesmo bonus que ter 3 fogo) nao ha
  incentivo nenhum em concentrar - todo build da o mesmo. A variacao de build
  que o usuario quer **nao acontece**.
- **Com a contagem escalando** (1 fogo = +1 ATK, 3 fogo = +3 ATK), concentrar
  fica estritamente melhor para ATK, e espalhar da variedade com menos de
  cada. Aí a escolha e real: mono-elemento forte, ou mixto com_solver.

**A spec assume que escala com a contagem.** E a unica leitura que entrega a
variacao de build que motivou a mudanca.

### Aplicacao

- **Recalculado a cada fase de farm**, a partir do tabuleiro do momento.
- Os bonuses de ATK/DEF sao **permanentes** e somam. O de mana e do
  **proxima rolagem**. O de vida e cura na hora.
- **Teto de +3 por elemento**, para nao crescer sem limite numa partida longa.
- **Os dois lados recebem**, pelo proprio tabuleiro. Nao e premio de disputa.

### PENDENTE - o placar da fase

A pontuacao da fase de farm (mobs destruidos) **deixou de dar bonus**. Nada
na spec atual diz o que ela faz, e sem isso a fase de farm nao tem recompensa
mecanica nenhuma - o placar seria so numero decorativo.

O orquestrador recomenda **placar vira cura** (mobs destruidos curam vida),
porque mantem a fase competitiva, e legivel na hora, e nao briga com a
identidade de build dos bonuses. **Aguardando o usuario decidir.** Ate la,
implemente o placar como esta (emitindo os eventos) e nao de premio por ele.

## Contrato de eventos

**Isto é o que impede os agentes de inventar formatos diferentes.** Todo o
comportamento de presentation sai por aqui.

```gdscript
_event("farm_start", {})                       # fase começou
_event("mob_spawned",  {"lane": int, "i": int, "hp": int})
_event("mob_moved",   {"lane": int, "i": int, "x": float})
_event("mob_hit",     {"lane": int, "i": int, "amount": int, "hp_left": int})
_event("mob_killed",  {"lane": int, "i": int})
_event("mob_escaped", {"lane": int, "i": int})
_event("farm_end",    {"player_score": int, "ai_score": int, "winner": int})
_event("bonus",       {"side": int, "element": int, "count": int,
                      "atk": int, "def": int, "mana": int, "heal": int})
```

`lane` é `Board.Side.PLAYER` ou `Board.Side.AI`. `winner` é o lado vencedor, ou
`-1` no empate. `count` em `bonus` é **quantas criaturas daquele elemento estão
no campo** — é o número que faz o bônus escalar.

Um `bonus` por **par (lado, elemento)**, não por lado. Uma trilha com
`1 fogo + 1 agua` emite **dois** `bonus`.

## Quem faz o quê

| Agente | Escopo desta fase |
|---|---|
| `mecanicas` | Fases em `game.gd`, regras e placar em `rules.gd`, dados do mob genérico, `commit_farm()` |
| `cena` | Geometria das duas trilhas, os mobs genéricos andando, os projéteis do ataque a distância |
| `interface` | HUD da fase: placar da fase, vida dos mobs, aviso "FASE DE FARM" |
| **orquestrador** | `main_3d.gd`: enquadramento de câmera com as trilhas, e ligar os eventos à cena |

## Ordem de execução

`mecanicas` primeiro — é o que produz os eventos. `cena` e `interface` podem
desenvolver contra o contrato acima sem esperar, e eu integro no fim.

## Invariantes que continuam valendo

Está tudo em `invariantes.md`. As que mais pesam aqui:

- **Armadilha 1**: nada de estado preso em `true` dentro de função com `await`.
  A fase de farm tem várias pausas — cuidado redobrado.
- **Armadilha 6**: callback de animação não pode ser perdido, senão sobra nó
  órfão na cena.
- **`Game` não sabe que existe 3D.** Nada de `Node3D` ou posição de câmera.
  As trilhas existem como dado (`x` na trilha), e a cena decide onde isso vira
  geometria.
- Texto novo em português passa por `UiKit.fold()`.
