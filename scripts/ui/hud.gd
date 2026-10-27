extends Control
## Always-on overlay: clock, gold, renown, crosshair, interaction prompt,
## a goal hint, and a feed of recent events.

const FEED_SECONDS := 7.0

var player: Node
var _status: RichTextLabel
var _prompt: Label
var _hint: Label
var _feed: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_anchor(_status, Vector2(0, 0), Rect2(16, 12, 600, 80))
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.add_theme_font_size_override("normal_font_size", 20)
	_status.add_theme_constant_override("outline_size", 6)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(_status)

	var cross := ColorRect.new()
	cross.color = Color(1, 1, 1, 0.85)
	cross.size = Vector2(6, 6)
	_anchor(cross, Vector2(0.5, 0.5), Rect2(-3, -3, 6, 6))
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cross)

	_prompt = _make_label(22)
	_anchor(_prompt, Vector2(0.5, 0.5), Rect2(-400, 24, 800, 40))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_hint = _make_label(17, Color("ffe9a8"))
	_anchor(_hint, Vector2(0, 1), Rect2(16, -48, 1000, 36))

	_feed = VBoxContainer.new()
	_anchor(_feed, Vector2(1, 0), Rect2(-520, 12, 500, 300))
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed)

	EventBus.notify.connect(_on_notify)
	for s in [EventBus.gold_changed, EventBus.renown_changed, EventBus.time_changed]:
		s.connect(func(_v): _refresh_status())
	EventBus.day_started.connect(func(_d): _refresh_status())
	_refresh_status()


## Pins `c` to a point of the screen (0,0 = top-left, 1,1 = bottom-right)
## with `rect` as the offset/size from that point.
static func _anchor(c: Control, at: Vector2, rect: Rect2) -> void:
	c.anchor_left = at.x
	c.anchor_right = at.x
	c.anchor_top = at.y
	c.anchor_bottom = at.y
	c.offset_left = rect.position.x
	c.offset_top = rect.position.y
	c.offset_right = rect.position.x + rect.size.x
	c.offset_bottom = rect.position.y + rect.size.y


func _make_label(size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _refresh_status() -> void:
	var open := "[color=#8fd18f]OPEN[/color]" if TimeManager.is_shop_open() else "[color=#e06c6c]CLOSED[/color]"
	var tier := DataDB.tier_for_renown(GameState.renown)
	_status.text = "Day %d  -  %s  -  Shop %s\n[color=#ffd27a]%dg[/color]   Renown %d  [color=#b8b0a0](%s)[/color]" % [
		GameState.day, TimeManager.time_string(), open, GameState.gold, GameState.renown, tier["name"]]


func _process(delta: float) -> void:
	for l in _feed.get_children():
		l.set_meta("t", float(l.get_meta("t")) - delta)
		var t: float = l.get_meta("t")
		l.modulate.a = clampf(t, 0.0, 1.0)
		if t <= 0.0:
			l.queue_free()
	if player and player.input_enabled:
		var target: Node = player.get_target()
		_prompt.text = target.get_prompt() if target else ""
	else:
		_prompt.text = ""
	_hint.text = _goal_hint()


func _on_notify(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 500
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.set_meta("t", FEED_SECONDS)
	_feed.add_child(l)
	if _feed.get_child_count() > 6:
		_feed.get_child(0).queue_free()


## A light-touch tutorial: always tells a new player what to do next.
func _goal_hint() -> String:
	if GameState.items.is_empty():
		for id in DataDB.recipes:
			if GameState.is_recipe_unlocked(id) and GameState.station_level(DataDB.recipes[id]["station"]) > 0 \
					and GameState.has_materials(DataDB.recipes[id]["inputs"]):
				return "Goal: craft something at the Forge or Workbench (look at it and press E)."
		return "Goal: buy materials at the Supply Order Board (left wall)."
	if TimeManager.is_shop_open():
		return "Goal: serve adventurers at the counter. Gear you sell earns renown when they win."
	if TimeManager.can_sleep():
		return "Goal: sleep in your bed to see how your adventurers fared tonight."
	return "Goal: the shop opens at 08:00. Craft stock while you wait."
