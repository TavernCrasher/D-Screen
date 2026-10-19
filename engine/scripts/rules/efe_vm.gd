class_name EfeVM
extends RefCounted
## DW1's technique effects (EFE): the per-technique bytecode in ETCHI/EFEDAT.EFE run by the
## battle's effect engine (object 0x500; BTL 8006ec68, ported from jype0's dw_decomp
## src/btl/battle_effect.c, checked against Ghidra). docs/battle_system.md, "Technique effects".
##
## A technique's start script spawns a root instance; each frame every live sub-effect's tick
## script runs (frame + 1), then its draw script. Scripts move their instances and call
## collision natives; whatever they touch gets is_hit and an entry pushed through hit_cb, which
## the battle resolves on the next frame (8005c798). Timing is per technique, not per clip.
##
## Coordinates: the VM works in DW1's own frame (x right, y down, z forward; right-handed). The
## battle's space keeps Godot's z (battle_view: (x, z) from the map), a mirror of DW1's, so
## positions cross the boundary as (x, 0, -z) and the facing as -f (_loc, _rot_y, hit_cb,
## instances(), aabb_hit callers): otherwise every effect is DW1's mirror image (left-glove bombs
## in the right glove, spins reversed; EFE-3B-1). The draw list is in DW1's frame too.
##
## Deliberate differences: fighters have no skeletons here, so bone k comes from DW1's own
## clips simulated offline (data/efe.json "clips": the technique clip's pose at the current
## frame; "bones": the idle pose otherwise), turned by the fighter's facing; bone 0 = the
## fighter's transform, exact as in DW1. rand() comes from the VM's own generator so the
## battle's rolls stay reproducible.
##
## Drawing (docs/efe_effects.md sections 1 and 4): the render natives don't draw here; they
## record what DW1 would draw into `draws` (rebuilt every tick: TMD objects, projected,
## screen and flash sprites, 2D quads, lines, grids, wire boxes, the screen fade, the map
## layer and fixed camera switches) and their one-shot spawns into `events` (sounds,
## particle emitters, flashes, clouds, entity crackle; collect with take_events()). Each entry
## is a Dictionary with "kind", "slot", "sub", "tech" and the native's operands, values in DW1
## units and DW1's raw fixed point (4096 = 1.0, colours 128 = 1.0). Per-slot state that
## changes how a TMD draws lives in the Slot as in DW1 (uv_anims, colors) and is copied into
## each "tmd" entry; the textures and meshes are data/efe_assets (tools/dw1_efe_assets.py).

const BASE := 0x1000000                 # address of a slot's data D[0]; 0 stays NULL
const ENT_MAX := 10                     # ENTITY_TABLE: 0 tamer, 1 partner, 2.. enemies
const STEP_LIMIT := 20000               # a runaway script stops (never seen in the data)
## Operand counts of every native (BTL_D_800732FC); those not ported below just pop these.
const POPS := [1, 3, 2, 2, 8, 0, 2, 2, 2, 0, 2, 2, 6, 3, 1, 2, 4, 1, 8, 1, 13, 4, 9, 1, 13, 3, 3,
	1, 1, 0, 5, 3, 1, 1, 4, 2, 6, 1, 3, 3, 6, 3, 1, 2, 3, 2, 0, 2, 2, 2, 2, 2, 2, 2, 2, 0, 3, 2, 2,
	2, 7, 3, 3, 0, 0, 12, 10, 1, 3, 0, 11, 2, 2, 2, 4, 1, 1, 2, 4, 2, 4, 1, 1, 1, 1, 3, 6, 3, 0, 3,
	2, 3, 1, 0, 1, 0, 1]


class Sub:
	var inst := 0        # tick script (0 = free)
	var draw := 0        # draw script (someInst)
	var instance := 0    # address of {frame, pos xyz, rot xyz}
	var parent := 0
	var src := -1        # entity indices (-1 = NULL)
	var tgt := -1
	var bone := 0        # address of {bone, x, y, z} (checkTechCompatibility)


class Slot:
	var tech := -1
	var hdr: Array = []
	var uv := 0
	var mem := PackedByteArray()
	var subs: Array = []
	var state := 0       # 80139AB0: -1 started, 0 finished (markEFEFinished), 1 idle
	## EfeUvAnim per TMD object (slot D[8], 32 bytes each), null until native 1 touches it:
	## {enable, keys: [[frames, du, dv]], key, uv_frame, frame, num_frames, du, dv}. du/dv is
	## what BTL_offsetEFEPrimitiveUVs has added to every textured prim's UV bytes so far
	## (mod 256); it persists for the slot's life, as the TMD in memory does in DW1.
	var uv_anims: Array = []
	## Native 15 (setEFEModelObjectColor): object -> [r, g, b], written into the leading run of
	## mode 0x2D/0x2F prims (the loop stops advancing at any other prim). Persists too.
	var colors := {}
	## Native 78 (loadClutColors): Vector2i(index, row) of the slot's TIM CLUT -> a 15-bit PS1
	## colour (bit 15 = STP) LoadImage'd over it; every later draw of the TIM uses it. Persists.
	var clut := {}


## Render natives recorded as drawn every frame, without a decoded effect yet (other moves).
const GENERIC_DRAWS := [30, 31, 70, 79, 80, 82, 85, 86, 87]
## playEFESound: these ids loop on a channel until their sub-effect ends (tick 1287-1295).
const LOOP_SOUNDS := [0x12, 0x20, 0x21, 0x22]

var data                                # GameData (digimon sizes, efe.json)
var entities: Array = []                # ENT_MAX entries: fighters (duck-typed) or null
var hit_cb := Callable()                # (victim, pos [x, y, z], slot, sub, caster)
var face_cb := Callable()               # (user, target): native 88 turns the user
## Native 21 (projectPositionToScreen): (pos [x, y, z]) -> [x, y, depth] as DW1 writes them
## (GTE screen pixels from the camera's axis, y down; worldPosToScreenPos's SZ >> 4). Unset,
## nothing is written (no camera). Under DW1's fixed camera (natives 63 / 64) the VM projects
## itself (fixed_project).
var project_cb := Callable()
## Native 63 (setupFixedCamera) until 64 (restoreCameraView): GsSetProjection(0x200) and a view
## from (0, 0, -2000) along +z (battle_effect.c:3008-3038). Draws made meanwhile carry "fixed".
var fixed_cam := false
var viewport_distance := 0x200          # natives 81/94: VIEWPORT_DISTANCE, the map's (battle_view sets it)
var draws: Array = []                   # this frame's draw calls (see the header)
var events: Array = []                  # one-shot spawns since the last take_events()
var slots: Array = []                   # Slot, at most 16 in DW1
var _loops: Array = []                  # looping sound channels (80139AD0, 10): [id, slot, sub]
## BTL_addParticleEmitter's 4 emitters (MAIN_D_80134CCC; null = free): {slot, inst (the instance
## it follows), type, frames, rgb, start, vel, acc, parts: 21 x {d, v, dir, pos}}.
var emitters: Array = [null, null, null, null]
var rng := RandomNumberGenerator.new()
var fx_rng := RandomNumberGenerator.new()   # the particles' directions (visual only)
var _custom := [0, 0x13cc25]            # customRandom state (CUSTOM_RNG_1/2)

var _s: Slot                            # MAIN_D_80134D0C
var _cd4 := 0                           # running slot index
var _cd0 := 0                           # sub index of the tick loop
var _cd8 := 0                           # hit search cursor
var _ce0 := 1
var _ce4 := -1
var _ce8 := 0                           # current sub
var _acc := 0                           # MAIN_D_80134CEC
var _ip := 0
var _op := 0
var _inst := 0                          # EFE_INSTANCE
var _par := 0                           # EFE_PARENT_INSTANCE
var _user := -1                         # MAIN_D_80134EF8 / EF4
var _target := -1
var _stack: Array = []
var _calls: Array = []
var _phase := "start"                    # the scripts running: start (load/start), tick or draw


func _init(game_data, seed_value := 1) -> void:
	data = game_data
	rng.seed = seed_value
	fx_rng.seed = seed_value + 2
	entities.resize(ENT_MAX)


# ---------------------------------------------------------------- slots
## BTL_setupLoadedEFEFile: a slot with a fresh copy of the technique's data; the load script
## runs once. Returns the slot index, or -1 if the technique has no effect file.
func load(tech: int) -> int:
	var e: Dictionary = data.efe_tech(tech)
	if e.is_empty():
		return -1
	var s := Slot.new()
	s.tech = tech
	s.hdr = e["hdr"]
	s.uv = int(e.get("uv", 0))
	s.mem = (e["mem"] as PackedByteArray).duplicate()
	for j in int(s.hdr[11]):
		s.subs.append(Sub.new())
	s.uv_anims.resize(s.uv)
	s.state = 1
	slots.append(s)
	var k := slots.size() - 1
	_enter(k)
	_inst = 0
	_ce8 = 0
	_ce4 = -1
	_run(BASE + int(s.hdr[1]))
	return k


