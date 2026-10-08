extends Node3D

## Raiz da cena 3D: câmera, luzes, tabuleiro, as duas mãos e o HUD.
## Toda a entrada do jogador passa por aqui — nada de colisão 3D, o picking é
## por posição do ponteiro (mais perto para cartas, raycast no chão para tiles),
## que é mais barato e mais fácil de acertar numa câmera inclinada.

const CAM_POS := Vector3(0, 10.2, 10.2)
## Era (0, -0.2, -1.0), enquadrado só para o tabuleiro. Com as duas trilhas
## (z = ±3.95) a cena inteira passa a ocupar ~480px de altura e ficava
## deslocada para baixo: a trilha do jogador encostava nos botões e sobravam
## ~100px vazios no topo. Mirar 0.6 mais perto do jogador sobe tudo e centra.
const CAM_LOOK := Vector3(0, -0.2, -0.4)

## Posições do dado em espaço de mundo. A mão do jogador ocupa o canto
## inferior direito, então o dado dele fica embaixo à ESQUERDA — é o único
## canto livre da tela. O do rival fica em cima à esquerda, espelhado.
const DIE_PLAYER_POS := Vector3(6.3, 0.72, 4.6)
## O do rival desceu de z=-5.5 para -4.7: com a câmera reenquadrada ele subiu
## e ficava com o topo metido atrás do painel do rival (que termina em y=135).
const DIE_AI_POS := Vector3(9.0, 0.72, -4.7)
## Raio de clique em pixels na tela, para pegar o dado sem colisão 3D.
const DIE_CLICK_RADIUS := 46.0

## A mão do jogador vive no espaço da câmera: assim ela fica sempre enquadrada
## e em proporção constante, independente de como a câmera é ajustada.
## A distância precisa ser grande o bastante para a carta não preencher a tela
## (≈9.6) e o deslocamento vertical pequeno o bastante para caber no frustum.
const HAND_OFFSET := Vector3(0.0, -2.15, -8.80)
const HAND_SPAN := 5.2

const AI_HAND_POS := Vector3(0, 2.05, -5.9)
const AI_HAND_SPAN := 4.4

var _rig: Node3D
var _camera: Camera3D
var _board: Board3D
var _hand: HandView
var _ai_hand: HandView
var _layer: CanvasLayer
var _hud: CanvasLayer
var _faces: Node

var _selected: int = -1
var _hover_tile: Vector2i = Vector2i(-1, -1)
## fila de efeitos: um evento por vez, com pausa no meio
var _fx_queue: Array = []
var _fx_busy: bool = false
var _fx_timer: Timer
var _ending_turn: bool = false
## Geração da partida/presentation. Incrementada no REINICIAR para invalidar
## qualquer `_on_end_turn` suspenso num `await`.
var _turn_generation: int = 0
var _dice_pending: bool = false
var _die: Die3D
var _ai_die: Die3D
var _farm: Farm3D

## Pausa entre dois eventos da fila. 0.34s é o suficiente para o número subir e
## a tile piscar sem deixar a partida arrastada.
const FX_GAP := 0.34

## Pausas da fase de farm. Valores separados do `FX_GAP` porque o farm tem
## ~100 eventos e a 0.34 cada ele duraria meio minuto: o ritmo da fase é o que
## decide se ela é "dopaminérgica" ou uma espera.
## Entre dois tiros da salva: curto, para as salvas parecerem rajadas.
const FARM_SHOT_GAP := 0.11
## Depois de um abate: um respiro a mais, é o momento de recompensa.
const FARM_KILL_GAP := 0.18
## Entre dois passos da fila andando.
const FARM_STEP_GAP := 0.42
## Entre dois disparos de ataque direto. Os tiros se sobrepõem de propósito: o
## voo dura ~0.4s e a pausa é menor, então as criaturas atiram em rajada.
const PLAYER_SHOT_GAP := 0.22



