class_name SaveGame
extends RefCounted
## DW1's save file (writer FUN_801130c8, loader FUN_80112d84, main.c:60172-60379) as JSON in
## user://save_NN.json, 15 files like one memory card. It holds what DW1 saves: the partner
## (all care state, stats, moves, name, lives), the clock, story triggers 0-799 and pstats 0-34,
## money, merit, bag, cards, recycle shop, tamer name/level/raised count, and the map, exits and
## exact positions. Not saved, as in DW1: script/VM state, pstats 35+, price, time speed, scold
## and Nanimon flags, a pending evolution, items on the ground, NPC states and the RNG.
## A write goes to a temp file, then replaces the save, keeping the old one as .bak (DW1 keeps
## two checksummed copies); a load takes the newest complete copy of the save, .tmp and .bak
## (a rename fails while another program has the file open, docs/vpet_save.md section 4).

const SLOTS := 15
const VERSION := 1
const TRIGGERS := 800                   # 100 bytes of trigger bits (main.c:54230)
const PSTATS := 35                      # pstats 0..34 only (main.c:53667)
const LEVEL := {"Fresh": 1, "In-Training": 2, "Rookie": 3, "Champion": 4, "Ultimate": 5}
## Partner vars that are runtime only (none yet; every Partner field is in PARTNER_PARA/stats).
const PARTNER_SKIP := []


## The folder of the save files (tests point it elsewhere so they never touch real saves).
static var root := "user://"


static func path(slot: int) -> String:
	return root + "save_%02d.json" % (slot + 1)


## place: {map, exit, prev: Vector2i(screen, exit), tamer: Vector3, partner: Vector3} (DW1 units)
static func to_dict(story: StoryState, sim: CareSim, place: Dictionary, main_state := 1,
		extra := {}) -> Dictionary:
	var trig := []
	for t in TRIGGERS:
		if story.is_set(t):
			trig.append(t)
	var ps := []
	for i in PSTATS:
		ps.append(story.pstat(i))
	if ps[0] == 3:                                    # "script running" is saved as 0 (main.c:60287)
		ps[0] = 0
	var partner := {}
	for prop in sim.p.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and not prop["name"] in PARTNER_SKIP:
			var v = sim.p.get(prop["name"])
			partner[prop["name"]] = v.duplicate() if v is Array else v
	var d := {
		"version": VERSION,
		"main_state": main_state,
		"story": {
			"triggers": trig, "pstats": ps, "money": story.money, "merit": story.merit,
			"player_name": story.player_name, "partner_name": story.partner_name,
			"battles": story.battles, "flees": story.flees, "fish_caught": story.fish_caught,
			"tournament": [story.tournament_titles, story.tournament_wins, story.tournament_losses],
			"bank": story.bank.duplicate(), "daily_cards": story.daily_cards.duplicate(),
			"cards": story.learned_cards.duplicate(), "recycle": story.recycle.duplicate(),
			"bag": {"size": story.inventory.size, "types": Array(story.inventory.types),
				"amounts": Array(story.inventory.amounts)},
		},
		"care": {
			"tick": sim.tick, "hour": sim.hour, "minute": sim.minute, "day": sim.day,
			"year": sim.year, "tamer_level": sim.tamer_level, "raised_count": sim.raised_count,
			"sukamon_backup": sim.sukamon_backup.duplicate(), "partner": partner,
		},
		"place": {
			"map": int(place["map"]), "exit": int(place["exit"]),
			"prev": [place["prev"].x, place["prev"].y],
			"tamer": _xyz(place["tamer"]), "partner": _xyz(place["partner"]),
		},
	}
	d.merge(extra)                                     # e.g. vs_registrations, playtime
	return d


static func _xyz(v: Vector3) -> Array:
	return [int(round(v.x)), int(round(v.y)), int(round(v.z))]


