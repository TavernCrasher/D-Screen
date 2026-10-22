class_name PetPlace
extends Node
## The pet's props (docs/desktop_pet.md "Care"): Train in his menu opens a ring of them orbiting
## him (the Meat, the toilet and File City's six gym stations, PetProps). Drag one out and drop
## it on the taskbar or a window top, or click it to drop it beside him: he walks or leaps over
## and uses it once (trains with the station's DW1 clip, uses the toilet when he's due, eats the
## Meat when he's hungry), then it's gone. The Meat dropped on him: he eats it there. A prop
## waiting on the desktop is a PetPropWindow; once he reaches it, it moves into his own world, so
## he and it overlap with depth. His accidents leave DW1's piles (UNTI) on the desktop, each in its
## own window: a click cleans one.

const RING_PX := 52.0                # a prop's height in the ring, px at 96 dpi
const RING_W := 74.0                 # ... and its widest
const RING_SPIN := 16.0              # degrees per s
const RING_OPEN := 0.25              # s to unfold
const RING_AWAY := 8.0               # s with the cursor off him and the ring before it closes
const SESSION := 12.0                # s on a station (DW1's session is 1200 frames; the desktop's is short)
const LINGER := 10.0                 # s an unused prop stays on the desktop
const GRAVITY := 2600.0
const TRIES := 3                     # leaps toward a prop before he gives up on it
const FLOAT_AT_STATION := 0.75       # of a floating baby's float he drops while he trains (9d 6)
const TOILET_SEAT := Vector3(0, 0.46, -0.04)   # props units: his feet on the bowl's rim (at 0.3 the bowl hid his legs, 9d 15)
const SHRINK_WAIT := 0.6              # s before a used prop shrinks away ...
const SHRINK_TIME := 0.3              # ... and how long it takes (he steps off the toilet with it, 9d 14)
## Station clips (DW1 ids; gym_session.gd): push 0x1B, stand under the water 0, the strike per
## Digimon (GymMoves.STRIKE), brace 0x25 against the glove, run 4, nod 0x16 at the desk (restarted
## every 35 frames), then 0x12 when the session ends.
const CLIP := {"boulder": 27, "waterfall": 0, "glove": 37, "track": 4, "chalkboard": 22}
const A_END := 18
const A_EAT := 8                     # care_actions.gd: the partner eats (Partner.cpp:1233)
const A_SQUAT := 10                  # the toilet squat (ANIM-12)
const A_REFUSE := 13                 # FUN_800ddec0 case 4: refused food (main.c:31848-31855)
const CHALK_EVERY := 35.0 / 20.0
## The gym's sounds (ESALL section 14, docs/pet_sounds.md section 4): 9 as he sets off for a
## station, 0xA when its session ends; the boulder's grind every 10 frames, the waterfall's held
## loop, the log's thwack at each hit, the glove's at each reach, the chalk every 30 frames.
const GYM_SET_OFF := 9
const GYM_END := 0xA
const GYM_BOULDER := 0
const GYM_WATER := 2
const GYM_CHALK := 3
const GYM_GLOVE := 4
const GYM_LOG := 5
const BOULDER_EVERY := 10.0 / 20.0
const CHALK_SOUND_EVERY := 30.0 / 20.0
const GLOVE_FRONT := 0.6             # the glove's front at rest, x in Ninjamon heights (tools/pet_props.py)
const GLOVE_REACH := 100 * 0.0025    # its throw at full reach (DW1's +100, GLOVE scaled to the prop)
## Stations he stands beside or in front of: they stay in their own window while he uses them (his
## window draws the part over it behind him, _mirror), so a big Digimon can stand off them at his
## size without his window cutting them, and nothing pops when he arrives (the user, 2026-10-18).
## The toilet and the track, which he sits or stands on, move into his world for depth.
const BESIDE := ["boulder", "log", "glove", "waterfall", "chalkboard"]
const MOVING := ["Glove", "Target"]  # parts a session moves, copied onto the mirror

var pet                              # pet.gd
var ring: Node3D
var ring_props: Array = []
var ring_open := false
var hover := -1
var tip: PetMenu
var placed: PetPropWindow            # the prop waiting for him on the desktop
var piles := {}                      # pile id -> PetPropWindow
var drag: PetPropWindow
var use := {}                        # the session: {name, node, t, side, ...}
var _ring_t := 0.0
var _angle := 0.0
var _press := -1
var _press_at := Vector2.ZERO
var _away := 0.0
var _tries := 0
var _t := 0.0
var _piles_shown := false            # his saved piles appear once the window list has come in
var _loose: Array = []               # refused props fading on the desktop
var _mirrors := {}                   # desktop window -> its copy drawn in his own window (_mirror)


