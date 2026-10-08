class_name Entity3D
extends Node3D

## Uma carta colocada no tabuleiro, de pé na tile.
##
## Criaturas são sprites do pacote `slime-mobs` (frames de 64x64) animados por
## uma máquina de estados simples: Idle em laço, Walk enquanto avançam, Attack
## no brawl, Hurt ao levar dano e Death no fim. Antes era um frame único e
## estático — nenhuma criatura se mexia.
##
## O slime é o mesmo art em três variantes, então a identidade visual vem do
## TINT por elemento: água azul, fogo laranja, terra marrom, gelo claro, sombra
## roxo. É o que dá dez criaturas legíveis com três modelos.
##
## Construções e terrenos continuam sendo um plano deitado com a arte da carta.

## O quadro do slime é 64x64, mas o CORPO só ocupa uns 19x22 pixels dentro
## dele (medido no PNG) — 30%. Então o `pixel_size` é bem maior que parece:
## com 0.05 o corpo sai com ~1.0 unidade, mais da metade da largura da tile
## (1.9), que é o porte certo para leitura imediata.
const SLIME_SCALE := 0.05
## Centro do sprite em espaço de mundo. O corpo vai do frame y=20 ao y=41, e o
## "chão" do quadro é y=32: com pixel_size 0.05, os pés ficam 0.45 abaixo do
## centro, então o centro vai em 0.52 para encostarem no topo da laje.
## (Antes era 0.55 com z = -0.35, o que deixava o sprite flutuando e puxado
## para fora do centro da tile — o usuário pediu para descer um pouco e
## centralizar.)
const SLIME_Y := 0.45
## Quadros por segundo de cada animação.
const FPS := {
	"Idle": 6.0, "Walk": 10.0, "Run": 12.0, "Attack": 14.0, "Hurt": 10.0,
	"Death": 12.0,
}

var entity: BoardEntity = null

var _sprite: Sprite3D
var _mat: StandardMaterial3D
var _shadow: MeshInstance3D
var _mat_shadow: StandardMaterial3D

var _flash: float = 0.0
## Brilho do bônus da fase de farm: tempo restante, cor e quanto acima do
## branco o sprite vai. Vive separado do `_flash` (que é o flash vermelho de
## dano) porque os dois podem acontecer juntos — o bônus chega logo depois do
## farm, com as criaturas ainda marcadas.
var _pulse_t: float = 0.0
var _pulse_color: Color = Color.WHITE
var _pulse_boost: float = 1.0
var _action: StringName = &"Idle"
var _frame: int = 0
var _acc: float = 0.0
var _looping := true
var _slime: int = 1
var _tint := Color(1, 1, 1)
var _dying := false
## Tweens que animam o Sprite3D. Um tween de `hit`/`lunge` continua rodando se
## a criatura morrer no meio, e aí ele tenta escrever num nó já liberado
## ("Trying to assign invalid previously freed instance"). São mortos na
## [_fade_out].
var _sprite_tween: Tween
## Callback de [die], guardado para a animação de Death usar no fim.
var _die_done: Callable
## Nó para efeitos visuais (impactos, etc.) — os tweens nascem aqui,
## então se o pai for liberado o tween morre junto e não escreve em
## objeto destruído.
var _fx: Node3D


static func create(e: BoardEntity) -> Entity3D:
	var n := Entity3D.new()
	n.entity = e
	return n


func _ready() -> void:
	var card := entity.card()

	# sombra: elipse achatada no chão, dá o peso da coisa no tabuleiro
	_mat_shadow = StandardMaterial3D.new()
	_mat_shadow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_shadow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_shadow.albedo_color = Color(0, 0, 0, 0.42)
	var sq := QuadMesh.new()
	sq.size = Vector2(0.95, 0.42)
	_shadow = MeshInstance3D.new()
	_shadow.mesh = sq
	_shadow.material_override = _mat_shadow
	_shadow.rotation_degrees = Vector3(-90, 0, 0)
	_shadow.position = Vector3(0, 0.10, 0.02)
	add_child(_shadow)

	# Nó para efeitos visuais (impactos, etc.) — os tweens nascem aqui,
	# então se o pai for liberado o tween morre junto e não escreve em
	# objeto destruído.
	_fx = Node3D.new()
	_fx.name = "Fx"
	add_child(_fx)

	if card.is_creature():
		_slime = clampi(card.slime, 1, 3)
		# 0.55 para o branco: a 0.45 a criatura de fogo sumia dentro do terreno de
		# lava, que é exatamente o par que a regra mais usa
		_tint = CardData.ELEMENT_COLOR[card.element].lerp(Color.WHITE, 0.55)

		_sprite = Sprite3D.new()
		_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		_sprite.shaded = false
		_sprite.double_sided = true
		_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		# o corpo do slime ocupa só o miolo do quadro: o centro precisa ficar alto o
		# suficiente para os pés encostarem no topo da laje (ver SLIME_Y); z = 0 no
		# centro da tile (era -0.35, o que empurrava o corpo para trás)
		_sprite.position = Vector3(0, SLIME_Y, 0.40)
		_sprite.render_priority = 1
		_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		_sprite.modulate = _tint
		add_child(_sprite)
		_apply_frame()
	else:
		# permanente: plano deitado na tile, com a arte da carta
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_mat.albedo_texture = CardDB.art(card.art)
		var q := QuadMesh.new()
		q.size = Vector2(0.9, 0.9)
		var m := MeshInstance3D.new()
		m.mesh = q
		m.material_override = _mat
		m.rotation_degrees = Vector3(-90, 0, 0)
		m.position = Vector3(0, 0.10, 0)
		add_child(m)
		_sprite = Sprite3D.new()   # placeholder para as animações comuns
		_sprite.visible = false
		add_child(_sprite)


