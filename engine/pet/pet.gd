extends Node
## The partner of the pet's save (VpetSave's link; Ninjamon without one) as a desktop pet
## (docs/desktop_pet.md): a borderless, transparent, always-on-top window that shows only him, with
## clicks passing through everywhere else. He idles, walks along the taskbar, trains with his own
## moves, sleeps when the PC is idle, plays DW1's own clips with their eye states (and Ninjamon's
## scarf sway), and speaks in DW1's text box and font (his stage's and his own lines, pet/lines/,
## PetBrain). Click: the
## menu (PetMenu). Drag: he dangles, then drops to the taskbar. Claude Code's hooks
## (tools/pet_hook.py) append events to user://pet_events.jsonl, and he reacts to them; the game
## appends game_load when his save loads (VpetSave), and he leaves.
## Run: tools/run_pet.bat, or godot --path engine res://pet/pet.tscn [-- --partner=8 --say=talk --menu --act=56 --sleep --stay --drop=x,y
## --jump --read --shot=f.png --shot-delay=2.5 --quit --dw1-model --disc=image] (debug: another Digimon, a line, the menu, a clip, a frame of
## the window, D-Screen's models: DW1's own, built from the disc image (DuckStation's DW1, or --disc) by Dw1Model).

const DEFAULT_TYPE := PetBrain.DEFAULT_TYPE
## 60 fps: his clips are keyed at 30 (DW1's frames, linear between them), so at DW1's 20 a third of
## the motion was skipped and he looked stiff beside the smooth game (the user, 2026-10-18); 60 costs
## no more than 20 within measuring noise (0.1% CPU, 1% GPU).
const FPS := 60
const MODEL_PX := PetBrain.MODEL_PX
const TEXT_SCALE := 2.0              # DW1 pixels to screen pixels at 96 dpi
const WIN_SIZE := Vector2(540, 350)  # at 96 dpi
const FEET := 10.0                   # px from the window's bottom to his feet
const HIT_EVERY := 0.15              # s between reads of his frame for the click area
const HIT_SLACK := 4.0               # px around his pixels that still count as him
const PITCH := 12.0                  # camera tilt, degrees (DW1's field camera looks down)
const WALK_YAW := 70.0               # degrees: walking in three-quarter view
const GRAVITY := 2600.0              # px/s^2
const GONE_FALL_V := 450.0           # px/s down at once when the window under him goes (9d 12)
const FLICK_WINDOW := 0.08           # s of the drag before the release a throw's speed is taken from
const SLEEP_AFTER := 300.0           # s without input
const TURN_SPEED := 240.0            # degrees per s: idle glances turn smoothly
const FACE_SPEED := 720.0            # degrees per s: other turns (to walk, leap, face a prop, back to you)
const LEAN_SPEED := 90.0             # degrees per s: leaning over a window's text and back
const JUMP_UP := 5.0                 # Ninjamon heights (MODEL_PX) any of them can leap up to a window top
const JUMP_SIDE := 420.0             # px (96 dpi) sideways
const READ_TILT := 22.0              # degrees forward, peering down at a window's text
const A_LEAP := 11                   # DW1 joy: arms out, a kick; his take-off
const A_LAND := 37                   # DW1 brace: a crouch; his landing
const CONFIG := "pet.cfg"            # in SaveGame.root, so a --save-dir run keeps its own
const MENU := ["Talk", "Praise", "Scold", "Train", "Sleep", "Settings", "Bye"]
## Settings (the user, 2026-10-18: the menu was "a bit LORGE"; the work timer went): each row
## toggles, and the list opens again so several can be changed in a row.
const SETTINGS := ["Speech", "Quiet", "Stay Put", "Name", "Sounds", "Gym Sounds", "Volume", "DW1 Save",
	"Apply to DW1", "Ask to Apply", "About", "Back"]
## D-Screen's Apply window (CardLink; the remake's three answers, main._vpet_offer).
const APPLY := ["Yes", "No", "No, stop asking"]
const APPLY_ROW := 24                # characters a row of gains takes in his text box (a row fits ~26)
const SWITCH_AFTER := 2.5            # s from the Apply window closing to a save switch waiting on it
const RAM_PATTERN := 0x8012CEE8      # the EXE stretch the helper finds DW1's RAM by (Digimon entry 1)
const OFFER_AFTER := 6.0             # s after launch before the Apply window (after his greeting)
const APPLY_PAGE := 3.0              # s a page of gains shows before the box turns to the next
## Volume steps, % (the user, 2026-10-18: "a bit loud", a setting to fine-tune it); 60 at first.
const VOLUMES := [20, 40, 60, 80, 100]
## Speech (the user, 2026-10-18): Text (lines in the box), Mixed (lines plus DW1's icon where one
## fits) or Digi (only DW1's icons: nothing where none fits).
const SPEECH := ["Text", "Mixed", "Digi"]
## Each line category's icon (docs/condition_bubbles.md; pet/pet_bubble.gd): ["b", type] a
## condition bubble as DW1 shows the need, ["fly"] the sulking butterfly, ["face", mood] one of
## Monochromon's shop faces (0 laughing, 1 smile, 2 worried, 3 frown). The bubbles and the
## butterfly mean what they mean in DW1; the faces are the remake's pick (DW1 shows them only over
## customers).
const SPEECH_ICON := {
	"hungry": ["b", ConditionBubble.HUNGRY], "missed": ["b", ConditionBubble.HUNGRY],
	"toilet": ["b", ConditionBubble.TOILET], "accident": ["b", ConditionBubble.TOILET],
	"night": ["b", ConditionBubble.SLEEPY], "trained_enough": ["b", ConditionBubble.TIRED],
	"trained_frozen": ["b", ConditionBubble.TIRED], "dropped": ["b", ConditionBubble.INJURED],
	"evolve_ready": ["b", ConditionBubble.EVOLVING], "pile_left": ["fly"],
	"praise": ["face", 0], "ate": ["face", 0], "toilet_done": ["face", 0], "clean": ["face", 0],
	"trained": ["face", 0], "done": ["face", 0],
	"greet": ["face", 1], "morning": ["face", 1], "talk": ["face", 1], "your_turn": ["face", 1],
	"read": ["face", 1], "game": ["face", 1], "train_start": ["face", 1], "bye": ["face", 1], "wake": ["face", 1],
	"failed": ["face", 2], "ask": ["face", 2], "cant_reach": ["face", 2], "held": ["face", 2],
	"full": ["face", 2], "toilet_no": ["face", 2],
	"scold": ["face", 3], "scold_unfair": ["face", 2],
}
const ICON_HOLD := 3.0               # s a face or the butterfly stays
## DW1's system sounds (bank 0, SS; docs/pet_sounds.md section 3).
const SS_OPEN := 0                   # a window zooms open (createAnimatedUIBox)
const SS_CLOSE := 1                  # ... and closes
const SS_CONFIRM := 3                # a menu pick
const SS_CANCEL := 4                 # Triangle out of a menu (overworld.c:5913)
const SS_FEED := 12                  # the hand-over (partnerTickFeedItem)
const SS_SCOLD := 13
const SS_PRAISE := 14
const SS_SLEEP := 15
const LOOK_FOR := 1.0                # s he follows the cursor after it crosses him
const LOOK_REST := 4.0               # s before a crossing catches his eye again
const MENU_AWAY := 8.0               # s with the cursor off him and his menu before it closes
const PID_EVERY := 5.0               # s between refreshes of his pid file (VpetSave.pet_running)
const ASK_EVERY := 900.0             # s between his asks for food: 3 in all, before the miss at 45 min (3a #9)
const FORECAST_AFTER := 25.0         # s after launch before he says he's ready to evolve
const FORECAST_AFTER_TRAIN := 5.0    # s after the session's own line
const FORECAST_SHARE := 1.0 / 3.0    # of Talk picks and talk chatter that give his hint, while he has one
const COND_IDLE := 0.35              # the share of idle choices that show his need (DW1's condition idles)

enum S { IDLE, WALK, ACT, HELD, FALL, SLEEP, BYE, USE }

