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
## empty for the taskbar), or {} while nothing is crossed. The highest surface crossed wins.
static func landing(windows: Array, x: float, y0: float, y1: float, usable: Rect2, room: float, margin: float) -> Dictionary:
	if y1 < y0:
		return {}
	var best := {}
	for i in windows.size():
		var r: Rect2 = windows[i]
		var top := r.position.y
		if top < y0 or top > y1 or not _edge_ok(windows, i, x, usable, room, margin):
			continue
		if best.is_empty() or top < float(best["y"]):
			best = {"y": top, "rect": r}
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
