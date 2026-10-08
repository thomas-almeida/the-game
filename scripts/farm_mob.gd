class_name FarmMob
extends RefCounted

## Um mobo genérico da fase de farm: o alvo que a criatura atira na trilha.
##
## Fica em arquivo próprio em vez de virar mais um `BoardEntity` de propósito.
## `BoardEntity` é uma carta occupant uma tile do tabuleiro 3x4 — carrega `col`,
## `row`, `owner_side`, DEF, `card()` e summoning sickness — e nada disso
## existe na trilha, que vive FORA do tabuleiro. Embutir o mobo ali faria quem
## anima o tabuleiro (`entity_3d.gd`) ter que perguntar "isto é carta ou é
## mobo?" a cada campo, e o `x` do farm não existe em `BoardEntity` mesmo.

## Vida atual. Fica <= 0 quando o mobo morre — o valor cru, com o dano
## excedente, porque é o que o log mostra. O evento `mob_hit` manda a versão
## travada em 0 (ver `Game.commit_farm`).
var hp: int = 1
var max_hp: int = 1

## `Board.Side` dono da trilha. É o `lane` de todos os eventos da fase.
var lane: int = 0

## Posição na fila. 0 é o da FRENTE, o mais advanced: como a fila inteira
## avança junta e sempre com o mesmo `x`, quem diz quem é o alvo de "cada
## criatura atira no mobo da frente" é este número. Também é o `i` de todos os
## eventos da fase.
var index: int = 0

## Posição na trilha: 0.0 é onde a fila aparece, 1.0 é a saída. Normalizado de
## propósito, porque o `Game` não sabe onde a trilha fica na tela — dado puro,
## e a cena decide o que 0.0..1.0 vira em coordenada de mundo.
var x: float = 0.0

## Atravessou a trilha sem morrer. Sai da fase sem contar como destruído.
var escaped: bool = false


func _init(p_lane: int, p_index: int, p_hp: int) -> void:
	lane = p_lane
	index = p_index
	hp = p_hp
	max_hp = p_hp


func is_alive() -> bool:
	return hp > 0 and not escaped


func advance(step: float) -> void:
	x += step


## Texto curto pro log: "mobo 3 (4 de vida)".
func describe() -> String:
	return "mobo %d (%d de vida)" % [index, maxi(hp, 0)]