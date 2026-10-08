class_name Lane3D
extends Node3D

## A trilha de farm de um lado: UMA LINHA luminosa FORA do tabuleiro, na cor do
## dono. Não é uma pista — era (leito, guias, portões, chevrons) e competia
## com o tabuleiro; agora só marca por onde os mobs andam.
##
## A trilha do jogador fica embaixo (z POSITIVO, alem da linha 3) e a do
## rival em cima (z NEGATIVO, alem da linha 0). As duas sao geometricamente
## espelhadas em relacao a z=0, que e o meio do tabuleiro -- e por isso que
## o enquadramento da camera precisa de uma correcao so, nao duas.

## Cores de dono. O ciano do jogador e o ambar do rival sao os dois pontos
## mais distantes da paleta que o tabuleiro ja usa (lajes em roxo-carvao e o
## brilho de choque em violeta), e sao simétricos: quem olha de longe sabe
## de quem e a trilha sem ler nada.
const ACCENT_PLAYER := Color("5ec8f5")
const ACCENT_AI := Color("f08a3c")

## Pips de placar. Ficam escondidos (o placar vive no HUD), mas a contagem
## continua existindo porque `Farm3D` chama `set_kills`.
const SCORE_PIPS := 6
const PIP_SPACING := 0.17
const PIP_Y := 1.18
const PIP_SIZE := 0.15

var side: int = Board.Side.PLAYER
var half_x: float = 4.30
## Largura da faixa. Não desenha mais nada (a trilha é uma linha); o `Farm3D`
## ainda passa o valor no `create`, e fica aqui só para não mudar a assinatura.
var width: float = 1.55
var active: bool = false

var _accent: Color = ACCENT_PLAYER
var _dir: float = 1.0
var _mat_rail: StandardMaterial3D
var _mat_flare: StandardMaterial3D
var _flare: MeshInstance3D
var _pip_on: Array[StandardMaterial3D] = []
## Os nós dos pips, não só os materiais: `StandardMaterial3D` é um Resource e
## não tem `get_parent()`. O código chamava isso e nunca teria compilado.
var _pip_holders: Array[Node3D] = []
var _pip_off: StandardMaterial3D
var _pips_root: Node3D
var _kills: int = 0
var _t: float = 0.0
var _flare_pulse: float = 0.0


## Direcao de caminhada do dono: o jogador da esquerda para a direita (+X), o
## rival da direita para a esquerda (-X).
static func dir_of(p_side: int) -> float:
	return 1.0 if p_side == Board.Side.PLAYER else -1.0


static func accent_of(p_side: int) -> Color:
	return ACCENT_PLAYER if p_side == Board.Side.PLAYER else ACCENT_AI


static func create(p_side: int, p_half_x: float, p_width: float) -> Lane3D:
	var n := Lane3D.new()
	n.side = p_side
	n.half_x = p_half_x
	n.width = p_width
	return n


func _ready() -> void:
	_accent = accent_of(side)
	_dir = dir_of(side)
	_build()
	set_kills(_kills)
	set_process(true)


func lane_len() -> float:
	return half_x * 2.0


func _build() -> void:
	var length := lane_len()

	# A trilha e UMA LINHA, nao uma pista. Antes eram leito, rastro gasto, duas
	# guias, dois portoes e nove chevrons correndo: uma laje de 8.6 x 1.55 que
	# competia com o tabuleiro. Agora so um filete luminoso na cor do dono, que
	# diz "por aqui" e nada mais; os mobs andam em cima dele.
	_mat_rail = StandardMaterial3D.new()
	_mat_rail.albedo_color = _accent.darkened(0.2)
	_mat_rail.roughness = 0.4
	_mat_rail.emission_enabled = true
	_mat_rail.emission = _accent
	_mat_rail.emission_energy_multiplier = 0.9

	var line := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(length, 0.035, 0.07)
	line.mesh = lb
	line.material_override = _mat_rail
	line.position = Vector3(0, 0.02, 0)
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(line)

	# --- brilho difuso ao longo da linha: acende quando a fase comeca e a
	# cada abate.
	#
	# O material TEM que sair de `FarmFx.glow_mat`: unshaded, com transparencia
	# por alfa, mistura ADITIVA e a textura difusa. Antes era um
	# `StandardMaterial3D.new()` cru, cuja transparencia vem DESLIGADA - o alfa
	# era ignorado e o "brilho" virava um retangulo OPACO na cor do dono.
	_mat_flare = FarmFx.glow_mat(FarmFx.soft_dot(),
		Color(_accent.r, _accent.g, _accent.b, 0.0), true)
	_flare = FarmFx.flat_quad(1.0, FarmFx.soft_dot(), Color.WHITE, true)
	_flare.material_override = _mat_flare
	# estreito: so um halo em volta da linha, nao uma faixa cobrindo o chao
	_flare.scale = Vector3(length * 1.04, 0.55, 1.0)
	_flare.position = Vector3(0, 0.05, 0)
	add_child(_flare)

	_build_pips()
	# os pips de placar em 3D ficam escondidos: o placar vive no HUD, e uma
	# fileira de bolinhas sobre a linha e justamente o "enfeite" que saiu
	_pips_root.visible = false


