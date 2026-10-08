class_name Tile3D
extends Node3D

## Uma tile do tabuleiro em 3D: uma laje com espessura que pega luz, o terreno
## pintado por cima, e o realce de legal/ilegal.

signal clicked(col: int, row: int)

const SIZE := Vector2(1.33, 1.33)
## As peças de terreno acompanham o encolhimento da tile. Sem isto elas
## continuariam do tamanho antigo e ficariam enormes em relação à laje.
const PROP_SCALE := 0.7
const HEIGHT := 0.18

var col: int = 0
var row: int = 0
var is_front: bool = true
var is_player_side: bool = true

var _slab: MeshInstance3D
var _mat_slab: StandardMaterial3D
var _cap: MeshInstance3D
var _glow: MeshInstance3D
var _mat_glow: StandardMaterial3D

var _highlight: int = 0        ## 0 nenhuma, 1 válido, 2 inválido
var _pulse: float = 0.0
var _hovered: bool = false
var _shock_glow: MeshInstance3D
var _mat_shock: StandardMaterial3D
var _shock_pulse: float = 0.0
## flash de impacto: 0 = nada, 1 = pico. Decai em `_process`.
var _flash: float = 0.0
var _flash_color := Color(1, 1, 1)
var _mat_flash: StandardMaterial3D
var _flash_mesh: MeshInstance3D
var _props: Array[MeshInstance3D] = []
var _terrain_element: int = -2


func flash(color: Color) -> void:
	_flash = 1.0
	_flash_color = color


static func create(p_col: int, p_row: int) -> Tile3D:
	var t := Tile3D.new()
	t.col = p_col
	t.row = p_row
	return t


func _ready() -> void:
	is_front = Board.is_front_row(row)
	is_player_side = Board.side_of_row(row) == Board.Side.PLAYER
	_build()
	set_process(true)


func _build() -> void:
	# --- laje ---
	_mat_slab = StandardMaterial3D.new()
	_mat_slab.albedo_color = Color("2b2736") if is_front else Color("221f2b")
	_mat_slab.roughness = 0.9

	var mesh := BoxMesh.new()
	mesh.size = Vector3(SIZE.x, HEIGHT, SIZE.y)
	_slab = MeshInstance3D.new()
	_slab.mesh = mesh
	_slab.material_override = _mat_slab
	add_child(_slab)

	# --- topo ---
	# Não há mais imagem de terreno. Antes era um quad com o PNG colado por cima
	# da laje: ficava com cara de adesivo, brigava com as peças 3D e era a
	# única coisa que denunciava a origem raster. Agora a própria laje é tingida
	# pelo elemento (ver [set_terrain]) e o volume vem das peças.
	var top := BoxMesh.new()
	top.size = Vector3(SIZE.x * 0.99, 0.03, SIZE.y * 0.99)
	_cap = MeshInstance3D.new()
	_cap.mesh = top
	_cap.material_override = _mat_slab
	_cap.position = Vector3(0, HEIGHT * 0.5 + 0.008, 0)
	add_child(_cap)

	# --- realce de alvo ---
	_mat_glow = StandardMaterial3D.new()
	_mat_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat_glow.albedo_color = Color(1, 1, 1, 0)
	var gquad := QuadMesh.new()
	gquad.size = SIZE - Vector2(0.12, 0.12)
	_glow = MeshInstance3D.new()
	_glow.mesh = gquad
	_glow.material_override = _mat_glow
	_glow.rotation_degrees = Vector3(-90, 0, 0)
	_glow.position = Vector3(0, HEIGHT * 0.5 + 0.008, 0)
	add_child(_glow)

	# --- flash de impacto ---
	_mat_flash = StandardMaterial3D.new()
	_mat_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_flash.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat_flash.albedo_color = Color(1, 1, 1, 0)
	var fquad := QuadMesh.new()
	fquad.size = SIZE - Vector2(0.06, 0.06)
	_flash_mesh = MeshInstance3D.new()
	_flash_mesh.mesh = fquad
	_flash_mesh.material_override = _mat_flash
	_flash_mesh.rotation_degrees = Vector3(-90, 0, 0)
	_flash_mesh.position = Vector3(0, HEIGHT * 0.5 + 0.016, 0)
	add_child(_flash_mesh)

	# --- brilho da linha de choque (só nas linhas de frente) ---
	if is_front:
		_mat_shock = StandardMaterial3D.new()
		_mat_shock.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_shock.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_shock.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_mat_shock.albedo_color = Color(0.55, 0.42, 0.95, 0.0)
		var squad := QuadMesh.new()
		squad.size = Vector2(SIZE.x, 0.14)
		_shock_glow = MeshInstance3D.new()
		_shock_glow.mesh = squad
		_shock_glow.material_override = _mat_shock
		_shock_glow.rotation_degrees = Vector3(-90, 0, 0)
		# encosta na borda que dá de frente para o adversário
		var z := SIZE.y * 0.5 - 0.07 if is_player_side else -SIZE.y * 0.5 + 0.07
		_shock_glow.position = Vector3(0, HEIGHT * 0.5 + 0.012, z)
		add_child(_shock_glow)


