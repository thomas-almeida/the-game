class_name Mob3D
extends Node3D

## Um mob generico da fase de farm: o alvo descartavel, nao uma criatura do
## jogador.
##
## A identidade vem de ser OBJETIVAMENTE outra coisa: arte de goblin (o kit de
## rogue, vista de LADO, andando em perfil) em vez de slime (o pacote
## `slime-mobs`, de cima, sempre virado para a camera); silhueta de duas
## pernas com arma em vez de uma borrao sem pernas; menor que a criatura do
## dono; e sem tint de elemento -- as criaturas sao tingidas pela cor do
## elemento e These nao tem elemento nenhum.
##
## A cor tambem ajuda: [_base_tint] apaga um pouco a saturacao do goblin. A
## regra do jogo e "tudo que e colorido no tabuleiro e seu"; um mob cinza e
## um alvo, um mob tingido seria mais uma criatura sua.

## O mobo é um SLIME GENÉRICO, do mesmo pacote `slime-mobs` das criaturas, mas
## SEM tint de elemento e só com o primeiro modelo. Era um goblin do kit antigo
## (folhas de 32px); por enquanto vale um slime neutro, que fica coerente com o
## resto da cena e já se lê como "alvo" por ser cinza.
const FRAME := 64

## Quantos frames tem cada folha, medido no PNG (largura / 64):
## Idle 384, Walk 512, Hurt 320, Death 640.
const FRAMES := {"Idle": 6, "Walk": 8, "Hurt": 5, "Death": 10}
const FPS := {"Idle": 6.0, "Walk": 10.0, "Hurt": 12.0, "Death": 12.0}

## Um modelo só, o Slime1. A `CardDB.slime_sheet` aceita 1..3 e a variedade
## entre mobs pode voltar depois trocando esta lista.
const VARIANTS := [1]

## O quadro é 64x64, mas o CORPO do slime ocupa só ~19x22 pixels dentro dele
## (medido no PNG, y=20..41). Com pixel_size 0.033 o corpo sai com 0.63 de
## largura e 0.72 de altura: cabe com folga no espaçamento da fila (0.86) e é
## menor que a criatura do tabuleiro (~1.0), o que já diz "alvo".
const PIXEL := 0.033

## Distância do centro do quadro até o chão. Os pés estão em y=41 e o centro do
## quadro em y=32: 9px abaixo, ou 9 * 0.033 = 0.30.
const FOOT := 0.30

## Velocidade visual da caminhada. O `x` do mob vem da REGRA (evento
## `mob_moved`) e a duracao do passo e distancia/velocidade -- assim o mobo
## anda sempre na MESMA velocidade, nao importa de quanto em quanto tempo a
## regra emite o evento.
const SPEED := 3.2

const PIP_MAX := 6
const PIP_SPACING := 0.13
const PIP_Y := 0.98
const PIP_SIZE := 0.115

## Mobs sao moeda moeda: apagados de proposito, para a unica coisa colorida na
## tela ser a criatura do dono.
const BASE_TINT := Color(0.74, 0.74, 0.80)

var side: int = Board.Side.PLAYER
var index: int = 0
var hp: int = 1
var max_hp: int = 1
var alive: bool = true

var _variant: int = 2
var _atlas: AtlasTexture
var _sprite: Sprite3D
var _body: Node3D
var _shadow: MeshInstance3D
var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D
var _pips_root: Node3D
var _pips: Array[MeshInstance3D] = []

var _action: String = "Idle"
var _frame: int = 0
var _acc: float = 0.0
var _looping: bool = true
var _flash: float = 0.0
var _dying: bool = false
var _gone: bool = false
var _walking: bool = false
var _bob: float = 0.0
var _move_tween: Tween
var _react_tween: Tween

static var _sheets: Dictionary = {}


static func sheet_path(variant: int, action: String) -> String:
	return CardDB.slime_sheet(variant, action)


