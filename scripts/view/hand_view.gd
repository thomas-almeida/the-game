class_name HandView
extends Node2D

## Mão de cartas em leque com perspectiva 3D de verdade.
##
## Por que não usar um nó 3D: vários quads texturizados quase coplanares numa
## mão não renderizavam de forma confiável — apareciam uma ou três das cinco
## cartas, sem erro no console, em três APIs diferentes (QuadMesh, Sprite3D,
## no_depth_test). Aqui a projeção dos 4 cantos de cada carta é calculada em
## GDScript e a carta é desenhada como um polígono texturizado. É a mesma
## conta de uma câmera pinhole, o resultado é determinístico, e dá o que
## importa: o topo da carta fica mais estreito que a base, o hover levanta e
## endireita, e o ponteiro inclina.
##
## Não há descrição no hover: o painel de leitura abre só no clique.

const FOV := 50.0
const CAM_D := 620.0
## tamanho da carta no mundo. Compensa CAM_D: o tamanho aparente na tela é
## inverso à distância, então aumentar a distância encolhe a carta.
const CARD := Vector2(84, 121)
const UV := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]

var face_down: bool = false
var selected: int = -1
## Inclinação de repouso. 0 = carta totalmente de frente (em pé); ~1.2 = deitada
## na mesa. O padrão é baixo de propósito: era o `base_pitch` alto que fazia as
## cartas parecerem dormidas, e não a perspectiva.
var base_pitch := 0.13
var hover_pitch := 0.04
## Tilt estilo react-tilt: inclinação máxima quando o ponteiro está na borda da
## carta. Sinal escolhido para a borda sob o ponteiro AVANÇAR (a carta parece
## seguir o cursor); CAM_D curto é o que faz essa borda crescer de verdade.
var tilt_max := 0.50
## Brilho especular que segue o ponteiro (o "glare" do react-tilt). 0 desliga.
var glare := 0.20
var card_scale := 1.0

var _ids: Array[StringName] = []
var _playable := {}
var _hovered: int = -1
var _hover_tilt := Vector2.ZERO
var _hover_off := Vector2.ZERO
var _lift := {}          ## índice -> 0..1, interpolado
var _anchor := Vector2.ZERO
var _span := 1.0

## Só para testes automatizados: força a posição do ponteiro, porque
## `Input.warp_mouse()` não move o cursor nesta máquina.
var mouse_override: Variant = null


func _init(p_face_down := false) -> void:
	face_down = p_face_down
	z_index = 0


func setup(anchor_ratio: Vector2, span_ratio: float) -> void:
	_anchor = anchor_ratio
	_span = span_ratio


func set_cards(ids: Array[StringName]) -> void:
	_ids = ids
	# uma entrada por carta: `_process` itera pelo dicionário, então uma carta
	# sem entrada nunca anima
	_lift.clear()
	for i in ids.size():
		_lift[i] = 0.0
	# a mão encolhe ao jogar uma carta; um índice de hover antigo passaria
	# batendo fora da faixa no clique seguinte
	if _hovered >= ids.size():
		_hovered = -1
	if selected >= ids.size():
		selected = -1
	queue_redraw()


func set_playable(indices: Array) -> void:
	_playable.clear()
	for i in indices:
		_playable[i] = true
	queue_redraw()


func set_selected(index: int) -> void:
	if selected != index:
		selected = index
		queue_redraw()


func hovered_index() -> int:
	return _hovered


func _f() -> float:
	return 1.0 / tan(deg_to_rad(FOV) * 0.5)


## Projeta um ponto do mundo da mão para a tela.
func _project(p: Vector3, s: Vector2) -> Vector2:
	var z := CAM_D - p.z
	if z <= 1.0:
		z = 1.0
	var f := _f()
	return Vector2(
		s.x * 0.5 + p.x * f / z * s.x * 0.5,
		s.y * 0.5 + p.y * f / z * s.y * 0.5)


## Inverso: onde o mundo precisa estar para aparecer em (sx, sy).
func _world_at(sx: float, sy: float, z: float, s: Vector2) -> Vector3:
	var f := _f()
	var depth := CAM_D - z
	return Vector3(
		(sx - s.x * 0.5) * depth / (f * s.x * 0.5),
		(sy - s.y * 0.5) * depth / (f * s.y * 0.5),
		z)


