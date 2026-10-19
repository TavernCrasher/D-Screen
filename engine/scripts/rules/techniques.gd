class_name Techniques
extends RefCounted
## Equipped techniques (Stats.moves 0x801557EC..EF): three slots the player fills in the
## DIGIMON menu's Tech chart, plus the species' finisher. Kept apart from the learned set
## (Partner.techniques, the bitfield at 0x80155800). Partner.moves holds technique ids,
## -1 = empty.

const LEARNABLE := 0x3A
## Tech chart rows (FUN_800ba4d4): Fire, Battle, Air, Earth, Ice, Mech, Filth; 8 columns.
const ROW_BLOCK := [0, 5, 1, 4, 2, 3, 6]
const ROW_NAMES := ["Fire", "Battle", "Air", "Earth", "Ice", "Mech", "Filth"]
## Chart cells that also stand for a paired technique a species may list instead.
const CELL_ALIAS := {44: 48, 55: 57}


## Technique id of chart cell (row 0-6, col 0-7); ids from 48 up are shifted by one, so 48
## and 57 have no cell of their own.
static func cell_tech(row: int, col: int) -> int:
	var id: int = ROW_BLOCK[row] * 8 + col
	return id + 1 if id >= 48 else id


static func species_moves(data, id: int) -> Array:
	var out := []
	for t in data.digimon[id]["techniques"]:
		out.append(int(t["id"]))
	return out


## FUN_800a442c / EVL: the finisher is the last list entry in 0x3A..0x70 (none for babies).
## H-Kabuterimon's index 14 resolves to High Electro Shocker (FUN_800e6000).
static func finisher_for(data, id: int) -> int:
	var list := species_moves(data, id)
	for i in range(list.size() - 1, -1, -1):
		if list[i] >= 0x3A and list[i] <= 0x70:
			return slot_move(data, id, i)
	return -1


## The move in slot n of a species' list as the game uses it (FUN_800e6000): H-Kabuterimon's
## index 14 is High Electro Shocker (112), not the listed Electro Shocker.
static func slot_move(data, id: int, n: int) -> int:
	return 112 if id == 0x3C and n == 14 else int(data.digimon[id]["techniques"][n]["id"])


## The first species move for a cell's technique (or its alias), or -1.
static func _in_species(data, id: int, tech: int) -> int:
	for t in species_moves(data, id):
		if t == tech or t == CELL_ALIAS.get(tech, -2):
			return t
	return -1


## Cross on a chart cell (main.c:17907-17918, FUN_800ba654): an equipped technique is
## unequipped (slots aren't compacted); otherwise it must be learned and in the species' list,
## and goes into the lowest empty slot. Returns "unequip", "equip" or "" (buzzer).
static func press_cell(data, p: Partner, row: int, col: int) -> String:
	var tech := cell_tech(row, col)
	for s in 3:
		var m: int = p.moves[s]
		if m >= 0 and (m == tech or m == CELL_ALIAS.get(tech, -2)):
			p.moves[s] = -1
			return "unequip"
	if not p.techniques.has(tech) and not p.techniques.has(CELL_ALIAS.get(tech, -2)):
		return ""
	var t := _in_species(data, p.id, tech)
	if t < 0 or not p.techniques.has(t):
		return ""
	for s in 3:
		if p.moves[s] < 0:
			p.moves[s] = t
			return "equip"
	return ""


## Triangle leaves the chart only with at least one equipped move of power above 0.
static func can_close(data, p: Partner) -> bool:
	for s in 3:
		if p.moves[s] >= 0 and int(data.techniques[p.moves[s]]["power"]) != 0:
			return true
	return false


## Old saves (before equipped moves): the first three learned moves of the species.
static func default_moves(data, p: Partner) -> Array:
	var m := [-1, -1, -1, finisher_for(data, p.id)]
	var s := 0
	for t in species_moves(data, p.id):
		if s < 3 and p.techniques.has(t) and not (t >= 0x3A and t <= 0x70):
			m[s] = t
			s += 1
	if s == 0:
		var list := species_moves(data, p.id)
		if not list.is_empty():
			m[0] = list[0]
	return m
