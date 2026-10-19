class_name DwSound
extends Node
## DW1's sound effects, played as DW1 plays them (dw_decomp src/main/sound.c:560-660). The WAVs come
## from tools/dw1_sounds.py (game_data/sounds: banks "sb" = SB.VHB, the technique effects, bank 8 in
## battles; "ss" = SS.VHB, bank 0, the system sounds; "evo" = ESALL section 18, the evolution scene),
## one per sound id with its tones already mixed, keyed and enveloped. D-Screen (Dw1Model has the
## player's disc, or use_disc): the pet's banks come from the disc instead, rendered on first use and
## cached (Dw1SoundBanks); index[bank] fills from the VAB headers when a bank is first asked for.
##
## playSound(bank, id) keys each tone on a free SPU voice from 10-23 (getNextFreeChannel: the search
## starts after the last voice taken; with all 14 busy it takes the next in turn, cutting what played
## there). A sound whose VAG repeats never ends by itself (`held`, looping from loop_begin to loop_end):
## DW1 stops the EFE loop ids with stopSoundMask (SsUtAutoVol to 0 over 6 ticks of SS_TICK240 and an
## immediate key off, so the tone's release cuts it: ~12 ms for the loop ids) and every voice with
## stopSound() at battle end (silent at once); here stop() and stop_all(). The reverb (SND-4) is
## baked into the evolution bank's WAVs, so a stop cuts its tail too (SND-11, open: DW1's reverb
## rings on; needs a runtime reverb unit, with the in-game evolution scene).

const VOICES := 14                       # SPU voices 10..23
const STOP_FADE := 6.0 / 240.0           # SsUtAutoVol(v, 127, 0, 6) at SS_TICK240 (sound.c:518), the cap

var index := {}                          # bank -> id (String) -> {file, seconds, held, ...}
var bus := &"Master"
var volume_db := 0.0                     # every voice's level (the mix against music)
var voices: Array[AudioStreamPlayer] = []
var free_index := 0                      # FREE_CHANNEL_INDEX
var _streams := {}
var banks: Dw1SoundBanks                 # D-Screen: the disc's banks (null: game_data/sounds)
static var disc_banks: Dw1SoundBanks


## D-Screen: the sounds come from this disc from now on (Dw1Model.use does the same for models).
static func use_disc(d: Dw1Disc, x: Dw1Exe) -> void:
	disc_banks = Dw1SoundBanks.new(d, x) if d != null and x != null else null


func _init() -> void:
	if disc_banks == null and Dw1Model.on():
		use_disc(Dw1Model.disc, Dw1Model.exe)
	banks = disc_banks
	if banks:
		index = banks.tables()
		_add_voices()
		return
	var f := FileAccess.open("res://game_data/sounds/sounds.json", FileAccess.READ)
	if f:
		index = JSON.parse_string(f.get_as_text())
	else:
		push_warning("DwSound: no game_data/sounds (run tools/dw1_sounds.py, tools/sync_godot_data.py)")
	_add_voices()


func _add_voices() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		voices.append(p)
		add_child(p)


func has(bank: String, id: int) -> bool:
	if banks and not index.has(bank):
		var ids := {}
		for k in banks.ids(bank):
			ids[str(k)] = {"reverb": banks.ids(bank)[k]}
		index[bank] = ids
	return index.has(bank) and index[bank] is Dictionary and (index[bank] as Dictionary).has(str(id))


## D-Screen: renders these on a thread now, so their first play doesn't wait (Dw1SoundBanks.warm:
## bank names, or [bank, [ids]]). Nothing to do with game_data's WAVs.
func warm(what: Array) -> void:
	if banks:
		banks.warm(what)


func _exit_tree() -> void:
	if banks:
		banks.stop_warm()


## The voice getNextFreeChannel hands out: the first idle one from free_index on, else free_index
## itself; the next search starts after it.
func next_voice() -> int:
	var v := free_index
	for i in VOICES:
		var k := (i + free_index) % VOICES
		if not voices[k].playing:
			v = k
			break
	free_index = (v + 1) % VOICES
	return v


## playSound(bank, id): the voice it took, or null (no such id; no tones keyed).
func play(bank: String, id: int, gain_db := 0.0) -> AudioStreamPlayer:
	if not has(bank, id):
		return null
	var s := stream(bank, id)
	if s == null:
		return null
	var p := voices[next_voice()]
	if p.has_meta("tween"):                  # a stop still fading this voice would cut the new sound
		(p.get_meta("tween") as Tween).kill()
		p.remove_meta("tween")
	p.stop()
	p.stream = s
	p.bus = bus
	p.volume_db = volume_db + gain_db
	p.set_meta("sound", [bank, id])
	p.play()
	return p


## stopSoundMask: key the voice off; it dies over its release (at most the AutoVol's 6 ticks). Only
## if it still plays that sound (DW1's mask names voices, which another sound may have taken since).
func stop(p: AudioStreamPlayer, sound: Array = []) -> void:
	if p == null or not p.playing or (not sound.is_empty() and p.get_meta("sound", []) != sound):
		return
	var s: Array = p.get_meta("sound", [])
	var fade := STOP_FADE
	if s.size() == 2 and has(s[0], s[1]):
		fade = minf(banks.release(s[0], s[1]) if banks else float(index[s[0]][str(s[1])]["release"]), STOP_FADE)
	var tw := p.create_tween()
	tw.tween_property(p, "volume_db", -60.0, fade)
	tw.tween_callback(p.stop)
	p.set_meta("tween", tw)


## stopSound() (battle end, victory, the evolution scene): every voice silent at once (SsUtAllKeyOff
## FUN_800ce4b4 sets volume 0 and a zero release on all voices before the key-off, SND-10).
func stop_all() -> void:
	for p in voices:
		if p.has_meta("tween"):
			(p.get_meta("tween") as Tween).kill()
			p.remove_meta("tween")
		p.stop()


func stream(bank: String, id: int) -> AudioStreamWAV:
	var key := "%s/%d" % [bank, id]
	if not _streams.has(key) and banks:
		_streams[key] = banks.stream(bank, id)
	if not _streams.has(key):
		var e: Dictionary = index[bank][str(id)]
		var path := "res://game_data/sounds/" + String(e["file"])
		var w: AudioStreamWAV = null
		if FileAccess.file_exists(path):         # the exact WAV
			w = AudioStreamWAV.load_from_file(path)
		elif ResourceLoader.exists(path):        # an export carries only the imported stream (the pet app)
			w = (load(path) as AudioStreamWAV).duplicate()
		if w and e.has("loop_end"):              # a repeating VAG: whole source loops, once it holds
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = int(e["loop_begin"])
			w.loop_end = int(e["loop_end"])
		_streams[key] = w
	return _streams[key]


func seconds(bank: String, id: int) -> float:
	if banks:
		var s := stream(bank, id) if has(bank, id) else null
		return s.get_length() if s else 0.0
	return float(index[bank][str(id)]["seconds"]) if has(bank, id) else 0.0
