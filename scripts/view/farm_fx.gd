class_name FarmFx
extends RefCounted

## Pecas de efeito da fase de farm: as duas texturas macias (borrao radial e
## anel) e os efeitos que aparecem o tempo todo -- onda de choque no chao,
## estilhaco e clarao.
##
## Tudo procedural, nada de PNG. Um borrao radial e um anel sao 64x64 de
## `Image`, e o resto e `Tween` num no que se libera sozinho. Motivo: sao
## efeitos de meio segundo em quantidade variavel (um por tiro), e um atlas
## novo entraria na bilhetada dos ~944 `.import` sem ganhar nada.

## Resolucao das texturas geradas aqui.
const TEX := 64

static var _dot: Texture2D = null
static var _ring: Texture2D = null


## Borrao radial com queda quadratica. E o clarao do projetil, o flash do
## impacto e o pip de vida do mobo -- um so material para os tres.
static func soft_dot() -> Texture2D:
	if _dot != null:
		return _dot
	var img := Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(TEX) * 0.5
	for y in TEX:
		for x in TEX:
			var d := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(
				Vector2(c, c)) / c
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_dot = ImageTexture.create_from_image(img)
	return _dot


## Anel fino centrado em 0.82 do raio, com 0.18 de espessura. E a onda que
## sai do ponto de impacto.
static func ring_tex() -> Texture2D:
	if _ring != null:
		return _ring
	var img := Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(TEX) * 0.5
	for y in TEX:
		for x in TEX:
			var d := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(
				Vector2(c, c)) / c
			# o teto era 1.5, e 1 - 1.5 = -0.5 elevado ao quadrado dava 0.25: o
			# miolo e os cantos do quadro ficavam num cinza opaco (um QUADRADO
			# em volta de todo anel). O teto tem que ser 1.0.
			var a := 1.0 - clampf(absf(d - 0.82) / 0.18, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_ring = ImageTexture.create_from_image(img)
	return _ring


static func glow_mat(tex: Texture2D, color: Color, additive := true) \
		-> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive \
		else BaseMaterial3D.BLEND_MODE_MIX
	m.albedo_texture = tex
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m


static func solid_mat(color: Color, roughness := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


## Quad deitado no chao (rotacao -90 em X). Onda de choque, brilho da trilha.
static func flat_quad(size: float, tex: Texture2D, color: Color,
		additive := true) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	m.mesh = q
	m.material_override = glow_mat(tex, color, additive)
	m.rotation_degrees = Vector3(-90, 0, 0)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## Quad virado para a camera. O billboard vem do MATERIAL, nao de um
## `Sprite3D`: `Sprite3D` nao aceita `BLEND_MODE_ADD`, e sem aditivo o clarao
## do tiro vira um borrao cinza chapado.
static func billboard_quad(size: float, tex: Texture2D, color: Color,
		additive := true) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	m.mesh = q
	var mat := glow_mat(tex, color, additive)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## Anel que se abre no chao a partir de [pos]. E o "bateu aqui" do impacto:
## o raio e proporcional ao dano, entao um tiro de 6 abre bem mais que um
## de 2 -- e a escala do ATK virando tamanho de onda.
static func shockwave(parent: Node, pos: Vector3, color: Color, radius: float,
		time := 0.38) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var m := flat_quad(1.0, ring_tex(), color, true)
	m.position = pos + Vector3(0, 0.04, 0)
	m.scale = Vector3.ONE * 0.18
	parent.add_child(m)
	# O tween nasce no no, nao na cena: se o pai for liberado no meio, o tween
	# morre junto em vez de escrever num objeto destruido.
	var tw := m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3.ONE * radius * 2.0, time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "transparency", 1.0, time).set_delay(time * 0.35)
	tw.chain().tween_callback(m.queue_free)


## Estilhaco que sai do impacto. [count] e [speed] escalam com o dano: um tiro
## de 6 joga mais pedacos, mais longe e mais duros que um de 2.
static func debris(parent: Node, pos: Vector3, color: Color, count: int,
		speed: float, life := 0.6) -> void:
	if parent == null or not is_instance_valid(parent) or count <= 0:
		return
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	var tw := root.create_tween()
	tw.set_parallel(true)
	for i in count:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		var s := randf_range(0.05, 0.12)
		b.size = Vector3(s, s, s)
		m.mesh = b
		m.material_override = solid_mat(
			color.lerp(Color.WHITE, randf() * 0.45), 0.6)
		m.rotation_degrees = Vector3(randf_range(0, 360), randf_range(0, 360), 0)
		root.add_child(m)
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(0.25, 1.1),
			randf_range(-1.0, 1.0)).normalized()
		var sp := speed * randf_range(0.6, 1.4)
		# queda: o alvo final e o vetor de saida mais a queda do tempo ao quadrado
		var land := dir * sp * life * 0.5 \
			+ Vector3(0, -4.0 * life * life * 0.5, 0)
		tw.tween_property(m, "position", land, life) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(m, "rotation_degrees",
			Vector3(randf_range(-540, 540), randf_range(-540, 540), 0), life)
		tw.tween_property(m, "scale", Vector3.ZERO, life * 0.5) \
			.set_delay(life * 0.5)
	tw.chain().tween_callback(root.queue_free)


