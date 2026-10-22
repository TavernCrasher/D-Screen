class_name PetGround
extends RefCounted
## Where the desktop pet can stand: the taskbar (the bottom of the screen's usable rect) or the top
## edge of a window from pet/windows_feed.ps1 (rects topmost first, desktop pixels). A window top
## counts when the spot just above it isn't covered by a window higher in the stack, there is room
## for him below the screen's top, and his feet are `margin` inside its ends.

## Whether he still stands on `ground` (a rect from the last feed) at feet x.
static func stands_on(windows: Array, ground: Rect2, x: float, usable: Rect2, room: float, margin: float) -> bool:
	var i := _index(windows, ground)
	return i >= 0 and _edge_ok(windows, i, x, usable, room, margin)


## The surface he lands on falling from feet y0 to y1 at x: {"y": top, "rect": the window} (rect
## empty for the taskbar), or {} while nothing is crossed. The highest surface crossed wins. snap:
## a window top whose nearest standable spot is that close to x catches him too, with "x" the spot
## (dropped where two windows meet, just past the front one's end and over the covered part of the
## one behind, he fell through both, the user, 9d 11).
static func landing(windows: Array, x: float, y0: float, y1: float, usable: Rect2, room: float, margin: float,
		snap := 0.0) -> Dictionary:
	if y1 < y0:
		return {}
	var best := {}
	for i in windows.size():
		var r: Rect2 = windows[i]
		var top := r.position.y
		if top < y0 or top > y1:
			continue
		var at := x if _edge_ok(windows, i, x, usable, room, margin) else _nearest_spot(windows, i, x, usable, room, margin, snap)
		if is_nan(at):
			continue
		if best.is_empty() or top < float(best["y"]):
			best = {"y": top, "rect": r}
			if at != x:
				best["x"] = at
	var floor_y := usable.end.y
	if best.is_empty() and y1 >= floor_y:
		best = {"y": floor_y, "rect": Rect2()}
	return best


## The window `old` became in a new feed: itself, the same size moved (dragged), or resized from the
## same corner; the nearest wins. Rect2() when it's gone (closed, minimised).
static func follow(windows: Array, old: Rect2) -> Rect2:
	var best := Rect2()
	var best_d := INF
	for w in windows:
		var r: Rect2 = w
		var moved := absf(r.size.x - old.size.x) <= 2.0 and absf(r.size.y - old.size.y) <= 2.0
		var resized := r.position.distance_to(old.position) <= 2.0
		if not moved and not resized:
			continue
		var d := r.position.distance_to(old.position)
		if d < best_d and d < 800.0:
			best_d = d
			best = r
	return best


## Where he can leap from feet `from`: [{"x", "y", "rect"}]: window tops (other than `current`)
## at most max_up above him or anywhere below, whose nearest standable spot is within max_dx
## sideways, plus the taskbar when he's on a window.
static func reachable(windows: Array, from: Vector2, usable: Rect2, room: float, margin: float,
		max_up: float, max_dx: float, current: Rect2) -> Array:
	var out := []
	for i in windows.size():
		var r: Rect2 = windows[i]
		if r.is_equal_approx(current):
			continue
		var dy := from.y - r.position.y                     # > 0: above him
		if dy > max_up or absf(dy) < 30.0:
			continue
		var sp := span(r, margin + 10.0)
		if sp.x > sp.y:
			continue
		var x := clampf(from.x, sp.x, sp.y)
		if absf(x - from.x) > max_dx or not _edge_ok(windows, i, x, usable, room, margin):
			continue
		out.append({"x": x, "y": r.position.y, "rect": r})
	if current.size != Vector2.ZERO:
		out.append({"x": from.x, "y": usable.end.y, "rect": Rect2()})
	return out


## The feet-x span he can walk on a window.
static func span(r: Rect2, margin: float) -> Vector2:
	return Vector2(r.position.x + margin, r.end.x - margin)


static func _index(windows: Array, r: Rect2) -> int:
	for i in windows.size():
		if (windows[i] as Rect2).is_equal_approx(r):
			return i
	return -1


