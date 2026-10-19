class_name Dw1Card
extends RefCounted
## DW1's saves on a memory card (docs/memcard_bridge.md sections 3-5, 10): D-Screen's card bridge.
## A card image (DuckStation's .mcd, 128 KB) holds each game in its own one-block file
## BASLUS-01032DMR<n> (n = 0-9, A-E): a header, then two identical 0xF00-byte payload copies, each
## with a byte-sum checksum. Continue loads copy 0 if its checksum matches, else copy 1, else
## nothing (main.c:59352-59378). Payload bytes 0x4E4-0x4FB are never written or read by DW1 and
## sit outside the checksum: the bridge keeps its record there (SPARE), so whichever version of
## the save survives carries a matching record: gains are delayed, never lost or doubled.
## Pure: bytes in, bytes out. The pet's side (which save, the journal, the window) is CardLink.

const SIZE := 131072
const FRAME := 128
const BLOCK := 8192
const NAME := "BASLUS-01032DMR"
const SLOT_CHARS := "0123456789ABCDE"     # FUN_8010ff1c: '0'-'9' -> 0-9, else c - 0x37 (15 entries)
const COPIES: Array[int] = [0x200, 0x1100]
const PAYLOAD := 0xF00
const SUM_AT := 0x4FC                     # the stored checksum, inside each copy
const SPARE := 0x4E4                      # 24 bytes, never written by DW1, outside the checksum
const SPARE_SIZE := 24
const MAGIC := "DWVP"
const VERSION := 1
const FREE_STATE := 0xA0
## Payload offsets (docs/memcard_bridge.md 3b; PARTNER_PARA at 0x1E0 = RAM 0x80138460).
const TYPE := 0x1B8
const LEARNED := 0x1BC                    # learnedMoves[2] (u32 x 2): bit n = technique n
const PLAY_FRAMES := 0x1D8
const PLAY_HOURS := 0x1DA
const PLAY_MINUTES := 0x1DC
const PARA := 0x1E0
const VIRUS := PARA + 0x1E
const DISCIPLINE := PARA + 0x28
const HAPPINESS := PARA + 0x2A
const WEIGHT := PARA + 0x42
const CARE_MISTAKES := PARA + 0x52
const BATTLES := PARA + 0x54
const STAGE_HOURS := PARA + 0x56
const STATS := 0x270                      # Off Def Spd Brn (s16), priorities, moves (anim ids)
const MAX_HP := 0x280
const MAX_MP := 0x282
const GAME_STATE := 0x290                 # triggers at +0xF5
const TRIGGERS := GAME_STATE + 0xF5
const TAMER_NAME := 0x467
const PARTNER_NAME := 0x47B
const LIVES := 0x48F
const RAISED := 0x491
const SCREEN := 0x49A
const ANIM_MOVES := 0x2E                  # an equipped move is stored as animation 0x2E + list index
const RAISED_TRIGGER := 0x200
const SUKAMON := 0x27
## Where the deltas land, with FUN_800a568c's and the stat screens' limits (VpetSave.STAT_MAX).
const STAT_AT := {"off": STATS, "def": STATS + 2, "spd": STATS + 4, "brn": STATS + 6,
	"max_hp": MAX_HP, "max_mp": MAX_MP}
const STAT_MAX := {"off": 999, "def": 999, "spd": 999, "brn": 999, "max_hp": 9999, "max_mp": 9999}


# ---------------------------------------------------------------- the card
## The slot a save's name holds, or -1 (another game's file, or a name DW1 would mis-index).
static func slot_of(name: String) -> int:
	if not name.begins_with(NAME) or name.length() != NAME.length() + 1:
		return -1
	return SLOT_CHARS.find(name[-1])


## FUN_80112d34: the byte sum of copy n's payload [0, 0x4E4) and [0x500, 0xF00).
static func checksum(block: PackedByteArray, n: int) -> int:
	var p := COPIES[n]
	var s := 0
	for i in range(p, p + SPARE):
		s += block[i]
	for i in range(p + 0x500, p + PAYLOAD):
		s += block[i]
	return s


static func stored(block: PackedByteArray, n: int) -> int:
	return block.decode_s32(COPIES[n] + SUM_AT)


## The copy DW1's Continue loads: 0, 1, or -1 (both bad: DW1 shows its error and loads nothing).
static func pick(block: PackedByteArray) -> int:
	for n in 2:
		if stored(block, n) == checksum(block, n):
			return n
	return -1


