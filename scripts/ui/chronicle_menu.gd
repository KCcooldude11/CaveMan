extends BaseMenu
## The Village Chronicle (C): your legends and everything that happened.


func _init() -> void:
	super("Village Chronicle")


func build() -> void:
	add_heading("Hall of Legends")
	if GameState.legends.is_empty():
		add_label("No legends yet. A Masterwork with a special property might become one.", 15, Color("b8b0a0"))
	for id in GameState.legends:
		var l: Dictionary = GameState.legends[id]
		var where := ""
		match str(l["status"]):
			"shelf": where = "on your shelf"
			"wielded": where = "carried by %s" % l["holder_name"]
			"lost": where = "[color=#e06c6c]lost in the %s[/color]" % l["location"]
			_: where = str(l["status"])
		add_rich("[color=#ffc94a][b]%s[/b][/color]  [color=#b8b0a0]%s - %s - %d victories[/color]\n    [i]%s[/i]" % [
			l["name"], l["base"], where, int(l["kills"]), "  ".join(l["history"].slice(maxi(0, l["history"].size() - 3)))])
	add_heading("Chronicle")
	var entries: Array = Chronicle.entries.duplicate()
	entries.reverse()
	if entries.is_empty():
		add_label("Nothing has happened yet. Give it time.", 15, Color("b8b0a0"))
	for e in entries.slice(0, 120):
		add_rich(Chronicle.bbcode(e))
