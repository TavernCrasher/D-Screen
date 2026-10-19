class_name Follow
extends RefCounted
## How the partner follows the tamer in the field (DW1-SydPatches Partner.cpp / Map.cpp /
## Helper.cpp). Works on the 100x100 DW1 tile grid in DW1 units:
## - closeness (getPartnerTamerCloseness): stop / walk / sprint by distance, from the
##   partner's radius;
## - a waypoint trail (Partner_tickCollision): while the straight 5-tile-wide corridor to the
##   tamer is blocked, the partner walks through the tiles the tamer stepped on;
## - off-screen catch-up (tickPartnerWaypoints): a partner that fell off screen is put on the
##   tile nearest the tamer that is still off screen.

enum { STOP, WALK, SPRINT }

const RING := 30                     # PARTNER_WAYPOINT_X/Y hold 30 tiles
const BLOCKED := 0x80

var tile_value: Callable             # Vector2i -> collision byte (0x80 = blocked)
var wx := PackedInt32Array()
var wy := PackedInt32Array()
var count := 0                       # PARTNER_WAYPOINT_COUNT
var current := 0                     # PARTNER_WAYPOINT_CURRENT (oldest waypoint)
var prev_tamer := Vector2i(-1, -1)   # PARTNER_TAMER_PREVIOUS_TILE


func _init(tile_value_: Callable) -> void:
	tile_value = tile_value_
	wx.resize(RING)
	wy.resize(RING)


# ---------------------------------------------------------------- grid helpers
static func tile_of(p: Vector3) -> Vector2i:
	## getTileX / getTileZ (DW1 position -> tile). DW1 positions are integers: floor first.
	var x := int(floor(p.x))
	var z := int(floor(p.z))
	var tx := x / 100 + 50 - (1 if x < 0 else 0)
	var tz := 50 - z / 100 - (1 if z > 0 else 0)
	return Vector2i(tx, tz)


static func tile_center(t: Vector2i) -> Vector3:
	return Vector3((t.x - 50) * 100 + 50, 0, (50 - t.y) * 100 - 50)


## TileIterator: the tiles from a towards b (a included, b excluded), DW1's own stepping.
static func tiles_between(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dx := b.x - a.x
	var dy := b.y - a.y
	var ax := absi(dx)
	var ay := absi(dy)
	if ax == 0 and ay == 0:
		return out
	var step_x: int
	var step_y: int
	var sub_x := 0
	var sub_y := 0
	var prog_x := 0
	var prog_y := 0
	var steps: int
	if ax < ay:
		step_x = -1 if dx < 0 else 1
		step_y = -1 if dy < 1 else 1
		sub_x = absi(dx % ay)
		prog_x = ay
		steps = ay
		if sub_x == 0:
			step_x = dx / ay
	else:
		step_x = -1 if dx < 1 else 1
		step_y = -1 if dy < 0 else 1
		sub_y = absi(dy % ax)
		prog_y = ax
		steps = ax
		if sub_y == 0:
			step_y = dy / ax
	var c := a
	while steps > 0:
		out.append(c)
		steps -= 1
		if sub_x == 0:
			c.x += step_x
		else:
			prog_x -= sub_x
			if prog_x < 1:
				c.x += step_x
				prog_x += ay
		if sub_y == 0:
			c.y += step_y
		else:
			prog_y -= sub_y
			if prog_y < 1:
				c.y += step_y
				prog_y += ax
	return out


## isLinearPathBlocked
func path_blocked(a: Vector2i, b: Vector2i) -> bool:
	a = a.clamp(Vector2i.ZERO, Vector2i(99, 99))
	b = b.clamp(Vector2i.ZERO, Vector2i(99, 99))
	if a == b:
		return false
	for t in tiles_between(a, b):
		if int(tile_value.call(t)) & BLOCKED:
			return true
	return false


## isFiveTileWidePathBlocked: the corridor, 5 tiles wide across the main direction.
func wide_path_blocked(a: Vector2i, b: Vector2i) -> bool:
	var along_y := absi(b.x - a.x) < absi(b.y - a.y)
	for i in range(-2, 3):
		var o := Vector2i(i, 0) if along_y else Vector2i(0, i)
		if path_blocked(a + o, b + o):
			return true
	return false


# ---------------------------------------------------------------- closeness
## getPartnerTamerCloseness; positions in DW1 units, radius from the Digimon table.
static func closeness(tamer: Vector3, partner: Vector3, radius: int) -> int:
	var d2 := Vector2(tamer.x - partner.x, tamer.z - partner.z).length_squared()
	var r := radius / 2
	if d2 > pow(r * 7, 2):
		return SPRINT
	if d2 > pow(r * 5, 2):
		return WALK
	return STOP


# ---------------------------------------------------------------- waypoints
## initializePartnerWaypoint
func reset(tamer_tile: Vector2i) -> void:
	count = 0
	current = 0
	prev_tamer = tamer_tile


func _push(index: int, t: Vector2i) -> void:
	wx[index % RING] = t.x
	wy[index % RING] = t.y
	count = mini(count + 1, RING)


func _wp(index: int) -> Vector2i:
	var i := posmod(index, RING)
	return Vector2i(wx[i], wy[i])


func pop() -> void:
	count = maxi(count - 1, 0)
	current = (current + 1) % RING


## The tile the partner heads for, or (-1, -1) = straight at the tamer.
func target() -> Vector2i:
	return _wp(current) if count > 0 else Vector2i(-1, -1)


## Partner_tickCollision, waypoint part: call once per game frame.
func update(tamer_tile: Vector2i, partner_tile: Vector2i) -> void:
	if prev_tamer.x < 0:
		prev_tamer = tamer_tile
	if tamer_tile != prev_tamer:
		if not wide_path_blocked(tamer_tile, partner_tile):
			reset(tamer_tile)
		elif count == 0:
			reset(tamer_tile)                 # (DW1 resets first, so this is the new tile)
			_push(current, prev_tamer)
		elif wide_path_blocked(tamer_tile, _wp(current + count - 1)):
			_push(current + count, prev_tamer)
	if count > 1:                             # drop waypoints the tamer can see past
		for i in 3:
			if not wide_path_blocked(tamer_tile, _wp(current + count - 2 - i)):
				count = maxi(count - (i + 1), 0)
				break
			if i == current:
				break
	if count > 0 and _wp(current) == partner_tile:
		pop()
	prev_tamer = tamer_tile


## getClosestTileOffScreen: walking from the tamer towards the partner, the first tile that
## is off screen (is_off_screen: Callable(Vector2i) -> bool), or (-1, -1).
static func closest_off_screen(tamer_tile: Vector2i, partner_tile: Vector2i,
		is_off_screen: Callable) -> Vector2i:
	for t in tiles_between(tamer_tile, partner_tile):
		if is_off_screen.call(t):
			return t
	return Vector2i(-1, -1)
