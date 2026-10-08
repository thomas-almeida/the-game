class_name Farm3D
extends Node3D

## A fase de farm em 3D: as duas trilhas, os mobs genericos andando nelas e os
## projeteis do ataque a distancia.
##
## Este no NAO le eventos. O `main_3d.gd` (orquestrador) consome a fila do
## `Game` e chama os metodos publicos daqui, um por evento do contrato
## congelado. Ver [start_farm], [spawn_mob], [move_mob], [shoot_at], [hit_mob],
## [kill_mob], [escape_mob], [end_farm] e [show_bonus].
##
## REGRA DE OURO: o `x` de `mob_moved` vem CALCULADO pela regra e e usado
##verbatim como X de mundo. A cena nao recalcula caminho, nao interpola fila e
## nao inventa posicao -- se ela recalculasse, a cena e a regra divergiriam.
## A unica coisa que a cena faz e suavizar o passo (duracao = distancia /
## velocidade), para o mobo andar sempre na mesma velocidade em vez de teleportar
## conforme a cadencia do evento.
##
## Geometria (espelhada em relacao a z=0, que e o meio do tabuleiro):
##   trilha do jogador: z = +3.95, embaixo, alem da linha 3, caminha +X
##   trilha do rival:   z = -3.95, em cima,  alem da linha 0, caminha -X
## A borda da laje do tabuleiro esta em z = +-2.825, entao sobra 0.35 de
## folga entre a laje e a borda interna da trilha (que esta em z = +-3.175).

## ------- geometria das trilhas (em unidades de mundo) -------

## Metade do comprimento da trilha: ela vai de -4.30 a +4.30 em X, contra
## +-2.105 do tabuleiro. Os mobs entram por uma ponta e saem pela outra.
const LANE_HALF_X := 4.30
## Largura (Z) da faixa. 1.55 contra 1.33 da tile: um pouco mais larga que
## uma tile, para a fila de 6 caber sem apertar.
const LANE_WIDTH := 1.55
const LANE_Z_PLAYER := 3.95
const LANE_Z_AI := -3.95
## Espacamento de referencia da fila. A REGRA e dona do `x`; este valor so
## documenta o que a cena espera para os mobs nao se sobreporem (o corpo do
## mobo tem 0.72 de largura).
const MOB_SPACING := 0.85
const MOB_COUNT := 6
## Altura do ponto de mira no corpo do mobo, usada pelo projetil.
const MOB_AIM_Y := 0.42

## ------- sinais (opcionais) -------
## Todos saouxILIARES: a cena funciona inteira sem ninguem conectado. O
## orquestrador usa o `impact` para tremer a camera e o `bonus_shown` para
## flutuar o numero do bonus.

## O tiro impactou. [amount] e o ATK que o gerou -- a camera pode tremer
## proporcional a ele.
signal impact(lane: int, i: int, amount: int, pos: Vector3)
## O tiro do ataque direto pousou no jogador. [shooter_side] e o dono da
## criatura (quem apanha e o outro); [pos] e o ponto de mundo do impacto.
signal point_impact(shooter_side: int, pos: Vector3, amount: int, element: int)
signal mob_died(lane: int, i: int, pos: Vector3)
signal mob_escaped(lane: int, i: int, pos: Vector3)
signal bonus_shown(side: int, atk: int, heal: int, pos: Vector3)
signal farm_finished(player_score: int, ai_score: int, winner: int)

## O `Board3D` da cena, so para achar a criatura que dispara. Frouxo: se for
## nulo, [shoot_at] ainda funciona, so que sem a animacao de ataque na
## criatura.
var board: Board3D = null
var active: bool = false

