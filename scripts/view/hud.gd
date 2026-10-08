extends CanvasLayer

## Camada 2D sobre a cena 3D. Textos nunca ficam no plano inclinado (seriam
## ilegíveis), então tudo que é leitura vive aqui: log, barras, badges de
## ATK/DEF projetados da posição 3D, números de dano e a faixa de leitura da
## carta selecionada.

const FONT_PATH := "res://assets/top-down-roguelike-game-kit-pixel-art/4 GUI/TinyFontCraftpixPixel.otf"

# --- cores do log por categoria -------------------------------------------
const C_SYSTEM := "#6f7a94"
const C_ROUND := "#ffd76a"
const C_PLAYER := "#7fd4a8"
const C_AI := "#e08a7f"
const C_BRAWL := "#ff9d5c"
const C_DEATH := "#ff6b6b"
const C_WIN := "#ffe98a"
## Cor da fase de farm. Um aqua: a paleta já usa verde no jogador, azul na
## mana, coral no rival e dourado no round/bônus, e a faixa da fase precisa
## dizer "isto é outra coisa" sem ser lida antes do texto.
const C_FARM := "#9be7d6"
## Número de dano do farm. Dourado porque aqui o dano é BOM news: quem acerta
## a trilha é o próprio dono dela. O vermelho do brawl passaria a mensagem
## errada ("você perdeu vida") no meio de um aquecimento.
const C_FARM_HIT := "#ffd76a"

var _log: RichTextLabel
var _top_bar: Control
var _player_panel: Control
var _ai_panel: Control
var _badges: Control
var _card_info: PanelContainer
var _fx: Control
var _banner: Label
var _turn_button: Button
var _new_button: Button

var _camera: Camera3D
var _log_unread: int = 0

# --- estado animado do feedback --------------------------------------------
## Tudo aqui existe para o tabuleiro deixar de ser estático. O HP não cai de
## uma vez: a barra desce, e um rastro claro fica para trás drenando devagar,
## que é o que faz o dano ser *visto* e não só correto no estado.
var _hp_shown := {}         ## side -> 0..1, barra principal
var _hp_ghost := {}         ## side -> 0..1, rastro do dano
var _mana_shown := {}       ## side -> 0..1
var _mana_peak := {}        ## side -> maior mana já vista (escala da barra)
var _flash := {}            ## side -> 0..1, pisca ao levar dano
## Tweens que escrevem em nós do HUD (números flutuantes, banner). São
## guardados para poderem ser mortos no reinício: um tween vivo continua
## escrevendo no nó depois de ele sair da árvore.
## O `shake_camera` NÃO entra aqui de propósito — ele mexe num nó da cena 3D
## que pertence ao orquestrador, e matar no meio deixaria a câmera torta.
var _own_tweens: Array[Tween] = []
var _turn_glow: Control
var _turn_label := ""
var _turn_color := Color(1, 1, 1)
var _turn_timer := 0.0
## Tamanho da letra da faixa. A faixa de turno e a de farm dividem o MESMO
## espaço (duas faixas empilhadas cobririam o tabuleiro), e os textos não têm o
## mesmo comprimento: "FASE DE FARM" aguenta 24, "EMPATE - SEM BONUS" não.
var _turn_size := 24
var _turn_side := -1
var _log_hint_timer := 0.0
var _input_locked: bool = false

# --- fase de farm ----------------------------------------------------------
## Tudo da fase é indexado por TRILHA (Board.Side) e nunca global: as duas
## partidas são independentes e um placar somado seria mentira.
var _farm_panel: Control
var _farm_on := false      ## o placar está na tela
var _farm_out := 0.0       ## contagem para o placar sumir (0 = fica)
var _farm_score := {}      ## side -> destruídos
var _farm_pips := {}       ## side -> Array[int] estado por mobo (0 vivo, 1 fugiu, 2 morto)
var _farm_pip_flash := {}  ## side -> Array[float] brilho do pip ao levar tiro
var _farm_pop := {}        ## side -> 0..1 pulso do placar quando o ponto entra
var _heal_flash := {}      ## side -> 0..1 pulso verde da barra de vida (bônus)
## quantas salvas de "+N" já saíram nesta fase: escalona a salva seguinte. Zera
## em `farm_begin` e `reset_session`, senão o atraso cresceria a partida toda.
var _farm_burst_seq := 0
## Bônus ativos de farm: {side -> {element -> {atk, def, mana, heal}}}
var _active_farm_bonuses: Dictionary = {}
## Total de mobs por trilha. Vem do chamador porque a fase decide o número e o
## HUD só desenha um pip por mobo; se o evento `farm_start` ganhar esse campo
## depois, é este default que mantém o placar com a escala certa.
const FARM_MOBS := 6
## Quanto tempo o placar fica na tela depois do fim da fase. some no mesmo
## frame em que a fase acaba e o jogador não chega a ler o resultado — e o
## brawl vem logo em seguida, então a tela precisa ficar limpa.
const FARM_HOLD := 2.2
## Geometria de um pip. 6 cabem em 93px, que é o que sobra entre o número do
## placar e o nome da trilha dentro dos 250px da coluna esquerda.
const FARM_PIP_W := 13.0
const FARM_PIP_H := 12.0
const FARM_PIP_GAP := 3.0
## Quantos slots a trilha atual tem, para o placar desenhar exatamente o que a
## fase spawnou — e não os 6 do default, se a fase mudar o número.
var _farm_slots := FARM_MOBS


func setup(p_camera: Camera3D) -> void:
	_camera = p_camera
	layer = 10
	_build()


