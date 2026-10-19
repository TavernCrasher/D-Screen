class_name DwWindow
extends Control
## DW1's framed UI window (FUN_800c3014 open / 800c2998 draw / 800c3260 frame / 800c31fc close),
## drawn in DW1's centred 320x240 coordinates scaled to the window height. A grey outline zooms
## from the origin rect to the target over 5 frames (t/4, truncated), then the open window draws
## the box (colour table 80124bfc, 50% with flag 2), the blue frame and its contents; its update
## callback runs once a frame only while open. Closing zooms back over 5 frames. Subclasses
## override _open_frame() (the update) and _draw_contents() (the render, on top of the frame).

const LIGHT := Color8(0x90, 0xD9, 0xFA)
const MID := Color8(0x4A, 0x9F, 0xC5)
const DARK := Color8(2, 2, 2)
const GREY := Color8(0x80, 0x80, 0x80)
const BOX_COLOURS := [Color8(0, 0, 0), Color8(45, 56, 64)]   # 80124bfc

var target := Rect2(-82, -87, 164, 90)
var origin := Rect2(-8, -8, 16, 16)
var box_colour := 0
var phase := 3                       # 0 opening, 1 open, 2 closing, 3 closed
var t := 0
var frame := 0                       # frames open
var _accum := 0.0
var _corners: Texture2D


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_corners = load_sheet("window_corners")
	visible = false


## A PNG of game_data/ui, exact (DigimonModel._texture); in D-Screen the pet's sheets are cut from
## the player's disc (Dw1Assets.SHEETS).
static func load_sheet(n: String) -> Texture2D:
	var img := Dw1Assets.sheet(n)
	if img:
		return ImageTexture.create_from_image(img)
	if Dw1Assets.on():                       # D-Screen ships no game_data: a failed cut is an error (CARD-G1)
		push_error("D-Screen: couldn't cut the %s sheet from the disc" % n)
		return null
	return DigimonModel._texture("res://game_data/ui/%s.png" % n)


func open_window(target_: Rect2, origin_: Rect2, colour := 0) -> void:
	target = target_
	origin = origin_
	box_colour = colour
	phase = 0
	t = -1                                   # the first frame draws t = 0
	frame = 0
	_accum = 0.0
	visible = true


## 800c31fc: zoom back to `to` (the origin by default).
func close_window(to = null) -> void:
	if phase == 3 or phase == 2:
		return
	if to != null:
		origin = to
	phase = 2
	t = 5                                    # the first closing frame draws t = 4


func done() -> bool:
	return phase == 3


func is_open() -> bool:
	return phase == 1


## Runs the window at DW1's 20 fps; owners that tick it themselves call step() instead.
var self_tick := true


func _process(delta: float) -> void:
	if phase == 3:
		return
	if self_tick:
		_accum += delta * 20.0
		while _accum >= 1.0 and phase != 3:
			_accum -= 1.0
			step()
	_redraw()


func _redraw() -> void:
	queue_redraw()


## One DW1 frame.
func step() -> void:
	match phase:
		0:                                       # 5 frames of the outline, t = 0..4 (800c311c);
			t += 1                               # the frame after, the box and the first update
			if t > 4:
				phase = 1
				frame += 1
				_open_frame()
		1:
			frame += 1
			_open_frame()
		2:
			t -= 1
			if t < 0:
				phase = 3
				visible = false
				_closed()


func _open_frame() -> void:
	pass


func _closed() -> void:
	pass


func _draw_contents() -> void:
	pass


# ---------------------------------------------------------------- drawing
func _s() -> float:
	return size.y / 240.0


func _p(x: float, y: float) -> Vector2:
	return size / 2.0 + Vector2(x, y) * _s()


## The target rect in this control's pixels.
func pixel_rect() -> Rect2:
	return Rect2(position + _p(target.position.x, target.position.y), target.size * _s())


## A 1-pixel PS1 line (LineF2 draws both end points), horizontal or vertical.
func _line(x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var a := Vector2(mini(x0, x1), mini(y0, y1))
	var b := Vector2(maxi(x0, x1) + 1, maxi(y0, y1) + 1)
	draw_rect(Rect2(_p(a.x, a.y), (b - a) * _s()), c)


func _box(x: float, y: float, w: float, h: float, c: Color) -> void:
	draw_rect(Rect2(_p(x, y), Vector2(w, h) * _s()), c)


## 800c2920: the outline between the origin and the target rect, t/4 of the way.
static func lerp_rect(from: Rect2, to: Rect2, t_: int) -> Rect2i:
	var x0 := int(from.position.x) + int(t_ * (to.position.x - from.position.x) / 4)
	var y0 := int(from.position.y) + int(t_ * (to.position.y - from.position.y) / 4)
	var x1 := int(from.end.x) + int(t_ * (to.end.x - from.end.x) / 4)
	var y1 := int(from.end.y) + int(t_ * (to.end.y - from.end.y) / 4)
	return Rect2i(x0, y0, x1 - x0, y1 - y0)


func _draw() -> void:
	if phase == 0 or phase == 2:
		var r := lerp_rect(origin, target, t)
		_line(r.position.x, r.position.y, r.end.x, r.position.y, GREY)
		_line(r.end.x, r.position.y, r.end.x, r.end.y, GREY)
		_line(r.end.x, r.end.y, r.position.x, r.end.y, GREY)
		_line(r.position.x, r.end.y, r.position.x, r.position.y, GREY)
		return
	if phase != 1:
		return
	var x := int(target.position.x)
	var y := int(target.position.y)
	var w := int(target.size.x)
	var h := int(target.size.y)
	# 800c2998: the semi-transparent box, then the frame over it (OT order)
	var bc: Color = BOX_COLOURS[box_colour]
	draw_rect(Rect2(_p(x + 4, y + 3), Vector2(w - 8, h - 3) * _s()), Color(bc, 0.5))
	_line(x + 3, y + 3, x + 3, y + h - 3, DARK)
	_line(x + w - 4, y + 3, x + w - 4, y + h - 3, DARK)
	# 800c3260: three-line edges and the four 4x4 corner sprites
	for k in 3:
		var c: Color = [DARK, LIGHT, DARK][k]
		_line(x + 4, y + k, x + w - 4, y + k, c)
		_line(x + 4, y + h - 3 + k, x + w - 4, y + h - 3 + k, c)
	var vc := [DARK, MID, LIGHT]
	for k in 3:
		_line(x + k, y + 4, x + k, y + h - 3, vc[k])
		_line(x + w - 1 - k, y + 4, x + w - 1 - k, y + h - 3, vc[k])
	if _corners:
		for i in 4:
			var cx := x if i & 1 == 0 else x + w - 4
			var cy := y if i < 2 else y + h - 4
			draw_texture_rect_region(_corners, Rect2(_p(cx, cy), Vector2(4, 4) * _s()),
				Rect2((i & 1) * 4, (i >> 1) * 4, 4, 4))
	_draw_contents()
