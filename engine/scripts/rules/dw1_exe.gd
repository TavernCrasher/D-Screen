class_name Dw1Exe
extends RefCounted
## DW1's tables read straight from the player's SLUS_010.32 (docs/shareable_pet_plan.md
## step 2): the parts of tools/dump_tables.py the pet uses, giving the same rows as
## data/*.json, plus the model file names and skeletons the model loader needs
## (tools/dw1_model_size.py). Addresses and field notes: dump_tables.py, docs/data_tables.md.

const LOAD := 0x80090800
const HDR := 0x800

const DIGIMON_TABLE := 0x8012CEB4   # 180 x 52
const DIGIMON_COUNT := 180
const TECH_NAME_PTRS := 0x80126054  # 121 x u32 pointers to names
const TECH_TABLE := 0x80126240      # 121 x 16 (the Move record starts 4 bytes earlier)
const TECH_COUNT := 121
const FLAT_BULLET := 121            # hidden record 0x79, no name pointer
const LEARN_CHANCE := 0x80125FA4    # u8[58][3]
const ITEM_TABLE := 0x801269DC      # 128 x 32
const ITEM_COUNT := 128
const EVO_ITEM_TARGETS := 0x80127C15
const EVO_ITEM_SPECIAL := {125: 64, 126: 63, 127: 65}   # Giga Hand, Noble Mane, Metalbanana
## A disc whose EXE keeps these tables elsewhere (a mod that moves them) is refused: D-Screen
## reads the original DW1 (USA) only. SydMontague advised against building on SydPatches'
## layout, which is unfinished and will move (2026-10-19).
const EVO_PATHS := 0x8012B66C       # 62 x 11 (from[5], to[6]), index id-1
const EVO_PATH_COUNT := 62
const CARE_TABLE := 0x801225BC      # 28 bytes per id; 66 rows, then the sleep schedules
## The care table's loader, lui/addiu = table + 8: a mod that moves the table re-points it.
const CARE_LOADER := 0x80105354
const SLEEP_SCHEDULES := 0x80122CF4  # 8 x 6 bytes
const SLEEP_COUNT := 8
const EVO_REQS := 0x8012ABEC        # 28 bytes per id, 14 x s16, -1 = none; ids 0-62
const EVO_REQS_SIZE := 63 * 28      # right before the gains
const RECYCLE_ITEMS := 0x8012FE78   # 78 item ids
const EVO_GAINS := 0x8012B2D0       # 7 x s16 per target id; 66 rows, then the paths
## EVL_REL.BIN (loaded at 0x80060000): li v0, gains at 0x80063390.
const EVL_LOAD := 0x80060000
const EVL_GAINS_LOADER := 0x80063390
const FILE_NAMES := 0x80133B44      # 180 x char[8] -> CHDAT/MMD<id/30>/<name>.MMD
const MAP_ENTRIES := 0x801292D4     # 255 x 16 (dw1_maps.py): byte 15 the loading name
const MAP_COUNT := 255
const AREA_NAMES := 0x801291BC      # area name pointers, by the map entry's loading name
const SKELETONS := 0x8011CE60       # 180 x pointer to {s8 object, s8 parent}[bones]
const MODDED := "a modded disc (its tables have moved): D-Screen reads the original Digimon World (USA) only"

const TYPES := {1: "Data", 2: "Vaccine", 3: "Virus"}
const STATUSES := {0: null, 1: "poison", 2: "confuse", 3: "stun", 4: "flatten"}
const LEVELS := {1: "Fresh", 2: "In-Training", 3: "Rookie", 4: "Champion", 5: "Ultimate"}
const SPECIALTIES := ["Fire", "Battle", "Air", "Earth", "Ice", "Mech", "Filth"]

var d: PackedByteArray
var evl: PackedByteArray            # EVL_REL.BIN, for the gains loader (empty: vanilla address)
var care_base := CARE_TABLE
var sleep_base := SLEEP_SCHEDULES
var gains_base := EVO_GAINS
var reqs_base := EVO_REQS
var paths_base := EVO_PATHS         # id 1's row
var error := ""                     # why the tables can't be trusted ("" = fine)


func _init(exe: PackedByteArray, evl_rel := PackedByteArray()) -> void:
	d = exe
	evl = evl_rel
	error = _locate()


## The tables of the disc's EXE, or null when the disc isn't DW1 (USA) or its EXE doesn't
## check out (an unknown mod: check() says why through from_disc_checked()).
static func from_disc(disc: Dw1Disc) -> Dw1Exe:
	var x := from_disc_checked(disc)
	return x if x != null and x.error.is_empty() else null