## Folha base (a textura inteira). O ATLAS nao e compartilhado: cada mobo cria
## o seu, porque a `region` muda frame a frame e um atlas unico faria os seis
## andarem em sincronia.
static func sheet(variant: int, action: String) -> Texture2D:
	var key := "%d:%s" % [variant, action]
	if _sheets.has(key):
		return _sheets[key]
	# `CardDB.art` e so um cache de `load()`. Aqui so se le esse cache; nada
	# em `card_db.gd` (arquivo do agente de mecanicas) e tocado.
	var t := CardDB.art(sheet_path(variant, action))
	_sheets[key] = t
	return t


static func create(p_side: int, p_index: int, p_hp: int) -> Mob3D:
	var n := Mob3D.new()
	n.side = p_side
	n.index = p_index
	n.hp = clampi(p_hp, 1, PIP_MAX)
	n.max_hp = n.hp
	return n


func _ready() -> void:
	# Variante pelo indice: a fila tem variedade sem virar aleatoriedade, e o
	# mobo 0 da trilha e sempre o mesmo desenho.
	_variant = VARIANTS[posmod(index, VARIANTS.size())]
	_atlas = AtlasTexture.new()
	_atlas.atlas = sheet(_variant, "Idle")
	_atlas.region = Rect2(0, 0, float(FRAME), float(FRAME))
	_build()
	_apply_frame()
	_set_hp(hp, false)
	set_process(true)


func _build() -> void:
	var accent := Lane3D.accent_of(side)
	var away := 1.0 if side == Board.Side.PLAYER else -1.0

	# --- sombra: elipse achatada. Sem ela o goblin parece flutuar acima da
	# trilha, e e a sombra que gruda o sprite no chao.
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0, 0, 0, 0.45)
	var sq := QuadMesh.new()
	sq.size = Vector2(0.52, 0.24)
	_shadow = MeshInstance3D.new()
	_shadow.mesh = sq
	_shadow.material_override = sm
	_shadow.rotation_degrees = Vector3(-90, 0, 0)
	_shadow.position = Vector3(0, 0.035, 0)
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)

	# --- marcador de alvo: um anel na cor do dono, no chao. E o que gruda o
	# mobo na trilha E diz que ele esta na lista, sem texto nenhum.
	_marker_mat = FarmFx.glow_mat(FarmFx.ring_tex(),
		Color(accent.r, accent.g, accent.b, 0.42), true)
	_marker = MeshInstance3D.new()
	var mq := QuadMesh.new()
	mq.size = Vector2(0.72, 0.72)
	_marker.mesh = mq
	_marker.material_override = _marker_mat
	_marker.rotation_degrees = Vector3(-90, 0, 0)
	_marker.position = Vector3(0, 0.03, 0)
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marker)

	# --- corpo. E um no separado porque e ele que tomba e que sacode no dano:
	# o pivi fica no chao, entao a pArte de cima e que cai, nao o sprite
	# flutuando.
	_body = Node3D.new()
	add_child(_body)

	_sprite = Sprite3D.new()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sprite.shaded = false
	_sprite.double_sided = true
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.pixel_size = PIXEL
	_sprite.texture = _atlas
	_sprite.position = Vector3(0, FOOT, 0)
	_sprite.render_priority = 1
	# `ALPHA_CUT_DISABLED` (e nao DISCARD) porque o fade da morte precisa do
	# canal alpha: com DISCARD, `modulate:a` nao faz nada.
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	_sprite.modulate = BASE_TINT
	# O goblin do PNG olha para a direita. A trilha do jogador caminha para a
	# direita, a do rival para a esquerda -- entao so a do rival espelha.
	_sprite.flip_h = away < 0.0
	_body.add_child(_sprite)

	_build_pips()


func _build_pips() -> void:
	_pips_root = Node3D.new()
	_pips_root.position = Vector3(0, PIP_Y, 0)
	add_child(_pips_root)
	var start := -PIP_SPACING * (PIP_MAX - 1) * 0.5
	for k in PIP_MAX:
		var pip := FarmFx.billboard_quad(PIP_SIZE, FarmFx.soft_dot(),
			Color.WHITE, false)
		pip.position = Vector3(start + PIP_SPACING * float(k), 0, 0)
		_pips_root.add_child(pip)
		_pips.append(pip)


