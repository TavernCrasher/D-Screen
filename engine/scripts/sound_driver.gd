class_name SoundDriver
extends Node
## Plays the sound cues in DW1's clips (op 0x4000, tools/dw1_anim_sounds.py -> anim_sounds.json;
## docs/pet_sounds.md) on the clip's own 20 Hz tick from its start, like EyeDriver: startAnimation
## sets frame 1 and the clip ticks in the same frame, so tick-0 cues sound at once. A cue's bank:
## 1 SL (footsteps, foley), 3 the type's VLALL voice group, 4 his own VBALL cries (the partner's
## vabId), 0 SS; bank 8 (the map's ESALL section) isn't played (only non-partners have such cues).
## Full volume as DW1 (SsUtKeyOnV 0x7f), except `step_db` on bank 1 in the walk and run clips (the
## user: quieter footsteps on the desktop, 2026-10-18). A cue whose bank has no tone at its note
## plays nothing, as in DW1 (DwSound.has).

const STEP_CLIPS := [2, 4, 27]          # walk, run, push: their bank-1 cues are footsteps
const VL_DEFAULT := 15                  # loadPartnerSounds: types outside 1-65 take group 15

static var _all: Dictionary = {}

var sfx: DwSound
var clips: Dictionary = {}              # this type's clips (anim_sounds.json)
var vl := ""
var vb := ""
var enabled := true
var no_steps: Array = []                # clips whose bank-1 cues stay silent (the pet's dangle, clip 23)
var step_db := -9.0
var clip: Dictionary = {}
var clip_id := -1
var tick := 0.0
var rate := 1.0                         # ticks per 20 Hz frame (the pet's leap plays at 1.6)
var _next := 0                          # the first tick not yet played
var external := false                   # the cues come from the model's own tick (Dw1Model.cue)


static func cues() -> Dictionary:
	if _all.is_empty():
		var f := FileAccess.open("res://game_data/anim_sounds.json", FileAccess.READ)
		if f:
			_all = JSON.parse_string(f.get_as_text())
	return _all


## The bank names of type's voice (bank 3) and cries (bank 4): DIGIMON_VLALL_SOUND_ID /
## DIGIMON_VBALL_SOUND_ID (sounds.json "vlall" / "vball").
static func banks(index: Dictionary, type: int) -> Array:
	var vlall: Array = index.get("vlall", [])
	var vball: Array = index.get("vball", [])
	var g := int(vlall[type]) if type >= 1 and type <= 65 and type < vlall.size() else VL_DEFAULT
	var s := int(vball[type]) if type >= 0 and type < vball.size() else -1
	return ["vl%d" % g, "vb%d" % s if s >= 0 else ""]


func setup(sfx_: DwSound, type: int) -> void:
	sfx = sfx_
	clips = {} if Dw1Model.on() else cues().get(str(type), {})   # D-Screen: the model's own tick cues (listen)
	var b := banks(sfx.index, type)
	vl = b[0]
	vb = b[1]


## startAnimation: clip `id` from tick 0 (its tick-0 cues at once).
func start(id: int, rate_ := 1.0) -> void:
	clip = clips.get(str(id), {})
	clip_id = id
	tick = 0.0
	rate = rate_
	_next = 0
	_update()


## The (bank, id) pairs a clip fires at ticks [from, to): an endless clip repeats [start, start +
## period) after its first pass; a one-shot ends at its tick count.
static func due(c: Dictionary, from: int, to: int) -> Array:
	var out := []
	if c.is_empty():
		return out
	var ev: Array = c["events"]
	var lp: Array = c.get("loop", [])
	for t in range(from, to):
		var tt := t
		if lp.is_empty():
			if t >= int(c.get("ticks", 0)):
				break
		elif t >= int(lp[0]) + int(lp[1]):
			tt = int(lp[0]) + (t - int(lp[0])) % int(lp[1])
		for e in ev:
			if int(e[0]) == tt:
				out.append([int(e[1]), int(e[2])])
	return out


## A Dw1Model's tick fires its clip's cues itself: they play through the same rules.
func listen(model: Dw1Model) -> void:
	external = true
	clips = {}
	model.cue.connect(cue)


func _process(delta: float) -> void:
	if clip.is_empty():
		return
	tick += delta * 20.0 * rate
	_update()


func _update() -> void:
	var to := int(tick) + 1
	if to <= _next:
		return
	var fire := due(clip, _next, to)
	_next = to
	if not enabled or sfx == null:
		return
	for f in fire:
		cue(int(f[0]), int(f[1]))


## Plays one cue of the current clip (bank, id), unless off or its bank has no tone there.
func cue(b: int, id: int) -> void:
	if not enabled or sfx == null:
		return
	if b == 1 and clip_id in no_steps:
		return
	var bank := _bank(b)
	if bank != "" and sfx.has(bank, id):
		sfx.play(bank, id, step_db if b == 1 and clip_id in STEP_CLIPS else 0.0)


func _bank(b: int) -> String:
	match b:
		0:
			return "ss"
		1:
			return "sl"
		3:
			return vl
		4:
			return vb
	return ""
