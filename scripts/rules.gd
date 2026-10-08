class_name Rules
extends RefCounted

## Regras de posicionamento e resolução de combate.
## Tudo aqui é estático e sem estado: recebe o tabuleiro/jogo e devolve o
## resultado. `can_place` devolve "" quando o lançamento é legal, ou o motivo
## daillegalidade (usado tanto no log quanto no tooltip da UI).

const OK := ""

# --- fase de farm ----------------------------------------------------------
# Pontos de ajuste da fase. Ficam aqui (e não no `Game`) porque a fase é
# REGRA: quem chama o brawl também precisa saber o que é uma rodada de farm.

## A cada quantas rodadas a rodada é de farm (`round % FARM_EVERY == 0`).
## 3 é a cadência da spec: dá duas rodadas de construção entre um aquecimento
## e outro, e o prêmio (+1 ATK) ainda chega quente no brawl logo em seguida.
const FARM_EVERY := 3

## Mobs por trilha. 6 é o número de casas que uma linha principal inteira
## (Board.COLS = 3) derruba ao longo da fase sem limpar a fila no primeiro
## golpe, e cabe na tela sem a trilha virar uma parede de sprites.
const FARM_MOBS_PER_LANE := 6

## Vida do mobo, sorteada por mobo.
##
## FOI 1..6 e a fase quase não rendia: medido em 1000 partidas, 95% dos mobs
## escapavam e 60% das fases terminavam empatadas. A conta é simples: 6 mobs de
## vida média 3,5 somam ~21 por trilha, e uma criatura só tirava ~3. Ver
## [FARM_SHOTS_PER_CREATURE] — o remédio principal é nos tiros, e a vida
## menor só ajuda a fila a cair.
const FARM_MOB_HP_MIN := 1
const FARM_MOB_HP_MAX := 4

## Tiros por criatura numa fase de farm: uma SALVA, não um tiro.
##
## Era 1 e foi a causa do 95% de fuga: com no máximo 3 criaturas por tabuleiro,
## o dano total da fase mal passava de 3-9, contra ~21 de vida na trilha. Uma
## salva de 3 faz a fase de fato derrubar a fila — que é o ponto, porque o
## usuário pediu uma fase dopaminérgica, com muita coisa morrendo e um placar
## que sobe. Cada tiro vai no mobo da frente NO MOMENTO do tiro, então quem
## mata um mobo já abre o próximo.
const FARM_SHOTS_PER_CREATURE := 3

## Comprimento da trilha em `x`: 0.0 é a entrada da fila, 1.0 é a saída.
## Normalizado de propósito — o `Game` não sabe onde a trilha fica na tela, e
## um 0.0..1.0 deixa a cena escolher o tamanho do mundo sem renegociar com a
## regra.
const FARM_LANE_LENGTH := 1.0

## Passos de caminhada por fase. É o que dá o ritmo do aquecimento: o que
## ninguém mira atravessa a trilha e conta como não-destruído, então a fase
## tem prazo. 5 é mais lento que o original (3), dando mais tempo pro jogador
## ver os mobs andarem.
const FARM_TICKS := 5

## Quanto o mobo anda por passo. 0.20 x 5 passos = 1.00, ou seja: quem nasce
## em 0.0 chega em 1.00 e atravessa. Menor que 0.34 dá mais tempo pro jogador
## ver os mobs andando.
const FARM_MOB_STEP := 0.20

## ATENÇÃO: o `x` é NORMALIZADO (0..1) e a cena multiplica pelo comprimento da
## trilha (~8.6 unidades de mundo). O corpo do mobo tem 0.72 de largura, então
## o espaçamento mínimo para não se sobreporem é 0.72 / 8.6 = 0.084. Com 0.06
## (que parecia pequeno) eles ficavam a 0.52 de distância e se atravessavam.
## 0.10 dá ~0.86 de mundo, que é o `MOB_SPACING` que a cena espera.
##
## Profundidade da fila: distância entre um mobo e o da frente. A fila nasce
## espalhada ao longo de `GAP * (FARM_MOBS_PER_LANE - 1)` da entrada, com o `i`
## 0 já mais advanced. É o que dá para a cena desenhar uma fila de verdade em
## vez de seis sprites empilhados no mesmo `x`.
const FARM_QUEUE_GAP := 0.10