func _build() -> void:
	var font := load(FONT_PATH)
	if font:
		var theme := Theme.new()
		theme.default_font = font
		theme.default_font_size = 12

	_top_bar = Control.new()
	_top_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar.draw.connect(_draw_top_bar)
	add_child(_top_bar)

	_player_panel = Control.new()
	_player_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_player_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_panel.draw.connect(_draw_player_panel)
	add_child(_player_panel)

	_ai_panel = Control.new()
	_ai_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ai_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ai_panel.draw.connect(_draw_ai_panel)
	add_child(_ai_panel)

	# Placar da fase de farm. Fica na COLUNA ESQUERDA, logo abaixo do painel do
	# jogador, e não no meio da tela: o tabuleiro ocupa o centro e as trilhas
	# vêm em cima e embaixo dele, então o único lugar realmente livre é a
	# margem. É um bloco de 70px numa tela de 540 — some de longe.
	_farm_panel = Control.new()
	_farm_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_farm_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_farm_panel.draw.connect(_draw_farm_panel)
	add_child(_farm_panel)

	# log
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.fit_content = false
	_log.add_theme_font_override("normal_font", font)
	_log.add_theme_font_size_override("normal_font_size", 11)
	_log.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_log.position = Vector2(16, 92)
	_log.custom_minimum_size = Vector2(300, 300)
	_log.size = Vector2(300, 300)
	_log.set_offsets_preset(Control.PRESET_TOP_RIGHT)
	_log.mouse_filter = Control.MOUSE_FILTER_STOP
	# escondido por padrão: o log é conferência, não leitura de jogo
	_log.visible = false
	add_child(_log)

	_fx = Control.new()
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx)

	_badges = Control.new()
	_badges.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badges.draw.connect(_draw_badges)
	add_child(_badges)

	# Véu do turno rival + faixa de turno. Fica ABAIXO de `_badges` no stack de
	# desenho, senão o escurecimento apagaria os próprios números de ATK/DEF.
	_turn_glow = Control.new()
	_turn_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_turn_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_glow.draw.connect(_draw_turn_glow)
	add_child(_turn_glow)
	move_child(_turn_glow, _badges.get_index())

	# Faixa de leitura da carta selecionada. Antes isso era um modal que
	# abria no clique e engolia a jogada; aqui é uma linha discreta que só
	# aparece com uma carta na mão e nunca intercepta o mouse.
	_card_info = PanelContainer.new()
	_card_info.add_theme_stylebox_override("panel", _card_info_style())
	_card_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_info.visible = false
	add_child(_card_info)

	_banner = Label.new()
	_banner.add_theme_font_override("font", font)
	_banner.add_theme_font_size_override("font_size", 44)
	_banner.add_theme_color_override("font_color", Color(C_WIN))
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.size = Vector2(760, 70)
	_banner.position = Vector2(100, 150)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.modulate.a = 0.0
	add_child(_banner)

	_turn_button = Button.new()
	_turn_button.text = "TERMINAR TURNO"
	_turn_button.custom_minimum_size = Vector2(220, 42)
	add_child(_turn_button)

	_new_button = Button.new()
	_new_button.text = "REINICIAR"
	_new_button.custom_minimum_size = Vector2(220, 28)
	add_child(_new_button)


func _viewport_size() -> Vector2:
	var s := get_viewport().get_visible_rect().size
	if s.x <= 0.0:
		# no primeiro frame ainda devolve zero; usa o tamanho configurado
		return Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))
	return s


func set_viewport_size(v: Vector2) -> void:
	# reposiciona os elementos que dependem do tamanho da tela
	_log.position = Vector2(v.x - 316, 92)
	_log.size = Vector2(300, minf(340.0, v.y - 250.0))
	# botões no canto inferior esquerdo: o canto inferior direito é da mão
	_turn_button.position = Vector2(20, v.y - 96)
	_new_button.position = Vector2(20, v.y - 44)
	# a faixa de turno é desenhada em y=116; o banner fica mais abaixo para os
	# dois nunca se sobreporem (vitória + "SUA VEZ" no mesmo frame)
	_banner.position = Vector2(v.x * 0.5 - 380, v.y * 0.40)
	# faixa da carta selecionada logo acima dos botões
	if _card_info != null and _card_info.visible:
		_card_info.reset_size()
		_card_info.position = Vector2(20, v.y - 96 - _card_info.size.y - 8.0)


# --- log -------------------------------------------------------------------

func push_log(color: String, text: String) -> void:
	if _log == null:
		return
	_log.append_text("[color=%s]%s[/color]\n" % [color, UiKit.fold(text)])


func clear_log() -> void:
	if _log:
		_log.clear()


func log_game_line(text: String) -> void:
	push_log(_classify(text), text)


func _classify(t: String) -> String:
	var u := t.to_upper()
	if "VENCEU" in u:
		return C_WIN
	if "ROUND" in u or "===" in u:
		return C_ROUND
	if "CAI" in u or "DESTRU" in u or "SUCO" in u:
		return C_DEATH
	if "BRAWL" in u or "CAUSA" in u or "ACERTA" in u or "×" in t:
		return C_BRAWL
	if u.begins_with("VOC") or "VOCÊ" in t:
		return C_PLAYER
	if u.begins_with("RIVAL"):
		return C_AI
	return C_SYSTEM


# --- barras ----------------------------------------------------------------

func _draw_top_bar() -> void:
	var box := Rect2(Vector2(16, 14), Vector2(330, 62))
	_panel(_top_bar, box, Color(C_ROUND) if _turn_side == Board.Side.PLAYER
		else Color("#3b3550"))
	UiKit.text(_top_bar, Vector2(box.position.x + 14, box.position.y + 26),
		"ROUND %d" % Game.round, 20, Color(C_ROUND))
	UiKit.text(_top_bar, Vector2(box.position.x + 190, box.position.y + 25),
		Game.phase_label(), 13, Color("#cfd6e4"))
	UiKit.text(_top_bar, Vector2(box.position.x + 14, box.position.y + 50),
		"vence com %d de dano" % Game.STARTING_HP, 11, Color("#8d93a8"))

	# dica da tecla do log: fica discreta e pisca quando o log é aberto.
	# Na linha de baixo, não na de cima: o rótulo da fase muda de largura
	# ("SORTEANDO MANA" é o mais longo) e na mesma linha ele cobria o "L",
	# deixando a barra do round como "SORTEANDO MANA.L00".
	var hint := "L: log"
	var hcol := Color("#8d93a8")
	if _log_hint_timer > 0.0:
		hcol = Color("ffd76a", 0.5 + 0.5 * sin(_log_hint_timer * 9.0))
	UiKit.text(_top_bar, Vector2(box.position.x + box.size.x - 48,
		box.position.y + 50), hint, 10, hcol)


# --- indicador de turno ----------------------------------------------------

func set_turn(side: int) -> void:
	_turn_side = side


## Aviso de "clique no dado". Fica no canto, embaixo, perto de onde o dado
## realmente está, e não no meio da tela.
func show_dice_prompt() -> void:
	_set_band("CLIQUE NO DADO", Color("ffd76a"), 9.0, 24)


## Escreve a faixa momentânea do topo. Uma única faixa para turno e para farm,
## pelo motivo que está em `_turn_size`: empilhar duas faixas ocuparia a faixa
## de baixo justamente onde a segunda fase precisa ser lida.
func _set_band(text: String, color: Color, seconds: float, size: int) -> void:
	_turn_label = UiKit.fold(text)
	_turn_color = color
	_turn_timer = seconds
	_turn_size = size



## Limpa o aviso momentâneo de turno.
func clear_transients() -> void:
	_turn_timer = 0.0


## Faixa grande no topo do tabuleiro dizendo de quem é a vez.
func announce_turn(side: int, seconds := 0.9) -> void:
	set_turn(side)
	if side == Board.Side.PLAYER:
		_set_band("SUA VEZ", Color(C_PLAYER), seconds, 24)
	else:
		_set_band("TURNO DO RIVAL", Color(C_AI), seconds, 24)


func on_side_damaged(side: int) -> void:
	_flash[side] = 1.0


## Ponto de TELA para onde voa o disparo de ataque direto em [side]: logo
## abaixo do painel de vida de quem apanha. É o jeito de "atacar o jogador" em
## 3D, já que o jogador é só um painel de HUD e não existe no mundo.
##
## Fica embaixo do painel, e não no centro dele, porque o HUD desenha POR CIMA
## do 3D: um impacto no meio do painel seria engolido pelo fundo escuro dele.
## As posições espelham `_draw_player_panel` / `_draw_ai_panel`.
func hp_anchor(side: int) -> Vector2:
	var v := _viewport_size()
	if side == Board.Side.PLAYER:
		return Vector2(16.0 + 125.0, 92.0 + 88.0 + 24.0)
	return Vector2(v.x - 266.0 + 125.0, 14.0 + 88.0 + 24.0)


