extends SceneTree

## Roda uma partida e imprime o log, para inspecionar o comportamento.
## Uso:  godot --headless --path . --script res://tests/trace.gd -- 6
##
## Argumentos: `-- <turns> <seed> <stop_at_farm>`
##
##   turns         quantos turnos jogar (padrão 8)
##   seed          seed da partida (padrão 0 = o do Game)
##   stop_at_farm  1 = para assim que a PRIMEIRA fase de farm fechar, e imprime
##                todos os eventos dela um por linha. É o jeito de conferir o
##                contrato de eventos sem caçar a fase no meio do log inteiro.

func _init() -> void:
	var turns := 8
	var seed_override := 0
	var stop_at_farm := false
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		turns = int(args[0])
	if args.size() > 1:
		seed_override = int(args[1])
	if args.size() > 2:
		stop_at_farm = int(args[2]) != 0

	var game: Node = load("res://scripts/game.gd").new()
	root.add_child(game)
	if seed_override != 0:
		game.SEED = seed_override
	game.start_game()

	var farm_seen := 0
	var stopped := false
	for i in turns:
		if game.is_over():
			break
		AiBrain.run(game, Board.Side.PLAYER)
		game.end_turn()
		# drena os eventos do turno. Nada aqui consome a fila, e sem isso ela
		# só cresce durante a partida inteira.
		var evs: Array = game.take_events()
		game.commit_roll()

		var ran := _farm_turns(evs)
		farm_seen += ran
		if stop_at_farm and ran > 0:
			_dump_farm_events(evs)
			_dump_farm(game)
			stopped = true
			break

	if stop_at_farm and not stopped:
		print("\n(nenhuma fase de farm em %d turno(s); a primeira e a rodada 3)" % turns)

	print("\n===== ESTADO FINAL (round %d) =====" % game.round)
	for row in Board.ROWS:
		var line := "linha %d: " % row
		for col in Board.COLS:
			var t: int = game.board.get_terrain(col, row)
			var e = game.board.get_entity(col, row)
			var cell := "[terreno]" if t >= 0 else "[     ]"
			if e != null:
				cell = "%s%s" % [
					e.card().title.substr(0, 6),
					" %d/%d" % [e.attack, e.defense] if e.is_creature_token else "",
				]
			line += "%-12s " % cell
		print(line)
	print("HP: você %d | IA %d" % [game.player().hp, game.opponent().hp])
	print("fases de farm vistas: %d" % farm_seen)

	quit()


## Quantas fases de farm fecharam dentro de [evs].
func _farm_turns(evs: Array) -> int:
	var n := 0
	for ev in evs:
		if String(ev.get("type", "")) == "farm_end":
			n += 1
	return n


func _is_farm_event(ev: Dictionary) -> bool:
	var kind := String(ev.get("type", ""))
	return kind.begins_with("mob_") or kind in ["farm_start", "farm_end", "bonus"]


func _side_name(side: int) -> String:
	return "JOG" if side == Board.Side.PLAYER else " IA"


## O contrato de eventos da fase, um por linha, na ordem em que saíram.
func _dump_farm_events(evs: Array) -> void:
	print("\n===== CONTRATO DE EVENTOS DA FASE DE FARM =====")
	for ev in evs:
		if not _is_farm_event(ev):
			continue
		var kind := String(ev.get("type", ""))
		var line := "  %-13s" % kind
		match kind:
			"mob_spawned":
				line += " lane=%s i=%d hp=%d" % [
					_side_name(int(ev["lane"])), int(ev["i"]), int(ev["hp"])]
			"mob_moved":
				line += " lane=%s i=%d x=%.3f" % [
					_side_name(int(ev["lane"])), int(ev["i"]), float(ev["x"])]
			"mob_hit":
				line += " lane=%s i=%d dano=%d restante=%d" % [
					_side_name(int(ev["lane"])), int(ev["i"]),
					int(ev["amount"]), int(ev["hp_left"])]
			"mob_killed", "mob_escaped":
				line += " lane=%s i=%d" % [_side_name(int(ev["lane"])), int(ev["i"])]
			"farm_end":
				var w: int = int(ev["winner"])
				line += " jogador=%d ia=%d vencedor=%s" % [
					int(ev["player_score"]), int(ev["ai_score"]),
					"empate" if w < 0 else _side_name(w)]
			"bonus":
				line += " lado=%s elemento=%s" % [
					_side_name(int(ev["side"])),
					str(CardData.ELEMENT_LABEL[int(ev["element"])])]
				for pair in [["atk", "+%d ATK"], ["def", "+%d DEF"],
						["mana", "+%d mana"], ["heal", "+%d cura"]]:
					var v := int(ev[pair[0]])
					if v > 0:
						line += " %s" % pair[1] % v
			_:
				line += " (sem payload)"
		print(line)


## Como as duas trilhas ficaram depois de fecharem.
func _dump_farm(game: Node) -> void:
	print("\n===== TRILHAS DEPOIS DA FASE =====")
	for side in [Board.Side.AI, Board.Side.PLAYER]:
		var out := "  %s (%d destruido(s)): " % [_side_name(side), game.farm_score(side)]
		for mob in game.farm_mobs(side):
			var fate := "ATRAVESSOU" if mob.escaped else ("MORREU" if mob.hp <= 0 else "SOB VIVO")
			out += "[%d hp=%d x=%.2f %s] " % [mob.index, mob.hp, mob.x, fate]
		print(out)