## Terreno = cor do elemento na laje + peças 3D por cima. Não há imagem: um
## decalque chapado ficava com cara de adesivo e brigava com o volume.
func set_terrain(element: int) -> void:
	if _terrain_element == element:
		return
	_terrain_element = element
	_clear_props()

	if element < 0:
		_mat_slab.albedo_color = Color("2b2736") if is_front else Color("221f2b")
		return

	# escurecido o bastante para as peças 3D se destacarem, claro o bastante
	# para o elemento ser legível de relance
	_mat_slab.albedo_color = CardData.ELEMENT_COLOR[element].darkened(0.55)

	var base := HEIGHT * 0.5
	# Props baixos e encostados nas bordas: o centro da tile é do BOARD de
	# verdade (uma criatura fica em pé ali), então nada de pieceira alta no meio.
	match element:
		CardData.Element.EARTH:
			# pedras achatadas nos cantos
			_prop(BoxMesh, Vector3(0.5, 0.12, 0.42), Vector3(-0.52, base + 0.06, 0.2), 0.3, Color("6b5f4c"))
			_prop(BoxMesh, Vector3(0.36, 0.1, 0.3), Vector3(0.55, base + 0.05, -0.3), -0.5, Color("7a6b53"))
			_prop(BoxMesh, Vector3(0.28, 0.08, 0.26), Vector3(0.3, base + 0.04, 0.56), 0.7, Color("5c5243"))
		CardData.Element.WATER:
			# poça rasa, só a borda
			_prop(CylinderMesh, Vector3(1.4, 0.05, 1.4), Vector3(0, base + 0.025, 0), 0.0, Color("2a6ea8"), 0.62)
			_prop(CylinderMesh, Vector3(1.0, 0.04, 1.0), Vector3(0, base + 0.05, 0), 0.0, Color("57a8dd"), 0.5)
		CardData.Element.FIRE:
			# cratera rasa com a brasa no meio (baixa, não um pilar)
			_prop(CylinderMesh, Vector3(1.2, 0.06, 1.2), Vector3(0, base + 0.03, 0), 0.0, Color("7a2410"), 1.0)
			_prop(CylinderMesh, Vector3(0.8, 0.04, 0.8), Vector3(0, base + 0.07, 0), 0.0, Color("e85a1e"), 0.9)
			# labaredas nos cantos, não no meio
			_prop(CylinderMesh, Vector3(0.22, 0.2, 0.22), Vector3(-0.55, base + 0.1, -0.5), 0.0, Color("ff9b2f"), 0.85)
			_prop(CylinderMesh, Vector3(0.18, 0.14, 0.18), Vector3(0.6, base + 0.07, 0.55), 0.0, Color("ffb04a"), 0.8)
		CardData.Element.FROST:
			# cristais nos cantos
			_prop(CylinderMesh, Vector3(0.18, 0.34, 0.18), Vector3(-0.58, base + 0.17, -0.42), 0.14, Color("bfe4f5"), 0.85)
			_prop(CylinderMesh, Vector3(0.15, 0.26, 0.15), Vector3(0.6, base + 0.13, -0.5), -0.2, Color("9fd0ea"), 0.8)
			_prop(CylinderMesh, Vector3(0.12, 0.2, 0.12), Vector3(0.5, base + 0.1, 0.58), 0.3, Color("e4f6ff"), 0.75)
		CardData.Element.SHADOW:
			# obelisco atrás e fissura no chão
			_prop(BoxMesh, Vector3(0.28, 0.4, 0.28), Vector3(-0.58, base + 0.2, -0.5), 0.1, Color("#3a2a52"))
			_prop(BoxMesh, Vector3(0.13, 0.28, 0.13), Vector3(-0.54, base + 0.14, -0.46), -0.14, Color("#8f6ed6"), 0.9)
			_prop(BoxMesh, Vector3(0.7, 0.04, 0.7), Vector3(0.4, base + 0.02, 0.4), 0.3, Color("#241a36"))


