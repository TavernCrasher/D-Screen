class_name Dw1SoundBanks
extends RefCounted
## D-Screen's sounds (docs/shareable_pet_plan.md step 6, docs/pet_sounds.md section 5): the pet's
## banks read from the player's own disc and rendered by Dw1Vab on first use, cached as WAVs in
## user://cache/sounds/<md5 of the bank's VAB bytes>/ (a modded bank gets its own folder, so a
## stale entry is never played). DwSound uses it when Dw1Model has a disc; the personal build
## keeps game_data/sounds.
##
## Banks: "ss" (SS.VHB, bank 0), "sl" (SL.VHB, bank 1), "es14" (ESALL.VHB section 14, the gyms),
## "vl<g>" (VLALL.VHB group g, 15 sectors), "vb<s>" (VBALL.VHB section s, 7 sectors); the type
## tables DIGIMON_VLALL_SOUND_ID / DIGIMON_VBALL_SOUND_ID from the EXE (loadPartnerSounds).
## Not here: SB.VHB, the evolution bank, the reverb (Dw1Vab).
##
## The disc is read on the main thread only (Dw1Disc isn't thread-safe); warm() parses the banks
## first, then renders the uncached ids on a thread.

static var cache_root := "user://cache/sounds/"   # tests point it elsewhere
## Bumped when Dw1Vab renders differently: players' caches from an older renderer are left behind (DS6-1).
const RENDER_VERSION := 1
const VHB := "SOUND/VHB/"
const ES14 := [0x09ae * 1024, 0x9e * 1024]     # ESALL.VHB section 14 (dw1_sounds.load_banks)
const VL_BYTES := 15 * 2048
const VB_BYTES := 7 * 2048
const VL_GROUPS := 16
const VB_SECTIONS := 71
const VLALL_TABLE := 0x80127EFC                # 66 bytes: a voice group per type 1-65
const VBALL_TABLE := 0x80127F40                # 180 bytes: a cry section per type
const RELEASE_CAP := 0.05                      # s: DwSound's stop needs at most its 6-tick fade

var disc: Dw1Disc
var exe: Dw1Exe
var _vab := {}                                 # bank -> Dw1Vab.vab() ({} = no such bank)
var _md5 := {}
var _ids := {}                                 # bank -> {id: reverb}
var _mutex := Mutex.new()
var _thread: Thread
var _quit := false
var warm_ms := 0                               # the last warm-up's time, for the log and tests


func _init(d: Dw1Disc, x: Dw1Exe) -> void:
	disc = d
	exe = x


static func keyed(bank: String) -> bool:
	return bank.begins_with("vl") or bank.begins_with("vb")


## The bank's VHB bytes from the disc (main thread), empty for an unknown name.
func bank_bytes(bank: String) -> PackedByteArray:
	if bank == "ss" or bank == "sl":
		return disc.read(VHB + bank.to_upper() + ".VHB")
	if bank == "es14":
		return disc.read_part(VHB + "ESALL.VHB", ES14[0], ES14[1])
	var k := bank.substr(2)
	if not k.is_valid_int():
		return PackedByteArray()
	var i := k.to_int()
	if bank.begins_with("vl") and i >= 0 and i < VL_GROUPS:
		return disc.read_part(VHB + "VLALL.VHB", i * VL_BYTES, VL_BYTES)
	if bank.begins_with("vb") and i >= 0 and i < VB_SECTIONS:
		return disc.read_part(VHB + "VBALL.VHB", i * VB_BYTES, VB_BYTES)
	return PackedByteArray()


## The parsed bank, read and parsed once (main thread).
func vab(bank: String) -> Dictionary:
	_mutex.lock()
	var have := _vab.has(bank)
	var v: Dictionary = _vab.get(bank, {})
	_mutex.unlock()
	if have:
		return v
	var raw := bank_bytes(bank)
	v = Dw1Vab.vab(raw)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(raw)
	_mutex.lock()
	_vab[bank] = v
	_md5[bank] = ctx.finish().hex_encode()
	_ids[bank] = Dw1Vab.ids(v, keyed(bank)) if not v.is_empty() else {}
	_mutex.unlock()
	return v


## {id (int): reverb} of the ids playSound can key in the bank.
func ids(bank: String) -> Dictionary:
	vab(bank)
	_mutex.lock()
	var out: Dictionary = _ids.get(bank, {})
	_mutex.unlock()
	return out


## sounds.json's "vlall" / "vball" from the disc's EXE.
func tables() -> Dictionary:
	var vl := []
	var vb := []
	for b in exe.bytes(VLALL_TABLE, 66):
		vl.append(b)
	for b in exe.bytes(VBALL_TABLE, 180):
		vb.append(b)
	return {"vlall": vl, "vball": vb}