## Clarao no ponto de impacto: um borrao que estoura e some. Vai junto com a
## onda, mas e o que da o estalo do golpe.
static func flash(parent: Node, pos: Vector3, color: Color, size: float,
		time := 0.22) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var m := billboard_quad(size, soft_dot(), color, true)
	m.position = pos
	parent.add_child(m)
	var tw := m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3.ONE * 2.1, time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "transparency", 1.0, time)
	tw.chain().tween_callback(m.queue_free)

## Pilar de luz que sobe da trilha quando um mobo morre. E a unica peca que
## sobrevive ao flash: sem ela mata-se um mobo e some, e o jogador nao sente o
## placar subindo.
static func pillar(parent: Node, pos: Vector3, color: Color, height: float,
		time := 0.7) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.10
	c.bottom_radius = 0.22
	c.height = 1.0
	c.radial_segments = 12
	c.rings = 1
	m.mesh = c
	m.material_override = glow_mat(soft_dot(), color, true)
	m.position = pos + Vector3(0, 0.5, 0)
	m.scale = Vector3(1.0, 0.01, 1.0)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	var tw := m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3(1.0, height, 1.0), time * 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "scale", Vector3(0.15, height * 1.3, 0.15), time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(m, "transparency", 1.0, time).set_delay(time * 0.3)
	tw.chain().tween_callback(m.queue_free)

