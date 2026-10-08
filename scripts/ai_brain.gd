class_name AiBrain
extends RefCounted

## IA do MVP. Heurística simples e legível: prepara terreno na linha
## principal, invoca criaturas que caibam na mana restante, completa o fundo
## com construções e usa magias quando fazem sentido.
##
## `run` aplica as jogadas de verdade em [game], uma por vez, reavaliando a
## situação a cada passo — não simula, então o estado fica sempre coerente.

const MAX_ACTIONS := 40


static func run(game: Game, side: int) -> void:
	for _i in MAX_ACTIONS:
		var action := _best_action(game, side)
		if action.is_empty():
			break
		game.apply_scripted_action(action, side)

	# FASE DE FARM. O tiro não é uma jogada que a IA escolhe — é consequência
	# de ter criatura na linha principal — então não entra em `_best_action` e
	# não pode virar action: se voltasse, o laço de cima a repetiria até dar
	# MAX_ACTIONS. Por isso está DEPOIS do laço e não dentro dele.
	#
	# No fluxo real isto é um no-op: a fase só abre no fim do turno, dentro de
	# `Game.run_farm`, depois que a IA já jogou. Está aqui para a IA ter a
	# rotina e não ter regra: `commit_farm` é idempotente por fase, então se
	# algum dia a fase abrir antes da jogada do rival, o tiro da IA sai
	# daqui e o `run_farm` não duplica nada.
	game.commit_farm(side)


## Procura a melhor jogada disponível. Devolve {} se não há nada legal.
static func _best_action(game: Game, side: int) -> Dictionary:
	var board := game.board
	var p: PlayerState = game.players[side]
	var enemy := game.other_side(side)

	# 1. Magias que valem a pena agora (barato e surtem efeito agora).
	var best_spell := _best_spell(game, side)
	if not best_spell.is_empty():
		return best_spell

	# 2. Criaturas: só nas tiles da linha principal com terreno da casa.
	var creature_move := _best_creature(game, side)
	if not creature_move.is_empty():
		return creature_move

	# 3. Terreno na linha principal, priorizando elemento que dá pra invocar.
	var terrain_move := _best_terrain(game, side)
	if not terrain_move.is_empty():
		return terrain_move

	# 4. Construções na linha secundária.
	var building_move := _best_building(game, side)
	if not building_move.is_empty():
		return building_move

	# 5. Sobrou mana e sobrou carta? Usa magia restante.
	if not p.hand.is_empty() and p.mana > 0:
		var fallback := _fallback_spell(game, side)
		if not fallback.is_empty():
			return fallback

	# 6. Nada jogável? Descarta o que é comprovadamente inútil, senão a mão
	#    trava cheia de cartas mortas e a partida nunca mais anda.
	return _best_discard(game, side)


## Carta que não tem nenhuma tile legal agora **nem depois do resto do turno**
## (nada muda as tiles durante o turno, então basta checar agora).
static func _best_discard(game: Game, side: int) -> Dictionary:
	var board := game.board
	var p: PlayerState = game.players[side]

	for i in p.hand.size():
		var card := CardDB.get_card(p.hand[i])
		if card.is_spell():
			continue  # magias sempre podem ser usadas em algum momento
		if Rules.find_legal_tile(board, side, card).x >= 0:
			continue
		# terreno que pinta tile já pintada / criatura sem terreno possível
		return {"type": "discard", "hand": i}
	return {}


static func _affordable(p: PlayerState, card: CardData) -> bool:
	return p.has_mana(card.cost)


static func _best_creature(game: Game, side: int) -> Dictionary:
	var board := game.board
	var p: PlayerState = game.players[side]
	var front := Board.front_row(side)

	var best := {}
	var best_score := -1
	for i in p.hand.size():
		var card := CardDB.get_card(p.hand[i])
		if not card.is_creature() or not _affordable(p, card):
			continue
		for col in Board.COLS:
			if board.get_terrain(col, front) != card.element:
				continue
			if board.is_occupied(col, front):
				continue
			var score := card.attack * 2 + card.defense
			if score > best_score:
				best_score = score
				best = {"type": "place", "hand": i, "col": col, "row": front}
	return best