func _dir(bank: String) -> String:
	_mutex.lock()
	var h: String = _md5.get(bank, "")
	_mutex.unlock()
	return cache_root + "v%d/" % RENDER_VERSION + h + "/"


## The cached entry of a rendered id ({} if not rendered yet): Dw1Vab.render's fields, no pcm.
func cached(bank: String, id: int) -> Dictionary:
	var meta := _dir(bank) + "%d.json" % id
	if not FileAccess.file_exists(meta) or not FileAccess.file_exists(_dir(bank) + "%d.wav" % id):
		return {}
	var e = JSON.parse_string(FileAccess.get_file_as_string(meta))
	return e if e is Dictionary else {}


## Renders an id and writes it to the cache (any thread, once the bank is parsed): the entry with
## its pcm, {} if the bank has no tone there.
func render(bank: String, id: int) -> Dictionary:
	_mutex.lock()
	var v: Dictionary = _vab.get(bank, {})
	_mutex.unlock()
	if v.is_empty():
		return {}
	var e := Dw1Vab.render(v, id, keyed(bank), RELEASE_CAP)
	if e.is_empty():
		return e
	var dir := _dir(bank)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var tag := "%d_%d" % [OS.get_thread_caller_id(), Time.get_ticks_usec()]
	var tmp := dir + "%d.%s.part.wav" % [id, tag]
	if _stream(e).save_to_wav(tmp) == OK:
		var wav := dir + "%d.wav" % id
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(wav)) != OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		var meta := e.duplicate()
		meta.erase("pcm")
		var f := FileAccess.open(dir + "%d.%s.json.part" % [id, tag], FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(meta))
			f.close()
			DirAccess.rename_absolute(ProjectSettings.globalize_path(dir + "%d.%s.json.part" % [id, tag]),
				ProjectSettings.globalize_path(dir + "%d.json" % id))
	return e


static func _stream(e: Dictionary) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.stereo = true
	w.mix_rate = Dw1Vab.RATE
	w.data = e["pcm"]
	return w


## The id's stream: from the cache, else rendered now. Loops as DwSound.stream (a held VAG loops
## whole source loops once it holds). null if the bank has no tone there.
func stream(bank: String, id: int) -> AudioStreamWAV:
	vab(bank)
	var e := cached(bank, id)
	var w: AudioStreamWAV = null
	if not e.is_empty():
		w = AudioStreamWAV.load_from_file(_dir(bank) + "%d.wav" % id)
	if w == null:
		e = render(bank, id)
		if e.is_empty():
			return null
		w = _stream(e)
	if e.has("loop_end"):
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = int(e["loop_begin"])
		w.loop_end = int(e["loop_end"])
	return w


## The id's release time (at most RELEASE_CAP), from its tones' ADSR: no render needed.
func release(bank: String, id: int) -> float:
	var v := vab(bank)
	if v.is_empty():
		return 0.0
	var prog := 0 if keyed(bank) else id / 16
	var note := id if keyed(bank) else 60 + id % 16
	var r := 0.0
	for t in v["tones"].get(prog, []):
		if int(t["max"]) == note:
			r = maxf(r, Dw1Vab.release_seconds(int(t["adsr2"]), RELEASE_CAP))
	return r


## Renders the uncached ones of `what` on a thread: each item a bank name (all its ids) or
## [bank, [ids]]. The banks are parsed here first (the disc stays on the main thread).
func warm(what: Array) -> void:
	stop_warm()
	var todo := []
	for w in what:
		var bank: String = w if w is String else w[0]
		if bank == "":
			continue
		var all := ids(bank)
		for id in (all.keys() if w is String else w[1]):
			if all.has(int(id)) and cached(bank, int(id)).is_empty():
				todo.append([bank, int(id)])
	if todo.is_empty():
		warm_ms = 0
		return
	_quit = false
	_thread = Thread.new()
	_thread.start(_warm.bind(todo))


func _warm(todo: Array) -> void:
	var t0 := Time.get_ticks_msec()
	for item in todo:
		if _quit:
			return
		if cached(item[0], item[1]).is_empty():
			render(item[0], item[1])
	warm_ms = Time.get_ticks_msec() - t0


## Whether a warm-up still runs (a finished one is joined here).
func warming() -> bool:
	if _thread != null and not _thread.is_alive():
		_thread.wait_to_finish()
		_thread = null
	return _thread != null


## Stops a running warm-up after its current sound and joins it (call before quitting).
func stop_warm() -> void:
	if _thread == null:
		return
	_quit = true
	_thread.wait_to_finish()
	_thread = null
