class_name PetMenu
extends DwWindow
## The pet's click menu in DW1's window frame and font (DwWindow, DwText): one row per action,
## the row under the mouse in yellow (font colour 7) with a small cursor. INTERIM: DW1's own
## choice cursor isn't extracted; the cursor is a drawn triangle in the frame's light blue.

const ROW_X := 14
const ROW_Y := 5
const ROW_PITCH := 13
const WIDTH := 92

var width := WIDTH                   # DW1 px; the props ring's tip sets its own
var labels: PackedStringArray = []
var hover := -1
var _rows: Array = []
var _font: Texture2D


func _init() -> void:
	super()
	_font = DwWindow.load_sheet("dw_font")


## Opens at `at` (DW1 coordinates of the window's top-left), zooming from `origin_`.
func open_menu(labels_: PackedStringArray, at: Vector2, origin_: Rect2) -> void:
	labels = labels_
	_rows = []
	for l in labels:
		_rows.append(DwText.layout(l, 1))
		var g: Array = _rows[-1]["glyphs"]
		if not g.is_empty():                             # wide enough for its longest row ("Go Explore")
			width = maxi(width, ROW_X + int(g[-1][1]) + 18)
	hover = -1
	open_window(rect_at(at), origin_, 0)


func rect_at(at: Vector2) -> Rect2:
	return Rect2(at, Vector2(width, ROW_Y * 2 + ROW_PITCH * labels.size() + 2))


## The row at a point in window pixels, -1 outside.
func row_at(p: Vector2) -> int:
	if not is_open():
		return -1
	var q := (p - size / 2.0) / _s()
	if q.x < target.position.x or q.x > target.end.x:
		return -1
	var i := floori((q.y - target.position.y - ROW_Y) / ROW_PITCH)
	return i if i >= 0 and i < labels.size() else -1


## Row i's rect in window pixels (row_at's inverse).
func row_rect(i: int) -> Rect2:
	var a := size / 2.0 + Vector2(target.position.x, target.position.y + ROW_Y + i * ROW_PITCH) * _s()
	return Rect2(a, Vector2(target.size.x, ROW_PITCH) * _s())


func _draw_contents() -> void:
	if _font == null:
		return
	var x := int(target.position.x)
	var y := int(target.position.y)
	for shadow in [true, false]:
		for i in _rows.size():
			var r: Dictionary = _rows[i]
			for g in r["glyphs"]:
				var c := Color.BLACK if shadow else DwText.colour(7 if i == hover else int(g[2]))
				var o := 1 if shadow else 0
				draw_texture_rect_region(_font, Rect2(_p(x + ROW_X + int(g[1]) + o, y + ROW_Y + ROW_PITCH * i + o), Vector2(12, 12) * _s()),
					Rect2(int(g[0]) * 12, 0, 12, 12), c)
	if hover >= 0:
		var cy := y + ROW_Y + ROW_PITCH * hover + 6
		draw_colored_polygon(PackedVector2Array([_p(x + 5, cy - 4), _p(x + 10, cy), _p(x + 5, cy + 4)]), LIGHT)
