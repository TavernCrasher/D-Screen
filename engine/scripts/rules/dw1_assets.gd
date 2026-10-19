class_name Dw1Assets
extends RefCounted
## D-Screen's UI, pile and prop cut-outs, read from the player's own disc at runtime
## (docs/shareable_pet_plan.md step 6): the same pixels tools/dw1_objects.py exports into
## data/ui and data/objects, so nothing of DW1's is shipped. Each cut is made once a process.
## - Sheets (DwWindow.load_sheet): dw_font (the EXE's glyphs), textbox_prompt and window_corners
##   (ETCDAT/SYSTEM_W.TIM rows 12 and 4), feel_ef (FEEL_EF.TIM, every CLUT row stacked), mood_faces
##   (GCAN11.MAP's 4bpp TIM, every row stacked).
## - The pile (PetProps.pile): ETCNA/UNTI.TMD with SYSTEM_W.TIM rows 13 (the cone) and 14 (the
##   subtractive shadow, black with alpha = its grey).
## - The boulder's red lettering (PetProps): TRAI00's overlay object 82 as dw1_maps.py cuts it
##   (palette 0, its opaque texels), then prop_boulder's red mask (tools/pet_props.py).

const SHEETS := ["dw_font", "textbox_prompt", "window_corners", "feel_ef", "mood_faces"]
const SYSTEM_W := "ETCDAT/SYSTEM_W.TIM"
const FEEL_EF := "ETCDAT/FEEL_EF.TIM"
const UNTI := "ETCNA/UNTI.TMD"
const MOOD_MAP := "MAP/MAP4/GCAN11.MAP"
const MOOD_TIM := 0x302e8
const FONT_CODES := 0x801307e0      # CHAR_TO_GLYPH_TABLE: 79 Shift-JIS codes (+ a 0 word)
const FONT_GLYPHS := 0x80130880     # 79 x 24 bytes: 11 u16 rows (bit 15 leftmost, clear = ink), width
const FONT_CLUT := 0x80130fe8
const FONT_COUNT := 79
const PILE_CBA := [0x7D46, 0x7D86]  # the cone (row 13), the shadow quad (row 14)
const MAP_ENTRIES := 0x801292D4     # 255 x 16 bytes (dw1_maps.py)
const BOULDER_MAP := 112            # TRAI00
const BOULDER_OBJ := 82             # the Boulder Moving rock's front sprite
const KANJI := Color8(220, 10, 6)

static var _memo := {}


static func on() -> bool:
	return Dw1Model.on()


# ---------------------------------------------------------------- TIMs
## tools/dw1_objects.py read_tim: a 4/8 bpp TIM coloured with CLUT row clut_row (alpha 0 for colour
## 0x0000, else 255), as RGBA8.
static func read_tim(d: PackedByteArray, clut_row := 0) -> Image:
	var flags := d.decode_u32(4)
	var o := 8
	var clut := PackedInt32Array()
	if flags & 8:
		var n := d.decode_u32(o)
		var cw := d.decode_u16(o + 8)
		var ch := d.decode_u16(o + 10)
		for i in cw * ch:
			clut.append(d.decode_u16(o + 12 + i * 2))
		o += n
	var w := d.decode_u16(o + 8)
	var h := d.decode_u16(o + 10)
	var bpp4 := (flags & 7) == 0
	var width := w * (4 if bpp4 else 2)
	var base := o + 12
	var size := 16 if bpp4 else 256
	var out := PackedByteArray()
	out.resize(width * h * 4)
	for j in h:
		for i in width:
			var idx: int
			if bpp4:
				var b := d[base + j * w * 2 + (i >> 1)]
				idx = b >> 4 if i & 1 else b & 15
			else:
				idx = d[base + j * w * 2 + i]
			var c := clut[idx + clut_row * size]
			_put(out, (j * width + i) * 4, c, 0 if c == 0 else 255)
	return Image.create_from_data(width, h, false, Image.FORMAT_RGBA8, out)


