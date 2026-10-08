class_name BoardEntity
extends RefCounted

## Uma carta colocada no tabuleiro. Instância própria por tile, para que buffs
## e dano accumulation não vazem entre cartas iguais.

var uid: int = 0
var card_id: StringName = &""

var base_attack: int = 0
var attack: int = 0
var base_defense: int = 0
var defense: int = 0

var owner_side: int = 0
var col: int = 0
var row: int = 0
var summoned_round: int = 0

## Só criaturas sofrem dano de combate e atrito. Construções e magias
## permanentes não têm DEF e nunca "morrem".
var is_creature_token: bool = true

var damage_taken: int = 0


static func from_card(card: CardData, side: int, col: int, row: int, round: int, uid: int) -> BoardEntity:
	var e := BoardEntity.new()
	e.uid = uid
	e.card_id = card.id
	e.base_attack = card.attack
	e.attack = card.attack
	e.base_defense = card.defense
	e.defense = card.defense
	e.owner_side = side
	e.col = col
	e.row = row
	e.summoned_round = round
	e.is_creature_token = card.is_creature()
	return e


func card() -> CardData:
	return CardDB.get_card(card_id)


func display_name() -> String:
	return card().title


## Magia de "summer sickness": não pode atacar nem bloquear neste round.
func is_ready(round: int) -> bool:
	return summoned_round < round


## No modelo Magic, o limiar é a DEF e o dano é acumulativo. Permanentes
## (construções/magias) não têm DEF, então nunca são destruídos por dano.
func is_dead() -> bool:
	if not is_creature_token:
		return false
	return damage_taken >= defense


func take_damage(amount: int) -> void:
	damage_taken += amount


func buff_attack(amount: int) -> void:
	base_attack += amount
	attack += amount


## +1 DEF é o bônus de ÁGUA da fase de farm. Sobe o limiar de [is_dead], que é
## `damage_taken >= defense` — então uma criatura já machucada ganha um ponto
## de folga. Não "ressuscita" nada: quem já estava no limiar foi removido do
## tabuleiro antes.
func buff_defense(amount: int) -> void:
	base_defense += amount
	defense += amount