func _ready() -> void:
	_build_world()
	_build_scene()
	_build_hands()
	_build_fx_timer()
	_connect()
	Game.start_game()
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("0b0a12")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("6d7ba8")
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)

	# luz principal, de cima e de frente: dá volume às lajes
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 28, 0)
	sun.light_energy = 1.25
	sun.light_color = Color("fff0d8")
	sun.shadow_enabled = true
	add_child(sun)

	# luz de recorte, do lado oposto: separa a silhueta do fundo
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-18, -140, 0)
	rim.light_energy = 0.55
	rim.light_color = Color("7f9ede")
	rim.shadow_enabled = false
	add_child(rim)


func _build_scene() -> void:
	_rig = Node3D.new()
	add_child(_rig)

	_camera = Camera3D.new()
	_camera.fov = 44.0
	# near/far com razão pequena: nada na cena passa de ~30 unidades, e um near
	# de 0.1 destrói a precisão do buffer de profundidade (z-fighting nas faces)
	_camera.near = 1.0
	_camera.far = 60.0
	_rig.add_child(_camera)
	_camera.look_at_from_position(CAM_POS, CAM_LOOK, Vector3.UP)
	_camera.make_current()

	_board = Board3D.new()
	add_child(_board)
	_board.setup(_camera)

	# As duas trilhas da fase de farm, fora do tabuleiro. A cena não lê eventos:
	# este arquivo consome a fila e chama a API dela (ver `_fx_apply`).
	_farm = Farm3D.new()
	add_child(_farm)
	_farm.setup(_board)
	# o impacto do tiro sacode a câmera na proporção do dano: um tiro de 5 tem
	# que pesar mais que um de 1
	_farm.impact.connect(func(_lane: int, _i: int, amount: int, _pos: Vector3) -> void:
		_hud.shake_camera(_rig, clampf(0.04 + 0.02 * float(amount), 0.05, 0.18)))
	# o disparo do ataque direto no jogador chegou
	_farm.point_impact.connect(_on_point_impact)

	_build_dice()

	# hospeda os SubViewports das faces de carta (precisa estar na árvore)
	_faces = Node.new()
	_faces.name = "CardFaces"
	add_child(_faces)
	CardFace.init(_faces)

	_hud = load("res://scripts/view/hud.gd").new()
	add_child(_hud)
	_hud.setup(_camera)


## As duas mãos são desenhadas em 2D com projeção 3D calculada em GDScript
## (ver [HandView]). A do jogador fica no canto inferior direito, espalhando
## para a esquerda; a da IA, no topo, virada para baixo.
func _build_hands() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)

	# Mão da IA: em cima, virada para baixo. Sem hover (o baralho dela é
	# virado, não há o que ler) — por isso `HandView` desliga o tilt nela.
	_ai_hand = HandView.new(true)
	_ai_hand.setup(Vector2(0.47, 0.125), 0.40)
	_ai_hand.base_pitch = 0.22
	_ai_hand.card_scale = 0.66
	_layer.add_child(_ai_hand)

	# Mão do jogador: canto inferior direito. `base_pitch` baixo = cartas em pé;
	# o padrão da classe já é esse, então não precisa repetir aqui (foi
	# exatamente um override assim que anulava a mudança no `hand_view.gd`).
	_hand = HandView.new(false)
	_hand.setup(Vector2(0.80, 0.74), 0.28)
	_layer.add_child(_hand)


