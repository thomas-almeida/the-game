extends Node

## Autoload `Game`. Dono do estado da partida e da máquina de turnos.
## A UI só lê daqui e nunca escreve no tabuleiro diretamente.

signal state_changed
signal phase_changed(phase: int)
signal logged(text: String)
signal hand_changed
signal finished(winner_side: int)

enum Phase {
	IDLE,
	ROLL,
	DRAW,
	PLAYER_BUILD,
	AI_BUILD,
	FARM,
	BRAWL,
	PUNISH,
	GAME_OVER,
}

const PHASE_LABEL := {
	Phase.IDLE: "—",
	Phase.ROLL: "SORTEANDO MANA",
	Phase.DRAW: "COMPRANDO",
	Phase.PLAYER_BUILD: "SUA VEZ",
	Phase.AI_BUILD: "IA JOGANDO",
	Phase.FARM: "FASE DE FARM",
	Phase.BRAWL: "BRAWL",
	Phase.PUNISH: "ATITO",
	Phase.GAME_OVER: "FIM",
}

# --- regras afináveis do MVP ----------------------------------------------

const STARTING_HP := 10
const HAND_SIZE := 5
## Cartas da primeira mão. Mão curta de propósito: quem abre o jogo tem menos
## ruído para ler, e a partir da segunda rodada a compra obrigatória de 1 carta
## por vez é o que alimenta a partida.
const OPENING_HAND := 3
const MANA_DICE := 1
const MANA_DIE_FACES := 6
## Mana que não foi gasta fica para o próximo round (até este teto).
## Sem isso, 1d6 por round com custos de 1 a 6 trava a partida: cada turno
## paga no máximo uma carta e o tabuleiro nunca se decide.
const MANA_CARRYOVER := true
const MANA_MAX := 10
## Dano em toda criatura no fim do round (atrito estilo Magic). **DESLIGADO (0).**
##
## Era 1. Foi desligado a pedido do usuário: uma criatura que acabava de bater
## direto no jogador levava `-1` logo depois, com o número vermelho subindo e a
## câmera tremendo, e isso lia como se o próprio ataque a machucasse ("não faz
## sentido"). O dano em criatura agora só vem de duelo (mútuo, por design) e de
## magia.
##
## Atenção: o atrito também era o que renovava o tabuleiro. Se partidas
## travarem, rode `tests/sim.gd -- 1000` antes de religar.
const TURN_PUNISHMENT_DAMAGE := 0
## Criatura invocada no round não luta neste round (summoning sickness).
const USE_SUMMONING_SICKNESS := true
## Embaralha o baralho.
const SHUFFLE_DECK := true
## Semente da partida. **0 = aleatória** (o padrão): cada partida é diferente.
## Um valor fixo torna a partida reproduzível — é o que o `sim` e o `trace`
## fazem, atribuindo `game.SEED` antes do `start_game()`.
##
## Isto era `20260101`, sobra do MVP "para manter a partida reproduzível". O
## efeito: TODA partida era idêntica — mesma ordem de baralho e a mesma
## sequência de dados, com o jogador tirando 2, 2, 6… em toda partida. É a
## causa de "sempre que eu rolo o dado cai mana 2". Os meus próprios testes
## também davam 2 toda vez e eu lia como "consistente", em vez de estranhar.
var SEED: int = 0
## Ativa o opponent controlado por IA.
const VS_AI := true

# --- estado ----------------------------------------------------------------

var board: Board
var players: Array[PlayerState] = []
var round: int = 1
var phase: Phase = Phase.IDLE
## A rodada parou esperando o jogador clicar no dado. Enquanto é verdade, o
## clique nas cartas não faz nada: a mana ainda nem existe.
var roll_pending: bool = false
var log_lines: Array[String] = []

## Índice na mão da carta em resolução de magia, ou -1.
var pending_spell: int = -1

## FASE DE FARM — estado das duas trilhas, indexado por `Board.Side`:
## `farm_lanes[side]` é a fila de `FarmMob` daquele dono e `farm_scores[side]`
## é quantos ele destruiu na fase atual. Fica no `Game` (e não na cena) porque
## quem decide placar e prêmio é a regra; quem desenha lê daqui e da fila de
## eventos.
var farm_lanes: Array = []
var farm_scores: Array = []
## Cada lado já atirou nesta fase? Uma fase, um tiro por criatura por lado.
## É o que deixa [commit_farm] idempotente, e o que impede a IA de disparar
## duas vezes ao chamar a rotina no meio do turno dela.
var _farm_fired: Array = []

## Fila de eventos Accumulados desde o último [take_events]. A cena 3D lê isso
## para animar dano e morte; a UI só escuta signals. É uma fila em vez de
## signals porque os efeitos precisam de dois dados juntos (tile + valor).
var events: Array = []

var rng := RandomNumberGenerator.new()


func _event(kind: String, data := {}) -> void:
	data["type"] = kind
	events.append(data)


