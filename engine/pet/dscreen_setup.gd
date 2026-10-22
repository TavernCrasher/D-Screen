class_name DScreenSetup
extends Window
## D-Screen's setup window (docs/shareable_pet_plan.md step 8): the fan-project notice, the disc
## image (found in DuckStation's game list or picked, then checked) and his save on DuckStation's
## memory cards. Shown at the first run and whenever the disc can't be read; Settings' About opens
## it again. Drawn in Godot's own font in a DW1-blue box: DW1's font and frames come from the disc,
## which may not be there yet.

signal finished(changed: bool)       # Start / Apply (changed: disc or save differ) or Quit / Close

const NOTICE := "D-Screen is an unofficial fan project, not affiliated with or endorsed by Bandai Namco or Toei Animation. Digimon is their trademark. No game data is included: it reads your own copy of Digimon World 1."
## The bridge's real promise (DS8-3, docs/memcard_bridge.md section 16): a state resumed from before an
## apply only undoes it once DW1 saves over it, and the gains are then offered again; never applied twice.
const STATES := "If you resume a DuckStation save state made before the desktop gains were applied and then save in DW1, the old save is written back. The gains are offered again later; they're never applied twice."
const FILTERS := ["*.cue, *.chd, *.iso, *.bin, *.img, *.m3u ; Digimon World disc image"]
const BLUE := Color8(16, 24, 72)
const FRAME := Color8(170, 180, 220)
const SIZE := Vector2i(600, 600)

var first := true                    # the first run (Start / Quit) or About (Apply / Close)
var disc_path := ""                  # the image as checked ("" none)
var disc_ok := false
var names: Array = []                # species by id, from the checked disc's EXE
var saves: Array = []                # CardLink.entries with a good copy
var _kept := -1                      # the row of a chosen save that can't be read now (kept as it is)
var _asked := ""                     # the image pet.cfg named, when it's gone (DS8-13)
var _status: Label
var _list: ItemList
var _start: Button
var _was := {}                       # the disc and the save at opening, for `changed`


## first_: the first run (else About); disc_: the image pet.cfg names ("" none); k: the screen's
## dpi scale. Builds the window; add it to the tree.
func setup(first_: bool, disc_: String, k: float) -> void:
	first = first_
	title = "D-Screen" if first else "About D-Screen"
	borderless = false
	transient = false
	exclusive = false
	unresizable = true
	wrap_controls = false
	content_scale_factor = k
	size = Vector2i(Vector2(SIZE) * k)
	close_requested.connect(_quit)
	_build()
	_check(disc_)
	var c := CardLink.read_choice()
	_was = {"disc": disc_path, "card": str(c.get("card", "")), "slot": int(c.get("slot", -1))}


func _ready() -> void:
	var r := DisplayServer.screen_get_usable_rect(DisplayServer.get_primary_screen())
	position = r.position + (r.size - size) / 2


func _build() -> void:
	var th := Theme.new()
	var box := StyleBoxFlat.new()
	box.bg_color = BLUE
	box.border_color = FRAME
	box.set_border_width_all(2)
	box.set_corner_radius_all(3)
	box.set_content_margin_all(14)
	th.set_stylebox("panel", "PanelContainer", box)
	var inner := box.duplicate() as StyleBoxFlat
	inner.bg_color = BLUE.lightened(0.08)
	inner.set_border_width_all(1)
	inner.set_content_margin_all(8)
	th.set_stylebox("panel", "ItemList", inner)
	th.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	for s in ["normal", "hover", "pressed", "disabled", "focus"]:
		var b := inner.duplicate() as StyleBoxFlat
		b.set_content_margin_all(6)
		b.content_margin_left = 16
		b.content_margin_right = 16
		b.bg_color = {"hover": BLUE.lightened(0.25), "pressed": BLUE.lightened(0.35), "disabled": BLUE}.get(s, BLUE.lightened(0.15))
		if s == "focus":
			b.draw_center = false
		th.set_stylebox(s, "Button", b)
	th.set_color("font_color", "Label", Color.WHITE)
	th.set_color("font_color", "ItemList", Color.WHITE)
	th.set_color("font_selected_color", "ItemList", Color8(255, 230, 120))
	th.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	var sel := StyleBoxFlat.new()
	sel.bg_color = BLUE.lightened(0.3)
	th.set_stylebox("selected", "ItemList", sel)
	th.set_stylebox("selected_focus", "ItemList", sel)
	theme = th
	var bg := ColorRect.new()
	bg.color = BLUE.darkened(0.4)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [SIDE_LEFT, SIDE_TOP]:
		panel.set_offset(side, 10)
	for side in [SIDE_RIGHT, SIDE_BOTTOM]:
		panel.set_offset(side, -10)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var head := Label.new()
	head.text = "D-Screen"
	head.add_theme_font_size_override("font_size", 26)
	v.add_child(head)                                   # the name alone (the user, 9d 18: no tagline naming the game)
	v.add_child(_text(NOTICE, 13, Color8(255, 230, 120)))
	v.add_child(_text("Your Digimon World (USA) disc image", 16))
	var row := HBoxContainer.new()
	_status = _text("", 13)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_status)
	var pick := Button.new()
	pick.text = "Choose..."
	pick.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pick.pressed.connect(_choose)
	row.add_child(pick)
	v.add_child(row)
	v.add_child(_text("Your partner: a DW1 save on DuckStation's memory cards", 16))
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size.y = 90
	v.add_child(_list)
	v.add_child(_text(STATES, 12, Color8(200, 205, 235)))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	_start = Button.new()
	_start.text = "Start" if first else "Apply"
	_start.pressed.connect(_done)
	buttons.add_child(_start)
	var quit := Button.new()
	quit.text = "Quit" if first else "Close"
	quit.pressed.connect(_quit)
	buttons.add_child(quit)
	v.add_child(buttons)


