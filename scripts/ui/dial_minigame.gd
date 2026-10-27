extends Control
## Gem-setting minigame, inspired by the Starcatcher fishing mod for Minecraft.
##
## A needle sweeps around a ring. Glowing "gem slots" sit on the ring; press
## Space / E / click while the needle is over one.
##   - Hit  -> progress goes up, the slot jumps somewhere else on the ring.
##   - Miss -> progress drops by the penalty (and your perfect run is gone).
##   - Progress also drains slowly once you've started, so keep hitting.
##   - Fill the bar to finish. Drop below zero and the piece is botched.
## Special slots: thin (worth more), flip (reverses the needle), fading
## (disappears unless you hit it in time), drifting (slides around the ring)
## and the green *treasure* slot which fills a bonus meter: complete it for
## +1 quality tier.
##
## All numbers live in data/dial_minigame.json.

signal finished(quality: int)

const RADIUS := 110.0
const RING_W := 18.0
const TREASURE_GOAL := 100.0
const START_PROGRESS := 20.0
const MIN_GAP_FROM_NEEDLE := 45.0  # new slots never spawn right under the needle

var hp := 75.0
var speed := 150.0          # degrees per second
var penalty := 5.0
var decay := 4.0
var progress := START_PROGRESS
var treasure := 0.0
var has_treasure := false
var needle := 0.0           # degrees, 0 = top, clockwise
var direction := 1.0
var started := false        # decay only starts after the first press
var hits := 0
var misses := 0
var spots: Array = []       # [{type, pos, size, reward, color, flip, vanish, move, treasure, alpha}]

var _done := false
var _particles: Array = []
var _shake := 0.0
var _flash := ""
var _flash_t := 0.0


## `power` picks the difficulty (unless the recipe names one with "dial").
func configure(station_level: int, recipe_power: int, override := "") -> void:
	var cfg: Dictionary = DataDB.dial
	var diff := override
	if diff == "":
		diff = "easy" if recipe_power <= 5 else ("medium" if recipe_power <= 11 else "hard")
	var d: Dictionary = cfg["difficulties"][diff]
	hp = float(d["hp"])
	speed = float(d["speed"])
	penalty = float(d["penalty"])
	decay = float(d["decay"]) * maxf(0.4, 1.0 - 0.15 * (station_level - 1))
	var bonus_size := 3.0 * (station_level - 1)  # upgrades widen every slot
	spots = []
	var types: Array = d["spots"].duplicate()
	has_treasure = randf() < float(d["treasure_chance"])
	if has_treasure:
		types.append("treasure")
	for t in types:
		var st: Dictionary = cfg["spot_types"][t]
		var spot := {
			"type": t,
			"size": float(st["size"]) + bonus_size,
			"reward": float(st["reward"]),
			"color": Color(st["color"]),
			"flip": st.get("flip", false),
			"vanish": float(st.get("vanish", 0.0)),
			"move": float(st.get("move", 0.0)) * (1 if randf() < 0.5 else -1),
			"treasure": st.get("treasure", false),
			"alpha": 1.0,
			"pos": 0.0,
		}
		spot["pos"] = free_position(spot["size"])
		spots.append(spot)


func _ready() -> void:
	custom_minimum_size = Vector2(700, 330)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# --- Rules -------------------------------------------------------------------

static func angle_dist(a: float, b: float) -> float:
	var d := fposmod(a - b, 360.0)
	return minf(d, 360.0 - d)


## A random ring position that doesn't overlap other slots or the needle.
func free_position(size: float) -> float:
	for attempt in 60:
		var p := randf() * 360.0
		if angle_dist(p, needle) < MIN_GAP_FROM_NEEDLE:
			continue
		var ok := true
		for s in spots:
			if angle_dist(p, s["pos"]) < (size + float(s["size"])) / 2.0 + 4.0:
				ok = false
				break
		if ok:
			return p
	return fposmod(needle + 180.0, 360.0)


## Advance the simulation (separate from _process so tests can drive it).
func step(delta: float) -> void:
	if _done:
		return
	needle = fposmod(needle + speed * direction * delta, 360.0)
	for s in spots:
		if s["move"] != 0.0:
			s["pos"] = fposmod(s["pos"] + s["move"] * delta, 360.0)
		if s["vanish"] > 0.0 and started:
			s["alpha"] -= s["vanish"] * delta
			if s["alpha"] <= 0.0:
				s["alpha"] = 1.0
				s["pos"] = free_position(s["size"])
	if started:
		progress -= decay * delta
	_check_end()


func strike() -> void:
	if _done:
		return
	started = true
	var hit: Dictionary = {}
	for s in spots:
		if angle_dist(needle, s["pos"]) <= float(s["size"]) / 2.0:
			hit = s
			break
	if hit.is_empty():
		misses += 1
		progress -= penalty
		_shake = 8.0
		_say("Miss!")
		for s in spots:
			s["alpha"] = 1.0  # like Starcatcher: a miss refreshes fading slots
	else:
		hits += 1
		_burst(hit["pos"], hit["color"])
		if hit["treasure"]:
			treasure += hit["reward"]
			_say("Sparkle!")
			if treasure >= TREASURE_GOAL:
				spots.erase(hit)
				_say("Flawless gem! +1 quality")
		else:
			progress += hit["reward"]
			_say("Thin hit!" if hit["type"] == "thin" else "Hit!")
		if hit["flip"]:
			direction = -direction
		hit["alpha"] = 1.0
		hit["pos"] = free_position(hit["size"])
	_check_end()


