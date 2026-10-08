class_name Board3D
extends Node3D

## Monta as 12 tiles em 3D e mantém a cena em sincronia com o [Game]: entidades
## que aparecem, levam dano e morrem viram animação aqui.

signal tile_clicked(col: int, row: int)

## Espaçamento entre linhas/colunas. Reduzido em 30%: com a laje em 2.05 o
## tabuleiro ficava espalhado e o slime — que ocupa ~1 unidade — seemedo
## perdido no meio da tile.
const TILE_Z := 1.44     ## espaçamento entre linhas
const TILE_X := 1.44     ## espaçamento entre colunas

var _tiles: Array[Tile3D] = []
var _entities: Dictionary = {}    ## Vector2i(col,row) -> Entity3D
var _camera: Camera3D


func setup(p_camera: Camera3D) -> void:
	_camera = p_camera
	_build()


func _build() -> void:
	for row in Board.ROWS:
		for col in Board.COLS:
			var t := Tile3D.create(col, row)
			t.position = _tile_position(col, row)
			add_child(t)
			t.clicked.connect(func(c: int, r: int) -> void: tile_clicked.emit(c, r))
			_tiles.append(t)


func _tile_position(col: int, row: int) -> Vector3:
	var x := (col - (Board.COLS - 1) * 0.5) * TILE_X
	# linha 1 e 2 (frentes) ficam mais perto do centro do tabuleiro
	var z := (row - (Board.ROWS - 1) * 0.5) * TILE_Z
	return Vector3(x, 0, z)


## Nó 3D da entidade em (col,row), ou null. A fase de farm usa para descobrir
## qual criatura disparou e mandar ela [method Entity3D.shoot_at].
func entity_node(col: int, row: int) -> Entity3D:
	var e: Entity3D = _entities.get(Vector2i(col, row))
	if e != null and not is_instance_valid(e):
		return null
	return e


## Faz TODAS as criaturas de um lado brilharem. É o bônus da fase de farm virando
## gesto no tabuleiro: +1 ATK tem que se ver nas criaturas que vão levar isso no
## brawl logo em seguida, e não só num número de HUD.
func pulse_side(side: int, color: Color) -> void:
	for key in _entities:
		var e: Entity3D = _entities[key]
		if e == null or not is_instance_valid(e) or e.entity == null:
			continue
		if e.entity.owner_side != side or not e.entity.card().is_creature():
			continue
		e.pulse(color)

## Limpa a cena inteira: criaturas e terreno.
##
## Precisa existir porque o `Game.start_game()` troca o `Board` por um objeto
## NOVO. Os `Entity3D` da partida antiga continuam apontando para entidades do
## tabuleiro velho, que não estão mortas — então o [sync] as considers vivas
## para sempre e os slimes ficam na tela depois do REINICIAR.
func reset() -> void:
	for key in _entities:
		var e: Entity3D = _entities[key]
		e.queue_free()
	_entities.clear()
	for t in _tiles:
		t.set_terrain(-1)
		t.set_highlight(0)
		t.set_hovered(false)


func tile_at(col: int, row: int) -> Tile3D:
	for t in _tiles:
		if t.col == col and t.row == row:
			return t
	return null


## Pisca a tile. É o que diz "o golpe caiu AQUI" sem depender do número
## flutuante, que some rápido demais para quem olha o canto da tela.
func pulse(col: int, row: int, color: Color) -> void:
	var t := tile_at(col, row)
	if t:
		t.flash(color)


## Reconstrói a cena a partir do estado. Usa o uid da entidade pra saber o que
## é novo, o que saiu e o que mudou, em vez de diffing feio.
func sync(game: Game, events: Array) -> void:
	# terreno
	for t in _tiles:
		t.set_terrain(game.board.get_terrain(t.col, t.row))

	# remove entidades que saíram
	for key in _entities.keys():
		var e: Entity3D = _entities[key]
		if e.entity == null or e.entity.is_dead():
			e.die(func() -> void: _entities.erase(key))

	# cria/atualiza as novas
	for row in Board.ROWS:
		for col in Board.COLS:
			var be := game.board.get_entity(col, row)
			var key := Vector2i(col, row)
			if be == null:
				continue
			if _entities.has(key):
				continue
			var node := Entity3D.create(be)
			node.position = _tile_position(col, row)
			add_child(node)
			_entities[key] = node
			# entrada: a carta "cai" na tile
			var target_y := _tile_position(col, row).y
			node.position.y = target_y + 1.4
			node.scale = Vector3.ONE * 0.2
			var tw := node.create_tween()
			tw.set_parallel(true)
			tw.tween_property(node, "position:y", target_y, 0.35) \
				.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			tw.tween_property(node, "scale", Vector3.ONE, 0.3) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# reage aos eventos do turno
	for ev in events:
		match ev.get("type", ""):
			"damage":
				var k := Vector2i(ev["col"], ev["row"])
				if _entities.has(k):
					(_entities[k] as Entity3D).hit()
				# o atacante avança na direção de quem apanhou: o dado `from_col`
				#/`from_row` é quem bateu, e sem ele a cena não tem como mostrar
				# o "avança livre" da regra
				if ev.has("from_col"):
					var ak := Vector2i(ev["from_col"], ev["from_row"])
					if _entities.has(ak):
						var atk: Entity3D = _entities[ak]
						var dx := float(ev["col"] - ev["from_col"])
						var dz := float(ev["row"] - ev["from_row"])
						atk.attack()
						atk.lunge(dx, dz)
			"death":
				var k2 := Vector2i(ev["col"], ev["row"])
				if _entities.has(k2):
					(_entities[k2] as Entity3D).die()


## Pilhas de baralho/descarte ao fundo do tabuleiro: caixas empilhadas com a
## cor do jogador. Antes eram rótulos de texto soltos, que não diziam nada
## sobre o estado do baralho.
func set_deck_top(parent: Node, count: int, accent: Color) -> void:
	for c in parent.get_children():
		parent.remove_child(c)
		c.queue_free()
	if count <= 0:
		return
	const W := 42.0
	var layers := clampi(ceil(float(count) / 5.0), 1, 6)
	for i in layers:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(W, 4.0, W * 0.72)
		m.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = accent.darkened(0.15 + 0.09 * float(i))
		mat.roughness = 0.85
		m.material_override = mat
		m.position = Vector3(0, 4.0 * (float(i) + 0.5), 0)
		parent.add_child(m)


func set_highlights(selected_card: CardData, pending_spell: int, game: Game) -> void:
	for t in _tiles:
		var kind := 0
		if pending_spell >= 0:
			var spell := CardDB.get_card(game.player().hand[pending_spell])
			var valid := Rules.spell_targets(game.board, Board.Side.PLAYER, spell)
			kind = 1 if valid.has(Vector2i(t.col, t.row)) else 2
		elif selected_card != null:
			if t.is_player_side:
				var reason := Rules.can_place(game.board, Board.Side.PLAYER,
					selected_card, t.col, t.row)
				kind = 1 if reason == Rules.OK else 2
		t.set_highlight(kind)
