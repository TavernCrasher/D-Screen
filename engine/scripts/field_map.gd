class_name FieldMap
extends Node3D

## MAP_LAYER_ENABLED changed (set_map_layer): main hides / shows the chests and dropped items with
## it (renderChest and renderDroppedItem check it too, map_object.c:415, item.c:355; EFE-3F-3).
signal map_layer_changed(on: bool)
## A DW1 field map: the original pre-rendered background projected onto the ground through
## the map's fixed camera, the 100x100 collision/trigger grid, warps and placed Digimon.
## Data from tools/dw1_maps.py (structures per DW1-SydPatches; it has no license, checked 2026-10-19).
##
## Coordinates: DW1 units (x right, y down, z forward); Godot = (x, -y, -z) * UNIT.
## Collision tile (tx, ty) as FUN_800c0f28: x = dx / 100 + 50 (- 1 if dx < 0),
## y = 50 - dz / 100 (- 1 if dz > 0), with C division (truncating) on integer DW1 units.

const UNIT := 0.005                 # metres per DW1 unit (same as battles)
const BLOCKED := 0x80
const SCREEN_H := 240.0             # DW1 screen height in pixels

var data: Dictionary = {}           # map JSON
var map_name := ""
var camera: Camera3D
var _cam_basis := {}                # r, d, f, vp (DW1 space), h, center
## The loaded map's projection distance (VIEWPORT_DISTANCE, map.c:4569); a battle's effects
## read it (EFE natives 81/94).
static var view_distance := 0x200
var _ground: MeshInstance3D
var _view_offset := Vector2.ZERO    # current lens shift, DW1 screen pixels
var scripted_exits: Dictionary = {}  # trigger -> {map, exit, event} from tools/dw1_exits.py
var object_flags := {}                # overlay instance -> flag (set_map_object; 1 = hidden)

static var _all_exits: Dictionary = {}


static func entries() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://game_data/maps/map_entries.json"))


static func entry(map_id: int) -> Dictionary:
	for e in entries():
		if int(e["id"]) == map_id:
			return e
	return {}


## changeMap (FUN_800d9020): where fleeing a battle returns to. PREVIOUS_SCREEN is the map
## being left and PREVIOUS_EXIT the exit tile taken (or, for a scripted change, the exit the
## map was entered by), except after the transports from map 207 and a few one-way paths.
static func previous_screen(cur: int, dest: int, exit_used: int) -> Vector2i:
	var prev := Vector2i(cur, exit_used)
	if cur == 207:
		var transport := {38: Vector2i(88, 2), 70: Vector2i(69, 2), 79: Vector2i(17, 1),
			93: Vector2i(90, 0), 119: Vector2i(118, 1), 105: Vector2i(106, 0)}
		if transport.has(dest):
			prev = transport[dest]
	if cur == 43 and dest == 42:                      # falling off the canyon cliff
		prev = Vector2i(41, 1)
	if cur == 6 and dest == 105:                      # Seadramon to Beetle Land
		prev.x = 106
	if cur == 142 and dest == 135:                    # Whamon's cave back to Freezeland
		prev = Vector2i(132, 1)
	if cur == 5 and dest == 12:                       # Coelamon to the jungle
		prev = Vector2i(13, 1)
	return prev


static func id_of(map_name: String) -> int:
	for e in entries():
		if e["file"] == map_name:
			return int(e["id"])
	return -1


static func name_of(map_id: int) -> String:
	for e in entries():
		if int(e["id"]) == map_id:
			return e["file"]
	return ""


func load_map(name: String) -> bool:
	var text := FileAccess.get_file_as_string("res://game_data/maps/%s.json" % name)
	if text.is_empty():
		push_warning("no data for map %s" % name)
		return false
	data = JSON.parse_string(text)
	map_name = name
	object_flags.clear()
	day_night = bool(data.get("day_night", false))
	outdoor = bool(data.get("outdoor", day_night))
	if _all_exits.is_empty():
		var ex := FileAccess.get_file_as_string("res://game_data/maps/exits.json")
		_all_exits = JSON.parse_string(ex) if not ex.is_empty() else {}
	scripted_exits = _all_exits.get(name, {})
	for c in get_children():
		c.queue_free()
	_setup_camera()
	_build_ground()
	_build_overlays()
	_build_screen_fx()
	_build_light()
	return true


# ---------------------------------------------------------------- camera
func _setup_camera() -> void:
	var s: Dictionary = data["setup"]
	var vp := Vector3(s["viewpoint"][0], s["viewpoint"][1], s["viewpoint"][2]) * 2.0
	var rp := Vector3(s["reference_point"][0], s["reference_point"][1], s["reference_point"][2]) * 2.0
	var f := (rp - vp).normalized()
	var r := Vector3(0, 1, 0).cross(f).normalized()
	var d := f.cross(r)
	view_distance = int(s["view_distance"])
	_cam_basis = {"vp": vp, "r": r, "d": d, "f": f, "h": float(s["view_distance"]),
		"center": Vector2(s["bg_width"] * 64, s["bg_height"] * 64),
		"size": Vector2(s["bg_width"] * 128, s["bg_height"] * 128)}
	camera = Camera3D.new()
	add_child(camera)
	camera.global_position = to_godot(vp)
	camera.look_at(to_godot(rp), Vector3.UP)
	camera.near = 1.0
	camera.far = 400.0
	_apply_lens(Vector2.ZERO)
	camera.make_current()


## DW1 scrolls its background as the player moves: a lens shift with the camera fixed.
func _apply_lens(offset_px: Vector2) -> void:
	var h: float = _cam_basis["h"]
	var near := camera.near
	camera.set_frustum(SCREEN_H * near / h, Vector2(offset_px.x, -offset_px.y) * near / h, near, camera.far)