var k := 1.0                         # dpi factor
var _fps := FPS
var type := DEFAULT_TYPE             # his DW1 id
var model_px := MODEL_PX             # his height on screen at 96 dpi
var top_px := MODEL_PX               # the top of his head above the ground (floating babies: more)
var body_w := MODEL_PX * 0.85        # his width on screen at 96 dpi (measured once he stands idle)
var _measured := false
var head_px := 0.0                   # the top of his head in the idle pose above his feet (measured; 0: top_px)
var pet_name := ""                   # the name he goes by: his nickname, or his species' (show_species)
var nickname := ""                   # the partner's name (DW1's naming); "" without a save
var species := ""                    # DigimonModel.display_name
var show_species := false           # the Name row (pet.cfg "name"): the species' name over his nickname
var sfx: DwSound                     # DW1's sounds (docs/pet_sounds.md)
var snd: SoundDriver                 # his clips' own cues
var sounds_on := true                # Settings: his clips, care and menus (the user: on by default)
var gym_sounds := true               # Settings: the stations' own sounds, apart ("some might just want to hear the digimon")
var speech := "Text"                 # Settings: SPEECH
var volume := 60                     # Settings: VOLUMES, his sounds and the gym's
var bubble: PetBubble
var _pid_left := 0.0
var win: Window
var cam: Camera3D
var holder: Node3D
var model: Node3D
var layer: Control
var box: DwTextBox
var menu: PetMenu
var brain: PetBrain
var state := S.IDLE
var pos := Vector2.ZERO              # the window's top-left on the desktop (float)
var walk_to := 0.0
var walk_dir := 1.0
var act_left := 0.0                  # s; looping clips end on a timer, one-shots when they finish
var then_line := ""                  # a line to say once the current act finishes
var next_choice := 0.0
var fall_v := 0.0
var fall_vx := 0.0
var fall_from := 0.0
var ground := Rect2()                # the window he stands on; Rect2() = the taskbar
var windows: Array = []              # visible windows, topmost first (pet/pet_helper.cs)
var taskbars: Array = []             # the taskbars' rects (an auto-hidden one slides up and down)
var box_left := 0.0
var _now := 0.0
var _press := false
var _press_at := Vector2.ZERO
var _grab := Vector2.ZERO
var _active_at := 0.0                # last time the user was seen at the PC
var _idle_check := 0.0
var _idle_ms := -1                   # from the helper: ms since the last keyboard or mouse input
var _ev_offset := 0
var _ev_last_t := 0.0
var _ev_poll := 0.0
var _started := 0.0
var _tray := -1
var _args := {}
var _feed := {}
var _feed_thread: Thread
var _feed_mutex := Mutex.new()
var _feed_w := ""                    # the helper's latest window line, "w " included ("" = none new)
var _feed_i := -1                    # its latest idle time (-1 = none new)
var _feed_t := ""                    # its latest taskbar line, "t " included ("" = none new)
var _feed_c: Array[Vector2] = []     # its mouse presses anywhere on the desktop since the last frame
var _feed_d := ""                    # its latest DuckStation line ("d ..."; "" = none new)
var _feed_m := ""                    # its latest DW1 RAM line ("m ...")
var _card := false                   # D-Screen: his save is on DW1's memory card (CardLink)
var _dscreen := false                # the shareable app (the dscreen tag, or --dscreen): setup window, About
var _duck := -1                      # DuckStation: -1 not known yet, 0 closed, else its pid
var _ram := {}                       # DW1 in DuckStation (CardLink.parse_ram), {} none
var _away := false                   # gone into DW1: his save is being played
var _menu_kind := ""                 # "" the menus, "apply" the Apply window, "saves" the save picker
var _switch_to := {}                 # a picked save waiting for the Apply window about the current one
var _switch_at := 0.0
var _switch_ask := true              # "Ask to Apply" when the save was picked: the switch keeps it
var _picker := []                    # the save picker's rows (CardLink.entries)
var _apply_m := {}                   # the offer the Apply window shows (CardLink.pending)
var _offer_at := 0.0                 # when to offer at launch (0: not)
var _apply_pages := []               # the Apply window's box pages (two rows of gains each)
var _apply_page := 0
var _layer_y := 0.0
var _held_trail := []                # [time, mouse] while he's held (PetGround.flick)
var _jumping := false                # a leap on purpose: lands on his feet, no KO
var _jump_to := Vector2.INF          # a leap's target (feet, desktop px): edges above it don't catch him
var _jump_rect := Rect2()            # ... and the window it's on (Rect2() = the taskbar)
var _hold_pose := false              # the current act holds a one-shot's last frame until act_left runs out
var _nod_at := -1.0                  # reading: the next nod (DW1's Brains desk nods every 35 frames); -1 none
## Stay Put (the user, 2026-10-18): he doesn't walk or leap on his own; dragging him, a prop you drop
## and falling when his window goes still move him, and he stays where that leaves him.
var stay_put := false
var _view_x := 0.0                   # px: his window sits this far right of pos to stay on the screen
var _view_y := 0.0                   # px: with the menu open high up, this far below pos (PetGround.menu_drop)
var _ride := Vector2.ZERO            # px: the last ride step his window hasn't caught up with yet (PetGround.ease_ride)
var _ride_told := Rect2(-1, -1, 0, 0)   # the window he stands on, as last named to the helper
var _hit_img: Image                  # his window's last frame, for the click area's alpha test
var _hit_img_at := -1.0
var _px_per_m := 1.0
var facing := Vector3.ZERO           # the rotation he turns to (degrees) outside idle; idle: _tick_gaze
var _gaze := 0.0                     # idle: the yaw he turns to (degrees; 0 faces you, 180 the screen)
var _gaze_back := 0.0                # when an idle glance turns back to you
var _mouse_last := Vector2.ZERO
var _mouse_until := 0.0              # he follows the cursor until then
var _mouse_rest := 0.0               # no new crossing catches his eye before then
var _menu_away := 0.0                # s the cursor has been off him and his open menu
var _look_win := Rect2()             # a window that just opened, came to the front or moved
var _look_win_until := 0.0
var _menu_items := PackedStringArray()
var care: PetCare                    # his care and his file (docs/vpet_save.md)
var place: PetPlace                  # the props ring (Train), the props and piles
var link := {}
var _clicks: Array[Vector2] = []     # the helper's presses this frame
var _asks_left := 0                  # asks for food left (3 per hunger)
var forecast := {}                   # EvoForecast.forecast on his save + desktop totals
var _forecast_at := 0.0              # when he announces he's ready (at launch, after training); 0: not
var _ask_at := 0.0
var _toilet_ask_at := 0.0
var _toilet_asks_left := 0
var _cues := false                   # debug (the trailer): his feed's "cue" lines drive him (PetCues)
var _stage_left := 0.0               # debug: s to the next --stage-out write


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if _args.has("save-dir"):                    # debug: the game's --save-dir (his events and pid too)
		SaveGame.root = "user://%s/" % _args["save-dir"]
	_cues = _args.has("cues")
	if _cues:                                    # the script moves him: no walks or leaps of his own
		_args["stay"] = "1"
	_dscreen = OS.has_feature("dscreen") or _args.has("dscreen")
	_card = _dscreen or _args.has("card")        # D-Screen: his save is on DW1's card (--card)
	if _card:
		VpetSave.pet_prefix = "dw1pet_"                  # beside the remake pet's files, never on them
	if VpetSave.pet_running() and FileAccess.get_file_as_string(VpetSave.pid_path()).strip_edges() != str(OS.get_process_id()):
		print("pet: already running")            # one pet per folder: one writer of his file (PET-8)
		set_process(false)
		get_tree().quit()
		return
	get_tree().set_auto_accept_quit(false)       # closing the window goes through _quit (his last write)
	k = clampf(DisplayServer.screen_get_dpi() / 96.0, 1.0, 3.0)
	if _args.has("dw1-model") or _dscreen:       # D-Screen: DW1's own models from the disc
		var ok := _use_disc()
		if _dscreen and (not ok or not _config("setup", false) or _args.has("first-run")):
			_hide_root()                             # the setup window first (step 8); it starts him again
			set_process(false)
			set_physics_process(false)
			_write_pid()                             # one app per folder while it's open too (DS8-8)
			var beat := Timer.new()
			beat.wait_time = PID_EVERY
			beat.autostart = true
			beat.timeout.connect(_write_pid)
			add_child(beat)
			_open_setup(true)
			return
	if _args.has("fps"):                          # debug: another idle frame rate
		_fps = int(_args["fps"])
	Engine.max_fps = _fps
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	link = _pick_partner()
	brain = PetBrain.new(PetBrain.load_lines(type, str(GameData.digimon[type].get("level", ""))),
		int(_args.get("seed", "-1")))                # debug: --seed=N, the same lines each take
	var his := type == int(link.get("partner_id", -1))   # not --partner, and he has a model
	brain.train = PetBrain.moves_for(GameData, type, brain.lines.get("_moves", []), link.get("techniques", []),
		link.get("moves", []) if his else [])
	care = PetCare.new(link, not _args.has("partner"))   # --partner: in memory only
	if care.hungry():                            # started hungry: one ask soon (the count isn't saved)
		_asks_left = 1
		_ask_at = 30.0
	if care.needs_toilet():                      # the same for the toilet
		_toilet_asks_left = 1
		_toilet_ask_at = 30.0
	_load_config()
	if _args.has("speech"):                      # debug: --speech=Mixed / Digi (saved as the menu saves it)
		speech = str(_args["speech"])
	_apply_name()
	if RenderingServer.get_current_rendering_driver_name() != "opengl3":
		push_warning("pet: run with --rendering-driver opengl3 (tools/run_pet.bat); Forward+ tints the window's box")
	_hide_root()
	_build_window()
	_build_scene()
	place = PetPlace.new()
	add_child(place)
	place.setup(self)
	_place_on_floor(true)
	_started = Time.get_unix_time_from_system()
	_ev_last_t = _started
	_skip_old_events()
	_write_pid()
	_start_feed()
	if _card:
		_start_duck()
		_offer_at = _now + OFFER_AFTER
	_active_at = _now
	brain.schedule_chatter(_now)
	_update_forecast()
	if forecast["state"] == "ready":                 # said once a launch, after his greeting
		_forecast_at = _now + FORECAST_AFTER
	if _args.has("forecast"):                        # debug: his hint 1 s in (ready or close)
		print("forecast ", forecast)
		_forecast_at = _now + 1.0 if forecast["state"] != "none" else 0.0
	next_choice = _now + 3.0
	if _cues:                                    # nothing unprompted on the script's clock
		_forecast_at = 0.0
		_offer_at = 0.0
		brain.next_chatter = INF
	if _args.has("hidden"):                      # debug: unseen until the "appear" cue
		holder.visible = false
	else:
		_greet()
	if _args.has("say"):
		_say(brain.pick(_args["say"]))
	if _args.has("menu"):                        # --menu=settings: the Settings list
		_open_menu(SETTINGS if _args["menu"] == "settings" else MENU)
	if _args.has("sleep"):
		box.close_now()
		state = S.IDLE
		_sleep(true)
	if _args.has("drop"):
		_debug_drop(String(_args["drop"]).split(","))
	if _args.has("jump"):
		get_tree().create_timer(2.5).timeout.connect(func(): print("jump: ", _try_jump(), " from ", _feet()))
	if _args.has("read"):
		get_tree().create_timer(2.5).timeout.connect(_read)
	if _args.has("act"):
		_act(int(_args["act"]), "", 3.0)
	if _args.has("ring") and not _args.has("drop"):   # debug: the props ring open (with --drop: once he lands)
		place.open_ring()
	if _args.has("hungry"):                      # debug: hungry now
		care.d["live"]["hunger_at"] = care.d["live"]["clock"]
	if _args.has("due"):                         # debug: due for the toilet now
		PetCues.due_now(care.d)
	if _args.has("accident"):                    # debug: an accident on the next frame
		care.d["live"]["poops"] = [float(care.d["live"]["clock"])]
		care.d["live"]["toilet_since"] = float(care.d["live"]["clock"])
		care.d["live"]["clock"] = float(care.d["live"]["clock"]) + Vpet.toilet_window(100)
	if _args.has("pick"):                        # debug: menu rows in turn, 4 s apart (--pick=Scold,Praise)
		var rows: PackedStringArray = str(_args["pick"]).split(",", false)
		for i in rows.size():
			get_tree().create_timer(2.5 + 4.0 * i).timeout.connect(_menu_pick.bind(rows[i]))
	if _args.has("prop"):                        # debug: a prop dropped beside him
		get_tree().create_timer(1.0).timeout.connect(func(): place._place_beside(_args["prop"]))
	if _args.has("shot"):
		_shot.call_deferred(_args["shot"], float(_args.get("shot-delay", "2.5")))
	_make_tray.call_deferred()


# ---------------------------------------------------------------- setup
## Who he is: the partner of the pet's save (the game's link), or --partner=N, or Ninjamon. A
## Digimon without a model stays Ninjamon. Returns the link ({} without one).
func _pick_partner() -> Dictionary:
	var link := {} if _args.has("partner") else CardLink.link(GameData) if _card else VpetSave.read_link()
	var want := int(_args["partner"]) if _args.has("partner") else int(link.get("partner_id", DEFAULT_TYPE))
	type = want if _has_model(want) else DEFAULT_TYPE
	species = DigimonModel.display_name(type)
	nickname = str(link.get("partner_name", "")) if type == want else ""
	_apply_name()
	model_px = PetBrain.size_px(type)
	top_px = model_px * PetBrain.top_factor(type)
	return link


## The name in his text box, window titles and tray tip: his nickname unless the Name row says the
## species', or he has none (DW1 names the partner; the user's default is the nickname, 2026-10-18).
func _apply_name() -> void:
	pet_name = PetBrain.pick_name(nickname, species, show_species)
	if is_instance_valid(win):
		win.title = _title()
		get_window().title = _title()
	if _tray >= 0:
		DisplayServer.status_indicator_set_tooltip(_tray, _tray_tip())


## His windows' title: his name, and the app's in D-Screen.
func _title() -> String:
	if not _dscreen:
		return pet_name
	return "%s - D-Screen" % pet_name if pet_name != "" else "D-Screen"


func _tray_tip() -> String:
	return "%s (right click: quit)" % _title()


static func _has_model(id: int) -> bool:
	if Dw1Model.on():
		return id > 0 and id < Dw1Exe.DIGIMON_COUNT and not Dw1Model.info(id).is_empty()
	var chr := DigimonModel.chr_for(id) if id > 0 and id < GameData.digimon.size() else ""
	return chr != "" and ResourceLoader.exists("res://models/%s.glb" % chr)


## D-Screen's models and tables (docs/shareable_pet_plan.md steps 5 and 8): DW1 (USA) from --disc,
## the setup window's pick (pet.cfg) or DuckStation's game list, read every launch. Without one the
## personal build keeps its models; D-Screen opens the setup window. False: no disc.
func _use_disc() -> bool:
	var path := str(_args.get("disc", _config("disc", "")))
	if not FileAccess.file_exists(path):
		path = Dw1Disc.find_dw1()
	var d := Dw1Disc.open_checked(path) if path != "" else null
	if d == null or d.error != "" or not d.is_dw1_usa():
		push_warning("pet: no DW1 (USA) disc image (%s): %s" % [path, d.error if d else "none found"])
		return false
	var x := Dw1Exe.from_disc_checked(d)
	if x.error != "":
		push_warning("pet: the disc's EXE: " + x.error)
		return false
	Dw1Model.use(d, x)
	GameData.use_exe(x)                                  # D-Screen ships no game_data (CARD-G1)
	return true


## A value of pet.cfg's [dscreen] section (the setup window's: disc, setup).
func _config(key: String, default: Variant) -> Variant:
	var c := ConfigFile.new()
	return c.get_value("dscreen", key, default) if c.load(SaveGame.root + CONFIG) == OK else default


## The setup window (DScreenSetup): at the first run, when the disc can't be read, and Settings'
## About. Start / Apply keeps its disc in pet.cfg and starts him again when the disc or his save
## changed; Quit at the first run quits.
func _open_setup(first: bool) -> void:
	if not first and is_instance_valid(get_node_or_null("Setup")):
		return
	var s := DScreenSetup.new()
	s.name = "Setup"
	s.setup(first, str(_args.get("disc", _config("disc", ""))), k)
	s.finished.connect(_setup_finished.bind(s, first))
	add_child(s)
	if _args.has("stage-out"):                            # debug: where its Start / Apply button is
		_stage_setup.call_deferred(s)
	if _args.has("setup-shot"):                          # debug: --setup-shot=f.png saves the window and quits
		await get_tree().create_timer(float(_args.get("shot-delay", "2.5"))).timeout
		s.get_texture().get_image().save_png(str(_args["setup-shot"]))
		print("setup window ", s.size, " disc ", s.disc_path, " saves ", s.saves.size())
		_drop_pid()
		get_tree().quit()


