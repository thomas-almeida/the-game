class_name CardData
extends Resource

## Definição de uma carta. Instâncias são criadas por [CardDB].

enum Kind {
	CREATURE,   ## só linha principal, tem ATK/DEF
	TERRAIN,    ## pinta a tile, qualquer linha vazia
	BUILDING,   ## só linha secundária
	SPELL,      ## instantâneo, não ocupa tile
}

enum Element {
	WATER,
	FIRE,
	EARTH,
	FROST,
	SHADOW,
}

enum Spell {
	NONE,
	DAMAGE_CREATURE,    ## causa [spell_value] a uma criatura inimiga
	DAMAGE_PLAYER,      ## causa [spell_value] direto no jogador inimigo
	HEAL_PLAYER,        ## cura [spell_value] do próprio jogador
	DRAW,               ## compra [spell_value] cartas
	DESTROY_CREATURE,   ## destrói uma criatura inimiga
	BUFF_CREATURE,      ## dá +[spell_value] ATK a uma criatura própria
}

const KIND_LABEL := {
	Kind.CREATURE: "CRIATURA",
	Kind.TERRAIN: "TERRENO",
	Kind.BUILDING: "CONSTRUÇÃO",
	Kind.SPELL: "MAGIA",
}

const ELEMENT_LABEL := {
	Element.WATER: "ÁGUA",
	Element.FIRE: "FOGO",
	Element.EARTH: "TERRA",
	Element.FROST: "GELO",
	Element.SHADOW: "SOMBRA",
}

const ELEMENT_COLOR := {
	Element.WATER: Color("4a90d9"),
	Element.FIRE: Color("e2553b"),
	Element.EARTH: Color("8a5a3b"),
	Element.FROST: Color("9fd8e8"),
	Element.SHADOW: Color("7b5ea7"),
}

@export var id: StringName = &""
@export var title: String = ""
@export var kind: Kind = Kind.CREATURE
@export var element: Element = Element.EARTH
@export var cost: int = 1

# Criaturas
@export var attack: int = 0
@export var defense: int = 0

# Magias
@export var spell: Spell = Spell.NONE
@export var spell_value: int = 0

@export var art: String = ""
@export var text: String = ""

## Qual slime do pacote `slime-mobs` representa esta criatura (1..3). São três
## modelos, então a variedade vem do tint por elemento, não de dez sprites.
@export var slime: int = 1


func is_creature() -> bool:
	return kind == Kind.CREATURE


func is_spell() -> bool:
	return kind == Kind.SPELL


## "[1/3]" como no Magic. Vazio para cartas sem stats.
func stats_text() -> String:
	if not is_creature():
		return ""
	return "%d/%d" % [attack, defense]


func kind_text() -> String:
	return KIND_LABEL[kind]


func element_text() -> String:
	return ELEMENT_LABEL[element]


func element_color() -> Color:
	return ELEMENT_COLOR[element]


## Uma linha de resumo do efeito, para a UI e o log.
func effect_text() -> String:
	match spell:
		Spell.DAMAGE_CREATURE:
			return "Causa %d de dano a uma criatura inimiga." % spell_value
		Spell.DAMAGE_PLAYER:
			return "Causa %d de dano ao jogador inimigo." % spell_value
		Spell.HEAL_PLAYER:
			return "Recupera %d de vida." % spell_value
		Spell.DRAW:
			return "Compra %d carta(s)." % spell_value
		Spell.DESTROY_CREATURE:
			return "Destrói uma criatura inimiga."
		Spell.BUFF_CREATURE:
			return "Sua criatura ganha +%d de ATK." % spell_value
		_:
			return text