# ---------------------------------------------------------------- view scrolling
## DW1 (FUN_800d6f64 / FUN_800d763c, verified live): no dead zone, no easing. While a d-pad
## direction is held the view moves by the tamer's projected step; an axis whose direction is
## held only scrolls once the anchor (the tamer's tracked screen point) is at or past the
## centre, the other axis always follows. Clamped to the background; nothing scrolls without
## input except script pans. In background px from its centre: _view_offset = 160 - EC0,
## _anchor = 160 - PLAYER_OFFSET. Widescreen: the horizontal clamp uses the wider view.
var _anchor := Vector2.ZERO
var _pan := {}                       # camera_to pan in progress (FUN_800d80a0)
var view_width := 0.0                # 0 = the window's aspect; tests use 320 (DW1)


func view_limit() -> Vector2:
	var size: Vector2 = _cam_basis["size"]
	var w := view_width
	if w <= 0.0:
		w = SCREEN_H * (get_viewport().get_visible_rect().size.aspect() if is_inside_tree() else 4.0 / 3.0)
	return (size / 2.0 - Vector2(w, SCREEN_H) / 2.0).max(Vector2.ZERO)


func view_offset() -> Vector2:
	return _view_offset


## Map entry (FUN_800d634c + FUN_800d6a4c): the tamer centred, clamped, at once.
func enter_view(p: Vector3) -> void:
	_anchor = project(p) - _cam_basis["center"]
	_view_offset = _anchor.clamp(-view_limit(), view_limit())
	_pan = {}
	_apply_lens(_view_offset)


## One step of an entity from old_p to new_p (Godot positions) with the held directions.
## Script *_camera moves call it with no directions (full follow).
func scroll(old_p: Vector3, new_p: Vector3, left := false, right := false, up := false,
		down := false) -> void:
	var d: Vector2 = project(new_p) - project(old_p)
	var lim := view_limit()
	var a_old := _anchor
	var v_old := _view_offset
	_anchor += d
	for ax in 2:
		var v := v_old[ax] + d[ax]
		if absf(v) > lim[ax]:                         # FUN_800d7f68: pinned at the edge
			_view_offset[ax] = clampf(v, -lim[ax], lim[ax])
			continue
		var neg := left if ax == 0 else up
		var pos := right if ax == 0 else down
		if (neg and a_old[ax] > v_old[ax]) or (pos and not neg and a_old[ax] < v_old[ax]):
			continue                                  # not yet at the centre: no scroll
		_view_offset[ax] = v
	_apply_lens(_view_offset)


## SCRIPT camera_to / camera_to_entity (FUN_800d80a0): a linear pan over `speed` frames to the
## clamped target; the anchor jumps to the target. pan_tick() runs once per 20 fps frame.
func start_pan(p: Vector3, speed: int) -> void:
	var t: Vector2 = project(p) - _cam_basis["center"]
	_anchor = t
	var tc := t.clamp(-view_limit(), view_limit())
	var axes := []
	for ax in 2:
		var diff := int(round(tc[ax] - _view_offset[ax]))
		var sp := maxi(speed, 1)
		axes.append({"tc": tc[ax], "diff": diff, "q": diff / sp, "rem": absi(diff % sp),
			"done": diff == 0})
		if diff == 0:
			_view_offset[ax] = tc[ax]
	_pan = {"axes": axes}


func pan_active() -> bool:
	return not _pan.is_empty()


## Background px from its centre -> the DW1 ground point (y 0) under it (FUN_800e4038: a ray
## through the pixel intersected with the ground).
func ground_at(px: Vector2) -> Vector3:
	var dir: Vector3 = _cam_basis["f"] * float(_cam_basis["h"]) + _cam_basis["r"] * px.x + _cam_basis["d"] * px.y
	var vp: Vector3 = _cam_basis["vp"]
	if absf(dir.y) < 0.0001:
		return Vector3(vp.x, 0, vp.z)
	var t := -vp.y / dir.y
	return vp + dir * t


## A DW1 point -> background px from its centre.
func px_of(dw: Vector3) -> Vector2:
	return project(to_godot(dw)) - _cam_basis["center"]


func bg_half() -> Vector2:
	return _cam_basis["size"] / 2.0


## FISH::80070040: moves the view toward background px `px` (from the centre) when it is more
## than `dead` px off the view centre, at most `step` px a frame, clamped. False once settled.
func view_toward(px: Vector2, step: float, dead := Vector2(40, 30)) -> bool:
	var lim := view_limit()
	var moved := false
	for ax in 2:
		var diff: float = px[ax] - _view_offset[ax]
		var want := 0.0
		if diff > dead[ax]:
			want = diff - dead[ax]
		elif diff < -dead[ax]:
			want = diff + dead[ax]
		var v: float = clampf(_view_offset[ax] + clampf(want, -step, step), -lim[ax], lim[ax])
		if absf(v - _view_offset[ax]) > 0.01:
			moved = true
		_view_offset[ax] = v
	_apply_lens(_view_offset)
	return moved


## Restores a saved view (FISH's unload); anchor: the tamer's px, which scrolling follows.
func set_view(v: Vector2, anchor: Vector2) -> void:
	_view_offset = v.clamp(-view_limit(), view_limit())
	_anchor = anchor
	_pan = {}
	_apply_lens(_view_offset)


