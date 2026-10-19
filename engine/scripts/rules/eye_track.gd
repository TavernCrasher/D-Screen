class_name EyeTrack
extends RefCounted
## DW1's per-frame face tiles (game_data/eye_states.json, tools/dw1_eyes.py). Animation op 0x3000
## (tickAnimation FUN_800c1c64, main.c:21145-21158) pastes a tile of the model's own texture into
## a channel rect (eyes, mouth, other) on the tick its frame is reached. Nothing resets it when a
## clip starts (startAnimation FUN_800c1a04): a clip without a paste keeps the last one, and
## before any paste the disc texture shows. There is no blink routine; blinks, the battle stare,
## sleep and hurt eyes are all in the clips. Ticks are game frames (20 Hz) from the clip's start.

static var _data: Dictionary = {}


## The paste data of a DW1 type ({} when its model has none): its own entry, else its
## regular Digimon's (story NPC types).
static func model(dw1_type: int) -> Dictionary:
	if _data.is_empty():
		var t := FileAccess.get_file_as_string("res://game_data/eye_states.json")
		_data = JSON.parse_string(t) if not t.is_empty() else {"_": {}}
	var m = _data.get(str(dw1_type))
	if m == null and DigimonModel.NPC_BASE.has(dw1_type):
		m = _data.get(str(DigimonModel.NPC_BASE[dw1_type]))
	return m if m is Dictionary else {}


## The first eye channel of a model's data, -1 when it has none (Yanmamon, Monzaemon...).
static func eye_channel(m: Dictionary) -> int:
	var chans: Array = m.get("channels", [])
	for i in chans.size():
		if chans[i]["kind"] == "eye":
			return i
	return -1


## The tile channel `ch` shows at tick `t` of `clip`; `carry` is what it showed before the clip.
## One-shot clips hold their last state; endless ones repeat their cycle [start, start + period):
## a later pass shows the last paste so far in the cycle, else the cycle's last, else the last
## before it.
static func state(clip: Dictionary, ch: int, t: int, carry: String) -> String:
	var ev: Array = clip.get("events", [])
	var cur := carry
	if clip.has("ticks"):
		t = mini(t, int(clip["ticks"]) - 1)
	elif clip.has("loop"):
		var start := int(clip["loop"][0])
		var period := int(clip["loop"][1])
		if period > 0 and t >= start + period:
			var tt := start + (t - start) % period
			var in_cycle := ""
			var last_cycle := ""
			for e in ev:
				if int(e[1]) != ch:
					continue
				var et := int(e[0])
				if et < start:
					cur = e[2]
				else:
					last_cycle = e[2]
					if et <= tt:
						in_cycle = e[2]
			if in_cycle != "":
				return in_cycle
			return last_cycle if last_cycle != "" else cur
	for e in ev:
		if int(e[1]) == ch and int(e[0]) <= t:
			cur = e[2]
	return cur


## Whether `clip` pastes into channel `ch` on a tick in (t0, t1]: one-shot clips stop pasting at
## their end, endless ones paste again each pass of their cycle (NPCs sharing a texture, EYE-9).
static func pasted(clip: Dictionary, ch: int, t0: int, t1: int) -> bool:
	var at := {}
	for e in clip.get("events", []):
		if int(e[1]) == ch:
			at[int(e[0])] = true
	if at.is_empty():
		return false
	var lo := maxi(t0 + 1, 0)
	var hi := t1
	if clip.has("ticks"):
		hi = mini(hi, int(clip["ticks"]) - 1)
	elif clip.has("loop"):
		var start := int(clip["loop"][0])
		var period := int(clip["loop"][1])
		if period > 0 and hi - lo >= period:
			lo = maxi(lo, hi - period + 1)                # one whole cycle covers every paste
		for t in range(lo, hi + 1):
			var tt := t
			if period > 0 and t >= start + period:
				tt = start + (t - start) % period
			if at.has(tt):
				return true
		return false
	for t in range(lo, hi + 1):
		if at.has(t):
			return true
	return false


## The meaning of a tile on a channel (open, battle, half, closed, happy, other; rest, mouth).
static func label(m: Dictionary, ch: int, tile: String) -> String:
	if ch < 0 or tile == "":
		return "open"
	return m["channels"][ch]["tiles"].get(tile, "other")


## The tile a channel shows before any paste: the disc texture's, else the first labelled open.
static func disc(m: Dictionary, ch: int) -> String:
	var c: Dictionary = m["channels"][ch]
	if c.get("disc") != null:
		return c["disc"]
	for k in c["tiles"]:
		if c["tiles"][k] in ["open", "rest"]:
			return k
	return ""