func _connect() -> void:
	Game.state_changed.connect(_sync)
	Game.hand_changed.connect(_sync)
	Game.logged.connect(_hud.log_game_line)
	Game.phase_changed.connect(_on_phase_changed)
	Game.finished.connect(_on_finished)
	_hud._turn_button.pressed.connect(_on_end_turn)
	_hud._new_button.pressed.connect(func() -> void:
		# Invalida qualquer apresentação em andamento. O `_on_end_turn` fica
		# suspenso num `await` durante o turno do rival; sem esta geração, ele
		# voltava depois do restart e chamava `Game.end_turn()` na partida
		# NOVA, corrompendo o estado. Desabilitar o botão não resolve: a
		# corrotina já está fora.
		_turn_generation += 1
		_ending_turn = false
		_selected = -1
		_hover_tile = Vector2i(-1, -1)
		_hud.clear_log()
		_hud.clear_card_info()
		# antes do `start_game`: ele emite `phase_changed(ROLL)` e repõe a dica
		# "CLIQUE NO DADO". Chamar depois apagaria o aviso da partida nova.
		_hud.reset_session()
		# a cena precisa ser limpa ANTES do novo jogo: o `start_game` troca o
		# `Board` por outro objeto e os slimes antigos ficariam órfãos na tela
		_board.reset()
		_farm.reset()
		_hud.clear_farm()
		# REINICIAR no meio do farm: a mão podia ficar apagada para sempre
		_hand.modulate.a = 1.0
		_fx_queue.clear()
		_fx_busy = false
		_dice_pending = false
		Game.start_game()
		_sync())
	_board.tile_clicked.connect(_on_tile_clicked)


## Cada fase da rodada vira um evento visível. Sem isso a partida inteira
## acontecia num único frame: a IA jogava, o brawl resolvia e a vida caía,
## tudo antes de o jogador ver qualquer coisa.
func _on_phase_changed(phase: int) -> void:
	match phase:
		Game.Phase.ROLL:
			# A rodada parou esperando o clique no dado. Quem sorteia é o
			# jogador: o dado fica clicável e o resto da tela travado.
			if not _ending_turn:
				_hud.show_dice_prompt()
		Game.Phase.AI_BUILD, Game.Phase.BRAWL, Game.Phase.PUNISH:
			# `_on_end_turn` já anuncia o rival com respiro; aqui só sincroniza
			_hud.set_turn(Board.Side.AI)
		Game.Phase.PLAYER_BUILD:
			_hud.set_turn(Board.Side.PLAYER)


## Os dois dados ficam nos cantos, fora do tabuleiro: o do jogador embaixo à
## direita (clicável), o do rival em cima à direita (rola sozinho). Estavam no
## meio da tela e cobriam as criaturas justamente quando o jogador precisa ler
## o resultado da luta.
func _build_dice() -> void:
	_die = Die3D.create(true)
	add_child(_die)
	_die.position = DIE_PLAYER_POS

	_ai_die = Die3D.create(false)
	add_child(_ai_die)
	_ai_die.position = DIE_AI_POS
	_ai_die.rotation_degrees = Vector3(0, 180, 0)


func _build_fx_timer() -> void:
	_fx_timer = Timer.new()
	_fx_timer.one_shot = true
	_fx_timer.timeout.connect(_on_fx_timer_done)
	add_child(_fx_timer)


func _on_resize() -> void:
	var s := get_viewport().get_visible_rect().size
	_hud.set_viewport_size(s)
	_layout_hands(s)


func _layout_hands(_s: Vector2) -> void:
	# a HandView trabalha em proporção da tela, então nada a reposicionar
	pass


# --- sincronização com o estado -------------------------------------------

func _sync() -> void:
	var events := Game.take_events()

	_board.sync(Game, events)
	_hand.set_cards(Game.player().hand)
	_ai_hand.set_cards(Game.opponent().hand)
	_hand.set_selected(_selected)

	var affordable: Array = []
	for i in Game.player().hand.size():
		var card := CardDB.get_card(Game.player().hand[i])
		if Game.player().has_mana(card.cost):
			affordable.append(i)
	_hand.set_playable(affordable)
	_ai_hand.set_selected(-1)

	# Os eventos entram numa fila tocada com intervalo, em vez de todos no mesmo
	# frame. O estado já mudou quando eles chegam — a IA jogou de uma vez — mas
	# tocar um por vez é o que dá a sensação de sequência.
	for ev in events:
		_fx_queue.append(ev)
	_pump_fx()
	_sync_selection_state()