func pan_tick() -> void:
	if _pan.is_empty():
		return
	var lim := view_limit()
	var all_done := true
	for ax in 2:
		var a: Dictionary = _pan["axes"][ax]
		if a["done"]:
			continue
		var v: float = _view_offset[ax] + int(a["q"])
		if int(a["rem"]) >= 0:
			v += 1 if int(a["diff"]) > 0 else -1
			a["rem"] = int(a["rem"]) - 1
		v = clampf(v, -lim[ax], lim[ax])
		var tc: float = a["tc"]
		v = minf(v, tc) if int(a["diff"]) > 0 else maxf(v, tc)
		_view_offset[ax] = v
		if is_equal_approx(v, tc) or absf(v) >= lim[ax]:
			a["done"] = true
		else:
			all_done = false
	_apply_lens(_view_offset)
	if all_done:
		_pan = {}


## Background pixel for a Godot-space point (same math as the shader / tools/dw1_camera.py).
func project(p: Vector3) -> Vector2:
	var q: Vector3 = to_dw1(p) - _cam_basis["vp"]
	var zc: float = q.dot(_cam_basis["f"])
	var h: float = _cam_basis["h"]
	return Vector2(h * q.dot(_cam_basis["r"]) / zc, h * q.dot(_cam_basis["d"]) / zc) + _cam_basis["center"]


## isTileOffScreen / isInScreenRect: DW1 tests a 400x320 rect around its 320x240 screen,
## i.e. 40 px beyond each edge. Our view can be wider, so the margin is added to its width.
func off_screen(p: Vector3) -> bool:
	if _cam_basis.is_empty():
		return false
	var s: Vector2 = project(p) - _cam_basis["center"] - _view_offset
	var aspect := get_viewport().get_visible_rect().size.aspect() if is_inside_tree() else 4.0 / 3.0
	return absf(s.x) > SCREEN_H * aspect / 2.0 + 40.0 or absf(s.y) > SCREEN_H / 2.0 + 40.0


# ---------------------------------------------------------------- scene
func _build_ground() -> void:
	_bg_tex = []
	for k in palette_count():                        # day / evening / night pictures
		var path := "res://game_data/maps/%s_bg%s.png" % [map_name, "" if k == 0 else "_%d" % k]
		if k > 0 and not FileAccess.file_exists(path):
			day_night = false
			break
		_bg_tex.append(ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(path))))
	var tex: ImageTexture = _bg_tex[0]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/dw1_bg_project.gdshader")
	mat.set_shader_parameter("bg", tex)
	mat.set_shader_parameter("bg_b", tex)
	_ground_mat = mat
	for k in ["vp", "h", "center", "size"]:
		mat.set_shader_parameter(k, _cam_basis[k])
	mat.set_shader_parameter("axis_r", _cam_basis["r"])
	mat.set_shader_parameter("axis_d", _cam_basis["d"])
	mat.set_shader_parameter("axis_f", _cam_basis["f"])
	mat.set_shader_parameter("unit", UNIT)
	var plane := PlaneMesh.new()
	plane.size = Vector2(10000, 10000) * UNIT      # the 100x100-tile grid
	_ground = MeshInstance3D.new()
	_ground.mesh = plane
	_ground.material_override = mat
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ground)
	# The projection gives the right pixel on any surface the camera sees, so a large box
	# around the camera, behind the ground, shows the parts of the picture above the horizon
	# (low cameras such as the Drill Tunnel's).
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 300.0
	box.flip_faces = true
	var backdrop := MeshInstance3D.new()
	backdrop.mesh = box
	backdrop.material_override = mat
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	backdrop.position = to_godot(Vector3(_cam_basis["vp"].x, _cam_basis["vp"].y, _cam_basis["vp"].z))
	add_child(backdrop)


## Map-object overlays (signs, building fronts, trees, water, fire): DW1 draws each instance
## over the background sorted by the depth of its first frame's anchor, which is how
## characters disappear behind buildings. Each frame's sprite becomes a camera-facing quad at
## that depth covering exactly its background pixels; the instance's OverlayAnim picks the
## quad shown (FUN_800b43c0). "Far" instances (anchor y 10000) sit just in front of the
## background tiles: they are composited into the ground texture. FRZL snowflakes are screen
## effects (SnowFx, see "screen effects" below).
var _anims := {}                     # instance -> OverlayAnim
var _inst := {}                      # instance -> its data (overlay_instances)
var _quads := {}                     # instance -> {object: [MeshInstance3D, ...]}
var _objects := {}                   # object index -> overlay_objects entry
var _atlas_imgs: Array = []          # per palette: Image
var _atlas_tex: Array = []           # per palette: ImageTexture
var _overlay_mats := {}              # blend -> ShaderMaterial
var _far: Array = []                 # far instance ids
var _far_imgs: Array = []            # per palette: Image (background size), drawn over
var _far_tex: Array = []
var _far_add_imgs: Array = []        # per palette: the additive far objects (FIELD-16)
var _far_add_tex: Array = []
var _far_dirty := false
var _anim_accum := 0.0

const BLEND5 := """// DW1's palette fade (FUN_800d7210) on the 5-bit values: c1 - (c1 - c2) / d, truncated toward
// zero; d = 0 shows c1. The pictures hold c * 255 / 31, so the 5-bit values come back exactly.
vec3 blend5(vec3 a, vec3 b, int d) {
	if (d <= 0) {
		return a;
	}
	ivec3 ia = ivec3(round(a * 31.0));
	ivec3 ib = ivec3(round(b * 31.0));
	ivec3 df = ia - ib;
	ivec3 q = ivec3(sign(vec3(df))) * (abs(df) / d);
	return vec3(ia - q) / 31.0;
}
vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}"""