## Drena a fila. Chamar uma vez por quadro de sincronização.
func take_events() -> Array:
	var drained := events
	events = []
	return drained


func _ready() -> void:
	if SEED != 0:
		rng.seed = SEED
	else:
		rng.randomize()


# --- setup -----------------------------------------------------------------

func start_game() -> void:
	# A semente entra ANTES do embaralhamento. Estava depois: o baralho era
	# embaralhado com o estado que sobrou da partida anterior e só então o `rng`
	# era recolocado na semente — então num REINICIAR o baralho mudava mas a
	# sequência de dados recomeçava igual.
	if SEED != 0:
		rng.seed = SEED
	else:
		rng.randomize()

	board = Board.new()
	# O array é indexado por Board.Side: [AI, PLAYER].
	players = []
	players.resize(Board.Side.PLAYER + 1)
	players[Board.Side.AI] = PlayerState.new("RIVAL", VS_AI, Board.Side.AI, STARTING_HP)
	players[Board.Side.PLAYER] = PlayerState.new("VOCÊ", not VS_AI, Board.Side.PLAYER, STARTING_HP)
	for p in players:
		p.deck = CardDB.starting_deck().duplicate()
		if SHUFFLE_DECK:
			p.shuffle_deck(rng)

	round = 1
	log_lines.clear()
	# A fase de farm precisa começar zerada junto com a partida: deixar
	# `FarmMob` da partida anterior vivo aqui significaria a cena ainda
	# animando um mobo que o novo `start_game` já destruiu.
	farm_lanes = []
	farm_scores = []
	_farm_fired = []
	# REINICIAR no meio do farm: sem isto a flag sobrevivia à partida velha e o
	# `resume_after_farm` da partida nova rodava um brawl que ninguém pediu
	farm_pending = false
	for _side in Board.Side.PLAYER + 1:
		farm_lanes.append([])
		farm_scores.append(0)
		_farm_fired.append(false)

	# Terreno inicial na linha principal: 2 tiles aleatórias por lado.
	# Isso permite invocar criatura já no round 1, eliminando farm 0x0.
	for side in [Board.Side.PLAYER, Board.Side.AI]:
		var front := Board.front_row(side)
		var count := 2
		while count > 0:
			var col := rng.randi_range(0, Board.COLS - 1)
			var elements: Array[int] = [CardData.Element.WATER, CardData.Element.FIRE,
				CardData.Element.EARTH, CardData.Element.FROST, CardData.Element.SHADOW]
			var elem: int = elements[rng.randi_range(0, elements.size() - 1)]
			board.set_terrain(col, front, elem)
			count -= 1

	log_line("=== Tabuleiro pronto. %d × %d tiles, vitória em %d de dano. ===" % [
		Board.COLS, Board.ROWS, STARTING_HP])
	_begin_round()


# --- acessores -------------------------------------------------------------

func player() -> PlayerState:
	return players[Board.Side.PLAYER]


func opponent() -> PlayerState:
	return players[Board.Side.AI]


func side_of(p: PlayerState) -> int:
	return p.side


func other_side(side: int) -> int:
	return Board.Side.AI if side == Board.Side.PLAYER else Board.Side.PLAYER


func phase_label() -> String:
	return PHASE_LABEL[phase]


func is_player_turn() -> bool:
	return phase == Phase.PLAYER_BUILD


func is_over() -> bool:
	return phase == Phase.GAME_OVER


## A rodada atual é de farm? `round % Rules.FARM_EVERY == 0`. A HUD usa para
## avisar antes do turno do rival.
func is_farm_round() -> bool:
	return Rules.is_farm_round(round)


## A fila de mobs da trilha [lane] (um `Board.Side`). Vazio quando não houve
## fase ainda, ou depois que ela fechou.
func farm_mobs(lane: int) -> Array:
	if lane < 0 or lane >= farm_lanes.size():
		return []
	return farm_lanes[lane]


## Mobs destruídos por [side] na última fase de farm.
func farm_score(side: int) -> int:
	if side < 0 or side >= farm_scores.size():
		return 0
	return farm_scores[side]


# --- log -------------------------------------------------------------------

