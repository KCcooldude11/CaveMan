extends Node
## The day clock. A day runs 06:00 -> 24:00. The shop is open 08:00 - 20:00.
## Time pauses while a menu is open (change PAUSE_IN_MENUS if you want
## Schedule-1 style "the world keeps going" pressure).

const DAY_START := 6 * 60
const SHOP_OPEN := 8 * 60
const SHOP_CLOSE := 20 * 60
const SLEEP_ALLOWED := 18 * 60
const DAY_END := 24 * 60
const PAUSE_IN_MENUS := true

## Game minutes per real second. 3.0 => a full day is 6 real minutes.
@export var minutes_per_second: float = 3.0

var minutes: float = DAY_START
var running: bool = false
var _menus_open: int = 0
var _last_emitted: int = -1
var _shop_open: bool = false


func _ready() -> void:
	EventBus.menu_opened.connect(func(): _menus_open += 1)
	EventBus.menu_closed.connect(func(): _menus_open = max(0, _menus_open - 1))


func is_paused() -> bool:
	return not running or (PAUSE_IN_MENUS and _menus_open > 0)


## Game minutes that pass during `delta` real seconds (0 while paused).
func game_delta(delta: float) -> float:
	return 0.0 if is_paused() else delta * minutes_per_second


func _process(delta: float) -> void:
	if is_paused():
		return
	minutes += game_delta(delta)
	# Update shop hours first so listeners of time_changed see the right state.
	if not _shop_open and minutes >= SHOP_OPEN and minutes < SHOP_CLOSE:
		_shop_open = true
		EventBus.shop_opened.emit()
	elif _shop_open and minutes >= SHOP_CLOSE:
		_shop_open = false
		EventBus.shop_closed.emit()
	var whole := int(minutes)
	if whole != _last_emitted:
		_last_emitted = whole
		EventBus.time_changed.emit(whole)
	if minutes >= DAY_END:
		running = false
		EventBus.notify.emit("You collapse from exhaustion...")
		EventBus.sleep_requested.emit()


## Skip time forward (e.g. an hour spent gathering wood).
func advance(game_minutes: int) -> void:
	minutes = minf(minutes + game_minutes, DAY_END - 1)
	EventBus.notify.emit("%d minutes pass..." % game_minutes)


func start_day() -> void:
	minutes = DAY_START
	_last_emitted = -1
	_shop_open = false
	running = true
	EventBus.day_started.emit(GameState.day)


func is_shop_open() -> bool:
	return _shop_open


func can_sleep() -> bool:
	return minutes >= SLEEP_ALLOWED


func time_string() -> String:
	var m := int(minutes)
	return "%02d:%02d" % [(m / 60) % 24, m % 60]