## Toca um evento por vez com pausa no meio. A recarga é um `Timer` de verdade
## e não um `await` dentro da função: com `await`, cada retomada roda numa
## cópia da corrotina, o `_fx_busy` ficava preso em `true` para sempre e a
## fila drenava sem nunca devolver o controle.
func _pump_fx() -> void:
	# Laço, não um evento por chamada: eventos com pausa 0 (nascimento de mob,
	# movimentos simultâneos) precisam seguir no mesmo frame, senão uma fase de
	# farm com ~100 eventos levaria mais de 30 segundos a 0.34s cada.
	while not _fx_busy and not _fx_queue.is_empty():
		_fx_busy = true
		var ev: Dictionary = _fx_queue.pop_front()
		var gap := _fx_apply(ev)
		if gap <= 0.0:
			_fx_busy = false
			continue
		# `Timer.start(0)` reaproveita o wait_time anterior, não vale 0 — por
		# isso o caminho de pausa zero fica no `continue` acima e nunca chega aqui
		_fx_timer.start(gap)


## Aplica o efeito de UM evento e devolve quanto tempo esperar antes do
## próximo. 0 = próximo no mesmo frame.
func _fx_apply(ev: Dictionary) -> float:
	var kind: String = ev.get("type", "")
	match kind:
		"damage":
			var p := _board_pos(ev["col"], ev["row"]) + Vector3(0, 1.15, 0)
			_hud.float_number(p, "-%d" % ev["amount"], Color("ff7b6b"))
			_hud.shake_camera(_rig, 0.16)
			_board.pulse(ev["col"], ev["row"], Color("ff6b4b"))
			return FX_GAP
		"buff":
			var pb := _board_pos(ev["col"], ev["row"]) + Vector3(0, 1.15, 0)
			_hud.float_number(pb, "+%d" % ev["amount"], Color("9dffb0"), 22)
			_board.pulse(ev["col"], ev["row"], Color("8fffb0"))
			return FX_GAP
		"death":
			_hud.shake_camera(_rig, 0.12)
			return FX_GAP
		"player_damage":
			var from_col: int = ev.get("from_col", -1)
			if from_col >= 0:
				# ATAQUE DIRETO: a criatura dispara no jogador. O disparo voa
				# até o painel de vida de quem apanha, e o efeito de dano
				# (piscar, número, tremor) acontece no IMPACTO, em
				# [_on_point_impact] — não aqui, senão o número apareceria
				# antes do tiro chegar.
				var victim: int = ev["side"]
				_farm.shoot_at_point(ev.get("from_side", Game.other_side(victim)),
					from_col, _hp_target_world(victim), ev["amount"],
					ev.get("element", -1))
				return PLAYER_SHOT_GAP
			# sem atacante no tabuleiro (magia): efeito imediato, como antes
			_apply_player_hit(ev["side"], ev["amount"], Vector3.ZERO)
			return FX_GAP

		# --- fase de farm -------------------------------------------------
		"farm_start":
			# A mão fica no canto inferior direito, exatamente onde a trilha do
			# jogador TERMINA: os mobs passavam por baixo das cartas na parte
			# final do caminho. Durante o farm ela não é usável mesmo (o turno
			# está travado), então apaga em vez de brigar por espaço.
			_dim_hand(0.14)
			_farm.start_farm()
			_hud.farm_begin(Rules.FARM_MOBS_PER_LANE)
			# curto: os mobs já nascem na fila e as criaturas podem atirar de
			# imediato. 0.9s aqui era espera pura antes do primeiro tiro.
			return 0.30
		"mob_spawned":
			_farm.spawn_mob(ev["lane"], ev["i"], ev["hp"])
			_hud.farm_mob_spawned(ev["lane"], ev["i"], ev["hp"])
			return 0.0
		"mob_moved":
			# A PRIMEIRA posição do mobo é o posicionamento inicial da fila, não
			# um passo de caminhada: sem pausa nenhuma. `_farm_move_gap` só vale
			# para passos de verdade — antes todo `mob_moved` pagava 0.42s
			# porque o evento seguinte era um `mob_spawned`, e os 12 mobs
			# apareciam um a um em ~5 segundos em vez de todos de uma vez.
			var first := not _farm.is_placed(ev["lane"], ev["i"])
			_farm.move_mob(ev["lane"], ev["i"], ev["x"])
			if first:
				return 0.0
			return _farm_move_gap(ev)
		"mob_hit":
			var lane: int = ev["lane"]
			var i: int = ev["i"]
			var amt: int = ev["amount"]
			# o tiro sai da coluna da criatura que atirou. `col` pode faltar
			# (contrato antigo): a cena trata -1 sem animar o atirador.
			_farm.shoot_at(lane, ev.get("col", -1), i, amt)
			_farm.hit_mob(lane, i, amt, ev["hp_left"])
			_hud.farm_mob_hit(lane, i, amt, ev["hp_left"], _farm.mob_position(lane, i))
			# pausa curta: o jogador precisa ver as salvas saindo uma a uma,
			# mas 0.34 (a pausa do brawl) deixaria a fase arrastada
			return FARM_SHOT_GAP
		"mob_killed":
			_farm.kill_mob(ev["lane"], ev["i"])
			_hud.farm_mob_killed(ev["lane"], ev["i"])
			return FARM_KILL_GAP
		"mob_escaped":
			_farm.escape_mob(ev["lane"], ev["i"])
			_hud.farm_mob_escaped(ev["lane"], ev["i"])
			return 0.0
		"farm_end":
			_farm.end_farm(ev["player_score"], ev["ai_score"], ev["winner"])
			_hud.farm_end(ev["player_score"], ev["ai_score"], ev["winner"])
			return 1.1
		"bonus":
			_farm.show_bonus(ev["side"], ev["atk"], ev["heal"])
			_hud.farm_bonus(ev["side"], ev["atk"], ev["heal"],
				"%s x%d" % [CardData.ELEMENT_LABEL.get(ev["element"], "?"), ev["count"]])
			return 0.55
	return FX_GAP