## Troca a animação. [loop] false para as que tocam uma vez (Attack, Hurt,
## Death) — ao terminar elas voltam sozinhas para a anterior.
func play(action: StringName, loop := true, restart := true) -> void:
	if not entity.card().is_creature():
		return
	if action == _action and not restart:
		return
	_action = action
	_looping = loop
	_frame = 0
	_acc = 0.0
	_apply_frame()


func _apply_frame() -> void:
	if _sprite == null or _sprite.visible == false:
		return
	var count := CardDB.slime_frames(String(_action))
	_frame = clampi(_frame, 0, count - 1)
	_sprite.texture = CardDB.slime_frame(_slime, String(_action), _frame)
	_sprite.pixel_size = SLIME_SCALE


## Flash vermelho + tranco quando leva dano, e a animação de Hurt.
func hit() -> void:
	_flash = 1.0
	if _dying:
		return
	if not entity.card().is_creature():
		return
	play(&"Hurt", false)
	if _sprite:
		var off := Vector3(randf_range(-0.06, 0.06), 0, randf_range(-0.06, 0.06))
		var base := _sprite.position
		if _sprite_tween != null and _sprite_tween.is_valid():
			_sprite_tween.kill()
		_sprite_tween = create_tween()
		_sprite_tween.tween_property(_sprite, "position", base + off, 0.04)
		_sprite_tween.tween_property(_sprite, "position", base, 0.09)


