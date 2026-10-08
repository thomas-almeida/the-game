extends Node

## Renderiza a cena principal e salva um PNG, para conferir a UI sem abrir
## a janela. Uso:  godot --path . res://tests/shot.tscn
##
## Também reporta a cobertura de glifos da fonte pixel — o
## TinyFontCraftpixPixel éLatino básico e NÃO tem acentos, o que importa
## porque a UI está em português.

const OUT_DIR := "user://"


## Cria um clique de mouse numa posição de tela, para exercitar o mesmo caminho
## do input real sem depender de janela com foco.
static func _click_at(pos: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pos
	e.global_position = pos
	return e


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)

	await get_tree().process_frame
	await get_tree().process_frame

	# opcional: avanca N turnos com a heurística da IA nos dois lados, para
	# a captura mostrar o tabuleiro com terreno e criaturas.
	var args := OS.get_cmdline_user_args()
	var turns := 0
	if args.size() > 0:
		turns = int(args[0])
	for i in turns:
		if Game.is_over():
			break
		AiBrain.run(Game, Board.Side.PLAYER)
		Game.end_turn()
		# no jogo quem sorteia a mana é o clique no dado
		Game.commit_roll()
		await get_tree().process_frame

	# opcional: ponteiro de teste, para conferir hover/tilt na captura. Vem no
	# FIM do script, senão o hover fica preso na carta durante a captura da
	# apresentação do turno.
	var want := Vector2.ZERO
	var use_mouse := args.size() >= 3

	# opcional: termina o turno e espera a apresentação tocar, para conferir o
	# dado, o véu do rival e a sequência de dano numa captura
	if args.size() >= 4 and int(args[3]) > 0:
		var mode := int(args[3])
		if mode == 999:
			# modo de inspeção: força o estado do turno do rival e segura, para
			# conferir o visual sem depender do frame rate da máquina
			var hud = main.get("_hud")
			hud.set_input_locked(true)
			hud.announce_turn(Board.Side.AI, 99.0)
			# Não se mexe em `_dice_t` nem em `show_dice_rolls` aqui: nada
			# disso existe mais no HUD (a rolagem foi para os dados 3D e para
			# o log). Chamar método inexistente matava o script antes da
			# captura, então este modo estava morto.
			for i in 6:
				await get_tree().process_frame
		elif mode == 997:
			# fluxo completo: espera a rodada pedir o dado, clica nele, e depois
			# invoca uma carta com a mana que saiu. É o caminho real do jogador.
			var guard := 0
			while not Game.roll_pending and guard < 400:
				guard += 1
				await get_tree().process_frame
			var cam3 = main.get("_camera")
			var die3 = main.get("_die")
			main._unhandled_input(_click_at(
				cam3.unproject_position(die3.global_position)))
			for i in 90:
				await get_tree().process_frame
			print("DEBUG rolando: mana=", Game.player().mana,
				" face=", die3.face, " mao=", Game.player().hand.size(),
				" vez=", Game.is_player_turn())

			# invoca a primeira criatura que a mana pagar, numa tile válida
			var chosen := -1
			for i in Game.player().hand.size():
				var c2 := CardDB.get_card(Game.player().hand[i])
				if c2.is_creature() and Game.player().has_mana(c2.cost):
					chosen = i
					break
			if chosen < 0:
				print("DEBUG nenhuma criatura pagavel com ", Game.player().mana)
			else:
				var cr := CardDB.get_card(Game.player().hand[chosen])
				print("DEBUG invocando ", cr.title, " (custo ", cr.cost, ")")
				main._on_card_clicked(chosen)
				for i in 4:
					await get_tree().process_frame
				# procura uma tile legal pela própria regra, não chutando
				var spot := Vector2i(-1, -1)
				for row in Board.ROWS:
					for col in Board.COLS:
						if Rules.can_place(Game.board, Board.Side.PLAYER, cr,
								col, row) == Rules.OK:
							spot = Vector2i(col, row)
							break
					if spot.x >= 0:
						break
				if spot.x < 0:
					print("DEBUG sem tile legal para ", cr.title)
				else:
					main._on_tile_clicked(spot.x, spot.y)
					for i in 24:
						await get_tree().process_frame
					var be = Game.board.get_entity(spot.x, spot.y)
					print("DEBUG tile ", spot, " tem=", be != null,
						" mana restante=", Game.player().mana)
		elif mode == 998:
			# clica no dado pelo mesmo caminho do mouse: mesmo código de entrada,
			# mesma checagem de proximidade
			var cam2 = main.get("_camera")
			var die = main.get("_die")
			var at2: Vector2 = cam2.unproject_position(die.global_position)
			print("DEBUG clicaria em ", at2, " roll_pending=", Game.roll_pending)
			main._unhandled_input(_click_at(at2))
			print("DEBUG apos clique: roll_pending=", Game.roll_pending,
				" mana=", Game.player().mana, "/", Game.opponent().mana,
				" face=", die.face, " die_rolando=", die.rolling)
			for i in 90:
				await get_tree().process_frame
			print("DEBUG fim da rolagem: face=", die.face,
				" die_rolando=", die.rolling,
				" ending=", main.get("_ending_turn"),
				" lock=", main.get("_hud")._input_locked)
		elif mode == 993:
			# GALERIA dos cinco tiros: um por elemento, lado a lado, com várias
			# capturas durante o voo. O agente só tinha visto imagem ESTÁTICA, e o
			# que distingue os elementos é o movimento (arco, balanço, erraticidade).
			#
			# Uso: -- 0 0 0 993
			var farm993: Farm3D = main.get("_farm")
			var cam993: Camera3D = main.get("_camera")
			var org: Vector3 = cam993.project_position(Vector2(240.0, 470.0), 14.0)
			var tgt: Vector3 = cam993.project_position(Vector2(1000.0, 330.0), 14.0)
			print("DEBUG galeria de ", org, " para ", tgt)
			farm993.demo_gallery(org, tgt)
			var caps993 := 0
			for f993 in 200:
				await get_tree().process_frame
				var bolts993: Node = farm993.get("_bolts")
				# captura a cada 5 frames enquanto houver algo voando, até 8
				if bolts993 != null and bolts993.get_child_count() > 0 \
						and caps993 < 8 and f993 % 5 == 0:
					caps993 += 1
					get_viewport().get_texture().get_image().save_png(
						OUT_DIR + "shot_gal_%d.png" % caps993)
					print("DEBUG galeria captura ", caps993, " no frame ", f993,
						" voando=", bolts993.get_child_count())
			print("DEBUG galeria: ", caps993, " capturas")
		elif mode == 994:
			# Pipeline COMPLETO da fase de farm: eventos reais do `Game` -> fila de
			# efeitos do `main_3d` -> cena 3D + HUD. É o único modo que prova a
			# integração; o 995 só força o HUD isolado.
			#
			# Uso: -- 2 0 0 994   (2 turnos de IA antes: cai na rodada 3 = farm)
			# Captura em marcas de frame contadas A PARTIR do início do farm, não
			# do script: o fim de turno espera 1.3s de relógio antes de começar, e
			# o renderizador roda a taxa imprevisível.
			var f994 := 0
			var start994 := -1
			var bolt_caps994 := 0
			var direct_caps994 := 0
			var peak_mobs := 0
			var ended := false
			# Impactos do ATAQUE DIRETO no jogador: é o que prova que o tiro
			# voa até o painel de vida e que o efeito de dano espera o impacto.
			var direct_hits: Array = []
			var farm_obj: Farm3D = main.get("_farm")
			farm_obj.point_impact.connect(func(ss: int, pos: Vector3, amt: int, el: int) -> void:
				direct_hits.append([ss, amt, el, pos]))
			print("DEBUG farm: round=", Game.round, " is_farm=", Game.is_farm_round(),
				" criaturas jog=", Game.board.front_line(Board.Side.PLAYER).size(),
				" ia=", Game.board.front_line(Board.Side.AI).size())
			main._on_end_turn()
			while f994 < 2400:
				await get_tree().process_frame
				f994 += 1
				var farm994 = main.get("_farm")
				if start994 < 0 and farm994.active:
					start994 = f994
					print("DEBUG farm comecou no frame ", f994)
				if start994 >= 0:
					peak_mobs = maxi(peak_mobs, farm994.mob_count())
					# Projétil NO AR: é o que o usuário reclamou de não ver, e o
					# que eu nunca tinha conferido. Captura enquanto houver
					# alguém voando, no máximo 4 vezes, a cada 3 frames.
					var bolts994: Node = farm994.get("_bolts")
					if bolts994 != null and bolts994.get_child_count() > 0 \
							and bolt_caps994 < 4 and f994 % 3 == 0:
						bolt_caps994 += 1
						get_viewport().get_texture().get_image().save_png(
							OUT_DIR + "shot_bolt_%d.png" % bolt_caps994)
						var bp: Node3D = bolts994.get_child(0)
						var cam994: Camera3D = main.get("_camera")
						print("DEBUG projetil no ar #", bolt_caps994,
							" mundo=", bp.global_position,
							" tela=", cam994.unproject_position(bp.global_position),
							" no ar=", bolts994.get_child_count())
					# tiro de ATAQUE DIRETO em voo: a fase de farm já acabou
					# (`active` falso) e ainda há projétil no ar
					if not farm994.active and bolts994 != null \
							and bolts994.get_child_count() > 0 \
							and direct_caps994 < 3 and f994 % 3 == 0:
						direct_caps994 += 1
						get_viewport().get_texture().get_image().save_png(
							OUT_DIR + "shot_direct_%d.png" % direct_caps994)
						print("DEBUG tiro direto em voo #", direct_caps994,
							" no ar=", bolts994.get_child_count())
					var k994 := f994 - start994
					if k994 == 60:
						# onde os mobs REALMENTE estão. Julgar "nas pontas da
						# trilha" por uma captura foi o erro: eles estavam no z
						# da fileira do tabuleiro (z=0), nao no da trilha.
						var cam60: Camera3D = main.get("_camera")
						for lane60 in [Board.Side.PLAYER, Board.Side.AI]:
							for i60 in 6:
								var pos60: Vector3 = farm994.mob_position(lane60, i60)
								if pos60 == Vector3.ZERO:
									continue
								print("DEBUG mob lane=", lane60, " i=", i60,
									" mundo=(", snappedf(pos60.x, 0.01), ", ",
									snappedf(pos60.z, 0.01), ")",
									" tela=", cam60.unproject_position(pos60))
					if k994 in [40, 110, 200, 300]:
						get_viewport().get_texture().get_image().save_png(
							OUT_DIR + "shot_run_%d.png" % k994)
						print("DEBUG captura +", k994, " mobs=", farm994.mob_count(),
							" fila=", main.get("_fx_queue").size())
				if start994 >= 0 and not main.get("_ending_turn") and f994 > start994 + 20:
					ended = true
					break
			print("DEBUG ataques diretos que chegaram: ", direct_hits.size())
			for dh in direct_hits:
				print("DEBUG   impacto: atirador do lado ", dh[0], " dano ", dh[1],
					" elemento ", dh[2], " em (", snappedf(dh[3].x, 0.1), ", ",
					snappedf(dh[3].y, 0.1), ", ", snappedf(dh[3].z, 0.1), ")")
			print("DEBUG fim do farm: frames=", f994, " ended=", ended,
				" pico de mobs=", peak_mobs, " round=", Game.round,
				" farm_pending=", Game.farm_pending, " fase=", Game.phase_label())
			if not ended:
				print("FALHOU: a apresentacao do farm nao terminou")
			elif start994 < 0:
				print("FALHOU: o farm nunca comecou (rodada nao era de farm?)")
			else:
				print("OK: farm tocou do inicio ao fim e devolveu o controle")
		elif mode == 990:
			# CENÁRIO IMPLANTADO: dispara um ataque direto da trilha do JOGADOR
			# contra o painel de vida do RIVAL, sem depender do estado aleatório
			# da partida (que, duas vezes, não produzia nenhum no 994).
			#
			# Uso: -- 0 0 0 990
			var farm990: Farm3D = main.get("_farm")
			var impactos := [0]
			farm990.point_impact.connect(func(s,p,a,e): impactos[0] += 1)
			Game.events.append({
				"type": "player_damage", "side": Board.Side.AI, "amount": 3,
				"source": "GOLEM", "from_col": 1, "from_row": 2,
				"from_side": Board.Side.PLAYER, "element": CardData.Element.EARTH})
			main._sync()
			var c990 := 0
			for f990 in 140:
				await get_tree().process_frame
				var bolts990: Node = farm990.get("_bolts")
				if bolts990 != null and bolts990.get_child_count() > 0 \
						and c990 < 5 and f990 % 6 == 0:
					c990 += 1
					get_viewport().get_texture().get_image().save_png(
						OUT_DIR + "shot_g990_%d.png" % c990)
			print("DEBUG ataque direto plantado: impactos=", impactos[0],
				" capturas_voo=", c990, " manajog=", Game.player().mana)
		elif mode == 995:
			# Fase de farm: força o estado do HUD DIRETO, sem esperar os eventos
			# (eles ainda não saem do `Game`). Prova três coisas numa execução
			# só, porque cada execução abre uma janela de verdade:
			#   shot_farm.png        -> placar no meio da fase + número de dano
			#   shot_farm_bonus.png  -> bônus: banner, faixa e "+1" nas criaturas
			#   shot.png (o do fim)  -> o estado do bônus, por acidente
			var hud995 = main.get("_hud")

			# Tabuleiro com criaturas: sem criatura o bônus não tem onde estourar
			# os "+1" e a captura não prova nada. A IA joga dos dois lados, que é
			# o jeito confiável de encher o tabuleiro.
			for t995 in 8:
				if Game.is_over():
					break
				AiBrain.run(Game, Board.Side.PLAYER)
				Game.end_turn()
				Game.commit_roll()
				for f in 4:
					await get_tree().process_frame
			var criaturas995 := 0
			for row in Board.ROWS:
				for col in Board.COLS:
					var e995 = Game.board.get_entity(col, row)
					if e995 != null and e995.card().is_creature():
						criaturas995 += 1
			if criaturas995 == 0:
				print("FALHOU: nenhuma criatura na cena, o bonus nao tem onde aparecer")

			# Posições de mundo FALSAS, onde as trilhas vão ficar: embaixo da
			# linha 3 (jogador) e em cima da linha 0 (rival). Servem para ver
			# onde os números de dano caem na tela.
			var lane_p := Vector3(-2.2, 0.9, 4.4)
			var lane_a := Vector3(2.2, 0.9, -4.4)
			hud995.farm_begin(6)
			for i in 6:
				hud995.farm_mob_spawned(Board.Side.PLAYER, i, 1 + i % 6)
				hud995.farm_mob_spawned(Board.Side.AI, i, 1 + (i * 2) % 6)

			# --- meio da fase: 3 x 2, com um fugido de cada lado -------------
			hud995.farm_mob_hit(Board.Side.PLAYER, 0, 3, 0, lane_p)
			hud995.farm_mob_killed(Board.Side.PLAYER, 0)
			hud995.farm_mob_hit(Board.Side.PLAYER, 1, 2, 1, lane_p + Vector3(1.4, 0, 0))
			hud995.farm_mob_killed(Board.Side.PLAYER, 1)
			hud995.farm_mob_escaped(Board.Side.PLAYER, 5)
			hud995.farm_mob_hit(Board.Side.AI, 0, 3, 0, lane_a)
			hud995.farm_mob_killed(Board.Side.AI, 0)
			hud995.farm_mob_hit(Board.Side.AI, 1, 1, 1, lane_a - Vector3(1.4, 0, 0))
			hud995.farm_mob_killed(Board.Side.AI, 1)
			hud995.farm_mob_hit(Board.Side.AI, 2, 2, 2, lane_a - Vector3(2.8, 0, 0))
			hud995.farm_mob_escaped(Board.Side.AI, 5)
			# o ÚLTIMO tiro é disparado já no fim: o brilho do pip decai em
			# ~0.5s, e uma captura com o brilho já drenado não mostra o feedback
			hud995.farm_mob_hit(Board.Side.AI, 3, 1, 4, lane_a - Vector3(4.2, 0, 0))
			await get_tree().process_frame
			await get_tree().process_frame

			print("FARM meio: placar=", hud995._farm_score,
				" pips=", hud995._farm_pips,
				" slots=", hud995._farm_slots,
				" on=", hud995._farm_on,
				" faixa='", hud995._turn_label, "'",
				" criaturas=", criaturas995)
			if int(hud995._farm_score.get(Board.Side.PLAYER, 0)) != 3 \
					or int(hud995._farm_score.get(Board.Side.AI, 0)) != 2:
				print("FALHOU: placar da fase fora do esperado")
			# 6 slots, e o sexto marcado como fugido: se a lista vier vazia o
			# índice abaixo mataria o script antes da captura
			var pips995: Array = hud995._farm_pips.get(Board.Side.PLAYER, [])
			if pips995.size() != 6 or int(pips995[5]) != 1:
				print("FALHOU: pips da trilha do jogador fora do esperado: ", pips995)

			var img995 := get_viewport().get_texture().get_image()
			var farm_path := OUT_DIR + "shot_farm.png"
			img995.save_png(farm_path)
			print("captura da fase -> ", ProjectSettings.globalize_path(farm_path))

			# --- fim da fase + bônus do jogador ------------------------------
			hud995.farm_end(3, 2, Board.Side.PLAYER)
			hud995.farm_bonus(Board.Side.PLAYER, 1, 2)
			for i in 6:
				await get_tree().process_frame
			print("FARM bonus: faixa='", hud995._turn_label, "'",
				" banner='", hud995._banner.text, "'",
				" cura=", snappedf(hud995._heal_flash.get(Board.Side.PLAYER, 0.0),
					0.001),
				" numeros_flutuantes=", hud995._fx.get_child_count(),
				" placar_ainda_visivel=", hud995._farm_on)
			if hud995._fx.get_child_count() == 0:
				print("FALHOU: nenhum numero flutuante, o bonus nao estourou")
			var img995b := get_viewport().get_texture().get_image()
			var bonus_path := OUT_DIR + "shot_farm_bonus.png"
			img995b.save_png(bonus_path)
			print("captura do bonus -> ", ProjectSettings.globalize_path(bonus_path))
		elif mode > 0:
			main._on_end_turn()
			# espera em FRAMES, não em segundos: o renderizador em software roda
			# a uma taxa imprevisível e o tempo de parede não bate
			var hud2 = main.get("_hud")
			for i in mode:
				print("DEBUG f", i, " ending=", main.get("_ending_turn"),
					" locked=", hud2._input_locked,
					" fila=", main.get("_fx_queue").size(),
					" busy=", main.get("_fx_busy"))
				await get_tree().process_frame
		else:
			main._on_end_turn()
			# espera em FRAMES, não em segundos: o renderizador em software roda
			# a uma taxa unpredictable e o tempo de parede não bate
			for i in mode:
				await get_tree().process_frame
			print("DEBUG pos-termino ending=", main.get("_ending_turn"),
				" fila=", main.get("_fx_queue").size(),
				" busy=", main.get("_fx_busy"))

	# opcional: exercita a jogada real — seleciona uma carta de terreno e
	# invoca na tile 0,0, passando por `_on_card_clicked` / `_on_tile_clicked`
	# (os mesmos que o input chamam). Confere que clicar carta + clicar tile
	# invoca, e que a faixa de leitura some depois.
	if args.size() >= 6:
		var pick := -1
		for i in Game.player().hand.size():
			if CardDB.get_card(Game.player().hand[i]).kind == CardData.Kind.TERRAIN:
				pick = i
				break
		if pick < 0:
			print("JOGADA: sem carta de terreno na mao")
		else:
			print("JOGADA: seleciona carta ", pick, " ",
				CardDB.get_card(Game.player().hand[pick]).title)
			main._on_card_clicked(pick)
			for i in 8:
				await get_tree().process_frame
			if args.size() >= 6:
				print("JOGADA: invoca na tile ", args[4], ",", args[5])
				main._on_tile_clicked(int(args[4]), int(args[5]))
				for i in 20:
					await get_tree().process_frame

	if use_mouse:
		want = Vector2(float(args[1]), float(args[2]))
		var hand = main.get("_hand")
		if hand:
			hand.mouse_override = want
		print("ponteiro de teste em ", want)
		for i in 20:
			await get_tree().process_frame

	# opcional: 1 = log aberto. Confere a tecla [L] sem precisar de teclado.
	var hud_chk = main.get("_hud")
	if args.size() >= 5 and int(args[4]) == 1:
		hud_chk.toggle_log()
		for i in 6:
			await get_tree().process_frame
		print("DEBUG log visivel=", hud_chk._log.visible,
			" linhas=", hud_chk._log.get_line_count())

	# opcional: 2 = imprime onde os dados caem na tela, para calibrar a posição
	if args.size() >= 5 and int(args[4]) == 2:
		var cam = main.get("_camera")
		var vp := get_viewport().get_visible_rect().size
		for label in ["jogador", "rival"]:
			var d = main.get("_die" if label == "jogador" else "_ai_die")
			var sp: Vector2 = cam.unproject_position(d.global_position)
			print("DADO ", label, " vp=", sp, " ratio=", Vector2(sp.x / vp.x, sp.y / vp.y))

	# opcional: 996 = joga alguns turnos, aperta REINICIAR e confere as DUAS
	# coisas que podem sobrar da partida velha: as criaturas na cena 3D (o
	# `start_game` troca o `Board` por outro objeto) e o resíduo no HUD (o
	# `Label` do número flutuante e o dicionário de estado animado das barras).
	if args.size() >= 5 and int(args[4]) == 996:
		var b996 = main.get("_board")
		var hud996 = main.get("_hud")
		var fx996 = hud996.get("_fx")
		# Deixa a IA jogar de verdade: é o jeito mais confiável de encher o
		# tabuleiro de criaturas. Invocar carta na mão não serve, porque quase
		# sempre o que sai primeiro é TERRENO — e terreno só pinta a tile, não
		# cria Entity3D, que é justamente o que vaza no bug.
		for t996 in 8:
			if Game.is_over():
				break
			AiBrain.run(Game, Board.Side.PLAYER)
			Game.end_turn()
			Game.commit_roll()
			for f in 4:
				await get_tree().process_frame

		var antes := 0
		for k in b996._entities:
			if is_instance_valid(b996._entities[k]):
				antes += 1
		var orfas_antes := 0
		for ch in b996.get_children():
			if ch is Entity3D and is_instance_valid(ch):
				orfas_antes += 1
		print("DEBUG antes do reinicio: no dicionario=", antes,
			" nos na cena=", orfas_antes, " round=", Game.round)
		if antes == 0:
			# sem criaturas na cena o teste não prova nada: "0 depois de 0" é
			# justamente o que aconteceu nas duas tentativas anteriores
			print("FALHOU: nao havia criatura na cena, o teste nao valida nada")

		# --- monta o resíduo de HUD do jeito que o jogo produz -----------
		# `float_number` cria o Label em `_fx` e só o tween o libera; a barra
		# só ganha o rastro amarelo depois que o `_tick_panels` vê a vida
		# menor que o valor animado. Dois frames bastam: o rastro aparece e
		# ainda não drenou.
		hud996.float_number(Vector3(0.0, 1.0, 2.0), "-1", Color("ff7b6b"))
		Game.player().hp = maxi(Game.player().hp - 4, 1)
		hud996.on_side_damaged(Board.Side.PLAYER)
		hud996.announce_turn(Board.Side.AI, 99.0)
		hud996.show_banner("PARTIDA ANTIGA")
		for f in 2:
			await get_tree().process_frame

		var ps := Board.Side.PLAYER
		print("HUD antes: numeros flutuantes=", fx996.get_child_count(),
			" hp_shown=", snappedf(hud996._hp_shown.get(ps, -1.0), 0.001),
			" hp_ghost=", snappedf(hud996._hp_ghost.get(ps, -1.0), 0.001),
			" flash=", snappedf(hud996._flash.get(ps, 0.0), 0.001),
			" turn_label='", hud996._turn_label, "'")
		var rastro_antes: bool = hud996._hp_ghost.get(ps, 0.0) \
			> hud996._hp_shown.get(ps, 0.0) + 0.001
		if fx996.get_child_count() == 0 or not rastro_antes:
			# sem resíduo montado o teste não prova nada, pelo mesmo motivo
			print("FALHOU: nao ha residuo de HUD para limpar, teste invalido")

		# --- a sequencia que o REINICIAR vai fazer ------------------------
		# `reset_session()` ANTES do botao, e não depois: o `start_game` emite
		# `phase_changed(ROLL)` e reposiciona a dica "CLIQUE NO DADO".
		hud996.reset_session()
		print("HUD no mesmo frame do reset: numeros flutuantes=",
			fx996.get_child_count(),
			" hp_shown vazio=", hud996._hp_shown.is_empty(),
			" hp_ghost vazio=", hud996._hp_ghost.is_empty(),
			" flash vazio=", hud996._flash.is_empty(),
			" turn_label='", hud996._turn_label, "'",
			" tweens=", hud996._own_tweens.size())

		hud996._new_button.pressed.emit()
		for i in 20:
			await get_tree().process_frame
		var depois := 0
		for k in b996._entities:
			if is_instance_valid(b996._entities[k]):
				depois += 1
		var orfas := 0
		for ch in b996.get_children():
			if ch is Entity3D and is_instance_valid(ch):
				orfas += 1
		var terreno := 0
		for tl in b996._tiles:
			if tl._terrain_element >= 0:
				terreno += 1
		print("DEBUG depois do reinicio: no dicionario=", depois,
			" nos na cena=", orfas, " tiles com terreno=", terreno,
			" round=", Game.round, " hp=", Game.player().hp,
			" mao=", Game.player().hand.size())
		print("HUD depois: numeros flutuantes=", fx996.get_child_count(),
			" hp=", Game.player().hp, "/", Game.player().max_hp,
			" hp_shown=", snappedf(hud996._hp_shown.get(ps, -1.0), 0.001),
			" hp_ghost=", snappedf(hud996._hp_ghost.get(ps, -1.0), 0.001),
			" flash=", snappedf(hud996._flash.get(ps, 0.0), 0.001),
			" turn_label='", hud996._turn_label, "'",
			" banner='", hud996._banner.text, "'")
		if antes > 0 and depois == 0 and orfas == 0:
			print("OK: criaturas someyram no reinicio")
		elif antes > 0:
			print("FALHOU: sobrou entidade apos o reinicio")

		# rastro amarelo = a faixa entre a barra atual e onde ela estava. Sem
		# limpá-la a captura mostra uma mancha que não pertence à partida nova.
		var rastro_depois: bool = hud996._hp_ghost.get(ps, 0.0) \
			> hud996._hp_shown.get(ps, 0.0) + 0.001
		if fx996.get_child_count() == 0 and not rastro_depois \
				and snappedf(hud996._flash.get(ps, 0.0), 0.001) == 0.0:
			print("OK: HUD sem residuo apos o reinicio")
		else:
			print("FALHOU: sobrou residuo de HUD apos o reinicio")

		# idempotencia: pode chamar de novo (e no primeiro frame) sem erro
		hud996.reset_session()
		hud996.reset_session()
		for i in 4:
			await get_tree().process_frame
		print("OK: reset_session idempotente, numeros flutuantes=",
			fx996.get_child_count())

