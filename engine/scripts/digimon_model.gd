class_name DigimonModel
extends RefCounted
## Loads Time Stranger models for DW1 Digimon (res://models/<chr>.glb from
## tools/blender_ts_to_gltf.py) and plays TS animations by suffix.
## TS clip suffixes: _bn01 idle, _br01 run, _ba01/_ba02 attack, _bd01-03 damage,
## _bg01 guard, _bv01 victory, _f* field, _e* event.

static var _map: Dictionary = {}
static var _heights: Dictionary = {}   # chr -> rest-pose (lowest, highest) y of the TS model (m)

## Story NPC types after the 114 regular Digimon (DW1-SydPatches DigimonType).
const NPC_NAMES := {114: "Unknown", 115: "Machinedramon", 116: "Analogman", 117: "Jijimon",
	118: "Market Manager", 119: "ShogunGekomon", 120: "King Sukamon", 121: "Cherrymon",
	122: "Hagurumon", 123: "Tinmon", 124: "Master Tyrannomon"}


## DW1 id 0 is the tamer ("main character"). Shown as Aegiomon in its human disguise
## (TS char_AEGIOMON_PLAIN_CLOTHES; clips come from chr183a).
const TAMER_CHR := "chr183b"
## Clip preferences: the tamer has TS field clips (fn idle, fw walk, fr run); Digimon only
## have the battle stance/run in field use.
const IDLE := ["_fn01_01", "_bn01", "_fn02_01"]
const WALK := ["_fw01_01", "_br01"]
const RUN := ["_fr01_01", "_br01"]


## NPC types 125-179 (DW1-SydPatches DigimonType NPC_*): story NPCs that are regular Digimon,
## drawn with that Digimon's model, name and height (NPC_PATAMON 151 -> Patamon 31, ...).
## 126 Brachiomon and 127 DemiMeramon have no playable counterpart.
const NPC_BASE := {125: 80, 128: 4, 129: 5, 130: 6, 131: 7, 132: 8, 133: 9, 134: 10, 135: 11,
	136: 12, 137: 13, 138: 14, 139: 17, 140: 18, 141: 19, 142: 20, 143: 21, 144: 22, 145: 23,
	146: 24, 147: 25, 148: 26, 149: 27, 150: 28, 151: 31, 152: 32, 153: 33, 154: 34, 155: 35,
	156: 36, 157: 37, 158: 38, 159: 39, 160: 40, 161: 41, 162: 42, 163: 45, 164: 46, 165: 47,
	166: 48, 167: 49, 168: 50, 169: 51, 170: 52, 171: 53, 172: 54, 173: 55, 174: 56, 175: 58,
	176: 57, 177: 66, 178: 5, 179: 12}


## The Digimon table entry a DW1 type uses (NPC types map to their regular Digimon).
static func base_id(dw1_id: int) -> int:
	return NPC_BASE.get(dw1_id, dw1_id)


static func display_name(dw1_id: int) -> String:
	if NPC_NAMES.has(dw1_id):
		return NPC_NAMES[dw1_id]
	if dw1_id == 126:
		return "Brachiomon"
	if dw1_id == 127:
		return "DemiMeramon"
	dw1_id = base_id(dw1_id)
	var gd = Engine.get_main_loop().root.get_node_or_null("GameData")
	return gd.digimon[dw1_id]["name"] if gd and dw1_id >= 0 and dw1_id < gd.digimon.size() else "?"


static func chr_for(dw1_id: int) -> String:
	if dw1_id == 0:
		return TAMER_CHR
	if _map.is_empty():
		var text := FileAccess.get_file_as_string("res://game_data/digimon_map.json")
		_map = JSON.parse_string(text) if not text.is_empty() else {}
	# a story NPC type with a custom model of its own keeps it (custom_ecoc, 168: its technique
	# clips follow its own move list); the others are drawn with their regular Digimon's model
	var own = _map.get(str(dw1_id))
	if own and own.get("kind", "") == "custom" and own["chr"]:
		return own["chr"]
	dw1_id = base_id(dw1_id)
	var e = _map.get(str(dw1_id))
	return e["chr"] if e and e["chr"] else ""


## Returns the model scene for a DW1 id, or a capsule placeholder. With a disc in use
## (Dw1Model.use, D-Screen), DW1's own model built from it.
static func instance(dw1_id: int) -> Node3D:
	if Dw1Model.on():
		var dm := Dw1Model.build(dw1_id)
		if dm:
			return dm                                # DW1 draws no outline (DSM-6)
	var chr := chr_for(dw1_id)
	var path := "res://models/%s.glb" % chr
	if chr == "" or not ResourceLoader.exists(path):
		# placeholder until a model exists: small capsule with the Digimon's name
		var cap := MeshInstance3D.new()
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.22
		mesh.height = 0.9
		cap.mesh = mesh
		cap.position.y = 0.45
		var label := Label3D.new()
		label.text = display_name(dw1_id)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 36
		label.outline_size = 8
		label.position.y = 1.15
		var holder := Node3D.new()
		holder.add_child(cap)
		holder.add_child(label)
		return holder
	var model: Node3D = load(path).instantiate()
	_fix_outline(model)
	var eye_mats := _fix_eyes(model, chr)
	model.set_meta("dw1_type", dw1_id)
	_apply_tint(model, base_id(dw1_id))
	_apply_fire(model, chr)
	if chr.begins_with("dw1_") or chr.begins_with("custom_"):
		_dw1_style(model)
	_add_eye_driver(model, dw1_id, chr, eye_mats)
	_apply_reflect(model, chr)
	_apply_sway(model, chr)
	_add_fire_fx(model, dw1_id)
	if chr.begins_with("no_"):
		_attach_no_clips(model, chr)
	# TS and DW1 sizes differ (TS Agumon 1.74 m, DW1 250 units = 1.25 m): scale every model
	# to its DW1 height so Digimon, tamer and maps keep DW1's proportions
	if chr.begins_with("dw1_") or chr.begins_with("custom_"):
		return model                                  # built at DW1's scale already
	var want := dw1_height(dw1_id)
	if not _heights.has(chr):
		var posed := Vector2.ZERO if chr.begins_with("no_") else _idle_extent(model)
		_heights[chr] = posed if posed.y > posed.x else _model_extent(model, chr.begins_with("no_"))
	var e2: Vector2 = _heights[chr]
	var have: float = e2.y - e2.x
	if want > 0.0 and have > 0.00001:            # NO meshes measure ~0.005 m before scaling
		var k := want / have
		model.scale = Vector3.ONE * k
		# floating Digimon (Poyomon, Yuramon...): DW1's mesh starts above the ground; lift the
		# TS mesh by the difference (inside the model, so callers can still set its position)
		var ext: Vector2 = _heights[chr]
		var lift: float = dw1_bottom(dw1_id) - ext.x * k
		if lift > 0.05 and model.get_child_count() > 0 and model.get_child(0) is Node3D:
			(model.get_child(0) as Node3D).position.y += lift / k
	return model


## DW1's own models (tools/dw1_to_gltf.py, "dw1_<file>"): the TS models' dark outline, so they
## sit with the TS cast.
static var _outline: ShaderMaterial
static var _outline_flame: ShaderMaterial


static func _dw1_style(root: Node) -> void:
	if _outline == null:
		_outline = ShaderMaterial.new()
		_outline.shader = load("res://shaders/dw1_outline.gdshader")
		_outline_flame = ShaderMaterial.new()
		_outline_flame.shader = load("res://shaders/dw1_outline_flame.gdshader")
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var fire := (mi as MeshInstance3D).get_active_material(i) as ShaderMaterial
			if fire and fire.has_meta("flame"):    # custom fire: the outline moves with the tips
				fire.next_pass = _outline_flame
				continue
			var m := (mi as MeshInstance3D).get_active_material(i) as BaseMaterial3D
			if m == null or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue                       # no outline around translucent wings
			var m2: BaseMaterial3D = m.duplicate()
			m2.next_pass = _outline
			(mi as MeshInstance3D).set_surface_override_material(i, m2)