## BTL_startEFE / runEFESlotScript (8005d9fc): the user's technique starts; target -1 = none
## (a confused shot). Returns CE4 (the first instance spawned, -1 none, -2 halted).
func start(k: int, user: int, target: int) -> int:
	if k < 0 or k >= slots.size():
		return -1
	_user = user
	_target = target
	_enter(k)
	_s.state = -1
	_inst = 0
	_ce8 = 0
	_ce4 = -1
	return _run(BASE + int(_s.hdr[0]))


## 8005de70 / BTL_stopEFESubEffect: ends one sub-effect (the user's root on a hit).
func stop_sub(k: int, sub: int) -> void:
	if k < 0 or k >= slots.size() or sub < 0 or sub >= slots[k].subs.size():
		return
	var s: Slot = slots[k]
	var sb: Sub = s.subs[sub]
	sb.inst = 0
	if sb.instance != 0:
		_s = s
		_w32(sb.instance, -1)


## True while any sub-effect of the slot runs.
func running(k: int) -> bool:
	if k < 0 or k >= slots.size():
		return false
	for sb in slots[k].subs:
		if sb.inst != 0:
			return true
	return false


## BTL_tickEFEEngine, then BTL_renderEFEEngine: every live sub-effect's tick script (frame + 1)
## in slot and sub order (a child spawned later in the table runs in the same pass) and the
## slot's UV anims, the looping sounds whose sub-effect ended stop, then every draw script.
## `draws` holds this frame's draw calls afterwards.
func tick() -> void:
	draws = []
	fixed_cam = false
	_phase = "tick"
	for k in slots.size():
		var s: Slot = slots[k]
		if s.state == 0:
			s.state = 1
	for k in slots.size():
		_enter(k)
		var n: int = _s.subs.size()
		_cd0 = 0
		while _cd0 < n:
			var sb: Sub = _s.subs[_cd0]
			if sb.inst != 0:
				_ce8 = _cd0
				_inst = sb.instance
				_par = sb.parent
				_w32(_inst, _r32(_inst) + 1)
				_run(sb.inst)
			_cd0 += 1
		for a in _s.uv_anims:
			_tick_uv(a)
	_tick_emitters()
	for c in _loops.duplicate():
		_enter(c[1])
		var sb: Sub = _s.subs[c[2]]
		if _r32(sb.instance) < 0:
			_loops.erase(c)
			events.append({"kind": "sound_stop", "id": c[0], "slot": c[1], "sub": c[2], "tech": _s.tech})
	_phase = "draw"
	for k in slots.size():
		_enter(k)
		for j in _s.subs.size():
			var sb: Sub = _s.subs[j]
			if sb.inst != 0 and sb.draw != 0:
				_ce8 = j
				_inst = sb.instance
				_par = sb.parent
				_run(sb.draw)
	_phase = "start"
	_draw_emitters()


# ---------------------------------------------------------------- particle emitters
## BTL_addParticleEmitter (battle_effect.c:4158-4195): the first free of the 4 emitters follows
## the current instance; `n` is a distance scale: particles start n * 16 out (n units on screen),
## move n / 8 * 16 a frame and slow by n / 160 * 16 a frame.
func _add_emitter(typ: int, n: int, frames: int, col: Array) -> void:
	var i := emitters.find(null)
	if i < 0:
		return
	var parts := []
	for k in 21:                                     # 20 particles and the free-search sentinel
		parts.append({"d": 0, "v": 0, "dir": [0, 0, 0], "pos": [0, 0, 0]})
	emitters[i] = {"slot": _cd4, "inst": _inst, "type": _wrap(typ, 8), "frames": _wrap(frames, 16),
		"rgb": [col[0] & 0xff, col[1] & 0xff, col[2] & 0xff], "start": _wrap(n * 16, 16),
		"vel": _wrap(_div(n, 8) * 16, 16), "acc": _wrap(_div(n, 160) * 16, 16), "parts": parts}


## BTL_tickParticleEmitters (1674-1736), after the slots' tick scripts: an emitter whose instance
## ended (frame -1) is freed; otherwise a new particle starts at the instance's position in a
## random direction (RotMatrixZYX of three random angles on (0, 0, start)), every live one moves
## in (distance - velocity) and slows, and the emitter dies after `frames` ticks.
func _tick_emitters() -> void:
	for i in emitters.size():
		var e = emitters[i]
		if e == null:
			continue
		_enter(int(e["slot"]))
		if _r32(int(e["inst"])) == -1:
			emitters[i] = null
			continue
		var parts: Array = e["parts"]
		var k := 0
		while int(parts[k]["d"]) > 0:
			k += 1
		if k != 20:
			var pt: Dictionary = parts[k]
			pt["d"] = e["start"]
			pt["v"] = e["vel"]
			var ang := []
			for j in 3:
				ang.append(((fx_rng.randi() & 0x7f) - 0x40) * 64)
			pt["dir"] = _svec(_apply(rot_zyx(ang), [0, 0, int(e["start"])]))
			pt["pos"] = _svec(_vec(int(e["inst"]) + 4))
		for j in 20:
			var pt: Dictionary = parts[j]
			if int(pt["d"]) > 0:
				pt["d"] = _wrap(int(pt["d"]) - int(pt["v"]), 16)
				pt["v"] = _wrap(int(pt["v"]) - int(e["acc"]), 16)
		e["frames"] = _wrap(int(e["frames"]) - 1, 16)
		if int(e["frames"]) <= 0:
			emitters[i] = null


## BTL_renderParticleEmitters (1738-1819), after the draw scripts: each live particle is a
## "particle" draw from a to b along its direction (types 0 / 1 converge as the distance runs
## down, 2 / 3 burst out). The renderer picks DW1's form by depth: a 25-unit dot
## (renderFXParticle) while SZ / 4 < 1000 for even types, else a flat line a-b in the colour.
func _draw_emitters() -> void:
	for e in emitters:
		if e == null:
			continue
		var typ: int = e["type"]
		if typ < 0 or typ > 3:
			continue
		var st: int = e["start"]
		for pt in (e["parts"] as Array).slice(0, 20):
			var dist: int = pt["d"]
			if dist <= 0:
				continue
			var f0: int
			var f1: int
			match typ:
				0:
					f0 = dist << 4
					f1 = (dist + 7) << 4
				1:
					f0 = dist << 4
					f1 = dist << 2
				2:
					f0 = (st - dist) << 4
					f1 = ((st - dist) - 5) << 4
				3:
					f0 = (st - dist) << 4
					f1 = (st - dist) << 2
			f0 = _div(f0, st)
			f1 = _div(f1, st)
			var p: Array = pt["pos"]
			var dv: Array = pt["dir"]
			var a := []
			var b := []
			for j in 3:
				a.append(_wrap(p[j] + ((dv[j] * f0) >> 8), 16))
				b.append(_wrap(p[j] + ((dv[j] * f1) >> 8), 16))
			draws.append({"kind": "particle", "a": a, "b": b, "rgb": e["rgb"], "line": (typ & 1) == 1,
				"slot": e["slot"], "sub": -1, "tech": (slots[int(e["slot"])] as Slot).tech})


## Live instances for the view: [{slot, sub, frame, pos: Vector3i (DW1 units, battle space)}].
func instances() -> Array:
	var out := []
	for k in slots.size():
		var s: Slot = slots[k]
		_s = s
		for j in s.subs.size():
			var sb: Sub = s.subs[j]
			if sb.inst != 0 and sb.instance != 0:
				out.append({"slot": k, "sub": j, "tech": s.tech, "frame": _r32(sb.instance),
					"pos": Vector3i(_r32(sb.instance + 4), _r32(sb.instance + 8), -_r32(sb.instance + 12))})
	return out


## The one-shot spawns recorded since the last call (start scripts included), then cleared.
func take_events() -> Array:
	var out := events
	events = []
	return out


## BTL_tickEFEUVAnimation: a key holds `frames` ticks, then the next key's (du, dv) is added to
## the object's UVs (after the last key the first comes round again); `frame` counts modulo the
## keys' total (getUVAnimTimer).
static func _tick_uv(a) -> void:
	if a == null or (a["keys"] as Array).is_empty():
		return
	var keys: Array = a["keys"]
	a["uv_frame"] += 1
	if a["uv_frame"] >= int(keys[a["key"]][0]):
		a["uv_frame"] = 0
		a["key"] = (int(a["key"]) + 1) % keys.size()
		a["du"] = (int(a["du"]) + int(keys[a["key"]][1])) & 0xff
		a["dv"] = (int(a["dv"]) + int(keys[a["key"]][2])) & 0xff
	if int(a["num_frames"]) != 0:
		a["frame"] = (int(a["frame"]) + 1) % int(a["num_frames"])