## Every DW1 save on the card: [{slot, frame, name, copy (-1 = both bad), payload, species (the
## header's ASCII name from the EXE that wrote it)}], by slot. {} entries for other games are
## skipped, and so are free frames and names DW1 wouldn't list.
static func saves(card: PackedByteArray) -> Array:
	var out := []
	if card.size() < SIZE or card[0] != 0x4D or card[1] != 0x43:    # "MC"
		return out
	for f in range(1, 16):
		var fr := card.slice(f * FRAME, (f + 1) * FRAME)
		if fr.decode_u32(0) & 0xFF != 0x51:                          # in use, first block of a file
			continue
		var name := _cstr(fr.slice(10, 30))
		var slot := slot_of(name)
		if slot < 0:
			continue
		var block := card.slice(f * BLOCK, (f + 1) * BLOCK)
		var c := pick(block)
		out.append({"slot": slot, "frame": f, "name": name, "copy": c,
			"payload": block.slice(COPIES[c], COPIES[c] + PAYLOAD) if c >= 0 else PackedByteArray(),
			"species": _cstr(block.slice(0x20, 0x31))})
	out.sort_custom(func(a, b): return a["slot"] < b["slot"])
	return out


static func find(card: PackedByteArray, slot: int) -> Dictionary:
	for s in saves(card):
		if s["slot"] == slot:
			return s
	return {}


## The card with the save in `frame` replaced by payload p in both copies, each copy's checksum
## recomputed (as DW1's own save: copy 0 summed, then copied to copy 1; main.c:58803-58827).
## The header and the directory frame are untouched.
static func with_payload(card: PackedByteArray, frame: int, p: PackedByteArray) -> PackedByteArray:
	var out := card.duplicate()
	var b := frame * BLOCK
	for n in 2:
		var at := b + COPIES[n]
		for i in PAYLOAD:
			out[at + i] = p[i]
	var block := out.slice(b, b + BLOCK)
	for n in 2:
		out.encode_s32(b + COPIES[n] + SUM_AT, checksum(block, n))
	return out


# ---------------------------------------------------------------- the payload
## The partner as the pet needs him (VpetSave.link_for's fields, DW1 units).
static func decode(p: PackedByteArray) -> Dictionary:
	var learned := []
	for i in 64:
		if p[LEARNED + (i >> 3)] >> (i & 7) & 1:
			learned.append(i)
	var raised := []
	for id in 0x40:
		var t := RAISED_TRIGGER + id
		if p[TRIGGERS + (t >> 3)] >> (t & 7) & 1:
			raised.append(id)
	var anims := []
	for i in 4:
		anims.append(p[STATS + 12 + i])
	return {"type": p.decode_s32(TYPE),
		"off": p.decode_s16(STATS), "def": p.decode_s16(STATS + 2), "spd": p.decode_s16(STATS + 4),
		"brn": p.decode_s16(STATS + 6), "max_hp": p.decode_s16(MAX_HP), "max_mp": p.decode_s16(MAX_MP),
		"weight": p.decode_s16(WEIGHT), "happiness": p.decode_s16(HAPPINESS),
		"discipline": p.decode_s16(DISCIPLINE), "virus": p.decode_s16(VIRUS),
		"care_mistakes": p.decode_s16(CARE_MISTAKES), "battles": p.decode_s16(BATTLES),
		"stage_hours": p.decode_s16(STAGE_HOURS), "learned": learned, "anims": anims, "raised": raised,
		"tamer": sjis_text(p.slice(TAMER_NAME, TAMER_NAME + 20)),
		"tamer_raw": _until_nul(p.slice(TAMER_NAME, TAMER_NAME + 20)).hex_encode(),
		"name": sjis_text(p.slice(PARTNER_NAME, PARTNER_NAME + 20)),
		"lives": p[LIVES], "raised_count": p[RAISED], "screen": p[SCREEN],
		"play": [p.decode_u16(PLAY_HOURS), p.decode_u16(PLAY_MINUTES)]}


## Equipped animation ids -> technique ids through the species' list (Techniques.slot_move:
## Digimon table moves[anim - 0x2E]; 0xFF = none -> -1).
static func moves(anims: Array, species_moves: Array, type: int) -> Array:
	var out := []
	for a in anims:
		var n := int(a) - ANIM_MOVES
		if int(a) == 0xFF or n < 0:
			out.append(-1)
		elif type == 0x3C and n == 14:
			out.append(112)
		else:
			out.append(int(species_moves[n]) if n < species_moves.size() else -1)
	return out


