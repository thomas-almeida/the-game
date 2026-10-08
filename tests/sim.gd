extends SceneTree

## Simula partidas headless para validar as regras.
## Uso:  godot --headless --path . --script res://tests/sim.gd
##
## A contagem é argumentável porque o empate travado aparecia em ~1 de cada 700
## partidas: com 60 execuções não há como afirmar que sumiu. Passando um número
## maior, o uso é `godot ... --script res://tests/sim.gd -- 1000`.

const DEFAULT_RUNS := 60

var _runs := DEFAULT_RUNS


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_runs = maxi(int(args[0]), 1)
	_run_all()


func _run_all() -> void:
	var wins := {Board.Side.PLAYER: 0, Board.Side.AI: 0}
	var max_round := 0
	var errors: Array[String] = []
	var farm_stats := {
		"fases": 0,
		"empates": 0,
		"venceu_jog": 0,
		"venceu_ia": 0,
		"elemento": {},
		"bônus": 0,
		"bônus_lado": {Board.Side.PLAYER: 0, Board.Side.AI: 0},
		"mobs_mortos": 0,
		"mobs_escapados": 0,
	}

	for run in _runs:
		var game: Node = load("res://scripts/game.gd").new()
		root.add_child(game)
		game.SEED = 1000 + run * 7919
		game.start_game()

		var guard := 0
		while not game.is_over() and guard < 200:
			guard += 1

			# sanidade do estado a cada passo
			var err := _validate(game)
			if err != "":
				errors.append("run %d: %s" % [run, err])
				break

			# joga dos dois lados com a mesma heurística
			AiBrain.run(game, Board.Side.PLAYER)
			game.end_turn()
			# no jogo quem dispara é o clique no dado; aqui é a própria chamada
			var evs: Array = game.take_events()
			_farm_errors(game, evs, farm_stats, errors, run)
			game.commit_roll()

		if not game.is_over():
			errors.append("run %d (seed %d): não terminou em %d turnos\n%s" % [
				run, game.SEED, guard, _dump(game)])
		else:
			var winner := Board.Side.AI
			for p in game.players:
				if p.hp > 0:
					winner = p.side
			wins[winner] += 1
			max_round = maxi(max_round, game.round)

		root.remove_child(game)
		game.free()

	print("=== %d partidas ===" % _runs)
	print("vitórias do jogador: %d" % wins[Board.Side.PLAYER])
	print("vitórias da IA:      %d" % wins[Board.Side.AI])
	print("round mais longo:    %d" % max_round)
	_print_farm_stats(farm_stats)
	if errors.is_empty():
		print("OK — nenhuma inconsistência de estado")
	else:
		print("--- problemas (%d) ---" % errors.size())
		for e in errors.slice(0, 20):
			print("  " + e)

	quit()


func _print_farm_stats(s: Dictionary) -> void:
	print("--- fase de farm ---")
	print("fases rodadas:        %d" % s["fases"])
	print("  empatadas:          %d" % s["empates"])
	print("    das quais 0 x 0:  %d" % int(s.get("vazias", 0)))
	print("  atiradores/trilha:  %.2f (media por fase; max 3)" % (
		float(s.get("atiradores", 0)) / maxf(float(s["fases"]) * 2.0, 1.0)))
	print("  trilhas sem atirador: %d de %d (%.0f%%)" % [
		int(s.get("trilhas_sem_atirador", 0)), int(s["fases"]) * 2,
		100.0 * float(s.get("trilhas_sem_atirador", 0)) / maxf(float(s["fases"]) * 2.0, 1.0)])
	print("  abates/trilha:      %.2f (meta 2.5 a 4.5 de 6)" % (
		float(s["mobs_mortos"]) / maxf(float(s["fases"]) * 2.0, 1.0)))
	print("  venceu o jogador:   %d" % s["venceu_jog"])
	print("  venceu a IA:        %d" % s["venceu_ia"])
	print("  mobs destruídos:    %d" % s["mobs_mortos"])
	print("  mobs atravessaram:  %d" % s["mobs_escapados"])
	print("  bônus emitidos:     %d" % s["bônus"])
	var por_lado: Dictionary = s["bônus_lado"]
	print("  bônus jogador/IA:   %d / %d" % [
		por_lado[Board.Side.PLAYER], por_lado[Board.Side.AI]])
	var by_element: Dictionary = s["elemento"]
	var parts: Array[String] = []
	for label: String in CardData.ELEMENT_LABEL.values():
		parts.append("%s=%d" % [label, int(by_element.get(label, 0))])
	print("  bônus por elemento: " + " ".join(parts))