const OVERLAY_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled%s;
uniform sampler2D tex_a : filter_linear;
uniform sampler2D tex_b : filter_linear;
uniform sampler2D tex_a_n : filter_nearest;   // the same atlas: alpha stays crisp at the edges
uniform int fade_d = 0;
""" + BLEND5 + """
void fragment() {
	vec4 c = texture(tex_a, UV);
	c.a = texture(tex_a_n, UV).a;   // linear alpha left 1-px seams between abutting sprites
	c.rgb = blend5(c.rgb, texture(tex_b, UV).rgb, fade_d);
	ALBEDO = to_linear(c.rgb);
	%s
}
"""



func _overlay_material(blend: String) -> ShaderMaterial:
	if _overlay_mats.has(blend):
		return _overlay_mats[blend]
	var sh := Shader.new()
	match blend:
		"opaque":
			sh.code = OVERLAY_SHADER % ["", "if (c.a < 0.5) { discard; }"]
		"add":
			sh.code = OVERLAY_SHADER % [", blend_add, depth_draw_never", "ALPHA = c.a;"]
		_:
			sh.code = OVERLAY_SHADER % [", blend_mix, depth_prepass_alpha", "ALPHA = c.a;"]
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tex_a", _atlas_tex[0])
	m.set_shader_parameter("tex_b", _atlas_tex[0])
	m.set_shader_parameter("tex_a_n", _atlas_tex[0])
	_overlay_mats[blend] = m
	return m


func _build_overlays() -> void:
	_anims.clear()
	_inst.clear()
	_quads.clear()
	_objects.clear()
	_overlay_mats.clear()
	_far.clear()
	_atlas_imgs = []
	_atlas_tex = []
	_far_imgs = []                                   # nothing carries over from the last map
	_far_tex = []
	_far_add_imgs = []
	_far_add_tex = []
	var list: Array = data.get("overlay_instances", [])
	for k in palette_count():
		var path := "res://game_data/maps/%s_ov%s.png" % [map_name, "" if k == 0 else "_%d" % k]
		if not FileAccess.file_exists(path):
			break
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		_atlas_imgs.append(img)
		_atlas_tex.append(ImageTexture.create_from_image(img))
	if list.is_empty() or _atlas_tex.is_empty():
		return
	for o in data.get("overlay_objects", []):
		_objects[int(o["obj"])] = o
	var atlas_size := Vector2(_atlas_tex[0].get_width(), _atlas_tex[0].get_height())
	for inst in list:
		var id := int(inst["instance"])
		if inst.get("snow", false):
			continue                                 # SnowFx runs these
		_inst[id] = inst
		_anims[id] = OverlayAnim.new(inst["frames"])
		if inst["far"]:
			_far.append(id)
			continue
		var by_obj := {}
		for fr in inst["frames"]:
			var obj := int(fr[0])
			if obj < 0 or by_obj.has(obj) or not _objects.has(obj):
				continue
			var nodes := []
			for blend in _objects[obj]["layers"]:
				var mi := MeshInstance3D.new()
				mi.mesh = _overlay_quad(inst, _objects[obj], _objects[obj]["layers"][blend], atlas_size)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.material_override = _overlay_material(blend)
				add_child(mi)
				nodes.append(mi)
			by_obj[obj] = nodes
		_quads[id] = by_obj
		_show_instance(id)
	_build_far()


func palette_count() -> int:
	return 3 if day_night else 1


func _hidden(id: int) -> bool:
	var inst: Dictionary = _inst[id]
	return int(object_flags[id]) & 1 == 1 if object_flags.has(id) else bool(inst["hidden"])


func _show_instance(id: int) -> void:
	if _far.has(id):
		_far_dirty = true                            # rebuilt once per tick
		return
	if not _quads.has(id):
		return
	var cur: int = _anims[id].current()
	var vis := map_layer and not _hidden(id)
	for obj in _quads[id]:
		for n in _quads[id][obj]:
			n.visible = vis and int(obj) == cur


## The far layer: every visible far instance's current frame, over the background picture.
func _build_far() -> void:
	if _far.is_empty() or _atlas_imgs.is_empty():
		return
	_far_dirty = false
	var size: Vector2i = Vector2i(_cam_basis["size"])
	_far_imgs = []
	_far_add_imgs = []
	var order := _far.duplicate()
	order.reverse()                                  # one OT bucket: the lower index on top
	for k in _atlas_imgs.size():
		var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		var add := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		for id in order:
			var cur: int = _anims[id].current()
			if cur < 0 or _hidden(id) or not map_layer or not _objects.has(cur):
				continue
			var o: Dictionary = _objects[cur]
			var px := object_xy(id)
			for blend in o["layers"]:
				var at: Array = o["layers"][blend]
				var src := Rect2i(int(at[0]), int(at[1]), int(o["size"][0]), int(o["size"][1]))
				(add if blend == "add" else img).blend_rect(_atlas_imgs[k], src, px)
		img.premultiply_alpha()                      # filtered edges stay the sprite's colour
		_far_imgs.append(img)
		_far_add_imgs.append(add)
	if _far_tex.size() != _far_imgs.size():
		_far_tex = []
		_far_add_tex = []
		for k in _far_imgs.size():
			_far_tex.append(ImageTexture.create_from_image(_far_imgs[k]))
			_far_add_tex.append(ImageTexture.create_from_image(_far_add_imgs[k]))
	else:
		for k in _far_imgs.size():
			_far_tex[k].update(_far_imgs[k])
			_far_add_tex[k].update(_far_add_imgs[k])
	_apply_palettes()


## set_map_object: show/hide one overlay instance (its animation keeps running).
func set_object_flag(instance: int, flag: int) -> void:
	object_flags[instance] = flag
	snow.set_flag(instance, flag)                    # clears the snow bit (FIELD-30)
	if _inst.has(instance):
		_show_instance(instance)
		if _far_dirty:
			_build_far()


## Kept for callers: flags apply at once now.
func rebuild_overlays() -> void:
	pass


## The instances' positions in background pixels (LOCAL_MAP_OBJECT_INSTANCE +2 / +4), which the
## gyms move (TRN / TRN2 via 800b558c / 800b591c / 800b5318 / 800b5504). A moved sprite keeps
## its depth: DW1 sorts it by its anchor, so the quad slides across the view at that depth.
var _moved := {}                     # instance -> Vector2i, only for instances that moved


func object_xy(id: int) -> Vector2i:
	if _moved.has(id):
		return _moved[id]
	if _inst.has(id):
		return Vector2i(int(_inst[id]["px"][0]), int(_inst[id]["px"][1]))
	return Vector2i.ZERO


func set_object_xy(id: int, xy: Vector2i) -> void:
	if not _inst.has(id):
		return
	_moved[id] = xy
	if _far.has(id):
		_far_dirty = true
		return
	var base := Vector2i(int(_inst[id]["px"][0]), int(_inst[id]["px"][1]))
	var off := xy - base
	var z := _inst_depth(_inst[id])
	var h: float = _cam_basis["h"]
	var shift := to_godot(_cam_basis["r"] * (off.x * z / h) + _cam_basis["d"] * (off.y * z / h))
	for obj in _quads.get(id, {}):
		for n in _quads[id][obj]:
			n.position = shift


## 800b591c: move count instances from start by (dx, dy) pixels.
func move_objects(start: int, count: int, dx: int, dy: int) -> void:
	for id in range(start, start + count):
		set_object_xy(id, object_xy(id) + Vector2i(dx, dy))
	if _far_dirty:
		_build_far()


## 800b558c: the same, true once the first instance reaches the limit on a moving axis.
func move_objects_limit(start: int, count: int, dx: int, dy: int, lim_x: int, lim_y: int) -> bool:
	move_objects(start, count, dx, dy)
	var p := object_xy(start)
	if (dx > 0 and p.x >= lim_x) or (dx < 0 and p.x <= lim_x):
		return true
	return (dy > 0 and p.y >= lim_y) or (dy < 0 and p.y <= lim_y)


## 800b5318 / 800b5504: save and put back count instances' positions.
func store_objects(start: int, count: int) -> Array:
	var out := []
	for id in range(start, start + count):
		out.append(object_xy(id))
	return out


func restore_objects(start: int, saved: Array) -> void:
	for k in saved.size():
		set_object_xy(start + k, saved[k])
	if _far_dirty:
		_build_far()


## Builtin 0x15 (FUN_800b5c64): count instances from start restart their loop.
func reset_object_anim(start: int, count: int) -> void:
	for id in range(start, start + count):
		if _anims.has(id):
			_anims[id].reset()
			_show_instance(id)


## The overlay clock: 20 fps, whenever the field is shown (also in scripts and menus).
func _process(delta: float) -> void:
	if get_parent() != null and get_parent().get("battle") != null:
		if _fx_layer != null:
			_fx_layer.visible = false
		return                                       # renderMap doesn't run in BTL (FIELD-25)
	_anim_accum += delta * 20.0
	while _anim_accum >= 1.0:
		_anim_accum -= 1.0
		if map_layer:                                # FUN_800b43c0 is skipped entirely
			for id in _anims:
				if _anims[id].tick():
					_show_instance(id)
		_tick_screen_fx()
	if _far_dirty:
		_build_far()
	_draw_screen_fx()


# ---------------------------------------------------------------- screen effects
## Snow and mist (docs/maps.md "Screen effects"; FUN_800b43c0 → FUN_800b4cf4 / FUN_800b4780):
## 2D effects at OT 30 / 20, over every model and overlay, in screen space from the screen
## centre (the DR_OFFSET at OT 32, FIELD-29): they don't scroll with the background; the mist
## offsets follow the scroll themselves. Drawn on a canvas layer below the HUD; the pattern
## repeats every 320x240 so it also fills a widescreen view (the user's choice; DW1's screen is
## 320x240). Neither follows day/night.
## Not ticked or drawn while the map layer is off (set_map_layer) or in battle.
var snow := SnowFx.new()
var _snow_rng := DwRng.new()
var _snow_draw: Array = []           # this frame's flakes: [object, offset x, offset y]
var _snow_nodes: Array = []          # [opaque Node2D, additive Node2D]
var _fx_layer: CanvasLayer
var _fx_clip: Control                # the background picture's rectangle (no snow on the bars)
var _mist_rect: ColorRect
var _mist_on := false
var _prev_scroll := Vector2i.ZERO    # 0x80134dcc: the scroll at the end of the last frame
var _fx_frames := 0                  # PLAYTIME_FRAMES (only its parity matters)
var map_layer := true                # MAP_LAYER_ENABLED 0x80134ec8


## FUN_800e65b8: MAP_LAYER_ENABLED gates all of FUN_800b43c0, so every map object (overlays,
## far sprites, snow, mist) disappears and its timers stop. EVL turns it off after its 32-frame
## lead-in and back on at the end (EVL.c:196 / 472); DOOA's egg sequence from its start until
## the new partner appears (DOOA.c:36 / 799); EAB (EAB.c:290 / 381). FIELD-31.
func set_map_layer(on: bool) -> void:
	if on == map_layer:
		return
	map_layer = on
	for id in _quads:
		_show_instance(id)
	if not _far.is_empty():
		_build_far()
	map_layer_changed.emit(on)


func _map_id() -> int:
	return int(data.get("entry", {}).get("id", -1))


func _build_screen_fx() -> void:
	_fx_layer = null
	_mist_rect = null
	_snow_nodes = []
	_snow_draw = []
	_mist_on = false
	snow.load(_map_id(), data.get("overlay_instances", []), _snow_rng)
	var mist: Dictionary = data.get("mist", {})
	var mist_path := "res://game_data/maps/%s_mist.png" % map_name
	var has_mist := MistFx.is_mist_map(_map_id()) and not mist.is_empty() \
		and FileAccess.file_exists(mist_path)
	if snow.flakes.is_empty() and not has_mist:
		return
	_fx_layer = CanvasLayer.new()
	_fx_layer.layer = -1                             # under the HUD, the text and the fade
	add_child(_fx_layer)
	_fx_clip = Control.new()                         # DW1's screen always has background under
	_fx_clip.clip_contents = true                    # it: a widescreen view's black bars stay clear
	_fx_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(_fx_clip)
	if not snow.flakes.is_empty() and not _atlas_tex.is_empty():
		for blend in ["opaque", "add"]:              # FRZL03/06 flakes are opaque
			var n := Node2D.new()
			if blend == "add":
				var m := CanvasItemMaterial.new()
				m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
				n.material = m
			n.draw.connect(_draw_snow.bind(n, blend))
			_fx_clip.add_child(n)
			_snow_nodes.append(n)
	if has_mist:
		var idx := Image.load_from_file(ProjectSettings.globalize_path(mist_path))
		idx.convert(Image.FORMAT_R8)
		var clut := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		var rows: Array = mist["cluts"]
		for r in rows.size():
			for i in 16:
				var c: int = int(rows[r][i])
				clut.set_pixel(i, r, Color8(c & 31, (c >> 5) & 31, (c >> 10) & 31))
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/dw1_mist.gdshader")
		mat.set_shader_parameter("idx_tex", ImageTexture.create_from_image(idx))
		mat.set_shader_parameter("clut_tex", ImageTexture.create_from_image(clut))
		_mist_rect = ColorRect.new()
		_mist_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_mist_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mist_rect.material = mat
		_mist_rect.visible = false
		_fx_clip.add_child(_mist_rect)               # after the snow: OT 20 is on top


## One field frame of the effects (renderMap: after the scroll update; the previous scroll is
## stored at the end).
func _tick_screen_fx() -> void:
	_fx_frames += 1
	var sc := Vector2i(roundi(_view_offset.x), roundi(_view_offset.y))
	var d := _prev_scroll - sc                       # prevC38 - c38 (c38 - vo is constant)
	_prev_scroll = sc
	if _fx_layer == null or not map_layer:
		return
	var main := get_parent()
	var frame: int = main.sim.tick if main != null and main.get("sim") != null else _fx_frames
	if not snow.flakes.is_empty():
		_snow_draw = snow.tick(_snow_rng, frame)
	if _mist_rect != null:
		var story = main.story if main != null and main.get("story") != null else null
		var t148: bool = story != null and story.is_set(148)
		var t341: bool = story != null and story.is_set(341)
		_mist_on = MistFx.tick(_map_id(), d.x, d.y, _fx_frames & 1 == 0, t148, t341)


func _draw_screen_fx() -> void:
	if _fx_layer == null:
		return
	_fx_layer.visible = map_layer
	var vs := get_viewport().get_visible_rect().size
	var s := vs.y / 240.0
	var bg := Rect2(vs / 2.0 - (_cam_basis["size"] / 2.0 + _view_offset) * s, _cam_basis["size"] * s)
	bg = bg.intersection(Rect2(Vector2.ZERO, vs))
	_fx_clip.position = bg.position
	_fx_clip.size = bg.size
	for n in _snow_nodes:
		n.queue_redraw()
	if _mist_rect != null:
		_mist_rect.visible = _mist_on
		if _mist_on:
			var m: ShaderMaterial = _mist_rect.material
			m.set_shader_parameter("view_size", vs)
			m.set_shader_parameter("rect_pos", bg.position)
			m.set_shader_parameter("rect_size", bg.size)
			m.set_shader_parameter("l1", Vector2(MistFx.xs[0], MistFx.ys[0]))
			m.set_shader_parameter("l2x", float(MistFx.xs[2]))
			m.set_shader_parameter("row2", MistFx.layer2_row(_map_id()))


## Each flake at its screen position and every 320x240 repeat that reaches the view.
func _draw_snow(n: Node2D, blend: String) -> void:
	var vs := get_viewport().get_visible_rect().size
	var s := vs.y / 240.0
	var hw := vs.x / 2.0 / s
	for f in _snow_draw:
		var o: Dictionary = _objects.get(int(f[0]), {})
		if o.is_empty() or not o["layers"].has(blend):
			continue
		var at: Array = o["layers"][blend]
		var size := Vector2(float(o["size"][0]), float(o["size"][1]))
		var src := Rect2(float(at[0]), float(at[1]), size.x, size.y)
		var ox := float(f[1])
		var oy := float(f[2])
		for kx in range(ceili((-hw - size.x - ox) / 320.0), floori((hw - ox) / 320.0) + 1):
			for ky in range(ceili((-120.0 - size.y - oy) / 240.0), floori((120.0 - oy) / 240.0) + 1):
				var p := MistFx.to_view(Vector2(ox + 320.0 * kx, oy + 240.0 * ky), vs)
				n.draw_texture_rect_region(_atlas_tex[0], Rect2(p - _fx_clip.position, size * s), src)



## The instance's view depth: its anchor's; equal depths put the lower index on top (addPrim,
## FIELD-24), a 0.05-unit step per index.
func _inst_depth(inst: Dictionary) -> float:
	var anchor := Vector3(inst["anchor"][0], inst["anchor"][1], inst["anchor"][2])
	return maxf((anchor - _cam_basis["vp"]).dot(_cam_basis["f"]), 100.0) - (200 - int(inst["instance"])) * 0.05


func _overlay_quad(inst: Dictionary, o: Dictionary, at: Array, atlas_size: Vector2) -> ArrayMesh:
	var vp: Vector3 = _cam_basis["vp"]
	var f: Vector3 = _cam_basis["f"]
	var r: Vector3 = _cam_basis["r"]
	var d: Vector3 = _cam_basis["d"]
	var h: float = _cam_basis["h"]
	var c: Vector2 = _cam_basis["center"]
	var z := _inst_depth(inst)
	var px := Vector2(inst["px"][0], inst["px"][1])
	var size := Vector2(o["size"][0], o["size"][1])
	var uv0 := Vector2(at[0], at[1]) / atlas_size
	var uv1 := (Vector2(at[0], at[1]) + size) / atlas_size
	var corners := []
	for k in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
		var p: Vector2 = px + size * k - c
		corners.append(to_godot(vp + f * z + r * (p.x * z / h) + d * (p.y * z / h)))
	var uvs := [uv0, Vector2(uv1.x, uv0.y), uv1, Vector2(uv0.x, uv1.y)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uvs[i])
		st.add_vertex(corners[i])
	return st.commit()


# ---------------------------------------------------------------- day / night
var day_night := false               # the map has 3 palettes and no flag 0x40
var phase := DayNight.DAY            # the palette in use
var trans_mode := -1                 # a running transition (0 / 1 / 2), -1 none
var trans_frame := 0
var _bg_tex: Array = []              # per palette
var _ground_mat: ShaderMaterial
var _sun: DirectionalLight3D
var _sun_raw := Color.WHITE         # the map's light 0 as DW1 has it
var _mix := [0, 0, 0]                # palette from, palette to, fade divisor (0 = none)
var _last_mode := -1                 # CURRENT_TIME_OF_DAY d9d: the last mode started or set
var transition_blocked := false      # SKIP_DAYTIME_TRANSITION 0x80134db4 (a lost / fled battle)
var outdoor := false                 # no flag 0x40: the lights follow the hour (FIELD-23)


## updateTimeOfDay (FUN_800d676c): the palette and lights for the hour, at once (also ends a
## running transition).
func set_time_of_day(hour: int) -> void:
	var p := DayNight.phase_for_hour(hour)
	phase = p if day_night else DayNight.DAY
	trans_mode = -1
	transition_blocked = false                       # FUN_800d676c clears db4 (FIELD-17)
	_last_mode = [2, 0, 1][p]                        # d9d: day 2, evening 0, night 1
	_mix = [phase, phase, 0]
	_apply_palettes()
	_apply_light(p)


## initializeDaytimeTransition (FUN_800d7104); false when nothing starts.
func start_transition(mode: int) -> bool:
	if not day_night or mode < 0 or mode == _last_mode:   # FIELD-22: d9d is set at the start
		return false
	_last_mode = mode
	trans_mode = mode
	trans_frame = 0
	return true


func transitioning() -> bool:
	return trans_mode >= 0


## tickDaytimeTransition (FUN_800d7210), one 20 fps field frame: 25 partial steps, then the
## target palette and the lights.
func transition_tick() -> void:
	if trans_mode < 0:
		return
	var a := DayNight.source_phase(trans_mode)
	var b := DayNight.target_phase(trans_mode)
	if trans_frame < DayNight.FRAMES:
		_mix = [a, b, DayNight.transition_divisor(trans_frame)]
		trans_frame += 1
	else:
		_mix = [b, b, 0]
		phase = b
		trans_mode = -1
		transition_blocked = false
		_apply_light(b)
	_apply_palettes()


func _apply_palettes() -> void:
	var a: int = mini(_mix[0], _bg_tex.size() - 1)
	var b: int = mini(_mix[1], _bg_tex.size() - 1)
	if _ground_mat and a >= 0:
		_ground_mat.set_shader_parameter("bg", _bg_tex[a])
		_ground_mat.set_shader_parameter("bg_b", _bg_tex[b])
		_ground_mat.set_shader_parameter("fade_d", _mix[2])
		if not _far_tex.is_empty():
			var fa := mini(a, _far_tex.size() - 1)
			var fb := mini(b, _far_tex.size() - 1)
			_ground_mat.set_shader_parameter("far_a", _far_tex[fa])
			_ground_mat.set_shader_parameter("far_b", _far_tex[fb])
			_ground_mat.set_shader_parameter("far_add_a", _far_add_tex[fa])
			_ground_mat.set_shader_parameter("far_add_b", _far_add_tex[fb])
			_ground_mat.set_shader_parameter("has_far", true)
	if _atlas_tex.is_empty():
		return
	for blend in _overlay_mats:
		var m: ShaderMaterial = _overlay_mats[blend]
		m.set_shader_parameter("tex_a", _atlas_tex[mini(_mix[0], _atlas_tex.size() - 1)])
		m.set_shader_parameter("tex_a_n", _atlas_tex[mini(_mix[0], _atlas_tex.size() - 1)])
		m.set_shader_parameter("tex_b", _atlas_tex[mini(_mix[1], _atlas_tex.size() - 1)])
		m.set_shader_parameter("fade_d", _mix[2])


## The model lights scaled per channel (lights 0-2 x factor / 10; ambient stays).
func _apply_light(p: int) -> void:
	if _sun == null:
		return
	var fac := DayNight.light_factors(p) if outdoor else Vector3i(10, 10, 10)
	var raw := Color(_sun_raw.r * fac.x / 10.0, _sun_raw.g * fac.y / 10.0, _sun_raw.b * fac.z / 10.0)
	_sun.light_color = raw.lerp(Color.WHITE, 0.3)


func _build_light() -> void:
	var l: Dictionary = data["setup"]["lights"][0]
	var sun := DirectionalLight3D.new()
	_sun = sun
	var dir := to_godot(Vector3(l["pos"][0], l["pos"][1], l["pos"][2])) / UNIT
	if dir.length() < 0.001:
		dir = Vector3(0, -1, -0.5)
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.FORWARD)
	_sun_raw = Color(l["rgb"][0] / 255.0, l["rgb"][1] / 255.0, l["rgb"][2] / 255.0)
	sun.light_color = _sun_raw.lerp(Color.WHITE, 0.3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.5, 0.5)       # libgs_GsSetAmbient(2048, ...) = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	add_child(env)


## Soft round shadow under a character (DW1 uses blob shadows on its flat backgrounds).
static func blob_shadow(radius_m: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(radius_m, radius_m) * 2.0
	q.orientation = PlaneMesh.FACE_Y
	m.mesh = q
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = vec3(0.0);
	ALPHA = 0.45 * smoothstep(1.0, 0.4, d);
}"""
	mat.shader = sh
	m.material_override = mat
	m.position.y = 0.01
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