## Restores story and care state; returns the place (Vector types restored).
static func apply(d: Dictionary, story: StoryState, sim: CareSim) -> Dictionary:
	var s: Dictionary = d["story"]
	story.triggers.fill(0)
	for t in s["triggers"]:
		story.set_trigger(int(t))
	story.pstats.fill(0)                               # pstats 35+ start at 0 (FUN_801059c8)
	var ps: Array = s["pstats"]
	for i in ps.size():
		story.set_pstat(i, int(ps[i]))
	story.money = int(s["money"])
	story.merit = int(s["merit"])
	story.battles = int(s.get("battles", 0))
	story.fish_caught = int(s.get("fish_caught", 0))
	story.flees = int(s.get("flees", 0))
	var tr: Array = s.get("tournament", [0, 0, 0])
	story.tournament_titles = int(tr[0])
	story.tournament_wins = int(tr[1])
	story.tournament_losses = int(tr[2])
	story.bank = []
	for v in s.get("bank", []):
		story.bank.append(int(v))
	story.daily_cards = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
	var dc: Array = s.get("daily_cards", [])
	for i in mini(dc.size(), 6):
		story.daily_cards[i] = int(dc[i])
	story.price = 0
	story.time_speed = 0
	story.player_name = str(s["player_name"])
	story.partner_name = str(s["partner_name"])
	story.learned_cards = {}
	for k in s["cards"]:
		story.learned_cards[int(k)] = int(s["cards"][k])
	story.recycle = []
	for v in s["recycle"]:
		story.recycle.append(int(v))
	var bag: Dictionary = s["bag"]
	var inv := story.inventory
	inv.size = int(bag["size"])
	for i in inv.types.size():
		inv.types[i] = int(bag["types"][i]) if i < bag["types"].size() else Inventory.NONE
		inv.amounts[i] = int(bag["amounts"][i]) if i < bag["amounts"].size() else 0
	var c: Dictionary = d["care"]
	sim.tick = int(c["tick"])
	sim.hour = int(c["hour"])
	sim.minute = int(c["minute"])
	sim.day = int(c["day"])
	sim.year = int(c["year"])
	sim.tamer_level = int(c["tamer_level"])
	sim.raised_count = int(c["raised_count"])
	sim.sukamon_backup = []
	for v in c["sukamon_backup"]:
		sim.sukamon_backup.append(int(v))
	var p := Partner.new()
	var pd: Dictionary = c["partner"]
	for prop in p.get_property_list():
		var n: String = prop["name"]
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and pd.has(n):
			var cur = p.get(n)
			if cur is Array:
				var arr := []
				for v in pd[n]:
					arr.append(int(v) if v is float else v)
				p.set(n, arr)
			elif cur is bool:
				p.set(n, bool(pd[n]))
			elif cur is int:
				p.set(n, int(pd[n]))
			else:
				p.set(n, pd[n])
	if not pd.has("moves"):                            # saves from before equipped moves
		p.moves = Techniques.default_moves(sim.data, p)
	sim.p = p
	# runtime state DW1 doesn't save
	sim.pending_evolution = -1
	sim.scold_flag = 0
	sim.nanimon_flag = false
	sim.dead = false
	sim.natural_death = false
	sim.walk_frames = 0
	sim.woke_hour = sim.hour                           # FUN_800a97e0: checks wait for the next hour
	var pl: Dictionary = d["place"]
	return {"map": int(pl["map"]), "exit": int(pl["exit"]),
		"prev": Vector2i(int(pl["prev"][0]), int(pl["prev"][1])),
		"tamer": Vector3(pl["tamer"][0], pl["tamer"][1], pl["tamer"][2]),
		"partner": Vector3(pl["partner"][0], pl["partner"][1], pl["partner"][2])}


## FUN_800efa18 (on save and load): pstat 1 (File City prosperity) = for raised ids 3-58
## (trigger 200 + id) of level Rookie or above, level - 2 each, but 1 for Numemon, Sukamon
## and Nanimon; then, if pstat 3 > 22, triggers 37-39 are cleared.
static func prosperity(story: StoryState, digimon: Array) -> void:
	var total := 0
	for id in range(3, 59):
		if id >= digimon.size() or not story.is_set(200 + id):
			continue
		var lv: int = LEVEL.get(digimon[id].get("level", 0), 0)
		if lv < 3:
			continue
		total += 1 if id in [11, 39, 53] else lv - 2
	story.set_pstat(1, total)
	if story.pstat(3) > 22:
		for t in [37, 38, 39]:
			story.set_trigger(t, false)