func setup(pet_) -> void:
	pet = pet_
	ring = Node3D.new()
	ring.visible = false
	pet.holder.get_parent().add_child(ring)
	for name in PetProps.ORDER:
		var n := PetProps.make(name)
		var s := minf(RING_PX * pet.k / pet._px_per_m / float(n.get_meta("h")),
			RING_W * pet.k / pet._px_per_m / float(n.get_meta("w")))
		n.set_meta("ring_scale", s)
		n.scale = Vector3.ONE * s
		ring.add_child(n)
		ring_props.append(n)
	tip = PetMenu.new()
	pet.layer.add_child(tip)


## A prop's scale in his world: a Ninjamon height is his own height, so every Digimon gets props
## his size (the user, 2026-10-18: "similar to the training area").
func prop_scale() -> float:
	return pet.model_px * pet.k / pet._px_per_m


# ---------------------------------------------------------------- the ring
func open_ring() -> void:
	ring_open = true
	ring.visible = true
	_ring_t = 0.0
	_away = 0.0
	hover = -1


func close_ring() -> void:
	ring_open = false
	ring.visible = false
	hover = -1
	_press = -1
	if tip.visible:
		tip.close_window()


func _tick_ring(delta: float, clicks: Array) -> void:
	if not ring_open:
		return
	_ring_t += delta
	if hover < 0:
		_angle += RING_SPIN * delta
	var f := clampf(_ring_t / RING_OPEN, 0.0, 1.0)
	# sized by his height, not his measured width (a wide pose like Tyrannomon's spread the ring past
	# the window: only its top-left quarter showed, the user, 2026-10-18), and never wider than the
	# window; high enough that the front props (hovered: 1.3x) stay above the taskbar and the window's
	# bottom, low enough that the back ones stay under the screen's and the window's top
	var edge: float = RING_W * pet.k * 0.65
	var rx_px: float = minf(pet.model_px * 0.85 * pet.k, float(pet.win.size.x) / 2.0 - edge - 4.0 * pet.k)
	var wy := float(pet.win.position.y)
	var feet: float = wy + float(pet.win.size.y) - pet.FEET * pet.k
	var bottom: float = minf(pet._usable().end.y, wy + float(pet.win.size.y))
	var top: float = maxf(pet._screen_rect().position.y, wy)
	var prop_half: float = RING_PX * pet.k * 0.65 + 4.0 * pet.k
	rx_px = PetGround.ring_fit(rx_px, bottom, top, prop_half, pet.PITCH)
	var cy_px: float = PetGround.ring_height(pet.top_px * 0.45 * pet.k, feet, bottom, top, rx_px, prop_half, pet.PITCH)
	var rx: float = rx_px / pet._px_per_m * f
	var cy: float = cy_px / pet._px_per_m
	# near a screen edge he's drawn off his window's centre: the ring slides back inside the window
	var half: float = rx_px + edge
	var bx: float = pet._body_x()
	ring.position.x = (clampf(bx, half, maxf(half, float(pet.win.size.x) - half)) - bx) / pet._px_per_m
	for i in ring_props.size():
		var n: Node3D = ring_props[i]
		var a := deg_to_rad(_angle + i * 360.0 / ring_props.size())
		n.position = Vector3(rx * cos(a), cy - rx * 0.3 * sin(a) - float(n.get_meta("h")) * float(n.get_meta("ring_scale")) * 0.5, rx * sin(a))
		n.rotation_degrees.y = sin(_t * 0.8 + i) * 25.0
		var s: float = float(n.get_meta("ring_scale")) * f * (1.3 if i == hover else 1.0)
		n.scale = Vector3.ONE * s
	var m := Vector2(DisplayServer.mouse_get_position() - pet.win.position)
	for c in clicks:
		if _ring_t < 0.3:
			break                                    # the menu click that opened it, reported late by the helper
		if not pet._hit_rects().any(func(r): return r.has_point(c - Vector2(pet.win.position))):
			close_ring()
			return
	_away = 0.0 if pet._hit_rects().any(func(r): return r.has_point(m)) else _away + delta
	if _away >= RING_AWAY:
		close_ring()
		return
	_set_hover(prop_at(m))


func _set_hover(i: int) -> void:
	if i == hover:
		if i >= 0:
			_place_tip()
		return
	hover = i
	if i < 0:
		if tip.visible:
			tip.close_window()
		return
	var label: String = PetProps.LABEL[PetProps.ORDER[i]]
	var glyphs: Array = DwText.layout(label, 1)["glyphs"]
	tip.width = PetMenu.ROW_X + (int(glyphs[-1][1]) + 14 if not glyphs.is_empty() else 40)
	tip.open_menu(PackedStringArray([label]), Vector2.ZERO, Rect2(pet._dw(_screen_of(i)), Vector2(8, 8)))
	tip.hover = 0
	_place_tip()