var _lanes: Dictionary = {}     ## lane -> Lane3D
var _mobs: Dictionary = {}      ## Vector2i(lane, i) -> Mob3D
var _in_flight: Dictionary = {} ## Vector2i(lane, i) -> true
var _placed: Dictionary = {}    ## Vector2i(lane, i) -> true: já recebeu a 1ª posição
var _pending: Dictionary = {}   ## Vector2i(lane, i) -> {amount, hp_left}
var _elems: Dictionary = {}     ## Vector2i(lane, i) -> elemento do ultimo tiro que pousou
var _bolts: Node3D
var _fx: Node3D
var _kills: Dictionary = {}
var _safety: Timer
## Tempo que um `mob_hit` espera o projetil pousar antes de se aplicar sozinho.
## Existe so para o feedback nunca ser perdido: se o projetil nao chegar, o dano
## aparece mesmo assim.
## Subiu de 0.75: o tiro de terra voa ate 0.84s (duracao x2), e se a espera
## vencesse antes dele pousar o dano apareceria duas vezes.
const PENDING_WAIT := 1.3


func _ready() -> void:
	if _lanes.is_empty():
		_build()
	set_process(false)


func _build() -> void:
	_bolts = Node3D.new()
	_bolts.name = "Bolts"
	add_child(_bolts)
	_fx = Node3D.new()
	_fx.name = "Fx"
	add_child(_fx)

	for side in [Board.Side.PLAYER, Board.Side.AI]:
		var lane := Lane3D.create(side, LANE_HALF_X, LANE_WIDTH)
		lane.position = Vector3(0, 0, lane_z(side))
		add_child(lane)
		_lanes[side] = lane
		_kills[side] = 0

	# Um Timer de verdade, e nao `await` numa funcao: com `await`, a retomada
	# roda numa copia da corrotina e o estado fica preso (armadilha 1).
	_safety = Timer.new()
	_safety.one_shot = true
	_safety.timeout.connect(_flush_pending)
	add_child(_safety)


# --- geometria -------------------------------------------------------------

## Z da trilha do lado. Os dois lados sao espelhados em relacao a z=0.
static func lane_z(side: int) -> float:
	return LANE_Z_PLAYER if side == Board.Side.PLAYER else LANE_Z_AI


## +1 na trilha do jogador (esquerda -> direita), -1 na do rival.
static func lane_dir(side: int) -> float:
	return Lane3D.dir_of(side)


## Posicao de mundo de um ponto da trilha. E o que o HUD usa para colocar o
## numero flutuante sem duplicar a conta de geometria.
func lane_position(side: int, x: float) -> Vector3:
	return Vector3(x, 0, lane_z(side))


## Onde o mobo [i] esta agora, ou o ponto de entrada da fila se ele ainda nao
## nasceu. Devolve `Vector3.ZERO` se o slot nao existe -- ai o HUD decide o
## que fazer com isso.
func mob_position(lane: int, i: int) -> Vector3:
	var m: Mob3D = _mobs.get(Vector2i(lane, i))
	if m != null and is_instance_valid(m):
		return m.global_position
	return Vector3.ZERO


func mob_count() -> int:
	return _mobs.size()


## O mobo já recebeu a posição inicial na fila? Falso entre o `mob_spawned` e o
## primeiro `mob_moved`. O orquestrador usa para não pagar pausa de caminhada
## no posicionamento inicial.
func is_placed(lane: int, i: int) -> bool:
	return _placed.has(Vector2i(lane, i))


func mob_hp(lane: int, i: int) -> int:
	var m: Mob3D = _mobs.get(Vector2i(lane, i))
	return m.hp if m != null and is_instance_valid(m) else -1


func lane_node(side: int) -> Lane3D:
	return _lanes.get(side)


func set_score_pips_visible(on: bool) -> void:
	for side in _lanes:
		(_lanes[side] as Lane3D).set_score_pips_visible(on)


# --- API publica (a que o orquestrador chama) ------------------------------

func setup(p_board: Board3D) -> void:
	board = p_board


## `farm_start`. Acende as duas trilhas e zera a contagem.
func start_farm() -> void:
	_clear_mobs()
	active = true
	for side in _lanes:
		var lane: Lane3D = _lanes[side]
		lane.set_active(true)
		lane.set_kills(0)
		_kills[side] = 0
		lane.flare(1.0, Lane3D.accent_of(side))
	set_process(true)