func _setup_finished(changed: bool, s: DScreenSetup, first: bool) -> void:
	s.queue_free()
	if s.has_meta("quit"):
		if first:
			_drop_pid()
			get_tree().quit()
		return
	var c := ConfigFile.new()
	c.load(SaveGame.root + CONFIG)
	c.set_value("dscreen", "disc", s.disc_path)
	c.set_value("dscreen", "setup", true)
	c.save(SaveGame.root + CONFIG)
	_args.erase("disc")
	if first:                                            # no pet yet: start the app again
		_drop_pid()                                      # before the next one checks it
		OS.create_instance(_restart_args())
		get_tree().quit()
	elif changed:
		_quit(true)


## This launch's arguments for the next one, less the one-time --first-run and --disc.
func _restart_args() -> PackedStringArray:
	return PetBrain.relaunch_args(OS.get_cmdline_args(), OS.get_cmdline_user_args(), OS.has_feature("template"),
		RenderingServer.get_current_rendering_driver_name(), ProjectSettings.globalize_path("res://"))


## What he calls out when he trains a move: his own line for it, else the move's name.
func _train_line(anim: int) -> String:
	var own := brain.pick("train_%d" % anim)
	if own != "":
		return own
	var techs: Array = GameData.digimon[type]["techniques"]
	var n := anim - DigimonModel.TECH_ANIM_START
	if n < 0 or n >= techs.size():
		return ""
	return PetBrain.move_call(str(GameData.techniques[Techniques.slot_move(GameData, type, n)].get("name", "")))


## The root window stays hidden: the pet lives in its own transparent window.
func _hide_root() -> void:
	var r := get_window()
	r.gui_embed_subwindows = false
	r.borderless = true
	r.size = Vector2i(1, 1)
	r.position = Vector2i(-100, -100)
	r.title = _title()                                       # Godot can't hide its main window


func _build_window() -> void:
	win = Window.new()
	win.title = _title()
	win.transparent_bg = true
	win.transparent = true
	win.borderless = true
	win.always_on_top = true
	win.unfocusable = true
	win.size = Vector2i((WIN_SIZE + Vector2(0, maxf(0.0, top_px - MODEL_PX))) * k)   # room for a tall one
	add_child(win)
	win.window_input.connect(_on_input)
	win.close_requested.connect(_quit)


func _build_scene() -> void:
	var root := Node3D.new()
	win.add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	root.add_child(sun)
	holder = Node3D.new()
	root.add_child(holder)
	model = DigimonModel.instance(type)
	holder.add_child(model)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var h := float(win.size.y)
	var px_per_m := model_px * k / (DigimonModel.dw1_height(type) if DigimonModel.dw1_height(type) > 0.0 else 1.0)
	_px_per_m = px_per_m
	cam.size = h / px_per_m
	# feet (the origin) at FEET px above the window's bottom: the look-at point sits (h/2 - FEET)
	# px above them along the tilted screen's up axis
	var th := deg_to_rad(PITCH)
	var t := (h / 2.0 - FEET * k) / px_per_m / cos(th)
	cam.rotation = Vector3(-th, 0, 0)
	cam.position = Vector3(0, t, 0) + cam.transform.basis.z * 20.0
	root.add_child(cam)
	cam.make_current()
	layer = Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := TEXT_SCALE * k
	layer.size = Vector2(win.size.x, 240.0 * s)
	_layer_y = 4.0 * k - (120.0 + DwTextBox.RECT.position.y) * s
	layer.position = Vector2(0, _layer_y)
	win.add_child(layer)
	bubble = PetBubble.new()                                # under the text box
	win.add_child(bubble)
	win.move_child(bubble, layer.get_index())
	box = DwTextBox.new()
	layer.add_child(box)
	menu = PetMenu.new()
	layer.add_child(menu)
	sfx = DwSound.new()
	add_child(sfx)
	sfx.volume_db = linear_to_db(volume / 100.0)
	snd = SoundDriver.new()
	add_child(snd)
	snd.setup(sfx, type)
	# D-Screen: render what he plays from the disc now (cached after the first launch)
	sfx.warm([["ss", [SS_OPEN, SS_CLOSE, SS_CONFIRM, SS_CANCEL, SS_FEED, SS_SCOLD, SS_PRAISE, SS_SLEEP]],
		snd.vl, snd.vb, "sl", ["es14", [0, 2, 3, 4, 5, 9, 10]]])
	if model is Dw1Model:                                    # his clips fire their own cues
		snd.listen(model)
	snd.enabled = sounds_on
	snd.no_steps = [PetBrain.A_DISTRESS]                     # no footsteps while he dangles
	_play(PetBrain.A_IDLE)
	# he runs all day: keep only his rows of the shared DW1 tables (motion 2.8 MB, eye states, cues)
	DigimonModel._motion = {str(type): DigimonModel._motion.get(str(type), {})}
	EyeTrack._data = {str(type): EyeTrack._data.get(str(type), {})}
	SoundDriver._all = {}


func _load_config() -> void:
	var c := ConfigFile.new()
	if c.load(SaveGame.root + CONFIG) == OK:
		brain.quiet = c.get_value("pet", "quiet", false)
		stay_put = c.get_value("pet", "stay_put", false)
		show_species = c.get_value("pet", "name", "nickname") == "species"
		sounds_on = c.get_value("pet", "sounds", true)
		gym_sounds = c.get_value("pet", "gym_sounds", true)
		speech = c.get_value("pet", "speech", "Text")
		volume = c.get_value("pet", "volume", 60)
		if not volume in VOLUMES:
			volume = 60
		if not speech in SPEECH:
			speech = "Text"
		pos.x = c.get_value("pet", "x", -1.0)
	else:
		pos.x = -1.0


func _save_config() -> void:
	var c := ConfigFile.new()
	c.load(SaveGame.root + CONFIG)                       # keeps the setup window's [dscreen] section
	c.set_value("pet", "quiet", brain.quiet)
	c.set_value("pet", "stay_put", stay_put)
	c.set_value("pet", "name", "species" if show_species else "nickname")
	c.set_value("pet", "sounds", sounds_on)
	c.set_value("pet", "gym_sounds", gym_sounds)
	c.set_value("pet", "speech", speech)
	c.set_value("pet", "volume", volume)
	c.set_value("pet", "x", pos.x)
	c.save(SaveGame.root + CONFIG)


# ---------------------------------------------------------------- the frame
func _process(delta: float) -> void:
	_now += delta
	bubble.anchor = Vector2(_body_x(), _floor_y() - (FEET + (head_px if head_px > 0.0 else top_px)) * k)
	bubble.ppu = _px_per_m * FieldMap.UNIT
	bubble.face_px = TEXT_SCALE * k
	bubble.box_bottom = layer.position.y + box.pixel_rect().end.y if box.visible and speech == "Mixed" else -1.0
	_watch_user(delta)
	_poll_events(delta)
	_take_feed(delta)
	_tick_switch()
	_pid_left -= delta
	if _pid_left <= 0.0:
		_write_pid()
	_tick_care(delta)
	place.tick(delta, _clicks)
	if state in [S.IDLE, S.WALK, S.ACT, S.SLEEP, S.BYE, S.USE]:
		_check_ground()
	match state:
		S.IDLE:
			if not place.want(delta):
				_tick_idle()
				_tick_gaze(delta)
		S.USE:
			place.tick_use(delta)
			_tick_facing(delta)
		S.WALK:
			_tick_walk(delta)
			_tick_facing(delta)
		S.ACT:
			_tick_act(delta)
			_tick_facing(delta)
		S.FALL:
			_tick_fall(delta)
			_tick_facing(delta)
		S.HELD:
			var m := Vector2(DisplayServer.mouse_get_position())
			_held_trail.append([_now, m])                    # the last moments of the drag, for the throw
			while _held_trail.size() > 2 and float(_held_trail[0][0]) < _now - FLICK_WINDOW * 3.0:
				_held_trail.pop_front()
			pos = m - _grab
			_tick_facing(delta)
		S.BYE:
			_tick_act(delta)
			_tick_facing(delta)
		S.SLEEP:
			_tick_facing(delta)
	if box.visible and not box.done():
		box_left -= delta
		if box_left <= 0.0 and box.is_open():
			box.close_now()
	_ride = PetGround.ease_ride(_ride, delta)
	_tell_ride()
	_place_window()
	place.after_move()                                       # the props' copies follow his window this frame
	_keep_text_on_screen()
	_update_passthrough()
	if _args.has("stage-out"):
		_write_stage(delta)


func _tick_idle() -> void:
	if menu.visible or place.ring_open:                      # he waits for your pick (the ring too)
		next_choice = maxf(next_choice, _now + 3.0)
		return
	if _forecast_at > 0.0 and _now >= _forecast_at:
		_forecast_at = 0.0
		_act(PetBrain.A_JOY, _forecast_line())
		return
	var r := brain.chatter(_now, Time.get_datetime_dict_from_system()["hour"])
	if not r.is_empty():
		var line := _forecast_line() if r["line"] == "talk" and brain.rng.randf() < FORECAST_SHARE else ""
		_act(int(r["anim"]), line if line != "" else brain.pick(r["line"]))
		return
	if _now < next_choice or _args.has("stay"):
		return
	next_choice = _now + brain.rng.randf_range(4.0, 12.0)
	var roll := brain.rng.randf()
	var need := _need_clip()
	if need >= 0 and roll < COND_IDLE:
		_act(need, "", 3.0)
		if speech != "Text":                                 # DW1's bubble names the need
			bubble.show_bubble(ConditionBubble.TOILET if need == PetBrain.A_TOILET else ConditionBubble.HUNGRY, 2)
		return
	if roll < 0.18 and not stay_put and _try_jump():
		return
	if roll < 0.28 and ground.size != Vector2.ZERO:
		_read()
		return
	if roll < 0.55:
		# along the taskbar, or the window he's on; now and then off its end, to drop to the next
		var sp := Vector2(_usable().position.x + 60.0 * k, _usable().end.x - 60.0 * k)
		if ground.size != Vector2.ZERO:
			sp = PetGround.span(ground, 30.0 * k)
		var fx := brain.rng.randf_range(sp.x, sp.y)
		if ground.size != Vector2.ZERO and brain.rng.randf() < 0.1:
			fx = sp.x - 70.0 * k if brain.rng.randf() < 0.5 else sp.y + 70.0 * k
		var x := fx - float(win.size.x) / 2.0
		if absf(x - pos.x) > 80.0 * k and not stay_put:
			_walk(x)
	elif roll < 0.73 and _mood_clip() >= 0:
		_act(_mood_clip(), "", 2.5)
	elif roll < 0.8:
		var mv := _shadowbox()                               # now and then he calls the move out
		_act(mv, _train_line(mv) if brain.rng.randf() < 0.25 and not brain.quiet else "")
	else:
		_glance()


## DW1's condition idle for his need (FUN_800df2d0: the toilet before hunger), -1 for none.
func _need_clip() -> int:
	if care.needs_toilet():
		return PetBrain.A_TOILET
	if care.hungry():
		return PetBrain.A_HUNGRY
	return -1


## DW1's idle without a condition: happiness above 30 the happy idle 5, below -30 the unhappy 7
## (FUN_800df2d0, main.c:32373-32374), else none. His happiness: the save's and the desktop's since.
func _mood_clip() -> int:
	var h := int((link.get("base", {}) as Dictionary).get("happiness", 50)) + Vpet.unapplied(care.d, link, "happy")
	return PetBrain.A_HAPPY if h > 30 else (PetBrain.A_UNHAPPY if h < -30 else -1)


## One of his first two moves (Ninjamon: Sonic Jab, Dynamite Kick), or a joy hop without any.
func _shadowbox() -> int:
	if brain.train.is_empty():
		return PetBrain.A_JOY
	return int(brain.train[brain.rng.randi_range(0, mini(1, brain.train.size() - 1))])


