class_name PetPropWindow
extends Window
## A prop or a pile on the desktop (PetPlace): its own small transparent, always-on-top window
## with its own 3D world, drawn at the pet's scale and camera, standing on the taskbar or a window
## top (`feet`, desktop px). It falls when what it stands on goes, and takes clicks on its rect.

signal pressed

const FEET := 12.0                   # px from the window's bottom to the prop's base (96 dpi): room for the pile's shadow

var node: Node3D
var feet := Vector2.ZERO
var ground := Rect2()                # the window it stands on; Rect2() = the taskbar
var fall_v := 0.0
var falling := false
var age := 0.0
var _k := 1.0
var _cam: Camera3D


## content: a PetProps node; px_per_m: the pet's scale; scale_m: the node's scale in his world.
func setup(content: Node3D, px_per_m: float, scale_m: float, k: float, pitch: float) -> void:
	_k = k
	node = content
	title = "prop"
	transparent_bg = true
	transparent = true
	borderless = true
	always_on_top = true
	unfocusable = true
	own_world_3d = true
	var h: float = float(content.get_meta("h", 1.0)) * scale_m * px_per_m
	var w: float = float(content.get_meta("w", 1.0)) * scale_m * px_per_m
	size = Vector2i(ceili(w * 1.25 + 12.0 * k), ceili(h * 1.15 + 14.0 * k + FEET * k))
	var root := Node3D.new()
	add_child(root)
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
	content.scale = Vector3.ONE * scale_m
	root.add_child(content)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = float(size.y) / px_per_m
	var th := deg_to_rad(pitch)
	var t := (float(size.y) / 2.0 - FEET * k) / px_per_m / cos(th)   # the base FEET px above the bottom
	_cam.rotation = Vector3(-th, 0, 0)
	_cam.position = Vector3(0, t, 0) + _cam.transform.basis.z * 20.0
	root.add_child(_cam)
	_cam.current = true
	window_input.connect(_on_input)


func place() -> void:
	position = Vector2i((feet - Vector2(size.x / 2.0, size.y - FEET * _k)).round())


func _on_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
		pressed.emit()


## Gone with a shrink, then freed.
func vanish(after := 0.0) -> void:
	if not is_instance_valid(node):
		return
	var tw := create_tween()
	tw.tween_interval(after)
	tw.tween_property(node, "scale", node.scale * 0.05, 0.3)
	tw.tween_callback(queue_free)
