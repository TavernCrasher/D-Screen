class_name Services
extends RefCounted
## The rules behind DW1's service builtins (docs/scripts.md "Builtins"): the daily rollover,
## cards (pack, single, selling), the merit shop, the Item Keeper, Birdramon's transport,
## Mojyamon's collector trades and the tournament medal. The menus live in script_host.gd.
## Data: GameData.services (tools/dump_tables.py services()).

const CARD_MAX := 9                  # 4-bit counts at story block +0xD4, capped at 9
const BANK_MAX := 99
const MERIT_MAX := 9999
const MONEY_MAX := 999999
const MEDAL_TRIGGER := 0x16C         # + medal id: owned (FUN_800ff830)
const COLLECTOR_TRIGGER := 5         # + set * 3 + i: that trade done; 14 = all nine
const COLLECTOR_ALL := 14


# ---------------------------------------------------------------- daily rollover
## FUN_800fc374 (main.c:47333), at every new day: six new single cards (1..64, never 4;
## vanilla's duplicate check compares a slot with itself, so repeats can happen), the day
## counters pstats 28-31 +1 unless 0xFF, pstat 2 &= 0x7F unless 0xFF.
static func daily_rollover(st: StoryState, rng: DwRng) -> void:
	for i in 6:
		st.daily_cards[i] = 0xFF
	for i in 6:
		var c := rng.rand(64) + 1
		while c == 4:
			c = rng.rand(64) + 1
		st.daily_cards[i] = c
	for k in range(28, 32):
		if st.pstat(k) != 0xFF:
			st.set_pstat(k, (st.pstat(k) + 1) & 0xFF)
	if st.pstat(2) != 0xFF:
		st.set_pstat(2, st.pstat(2) & 0x7F)


# ---------------------------------------------------------------- cards
static func card(data, id: int) -> Dictionary:
	return data.services["cards"][id]


static func card_count(st: StoryState, id: int) -> int:
	return int(st.learned_cards.get(id, 0))


static func set_card_count(st: StoryState, id: int, n: int) -> void:
	if n <= 0:
		st.learned_cards.erase(id)
	else:
		st.learned_cards[id] = mini(n, CARD_MAX)


static func card_price(data, id: int) -> int:
	return int(data.services["card_prices"][int(card(data, id)["rarity"])])


## FUN_80106e0c (main.c:54283): r = random(100) -> rarity 0 (r = 0), 1 (<= 4), 2 (<= 19),
## 3 (<= 49), else 4.
static func pack_rarity(r: int) -> int:
	if r == 0:
		return 0
	if r <= 4:
		return 1
	if r <= 19:
		return 2
	if r <= 49:
		return 3
	return 4


static func rarity_pool(data, rarity: int) -> Array:
	var out := []
	for c in data.services["cards"]:
		if int(c["rarity"]) == rarity:
			out.append(int(c["id"]))
	return out


## One pack card (500 bits paid by the script): the line by the count before (FUN_80106f18:
## new: rarity 0 -> 2, 1 -> 3, else 4; 1-5 -> 5; 6+ -> 6), +1 below 9, pstat 249 = its Digimon.
static func draw_pack(st: StoryState, data, rng: DwRng) -> Dictionary:
	var rarity := pack_rarity(rng.rand(100))
	var pool := rarity_pool(data, rarity)
	var id: int = pool[rng.rand(pool.size())]
	var before := card_count(st, id)
	var msg := 5
	if before == 0:
		msg = 2 if rarity == 0 else (3 if rarity == 1 else 4)
	elif before >= 6:
		msg = 6
	if before < CARD_MAX:
		set_card_count(st, id, before + 1)
	st.set_pstat(249, int(card(data, id)["digimon"]))
	return {"card": id, "msg": msg}


## FUN_80107000: a daily card row is enabled with money >= its price and fewer than 9 held.
static func single_enabled(st: StoryState, data, id: int) -> bool:
	return id != 0xFF and st.money >= card_price(data, id) and card_count(st, id) <= CARD_MAX - 1


static func buy_single(st: StoryState, data, slot: int) -> bool:
	var id: int = st.daily_cards[slot]
	if not single_enabled(st, data, id):
		return false
	set_card_count(st, id, card_count(st, id) + 1)
	st.money -= card_price(data, id)
	st.daily_cards[slot] = 0xFF
	return true