## O BÔNUS DA FASE — por elemento do próprio tabuleiro.
##
## Não é prêmio de disputa: quem vence a fase não leva nada. Cada lado recebe
## pelo que tem em campo, contando as criaturas do elemento e aplicando o bônus
## DE CADA elemento presente. Ver [apply_farm_bonus].
##
## A tabela é **por criatura**: o bônus final é a linha multiplicada pela
## contagem. Isso é o número que decide a build. Sem escala, "ter 1 fogo" e
## "ter 3 fogo" dariam a mesma coisa, todo build pagaria o mesmo e a feature
## seria decorativa — concentrating num elemento só teria que continuar sendo
## estritamente melhor.
const FARM_BONUS_TABLE := {
	# FOGO e SOMBRA: as duas ofensivas que valem à partida inteira.
	CardData.Element.FIRE: {"atk": 1, "def": 0, "mana": 0, "heal": 0},
	CardData.Element.SHADOW: {"atk": 1, "def": 0, "mana": 0, "heal": 0},
	CardData.Element.WATER: {"atk": 0, "def": 1, "mana": 0, "heal": 0},
	CardData.Element.FROST: {"atk": 0, "def": 0, "mana": 1, "heal": 0},
	CardData.Element.EARTH: {"atk": 0, "def": 0, "mana": 0, "heal": 1},
}

## Teto por elemento. Hoje o tabuleiro limita a 3 criaturas (Board.COLS, uma por
## tile, só na linha principal), então a contagem nunca passa disso — mas o
## limite é explícito de propósito: se um dia a linha principal ganhar uma
## linha, o bônus não pode sair crescendo sem teto numa partida longa.
const FARM_BONUS_MAX_PER_ELEMENT := 3

## Criatura recém-invocada também atira na fase de farm. A spec é literal
## ("cada criatura na linha principal") e assim o placar fica função direta do
## tabuleiro. Se um dia a summoning sickness valer para o farm, é `false` aqui:
## o resto do caminho não muda.
const FARM_IGNORE_SUMMONING := true


static func in_bounds(col: int, row: int) -> bool:
	return col >= 0 and col < Board.COLS and row >= 0 and row < Board.ROWS


## Verifica se [side] pode jogar [card] em [col]/[row].
static func can_place(board: Board, side: int, card: CardData, col: int, row: int) -> String:
	if card == null:
		return "Carta inválida."
	if card.is_spell():
		return "Magias são resolvidas na hora, não vao pro tabuleiro."
	if not in_bounds(col, row):
		return "Fora do tabuleiro."
	if Board.side_of_row(row) != side:
		return "Essa tile não é do seu lado do tabuleiro."
	if board.is_occupied(col, row):
		return "Tile ocupada."

	match card.kind:
		CardData.Kind.CREATURE:
			if not Board.is_front_row(row):
				return "Criaturas só podem ser invocadas na linha principal."
			var t := board.get_terrain(col, row)
			if t != card.element:
				return "Precisa de terreno %s nesta tile." % card.element_text()
		CardData.Kind.TERRAIN:
			# Repintar é permitido: o terreno é permanente, então uma linha
			# principal pintada do elemento errado tranca a partida para sempre
			# (ninguém tem criatura daquele elemento e ninguém troca o terreno).
			# A restrição real é só não pisar em cima de uma criatura.
			pass
		CardData.Kind.BUILDING:
			if Board.is_front_row(row):
				return "Construções e magias permanentes só vão na linha secundária."
	return OK


