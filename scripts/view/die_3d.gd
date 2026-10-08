class_name Die3D
extends Node3D

## Um d6 de verdade, com pips desenhados em runtime.
##
## O jogador CLICA no dado para rolar: o número já foi sorteado pelo `Game`
## (é o `Game` que decide), e o dado só gira até mostrar aquele valor. É o
## inverso de "sorteia e mostra" — o sorteio é do sistema, a animação é a
## consequência visível. O dado do rival usa o mesmo código e é rolado por
## baixo dos panos, sem clique.
##
## Não usa física de propósito: um corpo rígido tombando em direção aleatória
## nem sempre para no número sorteado, e aí a face mostrada contradiz a mana.
## Aqui a rotação é calculada para a face correta, com um giro extra em Z para
## não ficar sempre igual.

const SIZE := 0.86
const TEX := 128
## Quanto tempo o dado leva para girar e travar.
const ROLL_TIME := 0.85

## Para onde aponta a normal de cada face, na ordem do número.
##
## Isto tem que bater com o cubo montado em [_build]: o quad 0 fica em +Z sem
## rotação, o 1 em -Z girado 180°, o 2 em +X, o 3 em -X, o 4 em +Y e o 5 em
## -Y. Estava com a ordem do `BoxMesh` (+X, -X, +Y, -Y, +Z, -Z), que não é a
## mesma coisa — aí o dado trazia para a frente a face de outro número.
const FACE_AXIS := [
	Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3.RIGHT, Vector3.LEFT,
	Vector3.UP, Vector3.DOWN]

var face: int = 1              ## número mostrado de frente
var rolling: bool = false
var interactive: bool = true

var _t := 0.0
var _from := Basis.IDENTITY
var _to := Basis.IDENTITY
var _hover := 0.0
var _hover_target := 0.0
var _shade: OmniLight3D


static func create(p_interactive: bool) -> Die3D:
	var d := Die3D.new()
	d.interactive = p_interactive
	return d


func _ready() -> void:
	_build()


## O cubo é montado com seis quads, um por face, em vez de um `BoxMesh`. Com
## `BoxMesh` o Godot não deixa substituir o material das seis surfaces (só a
## primeira), e os quads dão controle direto de para onde cada número olha —
## o que é justamente o que a rotação final precisa.
func _build() -> void:
	var h := SIZE * 0.5
	for i in 6:
		var q := QuadMesh.new()
		q.size = Vector2(SIZE, SIZE)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = _face_material(i + 1)
		match i:
			0:
				mi.position = Vector3(0, 0, h)
			1:
				mi.position = Vector3(0, 0, -h)
				mi.rotation_degrees = Vector3(0, 180, 0)
			2:
				mi.position = Vector3(h, 0, 0)
				mi.rotation_degrees = Vector3(0, 90, 0)
			3:
				mi.position = Vector3(-h, 0, 0)
				mi.rotation_degrees = Vector3(0, -90, 0)
			4:
				mi.position = Vector3(0, h, 0)
				mi.rotation_degrees = Vector3(-90, 0, 0)
			5:
				mi.position = Vector3(0, -h, 0)
				mi.rotation_degrees = Vector3(90, 0, 0)
		add_child(mi)

	_shade = OmniLight3D.new()
	_shade.light_color = Color("ffe8c0")
	_shade.light_energy = 1.2
	_shade.omni_range = 3.4
	_shade.position = Vector3(0.7, 1.3, 1.1)
	add_child(_shade)


func _face_material(number: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _pip_texture(number)
	m.roughness = 0.45
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	return m


## Desenha a face de um dado num `Image`: fundo claro, pips escuros.
static func _pip_texture(number: int) -> ImageTexture:
	var img := Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	img.fill(Color("f2ead8"))

	# 1 no centro, 2 na diagonal, 3 na diagonal, 4 nos cantos, 5 no X, 6 em duas
	# colunas de três
	var spots := {
		1: [Vector2(0, 0)],
		2: [Vector2(-1, -1), Vector2(1, 1)],
		3: [Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)],
		4: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
		5: [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1),
			Vector2(1, 1)],
		6: [Vector2(-1, -1), Vector2(1, -1), Vector2(-0.5, 0), Vector2(0.5, 0),
			Vector2(-1, 1), Vector2(1, 1)],
	}
	var list: Array = spots.get(clampi(number, 1, 6), [])
	var r := TEX * 0.1
	for s in list:
		var c := Vector2(TEX * 0.5, TEX * 0.5) \
			+ Vector2(float(s.x), float(s.y)) * TEX * 0.26
		# sombra primeiro, pips por cima: dá volume em vez de bolster preto
		_blit(img, c + Vector2(2, 2), r, Color("c9bfa8"))
		_blit(img, c, r, Color("2a1f38"))

	return ImageTexture.create_from_image(img)