static func from_disc_checked(disc: Dw1Disc) -> Dw1Exe:
	if disc == null or not disc.is_dw1_usa():
		return null
	return Dw1Exe.new(disc.read(Dw1Disc.DW1_SERIAL), disc.read("EVL_REL.BIN"))


## Refuses a mod that moved the tables (their loaders point elsewhere), then checks the EXE:
## "" or what is wrong.
func _locate() -> String:
	if d.size() < 0x800 or d.slice(0, 8).get_string_from_ascii() != "PS-X EXE" or d.decode_u32(0x18) != LOAD:
		return "not a PS-X EXE loaded at 0x80090800"
	if not valid(FILE_NAMES + 8 * DIGIMON_COUNT):
		return "EXE too short"
	var g := _li(evl, EVL_LOAD, EVL_GAINS_LOADER)
	if care_table() != CARE_TABLE or (g > 0 and g != EVO_GAINS):
		return MODDED
	return check()


## The address a lui + addiu/ori pair at addr builds (code loaded at load), or -1.
static func _li(code: PackedByteArray, load: int, addr: int) -> int:
	var o := addr - load
	if o < 0 or o + 8 > code.size():
		return -1
	var hi := code.decode_u32(o)
	var lo_ins := code.decode_u32(o + 4)
	if hi >> 26 != 0x0F or (lo_ins >> 26 != 0x09 and lo_ins >> 26 != 0x0D):
		return -1
	var lo := lo_ins & 0xFFFF
	if lo_ins >> 26 == 0x09 and lo >= 0x8000:   # addiu sign-extends; ori doesn't
		lo -= 0x10000
	return ((hi & 0xFFFF) << 16) + lo


## 62 rows of Digimon ids (vanilla's hold a few 0s and 0xFEs too), Botamon from nobody.
func _paths_ok(at: int) -> bool:
	if not valid(at + 11 * EVO_PATH_COUNT):
		return false
	for k in 11 * EVO_PATH_COUNT:
		var b := u8(at + k)
		if b >= DIGIMON_COUNT and b < 0xFE:
			return false
	return bytes(at, 5) == PackedByteArray([255, 255, 255, 255, 255])


## Sanity checks the EXE must pass before its rows are used: "" or the first problem.
func check() -> String:
	for i in range(1, DIGIMON_COUNT):
		var r := DIGIMON_TABLE + 52 * i
		if u8(r + 0x1D) > 5:
			return "Digimon %d: level %d" % [i, u8(r + 0x1D)]
		for s in bytes(r + 0x1E, 3):
			if s != 0xFF and s >= SPECIALTIES.size():
				return "Digimon %d: specialty %d" % [i, s]
		for m in bytes(r + 0x23, 16):
			if m != 0xFF and m > TECH_COUNT:
				return "Digimon %d: technique %d" % [i, m]
	for s in SLEEP_COUNT:
		var sc := sleep_base + 6 * s
		if u8(sc) > 23 or u8(sc + 1) > 59 or u8(sc + 2) > 23 or u8(sc + 3) > 59:
			return "sleep schedule %d" % s
	for i in 66:
		if u8(care_base + 28 * i + 0x12) >= SLEEP_COUNT:
			return "care row %d: sleep schedule %d" % [i, u8(care_base + 28 * i + 0x12)]
	if not _paths_ok(paths_base):
		return "evolution paths"
	return ""


func off(addr: int) -> int:
	return addr - LOAD + HDR


func valid(addr: int) -> bool:
	return addr >= LOAD and off(addr) < d.size()


func u8(addr: int) -> int:
	return d[off(addr)]


func s8(addr: int) -> int:
	return d.decode_s8(off(addr))


func s16(addr: int) -> int:
	return d.decode_s16(off(addr))


func u16(addr: int) -> int:
	return d.decode_u16(off(addr))


func s32(addr: int) -> int:
	return d.decode_s32(off(addr))


func u32(addr: int) -> int:
	return d.decode_u32(off(addr))


func bytes(addr: int, n: int) -> PackedByteArray:
	return d.slice(off(addr), off(addr) + n)


## A map's area name (the loading screen's, services.json area_names): MAP_ENTRIES[map] byte 15
## indexes AREA_NAMES' pointers. "" for a map or an index outside the tables.
func area_name(map: int) -> String:
	if map < 0 or map >= MAP_COUNT:
		return ""
	var p := u32(AREA_NAMES + 4 * u8(MAP_ENTRIES + 16 * map + 15))
	return cstr(p).strip_edges() if valid(p) else ""


