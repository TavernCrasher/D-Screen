class_name CareSim
extends RefCounted
## DW1 game clock + partner care simulation, ported from the decompiled code.
## One step() = one DW1 tick (20 ticks = 1 game minute, 20 ticks per real second).
## Function names in comments refer to docs/care_simulation.md.

signal event(name: String, info: Dictionary)

const TICKS_PER_MINUTE := 20
const TICKS_PER_HOUR := 1200
const TICKS_PER_DAY := 28800
const SUKAMON := 39
const LEARNABLE := 0x3A           # technique ids 0-0x39 live in the learned-moves bitfield
## FUN_800e5f14: these moves share their learned bit, so learning one learns both
const PAIRED_MOVES := {0x2C: 0x30, 0x30: 0x2C, 0x37: 0x39, 0x39: 0x37}
const RAISED_TRIGGER := 0x200     # + Digimon id (< 0x3F): raised once (FUN_800ff7f8; medal 6)
## FUN_800a5198: starting stats per Fresh Digimon (HP, MP, Off, Def, Spd, Brains)
const BABY_STATS := {1: [90, 110, 10, 11, 9, 10], 15: [120, 100, 16, 8, 8, 6],
	29: [100, 140, 12, 6, 6, 8], 43: [100, 120, 8, 8, 8, 8]}

var data                          # GameData (autoload or test instance)
var rng: DwRng
var p: Partner = Partner.new()

# clock (0x80134F08 / EBC / EBE / F04 / F02)
var tick := 9600
var hour := 8
var minute := 0
var day := 0
var year := 0
var climate := 0                  # 0x80150C3E: 1 comfortable area, 2 uncomfortable (set by the map)
var inventory := Inventory.new()  # the tamer's bag (main.gd shares it with StoryState)
var walk_frames := 0              # 0x80134E26
var pending_evolution := -1
var scold_flag := 0               # ITEM_SCOLD_FLAG 0x80134c59 (see items.gd refuses())
var map_id := -1                 # CURRENT_SCREEN 0x80134da8 (set by the field on map entry)
var nanimon_flag := false         # 0x80134c64: set by scolding a miserable Rookie
var tamer_level := 0             # 0x801557A4, 0-10 (FUN_800acbf4); rebirth inherits it as %
var sukamon_backup: Array = []    # 0x801384D6..E0: max HP/MP, Off, Def, Spd, Brn before Sukamon
var woke_hour := -1               # 0x80134ca4 (with flag ca8): the hour the partner woke up in;
								  # evolution, death and sick-death wait until it has passed


func _init(game_data, rng_: DwRng = null) -> void:
	data = game_data
	rng = rng_ if rng_ else DwRng.new()


func care_row() -> Dictionary:
	return data.care[p.id]


func level() -> int:
	return data.level_of(p.id)


func periodic(n: int) -> bool:
	return tick % n == 0


# ---------------------------------------------------------------- new partner
## FUN_800e5f14: learn a technique (and its paired move).
func learn(move: int) -> void:
	for t in [move, PAIRED_MOVES.get(move, -1)]:
		if t != -1 and not p.techniques.has(t):
			p.techniques.append(t)


## FUN_800a442c: hatch / start raising a Digimon.
func new_partner(id: int) -> void:
	p = Partner.new()
	p.id = id
	p.uid = Crypto.new().generate_random_bytes(8).hex_encode()   # the v-pet's partner check
	var c := care_row()
	_init_schedule()                                   # FUN_800a4750
	p.sleepy_hours_total = 0
	p.poop_timer = int(c["poop_timer"])
	p.toilet_window = -1
	p.virus = 0
	p.tiredness = 0
	p.discipline = 50
	p.happiness = 50
	next_hunger()                                     # FUN_800a4a08
	p.fullness = int(c["fullness_needed"])
	p.lifespan = 360
	p.weight = int(c["base_weight"])
	# the species' first move is equipped (Gabumon: index 2, Sonic Jab) and learned if it's a
	# learnable one (not a baby's bubble); the finisher is the species' (Techniques)
	p.techniques = []
	var list := Techniques.species_moves(data, id)
	var first: int = list[0] if not list.is_empty() else -1
	if id == 17 and list.size() > 2:
		first = list[2]
	if first >= 0 and first < LEARNABLE:
		learn(first)
	p.moves = [first, -1, -1, Techniques.finisher_for(data, id)]


