class_name VpetSave
extends RefCounted
## The desktop pet tied to a save (not DW1; docs/vpet_save.md). Three places, one writer each:
## - vpet_link.json, the game's: which file is the pet's, its partner and current values;
## - vpet_NN.json, the pet's: running totals of what desktop care changed, which only rise;
## - the save's own "vpet" block: the totals the game has already applied.
## A load of the pet's file shows what the totals add beyond the block; Yes applies them and
## saves at once (after a backup), so each change lands exactly once. The game never writes
## the pet's file and the pet never opens the save.

const FORMAT := 1
const KEYS := ["max_hp", "max_mp", "off", "def", "spd", "brn", "happy_up", "happy_down",
	"disc_up", "disc_down", "weight_up", "weight_down", "care_mistakes", "virus"]
## The most one load applies per key (docs/vpet_save.md section 3, rule 15; care mistakes
## one a day for a week, virus up to DW1's Sukamon threshold of 16).
const MERGE_CAP := {"max_hp": 210, "max_mp": 210, "off": 21, "def": 21, "spd": 21, "brn": 21,
	"happy_up": 10, "happy_down": 10, "disc_up": 10, "disc_down": 10, "weight_up": 5,
	"weight_down": 5, "care_mistakes": 7, "virus": 16}
const BACKUPS := 5
const STAT_MAX := {"max_hp": 9999, "max_mp": 9999, "off": 999, "def": 999, "spd": 999, "brn": 999}
const LABELS := {"max_hp": "HP", "max_mp": "MP", "off": "Offense", "def": "Defense",
	"spd": "Speed", "brn": "Brains"}


static func link_path() -> String:
	return SaveGame.root + "vpet_link.json"


## The pet's file name: "vpet_" for the remake's saves; D-Screen's card mode sets "dw1pet_", so a
## card slot's file never shares a name with the remake save slot's in the same folder.
static var pet_prefix := "vpet_"


static func pet_path(slot: int) -> String:
	return SaveGame.root + pet_prefix + "%02d.json" % (slot + 1)


static func backup_dir() -> String:
	return SaveGame.root + "vpet_backup/"


static func zeros() -> Dictionary:
	var d := {}
	for k in KEYS:
		d[k] = 0
	return d


# ---------------------------------------------------------------- the link (game writes)
## Designates slot as the pet's (the title's option): an old save without a partner uid gets
## one, written through SaveGame.write (which keeps the .bak). Returns false if it can't.
static func designate(slot: int, data) -> bool:
	var d := SaveGame.read(slot)
	if d.is_empty() or int(d.get("main_state", 0)) == 0 or not d.has("care"):
		return false
	var pd: Dictionary = d["care"]["partner"]
	if str(pd.get("uid", "")) == "":
		pd["uid"] = Crypto.new().generate_random_bytes(8).hex_encode()
		if not SaveGame.write(slot, d):
			return false
	var link := read_link()
	return write_link(slot, d, data, bool(link.get("ask", true)) if not link.is_empty() else true,
		_declined(link, slot))


## The link for a save's dictionary (as written or read). ask: show the Apply window on load
## ("No and stop asking" clears it); declined: the last offer was turned down, so desktop
## training is on hold until it's applied.
static func link_for(slot: int, d: Dictionary, data, ask := true, declined := false) -> Dictionary:
	var pd: Dictionary = d["care"]["partner"]
	var id := int(pd.get("id", 0))
	var c: Dictionary = data.care[id] if id < data.care.size() else {}
	var base := {}
	for k in ["weight", "happiness", "discipline", "max_hp", "max_mp", "off", "def", "spd", "brn"]:
		base[k] = int(pd.get(k, 0))
	return {"format": FORMAT, "slot": slot, "partner_uid": str(pd.get("uid", "")), "partner_id": id,
		"partner_name": str(d["story"].get("partner_name", "")),
		"raised_count": int(d["care"].get("raised_count", 0)), "base": base,
		"care": {"poop_size": int(c.get("poop_size", 8)), "base_weight": int(c.get("base_weight", 10)),
			"fullness_needed": int(c.get("fullness_needed", 20))},
		"techniques": (pd.get("techniques", []) as Array).map(func(v): return int(v)),   # learned
		"moves": (pd.get("moves", []) as Array).map(func(v): return int(v)),   # equipped 3 + finisher: he shadowboxes with these
		# the rest of what DW1's evolution pick reads (EvoForecast, the pet's hint)
		"care_mistakes": int(pd.get("care_mistakes", 0)), "battles": int(pd.get("battles", 0)), "virus": int(pd.get("virus", 0)),
		"stage_hours": int(pd.get("stage_hours", 0)), "raised": _raised(d),
		"applied": (d.get("vpet", {}) as Dictionary).get("consumed", zeros()),
		"applied_file_id": str((d.get("vpet", {}) as Dictionary).get("file_id", "")),   # whose totals "applied" counts
		"ask": ask, "declined": declined, "written_at": Time.get_unix_time_from_system()}