func _enter(k: int) -> void:
	_cd4 = k
	_s = slots[k]


# ---------------------------------------------------------------- memory
func _ok(a: int, n: int) -> bool:
	var o := a - BASE
	return o >= 0 and o + n <= _s.mem.size()


func _r32(a: int) -> int:
	return _s.mem.decode_s32(a - BASE) if _ok(a, 4) else 0


func _r16(a: int) -> int:
	return _s.mem.decode_s16(a - BASE) if _ok(a, 2) else 0


func _r8(a: int) -> int:
	return _s.mem.decode_s8(a - BASE) if _ok(a, 1) else 0


func _w32(a: int, v: int) -> void:
	if _ok(a, 4):
		_s.mem.encode_s32(a - BASE, _wrap32(v))


func _w16(a: int, v: int) -> void:
	if _ok(a, 2):
		_s.mem.encode_s16(a - BASE, _wrap(v, 16))


func _w8(a: int, v: int) -> void:
	if _ok(a, 1):
		_s.mem.encode_s8(a - BASE, _wrap(v, 8))


func _vec(a: int) -> Array:
	return [_r32(a), _r32(a + 4), _r32(a + 8)]


func _setvec(a: int, v: Array) -> void:
	for i in 3:
		_w32(a + 4 * i, v[i])


static func _wrap32(v: int) -> int:
	return ((v + 0x80000000) & 0xFFFFFFFF) - 0x80000000


static func _wrap(v: int, bits: int) -> int:
	var half := 1 << (bits - 1)
	return ((v + half) & ((1 << bits) - 1)) - half


## Code is int16 words: _h(k) = the k-th word of the current instruction.
func _h(k: int) -> int:
	return _r16(_ip + 2 * k)


func _var(off: int, kind: int) -> int:
	return _inst + off if kind == 0 else BASE + off


## Operand size from the op's 0xF00 nibble: 0x400 int32, 0x200 int16, else int8.
func _read_sized(a: int, sel: int) -> int:
	if sel == 4:
		return _r32(a)
	if sel == 2:
		return _r16(a)
	return _r8(a)


func _pop() -> int:
	return _stack.pop_back() if not _stack.is_empty() else 0


func _push(v: int) -> void:
	_stack.push_back(_wrap32(v))


# ---------------------------------------------------------------- interpreter
## BTL_runEFEScript.
func _run(script: int) -> int:
	_stack.clear()
	_calls.clear()
	_calls.push_back(0)
	_ip = script
	var steps := 0
	while _ip != 0:
		steps += 1
		if steps > STEP_LIMIT:
			push_warning("EFE %d: script ran away at %x" % [_s.tech, _ip - BASE])
			break
		_op = _h(0)
		match _op & 0xff:
			0:                                           # load immediate
				_acc = _h(1)
				_ip += 6
			1:                                           # load variable
				_acc = _read_sized(_var(_h(1), _h(2)), (_op >> 8) & 0xf)
				_ip += 6
			2:                                           # load rand()
				_acc = rng.randi() & 0x7fff
				_ip += 2
			3:                                           # load D[x + idx * size]
				var idx := _read_sized(_var(_h(3), _h(4)), (_op >> 12) & 0xf)
				var sel := (_op >> 8) & 0xf
				var size := 4 if sel == 4 else (2 if sel == 2 else 1)
				_acc = _read_sized(BASE + _h(1) + idx * size, sel)
				_ip += 10
			4:                                           # var op= acc
				_operate(_var(_h(1), _h(2)), (_op >> 8) & 0xf, (_op >> 12) & 0xf)
				_ip += 6
			5, 6, 8:                                     # stop
				_ip = 0
			7:                                           # if var <cmp> acc goto
				var v := _read_sized(_var(_h(1), _h(2)), (_op >> 8) & 0xf)
				if _compare(v, (_op >> 12) & 0xf):
					_ip = BASE + _h(3)
				else:
					_ip += 10
			9:                                           # goto
				_ip = BASE + _h(1)
			10:                                          # push immediate
				_push(_h(1))
				_ip += 6
			11:                                          # push variable
				_push(_read_sized(_var(_h(1), _h(2)), (_op >> 8) & 0xf))
				_ip += 6
			12:                                          # push address
				_push(_var(_h(1), _h(2)))
				_ip += 6
			13:                                          # call
				_calls.push_back(_ce0)
				_calls.push_back(_ce8)
				_calls.push_back(_ip + 6)
				_ip = BASE + _h(1)
			14:                                          # native
				_ip += 2
				_native((_op >> 8) & 0xff)
			15:
				_return()
			16:                                          # pop -> var (int32)
				_w32(_var(_h(1), _h(2)), _pop())
				_ip += 6
			17:
				_spawn()
			_:
				push_warning("EFE %d: bad op %x at %x" % [_s.tech, _op, _ip - BASE])
				_ip = 0
	if _ce8 < _s.subs.size():
		var sb: Sub = _s.subs[_ce8]
		if sb.instance != 0 and _r32(sb.instance) == -1:
			sb.inst = 0
	return _ce4


func _operate(a: int, row: int, oper: int) -> void:
	var bits := 32 if row == 4 else (16 if row == 2 else 8)
	var v := _r32(a) if bits == 32 else (_r16(a) if bits == 16 else _r8(a))
	var k := _acc
	match oper:
		0: v = k
		1: v = v + k
		2: v = v - k
		3: v = v * k
		4: v = _div(v, k)
		5: v = _mod(v, k)
		6: v = v << (k & 31)
		7: v = v >> (k & 31)
	if bits == 32:
		_w32(a, v)
	elif bits == 16:
		_w16(a, v)
	else:
		_w8(a, v)


func _compare(v: int, c: int) -> bool:
	match c:
		0: return v == _acc
		1: return v != _acc
		2: return v < _acc
		3: return v <= _acc
		4: return v > _acc
		5: return v >= _acc
	return false


## MIPS div: no trap on 0 (quotient -1 / 1, remainder = the dividend); C truncation.
static func _div(a: int, b: int) -> int:
	if b == 0:
		return -1 if a >= 0 else 1
	var q := absi(a) / absi(b)
	return q if (a < 0) == (b < 0) else -q


static func _mod(a: int, b: int) -> int:
	if b == 0:
		return a
	return a - _div(a, b) * b


func _return() -> void:
	_ip = _calls.pop_back() if not _calls.is_empty() else 0
	if _ip != 0:
		_ce8 = _calls.pop_back()
		var sb: Sub = _s.subs[_ce8]
		_inst = sb.instance
		_par = sb.parent
		_ce0 = _calls.pop_back()


## BTL_spawnEFESubEffect: claims a free instance (frame -1) in the array and the next free
## sub-effect from the current one; the root gets the user and target, a child its parent's.
func _spawn() -> void:
	_ce0 = 1
	var n := _h(1)
	var p := BASE + _h(2)
	var stride := _h(4)
	var i := 0
	while i < n:
		if _r32(p) == -1:
			break
		p += stride
		i += 1
	if i == n:
		_return()
		return
	if _ce4 == -1:
		_ce4 = i
	var cur: Sub = _s.subs[_ce8]
	var src := cur.src
	var tgt := cur.tgt
	while (_s.subs[_ce8] as Sub).inst != 0:
		_ce8 += 1
		if _ce8 >= _s.subs.size():
			_ce8 = _s.subs.size() - 1
			_return()
			return
	_par = _inst
	_inst = p
	var sb: Sub = _s.subs[_ce8]
	sb.instance = p
	sb.parent = _par
	if _par == 0:
		sb.src = _user
		sb.tgt = _target
	else:
		sb.src = src
		sb.tgt = tgt
	_ip += 12


# ---------------------------------------------------------------- entities
func _ent(i: int):
	return entities[i] if i >= 0 and i < ENT_MAX else null


## The fighter's position in DW1's frame: battle (x, y) -> (x, 0, -y) (the header).
func _loc(i: int) -> Array:
	var e = _ent(i)
	if e == null:
		return [0, 0, 0]
	return [int(e.pos.x), 0, -int(e.pos.y)]


## DW1 facing (4096 = 360°, forward = Ry(a) (0, 0, -1)): the battle's facing f faces (sin f,
## cos f) in battle space, (sin f, -cos f) in DW1's frame, which is a = -f.
func _rot_y(i: int) -> int:
	var e = _ent(i)
	if e == null:
		return 0
	return (-roundi(e.facing * 4096.0 / TAU)) & 0xfff


