class_name DwText
extends RefCounted
## DW1's text font and row layout (the field text box, main.c:50244 FUN_80100948, glyphs drawn by
## FUN_8010cc28; data/ui/dw_font.json from tools/dw1_objects.py export_font). A row is drawn into
## 4 bpp VRAM, so each glyph lands at 4 * floor(X / 4), X the running sum of advances. A space only
## clears a cell and advances by the previous glyph's width (a vanilla quirk; 0 at a row's start
## here, where DW1 uses whatever the register held). Glyphs not in the table draw the sentinel.

const SENTINEL := 78
## The scripts' text (data/scripts) is ASCII; DW1 stores full-width Shift-JIS. Punctuation as
## the script decoder (scn.py ASCII_AS) and drawString (main.c:57654) have it: '.' -> 。, '\'' -> 「
## (0x8175, a single tick 5 px wide). The button symbols are keyed by code: glyph 77 (△'s code)
## draws an ×, glyph 78 (×'s code, the sentinel) a △, so {COLOR 06}△ is the blue Cross button.
const PUNCT := {" ": 0x8140, ".": 0x8142, ",": 0x8143, ":": 0x8146, ";": 0x8147, "?": 0x8148,
	"!": 0x8149, "\\": 0x815F, "'": 0x8175, "+": 0x817B, "-": 0x817C, "=": 0x8181,
	"○": 0x819B, "□": 0x81A0, "△": 0x81A2, "×": 0x817E}
## Names and substituted strings are ASCII converted by FUN_800f18c8's table (0x8012f3a8), which
## turns '\'' into ’ (0x8166): not in the font, so the sentinel glyph.
const ASCII_APOSTROPHE := 0x8166
const SPACE := 0x8140

static var _data: Dictionary = {}
static var _index: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		if Dw1Assets.on():                       # D-Screen: the EXE's own table (Dw1Assets.font)
			_data = Dw1Assets.font()
		else:
			var t := FileAccess.get_file_as_string("res://game_data/ui/dw_font.json")
			if not t.is_empty():
				_data = JSON.parse_string(t)
		if not _data.is_empty():
			var codes: Array = _data["codes"]
			for i in codes.size():
				_index[int(codes[i])] = i
	return _data


static func sjis(ch: String, ascii := false) -> int:
	if ascii and ch == "'":
		return ASCII_APOSTROPHE
	var o := ch.unicode_at(0)
	if o >= 0x41 and o <= 0x5A:
		return 0x8260 + o - 0x41
	if o >= 0x61 and o <= 0x7A:
		return 0x8281 + o - 0x61
	if o >= 0x30 and o <= 0x39:
		return 0x824F + o - 0x30
	return int(PUNCT.get(ch, 0))


## One row: [[glyph index, draw x, colour index], ...] and the row's end X. ascii: a name or a
## substituted string (see ASCII_APOSTROPHE).
static func layout(text: String, colour := 1, ascii := false) -> Dictionary:
	var d := data()
	var widths: Array = d.get("widths", [])
	var glyphs := []
	var x := 0
	var last := 0
	var i := 0
	while i < text.length():
		if text.substr(i, 7) == "{COLOR ":               # {COLOR nn}: hex colour index
			var close := text.find("}", i)
			colour = text.substr(i + 7, close - i - 7).hex_to_int()
			i = close + 1
			continue
		var code := sjis(text[i], ascii)
		i += 1
		if code == SPACE:
			x += last
			continue
		var g: int = _index.get(code, SENTINEL)
		glyphs.append([g, x & ~3, colour])
		last = int(widths[g]) if g < widths.size() else 12
		x += last
	return {"glyphs": glyphs, "width": x, "colour": colour}


## The font CLUT colour (5-bit to 8-bit as the other DW1 sheets).
static func colour(index: int) -> Color:
	var clut: Array = data().get("clut", [])
	if index < 0 or index >= clut.size():
		return Color.WHITE
	var c: Array = clut[index]
	return Color8(int(c[0]), int(c[1]), int(c[2]))


## The speaker's name colour (FUN_80101688): the player 6, the partner 10, an NPC 7, ids 200+ 5.
static func speaker_colour(speaker: int) -> int:
	if speaker == 0xFD:
		return 6
	if speaker == 0xFC:
		return 10
	return 7 if speaker < 200 else 5