## The forms raised on this file (CareSim.RAISED_TRIGGER + id, set on every evolution and hatch).
static func _raised(d: Dictionary) -> Array:
	var out := []
	for t in d["story"].get("triggers", []):
		var id := int(t) - CareSim.RAISED_TRIGGER
		if id >= 0 and id < 0x40:
			out.append(id)
	return out


static func write_link(slot: int, d: Dictionary, data, ask := true, declined := false) -> bool:
	return SaveGame.write_atomic(link_path(), JSON.stringify(link_for(slot, d, data, ask, declined), "\t"))


static func read_link() -> Dictionary:
	return SaveGame.read_newest(link_path(),
		func(d): return int(d.get("format", 0)) == FORMAT and d.has("slot"),
		func(d): return float(d.get("written_at", 0.0)))


## The designated file, or -1.
static func designated() -> int:
	var link := read_link()
	return int(link["slot"]) if not link.is_empty() else -1


static func _declined(link: Dictionary, slot: int) -> bool:
	return not link.is_empty() and int(link["slot"]) == slot and bool(link.get("declined", false))


## "Ask when loading" on the title's DESKTOP PET option ("No, stop asking" turns it off).
static func set_ask(on: bool) -> bool:
	var link := read_link()
	if link.is_empty():
		return false
	link["ask"] = on
	link["written_at"] = Time.get_unix_time_from_system()
	return SaveGame.write_atomic(link_path(), JSON.stringify(link, "	"))


