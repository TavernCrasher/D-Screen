class_name Dw1Clip
extends RefCounted
## DW1's animation tick on a model's MMD clips (docs/shareable_pet_plan.md step 4), one port of
## startAnimation (FUN_800c1a04), tickAnimation (FUN_800c1c64), the momentum tick (FUN_800c1fbc,
## FUN_800c2570), the keyframe reader (FUN_800c2350, FUN_800c24a4), the root step (FUN_800c25c0)
## and the per-type texture cycles (FUN_800c1824). SydPatches Model.cpp is the same code.
##
## A clip is a header pose (bones 1.., scale if the count's bit 15 is set) and an instruction
## stream of halfwords: 0x0000 keyframes (per node a mask of 9 axes and a divisor: each value
## becomes a per-tick delta plus a remainder spread over the ticks), 0x1000 loop start (count,
## 0xFF = endless), 0x2000 loop end (jump back to frame hw1), 0x3000 a MoveImage inside the
## model's texture (eyes, mouths, swap channels), 0x4000 a sound (bank << 8 | id). An op runs
## when the clip's frame reaches its low 12 bits. One tick = one DW1 frame (20 per second).
##
## Each tick: the momentum moves every bone (node 0's translation is the root step, the root
## motion, a frame behind its keyframe), then the frame's instructions run, then the frame
## advances or the clip stops on its last one. Ticks after the stop change nothing (the eyes
## keep the last paste: nothing resets the texture when a clip starts).
##
## Units are DW1's: angles 4096 = 360, scale 4096 = 1, lengths in model units (y down, the model
## faces -z). Tests: equal to motion.json, eye_states.json, anim_sounds.json and efe.json's poses.

## FUN_800c1824: types whose texture cycles while a clip plays: the top 32 rows of the texture
## take one of the three bands below them, every second frame of the play time, in the order
## 3, 1, 2, 3, 2, 1 (the flames of Meramon, Birdramon, DemiMeramon...). Width in halfwords.
const CYCLE_WIDTH := {0x7F: 0x2C, 0x45: 0x10, 0x65: 0x10, 0x8F: 0x28, 0x6A: 0x28, 0x15: 0x28,
	0x68: 0x1E, 0x85: 0x1E, 9: 0x1E}
## FUN_800c25c0: the clips whose root step drops x ('$' and '#').
const NO_ROOT_X := [0x23, 0x24]

var mmd: PackedByteArray
var bones := 0
var type := -1                      # the model's id (the texture cycles)
var table := 0                      # the clip table (MMD header word 1)
var clip := -1                      # the clip playing or last played
var playing := false
var frame := 1
var end_frame := 0
var loop_end := 1
var loop_count := 0
var loop_start := 0
var ins := 0                        # the instruction pointer, in halfwords
var ticks := 0                      # ticks since the clip started
var playtime := 0                   # PLAYTIME_FRAMES: the texture cycles' clock (any tick count)
## The pose: per bone x, y, z. Bone 0's scale and rotation are the root's own (the entity's: kept
## from clip to clip); its translation is not kept here, see `root`.
var scale := PackedInt32Array()
var rot := PackedInt32Array()
var loc := PackedInt32Array()
## Momentum, 9 axes per node (scale xyz, rotation xyz, translation xyz).
var _delta := PackedInt32Array()
var _sub_delta := PackedInt32Array()
var _sub_value := PackedInt32Array()
var _scale1 := PackedInt32Array()
var _sub_scale := PackedInt32Array()
var _active := {}                   # node * 9 + axis -> true: the axes with momentum
var pose_bones := true              # false: only the root and the ops (the tests' fast path)
## This tick's results.
var root := Vector3i.ZERO           # the root step (model space)
var pastes: Array = []              # [sx, sy, w, h, dx, dy]: halfwords / rows from the texture origin
var sounds: Array = []              # [bank, id] (bank 4 = the entity's own cries)


func _init(mmd_bytes: PackedByteArray, bone_count: int, model_type := -1) -> void:
	mmd = mmd_bytes
	bones = bone_count
	type = model_type
	table = mmd.decode_u32(4) if mmd.size() >= 8 else 0
	for a in [scale, rot, loc]:
		a.resize(bones * 3)
	for b in bones:
		for k in 3:
			scale[b * 3 + k] = 4096
	for a in [_delta, _sub_delta, _sub_value, _scale1, _sub_scale]:
		a.resize(bones * 9)