func _check_end() -> void:
	if _done:
		return
	if progress >= hp:
		_finish(true)
	elif progress < 0.0:
		_finish(false)


func _finish(success: bool) -> void:
	_done = true
	finished.emit(result_quality(success, misses, treasure >= TREASURE_GOAL))


## 0 misses -> Fine, a few -> Common, many or a botch -> Crude.
## A completed treasure meter bumps it one tier (perfect + treasure = Masterwork).
static func result_quality(success: bool, miss_count: int, treasure_done: bool) -> int:
	var q := 0
	if success:
		q = 2 if miss_count == 0 else (1 if miss_count <= 3 else 0)
	if treasure_done:
		q += 1
	return mini(q, 3)


## Walking away mid-craft counts as a botch.
func force_finish() -> void:
	if not _done:
		_finish(false)


# --- Frame loop, input & drawing ----------------------------------------------

func _process(delta: float) -> void:
	step(delta)
	_shake = maxf(0.0, _shake - 40.0 * delta)
	_flash_t -= delta
	for p in _particles:
		p["pos"] += p["vel"] * delta
		p["vel"] *= 0.9
		p["life"] -= delta
	_particles = _particles.filter(func(p): return p["life"] > 0.0)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if _done or not is_visible_in_tree():
		return
	if event.is_action_pressed("strike") and not event.is_echo():
		get_viewport().set_input_as_handled()
		strike()


func _say(text: String) -> void:
	_flash = text
	_flash_t = 0.8


## Offset from the ring's center to a point at `deg` degrees, `r` pixels out.
static func _ring_offset(deg: float, r: float) -> Vector2:
	var rad := deg_to_rad(deg - 90.0)
	return Vector2(cos(rad), sin(rad)) * r


func _center() -> Vector2:
	var c := Vector2(size.x / 2.0, 175.0)
	if _shake > 0.0:
		c += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
	return c


func _burst(deg: float, color: Color) -> void:
	var origin := _ring_offset(deg, RADIUS)
	for i in 24:
		var dir := Vector2.from_angle(randf() * TAU)
		_particles.append({ "pos": origin, "vel": dir * randf_range(60, 220), "life": randf_range(0.3, 0.7), "color": color })


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var c := _center()
	draw_string(font, Vector2(0, 20), "Hits %d   Misses %d   -   press SPACE / E / click when the needle crosses a gem slot" % [hits, misses],
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 17, Color("e8e2d6"))

	# Ring + slots.
	draw_arc(c, RADIUS, 0, TAU, 96, Color("2a2420"), RING_W, true)
	draw_arc(c, RADIUS + RING_W / 2.0 + 2, 0, TAU, 96, Color("c8862f", 0.5), 2.0, true)
	for s in spots:
		var a := deg_to_rad(float(s["pos"]) - 90.0)
		var half := deg_to_rad(float(s["size"]) / 2.0)
		var col: Color = s["color"]
		col.a = clampf(s["alpha"], 0.15, 1.0)
		draw_arc(c, RADIUS, a - half, a + half, 16, col, RING_W, true)

	# Needle.
	draw_line(c, c + _ring_offset(needle, RADIUS + 16), Color.WHITE, 4.0, true)
	draw_circle(c, 9, Color("c8862f"))
	draw_circle(c, 5, Color("ffe08a"))

	for p in _particles:
		var pc: Color = p["color"]
		pc.a = clampf(p["life"] * 2.0, 0.0, 1.0)
		draw_circle(c + p["pos"], 3.0, pc)

	# Progress bar (left) and treasure meter (right).
	var bar_h := 220.0
	var top := c.y - bar_h / 2.0
	var left_x := c.x - RADIUS - 90
	var ratio := clampf(progress / hp, 0.0, 1.0)
	draw_rect(Rect2(left_x, top, 22, bar_h), Color("2a2420"))
	var fill := Color("e06c6c").lerp(Color("8fd18f"), ratio)
	draw_rect(Rect2(left_x, top + bar_h * (1.0 - ratio), 22, bar_h * ratio), fill)
	draw_rect(Rect2(left_x, top, 22, bar_h), Color("c8862f"), false, 2.0)
	draw_string(font, Vector2(left_x - 30, top + bar_h + 22), "Progress", HORIZONTAL_ALIGNMENT_CENTER, 82, 14, Color("b8b0a0"))
	if has_treasure:
		var tx := c.x + RADIUS + 68
		var tr := clampf(treasure / TREASURE_GOAL, 0.0, 1.0)
		draw_rect(Rect2(tx, top, 22, bar_h), Color("2a2420"))
		draw_rect(Rect2(tx, top + bar_h * (1.0 - tr), 22, bar_h * tr), Color("6fe3a1"))
		draw_rect(Rect2(tx, top, 22, bar_h), Color("6fe3a1") if tr >= 1.0 else Color("c8862f"), false, 2.0)
		draw_string(font, Vector2(tx - 30, top + bar_h + 22), "Flawless", HORIZONTAL_ALIGNMENT_CENTER, 82, 14, Color("6fe3a1"))

	if _flash_t > 0.0:
		var fc := Color("ffe08a")
		fc.a = clampf(_flash_t * 2.0, 0.0, 1.0)
		draw_string(font, Vector2(0, c.y + RADIUS + 52), _flash, HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, fc)
