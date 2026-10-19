class_name EvoForecast
extends RefCounted
## The desktop pet's evolution hint (not DW1: DW1 has no forecast; the user's final polish,
## 2026-10-18). DW1's own pick (Evolution.choose / choose_by_stats, as CareSim._evolution_timer
## runs them) on the save's partner as the link last saw him plus what the desktop added since
## (capped as the game's merge caps it, VpetSave.MERGE_CAP):
## - "ready": DW1 would pick a form now, so he evolves once his stage timer passes (or at the
##   next hour if it already has);
## - "close": no form yet, but one scores 2 and only its stats are missing, each at least
##   CLOSE of what it asks; "stat" names the one furthest behind (VpetSave.LABELS key);
## - "none": neither, or he can't evolve by stats (Fresh: one fixed form; Ultimate: specials only).
## Links written before 2026-10-18 lack care mistakes, battles, virus and the raised flags: no hint.
## Virus over 15 (what the game would make of him: Sukamon) gives no hint either.

const CLOSE := 0.8
const SUKAMON_VIRUS := 15               # virus above this: the next check makes him Sukamon
## The stat keys in Evolution.STATS order.
const KEYS := ["max_hp", "max_mp", "off", "def", "spd", "brn"]


## A story stub for Evolution.score's raised flags (CareSim.RAISED_TRIGGER + id).
class Raised:
	var ids: Array = []

	func is_set(t: int) -> bool:
		return (t - CareSim.RAISED_TRIGGER) in ids


## The partner the game would load: the link's values + what the pet's file would add on that load,
## by the game's own merge (VpetSave.pending: capped, applied totals not counted twice, weight and
## care mistakes from before an evolution dropped; PET-33). d: his file ({} without one).
static func partner(link: Dictionary, d: Dictionary) -> Partner:
	var b: Dictionary = link.get("base", {})
	var p := Partner.new()
	p.id = int(link.get("partner_id", 0))
	p.uid = str(link.get("partner_uid", ""))
	for k in KEYS:
		p.set(k, int(b.get(k, 1)))
	p.weight = int(b.get("weight", 1))
	p.happiness = int(b.get("happiness", 50))
	p.discipline = int(b.get("discipline", 50))
	p.care_mistakes = int(link.get("care_mistakes", 0))
	p.virus = int(link.get("virus", 0))
	p.battles = int(link.get("battles", 0))
	p.stage_hours = int(link.get("stage_hours", 0))
	p.techniques = (link.get("techniques", []) as Array).duplicate()
	var m := VpetSave.pending({"consumed": link.get("applied", {}), "file_id": link.get("applied_file_id", "")}, d, p)
	if m["state"] == "pending":                  # as VpetSave.apply, without a CareSim
		var dl: Dictionary = m["deltas"]
		for k in KEYS:
			p.set(k, mini(int(p.get(k)) + int(dl[k]), int(VpetSave.STAT_MAX[k])))
		p.happiness = clampi(p.happiness + int(dl["happy_up"]) - int(dl["happy_down"]), -100, 100)
		p.discipline = clampi(p.discipline + int(dl["disc_up"]) - int(dl["disc_down"]), 0, 100)
		p.weight = maxi(1, p.weight + int(dl["weight_up"]) - int(dl["weight_down"]))
		p.care_mistakes += int(dl["care_mistakes"])
		p.virus += int(dl["virus"])
	return p


## {state: "ready" | "close" | "none", target (ready / close: the form's id), stat (close)}.
static func forecast(data, link: Dictionary, d: Dictionary) -> Dictionary:
	var none := {"state": "none", "target": -1, "stat": ""}
	if not link.has("care_mistakes") or data.evolution.is_empty():
		return none
	var p := partner(link, d)
	var lv: int = data.level_of(p.id)
	if lv < 2 or lv > 4 or p.virus > SUKAMON_VIRUS:   # CareSim._evolution_timer: Sukamon instead (PET-33)
		return none
	var story := Raised.new()
	story.ids = (link.get("raised", []) as Array).map(func(v): return int(v))   # a JSON link's are floats (DS8-5)
	var target := Evolution.choose(data, p, story) if lv == 2 else Evolution.choose_by_stats(data, p, false, story)
	if target != -1:
		return {"state": "ready", "target": target, "stat": ""}
	# close: a form one point short, the point being its stats
	var best := none
	var best_gap := INF
	var have := [p.max_hp / 10, p.max_mp / 10, p.off, p.def, p.spd, p.brn]
	for t in data.evolution.get(p.id, {}).get("to", []):
		var t_id := int(t)
		if t_id <= 0 or t_id >= data.digimon.size() or Evolution.score(data, p, t_id) != 2:
			continue
		var r: Dictionary = data.evolution[t_id]["requirements"]
		var gap := 0.0
		var worst := -1
		var worst_gap := 0.0
		if data.level_of(t_id) == 3:
			# a Rookie wants a flagged stat to be his highest: the flagged one nearest the top
			var top: int = have.max()
			for i in 6:
				if _need(r, i) == 1:
					var g := 1.0 - float(have[i]) / maxf(1.0, top)
					if worst == -1 or g < worst_gap:
						worst = i
						worst_gap = g
			gap = worst_gap
		else:
			for i in 6:
				var need := _need(r, i)
				if need <= 0 or have[i] >= need:
					continue
				var g := 1.0 - float(have[i]) / need
				gap += g
				if g > worst_gap:
					worst = i
					worst_gap = g
		if worst == -1 or worst_gap > 1.0 - CLOSE or Evolution.score(data, _with_stats(p, r, data.level_of(t_id)), t_id) < 3:
			continue
		if gap < best_gap:
			best_gap = gap
			best = {"state": "close", "target": t_id, "stat": KEYS[worst]}
	return best


## A stat requirement as Evolution.score compares it (HP/MP /10), -1 none.
static func _need(r: Dictionary, i: int) -> int:
	var n := Evolution._req(r, Evolution.STATS[i])
	return n / 10 if n != -1 and i < 2 else n


## p with the target's stat point met (a check that the stats are the only missing point).
static func _with_stats(p: Partner, r: Dictionary, target_level: int) -> Partner:
	var q := Partner.new()
	for prop in ["id", "weight", "happiness", "discipline", "care_mistakes", "battles", "techniques"]:
		q.set(prop, p.get(prop))
	var top := -1                                  # a Rookie: the first flagged stat made the highest
	for i in 6:
		if target_level == 3 and top == -1 and _need(r, i) == 1:
			top = i
	for i in 6:
		var need := _need(r, i)
		var v: int = p.get(KEYS[i])
		if target_level == 3:
			v = 9999 if i == top else 1
		elif need > 0:
			v = maxi(v, need * (10 if i < 2 else 1))
		q.set(KEYS[i], v)
	return q
