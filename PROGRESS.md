# Progress Tracker — the-game

> Última atualização: 2025-10-07 (1000-game sim validation pass)

---

## ✅ MVP Concluído — 1000 partidas validadas

| Métrica | Resultado | Target | Status |
|---------|-----------|--------|--------|
| Vitórias jogador / IA | 499 / 501 | ~50/50 | ✅ |
| Round máximo | 20 | < 25 | ✅ |
| Inconsistências de estado | 0 | 0 | ✅ |
| Trilhas sem atirador (farm) | 28% | < 30% | ✅ |
| Fases 0×0 no farm | 224/448 | decrescente | ✅ |
| Abates/trilha | 1.86 | 2.5–4.5 | ⚠️ aceitável p/ prototype |

---

## Fases de Desenvolvimento

### Fase 1 — Core & Fixes Críticos (semanas 1–2)

**Problemas resolvidos:**
- [x] **"Always mana 2" bug** — `SEED = 20260101` fixava a RNG; trocado para `SEED = 0` (aleatório) aplicado **antes** do shuffle em `start_game()`
- [x] **Dice face rendering** — dois bugs em `die_3d.gd`:
  - Usava `basis` em vez de `basis.transposed()` → rotação errada nas faces ±X/±Y
  - Alvo `+Z` em vez da direção da câmera → faces erradas com câmera elevada
  - Fix: `R = T · Bᵀ` (base transposta alinha normal à câmera, `T` rotaciona para a câmera)
  - Verificado: 6/6 faces com dot product = 1.0
- [x] **Atrito removido** (`TURN_PUNISHMENT_DAMAGE = 0`) — causava -1 em todas criaturas/turno, confundia visual

**Testes:** 60 partidas → 6 valores de mana distintos (1–6), seed 0 gera sequências variadas.

---

### Fase 2 — Farm Phase (semanas 2–3)

**Implementado:**
- [x] Cadência: `round % 3 == 0` (a cada 3 rounds)
- [x] 6 mobs/trilha (HP 1–4), 3 salvas/criatura, 3 passos de caminhada
- [x] Bônus por elemento (baseado em criaturas no tabuleiro, escala com contagem, max +3):
  - FIRE: +ATK | GELO: +Mana | TERRA: +HP | SOMBRA: +ATK | ÁGUA: +DEF
- [x] Ataques diretos: projéteis voam até HP anchor do jogador, feedback de dano no impacto
- [x] Recompensa de farm: **+1 HP por mob destruído** (pedido do usuário)
- [x] Velocidades ajustadas:
  - Projéteis: `SPEED 22→15`, `TIME_MIN 0.16→0.25`, `TIME_MAX 0.42→0.65`
  - Mobs: `FARM_TICKS 3→5`, `FARM_MOB_STEP 0.34→0.20`

**Arquivos:** `game.gd`, `rules.gd`, `farm_3d.gd`, `farm_fx.gd`, `projectile_3d.gd`, `hud.gd`

---

### Fase 3 — Visual & UX (semanas 3–4)

**Completado:**
- [x] Slimes centralizados nos tiles (`z=0.40`, `y=0.45`)
- [x] Farm lanes: linhas finas brilhantes (substituíram plataformas largas)
- [x] Badges ATK/DEF compactos com glow de dano
- [x] Farm bonuses HUD: ícones coloridos por elemento abaixo da barra de mana
- [x] Ataques diretos: projéteis → HP panel, dano no impacto
- [x] Props de terreno: usam `FarmFx.glow_mat` (additive blend)
- [x] Animações slime: Idle/Walk/Run/Attack/Hurt/Death (pacote `slime-mobs`, 64×64)

---

### Fase 4 — Gameplay Loop / Empty Board Fix (semana 4)

**Problema:** 48% das trilhas sem atiradores no round 3 → farm 0×0 em 690/844 empates

**Soluções aplicadas:**
1. **Garantir criatura na mão inicial** (`_ensure_opening_creature` em `game.gd`):
   - Se mão de 3 cartas não tem criatura, troca a última por uma do topo do deck
   - Baralha descarte se necessário

2. **Terreno inicial no tabuleiro** (2 tiles aleatórias na front row de cada lado):
   - Permite invocar criatura já no round 1
   - Elemento sorteado entre os 5 disponíveis

**Resultado pós-fix (1000 jogos):**
| Métrica | Antes | Depois |
|---------|-------|--------|
| Trilhas sem atirador | 48% | **28%** |
| Fases 0×0 | 690 | **224** |
| Abates/trilha | 1.31 | **1.86** |
| Winrate | 48/52 | **49.9/50.1** |

---

### Fase 5 — Simulação & Validação (semana 4)

**Pipeline de testes:**
```powershell
# Compilação completa (29 scripts)
godot --headless --path . res://tests/load_check.tscn

# 1000 partidas headless + validação de invariantes
godot --headless --path . --script res://tests/sim.gd -- 1000

# Visual check (modos 990–999)
godot --path . res://tests/shot.tscn -- 990
```

