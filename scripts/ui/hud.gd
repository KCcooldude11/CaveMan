extends Control
## Always-on overlay: clock, gold, renown, crosshair, interaction prompt,
## a goal hint, and a feed of recent events.

const FEED_SECONDS := 7.0

var player: Node
var _status: RichTextLabel
var _prompt: Label
var _hint: Label
var _feed: VBoxContainer
var _banner: Label
var _banner_sub: Label
var _banner_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_anchor(_status, Vector2(0, 0), Rect2(16, 12, 760, 110))
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.add_theme_font_size_override("normal_font_size", 20)
	_status.add_theme_constant_override("outline_size", 6)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(_status)

	_prompt = _make_label(22)
	_anchor(_prompt, Vector2(0.5, 1), Rect2(-400, -110, 800, 40))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_hint = _make_label(17, Color("ffe9a8"))
	_anchor(_hint, Vector2(0, 1), Rect2(16, -48, 1000, 36))

	_feed = VBoxContainer.new()
	_anchor(_feed, Vector2(1, 0), Rect2(-520, 12, 500, 300))
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed)

	_banner = _make_label(40, Color("ffc94a"))
	_anchor(_banner, Vector2(0.5, 0.3), Rect2(-600, -40, 1200, 60))
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub = _make_label(22, Color("ffe9a8"))
	_anchor(_banner_sub, Vector2(0.5, 0.3), Rect2(-600, 22, 1200, 40))
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = false
	_banner_sub.visible = false
	EventBus.celebrate.connect(_on_celebrate)

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
	_status.text += "   [color=#9fd8ff]Prosperity %d[/color]" % Village.prosperity
	var tonight := Village.events_on(GameState.day)
	if not tonight.is_empty():
		var e: Dictionary = tonight[0]
		_status.text += "\n[color=#e0b06c]Tonight: %s in %s[/color]%s" % [
			DataDB.enemies[e["enemy"]]["name"], DataDB.dungeon(e["dungeon"])["name"],
			"  [color=#b8b0a0](+%d more on the notice board)[/color]" % (tonight.size() - 1) if tonight.size() > 1 else ""]


func _on_celebrate(title: String, sub: String) -> void:
	_banner.text = title
	_banner_sub.text = sub
	_banner_t = 4.0


func _process(delta: float) -> void:
	_banner_t -= delta
	_banner.visible = _banner_t > 0.0
	_banner_sub.visible = _banner_t > 0.0
	if _banner_t > 0.0:
		var a := clampf(_banner_t, 0.0, 1.0)
		_banner.modulate.a = a
		_banner_sub.modulate.a = a
		_banner.scale = Vector2.ONE * (1.0 + maxf(0.0, _banner_t - 3.7))
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
	if not Happenings.pending.is_empty():
		return "%d decision(s) are waiting for you - press B for the morning briefing." % Happenings.pending.size()
	if GameState.items.is_empty():
		for id in DataDB.recipes:
			if GameState.is_recipe_unlocked(id) and GameState.station_level(DataDB.recipes[id]["station"]) > 0 \
					and GameState.has_materials(DataDB.recipes[id]["inputs"]):
				return "Goal: craft something at the Forge or Workbench (walk up to it and press E)."
		return "Goal: buy materials at the Supply Order Board (left wall)."
	if TimeManager.is_shop_open():
		return "Goal: serve adventurers at the counter. Gear you sell earns renown when they win."
	if TimeManager.can_sleep():
		return "Goal: sleep in your bed to see how your adventurers fared tonight."
	return "Goal: the shop opens at 08:00. Craft stock while you wait."
