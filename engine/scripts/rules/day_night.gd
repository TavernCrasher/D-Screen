class_name DayNight
extends RefCounted
## Time of day on outdoor maps (docs/maps.md "Day/night palettes"): three background
## palettes (day, evening, night) and light factors for the 3D models. updateTimeOfDay
## FUN_800d676c sets them on map load; at 16:00, 20:00 and 6:00 a 26-frame transition
## (FUN_800d7104 / tick FUN_800d7210) fades to the next one. Maps with flag 0x40 (indoors,
## caves) always use palette 0 and full lights.

const DAY := 0                       # palette index (mapCluts[0..2])
const EVENING := 1
const NIGHT := 2
const FRAMES := 25                   # d9c 0..24 fade, the 26th tick loads the target


static func phase_for_hour(h: int) -> int:
	if h >= 6 and h < 16:
		return DAY
	if h >= 16 and h < 20:
		return EVENING
	return NIGHT


## renderMap (main.c:27911-27922): the transition started at the top of hours 16, 20, 6.
static func mode_for_hour(h: int) -> int:
	match h:
		16:
			return 0
		20:
			return 1
		6:
			return 2
	return -1


static func source_phase(mode: int) -> int:
	return [DAY, EVENING, NIGHT][mode]


static func target_phase(mode: int) -> int:
	return [EVENING, NIGHT, DAY][mode]


## Light colour factors /10 (main.c:28309-28330): evening keeps red at full.
static func light_factors(phase: int) -> Vector3i:
	match phase:
		EVENING:
			return Vector3i(10, 7, 7)
		NIGHT:
			return Vector3i(5, 5, 5)
	return Vector3i(10, 10, 10)


## d = 6 - d9c / 5: each fade frame moves 1/d of the way from the original palette.
static func transition_divisor(frame: int) -> int:
	return 6 - frame / 5


## The fraction of the way shown at fade frame f (0..24); 1.0 once the target is loaded.
static func mix_for_frame(f: int) -> float:
	return 1.0 if f >= FRAMES else 1.0 / transition_divisor(f)


## FUN_800d7210's per-entry maths on RGB5551: each channel c1 - (c1 - c2) / d (C truncation),
## the STP bit from c1.
static func blend_entry(c1: int, c2: int, d: int) -> int:
	var out := c1 & 0x8000
	for shift in [0, 5, 10]:
		var a: int = (c1 >> shift) & 31
		var b: int = (c2 >> shift) & 31
		out |= (a - (a - b) / d) << shift
	return out
