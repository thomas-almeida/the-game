class_name CardView
extends Control

## Desenho 2D de uma carta. Usado em dois lugares:
##  - renderizado uma vez dentro de um SubViewport ([CardFace]) para virar a
##    textura do quad 3D da mão;
##  - direto na tela, ampliado, no painel de detalhe.
##
## Tudo é desenhado no espaço de [CARD_SIZE]; o zoom fica por `scale` no nó.

signal card_activated(card_index: int)

const CARD_SIZE := Vector2(96, 132)

var card_index: int = -1
var card: CardData

var _selected: bool = false
var _playable: bool = true


func _init() -> void:
	custom_minimum_size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(p_index: int, p_card: CardData, p_playable: bool) -> void:
	card_index = p_index
	card = p_card
	_playable = p_playable
	_selected = false
	queue_redraw()
	tooltip_text = build_tooltip()


func selected(value: bool) -> void:
	if _selected == value:
		return
	_selected = value
	queue_redraw()


## Carta sem mana: escurece, não fica transparente (transparente sumia).
func playable(value: bool) -> void:
	if _playable == value:
		return
	_playable = value
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			card_activated.emit(card_index)
			accept_event()


func build_tooltip() -> String:
	if card == null:
		return ""
	var lines: Array[String] = []
	lines.append("%s — %s (%s)" % [card.title, card.kind_text(), card.element_text()])
	if card.is_creature():
		lines.append("ATK %d / DEF %d   custo %d" % [card.attack, card.defense, card.cost])
	else:
		lines.append("custo %d   %s" % [card.cost, card.effect_text()])

	match card.kind:
		CardData.Kind.TERRAIN:
			lines.append("Pinta a tile e libera criaturas %s nela." % card.element_text())
		CardData.Kind.CREATURE:
			lines.append("Só na linha principal, em tile com terreno %s." % card.element_text())
		CardData.Kind.BUILDING:
			lines.append("Só na linha secundária.")
		CardData.Kind.SPELL:
			lines.append("Resolvida na hora, não ocupa tile.")
	return "\n".join(lines)


func _draw() -> void:
	if card == null:
		return

	var w := CARD_SIZE.x
	var h := CARD_SIZE.y
	var accent: Color = CardData.ELEMENT_COLOR[card.element]
	var frame := CardView.frame_color_for(card.kind)

	# moldura externa dupla: dá thickness mesmo antes do 3D
	draw_rect(Rect2(Vector2(1.5, 2.5), Vector2(w - 3, h - 3)), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), frame.darkened(0.55))
	draw_rect(Rect2(Vector2(2, 2), Vector2(w - 4, h - 4)), Color("15131d"))

	# faixa do nome
	_draw_band(Rect2(Vector2(2, 2), Vector2(w - 4, 20)), accent.darkened(0.35), frame)
	UiKit.text(self, Vector2(6, 16), card.title, 9, Color("f2eef8"), 62)

	# custo
	_draw_cost_badge(Rect2(Vector2(w - 24, 4), Vector2(18, 18)), accent)

	# arte: caixa quase quadrada, senão a arte de 32px fica minúscula no meio
	var art := Rect2(Vector2(17, 25), Vector2(62, 54))
	draw_rect(art, Color("221f2e"))
	_draw_art(art)
	draw_rect(art, Color(accent, 0.55), false, 1.0)

	# faixa do tipo
	_draw_band(Rect2(Vector2(2, 85), Vector2(w - 4, 12)), Color(accent, 0.22), null)
	UiKit.text(self, Vector2(6, 95), card.kind_text(), 8, Color(accent.lightened(0.45)))

	# rodapé
	if card.is_creature():
		_draw_stats(Rect2(Vector2(2, 98), Vector2(w - 4, h - 102)))
	else:
		UiKit.text(self, Vector2(7, 113), "custo %d" % card.cost, 10, Color("e8e2f4"))

	# filete de elemento
	draw_rect(Rect2(Vector2(5, h - 5), Vector2(w - 10, 3)), accent)

	# estados: seleção é só uma borda colorida (a carta não cresce nem sai do
	# lugar); sem mana escurece e esfria, mas continua legível
	if not _playable:
		draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), Color(0.10, 0.09, 0.16, 0.55))
		draw_rect(Rect2(Vector2(0, h - 6), Vector2(w, 6)), Color(0.5, 0.2, 0.2, 0.6))
	if _selected:
		var b: Color = CardData.ELEMENT_COLOR[card.element].lightened(0.3)
		draw_rect(Rect2(Vector2(-3, -3), Vector2(w + 6, h + 6)), b, false, 3.0)
		draw_rect(Rect2(Vector2(-5, -5), Vector2(w + 10, h + 10)),
			Color(b.r, b.g, b.b, 0.35), false, 2.0)