## Uma carta é jogável agora, em alguma tile? Usado pela IA e pela UI.
static func find_legal_tile(board: Board, side: int, card: CardData) -> Vector2i:
	for row in [Board.front_row(side), Board.back_row(side)]:
		for col in Board.COLS:
			if can_place(board, side, card, col, row) == OK:
				return Vector2i(col, row)
	return Vector2i(-1, -1)


# --- magias ----------------------------------------------------------------

## Alvos válidos para a magia [card] jogada por [side].
static func spell_targets(board: Board, side: int, card: CardData) -> Array:
	var enemy := Board.Side.AI if side == Board.Side.PLAYER else Board.Side.PLAYER
	var out: Array = []
	match card.spell:
		CardData.Spell.DAMAGE_CREATURE, CardData.Spell.DESTROY_CREATURE:
			for col in Board.COLS:
				for row in Board.ROWS:
					var e := board.get_entity(col, row)
					if e != null and e.card().is_creature() and e.owner_side == enemy:
						out.append(Vector2i(col, row))
		CardData.Spell.BUFF_CREATURE:
			for col in Board.COLS:
				for row in Board.ROWS:
					var e := board.get_entity(col, row)
					if e != null and e.card().is_creature() and e.owner_side == side:
						out.append(Vector2i(col, row))
		_:
			pass  # sem alvo
	return out


static func spell_needs_target(card: CardData) -> bool:
	return card.spell in [
		CardData.Spell.DAMAGE_CREATURE,
		CardData.Spell.DESTROY_CREATURE,
		CardData.Spell.BUFF_CREATURE,
	]


# --- combate ---------------------------------------------------------------

## Resultado de uma coluna no brawl.
class Duel:
	var attacker: BoardEntity = null      # lado PLAYER
	var defender: BoardEntity = null      # lado AI
	var player_dealt: int = 0
	var ai_dealt: int = 0
	var to_player_hp: int = 0
	var to_ai_hp: int = 0
	var deaths: Array[BoardEntity] = []


## Monta os duelos da linha de choque antes de aplicar nada, para que a
## resolução seja simultânea (modelo Magic).
static func plan_brawl(board: Board, round: int, use_summoning_sickness: bool) -> Array:
	var duels: Array = []
	for col in Board.COLS:
		var d := Duel.new()
		var pt := board.get_entity(col, Board.ROW_PLAYER_FRONT)
		var ai := board.get_entity(col, Board.ROW_AI_FRONT)

		var pt_active := pt != null and (not use_summoning_sickness or pt.is_ready(round))
		var ai_active := ai != null and (not use_summoning_sickness or ai.is_ready(round))

		if pt_active:
			d.attacker = pt
		if ai_active:
			d.defender = ai

		if pt_active and ai_active:
			# frontal, lateral: cada um causa seu ATK no outro
			d.player_dealt = pt.attack
			d.ai_dealt = ai.attack
		elif pt_active:
			# coluna vazia: avança e bate direto no jogador
			d.to_ai_hp = pt.attack
		elif ai_active:
			d.to_player_hp = ai.attack

		duels.append(d)
	return duels


## Aplica dano e resolve mortes. [log_cb] recebe uma linha por evento.
static func apply_duels(duels: Array, log_cb: Callable) -> void:
	# 1. dano simultâneo
	for d in duels:
		if d.attacker != null and d.defender != null:
			d.defender.take_damage(d.player_dealt)
			d.attacker.take_damage(d.ai_dealt)
	# 2. mortes (depois de todo o dano, como SBA do Magic)
	for d in duels:
		for e in [d.attacker, d.defender]:
			if e != null and e.is_dead():
				d.deaths.append(e)


