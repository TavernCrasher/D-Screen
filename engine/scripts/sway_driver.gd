class_name SwayDriver
extends Node
## Secondary motion of free-hanging cloth (Ninjamon's scarf tails and hood flap, custom_sway.gdshaderinc).
## Samples a point on the head/torso bone (animation and world movement both count), and lets a damped
## spring chase "minus the velocity times a lag": the cloth trails behind a run, flaps up when the model falls
## and whips about when the head turns. The result, `sway_lag` (mesh-local metres), goes to the shaders.

var skeleton: Skeleton3D
var bone := -1
var probe := Vector3.ZERO           # sampled point in the bone's frame (up on the head, so turns register)
var mesh: Node3D                    # a mesh instance: its basis turns world vectors to mesh-local ones
var materials: Array[ShaderMaterial] = []
var lag_time := 0.12                # s: how far the cloth trails (lag = -velocity * lag_time at rest)
var omega := 13.0                   # spring rad/s
var zeta := 0.3                     # damping: below 1 so it overshoots and flaps
var max_lag := 0.25                 # m
var lag := Vector3.ZERO
var _lag_v := Vector3.ZERO
var _last := Vector3.ZERO
var _vel := Vector3.ZERO
var _have := false


func _process(delta: float) -> void:
	if skeleton == null or not skeleton.is_inside_tree() or delta <= 0.0:
		return
	var p := skeleton.global_transform * (skeleton.get_bone_global_pose(bone) * probe)
	if not _have:
		_last = p
		_have = true
		return
	var v := (p - _last) / delta
	_last = p
	if v.length() > 40.0:
		v = Vector3.ZERO                # a teleport (map change, snap), not a movement
	_vel = _vel.lerp(v, minf(1.0, delta * 14.0))
	var basis_inv := mesh.global_transform.basis.orthonormalized().inverse()
	var target := basis_inv * (-_vel * lag_time)
	# the spring runs in small steps so a long frame doesn't blow it up
	var steps := maxi(1, ceili(delta / 0.01))
	var h := delta / steps
	for i in steps:
		var acc := omega * omega * (target - lag) - 2.0 * zeta * omega * _lag_v
		_lag_v += acc * h
		lag += _lag_v * h
	if lag.length() > max_lag:
		lag = lag.normalized() * max_lag
	for m in materials:
		m.set_shader_parameter("sway_lag", lag)
		m.set_shader_parameter("sway_lag_scale", DigimonModel.sway_scale)
