class_name UiKit
extends RefCounted

## Utilidades de UI compartilhadas. A fonte pixel do projeto é configurada em
## `project.godot > gui/theme/custom_font`, então `ThemeDB.fallback_font` já é
## a fonte certa e a cor vai no `modulate` do `draw_string`.

const INK := Color("0b0a12")
const PANEL := Color("16151f")
const PANEL_LIGHT := Color("221f2c")
const LINE := Color("3b3550")
const TEXT := Color("d8dcea")
const TEXT_DIM := Color("8d93a8")
const GOLD := Color("ffd76a")
const GOOD := Color("7ee08a")
const BAD := Color("d05a5a")

## A TinyFontCraftpixPixel do kit é Latin básico: não tem acento nenhum nem
## símbolos como ×. Sem esta tradução a UI em português vira "VOC" e "ROLA 6 DE
## HANA". Troque a fonte por uma com acentos e este mapa pode sumir.
const FOLD := {
	"á": "a", "à": "a", "â": "a", "ã": "a", "ä": "a",
	"é": "e", "è": "e", "ê": "e", "ë": "e",
	"í": "i", "ì": "i", "î": "i", "ï": "i",
	"ó": "o", "ò": "o", "ô": "o", "õ": "o", "ö": "o",
	"ú": "u", "ù": "u", "û": "u", "ü": "u",
	"ç": "c", "ñ": "n", "ý": "y",
	"Á": "A", "À": "A", "Â": "A", "Ã": "A", "Ä": "A",
	"É": "E", "È": "E", "Ê": "E", "Ë": "E",
	"Í": "I", "Ì": "I", "Î": "I", "Ï": "I",
	"Ó": "O", "Ò": "O", "Ô": "O", "Õ": "O", "Ö": "O",
	"Ú": "U", "Ù": "U", "Û": "U", "Ü": "U",
	"Ç": "C", "Ñ": "N",
	"×": "x", "·": "-", "▸": ">", "—": "-", "–": "-", "…": "...",
}


static func fold(s: String) -> String:
	var needs_fold := false
	for i in s.length():
		if s.unicode_at(i) > 127:
			needs_fold = true
			break
	if not needs_fold:
		return s

	var out := ""
	for i in s.length():
		var ch := s[i]
		out += FOLD.get(ch, ch)
	return out


static func font() -> Font:
	return ThemeDB.fallback_font


static func text(ci: CanvasItem, pos: Vector2, s: String, size: int,
		color: Color = TEXT, width := -1.0,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	ci.draw_string(font(), pos, fold(s), align, width, size, color)


## Texto centralizado dentro de um retângulo.
static func text_centered(ci: CanvasItem, box: Rect2, s: String, size: int,
		color: Color = TEXT) -> void:
	var folded := fold(s)
	var metrics := font().get_string_size(folded, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var pos := Vector2(
		box.position.x + (box.size.x - metrics.x) * 0.5,
		box.position.y + (box.size.y + metrics.y * 0.55) * 0.5)
	ci.draw_string(font(), pos, folded, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## Quebra [s] em no máximo [max_chars] caracteres por linha.
static func wrap(s: String, max_chars: int) -> String:
	var words := fold(s).split(" ", false)
	var lines: Array[String] = []
	var cur := ""
	for w in words:
		if cur.is_empty():
			cur = w
		elif cur.length() + 1 + w.length() <= max_chars:
			cur += " " + w
		else:
			lines.append(cur)
			cur = w
	if not cur.is_empty():
		lines.append(cur)
	return "\n".join(lines)


## Barra de progresso com rótulo. [ratio] em 0..1.
static func bar(ci: CanvasItem, box: Rect2, ratio: float, fill: Color,
		label := "") -> void:
	ci.draw_rect(box, INK)
	var inner := Rect2(box.position + Vector2(1, 1), box.size - Vector2(2, 2))
	ci.draw_rect(inner, Color(0.13, 0.13, 0.17))
	var w := inner.size.x * clampf(ratio, 0.0, 1.0)
	if w > 0:
		ci.draw_rect(Rect2(inner.position, Vector2(w, inner.size.y)), fill)
	ci.draw_rect(box, LINE, false, 1.0)
	if label != "":
		text_centered(ci, box, label, 9, INK if ratio > 0.45 else TEXT)