## Durante o turno do rival o tabuleiro escurece e as cartas da mão apagam.
## Sem isso o jogador clica achando que ainda é a vez dele e não acontece
## nada — o botão desabilitado sozinho é um aviso fácil de ignorar.
func set_input_locked(on: bool) -> void:
	_input_locked = on
	# `reset_session()` pode ser chamado antes de `_build()` (primeiro frame,
	# ou num HUD montado por outro caminho); o estado é guardado mesmo assim,
	# só o botão não existe ainda.
	if _turn_button == null:
		return
	_turn_button.disabled = on
	_turn_button.text = "TURNO DO RIVAL..." if on else "TERMINAR TURNO"


func _draw_turn_glow() -> void:
	var s := _turn_glow.size
	if s.x <= 0.0:
		return
	# o `_badges` desenha depois do véu, senão os números de ATK/DEF ficariam
	# por cima do escurecimento e a cena pareceria quebrada
	

	# faixa de turno: fica entre os dois painéis (não em cima deles) e some
	# rápido. É um aviso momentâneo, não um HUD permanente.
	if _turn_timer > 0.0 and _turn_label != "":
		var t: float = clampf(_turn_timer / 0.55, 0.0, 1.0)
		var w := 300.0
		var r := Rect2(Vector2((s.x - w) * 0.5, 116), Vector2(w, 40))
		_turn_glow.draw_rect(r, Color(0.04, 0.03, 0.07, 0.92 * t))
		_turn_glow.draw_rect(r, Color(_turn_color, t), false, 2.0)
		UiKit.text_centered(_turn_glow, r, _turn_label, _turn_size,
			Color(_turn_color, t))

	# Véu do turno do rival: escurece o tabuleiro inteiro e apaga as cartas.
	if _input_locked:
		_turn_glow.draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.02, 0.05, 0.42))


func _draw_player_panel() -> void:
	# mesmo tamanho nos dois painéis: o da IA era mais baixo e a barra de mana
	# caía por cima da linha "mao / deck / descarte"
	var box := Rect2(Vector2(16, 92), Vector2(250, 88))
	_draw_side(_player_panel, box, Game.player(), Color(C_PLAYER), "VOCE")


func _draw_ai_panel() -> void:
	var s := _ai_panel.size
	var box := Rect2(Vector2(s.x - 266, 14), Vector2(250, 88))
	_draw_side(_ai_panel, box, Game.opponent(), Color(C_AI), "RIVAL")


func _draw_side(ci: Control, box: Rect2, p: PlayerState, accent: Color, label: String) -> void:
	# painel do lado que está jogando ganha moldura acesa; o outro apaga. É a
	# informação mais básica que faltava: de quem é a vez.
	var active := _turn_side == p.side and _turn_side >= 0
	_panel(ci, box, accent if active else Color("#3b3550"))

	UiKit.text(ci, Vector2(box.position.x + 12, box.position.y + 21), label, 15,
		accent if active else accent.darkened(0.45))

	# --- vida ---
	var hp_bar := Rect2(Vector2(box.position.x + 12, box.position.y + 28),
		Vector2(box.size.x - 24, 17))
	_draw_hp_bar(ci, hp_bar, p)

	# --- mana: barra curta à esquerda, número à direita, na MESMA linha ---
	var mw := 96.0
	var mana_bar := Rect2(Vector2(box.position.x + 12, box.position.y + 49),
		Vector2(mw, 8))
	_draw_mana_bar(ci, mana_bar, p)
	UiKit.text(ci, Vector2(box.position.x + 18 + mw, box.position.y + 46),
		"MANA %d/%d" % [p.mana, maxi(int(_mana_peak.get(p.side, 1)), 1)], 11,
		Color("#6f9fe0"))

	UiKit.text(ci, Vector2(box.position.x + 12, box.position.y + box.size.y - 6),
		"mao %d   deck %d   descarte %d" % [p.hand.size(), p.deck.size(), p.discard.size()],
		10, Color("#8d93a8"))


## Barra de vida com rastro: a parte escura que sobra é o dano que acabou de
## acontecer e ainda está drenando. Sem ela a barra cai e o olho não pega.
func _draw_hp_bar(ci: Control, box: Rect2, p: PlayerState) -> void:
	var shown: float = _hp_shown.get(p.side, 1.0)
	var ghost: float = _hp_ghost.get(p.side, 1.0)
	var ratio := float(p.hp) / float(p.max_hp)

	ci.draw_rect(box, UiKit.INK)
	var inner := Rect2(box.position + Vector2(1, 1), box.size - Vector2(2, 2))
	ci.draw_rect(inner, Color(0.13, 0.13, 0.17))

	var fill := Color("d05050") if p.side == Board.Side.PLAYER else Color("c07050")
	var w := inner.size.x * clampf(shown, 0.0, 1.0)
	if w > 0.0:
		ci.draw_rect(Rect2(inner.position, Vector2(w, inner.size.y)), fill)
	# rastro do dano: a faixa amarela entre a barra atual e onde ela estava.
	# Só aparece quando existe diferença, senão fica uma mancha permanente.
	var gw := inner.size.x * clampf(ghost, 0.0, 1.0)
	if gw > w + 0.5:
		ci.draw_rect(Rect2(inner.position + Vector2(w, 0),
			Vector2(gw - w, inner.size.y)), Color(1.0, 0.88, 0.35, 0.9))
		# divisória brilhante onde a barra parou: o "impacto"
		ci.draw_rect(Rect2(inner.position + Vector2(w - 1.0, 0),
			Vector2(2.0, inner.size.y)), Color(1.0, 1.0, 0.85, 0.95))

	# piscar vermelho no instante do golpe
	var f: float = _flash.get(p.side, 0.0)
	if f > 0.0:
		ci.draw_rect(inner, Color(1, 0.25, 0.2, 0.45 * f))
	# piscar verde na cura do bônus de farm. Sem isto a cura é invisível: a
	# barra sobe, e subir não é evento, é só um número que mudou.
	var hf: float = _heal_flash.get(p.side, 0.0)
	if hf > 0.0:
		ci.draw_rect(inner, Color(0.35, 1.0, 0.5, 0.40 * hf))
	ci.draw_rect(box, UiKit.LINE, false, 1.0)

	# Rótulo à esquerda, com fundo próprio: centrado, ele caía em cima do
	# rastro amarelo e ficava ilegível bem no momento do dano.
	var lbl := "HP %d/%d" % [p.hp, p.max_hp]
	var lw := 62.0
	var lr := Rect2(inner.position, Vector2(lw, inner.size.y))
	ci.draw_rect(lr, Color(0, 0, 0, 0.62))
	UiKit.text_centered(ci, lr, lbl, 10, Color("ffe4e0"))


