class_name DwRng
extends RefCounted
## Random numbers with DW1's semantics: rand(n) returns 0..n-1 (FUN_800a36d4).
## Tests can queue fixed results with push().

var _rng := RandomNumberGenerator.new()
var _queued: Array = []


func _init(seed_value: int = 0) -> void:
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


func rand(n: int) -> int:
	if n <= 0:                                           # FUN_800a36d4: n * rand() >> 15 = 0
		return 0
	if not _queued.is_empty():
		return mini(_queued.pop_front(), n - 1)
	return _rng.randi() % n


func push(values: Array) -> void:
	_queued.append_array(values)