# ---------------------------------------------------------------- grid
static func to_godot(dw: Vector3) -> Vector3:
	return Vector3(dw.x, -dw.y, -dw.z) * UNIT


static func to_dw1(g: Vector3) -> Vector3:
	return Vector3(g.x, -g.y, -g.z) / UNIT


## applyRootMomentum (FUN_800c25c0): one frame's root delta (DW1 units, the model's own axes,
## forward = -z) rotated by the facing and added to the location, with no collision test.
static func root_step(pos: Vector3, rot_y: float, d: Array) -> Vector3:
	var dw := to_dw1(pos)
	var r := -rot_y                                  # DW1 rotation in radians (set_rotation)
	var dx: float = d[0]
	var dz: float = d[1]
	dw.x += cos(r) * dx + sin(r) * dz
	dw.z += -sin(r) * dx + cos(r) * dz
	var g := to_godot(dw)
	return Vector3(g.x, pos.y, g.z)


func tile_at(g: Vector3) -> Vector2i:
	return Follow.tile_of(to_dw1(g))


func tile_value(t: Vector2i) -> int:
	if t.x < 0 or t.y < 0 or t.x > 99 or t.y > 99:
		return BLOCKED
	return int(data["collision"][t.y * 100 + t.x])


func walkable(g: Vector3) -> bool:
	return tile_value(tile_at(g)) & BLOCKED == 0