## The standable x on window i nearest x and at most `snap` from it, or NAN: the end of its walkable
## span, or just past a higher window covering its top.
static func _nearest_spot(windows: Array, i: int, x: float, usable: Rect2, room: float, margin: float, snap: float) -> float:
	if snap <= 0.0:
		return NAN
	var sp := span(windows[i], margin)
	if sp.x > sp.y:
		return NAN
	var tries := [clampf(x, sp.x, sp.y)]
	var r: Rect2 = windows[i]
	for j in i:
		var c: Rect2 = windows[j]
		if c.position.y <= r.position.y - 3.0 and c.end.y > r.position.y - 3.0:
			tries.append(clampf(c.position.x - 1.0, sp.x, sp.y))
			tries.append(clampf(c.end.x + 1.0, sp.x, sp.y))
	var best := NAN
	for t in tries:
		var tx := float(t)
		if absf(tx - x) <= snap and _edge_ok(windows, i, tx, usable, room, margin) \
				and (is_nan(best) or absf(tx - x) < absf(best - x)):
			best = tx
	return best


static func _edge_ok(windows: Array, i: int, x: float, usable: Rect2, room: float, margin: float) -> bool:
	var r: Rect2 = windows[i]
	if x < r.position.x + margin or x > r.end.x - margin:
		return false
	if r.position.y < usable.position.y + room or r.position.y >= usable.end.y:
		return false
	var above := Vector2(x, r.position.y - 3.0)
	for j in i:
		if (windows[j] as Rect2).has_point(above):
			return false
	return true


## The helper's rect list ("x0 y0 x1 y1;..." after its "w " / "t " tag) as Rect2s.
static func rects(list: String) -> Array:
	var out := []
	for part in list.strip_edges().split(";", false):
		var n := part.split(" ")
		if n.size() == 4:
			out.append(Rect2(float(n[0]), float(n[1]), float(n[2]) - float(n[0]), float(n[3]) - float(n[1])))
	return out


## The helper's last "w " or "t " line since the previous frame as rects, or null when none came.
## A bare "w " is a list too, an empty one: minimizing the last window he stood on sends it, and
## reading it as "no news" kept that window and left him standing in midair (9d 3, the beta tester's report).
static func feed_rects(line: String) -> Variant:
	return null if line == "" else rects(line.substr(2))


## His click box asleep (window px; feet at `x`, the ground line at `floor_y`): wide for one lying
## down, and as tall as he stands, since a floating baby sleeps up in the air (Poyomon drawn 197-319
## px down a 453 px window, the old low box 375-453: he couldn't be clicked or woken, 9d 2). Only
## his own pixels in it take the click (pet.gd _on_body), so the height costs nothing beside him.
static func sleep_rect(x: float, floor_y: float, body_w: float, model_px: float, top_px: float, feet: float, k: float) -> Rect2:
	var w := maxf(body_w, model_px * 1.4) * k
	var h := (feet + maxf(model_px * 0.6, top_px * 1.12)) * k
	return Rect2(x - w / 2.0, floor_y - h, w, h)


## How far below its place his window (top at `top_y`, `h` px tall) sits while his menu is open, so
## its top is on the screen (`usable_top`): Settings is nearly as tall as the window, and high on a
## window it opened past the screen's top (9d 4, the beta tester's report). Never so far that the `keep` px his
## body needs above the window's bottom leave it; he is drawn that much higher in it (cam.v_offset).
static func menu_drop(top_y: float, h: float, usable_top: float, keep: float) -> float:
	return clampf(usable_top - top_y, 0.0, maxf(0.0, h - keep))


## The menu's top (layer units) between `lo` and `hi` (the part of his window on the screen), 2 apart
## from each; one too tall for it keeps its top rows on the screen.
static func menu_y(y: float, size_y: float, lo: float, hi: float) -> float:
	return maxf(lo + 2.0, minf(y, hi - size_y - 2.0))


## A throw's speed (px/s): the mouse's travel over its last `window` s before the release, from
## `samples` ([time, Vector2] in order). A per-frame smoothing was dragged down by the slowing last
## frames of a flick (the user, 9d 10: he slowed the moment the mouse let go).
static func flick(samples: Array, now: float, window: float) -> Vector2:
	if samples.size() < 2:
		return Vector2.ZERO
	var last: Array = samples[-1]
	var first: Array = samples[0]
	for s in samples:
		if float(s[0]) >= now - window:
			first = s
			break
	if first == last:
		first = samples[-2]
	var dt := float(last[0]) - float(first[0])
	return (Vector2(last[1]) - Vector2(first[1])) / dt if dt > 0.0 else Vector2.ZERO


