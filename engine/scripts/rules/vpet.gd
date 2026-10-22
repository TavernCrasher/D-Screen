class_name Vpet
extends RefCounted
## The desktop pet's care (not DW1's clock; docs/vpet_save.md sections 3 and 3a): hunger, meals,
## the toilet, piles, praise and scold, and training on the props, all on his own clock of active
## seconds (he's awake and you're at the PC), so nights and a switched-off PC cost nothing. What
## it changes goes into the totals of his file (vpet_NN.json, VpetSave.write_pet), which only rise;
## the game applies them when his save loads. Pure: the pet passes the time, the day and a DwRng.

## Rates v3 (the user, 2026-10-19: "0.75 h tops for everything"; docs/vpet_save.md 3a #9).
const HUNGER_EVERY := 15 * 60.0      # active s from a meal to the next hunger
const MISSED_AFTER := 45 * 60.0      # hungry this long unfed: a missed meal, then the next 45 min on
const POOP_DELAY := 10 * 60.0        # each meal's poop comes 10-20 active min after it
const POOP_SPREAD := 10 * 60
const TOILET_MAX := 120.0            # DW1's 12-72 min toilet window scaled into 2 min at most (the user, 9d 9)
const PILE_AFTER := 45 * 60.0        # a pile out this long costs, once for all the piles out then
## Praise and scold (rule 11, 3a #10). DW1's one "deserved" flag is the scold's (0x80134c59): set by
## an accident (main.c:9848-9851) or a refused item (9654-9660; the pet's only item is the Meat, and
## a refused meal never sets it), spent by the scold (9281-9283: it turns 1 into 2, which makes the
## next item be taken without a roll, 9650-9653; the pet has no refusal roll), cleared when the tamer moves
## (10593-10612). The pet has no tamer, so a time stands in. DW1's praise has no flag; the pet's
## counts after a finished Claude Code task.
const SCOLD_AFTER := 600.0           # active s after an accident in which a scold is deserved
const PRAISE_AFTER := 600.0          # active s after a finished Claude Code task in which a praise counts
const SESSIONS := 3                  # training sessions that count per station per day (rule 12)
const KEEP_DAYS := 14
const MAX_PILES := 20                # piles on the desktop at once (DW1's table holds 100; each is a window here)
## The most a day adds per key (rule 14); the stats are bounded by SESSIONS. Care mistakes at most 2
## (the user, 2026-10-19: unfed while you work, he missed a meal every 45 min, about 10 a workday,
## all of them applied to the DW1 save).
const DAY_CAP := {"happy_up": 5, "happy_down": 5, "disc_up": 5, "disc_down": 5, "weight_up": 3, "weight_down": 3,
	"care_mistakes": 2}
## The props he trains on: DW1's File City stations (training.gd GYMS order) and a desktop
## session's gain, an eighth of DW1's primary base gain (HP/MP 80 -> 10, a stat 8 -> 1; rule 12).
const STATIONS := {"boulder": {"stat": "max_hp", "gain": 10}, "waterfall": {"stat": "max_mp", "gain": 10},
	"log": {"stat": "off", "gain": 1}, "glove": {"stat": "def", "gain": 1},
	"track": {"stat": "spd", "gain": 1}, "chalkboard": {"stat": "brn", "gain": 1}}

## Events tick() returns.
const HUNGRY := "hungry"
const MISSED := "missed_meal"
const NEEDS_TOILET := "needs_toilet"
const ACCIDENT := "accident"
const PILE_LEFT := "pile_left"


## A new file for the link's partner (its id is random: a recreated file starts from zero in the
## game's merge). Without a link (Ninjamon, no save): the same in memory, never written.
static func fresh(link: Dictionary, now := 0.0) -> Dictionary:
	var out := _fresh(link, now)
	if link.has("card"):
		out["card"] = card_key(link["card"])
	return out


## A card file's path as his file keeps it (D-Screen): the same however it's spelled.
static func card_key(card) -> String:
	return str(card).replace("\\", "/").to_lower()


## His file belongs to another card than the link's: the same save in the same slot on a copied
## card has the same uid, and without this its totals were offered again there (9d 5).
static func other_card(d: Dictionary, link: Dictionary) -> bool:
	return link.has("card") and d.has("card") and card_key(d["card"]) != card_key(link["card"])


static func _fresh(link: Dictionary, now := 0.0) -> Dictionary:
	return {"format": VpetSave.FORMAT, "slot": int(link.get("slot", -1)),
		"file_id": Crypto.new().generate_random_bytes(8).hex_encode(), "seq": 0,
		"partner_uid": str(link.get("partner_uid", "")), "partner_id": int(link.get("partner_id", 0)),
		"totals": VpetSave.zeros(), "days": {},
		"live": {"clock": now, "hunger_at": now + HUNGER_EVERY, "hungry_since": -1.0, "poops": [],
			"toilet_since": -1.0, "weight_carry": 0.0, "accident_at": -1e9, "done_at": -1e9,
			"piles": [], "next_pile": 1}}