## Idle: he turns to look left or right, or now and then away into the screen, then back to you.
func _glance() -> void:
	var side := 1.0 if brain.rng.randf() < 0.5 else -1.0
	if brain.rng.randf() < 0.3:
		_gaze = side * brain.rng.randf_range(150.0, 180.0)   # his back to you: watching the screen
	else:
		_gaze = side * brain.rng.randf_range(35.0, 75.0)
	_gaze_back = _now + brain.rng.randf_range(2.5, 6.0)
	next_choice = maxf(next_choice, _gaze_back + 1.0)


## Idle: his yaw eases to the glance, or to the cursor while it moves near his head, or to a
## window that just opened, came to the front or moved; he leans back to look up, forward to look
## down.
func _tick_gaze(delta: float) -> void:
	if _gaze_back > 0.0 and _now >= _gaze_back:
		_gaze_back = 0.0
		_gaze = brain.rng.randf_range(-12.0, 12.0)           # not quite square on
	var head := _feet() - Vector2(0, top_px * 0.8 * k)
	var m := Vector2(DisplayServer.mouse_get_position())
	var moved := m.distance_to(_mouse_last) > 2.0
	_mouse_last = m
	# the cursor crossing him (moving over his body) catches his eye for a second; resting on him
	# to click doesn't
	if moved and _now >= _mouse_rest and _hit_rects()[0].grow(16.0 * k).has_point(m - Vector2(win.position)):
		_mouse_until = _now + LOOK_FOR
		_mouse_rest = _now + LOOK_REST
	var yaw := _gaze
	var pitch := 0.0
	var speed := TURN_SPEED
	var at := Vector2.INF
	if _now < _mouse_until:
		at = m
	elif _now < _look_win_until:
		at = _look_win.get_center()
	if at != Vector2.INF:
		var d := at - head
		yaw = clampf(d.x / (120.0 * k), -1.0, 1.0) * 70.0
		pitch = clampf(d.y / (250.0 * k), -1.0, 1.0) * 14.0
		speed = TURN_SPEED * 1.5
	holder.rotation_degrees.y = PetGround.turn(holder.rotation_degrees.y, yaw, speed * delta)
	holder.rotation_degrees.x = move_toward(holder.rotation_degrees.x, pitch, 60.0 * delta)


## Outside idle he turns to `facing` (quickly) instead of snapping, which looked stiff (the user,
## 2026-10-18); leans and tilts ease slower. DW1's Digimon ease their turns too (map NPCs about
## 199°/s, NPCEntity.cpp:14; script rotates about 900°/s, Entity.cpp:196); only the tamer snaps.
func _tick_facing(delta: float) -> void:
	var r := holder.rotation_degrees
	holder.rotation_degrees = Vector3(move_toward(r.x, facing.x, LEAN_SPEED * delta),
		PetGround.turn(r.y, facing.y, FACE_SPEED * delta), move_toward(r.z, facing.z, LEAN_SPEED * delta))



func _walk(x: float) -> void:
	walk_to = x
	walk_dir = signf(x - pos.x)
	facing = Vector3(0, WALK_YAW * walk_dir, 0)             # quickly (DW1's Digimon ease too: NPCs ~199°/s)
	state = S.WALK
	_play(PetBrain.A_WALK)


func _tick_walk(delta: float) -> void:
	pos.x += walk_dir * _walk_speed() * delta
	if (walk_to - pos.x) * walk_dir <= 0.0:
		pos.x = walk_to
		_idle()


func _idle() -> void:
	state = S.IDLE
	_hold_pose = false
	facing = Vector3.ZERO
	_gaze = 0.0                                              # _tick_gaze turns him back
	_gaze_back = 0.0
	_play(PetBrain.A_IDLE)
	_save_config()
	if not _measured:
		_measured = true
		_measure_body.call_deferred()


## Plays a DW1 clip; a looping one stops after `hold` s. `line` is said as it starts.
func _act(anim: int, line := "", hold := 2.0) -> void:
	if state == S.HELD or state == S.FALL:
		return
	if state == S.USE:                                       # a prop session ends with any other act (PET-10)
		place.cancel()
	state = S.ACT
	_hold_pose = false
	_nod_at = -1.0
	facing = Vector3.ZERO
	_play(anim)
	act_left = hold
	if line != "":
		_say(line)


func _tick_act(delta: float) -> void:
	act_left -= delta
	var ended := not DigimonModel.is_playing(model) or (DigimonModel.dw1_oneshot(type, _anim) == false and act_left <= 0.0)
	if _hold_pose:
		ended = act_left <= 0.0
		if _nod_at >= 0.0 and _now >= _nod_at and act_left > PetPlace.CHALK_EVERY:
			_play(PetBrain.A_NOD)
			_nod_at = _now + PetPlace.CHALK_EVERY
	if not ended:
		return
	if state == S.BYE:
		if not box.visible or box.done():
			_gone()
		return
	if _queued >= 0:
		_play(_queued)
		_queued = -1
		act_left = 2.5
		return
	if then_line != "":
		_say(then_line)
		then_line = ""
	_idle()


var _anim := 0


func _play(id: int) -> void:
	_anim = id
	if snd:                                                  # first: a Dw1Model fires its tick-0
		snd.start(id)                                        # cues as it starts (DSM-3)
	DigimonModel.play_dw1(model, type, id)


## A DW1 system sound (SS), unless Sounds is off.
func ss(id: int) -> void:
	if sounds_on and sfx:
		sfx.play("ss", id)


## A gym station's sound (ESALL section 14; docs/pet_sounds.md section 4), unless Gym Sounds is off.
func gym(id: int) -> AudioStreamPlayer:
	return sfx.play("es14", id) if gym_sounds and sfx else null


# ---------------------------------------------------------------- dragging and falling
func _on_input(e: InputEvent) -> void:
	if place.ring_input(e):
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_press = true
			_press_at = Vector2(DisplayServer.mouse_get_position())
			_grab = _press_at - pos - _ride
		elif _press:
			_press = false
			if state == S.HELD:
				_drop()
			else:
				_click(e.position)
	elif e is InputEventMouseMotion:
		if menu.is_open():
			var r := menu.row_at(e.position - layer.position)
			if r != menu.hover:
				menu.hover = r
		if _press and state != S.HELD and state != S.BYE \
				and Vector2(DisplayServer.mouse_get_position()).distance_to(_press_at) > 6.0 * k:
			_pick_up()


func _pick_up() -> void:
	pos += _ride
	_ride = Vector2.ZERO
	_held_trail = [[_now, Vector2(DisplayServer.mouse_get_position())]]
	if menu.is_open():
		menu.close_window()
	place.close_ring()
	place.cancel()
	_jumping = false
	_jump_to = Vector2.INF
	state = S.HELD
	Engine.max_fps = 60
	facing = Vector3.ZERO
	_play(PetBrain.A_DISTRESS)                               # DW1's distress loop while he dangles
	if brain.rng.randf() < 0.5 and not brain.quiet:
		_say(brain.pick("held"))


## Let go: he keeps the throw's speed (capped).
func _drop() -> void:
	var v := PetGround.throw_cap(PetGround.flick(_held_trail, _now, FLICK_WINDOW), _screen_rect().size.x, 1800.0 * k)
	_fall(v.x, v.y)


func _fall(vx: float, vy: float) -> void:
	if menu.is_open():
		menu.close_window()
	place.close_ring()
	if state == S.USE:
		place.cancel()
	state = S.FALL
	Engine.max_fps = 60
	fall_vx = vx
	fall_v = vy
	fall_from = _feet().y
	ground = Rect2()
	_hold_pose = false
	facing.x = 0.0
	if not _jumping and _anim != PetBrain.A_DISTRESS:
		facing.y = 0.0
		_play(PetBrain.A_DISTRESS)                           # flailing on the way down


func _tick_fall(delta: float) -> void:
	var y0 := _feet().y
	fall_v += GRAVITY * k * delta
	pos.y += fall_v * delta
	pos.x += fall_vx * delta
	_clamp_x()
	var f := _feet()
	var hit := {}
	if _jumping and _jump_to != Vector2.INF and y0 < _jump_to.y:
		# a leap down to a target passes the window tops above it (they caught him on the way, so he
		# rarely got down through windows, the user, 2026-10-18)
		if f.y < _jump_to.y:
			return
		if _jump_rect.size == Vector2.ZERO or PetGround.stands_on(windows, _jump_rect, f.x, _usable(), _room(), 20.0 * k):
			hit = {"y": _usable().end.y if _jump_rect.size == Vector2.ZERO else _jump_rect.position.y, "rect": _jump_rect}
		else:
			hit = PetGround.landing(windows, f.x, _jump_to.y, f.y, _usable(), _room(), 20.0 * k)
	else:                                                    # a spot half his width over still catches him (9d 11)
		hit = PetGround.landing(windows, f.x, y0, f.y, _usable(), _room(), 20.0 * k, body_w * 0.5 * k)
	if hit.is_empty():
		return
	if hit.has("x"):
		pos.x += float(hit["x"]) - f.x
	_jump_to = Vector2.INF
	_set_feet_y(float(hit["y"]))
	ground = hit["rect"]
	if _args.has("drop") or _args.has("jump"):
		print("landed at ", hit["y"], " on ", ground, " (", windows.size(), " windows: ", windows.slice(0, 4), ")")
		if _args.has("ring") and not place.ring_open:
			place.open_ring.call_deferred()
	Engine.max_fps = _fps
	var far := float(hit["y"]) - fall_from > 220.0 * k
	state = S.IDLE                                           # so _act runs
	if _jumping:
		_jumping = false
		_act(A_LAND)                                         # a crouch, then idle
		return
	if far:
		_act(PetBrain.A_KO)
		then_line = "" if brain.quiet else brain.pick("dropped")
		_queue_after(PetBrain.A_KO_UP)
	else:
		_act(PetBrain.A_FLINCH)


var _queued := -1


## --drop=x,y: dropped from feet x,y once the helper's first window list is in (at most 3 s), so
## a window below catches him (dropped before it, he fell through to the taskbar).
func _debug_drop(d: PackedStringArray) -> void:
	var t := 0.0
	while windows.is_empty() and not _feed.is_empty() and t < 3.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	pos.x = float(d[0]) - float(win.size.x) / 2.0
	_set_feet_y(float(d[1]))
	_fall(0.0, 0.0)


## Leap to a window top within reach (up or down), or down to the taskbar. False: none in reach.
func _try_jump() -> bool:
	var f := _feet()
	var spots := PetGround.reachable(windows, f, _usable(), _room(), 30.0 * k, JUMP_UP * MODEL_PX * k, JUMP_SIDE * k, ground)
	if spots.is_empty():
		return false
	var up := spots.filter(func(t): return float(t["y"]) < f.y)
	var pick: Dictionary = (up if not up.is_empty() and brain.rng.randf() < 0.65 else spots).pick_random()
	_jump(Vector2(float(pick["x"]), float(pick["y"])), pick["rect"])
	return true


## A ballistic leap from his feet to `to` (desktop px) on `rect` (Rect2() = the taskbar): up to an
## apex above the higher end, then down onto it; only the target catches him above its height.
func _jump(to: Vector2, rect := Rect2()) -> void:
	var a := _feet()
	var g := GRAVITY * k
	var apex := minf(a.y, to.y) - (50.0 * k + 0.12 * absf(to.x - a.x))
	var vy := -sqrt(2.0 * g * (a.y - apex))
	var t := -vy / g + sqrt(2.0 * maxf(0.0, to.y - apex) / g)
	_jumping = true
	var dir := signf(to.x - a.x)
	_jump_rect = rect
	_jump_to = Vector2(to.x, _usable().end.y if rect.size == Vector2.ZERO else rect.position.y)
	facing = Vector3(0, WALK_YAW * dir if absf(to.x - a.x) > 20.0 * k else 0.0, 0)
	_fall((to.x - a.x) / t, vy)
	_play(A_LEAP)
	DigimonModel.set_speed(model, 1.6)                       # the kick lands mid-air
	snd.rate = 1.6