## Script op 0x37: jump the clock to (year, day, hour, minute), skipping the whole hours in
## between at once (FUN_800a8ae4) when the target is later.
func wait_until(y: int, d: int, h: int, m: int) -> void:
	var goal := ((y * 30 + d) * 24 + h) * 60 + m
	var now := ((year * 30 + day) * 24 + hour) * 60 + minute
	if now < goal:
		skip_hours((goal - now) / 60)
	year = y
	var changed := day != d
	day = d
	if changed:                                      # op 0x37 (main.c:51947): FUN_800fc374
		_new_day()
	hour = h
	minute = m
	tick = hour * 1200 + minute * 20


## FUN_800a8ae4: n hours pass at once (stage, lifespan, age; the happiness lifespan drain if
## it lands on an hour divisible by 4; sleepy, hunger/feeding, poop/toilet, sick and injured
## counters).
func skip_hours(n: int) -> void:
	var c := care_row()
	p.stage_hours += n
	p.lifespan -= n
	if hour + n > 23:
		p.age_days += (hour + n) / 24
	var r := n % 4                                       # C remainder
	if hour + r == 0 and p.happiness < 80:
		p.lifespan -= (80 - p.happiness) / 50 + 1
	p.lifespan = maxi(p.lifespan, 0)
	if p.has(Partner.SLEEPY):
		p.sleepy_hours += n
		p.sleepy_hours_total += n
	if not p.has(Partner.HUNGRY):
		p.hunger_minutes -= n * 60
	else:
		p.feed_window -= n * 120
		if p.feed_window < 1 and p.fullness < int(c["fullness_needed"]):
			p.care_mistakes += 1
	p.fullness -= int(c["fullness_drain_per_hour"])
	if not p.has(Partner.NEEDS_TOILET):
		p.poop_timer -= n * 6
	else:
		p.toilet_window -= 1200
	if p.has(Partner.SICK):
		p.sick_roll += n
		p.sick_hours += n
	if p.has(Partner.INJURED):
		p.injured_hours += n


## FUN_800a4750: sleep schedule for the current Digimon.
func _init_schedule() -> void:
	var s: Dictionary = care_row()["sleep_schedule"]
	if level() < 3:
		var awake := (3 if level() == 1 else 7) + rng.rand(1)
		p.sleep_h = (hour + awake) % 24
		p.sleep_m = 0
		p.wake_h = (p.sleep_h + int(s["sleep_hours"])) % 24
		p.wake_m = 0
		p.awake_hours = awake
		p.sleep_hours = int(s["sleep_hours"])
	else:
		p.sleep_h = int(s["sleep"].split(":")[0])
		p.sleep_m = int(s["sleep"].split(":")[1])
		p.wake_h = int(s["wake"].split(":")[0])
		p.wake_m = int(s["wake"].split(":")[1])
		p.awake_hours = int(s["awake_hours"])
		p.sleep_hours = int(s["sleep_hours"])
	p.bedtime_shift = p.awake_hours * 6
	p.sleepy_hours = 0
	p.bedtime_accum = 0


## Next sleep window after waking (shared by FUN_800a5804 and FUN_800a63dc).
func _reschedule() -> void:
	if level() < 3:
		p.sleep_h = (p.wake_h + p.awake_hours) % 24
		p.sleep_m = 0
		p.wake_h = (p.sleep_h + p.sleep_hours) % 24
		p.wake_m = 0
	else:
		var s: Dictionary = care_row()["sleep_schedule"]
		p.sleep_h = int(s["sleep"].split(":")[0])
		p.sleep_m = int(s["sleep"].split(":")[1])
		p.wake_h = int(s["wake"].split(":")[0])
		p.wake_m = int(s["wake"].split(":")[1])


## FUN_800a4a08: next hunger hour and minutes until then.
## Simplified for Rookie+: first listed hour after the current hour, else the first one.
func next_hunger() -> void:
	match level():
		1:
			p.next_hunger_hour = (hour / 2) * 2 + 2
		2:
			p.next_hunger_hour = (hour / 3) * 3 + 3
		_:
			var hours: Array = care_row()["hunger_hours"]
			p.next_hunger_hour = int(hours[0]) if not hours.is_empty() else hour
			for h in hours:
				if int(h) > hour:
					p.next_hunger_hour = int(h)
					break
	if p.next_hunger_hour > 23:
		p.next_hunger_hour -= 24
	if p.next_hunger_hour < hour:
		p.hunger_minutes = (24 - hour) * 60 + p.next_hunger_hour * 60 - minute
	else:
		p.hunger_minutes = (p.next_hunger_hour - hour) * 60 - minute


# ---------------------------------------------------------------- the tick
## One frame of field time: clock (FUN_800dcf88) then the care tick (FUN_800a8f38).
func step() -> void:
	_advance_clock()
	_care_tick()


