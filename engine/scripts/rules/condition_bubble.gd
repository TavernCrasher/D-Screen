class_name ConditionBubble
extends RefCounted
## DW1's condition bubbles (docs/condition_bubbles.md): types 0-7 share the bubble, its rise, bob
## and pop; each has its own FEEL_EF icon (icons()). Also the sulking butterfly (butterfly()) and
## Monochromon's shop mood faces (face()). Type 7, shown before a digivolution (docs/film_step5_sprites.md (b)):
## a white thought bubble rises over the partner's head with a black silhouette inside that grows
## (blob -> baby -> rookie -> champion, looping), bobs for 2 s, then pops. addConditionBubble(7)
## 800ec538 from tickEvoSequenceLoading 800e7220 (frame 56 of the lead-in); tickConditionBubble
## 800ecc60 and renderConditionBubble 800ec644 (dw_decomp src/main/bubble.c: icon 12, sprites 9-11).
##
## One step = one 20 fps frame: the tick (with the frame counter fc before its increment), then the
## render with the counter after it, k = fc + 1. Render k draws the state the tick at k - 1 set:
## k 1-50 the icon over the bubble, k 51 the pop alone; the tick at fc 51 removes the bubble.
##
## Drawing (renderSprite 800da36c, libgs GsSortSprite): each sprite is screen-aligned at the
## anchor's projection, scale x h / depth, so in world space a texel is scale / 4096 DW1 units
## (0x6000: 6 units, the bubble 192 wide). The blend rate comes from the attribute (GsSortSprite
## builds the draw mode from attribute bits 28-29, not the tpage's abr): the icon 0x50000000 adds
## its STP texels, the bubble and the pop 0x40000000 blend theirs 50/50; texels without STP are
## opaque, colour 0 is never drawn. Same OT slot, so the bubble (sorted after) is drawn first and
## the icon over it.

const ROW_ICON := 2                       # FEEL_EF CLUT rows (cy 0x1E2 / 0x1E4 - 480)
const ROW_BUBBLE := 4
## CONDITION_EVOLVING_FRAMES: the icon frame per render counter % 19.
const ICON_FRAMES := [0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3]
const RISE_FRAMES := 10
const HOLD_SCALE := 0x6000
const POP_SCALE := 0xF000
const POP_FC := 50                        # the tick at fc 50 turns it into the pop
const LAST_RENDER := 51
const HOLD_LIFT := -65                    # units above the base (y down)
const BOB := 12
const POP_LIFT := -230
## The screen-top clamp (renderConditionBubble): the anchor stays this many texels (at the sprite's
## scale) below the screen's top edge: 32 for the bubble, 8 for the pop.
const TOP_BUBBLE := 32
const TOP_POP := 8

enum Blend { ADD, HALF }

## The types (CONDITION_TYPE_ICONS 0x8012CE44; docs/condition_bubbles.md section 3).
const HUNGRY := 0
const TOILET := 1
const SICK := 2
const SLEEPY := 3
const TIRED := 4
const SKULL := 5                          # never shown in DW1
const INJURED := 6
const EVOLVING := 7
## The icons' frame tables (render main.c:39581-39679).
const HUNGRY_FRAMES := [0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3]
const TOILET_FRAMES := [0, 0, 0, 0, 0, 0, 0, 1, 2, 2, 2, 2, 1]
const INJURED_FRAMES := [0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 0]
const TIRED_U := [0, 0, 16, 16, 32, 32, 48, 48, 48, 48, 48, 48, 48]
const TIRED_MY := [9, 9, 9, 9, 9, 9, 9, 9, 9, 8, 6, 3, 0]
## The sleepy chain (0x8012CE18) by render k: none for k 1-10, then a 19-frame loop of icons 4
## (low z), 5 (+ mid), 6 (+ high), 7 (mid + high), 8 (high), none (list 0x8012CD64).
const ZZZ := {"low": [Rect2i(128, 48, 8, 8), Vector2i(0, 13)], "mid": [Rect2i(152, 16, 8, 8), Vector2i(8, 19)],
	"high": [Rect2i(144, 16, 8, 8), Vector2i(3, 28)]}
const ZZZ_ICONS := {4: ["low"], 5: ["low", "mid"], 6: ["low", "mid", "high"], 7: ["mid", "high"], 8: ["high"]}
const BUTTERFLY_SCALE := 0x5400
const FACE_GROW := 30                     # renders over which a mood face grows (t from 30 down)

## The tick at counter fc: [scale (4.12), lift above the base in DW1 units, y down].
static func tick_state(fc: int) -> Array:
	if fc >= POP_FC:
		return [POP_SCALE, POP_LIFT]
	if fc < RISE_FRAMES:
		# lerp(0, -65, 0, 10, fc - 10): the time runs -10..-1, so DW1's lerp wraps (0, -7 .. -59)
		return [EfeVM.lerp_dw(0, HOLD_SCALE, 0, RISE_FRAMES, fc), EfeVM.lerp_dw(0, HOLD_LIFT, 0, RISE_FRAMES, fc - RISE_FRAMES)]
	var angle := EfeVM.lerp_dw(0, 512, 0, 20, fc)    # wraps mod 513; _sin has 512 steps a turn
	return [HOLD_SCALE, HOLD_LIFT + (EfeVM.sin512(angle) * BOB >> 12)]