## On a window: he leans over its edge and studies the text below, nodding as at DW1's Brains desk,
## sometimes saying so (the read cue: for `hold` s, saying it when `say`).
func _read(hold := 0.0, say := false) -> void:
	_act(PetBrain.A_NOD, "", hold if hold > 0.0 else brain.rng.randf_range(4.0, 7.0))   # the Brains desk's nod
	_hold_pose = true
	_nod_at = _now + PetPlace.CHALK_EVERY                  # and nods on, as he studies (live check PET-5c)
	facing.x = READ_TILT
	if (say or brain.rng.randf() < 0.3) and not brain.quiet:
		_say(brain.pick("read"))


## His launch greeting, by the hour (debug: --greet=category, kept across his restarts).
func _greet() -> void:
	var cat := str(_args.get("greet", PetBrain.greet_category(Time.get_datetime_dict_from_system()["hour"])))
	_act(PetBrain.A_HAPPY, brain.pick(cat))


## A clip to play once the current one ends (the KO's get-up).
func _queue_after(id: int) -> void:
	_queued = id


# ---------------------------------------------------------------- clicks and the menu
func _click(at: Vector2) -> void:
	if state == S.SLEEP:
		_wake()
		return
	if place.ring_open:                                       # a click on him closes the ring
		place.close_ring()
		return
	if box.visible and not box.done() and box.pixel_rect().has_point(at - layer.position):
		if _menu_kind == "apply" and menu.is_open():      # the gains stay with the window: a click turns
			if _apply_pages.size() > 1:                    # their page (it closed them, Yes / No left alone, 9d 7)
				_apply_page = (_apply_page + 1) % _apply_pages.size()
				box.set_page(pet_name, 7, _apply_pages[_apply_page])
				box.queue_redraw()
			return
		box.close_now()
		return
	if menu.is_open():
		var r := menu.row_at(at - layer.position)
		menu.close_window()
		ss(SS_CONFIRM if r >= 0 else SS_CANCEL)          # then the box closes: SS 1 (PET-30)
		ss(SS_CLOSE)
		if r >= 0:
			_menu_pick(_menu_items[r], r)
		elif _menu_kind == "apply":                       # closed without an answer: asked again later
			box.close_now()
			_apply_m = {}
		return
	if state == S.IDLE or state == S.WALK or state == S.ACT:
		_open_menu()


func _open_menu(items: Array = MENU, kind := "") -> void:
	if state == S.WALK:
		_idle()
	_menu_kind = kind
	var labels := PackedStringArray(items)
	if items == SETTINGS:
		labels[SETTINGS.find("Quiet")] = "Talk more" if brain.quiet else "Quiet"
		labels[SETTINGS.find("Stay Put")] = "Go Explore" if stay_put else "Stay Put"
		labels[SETTINGS.find("Speech")] = "Speech:  " + speech
		labels[SETTINGS.find("Volume")] = "Volume:  %d" % volume
		labels[SETTINGS.find("Sounds")] = "Sounds On" if not sounds_on else "Sounds Off"
		labels[SETTINGS.find("Gym Sounds")] = "Gym Sounds On" if not gym_sounds else "Gym Sounds Off"
		labels[SETTINGS.find("Name")] = "Show Nickname" if show_species else "Show Species"
		labels[SETTINGS.find("Ask to Apply")] = "Ask to Apply:  " + ("On" if bool(link.get("ask", true)) else "Off")
		if nickname == "" or nickname == species:                # nothing to switch between
			labels.remove_at(SETTINGS.find("Name"))
		if not _card:                                            # D-Screen's card rows
			labels.remove_at(labels.find("DW1 Save"))
		if not _dscreen:                                         # the notice, the disc and his save
			labels.remove_at(labels.find("About"))
		if not _card or link.is_empty():
			labels.remove_at(labels.find("Apply to DW1"))
			labels.remove_at(labels.find("Ask to Apply:  " + ("On" if bool(link.get("ask", true)) else "Off")))
	_menu_items = labels
	_menu_away = 0.0
	ss(SS_OPEN)
	menu.width = PetMenu.WIDTH                           # open_menu widens it for a long row
	menu.open_menu(labels, Vector2.ZERO, Rect2(_menu_head(), Vector2(8, 8)))
	_place_menu()


func _menu_head() -> Vector2:
	return _dw(Vector2(_body_x(), _floor_y() - (FEET + top_px * 0.8) * k))


## Beside his head (right of it, or left when that would leave the window, which is always on the
## screen sideways), every frame, so it stays with him; up and down inside the part of the window
## that is on the screen: off its top high on a window, over the taskbar low (9d 4, Doug's report).
## _place_window holds the window down for it (_view_y).
func _place_menu() -> void:
	var head := _menu_head()
	var u := _usable()
	var wy := float(win.position.y)
	var lo := _dw(Vector2(0.0, maxf(0.0, u.position.y - wy)))
	var hi := _dw(Vector2(float(win.size.x), minf(float(win.size.y), u.end.y - wy)))
	var at := Vector2(head.x + 28, head.y)
	if at.x + menu.width > hi.x - 2:
		at.x = head.x - 28 - menu.width
	at.x = clampf(at.x, lo.x + 2, hi.x - menu.width - 2)
	at.y = PetGround.menu_y(at.y, menu.target.size.y, lo.y, hi.y)
	menu.target.position = at


## The menu closes when you click elsewhere on the desktop (the helper's "c" presses), or leave
## the cursor off him and the menu for MENU_AWAY s.
func _tick_menu(delta: float, clicks: Array[Vector2]) -> void:
	if not menu.visible:
		return
	_place_menu()
	if not menu.is_open():
		return
	var rects := _hit_rects()
	for c in clicks:
		if not rects.any(func(r): return r.has_point(c - Vector2(win.position))):
			menu.close_window()
			ss(SS_CANCEL)                                 # as Triangle: 4, then the box's 1 (PET-30)
			ss(SS_CLOSE)
			return
	var m := Vector2(DisplayServer.mouse_get_position() - win.position)
	_menu_away = 0.0 if _menu_kind == "apply" or rects.any(func(r): return r.has_point(m)) else _menu_away + delta   # the Apply window waits
	if _menu_away >= MENU_AWAY:
		menu.close_window()
		ss(SS_CLOSE)


func _menu_pick(what: String, row := -1) -> void:
	if row < 0 and what.begins_with("#"):                   # debug --pick=#N: the menu's row N (the save picker)
		row = int(what.substr(1))
	if _menu_kind == "apply":
		_apply_answer(row)
		return
	if _menu_kind == "saves":
		_pick_save(row)
		return
	match what:
		"Talk":
			var cat := "night" if PetBrain.greet_category(Time.get_datetime_dict_from_system()["hour"]) == "night" and brain.rng.randf() < 0.3 else "talk"
			var line := _forecast_line() if cat == "talk" and brain.rng.randf() < FORECAST_SHARE else ""
			_act(PetBrain.A_HAPPY, line if line != "" else brain.pick(cat))
		"Praise":                                        # one that counts (a task just done): his cheer
			ss(SS_PRAISE)
			_act(PetBrain.A_VICTORY if care.praise() else PetBrain.A_JOY, brain.pick("praise"))
		"Scold":                                         # a deserved one: DW1's head hung (FUN_800aab00);
			ss(SS_SCOLD)                                 # an unfair one: puzzled or sulky (CARE3-5)
			var deserved := care.scold()
			_act(PetBrain.A_SCOLDED_DESERVED if deserved else PetBrain.A_SCOLDED, brain.pick("scold" if deserved else "scold_unfair"))
		"Train":                                         # the ring of props (the user: "housed in the Train section")
			place.open_ring()
		"Settings":
			_open_menu(SETTINGS)
		"Back":
			_open_menu()
		"Sleep":
			ss(SS_SLEEP)
			_sleep(true)
		"Quiet", "Talk more":
			brain.quiet = not brain.quiet
			_save_config()
			_act(PetBrain.A_NOD if brain.quiet else PetBrain.A_HAPPY)
			_open_menu(SETTINGS)
		"Stay Put", "Go Explore":
			stay_put = not stay_put
			_save_config()
			_act(PetBrain.A_NOD if stay_put else PetBrain.A_HAPPY)
			_open_menu(SETTINGS)
		"Show Species", "Show Nickname":
			show_species = not show_species
			_save_config()
			_apply_name()
			_act(PetBrain.A_NOD)
			_open_menu(SETTINGS)
		"Speech:  Text", "Speech:  Mixed", "Speech:  Digi":
			speech = SPEECH[(SPEECH.find(speech) + 1) % SPEECH.size()]
			_save_config()
			_act(PetBrain.A_NOD)
			_icon(["face", 1])                               # a sample of the new mode
			_open_menu(SETTINGS)
		"Volume:  20", "Volume:  40", "Volume:  60", "Volume:  80", "Volume:  100":
			volume = VOLUMES[(VOLUMES.find(volume) + 1) % VOLUMES.size()]
			sfx.volume_db = linear_to_db(volume / 100.0)
			_save_config()
			ss(SS_PRAISE)                                    # a sample at the new level
			_open_menu(SETTINGS)
		"Sounds On", "Sounds Off":
			sounds_on = not sounds_on
			snd.enabled = sounds_on
			_save_config()
			_act(PetBrain.A_NOD)
			_open_menu(SETTINGS)
		"Gym Sounds On", "Gym Sounds Off":
			gym_sounds = not gym_sounds
			_save_config()
			_act(PetBrain.A_NOD)
			_open_menu(SETTINGS)
		"DW1 Save":
			_open_saves()
		"About":
			_open_setup(false)
		"Apply to DW1":
			_offer_apply(true)
		"Ask to Apply:  On", "Ask to Apply:  Off":          # the offer at launch and on DuckStation's close
			var ask := not bool(link.get("ask", true))           # (the way back from "No, stop asking")
			var c := CardLink.read_choice()
			if CardLink.set_flags(ask, bool(c.get("declined", false))):
				link["ask"] = ask
				care.link = link
			_act(PetBrain.A_NOD)
			if ask:
				_offer_apply()                                   # waiting gains: offered now
			if _menu_kind != "apply":
				_open_menu(SETTINGS)
		"Bye":
			_bye()


func _bye(lines := "bye") -> void:
	state = S.ACT
	_act(PetBrain.A_VICTORY, brain.pick(lines))
	state = S.BYE


## His save is loading in the game (docs/vpet_save.md): he heads in there, even from sleep.
func _game_bye() -> void:
	if state == S.BYE:
		return
	if state == S.HELD or state == S.FALL:
		_gone()
		return
	if menu.is_open():
		menu.close_window()
	_bye("game")


## Refreshed every PID_EVERY s: the game counts him as running while the file is fresh.
func _drop_pid() -> void:
	if FileAccess.get_file_as_string(VpetSave.pid_path()).strip_edges() == str(OS.get_process_id()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(VpetSave.pid_path()))


func _write_pid() -> void:
	_pid_left = PID_EVERY
	var f := FileAccess.open(VpetSave.pid_path(), FileAccess.WRITE)
	if f:
		f.store_string(str(OS.get_process_id()))
		f.close()


# ---------------------------------------------------------------- the evolution forecast
## DW1's own pick on his save + what the desktop added (EvoForecast). Called at launch and after
## each training session: a session that makes him ready is announced a few seconds later.
func _update_forecast() -> void:
	var was: String = forecast.get("state", "")
	forecast = EvoForecast.forecast(GameData, care.link, care.d)
	if was != "" and was != "ready" and forecast["state"] == "ready":
		_forecast_at = _now + FORECAST_AFTER_TRAIN


## His hint: "ready" or "close" (naming the stat furthest behind), "" without one.
func _forecast_line() -> String:
	match forecast.get("state", "none"):
		"ready":
			return brain.pick("evolve_ready")
		"close":
			return brain.pick("evolve_close").replace("%s", VpetSave.LABELS[forecast["stat"]])
	return ""


# ---------------------------------------------------------------- sleep
func _sleep(on_purpose := false) -> void:
	if state == S.HELD or state == S.FALL or state == S.SLEEP:
		return
	box.close_now()
	if menu.is_open():
		menu.close_window()
	state = S.SLEEP
	_slept_on_purpose = on_purpose
	facing = Vector3.ZERO
	_play(PetBrain.A_SLEEP)                                  # lies down; the last frame holds
	if speech != "Text":
		bubble.show_bubble(ConditionBubble.SLEEPY)


func _wake() -> void:
	_slept_on_purpose = false
	state = S.IDLE
	_act(PetBrain.A_GET_UP)
	then_line = "" if brain.quiet else brain.pick("wake")