## Esfera de baixa contagem de segmentos. A `SphereMesh` padrao tem 64x32 e,
## com um projetil por tiro, isso e geometria jogada fora.
static func sphere(radius: float, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 12
	s.rings = 6
	m.mesh = s
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## Cubo unitario com material. O tamanho vem do `scale` do no, o que deixa o
## rastro do projetil com comprimento e espessura independentes.
static func box(mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3.ONE
	m.mesh = b
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


# ===========================================================================
# Linguagem visual por elemento
# ===========================================================================
# Cada elemento tem forma, movimento, rastro e impacto proprios (o projetil em
# si mora em `Projectile3D`). Aqui ficam as pecas que ele e o impacto
# compartilham: a paleta, particulas de billboard (`puff`), pedacos soltos com
# gravidade (`bit`), o anel de billboard (`ring_fx`) e os efeitos de boca e
# de impacto. Tudo e MeshInstance3D + Tween, sem GPUParticles3D (o caminho
# opengl3 e o mais fragil, e os testes rodam nele).

const P_CORE := 0
const P_MID := 1
const P_DEEP := 2

## [nucleo quente, tom medio, tom profundo] de cada elemento. Os tons medios
## acompanham `CardData.ELEMENT_COLOR`; o fogo e puxado para o laranja porque o
## vermelho puro some contra a lava.
const PAL := {
	CardData.Element.FIRE: [Color("fff1c9"), Color("ff9a2e"), Color("e2553b")],
	CardData.Element.WATER: [Color("e6f7ff"), Color("4aa8ff"), Color("2a62c8")],
	CardData.Element.EARTH: [Color("c8a070"), Color("8a5a3b"), Color("5a3a22")],
	CardData.Element.FROST: [Color("f6ffff"), Color("bfeeff"), Color("7cc4e8")],
	CardData.Element.SHADOW: [Color("2a1244"), Color("9a5cff"), Color("5a2a9a")],
}

static var _shard: Mesh = null
static var _cone: Mesh = null
static var _cube: Mesh = null
static var _drop: Mesh = null


static func has_style(element: int) -> bool:
	return PAL.has(element)


static func pal(element: int, which: int) -> Color:
	var p: Array = PAL.get(element, PAL[CardData.Element.FIRE])
	return p[which]


## Piramide de 4 lados, ponta em +Y, altura 1 e base de raio 0.5. E o estilhaco
## de gelo e o cristal do projetil de gelo.
static func shard_mesh() -> Mesh:
	if _shard == null:
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 0.5
		c.height = 1.0
		c.radial_segments = 4
		c.rings = 1
		_shard = c
	return _shard


## Cone redondo (7 lados): a labareda do fogo.
static func cone_mesh() -> Mesh:
	if _cone == null:
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 0.5
		c.height = 1.0
		c.radial_segments = 7
		c.rings = 1
		_cone = c
	return _cone


static func cube_mesh() -> Mesh:
	if _cube == null:
		var b := BoxMesh.new()
		b.size = Vector3.ONE
		_cube = b
	return _cube


static func drop_mesh() -> Mesh:
	if _drop == null:
		var s := SphereMesh.new()
		s.radius = 0.5
		s.height = 1.0
		s.radial_segments = 8
		s.rings = 4
		_drop = s
	return _drop


static func _rdir(up_bias := 0.0) -> Vector3:
	return Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0) + up_bias,
		randf_range(-1.0, 1.0)).normalized()


## Particula de billboard: nasce em [pos], anda [vel] * [life] (freando), cresce
## ate [grow] vezes e some. [grow] < 1 encolhe. Com [additive] falso o blend e
## MIX, que e o que faz poeira e sombra escurecerem em vez de acenderem.
static func puff(parent: Node, pos: Vector3, color: Color, size: float,
		vel: Vector3, life: float, grow := 2.0, additive := true,
		tex: Texture2D = null) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var m := billboard_quad(size, tex if tex != null else soft_dot(), color,
		additive)
	m.position = pos
	parent.add_child(m)
	var tw := m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "position", pos + vel * life, life) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "scale", Vector3.ONE * grow, life)
	tw.tween_property(m, "transparency", 1.0, life * 0.7).set_delay(life * 0.3)
	tw.chain().tween_callback(m.queue_free)


## Pedaco solido com gravidade: rocha, gota, estilhaco. A trajetoria e a
## parabola exata (`tween_method`), nao um tween linear. [aligned] aponta o +Y
## do pedaco na direcao da velocidade (estilhaco de gelo) e dispensa o giro.
static func bit(parent: Node, mesh: Mesh, mat: Material, pos: Vector3,
		vel: Vector3, life: float, gravity := 9.0, sc := Vector3.ONE,
		spin := 6.0, aligned := false) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position = pos
	if aligned and vel.length_squared() > 0.0001:
		m.basis = Basis(Quaternion(Vector3.UP, vel.normalized()))
	else:
		m.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	m.scale = sc
	parent.add_child(m)
	# o tween nasce no pedaco: se o pai morrer no meio, ele morre junto
	var tw := m.create_tween()
	tw.set_parallel(true)
	tw.tween_method(func(t: float) -> void:
		m.position = pos + vel * t + Vector3(0, -0.5 * gravity * t * t, 0),
		0.0, life, life)
	if not aligned:
		tw.tween_property(m, "rotation", m.rotation + Vector3(
			randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)) * spin, life)
	tw.tween_property(m, "scale", Vector3.ZERO, life * 0.4) \
		.set_delay(life * 0.6)
	tw.chain().tween_callback(m.queue_free)