func log_line(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 200:
		log_lines.pop_front()
	logged.emit(text)
	print("[game] ", text)


# --- fluxo de turno --------------------------------------------------------

func _set_phase(new_phase: Phase) -> void:
	phase = new_phase
	phase_changed.emit(new_phase)
	state_changed.emit()


## Começa a rodada e PARA na fase de rolagem. Quem dispara a sorteada é
## [commit_roll]: no jogo é o clique no dado, no sim é a própria chamada. Sem
## essa separação a mana era sorteada dentro do mesmo `end_turn` e o jogador
## nunca via o dado — o número só aparecia como linha de log.
func _begin_round() -> void:
	if _check_victory():
		return
	log_line("── ROUND %d ──" % round)
	roll_pending = true
	_set_phase(Phase.ROLL)


## Compra e sorteia a mana, abrindo a rodada. Idempotente: chamar duas vezes no
## mesmo ROLL não rola de novo.
##
## A COMPRA vem ANTES da rolagem, e é obrigatória. Isso não é flavor: é o que
## impede o empate travado. Antes a mão só era completada até `HAND_SIZE`, e
## `while p.hand.size() < target` não executava com a mão cheia — o baralho
## nunca era tocado, `_reshuffle_discard` nunca rodava e as criaturas do
## descarte nunca voltavam. Chegava um estado sem nenhuma criatura no
## tabuleiro, e como todo dano vem de criatura (brawl na linha principal ou
## atrito), a vida dos dois ficava permanentemente imutável. Cerca de 1
## partida em 700 travava assim.
func commit_roll() -> void:
	if not roll_pending:
		return
	roll_pending = false

	_set_phase(Phase.DRAW)
	for p in players:
		if p.opening_done:
			# compra obrigatória de 1 carta
			draw_cards(p, 1)
		else:
			# primeira rodada de cada lado: mão inicial curta, e a partir
			# daqui a compra obrigatória passa a valer
			p.opening_done = true
			_draw_up(p, OPENING_HAND)
			# Garante pelo menos 1 criatura na mão inicial: sem isso a fase de
			# farm (round 3) fica vazia em ~47% das trilhas (1000 jogos).
			_ensure_opening_creature(p)
			log_line("%s comeca com %d carta(s)." % [p.display_name, p.hand.size()])
	hand_changed.emit()

	_set_phase(Phase.ROLL)
	for p in players:
		var carry := p.mana if MANA_CARRYOVER else 0
		var roll := 0
		for _i in MANA_DICE:
			roll += rng.randi_range(1, MANA_DIE_FACES)
		# Bônus de GELO da fase de farm: entra NESTA rolagem e é gasto aqui,
		# uma vez só. Depois do `carry` porque a spec é "+1 na próxima
		# rolagem", não "+1 em toda rolagem".
		var gel := p.pending_mana_bonus
		p.pending_mana_bonus = 0
		p.mana = mini(MANA_MAX, carry + roll + gel)
		p.mana_max = p.mana
		if MANA_CARRYOVER and carry > 0:
			log_line("%s rola %d de mana (+%d que sobrou = %d)." % [
				p.display_name, roll, carry, p.mana])
		else:
			log_line("%s rola %d de mana." % [p.display_name, p.mana])
		if gel > 0:
			log_line("  %s usa o bônus de GELO do farm: +%d nesta rolagem." % [
				p.display_name, gel])

	# SUA VEZ
	_set_phase(Phase.PLAYER_BUILD)
	log_line("Sua vez: jogue cartas, depois clique em Terminar Turno.")


## Enche a mão até [target]. Quando o deck acaba, o descarte volta para o
## baralho — sem isso a partida morre sozinha na metade do tempo.
func _draw_up(p: PlayerState, target: int) -> void:
	while p.hand.size() < target:
		if p.deck.is_empty():
			_reshuffle_discard(p)
			if p.deck.is_empty():
				return  # baralho e descarte vazios: não há mais o que dar
		p.hand.append(p.deck.pop_back())


## Garante pelo menos 1 criatura na mão inicial. Se não houver, substitui
## uma carta não-criatura por uma criatura do topo do baralho (ou baralha o
## descarte se necessário). Simples, sem mulligan complexo — só evita farm 0x0.
func _ensure_opening_creature(p: PlayerState) -> void:
	var has_creature := false
	for hid in p.hand:
		if CardDB.get_card(hid).is_creature():
			has_creature = true
			break
	if has_creature:
		return

	# Procura uma criatura no deck
	var creature_idx := -1
	for i in range(p.deck.size() - 1, -1, -1):
		if CardDB.get_card(p.deck[i]).is_creature():
			creature_idx = i
			break
	if creature_idx < 0:
		# Não tem criatura no deck — baralha descarte e tenta de novo
		_reshuffle_discard(p)
		for i in range(p.deck.size() - 1, -1, -1):
			if CardDB.get_card(p.deck[i]).is_creature():
				creature_idx = i
				break
	if creature_idx < 0:
		return  # sem criaturas no jogo todo (impossível no deck atual)

	# Troca a última carta da mão (aleatória o suficiente) pela criatura
	var replace_idx := p.hand.size() - 1
	var old_card := p.hand[replace_idx]
	p.hand[replace_idx] = p.deck[creature_idx]
	p.deck[creature_idx] = old_card
	log_line("%s garante criatura na mão inicial." % p.display_name)


func _reshuffle_discard(p: PlayerState) -> void:
	if p.discard.is_empty():
		return
	for id in p.discard:
		p.deck.append(id)
	p.discard.clear()
	p.shuffle_deck(rng)
	log_line("%s embaralha o descarte de volta no baralho." % p.display_name)


func draw_cards(p: PlayerState, amount: int) -> void:
	var before := p.hand.size()
	_draw_up(p, p.hand.size() + amount)
	var drawn := p.hand.size() - before
	if drawn > 0:
		log_line("%s compra %d carta(s)." % [p.display_name, drawn])
	else:
		log_line("%s não tem cartas para comprar." % p.display_name)


## O farm terminou e o brawl está esperando [resume_after_farm]. Só é verdade
## quando [end_turn] foi chamado com `auto_resume = false` numa rodada de farm.
var farm_pending: bool = false


## Avança a máquina: fase da IA → farm → brawl → atrito → próximo round.
##
## Por padrão roda tudo de forma síncrona — é o que o sim e o trace querem.
##
## A CENA passa `auto_resume = false`: numa rodada de farm, o turno PARA depois
## da fase de farm e fica esperando [resume_after_farm]. Sem essa pausa o
## jogador via tiros saindo de criaturas já mortas: o `end_turn` rodava o brawl
## no mesmo frame, a cena recebia o estado FINAL, e as criaturas que morrem no
## brawl sumiam antes de o projétil do farm ser sequer enfileirado. Fora de
## rodada de farm, `auto_resume` não muda nada: o turno completa inteiro.
func end_turn(auto_resume := true) -> void:
	if phase != Phase.PLAYER_BUILD:
		return
	cancel_pending_spell()
	_set_phase(Phase.AI_BUILD)
	log_line("A IA joga.")

	AiBrain.run(self, Board.Side.AI)
	state_changed.emit()

	if _check_victory():
		return

	# Aquecimento, a cada 3 rodadas. Nos outros rounds [Rules.is_farm_round]
	# é falso, [_run_farm] retorna na primeira linha e o caminho normal é
	# exatamente o de antes — nem entra uma chamada a mais no meio do brawl.
	_run_farm()
	# A fase de farm não causa dano em jogador nenhum (mobo não ataca de
	# volta), então não há o que checar aqui antes do brawl.

	if Rules.is_farm_round(round) and not auto_resume:
		farm_pending = true
		return
	_finish_turn()


## A cena avisa que terminou de tocar o farm: agora o brawl pode acontecer.
## Idempotente — chamar sem `farm_pending` não faz nada.
func resume_after_farm() -> void:
	if not farm_pending:
		return
	farm_pending = false
	_finish_turn()


## Do brawl em diante: brawl → atrito → próximo round.
func _finish_turn() -> void:
	_set_phase(Phase.BRAWL)
	_resolve_brawl()

	if _check_victory():
		return

	_set_phase(Phase.PUNISH)
	_apply_punishment()

	if _check_victory():
		return

	round += 1
	_begin_round()


## Entrada usada por [AiBrain]. Aplica uma jogada já planejada.
func apply_ai_action(action: Dictionary) -> void:
	apply_scripted_action(action, Board.Side.AI)


## Mesma coisa, mas para qualquer lado — é o que permite ao sim jogar
## dos dois lados e ao mesmo [AiBrain] servir como referência.
func apply_scripted_action(action: Dictionary, side: int) -> void:
	if action.is_empty() or is_over():
		return

	if action.get("type") == "discard":
		discard_from_hand(side, int(action.get("hand", -1)))
		return

	var p := players[side]
	var hand_index: int = action.get("hand", -1)
	if hand_index < 0 or hand_index >= p.hand.size():
		return
	var card := CardDB.get_card(p.hand[hand_index])

	if action.get("type") == "place":
		var col: int = action["col"]
		var row: int = action["row"]
		_place_card(p, hand_index, col, row)
		return

	# magia
	p.spend(card.cost)
	p.hand.remove_at(hand_index)
	if Rules.spell_needs_target(card):
		var tc: Vector2i = action.get("target", Vector2i(-1, -1))
		_resolve_spell_on_target(p, card, tc)
	else:
		_resolve_spell_no_target(p, card)


# --- ações do jogador ------------------------------------------------------

## Tenta jogar a carta da mão [hand_index] na tile [col]/[row].
## Devolve "" em sucesso, ou o motivo da falha.
func try_play_card(hand_index: int, col: int, row: int) -> String:
	if phase != Phase.PLAYER_BUILD:
		return "Não é a sua vez."
	var p := player()
	if hand_index < 0 or hand_index >= p.hand.size():
		return "Carta inválida."
	var card := CardDB.get_card(p.hand[hand_index])

	var reason := Rules.can_place(board, Board.Side.PLAYER, card, col, row)
	if reason != Rules.OK:
		return reason
	if not p.has_mana(card.cost):
		return "Mana insuficiente (custa %d, você tem %d)." % [card.cost, p.mana]

	_place_card(p, hand_index, col, row)
	state_changed.emit()
	hand_changed.emit()
	return Rules.OK


func _place_card(p: PlayerState, hand_index: int, col: int, row: int) -> void:
	var card := CardDB.get_card(p.hand[hand_index])
	p.spend(card.cost)
	p.hand.remove_at(hand_index)

	if card.kind == CardData.Kind.TERRAIN:
		# Terreno só pinta a tile — não ocupa, não vira entidade.
		var before: int = board.get_terrain(col, row)
		board.set_terrain(col, row, card.element)
		if before >= 0:
			log_line("%s repinta a tile (%d,%d): %s vira %s." % [
				p.display_name, col, row,
				CardData.ELEMENT_LABEL[before], card.element_text()])
		else:
			log_line("%s invoca %s em (%d,%d)." % [p.display_name, card.title, col, row])
		return

	var e := board.place(card, p.side, col, row, round)
	log_line("%s invoca %s%s em (%d,%d)." % [
		p.display_name,
		card.title,
		" [%s]" % card.stats_text() if card.is_creature() else "",
		col, row,
	])
	if card.is_creature() and USE_SUMMONING_SICKNESS and not e.is_ready(round):
		log_line("  %s não pode lutar neste round (invocação nova)." % card.title)


## Descarta uma carta da mão de graça. Existe para o jogador e a IA terem
## como se livrar de cartas que nunca poderão ser jogadas (terreno em tile já
## pintada, criatura sem elemento correspondente, etc.).
func discard_from_hand(side: int, hand_index: int) -> bool:
	if hand_index < 0 or hand_index >= players[side].hand.size():
		return false
	var card := CardDB.get_card(players[side].hand[hand_index])
	players[side].hand.remove_at(hand_index)
	players[side].discard.append(card.id)
	log_line("%s descarta %s." % [players[side].display_name, card.title])
	return true


## Inicia a resolução de uma magia da mão. Devolve "" ou o motivo.
func try_cast_spell(hand_index: int) -> String:
	if phase != Phase.PLAYER_BUILD:
		return "Não é a sua vez."
	var p := player()
	if hand_index < 0 or hand_index >= p.hand.size():
		return "Carta inválida."
	var card := CardDB.get_card(p.hand[hand_index])
	if not card.is_spell():
		return "Essa carta não é uma magia."
	if not p.has_mana(card.cost):
		return "Mana insuficiente (custa %d, você tem %d)." % [card.cost, p.mana]

	if Rules.spell_needs_target(card):
		if Rules.spell_targets(board, Board.Side.PLAYER, card).is_empty():
			return "Não há alvo válido para %s." % card.title
		pending_spell = hand_index
		log_line("Escolha o alvo de %s." % card.title)
	else:
		p.spend(card.cost)
		p.hand.remove_at(hand_index)
		_resolve_spell_no_target(p, card)
		state_changed.emit()
		hand_changed.emit()
	return Rules.OK


## Resolve a magia pendente no alvo [col]/[row]. Devolve "" ou o motivo.
func try_target_spell(col: int, row: int) -> String:
	if pending_spell < 0:
		return "Nenhuma magia em resolução."
	var p := player()
	var card := CardDB.get_card(p.hand[pending_spell])
	var valid := Rules.spell_targets(board, Board.Side.PLAYER, card).has(Vector2i(col, row))
	if not valid:
		return "Alvo inválido para %s." % card.title

	p.spend(card.cost)
	p.hand.remove_at(pending_spell)
	pending_spell = -1
	_resolve_spell_on_target(p, card, Vector2i(col, row))
	state_changed.emit()
	hand_changed.emit()
	return Rules.OK


func cancel_pending_spell() -> void:
	pending_spell = -1


# --- resolução de magias ---------------------------------------------------

func _resolve_spell_no_target(p: PlayerState, card: CardData) -> void:
	match card.spell:
		CardData.Spell.HEAL_PLAYER:
			var healed := p.heal(card.spell_value)
			log_line("%s usa %s e recupera %d de vida." % [p.display_name, card.title, healed])
		CardData.Spell.DRAW:
			draw_cards(p, card.spell_value)
		CardData.Spell.DAMAGE_PLAYER:
			_damage_player(other_side(p.side), card.spell_value, card.title)
		_:
			log_line("%s usa %s." % [p.display_name, card.title])


func _resolve_spell_on_target(p: PlayerState, card: CardData, target: Vector2i) -> void:
	var e := board.get_entity(target.x, target.y)
	if e == null:
		return
	var enemy_side := e.owner_side

	match card.spell:
		CardData.Spell.DAMAGE_CREATURE:
			e.take_damage(card.spell_value)
			log_line("%s lança %s: %d de dano em %s." % [
				p.display_name, card.title, card.spell_value, e.display_name()])
			_event("damage", {"col": target.x, "row": target.y, "amount": card.spell_value})
		CardData.Spell.DESTROY_CREATURE:
			e.take_damage(e.defense)
			log_line("%s lança %s e destrói %s." % [p.display_name, card.title, e.display_name()])
			_event("damage", {"col": target.x, "row": target.y, "amount": e.defense})
		CardData.Spell.BUFF_CREATURE:
			e.buff_attack(card.spell_value)
			log_line("%s lança %s: %s ganha +%d ATK." % [
				p.display_name, card.title, e.display_name(), card.spell_value])
			_event("buff", {"col": target.x, "row": target.y, "amount": card.spell_value})

	# limpa as mortes por magia
	for row in Board.ROWS:
		for col in Board.COLS:
			var dead := board.get_entity(col, row)
			if dead != null and dead.is_dead():
				log_line("%s é destruído." % dead.display_name())
				_event("death", {"col": col, "row": row})
				board.remove(col, row)


## Dano direto num jogador. Quando vem de uma CRIATURA (ataque direto, coluna
## sem defensor), [attacker] é ela: o evento leva a coluna e o elemento dela, e
## é o que permite à cena disparar o projétil do lugar certo e na cor certa.
## Magia não tem atacante no tabuleiro, então sai com `from_col = -1`.
func _damage_player(target_side: int, amount: int, source_name: String,
		attacker: BoardEntity = null) -> void:
	var victim := players[target_side]
	var applied := victim.take_damage(amount)
	log_line("%s causa %d de dano em %s (HP %d/%d)." % [
		source_name, applied, victim.display_name, victim.hp, victim.max_hp])
	var ev := {"side": target_side, "amount": applied, "source": source_name,
		"from_col": -1, "from_row": -1, "element": -1}
	if attacker != null:
		ev["from_col"] = attacker.col
		ev["from_row"] = attacker.row
		ev["element"] = int(attacker.card().element)
		# lado de quem atirou: é o oposto da vítima. A cena usa para achar o nó
		# da criatura sem depender de ler o tabuleiro.
		ev["from_side"] = attacker.owner_side
	_event("player_damage", ev)


# --- fase de farm ----------------------------------------------------------

## A fase de farm inteira, se a rodada for de farm. Roda entre o fim da jogada
## da IA e o brawl, porque é o aquecimento do confronto que vem logo depois.
##
## É totalmente síncrona, como o resto de [end_turn]: o ritmo é da cena, e sai
## tudo pela fila [_event]. Nenhum `await` aqui — a armadilha 1 dos invariantes
## (estado preso em `true` dentro de função com `await`) não tem onde pegar.
func _run_farm() -> void:
	if not Rules.is_farm_round(round):
		return
	_set_phase(Phase.FARM)
	_farm_open()

	# Os dois lados atiram depois que os dois construíram. Se o jogador atirasse
	# antes da IA construir, o placar da fase mediria duas coisas diferentes em
	# cada lado — e no sim, onde o `AiBrain` joga dos dois, isso viraria
	# vantagem do jogador por construção, não por jogada.
	for side in [Board.Side.PLAYER, Board.Side.AI]:
		commit_farm(side)

	_farm_walk()
	_farm_close()


## Sorteia e enfileira os mobs das duas trilhas.
func _farm_open() -> void:
	_event("farm_start", {})
	for side in [Board.Side.AI, Board.Side.PLAYER]:
		farm_lanes[side].clear()
		farm_scores[side] = 0
		_farm_fired[side] = false
	for side in [Board.Side.AI, Board.Side.PLAYER]:
		for i in Rules.FARM_MOBS_PER_LANE:
			var hp := rng.randi_range(Rules.FARM_MOB_HP_MIN, Rules.FARM_MOB_HP_MAX)
			var mob := FarmMob.new(side, i, hp)
			# `i` 0 é o da frente, e por isso o mais advanced: nasce mais longe
			# da entrada. É o que dá profundidade de fila para a cena sem
			# custar passo de caminhada extra.
			mob.x = float(Rules.FARM_MOBS_PER_LANE - 1 - i) * Rules.FARM_QUEUE_GAP
			farm_lanes[side].append(mob)
			_event("mob_spawned", {"lane": side, "i": i, "hp": hp})
			# `mob_spawned` não carrega `x` (contrato congelado), então o
			# primeiro `mob_moved` é o que diz à cena onde cada um nasceu.
			_event("mob_moved", {"lane": side, "i": i, "x": mob.x})
	log_line("FASE DE FARM: %d mobs na trilha de cada lado." % Rules.FARM_MOBS_PER_LANE)


## Tiros de [side]. Cada criatura da linha principal dele atira exatamente uma
## vez, no mobo da frente da trilha, com o ATK que tem no momento do tiro.
##
## Não é uma jogada que alguém escolhe: é consequência de ter criatura na linha
## principal. Por isso é idempotente por fase — a segunda chamada do mesmo lado
## não atira de novo, e é isso que deixa o [AiBrain] poder chamar esta rotina
## no meio do turno dela sem duplicar tiro nem entrar em laço.
##
## Devolve quantos mobs este lado destruiu.
func commit_farm(side: int) -> int:
	if not Rules.is_farm_round(round):
		return 0
	if side < 0 or side >= farm_lanes.size() or _farm_fired[side]:
		return 0
	var lane: Array = farm_lanes[side]
	if lane.is_empty():
		# A fase ainda não abriu — quem abre é [run_farm], no fim da jogada da
		# IA. É o caso normal quando o `AiBrain` chama daqui durante o
		# `AI_BUILD`: ele atira junto com todo mundo, um passo depois.
		return 0
	_farm_fired[side] = true

	# A SALVA: rodadas de tiro, e dentro de cada rodada uma criatura por coluna.
	# A ordem é "rodada 1 de todo mundo, depois rodada 2" (e não "3 tiros de
	# uma, depois 3 da outra") para a cena poder escalonar: o jogador vê as três
	# criaturas atirando juntas, em vez de uma metralhadora de cada vez.
	var shooters: Array = []
	for e: BoardEntity in board.front_line(side):
		if Rules.farm_shoots(e, round):
			shooters.append(e)

	var killed := 0
	for _shot in Rules.FARM_SHOTS_PER_CREATURE:
		for e: BoardEntity in shooters:
			var target := _farm_front_mob(lane)
			if target == null:
				return killed  # trilha limpa: não há mais em quem atirar
			var amount := maxi(0, e.attack)
			target.hp -= amount
			# `hp_left` sai travado em 0 quando o mobo morre: é o número que a
			# barra de vida da cena quer, e o excesso de dano fica no log.
			# `col` é a coluna da criatura que atirou: a cena precisa dela para
			# o projétil sair do lugar certo.
			_event("mob_hit", {"lane": side, "i": target.index,
				"amount": amount, "hp_left": maxi(target.hp, 0), "col": e.col})
			if target.hp <= 0:
				killed += 1
				farm_scores[side] += 1
				log_line("  %s [%s] abate o %s da frente (ATK %d)." % [
					e.display_name(), e.card().stats_text(), target.describe(), amount])
				_event("mob_killed", {"lane": side, "i": target.index})
			else:
				log_line("  %s [%s] acerta o %s (ATK %d, fica com %d de vida)." % [
					e.display_name(), e.card().stats_text(), target.describe(),
					amount, target.hp])
	return killed


## O mobo vivo mais advanced da [lane], ou null se ela estiver limpa.
## Ordena por `x` de verdade (e não assume `i`): o `x` é a verdade da trilha,
## e um dia a fila pode não sair toda no mesmo passo.
func _farm_front_mob(lane: Array) -> FarmMob:
	var front: FarmMob = null
	for mob: FarmMob in lane:
		if not mob.is_alive():
			continue
		if front == null or mob.x > front.x or (mob.x == front.x and mob.index < front.index):
			front = mob
	return front


## Os passos de caminhada. Quem sobreviveu anda; quem chega em
## [Rules.FARM_LANE_LENGTH] saiu da trilha e não conta como destruído.
func _farm_walk() -> void:
	for _tick in Rules.FARM_TICKS:
		for side in [Board.Side.AI, Board.Side.PLAYER]:
			for mob: FarmMob in farm_lanes[side]:
				if not mob.is_alive():
					continue
				mob.advance(Rules.FARM_MOB_STEP)
				_event("mob_moved", {"lane": side, "i": mob.index,
					"x": clampf(mob.x, 0.0, Rules.FARM_LANE_LENGTH)})
				if mob.x >= Rules.FARM_LANE_LENGTH:
					mob.escaped = true
					_event("mob_escaped", {"lane": side, "i": mob.index})


## Fecha a fase: placar, bônus de tabuleiro e recompensa por abates.
##
## O vencedor do farm recebe cura = mobs destruídos (1 HP por mob morto).
## Isso dá propósito ao placar, é intuitivo (matar cura) e não quebra
## a identidade dos bônus por elemento.
func _farm_close() -> void:
	var p_score: int = farm_scores[Board.Side.PLAYER]
	var a_score: int = farm_scores[Board.Side.AI]
	var winner := -1
	if p_score > a_score:
		winner = Board.Side.PLAYER
	elif a_score > p_score:
		winner = Board.Side.AI

	_event("farm_end", {"player_score": p_score, "ai_score": a_score, "winner": winner})
	log_line("Farm: %s %d x %s %d." % [
		players[Board.Side.PLAYER].display_name, p_score,
		players[Board.Side.AI].display_name, a_score])

	# Recompensa: 1 HP por mob destruído
	if p_score > 0:
		players[Board.Side.PLAYER].heal(p_score)
		_event("player_damage", {"side": Board.Side.PLAYER, "amount": -p_score, "source": "farm_reward"})
	if a_score > 0:
		players[Board.Side.AI].heal(a_score)
		_event("player_damage", {"side": Board.Side.AI, "amount": -a_score, "source": "farm_reward"})

	# Bônus por elemento (baseado no tabuleiro, não no placar)
	_grant_farm_bonus()


## Aplica o bônus de tabuleiro dos DOIS lados e avisa a cena. Um `bonus` por
## par (lado, elemento presente), na ordem do enum de elemento — o jogador
## primeiro, para a fase não ficar alternando a atenção entre as duas trilhas.
func _grant_farm_bonus() -> void:
	for side in [Board.Side.PLAYER, Board.Side.AI]:
		var p := players[side]
		for res: Dictionary in Rules.apply_farm_bonus(board, p, side):
			# O anúncio vem antes dos números nas criaturas: é a ordem que faz
			# sentido de ler.
			_event("bonus", {"side": side,
				"element": int(res["element"]), "count": int(res["count"]),
				"atk": int(res["atk"]), "def": int(res["def"]),
				"mana": int(res["mana"]), "heal": int(res["heal"])})

			var buffed: Array = res["buffed"]
			for e: BoardEntity in buffed:
				if int(res["atk"]) > 0:
					_event("buff", {"col": e.col, "row": e.row,
						"amount": int(res["atk"]), "stat": "atk"})
				if int(res["def"]) > 0:
					_event("buff", {"col": e.col, "row": e.row,
						"amount": int(res["def"]), "stat": "def"})

			var what := ""
			if int(res["atk"]) > 0:
				what += "+%d ATK em %d criatura(s)" % [int(res["atk"]), buffed.size()]
			if int(res["def"]) > 0:
				what += "%s+%d DEF em %d criatura(s)" % [
					" e " if what != "" else "", int(res["def"]), buffed.size()]
			if int(res["mana"]) > 0:
				what += "%s+%d de mana na próxima rolagem" % [" e " if what != "" else "", int(res["mana"])]
			if int(res["heal"]) > 0:
				what += "%scura %d de vida (HP %d/%d)" % [
					" e " if what != "" else "", int(res["heal"]), p.hp, p.max_hp]
			log_line("  Bônus %s de %s (%d em campo): %s." % [
				p.display_name,
				CardData.ELEMENT_LABEL[int(res["element"])],
				int(res["count"]), what])


# --- brawl e atrito --------------------------------------------------------

func _resolve_brawl() -> void:
	var duels := Rules.plan_brawl(board, round, USE_SUMMONING_SICKNESS)
	for d: Rules.Duel in duels:
		var line := Rules.describe_duel(d)
		if line != "":
			log_line(line)

	# dano direto no jogador (coluna sem defensor)
	for d: Rules.Duel in duels:
		if d.to_player_hp > 0:
			var atk: BoardEntity = d.defender
			log_line("  %s acerta VOCÊ por %d." % [atk.display_name(), d.to_player_hp])
			_damage_player(Board.Side.PLAYER, d.to_player_hp, atk.display_name(), atk)
		if d.to_ai_hp > 0:
			var atk: BoardEntity = d.attacker
			log_line("  %s acerta a IA por %d." % [atk.display_name(), d.to_ai_hp])
			_damage_player(Board.Side.AI, d.to_ai_hp, atk.display_name(), atk)

	if _check_victory():
		return

	# mortes simultâneas
	Rules.apply_duels(duels, Callable())
	for d: Rules.Duel in duels:
		# quem apanhou no confronto leva flash. O evento carrega também QUEM
		# bateu: sem isso a cena não tem como animar o avanço do atacante, e o
		# "avança livre" da regra continua sendo só uma frase de log.
		if d.attacker != null and d.defender != null:
			_event("damage", {"col": d.defender.col, "row": d.defender.row,
				"amount": d.player_dealt,
				"from_col": d.attacker.col, "from_row": d.attacker.row})
			_event("damage", {"col": d.attacker.col, "row": d.attacker.row,
				"amount": d.ai_dealt,
				"from_col": d.defender.col, "from_row": d.defender.row})
		for e: BoardEntity in d.deaths:
			log_line("%s [%s] cai (dano %d / DEF %d)." % [
				e.display_name(), e.card().stats_text(), e.damage_taken, e.defense])
			_event("death", {"col": e.col, "row": e.row})
			board.remove(e.col, e.row)


func _apply_punishment() -> void:
	if TURN_PUNISHMENT_DAMAGE <= 0:
		return
	var deaths: Array[BoardEntity] = []
	for row in Board.ROWS:
		for col in Board.COLS:
			var e := board.get_entity(col, row)
			if e == null or not e.card().is_creature():
				continue
			e.take_damage(TURN_PUNISHMENT_DAMAGE)
			_event("damage", {"col": col, "row": row, "amount": TURN_PUNISHMENT_DAMAGE})
			if e.is_dead():
				deaths.append(e)
	for e in deaths:
		log_line("%s [%s] sucumbe ao atrito (DEF %d)." % [
			e.display_name(), e.card().stats_text(), e.defense])
		_event("death", {"col": e.col, "row": e.row})
		board.remove(e.col, e.row)


func _check_victory() -> bool:
	for p in players:
		if p.is_dead():
			var winner := other_side(p.side)
			log_line("### %s venceu! %s ficou com %d de vida." % [
				players[winner].display_name, p.display_name, maxi(p.hp, 0)])
			_set_phase(Phase.GAME_OVER)
			finished.emit(winner)
			return true
	return false
