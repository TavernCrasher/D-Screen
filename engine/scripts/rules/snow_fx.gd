class_name SnowFx
extends RefCounted
## Freezeland snow (docs/maps.md "Screen effects"): on maps 88-96 and 132-135, overlay
## instances 0-34 are 2D flakes in screen space (origin at the screen centre, FIELD-29).
## Load FUN_800b3e08 (main.c:15558): i >= 20 x = random(320), then y = random(240), every
## load. Per field frame FUN_800b4cf4: the type comes from frames[0] (0 A, 1 B, 2 C), a
## random x jitter, a fixed fall speed; A and B melt (frames 3,4 / 5,6) past y 130 and
## restart at the top. Uses its own DwRng (vanilla shares rand(); nothing observable).

const MAPS := [88, 89, 90, 91, 92, 93, 94, 95, 96, 132, 133, 134, 135]
const COUNT := 35                    # instances 0-34
## frames[0] -> [jitter range, fall speed, type A (x drifts)]
const TYPES := {0: [6, 3, true], 3: [6, 3, true], 4: [6, 3, true],
	1: [2, 1, false], 5: [2, 1, false], 6: [2, 1, false], 2: [4, 10, false]}

var flakes: Array = []               # {id, x, y, cur, timer, frames: [obj], durations: [n], off}


static func is_snow_map(map_id: int) -> bool:
	return MAPS.has(map_id)


## FUN_800b3e08: the snow instances of a map's overlay_instances, randomised in order.
func load(map_id: int, instances: Array, rng: DwRng) -> void:
	flakes = []
	if not is_snow_map(map_id):
		return
	for inst in instances:
		var i := int(inst["instance"])
		if i >= COUNT:
			continue
		var objs := []
		var durs := []
		for fr in inst["frames"]:
			objs.append(int(fr[0]))
			durs.append(int(fr[1]))
		var x := int(inst["px"][0])
		if i >= 20:
			x = rng.rand(320)
		var y := rng.rand(240)
		flakes.append({"id": i, "x": x, "y": y, "cur": 0, "timer": 0, "frames": objs,
			"durations": durs, "off": false})


## set_map_object (op 0x57, FUN_800b5984) overwrites the instance's flag byte: the snow bit
## 0x80 is gone, so with flag 1 FUN_800b43c0 only runs the timer (FIELD-30; FRZL06 and FRZL15
## hide flakes this way). Flag 0 would make it an ordinary static sprite; no script does that.
func set_flag(instance: int, _flag: int) -> void:
	for f in flakes:
		if f["id"] == instance:
			f["off"] = true


## r = random(range); r > range/2 -> -(r mod range/2).
static func jitter(r: int, range_: int) -> int:
	var half := range_ / 2
	return -(r % half) if r > half else r


## One field frame (FUN_800b43c0 + FUN_800b4cf4) for every flake in order. Returns the
## sprites drawn this frame: [object, offset x, offset y] (top-left, offset space).
func tick(rng: DwRng, current_frame: int) -> Array:
	var out := []
	for f in flakes:
		var frames: Array = f["frames"]
		var cur0: int = f["cur"]
		if f["off"]:
			_advance(f, cur0)
			continue
		var t: Array = TYPES.get(frames[0], [])
		if t.is_empty():
			continue                                 # not a flake object (never in the data)
		var range_: int = t[0]
		var jit := jitter(rng.rand(range_), range_)
		if t[2] and current_frame % 3 == 0:
			f["x"] += jit
			if f["x"] > 320:
				f["x"] = 0
			elif f["x"] < 0:
				f["x"] = 320
		out.append([frames[cur0], int(f["x"]) - 160 + jit, int(f["y"]) - 120])
		f["y"] += int(t[1])
		if f["y"] > 130 and frames[0] != 2:
			var roll := rng.rand(10)
			if roll < 2 and f["cur"] == 0:
				f["cur"] = 1
				f["timer"] = 0
			if f["cur"] > 1 and f["cur"] + 1 >= frames.size():
				f["cur"] = 0
				f["y"] = 0
		if f["y"] > 240:
			f["y"] = 0
		_advance(f, cur0)
	return out


## FUN_800b43c0's generic timer advance, against the duration of the frame it started with.
static func _advance(f: Dictionary, cur0: int) -> void:
	f["timer"] += 1
	if f["timer"] >= int(f["durations"][cur0]):
		f["cur"] += 1
		f["timer"] = 0
		if f["cur"] >= f["frames"].size() or f["cur"] > 7:
			f["cur"] = 0