## Anel de billboard de raio [r0] a [r1]. Serve para onda (r0 < r1) e para
## implosao (r0 > r1): em ambos o fade pega a segunda metade do tempo.
static func ring_fx(parent: Node, pos: Vector3, color: Color, r0: float,
		r1: float, time: float, additive := true) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var m := billboard_quad(1.0, ring_tex(), color, additive)
	m.position = pos
	m.scale = Vector3.ONE * r0 * 2.0
	parent.add_child(m)
	var tw := m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3.ONE * r1 * 2.0, time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "transparency", 1.0, time * 0.6) \
		.set_delay(time * 0.4)
	tw.chain().tween_callback(m.queue_free)


# --- impacto por elemento ---------------------------------------------------

## O que acontece onde o tiro pousa. [amount] (o ATK) escala tudo. [big] e o
## impacto contra o jogador: o ponto fica perto do canto da tela, onde o HUD
## desenha por cima, entao o clarao sai ~1.7x maior e ganha um segundo flash
## para continuar legivel mesmo meio coberto.
static func impact(parent: Node, pos: Vector3, element: int, amount: int,
		big := false) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var sz := (0.9 + 0.16 * float(maxi(amount, 1))) * (1.7 if big else 1.0)
	match element:
		CardData.Element.FIRE:
			_imp_fire(parent, pos, sz)
		CardData.Element.WATER:
			_imp_water(parent, pos, sz)
		CardData.Element.EARTH:
			_imp_earth(parent, pos, sz)
		CardData.Element.FROST:
			_imp_frost(parent, pos, sz)
		CardData.Element.SHADOW:
			_imp_shadow(parent, pos, sz)
		_:
			flash(parent, pos, Color(1, 0.85, 0.6), 0.5 * sz)
			ring_fx(parent, pos, Color(1, 0.85, 0.6, 0.9), 0.1 * sz, 0.6 * sz, 0.25)
	if big:
		var mid := pal(element, P_MID)
		flash(parent, pos, Color(mid, 0.9), 1.4 * sz, 0.4)


## Fogo: clarao quente, anel de choque CURTO e uma chuva de brasas que sobe.
static func _imp_fire(p: Node, pos: Vector3, sz: float) -> void:
	var core := pal(CardData.Element.FIRE, P_CORE)
	var mid := pal(CardData.Element.FIRE, P_MID)
	var deep := pal(CardData.Element.FIRE, P_DEEP)
	flash(p, pos, Color(core, 0.95), 0.50 * sz, 0.18)
	flash(p, pos, Color(mid, 0.85), 0.85 * sz, 0.28)
	ring_fx(p, pos, Color(deep.lerp(mid, 0.5), 0.9), 0.12 * sz, 0.62 * sz, 0.2)
	for i in 8 + int(3.0 * sz):
		var sp := randf_range(1.2, 3.2) * (0.7 + 0.3 * sz)
		puff(p, pos, mid.lerp(core, randf()), randf_range(0.09, 0.20) * sz,
			_rdir(0.5) * sp, randf_range(0.28, 0.5), 0.1)


## Agua: respingo. Anel lento e fino, coroa de bolhas e gotas que caem.
static func _imp_water(p: Node, pos: Vector3, sz: float) -> void:
	var core := pal(CardData.Element.WATER, P_CORE)
	var mid := pal(CardData.Element.WATER, P_MID)
	flash(p, pos, Color(mid, 0.8), 0.45 * sz, 0.22)
	ring_fx(p, pos, Color(core, 0.9), 0.10 * sz, 0.75 * sz, 0.4)
	ring_fx(p, pos, Color(mid, 0.7), 0.05 * sz, 0.5 * sz, 0.3)
	for i in 4:
		var a := TAU * float(i) / 4.0 + randf() * 0.6
		puff(p, pos, Color(mid, 0.8), 0.14 * sz,
			Vector3(cos(a), 0.4, sin(a)) * 0.9 * sz, 0.4, 1.8, true, ring_tex())
	# gotas: translucidas, sobem e CAEM (gravidade de verdade)
	var dm := glow_mat(null, Color(0.55, 0.8, 1.0, 0.85), false)
	for i in 6 + int(2.0 * sz):
		var s := randf_range(0.05, 0.10) * (0.7 + 0.3 * sz)
		var out := Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)) \
			* randf_range(0.6, 1.5) * (0.7 + 0.3 * sz)
		bit(p, drop_mesh(), dm, pos, out + Vector3(0, randf_range(2.0, 3.6), 0),
			0.6, 9.0, Vector3(s, s * 1.3, s), 0.0)