## The day his caps count in (the local date) at unix time `unix`, never earlier than the latest time
## his file has seen ("seen"): a clock set back can't open a new day and its fresh caps (the user,
## 2026-10-19; a clock set forward isn't caught: offline, nothing tells it from a real day).
static func day_of(d: Dictionary, unix: float) -> String:
	var t := maxf(unix, float(d.get("seen", 0.0)))
	d["seen"] = t
	return Time.get_date_string_from_unix_time(int(t) + int(Time.get_time_zone_from_system()["bias"]) * 60)


## His file as read (VpetSave.read_pet) for the link's partner: kept when it's his; a different
## partner (rebirth, a new game, another save, the same save on another card) moves the old totals
## to "previous", never applied. A file from before the card stamp takes the link's card.
static func adopt(d: Dictionary, link: Dictionary) -> Dictionary:
	if d.is_empty():
		return fresh(link)
	if str(d.get("partner_uid", "")) != str(link.get("partner_uid", "")) or other_card(d, link):
		var old := d.duplicate(true)
		old.erase("previous")
		var n := fresh(link)                        # a new file id: a zero baseline in the game
		n["seq"] = int(d.get("seq", 0))             # seq keeps rising, so the reader takes this copy
		n["seen"] = float(d.get("seen", 0.0))       # the clock guard carries over (day_of)
		n["previous"] = old
		return n
	var id := int(link.get("partner_id", d.get("partner_id", 0)))
	if id != int(d.get("partner_id", id)):
		# he evolved in the game: DW1's evolution resets weight and care mistakes (main.c:8941-8942),
		# so what the totals hold so far never applies to the new form (VpetSave.pending, PET-9)
		var ev := {}
		for k in ["weight_up", "weight_down", "care_mistakes"]:
			ev[k] = int(d["totals"].get(k, 0))
		d["evolved"] = ev
	d["partner_id"] = id
	if link.has("card"):
		d["card"] = card_key(link["card"])
	var f := fresh(link)                            # a file from before the care side: its clock starts now
	for k in ["days", "live"]:
		if not d.get(k) is Dictionary:
			d[k] = f[k]
	var lv: Dictionary = d["live"]
	if not lv.has("poops"):                         # a v2 file: its one poop timer becomes the list
		if float(lv.get("toilet_at", -1.0)) >= 0.0:
			lv["poops"] = [float(lv["toilet_at"])]
		elif float(lv.get("toilet_since", -1.0)) >= 0.0:
			lv["poops"] = [float(lv["toilet_since"])]
		elif int(lv.get("meals", 0)) > 0:           # meals not yet pooped: one poop for them (CARE3-6)
			lv["poops"] = [float(lv.get("clock", 0.0)) + POOP_DELAY]
	lv.erase("toilet_at")
	lv.erase("meals")
	lv.erase("praised_at")
	for k in f["live"]:
		if not (d["live"] as Dictionary).has(k):
			d["live"][k] = f["live"][k]
	for k in VpetSave.KEYS:
		if not (d["totals"] as Dictionary).has(k):
			d["totals"][k] = 0
	return d


## Meals per poop in DW1's terms: his average poop loss, (rand(4) + poop_size) / 4 (FUN_800a8100),
## so a meal's +1 evens out (3a #1): Ninjamon (size 8) 2, size 15 4. Each meal now brings its own
## poop, so a toilet poop costs one meal's share of DW1's loss, a third of it (3a #9).
static func meals_per_poop(poop_size: int) -> int:
	var sum := 0
	for r in 4:
		sum += (r + poop_size) / 4
	return maxi(1, roundi(sum / 4.0))


## DW1's poop weight loss (FUN_800a8100, main.c:9920-9934).
static func poop_loss(rng: DwRng, poop_size: int) -> int:
	return (rng.rand(4) + poop_size) / 4


## His discipline now: the save's (the link's base) and what the desktop added since the game last
## applied his totals.
static func discipline(d: Dictionary, link: Dictionary) -> int:
	return clampi(int((link.get("base", {}) as Dictionary).get("discipline", 50)) + unapplied(d, link, "disc"), 0, 100)


## What the desktop moved a meter ("happy", "disc", "weight") beyond what the game applied: the
## save's applied totals count only when they are this file's (the link's applied_file_id, PET-20).
static func unapplied(d: Dictionary, link: Dictionary, meter: String) -> int:
	var t: Dictionary = d["totals"]
	var a: Dictionary = link.get("applied", {}) if str(link.get("applied_file_id", "")) == str(d.get("file_id", "")) else {}
	return maxi(0, int(t[meter + "_up"]) - int(a.get(meter + "_up", 0))) \
		- maxi(0, int(t[meter + "_down"]) - int(a.get(meter + "_down", 0)))