# opcional: 4 = impõe um valor no dado e segura, para conferir os pips
	if args.size() >= 6 and int(args[4]) == 4:
		# Valor 0 = confere os seis de uma vez, num processo só (cada
		# execução abre uma janela de verdade).
		#
		# Para cada valor calcula QUAL NÚMERO está de fato virado para a câmera:
		# a face cuja normal tem o maior produto escalar com a direção
		# câmera->dado. Comparar isso com o valor sorteado é a prova direta. A
		# versão anterior só conferia `basis.z`, que é a imagem do eixo Z local,
		# e não da normal da face — e deu "confere" para um dado que mostrava a
		# face oposta nos números 3 a 6.
		var die4 = main.get("_die")
		var cam4: Camera3D = main.get("_camera")
		var values4: Array = [int(args[5])] if int(args[5]) > 0 else [1, 2, 3, 4, 5, 6]
		var all_ok := true
		for v4 in values4:
			die4.roll_to(v4)
			var guard4 := 0
			while die4.rolling and guard4 < 300:
				guard4 += 1
				await get_tree().process_frame
			var cam_pos: Vector3 = cam4.global_position
			var die_pos: Vector3 = die4.global_position
			var to_cam: Vector3 = (cam_pos - die_pos).normalized()
			var best_n := -1
			var best_dot := -2.0
			for k4 in 6:
				var wn: Vector3 = die4.transform.basis * Die3D.FACE_AXIS[k4]
				var d4: float = wn.normalized().dot(to_cam)
				if d4 > best_dot:
					best_dot = d4
					best_n = k4 + 1
			# tipado: `v4` vem de um Array sem tipo (Variant), e `best_n == v4`
			# não deixa o GDScript inferir o tipo — o parse falhava e a janela de
			# teste ficava aberta para sempre numa tela de erro
			var ok4: bool = best_n == int(v4)
			all_ok = all_ok and ok4
			print("DADO sorteado=", v4, " numero virado para a camera=", best_n,
				" (dot ", snappedf(best_dot, 0.001), ") ", "OK" if ok4 else "FALHOU")
		print("DADO: ", "OK - as 6 faces conferem" if all_ok else "FALHOU")

	# opcional: 3 =_dump das criaturas: tamanho real do sprite no mundo
	if args.size() >= 5 and int(args[4]) == 3:
		var b3 = main.get("_board")
		for key in b3._entities:
			var en = b3._entities[key]
			var sp3 = en._sprite
			var card3 = en.entity.card()
			var tex: Texture2D = sp3.texture if sp3 else null
			print("SLIME ", card3.title, " slime=", card3.slime,
				" pixel_size=", sp3.pixel_size if sp3 else -1.0,
				" tex=", tex.get_size() if tex else Vector2i.ZERO,
				" mundo=", (tex.get_size() * sp3.pixel_size) if tex else Vector2i.ZERO,
				" pos=", sp3.position if sp3 else Vector3.ZERO,
				" vis=", sp3.visible if sp3 else false)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	_report_font()

	var img := get_viewport().get_texture().get_image()
	var path := OUT_DIR + "shot.png"
	img.save_png(path)
	print("screenshot (", turns, " turnos) -> ", ProjectSettings.globalize_path(path))
	get_tree().quit()


func _report_font() -> void:
	var f: Font = ThemeDB.fallback_font
	print("fonte: ", f.resource_path if f else "nenhuma")
	if f == null:
		return
	var probes := "ÁÀÂÃÉÊÍÓÔÕÚÇáàâãéêíóôõúç—×·▸"
	var missing := ""
	for i in probes.length():
		var ch := probes.unicode_at(i)
		if not f.has_char(ch):
			missing += probes[i]
	print("glifos faltando: [", missing, "]")
