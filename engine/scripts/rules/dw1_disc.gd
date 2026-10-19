class_name Dw1Disc
extends RefCounted
## The player's own DW1 disc image, read in place every launch (docs/shareable_pet_plan.md
## step 1). A port of tools/extract_disc.py: raw 2352-byte sectors (MODE2/2352 as DW1 is, or
## MODE1/2352) from a .cue/.bin, or plain 2048-byte sectors from an .iso; an .m3u opens its
## first disc. The ISO9660 tree is walked once at open; read(path) returns a file's bytes.
## A .chd is read through the pet's helper (pet/pet_chd.cs, built by WinHelper), which decodes
## only the hunks a read touches; find_images() also lists OTHER_EXTS so the first-run window
## can say they aren't read.

const RAW := 2352
const USER := 2048
const FORM2_BIT := 0x20          # XA subheader submode byte (raw offset 18)
const DW1_SERIAL := "SLUS_010.32"
const IMAGE_EXTS := ["cue", "bin", "iso", "img", "m3u", "chd"]
## Formats DuckStation opens that this reader doesn't: listed so the first-run window can say so.
const OTHER_EXTS := ["ecm", "pbp", "mds", "ccd"]
const SCAN_DEPTH := 6            # find_images() walks DuckStation's folders this deep
const SCAN_MAX := 20000          # and looks at no more entries than this

var path := ""                   # the image file the sectors come from (the .bin of a .cue)
var sector_size := RAW
var data_offset := 24            # 12 sync + 4 header + 8 subheader (MODE2 XA); 16 MODE1; 8 MODE2/2336; 0 ISO
var submode := 18                # the XA subheader's submode byte in a stored sector, -1 = none (MODE1, ISO)
var byte_offset := 0             # where LBA 0 starts in the file (a .cue INDEX 01 past 0)
var volume := ""
var files := {}                  # "DIR/NAME.EXT" (no ";1") -> {"lba": int, "size": int}
var error := ""                  # why open() failed
var _f: FileAccess
var _chd := {}                   # a .chd: the helper's pipes (OS.execute_with_pipe: stdio, stderr, pid)
var _chd_frames := 0             # its track 1 sectors
var _chd_restarted := false      # the helper was started again after it died
var _walked := {}                # directory LBAs already walked


## Opens a .cue, .bin, .iso/.img, .chd or .m3u, walks its file system; null with no ISO9660 volume.
## Check error on a null result through open_checked() if the reason matters.
static func open(image: String) -> Dw1Disc:
	var d := open_checked(image)
	return d if d.error.is_empty() else null


## As open(), but always returns the reader; error says what went wrong ("" = fine).
static func open_checked(image: String) -> Dw1Disc:
	var d := Dw1Disc.new()
	d._open(image, 0)
	return d


func _open(image: String, depth: int) -> void:
	var ext := image.get_extension().to_lower()
	if ext == "m3u":
		if depth > 2:
			error = "m3u nests too deep"
			return
		var first := _m3u_first(image)
		if first.is_empty():
			error = "empty m3u"
			return
		_open(first, depth + 1)
		return
	if ext in OTHER_EXTS:
		error = ext
		return
	if ext == "chd":
		if not _open_chd(image):
			return
	elif ext == "cue":
		if not _parse_cue(image):
			return
	else:
		path = image
		if not _guess_layout(ext):
			return
	if _chd.is_empty():
		_f = FileAccess.open(path, FileAccess.READ)
		if _f == null:
			error = "cannot open %s" % path
			return
	var pvd := read_sectors(16, 1)
	if not _is_pvd(pvd) and ext != "cue" and ext != "chd":   # a bare dump that kept the 150-sector pregap
		byte_offset = 150 * sector_size
		pvd = read_sectors(16, 1)
	if not _is_pvd(pvd):
		error = "no ISO9660 volume"
		return
	volume = pvd.slice(40, 72).get_string_from_ascii().strip_edges()
	var root_lba := pvd.decode_u32(156 + 2)
	var root_size := pvd.decode_u32(156 + 10)
	_walk(root_lba, root_size, "", 0)