## DW1's toilet window, (discipline + 20)% of an hour (main.c:9828-9855), 12-72 min, scaled so
## discipline 100 is TOILET_MAX: 20-120 s on his clock (was 7.5-45 min: Doug's partner "had to poop
## for ages"; the user: 2 minutes holding it at most, 2026-10-21, 9d 9).
static func toilet_window(disc: int) -> float:
	return (disc + 20) * TOILET_MAX / 120.0


static func poop_size(link: Dictionary) -> int:
	return int((link.get("care", {}) as Dictionary).get("poop_size", 8))


static func is_hungry(d: Dictionary) -> bool:
	return float(d["live"]["hungry_since"]) >= 0.0


## Due: a meal's poop is waiting, so the toilet works (before he asks for it, too).
static func toilet_due(d: Dictionary) -> bool:
	return not (d["live"]["poops"] as Array).is_empty()


static func needs_toilet(d: Dictionary) -> bool:
	return float(d["live"]["toilet_since"]) >= 0.0


## Adds n to a total within the day's cap; returns what was added.
static func add(d: Dictionary, key: String, n: int, today: String) -> int:
	if n <= 0:
		return 0
	var day: Dictionary = (d["days"] as Dictionary).get(today, {})
	if DAY_CAP.has(key):
		n = mini(n, int(DAY_CAP[key]) - int(day.get(key, 0)))
		if n <= 0:
			return 0
	day[key] = int(day.get(key, 0)) + n
	d["days"][today] = day
	d["totals"][key] = int(d["totals"][key]) + n
	_prune(d)
	return n


## Weight in fractions (3a #9): a third of a point a meal, the toilet's share off; whole points
## reach the totals as they add up, so a balanced day moves nothing.
static func add_weight(d: Dictionary, n: float, today: String) -> void:
	var live: Dictionary = d["live"]
	var c := float(live.get("weight_carry", 0.0)) + n
	while c >= 1.0 - 1e-6:
		add(d, "weight_up", 1, today)
		c -= 1.0
	while c <= -1.0 + 1e-6:
		add(d, "weight_down", 1, today)
		c += 1.0
	live["weight_carry"] = 0.0 if absf(c) < 1e-6 else c


static func _prune(d: Dictionary) -> void:
	var days: Array = (d["days"] as Dictionary).keys()
	if days.size() <= KEEP_DAYS:
		return
	days.sort()
	for k in days.slice(0, days.size() - KEEP_DAYS):
		d["days"].erase(k)


## Advances his clock by dt active seconds (the pet passes 0 while he sleeps or you're away).
## Returns the events that happened, in order; `x`, `y` are his feet (for an accident's pile).
static func tick(d: Dictionary, link: Dictionary, dt: float, today: String, rng: DwRng, x := 0.0, y := 0.0) -> Array:
	var live: Dictionary = d["live"]
	var out := []
	live["clock"] = float(live["clock"]) + maxf(0.0, dt)
	var now: float = live["clock"]
	if not is_hungry(d) and now >= float(live["hunger_at"]):
		live["hungry_since"] = now
		out.append(HUNGRY)
	elif is_hungry(d) and now - float(live["hungry_since"]) >= MISSED_AFTER:
		live["hungry_since"] = now                  # still hungry; the next miss 45 min on
		add(d, "happy_down", 2, today)
		add(d, "disc_down", 1, today)
		add(d, "care_mistakes", 1, today)
		out.append(MISSED)
	# a pile out PILE_AFTER is left too long (3a #8, settled #4: an uncleaned poop lowers happiness
	# and discipline a little): one charge for all the piles out then (3a #9); its virus came with
	# the accident
	var late := false
	for p in live["piles"]:
		late = late or (not p["charged"] and now - float(p["since"]) >= PILE_AFTER)
	if late:
		for p in live["piles"]:
			p["charged"] = true
		add(d, "happy_down", 2, today)
		add(d, "disc_down", 2, today)
		out.append(PILE_LEFT)
	var poops: Array = live["poops"]
	if not poops.is_empty() and not needs_toilet(d) and now >= float(poops[0]):
		# each poop's window runs from its own due time, not from when the one before it was settled
		# (3a #9: two meals at 10:30, two poops by 10:50; CARE3-1)
		live["toilet_since"] = float(poops[0])
		out.append(NEEDS_TOILET)
	elif needs_toilet(d) and now - float(live["toilet_since"]) >= toilet_window(discipline(d, link)):
		# the window ran out: an accident, a pile beside him. With the toilet there to give him, a
		# missed window costs at once (3a #8; the user, 2026-10-18, PET-12), and the pile is a poop
		# not made at a toilet: virus +1 (DW1's counter, main.c:9487)
		add(d, "weight_down", poop_loss(rng, poop_size(link)), today)
		add(d, "happy_down", 2, today)
		add(d, "disc_down", 2, today)
		if int(link.get("partner_id", 0)) != CareSim.SUKAMON:   # DW1 never raises it on Sukamon (main.c:9486)
			add(d, "virus", 1, today)
		_poop_done(live)
		live["accident_at"] = now
		if (live["piles"] as Array).size() < MAX_PILES:
			live["piles"].append({"id": int(live["next_pile"]), "x": x, "y": y, "since": now, "charged": false})
			live["next_pile"] = int(live["next_pile"]) + 1
		out.append(ACCIDENT)
	return out


