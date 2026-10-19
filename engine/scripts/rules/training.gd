class_name Training
extends RefCounted
## File City gym training (overlay TRN). Gains verified in-game (docs/verification.md).
## The other gyms (Freezeland, Beetleland, Trash Mountain) run overlay TRN2: GYMS2, train2.

## gym: multiplier id (TRN::80089e08 arg), base gains, session cost (tiredness, fullness, happiness)
const GYMS := [
	{"name": "HP", "mult_id": 0, "base": {"max_hp": 80, "off": 2}, "cost": [10, 1, 0]},
	{"name": "MP", "mult_id": 1, "base": {"max_mp": 80, "def": 2}, "cost": [7, 1, 0]},
	{"name": "Offense", "mult_id": 2, "base": {"off": 8, "spd": 2}, "cost": [9, 1, 1]},
	{"name": "Defense", "mult_id": 3, "base": {"def": 8, "brn": 2}, "cost": [9, 1, 0]},
	{"name": "Speed", "mult_id": 4, "base": {"max_hp": 10, "spd": 8}, "cost": [8, 1, 1]},
	{"name": "Brains", "mult_id": 1, "base": {"max_mp": 10, "brn": 8}, "cost": [6, 1, 1]},
]
const BOOST_BIT := {"off": 1, "def": 2, "spd": 4, "brn": 8, "max_hp": 0x10, "max_mp": 0x20}
const TRAINING_MANUAL := 33

## TRN2 gyms (docs/care_simulation.md "Other gyms"; gain functions TRN2.c:805-1093). The first
## base entry is the primary stat; bit: the one boost bit checked for both stats.
const GYMS2 := [
	{"name": "Moving Ice", "mult_id": 0, "base": {"max_hp": 120, "def": 2}, "bit": 0x10, "cost": [10, 2, 2]},
	{"name": "Rock Pushing", "mult_id": 0, "base": {"max_hp": 120}, "bit": 0x10, "cost": [10, 2, 1]},
	{"name": "Icicle Fall", "mult_id": 3, "base": {"def": 12, "spd": 2}, "bit": 2, "cost": [9, 2, 2]},
	{"name": "Hammer Machine", "mult_id": 3, "base": {"def": 12}, "bit": 2, "cost": [9, 2, 1]},
	{"name": "Striking", "mult_id": 2, "base": {"off": 12}, "bit": 1, "cost": [9, 2, 1]},
	{"name": "Treadmill", "mult_id": 4, "base": {"spd": 12}, "bit": 4, "cost": [8, 2, 1]},
	{"name": "Hide In Trash", "mult_id": 1, "base": {"max_mp": 150}, "bit": 0x20, "cost": [7, 1, 4]},
]
## Builtin 7 (main.c:52420-52457): on these maps pstat 254 picks a TRN2 routine; each routine's
## init only registers on its own map (ICSA03, BETL03, BETL04, GOMI02) -> GYMS2 index.
const TRN2_GYMS := {99: {0: 0, 3: 2}, 107: {0: 1, 1: 4}, 108: {3: 3, 2: 5}, 165: {4: 6}}
const TRN2_MAPS := [99, 107, 108, 165]


## Per-gym affinity (x10) by the care table's training_affinity row (TRN::80089e08).
static func affinity(mult_id: int, row: int) -> int:
	match mult_id:
		0, 3:
			return [10, 10, 9, 11][row] if row < 4 else 8
		1, 5:
			return [10, 9, 11, 10][row] if row < 4 else 8
		_:
			return [10, 11, 10, 9][row] if row < 4 else 8


## Affinity x stage factor (both overlays).
static func _affinity_stage(sim: CareSim, mid: int) -> int:
	var v := affinity(mid, int(sim.care_row()["training_affinity"]))
	match sim.level():
		1, 2: v *= 9
		3: v *= 10
		4: v *= 11
		_: v *= 12
	return v


## The variant sessions (TRN inits 8008b5e8 / 8008ca04 / 8008ce90, TRN.c:1121, 1575, 1705):
## GIAS09's Offense and Speed stations run with variant 6, MIST05's Brains with 9. A variant
## has its own base gains (Off: HP +10, Off +8, TRN.c:161-167; Brn: Brn +15 only, TRN.c:401-406;
## Spd: the normal ones), no gym-upgrade or session bonus and no session count.
const VARIANT_BASE := {6: {2: {"max_hp": 10, "off": 8}}, 9: {5: {"brn": 15}}}


static func variant(map_id: int, gym: int) -> int:
	if map_id == 78 and gym in [2, 4]:
		return 6
	if map_id == 119 and gym == 5:
		return 9
	return 0