## SCRIPT_OP_SET_IMPASSABLE (FUN_800c103c): tiles [x, x+w) x [z, z+h) become 0x80, which also
## erases their trigger. Lasts until the next map load (load_map re-reads the grid; the map
## script's init section runs it again on entry).
func set_impassable(x: int, z: int, w: int, h: int) -> void:
	for row in range(maxi(z, 0), mini(z + h, 100)):
		for col in range(maxi(x, 0), mini(x + w, 100)):
			data["collision"][row * 100 + col] = BLOCKED


## TOILET_DATA (0x80122E10): per map entry toilet_id 1-10, {POS1 x, z, POS2 x, z} in DW1 units.
const TOILETS := [[-196, -1831, -392, -976], [-2852, -957, -3319, -714], [-1200, -925, -2544, -935],
	[-281, 652, -176, 1306], [389, 445, 1487, 567], [3494, -2583, 3489, -1895],
	[-1617, -666, -1576, 181], [-30, 1550, -144, 2075], [-2122, -1930, -2256, -1260],
	[-1371, 816, -1449, 1819]]


static func toilet_spots(toilet_id: int) -> Array:
	if toilet_id < 1 or toilet_id > TOILETS.size():
		return []
	var t: Array = TOILETS[toilet_id - 1]
	return [Vector2(t[0], t[1]), Vector2(t[2], t[3])]