func _advance_clock() -> void:
	tick += 1
	if tick % TICKS_PER_MINUTE != 0:
		return
	minute += 1
	if minute < 60:
		return
	minute = 0
	hour += 1
	p.stage_hours += 1
	p.lifespan = maxi(p.lifespan - 1, 0)
	if hour == 24:
		hour = 0
		tick = 0
		p.age_days += 1
		day += 1
		_new_day()                    # FUN_800fc374 (main.c:31478)
		if day > 29:
			day = 0
			year = (year + 1) % 100
			if p.happiness == 100:                     # main.c:31485
				add_tamer_level(5, 1)
			elif p.happiness < 0:
				add_tamer_level(10, -1)


func _care_tick() -> void:
	if woke_hour != -1 and hour != woke_hour:
		woke_hour = -1
	if p.lifespan < 1 and woke_hour == -1:             # FUN_800a8a3c
		if not dead:
			dead = true
			natural_death = true                       # IS_NATURAL_DEATH 0x80134c4c
			event.emit("death", {"reason": "lifespan"})   # main.gd runs event 0x4DE once
		return
	_sleep_tick()
	_sickness_tick()
	_tiredness_tick()
	_hunger_tick()
	_sulk_tick()
	_poop_tick()                                       # FUN_800a7d68
	clamp_state()
	p.area_ticks += 1
	if p.area_ticks > TICKS_PER_DAY:
		p.area_ticks = 0
	p.boost_ticks -= 1
	if p.boost_ticks < 1:
		p.boost_mask = 0
		p.boost_ticks = 0
	if periodic(4800) and p.happiness < 80:            # unhappiness shortens life
		p.lifespan = maxi(p.lifespan - ((80 - p.happiness) / 50 + 1), 0)
	if woke_hour == -1 and not hold_evolution:        # FUN_800d7618: not during a day/night fade
		_evolution_timer()


## Map load (main.c ~28138): liked (1) / disliked (2) area when a slot matches the habitat
## byte (care table +0x13, "unk_13"), liked checked before disliked in each slot; the area
## timer restarts (FUN_800a5604).
func enter_area(liked: Array, disliked: Array) -> void:
	var pref := int(care_row().get("unk_13", -2))
	climate = 0
	for i in 4:
		if i < liked.size() and int(liked[i]) == pref:
			climate = 1
			break
		if i < disliked.size() and int(disliked[i]) == pref:
			climate = 2
			break
	p.area_ticks = 0


## Clock only: time passes while a care action runs (DW1's care tick needs partner state 1,
## FUN_800a8f38 checks DAT_80134c5b == 1).
func clock_only() -> void:
	_advance_clock()


var dead := false                 # lifespan ran out; waits for the death event (0x4DE)
var natural_death := false        # IS_NATURAL_DEATH 0x80134c4c: only the lifespan check sets it
var story = null                  # StoryState (main sets it): the hunger tick writes trigger 640
var hold_evolution := false       # a day/night transition is running (main sets it, FIELD-15)


## A new day: DW1's daily rollover FUN_800fc374 (daily cards, day counters pstats 28-31).
func _new_day() -> void:
	event.emit("new_day", {})
	if story != null:
		Services.daily_rollover(story, rng)
var raised_count := 0             # 0x801557a5: Digimon raised, +1 per rebirth (max 99)


## FUN_800a5804
func _sleep_tick() -> void:
	var was_awake := not p.has(Partner.SLEEPY)
	if periodic(20):
		p.bedtime_accum += p.tiredness * 3 / 10
	if was_awake and p.bedtime_accum > 179 and periodic(200):
		# tiredness pulls bedtime earlier in 10-minute steps
		p.bedtime_shift -= 1
		p.bedtime_accum = 0
		var i4 := p.awake_hours * 6 - p.bedtime_shift
		var c := i4 / 6 + (1 if i4 % 6 != 0 else 0)
		p.sleep_h = p.wake_h - p.sleep_hours - c
		if p.sleep_h < 0:
			p.sleep_h += 24
		p.sleep_m = (p.bedtime_shift % 6) * 10
	if p.has(Partner.SLEEPY):
		match level():
			1:
				if periodic(200):
					p.happiness -= 1
					p.discipline -= 1
			2:
				if periodic(300):
					p.happiness -= 1
					p.discipline -= 1
			_:
				if periodic(TICKS_PER_HOUR):
					p.happiness -= 2
					p.discipline -= 4
		if periodic(TICKS_PER_HOUR) and hour != p.sleep_h:
			p.sleepy_hours += 1
			p.sleepy_hours_total += 1
		var past_wake := (p.sleep_h < p.wake_h and p.sleep_h < hour and p.wake_h <= hour) \
			or (p.wake_h < p.sleep_h and hour < p.sleep_h and p.wake_h <= hour)
		if past_wake:
			_reschedule()
			p.bedtime_shift = p.awake_hours * 6
			p.bedtime_accum = 0
			p.flags &= ~Partner.SLEEPY
			p.care_mistakes += 1
			event.emit("care_mistake", {"reason": "not put to sleep"})
			add_tamer_level(1, -1)                       # main.c:9166
	if was_awake:
		var in_window := false
		if p.wake_h < p.sleep_h:
			in_window = p.sleep_h <= hour or hour < p.wake_h
		elif p.sleep_h < p.wake_h:
			in_window = p.sleep_h <= hour and hour < p.wake_h
		if in_window:
			p.flags |= Partner.SLEEPY
			event.emit("sleepy", {})