## `mob_spawned`. O mobo nasce já na trilha DO DONO (no `z` dela) e estufa com
## escala; a posição na fila chega no `mob_moved` seguinte, no mesmo frame.
##
## O `z` era 0: os mobs são filhos deste nó (na origem), e só o nó da trilha
## tem `z = ±3.95`. Sem setar aqui eles corriam pelo MEIO do tabuleiro.
func spawn_mob(lane: int, i: int, hp: int) -> void:
	var key := Vector2i(lane, i)
	var old: Mob3D = _mobs.get(key)
	if old != null and is_instance_valid(old):
		# respawn do mesmo slot: some com o anterior sem tocar no dicionario
		_mobs.erase(key)
		old.queue_free()
	var m := Mob3D.create(lane, i, hp)
	var dir := lane_dir(lane)
	m.position = Vector3(-dir * LANE_HALF_X, 0, lane_z(lane))
	add_child(m)
	_mobs[key] = m
	_placed.erase(key)
	_elems.erase(key)
	# entrada: o mobo estufa na trilha em vez de aparecer do nada
	m.scale = Vector3(0.3, 1.5, 0.3)
	var tw := m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3.ONE, 0.26) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## X de mundo para o `x` NORMALIZADO (0..1) que a regra emite.
##
## A regra não sabe onde a trilha fica na tela, de propósito: `x = 0` é a
## entrada da fila e `x = 1` a saída, e quem sabe o tamanho do mundo é a cena.
## Esta função é a única ponte. Antes a cena usava o `x` direto como unidade de
## mundo, e como ele só vai de 0 a 1, o mob andava no miolo do tabuleiro.
static func world_x(side: int, x: float) -> float:
	return lane_dir(side) * (-LANE_HALF_X + clampf(x, 0.0, 1.0) * LANE_HALF_X * 2.0)


## `mob_moved`. [x] é o valor NORMALIZADO da regra; ver [world_x].
##
## A PRIMEIRA posição de um mobo é um teleporte: ele já nasce na fila, e os
## tiros podem começar de imediato. Antes ele corria da ponta até o lugar dele
## enquanto os projéteis já estavam no ar, e mirava um alvo em movimento.
func move_mob(lane: int, i: int, x: float) -> void:
	var key := Vector2i(lane, i)
	var m: Mob3D = _mobs.get(key)
	if m == null or not is_instance_valid(m):
		return
	var wx := world_x(lane, x)
	if not _placed.has(key):
		_placed[key] = true
		m.position.x = wx
		FarmFx.shockwave(_fx, m.position + Vector3(0, 0.02, 0),
			Lane3D.accent_of(lane), 0.5, 0.32)
		return
	m.set_x(wx)


## Dispara a criatura [col] da linha principal de [lane] no mobo [i].
##
## NAO faz parte do contrato de eventos -- o contrato congelado nao tem evento
## de tiro. E opcional: se o orquestrador nao chamar isto, o `mob_hit` sozinho
## ja reage (o mobo pisca, empurra e abre a onda) e nada se perde. Chamar da
## e o que DA o tiro voando, que e o feedback central da fase.
##
## O alvo e lido frame a frame pelo projetil, entao da para chamar com o mobo
## ainda andando.
func shoot_at(lane: int, col: int, i: int, amount: int) -> void:
	var key := Vector2i(lane, i)
	var m: Mob3D = _mobs.get(key)
	if m == null or not is_instance_valid(m):
		return
	var from := Vector3(0, 1.0, 0)
	var color := Color("ffd88a")
	var element := -1
	var shooter := _shooter_node(lane, col)
	if shooter != null:
		shooter.shoot_at(m.aim_point())
		from = shooter.muzzle_position()
		color = shooter.bolt_color()
		element = _element_of(shooter)
	# se nao achou a criatura (ninguem no tabuleiro ainda), atira de uma borda
	# da trilha mesma -- melhor um tiro sem dono do que nenhum tiro
	if _bolts == null:
		return
	if _fx != null:
		FarmFx.muzzle(_fx, from, m.aim_point() - from, element, amount)
	var b := Projectile3D.launch(_bolts, from, m, m.aim_point(), amount, color,
		element)
	_in_flight[key] = true
	b.landed.connect(_on_bolt_landed.bind(key, amount, element))