func _process(delta: float) -> void:
	_pick_hover()
	# hover da IA não existe: o baralho dela é virado e não tem o que mostrar
	var want := _hovered if not face_down else -1
	for i in _ids.size():
		var t: float = 1.0 if i == want else 0.0
		_lift[i] = move_toward(_lift.get(i, 0.0), t, delta * 6.0)
	queue_redraw()


## Acha a carta sob o ponteiro e calcula o quanto o ponteiro está deslocado
## dentro dela, em -1..1. O deslocamento é medido nos CANTOS JÁ PROJETADOS, e
## não num retângulo imaginário: com as cartas sobrepostas num leque, o
## retângulo real da carta na tela é um trapézio, e é nele que o ponteiro
## precisa ser medido para o tilt responder certo.
func _pick_hover() -> void:
	var s := get_viewport_rect().size
	if _ids.is_empty() or face_down:
		if _hovered != -1:
			_hovered = -1
			_hover_tilt = Vector2.ZERO
		return

	var mouse: Vector2 = mouse_override if mouse_override != null \
		else get_viewport().get_mouse_position()

	# Primeiro: a carta de ONTOPO que contenha o ponteiro. Com o leque todo
	# sobreposto, "centro mais próximo" erra — o centro de uma carta fica
	# coberto pela seguinte, e o clique cairia na carta errada. A ordem de
	# desenho em `_draw` é a mesma pilha, então percorrer de trás para frente
	# devolve exatamente o que o jogador está vendo.
	var best := -1
	for i in range(_ids.size() - 1, -1, -1):
		if _contains(_corners(i, s), mouse):
			best = i
			break

	# Fora do leque: cai no centro mais próximo, dentro de um alcance curto.
	if best < 0:
		var best_d := 1e9
		for i in _ids.size():
			var c := _project(_card_world(i, s), s)
			var d := absf(mouse.x - c.x) + absf(mouse.y - c.y) * 0.55
			if d < best_d:
				best_d = d
				best = i
		if best_d > CARD.x * card_scale * 0.8:
			best = -1

	_hovered = best
	if best < 0:
		_hover_tilt = Vector2.ZERO
		_hover_off = Vector2.ZERO
		return

	var pts := _corners(best, s)
	var tl: Vector2 = pts[0]
	var tr: Vector2 = pts[1]
	var bl: Vector2 = pts[3]
	var br: Vector2 = pts[2]
	var centre: Vector2 = (tl + tr + br + bl) * 0.25
	var half_w: float = (tr - tl).length() * 0.5
	var half_h: float = (tl - bl).length() * 0.5
	# direção do mouse dentro da carta, normalizada
	var off := Vector2(
		(mouse.x - centre.x) / maxf(1.0, half_w),
		(mouse.y - centre.y) / maxf(1.0, half_h)).limit_length(1.0)
	# x -> guinada (a carta gira para o ponteiro), y -> tombadura
	_hover_off = off
	_hover_tilt = Vector2(-off.x * tilt_max, off.y * tilt_max)


## Posição e rotação 3D da carta [i].
func _card_world(i: int, s: Vector2) -> Vector3:
	var n := _ids.size()
	var h: float = _lift.get(i, 0.0)

	# cartas se espalham para a esquerda a partir da âncora (canto inferior
	# direito do jogador), e sobem um pouco as do meio
	var step := _step(s)
	var x_off := (i - (n - 1) * 0.5) * step
	var t := 0.0 if n <= 1 else (i - (n - 1) * 0.5) / ((n - 1) * 0.5)
	var arc := (1.0 - absf(t)) * 10.0

	var sx := _anchor.x * s.x - (n - 1 - i) * step
	var sy := _anchor.y * s.y - arc - h * 44.0
	var z := h * 95.0
	return _world_at(sx, sy, z, s)


## Cartas bem sobrepostas, como na referência: cada uma mostra só uma fatia
## da anterior, e a do hover vem para a frente.
func _step(s: Vector2) -> float:
	var n := maxi(_ids.size(), 1)
	var room := _span * s.x
	return clampf(room / float(n), CARD.x * 0.30, CARD.x * 0.78)