## The user's presence: the helper's GetLastInputInfo every 2 s (keys and mouse, anywhere).
func _watch_user(delta: float) -> void:
	_idle_check -= delta
	if _idle_check > 0.0 or _idle_ms < 0:
		return
	_idle_check = 2.0
	if _idle_ms < 2500:
		_user_seen()
	else:
		_active_at = minf(_active_at, _now - _idle_ms / 1000.0)
	if _now - _active_at >= SLEEP_AFTER and state == S.IDLE:
		_sleep()


func _user_seen() -> void:
	_active_at = _now
	if state == S.SLEEP and not _slept_on_purpose:
		_wake()


var _slept_on_purpose := false


# ---------------------------------------------------------------- Claude Code's hook events
func _skip_old_events() -> void:
	var f := FileAccess.open(VpetSave.events_path(), FileAccess.READ)
	if f:
		_ev_offset = f.get_length()


func _poll_events(delta: float) -> void:
	_ev_poll -= delta
	if _ev_poll > 0.0:
		return
	_ev_poll = 0.0 if _cues else 0.5                         # cues land on the frame
	var f := FileAccess.open(VpetSave.events_path(), FileAccess.READ)
	if f == null:
		return
	if f.get_length() < _ev_offset:                          # the hook trimmed the file
		_ev_offset = 0
	if f.get_length() == _ev_offset:
		return
	f.seek(_ev_offset)
	var text := f.get_buffer(f.get_length() - _ev_offset).get_string_from_utf8()
	var end := text.rfind("\n")
	if end < 0:
		return                                               # a line still being written
	_ev_offset += text.substr(0, end + 1).to_utf8_buffer().size()
	for line in text.substr(0, end).split("\n", false):
		var ev = JSON.parse_string(line)
		if not ev is Dictionary or float(ev.get("t", 0.0)) <= _ev_last_t:
			continue
		_ev_last_t = float(ev["t"])
		if ev.get("event", "") == "game_load":                # the game loads his save
			_game_bye()
			continue
		if ev.get("event", "") == "cue":                      # debug: the trailer's script
			if _cues:
				_cue(ev)
			continue
		if ev.get("event", "") == "Stop":                     # a finished task: a praise counts now
			care.task_done()
		_react(brain.on_event(ev, _now))


## Debug (--cues): one of the trailer's cues (PetCues), through what he does on his own.
func _cue(ev: Dictionary) -> void:
	var why := PetCues.check(ev)
	print("cue %.2f %s %s" % [_now, ev.get("do", ""), why if why != "" else "ok"])
	if why != "":
		return
	match str(ev["do"]):
		"appear":                                                # cat: a greeting category, else by the hour
			holder.visible = true
			if ev.has("cat"):
				_act(PetBrain.A_HAPPY, brain.pick(str(ev["cat"])))
			else:
				_greet()
		"walk":                                                  # x: his feet's
			_walk(float(ev["x"]) - float(win.size.x) / 2.0)
		"leap":
			var spots := PetGround.reachable(windows, _feet(), _usable(), _room(), 30.0 * k, JUMP_UP * MODEL_PX * k, JUMP_SIDE * k, ground)
			var spot := PetCues.leap_spot(spots, Vector2(float(ev["x"]), float(ev["y"])), 12.0 * k)
			if spot.is_empty():
				print("cue leap: out of reach from ", _feet(), "; spots ", spots.map(func(t): return Vector2(t["x"], t["y"])))
			else:
				_jump(Vector2(float(spot["x"]), float(spot["y"])), spot["rect"])
		"read":
			_read(float(ev.get("hold", 0.0)), bool(ev.get("say", false)))
		"sleep":
			_sleep(true)
		"act":
			_act(int(ev["anim"]), brain.pick(str(ev["line"])) if ev.has("line") else "", float(ev.get("hold", 2.0)))
		"pin":
			brain.pin(str(ev["cat"]), int(ev["i"]))
		"hungry":
			care.d["live"]["hunger_at"] = care.d["live"]["clock"]
		"due":
			PetCues.due_now(care.d)
		"prop":
			place._place_beside(str(ev["name"]))
		"apply":
			_offer_apply(true)
		"about":
			_open_setup(false)
		"bye":
			_bye()


## Debug (--stage-out=file): where he, his menu and the ring's props are on the screen, 10 times a
## second, for the trailer's stage script to click (written whole, then renamed).
func _write_stage(delta: float) -> void:
	_stage_left -= delta
	if _stage_left > 0.0:
		return
	_stage_left = 0.1
	var wp := Vector2(win.position)
	var rows := []
	if menu.is_open():
		for i in _menu_items.size():
			var r := menu.row_rect(i)
			rows.append({"label": _menu_items[i], "rect": _rect_list(Rect2(r.position + layer.position + wp, r.size))})
	var props := []
	if place.ring_open:
		for i in place.ring_props.size():
			var r := place._rect_of(i)
			props.append({"name": PetProps.ORDER[i], "rect": _rect_list(Rect2(r.position + wp, r.size))})
	var f := _feet()
	var out := {"t": _now, "state": S.keys()[state], "visible": holder.visible and win.visible, "feet": [f.x, f.y],
		"window": _rect_list(Rect2(wp, Vector2(win.size))), "ground": _rect_list(ground),
		"box": box.visible and not box.done(), "menu": {"kind": _menu_kind, "open": menu.is_open(), "rows": rows},
		"ring": props, "hungry": care.hungry(), "toilet": care.needs_toilet()}
	var path := str(_args["stage-out"])
	var w := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if w:
		w.store_string(JSON.stringify(out))
		w.close()
		DirAccess.rename_absolute(path + ".tmp", path)


## Debug (--stage-out): the setup window's Start / Apply button on the screen, for the trailer's stage.
func _stage_setup(s: DScreenSetup) -> void:
	await get_tree().create_timer(0.5).timeout
	if not is_instance_valid(s):
		return
	var c := s.content_scale_factor                       # its contents are laid out at 96 dpi and scaled
	var g: Rect2 = s._start.get_global_rect()
	var r := Rect2(g.position * c, g.size * c)
	var w := FileAccess.open(str(_args["stage-out"]) + ".tmp", FileAccess.WRITE)
	if w:
		w.store_string(JSON.stringify({"state": "SETUP", "setup": {"start": _rect_list(Rect2(r.position + Vector2(s.position), r.size)),
			"window": _rect_list(Rect2(Vector2(s.position), Vector2(s.size)))}}))
		w.close()
		DirAccess.rename_absolute(str(_args["stage-out"]) + ".tmp", str(_args["stage-out"]))


static func _rect_list(r: Rect2) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]


func _react(r: Dictionary) -> void:
	if r.is_empty():
		return
	var line: String = brain.pick(r["line"]) if r.has("line") else ""
	if state == S.SLEEP:
		if not r.get("urgent", false):
			return
		state = S.IDLE
	if state == S.HELD or state == S.FALL or state == S.BYE or state == S.USE:
		if line != "":
			_say(line)
		return
	if menu.is_open():
		menu.close_window()
	_act(int(r.get("anim", PetBrain.A_HAPPY)), line, 2.5)


# ---------------------------------------------------------------- care (docs/vpet_save.md)
## His clock runs while he's awake and you're at the PC (input in the last SLEEP_AFTER s).
func _tick_care(delta: float) -> void:
	# without the helper (no idle times) he can't tell you're there: treated as away (PET-22)
	var active := state != S.SLEEP and state != S.BYE and _idle_ms >= 0 and _now - _active_at < SLEEP_AFTER
	var f := _feet()
	var u := _usable()
	var beside := (body_w * 0.55 + 20.0) * k                 # an accident's pile: beside him, where it shows
	var px := f.x - beside if f.x - beside > u.position.x + 20.0 else f.x + beside
	for ev in care.tick(delta if active else 0.0, _now, px, f.y):
		_care_event(ev)
	if not active:
		return
	# asks again: food every ASK_EVERY, 3 asks in all; the toilet as soon as he's free (never cutting
	# a clip such as an accident's squat, nor lost to a toilet session: CARE3-2/3), once more halfway
	if care.hungry() and _asks_left > 0 and _now >= _ask_at and can_use():
		_ask("hungry", PetBrain.A_HUNGRY)
	if care.needs_toilet() and _toilet_asks_left > 0 and _now >= _toilet_ask_at and state in [S.IDLE, S.WALK]:
		_ask("toilet", PetBrain.A_TOILET)


func _care_event(ev: String) -> void:
	match ev:
		Vpet.HUNGRY:
			_asks_left = 3
			_ask_at = _now
		Vpet.NEEDS_TOILET:
			_toilet_asks_left = 2
			_toilet_ask_at = _now
		Vpet.ACCIDENT:
			place.add_pile(care.piles()[-1])
			_toilet_asks_left = 0
			if can_use():
				_act(PetPlace.A_SQUAT, brain.pick("accident"), 2.0)
		Vpet.PILE_LEFT:
			if can_use():
				_act(PetBrain.A_UNHAPPY, brain.pick("pile_left"))
		Vpet.MISSED:
			if can_use():
				_act(PetBrain.A_UNHAPPY, brain.pick("missed"))


func _ask(line: String, anim: int) -> void:
	if menu.is_open() or place.ring_open or not can_use():
		return                                               # asks again once you're done
	if line == "hungry":
		_asks_left -= 1
		_ask_at = _now + ASK_EVERY
	elif line == "toilet":
		_toilet_asks_left -= 1
		_toilet_ask_at = _now + Vpet.toilet_window(Vpet.discipline(care.d, link)) / 2.0
	_act(anim, brain.pick(line), 3.0)


## Free to go to a prop or take the Meat: standing, walking or playing a clip.
func can_use() -> bool:
	return state in [S.IDLE, S.WALK, S.ACT]


func start_use() -> void:
	if menu.is_open():
		menu.close_window()
	state = S.USE
	_hold_pose = false


## The session is over: the last clip plays out, then he idles.
func end_use() -> void:
	state = S.ACT
	act_left = 2.5


# ---------------------------------------------------------------- text
## always: the app's own words (the Apply window's gains, card notices) show in the box in every
## Speech mode; in Digi the Apply window had only Yes / No, no gains (9d 7).
func _say(text: String, always := false) -> void:
	if text == "":
		return
	var icon: Array = SPEECH_ICON.get(brain.category_of(text), [])
	if speech != "Text" and not icon.is_empty() and not always:
		_icon(icon)
	if speech == "Digi" and not always:                      # only DW1's icons
		return
	if not box.visible:
		ss(SS_OPEN)                                          # a box with a speaker zooms open with SS 0
	box.set_page(pet_name, 7, text)                          # an NPC's name colour (FUN_80101688)
	var head := _dw(Vector2(_body_x(), _floor_y() - (FEET + top_px * 0.9) * k))
	box.open_text(Rect2(head, Vector2(8, 8)))
	box_left = 3.5 + 0.05 * text.length()


## Shows a SPEECH_ICON entry over him.
func _icon(icon: Array) -> void:
	if speech == "Text":
		return
	match str(icon[0]):
		"b":
			bubble.show_bubble(int(icon[1]))
		"fly":
			bubble.show_butterfly(ICON_HOLD)
		"face":
			bubble.show_face(int(icon[1]), ICON_HOLD)


## Window pixels -> DW1 coordinates of the text layer.
func _dw(p: Vector2) -> Vector2:
	return (p - layer.position - layer.size / 2.0) / (TEXT_SCALE * k)


## Near a screen edge his window stays on the screen and he is drawn off its centre (_view_x), so
## the text box, nearly as wide as the window, isn't cut off by the window's own edge.
func _place_window() -> void:
	var w := float(win.size.x)
	var at := pos + _ride
	_view_x = PetGround.view_offset(at.x, w, _screen_rect(), w)    # dragged past the edge: he leaves it, the box doesn't
	_view_y = PetGround.menu_drop(at.y, float(win.size.y), _usable().position.y, (FEET + top_px * 1.15) * k) if menu.visible else 0.0
	win.position = Vector2i(Vector2(at.x + _view_x, at.y + _view_y).round())
	cam.h_offset = _view_x / _px_per_m
	cam.v_offset = -_view_y / _px_per_m


