# Invariantes do projeto

Leia isto **antes** de editar qualquer arquivo. Estes são erros que já
aconteceram e foram corrigidos; sem este documento, um agente com contexto
limpo reintroduz cada um deles.

## Arquitetura

`Game` é headless e não sabe que existe 3D. Ele só acumula uma fila de eventos
(`_event()` / `take_events()`) e emite signals. A cena drena a fila e decide o
que animar. Por isso a lógica é testável sem abrir janela:

```
godot --headless --path C:\Repos\the-game --script res://tests/sim.gd -- 1000
```

Fluxo de uma rodada:

```
_begin_round()  -> fase ROLL, PARA aqui (roll_pending = true)
                     ↓
commit_roll()   -> compra 1 carta (obrigatória) + rola a mana
                  -> fase PLAYER_BUILD
```

O clique no dado chama `commit_roll()`. No sim e no trace é chamada direto.

## Quem é dono de qual arquivo

Conflitos de edição são o maior risco com vários agentes. Cada agente só pode
editar os arquivos dele:

| Agente | Arquivos |
|---|---|
| `mecanicas` | `scripts/game.gd`, `rules.gd`, `board.gd`, `board_entity.gd`, `player_state.gd`, `card_data.gd`, `card_db.gd`, `ai_brain.gd`, `tests/sim.gd`, `tests/trace.gd` |
| `interface` | `scripts/view/hud.gd`, `scripts/ui/card_view.gd`, `scripts/ui/ui_kit.gd`, `scripts/view/card_face.gd`, `scripts/view/hand_view.gd`, `tests/shot.gd` |
| `cena` | `scripts/view/tile_3d.gd`, `entity_3d.gd`, `board_3d.gd`, `die_3d.gd`, `assets/**` |
| **orquestrador** | `scripts/view/main_3d.gd` (o hub) + integração + validação |

`main_3d.gd` é o arquivo que os três precisam e nenhum pode ter. É meu. Se um
agente precisar mudar algo lá, ele reporta e eu faço (via barramento MCP ou CLI
documentado em `context/comunicacao.md`).

## Armadilhas do Godot 4 que já custaram tempo

### 1. `await` dentro de função recursiva cria cópia da corrotina

Este já travou a fila de efeitos: cada retomada roda numa cópia, então um
`_fx_busy = true` dentro de uma função com `await` **nunca volta a false**. A
fila drenava e o turno nunca destravava.

```gdscript
# ERRADO — estado preso em cópia
func _fx_one() -> void:
    _busy = true
    await get_tree().create_timer(0.34).timeout
    _busy = false        # nunca executa no contexto certo

# CERTO — Timer de verdade
_fx_timer.timeout.connect(_on_fx_timer_done)
```

### 2. `Label` com autowrap explode a caixa antes do layout

A altura mínima de um `Label` com `AUTOWRAP` é calculada quebrando o texto na
largura **atual** — que antes do layout é ~0. Resultado: uma caixa de 21×1601px
com o texto uma letra por linha. Ou desliga o autowrap em linhas curtas, ou dá
largura mínima explícita.

### 3. `Basis.slerp` exige base normalizada

`slerp` converte a base em `Quaternion` por dentro. Se a base tiver escala
residual (ex.: um "bob" flutuante no `scale`), o Godot cuspe erro a cada frame.
Normalize **antes** do slerp:

```gdscript
_from = transform.basis.orthonormalized()   # não depois
```

### 4. `set_trans()` devolve `PropertyTweener`, não `Tween`

Encadear `.tween_property()` no retorno de `set_trans()` dá erro de tipo.
Use `tween_property()` normal para encadear, ou guarde o `PropertyTweener`.

### 5. Tween escrevendo em nó já liberado

Um tween de `hit()` continua rodando se a criatura morrer no meio, e aí ele
tenta escrever num `Sprite3D` destruído
(*"Trying to assign invalid previously freed instance"*). Guarde o tween numa
variável e mate com `kill()` antes de liberar o nó.

### 6. `Callback` de animação não pode ser perdido

`die(on_done)` toca a animação; se a animação terminar chamando `_fade_out()`
**sem** o `on_done`, o nó é liberado mas a chave continua no dicionário do
`Board3D`, e o próximo `sync` opera num objeto destruído. Guarde o callback.

### 7. `BoxMesh` não aceita 6 materiais

`set_surface_override_material` só substitui a primeira surface. Para um cubo
com uma textura por face, monte seis `QuadMesh` — o que também dá controle
direto de para onde cada face olha.