## Trigger id at a position (0 = none): 110-119 exit, 120 toilet, 80-109 examine, 50-79 auto event.
func trigger(g: Vector3) -> int:
	var v := tile_value(tile_at(g))
	return 0 if v & BLOCKED else v & 0x7F


## Entrance k: Godot position and facing (DW1 rotation: 0x1000 = 360 degrees).
func spawn(exit_id: int) -> Dictionary:
	for w in data["warps"]:
		if int(w["exit"]) == exit_id:
			return {"pos": to_godot(Vector3(w["x"], w["y"], w["z"])),
				"rot": -float(w["rotation"]) / 4096.0 * TAU, "dw1_rot": int(w["rotation"])}
	var c := to_godot(Vector3.ZERO)
	return {"pos": c, "rot": 0.0, "dw1_rot": 0}


## Where a trigger tile leads: exit tiles 110-119 use the map's warp table; event triggers
## (50-109) use the DG.SCN script's change_screen for the current story state (new game),
## and only plain exits (no dialogue/battle on the way) count. {} = not an exit.
func exit_for_trigger(t: int) -> Dictionary:
	if t >= 110 and t < 120:
		return warp_target(t - 110)
	var e = scripted_exits.get(str(t))
	if e is Dictionary and e.has("event") and not e["event"]:
		return {"map": e["map"], "exit": int(e["exit"]), "needs_button": t >= 80}
	return {}


## Where exit trigger k leads: {"map": name, "exit": id} or {} if it has no destination.
func warp_target(k: int) -> Dictionary:
	for w in data["warps"]:
		if int(w["exit"]) == k and int(w["target_map"]) != 65535 and w["target_name"]:
			return {"map": w["target_name"], "exit": int(w["target_exit"])}
	return {}