## tools/dw1_objects.py read_tim_rows: every CLUT row stacked top to bottom; alpha 0 = colour 0x0000,
## 255 = STP set (blends in a semi-transparent primitive), 128 = STP clear (opaque).
static func read_tim_rows(d: PackedByteArray) -> Image:
	var flags := d.decode_u32(4)
	var bpp4 := (flags & 7) == 0
	var ln := d.decode_u32(8)
	var cw := d.decode_u16(16)
	var ch := d.decode_u16(18)
	var w := d.decode_u16(8 + ln + 8)
	var h := d.decode_u16(8 + ln + 10)
	var base := 8 + ln + 12
	var rows := ch if bpp4 else 1
	var size := 16 if bpp4 else 256
	var width := w * (4 if bpp4 else 2)
	var out := PackedByteArray()
	out.resize(width * h * rows * 4)
	for r in rows:
		for j in h:
			for i in width:
				var idx: int
				if bpp4:
					var b := d[base + j * w * 2 + (i >> 1)]
					idx = b >> 4 if i & 1 else b & 15
				else:
					idx = d[base + j * w * 2 + i]
				var c := d.decode_u16(20 + (idx + r * size) * 2) if idx + r * size < cw * ch else 0
				_put(out, ((r * h + j) * width + i) * 4, c, 0 if c == 0 else (255 if c & 0x8000 else 128))
	return Image.create_from_data(width, h * rows, false, Image.FORMAT_RGBA8, out)


## A 15-bit colour as dw1_objects.py writes it: (c & 31) * 255 // 31 per channel.
static func _put(out: PackedByteArray, at: int, c: int, a: int) -> void:
	out[at] = (c & 31) * 255 / 31
	out[at + 1] = (c >> 5 & 31) * 255 / 31
	out[at + 2] = (c >> 10 & 31) * 255 / 31
	out[at + 3] = a


# ---------------------------------------------------------------- sheets and font
## One of SHEETS cut from the disc in use (null without one).
static func sheet(n: String) -> Image:
	if not on() or not n in SHEETS:
		return null
	var key := "sheet_" + n
	if not _memo.has(key):
		_memo[key] = sheet_from(Dw1Model.disc, Dw1Model.exe, n)
	return _memo[key]


static func sheet_from(disc: Dw1Disc, exe: Dw1Exe, n: String) -> Image:
	match n:
		"dw_font":
			return font_image(exe)
		"textbox_prompt":
			return read_tim(disc.read(SYSTEM_W), 12).get_region(Rect2i(76, 55, 48, 12))
		"window_corners":
			return read_tim(disc.read(SYSTEM_W), 4).get_region(Rect2i(120, 16, 8, 8))
		"feel_ef":
			return read_tim_rows(disc.read(FEEL_EF))
		"mood_faces":
			var m := disc.read(MOOD_MAP)
			return read_tim_rows(m.slice(MOOD_TIM))
	return null


## data/ui/dw_font.png: 79 white 12 x 12 cells in a row, ink in alpha.
static func font_image(exe: Dw1Exe) -> Image:
	var img := Image.create(FONT_COUNT * 12, 12, false, Image.FORMAT_RGBA8)
	for i in FONT_COUNT:
		var g := exe.off(FONT_GLYPHS + i * 24)
		for r in 11:
			var row := exe.d.decode_u16(g + r * 2)
			for k in 12:
				if not (row >> (15 - k)) & 1:
					img.set_pixel(i * 12 + k, r, Color.WHITE)
	return img


## data/ui/dw_font.json: {codes, widths, cell, clut: [[r, g, b]...]}.
static func font_from(exe: Dw1Exe) -> Dictionary:
	var codes := []
	var widths := []
	for i in FONT_COUNT:
		codes.append(exe.u16(FONT_CODES + i * 2))
		widths.append(exe.u8(FONT_GLYPHS + i * 24 + 22))
	var clut := []
	for i in 16:
		var c := exe.u16(FONT_CLUT + i * 2)
		clut.append([(c & 31) * 255 / 31, (c >> 5 & 31) * 255 / 31, (c >> 10 & 31) * 255 / 31])
	return {"codes": codes, "widths": widths, "cell": 12, "clut": clut}


static func font() -> Dictionary:
	if not on():
		return {}
	if not _memo.has("font"):
		_memo["font"] = font_from(Dw1Model.exe)
	return _memo["font"]


