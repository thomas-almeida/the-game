class_name Projectile3D
extends Node3D

## O tiro da fase de farm: o que sai da criatura e chega no mobo (ou no jogador).
##
## Ele existe para responder a tres perguntas de uma vez -- de onde saiu, para
## onde foi e onde bateu. As duas primeiras sao o proprio corpo do projetil; a
## terceira e o que o `Farm3D` dispara quando o tiro pousa.
##
## CADA ELEMENTO TEM O SEU TIRO, e o jogador deve reconhece-lo sem olhar a cor,
## so pela silhueta e pelo movimento:
##   FOGO   bola quente com labareda, RAPIDO e reto, pulsando; solta brasas
##   AGUA   orbe/gota translucida que ONDULA num arco suave; solta bolhas
##   TERRA  pedra girando, LENTA e pesada, arco ALTO; solta poeira e pedriscos
##   GELO   cristal de duas pontas girando como shuriken, reto e frio
##   SOMBRA orbe negro com anel roxo e fiapos, trajetoria ERRATICA e sinuosa
## Elemento -1 (ou desconhecido) cai no estilo antigo: nucleo + halo + rastros.
##
## O alvo e lido A CADA FRAME em vez de ser congelado no lancamento: o mobo
## esta andando, e um tiro de 0.3s contra 3.2 u/s erra meio metro se mirar
## onde ele estava. Perseguir o alvo e o que faz o tiro "acertar".

## Velocidade do projetil em unidades por segundo, e os limites de tempo de
## voo. O piso evita o tiro instantaneo quando o alvo esta em cima da
## criatura; o teto evita que um tiro para o outro lado da tela demore tanto
## que a fase arraste. O fator de cada elemento multiplica os dois.
##
## ABAIXO DO ORIGINAL: 22 -> 15 (mais lento), tempo maior (0.25..0.65)
## para o jogador ver o voo do projetil.
const SPEED := 15.0
const TIME_MIN := 0.25
const TIME_MAX := 0.65

## Personalidade de movimento por elemento:
## [fator de duracao, curva do ease, arco base, arco por unidade de distancia].
## Fogo e gelo chegam antes e quase retos; a terra leva o dobro e sobe alto.
const MOVE := {
	CardData.Element.FIRE: [0.72, 1.15, 0.04, 0.015],
	CardData.Element.WATER: [1.10, 1.50, 0.16, 0.070],
	CardData.Element.EARTH: [2.00, 1.30, 0.55, 0.220],
	CardData.Element.FROST: [0.85, 1.10, 0.02, 0.008],
	CardData.Element.SHADOW: [1.35, 1.00, 0.05, 0.020],
}

## Intervalo entre particulas do rastro, por elemento (segundos).
const TRAIL_GAP := {
	CardData.Element.FIRE: 0.020,
	CardData.Element.WATER: 0.040,
	CardData.Element.EARTH: 0.035,
	CardData.Element.FROST: 0.030,
	CardData.Element.SHADOW: 0.028,
}

## [amount] e o ATK que gerou o tiro, e ele escala o projetil inteiro: nucleo,
## halo, rastro e brilho. E assim que "6 pesa mais que 2" fica visivel sem
## nenhum numero na tela. [p_element] e opcional (-1 = estilo antigo).
static func launch(parent: Node, from: Vector3, target: Node3D,
		fallback: Vector3, p_amount: int, color: Color,
		p_element := -1) -> Projectile3D:
	var b := Projectile3D.new()
	b.amount = maxi(1, p_amount)
	b.element = p_element if FarmFx.has_style(p_element) else -1
	b._from = from
	b._target = target
	b._fallback = fallback
	var dist := from.distance_to(fallback)
	var f := 1.0
	b._ease = 1.6
	b._arc = 0.08 + dist * 0.045
	if b.element >= 0:
		var mv: Array = MOVE[b.element]
		f = mv[0]
		b._ease = mv[1]
		b._arc = mv[2] + dist * mv[3]
	b._duration = clampf(dist / SPEED * f, TIME_MIN * f, TIME_MAX * f)
	b._dir = (fallback - from).normalized()
	b._build(color)
	parent.add_child(b)
	b._pos = from
	b._prev = from
	b.position = from
	b.set_process(true)
	return b