## FUN_800a856c
func _sickness_tick() -> void:
	var was_sick := p.has(Partner.SICK)
	var hourly := periodic(TICKS_PER_HOUR)
	if p.sleepy_hours > 9 and hourly and not was_sick:
		p.sick_roll += 1
		var chance := (p.tiredness - 50 + (p.sick_roll - 10) * 5) & 0xFF   # unsigned byte, as in the code
		if rng.rand(100) < chance:
			_get_sick(20)
			p.sleepy_hours = 0
	if not was_sick and p.area_ticks > 12000 and hourly and climate == 2:
		_get_sick(0)
		p.area_ticks = 0
	if hourly and p.has(Partner.SICK):
		p.happiness -= 10
		p.discipline -= 5
		p.tiredness += 5
	if not was_sick and p.sick_hours > 0:
		p.sick_hours = 0
	if hourly:
		if p.has(Partner.SICK):
			p.sick_hours += 1
		if p.has(Partner.INJURED):
			p.injured_hours += 1
	if p.injured_hours > 11 and not was_sick:
		p.flags &= ~Partner.INJURED
		p.injured_hours = 0
		_get_sick(0)
	if p.sick_hours > 11 and p.lifespan != 0:
		p.lives -= 1
		p.sick_hours = 0
		event.emit("sick_too_long", {"lives": p.lives})


func _get_sick(happiness_loss: int) -> void:
	p.flags |= Partner.SICK
	p.times_sick += 1
	p.sick_hours = 1
	p.happiness -= happiness_loss
	event.emit("sick", {})


## FUN_800a70e4
func _tiredness_tick() -> void:
	if p.area_ticks % TICKS_PER_HOUR == 0 and p.area_ticks > 0:
		if climate == 1:
			p.happiness += 1
			p.tiredness -= 2
		elif climate == 2:
			p.happiness -= 1
			p.tiredness += 1
	p.tired_ticks = 0 if p.tiredness < 50 else p.tired_ticks + 1
	if p.tiredness < 80:
		p.flags &= ~Partner.TIRED
	else:
		p.flags |= Partner.TIRED
		if periodic(100):
			p.happiness -= 2


## FUN_800a75dc
func _hunger_tick() -> void:
	var c := care_row()
	if not p.has(Partner.HUNGRY):
		if periodic(20):
			p.hunger_minutes -= 1
	elif periodic(10):
		p.feed_window -= 1
	if periodic(TICKS_PER_HOUR):
		p.fullness = maxi(p.fullness - int(c["fullness_drain_per_hour"]), 0)
	if not p.has(Partner.HUNGRY) and p.hunger_minutes < 1:
		p.feed_window = 180
		p.flags |= Partner.HUNGRY
		event.emit("hungry", {})
	if p.has(Partner.HUNGRY) and p.feed_window < 1:
		next_hunger()
		p.feed_window = 0
		p.flags &= ~Partner.HUNGRY
		if p.fullness < int(c["fullness_needed"]):
			p.care_mistakes += 1
			event.emit("care_mistake", {"reason": "not fed"})
	if p.fullness < 1:
		if periodic(200):
			p.weight = maxi(p.weight - 1, 1)
		if periodic(20):
			p.starving += 1
	if p.tired_ticks > 49 and periodic(TICKS_PER_HOUR):
		p.hunger_minutes -= 3
	if story != null and p.fullness >= int(c["fullness_needed"]):
		story.set_trigger(640)                           # main.c:9734: "full" (restaurants check it)


## FUN_800a5ea0
func _sulk_tick() -> void:
	if p.flags == 0 and p.happiness < 0 and periodic(200):
		if rng.rand(100) < absi(p.happiness) - p.discipline:
			p.flags |= Partner.SULKING
			event.emit("sulking", {})
	if p.has(Partner.SULKING):
		if periodic(15):
			p.happiness += 1
		if periodic(300):
			for k in ["max_hp", "max_mp", "off", "def", "spd", "brn"]:
				p.set(k, maxi(p.get(k) - p.get(k) * 2 / 100, 1))
			p.hp = mini(p.hp, p.max_hp)
			p.mp = mini(p.mp, p.max_mp)
		if p.happiness >= 0:
			p.flags &= ~Partner.SULKING