## Ponto do MUNDO para onde voa o disparo de ataque direto em [side].
##
## O jogador não existe no mundo 3D, é um painel de HUD. O alvo é o ponto de
## tela logo abaixo desse painel (`Hud.hp_anchor`), levado ao mundo na
## profundidade do centro do tabuleiro. Assim o tiro atravessa a cena até o
## canto onde a vida de quem apanha está desenhada.
func _hp_target_world(side: int) -> Vector3:
	var depth := (CAM_POS - CAM_LOOK).length()
	return _camera.project_position(_hud.hp_anchor(side), depth)


## O disparo do ataque direto chegou: aí sim o jogador sente o golpe.
func _on_point_impact(shooter_side: int, pos: Vector3, amount: int, _element: int) -> void:
	_apply_player_hit(Game.other_side(shooter_side), amount, pos)


## Efeito de dano num jogador. [at] é o ponto do impacto no mundo, ou ZERO
## quando não há tiro (magia): aí o número sobe da posição de sempre.
func _apply_player_hit(side: int, amount: int, at: Vector3) -> void:
	_hud.on_side_damaged(side)
	var pos := at
	if pos == Vector3.ZERO:
		pos = Vector3(0, -1.4, 6.2) if side == Board.Side.PLAYER \
			else Vector3(0, 2.0, -6.4)
	_hud.float_number(pos, "-%d" % amount, Color("ff7b6b"), 34)
	# o tremor cresce com o golpe: 1 de dano mal mexe, 5 sacode
	_hud.shake_camera(_rig, clampf(0.10 + 0.05 * float(amount), 0.12, 0.40))


## Escurece ou devolve a mão do jogador. Tween no próprio nó: se o nó sair de
## cena o tween morre junto, em vez de escrever num objeto destruído.
func _dim_hand(alpha: float) -> void:
	if _hand == null:
		return
	var tw := _hand.create_tween()
	tw.tween_property(_hand, "modulate:a", alpha, 0.25)