func _type(i: int) -> int:
	var e = _ent(i)
	return int(e.id) if e != null else 0


func _radius(i: int) -> int:
	return int(data.digimon[_type(i)]["radius"])


func _height(i: int) -> int:
	return int(data.digimon[_type(i)]["height"])


func _is_hit(i: int) -> bool:
	var e = _ent(i)
	return e == null or bool(e.is_hit)


func _set_hit(i: int) -> void:
	var e = _ent(i)
	if e != null:
		e.is_hit = true


func _on_map(i: int) -> bool:
	var e = _ent(i)
	return e != null and bool(e.on_map)


func _on_screen(i: int) -> bool:
	var e = _ent(i)
	return e != null and bool(e.on_screen)


func _hp(i: int) -> int:
	var e = _ent(i)
	return int(e.hp) if e != null else 0


## getOriginalType: a story NPC type uses its regular Digimon's effects (ORIGINAL_TYPE).
func original_type(t: int) -> int:
	if t < 0 or t > 0xb0:
		return -1
	var o: int = data.efe_original_type(t)
	return t if o < 0 else o


## calculateBoneMatrix (800d9a88): a bone's world [position, rotation], turned by the facing:
## its pose at the current frame of the technique clip the fighter plays (dw1_efe.py clips),
## else the idle pose; bone 0, or a bone the model doesn't have, is the fighter's transform.
func _bone(i: int, b: int) -> Array:
	var l := _loc(i)
	var ry := _ry(_rot_y(i))
	var bones: Array = data.efe_bones(_type(i))
	if b <= 0 or b >= bones.size():
		return [l, ry]
	var e: Array = bones[b]
	var f = _ent(i)
	if f != null and int(f.clip_anim) >= 0:
		var frames: Array = data.efe_clip(_type(i), int(f.clip_anim)).get("bones", {}).get(str(b), [])
		if not frames.is_empty():
			e = frames[clampi(f.clip_frame() - 1, 0, frames.size() - 1)]
	var m := [[e[3], e[4], e[5]], [e[6], e[7], e[8]], [e[9], e[10], e[11]]]
	var r := _apply(ry, [e[0], e[1], e[2]])
	return [[l[0] + r[0], l[1] + r[1], l[2] + r[2]], _mul(ry, m)]


func _bone_pos(i: int, b: int) -> Array:
	return _bone(i, b)[0]


## For HitFx: entity i's position and bone b's (DW1's frame), its Digimon type (-1: none).
func loc(i: int) -> Array:
	return _loc(i)


func bone_pos(i: int, b: int) -> Array:
	return _bone_pos(i, b)


func type_of(i: int) -> int:
	return _type(i) if _ent(i) != null else -1


func _hit(victim: int, pos: Array, sub: int) -> void:
	_set_hit(victim)
	if hit_cb.is_valid():
		hit_cb.call(victim, [_wrap(pos[0], 16), _wrap(pos[1], 16), -_wrap(pos[2], 16)], _cd4, sub,   # battle space
			_s.subs[_ce8].src)


# ---------------------------------------------------------------- PSX math
static func rsin(a: int) -> int:
	return roundi(sin((a & 0xfff) * TAU / 4096.0) * 4096.0)


static func rcos(a: int) -> int:
	return rsin(a + 1024)


## DW1's _sin / _cos: a 512-step circle (SydPatches Math.cpp).
## _sin (main.c math, SLUS 800A3704): a quarter-wave table of 129 halfwords at 0x80122480,
## floor(sin x 4096) (EFE-3E-1: rounding put 65 entries 1 high), mirrored into 512 steps.
static var _sin_table: PackedInt32Array

static func sin512(a: int) -> int:
	if _sin_table.is_empty():
		for i in 129:
			_sin_table.append(floori(sin(i * TAU / 512.0) * 4096.0 + 1e-9))
	a &= 0x1ff
	if a < 128:
		return _sin_table[a]
	if a < 256:
		return _sin_table[256 - a]
	if a < 384:
		return -_sin_table[a - 256]
	return -_sin_table[512 - a]


static func cos512(a: int) -> int:
	return sin512(a + 0x80)


static func ratan2(y: int, x: int) -> int:
	return roundi(atan2(y, x) * 4096.0 / TAU)


## DW1's _atan(dy, dx) (SydPatches Math.cpp): the angle from +dy toward +dx, + 0x800.
static func atan_dw(dy: int, dx: int) -> int:
	return (roundi(atan2(dx, dy) * 4096.0 / TAU) + 2048) & 0xfff


static func _rx(a: int) -> Array:
	var c := rcos(a)
	var s := rsin(a)
	return [[4096, 0, 0], [0, c, -s], [0, s, c]]


static func _ry(a: int) -> Array:
	var c := rcos(a)
	var s := rsin(a)
	return [[c, 0, s], [0, 4096, 0], [-s, 0, c]]


static func _rz(a: int) -> Array:
	var c := rcos(a)
	var s := rsin(a)
	return [[c, -s, 0], [s, c, 0], [0, 0, 4096]]


## MulMatrix0: (a . b) >> 12.
static func _mul(a: Array, b: Array) -> Array:
	var m := [[0, 0, 0], [0, 0, 0], [0, 0, 0]]
	for i in 3:
		for j in 3:
			var t := 0
			for k in 3:
				t += int(a[i][k]) * int(b[k][j])
			m[i][j] = t >> 12
	return m


## ApplyMatrix: (m . v) >> 12.
static func _apply(m: Array, v: Array) -> Array:
	var out := [0, 0, 0]
	for i in 3:
		var t := 0
		for k in 3:
			t += int(m[i][k]) * int(v[k])
		out[i] = t >> 12
	return out


## worldPosToScreenPos under setupFixedCamera: the view from (0, 0, -2000) along +z with no
## rotation, H = 0x200 (GTE OFX / OFY 0: pixels from the screen centre, y down), the depth
## SZ >> 4 as native 21 writes it. [0, 0, 0] behind the eye.
static func fixed_project(p: Array) -> Array:
	var sz: int = int(p[2]) + FIXED_EYE_Z
	if sz <= 0:
		return [0, 0, 0]
	return [int(p[0]) * FIXED_VPD / sz, int(p[1]) * FIXED_VPD / sz, sz >> 4]


const FIXED_VPD := 0x200
const FIXED_EYE_Z := 0x7d0


## libgte: RotMatrix = Rx.Ry.Rz (tools/dw1_model_size.py), ZYX = Rz.Ry.Rx, YXZ = Ry.Rx.Rz.
static func rot_zyx(r: Array) -> Array:
	return _mul(_mul(_rz(r[2]), _ry(r[1])), _rx(r[0]))


## RotMatrix (drawTMD): Rx.Ry.Rz.
static func rot_xyz(r: Array) -> Array:
	return _mul(_mul(_rx(r[0]), _ry(r[1])), _rz(r[2]))


static func rot_yxz(r: Array) -> Array:
	return _mul(_mul(_ry(r[1]), _rx(r[0])), _rz(r[2]))


static func _svec(v: Array) -> Array:
	return [_wrap(v[0], 16), _wrap(v[1], 16), _wrap(v[2], 16)]


static func _signed12(a: int) -> int:
	a &= 0xfff
	return a - 0x1000 if a >= 0x800 else a


## matrixToEuler1 (graphics2.c).
static func euler1(m: Array) -> Array:
	if m[2][2] == 0 and m[0][0] == 0:
		return [ratan2(m[2][1], m[1][1]), 0x400 if m[0][2] > 0 else -0x400, 0]
	var vx := ratan2(-m[1][2], m[2][2])
	var vz := ratan2(-m[0][1], m[0][0])
	var sx := rsin(vx)
	var cx := rcos(vx)
	var sz := rsin(vz)
	var cz := rcos(vz)
	var mx := maxi(maxi(absi(sx), absi(cx)), maxi(absi(sz), absi(cz)))
	var value := 0
	if mx == absi(sx):
		value = _div(m[1][2] * -0x1000, sx)
	elif mx == absi(cx):
		value = _div(m[2][2] << 12, cx)
	elif mx == absi(sz):
		value = _div(m[0][1] * -0x1000, sz)
	else:
		value = _div(m[0][0] << 12, cz)
	return [vx, ratan2(m[0][2], value), vz]