## Confere a fase de farm pelos eventos que ela acabou de emitir. É a prova de
## que o contrato sai inteiro e de que a fase FECHA: nada de mobo vivo depois
## do `farm_end`, nenhum placar que não bata com os abates, nenhum bônus no
## empate.
func _farm_errors(game, evs: Array, stats: Dictionary, errors: Array[String], run: int) -> void:
	var starts := 0
	var ends := 0
	var bonuses := 0
	var bonuses_seen := {}
	var by_element: Dictionary = {}
	var hp := {}          # "lane:i" -> vida esperada, tirada do mob_spawned
	var hits := {}        # "lane:i" -> quantos tiros levou
	var fate := {}        # "lane:i" -> "killed"/"escaped"
	var killed_by_side := {Board.Side.AI: 0, Board.Side.PLAYER: 0}
	var escaped := 0
	var end_winner := -2
	var end_p := -1
	var end_a := -1
	# Colunas distintas que atiraram, por trilha: é o número REAL de atiradores.
	# Medir `board.front_line()` depois do `end_turn` enviesava para baixo,
	# porque o brawl e o atrito já mataram criaturas quando o sim lê o estado.
	var shooter_cols := {Board.Side.AI: {}, Board.Side.PLAYER: {}}

	for ev in evs:
		var kind := String(ev.get("type", ""))
		var key := "%d:%d" % [int(ev.get("lane", -1)), int(ev.get("i", -1))]
		match kind:
			"farm_start":
				starts += 1
			"mob_spawned":
				var lane := int(ev["lane"])
				var i := int(ev["i"])
				if lane < 0 or lane > Board.Side.PLAYER:
					return _farm_error(errors, run, "mob_spawned com lane=%d" % lane)
				if i < 0 or i >= Rules.FARM_MOBS_PER_LANE:
					return _farm_error(errors, run, "mob_spawned com i=%d" % i)
				if int(ev["hp"]) < Rules.FARM_MOB_HP_MIN or int(ev["hp"]) > Rules.FARM_MOB_HP_MAX:
					return _farm_error(errors, run, "mob %d nasceu com %d de vida" % [i, int(ev["hp"])])
				if hp.has(key):
					return _farm_error(errors, run, "mob %s já existia nesta fase" % key)
				hp[key] = int(ev["hp"])
				hits[key] = 0
			"mob_moved":
				var x := float(ev["x"])
				if x < 0.0 or x > Rules.FARM_LANE_LENGTH:
					return _farm_error(errors, run, "mob %s andou para x=%.3f, fora da trilha" % [key, x])
			"mob_hit":
				if not hp.has(key):
					return _farm_error(errors, run, "mob_hit em %s, que não nasceu nesta fase" % key)
				if fate.has(key):
					return _farm_error(errors, run, "mob_hit em %s, que já tinha um final" % key)
				var amount := int(ev["amount"])
				var left := int(ev["hp_left"])
				if amount <= 0:
					return _farm_error(errors, run, "mob_hit de %d em %s" % [amount, key])
				# o `hp_left` do evento tem que ser exatamente o que sobra: nem
				# mais, nem menos. É o que pega dano perdido e dano dobrado.
				if left != maxi(int(hp[key]) - amount, 0):
					return _farm_error(errors, run,
						"mob_hit em %s: %d de dano com %d de vida, saiu hp_left=%d" % [
							key, amount, int(hp[key]), left])
				hp[key] = left
				hits[key] = int(hits[key]) + 1
				if ev.has("col"):
					shooter_cols[int(ev["lane"])][int(ev["col"])] = true
			"mob_killed":
				if not hp.has(key):
					return _farm_error(errors, run, "mob_killed em %s, que não nasceu" % key)
				if fate.has(key):
					return _farm_error(errors, run, "mob %s tem dois finais" % key)
				if int(hits[key]) == 0:
					return _farm_error(errors, run, "mob %s morreu sem levar nenhum tiro" % key)
				if int(hp[key]) != 0:
					return _farm_error(errors, run,
						"mob %s foi morto com %d de vida" % [key, int(hp[key])])
				fate[key] = "killed"
				killed_by_side[int(ev["lane"])] += 1
			"mob_escaped":
				if not hp.has(key):
					return _farm_error(errors, run, "mob_escaped em %s, que não nasceu" % key)
				if fate.has(key):
					return _farm_error(errors, run, "mob %s tem dois finais" % key)
				fate[key] = "escaped"
				escaped += 1
			"farm_end":
				ends += 1
				end_p = int(ev["player_score"])
				end_a = int(ev["ai_score"])
				end_winner = int(ev["winner"])
			"bonus":
				var bside := int(ev["side"])
				var belement := int(ev["element"])
				var bcount := int(ev["count"])
				if bside < 0 or bside > Board.Side.PLAYER:
					_farm_error(errors, run, "bonus com side=%d" % bside)
				if not CardData.ELEMENT_LABEL.has(belement):
					_farm_error(errors, run, "bonus com elemento %d" % belement)
					continue
				if bcount < 1 or bcount > Rules.FARM_BONUS_MAX_PER_ELEMENT:
					_farm_error(errors, run, "bonus com count=%d" % bcount)
					continue
				var bkey := "%d:%d" % [bside, belement]
				if bonuses_seen.has(bkey):
					_farm_error(errors, run, "bônus repetido para o par %s" % bkey)
				bonuses_seen[bkey] = true
				# o número do evento tem que ser a tabela vezes a contagem:
				# é o que garante que o bônus ESCALA, que é o ponto da feature
				var unit: Dictionary = Rules.FARM_BONUS_TABLE[belement]
				for stat: String in ["atk", "def", "mana", "heal"]:
					if int(ev[stat]) != int(unit[stat]) * bcount:
						_farm_error(errors, run, "bonus %s com %s=%d, esperado %d" % [
							bkey, stat, int(ev[stat]), int(unit[stat]) * bcount])
				bonuses += 1
				var label: String = CardData.ELEMENT_LABEL[belement]
				by_element[label] = int(by_element.get(label, 0)) + 1

	if starts == 0:
		if ends != 0 or bonuses != 0:
			_farm_error(errors, run, "eventos de farm sem farm_start")
		return
	if starts != 1 or ends != 1:
		_farm_error(errors, run, "fase de farm com %d farm_start e %d farm_end" % [starts, ends])
	if hp.size() != 2 * Rules.FARM_MOBS_PER_LANE:
		_farm_error(errors, run, "%d mobs spawnados, esperado %d" % [
			hp.size(), 2 * Rules.FARM_MOBS_PER_LANE])
	if fate.size() != hp.size():
		_farm_error(errors, run, "%d de %d mobs têm final" % [fate.size(), hp.size()])
	if killed_by_side[Board.Side.PLAYER] != end_p or killed_by_side[Board.Side.AI] != end_a:
		_farm_error(errors, run, "farm_end diz %dx%d mas %d e %d abates saíram" % [
			end_p, end_a, killed_by_side[Board.Side.PLAYER], killed_by_side[Board.Side.AI]])
	var tie := end_p == end_a
	var expect_winner := -1
	if not tie:
		expect_winner = Board.Side.PLAYER if end_p > end_a else Board.Side.AI
	if end_winner != expect_winner:
		_farm_error(errors, run, "farm_end com vencedor=%d para %dx%d" % [end_winner, end_p, end_a])
	# O bônus NÃO é prêmio da fase: não há nada a conferir entre o vencedor e
	# os `bonus`. O que já foi conferido evento a evento é que cada par
	# (lado, elemento) apareceu uma vez só e com o número certo.

	# o estado final das trilhas tem que bater com os eventos
	for side in [Board.Side.AI, Board.Side.PLAYER]:
		var lane: Array = game.farm_mobs(side)
		if lane.size() != Rules.FARM_MOBS_PER_LANE:
			_farm_error(errors, run, "trilha %d com %d mobs" % [side, lane.size()])
			continue
		for mob in lane:
			if mob.lane != side:
				_farm_error(errors, run, "mob %d mora na trilha %d, listado na %d" % [
					mob.index, mob.lane, side])
			if mob.is_alive():
				_farm_error(errors, run, "mob %d da trilha %d sobreviveu à fase" % [mob.index, side])

	stats["fases"] += 1
	stats["empates"] += 1 if tie else 0
	# Dos empates, quantos são 0 x 0? É a pergunta que separa "fase fraca" de
	# "tabuleiro vazio": se a maioria é 0 x 0, mexer em tiros não resolve —
	# o problema é não haver quem atire.
	if tie and end_p == 0:
		stats["vazias"] = int(stats.get("vazias", 0)) + 1
	for side in [Board.Side.AI, Board.Side.PLAYER]:
		var n: int = shooter_cols[side].size()
		stats["atiradores"] = int(stats.get("atiradores", 0)) + n
		if n == 0:
			# trilha em que NINGUÉM atirou: a causa direta dos 0 x 0
			stats["trilhas_sem_atirador"] = int(stats.get("trilhas_sem_atirador", 0)) + 1
	stats["mobs_mortos"] += killed_by_side[Board.Side.AI] + killed_by_side[Board.Side.PLAYER]
	stats["mobs_escapados"] += escaped
	if expect_winner == Board.Side.PLAYER:
		stats["venceu_jog"] += 1
	elif expect_winner == Board.Side.AI:
		stats["venceu_ia"] += 1
	stats["bônus"] += bonuses
	# quantos bônus cada lado levou por fase: é a medida direta de "o bônus
	# depende do build", que é o que a mudança de gatilho queria
	stats["bônus_lado"][Board.Side.PLAYER] = \
		int(stats["bônus_lado"][Board.Side.PLAYER]) + _count_side(bonuses_seen, Board.Side.PLAYER)
	stats["bônus_lado"][Board.Side.AI] = \
		int(stats["bônus_lado"][Board.Side.AI]) + _count_side(bonuses_seen, Board.Side.AI)
	var total_element: Dictionary = stats["elemento"]
	for label: String in by_element:
		total_element[label] = int(total_element.get(label, 0)) + int(by_element[label])


