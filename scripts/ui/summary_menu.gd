extends BaseMenu
## The night report - the payoff moment of each day. Leads with what will be
## remembered (chronicle highlights), then every hero's night.

var _report: Dictionary
var _on_continue: Callable


func _init(report: Dictionary, on_continue: Callable) -> void:
	_report = report
	_on_continue = on_continue
	super("Night after Day %d" % int(report["day"]))


func build() -> void:
	var gain := int(_report["renown"])
	var col := "8fd18f" if gain >= 0 else "e06c6c"
	add_rich("[font_size=22]Renown [color=#%s]%+d[/color]   -   Total %d (%s)   -   Gold %dg[/font_size]" % [
		col, gain, GameState.renown, DataDB.tier_for_renown(GameState.renown)["name"], GameState.gold])
	add_rich("[color=#b8b0a0]Village prosperity %d   -   safety %d[/color]" % [Village.prosperity, Village.safety])
	if not _report["highlights"].is_empty():
		add_heading("Tonight will be remembered")
		for e in _report["highlights"]:
			add_rich(Chronicle.bbcode(e))
	add_heading("While you slept...")
	if _report["lines"].is_empty():
		add_label("No one went adventuring.")
	for l in _report["lines"]:
		add_rich("- " + l)
	add_label("Game saved.", 14, Color("b8b0a0"))
	content.add_child(button("Start Day %d" % (int(_report["day"]) + 1), close))


func close() -> void:
	super()
	_on_continue.call()