# ---------------------------------------------------------------- the pile
## data/objects/unti.json's shape: {objects: [cone, shadow]}, each {pos, uv, normal} per vertex
## (DW1 units, y down; uv normalised to the 256-wide SYSTEM_W image; normals / 4096), plus the
## two images: "cone" (row 13) and "shadow" (black, alpha = row 14's grey).
static func pile_from(disc: Dw1Disc) -> Dictionary:
	var tim := disc.read(SYSTEM_W)
	var cone := read_tim(tim, 13)
	var shade := read_tim(tim, 14)
	var mask := Image.create(shade.get_width(), shade.get_height(), false, Image.FORMAT_RGBA8)
	for y in shade.get_height():
		for x in shade.get_width():
			var c := shade.get_pixel(x, y)
			if c.a8 > 0:
				mask.set_pixel(x, y, Color8(0, 0, 0, (c.r8 + c.g8 + c.b8) / 3))
	var o := 8 + tim.decode_u32(8) if tim.decode_u32(4) & 8 else 8
	var vy := tim.decode_u16(o + 6)
	var w := float(cone.get_width())
	var h := float(cone.get_height())
	var tmd := PackedByteArray([4, 0, 0, 0])            # Dw1Model.objects reads the TMD's offset first
	tmd.append_array(disc.read(UNTI))
	var obj: Dictionary = Dw1Model.objects(tmd)[0]
	var out := {}
	for cba in PILE_CBA:
		out[cba] = {"pos": [], "uv": [], "normal": []}
	for pr: Dictionary in obj["prims"]:
		var t: Dictionary = out[int(pr["cba"])]
		var vi: Array = pr["vi"]
		var ni: Array = pr["ni"]
		var uvs: Array = pr["uvs"]
		for k in ([0, 1, 2] + ([1, 3, 2] if vi.size() == 4 else [])):
			var v: Vector3i = obj["verts"][vi[k]]
			(t["pos"] as Array).append([v.x, v.y, v.z])
			var nm: Vector3 = obj["norms"][ni[k]]
			(t["normal"] as Array).append([nm.x, nm.y, nm.z])
			var uv: Vector2i = uvs[k]
			(t["uv"] as Array).append([(uv.x + 0.5) / w, (uv.y - vy + 0.5) / h])
	return {"objects": [out[PILE_CBA[0]], out[PILE_CBA[1]]], "cone": cone, "shadow": mask}


static func pile() -> Dictionary:
	if not on():
		return {}
	if not _memo.has("pile"):
		_memo["pile"] = pile_from(Dw1Model.disc)
	return _memo["pile"]