static func clear_link() -> void:
	for p in [link_path(), link_path() + ".tmp", link_path() + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


# ---------------------------------------------------------------- the pet's process
static func pid_path() -> String:                 # pet.gd writes it while he runs
	return SaveGame.root + "pet.pid"


static func events_path() -> String:              # pet.gd reads it (Claude Code's hooks too)
	return SaveGame.root + "pet_events.jsonl"


## Whether the pet runs: he refreshes his pid file every 5 s and removes it when he quits
## (OS.is_process_running only knows processes this one started). A file older than max_age
## is a crashed pet.
static func pet_running(max_age := 15.0) -> bool:
	if not FileAccess.file_exists(pid_path()):
		return false
	return Time.get_unix_time_from_system() - FileAccess.get_modified_time(pid_path()) <= max_age


## Tells the pet his save is loading (an event like Claude Code's hooks): he says a line,
## writes his last changes and quits.
static func send_pet_home() -> void:
	tell_pet({"event": "game_load"})


## Appends an event to the pet's feed (pet_events.jsonl, which Claude Code's hooks also write),
## stamped with the time; the pet reads it within half a second.
static func tell_pet(ev: Dictionary) -> void:
	var p := events_path()
	var f := FileAccess.open(p, FileAccess.READ_WRITE if FileAccess.file_exists(p) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	ev["t"] = Time.get_unix_time_from_system()
	f.store_string(JSON.stringify(ev) + "\n")
	f.close()


# ---------------------------------------------------------------- the pet's file (pet writes)
static func valid_pet(d: Dictionary, slot: int) -> bool:
	return int(d.get("format", 0)) == FORMAT and int(d.get("slot", -1)) == slot \
		and d.has("seq") and str(d.get("file_id", "")) != "" and d.get("totals") is Dictionary


## The newest complete copy of the pet's file (highest seq of main, .tmp, .bak), {} if none.
## Retried: a read can meet the moment between the pet's two renames.
static func read_pet(slot: int) -> Dictionary:
	for attempt in 3:
		if attempt > 0:
			OS.delay_msec(50)
		var d := SaveGame.read_newest(pet_path(slot), func(x): return valid_pet(x, slot),
			func(x): return float(x["seq"]))
		if not d.is_empty():
			return d
		if not FileAccess.file_exists(pet_path(slot)) and not FileAccess.file_exists(pet_path(slot) + ".tmp") \
				and not FileAccess.file_exists(pet_path(slot) + ".bak"):
			return {}
	return {}


## The pet's write: seq + 1 each time. On false the .tmp holds it; the pet retries next tick.
static func write_pet(slot: int, d: Dictionary) -> bool:
	d["format"] = FORMAT
	d["slot"] = slot
	d["seq"] = int(d.get("seq", 0)) + 1
	d["written_at"] = Time.get_unix_time_from_system()
	return SaveGame.write_atomic(pet_path(slot), JSON.stringify(d, "\t"))


## Moves the pet's file aside (never deleted): its partner is gone (rebirth, new game, the
## file deleted). Returns the new name of the main copy, or "".
static func archive_pet(slot: int) -> String:
	var stamp := int(Time.get_unix_time_from_system())
	var moved := ""
	for ext in ["", ".tmp", ".bak"]:
		var p: String = pet_path(slot) + ext
		if FileAccess.file_exists(p):
			var to: String = pet_path(slot).trim_suffix(".json") + ".orphan-%d.json%s" % [stamp, ext]
			if DirAccess.rename_absolute(ProjectSettings.globalize_path(p),
					ProjectSettings.globalize_path(to)) == OK and ext == "":
				moved = to
	return moved


# ---------------------------------------------------------------- the merge (game)
## What the pet's totals add beyond the save's block, for the loaded partner p:
## {state: "none" | "orphan" | "pending", deltas, consumed (the totals to record), file_id}.
## Each delta is >= 0 and capped (MERGE_CAP). If he evolved since the pet last saw him,
## weight and care mistakes don't carry (DW1's evolution resets both, main.c:8941-8942).
static func pending(block: Dictionary, pet: Dictionary, p: Partner) -> Dictionary:
	var out := {"state": "none", "deltas": zeros(), "consumed": {}, "file_id": ""}
	if pet.is_empty():
		return out
	if p.uid == "" or str(pet.get("partner_uid", "")) != p.uid:
		out["state"] = "orphan"
		return out
	var totals: Dictionary = pet["totals"]
	var base: Dictionary = block.get("consumed", {}) if str(block.get("file_id", "")) == str(pet["file_id"]) else {}
	var evolved := int(pet.get("partner_id", p.id)) != p.id
	var reset: Dictionary = pet.get("evolved", {})   # the pet saw him evolve: what came before never applies
	var any := false
	for k in KEYS:
		var t := maxi(0, int(totals.get(k, 0)))
		out["consumed"][k] = maxi(t, int(base.get(k, 0)))
		var d := clampi(t - maxi(int(base.get(k, 0)), int(reset.get(k, 0))), 0, int(MERGE_CAP[k]))
		if evolved and k in ["weight_up", "weight_down", "care_mistakes"]:
			d = 0
		out["deltas"][k] = d
		any = any or d != 0
	out["file_id"] = str(pet["file_id"])
	out["state"] = "pending" if any else "none"
	return out


## Applies the deltas of pending() to the partner, within DW1's limits.
static func apply(sim: CareSim, deltas: Dictionary) -> void:
	var p := sim.p
	for k in STAT_MAX:
		p.set(k, mini(int(p.get(k)) + int(deltas[k]), int(STAT_MAX[k])))
	p.happiness += int(deltas["happy_up"]) - int(deltas["happy_down"])
	p.discipline += int(deltas["disc_up"]) - int(deltas["disc_down"])
	p.weight += int(deltas["weight_up"]) - int(deltas["weight_down"])
	p.care_mistakes += int(deltas["care_mistakes"])
	p.virus += int(deltas["virus"])
	sim.clamp_state()


## The save block after applying: what the totals now count as applied.
static func block_after(m: Dictionary, pet: Dictionary, p: Partner) -> Dictionary:
	return {"file_id": m["file_id"], "partner_uid": p.uid, "consumed": m["consumed"],
		"merged_seq": int(pet.get("seq", 0)), "merged_at": Time.get_unix_time_from_system()}


## The Apply window's lines, e.g. ["HP +30  Offense +2", "Happiness +3  Weight -1"].
static func describe(deltas: Dictionary) -> Array:
	var parts := []
	for k in STAT_MAX:
		if int(deltas[k]) != 0:
			parts.append("%s +%d" % [LABELS[k], int(deltas[k])])
	for pair in [["Happiness", "happy"], ["Discipline", "disc"], ["Weight", "weight"]]:
		var n := int(deltas[pair[1] + "_up"]) - int(deltas[pair[1] + "_down"])
		if n != 0:
			parts.append("%s %+d" % [pair[0], n])
	if int(deltas["care_mistakes"]) > 0:
		parts.append("Care mistakes +%d" % int(deltas["care_mistakes"]))
	if int(deltas["virus"]) > 0:
		parts.append("Virus +%d" % int(deltas["virus"]))
	var lines := []
	for i in range(0, parts.size(), 2):
		lines.append("  ".join(parts.slice(i, i + 2)))
	return lines


## Keeps a copy of the save as loaded (d) before a merge; at most BACKUPS per file.
static func backup(slot: int, d: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(backup_dir()))
	var name := "save_%02d.%d.json" % [slot + 1, int(Time.get_unix_time_from_system() * 1000000.0)]
	var f := FileAccess.open(backup_dir() + name, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	var mine := []
	for n in DirAccess.get_files_at(backup_dir()):
		if n.begins_with("save_%02d." % (slot + 1)):
			mine.append(n)
	mine.sort_custom(func(a, b): return int(a.get_slice(".", 1)) < int(b.get_slice(".", 1)))
	while mine.size() > BACKUPS:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_dir() + str(mine.pop_front())))
	return true