func _place_tip() -> void:
	var p: Vector2 = pet._dw(_screen_of(hover) + Vector2(0, 30.0 * pet.k))
	var lo: Vector2 = pet._dw(Vector2.ZERO)
	var hi: Vector2 = pet._dw(Vector2(pet.win.size))
	p.x = clampf(p.x - tip.width / 2.0, lo.x + 2, hi.x - tip.width - 2)
	p.y = clampf(p.y, lo.y + 2, hi.y - tip.target.size.y - 2)
	tip.target.position = p


## A ring prop's centre in window pixels.
func _screen_of(i: int) -> Vector2:
	var n: Node3D = ring_props[i]
	var c := n.global_position + Vector3(0, float(n.get_meta("h")) * n.scale.y * 0.5, 0)
	return pet.cam.unproject_position(c)


func _rect_of(i: int) -> Rect2:
	var n: Node3D = ring_props[i]
	var hp: float = float(n.get_meta("h")) * n.scale.y * pet._px_per_m
	var wp: float = float(n.get_meta("w")) * n.scale.x * pet._px_per_m
	var side := maxf(maxf(hp, wp), 30.0 * pet.k)
	return Rect2(_screen_of(i) - Vector2(side, side) / 2.0, Vector2(side, side))


## The ring prop under p (window pixels), the nearest when they overlap; -1 for none.
func prop_at(p: Vector2) -> int:
	if not ring_open or _ring_t < RING_OPEN:
		return -1
	var best := -1
	var best_d := INF
	for i in ring_props.size():
		if _rect_of(i).has_point(p):
			var d := p.distance_to(_screen_of(i))
			if d < best_d:
				best_d = d
				best = i
	return best


## Where the window takes clicks while the ring is open.
func hit_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if ring_open:
		for i in ring_props.size():
			out.append(_rect_of(i))
		if tip.visible:
			out.append(pet._in_window(tip.pixel_rect()))
	return out


## Mouse on his window while the ring is open: true if the ring took it.
func ring_input(e: InputEvent) -> bool:
	if drag != null:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
			_drop()
		return true
	if not ring_open:
		return false
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_press = prop_at(e.position)
			_press_at = Vector2(DisplayServer.mouse_get_position())
			return _press >= 0
		if _press >= 0:
			var name: String = PetProps.ORDER[_press]
			_press = -1
			close_ring()
			_place_beside(name)
			return true
		return false
	if e is InputEventMouseMotion and _press >= 0 \
			and Vector2(DisplayServer.mouse_get_position()).distance_to(_press_at) > 6.0 * pet.k:
		var name: String = PetProps.ORDER[_press]
		_press = -1
		close_ring()
		_start_drag(name)
		return true
	return _press >= 0


# ---------------------------------------------------------------- the props on the desktop
func _window(name: String) -> PetPropWindow:
	var w := PetPropWindow.new()
	w.setup(PetProps.make(name), pet._px_per_m, prop_scale(), pet.k, pet.PITCH)
	add_child(w)
	_keep_pet_on_top()
	return w


## His window stays over the props' (both are always on top: the last raised wins). Raised by the
## helper (SetWindowPos): toggling his always_on_top flag made Godot hide his window.
func _keep_pet_on_top() -> void:
	pet.raise_window.call_deferred()


func _start_drag(name: String) -> void:
	_clear_placed()
	drag = _window(name)
	drag.feet = _drag_feet()
	drag.place()


func _drag_feet() -> Vector2:
	var h: float = float(drag.node.get_meta("h")) * prop_scale() * pet._px_per_m
	return Vector2(DisplayServer.mouse_get_position()) + Vector2(0, h * 0.5)


func _drop() -> void:
	var w := drag
	drag = null
	var m := Vector2(DisplayServer.mouse_get_position())
	if w.node.get_meta("prop") == "meat" and pet._hit_rects()[0].has_point(m - Vector2(pet.win.position)) \
			and pet.can_use():
		w.queue_free()
		_meat_in_hand()
		return
	w.falling = true
	w.fall_v = 0.0
	_set_placed(w)


## A click on a ring prop: it drops beside him, on the side with more room.
func _place_beside(name: String) -> void:
	_clear_placed()
	var w := _window(name)
	var f: Vector2 = pet._feet()
	var u: Rect2 = pet._usable() if pet.ground.size == Vector2.ZERO else pet.ground
	var gap: float = (pet.body_w * 0.5 + 10.0) * pet.k + float(w.node.get_meta("w")) * prop_scale() * pet._px_per_m * 0.5
	var side := 1.0 if u.end.x - f.x > f.x - u.position.x else -1.0
	w.feet = Vector2(f.x + side * gap, f.y - 60.0 * pet.k)
	_keep_on_screen(w)
	w.falling = true
	w.fall_v = 0.0
	_set_placed(w)