## matrixToEuler2 (graphics2.c).
static func euler2(m: Array) -> Array:
	if m[2][2] == 0 and m[0][2] == 0:
		return [-0x400 if m[1][2] > 0 else 0x400, ratan2(-m[2][0], m[0][0]), 0]
	var vy := ratan2(m[0][2], m[2][2])
	var vz := ratan2(m[1][0], m[1][1])
	var sy := rsin(vy)
	var cy := rcos(vy)
	var sz := rsin(vz)
	var cz := rcos(vz)
	var mx := maxi(maxi(absi(sy), absi(cy)), maxi(absi(sz), absi(cz)))
	var value := 0
	if mx == absi(sy):
		value = _div(m[0][2] << 12, sy)
	elif mx == absi(cy):
		value = _div(m[2][2] << 12, cy)
	elif mx == absi(sz):
		value = _div(m[1][0] << 12, sz)
	else:
		value = _div(m[1][1] << 12, cz)
	return [ratan2(-m[1][2], value), vy, vz]


static func distance(x: int, y: int, z: int) -> int:
	return int(sqrt(float(x) * x + float(y) * y + float(z) * z))


## lerp (SydPatches Math.cpp, vanilla quirks kept).
static func lerp_dw(start: int, end: int, t0: int, t1: int, t: int) -> int:
	var diff := end - start
	var td := t1 - t0
	if td == 0:
		return 0
	var val := _div(diff * (t - t0), td)
	if diff < 0:
		val = _mod(val, diff - 1)
		if val > 0:
			val += diff
	else:
		val = _mod(val, diff + 1)
		if val < 0:
			val += diff
	return start + val


## customRandom (800e4c1c; SydPatches Matrix.cpp has the generator, its range is off by one).
func _custom_random(lo: int, hi: int) -> int:
	if lo == hi:
		return hi
	if lo > hi:
		var t := lo
		lo = hi
		hi = t
	_custom[0] = (_custom[0] * 1103515821 + 12345) & 0xFFFFFFFF
	_custom[1] = (_custom[1] * 1103515821 + 12345) & 0xFFFFFFFF
	var r: int = ((_custom[0] >> 16) | (_custom[1] << 16)) & 0xFFFFFFFF
	return lo + r % (hi - lo + 1)                        # 800e4c1c: [lo, hi] (BTL-89)


