class_name Dw1Model
extends Node3D
## A DW1 character model built from the player's own disc at runtime (docs/shareable_pet_plan.md
## steps 3-5): CHDAT/MMD<n>/<name>.MMD (TMD mesh + clips) and its ALLTIM.TIM entry, played by
## DW1's own animation tick (Dw1Clip) as it goes: bones, eye and mouth pastes, texture cycles and
## sound cues. The Python reference is tools/dw1_to_gltf.py (mesh, atlas bands, space), and
## tools/dw1_model_size.py (the size).
##
## - Mesh: DW1 models are rigid, one TMD object per bone (the skeleton gives (object, parent) per
##   bone): a Node3D per bone, the object's mesh under it. Every primitive DW1's models use:
##   textured gouraud and flat, lit (0x34/0x3C, 0x24/0x2C) or raw (0x25/0x2D, TGE: Hyogamon),
##   semi-transparent (bit 1), and the untextured gouraud quad 0x38 (the Market Manager).
## - Texture: the 4bpp ALLTIM entry, one band per CLUT row the primitives use (dw1_to_gltf.atlas),
##   CLUT 0 = transparent, STP texels alpha STP_ALPHA (a semi-transparent primitive blends only
##   those, as the GPU does: ABR 0 half, 1 add, 2 subtract, 3 a quarter added), upscaled x4
##   (Lanczos). Each band is its own texture, so a paste re-uploads only the bands whose
##   primitives show the pasted texels.
## - Space: DW1 units, y down, facing -z -> metres (x 0.005), y up, facing +z: (x, -y, -z).
## - Clips: 20 ticks a second times speed_scale, the pose eased between ticks.

signal cue(bank: int, id: int)          # a clip's sound (op 0x4000): bank 4 = his own cries

const UNIT := 0.005
const UPSCALE := 4
const ALLTIM := "CHDAT/ALLTIM.TIM"
const TIM_SIZE := 0x4800                # one model's entry in ALLTIM
const STP_ALPHA := 160                  # STP texels (opaque prims draw them; semi prims blend them)
const SOLID_CUT := 0.82                 # alpha above: a texel without STP
const STP_CUT := 0.4                    # alpha above: drawn at all (Lanczos softens the edges)
const FLAT_TEXTURED := [0x24, 0x26, 0x2C, 0x2E]
const RAW_TEXTURED := [0x25, 0x27, 0x2D, 0x2F]   # TGE: the texture as is, no light
const GOURAUD_TEXTURED := [0x34, 0x36, 0x3C, 0x3E]
const GOURAUD_PLAIN := [0x30, 0x32, 0x38, 0x3A]  # untextured, one colour, lit
## Textures kept per band (a flame's three cycle states times the face's tiles): a state seen
## before swaps in without a new upload or mipmaps.
const MEMO_CAP := 12

## The disc the models come from (D-Screen; DigimonModel switches to these when it is set).
static var disc: Dw1Disc
static var exe: Dw1Exe
static var _info := {}                  # type -> info() (size, clips), measured once

var type := -1
var bones := 0
var skeleton: Array = []
var clip: Dw1Clip
var speed_scale := 1.0
var bone_nodes: Array[Node3D] = []
var tex_origin := Vector2i.ZERO         # the image's VRAM position (halfwords, rows)
var _mmd: PackedByteArray
var _tw := 0                            # image width in halfwords (texels / 4)
var _th := 0
var _pix := PackedByteArray()           # 4bpp indices, the pastes land here
var _rows: Array = []                   # CLUT rows: PackedInt32Array of 16 colours
var _cy := 0                            # the CLUT's VRAM row
var _bands: Array = []                  # CLUT row per band
var _band_rect: Array[Rect2i] = []      # texels each band's primitives sample
var _base: Array[Image] = []            # per band, 1:1
var _big: Array[Image] = []             # per band, upscaled
var _tex: Array[ImageTexture] = []
var _dirty := {}                        # band -> Rect2i to redraw (texels)
var _band_mats: Array = []              # per band, the materials that show its texture
var _memo: Array = []                   # per band, {hash of the indices: ImageTexture} (DSM-8)
var _memo_order: Array = []             # per band, the keys oldest first
var _clock := 0.0                       # PLAYTIME_FRAMES: 20 Hz real time, the texture cycles' clock
var _acc := 0.0                         # the part of a tick elapsed
var _prev: Array = []                   # pose per bone before the last tick [quat, scale, origin]
var _cur: Array = []


