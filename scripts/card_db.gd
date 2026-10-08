class_name CardDB
extends RefCounted

## Catálogo de cartas do MVP.
##
## As criaturas usam o pacote `slime-mobs`: três slimes, cada um com Idle,
## Walk, Run, Attack, Hurt e Death em folhas horizontais de 64x64. Isso dá
## animação de verdade no tabuleiro — antes a criatura era UM frame estático
## de 32x32 do outro kit.

const KIT := "res://assets/top-down-roguelike-game-kit-pixel-art"
const RUINS := "res://assets/top-down-ruins-pixel-art/PNG/Assets"
const SLIME := "res://assets/slime-mobs-pixel-art-top-down-sprite-pack/PNG"

## Tiles de terreno já achatados sobre fundo opaco. Os PNGs originais em
## `RUINS` são RGBA8 com borda transparente, e tiles de terreno são quadrados
## por definicao: a transparencia so atrapalha.
const TERRAIN := "res://assets/generated/terrain"

## Cor de fundo dos tiles de terreno, para a UI bordar igual.
const TERRAIN_BG := Color("1d1a26")

const FRAME_SIZE := Vector2i(32, 32)
## Os slimes vêm em frames de 64x64 — o dobro do kit antigo, então o sprite
## na tela precisa de metade do `pixel_size` para não ficar gigante.
const SLIME_FRAME := Vector2i(64, 64)
## Quantos frames tem cada animação. Sai da largura da própria folha / 64,
## conferido contra os PNGs do pacote.
const SLIME_FRAMES := {
	"Idle": 6, "Walk": 8, "Run": 8, "Attack": 10, "Hurt": 5, "Death": 10,
}

static var _cache: Dictionary = {}


## Textura de arte, cacheada. Tudo passa por aqui em vez de `load()` direto no
## `_draw`: `load()` a cada redesenho re-consulta o disco e, no meu ambiente,
## textura crua sem cache renderizava branco.
static func art(path: String) -> Texture2D:
	if path == "":
		return null
	if _cache.has(path):
		return _cache[path]

	var tex := load(path)
	_cache[path] = tex
	return tex


## Recorta um frame de uma folha horizontal de sprites 32x32.
static func frame(sheet_path: String, index: int) -> AtlasTexture:
	return _crop(sheet_path, index, FRAME_SIZE)


## Folha de animação do slime [variant] (1..3) na ação [action].
## `variant` é 1-based porque é assim que o pacote nomeia as pastas.
static func slime_sheet(variant: int, action: String) -> String:
	return "%s/Slime%d/With_shadow/Slime%d_%s_with_shadow.png" % [
		SLIME, variant, variant, action]


static func slime_frames(action: String) -> int:
	return int(SLIME_FRAMES.get(action, 6))


## Frame [index] de uma folha de slimes (64x64).
static func slime_frame(variant: int, action: String, index: int) -> AtlasTexture:
	var sheet := slime_sheet(variant, action)
	var key := "slime:%d:%s#%d" % [variant, action, index]
	if _cache.has(key):
		return _cache[key]

	var atlas := AtlasTexture.new()
	atlas.atlas = art(sheet)
	atlas.region = Rect2(index * SLIME_FRAME.x, 0, SLIME_FRAME.x, SLIME_FRAME.y)
	_cache[key] = atlas
	return atlas


static func _crop(sheet_path: String, index: int, size: Vector2i) -> AtlasTexture:
	var key := "frame:%s#%d" % [sheet_path, index]
	if _cache.has(key):
		return _cache[key]

	var atlas := AtlasTexture.new()
	atlas.atlas = art(sheet_path)
	atlas.region = Rect2(index * size.x, 0, size.x, size.y)
	_cache[key] = atlas
	return atlas


static func creature_art(dir: String, facing := "U") -> String:
	return "%s/%s/%s_Idle.png" % [KIT, dir, facing]


static func terrain_art(element: CardData.Element) -> String:
	match element:
		CardData.Element.WATER:
			return "%s/water.png" % TERRAIN
		CardData.Element.FIRE:
			return "%s/fire.png" % TERRAIN
		CardData.Element.EARTH:
			return "%s/earth.png" % TERRAIN
		CardData.Element.FROST:
			return "%s/frost.png" % TERRAIN
		_:
			return "%s/shadow.png" % TERRAIN


# --- construção das cartas -------------------------------------------------

static func _creature(
	id: StringName,
	title: String,
	element: CardData.Element,
	cost: int,
	atk: int,
	def: int,
	slime: int,
	text := ""
) -> CardData:
	var c := CardData.new()
	c.id = id
	c.title = title
	c.kind = CardData.Kind.CREATURE
	c.element = element
	c.cost = cost
	c.attack = atk
	c.defense = def
	c.slime = slime
	# a arte da criatura é o frame de Idle do slime; quem quiser a animação
	# completa pega [slime_frame] pelo `card.slime`
	c.art = slime_sheet(slime, "Idle")
	c.text = text
	return c


static func _terrain(
	id: StringName,
	title: String,
	element: CardData.Element,
	cost: int,
	text := ""
) -> CardData:
	var c := CardData.new()
	c.id = id
	c.title = title
	c.kind = CardData.Kind.TERRAIN
	c.element = element
	c.cost = cost
	c.art = terrain_art(element)
	c.text = text
	return c