## Emitido no instante em que o tiro chega. O `Farm3D` se conecta a ele para
## tocar o impacto -- o projetil nao sabe nada sobre mobo, vida ou dano.
signal landed(where: Vector3)

var amount: int = 1
var element: int = -1

var _from: Vector3
var _fallback: Vector3
var _target: Node3D
var _arc: float = 0.0
var _ease: float = 1.6
var _time: float = 0.0
var _clock: float = 0.0
var _duration: float = 0.3
var _pos: Vector3
var _prev: Vector3
var _dir: Vector3 = Vector3.FORWARD
var _trail_t: float = 0.0
## fases aleatorias da trajetoria (agua/sombra): cada tiro serpenteia diferente
var _ph: Array[float] = []

var _body: Node3D          ## orientado: +Z na direcao do voo
var _spin: Node3D          ## gira sobre si (pedra, cruz de gelo, fiapos)
var _crystal: Node3D       ## o cristal de gelo (eixo longo no voo)
var _core: MeshInstance3D
var _halo: MeshInstance3D
var _halo2: MeshInstance3D
var _flame: MeshInstance3D
var _flame2: MeshInstance3D
var _tail: MeshInstance3D
var _tail2: MeshInstance3D
var _tendrils: Array[MeshInstance3D] = []
var _tw_in: Tween
var _landed: bool = false
var _land_scale: float = 1.7


func _core_r() -> float:
	return 0.055 + 0.018 * float(amount)


func _build(color: Color) -> void:
	for i in 4:
		_ph.append(randf() * TAU)
	match element:
		CardData.Element.FIRE:
			_build_fire()
		CardData.Element.WATER:
			_build_water()
		CardData.Element.EARTH:
			_build_earth()
		CardData.Element.FROST:
			_build_frost()
		CardData.Element.SHADOW:
			_build_shadow()
		_:
			_build_default(color)

	# estrobo de saida: o tiro nasce pequeno e cresce, o que da o "estalo" no
	# ponto exato de onde a criatura disparou.
	scale = Vector3.ONE * 0.35
	_tw_in = create_tween()
	_tw_in.tween_property(self, "scale", Vector3.ONE, 0.09) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## O estilo antigo (elemento desconhecido): nucleo + halo + dois rastros.
func _build_default(color: Color) -> void:
	var core_r := _core_r()

	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.albedo_color = Color(1, 1, 1).lerp(color, 0.35)
	_core = FarmFx.sphere(core_r, cm)
	add_child(_core)

	# halo: o mesmo volume com blend aditivo e raio maior. E o que faz o tiro
	# "acender" em vez de virar uma bolinha opaca.
	_halo = FarmFx.sphere(core_r * 2.5, FarmFx.glow_mat(
		FarmFx.soft_dot(), color, true))
	add_child(_halo)

	# rastros: dois cubos unitarios esticados no eixo Z. O de fora e largo e
	# fraco, o de dentro e estreito e quente. Comprimento e espessura sao
	# independentes porque o tamanho vem do scale do no.
	_tail = FarmFx.box(FarmFx.glow_mat(FarmFx.soft_dot(),
		Color(color.r, color.g, color.b, 0.5), true))
	add_child(_tail)
	_tail2 = FarmFx.box(FarmFx.glow_mat(FarmFx.soft_dot(),
		Color(1, 1, 1, 0.75), true))
	add_child(_tail2)


func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