## FUN_800a7d68
func _poop_tick() -> void:
	if not p.has(Partner.NEEDS_TOILET):
		if periodic(200):
			p.poop_timer -= 1
		if p.poop_timer < 1:
			p.flags |= Partner.NEEDS_TOILET
			p.toilet_window = (p.discipline + 20) * TICKS_PER_HOUR / 100
			event.emit("needs_toilet", {})
	else:
		p.toilet_window -= 1
		if p.toilet_window < 1:
			_poop_accident()


## FUN_800a568c
func clamp_state() -> void:
	p.happiness = clampi(p.happiness, -100, 100)
	p.discipline = clampi(p.discipline, 0, 100)
	p.tiredness = clampi(p.tiredness, 0, 100)
	p.fullness = clampi(p.fullness, 0, int(care_row()["fullness_max"]))
	p.weight = clampi(p.weight, 1, 99)


# ---------------------------------------------------------------- actions
## FUN_800a806c: partner used a toilet in time.
func use_toilet() -> void:
	if not p.has(Partner.NEEDS_TOILET):
		return
	p.happiness += 2
	p.discipline += 2
	_after_poop()
	event.emit("toilet", {})


## FUN_800a8198 + FUN_800a6848: pooped on the ground.
func _poop_accident() -> void:
	p.care_mistakes += 1
	p.happiness -= 10
	p.discipline -= 5
	scold_flag = 1                                     # main.c:9851: a scold now is justified
	_after_poop()
	if p.id != SUKAMON:
		p.virus += 1
	event.emit("care_mistake", {"reason": "poop accident"})


func _after_poop() -> void:
	p.flags &= ~Partner.NEEDS_TOILET
	p.poop_timer = int(care_row()["poop_timer"]) * 2
	p.toilet_window = -1
	p.weight = maxi(p.weight - (rng.rand(4) + int(care_row()["poop_size"])) / 4, 1)   # FUN_800a8100


## FUN_800a6230. Justified = scolded after refusing an item (scold_flag 1): +8 discipline,
## and the next item is taken for sure (flag 2). The happiness change in that branch comes
## from an unknown register, so it's left at 0.
func scold(justified := false) -> void:
	# FUN_800a6230 tail: a Rookie with discipline 0 and happiness -100 when scolded will
	# turn into Nanimon (checked by special_evolution(3) right after)
	nanimon_flag = level() == 3 and p.discipline == 0 and p.happiness == -100
	if scold_flag == 1:
		justified = true
		scold_flag = 2
	if justified:
		p.discipline += 8
	else:
		p.discipline += 2
		p.happiness -= 10
	p.flags &= ~Partner.SULKING
	clamp_state()


func praise() -> void:
	var disc := p.discipline
	p.discipline -= 5
	p.happiness += disc / 10 + 2
	clamp_state()


func has_item(item: int) -> bool:
	return inventory.has(item)


## FUN_800a6d00: HP/MP/tiredness recovery for sleeping until wake-up.
## A full night restores 70-79% of max HP/MP and removes 80-99% of tiredness.
func _sleep_recovery() -> void:
	var slept := p.wake_h + (-hour if hour < p.wake_h else 24 - hour)
	if minute > 0 and hour != p.sleep_h:
		slept += 1
	var pct := slept * 100 / maxi(p.sleep_hours, 1)
	if has_item(34):                                   # Rest pillow
		pct = pct * 12 / 10
	if climate == 1:
		pct = pct * 12 / 10
	elif climate == 2:
		pct = pct * 8 / 10
	var r := rng.rand(10)
	p.hp = mini(p.hp + pct * (p.max_hp * (r + 70) / 100) / 100, p.max_hp)
	p.mp = mini(p.mp + pct * (p.max_mp * (r + 70) / 100) / 100, p.max_mp)
	p.tiredness = maxi(p.tiredness - pct * (p.tiredness * (rng.rand(20) + 80) / 100) / 100, 0)
	p.weight = maxi(p.weight - int(care_row()["base_weight"]) / 10, 1)


## Field step while walking (main exe ~0x800ded10): Health shoe regenerates 5 HP/MP
## every 20 frames. ASSUMPTION: the state check (0x8015579A == 2) means "walking".
func walk_tick() -> void:
	if not has_item(37):
		return
	walk_frames += 1
	if walk_frames > 19:
		p.hp = mini(p.hp + 5, p.max_hp)
		p.mp = mini(p.mp + 5, p.max_mp)
		walk_frames = 0