## base = 20 - the Digimon's height (DIGIMON_DATA height), y down: the lift is added to it.
static func base_height(height: int) -> int:
	return 20 - height


## What render k (1..51) draws: [] before or after, else a list of sprites back to front, each
## {rect: FEEL_EF texels (row-local), row, pivot (mx, my), blend, scale} (scale in 4.12).
static func sprites(k: int, type := EVOLVING) -> Array:
	if k < 1 or k > LAST_RENDER:
		return []
	var st := tick_state(k - 1)
	var scale: int = st[0]
	if k >= LAST_RENDER:
		return [{"rect": Rect2i(208, 48, 16, 16), "row": ROW_BUBBLE, "pivot": Vector2i(8, 8), "blend": Blend.HALF, "scale": scale}]
	var out := [{"rect": Rect2i(160, 16, 32, 32), "row": ROW_BUBBLE, "pivot": Vector2i(16, 31), "blend": Blend.HALF, "scale": scale}]
	for i in icons(k, type):
		i["blend"] = Blend.ADD
		i["scale"] = scale
		out.append(i)
	return out


## The icon sprites of type at render k ({rect, row, pivot}), drawn over the bubble.
static func icons(k: int, type: int) -> Array:
	match type:
		HUNGRY:
			var f: int = HUNGRY_FRAMES[k % 19]
			var my := 29 if (k % 19 + 1) % 5 == 0 else 26          # a hop on each bite
			return [{"rect": Rect2i(144 + 16 * f, 0, 16, 16) if f < 3 else Rect2i(192, 48, 16, 16), "row": 3, "pivot": Vector2i(8, my)}]
		TOILET:
			return [{"rect": Rect2i(208 + 16 * int(TOILET_FRAMES[k % 13]), 16, 16, 16), "row": 3, "pivot": Vector2i(8, 26)}]
		SICK:
			return [{"rect": Rect2i(192, 16 + 16 * ((k / 20) & 1), 16, 16), "row": 1, "pivot": Vector2i(8, 26)}]
		SLEEPY:
			if k <= 10:
				return []
			var n: int = [4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 6, 7, 8, 0][(k - 11) % 19]
			var out := []
			for z in ZZZ_ICONS.get(n, []):
				out.append({"rect": ZZZ[z][0], "row": 2, "pivot": ZZZ[z][1]})
			return out
		TIRED:
			return [{"rect": Rect2i(192 + int(TIRED_U[k % 13]), 0, 16, 16), "row": 1, "pivot": Vector2i(8, 23 + int(TIRED_MY[k % 13]))}]
		SKULL:
			return [{"rect": Rect2i(224 + 16 * ((k / 15) & 1), 48, 16, 16), "row": 2, "pivot": Vector2i(8, 26)}]
		INJURED:
			return [{"rect": Rect2i(208 + 16 * int(INJURED_FRAMES[k % 20]), 32, 16, 16), "row": 3, "pivot": Vector2i(8, 26)}]
		EVOLVING:
			var f: int = ICON_FRAMES[k % ICON_FRAMES.size()]
			if f == 0:
				return [{"rect": Rect2i(128, 56, 16, 8), "row": ROW_ICON, "pivot": Vector2i(8, 18)}]
			return [{"rect": Rect2i(128 + 16 * f, 48, 16, 16), "row": ROW_ICON, "pivot": Vector2i(8, 26)}]
	return []


## The sulking butterfly at its frame f (render main.c:38011-38037): the sprite and its offset
## from the anchor in DW1 units (x, y down, z): a lap of 150 units a 60 frames, 3 bobs a lap,
## 100 above. {rect, row, pivot, blend, scale, offset}.
static func butterfly(f: int) -> Dictionary:
	var a := EfeVM.lerp_dw(0, 512, 0, 60, f)
	var off := Vector3i(_trunc(EfeVM.sin512(a) * 150), _trunc(EfeVM.sin512(EfeVM.lerp_dw(0, 0x600, 0, 60, f)) * 50) - 100,
		_trunc(EfeVM.cos512(a) * 150))
	return {"rect": Rect2i(((f >> 1) & 1) * 16, 48, 16, 16), "row": 2, "pivot": Vector2i(8, 8), "blend": Blend.ADD,
		"scale": BUTTERFLY_SCALE, "offset": off}


static func _trunc(v: int) -> int:                 # C's division by 4096 (toward zero)
	return v / 4096 if v >= 0 else -((-v) / 4096)


## A mood face at render n from its creation (FUN_800fbe90): t = 30 - n down to 0; it grows from
## 1/16 to full size (scale (16 - t/2) << 8) and rises (16 - t/2) px, then holds. mood 0 laughing,
## 1 smile, 2 worried, 3 frown, 4 angry (mood_faces.png, u = mood * 32). {rect, pivot, scale, lift_px}.
static func face(n: int, mood: int) -> Dictionary:
	var t := maxi(FACE_GROW - n, 0)
	var s := 16 - t / 2
	return {"rect": Rect2i(mood * 32, 0, 32, 32), "pivot": Vector2i(16, 16), "scale": s << 8, "lift_px": s}


## The lift above the base at render k (the tick at k - 1).
static func lift(k: int) -> int:
	return tick_state(clampi(k - 1, 0, POP_FC))[1]


## The screen-top clamp's margin in texels at render k.
static func top_margin(k: int) -> int:
	return TOP_POP if k >= LAST_RENDER else TOP_BUBBLE