## Pausa depois de um `mob_moved`. Os movimentos de um mesmo passo da fila
## chegam em sequência (lado da IA, depois o do jogador, `i` crescendo), então
## pausa 0 entre eles faz a fila andar JUNTA. Só vale pausa quando o próximo
## `mob_moved` recomeça a contagem: é a fronteira entre dois passos.
func _farm_move_gap(ev: Dictionary) -> float:
	if _fx_queue.is_empty():
		return FARM_STEP_GAP
	var nxt: Dictionary = _fx_queue[0]
	if nxt.get("type", "") != "mob_moved":
		return FARM_STEP_GAP
	var here: int = int(ev["lane"]) * 100 + int(ev["i"])
	var there: int = int(nxt["lane"]) * 100 + int(nxt["i"])
	return 0.0 if there > here else FARM_STEP_GAP


## Só para o teste automatizado: dispara o próximo evento imediatamente.
func _on_fx_timer_done() -> void:
	_fx_busy = false
	_pump_fx()


## O realce das tiles e o estado do botão são sincronizados AQUI, uma vez por
## `_sync`. Dentro de `_fx_one` eles eram reavaliados a cada evento da fila,
## no meio da apresentação — o botão destravava e a vez voltava a parecer sua
## enquanto o jogo ainda estava mostrando o dano do rival.
func _sync_selection_state() -> void:
	_board.set_highlights(_selected_card(), Game.pending_spell, Game)
	_refresh_buttons()


func _selected_card() -> CardData:
	if _selected < 0 or _selected >= Game.player().hand.size():
		return null
	return CardDB.get_card(Game.player().hand[_selected])


func _board_pos(col: int, row: int) -> Vector3:
	return Vector3(
		(col - (Board.COLS - 1) * 0.5) * Board3D.TILE_X,
		0,
		(row - (Board.ROWS - 1) * 0.5) * Board3D.TILE_Z)


func _refresh_buttons() -> void:
	# `_ending_turn` manda: durante a apresentação o jogador não pode Acting,
	# mesmo que a fase do Game já tenha voltado para PLAYER_BUILD. Sem este
	# teste o botão destravava no meio da animação e reiniciava o turno.
	if _ending_turn:
		_hud.set_input_locked(true)
		return
	# esperando a rolagem o botão não é "TURNO DO RIVAL": é o dado que libera
	# a rodada, e um botão que diz a coisa errada é pior que nenhum.
	if Game.roll_pending:
		_hud.set_input_locked(true)
		_hud._turn_button.text = "ROLE O DADO"
		return
	var mine := Game.is_player_turn()
	_hud.set_input_locked(not mine)
	if mine:
		_hud._turn_button.text = "TERMINAR TURNO"


# --- entrada ---------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_clear_selection()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			# o dado tem prioridade absoluta: enquanto a rodada espera a
			# rolagem, nenhum outro clique faz sentido
			if _die_at(mb.position) <= DIE_CLICK_RADIUS:
				_roll_dice()
				return
			# carta primeiro: a mão tem prioridade sobre o tabuleiro
			var idx := _hand.pick(mb.position)
			if idx >= 0:
				_on_card_clicked(idx)
			else:
				var t := _tile_under_mouse()
				if t.x >= 0:
					_on_tile_clicked(t.x, t.y)
				elif _selected >= 0:
					# clique fora da mao e do tabuleiro so desmarca
					_clear_selection()


## Distância em pixels entre o ponteiro e o dado do jogador, ou um número
## enorme se ele não puder ser clicado agora.
func _die_at(mouse: Vector2) -> float:
	if _die == null or _camera == null:
		return INF
	if not Game.roll_pending or _die.rolling or _ending_turn:
		return INF
	if _camera.is_position_behind(_die.global_position):
		return INF
	return mouse.distance_to(_camera.unproject_position(_die.global_position))