## A .chd through the helper: its first reply names track 1's sectors ("frames=N type=T ...",
## pet/pet_chd.cs), which then come back as a .bin of that track would store them.
func _open_chd(image: String) -> bool:
	path = image
	var exe := WinHelper.exe()
	if exe.is_empty():
		error = "chd: " + WinHelper.error
		return false
	_chd = OS.execute_with_pipe(exe, ["chd", ProjectSettings.globalize_path(image), str(OS.get_process_id())])
	if _chd.is_empty():
		error = "chd: the helper didn't start"
		return false
	var r := _chd_reply()
	if r.is_empty() or r[0] != 0:
		error = "chd: the helper stopped" if r.is_empty() else (r[1] as PackedByteArray).get_string_from_utf8()
		_chd_close()
		return false
	var info := {}
	for kv in (r[1] as PackedByteArray).get_string_from_ascii().split(" "):
		info[kv.get_slice("=", 0)] = kv.get_slice("=", 1)
	_chd_frames = int(info.get("frames", "0"))
	match str(info.get("type", "")):
		"MODE2_RAW":
			pass                                 # the defaults: 2352, 24, 18
		"MODE1_RAW":
			data_offset = 16
			submode = -1
		"MODE1", "MODE2_FORM1":
			sector_size = USER
			data_offset = 0
			submode = -1
		"MODE2", "MODE2_FORM_MIX":
			sector_size = 2336
			data_offset = 8
			submode = 2
		_:
			error = "chd: track 1 is %s" % info.get("type", "?")
			_chd_close()
			return false
	return true


## One reply from the helper: [status (0 = ok), bytes], or [] when its pipe is gone.
func _chd_reply() -> Array:
	var head := _chd_bytes(8)
	if head.size() < 8:
		return []
	var n := head.decode_u32(4)
	var body := _chd_bytes(n)
	return [head.decode_u32(0), body] if body.size() == n else []


## n bytes from the helper's stdout (a pipe read returns what has arrived so far).
func _chd_bytes(n: int) -> PackedByteArray:
	var io: FileAccess = _chd["stdio"]
	var out := PackedByteArray()
	while out.size() < n:
		var b := io.get_buffer(n - out.size())
		if b.is_empty():
			break
		out.append_array(b)
	return out


func _chd_close() -> void:
	if _chd.is_empty():
		return
	(_chd["stdio"] as FileAccess).close()       # the helper exits when its stdin closes
	(_chd["stderr"] as FileAccess).close()
	_chd = {}


func _notification(what: int) -> void:
	# inline: a RefCounted's own methods can't be called while it's being freed
	if what == NOTIFICATION_PREDELETE and not _chd.is_empty():
		(_chd["stdio"] as FileAccess).close()
		(_chd["stderr"] as FileAccess).close()


## A .chd only: the helper decodes every hunk (about 12 s for DW1) and compares the image's
## SHA-1 with the one chdman stored. "" when it matches, else what went wrong.
func chd_check() -> String:
	if _chd.is_empty():
		return "not a chd"
	(_chd["stdio"] as FileAccess).store_string("sha1\n")
	var r := _chd_reply()
	if r.is_empty():
		return "the helper stopped"
	var s := (r[1] as PackedByteArray).get_string_from_utf8()
	if r[0] != 0:
		return s
	return "" if s.get_slice(" ", 0) == s.get_slice(" ", 1) else "the image's SHA-1 doesn't match"


## The first image an .m3u lists, as an absolute path (relative entries are next to it).
static func _m3u_first(m3u: String) -> String:
	for line in FileAccess.get_file_as_string(m3u).split("\n"):
		var l := line.strip_edges()
		if l.is_empty() or l.begins_with("#"):
			continue
		return l if l.is_absolute_path() else m3u.get_base_dir().path_join(l)
	return ""