## Selling n of a card at half its price (FUN_800fcfb8 amount box).
static func sell_cards(st: StoryState, data, id: int, n: int) -> void:
	n = mini(n, card_count(st, id))
	st.money = mini(st.money + n * (card_price(data, id) / 2), MONEY_MAX)
	set_card_count(st, id, card_count(st, id) - n)


# ---------------------------------------------------------------- merit shop
## Room for one more of item: a slot already holding it below 99, or a free slot.
static func bag_room(inv: Inventory, item: int) -> bool:
	for i in inv.size:
		if inv.types[i] == item:
			return inv.amounts[i] < Inventory.MAX_STACK
	for i in inv.size:
		if inv.types[i] == Inventory.NONE:
			return true
	return false


## FUN_80108230: the card's merit, the line 7 + rarity; giving it: merit += value (9999 cap).
static func give_card_for_merit(st: StoryState, data, id: int) -> void:
	st.merit = mini(st.merit + int(card(data, id)["merit"]), MERIT_MAX)
	set_card_count(st, id, card_count(st, id) - 1)


static func merit_items(data) -> Array:
	var out := []
	for it in data.items:
		if int(it.get("merit", 0)) != 0:
			out.append(int(it["id"]))
	return out


## FUN_801072c4: enabled with merit >= cost and room in the bag. Vanilla also enables an item
## held at 99 when another slot is free, then loses the merit; the remake keeps it disabled
## (SCR-29, the user's call).
static func merit_enabled(st: StoryState, inv: Inventory, data, item: int) -> bool:
	return st.merit >= int(data.items[item]["merit"]) and bag_room(inv, item)


static func buy_merit(st: StoryState, inv: Inventory, data, item: int) -> bool:
	if not merit_enabled(st, inv, data, item):
		return false
	st.merit -= int(data.items[item]["merit"])
	inv.give(item, 1)
	return true


# ---------------------------------------------------------------- item keeper
static func bank_count(st: StoryState, item: int) -> int:
	if st.bank.size() < 128:
		st.bank.resize(128)
		for i in 128:
			if st.bank[i] == null:
				st.bank[i] = 0
	return int(st.bank[item])


## FUN_801086e0 / 80108890 / 80108a98: move 1 (Cross), 10 (Circle: source >= 10 and
## destination < 90) or all that fits (Square). to_bag: from the Keeper into the bag.
## Returns how many moved.
static func keeper_move(st: StoryState, inv: Inventory, item: int, to_bag: bool, mode: String) -> int:
	var src := bank_count(st, item) if to_bag else inv.count(item)
	var dst := inv.count(item) if to_bag else bank_count(st, item)
	var n := 0
	match mode:
		"one":
			n = 1 if src >= 1 and dst < BANK_MAX else 0
		"ten":
			n = 10 if src >= 10 and dst < BANK_MAX - 9 else 0
		"all":
			n = mini(src, BANK_MAX - dst)
	if n <= 0:
		return 0
	if to_bag:
		if not inv.give(item, n):
			return 0
		st.bank[item] = src - n
	else:
		inv.take(item, n)
		st.bank[item] = dst + n
	return n


# ---------------------------------------------------------------- transport
## FUN_80107ab8: the destinations whose trigger is set; enabled with money >= price.
static func destinations(st: StoryState, data) -> Array:
	var out := []
	var names: Array = data.services.get("area_names", [])
	for i in data.services["transport"].size():
		var t: Dictionary = data.services["transport"][i]
		if not st.is_set(int(t["trigger"])):
			continue
		var label := ""
		var e := FieldMap.entry(int(t["map"]))
		if not e.is_empty() and int(e.get("loading_name", -1)) < names.size():
			label = str(names[int(e["loading_name"])]).strip_edges()
		out.append({"index": i, "map": int(t["map"]), "exit": int(t["exit"]), "price": int(t["price"]),
			"label": label, "enabled": st.money >= int(t["price"])})
	return out


## Taking it: pstat 247 = map, 248 = exit, money -= price; the script goes on at MAPHEAD
## section 1251 ("Hold on tight!", change_screen_pstat 247).
static func take_transport(st: StoryState, data, index: int) -> void:
	var t: Dictionary = data.services["transport"][index]
	st.set_pstat(247, int(t["map"]))
	st.set_pstat(248, int(t["exit"]))
	st.money -= int(t["price"])