# ---------------------------------------------------------------- natives
func _native(n: int) -> void:
	var sb: Sub = _s.subs[_ce8]
	match n:
		0:                                               # checkTechCompatibility
			var p := _pop()
			var t := original_type(_type(sb.src))
			while _r16(p) != t:
				if _r16(p) < 0:
					_ce4 = -1
					_ip = 0
					break
				p += 10
			sb.bone = p + 2
		1:                                               # initializeUVAnim
			var ptr := _pop()
			var val := _pop()
			var idx := _pop()
			if idx < 0 or idx >= _s.uv:
				_ce4 = -2
				_ip = 0
				return
			if _s.uv_anims[idx] == null:
				_s.uv_anims[idx] = {"enable": 0, "keys": [], "key": 0, "uv_frame": 0, "frame": 0,
					"num_frames": 0, "du": 0, "dv": 0}
			var a: Dictionary = _s.uv_anims[idx]
			a["enable"] = _wrap(val, 16)
			if ptr == -1:
				return
			var keys := []
			var total := 0
			for i in _wrap(_r32(ptr), 16):               # numKeyframes is an int16
				var kf := [_r16(ptr + 4 + 4 * i), _r8(ptr + 6 + 4 * i), _r8(ptr + 7 + 4 * i)]
				keys.append(kf)
				total += int(kf[0])
			a["keys"] = keys
			a["key"] = 0
			a["uv_frame"] = 0
			a["frame"] = 1
			a["num_frames"] = _wrap(total, 16)
		3, 77:                                           # drawTMD (RotMatrix XYZ), drawTMDYXZ
			var sc := _vec(_pop())
			var obj := _pop()
			var a = _s.uv_anims[obj] if obj >= 0 and obj < _s.uv_anims.size() else null
			_draw({"kind": "tmd", "obj": obj, "scale": sc, "pos": _vec(_inst + 4), "rot": _vec(_inst + 0x10),
				"order": "yxz" if n == 77 else "xyz", "uv": [0, 0] if a == null else [a["du"], a["dv"]],
				"color": _s.colors.get(obj)})
		4:                                               # renderCenteredSprite: additive, pivot centred
			var y := _pop()
			var x := _pop()
			_push(x + 1)
			_push(y + 1)
			_push(_div(x, 2))
			_push(_div(y, 2))
			_push(0)
			_push(5)
			_push(0)
			_sprite()
		15:                                              # setEFEModelObjectColor
			var col := _vec(_pop())
			_s.colors[_pop()] = [col[0] & 0xff, col[1] & 0xff, col[2] & 0xff]
		16:                                              # addParticleEmitter
			var frames := _pop()
			var col := _vec(_pop())
			var cnt := _pop()
			var typ := _pop()
			if _inst != 0:                               # NULL (no instance yet): DW1's slot stays free
				_add_emitter(typ, cnt, frames, col)
				_event({"kind": "emitter", "type": typ, "n": cnt, "frames": frames, "rgb": col,
					"pos": _vec(_inst + 4)})
		18:                                              # EFECreateFlash
			var cmax := _vec(_pop())
			var cmin := _vec(_pop())
			var smax := _pop()
			var smin := _pop()
			var tmax := _pop()
			var depth := _pop()
			var wp := _vec(_pop())
			_event({"kind": "flash", "mode": _pop(), "pos": wp, "depth": depth, "frames": tmax,
				"scale": [smin, smax], "rgb": [cmin, cmax]})
		19:                                              # addCloudEffect
			var v := _vec(_pop())
			_event({"kind": "cloud", "pos": [_wrap(v[0], 16), _wrap(v[1], 16), _wrap(v[2], 16)]})
		20:                                              # renderScreenSprite: additive, pixels
			var a := []
			for i in 13:
				a.append(_pop())
			# pixels from the screen centre; flip < 0: pinned to the screen (the drawing offset's
			# shake is taken back out), CLUT row -flip; else the row is flip
			_draw({"kind": "screen_sprite", "pos": [a[12], a[11]], "uv": [a[10], a[9]], "size": [a[8], a[7]],
				"pivot": [a[6], a[5]], "rot": a[4], "depth": a[3], "scale": [a[2], a[1]],
				"row": absi(a[0]), "pinned": a[0] < 0})
		21:                                              # projectPositionToScreen
			var depth_out := _pop()
			var y_out := _pop()
			var x_out := _pop()
			var src := _vec(_pop())
			if fixed_cam:
				var r := fixed_project(src)
				_w32(x_out, r[0])
				_w32(y_out, r[1])
				_w32(depth_out, r[2])
			elif project_cb.is_valid():
				var r: Array = project_cb.call(src)
				_w32(x_out, int(r[0]))
				_w32(y_out, int(r[1]))
				_w32(depth_out, int(r[2]))
		22:                                              # renderParticleFlashSprite: quarter x4, additive
			var row := _pop()
			var depth := _pop()
			var scale := _wrap(_pop(), 16)
			var szy := _pop()
			var szx := _pop()
			var v := _pop()
			var u := _pop()
			var y := _pop()
			_draw({"kind": "flash_sprite", "pos": [_pop(), y], "uv": [u & 0xff, v & 0xff], "size": [szx, szy],
				"scale": scale, "depth": depth, "row": row})
		24:                                              # renderProjectedSprite
			_sprite()
		27:                                              # addSourceEntityParticleFX
			_event({"kind": "entity_fx", "entity": sb.src, "timer": _pop()})
		28:                                              # playEFESound
			var id := _pop()
			if id < 0:
				return
			var loop := id in LOOP_SOUNDS
			if loop:
				if _loops.size() >= 10:
					return
				_loops.append([id, _cd4, _ce8])
			_event({"kind": "sound", "id": id, "loop": loop})
		2:                                               # initializeSubEffectInstructions
			var a := _pop()
			var b := _pop()
			_w32(_inst, 0)
			sb.inst = b
			sb.draw = a
		5:                                               # initializeEFETransform
			if _par == 0:
				_bone_transform(sb, false)
			else:
				for i in 6:
					_w32(_inst + 4 + 4 * i, _r32(_par + 4 + 4 * i))
		6:                                               # box, default sub index
			_push(-1)
			_box()
		7:                                               # EFERotateVector: ZYX
			var vp := _pop()
			var rp := _pop()
			var out := _svec(_apply(rot_zyx(_svec(_vec(rp))), _svec(_vec(vp))))
			_setvec(vp, out)
		8, 32:                                           # setTransformTo{Target,Source}Bone
			var r := _pop() if n == 8 else 25
			var idx := _pop()
			var who := sb.tgt if n == 8 else sb.src
			if who < 0:
				who = sb.src
			var ry := _rot_y(who)
			_setvec(_inst + 4, _bone_pos(who, idx))
			_setvec(_inst + 0x10, [0, ry, 0])
			var s1 := sin512(-(ry >> 3))
			var s2 := sin512(-(((ry >> 3) + 0x80) & 0x1ff))
			_w32(_inst + 4, _r32(_inst + 4) + ((r * s1) >> 12))
			_w32(_inst + 12, _r32(_inst + 12) + ((r * s2) >> 12))
		9:                                               # addAttackObjectToTarget
			if sb.tgt < 0 or _is_hit(sb.tgt):
				return
			_hit(sb.tgt, _vec(_inst + 4), _cd0)
		10:                                              # getScatteredSpawnPosition
			var r := _pop()
			var out := _pop()
			var v := _bone_pos(sb.src, _r16(sb.bone)) if _par == 0 else _vec(_par + 4)
			if r > 0:
				for i in 3:
					v[i] += _mod(rng.randi() & 0x7fff, r) - (r >> 1)
			_setvec(out, v)
		11:
			_pop()
			_pop()
		12:                                              # interpolateVector
			var out := _pop()
			var t := _pop()
			var t1 := _pop()
			var t0 := _pop()
			var b := _vec(_pop())
			var a := _vec(_pop())
			_setvec(out, [lerp_dw(a[0], b[0], t0, t1, t), lerp_dw(a[1], b[1], t0, t1, t),
				lerp_dw(a[2], b[2], t0, t1, t)])
		13:                                              # steerTransformTowardPoint
			_steer()
		14:                                              # copyTargetEntityPosition
			_setvec(_pop(), _loc(sb.tgt if sb.tgt >= 0 else sb.src))
		17:                                              # selectNextTargetEntity
			var out := _pop()
			while _ce0 < ENT_MAX:
				var e = _ent(_ce0)
				if e != null and _ce0 != sb.src and _on_map(_ce0) and _on_screen(_ce0) and _hp(_ce0) > 0:
					break
				_ce0 += 1
			if _ce0 >= ENT_MAX:
				_w32(out, -1)
				return
			sb.tgt = _ce0
			_w32(out, _ce0)
			_ce0 += 1
		23, 37:                                          # get{Target,Source}DigimonSize
			var who := sb.tgt if n == 23 and sb.tgt >= 0 else sb.src
			_setvec(_pop(), [_radius(who), _height(who), _radius(who)])
		25:                                              # calculatePolarOffset
			var r := _pop()
			var ang := _pop()
			var out := _pop()
			_w32(out + 8, (r * sin512(0x80 - ang)) >> 12)
			_w32(out, (r * cos512(0x80 - ang)) >> 12)
		26:                                              # copyFromParentTransform
			var size := _pop()
			var off := _pop()
			var dst := _pop()
			_copy(_par + off, dst, size)
		29:                                              # setTransformToBoneOffset
			_bone_transform(sb, false)
		33:                                              # rotateTransformTowardPoint
			var p := _vec(_pop())
			var ang := (-(atan_dw(p[0] - _r32(_inst + 4), p[2] - _r32(_inst + 12)) - 0x400)) & 0xfff
			_w32(_inst + 0x14, ang)
		34:                                              # checkTargetCollision
			_target_collision(sb)
		35:                                              # getUVAnimTimer: the anim's frame
			var idx := _pop()
			var a = _s.uv_anims[idx] if idx >= 0 and idx < _s.uv_anims.size() else null
			_w32(_pop(), 0 if a == null else int(a["frame"]))
		36:                                              # applyHomingMovement
			_homing()
		38, 39:                                          # calculateSine / Cosine
			var out := _pop()
			var scale := _pop()
			var ang := _pop()
			_w32(out, (scale * (rsin(ang) if n == 38 else rcos(ang))) >> 12)
		40:                                              # interpolateValue
			var end := _pop()
			var st := _pop()
			var t := _pop()
			var hi := _pop()
			var lo := _pop()
			var out := _pop()
			if hi < lo:
				var tmp := lo
				lo = hi
				hi = tmp
			t = clampi(t, lo, hi)
			_w32(out, st if lo == hi else st + _div((t - lo) * (end - st), hi - lo))
		41:                                              # getRandomInRange
			var a := _pop()
			var b := _pop()
			_w32(_pop(), _custom_random(b, a))
		43:                                              # getVectorEulerAngles
			var v := _vec(_pop())
			var out := _pop()
			var vy := _signed12(ratan2(v[0], v[2]))
			var vx := _signed12(-ratan2(v[1], distance(v[0], 0, v[2])))
			_setvec(out, [vx, vy, 0])
		44:                                              # findHitEntity
			_find_hit()
		45, 58:                                          # normalizeRotationAngles(2)
			var v := _pop()
			var out := _pop()
			_setvec(out, euler1(rot_yxz(_svec(_vec(v)))))
		46:                                              # setTargetToHitEntity
			if _cd8 >= 0:
				sb.tgt = _cd8
		47:                                              # getVectorLength
			var v := _vec(_pop())
			_w32(_pop(), distance(v[0], v[1], v[2]))
		48, 49, 50, 51, 52, 53, 54:                      # vector ops
			var b := _vec(_pop())
			var ap := _pop()
			var a := _vec(ap)
			for i in 3:
				match n:
					48: a[i] = b[i]
					49: a[i] += b[i]
					50: a[i] -= b[i]
					51: a[i] *= b[i]
					52: a[i] = _div(a[i], b[i])
					53: a[i] &= b[i]
					54: a[i] >>= (b[i] & 31)
			_setvec(ap, a)
		55:                                              # centerTransformOnEntities
			var sum := [0, 0, 0]
			var count := 0
			for i in range(1, ENT_MAX):
				if _ent(i) == null or i == sb.src or not _on_map(i):
					continue
				count += 1
				var l := _loc(i)
				for c in 3:
					sum[c] += l[c]
			for c in 3:
				sum[c] = _div(sum[c], count)
			_setvec(_inst + 4, sum)
			_setvec(_inst + 0x10, [0, 0, 0])
		56, 62:                                          # get{Target,Source}BoneTransform
			var rot_out := _pop()
			var pos_out := _pop()
			var idx := _pop()
			var who := sb.tgt if n == 56 and sb.tgt >= 0 else sb.src
			var bm := _bone(who, idx)
			_setvec(rot_out, euler2(bm[1]))
			_setvec(pos_out, bm[0])
		57:                                              # rotateVectorByAngles: YXZ, LV
			var v := _pop()
			var w := _pop()
			_setvec(v, _apply(rot_yxz(_svec(_vec(w))), _vec(v)))
		59:                                              # combineRotations
			var bp := _pop()
			var ap := _pop()
			var r1 := _svec(_vec(ap))
			var r2 := _svec(_vec(bp))
			if r2 != [0, 0, 0]:
				r1 = euler2(_mul(rot_yxz(r1), rot_yxz(r2)))
			_setvec(ap, r1)
		61:                                              # copyToParentTransform
			var size := _pop()
			var off := _pop()
			var src := _pop()
			_copy(src, _par + off, size)
		69:                                              # setTransformToBoneMatrix
			_bone_transform(sb, true)
		71, 72, 73:                                      # vector by scalar
			var k := _pop()
			var vp := _pop()
			var v := _vec(vp)
			for i in 3:
				match n:
					71: v[i] *= k
					72: v[i] = _div(v[i], k)
					73: v[i] &= k
			_setvec(vp, v)
		74:                                              # convertToViewSpace (no camera here)
			var rot_in := _vec(_pop())
			var trans := _vec(_pop())
			var out2 := _pop()
			var out1 := _pop()
			_setvec(out1, trans)
			_setvec(out2, rot_in)
		75:                                              # selectRandomTargetEntity
			_random_target(sb)
		78:                                              # loadClutColors: 4 uint16 (r, g, b, stp) each
			var src := _pop()
			var count := _pop()
			var x := _pop()
			var y := _pop()
			if count > 0 and count <= 16:
				for i in count:
					var p := src + 8 * i
					var c := (_r16(p) + (_r16(p + 2) << 5) + (_r16(p + 4) << 10) + (_r16(p + 6) << 15)) & 0xffff
					_s.clut[Vector2i(x + i, y)] = c
		83:                                              # initializeRibbonPoints: 10 SVECTORs
			var q := _pop()
			for i in 10:
				_w16(q + 8 * i, -0x708 + 0x190 * i)
				_w16(q + 8 * i + 2, _custom_random(-0x96, 0x96))
				_w16(q + 8 * i + 6, _custom_random(-0x1e, 0x1e))
				_w16(q + 8 * i + 4, 0)
		84:                                              # tickRibbonPoints: y, z drift, clamped +-150
			var q := _pop()
			var fr := _r32(_inst)
			for i in 10:
				var a := q + 8 * i
				if _mod(fr + i * 8, 10) == 0:
					_w16(a + 6, _custom_random(-0xf, 0xf))
				var pad := _r16(a + 6)
				_w16(a + 2, clampi(_wrap(_r16(a + 2) + pad, 16), -0x96, 0x96))
				_w16(a + 4, clampi(_wrap(_r16(a + 4) + pad, 16), -0x96, 0x96))
		81, 94:                                          # viewport distance
			_w32(_pop(), viewport_distance)
		60:                                              # renderEFELine: screen pixels
			var flags := _pop()
			var depth := _pop()
			var col := _vec(_pop())
			var y1 := _pop()
			var x1 := _pop()
			var y0 := _pop()
			# 0x20: drawn 4 times, offset, at 50% and additive (a glow)
			_draw({"kind": "line", "p0": [_pop(), y0], "p1": [x1, y1], "rgb": col, "depth": depth,
				"glow": flags & 0x20 != 0})
		63:                                              # setupFixedCamera (vpd 0x200, eye z -2000)
			_draw({"kind": "fixed_camera"})
			fixed_cam = true
		64:                                              # restoreCameraView
			fixed_cam = false
			_draw({"kind": "restore_camera"})
		65:                                              # render2DTexturedQuad: screen pixels
			var semi := _pop()
			var row := _pop()
			var dv := _pop()
			var du := _pop()
			var v0 := _pop()
			var u0 := _pop()
			var col := _vec(_pop())
			var depth := _pop()
			var a := []
			for i in 4:
				a.push_front(_pop())
			var pts := []
			if semi < 0:                                 # four pointers to [x, y]
				semi = -semi & 0xffff
				for p in a:
					pts.append([_r32(p), _r32(p + 4)])
			else:                                        # x, y, w, h
				pts = [[a[0], a[1]], [a[0] + a[2], a[1]], [a[0], a[1] + a[3]], [a[0] + a[2], a[1] + a[3]]]
			_draw({"kind": "quad2d", "pts": pts, "uv": [u0, v0], "size": [du, dv], "row": row, "rgb": col,
				"depth": depth, "semi": semi != 0, "abr": (semi >> 5) & 3})
		66:                                              # renderWireframeGrid: lines in the world
			var a := []
			for i in 7:
				a.append(_pop())
			var col := _vec(_pop())
			var rot := _vec(_pop())
			_draw({"kind": "grid", "base": _vec(_pop()), "rot": rot, "rgb": col, "x": [a[6], a[5]], "nx": a[4],
				"z": [a[3], a[2]], "nz": a[1], "y": a[0]})
		68:                                              # renderWireframeBox: ZYX by the instance
			var col := _vec(_pop())
			var ext := _vec(_pop())
			_draw({"kind": "wirebox", "base": _vec(_pop()), "ext": ext, "rgb": col, "rot": _vec(_inst + 0x10)})
		92:                                              # renderScreenFade: subtractive, full screen
			_draw({"kind": "fade", "c": _pop()})
		93:                                              # disableMapLayer (this frame)
			_draw({"kind": "map_off"})
		88:                                              # faceTargetEntity
			if sb.tgt >= 0 and face_cb.is_valid():
				face_cb.call(sb.src, sb.tgt)
		89:                                              # applyLineAttackHit
			_line_hit(sb)
		90:                                              # applyRadiusAttackHit
			_radius_hit(sb)
		91:                                              # applyBoxAttackHit
			_box()
		95:                                              # markEFEFinished
			_s.state = 0
		96:                                              # isTargetUnhit
			_w32(_pop(), 1 if sb.tgt >= 0 and not _is_hit(sb.tgt) else 0)
		_:
			var args := []
			for i in (POPS[n] if n < POPS.size() else 0):
				args.append(_pop())
			if n in GENERIC_DRAWS:
				_draw({"kind": "native", "n": n, "args": args})