## Track 1 of a .cue: its FILE, mode and INDEX 01 (DW1 is one MODE2/2352 data track).
func _parse_cue(cue: String) -> bool:
	var file := ""
	var mode := ""
	var index := -1
	for line in FileAccess.get_file_as_string(cue).split("\n"):
		var l := line.strip_edges()
		var up := l.to_upper()
		if up.begins_with("FILE ") and file.is_empty():
			var q1 := l.find("\"")
			var q2 := l.rfind("\"")
			file = l.substr(q1 + 1, q2 - q1 - 1) if q1 >= 0 and q2 > q1 else l.split(" ")[1]
		elif up.begins_with("TRACK ") and mode.is_empty():
			mode = up.split(" ", false)[-1]
		elif up.begins_with("INDEX 01") and index < 0:
			var t := up.split(" ", false)[-1].split(":")
			if t.size() == 3:
				index = (int(t[0]) * 60 + int(t[1])) * 75 + int(t[2])
		if not mode.is_empty() and index >= 0:
			break
	if file.is_empty():
		error = "cue lists no FILE"
		return false
	path = file if file.is_absolute_path() else cue.get_base_dir().path_join(file)
	match mode:
		"MODE2/2352":
			sector_size = RAW
			data_offset = 24
		"MODE1/2352":
			sector_size = RAW
			data_offset = 16
			submode = -1
		"MODE2/2336":
			sector_size = 2336
			data_offset = 8
			submode = 2
		"MODE1/2048", "MODE2/2048":
			sector_size = USER
			data_offset = 0
			submode = -1
		_:
			error = "unsupported track mode %s" % mode
			return false
	byte_offset = maxi(index, 0) * sector_size
	return true