## His feet's x in window pixels.
func _body_x() -> float:
	return float(win.size.x) / 2.0 - _view_x


## The ground line under him in window pixels (his feet are FEET above it): the window's bottom,
## higher while the menu holds his window down (_view_y).
func _floor_y() -> float:
	return float(win.size.y) - _view_y


## High on a window, the text layer slides down so the box stays on the desktop. Never sideways:
## the window is always on the screen, and a sideways slide pushed the box past its edge.
func _keep_text_on_screen() -> void:
	var u := _screen_rect()
	var s := TEXT_SCALE * k
	var by := float(win.position.y) + _layer_y + (120.0 + DwTextBox.RECT.position.y) * s   # high on a window: slide down
	layer.position.y = _layer_y + maxf(0.0, u.position.y - by)


# ---------------------------------------------------------------- the desktop
func _screen() -> int:
	var c := Vector2i(pos + Vector2(win.size) / 2.0)
	for i in DisplayServer.get_screen_count():
		if Rect2i(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i)).has_point(c):
			return i
	return DisplayServer.get_primary_screen()


func _usable() -> Rect2:
	return _usable_of(_screen())


## Screen i's usable rect, its bottom on the taskbar's top when that is higher (an auto-hidden
## taskbar slid up: Windows counts the whole screen as usable then).
func _usable_of(i: int) -> Rect2:
	var s := Rect2(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i))
	return PetGround.floor_rect(Rect2(DisplayServer.screen_get_usable_rect(i)), s, taskbars)


## The floor (the taskbar's top or the usable bottom) of the screen under desktop x.
func floor_at(x: float) -> float:
	for i in DisplayServer.get_screen_count():
		var s := Rect2(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i))
		if x >= s.position.x and x < s.end.x:
			return _usable_of(i).end.y
	return _usable().end.y


func _screen_rect() -> Rect2:
	var i := _screen()
	return Rect2(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i))


## His feet on the desktop (the window's bottom centre, FEET above it).
func _feet() -> Vector2:
	return Vector2(pos.x + float(win.size.x) / 2.0, pos.y + float(win.size.y) - FEET * k)


func _set_feet_y(y: float) -> void:
	pos.y = y - float(win.size.y) + FEET * k


## Headroom a window top needs below the screen's top for him to stand on it.
func _room() -> float:
	return top_px * 1.1 * k


## Standing: on the taskbar he stays on it; on a window he rides along when it moves and falls
## when it closes, is covered, or he walks off its end.
func _check_ground() -> void:
	if ground.size == Vector2.ZERO:
		var y0 := pos.y
		_set_feet_y(_usable().end.y)
		if absf(pos.y - y0) < 400.0 * k:                    # the taskbar rose or fell: he slides with it
			_ride.y += y0 - pos.y
		return
	if not PetGround.stands_on(windows, ground, _feet().x, _usable(), _room(), 20.0 * k):
		var vx := walk_dir * _walk_speed() if state == S.WALK else 0.0
		var was_bye := state == S.BYE
		# his window went (closed, minimized): he drops at once; from rest he crept ~13 px in the
		# first 0.1 s and looked late (9d 12). Walking off its end still starts from rest.
		_fall(vx, 0.0 if windows.has(ground) else GONE_FALL_V * k)
		if was_bye:
			_gone()


func _walk_speed() -> float:
	# DW1's walk root motion (motion.json, units per frame at 20 fps) scaled to the screen
	var px_per_unit := model_px * k / (DigimonModel.dw1_height(type) / 0.005)
	return float(DigimonModel.dw1_anim(type, PetBrain.A_WALK).get("speed", 20.0)) * 20.0 * px_per_unit


# ---------------------------------------------------------------- D-Screen: DW1 on the card
## The helper's read-only DuckStation watch (pet/pet_duck.cs), finding DW1's RAM by the disc's own
## EXE bytes.
func _start_duck() -> void:
	if _feed.is_empty() or Dw1Model.exe == null:
		_duck = 1 if CardLink.duckstation_running() else 0       # no watch: tasklist once
		return
	var io: FileAccess = _feed["stdio"]
	io.store_line("duck %s %X %s" % [Dw1Model.exe.bytes(RAM_PATTERN, 32).hex_encode(), RAM_PATTERN & 0x1FFFFF,
		str(_args.get("duck-name", "duckstation"))])      # debug: --duck-name=another process (a test stand-in)


## DuckStation opened or closed ("d"), DW1's slot and map in its RAM ("m"): his own save loaded
## sends him into the game; another save's maps get his place comments (pet/lines/places.json).
func _duck_feed(dl: String, ml: String) -> void:
	if dl != "":
		var was := _duck
		_duck = int(dl.substr(2))
		if was > 0 and _duck == 0:                       # DuckStation closed
			var now_link := CardLink.link(GameData) if not link.is_empty() else {}
			if _away:
				print("pet: DuckStation closed: back from DW1")
				_quit(true)                              # back as the save left him
			elif not now_link.is_empty() and (str(now_link["partner_uid"]) != str(link["partner_uid"])
					or int(now_link["partner_id"]) != int(link["partner_id"])):
				_quit(true)                              # his save changed partner without him (CARD-5)
			elif CardLink.save_moved(link, now_link):    # only when his save was played (9d 5)
				_offer_apply()
	if ml == "":
		return
	var before := _ram
	_ram = CardLink.parse_ram(ml)
	if _ram.is_empty() or _away:
		return
	if CardLink.his_save(link, _ram):
		print("pet: his save is being played: into DW1")
		_away = true
		if CardLink.session_behind(link, _ram):          # a resumed state from before the gains (CARD-2)
			if menu.is_open():
				menu.close_window()
			_bye("game")
			_say("This game is from\nbefore my training!\nLoad from the title.", true)
			return
		_game_bye()
	elif Dw1Model.exe and CardLink.save_loaded(_ram, Dw1Model.exe.bytes(Dw1Exe.DIGIMON_TABLE, 20).hex_encode()) \
			and (before.is_empty() or int(before["screen"]) != int(_ram["screen"])):
		var area := Dw1Model.exe.area_name(int(_ram["screen"]))
		if area != "":
			_react(brain.on_event({"event": "map", "map": int(_ram["screen"]), "area": area}, _now))


## The Apply window (docs/memcard_bridge.md section 15.2): what desktop care adds beyond the save's
## record, offered while DuckStation is closed; force: asked from Settings (also after "stop asking").
func _offer_apply(force := false) -> void:
	if not _card or link.is_empty() or _away:
		return
	if _duck > 0 or CardLink.duckstation_running():
		if force:
			_say("Close DuckStation\nfirst, then I can\nbring it in!", true)
		return
	care.flush(_now, true)
	var fresh := CardLink.link(GameData)
	if fresh.is_empty() or str(fresh["partner_uid"]) != str(link["partner_uid"]):
		if force:
			_say("I can't find my\nsave on the card...", true)
		return
	link = fresh
	care.link = link
	var m := CardLink.pending(link, VpetSave.read_pet(int(link["slot"])))
	if m["state"] != "pending":
		if force:
			_say("Nothing new to\nbring in yet!", true)
		return
	if not force and not bool(link.get("ask", true)):
		return
	_apply_m = m
	_apply_pages = CardLink.apply_pages(m["deltas"], APPLY_ROW).map(func(p: Array) -> String:
		return CardLink.apply_header(link) + "\n" + "\n".join(p))
	_apply_page = 0
	_say(_apply_pages[0], true)
	box_left = 600.0                                     # stays up while the window waits
	_open_menu(APPLY, "apply")
	if _apply_pages.size() > 1:
		get_tree().create_timer(APPLY_PAGE).timeout.connect(_turn_apply_page)
	if _args.has("apply"):                               # debug: --apply=Yes / No / "No, stop asking"
		get_tree().create_timer(1.5).timeout.connect(_debug_apply)


## More gains than a page: the box turns to the next page every APPLY_PAGE s while the window waits.
func _turn_apply_page() -> void:
	if _menu_kind != "apply" or not menu.is_open() or _apply_m.is_empty():
		return
	_apply_page = (_apply_page + 1) % _apply_pages.size()
	box.set_page(pet_name, 7, _apply_pages[_apply_page])
	box.queue_redraw()
	get_tree().create_timer(APPLY_PAGE).timeout.connect(_turn_apply_page)


func _debug_apply() -> void:
	if menu.is_open() and _menu_kind == "apply":
		menu.close_window()
		_apply_answer(APPLY.find(str(_args["apply"])))


## Yes: written into the save (CardLink.apply: DuckStation closed, backup, both copies, read back);
## No: kept, desktop training on hold until it's applied; No, stop asking: no more offers (Settings'
## "Apply to DW1" still offers it). The remake's three answers (main._vpet_offer).
func _apply_answer(row: int) -> void:
	box.close_now()
	if _apply_m.is_empty():
		return
	var shown: Dictionary = _apply_m["deltas"]
	_apply_m = {}
	if row == 0:
		var r := CardLink.apply(GameData, Callable(), shown)
		if r["error"] == "changed":                      # he trained on while the window waited: ask again
			_offer_apply(true)
			return
		if r["ok"]:
			link = CardLink.link(GameData)
			care.link = link
			_act(PetBrain.A_JOY)
			_say("All set!  It's in\nyour DW1 save.", true)
		else:
			push_warning("pet: the card: " + str(r["error"]))
			_act(PetBrain.A_UNHAPPY)
			_say("I couldn't write\nthe card...", true)
		return
	CardLink.set_flags(row != 2, true)
	link["ask"] = row != 2
	link["declined"] = true
	care.link = link
	_act(PetBrain.A_NOD)


## The save picker: DW1's saves on DuckStation's cards; the one picked becomes his (he starts again
## as that save's partner).
func _open_saves() -> void:
	_picker = CardLink.entries([], GameData.digimon.map(func(e): return str(e["name"]))).filter(
		func(e): return int(e["copy"]) >= 0)
	var labels := []
	for e in _picker:
		var dec: Dictionary = e["partner"]
		var id := int(dec["type"])
		var sp := str(GameData.digimon[id]["name"]) if id >= 0 and id < GameData.digimon.size() else "?"
		labels.append("%d %s - %s" % [int(e["slot"]) + 1, dec["name"], sp])   # DW1's font has no ( ): they drew as △
	if labels.is_empty():
		_say("I can't find any\nDW1 saves on your\nmemory cards.")
		return
	labels.append("Back")
	_open_menu(labels, "saves")


func _pick_save(row: int) -> void:
	if row < 0 or row >= _picker.size():
		_open_menu(SETTINGS)
		return
	var e: Dictionary = _picker[row]
	var c := CardLink.read_choice()
	if not c.is_empty() and str(c["card"]) == str(e["card"]) and int(c["slot"]) == int(e["slot"]):
		_act(PetBrain.A_NOD)
		return
	# his gains waiting: the Apply window asks about them first, then the switch (the user's call,
	# 9d 8); with DuckStation running the card can't be written, so he switches and they wait
	_switch_ask = bool(link.get("ask", true))               # as it was before the window's answer
	if not link.is_empty() and not _away and _duck <= 0 and not CardLink.duckstation_running() \
			and CardLink.pending(link, VpetSave.read_pet(int(link["slot"])))["state"] == "pending":
		_switch_to = e
		_switch_at = _now + SWITCH_AFTER
		_offer_apply(true)
		if _apply_up():
			print("pet: switching to save %d after the Apply window" % (int(e["slot"]) + 1))
			return                                           # _tick_switch switches once it's answered
		_switch_to = {}
	_switch(e)


## The picked save becomes his: he starts again as its partner. "Ask to Apply" stays as it was (it
## was reset on every switch, 9d 8); the hold after a No is the old partner's and doesn't follow.
func _switch(e: Dictionary) -> void:
	print("pet: switching to save %d (%s)" % [int(e["slot"]) + 1, str(e["card"]).get_file()])
	if CardLink.write_choice(str(e["card"]), int(e["slot"]), _switch_ask):
		_quit(true)


## The Apply window is up: opening (it zooms in over a few frames, not yet is_open) or open.
func _apply_up() -> bool:
	return _menu_kind == "apply" and menu.visible and menu.phase <= 1


