class_name CardLink
extends RefCounted
## D-Screen's bridge to real DW1 (docs/memcard_bridge.md sections 10, 12 and 15; no mod): the pet
## is the partner of a save on DuckStation's memory card. Three places, one writer each:
## - card_link.json (the pet's choice): which card file and slot, ask, declined;
## - vpet_NN.json (the pet's file, VpetSave): his running totals, which only rise;
## - the save itself (Dw1Card.SPARE): the pet file's id and the seq whose totals are applied, plus
##   card_applied_NN.json, the journal of what each applied seq's totals were.
## Gains are written into the save only while DuckStation is closed (it keeps the card in memory
## and writes it back over any outside edit), after the Apply window; the record rides inside the
## save, so a version that DuckStation or a save state puts back offers the gains again: delayed,
## never lost or doubled. The link it builds has VpetSave.link_for's keys, so PetCare, Vpet and
## EvoForecast run unchanged.

const FORMAT := 1
const BACKUPS := 5
const CARD_EXT := "mcd"


static func link_path() -> String:
	return SaveGame.root + "card_link.json"


static func journal_path(slot: int) -> String:
	return SaveGame.root + "card_applied_%02d.json" % (slot + 1)


static func backup_dir() -> String:
	return SaveGame.root + "card_backup/"


# ---------------------------------------------------------------- finding the cards
## DuckStation's memory card folder ([MemoryCards] Directory, relative to its settings.ini).
static func card_dirs() -> Array[String]:
	var out: Array[String] = []
	for ini in Dw1Disc.duckstation_settings():
		var dir := "memcards"
		var section := ""
		for line in FileAccess.get_file_as_string(ini).split("\n"):
			var l := line.strip_edges()
			if l.begins_with("["):
				section = l
			elif section == "[MemoryCards]" and l.get_slice("=", 0).strip_edges() == "Directory":
				dir = l.substr(l.find("=") + 1).strip_edges().replace("\\", "/")
		if dir.is_relative_path():
			dir = ini.get_base_dir().path_join(dir)
		if DirAccess.dir_exists_absolute(dir) and not out.has(dir):
			out.append(dir)
	return out


## The card's port from DuckStation's name ({title}_{n}.mcd): 1, 2, or 0 when the name says nothing.
static func port_of(card: String) -> int:
	var b := card.get_file().get_basename()
	return int(b[-1]) if b.length() > 2 and b[-2] == "_" and b[-1] in ["1", "2"] else 0


## Every DW1 save on every card: [{card, port, slot, copy, label, partner (Dw1Card.decode)}].
## names: the species names by id (the EXE's table; the card header's copy keeps junk, CARD-8).
static func entries(dirs: Array[String] = [], names: Array = []) -> Array:
	if dirs.is_empty():
		dirs = card_dirs()
	var out := []
	for dir in dirs:
		for f in DirAccess.get_files_at(dir):
			if f.get_extension().to_lower() != CARD_EXT:
				continue
			var path := dir.path_join(f)
			var card := FileAccess.get_file_as_bytes(path)
			for s in Dw1Card.saves(card):
				var e := {"card": path, "port": port_of(path), "slot": s["slot"], "copy": s["copy"]}
				if s["copy"] >= 0:
					var dec := Dw1Card.decode(s["payload"])
					e["partner"] = dec
					var id := int(dec["type"])
					e["label"] = "%d %s (%s) %d:%02d" % [s["slot"] + 1, dec["name"],
						names[id] if id >= 0 and id < names.size() else "?", dec["play"][0], dec["play"][1]]
				else:
					e["label"] = "%d (damaged)" % (s["slot"] + 1)
				out.append(e)
	return out


# ---------------------------------------------------------------- the choice (pet writes)
static func read_choice() -> Dictionary:
	return SaveGame.read_newest(link_path(),
		func(d): return int(d.get("format", 0)) == FORMAT and d.has("card") and d.has("slot"),
		func(d): return float(d.get("written_at", 0.0)))


static func write_choice(card: String, slot: int, ask := true, declined := false) -> bool:
	return SaveGame.write_atomic(link_path(), JSON.stringify({"format": FORMAT, "card": card,
		"slot": slot, "ask": ask, "declined": declined,
		"written_at": Time.get_unix_time_from_system()}, "\t"))