func _draw_mana_bar(ci: Control, box: Rect2, p: PlayerState) -> void:
	# a escala é o pico de mana já visto na partida: se fosse a mana do turno,
	# a barra encolheria a cada rodada e perderia o sentido de "quanto eu tenho"
	var peak: int = maxi(int(_mana_peak.get(p.side, 1)), maxi(p.mana, 1))
	var shown: float = _mana_shown.get(p.side, 0.0)
	ci.draw_rect(box, UiKit.INK)
	var inner := Rect2(box.position + Vector2(1, 1), box.size - Vector2(2, 2))
	ci.draw_rect(inner, Color(0.10, 0.12, 0.18))
	var w := inner.size.x * clampf(shown / float(peak), 0.0, 1.0)
	if w > 0.0:
		ci.draw_rect(Rect2(inner.position, Vector2(w, inner.size.y)),
			Color("4a7fd0") if p.side == Board.Side.PLAYER else Color("7a5fc0"))
	# divisórias da escala: uma por ponto de mana, para a barra ter contagem
	# em vez de ser um borrão
	for i in range(1, peak):
		var x := inner.size.x * float(i) / float(peak)
		ci.draw_rect(Rect2(inner.position + Vector2(x, 0), Vector2(1, inner.size.y)),
			Color(0, 0, 0, 0.35))
	ci.draw_rect(box, UiKit.LINE, false, 1.0)


## Desenha os bônus permanentes de farm abaixo da barra de mana.
## Mostra ícones coloridos por elemento com os valores de ATK/DEF/MANA/VIDA.
func _draw_farm_bonuses(ci: Control, box: Rect2, p: PlayerState) -> void:
	var bonuses: Dictionary = _active_farm_bonuses.get(p.side, {})
	if bonuses.is_empty():
		return

	var element_colors := {
		CardData.Element.FIRE: Color("#e2553b"),
		CardData.Element.WATER: Color("#4a90d9"),
		CardData.Element.EARTH: Color("#8a5a3b"),
		CardData.Element.FROST: Color("#9fe4f5"),
		CardData.Element.SHADOW: Color("#8f6ed6"),
	}

	var y_offset := box.position.y + box.size.y + 4  # 4px abaixo da barra de mana
	var x_start := box.position.x + 12
	var element_width := 40.0
	var gap := 4.0

	for element in bonuses:
		var bonus_data: Dictionary = bonuses[element]
		if not bonus_data:
			continue

		var atk := int(bonus_data.get("atk", 0))
		var def_bonus := int(bonus_data.get("def", 0))
		var mana_bonus := int(bonus_data.get("mana", 0))
		var heal := int(bonus_data.get("heal", 0))

		# Pula se não tem nenhum bônus
		if atk == 0 and def_bonus == 0 and mana_bonus == 0 and heal == 0:
			continue

		var color: Color = element_colors.get(element, Color.WHITE)
		var element_name: String = CardData.ELEMENT_LABEL.get(element, "??")

		var box_rect := Rect2(Vector2(0, 0), Vector2(element_width, 36))
		box_rect.position = Vector2(x_start, y_offset)

		# Fundo do bônus
		ci.draw_rect(box_rect, Color(0, 0, 0, 0.6))
		ci.draw_rect(box_rect, color, false, 1.0)

		# Ícone do elemento (círculo colorido)
		var icon_pos := Vector2(x_start + 6, y_offset + 18)
		ci.draw_circle(icon_pos, 6, color)

		# Nome do elemento
		UiKit.text(ci, Vector2(x_start + 16, y_offset + 2), element_name, 9, Color("#e8e2f4"))

		# Valores dos bônus
		var bonus_parts: Array[String] = []
		if int(bonus_data.get("atk", 0)) > 0:
			bonus_parts.append("ATK +%d" % bonus_data["atk"])
		if int(bonus_data.get("def", 0)) > 0:
			bonus_parts.append("DEF +%d" % bonus_data["def"])
		if int(bonus_data.get("mana", 0)) > 0:
			bonus_parts.append("MANA +%d" % bonus_data["mana"])
		if int(bonus_data.get("heal", 0)) > 0:
			bonus_parts.append("VIDA +%d" % bonus_data["heal"])

		var bonus_text := " | ".join(bonus_parts)
		UiKit.text(ci, Vector2(x_start + 16, y_offset + 18), 
			" | ".join(bonus_parts), 8, Color("#e8e2f4"))

		x_start += element_width + gap


func _panel(ci: Control, r: Rect2, border := Color("#3b3550")) -> void:
	ci.draw_rect(r, Color(0, 0, 0, 0.55))
	ci.draw_rect(r, border, false, 1.0)


# --- fase de farm ----------------------------------------------------------
#
## Contrato com `main_3d`: um método por evento da fase, na mesma ordem da
## fila. Nenhum método aqui recebe a fila inteira — a apresentação quer um
# evento por chamada, senão o orquestrador precisa repassar um dicionário e o
# HUD volta a conhecer o formato do `Game`.
#
## O HUD só guarda o que ele DESENHA (placar e pips). HP, posição e animação do
# mobo são da cena 3D: duplicar isso aqui seria uma segunda verdade sobre o
# mesmo objeto, e foi um placar por cima das criaturas que o jogador reclamou.


## A fase começou. Zera os dois placares e anuncia a fase na faixa do topo.
## [mobs_per_lane] é o total de mobs de CADA trilha: o placar desenha um pip
## por mobo, e sem esse número não existe contra o que preencher.
func farm_begin(mobs_per_lane: int = FARM_MOBS) -> void:
	_farm_score.clear()
	_farm_pips.clear()
	_farm_pip_flash.clear()
	_farm_pop.clear()
	_farm_burst_seq = 0
	_farm_slots = maxi(mobs_per_lane, 0)
	for side in [Board.Side.PLAYER, Board.Side.AI]:
		var st: Array = []
		var fl: Array = []
		for i in maxi(mobs_per_lane, 0):
			st.append(0)
			fl.append(0.0)
		_farm_pips[side] = st
		_farm_pip_flash[side] = fl
	_farm_on = true
	_farm_out = 0.0
	_set_band("FASE DE FARM", Color(C_FARM), 1.7, 24)


## Um mobo entrou na trilha. Não desenha nada: o pip já nasceu vazio em
## `farm_begin` e o mobo em si é coisa da cena 3D. O HP chega aqui só para
## manter o placar coerente se a trilha spawnar mais tarde do que o placar.
func farm_mob_spawned(lane: int, i: int, hp: int) -> void:
	if not _farm_on:
		return
	var st: Array = _farm_pips.get(lane, [])
	if i >= 0 and i < st.size():
		st[i] = 0


