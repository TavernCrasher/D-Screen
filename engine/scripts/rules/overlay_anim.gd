class_name OverlayAnim
extends RefCounted
## One map-object instance's frame loop (FUN_800b43c0): up to 8 frames, each shown for its
## duration in 20 fps frames (0 = 256), looping; -2 is a blank frame. The timer runs even
## while the instance is hidden or off screen. Builtin 0x15 (FUN_800b5c64) resets it.

var frames: Array = []               # [[object index or -2, duration], ...]
var frame := 0
var timer := 0


func _init(frames_: Array) -> void:
	frames = frames_


## The object shown now, or -2 for a blank frame.
func current() -> int:
	return int(frames[frame][0]) if not frames.is_empty() else -2


## One 20 fps tick; true when the frame changed.
func tick() -> bool:
	if frames.size() < 2:
		return false
	timer += 1
	if timer < int(frames[frame][1]):
		return false
	timer = 0
	frame = (frame + 1) % frames.size()
	return true


func reset() -> void:
	frame = 0
	timer = 0
