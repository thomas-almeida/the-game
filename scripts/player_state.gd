class_name PlayerState
extends RefCounted

var display_name: String = "Jogador"
var is_ai: bool = false
var side: int = 0

var max_hp: int = 10
var hp: int = 10
var mana: int = 0
var mana_max: int = 0

var deck: Array[StringName] = []
var hand: Array[StringName] = []
var discard: Array[StringName] = []

## Mana extra a somar na PRÓXIMA rolagem, e só nela. É o bônus de GELO da
## fase de farm: ele não dá mana agora (a rolagem já passou) e não é
## permanente, então precisa de um lugar para esperar. `Game.commit_roll`
## soma e zera. Por Side e não global: o bônus é do vencedor da fase dele.
var pending_mana_bonus: int = 0

## Rodadas em que este lado já recebeu a mão inicial. while a compra
## obrigatória não começou, a mão vem de [Game.OPENING_HAND] uma vez só.
var opening_done: bool = false


func _init(p_name: String, p_is_ai: bool, p_side: int, p_max_hp: int) -> void:
	display_name = p_name
	is_ai = p_is_ai
	side = p_side
	max_hp = p_max_hp
	hp = p_max_hp


func is_dead() -> bool:
	return hp <= 0


func has_mana(amount: int) -> bool:
	return mana >= amount


func spend(amount: int) -> void:
	mana = maxi(0, mana - amount)


func take_damage(amount: int) -> int:
	# Devolve o dano realmente aplicado (não passa de 0).
	var applied := mini(amount, hp)
	hp -= applied
	return applied


func heal(amount: int) -> int:
	var before := hp
	hp = mini(max_hp, hp + amount)
	return hp - before


## Fisher-Yates com RNG explícito, para a partida ser reproduzível a partir
## de uma seed.
func shuffle_deck(rng: RandomNumberGenerator) -> void:
	for i in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := deck[i]
		deck[i] = deck[j]
		deck[j] = tmp