## Dano acertado num mobo.
##
## [at] é a posição de mundo do mobo, para o número subir em cima dele — passe
## `Vector3.ZERO` quando a cena não tiver a posição (aí sai só o placar).
## [hp_left] não desenha nada por si: o que sobra de vida é da cena 3D. Ele
## decide o QUANTO o pip acende, porque um mobo com 1-2 de vida é justamente o
## que está prestes a cair e o jogador precisa saber qual deles é.
func farm_mob_hit(lane: int, i: int, amount: int, hp_left: int,
		at := Vector3.ZERO) -> void:
	if not _farm_on:
		return
	var fl: Array = _farm_pip_flash.get(lane, [])
	if i >= 0 and i < fl.size():
		fl[i] = 1.0 if hp_left <= 2 else 0.55
	if at != Vector3.ZERO and amount > 0:
		# sobe um pouco acima do mobo: o número não pode ficar em cima do
		# corredor, senão some no meio das criaturas
		float_number(at + Vector3(0, 0.55, 0), "%d" % amount,
			Color(C_FARM_HIT), 22)


## Mobo destruído: é o ponto do placar. O pip enche na cor da trilha e o
## número do placar dá um pulo — o placar é a única coisa que muda quando a
## fase está sendo vencida, então é nele que o jogo tem que reagir.
func farm_mob_killed(lane: int, i: int) -> void:
	if not _farm_on:
		return
	# Contar duas vezes o mesmo mobo inflaria o placar sem o jogador ter feito
	# nada: o evento pode chegar repetido se a apresentação for reprocessada.
	var novo := true
	var st: Array = _farm_pips.get(lane, [])
	if i >= 0 and i < st.size():
		novo = int(st[i]) != 2
		st[i] = 2
	if novo:
		_farm_score[lane] = int(_farm_score.get(lane, 0)) + 1
		_farm_pop[lane] = 1.0


## Mobo atravessou a trilha: saiu sem morrer. Marca o pip como "fugiu" — um
## estado visível diferente de "vivo", porque no fim da fase as duas coisas
## precisam ser distinguíveis para o placar não parecer um bug.
func farm_mob_escaped(lane: int, i: int) -> void:
	if not _farm_on:
		return
	var st: Array = _farm_pips.get(lane, [])
	if i >= 0 and i < st.size() and int(st[i]) != 2:
		st[i] = 1


## A fase acabou. O placar NÃO some aqui: ele segura [FARM_HOLD] segundos e
## some sozinho, porque quem ganha o bônus logo em seguida precisa ainda ler o
## placar zerado. [winner] é -1 no empate — e no empate ninguém ganha nada,
## então o texto diz isso.
func farm_end(player_score: int, ai_score: int, winner: int) -> void:
	if not _farm_on:
		return
	# O placar manda no placar: o evento é a fonte da verdade e o que o HUD
	# contou evento por evento é só palpite durante a fase.
	_farm_score[Board.Side.PLAYER] = maxi(player_score, 0)
	_farm_score[Board.Side.AI] = maxi(ai_score, 0)
	_farm_pop[Board.Side.PLAYER] = 1.0
	_farm_pop[Board.Side.AI] = 1.0
	_farm_out = FARM_HOLD

	var p := int(_farm_score[Board.Side.PLAYER])
	var a := int(_farm_score[Board.Side.AI])
	if winner != Board.Side.PLAYER and winner != Board.Side.AI:
		_set_band("EMPATE - SEM BONUS", Color(C_ROUND), 2.0, 18)
	else:
		var col := Color(C_PLAYER) if winner == Board.Side.PLAYER else Color(C_AI)
		_set_band("FARM %d x %d" % [p, a], col, 1.8, 22)


## O bônus foi aplicado. Isto é a recompensa da fase e precisa ser óbvia:
## três coisas ao mesmo tempo, porque cada uma pega um olhar diferente.
##  1. faixa no topo + banner no meio: o texto, para quem lê;
##  2. um "+1" em cima de CADA criatura do lado: o número, para quem olha o
##     tabuleiro — e é onde o efeito vai ser usado no brawl que vem a seguir;
##  3. pulso verde na barra de vida, se houve cura.
##
## [label] é o texto humano do bônus, quando a regra dá algo que não cabe em
## dois números (o evento `bonus` atual também traz elemento, DEF e mana, e
## pode vir mais de uma vez por fase, um por bônus). Sem ele, o HUD escreve
## "+1 ATK +2 VIDA"; com ele, escreve os números e o nome do bônus.
##
## **Não presume que o bônus vem do placar.** Quem ganhou o farm e quem levou
## o bônus são coisas independentes na regra atual, então o texto aqui não diz
## "você venceu o farm". Quem ganhou o farm é o `farm_end`.
func farm_bonus(side: int, atk: int, heal: int, label := "") -> void:
	var mine := side == Board.Side.PLAYER
	var col := Color(C_PLAYER) if mine else Color(C_AI)

	var parts: Array[String] = []
	if atk != 0:
		parts.append("+%d ATK" % atk)
	if heal != 0:
		parts.append("+%d VIDA" % heal)
	var txt := " ".join(parts)
	if not label.is_empty():
		txt = ("%s  %s" % [txt, label]) if not txt.is_empty() else label
	elif txt.is_empty():
		txt = "BONUS"

	# Armazena o bônus ativo para exibição
	var bonuses: Dictionary = _active_farm_bonuses.get(side, {})
	var bonus_data: Dictionary = {"atk": atk, "heal": heal}
	bonuses[0] = bonus_data  # por enquanto só um bônus por lado
	_active_farm_bonuses[side] = bonuses

	_set_band("BONUS DE FARM" if mine else "BONUS DO RIVAL", col, 2.0, 20)
	show_banner(txt, 44, Color(C_WIN) if mine else col)

	if atk > 0:
		_burst_over_side(side, "+%d" % atk, Color(C_WIN))
	if heal > 0:
		_heal_flash[side] = 1.0
	_farm_pop[side] = 1.0


## Solta um número em cima de cada criatura do lado, escalonado. É o que faz o
## bônus parecer ganho: o "+1" cai exatamente em cima dos badges de ATK que o
## jogador já está acostumado a ler, e o número do badge sobe junto porque a
## criatura mudou de ATK de verdade.
##
## A fase pode aplicar DOIS bônus (um por elemento) no mesmo segundo de jogo.
## O contador de salva joga a segunda salva depois da primeira, senão os dois
## "+1" caem no mesmo pixel e o jogador lê "+1 +1" como um número só.
func _burst_over_side(side: int, text: String, color: Color) -> void:
	if _camera == null or Game.board == null:
		return
	var base := _farm_burst_seq * 0.45
	_farm_burst_seq += 1
	var n := 0
	for row in Board.ROWS:
		for col in Board.COLS:
			var e := Game.board.get_entity(col, row)
			if e == null or not e.card().is_creature() or e.owner_side != side:
				continue
			# `float_number` espera a posição de mundo; o escalonamento vem do
			# índice para a salva não parecer uma explosão só.
			float_number(_board_pos(col, row) + Vector3(0, 1.5, 0), text,
				color, 24, base + 0.06 * n)
			n += 1


## Desliga o placar sem animação. Usado pelo reinício de partida e por quem
## quiser fechar a fase na mão. Não toca no `_heal_flash`: o pulso verde é da
## barra de vida e sobrevive ao placar (o bônus chega logo depois do fim da
## fase, e é aí que a cura precisa aparecer).
func clear_farm() -> void:
	_farm_on = false
	_farm_out = 0.0
	_farm_score.clear()
	_farm_pips.clear()
	_farm_pip_flash.clear()
	_farm_pop.clear()


