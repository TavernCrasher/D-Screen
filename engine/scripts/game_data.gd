extends Node
## Loads the DW1 tables exported by tools/dump_tables.py (synced into res://game_data/).

const LEVELS := {"Fresh": 1, "In-Training": 2, "Rookie": 3, "Champion": 4, "Ultimate": 5}
const SPECIALTIES := ["Fire", "Battle", "Air", "Earth", "Ice", "Mech", "Filth"]

var digimon: Array = []
var techniques: Array = []
var items: Array = []
var care: Array = []
var evolution: Dictionary = {}     # id -> evolution entry
var food: Dictionary = {}          # item id -> effects
var motion: Dictionary = {}        # str(id) -> {"anims": {str(anim): {frames, speed}}} (tools/dw1_motion.py)
var tournament_cups: Dictionary = {}  # cups 0-22 from DG section 10 (tools/dw1_scripts.py)
var services: Dictionary = {}      # cards, card prices, transport, collector, medals, area names
var efe: Dictionary = {}           # technique effect scripts, ORIGINAL_TYPE, bones (tools/dw1_efe.py)
var loaded := false


func _ready() -> void:
	if OS.has_feature("dscreen"):            # D-Screen ships no game_data: the pet fills it from the disc (use_exe)
		return
	if "res://pet/pet.tscn" in OS.get_cmdline_args() or OS.has_feature("pet"):   # the pet app (tools/pet_export.py)
		load_pet()
	else:
		load_all()


## The desktop pet (docs/desktop_pet.md) needs only the Digimon table (names, heights, move
## lists), the evolution graph (his forecast, EvoForecast) and the care rows (the card link's poop
## size and weights, CardLink.link_for); it runs all day, so the rest stays unloaded. load_all()
## still loads it if asked.
func load_pet() -> void:
	digimon = _load("digimon")
	techniques = _load("techniques")
	care = _load("care")
	for e in _load("evolution"):
		evolution[int(e["id"])] = e


## D-Screen (docs/shareable_pet_plan.md section 4): the pet's tables from the player's own EXE
## (Dw1Exe, the same shapes as dump_tables.py's JSON), in place of game_data.
func use_exe(x: Dw1Exe) -> void:
	techniques = x.techniques()
	var tech_names: Array = techniques.map(func(t): return t["name"])
	digimon = x.digimon(tech_names)
	var names: Array = digimon.map(func(d): return d["name"])
	items = x.items()
	care = x.care(names, items.map(func(i): return i["name"]))
	evolution = {}
	for e in x.evolution(names):
		evolution[int(e["id"])] = e


func load_all() -> void:
	if loaded:
		return
	digimon = _load("digimon")
	techniques = _load("techniques")
	items = _load("items")
	care = _load("care")
	for e in _load("evolution"):
		evolution[int(e["id"])] = e
	for f in _load("food_effects"):
		food[int(f["item"])] = f
	var tc := FileAccess.get_file_as_string("res://game_data/scripts/tournament_cups.json")
	tournament_cups = JSON.parse_string(tc) if not tc.is_empty() else {}
	for c in tournament_cups.get("cups", []):            # ints, so Array.has(type) matches
		for k in ["warn", "entry", "pool"]:
			c[k] = c[k].map(func(v): return int(v))
	if tournament_cups.has("ultimates"):
		tournament_cups["ultimates"] = tournament_cups["ultimates"].map(func(v): return int(v))
	var sv := FileAccess.get_file_as_string("res://game_data/services.json")
	services = JSON.parse_string(sv) if not sv.is_empty() else {}
	var mt := FileAccess.get_file_as_string("res://game_data/motion.json")
	motion = JSON.parse_string(mt) if not mt.is_empty() else {}
	loaded = true


func _load(name: String) -> Array:
	var path := "res://game_data/%s.json" % name
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("missing %s - run tools/dump_tables.py and tools/sync_godot_data.py" % path)
		return []
	return JSON.parse_string(text)


func level_of(id: int) -> int:
	return LEVELS.get(digimon[id]["level"], 0)


func specialty_ids(id: int) -> Array:
	return digimon[id]["specialties"].map(func(s): return SPECIALTIES.find(s))


func id_by_name(n: String) -> int:
	for d in digimon:
		if d["name"] == n:
			return int(d["id"])
	return -1


## Frames and root-motion speed (DW1 units per frame) of animation anim of Digimon id.
## A technique's effect script: {hdr, uv, mem: PackedByteArray}, or {} (none, e.g. 0x79).
func efe_tech(tech: int) -> Dictionary:
	_load_efe()
	var techs: Array = efe.get("techs", [])
	if tech < 0 or tech >= techs.size() or techs[tech] == null:
		return {}
	var e: Dictionary = techs[tech]
	if not e.has("mem"):
		e["mem"] = Marshalls.base64_to_raw(e["data"])
	return e


func efe_original_type(t: int) -> int:
	_load_efe()
	var o: Array = efe.get("original_type", [])
	return int(o[t]) if t >= 0 and t < o.size() else -1


## A battle clip simulated frame by frame (tools/dw1_efe.py): {"root": [[dx, dy, dz] per
## frame], "bones": {bone: [[x, y, z, m00..m22] per frame]}}, or {}.
func efe_clip(id: int, anim: int) -> Dictionary:
	_load_efe()
	return efe.get("clips", {}).get(str(id), {}).get(str(anim), {})


## Idle-pose bone positions of a Digimon (DW1 units, facing -z), [] if unknown.
func efe_bones(id: int) -> Array:
	_load_efe()
	return efe.get("bones", {}).get(str(id), [])


func _load_efe() -> void:
	if efe.is_empty():
		var t := FileAccess.get_file_as_string("res://game_data/efe.json")
		efe = JSON.parse_string(t) if not t.is_empty() else {"techs": []}


func anim_info(id: int, anim: int) -> Dictionary:
	return motion.get(str(id), {}).get("anims", {}).get(str(anim), {})