## Terra: nuvem de poeira (blend MIX, escurece) e fragmentos de rocha pesados.
static func _imp_earth(p: Node, pos: Vector3, sz: float) -> void:
	var core := pal(CardData.Element.EARTH, P_CORE)
	var mid := pal(CardData.Element.EARTH, P_MID)
	var deep := pal(CardData.Element.EARTH, P_DEEP)
	flash(p, pos, Color(core, 0.55), 0.45 * sz, 0.14)
	puff(p, pos, Color(core.lerp(mid, 0.4), 0.7), 0.5 * sz, Vector3(0, 0.3, 0),
		0.8, 2.6, false)
	for i in 5 + int(sz):
		var a := randf() * TAU
		puff(p, pos, Color(core.lerp(mid, randf() * 0.7), 0.55),
			randf_range(0.3, 0.5) * sz,
			Vector3(cos(a) * 1.0, randf_range(0.2, 0.7), sin(a) * 1.0) * sz * 0.7,
			randf_range(0.55, 0.85), 2.4, false)
	for i in 4 + int(1.5 * sz):
		var s := randf_range(0.06, 0.13) * (0.7 + 0.3 * sz)
		var mat := solid_mat(mid.lerp(deep, randf()), 0.95)
		bit(p, cube_mesh(), mat, pos, Vector3(randf_range(-1.6, 1.6) * sz * 0.7,
			randf_range(2.5, 4.2), randf_range(-1.6, 1.6) * sz * 0.7),
			0.75, 10.0, Vector3(s, s * randf_range(0.6, 1.2), s), 8.0)


## Gelo: estilhacos que irradiam e um anel palido, nitido e rapido.
static func _imp_frost(p: Node, pos: Vector3, sz: float) -> void:
	var core := pal(CardData.Element.FROST, P_CORE)
	var mid := pal(CardData.Element.FROST, P_MID)
	var deep := pal(CardData.Element.FROST, P_DEEP)
	flash(p, pos, Color(core, 0.95), 0.40 * sz, 0.14)
	ring_fx(p, pos, Color(mid, 0.95), 0.10 * sz, 0.66 * sz, 0.26)
	var sm := glow_mat(null, Color(core.lerp(mid, 0.4), 0.95), true)
	var n := 7 + int(sz * 1.5)
	for i in n:
		# irradia num disco virado para a camera (XY), com um pouco de Z
		var a := TAU * float(i) / float(n) + randf_range(-0.2, 0.2)
		var dir := Vector3(cos(a), sin(a), randf_range(-0.3, 0.3)).normalized()
		var s := randf_range(0.05, 0.08) * (0.7 + 0.3 * sz)
		bit(p, shard_mesh(), sm, pos, dir * randf_range(2.2, 3.6) * (0.7 + 0.3 * sz),
			0.42, 2.0, Vector3(s, s * 4.5, s), 0.0, true)
	for i in 5:
		puff(p, pos, Color(deep.lerp(core, randf()), 0.9), 0.07 * sz,
			_rdir() * 1.2, 0.4, 0.2)


## Sombra: IMPLOSAO primeiro (anel e fiapos puxados para dentro, um miolo
## escuro), e so depois o estouro roxo -- e o que a diferencia de um simples
## clarao roxo.
static func _imp_shadow(p: Node, pos: Vector3, sz: float) -> void:
	var mid := pal(CardData.Element.SHADOW, P_MID)
	var deep := pal(CardData.Element.SHADOW, P_DEEP)
	const T_IN := 0.2
	ring_fx(p, pos, Color(mid, 0.95), 0.9 * sz, 0.08 * sz, T_IN)
	for i in 8:
		var off := _rdir() * 0.75 * sz
		puff(p, pos + off, Color(mid.lerp(deep, randf()), 0.9), 0.14 * sz,
			-off / T_IN, T_IN, 0.3)
	puff(p, pos, Color(0.02, 0.0, 0.05, 0.9), 0.34 * sz, Vector3.ZERO, T_IN,
		0.4, false)
	var holder := Node3D.new()
	parent_add(p, holder)
	var tw := holder.create_tween()
	tw.tween_interval(T_IN)
	tw.tween_callback(_shadow_burst.bind(p, pos, sz))
	tw.tween_callback(holder.queue_free)