## A switch waiting on the Apply window: SWITCH_AFTER s after it closes (answered or not), so its
## "All set!" is seen first.
func _tick_switch() -> void:
	if _switch_to.is_empty():
		return
	if _apply_up():
		_switch_at = _now + SWITCH_AFTER
	elif _now >= _switch_at:
		var e := _switch_to
		_switch_to = {}
		_switch(e)


# ---------------------------------------------------------------- the window feed
## Starts the helper (pet/pet_helper.cs), built first by WinHelper when it's missing or its
## source changed.
func _start_feed() -> void:
	var exe := WinHelper.exe()
	if exe.is_empty():
		push_warning("pet: " + WinHelper.error)
		return
	_feed = OS.execute_with_pipe(exe, [str(OS.get_process_id())])
	if _feed.is_empty():
		return
	_feed_thread = Thread.new()
	_feed_thread.start(_read_feed)


func _read_feed() -> void:
	var io: FileAccess = _feed["stdio"]
	while io.is_open():
		var line := io.get_line()
		if io.get_error() != OK:
			break
		_feed_mutex.lock()
		if line.begins_with("w "):
			_feed_w = line                                   # whole: a bare "w " is an empty list, not none
		elif line.begins_with("t "):
			_feed_t = line
		elif line.begins_with("i "):
			_feed_i = int(line.substr(2))
		elif line.begins_with("d "):
			_feed_d = line
		elif line.begins_with("m "):
			_feed_m = line
		elif line.begins_with("c "):
			var n := line.split(" ")
			if n.size() == 3:
				_feed_c.append(Vector2(float(n[1]), float(n[2])))
		_feed_mutex.unlock()


func _take_feed(delta: float) -> void:
	_feed_mutex.lock()
	var line := _feed_w
	_feed_w = ""
	var bars := _feed_t
	_feed_t = ""
	var clicks := _feed_c.duplicate()
	_feed_c.clear()
	_clicks = clicks
	if _feed_i >= 0:
		_idle_ms = _feed_i
		_feed_i = -1
	var duck := _feed_d
	_feed_d = ""
	var ram := _feed_m
	_feed_m = ""
	_feed_mutex.unlock()
	if duck != "" or ram != "":
		_duck_feed(duck, ram)
	if _offer_at > 0.0 and _now >= _offer_at and _duck >= 0 and can_use():
		_offer_at = 0.0
		_offer_apply()
	_tick_menu(delta, clicks)
	var new_bars = PetGround.feed_rects(bars)
	if new_bars != null:
		taskbars = new_bars
	var new_windows = PetGround.feed_rects(line)
	if new_windows == null:
		return
	var top: Rect2 = windows[0] if not windows.is_empty() else Rect2()
	windows = new_windows
	# the front window changed (opened, focused, moved): he glances at it if it's on his screen
	if not windows.is_empty() and not (windows[0] as Rect2).is_equal_approx(top) \
			and _screen_rect().intersects(windows[0]):
		_look_win = windows[0]
		_look_win_until = _now + 2.0
	if ground.size != Vector2.ZERO and state != S.FALL and state != S.HELD:
		var now := PetGround.follow(windows, ground)
		if now.size != Vector2.ZERO:
			pos += now.position - ground.position              # ride along
			_ride -= now.position - ground.position             # his window slides there (PetGround.ease_ride)
			walk_to += now.position.x - ground.position.x
			ground = now


## "L T R B;L T R B;..." from the helper as rects.
static func _rects(line: String) -> Array:
	return PetGround.rects(line)


func _clamp_x() -> void:
	var u := _usable()
	var half := float(win.size.x) / 2.0
	var m := body_w * 0.53 * k                               # his whole body on the screen
	pos.x = clampf(pos.x, u.position.x - half + m, u.end.x - half - m)


func _place_on_floor(first := false) -> void:
	var u := _usable_of(DisplayServer.get_primary_screen())
	if first and pos.x < 0.0:
		pos.x = u.end.x - float(win.size.x) / 2.0 - 260.0 * k
	ground = Rect2()
	_ride = Vector2.ZERO
	_set_feet_y(u.end.y)
	_clamp_x()
	_place_window()


## Clicks land only on him, the text box and the menu; everywhere else they reach the desktop.
## The whole window turns click-through while the cursor is elsewhere (_click_through). A
## passthrough polygon (SetWindowRgn) clips the drawing to the region, flickered when reset every
## frame and framed Forward+'s tint as a box (the user, 2026-10-18).
func _update_passthrough() -> void:
	var inside := state == S.HELD or _press or place.drag != null
	if not inside:
		var m := Vector2(DisplayServer.mouse_get_position() - win.position)
		var rects := _hit_rects()
		for i in rects.size():
			if rects[i].has_point(m) and (i > 0 or _on_body(m)):
				inside = true
				break
	_click_through(not inside)


## Inside the body's rect, the cursor is on him only over his own pixels (a few px of slack): the
## rect is twice his farthest reach and was taking clicks beside him (the user, 2026-10-18). His
## frame is read back from the GPU at most every HIT_EVERY s, and only while the cursor is there.
func _on_body(m: Vector2) -> bool:
	if _hit_img == null or _now - _hit_img_at >= HIT_EVERY:
		_hit_img = win.get_texture().get_image()
		_hit_img_at = _now
	if _hit_img == null or _hit_img.is_empty():
		return true
	return PetGround.opaque_near(_hit_img, Vector2i(m.round()), int(HIT_SLACK * k))


var _through := -1                   # -1 unknown, 0 takes clicks, 1 click-through


## The helper (pet/pet_helper.cs) sets WS_EX_TRANSPARENT on his window: a real click-through.
func _click_through(on: bool) -> void:
	if _feed.is_empty() or _through == int(on):
		return
	_through = int(on)
	var hwnd := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, win.get_window_id())
	var io: FileAccess = _feed["stdio"]
	io.store_line("pass %d %d" % [hwnd, int(on)])
	io.flush()


## The window he stands on, for the helper to watch every 15 ms (pet/pet_helper.cs "ride"): one
## moved by its own program follows as quickly as a dragged one.
func _tell_ride() -> void:
	if _feed.is_empty() or ground == _ride_told:
		return
	_ride_told = ground
	var io: FileAccess = _feed["stdio"]
	if ground.size == Vector2.ZERO:
		io.store_line("ride")
	else:
		io.store_line("ride %d %d %d %d" % [ground.position.x, ground.position.y, ground.end.x, ground.end.y])
	io.flush()


## Over his props' and piles' windows (pet/pet_helper.cs "top").
func raise_window() -> void:
	if _feed.is_empty():
		return
	var hwnd := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, win.get_window_id())
	var io: FileAccess = _feed["stdio"]
	io.store_line("top %d" % hwnd)
	io.flush()


## Where he takes clicks, in window pixels: his body, the text box, the menu.
func _hit_rects() -> Array[Rect2]:
	var x := _body_x()
	var h := _floor_y()
	var bw := body_w * k
	var out: Array[Rect2] = [Rect2(x - bw / 2.0, h - (FEET + top_px * 1.12) * k, bw, (FEET + top_px * 1.12) * k)]
	if state == S.SLEEP:                                     # lying down, or a baby asleep in the air
		out[0] = PetGround.sleep_rect(x, h, body_w, model_px, top_px, FEET, k)
	if box.visible and not box.done():
		out.append(_in_window(box.pixel_rect()).grow(4 * k))
	if menu.visible:
		out.append(_in_window(menu.pixel_rect()).grow(4 * k))
	out.append_array(place.hit_rects())
	return out


## His width for the click area, from the drawn frame: the columns his idle pose covers (alpha)
## below the text box, both sides of his centre alike. Models differ too much (TS T-poses, Next
## Order units, long serpents) for their meshes' bounds to say it.
func _measure_body() -> void:
	bubble.visible = false                                   # only he counts
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	bubble.visible = true
	if state != S.IDLE or not holder.visible or _view_y != 0.0:   # (--hidden: once he appears; not drawn up high for the menu)
		_measured = false                                    # try again at the next idle
		return
	var img := win.get_texture().get_image()
	var h := img.get_height()
	var cx := int(_body_x())
	var reach := 0
	var top := h
	var from := maxi(0, h - int((FEET + top_px * 1.15) * k))
	for y in range(from, h, 2):
		for x in range(0, img.get_width(), 2):
			if img.get_pixel(x, y).a > 0.1:
				reach = maxi(reach, absi(x - cx))
				if absi(x - cx) < model_px * 0.5 * k:
					top = mini(top, y)
	if reach > 0:
		body_w = clampf(2.0 * reach / k, model_px * 0.4, model_px * 2.5)
	if top > from and top < h:                               # his head in the idle pose (the bubbles' anchor)
		head_px = (h - top) / k - FEET


# ---------------------------------------------------------------- tray icon, screenshots, quit
## A tray icon (Godot's status indicator) with his face: left click calls him back to the
## primary screen, right click quits.
func _make_tray() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR):
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := win.get_texture().get_image()
	var h := float(win.size.y)
	var side := int(model_px * 0.62 * k)
	var face := Rect2i(int(_body_x() - side / 2.0), int(h - (FEET + top_px * 0.95) * k), side, side)
	img = img.get_region(face)
	img.resize(32, 32, Image.INTERPOLATE_LANCZOS)
	_tray = DisplayServer.create_status_indicator(ImageTexture.create_from_image(img), _tray_tip(), _on_tray)


func _on_tray(button: int, _at: Vector2i) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		_bye()
		return
	if state == S.SLEEP:
		_wake()
	if state == S.USE:
		place.cancel()
	state = S.IDLE
	_place_on_floor()
	pos.x = Rect2(DisplayServer.screen_get_usable_rect(DisplayServer.get_primary_screen())).get_center().x - float(win.size.x) / 2.0
	_act(PetBrain.A_HAPPY, brain.pick("greet"))


func _shot(path: String, after: float) -> void:
	await get_tree().create_timer(after).timeout

	print("window ", win.position, " ", win.size, " ", pet_name, " ", model_px, " x ", body_w, " px, moves ", brain.train)
	if _args.has("probe"):                                   # debug: would a click at window x,y reach him?
		var xy := String(_args["probe"]).split(",")
		var m := Vector2(float(xy[0]), float(xy[1]))
		print("probe ", m, " state ", S.keys()[state], " body box ", _hit_rects()[0], " in box ", _hit_rects()[0].has_point(m),
			" on his pixels ", _on_body(m), " click-through now ", _through)
	if place.ring_open:
		print("ring: ", range(place.ring_props.size()).map(func(i): return place._screen_of(i).round()))
	else:
		print("ring closed")
	await RenderingServer.frame_post_draw
	win.get_texture().get_image().save_png(path)
	print("saved ", path)
	var uw = place.placed if place.placed != null and is_instance_valid(place.placed) else place.use.get("win")
	if uw != null and is_instance_valid(uw):                 # and a waiting or in-use prop's window
		uw.get_texture().get_image().save_png(path.get_basename() + "_prop.png")
		print("prop at ", uw.position, " ", uw.size)
	for id in place.piles:                                   # and each pile's own window
		var pw: Window = place.piles[id]
		pw.get_texture().get_image().save_png(path.get_basename() + "_pile%d.png" % id)
		print("pile ", id, " at ", pw.position, " ", pw.size)
	if _args.has("quit"):
		_quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if care != null:
			_quit()
		else:                                            # the setup window's app (Restart Manager, Close)
			_drop_pid()
			get_tree().quit()


## Off after Bye, or into the game: D-Screen keeps running hidden while DW1 plays his save (the
## helper watches DuckStation) and starts again when it closes, so he comes back as the save left him.
func _gone() -> void:
	if not _away:
		_quit()
		return
	care.flush(_now, true)
	place.close_ring()
	box.close_now()
	win.hide()


func _quit(restart := false) -> void:
	_save_config()
	care.flush(_now, true)                                   # his last write, before the pid goes
	_drop_pid()
	if not _feed.is_empty():
		OS.kill(int(_feed["pid"]))
		(_feed["stdio"] as FileAccess).close()
	if _feed_thread != null:
		_feed_thread.wait_to_finish()
	if _tray >= 0:
		DisplayServer.delete_status_indicator(_tray)
	if restart:                                              # after his pid file went: the new one runs
		OS.create_instance(_restart_args())
	get_tree().quit()


func _in_window(r: Rect2) -> Rect2:
	return Rect2(r.position + layer.position, r.size)