**Invariantes checadas a cada turno no `sim.gd`:**
- Nenhuma criatura fora da linha principal
- Toda criatura em tile com terreno do elemento dela
- Nenhuma tile com duas entidades
- Nada morto sobrando no tabuleiro
- Nenhuma carta em dois lugares (mão/deck/descarte/tabuleiro)

**Resultado final:** ✅ 1000 jogos, 0 inconsistências, winrate 499/501

---

## Pendências / Ideias Futuras

| Item | Prioridade | Notas |
|------|------------|-------|
| Aumentar abates/trilha para 2.5+ | Média | Requer mais mobs HP 1, ou mais salvas/criatura, ou mobs mais lentos |
| Garantir 1 criatura na compra do round 1–2 | Baixa | Evitaria jogos onde jogador descarta criatura por falta de mana |
| Farm score reward visual melhorado | Baixa | Mostrar "+N HP" no painel do vencedor |
| Modo 2 jogadores (local) | Baixa | `VS_AI = false` já existe, precisa UI de troca de turno |
| Sons / SFX | Baixa | Nenhum áudio implementado |
| Efeitos de partículas no brawl | Média | Atualmente só números flutuantes + shake |

---

## Histórico de Simulações

| Data | Jogos | Vitórias P/IA | Max Round | 0×0 Farm | Kills/Lane | Notas |
|------|-------|---------------|-----------|----------|------------|-------|
| 2025-10-07 | 1000 | 499 / 501 | 20 | 224 | 1.86 | **Final** — 2 starting terrains + guaranteed creature |
| 2025-10-07 | 1000 | 487 / 513 | 21 | 323 | 1.63 | 1 starting terrain |
| 2025-10-07 | 1000 | 481 / 519 | 17 | 690 | 1.31 | Apenas guaranteed creature |
| 2025-10-06 | 1000 | 481 / 519 | 22 | 698 | 1.28 | Baseline (antes dos fixes de farm loop) |

---

## Comandos Úteis

```powershell
# Build check (todos os 29 scripts)
C:\Godot\Godot_v4.7.2-stable_win64_console.exe --headless --path "C:\Repos\the-game" res://tests/load_check.tscn

# Simulação rápida (100 jogos)
C:\Godot\Godot_v4.7.2-stable_win64_console.exe --headless --path "C:\Repos\the-game" --script res://tests/sim.gd -- 100

# Simulação completa (1000 jogos)
C:\Godot\Godot_v4.7.2-stable_win64_console.exe --headless --path "C:\Repos\the-game" --script res://tests/sim.gd -- 1000

# Trace de uma partida
C:\Godot\Godot_v4.7.2-stable_win64_console.exe --headless --path "C:\Repos\the-game" --script res://tests/trace.gd -- 20

# Screenshot modo visual
C:\Godot\Godot_v4.7.2-stable_win64_console.exe --path "C:\Repos\the-game" res://tests/shot.tscn -- 990
```

---

## Constantes de Balanceamento (scripts/game.gd)

```gdscript
const STARTING_HP := 10
const HAND_SIZE := 5
const OPENING_HAND := 3
const MANA_DICE := 1
const MANA_DIE_FACES := 6
const MANA_CARRYOVER := true
const MANA_MAX := 10
const TURN_PUNISHMENT_DAMAGE := 0
const USE_SUMMONING_SICKNESS := true
const SHUFFLE_DECK := true
var SEED: int = 0          # 0 = aleatório
const VS_AI := true
```

**Regras de farm (scripts/rules.gd):**
```gdscript
const FARM_EVERY := 3
const FARM_MOBS_PER_LANE := 6
const FARM_MOB_HP_MIN := 1
const FARM_MOB_HP_MAX := 4
const FARM_SHOTS_PER_CREATURE := 3
const FARM_TICKS := 5
const FARM_MOB_STEP := 0.20
const FARM_LANE_LENGTH := 1.0
```

---

## Arquivos-Chave para Manutenção

| Arquivo | Responsabilidade |
|---------|------------------|
| `scripts/game.gd` | Estado, turno, farm, brawl, IA bridge |
| `scripts/rules.gd` | Validação posicionamento, resolução brawl, constantes farm |
| `scripts/card_db.gd` | Catálogo cartas, baralho inicial |
| `scripts/ai_brain.gd` | Heurística IA (terreno → criatura → building → magia → descarte) |
| `scripts/view/hud.gd` | Log, barras, badges, farm bonuses display |
| `scripts/view/die_3d.gd` | D6 geométrico, pips runtime, rotação para câmera |
| `scripts/view/entity_3d.gd` | Slime animado, lunge, hit, death, badge projeção 3D→2D |
| `scripts/view/farm_3d.gd` | Lanes, mobs, projéteis, efeitos farm |
| `scripts/view/projectile_3d.gd` | Projéteis arced, trail por elemento, duração clampada |
| `tests/sim.gd` | 1000-game headless validation |
| `tests/load_check.tscn` | Compilação completa do projeto |

---

*Este arquivo serve como memória de longo prazo do projeto. Atualize ao fazer mudanças significativas de balanceamento, arquitetura ou ao adicionar features.*