## The throw's speed caps (px/s): sideways enough to cross `screen_w` in about a second of flight
## (1800 px/s fell short of an ultrawide, 9d 10), never below `base`; up stays `base`, so a hard flick
## can't send him past the screen's top.
static func throw_cap(v: Vector2, screen_w: float, base: float) -> Vector2:
	var side := maxf(base, screen_w * 1.2)
	return Vector2(clampf(v.x, -side, side), clampf(v.y, -base, base))


## How far right of its place `x` his window of width `w` sits so it stays on `screen` (he is drawn
## that far left inside it, so his text box is never cut off), at most `lim` either way so he
## stays inside it.
static func view_offset(x: float, w: float, screen: Rect2, lim: float) -> float:
	var on := clampf(x, screen.position.x, screen.end.x - w)
	return clampf(on - x, -lim, lim)


## A yaw step toward `to` the shorter way round, as DW1's entities turn (rotateEntity).
static func turn(from: float, to: float, step: float) -> float:
	return wrapf(move_toward(from, from + wrapf(to - from, -180.0, 180.0), step), -180.0, 180.0)


const RIDE_EASE := 0.02              # s, the ride's time constant (the feed comes every 15 ms while windows move)


## What's left of a ride's step `off` (px) after `delta` s: his window eases the last step of the
## window or taskbar under him (the feed reports it every few frames) instead of jumping it, so
## he slides up and down with it.
static func ease_ride(off: Vector2, delta: float) -> Vector2:
	var left := off * exp(-delta / RIDE_EASE)
	return Vector2.ZERO if left.length() < 0.5 else left


## The props ring's centre height above his feet (px): `base`, raised so its front (`rx` px wide,
## props `half` px tall from their centre) stays above `bottom` and lowered so its back stays under
## `top` (desktop y; his feet at `feet`). The bottom wins: the ring dipped below the screen when he
## stood low (the user, 2026-10-18). The ring's centre dips rx * (0.3 cos + sin) at its front on
## the tilted camera (pet_place.gd: 0.3 rx of height, rx of depth).
static func ring_height(base: float, feet: float, bottom: float, top: float, rx: float, half: float, pitch: float) -> float:
	var th := deg_to_rad(pitch)
	var amp := rx * (0.3 * cos(th) + sin(th))
	var lo := (feet - bottom + amp + half) / cos(th)
	var hi := (feet - top - amp - half) / cos(th)
	return maxf(minf(base, hi), lo)


## The ring's radius (px), narrowed so it fits between `top` and `bottom` (desktop y) with its props
## (`half` px from their centre): high on a window, there isn't room under the screen's top for the
## full ring above his window's bottom (Ninjamon at feet 213 lost his back props past the top).
static func ring_fit(rx: float, bottom: float, top: float, half: float, pitch: float) -> float:
	var th := deg_to_rad(pitch)
	return clampf((bottom - top - 2.0 * half) / (2.0 * (0.3 * cos(th) + sin(th))), 0.0, rx)


## Whether `img` (his window's last frame) has a drawn pixel within `slack` px of `p`: his click
## area follows his own pixels, not a box around his farthest reach (the user, 2026-10-18: a click
## beside Tyrannomon got him).
static func opaque_near(img: Image, p: Vector2i, slack: int) -> bool:
	var step := maxi(1, slack / 2)
	for y in range(p.y - slack, p.y + slack + 1, step):
		for x in range(p.x - slack, p.x + slack + 1, step):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and img.get_pixel(x, y).a > 0.1:
				return true
	return false


## `usable` with its bottom on the top of a taskbar along `screen`'s bottom when that is higher. An
## auto-hidden taskbar leaves the whole screen usable to Windows; slid up, he stands on it, and he
## rides it down as it hides (2 px of it stay on the screen).
static func floor_rect(usable: Rect2, screen: Rect2, bars: Array) -> Rect2:
	var y := usable.end.y
	for b in bars:
		var r: Rect2 = b
		var across := minf(r.end.x, screen.end.x) - maxf(r.position.x, screen.position.x)
		if across >= screen.size.x * 0.5 and r.position.y > screen.get_center().y and r.position.y < screen.end.y:
			y = minf(y, r.position.y)
	return Rect2(usable.position, Vector2(usable.size.x, maxf(0.0, y - usable.position.y)))