func _text(s: String, px: int, colour := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = s
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 100
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", colour)
	return l


## Checks an image (Dw1Disc and Dw1Exe, as the pet opens it); "" looks in DuckStation's game list.
func _check(path: String) -> void:
	var how := "Picked"
	if path == "" or not FileAccess.file_exists(path):
		if path != "":
			_asked = path
		path = Dw1Disc.find_dw1()
		how = "Found in DuckStation's game list"
	if _asked != "" and path != _asked:
		how = "%s isn't there any more.
%s" % [_asked, how]
	var why := check(path)
	disc_ok = why == ""
	disc_path = path if disc_ok else ""
	if disc_ok:
		_status.text = "%s:\n%s" % [how, path]
	elif path == "":
		_status.text = ("%s isn't there any more, and DW1 isn't" % _asked if _asked != "" else "Not found") + 			" in DuckStation's game list. Choose your disc image (.cue, .chd, .iso or .m3u)."
	else:
		_status.text = "%s\n%s" % [path, why]
	_status.add_theme_color_override("font_color", Color.WHITE if disc_ok else Color8(255, 150, 140))
	_fill_saves()


## Why the image at path can't be D-Screen's disc ("" when it can); names takes its species.
func check(path: String) -> String:
	if path == "":
		return "no image"
	var d := Dw1Disc.open_checked(path)
	if d == null or d.error != "":
		return "Can't read it: %s" % (d.error if d else "unknown")
	if not d.is_dw1_usa():
		return "That isn't Digimon World (USA), SLUS-01032. Other regions aren't supported."
	var x := Dw1Exe.from_disc_checked(d)
	if x.error != "":
		return "The disc's game program doesn't look right: %s" % x.error
	names = x.digimon().map(func(e): return str(e["name"]))
	return ""


func _fill_saves() -> void:
	_list.clear()
	saves = []
	_kept = -1
	if not disc_ok:
		_list.add_item("(the disc first)", null, false)
		_start.disabled = true
		return
	_start.disabled = false
	saves = CardLink.entries([], names).filter(func(e): return int(e["copy"]) >= 0)
	var c := CardLink.read_choice()
	for e in saves:
		var dec: Dictionary = e["partner"]
		var id := int(dec["type"])
		var sp: String = names[id] if id >= 0 and id < names.size() else "?"
		var card := "Card %d" % int(e["port"]) if int(e["port"]) > 0 else str(e["card"]).get_file().get_basename()
		_list.add_item("%s, save %d: %s the %s (tamer %s)" % [card, int(e["slot"]) + 1, dec["name"], sp, dec.get("tamer", "?")])
		if not c.is_empty() and same_card(c["card"], e["card"]) and int(c["slot"]) == int(e["slot"]):
			_list.select(_list.item_count - 1)
	if not c.is_empty() and not _list.is_anything_selected():
		# the chosen save isn't readable now (the card mid-write, moved, another folder): kept (DS8-7)
		_list.add_item("Save %d on %s: can't be read right now (kept)" % [int(c["slot"]) + 1, str(c["card"]).get_file()])
		_kept = _list.item_count - 1
		_list.select(_kept)
	_list.add_item("No save: Ninjamon, just for the desktop (their care isn't kept)")
	if not _list.is_anything_selected():
		_list.select(0 if not saves.is_empty() and c.is_empty() else _list.item_count - 1)


## One card file however its path is spelled (slashes, case: Windows paths).
static func same_card(a, b) -> bool:
	return str(a).replace("\\", "/").to_lower() == str(b).replace("\\", "/").to_lower()


func _choose() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		return
	var from := disc_path.get_base_dir() if disc_path != "" else OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	DisplayServer.file_dialog_show("Your Digimon World (USA) disc image", from, "", false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, PackedStringArray(FILTERS), _chosen, get_window_id())


func _chosen(ok: bool, paths: PackedStringArray, _filter: int) -> void:
	if ok and not paths.is_empty():
		_check.call_deferred(paths[0])


func _done() -> void:
	if not disc_ok:
		return
	var row := _list.get_selected_items()[0] if _list.is_anything_selected() else -1
	if row >= 0 and row < saves.size():
		var e: Dictionary = saves[row]
		var c := CardLink.read_choice()
		if c.is_empty() or not same_card(c["card"], e["card"]) or int(c["slot"]) != int(e["slot"]):
			CardLink.write_choice(str(e["card"]), int(e["slot"]))
	elif row != _kept:
		CardLink.clear_choice()
	var c2 := CardLink.read_choice()
	finished.emit(disc_path != _was["disc"] or str(c2.get("card", "")) != _was["card"] or int(c2.get("slot", -1)) != _was["slot"])


func _quit() -> void:
	set_meta("quit", true)
	finished.emit(false)