# --- desenho do placar da fase ---------------------------------------------

func _draw_farm_panel() -> void:
	if not _farm_on:
		return
	# Coluna esquerda, embaixo do painel do jogador. Largura igual à dele para
	# a coluna ler como uma coisa só, e não como um painel solto.
	var box := Rect2(Vector2(16, 188), Vector2(250, 70))
	var p := int(_farm_score.get(Board.Side.PLAYER, 0))
	var a := int(_farm_score.get(Board.Side.AI, 0))

	# Quem está na frente acende: o objetivo é o jogador ler "estou ganhando"
	# sem fazer conta, então o estado tem que estar no COR, não só no número.
	var pop_p: float = _farm_pop.get(Board.Side.PLAYER, 0.0)
	var pop_a: float = _farm_pop.get(Board.Side.AI, 0.0)
	var lead := 0
	if p > a:
		lead = Board.Side.PLAYER
	elif a > p:
		lead = Board.Side.AI

	# alpha do desaparecimento: segura cheia e só então some
	var alpha := 1.0 if _farm_out <= 0.0 \
		else clampf(_farm_out / 0.6, 0.0, 1.0)

	var border := Color(C_FARM) if _farm_on else Color("#3b3550")
	if pop_p > 0.0 or pop_a > 0.0:
		border = border.lightened(0.4)
	_farm_panel.draw_rect(box, Color(0, 0, 0, 0.55 * alpha))
	_farm_panel.draw_rect(box, Color(border, 0.85 * alpha), false, 1.0)

	UiKit.text(_farm_panel, Vector2(box.position.x + 12, box.position.y + 15),
		"FASE DE FARM", 10, Color(C_FARM, alpha))

	_draw_farm_row(box, Vector2(0, 24), Board.Side.PLAYER, p, lead, pop_p, alpha)
	_draw_farm_row(box, Vector2(0, 44), Board.Side.AI, a, lead, pop_a, alpha)


func _draw_farm_row(box: Rect2, at: Vector2, side: int, score: int,
		lead: int, pop: float, alpha: float) -> void:
	var accent := Color(C_PLAYER) if side == Board.Side.PLAYER else Color(C_AI)
	var col := Color(C_WIN) if side == lead else accent.darkened(0.25)
	var row_y := box.position.y + at.y

	# O número é o placar; o pip é o progresso da fase (morto / fugiu / vivo);
	# o nome da trilha é a legenda. Nessa ordem: o olho pega o número primeiro
	# e o pip só confirma.
	var num := Rect2(box.position.x + 8, row_y, 28, 18)
	# o número dá um pulo quando o ponto entra: é o "dopamina" que o placar
	# permite sem cobrir nada
	var size := 18 + int(round(5.0 * clampf(pop, 0.0, 1.0)))
	UiKit.text_centered(_farm_panel, num, str(score), size, Color(col, alpha))

	_draw_farm_pips(Rect2(box.position.x + 42, row_y + 3,
		float(_farm_slots) * (FARM_PIP_W + FARM_PIP_GAP) - FARM_PIP_GAP,
		FARM_PIP_H), side, accent, alpha)

	UiKit.text(_farm_panel, Vector2(box.position.x + 146, row_y + 13),
		"VOCE" if side == Board.Side.PLAYER else "RIVAL", 10,
		Color(accent.darkened(0.15), alpha * 0.9), 92.0,
		HORIZONTAL_ALIGNMENT_RIGHT)


## Um pip por mobo da trilha. Três estados, e eles precisam ser lidos de
## relance sem legenda:
##  - morto: bloco sólido na cor da trilha (é o que o dono marcou);
##  - fugiu: bloco escuro com um traço diagonal (saiu andando, ninguém marcou);
##  - vivo: bloco vazio com contorno fraco.
## Barras de HP por mobo foram descartadas de propósito: seis barras em cima da
## trilha é exatamente o HUD que cobre o que o jogador deveria estar olhando.
func _draw_farm_pips(box: Rect2, side: int, accent: Color, alpha: float) -> void:
	var st: Array = _farm_pips.get(side, [])
	var fl: Array = _farm_pip_flash.get(side, [])
	for i in st.size():
		var r := Rect2(box.position + Vector2(float(i) * (FARM_PIP_W + FARM_PIP_GAP), 0),
			Vector2(FARM_PIP_W, FARM_PIP_H))
		var f: float = clampf(float(fl[i]) if i < fl.size() else 0.0, 0.0, 1.0)
		match int(st[i]):
			2:
				_farm_panel.draw_rect(r, Color(accent, alpha))
				if f > 0.0:
					_farm_panel.draw_rect(r, Color(1, 1, 1, f * alpha))
			1:
				_farm_panel.draw_rect(r, Color(0.10, 0.10, 0.13, 0.9 * alpha))
				_farm_panel.draw_line(
					r.position + Vector2(2, FARM_PIP_H - 2),
					r.position + Vector2(FARM_PIP_W - 2, 2),
					Color(0.55, 0.55, 0.62, 0.85 * alpha), 1.0)
			_:
				_farm_panel.draw_rect(r, Color(0.10, 0.10, 0.13, 0.9 * alpha))
				_farm_panel.draw_rect(r, Color(0.32, 0.32, 0.38, 0.8 * alpha),
					false, 1.0)
		# contorno preto em volta de tudo: separa os pips da caixa e do texto
		_farm_panel.draw_rect(r, Color(0, 0, 0, 0.75 * alpha), false, 1.0)
		if f > 0.0 and int(st[i]) != 2:
			_farm_panel.draw_rect(r, Color(accent.lightened(0.5),
				0.5 * f * alpha), false, 1.0)



# --- badges projetados -----------------------------------------------------

func _draw_badges() -> void:
	if _camera == null:
		return
	for row in Board.ROWS:
		for col in Board.COLS:
			var e := Game.board.get_entity(col, row)
			if e == null or not e.card().is_creature():
				continue
			# o slime tem ~1.05 de altura e o chão em 0.1: o badge precisa ficar acima
			# da cabeça, ou ele some atrás da criatura
			var world := _board_pos(col, row) + Vector3(0, 1.42, 0)
			var sp := _camera.unproject_position(world)
			if sp.x < -50 or sp.x > _badges.size.x + 50:
				continue
			_draw_stat_badge(e, sp)


func _board_pos(col: int, row: int) -> Vector3:
	return Vector3(
		(col - (Board.COLS - 1) * 0.5) * Board3D.TILE_X,
		0,
		(row - (Board.ROWS - 1) * 0.5) * Board3D.TILE_Z)