## FUN_800ef38c's load check (FUN_800d45ec(partner, tamer), SydPatches entityCheckCollision):
## the tamer's saved spot against the map Digimon in slot order, boxes of half-size = each
## one's own radius (the tamer's is 100); the first visible hit counts. npcs: [{type, x, z,
## radius, visible}]. Returns its index or -1.
static func load_overlap(tamer: Vector3, npcs: Array, tamer_radius := 100) -> int:
	for i in npcs.size():
		var n: Dictionary = npcs[i]
		if not n.get("visible", true):
			continue
		var reach := tamer_radius + int(n["radius"])
		if absf(tamer.x - float(n["x"])) <= reach and absf(tamer.z - float(n["z"])) <= reach:
			return i
	return -1


## Map Digimon a loaded tamer doesn't push off the map (main.c:40666-40674): then the tamer
## and partner go to the entrance instead.
static func load_protected(type: int, map_id: int) -> bool:
	return type in [109, 1, 2, 15, 16, 29, 30, 43, 44] or type > 116 \
		or (type == 92 and map_id == 155) or (type == 106 and map_id == 85)


## loadMapEntities: the partner starts 200 units from the tamer along the axis the entrance
## faces (DW1 rotation, 0x1000 = 360 degrees).
static func partner_offset(rot: int) -> Vector3:
	if rot <= 0x200 or rot > 0xE00:
		return Vector3(0, 0, 200)
	if rot <= 0x600:
		return Vector3(200, 0, 0)
	if rot <= 0xA00:
		return Vector3(0, 0, -200)
	return Vector3(-200, 0, 0)


# ---------------------------------------------------------------- files
static func write(slot: int, d: Dictionary) -> bool:
	var out := d.duplicate()
	out["written_at"] = Time.get_unix_time_from_system()   # which copy is newest (read)
	return write_atomic(path(slot), JSON.stringify(out, "\t"))


## Writes text to p safely: p.tmp first, then the old p becomes p.bak and p.tmp becomes p.
## Each rename is retried (it fails while another handle has either file open). On false
## the new text is still complete in p.tmp, which read_newest also considers.
static func write_atomic(p: String, text: String) -> bool:
	var tmp := p + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	if FileAccess.file_exists(p):
		_rename(p, p + ".bak")                          # a failure leaves p as it was
	return _rename(tmp, p)


static func _rename(from: String, to: String) -> bool:
	for attempt in 3:
		if attempt > 0:
			OS.delay_msec(50)
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(from),
				ProjectSettings.globalize_path(to)) == OK:
			return true
	return false


## The newest complete copy of p, p.tmp and p.bak: those that parse to a Dictionary that
## valid accepts, ranked by rank (ties keep the order p, .tmp, .bak). {} if none.
static func read_newest(p: String, valid: Callable, rank: Callable) -> Dictionary:
	var best := {}
	var best_rank := -INF
	for c in [p, p + ".tmp", p + ".bak"]:
		if not FileAccess.file_exists(c):
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string(c))
		if not (d is Dictionary and valid.call(d)):
			continue
		var r: float = rank.call(d)
		if r > best_rank:
			best = d
			best_rank = r
	return best


static func read(slot: int) -> Dictionary:
	return read_newest(path(slot), func(d): return d.has("main_state"),
		func(d): return float(d.get("written_at", 0.0)))


static func exists(slot: int) -> bool:
	return not read(slot).is_empty()


static func delete(slot: int) -> void:
	for p in [path(slot), path(slot) + ".bak", path(slot) + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## One line per file for the title's list: "Not used" or tamer name and species.
static func summary(slot: int, digimon: Array) -> String:
	var d := read(slot)
	if d.is_empty():
		return "Not used"
	if int(d["main_state"]) == 0 or not d.has("care"):
		return "%s  (new adventure)" % d.get("story", {}).get("player_name", "Tamer")
	var id := int(d["care"]["partner"].get("id", 0))
	var species: String = digimon[id]["name"] if id < digimon.size() else "?"
	return "%s / %s %s" % [d["story"]["player_name"], d["story"]["partner_name"],
		"(%s)" % species if species != d["story"]["partner_name"] else ""]