# --- caminhada ------------------------------------------------------------

## O `x` ja vem calculado pela regra. A cena nao recalcula caminho nenhum: ela
## so persegue o valor, com duracao proporcional a distancia para o passo ter
## velocidade constante.
func set_x(x: float) -> void:
	if _dying or _gone:
		return
	var dx := x - position.x
	if absf(dx) < 0.0005:
		return
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position:x", x,
		clampf(absf(dx) / SPEED, 0.06, 1.5)).set_trans(Tween.TRANS_LINEAR)
	_move_tween.tween_callback(_on_step_done)
	_walking = true
	_set_action("Walk")


func _on_step_done() -> void:
	_walking = false
	_move_tween = null
	if not _dying and not _gone and alive:
		_set_action("Idle")


func _stop_move() -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = null
	_walking = false


# --- dano e morte ----------------------------------------------------------

## Leva [amount] de dano e fica com [hp_left] de vida. Tudo aqui escala com
## [amount]: o empurrao, o baque e o brilho. E o que faz um tiro de 6 pesar
## mais que um de 2 sem precisar de numero nenhum na tela.
func hit(amount: int, hp_left: int) -> void:
	if _dying or _gone:
		return
	_flash = clampf(0.45 + 0.11 * float(amount), 0.45, 1.15)
	_set_hp(hp_left, true)
	_set_action("Hurt", false)
	if _react_tween != null and _react_tween.is_valid():
		_react_tween.kill()
	_react_tween = create_tween()
	_react_tween.set_parallel(true)
	# empurrao para longe do tabuleiro: a trilha esta fora dele
	var away := 1.0 if side == Board.Side.PLAYER else -1.0
	var push := 0.06 + 0.035 * float(amount)
	_react_tween.tween_property(self, "position:z", position.z + away * push,
		0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_react_tween.tween_property(self, "position:z", position.z, 0.24) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var kick := 0.05 + 0.022 * float(amount)
	_react_tween.tween_property(_body, "scale",
		Vector3(1.0 + kick, 1.0 - kick * 0.6, 1.0 + kick), 0.07) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_react_tween.tween_property(_body, "scale", Vector3.ONE, 0.26) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_react_tween.chain().tween_callback(_on_react_done)


func _on_react_done() -> void:
	_react_tween = null
	if _dying or _gone or not alive:
		return
	_set_action("Walk" if _walking else "Idle")


func kill() -> void:
	if _dying or _gone:
		return
	_dying = true
	alive = false
	_stop_move()
	# mata o tween de reacao ANTES de trocar de estado: ele escreve em
	# `position:z` e em `_body`, e o `_flash` ainda esta ativo.
	if _react_tween != null and _react_tween.is_valid():
		_react_tween.kill()
	_react_tween = null
	_flash = 1.15
	_set_action("Death", false)


## A folha `S_Death` tem 8 frames e ja e uma queda de verdade: o goblin
## cambaleia, tomba, se achata e some. Depois dela o resto e so apagar o
## que sobrou no chao -- tombar de novo seria dobrar a animacao.
func _finish_death() -> void:
	if _gone:
		return
	_gone = true
	set_process(false)
	_set_hp(0, false)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_body, "position:y", -0.30, 0.44) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_sprite, "modulate:a", 0.0, 0.44)
	tw.tween_property(_shadow, "scale", Vector3.ONE * 0.25, 0.40)
	tw.tween_property(_marker_mat, "albedo_color", Color(1, 1, 1, 0.0), 0.6)
	tw.tween_property(_pips_root, "scale", Vector3.ZERO, 0.22)
	tw.chain().tween_callback(queue_free)


