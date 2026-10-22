class_name PetBrain
extends RefCounted
## The desktop pet's choices, apart from the window (testable headless): which line he says
## (pet/lines/, a shuffled bag per category so nothing repeats until the bag is empty), the
## greeting for the hour, and how he answers Claude Code's hook events (tools/pet_hook.py writes
## them) without chattering: a long job's end gets a cheer and a line, a short one a hop, a
## question always gets a line, failures are rate-limited.

const LONG_JOB := 45.0               # s from the prompt to Stop: cheer with a line
const SHORT_JOB := 10.0              # s: a joy hop, no line
const ASK_GAP := 20.0                # s between "they need your answer" lines
const YOUR_TURN_GAP := 600.0
const FAIL_ANIM_GAP := 120.0
const FAIL_LINE_GAP := 900.0
## Places (the user, 2026-10-18): while another save is played, each map it enters ("map" events,
## VpetSave.tell_pet) has a 1 in 10 chance of a comment on its area; after one, that area rests
## 20-30 min, and any comment waits PLACE_GAP s after the last.
const PLACE_CHANCE := 0.1
const PLACE_REST := [1200.0, 1800.0]
const PLACE_GAP := 120.0
const PLACE := "place:"              # line categories "place:<area>" (places.json)
const CHATTER_MIN := 1200.0          # s between unprompted lines
const CHATTER_MAX := 2400.0

## DW1 animation ids (docs/godot_prototype.md "Animations"; every partner has them all). Their
## uses are cited in docs/fidelity_audit.md PET-5: 15 / 16 / 19 are DW1's condition idles
## (FUN_800df2d0, main.c:32369-32412), 22 the nod (TRN.c:1764 and five scripts), 23 the partner's
## distress loop (scripts 180, 203), 21 a get-up (its root motion is 44's or undoes 9).
const A_IDLE := 0
const A_WALK := 2
const A_HAPPY := 5
const A_UNHAPPY := 7
const A_SLEEP := 9
const A_JOY := 11
const A_SCOLDED := 12
const A_SCOLDED_DESERVED := 25       # a deserved scold: head hung, trembling (main.c:10996-11013)
const A_REFUSE := 13                 # refused food (FUN_800ddec0 case 4)
const A_HUNGRY := 15                 # condition idle: hungry
const A_TOILET := 16                 # condition idle: needs the toilet
const A_CALL := 19                   # condition idle: sulking (flag 0x10); his calls for you
const A_GET_UP := 21
const A_NOD := 22
const A_DISTRESS := 23               # dangling, falling
const A_FLINCH := 40
const A_VICTORY := 42
const A_KO := 43
const A_KO_UP := 44
const TRAIN := [48, 49, 56]          # Ninjamon: Sonic Jab, Dynamite Kick, Iga School Knife Throw (46 + slot)
const DEFAULT_TYPE := 58             # Ninjamon (custom_ninj), when no save is the pet's
const MODEL_PX := 150.0              # Ninjamon's height on screen at 96 dpi; the others by DW1 size (size_px)
const LINES_DIR := "res://pet/lines/"
## Every category the pet says (a stage pool has them all; train_<anim> lines are optional:
## without one a move is called by its name).
const CATEGORIES := ["greet", "morning", "night", "talk", "praise", "scold", "scold_unfair", "read", "held", "dropped",
	"wake", "done", "ask", "your_turn", "failed", "bye", "game", "hungry", "ate", "full", "toilet", "toilet_done", "toilet_no", "accident",
	"pile_left", "missed", "clean", "trained", "trained_enough", "trained_frozen", "train_start",
	"cant_reach", "evolve_ready", "evolve_close"]
## Lines with a stat: "%s" takes VpetSave.LABELS' name (evolve_close, EvoForecast's "close").
const STAT_LINES := ["evolve_close"]

var lines: Dictionary = {}
var train: Array = TRAIN             # the DW1 animation ids of the moves he shadowboxes and trains
var quiet := false                   # no lines except questions
var rng := RandomNumberGenerator.new()
var _bags := {}
var _work_start := {}                # session id -> time of its last prompt
var _last := {}                      # gate name -> time
var next_chatter := 0.0
var _place_rest := {}                # area -> time it may be commented on again
var last_cat := ""                   # the last pick's category and line (category_of: his icon in
var last_text := ""                  # Mixed / Digi talk)
var _pins := {}                      # category -> the line the next pick returns (the trailer's cues)


func _init(lines_: Dictionary = {}, seed_ := -1) -> void:
	lines = lines_
	if seed_ >= 0:
		rng.seed = seed_
	else:
		rng.randomize()


## The name he goes by (the Settings' Name row): his nickname, or the species' when asked or
## when he has none.
static func pick_name(nick: String, spec: String, spec_first: bool) -> String:
	return spec if spec_first or nick == "" else nick