## O ponto está dentro do polígono projetado? (algoritmo do ponto no polígono
## com sinal cruzado — os quatro cantos já são um quad convexo.)
func _contains(pts: Array, p: Vector2) -> bool:
	var inside := false
	var j := pts.size() - 1
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[j]
		if (a.y > p.y) != (b.y > p.y):
			if p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x:
				inside = not inside
		j = i
	return inside


## Os quatro cantos projetados, em ordem TL, TR, BR, BL.
func _corners(i: int, s: Vector2) -> Array:
	var n := _ids.size()
	var h: float = _lift.get(i, 0.0)
	var t := 0.0 if n <= 1 else (i - (n - 1) * 0.5) / ((n - 1) * 0.5)

	# Repouso: carta em pé (base_pitch baixo), só com a inclinação lateral do
	# leque. No hover entra o tilt que segue o ponteiro.
	var pitch := lerpf(base_pitch, hover_pitch, h)
	var yaw := 0.0
	var roll := lerpf(t * 0.09, 0.0, h)

	if h > 0.0:
		yaw = _hover_tilt.x * h
		pitch += _hover_tilt.y * h

	var b := Basis.from_euler(Vector3(0, yaw, roll))
	b = b.rotated(Vector3(1, 0, 0), pitch)

	var centre := _card_world(i, s)
	var hw := CARD.x * 0.5 * card_scale
	var hh := CARD.y * 0.5 * card_scale
	var out: Array = []
	# TL, TR, BR, BL no espaço da carta (y para baixo, como na tela)
	for local in [Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)]:
		out.append(_project(b * Vector3(local.x, local.y, 0.0) + centre, s))
	return out


func _draw() -> void:
	if _ids.is_empty():
		return
	var s := get_viewport_rect().size

	# desenha de trás para frente; a carta em hover sempre por último
	var order: Array = []
	for i in _ids.size():
		order.append(i)
	if _hovered >= 0:
		order.erase(_hovered)
		order.append(_hovered)

	for i in order:
		var pts := _corners(i, s)
		var poly := PackedVector2Array(pts)
		var tex := _texture(i)
		if tex == null:
			continue

		var col := Color(1, 1, 1, 1)
		if face_down:
			col = Color(0.72, 0.72, 0.82)
		else:
			if not _playable.has(i):
				col = Color(0.46, 0.44, 0.56)
			# leve escurecimento nas cartas mais inclinadas do leque
			var t := absf((i - (_ids.size() - 1) * 0.5) / maxf(1.0, (_ids.size() - 1) * 0.5))
			var sh := t * 0.18
			col = Color(1 - sh, 1 - sh, 1 - sh * 0.8, 1)

		draw_polygon(poly, PackedColorArray([col, col, col, col]),
			PackedVector2Array(UV), tex)

		# Glare: um segundo polígono com brilho por vértice, centrado na direção
		# do ponteiro. `draw_polygon` aceita cor por vértice, então o gradiente
		# sai de graça — é o efeito especular do react-tilt.
		if i == _hovered and glare > 0.0:
			var h: float = _lift.get(i, 0.0)
			var g := PackedColorArray()
			# cantos TL, TR, BR, BL em -1..1
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var d: float = 1.0 - (corner - _hover_off).length() / 2.83
				g.append(Color(1, 1, 1, maxf(0.0, d) * glare * h))
			draw_polygon(poly, g, PackedVector2Array(UV))

		if i == selected and not face_down:
			var accent: Color = CardData.ELEMENT_COLOR[CardDB.get_card(_ids[i]).element]
			draw_polyline(_closed(poly), accent.lightened(0.35), 3.0, true)
			draw_polyline(_closed(poly), Color(accent.r, accent.g, accent.b, 0.4), 7.0, true)

		if not _playable.has(i) and not face_down:
			draw_polyline(_closed(poly), Color(0.55, 0.2, 0.2, 0.7), 2.0, true)


func _closed(p: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(p)
	out.append(p[0])
	return out


func _texture(i: int) -> Texture2D:
	if face_down:
		return CardFace.back_texture()
	return CardFace.texture_for(CardDB.get_card(_ids[i]))


## Índice da carta sob o ponteiro, ou -1.
func pick(mouse: Vector2) -> int:
	if face_down or _ids.is_empty():
		return -1
	return _hovered