## A prop or pile stays whole on its screen (a blackboard dropped beside him at the screen's end
## was cut off, the user, 2026-10-18): its ends from the origin (PetProps "x0" / "x1", mirrored).
func _keep_on_screen(w: PetPropWindow) -> void:
	var u: Rect2 = pet._usable()
	for i in DisplayServer.get_screen_count():
		var r := Rect2(DisplayServer.screen_get_usable_rect(i))
		if r.has_point(Vector2(w.feet.x, r.get_center().y)):
			u = r
	var px: float = absf(w.node.scale.x) * pet._px_per_m
	var x0 := float(w.node.get_meta("x0", -0.5))
	var x1 := float(w.node.get_meta("x1", 0.5))
	if w.node.scale.x < 0.0:
		var t := x0
		x0 = -x1
		x1 = -t
	var lo: float = u.position.x - x0 * px + 4.0 * pet.k
	var hi: float = u.end.x - x1 * px - 4.0 * pet.k
	w.feet.x = clampf(w.feet.x, lo, maxf(lo, hi))


func _set_placed(w: PetPropWindow) -> void:
	placed = w
	w.age = 0.0
	_tries = 0
	if Vpet.STATIONS.has(w.node.get_meta("prop")):
		pet.gym(GYM_SET_OFF)
	if w.node.get_meta("prop") == "glove":
		# it faces him from the start (+x unless he's on its left), so it doesn't flip when he arrives
		var face := 1.0 if pet._feet().x >= w.feet.x else -1.0
		w.set_meta("face", face)
		w.node.scale.x = absf(w.node.scale.x) * face
	w.pressed.connect(func():                    # a click takes it away again
		if placed == w and use.is_empty():
			placed = null
			w.vanish())
	w.place()


func _clear_placed() -> void:
	if placed != null and is_instance_valid(placed):
		placed.vanish()
	placed = null


## Props and piles fall onto the first edge below when what they stand on goes.
func _tick_windows(delta: float) -> void:
	_loose = _loose.filter(func(w): return is_instance_valid(w))
	var all: Array = piles.values() + _loose
	if placed != null and is_instance_valid(placed):
		all.append(placed)
	for w in all:
		if not is_instance_valid(w):
			continue
		if not w.falling and w.ground.size != Vector2.ZERO \
				and not PetGround.stands_on(pet.windows, w.ground, w.feet.x, pet._usable(), 0.0, 4.0 * pet.k):
			w.falling = true
			w.fall_v = 0.0
		if w.falling:
			var y0: float = w.feet.y
			w.fall_v += GRAVITY * pet.k * delta
			w.feet.y += w.fall_v * delta
			var hit := PetGround.landing(pet.windows, w.feet.x, y0, w.feet.y, pet._usable(), 0.0, 4.0 * pet.k)
			if not hit.is_empty():
				w.feet.y = float(hit["y"])
				w.ground = hit["rect"]
				w.falling = false
				_keep_on_screen(w)
				_moved_pile(w)
		elif w.ground.size != Vector2.ZERO:
			var now := PetGround.follow(pet.windows, w.ground)
			if now.size != Vector2.ZERO:
				w.feet += now.position - w.ground.position   # rides along
				w.ground = now
		else:
			w.feet.y = pet.floor_at(w.feet.x)            # on the taskbar: rides it when it slides
		w.place()
	if drag != null:
		drag.feet = _drag_feet()
		drag.place()
	if placed != null and is_instance_valid(placed) and use.is_empty():
		placed.age += delta
		PetProps.animate(placed.node, _t)
		if placed.age > LINGER * 3.0:            # never reached: gone
			_clear_placed()



## After his window has moved this frame: the copies of the props and piles under it, placed
## against where it is now (placed before the move, they lagged a frame and rippled as he walked).
func after_move() -> void:
	_loose = _loose.filter(func(w): return is_instance_valid(w))
	var all: Array = piles.values() + _loose
	if placed != null and is_instance_valid(placed):
		all.append(placed)
	if drag != null:
		all.append(drag)
	var uw = use.get("win")
	if uw != null and is_instance_valid(uw):
		all.append(uw)
	_mirror(all)