## Uses this disc (and its EXE) for DW1's models from now on.
static func use(d: Dw1Disc, x: Dw1Exe) -> void:
	disc = d
	exe = x
	_info.clear()


static func on() -> bool:
	return disc != null and exe != null


## The model of DW1 type `id` from the disc in use, playing its idle (clip 0); null when the
## type has no model (62, 114) or no disc is in use.
static func build(id: int) -> Dw1Model:
	if not on():
		return null
	var path := exe.model_path(id)
	var bc := exe.bone_count(id)
	var skel := exe.skeleton(id, bc)
	if path.is_empty() or bc <= 0 or skel.is_empty() or not disc.has(path):
		return null
	var mmd := disc.read(path)
	var tim := disc.read_part(ALLTIM, id * TIM_SIZE, TIM_SIZE)
	var m := Dw1Model.new()
	if not m.setup(id, mmd, tim, skel):
		m.free()
		return null
	return m


## Builds the model from its bytes. False if the MMD or TIM don't parse.
func setup(id: int, mmd: PackedByteArray, tim: PackedByteArray, skel: Array) -> bool:
	type = id
	bones = skel.size()
	skeleton = skel
	_mmd = mmd
	name = "Dw1Model_%d" % id
	set_meta("dw1_type", id)
	if mmd.size() < 16 or not _read_tim(tim):
		return false
	var objs := objects(mmd)
	if objs.is_empty():
		return false
	_make_bands(objs)
	_draw_all()
	for b in bones:
		var n := Node3D.new()
		n.name = "bone%d" % b
		bone_nodes.append(n)
	for b in bones:
		var parent: int = skel[b][1]
		if b == 0 or parent < 0 or parent >= bones or parent == b:
			add_child(bone_nodes[b])
		else:
			bone_nodes[parent].add_child(bone_nodes[b])
	for b in bones:
		var obj: int = skel[b][0]
		if obj >= 0 and obj < objs.size():
			var mesh := _mesh(objs[obj])
			if mesh:
				var mi := MeshInstance3D.new()
				mi.name = "mesh"
				mi.mesh = mesh
				bone_nodes[b].add_child(mi)
	clip = Dw1Clip.new(mmd, bones, id)
	play(0)
	return true


# ---------------------------------------------------------------- the TMD
## TMD objects -> [{verts: [Vector3i], norms: [Vector3], prims: [{mode, uvs, cba, tsb, ni, vi,
## colour}]}].
static func objects(mmd: PackedByteArray) -> Array:
	var out := []
	var base := mmd.decode_u32(0)
	if base + 12 > mmd.size():
		return out
	var nobj := mmd.decode_u32(base + 8)
	var table := base + 12
	if nobj > 64 or table + nobj * 28 > mmd.size():
		return out
	for i in nobj:
		var h := table + i * 28
		var vtop := mmd.decode_u32(h)
		var nvert := mmd.decode_u32(h + 4)
		var ntop := mmd.decode_u32(h + 8)
		var nnorm := mmd.decode_u32(h + 12)
		var ptop := mmd.decode_u32(h + 16)
		var nprim := mmd.decode_u32(h + 20)
		var verts: Array[Vector3i] = []
		for j in nvert:
			var o := table + vtop + j * 8
			verts.append(Vector3i(mmd.decode_s16(o), mmd.decode_s16(o + 2), mmd.decode_s16(o + 4)))
		var norms: Array[Vector3] = []
		for j in nnorm:
			var o := table + ntop + j * 8
			norms.append(Vector3(mmd.decode_s16(o), mmd.decode_s16(o + 2), mmd.decode_s16(o + 4)) / 4096.0)
		var prims := []
		var o := table + ptop
		for _p in nprim:
			if o + 4 > mmd.size():
				break
			var ilen := mmd[o + 1]
			var mode := mmd[o + 3]
			var pr := _prim(mmd, o + 4, mode)
			if not pr.is_empty():
				prims.append(pr)
			o += 4 + ilen * 4
		out.append({"verts": verts, "norms": norms, "prims": prims})
	return out