static func parent_add(p: Node, n: Node) -> void:
	if p != null and is_instance_valid(p):
		p.add_child(n)


static func _shadow_burst(p: Node, pos: Vector3, sz: float) -> void:
	if p == null or not is_instance_valid(p):
		return
	var core := Color(0.9, 0.75, 1.0)
	var mid := pal(CardData.Element.SHADOW, P_MID)
	var deep := pal(CardData.Element.SHADOW, P_DEEP)
	flash(p, pos, Color(mid, 0.95), 0.95 * sz, 0.3)
	flash(p, pos, Color(core, 0.8), 0.4 * sz, 0.16)
	ring_fx(p, pos, Color(mid, 0.95), 0.1 * sz, 0.9 * sz, 0.32)
	for i in 9:
		puff(p, pos, Color(mid.lerp(deep, randf()), 0.9), randf_range(0.12, 0.22) * sz,
			_rdir() * randf_range(1.4, 2.8) * (0.7 + 0.3 * sz), 0.45, 0.3)
	for i in 3:
		puff(p, pos, Color(0.03, 0.0, 0.07, 0.7), 0.3 * sz,
			_rdir() * 1.0 * sz, 0.5, 1.8, false)


# --- boca do tiro ------------------------------------------------------------

## Efeito curto no `muzzle_position()` da criatura, na mesma linguagem do
## projetil do elemento. [dir] e a direcao do tiro (nao precisa ser unitario).
static func muzzle(parent: Node, pos: Vector3, dir: Vector3, element: int,
		amount: int) -> void:
	if parent == null or not is_instance_valid(parent) or not has_style(element):
		return
	var s := 0.75 + 0.09 * float(maxi(amount, 1))
	var d := dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	var core := pal(element, P_CORE)
	var mid := pal(element, P_MID)
	match element:
		CardData.Element.FIRE:
			flash(parent, pos, Color(mid, 0.9), 0.30 * s, 0.14)
			for i in 5:
				puff(parent, pos, mid.lerp(core, randf()), 0.08 * s,
					d * 2.2 + _rdir() * 0.9, 0.26, 0.1)
		CardData.Element.WATER:
			ring_fx(parent, pos, Color(core, 0.85), 0.04 * s, 0.26 * s, 0.22)
			var dm := glow_mat(null, Color(0.55, 0.8, 1.0, 0.85), false)
			for i in 3:
				bit(parent, drop_mesh(), dm, pos, d * 1.2 + _rdir() * 0.8 + Vector3.UP,
					0.3, 8.0, Vector3.ONE * 0.05 * s, 0.0)
		CardData.Element.EARTH:
			puff(parent, pos, Color(core.lerp(mid, 0.4), 0.6), 0.3 * s,
				d * 0.5 + Vector3.UP * 0.3, 0.4, 2.2, false)
			for i in 2:
				bit(parent, cube_mesh(), solid_mat(mid, 0.95), pos,
					d * 1.0 + _rdir() * 0.8 + Vector3.UP * 1.2, 0.35, 9.0,
					Vector3.ONE * 0.06 * s, 6.0)
		CardData.Element.FROST:
			flash(parent, pos, Color(core, 0.85), 0.24 * s, 0.12)
			var sm := glow_mat(null, Color(core, 0.95), true)
			for i in 4:
				bit(parent, shard_mesh(), sm, pos, d * 2.4 + _rdir() * 0.9, 0.24,
					0.0, Vector3(0.04, 0.2, 0.04) * s, 0.0, true)
		CardData.Element.SHADOW:
			# fiapos sendo PUXADOS para a boca, o inverso do fogo
			for i in 3:
				var off := _rdir() * 0.35 * s
				puff(parent, pos + off, Color(mid, 0.9), 0.1 * s, -off / 0.16,
					0.16, 0.3)
			flash(parent, pos, Color(mid, 0.7), 0.22 * s, 0.14)