func _prop(mesh_type: Variant, size: Vector3, pos: Vector3, tilt: float,
		color: Color, alpha := 1.0) -> void:
	var m := MeshInstance3D.new()
	if mesh_type == BoxMesh:
		var b := BoxMesh.new()
		b.size = size * PROP_SCALE
		m.mesh = b
	else:
		var c := CylinderMesh.new()
		c.top_radius = size.x * 0.5 * PROP_SCALE
		c.bottom_radius = size.x * 0.5 * PROP_SCALE
		c.height = size.y * PROP_SCALE
		m.mesh = c
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.roughness = 0.75
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material_override = mat
	# tudo é achatado e encostado nos cantos: a criatura precisa ficar
	# visível, e ela ocupa o CENTRO da tile. Antes a cratera de lava (0.34 de
	# altura no centro) tapava a criatura inteira.
	# O Y sai de [pos.y] acima da laje e é escalado separado, senão a peça
	# afundaria dentro do chão quando a tile encolhe.
	var base := HEIGHT * 0.5
	m.position = Vector3(pos.x * PROP_SCALE,
		base + (pos.y - base) * PROP_SCALE, pos.z * PROP_SCALE)
	m.rotation_degrees = Vector3(tilt * 40.0, tilt * 70.0, 0)
	add_child(m)
	_props.append(m)


func _clear_props() -> void:
	for p in _props:
		remove_child(p)
		p.queue_free()
	_props.clear()


func set_highlight(kind: int) -> void:
	_highlight = kind


func _process(delta: float) -> void:
	_pulse += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.2)
		_mat_flash.albedo_color = Color(_flash_color.r, _flash_color.g,
			_flash_color.b, _flash * 0.75)
	# pulso só quando há realce (não gasta nada quando não está)
	var a := 0.0
	var col := Color(1, 1, 1, 0)
	match _highlight:
		1:
			a = 0.16 + 0.12 * sin(_pulse * 6.0)
			col = Color("5fe08a")
		2:
			a = 0.10
			col = Color("e05f5f")
	_mat_glow.albedo_color = Color(col.r, col.g, col.b, a)

	if _hovered and _highlight == 0:
		_mat_glow.albedo_color = Color(0.9, 0.9, 1.0, 0.10)

	# brilho da linha de choque: sempre ligado, pulsando devagar
	if _mat_shock:
		_shock_pulse += delta
		_mat_shock.albedo_color = Color(0.55, 0.42, 0.95,
			0.18 + 0.10 * sin(_shock_pulse * 2.2))


func set_hovered(on: bool) -> void:
	_hovered = on