## No save: he is Ninjamon of his own (the setup window's last row). Every copy goes, so
## read_choice can't fall back to a .bak.
static func clear_choice() -> void:
	for p in [link_path(), link_path() + ".tmp", link_path() + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


static func set_flags(ask: bool, declined: bool) -> bool:
	var c := read_choice()
	return not c.is_empty() and write_choice(str(c["card"]), int(c["slot"]), ask, declined)


# ---------------------------------------------------------------- the link
## His identity (DW1 has no uid): the slot, the raised count (+1 at every rebirth) and the tamer's
## name (a new game in that slot names him again). Same count, new species: he evolved.
static func uid(slot: int, dec: Dictionary) -> String:
	return "dw1:%d:%d:%s" % [slot, int(dec["raised_count"]), str(dec["tamer_raw"])]


## uid() plus an epoch for a new game under the same tamer name (CARD-3): New Game writes raised
## count 1 and zeroes the record (main.c:60073-60096), so a save without a record, raised once,
## whose play time is below what this uid was first seen with, is another partner (":<epoch>").
## Recorded in the journal's "partners" so the same save keeps its uid as its play time grows.
## A save state of the first life from before the link looks the same: its gains are set aside,
## never given to someone else.
static func identity(slot: int, dec: Dictionary, rec: Dictionary) -> String:
	var base := uid(slot, dec)
	var play := int(dec["play"][0]) * 60 + int(dec["play"][1])
	var j := read_journal(slot)
	var ids: Dictionary = j.get("partners", {})
	var e: Dictionary = ids.get(base, {})
	if e.is_empty() or (rec.is_empty() and int(dec["raised_count"]) == 1 and play < int(e["play"])):
		e = {"epoch": int(e.get("epoch", -1)) + 1, "play": play}
		ids[base] = e
		j["partners"] = ids
		write_journal(slot, j)
	return base if int(e["epoch"]) == 0 else "%s:%d" % [base, int(e["epoch"])]


## The pet's link (VpetSave.link_for's keys) for the chosen save, read from the card now; {} when
## the card or the save can't be read. data: GameData (techniques, care rows).
static func link(data, choice := {}) -> Dictionary:
	if choice.is_empty():
		choice = read_choice()
	if choice.is_empty():
		return {}
	var s := read_save(str(choice["card"]), int(choice["slot"]))
	if s.is_empty() or int(s["copy"]) < 0:
		return {}
	return link_for(int(choice["slot"]), s["payload"], data, VpetSave.read_pet(int(choice["slot"])),
		bool(choice.get("ask", true)), bool(choice.get("declined", false)),
		{"card": str(choice["card"]), "port": port_of(str(choice["card"]))})


## The save in a card file (Dw1Card.find), read again a few times when no copy passes its checksum:
## a read can meet DuckStation halfway through writing the card.
static func read_save(path: String, slot: int, tries := 3) -> Dictionary:
	var s := {}
	for i in tries:
		if i > 0:
			OS.delay_msec(200)
		s = Dw1Card.find(FileAccess.get_file_as_bytes(path), slot)
		if s.is_empty() or int(s["copy"]) >= 0:
			return s
	return s


static func link_for(slot: int, payload: PackedByteArray, data, pet: Dictionary, ask := true,
		declined := false, extra := {}) -> Dictionary:
	var dec := Dw1Card.decode(payload)
	var id := int(dec["type"])
	var c: Dictionary = data.care[id] if id >= 0 and id < data.care.size() else {}
	var species: Array = (data.digimon[id]["techniques"] as Array).map(func(t): return int(t["id"])) \
		if id >= 0 and id < data.digimon.size() else []
	var base := {}
	for k in ["weight", "happiness", "discipline", "max_hp", "max_mp", "off", "def", "spd", "brn"]:
		base[k] = int(dec[k])
	var rec := Dw1Card.spare(payload)
	var applied := applied_for(slot, rec, pet)
	var out := {"format": VpetSave.FORMAT, "slot": slot, "partner_uid": identity(slot, dec, rec), "partner_id": id,
		"partner_name": str(dec["name"]), "raised_count": int(dec["raised_count"]), "base": base,
		"care": {"poop_size": int(c.get("poop_size", 8)), "base_weight": int(c.get("base_weight", 10)),
			"fullness_needed": int(c.get("fullness_needed", 20))},
		"techniques": dec["learned"], "moves": Dw1Card.moves(dec["anims"], species, id),
		"care_mistakes": int(dec["care_mistakes"]), "battles": int(dec["battles"]),
		"virus": int(dec["virus"]), "stage_hours": int(dec["stage_hours"]), "raised": dec["raised"],
		"applied": applied["consumed"], "applied_file_id": applied["file_id"],
		"ask": ask, "declined": declined, "tamer": str(dec["tamer"]), "tamer_raw": str(dec["tamer_raw"]),
		"screen": int(dec["screen"]), "record": rec,
		"species": str(data.digimon[id]["name"]) if id >= 0 and id < data.digimon.size() else "",
		"written_at": Time.get_unix_time_from_system()}
	out.merge(extra)
	return out


## What the save's record says is applied: the journal's totals for its seq when the record is
## the pet file's ({consumed, file_id}); none ({}, "") otherwise. A record of this file whose seq
## the journal lost (its file deleted) counts everything so far as applied: never doubled.
static func applied_for(slot: int, rec: Dictionary, pet: Dictionary) -> Dictionary:
	var none := {"consumed": {}, "file_id": ""}
	var fid := str(pet.get("file_id", ""))
	if rec.is_empty() or pet.is_empty() or Dw1Card.file_key(fid) != int(rec["file"]):
		return none
	var snaps: Dictionary = (read_journal(slot).get("files", {}) as Dictionary).get(fid, {})
	var snap = snaps.get(str(int(rec["seq"])))
	if snap is Dictionary:
		return {"consumed": snap, "file_id": fid}
	push_warning("card: the save's record (seq %d) isn't in the journal: counted as applied" % int(rec["seq"]))
	return {"consumed": (pet.get("totals", {}) as Dictionary).duplicate(), "file_id": fid}


## The Partner VpetSave.pending() compares the pet's file with.
static func partner_of(link: Dictionary) -> Partner:
	var p := Partner.new()
	p.id = int(link.get("partner_id", 0))
	p.uid = str(link.get("partner_uid", ""))
	return p


static func pending(link: Dictionary, pet: Dictionary) -> Dictionary:
	if link.is_empty():
		return {"state": "none", "deltas": VpetSave.zeros(), "consumed": {}, "file_id": ""}
	return VpetSave.pending({"consumed": link.get("applied", {}), "file_id": link.get("applied_file_id", "")},
		pet, partner_of(link))


# ---------------------------------------------------------------- the pet's side
## DW1 has loaded his save: its slot (MEMORY_CARD_SLOT) on his card's port (MEMORY_CARD_ID: 0 port
## 1, 0x10 port 2; a card named without a port matches either).
## ram: the helper's "m" line as {slot, card, screen, type, raised, name, record} (pet_duck.cs).
## DW1 sets MEMORY_CARD_SLOT / _ID only in its card menus and they are 0 / 0 from boot (BSS), so
## the slot alone would match at the title (CARD-1): his save also needs the tamer's name in
## Digimon entry 0 (copied in by the load, FUN_80112d84, main.c:60235) and his raised count.
static func his_save(link: Dictionary, ram: Dictionary) -> bool:
	if link.is_empty() or ram.is_empty() or int(ram["slot"]) != int(link.get("slot", -1)):
		return false
	var port := int(link.get("port", 0))
	if port != 0 and int(ram["card"]) != (0 if port == 1 else 0x10):
		return false
	return names_tamer(str(ram["name"]), str(link.get("tamer_raw", ""))) \
		and int(ram["raised"]) == int(link.get("raised_count", -1))


## Whether entry 0's name in RAM (hex, 20 bytes) is this tamer's (NUL-terminated).
static func names_tamer(name_hex: String, tamer_hex: String) -> bool:
	return tamer_hex != "" and name_hex.begins_with(tamer_hex + "00")


## A save is being played at all (for the place comments): entry 0's name is no longer the EXE's
## own (`original`, hex), which the title shows until a load or New Game's naming.
static func save_loaded(ram: Dictionary, original: String) -> bool:
	return not ram.is_empty() and str(ram["name"]) != "-" and str(ram["name"]) != original


## The session holds an older record than the card (CARD-2): a resumed save state from before the
## gains were applied; its next save would put the old stats and record back (offered again later).
static func session_behind(link: Dictionary, ram: Dictionary) -> bool:
	var card: Dictionary = link.get("record", {})
	if card.is_empty() or ram.is_empty() or str(ram["record"]) == "-":
		return false
	var mine := Dw1Card.parse_spare(str(ram["record"]).hex_decode())
	return mine.is_empty() or int(mine["file"]) != int(card["file"]) or int(mine["seq"]) < int(card["seq"])


## The helper's "m" line, or {} for "m -".
static func parse_ram(line: String) -> Dictionary:
	var f := line.substr(2).split(" ")
	if f.size() != 7:
		return {}
	return {"slot": int(f[0]), "card": int(f[1]), "screen": int(f[2]), "type": int(f[3]),
		"raised": int(f[4]), "name": f[5], "record": f[6]}


## The gains as rows of the box (VpetSave.describe's items, packed to `width` characters).
static func apply_rows(deltas: Dictionary, width: int) -> Array:
	var items := []
	for l in VpetSave.describe(deltas):
		items.append_array(String(l).split("  ", false))
	var rows := []
	for it in items:
		if not rows.is_empty() and String(rows[-1]).length() + 2 + String(it).length() <= width:
			rows[-1] = String(rows[-1]) + "  " + String(it)
		else:
			rows.append(it)
	return rows


## apply_rows in pages of `per` rows, every page but the last marked " ..." (the pet's box shows a
## page at a time, turning while the window waits, so every gain is seen before Yes).
static func apply_pages(deltas: Dictionary, width: int, per := 2) -> Array:
	var rows := apply_rows(deltas, width)
	var pages := []
	for i in range(0, rows.size(), per):
		var page: Array = rows.slice(i, i + per)
		if i + per < rows.size():
			page[-1] = String(page[-1]) + " ..."
		pages.append(page)
	return pages


# ---------------------------------------------------------------- the journal
static func read_journal(slot: int) -> Dictionary:
	return SaveGame.read_newest(journal_path(slot), func(d): return int(d.get("format", 0)) == FORMAT,
		func(d): return float(d.get("written_at", 0.0)))


static func journal_add(slot: int, file_id: String, seq: int, consumed: Dictionary) -> bool:
	var j := read_journal(slot)
	var files: Dictionary = j.get("files", {})
	var snaps: Dictionary = files.get(file_id, {})
	snaps[str(seq)] = consumed                    # all kept: a save state can bring back any record (CARD-9)
	files[file_id] = snaps
	j["files"] = files
	return write_journal(slot, j)


static func write_journal(slot: int, j: Dictionary) -> bool:
	j["format"] = FORMAT
	j["written_at"] = Time.get_unix_time_from_system()
	return SaveGame.write_atomic(journal_path(slot), JSON.stringify(j, "\t"))


# ---------------------------------------------------------------- DuckStation
## DuckStation's processes (Windows' tasklist): the card can be written only while none runs.
static func duckstation_running() -> bool:
	var out := []
	if OS.execute("tasklist", ["/FO", "CSV", "/NH"], out, true) != 0 or out.is_empty():
		return true                               # can't tell: treated as running (never write blind)
	return str(out[0]).to_lower().contains("duckstation")


# ---------------------------------------------------------------- the apply
## Applies what the pet's file adds beyond the save's record: the deltas into the save's payload,
## the record (this file, its seq) into the spare block, both copies and checksums, the journal
## first. Refused while DuckStation runs, when the card changed partner under us, or when the
## written card doesn't read back. Returns {ok, error, deltas}.
static func apply(data, running := Callable(), shown := {}) -> Dictionary:
	if not running.is_valid():
		running = func() -> bool: return duckstation_running()
	var res := {"ok": false, "error": "", "deltas": {}}
	var choice := read_choice()
	if choice.is_empty():
		res["error"] = "no save chosen"
		return res
	if running.call():
		res["error"] = "DuckStation is running"
		return res
	var path := str(choice["card"])
	var slot := int(choice["slot"])
	var card := FileAccess.get_file_as_bytes(path)
	var s := Dw1Card.find(card, slot)
	if s.is_empty() or int(s["copy"]) < 0:
		res["error"] = "the save can't be read (both copies damaged, or gone)"
		return res
	var pet := VpetSave.read_pet(slot)
	var l := link_for(slot, s["payload"], data, pet)
	var m := pending(l, pet)
	if m["state"] != "pending":
		res["error"] = "nothing to apply" if m["state"] == "none" else "the save holds another partner"
		return res
	if not shown.is_empty() and shown != m["deltas"]:   # the totals moved while the window waited (CARD-6)
		res["error"] = "changed"
		return res
	var p := Dw1Card.apply(s["payload"], m["deltas"])
	p = Dw1Card.with_spare(p, {"raised": int(l["raised_count"]), "key": Dw1Card.crc32(str(l["partner_uid"]).to_utf8_buffer()),
		"file": Dw1Card.file_key(str(pet["file_id"])), "seq": int(pet["seq"])})
	if not journal_add(slot, str(pet["file_id"]), int(pet["seq"]), m["consumed"]):
		res["error"] = "can't write the journal"
		return res
	var out := Dw1Card.with_payload(card, int(s["frame"]), p)
	if not backup(path, card):
		res["error"] = "can't back up the card"
		return res
	if running.call():                            # checked again right before the write
		res["error"] = "DuckStation is running"
		return res
	var err := write_card(path, out)
	if err != "":
		res["error"] = err
		return res
	var back := Dw1Card.find(FileAccess.get_file_as_bytes(path), slot)
	if back.is_empty() or int(back["copy"]) != 0 or back["payload"] != Dw1Card.find(out, slot)["payload"]:
		write_card(path, card)                    # put the card back as it was
		res["error"] = "the card didn't read back; restored"
		return res
	set_flags(bool(choice.get("ask", true)), false)
	res["ok"] = true
	res["deltas"] = m["deltas"]
	return res


## Replaces the card file: written beside it, then swapped in (the old one renamed aside first,
## put back if the swap fails). "" or why it failed.
static func write_card(path: String, bytes: PackedByteArray) -> String:
	var tmp := path + ".dscreen-tmp"
	var old := path + ".dscreen-old"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "can't write %s" % tmp
	f.store_buffer(bytes)
	f.close()
	if FileAccess.get_file_as_bytes(tmp) != bytes:
		DirAccess.remove_absolute(tmp)
		return "the new card didn't write fully"
	var out := []                                 # cmd's move /y: one MoveFileEx, the card never missing (CARD-10)
	if OS.execute("cmd", ["/c", "move", "/y", tmp.replace("/", "\\"), path.replace("/", "\\")], out, true) == 0 \
			and not FileAccess.file_exists(tmp):
		return ""
	if FileAccess.file_exists(old):
		DirAccess.remove_absolute(old)
	if DirAccess.rename_absolute(path, old) != OK:
		DirAccess.remove_absolute(tmp)
		return "can't move the card aside"
	if DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.rename_absolute(old, path)
		return "can't put the new card in place"
	DirAccess.remove_absolute(old)
	return ""


## Keeps a copy of the card as it was before a write; at most BACKUPS per card.
static func backup(path: String, card: PackedByteArray) -> bool:
	var dir := backup_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var stem := path.get_file().get_basename()
	var f := FileAccess.open(dir + "%s.%d.mcd" % [stem, int(Time.get_unix_time_from_system() * 1000000.0)], FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(card)
	f.close()
	var mine := []
	for n in DirAccess.get_files_at(dir):
		if n.begins_with(stem + ".") and n.ends_with(".mcd"):
			mine.append(n)
	mine.sort_custom(func(a, b): return int(a.get_slice(".", a.get_slice_count(".") - 2)) < int(b.get_slice(".", b.get_slice_count(".") - 2)))
	while mine.size() > BACKUPS:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + str(mine.pop_front())))
	return true