## Where a prop's or pile's window lies under his (a big transparent window), OpenGL doesn't draw
## the covered part: only what stuck out past his window showed (the user, 2026-10-18). So while
## they overlap his window draws a copy in the same spot, a little behind him.
func _mirror(all: Array) -> void:
	for w in _mirrors.keys():
		if not is_instance_valid(w) or not w in all:
			if is_instance_valid(_mirrors[w]):
				_mirrors[w].queue_free()
			_mirrors.erase(w)
	var mine := Rect2(Vector2(pet.win.position), Vector2(pet.win.size))
	var th := deg_to_rad(pet.PITCH)
	for w in all:
		if not is_instance_valid(w.node) or not w.node.is_inside_tree():
			continue
		var over := mine.intersects(Rect2(Vector2(w.position), Vector2(w.size)))
		var m: Node3D = _mirrors.get(w)
		if not over:
			if m != null:
				m.visible = false
			continue
		if m == null:
			var name: String = w.node.get_meta("prop", "")
			m = PetProps.make(name) if name != "" else PetProps.pile(false)
			pet.holder.get_parent().add_child(m)
			_mirrors[w] = m
		m.visible = true
		m.scale = w.node.scale
		m.rotation = w.node.rotation
		var z := -0.4 * prop_scale()
		# both from where the windows really are (whole pixels): from his float position the copy drifted
		# 0-1 px against the prop's own window while he walked, a shimmer at the edges (9d 16)
		var me: Vector2 = Vector2(pet.win.position) + Vector2(pet._body_x(), pet._floor_y() - pet.FEET * pet.k)
		var it: Vector2 = Vector2(w.position) + Vector2(w.size.x / 2.0, w.size.y - PetPropWindow.FEET * w._k)
		var up: float = (me.y - it.y) / pet._px_per_m
		m.position = Vector3((it.x - me.x) / pet._px_per_m, (up + z * sin(th)) / cos(th), z) \
			+ Vector3(w.node.position.x, w.node.position.y, 0)   # a session's jitter
		for part in MOVING:                          # the glove's punch, the log's shake
			var a := w.node.find_child(part, true, false) as Node3D
			var b := m.find_child(part, true, false) as Node3D
			if a != null and b != null:
				b.transform = a.transform
		PetProps.animate(m, _t)


# ---------------------------------------------------------------- going to it and using it
## Called every frame while he's free (idle): heads for the waiting prop.
func want(delta: float) -> bool:
	if placed == null or not is_instance_valid(placed) or placed.falling or not use.is_empty():
		return false
	if not pet.can_use():
		return false
	var name: String = placed.node.get_meta("prop")
	var f: Vector2 = pet._feet()
	var side := -1.0 if f.x < placed.feet.x else 1.0      # the side he comes from
	if name == "glove":
		side = float(placed.get_meta("face", 1.0))       # the side the glove punches toward
	var stand := Vector2(placed.feet.x + side * _offset(name, side), placed.feet.y)
	var same: bool = (placed.ground.size == Vector2.ZERO and pet.ground.size == Vector2.ZERO and absf(f.y - placed.feet.y) < 4.0) \
		or placed.ground.is_equal_approx(pet.ground)
	if same and absf(f.x - stand.x) < 10.0 * pet.k:
		_begin(name, side)
		return true
	if same:
		pet._walk(stand.x - float(pet.win.size.x) / 2.0)
		return true
	_tries += 1
	if _tries > TRIES:
		_clear_placed()
		pet._act(pet.brain.A_UNHAPPY, pet.brain.pick("cant_reach"))
		return true
	pet._jump(stand, placed.ground)
	return true


## How far from the prop's centre he stands (px): beside the stations he hits or pushes, in front
## of the waterfall, the board, the toilet and on the track.
func _offset(name: String, side := 1.0) -> float:
	match name:
		"boulder", "log", "glove":
			# beside him, by his height rather than his measured width (Tyrannomon's spread arms put
			# the prop past his window's edge: cut in half, the user, 2026-10-18), with a gap that
			# grows with his size (he sat too close for his size); the glove from its front at full
			# reach; the prop's far side stays inside his window
			var px: float = prop_scale() * pet._px_per_m
			var near := _near_end(name, side)
			var want_px: float = _half_body() + (6.0 + pet.model_px * 0.12) * pet.k + near * px
			if name == "glove":
				want_px = (GLOVE_FRONT + GLOVE_REACH) * px + _half_body() * 1.1
			return want_px                           # it stays in its own window (BESIDE): no window limit
		"meat":
			return _half_body() + 4.0 * pet.k
		"chalkboard":
			return _prop_w_px(name) * 0.25
	return 0.0


## Half his body's width for standing beside things: the measured width, but no more than 0.3 of
## his height (wide poses measure their arms).
func _half_body() -> float:
	return minf(pet.body_w * 0.42, pet.model_px * 0.3) * pet.k


