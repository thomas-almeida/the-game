extends SceneTree

## Prova que o sorteio de mana NÃO é igual em toda partida.
##
## Existe por causa de um defeito que passou despercebido: `Game.SEED` valia
## 20260101 por padrão, então toda partida tinha a mesma sequência de dados e o
## jogador tirava 2, 2, 6... sempre. Meus testes davam o mesmo número toda vez e
## eu lia como "consistente". Este teste olha a DISTRIBUIÇÃO, que é o que
## denuncia.
##
## Uso: godot --headless --path . --script res://tests/roll_check.gd

const GAMES := 60


func _init() -> void:
	var failed := false

	# 1) Partidas independentes, semente padrão: a 1ª rolagem tem que variar.
	var first := {}
	for i in GAMES:
		var g := _new_game()
		g.start_game()
		g.commit_roll()
		var m: int = g.player().mana
		first[m] = int(first.get(m, 0)) + 1
		_free(g)
	var keys := first.keys()
	keys.sort()
	var dist := ""
	for k in keys:
		dist += "%d:%d  " % [k, first[k]]
	print("1) 1a rolagem do jogador em %d partidas: %s" % [GAMES, dist])
	if first.size() < 4:
		print("   FALHOU: so %d valores distintos; o sorteio parece fixo" % first.size())
		failed = true
	else:
		print("   OK: %d valores distintos" % first.size())

	# 2) REINICIAR (start_game no mesmo objeto): a sequência não pode recomeçar
	# igual. Era o efeito de reaplicar a semente DEPOIS de embaralhar.
	var seqs := []
	var g2 := _new_game()
	for i in 12:
		g2.start_game()
		g2.commit_roll()
		seqs.append(g2.player().mana)
	var distinct := {}
	for v in seqs:
		distinct[v] = true
	print("2) 12 reinicios seguidos, 1a rolagem: %s" % str(seqs))
	if distinct.size() < 3:
		print("   FALHOU: o reinicio repete a rolagem")
		failed = true
	else:
		print("   OK: %d valores distintos" % distinct.size())
	_free(g2)

	# 3) Com semente EXPLÍCITA continua reproduzível (é o que sim/trace usam).
	var a := _rolls_with_seed(777)
	var b := _rolls_with_seed(777)
	var c := _rolls_with_seed(778)
	print("3) semente 777: %s | de novo: %s | semente 778: %s" % [a, b, c])
	if a != b:
		print("   FALHOU: a mesma semente nao reproduz")
		failed = true
	elif a == c:
		print("   FALHOU: sementes diferentes deram a mesma sequencia")
		failed = true
	else:
		print("   OK: reproduzivel com semente, e diferente entre sementes")

	print("RESULTADO: ", "FALHOU" if failed else "OK")
	quit(1 if failed else 0)


func _new_game() -> Node:
	var g: Node = load("res://scripts/game.gd").new()
	root.add_child(g)
	return g


func _free(g: Node) -> void:
	root.remove_child(g)
	g.free()


## As três primeiras rolagens do jogador numa partida com semente fixa.
func _rolls_with_seed(seed_value: int) -> Array:
	var g := _new_game()
	g.SEED = seed_value
	g.start_game()
	var out := []
	for i in 3:
		g.commit_roll()
		out.append(g.player().mana)
		AiBrain.run(g, Board.Side.PLAYER)
		g.end_turn()
	_free(g)
	return out
