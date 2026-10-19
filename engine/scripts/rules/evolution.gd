class_name Evolution
extends RefCounted
## Evolution scoring: FUN_800e26b8 (score one candidate); FUN_800e2598 picks the best score
## (In-Training), FUN_800e2bb4 / FUN_800e2f08 pick by required-stat average (Rookie / Champion).
## The scorer's last step weighs the "raised" story flags (0x200 + id, CareSim.RAISED_TRIGGER).


## Fresh -> In-Training: FUN_800e2544 is not decoded; the graph has one target per Fresh form.
static func fresh_target(data, id: int) -> int:
	var e: Dictionary = data.evolution.get(id, {})
	var to: Array = e.get("to", [])
	return int(to[0]) if not to.is_empty() else -1


static func _req(r: Dictionary, key: String) -> int:
	var v = r.get(key)
	return -1 if v == null else int(v)


## Score for evolving partner p into target (0-4). Evolves at >= 3. main.c:34025: against the
## caller's best candidate so far (`best_so_far`, -1 none), a score above 2 drops to 0 if the
## target was raised before and that one wasn't, and gains 1 if that one was and the target wasn't.
static func score(data, p: Partner, target: int, story = null, best_so_far := -1) -> int:
	var e: Dictionary = data.evolution.get(target, {})
	if e.is_empty():
		return 0
	var r: Dictionary = e["requirements"]
	var s := 0
	# care mistakes (max if flagged, else min)
	var cm := _req(r, "care_mistakes")
	if r["care_mistakes_is_max"]:
		s += 1 if p.care_mistakes <= cm else 0
	else:
		s += 1 if cm <= p.care_mistakes else 0
	# weight within +-5
	var w := _req(r, "weight")
	if w - 5 <= p.weight and p.weight <= w + 5:
		s += 1
	# stats; HP/MP are stored /10 (the export multiplied them back by 10)
	var req := [_req(r, "hp"), _req(r, "mp"), _req(r, "offense"), _req(r, "defense"),
		_req(r, "speed"), _req(r, "brains")]
	for i in 2:
		if req[i] != -1:
			req[i] /= 10
	var have := [p.max_hp / 10, p.max_mp / 10, p.off, p.def, p.spd, p.brn]
	if data.level_of(target) == 3:
		# Rookie: the partner's highest stat (ties -> later stat) must be flagged 1
		var best := 0
		for i in 6:
			var is_max := true
			for j in 6:
				if have[i] < have[j]:
					is_max = false
			if is_max:
				best = i
		s += 1 if req[best] == 1 else 0
	else:
		var ok := true
		for i in 6:
			if req[i] > have[i]:
				ok = false
		s += 1 if ok else 0
	# bonus: any one condition
	var bonus := false
	var bd := _req(r, "bonus_digimon")
	if bd != -1 and bd == p.id:
		bonus = true
	var disc := _req(r, "bonus_discipline")
	if disc != -1 and disc <= p.discipline:
		bonus = true
	var happ := _req(r, "bonus_happiness")
	if happ != -1 and happ <= p.happiness:
		bonus = true
	var bat := _req(r, "bonus_battles")
	if bat != -1:
		if r["bonus_battles_is_max"]:
			bonus = bonus or p.battles <= bat
		else:
			bonus = bonus or bat <= p.battles
	var techs := _req(r, "bonus_techniques")
	if techs != -1 and techs <= p.techniques.size():
		bonus = true
	s += 1 if bonus else 0
	if s > 2 and best_so_far != -1 and story != null:
		var raised: bool = story.is_set(CareSim.RAISED_TRIGGER + target)
		var best_raised: bool = story.is_set(CareSim.RAISED_TRIGGER + best_so_far)
		if raised and not best_raised:
			s = 0
		elif best_raised and not raised:
			s += 1
	return s


const NUMEMON := 11
const STATS := ["hp", "mp", "offense", "defense", "speed", "brains"]


## FUN_800e2bb4 (Rookie, numemon_fallback) / FUN_800e2f08 (Champion): among candidates scoring
## above 2, the one whose required stats (HP/MP counted /10) the partner has the highest
## average in wins. Vanilla only resets the running sum and count when a new best is found, so
## a losing candidate's stats carry into the next average; kept as is. A Rookie without a
## winner turns into Numemon once its stage timer passes 95 hours.
static func choose_by_stats(data, p: Partner, numemon_fallback := false, story = null) -> int:
	var e: Dictionary = data.evolution.get(p.id, {})
	var have := [p.max_hp / 10, p.max_mp / 10, p.off, p.def, p.spd, p.brn]
	var best := -1
	var best_avg := 0
	var total := 0
	var count := 0
	for t in e.get("to", []):
		var t_id := int(t)
		if t_id <= 0 or t_id >= data.digimon.size():
			continue
		if score(data, p, t_id, story, best) <= 2:
			continue
		var r: Dictionary = data.evolution.get(t_id, {}).get("requirements", {})
		for i in 6:
			if _req(r, STATS[i]) != -1:
				total += have[i]
				count += 1
		var avg: int = total / count if count > 0 else 0
		if best_avg < avg:
			best_avg = avg
			total = 0
			count = 0
			best = t_id
	if best == -1 and numemon_fallback and p.stage_hours > 95:
		best = NUMEMON
	return best


## FUN_800e2598: best-scoring "to" candidate with score >= 3, else -1.
static func choose(data, p: Partner, story = null) -> int:
	var e: Dictionary = data.evolution.get(p.id, {})
	var best := -1
	var best_score := 0
	for t in e.get("to", []):
		var t_id := int(t)
		if t_id <= 0 or t_id >= data.digimon.size():
			continue
		var sc := score(data, p, t_id, story, best)
		if sc > best_score and sc > 2:
			best = t_id
			best_score = sc
	return best