## A NUL-terminated string, decoded as latin1 (as dump_tables.py does).
func cstr(addr: int, maxlen := 64) -> String:
	return latin1(bytes(addr, maxlen))


static func latin1(raw: PackedByteArray) -> String:
	var s := ""
	for b in raw:
		if b == 0:
			break
		s += String.chr(b)
	return s


func _u8_list(addr: int, n: int, skip_ff := false) -> Array:
	var out := []
	for b in bytes(addr, n):
		if not (skip_ff and b == 0xFF):
			out.append(b)
	return out


func techniques() -> Array:
	var out := []
	for i in TECH_COUNT + 1:
		var name := "Flat Bullet" if i == FLAT_BULLET else cstr(u32(TECH_NAME_PTRS + 4 * i))
		var r := TECH_TABLE + 16 * i
		var el := u8(r + 5)
		out.append({
			"id": i,
			"name": name,
			"distance": s32(r - 4),
			"power": s16(r),
			"mp_cost": u8(r + 2) * 3,
			"stagger": u8(r + 3),
			"type": u8(r + 4),
			"element": SPECIALTIES[el] if el < SPECIALTIES.size() else el,
			"status": STATUSES.get(u8(r + 6), u8(r + 6)),
			"accuracy": u8(r + 7),
			"status_chance": u8(r + 8),
			"flags": u8(r + 9),
			"is_finisher": i >= 58 and i <= 112,
			"learn_chance": _u8_list(LEARN_CHANCE + 3 * i, 3) if i < 58 else [0, 0, 0],
			"unk_10_11": "%02x %02x" % [u8(r + 10), u8(r + 11)],
		})
	return out


func digimon(tech_names := []) -> Array:
	if tech_names.is_empty():
		tech_names = techniques().map(func(t: Dictionary) -> String: return t["name"])
	var out := []
	for i in DIGIMON_COUNT:
		var r := DIGIMON_TABLE + 52 * i
		var moves := [] if i == 0 else _u8_list(r + 0x23, 16, true)
		var gains := []
		for k in 7:
			gains.append(s16(gains_base + 14 * i + 2 * k))
		var specs := []
		var slots := []
		for s in bytes(r + 0x1E, 3):
			var sp = SPECIALTIES[s] if s < SPECIALTIES.size() else (null if s == 0xFF else s)
			slots.append(sp)
			if s != 0xFF:
				specs.append(sp)
		out.append({
			"evo_gains": gains,
			"id": i,
			"name": cstr(r, 20),
			"bone_count": u32(r + 20),
			"radius": u16(r + 24),
			"height": u16(r + 26),
			"type": TYPES.get(u8(r + 0x1C), u8(r + 0x1C)),
			"level": LEVELS.get(u8(r + 0x1D), u8(r + 0x1D)),
			"specialties": specs,
			"specialty_slots": slots,
			"drop_item": u8(r + 0x21),
			"drop_chance": u8(r + 0x22),
			"techniques": moves.map(func(m: int) -> Dictionary:
				return {"id": m, "name": tech_names[m] if m < tech_names.size() else null}),
		})
	return out


## The evolution graph and requirements (dump_tables.evolution; the scoring is
## EvolutionRules, docs/data_tables.md).
func evolution(names := []) -> Array:
	if names.is_empty():
		names = digimon().map(func(e: Dictionary) -> String: return e["name"])
	var out := []
	for i in range(1, EVO_PATH_COUNT + 1):
		var p := bytes(paths_base + 11 * (i - 1), 11)
		var v := []
		for k in 14:
			v.append(s16(reqs_base + 28 * i + 2 * k))
		var flags: int = v[13] & 0xFFFF
		var from := []
		var to := []
		for k in 11:
			if p[k] != 0xFF:
				(from if k < 5 else to).append(p[k])
		out.append({
			"id": i,
			"name": names[i],
			"from": from,
			"to": to,
			"requirements": {
				"hp": _stat10(v[1]),
				"mp": _stat10(v[2]),
				"offense": _opt(v[3]),
				"defense": _opt(v[4]),
				"speed": _opt(v[5]),
				"brains": _opt(v[6]),
				"care_mistakes": _opt(v[7]),
				"care_mistakes_is_max": flags & 0x10 != 0,
				"weight": _opt(v[8]),
				"bonus_digimon": _opt(v[0]),
				"bonus_discipline": _opt(v[9]),
				"bonus_happiness": _opt(v[10]),
				"bonus_battles": _opt(v[11]),
				"bonus_battles_is_max": flags & 0x01 != 0,
				"bonus_techniques": _opt(v[12]),
				"flags_raw": flags,
			},
		})
	return out