## The deltas of VpetSave.pending() added to the payload, within DW1's limits (CareSim.clamp_state:
## happiness -100..100, discipline 0..100, weight 1..99; stats 999, max HP / MP 9999). Current
## HP / MP stay as they are (as the remake's apply).
static func apply(p: PackedByteArray, deltas: Dictionary) -> PackedByteArray:
	var out := p.duplicate()
	for k in STAT_AT:
		out.encode_s16(STAT_AT[k], mini(out.decode_s16(STAT_AT[k]) + int(deltas.get(k, 0)), STAT_MAX[k]))
	out.encode_s16(HAPPINESS, clampi(out.decode_s16(HAPPINESS) + int(deltas.get("happy_up", 0))
		- int(deltas.get("happy_down", 0)), -100, 100))
	out.encode_s16(DISCIPLINE, clampi(out.decode_s16(DISCIPLINE) + int(deltas.get("disc_up", 0))
		- int(deltas.get("disc_down", 0)), 0, 100))
	out.encode_s16(WEIGHT, clampi(out.decode_s16(WEIGHT) + int(deltas.get("weight_up", 0))
		- int(deltas.get("weight_down", 0)), 1, 99))
	out.encode_s16(CARE_MISTAKES, mini(out.decode_s16(CARE_MISTAKES) + int(deltas.get("care_mistakes", 0)), 0x7FFF))
	if out.decode_s32(TYPE) != SUKAMON:                     # DW1 never raises it on Sukamon (main.c:9486, CARD-7)
		out.encode_s16(VIRUS, mini(out.decode_s16(VIRUS) + int(deltas.get("virus", 0)), 0x7FFF))
	return out


# ---------------------------------------------------------------- the spare block
## {file: the pet file id's first 32 bits, seq: the pet file's seq whose totals are applied,
## raised: the raised count when written}; {} when the block isn't ours (zeros: never applied).
static func spare(p: PackedByteArray) -> Dictionary:
	return parse_spare(p.slice(SPARE, SPARE + SPARE_SIZE))


## A record's 24 bytes (from a payload, or DW1's card buffer in RAM: the record Continue read in).
static func parse_spare(b: PackedByteArray) -> Dictionary:
	if b.size() != SPARE_SIZE or b.slice(0, 4).get_string_from_ascii() != MAGIC or b[4] != VERSION:
		return {}
	if b.decode_u32(20) != crc32(b.slice(0, 20)):
		return {}
	return {"raised": b.decode_u16(6), "file": b.decode_u32(12), "seq": b.decode_u32(16)}


static func with_spare(p: PackedByteArray, rec: Dictionary) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(SPARE_SIZE)
	var magic := MAGIC.to_ascii_buffer()
	for i in 4:
		b[i] = magic[i]
	b[4] = VERSION
	b.encode_u16(6, int(rec.get("raised", 0)))
	b.encode_u32(8, int(rec.get("key", 0)))
	b.encode_u32(12, int(rec.get("file", 0)))
	b.encode_u32(16, int(rec.get("seq", 0)))
	b.encode_u32(20, crc32(b.slice(0, 20)))
	var out := p.duplicate()
	for i in SPARE_SIZE:
		out[SPARE + i] = b[i]
	return out


## The pet file id ("hex...") as the block's 32 bits.
static func file_key(file_id: String) -> int:
	return file_id.substr(0, 8).hex_to_int() if file_id.length() >= 8 else 0


static var _crc_table := PackedInt64Array()


static func crc32(b: PackedByteArray) -> int:
	if _crc_table.is_empty():
		_crc_table.resize(256)
		for n in 256:
			var c := n
			for k in 8:
				c = (0xEDB88320 ^ (c >> 1)) if c & 1 else c >> 1
			_crc_table[n] = c
	var crc := 0xFFFFFFFF
	for x in b:
		crc = _crc_table[(crc ^ x) & 0xFF] ^ (crc >> 8)
	return crc ^ 0xFFFFFFFF


# ---------------------------------------------------------------- text
## A DW1 name (Shift-JIS from the naming keyboard: full-width letters, digits, the punctuation
## DwText knows) as ASCII; stops at the first NUL (the bytes after it are junk).
static func sjis_text(raw: PackedByteArray) -> String:
	var s := ""
	var i := 0
	while i < raw.size() and raw[i] != 0:
		var c := raw[i]
		if c < 0x80:
			s += String.chr(c)
			i += 1
			continue
		if i + 1 >= raw.size():
			break
		var code := c << 8 | raw[i + 1]
		i += 2
		if code >= 0x8260 and code <= 0x8279:
			s += String.chr(0x41 + code - 0x8260)
		elif code >= 0x8281 and code <= 0x829A:
			s += String.chr(0x61 + code - 0x8281)
		elif code >= 0x824F and code <= 0x8258:
			s += String.chr(0x30 + code - 0x824F)
		else:
			var ch := "?"
			for k in DwText.PUNCT:
				if int(DwText.PUNCT[k]) == code:
					ch = k
					break
			s += ch
	return s


static func _until_nul(raw: PackedByteArray) -> PackedByteArray:
	var n := raw.find(0)
	return raw if n < 0 else raw.slice(0, n)


static func _cstr(raw: PackedByteArray) -> String:
	return _until_nul(raw).get_string_from_ascii()