## O clique no dado é o que dispara a sorteada: o `Game` rola, e a animação é
## só a consequência visível do número que ele já escolheu. O dado do rival
## gira junto, sem clique — ele é rolado "por baixo dos panos".
func _roll_dice() -> void:
	if not Game.roll_pending or _ending_turn:
		return
	_ending_turn = true
	_hud.clear_transients()
	_hud.set_input_locked(true)

	Game.commit_roll()
	_die.roll_to(Game.player().mana)
	_ai_die.roll_to(Game.opponent().mana)
	_sync()

	# espera a rolagem terminar em frames, não em segundos: o renderizador roda
	# a uma taxa imprevisível
	var frames := int(Die3D.ROLL_TIME * 60.0) + 6
	for i in frames:
		await get_tree().process_frame

	_hud.announce_turn(Board.Side.PLAYER, 1.0)
	_hud.set_input_locked(false)
	_ending_turn = false


func _tile_under_mouse() -> Vector2i:
	var mouse := get_viewport().get_mouse_position()
	var origin := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	if absf(dir.y) < 0.0001:
		return Vector2i(-1, -1)
	var t := (0.0 - origin.y) / dir.y
	if t < 0.0:
		return Vector2i(-1, -1)
	var hit := origin + dir * t

	var col := int(round(hit.x / Board3D.TILE_X + (Board.COLS - 1) * 0.5))
	var row := int(round(hit.z / Board3D.TILE_Z + (Board.ROWS - 1) * 0.5))
	if col < 0 or col >= Board.COLS or row < 0 or row >= Board.ROWS:
		return Vector2i(-1, -1)
	# fora da laje? descarta
	if absf(hit.x - _board_pos(col, row).x) > Board3D.TILE_X * 0.5:
		return Vector2i(-1, -1)
	if absf(hit.z - _board_pos(col, row).z) > Board3D.TILE_Z * 0.5:
		return Vector2i(-1, -1)
	return Vector2i(col, row)


func _process(_delta: float) -> void:
	# recalcula a área das mãos todo frame: no primeiro frame da cena
	# `get_visible_rect()` ainda devolve zero e as cartas ficam empilhadas
	# no canto da tela
	_layout_hands(get_viewport().get_visible_rect().size)

	# hover de tile para o realce sutil
	var t := _tile_under_mouse()
	if t != _hover_tile:
		var old := _hover_tile
		_hover_tile = t
		var a := _board.tile_at(old.x, old.y)
		if a:
			a.set_hovered(false)
		var b := _board.tile_at(t.x, t.y)
		if b:
			b.set_hovered(true)


func _on_card_clicked(index: int) -> void:
	if not Game.is_player_turn():
		return
	# o índice pode ter vindo do hover, que fica um frame defasado quando a mão
	# encolhe no mesmo instante do clique
	if index < 0 or index >= Game.player().hand.size():
		return
	if _selected == index:
		_clear_selection()
		return

	var card := CardDB.get_card(Game.player().hand[index])

	# Magia resolve na hora e não abre modal: o jogador já sabe o que ela faz
	# naquele momento, e abrir um painel no meio da jogada atrapalha.
	if card.is_spell():
		_clear_selection()
		var err := Game.try_cast_spell(index)
		if err != Rules.OK:
			_hud.float_number(Vector3(0, -1.0, 5.0), UiKit.fold(err), Color("ff9d9d"), 16)
			return
		if Game.pending_spell == index:
			_hud.show_banner("ESCOLHA O ALVO")
		_sync()
		return

	_selected = index
	_hand.set_selected(index)
	_board.set_highlights(card, -1, Game)
	# Nada de modal aqui: o clique na carta seleciona, e a regra vai para a
	# faixa do canto. O próximo passo (clicar na tile) é o que invoca.
	_hud.show_card_info(card)
	_hud.show_banner(card.title)