## How far the waiting prop reaches from its origin toward him, in Ninjamon heights, mirrored as
## it stands; he is on `side` of it.
func _near_end(name: String, side: float) -> float:
	return _end_of(name, side)


func _end_of(name: String, toward: float) -> float:
	if placed == null or not is_instance_valid(placed) or placed.node.get_meta("prop") != name:
		return 0.5
	var n := placed.node
	var x0 := float(n.get_meta("x0", -0.5))
	var x1 := float(n.get_meta("x1", 0.5))
	if n.scale.x < 0.0:
		var t := x0
		x0 = -x1
		x1 = -t
	return maxf(0.0, x1 if toward > 0.0 else -x0)


func _prop_w_px(name: String) -> float:
	if placed != null and is_instance_valid(placed) and placed.node.get_meta("prop") == name:
		return float(placed.node.get_meta("w")) * prop_scale() * pet._px_per_m
	return 60.0 * pet.k


## He's there: the prop moves from its window into his world, where it stood.
func _begin(name: String, side: float) -> void:
	var node := placed.node
	var win: PetPropWindow = null
	if name in BESIDE:
		win = placed                                 # stays in its window (BESIDE)
	else:
		var at: float = (placed.feet.x - pet._feet().x) / pet._px_per_m
		node.get_parent().remove_child(node)
		placed.queue_free()
		pet.holder.get_parent().add_child(node)
		node.position = Vector3(at, 0, 0)
		node.scale = Vector3.ONE * prop_scale()
	placed = null
	use = {"name": name, "node": node, "win": win, "t": 0.0, "side": side, "next": 0.0, "hit": -1.0}
	pet.start_use()
	var face := -side                                # toward the prop
	match name:
		"meat":
			pet.ss(pet.SS_FEED)
			if pet.care.hungry():
				_face(face * 40.0)
				pet._play(A_EAT)
				use["end"] = _clip_len(A_EAT)
			else:
				_refuse("full")
		"toilet":
			if pet.care.use_toilet():               # settled as he sits: the window can't run out mid-squat (PET-11)
				_face(0.0)
				pet.holder.position = Vector3(0, TOILET_SEAT.y, TOILET_SEAT.z) * prop_scale()   # on the rim, his legs over the bowl's front
				pet._play(A_SQUAT)
				use["end"] = 4.0
			else:
				_refuse("toilet_no")
		"track":
			_face(90.0 * face)
			node.set_meta("belt_dir", face)          # the belt runs under him (not mirrored: the look snapped)
			pet.holder.position.y = 0.08 * prop_scale()
			use["end"] = SESSION
		"chalkboard":
			_face(140.0 * face)
			use["end"] = SESSION
		"waterfall":
			_face(0.0)
			use["end"] = SESSION
		"glove":
			_face(90.0 * face)
			use["end"] = SESSION
			use["next"] = -1.0                       # the last punch cycle played: none, so cycle 0's punch
			                                         # plays too (it was silent, 0 = "already played", 9d 17)
		_:
			_face(90.0 * face)
			use["end"] = SESSION
	if not use.is_empty() and Vpet.STATIONS.has(name):
		# a floating baby trains down at the station, not hovering over it (props are his mesh's
		# height; Poyomon floated over the waterfall, the user, 9d 6); _end puts him back up
		pet.holder.position.y -= DigimonModel.dw1_bottom(pet.type) * FLOAT_AT_STATION
		match name:
			"boulder":
				pet.gym(GYM_BOULDER)
				use["grind"] = 0.0
			"waterfall":
				use["loop"] = pet.gym(GYM_WATER)
			"chalkboard":
				use["chalk"] = 0.0
		pet._play(_station_clip(name))
		if pet.brain.rng.randf() < 0.4:
			pet._say(pet.brain.pick("train_start"))


func _face(yaw: float) -> void:
	pet.facing = Vector3(0, yaw, 0)                         # he turns to it (pet._tick_facing)


func _refuse(line: String) -> void:
	var node: Node3D = use["node"]
	if line == "toilet_no":
		# DW1 has no toilet refusal (its toilet only works when he needs it): he turns his head away.
		# Not 13, food's refusal, whose stand-in on Tyrannomon looks like a squat (the user, 2026-10-18)
		_face(55.0 * (1.0 if pet.brain.rng.randf() < 0.5 else -1.0))
		pet._play(pet.brain.A_IDLE)
	else:
		_face(0.0)
		pet._play(A_REFUSE)
	pet._say(pet.brain.pick(line))
	use = {}
	pet.end_use()                                    # he's free; the prop lingers in his world
	pet.holder.get_parent().remove_child(node)
	_back_to_desktop(node)


