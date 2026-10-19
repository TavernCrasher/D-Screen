class_name PetBubble
extends Node2D
## DW1's condition bubbles, the sulking butterfly and the mood faces over the desktop pet
## (rules/condition_bubble.gd, docs/condition_bubbles.md), for his Mixed-talk and Digi-talk.
## Drawn in his window's pixels at DW1's 20 fps. Each sprite is drawn in two passes, as the PS1
## draws one primitive: its opaque texels (no STP), then its STP texels blended by its own rate
## (the bubble and pop 50/50, the icons, butterfly and faces additive), so a later sprite covers
## an earlier one (the icon over the bubble).

const FPS := 20.0
const BUBBLE_EVERY := 60                 # renders between a need's bubbles (FUN_800a7960: timer >= 60)
const FIT_UNITS := 249.0                 # the bubble's reach above his head at hold, DW1 units
const SHADERS := {ConditionBubble.Blend.HALF: preload("res://pet/shaders/psx_half.gdshader"),
	ConditionBubble.Blend.ADD: preload("res://pet/shaders/psx_add.gdshader")}
const OPAQUE := preload("res://pet/shaders/psx_opaque.gdshader")

## One pass of one sprite.
class Item extends Node2D:
	var tex: Texture2D
	var src := Rect2()
	var dst := Rect2()

	func _draw() -> void:
		if tex:
			draw_texture_rect_region(tex, dst, src)


var feel: Texture2D
var faces: Texture2D
var anchor := Vector2.ZERO               # the top of his head, window px
var ppu := 0.5                           # window px per DW1 unit (his size)
var face_px := 2.0                       # window px per DW1 screen px (the text layer's scale)
var box_bottom := -1.0                   # the open text box's bottom, window px (-1: none; Mixed talk's bubble fits under it)
var bubble_type := -1
var bubble_left := 0                     # bubbles still to show (a need repeats)
var mood := -1
var face_left := 0.0                     # s the face still holds
var butterfly_left := 0.0
var _k := 0                              # the bubble's render counter (0: between bubbles)
var _gap := 0
var _face_n := 0
var _fly_f := 0
var _accum := 0.0
var _items: Array = []                   # [opaque, stp] pairs, in draw order
var _mats := {}
var _drawn := false


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	feel = DwWindow.load_sheet("feel_ef")
	faces = DwWindow.load_sheet("mood_faces")
	_mats[-1] = _mat(OPAQUE)
	for b in SHADERS:
		_mats[b] = _mat(SHADERS[b])