func _draw(d: Dictionary) -> void:
	if fixed_cam:
		d["fixed"] = true
	d["slot"] = _cd4
	d["sub"] = _ce8
	d["tech"] = _s.tech
	draws.append(d)


func _event(d: Dictionary) -> void:
	d["phase"] = _phase
	d["slot"] = _cd4
	d["sub"] = _ce8
	d["tech"] = _s.tech
	events.append(d)


## renderProjectedSprite (8006C114): a GsSPRITE billboard at a world point, from the move's TIM.
## attr << 28: 0-3 opaque, 4 = 50/50, 5 = additive, 6 = subtractive, 7 = +25%; rot in degrees;
## scale 4096 = 1 before projection (DW1 size: w * scale / 32 units); row = CLUT row offset.
func _sprite() -> void:
	var row := _pop()
	var attr := _pop()
	var rot := _pop()
	var my := _pop()
	var mx := _pop()
	var h := _pop()
	var w := _pop()
	var v := _pop()
	var u := _pop()
	var sy := _pop()
	var sx := _pop()
	var col := _vec(_pop())
	for c in 3:
		col[c] = int(col[c]) & 0xff                  # GsSPRITE r, g, b are bytes: 256 draws as 0 (EFE-3B-4)
	_draw({"kind": "sprite", "pos": _vec(_pop()), "rgb": col, "scale": [sx, sy], "uv": [u & 0xff, v & 0xff],
		"size": [w, h], "pivot": [mx, my], "rot": rot, "attr": attr & 7, "row": row})


func _copy(src: int, dst: int, size: int) -> void:
	match size:
		0xc:
			_setvec(dst, _vec(src))
		8:
			_w32(dst, _r32(src))
			_w32(dst + 4, _r32(src + 4))
		4:
			_w32(dst, _r32(src))
		2:
			_w16(dst, _r16(src))
		1:
			_w8(dst, _r8(src))


## setTransformToBoneOffset / setTransformToBoneMatrix: the bone's position plus the
## compatibility offset turned by the bone (BTL-86); rotation = the user's facing, or the
## bone's (matrixToEuler2) for the matrix variant.
func _bone_transform(sb: Sub, euler: bool) -> void:
	var b := _r16(sb.bone) if sb.bone != 0 else 0
	var off := [_r16(sb.bone + 2), _r16(sb.bone + 4), _r16(sb.bone + 6)] if sb.bone != 0 else [0, 0, 0]
	var bm := _bone(sb.src, b)
	var o := _apply(bm[1], _svec(off))
	var t: Array = bm[0]
	_setvec(_inst + 4, [_wrap(o[0], 16) + t[0], _wrap(o[1], 16) + t[1], _wrap(o[2], 16) + t[2]])
	_setvec(_inst + 0x10, euler2(bm[1]) if euler else [0, _rot_y(sb.src), 0])


func _steer() -> void:
	var turn := _pop()
	var speed := _pop()
	var target := _vec(_pop())
	var px := _r32(_inst + 4)
	var pz := _r32(_inst + 12)
	var o := _svec(_apply(rot_zyx([0, -_r32(_inst + 0x14), 0]), _svec([target[0] - px, 0, target[2] - pz])))
	var d := (-(atan_dw(o[0], o[2]) - 0x400)) & 0xfff
	if d >= 0x801:
		d -= 0x1000
	if d > 0:
		if d < turn:
			turn = d
	elif -d < turn:
		turn = d
	else:
		turn = -turn
	_w32(_inst + 0x14, _r32(_inst + 0x14) + turn)
	var rot := [_r32(_inst + 0x10), _r32(_inst + 0x14), _r32(_inst + 0x18)]
	var v := _svec(_apply(rot_zyx(_svec(rot)), _svec([0, 0, -speed * 8])))
	_w32(_inst + 4, px + (v[0] >> 3))
	_w32(_inst + 8, _r32(_inst + 8) + (v[1] >> 3))
	_w32(_inst + 12, pz + (v[2] >> 3))