## A DW1 model (its clips are DW1's own, "dw1_<id>").
static func is_dw1(model: Node) -> bool:
	var ap := player(model)
	return ap != null and ap.has_animation("dw1_0")


## TS stand-in suffixes -> DW1 ids, for callers that still ask by suffix on a DW1 model.
const SUFFIX_DW1 := {"_fn01_01": 0, "_bn01": 0, "_fn02_01": 0, "_bn02": 1, "_fw01_01": 2,
	"_br01": 4, "_fr01_01": 4, "_ba01": 46, "_ba02": 47, "_bs01": 48, "_bd01": 40, "_bd02": 43,
	"_bd03": 44, "_bv01": 42, "_bg01": 10, "_bg02": 37, "_fe01": 22, "_fe02": 11, "_fe03": 5,
	"_fe04": 24, "_fq01": 23, "_fq02": 13}


## Recolours and relatives (digimon_map.json "tint"): the body textures recoloured towards the
## DW1 Digimon's colour by tools/tint_models.py, in models/tint/<id>/ under the same names.
static var _tints := {}


static func _apply_tint(root: Node, id: int) -> void:
	var dir := "res://models/tint/%d" % id
	if not DirAccess.dir_exists_absolute(dir):
		return
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var m := (mi as MeshInstance3D).get_active_material(i) as BaseMaterial3D
			if m == null or m.albedo_texture == null:
				continue
			var tex := _tint_texture(dir, m.albedo_texture.resource_path.get_file())
			var em: Texture2D = null
			if m.emission_texture != null:
				em = _tint_texture(dir, m.emission_texture.resource_path.get_file())
			if tex or em:
				var m2: BaseMaterial3D = m.duplicate()
				if tex:
					m2.albedo_texture = tex
				if em:
					m2.emission_texture = em
				(mi as MeshInstance3D).set_surface_override_material(i, m2)


## Time Stranger's moving fire (game_data/ts_fire.json, tools/ts_fire.py): the fire materials of
## Meramon, Birdramon, Centarumon... become shaders/ts_fire.gdshader, which scrolls TS's flame
## distortion map so the flames flow (the glTF convert keeps only a static glow). Runs after the
## tint, so recoloured relatives keep their colours.
static var _fire: Variant = null
const FIRE_GLOW := 1.7          # TS's EmissiveSampler (0.5-0.7) scaled to the old full glow


static func _apply_fire(root: Node, chr: String) -> void:
	if CUSTOM_FIRE.has(chr):
		_apply_custom_fire(root, chr)
		return
	if _fire == null:
		var text := FileAccess.get_file_as_string("res://game_data/ts_fire.json")
		_fire = JSON.parse_string(text) if not text.is_empty() else {}
	var mats: Dictionary = (_fire as Dictionary).get(chr, {})
	if mats.is_empty():
		return
	var shader: Shader = load("res://shaders/ts_fire.gdshader")
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var m := (mi as MeshInstance3D).get_active_material(i) as BaseMaterial3D
			if m == null or not mats.has(m.resource_name):
				continue
			var f: Dictionary = mats[m.resource_name]
			var sm := ShaderMaterial.new()
			sm.shader = shader
			sm.resource_name = m.resource_name
			sm.set_shader_parameter("albedo_tex", m.albedo_texture)
			sm.set_shader_parameter("emission_tex", m.emission_texture if m.emission_texture \
				else m.albedo_texture)
			var distort := "res://models/%s_%s.png" % [chr, f.get("distort", "")]
			if f.get("distort") and ResourceLoader.exists(distort):
				sm.set_shader_parameter("distort_tex", load(distort))
			if m.normal_texture:
				sm.set_shader_parameter("normal_tex", m.normal_texture)
				sm.set_shader_parameter("has_normal", true)
			var sc: Array = f["scroll"]
			sm.set_shader_parameter("scroll", Vector2(sc[0], sc[1]))
			var card: bool = f.get("card", false)
			sm.set_shader_parameter("card", card)
			sm.set_shader_parameter("distort", 0.06 if card else 0.015)
			var t: Array = f["emissive_tint"]
			sm.set_shader_parameter("emission_tint", Vector3(t[0], t[1], t[2]))
			var s: Variant = f["emissive_strength"]
			sm.set_shader_parameter("emission_strength", \
				(float(s[0]) if s is Array else float(s)) * FIRE_GLOW)
			sm.set_shader_parameter("roughness", m.roughness)
			(mi as MeshInstance3D).set_surface_override_material(i, sm)


## Custom models that burn (shaders/custom_fire.gdshader): their glb carries the flame masks in
## COLOR_0 (tools/hy3d_rig.py --flame-mask). The glow flows through TS's own flame distortion map.
## Many-part bodies (Flarerizamon) also carry a "<name>_metal" material (the helmet, claws and teeth:
## metallic, no glow, only a low floor so the painted eyes stay readable in caves) and
## "<name>_card" (DW1-style flame cards, shaders/custom_fire_card.gdshader). "floor" is the body's
## unlit floor (eye_floor; default 0.45). Darkrizamon's fire is dark (the user's choice, 2026-10-10):
## a dim red ember glow on the flame rims and streak cores, its silver jaw not glowing.
const CUSTOM_FIRE := {"custom_demi": {"tint": Vector3(1.0, 0.47, 0.11), "strength": 1.0},
	"custom_flar": {"tint": Vector3(1.0, 0.47, 0.11), "strength": 1.0, "metal_floor": 0.12},
	"custom_dark": {"tint": Vector3(1.0, 0.2, 0.1), "strength": 1.4, "metal_floor": 0.1, "floor": 0.15}}
const FIRE_NOISE := "res://models/chr010_chr_f01n.png"


static func _apply_custom_fire(root: Node, chr: String) -> void:
	var f: Dictionary = CUSTOM_FIRE[chr]
	var shader: Shader = load("res://shaders/custom_fire.gdshader")
	var noise: Texture2D = load(FIRE_NOISE) if ResourceLoader.exists(FIRE_NOISE) else null
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var m := (mi as MeshInstance3D).get_active_material(i) as BaseMaterial3D
			if m == null:
				continue
			if m.resource_name.ends_with("_card"):
				var cm := ShaderMaterial.new()
				cm.shader = load("res://shaders/custom_fire_card.gdshader")
				cm.resource_name = m.resource_name
				cm.set_shader_parameter("albedo_tex", m.albedo_texture)
				cm.set_shader_parameter("noise_tex", noise)
				cm.set_shader_parameter("emission_tint", f["tint"])
				cm.set_shader_parameter("emission_strength", f["strength"])
				(mi as MeshInstance3D).set_surface_override_material(i, cm)
				continue
			if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			var sm := ShaderMaterial.new()
			sm.shader = shader
			sm.resource_name = m.resource_name
			sm.set_meta("flame", true)
			if m.resource_name.ends_with("_metal"):
				sm.set_shader_parameter("metallic", m.metallic)
				sm.set_shader_parameter("eye_floor", f.get("metal_floor", 0.45))
			elif f.has("floor"):
				sm.set_shader_parameter("eye_floor", f["floor"])
			sm.set_shader_parameter("albedo_tex", m.albedo_texture)
			sm.set_shader_parameter("noise_tex", noise)
			sm.set_shader_parameter("roughness", m.roughness)
			sm.set_shader_parameter("emission_tint", f["tint"])
			sm.set_shader_parameter("emission_strength", f["strength"])
			(mi as MeshInstance3D).set_surface_override_material(i, sm)