static func describe_duel(d: Duel) -> String:
	if d.attacker != null and d.defender != null:
		return "%s [%s] × %s [%s] → %s causa %d, %s causa %d" % [
			d.attacker.display_name(), d.attacker.card().stats_text(),
			d.defender.display_name(), d.defender.card().stats_text(),
			d.defender.display_name(), d.player_dealt,
			d.attacker.display_name(), d.ai_dealt,
		]
	if d.attacker != null:
		return "%s [%s] avança livre e causa %d no jogador" % [
			d.attacker.display_name(), d.attacker.card().stats_text(), d.to_ai_hp]
	if d.defender != null:
		return "%s [%s] avança livre e causa %d no jogador" % [
			d.defender.display_name(), d.defender.card().stats_text(), d.to_player_hp]
	return ""


# --- fase de farm ----------------------------------------------------------

## A rodada [round] é de farm? A cadência é `round % 3 == 0`, ou seja a rodada 3
## de cada ciclo — depois de duas rodadas de construção, que é o tempo de
## aparecer criatura suficiente para a fase valer alguma coisa.
static func is_farm_round(round_index: int) -> bool:
	return round_index % FARM_EVERY == 0


## A criatura [e] atira na fase de farm? Todo mundo na linha principal atira
## uma vez; o único filtro é a summoning sickness, e ele só entra em jogo se
## [FARM_IGNORE_SUMMONING] for desligado. O `Game` já percorre
## [Board.front_line], então "é criatura" e "é da minha linha" já estão
## garantidos aqui.
static func farm_shoots(e: BoardEntity, round_index: int) -> bool:
	if FARM_IGNORE_SUMMONING:
		return true
	return e.is_ready(round_index)


## Aplica o bônus de tabuleiro do lado [side] e devolve UM RESULTADO POR
## ELEMENTO PRESENTE, na ordem do enum — é isso que o `Game` vira evento
## `bonus`, um por par (lado, elemento).
##
## É a função ÚNICA da aplicação: mudar o balanceamento do bônus é mexer em
## [FARM_BONUS_TABLE] ou aqui, nunca na fase.
##
## Cada resultado traz `element`, `count` (criaturas daquele elemento em campo,
## já com o teto), os quatro números `atk`/`def`/`mana`/`heal` **já
## multiplicados pela contagem**, e `buffed`: as criaturas que mudaram, para o
## `Game` tocar um evento em cada.
static func apply_farm_bonus(board: Board, p: PlayerState, side: int) -> Array:
	var creatures := board.creatures_of(side)

	# Contagem por elemento. Percorre o enum inteiro (e não só os elementos
	# vistos) para a ordem de saída dos eventos ser sempre a mesma: a cena não
	# pode ver o bônus de FOGO antes do de ÁGUA numa partida e depois depois.
	var counts := {}
	for element: int in CardData.ELEMENT_LABEL:
		counts[element] = 0
	for e in creatures:
		counts[e.card().element] += 1

	var out: Array = []
	for element: int in counts:
		var count := mini(int(counts[element]), FARM_BONUS_MAX_PER_ELEMENT)
		if count <= 0:
			continue  # elemento ausente: sem bônus e sem evento
		var unit: Dictionary = FARM_BONUS_TABLE[element]
		var atk := int(unit["atk"]) * count
		var def := int(unit["def"]) * count
		var mana := int(unit["mana"]) * count
		var heal := int(unit["heal"]) * count

		# Só no tabuleiro de QUEM tem o elemento. Nos dois lados daria ao
		# adversário exatamente a mesma coisa.
		var buffed: Array[BoardEntity] = []
		for e in creatures:
			if atk > 0:
				e.buff_attack(atk)
			if def > 0:
				e.buff_defense(def)
			buffed.append(e)

		if heal > 0:
			p.heal(heal)
		if mana > 0:
			# "+N na PRÓXIMA rolagem", não "+N sempre": fica marcado no
			# jogador e é gasto uma vez em `Game.commit_roll`.
			p.pending_mana_bonus += mana

		out.append({
			"element": element,
			"count": count,
			"atk": atk, "def": def, "mana": mana, "heal": heal,
			"buffed": buffed,
		})
	return out
