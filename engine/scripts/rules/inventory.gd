class_name Inventory
extends RefCounted
## The tamer's bag (DW1-SydPatches Inventory.cpp; vanilla INVENTORY_ITEM_TYPES/AMOUNTS):
## 30 ordered slots of which `size` are usable (10 at the start, raised by scripts), up to
## 99 of one item per slot. Shared by the care rules and the script VM.

const SLOTS := 30
const MAX_STACK := 99
const NONE := -1
## InventoryUI sortOrder: for sort mode 0 Battle / 1 Raise / 2 Basic, the rank of each
## item sort group (items.json "sort").
const SORT_ORDER := [[0, 1, 3, 2, 5, 4], [2, 3, 0, 5, 4, 1], [1, 2, 0, 3, 5, 4]]

var types := PackedInt32Array()
var amounts := PackedInt32Array()
var size := 10


func _init() -> void:
	types.resize(SLOTS)
	types.fill(NONE)
	amounts.resize(SLOTS)


## getItemCount: the first slot holding the item.
func count(item: int) -> int:
	for i in size:
		if types[i] == item:
			return amounts[i]
	return 0


func has(item: int) -> bool:
	return count(item) > 0


## giveItem: tops up the item's slot (fails if it already holds 99), else takes the first
## free slot. False = no room.
func give(item: int, n := 1) -> bool:
	for i in size:
		if types[i] == item:
			if amounts[i] >= MAX_STACK:
				return false
			amounts[i] = mini(amounts[i] + n, MAX_STACK)
			return true
	for i in size:
		if types[i] == NONE:
			types[i] = item
			amounts[i] = n
			return true
	return false


## removeItem
func take(item: int, n := 1) -> void:
	for i in size:
		if types[i] != item:
			continue
		amounts[i] = maxi(amounts[i] - n, 0)
		if amounts[i] == 0:
			types[i] = NONE


func swap(a: int, b: int) -> void:
	var t := types[a]
	types[a] = types[b]
	types[b] = t
	var n := amounts[a]
	amounts[a] = amounts[b]
	amounts[b] = n


## sortItems: by group rank for the mode, then item id; empty slots last.
func sort(mode: int, items: Array) -> void:
	var order: Array = SORT_ORDER[mode]
	var entries := []
	for i in SLOTS:
		var rank := 255 if types[i] == NONE else int(order[int(items[types[i]]["sort"])])
		var key := (types[i] if types[i] != NONE else 0) + rank * 256
		entries.append([key, types[i], amounts[i]])
	entries.sort_custom(func(a, b): return a[0] < b[0])
	for i in SLOTS:
		types[i] = entries[i][1]
		amounts[i] = entries[i][2]


## Non-empty slots as [slot, item, amount] (the inventory screen lists all `size` slots).
func filled() -> Array:
	var out := []
	for i in size:
		if types[i] != NONE:
			out.append([i, types[i], amounts[i]])
	return out


func _filled_slots() -> Array:
	var out := []
	for i in size:
		if types[i] != NONE:
			out.append(i)
	return out


## FUN_800fc0dc (battle lost): 30% of the filled slots (rounded down) are lost. Each time a
## slot is picked at random among those still filled and its whole stack goes; the amount
## is added to the recycle shop's count for that item (max 99). Returns how many (pstat 200).
func lose_on_defeat(rng: DwRng, items: Array, recycle: Array) -> int:
	var n := _filled_slots().size() * 30 / 100
	for k in n:
		var slots := _filled_slots()
		var slot: int = slots[rng.rand(slots.size())]
		var item := types[slot]
		var r: int = items[item].get("recycle_slot", -1)
		if r >= 0:
			recycle[r] = mini(int(recycle[r]) + amounts[slot], 99)
		take(item, MAX_STACK)
	return n