## Embers and a warm light on burning Digimon (the user's choice for DemiMeramon, 2026-10-10),
## on the body bone so they bob with it. The embers live in world space, so they trail behind
## when it moves. DW1 draws neither. "emitters" gives several ember sources, each on its own bone;
## "at" places one in the model's rest space (converted to the bone), "from" in the bone's own.
## No "light": no OmniLight3D (dark fire); "ember_colours" [head, hot, mid, end] recolours the sparks.
const FIRE_FX := {127: {"bone": 2, "light": Color(1.0, 0.55, 0.2), "energy": 0.8, "range": 2.5,
	"embers": 18, "radius": 0.22, "from": Vector3(0, 0.05, -0.3)},  # from the tail, not the crown
	# Flarerizamon: sparks off the ear flames, the back crest and the tail tip; the light on the chest
	69: {"bone": 3, "light": Color(1.0, 0.55, 0.2), "energy": 0.9, "range": 3.0, "emitters": [
		{"bone": 4, "embers": 8, "radius": 0.08, "at": Vector3(0.0, 1.5, 0.18)},
		{"bone": 3, "embers": 6, "radius": 0.1, "at": Vector3(0.0, 1.3, -0.12)},
		{"bone": 15, "embers": 8, "radius": 0.07, "at": Vector3(-0.05, 0.85, -0.83)}]},
	# Darkrizamon: dark fire, no light; a few dim dark-red sparks off the same flames
	101: {"bone": 3, "ember_colours": [Color(0.85, 0.24, 0.1, 1.0), Color(0.7, 0.12, 0.05, 1.0),
		Color(0.42, 0.05, 0.03, 0.85), Color(0.18, 0.02, 0.02, 0.0)], "emitters": [
		{"bone": 4, "embers": 5, "radius": 0.08, "at": Vector3(0.0, 1.5, 0.18)},
		{"bone": 3, "embers": 4, "radius": 0.1, "at": Vector3(0.0, 1.3, -0.12)},
		{"bone": 15, "embers": 5, "radius": 0.07, "at": Vector3(-0.05, 0.85, -0.83)}]}}


static func _add_fire_fx(model: Node3D, dw1_id: int) -> void:
	var fx: Dictionary = FIRE_FX.get(base_id(dw1_id), {})
	if fx.is_empty():
		return
	var skel: Skeleton3D = null
	for n in model.find_children("*", "Skeleton3D", true, false):
		skel = n
		break
	if skel == null:
		return
	var att := BoneAttachment3D.new()
	att.name = "FireFX"
	skel.add_child(att)
	att.bone_idx = fx["bone"]
	if fx.has("light"):
		var light := OmniLight3D.new()
		light.light_color = fx["light"]
		light.light_energy = fx["energy"]
		light.omni_range = fx["range"]
		light.omni_attenuation = 1.5
		att.add_child(light)
	for e: Dictionary in fx.get("emitters", [fx]):
		var ea := att
		if int(e["bone"]) != int(fx["bone"]) or e.has("at"):
			ea = BoneAttachment3D.new()
			ea.name = "FireFX_embers"
			skel.add_child(ea)
			ea.bone_idx = e["bone"]
		var p := _embers(e, fx.get("ember_colours", []))
		if e.has("at"):
			# the model's rest space onto the bone: the offset and the up-and-back direction
			var rest := skel.get_bone_global_rest(int(e["bone"]))
			var pm2 := p.process_material as ParticleProcessMaterial
			pm2.emission_shape_offset = rest.affine_inverse() * (e["at"] as Vector3)
			pm2.direction = (rest.basis.inverse() * Vector3(0, 1, -0.7)).normalized()
		ea.add_child(p)


static func _embers(fx: Dictionary, colours: Array = []) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = fx["embers"]
	p.lifetime = 1.1
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 4, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = fx["radius"]
	pm.emission_shape_offset = fx.get("from", Vector3.ZERO)
	pm.direction = Vector3(0, 1, -0.7)                # up and back, with the flames
	pm.spread = 45.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0, 0.35, 0)                  # heat carries them up
	pm.damping_min = 0.3
	pm.damping_max = 0.6
	pm.scale_min = 0.5
	pm.scale_max = 1.1
	p.randomness = 0.6
	pm.lifetime_randomness = 0.5
	# embers, not dots: thin sparks stretched along their flight, wandering on the heat, shrinking
	# and cooling from white-hot through orange to a dull red before they die out
	pm.particle_flag_align_y = true
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 2.5
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(0.7, 0.7))
	shrink.add_point(Vector2(1.0, 0.0))
	var st := CurveTexture.new()
	st.curve = shrink
	pm.scale_curve = st
	var ramp := Gradient.new()
	var ec: Array = colours if colours.size() == 4 else [Color(1.0, 0.85, 0.45, 1.0),
		Color(1.0, 0.55, 0.12, 1.0), Color(0.9, 0.22, 0.04, 0.85), Color(0.5, 0.06, 0.02, 0.0)]
	ramp.set_color(0, ec[0])
	ramp.set_color(1, ec[3])
	ramp.add_point(0.12, ec[1])
	ramp.add_point(0.6, ec[2])
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.02, 0.07)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA   # mixed, not added: stays orange on light ground
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y   # long axis kept on the velocity
	qm.billboard_keep_scale = true
	qm.vertex_color_use_as_albedo = true
	qm.albedo_texture = _ember_dot()
	quad.material = qm
	p.draw_pass_1 = quad
	return p


static var _ember: Texture2D


## An ember streak: a hard bright head (top) trailing a fading tail, narrow across.
static func _ember_dot() -> Texture2D:
	if _ember == null:
		var img := Image.create(8, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			var along := 1.0 - y / 31.0                    # 1 at the head, 0 at the tail
			var half := lerpf(1.0, 4.2, along)              # the tail thins
			for x in 8:
				var across := clampf(1.0 - absf(x - 3.5) / half, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, sqrt(across) * along ** 1.2))
		_ember = ImageTexture.create_from_image(img)
	return _ember