# ---------------------------------------------------------------- the boulder's lettering
## TRAI00's overlay object 82 (128 x 128) in palette 0, its opaque texels only, as dw1_maps.py's
## export_overlays loads VRAM and cut_sprite cuts it (data/maps/TRAI00_ov.png at (362, 166)).
static func boulder_sprite(disc: Dw1Disc, exe: Dw1Exe) -> Image:
	var e := exe.off(MAP_ENTRIES + 16 * BOULDER_MAP)
	var file := exe.d.slice(e, e + 10).get_string_from_ascii()
	var n8: int = exe.d[e + 10]
	var n4: int = exe.d[e + 11]
	var dir := "MAP/MAP%d/" % (BOULDER_MAP / 15 + 1)
	var d := disc.read(dir + file + ".MAP")
	var t := disc.read(dir + file + ".TFS")
	if d.is_empty() or t.is_empty():
		return null
	var vram := []                                      # [Rect2i, halfwords], later loads on top
	for k in n8 + n4:
		var o := d.decode_u32(4 * (1 + k))
		var flags := d.decode_u32(o + 4)
		var p := o + 8
		var cluts := []                                 # loaded after the pixels, as dw1_maps.py
		if flags & 8:
			var cl := _rect(d, p)
			var cd := d.slice(p + 12, p + d.decode_u32(p))
			if k < n8 and cl.position.y != 480:
				cluts.append([cl, cd])
			elif k == n8:                               # 4bpp TIM 0: its CLUT rows to (16 i, 486)
				for row in cl.size.y:
					cluts.append([Rect2i(16 * row, 486, 16, 1), cd.slice(row * cl.size.x * 2, row * cl.size.x * 2 + 32)])
			p += d.decode_u32(p)
		vram.append([_rect(d, p), d.slice(p + 12, p + d.decode_u32(p))])
		vram.append_array(cluts)
	vram.append([Rect2i(0, 480, 256, 1), t.slice(8, 8 + 512)])   # TFS palette 0 = row 480
	var ob := d.decode_u32(4 * (1 + n8 + n4)) + 2 + 18 * BOULDER_OBJ
	var tx := d.decode_u16(ob)
	var ty := d.decode_u16(ob + 2)
	var w := d.decode_u16(ob + 4)
	var h := d.decode_u16(ob + 6)
	var clut := d.decode_u16(ob + 14) & 0xFF
	var transp := d.decode_u16(ob + 16)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for yy in h:
		for xx in w:
			var u := tx % 256 + xx
			var c: int
			if clut < 16:
				var hw := _hw(vram, (tx / 256) * 64 + 384 + u / 4, ty + yy)
				c = _hw(vram, clut * 16 + (hw >> ((u % 4) * 4) & 0xF), 486)
			else:
				var hw := _hw(vram, (tx / 256) * 128 + 384 + u / 2, ty + yy)
				c = _hw(vram, hw >> ((u % 2) * 8) & 0xFF, 480 if clut == 0xFF else 468 + clut)
			if c != 0 and (not c & 0x8000 or transp == 4):
				img.set_pixel(xx, yy, Color8((c & 31) * 255 / 31, (c >> 5 & 31) * 255 / 31, (c >> 10 & 31) * 255 / 31, 255))
	return img


static func _rect(d: PackedByteArray, p: int) -> Rect2i:
	return Rect2i(d.decode_u16(p + 4), d.decode_u16(p + 6), d.decode_u16(p + 8), d.decode_u16(p + 10))


static func _hw(vram: Array, x: int, y: int) -> int:
	for i in range(vram.size() - 1, -1, -1):
		var r: Rect2i = vram[i][0]
		if r.has_point(Vector2i(x, y)):
			var data: PackedByteArray = vram[i][1]
			var at := ((y - r.position.y) * r.size.x + x - r.position.x) * 2
			return data.decode_u16(at) if at + 1 < data.size() else 0
	return 0


## tools/pet_props.py prop_boulder's lettering from the sprite: the red brush strokes (r > 0.36,
## g and b < 0.3, r > 1.8 g; the strap's rust in the corner cut), KANJI red, alpha = the mask;
## outside it the rim colour (0.7 KANJI), alpha 0.
static func lettering_from(spr: Image) -> Image:
	var out := Image.create(spr.get_width(), spr.get_height(), false, Image.FORMAT_RGBA8)
	var rim := Color8(roundi(KANJI.r8 * 0.7), roundi(KANJI.g8 * 0.7), roundi(KANJI.b8 * 0.7), 0)
	for y in spr.get_height():
		for x in spr.get_width():
			var c := spr.get_pixel(x, y)
			var red := c.r8 / 255.0 > 0.36 and c.g8 / 255.0 < 0.3 and c.b8 / 255.0 < 0.3 and c.r8 > 1.8 * c.g8
			if y >= 96 and x >= 64:
				red = false
			out.set_pixel(x, y, KANJI if red else rim)
	return out


## The lettering in either build: the disc's sprite (D-Screen) or the remake's TRAI00 overlay atlas.
static func lettering() -> Image:
	if not _memo.has("lettering"):
		var spr: Image = null
		if on():
			spr = boulder_sprite(Dw1Model.disc, Dw1Model.exe)
		else:
			var tex := DigimonModel._texture("res://game_data/maps/TRAI00_ov.png")
			if tex:
				var atlas := tex.get_image()
				if atlas.is_compressed():
					atlas.decompress()
				atlas.convert(Image.FORMAT_RGBA8)
				spr = atlas.get_region(Rect2i(362, 166, 128, 128))
		_memo["lettering"] = lettering_from(spr) if spr else null
	return _memo["lettering"]


## Forgets the cuts (another disc, or tests).
static func clear() -> void:
	_memo.clear()
