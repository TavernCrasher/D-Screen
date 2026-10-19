class_name GymMoves
extends RefCounted
## The two gym tables the desktop pet shares with GymSession (docs/care_simulation.md), apart so
## D-Screen ships them without the gym's field code (DS8-2).

## TRN 8008f050 / TRN2 8008da20 (identical): the strike clip and its hit frame per Digimon.
const STRIKE := [[0, 0], [46, 10], [46, 10], [51, 12], [46, 20], [53, 20], [46, 10], [46, 10],
	[46, 10], [53, 13], [46, 10], [46, 20], [49, 10], [46, 8], [46, 10], [46, 10], [46, 10], [46, 20],
	[46, 10], [46, 10], [46, 14], [46, 15], [46, 10], [46, 10], [46, 10], [46, 10], [46, 10], [46, 8],
	[51, 10], [46, 20], [46, 20], [46, 10], [46, 14], [46, 20], [49, 10], [46, 10], [53, 20], [46, 20],
	[46, 10], [46, 20], [46, 13], [47, 30], [46, 15], [46, 15], [46, 10], [53, 23], [46, 10], [51, 10],
	[46, 10], [46, 10], [52, 10], [46, 10], [46, 10], [46, 10], [46, 10], [46, 10], [48, 30], [46, 10],
	[46, 10], [46, 25], [48, 10], [46, 10], [46, 10], [46, 10], [46, 10], [46, 10], [46, 10]]

## TRN 8008c1c8: the glove (71..83) swings out and back by the limits from its saved x; at the
## impact three sparks, then two frames of the partner knocked +100 x with dust; after the snap
## it runs back to the station, where the end is checked.
const GLOVE := [[50, 100, 3], [-50, 50, 4], [50, 90, 5], [-30, 60, 6], [20, 90, 7], [-10, 70, 8],
	[5, 90, 9], [-4, 0, 10]]


## The glove's x offset from its saved x on each frame of one cycle (39 frames).
static func glove_offsets() -> Array:
	var out := []
	var x := 0
	for g in GLOVE:
		while true:
			x += int(g[0])
			out.append(x)
			if (g[0] > 0 and x >= int(g[1])) or (g[0] < 0 and x <= int(g[1])):
				break
	return out
