class_name Board
extends RefCounted

## Tabuleiro 3 colunas × 4 linhas. Metade de cima é da IA, metade de baixo é
## do jogador. Cada lado tem uma linha principal (frente, só criaturas) e uma
## secundária (fundo, construções e magias permanentes).

const COLS := 3
const ROWS := 4

enum Side { AI, PLAYER }

const ROW_AI_BACK := 0
const ROW_AI_FRONT := 1
const ROW_PLAYER_FRONT := 2
const ROW_PLAYER_BACK := 3

## Índice [row][col].
var entities: Array = []
## Elemento do terreno pintado em [row][col], ou -1 se vazio.
var terrain: Array = []

var _next_uid: int = 1


func _init() -> void:
	entities = []
	terrain = []
	for row in ROWS:
		var e_row := []
		var t_row := []
		for col in COLS:
			e_row.append(null)
			t_row.append(-1)
		entities.append(e_row)
		terrain.append(t_row)


# --- consultas de linha ----------------------------------------------------

## Linha principal (frente) do lado — a que encosta no adversário.
static func front_row(side: int) -> int:
	return ROW_AI_FRONT if side == Side.AI else ROW_PLAYER_FRONT


## Linha secundária (fundo) do lado.
static func back_row(side: int) -> int:
	return ROW_AI_BACK if side == Side.AI else ROW_PLAYER_BACK


static func is_front_row(row: int) -> bool:
	return row == ROW_AI_FRONT or row == ROW_PLAYER_FRONT


## Lado dono da linha.
static func side_of_row(row: int) -> int:
	return Side.AI if row <= ROW_AI_FRONT else Side.PLAYER


## Linha do fundo olhando a partir da frente: o adversário de [side] está
## logo acima da linha principal dele, e vice-versa.
static func opposing_front_row(side: int) -> int:
	return ROW_PLAYER_FRONT if side == Side.AI else ROW_AI_FRONT


# --- acesso ----------------------------------------------------------------

func get_entity(col: int, row: int) -> BoardEntity:
	if col < 0 or col >= COLS or row < 0 or row >= ROWS:
		return null
	return entities[row][col]


func set_entity(col: int, row: int, entity: BoardEntity) -> void:
	entities[row][col] = entity


func get_terrain(col: int, row: int) -> int:
	if col < 0 or col >= COLS or row < 0 or row >= ROWS:
		return -1
	return terrain[row][col]


func set_terrain(col: int, row: int, element: int) -> void:
	terrain[row][col] = element


func is_occupied(col: int, row: int) -> bool:
	return get_entity(col, row) != null


func next_uid() -> int:
	_next_uid += 1
	return _next_uid


func place(card: CardData, side: int, col: int, row: int, round: int) -> BoardEntity:
	var e := BoardEntity.from_card(card, side, col, row, round, next_uid())
	entities[row][col] = e
	return e


func remove(col: int, row: int) -> void:
	entities[row][col] = null


## Todas as criaturas de um lado, em qualquer linha. Usado por magias.
func creatures_of(side: int) -> Array[BoardEntity]:
	var out: Array[BoardEntity] = []
	for row in ROWS:
		if side_of_row(row) != side:
			continue
		for col in COLS:
			var e: BoardEntity = entities[row][col]
			if e != null and e.card().is_creature():
				out.append(e)
	return out


## Criaturas na linha principal, ordenadas por coluna.
func front_line(side: int) -> Array[BoardEntity]:
	var out: Array[BoardEntity] = []
	var row := front_row(side)
	for col in COLS:
		var e: BoardEntity = entities[row][col]
		if e != null and e.card().is_creature():
			out.append(e)
	return out