static func _building(id: StringName, title: String, cost: int, art: String, text := "") -> CardData:
	var c := CardData.new()
	c.id = id
	c.title = title
	c.kind = CardData.Kind.BUILDING
	c.element = CardData.Element.EARTH
	c.cost = cost
	c.art = art
	c.text = text
	return c


static func _spell(
	id: StringName,
	title: String,
	element: CardData.Element,
	cost: int,
	effect: CardData.Spell,
	value: int
) -> CardData:
	var c := CardData.new()
	c.id = id
	c.title = title
	c.kind = CardData.Kind.SPELL
	c.element = element
	c.cost = cost
	c.spell = effect
	c.spell_value = value
	return c


## Todas as cartas do jogo, indexadas por id.
static func all() -> Dictionary:
	if _cache.has("__all__"):
		return _cache["__all__"]

	var list: Array[CardData] = [
		# --- criaturas: ÁGUA ---
		_creature(&"lula", "Lula Abissal", CardData.Element.WATER, 1, 1, 1, 2),
		_creature(&"hidra", "Hidra de Maré", CardData.Element.WATER, 4, 2, 3, 3),
		# --- criaturas: FOGO ---
		_creature(&"raposa", "Raposa Ígnea", CardData.Element.FIRE, 2, 1, 1, 1),
		_creature(&"dragao", "Dragão de Cinzas", CardData.Element.FIRE, 6, 4, 4, 3),
		# --- criaturas: TERRA ---
		_creature(&"golem", "Golem de Lama", CardData.Element.EARTH, 2, 1, 3, 1),
		_creature(&"colosso", "Colosso de Pedra", CardData.Element.EARTH, 5, 2, 4, 2),
		# --- criaturas: GELO ---
		_creature(&"fada", "Fada Gélida", CardData.Element.FROST, 3, 1, 2, 2),
		_creature(&"lobo", "Lobo Glacial", CardData.Element.FROST, 3, 2, 2, 1),
		# --- criaturas: SOMBRA ---
		_creature(&"espectro", "Espectro", CardData.Element.SHADOW, 2, 1, 2, 3),
		_creature(&"senhor", "Senhor das Sombras", CardData.Element.SHADOW, 6, 4, 4, 3),

		# --- terrenos ---
		_terrain(&"poca", "Poça", CardData.Element.WATER, 1),
		_terrain(&"lava", "Charco de Lava", CardData.Element.FIRE, 2),
		_terrain(&"fertil", "Terra Fértil", CardData.Element.EARTH, 1),
		_terrain(&"gelo", "Gelo Eterno", CardData.Element.FROST, 2),
		_terrain(&"veu", "Véu Sombrio", CardData.Element.SHADOW, 3),

		# --- construções (linha secundária) ---
		_building(&"muralha", "Muralha", 2, "%s/White_ruins5.png" % RUINS,
			"Constrói uma muralha. Bloqueio visual por enquanto."),
		_building(&"deposito", "Depósito", 2,
			"%s/2 Dungeon Tileset/2 Objects/Boxes/1.png" % KIT),
		_building(&"altar", "Altar de Mana", 4,
			"%s/2 Dungeon Tileset/2 Objects/Torches/1.png" % KIT),

		# --- magias ---
		_spell(&"ruptura", "Ruptura", CardData.Element.EARTH, 2,
			CardData.Spell.DAMAGE_CREATURE, 3),
		_spell(&"ciclone", "Ciclone", CardData.Element.WATER, 4,
			CardData.Spell.DESTROY_CREATURE, 0),
		_spell(&"sede", "Sede Ancestral", CardData.Element.EARTH, 3,
			CardData.Spell.HEAL_PLAYER, 3),
		_spell(&"pressagio", "Presságio", CardData.Element.SHADOW, 2,
			CardData.Spell.DRAW, 2),
		_spell(&"furia", "Fúria", CardData.Element.FIRE, 2,
			CardData.Spell.BUFF_CREATURE, 2),
		_spell(&"veneno", "Flecha Venenosa", CardData.Element.SHADOW, 3,
			CardData.Spell.DAMAGE_PLAYER, 2),
	]

	var by_id := {}
	for c in list:
		by_id[c.id] = c
	_cache["__all__"] = by_id
	return by_id


static func get_card(id: StringName) -> CardData:
	return all().get(id)


## Composição do baralho inicial (20 cartas), usada pelos dois lados.
##
## Duas regras de ouro na hora de montar isso:
## 1. **todo elemento com criatura tem terreno** no baralho, senão aquela
##    criatura nunca pode ser invocada;
## 2. **os custos precisam cobrir a faixa inteira 1..6**, senão a parte cara
##    das cartas nunca é testada.
static func starting_deck() -> Array[StringName]:
	return [
		# criaturas (10) — dois de cada elemento, um fraco e um caro
		&"lula", &"hidra",           # WATER  1 / 4
		&"raposa", &"dragao",         # FIRE   2 / 6
		&"golem", &"colosso",         # EARTH  2 / 5
		&"fada", &"lobo",             # FROST  3 / 3
		&"espectro", &"senhor",       # SHADOW 2 / 6
		# terreno (7) — cobre os cinco elementos
		&"poca", &"poca", &"lava", &"fertil", &"fertil",
		&"gelo", &"veu",
		# utilidade (3)
		&"ruptura", &"pressagio", &"furia",
	]