## Só um "ATK/DEF" em texto. Antes era uma caixa escura de 66×22 com borda
## na cor do elemento e um barinho de dano embaixo — pesava mais que a própria
## criatura e escondia o tabuleiro.
##
## A DEF mostrada é a **restante** (`defense - damage_taken`), então o número
## já diz quanto a criatura apanhou: ele cai e fica vermelho sozinho, sem
## nenhum adorno extra.
func _draw_stat_badge(e: BoardEntity, at: Vector2) -> void:
	var left: int = maxi(e.defense - e.damage_taken, 0)
	var txt := "%d/%d" % [e.attack, left]
	var box := Rect2(at - Vector2(26, 11), Vector2(52, 22))
	var col := Color("e8e2f4")
	if e.damage_taken > 0:
		col = Color("ff8f7a")

	# contorno em 4 direções: legível sobre qualquer cor de elemento sem
	# precisar de fundo
	for off in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		UiKit.text_centered(_badges,
			Rect2(box.position + off, box.size), txt, 11, Color(0, 0, 0, 0.85))
	UiKit.text_centered(_badges, box, txt, 11, col)


# --- efeitos ---------------------------------------------------------------

func float_number(world_pos: Vector3, text: String, color: Color, size := 26,
		delay := 0.0) -> void:
	if _camera == null or _fx == null:
		return
	var start := _camera.unproject_position(world_pos)
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", load(FONT_PATH))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = start - Vector2(40, 12)
	label.size = Vector2(80, 26)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Com atraso, o número nasce invisível: `set_delay` só adia o tween, e sem
	# isso o Label ficaria parado e visível na posição inicial até a hora dele.
	if delay > 0.0:
		label.modulate.a = 0.0
	_fx.add_child(label)

	var tw := create_tween()
	tw.set_parallel(true)
	if delay > 0.0:
		tw.tween_property(label, "modulate:a", 1.0, 0.0).set_delay(delay)
	tw.tween_property(label, "position:y", start.y - 60, 0.85) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT) \
		.set_delay(delay)
	tw.tween_property(label, "modulate:a", 0.0, 0.85).set_delay(0.25 + delay)
	# o `Label` não tem autowrap, então a largura fixa de 80px não explode a
	# caixa (armadilha 2). O `chain` espera TODOS os tween em paralelo antes de
	# liberar o nó; como todos já carregam o atraso, não precisa de intervalo.
	tw.chain().tween_callback(label.queue_free)
	_track(tw)


## Guarda um tween que escreve em nós do HUD para poder matá-lo no reinício.
## O `Label` do número flutuante é criado aqui e só morre quando o tween
## termina; se a partida reiniciar no meio, o tween precisa morrer junto.
func _track(tw: Tween) -> void:
	_own_tweens.append(tw)
	tw.finished.connect(_forget_tween.bind(tw))


func _forget_tween(tw: Tween) -> void:
	_own_tweens.erase(tw)


## Mata os tweens do HUD que ainda estão rodando. Ver o comentário de
## `_own_tweens`: o da câmera fica de fora de propósito.
func _kill_own_tweens() -> void:
	# Itera uma CÓPIA: `kill()` emite `finished`, o `_forget_tween` apaga a
	# entrada da lista, e encolher a lista no meio do `for` fazia o Godot
	# pular elementos — ou pior, ler índice fora do range.
	for tw in _own_tweens.duplicate():
		# um tween já encerrado não precisa ser morto, e `kill()` nele reclama
		if is_instance_valid(tw) and tw.is_valid():
			tw.kill()
	_own_tweens.clear()


func shake_camera(rig: Node3D, strength := 0.22) -> void:
	var base := rig.position
	var tw := create_tween()
	for i in 6:
		var off := Vector3(randf_range(-strength, strength),
			randf_range(-strength, strength) * 0.5,
			randf_range(-strength, strength))
		tw.tween_property(rig, "position", base + off, 0.035)
	tw.tween_property(rig, "position", base, 0.06)


## Faixa grande no meio da tela: vitória, erro, título de carta. O tamanho e a
## cor são parâmetros para o bônus de farm, que precisa do mesmo estouro com a
## cor do lado que ganhou — e é o único lugar da UI que usa dourado.
func show_banner(text: String, size := 44, color := Color(C_WIN)) -> void:
	if _banner == null:
		return
	_banner.text = UiKit.fold(text)
	_banner.add_theme_font_size_override("font_size", size)
	_banner.add_theme_color_override("font_color", color)
	_banner.modulate.a = 0.0
	_banner.scale = Vector2(0.8, 0.8)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_banner, "modulate:a", 1.0, 0.2)
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(1.6)
	tw.chain().tween_property(_banner, "modulate:a", 0.0, 0.5)
	_track(tw)


# --- leitura da carta selecionada -------------------------------------------

## Não é modal e não abre nada: só preenche a faixa do canto inferior
## esquerdo. O clique na carta tem que continuar significando "selecionar para
## invocar", não "abrir uma janela".
func show_card_info(card: CardData) -> void:
	clear_card_info()
	if card == null or _card_info == null:
		return

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.custom_minimum_size = Vector2(330, 0)
	_card_info.add_child(vb)

	var head := "%s  ·  %s  ·  custo %d" % [
		card.title, card.kind_text(), card.cost]
	vb.add_child(_label(head, 13, CardData.ELEMENT_COLOR[card.element], false))

	if card.is_creature():
		vb.add_child(_label("ATK %d   /   DEF %d" % [card.attack, card.defense], 12,
			Color("#ffd76a"), false))

	vb.add_child(_label(_card_rules(card), 11, Color("#cfd6e4"), false))
	vb.add_child(_label("clique numa tile para invocar", 10, Color("#8d93a8"), false))

	# o tamanho só existe depois do layout; `reset_size` resolve a linha
	# principal, e a faixa sobe para ficar acima dos botões
	_card_info.reset_size()
	_card_info.visible = true
	var v := _viewport_size()
	_card_info.position = Vector2(20, v.y - 96 - _card_info.size.y - 8.0)


## `wrap` desligado para linhas curtas: com autowrap o Godot calcula a altura
## mínima quebrando o texto na largura atual, que antes do layout é ~0, e a
## caixa explode para uma letra por linha.
func _label(text: String, size: int, color: Color, wrap := true) -> Label:
	var l := Label.new()
	l.text = UiKit.fold(text)
	l.add_theme_font_override("font", load(FONT_PATH))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A regra que o jogador precisa para decidir a jogada. Cabe numa linha, porque
## o objetivo é informar e sair da frente. 
func _card_rules(card: CardData) -> String:
	match card.kind:
		CardData.Kind.CREATURE:
			return "Só na linha principal, em tile com terreno %s." % card.element_text()
		CardData.Kind.TERRAIN:
			return "Pinta um tile livre com %s e libera criaturas %s." % [
				card.element_text(), card.element_text()]
		CardData.Kind.BUILDING:
			return "Vai na linha secundária (fundo)."
		_:
			return card.effect_text()


func _card_info_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.08, 0.92)
	sb.border_color = Color("#6b5a94")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(10)
	return sb


func clear_card_info() -> void:
	if _card_info == null:
		return
	_card_info.visible = false
	for c in _card_info.get_children():
		_card_info.remove_child(c)
		c.queue_free()


# --- reinício de partida ----------------------------------------------------

