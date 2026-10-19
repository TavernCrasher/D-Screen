class_name StoryState
extends RefCounted
## Persistent DW1 script state: story triggers (flags), pstats (script variables), money,
## inventory and names. Script semantics: include/dw/script.h (jype0/dw_decomp PR #96).

const TRIGGER_COUNT := 4096

var triggers := PackedByteArray()     # 1 byte per trigger for simplicity
var pstats := PackedByteArray()       # 256 script variables
var money := 0
var price := 0                        # SCRIPT_PRICE (0x8013500c): builtins 0x1E/0x1F/0x38, {PRICE}
var time_speed := 0                   # SCRIPT_SAVED_TIME_SPEED, builtin 0x19 (not used yet)
var merit := 0
var battles := 0                      # 0x80134fc8: battles fought (script op 0x66, cap 9999)
var flees := 0                        # 0x80134fca: battles fled
var tournament_titles := 0            # 0x80134fcc: tournaments won (script stat 17)
var tournament_wins := 0              # 0x80134fce: tournament rounds won (stat 18)
var tournament_losses := 0            # 0x80134fd0: tournaments lost (stat 19)
var fish_caught := 0                  # 0x801384BE: fish landed (also when not kept); kept on rebirth
var bank: Array = []                  # story block +0x54: the Item Keeper, one count per item id (max 99)
var daily_cards: Array = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]   # story block 0-5: today's single cards
var dirt_pile := 15                   # 0x80134424: Drimogemon's dirt pile (not saved, session only)
var inventory := Inventory.new()     # shared with CareSim (main.gd)
var player_name := "Tamer"
var partner_name := ""
var learned_cards := {}
var recycle: Array = []               # story block +6: 78 counts of items lost in battle (items.json recycle_slot)


func _init() -> void:
	recycle.resize(78)
	recycle.fill(0)
	triggers.resize(TRIGGER_COUNT)
	pstats.resize(256)


func is_set(t: int) -> bool:
	return t >= 0 and t < TRIGGER_COUNT and triggers[t] != 0


func set_trigger(t: int, on := true) -> void:
	if t >= 0 and t < TRIGGER_COUNT:
		triggers[t] = 1 if on else 0


func pstat(i: int) -> int:
	return pstats[i & 0xFF]


func set_pstat(i: int, v: int) -> void:
	pstats[i & 0xFF] = v & 0xFF


func item_count(item: int) -> int:
	return inventory.count(item)


func give_item(item: int, n: int) -> bool:
	return inventory.give(item, n)


func take_item(item: int, n: int) -> void:
	inventory.take(item, n)
