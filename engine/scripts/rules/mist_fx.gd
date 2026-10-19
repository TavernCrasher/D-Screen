class_name MistFx
extends RefCounted
## Misty Trees and factory mist (docs/maps.md "Screen effects", FUN_800b4780): two layers of
## four 320x240 additive quads of the 256x200 4bpp texture at VRAM (704, 0), in screen space
## (the DR_OFFSET at OT 32 puts the origin back at the screen centre, FIELD-29). Layer 1
## (B + F/4, colour 150, CLUT row 0) drifts left and follows the scroll, layer 2 (mirrored,
## B + F, colour 80) drifts right at 1.2x the scroll. The offsets
## and CLUT values are globals that last the whole session (never reset on load).

const MAPS := [115, 116, 117, 118, 119, 121, 163, 220]   # MIST01-05, MIST07, FACT11A/B
const FACT := [163, 220]
const MIST05 := 119

static var xs := [-160, 160, 160, -160]   # 0x80134224: layer 1 X0, X1; layer 2 X2, X3
static var ys := [-120, 120]              # 0x8013422c
static var clut := [80, 16]               # 0x80134230: layer-2 CLUT x (MIST05, the others)


## Power-on values (tests).
static func reset() -> void:
	xs = [-160, 160, 160, -160]
	ys = [-120, 120]
	clut = [80, 16]


static func is_mist_map(map_id: int) -> bool:
	return MAPS.has(map_id)


## One field frame. dx, dy = previous scroll - this frame's scroll (background px); even =
## PLAYTIME_FRAMES & 1 == 0. False: nothing drawn (trigger 341 on FACT11, the offsets hold).
static func tick(map_id: int, dx: int, dy: int, even: bool, t148: bool, t341: bool) -> bool:
	if FACT.has(map_id) and t341:
		return false
	if map_id != 220 and t148:
		clut[0] = 192
		clut[1] = 128
	var x0: int = xs[0] + dx - (1 if even else 0)
	if x0 > 159:
		x0 -= 640
	elif x0 < -479:
		x0 += 640
	xs[0] = x0
	xs[1] = x0 + 320 if x0 <= -160 else x0 - 320
	var x2: int = xs[2] + (dx * 12) / 10 + (1 if even else 0)   # C division: toward zero
	if x2 > 479:
		x2 -= 640
	elif x2 < -159:
		x2 += 640
	xs[2] = x2
	xs[3] = x2 + 320 if x2 <= 160 else x2 - 320
	var y0: int = ys[0] + dy
	if y0 > 119:
		y0 -= 480
	elif y0 < -359:
		y0 += 480
	ys[0] = y0
	ys[1] = y0 + 240 if y0 <= -120 else y0 - 240
	return true


## Layer 2's CLUT row (CLUT x / 16): 0 on FACT11, CLUT[0] on MIST05, CLUT[1] elsewhere.
static func layer2_row(map_id: int) -> int:
	if FACT.has(map_id):
		return 0
	return (clut[0] if map_id == MIST05 else clut[1]) / 16


## Builtin 0x25 (FUN_800b5cb8): +16 per frame; true (and 192/128) once past 191.
static func lift_step() -> bool:
	clut[0] += 16
	clut[1] += 16
	if clut[0] > 191:
		clut[0] = 192
		clut[1] = 128
		return true
	return false


## The PS1 colour maths for one texel channel: F = min(31, c5 * colour >> 7).
static func modulate(c5: int, colour: int) -> int:
	return mini(31, (c5 * colour) >> 7)


## DW1 screen coordinates from the centre -> view pixels (one DW1 pixel = view height / 240).
## FUN_800efd30 adds a DR_OFFSET of (160, 120) at OT 32 every frame, so everything at OT <= 32
## (snow 30, mist 20, the fade) is drawn from the screen centre, not the scrolled background.
static func to_view(offset: Vector2, view_size: Vector2) -> Vector2:
	return view_size / 2.0 + offset * (view_size.y / 240.0)