## A refused prop goes back onto the desktop where it stood, then fades.
func _back_to_desktop(node: Node3D) -> void:
	var w := PetPropWindow.new()
	var name: String = node.get_meta("prop")
	var at: float = node.position.x * pet._px_per_m
	node.queue_free()
	w.setup(PetProps.make(name), pet._px_per_m, prop_scale(), pet.k, pet.PITCH)
	add_child(w)
	_keep_pet_on_top()
	w.feet = pet._feet() + Vector2(at, 0)
	w.ground = pet.ground
	w.place()
	w.vanish(LINGER)
	_loose.append(w)


func _station_clip(name: String) -> int:
	if name == "log":
		return int(_strike()[0])
	return int(CLIP[name])


## The strike clip and its hit frame for him (TRN 8008f050).
func _strike() -> Array:
	var id: int = pet.type
	return GymMoves.STRIKE[id] if id < GymMoves.STRIKE.size() else [46, 10]


func _clip_len(_id: int) -> float:
	return DigimonModel.clip_length(pet.model)


func _meat_in_hand() -> void:
	var node := PetProps.make("meat")
	node.set_meta("prop", "meat")
	pet.holder.get_parent().add_child(node)
	node.scale = Vector3.ONE * prop_scale()
	node.position = Vector3(0, pet.top_px * 0.5 * pet.k / pet._px_per_m, 0.4 * prop_scale())
	use = {"name": "meat", "node": node, "t": 0.0, "side": 1.0, "next": 0.0, "hit": -1.0}
	pet.start_use()
	pet.ss(pet.SS_FEED)
	if pet.care.hungry():
		_face(0.0)
		pet._play(A_EAT)
		use["end"] = _clip_len(A_EAT)
	else:
		_refuse("full")


func tick_use(delta: float) -> void:
	if use.is_empty():
		return
	use["t"] = float(use["t"]) + delta
	var t: float = use["t"]
	var name: String = use["name"]
	var node: Node3D = use["node"]
	PetProps.animate(node, _t)
	var clip_done := not DigimonModel.is_playing(pet.model)
	match name:
		"meat":
			if t > 11.0 / 20.0 and node.visible:
				node.visible = false                 # gone at the eat clip's frame 11 (FUN_800ddec0 case 5)
		"log":
			var s := _strike()
			var since := t - float(use["next"])
			if float(use["hit"]) < 0.0 and since >= int(s[1]) / 20.0:
				use["hit"] = t
				pet.gym(GYM_LOG)
			if since >= (int(s[1]) + 41) / 20.0 and t < float(use["end"]):   # the next strike once the shake ends
				use["next"] = t
				use["hit"] = -1.0
				pet._play(int(s[0]))
			_shake(node, t)
		"glove":
			_glove(node, t)
		"chalkboard":
			if t - float(use["next"]) >= CHALK_EVERY and t < float(use["end"]):
				use["next"] = t
				pet._play(22)
			if t - float(use["chalk"]) >= CHALK_SOUND_EVERY and t < float(use["end"]):
				use["chalk"] = t
				pet.gym(GYM_CHALK)
		"boulder":
			if not node.has_meta("jit_x0"):
				node.set_meta("jit_x0", node.position.x)
			# DW1's ±2 px jitter a DW1 frame, about its rest spot (added each frame, it drifted at 60 fps)
			node.position.x = float(node.get_meta("jit_x0")) + (1.0 if int(t * 20.0) % 2 == 0 else -1.0) * pet.k / pet._px_per_m
			if clip_done and t < float(use["end"]):
				pet._play(27)
			if t - float(use["grind"]) >= BOULDER_EVERY and t < float(use["end"]):
				use["grind"] = t
				pet.gym(GYM_BOULDER)
	if t < float(use["end"]):
		return
	if not use.has("done"):
		use["done"] = true
		_finish(name)
	elif clip_done or t > float(use["end"]) + 2.5:
		_end()


func _finish(name: String) -> void:
	var node: Node3D = use["node"]
	match name:
		"meat":
			pet.care.feed()
			pet._play(pet.brain.A_JOY)               # DW1 after a meal he wanted: 0xB (FUN_800a7b94)
			pet._say(pet.brain.pick("ate"))
		"toilet":
			pet._play(pet.brain.A_HAPPY)
			pet._say(pet.brain.pick("toilet_done"))
			_shrink(node)
			# down off the seat as it shrinks away; he hovered at seat height until the clip ended (9d 14)
			var down := create_tween()
			down.tween_interval(SHRINK_WAIT)
			down.tween_property(pet.holder, "position", Vector3.ZERO, SHRINK_TIME)
		_:
			pet.gym(GYM_END)
			_stop_loop()
			var r: Dictionary = pet.care.train(name)
			_face(0.0)
			pet.holder.position = Vector3.ZERO
			pet._play(A_END)
			var line: String = pet.brain.pick({"frozen": "trained_frozen", "enough": "trained_enough"}.get(r["why"], "trained"))
			if int(r["gain"]) > 0:
				line = line.split("\n")[0] + "\n%s +%d" % [VpetSave.LABELS[r["stat"]], int(r["gain"])]
				pet._update_forecast()
			pet._say(line)
			_shrink(node)