static func _mat(s: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = s
	return m


## A condition bubble of type (ConditionBubble types 0-7), `times` in a row as DW1 repeats a need.
func show_bubble(type: int, times := 1) -> void:
	clear()
	bubble_type = type
	bubble_left = times
	_k = 0
	_gap = 0


## A mood face (0 laughing, 1 smile, 2 worried, 3 frown, 4 angry) for `seconds`.
func show_face(mood_: int, seconds: float) -> void:
	clear()
	mood = mood_
	face_left = seconds
	_face_n = 0


func show_butterfly(seconds: float) -> void:
	clear()
	butterfly_left = seconds
	_fly_f = 0


func clear() -> void:
	bubble_left = 0
	_k = 0
	face_left = 0.0
	butterfly_left = 0.0
	_redraw([])


func busy() -> bool:
	return bubble_left > 0 or _k > 0 or face_left > 0.0 or butterfly_left > 0.0


func _process(delta: float) -> void:
	if not busy():
		if _drawn:
			_redraw([])
			_drawn = false
		return
	face_left -= delta
	butterfly_left -= delta
	_accum += delta * FPS
	while _accum >= 1.0:
		_accum -= 1.0
		_step()
	var list := _sprites()
	_redraw(list)
	_drawn = not list.is_empty()


## One DW1 frame: the bubble's counter (1..51, then the gap to the next of a repeated need), the
## face's and the butterfly's.
func _step() -> void:
	_face_n += 1
	_fly_f += 1
	if _k > 0:
		_k += 1
		if _k > ConditionBubble.LAST_RENDER:
			_k = 0
			bubble_left -= 1
			_gap = BUBBLE_EVERY - ConditionBubble.LAST_RENDER
	elif bubble_left > 0:
		_gap -= 1                                # a lone need's next bubble 60 frames after the last
		if _gap <= 0:                            # (timer >= 60 on the 60th call, main.c:9773-9786; PET-31)
			_k = 1


## The frame's sprites back to front: [{tex, src, dst, blend}].
func _sprites() -> Array:
	var out := []
	if _k > 0 and feel:
		var u := ppu
		if box_bottom >= 0.0:                                     # under the box: the bubble's 249 units
			u = clampf((anchor.y - box_bottom - 4.0) / FIT_UNITS, ppu * 0.35, ppu)   # (tip 45 + 192 + bob 12)
		var lift := ConditionBubble.lift(_k)
		var tip := anchor + Vector2(0, (20 + lift) * u)            # base = 20 - height (y down) + lift
		var list := ConditionBubble.sprites(_k, bubble_type)
		# the top clamp moves the shared anchor: margin texels (32, the pop 8) below the top (PET-28)
		var px0 := u * float(list[0]["scale"]) / 4096.0
		tip.y = maxf(tip.y, ConditionBubble.top_margin(_k) * px0)
		for s in list:
			var px := u * float(s["scale"]) / 4096.0                  # window px per texel
			var r: Rect2i = s["rect"]
			out.append({"tex": feel, "src": _src(r, int(s["row"])),
				"dst": Rect2(tip - Vector2(s["pivot"]) * px, Vector2(r.size) * px), "blend": s["blend"]})
	if face_left > 0.0 and mood >= 0 and faces:
		var f := ConditionBubble.face(_face_n, mood)
		var px := face_px * float(f["scale"]) / 4096.0
		var c := anchor - Vector2(0, (int(f["lift_px"]) + 16) * face_px)
		var r: Rect2i = f["rect"]
		out.append({"tex": faces, "src": _src(r, 0), "dst": Rect2(c - Vector2(f["pivot"]) * px, Vector2(r.size) * px),
			"blend": ConditionBubble.Blend.ADD})
	if butterfly_left > 0.0 and feel:
		var b := ConditionBubble.butterfly(_fly_f)
		var px := ppu * float(b["scale"]) / 4096.0
		var o: Vector3i = b["offset"]
		var c := anchor + Vector2(o.x, o.y + 60) * ppu               # around his head
		var r: Rect2i = b["rect"]
		out.append({"tex": feel, "src": _src(r, int(b["row"])),
			"dst": Rect2(c - Vector2(b["pivot"]) * px, Vector2(r.size) * px), "blend": b["blend"]})
	return out


## A sprite's texels in the sheet (a CLUT row is 64 texels down): a scaled GsSPRITE is a POLY_FT4
## whose UVs end at w - 1, so w - 1 texels stretch over w (BUB-1, PET-32).
static func _src(r: Rect2i, row: int) -> Rect2:
	return Rect2(r.position + Vector2i(0, 64 * row), r.size - Vector2i.ONE)


func _redraw(list: Array) -> void:
	while _items.size() < list.size():
		var pair := []
		for i in 2:
			var it := Item.new()
			add_child(it)
			pair.append(it)
		_items.append(pair)
	for i in _items.size():
		var pair: Array = _items[i]
		var on := i < list.size()
		for j in 2:
			var it: Item = pair[j]
			it.visible = on
			if on:
				var s: Dictionary = list[i]
				it.tex = s["tex"]
				it.src = s["src"]
				it.dst = s["dst"]
				it.material = _mats[-1] if j == 0 else _mats[s["blend"]]
				it.queue_redraw()