## Atravessou a linha de chegada: nao morreu, foi embora. Sai desbotado, para
## nao parecer que foi morto.
func escape() -> void:
	if _gone or _dying:
		return
	alive = false
	_gone = true
	_stop_move()
	set_process(false)
	if _react_tween != null and _react_tween.is_valid():
		_react_tween.kill()
	_react_tween = null
	var away := 1.0 if side == Board.Side.PLAYER else -1.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "position:x", position.x + away * 1.1, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(_sprite, "modulate", Color(0.5, 0.5, 0.58, 0.0), 0.55)
	tw.tween_property(_marker_mat, "albedo_color", Color(1, 1, 1, 0.0), 0.5)
	tw.tween_property(_pips_root, "scale", Vector3.ZERO, 0.3)
	tw.chain().tween_callback(queue_free)


func _set_hp(new_hp: int, animate := true) -> void:
	hp = clampi(new_hp, 0, PIP_MAX)
	var ratio := float(hp) / float(maxi(1, max_hp))
	var col := Color("7fe08a")
	if ratio <= 0.34:
		col = Color("f2614f")
	elif ratio <= 0.67:
		col = Color("f0c04a")
	for k in _pips.size():
		var pip := _pips[k]
		var on := k < hp
		if on:
			if not pip.visible:
				pip.visible = true
				pip.scale = Vector3.ONE
			(pip.material_override as StandardMaterial3D).albedo_color = col
		elif pip.visible:
			if animate:
				var t := pip.create_tween()
				t.tween_property(pip, "scale", Vector3.ONE * 2.6, 0.16) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				t.tween_callback(_hide_pip.bind(pip))
			else:
				pip.visible = false


static func _hide_pip(pip: MeshInstance3D) -> void:
	if not is_instance_valid(pip):
		return
	pip.visible = false
	pip.scale = Vector3.ONE


## Ponto de mira no chao, para o projetil acertar o meio do corpo.
func aim_point() -> Vector3:
	return global_position + Vector3(0, FOOT * 2.0, 0)


func marker_position() -> Vector3:
	return global_position + Vector3(0, 0.03, 0)


# --- animacao --------------------------------------------------------------

func _set_action(action: String, loop := true) -> void:
	if _gone or _action == action:
		return
	_action = action
	_looping = loop
	_frame = 0
	_acc = 0.0
	_atlas.atlas = sheet(_variant, action)
	_apply_frame()


func _apply_frame() -> void:
	if _atlas == null:
		return
	var count := int(FRAMES.get(_action, 4))
	_frame = clampi(_frame, 0, count - 1)
	_atlas.region = Rect2(float(_frame * FRAME), 0.0, float(FRAME), float(FRAME))


func _process(delta: float) -> void:
	_tick_anim(delta)

	if _walking:
		_bob += delta * 9.0
		_sprite.position.y = FOOT + absf(sin(_bob)) * 0.055
	elif _sprite != null:
		_sprite.position.y = lerpf(_sprite.position.y, FOOT, delta * 9.0)

	if _flash <= 0.0:
		return
	_flash = maxf(0.0, _flash - delta * 4.5)
	var w := Color(1, 1, 1).lerp(Color(3.2, 2.4, 2.2), minf(_flash, 1.0))
	_sprite.modulate = Color(
		BASE_TINT.r * w.r, BASE_TINT.g * w.g, BASE_TINT.b * w.b,
		_sprite.modulate.a)


func _tick_anim(delta: float) -> void:
	if _atlas == null:
		return
	var count := int(FRAMES.get(_action, 4))
	_acc += delta * float(FPS.get(_action, 8.0))
	while _acc >= 1.0:
		_acc -= 1.0
		_frame += 1
		if _frame < count:
			_apply_frame()
			continue
		if _looping:
			_frame = 0
			_apply_frame()
			continue
		# uma vez so: trava no ultimo frame e avisa. O callback PRECISA ser
		# chamado -- sem ele o no some mas o dicionario do `Farm3D` continua
		# com a chave, e o proximo evento mexe num objeto destruido.
		_frame = count - 1
		_acc = 0.0
		_apply_frame()
		_on_anim_end(_action)
		return


func _on_anim_end(action: String) -> void:
	if action == "Death":
		_finish_death()
	elif action == "Hurt" and not _dying and not _gone and alive:
		_set_action("Walk" if _walking else "Idle")