func _homing() -> void:
	var limit := _pop()
	var speed_p := _pop()
	_pop()
	var max_speed := _pop()
	var min_speed := _pop()
	var target := _vec(_pop())
	var pos := _vec(_inst + 4)
	var d := _svec([target[0] - pos[0], target[1] - pos[1], target[2] - pos[2]])
	var o := _svec(_apply(rot_zyx([0, -_r32(_inst + 0x14), 0]), d))
	var ang := (-(atan_dw(o[0], o[2]) - 0x400)) & 0xfff
	if ang >= 0x801:
		ang -= 0x1000
	var dy := ang if absi(ang) < limit else (limit if ang > 0 else -limit)
	_w32(_inst + 0x14, _r32(_inst + 0x14) + dy)
	ang = (atan_dw(o[1], o[2]) - 0x400 - _r32(_inst + 0x18)) & 0xfff
	if ang >= 0x801:
		ang -= 0x1000
	var dp := ang if absi(ang) < limit else (limit if ang > 0 else -limit)
	_w32(_inst + 0x18, _r32(_inst + 0x18) + dp)
	var w := _r32(_inst + 0x18)
	if (w & 0xfff) >= 0x400 and (w & 0xfff) < 0xc00:
		_w32(_inst + 0x18, 0x800 - w)
	var speed := _r32(speed_p)
	if limit * 40 / 100 >= absi(dp) + absi(dy):
		speed = mini(speed * 130 / 100, max_speed)
	else:
		speed = maxi(speed * 82 / 100, min_speed)
	_w32(speed_p, speed)
	var v := _svec(_apply(rot_zyx([_r32(_inst + 0x18), 0, 0]), _svec([0, 0, -speed << 3])))
	v = _svec(_apply(rot_zyx([0, _r32(_inst + 0x14), 0]), v))
	_w32(_inst + 4, pos[0] + (v[0] >> 3))
	_w32(_inst + 8, pos[1] + (v[1] >> 3))
	_w32(_inst + 12, pos[2] + (v[2] >> 3))


func _target_collision(sb: Sub) -> void:
	var r := _pop()
	var flag := _pop()
	var out2 := _pop()
	var out := _pop()
	var t := _loc(sb.tgt if sb.tgt >= 0 else sb.src)
	var d0: int = _r32(_inst + 4) - t[0]
	var d1: int = _r32(_inst + 12) - t[2]
	if r * r < d0 * d0 + d1 * d1:
		_w32(flag, 0)
		return
	_w32(flag, 1)
	var ang := _wrap(-_wrap(atan_dw(d0, d1) - 0x400, 16), 16) & 0xfff
	var t2 := ang + 0x800
	_w32(out2, t2)
	ang = _wrap(t2, 16) >> 3
	_w32(out + 8, (r * sin512(0x80 - ang)) >> 12)
	_w32(out, (r * cos512(0x80 - ang)) >> 12)


func _random_target(sb: Sub) -> void:
	var exclude_self := _pop()
	var e := -1
	var n := _mod(rng.randi() & 0x7fff, 8)
	var guard := 0
	while n >= 0:
		_ce0 += 1
		while true:
			guard += 1
			if guard > 1000:                            # nobody qualifies: DW1 would hang
				return
			while _ce0 < ENT_MAX:
				if _ent(_ce0) != null and _on_map(_ce0) and _hp(_ce0) > 0 \
						and (exclude_self != 0 or _ce0 != sb.src):
					e = _ce0
					break
				_ce0 += 1
			if e >= 0 and _ce0 < ENT_MAX:
				break
			_ce0 += 1
			if _ce0 >= ENT_MAX:
				_ce0 = 1
		n -= 1
	sb.tgt = e


## findAABBHitEntity (main/aabb.c): the first fighter from start whose box (centre at
## mid-height, half extents r/2, h/2, r/2) overlaps the box c +- ext.
func aabb_hit(c: Array, ext: Array, src: int, start: int) -> int:
	for i in range(maxi(start, 0), ENT_MAX):
		if _ent(i) == null or i == src:
			continue
		var l := _loc(i)
		var h := _height(i)
		var r := _radius(i)
		var ec := [l[0], l[1] - (h >> 1), l[2]]
		var ee := [r >> 1, h >> 1, r >> 1]
		var hit := true
		for k in 3:
			if ec[k] + ee[k] < c[k] - ext[k] or ec[k] - ee[k] > c[k] + ext[k]:
				hit = false
				break
		if hit:
			return i
	return -1


func _box() -> void:
	var r := _pop()
	var out := _pop()
	var ext := _svec(_vec(_pop()))
	_w32(out, 0)
	if r < 0:
		r = _cd0
	var c := _svec(_vec(_inst + 4))
	var src: int = (_s.subs[_ce8] as Sub).src
	_cd8 = 1
	while true:
		var id := aabb_hit(c, ext, src, _cd8)
		_cd8 = id
		if id == -1:
			return
		if not _is_hit(id):
			_hit(id, c, r)
			_w32(out, 1)
			return
		_cd8 = id + 1


func _find_hit() -> void:
	var ext := _svec(_vec(_pop()))
	var mode := _pop()
	var out := _pop()
	_w32(out, 0)
	var c := _svec(_vec(_inst + 4))
	var src: int = (_s.subs[_ce8] as Sub).src
	_cd8 = 1
	while true:
		var id := aabb_hit(c, ext, src, _cd8)
		_cd8 = id
		if id == -1:
			return
		match mode:
			0:
				if not _is_hit(id):
					_w32(out, 1)
					return
				_cd8 = id + 1
			1:
				_w32(out, 1)
				return
			_:
				return


## calculateAttackHitPosition: on the victim's edge toward the attacker, at its head height.
func _hit_position(victim: int, attacker: int, r: int) -> Array:
	var v := _loc(victim)
	var a := _loc(attacker)
	var dx := _wrap(a[0] - v[0], 16)
	var dz := _wrap(a[2] - v[2], 16)
	var ry := (atan_dw(dz, dx) + 0x800) & 0xfff
	var o := _svec(_apply(rot_zyx([0, ry, 0]), [0, -_height(victim), r]))
	return [o[0] + v[0], o[1], o[2] + v[2]]


## applyLineAttackHit: the segment from the instance to the user's position against each
## fighter's square (+- radius), above its height + ext.y; the first hit, then stop.
func _line_hit(sb: Sub) -> void:
	_pop()
	var out := _pop()
	var arg := _pop()
	_w32(out, 0)
	var l0 := [_wrap(_r32(_inst + 4), 16), _wrap(_r32(_inst + 12), 16)]
	var s := _loc(sb.src)
	var l1 := [_wrap(s[0], 16), _wrap(s[2], 16)]
	for i in range(1, ENT_MAX):
		_cd8 = i
		if i == sb.src or _ent(i) == null or _is_hit(i) or not _on_map(i):
			continue
		var l := _loc(i)
		var r := _radius(i)
		var rect := [_wrap(l[0] - r, 16), _wrap(l[2] - r, 16), _wrap(l[0] + r, 16), _wrap(l[2] + r, 16)]
		if not segment_hits_rect(rect, l0, l1):
			continue
		if _r32(_inst + 8) < -_height(i) - _r32(arg + 4):
			continue
		var pos := _hit_position(i, sb.src, r)
		pos[1] = _r32(_inst + 8)
		_hit(i, pos, _cd0)
		_w32(out, 1)
		return
	_cd8 = ENT_MAX


## applyRadiusAttackHit: every fighter within its radius + R of the instance (x/z).
func _radius_hit(sb: Sub) -> void:
	var flag := _pop()
	var r := _pop()
	r = r * r
	_w32(flag, 0)
	for i in range(1, ENT_MAX):
		_cd8 = i
		if i == sb.src or _ent(i) == null or _is_hit(i) or not _on_map(i):
			continue
		var rad := _radius(i)
		var l := _loc(i)
		var dx: int = _r32(_inst + 4) - l[0]
		var dz: int = _r32(_inst + 12) - l[2]
		if rad * rad + r < dz * dz + dx * dx:
			continue
		var pos := _hit_position(i, sb.src, rad)
		pos[1] = -_height(i) / 2
		_hit(i, pos, _cd0)
		_w32(flag, 1)
	_cd8 = ENT_MAX


## doSomethingWithSomePoints (main/map.c): does the segment touch the rect [x0, z0, x1, z1]?
static func segment_hits_rect(rect: Array, a: Array, b: Array) -> bool:
	var code := [0, 0]
	var pts := [a, b]
	for i in 2:
		var p: Array = pts[i]
		var c := 5 if rect[2] < p[0] else (3 if p[0] < rect[0] else 4)
		if rect[3] < p[1]:
			c += 3
		elif p[1] < rect[1]:
			c -= 3
		if c == 4:
			return true
		code[i] = c
	if code[0] + code[1] == 8:
		return true
	if code[0] / 3 == code[1] / 3:
		return false
	if code[0] % 3 == code[1] % 3:
		return false
	var dx: int = b[0] - a[0]
	var dy: int = b[1] - a[1]
	var cx := [rect[0] - a[0], rect[2] - a[0], rect[0] - a[0], rect[2] - a[0]]
	var cy := [rect[1] - a[1], rect[1] - a[1], rect[3] - a[1], rect[3] - a[1]]
	var cross := _wrap32(_wrap32(dx * cy[0]) - _wrap32(dy * cx[0]))
	for i in range(1, 4):                                # 800da740: 32-bit products (BTL-91)
		if _wrap32(cross * _wrap32(_wrap32(dx * cy[i]) - _wrap32(dy * cx[i]))) < 0:
			return true
	return false
