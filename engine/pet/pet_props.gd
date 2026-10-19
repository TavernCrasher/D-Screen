class_name PetProps
extends RefCounted
## The desktop pet's props (docs/desktop_pet.md "Care"): the Meat, the toilet and the six File
## City gym stations, built after DW1's gym (tools/pet_props.py -> pet/props/<name>.glb; heights
## in Ninjamon heights, origin at the ground centre, front +Z), and DW1's own poop pile (UNTI.TMD,
## tools/dw1_objects.py). A prop without its .glb yet shows a plain stand-in shape. The .glbs hold
## no DW1 pixels: the boulder's red lettering is cut at runtime (Dw1Assets.lettering: from the
## player's disc in D-Screen, from the remake's TRAI00 overlays here), and D-Screen's pile too.

const ORDER := ["meat", "toilet", "boulder", "waterfall", "log", "glove", "track", "chalkboard"]
const LABEL := {"meat": "Meat", "toilet": "Toilet", "boulder": "Boulder  HP", "waterfall": "Waterfall  MP",
	"log": "Log  Offense", "glove": "Glove  Defense", "track": "Track  Speed", "chalkboard": "Blackboard  Brains"}
const STAND_IN := {"meat": [Color(0.75, 0.3, 0.2), 0.35], "toilet": [Color(0.92, 0.92, 0.95), 0.9],
	"boulder": [Color(0.6, 0.55, 0.5), 1.1], "waterfall": [Color(0.6, 0.85, 1.0), 1.6],
	"log": [Color(0.55, 0.38, 0.22), 0.9], "glove": [Color(0.85, 0.15, 0.15), 1.3],
	"track": [Color(0.75, 0.6, 0.4), 0.08], "chalkboard": [Color(0.15, 0.3, 0.2), 1.2]}
## UV per s (tools/pet_props.py lays them out): the water falls (+v), the belt runs toward -x (+u).
const SCROLL := {"Water": Vector2(0, 0.8), "Belt": Vector2(1.2, 0)}

static var _lettering: ImageTexture


## A prop node; meta "h" is its height, "w" its width, "x0" / "x1" its left and right ends from
## the origin (Ninjamon heights; the glove machine is lopsided).
static func make(name: String) -> Node3D:
	var path := "res://pet/props/%s.glb" % name
	var n: Node3D
	if ResourceLoader.exists(path):
		n = (load(path) as PackedScene).instantiate()
		if name == "boulder":
			_letter(n)
	else:
		n = _stand_in(name)
	var box := _bounds(n, Transform3D.IDENTITY)
	n.set_meta("h", maxf(box.size.y, 0.05))
	n.set_meta("w", maxf(box.size.x, 0.05))
	n.set_meta("x0", box.position.x)
	n.set_meta("x1", box.end.x)
	n.set_meta("prop", name)
	return n


## The boulder's "lettering" material (a blank texture in the .glb) takes the cut lettering.
static func _letter(n: Node) -> void:
	var img := Dw1Assets.lettering()
	if img == null:
		return
	if _lettering == null:
		var mip := img.duplicate() as Image
		mip.generate_mipmaps()
		_lettering = ImageTexture.create_from_image(mip)
	var tex := _lettering
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if mat and mat.resource_name == "lettering":
				mat.albedo_texture = tex


static func _stand_in(name: String) -> Node3D:
	var c: Color = STAND_IN[name][0]
	var h: float = STAND_IN[name][1]
	var mi := MeshInstance3D.new()
	var m: PrimitiveMesh
	match name:
		"boulder", "meat":
			m = SphereMesh.new()
			(m as SphereMesh).radius = h / 2.0
			(m as SphereMesh).height = h
		"log":
			m = CylinderMesh.new()
			(m as CylinderMesh).top_radius = 0.25
			(m as CylinderMesh).bottom_radius = 0.28
			(m as CylinderMesh).height = h
		"track":
			m = BoxMesh.new()
			(m as BoxMesh).size = Vector3(1.6, h, 0.6)
		_:
			m = BoxMesh.new()
			(m as BoxMesh).size = Vector3(0.7 if name != "waterfall" else 1.0, h, 0.3)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	m.material = mat
	mi.mesh = m
	mi.position.y = h / 2.0
	var root := Node3D.new()
	root.add_child(mi)
	return root


static func _bounds(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var t := xf * (n as Node3D).transform if n is Node3D else xf
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out = t * (n as MeshInstance3D).mesh.get_aabb()
		first = false
	for c in n.get_children():
		var b := _bounds(c, t)
		if b.size == Vector3.ZERO:
			continue
		out = b if first else out.merge(b)
		first = false
	return out


## DW1's poop pile at DW1 size (UNTI.TMD: 150 units wide, 100 high), in metres: object 0 the
## brown cone, object 1 the quad under it, DW1's subtractive shadow (tools/dw1_objects.py), drawn
## as a darkening layer (over everything in its own window; depth-tested in his, so he stands on it).
static func pile(own_window := true) -> Node3D:
	var root := Node3D.new()
	var objs: Array
	var tex: Array[Texture2D] = []
	var disc := Dw1Assets.pile()                     # D-Screen: from the player's disc
	if not disc.is_empty():
		objs = disc["objects"]
		tex = [ImageTexture.create_from_image(disc["cone"]), ImageTexture.create_from_image(disc["shadow"])]
	elif Dw1Assets.on():                             # D-Screen ships no game_data: a failed cut is an error (CARD-G1)
		push_error("D-Screen: couldn't cut the pile from the disc")
		return root
	else:
		var path := "res://game_data/objects/unti.json"
		if not FileAccess.file_exists(path):
			return root
		objs = JSON.parse_string(FileAccess.get_file_as_string(path))["objects"]
		for f in ["unti", "unti_shadow"]:
			tex.append(DigimonModel._texture("res://game_data/objects/%s.png" % f))
	for i in objs.size():
		var o: Dictionary = objs[i]
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex[i]
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		if i == 1:
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.no_depth_test = own_window
			mat.render_priority = -1
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var pos: Array = o["pos"]
		for j in pos.size():
			var nm: Array = o["normal"][j]
			var uv: Array = o["uv"][j]
			st.set_normal(Vector3(nm[0], -nm[1], -nm[2]))
			st.set_uv(Vector2(uv[0], uv[1]))
			st.add_vertex(Vector3(pos[j][0], -pos[j][1], -pos[j][2]) * 0.005)   # FieldMap.to_godot
		st.set_material(mat)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		root.add_child(mi)
	root.set_meta("h", 0.5)
	root.set_meta("w", 0.75)
	return root


## The props' moving parts (SCROLL): the waterfall's water falls and the track's belt runs.
static func animate(n: Node3D, t: float) -> void:
	for part in SCROLL:
		var mi := n.find_child(part, true, false) as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as StandardMaterial3D
			if mat == null:
				continue
			if not mi.has_meta("own_%d" % s):           # its own copy, so the scroll is per prop
				mat = mat.duplicate()
				mi.set_surface_override_material(s, mat)
				mi.set_meta("own_%d" % s, true)
			var v: Vector2 = SCROLL[part] * t
			if part == "Belt":
				v *= float(n.get_meta("belt_dir", 1.0))   # toward his back as he runs
			mat.uv1_offset = Vector3(fposmod(v.x, 1.0), fposmod(v.y, 1.0), 0)
