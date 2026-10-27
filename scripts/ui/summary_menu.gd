extends BaseMenu
## The "night report" shown after sleeping - the payoff moment of each day.

var _day: int
var _lines: Array
var _renown: int
var _on_continue: Callable


func _init(day: int, lines: Array, renown_gain: int, on_continue: Callable) -> void:
	_day = day
	_lines = lines
	_renown = renown_gain
	_on_continue = on_continue
	super("Night after Day %d" % day)


func build() -> void:
	var col := "8fd18f" if _renown >= 0 else "e06c6c"
	add_rich("[font_size=22]Renown [color=#%s]%+d[/color]   -   Total %d (%s)   -   Gold %dg[/font_size]" % [
		col, _renown, GameState.renown, DataDB.tier_for_renown(GameState.renown)["name"], GameState.gold])
	add_heading("While you slept, the adventurers delved...")
	if _lines.is_empty():
		add_label("No one went adventuring.")
	for l in _lines:
		add_rich("- " + l)
	add_label("Game saved.", 14, Color("b8b0a0"))
	content.add_child(button("Start Day %d" % (_day + 1), close))


func close() -> void:
	super()
	_on_continue.call()