static func _opt(x: int) -> Variant:
	return null if x == -1 else x


## dump_tables' `opt(v) and v * 10`: -1 = none, 0 stays 0.
static func _stat10(x: int) -> Variant:
	return null if x == -1 else x * 10


## The care table's base from its loader, else CARE_TABLE (a moved table means a mod: _locate).
func care_table() -> int:
	var a := _li(d, LOAD - HDR, CARE_LOADER)
	return CARE_TABLE if a < 0 else a - 8


func care(names := [], item_names := []) -> Array:
	if names.is_empty():
		names = digimon().map(func(e: Dictionary) -> String: return e["name"])
	if item_names.is_empty():
		item_names = items().map(func(e: Dictionary) -> String: return e["name"])
	var out := []
	for i in DIGIMON_COUNT:                  # as dump_tables: rows past 65 aren't care data
		var r := care_base + 28 * i
		var sid := u8(r + 0x12)
		var sc := sleep_base + 6 * sid
		var fav := u8(r + 0x11)
		out.append({
			"id": i,
			"name": names[i],
			"hunger_hours": _u8_list(r, 8, true),
			"fullness_max": u8(r + 0x08),
			"fullness_needed": u8(r + 0x09),
			"fullness_drain_per_hour": u8(r + 0x0A),
			"unk_0b": u8(r + 0x0B),
			"poop_timer": s16(r + 0x0C),
			"unk_0e": s16(r + 0x0E),
			"poop_size": u8(r + 0x10),
			"favorite_food": {"id": fav, "name": item_names[fav] if fav < item_names.size() else null},
			"sleep_schedule": {
				"id": sid,
				"sleep": "%02d:%02d" % [u8(sc), u8(sc + 1)],
				"wake": "%02d:%02d" % [u8(sc + 2), u8(sc + 3)],
				"awake_hours": u8(sc + 4),
				"sleep_hours": u8(sc + 5),
			},
			"unk_13": u8(r + 0x13),
			"training_affinity": u8(r + 0x14),
			"base_weight": u8(r + 0x15),
			"unk_16_xyz": [s16(r + 0x16), s16(r + 0x18), s16(r + 0x1A)],
		})
	return out


func items() -> Array:
	var recycle := _u8_list(RECYCLE_ITEMS, 78)
	var out := []
	for i in ITEM_COUNT:
		var r := ITEM_TABLE + 32 * i
		var row := {
			"id": i,
			"name": cstr(r, 20),
			"price": u32(r + 20),
			"merit": s16(r + 24),
			"sort": s16(r + 26),
			"color": u8(r + 28),
			"droppable": u8(r + 29) != 0,
			"unk_30": u16(r + 30),
			"recycle_slot": recycle.find(i),
		}
		if i >= 71 and i <= 114:
			row["evo_target"] = u8(EVO_ITEM_TARGETS + i)
		elif EVO_ITEM_SPECIAL.has(i):
			row["evo_target"] = EVO_ITEM_SPECIAL[i]
		out.append(row)
	return out


## A Digimon's model file name ("AGUMON"), "" if none.
func model_name(id: int) -> String:
	return cstr(FILE_NAMES + 8 * id, 8)


## Its bone count (the Digimon table's word at +20), 0 for an id past the table.
func bone_count(id: int) -> int:
	return u32(DIGIMON_TABLE + 52 * id + 20) if id >= 0 and id < DIGIMON_COUNT else 0


## Its model's path on the disc, "" if none.
func model_path(id: int) -> String:
	var n := model_name(id)
	return "" if n.is_empty() else "CHDAT/MMD%d/%s.MMD" % [id / 30, n]


## Its skeleton: [object, parent] per bone (s8, -1 = root), [] if none.
func skeleton(id: int, bones: int) -> Array:
	var ptr := u32(SKELETONS + 4 * id)
	if ptr == 0 or ptr < LOAD or not valid(ptr + 2 * bones):
		return []
	var out := []
	for b in bones:
		out.append([s8(ptr + 2 * b), s8(ptr + 2 * b + 1)])
	return out