## A Digimon's lines: his stage's pool (stage_<key>.json) plus his own few (own.json, by DW1 id),
## which join the pool's bags; an own entry with "_only" (Ninjamon's full set) replaces the pool.
static func load_lines(type := 58, level := "Champion", dir := LINES_DIR) -> Dictionary:
	var own_all = _json(dir + "own.json")
	var own: Dictionary = own_all.get(str(type), {}) if own_all is Dictionary else {}
	var out := {}
	if not own.get("_only", false):
		var pool = _json(dir + "stage_%s.json" % stage_key(level))
		if pool is Dictionary:
			for cat in pool:
				if pool[cat] is Array:
					out[cat] = (pool[cat] as Array).duplicate()
	for cat in own:
		if own[cat] is Array and not String(cat).begins_with("_"):
			out[cat] = (own[cat] as Array) + (out.get(cat, []) as Array)
	if own.has("_moves"):
		out["_moves"] = own["_moves"]
	var places = _json(dir + "places.json")          # every partner's
	if places is Dictionary:
		for area in places:
			if places[area] is Array:
				out[PLACE + str(area)] = (places[area] as Array).duplicate()
	return out


static func _json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	return JSON.parse_string(text) if text != "" else null


## His height on screen: smaller than Ninjamon, DW1's own proportion (the user, 2026-10-21, 9d 6:
## the babies looked far too big; Poyomon 84 px, was 113); bigger, softened (the square root of
## the ratio), so the big ones still look big without covering the screen (the user, 2026-10-18):
## Botamon 78 px, Tyrannomon 213, SkullGreymon 268.
static func size_px(id: int) -> float:
	var ref := DigimonModel.dw1_height(DEFAULT_TYPE)
	var h := DigimonModel.dw1_height(id)
	if h <= 0.0 or ref <= 0.0:
		return MODEL_PX
	return MODEL_PX * (h / ref if h < ref else sqrt(h / ref))


## The DW1 animation ids of the moves he shadowboxes with: the save's equipped three and his
## finisher (the link's "moves"; PET-6, the user: "the equipped moves the digimon had in the save
## file"), else his own list (own.json "_moves", Ninjamon's three), else the moves of his that he
## has learned (the link) and his finisher (his species' own, never learned), else all his moves
## with a clip. A move's clip is 46 + its slot in his technique list.
static func moves_for(data, id: int, own: Array, learned: Array, equipped: Array = []) -> Array:
	var eq := []
	var techs0: Array = data.digimon[id]["techniques"]
	for t in equipped:
		for n in techs0.size():
			var a := DigimonModel.TECH_ANIM_START + n
			if int(t) >= 0 and Techniques.slot_move(data, id, n) == int(t) and not DigimonModel.dw1_anim(id, a).is_empty() and not a in eq:
				eq.append(a)
	if not eq.is_empty():
		return eq
	if not own.is_empty():
		return own.map(func(v): return int(v))
	var known := learned.map(func(v): return int(v))
	var all := []
	var mine := []
	var techs: Array = data.digimon[id]["techniques"]
	for n in techs.size():
		var a := DigimonModel.TECH_ANIM_START + n
		if DigimonModel.dw1_anim(id, a).is_empty():
			continue
		all.append(a)
		var t := Techniques.slot_move(data, id, n)
		if t in known or data.techniques[t].get("is_finisher", false):
			mine.append(a)
	return all if known.is_empty() or mine.is_empty() else mine


## The top of his head over his mesh height: above 1 for DW1's floating Digimon (Poyomon's mesh
## starts 145 units above the ground, Yuramon's 97), which DigimonModel lifts as in the game.
static func top_factor(id: int) -> float:
	var h := DigimonModel.dw1_height(id)
	return (h + DigimonModel.dw1_bottom(id)) / h if h > 0.0 else 1.0


## A move called out by name when he has no line of his own for it. DW1's font has no "&"
## (Etemon's Dark Network & Concert Crush): "and", on a second row.
static func move_call(name: String) -> String:
	return name.replace(" & ", " and\n") + "!"


## The stage pool for a DW1 level (the digimon table's "level").
static func stage_key(level: String) -> String:
	match level:
		"Fresh", "In-Training":
			return "baby"
		"Rookie":
			return "rookie"
		"Ultimate":
			return "ultimate"
	return "champion"


## Lines that break DW1's text box: more than 3 rows under the name, a row too wide for the box,
## or a glyph DW1's font lacks (test_pet_lines, tools/check_pet_lines.gd).
static func bad_lines(lines_: Dictionary) -> Array:
	var bad := []
	for cat in lines_:
		if not lines_[cat] is Array or String(cat).begins_with("_"):
			continue
		var texts: Array = lines_[cat]
		if cat in STAT_LINES:                              # every stat's name in its place
			texts = []
			for text in lines_[cat]:
				for l in VpetSave.LABELS.values():
					texts.append(String(text).replace("%s", l))
		for text in texts:
			var rows: PackedStringArray = String(text).split("\n")
			if rows.size() > DwTextBox.ROWS - 1:               # the name takes row 0
				bad.append("%s: %d rows: %s" % [cat, rows.size(), text])
			for row in rows:
				for g in DwText.layout(row)["glyphs"]:
					if int(g[1]) + 12 > DwTextBox.ROW_W:
						bad.append("%s: too wide: %s" % [cat, row])
						break
					if int(g[0]) == DwText.SENTINEL:
						bad.append("%s: not in DW1's font: %s" % [cat, row])
						break
	return bad


