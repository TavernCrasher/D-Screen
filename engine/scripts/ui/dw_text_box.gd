class_name DwTextBox
extends DwWindow
## DW1's field text box (script ops `speaker` / `text`; FUN_80100fdc, render FUN_801012bc,
## docs/scripts.md "Text box"): window 0 at (-130, 42, 262, 59), box colour 0 at 50%, zooming
## from the speaker over 5 frames. With a speaker, row 0 is the name in its colour and the text
## follows on rows 1-3; rows sit at (x + 5, y + 4 + 13 i) with a black shadow at +1, +1, the whole
## page shown at once (no typewriter). While it waits for Cross, the Cross icon (FUN_80101440)
## turns at (x + 239, y + 43), a frame every 4 of the open timer. close_textbox removes the box
## in one frame (close_now; no zoom back).

const RECT := Rect2(-130, 42, 262, 59)
const ROW_X := 5
const ROW_Y := 4
const ROW_PITCH := 13
const ROW_W := 252
const ROWS := 4                      # rows on a page (a name takes the first); DW1 pages longer texts (not ported)
const PROMPT := Vector2i(239, 43)

var rows: Array = []                 # DwText.layout() per row
var prompt := true
var timer_at_open := 5               # DAT_80135012 on the first open frame (the page flipped 5 frames before)
var _font: Texture2D
var _prompt: Texture2D


func _init() -> void:
	super()
	_font = DwWindow.load_sheet("dw_font")
	_prompt = DwWindow.load_sheet("textbox_prompt")


## name: "" for speaker 0xFF (no name row). text: rows split on "\n" (the scripts' "\\n" too).
func set_page(name: String, name_colour: int, text: String) -> void:
	rows = []
	if name != "":
		rows.append(DwText.layout(name, name_colour, true))
	var colour := 1
	for line in text.replace("\\n", "\n").split("\n"):
		var r := DwText.layout(line, colour)
		colour = int(r["colour"])                         # {COLOR} persists across rows
		rows.append(r)


func open_text(origin_: Rect2) -> void:
	open_window(RECT, origin_, 0)


## The open timer (DAT_80135012) on this open frame.
func timer() -> int:
	return (frame - 1 + timer_at_open) & 0xFF            # a u8


func close_now() -> void:
	phase = 3
	visible = false


func _draw_contents() -> void:
	if _font == null:
		return
	var x := int(target.position.x)
	var y := int(target.position.y)
	for shadow in [true, false]:
		for i in mini(rows.size(), ROWS):                   # FUN_801012bc draws 4 row quads
			var r: Dictionary = rows[i]
			for g in r["glyphs"]:
				var gx: int = g[1]
				if gx + 12 > ROW_W:
					continue
				var c := Color.BLACK if shadow else DwText.colour(int(g[2]))
				var o := 1 if shadow else 0
				draw_texture_rect_region(_font, Rect2(_p(x + ROW_X + gx + o, y + ROW_Y + ROW_PITCH * i + o), Vector2(12, 12) * _s()),
					Rect2(int(g[0]) * 12, 0, 12, 12), c)
	if prompt and _prompt:
		var f := (timer() >> 2) % 3
		draw_texture_rect_region(_prompt, Rect2(_p(x + PROMPT.x, y + PROMPT.y), Vector2(16, 12) * _s()), Rect2(16 * f, 0, 16, 12))
