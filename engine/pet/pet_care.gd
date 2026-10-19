class_name PetCare
extends RefCounted
## The pet's side of the v-pet save (docs/vpet_save.md): his file (vpet_NN.json) and the care rules
## (Vpet) on it. He is its only writer: written at once after anything that changes his totals,
## else every WRITE_EVERY s while his clock runs, and on quit; a failed write keeps the .tmp and
## retries a second later (VpetSave.write_pet). Without a save (Ninjamon, --partner) the same rules
## run in memory and nothing is written.

const WRITE_EVERY := 30.0

var link: Dictionary
var slot := -1
var d: Dictionary
var writable := false
var rng := DwRng.new()
var _dirty := false
var _next_write := 0.0


func _init(link_: Dictionary, writable_ := true) -> void:
	link = link_
	slot = int(link.get("slot", -1))
	writable = writable_ and slot >= 0 and str(link.get("partner_uid", "")) != ""
	var found := VpetSave.read_pet(slot) if writable else {}
	if writable and found.is_empty() and _any_copy():
		# copies that don't parse: set aside (never deleted) before a new file can push them out
		# through its .bak (PET-7); if they won't move, nothing is written this run
		var moved := VpetSave.archive_pet(slot)
		push_warning("pet: his file couldn't be read; set aside as %s" % moved)
		writable = not _any_copy()
	d = Vpet.adopt(found, link)
	_dirty = writable                               # written at once: a new or adopted file exists on disk


func _any_copy() -> bool:
	for ext in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(VpetSave.pet_path(slot) + ext):
			return true
	return false


## The day his caps count in: the local date, but never before the latest time seen (Vpet.day_of).
func today() -> String:
	return Vpet.day_of(d, Time.get_unix_time_from_system())


## Advances his clock by dt active seconds; returns Vpet's events.
func tick(dt: float, now: float, x: float, y: float) -> Array:
	var ev := Vpet.tick(d, link, dt, today(), rng, x, y)
	if dt > 0.0:
		_dirty = true
	if not ev.is_empty():
		_next_write = 0.0
	flush(now)
	return ev


func flush(now: float, force := false) -> void:
	if not writable or not _dirty or (not force and now < _next_write):
		return
	if VpetSave.write_pet(slot, d):
		_dirty = false
		_next_write = now + WRITE_EVERY
	else:
		_next_write = now + 1.0


func _changed() -> void:
	_dirty = true
	_next_write = 0.0


func hungry() -> bool:
	return Vpet.is_hungry(d)


func needs_toilet() -> bool:
	return Vpet.needs_toilet(d)


func feed() -> bool:
	var ok := Vpet.feed(d, today(), rng)
	if ok:
		_changed()
	return ok


func use_toilet() -> bool:
	var ok := Vpet.use_toilet(d, link, today(), rng)
	if ok:
		_changed()
	return ok


func train(station: String) -> Dictionary:
	var r := Vpet.train(d, link, station, today())
	_changed()
	return r


## A praise or scold; true when it counted (shown even when the day's cap took the point).
func praise() -> bool:
	var counts := Vpet.praise_counts(d)
	Vpet.praise(d, today())
	if counts:
		_changed()
	return counts


func scold() -> bool:
	var counts := Vpet.scold_deserved(d)
	Vpet.scold(d, today())
	if counts:
		_changed()
	return counts


func task_done() -> void:
	Vpet.task_done(d)
	_changed()


func clean(id: int) -> bool:
	var ok := Vpet.clean(d, id)
	if ok:
		_changed()
	return ok


func piles() -> Array:
	return d["live"]["piles"]
