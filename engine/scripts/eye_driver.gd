class_name EyeDriver
extends Node
## Plays DW1's per-frame eye tiles (rules/eye_track.gd) on a model's eyes, on its own 20 Hz tick
## counter from the clip's start (TS stand-in clips have other lengths, and DW1_SPEED doesn't
## scale DW1's ticks). DigimonModel.instance adds one when the DW1 model has an eye channel and
## the model can show it:
## - Time Stranger eyes (ts_eye.gdshader): open, closed, happy and the battle stare (TS's angry
##   row) are atlas rows; half-lidded lays the closed lid over the top of the open eye;
## - custom models with painted eye states (<chr>.eye_states.json: an atlas of the states over
##   the eye's texture rect, custom_eye.gdshaderinc).
## Custom models also play their other channels' tiles when the atlas has them (Tinmon's brow
## flash in its song and its treads rolling in the walk): each such channel has a slot in the
## shader and its tiles' rows.
## Map NPCs and battle enemies of one type share one texture (EYE-9): DW1 loads an NPC type's model
## and texture into one slot for all of them (FUN_800a1f68 mode 0, main.c:7405-7466, reached from
## script op 0x46 load_model, main.c:16543), so the last paste of any of them shows on all, a
## blink included. The tamer (mode 2) and the partner (mode 3, FUN_800a442c) have their own, so a
## partner of the same type never shares. DigimonModel.share_eyes puts a driver in its type's
## group; only visible members paste (a fighter's field node is hidden for the fight, so it
## doesn't paste twice; EYE-14: whether DW1's hidden NPCs keep pasting during a battle is open).
## The slot outlives its NPCs (removing one frees the entity, FUN_800b63c4, main.c:16588-16598):
## it is freed by op 0x79 unload_model (FUN_80106c08) or on map exit (FUN_800b6570), and the
## next load uploads the disc texture again (EYE-12, EYE-13).

const TS_ROW := {"open": 0, "closed": 1, "happy": 2, "battle": 3}

var data: Dictionary = {}
var channel := -1
var clip: Dictionary = {}
var clip_id := -1
var tick := 0.0
var rate := 1.0                         # ticks per game frame (2: DW1's animFlag bit 4, the flee run)
var paused := false
var carry := ""
var tile := ""
var shown := ""                         # the label on screen
var ts_mats: Array[ShaderMaterial] = []
var custom_mats: Array[ShaderMaterial] = []
var custom_states: Array = []           # custom atlas cell order, e.g. ["open", "battle", ...]
var others: Array = []                  # [{"channel", "slot", "tiles": [row order], "tile"}]
var cells := Vector4i.ZERO              # the atlas row each shader slot shows (0: the eyes)
var share_key := -1                     # the NPC type whose texture this shares (-1: its own)
var last_t := -1                        # the last tick checked for pastes

static var _shared: Dictionary = {}     # NPC type -> {"tiles": {channel: tile}, "members": [EyeDriver]}


func setup(m: Dictionary) -> void:
	data = m
	channel = EyeTrack.eye_channel(m)
	tile = EyeTrack.disc(m, channel) if channel >= 0 else ""
	carry = tile
	for o in others:
		o["tile"] = EyeTrack.disc(m, int(o["channel"]))
		o["carry"] = o["tile"]
	if channel >= 0:
		_apply()
	_apply_others()


## startAnimation: clip `id` from tick 0. An id the model's data lacks changes nothing.
## held: startAnimation with animFlag bit 0 cleared (the finisher's charge, the stun): nothing is
## pasted until it resumes, so the previous clip's tile stays.
func start(id: int, held := false, ticks_per_frame := 1.0) -> void:
	var c = data.get("clips", {}).get(str(id))
	if c == null:
		return
	carry = tile
	for o in others:
		o["carry"] = o["tile"]
	last_t = -1
	clip = c
	clip_id = id
	tick = 0.0
	rate = ticks_per_frame
	paused = held
	if not held:
		_update()


## The DIGIMON / PLAYER status page (FUN_800beebc, main.c:19795-19796 / 19827-19828): every frame
## it draws, it starts clip 0 and ticks it, then starts the entity's own clip and ticks it.
func status_restart() -> void:
	var id := clip_id
	start(0)
	tick = 1.0
	_update()
	if id >= 0 and id != 0:
		start(id)
		tick = 1.0
		_update()


func _process(delta: float) -> void:
	if paused or clip.is_empty():
		return
	tick += delta * 20.0 * rate
	_update()


func _update() -> void:
	if share_key >= 0:
		_update_shared()
		return
	if channel >= 0:
		var t := EyeTrack.state(clip, channel, int(tick), carry)
		if t != tile:
			tile = t
			_apply()
	var changed := false
	for o in others:
		var ot := EyeTrack.state(clip, int(o["channel"]), int(tick), String(o["carry"]))
		if ot != o["tile"]:
			o["tile"] = ot
			changed = true
	if changed:
		_apply_others()