## One primitive's fields (TMD layouts by mode), {} for one DW1's models don't use.
static func _prim(mmd: PackedByteArray, p: int, mode: int) -> Dictionary:
	var n := 4 if mode & 0x08 else 3
	var pr := {"mode": mode, "colour": Color.WHITE}
	if mode in GOURAUD_TEXTURED or mode in FLAT_TEXTURED or mode in RAW_TEXTURED:
		var uvs: Array[Vector2i] = []
		for k in n:
			uvs.append(Vector2i(mmd[p + k * 4], mmd[p + k * 4 + 1]))
		pr["uvs"] = uvs
		pr["cba"] = mmd.decode_u16(p + 2)
		pr["tsb"] = mmd.decode_u16(p + 6)
		var q := p + (12 if n == 3 else 16)
		if mode in GOURAUD_TEXTURED:                         # N0 V0, N1 V1...
			pr["ni"] = range(n).map(func(k: int) -> int: return mmd.decode_u16(q + k * 4))
			pr["vi"] = range(n).map(func(k: int) -> int: return mmd.decode_u16(q + k * 4 + 2))
		elif mode in FLAT_TEXTURED:                          # N0 V0, V1 V2[, V3 pad]
			var n0 := mmd.decode_u16(q)
			pr["ni"] = range(n).map(func(_k: int) -> int: return n0)
			pr["vi"] = range(n).map(func(k: int) -> int: return mmd.decode_u16(q + 2 + k * 2))
		else:                                                # R G B -, V0 V1, V2[ V3]; TGE: the
			pr["ni"] = []                                    # texture as is, its colour unused
			pr["vi"] = range(n).map(func(k: int) -> int: return mmd.decode_u16(q + 4 + k * 2))
		return pr
	if mode in GOURAUD_PLAIN:                                # R G B mode, N0 V0...
		pr["colour"] = Color8(mmd[p], mmd[p + 1], mmd[p + 2])
		pr["ni"] = range(n).map(func(k: int) -> int: return mmd.decode_u16(p + 4 + k * 4))
		pr["vi"] = range(n).map(func(k: int) -> int: return mmd.decode_u16(p + 4 + k * 4 + 2))
		return pr
	return {}


static func _conv(v: Vector3i) -> Vector3:
	return Vector3(v.x, -v.y, -v.z) * UNIT


## An object's mesh: a surface per (band, kind): "solid" (lit), "raw" (TGE), "plain" (no
## texture), and for a semi-transparent primitive its texels without STP as solid plus its STP
## texels blended ("abr0".."abr3").
func _mesh(obj: Dictionary) -> ArrayMesh:
	var verts: Array[Vector3i] = obj["verts"]
	var norms: Array[Vector3] = obj["norms"]
	var sets := {}                                           # [band, kind] -> SurfaceTool
	for pr: Dictionary in obj["prims"]:
		var mode: int = pr["mode"]
		var band := -1
		var kinds := ["plain"]
		if pr.has("uvs"):
			band = _band_of(int(pr["cba"]))
			if mode in RAW_TEXTURED:
				kinds = ["raw"]
			elif mode & 0x02:
				kinds = ["solid_cut", "abr%d" % ((int(pr["tsb"]) >> 5) & 3)]
			else:
				kinds = ["solid"]
		var uv: Array = _uvs(pr) if band >= 0 else []
		var vi: Array = pr["vi"]
		var ni: Array = pr["ni"]
		if vi.any(func(i: int) -> bool: return i >= verts.size()):
			continue
		var order := [0, 1, 2] + ([1, 3, 2] if vi.size() == 4 else [])   # Godot's fronts wind clockwise
		for kind: String in kinds:
			var key := [band, kind]
			if not sets.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				sets[key] = st
			var st: SurfaceTool = sets[key]
			for c: int in order:
				var nn: Vector3 = norms[ni[c]] if c < ni.size() and int(ni[c]) < norms.size() else Vector3(0, -1, 0)
				st.set_normal(Vector3(nn.x, -nn.y, -nn.z))
				st.set_color(pr["colour"])
				if band >= 0:
					st.set_uv(uv[c])
				st.add_vertex(_conv(verts[vi[c]]))
	if sets.is_empty():
		return null
	var mesh := ArrayMesh.new()
	var keys := sets.keys()
	keys.sort_custom(func(a: Array, b: Array) -> bool:                # solid surfaces first
		return (1 if String(a[1]).begins_with("abr") else 0) < (1 if String(b[1]).begins_with("abr") else 0))
	for key: Array in keys:
		(sets[key] as SurfaceTool).commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(key[0], key[1]))
	return mesh