## FUN_800a63dc: put the partner to bed; time skips to the wake-up time.
func put_to_sleep() -> void:
	_sleep_recovery()
	var slept := p.wake_h + (-hour if hour < p.wake_h else 24 - hour)
	if p.wake_h < hour or (p.wake_h == hour and p.wake_m < minute):   # FUN_800dd678
		day += 1
		_new_day()                    # FUN_800fc374 (main.c:31513)
		p.age_days += 1
		if day > 29:
			day = 0
			year = (year + 1) % 100
	hour = p.wake_h
	minute = p.wake_m
	tick = hour * TICKS_PER_HOUR + minute * TICKS_PER_MINUTE
	p.stage_hours += p.sleep_hours
	p.lifespan = maxi(p.lifespan - slept, 0)
	_reschedule()
	next_hunger()
	p.feed_window = 0
	p.bedtime_shift = p.awake_hours * 6
	p.bedtime_accum = 0
	p.sleepy_hours = 0
	p.flags &= ~(Partner.SLEEPY | Partner.HUNGRY)
	if p.has(Partner.NEEDS_TOILET):                  # wets the bed
		p.flags &= ~Partner.NEEDS_TOILET
		p.poop_timer = int(care_row()["poop_timer"])
		p.toilet_window = -1
		if p.id != SUKAMON:
			p.virus += 1
	if p.has(Partner.SICK):
		p.sick_hours += slept
		p.happiness -= 20
		p.discipline -= 10
		p.tiredness += 10
	if p.has(Partner.INJURED):
		p.injured_hours += slept
		p.happiness -= 10
		p.discipline -= 5
		p.tiredness += 5
	clamp_state()
	woke_hour = hour                                   # main.c:9364-9365
	event.emit("woke_up", {"hours": slept})


## FUN_800abccc: a battle (or similar action) takes 20 game minutes.
func battle_time_skip() -> void:
	tick += 400
	minute += 20
	if minute > 59:
		minute -= 60
		hour += 1
		p.lifespan = maxi(p.lifespan - 1, 0)
		if p.has(Partner.SLEEPY):
			p.sleepy_hours += 1
			p.sleepy_hours_total += 1
		if p.has(Partner.SICK):
			p.sick_roll += 1
			p.sick_hours += 1
		if p.has(Partner.INJURED):
			p.injured_hours += 1
		if hour > 23:                                # FUN_800abccc: no daily rollover
			hour = 0                                 # here (CARE-24)
			day += 1
			tick = minute * TICKS_PER_MINUTE
			if day > 29:
				day = 0
				year = (year + 1) % 100
	if not p.has(Partner.HUNGRY):
		p.hunger_minutes -= 20
	else:
		p.feed_window -= 40
		if p.feed_window < 1 and p.fullness < int(care_row()["fullness_needed"]):
			p.care_mistakes += 1
	if not p.has(Partner.NEEDS_TOILET):
		p.poop_timer -= 2
	else:
		p.toilet_window -= 400


## Skip time without running per-tick events (e.g. a battle = 20 minutes, FUN_800abccc).
func advance_minutes(n: int) -> void:
	for i in n * TICKS_PER_MINUTE:
		step()


# ---------------------------------------------------------------- evolution
## FUN_800a8f38 tail: evolution checks once the stage timer passes.
func _evolution_timer() -> void:
	if pending_evolution != -1:
		return
	var lv := level()
	var target := -1
	if lv == 1 and p.stage_hours > 5:
		target = Evolution.fresh_target(data, p.id)
	elif lv == 2 and p.stage_hours > 23:
		target = Evolution.choose(data, p, story)             # FUN_800e2598
	elif lv == 3 and p.stage_hours > 71:
		target = Evolution.choose_by_stats(data, p, true, story)   # FUN_800e2bb4 (Numemon fallback)
	elif lv == 4 and p.stage_hours > 143:
		target = Evolution.choose_by_stats(data, p, false, story)  # FUN_800e2f08
	if lv == 4 and p.stage_hours == 360:
		var sp := special_evolution(3)                        # main.c:10252
		if sp != -1:
			target = sp
	if p.virus > 15 and p.id != SUKAMON:
		target = SUKAMON
		sukamon_backup = [p.max_hp, p.max_mp, p.off, p.def, p.spd, p.brn]   # main.c:10258
	if target != -1:
		pending_evolution = target
		event.emit("evolve", {"to": target, "from": p.id})


const SPECIALTY_TECH_BASE := [0, 40, 8, 32, 16, 24, 49]   # EVL 80063350, by specialty index