func _shrink(node: Node3D) -> void:
	var tw := create_tween()
	tw.tween_interval(SHRINK_WAIT)
	tw.tween_property(node, "scale", node.scale * 0.05, SHRINK_TIME)


func _end() -> void:
	_free_use()
	use = {}
	pet.holder.position = Vector3.ZERO
	pet.end_use()


## Interrupted (picked up, fell): the prop is gone with him.
func cancel() -> void:
	if use.is_empty():
		return
	_free_use()
	use = {}
	pet.holder.position = Vector3.ZERO


func _stop_loop() -> void:
	if use.get("loop") != null and pet.sfx:
		pet.sfx.stop(use["loop"])
		use.erase("loop")


func _free_use() -> void:
	_stop_loop()
	var w = use.get("win")
	if w != null and is_instance_valid(w):
		w.queue_free()
	elif is_instance_valid(use["node"]):
		(use["node"] as Node3D).queue_free()


## The log shakes for 41 frames after each hit (TRN 8008b820).
func _shake(node: Node3D, t: float) -> void:
	var target := node.find_child("Target", true, false) as Node3D
	if target == null:
		target = node
	var since := t - float(use["hit"]) if float(use["hit"]) >= 0.0 else 99.0
	target.rotation_degrees.z = sin(since * 40.0) * 6.0 * maxf(0.0, 1.0 - since / 2.05) if since < 2.05 else 0.0


## The glove's cycle (DW1's 39 frames, GymMoves.glove_offsets: out to +100, back, smaller swings),
## toward him; at full reach he braces again and is knocked back a little.
func _glove(node: Node3D, t: float) -> void:
	var g := node.find_child("Glove", true, false) as Node3D
	var offs: Array = GymMoves.glove_offsets()
	var f := int(t * 20.0) % offs.size()
	if g != null:
		if not g.has_meta("x0"):
			g.set_meta("x0", g.position.x)
		g.position.x = float(g.get_meta("x0")) + float(offs[f]) * 0.0025
	# no punch once the session ended: the glove shrinks away, and it went on "boing"-ing until _end
	# (the user, 9d 17; the log, chalkboard and boulder already stopped at the end)
	if f == 1 and t < float(use["end"]) and float(use["next"]) != floorf(t * 20.0 / offs.size()):
		use["next"] = floorf(t * 20.0 / offs.size())
		pet._play(37)
		pet.gym(GYM_GLOVE)                           # each time it reaches him (trn_def.c:129, 236-238; PET-29)


func _moved_pile(w: PetPropWindow) -> void:
	for id in piles:
		if piles[id] == w:
			for p in pet.care.piles():
				if int(p["id"]) == int(id):
					p["x"] = w.feet.x
					p["y"] = w.feet.y


# ---------------------------------------------------------------- piles
func add_pile(p: Dictionary) -> void:
	_pile_window(p)


func _pile_window(p: Dictionary) -> void:
	var have = piles.get(int(p["id"]))
	if have != null and is_instance_valid(have):         # an accident before the saved piles were drawn
		return                                           # had two windows: one stayed after a clean (the user)
	var w := PetPropWindow.new()
	w.setup(PetProps.pile(), pet._px_per_m, 1.0, pet.k, pet.PITCH)
	add_child(w)
	var u: Rect2 = pet._usable()
	w.feet = Vector2(clampf(float(p["x"]), u.position.x + 20.0, u.end.x - 20.0), minf(float(p["y"]), u.end.y))
	w.falling = true                                 # settles onto whatever is under it now
	w.place()
	var id := int(p["id"])
	piles[id] = w
	w.pressed.connect(func(): _clean(id))
	_keep_pet_on_top()


func _clean(id: int) -> void:
	var w: PetPropWindow = piles.get(id)
	piles.erase(id)
	if w != null and is_instance_valid(w):
		w.vanish()
	if pet.care.clean(id) and pet.can_use():
		pet._act(pet.brain.A_HAPPY, pet.brain.pick("clean"))


func tick(delta: float, clicks: Array) -> void:
	_t += delta
	if not _piles_shown and (not pet.windows.is_empty() or _t > 3.0):
		_piles_shown = true                          # else they'd all fall through to the taskbar
		for p in pet.care.piles():
			_pile_window(p)
	_tick_ring(delta, clicks)
	_tick_windows(delta)