## TRN::80089e08. upgraded: gym-upgrade story flag (0xDB gyms 0/3/4, 0xFB gyms 1/2/5). The
## session counts are read by multiplier id (Brains reads MP's, TRN.c:624).
static func multiplier(sim: CareSim, gym: int, upgraded := false, has_manual := false, variant_ := 0) -> int:
	var mid: int = GYMS[gym]["mult_id"]
	var v := _affinity_stage(sim, mid)
	var div := 100
	if upgraded and variant_ == 0:
		v *= 6
		div *= 5
	if sim.p.gym_sessions[mid] > 9 and variant_ == 0:
		v *= 6
		div *= 5
	if has_manual:
		v *= 11
		div *= 10
	return v * 10 / div


## Gains for one session; perf = 10 normally (Bonus Try: the slot machine's 100/40/20/5).
static func gains(sim: CareSim, gym: int, mult: int, perf := 10, variant_ := 0) -> Dictionary:
	var p := sim.p
	var out := {}
	var base: Dictionary = VARIANT_BASE.get(variant_, {}).get(gym, GYMS[gym]["base"])
	for k in base:
		var b: int = base[k]
		var g: int
		if p.boost_mask & BOOST_BIT[k]:
			g = b * mult * p.boost_mult / 100
		else:
			g = b * mult / 10
		g = g * perf / 10
		if k in ["max_hp", "max_mp"]:
			g = mini(g, 999)
		if p.tiredness == 100:
			g = 1
		out[k] = g
	return out


## One full session: gains, then the 1-hour session cost (TRN::8008a284). The gym's own
## session count goes up when the session starts (TRN.c:846-1712, Fresh/In-Training only, not
## in a variant), so it already counts for this session's multiplier.
static func train(sim: CareSim, gym: int, upgraded := false, has_manual := false, perf := 10,
		variant_ := 0) -> Dictionary:
	var p := sim.p
	if sim.level() < 3 and variant_ == 0:
		p.gym_sessions[gym] += 1
	var g := gains(sim, gym, multiplier(sim, gym, upgraded, has_manual, variant_), perf, variant_)
	for k in g:
		var cap := 9999 if k in ["max_hp", "max_mp"] else 999
		p.set(k, mini(p.get(k) + g[k], cap))
	var cost: Array = GYMS[gym]["cost"]
	session_cost(sim, cost[0], cost[1], cost[2])
	return g


## TRN2::8008b76c: the same affinity and stage, the Training Manual, but no gym-upgrade or
## session-count bonus.
static func multiplier2(sim: CareSim, gym: int, has_manual := false) -> int:
	var v := _affinity_stage(sim, int(GYMS2[gym]["mult_id"]))
	return v * 11 * 10 / 1000 if has_manual else v * 10 / 100


## TRN2 gains: one boost bit for both stats; at tiredness 100 both are 1; only the primary is
## capped at 999.
static func gains2(sim: CareSim, gym: int, mult: int, perf := 10) -> Dictionary:
	var p := sim.p
	var out := {}
	var first := true
	for k in GYMS2[gym]["base"]:
		var b: int = GYMS2[gym]["base"][k]
		var g: int
		if p.boost_mask & int(GYMS2[gym]["bit"]):
			g = b * mult * p.boost_mult / 100
		else:
			g = b * mult / 10
		g = g * perf / 10
		if first:
			g = mini(g, 999)
		if p.tiredness == 100:
			g = 1
		out[k] = g
		first = false
	return out


## One TRN2 session: gains, then the cost (TRN2::8008ba80: hunger -61 / feed window -12, no
## day/night transition). No session counters, weight or technique changes.
static func train2(sim: CareSim, gym: int, has_manual := false, perf := 10) -> Dictionary:
	var p := sim.p
	var g := gains2(sim, gym, multiplier2(sim, gym, has_manual), perf)
	for k in g:
		var cap := 9999 if k in ["max_hp", "max_mp"] else 999
		p.set(k, mini(p.get(k) + g[k], cap))
	var cost: Array = GYMS2[gym]["cost"]
	session_cost(sim, cost[0], cost[1], cost[2], 61, 12)
	return g


## The TRN2 gym for builtin 7 on map_id with routine pstat 254; -1 = not a TRN2 map, -2 = a
## TRN2 map but no routine registers there (vanilla would hang; no script does it).
static func trn2_gym(map_id: int, routine: int) -> int:
	if not TRN2_MAPS.has(map_id):
		return -1
	return int(TRN2_GYMS[map_id].get(routine, -2))


## Brains training (TRN 800897f8, TRN.c:451-497): with b0 = Brains before and b1 = b0 + the
## (999-capped) gain, crossing 100 / 200 / 300 / 400 / 500 gives "new orders" messages (rows 120 /
## 132 / 148 of window 2); otherwise crossing 150, 250, ..., 750, 800, 850, 900, 950 or landing on
## exactly 999 rolls for a technique (8008a744). Returns {lines: [[row, colour, text]], roll}.
const ORDER_MSGS := {100: ["Give it all you got!"], 200: ["Take it easy!"], 300: ["Get back!", "Change target!"],
	400: ["Hang in there!"], 500: ["Technique mastered."]}