## {clip id: byte offset} of every clip in the model's table (the table ends where the first
## clip starts; 0 = none), as the exporters walk it.
static func clip_offsets(mmd: PackedByteArray) -> Dictionary:
	var out := {}
	if mmd.size() < 8:
		return out
	var t := mmd.decode_u32(4)
	var first := mmd.size()
	var a := -1
	while (a + 1) * 4 < first and t + (a + 2) * 4 <= mmd.size():
		a += 1
		var off := mmd.decode_u32(t + a * 4)
		if off == 0:
			continue
		first = mini(first, off)
		if t + off + 2 <= mmd.size():
			out[a] = t + off
	return out


func has_clip(id: int) -> bool:
	if id < 0 or table + id * 4 + 4 > mmd.size():
		return false
	var off := mmd.decode_u32(table + id * 4)
	return off != 0 and table + off + 2 <= mmd.size()


func _w(i: int) -> int:
	return mmd.decode_u16(i * 2) if i * 2 + 2 <= mmd.size() else 0x2000


func _s(i: int) -> int:
	return mmd.decode_s16(i * 2) if i * 2 + 2 <= mmd.size() else 0


## startAnimation: the clip's header pose on bones 1.., the momentum cleared, frame 1. A clip the
## model doesn't have changes nothing (main.c:21005) and returns false.
func start(id: int) -> bool:
	if not has_clip(id):
		return false
	var o := table + mmd.decode_u32(table + id * 4)
	var count := mmd.decode_u16(o)
	var has_scale := count & 0x8000
	end_frame = count & 0x7FFF
	clip = id
	frame = 1
	loop_end = 1
	loop_count = 0
	playing = true
	ticks = 0
	_delta.fill(0)
	_sub_delta.fill(0)
	_sub_value.fill(0)
	_scale1.fill(0)
	_sub_scale.fill(0)
	_active.clear()
	o += 2
	for b in range(1, bones):
		if o + (18 if has_scale else 12) > mmd.size():
			break
		for k in 3:
			if has_scale:
				scale[b * 3 + k] = mmd.decode_s16(o + 2 * k)
			else:
				scale[b * 3 + k] = 4096
		if has_scale:
			o += 6
		for k in 3:
			rot[b * 3 + k] = mmd.decode_s16(o + 2 * k)
			loc[b * 3 + k] = mmd.decode_s16(o + 6 + 2 * k)
		o += 12
	ins = o / 2
	loop_start = ins
	root = Vector3i.ZERO
	pastes = []
	sounds = []
	return true


## One DW1 frame (tickAnimation). Fills root, pastes and sounds with what it did.
func tick() -> void:
	root = Vector3i.ZERO
	pastes = []
	sounds = []
	if not playing:
		return
	_momentum()
	if _w(ins) & 0x1000:                                     # vanilla's loop-start test (main.c:21094)
		loop_count = _w(ins) & 0xFF
		ins += 1
		loop_start = ins
		loop_end = _w(ins) & 0xFFF
	var guard := 0
	while frame == loop_end and guard < 256:
		guard += 1
		var op := _w(ins) & 0xF000
		if op == 0x4000:
			var c := _w(ins + 1)
			sounds.append([c >> 8, c & 0xFF])
			ins += 2
		elif op == 0x3000:
			var a := _w(ins + 1)
			var b := _w(ins + 2)
			var c := _w(ins + 3)
			pastes.append([a >> 8, a & 0xFF, b >> 8, b & 0xFF, c >> 8, c & 0xFF])
			ins += 4
		elif op == 0x2000:
			if loop_count != 0xFF:
				loop_count = (loop_count - 1) & 0xFF
			if loop_count == 0:
				ins += 2
			else:
				frame = _s(ins + 1)
				ins = loop_start
		elif op == 0x1000:
			loop_count = _w(ins) & 0xFF
			ins += 1
			loop_start = ins
		elif op == 0x0000:
			ins = _keyframe(ins + 1)
		else:
			break                                            # an unknown op: DW1 would spin here
		loop_end = _w(ins) & 0xFFF
	if frame == end_frame:
		playing = false
	else:
		frame += 1
	ticks += 1
	_cycle()
	playtime += 1


## FUN_800c1824, after the instructions: on even play-time frames the top 32 rows take band
## 3 (every 6th frame), 2 (every 4th) or 1.
func _cycle() -> void:
	if not CYCLE_WIDTH.has(type) or playtime & 1:
		return
	var band := 2 if playtime % 6 == 0 else 1 if playtime & 3 == 0 else 0
	pastes.append([0, 0x20 + band * 0x20, CYCLE_WIDTH[type], 0x20, 0, 0])


