extends Node

## Carrega TODOS os .gd do projeto e reporta os que não compilam.
##
## Existe porque `godot --editor --quit` só pega erro em script alcançável por
## `class_name`. O `hud.gd` e o `main_3d.gd` não têm, então um erro de parse
## neles passava "limpo" e só aparecia ao abrir a cena — com a tela sem HUD.
##
## É uma CENA, não `--script`, de propósito: em `--script` os autoloads não
## existem, e todo script que usa `Game` falharia com "Identifier not found:
## Game" — um falso positivo permanente no `hud.gd` e no `main_3d.gd`.
##
## Uso:  godot --headless --path . res://tests/load_check.tscn
## Imprime "OK" ou a lista de falhas; o código de saída é 1 se houver falha.

var _count := 0


func _ready() -> void:
	var bad: Array[String] = []
	for dir in ["res://scripts", "res://tests"]:
		_walk(dir, bad)
	if bad.is_empty():
		print("OK: %d scripts carregaram sem erro de parse" % _count)
	else:
		print("FALHOU: %d de %d scripts nao carregam:" % [bad.size(), _count])
		for b in bad:
			print("  ", b)
	get_tree().quit(1 if not bad.is_empty() else 0)


func _walk(dir: String, bad: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		_walk(dir.path_join(sub), bad)
	for f in d.get_files():
		if not f.ends_with(".gd"):
			continue
		var path := dir.path_join(f)
		_count += 1
		var s = load(path)
		if s == null or not (s is GDScript) or not (s as GDScript).can_instantiate():
			bad.append(path)