static func _tint_texture(dir: String, file: String) -> Texture2D:
	var path := dir + "/" + file
	if _tints.has(path):
		return _tints[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	elif FileAccess.file_exists(path):
		tex = _texture(path)
	_tints[path] = tex
	return tex


## Height above the ground where the DW1 model's mesh starts (m); 0 for Digimon that stand.
static func dw1_bottom(dw1_id: int) -> float:
	var own := _disc_size(dw1_id)
	if not own.is_empty():
		return maxf(float(own["bottom"]), 0.0) * FieldMap.UNIT
	dw1_height(dw1_id)                                  # loads _sizes
	var e = _sizes.get(str(dw1_id), _sizes.get(str(base_id(dw1_id))))
	return maxf(float(e["bottom"]), 0.0) * FieldMap.UNIT if e is Dictionary else 0.0


static var _sizes: Dictionary = {}


## With a disc in use: the type's model measured from it (Dw1Model.info), {} without one.
static func _disc_size(dw1_id: int) -> Dictionary:
	if not Dw1Model.on():
		return {}
	return Dw1Model.info(dw1_id).get("size", {})


## model_size.json's row for a DW1 id (height, file...), {} when unmeasured.
static func dw1_model_size(dw1_id: int) -> Dictionary:
	if _sizes.is_empty():
		var t := FileAccess.get_file_as_string("res://game_data/model_size.json")
		_sizes = JSON.parse_string(t) if not t.is_empty() else {"_": 0}
	var row = _sizes.get(str(dw1_id))
	return row if row is Dictionary else {}


## Height of the DW1 model's mesh in metres (tools/dw1_model_size.py, 0.005 m per unit), or
## the Digimon table "height" (the top of the head, which overstates floating Digimon such as
## Poyomon) when the model wasn't measured; 0 if unknown.
static func dw1_height(dw1_id: int) -> float:
	var own := _disc_size(dw1_id)
	if not own.is_empty():
		return float(own["height"]) * FieldMap.UNIT
	if _sizes.is_empty():
		var t := FileAccess.get_file_as_string("res://game_data/model_size.json")
		_sizes = JSON.parse_string(t) if not t.is_empty() else {"_": 0}
	if _sizes.has(str(dw1_id)):                        # story NPCs have their own DW1 model
		return float(_sizes[str(dw1_id)]["height"]) * FieldMap.UNIT   # (giant Seadramon 134...)
	dw1_id = base_id(dw1_id)
	if _sizes.has(str(dw1_id)):
		return float(_sizes[str(dw1_id)]["height"]) * FieldMap.UNIT
	var gd = Engine.get_main_loop().root.get_node_or_null("GameData")
	if not gd or dw1_id < 0 or dw1_id >= gd.digimon.size():
		return 0.0
	return float(gd.digimon[dw1_id].get("height", 0)) * FieldMap.UNIT


## Blob shadow for a (possibly scaled) model: DW1 radius in metres on the ground.
static func shadow_for(dw1_id: int, model: Node3D) -> MeshInstance3D:
	var gd = Engine.get_main_loop().root.get_node_or_null("GameData")
	var r := 0.5
	if gd and dw1_id >= 0 and dw1_id < gd.digimon.size() and int(gd.digimon[dw1_id].get("radius", 0)) > 0:
		r = float(gd.digimon[dw1_id]["radius"]) * FieldMap.UNIT          # own table radius first
	elif gd and base_id(dw1_id) < gd.digimon.size():
		r = float(gd.digimon[base_id(dw1_id)].get("radius", 100)) * FieldMap.UNIT
	return FieldMap.blob_shadow(r / maxf(model.scale.y, 0.01))


## Lowest and highest y of a TS model in the first frame of its idle clip (_bn01), outline
## shells excluded. DW1's sizes are measured in an animation frame too (tools/dw1_model_size.py),
## and some bind poses are far off the drawn shape (Sukamon: 3.5 m at rest, 1.0 m idle).
## Leaves the skeleton posed; the AnimationPlayer takes over once the model plays.
static func _idle_extent(root: Node3D) -> Vector2:
	var aps := root.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		return Vector2.ZERO
	var ap := aps[0] as AnimationPlayer
	var anim: Animation = null
	for n in ap.get_animation_list():
		if n.ends_with("_bn01"):
			anim = ap.get_animation(n)
	if anim == null:
		return Vector2.ZERO
	var base := ap.get_node_or_null(ap.root_node)
	if base == null:
		return Vector2.ZERO
	for t in anim.get_track_count():
		var path := anim.track_get_path(t)
		var skel := base.get_node_or_null(NodePath(path.get_concatenated_names())) as Skeleton3D
		if skel == null:
			continue
		var bone := skel.find_bone(path.get_concatenated_subnames())
		if bone < 0:
			continue
		match anim.track_get_type(t):
			Animation.TYPE_POSITION_3D:
				skel.set_bone_pose_position(bone, anim.position_track_interpolate(t, 0.0))
			Animation.TYPE_ROTATION_3D:
				skel.set_bone_pose_rotation(bone, anim.rotation_track_interpolate(t, 0.0))
			Animation.TYPE_SCALE_3D:
				skel.set_bone_pose_scale(bone, anim.scale_track_interpolate(t, 0.0))
	var lo := INF
	var hi := -INF
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.name.begins_with("outline") or mi.skin == null:
			continue
		var r := _skinned_extent(root, mi, true)
		if r.y > r.x:
			lo = minf(lo, r.x)
			hi = maxf(hi, r.y)
	return Vector2(lo, hi) if hi > lo else Vector2.ZERO


## Lowest and highest y of the unanimated model (bind pose), outline shells excluded.
## skinned = place the vertices with the skeleton's rest pose (Next Order meshes are stored in
## another unit than their bones, so their raw bounds say nothing about the drawn size).
static func _model_extent(root: Node3D, skinned := false) -> Vector2:
	var lo := INF
	var hi := -INF
	for n in root.find_children("*", "MeshInstance3D", true, false):
		if n.name.begins_with("outline"):
			continue
		var mi := n as MeshInstance3D
		if skinned and mi.skin != null:
			var r := _skinned_extent(root, mi)
			if r.y > r.x:
				lo = minf(lo, r.x)
				hi = maxf(hi, r.y)
				continue
		var b: AABB = _to_root(root, mi) * mi.get_aabb()
		lo = minf(lo, b.position.y)
		hi = maxf(hi, b.end.y)
	return Vector2(lo, hi) if hi > lo else Vector2.ZERO


static func _to_root(root: Node3D, n: Node) -> Transform3D:
	var t := Transform3D()
	var p: Node = n
	while p and p != root:
		t = (p as Node3D).transform * t if p is Node3D else t
		p = p.get_parent()
	return t


static func _skinned_extent(root: Node3D, mi: MeshInstance3D, posed := false) -> Vector2:
	var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D
	if skel == null or mi.mesh == null:
		return Vector2.ZERO
	var skin := mi.skin
	var to_root := _to_root(root, skel)
	var mats := []
	for i in skin.get_bind_count():
		var bone := skin.get_bind_bone(i)
		if bone < 0:
			bone = skel.find_bone(skin.get_bind_name(i))
		var g := skel.get_bone_global_pose(maxi(bone, 0)) if posed else skel.get_bone_global_rest(maxi(bone, 0))
		mats.append(to_root * g * skin.get_bind_pose(i))
	var lo := INF
	var hi := -INF
	for sidx in mi.mesh.get_surface_count():
		var a: Array = mi.mesh.surface_get_arrays(sidx)
		var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var bones = a[Mesh.ARRAY_BONES]
		var weights = a[Mesh.ARRAY_WEIGHTS]
		if bones == null or weights == null or verts.is_empty():
			continue
		var per: int = bones.size() / verts.size()
		for v in verts.size():
			var p := Vector3.ZERO
			for k in per:
				var w: float = weights[v * per + k]
				if w > 0.0:
					p += (mats[int(bones[v * per + k])] as Transform3D) * verts[v] * w
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
	return Vector2(lo, hi)


## The inverted-hull "outline" mesh (faces already flipped): plain black, unshaded,
## default back-face culling, so only the rim around the body shows.
static func _fix_outline(root: Node) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		if n.name.begins_with("outline"):
			var m := StandardMaterial3D.new()
			m.albedo_color = Color.BLACK
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			n.material_override = m


## Rebuilds TS eyeball materials from <chr>.eyes.json (see docs/godot_prototype.md).
static func _fix_eyes(root: Node, chr: String) -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	var text := FileAccess.get_file_as_string("res://models/%s.eyes.json" % chr)
	if text.is_empty():
		return out
	var eyes: Dictionary = JSON.parse_string(text)
	var shader: Shader = load("res://shaders/ts_eye.gdshader")
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var slots = eyes.get(String(n.name).replace("_", "."), eyes.get(String(n.name)))
		if slots == null:
			continue
		var m := ShaderMaterial.new()
		m.shader = shader
		for u in [["base_tex", "base"], ["lid_tex", "iris"], ["pupil_tex", "pupil"]]:
			if slots.has(u[1]):
				m.set_shader_parameter(u[0], _texture("res://models/%s_tex/%s.png" % [chr, slots[u[1]]]))
		n.material_override = m
		if slots.has("iris"):
			out.append(m)
	return out


## DW1's per-frame eye tiles (eye_driver.gd): a driver when the DW1 model has an eye channel and
## the model can show it (TS eyes with an eyelid atlas, or a custom model's painted states), or a
## custom model's atlas has other channels (Tinmon's brow and treads).
static func _add_eye_driver(model: Node3D, dw1_id: int, chr: String, ts_mats: Array[ShaderMaterial]) -> void:
	var m := EyeTrack.model(dw1_id)
	if m.is_empty() or (EyeTrack.eye_channel(m) < 0 and not chr.begins_with("custom_")):
		return
	var d := EyeDriver.new()
	d.name = "EyeDriver"
	if EyeTrack.eye_channel(m) >= 0:
		d.ts_mats = ts_mats
	if chr.begins_with("custom_"):
		_custom_eye_states(model, chr, d)
	if d.ts_mats.is_empty() and d.custom_mats.is_empty():
		d.free()
		return
	if EyeTrack.eye_channel(m) < 0 and d.others.is_empty():
		d.free()
		return
	model.add_child(d)
	d.setup(m)


## A custom model's painted eye states (tools/custom_eye_atlas.py): <chr>.eye_states.json {"states",
## "rects", "slots", "step"; for other channels "channels": [{"channel", "slot", "tiles"}] and
## "rect_slots"} and the atlas <chr>_eyes.png. Every material that shows the texture takes the atlas
## over the rects (custom_fire.gdshader includes custom_eye.gdshaderinc; a plain opaque material
## becomes custom_eye.gdshader, keeping its outline pass and its emission).
static func _custom_eye_states(model: Node3D, chr: String, d: EyeDriver) -> void:
	var text := FileAccess.get_file_as_string("res://models/%s.eye_states.json" % chr)
	if text.is_empty():
		return
	var info: Dictionary = JSON.parse_string(text)
	var atlas := _texture("res://models/%s_eyes.png" % chr)
	if atlas == null:
		return
	d.custom_states = info.get("states", [])
	var part_slot := -1
	for c in info.get("channels", []):
		d.others.append({"channel": int(c["channel"]), "slot": int(c["slot"]), "tiles": c["tiles"],
			"tile": "", "carry": ""})
		if c.get("parts", false):
			part_slot = int(c["slot"])   # its tile picks the built parts shown (Giromon's chain sets)
	var rects: Array[Vector4] = []
	var slots: Array[Vector4] = []
	var rect_slots := PackedInt32Array()
	var rs: Array = info.get("rect_slots", [])
	for k in 8:
		var r: Array = info["rects"][k] if k < info["rects"].size() else [0, 0, 0, 0]
		var s: Array = info["slots"][k] if k < info["slots"].size() else [0, 0, 0, 0]
		rects.append(Vector4(r[0], r[1], r[2], r[3]))
		slots.append(Vector4(s[0], s[1], s[2], s[3]))
		rect_slots.append(int(rs[k]) if k < rs.size() else 0)
	var shader: Shader = load("res://shaders/custom_eye.gdshader")
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null or String(mi.name).begins_with("outline"):
			continue
		for i in mesh.get_surface_count():
			var mat := (mi as MeshInstance3D).get_active_material(i)
			var sm: ShaderMaterial
			if mat is ShaderMaterial:
				sm = mat as ShaderMaterial
				if sm.shader == null or not sm.shader.resource_path.ends_with("custom_fire.gdshader"):
					continue
			elif mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				sm = _to_custom_eye(mat as BaseMaterial3D, shader)
				(mi as MeshInstance3D).set_surface_override_material(i, sm)
			else:
				continue
			sm.set_shader_parameter("eye_atlas", atlas)
			sm.set_shader_parameter("eye_count", mini(info["rects"].size(), 8))
			sm.set_shader_parameter("eye_rects", rects)
			sm.set_shader_parameter("eye_slots", slots)
			sm.set_shader_parameter("eye_rect_slot", rect_slots)
			sm.set_shader_parameter("eye_step", float(info["step"]))
			sm.set_shader_parameter("eye_part_slot", part_slot)
			if not d.custom_mats.has(sm):
				d.custom_mats.append(sm)


## A plain opaque material of a custom model as custom_eye.gdshader (albedo, roughness, metallic,
## emission, its outline pass kept).
static func _to_custom_eye(b: BaseMaterial3D, shader: Shader) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = shader
	sm.resource_name = b.resource_name
	sm.set_shader_parameter("albedo_tex", b.albedo_texture)
	sm.set_shader_parameter("roughness", b.roughness)
	sm.set_shader_parameter("metallic", b.metallic)
	if b.emission_enabled:
		var glow := b.emission.srgb_to_linear() * b.emission_energy_multiplier   # glTF's linear factor
		if b.emission_texture != null and b.emission_texture == b.albedo_texture:
			sm.set_shader_parameter("emission_albedo", glow.v)
		elif b.emission_texture == null:
			sm.set_shader_parameter("emission", Vector3(glow.r, glow.g, glow.b))
	sm.next_pass = b.next_pass
	return sm


## Metal on custom models: the soft room reflection of custom_eye.gdshader, per material name
## (strength; "tint" how much it takes the metal's colour; "params": any other custom_eye.gdshader
## reflect_* uniform for the model, e.g. {"reflect_horizon": Vector2(-0.04, 0.14)}). Tuned in OMOC03 and
## a studio turn.
const CUSTOM_REFLECT := {
	"custom_tin": {"custom_tin": 0.75, "custom_tin_steel": 0.7, "custom_tin_key": 0.85,
		"custom_tin_enamel": 0.03, "custom_tin_glass": 0.25, "tint": 0.3,
		"params": {"reflect_below": Color(0.86, 0.88, 0.93), "reflect_above": Color(0.3, 0.32, 0.4),
			"reflect_horizon": Vector2(-0.32, 0.0), "reflect_diffuse": 0.35, "reflect_key_gain": 1.6}},
	# Giromon (and its story NPC rig): painted steel casing with a low share (it is seen in dark rooms
	# and outdoors alike), bare steel saw bar, threads and chain, red enamel almost none
	# (a wide floor-to-wall blend: a sharp horizon read as a line round the ball; a light neutral floor,
	# as Tinmon's: the default dark floor turned the saw's undersides and the lower teeth navy-black)
	"custom_giro": {"custom_giro": 0.2, "custom_giro_steel": 0.65, "custom_giro_enamel": 0.05, "custom_giro_dsteel": 0.15,
		"tint": 0.5,
		"params": {"reflect_below": Color(0.55, 0.56, 0.6), "reflect_horizon": Vector2(-0.75, 0.75),
			"reflect_key_gain": 0.6, "alpha_matte": true, "matte_roughness": 0.18}},
	# Ninjamon (and its story NPC rig): painted iron pads and spikes, gold fittings and the lacquered scabbard
	# take a little of the room (the iron less since round 8: darker gunmetal, not chrome); cloth, skin and leather none. alpha_matte: the eyes and teeth (matte roles in
	# the texture's alpha) take a glossy 0.08 instead of the cloth's roughness
	"custom_ninj": {"custom_ninj": 0.0, "custom_ninj_skin": 0.0, "custom_ninj_iron": 0.2, "custom_ninj_gold": 0.15,
		"custom_ninj_lacquer": 0.08, "tint": 0.5,
		"params": {"reflect_below": Color(0.55, 0.56, 0.6), "reflect_horizon": Vector2(-0.75, 0.75),
			"reflect_key_gain": 0.6, "alpha_matte": true, "matte_roughness": 0.08}},
	"custom_eiga": {"custom_eiga": 0.0, "custom_eiga_skin": 0.0, "custom_eiga_iron": 0.2, "custom_eiga_gold": 0.15,
		"custom_eiga_lacquer": 0.08, "tint": 0.5,
		"params": {"reflect_below": Color(0.55, 0.56, 0.6), "reflect_horizon": Vector2(-0.75, 0.75),
			"reflect_key_gain": 0.6, "alpha_matte": true, "matte_roughness": 0.08}},
	"custom_egir": {"custom_egir": 0.2, "custom_egir_steel": 0.65, "custom_egir_enamel": 0.05, "custom_egir_dsteel": 0.15,
		"tint": 0.5,
		"params": {"reflect_below": Color(0.55, 0.56, 0.6), "reflect_horizon": Vector2(-0.75, 0.75),
			"reflect_key_gain": 0.6, "alpha_matte": true, "matte_roughness": 0.18}},
}


static func _apply_reflect(model: Node3D, chr: String) -> void:
	if not CUSTOM_REFLECT.has(chr):
		return
	var t: Dictionary = CUSTOM_REFLECT[chr]
	var shader: Shader = load("res://shaders/custom_eye.gdshader")
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null or String(mi.name).begins_with("outline"):
			continue
		for i in mesh.get_surface_count():
			var mat := (mi as MeshInstance3D).get_active_material(i)
			if mat == null or not t.has(String(mat.resource_name)):
				continue
			var sm: ShaderMaterial
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader == shader:
				sm = mat
			elif mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				sm = _to_custom_eye(mat as BaseMaterial3D, shader)
				(mi as MeshInstance3D).set_surface_override_material(i, sm)
			else:
				continue
			sm.set_shader_parameter("reflect_strength", float(t[String(mat.resource_name)]))
			sm.set_shader_parameter("reflect_tint", float(t.get("tint", 0.5)))
			var extra: Dictionary = t.get("params", {})
			for k in extra:
				sm.set_shader_parameter(k, extra[k])


## Ambient flutter of free-hanging cloth (custom_sway.gdshaderinc): chr -> shader parameters. Only the surfaces
## that carry sway weights (the hood tip is marked static in CUSTOM0.y) (CUSTOM0, written by tools/hy3d_rig.py) move; their outline shell follows.
## `SWAY_DEMO` (--sway-demo) multiplies the amplitude to show the wave alone.
const SWAY := {
	"custom_ninj": {"sway_amp": 0.008, "sway_speed": 2.2, "sway_wavelength": 0.35, "bone": 1, "probe": Vector3(0, 0.3, -0.1)},
	"custom_eiga": {"sway_amp": 0.008, "sway_speed": 2.2, "sway_wavelength": 0.35, "bone": 1, "probe": Vector3(0, 0.3, -0.1)},
}
static var sway_scale := 1.0


static func _apply_sway(model: Node3D, chr: String) -> void:
	if not SWAY.has(chr):
		return
	var t: Dictionary = SWAY[chr]
	var shader: Shader = load("res://shaders/custom_eye.gdshader")
	var drv := SwayDriver.new()
	drv.name = "SwayDriver"
	drv.skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	drv.bone = int(t.get("bone", 1))
	drv.probe = t.get("probe", Vector3.ZERO)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null or String(mi.name).begins_with("outline"):
			continue
		drv.mesh = mi as Node3D
		for i in mesh.get_surface_count():
			if (mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_CUSTOM0) == 0:
				continue
			var mat := (mi as MeshInstance3D).get_active_material(i)
			var sm: ShaderMaterial
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader == shader:
				sm = mat
			elif mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				sm = _to_custom_eye(mat as BaseMaterial3D, shader)
				(mi as MeshInstance3D).set_surface_override_material(i, sm)
			else:
				continue
			var ol := sm.next_pass as ShaderMaterial
			if ol != null:
				ol = ol.duplicate()
				sm.next_pass = ol
			for k in t:
				if not String(k).begins_with("sway_"):
					continue
				var v: Variant = t[k]
				if k == "sway_amp":
					v = float(v) * sway_scale
				sm.set_shader_parameter(k, v)
				if ol != null:
					ol.set_shader_parameter(k, v)
			sm.set_shader_parameter("sway_lag_scale", sway_scale)
			drv.materials.append(sm)
			if ol != null:
				ol.set_shader_parameter("sway_lag_scale", sway_scale)
				drv.materials.append(ol)
	if drv.skeleton != null and drv.mesh != null and not drv.materials.is_empty():
		model.add_child(drv)
	else:
		drv.free()


## Starts DW1 clip `id`'s eye track on a model (no driver: nothing); rate 2 for animFlag bit 4.
static func eyes(model: Node, id: int, rate := 1.0) -> void:
	var d := model.get_node_or_null("EyeDriver") as EyeDriver if model else null
	if d:
		d.start(id, false, rate)


## A map NPC or battle enemy: its eye tiles share NPC type `type`'s texture with the others of that
## type (EyeDriver.share, EYE-9). Not for the partner or the tamer, who have their own.
static func share_eyes(model: Node, type: int) -> void:
	var d := model.get_node_or_null("EyeDriver") as EyeDriver if model else null
	if d:
		d.share(type)


## Holds the eye track (a clip held on a frame, as the finisher's charge pose).
static func eyes_pause(model: Node, paused: bool) -> void:
	var d := model.get_node_or_null("EyeDriver") as EyeDriver if model else null
	if d:
		d.paused = paused


## startAnimation with animFlag bit 0 cleared (the finisher's charge, the stun): clip `id` armed at
## tick 0 but not ticked, so the previous tile stays until eyes_pause(model, false).
static func eyes_held(model: Node, id: int) -> void:
	var d := model.get_node_or_null("EyeDriver") as EyeDriver if model else null
	if d:
		d.start(id, true)


## The DW1 clip a model's eye track follows (-1: none or no driver).
static func eye_clip(model: Node) -> int:
	var d := model.get_node_or_null("EyeDriver") as EyeDriver if model else null
	return d.clip_id if d else -1


## The status page restarts the entity's clip (EyeDriver.status_restart) and its body clip.
static func status_restart(model: Node) -> void:
	var d := model.get_node_or_null("EyeDriver") as EyeDriver if model else null
	if d:
		d.status_restart()
	var ap := player(model)
	if ap and ap.current_animation != "":
		ap.seek(0.0, true)


## Time Stranger's pixel form (tools/ts_dot_sprites.py), shown while flattened: a 32x32 sheet
## of four 16x16 frames, the top row a two-frame walk. Null when the Digimon has none.
static func dot_sheet(dw1_id: int) -> Texture2D:
	var chr := chr_for(dw1_id)
	var path := "res://models/dot_%s.png" % chr
	if chr == "" or not FileAccess.file_exists(path):
		return null
	return _texture(path)


## A raw PNG, exact, read through FileAccess (globalize_path doesn't reach inside a .pck). An
## export carries only the imported texture (the desktop pet app): that one, lossless (compress
## mode 0), is used when the raw file isn't there.
static func _texture(path: String) -> Texture2D:
	var img := Image.new()
	if FileAccess.file_exists(path) and img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
		return ImageTexture.create_from_image(img)
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


static func player(model: Node) -> AnimationPlayer:
	return model.find_child("AnimationPlayer", true, false) if model else null


## Whether the model's clip still plays (a one-shot that ended: false); a Dw1Model or a scene.
static func is_playing(model: Node) -> bool:
	if model is Dw1Model:
		return (model as Dw1Model).is_playing()
	var ap := player(model)
	return ap != null and ap.is_playing()


## The clip's speed (1 = DW1's 20 frames a second).
static func set_speed(model: Node, s: float) -> void:
	if model is Dw1Model:
		(model as Dw1Model).speed_scale = s
		return
	var ap := player(model)
	if ap:
		ap.speed_scale = s


## The current clip's length in seconds at its speed (a one-shot: until it stops); 1 without one.
static func clip_length(model: Node) -> float:
	if model is Dw1Model:
		return (model as Dw1Model).clip_length()
	var ap := player(model)
	if ap == null or ap.current_animation == "":
		return 1.0
	return ap.get_animation(ap.current_animation).length / maxf(ap.speed_scale, 0.01)


static func clips(model: Node) -> PackedStringArray:
	var out: PackedStringArray = []
	var ap := player(model)
	if ap:
		for n in ap.get_animation_list():
			if not n.ends_with(".001"):
				out.append(n)
	return out


## Plays the first clip ending with one of the suffixes. loop=false for one-shot actions.
## `eye` is the DW1 animation id whose eye track runs with it (-1: leave the eyes; -2: the field
## idle / walk / run when `suffixes` is IDLE / WALK / RUN).
static func play(model: Node, suffixes: Array, loop := true, restart := false, eye := -2) -> String:
	if model is Dw1Model:                            # DW1's own clip for the asked meaning
		var dm := model as Dw1Model
		for s in suffixes:
			var id := int(String(s).substr(4)) if String(s).begins_with("dw1_") else int(SUFFIX_DW1.get(s, -1))
			if id >= 0 and (restart or dm.clip_id() != id) and dm.play(id):
				return "dw1_%d" % id
			if id >= 0 and dm.clip_id() == id:
				return "dw1_%d" % id
		return ""
	var ap := player(model)
	if not ap:
		return ""
	var was := ap.current_animation
	var n := _play(model, ap, suffixes, loop, restart)
	if n != "" and (restart or was != n):           # startAnimation: a script animate's root
		model.set_meta("clip_starts", int(model.get_meta("clip_starts", 0)) + 1)   # motion ends
	if n != "":
		if eye == -2:
			var tamer: bool = model.get_meta("dw1_type", -1) == 0
			eye = 0 if suffixes == IDLE else 2 if suffixes == WALK else (3 if tamer else 4) if suffixes == RUN else -1
		var d := model.get_node_or_null("EyeDriver") as EyeDriver
		if eye >= 0 and d and (restart or was != n or d.clip_id != eye):
			d.start(eye)
	return n


static func _play(model: Node, ap: AnimationPlayer, suffixes: Array, loop: bool, restart: bool) -> String:
	if is_dw1(model):                                # DW1's own clip for the asked meaning
		for s in suffixes:
			var n := "dw1_%d" % SUFFIX_DW1.get(s, -1)
			if String(s).begins_with("dw1_"):
				n = s
			if ap.has_animation(n):
				_set_loop(ap, n, Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE)
				if restart and ap.current_animation == n:
					ap.seek(0.0, true)
				ap.play(n, 0.1)
				return n
		return ""
	for s in suffixes:
		for n in clips(model):
			if n.ends_with(s):
				_set_loop(ap, n, Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE)
				if restart and ap.current_animation == n:
					ap.seek(0.0, true)
				ap.play(n, 0.15)
				return n
	return ""


# ---------------------------------------------------------------- DW1 animation ids
## DW1 animation id -> Time Stranger stand-in clips (the first the model has wins; NO models map
## through NO_CLIP_ALIASES). Ids 0-44 mean the same for every DW1 model; 46 + n is the n-th
## technique's clip (TECH_ANIM_START_ID). Meanings: docs/godot_prototype.md "Animations".
## TS Digimon share one battle-centred clip set (bn idle, br run, ba attacks, bs special, bd
## hurt / down / up, bg guard, bv victory, fe / fq emotes); few have field walk or idle clips.
const DW1_CLIPS := {
	0: IDLE, 1: ["_bn02", "_bn01"], 2: WALK, 3: WALK, 4: RUN,
	5: ["_fe03", "_fe02"], 7: ["_fq02", "_bn02"], 8: ["_fe03", "_fe01"], 9: ["_bd02"],
	10: ["_bg01"], 11: ["_fe02", "_bv01"], 12: ["_bd01"], 13: ["_fq02", "_fq01"],
	14: ["_bn02", "_bn01"], 15: ["_bn02", "_bn01"], 16: ["_bn02", "_bn01"], 17: ["_bn02", "_bn01"],
	18: ["_bn02", "_bn01"], 19: ["_fq01", "_bn02"], 21: ["_bd03"], 22: ["_fe01"], 23: ["_fq01"],
	24: ["_fe04"], 25: ["_bd01"], 27: WALK,
	28: ["_fe01", "_fe02"], 29: ["_fe02", "_fe01"], 30: ["_fe03", "_fe01"], 31: ["_fe04", "_fe01"],
	32: ["_fe01"],
	33: ["_bn01"], 34: ["_bn02", "_bn01"], 35: ["_br01"], 36: ["_br01"], 37: ["_bg02", "_bd01"],
	40: ["_bd01"], 41: ["_bd01"], 42: ["_bv01"], 43: ["_bd02"], 44: ["_bd03"],
}
## Slower-paced ids (tired walk, weak battle walk, push).
const DW1_SPEED := {3: 0.6, 27: 0.5, 35: 0.6}
## The tamer (BOYS, id 0) on TS's human set (fn idle, fw walk, fr run, bn stance, ba, bd, bv, fe).
const TAMER_DW1_CLIPS := {
	0: ["_fn01_01"], 1: ["_bn01"], 2: ["_fw01_01"], 3: ["_fr01_01"], 4: ["_fe03"], 5: ["_ba01"],
	6: ["_ba01"], 7: ["_fe04"], 8: ["_fe01"], 9: ["_fe04"], 10: ["_fe02"], 11: ["_bv01"],
	12: ["_fe03"], 14: ["_fe04"], 15: ["_bd01"], 16: ["_fe01"], 17: ["_bd01"], 18: ["_bd01"],
	19: ["_fe01"], 20: ["_fe04"], 21: ["_fr01_01"], 22: ["_fn02_01"], 23: ["_fn02_01"],
	24: ["_fn02_01"], 25: ["_fe01"], 26: ["_fe03"], 38: ["_fe02"], 39: ["_fe02"],
}
const TECH_ANIM_START := 46
static var _motion := {}


## The DW1 clip info of a type's animation (data/motion.json), {} when its model lacks it.
static func dw1_anim(dw1_type: int, id: int) -> Dictionary:
	if Dw1Model.on() and dw1_type != 0:
		var own: Dictionary = Dw1Model.info(dw1_type).get("clips", {})
		if not own.is_empty():
			return own.get(id, {})
	if _motion.is_empty():
		var t := FileAccess.get_file_as_string("res://game_data/motion.json")
		_motion = JSON.parse_string(t) if not t.is_empty() else {"_": {}}
	return _motion.get(str(dw1_type), {}).get("anims", {}).get(str(id), {})


## Clips that end (one-shot, or a finite loop count: motion.json simulated < 200, the cap) hold
## their last frame; the rest loop forever (the clip's loop op, Model.cpp:1176-1259). The tamer's
## looping action ids whose stand-in is an action clip (hold out, hurt, confront...) play once.
const TAMER_LOOPS := [0, 1, 2, 3, 10, 22, 23]


static func dw1_oneshot(dw1_type: int, id: int) -> bool:
	if dw1_type == 0 and not id in TAMER_LOOPS:
		return true
	var m := dw1_anim(dw1_type, id)
	return not m.is_empty() and int(m.get("simulated", 200)) < 200


## The stand-in clips for a DW1 animation id of a type (0 = the tamer).
static func clips_for(dw1_type: int, id: int) -> Array:
	if dw1_type == 0:
		return TAMER_DW1_CLIPS.get(id, [])
	if id >= TECH_ANIM_START:
		return _tech_clips(dw1_type, id - TECH_ANIM_START)
	return DW1_CLIPS.get(id, [])


## The n-th technique of the type: a strike (type 1) plays ba01, a projectile ba02, a finisher
## TS's special bs01.
static func _tech_clips(dw1_type: int, n: int) -> Array:
	var gd = Engine.get_main_loop().root.get_node_or_null("GameData")
	if gd == null or dw1_type >= gd.digimon.size():
		return ["_ba01", "_ba02"]
	var techs: Array = gd.digimon[dw1_type]["techniques"]
	if n >= techs.size():
		return ["_ba01", "_ba02"]
	var t: Dictionary = gd.techniques[int(techs[n]["id"])]
	if t.get("is_finisher", false):
		return ["_bs01", "_ba02", "_ba01"]
	return ["_ba01", "_ba02"] if int(t.get("type", 0)) == 1 else ["_ba02", "_ba01"]


## startAnimation (FUN_800c1a04): play DW1 animation `id` of `dw1_type` on its model, from the
## start. An id the DW1 model doesn't have changes nothing (main.c:21005), as when no stand-in
## clip exists. Returns whether it played.
static func play_dw1(model: Node, dw1_type: int, id: int) -> bool:
	if model == null or (dw1_type != 0 and dw1_anim(dw1_type, id).is_empty()):
		return false
	if model is Dw1Model:                            # startAnimation on DW1's own tick
		(model as Dw1Model).speed_scale = 1.0
		return (model as Dw1Model).play(id)
	var want: Array = ["dw1_%d" % id] if is_dw1(model) else clips_for(dw1_type, id)
	var name := play(model, want, not dw1_oneshot(dw1_type, id), true, id)
	if name == "":
		return false
	var ap := player(model)
	if ap:
		ap.speed_scale = DW1_SPEED.get(id, 1.0) if dw1_type != 0 and not is_dw1(model) else 1.0
	return true


## Loop modes live on the Animation, which every instance of a model shares: an instance that
## needs another mode gets its own copy of the library and of that clip.
static func _set_loop(ap: AnimationPlayer, n: String, mode: int) -> void:
	var anim := ap.get_animation(n)
	if anim.loop_mode == mode:
		return
	var lib_name: StringName = ap.find_animation_library(anim)
	var lib := ap.get_animation_library(lib_name)
	if not lib.has_meta("own"):
		var was := ap.current_animation
		lib = lib.duplicate()
		lib.set_meta("own", true)
		ap.remove_animation_library(lib_name)
		ap.add_animation_library(lib_name, lib)
		if was != "" and was != n:
			ap.play(was)
	var key := n.substr(String(lib_name).length() + 1) if String(lib_name) != "" else n
	var copy: Animation = anim.duplicate()
	copy.loop_mode = mode
	lib.add_animation(key, copy)


## BTL-117: the ground speed (m/s, in the model's world scale) the feet of a TS walk / run clip
## cover, estimated from how far a foot sweeps along the ground per half cycle (the stance).
## 0 when the model has no feet or the clip is missing. Cached per clip resource.
static var _foot_cache := {}


static func foot_speed(model: Node, clip: String) -> float:
	var ap := player(model)
	var sk := model.find_child("Skeleton3D", true, false) as Skeleton3D if model else null
	if ap == null or sk == null or is_dw1(model) or not ap.has_animation(clip):
		return 0.0
	var a := ap.get_animation(clip)
	if a.length <= 0.0:
		return 0.0
	var key := a.get_instance_id()
	if not _foot_cache.has(key):
		_foot_cache[key] = _measure_foot(sk, a)
	return float(_foot_cache[key]) * sk.global_transform.basis.get_scale().x


static func _measure_foot(sk: Skeleton3D, a: Animation) -> float:
	var pos_t := {}
	var rot_t := {}
	for t in a.get_track_count():
		var path := String(a.track_get_path(t))
		var c := path.find(":")
		var bi := sk.find_bone(path.substr(c + 1)) if c >= 0 else -1
		if bi < 0:
			continue
		if a.track_get_type(t) == Animation.TYPE_POSITION_3D:
			pos_t[bi] = t
		elif a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			rot_t[bi] = t
	var total := 0.0
	var feet := 0
	var n := maxi(int(a.length * 30.0), 4)
	for fname in ["J_foot_r", "J_foot_l"]:
		var fb := sk.find_bone(fname)
		if fb < 0:
			continue
		var chain: Array = []
		var b := fb
		while b >= 0:
			chain.push_front(b)
			b = sk.get_bone_parent(b)
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for k in n:
			var t := a.length * k / n
			var xf := Transform3D.IDENTITY
			for bi in chain:
				var rest := sk.get_bone_rest(bi)
				var origin: Vector3 = a.position_track_interpolate(pos_t[bi], t) if pos_t.has(bi) else rest.origin
				var q: Quaternion = a.rotation_track_interpolate(rot_t[bi], t) if rot_t.has(bi) else rest.basis.get_rotation_quaternion()
				xf = xf * Transform3D(Basis(q), origin)
			lo = lo.min(Vector2(xf.origin.x, xf.origin.z))
			hi = hi.max(Vector2(xf.origin.x, xf.origin.z))
		total += maxf(hi.x - lo.x, hi.y - lo.y)
		feet += 1
	return 0.0 if feet == 0 else total / feet * 2.0 / a.length       # one stride per half cycle


## BTL-118: a TS one-shot carries hip (J_center) translation on top of the DW1 root motion the
## sim already applies (Agumon's _bg02 sidesteps 0.45 m, DW1's 0x25 has none), so the horizontal
## hip keys are pinned to the first key, once per clip (the vertical bob stays).
static func flatten_hip(model: Node, clip: String) -> void:
	var ap := player(model)
	if ap == null or is_dw1(model) or not ap.has_animation(clip):
		return
	var a := ap.get_animation(clip)
	if a.has_meta("hip_flat"):
		return
	a.set_meta("hip_flat", true)
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_POSITION_3D or a.track_get_key_count(t) < 2 				or not String(a.track_get_path(t)).ends_with(":J_center"):
			continue
		var first: Vector3 = a.track_get_key_value(t, 0)
		for k in range(1, a.track_get_key_count(t)):
			var v: Vector3 = a.track_get_key_value(t, k)
			a.track_set_key_value(t, k, Vector3(first.x, v.y, first.z))


static func current(model: Node) -> String:
	var ap := player(model)
	return ap.current_animation if ap else ""


# ---------------------------------------------------------------- Next Order models
## Next Order clip (middle part of e.g. "a0_walk_fa0_ul") -> the TS-style suffix the game asks
## for (play() matches on endings), so NO models answer the same requests as TS ones.
const NO_CLIP_ALIASES := {"base_fa0": "_bn01", "base_fb0": "_fn02_01", "walk_fa0": "_fw01_01",
	"run__fa0": "_br01", "atck_fd0": "_ba01", "shot_fa0": "_ba02", "dmgs_fa0": "_bd01",
	"dmgl_fa0": "_bd02", "dmgx_fa0": "_bd03", "gurd_fa0": "_bg01", "feel_fa0": "_bv01",
	"feel_fc0": "_fe01", "feel_fe0": "_fe02", "eat__fa0": "_fe03", "feel_fd0": "_fe04",
	"feel_ff0": "_fq01", "prov_fa0": "_fq02"}
static var _no_libs: Dictionary = {}


## Builds the model's animations from <chr>.anims.json (tools/no_anims.py): per bone position /
## rotation / scale tracks on the Skeleton3D, sampled at 30 fps.
static func _attach_no_clips(model: Node3D, chr: String) -> void:
	var skel: Skeleton3D = model.find_child("*", true, false) as Skeleton3D
	if skel == null:
		var found := model.find_children("*", "Skeleton3D", true, false)
		if found.is_empty():
			return
		skel = found[0]
	var ap := player(model)
	if ap == null:
		ap = AnimationPlayer.new()
		ap.name = "AnimationPlayer"
		model.add_child(ap)
	ap.root_node = ap.get_path_to(model)
	var skel_path := String(model.get_path_to(skel))
	if not _no_libs.has(chr):
		var text := FileAccess.get_file_as_string("res://models/%s.anims.json" % chr)
		var lib := AnimationLibrary.new()
		if not text.is_empty():
			var data: Dictionary = JSON.parse_string(text)
			var fps: float = data["fps"]
			for clip_name in data["clips"]:
				var c: Dictionary = data["clips"][clip_name]
				var anim := Animation.new()
				anim.length = maxf(float(c["length"]), 1.0 / fps)
				for bone in c["tracks"]:
					if skel.find_bone(bone) < 0:
						continue
					var tr: Dictionary = c["tracks"][bone]
					var path := NodePath("%s:%s" % [skel_path, bone])
					if tr.has("pos"):
						var i := anim.add_track(Animation.TYPE_POSITION_3D)
						anim.track_set_path(i, path)
						var vals: Array = tr["pos"]
						for f in vals.size():
							var v: Array = vals[f]
							anim.position_track_insert_key(i, f / fps, Vector3(v[0], v[1], v[2]))
					if tr.has("rot"):
						var i := anim.add_track(Animation.TYPE_ROTATION_3D)
						anim.track_set_path(i, path)
						var vals: Array = tr["rot"]
						for f in vals.size():
							var q: Array = vals[f]
							anim.rotation_track_insert_key(i, f / fps, Quaternion(q[0], q[1], q[2], q[3]).normalized())
					if tr.has("scale"):
						var i := anim.add_track(Animation.TYPE_SCALE_3D)
						anim.track_set_path(i, path)
						var vals: Array = tr["scale"]
						for f in vals.size():
							var v: Array = vals[f]
							anim.scale_track_insert_key(i, f / fps, Vector3(v[0], v[1], v[2]))
				var parts := String(clip_name).split("_")
				var key := "_".join(parts.slice(1, parts.size() - 1)) if parts.size() > 2 else String(clip_name)
				var alias: String = NO_CLIP_ALIASES.get(key, "")
				lib.add_animation(String(clip_name) + (alias if alias != "" else ""), anim)
		_no_libs[chr] = lib
	if ap.has_animation_library(""):
		ap.remove_animation_library("")
	ap.add_animation_library("", _no_libs[chr])