static func _best_terrain(game: Game, side: int) -> Dictionary:
	var board := game.board
	var p: PlayerState = game.players[side]
	var front := Board.front_row(side)

	# Só vale pintar terreno de um elemento que realmente sabemos usar.
	# Sem esse filtro a IA queima a mana toda pintando tiles vazias — terreno
	# que não tem criatura correspondente é uma jogada perdida.
	var in_hand := {}
	for hid in p.hand:
		var hc := CardDB.get_card(hid)
		if hc.is_creature():
			in_hand[hc.element] = mini(int(in_hand.get(hc.element, 99)), hc.cost)

	var in_deck := {}
	for hid in p.deck:
		var dc := CardDB.get_card(hid)
		if dc.is_creature():
			in_deck[dc.element] = mini(int(in_deck.get(dc.element, 99)), dc.cost)

	var wanted := in_hand.duplicate()
	for k: int in in_deck:
		if not wanted.has(k):
			wanted[k] = in_deck[k]

	var best := {}
	var best_score := -1
	for i in p.hand.size():
		var terrain_card := CardDB.get_card(p.hand[i])
		if terrain_card.kind != CardData.Kind.TERRAIN or not _affordable(p, terrain_card):
			continue
		# ignora terreno que não habilita nada que a gente tenha ou vá ter
		if not wanted.has(terrain_card.element):
			continue
		for col in Board.COLS:
			if board.is_occupied(col, front):
				continue
			var current: int = board.get_terrain(col, front)
			var score := 0
			if current < 0:
				score += 30          # tile vazia: o melhor caso
			elif current == terrain_card.element:
				continue              # já é o que queríamos, não mexe
			else:
				# repintar só compensa se destrava uma criatura que a gente tem
				if not in_hand.has(terrain_card.element):
					continue
				score += 5

			if in_hand.has(terrain_card.element):
				score += 100 if p.mana - terrain_card.cost >= int(in_hand[terrain_card.element]) else 40
			else:
				score += 10

			if score > best_score:
				best_score = score
				best = {"type": "place", "hand": i, "col": col, "row": front}
	return best


static func _best_building(game: Game, side: int) -> Dictionary:
	var board := game.board
	var p: PlayerState = game.players[side]
	var back := Board.back_row(side)

	for i in p.hand.size():
		var card := CardDB.get_card(p.hand[i])
		if card.kind != CardData.Kind.BUILDING or not _affordable(p, card):
			continue
		for col in Board.COLS:
			if Rules.can_place(board, side, card, col, back) == Rules.OK:
				return {"type": "place", "hand": i, "col": col, "row": back}
	return {}


static func _best_spell(game: Game, side: int) -> Dictionary:
	var board := game.board
	var p: PlayerState = game.players[side]
	var enemy_state: PlayerState = game.players[game.other_side(side)]

	for i in p.hand.size():
		var card := CardDB.get_card(p.hand[i])
		if not card.is_spell() or not _affordable(p, card):
			continue

		match card.spell:
			CardData.Spell.HEAL_PLAYER:
				if p.hp <= p.max_hp - card.spell_value:
					return {"type": "spell", "hand": i}
			CardData.Spell.DRAW:
				if p.hand.size() < 3 and not p.deck.is_empty():
					return {"type": "spell", "hand": i}
			CardData.Spell.DAMAGE_PLAYER:
				return {"type": "spell", "hand": i}
			CardData.Spell.DAMAGE_CREATURE:
				var target := _pick_damage_target(game, side, card)
				if target.x >= 0:
					return {"type": "spell", "hand": i, "target": target}
			CardData.Spell.DESTROY_CREATURE:
				var target := _pick_strongest(game, side)
				if target.x >= 0:
					return {"type": "spell", "hand": i, "target": target}
			CardData.Spell.BUFF_CREATURE:
				var target := _pick_own_strongest(game, side)
				if target.x >= 0:
					return {"type": "spell", "hand": i, "target": target}
	return {}


## Só usa magia se sobrou mana depois das outras jogadas.
static func _fallback_spell(game: Game, side: int) -> Dictionary:
	var p: PlayerState = game.players[side]
	for i in p.hand.size():
		var card := CardDB.get_card(p.hand[i])
		if not card.is_spell() or not _affordable(p, card):
			continue
		if Rules.spell_needs_target(card):
			var target := _pick_strongest(game, side)
			if target.x >= 0:
				return {"type": "spell", "hand": i, "target": target}
		else:
			return {"type": "spell", "hand": i}
	return {}


## Alvo com DEF alta o bastante para morrer com o dano da magia, senão o mais forte.
static func _pick_damage_target(game: Game, side: int, card: CardData) -> Vector2i:
	var board := game.board
	var enemy_side := game.other_side(side)
	var fallback := Vector2i(-1, -1)
	var best_score := -1

	for row in Board.ROWS:
		for col in Board.COLS:
			var e := board.get_entity(col, row)
			if e == null or not e.card().is_creature() or e.owner_side != enemy_side:
				continue
			var lethal := e.defense - e.damage_taken <= card.spell_value
			var score := e.attack * 3 + e.defense + (100 if lethal else 0)
			if score > best_score:
				best_score = score
				fallback = Vector2i(col, row)
	return fallback


static func _pick_strongest(game: Game, side: int) -> Vector2i:
	return _strongest_of(game, game.other_side(side))


static func _pick_own_strongest(game: Game, side: int) -> Vector2i:
	return _strongest_of(game, side)


static func _strongest_of(game: Game, owner: int) -> Vector2i:
	var board := game.board
	var best := Vector2i(-1, -1)
	var best_score := -1
	for row in Board.ROWS:
		for col in Board.COLS:
			var e := board.get_entity(col, row)
			if e == null or not e.card().is_creature() or e.owner_side != owner:
				continue
			var score := e.attack * 3 + e.defense
			if score > best_score:
				best_score = score
				best = Vector2i(col, row)
	return best
