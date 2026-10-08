class_name CardFace
extends RefCounted

## Renderiza a face de uma carta uma única vez e entrega a textura, para ser
## aplicada num quad 3D.
##
## Reaproveita o desenho 2D do [CardView] via um SubViewport por carta com
## `UPDATE_ONCE`: dá pra manter a nitidez do texto (que em plano inclinado
## seria ilegível se fosse vetorial/3D) sem pagar custo por frame.

const SCALE := 2
## tamanho em pixels da textura de face gerada
const SIZE := Vector2i(192, 264)

static var _cache: Dictionary = {}
static var _host: Node = null


## [host] precisa estar dentro da árvore para o SubViewport renderizar.
static func init(host: Node) -> void:
	_host = host
	_cache.clear()


static func texture_for(card: CardData) -> Texture2D:
	if _host == null or card == null:
		return null
	var key := str(card.id)
	if _cache.has(key):
		return _cache[key]

	var size := Vector2i(SIZE)

	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.disable_3d = true
	# UPDATE_ONCE congelava o viewport antes do Control ter chance de desenhar,
	# e a face saía vazia. Custa um pouco renderizar sempre, mas são viewports
	# pequenos e em número limitado pelo número de cartas distintas.
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_host.add_child(vp)

	var view := CardView.new()
	view.scale = Vector2(SCALE, SCALE)
	view.setup(-1, card, true)
	vp.add_child(view)

	var tex: Texture2D = vp.get_texture()
	_cache[key] = tex
	return tex


## Versão em cinza da face, para o baralho virado da IA.
static func back_texture() -> Texture2D:
	if _cache.has("__back__"):
		return _cache["__back__"]

	var w := int(CardView.CARD_SIZE.x * SCALE)
	var h := int(CardView.CARD_SIZE.y * SCALE)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)

	img.fill(Color(0, 0, 0, 0))
	var frame := Color("2c2740")
	var inner := Color("191527")
	var accent := Color("6b5a94")

	# moldura
	for x in w:
		img.set_pixel(x, 0, frame)
		img.set_pixel(x, h - 1, frame)
	for y in h:
		img.set_pixel(0, y, frame)
		img.set_pixel(w - 1, y, frame)
	for x in range(2, w - 2):
		img.set_pixel(x, 2, frame)
	for y in range(2, h - 2):
		img.set_pixel(2, y, frame)

	# miolo com losango central
	for y in range(4, h - 4):
		for x in range(4, w - 4):
			img.set_pixel(x, y, inner)

	var cx := w / 2
	var cy := h / 2
	var r := int(minf(cx, cy) * 0.55)
	for y in range(cy - r, cy + r):
		for x in range(cx - r, cx + r):
			var d := absi(x - cx) + absi(y - cy)
			if d <= r and d >= r - 4:
				img.set_pixel(x, y, accent)
			elif d <= r - 10:
				img.set_pixel(x, y, accent.darkened(0.45))

	var tex := ImageTexture.create_from_image(img)
	_cache["__back__"] = tex
	return tex