## A bare .bin/.iso: 2352 when it starts with the CD sync pattern, else 2048 (an ISO).
func _guess_layout(ext: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		error = "cannot open %s" % path
		return false
	var head := f.get_buffer(16)
	var sync := _is_sync(head)
	if not sync and f.get_length() > 150 * RAW:         # a dump that kept the pregap
		f.seek(150 * RAW)
		head = f.get_buffer(16)
		sync = _is_sync(head)
	if sync:
		sector_size = RAW
		data_offset = 24 if head[15] == 2 else 16
		submode = 18 if head[15] == 2 else -1
	elif ext == "bin" and f.get_length() % RAW == 0 and f.get_length() % USER != 0:
		error = "no sync pattern in a 2352-byte image"
		return false
	else:
		sector_size = USER
		data_offset = 0
		submode = -1
	return true


static func _is_sync(head: PackedByteArray) -> bool:
	var sync := head.size() == 16 and head[0] == 0 and head[11] == 0
	for i in range(1, 11):
		sync = sync and head[i] == 0xFF
	return sync


static func _is_pvd(pvd: PackedByteArray) -> bool:
	return pvd.size() >= USER and pvd[0] == 1 and pvd.slice(1, 6).get_string_from_ascii() == "CD001"


func sector_count() -> int:
	if not _chd.is_empty():
		return _chd_frames
	return (_f.get_length() - byte_offset) / sector_size if _f else 0


## The raw bytes of count sectors from lba (2352 or 2048 each, as the image stores them).
func read_raw(lba: int, count: int) -> PackedByteArray:
	if not _chd.is_empty():
		(_chd["stdio"] as FileAccess).store_string("r %d %d\n" % [lba, count])
		var r := _chd_reply()
		if r.is_empty() and not _chd_restarted:        # the helper died: start it again, once (CHD-4)
			_chd_restarted = true
			_chd_close()
			if _open_chd(path):
				return read_raw(lba, count)
		if r.size() == 2 and r[0] == 0:
			return r[1]
		if r.is_empty():
			_chd_close()
			if error.is_empty():
				error = "chd: the helper stopped"
		push_warning("disc: " + (error if r.is_empty() else (r[1] as PackedByteArray).get_string_from_utf8()))
		return PackedByteArray()
	if _f == null:
		return PackedByteArray()
	_f.seek(byte_offset + lba * sector_size)
	return _f.get_buffer(count * sector_size)


## The 2048 user bytes of each sector (Form 1 data).
func read_sectors(lba: int, count: int) -> PackedByteArray:
	var raw := read_raw(lba, count)
	if sector_size == USER:
		return raw
	var out := PackedByteArray()
	var n := raw.size() / sector_size
	for i in n:
		var s := i * sector_size + data_offset
		out.append_array(raw.slice(s, s + USER))
	return out


func _walk(lba: int, size: int, prefix: String, depth: int) -> void:
	if depth > 16 or _walked.has(lba):         # a broken image can't loop the walk
		return
	_walked[lba] = true
	var buf := read_sectors(lba, (size + USER - 1) / USER)
	var pos := 0
	while pos < buf.size():
		var rec_len := buf[pos]
		if rec_len == 0:                      # padding to the next sector
			pos = (pos / USER + 1) * USER
			continue
		if pos + 33 > buf.size():
			break
		var ext_lba := buf.decode_u32(pos + 2)
		var ext_size := buf.decode_u32(pos + 10)
		var is_dir := buf[pos + 25] & 2 != 0
		var name_len := buf[pos + 32]
		var raw_name := buf.slice(pos + 33, pos + 33 + name_len)
		pos += rec_len
		if name_len == 1 and raw_name[0] <= 1:   # "." and ".."
			continue
		var name := raw_name.get_string_from_ascii().get_slice(";", 0)
		var p := prefix.path_join(name) if not prefix.is_empty() else name
		if is_dir:
			_walk(ext_lba, ext_size, p, depth + 1)
		else:
			files[p] = {"lba": ext_lba, "size": ext_size}


## Whether path ("CHDAT/MMD0/AGUMON.MMD", case-insensitive) is on the disc.
func has(p: String) -> bool:
	return files.has(p.to_upper().replace("\\", "/"))


## A file's bytes, as extract_disc.py writes it: its Form 1 data, or (XA audio, STR video:
## any Form 2 sector) the raw 2352-byte sectors. Empty if it isn't there.
func read(p: String) -> PackedByteArray:
	var key := p.to_upper().replace("\\", "/")
	if not files.has(key) or (_f == null and _chd.is_empty()):
		return PackedByteArray()
	var e: Dictionary = files[key]
	var size: int = e["size"]
	var nsec := maxi(1, (size + USER - 1) / USER)
	var raw := read_raw(int(e["lba"]), nsec)
	if sector_size == USER:
		return raw.slice(0, size)
	var out := PackedByteArray()
	for i in raw.size() / sector_size:
		var s := i * sector_size
		if submode >= 0 and raw[s + submode] & FORM2_BIT:
			return raw
		out.append_array(raw.slice(s + data_offset, s + data_offset + USER))
	return out.slice(0, size)


## `size` bytes of a Form 1 file from byte `offset`, reading only the sectors they lie in
## (ALLTIM.TIM is 3.3 MB; a model needs 18 KB of it). Empty if the file isn't there.
func read_part(p: String, offset: int, size: int) -> PackedByteArray:
	var key := p.to_upper().replace("\\", "/")
	if not files.has(key) or (_f == null and _chd.is_empty()) or offset < 0:
		return PackedByteArray()
	var e: Dictionary = files[key]
	size = mini(size, int(e["size"]) - offset)
	if size <= 0:
		return PackedByteArray()
	var first := offset / USER
	var count := (offset % USER + size + USER - 1) / USER
	var data := read_sectors(int(e["lba"]) + first, count)
	return data.slice(offset % USER, offset % USER + size)


## The boot EXE's name from SYSTEM.CNF ("SLUS_010.32"), "" without one.
func serial() -> String:
	for line in read("SYSTEM.CNF").get_string_from_ascii().split("\n"):
		var l := line.strip_edges()
		if l.to_upper().begins_with("BOOT"):
			var exe := l.get_slice("\\", l.get_slice_count("\\") - 1)
			if exe == l:
				exe = l.get_slice(":", l.get_slice_count(":") - 1)
			return exe.get_slice(";", 0).strip_edges().to_upper()
	return ""


func is_dw1_usa() -> bool:
	return serial() == DW1_SERIAL and has(DW1_SERIAL)


## SHA-256 of the boot EXE in hex: the cache key (user://cache/), so a rebuilt mod disc
## invalidates what was decoded from the old one.
func exe_hash() -> String:
	if serial().is_empty():
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(read(serial()))
	return ctx.finish().hex_encode()


# ---------------------------------------------------------------- finding the image
## DuckStation's settings.ini: the portable one beside its exe isn't known to us, so the
## user-folder ones (current, then the old Documents location).
static func duckstation_settings() -> Array[String]:
	var out: Array[String] = []
	var local := OS.get_environment("LOCALAPPDATA")
	if not local.is_empty():
		out.append(local.path_join("DuckStation/settings.ini"))
	out.append(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("DuckStation/settings.ini"))
	var have: Array[String] = []
	have.assign(out.filter(func(p: String) -> bool: return FileAccess.file_exists(p)))
	return have


## The folders of DuckStation's game list: [GameList] RecursivePaths (walked) and Paths (not).
static func game_list_dirs(settings_ini: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var section := ""
	for line in FileAccess.get_file_as_string(settings_ini).split("\n"):
		var l := line.strip_edges()
		if l.begins_with("["):
			section = l
			continue
		if section != "[GameList]" or not l.contains("="):
			continue
		var key := l.get_slice("=", 0).strip_edges()
		var val := l.substr(l.find("=") + 1).strip_edges().replace("\\", "/")
		if key in ["RecursivePaths", "Paths"] and not val.is_empty():
			out.append({"dir": val, "recursive": key == "RecursivePaths"})
	return out


## Every disc image in DuckStation's game list folders (IMAGE_EXTS and OTHER_EXTS),
## names with "digimon world" first. A .bin a .cue beside it names is left out.
static func find_images(settings_ini := "") -> Array[String]:
	var inis := duckstation_settings()
	if not settings_ini.is_empty():
		inis = [settings_ini]
	var found: Array[String] = []
	var budget := [SCAN_MAX]
	for ini in inis:
		for g in game_list_dirs(ini):
			_scan(g["dir"], 0 if g["recursive"] else SCAN_DEPTH, found, budget)
	var named := {}
	for p in found:
		if p.get_extension().to_lower() == "cue":
			var d := Dw1Disc.new()
			if d._parse_cue(p):
				named[d.path.simplify_path().to_lower()] = true
	var out: Array[String] = []
	for p in found:
		if not named.has(p.simplify_path().to_lower()) and not out.has(p):
			out.append(p)
	out.sort_custom(func(a: String, b: String) -> bool:
		var ra := 0 if a.get_file().to_lower().begins_with("digimon world (") else 1
		var rb := 0 if b.get_file().to_lower().begins_with("digimon world (") else 1
		return ra < rb if ra != rb else a < b)
	return out


static func _scan(dir: String, depth: int, found: Array[String], budget: Array) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	for f in da.get_files():
		budget[0] -= 1
		if budget[0] < 0:
			return
		var e := f.get_extension().to_lower()
		if e in IMAGE_EXTS or e in OTHER_EXTS:
			found.append(dir.path_join(f))
	if depth >= SCAN_DEPTH:
		return
	for sub in da.get_directories():
		if budget[0] < 0:
			return
		_scan(dir.path_join(sub), depth + 1, found, budget)


## The first DW1 (USA) image in DuckStation's game list that this reader opens, or "".
## OTHER_EXTS come back through find_images() for the "not read" message.
static func find_dw1(settings_ini := "") -> String:
	for p in find_images(settings_ini):
		var ext := p.get_extension().to_lower()
		if ext == "m3u":
			ext = _m3u_first(p).get_extension().to_lower()
		if ext in OTHER_EXTS:
			continue
		var d := Dw1Disc.open(p)
		if d and d.is_dw1_usa():
			return p
	return ""