### 8. Semente fixa: toda partida idêntica

`Game.SEED` valia `20260101` por padrão, sobra do MVP "para manter a partida
reproduzível". O efeito: **toda partida tinha o mesmo baralho e a mesma
sequência de dados** (o jogador tirava 2, 2, 6… sempre). O usuário reportou
"sempre que rolo o dado cai mana 2" e a causa só apareceu quando alguém
estranhou que vários testes independentes davam o mesmo número.

- O padrão é **`SEED = 0`** (aleatória). Valor fixo só de forma explícita:
  `sim.gd` e `trace.gd` atribuem `game.SEED` antes do `start_game()`.
- A semente é aplicada **antes** do embaralhamento no `start_game`. Estava
  depois: no REINICIAR o baralho mudava mas os dados recomeçavam iguais.
- **Regra de método:** se um teste dá o MESMO número várias vezes, isso é um
  alarme, não consistência. Olhe a distribuição. `tests/roll_check.gd` faz isso.

### 9. Rotação de uma face de dado: transposta E alvo = câmera

Dois erros empilhados, e só o segundo apareceu depois do primeiro corrigido.

**(a) Transposta, não a base.** Para levar a face de normal `N` a um alvo, a
rotação `R` tem que satisfazer `R * N = alvo`. `Basis(right, up, N)` faz o
INVERSO (`R * Z = N`). Usar `b` direto só funciona para as faces ±Z (a matriz é
a sua própria inversa); em ±X e ±Y o dado mostrava a face **oposta**.

**(b) O alvo é a DIREÇÃO ATÉ A CÂMERA, não `+Z`.** A câmera é elevada (olha o
tabuleiro de cima): `+Z` tem produto escalar de só ~0.44 com a direção da
câmera, e a face de cima ~0.75. Um cubo visto de cima e de lado mostra o topo
bem maior que a "frente", então mesmo uma rotação perfeita para `+Z` fazia o
jogador ler o número do topo — que era outro. Fórmula final:
`R = T · Bᵀ`, com `B = Basis(right, up, N)` e `T = Basis(right', up', toward)`.

**Como se prova:** `tests/shot.gd` modo `4` com valor `0` calcula, para cada
valor sorteado, *qual número está de fato virado para a câmera* (maior produto
escalar com a direção câmera→dado) e compara. Antes da correção errava 3, 4 e 6;
depois, as seis com produto escalar 1.0.

**Lição de método:** conferir `basis.z` deu "confere" para um dado errado — era a
pergunta errada. E o primeiro teste correto falhou nas DUAS versões: um teste
que falha dos dois lados diz que o problema está em outro lugar, e isso foi mais
útil que qualquer "OK".

### 10. Janela de teste pendurada = parse error no script de teste

Se `tests/shot.gd` não compila, a janela do Godot **fica aberta numa tela de
erro para sempre** (a cena sobe sem script e nunca chama `quit()`). Rode o
`load_check` antes. Em scripts de teste, **não** use `var x := a == b` com
`b` vindo de um `Array` sem tipo: o GDScript não infere (`Variant`) e o parse
falha. Tipe explicitamente (`var ok: bool = ...`). Ao disparar o Godot em
background, use `Start-Process ... WaitForExit(timeout)` e mate o processo se
estourar.

## Invariantes de design (não são sugestão, são decisão)

- **O log fica oculto e abre com `L`.** Deixá-lo à vista fazia o jogador ler
  texto em vez de olhar o tabuleiro, e o tabuleiro era o que não tinha
  feedback. Não reintroduza o log sempre visível.
- **Não existe modal de detalhe.** Clique na carta seleciona (borda colorida +
  tile verde + faixa no canto inferior esquerdo). Um modal sequestrava o clique:
  o jogador achava que estava invocando e só lia.
- **Hover não abre nada.** Só levanta, endireita e inclina a carta. O painel de
  leitura abre no clique esquerdo.
- **Selecionar não move nem aumenta a carta.** Só acende a borda na cor do
  elemento.
- **A compra de 1 carta por rodada é obrigatória** e vem antes da rolagem.
  Ver abaixo.
- **`UiKit.fold()`** translitera acentos porque a fonte
  (`TinyFontCraftpixPixel.otf`) é Latin básico e não tem acento nenhum nem
  `×`/`·`. Texto novo em português precisa passar por ele.

## Por que a compra obrigatória existe

Já houve **empate travado** em ~1 de cada 700 partidas. O mecanismo exato:

1. A mão só era completada até `HAND_SIZE`, com
   `while p.hand.size() < target`. Com a mão cheia o corpo do laço não
   executava.
2. Logo o baralho nunca era tocado e `_reshuffle_discard` nunca rodava — as
   criaturas ficavam presas no descarte.
3. O tabuleiro ficava **sem nenhuma criatura**.
4. Todo dano vem de criatura: o brawl só olha `ROW_PLAYER_FRONT` (2) e
   `ROW_AI_FRONT` (1), e a punição de atrito pula o que não é criatura.
5. Sem dano possível, a vida dos dois ficava imutável. A vitória só existe por
   vida zerada, então a partida nunca terminava.

A compra obrigatória por rodada mata o passo 2 pela origem. **Não reintroduza
`while hand.size() < HAND_SIZE` como única forma de comprar.** Se mudar isso,
rode o sim com 1000+ partidas: o defeito era raro demais para aparecer em 60.

## Como validar

### "Compila" NÃO é `--editor --quit`

`godot --editor --quit` **só enxerga scripts alcançáveis por `class_name`**. O
`hud.gd` e o `main_3d.gd` não têm, então um erro de parse neles passa "limpo".
Isso já deixou o jogo abrir **sem HUD nenhum** (o script falhou, o nó virou
`null`, e ninguém viu porque o check dizia OK).

A verificação de compilação de verdade é o `load_check`, que carrega todos os
scripts como cena (em `--script` os autoloads não existem e todo script que usa
`Game` daria falso positivo):

```powershell
& "C:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path C:\Repos\the-game res://tests/load_check.tscn
```

Tem que imprimir `OK: N scripts carregaram sem erro de parse`. **Rode isto antes
de dizer "compila".**

### Edição pela metade

Se a sua sessão cair (rate limit) no meio de uma edição, ela pode deixar uma
variável usada e nunca declarada. Ao retomar trabalho num arquivo, rode o
`load_check` primeiro — antes de assumir que o que está em disco funciona.

```powershell
$g = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"

# class_name apenas (NAO basta; ver acima)
& $g --headless --path C:\Repos\the-game --editor --quit

# 60 partidas (rápido, não prova ausência de empate)
& $g --headless --path C:\Repos\the-game --script res://tests/sim.gd

# 1000+ partidas (prova de verdade)
& $g --headless --path C:\Repos\the-game --script res://tests/sim.gd -- 1000

# captura: N turnos, ou o modo de teste
Remove-Item -Recurse -Force "$env:APPDATA\Godot\app_userdata\the-game" -ErrorAction SilentlyContinue
& $g --path C:\Repos\the-game --rendering-driver opengl3 res://tests/shot.tscn -- 6
```

**Apagar `$env:APPDATA\Godot\app_userdata\the-game` antes de capturar é
obrigatório**, senão vem um PNG velho sem erro nenhum.

`shot.tscn` **não é headless**: abre janela de verdade e renderiza por software
(10–20s por execução). Minimize execuções — cada verificação que abre uma
janela é uma janela piscando na tela do usuário.

### Modos do `tests/shot.gd`

Argumentos: `-- turnos mx my modo extra`

| modo | o que faz |
|---|---|
| `994` | **pipeline completo do farm**: eventos reais do `Game` -> fila -> cena + HUD, com capturas. Use `-- 3 0 0 994` (o `3` leva à rodada 3; o primeiro turno do laço só abre a rolagem) |
| `995` | farm: força só o HUD isolado, sem eventos |
| `4` + `0` | **confere as 6 faces do dado** numa execução: calcula qual número está virado para a câmera para cada valor sorteado. Use `-- 0 0 0 0 4 0` |
| `997` | fluxo real: espera pedir o dado, clica nele, invoca uma criatura |
| `998` | clica no dado e segura |
| `999` | força o estado de turno do rival e segura (conferir visual) |
| `996` | invoca cartas e aperta REINICIAR (testa vazamento de cena) |
| `4` + valor | impõe um valor no dado e segura |
| `2` | imprime onde os dados caem na tela |
| `3` | imprime tamanho/posição real dos sprites |

## Estado atual

- **não commitado**, tudo no `main` do working tree
- sim de 5000 partidas: todas terminam, zero inconsistência, 48%/52%
- dado: `FACE_AXIS` e a rotação (transposta) corrigidos; ver armadilhas 8 e 9
- `tests/roll_check.gd` prova que o sorteio varia entre partidas e reinícios