## Apaga o resíduo visual da partida anterior. Sem isto o REINICIAR deixava
## duas coisas na tela que não pertencem mais à partida: os números de dano
## flutuando (o `Label` do `float_number` só morre quando o tween acaba) e o
## rastro amarelo da barra de HP (que é estado animado indexado por `side`,
## não estado do `Game` — o `Game.reset` não existe, ele troca o objeto
## inteiro, e o dicionário do HUD sobrevive).
##
## **Chamar ANTES de `Game.start_game()`.** O `start_game` já emite
## `phase_changed(ROLL)`, que reposiciona a dica "CLIQUE NO DADO"; limpar
## depois apagaria o aviso da partida nova.
##
## Idempotente de propósito: pode ser chamada com o HUD ainda vazio (antes do
## `setup()`), duas vezes seguidas, ou a cada REINICIAR, sem efeito colateral.
func reset_session() -> void:
	# 1. Tweens primeiro. Um tween vivo escreveria em nós que já saíram da
	#    árvore, e o `_banner` voltaria a acender sozinho no meio da partida
	#    nova.
	_kill_own_tweens()

	# 2. Números de dano / buff / erro que ainda estavam subindo. O
	#    `remove_child` antes do `queue_free` tira da árvore no mesmo frame:
	#    só com `queue_free` o Label ainda é desenhado neste frame.
	if _fx != null:
		for c in _fx.get_children():
			_fx.remove_child(c)
			c.queue_free()

	# 3. Barras. Esvaziar os dicionários faz o `_tick_panels` semear de novo
	#    a partir do `Game` novo no próximo frame — é o mesmo caminho de
	#    "primeiro frame de partida", então a barra de mana começa a encher
	#    em vez de mostrar o valor antigo.
	_hp_shown.clear()
	_hp_ghost.clear()
	_mana_shown.clear()
	_mana_peak.clear()
	_flash.clear()
	_heal_flash.clear()
	_farm_burst_seq = 0
	# Placar da fase: some junto com a partida, senão o REINICIAR deixa um
	# placar da partida velha na coluna esquerda. O `_heal_flash` é limpo
	# acima, e não dentro de `clear_farm`, porque ele pertence à barra de vida
	# e precisa sobreviver ao fim da fase (o bônus chega logo depois dela).
	clear_farm()

	# 4. Avisos momentâneos e o painel de lado. `_turn_side = -1` é o estado
	#    neutro (nenhum painel aceso): depois do reinício quem decide o
	#    destaque é o `set_turn` do próximo turno, não a partida velha.
	_turn_label = ""
	_turn_color = Color(1, 1, 1)
	_turn_timer = 0.0
	_turn_side = -1
	_log_hint_timer = 0.0

	# 5. Banner de vitória/erro: sem o tween morto ele voltaria a aparecer.
	if _banner != null:
		_banner.text = ""
		_banner.modulate.a = 0.0
		_banner.scale = Vector2.ONE

	set_input_locked(false)


func _process(delta: float) -> void:
	_tick_panels(delta)
	if _turn_timer > 0.0:
		_turn_timer = maxf(0.0, _turn_timer - delta)
	if _log_hint_timer > 0.0:
		_log_hint_timer = maxf(0.0, _log_hint_timer - delta)
	_tick_farm(delta)

	# Todos os painéis precisam ser marcados para redesenhar. Antes só o
	# `_badges` entrava na lista, e como o `draw` de um Control só dispara
	# quando ele é invalidado, as barras de HP e o painel de round eram
	# desenhados UMA vez e nunca mais: a vida caía no estado, o texto não.
	for c in [_top_bar, _player_panel, _ai_panel, _badges, _turn_glow,
			_farm_panel]:
		if c:
			c.queue_redraw()


## Decaimento do placar da fase. Tudo aqui é conta de `_process`, nunca uma
## corrotina com `await` (armadilha 1): a fase de farm tem várias pausas e um
## `await` deixaria o placar preso em algum estado intermediário para sempre.
func _tick_farm(delta: float) -> void:
	if _farm_out > 0.0:
		_farm_out = maxf(0.0, _farm_out - delta)
		if _farm_out <= 0.0:
			# só desliga aqui: o `draw` já começou a apagar nos últimos 0.6s
			_farm_on = false
	for side in _farm_pop.keys():
		_farm_pop[side] = maxf(0.0, float(_farm_pop[side]) - delta * 2.6)
	for side in _farm_pip_flash.keys():
		var fl: Array = _farm_pip_flash[side]
		for i in fl.size():
			fl[i] = maxf(0.0, float(fl[i]) - delta * 1.6)
	for side in _heal_flash.keys():
		_heal_flash[side] = maxf(0.0, float(_heal_flash[side]) - delta * 1.2)


## Interpola as barras em direção ao estado real. A vida desce em ~0.35s e o
## rastro amarelo drena mais devagar, ~1s: essa diferença de velocidade é o
## que faz o olho ler "levou dano" em vez de "um número mudou".
func _tick_panels(delta: float) -> void:
	for p in Game.players:
		var side := p.side
		var ratio := float(p.hp) / float(maxi(p.max_hp, 1))
		if not _hp_shown.has(side):
			_hp_shown[side] = ratio
			_hp_ghost[side] = ratio
			_mana_shown[side] = 0.0
			_mana_peak[side] = maxi(p.mana, 1)

		# O rastro é preso no ponto onde a barra ESTAVA, não no valor real: ele
		# representa "onde você estava antes de apanhar". Perseguir o valor
		# real fazia ele sumir antes do olho alcançar.
		var prev: float = _hp_shown[side]
		if ratio < prev:
			_hp_ghost[side] = maxf(_hp_ghost[side], prev)
		elif ratio > _hp_ghost[side]:
			_hp_ghost[side] = ratio
		_hp_shown[side] = move_toward(prev, ratio, delta * 3.2)

		if _hp_ghost[side] > _hp_shown[side] + 0.001:
			_hp_ghost[side] = maxf(_hp_shown[side], _hp_ghost[side] - delta * 0.55)

		_mana_shown[side] = move_toward(_mana_shown[side], float(p.mana), delta * 6.0)
		_mana_peak[side] = maxi(int(_mana_peak[side]), p.mana)

		var f: float = _flash.get(side, 0.0)
		if f > 0.0:
			_flash[side] = maxf(0.0, f - delta * 2.0)


## Um dado por vez: gira por ~0.75s com faces aleatórias e trava no valor
## sorteado. Depois de ~0.5s parado, sai o próximo lado.
# --- log -------------------------------------------------------------------

## O log é só conferência, não leitura de jogo: fica escondido e abre com [L].
## Deixá-lo à vista fazia o jogador ler texto em vez de olhar o tabuleiro — e
## o tabuleiro é que não tinha feedback.
func toggle_log() -> void:
	if _log == null:
		return
	_log.visible = not _log.visible
	_flash_log_hint()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_L:
		toggle_log()
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_ESCAPE:
		# atalho para dispensar o aviso momentâneo que cobre o tabuleiro
		_turn_timer = 0.0


## Faz o "L: log" piscar quando o log abre ou fecha, para o jogador descobrir
## a tecla sem precisar de tutorial.
func _flash_log_hint() -> void:
	_log_hint_timer = 2.0