func _build_pips() -> void:
	_pips_root = Node3D.new()
	_pips_root.position = Vector3(0, PIP_Y, 0)
	add_child(_pips_root)
	_pip_off = FarmFx.glow_mat(FarmFx.ring_tex(), Color(1, 1, 1, 0.5), true)
	var start := -PIP_SPACING * (SCORE_PIPS - 1) * 0.5
	for k in SCORE_PIPS:
		var holder := Node3D.new()
		holder.position = Vector3(start + PIP_SPACING * float(k), 0, 0)
		_pips_root.add_child(holder)
		# anel apagado: sempre visivel, e o que mostra quantos mobos a fila tem
		holder.add_child(FarmFx.billboard_quad(PIP_SIZE, FarmFx.ring_tex(),
			Color(1, 1, 1, 0.22), true))
		# disco aceso: um por mobo morto
		var lit := FarmFx.billboard_quad(PIP_SIZE * 0.62, FarmFx.soft_dot(),
			Color.WHITE, true)
		lit.visible = false
		holder.add_child(lit)
		_pip_on.append(lit.material_override as StandardMaterial3D)
		_pip_holders.append(holder)


## Acende [count] pips: e a contagem da fase virando objeto na cena. Quem
## chama e o `Farm3D`, um pip a cada `mob_killed`.
func set_kills(count: int) -> void:
	var prev := _kills
	_kills = clampi(count, 0, SCORE_PIPS)
	if _pips_root == null:
		return
	for k in SCORE_PIPS:
		var on := k < _kills
		var pip := _pip_on[k]
		_pip_holders[k].get_child(1).visible = on
		pip.albedo_color = _accent if on else Color(0, 0, 0, 0)
	# o pip recem aceso estufa: sem isso a fileira muda de cor e ninguem nota
	if _kills > prev and _kills > 0:
		var last: Node3D = _pip_holders[_kills - 1]
		last.scale = Vector3.ONE * 2.2
		var tw: Tween = last.create_tween()
		tw.tween_property(last, "scale", Vector3.ONE, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func kills() -> int:
	return _kills


## Liga/desliga a trilha. Apagada ela e cenario; acesa, e o aquecimento.
func set_active(on: bool) -> void:
	active = on


## Os pips de placar em 3D ficam SEMPRE escondidos: o placar vive no HUD. A
## função existe porque o `Farm3D` a chama; o parâmetro é ignorado de propósito.
func set_score_pips_visible(_on: bool) -> void:
	if _pips_root:
		_pips_root.visible = false


## Pulso de una cor na trilha inteira. Usado no bonus e na vitoria da fase: e o
## "subiu" que o jogador ve no mundo antes de olhar o placar da HUD.
func flare(strength := 1.0, color := Color(0, 0, 0, 0)) -> void:
	if _mat_flare == null:
		return
	if color.a > 0.0:
		_mat_flare.albedo_color = Color(color.r, color.g, color.b, 0.0)
	_flare_pulse = maxf(_flare_pulse, strength)


func _process(delta: float) -> void:
	_t += delta

	# a linha: apagada em repouso, acesa durante a fase
	_mat_rail.emission_energy_multiplier = lerpf(
		_mat_rail.emission_energy_multiplier,
		0.9 if active else 0.35, delta * 4.0)

	# brilho: um piso fraco quando acesa + o pulso do flare. Estes são os
	# valores originais: eu os tinha reduzido (0.05 / 0.30) achando que o bloco
	# saturado era intensidade demais, mas o bloco era o material OPACO do
	# flare (ver [_build]), não a intensidade. Com a mistura aditiva certa, o
	# pico a cada abate é justamente o "subiu" que a fase precisa mostrar.
	var base_a := (0.10 + 0.04 * sin(_t * 2.0)) if active else 0.0
	if _flare_pulse > 0.0:
		_flare_pulse = maxf(0.0, _flare_pulse - delta * 1.5)
		base_a = maxf(base_a, _flare_pulse * 0.7)
	_mat_flare.albedo_color = Color(
		_mat_flare.albedo_color.r, _mat_flare.albedo_color.g,
		_mat_flare.albedo_color.b, minf(base_a, 1.0))