var _mats := {}


func _material(band: int, kind: String) -> Material:
	var key := "%d:%s" % [band, kind]
	if _mats.has(key):
		return _mats[key]
	var m: Material
	if kind.begins_with("abr"):
		var sm := ShaderMaterial.new()
		sm.shader = _semi_shader(int(kind.substr(3)))
		sm.set_shader_parameter("tex", _tex[band])
		m = sm
	else:
		var s := StandardMaterial3D.new()
		s.roughness = 1.0
		s.metallic = 0.0
		s.vertex_color_use_as_albedo = true
		s.vertex_color_is_srgb = true                        # PSX colours are display values (DSM-6)
		if band >= 0:
			s.albedo_texture = _tex[band]
			s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			s.alpha_scissor_threshold = SOLID_CUT if kind == "solid_cut" else 0.5
		if kind == "raw":
			s.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m = s
	_mats[key] = m
	if band >= 0:
		_band_mats[band].append(m)
	return m


## Shows texture t on every material of band k.
func _show(k: int, t: ImageTexture) -> void:
	if t == _tex[k]:
		return
	_tex[k] = t
	for m: Material in _band_mats[k]:
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter("tex", t)
		else:
			(m as StandardMaterial3D).albedo_texture = t


static var _semi := {}


## STP texels of a semi-transparent primitive, blended by its ABR: 0 B/2 + F/2, 1 B + F,
## 2 B - F, 3 B + F/4.
static func _semi_shader(abr: int) -> Shader:
	if _semi.has(abr):
		return _semi[abr]
	var blend: String = ["blend_mix", "blend_add", "blend_sub", "blend_add"][abr]
	var amount: float = [0.5, 1.0, 1.0, 0.25][abr]
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode %s, depth_draw_never, cull_back;
uniform sampler2D tex : source_color, filter_linear_mipmap;
void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < %.3f || c.a > %.3f) discard;
	ALBEDO = c.rgb * COLOR.rgb;
	ALPHA = %.3f;
	ROUGHNESS = 1.0;
}
""" % [blend, STP_CUT, SOLID_CUT, amount]
	_semi[abr] = sh
	return sh


# ---------------------------------------------------------------- the texture
func _read_tim(tim: PackedByteArray) -> bool:
	if tim.size() < 20:
		return false
	var n := tim.decode_u32(8)
	_cy = tim.decode_u16(14)
	var cw := tim.decode_u16(16)
	var ch := tim.decode_u16(18)
	if 20 + cw * ch * 2 > tim.size() or 8 + n + 12 > tim.size():
		return false
	for r in ch:
		var row := PackedInt32Array()
		for c in 16:
			row.append(tim.decode_u16(20 + (r * cw + c) * 2) if c < cw else 0)
		_rows.append(row)
	var o := 8 + n
	tex_origin = Vector2i(tim.decode_u16(o + 4), tim.decode_u16(o + 6))
	_tw = tim.decode_u16(o + 8)
	_th = tim.decode_u16(o + 10)
	_pix = tim.slice(o + 12, o + 12 + _tw * _th * 2)
	if _pix.size() < _tw * _th * 2 or _rows.is_empty():
		return false
	return true


func _row_of(cba: int) -> int:
	var r := ((cba >> 6) & 0x1FF) - _cy
	return r if r >= 0 and r < _rows.size() else 0


func _band_of(cba: int) -> int:
	return _bands.find(_row_of(cba))


## The bands: the CLUT rows the primitives use, sorted, and the texels each samples.
func _make_bands(objs: Array) -> void:
	var rects := {}
	for obj: Dictionary in objs:
		for pr: Dictionary in obj["prims"]:
			if not pr.has("uvs"):
				continue
			var r := _row_of(int(pr["cba"]))
			var tsb: int = pr["tsb"]
			for uv: Vector2i in pr["uvs"]:
				var t := _texel(uv, tsb)
				var cell := Rect2i(t, Vector2i.ONE)
				rects[r] = (rects[r] as Rect2i).merge(cell) if rects.has(r) else cell
	_bands = rects.keys()
	_bands.sort()
	for r: int in _bands:
		_band_rect.append(rects[r])
		var img := Image.create(_tw * 4, _th, false, Image.FORMAT_RGBA8)
		_base.append(img)
		_big.append(null)
		_tex.append(null)
		_band_mats.append([])
		_memo.append({})
		_memo_order.append([])


## A primitive's uv -> texel in the image (its page from TSB, the image's VRAM origin).
func _texel(uv: Vector2i, tsb: int) -> Vector2i:
	var page_x := (tsb & 0xF) * 64
	var page_y := ((tsb >> 4) & 1) * 256
	return Vector2i(uv.x - (tex_origin.x - page_x) * 4, uv.y + page_y - tex_origin.y)


func _uvs(pr: Dictionary) -> Array:
	var out := []
	for uv: Vector2i in pr["uvs"]:
		var t := _texel(uv, int(pr["tsb"]))
		out.append(Vector2((t.x + 0.5) / (_tw * 4.0), (t.y + 0.5) / float(_th)))
	return out


## Texel colour of index i in CLUT row r, RGBA8 (0 transparent; STP -> STP_ALPHA).
func _rgba(row: PackedInt32Array, i: int) -> Color:
	var c := row[i]
	if c == 0:
		return Color(0, 0, 0, 0)
	return Color8((c & 31) * 255 / 31, (c >> 5 & 31) * 255 / 31, (c >> 10 & 31) * 255 / 31,
		STP_ALPHA if c & 0x8000 else 255)


func _draw_all() -> void:
	for k in _bands.size():
		var row: PackedInt32Array = _rows[_bands[k]]
		var lut := PackedByteArray()
		for i in 16:
			var c := _rgba(row, i)
			lut.append_array([c.r8, c.g8, c.b8, c.a8])
		var data := PackedByteArray()
		data.resize(_tw * 4 * _th * 4)
		var o := 0
		for b in _pix:
			var lo := (b & 15) * 4
			var hi := (b >> 4) * 4
			data[o] = lut[lo]
			data[o + 1] = lut[lo + 1]
			data[o + 2] = lut[lo + 2]
			data[o + 3] = lut[lo + 3]
			data[o + 4] = lut[hi]
			data[o + 5] = lut[hi + 1]
			data[o + 6] = lut[hi + 2]
			data[o + 7] = lut[hi + 3]
			o += 8
		_base[k] = Image.create_from_data(_tw * 4, _th, false, Image.FORMAT_RGBA8, data)
		var big := _base[k].duplicate() as Image
		big.resize(_tw * 4 * UPSCALE, _th * UPSCALE, Image.INTERPOLATE_LANCZOS)
		_big[k] = big
		var up := big.duplicate() as Image
		up.generate_mipmaps()
		_tex[k] = ImageTexture.create_from_image(up)
		_remember(k, hash(_pix), _tex[k])


func _remember(k: int, key: int, t: ImageTexture) -> void:
	_memo[k][key] = t
	_memo_order[k].append(key)
	if _memo_order[k].size() > MEMO_CAP:
		_memo[k].erase(_memo_order[k].pop_front())


## A MoveImage inside the texture (halfwords / rows from its origin), clipped to the image; the
## bands that show the destination are redrawn on the next frame.
func paste(sx: int, sy: int, w: int, h: int, dx: int, dy: int) -> void:
	var rb := _tw * 2
	# copy through a buffer (MoveImage reads the source before it writes)
	var rows := []
	for r in h:
		var y := sy + r
		rows.append(_pix.slice(y * rb + maxi(sx, 0) * 2, y * rb + mini(sx + w, _tw) * 2) if y >= 0 and y < _th and sx < _tw else PackedByteArray())
	for r in h:
		var y := dy + r
		var src: PackedByteArray = rows[r]
		if y < 0 or y >= _th or src.is_empty():
			continue
		var x0 := dx + maxi(sx, 0) - sx
		for i in src.size():
			var x := x0 * 2 + i
			if x >= 0 and x < rb:
				_pix[y * rb + x] = src[i]
	var rect := Rect2i(dx * 4, dy, w * 4, h).intersection(Rect2i(0, 0, _tw * 4, _th))
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	for k in _bands.size():
		if _band_rect[k].grow(4).intersects(rect):
			_dirty[k] = (_dirty[k] as Rect2i).merge(rect) if _dirty.has(k) else rect


func _redraw() -> void:
	var key := hash(_pix)
	for k: int in _dirty:
		var rect: Rect2i = _dirty[k]
		var row: PackedInt32Array = _rows[_bands[k]]
		var rb := _tw * 2
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var b := _pix[y * rb + x / 2]
				_base[k].set_pixelv(Vector2i(x, y), _rgba(row, b >> 4 if x & 1 else b & 15))
		# Lanczos reaches 3 texels each way: the 3 around the paste change too (DSM-4); upscale
		# a region 4 more around them, keep the paste and its ring
		var image := Rect2i(0, 0, _tw * 4, _th)
		var keep := rect.grow(3).intersection(image)
		var pad := rect.grow(7).intersection(image)
		var sub := _base[k].get_region(pad)
		sub.resize(pad.size.x * UPSCALE, pad.size.y * UPSCALE, Image.INTERPOLATE_LANCZOS)
		var inner := Rect2i((keep.position - pad.position) * UPSCALE, keep.size * UPSCALE)
		_big[k].blit_rect(sub, inner, keep.position * UPSCALE)
		var t: ImageTexture = _memo[k].get(key)
		if t == null:
			var up := _big[k].duplicate() as Image
			up.generate_mipmaps()
			t = ImageTexture.create_from_image(up)
			_remember(k, key, t)
		_show(k, t)
	_dirty.clear()


# ---------------------------------------------------------------- clips
## startAnimation: clip `id` from its first frame. False (nothing changes) if the model lacks it.
func play(id: int) -> bool:
	if not clip.start(id):
		return false
	_acc = 0.0
	_prev = _cur.duplicate() if not _cur.is_empty() else _pose()
	_tick()
	return true


func is_playing() -> bool:
	return clip.playing


func clip_id() -> int:
	return clip.clip


var _lengths := {}


## The clip's length in seconds at speed_scale: a clip that stops, until its last tick (its loops
## played; play() ran the first at once, DSM-9); an endless one, its frame count.
func clip_length() -> float:
	var id := clip.clip
	if not _lengths.has(id):
		var c := Dw1Clip.new(_mmd, bones)
		c.pose_bones = false
		c.start(id)
		while c.playing and c.ticks < SIM_TICKS:
			c.tick()
		_lengths[id] = maxi(c.ticks - 1, 0) if not c.playing else c.end_frame
	return float(_lengths[id]) / 20.0 / maxf(speed_scale, 0.01)


## One DW1 frame: the tick, its pastes and cues.
func _tick() -> void:
	clip.playtime = int(_clock)
	clip.tick()
	for p: Array in clip.pastes:
		paste(p[0], p[1], p[2], p[3], p[4], p[5])
	for s: Array in clip.sounds:
		cue.emit(int(s[0]), int(s[1]))
	_cur = _pose()


func _process(delta: float) -> void:
	_clock = fmod(_clock + delta * 20.0, 1200.0)            # GameTime: 20 a second, reset each minute
	_acc += delta * 20.0 * speed_scale
	var n := 0
	while _acc >= 1.0 and n < 8:
		_acc -= 1.0
		n += 1
		_prev = _cur
		_tick()
	if _acc >= 1.0:
		_acc = 0.0
	if not _dirty.is_empty():
		_redraw()
	_apply(clampf(_acc, 0.0, 1.0) if clip.playing else 1.0)


## The clip's pose per bone: [rotation, scale, origin] in Godot space (bone 0 at rest).
func _pose() -> Array:
	var out := []
	for b in bones:
		if b == 0:
			out.append([Quaternion.IDENTITY, Vector3.ONE, Vector3.ZERO])
			continue
		var m := Dw1Clip.rot_matrix(clip.rot[b * 3], clip.rot[b * 3 + 1], clip.rot[b * 3 + 2])
		# P M P^T, P = diag(1, -1, -1): an element keeps its sign when row and column agree
		var s := [1.0, -1.0, -1.0]
		var basis := Basis(Vector3(m[0], m[3] * s[1], m[6] * s[2]),
			Vector3(m[1] * s[1], m[4], m[7]), Vector3(m[2] * s[2], m[5], m[8]))
		out.append([basis.get_rotation_quaternion(),
			Vector3(clip.scale[b * 3], clip.scale[b * 3 + 1], clip.scale[b * 3 + 2]) / 4096.0,
			_conv(Vector3i(clip.loc[b * 3], clip.loc[b * 3 + 1], clip.loc[b * 3 + 2]))])
	return out


func _apply(t: float) -> void:
	for b in mini(bones, _cur.size()):
		var c: Array = _cur[b]
		var p: Array = _prev[b] if b < _prev.size() else c
		var q: Quaternion = (p[0] as Quaternion).slerp(c[0], t)
		var sc: Vector3 = (p[1] as Vector3).lerp(c[1], t)
		var o: Vector3 = (p[2] as Vector3).lerp(c[2], t)
		bone_nodes[b].transform = Transform3D(Basis(q) * Basis.from_scale(sc), o)


# ---------------------------------------------------------------- measures
## The mesh's extent in clip 0's opening pose, in DW1 units, as dw1_model_size.py measures it:
## {height, top, bottom, width}; {} without vertices.
func measure() -> Dictionary:
	return measure_pose(objects(_mmd), skeleton, bones, _mmd)


static func measure_pose(objs: Array, skel: Array, bone_count: int, mmd: PackedByteArray) -> Dictionary:
	var c := Dw1Clip.new(mmd, bone_count)
	if not c.has_clip(0):
		return {}
	c.start(0)
	var world := c.world(skel)
	var lo_x := 1e9
	var hi_x := -1e9
	var lo_y := 1e9
	var hi_y := -1e9
	var lo_z := 1e9
	var hi_z := -1e9
	for b in bone_count:
		var obj: int = skel[b][0]
		if obj < 0 or obj >= objs.size():
			continue
		var w: PackedFloat64Array = world[b]
		for v: Vector3i in objs[obj]["verts"]:
			var x := w[0] * v.x + w[1] * v.y + w[2] * v.z + w[9]
			var y := w[3] * v.x + w[4] * v.y + w[5] * v.z + w[10]
			var z := w[6] * v.x + w[7] * v.y + w[8] * v.z + w[11]
			lo_x = minf(lo_x, x)
			hi_x = maxf(hi_x, x)
			lo_y = minf(lo_y, y)
			hi_y = maxf(hi_y, y)
			lo_z = minf(lo_z, z)
			hi_z = maxf(hi_z, z)
	if lo_x > hi_x:
		return {}
	# PS1 y points down: the model stands on y = 0 and its top is the most negative y
	return {"height": roundi(hi_y - lo_y), "top": roundi(-lo_y), "bottom": roundi(-hi_y),
		"width": roundi(maxf(hi_x - lo_x, hi_z - lo_z))}


## What the pet asks of a type without building it (cached): {"size": measure(), "clips": {id:
## {frames, speed, dx, dz, simulated}}} as motion.json, {} without a model.
static func info(id: int) -> Dictionary:
	if _info.has(id):
		return _info[id]
	var out := {}
	if on():
		var path := exe.model_path(id)
		var bc := exe.bone_count(id)
		var skel := exe.skeleton(id, bc)
		if not path.is_empty() and bc > 0 and not skel.is_empty() and disc.has(path):
			var mmd := disc.read(path)
			out = {"size": measure_pose(objects(mmd), skel, bc, mmd), "clips": clip_info(mmd, bc)}
	_info[id] = out
	return out


const SIM_TICKS := 200                  # motion.json's 10 s


## Every clip's root motion over up to 10 s, as tools/dw1_motion.py reports it: a clip that
## stops, the steps DW1 applies tick by tick (tick 0's none; the step its last tick sets up never
## runs, DSM-1); an endless one, its momentum's steady pace over 200 steps.
static func clip_info(mmd: PackedByteArray, bone_count: int) -> Dictionary:
	var out := {}
	var c := Dw1Clip.new(mmd, bone_count)
	c.pose_bones = false
	for id: int in Dw1Clip.clip_offsets(mmd):
		c.start(id)
		c.tick()
		var roots: Array = [Vector3i.ZERO]
		while c.playing and roots.size() <= SIM_TICKS:
			c.tick()
			roots.append(c.root)
		var steps: Array = roots if not c.playing else roots.slice(1, SIM_TICKS + 1)
		var dx := 0
		var dz := 0
		for s: Vector3i in steps:
			dx += s.x
			dz += s.z
		var n := steps.size()
		out[id] = {"frames": c.end_frame, "speed": snappedf(-dz / float(n), 0.001) if n else 0.0,
			"dx": dx, "dz": dz, "simulated": n, "steps": steps}
	return out