static func _blit(img: Image, centre: Vector2, r: float, col: Color) -> void:
	var x0 := maxi(int(centre.x - r - 2), 0)
	var x1 := mini(int(centre.x + r + 2), TEX - 1)
	var y0 := maxi(int(centre.y - r - 2), 0)
	var y1 := mini(int(centre.y + r + 2), TEX - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(float(x) + 0.5, float(y) + 0.5) - centre
			if d.length() <= r:
				img.set_pixel(x, y, col)


## Faz o dado girar e travar mostrando [value].
func roll_to(value: int) -> void:
	face = clampi(value, 1, 6)
	# `orthonormalized()` é obrigatório: `Basis.slerp` converte a base em
	# Quaternion por dentro, e a base carrega a escala do "bob" do hover —
	# sem isso o Godot cuspe erro a cada frame da rolagem.
	_from = transform.basis.orthonormalized()
	_to = basis_for_face(face, _toward_camera())
	_t = 0.0
	rolling = true


## Direção do dado até a câmera. Sem câmera (teste headless) cai em +Z.
func _toward_camera() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return Vector3(0, 0, 1)
	var d := cam.global_position - global_position
	return d.normalized() if d.length() > 0.001 else Vector3(0, 0, 1)


## Base que leva a face [n] a apontar para [toward] (a direção até a câmera),
## com o número em pé.
##
## O ALVO É A CÂMERA, não +Z. A câmera é elevada (olha o tabuleiro de cima), e
## +Z tem produto escalar de só ~0.44 com a direção da câmera, enquanto a face
## de CIMA tem ~0.75: um cubo visto de cima e de lado mostra o topo bem maior
## que a "frente". Então, mesmo com a rotação perfeita para +Z, o jogador lia o
## número do topo — outro. O teste (`shot.gd` modo 4/0) calcula qual número está
## de fato virado para a câmera e acusou isso: a face "da frente" era 3 e a
## virada para a câmera era 5.
##
## A conta: `B = Basis(right, up, N)` é o referencial da face; `Bᵀ` (a inversa)
## leva N → +Z e `up` → +Y. `T = Basis(right', up', toward)` leva +Z para a
## câmera mantendo o "cima" da tela. `R = T · Bᵀ` leva a normal da face
## exatamente para a câmera, com o número em pé. (`B` direto leva Z → N, o
## inverso do que queremos, e só dava certo nas faces ±Z.)
static func basis_for_face(n: int, toward := Vector3(0, 0, 1)) -> Basis:
	var normal: Vector3 = FACE_AXIS[clampi(n, 1, 6) - 1].normalized()
	var ref := Vector3.UP
	if absf(normal.dot(ref)) > 0.9:
		# faces de topo e base não têm "cima" utilizável: usa a frente como
		# referência para os pips não saírem deitados
		ref = Vector3(0, 0, 1)
	var up := (ref - normal * ref.dot(normal)).normalized()
	var right := up.cross(normal).normalized()
	var b := Basis(right, up, normal)

	# referencial de destino: Z = câmera, Y = o "cima" do mundo projetado
	var z := toward.normalized()
	var y_hint := Vector3.UP
	if absf(z.dot(y_hint)) > 0.95:
		y_hint = Vector3(0, 0, -1)
	var y := (y_hint - z * y_hint.dot(z)).normalized()
	var x := y.cross(z).normalized()
	var t := Basis(x, y, z)

	# giro leve em torno do EIXO DA CÂMERA para o dado não cair sempre na mesma
	# pose; a face continua apontando para a câmera
	var spin := Basis(z, randf_range(-0.35, 0.35))
	return spin * (t * b.transposed())


func set_hovered(on: bool) -> void:
	_hover_target = 1.0 if on else 0.0


func _process(delta: float) -> void:
	if rolling:
		_t += delta / ROLL_TIME
		if _t >= 1.0:
			_t = 1.0
			rolling = false
			transform.basis = _to
		else:
			# A rotação real vem de um eixo aleatório por frame, para o dado
			# parecer solto; o alvo já está calculado, então ele sempre chega no
			# número sorteado.
			#
			# O `orthonormalized()` não é cosmeticamente: `slerp` devolve uma
			# base com escala residual e multiplicar por ela deixava a base
			# não-normalizada, o que fazia o Godot cuspir erro a cada frame.
			var axis := Vector3(randf_range(-1, 1), randf_range(-1, 1),
				randf_range(-1, 1))
			if axis.length() < 0.001:
				axis = Vector3.UP
			var spin := Basis(axis.normalized(), delta * (8.0 + 26.0 * (1.0 - _t)))
			transform.basis = (spin * _from.slerp(_to, ease(_t, 0.3))).orthonormalized()
		return

	_hover = move_toward(_hover, _hover_target, delta * 8.0)
	if interactive:
		# leve flutuação quando pode ser clicado, para chamar atenção
		var bob := 1.0 + 0.02 * sin(Time.get_ticks_msec() * 0.004)
		scale = Vector3.ONE * (1.0 + 0.06 * _hover) * bob