## EVL::80063350 effects of an evolution on the partner (before the new form is set up):
## stat gains from the 0x8012B2D0 row of the target (a stat below the row value becomes the
## average of both, otherwise it gains a tenth of the value); Numemon / Sukamon / Nanimon /
## Devimon, babies and leaving Sukamon use 80063b28 (x row[5]/10, or blend back towards the
## pre-Sukamon stats); +96 h lifespan on reaching Ultimate; learns the lowest-power technique of
## the target's first specialty from its move list. An evolution item skips gains and lifespan.
func _evolution_effects(old_id: int, target: int, used_item: bool) -> void:
	var row: Array = data.digimon[target].get("evo_gains", [])
	var t_level: int = data.level_of(target)
	if row.size() >= 6 and not used_item:
		var st := [p.max_hp, p.max_mp, p.off, p.def, p.spd, p.brn]
		if target in [11, 39, 53, 6] or old_id == SUKAMON or t_level < 3:
			if old_id == SUKAMON and sukamon_backup.size() == 6:
				for i in 6:
					var b: int = sukamon_backup[i]
					st[i] = b + int(float(st[i] - int(b / 2.0)) / 2.0)
				p.virus = 0
			else:
				for i in 6:
					st[i] = st[i] * int(row[5]) / 10
		else:
			for i in 6:
				var v: int = row[i]
				if st[i] < v:
					st[i] = int(float(st[i] + v) / 2.0)
				else:
					st[i] = st[i] + v / 10
			if t_level == 4:                                 # EVL.c:1531-1534
				add_tamer_level(20, 1)
			elif t_level == 5:
				add_tamer_level(100, 1)
		p.max_hp = mini(st[0], 9999)
		p.max_mp = mini(st[1], 9999)
		p.off = mini(st[2], 999)
		p.def = mini(st[3], 999)
		p.spd = mini(st[4], 999)
		p.brn = mini(st[5], 999)
		p.hp = mini(p.hp, p.max_hp)
		p.mp = mini(p.mp, p.max_mp)
	if t_level == 5 and not used_item:
		p.lifespan += 96
	# the specialty technique, learned and equipped alone (EVL 80063350: earlier choices are
	# dropped); below Rookie the species' first move; the finisher is the new species'
	var specs: Array = data.digimon[target]["specialties"]
	var moves: Array = data.digimon[target]["techniques"]
	var pick := -1
	if not specs.is_empty() and not moves.is_empty():
		var base: int = SPECIALTY_TECH_BASE[clampi(data.SPECIALTIES.find(specs[0]), 0, 6)]
		for m in moves:
			var mid := int(m["id"])
			if mid < base or mid > base + 8:
				continue
			var pw := int(data.techniques[mid]["power"])
			if pick == -1 or (pw < int(data.techniques[pick]["power"]) and pw != 0):
				pick = mid
		if pick != -1:
			learn(pick)
	var first: int = int(moves[0]["id"]) if not moves.is_empty() else -1
	var eq: int = pick if pick != -1 and t_level >= 3 else first
	p.moves = [eq, -1, -1, Techniques.finisher_for(data, target)]


## FUN_800acbf4: with chance% (one rand(100)), the tamer level moves by delta, kept in 0-10.
## Returns true if it changed (DW1 then shows "Tamer level went up/down!!!").
func add_tamer_level(chance: int, delta: int) -> bool:
	if rng.rand(100) >= chance:
		return false
	var before := tamer_level
	tamer_level = clampi(tamer_level + delta, 0, 10)
	if tamer_level != before:
		event.emit("tamer_level", {"level": tamer_level, "delta": delta})
	return tamer_level != before


## FUN_800e3234: special evolutions. Mode 2 runs after waking from sleep, mode 3 after praise /
## scold (and for a Champion at exactly 360 stage hours). One rand(100) per call. Returns the
## target (also queued as pending_evolution) or -1.
func special_evolution(mode: int) -> int:
	var id := p.id
	var lv := level()
	var r := rng.rand(100)
	var target := -1
	if mode == 3:
		if (id == 24 or id == 35) and lv == 4 and p.stage_hours == 200 and r < 30:
			target = 49                                       # Whamon / Shellmon -> Coelamon
		if nanimon_flag:
			target = 53                                       # Nanimon
			nanimon_flag = false
		if lv == 4 and p.stage_hours > 239 and r < 50:
			target = 28                                       # Vademon
	elif mode == 2:
		if r < 30:
			if (id == 21 or id == 10) and p.discipline == 100 and p.happiness == 100 and p.tiredness == 0:
				target = 7                                    # Birdramon / Seadramon -> Airdramon
			if id == 25 and p.battles > 49 and p.discipline == 100:
				target = 58                                   # Vegiemon -> Ninjamon
			if id == 38 and p.def > 499 and p.discipline == 100:
				target = 47                                   # Drimogemon -> Monochromon
		if r < 50 and id in [2, 30, 16, 44] and map_id == 1:
			target = 32                                       # In-Training asleep on map 1 -> Kunemon
	if target != -1:
		pending_evolution = target
		event.emit("evolve", {"to": target, "special": true})
	return target