# ---------------------------------------------------------------- collector
static func collector_want(data, set_i: int, i: int) -> int:
	return int(data.services["collector_want"][set_i * 3 + i])


static func collector_give(data, set_i: int, i: int) -> int:
	return int(data.services["collector_give"][set_i * 3 + i])


## The trade (FUN_8010c4b0 state 5): the offered item first; no room -> "full" and nothing
## taken. Then the wanted item ×1, trigger 5 + set·3 + i, and 14 once 5..13 are all set.
static func collector_trade(st: StoryState, inv: Inventory, data, set_i: int, i: int) -> String:
	var want := collector_want(data, set_i, i)
	if not inv.has(want):
		return "missing"
	if not inv.give(collector_give(data, set_i, i), 1):
		return "full"
	inv.take(want, 1)
	st.set_trigger(COLLECTOR_TRIGGER + set_i * 3 + i, true)
	var all := true
	for k in 9:
		all = all and st.is_set(COLLECTOR_TRIGGER + k)
	if all:
		st.set_trigger(COLLECTOR_ALL, true)
	return "ok"


# ---------------------------------------------------------------- medal
## FUN_800e6fe8: the first complete group decides (cups 15-20, 21-25, 26-32, 33-36;
## tournament battle wins >= 100; every card and trigger 50); -1 = none. If that group's medal
## is owned, nothing (vanilla quirk).
static func medal_group(st: StoryState, data, tournament_wins := 0) -> int:
	for g in [[0, 15, 20], [1, 21, 25], [2, 26, 32], [3, 33, 36]]:
		var ok := true
		for t in range(g[1], g[2] + 1):
			ok = ok and st.is_set(t)
		if ok:
			return g[0]
	if tournament_wins >= 100:
		return 4
	if st.is_set(50):
		var all := true
		for c in data.services["cards"].size():
			all = all and card_count(st, c) >= 1
		if all:
			return 5
	return -1


## Awards the group's medal; returns the group shown, or -1 when nothing happens.
static func award_medal(st: StoryState, data, tournament_wins := 0) -> int:
	var g := medal_group(st, data, tournament_wins)
	if g < 0:
		return -1
	var t := MEDAL_TRIGGER + int(data.services["medal_ids"][g])
	if st.is_set(t):
		return -1
	st.set_trigger(t, true)
	return g


## FUN_800ab66c (main.c:11367), every frame the tamer can walk: the record medals, checked in
## DW1's order. 5: every technique 0-56 learned (bitfield 0x80155800); 7: HP and MP 9999,
## Offense / Defense / Speed / Brains 999; 13: 999999 bits; 14: year 10 (0x80134F02);
## 6: every Digimon 1-61 raised (triggers 0x200 + id), which also raises the tamer level by
## one (capped at 10, no "Tamer level went up"); 9: more than 99 fish caught; 12: every card
## 0-65 owned. Returns the medals awarded (DW1 then shows "Congratulations!" once).
static func check_medals(st: StoryState, sim) -> Array:
	var got := []
	var p: Partner = sim.p
	var award := func(m: int) -> void:
		st.set_trigger(MEDAL_TRIGGER + m, true)
		got.append(m)
	if not st.is_set(MEDAL_TRIGGER + 5):
		var all := true
		for t in 0x39:
			all = all and p.techniques.has(t)
		if all:
			award.call(5)
	if not st.is_set(MEDAL_TRIGGER + 7) and p.max_hp == 9999 and p.max_mp == 9999 \
			and p.off == 999 and p.def == 999 and p.brn == 999 and p.spd == 999:
		award.call(7)
	if not st.is_set(MEDAL_TRIGGER + 13) and st.money == MONEY_MAX:
		award.call(13)
	if not st.is_set(MEDAL_TRIGGER + 14) and sim.year == 10:
		award.call(14)
	if not st.is_set(MEDAL_TRIGGER + 6):
		var all := true
		for id in range(1, 0x3E):
			all = all and st.is_set(CareSim.RAISED_TRIGGER + id)
		if all:
			award.call(6)
			sim.tamer_level = mini(sim.tamer_level + 1, 10)
	if not st.is_set(MEDAL_TRIGGER + 9) and st.fish_caught > 99:
		award.call(9)
	if not st.is_set(MEDAL_TRIGGER + 12):
		var all := true
		for c in 0x42:
			all = all and card_count(st, c) != 0
		if all:
			award.call(12)
	return got