## FUN_800c2350 / FUN_800c24a4: a keyframe's values -> per-tick deltas and remainders.
func _keyframe(i: int) -> int:
	while _w(i) & 0x8000:
		var h := _w(i)
		var node := h & 0x3F
		var mask := (h >> 6) & 0x1FF
		var sc := _s(i + 1)
		i += 2
		for a in 9:
			if mask & (0x100 >> a) == 0:
				continue
			var v := _s(i)
			i += 1
			if node >= bones or sc == 0:
				continue
			var j := node * 9 + a
			var q := v / sc                                  # C's truncating division and remainder
			var r := v % sc
			_delta[j] = q
			if r != 0:
				_sub_value[j] = -1 if r < 1 else 1
				_scale1[j] = sc
				_sub_scale[j] = sc
			_sub_delta[j] = absi(r)
			if q != 0 or r != 0:
				_active[j] = true
			else:
				_active.erase(j)
	return i


## FUN_800c1fbc: every axis with momentum moves; node 0's translation is the root step.
func _momentum() -> void:
	for j: int in _active:
		var node := j / 9
		var a := j % 9
		if node == 0 and a >= 6:
			continue
		if not pose_bones and node != 0:
			continue
		var val := _delta[j]
		if _sub_delta[j] != 0:                               # FUN_800c2570
			_sub_scale[j] -= _sub_delta[j]
			if _sub_scale[j] < 1:
				_sub_scale[j] += _scale1[j]
				val += _sub_value[j]
		if a < 3:
			scale[node * 3 + a] += val
		elif a < 6:
			var r := rot[node * 3 + a - 3] + val
			rot[node * 3 + a - 3] = ((r + 0x8000) & 0xFFFF) - 0x8000   # a short
		else:
			loc[node * 3 + a - 6] += val
	root = root_step()


## FUN_800c25c0's step: node 0's translation momentum for this tick (model space; DW1 then
## turns it by the entity's facing and moves the entity).
func root_step() -> Vector3i:
	var v := [0, 0, 0]
	for k in 3:
		var j := 6 + k
		if k == 0 and clip in NO_ROOT_X:
			continue
		if _sub_delta[j] == 0:
			v[k] = _delta[j]
			continue
		_sub_scale[j] -= _sub_delta[j]
		if _sub_scale[j] > 0:
			v[k] = _delta[j]
		else:
			v[k] = _delta[j] + _sub_value[j]
			_sub_scale[j] += _scale1[j]
	return Vector3i(v[0], v[1], v[2])


## The state that decides what the clip does next (a repeat of it is a loop).
func state_key() -> Array:
	return [ins, frame, loop_count, loop_end, loop_start, playing]


## libgte RotMatrix (4096 = 360): M = Rx * Ry * Rz, rows, float64 as dw1_model_size.py.
static func rot_matrix(rx: int, ry: int, rz: int) -> PackedFloat64Array:
	var a := rx / 4096.0 * TAU
	var b := ry / 4096.0 * TAU
	var c := rz / 4096.0 * TAU
	var ca := cos(a)
	var sa := sin(a)
	var cb := cos(b)
	var sb := sin(b)
	var cc := cos(c)
	var sc := sin(c)
	# Rx * Ry
	var m := PackedFloat64Array([cb, 0.0, sb, sa * sb, ca, -sa * cb, -ca * sb, sa, ca * cb])
	# * Rz
	return PackedFloat64Array([m[0] * cc + m[1] * sc, -m[0] * sc + m[1] * cc, m[2],
		m[3] * cc + m[4] * sc, -m[3] * sc + m[4] * cc, m[5],
		m[6] * cc + m[7] * sc, -m[6] * sc + m[7] * cc, m[8]])


## The world pose of every bone in DW1 space (bone 0 at the origin, unturned; parents first as
## the skeleton lists them): per bone [m00..m22, x, y, z], float64. skeleton: [object, parent].
func world(skeleton: Array) -> Array:
	var out := []
	for b in bones:
		if b == 0:
			out.append(PackedFloat64Array([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]))
			continue
		var m := rot_matrix(rot[b * 3], rot[b * 3 + 1], rot[b * 3 + 2])
		for i in 3:
			for k in 3:
				m[i * 3 + k] *= scale[b * 3 + k] / 4096.0
		var l := Vector3(loc[b * 3], loc[b * 3 + 1], loc[b * 3 + 2])
		var parent: int = skeleton[b][1] if b < skeleton.size() else -1
		var w := PackedFloat64Array()
		w.resize(12)
		if parent < 0 or parent >= out.size():
			for i in 9:
				w[i] = m[i]
			w[9] = l.x
			w[10] = l.y
			w[11] = l.z
		else:
			var p: PackedFloat64Array = out[parent]
			for i in 3:
				for k in 3:
					w[i * 3 + k] = p[i * 3] * m[k] + p[i * 3 + 1] * m[3 + k] + p[i * 3 + 2] * m[6 + k]
				w[9 + i] = p[9 + i] + p[i * 3] * l.x + p[i * 3 + 1] * l.y + p[i * 3 + 2] * l.z
		out.append(w)
	return out