## Apply a pending evolution (FUN_800a4f74 -> FUN_800a4750 + FUN_800a50a8).
## Stats, lifespan, happiness and discipline carry over; the stage timer restarts
## (confirmed in-game: a 6-day-old Ninjamon had 210 h lifespan left but 24 stage hours).
func evolve(target: int, used_item := false) -> void:
	var old_level := level()
	var old_id := p.id
	_evolution_effects(old_id, target, used_item)
	p.id = target
	p.flags = 0
	_init_schedule()
	p.sleepy_hours_total = 0
	p.bedtime_accum = 0
	p.poop_timer = int(care_row()["poop_timer"])
	p.toilet_window = -1
	p.tiredness = 0
	p.tired_ticks = 0
	p.times_sick = 0
	p.area_ticks = 0
	p.sick_hours = 0
	p.injured_hours = 0
	p.sick_roll = 0
	next_hunger()
	p.feed_window = -1
	p.starving = 0
	p.weight = int(care_row()["base_weight"])
	p.care_mistakes = 0
	p.battles = 0
	if level() != old_level:                           # EVL.c:1621: only when the level changes
		p.stage_hours = 0
	if target == SUKAMON:
		p.virus = 0
	pending_evolution = -1
	mark_raised(target)                                # EVL.c:1620
	event.emit("evolved", {"to": target})


## FUN_800ff7f8: the "raised" story flag of an evolution, a hatch or the new game's partner.
func mark_raised(id: int) -> void:
	if story != null and id >= 0 and id < 0x3F:
		story.set_trigger(RAISED_TRIGGER + id)


## FUN_800e3584 (reincarnatePartner, called by the hatch in DOOA): the egg hatches.
## FUN_800a5198 / FUN_800a5444: stat = base + previous stat * tamer level / 100, the tamer
## level counting only after a death of old age. The learned-moves bitfield (0x80155800, ids
## below 0x3A) is kept and only the baby's own move is equipped ({0x2E, -, -, -}); lives back
## to 3. FUN_800a5198 doesn't touch the virus counter, fullness, food boost or gym sessions.
func rebirth(baby_id: int) -> void:
	var prev := p.stat_array()
	var inherit := tamer_level if natural_death else 0
	var learned: Array = p.techniques.filter(func(t): return t < LEARNABLE)
	var kept := [p.virus, p.fullness, p.boost_mask, p.boost_mult, p.boost_ticks, p.gym_sessions]
	new_partner(baby_id)
	for t in learned:                                  # new_partner set the baby's first move
		if not p.techniques.has(t):
			p.techniques.append(t)
	p.moves[3] = -1                                    # {0x2E, FF, FF, FF} (main.c:34287)
	p.virus = kept[0]
	p.fullness = kept[1]
	p.boost_mask = kept[2]
	p.boost_mult = kept[3]
	p.boost_ticks = kept[4]
	p.gym_sessions = kept[5]
	var base: Array = BABY_STATS.get(baby_id, [90, 110, 10, 11, 9, 10])
	var keys := ["max_hp", "max_mp", "off", "def", "spd", "brn"]
	for i in 6:
		p.set(keys[i], base[i] + prev[i] * inherit / 100)
	p.hp = p.max_hp
	p.mp = p.max_mp
	p.lives = 3
	p.age_days = 0
	p.stage_hours = 0
	raised_count = mini(raised_count + 1, 99)
	natural_death = false
	dead = false
	pending_evolution = -1
	woke_hour = -1
	mark_raised(baby_id)                               # main.c:34296
	event.emit("reborn", {"id": baby_id, "inherit": inherit})


## FUN_800fe3f8 (builtin 47, after losing all lives): round((10 - TL) * 2 * n / 100) of the
## n learned techniques (ids below 0x3A) are forgotten at random. Returns the forgotten ids.
func forget_techniques() -> Array:
	var learned: Array = p.techniques.filter(func(t): return t < LEARNABLE)
	var x := (10 - tamer_level) * 2 * learned.size()
	if x % 100 > 0x31:
		x += 100
	var forgotten := []
	for i in x / 100:
		if learned.is_empty():
			break
		var t: int = learned.pop_at(rng.rand(learned.size()))
		p.techniques.erase(t)
		var s: int = p.moves.find(t)                    # FUN_800e66e0: the first slot holding it
		if s >= 0:
			p.moves[s] = -1
		forgotten.append(t)
	return forgotten