## Elemento da criatura que atira, lido da carta do no. -1 se nao for criatura.
func _element_of(shooter: Entity3D) -> int:
	if shooter == null or shooter.entity == null:
		return -1
	var card := shooter.entity.card()
	if card == null or not card.is_creature():
		return -1
	return int(card.element)


func _shooter_node(lane: int, col: int) -> Entity3D:
	if board == null or not is_instance_valid(board):
		return null
	return board.entity_node(col, Board.front_row(lane))


## Dispara a criatura da coluna [col] da linha principal de [shooter_side]
## contra um PONTO do mundo (o jogador, nao um mob da trilha). E o ataque
## direto: coluna sem defensor, a criatura bate na vida de quem apanha.
##
## O [target] fica perto de um canto da tela, onde o HUD desenha por cima do 3D,
## entao o impacto sai em versao "grande" (ver `FarmFx.impact`). [element] vem
## do evento `player_damage`; se vier invalido, usa o da criatura que atira.
func shoot_at_point(shooter_side: int, col: int, target: Vector3,
		amount: int, element: int) -> void:
	if _bolts == null:
		return
	# sem criatura: sai de uma borda do lado do atirador, melhor um tiro sem
	# dono que nenhum
	var from := Vector3(0, 1.0, lane_z(shooter_side))
	var color := Color("ffd88a")
	var shooter := _shooter_node(shooter_side, col)
	if shooter != null:
		shooter.shoot_at(target)
		from = shooter.muzzle_position()
		color = shooter.bolt_color()
		if not FarmFx.has_style(element):
			element = _element_of(shooter)
	if _fx != null:
		FarmFx.muzzle(_fx, from, target - from, element, amount)
	var b := Projectile3D.launch(_bolts, from, null, target, amount, color, element)
	b.landed.connect(_on_point_landed.bind(shooter_side, amount, element))


func _on_point_landed(where: Vector3, shooter_side: int, amount: int,
		element: int) -> void:
	FarmFx.impact(_fx, where, element, amount, true)
	point_impact.emit(shooter_side, where, amount, element)


## Um tiro de CADA elemento, lado a lado, so para conferir a aparencia. Nao
## depende de criatura nem de mobo: os cinco saem em paralelo de [origin] para
## [target], espalhados no eixo perpendicular ao voo.
func demo_gallery(origin: Vector3, target: Vector3) -> void:
	if _bolts == null:
		return
	var along := target - origin
	var side := along.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 0.0001 else Vector3.RIGHT
	var elements := [CardData.Element.FIRE, CardData.Element.WATER,
		CardData.Element.EARTH, CardData.Element.FROST, CardData.Element.SHADOW]
	for i in elements.size():
		var e: int = elements[i]
		var off := side * (float(i) - 2.0) * 0.7
		var from := origin + off
		var to := target + off
		FarmFx.muzzle(_fx, from, to - from, e, 3)
		var b := Projectile3D.launch(_bolts, from, null, to, 3,
			FarmFx.pal(e, FarmFx.P_MID), e)
		b.landed.connect(_on_gallery_landed.bind(e))


func _on_gallery_landed(where: Vector3, element: int) -> void:
	FarmFx.impact(_fx, where, element, 3)


## `mob_hit`. [amount] e o ATK do tiro e [hp_left] e a vida que sobrou.
##
## Se ha projetil no ar em direcao a este mobo, o impacto ESPERA o tiro pousar
## -- senao o numero/onda apareceria antes da explosao, e o tiro chegaria
## depois de tudo ja ter acontecido. A espera tem prazo: se o projetil nunca
## chegar, o dano e aplicado assim mesmo.
func hit_mob(lane: int, i: int, amount: int, hp_left: int) -> void:
	var key := Vector2i(lane, i)
	var m: Mob3D = _mobs.get(key)
	if m == null or not is_instance_valid(m):
		return
	if _in_flight.has(key):
		_pending[key] = {"amount": amount, "hp_left": hp_left}
		_safety.start(PENDING_WAIT)
		return
	_apply_hit(key, amount, hp_left)