## A shared texture: this clip's pastes since the last check go to every member of the type.
func _update_shared() -> void:
	var t1 := int(tick)
	var t0 := last_t
	last_t = t1
	if not _visible() or not _shared.has(share_key):
		return
	var s: Dictionary = _shared[share_key]
	var tiles: Dictionary = s["tiles"]
	var changed := false
	if channel >= 0 and EyeTrack.pasted(clip, channel, t0, t1):
		tiles[channel] = EyeTrack.state(clip, channel, t1, carry)
		changed = true
	for o in others:
		var ch := int(o["channel"])
		if EyeTrack.pasted(clip, ch, t0, t1):
			tiles[ch] = EyeTrack.state(clip, ch, t1, String(o["carry"]))
			changed = true
	if changed:
		for m in s["members"]:
			(m as EyeDriver)._show_shared(tiles)


## Joins NPC type `key`'s texture: the first member brings the disc tiles, later ones show what
## the texture holds now.
func share(key: int) -> void:
	share_key = key
	if not _shared.has(key):
		var tiles := {}
		if channel >= 0:
			tiles[channel] = tile
		for o in others:
			tiles[int(o["channel"])] = o["tile"]
		_shared[key] = {"tiles": tiles, "members": []}
	var s: Dictionary = _shared[key]
	if not s["members"].has(self):
		s["members"].append(self)
	_show_shared(s["tiles"])


## Leaves the shared texture; the slot keeps its tiles until free_slots (a respawn of the type
## on this map shows the last paste).
func unshare() -> void:
	if share_key < 0 or not _shared.has(share_key):
		return
	var s: Dictionary = _shared[share_key]
	s["members"].erase(self)


## Frees the NPC type slots: all of them on map exit (FUN_800b6570, main.c:16680-16684), or one
## type for op 0x79 unload_model (FUN_80106c08, main.c:54181-54198) once none of it is on the map.
static func free_slots(type := -1) -> void:
	if type < 0:
		_shared.clear()
	elif _shared.has(type) and (_shared[type]["members"] as Array).is_empty():
		_shared.erase(type)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		unshare()


func _show_shared(tiles: Dictionary) -> void:
	if channel >= 0 and tiles.has(channel) and tiles[channel] != tile:
		tile = tiles[channel]
		_apply()
	var changed := false
	for o in others:
		var ch := int(o["channel"])
		if tiles.has(ch) and tiles[ch] != o["tile"]:
			o["tile"] = tiles[ch]
			changed = true
	if changed:
		_apply_others()


func _visible() -> bool:
	var n: Node = get_parent()
	while n:
		if n is Node3D and not (n as Node3D).visible:
			return false
		n = n.get_parent()
	return true


## The other channels' rows (a tile the atlas lacks shows the model texture).
func _apply_others() -> void:
	if others.is_empty():
		return
	for o in others:
		var tiles: Array = o["tiles"]
		cells[clampi(int(o["slot"]), 1, 3)] = maxi(tiles.find(o["tile"]), 0)
	for m in custom_mats:
		m.set_shader_parameter("eye_cells", cells)


func _apply() -> void:
	var l := EyeTrack.label(data, channel, tile)
	if l != shown:
		show_label(l)


## Shows an eye state by its label (also for review renders: engine/tools/eye_sheet.gd).
func show_label(l: String) -> void:
	shown = l
	var half := l == "half"
	var row: int = TS_ROW.get(l, 0)
	for m in ts_mats:
		m.set_shader_parameter("expression_offset", Vector2(0.0, 0.25 * row))
		m.set_shader_parameter("half_lid", 1.0 if half else 0.0)
	if not custom_mats.is_empty():
		var cell := custom_states.find(l)
		if cell < 0:
			cell = maxi(custom_states.find("closed" if l == "happy" else "open"), 0)
		cells.x = cell
		# a custom atlas that carries the eye channel as one of its tile channels (Giromon: DW1's own eye
		# drawings per tile): that slot shows the label's tile (review renders call this directly)
		for o in others:
			if int(o["channel"]) != channel:
				continue
			var tiles: Array = o["tiles"]
			var k := -1
			for want in [l, "closed" if l == "happy" else "open"]:
				for i in tiles.size():
					if EyeTrack.label(data, channel, String(tiles[i])) == want:
						k = i
						break
				if k >= 0:
					break
			cells[clampi(int(o["slot"]), 1, 3)] = maxi(k, 0)
		for m in custom_mats:
			m.set_shader_parameter("eye_cells", cells)