## FOGO: nucleo laranja-branco, dois cones de labareda atras (que tremulam a
## cada frame) e halo duplo. Tudo pulsa rapido.
func _build_fire() -> void:
	var r := _core_r()
	var core := FarmFx.pal(CardData.Element.FIRE, FarmFx.P_CORE)
	var mid := FarmFx.pal(CardData.Element.FIRE, FarmFx.P_MID)
	var deep := FarmFx.pal(CardData.Element.FIRE, FarmFx.P_DEEP)
	_body = Node3D.new()
	add_child(_body)
	_flame = _glow_mesh(FarmFx.cone_mesh(), Color(deep.r, deep.g, deep.b, 0.6))
	_flame2 = _glow_mesh(FarmFx.cone_mesh(), Color(mid.r, mid.g, mid.b, 0.85))
	_body.add_child(_flame)
	_body.add_child(_flame2)
	_halo = FarmFx.billboard_quad(r * 6.5, FarmFx.soft_dot(),
		Color(mid.r, mid.g, mid.b, 0.85), true)
	add_child(_halo)
	_core = FarmFx.sphere(r * 0.95, _unshaded(core))
	add_child(_core)
	_halo2 = FarmFx.billboard_quad(r * 3.0, FarmFx.soft_dot(),
		Color(1.0, 0.95, 0.8, 0.9), true)
	add_child(_halo2)
	_flicker_flame()