## One meal's poop is done; the next one's timer (if any) runs on.
static func _poop_done(live: Dictionary) -> void:
	(live["poops"] as Array).pop_front()
	live["toilet_since"] = -1.0


## A meal (the Meat dropped on him). Not hungry: he refuses it, nothing changes (rule 4). Each
## meal sets its own poop 10-20 active min later (3a #9: two meals at 10:30, two poops by 10:50).
static func feed(d: Dictionary, today: String, rng: DwRng) -> bool:
	if not is_hungry(d):
		return false
	var live: Dictionary = d["live"]
	live["hungry_since"] = -1.0
	live["hunger_at"] = float(live["clock"]) + HUNGER_EVERY
	add_weight(d, 1.0 / 3.0, today)                 # a third of DW1's Meat (data/food_effects.json)
	var poops: Array = live["poops"]
	var at := float(live["clock"]) + POOP_DELAY + rng.rand(POOP_SPREAD + 1)
	poops.append(maxf(at, float(poops[-1])) if not poops.is_empty() else at)
	return true


## The toilet: he goes only when due; a third of one meal's share of DW1's poop loss, never more
## than the meal's third (so a cared-for day never drifts down), happiness and discipline +1 (half
## of FUN_800a806c's +2/+2, rule 8).
static func use_toilet(d: Dictionary, link: Dictionary, today: String, rng: DwRng) -> bool:
	if not toilet_due(d):
		return false
	var size := poop_size(link)
	add_weight(d, -minf(1.0 / 3.0, poop_loss(rng, size) / float(meals_per_poop(size)) / 3.0), today)
	add(d, "happy_up", 1, today)
	add(d, "disc_up", 1, today)
	_poop_done(d["live"])
	return true


## A click on a pile cleans it. Returns false if there was none with that id.
static func clean(d: Dictionary, id: int) -> bool:
	var piles: Array = d["live"]["piles"]
	for i in piles.size():
		if int(piles[i]["id"]) == id:
			piles.remove_at(i)
			return true
	return false


## A Claude Code task finished (the hook's Stop): a praise now counts.
static func task_done(d: Dictionary) -> void:
	d["live"]["done_at"] = d["live"]["clock"]


static func praise_counts(d: Dictionary) -> bool:
	var live: Dictionary = d["live"]
	return float(live["clock"]) - float(live["done_at"]) <= PRAISE_AFTER


static func scold_deserved(d: Dictionary) -> bool:
	var live: Dictionary = d["live"]
	return float(live["clock"]) - float(live["accident_at"]) <= SCOLD_AFTER


## Praise: happiness +1 within PRAISE_AFTER of a finished task, once per task; otherwise nothing.
## Returns what it added (0 also when the day's cap is full).
static func praise(d: Dictionary, today: String) -> int:
	if not praise_counts(d):
		return 0
	d["live"]["done_at"] = -1e9
	return add(d, "happy_up", 1, today)


## Scold: discipline +1 when deserved (within SCOLD_AFTER of an accident, DW1's flag), spent by
## it as in DW1; otherwise nothing (rule 11).
static func scold(d: Dictionary, today: String) -> int:
	if not scold_deserved(d):
		return 0
	d["live"]["accident_at"] = -1e9
	return add(d, "disc_up", 1, today)


## A session on a station prop: {stat, gain (what reached his totals), why: "" | "frozen" |
## "enough"}. He trains either way; only SESSIONS a day count on each station (3a #9), none while
## a declined offer waits in the game (3a #3: the link's "declined").
static func train(d: Dictionary, link: Dictionary, station: String, today: String) -> Dictionary:
	var s: Dictionary = STATIONS[station]
	var out := {"stat": s["stat"], "gain": 0, "why": ""}
	var day: Dictionary = (d["days"] as Dictionary).get(today, {})
	var key := "sessions_" + station
	if bool(link.get("declined", false)):
		out["why"] = "frozen"
	elif int(day.get(key, 0)) >= SESSIONS:
		out["why"] = "enough"
	else:
		day[key] = int(day.get(key, 0)) + 1
		d["days"][today] = day
		out["gain"] = add(d, str(s["stat"]), int(s["gain"]), today)
	return out
