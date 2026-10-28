extends VBoxContainer
## The crafting skill-check. A marker sweeps across a bar; press Space / E /
## click when it's in the gold zone. Three strikes decide the item's quality.
## Station upgrades widen the zone, harder recipes make the marker faster.

signal finished(quality: int)

const STRIKES := 3
const BAR_W := 640.0
const BAR_H := 36.0

var zone_width := 0.18
var speed := 0.9            # bar-widths per second
var _pos := 0.0
var _dir := 1.0
var _zone_start := 0.4
var _strike := 0
var _score := 0
var _done := false

var _bar: ColorRect
var _zone: ColorRect
var _perfect: ColorRect
var _needle: ColorRect
var _info: Label


func configure(station_level: int, recipe_power: int) -> void:
	zone_width = 0.14 + 0.05 * (station_level - 1)
	speed = 0.8 + recipe_power / 30.0


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 18)
	add_child(_info)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(BAR_W, BAR_H)
	add_child(holder)
	_bar = _rect(holder, Color("2a2420"), Vector2.ZERO, Vector2(BAR_W, BAR_H))
	_zone = _rect(holder, Color("c8862f"), Vector2.ZERO, Vector2(10, BAR_H))
	_perfect = _rect(holder, Color("ffe08a"), Vector2.ZERO, Vector2(4, BAR_H))
	_needle = _rect(holder, Color.WHITE, Vector2.ZERO, Vector2(5, BAR_H + 12))
	_needle.position.y = -6
	_new_zone()
	_update_info("")


func _rect(parent: Control, color: Color, pos: Vector2, size: Vector2) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.position = pos
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _new_zone() -> void:
	_zone_start = randf_range(0.05, 0.95 - zone_width)
	_zone.position.x = _zone_start * BAR_W
	_zone.size.x = zone_width * BAR_W
	var pw := zone_width * 0.3
	_perfect.position.x = (_zone_start + (zone_width - pw) / 2.0) * BAR_W
	_perfect.size.x = pw * BAR_W


func _process(delta: float) -> void:
	if _done:
		return
	_pos += _dir * speed * delta
	if _pos > 1.0:
		_pos = 1.0
		_dir = -1.0
	elif _pos < 0.0:
		_pos = 0.0
		_dir = 1.0
	_needle.position.x = _pos * BAR_W - 2.0


func _input(event: InputEvent) -> void:
	if _done or not is_visible_in_tree():
		return
	if event.is_action_pressed("strike"):
		get_viewport().set_input_as_handled()
		strike()


func strike() -> void:
	var center := _zone_start + zone_width / 2.0
	var off := absf(_pos - center)
	var result := "Miss!"
	if off <= zone_width * 0.15:
		_score += 2
		result = "PERFECT!"
	elif off <= zone_width / 2.0:
		_score += 1
		result = "Good hit."
	_strike += 1
	if _strike >= STRIKES:
		_done = true
		_update_info(result)
		finished.emit(score_to_quality(_score))
	else:
		speed *= 1.1
		_new_zone()
		_update_info(result)


func _update_info(last: String) -> void:
	_info.text = "Strike %d / %d   -   press SPACE / E / click in the gold zone.   %s" % [min(_strike + 1, STRIKES), STRIKES, last]


static func score_to_quality(score: int) -> int:
	if score >= 6:
		return 3
	if score >= 4:
		return 2
	if score >= 2:
		return 1
	return 0


## Called if the player walks away mid-craft: remaining strikes count as misses.
func force_finish() -> void:
	if _done:
		return
	_done = true
	finished.emit(score_to_quality(_score))