func _glow_mesh(mesh: Mesh, c: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = FarmFx.glow_mat(null, c, true)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## A labareda: comprimento e largura sorteados a cada frame. O cone tem a base
## larga no nucleo e a ponta ATRAS (rotacao de -90 em X leva o +Y para -Z).
func _flicker_flame() -> void:
	var r := _core_r()
	var a := float(amount)
	var len := (0.55 + 0.09 * a) * randf_range(0.8, 1.25)
	var w := r * 2.3 * randf_range(0.85, 1.15)
	var b := Basis(Vector3.RIGHT, -PI * 0.5)
	_flame.transform = Transform3D(b.scaled_local(Vector3(w, len, w)),
		Vector3(0, 0, -len * 0.5))
	var len2 := len * 0.65 * randf_range(0.8, 1.2)
	_flame2.transform = Transform3D(b.scaled_local(Vector3(w * 0.55, len2, w * 0.55)),
		Vector3(0, 0, -len2 * 0.5))


## AGUA: gota translucida (azul, blend MIX) esticada no sentido do voo, com
## brilho branco e miolo claro. Respira em squash/stretch.
func _build_water() -> void:
	var r := _core_r() * 1.15
	var mid := FarmFx.pal(CardData.Element.WATER, FarmFx.P_MID)
	var core := FarmFx.pal(CardData.Element.WATER, FarmFx.P_CORE)
	_body = Node3D.new()
	add_child(_body)
	_halo = FarmFx.billboard_quad(r * 5.0, FarmFx.soft_dot(),
		Color(mid.r, mid.g, mid.b, 0.5), true)
	add_child(_halo)
	_core = FarmFx.sphere(r, FarmFx.glow_mat(null,
		Color(mid.r, mid.g, mid.b, 0.72), false))
	_body.add_child(_core)
	var inner := FarmFx.sphere(r * 0.55, FarmFx.glow_mat(null,
		Color(core.r, core.g, core.b, 0.55), true))
	_body.add_child(inner)
	# o brilho especular fica fora do corpo orientado: a luz vem de cima
	var shine := FarmFx.sphere(r * 0.24, _unshaded(Color(1, 1, 1)))
	shine.position = Vector3(r * 0.32, r * 0.42, r * 0.35)
	add_child(shine)


## TERRA: pedra feita de tres blocos desencontrados (silhueta irregular),
## escura e opaca, com poeira em volta. Gira pesado.
func _build_earth() -> void:
	var r := _core_r() * 1.1
	var mid := FarmFx.pal(CardData.Element.EARTH, FarmFx.P_MID)
	var core := FarmFx.pal(CardData.Element.EARTH, FarmFx.P_CORE)
	var deep := FarmFx.pal(CardData.Element.EARTH, FarmFx.P_DEEP)
	_halo = FarmFx.billboard_quad(r * 4.2, FarmFx.soft_dot(),
		Color(core.r, core.g, core.b, 0.38), false)
	add_child(_halo)
	_spin = Node3D.new()
	add_child(_spin)
	_rock(Vector3(r * 1.7, r * 1.35, r * 1.55), Vector3.ZERO,
		Vector3(12, 20, 5), mid)
	_rock(Vector3(r * 1.25, r * 1.25, r * 1.25), Vector3(r * 0.35, r * 0.25, -r * 0.2),
		Vector3(40, 50, 25), mid.lerp(core, 0.35))
	_rock(Vector3(r * 0.8, r * 0.8, r * 0.8), Vector3(-r * 0.5, -r * 0.3, r * 0.4),
		Vector3(70, 15, 60), deep)


func _rock(size: Vector3, off: Vector3, rot_deg: Vector3, c: Color) -> void:
	var m := MeshInstance3D.new()
	m.mesh = FarmFx.cube_mesh()
	var mat := FarmFx.solid_mat(c, 0.95)
	# um fio de emissao: sem ele a pedra vira silhueta preta na sombra da trilha
	mat.emission_enabled = true
	mat.emission = c.darkened(0.45)
	mat.emission_energy_multiplier = 0.8
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.scale = size
	m.position = off
	m.rotation_degrees = rot_deg
	_spin.add_child(m)


## GELO: cristal de duas pontas (dois cones de base colada) com o eixo longo no
## sentido do voo, mais uma cruz curta atravessada: ao girar vira um shuriken.
func _build_frost() -> void:
	var r := _core_r()
	var core := FarmFx.pal(CardData.Element.FROST, FarmFx.P_CORE)
	var mid := FarmFx.pal(CardData.Element.FROST, FarmFx.P_MID)
	var deep := FarmFx.pal(CardData.Element.FROST, FarmFx.P_DEEP)
	_body = Node3D.new()
	add_child(_body)
	_halo = FarmFx.billboard_quad(r * 5.0, FarmFx.soft_dot(),
		Color(mid.r, mid.g, mid.b, 0.5), true)
	add_child(_halo)
	_crystal = Node3D.new()
	_body.add_child(_crystal)
	_bipyramid(_crystal, r * 5.2, r * 1.5, Vector3.ZERO, mid.lerp(core, 0.5))
	var cross := Node3D.new()
	cross.rotation_degrees = Vector3(90, 0, 0)
	_crystal.add_child(cross)
	_bipyramid(cross, r * 3.4, r * 1.1, Vector3.ZERO, deep.lerp(core, 0.55))


## Dois cones de base colada. O eixo longo e o Y do [parent].
func _bipyramid(parent: Node3D, length: float, width: float, off: Vector3,
		c: Color) -> void:
	var mat := _unshaded(c)
	for k in 2:
		var m := MeshInstance3D.new()
		m.mesh = FarmFx.shard_mesh()
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.scale = Vector3(width, length * 0.5, width)
		m.position = off + Vector3(0, length * 0.25 * (1.0 if k == 0 else -1.0), 0)
		if k == 1:
			m.rotation_degrees = Vector3(180, 45, 0)
		else:
			m.rotation_degrees = Vector3(0, 45, 0)
		parent.add_child(m)


## SOMBRA: orbe NEGRO opaco (contrasta com o brilho dos outros), anel roxo em
## volta e fiapos roxos que giram e esticam de forma irregular.
func _build_shadow() -> void:
	var r := _core_r() * 1.05
	var mid := FarmFx.pal(CardData.Element.SHADOW, FarmFx.P_MID)
	var deep := FarmFx.pal(CardData.Element.SHADOW, FarmFx.P_DEEP)
	_halo = FarmFx.billboard_quad(r * 6.0, FarmFx.soft_dot(),
		Color(deep.r, deep.g, deep.b, 0.6), true)
	add_child(_halo)
	_halo2 = FarmFx.billboard_quad(r * 4.2, FarmFx.ring_tex(),
		Color(mid.r, mid.g, mid.b, 0.95), true)
	add_child(_halo2)
	_core = FarmFx.sphere(r, _unshaded(Color(0.02, 0.0, 0.05)))
	add_child(_core)
	_spin = Node3D.new()
	add_child(_spin)
	for i in 5:
		var t := FarmFx.box(FarmFx.glow_mat(null,
			Color(mid.r, mid.g, mid.b, 0.8), true))
		t.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		_spin.add_child(t)
		_tendrils.append(t)
	_flicker_tendrils()


func _flicker_tendrils() -> void:
	var r := _core_r()
	for t in _tendrils:
		var len := r * randf_range(2.4, 5.5)
		var w := r * 0.14
		t.scale = Vector3(w, w, len)


func _aim() -> Vector3:
	if _target != null and is_instance_valid(_target) \
			and _target.has_method("aim_point"):
		return _target.call("aim_point")
	return _fallback


func _process(delta: float) -> void:
	if _landed:
		return
	_clock += delta
	_time += delta / _duration
	var aim := _aim()
	var t := minf(_time, 1.0)
	# `ease` com curva > 1 e aceleracao: o tiro sai da mao devagar e ganha forca
	# no meio do caminho, em vez de sair ja com a velocidade final.
	var k := ease(t, _ease)
	_prev = _pos
	_pos = _from.lerp(aim, k) + Vector3.UP * (_arc * 4.0 * k * (1.0 - k)) \
		+ _wobble(k, aim)
	position = _pos
	var d := _pos - _prev
	if d.length_squared() > 0.0000001:
		_dir = d.normalized()
	if element < 0:
		_stretch_tails()
	else:
		_animate(delta)
		_emit_trail(delta)
	if _time >= 1.0:
		_land(aim)


## Desvio lateral/vertical da trajetoria, so para agua (ondula) e sombra
## (erratica). O envelope `sin(pi k)` zera o desvio na saida e na chegada: o tiro
## sempre sai da boca e sempre pousa EM CIMA do alvo.
func _wobble(k: float, aim: Vector3) -> Vector3:
	if element != CardData.Element.WATER and element != CardData.Element.SHADOW:
		return Vector3.ZERO
	var along := aim - _from
	var side := along.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 0.0001 else Vector3.RIGHT
	var env := sin(PI * minf(k, 1.0))
	# trajetos longos (tiro no jogador) balancam mais, senao o desvio some
	var amp := clampf(0.7 + along.length() * 0.1, 0.7, 1.7)
	if element == CardData.Element.WATER:
		# balanco senoidal suave, uma onda e meia
		return (side * sin(k * TAU * 1.5 + _ph[0]) * 0.14
			+ Vector3.UP * cos(k * TAU * 1.5 + _ph[0]) * 0.05) * env * amp
	# sombra: soma de senos de frequencias nao multiplas, com fases do tiro --
	# nunca repete e parece mudar de ideia no meio do caminho
	var lat := sin(k * TAU * 2.3 + _ph[0]) * 0.24 + sin(k * TAU * 5.1 + _ph[1]) * 0.11
	var vert := sin(k * TAU * 3.1 + _ph[2]) * 0.22 + sin(k * TAU * 6.7 + _ph[3]) * 0.09
	return (side * lat + Vector3.UP * vert) * env * amp


## Animacao por frame do corpo, por elemento.
func _animate(delta: float) -> void:
	if _body != null and absf(_dir.dot(Vector3.UP)) < 0.999:
		_body.basis = Basis.looking_at(_dir, Vector3.UP, true)
	match element:
		CardData.Element.FIRE:
			# pulso rapido do nucleo e do halo, labareda trememdo
			_core.scale = Vector3.ONE * (1.0 + 0.16 * sin(_clock * 48.0))
			_halo.scale = Vector3.ONE * (1.0 + 0.22 * sin(_clock * 31.0 + 1.3))
			_halo2.scale = Vector3.ONE * (1.0 + 0.12 * sin(_clock * 57.0))
			_flicker_flame()
		CardData.Element.WATER:
			# squash/stretch: alonga no sentido do voo e respira de lado
			var w := sin(_clock * 26.0 + _ph[1])
			_core.scale = Vector3(1.0 + 0.10 * w, 1.0 - 0.08 * w, 1.35 + 0.10 * w)
			_halo.scale = Vector3.ONE * (1.0 + 0.08 * sin(_clock * 18.0))
		CardData.Element.EARTH:
			# gira pesado sobre dois eixos; o halo de poeira respira devagar
			_spin.rotation += Vector3(5.2, 3.1, 2.4) * delta
		CardData.Element.FROST:
			# o cristal gira em torno do EIXO DO VOO: o +Y dele aponta o voo
			var spin := _clock * 14.0
			_crystal.basis = Basis(Vector3.RIGHT, PI * 0.5) \
				* Basis(Vector3.UP, spin)
			_halo.scale = Vector3.ONE * (1.0 + 0.1 * sin(_clock * 22.0))
		CardData.Element.SHADOW:
			_spin.rotation += Vector3(7.0, -5.0, 9.0) * delta
			_halo2.scale = Vector3.ONE * (1.0 + 0.15 * sin(_clock * 21.0 + _ph[0]))
			_halo.scale = Vector3.ONE * (1.0 + 0.2 * sin(_clock * 13.0))
			# um terco dos quadros re-sorteia o comprimento dos fiapos
			if randf() < 0.35:
				_flicker_tendrils()


## Rastro do elemento: particulas soltas no PAI (ficam no mundo, nao
## acompanham o tiro). No maximo 2 por frame para nao explodir em frame lento.
func _emit_trail(delta: float) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var gap: float = TRAIL_GAP[element]
	_trail_t += delta
	var n := 0
	while _trail_t >= gap and n < 2:
		_trail_t -= gap
		n += 1
		_trail_one(parent)
	if n == 2:
		_trail_t = 0.0


func _trail_one(parent: Node) -> void:
	var r := _core_r()
	var back := -_dir
	var core := FarmFx.pal(element, FarmFx.P_CORE)
	var mid := FarmFx.pal(element, FarmFx.P_MID)
	var deep := FarmFx.pal(element, FarmFx.P_DEEP)
	match element:
		CardData.Element.FIRE:
			# brasas que ficam para tras e sobem; de vez em quando uma faisca
			# branca, pequena e rapida
			FarmFx.puff(parent, _pos, mid.lerp(core, randf()),
				randf_range(0.07, 0.13) * (0.8 + r * 3.0),
				back * 0.5 + FarmFx._rdir() * 0.45 + Vector3.UP * 0.5,
				randf_range(0.22, 0.38), 0.1)
			if randf() < 0.35:
				FarmFx.puff(parent, _pos, Color(1, 0.97, 0.85, 1.0), 0.05,
					FarmFx._rdir() * 1.6, 0.16, 0.2)
		CardData.Element.WATER:
			# bolhas (anel) e uma gota solta que cai
			FarmFx.puff(parent, _pos + FarmFx._rdir() * r * 0.6,
				Color(core.r, core.g, core.b, 0.8), randf_range(0.08, 0.15),
				back * 0.2 + Vector3.UP * 0.35 + FarmFx._rdir() * 0.15,
				0.5, 1.4, true, FarmFx.ring_tex())
			if randf() < 0.55:
				var s := randf_range(0.03, 0.06)
				FarmFx.bit(parent, FarmFx.drop_mesh(),
					FarmFx.glow_mat(null, Color(0.55, 0.8, 1.0, 0.85), false),
					_pos, back * 0.6 + FarmFx._rdir() * 0.35, 0.4, 7.0,
					Vector3(s, s * 1.3, s), 0.0)
		CardData.Element.EARTH:
			# nuvem de poeira que cresce (blend MIX) e pedriscos que caem
			FarmFx.puff(parent, _pos, Color(core.r, core.g, core.b, 0.42),
				r * 2.4, back * 0.3 + FarmFx._rdir() * 0.25, 0.55, 2.2, false)
			if randf() < 0.6:
				var s := randf_range(0.03, 0.07)
				FarmFx.bit(parent, FarmFx.cube_mesh(),
					FarmFx.solid_mat(mid.lerp(deep, randf()), 0.95), _pos,
					back * 0.5 + FarmFx._rdir() * 0.6, 0.45, 8.0,
					Vector3(s, s, s), 7.0)
		CardData.Element.FROST:
			# brilhos de neve: pontinhos pequenos que cintilam e somem
			FarmFx.puff(parent, _pos + FarmFx._rdir() * r * 0.8,
				Color(core.r, core.g, core.b, 0.95), randf_range(0.05, 0.10),
				back * 0.25 + FarmFx._rdir() * 0.35, 0.36, 0.15)
			if randf() < 0.25:
				FarmFx.puff(parent, _pos, Color(mid.r, mid.g, mid.b, 0.5),
					r * 2.0, back * 0.2, 0.3, 1.4, true)
		CardData.Element.SHADOW:
			# fiapos de vazio: roxo que se espalha, e um borrao escuro MIX
			FarmFx.puff(parent, _pos + FarmFx._rdir() * r * 0.5,
				Color(mid.lerp(deep, randf()), 0.85), randf_range(0.12, 0.2),
				back * 0.3 + FarmFx._rdir() * 0.55, 0.42, 0.3)
			if randf() < 0.5:
				FarmFx.puff(parent, _pos, Color(0.02, 0.0, 0.05, 0.55),
					r * 2.6, FarmFx._rdir() * 0.2, 0.36, 0.6, false)


## Orienta os rastros do estilo antigo na direcao da velocidade. `looking_at`
## com `use_model_front = true` aponta o +Z do no no alvo, e o eixo longo do
## `BoxMesh` e o Z -- entao escalar o Z e estica o rastro para tras.
func _stretch_tails() -> void:
	if absf(_dir.dot(Vector3.UP)) > 0.999:
		return
	var basis := Basis.looking_at(_dir, Vector3.UP, true)
	var a := float(amount)
	var len := 0.5 + 0.16 * a
	var thick := 0.10 + 0.028 * a
	_tail.transform = Transform3D(basis, Vector3.ZERO)
	_tail.scale = Vector3(thick, thick, len)
	_tail2.transform = Transform3D(basis, Vector3.ZERO)
	_tail2.scale = Vector3(thick * 0.45, thick * 0.45, len * 1.15)


func _collect(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)


## Pousou. A cena reage pelo sinal `landed`, e aqui so o corpo se apaga.
func _land(where: Vector3) -> void:
	if _landed:
		return
	_landed = true
	set_process(false)
	if _tw_in != null and _tw_in.is_valid():
		_tw_in.kill()
	landed.emit(where)
	var tw := create_tween()
	tw.set_parallel(true)
	if element < 0:
		tw.tween_property(_tail, "transparency", 1.0, 0.09)
		tw.tween_property(_tail2, "transparency", 1.0, 0.09)
		tw.tween_property(_halo, "transparency", 1.0, 0.12)
		tw.tween_property(self, "scale", Vector3.ONE * 1.7, 0.10)
		# a CABEÃ‡A do projÃ©til, nÃ£o `self`: `transparency` Ã© propriedade de
		# GeometryInstance3D e este nÃ³ Ã© um Node3D puro. Tween numa propriedade que
		# nÃ£o existe devolve null, e o `.set_delay()` encadeado derrubava com
		# "Cannot call method 'set_delay' on a null value" a cada tiro.
		tw.tween_property(_core, "transparency", 1.0, 0.16).set_delay(0.05)
	else:
		# todas as pecas sao MeshInstance3D (so elas tem `transparency`); a
		# sombra encolhe porque o impacto dela e uma implosao
		var parts: Array[MeshInstance3D] = []
		_collect(self, parts)
		for p in parts:
			tw.tween_property(p, "transparency", 1.0, 0.10)
		var s := 0.3 if element == CardData.Element.SHADOW else 1.3
		tw.tween_property(self, "scale", Vector3.ONE * s, 0.10)
	tw.chain().tween_callback(queue_free)