## Quantos bônus de [side] apareceram, contando as chaves "lado:elemento".
func _count_side(bonuses_seen: Dictionary, side: int) -> int:
	var n := 0
	for key: String in bonuses_seen:
		if key.begins_with("%d:" % side):
			n += 1
	return n


func _farm_error(errors: Array[String], run: int, msg: String) -> void:
	errors.append("run %d: fase de farm: %s" % [run, msg])


func _dump(game) -> String:
	var out := "      tabuleiro:\n"
	for row in Board.ROWS:
		var line := "        linha %d |" % row
		for col in Board.COLS:
			var t: int = game.board.get_terrain(col, row)
			var e = game.board.get_entity(col, row)
			var cell: String = "-" if t < 0 else str(CardData.ELEMENT_LABEL[t]).substr(0, 2)
			if e != null:
				cell = e.card().title.substr(0, 6)
				if e.is_creature_token:
					cell += "%d/%d" % [e.attack, e.defense]
			line += "%-14s|" % cell
		out += line + "\n"
	var hands := ""
	for p in game.players:
		hands += "\n      %s: mao=%s deck=%d descarte=%d" % [
			p.display_name, str(p.hand), p.deck.size(), p.discard.size()]
	return out + hands


func _validate(game) -> String:
	var board: Board = game.board

	# uma entidade por tile, no máximo
	for row in Board.ROWS:
		for col in Board.COLS:
			var e := board.get_entity(col, row)
			if e == null:
				continue
			if e.col != col or e.row != row:
				return "entidade em (%d,%d) diz estar em (%d,%d)" % [col, row, e.col, e.row]
			if e.owner_side != Board.side_of_row(row):
				return "entidade em (%d,%d) tem dono errado" % [col, row]
			var card := e.card()
			if card.is_creature() and not Board.is_front_row(row):
				return "criatura em linha secundária (%d,%d)" % [col, row]
			if card.kind == CardData.Kind.BUILDING and Board.is_front_row(row):
				return "construção na linha principal (%d,%d)" % [col, row]
			# criatura na linha principal precisa de terreno do mesmo elemento
			if card.is_creature() and board.get_terrain(col, row) != card.element:
				return "criatura %s sem terreno %s em (%d,%d)" % [
					card.id, CardData.ELEMENT_LABEL[card.element], col, row]
			# buff nunca pode reduzir stats, e as stats nunca ficam abaixo da carta
			if e.attack < e.base_attack or e.defense < e.base_defense:
				return "entidade em (%d,%d) com stats abaixo do buff acumulado" % [col, row]
			if e.base_attack < card.attack or e.base_defense < card.defense:
				return "entidade %s mais fraca que a carta de origem" % card.id

	# nada morto sobrando no tabuleiro
	for row in Board.ROWS:
		for col in Board.COLS:
			var e2 := board.get_entity(col, row)
			if e2 != null and e2.is_dead():
				return "entidade morta ainda na tile (%d,%d)" % [col, row]

	# cartas não podem existir em dois lugares ao mesmo tempo
	for p in game.players:
		if p.pending_mana_bonus < 0:
			return "%s com bônus de mana negativo" % p.display_name
		var total: int = p.hand.size() + p.deck.size() + p.discard.size()
		if total > CardDB.starting_deck().size():
			return "%s tem %d cartas (deck tem %d)" % [
				p.display_name, total, CardDB.starting_deck().size()]
		for hid in p.hand:
			var in_hand := 0
			for h2 in p.hand:
				if h2 == hid:
					in_hand += 1
			var in_deck := 0
			for h2 in p.deck:
				if h2 == hid:
					in_deck += 1
			if in_hand + in_deck > 2:
				return "carta %s duplicada (%d mão + %d deck)" % [hid, in_hand, in_deck]
	return ""