## Chamado pela apresentação antes de resolver o brawl: a criatura avança na
## direção do alvo e volta. É o "avança livre" da regra virando movimento.
##
## O deslocamento real é calculado a partir da diferença de coluna/linha
## multiplicada pelo espaçamento das tiles (TILE_X/TILE_Z), e não por um
## valor fixo — assim a criatura realmente encosta no alvo.
func lunge(dir_x: float, dir_z: float) -> void:
	if _dying or _sprite == null:
		return
	var base := Vector3(0, SLIME_Y, 0.40)
	# Distância real em unidades de mundo: TILE_X/TILE_Z por tile
	var dx := dir_x * Board3D.TILE_X
	var dz := dir_z * Board3D.TILE_Z
	var fwd := Vector3(dx, 0, dz)
	if _sprite_tween != null and _sprite_tween.is_valid():
		_sprite_tween.kill()
	_sprite_tween = create_tween()
	_sprite_tween.tween_property(_sprite, "position", base + fwd, 0.13) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# No ponto de contato: efeito de impacto por elemento
	_sprite_tween.tween_callback(_on_lunge_impact.bind(entity.card().element))
	_sprite_tween.tween_property(_sprite, "position", base, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _on_lunge_impact(element: int) -> void:
	# Usa os mesmos efeitos de impacto da fase de farm (por elemento)
	FarmFx.impact(_fx, global_position, element, 0, true)


func attack() -> void:
	if _dying or not entity.card().is_creature():
		return
	play(&"Attack", false)


# --- fase de farm: o tiro a distância --------------------------------------
# Tudo aqui existe para a criatura "atirar" na trilha. O tiro em si é do
# `Farm3D`; estas quatro funções são só a ponta de saída — de onde o projétil
# nasce, que animação toca, de que cor ele é e o brilho que confirma o bônus.


## De onde sai o projétil: acima e um pouco à frente do corpo. O -0.55 de Z é
## o mesmo deslocamento do sprite (ver `_ready`), então a boca do tiro fica na
## altura do peito e não na nuca.
func muzzle_position() -> Vector3:
	return global_position + Vector3(0, SLIME_Y + 0.10, 0.40)


## Cor do projétil desta criatura: a cor do elemento, lavada até quase branco
## para o tiro ficar legível tanto contra a trilha escura quanto contra a lava.
func bolt_color() -> Color:
	if entity == null:
		return Color("ffd88a")
	var card := entity.card()
	if not card.is_creature():
		return Color("ffd88a")
	return CardData.ELEMENT_COLOR[card.element].lerp(Color.WHITE, 0.45)


## A criatura se vira para o alvo e dispara. É o `attack` de sempre mais o
## [`lunge`] na direção certa, que é o que amarra a ponta de saída do tiro com o
## tabuleiro: sem isso o projétil sai do nada.
func shoot_at(target: Vector3) -> void:
	if _dying or _sprite == null or not entity.card().is_creature():
		return
	play(&"Attack", false)
	var d := target - global_position
	d.y = 0.0
	if d.length_squared() > 0.0001:
		lunge(d.x, d.z)


## Brilho forte e breve no sprite. Usado pelo bônus da fase de farm: as
## criaturas que ganharam +1 ATK acendem, e o jogador sabe quais foram antes
## de olhar o placar.
func pulse(color: Color, time := 0.65) -> void:
	if _sprite == null or not _sprite.visible:
		return
	_pulse_t = time
	_pulse_color = color
	_pulse_boost = 1.6
	if _sprite_tween != null and _sprite_tween.is_valid():
		_sprite_tween.kill()
	_sprite_tween = create_tween()
	_sprite_tween.tween_property(_sprite, "scale",
		Vector3(1.18, 1.18, 1.0), 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_sprite_tween.tween_property(_sprite, "scale", Vector3.ONE, 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func die(on_done: Callable = Callable()) -> void:
	_dying = true
	_die_done = on_done
	if not entity.card().is_creature():
		_fade_out(on_done)
		return
	# a animação de Death roda no `_process`; o fade e o tilt somem no fim.
	# O callback precisa ser guardado: se a animação terminar e chamar
	# `_fade_out` sem ele, o nó é liberado e a chave continua no dicionário de
	# `Board3D` — o próximo `sync` aí chama `die()` num objeto já destruído.
	play(&"Death", false)


func _fade_out(on_done: Callable) -> void:
	# mata o tween de tranco/avanço antes de liberar: ele escreve em `_sprite`,
	# que sai de cena junto com o pai
	if _sprite_tween != null and _sprite_tween.is_valid():
		_sprite_tween.kill()
	_sprite_tween = null
	set_process(false)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_sprite, "modulate:a", 0.0, 0.5)
	tw.tween_property(self, "rotation:z", 0.9, 0.5)
	tw.tween_property(_shadow, "scale", Vector3.ONE * 0.2, 0.4)
	if on_done.is_valid():
		tw.chain().tween_callback(on_done)
	else:
		tw.chain().tween_callback(queue_free)


func _process(delta: float) -> void:
	_tick_anim(delta)

	if _flash <= 0.0 and _pulse_t <= 0.0:
		return
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 3.5)
	# o flash tinge o sprite sem apagar o tint do elemento
	var white := Color(1, 1, 1).lerp(Color(3, 0.7, 0.7), _flash)
	if _pulse_t > 0.0:
		_pulse_t = maxf(0.0, _pulse_t - delta * 1.6)
		var k := _pulse_boost * ease(_pulse_t / 0.65, 0.4)
		white = white.lerp(_pulse_color * 2.2, clampf(k, 0.0, 1.0))
	if _sprite and _sprite.visible:
		_sprite.modulate = Color(
			_tint.r * white.r, _tint.g * white.g, _tint.b * white.b, 1.0)
	elif _mat:
		_mat.albedo_color = white


func _tick_anim(delta: float) -> void:
	if _sprite == null or not _sprite.visible:
		return
	var count := CardDB.slime_frames(String(_action))
	_acc += delta * float(FPS.get(_action, 8.0))
	while _acc >= 1.0:
		_acc -= 1.0
		_frame += 1
		if _frame >= count:
			if _looping:
				_frame = 0
			else:
				_frame = count - 1
				_acc = 0.0
				_on_animation_end(String(_action))
				break
		_apply_frame()


func _on_animation_end(action: String) -> void:
	match action:
		"Death":
			_fade_out(_die_done)
		"Attack", "Hurt":
			# volta ao Idle; se morreu no meio, `_dying` segura
			if not _dying:
				play(&"Idle", true, true)