## O primeiro parâmetro é `where`, que o sinal `landed(where)` emite: `bind()`
## acrescenta `key` e `amount` DEPOIS dos argumentos do sinal, então a função
## recebe 3 e antes declarava só 2 — erro "expected 2 argument(s), but called
## with 3" a cada tiro, e o impacto nunca era aplicado.
##
## [element] e o do tiro que pousou: o impacto de cada elemento e diferente, e o
## `_apply_hit` le o ultimo que pousou no slot (`_elems`).
func _on_bolt_landed(where: Vector3, key: Vector2i, amount: int,
		element: int) -> void:
	_in_flight.erase(key)
	_elems[key] = element
	var gone: Mob3D = _mobs.get(key)
	if gone == null or not is_instance_valid(gone):
		# o tiro de terra e lento: o mobo pode ja ter morrido. O impacto
		# acontece mesmo assim, no ponto onde o tiro chegou.
		if element >= 0:
			FarmFx.impact(_fx, where, element, amount)
		return
	if _pending.has(key):
		var p: Dictionary = _pending[key]
		_pending.erase(key)
		_apply_hit(key, int(p["amount"]), int(p["hp_left"]))
		return
	# O `mob_hit` nunca chegou (a regra resolv o tiro e a fila presentation nao
	# o viu). O impacto ainda acontece, com o dano do lancamento -- nunca
	# agora sem feedback nenhum.
	var m: Mob3D = _mobs.get(key)
	if m != null and is_instance_valid(m):
		_apply_hit(key, amount, maxi(m.hp - amount, 0))


func _flush_pending() -> void:
	if _pending.is_empty():
		return
	for key in _pending.keys():
		var p: Dictionary = _pending[key]
		_in_flight.erase(key)
		_apply_hit(key, int(p["amount"]), int(p["hp_left"]))
	_pending.clear()


func _apply_hit(key: Vector2i, amount: int, hp_left: int) -> void:
	var m: Mob3D = _mobs.get(key)
	if m == null or not is_instance_valid(m):
		return
	m.hit(amount, hp_left)
	var at := m.aim_point()
	var accent := Lane3D.accent_of(key.x)
	var heat := Color("ffb066").lerp(Color("ff5a4a"), clampf(float(amount) / 6.0, 0.0, 1.0))
	var element: int = _elems.get(key, -1)
	# tudo abaixo escala com o ATK: onda maior, mais estilhaco, clarao maior
	if FarmFx.has_style(element):
		# o impacto proprio do elemento substitui clarao + estilhaco; a onda
		# no chao fica, tingida pelo elemento, para marcar a trilha
		FarmFx.shockwave(_fx, m.marker_position(),
			FarmFx.pal(element, FarmFx.P_MID), 0.26 + 0.10 * float(amount))
		FarmFx.impact(_fx, at, element, amount)
	else:
		FarmFx.shockwave(_fx, m.marker_position(), heat, 0.30 + 0.13 * float(amount))
		FarmFx.flash(_fx, at, heat, 0.30 + 0.10 * float(amount))
		FarmFx.debris(_fx, at, Color(accent.r, accent.g, accent.b).lerp(heat, 0.5),
			4 + 2 * amount, 1.4 + 0.35 * float(amount))
	impact.emit(key.x, key.y, amount, at)
	# rede de seguranca: se a regra mandar `mob_hit` com 0 e nenhum
	# `mob_killed`, o mobo morre sozinho meio segundo depois. `kill()` e
	# idempotente, entao quando o `mob_killed` chegar nao acontece duas vezes.
	if hp_left <= 0:
		_auto_kill(key)


func _auto_kill(key: Vector2i) -> void:
	var tw := create_tween()
	tw.tween_interval(0.45)
	tw.tween_callback(_kill_if_alive.bind(key))