## A line of the category, "" if it has none.
func pick(cat: String) -> String:
	var all: Array = lines.get(cat, [])
	if all.is_empty():
		return ""
	if _pins.has(cat):                       # pinned: that line, once, outside the bag
		var i: int = _pins[cat]
		_pins.erase(cat)
		if i >= 0 and i < all.size():
			last_cat = cat
			last_text = all[i]
			return last_text
	var bag: Array = _bags.get(cat, [])
	if bag.is_empty():
		bag = range(all.size())
		for i in range(bag.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = bag[i]
			bag[i] = bag[j]
			bag[j] = t
		_bags[cat] = bag
	last_cat = cat
	last_text = all[int(bag.pop_back())]
	return last_text


## Debug (the trailer's pin cue): the next pick of `cat` returns its line i.
func pin(cat: String, i: int) -> void:
	_pins[cat] = i


## The category a line he's about to say was picked from: the last pick's, when the line starts as
## it does (a training line gets its gain as a second row; "%s" takes a stat's name), else "" (a
## move called by name).
func category_of(text: String) -> String:
	var head := last_text.split("\n")[0].split("%s")[0]
	return last_cat if head != "" and text.begins_with(head) else ""


static func greet_category(hour: int) -> String:
	if hour >= 5 and hour < 11:
		return "morning"
	if hour >= 23 or hour < 5:
		return "night"
	return "greet"


func schedule_chatter(now: float) -> void:
	next_chatter = now + rng.randf_range(CHATTER_MIN, CHATTER_MAX)


## An unprompted line when its time has come: {"anim", "line"} or {}.
func chatter(now: float, hour: int) -> Dictionary:
	if now < next_chatter:
		return {}
	schedule_chatter(now)
	if quiet:
		return {}
	var cat := "night" if greet_category(hour) == "night" and rng.randf() < 0.5 else "talk"
	return {"anim": A_HAPPY if cat == "talk" else A_NOD, "line": cat}


func _gate(name: String, now: float, gap: float) -> bool:
	if _last.has(name) and now - float(_last[name]) < gap:
		return false
	_last[name] = now
	return true


## A hook event ({"event", "type", "session", "t"}, see tools/pet_hook.py) -> {"anim": id,
## "line": category} (either may be missing) or {} to ignore it.
func on_event(ev: Dictionary, now: float) -> Dictionary:
	var kind: String = ev.get("event", "")
	var session: String = ev.get("session", "")
	var r := {}
	match kind:
		"UserPromptSubmit":
			_work_start[session] = now
		"Stop":
			var took := now - float(_work_start.get(session, now))
			_work_start.erase(session)
			if took >= LONG_JOB:
				r = {"anim": A_VICTORY, "line": "done"}
			elif took >= SHORT_JOB:
				r = {"anim": A_JOY}
		"StopFailure":
			_work_start.erase(session)
			r = {"anim": A_UNHAPPY, "line": "failed"}
		"Notification":
			match String(ev.get("type", "")):
				"permission_prompt", "elicitation_dialog":
					if _gate("ask", now, ASK_GAP):
						r = {"anim": A_CALL, "line": "ask", "urgent": true}
				"idle_prompt":
					if _gate("your_turn", now, YOUR_TURN_GAP):
						r = {"anim": A_NOD, "line": "your_turn"}
		"map":
			var area := str(ev.get("area", ""))
			if not quiet and lines.has(PLACE + area) and now >= float(_place_rest.get(area, 0.0)) \
					and now - float(_last.get("place", -INF)) >= PLACE_GAP and rng.randf() < PLACE_CHANCE:
				_last["place"] = now
				_place_rest[area] = now + rng.randf_range(PLACE_REST[0], PLACE_REST[1])
				r = {"anim": A_HAPPY, "line": PLACE + area}
		"PostToolUseFailure":
			if _gate("fail_anim", now, FAIL_ANIM_GAP):
				r = {"anim": A_UNHAPPY}
				if _gate("fail_line", now, FAIL_LINE_GAP):
					r["line"] = "failed"
	if quiet and r.has("line") and not r.get("urgent", false):
		r.erase("line")
	return r


## The command line for his next run. Godot's own options aren't in OS.get_cmdline_args, so a run
## from the editor (tools/run_pet.bat) lost --rendering-driver opengl3 on a restart (a save switch)
## and came back under Forward+, whose transparent window tints a box around him (the user,
## 2026-10-21: Ninjamon fine, then Agumon and Tokomon boxed); they're given again, with --path. The
## exported app sets its renderer in its own settings. A first run's options aren't repeated.
static func relaunch_args(args: PackedStringArray, user: PackedStringArray, exported: bool, driver: String, path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not exported:
		out.append_array(["--rendering-driver", driver, "--path", path])
	out.append_array(args)
	out.append("--")
	for a in user:
		if not (a == "--first-run" or a.begins_with("--disc=")):
			out.append(a)
	return out