const ROLL_AT := [150, 250, 350, 450, 550, 650, 750, 800, 850, 900, 950]


static func brains_events(b0: int, gain: int) -> Dictionary:
	var b1 := b0 + gain
	var rows := {}
	var new_row := 132
	for m in [100, 200, 300, 400, 500]:
		if b0 < m and b1 >= m:
			var msgs: Array = ORDER_MSGS[m]
			rows[120] = msgs[0]                       # each milestone writes row 120 again
			if msgs.size() > 1:
				rows[132] = msgs[1]
				new_row = 148
	if not rows.is_empty():
		var lines := []
		for r in rows:
			lines.append([r, 7, rows[r]])
		lines.append([new_row, 1, "New orders!"])
		return {"lines": lines, "roll": false}
	var roll := b1 == 999
	for m in ROLL_AT:
		if b0 < m and b1 >= m:
			roll = true
	return {"lines": [], "roll": roll}


## 8008a744: per specialty slot, the first candidate (8008f14c) not yet learned that the partner's
## species can learn sets that slot's chance (8008f184[3k + slot]); the best chance wins (ties:
## the earlier slot) against random(100), which is always drawn. Returns the move learned or -1.
const ROLL_CANDIDATES := [[2, 5, 0, 4, 3, 1, 6, 7], [43, 44, 42, 46, 45, 41, 40, 47],
	[12, 10, 13, 9, 11, 14, 8, 15], [37, 38, 32, 35, 34, 36, 39, 33], [23, 19, 20, 21, 18, 16, 17, 22],
	[24, 26, 31, 27, 30, 28, 25, 29], [55, 49, 50, 53, 54, 51, 52, 56]]
const ROLL_CHANCE := [0, 15, 10, 25, 13, 8, 22, 11, 7, 20, 9, 5, 18, 8, 2, 15, 7, 0, 12, 6, 0, 10, 5, 0]
const SPECIALTIES := ["Fire", "Battle", "Air", "Earth", "Ice", "Mech", "Filth"]


static func technique_roll(sim: CareSim, rng: DwRng) -> int:
	var d: Dictionary = sim.data.digimon[sim.p.id]
	var can := []
	for t in d["techniques"]:
		can.append(int(t["id"]))
	var best := -1
	var best_move := -1
	var slots: Array = d.get("specialty_slots", [])
	for s in 3:
		if s >= slots.size() or slots[s] == null:
			continue
		var cands: Array = ROLL_CANDIDATES[SPECIALTIES.find(slots[s])]
		for k in 8:
			var m: int = cands[k]
			if sim.p.techniques.has(m) or not can.has(m):
				continue
			var ch: int = ROLL_CHANCE[3 * k + s]
			if ch > best:
				best = ch
				best_move = m
			break
	if rng.rand(100) < best:
		sim.learn(best_move)
		return best_move
	return -1


## TRN::8008a284: costs plus one game hour of care effects. TRN2::8008ba80 differs only in the
## hunger (61) and feed-window (12) steps.
static func session_cost(sim: CareSim, tired: int, full: int, happy: int, hunger_step := 60,
		feed_step := 120) -> void:
	var p := sim.p
	var c := sim.care_row()
	p.tiredness += tired
	p.fullness -= full
	p.happiness -= happy
	if p.tiredness > 69:
		p.happiness -= 3
		p.discipline -= 3
	sim.tick += CareSim.TICKS_PER_HOUR
	sim.hour += 1
	if sim.hour > 23:
		sim.hour -= 24
		sim.tick -= CareSim.TICKS_PER_DAY
		p.age_days += 1
		sim.day += 1
		sim._new_day()                                   # TRN.c:661-664: FUN_800fc374 (CARE-25)
		if sim.day > 30:
			sim.day = 0
			sim.year = (sim.year + 1) % 100
	if sim.hour % 4 == 0 and p.happiness < 80:
		p.lifespan -= (80 - p.happiness) / 50 + 1
	if p.has(Partner.SLEEPY):
		p.sleepy_hours += 1
		p.sleepy_hours_total += 1
	if not p.has(Partner.HUNGRY):
		p.hunger_minutes -= hunger_step
	else:
		p.feed_window -= feed_step
		if p.feed_window < 1 and p.fullness < int(c["fullness_needed"]):
			p.care_mistakes += 1
	p.fullness -= int(c["fullness_drain_per_hour"])
	if not p.has(Partner.NEEDS_TOILET):
		p.poop_timer -= 6
	else:
		p.toilet_window -= CareSim.TICKS_PER_HOUR
	p.lifespan = maxi(p.lifespan - 1, 0)
	p.stage_hours += 1
	if p.has(Partner.INJURED):
		p.injured_hours += 1
	if p.has(Partner.SICK):
		p.sick_hours += 1
	sim.clamp_state()