func _kill_if_alive(key: Vector2i) -> void:
	var m: Mob3D = _mobs.get(key)
	if m != null and is_instance_valid(m) and m.alive:
		kill_mob(key.x, key.y)


## `mob_killed`. A chave sai do dicionario ANTES do no se liberar: e o
## inverso da armadilha 6, e por isso que um `mob_moved` atrasado nao encontra
## um objeto destruido.
func kill_mob(lane: int, i: int) -> void:
	var key := Vector2i(lane, i)
	var m: Mob3D = _mobs.get(key)
	if m == null or not is_instance_valid(m):
		return
	_mobs.erase(key)
	_in_flight.erase(key)
	_pending.erase(key)
	m.kill()
	_kills[lane] = int(_kills.get(lane, 0)) + 1
	var lane_node: Lane3D = _lanes.get(lane)
	if lane_node:
		lane_node.set_kills(int(_kills[lane]))
	var at := m.marker_position()
	var accent := Lane3D.accent_of(lane)
	FarmFx.pillar(_fx, at, accent, 1.7)
	FarmFx.shockwave(_fx, at, accent, 1.0, 0.5)
	FarmFx.debris(_fx, m.aim_point(), accent, 14, 2.6, 0.75)
	FarmFx.flash(_fx, m.aim_point(), Color(1, 1, 1), 0.8, 0.28)
	mob_died.emit(lane, i, at)


## `mob_escaped`. Nao houve morte: o mobo atravessou. Sai desbotado.
func escape_mob(lane: int, i: int) -> void:
	var key := Vector2i(lane, i)
	var m: Mob3D = _mobs.get(key)
	if m == null or not is_instance_valid(m):
		return
	_mobs.erase(key)
	_in_flight.erase(key)
	_pending.erase(key)
	var at := m.marker_position()
	m.escape()
	mob_escaped.emit(lane, i, at)


## `farm_end`. [winner] e o lado vencedor, ou -1 no empate (e no empate nao ha
## bônus para ninguem -- ver `context/fase-de-farm.md`).
func end_farm(player_score: int, ai_score: int, winner: int) -> void:
	active = false
	set_process(false)
	for side in _lanes:
		var lane: Lane3D = _lanes[side]
		lane.set_active(false)
		if side == winner:
			lane.flare(1.2, Lane3D.accent_of(side))
		else:
			lane.flare(0.35)
	farm_finished.emit(player_score, ai_score, winner)


## `bonus`. Aplica o premio na cena: acende a trilha do ganhador e faz as
## criaturas da linha principal desse lado pulsarem. O numero em si e da HUD
## (o `bonus_shown` leva a posicao de mundo para ela ancorar).
func show_bonus(side: int, atk: int, heal: int) -> void:
	var accent := Lane3D.accent_of(side)
	var lane: Lane3D = _lanes.get(side)
	if lane:
		lane.flare(1.0, accent)
	if board != null and is_instance_valid(board):
		board.pulse_side(side, Color("8fffb0"))
	var at := lane_position(side, 0.0) + Vector3(0, 1.4, 0)
	FarmFx.pillar(_fx, lane_position(side, 0.0), accent, 2.4, 0.9)
	bonus_shown.emit(side, atk, heal, at)


## Limpa tudo: chama no REINICIAR. Sem isso os mobs da partida velha ficam
## na tela, exatamente como os `Entity3D` velhos ficavam.
func reset() -> void:
	_clear_mobs()
	active = false
	_pending.clear()
	_in_flight.clear()
	if _safety:
		_safety.stop()
	for side in _lanes:
		var lane: Lane3D = _lanes[side]
		lane.set_active(false)
		lane.set_kills(0)
		_kills[side] = 0
	set_process(false)


func _clear_mobs() -> void:
	for key in _mobs.keys():
		var m: Mob3D = _mobs[key]
		if m != null and is_instance_valid(m):
			m.queue_free()
	_mobs.clear()
	_placed.clear()
	_elems.clear()
	if _bolts:
		for c in _bolts.get_children():
			c.queue_free()
	if _fx:
		for c2 in _fx.get_children():
			c2.queue_free()