func _on_tile_clicked(col: int, row: int) -> void:
	if not Game.is_player_turn():
		return

	if Game.pending_spell >= 0:
		var err := Game.try_target_spell(col, row)
		if err != Rules.OK:
			_hud.float_number(_board_pos(col, row) + Vector3(0, 1.4, 0),
				UiKit.fold(err), Color("ff9d9d"), 15)
			return
		_clear_selection()
		_sync()
		return

	if _selected < 0:
		return

	var card := _selected_card()
	if card == null:
		return

	var err2 := Game.try_play_card(_selected, col, row)
	if err2 != Rules.OK:
		_hud.float_number(_board_pos(col, row) + Vector3(0, 1.4, 0),
			UiKit.fold(err2), Color("ff9d9d"), 15)
		return

	if Game.player().mana <= 0:
		_clear_selection()
	_sync()


func _clear_selection() -> void:
	_selected = -1
	Game.cancel_pending_spell()
	_hand.set_selected(-1)
	_board.set_highlights(null, -1, Game)
	_hud.clear_card_info()


func _on_end_turn() -> void:
	_clear_selection()
	if _ending_turn:
		return
	_ending_turn = true
	# Esta função fica suspensa em vários `await`. Se o jogador apertar
	# REINICIAR nesse meio-tempo, ela volta e age sobre a partida NOVA. A
	# geração é o que impede: o REINICIAR incrementa, e aqui tudo que é
	# irreversível aborta se ela mudou. Desabilitar o botão não resolvia, porque
	# a corrotina já estava fora quando ele foi clicado.
	var gen := _turn_generation
	# O turno inteiro acontece dentro de `Game.end_turn`: a IA joga, o brawl
	# resolve e a rodada nova começa, tudo no mesmo frame. Sem este respiro o
	# jogador não distingue nada disso. A ordem importa: primeiro o dado e a
	# faixa da rodada anterior saem de cena, só então o turno do rival é
	# anunciado — senão o "TURNO DO RIVAL" nasce já com 0.9s e some antes de
	# o jogador olhar.
	_hud.clear_transients()
	_hud.announce_turn(Board.Side.AI, 1.3)
	_hud.set_input_locked(true)
	await get_tree().create_timer(1.3).timeout
	if gen != _turn_generation:
		return

	# `false`: numa rodada de farm o turno PARA depois do farm e espera este
	# arquivo tocar tudo. Fora do farm o turno completa inteiro, como antes.
	Game.end_turn(false)
	_sync()

	# espera a fila de efeitos tocar antes de devolver o controle
	if not await _drain_fx(gen):
		return

	# Rodada de farm: os tiros já foram vistos, agora o brawl acontece. Só neste
	# ponto as criaturas que morrem nele saem da tela — antes disso o jogador via
	# o projétil partir de uma criatura que já tinha sumido.
	if Game.farm_pending:
		# o farm acabou: a mão volta antes da luta
		_dim_hand(1.0)
		# um respiro entre o aquecimento e a luta: é a virada do ritmo
		await get_tree().create_timer(0.5).timeout
		if gen != _turn_generation:
			return
		Game.resume_after_farm()
		_sync()
		if not await _drain_fx(gen):
			return

	# A rodada nova parou em ROLL esperando o clique no dado. Não é para
	# destravar: a mana ainda nem foi sorteada, e é o clique que dispara.
	# `_refresh_buttons` é quem escreve "ROLE O DADO" — chamar
	# `set_input_locked` aqui deixaria "TURNO DO RIVAL...", que é mentira.
	_hud.show_dice_prompt()
	_ending_turn = false
	_refresh_buttons()


## Espera a fila de efeitos esvaziar. Devolve false se a apresentação foi
## invalidada no meio (REINICIAR), e quem chamou deve abortar.
##
## Sem teto de iterações o laço poderia girar para sempre se um evento prendesse
## a fila; 600 x 0.05s = 30s é bem mais que a fase de farm mais longa.
func _drain_fx(gen: int) -> bool:
	var guard := 0
	while (_fx_busy or not _fx_queue.is_empty()) and guard < 600:
		guard += 1
		await get_tree().create_timer(0.05).timeout
		if gen != _turn_generation:
			return false
	return gen == _turn_generation


func _on_finished(winner_side: int) -> void:
	_hud.show_banner("%s VENCEU!" % Game.players[winner_side].display_name)
