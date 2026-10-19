class_name PetCues
## Debug: the trailer's cues (docs/dscreen_trailer.md). With --cues, lines {"t", "event": "cue", "do", ...}
## in his feed (pet_events.jsonl, where Claude Code's hook writes) make him act on a stage script's clock:
## appear, walk, leap, read, sleep, act, pin, hungry, due, prop, apply, about, bye. Every one goes through
## what he does on his own (a leap only to a spot PetGround.reachable offers him), so the footage is the
## app's own behaviour; only the timing is the script's.

const COMMANDS := ["appear", "walk", "leap", "read", "sleep", "act", "pin", "hungry", "due", "prop", "apply",
	"about", "bye"]


## Why a cue can't run ("" when it can): an unknown command or a missing field.
static func check(ev: Dictionary) -> String:
	var what := str(ev.get("do", ""))
	if not what in COMMANDS:
		return "unknown cue '%s'" % what
	var need: Array = {"walk": ["x"], "leap": ["x", "y"], "act": ["anim"], "pin": ["cat", "i"], "prop": ["name"]}.get(what, [])
	for f in need:
		if not ev.has(f):
			return "cue '%s' needs '%s'" % [what, f]
	return ""


## The reachable spot (PetGround.reachable's) nearest to `at` whose height is within `tol` px of it,
## {} when none: the cue names where he should go, but he only goes where he could leap by himself.
static func leap_spot(spots: Array, at: Vector2, tol: float) -> Dictionary:
	var best := {}
	var best_d := INF
	for s in spots:
		if absf(float(s["y"]) - at.y) > tol:
			continue
		var d := absf(float(s["x"]) - at.x)
		if d < best_d:
			best_d = d
			best = s
	return best


## Makes his next poop due now (or one due now, without a meal's): the next care tick raises his need.
static func due_now(d: Dictionary) -> void:
	var lv: Dictionary = d["live"]
	var poops: Array = lv["poops"]
	var clock := float(lv["clock"])
	if poops.is_empty():
		poops.append(clock)
	else:
		poops[0] = minf(float(poops[0]), clock)