func _draw_band(r: Rect2, fill: Color, border: Variant) -> void:
	draw_rect(r, fill)
	# brilho no topo da faixa: simula chanfro
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Color(1, 1, 1, 0.12))
	if border != null:
		draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)),
			Color(border, 0.5))


func _draw_cost_badge(r: Rect2, accent: Color) -> void:
	draw_rect(Rect2(r.position + Vector2(1, 1.5), r.size), Color(0, 0, 0, 0.5))
	draw_rect(r, Color("20182c"))
	draw_rect(r, accent.lightened(0.25), false, 1.0)
	UiKit.text_centered(self, r, str(card.cost), 12, Color("fff4d8"))


func _draw_art(target: Rect2) -> void:
	if card.art == "":
		# magia sem arte no MVP: bloco na cor do elemento com um glifo
		draw_rect(target, accent_dark())
		UiKit.text_centered(self, target, glyph_for(card.kind), 30, accent_light())
		return

	if card.is_creature():
		# O frame do slime, não a folha inteira: `card.art` aponta para uma
		# folha de animação de 6 quadros de 64x64, e recortar 32x32 dela
		# cortaria o quadro ao meio.
		var tex := CardDB.slime_frame(card.slime, "Idle", 0)
		if tex == null:
			draw_rect(target, Color("232030"))
			return
		var tint: Color = CardData.ELEMENT_COLOR[card.element].lerp(Color.WHITE, 0.55)
		var src := Vector2(tex.get_width(), tex.get_height())
		# sprite: escala inteira e centrada, com sombra para não boiar
		var k := maxf(1.0, floorf(minf(target.size.x / src.x, target.size.y / src.y)))
		var drawn := src * k
		var at := target.position + (target.size - drawn) * 0.5
		draw_texture_rect(tex, Rect2(at + Vector2(2, 2), drawn), false,
			Color(0, 0, 0, 0.5))
		draw_texture_rect(tex, Rect2(at, drawn), false, tint)
		return

	var tex2: Texture2D = CardDB.art(card.art)
	if tex2 == null:
		draw_rect(target, Color("232030"))
		return

	var src2 := Vector2(tex2.get_width(), tex2.get_height())
	if src2.x <= 0.0:
		return
	# terreno e construção são manchas orgânicas: esticar preenche melhor a
	# caixa do que deixar um quadradinho perdido no meio
	draw_texture_rect(tex2, target, false)


func _draw_stats(r: Rect2) -> void:
	var mid := r.position.y + r.size.y * 0.5

	# ATK
	draw_string(UiKit.font(), Vector2(r.position.x + 4, mid + 4),
		str(card.attack), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("ffd76a"))
	# divisor
	draw_rect(Rect2(Vector2(r.position.x + r.size.x * 0.5 - 0.5, r.position.y + 3),
		Vector2(1, r.size.y - 6)), Color(1, 1, 1, 0.12))
	# DEF
	var dw := UiKit.font().get_string_size(str(card.defense), HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	draw_string(UiKit.font(), Vector2(r.position.x + r.size.x - 5 - dw, mid + 4),
		str(card.defense), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("8fc4ea"))

	UiKit.text(self, Vector2(r.position.x + 4, r.position.y + r.size.y - 2),
		"ATK", 7, Color("ffd76a").darkened(0.35))
	var aw := UiKit.font().get_string_size("ATK", HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
	UiKit.text(self, Vector2(r.position.x + r.size.x - 4 - aw, r.position.y + r.size.y - 2),
		"DEF", 7, Color("8fc4ea").darkened(0.3))


static func frame_color_for(kind: int) -> Color:
	match kind:
		CardData.Kind.CREATURE:
			return Color("c8a05a")
		CardData.Kind.TERRAIN:
			return Color("7fa06a")
		CardData.Kind.BUILDING:
			return Color("94909f")
		_:
			return Color("a273d6")


func accent_dark() -> Color:
	var c: Color = CardData.ELEMENT_COLOR[card.element]
	return c.darkened(0.55)


func accent_light() -> Color:
	var c: Color = CardData.ELEMENT_COLOR[card.element]
	return c.lightened(0.55)


static func glyph_for(kind: int) -> String:
	match kind:
		CardData.Kind.SPELL:
			return "*"
		CardData.Kind.BUILDING:
			return "#"
		_:
			return "o"
